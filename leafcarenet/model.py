# -*- coding: utf-8 -*-
"""
LeafCareNet: Hierarchical Decoupled Foliar Crop Disease Recognition Model.

Architecture Specifications:
- Feature Backbone: MobileNetV2 (timm: mobilenetv2_100.ra_in1k, Feature Dimension = 1280)
- Coarse Stage-1 Crop Router: Linear(1280 -> 3) [0: Potato, 1: Rice, 2: Tomato]
- Decoupled Stage-2 Disease Heads:
    - Potato Head: Linear(1280 -> 3)  [Early Blight, Late Blight, Healthy]
    - Rice Head:   Linear(1280 -> 5)  [Bacterial Blight, Brown Spot, Healthy, Leaf Blast, Sheath Blight]
    - Tomato Head: Linear(1280 -> 8)  [Bacterial Spot, Early Blight, Late Blight, Leaf Mold, Spider Mites, TYLCV, Mosaic Virus, Healthy]
- Total Model Parameters: 2,248,211 (100% strict match with checkpoint 05_leafcarenet_best.pth)
"""

import os
import torch
import torch.nn as nn
import timm

CANONICAL_CROPS = ["Potato", "Rice", "Tomato"]

CANONICAL_16_CLASSES = [
    # Potato (indices 0..2)
    "Potato___Early_blight",
    "Potato___Late_blight",
    "Potato___healthy",
    # Rice (indices 3..7)
    "Rice___Bacterial_Leaf_Blight",
    "Rice___Brown_Spot",
    "Rice___Healthy_Leaf",
    "Rice___Leaf_Blast",
    "Rice___Sheath_Blight",
    # Tomato (indices 8..15)
    "Tomato___Bacterial_spot",
    "Tomato___Early_blight",
    "Tomato___Late_blight",
    "Tomato___Leaf_Mold",
    "Tomato___Spider_mites_Two_spotted_spider_mite",
    "Tomato___Tomato_YellowLeaf_Curl_Virus",
    "Tomato___Tomato_mosaic_virus",
    "Tomato___healthy",
]

# Offsets mapping each crop's local disease index to the canonical 16-class index
CROP_GLOBAL_OFFSETS = [0, 3, 8]
CROP_CLASS_COUNTS = [3, 5, 8]


class LinearDiseaseHead(nn.Module):
    """Linear classifier head for crop-specific foliar disease categorization."""
    def __init__(self, in_features: int, num_classes: int):
        super().__init__()
        self.fc = nn.Linear(in_features, num_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.fc(x)


class HierarchicalClassifier(nn.Module):
    """
    LeafCareNet Hierarchical Classifier.
    Decouples coarse crop category routing from fine-grained foliar disease identification.
    """
    def __init__(
        self,
        backbone_name: str = "mobilenetv2_100.ra_in1k",
        crop_class_counts: list = None,
        pretrained: bool = False,
    ):
        super().__init__()
        if crop_class_counts is None:
            crop_class_counts = CROP_CLASS_COUNTS

        self.backbone = timm.create_model(
            backbone_name,
            pretrained=pretrained,
            num_classes=0,
            global_pool="avg",
        )
        self.feat_dim = int(self.backbone.num_features)  # 1280

        # Stage 1: Coarse Crop Router
        self.crop_router = nn.Linear(self.feat_dim, len(crop_class_counts))

        # Stage 2: Decoupled Crop-Specific Disease Heads
        self.disease_heads = nn.ModuleList([
            LinearDiseaseHead(self.feat_dim, n) for n in crop_class_counts
        ])

    def forward(self, x: torch.Tensor):
        """
        Forward pass returning raw logits for training and calibration:
        - crop_logits: [B, 3]
        - disease_logits: list of tensors [[B, 3], [B, 5], [B, 8]]
        """
        feat = self.backbone(x)
        crop_logits = self.crop_router(feat)
        disease_logits = [head(feat) for head in self.disease_heads]
        return crop_logits, disease_logits

    def predict_global(self, x: torch.Tensor):
        """
        End-to-end inference returning predicted crop, predicted disease,
        confidence scores, and mapped canonical 16-class global indices.
        """
        crop_logits, disease_logits = self.forward(x)
        crop_probs = torch.softmax(crop_logits, dim=-1)
        pred_crops = torch.argmax(crop_probs, dim=-1)

        batch_size = x.shape[0]
        global_preds = torch.empty(batch_size, dtype=torch.long, device=x.device)
        confidences = torch.empty(batch_size, dtype=torch.float32, device=x.device)

        for i in range(batch_size):
            c = pred_crops[i].item()
            d_logits = disease_logits[c][i]
            d_probs = torch.softmax(d_logits, dim=-1)
            pred_d = torch.argmax(d_probs).item()
            global_preds[i] = CROP_GLOBAL_OFFSETS[c] + pred_d
            confidences[i] = crop_probs[i, c].item() * d_probs[pred_d].item()

        return pred_crops, global_preds, confidences


def create_leafcarenet(checkpoint_path: str = None, pretrained: bool = False) -> HierarchicalClassifier:
    """Instantiate LeafCareNet and optionally load verified checkpoint."""
    model = HierarchicalClassifier(pretrained=pretrained)
    if checkpoint_path and os.path.exists(checkpoint_path):
        state_dict = torch.load(checkpoint_path, map_location="cpu")
        res = model.load_state_dict(state_dict, strict=True)
        print(f"Loaded LeafCareNet weights from {checkpoint_path}: {res}")
    return model


if __name__ == "__main__":
    model = create_leafcarenet()
    n_params = sum(p.numel() for p in model.parameters())
    print(f"LeafCareNet initialized. Total parameters: {n_params:,}")
    assert n_params == 2248211, f"Parameter count mismatch: {n_params} != 2,248,211"
    x = torch.randn(2, 3, 224, 224)
    c_logits, d_logits = model(x)
    print("Crop logits shape:", c_logits.shape)
    print("Disease logits shapes:", [d.shape for d in d_logits])
    crops, preds, confs = model.predict_global(x)
    print("Global predictions:", preds, "Confidences:", confs)
    print("Self-test PASSED successfully!")
