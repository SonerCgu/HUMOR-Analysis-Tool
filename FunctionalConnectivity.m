function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity.m
% fUSI Studio - Functional Connectivity GUI
% MATLAB 2017b compatible, ASCII-only.
%
% Updated Soner/HUMoR version
% ------------------------------------------------------------
% Fixes included in this full copy-paste version:
%   1) ROI heatmap is larger.
%   2) Graph matrix heatmap is larger.
%   3) Larger gaps between heatmap labels to avoid overlap.
%   4) Compare ROI dropdowns and labels use region abbreviations.
%   5) Pair ROI tab top controls/text are moved down and no longer cut off.
%   6) ROI heatmap no longer shows subject name.
%   7) Graph tab removes degree plot and degree text.
%   8) Vertical heatmap legends are reversed correctly: +1/high at top, -1/low at bottom.
%   9) File pickers robustly start in Registration folder via temporary cd().
%  10) Underlay remains separated from ROI labels.
%  11) Can load HUMoR Segmentation.mat region-time outputs directly into ROI FC.
%
% INPUT
%   dataIn:
%       numeric [Y X T] or [Y X Z T]
%       struct with fields I / PSC / data / functional / func / movie / volume
%       cell array or struct array for multiple subjects
%
% OPTIONAL opts fields:
%   .functionalField
%   .roiNames
%   .roiNameTable
%   .roiMinVox
%   .seedBoxSize
%   .chunkVox
%   .askMaskAtStart
%   .askAtlasAtStart
%   .debugRethrow
%   .statusFcn
%   .logFcn
%   .defaultUnderlayMode = scm / mean / median / anat / loaded / atlas
%   .anatIsDisplayReady = true/false
%   .defaultUnderlayViewMode = 5 default SCM log median, 3 robust gray, 4 vessel
%   .underlayBrightness
%   .underlayContrast
%   .underlayGamma
%   .underlayLogGain
%   .underlaySharpness

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4 || isempty(opts), opts = struct(); end

opts = fc_defaults(opts);

% Force Functional Connectivity GUI to open with SCM log / median underlay.
% This prevents fusi_studio or older caller settings from pre-selecting robust gray.
opts.defaultUnderlayMode = 'scm';
opts.defaultUnderlayViewMode = 5;

% Force Functional Connectivity GUI startup seed box to 25 pixels.
% This overrides older fUSI Studio callers that still pass seedBoxSize = 3.
opts.seedBoxSize = 25;

opts.saveRoot = saveRoot;

subjects = fc_make_subjects(dataIn, opts);
if isempty(subjects)
    error('FunctionalConnectivity: No valid subject/data found.');
end

nSub = numel(subjects);
[Y, X, Z] = fc_size3(subjects(1).I4);

for i = 2:nSub
    [Yi, Xi, Zi] = fc_size3(subjects(i).I4);
    if Yi ~= Y || Xi ~= X || Zi ~= Z
        error('FunctionalConnectivity: All subjects must have identical spatial dimensions.');
    end
end

[subjects, ~] = fc_startup_masks(subjects, opts);

if opts.askAtlasAtStart
    hasAtlas = false;
    for i = 1:nSub
        if ~isempty(subjects(i).roiAtlas)
            hasAtlas = true;
            break;
        end
    end
    if ~hasAtlas
        atlas = fc_ask_common_atlas(subjects(1), opts, Y, X, Z);
        if ~isempty(atlas)
            for i = 1:nSub
                subjects(i).roiAtlas = atlas;
            end
        end
    end
end

if ~isempty(opts.statusFcn) && isa(opts.statusFcn,'function_handle')
    try, opts.statusFcn(false); catch, end
end

% -------------------------------------------------------------------------
% STATE
% -------------------------------------------------------------------------
st = struct();
st.subjects = subjects;
st.nSub = nSub;
st.currentSubject = 1;
st.Y = Y;
st.X = X;
st.Z = Z;
st.slice = max(1, round(Z/2));
st.sliceRegionOnly = (Z > 1);  % HUMOR_REPAIR_TRUE_SLICE_STATE_20260519
st.sliceRegionOnly = (Z > 1);  % HUMOR_FC_STEP_SLICE_FILTER_DEFAULT_20260519  % HUMOR_FC_STEPMOTOR_NAMES_SLICE_UI_20260519

st.seedX = max(1, round(X/2));
st.seedY = max(1, round(Y/2));
st.seedBoxSize = max(1, round(opts.seedBoxSize));
st.useSliceOnly = false;

st.analysisStartSec = 0;
st.analysisEndSec = inf;
st.epochs = struct('name', {'Whole'}, 'start', {0}, 'end', {inf});
st.currentEpoch = 1;

% FC_LR_EPOCH_PATCH_20260505_STATE
% Injection/window settings are in minutes for user readability.
st.fcEpochMode = 'whole';      % whole | pre | during | post
st.fcInjStartMin = 14;          % edit in GUI
st.fcInjEndMin   = 15;          % edit in GUI
st.fcEpochWinMin = 3;           % first N minutes for pre/during/post

st.fcUseEpochWin = false;     % OFF = use full pre/during/post period; ON = use Win minutes% FC_LR_EPOCH_PATCH_20260505_STATE_END

st.underlayMode = fc_initial_underlay_mode(st.subjects(1), opts);
st.underlayViewMode = opts.defaultUnderlayViewMode;
st.underlayBrightness = opts.underlayBrightness;
st.underlayContrast   = opts.underlayContrast;
st.underlayGamma      = opts.underlayGamma;
st.underlayLogGain    = opts.underlayLogGain;
st.underlaySharpness  = opts.underlaySharpness;
st.underlayVesselSize = opts.underlayVesselSize;
st.underlayVesselLev  = opts.underlayVesselLev;

st.loadedUnderlay = [];
st.loadedUnderlayIsRGB = false;
st.loadedUnderlayDisplayReady = false;
st.loadedUnderlayName = '';

st.showAtlasLines = false;
st.showMaskLine = false;
st.overlayMode = 'seed_fc';

st.seedAbsThr = 0.20;
st.seedAlpha = 0.70;
st.seedDisplay = 'r';
st.seedCLim = 1.0;

st.roiAbsThr = 0.20;
st.roiDisplaySpace = 'r';
st.roiOrder = 'name';
st.roiCLim = 1.0;
st.roiZCLim = 1.0;

st.cmapName = 'bwr';
st.graphCmapName = 'bwr';
st.compareROI = 1;
st.compareTopN = 15;    % Compare ROI page size
st.compareSort = 'abs';
st.comparePage = 1;

st.seedResults = cell(nSub, numel(st.epochs));
st.roiResults  = cell(nSub, numel(st.epochs));

st.saveRoot = saveRoot;
st.tag = tag;
st.qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(st.qcDir,'dir'), mkdir(st.qcDir); end
st.opts = opts;

% Region-key bookkeeping. Used by the Region key button.
st.loadedRegionNameFile = '';
st.loadedSegmentationFile = '';
st.showHemisphere = true;  % FC_LR_LABEL_DISPLAY_PATCH_V2_STATE
st.roiHemiMode = 'both';   % both | left | right | merged
% FC_REGION_PICKER_STATE_20260512
st.fcSelectedRegionIdx = [];
st.fcSelectedRegionY = [];
st.fcSelectedRegionX = [];

% -------------------------------------------------------------------------
% COLORS / FONT
% -------------------------------------------------------------------------
C = struct();
C.bgFig   = [0.045 0.045 0.052];
C.bgPane  = [0.075 0.075 0.085];
C.bgAx    = [0.105 0.105 0.115];
C.bgEdit  = [0.15 0.15 0.17];
C.bgBtn   = [0.24 0.24 0.28];
C.blue    = [0.12 0.40 0.82];
C.green   = [0.12 0.58 0.25];
C.red     = [0.72 0.20 0.20];
C.orange  = [0.95 0.55 0.18];
C.fg      = [0.94 0.94 0.96];
C.dim     = [0.72 0.72 0.78];
C.warn    = [1.00 0.35 0.35];
C.good    = [0.25 0.85 0.35];
C.cross   = [1.00 0.20 0.20];
C.seedBox = [1.00 0.88 0.10];
C.line    = [0.95 0.95 0.95];
C.mask    = [0.20 0.95 0.40];
C.font    = 'Arial';
C.fsTiny  = 8;
C.fsSmall = 9;
C.fs      = 10;
C.fsBig   = 11;

% -------------------------------------------------------------------------
% FIGURE
% -------------------------------------------------------------------------
scr = get(0,'ScreenSize');
fig = figure( ...
    'Name','fUSI Studio - Functional Connectivity', ...
    'Color',C.bgFig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Units','normalized', ...
    'Position',[0.020 0.050 0.960 0.880], ...
    'CloseRequestFcn',@onClose, ...
    'WindowScrollWheelFcn',@onMouseWheel);
try, set(fig,'Units','normalized','Position',[0.035 0.060 0.930 0.850]); catch, end
try, movegui(fig,'center'); catch, end
% FC_CLEAN_FULLSIZE_FIXED_WINDOWSTATE
try, set(fig,'Units','normalized','Position',[0.035 0.060 0.930 0.850]); catch, end
try, movegui(fig,'center'); catch, end
try, set(fig,'Renderer','opengl'); catch, end
% FC_LR_LABEL_DISPLAY_PATCH_V2_INTERPRETER
try
    set(fig,'DefaultTextInterpreter','none');
    set(fig,'DefaultAxesTickLabelInterpreter','none');
    set(fig,'DefaultLegendInterpreter','none');
catch
end

panelCtrl = uipanel('Parent',fig,'Units','normalized','Position',[0.010 0.015 0.385 0.970], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Controls','FontName',C.font,'FontSize',11,'FontWeight','bold','FontSize',14);

panelViewWrap = uipanel('Parent',fig,'Units','normalized','Position',[0.405 0.015 0.585 0.970], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Views','FontName',C.font,'FontSize',11,'FontWeight','bold','FontSize',14);

% -------------------------------------------------------------------------
% CONTROL PANELS
% -------------------------------------------------------------------------
pData = fc_panel(panelCtrl,[0.015 0.760 0.970 0.220],'1. Data / ROI labels',C);
pSeed = fc_panel(panelCtrl,[0.015 0.575 0.970 0.175],'2. Seed-based FC',C);
pROI  = fc_panel(panelCtrl,[0.015 0.315 0.970 0.250],'3. Region-based FC',C);
pSave = fc_panel(panelCtrl,[0.015 0.020 0.970 0.285],'4. Display / Save',C);

% -------------------------------------------------------------------------
% DATA PANEL
% -------------------------------------------------------------------------
fc_label(pData,[0.02 0.83 0.18 0.10],'Subject',C);
subNames = cell(nSub,1);
for i = 1:nSub, subNames{i} = subjects(i).name; end

ddSubject = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.705 0.48 0.13], ...
    'String',subNames,'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'FontWeight','bold','Callback',@onSubject);

fc_label(pData,[0.54 0.83 0.16 0.10],'Slice Z',C);
slSlice = uicontrol('Parent',pData,'Style','slider','Units','normalized', ...
    'Position',[0.54 0.735 0.27 0.08], ...
    'Min',1,'Max',max(1,Z),'Value',st.slice, ...
    'SliderStep',fc_slider_step(Z), ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onSliceSlider);

edSlice = uicontrol('Parent',pData,'Style','edit','Units','normalized', ...
    'Position',[0.84 0.705 0.12 0.13], ...
    'String',num2str(st.slice), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'FontWeight','bold','Callback',@onSliceEdit);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.555 0.19 0.12], ...
    'String','Load data','BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadData);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.225 0.555 0.19 0.12], ...
    'String','Load mask','BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadMask);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.430 0.555 0.24 0.12], ...
    'String','Load ROI labels','BackgroundColor',C.orange,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadAtlas);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.685 0.555 0.275 0.12], ...
    'String','Names / step folder','BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadNames);

fc_label(pData,[0.02 0.385 0.16 0.10],'Reference',C);
underlayList0 = fc_underlay_list(st);
ddUnderlay = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.18 0.375 0.08 0.12], ...
    'Visible','off', ...
    'String',underlayList0, ...
    'Value',fc_underlay_value(st,underlayList0), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'Callback',@onUnderlay);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.18 0.375 0.34 0.12], ...
    'String','Load underlay / histology','BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadUnderlay);

cbAtlasLine = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.56 0.400 0.20 0.08], ...
    'String','Show ROI lines','Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onAtlasLine);

cbMaskLine = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.78 0.400 0.16 0.08], ...
    'String','Show mask','Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onMaskLine);

txtSummary = uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.02 0.055 0.94 0.02], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsTiny);

% -------------------------------------------------------------------------
% SEED PANEL
% -------------------------------------------------------------------------
fc_label(pSeed,[0.02 0.72 0.04 0.12],'X',C);
edSeedX = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.065 0.70 0.10 0.15], 'String',num2str(st.seedX), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'FontWeight','bold','Callback',@onSeedEdit);

fc_label(pSeed,[0.19 0.72 0.04 0.12],'Y',C);
edSeedY = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.235 0.70 0.10 0.15], 'String',num2str(st.seedY), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'FontWeight','bold','Callback',@onSeedEdit);

fc_label(pSeed,[0.365 0.72 0.08 0.12],'Size',C);
edSeedSize = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.445 0.70 0.10 0.15], 'String',num2str(st.seedBoxSize), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'FontWeight','bold','Callback',@onSeedEdit);

cbSliceOnly = uicontrol('Parent',pSeed,'Style','checkbox','Units','normalized', ...
    'Position',[0.585 0.73 0.18 0.10], 'String','Slice only','Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onSliceOnly);

fc_label(pSeed,[0.02 0.47 0.15 0.10],'Map',C);
ddSeedDisplay = uicontrol('Parent',pSeed,'Style','popupmenu','Units','normalized', ...
    'Position',[0.17 0.45 0.23 0.13], 'String',{'Pearson r','Fisher z'}, 'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'Callback',@onSeedDisplay);

fc_label(pSeed,[0.45 0.47 0.13 0.10],'|r| thr',C);
edSeedThr = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.60 0.45 0.11 0.13], 'String',sprintf('%.2f',st.seedAbsThr), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'Callback',@onSeedThr);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.17 0.26 0.16], 'String','Seed current', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onComputeSeedCurrent);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.30 0.17 0.22 0.16], 'String','Seed all', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onComputeSeedAll);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.54 0.17 0.28 0.16], 'String','Load ROI TXT', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadScmROI);

txtSeed = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.02 0.94 0.02], 'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

% -------------------------------------------------------------------------
% ROI PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.79 0.22 0.12], 'String','ROI current', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onComputeROICurrent);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.255 0.79 0.18 0.12], 'String','ROI all', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onComputeROIAll);

fc_label(pROI,[0.48 0.815 0.16 0.08],'Matrix value',C);
ddROISpace = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.61 0.79 0.18 0.12], 'String',{'Fisher z','Pearson r'}, 'Value',2, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onROISpace);

fc_label(pROI,[0.805 0.815 0.075 0.08],'|r| thr',C);
edROIThr = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.88 0.79 0.08 0.12], 'String',sprintf('%.2f',st.roiAbsThr), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onROIThr);

fc_label(pROI,[0.02 0.60 0.18 0.09],'Compare ROI',C);
ddCompareROI = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.20 0.58 0.42 0.12], 'String',{'n/a'}, 'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onCompareROI);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.64 0.58 0.18 0.12], 'String','Compare', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onCompareROI);

fc_label(pROI,[0.85 0.60 0.05 0.09],'Top',C);
edTopN = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.91 0.58 0.055 0.12], 'String',num2str(st.compareTopN), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onTopN);

btnComparePrev = uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.32 0.38 0.12 0.12], 'String','Prev', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onComparePagePrev);

txtComparePage = uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.455 0.38 0.16 0.12], 'String','1-20', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','center', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);
try, set(txtComparePage,'Visible','off'); catch, end % FC_PATCH_HIDE_COMPARE_PAGE_BOX

btnCompareNext = uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.63 0.38 0.12 0.12], 'String','Next', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onComparePageNext);

% Removed empty black UI label above Load Seg MAT.
ddSort = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.12 0.38 0.23 0.12], 'String',{'Abs strongest','Positive','Negative','Alphabetical'}, 'Value',1, 'Visible','off', ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onCompareSort);

% Removed empty black UI label above Prev/Next.
ddOrder = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.52 0.38 0.20 0.12], 'String',{'Name','Label'}, 'Value',1, 'Visible','off', ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onROIOrder);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.38 0.25 0.12], 'String','Load Seg MAT', ...
    'BackgroundColor',C.orange,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onLoadSegmentation);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.76 0.38 0.20 0.12], 'String','Export CSV', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onExportCSV);

txtROI = uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.02 0.06 0.94 0.02], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsTiny);

% FC_LR_EPOCH_PATCH_20260505_UI
fc_label(pROI,[0.02 0.205 0.105 0.085],'Window',C);
ddEpochMode = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.125 0.185 0.205 0.115], ...
    'String',{'Whole','Pre-inj','During-inj','Post-inj'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold', ...
    'Callback',@onEpochMode);

fc_label(pROI,[0.350 0.205 0.090 0.085],'Inj start',C);
edInjStart = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.445 0.185 0.075 0.115], 'String',sprintf('%.2f',st.fcInjStartMin), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold','Callback',@onEpochEdit);

fc_label(pROI,[0.535 0.205 0.075 0.085],'Inj end',C);
edInjEnd = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.610 0.185 0.075 0.115], 'String',sprintf('%.2f',st.fcInjEndMin), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold','Callback',@onEpochEdit);

fc_label(pROI,[0.700 0.205 0.060 0.085],'Win',C);
edEpochWin = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.755 0.185 0.065 0.115], 'String',sprintf('%.2f',st.fcEpochWinMin), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold','Callback',@onEpochEdit);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.835 0.185 0.125 0.115], 'String','Apply win', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onEpochApply);
% FC_USE_WINDOW_CHECKBOX_20260512
cbEpochUseWin = uicontrol('Parent',pROI,'Style','checkbox','Units','normalized', ...
    'Position',[0.745 0.185 0.085 0.115], ...
    'String','Use win', 'Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold', ...
    'Callback',@onEpochEdit);
% FC_USE_WINDOW_CHECKBOX_20260512_END
% FC_LR_EPOCH_PATCH_20260505_UI_END

% -------------------------------------------------------------------------
% DISPLAY / SAVE PANEL
% -------------------------------------------------------------------------
fc_label(pSave,[0.02 0.80 0.12 0.10],'Overlay',C);
ddOverlay = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.15 0.78 0.30 0.12], ...
    'String',{'Seed FC','ROI compare map','Pick ROI label','Labels only','Mask only','None'}, 'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onOverlay);

fc_label(pSave,[0.49 0.80 0.09 0.10],'Color',C);
ddCmapGlobal = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.58 0.78 0.24 0.12], ...
    'String',{'Blue-White-Red','Winter','Hot','Jet','Gray','Parula'}, ...
    'Value',1,'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onColorSettings);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.18 0.045 0.15 0.13], 'String','Reset view', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onResetView);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.35 0.045 0.15 0.13], 'String','Region key', ...
    'BackgroundColor',C.orange,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onOpenRegionKey);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.52 0.045 0.12 0.13], 'String','Save', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onSaveAll);

% FC_GROUP_ANALYSIS_EXPORT_BUTTON_20260504
uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.045 0.14 0.13], 'String','Export GA', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onExportGroupAnalysis);
% FC_GROUP_ANALYSIS_EXPORT_BUTTON_20260504_END


fc_label(pSave,[0.02 0.60 0.16 0.10],'Underlay style',C);
ddUnderlayStyle = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.20 0.58 0.30 0.12], ...
    'String',{'SCM log / median','Robust gray','Vessel enhanced','Raw min-max'}, ...
        'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onUnderlayStyle);

fc_label(pSave,[0.515 0.60 0.130 0.10],'Gamma',C);
edUGamma = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.650 0.58 0.085 0.12], 'String',sprintf('%.2f',st.underlayGamma), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, 'FontName',C.font, ...
    'FontSize',C.fsTiny,'Callback',@onUnderlayStyle);

fc_label(pSave,[0.765 0.60 0.090 0.10],'Sharp',C);
edUSharp = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.855 0.58 0.095 0.12], 'String',sprintf('%.2f',st.underlaySharpness), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, 'FontName',C.font, ...
    'FontSize',C.fsTiny,'Callback',@onUnderlayStyle);

fc_label(pSave,[0.02 0.40 0.20 0.10],'Seed z-limit',C);
edSeedCLim = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.22 0.38 0.08 0.12], 'String',num2str(st.seedCLim), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, 'FontName',C.font, ...
    'FontSize',C.fsTiny,'Callback',@onColorSettings);

fc_label(pSave,[0.36 0.40 0.22 0.10],'Overlay opacity',C);
edSeedAlpha = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.59 0.38 0.08 0.12], 'String',sprintf('%.2f',st.seedAlpha), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, 'FontName',C.font, ...
    'FontSize',C.fsTiny,'Callback',@onColorSettings);

% FC_LR_LABEL_DISPLAY_PATCH_V2_CHECKBOX
cbShowLR = uicontrol('Parent',pSave,'Style','checkbox','Units','normalized', ...
    'Position',[0.705 0.385 0.245 0.105], ...
    'String','Show L/R', 'Value',1, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny, ...
    'Callback',@onShowHemisphere);

% HUMOR_FC_STEPMOTOR_NAMES_SLICE_UI_20260519
fc_label(pSave,[0.835 0.80 0.035 0.10],'Z',C);
edSliceBox = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.875 0.78 0.075 0.12], 'String',num2str(st.slice), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold', ...
    'TooltipString','Display slice used by Seed Map / Compare ROI / slice-filtered heatmap', ...
    'Callback',@onSliceBoxEdit);
cbSliceRegionOnly = uicontrol('Parent',pSave,'Style','checkbox','Units','normalized', ...
    'Position',[0.810 0.500 0.150 0.075], ...
    'String','Slice ROIs', 'Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny, ...
    'TooltipString','When ON, ROI Heatmap and Graph show only atlas regions present in current slice', ...
    'Callback',@onSliceRegionOnly);

% FC_REGION_MODE_PATCH_20260504_UI
fc_label(pSave,[0.02 0.205 0.14 0.10],'Regions',C);
ddRegionMode = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.16 0.19 0.34 0.12], ...
    'String',{'Both L/R separate','Left only','Right only','Left vs Right','All merged no L/R'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold', ...
    'Callback',@onRegionMode);
% FC_REGION_MODE_PATCH_20260504_UI_END

% FC_LABEL_REGION_PICK_UI_20260512_START
try
    fc_label(pSave,[0.500 0.455 0.075 0.060],'Labels',C);
    ddMatrixTickMode = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
        'Position',[0.580 0.420 0.175 0.090], ...
        'String',{'Auto','All','Every 2','Every 3','Every 5','Every 10'}, ...
        'Value',2,'Tag','FC_MatrixTickMode', ...
        'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
        'FontName',C.font,'FontSize',C.fsTiny,'FontWeight','bold', ...
        'Callback',@onMatrixTickMode);
    uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
        'Position',[0.765 0.420 0.095 0.090],'String','Pick', ...
        'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
        'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny, ...
        'Callback',@onCustomRegionList);
    uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
        'Position',[0.870 0.420 0.080 0.090],'String','All', ...
        'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
        'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny, ...
        'Callback',@onClearCustomRegions);
catch ME_label_ui
    try, fprintf('FC label/custom-region UI warning: %s\n',ME_label_ui.message); catch, end
end
% FC_LABEL_REGION_PICK_UI_20260512_END

fc_label(pSave,[0.02 0.205 0.14 0.10],'',C);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.16 0.19 0.16 0.12], 'String','Flip ROI LR', ...
    'Visible','off', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onFlipAtlasLR);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.34 0.19 0.16 0.12], 'String','Flip ROI UD', ...
    'Visible','off', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onFlipAtlasUD);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.52 0.19 0.18 0.12], 'String','Flip underlay LR', ...
    'Visible','off', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onFlipUnderlayLR);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.72 0.19 0.18 0.12], 'String','Flip underlay UD', ...
    'Visible','off', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onFlipUnderlayUD);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.66 0.045 0.12 0.13], 'String','Help', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onHelp);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.80 0.045 0.14 0.13], 'String','Close', ...
    'BackgroundColor',C.red,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onClose);

txtStatus = uicontrol('Parent',pSave,'Style','text','Units','normalized', ...
    'Position',[0.02 0.025 0.02 0.02], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsTiny);
% -------------------------------------------------------------------------
% FC_LEFT_GUI_REPACK_20260512_START
try
    try, set(fig,'Units','normalized','Position',[0.035 0.060 0.930 0.850]); catch, end
    try, movegui(fig,'center'); catch, end

    set(panelCtrl,'Position',[0.010 0.015 0.390 0.970],'FontSize',10,'FontWeight','bold','FontSize',14);
    set(panelViewWrap,'Position',[0.410 0.015 0.580 0.970],'FontSize',10,'FontWeight','bold','FontSize',14);

    set(pData,'Position',[0.015 0.800 0.970 0.170],'FontSize',10,'FontWeight','bold','FontSize',14);
    set(pSeed,'Position',[0.015 0.615 0.970 0.175],'FontSize',10,'FontWeight','bold','FontSize',14);
    set(pROI, 'Position',[0.015 0.400 0.970 0.205],'FontSize',10,'FontWeight','bold','FontSize',14);
    set(pSave,'Position',[0.015 0.020 0.970 0.370],'FontSize',10,'FontWeight','bold','FontSize',14);

    hCtl = findall(panelCtrl,'Type','uicontrol');
    for ii = 1:numel(hCtl)
        try
            sty = get(hCtl(ii),'Style');
            if strcmpi(sty,'text')
                set(hCtl(ii),'FontName',C.font,'FontSize',7.5,'FontWeight','bold','FontSize',14);
            else
                set(hCtl(ii),'FontName',C.font,'FontSize',8,'FontWeight','bold','FontSize',14);
            end
        catch
        end
    end

    % ---------------- Box 1: compact and aligned ----------------
    try, set(findobj(pData,'Style','text','String','Subject'),'Position',[0.020 0.795 0.110 0.090]); catch, end
    try, set(ddSubject,'Position',[0.130 0.655 0.370 0.145]); catch, end
    try, set(findobj(pData,'Style','text','String','Slice Z'),'Position',[0.535 0.795 0.090 0.090]); catch, end
    try, set(slSlice,'Position',[0.625 0.700 0.205 0.070]); catch, end
    try, set(edSlice,'Position',[0.850 0.630 0.110 0.150]); catch, end

    try, set(findobj(pData,'String','Load data'),'Position',[0.020 0.430 0.190 0.145]); catch, end
    try, set(findobj(pData,'String','Load mask'),'Position',[0.230 0.430 0.190 0.145]); catch, end
    try, set(findobj(pData,'String','Load ROI labels'),'String','ROI labels'); catch, end
    try, set(findobj(pData,'String','ROI labels'),'Position',[0.445 0.430 0.230 0.145]); catch, end
    try, set(findobj(pData,'String','Names / step folder'),'String','Region names'); catch, end
    try, set(findobj(pData,'String','Region names'),'Position',[0.700 0.430 0.260 0.145]); catch, end

    try, set(findobj(pData,'Style','text','String','Reference'),'Position',[0.020 0.205 0.120 0.085]); catch, end
    try, set(findobj(pData,'String','Load underlay / histology'),'String','Underlay / histology'); catch, end
    try, set(findobj(pData,'String','Underlay / histology'),'Position',[0.160 0.160 0.345 0.140]); catch, end
    try, set(cbAtlasLine,'Position',[0.560 0.195 0.160 0.090],'String','ROI lines'); catch, end
    try, set(cbMaskLine,'Position',[0.755 0.195 0.140 0.090],'String','Mask'); catch, end
    try, set(txtSummary,'Visible','off'); catch, end

    % ---------------- Box 2: reduce right-side empty gap ----------------
    try, set(edSeedX,'Position',[0.070 0.690 0.095 0.150]); catch, end
    try, set(edSeedY,'Position',[0.235 0.690 0.095 0.150]); catch, end
    try, set(edSeedSize,'Position',[0.445 0.690 0.100 0.150]); catch, end
    try, set(cbSliceOnly,'Position',[0.610 0.720 0.180 0.095]); catch, end
    try, set(ddSeedDisplay,'Position',[0.170 0.435 0.240 0.130]); catch, end
    try, set(edSeedThr,'Position',[0.610 0.435 0.110 0.130]); catch, end
    try, set(findobj(pSeed,'String','Seed current'),'Position',[0.020 0.130 0.285 0.170]); catch, end
    try, set(findobj(pSeed,'String','Seed all'),'Position',[0.330 0.130 0.250 0.170]); catch, end
    try, set(findobj(pSeed,'String','Load ROI TXT'),'Position',[0.605 0.130 0.345 0.170]); catch, end
    try, set(txtSeed,'Visible','off'); catch, end

    % ---------------- Box 3: tighter bottom gap ----------------
    try, set(findobj(pROI,'String','ROI current'),'Position',[0.020 0.735 0.220 0.150]); catch, end
    try, set(findobj(pROI,'String','ROI all'),'Position',[0.260 0.735 0.190 0.150]); catch, end
    try, set(findobj(pROI,'Style','text','String','Matrix value'),'Position',[0.475 0.770 0.160 0.085]); catch, end
    try, set(ddROISpace,'Position',[0.610 0.735 0.180 0.150]); catch, end
    try, set(findobj(pROI,'Style','text','String','Thr'),'Position',[0.820 0.770 0.060 0.085]); catch, end
    try, set(edROIThr,'Position',[0.875 0.735 0.085 0.150]); catch, end
    try, set(findobj(pROI,'Style','text','String','Compare ROI'),'Position',[0.020 0.505 0.175 0.090]); catch, end
    try, set(ddCompareROI,'Position',[0.200 0.480 0.415 0.140]); catch, end
    try, set(findobj(pROI,'String','Compare'),'Position',[0.635 0.480 0.180 0.140]); catch, end
    try, set(findobj(pROI,'Style','text','String','Top'),'Position',[0.845 0.505 0.050 0.090]); catch, end
    try, set(edTopN,'Position',[0.905 0.480 0.060 0.140]); catch, end
    try, set(findobj(pROI,'String','Load Seg MAT'),'Position',[0.020 0.145 0.260 0.155]); catch, end
    try, set(btnComparePrev,'Position',[0.310 0.145 0.145 0.155],'String','< Prev'); catch, end
    try, set(btnCompareNext,'Position',[0.470 0.145 0.145 0.155],'String','Next >'); catch, end
    try, set(findobj(pROI,'String','Export CSV'),'Position',[0.760 0.145 0.200 0.155]); catch, end
    try, set(txtComparePage,'Visible','off'); catch, end
    try, set(txtROI,'Visible','off'); catch, end

    % Move window controls from Box 3 to Box 4
    try, set(findobj(fig,'Style','text','String','Window'),'Parent',pSave,'Position',[0.020 0.305 0.095 0.060]); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.125 0.270 0.180 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj start'),'String','Start','Parent',pSave,'Position',[0.325 0.305 0.060 0.060]); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.385 0.270 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj end'),'String','End','Parent',pSave,'Position',[0.475 0.305 0.055 0.060]); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.525 0.270 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Win'),'Parent',pSave,'Position',[0.615 0.305 0.045 0.060]); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.660 0.270 0.070 0.090]); catch, end
    try, set(findobj(fig,'String','Apply win'),'Parent',pSave,'Position',[0.760 0.270 0.190 0.090],'String','Apply window'); catch, end

    % ---------------- Box 4: full clean repack ----------------
    try, set(ddOverlay,'Position',[0.145 0.830 0.300 0.090]); catch, end
    try, set(ddCmapGlobal,'Position',[0.580 0.830 0.370 0.090]); catch, end

    try, set(ddUnderlayStyle,'Position',[0.200 0.690 0.300 0.090]); catch, end
    try, set(edUGamma,'Position',[0.650 0.690 0.085 0.090]); catch, end
    try, set(edUSharp,'Position',[0.865 0.690 0.085 0.090]); catch, end

    try, set(edSeedCLim,'Position',[0.190 0.555 0.085 0.090]); catch, end
    try, set(edSeedAlpha,'Position',[0.555 0.555 0.085 0.090]); catch, end
    try, set(cbShowLR,'Position',[0.705 0.560 0.245 0.080]); catch, end

    try, set(ddRegionMode,'Position',[0.160 0.420 0.330 0.090]); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.580 0.420 0.175 0.090]); catch, end
    try, set(findobj(pSave,'String','Pick'),'Position',[0.765 0.420 0.095 0.090]); catch, end
    try, set(findobj(pSave,'String','All'),'Position',[0.870 0.420 0.080 0.090]); catch, end

    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.045 0.155 0.105]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.190 0.045 0.120 0.105]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.325 0.045 0.160 0.105]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.500 0.045 0.115 0.105]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.630 0.045 0.115 0.105]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.760 0.045 0.190 0.105]); catch, end
    try, set(txtStatus,'Visible','off'); catch, end

    % Make colors cleaner/consistent for main action buttons
    try, set(findobj(panelCtrl,'String','ROI labels'),'BackgroundColor',C.orange,'ForegroundColor','w'); catch, end
    try, set(findobj(panelCtrl,'String','Region names'),'BackgroundColor',C.blue,'ForegroundColor','w'); catch, end
    try, set(findobj(panelCtrl,'String','Load Seg MAT'),'BackgroundColor',C.orange,'ForegroundColor','w'); catch, end
    try, set(findobj(panelCtrl,'String','Export GA'),'BackgroundColor',C.green,'ForegroundColor','w'); catch, end
    try, set(findobj(panelCtrl,'String','Region key'),'BackgroundColor',C.orange,'ForegroundColor','w'); catch, end
catch ME_left_layout
    try, fprintf('FC left GUI repack warning: %s\n',ME_left_layout.message); catch, end
end
% FC_LEFT_GUI_REPACK_20260512_END
% FC_LEFT_GUI_FINAL_ALIGN_20260512_START
try
    try, set(fig,'Units','normalized','Position',[0.030 0.055 0.940 0.860]); catch, end
    try, movegui(fig,'center'); catch, end

    set(panelCtrl,'Position',[0.010 0.015 0.395 0.970],'FontSize',10,'FontWeight','bold','FontSize',14);
    set(panelViewWrap,'Position',[0.415 0.015 0.575 0.970],'FontSize',10,'FontWeight','bold','FontSize',14);

    set(pData,'Position',[0.015 0.790 0.970 0.185],'FontSize',9,'FontWeight','bold','FontSize',14);
    set(pSeed,'Position',[0.015 0.600 0.970 0.180],'FontSize',9,'FontWeight','bold','FontSize',14);
    set(pROI, 'Position',[0.015 0.380 0.970 0.210],'FontSize',9,'FontWeight','bold','FontSize',14);
    set(pSave,'Position',[0.015 0.020 0.970 0.350],'FontSize',9,'FontWeight','bold','FontSize',14);

    hCtl = findall(panelCtrl,'Type','uicontrol');
    for ii = 1:numel(hCtl)
        try
            sty = get(hCtl(ii),'Style');
            if strcmpi(sty,'text')
                set(hCtl(ii),'FontName',C.font,'FontSize',7.2,'FontWeight','bold','FontSize',14);
            else
                set(hCtl(ii),'FontName',C.font,'FontSize',7.8,'FontWeight','bold','FontSize',14);
            end
        catch
        end
    end

    % ---------- Box 1: Data / ROI labels, clean 3-row layout ----------
    try, set(findobj(pData,'Style','text','String','Subject'),'Position',[0.020 0.790 0.110 0.090]); catch, end
    try, set(ddSubject,'Position',[0.130 0.665 0.370 0.130]); catch, end
    try, set(findobj(pData,'Style','text','String','Slice Z'),'Position',[0.535 0.790 0.090 0.090]); catch, end
    try, set(slSlice,'Position',[0.625 0.720 0.205 0.060]); catch, end
    try, set(edSlice,'Position',[0.850 0.650 0.110 0.135]); catch, end

    try, set(findobj(pData,'String','Load data'),'Position',[0.020 0.455 0.185 0.140]); catch, end
    try, set(findobj(pData,'String','Load mask'),'Position',[0.220 0.455 0.185 0.140]); catch, end
    try, set(findobj(pData,'String','Load ROI labels'),'String','ROI labels'); catch, end
    try, set(findobj(pData,'String','ROI labels'),'Position',[0.420 0.455 0.240 0.140]); catch, end
    try, set(findobj(pData,'String','Names / step folder'),'String','Region names'); catch, end
    try, set(findobj(pData,'String','Region names'),'Position',[0.680 0.455 0.280 0.140]); catch, end

    try, set(findobj(pData,'Style','text','String','Reference'),'Position',[0.020 0.225 0.120 0.080]); catch, end
    try, set(findobj(pData,'String','Load underlay / histology'),'String','Underlay / histology'); catch, end
    try, set(findobj(pData,'String','Underlay / histology'),'Position',[0.155 0.180 0.350 0.130]); catch, end
    try, set(cbAtlasLine,'Position',[0.555 0.220 0.155 0.080],'String','ROI lines'); catch, end
    try, set(cbMaskLine,'Position',[0.745 0.220 0.130 0.080],'String','Mask'); catch, end
    try, set(txtSummary,'Visible','off'); catch, end

    % ---------- Box 4: Display / Save, clean 6-row layout ----------
    try, set(findobj(pSave,'Style','text','String','Overlay'),'Position',[0.020 0.840 0.110 0.060]); catch, end
    try, set(ddOverlay,'Position',[0.140 0.815 0.315 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Color'),'Position',[0.490 0.840 0.080 0.060]); catch, end
    try, set(ddCmapGlobal,'Position',[0.570 0.815 0.380 0.090]); catch, end

    try, set(findobj(pSave,'Style','text','String','Underlay style'),'Position',[0.020 0.700 0.160 0.060]); catch, end
    try, set(ddUnderlayStyle,'Position',[0.200 0.675 0.295 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Gamma'),'Position',[0.525 0.700 0.080 0.060]); catch, end
    try, set(edUGamma,'Position',[0.610 0.675 0.090 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Sharp'),'Position',[0.730 0.700 0.080 0.060]); catch, end
    try, set(edUSharp,'Position',[0.840 0.675 0.110 0.090]); catch, end

    try, set(findobj(pSave,'Style','text','String','Seed z-limit'),'Position',[0.020 0.560 0.160 0.060]); catch, end
    try, set(edSeedCLim,'Position',[0.190 0.535 0.090 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Overlay opacity'),'Position',[0.335 0.560 0.195 0.060]); catch, end
    try, set(edSeedAlpha,'Position',[0.545 0.535 0.090 0.090]); catch, end
    try, set(cbShowLR,'Position',[0.685 0.545 0.240 0.080]); catch, end

    try, set(findobj(pSave,'Style','text','String','Regions'),'Position',[0.020 0.420 0.120 0.060]); catch, end
    try, set(ddRegionMode,'Position',[0.140 0.395 0.350 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Labels'),'Position',[0.510 0.420 0.070 0.060]); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.585 0.395 0.165 0.090]); catch, end
    try, set(findobj(pSave,'String','Pick'),'Position',[0.765 0.395 0.090 0.090]); catch, end
    try, set(findobj(pSave,'String','All'),'Position',[0.865 0.395 0.085 0.090]); catch, end

    try, set(findobj(fig,'Style','text','String','Window'),'Parent',pSave,'Position',[0.020 0.280 0.090 0.060]); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.115 0.255 0.165 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj start'),'String','Start'); catch, end
    try, set(findobj(fig,'Style','text','String','Start'),'Parent',pSave,'Position',[0.300 0.280 0.055 0.060]); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.360 0.255 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj end'),'String','End'); catch, end
    try, set(findobj(fig,'Style','text','String','End'),'Parent',pSave,'Position',[0.455 0.280 0.050 0.060]); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.505 0.255 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Win'),'Parent',pSave,'Position',[0.600 0.280 0.045 0.060]); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.645 0.255 0.070 0.090]); catch, end
    try, set(findobj(fig,'String','Apply win'),'String','Apply window'); catch, end
    try, set(findobj(fig,'String','Apply window'),'Parent',pSave,'Position',[0.735 0.255 0.215 0.090]); catch, end

    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.055 0.155 0.105]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.190 0.055 0.125 0.105]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.330 0.055 0.160 0.105]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.505 0.055 0.115 0.105]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.635 0.055 0.115 0.105]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.765 0.055 0.185 0.105]); catch, end
    try, set(txtStatus,'Visible','off'); catch, end

catch ME_align2
    try, fprintf('FC final left layout warning: %s\n',ME_align2.message); catch, end
end
% FC_LEFT_GUI_FINAL_ALIGN_20260512_END

% FC_LEFT_GUI_EXTRA_SPACING_20260512_START
try
    % Slightly wider left control column
    try, set(panelCtrl,'Position',[0.010 0.015 0.400 0.970]); catch, end
    try, set(panelViewWrap,'Position',[0.420 0.015 0.570 0.970]); catch, end

    % Panel heights with clean gaps
    try, set(pData,'Position',[0.015 0.785 0.970 0.190]); catch, end
    try, set(pSeed,'Position',[0.015 0.595 0.970 0.180]); catch, end
    try, set(pROI, 'Position',[0.015 0.380 0.970 0.205]); catch, end
    try, set(pSave,'Position',[0.015 0.020 0.970 0.350]); catch, end

    % Smaller clean font only inside the left controls
    hCtl2 = findall(panelCtrl,'Type','uicontrol');
    for jj = 1:numel(hCtl2)
        try
            sty2 = get(hCtl2(jj),'Style');
            if strcmpi(sty2,'text')
                set(hCtl2(jj),'FontSize',7.4,'FontWeight','bold','FontSize',14);
            else
                set(hCtl2(jj),'FontSize',7.8,'FontWeight','bold','FontSize',14);
            end
        catch
        end
    end

    % ======================================================
    % BOX 1: larger horizontal gaps and better alignment
    % ======================================================
    try, set(findobj(pData,'Style','text','String','Subject'),'Position',[0.020 0.790 0.100 0.080]); catch, end
    try, set(ddSubject,'Position',[0.130 0.665 0.350 0.125]); catch, end
    try, set(findobj(pData,'Style','text','String','Slice Z'),'Position',[0.535 0.790 0.090 0.080]); catch, end
    try, set(slSlice,'Position',[0.625 0.715 0.200 0.060]); catch, end
    try, set(edSlice,'Position',[0.865 0.650 0.095 0.125]); catch, end

    try, set(findobj(pData,'String','Load data'),'Position',[0.020 0.450 0.175 0.140]); catch, end
    try, set(findobj(pData,'String','Load mask'),'Position',[0.220 0.450 0.175 0.140]); catch, end
    try, set(findobj(pData,'String','Load ROI labels'),'String','ROI labels'); catch, end
    try, set(findobj(pData,'String','ROI labels'),'Position',[0.425 0.450 0.225 0.140]); catch, end
    try, set(findobj(pData,'String','Names / step folder'),'String','Region names'); catch, end
    try, set(findobj(pData,'String','Region names'),'Position',[0.690 0.450 0.270 0.140]); catch, end

    try, set(findobj(pData,'Style','text','String','Reference'),'Position',[0.020 0.215 0.115 0.080]); catch, end
    try, set(findobj(pData,'String','Load underlay / histology'),'String','Underlay / histology'); catch, end
    try, set(findobj(pData,'String','Underlay / histology'),'Position',[0.160 0.165 0.330 0.130]); catch, end
    try, set(cbAtlasLine,'Position',[0.560 0.205 0.160 0.080],'String','ROI lines'); catch, end
    try, set(cbMaskLine,'Position',[0.765 0.205 0.140 0.080],'String','Mask'); catch, end

    % ======================================================
    % BOX 4: wider gaps, centered labels, separated buttons
    % ======================================================
    try, set(findobj(pSave,'Style','text','String','Overlay'),'Position',[0.020 0.835 0.110 0.060]); catch, end
    try, set(ddOverlay,'Position',[0.145 0.805 0.310 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Color'),'Position',[0.500 0.835 0.070 0.060],'HorizontalAlignment','center'); catch, end
    try, set(ddCmapGlobal,'Position',[0.580 0.805 0.370 0.090]); catch, end

    try, set(findobj(pSave,'Style','text','String','Underlay style'),'Position',[0.020 0.690 0.160 0.060]); catch, end
    try, set(ddUnderlayStyle,'Position',[0.205 0.660 0.295 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Gamma'),'Position',[0.535 0.690 0.085 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edUGamma,'Position',[0.630 0.660 0.085 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Sharp'),'Position',[0.755 0.690 0.080 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edUSharp,'Position',[0.865 0.660 0.085 0.090]); catch, end

    try, set(findobj(pSave,'Style','text','String','Seed z-limit'),'Position',[0.020 0.545 0.160 0.060]); catch, end
    try, set(edSeedCLim,'Position',[0.190 0.515 0.085 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Overlay opacity'),'Position',[0.340 0.545 0.190 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edSeedAlpha,'Position',[0.555 0.515 0.085 0.090]); catch, end
    try, set(cbShowLR,'Position',[0.695 0.525 0.245 0.075]); catch, end

    try, set(findobj(pSave,'Style','text','String','Regions'),'Position',[0.020 0.405 0.110 0.060]); catch, end
    try, set(ddRegionMode,'Position',[0.145 0.375 0.330 0.090]); catch, end
    try, set(findobj(pSave,'Style','text','String','Labels'),'Position',[0.505 0.405 0.080 0.060],'HorizontalAlignment','center'); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.595 0.375 0.150 0.090]); catch, end
    try, set(findobj(pSave,'String','Pick'),'Position',[0.765 0.375 0.085 0.090]); catch, end
    try, set(findobj(pSave,'String','All'),'Position',[0.875 0.375 0.075 0.090]); catch, end

    try, set(findobj(fig,'Style','text','String','Window'),'Parent',pSave,'Position',[0.020 0.255 0.085 0.060]); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.110 0.225 0.170 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj start'),'String','Start'); catch, end
    try, set(findobj(fig,'Style','text','String','Start'),'Parent',pSave,'Position',[0.300 0.255 0.055 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.365 0.225 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Inj end'),'String','End'); catch, end
    try, set(findobj(fig,'Style','text','String','End'),'Parent',pSave,'Position',[0.465 0.255 0.050 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.525 0.225 0.075 0.090]); catch, end
    try, set(findobj(fig,'Style','text','String','Win'),'Parent',pSave,'Position',[0.620 0.255 0.045 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.670 0.225 0.070 0.090]); catch, end
    try, set(findobj(fig,'String','Apply win'),'String','Apply window'); catch, end
    try, set(findobj(fig,'String','Apply window'),'Parent',pSave,'Position',[0.770 0.225 0.180 0.090]); catch, end

    % Bottom row: separated, equal-looking buttons
    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.055 0.145 0.105]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.055 0.120 0.105]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.330 0.055 0.155 0.105]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.515 0.055 0.110 0.105]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.650 0.055 0.110 0.105]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.790 0.055 0.160 0.105]); catch, end

    % Cleaner text centering inside edits/buttons
    hEd = findall(pSave,'Style','edit');
    for jj = 1:numel(hEd), try, set(hEd(jj),'HorizontalAlignment','center'); catch, end, end
    hBtn = findall(pSave,'Style','pushbutton');
    for jj = 1:numel(hBtn), try, set(hBtn(jj),'FontSize',7.8,'FontWeight','bold','FontSize',14); catch, end, end

catch ME_space
    try, fprintf('FC extra spacing warning: %s\n',ME_space.message); catch, end
end
% FC_LEFT_GUI_EXTRA_SPACING_20260512_END

% RIGHT-SIDE TAB STRIP
% -------------------------------------------------------------------------
% FC_BOX4_PICK_LAYOUT_FIX_20260512_START
try
    % ================================================================
    % Final left-control layout cleanup: Box 1 and Box 4
    % ================================================================
    try, set(pData,'Position',[0.015 0.800 0.970 0.170]); catch, end
    try, set(pSave,'Position',[0.015 0.020 0.970 0.370]); catch, end

    % Make all controls slightly smaller so the gaps are visible.
    try
        hLeft = findall(panelCtrl,'Type','uicontrol');
        for ii = 1:numel(hLeft)
            try
                sty = get(hLeft(ii),'Style');
                if strcmpi(sty,'text')
                    set(hLeft(ii),'FontName',C.font,'FontSize',7.5,'FontWeight','bold','FontSize',14);
                else
                    set(hLeft(ii),'FontName',C.font,'FontSize',8,'FontWeight','bold','FontSize',14);
                end
            catch
            end
        end
    catch
    end

    % ---------------- Box 1: bigger horizontal/vertical gaps ----------------
    try, set(findobj(pData,'Style','text','String','Subject'),'Position',[0.025 0.790 0.120 0.090]); catch, end
    try, set(ddSubject,'Position',[0.150 0.645 0.360 0.145]); catch, end
    try, set(findobj(pData,'Style','text','String','Slice Z'),'Position',[0.545 0.790 0.100 0.090]); catch, end
    try, set(slSlice,'Position',[0.640 0.700 0.200 0.070]); catch, end
    try, set(edSlice,'Position',[0.865 0.625 0.095 0.155]); catch, end

    try, set(findobj(pData,'String','Load data'),'Position',[0.025 0.425 0.180 0.145]); catch, end
    try, set(findobj(pData,'String','Load mask'),'Position',[0.230 0.425 0.180 0.145]); catch, end
    try, set(findobj(pData,'String','Load ROI labels'),'String','ROI labels'); catch, end
    try, set(findobj(pData,'String','ROI labels'),'Position',[0.435 0.425 0.230 0.145]); catch, end
    try, set(findobj(pData,'String','Names / step folder'),'String','Region names'); catch, end
    try, set(findobj(pData,'String','Region names'),'Position',[0.690 0.425 0.270 0.145]); catch, end

    try, set(findobj(pData,'Style','text','String','Reference'),'Position',[0.025 0.205 0.120 0.085]); catch, end
    try, set(findobj(pData,'String','Load underlay / histology'),'String','Underlay / histology'); catch, end
    try, set(findobj(pData,'String','Underlay / histology'),'Position',[0.170 0.150 0.350 0.145]); catch, end
    try, set(cbAtlasLine,'Position',[0.575 0.185 0.160 0.090],'String','ROI lines'); catch, end
    try, set(cbMaskLine,'Position',[0.770 0.185 0.140 0.090],'String','Mask'); catch, end

    % ---------------- Box 4: clean grid, no overlaps ----------------
    try, set(findobj(pSave,'Style','text','String','Overlay'),'Position',[0.020 0.825 0.105 0.070]); catch, end
    try, set(ddOverlay,'Position',[0.145 0.805 0.310 0.095]); catch, end
    try, set(findobj(pSave,'Style','text','String','Color'),'Position',[0.505 0.825 0.070 0.070],'HorizontalAlignment','center'); catch, end
    try, set(ddCmapGlobal,'Position',[0.585 0.805 0.365 0.095]); catch, end

    try, set(findobj(pSave,'Style','text','String','Underlay style'),'Position',[0.020 0.655 0.165 0.070]); catch, end
    try, set(ddUnderlayStyle,'Position',[0.205 0.635 0.300 0.095]); catch, end
    try, set(findobj(pSave,'Style','text','String','Gamma'),'Position',[0.545 0.655 0.075 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edUGamma,'Position',[0.635 0.625 0.090 0.115]); catch, end
    try, set(findobj(pSave,'Style','text','String','Sharp'),'Position',[0.770 0.655 0.070 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edUSharp,'Position',[0.860 0.625 0.090 0.115]); catch, end

    try, set(findobj(pSave,'Style','text','String','Seed z-limit'),'Position',[0.020 0.495 0.145 0.070]); catch, end
    try, set(edSeedCLim,'Position',[0.185 0.465 0.090 0.115]); catch, end
    try, set(findobj(pSave,'Style','text','String','Overlay opacity'),'Position',[0.345 0.495 0.180 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edSeedAlpha,'Position',[0.545 0.465 0.090 0.115]); catch, end
    try, set(cbShowLR,'Position',[0.700 0.485 0.210 0.080]); catch, end

    try, set(findobj(pSave,'Style','text','String','Regions'),'Position',[0.020 0.335 0.120 0.070]); catch, end
    try, set(ddRegionMode,'Position',[0.145 0.315 0.345 0.095]); catch, end
    try, set(findobj(pSave,'Style','text','String','Labels'),'Position',[0.510 0.335 0.070 0.070],'HorizontalAlignment','center'); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.595 0.315 0.130 0.095]); catch, end

    % Pick/All buttons: separated and callback restored.
    try
        hPick = findobj(pSave,'Style','pushbutton','String','Pick');
        set(hPick,'Position',[0.745 0.305 0.095 0.115],'Callback',@onCustomRegionList,'Enable','on','Visible','on');
    catch
    end
    try
        hAll = findobj(pSave,'Style','pushbutton','String','All');
        set(hAll,'Position',[0.855 0.305 0.095 0.115],'Callback',@onClearCustomRegions,'Enable','on','Visible','on');
    catch
    end

    try, set(findobj(pSave,'Style','text','String','Window'),'Position',[0.020 0.180 0.085 0.070]); catch, end
    try, set(ddEpochMode,'Position',[0.115 0.155 0.185 0.100]); catch, end
    try, set(findobj(pSave,'Style','text','String','Start'),'Position',[0.325 0.180 0.055 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edInjStart,'Position',[0.385 0.145 0.075 0.120]); catch, end
    try, set(findobj(pSave,'Style','text','String','End'),'Position',[0.475 0.180 0.050 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edInjEnd,'Position',[0.530 0.145 0.075 0.120]); catch, end
    try, set(findobj(pSave,'Style','text','String','Win'),'Position',[0.625 0.180 0.045 0.070],'HorizontalAlignment','center'); catch, end
    try, set(edEpochWin,'Position',[0.675 0.145 0.070 0.120]); catch, end
    try, set(findobj(pSave,'String','Apply window'),'Position',[0.765 0.145 0.185 0.120]); catch, end
    try, set(findobj(pSave,'String','Apply win'),'String','Apply window','Position',[0.765 0.145 0.185 0.120]); catch, end

    % Bottom buttons: clear gaps between Reset / Region key / Save / Help / Close.
    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.035 0.145 0.100]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.035 0.125 0.100]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.335 0.035 0.160 0.100]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.520 0.035 0.120 0.100]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.665 0.035 0.120 0.100]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.810 0.035 0.140 0.100]); catch, end

    try, set(txtStatus,'Visible','off'); catch, end
catch ME_box4_final_layout
    try, fprintf('FC Box4 final layout warning: %s\n',ME_box4_final_layout.message); catch, end
end
% FC_BOX4_PICK_LAYOUT_FIX_20260512_END

% FC_EQUAL_GAPS_BOX4_COMPACT_FIX_20260512_START
try
    % ================================================================
    % Equal panel gaps + compact Box 4 layout
    % ================================================================

    % Equal vertical gaps between Box 1-2, 2-3, and 3-4.
    % Bottom margin = 0.020, top margin = 0.030, internal gaps = 0.020.
    try, set(pData,'Position',[0.015 0.795 0.970 0.175]); catch, end
    try, set(pSeed,'Position',[0.015 0.605 0.970 0.170]); catch, end
    try, set(pROI, 'Position',[0.015 0.385 0.970 0.200]); catch, end
    try, set(pSave,'Position',[0.015 0.020 0.970 0.345]); catch, end

    % Smaller fonts for the crowded left controls.
    try
        hLeft = findall(panelCtrl,'Type','uicontrol');
        for ii = 1:numel(hLeft)
            try
                sty = get(hLeft(ii),'Style');
                if strcmpi(sty,'text')
                    set(hLeft(ii),'FontName',C.font,'FontSize',7.0,'FontWeight','bold','FontSize',14);
                else
                    set(hLeft(ii),'FontName',C.font,'FontSize',7.5,'FontWeight','bold','FontSize',14);
                end
            catch
            end
        end
    catch
    end

    % ---------------- Box 1: more even spacing ----------------
    try, set(findobj(pData,'Style','text','String','Subject'),'Position',[0.025 0.790 0.120 0.085]); catch, end
    try, set(ddSubject,'Position',[0.150 0.640 0.355 0.135]); catch, end
    try, set(findobj(pData,'Style','text','String','Slice Z'),'Position',[0.555 0.790 0.095 0.085]); catch, end
    try, set(slSlice,'Position',[0.645 0.695 0.200 0.065]); catch, end
    try, set(edSlice,'Position',[0.870 0.615 0.090 0.145]); catch, end

    try, set(findobj(pData,'String','Load data'),'Position',[0.025 0.425 0.175 0.135]); catch, end
    try, set(findobj(pData,'String','Load mask'),'Position',[0.225 0.425 0.175 0.135]); catch, end
    try, set(findobj(pData,'String','Load ROI labels'),'String','ROI labels'); catch, end
    try, set(findobj(pData,'String','ROI labels'),'Position',[0.430 0.425 0.225 0.135]); catch, end
    try, set(findobj(pData,'String','Names / step folder'),'String','Region names'); catch, end
    try, set(findobj(pData,'String','Region names'),'Position',[0.685 0.425 0.275 0.135]); catch, end

    try, set(findobj(pData,'Style','text','String','Reference'),'Position',[0.025 0.205 0.120 0.080]); catch, end
    try, set(findobj(pData,'String','Load underlay / histology'),'String','Underlay / histology'); catch, end
    try, set(findobj(pData,'String','Underlay / histology'),'Position',[0.170 0.150 0.345 0.135]); catch, end
    try, set(cbAtlasLine,'Position',[0.575 0.180 0.160 0.085],'String','ROI lines'); catch, end
    try, set(cbMaskLine,'Position',[0.770 0.180 0.140 0.085],'String','Mask'); catch, end

    % ---------------- Box 4: compact, aligned, no overlap ----------------
    % Row 1
    try, set(findobj(pSave,'Style','text','String','Overlay'),'Position',[0.020 0.825 0.100 0.060]); catch, end
    try, set(ddOverlay,'Position',[0.145 0.800 0.305 0.085]); catch, end
    try, set(findobj(pSave,'Style','text','String','Color'),'Position',[0.500 0.825 0.075 0.060],'HorizontalAlignment','center'); catch, end
    try, set(ddCmapGlobal,'Position',[0.590 0.800 0.360 0.085]); catch, end

    % Row 2
    try, set(findobj(pSave,'Style','text','String','Underlay style'),'Position',[0.020 0.665 0.160 0.060]); catch, end
    try, set(ddUnderlayStyle,'Position',[0.205 0.640 0.300 0.085]); catch, end
    try, set(findobj(pSave,'Style','text','String','Gamma'),'Position',[0.530 0.665 0.105 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edUGamma,'Position',[0.650 0.625 0.085 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','Sharp'),'Position',[0.765 0.665 0.085 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edUSharp,'Position',[0.865 0.625 0.085 0.105]); catch, end

    % Row 3
    try, set(findobj(pSave,'Style','text','String','Seed z-limit'),'Position',[0.020 0.510 0.145 0.060]); catch, end
    try, set(edSeedCLim,'Position',[0.185 0.475 0.085 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','Overlay opacity'),'Position',[0.340 0.510 0.185 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edSeedAlpha,'Position',[0.545 0.475 0.085 0.105]); catch, end
    try, set(cbShowLR,'Position',[0.700 0.495 0.220 0.075]); catch, end

    % Row 4
    try, set(findobj(pSave,'Style','text','String','Regions'),'Position',[0.020 0.350 0.115 0.060]); catch, end
    try, set(ddRegionMode,'Position',[0.145 0.325 0.340 0.085]); catch, end
    try, set(findobj(pSave,'Style','text','String','Labels'),'Position',[0.505 0.350 0.075 0.060],'HorizontalAlignment','center'); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.595 0.325 0.130 0.085]); catch, end
    try
        hPick = findobj(pSave,'Style','pushbutton','String','Pick');
        set(hPick,'Position',[0.750 0.315 0.085 0.105],'Callback',@onCustomRegionList,'Enable','on','Visible','on');
    catch
    end
    try
        hAll = findobj(pSave,'Style','pushbutton','String','All');
        set(hAll,'Position',[0.865 0.315 0.085 0.105],'Callback',@onClearCustomRegions,'Enable','on','Visible','on');
    catch
    end

    % Row 5
    try, set(findobj(pSave,'Style','text','String','Window'),'Position',[0.020 0.195 0.085 0.060]); catch, end
    try, set(ddEpochMode,'Position',[0.110 0.170 0.180 0.085]); catch, end
    try, set(findobj(pSave,'Style','text','String','Start'),'Position',[0.315 0.195 0.060 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edInjStart,'Position',[0.385 0.155 0.070 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','End'),'Position',[0.475 0.195 0.055 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edInjEnd,'Position',[0.540 0.155 0.070 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','Win'),'Position',[0.630 0.195 0.045 0.060],'HorizontalAlignment','center'); catch, end
    try, set(edEpochWin,'Position',[0.685 0.155 0.065 0.105]); catch, end
    try, set(findobj(pSave,'String','Apply win'),'String','Apply window'); catch, end
    try, set(findobj(pSave,'String','Apply window'),'Position',[0.770 0.155 0.180 0.105]); catch, end

    % Bottom row
    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.035 0.145 0.095]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.035 0.125 0.095]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.335 0.035 0.160 0.095]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.520 0.035 0.120 0.095]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.665 0.035 0.120 0.095]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.810 0.035 0.140 0.095]); catch, end

    try, set(txtStatus,'Visible','off'); catch, end
catch ME_equal_gap_box4
    try, fprintf('FC equal-gap/Box4 layout warning: %s\n',ME_equal_gap_box4.message); catch, end
end
% FC_EQUAL_GAPS_BOX4_COMPACT_FIX_20260512_END

% FC_HEATMAP_WINDOW_LAYOUT_FIX_20260512_START
try
    % Equal panel gaps.
    try, set(pData,'Position',[0.015 0.795 0.970 0.175]); catch, end
    try, set(pSeed,'Position',[0.015 0.605 0.970 0.170]); catch, end
    try, set(pROI, 'Position',[0.015 0.385 0.970 0.200]); catch, end
    try, set(pSave,'Position',[0.015 0.020 0.970 0.345]); catch, end

    % Slightly smaller controls.
    try
        hLeft = findall(panelCtrl,'Type','uicontrol');
        for ii = 1:numel(hLeft)
            try
                sty = get(hLeft(ii),'Style');
                if strcmpi(sty,'text')
                    set(hLeft(ii),'FontName',C.font,'FontSize',7.0,'FontWeight','bold','FontSize',14);
                else
                    set(hLeft(ii),'FontName',C.font,'FontSize',7.5,'FontWeight','bold','FontSize',14);
                end
            catch
            end
        end
    catch
    end

    % Box 4: move upper controls upward and increase bottom-button gap.
    try, set(findobj(pSave,'Style','text','String','Overlay'),'Position',[0.020 0.850 0.100 0.055]); catch, end
    try, set(ddOverlay,'Position',[0.145 0.825 0.300 0.080]); catch, end
    try, set(findobj(pSave,'Style','text','String','Color'),'Position',[0.500 0.850 0.075 0.055],'HorizontalAlignment','center'); catch, end
    try, set(ddCmapGlobal,'Position',[0.590 0.825 0.360 0.080]); catch, end

    try, set(findobj(pSave,'Style','text','String','Underlay style'),'Position',[0.020 0.715 0.160 0.055]); catch, end
    try, set(ddUnderlayStyle,'Position',[0.205 0.690 0.300 0.080]); catch, end
    try, set(findobj(pSave,'Style','text','String','Gamma'),'Position',[0.530 0.715 0.105 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edUGamma,'Position',[0.650 0.675 0.085 0.100]); catch, end
    try, set(findobj(pSave,'Style','text','String','Sharp'),'Position',[0.765 0.715 0.085 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edUSharp,'Position',[0.865 0.675 0.085 0.100]); catch, end

    try, set(findobj(pSave,'Style','text','String','Seed z-limit'),'Position',[0.020 0.585 0.145 0.055]); catch, end
    try, set(edSeedCLim,'Position',[0.185 0.545 0.085 0.100]); catch, end
    try, set(findobj(pSave,'Style','text','String','Overlay opacity'),'Position',[0.330 0.585 0.190 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edSeedAlpha,'Position',[0.540 0.545 0.085 0.100]); catch, end
    try, set(cbShowLR,'Position',[0.700 0.560 0.220 0.070]); catch, end

    try, set(findobj(pSave,'Style','text','String','Regions'),'Position',[0.020 0.445 0.115 0.055]); catch, end
    try, set(ddRegionMode,'Position',[0.145 0.420 0.330 0.080]); catch, end
    try, set(findobj(pSave,'Style','text','String','Labels'),'Position',[0.500 0.445 0.075 0.055],'HorizontalAlignment','center'); catch, end
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Position',[0.590 0.420 0.130 0.080]); catch, end
    try, set(findobj(pSave,'Style','pushbutton','String','Pick'),'Position',[0.745 0.410 0.090 0.100],'Callback',@onCustomRegionList,'Enable','on','Visible','on'); catch, end
    try, set(findobj(pSave,'Style','pushbutton','String','All'),'Position',[0.860 0.410 0.090 0.100],'Callback',@onClearCustomRegions,'Enable','on','Visible','on'); catch, end

    try, set(findobj(pSave,'Style','text','String','Window'),'Position',[0.020 0.260 0.080 0.055],'HorizontalAlignment','center'); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.105 0.235 0.175 0.080]); catch, end
    try, set(findobj(pSave,'Style','text','String','Start'),'Position',[0.300 0.260 0.055 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.360 0.220 0.070 0.100]); catch, end
    try, set(findobj(pSave,'Style','text','String','End'),'Position',[0.450 0.260 0.055 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.510 0.220 0.070 0.100]); catch, end
    try, set(findobj(pSave,'Style','text','String','Win'),'Position',[0.600 0.260 0.045 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.650 0.220 0.065 0.100]); catch, end
    try, set(cbEpochUseWin,'Parent',pSave,'Position',[0.730 0.235 0.095 0.075],'String','Use win'); catch, end
    try, set(findobj(pSave,'String','Apply win'),'String','Apply'); catch, end
    try, set(findobj(pSave,'String','Apply window'),'String','Apply'); catch, end
    try, set(findobj(pSave,'String','Apply'),'Position',[0.775 0.165 0.180 0.085]); catch, end

    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.035 0.145 0.090]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.035 0.125 0.090]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.335 0.035 0.160 0.090]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.520 0.035 0.120 0.090]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.665 0.035 0.120 0.090]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.810 0.035 0.140 0.090]); catch, end
catch ME_layout_final
    try, fprintf('FC layout final warning: %s\n',ME_layout_final.message); catch, end
end
% FC_HEATMAP_WINDOW_LAYOUT_FIX_20260512_END

% FC_BOX2_BOX4_HEATMAP_MICROFIX_20260512_START
try
    % Keep equal panel gaps.
    try, set(pData,'Position',[0.015 0.795 0.970 0.175]); catch, end
    try, set(pSeed,'Position',[0.015 0.605 0.970 0.170]); catch, end
    try, set(pROI, 'Position',[0.015 0.385 0.970 0.200]); catch, end
    try, set(pSave,'Position',[0.015 0.020 0.970 0.345]); catch, end

    % Box 2: Seed-based FC, remove overlaps.
    try, set(findobj(pSeed,'Style','text','String','X'),'Position',[0.025 0.720 0.040 0.105]); catch, end
    try, set(edSeedX,'Position',[0.080 0.685 0.095 0.165]); catch, end
    try, set(findobj(pSeed,'Style','text','String','Y'),'Position',[0.205 0.720 0.040 0.105]); catch, end
    try, set(edSeedY,'Position',[0.260 0.685 0.095 0.165]); catch, end
    try, set(findobj(pSeed,'Style','text','String','Size'),'Position',[0.390 0.720 0.070 0.105]); catch, end
    try, set(edSeedSize,'Position',[0.465 0.685 0.105 0.165]); catch, end
    try, set(cbSliceOnly,'Position',[0.630 0.720 0.200 0.105]); catch, end
    try, set(findobj(pSeed,'Style','text','String','Map'),'Position',[0.025 0.450 0.070 0.100]); catch, end
    try, set(ddSeedDisplay,'Position',[0.125 0.425 0.265 0.145]); catch, end
    try, set(findobj(pSeed,'Style','text','String','|r| thr'),'Position',[0.450 0.450 0.120 0.100]); catch, end
    try, set(edSeedThr,'Position',[0.590 0.425 0.115 0.145]); catch, end
    try, set(findobj(pSeed,'String','Seed current'),'Position',[0.025 0.110 0.285 0.185]); catch, end
    try, set(findobj(pSeed,'String','Seed all'),'Position',[0.335 0.110 0.255 0.185]); catch, end
    try, set(findobj(pSeed,'String','Load ROI TXT'),'Position',[0.620 0.110 0.330 0.185]); catch, end

    % Box 4: Use win and Apply separated. Apply stays blue and clickable.
    try, set(findobj(pSave,'Style','text','String','Window'),'Position',[0.020 0.265 0.075 0.055],'HorizontalAlignment','center'); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.100 0.235 0.160 0.085]); catch, end
    try, set(findobj(pSave,'Style','text','String','Start'),'Position',[0.280 0.265 0.055 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.340 0.220 0.065 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','End'),'Position',[0.420 0.265 0.050 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.475 0.220 0.065 0.105]); catch, end
    try, set(findobj(pSave,'Style','text','String','Win'),'Position',[0.555 0.265 0.045 0.055],'HorizontalAlignment','center'); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.605 0.220 0.060 0.105]); catch, end
    try
        if exist('cbEpochUseWin','var') && ishandle(cbEpochUseWin)
            set(cbEpochUseWin,'Parent',pSave,'Position',[0.685 0.240 0.100 0.070],'String','Use win','BackgroundColor',C.bgPane,'ForegroundColor',C.fg);
        end
    catch
    end
    try, set(findobj(pSave,'String','Apply win'),'String','Apply'); catch, end
    try, set(findobj(pSave,'String','Apply window'),'String','Apply'); catch, end
    try
        hApply = findobj(pSave,'Style','pushbutton','String','Apply');
        set(hApply,'Position',[0.810 0.220 0.140 0.105],'BackgroundColor',C.blue,'ForegroundColor','w','Callback',@onEpochApply,'Enable','on','Visible','on');
    catch
    end

    % Give bottom buttons a little more breathing room.
    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.035 0.145 0.090]); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.035 0.125 0.090]); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.335 0.035 0.160 0.090]); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.520 0.035 0.120 0.090]); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.665 0.035 0.120 0.090]); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.810 0.035 0.140 0.090]); catch, end

    % Bigger heatmap/graph axes after creation as well.
    try, set(axHeat,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axHeatCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(txtHeat,'Position',[0.945 0.865 0.055 0.115]); catch, end
    try, set(axAdj,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axGraphCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(txtGraph,'Position',[0.945 0.865 0.055 0.115]); catch, end
catch ME_micro
    try, fprintf('FC micro-layout warning: %s\n',ME_micro.message); catch, end
end
% FC_BOX2_BOX4_HEATMAP_MICROFIX_20260512_END

% FC_FINAL_USEWIN_BOX4_LAYOUT_20260512_START
try
    % Make Box 4 slightly cleaner.
    try, set(pSave,'Position',[0.015 0.020 0.970 0.345]); catch, end

    % Window row: keep all labels centered and on one line.
    try, set(findobj(pSave,'Style','text','String','Window'),'Position',[0.020 0.255 0.090 0.060],'HorizontalAlignment','center','FontSize',8); catch, end
    try, set(ddEpochMode,'Parent',pSave,'Position',[0.115 0.225 0.155 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'Style','text','String','Start'),'Position',[0.285 0.255 0.055 0.060],'HorizontalAlignment','center','FontSize',8); catch, end
    try, set(edInjStart,'Parent',pSave,'Position',[0.345 0.215 0.060 0.105],'FontSize',8); catch, end
    try, set(findobj(pSave,'Style','text','String','End'),'Position',[0.420 0.255 0.050 0.060],'HorizontalAlignment','center','FontSize',8); catch, end
    try, set(edInjEnd,'Parent',pSave,'Position',[0.475 0.215 0.060 0.105],'FontSize',8); catch, end
    try, set(findobj(pSave,'Style','text','String','Win'),'Position',[0.550 0.255 0.045 0.060],'HorizontalAlignment','center','FontSize',8); catch, end
    try, set(edEpochWin,'Parent',pSave,'Position',[0.600 0.215 0.060 0.105],'FontSize',8); catch, end

    % Keep only one visible Apply button.
    try, set(findobj(pSave,'String','Apply win'),'String','Apply'); catch, end
    try, set(findobj(pSave,'String','Apply window'),'String','Apply'); catch, end
    hApply = [];
    try, hApply = findobj(pSave,'Style','pushbutton','String','Apply'); catch, end
    if ~isempty(hApply)
        try, set(hApply(2:end),'Visible','off'); catch, end
        try
            set(hApply(1),'Visible','on','Enable','on', ...
                'Position',[0.780 0.230 0.175 0.095], ...
                'String','Apply', ...
                'BackgroundColor',C.blue,'ForegroundColor','w', ...
                'FontName',C.font,'FontSize',8,'FontWeight','bold', ...
                'Callback',@onEpochApply);
        catch
        end
    end

    % Move Use win BELOW Apply, no overlap.
    try
        hUse = findobj(pSave,'String','Use win');
        if ~isempty(hUse)
            set(hUse,'Parent',pSave, ...
                'Position',[0.790 0.155 0.155 0.060], ...
                'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
                'FontName',C.font,'FontSize',8,'FontWeight','bold', ...
                'Visible','on','Enable','on');
        end
    catch
    end

    % Bottom buttons: keep separated.
    try, set(findobj(pSave,'String','Export GA'),'Position',[0.020 0.035 0.145 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'String','Reset view'),'String','Reset'); catch, end
    try, set(findobj(pSave,'String','Reset'),'Position',[0.185 0.035 0.125 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'String','Region key'),'Position',[0.335 0.035 0.160 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'String','Save'),'Position',[0.520 0.035 0.120 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'String','Help'),'Position',[0.665 0.035 0.120 0.090],'FontSize',8); catch, end
    try, set(findobj(pSave,'String','Close'),'Position',[0.810 0.035 0.140 0.090],'FontSize',8); catch, end
catch ME_box4_final
    try, fprintf('FC final Box 4 layout warning: %s\n',ME_box4_final.message); catch, end
end
% FC_FINAL_USEWIN_BOX4_LAYOUT_20260512_END

% FC_LAST_USEWIN_HEATMAP_LAYOUT_20260512_START
try
    % --- Box 4: final Use win / Apply separation ---
    try, set(findobj(pSave,'String','Apply win'),'String','Apply'); catch, end
    try, set(findobj(pSave,'String','Apply window'),'String','Apply'); catch, end
    hApply = findobj(pSave,'Style','pushbutton','String','Apply');
    if ~isempty(hApply)
        try, set(hApply(2:end),'Visible','off'); catch, end
        try
            set(hApply(1),'Visible','on','Enable','on', ...
                'Position',[0.780 0.265 0.175 0.075], ...
                'String','Apply', ...
                'BackgroundColor',C.blue,'ForegroundColor','w', ...
                'FontName',C.font,'FontSize',8,'FontWeight','bold', ...
                'Callback',@onEpochApply);
        catch
        end
    end

    hUse = findobj(pSave,'String','Use win');
    if ~isempty(hUse)
        try
            set(hUse,'Parent',pSave, ...
                'Position',[0.800 0.145 0.140 0.055], ...
                'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
                'FontName',C.font,'FontSize',8,'FontWeight','bold', ...
                'Visible','on','Enable','on');
        catch
        end
    end

    % --- Heatmap / Graph: final large plot positions ---
    try, set(axHeat,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axHeatCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(txtHeat,  'Position',[0.935 0.735 0.060 0.185],'FontSize',8,'HorizontalAlignment','left'); catch, end
    try, set(axAdj,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axGraphCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(txtGraph, 'Position',[0.935 0.735 0.060 0.185],'FontSize',8,'HorizontalAlignment','left'); catch, end
catch ME_last_layout
    try, fprintf('FC last layout warning: %s\n',ME_last_layout.message); catch, end
end
% FC_LAST_USEWIN_HEATMAP_LAYOUT_20260512_END

tabNames = {'Seed Map','ROI Heatmap','Compare ROI','Pair ROI','Graph'};
tabKeys  = {'seed','heatmap','compare','pair','graph'};
tabBtns = zeros(numel(tabNames),1);
for k = 1:numel(tabNames)
    tabBtns(k) = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
        'Position',[0.020 + (k-1)*0.182 0.940 0.165 0.040], ...
        'String',tabNames{k}, 'Value',double(k==1), ...
        'BackgroundColor',fc_if(k==1,C.blue,C.bgBtn), ...
        'ForegroundColor',fc_if(k==1,[1 1 1],C.fg), ...
        'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall, ...
        'Callback',@(src,evt)switchTab(tabKeys{k}));
end

pSeedView  = fc_view(panelViewWrap,C,'on');
pHeatView  = fc_view(panelViewWrap,C,'off');
pCompView  = fc_view(panelViewWrap,C,'off');
pPairView  = fc_view(panelViewWrap,C,'off');
pGraphView = fc_view(panelViewWrap,C,'off');

% Seed Map tab
txtSeedSlice = uicontrol('Parent',pSeedView,'Style','text','Units','normalized', ...
    'Position',[0.035 0.900 0.570 0.040], ...
    'String',sprintf('Seed map | slice Z %d / %d   mouse-wheel = change slice',st.slice,st.Z), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall);
axMap = axes('Parent',pSeedView,'Units','normalized','Position',[0.035 0.080 0.570 0.810], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axis(axMap,'image'); axis(axMap,'off');
hUnder = image(axMap,fc_get_underlay(st));
hold(axMap,'on');
hOver = imagesc(axMap,nan(Y,X,3)); set(hOver,'AlphaData',0);
hAtlas = imagesc(axMap,nan(Y,X,3)); set(hAtlas,'AlphaData',0);
hMask = imagesc(axMap,nan(Y,X,3)); set(hMask,'AlphaData',0);
hCrossH = line(axMap,[1 X],[st.seedY st.seedY],'Color',C.cross,'LineWidth',1.2);
hCrossV = line(axMap,[st.seedX st.seedX],[1 Y],'Color',C.cross,'LineWidth',1.2);
hSeedBox = rectangle('Parent',axMap, ...
    'Position',fc_seed_box_position(st.seedX,st.seedY,st.seedBoxSize,X,Y), ...
    'EdgeColor',C.seedBox,'LineWidth',2.5,'HitTest','off');
hold(axMap,'off');
set([hUnder hOver hAtlas hMask],'ButtonDownFcn',@onMapClick);
set(axMap,'ButtonDownFcn',@onMapClick);

uicontrol('Parent',pSeedView,'Style','text','Units','normalized','Position',[0.665 0.870 0.285 0.050], ...
    'String','Seed-map display','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsBig);

axSeedCB = axes('Parent',pSeedView,'Units','normalized','Position',[0.665 0.775 0.285 0.040], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);

uicontrol('Parent',pSeedView,'Style','text','Units','normalized','Position',[0.690 0.715 0.270 0.045], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

axSeedTS = axes('Parent',pSeedView,'Units','normalized','Position',[0.665 0.470 0.285 0.170], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axSeedHist = axes('Parent',pSeedView,'Units','normalized','Position',[0.665 0.160 0.285 0.190], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);

% ROI Heatmap tab - bigger
axHeat = axes('Parent',pHeatView,'Units','normalized','Position',[0.070 0.115 0.845 0.845], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axHeatCB = axes('Parent',pHeatView,'Units','normalized','Position',[0.955 0.215 0.022 0.600], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);
axHeatTS = axes('Parent',pHeatView,'Units','normalized','Position',[0.940 0.630 0.045 0.170],'Visible','off', ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtHeat = uicontrol('Parent',pHeatView,'Style','text','Units','normalized', ...
    'Position',[0.945 0.865 0.055 0.115], 'String','No heatmap yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsSmall);

% Compare ROI tab
axCompareBar = axes('Parent',pCompView,'Units','normalized','Position',[0.080 0.545 0.860 0.340], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axCompareMap = axes('Parent',pCompView,'Units','normalized','Position',[0.080 0.120 0.360 0.340], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axCompareCB = axes('Parent',pCompView,'Units','normalized','Position',[0.080 0.065 0.360 0.035], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);
axCompareTS = axes('Parent',pCompView,'Units','normalized','Position',[0.530 0.230 0.410 0.230], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtCompare = uicontrol('Parent',pCompView,'Style','text','Units','normalized', ...
    'Position',[0.530 0.065 0.410 0.120], 'String','Compute ROI FC and select a region.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsSmall);
txtCompareSlice = uicontrol('Parent',pCompView,'Style','text','Units','normalized', ...
    'Position',[0.080 0.465 0.360 0.045], ...
    'String',sprintf('Compare map slice Z %d / %d   scroll = change slice',st.slice,st.Z), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

% Pair ROI tab - positions fixed to avoid top cut-off
uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.055 0.900 0.080 0.055], ...
    'String','ROI A','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall);

ddPairA = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.125 0.898 0.330 0.060], 'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'Callback',@onPair);

uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.500 0.900 0.080 0.055], ...
    'String','ROI B','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall);

ddPairB = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.580 0.898 0.350 0.060], 'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsSmall,'Callback',@onPair);

uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.055 0.840 0.090 0.045], ...
    'String','Color A','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

ddPairColorA = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.125 0.838 0.200 0.050], 'String',{'Blue','Gray','Orange','Green','Purple','Red','White'}, ...
    'Value',1,'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onPair);

uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.500 0.840 0.090 0.045], ...
    'String','Color B','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

ddPairColorB = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.580 0.838 0.200 0.050], 'String',{'Orange','Gray','Blue','Green','Purple','Red','White'}, ...
    'Value',1,'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onPair);

txtPair = uicontrol('Parent',pPairView,'Style','text','Units','normalized', ...
    'Position',[0.060 0.755 0.880 0.075], 'String','Pair ROI compares exactly two selected atlas regions.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsSmall);

axPairTS = axes('Parent',pPairView,'Units','normalized','Position',[0.080 0.505 0.840 0.200], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axPairScat = axes('Parent',pPairView,'Units','normalized','Position',[0.080 0.135 0.380 0.280], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axPairLag = axes('Parent',pPairView,'Units','normalized','Position',[0.540 0.135 0.380 0.280], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);

% Graph tab - bigger heatmap, degree axis hidden
axAdj = axes('Parent',pGraphView,'Units','normalized','Position',[0.070 0.115 0.845 0.845], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axGraphCB = axes('Parent',pGraphView,'Units','normalized','Position',[0.955 0.215 0.022 0.600], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);
axDeg = axes('Parent',pGraphView,'Units','normalized','Position',[0.940 0.630 0.045 0.170], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim,'Visible','off');
txtGraph = uicontrol('Parent',pGraphView,'Style','text','Units','normalized', ...
    'Position',[0.945 0.865 0.055 0.115], 'String','No graph yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsSmall);

% FC_CLEAN_FULLSIZE_FIXED_NO_BAD_RESIZE
try, set(fig,'ResizeFcn',''); catch, end
% FC_FINAL_HEATMAP_GRAPH_LAYOUT_20260512_START
try
    try, set(findobj(fig,'Tag','FC_MatrixTickMode'),'Value',2); catch, end
    try, set(axHeat,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axAdj,'Position',[0.070 0.115 0.845 0.845]); catch, end
    try, set(axHeatCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(axGraphCB,'Position',[0.955 0.215 0.022 0.600]); catch, end
    try, set(txtHeat,'Position',[0.945 0.865 0.055 0.115],'FontSize',9,'HorizontalAlignment','left'); catch, end
    try, set(txtGraph,'Position',[0.945 0.865 0.055 0.115],'FontSize',9,'HorizontalAlignment','left'); catch, end
catch ME_final_layout
    try, fprintf('FC heatmap/graph final layout warning: %s\n',ME_final_layout.message); catch, end
end
% FC_FINAL_HEATMAP_GRAPH_LAYOUT_20260512_END

% FC_FISHERZ_STATS_PATCH_20260512_START
% FC bundle convention: Fisher z for averaging/statistics, Pearson r for display.
% FC_FISHERZ_STATS_PATCH_20260512_END
guidata(fig,st);
% HUMOR_FC_PRELOAD_SEGMENTATION_PATCH_20260519
try
    sPre = guidata(fig);
    if isfield(sPre.opts,'preloadSegmentationFile') && ~isempty(sPre.opts.preloadSegmentationFile) && exist(sPre.opts.preloadSegmentationFile,'file') == 2
        subjPre = sPre.subjects(sPre.currentSubject);
        [resPre, segInfoPre, roiAtlasPre] = fc_read_segmentation_result(sPre.opts.preloadSegmentationFile, subjPre.TR, sPre.opts);
        resPre = fc_apply_epoch_to_roi_result(resPre,sPre);
        sPre.roiResults{sPre.currentSubject,sPre.currentEpoch} = resPre;
        sPre.loadedSegmentationFile = sPre.opts.preloadSegmentationFile;
        if ~isempty(roiAtlasPre)
            try
                Apre = fc_fit_volume(fc_repair_signed_label_map(roiAtlasPre), sPre.Y, sPre.X, sPre.Z, false);
                if ~isempty(Apre) && fc_looks_like_roi_label_map(Apre)
                    sPre.subjects(sPre.currentSubject).roiAtlas = round(double(Apre));
                end
            catch
            end
        end
        if isfield(segInfoPre,'TR') && isfinite(segInfoPre.TR) && segInfoPre.TR > 0
            sPre.subjects(sPre.currentSubject).TR = segInfoPre.TR;
        end
        guidata(fig,sPre);
        updateROIDropdowns(resPre.names);
        setStatus(sprintf('Preloaded step-motor segmentation: %d regions, %d time points.',numel(resPre.labels),size(resPre.meanTS,1)),C.good);
    end
catch ME_preloadSeg
    try, setStatus(['Step-motor segmentation preload skipped: ' ME_preloadSeg.message],C.warn); catch, end
end
refreshAll();

% =========================================================================
% CALLBACKS
% =========================================================================
    function onClose(~,~)
        try
            s = guidata(fig);
            if isfield(s.opts,'statusFcn') && isa(s.opts.statusFcn,'function_handle')
                s.opts.statusFcn(true);
            end
        catch
        end
        try, delete(fig); catch, end
    end

    function onMouseWheel(~,ev)
        s = guidata(fig);
        if ~isfield(s,'Z') || s.Z <= 1, return; end
        step = 1;
        try
            if ev.VerticalScrollCount < 0, step = -1; else, step = 1; end
        catch
            step = 1;
        end
        s.slice = fc_clip(round(s.slice + step),1,s.Z);
        try, set(slSlice,'Value',s.slice); catch, end
        try, set(edSlice,'String',num2str(s.slice)); catch, end
        try, set(edSliceBox,'String',num2str(s.slice)); catch, end
        guidata(fig,s);
        try, setStatus(sprintf('Slice Z %d/%d. Heatmap/Compare refreshed.',s.slice,s.Z),C.dim); catch, end
        refreshAll();
    end

    function setStatus(msg,col)
        if nargin < 2, col = C.dim; end
        if exist('txtStatus','var') && ~isempty(txtStatus) && ishandle(txtStatus)
            set(txtStatus,'String',msg,'ForegroundColor',col);
            drawnow limitrate;
        end
        try
            s0 = guidata(fig);
            fc_log(s0.opts,msg);
        catch
            fc_log(st.opts,msg);
        end
    end

    function onHelp(~,~)
        fc_help_dialog(C);
    end

    function onOpenRegionKey(~,~)
        s = guidata(fig);
        try
            res = s.roiResults{s.currentSubject,s.currentEpoch};
            if isempty(res) || ~isfield(res,'labels') || isempty(res.labels)
                errordlg('No ROI/Segmentation result is loaded yet. Load Seg MAT or compute ROI FC first.','Region key');
                return;
            end

            [~,namesOrdered,order,meta] = fc_current_matrix(s,res);
            if exist('meta','var') && isfield(meta,'displayLabels')
                labelsOrdered = double(meta.displayLabels(:));
            else
                labelsOrdered = double(res.labels(order));
            end
            namesOrdered = namesOrdered(:);
            n = numel(labelsOrdered);

            abbr = fc_abbrev_only_list(namesOrdered,18);
            displayNames = fc_abbrev_list(namesOrdered,22,false);
            abbr = abbr(:);

            fullNames = cell(n,1);
            for kk = 1:n
                nm = char(namesOrdered{kk});
                nm = regexprep(nm,'\s*\[[^\]]*\]\s*$','');
                fullNames{kk} = fc_region_fullname_no_lr(strtrim(nm));
                if isempty(fullNames{kk})
                    fullNames{kk} = char(namesOrdered{kk});
                end
            end

            fullSource = 'Current ROI result names';

            % --------------------------------------------------
            % A) Try loaded region-name table first.
            %    If this table contains full names, use them.
            % --------------------------------------------------
            try
                if isfield(s,'opts') && isfield(s.opts,'roiNameTable')
                    T = s.opts.roiNameTable;
                    if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
                        for kk = 1:n
                            idx = find(abs(double(T.labels(:))) == abs(labelsOrdered(kk)),1,'first');
                            if ~isempty(idx) && idx <= numel(T.names)
                                nm = strtrim(char(T.names{idx}));
                                if ~isempty(nm)
                                    fullNames{kk} = nm;
                                    fullSource = 'Loaded region-name table';
                                end
                            end
                        end
                    end
                end
            catch
            end

            % --------------------------------------------------
            % B) Best source: HUMoR Segmentation MAT.
            %    Use Seg.region.acronyms for Abbrev and
            %    Seg.region.names for Full region name.
            % --------------------------------------------------
            segFile = '';
            try
                if isfield(res,'sourceFile') && ~isempty(res.sourceFile) && exist(res.sourceFile,'file')
                    segFile = res.sourceFile;
                elseif isfield(s,'loadedSegmentationFile') && ~isempty(s.loadedSegmentationFile) && exist(s.loadedSegmentationFile,'file')
                    segFile = s.loadedSegmentationFile;
                end
            catch
                segFile = '';
            end

            try
                if ~isempty(segFile)
                    Sseg = load(segFile);
                    if isfield(Sseg,'Seg')
                        Seg = Sseg.Seg;
                    else
                        Seg = Sseg;
                    end

                    if isfield(Seg,'region') && isstruct(Seg.region) && isfield(Seg.region,'labels')
                        labs0 = double(Seg.region.labels(:));
                        acr0 = {};
                        nam0 = {};

                        if isfield(Seg.region,'acronyms') && ~isempty(Seg.region.acronyms)
                            acr0 = cellstr(Seg.region.acronyms(:));
                        end
                        if isfield(Seg.region,'names') && ~isempty(Seg.region.names)
                            nam0 = cellstr(Seg.region.names(:));
                        end

                        for kk = 1:n
                            idx = find(abs(labs0) == abs(labelsOrdered(kk)),1,'first');
                            if isempty(idx)
                                continue;
                            end

                            if idx <= numel(acr0)
                                a0 = strtrim(char(acr0{idx}));
                                if ~isempty(a0) && ~strcmpi(a0,'unknown')
                                    abbr{kk} = fc_roi_abbrev_only(a0,18);
                                end
                            end

                            if idx <= numel(nam0)
                                n0 = strtrim(char(nam0{idx}));
                                if ~isempty(n0) && ~strcmpi(n0,'unknown')
                                    fullNames{kk} = n0;
                                    fullSource = 'Seg.region.names from Segmentation MAT';
                                end
                            end
                        end
                    end
                end
            catch MEsegKey
                setStatus(['Region key full-name lookup warning: ' MEsegKey.message],C.warn);
            end

            dataCell = [num2cell((1:n)'), num2cell(labelsOrdered(:)), displayNames(:), abbr(:), fullNames(:)];

            bg = [0.06 0.06 0.07];
            fg = [0.96 0.96 0.96];
            fKey = figure('Name','FC Region key - full names', ...
                'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
                'Units','pixels','Position',[120 45 1350 900]);
            try, movegui(fKey,'center'); catch, end

            uicontrol('Parent',fKey,'Style','text','Units','normalized', ...
                'Position',[0.025 0.945 0.95 0.035], ...
                'String','Region key sorted in the same order as the heatmap. One row = one region.', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontName','Arial','FontWeight','bold','FontSize',13, ...
                'HorizontalAlignment','left');

            uicontrol('Parent',fKey,'Style','text','Units','normalized', ...
                'Position',[0.025 0.910 0.95 0.030], ...
                'String',['Full-name source: ' fullSource], ...
                'BackgroundColor',bg,'ForegroundColor',[0.75 0.75 0.80], ...
                'FontName','Arial','FontWeight','bold','FontSize',11, ...
                'HorizontalAlignment','left');

            uitable('Parent',fKey,'Units','normalized', ...
                'Position',[0.025 0.085 0.95 0.815], ...
                'Data',dataCell, ...
                'ColumnName',{'#','Label','Display','Abbrev','Full region name'}, ...
                'ColumnEditable',[false false false false false], ...
                'RowName',[], ...
                'ColumnWidth',{55 90 160 130 820}, ...
                'FontName','Arial','FontSize',13);

            uicontrol('Parent',fKey,'Style','pushbutton','Units','normalized', ...
                'Position',[0.825 0.020 0.15 0.045],'String','Close', ...
                'BackgroundColor',C.red,'ForegroundColor','w', ...
                'FontName',C.font,'FontWeight','bold','FontSize',12, ...
                'Callback',@(src,evt)delete(fKey));

            setStatus(['Opened region key with full names. Source: ' fullSource],C.good);
        catch ME
            setStatus(['Region key error: ' ME.message],C.warn);
            errordlg(ME.message,'Region key');
        end
    end

    function onResetView(~,~)
        s = guidata(fig);
        s.underlayMode = 'scm';
        s.underlayViewMode = 5;
        s.underlayGamma = 0.95;
        s.underlaySharpness = 0.35;
        s.showAtlasLines = false;
        s.showMaskLine = false;
        s.overlayMode = 'seed_fc';
        s.seedDisplay = 'r';
        s.seedAbsThr = 0.20;
        s.seedAlpha = 0.70;
        s.seedCLim = 1.0;
        s.roiDisplaySpace = 'r';
        s.roiAbsThr = 0.20;
        s.roiOrder = 'name';
        s.compareSort = 'abs';
        s.cmapName = 'bwr';
        s.graphCmapName = 'bwr';
        s.showHemisphere = true; % FC_LR_LABEL_DISPLAY_PATCH_V2_RESET_STATE
        s.roiHemiMode = 'both'; % FC_REGION_MODE_PATCH_RESET
        s.fcEpochMode = 'whole'; % FC_LR_EPOCH_PATCH_RESET_MODE

        s.fcUseEpochWin = false; % FC_USE_WINDOW_RESET        try, set(ddOverlay,'Value',1); catch, end
        try, set(ddUnderlayStyle,'Value',1); catch, end
        try, set(ddCmapGlobal,'Value',1); catch, end
        try, set(ddSeedDisplay,'Value',1); catch, end
        try, set(ddROISpace,'Value',2); catch, end
        try, set(ddOrder,'Value',1); catch, end
        try, set(ddSort,'Value',1); catch, end
        try, set(cbAtlasLine,'Value',0); catch, end
        try, set(cbMaskLine,'Value',0); catch, end
        try, set(cbShowLR,'Value',1); catch, end % FC_LR_LABEL_DISPLAY_PATCH_V2_RESET_CHECKBOX
        try, set(ddRegionMode,'Value',1); catch, end % FC_REGION_MODE_PATCH_RESET_POPUP
        try, set(ddEpochMode,'Value',1); catch, end % FC_LR_EPOCH_PATCH_RESET_EPOCH_POPUP

        try, set(cbEpochUseWin,'Value',0); catch, end % FC_USE_WINDOW_RESET_CHECKBOX        try, set(edSeedThr,'String','0.20'); catch, end
        try, set(edROIThr,'String','0.20'); catch, end
        try, set(edSeedCLim,'String','1.0'); catch, end
        try, set(edSeedAlpha,'String','0.70'); catch, end
        try, set(edUGamma,'String','0.95'); catch, end
        try, set(edUSharp,'String','0.35'); catch, end
        guidata(fig,s);
        refreshAll();
        switchTab('seed');
        setStatus('View reset to SCM log/median underlay, Seed FC overlay, no ROI label overlay.',C.good);
    end

    function switchTab(whichTab)
        set(pSeedView,'Visible','off');
        set(pHeatView,'Visible','off');
        set(pCompView,'Visible','off');
        set(pPairView,'Visible','off');
        set(pGraphView,'Visible','off');
        for kk = 1:numel(tabBtns)
            if ishandle(tabBtns(kk))
                set(tabBtns(kk),'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
            end
        end
        switch lower(whichTab)
            case 'seed'
                set(pSeedView,'Visible','on'); idx = 1;
            case 'heatmap'
                set(pHeatView,'Visible','on'); idx = 2;
            case 'compare'
                set(pCompView,'Visible','on'); idx = 3;
            case 'pair'
                set(pPairView,'Visible','on'); idx = 4;
            case 'graph'
                set(pGraphView,'Visible','on'); idx = 5;
            otherwise
                set(pSeedView,'Visible','on'); idx = 1;
        end
        if ishandle(tabBtns(idx))
            set(tabBtns(idx),'Value',1,'BackgroundColor',C.blue,'ForegroundColor','w');
        end
    end

    function onSubject(~,~)
        s = guidata(fig);
        s.currentSubject = get(ddSubject,'Value');
        guidata(fig,s);
        setStatus(['Subject: ' s.subjects(s.currentSubject).name],C.dim);
        refreshAll();
    end

    function onSliceBoxEdit(~,~)
        s = guidata(fig);
        v = str2double(get(edSliceBox,'String'));
        if ~isfinite(v), v = s.slice; end
        s.slice = fc_clip(round(v),1,s.Z);
        set(slSlice,'Value',s.slice);
        set(edSlice,'String',num2str(s.slice));
        try, set(edSliceBox,'String',num2str(s.slice)); catch, end
        if ~isfield(s,'sliceRegionOnly') || isempty(s.sliceRegionOnly), s.sliceRegionOnly = false; end
        try, set(cbSliceRegionOnly,'Value',double(s.sliceRegionOnly)); catch, end
        try, set(txtSeedSlice,'String',sprintf('Seed map | slice Z %d / %d   mouse-wheel = change slice',s.slice,s.Z)); catch, end
        try, set(txtCompareSlice,'String',sprintf('Compare map slice Z %d / %d   scroll = change slice',s.slice,s.Z)); catch, end
        set(edSliceBox,'String',num2str(s.slice));
        guidata(fig,s);
        refreshAll();
    end

    function onSliceRegionOnly(~,~)
        s = guidata(fig);
        s.sliceRegionOnly = logical(get(cbSliceRegionOnly,'Value'));
        guidata(fig,s);
        refreshHeatmapView();
        refreshGraphView();
        if s.sliceRegionOnly
            setStatus(sprintf('Slice ROI filter ON: heatmap/graph show regions present in Z %d/%d.',s.slice,s.Z),C.good);
        else
            setStatus('Slice ROI filter OFF: heatmap/graph show all selected regions.',C.dim);
        end
    end

    function onSliceSlider(~,~)
        s = guidata(fig);
        s.slice = fc_clip(round(get(slSlice,'Value')),1,s.Z);
        set(edSlice,'String',num2str(s.slice));
        guidata(fig,s);
        refreshAll();
    end

    function onSliceEdit(~,~)
        s = guidata(fig);
        v = str2double(get(edSlice,'String'));
        if ~isfinite(v), v = s.slice; end
        s.slice = fc_clip(round(v),1,s.Z);
        set(slSlice,'Value',s.slice);
        set(edSlice,'String',num2str(s.slice));
        try, set(edSliceBox,'String',num2str(s.slice)); catch, end
        if ~isfield(s,'sliceRegionOnly') || isempty(s.sliceRegionOnly), s.sliceRegionOnly = false; end
        try, set(cbSliceRegionOnly,'Value',double(s.sliceRegionOnly)); catch, end
        try, set(txtSeedSlice,'String',sprintf('Seed map | slice Z %d / %d   mouse-wheel = change slice',s.slice,s.Z)); catch, end
        try, set(txtCompareSlice,'String',sprintf('Compare map slice Z %d / %d   scroll = change slice',s.slice,s.Z)); catch, end
        guidata(fig,s);
        refreshAll();
    end

    function onSeedEdit(~,~)
        s = guidata(fig);
        x = str2double(get(edSeedX,'String'));
        y = str2double(get(edSeedY,'String'));
        bs = str2double(get(edSeedSize,'String'));
        if ~isfinite(x), x = s.seedX; end
        if ~isfinite(y), y = s.seedY; end
        if ~isfinite(bs), bs = s.seedBoxSize; end
        s.seedX = fc_clip(round(x),1,s.X);
        s.seedY = fc_clip(round(y),1,s.Y);
        s.seedBoxSize = max(1,round(bs));
        guidata(fig,s);
        refreshAll();
    end

    function onSliceOnly(~,~)
        s = guidata(fig);
        s.useSliceOnly = logical(get(cbSliceOnly,'Value'));
        guidata(fig,s);
        refreshAll();
    end

    function onSeedDisplay(~,~)
        s = guidata(fig);
        if get(ddSeedDisplay,'Value') == 2
            s.seedDisplay = 'z';
        else
            s.seedDisplay = 'r';
        end
        guidata(fig,s);
        refreshSeedView();
    end

    function onColorSettings(~,~)
        s = guidata(fig);
        vals = {'bwr','winter','hot','jet','gray','parula'};
        s.cmapName = vals{get(ddCmapGlobal,'Value')};
        s.graphCmapName = s.cmapName;
        v = str2double(get(edSeedCLim,'String'));
        if isfinite(v) && v > 0
            s.seedCLim = v;
            s.roiZCLim = v;
        end
        a = str2double(get(edSeedAlpha,'String'));
        if isfinite(a)
            s.seedAlpha = max(0,min(1,a));
        end
        set(edSeedCLim,'String',num2str(s.seedCLim));
        set(edSeedAlpha,'String',sprintf('%.2f',s.seedAlpha));
        guidata(fig,s);
        refreshSeedView();
        refreshHeatmapView();
        refreshCompareView();
        refreshGraphView();
    end

    function onUnderlayStyle(~,~)
        s = guidata(fig);
        switch get(ddUnderlayStyle,'Value')
            case 1
                s.underlayViewMode = 5;
            case 2
                s.underlayViewMode = 3;
            case 3
                s.underlayViewMode = 4;
            otherwise
                s.underlayViewMode = 1;
        end
        g = str2double(get(edUGamma,'String'));
        if isfinite(g) && g > 0, s.underlayGamma = g; end
        sh = str2double(get(edUSharp,'String'));
        if isfinite(sh) && sh >= 0, s.underlaySharpness = sh; end
        set(edUGamma,'String',sprintf('%.2f',s.underlayGamma));
        set(edUSharp,'String',sprintf('%.2f',s.underlaySharpness));
        guidata(fig,s);
        refreshSeedView();
    end

    function onFlipAtlasLR(~,~)
        s = guidata(fig);
        did = false;
        for ii = 1:s.nSub
            if ~isempty(s.subjects(ii).roiAtlas)
                s.subjects(ii).roiAtlas = s.subjects(ii).roiAtlas(:,end:-1:1,:);
                s.roiResults(ii,:) = {[]};
                did = true;
            end
        end
        guidata(fig,s);
        if did
            setStatus('ROI label volume flipped left-right. Re-run ROI current before interpreting ROI FC.',C.warn);
        else
            setStatus('No ROI label volume loaded.',C.warn);
        end
        refreshAll();
    end

    function onFlipAtlasUD(~,~)
        s = guidata(fig);
        did = false;
        for ii = 1:s.nSub
            if ~isempty(s.subjects(ii).roiAtlas)
                s.subjects(ii).roiAtlas = s.subjects(ii).roiAtlas(end:-1:1,:,:);
                s.roiResults(ii,:) = {[]};
                did = true;
            end
        end
        guidata(fig,s);
        if did
            setStatus('ROI label volume flipped up-down. Re-run ROI current before interpreting ROI FC.',C.warn);
        else
            setStatus('No ROI label volume loaded.',C.warn);
        end
        refreshAll();
    end

    function onFlipUnderlayLR(~,~)
        s = guidata(fig);
        s = fc_flip_underlay_in_state(s,'lr');
        guidata(fig,s);
        setStatus('Display underlay flipped left-right. This is visual only; it does not warp data.',C.warn);
        refreshAll();
    end

    function onFlipUnderlayUD(~,~)
        s = guidata(fig);
        s = fc_flip_underlay_in_state(s,'ud');
        guidata(fig,s);
        setStatus('Display underlay flipped up-down. This is visual only; it does not warp data.',C.warn);
        refreshAll();
    end

    function onSeedThr(~,~)
        s = guidata(fig);
        v = str2double(get(edSeedThr,'String'));
        if ~isfinite(v), v = s.seedAbsThr; end
        s.seedAbsThr = max(0,min(0.99,abs(v)));
        set(edSeedThr,'String',sprintf('%.2f',s.seedAbsThr));
        guidata(fig,s);
        refreshSeedView();
    end

    function onROIThr(~,~)
        s = guidata(fig);
        v = str2double(get(edROIThr,'String'));
        if ~isfinite(v), v = s.roiAbsThr; end
        s.roiAbsThr = max(0,min(10,abs(v)));
        set(edROIThr,'String',sprintf('%.2f',s.roiAbsThr));
        guidata(fig,s);
        refreshHeatmapView();
        refreshCompareView();
        refreshGraphView();
    end

    function onROISpace(~,~)
        s = guidata(fig);
        if get(ddROISpace,'Value') == 1
            s.roiDisplaySpace = 'r';
        else
            s.roiDisplaySpace = 'r';
        end
        guidata(fig,s);
        refreshHeatmapView();
    end

    function onROIOrder(~,~)
        s = guidata(fig);
        if get(ddOrder,'Value') == 1
            s.roiOrder = 'name';
        else
            s.roiOrder = 'label';
        end
        guidata(fig,s);
        refreshHeatmapView();
        refreshCompareView();
        refreshPairView();
        refreshGraphView();
    end

    function onTopN(~,~)
        s = guidata(fig);
        v = str2double(get(edTopN,'String'));
        if ~isfinite(v), v = s.compareTopN; end
        s.compareTopN = max(1,min(50,round(v)));
        s.comparePage = 1;
        set(edTopN,'String',num2str(s.compareTopN));
        guidata(fig,s);
        refreshCompareView();
    end

    function onComparePagePrev(~,~)
        s = guidata(fig);
        if ~isfield(s,'comparePage') || isempty(s.comparePage), s.comparePage = 1; end
        s.comparePage = max(1,s.comparePage - 1);
        guidata(fig,s);
        refreshCompareView();
    end

    function onComparePageNext(~,~)
        s = guidata(fig);
        if ~isfield(s,'comparePage') || isempty(s.comparePage), s.comparePage = 1; end
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        nPartners = 1;
        if ~isempty(res)
            try
                [~,namesTmp] = fc_current_matrix(s,res);
                nPartners = max(1,numel(namesTmp)-1);
            catch
            end
        end
        pageSize = max(1,min(50,round(s.compareTopN)));
        maxPage = max(1,ceil(nPartners ./ pageSize));
        s.comparePage = min(maxPage,s.comparePage + 1);
        guidata(fig,s);
        refreshCompareView();
    end

    function onCompareSort(~,~)
        s = guidata(fig);
        vals = {'abs','positive','negative','label'};
        s.compareSort = vals{get(ddSort,'Value')};
        s.comparePage = 1;
        guidata(fig,s);
        refreshCompareView();
    end

    function onCompareROI(~,~)
        s = guidata(fig);
        s.compareROI = get(ddCompareROI,'Value');
        s.comparePage = 1;
        guidata(fig,s);
        refreshCompareView();
        refreshSeedView();
        switchTab('compare');
    end

    function onPair(~,~)
        refreshPairView();
    end

    function onUnderlay(~,~)
        s = guidata(fig);
        lst = get(ddUnderlay,'String');
        if ischar(lst), lst = cellstr(lst); end
        val = get(ddUnderlay,'Value');
        val = fc_clip(val,1,numel(lst));
        choice = lower(strtrim(lst{val}));

        if ~isempty(strfind(choice,'scm')) || ~isempty(strfind(choice,'log'))
            s.underlayMode = 'scm';
        elseif ~isempty(strfind(choice,'loaded')) || ~isempty(strfind(choice,'histology'))
            s.underlayMode = 'loaded';
        elseif ~isempty(strfind(choice,'mask editor')) || ~isempty(strfind(choice,'anatomy')) || ~isempty(strfind(choice,'anat')) || ~isempty(strfind(choice,'provided'))
            s.underlayMode = 'anat';
        elseif ~isempty(strfind(choice,'median'))
            s.underlayMode = 'median';
        elseif ~isempty(strfind(choice,'atlas')) || ~isempty(strfind(choice,'label'))
            s.underlayMode = 'atlas';
        else
            s.underlayMode = 'mean';
        end
        guidata(fig,s);
        refreshSeedView();
    end

    function onOverlay(~,~)
        s = guidata(fig);
        switch get(ddOverlay,'Value')
            case 1
                s.overlayMode = 'seed_fc';
            case 2
                s.overlayMode = 'roi_compare';
            case 3
                s.overlayMode = 'roi_pick';
            case 4
                s.overlayMode = 'atlas';
            case 5
                s.overlayMode = 'mask';
            otherwise
                s.overlayMode = 'none';
        end
        guidata(fig,s);
        refreshSeedView();
    end

    function onAtlasLine(~,~)
        s = guidata(fig);
        s.showAtlasLines = logical(get(cbAtlasLine,'Value'));
        guidata(fig,s);
        refreshSeedView();
    end

    function onMaskLine(~,~)
        s = guidata(fig);
        s.showMaskLine = logical(get(cbMaskLine,'Value'));
        guidata(fig,s);
        refreshSeedView();
    end

    function onShowHemisphere(~,~)
        s = guidata(fig);
        if exist('cbShowLR','var') && ishandle(cbShowLR)
            s.showHemisphere = logical(get(cbShowLR,'Value'));
        else
            s.showHemisphere = true;
        end
        guidata(fig,s);
        refreshHeatmapView();
        refreshCompareView();
        refreshPairView();
        refreshGraphView();
        refreshSeedView();
    end

    function onRegionMode(~,~)
        s = guidata(fig);
        try
            items = get(ddRegionMode,'String');
            val = get(ddRegionMode,'Value');
            if ischar(items), items = cellstr(items); end
            val = fc_clip(round(val),1,numel(items));
            choice = lower(strtrim(items{val}));
            if ~isempty(strfind(choice,'left')) && ~isempty(strfind(choice,'right'))
                s.roiHemiMode = 'lvr';
            elseif ~isempty(strfind(choice,'left'))
                s.roiHemiMode = 'left';
            elseif ~isempty(strfind(choice,'right'))
                s.roiHemiMode = 'right';
            elseif ~isempty(strfind(choice,'merged')) || ~isempty(strfind(choice,'no l/r')) || ~isempty(strfind(choice,'all'))
                s.roiHemiMode = 'merged';
            else
                s.roiHemiMode = 'both';
            end

            if strcmpi(s.roiHemiMode,'left') || strcmpi(s.roiHemiMode,'right') || strcmpi(s.roiHemiMode,'both')
                s.showHemisphere = true;
                try, set(cbShowLR,'Value',1); catch, end
            else
                s.showHemisphere = false;
                try, set(cbShowLR,'Value',0); catch, end
            end
        catch
            s.roiHemiMode = 'both';
        end
        guidata(fig,s);
        refreshHeatmapView();
        refreshCompareView();
        refreshPairView();
        refreshGraphView();
        refreshSeedView();
        setStatus(['Region mode: ' s.roiHemiMode],C.good);
    end

    function onEpochMode(~,~)
        s = guidata(fig);
        vals = {'whole','pre','during','post'};
        v = fc_clip(round(get(ddEpochMode,'Value')),1,numel(vals));
        s.fcEpochMode = vals{v};
        s = readEpochGuiToState(s);
        guidata(fig,s);
        setStatus(['FC window selected: ' fc_epoch_label(s)],C.good);
    end

    function onEpochEdit(~,~)
        s = guidata(fig);
        s = readEpochGuiToState(s);
        guidata(fig,s);
        setStatus(['FC window updated: ' fc_epoch_label(s)],C.good);
    end

    function onEpochApply(~,~)
        s = guidata(fig);
        s = readEpochGuiToState(s);
        didSeed = false;
        didROI = false;
        try
            % Recompute current seed result when it already exists.
            try
                seedNow = s.seedResults{s.currentSubject,s.currentEpoch};
                if ~isempty(seedNow)
                    s = computeSeed(s,s.currentSubject,s.currentEpoch);
                    didSeed = true;
                end
            catch
            end

            % Recompute/apply current ROI result when possible.
            resNow = [];
            try, resNow = s.roiResults{s.currentSubject,s.currentEpoch}; catch, end
            if ~isempty(resNow) && isfield(resNow,'meanTSFull') && ~isempty(resNow.meanTSFull)
                resNow = fc_apply_epoch_to_roi_result(resNow,s);
                s.roiResults{s.currentSubject,s.currentEpoch} = resNow;
                didROI = true;
            elseif ~isempty(s.subjects(s.currentSubject).roiAtlas)
                s = computeROI(s,s.currentSubject,s.currentEpoch);
                didROI = true;
            end

            guidata(fig,s);
            if didSeed && didROI
                setStatus(['Applied FC window to Seed FC and Region FC: ' fc_epoch_label(s)],C.good);
            elseif didSeed
                setStatus(['Applied FC window to Seed FC: ' fc_epoch_label(s)],C.good);
            elseif didROI
                setStatus(['Applied FC window to Region FC: ' fc_epoch_label(s)],C.good);
            else
                setStatus('Window saved. Press Seed current or ROI current to calculate with this window.',C.warn);
            end
            refreshAll();
        catch ME
            guidata(fig,s);
            setStatus(['Apply window error: ' ME.message],C.warn);
            errordlg(ME.message,'Apply FC window');
        end
    end

    function s = readEpochGuiToState(s)
        vals = {'whole','pre','during','post'};
        try
            v = fc_clip(round(get(ddEpochMode,'Value')),1,numel(vals));
            s.fcEpochMode = vals{v};
        catch
            if ~isfield(s,'fcEpochMode') || isempty(s.fcEpochMode), s.fcEpochMode = 'whole'; end
        end
                try
            if exist('cbEpochUseWin','var') && ishandle(cbEpochUseWin)
                s.fcUseEpochWin = logical(get(cbEpochUseWin,'Value'));
            elseif ~isfield(s,'fcUseEpochWin') || isempty(s.fcUseEpochWin)
                s.fcUseEpochWin = false;
            end
        catch
            s.fcUseEpochWin = false;
        end % FC_USE_WINDOW_READ_GUI
a = str2double(get(edInjStart,'String'));
        b = str2double(get(edInjEnd,'String'));
        w = str2double(get(edEpochWin,'String'));
        if ~isfinite(a), a = 14; end
        if ~isfinite(b), b = max(a,15); end
        if ~isfinite(w) || w <= 0, w = 3; end
        if b < a, b = a; end
        s.fcInjStartMin = max(0,a);
        s.fcInjEndMin = max(s.fcInjStartMin,b);
        s.fcEpochWinMin = max(0.01,w);
        set(edInjStart,'String',sprintf('%.2f',s.fcInjStartMin));
        set(edInjEnd,'String',sprintf('%.2f',s.fcInjEndMin));
        set(edEpochWin,'String',sprintf('%.2f',s.fcEpochWinMin));
    end
function onMapClick(~,~)
        s = guidata(fig);
        cp = get(axMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x < 1 || x > s.X || y < 1 || y > s.Y
            return;
        end

        if strcmpi(s.overlayMode,'roi_pick')
            subj = s.subjects(s.currentSubject);
            if isempty(subj.roiAtlas)
                setStatus('ROI pick needs an integer ROI label atlas.',C.warn);
                return;
            end
            [clickMap,clickOk] = fc_compare_slice(s);
        if ~clickOk || y > size(clickMap,1) || x > size(clickMap,2) || ~isfinite(clickMap(y,x))
            setStatus('Clicked region map background/no-label area.',C.warn);
            return;
        end
        atlasClickS = double(subj.roiAtlas(:,:,s.slice));
        lab = round(double(atlasClickS(y,x)));
            if ~isfinite(lab) || lab == 0
                setStatus('Clicked voxel has no ROI label.',C.warn);
                return;
            end
            res = s.roiResults{s.currentSubject,s.currentEpoch};
            if isempty(res)
                setStatus('ROI pick needs ROI current first. Compute ROI FC, then pick a region.',C.warn);
                return;
            end
            [~,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
            dispIdx = fc_display_index_from_raw_label(res,meta,lab);
            if isempty(dispIdx)
                setStatus(sprintf('Label %.0f was clicked, but it is not available in current region mode.',lab),C.warn);
                return;
            end
            s.compareROI = dispIdx;
            set(ddCompareROI,'String',fc_abbrev_list(names,18,s.showHemisphere),'Value',dispIdx);
            guidata(fig,s);
            setStatus(['Selected ROI: ' fc_roi_abbrev(names{dispIdx},20,s.showHemisphere)],C.good);
            refreshCompareView();
            switchTab('compare');
            return;
        end

        s.seedX = x;
        s.seedY = y;
        guidata(fig,s);
        refreshAll();
    end

    function onCompareMapClick(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        if isempty(res) || isempty(subj.roiAtlas)
            return;
        end
        cp = get(axCompareMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x < 1 || x > s.X || y < 1 || y > s.Y
            return;
        end
        atlasClickS = double(subj.roiAtlas(:,:,s.slice));
        lab = round(double(atlasClickS(y,x)));
        if ~isfinite(lab) || lab == 0
            setStatus('Clicked region map background/no-label area.',C.warn);
            return;
        end
        [~,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
        dispIdx = fc_display_index_from_raw_label(res,meta,lab);
        if isempty(dispIdx)
            setStatus(sprintf('Clicked label %.0f is not available in current region mode.',lab),C.warn);
            return;
        end
        s.compareROI = dispIdx;
        try, set(ddCompareROI,'String',fc_abbrev_list(names,18,s.showHemisphere),'Value',dispIdx); catch, end
        guidata(fig,s);
        setStatus(['Benchmark ROI changed to: ' fc_roi_abbrev(names{dispIdx},20,s.showHemisphere)],C.good);
        refreshCompareView();
    end

    function onLoadData(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = fc_uigetfile_start({'*.mat','MAT files (*.mat)'},'Load functional MAT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        S = load(fullfile(p,f));
        [I,varName] = fc_pick_data_from_mat(S);
        if isempty(I)
            errordlg('No compatible 3D/4D numeric variable found.');
            return;
        end
        I4 = fc_force4d(I);
        [Yi,Xi,Zi] = fc_size3(I4);
        if Yi ~= s.Y || Xi ~= s.X || Zi ~= s.Z
            errordlg('Loaded data spatial size does not match current GUI.');
            return;
        end
        s.subjects(s.currentSubject).I4 = I4;
        s.seedResults(s.currentSubject,:) = {[]};
        s.roiResults(s.currentSubject,:) = {[]};
        guidata(fig,s);
        setStatus(['Loaded data variable: ' varName],C.good);
        refreshAll();
    end

    function onLoadMask(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = fc_uigetfile_start({'*.mat','MAT files (*.mat)'},'Load mask MAT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        S = load(fullfile(p,f));
        m = fc_pick_volume(S,s.Y,s.X,s.Z);
        if isempty(m)
            errordlg('No compatible mask volume found.');
            return;
        end
        s.subjects(s.currentSubject).mask = logical(m);
        s.seedResults(s.currentSubject,:) = {[]};
        s.roiResults(s.currentSubject,:) = {[]};
        guidata(fig,s);
        setStatus(['Loaded mask: ' f],C.good);
        refreshAll();
    end

    function onLoadAtlas(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        choiceAtlas = questdlg('Load ROI labels from file or recursively from step-motor folder?','Load ROI labels','Label/TXT file','Step-motor folder','Cancel','Step-motor folder');
        if isempty(choiceAtlas) || strcmpi(choiceAtlas,'Cancel'), return; end

        if strcmpi(choiceAtlas,'Step-motor folder')
            startDir = fc_start_dir(subj,s.opts);
            try
                if isfield(s.opts,'stepMotorFolder') && ~isempty(s.opts.stepMotorFolder) && exist(s.opts.stepMotorFolder,'dir') == 7
                    startDir = s.opts.stepMotorFolder;
                end
            catch
            end
            folder = uigetdir(startDir,'Select step-motor analysed/session folder');
            if isequal(folder,0), return; end
            P = HUMOR_FC_stepmotor_read_folder(folder,s.Y,s.X,s.Z);
            did = false;
            if ~isempty(P.atlas)
                s.subjects(s.currentSubject).roiAtlas = round(double(P.atlas));
                s.roiResults(s.currentSubject,:) = {[]};
                did = true;
            end
            if ~isempty(P.names.labels)
                s.opts.roiNameTable = P.names;
                s.loadedRegionNameFile = folder;
                s.subjects(s.currentSubject).roiNameTable = P.names;
                did = true;
            end
            if ~did
                errordlg({'No usable step-motor label/name files were found recursively.','','Folder:',folder,'','Summary:',P.summary},'Step-motor ROI labels');
                return;
            end
            s.opts.stepMotorFolder = folder;
            guidata(fig,s);
            setStatus(['Loaded step-motor ROI labels/names: ' P.summary],C.good);
            refreshAll();
            return;
        end

        [f,p] = fc_uigetfile_start({'*.mat;*.nii;*.nii.gz;*.tif;*.tiff;*.txt;*.csv;*.tsv','ROI labels or step-motor TXT/MAT names'},'Load ROI labels or step-motor TXT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        fullFile = fullfile(p,f);
        [~,~,extNow] = fileparts(fullFile); extNow = lower(extNow);
        if any(strcmp(extNow,{'.txt','.csv','.tsv'}))
            P = HUMOR_FC_stepmotor_read_folder(p,s.Y,s.X,s.Z,fullFile);
            if ~isempty(P.names.labels)
                s.opts.roiNameTable = P.names;
                s.loadedRegionNameFile = fullFile;
                s.subjects(s.currentSubject).roiNameTable = P.names;
            end
            if ~isempty(P.atlas)
                s.subjects(s.currentSubject).roiAtlas = round(double(P.atlas));
                s.roiResults(s.currentSubject,:) = {[]};
            end
            if isempty(P.names.labels) && isempty(P.atlas)
                errordlg('Selected TXT/CSV could not be parsed, and no matching atlas was found in the same folder tree.','Step-motor TXT labels');
                return;
            end
            guidata(fig,s);
            setStatus(['Loaded TXT names and matching step-motor atlas: ' P.summary],C.good);
            refreshAll();
            return;
        end
        a = fc_read_atlas_any(fullFile,s.Y,s.X,s.Z);
        if isempty(a)
            errordlg('No compatible ROI label map found.','ROI labels');
            return;
        end
        choice = questdlg('Apply ROI label map to current subject or all subjects?','ROI labels','Current','All','Current');
        if strcmpi(choice,'All')
            for i = 1:s.nSub
                s.subjects(i).roiAtlas = round(double(a));
                s.roiResults(i,:) = {[]};
            end
        else
            s.subjects(s.currentSubject).roiAtlas = round(double(a));
            s.roiResults(s.currentSubject,:) = {[]};
        end
        guidata(fig,s);
        setStatus(['Loaded ROI labels: ' f],C.good);
        refreshAll();
    end

    function onLoadNames(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);

        choiceNames = questdlg('Load region names from file or recursively from step-motor folder?', ...
            'Load region names', ...
            'Name/TXT file', 'Step-motor folder', 'Cancel', 'Step-motor folder');

        if isempty(choiceNames) || strcmpi(choiceNames,'Cancel')
            return;
        end

        if strcmpi(choiceNames,'Step-motor folder')
            startDir = fc_start_dir(subj,s.opts);
            try
                if isfield(s.opts,'stepMotorFolder') && ~isempty(s.opts.stepMotorFolder) && exist(s.opts.stepMotorFolder,'dir') == 7
                    startDir = s.opts.stepMotorFolder;
                end
            catch
            end

            folder = uigetdir(startDir,'Select Registration2D or step-motor analysed/session folder');
            if isequal(folder,0), return; end

            R = HUMOR_FC_find_stepmotor_txt_names(folder);
            if isempty(R.names.labels)
                errordlg({'No readable region-name TXT/CSV/MAT files were found recursively.','','Selected folder:',folder,'','Expected example:','Registration2D\SourceSlice001_AtlasSlice111\AtlasRegions_slice111.txt','',R.summary},'Step-motor names');
                return;
            end

            s.opts.roiNameTable = R.names;
            s.loadedRegionNameFile = R.bestFile;
            s.opts.stepMotorFolder = folder;

            for i = 1:s.nSub
                s.subjects(i).roiNameTable = R.names;
            end

            for i = 1:s.nSub
                for e = 1:numel(s.epochs)
                    if ~isempty(s.roiResults{i,e})
                        labs = s.roiResults{i,e}.labels;
                        nm = cell(numel(labs),1);
                        for k = 1:numel(labs)
                            nm{k} = fc_roi_name(labs(k),s.opts);
                        end
                        s.roiResults{i,e}.names = nm;
                    end
                end
            end

            guidata(fig,s);
            setStatus(['Loaded recursive step-motor region names: ' R.summary],C.good);
            refreshAll();
            return;
        end

        [f,p] = fc_uigetfile_start( ...
            {'*.txt;*.csv;*.tsv;*.mat','Region names (*.txt,*.csv,*.tsv,*.mat)'}, ...
            'Load region names / AtlasRegions_slice TXT', ...
            fc_start_dir(subj,s.opts));

        if isequal(f,0), return; end

        try
            fullFile = fullfile(p,f);
            T = HUMOR_FC_read_region_names_file(fullFile);
            if isempty(T.labels)
                errordlg('Could not parse labels/names from selected file.','Region names');
                return;
            end

            s.opts.roiNameTable = T;
            s.loadedRegionNameFile = fullFile;

            for i = 1:s.nSub
                s.subjects(i).roiNameTable = T;
            end

            for i = 1:s.nSub
                for e = 1:numel(s.epochs)
                    if ~isempty(s.roiResults{i,e})
                        labs = s.roiResults{i,e}.labels;
                        nm = cell(numel(labs),1);
                        for k = 1:numel(labs)
                            nm{k} = fc_roi_name(labs(k),s.opts);
                        end
                        s.roiResults{i,e}.names = nm;
                    end
                end
            end

            guidata(fig,s);
            setStatus(sprintf('Loaded %d region names from %s',numel(T.labels),f),C.good);
            refreshAll();

        catch ME
            setStatus(['Region-name error: ' ME.message],C.warn);
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onLoadSegmentation(~,~)




        s = guidata(fig);
        subj = s.subjects(s.currentSubject);

        startDir = fc_segmentation_start_dir(subj, s.opts);

        [f,p] = fc_uigetfile_start({'Segmentation*.mat;*.mat','Segmentation MAT (*.mat)'}, ...
            'Load Segmentation.mat / region-time output', startDir);

        if isequal(f,0)
            return;
        end

        fullFile = fullfile(p,f);

        try
            [res, segInfo, roiAtlasFromSeg] = fc_read_segmentation_result(fullFile, subj.TR, s.opts);

            if isempty(res) || ~isfield(res,'M') || isempty(res.M)
                error('Selected MAT does not contain a usable Segmentation result.');
            end

            res = fc_apply_epoch_to_roi_result(res,s);
            s.roiResults{s.currentSubject,s.currentEpoch} = res;
            s.loadedSegmentationFile = fullFile;

            % If Segmentation.m saved a label map, use it for ROI overlay / compare map.
            if ~isempty(roiAtlasFromSeg)
                try
                    A = fc_fit_volume(fc_repair_signed_label_map(roiAtlasFromSeg), s.Y, s.X, s.Z, false);
                    if ~isempty(A) && fc_looks_like_roi_label_map(A)
                        s.subjects(s.currentSubject).roiAtlas = round(double(A));
                    end
                catch
                    % Region FC still works even if the spatial label map cannot be fitted.
                end
            end

            % Prefer TR from Segmentation if available.
            if isfield(segInfo,'TR') && isfinite(segInfo.TR) && segInfo.TR > 0
                s.subjects(s.currentSubject).TR = segInfo.TR;
            end

            guidata(fig,s);

            updateROIDropdowns(res.names);
            try
                s.compareTopN = 15;
                s.comparePage = 1;
                set(edTopN,'String','15');
                guidata(fig,s);
            catch
            end
            setStatus(sprintf('Loaded segmentation: %d regions, %d time points. ROI FC matrix computed from region time courses.', ...
                numel(res.labels), size(res.meanTS,1)), C.good);

            refreshAll();
            switchTab('heatmap');

        catch ME
            setStatus(['Segmentation load error: ' ME.message], C.warn);
            errordlg(ME.message,'Load Segmentation');
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onLoadUnderlay(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = fc_uigetfile_start( ...
            {'*.mat;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Underlay / histology files'}, ...
            'Load display underlay / histology', ...
            fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        try
            [U,isRGB,isDisplayReady] = fc_read_underlay(fullfile(p,f),s.Y,s.X,s.Z);
            s.loadedUnderlay = U;
            s.loadedUnderlayIsRGB = isRGB;
            s.loadedUnderlayDisplayReady = isDisplayReady;
            s.loadedUnderlayName = f;
            s.underlayMode = 'loaded';
            guidata(fig,s);
            setStatus(['Loaded underlay/histology: ' f],C.good);
            refreshAll();
        catch ME
            setStatus(['Underlay error: ' ME.message],C.warn);
            errordlg(ME.message,'Underlay error');
        end
    end

    function onLoadScmROI(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = fc_uigetfile_start({'*.txt','SCM ROI TXT (*.txt)'},'Load SCM ROI TXT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        try
            info = fc_read_scm_roi(fullfile(p,f));
            s.seedX = round((info.x1 + info.x2)/2);
            s.seedY = round((info.y1 + info.y2)/2);
            s.seedBoxSize = max(info.x2-info.x1+1, info.y2-info.y1+1);
            if isfinite(info.slice), s.slice = fc_clip(round(info.slice),1,s.Z); end
            guidata(fig,s);
            setStatus(['Loaded SCM ROI: ' f],C.good);
            refreshAll();
        catch ME
            setStatus(['SCM ROI error: ' ME.message],C.warn);
        end
    end

    function onComputeSeedCurrent(~,~)
        s = guidata(fig);
        try
            setStatus('Computing seed FC for current subject...',C.dim);
            s = computeSeed(s,s.currentSubject,s.currentEpoch);
            guidata(fig,s);
            setStatus('Seed FC done.',C.good);
            refreshSeedView();
            switchTab('seed');
        catch ME
            setStatus(['Seed FC error: ' ME.message],C.warn);
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeSeedAll(~,~)
        s = guidata(fig);
        try
            for i = 1:s.nSub
                setStatus(sprintf('Computing seed FC %d/%d...',i,s.nSub),C.dim);
                s = computeSeed(s,i,s.currentEpoch);
            end
            guidata(fig,s);
            setStatus('Seed FC done for all subjects.',C.good);
            refreshSeedView();
            switchTab('seed');
        catch ME
            setStatus(['Seed all error: ' ME.message],C.warn);
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function s = computeSeed(s,subIdx,epIdx)
        subj = s.subjects(subIdx);
        [t0,t1,epName] = fc_epoch_window_sec(s,subj.TR,size(subj.I4,4));
        idxT = fc_time_idx(subj.TR,size(subj.I4,4),t0,t1);
        res = fc_seed_fc(subj.I4(:,:,:,idxT),subj.TR,subj.mask, ...
            s.seedX,s.seedY,s.slice,s.seedBoxSize,s.useSliceOnly,s.opts.chunkVox);
        res.timeIdx = idxT;
        res.epochName = epName;
        res.epochWindowSec = [t0 t1];
        s.seedResults{subIdx,epIdx} = res;
    end

    function onComputeROICurrent(~,~)
        s = guidata(fig);
        try
            setStatus('Computing ROI FC for current subject...',C.dim);
            s = computeROI(s,s.currentSubject,s.currentEpoch);
            guidata(fig,s);
            setStatus('ROI FC done.',C.good);
            refreshAll();
            switchTab('heatmap');
        catch ME
            setStatus(['ROI FC error: ' ME.message],C.warn);
            errordlg(ME.message,'ROI FC error');
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeROIAll(~,~)
        s = guidata(fig);
        try
            for i = 1:s.nSub
                setStatus(sprintf('Computing ROI FC %d/%d...',i,s.nSub),C.dim);
                s = computeROI(s,i,s.currentEpoch);
            end
            guidata(fig,s);
            setStatus('ROI FC done for all subjects.',C.good);
            refreshAll();
            switchTab('heatmap');
        catch ME
            setStatus(['ROI all error: ' ME.message],C.warn);
            errordlg(ME.message,'ROI FC error');
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function s = computeROI(s,subIdx,epIdx)
        subj = s.subjects(subIdx);
        if isempty(subj.roiAtlas)
            error('No ROI atlas/label map loaded for subject %s.',subj.name);
        end
        [t0,t1,epName] = fc_epoch_window_sec(s,subj.TR,size(subj.I4,4));
        idxT = fc_time_idx(subj.TR,size(subj.I4,4),t0,t1);
        res = fc_roi_fc(subj.I4(:,:,:,idxT),subj.TR,subj.mask,subj.roiAtlas,s.opts);
        res.timeIdx = idxT;
        res.epochName = epName;
        res.epochWindowSec = [t0 t1];
        s.roiResults{subIdx,epIdx} = res;
    end

    function onExportCSV(~,~)
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        if isempty(res)
            setStatus('No ROI result to export.',C.warn);
            return;
        end
        try
            [M,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
            outFile = fullfile(s.qcDir,['ROI_heatmap_' s.tag '.csv']);
            fc_write_matrix_csv(outFile,M,names);
            setStatus(['Saved heatmap CSV: ' outFile],C.good);
        catch ME
            setStatus(['CSV export error: ' ME.message],C.warn);
        end
    end

    function onSaveAll(~,~)
        s = guidata(fig);
        try
            out = struct();
            out.subjects = s.subjects;
            out.epochs = s.epochs;
            out.seedResults = s.seedResults;
            out.roiResults = s.roiResults;
            out.guiState = s;
            matFile = fullfile(s.qcDir,['FunctionalConnectivity_' s.tag '.mat']);
            save(matFile,'out','-v7.3');
            % -------------------------------------------------------------
% Save standardized Functional Connectivity group bundle
% This file is what GroupAnalysis will load later.
% -------------------------------------------------------------
try
    fcBundle = fc_make_group_bundle(s);

    bundleFile1 = fullfile(s.qcDir, ['FC_GroupBundle_' s.tag '.mat']);
    save(bundleFile1, 'fcBundle', '-v7.3');

    bundleDir = fullfile(s.saveRoot, 'Connectivity', 'GroupBundles');
    if ~exist(bundleDir, 'dir')
        mkdir(bundleDir);
    end

    bundleFile2 = fullfile(bundleDir, ['FC_GroupBundle_' s.tag '.mat']);
    save(bundleFile2, 'fcBundle', '-v7.3');

    setStatus(['Saved FC group bundle: ' bundleFile2], C.good);
catch MEbundle
    setStatus(['Could not save FC group bundle: ' MEbundle.message], C.warn);
end
            fc_save_axis(axMap,fig,fullfile(s.qcDir,['FC_seed_map_' s.tag '.png']));
            fc_save_axis(axHeat,fig,fullfile(s.qcDir,['FC_heatmap_' s.tag '.png']));
            fc_save_axis(axCompareBar,fig,fullfile(s.qcDir,['FC_compare_bar_' s.tag '.png']));
            fc_save_axis(axCompareMap,fig,fullfile(s.qcDir,['FC_compare_map_' s.tag '.png']));
            fc_save_axis(axAdj,fig,fullfile(s.qcDir,['FC_graph_' s.tag '.png']));
            res = s.roiResults{s.currentSubject,s.currentEpoch};
            if ~isempty(res)
                [M,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
                fc_write_matrix_csv(fullfile(s.qcDir,['ROI_heatmap_' s.tag '.csv']),M,names);
                T = fc_compare_export_table(s,res);
                if ~isempty(T)
                    fc_write_compare_csv(fullfile(s.qcDir,['ROI_compare_' s.tag '.csv']),T);
                end
            end
            setStatus(['Saved all outputs to ' s.qcDir],C.good);
        catch ME
            setStatus(['Save error: ' ME.message],C.warn);
            errordlg(ME.message,'Save error');
        end
    end

    function onExportGroupAnalysis(~,~)
        s = guidata(fig);
        try
            outFile = fc_export_group_analysis_bundle_interactive(s);
            if ~isempty(outFile)
                setStatus(['Saved GroupAnalysis FC bundle: ' outFile],C.good);
            end
        catch ME
            setStatus(['GroupAnalysis FC export failed: ' ME.message],C.warn);
            errordlg(ME.message,'Export FC bundle for GroupAnalysis');
        end
    end

% =========================================================================
% REFRESH FUNCTIONS
% =========================================================================
    function refreshAll()
        s = guidata(fig);
        if ~isfield(s,'showHemisphere') || isempty(s.showHemisphere)
            s.showHemisphere = true;
        end % FC_LR_LABEL_DISPLAY_PATCH_V2_REFRESH_DEFAULT
                if ~isfield(s,'fcUseEpochWin') || isempty(s.fcUseEpochWin)
            s.fcUseEpochWin = false;
        end % FC_USE_WINDOW_REFRESH_DEFAULT
if ~isfield(s,'roiHemiMode') || isempty(s.roiHemiMode)
            s.roiHemiMode = 'both';
        end % FC_REGION_MODE_PATCH_REFRESH_DEFAULT
        s.slice = fc_clip(s.slice,1,s.Z);
        s.seedX = fc_clip(s.seedX,1,s.X);
        s.seedY = fc_clip(s.seedY,1,s.Y);
        set(ddSubject,'Value',s.currentSubject);
        set(slSlice,'Value',s.slice);
        set(edSlice,'String',num2str(s.slice));
        try, set(edSliceBox,'String',num2str(s.slice)); catch, end
        if ~isfield(s,'sliceRegionOnly') || isempty(s.sliceRegionOnly), s.sliceRegionOnly = false; end
        try, set(cbSliceRegionOnly,'Value',double(s.sliceRegionOnly)); catch, end
        try, set(txtSeedSlice,'String',sprintf('Seed map | slice Z %d / %d   mouse-wheel = change slice',s.slice,s.Z)); catch, end
        try, set(txtCompareSlice,'String',sprintf('Compare map slice Z %d / %d   scroll = change slice',s.slice,s.Z)); catch, end
        set(edSeedX,'String',num2str(s.seedX));
        set(edSeedY,'String',num2str(s.seedY));
        set(edSeedSize,'String',num2str(s.seedBoxSize));
        set(cbSliceOnly,'Value',double(s.useSliceOnly));
        set(cbAtlasLine,'Value',double(s.showAtlasLines));
        set(cbMaskLine,'Value',double(s.showMaskLine));
        try, set(cbShowLR,'Value',double(s.showHemisphere)); catch, end % FC_LR_LABEL_DISPLAY_PATCH_V2_REFRESH_CHECKBOX
        try, set(ddRegionMode,'Value',fc_region_mode_to_popup_value(s.roiHemiMode)); catch, end % FC_REGION_MODE_PATCH_REFRESH_POPUP
        try, set(ddEpochMode,'Value',fc_epoch_mode_to_popup_value(s.fcEpochMode)); catch, end % FC_LR_EPOCH_PATCH_REFRESH_EPOCH_POPUP

        try, set(cbEpochUseWin,'Value',double(s.fcUseEpochWin)); catch, end % FC_USE_WINDOW_REFRESH_CHECKBOX        try, set(edInjStart,'String',sprintf('%.2f',s.fcInjStartMin)); catch, end % FC_LR_EPOCH_PATCH_REFRESH_INJ_START
        try, set(edInjEnd,'String',sprintf('%.2f',s.fcInjEndMin)); catch, end % FC_LR_EPOCH_PATCH_REFRESH_INJ_END
        try, set(edEpochWin,'String',sprintf('%.2f',s.fcEpochWinMin)); catch, end % FC_LR_EPOCH_PATCH_REFRESH_WIN
        set(edSeedThr,'String',sprintf('%.2f',s.seedAbsThr));
        set(edROIThr,'String',sprintf('%.2f',s.roiAbsThr));
        set(edTopN,'String',num2str(s.compareTopN));
        set(ddUnderlayStyle,'Value',fc_view_mode_to_value(s.underlayViewMode));
        set(edUGamma,'String',sprintf('%.2f',s.underlayGamma));
        set(edUSharp,'String',sprintf('%.2f',s.underlaySharpness));
        underlayListNow = fc_underlay_list(s);
        set(ddUnderlay,'String',underlayListNow,'Value',fc_underlay_value(s,underlayListNow));
        set(txtSummary,'String','');
        set(txtStatus,'String','');
        set(txtSeed,'String','');
        guidata(fig,s);
        refreshSeedView();
        refreshHeatmapView();
        refreshCompareView();
        refreshPairView();
        refreshGraphView();
    end

    function refreshSeedView()
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        set(hUnder,'CData',fc_get_underlay(s));
        set(hCrossH,'YData',[s.seedY s.seedY]);
        set(hCrossV,'XData',[s.seedX s.seedX]);

        if exist('hSeedBox','var') && ishghandle(hSeedBox)
            set(hSeedBox,'Position',fc_seed_box_position(s.seedX,s.seedY,s.seedBoxSize,s.X,s.Y), ...
                'Visible','on','EdgeColor',C.seedBox,'LineWidth',2.5);
        end

        ovRGB = nan(s.Y,s.X,3);
        ovA = zeros(s.Y,s.X);
        cmap = fc_get_cmap(s.cmapName,256);
        cbLabel = 'No FC';
        cbClim = [-1 1];

        switch lower(s.overlayMode)
            case 'seed_fc'
                res = s.seedResults{s.currentSubject,s.currentEpoch};
                if ~isempty(res)
                    rS = res.rMap(:,:,s.slice);
                    zS = res.zMap(:,:,s.slice);
                    vis = abs(rS) >= s.seedAbsThr;
                    if ~isempty(subj.mask), vis = vis & subj.mask(:,:,s.slice); end
                    if strcmpi(s.seedDisplay,'z')
                        M = zS;
                        cbClim = [-s.seedCLim s.seedCLim];
                        cbLabel = 'Fisher z';
                    else
                        M = rS;
                        cbClim = [-1 1];
                        cbLabel = 'Pearson r';
                    end
                    ovRGB = fc_map_rgb(M,cmap,cbClim);
                    ovA = s.seedAlpha * double(vis);
                end
            case 'atlas'
                atlasS = fc_atlas_slice(s);
                if ~isempty(atlasS)
                    [ovRGB,ovA] = fc_line_overlay(atlasS ~= 0,atlasS,C.line);
                end
            case 'mask'
                if ~isempty(subj.mask)
                    [ovRGB,ovA] = fc_line_overlay(subj.mask(:,:,s.slice),double(subj.mask(:,:,s.slice)),C.mask);
                end
            case 'roi_compare'
                [mapS,ok] = fc_compare_slice(s);
                if ok
                    cbClim = [-1 1];
                    cbLabel = 'ROI Pearson r';
                    ovRGB = fc_map_rgb(mapS,cmap,cbClim);
                    ovA = 0.65 * double(isfinite(mapS) & abs(mapS) >= max(0,s.roiAbsThr));
                end
            case 'roi_pick'
                atlasS = fc_atlas_slice(s);
                if ~isempty(atlasS)
                    [ovRGB,ovA] = fc_line_overlay(atlasS ~= 0,atlasS,C.line);
                    cbLabel = 'Click ROI';
                    cbClim = [0 1];
                end
        end
        set(hOver,'CData',ovRGB,'AlphaData',ovA);

        atlasRGB = nan(s.Y,s.X,3); atlasA = zeros(s.Y,s.X);
        if s.showAtlasLines
            atlasS = fc_atlas_slice(s);
            if ~isempty(atlasS), [atlasRGB,atlasA] = fc_line_overlay(atlasS ~= 0,atlasS,C.line); end
        end
        set(hAtlas,'CData',atlasRGB,'AlphaData',atlasA);

        maskRGB = nan(s.Y,s.X,3); maskA = zeros(s.Y,s.X);
        if s.showMaskLine && ~isempty(subj.mask)
            [maskRGB,maskA] = fc_line_overlay(subj.mask(:,:,s.slice),double(subj.mask(:,:,s.slice)),C.mask);
        end
        set(hMask,'CData',maskRGB,'AlphaData',maskA);

        axis(axMap,'image'); axis(axMap,'ij'); axis(axMap,'off');
        fc_colorbar_legend(axSeedCB,cmap,cbClim,cbLabel,C);

        res = s.seedResults{s.currentSubject,s.currentEpoch};
        if isempty(res)
            fc_nodata(axSeedTS,'Seed ROI mean timecourse',C);
            fc_nodata(axSeedHist,'Voxelwise seed-FC distribution',C);
            return;
        end

        ts = double(res.seedTS(:));
        t = ((0:numel(ts)-1) * subj.TR) / 60;
        cla(axSeedTS);
        plot(axSeedTS,t,ts,'LineWidth',1.5,'Color',[0.2 0.75 1.0]);
        fc_ax(axSeedTS,C); grid(axSeedTS,'on');
        xlabel(axSeedTS,'Time (min)','Color',C.dim);
        ylabel(axSeedTS,'Mean signal (a.u.)','Color',C.dim);
        title(axSeedTS,'Seed ROI mean timecourse','Color',C.fg,'Interpreter','none');

        rr = double(res.rMap(:));
        if ~isempty(subj.mask), rr = rr(subj.mask(:)); end
        rr = rr(isfinite(rr));
        cla(axSeedHist);
        if isempty(rr)
            fc_nodata(axSeedHist,'Voxelwise seed-FC distribution',C);
        else
            histogram(axSeedHist,rr,60,'FaceColor',[0.2 0.65 1.0],'EdgeColor',[0.1 0.35 0.8]);
            fc_ax(axSeedHist,C); grid(axSeedHist,'on');
            xlabel(axSeedHist,'Pearson r to seed','Color',C.dim);
            ylabel(axSeedHist,'Voxel count','Color',C.dim);
            title(axSeedHist,'Voxelwise seed-FC distribution','Color',C.fg,'Interpreter','none');
        end
    end

    function refreshHeatmapView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        try
            set(axHeat,'Position',[0.070 0.115 0.845 0.845]);
            set(axHeatCB,'Position',[0.955 0.215 0.022 0.600]);
            set(txtHeat,'Position',[0.945 0.865 0.055 0.115]);
        catch
        end

        cla(axHeat);
        cla(axHeatTS);
        try, set(axHeatTS,'Visible','off'); catch, end

        cmap = fc_get_cmap(s.cmapName,256);

        if isempty(res)
            fc_nodata(axHeat,'Region-by-region FC heatmap',C);
            fc_colorbar_legend(axHeatCB,cmap,[-1 1],'Pearson r',C);
            set(txtHeat,'String','No ROI FC yet. Load ROI labels + names, then click ROI current.');
            updateROIDropdowns({'n/a'});
            return;
        end

        [M,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
        [M,names,order,meta] = fc_apply_region_visibility(s,M,names,order,meta);

        Mshow = M;
        if strcmpi(s.roiDisplaySpace,'z')
            Mshow = fc_atanh_safe(Mshow);
            Mshow(1:size(Mshow,1)+1:end) = 0;
            clim = [-s.roiZCLim s.roiZCLim];
            cbLabel = 'Fisher z';
            thrForM = s.roiAbsThr;
        else
            clim = [-s.roiCLim s.roiCLim];
            cbLabel = 'Pearson r';
            thrForM = s.roiAbsThr;
        end

        Mdisp = Mshow;
        if thrForM > 0
            Mdisp(abs(Mdisp) < thrForM) = 0;
        end

        imagesc(axHeat,Mdisp,clim);
        if exist('meta','var') && isfield(meta,'isRectangular') && meta.isRectangular
            axis(axHeat,'tight');
        else
            axis(axHeat,'tight'); axis(axHeat,'normal');
        end
        fc_ax(axHeat,C);
        colormap(axHeat,cmap);

        title(axHeat,sprintf('Region-by-region FC heatmap | Z %d/%d',s.slice,s.Z), ...
            'Color',C.fg, ...
            'Interpreter','none', ...
            'FontWeight','bold','FontSize',14);
        xlabel(axHeat,'Atlas region','Color',C.dim,'FontWeight','bold','FontSize',11);
        ylabel(axHeat,'Atlas region','Color',C.dim,'FontWeight','bold','FontSize',11);

        fc_set_matrix_ticks(axHeat,Mdisp,names,meta,s.showHemisphere,C);
        if isfield(meta,'isRectangular') && meta.isRectangular
            xlabel(axHeat,'Right atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            ylabel(axHeat,'Left atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            title(axHeat,'Left regions vs Right regions FC heatmap', ...
                'Color',C.fg,'Interpreter','none','FontWeight','bold','FontSize',11);
        else
            xlabel(axHeat,'Atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            ylabel(axHeat,'Atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            title(axHeat,sprintf('Region-by-region FC heatmap | Z %d/%d',s.slice,s.Z), ...
                'Color',C.fg,'Interpreter','none','FontWeight','bold','FontSize',11);
        end
        fc_colorbar_legend(axHeatCB,cmap,clim,cbLabel,C);
        updateROIDropdowns(names);

        if isfield(meta,'isRectangular') && meta.isRectangular
            regionTxt = sprintf('%d L x %d R',size(Mdisp,1),size(Mdisp,2));
        else
            regionTxt = sprintf('%d',numel(names));
        end
        set(txtHeat,'String',sprintf('Regions: %s\nSlice: %s\nValue: %s\n|r| thr: %.2f', regionTxt, fc_slice_filter_text(s), cbLabel, s.roiAbsThr));
    end

    function refreshCompareView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        cla(axCompareBar); cla(axCompareMap); cla(axCompareTS);
        cmap = fc_get_cmap(s.cmapName,256);
        fc_colorbar_legend(axCompareCB,cmap,[-1 1],'Pearson r',C);
        if isempty(res)
            fc_nodata(axCompareBar,'Selected ROI vs all regions',C);
            fc_nodata(axCompareMap,'Atlas correlation map',C);
            fc_nodata(axCompareTS,'Selected and partner traces',C);
            set(txtCompare,'String','Compute ROI FC first, then select CPu/CPU or any region.');
            return;
        end

        [M,names,order,meta] = fc_current_matrix(s,res);
        if isfield(meta,'isRectangular') && meta.isRectangular
            fc_nodata(axCompareBar,'Compare ROI is disabled in Left-vs-Right mode',C);
            fc_nodata(axCompareMap,'Switch to Left only / Right only / Both / Merged',C);
            fc_nodata(axCompareTS,'Selected and partner traces',C);
            set(txtCompare,'String','Left-vs-Right mode is a rectangular matrix for Heatmap/Graph. Use Left only, Right only, Both, or Merged for Compare ROI.');
            return;
        end
        updateROIDropdowns(names);
        sel = fc_clip(get(ddCompareROI,'Value'),1,numel(names));
        rawSel = order(sel); tsSel = fc_display_ts_for_index(res,meta,sel);
        r = M(sel,:);
        r(sel) = NaN;
        [idxAll,valAll] = fc_rank_vector(r,max(2,numel(names)-1),s.compareSort,names);
        pageSize = max(1,min(50,round(s.compareTopN)));
        nAll = numel(idxAll);
        maxPage = max(1,ceil(max(1,nAll) ./ pageSize));
        if ~isfield(s,'comparePage') || isempty(s.comparePage), s.comparePage = 1; end
        s.comparePage = fc_clip(round(s.comparePage),1,maxPage);
        i0 = (s.comparePage - 1) * pageSize + 1;
        i1 = min(nAll,i0 + pageSize - 1);
        if nAll > 0
            idxShow = idxAll(i0:i1);
            valShow = valAll(i0:i1);
        else
            idxShow = [];
            valShow = [];
            i0 = 0;
            i1 = 0;
        end
        try, set(txtComparePage,'String',sprintf('%d-%d/%d',i0,i1,nAll)); catch, end
        guidata(fig,s);

        if isempty(idxShow)
            fc_nodata(axCompareBar,'Selected ROI vs all regions',C);
        else
            barh(axCompareBar,valShow,'FaceColor',[0.30 0.65 1.00],'EdgeColor',[0.15 0.35 0.80]);
            fc_ax(axCompareBar,C); grid(axCompareBar,'on');
            xlabel(axCompareBar,'Pearson r to selected region','Color',C.dim);
            ylabel(axCompareBar,'Partner region','Color',C.dim);
            title(axCompareBar,sprintf('Selected ROI vs all regions: %s | ranks %d-%d of %d', ...
                fc_roi_abbrev(names{sel},18,s.showHemisphere),i0,i1,nAll), ...
                'Color',C.fg,'Interpreter','none');
            set(axCompareBar,'YTick',1:numel(idxShow),'YTickLabel',fc_abbrev_list(names(idxShow),18,s.showHemisphere),'YDir','reverse','FontSize',10);
            xlim(axCompareBar,[-1 1]);
        end

        [mapS,ok] = fc_compare_slice(s);
        if ok
            cla(axCompareMap);
            image(axCompareMap,ones(size(mapS,1),size(mapS,2),3));
            hold(axCompareMap,'on');
            hCmpImg = imagesc(axCompareMap,mapS,[-1 1]);
            set(hCmpImg,'AlphaData',double(isfinite(mapS)));
            hold(axCompareMap,'off');
            set(hCmpImg,'ButtonDownFcn',@onCompareMapClick);
            set(axCompareMap,'ButtonDownFcn',@onCompareMapClick);
            axis(axCompareMap,'image'); axis(axCompareMap,'ij'); axis(axCompareMap,'off');
            set(axCompareMap,'XLim',[0.5 s.X+0.5],'YLim',[0.5 s.Y+0.5]);
            colormap(axCompareMap,cmap);
            title(axCompareMap,sprintf('Click region | Z %d/%d  scroll = slice',s.slice,s.Z),'Color',C.fg,'Interpreter','none');
            try
                subjNow = s.subjects(s.currentSubject);
                fc_draw_roi_abbrev_on_map(axCompareMap,double(subjNow.roiAtlas(:,:,s.slice)),res.labels,res.names,C,s.showHemisphere);
            catch
            end
        else
            fc_nodata(axCompareMap,'Atlas correlation map',C);
        end

        t = fc_result_time_min(res,s.subjects(s.currentSubject).TR);
        if numel(t) ~= size(res.meanTS,1)
            t = fc_result_time_min(res,s.subjects(s.currentSubject).TR);
        if numel(t) ~= size(res.meanTS,1)
            t = ((0:size(res.meanTS,1)-1)' .* s.subjects(s.currentSubject).TR) ./ 60;
        end
        t = t(:)';
        end
        t = t(:)';
        plot(axCompareTS,t,fc_z(tsSel),'LineWidth',1.8,'Color',[0.2 0.75 1.0]);
        hold(axCompareTS,'on');
        if ~isempty(idxShow)
            rawBest = order(idxShow(1));
            tsBest = fc_display_ts_for_index(res,meta,idxShow(1));
            plot(axCompareTS,t,fc_z(tsBest),'LineWidth',1.4,'Color',[1.0 0.55 0.2]);
            lgdC = legend(axCompareTS,{['Blue: ' fc_roi_abbrev(names{sel},18,s.showHemisphere)], ...
                ['Orange: ' fc_roi_abbrev(names{idxShow(1)},18,s.showHemisphere)]}, ...
                'Location','best','TextColor',C.fg,'Interpreter','none');
            try
                set(lgdC,'Color',C.bgPane,'EdgeColor',C.dim,'TextColor',C.fg, ...
                    'FontName',C.font,'FontSize',12,'FontWeight','bold','FontSize',14);
            catch
            end
        end
        hold(axCompareTS,'off');
        fc_ax(axCompareTS,C); grid(axCompareTS,'on');
        xlabel(axCompareTS,'Time (min)','Color',C.dim);
        ylabel(axCompareTS,'Z-scored signal','Color',C.dim);
        title(axCompareTS,'Selected ROI and strongest partner','Color',C.fg,'Interpreter','none');
        try
            if numel(t) > 1 && all(isfinite([min(t) max(t)])) && max(t) > min(t)
                xlim(axCompareTS,[min(t) max(t)]);
            end
        catch
        end

        if isempty(idxShow)
            txtTop = 'none';
        else
            nList = min(6,numel(idxShow));
            lines = cell(nList,1);
            for k = 1:nList
                lines{k} = sprintf('%s: r = %.3f',fc_roi_abbrev(names{idxShow(k)},16,s.showHemisphere),valShow(k));
            end
            txtTop = fc_join(lines);
        end
        set(txtCompare,'String',sprintf('Selected: %s\nAtlas label: %g\n%s\nTop partners:\n%s', ...
            fc_roi_abbrev(names{sel},20,s.showHemisphere),res.labels(rawSel),fc_compare_slice_note(s,res.labels(rawSel)),txtTop));
    end

    function refreshPairView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        cla(axPairTS); cla(axPairScat); cla(axPairLag);
        if isempty(res)
            fc_nodata(axPairTS,'Pair ROI traces',C);
            fc_nodata(axPairScat,'ROI A vs ROI B scatter',C);
            fc_nodata(axPairLag,'Lag correlation',C);
            set(txtPair,'String','No ROI result yet. Compute ROI current first.');
            return;
        end
        [~,names,order,meta] = fc_current_matrix(s,res);
        if isfield(meta,'isRectangular') && meta.isRectangular
            fc_nodata(axPairTS,'Pair ROI is disabled in Left-vs-Right mode',C);
            fc_nodata(axPairScat,'Switch to Left only / Right only / Both / Merged',C);
            fc_nodata(axPairLag,'Lag correlation',C);
            set(txtPair,'String','Left-vs-Right mode is a rectangular matrix for Heatmap/Graph. Use Left only, Right only, Both, or Merged for Pair ROI.');
            return;
        end
        updateROIDropdowns(names);
        aSel = fc_clip(get(ddPairA,'Value'),1,numel(names));
        bSel = fc_clip(get(ddPairB,'Value'),1,numel(names));
        a = order(aSel); b = order(bSel); %#ok<NASGU>
        ta = fc_display_ts_for_index(res,meta,aSel);
        tb = fc_display_ts_for_index(res,meta,bSel);
        t = fc_result_time_min(res,s.subjects(s.currentSubject).TR);
        if numel(t) ~= numel(ta)
            t = fc_result_time_min(res,s.subjects(s.currentSubject).TR);
        if numel(t) ~= numel(ta)
            t = ((0:numel(ta)-1)' .* s.subjects(s.currentSubject).TR) ./ 60;
        end
        t = t(:)';
        end
        t = t(:)';
        colA = fc_pair_color(get(ddPairColorA,'String'),get(ddPairColorA,'Value'));
        colB = fc_pair_color(get(ddPairColorB,'String'),get(ddPairColorB,'Value'));
        plot(axPairTS,t,fc_z(ta),'LineWidth',1.6,'Color',colA);
        hold(axPairTS,'on');
        plot(axPairTS,t,fc_z(tb),'LineWidth',1.6,'Color',colB);
        hold(axPairTS,'off');
        fc_ax(axPairTS,C); grid(axPairTS,'on');
        xlabel(axPairTS,'Time (min)','Color',C.dim);
        ylabel(axPairTS,'Z-scored signal','Color',C.dim);
        title(axPairTS,'Pair ROI timecourses','Color',C.fg,'Interpreter','none');
        try
            if numel(t) > 1 && all(isfinite([min(t) max(t)])) && max(t) > min(t)
                xlim(axPairTS,[min(t) max(t)]);
            end
        catch
        end
        lgdP = legend(axPairTS,{['ROI A: ' fc_roi_abbrev(names{aSel},16,s.showHemisphere)], ...
            ['ROI B: ' fc_roi_abbrev(names{bSel},16,s.showHemisphere)]},'Location','best','TextColor',C.fg);
        try
            set(lgdP,'Color',C.bgPane,'EdgeColor',C.dim,'TextColor',C.fg, ...
                'FontName',C.font,'FontSize',12,'FontWeight','bold','Interpreter','none');
        catch
        end

        scatter(axPairScat,fc_z(ta),fc_z(tb),24,colA,'filled');
        fc_ax(axPairScat,C); grid(axPairScat,'on');
        xlabel(axPairScat,['Z(' fc_roi_abbrev(names{aSel},16,s.showHemisphere) ')'],'Color',C.dim,'Interpreter','none');
        ylabel(axPairScat,['Z(' fc_roi_abbrev(names{bSel},16,s.showHemisphere) ')'],'Color',C.dim,'Interpreter','none');
        title(axPairScat,'Scatter: ROI A vs ROI B','Color',C.fg,'Interpreter','none');

        maxLag = min(30,numel(ta)-1);
        if maxLag >= 1 && exist('xcorr','file') == 2
            [xc,lags] = xcorr(fc_z(ta),fc_z(tb),maxLag,'coeff');
            plot(axPairLag,lags*s.subjects(s.currentSubject).TR,xc,'LineWidth',1.5,'Color',colB);
            fc_ax(axPairLag,C); grid(axPairLag,'on');
            xlabel(axPairLag,'Lag of ROI B relative to ROI A (s)','Color',C.dim);
            ylabel(axPairLag,'Correlation coefficient','Color',C.dim);
            title(axPairLag,'Lag correlation','Color',C.fg,'Interpreter','none');
        else
            fc_nodata(axPairLag,'Lag correlation',C);
        end
        r = fc_corr_scalar(ta,tb);
        set(txtPair,'String',sprintf(['Pair ROI inspection: %s  <->  %s\n' ...
            'Pearson r = %.4f. Trace plot shows z-scored mean signals; scatter shows pointwise relation.'], ...
            fc_roi_abbrev(names{aSel},20,s.showHemisphere),fc_roi_abbrev(names{bSel},20,s.showHemisphere),r));
    end

    function refreshGraphView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        try
            set(axAdj,'Position',[0.070 0.115 0.845 0.845]);
            set(axGraphCB,'Position',[0.955 0.215 0.022 0.600]);
            set(axDeg,     'Visible','off');
            set(txtGraph,'Position',[0.945 0.865 0.055 0.115]);
        catch
        end

        cla(axAdj);
        cla(axGraphCB);
        try
            cla(axDeg);
            set(axDeg,'Visible','off');
        catch
        end

        cmap = fc_get_cmap(s.graphCmapName,256);

        if isempty(res)
            fc_nodata(axAdj,'Thresholded weighted FC matrix',C);
            fc_colorbar_legend(axGraphCB,cmap,[-1 1],'Pearson r',C);
            set(txtGraph,'String','No graph yet. Compute ROI current first.');
            return;
        end

        [M,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
        [M,names,order,meta] = fc_apply_region_visibility(s,M,names,order,meta);

        A = abs(M) >= s.roiAbsThr;
        if ~(isfield(meta,'isRectangular') && meta.isRectangular)
            A(1:size(A,1)+1:end) = false;
        end

        W = M;
        W(~A) = 0;

        imagesc(axAdj,W,[-1 1]);
        if isfield(meta,'isRectangular') && meta.isRectangular
            axis(axAdj,'tight');
        else
            axis(axAdj,'tight'); axis(axAdj,'normal');
        end
        colormap(axAdj,cmap);
        fc_ax(axAdj,C);

        title(axAdj,sprintf('Thresholded weighted FC matrix | Z %d/%d',s.slice,s.Z), ...
            'Color',C.fg, ...
            'Interpreter','none', ...
            'FontWeight','bold','FontSize',14);
        xlabel(axAdj,'Atlas region','Color',C.dim,'FontWeight','bold','FontSize',11);
        ylabel(axAdj,'Atlas region','Color',C.dim,'FontWeight','bold','FontSize',11);

        fc_set_matrix_ticks(axAdj,W,names,meta,s.showHemisphere,C);
        if isfield(meta,'isRectangular') && meta.isRectangular
            xlabel(axAdj,'Right atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            ylabel(axAdj,'Left atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            title(axAdj,'Left-vs-Right thresholded weighted FC matrix', ...
                'Color',C.fg,'Interpreter','none','FontWeight','bold','FontSize',11);
        else
            xlabel(axAdj,'Atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            ylabel(axAdj,'Atlas region','Color',C.fg,'FontWeight','bold','FontSize',11);
            title(axAdj,sprintf('Thresholded weighted FC matrix | Z %d/%d',s.slice,s.Z), ...
                'Color',C.fg,'Interpreter','none','FontWeight','bold','FontSize',11);
        end
        fc_colorbar_legend(axGraphCB,cmap,[-1 1],'Pearson r',C);

        if isfield(meta,'isRectangular') && meta.isRectangular
            nEdges = nnz(A);
            possibleEdges = max(1,numel(A));
            regionTxt = sprintf('%d L x %d R',size(A,1),size(A,2));
        else
            nEdges = nnz(triu(A,1));
            possibleEdges = max(1,(size(A,1)*(size(A,1)-1)/2));
            regionTxt = sprintf('%d',size(A,1));
        end
        density = nEdges / possibleEdges;

        set(txtGraph,'String',sprintf([ ...
            'Graph matrix\n\n' ...
            'Entry = Pearson r\n' ...
            'shown only when |r| >= threshold.\n\n' ...
            '|r| threshold: %.2f\n' ...
            'Regions: %s\n' ...
            'Connections: %d\n' ...
            'Density: %.4f'], ...
            s.roiAbsThr,regionTxt,fc_slice_filter_text(s),nEdges,density));
    end
% FC_LABEL_REGION_PICK_CALLBACKS_20260512_START
    function onMatrixTickMode(~,~)
        try, refreshHeatmapView(); catch, end
        try, refreshGraphView(); catch, end
    end

    function onClearCustomRegions(~,~)
        s = guidata(fig);
        s.fcSelectedRegionIdx = [];
        s.fcSelectedRegionY = [];
        s.fcSelectedRegionX = [];
        guidata(fig,s);
        refreshHeatmapView();
        refreshGraphView();
        setStatus('Showing all regions again.',C.good);
    end

    function onCustomRegionList(~,~)
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        if isempty(res)
            setStatus('No ROI result yet. Load Seg MAT or compute ROI current first.',C.warn);
            return;
        end
        try
            [M,names,order,meta] = fc_current_matrix(s,res); %#ok<ASGLU>
            if isfield(meta,'isRectangular') && meta.isRectangular
                yNames = fc_abbrev_list(meta.namesY,42,false);
                xNames = fc_abbrev_list(meta.namesX,42,false);
                yDefault = 1:numel(yNames);
                xDefault = 1:numel(xNames);
                if isfield(s,'fcSelectedRegionY') && ~isempty(s.fcSelectedRegionY), yDefault = s.fcSelectedRegionY; end
                if isfield(s,'fcSelectedRegionX') && ~isempty(s.fcSelectedRegionX), xDefault = s.fcSelectedRegionX; end
                [selY,selX,ok] = fc_checkbox_select_two_dialog(yNames,xNames,yDefault,xDefault,'Visible FC regions: Left/Y and Right/X');
                if ~ok || isempty(selY) || isempty(selX), return; end
                s.fcSelectedRegionY = selY(:)';
                s.fcSelectedRegionX = selX(:)';
                s.fcSelectedRegionIdx = [];
                guidata(fig,s);
                refreshHeatmapView();
                refreshGraphView();
                setStatus(sprintf('Custom visible regions: %d left/Y x %d right/X.',numel(selY),numel(selX)),C.good);
            else
                listNames = fc_abbrev_list(names,46,s.showHemisphere);
                def = 1:numel(listNames);
                if isfield(s,'fcSelectedRegionIdx') && ~isempty(s.fcSelectedRegionIdx), def = s.fcSelectedRegionIdx; end
                [sel,ok] = fc_checkbox_select_dialog(listNames,def,'Visible FC regions');
                if ~ok || isempty(sel), return; end
                s.fcSelectedRegionIdx = sel(:)';
                s.fcSelectedRegionY = [];
                s.fcSelectedRegionX = [];
                guidata(fig,s);
                refreshHeatmapView();
                refreshGraphView();
                setStatus(sprintf('Custom visible regions: %d.',numel(sel)),C.good);
            end
        catch ME_custom
            setStatus(['Custom region selector error: ' ME_custom.message],C.warn);
        end
    end
% FC_LABEL_REGION_PICK_CALLBACKS_20260512_END

function updateROIDropdowns(names)
        sTmp = guidata(fig);
        if ~isfield(sTmp,'showHemisphere') || isempty(sTmp.showHemisphere)
            sTmp.showHemisphere = true;
        end % FC_LR_LABEL_DISPLAY_PATCH_V2_DROPDOWN_STATE
        if isempty(names)
            names = {'n/a'};
        end
        namesDisplay = fc_abbrev_list(names,18,sTmp.showHemisphere);
        oldC = get(ddCompareROI,'Value');
        oldA = get(ddPairA,'Value');
        oldB = get(ddPairB,'Value');
        set(ddCompareROI,'String',namesDisplay,'Value',fc_clip(oldC,1,numel(namesDisplay)));
        set(ddPairA,'String',namesDisplay,'Value',fc_clip(oldA,1,numel(namesDisplay)));
        set(ddPairB,'String',namesDisplay,'Value',fc_clip(oldB,1,numel(namesDisplay)));
    end

    function [mapS,ok] = fc_compare_slice(s)
        ok = false; mapS = [];
        res = s.roiResults{s.currentSubject,s.currentEpoch};
        subj = s.subjects(s.currentSubject);
        if isempty(res) || isempty(subj.roiAtlas), return; end

        [M,~,~,meta] = fc_current_matrix(s,res);
        sel = fc_clip(get(ddCompareROI,'Value'),1,size(M,1));
        valsDisplay = M(sel,:);
        valsRaw = fc_display_values_to_raw(res,meta,valsDisplay);

        A = subj.roiAtlas;
        if ndims(A) < 3
            atlasS = round(double(A));
        else
            zNow = fc_clip(round(s.slice),1,size(A,3));
            atlasS = round(double(A(:,:,zNow)));
        end
        mapS = nan(size(atlasS));
        for k = 1:numel(res.labels)
            labK = round(double(res.labels(k)));
            nameK = '';
            try
                if isfield(res,'names') && k <= numel(res.names), nameK = res.names{k}; end
            catch
            end
            if ~isfinite(labK) || labK == 0 || fc_is_background_region(labK,nameK)
                continue;
            end
            if k <= numel(valsRaw) && isfinite(valsRaw(k))
                m = fc_label_mask_for_slice(atlasS,labK);
                mapS(m) = valsRaw(k);
            end
        end
        ok = true;
    end
end
% =========================================================================

% HELPER FUNCTIONS
% =========================================================================
function p = fc_panel(parent,pos,titleStr,C)
p = uipanel('Parent',parent,'Units','normalized','Position',pos, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title',titleStr,'FontName',C.font,'FontWeight','bold','FontSize',10);
end

function p = fc_view(parent,C,vis)
p = uipanel('Parent',parent,'Units','normalized','Position',[0.010 0.010 0.980 0.915], ...
    'BackgroundColor',C.bgPane,'BorderType','none','Visible',vis);
end

function h = fc_label(parent,pos,str,C)
h = uicontrol('Parent',parent,'Style','text','Units','normalized','Position',pos, ...
    'String',str,'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall);
end

function out = fc_if(cond,a,b)
if cond, out = a; else, out = b; end
end

function opts = fc_defaults(opts)
if ~isfield(opts,'statusFcn'), opts.statusFcn = []; end
if ~isfield(opts,'logFcn'), opts.logFcn = []; end
if ~isfield(opts,'stepMotorFolder'), opts.stepMotorFolder = ''; end
if ~isfield(opts,'preloadSegmentationFile'), opts.preloadSegmentationFile = ''; end
if ~isfield(opts,'functionalField'), opts.functionalField = ''; end
if ~isfield(opts,'roiNames'), opts.roiNames = {}; end
if ~isfield(opts,'roiNameTable'), opts.roiNameTable = struct('labels',[],'names',{{}}); end
if ~isfield(opts,'roiMinVox') || isempty(opts.roiMinVox), opts.roiMinVox = 9; end
if ~isfield(opts,'seedBoxSize') || isempty(opts.seedBoxSize), opts.seedBoxSize = 25; end
if ~isfield(opts,'chunkVox') || isempty(opts.chunkVox), opts.chunkVox = 6000; end
if ~isfield(opts,'askMaskAtStart') || isempty(opts.askMaskAtStart), opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart), opts.askAtlasAtStart = true; end
if ~isfield(opts,'debugRethrow') || isempty(opts.debugRethrow), opts.debugRethrow = false; end
if ~isfield(opts,'defaultUnderlayMode') || isempty(opts.defaultUnderlayMode), opts.defaultUnderlayMode = 'scm'; end
if ~isfield(opts,'anatIsDisplayReady') || isempty(opts.anatIsDisplayReady), opts.anatIsDisplayReady = false; end
if ~isfield(opts,'defaultUnderlayViewMode') || isempty(opts.defaultUnderlayViewMode), opts.defaultUnderlayViewMode = 5;

% Force Functional Connectivity GUI startup seed box to 25 pixels.
% This overrides older fUSI Studio callers that still pass seedBoxSize = 3.
opts.seedBoxSize = 25; end
if ~isfield(opts,'underlayBrightness') || isempty(opts.underlayBrightness), opts.underlayBrightness = -0.04; end
if ~isfield(opts,'underlayContrast') || isempty(opts.underlayContrast), opts.underlayContrast = 1.10; end
if ~isfield(opts,'underlayGamma') || isempty(opts.underlayGamma), opts.underlayGamma = 0.95; end
if ~isfield(opts,'underlayLogGain') || isempty(opts.underlayLogGain), opts.underlayLogGain = 2.0; end
if ~isfield(opts,'underlaySharpness') || isempty(opts.underlaySharpness), opts.underlaySharpness = 0.35; end
if ~isfield(opts,'underlayVesselSize') || isempty(opts.underlayVesselSize), opts.underlayVesselSize = 18; end
if ~isfield(opts,'underlayVesselLev') || isempty(opts.underlayVesselLev), opts.underlayVesselLev = 35; end
end

function mode = fc_initial_underlay_mode(subj,opts) %#ok<INUSD>
mode = lower(strtrim(opts.defaultUnderlayMode));
if isempty(mode) || strcmpi(mode,'anat') || strcmpi(mode,'loaded')
    mode = 'scm';
end
if ~ismember(mode,{'scm','mean','median','anat','atlas'})
    mode = 'scm';
end
end

function subjects = fc_make_subjects(dataIn,opts)
if iscell(dataIn)
    L = dataIn;
elseif isstruct(dataIn) && numel(dataIn) > 1
    L = cell(numel(dataIn),1);
    for i = 1:numel(dataIn), L{i} = dataIn(i); end
else
    L = {dataIn};
end
subjects = repmat(fc_empty_subject(),numel(L),1);
for i = 1:numel(L)
    [s,ok] = fc_one_subject(L{i},opts,i);
    if ~ok, error('Invalid subject at index %d.',i); end
    subjects(i) = s;
end
end

function s = fc_empty_subject()
s = struct();
s.I4 = [];
s.TR = 1;
s.mask = [];
s.anat = [];
s.anatIsDisplayReady = false;
s.roiAtlas = [];
s.roiNameTable = struct('labels',[],'names',{{}});
s.name = '';
s.group = 'All';
s.analysisDir = '';
end

function [s,ok] = fc_one_subject(in,opts,idx)
ok = false;
s = fc_empty_subject();
s.name = sprintf('Subject_%02d',idx);
s.roiNameTable = opts.roiNameTable;

if isnumeric(in)
    s.I4 = fc_force4d(in);
    s.analysisDir = opts.saveRoot;
    ok = true;
    return;
end

if ~isstruct(in), return; end
if isfield(in,'name') && ~isempty(in.name), s.name = char(in.name); end
if isfield(in,'group') && ~isempty(in.group), s.group = char(in.group); end
if isfield(in,'TR') && ~isempty(in.TR), s.TR = double(in.TR); end
if ~isscalar(s.TR) || ~isfinite(s.TR) || s.TR <= 0, s.TR = 1; end

[I,okI] = fc_get_functional(in,opts);
if ~okI, return; end
s.I4 = fc_force4d(I);
[Y,X,Z] = fc_size3(s.I4);

if isfield(in,'mask') && ~isempty(in.mask)
    s.mask = fc_fit_volume(in.mask,Y,X,Z,true);
elseif isfield(in,'brainMask') && ~isempty(in.brainMask)
    s.mask = fc_fit_volume(in.brainMask,Y,X,Z,true);
end

if isfield(in,'anatomical_reference') && ~isempty(in.anatomical_reference)
    s.anat = fc_fit_volume(in.anatomical_reference,Y,X,Z,false);
    s.anatIsDisplayReady = true;
elseif isfield(in,'anatomicalReference') && ~isempty(in.anatomicalReference)
    s.anat = fc_fit_volume(in.anatomicalReference,Y,X,Z,false);
    s.anatIsDisplayReady = true;
elseif isfield(in,'brainImage') && ~isempty(in.brainImage)
    s.anat = fc_fit_volume(in.brainImage,Y,X,Z,false);
    s.anatIsDisplayReady = true;
elseif isfield(in,'anat') && ~isempty(in.anat)
    s.anat = fc_fit_volume(in.anat,Y,X,Z,false);
elseif isfield(in,'bg') && ~isempty(in.bg)
    s.anat = fc_fit_volume(in.bg,Y,X,Z,false);
elseif isfield(in,'underlay') && ~isempty(in.underlay)
    s.anat = fc_fit_volume(in.underlay,Y,X,Z,false);
elseif isfield(in,'anatomical_reference_raw') && ~isempty(in.anatomical_reference_raw)
    s.anat = fc_fit_volume(in.anatomical_reference_raw,Y,X,Z,false);
end

try
    if isfield(in,'anatIsDisplayReady') && ~isempty(in.anatIsDisplayReady)
        s.anatIsDisplayReady = logical(in.anatIsDisplayReady);
    elseif isfield(in,'anatomicalReferenceIsDisplayReady') && ~isempty(in.anatomicalReferenceIsDisplayReady)
        s.anatIsDisplayReady = logical(in.anatomicalReferenceIsDisplayReady);
    elseif isfield(opts,'anatIsDisplayReady') && ~isempty(opts.anatIsDisplayReady) && ~isempty(s.anat)
        s.anatIsDisplayReady = logical(opts.anatIsDisplayReady);
    end
catch
end

if isfield(in,'roiAtlas') && ~isempty(in.roiAtlas)
    s.roiAtlas = fc_fit_volume(in.roiAtlas,Y,X,Z,false);
elseif isfield(in,'atlas') && ~isempty(in.atlas)
    tmp = fc_fit_volume(in.atlas,Y,X,Z,false);
    if fc_looks_like_roi_label_map(tmp), s.roiAtlas = tmp; end
elseif isfield(in,'regions') && ~isempty(in.regions)
    s.roiAtlas = fc_fit_volume(in.regions,Y,X,Z,false);
elseif isfield(in,'annotation') && ~isempty(in.annotation)
    s.roiAtlas = fc_fit_volume(in.annotation,Y,X,Z,false);
elseif isfield(in,'labels') && ~isempty(in.labels) && isnumeric(in.labels)
    s.roiAtlas = fc_fit_volume(in.labels,Y,X,Z,false);
end
if ~isempty(s.roiAtlas), s.roiAtlas = round(double(s.roiAtlas)); end

if isfield(in,'analysisDir') && exist(char(in.analysisDir),'dir')
    s.analysisDir = char(in.analysisDir);
elseif isfield(in,'loadedPath') && exist(char(in.loadedPath),'dir')
    s.analysisDir = char(in.loadedPath);
else
    s.analysisDir = opts.saveRoot;
end
ok = true;
end

function [I,ok] = fc_get_functional(s,opts)
ok = false; I = [];
if ~isempty(opts.functionalField) && isfield(s,opts.functionalField)
    x = s.(opts.functionalField);
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        I = x; ok = true; return;
    end
end
cand = {'I','PSC','data','functional','func','movie','volume'};
for i = 1:numel(cand)
    if isfield(s,cand{i})
        x = s.(cand{i});
        if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
            I = x; ok = true; return;
        end
    end
end
fn = fieldnames(s);
for i = 1:numel(fn)
    x = s.(fn{i});
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        I = x; ok = true; return;
    end
end
end

function I4 = fc_force4d(I)
if ndims(I) == 3
    sz = size(I);
    I4 = reshape(single(I),sz(1),sz(2),1,sz(3));
elseif ndims(I) == 4
    I4 = single(I);
else
    error('Data must be [Y X T] or [Y X Z T].');
end
end

function [Y,X,Z] = fc_size3(I4)
sz = size(I4); Y = sz(1); X = sz(2); Z = sz(3);
end

function V = fc_fit_volume(V0,Y,X,Z,makeLogical)
V = [];
V0 = squeeze(V0);
if ndims(V0)==2 && Z==1 && size(V0,1)==Y && size(V0,2)==X
    V = reshape(V0,Y,X,1);
elseif ndims(V0)==2 && size(V0,1)==Y && size(V0,2)==X && Z > 1
    V = repmat(V0,[1 1 Z]);
elseif ndims(V0)==2 && size(V0,1)==X && size(V0,2)==Y
    V0 = V0';
    if Z==1, V = reshape(V0,Y,X,1); else, V = repmat(V0,[1 1 Z]); end
elseif ndims(V0)==3 && all(size(V0)==[Y X Z])
    V = V0;
elseif ndims(V0)==3 && size(V0,1)==Y && size(V0,2)==X
    zi = round(linspace(1,size(V0,3),Z));
    V = V0(:,:,zi);
elseif ndims(V0)==3 && size(V0,1)==X && size(V0,2)==Y
    V0 = permute(V0,[2 1 3]);
    zi = round(linspace(1,size(V0,3),Z));
    V = V0(:,:,zi);
elseif ndims(V0)==4 && size(V0,1)==Y && size(V0,2)==X
    V = mean(V0,4);
    V = fc_fit_volume(V,Y,X,Z,makeLogical);
end
if ~isempty(V) && makeLogical, V = logical(V); end
end

function [subjects,msg] = fc_startup_masks(subjects,opts)
if ~opts.askMaskAtStart
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask), subjects(i).mask = fc_auto_mask(subjects(i).I4); end
    end
    msg = 'Mask: auto for missing.';
    return;
end
hasMask = false;
for i = 1:numel(subjects)
    if ~isempty(subjects(i).mask), hasMask = true; break; end
end
if hasMask
    choice = questdlg('Mask startup:', 'Mask startup','Use provided','Auto masks','Use provided');
else
    choice = questdlg('No mask provided. Use automatic masks?', 'Mask startup','Auto masks','No mask','Auto masks');
end
if isempty(choice), choice = 'Auto masks'; end
if strcmpi(choice,'Use provided')
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask), subjects(i).mask = fc_auto_mask(subjects(i).I4); end
    end
    msg = 'Mask: provided with auto fallback.';
elseif strcmpi(choice,'No mask')
    msg = 'Mask: none.';
else
    for i = 1:numel(subjects), subjects(i).mask = fc_auto_mask(subjects(i).I4); end
    msg = 'Mask: automatic.';
end
end

function mask = fc_auto_mask(I4)
m = mean(I4,4);
thr = fc_prctile(m(:),25);
mask = m > thr;
end

function atlas = fc_ask_common_atlas(subj,opts,Y,X,Z)
atlas = [];
q = questdlg('No ROI atlas found. Load common ROI label map MAT now?', 'ROI labels','Yes','No','No');
if ~strcmpi(q,'Yes'), return; end
[f,p] = fc_uigetfile_start({'*.mat','MAT files (*.mat)'},'Load ROI labels',fc_start_dir(subj,opts));
if isequal(f,0), return; end
atlas = fc_read_atlas_any(fullfile(p,f),Y,X,Z);
if isempty(atlas)
    errordlg('No compatible ROI label map found.');
else
    atlas = round(double(atlas));
end
end

function startDir = fc_start_dir(subj,opts)
% Prefer the 2D atlas/coregistration output folder.
% Main target: <exportPath>/Registration2D
% Fallbacks: <analysisDir>/Registration2D, then older Registration folder, then root.
startDir = pwd;
try
    if isfield(opts,'stepMotorFolder') && ~isempty(opts.stepMotorFolder) && exist(opts.stepMotorFolder,'dir') == 7
        segDir0 = fullfile(opts.stepMotorFolder,'Segmentation');
        if exist(segDir0,'dir') == 7, startDir = segDir0; return; end
        startDir = opts.stepMotorFolder; return;
    end
catch
end
try
    if isfield(opts,'registrationPath') && ~isempty(opts.registrationPath) && exist(opts.registrationPath,'dir')
        startDir = opts.registrationPath; return;
    end
catch
end
try
    if isfield(opts,'registration2DPath') && ~isempty(opts.registration2DPath) && exist(opts.registration2DPath,'dir')
        startDir = opts.registration2DPath; return;
    end
catch
end
try
    if isfield(opts,'startDirAtlas') && ~isempty(opts.startDirAtlas) && exist(opts.startDirAtlas,'dir')
        startDir = opts.startDirAtlas; return;
    end
catch
end
try
    if isfield(opts,'exportPath') && ~isempty(opts.exportPath)
        reg2DDir = fullfile(opts.exportPath,'Registration2D');
        if ~exist(reg2DDir,'dir')
            try, mkdir(reg2DDir); catch, end
        end
        if exist(reg2DDir,'dir'), startDir = reg2DDir; return; end

        oldRegDir = fullfile(opts.exportPath,'Registration');
        if exist(oldRegDir,'dir'), startDir = oldRegDir; return; end
    end
catch
end
try
    if isfield(subj,'analysisDir') && ~isempty(subj.analysisDir)
        reg2DDir = fullfile(subj.analysisDir,'Registration2D');
        if exist(reg2DDir,'dir'), startDir = reg2DDir; return; end

        oldRegDir = fullfile(subj.analysisDir,'Registration');
        if exist(oldRegDir,'dir'), startDir = oldRegDir; return; end
    end
catch
end
if isfield(subj,'analysisDir') && ~isempty(subj.analysisDir) && exist(subj.analysisDir,'dir')
    startDir = subj.analysisDir;
elseif isfield(opts,'exportPath') && ~isempty(opts.exportPath) && exist(opts.exportPath,'dir')
    startDir = opts.exportPath;
elseif isfield(opts,'loadedPath') && ~isempty(opts.loadedPath) && exist(opts.loadedPath,'dir')
    startDir = opts.loadedPath;
elseif isfield(opts,'saveRoot') && exist(opts.saveRoot,'dir')
    startDir = opts.saveRoot;
end
end

function [f,p] = fc_uigetfile_start(filterSpec,titleStr,startDir)
if nargin < 3 || isempty(startDir) || ~exist(startDir,'dir')
    startDir = pwd;
try
    if isfield(opts,'stepMotorFolder') && ~isempty(opts.stepMotorFolder) && exist(opts.stepMotorFolder,'dir') == 7
        segDir0 = fullfile(opts.stepMotorFolder,'Segmentation');
        if exist(segDir0,'dir') == 7, startDir = segDir0; return; end
        startDir = opts.stepMotorFolder; return;
    end
catch
end
end
oldDir = pwd;
cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>
try, cd(startDir); catch, end
[f,p] = uigetfile(filterSpec,titleStr);
end

function [I,varName] = fc_pick_data_from_mat(S)
I = []; varName = '';
fn = fieldnames(S); cand = {};
for i = 1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        cand{end+1} = fn{i}; %#ok<AGROW>
    elseif isstruct(x) && isfield(x,'Data') && isnumeric(x.Data) && (ndims(x.Data)==3 || ndims(x.Data)==4)
        cand{end+1} = [fn{i} '.Data']; %#ok<AGROW>
    elseif isstruct(x) && isfield(x,'I') && isnumeric(x.I) && (ndims(x.I)==3 || ndims(x.I)==4)
        cand{end+1} = [fn{i} '.I']; %#ok<AGROW>
    end
end
if isempty(cand), return; end
if numel(cand)==1
    varName = cand{1};
else
    [sel,ok] = listdlg('PromptString','Select data variable:', 'SelectionMode','single','ListString',cand);
    if ok && ~isempty(sel), varName = cand{sel}; else, varName = cand{1}; end
end
if ~isempty(strfind(varName,'.Data'))
    base = strrep(varName,'.Data',''); I = S.(base).Data;
elseif ~isempty(strfind(varName,'.I'))
    base = strrep(varName,'.I',''); I = S.(base).I;
else
    I = S.(varName);
end
end

function V = fc_pick_volume(S,Y,X,Z)
V = [];
fn = fieldnames(S);
preferred = {'mask','brainMask','loadedMask','activeMask','underlayMask','roiAtlas','atlas','regions','annotation','labels','Data'};
for p = 1:numel(preferred)
    if isfield(S,preferred{p})
        V = fc_volume_from_any(S.(preferred{p}),Y,X,Z);
        if ~isempty(V), return; end
    end
end
for i = 1:numel(fn)
    V = fc_volume_from_any(S.(fn{i}),Y,X,Z);
    if ~isempty(V), return; end
end
end

function V = fc_volume_from_any(x,Y,X,Z)
V = [];
if isstruct(x)
    if isfield(x,'Data'), x = x.Data; elseif isfield(x,'I'), x = x.I; else, return; end
end
if ~(isnumeric(x) || islogical(x)), return; end
V = fc_fit_volume(x,Y,X,Z,false);
end

function A = fc_read_atlas_any(fullFile,Y,X,Z)
A = [];
if ~exist(fullFile,'file'), return; end
try
    if numel(fullFile) >= 7 && strcmpi(fullFile(end-6:end),'.nii.gz')
        tmpDir = tempname; mkdir(tmpDir);
        cleanup = onCleanup(@() fc_rmdir_safe(tmpDir)); %#ok<NASGU>
        gunzip(fullFile,tmpDir);
        d = dir(fullfile(tmpDir,'*.nii'));
        if isempty(d), return; end
        V = double(niftiread(fullfile(tmpDir,d(1).name)));
        A = fc_atlas_volume_from_any(V,Y,X,Z);
    else
        [~,~,ext] = fileparts(fullFile); ext = lower(ext);
        if strcmpi(ext,'.nii')
            V = double(niftiread(fullFile));
            A = fc_atlas_volume_from_any(V,Y,X,Z);
        elseif strcmpi(ext,'.mat')
            S = load(fullFile);
            A = fc_pick_atlas_volume(S,Y,X,Z);
        else
            V = double(imread(fullFile));
            A = fc_atlas_volume_from_any(V,Y,X,Z);
        end
    end
catch
    A = [];
end
if ~isempty(A)
    A = round(double(A));
    if ~fc_looks_like_roi_label_map(A), A = []; end
end
end

function fc_rmdir_safe(d)
try, if exist(d,'dir'), rmdir(d,'s'); end, catch, end
end

function A = fc_pick_atlas_volume(S,Y,X,Z)
A = [];
try
    A = fcStudioPickAtlasVolume(S,Y,X,Z);
catch
    cand = {};
    names = {};
    fns = fieldnames(S);
    preferred = {'atlasRegionLabelsLR2D','roiAtlas','labelMap','atlasRegionLabels2D','regionLabelsLR','regionLabels','labels','annotation','regions','Regions','atlas','labelVolume','area'};
    for i = 1:numel(preferred)
        if isfield(S,preferred{i})
            tmp = fc_atlas_volume_from_any(S.(preferred{i}),Y,X,Z);
            if ~isempty(tmp)
                cand{end+1} = tmp; %#ok<AGROW>
                names{end+1} = preferred{i}; %#ok<AGROW>
            end
        end
    end
    for i = 1:numel(fns)
        tmp = fc_atlas_volume_from_any(S.(fns{i}),Y,X,Z);
        if ~isempty(tmp)
            cand{end+1} = tmp; %#ok<AGROW>
            names{end+1} = fns{i}; %#ok<AGROW>
        end
    end
    if isempty(cand), return; end
    scores = zeros(numel(cand),1);
    for k = 1:numel(cand), scores(k) = fc_score_atlas_candidate(cand{k},names{k}); end
    [~,idx] = max(scores);
    if isfinite(scores(idx)), A = cand{idx}; end
end
if ~isempty(A)
    A = round(double(A));
    if ~fc_looks_like_roi_label_map(A), A = []; end
end
end

function A = fc_atlas_volume_from_any(x,Y,X,Z)
A = [];
if isstruct(x)
    if isfield(x,'Data'), x = x.Data; elseif isfield(x,'I'), x = x.I; else, return; end
end
if ~(isnumeric(x) || islogical(x)), return; end
x = squeeze(x);
if ndims(x)==3 && size(x,3)==3 && Z==1
    return;
end
V = fc_fit_volume(x,Y,X,Z,false);
if isempty(V), return; end
if fc_looks_like_roi_label_map(V), A = round(double(V)); end
end

function score = fc_score_atlas_candidate(A,nameStr)
score = -Inf;
if isempty(A) || ~fc_looks_like_roi_label_map(A), return; end
score = 100;
lname = lower(nameStr);
good = {'roi','atlas','region','label','annotation','area'};
bad = {'histology','anat','anatom','underlay','display','mask','image','img','bg','raw'};
for i = 1:numel(good), if ~isempty(strfind(lname,good{i})), score = score + 20; end, end
for i = 1:numel(bad), if ~isempty(strfind(lname,bad{i})), score = score - 25; end, end
try
    U = unique(round(double(A(:)))); U = U(U~=0);
    score = score + min(50,numel(U));
catch
end
end

function tf = fc_looks_like_roi_label_map(A)
tf = false;
try
    A = double(A); A = A(isfinite(A));
    if isempty(A), return; end
    if numel(A) > 200000
        idx = round(linspace(1,numel(A),200000)); A = A(idx);
    end
    fracInt = mean(abs(A - round(A)) < 1e-6);
    if fracInt < 0.98, return; end
    U = unique(round(A(:))); U = U(U~=0);
    if numel(U) < 2, return; end
    if numel(U) > 5000, return; end
    tf = true;
catch
    tf = false;
end
end

function [U,isRGB,isDisplayReady] = fc_read_underlay(fullf,Y,X,Z)
U = [];
isRGB = false;
isDisplayReady = false;
[~,~,ext] = fileparts(fullf);
ext = lower(ext);

if strcmp(ext,'.mat')
    S = load(fullf);
    [U,isDisplayReady] = fc_pick_underlay_from_mat(S,Y,X,Z);
    if isempty(U)
        [U,~] = fc_pick_data_from_mat(S);
        isDisplayReady = false;
    end
else
    U = double(imread(fullf));
    isDisplayReady = true;
end

if isempty(U), error('No compatible underlay found.'); end
U = squeeze(U);

if ndims(U)==3 && size(U,3)==3 && Z==1
    isRGB = true;
    if max(U(:)) > 1, U = U / 255; end
    if size(U,1) ~= Y || size(U,2) ~= X, U = fc_resize_rgb(U,Y,X); end
    isDisplayReady = true;
    return;
end

if ndims(U)==2
    if size(U,1) ~= Y || size(U,2) ~= X, U = fc_resize2(U,Y,X); end
    if Z > 1, U = repmat(U,[1 1 Z]); end
elseif ndims(U)==3
    if size(U,1) ~= Y || size(U,2) ~= X
        tmp = zeros(Y,X,size(U,3));
        for z = 1:size(U,3), tmp(:,:,z) = fc_resize2(U(:,:,z),Y,X); end
        U = tmp;
    end
    if size(U,3) ~= Z
        zi = round(linspace(1,size(U,3),Z));
        U = U(:,:,zi);
    end
else
    error('Unsupported underlay dimensions.');
end
end

function [U,isDisplayReady] = fc_pick_underlay_from_mat(S,Y,X,Z)
U = []; isDisplayReady = false;
if isfield(S,'maskBundle') && isstruct(S.maskBundle)
    [U,isDisplayReady] = fc_pick_underlay_from_struct(S.maskBundle,Y,X,Z);
    if ~isempty(U), return; end
end
[U,isDisplayReady] = fc_pick_underlay_from_struct(S,Y,X,Z);
end

function [U,isDisplayReady] = fc_pick_underlay_from_struct(S,Y,X,Z)
U = []; isDisplayReady = false;

displayFields = {'anatomical_reference','anatomicalReference','savedUnderlayDisplay','savedUnderlayForReload','brainImage','brainImageDisplay'};
for i = 1:numel(displayFields)
    fn = displayFields{i};
    if ~isfield(S,fn), continue; end
    Ucand = fc_underlay_candidate(S.(fn),Y,X,Z);
    if isempty(Ucand), continue; end
    if fc_is_binary_mask(Ucand), continue; end
    U = Ucand;
    isDisplayReady = true;
    return;
end

rawFields = {'anatomical_reference_raw','anatomicalReferenceRaw','savedUnderlayRaw','underlay','bg','DP','dp','histology','Histology','image','img','I','Data'};
for i = 1:numel(rawFields)
    fn = rawFields{i};
    if ~isfield(S,fn), continue; end
    Ucand = fc_underlay_candidate(S.(fn),Y,X,Z);
    if isempty(Ucand), continue; end
    if fc_is_binary_mask(Ucand), continue; end
    if fc_looks_like_roi_label_map(Ucand) && fc_underlay_unique_count(Ucand) < 50, continue; end
    U = Ucand;
    isDisplayReady = false;
    return;
end

skip = {'mask','loadedMask','activeMask','brainMask','underlayMask','overlayMask','signalMask','roiAtlas','atlas','regions','annotation','labels','labelVolume','maskIsInclude','loadedMaskIsInclude','overlayMaskIsInclude'};
fns = fieldnames(S);
for i = 1:numel(fns)
    fn = fns{i};
    if any(strcmpi(fn,skip)), continue; end
    Ucand = fc_underlay_candidate(S.(fn),Y,X,Z);
    if isempty(Ucand), continue; end
    if fc_is_binary_mask(Ucand), continue; end
    if fc_looks_like_roi_label_map(Ucand) && fc_underlay_unique_count(Ucand) < 50, continue; end
    U = Ucand;
    isDisplayReady = false;
    return;
end
end

function n = fc_underlay_unique_count(A)
try
    A = double(A(:)); A = A(isfinite(A));
    if numel(A) > 200000
        idx = round(linspace(1,numel(A),200000)); A = A(idx);
    end
    n = numel(unique(A));
catch
    n = 0;
end
end

function tf = fc_is_binary_mask(A)
tf = false;
try
    A = double(A); A = A(isfinite(A));
    if isempty(A), tf = true; return; end
    U = unique(A(:));
    tf = numel(U) <= 2 && all(ismember(U,[0 1]));
catch
    tf = false;
end
end

function U = fc_underlay_candidate(v,Y,X,Z)
U = [];
if isstruct(v)
    if isfield(v,'Data'), v = v.Data;
    elseif isfield(v,'I'), v = v.I;
    else, return;
    end
end
if ~(isnumeric(v) || islogical(v)), return; end
v = squeeze(v);
if ndims(v)==3 && size(v,3)==3 && Z==1
    U = double(v); return;
end
U = fc_fit_volume(v,Y,X,Z,false);
if ~isempty(U), U = double(U); end
end

function B = fc_resize2(A,Y,X)
if exist('imresize','file') == 2
    B = imresize(A,[Y X],'nearest');
else
    yy = round(linspace(1,size(A,1),Y)); xx = round(linspace(1,size(A,2),X)); B = A(yy,xx);
end
end

function R = fc_resize_rgb(R,Y,X)
tmp = zeros(Y,X,3);
for k = 1:3, tmp(:,:,k) = fc_resize2(R(:,:,k),Y,X); end
R = tmp;
end

function T = fc_read_region_names(fullf)
T = HUMOR_FC_read_region_names_file(fullf);
end

function T = fc_region_names_from_mat(S)


T = struct('labels',[],'names',{{}});
% HUMOR_FC_SEG_REGION_NAMES_FIX_20260519
try
    if isfield(S,'Seg') && isstruct(S.Seg) && isfield(S.Seg,'region')
        T = fc_region_names_from_region_struct(S.Seg.region);
        if ~isempty(T.labels), return; end
    end
    if isfield(S,'region') && isstruct(S.region)
        T = fc_region_names_from_region_struct(S.region);
        if ~isempty(T.labels), return; end
    end
catch
end
try
    if isfield(S,'Seg') && isstruct(S.Seg) && isfield(S.Seg,'region')
        T = fc_region_names_from_region_struct(S.Seg.region);
        if ~isempty(T.labels), return; end
    end
    if isfield(S,'region') && isstruct(S.region)
        T = fc_region_names_from_region_struct(S.region);
        if ~isempty(T.labels), return; end
    end
catch
end
if isfield(S,'roiNameTable')
    x = S.roiNameTable;
    if isstruct(x) && isfield(x,'labels') && isfield(x,'names')
        T.labels = double(x.labels(:)); T.names = cellstr(x.names(:)); return;
    end
end
if isfield(S,'labels') && isfield(S,'names')
    T.labels = double(S.labels(:)); T.names = cellstr(S.names(:)); return;
end
fn = fieldnames(S);
for i = 1:numel(fn)
    x = S.(fn{i});
    if isstruct(x) && numel(x) > 1
        f = fieldnames(x); idField = ''; nameField = '';
        if any(strcmpi(f,'id')), idField = 'id'; end
        if any(strcmpi(f,'label')), idField = 'label'; end
        if any(strcmpi(f,'acronym')), nameField = 'acronym'; end
        if any(strcmpi(f,'name')), nameField = 'name'; end
        if ~isempty(idField) && ~isempty(nameField)
            labs = zeros(numel(x),1); nms = cell(numel(x),1);
            for k = 1:numel(x)
                labs(k) = double(x(k).(idField)); nms{k} = char(x(k).(nameField));
            end
            T.labels = labs; T.names = nms; return;
        end
    end
end
end

function info = fc_read_scm_roi(txtFile)
fid = fopen(txtFile,'r');
if fid < 0, error('Could not open ROI TXT.'); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
info = struct('x1',NaN,'x2',NaN,'y1',NaN,'y2',NaN,'slice',NaN);
L = {};
while ~feof(fid), L{end+1} = fgetl(fid); end %#ok<AGROW>
for i = 1:numel(L)
    s = strtrim(L{i});
    if strncmpi(s,'# SLICE:',8), info.slice = str2double(strtrim(s(9:end))); end
    if i > 1 && strcmp(strtrim(L{i-1}),'# x1 x2 y1 y2')
        v = sscanf(s,'%f %f %f %f');
        if numel(v)==4
            info.x1 = v(1); info.x2 = v(2); info.y1 = v(3); info.y2 = v(4);
        end
    end
end
if ~all(isfinite([info.x1 info.x2 info.y1 info.y2])), error('Could not parse x1 x2 y1 y2.'); end
end

function pos = fc_seed_box_position(seedX,seedY,boxSize,X,Y)
[x1,x2,y1,y2] = fc_seed_bounds(seedX,seedY,boxSize,X,Y);
pos = [x1-0.5, y1-0.5, x2-x1+1, y2-y1+1];
end

function [x1,x2,y1,y2] = fc_seed_bounds(seedX,seedY,boxSize,X,Y)
boxSize = max(1,round(boxSize));
seedX = fc_clip(round(seedX),1,X);
seedY = fc_clip(round(seedY),1,Y);
left  = floor((boxSize-1)/2);
right = ceil((boxSize-1)/2);
x1 = max(1,seedX-left);
x2 = min(X,seedX+right);
y1 = max(1,seedY-left);
y2 = min(Y,seedY+right);
end

function res = fc_seed_fc(I4,TR,mask,seedX,seedY,seedZ,boxSize,useSliceOnly,chunkVox)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>
if isempty(mask), mask = fc_auto_mask(I4); end
seedX = fc_clip(seedX,1,X); seedY = fc_clip(seedY,1,Y); seedZ = fc_clip(seedZ,1,Z);
seedMask2D = false(Y,X);
[x1,x2,y1,y2] = fc_seed_bounds(seedX,seedY,boxSize,X,Y);
seedMask2D(y1:y2,x1:x2) = true;
seedMask = false(Y,X,Z); seedMask(:,:,seedZ) = seedMask2D; seedMask = seedMask & mask;
seedIdx = find(seedMask(:));
if isempty(seedIdx), seedMask(seedY,seedX,seedZ) = true; seedIdx = find(seedMask(:)); end
V = Y*X*Z; D = reshape(I4,[V size(I4,4)]);
seedTS = mean(double(D(seedIdx,:)),1)';
s = seedTS - mean(seedTS); sNorm = sqrt(sum(s.^2));
if sNorm <= 0 || ~isfinite(sNorm), error('Seed timecourse has zero variance.'); end
if useSliceOnly
    voxMask = false(Y,X,Z); voxMask(:,:,seedZ) = mask(:,:,seedZ);
else
    voxMask = mask;
end
voxIdx = find(voxMask(:)); r = nan(V,1,'single');
chunk = max(1000,round(chunkVox)); s = single(s);
for i0 = 1:chunk:numel(voxIdx)
    i1 = min(numel(voxIdx),i0+chunk-1); id = voxIdx(i0:i1);
    Xc = D(id,:); Xc = bsxfun(@minus,Xc,mean(Xc,2));
    num = Xc * s; den = sqrt(sum(Xc.^2,2)) * single(sNorm);
    rr = num ./ max(den,single(eps)); rr(~isfinite(rr)) = 0; rr = max(-1,min(1,rr));
    r(id) = rr;
end
rMap = reshape(r,[Y X Z]); zMap = single(atanh(max(-0.999999,min(0.999999,double(rMap)))));
res = struct();
res.rMap = rMap; res.zMap = zMap; res.seedTS = seedTS; res.seedMask = seedMask; res.TR = TR;
res.seedInfo = struct('x',seedX,'y',seedY,'z',seedZ,'boxSize',boxSize,'useSliceOnly',useSliceOnly);
end

function res = fc_roi_fc(I4,TR,mask,atlas,opts)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>
if isempty(mask), mask = fc_auto_mask(I4); end

V = Y*X*Z;
D = reshape(I4,[V size(I4,4)]);

% IMPORTANT:
% Keep signed atlas labels separate. Do NOT use abs(label).
% This preserves left/right hemisphere labels when the atlas/segmentation uses signed IDs.
atlasV = round(double(atlas(:)));
maskV = logical(mask(:));

labels = unique(atlasV(maskV & atlasV ~= 0));
labels = labels(:);
labels = labels(isfinite(labels) & labels ~= 0);
if isempty(labels), error('No atlas labels inside mask.'); end

keepLabels = [];
names = {};
counts = [];
meanTS = [];

for k = 1:numel(labels)
    lab = round(double(labels(k)));
    nm = fc_roi_name(lab,opts);

    % Remove root/background/outside labels from FC.
    if fc_is_background_region(lab,nm)
        continue;
    end

    idx = find(maskV & atlasV == lab);
    if numel(idx) < opts.roiMinVox, continue; end

    ts = mean(double(D(idx,:)),1)';
    keepLabels(end+1,1) = lab; %#ok<AGROW>
    counts(end+1,1) = numel(idx); %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
    meanTS(:,end+1) = ts; %#ok<AGROW>
end

if isempty(keepLabels)
    error('No ROI survived roiMinVox after removing root/background labels.');
end

M = fc_corr_matrix(meanTS);

res = struct();
res.labels = keepLabels;
res.names = names;
res.counts = counts;
res.meanTS = meanTS;
res.M = M;
res.TR = TR;
end

function M = fc_corr_matrix(X)
X = double(X);
X = bsxfun(@minus,X,mean(X,1));
sd = std(X,0,1);
sd(sd <= 0 | ~isfinite(sd)) = 1;
X = bsxfun(@rdivide,X,sd);
M = (X' * X) / max(1,size(X,1)-1);
M = max(-1,min(1,M));
M(1:size(M,1)+1:end) = 1;
end

function [M,names,order,meta] = fc_current_matrix(s,res)
% HUMOR_REPAIR_TRUE_SLICE_CURRENT_MATRIX_20260519
try
    if isfield(s,'Z') && s.Z > 1 && isfield(s,'sliceRegionOnly') && s.sliceRegionOnly
        if ~(isstruct(res) && isfield(res,'sliceOnly') && isequal(res.sliceOnly,true))
            res = HUMOR_FC_make_slice_roi_result(s,s.currentSubject,res,s.slice);
        end
    end
catch
end
% Region-mode aware matrix builder.
% Modes:
%   both   = L_ and R_ regions remain separate.
%   left   = only L_ / negative-label regions.
%   right  = only R_ / positive-label regions when signed LR exists.
%   merged = L/R homologs are averaged into one bilateral region.
M0 = double(res.M);
names0 = res.names(:);
labels0 = double(res.labels(:));
n0 = numel(labels0);

if numel(names0) < n0
    tmp = cell(n0,1);
    for ii = 1:n0
        if ii <= numel(names0), tmp{ii} = names0{ii}; else, tmp{ii} = sprintf('ROI_%g',labels0(ii)); end
    end
    names0 = tmp;
end

mode = fc_region_mode_from_state(s);
hasSignedLR = any(labels0 < 0);

% FC_LR_EPOCH_PATCH_20260505_LVR_MATRIX
if strcmpi(mode,'lvr')
    leftIdx = [];
    rightIdx = [];
    for ii = 1:n0
        sideNow = fc_region_side_from_name_label(names0{ii},labels0(ii),hasSignedLR);
        if strcmpi(sideNow,'L'), leftIdx(end+1,1) = ii; end %#ok<AGROW>
        if strcmpi(sideNow,'R'), rightIdx(end+1,1) = ii; end %#ok<AGROW>
    end

    if isempty(leftIdx) || isempty(rightIdx)
        % Fallback to normal both-mode if hemisphere detection is unavailable.
        mode = 'both';
    else
        namesL0 = names0(leftIdx);
        namesR0 = names0(rightIdx);
        cleanL = cell(size(namesL0));
        cleanR = cell(size(namesR0));
        for ii = 1:numel(namesL0), cleanL{ii} = lower(fc_region_fullname_no_lr(namesL0{ii})); end
        for ii = 1:numel(namesR0), cleanR{ii} = lower(fc_region_fullname_no_lr(namesR0{ii})); end
        [~,ordL] = sort(cleanL);
        [~,ordR] = sort(cleanR);
        leftIdx = leftIdx(ordL);
        rightIdx = rightIdx(ordR);

        M = M0(leftIdx,rightIdx);
        names = names0(leftIdx);
        order = leftIdx;

        meta = struct();
        meta.mode = 'lvr';
        meta.isRectangular = true;
        meta.namesY = names0(leftIdx);
        meta.namesX = names0(rightIdx);
        meta.orderY = leftIdx(:);
        meta.orderX = rightIdx(:);
        meta.displayLabelsY = labels0(leftIdx);
        meta.displayLabelsX = labels0(rightIdx);
        meta.displayLabels = labels0(leftIdx);
        meta.rawLabels = labels0(:);
        meta.rawNames = names0(:);
        meta.groups = cell(numel(leftIdx),1);
        for ii = 1:numel(leftIdx), meta.groups{ii} = leftIdx(ii); end
        return;
    end
end
% FC_LR_EPOCH_PATCH_20260505_LVR_MATRIX_END

if strcmpi(mode,'merged') && isfield(res,'meanTS') && ~isempty(res.meanTS) && size(res.meanTS,2) == n0
    [TSmerge,names,labelsDisplay,groups,order] = fc_merge_lr_timecourses(res.meanTS,names0,labels0);
    M = fc_corr_matrix(TSmerge);
else
    keep = true(n0,1);
    if strcmpi(mode,'left') || strcmpi(mode,'right')
        keep = false(n0,1);
        for ii = 1:n0
            sideNow = fc_region_side_from_name_label(names0{ii},labels0(ii),hasSignedLR);
            if strcmpi(mode,'left') && strcmpi(sideNow,'L'), keep(ii) = true; end
            if strcmpi(mode,'right') && strcmpi(sideNow,'R'), keep(ii) = true; end
        end
        if ~any(keep)
            keep = true(n0,1);
        end
    end
    order = find(keep);
    M = M0(order,order);
    names = names0(order);
    labelsDisplay = labels0(order);
    groups = cell(numel(order),1);
    for ii = 1:numel(order)
        groups{ii} = order(ii);
    end
end

% Sort after filtering/merging.
try
    switch lower(s.roiOrder)
        case 'name'
            cleanNames = cell(size(names));
            for ii = 1:numel(names)
                cleanNames{ii} = lower(fc_region_fullname_no_lr(names{ii}));
            end
            [~,ord2] = sort(cleanNames);
        otherwise
            [~,ord2] = sort(labelsDisplay);
    end
catch
    ord2 = 1:numel(names);
end

M = M(ord2,ord2);
names = names(ord2);
labelsDisplay = labelsDisplay(ord2);
order = order(ord2);
groups = groups(ord2);

meta = struct();
meta.mode = mode;
meta.groups = groups(:);
meta.displayLabels = labelsDisplay(:);
meta.rawLabels = labels0(:);
meta.rawNames = names0(:);
end
function mode = fc_region_mode_from_state(s)
mode = 'both';
try
    if isfield(s,'roiHemiMode') && ~isempty(s.roiHemiMode)
        mode = lower(strtrim(char(s.roiHemiMode)));
    end
catch
    mode = 'both';
end
if strcmpi(mode,'all') || strcmpi(mode,'merge') || strcmpi(mode,'bilateral')
    mode = 'merged';
end
if strcmpi(mode,'left-vs-right') || strcmpi(mode,'left_vs_right') || strcmpi(mode,'leftright') || strcmpi(mode,'cross')
    mode = 'lvr';
end
if ~any(strcmpi(mode,{'both','left','right','lvr','merged'}))
    mode = 'both';
end
end

function val = fc_region_mode_to_popup_value(mode)
mode = fc_region_mode_from_state(struct('roiHemiMode',mode));
switch lower(mode)
    case 'left',   val = 2;
    case 'right',  val = 3;
    case 'lvr',    val = 4;
    case 'merged', val = 5;
    otherwise,      val = 1;
end
end

function side = fc_region_side_from_name_label(name,label,hasSignedLR)
side = '';
try
    s = strtrim(char(name));
    s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
    tok = regexp(s,'^\s*([LR])[_\-\s]+','tokens','once');
    if ~isempty(tok)
        side = upper(tok{1});
        return;
    end
catch
end
try
    if hasSignedLR
        if double(label) < 0
            side = 'L';
        elseif double(label) > 0
            side = 'R';
        end
    end
catch
end
end

function [TSmerge,namesMerge,labelsMerge,groups,order] = fc_merge_lr_timecourses(meanTS,names0,labels0)
n = numel(labels0);
keys = cell(n,1);
stems = cell(n,1);
absLabs = zeros(n,1);
for ii = 1:n
    [keys{ii},stems{ii},absLabs(ii)] = fc_region_merge_key(names0{ii},labels0(ii));
end

uniqueKeys = {};
groups = {};
for ii = 1:n
    hit = find(strcmp(uniqueKeys,keys{ii}),1,'first');
    if isempty(hit)
        uniqueKeys{end+1,1} = keys{ii}; %#ok<AGROW>
        groups{end+1,1} = ii; %#ok<AGROW>
    else
        groups{hit}(end+1) = ii;
    end
end

nG = numel(groups);
TSmerge = zeros(size(meanTS,1),nG);
namesMerge = cell(nG,1);
labelsMerge = zeros(nG,1);
order = zeros(nG,1);

for gg = 1:nG
    idx = groups{gg};
    X = double(meanTS(:,idx));
    good = isfinite(X);
    X(~good) = 0;
    cnt = sum(good,2);
    TSmerge(:,gg) = sum(X,2) ./ max(1,cnt);
    TSmerge(cnt == 0,gg) = 0;
    order(gg) = idx(1);
    labelsMerge(gg) = absLabs(idx(1));
    namesMerge{gg} = sprintf('%s [%g]',stems{idx(1)},labelsMerge(gg));
end
end

function [key,stem,absLab] = fc_region_merge_key(name,label)
absLab = abs(round(double(label)));
stem = fc_region_fullname_no_lr(name);
stem = regexprep(stem,'\s*\[[^\]]*\]\s*$','');
stem = strtrim(stem);
if isempty(stem)
    stem = sprintf('ROI_%g',absLab);
end
key = lower(regexprep(stem,'[^a-zA-Z0-9]+',''));
if isempty(key)
    key = sprintf('roi%g',absLab);
end
end

function s = fc_region_fullname_no_lr(name)
s = strtrim(char(name));
s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
s = regexprep(s,'^\s*-?\d+\s*','');
s = regexprep(s,'^\s*[LR][_\-\s]+','');
s = strrep(s,'_',' ');
s = regexprep(s,'\s+',' ');
s = strtrim(s);
end

function ts = fc_display_ts_for_index(res,meta,dispIdx)
try
    dispIdx = max(1,min(numel(meta.groups),round(dispIdx)));
    idx = meta.groups{dispIdx};
    X = double(res.meanTS(:,idx));
    good = isfinite(X);
    X(~good) = 0;
    cnt = sum(good,2);
    ts = sum(X,2) ./ max(1,cnt);
    ts(cnt == 0) = 0;
catch
    ts = zeros(size(res.meanTS,1),1);
end
end

function dispIdx = fc_display_index_from_raw_label(res,meta,rawLabel)
dispIdx = [];
try
    rawIdx = find(round(double(res.labels(:))) == round(double(rawLabel)),1,'first');
    if isempty(rawIdx)
        rawIdx = find(abs(round(double(res.labels(:)))) == abs(round(double(rawLabel))),1,'first');
    end
    if isempty(rawIdx), return; end
    for ii = 1:numel(meta.groups)
        if any(meta.groups{ii} == rawIdx)
            dispIdx = ii;
            return;
        end
    end
catch
    dispIdx = [];
end
end

function valsRaw = fc_display_values_to_raw(res,meta,valsDisplay)
valsRaw = nan(numel(res.labels),1);
try
    valsDisplay = double(valsDisplay(:));
    for ii = 1:min(numel(valsDisplay),numel(meta.groups))
        idx = meta.groups{ii};
        idx = idx(idx >= 1 & idx <= numel(valsRaw));
        valsRaw(idx) = valsDisplay(ii);
    end
catch
end
end

function labelsDisplay = fc_display_labels_from_meta(meta,res,order)
try
    labelsDisplay = meta.displayLabels(:);
catch
    labelsDisplay = res.labels(order);
end
end

function name = fc_roi_name(label,opts)
name = sprintf('ROI_%03d',label);
try
    T = opts.roiNameTable;
    if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
        idx = find(double(T.labels(:)) == double(label),1,'first');
        if isempty(idx)
            idx = find(abs(double(T.labels(:))) == abs(double(label)),1,'first');
        end
        if ~isempty(idx) && idx <= numel(T.names)
            nm = char(T.names{idx});
            if ~isempty(strtrim(nm)), name = sprintf('%s [%g]',nm,label); return; end
        end
    end
    if iscell(opts.roiNames) && label >= 1 && label <= numel(opts.roiNames)
        if ~isempty(opts.roiNames{label}), name = sprintf('%s [%g]',char(opts.roiNames{label}),label); end
    end
catch
end
end

function idxT = fc_time_idx(TR,T,t0,t1)
if ~isfinite(TR) || TR <= 0, TR = 1; end
sec = (0:T-1) * TR;
idxT = find(sec >= t0 & sec <= t1);
if isempty(idxT), idxT = 1:T; end
end

function s = fc_flip_underlay_in_state(s,mode)
try
    if ~isempty(s.loadedUnderlay)
        if strcmpi(mode,'lr')
            s.loadedUnderlay = s.loadedUnderlay(:,end:-1:1,:);
        else
            s.loadedUnderlay = s.loadedUnderlay(end:-1:1,:,:);
        end
    end
    for ii = 1:s.nSub
        if ~isempty(s.subjects(ii).anat)
            if strcmpi(mode,'lr')
                s.subjects(ii).anat = s.subjects(ii).anat(:,end:-1:1,:);
            else
                s.subjects(ii).anat = s.subjects(ii).anat(end:-1:1,:,:);
            end
        end
    end
catch
end
end

function rgb = fc_get_underlay(s)
subj = s.subjects(s.currentSubject);
I4 = subj.I4;
meanImg = squeeze(mean(I4,4));
medImg  = fc_fast_median_time(I4);

switch lower(s.underlayMode)
    case 'median'
        rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
    case 'mean'
        rgb = fc_underlay_to_rgb(meanImg(:,:,s.slice),s,false);
    case 'scm'
        rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
    case 'anat'
        if ~isempty(subj.anat)
            zUse = max(1,min(size(subj.anat,3),s.slice));
            if isfield(subj,'anatIsDisplayReady') && subj.anatIsDisplayReady
                rgb = fc_display_ready_rgb(subj.anat(:,:,zUse));
            else
                rgb = fc_underlay_to_rgb(subj.anat(:,:,zUse),s,false);
            end
        else
            rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
        end
    case 'atlas'
        if ~isempty(subj.roiAtlas)
            a = double(subj.roiAtlas(:,:,s.slice));
            rgb = fc_map_rgb(a,jet(256),[0 max(1,max(a(:)))]);
        else
            rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
        end
    case 'loaded'
        U = s.loadedUnderlay;
        if isempty(U)
            rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
        elseif s.loadedUnderlayIsRGB
            rgb = single(U);
            if max(rgb(:)) > 1, rgb = rgb ./ 255; end
            rgb = min(max(rgb,0),1);
        elseif isfield(s,'loadedUnderlayDisplayReady') && s.loadedUnderlayDisplayReady
            if ndims(U) == 2, rgb = fc_display_ready_rgb(U);
            else, zUse = max(1,min(size(U,3),s.slice)); rgb = fc_display_ready_rgb(U(:,:,zUse)); end
        elseif ndims(U) == 2
            rgb = fc_underlay_to_rgb(U,s,false);
        else
            zUse = max(1,min(size(U,3),s.slice));
            rgb = fc_underlay_to_rgb(U(:,:,zUse),s,false);
        end
    otherwise
        rgb = fc_underlay_to_rgb(medImg(:,:,s.slice),s,false);
end
end

function medImg = fc_fast_median_time(I4)
T = size(I4,4);
if T <= 600
    medImg = squeeze(median(I4,4));
else
    idx = round(linspace(1,T,600));
    medImg = squeeze(median(I4(:,:,:,idx),4));
end
if ndims(medImg)==2, medImg = reshape(medImg,size(I4,1),size(I4,2),size(I4,3)); end
end

function rgb = fc_display_ready_rgb(U)
U = squeeze(U);
if ndims(U) == 3 && size(U,3) == 3
    rgb = single(U);
    if max(rgb(:)) > 1, rgb = rgb ./ 255; end
    rgb = min(max(rgb,0),1);
    return;
end
U = double(U); U(~isfinite(U)) = 0;
mx = max(U(:)); mn = min(U(:));
if mx > 1 || mn < 0
    if mx > mn, U = (U - mn) ./ max(eps,mx - mn); else, U = zeros(size(U)); end
end
U = min(max(U,0),1);
rgb = repmat(single(U),[1 1 3]);
end

function rgb = fc_underlay_to_rgb(U,s,isColor)
if nargin < 3, isColor = false; end
U = squeeze(U);
if isColor || (ndims(U)==3 && size(U,3)==3)
    rgb = double(U);
    if max(rgb(:)) > 1, rgb = rgb ./ 255; end
    rgb = min(max(rgb,0),1);
    return;
end
U = double(U); U(~isfinite(U)) = 0;
modeVal = 5; brightness = -0.04; contrast = 1.10; gammaVal = 0.95; logGain = 2.0; sharp = 0.35; vsz = 18; vlv = 35;
try
    if isfield(s,'underlayViewMode'), modeVal = s.underlayViewMode; end
    if isfield(s,'underlayBrightness'), brightness = s.underlayBrightness; end
    if isfield(s,'underlayContrast'), contrast = s.underlayContrast; end
    if isfield(s,'underlayGamma'), gammaVal = s.underlayGamma; end
    if isfield(s,'underlayLogGain'), logGain = s.underlayLogGain; end
    if isfield(s,'underlaySharpness'), sharp = s.underlaySharpness; end
    if isfield(s,'underlayVesselSize'), vsz = s.underlayVesselSize; end
    if isfield(s,'underlayVesselLev'), vlv = s.underlayVesselLev; end
catch
end
switch modeVal
    case 1
        U01 = fc_mat2gray_safe(U);
    case 3
        U01 = fc_clip01_percentile(U,0.5,99.5);
    case 4
        U01 = fc_clip01_percentile(U,0.5,99.5);
        U01 = fc_vessel_enhance_simple(U01,vsz,vlv);
        U01 = fc_clip01_percentile(U01,0.5,99.5);
    otherwise
        Upos = U;
        minU = min(Upos(:));
        Upos = Upos - minU;
        med = median(Upos(isfinite(Upos) & Upos > 0));
        if isempty(med) || ~isfinite(med) || med <= 0
            med = fc_prctile(Upos(:),50);
        end
        if ~isfinite(med) || med <= 0, med = max(eps,mean(Upos(:))); end
        Ulog = log1p(max(0,Upos) ./ max(eps,med) * logGain);
        U01 = fc_clip01_percentile(Ulog,0.5,99.7);
        if sharp > 0
            U01 = fc_sharpen2d(U01,sharp);
            U01 = min(max(U01,0),1);
        end
end
U01 = U01 .* contrast + brightness;
U01 = min(max(U01,0),1);
if ~isfinite(gammaVal) || gammaVal <= 0, gammaVal = 1; end
U01 = U01 .^ gammaVal;
U01 = min(max(U01,0),1);
rgb = repmat(single(U01),[1 1 3]);
end

function S = fc_sharpen2d(A,amount)
A = double(A);
try
    h = ones(3,3)/9;
    blur = filter2(h,A,'same');
catch
    blur = conv2(A,ones(3,3)/9,'same');
end
S = A + amount*(A - blur);
end

function U = fc_mat2gray_safe(A)
A = double(A); A(~isfinite(A)) = 0;
mn = min(A(:)); mx = max(A(:));
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    U = zeros(size(A));
else
    U = (A - mn) ./ max(eps,mx - mn);
    U = min(max(U,0),1);
end
end

function U = fc_clip01_percentile(A,pLow,pHigh)
A = double(A); A(~isfinite(A)) = 0;
v = A(:); v = v(isfinite(v));
if isempty(v), U = zeros(size(A)); return; end
lo = fc_prctile(v,pLow); hi = fc_prctile(v,pHigh);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    U = fc_mat2gray_safe(A); return;
end
U = A; U(U < lo) = lo; U(U > hi) = hi;
U = (U - lo) ./ max(eps,hi - lo);
U = min(max(U,0),1);
end

function U = fc_vessel_enhance_simple(U01,conectSize,conectLev)
U01 = min(max(double(U01),0),1);
if nargin < 2 || isempty(conectSize), conectSize = 18; end
if nargin < 3 || isempty(conectLev), conectLev = 35; end
if conectSize <= 0, U = U01; return; end
lev01 = conectLev ./ 500; lev01 = min(max(lev01,0),1); lev01 = lev01.^0.75;
thrMask = U01 > lev01;
r = max(1,round(conectSize)); r = min(r,300);
[x,y] = meshgrid(-r:r,-r:r); m = double((x.^2 + y.^2) <= r.^2); m = m ./ max(eps,sum(m(:)));
try, D = filter2(m,double(thrMask),'same'); catch, D = conv2(double(thrMask),m,'same'); end
D = min(max(D,0),1);
strength = 0.8 + 1.6 * min(1,r/120);
U = U01 .* (1 + strength .* D.^2) + 0.15 .* D.^2;
U = min(max(U,0),1);
end

function atlasS = fc_atlas_slice(s)
subj = s.subjects(s.currentSubject);
atlasS = [];
if ~isempty(subj.roiAtlas)
    atlasS = double(subj.roiAtlas(:,:,s.slice));
end
end

function [rgb,A] = fc_line_overlay(mask,labels,col)
edge = false(size(mask));
edge(1:end-1,:) = edge(1:end-1,:) | labels(1:end-1,:) ~= labels(2:end,:);
edge(:,1:end-1) = edge(:,1:end-1) | labels(:,1:end-1) ~= labels(:,2:end);
edge = edge & mask;
rgb = nan(size(mask,1),size(mask,2),3);
for k = 1:3
    tmp = zeros(size(mask),'single'); tmp(edge) = col(k); rgb(:,:,k) = tmp;
end
A = 0.90 * double(edge);
end

function rgb = fc_map_rgb(M,cmap,clim)
M = double(M); cmin = clim(1); cmax = clim(2);
if ~isfinite(cmin) || ~isfinite(cmax) || cmax <= cmin
    cmin = min(M(:)); cmax = max(M(:)); if cmax <= cmin, cmax = cmin + 1; end
end
u = (M - cmin) / (cmax - cmin); u = max(0,min(1,u));
idx = 1 + floor(u * (size(cmap,1)-1)); idx(~isfinite(idx)) = 1; idx = max(1,min(size(cmap,1),idx));
rgb = zeros(size(M,1),size(M,2),3,'single');
for k = 1:3
    tmp = cmap(idx,k); rgb(:,:,k) = reshape(single(tmp),size(M,1),size(M,2));
end
end

function cmap = fc_get_cmap(name,n)
if nargin < 2, n = 256; end
name = lower(strtrim(name));
switch name
    case 'winter'
        cmap = winter(n);
    case 'hot'
        cmap = hot(n);
    case 'jet'
        cmap = jet(n);
    case 'gray'
        cmap = gray(n);
    case 'parula'
        try, cmap = parula(n); catch, cmap = jet(n); end
    otherwise
        cmap = fc_bwr(n);
end
end

function fc_colorbar_legend(ax,cmap,clim,labelStr,C)
% Robust colorbar legend.
% Fixes duplicate tick errors when zero is at the color limit edge.
try
    cla(ax);
catch
end

if nargin < 2 || isempty(cmap)
    cmap = jet(256);
end
if nargin < 3 || isempty(clim) || numel(clim) < 2 || ~all(isfinite(clim)) || clim(2) <= clim(1)
    clim = [-1 1];
end
if nargin < 4 || isempty(labelStr)
    labelStr = '';
end

nC = size(cmap,1);
if nC < 2
    cmap = jet(256);
    nC = size(cmap,1);
end

pos = get(ax,'Position');
isVertical = false;
try
    isVertical = numel(pos) >= 4 && pos(4) > pos(3) * 2;
catch
end

zeroFrac = (0 - clim(1)) ./ max(eps,(clim(2)-clim(1)));
zeroFrac = max(0,min(1,zeroFrac));

if isVertical
    img = reshape(nC:-1:1,[],1);
    imagesc(ax,img);
    colormap(ax,cmap);
    hold(ax,'on');

    y0 = round(1 + (1-zeroFrac) .* (nC - 1));
    y0 = max(1,min(nC,y0));
    try, line(ax,[0.55 1.45],[y0 y0],'Color',[1 1 1],'LineWidth',1.8); catch, end

    tickVals = [1 y0 nC];
    tickLabs = {num2str(clim(2),'%.2g'),'0',num2str(clim(1),'%.2g')};
    [tickVals,ia] = unique(tickVals,'stable');
    tickLabs = tickLabs(ia);
    [tickVals,ord] = sort(tickVals,'ascend');
    tickLabs = tickLabs(ord);

    set(ax, ...
        'YDir','normal', ...
        'XTick',[], ...
        'YTick',tickVals, ...
        'YTickLabel',tickLabs, ...
        'XColor',C.fg, ...
        'YColor',C.fg, ...
        'Color',C.bgPane, ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'LineWidth',1.1);

    try
        ylabel(ax,labelStr,'Color',C.fg,'FontSize',11,'FontWeight','bold','Interpreter','none');
    catch
    end
    hold(ax,'off');
else
    img = reshape(1:nC,1,[]);
    imagesc(ax,img);
    colormap(ax,cmap);
    hold(ax,'on');

    x0 = round(1 + zeroFrac .* (nC - 1));
    x0 = max(1,min(nC,x0));
    try, line(ax,[x0 x0],[0.55 1.45],'Color',[1 1 1],'LineWidth',1.8); catch, end

    tickVals = [1 x0 nC];
    tickLabs = {num2str(clim(1),'%.2g'),'0',num2str(clim(2),'%.2g')};
    [tickVals,ia] = unique(tickVals,'stable');
    tickLabs = tickLabs(ia);
    [tickVals,ord] = sort(tickVals,'ascend');
    tickLabs = tickLabs(ord);

    set(ax, ...
        'YTick',[], ...
        'XTick',tickVals, ...
        'XTickLabel',tickLabs, ...
        'XColor',C.fg, ...
        'YColor',C.fg, ...
        'Color',C.bgPane, ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'LineWidth',1.1);

    try
        title(ax,labelStr,'Color',C.fg,'FontSize',11,'FontWeight','bold','Interpreter','none');
    catch
    end
    hold(ax,'off');
end
end

function cmap = fc_bwr(n)
if nargin < 1, n = 256; end
n1 = floor(n/2); n2 = n - n1;
b = [0.00 0.25 0.95]; w = [1.00 1.00 1.00]; r = [0.95 0.20 0.20];
c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];
cmap = [c1; c2];
end

function [idx,vals] = fc_rank_vector(r,topN,mode,names)
if nargin < 4, names = {}; end
r = double(r(:)'); valid = find(isfinite(r));
if isempty(valid), idx = []; vals = []; return; end
switch lower(mode)
    case 'positive'
        [~,ord] = sort(r(valid),'descend');
    case 'negative'
        [~,ord] = sort(r(valid),'ascend');
    case 'label'
        if isempty(names)
            ord = 1:numel(valid);
        else
            [~,ord] = sort(lower(names(valid)));
        end
    otherwise
        [~,ord] = sort(abs(r(valid)),'descend');
end
idx = valid(ord); idx = idx(1:min(numel(idx),topN)); vals = r(idx);
end

function T = fc_compare_export_table(s,res)
T = [];
[M,names,order,meta] = fc_current_matrix(s,res);
sel = fc_clip(s.compareROI,1,numel(names));
vals = M(sel,:)'; labels = fc_display_labels_from_meta(meta,res,order);
T.selectedName = names{sel}; T.labels = labels(:); T.names = names(:); T.values = vals(:);
end

function fc_write_matrix_csv(fileName,M,names)
fid = fopen(fileName,'w'); if fid < 0, error('Could not open CSV file.'); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'ROI');
for j = 1:numel(names), fprintf(fid,',%s',fc_csv(names{j})); end
fprintf(fid,'\n');
for i = 1:size(M,1)
    fprintf(fid,'%s',fc_csv(names{i}));
    for j = 1:size(M,2), fprintf(fid,',%.10g',M(i,j)); end
    fprintf(fid,'\n');
end
end

function fc_write_compare_csv(fileName,T)
fid = fopen(fileName,'w'); if fid < 0, error('Could not open compare CSV.'); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Selected,%s\n',fc_csv(T.selectedName));
fprintf(fid,'Label,Region,Value\n');
for i = 1:numel(T.values), fprintf(fid,'%.10g,%s,%.10g\n',T.labels(i),fc_csv(T.names{i}),T.values(i)); end
end

function s = fc_csv(s0)
s = char(s0); s = strrep(s,'"','""'); s = ['"' s '"'];
end

function fc_save_axis(ax,fig,fileName)
try
    tmp = figure('Visible','off');
    ax2 = copyobj(ax,tmp);
    set(ax2,'Units','normalized','Position',[0.08 0.08 0.84 0.84]);
    set(tmp,'Color',get(fig,'Color'),'Position',[100 100 1000 800]);
    saveas(tmp,fileName);
    close(tmp);
catch
end
end

function stp = fc_slider_step(Z)
if Z <= 1, stp = [1 1]; else, stp = [1/(Z-1) min(10/(Z-1),1)]; end
end

function v = fc_clip(v,lo,hi)
v = max(lo,min(hi,v));
end

function z = fc_z(x)
x = double(x(:)); sd = std(x);
if ~isfinite(sd) || sd <= 0, z = zeros(size(x)); else, z = (x - mean(x)) / sd; end
end

function r = fc_corr_scalar(x,y)
x = double(x(:)); y = double(y(:)); x = x - mean(x); y = y - mean(y);
den = sqrt(sum(x.^2) * sum(y.^2));
if den <= 0 || ~isfinite(den), r = 0; else, r = sum(x.*y) / den; end
end

function Z = fc_atanh_safe(M)
Z = double(M); Z = max(-0.999999,min(0.999999,Z)); Z = atanh(Z);
end

function tMin = fc_result_time_min(res,TRfallback)
tMin = [];
try
    if isfield(res,'timeMin') && ~isempty(res.timeMin)
        tMin = double(res.timeMin(:));
    elseif isfield(res,'timeSec') && ~isempty(res.timeSec)
        tMin = double(res.timeSec(:)) ./ 60;
    elseif isfield(res,'tSec') && ~isempty(res.tSec)
        tMin = double(res.tSec(:)) ./ 60;
    elseif isfield(res,'tMin') && ~isempty(res.tMin)
        tMin = double(res.tMin(:));
    end
catch
    tMin = [];
end

if isempty(tMin) || any(~isfinite(tMin))
    try
        nT = size(res.meanTS,1);
    catch
        nT = 0;
    end
    if nargin < 2 || isempty(TRfallback) || ~isfinite(TRfallback) || TRfallback <= 0
        TRfallback = 1;
    end
    tMin = ((0:nT-1)' .* double(TRfallback)) ./ 60;
end
end

function tMin = fc_extract_seg_time_min(Seg,nT,TRfallback)
tMin = [];
if nargin < 3 || isempty(TRfallback) || ~isfinite(TRfallback) || TRfallback <= 0
    TRfallback = 1;
end

minFields = {'timeMin','tMin','minutes','timeMinutes','time_min','t_min','TimeMin'};
secFields = {'timeSec','tSec','seconds','timeSeconds','time_s','t_s','TimeSec','time','t'};

for ii = 1:numel(minFields)
    fn = minFields{ii};
    try
        if isfield(Seg,fn) && ~isempty(Seg.(fn))
            v = double(Seg.(fn)(:));
            if numel(v) == nT && all(isfinite(v))
                tMin = v;
                return;
            end
        end
    catch
    end
end

for ii = 1:numel(secFields)
    fn = secFields{ii};
    try
        if isfield(Seg,fn) && ~isempty(Seg.(fn))
            v = double(Seg.(fn)(:));
            if numel(v) == nT && all(isfinite(v))
                if strcmpi(fn,'t') || strcmpi(fn,'time')
                    if max(v) > max(5,2*((nT-1)*TRfallback/60))
                        tMin = v ./ 60;
                    else
                        tMin = v;
                    end
                else
                    tMin = v ./ 60;
                end
                return;
            end
        end
    catch
    end
end

try
    if isfield(Seg,'time') && isstruct(Seg.time)
        if isfield(Seg.time,'min') && numel(Seg.time.min) == nT
            tMin = double(Seg.time.min(:));
            return;
        elseif isfield(Seg.time,'sec') && numel(Seg.time.sec) == nT
            tMin = double(Seg.time.sec(:)) ./ 60;
            return;
        end
    end
catch
end

tMin = ((0:nT-1)' .* double(TRfallback)) ./ 60;
end

function x = fc_prctile(a,p)
a = double(a(:)); a = a(isfinite(a));
if isempty(a), x = NaN; return; end
a = sort(a);
if numel(a)==1, x = a; return; end
t = (p/100) * (numel(a)-1) + 1; i1 = floor(t); i2 = ceil(t);
if i1 == i2, x = a(i1); else, w = t - i1; x = (1-w)*a(i1) + w*a(i2); end
end

function fc_ax(ax,C)
try
    set(ax,'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim,'FontSize',10, ...
        'TickLabelInterpreter','none');
catch
    set(ax,'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim,'FontSize',10);
end
end

function fc_nodata(ax,titleStr,C)
cla(ax);
text(ax,0.5,0.5,'No data','HorizontalAlignment','center','Color',C.fg,'FontSize',12,'FontWeight','bold','FontSize',14);
fc_ax(ax,C); title(ax,titleStr,'Color',C.fg,'Interpreter','none');
set(ax,'XTick',[],'YTick',[]);
end

function lst = fc_underlay_list(st)
subj = st.subjects(st.currentSubject);
lst = {'SCM log-median underlay','Mean functional','Median functional'};
if ~isempty(subj.anat), lst{end+1} = 'Mask Editor / provided anatomy'; end
if ~isempty(st.loadedUnderlay), lst{end+1} = 'Loaded histology / underlay'; end
if ~isempty(subj.roiAtlas), lst{end+1} = 'ROI labels as underlay'; end
end

function val = fc_underlay_value(st,lst)
if nargin < 2 || isempty(lst), lst = fc_underlay_list(st); end
if ischar(lst), lst = cellstr(lst); end
val = 1;
modeNow = lower(strtrim(st.underlayMode));
for i = 1:numel(lst)
    item = lower(strtrim(lst{i}));
    switch modeNow
        case 'scm'
            if ~isempty(strfind(item,'scm')) || ~isempty(strfind(item,'log')), val = i; return; end
        case 'mean'
            if ~isempty(strfind(item,'mean')), val = i; return; end
        case 'median'
            if ~isempty(strfind(item,'median')) && isempty(strfind(item,'log')), val = i; return; end
        case 'anat'
            if ~isempty(strfind(item,'anatomy')) || ~isempty(strfind(item,'mask editor')) || ~isempty(strfind(item,'provided')), val = i; return; end
        case 'loaded'
            if ~isempty(strfind(item,'loaded')) || ~isempty(strfind(item,'histology')), val = i; return; end
        case 'atlas'
            if ~isempty(strfind(item,'labels')), val = i; return; end
    end
end
val = 1;
end

function out = fc_short_list(c,n)
out = c;
for i = 1:numel(out)
    s = char(out{i});
    if numel(s) > n, s = [s(1:max(1,n-3)) '...']; end
    out{i} = s;
end
end

function out = fc_abbrev_list(c,n,showHemisphere)
if nargin < 2 || isempty(n), n = 12; end
if nargin < 3 || isempty(showHemisphere), showHemisphere = true; end
out = c;
for i = 1:numel(out)
    out{i} = fc_roi_abbrev(out{i},n,showHemisphere);
end
end

function ab = fc_roi_abbrev(name,n,showHemisphere)
if nargin < 2 || isempty(n), n = 12; end
if nargin < 3 || isempty(showHemisphere), showHemisphere = true; end
s = strtrim(char(name));
s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
s = regexprep(s,'^\s*-?\d+\s*','');
s = strtrim(s);
hemi = '';
stem = s;
tok = regexp(s,'^([LR])[_\-\s]+(.+)$','tokens','once');
if ~isempty(tok)
    hemi = upper(strtrim(tok{1}));
    stem = strtrim(tok{2});
end
stem = strrep(stem,'_',' ');
stem = regexprep(stem,'\s+',' ');
if showHemisphere && ~isempty(hemi)
    ab = [hemi ' ' stem];
else
    ab = stem;
end
if isempty(strtrim(ab)), ab = s; end
if numel(ab) > n
    ab = [ab(1:max(1,n-3)) '...'];
end
end

function out = fc_abbrev_only_list(c,n)
if nargin < 2 || isempty(n), n = 12; end
out = c;
for i = 1:numel(out)
    out{i} = fc_roi_abbrev_only(out{i},n);
end
end

function ab = fc_roi_abbrev_only(name,n)
if nargin < 2 || isempty(n), n = 12; end
s = strtrim(char(name));
s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
s = regexprep(s,'^\s*-?\d+\s*','');
s = strtrim(s);
tok = regexp(s,'^([LR])[_\-\s]+(.+)$','tokens','once');
if ~isempty(tok)
    ab = strtrim(tok{2});
else
    ab = s;
end
ab = strrep(ab,'_',' ');
ab = regexprep(ab,'\s+',' ');
if isempty(strtrim(ab)), ab = s; end
if numel(ab) > n
    ab = [ab(1:max(1,n-3)) '...'];
end
end

function val = fc_epoch_mode_to_popup_value(mode)
try, mode = lower(strtrim(char(mode))); catch, mode = 'whole'; end
switch mode
    case 'pre',    val = 2;
    case 'during', val = 3;
    case 'post',   val = 4;
    otherwise,       val = 1;
end
end

function label = fc_epoch_label(s)
mode = 'whole';
try, if isfield(s,'fcEpochMode') && ~isempty(s.fcEpochMode), mode = lower(strtrim(char(s.fcEpochMode))); end, catch, end
useWin = false;
try, if isfield(s,'fcUseEpochWin') && ~isempty(s.fcUseEpochWin), useWin = logical(s.fcUseEpochWin); end, catch, end
win = 3;
try, if isfield(s,'fcEpochWinMin') && isfinite(s.fcEpochWinMin), win = double(s.fcEpochWinMin); end, catch, end
switch mode
    case 'pre'
        if useWin, label = sprintf('Pre-injection last %.2f min',win); else, label = 'Pre-injection full period'; end
    case 'during'
        if useWin, label = sprintf('During injection first %.2f min',win); else, label = 'During injection full period'; end
    case 'post'
        if useWin, label = sprintf('Post-injection first %.2f min',win); else, label = 'Post-injection full remaining period'; end
    otherwise
        label = 'Whole recording';
end
end

function [t0,t1,epName] = fc_epoch_window_sec(s,TR,nT)
if nargin < 2 || isempty(TR) || ~isfinite(TR) || TR <= 0, TR = 1; end
if nargin < 3 || isempty(nT) || ~isfinite(nT), nT = inf; end
totalSec = inf;
try
    if isfinite(nT), totalSec = max(0,(double(nT)-1).*double(TR)); end
catch
    totalSec = inf;
end
mode = 'whole';
try, if isfield(s,'fcEpochMode') && ~isempty(s.fcEpochMode), mode = lower(strtrim(char(s.fcEpochMode))); end, catch, end
inj0 = 14; inj1 = 15; win = 3;
try, if isfield(s,'fcInjStartMin') && isfinite(s.fcInjStartMin), inj0 = double(s.fcInjStartMin); end, catch, end
try, if isfield(s,'fcInjEndMin') && isfinite(s.fcInjEndMin), inj1 = double(s.fcInjEndMin); end, catch, end
try, if isfield(s,'fcEpochWinMin') && isfinite(s.fcEpochWinMin) && s.fcEpochWinMin > 0, win = double(s.fcEpochWinMin); end, catch, end
useWin = false;
try, if isfield(s,'fcUseEpochWin') && ~isempty(s.fcUseEpochWin), useWin = logical(s.fcUseEpochWin); end, catch, useWin = false; end
inj0 = max(0,inj0);
inj1 = max(inj0,inj1);
win = max(0.01,win);
switch mode
    case 'pre'
        if useWin
            t0 = max(0,(inj0-win).*60);
            t1 = inj0.*60;
            epName = sprintf('Pre-injection last %.2f min',win);
        else
            t0 = 0;
            t1 = inj0.*60;
            epName = 'Pre-injection full period';
        end
    case 'during'
        t0 = inj0.*60;
        if useWin
            t1 = min(inj1,inj0+win).*60;
            if t1 <= t0, t1 = (inj0+win).*60; end
            epName = sprintf('During injection first %.2f min',win);
        else
            t1 = inj1.*60;
            if t1 <= t0, t1 = inf; end
            epName = 'During injection full period';
        end
    case 'post'
        t0 = inj1.*60;
        if useWin
            t1 = (inj1+win).*60;
            epName = sprintf('Post-injection first %.2f min',win);
        else
            t1 = inf;
            epName = 'Post-injection full remaining period';
        end
    otherwise
        t0 = 0;
        t1 = inf;
        epName = 'Whole recording';
end
if isfinite(totalSec)
    t0 = max(0,min(t0,totalSec));
    if isfinite(t1), t1 = max(t0,min(t1,totalSec)); end
end
end

function res = fc_apply_epoch_to_roi_result(res,s)
try
    if ~isfield(res,'meanTSFull') || isempty(res.meanTSFull)
        res.meanTSFull = res.meanTS;
    end
    baseTS = double(res.meanTSFull);
    nT = size(baseTS,1);
    TR = 1;
    if isfield(res,'TR') && isfinite(res.TR) && res.TR > 0, TR = double(res.TR); end
    if isfield(res,'timeMinFull') && ~isempty(res.timeMinFull) && numel(res.timeMinFull)==nT
        tMinFull = double(res.timeMinFull(:));
    elseif isfield(res,'timeMin') && ~isempty(res.timeMin) && numel(res.timeMin)==nT
        tMinFull = double(res.timeMin(:));
    else
        tMinFull = ((0:nT-1)' .* TR) ./ 60;
    end
    [t0,t1,epName] = fc_epoch_window_sec(s,TR,nT);
    tSec = tMinFull(:).*60;
    idx = find(tSec >= t0 & tSec <= t1);
    if numel(idx) < 3
        idx = (1:nT)';
        epName = [epName ' - fallback whole recording, fewer than 3 points in selected window'];
    end
    meanTS = baseTS(idx,:);
    for kk = 1:size(meanTS,2)
        x = meanTS(:,kk);
        bad = ~isfinite(x);
        if any(bad)
            good = x(isfinite(x));
            if isempty(good), x(bad) = 0; else, x(bad) = mean(good); end
            meanTS(:,kk) = x;
        end
    end
    res.meanTS = meanTS;
    res.M = fc_corr_matrix(meanTS);
    res.timeIdx = idx(:);
    res.timeMin = tMinFull(idx(:));
    res.timeSec = res.timeMin(:).*60;
    res.timeMinFull = tMinFull(:);
    res.timeSecFull = tMinFull(:).*60;
    res.epochName = epName;
    res.epochWindowSec = [t0 t1];
catch
    % Keep original result if anything unexpected happens.
end
end

function tickIdx = fc_matrix_tick_indices(n)
% Default display: show all labels. User can still choose Auto/Every N.
if nargin < 1 || isempty(n) || n <= 0
    tickIdx = [];
    return;
end
mode = 'all';
try
    h = findobj(0,'Type','uicontrol','Tag','FC_MatrixTickMode');
    if ~isempty(h)
        val = get(h(1),'Value');
        modes = {'auto','all','every2','every3','every5','every10'};
        val = max(1,min(numel(modes),round(double(val))));
        mode = modes{val};
    end
catch
    mode = 'all';
end
switch lower(mode)
    case 'auto'
        if n <= 90
            tickIdx = 1:n;
        elseif n <= 140
            tickIdx = 1:2:n;
        elseif n <= 220
            tickIdx = 1:3:n;
        else
            tickIdx = 1:max(4,ceil(n/60)):n;
        end
    case 'every2'
        tickIdx = 1:2:n;
    case 'every3'
        tickIdx = 1:3:n;
    case 'every5'
        tickIdx = 1:5:n;
    case 'every10'
        tickIdx = 1:10:n;
    otherwise
        tickIdx = 1:n;
end
if isempty(tickIdx), tickIdx = 1:n; end
end

function fc_set_matrix_ticks(ax,M,names,meta,showHemisphere,C)
if nargin < 5 || isempty(showHemisphere), showHemisphere = true; end
nY = size(M,1);
nX = size(M,2);
namesY = names;
namesX = names;
try
    if isfield(meta,'isRectangular') && meta.isRectangular
        namesY = meta.namesY;
        namesX = meta.namesX;
        showHemisphere = false;
    end
catch
end
try, namesY = cellstr(namesY(:)); catch, namesY = {'n/a'}; end
try, namesX = cellstr(namesX(:)); catch, namesX = {'n/a'}; end
tickY = fc_matrix_tick_indices(nY);
tickX = fc_matrix_tick_indices(nX);
tickY = tickY(tickY >= 1 & tickY <= numel(namesY));
tickX = tickX(tickX >= 1 & tickX <= numel(namesX));
maxN = max(nX,nY);
tickFont = 8.5;
if maxN > 90,  tickFont = 7.5; end
if maxN > 130, tickFont = 6.7; end
if maxN > 220, tickFont = 5.8; end
labelLen = 8;
if maxN <= 80, labelLen = 10; end
try
    set(ax, ...
        'XTick',tickX, ...
        'YTick',tickY, ...
        'XTickLabel',fc_abbrev_list(namesX(tickX),labelLen,showHemisphere), ...
        'YTickLabel',fc_abbrev_list(namesY(tickY),labelLen,showHemisphere), ...
        'TickLength',[0 0], ...
        'FontName',C.font, ...
        'FontSize',tickFont, ...
        'FontWeight','bold', ...
        'TickLabelInterpreter','none');
catch
    set(ax,'XTick',tickX,'YTick',tickY,'FontSize',tickFont,'FontWeight','bold');
end
try, xtickangle(ax,90); catch, end
try
    set(get(ax,'Title'),'FontSize',16,'FontWeight','bold','Color',C.fg);
    set(get(ax,'XLabel'),'FontSize',15,'FontWeight','bold','Color',C.fg);
    set(get(ax,'YLabel'),'FontSize',15,'FontWeight','bold','Color',C.fg);
catch
end
end

function col = fc_pair_color(list,val)
if ischar(list), list = cellstr(list); end
val = max(1,min(numel(list),val));
name = lower(strtrim(list{val}));
switch name
    case 'blue'
        col = [0.20 0.75 1.00];
    case 'orange'
        col = [1.00 0.55 0.20];
    case 'green'
        col = [0.30 0.90 0.45];
    case 'purple'
        col = [0.75 0.55 1.00];
    case 'red'
        col = [1.00 0.35 0.35];
    case 'white'
        col = [0.95 0.95 0.95];
    otherwise
        col = [0.70 0.70 0.74];
end
end

function A2 = fc_fill_empty_hemi_labels(A)
% Disabled intentionally.
% Functional Connectivity must use the true co-registered atlas labels.
% Do not mirror labels, because that creates fake left/right symmetry.
A2 = A;
end

function fc_draw_roi_abbrev_on_map(ax,atlasS,labels,names,C,showHemisphere)
if nargin < 6 || isempty(showHemisphere), showHemisphere = true; end
try
    A = round(double(atlasS));
    labsInSlice = unique(A(:));
    labsInSlice = labsInSlice(isfinite(labsInSlice) & labsInSlice ~= 0);
    labsInSlice = intersect(labsInSlice,round(double(labels(:))));
    if isempty(labsInSlice) || numel(labsInSlice) > 60
        return;
    end
    hold(ax,'on');
    for ii = 1:numel(labsInSlice)
        lab = labsInSlice(ii);
        idx = find(round(double(labels(:))) == round(double(lab)),1,'first');
        if isempty(idx) || idx > numel(names), continue; end
        if fc_is_background_region(lab,names{idx}), continue; end
        [yy,xx] = find(A == round(double(lab)));
        if numel(xx) < 12, continue; end
        x = median(xx); y = median(yy);
        text(ax,x,y,fc_roi_abbrev(names{idx},8,showHemisphere), ...
            'Color',C.fg,'FontName',C.font,'FontSize',8,'FontWeight','bold', ...
            'HorizontalAlignment','center','VerticalAlignment','middle', ...
            'HitTest','off','Clipping','on');
    end
    hold(ax,'off');
catch
end
end

function v = fc_view_mode_to_value(modeVal)
switch modeVal
    case 5, v = 1;
    case 3, v = 2;
    case 4, v = 3;
    otherwise, v = 4;
end
end

function s = fc_short(s)
s = char(s);
if numel(s) > 32, s = [s(1:29) '...']; end
end

function out = fc_join(c)
if isempty(c), out = 'none'; return; end
out = c{1};
for i = 2:numel(c), out = sprintf('%s\n%s',out,c{i}); end
end

function fc_log(opts,msg)
try
    if isfield(opts,'logFcn') && isa(opts.logFcn,'function_handle')
        opts.logFcn(msg);
    end
catch
end
end

function fcBundle = fc_make_group_bundle(s)
% FC_MAKE_GROUP_BUNDLE
% Standardized subject-level FC export for GroupAnalysis.
%
% Important:
%   - Pearson r is stored as R.
%   - Fisher z = atanh(r) is stored as Z.
%   - Group analysis should average/statistically compare Z, not R.

fcBundle = struct();

fcBundle.version = 'FC_GroupBundle_v1';
fcBundle.created = datestr(now);
fcBundle.tag = s.tag;
fcBundle.saveRoot = s.saveRoot;
fcBundle.qcDir = s.qcDir;

fcBundle.settings = struct();
fcBundle.settings.roiMinVox = s.opts.roiMinVox;
fcBundle.settings.roiOrder = s.roiOrder;
fcBundle.settings.analysisStartSec = s.analysisStartSec;
fcBundle.settings.analysisEndSec = s.analysisEndSec;
fcBundle.settings.currentEpoch = s.currentEpoch;
fcBundle.settings.epochName = s.epochs(s.currentEpoch).name;
fcBundle.settings.note = 'Average/statistically compare Fisher Z. Use Pearson R mainly for visual display.';
fcBundle.settings.statsMatrix = 'Z';
fcBundle.settings.statsSpace = 'Fisher z';
fcBundle.settings.displayMatrix = 'R';
fcBundle.settings.displaySpace = 'Pearson r';
fcBundle.settings.regionMode = fc_region_mode_from_state(s);

fcBundle.subjects = struct([]);

for i = 1:s.nSub

    subj = s.subjects(i);

    fcBundle.subjects(i).name = subj.name;
    fcBundle.subjects(i).group = subj.group;
    fcBundle.subjects(i).TR = subj.TR;
    fcBundle.subjects(i).analysisDir = subj.analysisDir;

    fcBundle.subjects(i).hasROI = false;
    fcBundle.subjects(i).epochName = '';
    fcBundle.subjects(i).timeIdx = [];
    fcBundle.subjects(i).labels = [];
    fcBundle.subjects(i).names = {};
    fcBundle.subjects(i).counts = [];
    fcBundle.subjects(i).meanTS = [];
    fcBundle.subjects(i).R = [];
    fcBundle.subjects(i).Z = [];

    % Prefer current epoch result.
    res = [];
    if i <= size(s.roiResults,1) && s.currentEpoch <= size(s.roiResults,2)
        res = s.roiResults{i,s.currentEpoch};
    end

    % Fallback: find any available ROI result for this subject.
    if isempty(res)
        for e = 1:size(s.roiResults,2)
            if ~isempty(s.roiResults{i,e})
                res = s.roiResults{i,e};
                break;
            end
        end
    end

    if isempty(res)
        continue;
    end

    fcBundle.subjects(i).hasROI = true;
    fcBundle.subjects(i).epochName = res.epochName;
    fcBundle.subjects(i).timeIdx = res.timeIdx;
    fcBundle.subjects(i).labels = res.labels;
    fcBundle.subjects(i).names = res.names;
    fcBundle.subjects(i).counts = res.counts;
    fcBundle.subjects(i).meanTS = res.meanTS;
    fcBundle.subjects(i).R = res.M;

    Z = double(res.M);
    Z = max(-0.999999, min(0.999999, Z));
    Z = atanh(Z);

    % The diagonal is self-correlation. Keep R diagonal as 1,
    % but set Z diagonal to 0 so group plots/statistics are cleaner.
    Z(1:size(Z,1)+1:end) = 0;

    fcBundle.subjects(i).Z = Z;
    % HUMOR_REPAIR_SLICE_BUNDLE_EXPORT_20260519
    try
        fcBundle.subjects(i).isStepMotor3D = (isfield(s,'Z') && s.Z > 1);
        fcBundle.subjects(i).nSlices = s.Z;
        fcBundle.subjects(i).sliceResults = HUMOR_FC_build_slice_bundle(s,i,res);
        fcBundle.subjects(i).sliceExportNote = 'sliceResults contain true slice-specific ROI FC matrices.';
    catch ME_sliceExport
        fcBundle.subjects(i).sliceResults = struct([]);
        fcBundle.subjects(i).sliceExportNote = ['Slice export failed: ' ME_sliceExport.message];
    end
    fcBundle.subjects(i).statMatrix = Z;
    fcBundle.subjects(i).statSpace = 'Fisher z';
    fcBundle.subjects(i).displayMatrix = res.M;
    fcBundle.subjects(i).displaySpace = 'Pearson r';

    % Current display-mode matrix for GroupAnalysis convenience.
    try
        [Rdisp,namesDisp,orderDisp,metaDisp] = fc_current_matrix(s,res); %#ok<ASGLU>
        fcBundle.subjects(i).displayRegionMode = fc_region_mode_from_state(s);
        fcBundle.subjects(i).displayNames = namesDisp;
        fcBundle.subjects(i).displayLabels = metaDisp.displayLabels;
        fcBundle.subjects(i).displayGroups = metaDisp.groups;
        fcBundle.subjects(i).displayR = Rdisp;
        Zdisp = max(-0.999999,min(0.999999,double(Rdisp)));
        Zdisp = atanh(Zdisp);
        Zdisp(1:size(Zdisp,1)+1:end) = 0;
        fcBundle.subjects(i).displayZ = Zdisp;
        fcBundle.subjects(i).displayStatMatrix = Zdisp;
        fcBundle.subjects(i).displayStatSpace = 'Fisher z';
        fcBundle.subjects(i).displayMatrix = Rdisp;
        fcBundle.subjects(i).displaySpace = 'Pearson r';
    catch
        fcBundle.subjects(i).displayRegionMode = 'both';
        fcBundle.subjects(i).displayNames = res.names;
        fcBundle.subjects(i).displayLabels = res.labels;
        fcBundle.subjects(i).displayGroups = {};
        fcBundle.subjects(i).displayR = res.M;
        fcBundle.subjects(i).displayZ = Z;
        fcBundle.subjects(i).displayStatMatrix = Z;
        fcBundle.subjects(i).displayStatSpace = 'Fisher z';
        fcBundle.subjects(i).displayMatrix = res.M;
        fcBundle.subjects(i).displaySpace = 'Pearson r';
    end
end

end

function startDir = fc_segmentation_start_dir(subj,opts)
% Prefer the HUMoR segmentation output folder.
startDir = pwd;
try
    if isfield(opts,'stepMotorFolder') && ~isempty(opts.stepMotorFolder) && exist(opts.stepMotorFolder,'dir') == 7
        segDir0 = fullfile(opts.stepMotorFolder,'Segmentation');
        if exist(segDir0,'dir') == 7, startDir = segDir0; return; end
        startDir = opts.stepMotorFolder; return;
    end
catch
end
try
    if isfield(opts,'exportPath') && ~isempty(opts.exportPath)
        segDir = fullfile(opts.exportPath,'Segmentation');
        if exist(segDir,'dir'), startDir = segDir; return; end
    end
catch
end
try
    if isfield(opts,'saveRoot') && ~isempty(opts.saveRoot)
        segDir = fullfile(opts.saveRoot,'Segmentation');
        if exist(segDir,'dir'), startDir = segDir; return; end
    end
catch
end
try
    if isfield(subj,'analysisDir') && ~isempty(subj.analysisDir)
        segDir = fullfile(subj.analysisDir,'Segmentation');
        if exist(segDir,'dir'), startDir = segDir; return; end
        if exist(subj.analysisDir,'dir'), startDir = subj.analysisDir; return; end
    end
catch
end
try
    startDir = fc_start_dir(subj,opts);
catch
end
end

function [res, info, roiAtlas] = fc_read_segmentation_result(fullFile, fallbackTR, opts)
% TRUE-LR Segmentation loader.
% If Seg.labelMap contains signed labels, this loads Seg.Left + Seg.Right
% as separate FC regions: negative labels = left, positive labels = right.
% If no signed label map is present, it falls back to Seg.Both.

res = [];
info = struct();
roiAtlas = [];

if nargin < 2 || isempty(fallbackTR) || ~isfinite(fallbackTR) || fallbackTR <= 0
    fallbackTR = 1;
end
if nargin < 3
    opts = struct(); %#ok<NASGU>
end

if exist(fullFile,'file') ~= 2
    error('File does not exist: %s', fullFile);
end

S = load(fullFile);
if isfield(S,'Seg')
    Seg = S.Seg;
else
    Seg = S;
end

% ------------------------------------------------------------
% Get and repair label map early.
% Important for old files where negative labels were saved as uint32.
% ------------------------------------------------------------
if isfield(Seg,'labelMap') && ~isempty(Seg.labelMap)
    roiAtlas = fc_repair_signed_label_map(Seg.labelMap);
elseif isfield(Seg,'R') && ~isempty(Seg.R)
    roiAtlas = fc_repair_signed_label_map(Seg.R);
elseif isfield(Seg,'atlas') && ~isempty(Seg.atlas)
    roiAtlas = fc_repair_signed_label_map(Seg.atlas);
else
    roiAtlas = [];
end

hasSignedMap = false;
try
    hasSignedMap = ~isempty(roiAtlas) && any(double(roiAtlas(:)) < 0);
catch
    hasSignedMap = false;
end

% ------------------------------------------------------------
% Read base region metadata.
% Segmentation stores base labels as unsigned absolute Allen IDs.
% ------------------------------------------------------------
labelsBase = [];
acr = {};
nmFull = {};
countsLeft = [];
countsRight = [];
countsBoth = [];

if isfield(Seg,'region') && isstruct(Seg.region)
    if isfield(Seg.region,'labels') && ~isempty(Seg.region.labels)
        labelsBase = double(Seg.region.labels(:));
    end
    if isfield(Seg.region,'acronyms') && ~isempty(Seg.region.acronyms)
        acr = cellstr(Seg.region.acronyms(:));
    end
    if isfield(Seg.region,'names') && ~isempty(Seg.region.names)
        nmFull = cellstr(Seg.region.names(:));
    end
    if isfield(Seg.region,'countsLeft') && ~isempty(Seg.region.countsLeft)
        countsLeft = double(Seg.region.countsLeft(:));
    end
    if isfield(Seg.region,'countsRight') && ~isempty(Seg.region.countsRight)
        countsRight = double(Seg.region.countsRight(:));
    end
    if isfield(Seg.region,'countsBoth') && ~isempty(Seg.region.countsBoth)
        countsBoth = double(Seg.region.countsBoth(:));
    end
end

% ------------------------------------------------------------
% Decide whether we can use true left/right traces.
% Only do this if the saved spatial label map is signed.
% Otherwise FC map and timecourse labels would not match.
% ------------------------------------------------------------
hasLR = isfield(Seg,'Left') && isstruct(Seg.Left) && isfield(Seg,'Right') && isstruct(Seg.Right);
useLR = hasSignedMap && hasLR;

Mregion = [];
labels = [];
names = {};
counts = [];
spaceName = '';

if useLR
    L = [];
    R = [];
    if isfield(Seg.Left,'z') && isfield(Seg.Right,'z') && ~isempty(Seg.Left.z) && ~isempty(Seg.Right.z)
        Lz = double(Seg.Left.z);
        Rz = double(Seg.Right.z);
        nFinite = sum(any(isfinite(Lz),2)) + sum(any(isfinite(Rz),2));
        if nFinite >= 2
            L = Lz;
            R = Rz;
            spaceName = 'LeftRight.z';
        end
    end
    if isempty(L) && isfield(Seg.Left,'raw') && isfield(Seg.Right,'raw') && ~isempty(Seg.Left.raw) && ~isempty(Seg.Right.raw)
        L = double(Seg.Left.raw);
        R = double(Seg.Right.raw);
        spaceName = 'LeftRight.raw';
    end

    if ~isempty(L) && ~isempty(R)
        if isempty(labelsBase)
            labelsBase = (1:min(size(L,1),size(R,1)))';
        end
        nBase = min([numel(labelsBase), size(L,1), size(R,1)]);
        for kk = 1:nBase
            lab0 = abs(round(double(labelsBase(kk))));
            if ~isfinite(lab0) || lab0 == 0
                continue;
            end

            stem = '';
            if kk <= numel(acr)
                stem = strtrim(char(acr{kk}));
            end
            if isempty(stem) || strcmpi(stem,'unknown')
                if kk <= numel(nmFull)
                    stem = strtrim(char(nmFull{kk}));
                end
            end
            if isempty(stem) || strcmpi(stem,'unknown')
                stem = sprintf('ROI_%g',lab0);
            end

            if any(isfinite(L(kk,:)))
                Mregion(end+1,:) = L(kk,:); %#ok<AGROW>
                labels(end+1,1) = -lab0; %#ok<AGROW>
                names{end+1,1} = sprintf('L_%s [%g]',stem,-lab0); %#ok<AGROW>
                if kk <= numel(countsLeft), counts(end+1,1) = countsLeft(kk); else, counts(end+1,1) = NaN; end %#ok<AGROW>
            end

            if any(isfinite(R(kk,:)))
                Mregion(end+1,:) = R(kk,:); %#ok<AGROW>
                labels(end+1,1) = lab0; %#ok<AGROW>
                names{end+1,1} = sprintf('R_%s [%g]',stem,lab0); %#ok<AGROW>
                if kk <= numel(countsRight), counts(end+1,1) = countsRight(kk); else, counts(end+1,1) = NaN; end %#ok<AGROW>
            end
        end
    end
end

% ------------------------------------------------------------
% Fallback: bilateral merged Seg.Both result.
% This is expected to produce 78 regions for your slice.
% ------------------------------------------------------------
if isempty(Mregion)
    hasZ = isfield(Seg,'Both') && isstruct(Seg.Both) && isfield(Seg.Both,'z') && ~isempty(Seg.Both.z);
    hasRaw = isfield(Seg,'Both') && isstruct(Seg.Both) && isfield(Seg.Both,'raw') && ~isempty(Seg.Both.raw);
    if hasZ
        Mregion = double(Seg.Both.z);
        spaceName = 'Both.z';
        if sum(any(isfinite(Mregion),2)) < 2 && hasRaw
            Mregion = double(Seg.Both.raw);
            spaceName = 'Both.raw';
        end
    elseif hasRaw
        Mregion = double(Seg.Both.raw);
        spaceName = 'Both.raw';
    else
        error('Seg.Both.z/raw or signed Seg.Left/Right traces were not found.');
    end

    if isempty(labelsBase)
        labelsBase = (1:size(Mregion,1))';
    end
    nBase = min(numel(labelsBase),size(Mregion,1));
    labels = labelsBase(1:nBase);
    names = cell(nBase,1);
    for kk = 1:nBase
        stem = '';
        if kk <= numel(acr), stem = strtrim(char(acr{kk})); end
        if isempty(stem) || strcmpi(stem,'unknown')
            if kk <= numel(nmFull), stem = strtrim(char(nmFull{kk})); end
        end
        if isempty(stem) || strcmpi(stem,'unknown')
            stem = sprintf('ROI_%g',labels(kk));
        end
        names{kk} = sprintf('%s [%g]',stem,labels(kk));
    end
    if numel(countsBoth) >= nBase
        counts = countsBoth(1:nBase);
    else
        counts = nan(nBase,1);
    end
    Mregion = Mregion(1:nBase,:);
end

% ------------------------------------------------------------
% Orient to time x region.
% ------------------------------------------------------------
if size(Mregion,1) == numel(labels)
    meanTS = Mregion';
elseif size(Mregion,2) == numel(labels)
    meanTS = Mregion;
else
    error('Region-time matrix size does not match label count. Matrix = %s, labels = %d.', mat2str(size(Mregion)), numel(labels));
end

if size(meanTS,1) < 2
    error('The selected Segmentation file has only %d time point(s). Functional connectivity needs region time traces.',size(meanTS,1));
end

% ------------------------------------------------------------
% Remove invalid/background rows.
% ------------------------------------------------------------
valid = true(1,size(meanTS,2));
for kk = 1:size(meanTS,2)
    x = meanTS(:,kk);
    valid(kk) = any(isfinite(x));
    if kk <= numel(labels) && kk <= numel(names)
        if fc_is_background_region(labels(kk),names{kk})
            valid(kk) = false;
        end
    end
end

meanTS = meanTS(:,valid);
labels = labels(valid(:));
names = names(valid(:));
if numel(counts) == numel(valid)
    counts = counts(valid(:));
else
    counts = nan(numel(labels),1);
end

if size(meanTS,2) < 2
    error('Segmentation result has only %d usable region traces after cleanup. Source used: %s.',size(meanTS,2),spaceName);
end

% Replace NaNs per region by that region finite mean before correlation.
for kk = 1:size(meanTS,2)
    x = meanTS(:,kk);
    bad = ~isfinite(x);
    if any(bad)
        good = x(isfinite(x));
        if isempty(good)
            x(bad) = 0;
        else
            x(bad) = mean(good);
        end
        meanTS(:,kk) = x;
    end
end

Rfc = fc_corr_matrix(meanTS);

TR = fallbackTR;
if isfield(Seg,'TR') && ~isempty(Seg.TR) && isfinite(Seg.TR) && Seg.TR > 0
    TR = double(Seg.TR);
end

res = struct();
res.labels = labels(:);
res.names = names(:);
res.counts = counts(:);
res.meanTS = meanTS;
res.M = Rfc;
res.TR = TR;
res.timeIdx = (1:size(meanTS,1))';
res.epochName = ['Segmentation ' spaceName];
res.sourceFile = fullFile;
res.sourceType = 'HUMoR Segmentation';
res.meanTSFull = meanTS;
res.timeIdxFull = (1:size(meanTS,1))';
res.timeSec = [];
res.timeMin = [];

try
    if isfield(Seg,'timeSec') && ~isempty(Seg.timeSec) && numel(Seg.timeSec) == size(meanTS,1)
        res.timeSec = double(Seg.timeSec(:));
        res.timeMin = res.timeSec ./ 60;
    elseif isfield(Seg,'timeMin') && ~isempty(Seg.timeMin) && numel(Seg.timeMin) == size(meanTS,1)
        res.timeMin = double(Seg.timeMin(:));
        res.timeSec = res.timeMin .* 60;
    else
        res.timeSec = ((0:size(meanTS,1)-1)' .* TR);
        res.timeMin = res.timeSec ./ 60;
    end
catch
    res.timeSec = ((0:size(meanTS,1)-1)' .* TR);
    res.timeMin = res.timeSec ./ 60;
end

try
    res.timeMin = fc_extract_seg_time_min(Seg,size(meanTS,1),TR);
catch
end
try
    res.timeMinFull = res.timeMin(:);
    res.timeSecFull = res.timeMinFull .* 60;
catch
end

info = struct();
info.file = fullFile;
info.TR = TR;
info.spaceName = spaceName;
info.nRegions = numel(labels);
info.nTime = size(meanTS,1);
info.hasSignedMap = hasSignedMap;
info.note = 'True LR FC uses Seg.Left/Right only when Seg.labelMap has signed labels.';
end

function A = fc_repair_signed_label_map(A)
% Repair label maps while preserving signed left/right labels.
% This also fixes old files where int32 negative labels were accidentally saved as uint32.
try
    sz = size(A);
    if isa(A,'uint32')
        u = double(A(:));
        high = u > double(intmax('int32'));
        u(high) = u(high) - 2^32;
        A = reshape(u,sz);
    else
        A = double(A);
        high = A > double(intmax('int32')) & A <= 2^32;
        A(high) = A(high) - 2^32;
    end
    A = round(double(A));
    A(~isfinite(A)) = 0;
catch
    try
        A = round(double(A));
        A(~isfinite(A)) = 0;
    catch
        A = [];
    end
end
end

function tf = fc_is_background_region(label,nameStr)
tf = false;
if nargin < 2 || isempty(nameStr), nameStr = ''; end
try
    lab = round(double(label));
catch
    lab = NaN;
end
if ~isfinite(lab) || lab == 0
    tf = true;
    return;
end

if any(abs(lab) == [0 997])
    tf = true;
    return;
end

try
    s = lower(strtrim(char(nameStr)));
    s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
    s = regexprep(s,'[_\-]+',' ');
catch
    s = '';
end

bad = {'root','background','outside','no label','nolabel','unknown','void','empty','air'};
for ii = 1:numel(bad)
    if strcmp(s,bad{ii}) || ~isempty(strfind(s,bad{ii}))
        tf = true;
        return;
    end
end
end

function fc_region_key_dialog(s,C)
% Show abbreviation -> full-name mapping for the current ROI/Segmentation result.
res = [];
try
    res = s.roiResults{s.currentSubject,s.currentEpoch};
catch
end

if isempty(res) || ~isfield(res,'labels') || isempty(res.labels)
    error('No ROI/Segmentation result is loaded yet. Load Seg MAT or compute ROI FC first.');
end

labels = double(res.labels(:));
names = res.names(:);
n = numel(labels);
if numel(names) < n
    tmp = cell(n,1);
    for k = 1:n
        if k <= numel(names), tmp{k} = names{k}; else, tmp{k} = sprintf('ROI_%g',labels(k)); end
    end
    names = tmp;
end

[abbr, fullNames, sourceFile, sourceLabel] = fc_region_key_collect(labels,names,s,res);

lines = {};
lines{end+1} = 'FUNCTIONAL CONNECTIVITY REGION KEY';
lines{end+1} = '============================================================';
lines{end+1} = sprintf('Regions: %d',n);
if ~isempty(sourceLabel)
    lines{end+1} = ['Source: ' sourceLabel];
end
if ~isempty(sourceFile)
    lines{end+1} = ['File: ' sourceFile];
end
lines{end+1} = '';
lines{end+1} = sprintf('%-5s %-12s %-18s %s','No','Label','Abbrev','Full name');
lines{end+1} = sprintf('%-5s %-12s %-18s %s','----','----------','----------------','------------------------------');
for k = 1:n
    lines{end+1} = sprintf('%-5d %-12g %-18s %s',k,labels(k),abbr{k},fullNames{k}); %#ok<AGROW>
end
outTxt = strjoin(lines,newline);

bg = [0.06 0.06 0.07]; fg = [0.96 0.96 0.96];
figKey = figure('Name','FC Region key: abbreviation -> full name', ...
    'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Units','pixels','Position',[260 90 1050 820]);
try, movegui(figKey,'center'); catch, end

uicontrol('Parent',figKey,'Style','edit','Max',2,'Min',0, ...
    'Units','normalized','Position',[0.035 0.105 0.930 0.855], ...
    'BackgroundColor',bg,'ForegroundColor',fg,'FontName','Consolas', ...
    'FontSize',11,'HorizontalAlignment','left','String',outTxt);

if ~isempty(sourceFile) && exist(sourceFile,'file')
    uicontrol('Parent',figKey,'Style','pushbutton','Units','normalized', ...
        'Position',[0.035 0.025 0.250 0.055],'String','Open source file', ...
        'BackgroundColor',C.orange,'ForegroundColor','w', ...
        'FontName',C.font,'FontWeight','bold','FontSize',12, ...
        'Callback',@(src,evt)fc_open_file_external(sourceFile));
end

uicontrol('Parent',figKey,'Style','pushbutton','Units','normalized', ...
    'Position',[0.790 0.025 0.175 0.055],'String','Close', ...
    'BackgroundColor',C.red,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',12, ...
    'Callback',@(src,evt)delete(figKey));
end

function [abbr, fullNames, sourceFile, sourceLabel] = fc_region_key_collect(labels,names,s,res)
n = numel(labels);
abbr = cell(n,1);
fullNames = cell(n,1);
for k = 1:n
    displayName = char(names{k});
    displayName = strtrim(displayName);
    abbr{k} = fc_roi_abbrev(displayName,18);
    fullNames{k} = regexprep(displayName,'\s*\[[^\]]*\]\s*$','');
    if isempty(strtrim(fullNames{k})), fullNames{k} = displayName; end
end

sourceFile = '';
sourceLabel = '';

try
    if isfield(s,'loadedRegionNameFile') && ~isempty(s.loadedRegionNameFile) && exist(s.loadedRegionNameFile,'file')
        sourceFile = s.loadedRegionNameFile;
        sourceLabel = 'Loaded region-name TXT/CSV/MAT';
    elseif isfield(s,'loadedSegmentationFile') && ~isempty(s.loadedSegmentationFile) && exist(s.loadedSegmentationFile,'file')
        sourceFile = s.loadedSegmentationFile;
        sourceLabel = 'Loaded Segmentation MAT';
    elseif isfield(res,'sourceFile') && ~isempty(res.sourceFile) && exist(res.sourceFile,'file')
        sourceFile = res.sourceFile;
        sourceLabel = 'ROI result source file';
    end
catch
end

% If a region-name table was loaded, use it as full-name source.
try
    if isfield(s,'opts') && isfield(s.opts,'roiNameTable')
        T = s.opts.roiNameTable;
        if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
            for k = 1:n
                idx = find(abs(double(T.labels(:))) == abs(labels(k)),1,'first');
                if ~isempty(idx) && idx <= numel(T.names)
                    nm = strtrim(char(T.names{idx}));
                    if ~isempty(nm)
                        fullNames{k} = nm;
                        abbr{k} = fc_roi_abbrev(nm,18);
                    end
                end
            end
        end
    end
catch
end

% If this came from HUMoR Segmentation, retrieve acronyms and full names directly from Seg.region.
try
    segFile = '';
    if isfield(res,'sourceFile') && ~isempty(res.sourceFile) && exist(res.sourceFile,'file')
        segFile = res.sourceFile;
    elseif ~isempty(sourceFile) && exist(sourceFile,'file')
        segFile = sourceFile;
    end
    if ~isempty(segFile)
        S = load(segFile);
        if isfield(S,'Seg')
            Seg = S.Seg;
            if isfield(Seg,'region') && isstruct(Seg.region) && isfield(Seg.region,'labels')
                labs0 = double(Seg.region.labels(:));
                acr0 = {};
                nam0 = {};
                if isfield(Seg.region,'acronyms') && ~isempty(Seg.region.acronyms), acr0 = cellstr(Seg.region.acronyms(:)); end
                if isfield(Seg.region,'names') && ~isempty(Seg.region.names), nam0 = cellstr(Seg.region.names(:)); end
                for k = 1:n
                    idx = find(abs(labs0) == abs(labels(k)),1,'first');
                    if ~isempty(idx)
                        if idx <= numel(acr0) && ~isempty(strtrim(char(acr0{idx})))
                            abbr{k} = strtrim(char(acr0{idx}));
                        end
                        if idx <= numel(nam0) && ~isempty(strtrim(char(nam0{idx})))
                            fullNames{k} = strtrim(char(nam0{idx}));
                        end
                    end
                end
            end
        end
    end
catch
end
end

function fc_open_file_external(fileName)
try
    if exist(fileName,'file')
        if ispc
            winopen(fileName);
        elseif ismac
            system(['open "' fileName '" &']);
        else
            system(['xdg-open "' fileName '" &']);
        end
    end
catch
    try, edit(fileName); catch, end
end
end





function [M,names,order,meta] = fc_apply_region_visibility(s,M,names,order,meta)
try
    if nargin < 5 || isempty(M) || isempty(names), return; end

    if isfield(meta,'isRectangular') && meta.isRectangular
        yKeep = 1:size(M,1);
        xKeep = 1:size(M,2);
        if isfield(s,'fcSelectedRegionY') && ~isempty(s.fcSelectedRegionY)
            yKeep = fc_region_keep_indices(s.fcSelectedRegionY,size(M,1));
        end
        if isfield(s,'fcSelectedRegionX') && ~isempty(s.fcSelectedRegionX)
            xKeep = fc_region_keep_indices(s.fcSelectedRegionX,size(M,2));
        end
        if isempty(yKeep) || isempty(xKeep), return; end
        M = M(yKeep,xKeep);
        try, meta.namesY = meta.namesY(yKeep); catch, end
        try, meta.namesX = meta.namesX(xKeep); catch, end
        try, meta.orderY = meta.orderY(yKeep); catch, end
        try, meta.orderX = meta.orderX(xKeep); catch, end
        try, meta.displayLabelsY = meta.displayLabelsY(yKeep); catch, end
        try, meta.displayLabelsX = meta.displayLabelsX(xKeep); catch, end
        try, names = meta.namesY; catch, names = names(yKeep); end
        try, order = meta.orderY; catch, order = order(yKeep); end
        try, meta.displayLabels = meta.displayLabelsY; catch, end

        if isfield(s,'sliceRegionOnly') && s.sliceRegionOnly
            ySlice = HUMOR_FC_slice_keep_indices(s,meta,size(M,1),'y');
            xSlice = HUMOR_FC_slice_keep_indices(s,meta,size(M,2),'x');
            if ~isempty(ySlice) && ~isempty(xSlice)
                M = M(ySlice,xSlice);
                try, meta.namesY = meta.namesY(ySlice); catch, end
                try, meta.namesX = meta.namesX(xSlice); catch, end
                try, meta.orderY = meta.orderY(ySlice); catch, end
                try, meta.orderX = meta.orderX(xSlice); catch, end
                try, meta.displayLabelsY = meta.displayLabelsY(ySlice); catch, end
                try, meta.displayLabelsX = meta.displayLabelsX(xSlice); catch, end
                try, names = meta.namesY; catch, names = names(ySlice); end
                try, order = meta.orderY; catch, order = order(ySlice); end
                try, meta.displayLabels = meta.displayLabelsY; catch, end
            end
        end
        return;
    end

    if isfield(s,'fcSelectedRegionIdx') && ~isempty(s.fcSelectedRegionIdx)
        keep = fc_region_keep_indices(s.fcSelectedRegionIdx,size(M,1));
        if ~isempty(keep)
            M = M(keep,keep);
            names = names(keep);
            try, order = order(keep); catch, end
            try, meta.groups = meta.groups(keep); catch, end
            try, meta.displayLabels = meta.displayLabels(keep); catch, end
        end
    end

    if isfield(s,'sliceRegionOnly') && s.sliceRegionOnly
        keepSlice = HUMOR_FC_slice_keep_indices(s,meta,size(M,1),'both');
        if ~isempty(keepSlice)
            M = M(keepSlice,keepSlice);
            names = names(keepSlice);
            try, order = order(keepSlice); catch, end
            try, meta.groups = meta.groups(keepSlice); catch, end
            try, meta.displayLabels = meta.displayLabels(keepSlice); catch, end
        end
    end
catch
end
end

function keep = fc_region_keep_indices(sel,n)
keep = [];
try
    if isempty(sel) || n < 1, return; end
    if islogical(sel)
        sel = sel(:);
        if numel(sel) == n, keep = find(sel); end
    else
        sel = round(double(sel(:)));
        sel = unique(sel(isfinite(sel) & sel >= 1 & sel <= n));
        keep = sel(:)';
    end
catch
    keep = [];
end
end

function [sel,ok] = fc_checkbox_select_dialog(names,initialIdx,titleStr)
% Better custom region selector with tick/untick checkboxes.
if nargin < 2 || isempty(initialIdx), initialIdx = 1:numel(names); end
if nargin < 3 || isempty(titleStr), titleStr = 'Select regions'; end
ok = false;
sel = [];
names = cellstr(names(:));
n = numel(names);
checked = false(n,1);
initialIdx = round(double(initialIdx(:)));
initialIdx = initialIdx(isfinite(initialIdx) & initialIdx >= 1 & initialIdx <= n);
checked(initialIdx) = true;
data = cell(n,2);
for ii = 1:n
    data{ii,1} = checked(ii);
    data{ii,2} = names{ii};
end
bg = [0.06 0.06 0.07];
fg = [0.96 0.96 0.96];
fh = figure('Name',titleStr,'Color',bg,'MenuBar','none','ToolBar','none', ...
    'NumberTitle','off','Units','pixels','Position',[300 120 560 720], ...
    'WindowStyle','modal','CloseRequestFcn',@onCancel);
try, movegui(fh,'center'); catch, end
uicontrol('Parent',fh,'Style','text','Units','normalized', ...
    'Position',[0.04 0.945 0.92 0.035],'String','Tick/untick regions to display in Heatmap and Graph.', ...
    'BackgroundColor',bg,'ForegroundColor',fg,'HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',11,'FontWeight','bold','FontSize',14);
tbl = uitable('Parent',fh,'Units','normalized','Position',[0.04 0.125 0.92 0.805], ...
    'Data',data,'ColumnName',{'Show','Region'},'ColumnEditable',[true false], ...
    'ColumnFormat',{'logical','char'},'ColumnWidth',{55 430},'RowName',[], ...
    'FontName','Arial','FontSize',10);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.04 0.045 0.13 0.055],'String','All', ...
    'BackgroundColor',[0.18 0.55 0.25],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onAll);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.19 0.045 0.13 0.055],'String','None', ...
    'BackgroundColor',[0.45 0.45 0.48],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onNone);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.61 0.045 0.16 0.055],'String','Apply', ...
    'BackgroundColor',[0.10 0.38 0.78],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onOK);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.80 0.045 0.16 0.055],'String','Cancel', ...
    'BackgroundColor',[0.65 0.18 0.18],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onCancel);
uiwait(fh);
if ishandle(fh)
    try
        tmp = getappdata(fh,'fc_selected');
        if ~isempty(tmp)
            sel = tmp(:)';
            ok = true;
        end
    catch
    end
    try, delete(fh); catch, end
end

    function onAll(~,~)
        d = get(tbl,'Data');
        d(:,1) = num2cell(true(size(d,1),1));
        set(tbl,'Data',d);
    end

    function onNone(~,~)
        d = get(tbl,'Data');
        d(:,1) = num2cell(false(size(d,1),1));
        set(tbl,'Data',d);
    end

    function onOK(~,~)
        d = get(tbl,'Data');
        c = false(size(d,1),1);
        for jj = 1:size(d,1)
            try, c(jj) = logical(d{jj,1}); catch, c(jj) = false; end
        end
        idx = find(c);
        setappdata(fh,'fc_selected',idx);
        uiresume(fh);
    end

    function onCancel(~,~)
        setappdata(fh,'fc_selected',[]);
        uiresume(fh);
    end
end

function [selY,selX,ok] = fc_checkbox_select_two_dialog(namesY,namesX,initY,initX,titleStr)
% Better selector for Left-vs-Right rectangular heatmaps.
if nargin < 3 || isempty(initY), initY = 1:numel(namesY); end
if nargin < 4 || isempty(initX), initX = 1:numel(namesX); end
if nargin < 5 || isempty(titleStr), titleStr = 'Select visible regions'; end
ok = false;
selY = [];
selX = [];
namesY = cellstr(namesY(:));
namesX = cellstr(namesX(:));
nY = numel(namesY);
nX = numel(namesX);
cY = false(nY,1);
cX = false(nX,1);
initY = round(double(initY(:))); initY = initY(isfinite(initY) & initY >= 1 & initY <= nY);
initX = round(double(initX(:))); initX = initX(isfinite(initX) & initX >= 1 & initX <= nX);
cY(initY) = true;
cX(initX) = true;
dataY = cell(nY,2);
dataX = cell(nX,2);
for ii = 1:nY, dataY{ii,1} = cY(ii); dataY{ii,2} = namesY{ii}; end
for ii = 1:nX, dataX{ii,1} = cX(ii); dataX{ii,2} = namesX{ii}; end
bg = [0.06 0.06 0.07];
fg = [0.96 0.96 0.96];
fh = figure('Name',titleStr,'Color',bg,'MenuBar','none','ToolBar','none', ...
    'NumberTitle','off','Units','pixels','Position',[210 90 980 760], ...
    'WindowStyle','modal','CloseRequestFcn',@onCancel);
try, movegui(fh,'center'); catch, end
uicontrol('Parent',fh,'Style','text','Units','normalized', ...
    'Position',[0.035 0.945 0.43 0.035],'String','Left/Y axis regions', ...
    'BackgroundColor',bg,'ForegroundColor',fg,'HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',12,'FontWeight','bold','FontSize',14);
uicontrol('Parent',fh,'Style','text','Units','normalized', ...
    'Position',[0.535 0.945 0.43 0.035],'String','Right/X axis regions', ...
    'BackgroundColor',bg,'ForegroundColor',fg,'HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',12,'FontWeight','bold','FontSize',14);
tblY = uitable('Parent',fh,'Units','normalized','Position',[0.035 0.135 0.43 0.800], ...
    'Data',dataY,'ColumnName',{'Show','Left/Y region'},'ColumnEditable',[true false], ...
    'ColumnFormat',{'logical','char'},'ColumnWidth',{55 355},'RowName',[], ...
    'FontName','Arial','FontSize',10);
tblX = uitable('Parent',fh,'Units','normalized','Position',[0.535 0.135 0.43 0.800], ...
    'Data',dataX,'ColumnName',{'Show','Right/X region'},'ColumnEditable',[true false], ...
    'ColumnFormat',{'logical','char'},'ColumnWidth',{55 355},'RowName',[], ...
    'FontName','Arial','FontSize',10);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.035 0.050 0.105 0.055],'String','All L', ...
    'BackgroundColor',[0.18 0.55 0.25],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(src,evt)setAll(tblY,true));
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.150 0.050 0.105 0.055],'String','None L', ...
    'BackgroundColor',[0.45 0.45 0.48],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(src,evt)setAll(tblY,false));
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.535 0.050 0.105 0.055],'String','All R', ...
    'BackgroundColor',[0.18 0.55 0.25],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(src,evt)setAll(tblX,true));
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.650 0.050 0.105 0.055],'String','None R', ...
    'BackgroundColor',[0.45 0.45 0.48],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(src,evt)setAll(tblX,false));
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.775 0.050 0.090 0.055],'String','Apply', ...
    'BackgroundColor',[0.10 0.38 0.78],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onOK);
uicontrol('Parent',fh,'Style','pushbutton','Units','normalized', ...
    'Position',[0.875 0.050 0.090 0.055],'String','Cancel', ...
    'BackgroundColor',[0.65 0.18 0.18],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onCancel);
uiwait(fh);
if ishandle(fh)
    try
        a = getappdata(fh,'fc_selected_y');
        b = getappdata(fh,'fc_selected_x');
        if ~isempty(a) && ~isempty(b)
            selY = a(:)';
            selX = b(:)';
            ok = true;
        end
    catch
    end
    try, delete(fh); catch, end
end

    function setAll(tbl,val)
        d = get(tbl,'Data');
        d(:,1) = num2cell(logical(val) .* true(size(d,1),1));
        set(tbl,'Data',d);
    end

    function idx = getChecked(tbl)
        d = get(tbl,'Data');
        c = false(size(d,1),1);
        for jj = 1:size(d,1)
            try, c(jj) = logical(d{jj,1}); catch, c(jj) = false; end
        end
        idx = find(c);
    end

    function onOK(~,~)
        idxY = getChecked(tblY);
        idxX = getChecked(tblX);
        setappdata(fh,'fc_selected_y',idxY);
        setappdata(fh,'fc_selected_x',idxX);
        uiresume(fh);
    end

    function onCancel(~,~)
        setappdata(fh,'fc_selected_y',[]);
        setappdata(fh,'fc_selected_x',[]);
        uiresume(fh);
    end
end

function fc_help_dialog(C) %#ok<INUSD>
bg = [0.06 0.06 0.07]; fg = [0.96 0.96 0.96];
helpFig = figure('Name','Functional Connectivity - Help', ...
    'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Units','pixels','Position',[250 100 960 800]);
try, movegui(helpFig,'center'); catch, end
uicontrol('Parent',helpFig,'Style','edit','Max',2,'Min',0, ...
    'Units','normalized','Position',[0.04 0.04 0.92 0.92], ...
    'BackgroundColor',bg,'ForegroundColor',fg,'FontName','Arial', ...
    'FontSize',14,'HorizontalAlignment','left','String',fc_help_text());
end

function txt = fc_help_text()
lines = {
'FUNCTIONAL CONNECTIVITY GUIDE'
'============================================================'
''
'Underlay versus ROI labels'
'------------------------------------------------------------'
'- Underlay / histology is only the background image.'
'- ROI labels / atlas is an integer region map used to extract region timecourses.'
'- Do not load histology as ROI labels. Do not load ROI labels as the underlay unless you only want a label display.'
''
'Underlay display'
'------------------------------------------------------------'
'- Default underlay is SCM-like log-median Doppler equalization.'
'- This is computed directly from the active functional data if no Mask Editor underlay is passed.'
'- If Mask Editor anatomical_reference is passed, it is shown exactly and not normalized again.'
''
'Seed Map tab'
'------------------------------------------------------------'
'- Click on the brain image to place the seed.'
'- The yellow box shows the seed ROI that is averaged.'
'- Seed current computes voxelwise Pearson correlation with that seed timecourse.'
''
'ROI Heatmap tab'
'------------------------------------------------------------'
'- Requires ROI labels/atlas.'
'- Each cell is FC between two atlas-region mean timecourses.'
'- Fisher z = atanh(r) is the recommended display/statistics transform.'
''
'Compare ROI tab'
'------------------------------------------------------------'
'- Choose one region such as CPu/CPU.'
'- Bar plot shows the selected region versus all other regions.'
'- Atlas map projects those correlations back onto the ROI label map.'
''
'Pair ROI tab'
'------------------------------------------------------------'
'- Inspects exactly two regions with traces, scatter and lag correlation.'
''
'Graph tab'
'------------------------------------------------------------'
'- This is a network matrix summary derived from the ROI Heatmap.'
'- Matrix entries are Pearson r where |r| is above threshold, otherwise 0.'
};
txt = strjoin(lines,newline);
end


