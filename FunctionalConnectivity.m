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

st.seedX = max(1, round(X/2));
st.seedY = max(1, round(Y/2));
st.seedBoxSize = max(1, round(opts.seedBoxSize));
st.useSliceOnly = false;

st.analysisStartSec = 0;
st.analysisEndSec = inf;
st.epochs = struct('name', {'Whole'}, 'start', {0}, 'end', {inf});
st.currentEpoch = 1;

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
st.seedCLim = 2.5;

st.roiAbsThr = 0.00;
st.roiDisplaySpace = 'z';
st.roiOrder = 'name';
st.roiCLim = 1.0;
st.roiZCLim = 2.5;

st.cmapName = 'bwr';
st.graphCmapName = 'bwr';
st.compareROI = 1;
st.compareTopN = 20;
st.compareSort = 'abs';

st.seedResults = cell(nSub, numel(st.epochs));
st.roiResults  = cell(nSub, numel(st.epochs));

st.saveRoot = saveRoot;
st.tag = tag;
st.qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(st.qcDir,'dir'), mkdir(st.qcDir); end
st.opts = opts;

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
C.fsTiny  = 12;
C.fsSmall = 14;
C.fs      = 15;
C.fsBig   = 17;

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
    'Units','pixels', ...
    'Position',scr, ...
    'CloseRequestFcn',@onClose, ...
    'WindowScrollWheelFcn',@onMouseWheel);
try, set(fig,'WindowState','maximized'); catch, end
try, set(fig,'Renderer','opengl'); catch, end

panelCtrl = uipanel('Parent',fig,'Units','normalized','Position',[0.006 0.015 0.455 0.97], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Controls','FontName',C.font,'FontSize',14,'FontWeight','bold');

panelViewWrap = uipanel('Parent',fig,'Units','normalized','Position',[0.470 0.015 0.524 0.97], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Views','FontName',C.font,'FontSize',14,'FontWeight','bold');

% -------------------------------------------------------------------------
% CONTROL PANELS
% -------------------------------------------------------------------------
pData = fc_panel(panelCtrl,[0.015 0.735 0.970 0.245],'1. Data / ROI labels',C);
pSeed = fc_panel(panelCtrl,[0.015 0.540 0.970 0.185],'2. Seed-based FC',C);
pROI  = fc_panel(panelCtrl,[0.015 0.295 0.970 0.235],'3. Region-based FC',C);
pSave = fc_panel(panelCtrl,[0.015 0.020 0.970 0.265],'4. Display / Save',C);

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
    'String','Load region names','BackgroundColor',C.blue,'ForegroundColor','w', ...
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
    'Position',[0.61 0.79 0.18 0.12], 'String',{'Fisher z','Pearson r'}, 'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onROISpace);

fc_label(pROI,[0.82 0.815 0.06 0.08],'Thr',C);
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

fc_label(pROI,[0.02 0.40 0.10 0.09],'',C);
ddSort = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.12 0.38 0.23 0.12], 'String',{'Abs strongest','Positive','Negative','Alphabetical'}, 'Value',1, 'Visible','off', ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onCompareSort);

fc_label(pROI,[0.39 0.40 0.12 0.09],'',C);
ddOrder = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.52 0.38 0.20 0.12], 'String',{'Name','Label'}, 'Value',1, 'Visible','off', ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onROIOrder);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.76 0.38 0.20 0.12], 'String','Export CSV', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsSmall,'Callback',@onExportCSV);

txtROI = uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.02 0.06 0.94 0.02], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsTiny);

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
    'Position',[0.32 0.045 0.16 0.13], 'String','Reset view', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onResetView);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.50 0.045 0.14 0.13], 'String','Save', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onSaveAll);

fc_label(pSave,[0.02 0.60 0.16 0.10],'Underlay style',C);
ddUnderlayStyle = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.20 0.58 0.30 0.12], ...
    'String',{'SCM log / median','Robust gray','Vessel enhanced','Raw min-max'}, ...
        'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontName',C.font,'FontSize',C.fsTiny,'Callback',@onUnderlayStyle);

fc_label(pSave,[0.54 0.60 0.08 0.10],'Gamma',C);
edUGamma = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.62 0.58 0.08 0.12], 'String',sprintf('%.2f',st.underlayGamma), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, 'FontName',C.font, ...
    'FontSize',C.fsTiny,'Callback',@onUnderlayStyle);

fc_label(pSave,[0.73 0.60 0.08 0.10],'Sharp',C);
edUSharp = uicontrol('Parent',pSave,'Style','edit','Units','normalized', ...
    'Position',[0.82 0.58 0.08 0.12], 'String',sprintf('%.2f',st.underlaySharpness), ...
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
    'Position',[0.66 0.045 0.14 0.13], 'String','Help', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onHelp);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.82 0.045 0.14 0.13], 'String','Close', ...
    'BackgroundColor',C.red,'ForegroundColor','w', ...
    'FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny,'Callback',@onClose);

txtStatus = uicontrol('Parent',pSave,'Style','text','Units','normalized', ...
    'Position',[0.02 0.025 0.02 0.02], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsTiny);

% -------------------------------------------------------------------------
% RIGHT-SIDE TAB STRIP
% -------------------------------------------------------------------------
tabNames = {'Seed Map','ROI Heatmap','Compare ROI','Pair ROI','Graph'};
tabKeys  = {'seed','heatmap','compare','pair','graph'};
tabBtns = zeros(numel(tabNames),1);
for k = 1:numel(tabNames)
    tabBtns(k) = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
        'Position',[0.020 + (k-1)*0.147 0.940 0.130 0.040], ...
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
axMap = axes('Parent',pSeedView,'Units','normalized','Position',[0.035 0.075 0.605 0.820], ...
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

uicontrol('Parent',pSeedView,'Style','text','Units','normalized','Position',[0.690 0.870 0.260 0.050], ...
    'String','Seed-map display','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsBig);

axSeedCB = axes('Parent',pSeedView,'Units','normalized','Position',[0.690 0.775 0.260 0.040], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);

uicontrol('Parent',pSeedView,'Style','text','Units','normalized','Position',[0.690 0.715 0.270 0.045], ...
    'String','', 'Visible','off', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontName',C.font,'FontWeight','bold','FontSize',C.fsTiny);

axSeedTS = axes('Parent',pSeedView,'Units','normalized','Position',[0.700 0.470 0.250 0.170], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axSeedHist = axes('Parent',pSeedView,'Units','normalized','Position',[0.700 0.160 0.250 0.190], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);

% ROI Heatmap tab - bigger
axHeat = axes('Parent',pHeatView,'Units','normalized','Position',[0.045 0.160 0.785 0.735], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axHeatCB = axes('Parent',pHeatView,'Units','normalized','Position',[0.855 0.205 0.030 0.665], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);
axHeatTS = axes('Parent',pHeatView,'Units','normalized','Position',[0.900 0.610 0.070 0.230],'Visible','off', ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtHeat = uicontrol('Parent',pHeatView,'Style','text','Units','normalized', ...
    'Position',[0.900 0.205 0.085 0.665], 'String','No heatmap yet.', ...
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
axAdj = axes('Parent',pGraphView,'Units','normalized','Position',[0.045 0.160 0.785 0.735], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axGraphCB = axes('Parent',pGraphView,'Units','normalized','Position',[0.855 0.205 0.030 0.665], ...
    'Color',C.bgPane,'XColor',C.dim,'YColor',C.dim);
axDeg = axes('Parent',pGraphView,'Units','normalized','Position',[0.900 0.610 0.080 0.250], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim,'Visible','off');
txtGraph = uicontrol('Parent',pGraphView,'Style','text','Units','normalized', ...
    'Position',[0.900 0.205 0.085 0.665], 'String','No graph yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontName',C.font,'FontSize',C.fsSmall);

guidata(fig,st);
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
        if s.Z <= 1
            return;
        end
        step = 1;
        try
            if ev.VerticalScrollCount > 0
                step = 1;
            else
                step = -1;
            end
        catch
            step = 1;
        end
        s.slice = fc_clip(s.slice + step,1,s.Z);
        set(slSlice,'Value',s.slice);
        set(edSlice,'String',num2str(s.slice));
        guidata(fig,s);
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
        s.seedCLim = 2.5;
        s.roiDisplaySpace = 'z';
        s.roiAbsThr = 0.00;
        s.roiOrder = 'name';
        s.compareSort = 'abs';
        s.cmapName = 'bwr';
        s.graphCmapName = 'bwr';
        try, set(ddOverlay,'Value',1); catch, end
        try, set(ddUnderlayStyle,'Value',1); catch, end
        try, set(ddCmapGlobal,'Value',1); catch, end
        try, set(ddSeedDisplay,'Value',1); catch, end
        try, set(ddROISpace,'Value',1); catch, end
        try, set(ddOrder,'Value',1); catch, end
        try, set(ddSort,'Value',1); catch, end
        try, set(cbAtlasLine,'Value',0); catch, end
        try, set(cbMaskLine,'Value',0); catch, end
        try, set(edSeedThr,'String','0.20'); catch, end
        try, set(edROIThr,'String','0.00'); catch, end
        try, set(edSeedCLim,'String','2.5'); catch, end
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
            s.roiDisplaySpace = 'z';
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
        s.compareTopN = max(2,round(v));
        set(edTopN,'String',num2str(s.compareTopN));
        guidata(fig,s);
        refreshCompareView();
    end

    function onCompareSort(~,~)
        s = guidata(fig);
        vals = {'abs','positive','negative','label'};
        s.compareSort = vals{get(ddSort,'Value')};
        guidata(fig,s);
        refreshCompareView();
    end

    function onCompareROI(~,~)
        s = guidata(fig);
        s.compareROI = get(ddCompareROI,'Value');
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
            lab = double(subj.roiAtlas(y,x,s.slice));
            if ~isfinite(lab) || lab <= 0
                setStatus('Clicked voxel has no ROI label.',C.warn);
                return;
            end
            res = s.roiResults{s.currentSubject,s.currentEpoch};
            if isempty(res)
                setStatus('ROI pick needs ROI current first. Compute ROI FC, then pick a region.',C.warn);
                return;
            end
            [~,names,order] = fc_current_matrix(s,res);
            rawIdx = find(double(res.labels(:)) == double(lab),1,'first');
            if isempty(rawIdx)
                setStatus(sprintf('Label %.0f was clicked, but it is not in the current ROI result.',lab),C.warn);
                return;
            end
            dispIdx = find(order == rawIdx,1,'first');
            if isempty(dispIdx), dispIdx = 1; end
            s.compareROI = dispIdx;
            set(ddCompareROI,'String',fc_abbrev_list(names,18),'Value',dispIdx);
            guidata(fig,s);
            setStatus(['Selected ROI: ' fc_roi_abbrev(names{dispIdx},20)],C.good);
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
        lab = double(subj.roiAtlas(y,x,s.slice));
        if ~isfinite(lab) || lab <= 0
            setStatus('Clicked region map background/no-label area.',C.warn);
            return;
        end
        [~,names,order] = fc_current_matrix(s,res);
        rawIdx = find(double(res.labels(:)) == lab,1,'first');
        if isempty(rawIdx)
            setStatus(sprintf('Clicked label %.0f is not included in the current ROI result.',lab),C.warn);
            return;
        end
        dispIdx = find(order == rawIdx,1,'first');
        if isempty(dispIdx), dispIdx = 1; end
        s.compareROI = dispIdx;
        try, set(ddCompareROI,'String',fc_abbrev_list(names,18),'Value',dispIdx); catch, end
        guidata(fig,s);
        setStatus(['Benchmark ROI changed to: ' fc_roi_abbrev(names{dispIdx},20)],C.good);
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
        [f,p] = fc_uigetfile_start( ...
            {'*.mat;*.nii;*.nii.gz;*.tif;*.tiff','ROI label files'}, ...
            'Load ROI atlas / integer label map', ...
            fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        a = fc_read_atlas_any(fullfile(p,f),s.Y,s.X,s.Z);
        if isempty(a)
            errordlg({'No compatible ROI label map found.', '', ...
                'Histology/regions images are display underlays.', ...
                'ROI FC needs integer labels/annotation volume.'},'ROI labels');
            return;
        end
        choice = questdlg('Apply ROI label map to current subject or all subjects?', ...
            'ROI labels','Current','All','Current');
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
        [f,p] = fc_uigetfile_start( ...
            {'*.txt;*.csv;*.tsv;*.mat','Region names (*.txt,*.csv,*.tsv,*.mat)'}, ...
            'Load region names', ...
            fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end
        try
            T = fc_read_region_names(fullfile(p,f));
            if isempty(T.labels)
                errordlg('Could not parse labels/names from selected file.');
                return;
            end
            s.opts.roiNameTable = T;
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
        idxT = fc_time_idx(subj.TR,size(subj.I4,4),s.analysisStartSec,s.analysisEndSec);
        res = fc_seed_fc(subj.I4(:,:,:,idxT),subj.TR,subj.mask, ...
            s.seedX,s.seedY,s.slice,s.seedBoxSize,s.useSliceOnly,s.opts.chunkVox);
        res.timeIdx = idxT;
        res.epochName = s.epochs(epIdx).name;
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
        idxT = fc_time_idx(subj.TR,size(subj.I4,4),s.analysisStartSec,s.analysisEndSec);
        res = fc_roi_fc(subj.I4(:,:,:,idxT),subj.TR,subj.mask,subj.roiAtlas,s.opts);
        res.timeIdx = idxT;
        res.epochName = s.epochs(epIdx).name;
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
            [M,names] = fc_current_matrix(s,res);
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
            fc_save_axis(axMap,fig,fullfile(s.qcDir,['FC_seed_map_' s.tag '.png']));
            fc_save_axis(axHeat,fig,fullfile(s.qcDir,['FC_heatmap_' s.tag '.png']));
            fc_save_axis(axCompareBar,fig,fullfile(s.qcDir,['FC_compare_bar_' s.tag '.png']));
            fc_save_axis(axCompareMap,fig,fullfile(s.qcDir,['FC_compare_map_' s.tag '.png']));
            fc_save_axis(axAdj,fig,fullfile(s.qcDir,['FC_graph_' s.tag '.png']));
            res = s.roiResults{s.currentSubject,s.currentEpoch};
            if ~isempty(res)
                [M,names] = fc_current_matrix(s,res);
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

% =========================================================================
% REFRESH FUNCTIONS
% =========================================================================
    function refreshAll()
        s = guidata(fig);
        s.slice = fc_clip(s.slice,1,s.Z);
        s.seedX = fc_clip(s.seedX,1,s.X);
        s.seedY = fc_clip(s.seedY,1,s.Y);
        set(ddSubject,'Value',s.currentSubject);
        set(slSlice,'Value',s.slice);
        set(edSlice,'String',num2str(s.slice));
        set(edSeedX,'String',num2str(s.seedX));
        set(edSeedY,'String',num2str(s.seedY));
        set(edSeedSize,'String',num2str(s.seedBoxSize));
        set(cbSliceOnly,'Value',double(s.useSliceOnly));
        set(cbAtlasLine,'Value',double(s.showAtlasLines));
        set(cbMaskLine,'Value',double(s.showMaskLine));
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
                    [ovRGB,ovA] = fc_line_overlay(atlasS > 0,atlasS,C.line);
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
                    [ovRGB,ovA] = fc_line_overlay(atlasS > 0,atlasS,C.line);
                    cbLabel = 'Click ROI';
                    cbClim = [0 1];
                end
        end
        set(hOver,'CData',ovRGB,'AlphaData',ovA);

        atlasRGB = nan(s.Y,s.X,3); atlasA = zeros(s.Y,s.X);
        if s.showAtlasLines
            atlasS = fc_atlas_slice(s);
            if ~isempty(atlasS), [atlasRGB,atlasA] = fc_line_overlay(atlasS > 0,atlasS,C.line); end
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
            set(axHeat,   'Position',[0.045 0.160 0.785 0.735]);
            set(axHeatCB, 'Position',[0.855 0.205 0.030 0.665]);
            set(txtHeat,  'Position',[0.900 0.205 0.085 0.665]);
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

        [M,names,order] = fc_current_matrix(s,res); %#ok<ASGLU>

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
        axis(axHeat,'image');
        fc_ax(axHeat,C);
        colormap(axHeat,cmap);

        title(axHeat,'Region-by-region FC heatmap', ...
            'Color',C.fg, ...
            'Interpreter','none', ...
            'FontWeight','bold');
        xlabel(axHeat,'Atlas region','Color',C.dim,'FontWeight','bold');
        ylabel(axHeat,'Atlas region','Color',C.dim,'FontWeight','bold');

        nR = size(Mdisp,1);
        if nR <= 35
            tickStep = 1;
        elseif nR <= 70
            tickStep = 2;
        elseif nR <= 120
            tickStep = 4;
        elseif nR <= 200
            tickStep = 6;
        else
            tickStep = max(8,ceil(nR/30));
        end
        tickIdx = 1:tickStep:nR;

        set(axHeat, ...
            'XTick',tickIdx, ...
            'YTick',tickIdx, ...
            'XTickLabel',fc_abbrev_list(names(tickIdx),10), ...
            'YTickLabel',fc_abbrev_list(names(tickIdx),10), ...
            'TickLength',[0 0]);

        try, xtickangle(axHeat,90); catch, end

        if nR <= 50
            set(axHeat,'FontSize',10,'FontWeight','bold');
        elseif nR <= 100
            set(axHeat,'FontSize',8,'FontWeight','bold');
        else
            set(axHeat,'FontSize',7,'FontWeight','normal');
        end

        fc_colorbar_legend(axHeatCB,cmap,clim,cbLabel,C);
        updateROIDropdowns(names);

        set(txtHeat,'String',sprintf([ ...
            'Regions: %d\n\n' ...
            'Value: %s\n' ...
            'Threshold: %.2f\n\n' ...
            'Labels are abbreviated.\n' ...
            'Increase threshold to simplify dense maps.'], ...
            numel(names),cbLabel,s.roiAbsThr));
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

        [M,names,order] = fc_current_matrix(s,res);
        updateROIDropdowns(names);
        sel = fc_clip(get(ddCompareROI,'Value'),1,numel(names));
        rawSel = order(sel);
        r = M(sel,:);
        r(sel) = NaN;
        [idxShow,valShow] = fc_rank_vector(r,s.compareTopN,s.compareSort,names);

        if isempty(idxShow)
            fc_nodata(axCompareBar,'Selected ROI vs all regions',C);
        else
            barh(axCompareBar,valShow,'FaceColor',[0.30 0.65 1.00],'EdgeColor',[0.15 0.35 0.80]);
            fc_ax(axCompareBar,C); grid(axCompareBar,'on');
            xlabel(axCompareBar,'Pearson r to selected region','Color',C.dim);
            ylabel(axCompareBar,'Partner region','Color',C.dim);
            title(axCompareBar,['Selected ROI vs all regions: ' fc_roi_abbrev(names{sel},18)], ...
                'Color',C.fg,'Interpreter','none');
            set(axCompareBar,'YTick',1:numel(idxShow),'YTickLabel',fc_abbrev_list(names(idxShow),18));
            xlim(axCompareBar,[-1 1]);
        end

        [mapS,ok] = fc_compare_slice(s);
        if ok
            hCmpImg = imagesc(axCompareMap,mapS,[-1 1]);
            set(hCmpImg,'ButtonDownFcn',@onCompareMapClick);
            set(axCompareMap,'ButtonDownFcn',@onCompareMapClick);
            axis(axCompareMap,'image'); axis(axCompareMap,'ij'); axis(axCompareMap,'off');
            colormap(axCompareMap,cmap);
            title(axCompareMap,'Click a region to benchmark it','Color',C.fg,'Interpreter','none');
            try
                subjNow = s.subjects(s.currentSubject);
                fc_draw_roi_abbrev_on_map(axCompareMap,subjNow.roiAtlas(:,:,s.slice),res.labels,res.names,C);
            catch
            end
        else
            fc_nodata(axCompareMap,'Atlas correlation map',C);
        end

        t = ((0:size(res.meanTS,1)-1) * s.subjects(s.currentSubject).TR) / 60;
        plot(axCompareTS,t,fc_z(res.meanTS(:,rawSel)),'LineWidth',1.8,'Color',[0.2 0.75 1.0]);
        hold(axCompareTS,'on');
        if ~isempty(idxShow)
            rawBest = order(idxShow(1));
            plot(axCompareTS,t,fc_z(res.meanTS(:,rawBest)),'LineWidth',1.4,'Color',[1.0 0.55 0.2]);
            legend(axCompareTS,{fc_roi_abbrev(names{sel},16),fc_roi_abbrev(names{idxShow(1)},16)}, ...
                'Location','best','TextColor',C.fg);
        end
        hold(axCompareTS,'off');
        fc_ax(axCompareTS,C); grid(axCompareTS,'on');
        xlabel(axCompareTS,'Time (min)','Color',C.dim);
        ylabel(axCompareTS,'Z-scored signal','Color',C.dim);
        title(axCompareTS,'Selected ROI and strongest partner','Color',C.fg,'Interpreter','none');

        if isempty(idxShow)
            txtTop = 'none';
        else
            nList = min(6,numel(idxShow));
            lines = cell(nList,1);
            for k = 1:nList
                lines{k} = sprintf('%s: r = %.3f',fc_roi_abbrev(names{idxShow(k)},16),valShow(k));
            end
            txtTop = fc_join(lines);
        end
        set(txtCompare,'String',sprintf('Selected: %s\nAtlas label: %g\nTop partners:\n%s', ...
            fc_roi_abbrev(names{sel},20),res.labels(rawSel),txtTop));
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
        [~,names,order] = fc_current_matrix(s,res);
        updateROIDropdowns(names);
        aSel = fc_clip(get(ddPairA,'Value'),1,numel(names));
        bSel = fc_clip(get(ddPairB,'Value'),1,numel(names));
        a = order(aSel); b = order(bSel);
        ta = double(res.meanTS(:,a)); tb = double(res.meanTS(:,b));
        t = ((0:numel(ta)-1) * s.subjects(s.currentSubject).TR) / 60;
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
        legend(axPairTS,{fc_roi_abbrev(names{aSel},16),fc_roi_abbrev(names{bSel},16)},'Location','best','TextColor',C.fg);

        scatter(axPairScat,fc_z(ta),fc_z(tb),24,colA,'filled');
        fc_ax(axPairScat,C); grid(axPairScat,'on');
        xlabel(axPairScat,['Z(' fc_roi_abbrev(names{aSel},16) ')'],'Color',C.dim,'Interpreter','none');
        ylabel(axPairScat,['Z(' fc_roi_abbrev(names{bSel},16) ')'],'Color',C.dim,'Interpreter','none');
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
            fc_roi_abbrev(names{aSel},20),fc_roi_abbrev(names{bSel},20),r));
    end

    function refreshGraphView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        try
            set(axAdj,     'Position',[0.045 0.160 0.785 0.735]);
            set(axGraphCB, 'Position',[0.855 0.205 0.030 0.665]);
            set(axDeg,     'Visible','off');
            set(txtGraph,  'Position',[0.900 0.205 0.085 0.665]);
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

        [M,names] = fc_current_matrix(s,res);

        A = abs(M) >= s.roiAbsThr;
        A(1:size(A,1)+1:end) = false;

        W = M;
        W(~A) = 0;

        imagesc(axAdj,W,[-1 1]);
        axis(axAdj,'image');
        colormap(axAdj,cmap);
        fc_ax(axAdj,C);

        title(axAdj,'Thresholded weighted FC matrix', ...
            'Color',C.fg, ...
            'Interpreter','none', ...
            'FontWeight','bold');
        xlabel(axAdj,'Atlas region','Color',C.dim,'FontWeight','bold');
        ylabel(axAdj,'Atlas region','Color',C.dim,'FontWeight','bold');

        nG = size(W,1);
        if nG <= 35
            tickStep = 1;
        elseif nG <= 70
            tickStep = 2;
        elseif nG <= 120
            tickStep = 4;
        elseif nG <= 200
            tickStep = 6;
        else
            tickStep = max(8,ceil(nG/30));
        end
        tickIdx = 1:tickStep:nG;

        set(axAdj, ...
            'XTick',tickIdx, ...
            'YTick',tickIdx, ...
            'XTickLabel',fc_abbrev_list(names(tickIdx),10), ...
            'YTickLabel',fc_abbrev_list(names(tickIdx),10), ...
            'TickLength',[0 0]);

        try, xtickangle(axAdj,90); catch, end

        if nG <= 50
            set(axAdj,'FontSize',10,'FontWeight','bold');
        elseif nG <= 100
            set(axAdj,'FontSize',8,'FontWeight','bold');
        else
            set(axAdj,'FontSize',7,'FontWeight','normal');
        end

        fc_colorbar_legend(axGraphCB,cmap,[-1 1],'Pearson r',C);

        nEdges = nnz(triu(A,1));
        possibleEdges = max(1,(size(A,1)*(size(A,1)-1)/2));
        density = nEdges / possibleEdges;

        set(txtGraph,'String',sprintf([ ...
            'Graph matrix\n\n' ...
            'Entry = Pearson r\n' ...
            'shown only when |r| >= threshold.\n\n' ...
            'Threshold: %.2f\n' ...
            'Regions: %d\n' ...
            'Connections: %d\n' ...
            'Density: %.4f'], ...
            s.roiAbsThr,nG,nEdges,density));
    end

    function updateROIDropdowns(names)
        if isempty(names)
            names = {'n/a'};
        end
        namesDisplay = fc_abbrev_list(names,18);
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
        [M,~,order] = fc_current_matrix(s,res);
        sel = fc_clip(get(ddCompareROI,'Value'),1,numel(order));
        valsOrdered = M(sel,:);
        valsRaw = nan(numel(res.labels),1);
        valsRaw(order) = valsOrdered;
        atlasS = double(subj.roiAtlas(:,:,s.slice));
        mapS = nan(size(atlasS));
        for k = 1:numel(res.labels)
            mapS(atlasS == res.labels(k)) = valsRaw(k);
        end
        if ~isempty(subj.mask), mapS(~subj.mask(:,:,s.slice)) = NaN; end
        ok = true;
    end
end

% =========================================================================
% HELPER FUNCTIONS
% =========================================================================
function p = fc_panel(parent,pos,titleStr,C)
p = uipanel('Parent',parent,'Units','normalized','Position',pos, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title',titleStr,'FontName',C.font,'FontWeight','bold','FontSize',13);
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
if ~isfield(opts,'functionalField'), opts.functionalField = ''; end
if ~isfield(opts,'roiNames'), opts.roiNames = {}; end
if ~isfield(opts,'roiNameTable'), opts.roiNameTable = struct('labels',[],'names',{{}}); end
if ~isfield(opts,'roiMinVox') || isempty(opts.roiMinVox), opts.roiMinVox = 9; end
if ~isfield(opts,'seedBoxSize') || isempty(opts.seedBoxSize), opts.seedBoxSize = 5; end
if ~isfield(opts,'chunkVox') || isempty(opts.chunkVox), opts.chunkVox = 6000; end
if ~isfield(opts,'askMaskAtStart') || isempty(opts.askMaskAtStart), opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart), opts.askAtlasAtStart = true; end
if ~isfield(opts,'debugRethrow') || isempty(opts.debugRethrow), opts.debugRethrow = false; end
if ~isfield(opts,'defaultUnderlayMode') || isempty(opts.defaultUnderlayMode), opts.defaultUnderlayMode = 'scm'; end
if ~isfield(opts,'anatIsDisplayReady') || isempty(opts.anatIsDisplayReady), opts.anatIsDisplayReady = false; end
if ~isfield(opts,'defaultUnderlayViewMode') || isempty(opts.defaultUnderlayViewMode), opts.defaultUnderlayViewMode = 5; end
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
    preferred = {'roiAtlas','atlas','regions','annotation','labels','labelVolume','area'};
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
T = struct('labels',[],'names',{{}});
[~,~,ext] = fileparts(fullf); ext = lower(ext);
if strcmp(ext,'.mat')
    S = load(fullf); T = fc_region_names_from_mat(S); return;
end
fid = fopen(fullf,'r');
if fid < 0, error('Could not open region-name file.'); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
labels = []; names = {};
while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line), continue; end
    line = strtrim(line);
    if isempty(line), continue; end
    if line(1)=='#' || line(1)=='%', continue; end
    line = strrep(line,char(9),','); line = strrep(line,';',',');
    parts = regexp(line,',','split');
    if numel(parts) < 2, parts = regexp(line,'\s+','split'); end
    if numel(parts) < 2, continue; end
    lab = str2double(strtrim(parts{1}));
    if ~isfinite(lab), continue; end
    nm = strtrim(parts{2});
    if numel(parts) > 2
        for k = 3:numel(parts)
            pk = strtrim(parts{k}); if ~isempty(pk), nm = [nm ' ' pk]; end %#ok<AGROW>
        end
    end
    labels(end+1,1) = lab; %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
end
T.labels = labels; T.names = names;
end

function T = fc_region_names_from_mat(S)
T = struct('labels',[],'names',{{}});
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
V = Y*X*Z; D = reshape(I4,[V size(I4,4)]);
atlasV = atlas(:); maskV = mask(:);
labels = unique(atlasV(maskV & atlasV > 0)); labels = labels(:);
if isempty(labels), error('No atlas labels inside mask.'); end
keepLabels = []; names = {}; counts = []; meanTS = [];
for k = 1:numel(labels)
    lab = labels(k); idx = find(maskV & atlasV == lab);
    if numel(idx) < opts.roiMinVox, continue; end
    ts = mean(double(D(idx,:)),1)';
    keepLabels(end+1,1) = lab; %#ok<AGROW>
    counts(end+1,1) = numel(idx); %#ok<AGROW>
    names{end+1,1} = fc_roi_name(lab,opts); %#ok<AGROW>
    meanTS(:,end+1) = ts; %#ok<AGROW>
end
if isempty(keepLabels), error('No ROI survived roiMinVox.'); end
M = fc_corr_matrix(meanTS);
res = struct(); res.labels = keepLabels; res.names = names; res.counts = counts; res.meanTS = meanTS; res.M = M; res.TR = TR;
end

function M = fc_corr_matrix(X)
X = double(X); X = bsxfun(@minus,X,mean(X,1));
sd = std(X,0,1); sd(sd <= 0 | ~isfinite(sd)) = 1;
X = bsxfun(@rdivide,X,sd);
M = (X' * X) / max(1,size(X,1)-1);
M = max(-1,min(1,M)); M(1:size(M,1)+1:end) = 1;
end

function [M,names,order] = fc_current_matrix(s,res)
M0 = res.M; names0 = res.names; labels = res.labels;
switch lower(s.roiOrder)
    case 'name'
        [~,order] = sort(lower(names0));
    otherwise
        [~,order] = sort(labels);
end
M = M0(order,order); names = names0(order);
end

function name = fc_roi_name(label,opts)
name = sprintf('ROI_%03d',label);
try
    T = opts.roiNameTable;
    if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
        idx = find(double(T.labels(:)) == double(label),1,'first');
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
subj = s.subjects(s.currentSubject); atlasS = [];
if ~isempty(subj.roiAtlas), atlasS = double(subj.roiAtlas(:,:,s.slice)); end
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
cla(ax);
pos = get(ax,'Position');
isVertical = numel(pos) >= 4 && pos(4) > pos(3) * 2;

if isVertical
    img = reshape(size(cmap,1):-1:1,[],1);
    imagesc(ax,img);
    set(ax, ...
        'YDir','reverse', ...
        'XTick',[], ...
        'YTick',[1 size(cmap,1)], ...
        'YTickLabel',{num2str(clim(2),'%.2g'), num2str(clim(1),'%.2g')}, ...
        'XColor',C.dim, ...
        'YColor',C.dim, ...
        'Color',C.bgPane, ...
        'FontSize',10, ...
        'FontWeight','bold');
    ylabel(ax,labelStr, ...
        'Color',C.fg, ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Interpreter','none');
else
    img = reshape(1:size(cmap,1),1,[]);
    imagesc(ax,img);
    set(ax, ...
        'YTick',[], ...
        'XTick',[1 size(cmap,1)], ...
        'XTickLabel',{num2str(clim(1),'%.2g'),num2str(clim(2),'%.2g')}, ...
        'XColor',C.dim, ...
        'YColor',C.dim, ...
        'Color',C.bgPane, ...
        'FontSize',10, ...
        'FontWeight','bold');
    title(ax,labelStr, ...
        'Color',C.fg, ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Interpreter','none');
end
colormap(ax,cmap);
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
[M,names,order] = fc_current_matrix(s,res);
sel = fc_clip(s.compareROI,1,numel(names));
vals = M(sel,:)'; labels = res.labels(order);
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

function x = fc_prctile(a,p)
a = double(a(:)); a = a(isfinite(a));
if isempty(a), x = NaN; return; end
a = sort(a);
if numel(a)==1, x = a; return; end
t = (p/100) * (numel(a)-1) + 1; i1 = floor(t); i2 = ceil(t);
if i1 == i2, x = a(i1); else, w = t - i1; x = (1-w)*a(i1) + w*a(i2); end
end

function fc_ax(ax,C)
set(ax,'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim,'FontSize',10);
end

function fc_nodata(ax,titleStr,C)
cla(ax);
text(ax,0.5,0.5,'No data','HorizontalAlignment','center','Color',C.fg,'FontSize',12,'FontWeight','bold');
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

function out = fc_abbrev_list(c,n)
if nargin < 2, n = 12; end
out = c;
for i = 1:numel(out)
    out{i} = fc_roi_abbrev(out{i},n);
end
end

function ab = fc_roi_abbrev(name,n)
if nargin < 2, n = 12; end
s = strtrim(char(name));
s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
parts = regexp(s,'\s+','split');
if isempty(parts)
    ab = s;
else
    ab = strtrim(parts{1});
end
if isempty(ab), ab = s; end
if numel(ab) > n
    ab = [ab(1:max(1,n-3)) '...'];
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

function fc_draw_roi_abbrev_on_map(ax,atlasS,labels,names,C)
try
    labsInSlice = unique(double(atlasS(:)));
    labsInSlice = labsInSlice(isfinite(labsInSlice) & labsInSlice > 0);
    labsInSlice = intersect(labsInSlice,double(labels(:)));
    if isempty(labsInSlice) || numel(labsInSlice) > 60
        return;
    end
    hold(ax,'on');
    for ii = 1:numel(labsInSlice)
        lab = labsInSlice(ii);
        idx = find(double(labels(:)) == lab,1,'first');
        if isempty(idx) || idx > numel(names), continue; end
        [yy,xx] = find(double(atlasS) == lab);
        if numel(xx) < 12, continue; end
        x = median(xx); y = median(yy);
        text(ax,x,y,fc_roi_abbrev(names{idx},8), ...
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
