# HUMoR fUSI Studio

**HUMoR** — *Hemodynamic Ultrasound Imaging of Molecular Reporters* — is a MATLAB-based graphical analysis environment for functional ultrasound imaging (fUSI). It is designed for individual-animal inspection, quality control, preprocessing, percentage signal change (PSC) mapping, signal change map (SCM) visualization, masking, atlas registration, group analysis, and functional connectivity workflows.

The toolbox is built around a single entry point, `fusi_studio.m`, with modular analysis GUIs and helper functions for 2D probe data, step-motor / multi-slice data, and matrix / 3D probe data.

> **Research software notice:** HUMoR outputs should always be manually reviewed. QC plots, raw movies, ROI traces, baseline windows, masks, and atlas registrations must be checked before a dataset is treated as analysis-ready or publication-ready.

---

## Main features

- Load raw fUSI data from `.mat`, `.nii`, and `.nii.gz` files.
- Support common fUSI data shapes:
  - 2D time series: `[Y X T]`
  - multi-slice / matrix / 3D time series: `[Y X Z T]`
  - split step-motor files such as `slice1_t001.mat`, `slice2_t001.mat`, etc.
- Confirm probe type and TR at load time.
- Run QC modules for temporal stability, spatial quality, frame-rate artifacts, motion, outliers, CNR, PCA summaries, and reliability.
- Apply preprocessing modules such as frame rejection, scrubbing, imregdemons drift correction, motor reconstruction, temporal smoothing/subsampling, filtering, PCA/ICA, and despiking.
- Compute and visualize PSC maps and ROI time courses.
- Inspect dynamic overlays with the video GUI.
- Draw and load brain/underlay masks and overlay/signal masks.
- Register fUSI data to Allen atlas references using 2D or 3D workflows.
- Run atlas/ROI-based segmentation, group analysis, and functional connectivity workflows where available.
- Export figures, ROI tables, logs, group summaries, and PowerPoint reports.

---

## Requirements

### Required

- MATLAB, tested/developed around MATLAB **2017b** and **2023b** compatibility.
- Windows is the primary supported platform.
- HUMoR source files on the MATLAB path.

### Recommended

- Image Processing Toolbox for registration, masking, filtering, image resizing, and smoothing workflows.
- Microsoft PowerPoint on Windows for direct `.pptx` export.
- `allen_brain_atlas.mat` for atlas registration and atlas-based segmentation.

### Optional

- Trigger-controller scripts for StimBox, PulsePal, and step-motor acquisition workflows.
- Git LFS or release assets for large resources such as atlas `.mat` files.

---

## Installation

Clone the repository or download a clean release ZIP.

```matlab
cd('D:\Github\HUMOR-Analysis-Tool')
addpath(genpath(pwd))
run_fusi_studio
```

For a cleaner MATLAB path, avoid adding backup folders, archive folders, generated output folders, or old parser-error versions of files.

Recommended startup command:

```matlab
clear functions
run_fusi_studio
```

---

## Quick start workflow

1. Start MATLAB in the HUMoR repository folder.
2. Run:

   ```matlab
   run_fusi_studio
   ```

3. Click **Load fUSI Data**.
4. Select a raw `.mat`, `.nii`, or `.nii.gz` file.
5. Confirm the detected probe type and TR.
   - Standard 2D probe default: **320 ms**
   - Matrix / 3D probe default: **480 ms**
   - Use file TR or custom TR only when supported by the acquisition log/metadata.
6. Run **Full QC** or selected QC modules.
7. Review QC outputs before preprocessing.
8. Apply only justified preprocessing steps.
9. Inspect data in **Time-Course Viewer**.
10. Open **SCM** to generate PSC maps, ROI traces, masks, and exports.
11. Use **Video & SCM Mask** and **Mask Editor** to validate dynamic overlays and masks.
12. Register to atlas only after a stable anatomical/underlay reference exists.
13. Use **Group Analysis** and **Functional Connectivity** only after individual datasets pass QC.
14. Export the Studio Log and document all analysis decisions.

---

## Core modules

| GUI button / module | Main file(s) | Purpose |
|---|---|---|
| Launch Studio | `run_fusi_studio.m`, `fusi_studio.m` | Opens the main HUMoR GUI. |
| Load fUSI Data | `loadFUSIData.m` | Loads `.mat`, `.nii`, `.nii.gz`, detects dimensions and metadata/TR candidates. |
| Full / Specific QC | `qc_fusi.m`, `frameRateQC.m` | Produces QC diagnostics for spatial, temporal, frequency, motion, frame-rate, and reliability checks. |
| Frame Rejection | `frameRateQC.m`, `interpolateRejectedVolumes.m` | Detects abnormal frames and interpolates rejected volumes. |
| Imregdemons | `imregdemons_preprocess.m`, wrappers `gabriel_preprocess.m` | Drift/spatial-stability correction workflow. |
| Scrubbing | `scrubbing.m` | Detects and interpolates motion/artifact frames using DVARS/global-signal logic. |
| Motor Reconstruction | `motor.m` | Reconstructs continuous or split step-motor acquisitions into multi-slice data. |
| Temporal smoothing/subsampling | `temporalsmoothing.m` | Sliding smoothing or block subsampling; block mode changes effective TR. |
| Filtering | `filtering.m` | Butterworth low/high/band-pass filtering with QC. |
| PCA / ICA | `pca_denoise.m`, `ica_denoise.m` | Interactive component inspection and removal. |
| Despike | `despike.m` | Voxel-wise robust spike detection/interpolation. |
| Time-Course Viewer | `fUSI_Live_Studio.m` | Raw/PSC movie and time-course inspection. |
| SCM | `computePSC.m`, `SCM_gui.m` | PSC maps, ROI time courses, masks, underlays, and exports. |
| Video & SCM Mask | `play_fusi_video_final.m`, `showScmVideoSetupDialog.m` | Dynamic overlay/underlay/mask visualization. |
| Mask Editor | `mask.m`, `makeBrushMask.m` | Draw and save brain/underlay and overlay/signal masks. |
| Atlas registration | `coreg.m`, `coreg_coronal_2d.m`, `coreg_3d.m`, `registration_ccf.m`, `registration_coronal_2d.m` | 2D/3D manual atlas alignment. |
| Functional Connectivity | `FunctionalConnectivity.m` | Seed, ROI, pair, heatmap, and graph-style connectivity analysis. |
| Group Analysis | `GroupAnalysis.m`, `GroupAnalysis_FC.m`, `GroupAnalysis_Map.m`, `GroupAnalysis_Common.m` | Group/condition organization, ROI summaries, maps, FC summaries, and exports. |

---

## Expected data formats

### MATLAB `.mat`

Preferred image variable:

```matlab
I
```

Typical shapes:

```matlab
I = [Y X T]       % 2D time series
I = [Y X Z T]     % multi-slice / matrix / 3D time series
```

Useful optional metadata fields include TR, sampling rate, time vector, baseline information, probe information, and acquisition parameters.

### NIfTI `.nii` / `.nii.gz`

NIfTI files are loaded through MATLAB NIfTI-reading functionality. Always verify orientation, dimensions, TR, and total duration after loading.

### Step-motor split files

Use consistent naming, for example:

```text
slice1_t001.mat
slice2_t001.mat
slice3_t001.mat
...
```

Motor reconstruction is frame-based. Verify number of slices, frames per slice, trimming, and baseline blocks before reconstruction.

---

## Recommended analysis folder structure

Raw data should stay separate from generated analysis outputs.

```text
RawData/
  <project>/<animal>/<session>/<scan>.mat

AnalysedData/
  <project>/<animal>/<session>/<scan>/
    QC/
    Preprocessing/
    PSC/
    Visualization/
    Masks/
    Registration/
    Registration2D/
    FunctionalConnectivity/
    GroupAnalysis/
    Reports/
```

Do not overwrite raw data. Each preprocessing step should create a new dataset version and the active dataset dropdown should be checked before visualization, registration, group analysis, or FC.

---

## Recommended baseline and PSC logic

PSC is computed per voxel/pixel relative to a baseline window:

```text
PSC(t) = 100 * (I(t) - baseline) / baseline
```

A bad baseline contaminates every PSC frame. Always inspect the raw movie, global signal, and ROI traces around the baseline window before exporting maps.

---

## Quality-control checklist

Before marking a dataset ready for analysis or publication:

- Raw movie inspected.
- Probe type and TR confirmed.
- Total time matches acquisition/stimulation/injection log.
- Baseline window is stable and pre-event.
- Frame outliers reviewed and justified.
- Preprocessing steps are documented and used consistently across animals.
- SCM map is anatomically and temporally plausible.
- ROI trace aligns with stimulus/injection timing.
- Mask and underlay are aligned to the correct slice.
- Atlas registration is visually acceptable before atlas labels are trusted.
- Group labels, conditions, and sessions are checked before statistics.
- Studio Log is exported.

---

## GitHub cleanup and repository hygiene

### Do not commit generated analysis outputs

Generated outputs should stay in `AnalysedData` folders, not in the source-code repository. Add these to `.gitignore`:

```gitignore
# MATLAB/editor noise
*.asv
*.m~
*.autosave
*.slxc
*.mex*

# Generated HUMoR outputs
QC/
Preprocessing/
PSC/
Visualization/
Masks/
Registration/
Registration2D/
FunctionalConnectivity/
GroupAnalysis/
Reports/
AnalysedData/
RawData/

# Dataset-specific MATLAB outputs
*_PSC*.mat
*PSC*.mat
*preprocess*.mat
*Preprocessing*.mat
*Transformation*.mat
*CoronalRegistration2D*.mat
*BrainOnly*.mat
*Mask*.mat
*mask*.mat
*GroupBundle*.mat
*SCM*.mat

# Large resources: prefer Git LFS or release asset
allen_brain_atlas.mat

# Local backups / patch folders
_backup_before_*/
_legacy_unused/
_health_reports/
```

### Large atlas resource

`allen_brain_atlas.mat` is required for atlas registration/segmentation workflows, but it is large. Prefer one of these approaches:

1. Keep it out of normal Git tracking and provide download instructions.
2. Store it with Git LFS.
3. Attach it as a release asset.
4. Keep it in a local `resources/` folder ignored by Git.

### Suggested repository structure

```text
HUMOR-Analysis-Tool/
  README.md
  LICENSE
  run_fusi_studio.m
  fusi_studio.m
  loadFUSIData.m
  core/
  qc/
  preprocessing/
  visualization/
  masking/
  registration/
  advanced/
  trigger_controller/
  resources/
  docs/
  examples/
```

The current flat MATLAB layout can continue working, but a cleaner folder structure is easier to maintain once paths and dependencies are stable.

---

## Files that are usually safe to move out of the active MATLAB path

Move to `archive/`, `examples/`, or `optional/` first. Delete only after testing from a clean MATLAB path.

- Old demo scripts, for example `example01_registering.m`.
- Old GUIDE viewer files, for example `figviewscan.m` and `figviewscan.fig`, unless you still use them manually.
- Old utility/demo helpers not called by the main GUI.
- Old backup folders, parser-error versions, patch scripts, and temporary installer scripts.
- Generated analysis `.mat` files from `Preprocessing`, `PSC`, `Masks`, `Registration`, `Registration2D`, `GroupAnalysis`, and `FunctionalConnectivity`.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Dataset does not load | Unsupported variable name, huge/corrupt file, missing reader, path issue | Inspect variables with `whos -file`, confirm a valid 3D/4D image stack exists. |
| Wrong total time | Incorrect TR/probe type or metadata | Reload and confirm TR from acquisition log. |
| Buttons remain disabled | Data not loaded or GUI state not updated | Reload data and check the Studio Log. |
| SCM map looks wrong | Bad baseline, wrong active dataset, motion, mask/underlay issue | Check dataset dropdown, baseline, raw movie, ROI trace, and mask. |
| Motor reconstruction wrong | Wrong frames per slice/position or split filename mismatch | Verify frame counts, source mode, and naming before reconstruction. |
| PCA/ICA removes response | Biological component selected as artifact | Return to pre-PCA/ICA dataset and rerun with fewer/no removed components. |
| FC looks globally high | Global signal, motion, or non-brain voxels dominate | Use masks, QC, and consider confound strategy before interpreting. |
| Group analysis opens old behavior | Backup files or old modules are on MATLAB path | Keep only current GroupAnalysis files on the active MATLAB path. |

---

## Citation / ownership

Pipeline owner / author: **Soner Caner Cagun**.

Before public release, add a formal `LICENSE` file and preferred citation text. If this repository is private/internal, keep access restricted according to lab policy.
