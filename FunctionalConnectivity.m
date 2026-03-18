function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity.m
% Full self-contained functional connectivity GUI for fUSI Studio
% MATLAB 2017b compatible
% ASCII-safe / UTF-8-safe plain text only
%
% MAIN PURPOSES
%   1) Seed-based voxelwise FC
%   2) ROI-to-ROI FC using an ROI atlas
%   3) Group statistics across animals / conditions
%   4) Seed placement using anatomical underlay or functional overlay
%   5) Time-windowed FC (before / during / after injection, etc.)
%
% INPUTS
%   dataIn can be:
%     - numeric [Y X T] or [Y X Z T]
%     - struct with a functional data field and optional metadata
%     - struct array
%     - cell array of numerics / structs
%
%   Functional data fields searched automatically:
%     I, PSC, data, functional, func, movie, brain, img, volume
%
%   Optional per-subject fields:
%     TR, mask, anat, roiAtlas, name, group, pairID,
%     loadedPath, analysisDir, analysedDir, filePath, sourcePath
%
%   opts optional fields:
%     .statusFcn       function handle; called with false on open, true on close
%     .logFcn          function handle for logs
%     .askMaskAtStart  default true
%     .askAtlasAtStart default true
%     .askDataFieldAtStart default true
%     .seedRadius      default 1
%     .chunkVox        default 6000
%     .useSliceOnly    default false
%     .roiMinVox       default 9
%     .roiAbsThr       default 0.20
%     .rvVarExplained  default 0.20
%     .pcaN            default 5
%     .icaN            default 5
%     .roiNames        optional mapping of label->name
%     .roiOntology     optional ordering metadata
%     .functionalField optional exact field name to use
%     .datasetName     optional fallback dataset label
%     .debugRethrow    default false
%
% NOTE
%   This file is intentionally fully self-contained. Do not remove helper
%   functions at the bottom.

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4 || isempty(opts), opts = struct(); end
opts = normalizeOpts(opts);
opts.saveRoot = saveRoot;

subjects = normalizeSubjects(dataIn, opts);
if isempty(subjects)
    error('FunctionalConnectivity: No valid subjects found.');
end
nSub = numel(subjects);

[Y, X, Z] = getSpatialSize(subjects(1).I4);
for i = 2:nSub
    [Yi, Xi, Zi] = getSpatialSize(subjects(i).I4);
    if Yi ~= Y || Xi ~= X || Zi ~= Z
        error('FunctionalConnectivity: All subjects must have identical spatial dimensions.');
    end
end

[subjects, startupMaskInfo] = applyStartupMaskStrategy(subjects, opts);

if isempty(subjects(1).roiAtlas) && opts.askAtlasAtStart
    [atlasLoaded, okAtlas] = maybeLoadCommonAtlas(subjects);
    if okAtlas
        for i = 1:nSub
            subjects(i).roiAtlas = atlasLoaded;
        end
    end
end

st = struct();
st.subjects = subjects;
st.nSub = nSub;
st.currentSubject = 1;
st.Y = Y; st.X = X; st.Z = Z;
st.slice = max(1, round(Z/2));
st.seedX = round(X/2);
st.seedY = round(Y/2);
st.seedR = max(0, round(opts.seedRadius));
st.useSliceOnly = logical(opts.useSliceOnly);
st.seedMapMode = 'z';
st.seedDisplayMode = 'fc';
st.underlayMode = 'mean';
st.placementMode = 'window_mean';
st.seedAbsThr = 0.20;
st.seedAlpha = 0.70;
st.placementAlpha = 0.55;
st.roiMethod = 'mean_pearson';
st.roiAbsThr = opts.roiAbsThr;
st.reorderMode = 'none';
st.groupTarget = 'seed';
st.groupTest = 'one_sample_t';
st.groupAlpha = 0.05;
st.groupNames = uniqueCellstr({subjects.group});
if isempty(st.groupNames), st.groupNames = {'All'}; end
st.groupA = 1;
st.groupB = min(2, numel(st.groupNames));
st.seedResults = cell(nSub,1);
st.roiResults = cell(nSub,1);
st.compResults = cell(nSub,1);
st.groupSeedStats = [];
st.groupRoiStats = [];
st.seedTSColor = [0.20 0.75 1.00];
st.seedHistColor = [0.20 0.65 1.00];
st.datasetName = opts.datasetName;
st.tag = tag;
st.opts = opts;
st.startupMaskInfo = startupMaskInfo;
st.fcCmap = blueWhiteRed(256);
st.subjectNames = {subjects.name}';
st.analysisSecStart = 0;
st.analysisSecEnd = inf;
st.baseSecStart = 0;
st.baseSecEnd = 60;
st.signalSecStart = 60;
st.signalSecEnd = 120;
st.qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(st.qcDir, 'dir'), mkdir(st.qcDir); end

if ~isempty(opts.statusFcn)
    try
        opts.statusFcn(false);
    catch
    end
end

bgFig  = [0.05 0.05 0.06];
bgPane = [0.08 0.08 0.09];
bgAx   = [0.10 0.10 0.11];
fg     = [0.94 0.94 0.96];
fgDim  = [0.76 0.76 0.80];
accent = [0.20 0.65 1.00];
goodC  = [0.20 0.72 0.32];
warnC  = [1.00 0.35 0.35];
neutralBtn = [0.24 0.24 0.28];
greenBtn = [0.16 0.54 0.24];
blueBtn = [0.12 0.40 0.82];
redBtn  = [0.70 0.20 0.20];

scr = get(0,'ScreenSize');
fig = figure('Name','fUSI Studio - Functional Connectivity', ...
    'Color',bgFig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Units','pixels', ...
    'Position',scr, ...
    'CloseRequestFcn',@onCloseFigure);
try, set(fig,'Renderer','opengl'); catch, end
try, set(fig,'WindowState','maximized'); catch, end

panelCtrl = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.010 0.02 0.355 0.96], ...
    'BackgroundColor',bgPane, ...
    'ForegroundColor',fg, ...
    'Title','Controls', ...
    'FontWeight','bold','FontSize',13);

panelViewWrap = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.372 0.02 0.618 0.96], ...
    'BackgroundColor',bgPane, ...
    'ForegroundColor',fg, ...
    'Title','Views', ...
    'FontWeight','bold','FontSize',13);

pSubject = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.79 0.96 0.18], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','Subject / Display','FontWeight','bold','FontSize',12);
pWindows = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.61 0.96 0.16], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','Time Windows','FontWeight','bold','FontSize',12);
pSeed = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.36 0.96 0.23], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','Seed FC / Placement','FontWeight','bold','FontSize',12);
pROI = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.24 0.96 0.10], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','ROI FC','FontWeight','bold','FontSize',12);
pStats = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.08 0.96 0.14], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','Group Statistics','FontWeight','bold','FontSize',12);
pActions = uipanel('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.02 0.01 0.96 0.06], ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'Title','Actions','FontWeight','bold','FontSize',12);

% Subject / Display controls
uicontrol('Parent',pSubject,'Style','text','Units','normalized', ...
    'Position',[0.03 0.80 0.25 0.12], 'String','Current subject', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddSubject = uicontrol('Parent',pSubject,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.63 0.94 0.14], 'String',st.subjectNames, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onSubjectChanged);

uicontrol('Parent',pSubject,'Style','text','Units','normalized', ...
    'Position',[0.03 0.43 0.18 0.12], 'String','Underlay', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddUnder = uicontrol('Parent',pSubject,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.27 0.40 0.14], 'String',underlayList(st.subjects(1).anat), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onUnderlayChanged);

uicontrol('Parent',pSubject,'Style','text','Units','normalized', ...
    'Position',[0.48 0.43 0.18 0.12], 'String','Slice (Z)', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
slZ = uicontrol('Parent',pSubject,'Style','slider','Units','normalized', ...
    'Position',[0.48 0.29 0.30 0.07], 'Min',1,'Max',max(1,Z),'Value',st.slice, ...
    'SliderStep',sliderStep(Z), 'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onSliceChanged);
edZ = uicontrol('Parent',pSubject,'Style','edit','Units','normalized', ...
    'Position',[0.81 0.27 0.16 0.12], 'String',sprintf('%d',st.slice), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onSliceEdit);

btnLoadDataset = uicontrol('Parent',pSubject,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.05 0.28 0.13], 'String','Load Dataset', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onLoadDataset);
btnLoadMask = uicontrol('Parent',pSubject,'Style','pushbutton','Units','normalized', ...
    'Position',[0.35 0.05 0.28 0.13], 'String','Load Mask', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onLoadMask);
btnLoadAtlas = uicontrol('Parent',pSubject,'Style','pushbutton','Units','normalized', ...
    'Position',[0.67 0.05 0.30 0.13], 'String','Load ROI Atlas', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onLoadAtlas);

% Time windows controls
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.03 0.78 0.35 0.12], 'String','Analysis window (sec)', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.03 0.52 0.08 0.12], 'String','Start', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.23 0.52 0.08 0.12], 'String','End', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
edAnaStart = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.10 0.48 0.10 0.16], 'String','0', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);
edAnaEnd = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.30 0.48 0.12 0.16], 'String','inf', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);

uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.48 0.78 0.35 0.12], 'String','Baseline / signal (sec)', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.48 0.52 0.08 0.12], 'String','B0', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.60 0.52 0.08 0.12], 'String','B1', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.72 0.52 0.08 0.12], 'String','S0', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.84 0.52 0.08 0.12], 'String','S1', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);
edBaseStart = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.48 0.48 0.10 0.16], 'String','0', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);
edBaseEnd = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.60 0.48 0.10 0.16], 'String','60', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);
edSigStart = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.72 0.48 0.10 0.16], 'String','60', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);
edSigEnd = uicontrol('Parent',pWindows,'Style','edit','Units','normalized', ...
    'Position',[0.84 0.48 0.10 0.16], 'String','120', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onWindowEdit);

uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.03 0.12 0.25 0.14], 'String','Placement overlay', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
ddPlacementMode = uicontrol('Parent',pWindows,'Style','popupmenu','Units','normalized', ...
    'Position',[0.28 0.10 0.32 0.18], 'String',{'Window mean','Signal - baseline'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onPlacementModeChanged);

uicontrol('Parent',pWindows,'Style','text','Units','normalized', ...
    'Position',[0.66 0.12 0.12 0.14], 'String','Alpha', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
slPlacementAlpha = uicontrol('Parent',pWindows,'Style','slider','Units','normalized', ...
    'Position',[0.74 0.12 0.20 0.08], 'Min',0,'Max',1,'Value',st.placementAlpha, ...
    'SliderStep',[0.02 0.10], 'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onPlacementAlpha);

% Seed controls
uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.03 0.83 0.08 0.10], 'String','X', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
edSeedX = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.08 0.80 0.12 0.12], 'String',sprintf('%d',st.seedX), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onSeedXYEdit);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.24 0.83 0.08 0.10], 'String','Y', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
edSeedY = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.29 0.80 0.12 0.12], 'String',sprintf('%d',st.seedY), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onSeedXYEdit);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.45 0.83 0.12 0.10], 'String','Radius', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
edR = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.56 0.80 0.12 0.12], 'String',sprintf('%d',st.seedR), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onRadiusEdit);

cbSliceOnly = uicontrol('Parent',pSeed,'Style','checkbox','Units','normalized', ...
    'Position',[0.74 0.82 0.23 0.10], 'String','Slice only', ...
    'Value',st.useSliceOnly, 'BackgroundColor',bgPane, ...
    'ForegroundColor',fgDim, 'FontSize',10, 'Callback',@onComputeModeChanged);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.03 0.64 0.16 0.10], 'String','Display', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddSeedDisplay = uicontrol('Parent',pSeed,'Style','popupmenu','Units','normalized', ...
    'Position',[0.16 0.62 0.26 0.12], 'String',{'FC overlay','Placement overlay'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onSeedDisplayMode);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.48 0.64 0.16 0.10], 'String','Map type', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
bgMap = uibuttongroup('Parent',pSeed,'Units','normalized', ...
    'Position',[0.62 0.56 0.35 0.18], 'BackgroundColor',bgPane, ...
    'SelectionChangedFcn',@onMapModeChanged);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.05 0.10 0.42 0.80], 'String','Fisher z', 'Value',1, ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, 'FontSize',10);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.53 0.10 0.42 0.80], 'String','Pearson r', 'Value',0, ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, 'FontSize',10);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.03 0.40 0.30 0.08], 'String','FC threshold |r|', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
slThr = uicontrol('Parent',pSeed,'Style','slider','Units','normalized', ...
    'Position',[0.03 0.33 0.44 0.06], 'Min',0,'Max',0.99,'Value',st.seedAbsThr, ...
    'SliderStep',[0.01 0.10], 'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onThrChanged);
txtThr = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.03 0.27 0.24 0.05], 'String',sprintf('|r| >= %.2f',st.seedAbsThr), ...
    'BackgroundColor',bgPane,'ForegroundColor',accent, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.56 0.40 0.18 0.08], 'String','FC alpha', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
slAlpha = uicontrol('Parent',pSeed,'Style','slider','Units','normalized', ...
    'Position',[0.56 0.33 0.41 0.06], 'Min',0,'Max',1,'Value',st.seedAlpha, ...
    'SliderStep',[0.02 0.10], 'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onAlphaChanged);

btnTSColor = uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.12 0.22 0.11], 'String','Trace Color', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onTraceColor);
btnHistColor = uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.28 0.12 0.22 0.11], 'String','Hist Color', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onHistColor);

txtSeed = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.55 0.10 0.42 0.12], 'String',seedString(st), ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

% ROI controls
uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.03 0.56 0.16 0.24], 'String','ROI method', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddRoiMethod = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.18 0.54 0.28], 'String',roiMethodList(), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onRoiMethodChanged);

uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.62 0.56 0.14 0.24], 'String','Threshold', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
edRoiThr = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.62 0.18 0.12 0.28], 'String',sprintf('%.2f',st.roiAbsThr), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onRoiThrEdit);

uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.80 0.56 0.12 0.24], 'String','Reorder', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
ddReorder = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.80 0.18 0.16 0.28], 'String',{'None','Label','Ontology'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onReorderChanged);

% Group stats controls
uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.03 0.72 0.12 0.16], 'String','Target', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddGroupTarget = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.50 0.26 0.18], 'String',{'Seed maps','ROI edges'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onGroupTargetChanged);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.34 0.72 0.16 0.16], 'String','alpha / q', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
edAlpha = uicontrol('Parent',pStats,'Style','edit','Units','normalized', ...
    'Position',[0.45 0.50 0.12 0.18], 'String',sprintf('%.3f',st.groupAlpha), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onAlphaEdit);

ddGroupTest = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.24 0.94 0.18], 'String',groupTestList(), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onGroupTestChanged);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.03 0.02 0.10 0.14], 'String','A', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
ddGroupA = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.08 0.02 0.36 0.16], 'String',st.groupNames, ...
    'Value',st.groupA, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'FontSize',10, 'Callback',@onGroupAChanged);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.52 0.02 0.10 0.14], 'String','B', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
ddGroupB = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.57 0.02 0.40 0.16], 'String',st.groupNames, ...
    'Value',st.groupB, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'FontSize',10, 'Callback',@onGroupBChanged);

% Actions controls
btnComputeSeed = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.01 0.18 0.16 0.58], 'String','Compute Seed', ...
    'BackgroundColor',greenBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, 'Callback',@onComputeSeed);
btnComputeROI = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.19 0.18 0.16 0.58], 'String','Compute ROI', ...
    'BackgroundColor',greenBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, 'Callback',@onComputeROI);
btnComputeGroup = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.37 0.18 0.18 0.58], 'String','Compute Group', ...
    'BackgroundColor',greenBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, 'Callback',@onComputeGroup);
btnComputeComp = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.57 0.18 0.16 0.58], 'String','PCA / ICA', ...
    'BackgroundColor',greenBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, 'Callback',@onComputeComp);
btnSave = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.75 0.18 0.10 0.58], 'String','Save', ...
    'BackgroundColor',neutralBtn,'ForegroundColor',fg, ...
    'FontWeight','bold','FontSize',10, 'Callback',@onSave);
btnHelp = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.86 0.18 0.06 0.58], 'String','?', ...
    'BackgroundColor',blueBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',11, 'Callback',@onHelp);
btnClose = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.93 0.18 0.06 0.58], 'String','X', ...
    'BackgroundColor',redBtn,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',11, 'Callback',@onCloseFigure);

txtStatus = uicontrol('Parent',pActions,'Style','text','Units','normalized', ...
    'Position',[0.01 0.02 0.98 0.12], ...
    'String','Ready. Click in the Seed view to place a seed and start.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);

% View tab buttons
btnSeedTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.02 0.94 0.13 0.04], 'String','Seed', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('Seed'));
btnROITab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.16 0.94 0.13 0.04], 'String','ROI', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('ROI'));
btnPairTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.30 0.94 0.13 0.04], 'String','Pair', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('Pair'));
btnGroupTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.44 0.94 0.13 0.04], 'String','Group', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('Group'));
btnGraphTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.58 0.94 0.13 0.04], 'String','Graph', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('Graph'));
btnCompTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.72 0.94 0.13 0.04], 'String','Components', ...
    'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'Callback',@(src,evt)switchPanel('Components'));

panelSeedView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none');
panelROIView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none', 'Visible','off');
panelPairView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none', 'Visible','off');
panelGroupView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none', 'Visible','off');
panelGraphView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none', 'Visible','off');
panelCompView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], 'BackgroundColor',bgPane, ...
    'BorderType','none', 'Visible','off');

% Seed view axes
axSeedMap = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.03 0.10 0.55 0.78], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
axis(axSeedMap,'image'); axis(axSeedMap,'off');
axSeedTS = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.66 0.58 0.30 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axSeedTS,'on');
axSeedHist = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.66 0.18 0.30 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axSeedHist,'on');
hUnder = imagesc(axSeedMap, getUnderlaySlice(st));
colormap(axSeedMap, gray(256));
hold(axSeedMap,'on');
hOver = imagesc(axSeedMap, nan(st.Y, st.X, 3));
set(hOver,'AlphaData',0);
hCross1 = line(axSeedMap, [1 st.X], [st.seedY st.seedY], 'Color',warnC, 'LineWidth',1.0);
hCross2 = line(axSeedMap, [st.seedX st.seedX], [1 st.Y], 'Color',warnC, 'LineWidth',1.0);
hold(axSeedMap,'off');
set(hUnder,'ButtonDownFcn',@onMapClick);
set(hOver,'ButtonDownFcn',@onMapClick);
set(axSeedMap,'ButtonDownFcn',@onMapClick);

% ROI view axes
axRoiMat = axes('Parent',panelROIView,'Units','normalized', ...
    'Position',[0.05 0.14 0.55 0.76], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
axRoiTS = axes('Parent',panelROIView,'Units','normalized', ...
    'Position',[0.66 0.55 0.29 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axRoiTS,'on');
txtRoiInfo = uicontrol('Parent',panelROIView,'Style','text','Units','normalized', ...
    'Position',[0.65 0.14 0.30 0.28], 'String','ROI FC not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% Pair view axes
uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.08 0.03], 'String','ROI A', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddPairA = uicontrol('Parent',panelPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.14 0.93 0.32 0.035], 'String',{'n/a'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onPairPopup);
uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.52 0.93 0.08 0.03], 'String','ROI B', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddPairB = uicontrol('Parent',panelPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.61 0.93 0.32 0.035], 'String',{'n/a'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onPairPopup);
txtPairInfo = uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.82 0.90 0.08], 'String','ROI pair view not ready yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);
axPairTS = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.08 0.50 0.84 0.22], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axPairTS,'on');
axPairScatter = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.08 0.15 0.36 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axPairScatter,'on');
axPairLag = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.55 0.15 0.36 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axPairLag,'on');

% Group view axes
axGroupMain = axes('Parent',panelGroupView,'Units','normalized', ...
    'Position',[0.05 0.14 0.56 0.76], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
axGroupAux = axes('Parent',panelGroupView,'Units','normalized', ...
    'Position',[0.68 0.56 0.26 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axGroupAux,'on');
txtGroupInfo = uicontrol('Parent',panelGroupView,'Style','text','Units','normalized', ...
    'Position',[0.66 0.14 0.30 0.30], 'String','Group statistics not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% Graph view axes
axAdj = axes('Parent',panelGraphView,'Units','normalized', ...
    'Position',[0.05 0.15 0.42 0.74], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
axDeg = axes('Parent',panelGraphView,'Units','normalized', ...
    'Position',[0.57 0.58 0.33 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axDeg,'on');
txtGraphInfo = uicontrol('Parent',panelGraphView,'Style','text','Units','normalized', ...
    'Position',[0.55 0.16 0.38 0.30], 'String','Graph view not ready yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% Components view axes
uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.08 0.03], 'String','Type', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddCompType = uicontrol('Parent',panelCompView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.12 0.93 0.16 0.035], 'String',{'PCA','ICA'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onCompSelector);
uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.34 0.93 0.12 0.03], 'String','Component', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
ddCompIdx = uicontrol('Parent',panelCompView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.46 0.93 0.16 0.035], 'String',{'1'}, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'FontSize',10, 'Callback',@onCompSelector);
axCompMap = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.05 0.18 0.40 0.68], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
axCompTS = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.57 0.55 0.34 0.24], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axCompTS,'on');
axCompAux = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.57 0.18 0.34 0.22], 'Color',bgAx, ...
    'XColor',fgDim,'YColor',fgDim);
grid(axCompAux,'on');
txtCompInfo = uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.04 0.86 0.08], 'String','Components not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

guidata(fig, st);
switchPanel('Seed');
refreshAll();

% ========================= nested callbacks =========================
    function onCloseFigure(~,~)
        try
            stLocal = guidata(fig);
            if ~isempty(stLocal.opts.statusFcn)
                stLocal.opts.statusFcn(true);
            end
        catch
        end
        delete(fig);
    end

    function switchPanel(name)
        set(panelSeedView,'Visible','off');
        set(panelROIView,'Visible','off');
        set(panelPairView,'Visible','off');
        set(panelGroupView,'Visible','off');
        set(panelGraphView,'Visible','off');
        set(panelCompView,'Visible','off');
        set(btnSeedTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnROITab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnPairTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnGroupTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnGraphTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnCompTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        switch lower(name)
            case 'seed'
                set(panelSeedView,'Visible','on');
                set(btnSeedTab,'Value',1,'BackgroundColor',blueBtn);
            case 'roi'
                set(panelROIView,'Visible','on');
                set(btnROITab,'Value',1,'BackgroundColor',blueBtn);
            case 'pair'
                set(panelPairView,'Visible','on');
                set(btnPairTab,'Value',1,'BackgroundColor',blueBtn);
            case 'group'
                set(panelGroupView,'Visible','on');
                set(btnGroupTab,'Value',1,'BackgroundColor',blueBtn);
            case 'graph'
                set(panelGraphView,'Visible','on');
                set(btnGraphTab,'Value',1,'BackgroundColor',blueBtn);
            case 'components'
                set(panelCompView,'Visible','on');
                set(btnCompTab,'Value',1,'BackgroundColor',blueBtn);
        end
    end

    function onSubjectChanged(~,~)
        stLocal = guidata(fig);
        stLocal.currentSubject = get(ddSubject,'Value');
        stLocal.underlayMode = 'mean';
        set(ddUnder,'String',underlayList(stLocal.subjects(stLocal.currentSubject).anat), 'Value',1);
        guidata(fig, stLocal);
        refreshAll();
    end

    function onUnderlayChanged(~,~)
        stLocal = guidata(fig);
        lst = get(ddUnder,'String');
        val = get(ddUnder,'Value');
        choice = lower(strtrim(lst{val}));
        if ~isempty(strfind(choice,'median'))
            stLocal.underlayMode = 'median';
        elseif ~isempty(strfind(choice,'anat'))
            stLocal.underlayMode = 'anat';
        else
            stLocal.underlayMode = 'mean';
        end
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onSliceChanged(~,~)
        stLocal = guidata(fig);
        stLocal.slice = clamp(round(get(slZ,'Value')), 1, stLocal.Z);
        set(edZ,'String',sprintf('%d',stLocal.slice));
        guidata(fig, stLocal);
        refreshAll();
    end

    function onSliceEdit(~,~)
        stLocal = guidata(fig);
        v = str2double(get(edZ,'String'));
        if ~isfinite(v), v = stLocal.slice; end
        stLocal.slice = clamp(round(v), 1, stLocal.Z);
        set(edZ,'String',sprintf('%d',stLocal.slice));
        set(slZ,'Value',stLocal.slice);
        guidata(fig, stLocal);
        refreshAll();
    end

    function onWindowEdit(~,~)
        stLocal = guidata(fig);
        stLocal.analysisSecStart = readWindowEdit(edAnaStart, stLocal.analysisSecStart);
        stLocal.analysisSecEnd   = readWindowEdit(edAnaEnd, stLocal.analysisSecEnd);
        stLocal.baseSecStart     = readWindowEdit(edBaseStart, stLocal.baseSecStart);
        stLocal.baseSecEnd       = readWindowEdit(edBaseEnd, stLocal.baseSecEnd);
        stLocal.signalSecStart   = readWindowEdit(edSigStart, stLocal.signalSecStart);
        stLocal.signalSecEnd     = readWindowEdit(edSigEnd, stLocal.signalSecEnd);
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onPlacementModeChanged(~,~)
        stLocal = guidata(fig);
        if get(ddPlacementMode,'Value') == 1
            stLocal.placementMode = 'window_mean';
        else
            stLocal.placementMode = 'signal_minus_baseline';
        end
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onPlacementAlpha(~,~)
        stLocal = guidata(fig);
        stLocal.placementAlpha = get(slPlacementAlpha,'Value');
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onSeedXYEdit(~,~)
        stLocal = guidata(fig);
        vx = str2double(get(edSeedX,'String'));
        vy = str2double(get(edSeedY,'String'));
        if ~isfinite(vx), vx = stLocal.seedX; end
        if ~isfinite(vy), vy = stLocal.seedY; end
        stLocal.seedX = clamp(round(vx), 1, stLocal.X);
        stLocal.seedY = clamp(round(vy), 1, stLocal.Y);
        set(edSeedX,'String',sprintf('%d',stLocal.seedX));
        set(edSeedY,'String',sprintf('%d',stLocal.seedY));
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onRadiusEdit(~,~)
        stLocal = guidata(fig);
        v = str2double(get(edR,'String'));
        if ~isfinite(v), v = stLocal.seedR; end
        stLocal.seedR = max(0, round(v));
        set(edR,'String',sprintf('%d',stLocal.seedR));
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onComputeModeChanged(~,~)
        stLocal = guidata(fig);
        stLocal.useSliceOnly = logical(get(cbSliceOnly,'Value'));
        guidata(fig, stLocal);
    end

    function onSeedDisplayMode(~,~)
        stLocal = guidata(fig);
        if get(ddSeedDisplay,'Value') == 1
            stLocal.seedDisplayMode = 'fc';
        else
            stLocal.seedDisplayMode = 'placement';
        end
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onMapModeChanged(~,evt)
        stLocal = guidata(fig);
        if strcmpi(evt.NewValue.String,'Fisher z')
            stLocal.seedMapMode = 'z';
        else
            stLocal.seedMapMode = 'r';
        end
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onThrChanged(~,~)
        stLocal = guidata(fig);
        stLocal.seedAbsThr = get(slThr,'Value');
        set(txtThr,'String',sprintf('|r| >= %.2f',stLocal.seedAbsThr));
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onAlphaChanged(~,~)
        stLocal = guidata(fig);
        stLocal.seedAlpha = get(slAlpha,'Value');
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onTraceColor(~,~)
        stLocal = guidata(fig);
        c = uisetcolor(stLocal.seedTSColor, 'Choose seed timecourse color');
        if numel(c) == 3
            stLocal.seedTSColor = c;
            guidata(fig, stLocal);
            refreshSeedViewOnly();
        end
    end

    function onHistColor(~,~)
        stLocal = guidata(fig);
        c = uisetcolor(stLocal.seedHistColor, 'Choose histogram color');
        if numel(c) == 3
            stLocal.seedHistColor = c;
            guidata(fig, stLocal);
            refreshSeedViewOnly();
        end
    end

    function onRoiMethodChanged(~,~)
        stLocal = guidata(fig);
        lst = roiMethodList();
        stLocal.roiMethod = roiMethodCode(lst{get(ddRoiMethod,'Value')});
        guidata(fig, stLocal);
        refreshROIView();
        refreshPairView();
        refreshGraphView();
    end

    function onRoiThrEdit(~,~)
        stLocal = guidata(fig);
        v = str2double(get(edRoiThr,'String'));
        if ~isfinite(v), v = stLocal.roiAbsThr; end
        stLocal.roiAbsThr = max(0, min(1, abs(v)));
        set(edRoiThr,'String',sprintf('%.2f',stLocal.roiAbsThr));
        guidata(fig, stLocal);
        refreshROIView();
        refreshGraphView();
    end

    function onReorderChanged(~,~)
        stLocal = guidata(fig);
        strs = get(ddReorder,'String');
        idx = get(ddReorder,'Value');
        choice = lower(strtrim(strs{idx}));
        if ~isempty(strfind(choice,'label'))
            stLocal.reorderMode = 'label';
        elseif ~isempty(strfind(choice,'ontology'))
            stLocal.reorderMode = 'ontology';
        else
            stLocal.reorderMode = 'none';
        end
        guidata(fig, stLocal);
        refreshROIView();
        refreshPairView();
        refreshGraphView();
        refreshGroupView();
    end

    function onGroupTargetChanged(~,~)
        stLocal = guidata(fig);
        if get(ddGroupTarget,'Value') == 1
            stLocal.groupTarget = 'seed';
        else
            stLocal.groupTarget = 'roi';
        end
        guidata(fig, stLocal);
        refreshGroupView();
    end

    function onGroupTestChanged(~,~)
        stLocal = guidata(fig);
        stLocal.groupTest = groupTestCode(get(ddGroupTest,'String'), get(ddGroupTest,'Value'));
        guidata(fig, stLocal);
    end

    function onGroupAChanged(~,~)
        stLocal = guidata(fig);
        stLocal.groupA = get(ddGroupA,'Value');
        guidata(fig, stLocal);
    end

    function onGroupBChanged(~,~)
        stLocal = guidata(fig);
        stLocal.groupB = get(ddGroupB,'Value');
        guidata(fig, stLocal);
    end

    function onAlphaEdit(~,~)
        stLocal = guidata(fig);
        v = str2double(get(edAlpha,'String'));
        if ~isfinite(v) || v <= 0 || v >= 1
            v = stLocal.groupAlpha;
        end
        stLocal.groupAlpha = v;
        set(edAlpha,'String',sprintf('%.3f',stLocal.groupAlpha));
        guidata(fig, stLocal);
    end

    function onLoadMask(~,~)
        stLocal = guidata(fig);
        startDir = getOneSubjectStartDir(stLocal.subjects(stLocal.currentSubject), stLocal.opts);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load mask MAT', startDir);
        if isequal(f,0), return; end
        S = load(fullfile(p,f));
        m = firstVolumeFromStruct(S, stLocal.Y, stLocal.X, stLocal.Z);
        if isempty(m)
            errordlg('No compatible mask volume found in selected MAT.');
            return;
        end
        stLocal.subjects(stLocal.currentSubject).mask = logical(m);
        stLocal.seedResults{stLocal.currentSubject} = [];
        stLocal.roiResults{stLocal.currentSubject} = [];
        stLocal.compResults{stLocal.currentSubject} = [];
        guidata(fig, stLocal);
        refreshAll();
        setStatus(['Loaded mask: ' fullfile(p,f)], goodC);
    end

    function onLoadAtlas(~,~)
        stLocal = guidata(fig);
        startDir = getOneSubjectStartDir(stLocal.subjects(stLocal.currentSubject), stLocal.opts);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load ROI atlas MAT', startDir);
        if isequal(f,0), return; end
        S = load(fullfile(p,f));
        a = firstVolumeFromStruct(S, stLocal.Y, stLocal.X, stLocal.Z);
        if isempty(a)
            errordlg('No compatible ROI atlas found in selected MAT.');
            return;
        end
        stLocal.subjects(stLocal.currentSubject).roiAtlas = round(double(a));
        stLocal.roiResults{stLocal.currentSubject} = [];
        guidata(fig, stLocal);
        setStatus(['Loaded ROI atlas: ' fullfile(p,f)], goodC);
    end

    function onLoadDataset(~,~)
        stLocal = guidata(fig);
        startDir = getOneSubjectStartDir(stLocal.subjects(stLocal.currentSubject), stLocal.opts);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load replacement dataset MAT', startDir);
        if isequal(f,0), return; end
        try
            S = load(fullfile(p,f));
            [newSub, ok] = extractSubjectFromLoadedMat(S, stLocal.opts, stLocal.currentSubject);
            if ~ok
                errordlg('Could not detect a valid dataset inside the selected MAT file.');
                return;
            end
            [Yi, Xi, Zi] = getSpatialSize(newSub.I4);
            if Yi ~= stLocal.Y || Xi ~= stLocal.X || Zi ~= stLocal.Z
                errordlg('Loaded dataset spatial size does not match current GUI.');
                return;
            end
            stLocal.subjects(stLocal.currentSubject) = newSub;
            stLocal.seedResults{stLocal.currentSubject} = [];
            stLocal.roiResults{stLocal.currentSubject} = [];
            stLocal.compResults{stLocal.currentSubject} = [];
            guidata(fig, stLocal);
            refreshAll();
            setStatus(['Loaded dataset: ' fullfile(p,f)], goodC);
        catch ME
            setStatus(['LOAD DATASET ERROR: ' ME.message], warnC);
        end
    end

    function onMapClick(~,~)
        stLocal = guidata(fig);
        cp = get(axSeedMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x < 1 || x > stLocal.X || y < 1 || y > stLocal.Y, return; end
        stLocal.seedX = x;
        stLocal.seedY = y;
        set(edSeedX,'String',sprintf('%d',stLocal.seedX));
        set(edSeedY,'String',sprintf('%d',stLocal.seedY));
        guidata(fig, stLocal);
        refreshSeedViewOnly();
    end

    function onPairPopup(~,~)
        refreshPairView();
    end

    function onComputeSeed(~,~)
        stLocal = guidata(fig);
        setStatus('Computing seed FC for current subject ...', accent);
        try
            s = stLocal.subjects(stLocal.currentSubject);
            idxT = getAnalysisFrames(stLocal, s);
            stLocal.seedResults{stLocal.currentSubject} = compute_seed_fc_subject_window( ...
                s, idxT, stLocal.seedX, stLocal.seedY, stLocal.slice, stLocal.seedR, stLocal.useSliceOnly, stLocal.opts);
            guidata(fig, stLocal);
            refreshSeedViewOnly();
            switchPanel('Seed');
            setStatus(sprintf('Seed FC done for %s.', s.name), goodC);
        catch ME
            setStatus(['SEED ERROR: ' ME.message], warnC);
            logStack(stLocal.opts, ME);
            if stLocal.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeROI(~,~)
        stLocal = guidata(fig);
        setStatus('Computing ROI FC for all subjects ...', accent);
        try
            for i = 1:stLocal.nSub
                if isempty(stLocal.subjects(i).roiAtlas)
                    error('Subject %d (%s) has no roiAtlas.', i, stLocal.subjects(i).name);
                end
                idxT = getAnalysisFrames(stLocal, stLocal.subjects(i));
                stLocal.roiResults{i} = compute_roi_fc_subject_window(stLocal.subjects(i), idxT, stLocal.opts);
            end
            guidata(fig, stLocal);
            refreshROIView();
            refreshPairView();
            refreshGraphView();
            switchPanel('ROI');
            setStatus('ROI FC done for all subjects.', goodC);
        catch ME
            setStatus(['ROI ERROR: ' ME.message], warnC);
            logStack(stLocal.opts, ME);
            if stLocal.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeGroup(~,~)
        stLocal = guidata(fig);
        setStatus('Computing group statistics ...', accent);
        try
            if strcmpi(stLocal.groupTarget,'seed')
                stLocal = ensureAllSeedComputed(stLocal);
                stLocal.groupSeedStats = compute_group_seed_stats(stLocal);
            else
                stLocal = ensureAllROIComputed(stLocal);
                stLocal.groupRoiStats = compute_group_roi_stats(stLocal);
            end
            guidata(fig, stLocal);
            refreshGroupView();
            switchPanel('Group');
            setStatus('Group statistics finished.', goodC);
        catch ME
            setStatus(['GROUP ERROR: ' ME.message], warnC);
            logStack(stLocal.opts, ME);
            if stLocal.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeComp(~,~)
        stLocal = guidata(fig);
        setStatus('Computing PCA / ICA for current subject ...', accent);
        try
            idxT = getAnalysisFrames(stLocal, stLocal.subjects(stLocal.currentSubject));
            stLocal.compResults{stLocal.currentSubject} = compute_components_subject_window(stLocal.subjects(stLocal.currentSubject), idxT, stLocal.opts);
            guidata(fig, stLocal);
            refreshComponentsView();
            switchPanel('Components');
            setStatus(sprintf('PCA / ICA done for %s.', stLocal.subjects(stLocal.currentSubject).name), goodC);
        catch ME
            setStatus(['COMP ERROR: ' ME.message], warnC);
            logStack(stLocal.opts, ME);
            if stLocal.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onCompSelector(~,~)
        refreshComponentsView();
    end

    function onSave(~,~)
        stLocal = guidata(fig);
        try
            out = struct();
            out.subjects = stLocal.subjects;
            out.seedResults = stLocal.seedResults;
            out.roiResults = stLocal.roiResults;
            out.groupSeedStats = stLocal.groupSeedStats;
            out.groupRoiStats = stLocal.groupRoiStats;
            out.compResults = stLocal.compResults;
            out.guiState = stLocal;
            matFile = fullfile(stLocal.qcDir, sprintf('FunctionalConnectivity_%s.mat', stLocal.tag));
            save(matFile, 'out', '-v7.3');
            saveAxesPNG(axSeedMap, fig, fullfile(stLocal.qcDir, sprintf('FC_seed_%s.png', stLocal.tag)));
            saveAxesPNG(axRoiMat, fig, fullfile(stLocal.qcDir, sprintf('FC_roi_%s.png', stLocal.tag)));
            saveAxesPNG(axGroupMain, fig, fullfile(stLocal.qcDir, sprintf('FC_group_%s.png', stLocal.tag)));
            saveAxesPNG(axAdj, fig, fullfile(stLocal.qcDir, sprintf('FC_graph_%s.png', stLocal.tag)));
            saveAxesPNG(axCompMap, fig, fullfile(stLocal.qcDir, sprintf('FC_comp_%s.png', stLocal.tag)));
            saveas(fig, fullfile(stLocal.qcDir, sprintf('FC_GUI_snapshot_%s.png', stLocal.tag)));
            setStatus(['Saved outputs to ' stLocal.qcDir], goodC);
        catch ME
            setStatus(['SAVE ERROR: ' ME.message], warnC);
            logStack(stLocal.opts, ME);
        end
    end

    function onHelp(~,~)
        openHelpWindow();
    end

    function openHelpWindow()
        hf = figure('Name','FC Help / Tutorial', 'Color',[0.06 0.06 0.07], ...
            'MenuBar','none','ToolBar','none','NumberTitle','off', ...
            'Units','pixels', 'Position',[150 80 980 760]);
        uipanel('Parent',hf,'Units','normalized','Position',[0.02 0.02 0.96 0.96], ...
            'BackgroundColor',[0.08 0.08 0.09], ...
            'ForegroundColor',[0.94 0.94 0.96], ...
            'Title','Functional Connectivity Tutorial', ...
            'FontWeight','bold','FontSize',13);
        txt = [ ...
            'INTRODUCTION' 10 ...
            'Functional connectivity (FC) measures how similar signals are over time between brain locations.' 10 ...
            'This GUI supports seed-based FC, ROI FC, group statistics, and functional seed placement overlays.' 10 10 ...
            'WHAT IS AN ROI ATLAS?' 10 ...
            'An ROI atlas is an integer label image with the same spatial size as the functional data.' 10 ...
            'Background is 0. Each ROI has a positive integer label such as 1, 2, 3, ...' 10 ...
            'Example: 1=SSp_L, 2=SSp_R, 3=MOp_L, 4=MOp_R.' 10 10 ...
            'SEED VS ROI' 10 ...
            'Seed FC: choose one seed and correlate its timecourse with all voxels.' 10 ...
            'ROI FC: extract one representative timecourse per atlas parcel and compute ROI-to-ROI FC.' 10 10 ...
            'PEARSON r VS FISHER z' 10 ...
            'Pearson r is the raw correlation coefficient from -1 to 1.' 10 ...
            'Fisher z = atanh(r). It is better for averaging and group-level statistics.' 10 ...
            'Use Fisher z for statistics and Pearson r for intuitive map display.' 10 10 ...
            'ROI METHODS' 10 ...
            'Mean Pearson: correlate average ROI timecourses.' 10 ...
            'Mean Partial: partial correlation of ROI means.' 10 ...
            'PC1 Pearson: correlate first principal component of each ROI.' 10 ...
            'PC1 Partial: partial correlation of ROI first-PC signals.' 10 ...
            'RV coefficient: multivariate similarity between ROI feature spaces.' 10 10 ...
            'THRESHOLD AND REORDER' 10 ...
            'Threshold controls how much FC must be present to be displayed or kept.' 10 ...
            'Reorder = None, Label, or Ontology sorting of ROIs in the matrix.' 10 10 ...
            'TIME WINDOWS' 10 ...
            'Analysis window = frames actually used for FC computation.' 10 ...
            'This is how you compare before injection, during injection, and after injection.' 10 ...
            'Baseline / signal windows are used for placement overlay if you choose Signal - baseline.' 10 10 ...
            'PLACEMENT OVERLAY' 10 ...
            'Window mean: mean image over current analysis window.' 10 ...
            'Signal - baseline: mean(signal window) minus mean(baseline window).' 10 ...
            'Use placement overlay while selecting the seed, then switch back to FC overlay to inspect connectivity.' 10 10 ...
            'RECOMMENDED WORKFLOW' 10 ...
            '1) Load or verify mask and ROI atlas.' 10 ...
            '2) Set analysis window for the epoch of interest.' 10 ...
            '3) Switch display to Placement overlay and place seed using click or exact X/Y values.' 10 ...
            '4) Compute Seed FC.' 10 ...
            '5) Compute ROI FC if you want matrices or graph summaries.' 10 ...
            '6) For multi-animal analysis, choose group target and test, then Compute Group.' 10 10 ...
            'GROUP STATISTICS' 10 ...
            'One-sample tests ask whether FC differs from zero.' 10 ...
            'Paired tests compare matched conditions such as pre vs post within the same animal.' 10 ...
            'Two-sample tests compare independent groups such as vehicle vs drug.' 10 ...
            'BH-FDR controls multiple comparisons.' 10 10 ...
            'NOTES' 10 ...
            'For paired tests, pairID should match across conditions.' 10 ...
            'For ROI FC, all animals should share the same atlas space and labels.' 10 ...
            'Fisher z is used internally for correlation-based group statistics.' ];
        uicontrol('Parent',hf,'Style','edit','Max',50,'Min',0,'Enable','inactive', ...
            'Units','normalized','Position',[0.04 0.06 0.92 0.88], ...
            'String',txt,'HorizontalAlignment','left', ...
            'BackgroundColor',[0.10 0.10 0.11], ...
            'ForegroundColor',[0.94 0.94 0.96], ...
            'FontName','Courier New','FontSize',10);
    end

    function refreshAll()
        refreshSeedViewOnly();
        refreshROIView();
        refreshPairView();
        refreshGroupView();
        refreshGraphView();
        refreshComponentsView();
    end

    function refreshSeedViewOnly()
        stLocal = guidata(fig);
        set(txtSeed,'String',seedString(stLocal));
        set(hCross1,'YData',[stLocal.seedY stLocal.seedY]);
        set(hCross2,'XData',[stLocal.seedX stLocal.seedX]);
        set(hUnder,'CData',getUnderlaySlice(stLocal));
        title(axSeedMap, buildSeedTitle(stLocal), 'Color',fg, 'FontWeight','bold');

        if strcmpi(stLocal.seedDisplayMode,'placement')
            [ov, ok] = getPlacementOverlay(stLocal);
            if ok
                clim = autoClim(ov(isfinite(ov)), 1);
                rgb = mapToRGB(ov, hot(256), clim);
                A = stLocal.placementAlpha * double(isfinite(ov));
                set(hOver,'CData',rgb, 'AlphaData',A);
            else
                set(hOver,'CData',nan(stLocal.Y, stLocal.X, 3), 'AlphaData',0);
            end
        else
            res = stLocal.seedResults{stLocal.currentSubject};
            if isempty(res)
                set(hOver,'CData',nan(stLocal.Y, stLocal.X, 3), 'AlphaData',0);
            else
                rS = res.rMap(:,:,stLocal.slice);
                zS = res.zMap(:,:,stLocal.slice);
                vis = abs(rS) >= stLocal.seedAbsThr;
                vis = vis & stLocal.subjects(stLocal.currentSubject).mask(:,:,stLocal.slice);
                if strcmpi(stLocal.seedMapMode,'z')
                    M = zS; clim = autoClim(M(vis), 2.5);
                else
                    M = rS; clim = [-1 1];
                end
                rgb = mapToRGB(M, stLocal.fcCmap, clim);
                set(hOver,'CData',rgb, 'AlphaData',stLocal.seedAlpha * double(vis));
            end
        end

        res = stLocal.seedResults{stLocal.currentSubject};
        if isempty(res)
            plotNoData(axSeedTS,'Seed timecourse');
            plotNoData(axSeedHist,'Correlation histogram');
            return;
        end

        ts = double(res.seedTS(:));
        tmin = ((0:numel(ts)-1) * stLocal.subjects(stLocal.currentSubject).TR) / 60;
        cla(axSeedTS);
        plot(axSeedTS, tmin, ts, 'LineWidth',1.8, 'Color',stLocal.seedTSColor);
        set(axSeedTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axSeedTS,'on');
        xlabel(axSeedTS,'Time (min)','Color',fgDim);
        ylabel(axSeedTS,'a.u.','Color',fgDim);
        title(axSeedTS,'Seed timecourse','Color',fg,'FontWeight','bold');

        r = res.rMap(stLocal.subjects(stLocal.currentSubject).mask);
        r = double(r(isfinite(r)));
        cla(axSeedHist);
        if isempty(r)
            plotNoData(axSeedHist,'Correlation histogram');
        else
            histogram(axSeedHist, r, 60, ...
                'FaceColor',stLocal.seedHistColor, ...
                'EdgeColor',max(0, 0.65*stLocal.seedHistColor));
            set(axSeedHist,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axSeedHist,'on');
            xlabel(axSeedHist,'Pearson r','Color',fgDim);
            ylabel(axSeedHist,'Count','Color',fgDim);
            title(axSeedHist,'Correlation histogram','Color',fg,'FontWeight','bold');
        end
    end

    function refreshROIView()
        stLocal = guidata(fig);
        cla(axRoiMat); cla(axRoiTS);
        res = stLocal.roiResults{stLocal.currentSubject};
        if isempty(res)
            plotNoData(axRoiMat,'ROI matrix');
            plotNoData(axRoiTS,'Selected ROI mean traces');
            set(txtRoiInfo,'String','ROI FC not computed yet.');
            set(ddPairA,'String',{'n/a'},'Value',1);
            set(ddPairB,'String',{'n/a'},'Value',1);
            return;
        end

        [Mraw, names, labels, order] = getOrderedRoiMatrix(stLocal, res);
        Mdisp = Mraw;
        Mdisp(abs(Mdisp) < stLocal.roiAbsThr) = 0;
        imagesc(axRoiMat, Mdisp, [-1 1]);
        axis(axRoiMat,'image');
        colormap(axRoiMat, blueWhiteRed(256));
        set(axRoiMat,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        xlabel(axRoiMat,'ROI index','Color',fgDim);
        ylabel(axRoiMat,'ROI index','Color',fgDim);
        title(axRoiMat, buildRoiTitle(stLocal), 'Color',fg,'FontWeight','bold');

        set(txtRoiInfo,'String',sprintf(['Subject: %s
' ...
            'nROI: %d
' ...
            'Method: %s
' ...
            'Threshold |value| >= %.2f
' ...
            'Reorder: %s'], ...
            stLocal.subjects(stLocal.currentSubject).name, numel(labels), stLocal.roiMethod, stLocal.roiAbsThr, stLocal.reorderMode));

        set(ddPairA,'String',names);
        set(ddPairB,'String',names);
        va = min(max(1, getSafePopupValue(ddPairA)), numel(names));
        vb = min(max(1, getSafePopupValue(ddPairB)), numel(names));
        set(ddPairA,'Value',va);
        set(ddPairB,'Value',vb);

        ia = order(va);
        ib = order(vb);
        tmin = ((0:size(res.meanTS,1)-1) * stLocal.subjects(stLocal.currentSubject).TR) / 60;
        ta = zscoreSafe(double(res.meanTS(:, ia)));
        tb = zscoreSafe(double(res.meanTS(:, ib)));
        plot(axRoiTS, tmin, ta, 'LineWidth',1.4);
        hold(axRoiTS,'on');
        plot(axRoiTS, tmin, tb, 'LineWidth',1.4);
        hold(axRoiTS,'off');
        set(axRoiTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axRoiTS,'on');
        xlabel(axRoiTS,'Time (min)','Color',fgDim);
        ylabel(axRoiTS,'z-scored signal','Color',fgDim);
        title(axRoiTS,'Selected ROI mean traces','Color',fg,'FontWeight','bold');
        legend(axRoiTS,{shortRoiName(names{va}), shortRoiName(names{vb})}, ...
            'TextColor',fg,'Color',bgAx,'Location','best');
    end

    function refreshPairView()
        stLocal = guidata(fig);
        cla(axPairTS); cla(axPairScatter); cla(axPairLag);
        res = stLocal.roiResults{stLocal.currentSubject};
        if isempty(res)
            plotNoData(axPairTS,'Pair timecourses');
            plotNoData(axPairScatter,'Pair scatter');
            plotNoData(axPairLag,'Cross-correlation');
            set(txtPairInfo,'String','ROI pair view not ready yet.');
            return;
        end
        [~, names, ~, order] = getOrderedRoiMatrix(stLocal, res);
        va = min(max(1, getSafePopupValue(ddPairA)), numel(names));
        vb = min(max(1, getSafePopupValue(ddPairB)), numel(names));
        ia = order(va);
        ib = order(vb);
        tmin = ((0:size(res.meanTS,1)-1) * stLocal.subjects(stLocal.currentSubject).TR) / 60;
        ta = double(res.meanTS(:, ia));
        tb = double(res.meanTS(:, ib));
        plot(axPairTS, tmin, zscoreSafe(ta), 'LineWidth',1.4);
        hold(axPairTS,'on');
        plot(axPairTS, tmin, zscoreSafe(tb), 'LineWidth',1.4);
        hold(axPairTS,'off');
        set(axPairTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axPairTS,'on');
        xlabel(axPairTS,'Time (min)','Color',fgDim);
        ylabel(axPairTS,'z-scored signal','Color',fgDim);
        title(axPairTS,'ROI pair mean traces','Color',fg,'FontWeight','bold');
        legend(axPairTS,{shortRoiName(names{va}), shortRoiName(names{vb})}, ...
            'TextColor',fg,'Color',bgAx,'Location','best');
        scatter(axPairScatter, ta, tb, 22, 'filled');
        set(axPairScatter,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axPairScatter,'on');
        xlabel(axPairScatter, shortRoiName(names{va}), 'Color',fgDim);
        ylabel(axPairScatter, shortRoiName(names{vb}), 'Color',fgDim);
        title(axPairScatter,'Scatter','Color',fg,'FontWeight','bold');
        maxLag = min(20, numel(ta)-1);
        if maxLag >= 1
            [xc, lags] = xcorr(zscoreSafe(ta), zscoreSafe(tb), maxLag, 'coeff');
            plot(axPairLag, lags * stLocal.subjects(stLocal.currentSubject).TR, xc, 'LineWidth',1.4);
            set(axPairLag,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axPairLag,'on');
            xlabel(axPairLag,'Lag (sec)','Color',fgDim);
            ylabel(axPairLag,'xcorr','Color',fgDim);
            title(axPairLag,'Cross-correlation','Color',fg,'FontWeight','bold');
        else
            plotNoData(axPairLag,'Cross-correlation');
        end
        set(txtPairInfo,'String',buildPairInfoString(res, ia, ib, names{va}, names{vb}));
    end

    function refreshGroupView()
        stLocal = guidata(fig);
        cla(axGroupMain); cla(axGroupAux);
        if strcmpi(stLocal.groupTarget,'seed')
            G = stLocal.groupSeedStats;
            if isempty(G)
                plotNoData(axGroupMain,'Group seed statistics');
                plotNoData(axGroupAux,'q-value histogram');
                set(txtGroupInfo,'String','Group statistics not computed yet.');
                return;
            end
            S = G.statMap(:,:,stLocal.slice);
            Q = G.qMap(:,:,stLocal.slice);
            S(Q > stLocal.groupAlpha) = 0;
            imagesc(axGroupMain, S);
            axis(axGroupMain,'image'); axis(axGroupMain,'off');
            colormap(axGroupMain, blueWhiteRed(256));
            title(axGroupMain,'Group seed statistics (BH-FDR masked)','Color',fg,'FontWeight','bold');
            qvals = G.qMap(G.maskGroup);
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                plotNoData(axGroupAux,'q-value histogram');
            else
                histogram(axGroupAux, qvals, 40, 'FaceColor',[0.30 0.70 1.00], 'EdgeColor',[0.20 0.50 0.90]);
                set(axGroupAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q-value','Color',fgDim);
                ylabel(axGroupAux,'Count','Color',fgDim);
                title(axGroupAux,'Voxel q-value histogram','Color',fg,'FontWeight','bold');
            end
            set(txtGroupInfo,'String',buildGroupSeedInfoString(G, stLocal.groupAlpha));
        else
            G = stLocal.groupRoiStats;
            if isempty(G)
                plotNoData(axGroupMain,'Group ROI statistics');
                plotNoData(axGroupAux,'q-value histogram');
                set(txtGroupInfo,'String','Group statistics not computed yet.');
                return;
            end
            [Mshow, ~, order] = reorderMatrixAndNames(G.statMatrix, G.names, G.labels, stLocal.opts, stLocal.reorderMode);
            Qshow = G.qMatrix(order, order);
            Mshow(Qshow > stLocal.groupAlpha) = 0;
            imagesc(axGroupMain, Mshow);
            axis(axGroupMain,'image');
            colormap(axGroupMain, blueWhiteRed(256));
            set(axGroupMain,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            xlabel(axGroupMain,'ROI index','Color',fgDim);
            ylabel(axGroupMain,'ROI index','Color',fgDim);
            title(axGroupMain,'Group ROI statistics (BH-FDR masked)','Color',fg,'FontWeight','bold');
            qvals = G.qVector;
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                plotNoData(axGroupAux,'q-value histogram');
            else
                histogram(axGroupAux, qvals, 40, 'FaceColor',[0.30 0.70 1.00], 'EdgeColor',[0.20 0.50 0.90]);
                set(axGroupAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q-value','Color',fgDim);
                ylabel(axGroupAux,'Count','Color',fgDim);
                title(axGroupAux,'Edge q-value histogram','Color',fg,'FontWeight','bold');
            end
            set(txtGroupInfo,'String',buildGroupRoiInfoString(G, stLocal.groupAlpha));
        end
    end

    function refreshGraphView()
        stLocal = guidata(fig);
        cla(axAdj); cla(axDeg);
        res = stLocal.roiResults{stLocal.currentSubject};
        if isempty(res)
            plotNoData(axAdj,'Adjacency');
            plotNoData(axDeg,'Degree histogram');
            set(txtGraphInfo,'String','Graph view not ready yet.');
            return;
        end
        [Mraw, names] = getOrderedRoiMatrix(stLocal, res);
        G = compute_graph_summary(Mraw, stLocal.roiAbsThr, names);
        imagesc(axAdj, G.A);
        axis(axAdj,'image');
        colormap(axAdj, gray(256));
        set(axAdj,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        xlabel(axAdj,'ROI index','Color',fgDim);
        ylabel(axAdj,'ROI index','Color',fgDim);
        title(axAdj,'Adjacency from current ROI matrix','Color',fg,'FontWeight','bold');
        if isempty(G.degree)
            plotNoData(axDeg,'Degree histogram');
        else
            histogram(axDeg, G.degree, 'FaceColor',[0.30 0.70 1.00], 'EdgeColor',[0.20 0.50 0.90]);
            set(axDeg,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axDeg,'on');
            xlabel(axDeg,'Degree','Color',fgDim);
            ylabel(axDeg,'Count','Color',fgDim);
            title(axDeg,'Degree histogram','Color',fg,'FontWeight','bold');
        end
        set(txtGraphInfo,'String',buildGraphInfoString(G));
    end

    function refreshComponentsView()
        stLocal = guidata(fig);
        cla(axCompMap); cla(axCompTS); cla(axCompAux);
        res = stLocal.compResults{stLocal.currentSubject};
        if isempty(res)
            plotNoData(axCompMap,'Component map');
            plotNoData(axCompTS,'Component timecourse');
            plotNoData(axCompAux,'Component summary');
            set(txtCompInfo,'String','Components not computed yet.');
            set(ddCompIdx,'String',{'1'}, 'Value',1);
            return;
        end
        typList = get(ddCompType,'String');
        typ = lower(strtrim(typList{get(ddCompType,'Value')}));
        if strcmpi(typ,'ica') && ~res.hasICA
            set(ddCompType,'Value',1);
            typ = 'pca';
        end
        if strcmpi(typ,'pca')
            nComp = res.nPCA;
        else
            nComp = res.nICA;
        end
        if nComp < 1, nComp = 1; end
        strs = cell(nComp,1);
        for i = 1:nComp, strs{i} = sprintf('%d',i); end
        set(ddCompIdx,'String',strs);
        idx = min(max(1, getSafePopupValue(ddCompIdx)), nComp);
        set(ddCompIdx,'Value',idx);
        if strcmpi(typ,'pca')
            vol = maskedVectorToVol(res.pcaSpatial(:, idx), stLocal.subjects(stLocal.currentSubject).mask);
            imagesc(axCompMap, vol(:,:,stLocal.slice));
            axis(axCompMap,'image'); axis(axCompMap,'off');
            colormap(axCompMap, blueWhiteRed(256));
            title(axCompMap, sprintf('PCA component %d',idx), 'Color',fg,'FontWeight','bold');
            tc = res.pcaTS(:, idx);
            tmin = ((0:numel(tc)-1) * stLocal.subjects(stLocal.currentSubject).TR) / 60;
            plot(axCompTS, tmin, tc, 'LineWidth',1.5);
            set(axCompTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',fgDim);
            ylabel(axCompTS,'score','Color',fgDim);
            title(axCompTS,'PCA timecourse','Color',fg,'FontWeight','bold');
            nShow = min(10, numel(res.pcaExplained));
            bar(axCompAux, 100 * res.pcaExplained(1:nShow));
            set(axCompAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Component','Color',fgDim);
            ylabel(axCompAux,'Explained variance (%)','Color',fgDim);
            title(axCompAux,'PCA explained variance','Color',fg,'FontWeight','bold');
            set(txtCompInfo,'String',sprintf('PCA computed for %s. nMaskedVox=%d, nPCA=%d. Component %d explains %.2f%% variance.', ...
                stLocal.subjects(stLocal.currentSubject).name, res.nMasked, res.nPCA, idx, 100*res.pcaExplained(idx)));
        else
            vol = maskedVectorToVol(res.icaSpatial(:, idx), stLocal.subjects(stLocal.currentSubject).mask);
            imagesc(axCompMap, vol(:,:,stLocal.slice));
            axis(axCompMap,'image'); axis(axCompMap,'off');
            colormap(axCompMap, blueWhiteRed(256));
            title(axCompMap, sprintf('ICA component %d',idx), 'Color',fg,'FontWeight','bold');
            tc = res.icaTS(:, idx);
            tmin = ((0:numel(tc)-1) * stLocal.subjects(stLocal.currentSubject).TR) / 60;
            plot(axCompTS, tmin, tc, 'LineWidth',1.5);
            set(axCompTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',fgDim);
            ylabel(axCompTS,'source','Color',fgDim);
            title(axCompTS,'ICA timecourse','Color',fg,'FontWeight','bold');
            histogram(axCompAux, tc, 40, 'FaceColor',[0.30 0.70 1.00], 'EdgeColor',[0.20 0.50 0.90]);
            set(axCompAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Value','Color',fgDim);
            ylabel(axCompAux,'Count','Color',fgDim);
            title(axCompAux,'ICA histogram','Color',fg,'FontWeight','bold');
            set(txtCompInfo,'String',sprintf('ICA computed for %s. nMaskedVox=%d, nICA=%d.', ...
                stLocal.subjects(stLocal.currentSubject).name, res.nMasked, res.nICA));
        end
    end

    function setStatus(msg, colorIn)
        set(txtStatus,'String',msg,'ForegroundColor',colorIn);
        drawnow limitrate;
    end

    function stLocal = ensureAllSeedComputed(stLocal)
        for ii = 1:stLocal.nSub
            idxT = getAnalysisFrames(stLocal, stLocal.subjects(ii));
            doRecompute = false;
            if isempty(stLocal.seedResults{ii})
                doRecompute = true;
            else
                si = stLocal.seedResults{ii}.seedInfo;
                if si.seedX ~= stLocal.seedX || si.seedY ~= stLocal.seedY || si.seedZ ~= stLocal.slice || ...
                        si.seedRadius ~= stLocal.seedR || logical(si.useSliceOnly) ~= logical(stLocal.useSliceOnly)
                    doRecompute = true;
                end
            end
            if doRecompute
                stLocal.seedResults{ii} = compute_seed_fc_subject_window(stLocal.subjects(ii), idxT, stLocal.seedX, stLocal.seedY, stLocal.slice, stLocal.seedR, stLocal.useSliceOnly, stLocal.opts);
            end
        end
    end

    function stLocal = ensureAllROIComputed(stLocal)
        for ii = 1:stLocal.nSub
            if isempty(stLocal.roiResults{ii})
                idxT = getAnalysisFrames(stLocal, stLocal.subjects(ii));
                stLocal.roiResults{ii} = compute_roi_fc_subject_window(stLocal.subjects(ii), idxT, stLocal.opts);
            end
        end
    end
end

% ========================= normalize opts =========================
function opts = normalizeOpts(opts)
if nargin < 1 || isempty(opts) || ~isstruct(opts)
    opts = struct();
end
if ~isfield(opts,'datasetName')      || isempty(opts.datasetName),      opts.datasetName = ''; end
if ~isfield(opts,'functionalField')  || isempty(opts.functionalField),  opts.functionalField = ''; end
if ~isfield(opts,'mask'),                                              opts.mask = []; end
if ~isfield(opts,'anat'),                                              opts.anat = []; end
if ~isfield(opts,'roiAtlas'),                                          opts.roiAtlas = []; end
if ~isfield(opts,'roiNames'),                                          opts.roiNames = {}; end
if ~isfield(opts,'roiOntology'),                                       opts.roiOntology = []; end
if ~isfield(opts,'seedRadius')      || isempty(opts.seedRadius),       opts.seedRadius = 1; end
if ~isfield(opts,'chunkVox')        || isempty(opts.chunkVox),         opts.chunkVox = 6000; end
if ~isfield(opts,'useSliceOnly')    || isempty(opts.useSliceOnly),     opts.useSliceOnly = false; end
if ~isfield(opts,'roiMinVox')       || isempty(opts.roiMinVox),        opts.roiMinVox = 9; end
if ~isfield(opts,'roiAbsThr')       || isempty(opts.roiAbsThr),        opts.roiAbsThr = 0.20; end
if ~isfield(opts,'rvVarExplained')  || isempty(opts.rvVarExplained),   opts.rvVarExplained = 0.20; end
if ~isfield(opts,'pcaN')            || isempty(opts.pcaN),             opts.pcaN = 5; end
if ~isfield(opts,'icaN')            || isempty(opts.icaN),             opts.icaN = 5; end
if ~isfield(opts,'askMaskAtStart')  || isempty(opts.askMaskAtStart),   opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart),  opts.askAtlasAtStart = true; end
if ~isfield(opts,'askDataFieldAtStart') || isempty(opts.askDataFieldAtStart), opts.askDataFieldAtStart = true; end
if ~isfield(opts,'debugRethrow')    || isempty(opts.debugRethrow),     opts.debugRethrow = false; end
if ~isfield(opts,'logFcn'),                                            opts.logFcn = []; end
if ~isfield(opts,'statusFcn'),                                         opts.statusFcn = []; end
end

% ========================= normalize subjects =========================
function subjects = normalizeSubjects(dataIn, opts)
if iscell(dataIn)
    rawList = dataIn;
elseif isstruct(dataIn) && numel(dataIn) > 1
    rawList = cell(numel(dataIn),1);
    for i = 1:numel(dataIn), rawList{i} = dataIn(i); end
else
    rawList = {dataIn};
end

subjects = repmat(struct('I4',[],'TR',1,'mask',[],'anat',[],'roiAtlas',[], ...
    'name','','group','All','pairID',[],'analysisDir',''), numel(rawList), 1);

chosenField = '';
for i = 1:numel(rawList)
    [I4, TR, mask, anat, roiAtlas, name, group, pairID, analysisDir, chosenField] = ...
        normalizeOneSubject(rawList{i}, opts, i, chosenField);
    subjects(i).I4 = I4;
    subjects(i).TR = TR;
    subjects(i).mask = mask;
    subjects(i).anat = anat;
    subjects(i).roiAtlas = roiAtlas;
    subjects(i).name = name;
    subjects(i).group = group;
    subjects(i).pairID = pairID;
    subjects(i).analysisDir = analysisDir;
end
end

function [I4, TR, mask, anat, roiAtlas, name, group, pairID, analysisDir, chosenField] = normalizeOneSubject(in, opts, idx, chosenField)
TR = 1;
mask = [];
anat = [];
roiAtlas = [];
name = sprintf('Subject_%02d', idx);
group = 'All';
pairID = idx;
analysisDir = '';

if isnumeric(in)
    I4 = force4Dsingle(in);
    if ~isempty(opts.mask)
        [Y,X,Z] = getSpatialSize(I4);
        mask = interpretVolume(opts.mask, Y, X, Z, true);
    end
    if ~isempty(opts.anat)
        [Y,X,Z] = getSpatialSize(I4);
        anat = interpretVolume(opts.anat, Y, X, Z, false);
    end
    if ~isempty(opts.roiAtlas)
        [Y,X,Z] = getSpatialSize(I4);
        roiAtlas = interpretVolume(opts.roiAtlas, Y, X, Z, false);
        if ~isempty(roiAtlas), roiAtlas = round(double(roiAtlas)); end
    end
    analysisDir = pwd;
    return;
end

if ~isstruct(in)
    error('Each subject must be numeric or struct.');
end

if isfield(in,'name') && ~isempty(in.name), name = char(in.name); end
if isfield(in,'group') && ~isempty(in.group), group = char(in.group); end
if isfield(in,'pairID') && ~isempty(in.pairID), pairID = in.pairID; end
if isfield(in,'TR') && ~isempty(in.TR), TR = double(in.TR); end
if ~isscalar(TR) || ~isfinite(TR) || TR <= 0, TR = 1; end

if isempty(chosenField)
    [fieldName, Iraw] = extractFunctionalData(in, opts);
    chosenField = fieldName;
else
    if isfield(in, chosenField) && ~isempty(in.(chosenField))
        Iraw = in.(chosenField);
    else
        [~, Iraw] = extractFunctionalData(in, opts);
    end
end
I4 = force4Dsingle(Iraw);
[Y, X, Z] = getSpatialSize(I4);

if isfield(in,'mask') && ~isempty(in.mask)
    mask = interpretVolume(in.mask, Y, X, Z, true);
elseif isfield(in,'brainMask') && ~isempty(in.brainMask)
    mask = interpretVolume(in.brainMask, Y, X, Z, true);
elseif ~isempty(opts.mask)
    mask = interpretVolume(opts.mask, Y, X, Z, true);
end

if isfield(in,'anat') && ~isempty(in.anat)
    anat = interpretVolume(in.anat, Y, X, Z, false);
elseif isfield(in,'bg') && ~isempty(in.bg)
    anat = interpretVolume(in.bg, Y, X, Z, false);
elseif ~isempty(opts.anat)
    anat = interpretVolume(opts.anat, Y, X, Z, false);
end

if isfield(in,'roiAtlas') && ~isempty(in.roiAtlas)
    roiAtlas = interpretVolume(in.roiAtlas, Y, X, Z, false);
elseif isfield(in,'atlas') && ~isempty(in.atlas)
    roiAtlas = interpretVolume(in.atlas, Y, X, Z, false);
elseif isfield(in,'regions') && ~isempty(in.regions)
    roiAtlas = interpretVolume(in.regions, Y, X, Z, false);
elseif ~isempty(opts.roiAtlas)
    roiAtlas = interpretVolume(opts.roiAtlas, Y, X, Z, false);
end
if ~isempty(roiAtlas)
    roiAtlas = round(double(roiAtlas));
end
analysisDir = inferAnalysisDir(in, opts);
end

function [fieldName, Iraw] = extractFunctionalData(s, opts)
cand = {'I','PSC','data','functional','func','movie','brain','img','volume'};
avail = {};
for i = 1:numel(cand)
    if isfield(s,cand{i}) && ~isempty(s.(cand{i})) && isnumeric(s.(cand{i}))
        d = ndims(s.(cand{i}));
        if d == 3 || d == 4
            avail{end+1} = cand{i}; %#ok<AGROW>
        end
    end
end
if isempty(avail)
    fn = fieldnames(s);
    for i = 1:numel(fn)
        if isnumeric(s.(fn{i})) && (ndims(s.(fn{i})) == 3 || ndims(s.(fn{i})) == 4)
            avail{end+1} = fn{i}; %#ok<AGROW>
        end
    end
end
if isempty(avail)
    error('Could not find functional data field in input struct.');
end
if ~isempty(opts.functionalField) && isfield(s, opts.functionalField)
    fieldName = opts.functionalField;
elseif numel(avail) == 1
    fieldName = avail{1};
elseif opts.askDataFieldAtStart
    [sel, ok] = listdlg('PromptString','Select functional data field:', ...
        'SelectionMode','single','ListString',avail);
    if ok && ~isempty(sel)
        fieldName = avail{sel};
    else
        fieldName = avail{1};
    end
else
    fieldName = avail{1};
end
Iraw = s.(fieldName);
end

function I4 = force4Dsingle(I)
sz = size(I);
if ndims(I) == 3
    Y = sz(1); X = sz(2); T = sz(3);
    I4 = reshape(single(I), Y, X, 1, T);
elseif ndims(I) == 4
    I4 = single(I);
else
    error('Functional data must be [Y X T] or [Y X Z T].');
end
end

function v = interpretVolume(in, Y, X, Z, makeLogical)
v = [];
try
    if ndims(in) == 2 && Z == 1 && size(in,1) == Y && size(in,2) == X
        v = reshape(in, Y, X, 1);
    elseif ndims(in) == 3 && all(size(in) == [Y X Z])
        v = in;
    else
        return;
    end
    if makeLogical, v = logical(v); end
catch
    v = [];
end
end

% ========================= startup mask / atlas =========================
function [subjects, info] = applyStartupMaskStrategy(subjects, opts)
[Y, X, Z] = getSpatialSize(subjects(1).I4);
if ~opts.askMaskAtStart
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask)
            subjects(i).mask = buildAutoMask(subjects(i).I4);
        end
    end
    info = 'Used provided masks when available; auto otherwise.';
    return;
end

hasAnyProvided = false;
for i = 1:numel(subjects)
    if ~isempty(subjects(i).mask)
        hasAnyProvided = true;
        break;
    end
end

if hasAnyProvided
    choice = questdlg('Mask selection: choose startup strategy.', ...
        'Startup mask selection', ...
        'Use provided masks', 'Auto masks', 'Load one common mask', ...
        'Use provided masks');
else
    choice = questdlg('No provided subject masks found. Choose startup strategy.', ...
        'Startup mask selection', ...
        'Auto masks', 'Load one common mask', 'Auto masks');
end
if isempty(choice), choice = 'Auto masks'; end

switch lower(strtrim(choice))
    case 'use provided masks'
        for i = 1:numel(subjects)
            if isempty(subjects(i).mask)
                subjects(i).mask = buildAutoMask(subjects(i).I4);
            end
        end
        info = 'Used provided masks; auto fallback where missing.';
    case 'load one common mask'
        startDir = getStartupMaskDir(subjects, opts);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select common mask MAT file', startDir);
        if isequal(f,0)
            for i = 1:numel(subjects)
                subjects(i).mask = buildAutoMask(subjects(i).I4);
            end
            info = 'User cancelled common mask load; used auto masks.';
        else
            S = load(fullfile(p,f));
            m = firstVolumeFromStruct(S, Y, X, Z);
            if isempty(m)
                error('Could not find a compatible mask volume in selected MAT file.');
            end
            m = logical(m);
            for i = 1:numel(subjects)
                subjects(i).mask = m;
            end
            info = ['Loaded one common mask from ' fullfile(p,f)];
        end
    otherwise
        for i = 1:numel(subjects)
            subjects(i).mask = buildAutoMask(subjects(i).I4);
        end
        info = 'Used auto masks.';
end
end

function [atlas, ok] = maybeLoadCommonAtlas(subjects)
ok = false;
atlas = [];
q = questdlg('No roiAtlas found. Load one common ROI atlas MAT now?', ...
    'Load ROI atlas', 'Yes', 'No', 'No');
if ~strcmpi(q,'Yes')
    return;
end
[Y, X, Z] = getSpatialSize(subjects(1).I4);
startDir = getStartupMaskDir(subjects, struct('saveRoot',pwd));
[f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select common ROI atlas MAT file', startDir);
if isequal(f,0), return; end
S = load(fullfile(p,f));
atlas = firstVolumeFromStruct(S, Y, X, Z);
if isempty(atlas)
    errordlg('Could not find a compatible atlas volume in the selected MAT file.');
    atlas = [];
    return;
end
atlas = round(double(atlas));
ok = true;
end

function mask = buildAutoMask(I4)
mimg = mean(I4,4);
thr = prctileSafe(mimg(:), 25);
mask = logical(mimg > thr);
end

function analysisDir = inferAnalysisDir(in, opts)
analysisDir = '';
candFields = {'analysisDir','analysedDir','analysisPath','analysedPath','saveRoot','outputDir','resultsDir'};
for i = 1:numel(candFields)
    fn = candFields{i};
    if isstruct(in) && isfield(in,fn) && ~isempty(in.(fn))
        p = char(in.(fn));
        if exist(p,'dir')
            analysisDir = p;
            return;
        end
    end
end
pathFields = {'loadedPath','filePath','sourcePath','path','folder'};
for i = 1:numel(pathFields)
    fn = pathFields{i};
    if isstruct(in) && isfield(in,fn) && ~isempty(in.(fn))
        p = char(in.(fn));
        if exist(p,'dir')
            analysisDir = findAnalysedSubfolder(p);
            if ~isempty(analysisDir), return; end
            analysisDir = p;
            return;
        elseif exist(p,'file')
            p0 = fileparts(p);
            analysisDir = findAnalysedSubfolder(p0);
            if ~isempty(analysisDir), return; end
            analysisDir = p0;
            return;
        end
    end
end
if isfield(opts,'saveRoot') && ~isempty(opts.saveRoot) && exist(opts.saveRoot,'dir')
    analysisDir = opts.saveRoot;
else
    analysisDir = pwd;
end
end

function outDir = findAnalysedSubfolder(baseDir)
outDir = '';
if isempty(baseDir) || ~exist(baseDir,'dir'), return; end
cand = {fullfile(baseDir,'AnalysedData'), fullfile(baseDir,'AnalyzedData'), ...
        fullfile(baseDir,'Analysed'), fullfile(baseDir,'Analyzed'), ...
        fullfile(baseDir,'Analysis'), fullfile(baseDir,'analysis')};
for i = 1:numel(cand)
    if exist(cand{i},'dir')
        outDir = cand{i};
        return;
    end
end
end

function startDir = getStartupMaskDir(subjects, opts)
startDir = '';
for i = 1:numel(subjects)
    if isfield(subjects(i),'analysisDir') && ~isempty(subjects(i).analysisDir) && exist(subjects(i).analysisDir,'dir')
        startDir = subjects(i).analysisDir;
        return;
    end
end
if isfield(opts,'saveRoot') && ~isempty(opts.saveRoot) && exist(opts.saveRoot,'dir')
    startDir = opts.saveRoot;
else
    startDir = pwd;
end
end

function V = firstVolumeFromStruct(S, Y, X, Z)
V = [];
fn = fieldnames(S);
for i = 1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x)
        if ndims(x) == 2 && Z == 1 && size(x,1) == Y && size(x,2) == X
            V = reshape(x, Y, X, 1);
            return;
        elseif ndims(x) == 3 && all(size(x) == [Y X Z])
            V = x;
            return;
        end
    end
end
end

% ========================= single-subject FC =========================
function res = compute_seed_fc_subject(subj, seedX, seedY, sliceZ, seedR, useSliceOnly, opts)
I4 = subj.I4;
mask = subj.mask;
[Y, X, Z, T] = size(I4);
seedMask2D = diskMask(Y, X, seedY, seedX, seedR);
seedMask3D = false(Y, X, Z);
seedMask3D(:,:,sliceZ) = seedMask2D;
seedMask3D = seedMask3D & mask;
seedV = find(seedMask3D(:));
if isempty(seedV)
    seedMask3D = false(Y,X,Z);
    seedMask3D(seedY, seedX, sliceZ) = true;
    seedV = find(seedMask3D(:));
end
V = Y * X * Z;
Xvt = reshape(I4, [V T]);
seedTS = mean(double(Xvt(seedV,:)), 1);
seedTS = seedTS(:);
s = double(seedTS - mean(seedTS));
sNorm = sqrt(sum(s.^2));
if sNorm <= 0 || ~isfinite(sNorm)
    error('Seed timecourse has zero variance.');
end
r = nan(V,1,'single');
if useSliceOnly
    voxMask = false(Y, X, Z);
    voxMask(:,:,sliceZ) = mask(:,:,sliceZ);
else
    voxMask = mask;
end
voxIdx = find(voxMask(:));
if isempty(voxIdx)
    error('Mask is empty for seed FC.');
end
chunkVox = max(1000, round(opts.chunkVox));
sSingle = single(s);
for i0 = 1:chunkVox:numel(voxIdx)
    i1 = min(numel(voxIdx), i0 + chunkVox - 1);
    id = voxIdx(i0:i1);
    Xc = Xvt(id,:);
    Xm = mean(Xc,2);
    Xc = bsxfun(@minus, Xc, Xm);
    num = Xc * sSingle;
    den = sqrt(sum(Xc.^2,2)) * single(sNorm);
    rr = num ./ max(single(eps), den);
    rr(~isfinite(rr)) = 0;
    rr = max(-1, min(1, rr));
    r(id) = rr;
end
rMap = reshape(r, [Y X Z]);
rc = double(rMap);
rc = min(0.999999, max(-0.999999, rc));
zMap = single(atanh(rc));
res = struct();
res.rMap = rMap;
res.zMap = zMap;
res.seedTS = seedTS;
res.seedInfo = struct('seedX',seedX,'seedY',seedY,'seedZ',sliceZ, ...
    'seedRadius',seedR,'useSliceOnly',useSliceOnly);
end

function res = compute_roi_fc_subject(subj, opts)
[Y, X, Z, T] = size(subj.I4); %#ok<ASGLU>
V = Y * X * Z;
Xvt = reshape(subj.I4, [V T]);
maskV = subj.mask(:);
atlasV = subj.roiAtlas(:);
labelsAll = unique(atlasV(maskV & atlasV > 0));
labelsAll = labelsAll(:)';
if isempty(labelsAll)
    error('No positive ROI labels inside mask.');
end
labelsKeep = [];
countsKeep = [];
namesKeep = {};
meanTS = [];
pc1TS = [];
rvFeat = {};
for k = 1:numel(labelsAll)
    lab = labelsAll(k);
    idx = find(maskV & atlasV == lab);
    if numel(idx) < opts.roiMinVox
        continue;
    end
    Xroi = double(Xvt(idx,:))';
    if isempty(Xroi)
        continue;
    end
    m = mean(Xroi, 2);
    Xc = bsxfun(@minus, Xroi, mean(Xroi,1));
    if all(abs(Xc(:)) < eps)
        pc = m;
        rvF = zscoreSafe(m);
    else
        [U,S,~] = svd(Xc,'econ');
        pc = U(:,1) * S(1,1);
        if corrScalarSafe(pc, m) < 0
            pc = -pc;
        end
        s2 = diag(S).^2;
        if isempty(s2) || sum(s2) <= 0
            nComp = 1;
        else
            cumv = cumsum(s2) / sum(s2);
            nComp = find(cumv >= opts.rvVarExplained, 1, 'first');
            if isempty(nComp), nComp = 1; end
        end
        rvF = U(:,1:nComp) * S(1:nComp,1:nComp);
    end
    labelsKeep(end+1,1) = lab; %#ok<AGROW>
    countsKeep(end+1,1) = numel(idx); %#ok<AGROW>
    namesKeep{end+1,1} = resolveRoiName(lab, opts.roiNames); %#ok<AGROW>
    meanTS(:,end+1) = m; %#ok<AGROW>
    pc1TS(:,end+1) = pc; %#ok<AGROW>
    rvFeat{end+1,1} = rvF; %#ok<AGROW>
end
if isempty(labelsKeep)
    error('No ROI survived roiMinVox threshold.');
end
res = struct();
res.labels = labelsKeep;
res.counts = countsKeep;
res.names = namesKeep;
res.meanTS = meanTS;
res.pc1TS = pc1TS;
res.M_mean_pearson = corrcoefSafe(meanTS);
res.M_mean_partial = partialCorrMatrixSafe(meanTS);
res.M_pc1_pearson = corrcoefSafe(pc1TS);
res.M_pc1_partial = partialCorrMatrixSafe(pc1TS);
res.M_rv = rvCoefficientMatrix(rvFeat);
end

function res = compute_components_subject(subj, opts)
Xvt = reshape(subj.I4, [], size(subj.I4,4));
id = find(subj.mask(:));
Xmask = double(Xvt(id,:));
Xmask = bsxfun(@minus, Xmask, mean(Xmask,2));
[U,S,V] = svd(Xmask,'econ');
s2 = diag(S).^2;
expl = s2 / max(sum(s2), eps);
nPCA = min([opts.pcaN size(U,2) size(V,2)]);
res = struct();
res.nMasked = numel(id);
res.nPCA = nPCA;
res.pcaSpatial = U(:,1:nPCA);
res.pcaTS = V(:,1:nPCA) * S(1:nPCA,1:nPCA);
res.pcaExplained = expl(:);
res.hasICA = false;
res.nICA = 0;
res.icaSpatial = [];
res.icaTS = [];
if exist('fastica','file') == 2
    try
        nICA = min([opts.icaN size(Xmask,2)-1]);
        if nICA >= 1
            [icasig, A, ~] = fastica(Xmask, 'numOfIC',nICA, 'verbose','off', 'displayMode','off');
            res.hasICA = true;
            res.nICA = nICA;
            res.icaSpatial = A;
            res.icaTS = icasig';
        end
    catch
        res.hasICA = false;
        res.nICA = 0;
        res.icaSpatial = [];
        res.icaTS = [];
    end
end
end

% ========================= group stats =========================
function G = compute_group_seed_stats(st)
groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};
idxA = find(strcmpCellstr(groups, grpAName));
idxB = find(strcmpCellstr(groups, grpBName));
if isempty(idxA), error('Group A is empty.'); end
maskGroup = true(st.Y, st.X, st.Z);
for i = idxA(:)'
    maskGroup = maskGroup & st.subjects(i).mask;
end
for i = idxB(:)'
    maskGroup = maskGroup & st.subjects(i).mask;
end
featIdx = find(maskGroup(:));
ZA = zeros(numel(featIdx), numel(idxA));
for i = 1:numel(idxA)
    ZA(:,i) = double(st.seedResults{idxA(i)}.zMap(featIdx));
end
switch st.groupTest
    case 'one_sample_t'
        [stat,p,meanVal,nUsed] = stat_onesample_t(ZA);
    case 'one_sample_wilcoxon'
        [stat,p,meanVal,nUsed] = stat_onesample_signrank(ZA);
    case 'paired_t'
        ZB = getMatchedSeedMatrix(st, idxA, idxB, featIdx);
        [stat,p,meanVal,nUsed] = stat_paired_t(ZA, ZB);
    case 'paired_wilcoxon'
        ZB = getMatchedSeedMatrix(st, idxA, idxB, featIdx);
        [stat,p,meanVal,nUsed] = stat_paired_signrank(ZA, ZB);
    case 'two_sample_t'
        if isempty(idxB), error('Group B is empty.'); end
        ZB = zeros(numel(featIdx), numel(idxB));
        for i = 1:numel(idxB)
            ZB(:,i) = double(st.seedResults{idxB(i)}.zMap(featIdx));
        end
        [stat,p,meanVal,nUsed] = stat_twosample_t(ZA, ZB);
    case 'two_sample_wilcoxon'
        if isempty(idxB), error('Group B is empty.'); end
        ZB = zeros(numel(featIdx), numel(idxB));
        for i = 1:numel(idxB)
            ZB(:,i) = double(st.seedResults{idxB(i)}.zMap(featIdx));
        end
        [stat,p,meanVal,nUsed] = stat_twosample_ranksum(ZA, ZB);
    otherwise
        error('Unknown group test.');
end
q = nan(size(p));
q(isfinite(p)) = bh_fdr_vector(p(isfinite(p)));
statMap = nan(st.Y, st.X, st.Z);
pMap = nan(st.Y, st.X, st.Z);
qMap = nan(st.Y, st.X, st.Z);
meanMap = nan(st.Y, st.X, st.Z);
statMap(featIdx) = stat;
pMap(featIdx) = p;
qMap(featIdx) = q;
meanMap(featIdx) = meanVal;
G = struct();
G.test = st.groupTest;
G.groupA = grpAName;
G.groupB = grpBName;
G.nA = numel(idxA);
G.nB = numel(idxB);
G.nUsed = nUsed;
G.maskGroup = maskGroup;
G.statMap = statMap;
G.pMap = pMap;
G.qMap = qMap;
G.meanMap = meanMap;
G.nSignificant = nnz(qMap(maskGroup) <= st.groupAlpha);
end

function ZB = getMatchedSeedMatrix(st, idxA, idxB, featIdx)
subA = st.subjects(idxA);
subB = st.subjects(idxB);
pairA = cellfun(@pairToString, {subA.pairID}, 'UniformOutput', false);
pairB = cellfun(@pairToString, {subB.pairID}, 'UniformOutput', false);
commonPairs = intersect(pairA, pairB);
if isempty(commonPairs)
    nUse = min(numel(idxA), numel(idxB));
    idxB = idxB(1:nUse);
else
    keepB = [];
    for i = 1:numel(commonPairs)
        ib = find(strcmp(pairB, commonPairs{i}), 1, 'first');
        if ~isempty(ib)
            keepB(end+1) = idxB(ib); %#ok<AGROW>
        end
    end
    idxB = keepB;
end
ZB = zeros(numel(featIdx), numel(idxB));
for i = 1:numel(idxB)
    ZB(:,i) = double(st.seedResults{idxB(i)}.zMap(featIdx));
end
end

function G = compute_group_roi_stats(st)
groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};
idxA = find(strcmpCellstr(groups, grpAName));
idxB = find(strcmpCellstr(groups, grpBName));
if isempty(idxA), error('Group A is empty.'); end
[stack, labels, names, isFisher] = assembleRoiStack(st);
nR = numel(labels);
ut = find(triu(true(nR),1));
XA = reshape(stack(:,:,idxA), nR*nR, []);
XA = XA(ut,:);
switch st.groupTest
    case 'one_sample_t'
        [stat,p,meanVal,nUsed] = stat_onesample_t(XA);
    case 'one_sample_wilcoxon'
        [stat,p,meanVal,nUsed] = stat_onesample_signrank(XA);
    case 'paired_t'
        XB = getMatchedRoiStack(st, stack, idxA, idxB);
        XB = reshape(XB, nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal,nUsed] = stat_paired_t(XA, XB);
    case 'paired_wilcoxon'
        XB = getMatchedRoiStack(st, stack, idxA, idxB);
        XB = reshape(XB, nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal,nUsed] = stat_paired_signrank(XA, XB);
    case 'two_sample_t'
        if isempty(idxB), error('Group B is empty.'); end
        XB = reshape(stack(:,:,idxB), nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal,nUsed] = stat_twosample_t(XA, XB);
    case 'two_sample_wilcoxon'
        if isempty(idxB), error('Group B is empty.'); end
        XB = reshape(stack(:,:,idxB), nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal,nUsed] = stat_twosample_ranksum(XA, XB);
    otherwise
        error('Unknown group test.');
end
q = nan(size(p));
q(isfinite(p)) = bh_fdr_vector(p(isfinite(p)));
statMatrix = nan(nR);
pMatrix = nan(nR);
qMatrix = nan(nR);
meanMatrix = nan(nR);
statMatrix(ut) = stat;
pMatrix(ut) = p;
qMatrix(ut) = q;
meanMatrix(ut) = meanVal;
statMatrix = statMatrix + statMatrix';
pMatrix = pMatrix + pMatrix';
qMatrix = qMatrix + qMatrix';
meanMatrix = meanMatrix + meanMatrix';
for i = 1:nR
    statMatrix(i,i) = 0;
    pMatrix(i,i) = 1;
    qMatrix(i,i) = 1;
    meanMatrix(i,i) = 0;
end
if isFisher
    groupAvgA = nanmean_safe(XA,2);
    groupAverageMatrix = nan(nR);
    groupAverageMatrix(ut) = tanh(groupAvgA);
    groupAverageMatrix = groupAverageMatrix + groupAverageMatrix';
else
    groupAvgA = nanmean_safe(XA,2);
    groupAverageMatrix = nan(nR);
    groupAverageMatrix(ut) = groupAvgA;
    groupAverageMatrix = groupAverageMatrix + groupAverageMatrix';
end
groupAverageMatrix(1:nR+1:end) = 1;
G = struct();
G.test = st.groupTest;
G.groupA = grpAName;
G.groupB = grpBName;
G.nA = numel(idxA);
G.nB = numel(idxB);
G.nUsed = nUsed;
G.labels = labels;
G.names = names;
G.isFisher = isFisher;
G.groupAverageMatrix = groupAverageMatrix;
G.statMatrix = statMatrix;
G.pMatrix = pMatrix;
G.qMatrix = qMatrix;
G.qVector = q;
G.nSignificantEdges = nnz(q <= st.groupAlpha);
end

function [stack, labelsCommon, namesCommon, isFisher] = assembleRoiStack(st)
method = st.roiMethod;
isFisher = ~strcmpi(method,'rv');
labelSets = cell(st.nSub,1);
for i = 1:st.nSub
    labelSets{i} = st.roiResults{i}.labels(:);
end
labelsCommon = labelSets{1};
for i = 2:st.nSub
    labelsCommon = intersect(labelsCommon, labelSets{i});
end
if isempty(labelsCommon)
    error('No common ROI labels across subjects.');
end
labelsCommon = labelsCommon(:);
nR = numel(labelsCommon);
stack = nan(nR, nR, st.nSub);
namesCommon = cell(nR,1);
for i = 1:nR
    namesCommon{i} = resolveRoiName(labelsCommon(i), st.opts.roiNames);
end
for s = 1:st.nSub
    res = st.roiResults{s};
    switch lower(method)
        case 'mean_pearson'
            M = res.M_mean_pearson;
        case 'mean_partial'
            M = res.M_mean_partial;
        case 'pc1_pearson'
            M = res.M_pc1_pearson;
        case 'pc1_partial'
            M = res.M_pc1_partial;
        case 'rv'
            M = res.M_rv;
        otherwise
            M = res.M_mean_pearson;
    end
    Ms = nan(nR, nR);
    for i = 1:nR
        ii = find(res.labels == labelsCommon(i), 1, 'first');
        for j = 1:nR
            jj = find(res.labels == labelsCommon(j), 1, 'first');
            if ~isempty(ii) && ~isempty(jj)
                Ms(i,j) = M(ii,jj);
            end
        end
    end
    if isFisher
        Ms = atanh_clip(Ms);
    end
    stack(:,:,s) = Ms;
end
end

function XB = getMatchedRoiStack(st, stack, idxA, idxB)
subA = st.subjects(idxA);
subB = st.subjects(idxB);
pairA = cellfun(@pairToString, {subA.pairID}, 'UniformOutput', false);
pairB = cellfun(@pairToString, {subB.pairID}, 'UniformOutput', false);
commonPairs = intersect(pairA, pairB);
if isempty(commonPairs)
    nUse = min(numel(idxA), numel(idxB));
    idxB = idxB(1:nUse);
else
    keepB = [];
    for i = 1:numel(commonPairs)
        ib = find(strcmp(pairB, commonPairs{i}), 1, 'first');
        if ~isempty(ib)
            keepB(end+1) = idxB(ib); %#ok<AGROW>
        end
    end
    idxB = keepB;
end
XB = stack(:,:,idxB);
end
