function fusi_video_main()
% fusi_video_main
% ============================================================
% Main entry point for fUSI video / SCM analysis
%
% Supports:
%   - Linear probe  : [Y X T]
%   - Matrix probe  : [Y X Z T]
%
% Time + volume semantics (IMPORTANT):
%   - nVols  == number of PSC time frames (T)
%   - Tmax   == (nVols-1) * TR_eff
%   - Z is NEVER treated as volume count
%
% Author: Soner Caner Cagun
% Integration / cleanup: Naman Jain
% ============================================================

clearvars;
close all;
clc;

%% ===================== USER DEFAULTS =====================
fallbackTR = 0.3;
initialFPS = 10;
maxFPS     = 240;

%% ===================== FILE SELECTION =====================
startPath = 'Z:\fUS\Project_PACAP_AVATAR_SC';

[file,path] = uigetfile( ...
    {'*.nii;*.mat','fUS data (*.nii, *.mat)'}, ...
    'Select fUS data file', startPath);

if isequal(file,0)
    error('No file selected.');
end

dataFile = fullfile(path,file);

%% ===================== LOAD DATA =====================
[data, meta] = loadFUSIData(dataFile, fallbackTR);

I_raw = data.I;
TR0   = data.TR;

isMatrixProbe = (ndims(I_raw) == 4);

fprintf('\n=========== Dataset Summary ===========\n');
fprintf('File:   %s\n', file);
if isMatrixProbe
    fprintf('System: Matrix Probe (4D Volumetric)\n');
else
    fprintf('System: Linear Probe (2D)\n');
end
fprintf('Dims:   [%s]\n', num2str(size(I_raw)));
fprintf('TR:     %.3f s\n', TR0);
fprintf('=======================================\n');

%% ===================== RESTORE PARAMETERS =====================
par      = struct();
baseline = struct();

if isfield(meta,'loadedPar') && ~isempty(meta.loadedPar)
    par = meta.loadedPar;
end
if isfield(meta,'loadedBaseline') && ~isempty(meta.loadedBaseline)
    baseline = meta.loadedBaseline;
end

% ---- defaults ----
par = setDefault(par,'interpol',1);
par = setDefault(par,'LPF',0);
par = setDefault(par,'HPF',0);
par = setDefault(par,'conectSize',5);
par = setDefault(par,'conectLev',20);
par = setDefault(par,'gaussSize',0);
par = setDefault(par,'gaussSig',0);
par = setDefault(par,'previewCaxis',[0 100]);
par.matrixProbe = isMatrixProbe;

baseline = setDefault(baseline,'mode','sec');
baseline = setDefault(baseline,'start',0);
baseline = setDefault(baseline,'end',60);

%% ============================================================
% 1) QC — ORIGINAL DATA
%% ============================================================
QC = frameRateQC(I_raw, TR0, 'ORIGINAL', true);
fprintf('\n[QC] ORIGINAL rejected total: %d (%.2f%%)\n', nnz(QC.outliers), QC.rejPct);
waitForQC(QC);

%% ============================================================
% 2) PREPROCESSING STRATEGY
%% ============================================================
preprocMode = 'none';

choice = questdlg( ...
    sprintf(['QC completed on ORIGINAL data.\n\n' ...
             'Choose preprocessing strategy:\n\n' ...
             '• Interpolation: QC-based spike correction\n' ...
             '• Robust subsampling: median-based slow-trend extraction\n' ...
             '• None: use raw data']), ...
    'Preprocessing strategy', ...
    'Interpolation (QC-based)', ...
    'Robust subsampling (Gabriel)', ...
    'None', ...
    'Interpolation (QC-based)');

if isempty(choice), choice = 'None'; end

switch choice
    case 'Interpolation (QC-based)'
        preprocMode = 'interpolation';
    case 'Robust subsampling (Gabriel)'
        preprocMode = 'gabriel';
    otherwise
        preprocMode = 'none';
end

if ~strcmp(preprocMode,'gabriel')
    par = preproc_param_gui(par);
else
    fprintf('[Gabriel] NOTE: LPF/HPF + temporal interpolation disabled.\n');
end

%% ============================================================
% 3) APPLY PREPROCESSING
%% ============================================================
I_interp = I_raw;
I_proc   = I_raw;
QC_after = QC;

applyRejection = false;
TR = TR0;

if strcmp(preprocMode,'interpolation') && nnz(QC.outliers) > 0
    doInterp = questdlg( ...
        sprintf('QC detected %d unstable volumes.\nInterpolate?', nnz(QC.outliers)), ...
        'Frame-rate QC', 'Yes','No','No');

    if strcmp(doInterp,'Yes')
        I_interp = interpolateRejectedVolumes(I_raw, QC.outliers);
        QC_after = frameRateQC(I_interp, TR, 'INTERPOLATED', true);
        waitForQC(QC_after);
        I_proc = I_interp;
        applyRejection = true;
    end
end

if strcmp(preprocMode,'gabriel')
    answ = inputdlg('Subsampling factor (nsub):', ...
        'Gabriel robust subsampling', 1, {'50'});
    if isempty(answ), error('Gabriel cancelled'); end

    opts.nsub      = str2double(answ{1});
    opts.regSmooth = 1.3;
    opts.saveQC    = true;
    opts.showQC    = true;
    opts.qcDir     = fullfile(path,'gabriel_QC');

    G = gabriel_preprocess(I_raw, TR0, opts);
    waitForQC(G.QC);

    I_proc = G.I;
    I_interp = I_proc;

    TR = G.blockDur;
    applyRejection = false;
end

%% ============================================================
% 4) COMPUTE PSC (ONCE)
%% ============================================================
proc = computePSC(I_proc, TR, par, baseline);

PSC    = proc.PSC;
bgFull = proc.bg;
TR_gui = proc.TR_eff;

% ---- PSC time semantics (CRITICAL FIX) ----
nVols = size(PSC, ndims(PSC));        % ALWAYS T dimension
Tmax  = (nVols - 1) * TR_gui;

fprintf('PSC frames: %d\n', nVols);
fprintf('PSC duration: %.2f min\n', Tmax/60);

%% ============================================================
% 5) VISUALIZATION MODE
%% ============================================================
visMode = questdlg( ...
    'Choose output mode', ...
    'Visualization', ...
    'Video GUI', ...
    'Static SCM', ...
    'Exit', ...
    'Video GUI');

if isempty(visMode) || strcmp(visMode,'Exit')
    return;
end

%% ============================================================
% 6) LAUNCH
%% ============================================================

switch visMode

    case 'Video GUI'
        play_fusi_video_final( ...
            I_raw, I_interp, PSC, bgFull, ...
            par, initialFPS, maxFPS, ...
            TR_gui, Tmax, baseline, ...
            meta.loadedMask, meta.loadedMaskIsInclude, ...
            nVols, applyRejection, safeQC(QC_after), file );

    case 'Static SCM'
        SCM_gui( ...
            PSC, bgFull, TR_gui, par, baseline, ...
            I_raw, I_interp, initialFPS, maxFPS, ...
            meta.loadedMask, meta.loadedMaskIsInclude, ...
            applyRejection, safeQC(QC_after), file );
end

end

%% ===================== HELPERS =====================
function QCx = safeQC(QC_in)
if isempty(QC_in)
    QCx = struct('outliers',[],'rejPct',0,'thresholdLow',[],'thresholdHigh',[],'sigma',[]);
else
    QCx = QC_in;
end
end

function s = setDefault(s,field,val)
if ~isfield(s,field) || isempty(s.(field))
    s.(field) = val;
end
end

function waitForQC(QC)
if isfield(QC,'figIntensity') && ~isempty(QC.figIntensity) && ishandle(QC.figIntensity)
    waitfor(QC.figIntensity);
end
if isfield(QC,'figRejected') && ~isempty(QC.figRejected) && ishandle(QC.figRejected)
    waitfor(QC.figRejected);
end
end
