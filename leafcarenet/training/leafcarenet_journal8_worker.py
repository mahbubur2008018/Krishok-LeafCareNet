
# ============================================================
# LEAFCARENET — KAGGLE ONE-CLICK FULL MODEL COMPARISON
# Dataset: /kaggle/input/datasets/mahbubur03078/leafdisease2
# GPU: exactly one visible T4 per worker process
#
# One run performs:
#   1) Minimal fresh-session path/GPU/model-count checks
#   2) 6 controlled model experiments
#   3) Accuracy / Macro-F1 / Weighted-F1 evaluation
#   4) Stage-1, Stage-2, true end-to-end evaluation
#   5) LeafCareNet ablation comparison
#   6) All required 300-DPI publication PNG figures
#   7) CSV/JSON/Markdown result tables
#   8) Best model checkpoints
#   9) Final ZIP archive in /kaggle/working
# ============================================================

import os
import sys
import re
import gc
import json
import math
import time
import random
import shutil
import hashlib
import platform
import subprocess
import warnings
from pathlib import Path
from collections import Counter, defaultdict

warnings.filterwarnings("ignore")

# Keep CPU libraries from spawning nested thread pools inside each DataLoader worker.
# The image pipeline is parallelized by DataLoader processes instead.
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("NUMEXPR_NUM_THREADS", "1")
os.environ.setdefault("VECLIB_MAXIMUM_THREADS", "1")


# ---------------------------
# 0. Install/import packages
# ---------------------------
def ensure_package(import_name, pip_name=None):
    try:
        __import__(import_name)
    except ImportError:
        pkg = pip_name or import_name
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", pkg]
        )

ensure_package("timm")
ensure_package("sklearn", "scikit-learn")
ensure_package("pandas")
ensure_package("PIL", "Pillow")
ensure_package("matplotlib")
ensure_package("tqdm")
ensure_package("scipy")

import numpy as np
import pandas as pd
from PIL import Image, ImageFile
import matplotlib.pyplot as plt

# Be robust to partially truncated internet-downloaded files that PIL can still decode.
ImageFile.LOAD_TRUNCATED_IMAGES = True

import torch
from torch import nn
from torch.utils.data import Dataset, DataLoader, WeightedRandomSampler

import timm
from timm.data import create_transform, resolve_model_data_config

from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    precision_recall_fscore_support,
    classification_report,
    confusion_matrix,
    matthews_corrcoef,
    cohen_kappa_score,
    f1_score,
)
from scipy.stats import binomtest

from tqdm.auto import tqdm




# ============================================================
# 1. CONFIGURATION
# ============================================================

KAGGLE_DATASET_ROOT = Path("/kaggle/input/datasets/mahbubur03078/leafdisease2")
DATA_ROOT = KAGGLE_DATASET_ROOT
# Compatibility aliases; no in-notebook cleaning/re-splitting is performed.
RAW_DATA_ROOT = KAGGLE_DATASET_ROOT
CLEAN_DATA_ROOT = KAGGLE_DATASET_ROOT
OUTPUT_ROOT = Path(os.environ["LEAFCARENET_OUTPUT_ROOT"])
FIG_ROOT = OUTPUT_ROOT / "figures_300dpi"
TABLE_ROOT = OUTPUT_ROOT / "tables"
CHECKPOINT_ROOT = OUTPUT_ROOT / "checkpoints"
PREDICTION_ROOT = OUTPUT_ROOT / "predictions"
AUDIT_ROOT = OUTPUT_ROOT / "dataset_audit"
LOG_ROOT = OUTPUT_ROOT / "logs"

for p in [
    OUTPUT_ROOT,
    FIG_ROOT,
    TABLE_ROOT,
    CHECKPOINT_ROOT,
    PREDICTION_ROOT,
    AUDIT_ROOT,
    LOG_ROOT,
]:
    p.mkdir(parents=True, exist_ok=True)

# Full console + tqdm log. Output remains visible in Kaggle and is also saved.
class TeeStream:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, data):
        for stream in self.streams:
            stream.write(data)
        return len(data)

    def flush(self):
        for stream in self.streams:
            stream.flush()

    def isatty(self):
        return False

    @property
    def encoding(self):
        return getattr(self.streams[0], "encoding", "utf-8")

_ORIGINAL_STDOUT = sys.stdout
_ORIGINAL_STDERR = sys.stderr
_LOG_FILE = open(
    LOG_ROOT / "training_run.log",
    "a",
    buffering=1,
    encoding="utf-8",
)
sys.stdout = TeeStream(_ORIGINAL_STDOUT, _LOG_FILE)
sys.stderr = TeeStream(_ORIGINAL_STDERR, _LOG_FILE)

RUN_STARTED_AT = time.strftime("%Y-%m-%d %H:%M:%S")
print("=" * 100)
print("FINAL JOURNAL RUN LOG STARTED:", RUN_STARTED_AT)
print("Log file:", LOG_ROOT / "training_run.log")
print("=" * 100)

SEED = 42
IMG_SIZE = 224
BATCH_SIZE = int(os.environ.get("LEAFCARENET_BATCH_SIZE", "256"))
EVAL_BATCH_SIZE = int(os.environ.get("LEAFCARENET_EVAL_BATCH_SIZE", "512"))

# Optional shared deterministic preprocessing cache.
# The cache stores spatially preprocessed 224x224 RGB tensors as uint8.
# Normalization is performed on the GPU, eliminating repeated JPEG decode,
# resize/crop, ToTensor, and CPU normalization every epoch.
_UINT8_CACHE_ENV = os.environ.get("LEAFCARENET_UINT8_CACHE_DIR", "").strip()
UINT8_CACHE_DIR = Path(_UINT8_CACHE_ENV) if _UINT8_CACHE_ENV else None
USE_PREPROCESSED_UINT8_CACHE = (
    UINT8_CACHE_DIR is not None
    and (UINT8_CACHE_DIR / "cache_meta.json").exists()
)

ACTIVE_INPUT_MEAN = None
ACTIVE_INPUT_STD = None
_GPU_NORM_MEAN = None
_GPU_NORM_STD = None

# Original LeafCareNet training protocol
MAX_EPOCHS = 100
PATIENCE = 5
MIN_DELTA = 1e-4
LR = 1e-3
WEIGHT_DECAY = 1e-4

CROP_LOSS_WEIGHT = 2.0
CROP_LABEL_SMOOTHING = 0.1
FLAT_LABEL_SMOOTHING = 0.1

CPU_COUNT = os.cpu_count() or 4

# Two independent single-GPU model processes run concurrently.
NUM_WORKERS = int(
    os.environ.get(
        "LEAFCARENET_NUM_WORKERS",
        str(max(1, min(4, CPU_COUNT // 2))),
    )
)
AUTO_TUNE_NUM_WORKERS = False
WORKER_TUNE_CANDIDATES = [NUM_WORKERS]
WORKER_TUNE_WARMUP_BATCHES = 0
WORKER_TUNE_TIMED_BATCHES = 0

PREFETCH_FACTOR = int(
    os.environ.get("LEAFCARENET_PREFETCH_FACTOR", "3")
)

TQDM_MININTERVAL = 2.0
USE_CHANNELS_LAST = True
USE_DIRECT_DP_CPU_SCATTER = False
USE_FUSED_ADAMW = True

# No decoded-RGB memmap in this parallel version.
USE_RGB_MEMMAP_CACHE = False
RGB_CACHE_MAX_GIB = 0.0
RGB_CACHE_REBUILD = False
USE_AMP = True
PRETRAINED = os.environ.get("LEAFCARENET_PREFLIGHT", "0") != "1"
BOOTSTRAP_REPEATS = 1000
FAIL_ON_EXACT_CROSS_SPLIT_DUPLICATES = True
LATENCY_WARMUP = 20
LATENCY_REPEATS = 100

# Uploaded dataset provenance / validation settings
PREBUILT_SOURCE_CLEAN_DATASET = True

# The Kaggle upload physically contains train-only offline augmented copies,
# but this final run intentionally excludes them from every training Dataset.
UPLOADED_OFFLINE_AUGMENTATION_PRESENT = True
USE_OFFLINE_AUGMENTED_FILES_FOR_TRAINING = False

# Restore the original LeafCareNet training-time augmentation protocol.
ONLINE_AUGMENTATION = False
OFFLINE_AUGMENTATION = False

SOURCE_SPLIT_RATIOS = {"train": 0.75, "val": 0.20, "test": 0.05}
EXTERNAL_NEAR_DUPLICATE_THRESHOLD = 4

# Physical uploaded dataset counts.
EXPECTED_UPLOADED_SPLIT_COUNTS = {"train": 68600, "val": 3660, "test": 916}
EXPECTED_UPLOADED_TRAIN_ORIGINALS = 13720
EXPECTED_UPLOADED_TRAIN_AUGMENTED = 54880
EXPECTED_UPLOADED_TOTAL_IMAGES = 73176

# Files actually used by the eight model experiments.
EXPECTED_MODEL_SPLIT_COUNTS = {"train": 13720, "val": 3660, "test": 916}
EXPECTED_MODEL_TOTAL_IMAGES = 18296


# Eight final journal models: four backbone-matched flat/hierarchical comparisons.
# The SAME LINEAR hierarchy is transferred across backbones for controlled analysis.
# The MobileNetV2 hierarchical instance is the proposed LeafCareNet.
# LeafCareNet therefore keeps the exact earlier architecture that produced the
# previous Hierarchical MobileNetV2 result: Linear crop router + linear crop-specific heads.
EXPERIMENTS = [
    ("01_flat_mobilenetv2", "flat", "mobilenetv2", "flat"),
    ("02_flat_efficientnet_b3", "flat", "efficientnet_b3", "flat"),
    ("03_flat_fasternet_m", "flat", "fasternet_m", "flat"),
    ("04_flat_deit_tiny", "flat", "deit_tiny", "flat"),

    ("05_leafcarenet", "hierarchical", "mobilenetv2", "linear"),
    ("06_hier_efficientnet_b3", "hierarchical", "efficientnet_b3", "linear"),
    ("07_hier_fasternet_m", "hierarchical", "fasternet_m", "linear"),
    ("08_hier_deit_tiny", "hierarchical", "deit_tiny", "linear"),
]

CROPS = ["potato", "rice", "tomato"]
SPLITS = ["train", "val", "test"]
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

BACKBONE_CANDIDATES = {
    "mobilenetv2": [
        "mobilenetv2_100.ra_in1k",
        "mobilenetv2_100",
    ],
    "efficientnet_b3": [
        "efficientnet_b3.ra2_in1k",
        "efficientnet_b3",
    ],
    "fasternet_m": [
        "fasternet_m.in1k",
        "fasternet_m",
    ],
    # Lightweight transformer baseline chosen for fast T4 training.
    "deit_tiny": [
        "deit_tiny_patch16_224.fb_in1k",
        "deit_tiny_patch16_224",
    ],
}




# ============================================================
# 2. REPRODUCIBILITY / GPU
# ============================================================

def seed_everything(seed=42):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)

    # Deterministic where practical; benchmark improves T4 throughput.
    torch.backends.cudnn.benchmark = True

seed_everything(SEED)


# Keep the main process lightweight; DataLoader worker processes own image preprocessing.
try:
    torch.set_num_threads(1)
except Exception:
    pass

try:
    torch.set_num_interop_threads(1)
except Exception:
    pass



# Execution-only CUDA optimizations.
torch.backends.cudnn.benchmark = True
torch.backends.cuda.matmul.allow_tf32 = True
torch.backends.cudnn.allow_tf32 = True

try:
    torch.set_float32_matmul_precision("high")
except Exception:
    pass

print("=" * 90)
print("LEAFCARENET FINAL JOURNAL ONE-CLICK COMPARISON")
print("=" * 90)
print("Python:", sys.version.split()[0])
print("PyTorch:", torch.__version__)
print("timm:", timm.__version__)
print("CUDA available:", torch.cuda.is_available())
print("GPU count:", torch.cuda.device_count())

if not torch.cuda.is_available():
    raise RuntimeError(
        "GPU is not enabled. Kaggle: Settings > Accelerator > GPU."
    )

for i in range(torch.cuda.device_count()):
    print(f"GPU {i}: {torch.cuda.get_device_name(i)}")

DEVICE = torch.device("cuda:0")
USE_MULTI_GPU = torch.cuda.device_count() > 1
torch.cuda.set_device(0)
print("Visible-GPU DataParallel enabled:", USE_MULTI_GPU)
print("Detected CPU logical cores:", CPU_COUNT)
print("Initial DataLoader workers:", NUM_WORKERS)
print("Worker autotune candidates:", WORKER_TUNE_CANDIDATES)
print("Prefetch factor:", PREFETCH_FACTOR)
print("Channels-last:", USE_CHANNELS_LAST)
print("Train batch size:", BATCH_SIZE)
print("Eval batch size:", EVAL_BATCH_SIZE)
print("Direct DP CPU scatter:", USE_DIRECT_DP_CPU_SCATTER and USE_MULTI_GPU)
print(
    "Preprocessed uint8 cache:",
    str(UINT8_CACHE_DIR) if USE_PREPROCESSED_UINT8_CACHE else "DISABLED",
)




if torch.cuda.device_count() != 1:
    raise RuntimeError(
        "Each parallel worker must see exactly one GPU. "
        f"Visible GPU count: {torch.cuda.device_count()}"
    )


# ============================================================
# 3. DATASET PATH AUTO-CHECK
# ============================================================

def has_expected_crop_structure(root):
    root = Path(root)

    return all(
        (root / f"{crop}_leaf").is_dir()
        for crop in CROPS
    )


def locate_dataset():
    """
    Kaggle datasets sometimes preserve the uploaded top-level folder.
    Therefore the configured leafdisease2 root is searched recursively
    for the directory that directly contains potato_leaf/rice_leaf/tomato_leaf.
    """
    global DATA_ROOT, RAW_DATA_ROOT, CLEAN_DATA_ROOT

    configured = Path(KAGGLE_DATASET_ROOT)

    if not configured.exists():
        raise FileNotFoundError(
            f"Configured Kaggle dataset does not exist: {configured}"
        )

    if has_expected_crop_structure(configured):
        resolved = configured
    else:
        candidates = []

        for potato_dir in configured.rglob("potato_leaf"):
            parent = potato_dir.parent

            if has_expected_crop_structure(parent):
                candidates.append(parent)

        # Fallback search through all Kaggle inputs if the dataset slug changes.
        if not candidates:
            base = Path("/kaggle/input")

            for potato_dir in base.rglob("potato_leaf"):
                parent = potato_dir.parent

                if has_expected_crop_structure(parent):
                    candidates.append(parent)

        if not candidates:
            raise FileNotFoundError(
                "Could not locate a directory containing potato_leaf, "
                "rice_leaf and tomato_leaf."
            )

        # Prefer candidates physically inside leafdisease2.
        inside_configured = [
            p for p in candidates
            if configured == p or configured in p.parents
        ]

        resolved = (
            sorted(inside_configured, key=lambda p: len(p.parts))[0]
            if inside_configured
            else sorted(candidates, key=lambda p: len(p.parts))[0]
        )

    DATA_ROOT = resolved
    RAW_DATA_ROOT = resolved
    CLEAN_DATA_ROOT = resolved

    print("Configured Kaggle dataset root:", configured)
    print("Resolved training dataset root:", DATA_ROOT)

    return DATA_ROOT


locate_dataset()

# ------------------------------------------------------------
# Final experiment file-selection rule
# ------------------------------------------------------------
def is_offline_augmented_filename(name):
    return "__aug_" in Path(name).stem.lower()


def model_uses_path(path, split):
    """
    The Kaggle upload contains offline-generated __aug_* files in train.
    They are excluded from the final model Dataset objects.
    Validation/test are used as prepared.
    """
    path = Path(path)

    if split == "train" and is_offline_augmented_filename(path.name):
        return False

    return True



# ============================================================
# 4. DIRECT COMPRESSED-IMAGE LOADING — NO FULL RGB MEMMAP
# ============================================================
#
# Why:
#   The previous full-resolution RGB cache occupied ~11+ GiB and caused heavy
#   random memory-mapped I/O. This V2 loader reads the original compressed
#   JPG/PNG/WebP files directly and lets persistent DataLoader workers perform
#   decode + online augmentation in parallel.
#
# Methodology:
#   image file -> PIL RGB decode -> SAME online train transform
#   validation/test -> deterministic eval transform
# ============================================================

RGB_CACHE_DIR = OUTPUT_ROOT / "rgb_decode_cache"
RGB_CACHE_BIN = RGB_CACHE_DIR / "disabled.bin"
RGB_CACHE_INDEX_CSV = RGB_CACHE_DIR / "disabled.csv"
RGB_CACHE_INDEX = {}
RGB_CACHE_ACTIVE = False

# Free only legacy execution-cache folders from earlier notebook versions.
# Checkpoints/tables/results are NOT removed here.
LEGACY_CACHE_DIRS = [
    Path(
        "/kaggle/working/"
        "leafcarenet_final_original_onlineaug_journal_run/"
        "rgb_decode_cache"
    ),
]

for legacy_cache_dir in LEGACY_CACHE_DIRS:
    if legacy_cache_dir.exists():
        try:
            shutil.rmtree(legacy_cache_dir)
            print(
                "Removed legacy RGB execution cache:",
                legacy_cache_dir,
            )
        except Exception as exc:
            print(
                "Could not remove legacy RGB cache:",
                legacy_cache_dir,
                exc,
            )


def load_rgb_image_fast(path):
    """
    Direct compressed-file loader.

    The `with` block closes the underlying file immediately after RGB
    conversion, avoiding accumulation of open file handles in persistent
    DataLoader workers.
    """
    with Image.open(path) as img:
        return img.convert("RGB")


print("RGB memmap cache: DISABLED")
print("Image source: original compressed JPG/PNG/WebP files")


# ============================================================
# 5. BACKBONE HELPERS / TRANSFORMS
# ============================================================

def select_backbone(key):
    # include_tags=True is important: otherwise timm.list_models() can hide
    # tagged pretrained names such as "fasternet_m.in1k" and silently fall
    # back to the untagged alias.
    try:
        available = set(
            timm.list_models(
                include_tags=True
            )
        )
    except TypeError:
        available = set(
            timm.list_models()
        )

    for candidate in BACKBONE_CANDIDATES[key]:
        if candidate in available:
            return candidate

    if key == "mobilenetv2":
        matches = timm.list_models("*mobilenetv2*")
    elif key == "efficientnet_b3":
        matches = timm.list_models("*efficientnet_b3*")
    elif key == "fasternet_m":
        matches = timm.list_models("*fasternet_m*")
    elif key == "deit_tiny":
        matches = timm.list_models("*deit_tiny_patch16_224*")
    else:
        matches = []

    if not matches:
        raise RuntimeError(
            f"No timm model found for {key}"
        )

    return matches[0]


RESOLVED_BACKBONES = {
    key: select_backbone(key) for key in BACKBONE_CANDIDATES
}

print("\nResolved timm backbones:")
for k, v in RESOLVED_BACKBONES.items():
    print(f"  {k}: {v}")


class FasterNetPooledFeatures(nn.Module):
    """
    Exact LeafCareNet FasterNet feature interface:

        FasterNet.forward_features(x)
            -> global spatial average pooling
            -> 1152-D feature vector for FasterNet-M

    This deliberately bypasses timm FasterNet's forward_head / pre-logits
    expansion. In timm 1.0.26 the unwrapped model(x) path produced 1280-D
    pre-logits while model.num_features reported the backbone feature width
    used by LeafCareNet. That mismatch caused:
        mat1: [B, 1280]
        head: [1152, ...]
    """

    def __init__(
        self,
        model,
        feat_dim,
    ):
        super().__init__()

        self.model = model
        self.num_features = int(
            feat_dim
        )

        # The task-specific FasterNet experiments use raw backbone features.
        # Remove any unused timm classification/pre-logits head parameters
        # when that module is exposed as `head`.
        if hasattr(
            self.model,
            "head",
        ):
            self.model.head = nn.Identity()

    def forward(
        self,
        x,
    ):
        features = (
            self.model
            .forward_features(
                x
            )
        )

        if features.ndim == 4:
            # Normal FasterNet output is NCHW: [B, C, H, W].
            if (
                features.shape[1]
                == self.num_features
            ):
                features = (
                    features
                    .mean(
                        dim=(2, 3)
                    )
                )

            # Defensive NHWC fallback.
            elif (
                features.shape[-1]
                == self.num_features
            ):
                features = (
                    features
                    .mean(
                        dim=(1, 2)
                    )
                )

            else:
                raise RuntimeError(
                    "Unexpected FasterNet forward_features shape: "
                    f"{tuple(features.shape)}; expected feature width "
                    f"{self.num_features}."
                )

        elif features.ndim == 3:
            # Defensive token-sequence fallback.
            features = (
                features
                .mean(
                    dim=1
                )
            )

        if (
            features.ndim != 2
            or features.shape[1]
            != self.num_features
        ):
            raise RuntimeError(
                "FasterNet pooled feature mismatch: "
                f"got {tuple(features.shape)}, "
                f"expected [batch, {self.num_features}]."
            )

        return features


def create_backbone(backbone_key):
    name = RESOLVED_BACKBONES[backbone_key]

    try:
        model = timm.create_model(
            name,
            pretrained=PRETRAINED,
            num_classes=0,
            global_pool="avg",
        )
    except Exception as exc:
        raise RuntimeError(
            f"Could not load pretrained model '{name}'. "
            "For ImageNet pretrained weights, enable Internet in Kaggle. "
            f"Original error: {exc}"
        )

    feat_dim = int(
        model.num_features
    )

    if backbone_key == "fasternet_m":
        model = FasterNetPooledFeatures(
            model,
            feat_dim,
        )

        print(
            "FasterNet feature interface: "
            f"forward_features -> global mean -> {feat_dim}-D"
        )

    return model, feat_dim


def get_data_cfg(backbone_key):
    model, _ = create_backbone(backbone_key)

    # resolve_model_data_config can read through our wrapper's underlying
    # pretrained model config via the wrapped timm model.
    config_model = (
        model.model
        if isinstance(
            model,
            FasterNetPooledFeatures,
        )
        else model
    )

    cfg = resolve_model_data_config(
        config_model
    )

    del model
    gc.collect()
    torch.cuda.empty_cache()

    return cfg


def make_transforms(backbone_key):
    global ACTIVE_INPUT_MEAN
    global ACTIVE_INPUT_STD
    global _GPU_NORM_MEAN
    global _GPU_NORM_STD

    cfg = get_data_cfg(backbone_key)

    ACTIVE_INPUT_MEAN = tuple(float(x) for x in cfg["mean"])
    ACTIVE_INPUT_STD = tuple(float(x) for x in cfg["std"])
    _GPU_NORM_MEAN = None
    _GPU_NORM_STD = None

    # FINAL NO-AUGMENTATION PROTOCOL.
    # Train/val/test all receive deterministic resize/crop/normalization.
    train_tf = create_transform(
        input_size=(3, IMG_SIZE, IMG_SIZE),
        is_training=False,
        mean=cfg["mean"],
        std=cfg["std"],
        interpolation=cfg.get("interpolation", "bicubic"),
        crop_pct=cfg.get("crop_pct", 0.875),
    )

    eval_tf = create_transform(
        input_size=(3, IMG_SIZE, IMG_SIZE),
        is_training=False,
        mean=cfg["mean"],
        std=cfg["std"],
        interpolation=cfg.get("interpolation", "bicubic"),
        crop_pct=cfg.get("crop_pct", 0.875),
    )

    return train_tf, eval_tf


# ============================================================
# 6. DATASETS
# ============================================================

def _ordered_sample_hash(samples):
    """
    Hash only stable dataset-relative identifiers and class indices.
    This prevents a cache built in one Kaggle mount path from being accepted
    with a different ordering or split.
    """
    h = hashlib.sha256()

    for (
        path,
        crop_idx,
        disease_idx,
        global_idx,
        crop,
        cls,
    ) in samples:
        try:
            rel = Path(path).resolve().relative_to(
                DATA_ROOT.resolve()
            ).as_posix()
        except Exception:
            rel = "/".join(
                Path(path).as_posix().split("/")[-4:]
            )

        line = (
            f"{rel}|{crop_idx}|{disease_idx}|"
            f"{global_idx}|{crop}|{cls}\n"
        )

        h.update(
            line.encode("utf-8")
        )

    return h.hexdigest()


class HierarchicalLeafDataset(Dataset):
    def __init__(self, root, split, transform=None):
        self.root = Path(root)
        self.split = split
        self.transform = transform
        self._uint8_cache = None

        self.crop_to_idx = {crop: i for i, crop in enumerate(CROPS)}

        self.crop_classes = {}
        self.disease_to_idx = {}

        self.global_classes = []
        self.global_to_idx = {}

        self.samples = []

        # Discover class names alphabetically, consistent with ImageFolder.
        for crop in CROPS:
            split_dir = self.root / f"{crop}_leaf" / split

            classes = sorted(
                [p.name for p in split_dir.iterdir() if p.is_dir()]
            )

            self.crop_classes[crop] = classes
            self.disease_to_idx[crop] = {
                cls: idx for idx, cls in enumerate(classes)
            }

        for crop in CROPS:
            for cls in self.crop_classes[crop]:
                self.global_to_idx[(crop, cls)] = len(
                    self.global_classes
                )
                self.global_classes.append(f"{crop}::{cls}")

        for crop in CROPS:
            crop_idx = self.crop_to_idx[crop]
            split_dir = self.root / f"{crop}_leaf" / split

            for cls in self.crop_classes[crop]:
                disease_idx = self.disease_to_idx[crop][cls]
                global_idx = self.global_to_idx[(crop, cls)]
                cls_dir = split_dir / cls

                for f in sorted(cls_dir.rglob("*")):
                    if (
                        f.is_file()
                        and f.suffix.lower() in IMAGE_EXTS
                        and model_uses_path(f, split)
                    ):
                        self.samples.append(
                            (
                                str(f),
                                crop_idx,
                                disease_idx,
                                global_idx,
                                crop,
                                cls,
                            )
                        )

        # Optional deterministic spatial-preprocessing cache.
        if USE_PREPROCESSED_UINT8_CACHE:
            meta_path = UINT8_CACHE_DIR / "cache_meta.json"
            image_path = UINT8_CACHE_DIR / f"{split}_images.npy"

            if not image_path.exists():
                raise FileNotFoundError(
                    f"Preprocessed cache file missing: {image_path}"
                )

            meta = json.loads(
                meta_path.read_text(
                    encoding="utf-8"
                )
            )

            split_meta = meta.get(
                "splits",
                {}
            ).get(
                split
            )

            if split_meta is None:
                raise RuntimeError(
                    f"Cache metadata has no split '{split}'."
                )

            expected_hash = _ordered_sample_hash(
                self.samples
            )

            if int(split_meta.get("count", -1)) != len(self.samples):
                raise RuntimeError(
                    f"Cache count mismatch for {split}: "
                    f"cache={split_meta.get('count')} "
                    f"dataset={len(self.samples)}"
                )

            if split_meta.get("sample_hash") != expected_hash:
                raise RuntimeError(
                    f"Cache sample/order hash mismatch for {split}."
                )

            self._uint8_cache = np.load(
                image_path,
                mmap_mode="r",
            )

            expected_shape = (
                len(self.samples),
                3,
                IMG_SIZE,
                IMG_SIZE,
            )

            if tuple(self._uint8_cache.shape) != expected_shape:
                raise RuntimeError(
                    f"Cache tensor shape mismatch for {split}: "
                    f"{self._uint8_cache.shape} != {expected_shape}"
                )

            if self._uint8_cache.dtype != np.uint8:
                raise RuntimeError(
                    f"Cache dtype must be uint8, got {self._uint8_cache.dtype}"
                )

            print(
                f"FAST CACHE ACTIVE [{split}]: "
                f"{len(self.samples)} images | "
                f"{image_path.name}"
            )

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        (
            path,
            crop_idx,
            disease_idx,
            global_idx,
            crop,
            cls,
        ) = self.samples[idx]

        if self._uint8_cache is not None:
            # Copy one ~150 KB uint8 sample from the memory map.
            # This is dramatically cheaper than JPEG decode + resize/crop.
            image = torch.from_numpy(
                np.array(
                    self._uint8_cache[idx],
                    copy=True,
                )
            )

        else:
            image = load_rgb_image_fast(path)

            if self.transform:
                image = self.transform(image)

        return image, crop_idx, disease_idx, global_idx


class FlatLeafDataset(Dataset):
    def __init__(self, hierarchical_dataset):
        self.base = hierarchical_dataset
        self.samples = hierarchical_dataset.samples
        self.global_classes = hierarchical_dataset.global_classes

    def __len__(self):
        return len(self.base)

    def __getitem__(self, idx):
        image, _, _, global_idx = self.base[idx]
        return image, global_idx




# ============================================================
# 7. BALANCED SAMPLERS
# ============================================================

def build_hierarchical_balanced_sampler(dataset):
    counts = Counter()

    for _, crop_idx, disease_idx, _, _, _ in dataset.samples:
        counts[(crop_idx, disease_idx)] += 1

    weights = []

    for _, crop_idx, disease_idx, _, _, _ in dataset.samples:
        # Equivalent proportional form of:
        # (1 / n_crops) * (1 / disease_count_within_crop)
        w = (1.0 / len(CROPS)) * (
            1.0 / counts[(crop_idx, disease_idx)]
        )
        weights.append(w)

    return WeightedRandomSampler(
        torch.DoubleTensor(weights),
        num_samples=len(weights),
        replacement=True,
    )


def build_flat_balanced_sampler(dataset):
    counts = Counter(
        global_idx
        for _, _, _, global_idx, _, _ in dataset.base.samples
    )

    weights = [
        1.0 / counts[global_idx]
        for _, _, _, global_idx, _, _ in dataset.base.samples
    ]

    return WeightedRandomSampler(
        torch.DoubleTensor(weights),
        num_samples=len(weights),
        replacement=True,
    )




# ============================================================
# 8. MODEL DEFINITIONS
# ============================================================

class SEGate(nn.Module):
    def __init__(self, dim, reduction=16):
        super().__init__()

        hidden = max(dim // reduction, 8)

        self.fc1 = nn.Linear(dim, hidden)
        self.fc2 = nn.Linear(hidden, dim)

    def forward(self, x):
        attn = torch.relu(self.fc1(x))
        attn = torch.sigmoid(self.fc2(attn))
        return x * attn


class LinearDiseaseHead(nn.Module):
    def __init__(self, dim, num_classes):
        super().__init__()
        self.fc = nn.Linear(dim, num_classes)

    def forward(self, x):
        return self.fc(x)


class JournalDiseaseHead(nn.Module):
    """
    Crop-specific disease head used in the final journal hierarchy:
        feature -> FC(256) -> ReLU -> Dropout(0.5) -> class logits
    """
    def __init__(self, dim, num_classes):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(dim, 256),
            nn.ReLU(inplace=True),
            nn.Dropout(0.50),
            nn.Linear(256, num_classes),
        )

    def forward(self, x):
        return self.net(x)


class JournalCropRouter(nn.Module):
    """
    Final LeafCareNet crop router matching the architecture figure:
        SE(r=8) -> FC(256) -> ReLU -> Dropout(0.5) -> 3 crop logits.

    Softmax is intentionally NOT inside the module because CrossEntropyLoss
    requires raw logits. Softmax is applied only at evaluation/inference.
    """
    def __init__(self, dim, n_crops=3, reduction=8):
        super().__init__()
        self.se = SEGate(dim, reduction=reduction)
        self.net = nn.Sequential(
            nn.Linear(dim, 256),
            nn.ReLU(inplace=True),
            nn.Dropout(0.50),
            nn.Linear(256, n_crops),
        )

    def forward(self, x):
        return self.net(self.se(x))


class SEDiseaseHead(nn.Module):
    def __init__(self, dim, num_classes, reduction=16):
        super().__init__()
        self.se = SEGate(dim, reduction)
        self.fc = nn.Linear(dim, num_classes)

    def forward(self, x):
        return self.fc(self.se(x))


class DeepCropRouter(nn.Module):
    """
    Full custom LeafCareNet crop router:
    SE(r=8) -> 1152 -> 512 -> 256 -> 3
    BatchNorm + GELU + Dropout.
    """

    def __init__(self, dim, n_crops=3, reduction=8):
        super().__init__()

        self.se = SEGate(dim, reduction)

        self.net = nn.Sequential(
            nn.Linear(dim, 512),
            nn.BatchNorm1d(512),
            nn.GELU(),
            nn.Dropout(0.30),

            nn.Linear(512, 256),
            nn.BatchNorm1d(256),
            nn.GELU(),
            nn.Dropout(0.15),

            nn.Linear(256, n_crops),
        )

    def forward(self, x):
        return self.net(self.se(x))


class FlatClassifier(nn.Module):
    def __init__(self, backbone_key, n_classes=16):
        super().__init__()

        self.backbone, feat_dim = create_backbone(backbone_key)
        self.feat_dim = feat_dim
        self.head = nn.Linear(feat_dim, n_classes)

    def forward(self, x):
        # DataParallel first scatters NCHW chunks to each GPU.
        # Convert each chunk to channels-last on its own GPU, avoiding a
        # large CPU memory-format copy of the full batch.
        if USE_CHANNELS_LAST and x.is_cuda:
            x = x.contiguous(
                memory_format=torch.channels_last
            )

        features = self.backbone(x)
        return self.head(features)


class HierarchicalClassifier(nn.Module):
    """
    variant = linear:
        linear crop router + linear disease heads

    variant = se:
        shallow SE crop router + SE disease heads

    variant = leafcarenet:
        legacy FasterNet LeafCareNet variant (kept only for code compatibility)

    NOTE:
        The final journal benchmark uses variant="linear" for LeafCareNet
        (Hierarchical MobileNetV2) and for all cross-backbone hierarchical
        controls. This preserves the exact earlier linear hierarchical
        MobileNetV2 architecture.
    """

    def __init__(
        self,
        backbone_key,
        crop_class_counts,
        variant="linear",
    ):
        super().__init__()

        self.variant = variant
        self.backbone, feat_dim = create_backbone(backbone_key)
        self.feat_dim = feat_dim

        if variant == "linear":
            self.crop_router = nn.Linear(feat_dim, 3)

            self.disease_heads = nn.ModuleList(
                [
                    LinearDiseaseHead(feat_dim, n)
                    for n in crop_class_counts
                ]
            )

        elif variant == "se":
            self.crop_router = nn.Sequential(
                SEGate(feat_dim, reduction=8),
                nn.Linear(feat_dim, 3),
            )

            self.disease_heads = nn.ModuleList(
                [
                    SEDiseaseHead(
                        feat_dim,
                        n,
                        reduction=16,
                    )
                    for n in crop_class_counts
                ]
            )

        elif variant == "leafcarenet":
            self.crop_router = DeepCropRouter(
                feat_dim,
                n_crops=3,
                reduction=8,
            )

            self.disease_heads = nn.ModuleList(
                [
                    SEDiseaseHead(
                        feat_dim,
                        n,
                        reduction=16,
                    )
                    for n in crop_class_counts
                ]
            )

        elif variant == "journal_hier":  # legacy/unused in final benchmark
            self.crop_router = JournalCropRouter(
                feat_dim,
                n_crops=3,
                reduction=8,
            )

            self.disease_heads = nn.ModuleList(
                [
                    JournalDiseaseHead(feat_dim, n)
                    for n in crop_class_counts
                ]
            )

        else:
            raise ValueError(f"Unknown variant: {variant}")

    def forward(self, x):
        # Perform the memory-format conversion after DataParallel scatter,
        # independently on each GPU replica.
        if USE_CHANNELS_LAST and x.is_cuda:
            x = x.contiguous(
                memory_format=torch.channels_last
            )

        features = self.backbone(x)

        crop_logits = self.crop_router(features)

        disease_logits = [
            head(features) for head in self.disease_heads
        ]

        return crop_logits, disease_logits


def maybe_parallel(model):
    model = model.to(DEVICE)

    if USE_CHANNELS_LAST:
        model = model.to(
            memory_format=torch.channels_last
        )

    if USE_MULTI_GPU:
        model = nn.DataParallel(
            model,
            device_ids=list(range(torch.cuda.device_count())),
            output_device=0,
            dim=0,
        )

    return model


def make_fast_adamw(model):
    """
    Use fused AdamW on CUDA when the installed PyTorch build supports it.
    This changes only optimizer implementation, not AdamW hyperparameters.
    """
    kwargs = dict(
        lr=LR,
        weight_decay=WEIGHT_DECAY,
    )

    if USE_FUSED_ADAMW:
        try:
            opt = torch.optim.AdamW(
                model.parameters(),
                fused=True,
                **kwargs,
            )
            print("Optimizer backend: fused AdamW")
            return opt
        except (TypeError, RuntimeError):
            pass

    try:
        opt = torch.optim.AdamW(
            model.parameters(),
            foreach=True,
            **kwargs,
        )
        print("Optimizer backend: foreach AdamW")
        return opt
    except TypeError:
        opt = torch.optim.AdamW(
            model.parameters(),
            **kwargs,
        )
        print("Optimizer backend: standard AdamW")
        return opt


def unwrap_model(model):
    return model.module if isinstance(model, nn.DataParallel) else model




# ============================================================
# 9. LOSSES
# ============================================================

crop_ce = nn.CrossEntropyLoss(
    label_smoothing=CROP_LABEL_SMOOTHING
)
disease_ce = nn.CrossEntropyLoss()
flat_ce = nn.CrossEntropyLoss(
    label_smoothing=FLAT_LABEL_SMOOTHING
)


def hierarchical_loss(
    crop_logits,
    disease_logits,
    crop_targets,
    disease_targets,
):
    crop_loss = crop_ce(crop_logits, crop_targets)

    disease_losses = []

    for crop_idx in range(len(CROPS)):
        mask = crop_targets == crop_idx

        if mask.any():
            d_loss = disease_ce(
                disease_logits[crop_idx][mask],
                disease_targets[mask],
            )

            disease_losses.append(d_loss)

    if disease_losses:
        disease_loss = torch.stack(disease_losses).mean()
    else:
        disease_loss = crop_logits.new_tensor(0.0)

    total = (
        CROP_LOSS_WEIGHT * crop_loss
        + disease_loss
    )

    return (
        total,
        crop_loss.detach(),
        disease_loss.detach(),
    )




# ============================================================
# 10. METRICS
# ============================================================

def classification_metrics(y_true, y_pred):
    y_true = np.asarray(y_true)
    y_pred = np.asarray(y_pred)

    acc = accuracy_score(y_true, y_pred)

    p_macro, r_macro, f_macro, _ = (
        precision_recall_fscore_support(
            y_true,
            y_pred,
            average="macro",
            zero_division=0,
        )
    )

    p_weight, r_weight, f_weight, _ = (
        precision_recall_fscore_support(
            y_true,
            y_pred,
            average="weighted",
            zero_division=0,
        )
    )

    return {
        "accuracy": float(acc),
        "balanced_accuracy": float(
            balanced_accuracy_score(y_true, y_pred)
        ),
        "macro_precision": float(p_macro),
        "macro_recall": float(r_macro),
        "macro_f1": float(f_macro),
        "weighted_precision": float(p_weight),
        "weighted_recall": float(r_weight),
        "weighted_f1": float(f_weight),
        "mcc": float(matthews_corrcoef(y_true, y_pred)),
        "cohen_kappa": float(cohen_kappa_score(y_true, y_pred)),
    }


def bootstrap_ci(
    y_true,
    y_pred,
    n_classes,
    repeats=BOOTSTRAP_REPEATS,
    seed=SEED,
):
    """Non-parametric 95% CI over the held-out test samples."""
    y_true = np.asarray(y_true)
    y_pred = np.asarray(y_pred)

    rng = np.random.default_rng(seed)
    n = len(y_true)
    labels = np.arange(n_classes)

    acc_values = []
    macro_f1_values = []

    for _ in range(repeats):
        idx = rng.integers(0, n, size=n)
        yt = y_true[idx]
        yp = y_pred[idx]

        acc_values.append(float(np.mean(yt == yp)))
        macro_f1_values.append(
            float(
                f1_score(
                    yt,
                    yp,
                    labels=labels,
                    average="macro",
                    zero_division=0,
                )
            )
        )

    return {
        "accuracy_ci95_low": float(np.percentile(acc_values, 2.5)),
        "accuracy_ci95_high": float(np.percentile(acc_values, 97.5)),
        "macro_f1_ci95_low": float(np.percentile(macro_f1_values, 2.5)),
        "macro_f1_ci95_high": float(np.percentile(macro_f1_values, 97.5)),
    }


def count_parameters(model):
    return sum(
        p.numel()
        for p in unwrap_model(model).parameters()
    )


def save_state_dict(model, path):
    torch.save(
        unwrap_model(model).state_dict(),
        path,
    )


def checkpoint_size_mb(path):
    return Path(path).stat().st_size / (1024**2)


@torch.no_grad()
def benchmark_t4_latency(
    model,
    warmup=LATENCY_WARMUP,
    repeats=LATENCY_REPEATS,
):
    """
    Batch-1 inference benchmark on a single T4.
    This is a Kaggle-GPU benchmark, NOT Android/mobile latency.
    """
    base_model = unwrap_model(model)
    base_model.eval()

    dummy = torch.randn(
        1, 3, IMG_SIZE, IMG_SIZE,
        device=DEVICE,
    )

    if USE_CHANNELS_LAST:
        dummy = dummy.contiguous(
            memory_format=torch.channels_last
        )

    for _ in range(warmup):
        _ = base_model(dummy)

    torch.cuda.synchronize()

    elapsed_ms = []

    for _ in range(repeats):
        start = time.perf_counter()
        _ = base_model(dummy)
        torch.cuda.synchronize()
        elapsed_ms.append(
            (time.perf_counter() - start) * 1000.0
        )

    elapsed_ms = np.asarray(elapsed_ms)

    return {
        "t4_batch1_latency_mean_ms": float(elapsed_ms.mean()),
        "t4_batch1_latency_p50_ms": float(
            np.percentile(elapsed_ms, 50)
        ),
        "t4_batch1_latency_p95_ms": float(
            np.percentile(elapsed_ms, 95)
        ),
        "t4_batch1_throughput_fps": float(
            1000.0 / elapsed_ms.mean()
        ),
    }




# ============================================================
# 11. DATALOADERS
# ============================================================



_MODEL_DATASET_COUNTS_VERIFIED = False


def verify_model_dataset_counts(train_ds, val_ds, test_ds):
    """
    Final minimal safety gate.

    This checks the lengths of the actual Dataset objects passed to the
    DataLoaders. No SHA-256 hashing, perceptual comparison, source grouping,
    or physical 73k-file audit is performed.
    """
    global _MODEL_DATASET_COUNTS_VERIFIED

    if _MODEL_DATASET_COUNTS_VERIFIED:
        return

    actual = {
        "train": len(train_ds),
        "val": len(val_ds),
        "test": len(test_ds),
    }

    expected = EXPECTED_MODEL_SPLIT_COUNTS

    print("\n" + "=" * 90)
    print("ACTUAL MODEL DATASET COUNT CHECK")
    print("=" * 90)
    print("Train originals :", actual["train"])
    print("Validation      :", actual["val"])
    print("Test            :", actual["test"])
    print("Total originals :", sum(actual.values()))

    if actual != expected:
        raise RuntimeError(
            "Actual model Dataset counts do not match the verified final split. "
            f"Expected {expected}, found {actual}."
        )

    if sum(actual.values()) != EXPECTED_MODEL_TOTAL_IMAGES:
        raise RuntimeError(
            "Actual model Dataset total does not match 18,296."
        )

    print("MODEL DATASET COUNTS: PASS")
    print("Duplicate/leakage re-audit: NOT REPEATED")
    print("=" * 90)

    _MODEL_DATASET_COUNTS_VERIFIED = True


def fast_worker_init_fn(worker_id):
    """
    Prevent each DataLoader process from spawning a large PyTorch CPU
    thread pool. Deterministic PIL/timm online augmentation and preprocessing remain unchanged.
    """
    torch.set_num_threads(1)

    worker_seed = (
        torch.initial_seed()
        % (
            2 ** 32
        )
    )

    np.random.seed(
        worker_seed
    )

    random.seed(
        worker_seed
    )



_WORKERS_AUTOTUNED = False


def _shutdown_loader_iterator(iterator):
    try:
        iterator._shutdown_workers()
    except Exception:
        pass


def maybe_autotune_num_workers(dataset):
    """
    Benchmark a very small number of batches using the actual compressed-file
    decode + online augmentation pipeline, then keep the fastest worker count
    for the rest of all eight experiments.

    The benchmark is run only once. RNG is reset afterwards so model training
    reproducibility is not affected by this startup benchmark.
    """
    global NUM_WORKERS
    global _WORKERS_AUTOTUNED

    if _WORKERS_AUTOTUNED or not AUTO_TUNE_NUM_WORKERS:
        return

    print("\n" + "=" * 90)
    print("ONE-TIME DATALOADER WORKER AUTOTUNE")
    print("=" * 90)
    print("Candidates:", WORKER_TUNE_CANDIDATES)
    print("Prefetch factor:", PREFETCH_FACTOR)

    results = []

    for workers in WORKER_TUNE_CANDIDATES:
        kwargs = dict(
            batch_size=BATCH_SIZE,
            shuffle=False,
            num_workers=workers,
            pin_memory=True,
            persistent_workers=False,
            worker_init_fn=fast_worker_init_fn,
        )

        if workers > 0:
            kwargs["prefetch_factor"] = PREFETCH_FACTOR

        tune_loader = DataLoader(
            dataset,
            **kwargs,
        )

        iterator = iter(tune_loader)

        try:
            for _ in range(WORKER_TUNE_WARMUP_BATCHES):
                next(iterator)

            start = time.perf_counter()
            completed = 0

            for _ in range(WORKER_TUNE_TIMED_BATCHES):
                next(iterator)
                completed += 1

            elapsed = time.perf_counter() - start

            images_seen = (
                completed
                * BATCH_SIZE
            )

            throughput = (
                images_seen
                / max(elapsed, 1e-9)
            )

            results.append(
                (throughput, workers)
            )

            print(
                f"workers={workers}: "
                f"{throughput:.1f} images/s "
                f"({elapsed:.2f}s for {completed} timed batches)"
            )

        except StopIteration:
            pass
        finally:
            _shutdown_loader_iterator(iterator)
            del iterator
            del tune_loader
            gc.collect()

    if not results:
        raise RuntimeError(
            "Could not benchmark any DataLoader worker candidate."
        )

    results.sort(
        reverse=True
    )

    best_throughput, best_workers = results[0]
    NUM_WORKERS = int(best_workers)
    _WORKERS_AUTOTUNED = True

    # The tuning loaders consume RNG states for worker seeding / augmentation.
    # Reset before the real experiment loader and model are created.
    seed_everything(SEED)

    print(
        f"Selected NUM_WORKERS={NUM_WORKERS} "
        f"({best_throughput:.1f} images/s CPU pipeline throughput)"
    )
    print("=" * 90)


def loader_kwargs():
    kwargs = dict(
        num_workers=NUM_WORKERS,
        pin_memory=True,
        persistent_workers=NUM_WORKERS > 0,
        worker_init_fn=fast_worker_init_fn,
    )

    if NUM_WORKERS > 0:
        kwargs["prefetch_factor"] = PREFETCH_FACTOR

    return kwargs


def build_flat_loaders(backbone_key):
    train_tf, eval_tf = make_transforms(backbone_key)

    train_h = HierarchicalLeafDataset(
        DATA_ROOT,
        "train",
        train_tf,
    )
    val_h = HierarchicalLeafDataset(
        DATA_ROOT,
        "val",
        eval_tf,
    )
    test_h = HierarchicalLeafDataset(
        DATA_ROOT,
        "test",
        eval_tf,
    )

    train_ds = FlatLeafDataset(train_h)
    val_ds = FlatLeafDataset(val_h)
    test_ds = FlatLeafDataset(test_h)

    verify_model_dataset_counts(
        train_ds,
        val_ds,
        test_ds,
    )

    maybe_autotune_num_workers(
        train_ds
    )

    sampler = build_flat_balanced_sampler(train_ds)

    train_loader = DataLoader(
        train_ds,
        batch_size=BATCH_SIZE,
        sampler=sampler,
        **loader_kwargs(),
    )

    val_loader = DataLoader(
        val_ds,
        batch_size=EVAL_BATCH_SIZE,
        shuffle=False,
        **loader_kwargs(),
    )

    test_loader = DataLoader(
        test_ds,
        batch_size=EVAL_BATCH_SIZE,
        shuffle=False,
        **loader_kwargs(),
    )

    return (
        train_loader,
        val_loader,
        test_loader,
        train_ds.global_classes,
    )


def build_hier_loaders(backbone_key):
    train_tf, eval_tf = make_transforms(backbone_key)

    train_ds = HierarchicalLeafDataset(
        DATA_ROOT,
        "train",
        train_tf,
    )
    val_ds = HierarchicalLeafDataset(
        DATA_ROOT,
        "val",
        eval_tf,
    )
    test_ds = HierarchicalLeafDataset(
        DATA_ROOT,
        "test",
        eval_tf,
    )

    verify_model_dataset_counts(
        train_ds,
        val_ds,
        test_ds,
    )

    maybe_autotune_num_workers(
        train_ds
    )

    sampler = build_hierarchical_balanced_sampler(train_ds)

    train_loader = DataLoader(
        train_ds,
        batch_size=BATCH_SIZE,
        sampler=sampler,
        **loader_kwargs(),
    )

    val_loader = DataLoader(
        val_ds,
        batch_size=EVAL_BATCH_SIZE,
        shuffle=False,
        **loader_kwargs(),
    )

    test_loader = DataLoader(
        test_ds,
        batch_size=EVAL_BATCH_SIZE,
        shuffle=False,
        **loader_kwargs(),
    )

    crop_class_counts = [
        len(train_ds.crop_classes[crop])
        for crop in CROPS
    ]

    return (
        train_loader,
        val_loader,
        test_loader,
        train_ds,
        val_ds,
        test_ds,
        crop_class_counts,
    )




# ============================================================
# 12. FLAT TRAINING — SPEED OPTIMIZED, SAME METRICS
# ============================================================

def _to_gpu_images(images):
    """
    Transfer images to the single visible T4.

    Fast-cache path:
      pinned CPU uint8 -> async H2D -> float/255 -> model normalization on GPU.

    Normal path:
      the existing CPU transform already returns normalized float tensors.
    """
    global _GPU_NORM_MEAN
    global _GPU_NORM_STD

    if USE_MULTI_GPU and USE_DIRECT_DP_CPU_SCATTER:
        return images

    images = images.to(
        DEVICE,
        non_blocking=True,
    )

    if images.dtype == torch.uint8:
        if ACTIVE_INPUT_MEAN is None or ACTIVE_INPUT_STD is None:
            raise RuntimeError(
                "GPU normalization requested before model mean/std were resolved."
            )

        images = images.to(
            dtype=torch.float32
        ).mul_(
            1.0 / 255.0
        )

        if _GPU_NORM_MEAN is None:
            _GPU_NORM_MEAN = torch.tensor(
                ACTIVE_INPUT_MEAN,
                dtype=torch.float32,
                device=DEVICE,
            ).view(
                1, 3, 1, 1
            )

            _GPU_NORM_STD = torch.tensor(
                ACTIVE_INPUT_STD,
                dtype=torch.float32,
                device=DEVICE,
            ).view(
                1, 3, 1, 1
            )

        images.sub_(
            _GPU_NORM_MEAN
        ).div_(
            _GPU_NORM_STD
        )

    return images


def _update_gpu_confusion(cm, y_true, y_pred):
    n = cm.shape[0]
    encoded = (
        y_true.to(torch.int64) * n
        + y_pred.to(torch.int64)
    )
    cm += torch.bincount(
        encoded,
        minlength=n * n,
    ).reshape(n, n)


def _basic_metrics_from_gpu_confusion(cm):
    cmf = cm.to(torch.float32)
    tp = torch.diag(cmf)
    total = cmf.sum()

    accuracy = torch.where(
        total > 0,
        tp.sum() / total,
        torch.zeros((), device=cm.device),
    )

    support = cmf.sum(dim=1)
    predicted = cmf.sum(dim=0)

    precision = torch.where(
        predicted > 0,
        tp / predicted.clamp_min(1.0),
        torch.zeros_like(tp),
    )

    recall = torch.where(
        support > 0,
        tp / support.clamp_min(1.0),
        torch.zeros_like(tp),
    )

    denom = precision + recall
    f1 = torch.where(
        denom > 0,
        2.0 * precision * recall / denom,
        torch.zeros_like(denom),
    )

    return {
        "accuracy": float(accuracy.item()),
        "macro_f1": float(f1.mean().item()),
    }

def run_flat_epoch(
    model,
    loader,
    optimizer=None,
    scaler=None,
):
    train_mode = optimizer is not None
    model.train(train_mode)

    total_loss = torch.zeros(
        (),
        device=DEVICE,
        dtype=torch.float32,
    )

    n_classes = len(loader.dataset.global_classes)

    cm = torch.zeros(
        (n_classes, n_classes),
        device=DEVICE,
        dtype=torch.int64,
    )

    grad_context = (
        torch.enable_grad
        if train_mode
        else torch.inference_mode
    )

    with grad_context():
        for images, targets in tqdm(
            loader,
            leave=False,
            mininterval=TQDM_MININTERVAL,
        ):
            images = _to_gpu_images(images)

            targets = targets.to(
                DEVICE,
                non_blocking=True,
            )

            if train_mode:
                optimizer.zero_grad(
                    set_to_none=True
                )

            with torch.cuda.amp.autocast(
                enabled=USE_AMP
            ):
                logits = model(images)
                loss = flat_ce(
                    logits,
                    targets,
                )

            if train_mode:
                scaler.scale(loss).backward()
                scaler.step(optimizer)
                scaler.update()

            batch_size = targets.size(0)

            total_loss += (
                loss.detach().float()
                * batch_size
            )

            pred = logits.detach().argmax(
                dim=1
            )

            _update_gpu_confusion(
                cm,
                targets,
                pred,
            )

    metrics = _basic_metrics_from_gpu_confusion(
        cm
    )

    metrics["loss"] = float(
        (
            total_loss
            / len(loader.dataset)
        ).item()
    )

    return metrics


@torch.inference_mode()
def evaluate_flat_test(
    model,
    loader,
    class_names,
):
    model.eval()

    y_true_gpu = []
    y_pred_gpu = []
    confidence_gpu = []

    for images, targets in tqdm(
        loader,
        leave=False,
        mininterval=TQDM_MININTERVAL,
    ):
        images = _to_gpu_images(
            images
        )

        logits = model(
            images
        )

        probs = torch.softmax(
            logits,
            dim=1,
        )

        conf, pred = probs.max(
            dim=1
        )

        y_true_gpu.append(
            targets.to(
                DEVICE,
                non_blocking=True,
            )
        )

        y_pred_gpu.append(
            pred.detach()
        )

        confidence_gpu.append(
            conf.detach()
        )

    y_true = (
        torch.cat(
            y_true_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    y_pred = (
        torch.cat(
            y_pred_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    confidences = (
        torch.cat(
            confidence_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    metrics = classification_metrics(
        y_true,
        y_pred,
    )

    report = classification_report(
        y_true,
        y_pred,
        target_names=class_names,
        output_dict=True,
        zero_division=0,
    )

    cm = confusion_matrix(
        y_true,
        y_pred,
    )

    return (
        metrics,
        report,
        cm,
        y_true,
        y_pred,
        confidences,
    )


# ============================================================
# 13. HIERARCHICAL EPOCH METRICS — VECTORIZED FAST VERSION
# ============================================================

def _crop_global_offsets(dataset):
    offsets = []
    running = 0

    for crop in CROPS:
        offsets.append(
            running
        )

        running += len(
            dataset.crop_classes[
                crop
            ]
        )

    return torch.tensor(
        offsets,
        dtype=torch.long,
        device=DEVICE,
    )


def _vectorized_routed_prediction(
    crop_logits,
    disease_logits,
    dataset,
):
    """
    TRUE sequential routing:
      predicted crop -> corresponding disease head -> global class index.

    Same mathematical prediction as the previous per-sample loop,
    implemented batch-wise to avoid CUDA synchronization.
    """
    crop_prediction = crop_logits.argmax(
        dim=1
    )

    global_prediction = torch.empty(
        crop_prediction.shape[0],
        dtype=torch.long,
        device=crop_prediction.device,
    )

    offsets = _crop_global_offsets(
        dataset
    )

    for crop_idx in range(
        len(CROPS)
    ):
        mask = (
            crop_prediction
            == crop_idx
        )

        # Do not call .item(); indexing an empty mask is valid.
        local_prediction = (
            disease_logits[
                crop_idx
            ][mask]
            .argmax(
                dim=1
            )
        )

        global_prediction[
            mask
        ] = (
            offsets[
                crop_idx
            ]
            + local_prediction
        )

    return (
        crop_prediction,
        global_prediction,
    )


def run_hier_epoch(
    model,
    loader,
    optimizer=None,
    scaler=None,
):
    train_mode = optimizer is not None
    model.train(train_mode)

    total_loss = torch.zeros(
        (),
        device=DEVICE,
        dtype=torch.float32,
    )
    total_crop_loss = torch.zeros(
        (),
        device=DEVICE,
        dtype=torch.float32,
    )
    total_disease_loss = torch.zeros(
        (),
        device=DEVICE,
        dtype=torch.float32,
    )

    ds = loader.dataset
    if hasattr(ds, "base"):
        ds = ds.base

    n_global = len(ds.global_classes)

    crop_cm = torch.zeros(
        (len(CROPS), len(CROPS)),
        device=DEVICE,
        dtype=torch.int64,
    )

    end_cm = torch.zeros(
        (n_global, n_global),
        device=DEVICE,
        dtype=torch.int64,
    )

    oracle_cms = {
        crop_idx: torch.zeros(
            (
                len(ds.crop_classes[crop]),
                len(ds.crop_classes[crop]),
            ),
            device=DEVICE,
            dtype=torch.int64,
        )
        for crop_idx, crop in enumerate(CROPS)
    }

    grad_context = (
        torch.enable_grad
        if train_mode
        else torch.inference_mode
    )

    with grad_context():
        for (
            images,
            crop_t,
            disease_t,
            global_t,
        ) in tqdm(
            loader,
            leave=False,
            mininterval=TQDM_MININTERVAL,
        ):
            images = _to_gpu_images(images)

            crop_t_gpu = crop_t.to(
                DEVICE,
                non_blocking=True,
            )
            disease_t_gpu = disease_t.to(
                DEVICE,
                non_blocking=True,
            )
            global_t_gpu = global_t.to(
                DEVICE,
                non_blocking=True,
            )

            if train_mode:
                optimizer.zero_grad(
                    set_to_none=True
                )

            with torch.cuda.amp.autocast(
                enabled=USE_AMP
            ):
                (
                    crop_logits,
                    disease_logits,
                ) = model(images)

                (
                    loss,
                    crop_loss,
                    disease_loss,
                ) = hierarchical_loss(
                    crop_logits,
                    disease_logits,
                    crop_t_gpu,
                    disease_t_gpu,
                )

            if train_mode:
                scaler.scale(loss).backward()
                scaler.step(optimizer)
                scaler.update()

            batch_size = crop_t_gpu.size(0)

            total_loss += (
                loss.detach().float()
                * batch_size
            )
            total_crop_loss += (
                crop_loss.detach().float()
                * batch_size
            )
            total_disease_loss += (
                disease_loss.detach().float()
                * batch_size
            )

            (
                crop_prediction,
                global_prediction,
            ) = _vectorized_routed_prediction(
                crop_logits.detach(),
                [
                    output.detach()
                    for output in disease_logits
                ],
                ds,
            )

            _update_gpu_confusion(
                crop_cm,
                crop_t_gpu,
                crop_prediction,
            )

            _update_gpu_confusion(
                end_cm,
                global_t_gpu,
                global_prediction,
            )

            # Oracle Stage-2 metrics use the TRUE crop.
            for crop_idx in range(len(CROPS)):
                mask = (
                    crop_t_gpu
                    == crop_idx
                )

                if mask.any():
                    oracle_pred = (
                        disease_logits[crop_idx][mask]
                        .detach()
                        .argmax(dim=1)
                    )

                    _update_gpu_confusion(
                        oracle_cms[crop_idx],
                        disease_t_gpu[mask],
                        oracle_pred,
                    )

    crop_metrics = _basic_metrics_from_gpu_confusion(
        crop_cm
    )

    end_metrics = _basic_metrics_from_gpu_confusion(
        end_cm
    )

    per_crop = {
        crop: _basic_metrics_from_gpu_confusion(
            oracle_cms[crop_idx]
        )
        for crop_idx, crop in enumerate(CROPS)
    }

    dataset_size = len(loader.dataset)

    return {
        "loss": float(
            (
                total_loss
                / dataset_size
            ).item()
        ),
        "crop_loss": float(
            (
                total_crop_loss
                / dataset_size
            ).item()
        ),
        "disease_loss": float(
            (
                total_disease_loss
                / dataset_size
            ).item()
        ),

        "crop_accuracy": crop_metrics["accuracy"],
        "crop_macro_f1": crop_metrics["macro_f1"],

        "end_to_end_accuracy": end_metrics["accuracy"],
        "end_to_end_macro_f1": end_metrics["macro_f1"],

        "potato_accuracy": per_crop["potato"]["accuracy"],
        "potato_macro_f1": per_crop["potato"]["macro_f1"],

        "rice_accuracy": per_crop["rice"]["accuracy"],
        "rice_macro_f1": per_crop["rice"]["macro_f1"],

        "tomato_accuracy": per_crop["tomato"]["accuracy"],
        "tomato_macro_f1": per_crop["tomato"]["macro_f1"],
    }


# ============================================================
# 14. FULL HIERARCHICAL TEST EVALUATION — VECTORIZED FAST VERSION
# ============================================================

@torch.inference_mode()
def evaluate_hierarchical_test(
    model,
    loader,
    dataset,
):
    model.eval()

    crop_true_gpu = []
    crop_pred_gpu = []
    crop_confidence_gpu = []

    oracle_true_gpu = {
        crop_idx: []
        for crop_idx in range(
            len(CROPS)
        )
    }

    oracle_pred_gpu = {
        crop_idx: []
        for crop_idx in range(
            len(CROPS)
        )
    }

    oracle_confidence_gpu = {
        crop_idx: []
        for crop_idx in range(
            len(CROPS)
        )
    }

    global_true_gpu = []
    global_pred_gpu = []
    end_confidence_gpu = []

    offsets = _crop_global_offsets(
        dataset
    )

    for (
        images,
        crop_t,
        disease_t,
        global_t,
    ) in tqdm(
        loader,
        leave=False,
        mininterval=TQDM_MININTERVAL,
    ):
        images = _to_gpu_images(
            images
        )

        crop_t_gpu = crop_t.to(
            DEVICE,
            non_blocking=True,
        )

        disease_t_gpu = disease_t.to(
            DEVICE,
            non_blocking=True,
        )

        global_t_gpu = global_t.to(
            DEVICE,
            non_blocking=True,
        )

        with torch.cuda.amp.autocast(
            enabled=USE_AMP
        ):
            (
                crop_logits,
                disease_logits,
            ) = model(
                images
            )

        crop_prob = torch.softmax(
            crop_logits,
            dim=1,
        )

        (
            crop_confidence,
            crop_prediction,
        ) = crop_prob.max(
            dim=1
        )

        global_prediction = torch.empty(
            crop_prediction.shape[0],
            dtype=torch.long,
            device=DEVICE,
        )

        sequential_confidence = torch.empty(
            crop_prediction.shape[0],
            dtype=crop_prob.dtype,
            device=DEVICE,
        )

        for crop_idx in range(
            len(CROPS)
        ):
            predicted_mask = (
                crop_prediction
                == crop_idx
            )

            routed_prob = torch.softmax(
                disease_logits[
                    crop_idx
                ][predicted_mask],
                dim=1,
            )

            (
                routed_confidence,
                routed_prediction,
            ) = routed_prob.max(
                dim=1
            )

            global_prediction[
                predicted_mask
            ] = (
                offsets[
                    crop_idx
                ]
                + routed_prediction
            )

            sequential_confidence[
                predicted_mask
            ] = (
                crop_confidence[
                    predicted_mask
                ]
                * routed_confidence
            )

            # Oracle disease evaluation uses TRUE crop.
            true_mask = (
                crop_t_gpu
                == crop_idx
            )

            oracle_prob = torch.softmax(
                disease_logits[
                    crop_idx
                ][true_mask],
                dim=1,
            )

            (
                oracle_confidence,
                oracle_prediction,
            ) = oracle_prob.max(
                dim=1
            )

            oracle_true_gpu[
                crop_idx
            ].append(
                disease_t_gpu[
                    true_mask
                ].detach()
            )

            oracle_pred_gpu[
                crop_idx
            ].append(
                oracle_prediction.detach()
            )

            oracle_confidence_gpu[
                crop_idx
            ].append(
                oracle_confidence.detach()
            )

        crop_true_gpu.append(
            crop_t_gpu.detach()
        )

        crop_pred_gpu.append(
            crop_prediction.detach()
        )

        crop_confidence_gpu.append(
            crop_confidence.detach()
        )

        global_true_gpu.append(
            global_t_gpu.detach()
        )

        global_pred_gpu.append(
            global_prediction.detach()
        )

        end_confidence_gpu.append(
            sequential_confidence.detach()
        )

    crop_true = (
        torch.cat(
            crop_true_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    crop_pred = (
        torch.cat(
            crop_pred_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    crop_confidences = (
        torch.cat(
            crop_confidence_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    global_true = (
        torch.cat(
            global_true_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    global_pred = (
        torch.cat(
            global_pred_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    end_confidences = (
        torch.cat(
            end_confidence_gpu
        )
        .cpu()
        .numpy()
        .tolist()
    )

    oracle_true = {}
    oracle_pred = {}
    oracle_confidence = {}

    for crop_idx in range(
        len(CROPS)
    ):
        true_parts = [
            tensor
            for tensor
            in oracle_true_gpu[
                crop_idx
            ]
            if tensor.numel() > 0
        ]

        pred_parts = [
            tensor
            for tensor
            in oracle_pred_gpu[
                crop_idx
            ]
            if tensor.numel() > 0
        ]

        conf_parts = [
            tensor
            for tensor
            in oracle_confidence_gpu[
                crop_idx
            ]
            if tensor.numel() > 0
        ]

        oracle_true[
            crop_idx
        ] = (
            torch.cat(
                true_parts
            )
            .cpu()
            .numpy()
            .tolist()
        )

        oracle_pred[
            crop_idx
        ] = (
            torch.cat(
                pred_parts
            )
            .cpu()
            .numpy()
            .tolist()
        )

        oracle_confidence[
            crop_idx
        ] = (
            torch.cat(
                conf_parts
            )
            .cpu()
            .numpy()
            .tolist()
        )

    crop_metrics = classification_metrics(
        crop_true,
        crop_pred,
    )

    end_metrics = classification_metrics(
        global_true,
        global_pred,
    )

    per_crop = {}

    for crop_idx, crop in enumerate(
        CROPS
    ):
        per_crop[
            crop
        ] = classification_metrics(
            oracle_true[
                crop_idx
            ],
            oracle_pred[
                crop_idx
            ],
        )

    crop_cm = confusion_matrix(
        crop_true,
        crop_pred,
    )

    global_cm = confusion_matrix(
        global_true,
        global_pred,
    )

    per_crop_cm = {}

    for crop_idx, crop in enumerate(
        CROPS
    ):
        per_crop_cm[
            crop
        ] = confusion_matrix(
            oracle_true[
                crop_idx
            ],
            oracle_pred[
                crop_idx
            ],
        )

    crop_report = classification_report(
        crop_true,
        crop_pred,
        target_names=[
            crop.title()
            for crop in CROPS
        ],
        output_dict=True,
        zero_division=0,
    )

    per_crop_report = {}

    for crop_idx, crop in enumerate(
        CROPS
    ):
        per_crop_report[
            crop
        ] = classification_report(
            oracle_true[
                crop_idx
            ],
            oracle_pred[
                crop_idx
            ],
            target_names=dataset.crop_classes[
                crop
            ],
            output_dict=True,
            zero_division=0,
        )

    global_report = classification_report(
        global_true,
        global_pred,
        target_names=dataset.global_classes,
        output_dict=True,
        zero_division=0,
    )

    return {
        "crop": crop_metrics,
        "oracle_per_crop": per_crop,
        "end_to_end": end_metrics,

        "crop_cm": crop_cm,
        "per_crop_cm": per_crop_cm,
        "global_cm": global_cm,

        "crop_report": crop_report,
        "per_crop_report": per_crop_report,
        "global_report": global_report,

        "crop_true": crop_true,
        "crop_pred": crop_pred,

        "global_true": global_true,
        "global_pred": global_pred,

        "crop_confidences": crop_confidences,
        "oracle_confidence": oracle_confidence,
        "end_confidences": end_confidences,
    }


# ============================================================
# 15. PLOTTING UTILITIES — ALL 300-DPI PNG
# ============================================================

def save_line_plot(
    x,
    series,
    title,
    xlabel,
    ylabel,
    path,
):
    plt.figure(figsize=(8, 5))

    for label, values in series.items():
        plt.plot(
            x,
            values,
            label=label,
        )

    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)

    if len(series) > 1:
        plt.legend()

    plt.grid(alpha=0.25)
    plt.tight_layout()

    plt.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close()


def plot_confusion_matrix(
    cm,
    labels,
    title,
    path,
    normalize=False,
):
    cm = np.array(cm)

    if normalize:
        cm = cm.astype(float)

        row_sums = cm.sum(
            axis=1,
            keepdims=True,
        )

        cm = np.divide(
            cm,
            row_sums,
            out=np.zeros_like(cm),
            where=row_sums != 0,
        )

    plt.figure(
        figsize=(
            max(7, len(labels) * 0.75),
            max(6, len(labels) * 0.65),
        )
    )

    plt.imshow(
        cm,
        interpolation="nearest",
        cmap="Blues",
    )

    plt.title(title)
    plt.colorbar()

    tick_marks = np.arange(len(labels))

    plt.xticks(
        tick_marks,
        labels,
        rotation=90,
        fontsize=8,
    )

    plt.yticks(
        tick_marks,
        labels,
        fontsize=8,
    )

    threshold = (
        cm.max() / 2.0
        if cm.size and cm.max() > 0
        else 0
    )

    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            if normalize:
                text = f"{cm[i, j]:.2f}"
            else:
                text = f"{int(cm[i, j])}"

            plt.text(
                j,
                i,
                text,
                horizontalalignment="center",
                verticalalignment="center",
                fontsize=7,
                color=(
                    "white"
                    if cm[i, j] > threshold
                    else "black"
                ),
            )

    plt.xlabel("Predicted class")
    plt.ylabel("True class")
    plt.tight_layout()

    plt.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close()


def report_to_dataframe(
    report,
    class_names,
):
    rows = []

    for cls in class_names:
        r = report[cls]

        rows.append(
            {
                "class": cls,
                "precision": r["precision"],
                "recall": r["recall"],
                "f1-score": r["f1-score"],
                "support": r["support"],
            }
        )

    return pd.DataFrame(rows)


def plot_per_class_metrics(
    report,
    class_names,
    title,
    path,
):
    df = report_to_dataframe(
        report,
        class_names,
    )

    y = np.arange(len(df))
    height = 0.24

    plt.figure(
        figsize=(
            11,
            max(6, len(df) * 0.45),
        )
    )

    plt.barh(
        y - height,
        df["precision"],
        height=height,
        label="Precision",
    )

    plt.barh(
        y,
        df["recall"],
        height=height,
        label="Recall",
    )

    plt.barh(
        y + height,
        df["f1-score"],
        height=height,
        label="F1-score",
    )

    plt.yticks(y, df["class"], fontsize=8)
    plt.xlabel("Score")
    plt.xlim(0, 1.0)
    plt.title(title)
    plt.legend()
    plt.tight_layout()

    plt.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close()

    return df


def plot_confidence_distribution(
    y_true,
    y_pred,
    confidence,
    title,
    path,
):
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)
    confidence = np.array(confidence)

    correct = confidence[y_true == y_pred]
    incorrect = confidence[y_true != y_pred]

    plt.figure(figsize=(8, 5))

    if len(correct) > 0:
        plt.hist(
            correct,
            bins=20,
            alpha=0.65,
            label=f"Correct (n={len(correct)})",
        )

    if len(incorrect) > 0:
        plt.hist(
            incorrect,
            bins=20,
            alpha=0.65,
            label=f"Incorrect (n={len(incorrect)})",
        )

    plt.xlabel("Prediction confidence")
    plt.ylabel("Number of samples")
    plt.title(title)
    plt.legend()
    plt.tight_layout()

    plt.savefig(
        path,
        dpi=300,
        bbox_inches="tight",
    )

    plt.close()




# ============================================================
# 16. FLAT EXPERIMENT
# ============================================================


def save_history_csv(history, path):
    rows = []
    for item in history:
        row = {
            "epoch": item.get("epoch"),
            "lr": item.get("lr"),
        }
        for split in ["train", "val"]:
            metrics = item.get(split, {}) or {}
            for key, value in metrics.items():
                if isinstance(value, (int, float, np.integer, np.floating)):
                    row[f"{split}_{key}"] = float(value)
        rows.append(row)
    pd.DataFrame(rows).to_csv(path, index=False)


def write_experiment_config(exp_name, family, backbone_key, variant):
    payload = {
        "experiment": exp_name,
        "family": family,
        "backbone_key": backbone_key,
        "resolved_backbone": RESOLVED_BACKBONES.get(backbone_key),
        "variant": variant,
        "seed": SEED,
        "image_size": IMG_SIZE,
        "train_batch_size": BATCH_SIZE,
        "eval_batch_size": EVAL_BATCH_SIZE,
        "max_epochs": MAX_EPOCHS,
        "patience": PATIENCE,
        "min_delta": MIN_DELTA,
        "optimizer": "AdamW",
        "learning_rate": LR,
        "weight_decay": WEIGHT_DECAY,
        "crop_loss_weight": CROP_LOSS_WEIGHT,
        "crop_label_smoothing": CROP_LABEL_SMOOTHING,
        "flat_label_smoothing": FLAT_LABEL_SMOOTHING,
        "online_augmentation": False,
        "offline_augmented_files_used": False,
        "weighted_balanced_sampling": True,
        "amp": USE_AMP,
        "channels_last": USE_CHANNELS_LAST,
        "dataset_counts": EXPECTED_MODEL_SPLIT_COUNTS,
        "dataset_total": EXPECTED_MODEL_TOTAL_IMAGES,
    }
    (OUTPUT_ROOT / "experiment_config.json").write_text(
        json.dumps(payload, indent=2), encoding="utf-8"
    )


def train_flat_experiment(
    exp_name,
    backbone_key,
):
    print("\n" + "=" * 90)
    print("EXPERIMENT:", exp_name)
    print("TYPE: Flat 16-class")
    print("BACKBONE:", backbone_key)
    print("=" * 90)

    seed_everything(SEED)

    exp_dir = OUTPUT_ROOT / exp_name
    exp_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    (
        train_loader,
        val_loader,
        test_loader,
        class_names,
    ) = build_flat_loaders(backbone_key)

    model = FlatClassifier(
        backbone_key,
        n_classes=len(class_names),
    )

    model = maybe_parallel(model)

    optimizer = make_fast_adamw(
        model
    )

    scheduler = (
        torch.optim.lr_scheduler.CosineAnnealingLR(
            optimizer,
            T_max=MAX_EPOCHS,
        )
    )

    scaler = torch.cuda.amp.GradScaler(
        enabled=USE_AMP
    )

    best_val = float("inf")
    best_epoch = 0
    patience_left = PATIENCE

    history = []

    ckpt = (
        CHECKPOINT_ROOT
        / f"{exp_name}_best.pth"
    )

    start = time.time()

    for epoch in range(1, MAX_EPOCHS + 1):
        train_metrics = run_flat_epoch(
            model,
            train_loader,
            optimizer,
            scaler,
        )

        val_metrics = run_flat_epoch(
            model,
            val_loader,
        )

        scheduler.step()

        history.append(
            {
                "epoch": epoch,
                "lr": optimizer.param_groups[0]["lr"],
                "train": train_metrics,
                "val": val_metrics,
            }
        )

        print(
            f"[{epoch:03d}/{MAX_EPOCHS}] "
            f"train_loss={train_metrics['loss']:.4f} "
            f"train_acc={train_metrics['accuracy']:.4f} | "
            f"val_loss={val_metrics['loss']:.4f} "
            f"val_acc={val_metrics['accuracy']:.4f} "
            f"val_macroF1={val_metrics['macro_f1']:.4f}"
        )

        if (
            best_val - val_metrics["loss"]
            > MIN_DELTA
        ):
            best_val = val_metrics["loss"]
            best_epoch = epoch
            patience_left = PATIENCE

            save_state_dict(
                model,
                ckpt,
            )

        else:
            patience_left -= 1

        if patience_left <= 0:
            print(
                f"Early stopping at epoch {epoch}."
            )
            break

    train_seconds = time.time() - start

    unwrap_model(model).load_state_dict(
        torch.load(
            ckpt,
            map_location=DEVICE,
        )
    )

    (
        test_metrics,
        report,
        cm,
        y_true,
        y_pred,
        confidence,
    ) = evaluate_flat_test(
        model,
        test_loader,
        class_names,
    )

    ci = bootstrap_ci(
        y_true,
        y_pred,
        n_classes=len(class_names),
    )

    latency = benchmark_t4_latency(model)

    result = {
        "experiment": exp_name,
        "family": "flat",
        "backbone": backbone_key,
        "variant": "flat_16class",

        "best_epoch": best_epoch,
        "training_seconds": train_seconds,

        "parameters": count_parameters(model),
        "checkpoint_mb": checkpoint_size_mb(ckpt),

        "test_accuracy": test_metrics["accuracy"],
        "test_balanced_accuracy": test_metrics["balanced_accuracy"],
        "test_macro_precision": test_metrics["macro_precision"],
        "test_macro_recall": test_metrics["macro_recall"],
        "test_macro_f1": test_metrics["macro_f1"],
        "test_weighted_f1": test_metrics["weighted_f1"],
        "test_mcc": test_metrics["mcc"],
        "test_cohen_kappa": test_metrics["cohen_kappa"],

        **ci,
        **latency,
    }

    # Per-image test predictions. test_loader is not shuffled, so the
    # prediction order matches test_loader.dataset.base.samples.
    flat_test_base = test_loader.dataset.base
    prediction_rows = []

    for idx, (yt, yp, conf) in enumerate(
        zip(y_true, y_pred, confidence)
    ):
        sample_path = flat_test_base.samples[idx][0]

        prediction_rows.append(
            {
                "sample_index": idx,
                "path": sample_path,
                "true_global_idx": int(yt),
                "true_class": class_names[yt],
                "pred_global_idx": int(yp),
                "pred_class": class_names[yp],
                "confidence": float(conf),
                "correct": int(yt == yp),
            }
        )

    pd.DataFrame(prediction_rows).to_csv(
        PREDICTION_ROOT / f"{exp_name}_test_predictions.csv",
        index=False,
    )

    # Save raw outputs
    (
        exp_dir / "history.json"
    ).write_text(
        json.dumps(history, indent=2)
    )

    save_history_csv(
        history,
        TABLE_ROOT / f"{exp_name}_history.csv",
    )

    (
        exp_dir / "result.json"
    ).write_text(
        json.dumps(result, indent=2)
    )

    (
        exp_dir / "classification_report.json"
    ).write_text(
        json.dumps(report, indent=2)
    )

    np.save(
        exp_dir / "confusion_matrix.npy",
        cm,
    )

    # 300 DPI figures
    epochs = [
        h["epoch"] for h in history
    ]

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["loss"]
                for h in history
            ],
            "Validation": [
                h["val"]["loss"]
                for h in history
            ],
        },
        f"{exp_name}: training and validation loss",
        "Epoch",
        "Loss",
        FIG_ROOT / f"{exp_name}_loss_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["accuracy"]
                for h in history
            ],
            "Validation": [
                h["val"]["accuracy"]
                for h in history
            ],
        },
        f"{exp_name}: training and validation accuracy",
        "Epoch",
        "Accuracy",
        FIG_ROOT / f"{exp_name}_accuracy_curve.png",
    )

    plot_confusion_matrix(
        cm,
        class_names,
        f"{exp_name}: test confusion matrix",
        FIG_ROOT / f"{exp_name}_confusion_matrix_counts.png",
        normalize=False,
    )

    plot_confusion_matrix(
        cm,
        class_names,
        f"{exp_name}: normalized test confusion matrix",
        FIG_ROOT / f"{exp_name}_confusion_matrix_normalized.png",
        normalize=True,
    )

    metrics_df = plot_per_class_metrics(
        report,
        class_names,
        f"{exp_name}: per-class test metrics",
        FIG_ROOT / f"{exp_name}_per_class_metrics.png",
    )

    metrics_df.to_csv(
        TABLE_ROOT
        / f"{exp_name}_per_class_metrics.csv",
        index=False,
    )

    plot_confidence_distribution(
        y_true,
        y_pred,
        confidence,
        f"{exp_name}: test confidence distribution",
        FIG_ROOT
        / f"{exp_name}_confidence_distribution.png",
    )

    print("TEST:", result)

    del (
        model,
        train_loader,
        val_loader,
        test_loader,
    )

    gc.collect()
    torch.cuda.empty_cache()

    return result




# ============================================================
# 17. HIERARCHICAL EXPERIMENT
# ============================================================

def train_hier_experiment(
    exp_name,
    backbone_key,
    variant,
):
    print("\n" + "=" * 90)
    print("EXPERIMENT:", exp_name)
    print("TYPE: Hierarchical")
    print("BACKBONE:", backbone_key)
    print("VARIANT:", variant)
    print("=" * 90)

    seed_everything(SEED)

    exp_dir = OUTPUT_ROOT / exp_name
    exp_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    (
        train_loader,
        val_loader,
        test_loader,
        train_ds,
        val_ds,
        test_ds,
        crop_class_counts,
    ) = build_hier_loaders(backbone_key)

    model = HierarchicalClassifier(
        backbone_key,
        crop_class_counts,
        variant=variant,
    )

    model = maybe_parallel(model)

    optimizer = make_fast_adamw(
        model
    )

    scheduler = (
        torch.optim.lr_scheduler.CosineAnnealingLR(
            optimizer,
            T_max=MAX_EPOCHS,
        )
    )

    scaler = torch.cuda.amp.GradScaler(
        enabled=USE_AMP
    )

    best_val = float("inf")
    best_epoch = 0
    patience_left = PATIENCE

    history = []

    ckpt = (
        CHECKPOINT_ROOT
        / f"{exp_name}_best.pth"
    )

    start = time.time()

    for epoch in range(1, MAX_EPOCHS + 1):
        train_metrics = run_hier_epoch(
            model,
            train_loader,
            optimizer,
            scaler,
        )

        val_metrics = run_hier_epoch(
            model,
            val_loader,
        )

        scheduler.step()

        history.append(
            {
                "epoch": epoch,
                "lr": optimizer.param_groups[0]["lr"],
                "train": train_metrics,
                "val": val_metrics,
            }
        )

        print(
            f"[{epoch:03d}/{MAX_EPOCHS}] "
            f"train_loss={train_metrics['loss']:.4f} "
            f"crop_acc={train_metrics['crop_accuracy']:.4f} "
            f"e2e_acc={train_metrics['end_to_end_accuracy']:.4f} | "
            f"val_loss={val_metrics['loss']:.4f} "
            f"crop_acc={val_metrics['crop_accuracy']:.4f} "
            f"e2e_acc={val_metrics['end_to_end_accuracy']:.4f}"
        )

        if (
            best_val - val_metrics["loss"]
            > MIN_DELTA
        ):
            best_val = val_metrics["loss"]
            best_epoch = epoch
            patience_left = PATIENCE

            save_state_dict(
                model,
                ckpt,
            )

        else:
            patience_left -= 1

        if patience_left <= 0:
            print(
                f"Early stopping at epoch {epoch}."
            )
            break

    train_seconds = time.time() - start

    unwrap_model(model).load_state_dict(
        torch.load(
            ckpt,
            map_location=DEVICE,
        )
    )

    test_result = evaluate_hierarchical_test(
        model,
        test_loader,
        test_ds,
    )

    ci = bootstrap_ci(
        test_result["global_true"],
        test_result["global_pred"],
        n_classes=len(test_ds.global_classes),
    )

    latency = benchmark_t4_latency(model)

    result = {
        "experiment": exp_name,
        "family": "hierarchical",
        "backbone": backbone_key,
        "variant": variant,

        "best_epoch": best_epoch,
        "training_seconds": train_seconds,

        "parameters": count_parameters(model),
        "checkpoint_mb": checkpoint_size_mb(ckpt),

        "test_stage1_accuracy":
            test_result["crop"]["accuracy"],
        "test_stage1_macro_f1":
            test_result["crop"]["macro_f1"],

        "test_potato_oracle_accuracy":
            test_result["oracle_per_crop"]["potato"]["accuracy"],
        "test_potato_oracle_macro_f1":
            test_result["oracle_per_crop"]["potato"]["macro_f1"],

        "test_rice_oracle_accuracy":
            test_result["oracle_per_crop"]["rice"]["accuracy"],
        "test_rice_oracle_macro_f1":
            test_result["oracle_per_crop"]["rice"]["macro_f1"],

        "test_tomato_oracle_accuracy":
            test_result["oracle_per_crop"]["tomato"]["accuracy"],
        "test_tomato_oracle_macro_f1":
            test_result["oracle_per_crop"]["tomato"]["macro_f1"],

        "test_accuracy":
            test_result["end_to_end"]["accuracy"],
        "test_balanced_accuracy":
            test_result["end_to_end"]["balanced_accuracy"],
        "test_macro_precision":
            test_result["end_to_end"]["macro_precision"],
        "test_macro_recall":
            test_result["end_to_end"]["macro_recall"],
        "test_macro_f1":
            test_result["end_to_end"]["macro_f1"],
        "test_weighted_f1":
            test_result["end_to_end"]["weighted_f1"],
        "test_mcc":
            test_result["end_to_end"]["mcc"],
        "test_cohen_kappa":
            test_result["end_to_end"]["cohen_kappa"],

        **ci,
        **latency,
    }

    # Save every held-out test prediction to support paired statistical tests
    # and manual error analysis.
    prediction_rows = []

    for idx, (yt, yp, conf) in enumerate(
        zip(
            test_result["global_true"],
            test_result["global_pred"],
            test_result["end_confidences"],
        )
    ):
        sample_path = test_ds.samples[idx][0]

        prediction_rows.append(
            {
                "sample_index": idx,
                "path": sample_path,
                "true_global_idx": int(yt),
                "true_class": test_ds.global_classes[yt],
                "pred_global_idx": int(yp),
                "pred_class": test_ds.global_classes[yp],
                "confidence": float(conf),
                "correct": int(yt == yp),
            }
        )

    pd.DataFrame(prediction_rows).to_csv(
        PREDICTION_ROOT / f"{exp_name}_test_predictions.csv",
        index=False,
    )

    # Save raw results
    (
        exp_dir / "history.json"
    ).write_text(
        json.dumps(history, indent=2)
    )

    save_history_csv(
        history,
        TABLE_ROOT / f"{exp_name}_history.csv",
    )

    (
        exp_dir / "result.json"
    ).write_text(
        json.dumps(result, indent=2)
    )

    (
        exp_dir / "stage1_report.json"
    ).write_text(
        json.dumps(
            test_result["crop_report"],
            indent=2,
        )
    )

    (
        exp_dir / "end_to_end_report.json"
    ).write_text(
        json.dumps(
            test_result["global_report"],
            indent=2,
        )
    )

    for crop in CROPS:
        (
            exp_dir
            / f"stage2_{crop}_report.json"
        ).write_text(
            json.dumps(
                test_result[
                    "per_crop_report"
                ][crop],
                indent=2,
            )
        )

    np.save(
        exp_dir / "stage1_crop_cm.npy",
        test_result["crop_cm"],
    )

    np.save(
        exp_dir / "end_to_end_cm.npy",
        test_result["global_cm"],
    )

    for crop in CROPS:
        np.save(
            exp_dir / f"stage2_{crop}_cm.npy",
            test_result["per_crop_cm"][crop],
        )

    # --------------------------------------------
    # Figures for ALL hierarchical experiments
    # --------------------------------------------
    epochs = [
        h["epoch"] for h in history
    ]

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["loss"]
                for h in history
            ],
            "Validation": [
                h["val"]["loss"]
                for h in history
            ],
        },
        f"{exp_name}: total hierarchical loss",
        "Epoch",
        "Loss",
        FIG_ROOT / f"{exp_name}_total_loss_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training crop loss": [
                h["train"]["crop_loss"]
                for h in history
            ],
            "Validation crop loss": [
                h["val"]["crop_loss"]
                for h in history
            ],
        },
        f"{exp_name}: crop-routing loss",
        "Epoch",
        "Crop loss",
        FIG_ROOT / f"{exp_name}_crop_loss_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training disease loss": [
                h["train"]["disease_loss"]
                for h in history
            ],
            "Validation disease loss": [
                h["val"]["disease_loss"]
                for h in history
            ],
        },
        f"{exp_name}: disease-classification loss",
        "Epoch",
        "Disease loss",
        FIG_ROOT / f"{exp_name}_disease_loss_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["crop_accuracy"]
                for h in history
            ],
            "Validation": [
                h["val"]["crop_accuracy"]
                for h in history
            ],
        },
        f"{exp_name}: Stage-1 crop-router accuracy",
        "Epoch",
        "Accuracy",
        FIG_ROOT / f"{exp_name}_stage1_accuracy_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["end_to_end_accuracy"]
                for h in history
            ],
            "Validation": [
                h["val"]["end_to_end_accuracy"]
                for h in history
            ],
        },
        f"{exp_name}: true end-to-end accuracy",
        "Epoch",
        "Accuracy",
        FIG_ROOT / f"{exp_name}_end_to_end_accuracy_curve.png",
    )

    save_line_plot(
        epochs,
        {
            "Training": [
                h["train"]["end_to_end_macro_f1"]
                for h in history
            ],
            "Validation": [
                h["val"]["end_to_end_macro_f1"]
                for h in history
            ],
        },
        f"{exp_name}: true end-to-end Macro-F1",
        "Epoch",
        "Macro-F1",
        FIG_ROOT / f"{exp_name}_end_to_end_macro_f1_curve.png",
    )

    # Crop-specific Stage-2 accuracy curves
    for crop in CROPS:
        key = f"{crop}_accuracy"

        save_line_plot(
            epochs,
            {
                "Training": [
                    h["train"][key]
                    for h in history
                ],
                "Validation": [
                    h["val"][key]
                    for h in history
                ],
            },
            f"{exp_name}: Stage-2 {crop.title()} disease accuracy",
            "Epoch",
            "Accuracy",
            FIG_ROOT
            / f"{exp_name}_stage2_{crop}_accuracy_curve.png",
        )

    # Stage-1 confusion matrices
    plot_confusion_matrix(
        test_result["crop_cm"],
        [c.title() for c in CROPS],
        f"{exp_name}: Stage-1 crop-router confusion matrix",
        FIG_ROOT
        / f"{exp_name}_stage1_confusion_matrix_counts.png",
        normalize=False,
    )

    plot_confusion_matrix(
        test_result["crop_cm"],
        [c.title() for c in CROPS],
        f"{exp_name}: normalized Stage-1 crop-router confusion matrix",
        FIG_ROOT
        / f"{exp_name}_stage1_confusion_matrix_normalized.png",
        normalize=True,
    )

    # Stage-2 crop-wise confusion matrices + metrics
    for crop in CROPS:
        labels = test_ds.crop_classes[crop]
        cm = test_result["per_crop_cm"][crop]
        report = test_result["per_crop_report"][crop]

        plot_confusion_matrix(
            cm,
            labels,
            f"{exp_name}: Stage-2 {crop.title()} confusion matrix",
            FIG_ROOT
            / f"{exp_name}_stage2_{crop}_confusion_matrix_counts.png",
            normalize=False,
        )

        plot_confusion_matrix(
            cm,
            labels,
            f"{exp_name}: normalized Stage-2 {crop.title()} confusion matrix",
            FIG_ROOT
            / f"{exp_name}_stage2_{crop}_confusion_matrix_normalized.png",
            normalize=True,
        )

        metric_df = plot_per_class_metrics(
            report,
            labels,
            f"{exp_name}: Stage-2 {crop.title()} per-class metrics",
            FIG_ROOT
            / f"{exp_name}_stage2_{crop}_per_class_metrics.png",
        )

        metric_df.to_csv(
            TABLE_ROOT
            / f"{exp_name}_stage2_{crop}_per_class_metrics.csv",
            index=False,
        )

    # End-to-end confusion matrix
    plot_confusion_matrix(
        test_result["global_cm"],
        test_ds.global_classes,
        f"{exp_name}: true end-to-end confusion matrix",
        FIG_ROOT
        / f"{exp_name}_end_to_end_confusion_matrix_counts.png",
        normalize=False,
    )

    plot_confusion_matrix(
        test_result["global_cm"],
        test_ds.global_classes,
        f"{exp_name}: normalized true end-to-end confusion matrix",
        FIG_ROOT
        / f"{exp_name}_end_to_end_confusion_matrix_normalized.png",
        normalize=True,
    )

    # End-to-end class metrics
    e2e_metric_df = plot_per_class_metrics(
        test_result["global_report"],
        test_ds.global_classes,
        f"{exp_name}: true end-to-end per-class metrics",
        FIG_ROOT
        / f"{exp_name}_end_to_end_per_class_metrics.png",
    )

    e2e_metric_df.to_csv(
        TABLE_ROOT
        / f"{exp_name}_end_to_end_per_class_metrics.csv",
        index=False,
    )

    # Confidence distribution
    plot_confidence_distribution(
        test_result["global_true"],
        test_result["global_pred"],
        test_result["end_confidences"],
        f"{exp_name}: true end-to-end confidence distribution",
        FIG_ROOT
        / f"{exp_name}_end_to_end_confidence_distribution.png",
    )

    # Misclassification table
    mis_rows = []

    for yt, yp, conf in zip(
        test_result["global_true"],
        test_result["global_pred"],
        test_result["end_confidences"],
    ):
        if yt != yp:
            mis_rows.append(
                {
                    "true_class":
                        test_ds.global_classes[yt],
                    "predicted_class":
                        test_ds.global_classes[yp],
                    "confidence":
                        conf,
                }
            )

    pd.DataFrame(mis_rows).to_csv(
        TABLE_ROOT
        / f"{exp_name}_misclassifications.csv",
        index=False,
    )

    print("TEST:", result)

    del (
        model,
        train_loader,
        val_loader,
        test_loader,
        train_ds,
        val_ds,
        test_ds,
    )

    gc.collect()
    torch.cuda.empty_cache()

    return result





# ============================================================
# SINGLE-GPU WORKER ENTRY POINT
# ============================================================

def run_memory_preflight():
    """
    Test EfficientNet-B3 with one AMP forward/backward/optimizer step at the
    requested per-model batch size. If BS256 OOMs, the orchestrator uses the
    same BS128 fallback for every model.
    """
    print("\n" + "=" * 90)
    print("BATCH-SIZE MEMORY PREFLIGHT")
    print("=" * 90)
    print("Requested batch size:", BATCH_SIZE)
    print("Visible GPU:", torch.cuda.get_device_name(0))

    try:
        model = FlatClassifier(
            "efficientnet_b3",
            n_classes=16,
        )
        model = maybe_parallel(
            model
        )

        optimizer = make_fast_adamw(
            model
        )

        scaler = torch.cuda.amp.GradScaler(
            enabled=USE_AMP
        )

        model.train()

        images = torch.randn(
            BATCH_SIZE,
            3,
            IMG_SIZE,
            IMG_SIZE,
            device=DEVICE,
        )

        targets = torch.randint(
            0,
            16,
            (BATCH_SIZE,),
            device=DEVICE,
        )

        optimizer.zero_grad(
            set_to_none=True
        )

        with torch.cuda.amp.autocast(
            enabled=USE_AMP
        ):
            logits = model(
                images
            )

            loss = flat_ce(
                logits,
                targets,
            )

        scaler.scale(
            loss
        ).backward()

        scaler.step(
            optimizer
        )

        scaler.update()

        torch.cuda.synchronize()

        peak_gib = (
            torch.cuda.max_memory_allocated()
            / (
                1024 ** 3
            )
        )

        print(
            f"PREFLIGHT PASS: batch={BATCH_SIZE}, "
            f"peak allocated={peak_gib:.2f} GiB"
        )

        return 0

    except torch.cuda.OutOfMemoryError:
        print(
            f"PREFLIGHT OOM: batch={BATCH_SIZE} "
            "does not fit safely on one T4."
        )

        return 42


def run_fasternet_interface_preflight():
    """
    Verify the exact FasterNet-M feature width before any long experiment.
    No training is performed.
    """
    print("\n" + "=" * 90)
    print("FASTERNET FEATURE-INTERFACE PREFLIGHT")
    print("=" * 90)

    model, feat_dim = create_backbone(
        "fasternet_m"
    )

    model = model.to(
        DEVICE
    )

    model.eval()

    with torch.inference_mode():
        x = torch.randn(
            2,
            3,
            IMG_SIZE,
            IMG_SIZE,
            device=DEVICE,
        )

        y = model(
            x
        )

    print(
        "Resolved FasterNet:",
        RESOLVED_BACKBONES["fasternet_m"],
    )
    print(
        "Declared feature dim:",
        feat_dim,
    )
    print(
        "Actual pooled feature shape:",
        tuple(
            y.shape
        ),
    )

    if (
        y.ndim != 2
        or y.shape[1] != feat_dim
    ):
        raise RuntimeError(
            "FasterNet interface preflight failed."
        )

    print(
        "FASTERNET FEATURE INTERFACE: PASS"
    )


def run_selected_experiment():
    exp_name = os.environ[
        "LEAFCARENET_EXPERIMENT"
    ]

    exp_lookup = {
        name: (
            family,
            backbone_key,
            variant,
        )
        for (
            name,
            family,
            backbone_key,
            variant,
        ) in EXPERIMENTS
    }

    if exp_name not in exp_lookup:
        raise KeyError(
            f"Unknown experiment '{exp_name}'."
        )

    (
        family,
        backbone_key,
        variant,
    ) = exp_lookup[
        exp_name
    ]

    print("\n" + "#" * 100)
    print("PARALLEL SINGLE-GPU WORKER")
    print("Experiment:", exp_name)
    print(
        "Visible GPU:",
        torch.cuda.get_device_name(0),
    )
    print(
        "Train batch:",
        BATCH_SIZE,
    )
    print(
        "Eval batch:",
        EVAL_BATCH_SIZE,
    )
    print(
        "DataLoader workers:",
        NUM_WORKERS,
    )
    print(
        "Online augmentation: DISABLED"
    )
    print("#" * 100)

    write_experiment_config(
        exp_name,
        family,
        backbone_key,
        variant,
    )

    if family == "flat":
        result = train_flat_experiment(
            exp_name,
            backbone_key,
        )
    else:
        result = train_hier_experiment(
            exp_name,
            backbone_key,
            variant,
        )

    completion = {
        "experiment": exp_name,
        "batch_size": BATCH_SIZE,
        "eval_batch_size": EVAL_BATCH_SIZE,
        "num_workers": NUM_WORKERS,
        "online_augmentation": False,
        "gpu": torch.cuda.get_device_name(0),
        "result": result,
    }

    (
        OUTPUT_ROOT
        / "WORKER_COMPLETED.json"
    ).write_text(
        json.dumps(
            completion,
            indent=2,
        )
    )

    print(
        "\nWORKER COMPLETED:",
        exp_name,
    )


if __name__ == "__main__":
    mode = os.environ.get(
        "LEAFCARENET_MODE",
        "train",
    )

    if mode == "memory_preflight":
        sys.exit(
            run_memory_preflight()
        )

    if mode == "fasternet_preflight":
        run_fasternet_interface_preflight()
        sys.exit(0)

    run_selected_experiment()
