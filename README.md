# HUMoR Analysis Tool / fUSI Studio

**HUMoR Analysis Tool / fUSI Studio** is a MATLAB-based graphical toolbox for functional ultrasound imaging (fUSI) data analysis.

HUMoR stands for **Hemodynamic Ultrasound Imaging of Molecular Reporters**. The toolbox supports a complete fUSI analysis workflow, including data loading, quality control, preprocessing, percentage signal change (PSC) computation, signal change map (SCM) visualization, masking, atlas registration, group analysis, and functional connectivity.

The toolbox is built around the recommended launcher, `run_fusi_studio.m`, which sets up the MATLAB path and starts the main GUI safely. The main GUI itself is implemented in `fusi_studio.m`, with modular analysis GUIs and helper functions for 2D probe data, step-motor / multi-slice data, and matrix / 3D probe data.

> **Important:** This is research software. All outputs should be manually reviewed before interpretation or publication. Raw movies, QC plots, preprocessing choices, baseline windows, masks, ROI traces, atlas registrations, group labels, and functional connectivity results must be checked carefully.

---

## User Manual

A detailed user manual is available here:

[Download the HUMoR fUSI Studio User Manual PDF](https://github.com/SonerCgu/HUMOR-Analysis-Tool/raw/main/docs/HUMoR_fUSI_Studio_User_Manual.pdf)

The manual explains installation, expected data formats, QC, preprocessing, SCM visualization, mask editing, registration, group analysis, functional connectivity, output folders, and troubleshooting.

---

## Current Status

The toolbox is currently most complete for the **single-slice 2D probe fUSI workflow**.

Current development status:

- **2D probe / single-slice workflow:** functional and actively tested.
- **Step-motor / 2D motor workflow:** available, but still under development for downstream group analysis and functional connectivity.
- **3D / matrix probe workflow:** partially supported, but not fully validated for all advanced analyses.
- **Functional connectivity:** available as a standalone GUI; group-level FC integration is still being improved.
- **Group analysis:** available for ROI and map workflows; FC-related group functions are still experimental.
- **StimBox / PulsePal / motor scripts:** included as optional acquisition-related scripts, but require hardware-specific configuration.

There may still be bugs, edge cases, or workflow limitations. Please validate outputs carefully.

---

## Platform and MATLAB Compatibility

Developed and tested mainly on:

- **Windows**
- **MATLAB 2017b**
- **MATLAB 2023b**

Windows is currently the preferred platform. The analysis GUI has been written with portability in mind where possible, but macOS has not yet been fully tested.

Some acquisition-related scripts use Windows-style serial ports such as `COM9`, `COM8`, or `COM14`. These need platform-specific changes for macOS/Linux systems. PowerPoint export functions may also depend on Microsoft PowerPoint/ActiveX on Windows.

---

## Quick Start

1. Clone or download this repository.
2. Open MATLAB.
3. Navigate to the HUMoR repository folder.
4. Run:

```matlab
run_fusi_studio
```

The recommended launcher is `run_fusi_studio`, not direct execution of `fusi_studio`, because the launcher sets up the MATLAB path and starts the main GUI more safely.

Example on Windows:

```matlab
cd('D:\Github\HUMOR-Analysis-Tool')
run_fusi_studio
```

---

## Recommended Workflow

1. Launch the GUI with `run_fusi_studio`.
2. Click **Load fUSI Data**.
3. Select a `.mat`, `.nii`, or `.nii.gz` file.
4. Confirm the detected probe type and TR.
5. Run **Full QC** before preprocessing.
6. Review QC outputs.
7. Apply only scientifically justified preprocessing.
8. Inspect the dataset using the **Time-Course Viewer**.
9. Generate PSC/SCM maps in the **SCM GUI**.
10. Validate dynamic signal behavior using the **Video & SCM Mask** GUI.
11. Draw or load masks if needed.
12. Register to atlas only after the individual dataset is clean.
13. Use **Group Analysis** and **Functional Connectivity** only after individual datasets pass QC.
14. Export the Studio Log at the end of the analysis.

---

## Main Features

- Load fUSI datasets from `.mat`, `.nii`, and `.nii.gz` files.
- Support `[Y X T]` 2D probe data and `[Y X Z T]` multi-slice / step-motor / 3D-style data.
- Confirm probe type and TR during loading.
- Run quality control for temporal stability, spatial quality, motion, frame-rate artifacts, frequency content, CNR, common-mode behavior, PCA summaries, and reliability.
- Apply preprocessing modules including frame rejection, interpolation, scrubbing, imregdemons correction, motor reconstruction, temporal smoothing, filtering, PCA/ICA denoising, and despiking.
- Compute PSC maps and time courses.
- Visualize SCM overlays with underlay, mask, alpha, threshold, and colormap controls.
- Inspect dynamic fUSI responses using the video GUI.
- Draw and load brain/underlay masks and overlay/signal masks.
- Register data to Allen atlas resources using 2D or 3D registration tools.
- Export ROI time courses, figures, QC outputs, PowerPoint summaries, group bundles, and analysis logs.
- Perform ROI/seed-based functional connectivity analysis.
- Organize group-level ROI and map analyses.

---

## Core Files and Modules

| Module | Main file(s) | Purpose |
|---|---|---|
| Main launcher | `run_fusi_studio.m` | Starts HUMoR/fUSI Studio and sets up the path. |
| Main GUI | `fusi_studio.m` | Central graphical interface and workflow controller. |
| Data loading | `loadFUSIData.m` | Loads `.mat`, `.nii`, and `.nii.gz` fUSI datasets. |
| Path handling | `studio_resolve_paths.m`, `studio_mkdir.m` | Resolves dataset output folders and creates directories. |
| Load options dialog | `studio_load_options_dark_dialog_patch16.m` | Dataset loading options dialog. |
| QC | `qc_fusi.m`, `frameRateQC.m` | Quality-control diagnostics. |
| Frame interpolation | `interpolateRejectedVolumes.m` | Interpolates rejected frames/volumes. |
| Scrubbing | `scrubbing.m` | Detects and interpolates bad frames using DVARS/global signal. |
| Imregdemons preprocessing | `imregdemons_preprocess.m`, `imregdemons_param_gui.m` | Drift/spatial correction preprocessing. |
| Motor reconstruction | `motor.m` | Reconstructs step-motor/multi-slice acquisitions. |
| Temporal smoothing | `temporalsmoothing.m` | Sliding temporal smoothing or block averaging/subsampling. |
| Filtering | `filtering.m` | Butterworth low/high/band-pass filtering. |
| PCA denoising | `pca_denoise.m` | Interactive PCA component inspection/removal. |
| ICA denoising | `ica_denoise.m` | Interactive ICA component inspection/removal. |
| Despiking | `despike.m` | Robust voxel-wise spike detection/interpolation. |
| PSC computation | `computePSC.m` | Computes percentage signal change. |
| Time-course viewer | `fUSI_Live_Studio.m` | Raw/PSC movie and signal inspection. |
| SCM GUI | `SCM_gui.m` | PSC/SCM visualization, ROI traces, masks, underlays, exports. |
| Video GUI | `play_fusi_video_final.m` | Dynamic overlay/underlay/mask visualization. |
| SCM/video setup | `showScmVideoSetupDialog.m` | Underlay and visualization setup dialog. |
| Mask editor | `mask.m` | Draws and saves brain/underlay and overlay/signal masks. |
| Atlas registration launcher | `coreg.m` | Main launcher for 2D/3D atlas registration. |
| 2D coronal registration | `coreg_coronal_2d.m`, `registration_coronal_2d.m` | Manual 2D atlas registration workflow. |
| 3D registration | `coreg_3d.m`, `registration_ccf.m`, `register_data.m`, `interpolate3D.m` | 3D atlas registration workflow. |
| Registration application | `apply_coronal_registration_to_map.m`, `apply_reg2d_to_stack.m` | Applies saved 2D registration to maps/stacks. |
| Atlas underlay export | `save_atlas_underlays_from_reg2d.m` | Saves atlas underlays from 2D registration. |
| Segmentation | `Segmentation.m` | Segmentation-related workflow; still experimental in some contexts. |
| Functional connectivity | `FunctionalConnectivity.m` | Seed/ROI/pair/graph functional connectivity analysis. |
| Group analysis | `GroupAnalysis.m`, `GroupAnalysis_Common.m`, `GroupAnalysis_FC.m`, `GroupAnalysis_Map.m` | Group-level ROI, map, and FC workflows. |
| Colormaps | `blackbdy_iso.m`, `winter_brain_fsl.m` | SCM/FC visualization colormaps. |
| Trigger/acquisition scripts | `vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_*.m` | Optional StimBox/PulsePal/motor acquisition-related scripts. |

---

## Expected Data Formats

### MATLAB `.mat`

Preferred image variable:

```matlab
I
```

Typical dimensions:

```matlab
I = [Y X T]       % 2D probe / single-slice time series
I = [Y X Z T]     % multi-slice, step-motor, matrix, or 3D time series
```

Useful optional metadata fields include TR, sampling rate, time vector, baseline information, probe information, masks, and acquisition parameters.

### NIfTI `.nii` / `.nii.gz`

NIfTI files are supported, but orientation, dimensions, TR, and total duration should always be checked manually after loading.

### Step-Motor / Split Files

For split step-motor data, use consistent naming such as:

```text
slice1_t001.mat
slice2_t001.mat
slice3_t001.mat
```

Always verify frames per slice, number of slices, trimming, and reconstruction settings.

---

## Recommended Output Folder Structure

Raw data should remain untouched and separate from generated analysis outputs.

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

Do not overwrite raw data. Each preprocessing step should create a new dataset version. Always check the active dataset dropdown before visualization, registration, group analysis, or functional connectivity.

---

## PSC Logic

PSC is computed relative to a baseline window:

```text
PSC(t) = 100 * (I(t) - baseline) / baseline
```

A poor baseline affects every PSC frame. Always inspect the raw movie, global signal, and ROI traces around the baseline window before exporting maps.

---

## Quality-Control Checklist

Before treating a dataset as analysis-ready:

- Raw movie inspected.
- Probe type and TR confirmed.
- Total duration matches acquisition/stimulation/injection log.
- Baseline window is stable and biologically appropriate.
- Frame outliers are reviewed.
- Interpolation/scrubbing choices are justified.
- Filtering or PCA/ICA removal is scientifically justified.
- Preprocessing choices are consistent across animals when used for group analysis.
- SCM map is anatomically and temporally plausible.
- ROI trace matches expected timing.
- Mask and underlay align with the displayed slice.
- Atlas registration is visually inspected before atlas labels are trusted.
- Group labels, sessions, and conditions are checked before statistics.
- Studio Log is exported.

---

## Repository Structure

Recommended repository structure:

```text
HUMOR-Analysis-Tool/
  README.md
  docs/
    HUMoR_fUSI_Studio_User_Manual.pdf
  Icon.png
  run_fusi_studio.m
  fusi_studio.m
  loadFUSIData.m
  qc_fusi.m
  computePSC.m
  SCM_gui.m
  play_fusi_video_final.m
  mask.m
  GroupAnalysis*.m
  FunctionalConnectivity.m
  registration*.m
  coreg*.m
  vfUSI_StimBox*.m
```

For now, the MATLAB files are intentionally kept mostly in the root folder to avoid breaking path-dependent GUI calls. The user manual is stored in `docs/`. `Icon.png` is kept in the root folder because the GUI uses it from the toolbox root.

---

## Repository Hygiene

Do **not** commit generated analysis outputs or animal/session data to the source-code repository.

Keep these outside GitHub unless they are tiny curated examples:

```text
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
*.nii
*.nii.gz
*.mat
*.mp4
*.avi
*.pptx
```

Large atlas resources, such as `allen_brain_atlas.mat`, should ideally be handled using Git LFS, release assets, institutional storage, or separate download instructions rather than repeatedly committed into normal Git history.

---

## Suggested Citation / Acknowledgment

This toolbox is under active development. If you use or adapt it, please cite or acknowledge the author/developer and repository as appropriate. A formal citation can be added once the toolbox or associated manuscript is published.

---

## Author

**Soner Caner Cagun**  
PhD Student  
Max Planck Institute for Biological Cybernetics  
Molecular Signaling Lab  
Supervisor: Robert Ohlendorf  
Tuebingen, Germany

---

## Disclaimer

This toolbox is provided for research and development purposes. It is not medical software. Results should be validated independently and interpreted in the context of the experimental design, acquisition quality, preprocessing decisions, and biological question.
