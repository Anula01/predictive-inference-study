# Certain Minds in an Uncertain World? Computational signatures of belief updating in individuals holding radical attitudes

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)

Analysis code and data for the study **"Certain Minds in an Uncertain World? Exploring Computational Signatures of Belief Updating in Individuals Holding Radical Attitudes"** (Knorr, Podolin, Starlinger, Kossowska & Mikuš).

- Preprint: TODO (PsyArXiv link / DOI)
- Paper: TODO (journal DOI, after publication)
- Task code (separate repository): https://github.com/Anula01/predictive-inference-task

## Overview

We tested how two dimensions of radical political attitudes, dogmatic intolerance and authoritarianism, relate to learning under uncertainty in a politically neutral predictive-inference task. 462 US adults (recruited via Prolific) were analysed. They completed 300 trials of a [predictive-inference task](https://github.com/Anula01/predictive-inference-task) in which they positioned a bucket to catch a particle, reported their confidence of catching it, and received feedback. Observational noise and occasional changes of the latent mean were manipulated.

The analyses cover:

- exploratory factor analysis of the attitude measures (dogmatic intolerance, authoritarianism, political orientation),
- model-agnostic behaviour: mean inference, learning rate, confidence, metacognitive sensitivity and calibration,
- computational modelling with the extended hierarchical Gaussian filter of Mikuš et al. (2025), and its association with radical attitudes.

The study and analyses were exploratory and were not preregistered.

## Task settings

| Setting | Value |
|---------|-------|
| Trials | 300 (3 blocks of 100) |
| Bucket size | 36° |
| Observational noise (SD of particle landing location) | 12° (low noise), 21° (high noise) |
| Probability of a change in the latent mean (per eligible trial) | .10 |
| Minimum trials between mean changes | 3 |
| Minimum distance of a new mean from the previous mean | 12° |
| Probability that the noise level switches at a mean change | .40 |
| Confidence scale | 5–100%, steps of 5 (initial slider position randomized between 10% and 90%) |

## Repository structure

```
.
|-- CITATION.cff
|-- LICENSE                                  # MIT (code)
|-- README.md
|-- code/
|   |-- R/                                   # R project root (renv); run all R code from here
|       |-- Analysis.Rproj
|       |-- .Rprofile                        # activates renv
|       |-- renv.lock                        # package versions
|       |-- renv/                            # renv setup
|       |-- 01 Preprocessing.qmd             # raw exports -> cleaned files (needs raw data, not released)
|       |-- 02 Data Checks.Rmd               # data quality checks (needs raw data, not released)
|       |-- 03 Descriptives.Rmd              # descriptive statistics
|       |-- 04 Factor and composite scores.Rmd   # scale composites, factor analysis (needs item-level data, not released)
|       |-- 05 Main analyses.Rmd             # behavioural and HGF analyses (runs from the released files)
|       |-- helper_functions.R               # helper functions, including run_models()
|       |-- models/
|           |-- ehgf_jget_full.stan          # Stan implementation of the extended HGF
|           |-- ModelEstimationWrapper.R     # fits the model to the trial-level data
|-- data/
    |-- LICENSE.md                           # CC BY 4.0 (data)
    |-- L122136/
        |-- cleaned/
            |-- modelling_data.csv           # trial-level task data
            |-- composites_data.csv          # participant-level attitude composites, factor scores, demographics
            |-- HGF_Model_output.csv         # fitted HGF parameters per participant
            |-- Ehgf_taskData2.csv           # HGF belief trajectories per trial
```

## Data

Only the analysis files listed above are shared. Raw exports, item-level questionnaire responses (including clinical symptom measures), free-text answers, timestamps, mood ratings and pilot data are not shared to protect participants' privacy. Participant identifiers were replaced by random study IDs (`S001`, `S002`, ...), which are consistent across all files; Prolific IDs are not included and the mapping is not published.

| File | Level | Participants | Rows | Content |
|------|-------|--------------|------|---------|
| `modelling_data.csv` | trial | 467 | 297 per participant | task variables and responses, plus derived variables used for modelling |
| `composites_data.csv` | participant | 462 | 1 per participant | attitude scale composites and factor scores, demographics |
| `HGF_Model_output.csv` | participant | 467 | 1 per participant | fitted HGF parameters |
| `Ehgf_taskData2.csv` | trial | 467 | 297 per participant | task data and HGF belief trajectories |

The trial-level files and the HGF file contain 467 participants, `composites_data.csv` contains the 462 participants analysed in the paper. The five additional participants have task data but no attitude data and are not part of the analyses. Every participant has 297 trials in the trial-level files (TODO: state why, for example "the first three of the 300 trials are not used").

### Variables

`modelling_data.csv` (and, with HGF additions, `Ehgf_taskData2.csv`):

| Variable | Description |
|----------|-------------|
| `subject_id` | pseudonymous participant ID (`S001`, ...), used to join the files |
| `Stage` | task block (TODO: confirm coding) |
| `ID` | trial number within the task (TODO: confirm) |
| `Mean` | true latent mean of the generative distribution (degrees) |
| `Angle` | particle landing location (degrees) |
| `Bucket.Position` | participant's bucket position (degrees); called `Bucket_Position` in `Ehgf_taskData2.csv` (TODO: state whether this is the bucket middle) |
| `Caught` | 1 = particle caught, 0 = missed |
| `Noise_Condition` | `Low_Noise` (SD = 12°) or `High_Noise` (SD = 21°) |
| `conf` | confidence of catching the particle (5–100%, steps of 5) |
| `pe` | prediction error (TODO: confirm definition) |
| `action` | participant's update of the bucket position (TODO: confirm definition) |
| `pe_sc`, `action_sc`, `conf_sc` | variable scaled within participant |
| `ranked_PE`, `ranked_action`, `ranked_conf` | variable rank-transformed within participant |
| `pe_rank_sc`, `action_rank_sc`, `conf_rank_sc` | rank-transformed variable, scaled within participant |

`Ehgf_taskData2.csv` additionally contains HGF belief trajectories: `mux1`, `mux2`, `mua` (belief means), `lr1`, `lr2`, `lra` (learning rates) and `sax1`, `sax2`, `saa` (belief uncertainties) (TODO: confirm names and meaning; the suffixes 1 and 2 refer to the model levels and `a` to the action model).

`HGF_Model_output.csv`: `ID` (study ID, corresponds to `subject_id`), `om`, `om2`, `oma` (fitted HGF parameters) and `noise` (fitted noise parameter) (TODO: confirm parameter definitions against the paper).

`composites_data.csv`:

| Variable | Description |
|----------|-------------|
| `subject_id` | pseudonymous participant ID |
| `age`, `gender`, `education` | demographics |
| `lc_gen`, `lc_eco`, `lc_soc` | self-reported political orientation (general, economic, social) (TODO: confirm) |
| `demo_id`, `repub_id` | party identification (Democrat, Republican) (TODO: confirm) |
| `DOG`, `RWA`, `LWA`, `SECS`, `PI`, `BS`, `LC`, `CM`, `IUS` | scale composites (TODO: spell out each abbreviation) |
| `FA_PO`, `FA_DOG`, `FA_AUTH` | factor scores for political orientation, dogmatic intolerance and authoritarianism |

## Reproducing the analyses

Requirements: R 4.5.0 and the package versions recorded in `code/R/renv.lock`.

1. Clone or download this repository.
2. Start R in the folder `code/R/` (for example by opening `Analysis.Rproj` in RStudio), so that `renv` activates.
3. Install the packages with `renv::restore()`.
4. Open `05 Main analyses.Rmd` and knit it, or run all chunks from the top. The chunks depend on each other (the data are loaded in the first chunks), so run them in order. Data paths are relative (`../../data/...`), so run the file from `code/R/`, which is the default when knitting.

Scripts `01`, `02` and `04` need raw or item-level data that cannot be shared, so they are included for transparency but cannot be rerun with this repository. `05 Main analyses.Rmd` runs from the shared files. Its supplementary analysis S1 (mood ratings and recent noise exposure) needs mood ratings that are not shared, so the corresponding code is commented out and S1 cannot be reproduced from the released data.

Main packages: `tidyverse`, `lme4`, `lmerTest`, `parameters`, `effectsize`, `Hmisc`, `HLMdiag`, `BayesFactor`.

TODO: describe how the HGF parameters were estimated (runtime, Stan settings) and how to rerun `models/ModelEstimationWrapper.R` on `modelling_data.csv`.

## Related repositories

**Task:** https://github.com/Anula01/predictive-inference-task (DOI: 10.5281/zenodo.YYYYYYY). This separate repository contains the browser-based implementation of the predictive-inference task that was used to collect the data. The present repository contains only the analysis of the data collected with it.

## Citation

If you use this code or data, please cite the archived version on Zenodo
(DOI: 10.5281/zenodo.XXXXXXX) and the associated paper. Citation metadata
is also provided in CITATION.cff.

## License

- Code: MIT License (see `LICENSE`).
- Data (`data/`): Creative Commons Attribution 4.0 International, CC BY 4.0 (see `data/LICENSE.md`).

This repository contains no third-party datasets.

## Contact

Anna Knorr, Institute of Psychology, Jagiellonian University, Krakow, Poland. anna.knorr@uj.edu.pl
