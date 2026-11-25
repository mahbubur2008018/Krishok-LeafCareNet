# D2 External Generalization Benchmark: Sampling Methodology

**Seed:** 42  
**RNG:** NumPy Permuted Congruential Generator (`numpy.random.PCG64`)  
**Total Images:** Exactly 2,337 field images  
**Class Count:** 16 canonical categories  

To guarantee unbiased out-of-domain evaluation, images were sampled without replacement from 8 public datasets using stratified quotas. Full details and verified DOIs are listed in `DATASET_DOI_AND_SOURCE_REGISTRY.csv`.