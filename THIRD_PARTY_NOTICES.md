# Third-Party Notices and Acknowledgements

Krishok–LeafCareNet incorporates and depends upon open-source software, libraries, and public research datasets. This document details the respective licenses and attributions.

---

## 1. Software Libraries & Frameworks

- **PyTorch (BSD-style License)**: Used for neural network architecture definition, training, and benchmarking.
- **TensorFlow / TensorFlow Lite (Apache License 2.0)**: Used for lightweight mobile model execution.
- **Flutter & Dart (BSD-3-Clause License)**: Used for the cross-platform mobile user interface and offline advisory engine.
- **timm (Apache License 2.0)**: PyTorch Image Models library used for comparative baseline architectures.
- **Arduino Core for ESP32 (LGPL-2.1)**: Microcontroller framework for IoT microclimate sensor acquisition.
- **ModbusMaster (MIT License)**: Library for RS-485 Modbus RTU communications with the 7-in-1 NPK sensor.

---

## 2. Public Research Datasets

All public training and evaluation imagery originate from independent public research archives under their respective licenses:

1. **New Plant Diseases Dataset (PlantVillage Re-split)** (Kaggle): Derived from PlantVillage (Hughes & Salathé, 2015).
2. **Rice Leaf Bacterial and Fungal Disease Dataset** (Mendeley Data, DOI: `10.17632/hx6f852hw4.2`): Authored by Mehedi Hasan, Sonia Khatun, Md. Abu Raihan, Abdul Hasib Uddin (CC BY 4.0).
3. **BanglaRiceLeaf Dataset** (Harvard Dataverse, DOI: `10.7910/DVN/XAOBYW`): Authored by Md. Al-Amin, Md. Abu Bakr Siddique, Md. Shahin Ali (CC0 1.0 Universal).
4. **Irish Potato Leaf Disease Dataset** (Zenodo, DOI: `10.5281/zenodo.8286529`): Authored by Hudson Laizer, Neema Mduma, Dina Machuve, Tumaini Lyimo, Claire Babirye, Jenifa Swai, Adam Siwingwa (CC BY 4.0).
5. **Paddy Doctor Challenge Dataset** (Kaggle): Authored by P. Petchiammal, D. Murugan et al.
6. **High Resolution Tomato Leaf Disease Dataset** (Mendeley Data, DOI: `10.17632/74zvtzx9pr.1`): Authored by Puja Bapari, Md Zinnahtur Rahman Zitu, Mst Ummehani.
7. **Tomato Leaf Diseases Detect** (Roboflow Universe): Project maintainer Mohamed Traore.
8. **Tomato Leaf Disease Classification Dataset** (Mendeley Data, DOI: `10.17632/jttrv2w27r.1`): Authored by Nure Alam Siddiki Rachin, Nasim Mahmud Likhon, Md Abdullah Hel Baki.
9. **Tomato Leaf Disease Classification Dataset in Pakistan** (Mendeley Data, DOI: `10.17632/3mbnb82mxd.1`): Authored by Mohammad Naeem Malik, Syed Hashir Ali, Hamid Ali.
10. **Tomato Leaf Image Dataset for Disease Analysis in Real-World Environment** (Mendeley Data, DOI: `10.17632/rnbsw72zb5.1`): Authored by Mangsura Kabir Oni, Tabia Tanzin Prama.

*Note: Raw third-party datasets are not bundled in this source repository. Model code, weights, and evaluation manifests only are distributed in accordance with Apache-2.0.*
