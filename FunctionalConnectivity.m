function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity.m
% fUSI Studio - Functional Connectivity GUI
% MATLAB 2017b compatible
% ASCII-only source
%
% MAIN IMPROVEMENTS IN THIS VERSION
%   - Cleaner, more guided GUI
%   - Dedicated Heatmap tab
%   - Separate underlay and overlay display logic
%   - Epoch manager (named windows)
%   - Better data summary / current state visibility
%   - Atlas contour overlay on seed map
%   - Cleaner seed display and less stretched view
%   - Heatmap colormap / threshold / sign-mode controls
%   - Clearer subject / epoch aware result handling
%
% INPUT
%   dataIn:
%       numeric [Y X T] or [Y X Z T]
%       struct with functional fields
%       cell array / struct array for multiple subjects
%
% OPTIONAL opts fields
%   .statusFcn
%   .logFcn
%   .seedRadius
%   .chunkVox
%   .useSliceOnly
%   .roiMinVox
%   .roiAbsThr
%   .rvVarExplained
%   .askMaskAtStart
%   .askAtlasAtStart
%   .functionalField
%   .roiNames
%   .roiOntology
%   .pcaN
%   .icaN
%   .debugRethrow

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4 || isempty(opts), opts = struct(); end

opts = fc_normalize_opts(opts);
opts.saveRoot = saveRoot;

subjects = fc_normalize_subjects(dataIn, opts);
if isempty(subjects)
    error('FunctionalConnectivity: No valid subjects found.');
end

nSub = numel(subjects);
[Y, X, Z] = fc_spatial_size(subjects(1).I4);

for i = 2:nSub
    [Yi, Xi, Zi] = fc_spatial_size(subjects(i).I4);
    if Yi ~= Y || Xi ~= X || Zi ~= Z
        error('FunctionalConnectivity: All subjects must have identical spatial dimensions.');
    end
end

[subjects, startupMaskInfo] = fc_startup_mask_strategy(subjects, opts);

if opts.askAtlasAtStart
    anyAtlas = false;
    for i = 1:nSub
        if ~isempty(subjects(i).roiAtlas)
            anyAtlas = true;
            break;
        end
    end
    if ~anyAtlas
        atlas = fc_maybe_load_common_atlas(subjects, opts);
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
st.seedBoxSize  = max(1, round(2*opts.seedRadius + 1));  % convert old radius default to box size
st.seedGeometry = 'square';                              % SCM-compatible default
st.useSliceOnly = logical(opts.useSliceOnly);

st.analysisSecStart = 0;
st.analysisSecEnd   = inf;
st.baseSecStart     = 0;
st.baseSecEnd       = 60;
st.signalSecStart   = 60;
st.signalSecEnd     = 120;

st.epochs = struct('name', {'Whole'}, 'start', {0}, 'end', {inf});
st.currentEpoch = 1;

st.underlayMode     = 'mean';    % mean / median / anat / loaded / atlas_labels
st.overlayMode      = 'fc';      % fc / placement / atlas_edges / mask_edges / none
st.placementMode    = 'window_mean'; % window_mean / signal_minus_baseline

% SCM-compatible seed geometry
st.seedGeometry     = 'square';  % square / disk


% display / warp
st.loadedUnderlay      = [];
st.loadedUnderlayName  = '';
st.loadedUnderlayIsRGB = false;

st.isAtlasWarped       = false;
st.atlasTransformFile  = '';

% keep native copy for reset
st.nativeSubjects      = subjects;

st.showAtlasContours = true;
st.showMaskOutline   = false;

st.placementMode  = 'window_mean';  % window_mean / signal_minus_baseline
st.seedAbsThr     = 0.20;
st.seedAlpha      = 0.70;
st.placementAlpha = 0.55;
st.seedMapMode = 'z';

st.roiMethod      = 'mean_pearson';
st.roiAbsThr      = opts.roiAbsThr;
st.reorderMode    = 'none';

st.hmSource       = 'current_subject'; % current_subject / group_stat / group_q
st.hmMatrixType   = 'mean_pearson';    % mean_pearson / mean_partial / pc1_pearson / pc1_partial / rv
st.hmDisplaySpace = 'r';               % r / z
st.hmCmapName     = 'bluewhitered';    % bluewhitered / parula / hot / gray / jet
st.hmSignMode     = 'abs';             % abs / pos / neg / none
st.hmAbsThr       = opts.roiAbsThr;
st.hmShowLabels   = true;

st.groupTarget    = 'seed'; % seed / roi
st.groupTest      = 'one_sample_t';
st.groupAlpha     = 0.05;
st.groupNames     = unique(fc_cellstr({subjects.group}));
if isempty(st.groupNames), st.groupNames = {'All'}; end
st.groupA         = 1;
st.groupB         = min(2, numel(st.groupNames));

st.pairA = 1;
st.pairB = 2;

st.seedTSColor   = [0.20 0.75 1.00];
st.seedHistColor = [0.20 0.65 1.00];
st.fcCmap        = fc_bluewhitered(256);

st.seedResults     = cell(nSub, numel(st.epochs));
st.roiResults      = cell(nSub, numel(st.epochs));
st.compResults     = cell(nSub, numel(st.epochs));
st.groupSeedStats  = cell(1, numel(st.epochs));
st.groupRoiStats   = cell(1, numel(st.epochs));

st.tag = tag;
st.qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(st.qcDir,'dir'), mkdir(st.qcDir); end

st.opts = opts;

% -------------------------------------------------------------------------
% THEME
% -------------------------------------------------------------------------
C = struct();
C.bgFig      = [0.05 0.05 0.06];
C.bgPane     = [0.08 0.08 0.09];
C.bgAx       = [0.10 0.10 0.11];
C.bgEdit     = [0.16 0.16 0.18];
C.bgDrop     = [0.16 0.16 0.18];
C.bgBtn      = [0.24 0.24 0.28];
C.bgBlue     = [0.12 0.40 0.82];
C.bgGreen    = [0.16 0.54 0.24];
C.bgRed      = [0.70 0.20 0.20];
C.fg         = [0.94 0.94 0.96];
C.fgDim      = [0.76 0.76 0.80];
C.accent     = [0.20 0.65 1.00];
C.good       = [0.20 0.72 0.32];
C.warn       = [1.00 0.35 0.35];
C.outline    = [0.92 0.92 0.92];
C.maskLine   = [0.20 0.95 0.40];
C.cross      = [1.00 0.25 0.25];

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
    'CloseRequestFcn',@onClose);

try, set(fig,'Renderer','opengl'); catch, end
try, set(fig,'WindowState','maximized'); catch, end

% -------------------------------------------------------------------------
% MAIN PANELS
% -------------------------------------------------------------------------
ctrlX = 0.010;
ctrlY = 0.02;
ctrlW = 0.435;
ctrlH = 0.96;

viewX = ctrlX + ctrlW + 0.010;
viewY = 0.02;
viewW = 1.0 - viewX - 0.010;
viewH = 0.96;

panelCtrl = uipanel( ...
    'Parent',fig, ...
    'Units','normalized', ...
    'Position',[ctrlX ctrlY ctrlW ctrlH], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Controls', ...
    'FontWeight','bold', ...
    'FontSize',13);

panelViewWrap = uipanel( ...
    'Parent',fig, ...
    'Units','normalized', ...
    'Position',[viewX viewY viewW viewH], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Views', ...
    'FontWeight','bold', ...
    'FontSize',13);

pData = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.77 0.96 0.22], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Data / Display', ...
    'FontWeight','bold', ...
    'FontSize',12);

pEpoch = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.58 0.96 0.18], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Epochs / Time Windows', ...
    'FontWeight','bold', ...
    'FontSize',12);

pSeed = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.36 0.96 0.21], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Seed FC', ...
    'FontWeight','bold', ...
    'FontSize',12);

pHM = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.22 0.96 0.13], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','ROI / Heatmap', ...
    'FontWeight','bold', ...
    'FontSize',12);

pStats = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.09 0.96 0.12], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Group Statistics', ...
    'FontWeight','bold', ...
    'FontSize',12);

pActions = uipanel( ...
    'Parent',panelCtrl, ...
    'Units','normalized', ...
    'Position',[0.02 0.01 0.96 0.07], ...
    'BackgroundColor',C.bgPane, ...
    'ForegroundColor',C.fg, ...
    'Title','Actions', ...
    'FontWeight','bold', ...
    'FontSize',12);

% -------------------------------------------------------------------------
% DATA / DISPLAY PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.02 0.84 0.20 0.10], ...
    'String','Subject', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

subNames = cell(st.nSub,1);
for i = 1:st.nSub
    subNames{i} = st.subjects(i).name;
end
if isempty(subNames), subNames = {'Subject_01'}; end

ddSubject = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.73 0.44 0.12], ...
    'String',subNames, ...
    'Value',st.currentSubject, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onSubjectChanged);

uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.50 0.84 0.18 0.10], ...
    'String','Slice (Z)', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

slZ = uicontrol('Parent',pData,'Style','slider','Units','normalized', ...
    'Position',[0.50 0.75 0.34 0.08], ...
    'Min',1,'Max',max(1,st.Z),'Value',st.slice, ...
    'SliderStep',fc_slider_step(st.Z), ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onSliceChanged);

edZ = uicontrol('Parent',pData,'Style','edit','Units','normalized', ...
    'Position',[0.86 0.73 0.10 0.12], ...
    'String',sprintf('%d',st.slice), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onSliceEdit);

uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.02 0.58 0.18 0.08], ...
    'String','Underlay', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddUnder = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.47 0.28 0.11], ...
    'String',fc_underlay_list(st.subjects(st.currentSubject), st), ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onUnderlayChanged);

uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.33 0.58 0.18 0.08], ...
    'String','Overlay', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddOverlay = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.33 0.47 0.28 0.11], ...
    'String',{'Seed FC','Placement','Atlas boundaries','Mask boundaries','None'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onOverlayChanged);

cbAtlasContours = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.64 0.50 0.16 0.08], ...
    'String','Atlas lines', ...
    'Value',double(st.showAtlasContours), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onAtlasContourToggle);

cbMaskOutline = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.81 0.50 0.15 0.08], ...
    'String','Mask edge', ...
    'Value',double(st.showMaskOutline), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onMaskOutlineToggle);

btnLoadDataset = uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.29 0.30 0.12], ...
    'String','Load Dataset', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadDataset);

btnLoadMask = uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.35 0.29 0.28 0.12], ...
    'String','Load Mask', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadMask);

btnLoadAtlas = uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.66 0.29 0.30 0.12], ...
    'String','Load ROI Atlas', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadAtlas);

btnLoadUnderlay = uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.15 0.30 0.12], ...
    'String','Load Underlay', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadUnderlay);


txtSummary = uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.02 0.03 0.94 0.21], ...
    'String','', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left', ...
    'FontSize',10);

% -------------------------------------------------------------------------
% EPOCH PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pEpoch,'Style','text','Units','normalized', ...
    'Position',[0.02 0.86 0.18 0.10], ...
    'String','Saved epochs', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

lbEpochs = uicontrol('Parent',pEpoch,'Style','listbox','Units','normalized', ...
    'Position',[0.02 0.16 0.28 0.68], ...
    'String',fc_epoch_name_list(st.epochs), ...
    'Value',st.currentEpoch, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onEpochSelected);

uicontrol('Parent',pEpoch,'Style','text','Units','normalized', ...
    'Position',[0.34 0.78 0.14 0.10], ...
    'String','Start (s)', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edAnaStart = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.46 0.76 0.14 0.12], ...
    'String',num2str(st.analysisSecStart), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

uicontrol('Parent',pEpoch,'Style','text','Units','normalized', ...
    'Position',[0.63 0.78 0.12 0.10], ...
    'String','End (s)', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edAnaEnd = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.74 0.76 0.14 0.12], ...
    'String','inf', ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

btnEpochAdd = uicontrol('Parent',pEpoch,'Style','pushbutton','Units','normalized', ...
    'Position',[0.34 0.56 0.18 0.12], ...
    'String','Add current', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onAddEpoch);

btnEpochUpdate = uicontrol('Parent',pEpoch,'Style','pushbutton','Units','normalized', ...
    'Position',[0.54 0.56 0.18 0.12], ...
    'String','Update sel.', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onUpdateEpoch);

btnEpochDelete = uicontrol('Parent',pEpoch,'Style','pushbutton','Units','normalized', ...
    'Position',[0.74 0.56 0.14 0.12], ...
    'String','Delete', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onDeleteEpoch);

uicontrol('Parent',pEpoch,'Style','text','Units','normalized', ...
    'Position',[0.34 0.35 0.24 0.10], ...
    'String','Placement baseline', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edBaseStart = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.34 0.22 0.10 0.12], ...
    'String',num2str(st.baseSecStart), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

edBaseEnd = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.46 0.22 0.10 0.12], ...
    'String',num2str(st.baseSecEnd), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

uicontrol('Parent',pEpoch,'Style','text','Units','normalized', ...
    'Position',[0.60 0.35 0.22 0.10], ...
    'String','Placement signal', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edSigStart = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.60 0.22 0.10 0.12], ...
    'String',num2str(st.signalSecStart), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

edSigEnd = uicontrol('Parent',pEpoch,'Style','edit','Units','normalized', ...
    'Position',[0.72 0.22 0.10 0.12], ...
    'String',num2str(st.signalSecEnd), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onWindowEdit);

ddPlacementMode = uicontrol('Parent',pEpoch,'Style','popupmenu','Units','normalized', ...
    'Position',[0.84 0.22 0.12 0.12], ...
    'String',{'Window mean','Sig-baseline'}, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',9, ...
    'Callback',@onPlacementModeChanged);

% -------------------------------------------------------------------------
% SEED PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.80 0.06 0.10], ...
    'String','X', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edSeedX = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.06 0.79 0.11 0.12], ...
    'String',num2str(st.seedX), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onSeedXYEdit);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.20 0.80 0.06 0.10], ...
    'String','Y', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edSeedY = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.24 0.79 0.11 0.12], ...
    'String',num2str(st.seedY), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onSeedXYEdit);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.38 0.80 0.10 0.10], ...
    'String','Size', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edSeedR = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.48 0.79 0.10 0.12], ...
    'String',num2str(st.seedBoxSize), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onSeedREdit);

cbSliceOnly = uicontrol('Parent',pSeed,'Style','checkbox','Units','normalized', ...
    'Position',[0.62 0.80 0.18 0.10], ...
    'String','Slice only', ...
    'Value',double(st.useSliceOnly), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onSliceOnly);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.58 0.12 0.10], ...
    'String','Map type', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

bgMap = uibuttongroup('Parent',pSeed,'Units','normalized', ...
    'Position',[0.16 0.53 0.28 0.18], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','line', ...
    'SelectionChangedFcn',@onMapMode);

rbMapZ = uicontrol('Parent',bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.05 0.18 0.42 0.65], ...
    'String','Fisher z', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'FontSize',10);

rbMapR = uicontrol('Parent',bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.52 0.18 0.42 0.65], ...
    'String','Pearson r', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'FontSize',10);

set(bgMap,'SelectedObject',rbMapZ);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.48 0.58 0.20 0.10], ...
    'String','Threshold |r|', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

slThr = uicontrol('Parent',pSeed,'Style','slider','Units','normalized', ...
    'Position',[0.67 0.61 0.29 0.06], ...
    'Min',0,'Max',0.99,'Value',st.seedAbsThr, ...
    'SliderStep',[0.01 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onThr);

txtThr = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.48 0.48 0.18 0.08], ...
    'String',sprintf('|r| >= %.2f',st.seedAbsThr), ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.accent, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.68 0.48 0.08 0.08], ...
    'String','Alpha', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

slAlpha = uicontrol('Parent',pSeed,'Style','slider','Units','normalized', ...
    'Position',[0.76 0.50 0.20 0.06], ...
    'Min',0,'Max',1,'Value',st.seedAlpha, ...
    'SliderStep',[0.02 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onAlpha);

uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.34 0.18 0.08], ...
    'String','Placement alpha', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

slPlacementAlpha = uicontrol('Parent',pSeed,'Style','slider','Units','normalized', ...
    'Position',[0.20 0.36 0.24 0.06], ...
    'Min',0,'Max',1,'Value',st.placementAlpha, ...
    'SliderStep',[0.02 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onPlacementAlpha);

btnTraceColor = uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.48 0.26 0.22 0.12], ...
    'String','Trace Color', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onTraceColor);

btnHistColor = uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.73 0.26 0.22 0.12], ...
    'String','Hist Color', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onHistColor);

txtSeed = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.05 0.94 0.12], ...
    'String','', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',10);

btnLoadScmROI = uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.62 0.64 0.34 0.12], ...
    'String','Load SCM ROI TXT', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadScmROI);

% -------------------------------------------------------------------------
% HEATMAP PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.02 0.62 0.14 0.20], ...
    'String','Matrix', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddHMMatrix = uicontrol('Parent',pHM,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.28 0.24 0.28], ...
    'String',fc_roi_method_list(), ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onHMMatrixType);

uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.29 0.62 0.10 0.20], ...
    'String','Space', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddHMSpace = uicontrol('Parent',pHM,'Style','popupmenu','Units','normalized', ...
    'Position',[0.29 0.28 0.10 0.28], ...
    'String',{'r','z'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onHMSpace);

uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.42 0.62 0.10 0.20], ...
    'String','CMap', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddHMCmap = uicontrol('Parent',pHM,'Style','popupmenu','Units','normalized', ...
    'Position',[0.42 0.28 0.14 0.28], ...
    'String',{'Blue-White-Red','Parula','Hot','Gray','Jet'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onHMCmap);

uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.59 0.62 0.12 0.20], ...
    'String','Sign', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddHMSign = uicontrol('Parent',pHM,'Style','popupmenu','Units','normalized', ...
    'Position',[0.59 0.28 0.12 0.28], ...
    'String',{'Abs','Pos','Neg','None'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onHMSign);

uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.74 0.62 0.10 0.20], ...
    'String','Thr', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edHMThr = uicontrol('Parent',pHM,'Style','edit','Units','normalized', ...
    'Position',[0.74 0.28 0.09 0.28], ...
    'String',sprintf('%.2f',st.hmAbsThr), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onHMThr);

uicontrol('Parent',pHM,'Style','text','Units','normalized', ...
    'Position',[0.85 0.62 0.12 0.20], ...
    'String','Order', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddHMOrder = uicontrol('Parent',pHM,'Style','popupmenu','Units','normalized', ...
    'Position',[0.85 0.28 0.12 0.28], ...
    'String',{'None','Label','Ontology'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onReorder);

% -------------------------------------------------------------------------
% STATS PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.02 0.66 0.16 0.20], ...
    'String','Target', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddGroupTarget = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.36 0.18 0.24], ...
    'String',{'Seed maps','ROI edges'}, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onGroupTarget);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.23 0.66 0.12 0.20], ...
    'String','alpha/q', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

edAlpha = uicontrol('Parent',pStats,'Style','edit','Units','normalized', ...
    'Position',[0.23 0.36 0.10 0.24], ...
    'String',sprintf('%.3f',st.groupAlpha), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onGroupAlpha);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.36 0.66 0.12 0.20], ...
    'String','Test', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddGroupTest = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.36 0.36 0.34 0.24], ...
    'String',fc_group_test_list(), ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onGroupTest);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.02 0.08 0.04 0.18], ...
    'String','A', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddGroupA = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.06 0.04 0.28 0.22], ...
    'String',st.groupNames, ...
    'Value',st.groupA, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onGroupA);

uicontrol('Parent',pStats,'Style','text','Units','normalized', ...
    'Position',[0.38 0.08 0.04 0.18], ...
    'String','B', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddGroupB = uicontrol('Parent',pStats,'Style','popupmenu','Units','normalized', ...
    'Position',[0.42 0.04 0.28 0.22], ...
    'String',st.groupNames, ...
    'Value',st.groupB, ...
    'BackgroundColor',C.bgDrop,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onGroupB);

% -------------------------------------------------------------------------
% ACTIONS PANEL
% -------------------------------------------------------------------------
btnComputeSeed = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.01 0.35 0.18 0.45], ...
    'String','Seed current', ...
    'BackgroundColor',C.bgGreen,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeSeed);

btnComputeROI = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.205 0.35 0.18 0.45], ...
    'String','ROI all', ...
    'BackgroundColor',C.bgGreen,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeROI);

btnComputeGroup = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.40 0.35 0.18 0.45], ...
    'String','Group', ...
    'BackgroundColor',C.bgGreen,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeGroup);

btnComputeComp = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.595 0.35 0.18 0.45], ...
    'String','PCA / ICA', ...
    'BackgroundColor',C.bgGreen,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeComp);

btnSave = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.79 0.35 0.10 0.45], ...
    'String','Save', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onSave);

btnHelp = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.895 0.35 0.05 0.45], ...
    'String','?', ...
    'BackgroundColor',C.bgBlue,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onHelp);

btnClose = uicontrol('Parent',pActions,'Style','pushbutton','Units','normalized', ...
    'Position',[0.95 0.35 0.04 0.45], ...
    'String','X', ...
    'BackgroundColor',C.bgRed,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onClose);

txtStatus = uicontrol('Parent',pActions,'Style','text','Units','normalized', ...
    'Position',[0.01 0.02 0.98 0.22], ...
    'String',['Ready. ' startupMaskInfo], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fgDim, ...
    'HorizontalAlignment','left', ...
    'FontSize',9);

% -------------------------------------------------------------------------
% VIEW TABS
% -------------------------------------------------------------------------
btnSeedTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.02 0.94 0.11 0.04], ...
    'String','Seed', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBlue,'ForegroundColor','w', ...
    'Value',1, ...
    'Callback',@(src,evt)switchPanel('seed'));

btnHMTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.145 0.94 0.12 0.04], ...
    'String','Heatmap', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'Value',0, ...
    'Callback',@(src,evt)switchPanel('heatmap'));

btnPairTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.28 0.94 0.10 0.04], ...
    'String','Pair', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'Value',0, ...
    'Callback',@(src,evt)switchPanel('pair'));

btnGroupTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.395 0.94 0.11 0.04], ...
    'String','Group', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'Value',0, ...
    'Callback',@(src,evt)switchPanel('group'));

btnGraphTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.52 0.94 0.11 0.04], ...
    'String','Graph', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'Value',0, ...
    'Callback',@(src,evt)switchPanel('graph'));

btnCompTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.645 0.94 0.16 0.04], ...
    'String','Components', ...
    'FontWeight','bold','FontSize',10, ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'Value',0, ...
    'Callback',@(src,evt)switchPanel('components'));

panelSeedView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none');

panelHMView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none', ...
    'Visible','off');

panelPairView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none', ...
    'Visible','off');

panelGroupView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none', ...
    'Visible','off');

panelGraphView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none', ...
    'Visible','off');

panelCompView = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane, ...
    'BorderType','none', ...
    'Visible','off');

% -------------------------------------------------------------------------
% SEED VIEW
% -------------------------------------------------------------------------
axSeedMap = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.03 0.10 0.58 0.80], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
axis(axSeedMap,'image');
axis(axSeedMap,'off');

axSeedTS = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.66 0.60 0.31 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axSeedTS,'on');

axSeedHist = axes('Parent',panelSeedView,'Units','normalized', ...
    'Position',[0.66 0.20 0.31 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axSeedHist,'on');

hUnder = image(axSeedMap, fc_get_underlay_rgb(st));
hold(axSeedMap,'on');
hOver = imagesc(axSeedMap, nan(Y, X, 3));
set(hOver,'AlphaData',0);
hAtlasLine = imagesc(axSeedMap, nan(Y, X, 3));
set(hAtlasLine,'AlphaData',0);
hMaskLine = imagesc(axSeedMap, nan(Y, X, 3));
set(hMaskLine,'AlphaData',0);
hCross1 = line(axSeedMap,[1 X],[st.seedY st.seedY],'Color',C.cross,'LineWidth',1.0);
hCross2 = line(axSeedMap,[st.seedX st.seedX],[1 Y],'Color',C.cross,'LineWidth',1.0);
hold(axSeedMap,'off');

set(hUnder,'ButtonDownFcn',@onMapClick);
set(hOver,'ButtonDownFcn',@onMapClick);
set(hAtlasLine,'ButtonDownFcn',@onMapClick);
set(hMaskLine,'ButtonDownFcn',@onMapClick);
set(axSeedMap,'ButtonDownFcn',@onMapClick);

txtSeedTitle = uicontrol('Parent',panelSeedView,'Style','text','Units','normalized', ...
    'Position',[0.03 0.91 0.58 0.05], ...
    'String','', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','center', ...
    'FontWeight','bold','FontSize',11);

% -------------------------------------------------------------------------
% HEATMAP VIEW
% -------------------------------------------------------------------------
axHM = axes('Parent',panelHMView,'Units','normalized', ...
    'Position',[0.05 0.14 0.58 0.76], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);

axHMTS = axes('Parent',panelHMView,'Units','normalized', ...
    'Position',[0.69 0.58 0.28 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axHMTS,'on');

txtHMInfo = uicontrol('Parent',panelHMView,'Style','text','Units','normalized', ...
    'Position',[0.67 0.14 0.31 0.38], ...
    'String','Heatmap not computed yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',11);

% -------------------------------------------------------------------------
% PAIR VIEW
% -------------------------------------------------------------------------
uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.08 0.03], ...
    'String','ROI A', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);

ddPairA = uicontrol('Parent',panelPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.14 0.93 0.32 0.04], ...
    'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onPairChanged);

uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.52 0.93 0.08 0.03], ...
    'String','ROI B', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);

ddPairB = uicontrol('Parent',panelPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.61 0.93 0.32 0.04], ...
    'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onPairChanged);

txtPairInfo = uicontrol('Parent',panelPairView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.82 0.90 0.08], ...
    'String','ROI pair view not ready yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',11);

axPairTS = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.08 0.55 0.84 0.22], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axPairTS,'on');

axPairScatter = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.08 0.18 0.38 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axPairScatter,'on');

axPairLag = axes('Parent',panelPairView,'Units','normalized', ...
    'Position',[0.54 0.18 0.38 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axPairLag,'on');

% -------------------------------------------------------------------------
% GROUP VIEW
% -------------------------------------------------------------------------
axGroupMain = axes('Parent',panelGroupView,'Units','normalized', ...
    'Position',[0.05 0.14 0.62 0.78], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);

axGroupAux = axes('Parent',panelGroupView,'Units','normalized', ...
    'Position',[0.72 0.58 0.25 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axGroupAux,'on');

txtGroupInfo = uicontrol('Parent',panelGroupView,'Style','text','Units','normalized', ...
    'Position',[0.70 0.14 0.29 0.38], ...
    'String','Group statistics not computed yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',11);

% -------------------------------------------------------------------------
% GRAPH VIEW
% -------------------------------------------------------------------------
axAdj = axes('Parent',panelGraphView,'Units','normalized', ...
    'Position',[0.05 0.16 0.48 0.76], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);

axDeg = axes('Parent',panelGraphView,'Units','normalized', ...
    'Position',[0.60 0.60 0.35 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axDeg,'on');

txtGraphInfo = uicontrol('Parent',panelGraphView,'Style','text','Units','normalized', ...
    'Position',[0.58 0.16 0.39 0.38], ...
    'String','Graph view not ready yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',11);

% -------------------------------------------------------------------------
% COMPONENTS VIEW
% -------------------------------------------------------------------------
uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.10 0.03], ...
    'String','Type', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);

ddCompType = uicontrol('Parent',panelCompView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.12 0.93 0.16 0.04], ...
    'String',{'PCA','ICA'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onCompChanged);

uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.32 0.93 0.16 0.03], ...
    'String','Component', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);

ddCompIdx = uicontrol('Parent',panelCompView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.46 0.93 0.16 0.04], ...
    'String',{'1'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10, ...
    'Callback',@onCompChanged);

axCompMap = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.05 0.18 0.44 0.70], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);

axCompTS = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.55 0.58 0.40 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axCompTS,'on');

axCompAux = axes('Parent',panelCompView,'Units','normalized', ...
    'Position',[0.55 0.18 0.40 0.28], ...
    'Color',C.bgAx, ...
    'XColor',C.fgDim, ...
    'YColor',C.fgDim);
grid(axCompAux,'on');

txtCompInfo = uicontrol('Parent',panelCompView,'Style','text','Units','normalized', ...
    'Position',[0.05 0.04 0.90 0.10], ...
    'String','Components not computed yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',11);

% -------------------------------------------------------------------------
% INITIALIZE
% -------------------------------------------------------------------------
guidata(fig, st);
refreshAll();

% =========================================================================
% CALLBACKS
% =========================================================================
   function onLoadScmROI(~,~)
    st2 = guidata(fig);
    s = st2.subjects(st2.currentSubject);
    startDir = fc_pick_start_dir(s, st2.opts);

    [f,p] = uigetfile({'*.txt','SCM ROI txt (*.txt)'}, 'Load SCM ROI txt', startDir);
    if isequal(f,0), return; end

    info = fc_read_scm_roi_txt(fullfile(p,f));

    st2.seedX = round((info.x1 + info.x2)/2);
    st2.seedY = round((info.y1 + info.y2)/2);
    st2.seedBoxSize = max(info.x2-info.x1+1, info.y2-info.y1+1);
    st2.seedGeometry = 'square';

    if isfinite(info.slice)
        st2.slice = fc_clamp(round(info.slice),1,st2.Z);
    end

    guidata(fig, st2);
    refreshAll();
   end

function info = fc_read_scm_roi_txt(txtFile)
fid = fopen(txtFile,'r');
if fid < 0, error('Could not open ROI txt.'); end
c = onCleanup(@() fclose(fid));

info = struct('x1',NaN,'x2',NaN,'y1',NaN,'y2',NaN,'slice',NaN);
L = {};
while ~feof(fid)
    L{end+1} = fgetl(fid); %#ok<AGROW>
end

for i = 1:numel(L)
    s = strtrim(L{i});
    if strncmpi(s,'# SLICE:',8)
        info.slice = str2double(strtrim(s(9:end)));
    end
    if i > 1 && strcmp(strtrim(L{i-1}),'# x1 x2 y1 y2')
        v = sscanf(s,'%f %f %f %f');
        if numel(v)==4
            info.x1 = v(1); info.x2 = v(2);
            info.y1 = v(3); info.y2 = v(4);
        end
    end
end

if ~all(isfinite([info.x1 info.x2 info.y1 info.y2]))
    error('Could not parse x1 x2 y1 y2 from ROI txt.');
end
end

    
    function onClose(~,~)
        try
            st2 = guidata(fig);
            if ~isempty(st2) && isfield(st2,'opts') && ~isempty(st2.opts.statusFcn) && isa(st2.opts.statusFcn,'function_handle')
                st2.opts.statusFcn(true);
            end
        catch
        end
        delete(fig);
    end

    function setStatus(msg, col)
        if nargin < 2 || isempty(col), col = C.fgDim; end
        set(txtStatus,'String',msg,'ForegroundColor',col);
        drawnow limitrate;
        fc_warnlog(opts, msg);
    end

    function switchPanel(name)
        set(panelSeedView,'Visible','off');
        set(panelHMView,'Visible','off');
        set(panelPairView,'Visible','off');
        set(panelGroupView,'Visible','off');
        set(panelGraphView,'Visible','off');
        set(panelCompView,'Visible','off');

        set(btnSeedTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        set(btnHMTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        set(btnPairTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        set(btnGroupTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        set(btnGraphTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        set(btnCompTab,'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);

        switch lower(name)
            case 'seed'
                set(panelSeedView,'Visible','on');
                set(btnSeedTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
            case 'heatmap'
                set(panelHMView,'Visible','on');
                set(btnHMTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
            case 'pair'
                set(panelPairView,'Visible','on');
                set(btnPairTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
            case 'group'
                set(panelGroupView,'Visible','on');
                set(btnGroupTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
            case 'graph'
                set(panelGraphView,'Visible','on');
                set(btnGraphTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
            case 'components'
                set(panelCompView,'Visible','on');
                set(btnCompTab,'Value',1,'BackgroundColor',C.bgBlue,'ForegroundColor','w');
        end
    end

    function onSubjectChanged(~,~)
        st2 = guidata(fig);
        st2.currentSubject = get(ddSubject,'Value');
        guidata(fig, st2);
        setStatus(['Switched subject: ' st2.subjects(st2.currentSubject).name], C.fgDim);
        refreshAll();
    end

    function onSliceChanged(~,~)
        st2 = guidata(fig);
        st2.slice = fc_clamp(round(get(slZ,'Value')), 1, st2.Z);
        set(edZ,'String',sprintf('%d',st2.slice));
        guidata(fig, st2);
        refreshAll();
    end

    function onSliceEdit(~,~)
        st2 = guidata(fig);
        v = str2double(get(edZ,'String'));
        if ~isfinite(v), v = st2.slice; end
        st2.slice = fc_clamp(round(v), 1, st2.Z);
        set(slZ,'Value',st2.slice);
        set(edZ,'String',sprintf('%d',st2.slice));
        guidata(fig, st2);
        refreshAll();
    end

   function onUnderlayChanged(~,~)
    st2 = guidata(fig);
    lst = get(ddUnder,'String');
    val = get(ddUnder,'Value');
    choice = lower(strtrim(lst{val}));

    if ~isempty(strfind(choice,'loaded'))
        st2.underlayMode = 'loaded';
    elseif ~isempty(strfind(choice,'median'))
        st2.underlayMode = 'median';
    elseif ~isempty(strfind(choice,'anat'))
        st2.underlayMode = 'anat';
    elseif ~isempty(strfind(choice,'atlas'))
        st2.underlayMode = 'atlas_labels';
    else
        st2.underlayMode = 'mean';
    end

    guidata(fig, st2);
    refreshSeedView();
end
    function onOverlayChanged(~,~)
    st2 = guidata(fig);
    val = get(ddOverlay,'Value');
    switch val
        case 1
            st2.overlayMode = 'seed_fc';
        case 2
            st2.overlayMode = 'placement';
        case 3
            st2.overlayMode = 'atlas_edges';
        case 4
            st2.overlayMode = 'mask_edges';
        otherwise
            st2.overlayMode = 'none';
    end
    guidata(fig, st2);
    refreshSeedView();
end

    function onAtlasContourToggle(~,~)
        st2 = guidata(fig);
        st2.showAtlasContours = logical(get(cbAtlasContours,'Value'));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onMaskOutlineToggle(~,~)
        st2 = guidata(fig);
        st2.showMaskOutline = logical(get(cbMaskOutline,'Value'));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onEpochSelected(~,~)
        st2 = guidata(fig);
        idx = get(lbEpochs,'Value');
        idx = fc_clamp(idx, 1, numel(st2.epochs));
        st2.currentEpoch = idx;
        ep = st2.epochs(idx);
        st2.analysisSecStart = ep.start;
        st2.analysisSecEnd   = ep.end;

        set(edAnaStart,'String',fc_num_to_str(ep.start));
        set(edAnaEnd,'String',fc_num_to_str(ep.end));

        guidata(fig, st2);
        setStatus(['Selected epoch: ' ep.name], C.fgDim);
        refreshAll();
    end

    function onAddEpoch(~,~)
        st2 = guidata(fig);
        st2.analysisSecStart = fc_read_window(edAnaStart, st2.analysisSecStart);
        st2.analysisSecEnd   = fc_read_window(edAnaEnd, st2.analysisSecEnd);

        answ = inputdlg({'Epoch name:'}, 'Add epoch', 1, {sprintf('Epoch_%02d', numel(st2.epochs)+1)});
        if isempty(answ), return; end

        ep.name  = fc_sanitize_epoch_name(answ{1}, numel(st2.epochs)+1);
        ep.start = st2.analysisSecStart;
        ep.end   = st2.analysisSecEnd;

        st2.epochs(end+1) = ep; %#ok<AGROW>
        [st2.seedResults, st2.roiResults, st2.compResults, st2.groupSeedStats, st2.groupRoiStats] = ...
            fc_expand_epoch_storage(st2.seedResults, st2.roiResults, st2.compResults, st2.groupSeedStats, st2.groupRoiStats);

        st2.currentEpoch = numel(st2.epochs);
        guidata(fig, st2);

        set(lbEpochs,'String',fc_epoch_name_list(st2.epochs), 'Value',st2.currentEpoch);
        setStatus(['Added epoch: ' ep.name], C.good);
        refreshAll();
    end

    function onUpdateEpoch(~,~)
        st2 = guidata(fig);
        idx = st2.currentEpoch;
        if idx < 1 || idx > numel(st2.epochs), return; end

        st2.analysisSecStart = fc_read_window(edAnaStart, st2.analysisSecStart);
        st2.analysisSecEnd   = fc_read_window(edAnaEnd, st2.analysisSecEnd);

        st2.epochs(idx).start = st2.analysisSecStart;
        st2.epochs(idx).end   = st2.analysisSecEnd;

        guidata(fig, st2);
        set(lbEpochs,'String',fc_epoch_name_list(st2.epochs), 'Value',idx);
        setStatus(['Updated epoch: ' st2.epochs(idx).name], C.good);
        refreshAll();
    end

    function onDeleteEpoch(~,~)
        st2 = guidata(fig);
        if numel(st2.epochs) <= 1
            setStatus('Cannot delete the last remaining epoch.', C.warn);
            return;
        end

        idx = st2.currentEpoch;
        nm = st2.epochs(idx).name;

        st2.epochs(idx) = [];
        st2.seedResults(:,idx) = [];
        st2.roiResults(:,idx) = [];
        st2.compResults(:,idx) = [];
        st2.groupSeedStats(idx) = [];
        st2.groupRoiStats(idx) = [];

        st2.currentEpoch = min(idx, numel(st2.epochs));
        ep = st2.epochs(st2.currentEpoch);
        st2.analysisSecStart = ep.start;
        st2.analysisSecEnd   = ep.end;

        guidata(fig, st2);

        set(lbEpochs,'String',fc_epoch_name_list(st2.epochs), 'Value',st2.currentEpoch);
        set(edAnaStart,'String',fc_num_to_str(ep.start));
        set(edAnaEnd,'String',fc_num_to_str(ep.end));

        setStatus(['Deleted epoch: ' nm], C.good);
        refreshAll();
    end

    function onWindowEdit(~,~)
        st2 = guidata(fig);
        st2.analysisSecStart = fc_read_window(edAnaStart, st2.analysisSecStart);
        st2.analysisSecEnd   = fc_read_window(edAnaEnd, st2.analysisSecEnd);
        st2.baseSecStart     = fc_read_window(edBaseStart, st2.baseSecStart);
        st2.baseSecEnd       = fc_read_window(edBaseEnd, st2.baseSecEnd);
        st2.signalSecStart   = fc_read_window(edSigStart, st2.signalSecStart);
        st2.signalSecEnd     = fc_read_window(edSigEnd, st2.signalSecEnd);
        guidata(fig, st2);
        refreshSeedView();
        refreshHeatmapView();
    end

    function onPlacementModeChanged(~,~)
        st2 = guidata(fig);
        if get(ddPlacementMode,'Value') == 1
            st2.placementMode = 'window_mean';
        else
            st2.placementMode = 'signal_minus_baseline';
        end
        guidata(fig, st2);
        refreshSeedView();
    end

    function onPlacementAlpha(~,~)
        st2 = guidata(fig);
        st2.placementAlpha = get(slPlacementAlpha,'Value');
        guidata(fig, st2);
        refreshSeedView();
    end

    function onSeedXYEdit(~,~)
        st2 = guidata(fig);
        vx = str2double(get(edSeedX,'String'));
        vy = str2double(get(edSeedY,'String'));
        if ~isfinite(vx), vx = st2.seedX; end
        if ~isfinite(vy), vy = st2.seedY; end
        st2.seedX = fc_clamp(round(vx), 1, st2.X);
        st2.seedY = fc_clamp(round(vy), 1, st2.Y);
        set(edSeedX,'String',sprintf('%d',st2.seedX));
        set(edSeedY,'String',sprintf('%d',st2.seedY));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onSeedREdit(~,~)
    st2 = guidata(fig);
    vr = str2double(get(edSeedR,'String'));
    if ~isfinite(vr), vr = st2.seedBoxSize; end
    st2.seedBoxSize = max(1, round(vr));
    set(edSeedR,'String',sprintf('%d',st2.seedBoxSize));
    guidata(fig, st2);
    refreshSeedView();
end

    function onSliceOnly(~,~)
        st2 = guidata(fig);
        st2.useSliceOnly = logical(get(cbSliceOnly,'Value'));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onMapMode(~,evt)
        st2 = guidata(fig);
        if strcmpi(evt.NewValue.String,'Fisher z')
            st2.seedMapMode = 'z';
        else
            st2.seedMapMode = 'r';
        end
        guidata(fig, st2);
        refreshSeedView();
    end

    function onThr(~,~)
        st2 = guidata(fig);
        st2.seedAbsThr = get(slThr,'Value');
        set(txtThr,'String',sprintf('|r| >= %.2f',st2.seedAbsThr));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onAlpha(~,~)
        st2 = guidata(fig);
        st2.seedAlpha = get(slAlpha,'Value');
        guidata(fig, st2);
        refreshSeedView();
    end

    function onTraceColor(~,~)
        st2 = guidata(fig);
        c = uisetcolor(st2.seedTSColor, 'Choose seed trace color');
        if numel(c) == 3
            st2.seedTSColor = c;
            guidata(fig, st2);
            refreshSeedView();
        end
    end

    function onHistColor(~,~)
        st2 = guidata(fig);
        c = uisetcolor(st2.seedHistColor, 'Choose histogram color');
        if numel(c) == 3
            st2.seedHistColor = c;
            guidata(fig, st2);
            refreshSeedView();
        end
    end

    function onHMMatrixType(~,~)
        st2 = guidata(fig);
        lst = fc_roi_method_list();
        st2.hmMatrixType = fc_roi_method_code(lst{get(ddHMMatrix,'Value')});
        st2.roiMethod = st2.hmMatrixType;
        guidata(fig, st2);
        refreshHeatmapView();
        refreshPairView();
        refreshGraphView();
    end

    function onHMSpace(~,~)
        st2 = guidata(fig);
        if get(ddHMSpace,'Value') == 1
            st2.hmDisplaySpace = 'r';
        else
            st2.hmDisplaySpace = 'z';
        end
        guidata(fig, st2);
        refreshHeatmapView();
    end

    function onHMCmap(~,~)
        st2 = guidata(fig);
        vals = {'bluewhitered','parula','hot','gray','jet'};
        st2.hmCmapName = vals{get(ddHMCmap,'Value')};
        guidata(fig, st2);
        refreshHeatmapView();
        refreshGroupView();
    end

    function onHMSign(~,~)
        st2 = guidata(fig);
        vals = {'abs','pos','neg','none'};
        st2.hmSignMode = vals{get(ddHMSign,'Value')};
        guidata(fig, st2);
        refreshHeatmapView();
    end

    function onHMThr(~,~)
        st2 = guidata(fig);
        v = str2double(get(edHMThr,'String'));
        if ~isfinite(v), v = st2.hmAbsThr; end
        st2.hmAbsThr = max(0, min(1, abs(v)));
        st2.roiAbsThr = st2.hmAbsThr;
        set(edHMThr,'String',sprintf('%.2f',st2.hmAbsThr));
        guidata(fig, st2);
        refreshHeatmapView();
        refreshGraphView();
    end

    function onReorder(~,~)
        st2 = guidata(fig);
        strs = get(ddHMOrder,'String');
        idx = get(ddHMOrder,'Value');
        choice = lower(strtrim(strs{idx}));

        if ~isempty(strfind(choice,'label'))
            st2.reorderMode = 'label';
        elseif ~isempty(strfind(choice,'ontology'))
            st2.reorderMode = 'ontology';
        else
            st2.reorderMode = 'none';
        end

        guidata(fig, st2);
        refreshHeatmapView();
        refreshPairView();
        refreshGraphView();
        refreshGroupView();
    end

    function onGroupTarget(~,~)
        st2 = guidata(fig);
        if get(ddGroupTarget,'Value') == 1
            st2.groupTarget = 'seed';
        else
            st2.groupTarget = 'roi';
        end
        guidata(fig, st2);
        refreshGroupView();
    end

    function onGroupAlpha(~,~)
        st2 = guidata(fig);
        v = str2double(get(edAlpha,'String'));
        if ~isfinite(v) || v <= 0 || v >= 1
            v = st2.groupAlpha;
        end
        st2.groupAlpha = v;
        set(edAlpha,'String',sprintf('%.3f',st2.groupAlpha));
        guidata(fig, st2);
        refreshGroupView();
    end

    function onGroupTest(~,~)
        st2 = guidata(fig);
        st2.groupTest = fc_group_test_code(get(ddGroupTest,'String'), get(ddGroupTest,'Value'));
        guidata(fig, st2);
    end

    function onGroupA(~,~)
        st2 = guidata(fig);
        st2.groupA = get(ddGroupA,'Value');
        guidata(fig, st2);
    end

    function onGroupB(~,~)
        st2 = guidata(fig);
        st2.groupB = get(ddGroupB,'Value');
        guidata(fig, st2);
    end

    function onMapClick(~,~)
        st2 = guidata(fig);
        cp = get(axSeedMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x < 1 || x > st2.X || y < 1 || y > st2.Y
            return;
        end
        st2.seedX = x;
        st2.seedY = y;
        set(edSeedX,'String',sprintf('%d',st2.seedX));
        set(edSeedY,'String',sprintf('%d',st2.seedY));
        guidata(fig, st2);
        refreshSeedView();
    end

    function onPairChanged(~,~)
        refreshPairView();
    end

    function onCompChanged(~,~)
        refreshCompView();
    end

    function onLoadDataset(~,~)
        st2 = guidata(fig);
        s = st2.subjects(st2.currentSubject);
        startDir = fc_pick_start_dir(s, st2.opts);

        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load dataset MAT (3D/4D)', startDir);
        if isequal(f,0), return; end

        S = load(fullfile(p,f));
        [Iraw, varName] = fc_pick_3d4d_from_mat(S);
        if isempty(Iraw)
            errordlg('No 3D/4D numeric dataset found in selected MAT.');
            return;
        end

        I4 = fc_force4d_single(Iraw);
        [Yi, Xi, Zi] = fc_spatial_size(I4);
        if Yi ~= st2.Y || Xi ~= st2.X || Zi ~= st2.Z
            errordlg('Loaded dataset spatial size does not match current GUI.');
            return;
        end

        st2.subjects(st2.currentSubject).I4 = I4;
        st2.subjects(st2.currentSubject).analysisDir = fc_find_analysis_dir_from_file(fullfile(p,f), st2.opts.saveRoot);

        epCount = numel(st2.epochs);
        st2.seedResults(st2.currentSubject, 1:epCount) = {[]};
        st2.roiResults(st2.currentSubject, 1:epCount)  = {[]};
        st2.compResults(st2.currentSubject, 1:epCount) = {[]};

        guidata(fig, st2);
        setStatus(['Loaded dataset variable: ' varName], C.good);
        refreshAll();
    end

    function onLoadMask(~,~)
        st2 = guidata(fig);
        s = st2.subjects(st2.currentSubject);
        startDir = fc_pick_start_dir(s, st2.opts);

        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load mask MAT', startDir);
        if isequal(f,0), return; end

        S = load(fullfile(p,f));
        m = fc_first_volume_from_mat(S, st2.Y, st2.X, st2.Z);
        if isempty(m)
            errordlg('No compatible mask volume found in selected MAT.');
            return;
        end

        st2.subjects(st2.currentSubject).mask = logical(m);

        epCount = numel(st2.epochs);
        st2.seedResults(st2.currentSubject, 1:epCount) = {[]};
        st2.roiResults(st2.currentSubject, 1:epCount)  = {[]};
        st2.compResults(st2.currentSubject, 1:epCount) = {[]};

        guidata(fig, st2);
        setStatus(['Loaded mask: ' fullfile(p,f)], C.good);
        refreshAll();
    end


function onLoadUnderlay(~,~)
    st2 = guidata(fig);
    s = st2.subjects(st2.currentSubject);
    startDir = fc_pick_start_dir(s, st2.opts);

    [f,p] = uigetfile( ...
        {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay files'}, ...
         'Load underlay', startDir);

    if isequal(f,0), return; end

    [U,isRGB] = fc_read_underlay_file(fullfile(p,f), st2.Y, st2.X, st2.Z);

    st2.loadedUnderlay = U;
    st2.loadedUnderlayName = f;
    st2.loadedUnderlayIsRGB = isRGB;
    st2.underlayMode = 'loaded';

    guidata(fig, st2);
    setStatus(['Loaded underlay: ' fullfile(p,f)], C.good);
    refreshAll();
end

    function onLoadAtlas(~,~)
        st2 = guidata(fig);
        s = st2.subjects(st2.currentSubject);
        startDir = fc_pick_start_dir(s, st2.opts);

        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Load ROI atlas MAT', startDir);
        if isequal(f,0), return; end

        S = load(fullfile(p,f));
        a = fc_first_volume_from_mat(S, st2.Y, st2.X, st2.Z);
        if isempty(a)
            errordlg('No compatible ROI atlas found in selected MAT.');
            return;
        end

        st2.subjects(st2.currentSubject).roiAtlas = round(double(a));

        epCount = numel(st2.epochs);
        st2.roiResults(st2.currentSubject, 1:epCount) = {[]};

        guidata(fig, st2);
        setStatus(['Loaded ROI atlas: ' fullfile(p,f)], C.good);
        refreshAll();
    end

    function onComputeSeed(~,~)
        st2 = guidata(fig);
        ep = st2.currentEpoch;
        setStatus('Computing seed FC for current subject / current epoch...', C.accent);
        try
            subj = st2.subjects(st2.currentSubject);
            idxT = fc_analysis_frames(subj.TR, size(subj.I4,4), st2.analysisSecStart, st2.analysisSecEnd);

           res = fc_compute_seed_fc( ...
    subj.I4(:,:,:,idxT), subj.TR, subj.mask, ...
    st2.seedX, st2.seedY, st2.slice, st2.seedBoxSize, st2.seedGeometry, ...
    st2.useSliceOnly, st2.opts.chunkVox);

            res.timeIdx = idxT;
            res.epochName = st2.epochs(ep).name;
            st2.seedResults{st2.currentSubject, ep} = res;

            guidata(fig, st2);
            setStatus(['Seed FC done: ' subj.name ' / ' st2.epochs(ep).name], C.good);
            refreshSeedView();
            switchPanel('seed');
        catch ME
            setStatus(['SEED ERROR: ' ME.message], C.warn);
            fc_log_stack(st2.opts, ME);
            if st2.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeROI(~,~)
        st2 = guidata(fig);
        ep = st2.currentEpoch;
        setStatus('Computing ROI FC for all subjects / current epoch...', C.accent);
        try
            for i = 1:st2.nSub
                subj = st2.subjects(i);
                if isempty(subj.roiAtlas)
                    error('Subject %d (%s) has no roiAtlas.', i, subj.name);
                end

                idxT = fc_analysis_frames(subj.TR, size(subj.I4,4), st2.analysisSecStart, st2.analysisSecEnd);
                res = fc_compute_roi_fc(subj.I4(:,:,:,idxT), subj.TR, subj.mask, subj.roiAtlas, st2.opts);
                res.timeIdx = idxT;
                res.epochName = st2.epochs(ep).name;
                st2.roiResults{i, ep} = res;
            end

            guidata(fig, st2);
            setStatus(['ROI FC done for all subjects / ' st2.epochs(ep).name], C.good);
            refreshHeatmapView();
            refreshPairView();
            refreshGraphView();
            switchPanel('heatmap');
        catch ME
            setStatus(['ROI ERROR: ' ME.message], C.warn);
            fc_log_stack(st2.opts, ME);
            if st2.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeGroup(~,~)
        st2 = guidata(fig);
        ep = st2.currentEpoch;
        setStatus('Computing group statistics for current epoch...', C.accent);
        try
            if strcmpi(st2.groupTarget,'seed')
                st2 = ensureAllSeed(st2);
                st2.groupSeedStats{ep} = fc_group_stats_seed(st2, ep);
                guidata(fig, st2);
                refreshGroupView();
                switchPanel('group');
                setStatus(['Group seed statistics done / ' st2.epochs(ep).name], C.good);
            else
                st2 = ensureAllROI(st2);
                st2.groupRoiStats{ep} = fc_group_stats_roi(st2, ep);
                guidata(fig, st2);
                refreshGroupView();
                switchPanel('group');
                setStatus(['Group ROI statistics done / ' st2.epochs(ep).name], C.good);
            end
        catch ME
            setStatus(['GROUP ERROR: ' ME.message], C.warn);
            fc_log_stack(st2.opts, ME);
            if st2.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeComp(~,~)
        st2 = guidata(fig);
        ep = st2.currentEpoch;
        setStatus('Computing PCA / ICA for current subject / current epoch...', C.accent);
        try
            subj = st2.subjects(st2.currentSubject);
            idxT = fc_analysis_frames(subj.TR, size(subj.I4,4), st2.analysisSecStart, st2.analysisSecEnd);
            st2.compResults{st2.currentSubject, ep} = fc_compute_components(subj.I4(:,:,:,idxT), subj.TR, subj.mask, st2.opts);
            guidata(fig, st2);
            refreshCompView();
            switchPanel('components');
            setStatus(['Components computed / ' st2.epochs(ep).name], C.good);
        catch ME
            setStatus(['COMP ERROR: ' ME.message], C.warn);
            fc_log_stack(st2.opts, ME);
            if st2.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onSave(~,~)
        st2 = guidata(fig);
        try
            out = struct();
            out.subjects        = st2.subjects;
            out.epochs          = st2.epochs;
            out.seedResults     = st2.seedResults;
            out.roiResults      = st2.roiResults;
            out.compResults     = st2.compResults;
            out.groupSeedStats  = st2.groupSeedStats;
            out.groupRoiStats   = st2.groupRoiStats;
            out.guiState        = st2;

            matFile = fullfile(st2.qcDir, ['FunctionalConnectivity_' st2.tag '.mat']);
            save(matFile, 'out', '-v7.3');

            fc_save_axes_png(axSeedMap, fig, fullfile(st2.qcDir, ['FC_seed_' st2.tag '.png']));
            fc_save_axes_png(axHM, fig, fullfile(st2.qcDir, ['FC_heatmap_' st2.tag '.png']));
            fc_save_axes_png(axGroupMain, fig, fullfile(st2.qcDir, ['FC_group_' st2.tag '.png']));
            fc_save_axes_png(axAdj, fig, fullfile(st2.qcDir, ['FC_graph_' st2.tag '.png']));
            fc_save_axes_png(axCompMap, fig, fullfile(st2.qcDir, ['FC_comp_' st2.tag '.png']));

            % export current heatmap CSV when possible
            try
                [Mexp, namesExp] = fc_get_current_heatmap_for_export(st2);
                if ~isempty(Mexp)
                    csvFile = fullfile(st2.qcDir, ['FC_heatmap_' st2.tag '.csv']);
                    fc_write_matrix_csv(csvFile, Mexp, namesExp);
                end
            catch
            end

            setStatus(['Saved outputs to ' st2.qcDir], C.good);
        catch ME
            setStatus(['SAVE ERROR: ' ME.message], C.warn);
            fc_log_stack(st2.opts, ME);
        end
    end

    function onHelp(~,~)
        fc_open_help_window(C);
    end

% =========================================================================
% REFRESH FUNCTIONS
% =========================================================================
    function refreshAll()
        st2 = guidata(fig);

        % keep controls synced
        set(lbEpochs,'String',fc_epoch_name_list(st2.epochs), 'Value',st2.currentEpoch);
       set(ddUnder,'String',fc_underlay_list(st2.subjects(st2.currentSubject), st2));
        set(edAnaStart,'String',fc_num_to_str(st2.analysisSecStart));
        set(edAnaEnd,'String',fc_num_to_str(st2.analysisSecEnd));
        set(edBaseStart,'String',fc_num_to_str(st2.baseSecStart));
        set(edBaseEnd,'String',fc_num_to_str(st2.baseSecEnd));
        set(edSigStart,'String',fc_num_to_str(st2.signalSecStart));
        set(edSigEnd,'String',fc_num_to_str(st2.signalSecEnd));
        set(edZ,'String',sprintf('%d',st2.slice));
        set(slZ,'Value',st2.slice);
        set(edSeedX,'String',sprintf('%d',st2.seedX));
        set(edSeedY,'String',sprintf('%d',st2.seedY));
        set(edSeedR,'String',sprintf('%d',st2.seedBoxSize));
        set(cbSliceOnly,'Value',double(st2.useSliceOnly));
        set(cbAtlasContours,'Value',double(st2.showAtlasContours));
        set(cbMaskOutline,'Value',double(st2.showMaskOutline));
        set(txtThr,'String',sprintf('|r| >= %.2f',st2.seedAbsThr));
        set(slThr,'Value',st2.seedAbsThr);
        set(slAlpha,'Value',st2.seedAlpha);
        set(slPlacementAlpha,'Value',st2.placementAlpha);
        set(edHMThr,'String',sprintf('%.2f',st2.hmAbsThr));
        set(edAlpha,'String',sprintf('%.3f',st2.groupAlpha));
        set(txtSummary,'String',fc_build_summary_text(st2));
        set(txtSeed,'String',fc_seed_string(st2));

        refreshSeedView();
        refreshHeatmapView();
        refreshPairView();
        refreshGroupView();
        refreshGraphView();
        refreshCompView();
    end

    function refreshSeedView()
        st2 = guidata(fig);
        subj = st2.subjects(st2.currentSubject);
        epName = st2.epochs(st2.currentEpoch).name;

     underRGB = fc_get_underlay_rgb(st2);
set(hUnder,'CData',underRGB);

        set(hCross1,'YData',[st2.seedY st2.seedY]);
        set(hCross2,'XData',[st2.seedX st2.seedX]);

        ttl = fc_seed_title(st2);
        set(txtSeedTitle,'String',[ttl ' | Epoch: ' epName]);

        ovRGB = nan(st2.Y, st2.X, 3);
        ovA   = zeros(st2.Y, st2.X);

        switch lower(st2.overlayMode)
            case 'none'
                % nothing

            case 'placement'
                ov = fc_get_placement_overlay_slice(st2);
                if ~isempty(ov)
                    clim = fc_auto_clim(ov(isfinite(ov)), 1);
                    ovRGB = fc_map_to_rgb(ov, hot(256), clim);
                    ovA = st2.placementAlpha * double(isfinite(ov));
                end

                case 'atlas_edges'
    atlasS = fc_get_atlas_slice(st2);
    if ~isempty(atlasS)
        [ovRGB, ovA] = fc_overlay_atlas_rgb(atlasS, C.outline);
    end

case 'mask_edges'
    if ~isempty(subj.mask)
        [ovRGB, ovA] = fc_overlay_mask_rgb(subj.mask(:,:,st2.slice), C.maskLine);
    end

            case 'atlas_labels'
                atlasS = fc_get_atlas_slice(st2);
                if ~isempty(atlasS)
                    cmapLbl = jet(256);
                    ovRGB = fc_map_to_rgb(double(atlasS), cmapLbl, [0 max(1,max(atlasS(:)))]);
                    ovA = 0.35 * double(atlasS > 0);
                end

            otherwise % seed_fc
                res = st2.seedResults{st2.currentSubject, st2.currentEpoch};
                if ~isempty(res)
                    rS = res.rMap(:,:,st2.slice);
                    zS = res.zMap(:,:,st2.slice);

                    vis = abs(rS) >= st2.seedAbsThr;
                    if ~isempty(subj.mask)
                        vis = vis & subj.mask(:,:,st2.slice);
                    end

                    if strcmpi(st2.seedMapMode,'z')
                        M = zS;
                        clim = fc_auto_clim(M(vis), 2.5);
                    else
                        M = rS;
                        clim = [-1 1];
                    end

                    ovRGB = fc_map_to_rgb(M, st2.fcCmap, clim);
                    ovA = st2.seedAlpha * double(vis);
                end
        end

        set(hOver,'CData',ovRGB, 'AlphaData',ovA);

        % atlas contours
        atlasRGB = nan(st2.Y, st2.X, 3);
        atlasA   = zeros(st2.Y, st2.X);
        if st2.showAtlasContours
            atlasS = fc_get_atlas_slice(st2);
            if ~isempty(atlasS)
                [atlasRGB, atlasA] = fc_overlay_atlas_rgb(atlasS, C.outline);
            end
        end
        set(hAtlasLine,'CData',atlasRGB, 'AlphaData',atlasA);

        % mask outline
        maskRGB = nan(st2.Y, st2.X, 3);
        maskA   = zeros(st2.Y, st2.X);
        if st2.showMaskOutline && ~isempty(subj.mask)
            [maskRGB, maskA] = fc_overlay_mask_rgb(subj.mask(:,:,st2.slice), C.maskLine);
        end
        set(hMaskLine,'CData',maskRGB, 'AlphaData',maskA);

        axis(axSeedMap,'image');
        axis(axSeedMap,'ij');
        axis(axSeedMap,'off');

        res = st2.seedResults{st2.currentSubject, st2.currentEpoch};
        if isempty(res)
            fc_plot_nodata(axSeedTS, 'Seed timecourse', C);
            fc_plot_nodata(axSeedHist, 'Correlation histogram', C);
            return;
        end

        ts = double(res.seedTS(:));
        tmin = ((0:numel(ts)-1) * subj.TR) / 60;

        cla(axSeedTS);
        plot(axSeedTS, tmin, ts, 'LineWidth',1.8, 'Color',st2.seedTSColor);
        set(axSeedTS,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        grid(axSeedTS,'on');
        xlabel(axSeedTS,'Time (min)','Color',C.fgDim);
        ylabel(axSeedTS,'a.u.','Color',C.fgDim);
        title(axSeedTS,'Seed timecourse','Color',C.fg,'FontWeight','bold');

        r = res.rMap(:);
        if ~isempty(subj.mask)
            m = subj.mask(:);
            r = r(m);
        end
        r = double(r(isfinite(r)));

        cla(axSeedHist);
        if isempty(r)
            fc_plot_nodata(axSeedHist,'Correlation histogram',C);
        else
            histogram(axSeedHist, r, 60, ...
                'FaceColor',st2.seedHistColor, ...
                'EdgeColor',max(0,0.65*st2.seedHistColor));
            set(axSeedHist,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axSeedHist,'on');
            xlabel(axSeedHist,'Pearson r','Color',C.fgDim);
            ylabel(axSeedHist,'Count','Color',C.fgDim);
            title(axSeedHist,'Correlation histogram','Color',C.fg,'FontWeight','bold');
        end
    end

    function refreshHeatmapView()
        st2 = guidata(fig);
        cla(axHM);
        cla(axHMTS);

        res = st2.roiResults{st2.currentSubject, st2.currentEpoch};
        if isempty(res)
            fc_plot_nodata(axHM,'ROI heatmap',C);
            fc_plot_nodata(axHMTS,'Selected ROI mean traces',C);
            set(txtHMInfo,'String','Heatmap not computed yet for current subject / epoch.');
            set(ddPairA,'String',{'n/a'},'Value',1);
            set(ddPairB,'String',{'n/a'},'Value',1);
            return;
        end

        M0 = fc_pick_roi_matrix(res, st2.hmMatrixType);
        [M0, names, order] = fc_reorder_matrix_names(M0, res.names, res.labels, st2.opts, st2.reorderMode);

        if strcmpi(st2.hmDisplaySpace,'z') && fc_is_correlation_like_method(st2.hmMatrixType)
            M = fc_atanh_clip(M0);
            M(1:size(M,1)+1:end) = 0;
            cLim = fc_auto_clim(M(triu(true(size(M)),1)), 2.5);
        else
            M = M0;
            if strcmpi(st2.hmMatrixType,'rv')
                cLim = [0 1];
            else
                cLim = [-1 1];
            end
        end

        Mdisp = fc_apply_matrix_display_filter(M, st2.hmAbsThr, st2.hmSignMode);

        imagesc(axHM, Mdisp, cLim);
        axis(axHM,'image');
        set(axHM,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        colormap(axHM, fc_named_cmap(st2.hmCmapName, 256));
        xlabel(axHM,'ROI','Color',C.fgDim);
        ylabel(axHM,'ROI','Color',C.fgDim);
        title(axHM, ['ROI Heatmap - ' st2.subjects(st2.currentSubject).name ' - ' st2.epochs(st2.currentEpoch).name], ...
            'Color',C.fg,'FontWeight','bold');

        nR = size(Mdisp,1);
        if st2.hmShowLabels && nR <= 30
            set(axHM, 'XTick',1:nR, 'YTick',1:nR);
            set(axHM, 'XTickLabel',fc_shorten_name_list(names, 18), 'YTickLabel',fc_shorten_name_list(names, 18));
            try
                xtickangle(axHM,90);
            catch
            end
        else
            set(axHM, 'XTick',[], 'YTick',[]);
        end

        set(ddPairA,'String',names);
        set(ddPairB,'String',names);

        vA = get(ddPairA,'Value');
        vB = get(ddPairB,'Value');
        if isempty(vA) || vA < 1 || vA > numel(names), vA = 1; end
        if isempty(vB) || vB < 1 || vB > numel(names), vB = min(2,numel(names)); end
        set(ddPairA,'Value',vA);
        set(ddPairB,'Value',vB);

        rawA = order(vA);
        rawB = order(vB);

        tmin = ((0:size(res.meanTS,1)-1) * st2.subjects(st2.currentSubject).TR) / 60;
        ta = fc_zscore_safe(double(res.meanTS(:,rawA)));
        tb = fc_zscore_safe(double(res.meanTS(:,rawB)));

        plot(axHMTS, tmin, ta, 'LineWidth',1.4);
        hold(axHMTS,'on');
        plot(axHMTS, tmin, tb, 'LineWidth',1.4);
        hold(axHMTS,'off');
        set(axHMTS,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        grid(axHMTS,'on');
        xlabel(axHMTS,'Time (min)','Color',C.fgDim);
        ylabel(axHMTS,'z-scored','Color',C.fgDim);
        title(axHMTS,'Selected ROI mean traces','Color',C.fg,'FontWeight','bold');

        lg = legend(axHMTS, {fc_short_name(names{vA}), fc_short_name(names{vB})}, 'Location','best');
        try
            set(lg,'TextColor',C.fg,'Color',C.bgAx);
        catch
        end

        infoTxt = sprintf(['Subject: %s\nEpoch: %s\nnROI: %d\nMatrix: %s\nDisplay: %s\nSign mode: %s\nThreshold: %.2f\nReorder: %s'], ...
            st2.subjects(st2.currentSubject).name, st2.epochs(st2.currentEpoch).name, numel(names), ...
            st2.hmMatrixType, st2.hmDisplaySpace, st2.hmSignMode, st2.hmAbsThr, st2.reorderMode);
        set(txtHMInfo,'String',infoTxt);
    end

    function refreshPairView()
        st2 = guidata(fig);
        cla(axPairTS);
        cla(axPairScatter);
        cla(axPairLag);

        res = st2.roiResults{st2.currentSubject, st2.currentEpoch};
        if isempty(res)
            fc_plot_nodata(axPairTS,'Pair traces',C);
            fc_plot_nodata(axPairScatter,'Scatter',C);
            fc_plot_nodata(axPairLag,'Cross-corr',C);
            set(txtPairInfo,'String','ROI pair view not ready yet.');
            return;
        end

        M0 = fc_pick_roi_matrix(res, st2.hmMatrixType);
        [~, names, order] = fc_reorder_matrix_names(M0, res.names, res.labels, st2.opts, st2.reorderMode);

        if get(ddPairA,'Value') > numel(names), set(ddPairA,'Value',1); end
        if get(ddPairB,'Value') > numel(names), set(ddPairB,'Value',min(2,numel(names))); end

        aSel = get(ddPairA,'Value');
        bSel = get(ddPairB,'Value');

        a = order(aSel);
        b = order(bSel);

        tmin = ((0:size(res.meanTS,1)-1) * st2.subjects(st2.currentSubject).TR) / 60;
        ta = double(res.meanTS(:,a));
        tb = double(res.meanTS(:,b));

        plot(axPairTS, tmin, fc_zscore_safe(ta), 'LineWidth',1.4);
        hold(axPairTS,'on');
        plot(axPairTS, tmin, fc_zscore_safe(tb), 'LineWidth',1.4);
        hold(axPairTS,'off');
        set(axPairTS,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        grid(axPairTS,'on');
        xlabel(axPairTS,'Time (min)','Color',C.fgDim);
        ylabel(axPairTS,'z-scored','Color',C.fgDim);
        title(axPairTS,'ROI pair traces','Color',C.fg,'FontWeight','bold');

        lg = legend(axPairTS, {fc_short_name(names{aSel}), fc_short_name(names{bSel})}, 'Location','best');
        try
            set(lg,'TextColor',C.fg,'Color',C.bgAx);
        catch
        end

        scatter(axPairScatter, ta, tb, 22, 'filled');
        set(axPairScatter,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        grid(axPairScatter,'on');
        xlabel(axPairScatter, fc_short_name(names{aSel}), 'Color',C.fgDim);
        ylabel(axPairScatter, fc_short_name(names{bSel}), 'Color',C.fgDim);
        title(axPairScatter,'Scatter','Color',C.fg,'FontWeight','bold');

        maxLag = min(20, numel(ta)-1);
        if maxLag >= 1
            [xc, lags] = xcorr(fc_zscore_safe(ta), fc_zscore_safe(tb), maxLag, 'coeff');
            plot(axPairLag, lags * st2.subjects(st2.currentSubject).TR, xc, 'LineWidth',1.4);
            set(axPairLag,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axPairLag,'on');
            xlabel(axPairLag,'Lag (sec)','Color',C.fgDim);
            ylabel(axPairLag,'xcorr','Color',C.fgDim);
            title(axPairLag,'Cross-correlation','Color',C.fg,'FontWeight','bold');
        else
            fc_plot_nodata(axPairLag,'Cross-corr',C);
        end

        set(txtPairInfo,'String',fc_pair_info(res, a, b, names{aSel}, names{bSel}));
    end

    function refreshGroupView()
        st2 = guidata(fig);
        ep = st2.currentEpoch;
        cla(axGroupMain);
        cla(axGroupAux);

        if strcmpi(st2.groupTarget,'seed')
            G = st2.groupSeedStats{ep};
            if isempty(G)
                fc_plot_nodata(axGroupMain,'Group seed stats',C);
                fc_plot_nodata(axGroupAux,'q histogram',C);
                set(txtGroupInfo,'String','Group seed statistics not computed yet for current epoch.');
                return;
            end

            S = G.statMap(:,:,st2.slice);
            Q = G.qMap(:,:,st2.slice);
            S(Q > st2.groupAlpha) = 0;

            imagesc(axGroupMain, S);
            axis(axGroupMain,'image');
            axis(axGroupMain,'ij');
            axis(axGroupMain,'off');
            colormap(axGroupMain, fc_named_cmap(st2.hmCmapName, 256));
            title(axGroupMain, ['Group seed stats - ' st2.epochs(ep).name ' (BH-FDR masked)'], ...
                'Color',C.fg,'FontWeight','bold');

            qvals = G.qMap(G.maskGroup);
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                fc_plot_nodata(axGroupAux,'q histogram',C);
            else
                histogram(axGroupAux, qvals, 40, ...
                    'FaceColor',[0.30 0.70 1.00], ...
                    'EdgeColor',[0.20 0.50 0.90]);
                set(axGroupAux,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q','Color',C.fgDim);
                ylabel(axGroupAux,'Count','Color',C.fgDim);
                title(axGroupAux,'Voxel q histogram','Color',C.fg,'FontWeight','bold');
            end

            set(txtGroupInfo,'String',fc_group_seed_info(G, st2.groupAlpha));

        else
            G = st2.groupRoiStats{ep};
            if isempty(G)
                fc_plot_nodata(axGroupMain,'Group ROI stats',C);
                fc_plot_nodata(axGroupAux,'q histogram',C);
                set(txtGroupInfo,'String','Group ROI statistics not computed yet for current epoch.');
                return;
            end

            [Mshow, namesShow, order] = fc_reorder_matrix_names(G.statMatrix, G.names, G.labels, st2.opts, st2.reorderMode); %#ok<ASGLU>
            Qshow = G.qMatrix(order, order);
            Mshow(Qshow > st2.groupAlpha) = 0;

            imagesc(axGroupMain, Mshow);
            axis(axGroupMain,'image');
            set(axGroupMain,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            colormap(axGroupMain, fc_named_cmap(st2.hmCmapName, 256));
            xlabel(axGroupMain,'ROI','Color',C.fgDim);
            ylabel(axGroupMain,'ROI','Color',C.fgDim);
            title(axGroupMain, ['Group ROI stats - ' st2.epochs(ep).name ' (BH-FDR masked)'], ...
                'Color',C.fg,'FontWeight','bold');

            if numel(namesShow) <= 30
                set(axGroupMain, 'XTick',1:numel(namesShow), 'YTick',1:numel(namesShow));
                set(axGroupMain, 'XTickLabel',fc_shorten_name_list(namesShow,18), 'YTickLabel',fc_shorten_name_list(namesShow,18));
                try
                    xtickangle(axGroupMain,90);
                catch
                end
            else
                set(axGroupMain, 'XTick',[], 'YTick',[]);
            end

            qvals = G.qVector;
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                fc_plot_nodata(axGroupAux,'q histogram',C);
            else
                histogram(axGroupAux, qvals, 40, ...
                    'FaceColor',[0.30 0.70 1.00], ...
                    'EdgeColor',[0.20 0.50 0.90]);
                set(axGroupAux,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q','Color',C.fgDim);
                ylabel(axGroupAux,'Count','Color',C.fgDim);
                title(axGroupAux,'Edge q histogram','Color',C.fg,'FontWeight','bold');
            end

            set(txtGroupInfo,'String',fc_group_roi_info(G, st2.groupAlpha));
        end
    end

    function refreshGraphView()
        st2 = guidata(fig);
        cla(axAdj);
        cla(axDeg);

        res = st2.roiResults{st2.currentSubject, st2.currentEpoch};
        if isempty(res)
            fc_plot_nodata(axAdj,'Adjacency',C);
            fc_plot_nodata(axDeg,'Degree',C);
            set(txtGraphInfo,'String','Graph view not ready yet.');
            return;
        end

        M0 = fc_pick_roi_matrix(res, st2.hmMatrixType);
        [M, names] = fc_reorder_matrix_names(M0, res.names, res.labels, st2.opts, st2.reorderMode);
        Gg = fc_graph_summary(M, st2.hmAbsThr, names);

        imagesc(axAdj, Gg.A);
        axis(axAdj,'image');
        colormap(axAdj, gray(256));
        set(axAdj,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
        xlabel(axAdj,'ROI','Color',C.fgDim);
        ylabel(axAdj,'ROI','Color',C.fgDim);
        title(axAdj,'Adjacency (|edge| >= thr)','Color',C.fg,'FontWeight','bold');

        if size(Gg.A,1) <= 30
            set(axAdj, 'XTick',1:size(Gg.A,1), 'YTick',1:size(Gg.A,1));
            set(axAdj, 'XTickLabel',fc_shorten_name_list(names,18), 'YTickLabel',fc_shorten_name_list(names,18));
            try
                xtickangle(axAdj,90);
            catch
            end
        else
            set(axAdj, 'XTick',[], 'YTick',[]);
        end

        if isempty(Gg.degree)
            fc_plot_nodata(axDeg,'Degree',C);
        else
            histogram(axDeg, Gg.degree, ...
                'FaceColor',[0.30 0.70 1.00], ...
                'EdgeColor',[0.20 0.50 0.90]);
            set(axDeg,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axDeg,'on');
            xlabel(axDeg,'Degree','Color',C.fgDim);
            ylabel(axDeg,'Count','Color',C.fgDim);
            title(axDeg,'Degree histogram','Color',C.fg,'FontWeight','bold');
        end

        set(txtGraphInfo,'String',fc_graph_info(Gg));
    end

    function refreshCompView()
        st2 = guidata(fig);
        cla(axCompMap);
        cla(axCompTS);
        cla(axCompAux);

        res = st2.compResults{st2.currentSubject, st2.currentEpoch};
        if isempty(res)
            fc_plot_nodata(axCompMap,'Component map',C);
            fc_plot_nodata(axCompTS,'Component timecourse',C);
            fc_plot_nodata(axCompAux,'Summary',C);
            set(txtCompInfo,'String','Components not computed yet.');
            set(ddCompIdx,'String',{'1'},'Value',1);
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
        for k = 1:nComp
            strs{k} = sprintf('%d',k);
        end
        set(ddCompIdx,'String',strs);
        if get(ddCompIdx,'Value') > nComp, set(ddCompIdx,'Value',1); end
        k = get(ddCompIdx,'Value');

        if strcmpi(typ,'pca')
            vol = fc_masked_vec_to_vol(res.pcaSpatial(:,k), st2.subjects(st2.currentSubject).mask);
            imagesc(axCompMap, vol(:,:,st2.slice));
            axis(axCompMap,'image');
            axis(axCompMap,'off');
            colormap(axCompMap, fc_bluewhitered(256));
            title(axCompMap,['PCA component ' num2str(k)],'Color',C.fg,'FontWeight','bold');

            tmin = ((0:numel(res.pcaTS(:,k))-1) * st2.subjects(st2.currentSubject).TR) / 60;
            plot(axCompTS, tmin, res.pcaTS(:,k), 'LineWidth',1.5);
            set(axCompTS,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',C.fgDim);
            ylabel(axCompTS,'score','Color',C.fgDim);
            title(axCompTS,'PCA timecourse','Color',C.fg,'FontWeight','bold');

            nShow = min(10, numel(res.pcaExplained));
            bar(axCompAux, 100*res.pcaExplained(1:nShow));
            set(axCompAux,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Component','Color',C.fgDim);
            ylabel(axCompAux,'Explained var (%)','Color',C.fgDim);
            title(axCompAux,'PCA explained variance','Color',C.fg,'FontWeight','bold');

            set(txtCompInfo,'String',sprintf('PCA computed. nMasked=%d, nPCA=%d. Component %d: %.2f%% var.', ...
                res.nMasked, res.nPCA, k, 100*res.pcaExplained(k)));

        else
            vol = fc_masked_vec_to_vol(res.icaSpatial(:,k), st2.subjects(st2.currentSubject).mask);
            imagesc(axCompMap, vol(:,:,st2.slice));
            axis(axCompMap,'image');
            axis(axCompMap,'off');
            colormap(axCompMap, fc_bluewhitered(256));
            title(axCompMap,['ICA component ' num2str(k)],'Color',C.fg,'FontWeight','bold');

            tmin = ((0:numel(res.icaTS(:,k))-1) * st2.subjects(st2.currentSubject).TR) / 60;
            plot(axCompTS, tmin, res.icaTS(:,k), 'LineWidth',1.5);
            set(axCompTS,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',C.fgDim);
            ylabel(axCompTS,'source','Color',C.fgDim);
            title(axCompTS,'ICA timecourse','Color',C.fg,'FontWeight','bold');

            histogram(axCompAux, res.icaTS(:,k), 40, ...
                'FaceColor',[0.30 0.70 1.00], ...
                'EdgeColor',[0.20 0.50 0.90]);
            set(axCompAux,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Value','Color',C.fgDim);
            ylabel(axCompAux,'Count','Color',C.fgDim);
            title(axCompAux,'ICA histogram','Color',C.fg,'FontWeight','bold');

            set(txtCompInfo,'String',sprintf('ICA computed. nMasked=%d, nICA=%d.', res.nMasked, res.nICA));
        end
    end

    function st2 = ensureAllSeed(st2)
        ep = st2.currentEpoch;
        for i = 1:st2.nSub
            subj = st2.subjects(i);
            idxT = fc_analysis_frames(subj.TR, size(subj.I4,4), st2.analysisSecStart, st2.analysisSecEnd);

            need = false;
            if isempty(st2.seedResults{i,ep})
                need = true;
            else
                si = st2.seedResults{i,ep}.seedInfo;
                if si.seedX ~= st2.seedX || si.seedY ~= st2.seedY || si.seedZ ~= st2.slice || ...
                      si.seedBoxSize ~= st2.seedBoxSize || ~strcmpi(si.seedGeometry, st2.seedGeometry)
                    need = true;
                end
            end

            if need
                res = fc_compute_seed_fc( ...
                    subj.I4(:,:,:,idxT), subj.TR, subj.mask, ...
                    st2.seedX, st2.seedY, st2.slice, st2.seedR, ...
                    st2.useSliceOnly, st2.opts.chunkVox);
                res.timeIdx = idxT;
                res.epochName = st2.epochs(ep).name;
                st2.seedResults{i,ep} = res;
            end
        end
    end

    function st2 = ensureAllROI(st2)
        ep = st2.currentEpoch;
        for i = 1:st2.nSub
            if isempty(st2.roiResults{i,ep})
                subj = st2.subjects(i);
                if isempty(subj.roiAtlas)
                    error('Subject %d (%s) has no roiAtlas.', i, subj.name);
                end

                idxT = fc_analysis_frames(subj.TR, size(subj.I4,4), st2.analysisSecStart, st2.analysisSecEnd);
                res = fc_compute_roi_fc(subj.I4(:,:,:,idxT), subj.TR, subj.mask, subj.roiAtlas, st2.opts);
                res.timeIdx = idxT;
                res.epochName = st2.epochs(ep).name;
                st2.roiResults{i,ep} = res;
            end
        end
    end
end

% =========================================================================
% HELPERS (SELF-CONTAINED)
% =========================================================================
function rgb = fc_gray_to_rgb(img)
img = single(img);
mn = fc_prctile_safe(img(:),1);
mx = fc_prctile_safe(img(:),99);
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    mn = min(img(:));
    mx = max(img(:));
    if mx <= mn, mx = mn + 1; end
end
img = (img - mn) / (mx - mn);
img = max(0,min(1,img));
rgb = repmat(img,[1 1 3]);
end

function [U,isRGB] = fc_read_underlay_file(fullf, Y, X, Z)
U = [];
isRGB = false;

[~,~,ext] = fileparts(fullf);
ext = lower(ext);

isNiiGz = (numel(fullf) >= 7 && strcmpi(fullf(end-6:end), '.nii.gz'));

if isNiiGz
    tmpDir = tempname;
    mkdir(tmpDir);
    gunzip(fullf, tmpDir);
    d = dir(fullfile(tmpDir,'*.nii'));
    if isempty(d), error('Could not unzip NIfTI underlay.'); end
    U = double(niftiread(fullfile(tmpDir,d(1).name)));
    try, rmdir(tmpDir,'s'); catch, end
elseif strcmp(ext,'.nii')
    U = double(niftiread(fullf));
elseif strcmp(ext,'.mat')
    S = load(fullf);
    fn = fieldnames(S);
    for i = 1:numel(fn)
        x = S.(fn{i});
        if isnumeric(x) || islogical(x)
            U = double(x);
            break;
        elseif isstruct(x) && isfield(x,'Data') && isnumeric(x.Data)
            U = double(x.Data);
            break;
        end
    end
else
    U = double(imread(fullf));
end

if isempty(U)
    error('No usable underlay found.');
end

U = squeeze(U);

if ndims(U)==3 && size(U,3)==3
    isRGB = true;
    if max(U(:)) > 1, U = U/255; end
    return;
end

if ndims(U)==2
    if size(U,1)~=Y || size(U,2)~=X
        U = imresize(U,[Y X],'nearest');
    end
elseif ndims(U)==3
    if size(U,1)~=Y || size(U,2)~=X
        tmp = zeros(Y,X,size(U,3));
        for z = 1:size(U,3)
            tmp(:,:,z) = imresize(U(:,:,z),[Y X],'nearest');
        end
        U = tmp;
    end
    if size(U,3)~=Z
        zIdx = round(linspace(1,size(U,3),Z));
        zIdx = max(1,min(size(U,3),zIdx));
        U = U(:,:,zIdx);
    end
else
    error('Unsupported underlay dimensionality.');
end
end
function opts = fc_normalize_opts(opts)
if nargin < 1 || isempty(opts) || ~isstruct(opts), opts = struct(); end
if ~isfield(opts,'statusFcn'), opts.statusFcn = []; end
if ~isfield(opts,'logFcn'), opts.logFcn = []; end
if ~isfield(opts,'seedRadius') || isempty(opts.seedRadius), opts.seedRadius = 1; end
if ~isfield(opts,'chunkVox') || isempty(opts.chunkVox), opts.chunkVox = 6000; end
if ~isfield(opts,'useSliceOnly') || isempty(opts.useSliceOnly), opts.useSliceOnly = false; end
if ~isfield(opts,'roiMinVox') || isempty(opts.roiMinVox), opts.roiMinVox = 9; end
if ~isfield(opts,'roiAbsThr') || isempty(opts.roiAbsThr), opts.roiAbsThr = 0.20; end
if ~isfield(opts,'rvVarExplained') || isempty(opts.rvVarExplained), opts.rvVarExplained = 0.20; end
if ~isfield(opts,'askMaskAtStart') || isempty(opts.askMaskAtStart), opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart), opts.askAtlasAtStart = true; end
if ~isfield(opts,'functionalField'), opts.functionalField = ''; end
if ~isfield(opts,'roiNames'), opts.roiNames = {}; end
if ~isfield(opts,'roiOntology'), opts.roiOntology = []; end
if ~isfield(opts,'pcaN') || isempty(opts.pcaN), opts.pcaN = 10; end
if ~isfield(opts,'icaN') || isempty(opts.icaN), opts.icaN = 3; end
if ~isfield(opts,'debugRethrow') || isempty(opts.debugRethrow), opts.debugRethrow = false; end
end

function subjects = fc_normalize_subjects(dataIn, opts)
if iscell(dataIn)
    L = dataIn;
elseif isstruct(dataIn) && numel(dataIn) > 1
    L = cell(numel(dataIn),1);
    for i = 1:numel(dataIn)
        L{i} = dataIn(i);
    end
else
    L = {dataIn};
end

subjects = repmat(struct( ...
    'I4',[], ...
    'TR',1, ...
    'mask',[], ...
    'anat',[], ...
    'roiAtlas',[], ...
    'name','', ...
    'group','All', ...
    'pairID',[], ...
    'analysisDir',''), numel(L), 1);

for i = 1:numel(L)
    [subj, ok] = fc_one_subject(L{i}, opts, i);
    if ~ok
        error('Invalid subject at index %d.', i);
    end
    subjects(i) = subj;
end
end

function [subj, ok] = fc_one_subject(in, opts, idx)
ok = false;
subj = struct( ...
    'I4',[], ...
    'TR',1, ...
    'mask',[], ...
    'anat',[], ...
    'roiAtlas',[], ...
    'name',sprintf('Subject_%02d',idx), ...
    'group','All', ...
    'pairID',idx, ...
    'analysisDir','');

if isnumeric(in)
    subj.I4 = fc_force4d_single(in);
    subj.analysisDir = opts.saveRoot;
    ok = true;
    return;
end

if ~isstruct(in), return; end

if isfield(in,'name') && ~isempty(in.name), subj.name = char(in.name); end
if isfield(in,'group') && ~isempty(in.group), subj.group = char(in.group); end
if isfield(in,'pairID') && ~isempty(in.pairID), subj.pairID = in.pairID; end

if isfield(in,'TR') && ~isempty(in.TR)
    subj.TR = double(in.TR);
end
if ~isscalar(subj.TR) || ~isfinite(subj.TR) || subj.TR <= 0
    subj.TR = 1;
end

[Iraw, okI] = fc_extract_functional(in, opts);
if ~okI, return; end
subj.I4 = fc_force4d_single(Iraw);

[Y,X,Z] = fc_spatial_size(subj.I4);

if isfield(in,'mask') && ~isempty(in.mask)
    subj.mask = fc_interpret_vol(in.mask, Y, X, Z, true);
elseif isfield(in,'brainMask') && ~isempty(in.brainMask)
    subj.mask = fc_interpret_vol(in.brainMask, Y, X, Z, true);
end

if isfield(in,'anat') && ~isempty(in.anat)
    subj.anat = fc_interpret_vol(in.anat, Y, X, Z, false);
elseif isfield(in,'bg') && ~isempty(in.bg)
    subj.anat = fc_interpret_vol(in.bg, Y, X, Z, false);
end

if isfield(in,'roiAtlas') && ~isempty(in.roiAtlas)
    subj.roiAtlas = fc_interpret_vol(in.roiAtlas, Y, X, Z, false);
elseif isfield(in,'atlas') && ~isempty(in.atlas)
    subj.roiAtlas = fc_interpret_vol(in.atlas, Y, X, Z, false);
elseif isfield(in,'regions') && ~isempty(in.regions)
    subj.roiAtlas = fc_interpret_vol(in.regions, Y, X, Z, false);
end
if ~isempty(subj.roiAtlas)
    subj.roiAtlas = round(double(subj.roiAtlas));
end

subj.analysisDir = fc_infer_analysis_dir(in, opts.saveRoot);
ok = true;
end

function [Iraw, ok] = fc_extract_functional(s, opts)
ok = false;
Iraw = [];

if ~isempty(opts.functionalField) && isfield(s, opts.functionalField)
    x = s.(opts.functionalField);
    if isnumeric(x) && (ndims(x) == 3 || ndims(x) == 4)
        Iraw = x;
        ok = true;
        return;
    end
end

cand = {'I','PSC','data','functional','func','movie','volume'};
for i = 1:numel(cand)
    if isfield(s,cand{i}) && ~isempty(s.(cand{i})) && isnumeric(s.(cand{i})) && ...
            (ndims(s.(cand{i})) == 3 || ndims(s.(cand{i})) == 4)
        Iraw = s.(cand{i});
        ok = true;
        return;
    end
end

fn = fieldnames(s);
for i = 1:numel(fn)
    x = s.(fn{i});
    if isnumeric(x) && (ndims(x) == 3 || ndims(x) == 4)
        Iraw = x;
        ok = true;
        return;
    end
end
end

function I4 = fc_force4d_single(I)
sz = size(I);
if ndims(I) == 3
    Y = sz(1);
    X = sz(2);
    T = sz(3);
    I4 = reshape(single(I), Y, X, 1, T);
elseif ndims(I) == 4
    I4 = single(I);
else
    error('Functional data must be [Y X T] or [Y X Z T].');
end
end

function V = fc_interpret_vol(in, Y, X, Z, makeLogical)
V = [];
try
    if ndims(in) == 2 && Z == 1 && size(in,1)==Y && size(in,2)==X
        V = reshape(in, Y, X, 1);
    elseif ndims(in) == 3 && all(size(in)==[Y X Z])
        V = in;
    else
        return;
    end
    if makeLogical
        V = logical(V);
    end
catch
    V = [];
end
end

function [subjects, info] = fc_startup_mask_strategy(subjects, opts)
if ~opts.askMaskAtStart
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask)
            subjects(i).mask = fc_auto_mask(subjects(i).I4);
        end
    end
    info = 'Mask: auto for missing.';
    return;
end

hasAny = false;
for i = 1:numel(subjects)
    if ~isempty(subjects(i).mask)
        hasAny = true;
        break;
    end
end

if hasAny
    choice = questdlg('Mask selection at startup:', 'Mask startup', ...
        'Use provided masks', 'Auto masks', 'Load one common mask', 'Use provided masks');
else
    choice = questdlg('No masks provided. Choose startup mask:', 'Mask startup', ...
        'Auto masks', 'Load one common mask', 'Auto masks');
end

if isempty(choice), choice = 'Auto masks'; end

switch lower(strtrim(choice))
    case 'use provided masks'
        for i = 1:numel(subjects)
            if isempty(subjects(i).mask)
                subjects(i).mask = fc_auto_mask(subjects(i).I4);
            end
        end
        info = 'Mask: used provided masks; auto fallback.';
    case 'load one common mask'
        startDir = fc_pick_start_dir(subjects(1), opts);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select common mask MAT', startDir);
        if isequal(f,0)
            for i = 1:numel(subjects)
                subjects(i).mask = fc_auto_mask(subjects(i).I4);
            end
            info = 'Mask: user cancelled; used auto.';
        else
            S = load(fullfile(p,f));
            m = fc_first_volume_from_mat(S, size(subjects(1).I4,1), size(subjects(1).I4,2), size(subjects(1).I4,3));
            if isempty(m)
                error('Common mask MAT did not contain a compatible volume.');
            end
            m = logical(m);
            for i = 1:numel(subjects)
                subjects(i).mask = m;
            end
            info = ['Mask: loaded common mask: ' f];
        end
    otherwise
        for i = 1:numel(subjects)
            subjects(i).mask = fc_auto_mask(subjects(i).I4);
        end
        info = 'Mask: auto masks.';
end
end

function mask = fc_auto_mask(I4)
mimg = mean(I4,4);
thr = fc_prctile_safe(mimg(:), 25);
mask = logical(mimg > thr);
end

function atlas = fc_maybe_load_common_atlas(subjects, opts)
atlas = [];
q = questdlg('No roiAtlas found. Load a common ROI atlas MAT now?', 'ROI atlas', 'Yes','No','No');
if ~strcmpi(q,'Yes'), return; end

startDir = fc_pick_start_dir(subjects(1), opts);
[f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select ROI atlas MAT', startDir);
if isequal(f,0), return; end

S = load(fullfile(p,f));
[Y,X,Z] = fc_spatial_size(subjects(1).I4);
a = fc_first_volume_from_mat(S, Y, X, Z);
if isempty(a)
    errordlg('Selected atlas MAT did not contain a compatible volume.');
    return;
end
atlas = round(double(a));
end

function startDir = fc_pick_start_dir(subj, opts)
if isfield(subj,'analysisDir') && ~isempty(subj.analysisDir) && exist(subj.analysisDir,'dir')
    startDir = subj.analysisDir;
elseif isfield(opts,'saveRoot') && ~isempty(opts.saveRoot) && exist(opts.saveRoot,'dir')
    startDir = opts.saveRoot;
else
    startDir = pwd;
end
end

function analysisDir = fc_infer_analysis_dir(s, fallback)
analysisDir = '';

cand = {'analysisDir','analysedDir','analysisPath','resultsDir','outputDir','saveRoot'};
for i = 1:numel(cand)
    if isfield(s,cand{i}) && ~isempty(s.(cand{i}))
        p = char(s.(cand{i}));
        if exist(p,'dir')
            analysisDir = fc_find_analysed_subfolder(p, fallback);
            return;
        end
    end
end

cand2 = {'loadedPath','filePath','sourcePath','path','folder'};
for i = 1:numel(cand2)
    if isfield(s,cand2{i}) && ~isempty(s.(cand2{i}))
        p = char(s.(cand2{i}));
        if exist(p,'dir')
            analysisDir = fc_find_analysed_subfolder(p, fallback);
            return;
        elseif exist(p,'file')
            analysisDir = fc_find_analysed_subfolder(fileparts(p), fallback);
            return;
        end
    end
end

analysisDir = fallback;
if isempty(analysisDir), analysisDir = pwd; end
end

function outDir = fc_find_analysed_subfolder(baseDir, fallback)
outDir = '';
if isempty(baseDir) || ~exist(baseDir,'dir')
    outDir = fallback;
    return;
end

cand = { ...
    fullfile(baseDir,'AnalysedData'), ...
    fullfile(baseDir,'AnalyzedData'), ...
    fullfile(baseDir,'Analysed'), ...
    fullfile(baseDir,'Analyzed'), ...
    fullfile(baseDir,'Analysis'), ...
    fullfile(baseDir,'analysis')};

for i = 1:numel(cand)
    if exist(cand{i},'dir')
        outDir = cand{i};
        return;
    end
end
outDir = baseDir;
end

function dirOut = fc_find_analysis_dir_from_file(filePath, fallback)
dirOut = fallback;
try
    p = fileparts(filePath);
    dirOut = fc_find_analysed_subfolder(p, fallback);
catch
end
end

function V = fc_first_volume_from_mat(S, Y, X, Z)
V = [];
fn = fieldnames(S);
for i = 1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x)
        if ndims(x)==2 && Z==1 && size(x,1)==Y && size(x,2)==X
            V = reshape(x, Y, X, 1);
            return;
        elseif ndims(x)==3 && all(size(x)==[Y X Z])
            V = x;
            return;
        end
    end
end
end

function [Iraw, varName] = fc_pick_3d4d_from_mat(S)
Iraw = [];
varName = '';
fn = fieldnames(S);
cand = {};
for i = 1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        cand{end+1} = fn{i}; %#ok<AGROW>
    end
end

if isempty(cand), return; end
if numel(cand) == 1
    varName = cand{1};
    Iraw = S.(varName);
    return;
end

[sel, ok] = listdlg('PromptString','Select dataset variable:', ...
    'SelectionMode','single', ...
    'ListString',cand);

if ok && ~isempty(sel)
    varName = cand{sel};
else
    varName = cand{1};
end
Iraw = S.(varName);
end

function [Y,X,Z] = fc_spatial_size(I4)
sz = size(I4);
Y = sz(1);
X = sz(2);
Z = sz(3);
end

function stp = fc_slider_step(Z)
if Z <= 1
    stp = [1 1];
else
    stp = [1/(Z-1) min(10/(Z-1),1)];
end
end

function v = fc_clamp(v, lo, hi)
v = max(lo, min(hi, v));
end

function val = fc_read_window(h, fallback)
s = strtrim(get(h,'String'));
if strcmpi(s,'inf')
    val = inf;
    return;
end
v = str2double(s);
if ~isfinite(v)
    val = fallback;
else
    val = v;
end
end

function idxT = fc_analysis_frames(TR, T, sec0, sec1)
if ~isfinite(TR) || TR <= 0, TR = 1; end
sec = (0:T-1) * TR;
idxT = find(sec >= sec0 & sec <= sec1);
if isempty(idxT)
    idxT = 1:T;
end
end

function rgb = fc_get_underlay_rgb(st)
subj = st.subjects(st.currentSubject);
I4 = subj.I4;

meanImg = squeeze(mean(I4,4));
medImg  = squeeze(median(I4,4));

rgb = zeros(st.Y, st.X, 3, 'single');

switch lower(st.underlayMode)

    case 'loaded'
        if ~isempty(st.loadedUnderlay)
            U = st.loadedUnderlay;

            % RGB underlay already prepared
            if st.loadedUnderlayIsRGB
                if ndims(U) == 3 && size(U,3) == 3
                    rgb = single(U);
                    if max(rgb(:)) > 1
                        rgb = rgb ./ 255;
                    end
                    rgb = max(0, min(1, rgb));
                    return;
                else
                    rgb = fc_gray_to_rgb(U(:,:,st.slice));
                    return;
                end
            else
                if ndims(U) == 2
                    rgb = fc_gray_to_rgb(U);
                    return;
                elseif ndims(U) == 3
                    rgb = fc_gray_to_rgb(U(:,:,st.slice));
                    return;
                end
            end
        end

        % fallback if loaded mode selected but nothing valid موجود
        rgb = fc_gray_to_rgb(meanImg(:,:,st.slice));
        return;

    case 'median'
        rgb = fc_gray_to_rgb(medImg(:,:,st.slice));
        return;

    case 'anat'
        if ~isempty(subj.anat)
            rgb = fc_gray_to_rgb(subj.anat(:,:,st.slice));
        else
            rgb = fc_gray_to_rgb(meanImg(:,:,st.slice));
        end
        return;

    case 'atlas_labels'
        if ~isempty(subj.roiAtlas)
            atlasS = double(subj.roiAtlas(:,:,st.slice));
            cmapLbl = jet(256);
            rgb = fc_map_to_rgb(atlasS, cmapLbl, [0 max(1,max(atlasS(:)))]);
        else
            rgb = fc_gray_to_rgb(meanImg(:,:,st.slice));
        end
        return;

    otherwise
        rgb = fc_gray_to_rgb(meanImg(:,:,st.slice));
        return;
end
end

function ov = fc_get_placement_overlay_slice(st)
subj = st.subjects(st.currentSubject);
I4 = subj.I4;
TR = subj.TR;
T = size(I4,4);
sec = (0:T-1) * TR;

switch lower(st.placementMode)
    case 'signal_minus_baseline'
        ib = find(sec >= st.baseSecStart & sec <= st.baseSecEnd);
        is = find(sec >= st.signalSecStart & sec <= st.signalSecEnd);
        if isempty(ib) || isempty(is)
            ov = [];
            return;
        end
        mb = mean(I4(:,:,:,ib),4);
        ms = mean(I4(:,:,:,is),4);
        img = single(ms - mb);

    otherwise
        ia = find(sec >= st.analysisSecStart & sec <= st.analysisSecEnd);
        if isempty(ia), ia = 1:T; end
        img = single(mean(I4(:,:,:,ia),4));
end

ov = img(:,:,st.slice);
if ~isempty(subj.mask)
    m = subj.mask(:,:,st.slice);
    ov(~m) = NaN;
end
end

function atlasS = fc_get_atlas_slice(st)
subj = st.subjects(st.currentSubject);
atlasS = [];
if ~isempty(subj.roiAtlas)
    atlasS = double(subj.roiAtlas(:,:,st.slice));
end
end

function s = fc_seed_string(st)
s = sprintf('Seed: x=%d, y=%d, z=%d, size=%d (%s) | Epoch: %s', ...
    st.seedX, st.seedY, st.slice, st.seedBoxSize, st.seedGeometry, st.epochs(st.currentEpoch).name);
end

function t = fc_seed_title(st)
subj = st.subjects(st.currentSubject);
if strcmpi(st.overlayMode,'placement')
    t = ['Seed placement - ' subj.name];
elseif strcmpi(st.overlayMode,'atlas_labels')
    t = ['Atlas label overlay - ' subj.name];
elseif strcmpi(st.overlayMode,'none')
    t = ['Underlay only - ' subj.name];
else
    if strcmpi(st.seedMapMode,'z')
        t = ['Seed FC (Fisher z) - ' subj.name];
    else
        t = ['Seed FC (Pearson r) - ' subj.name];
    end
end
end

function lst = fc_underlay_list(subj, st)
lst = {'Mean (data)','Median (data)'};

if nargin >= 2 && isstruct(st) && isfield(st,'loadedUnderlay') && ~isempty(st.loadedUnderlay)
    lst{end+1} = 'Loaded underlay';
end

if ~isempty(subj.anat)
    lst{end+1} = 'Anat (provided)';
end

if ~isempty(subj.roiAtlas)
    lst{end+1} = 'Atlas labels';
end
end

function lst = fc_epoch_name_list(epochs)
lst = cell(numel(epochs),1);
for i = 1:numel(epochs)
    lst{i} = sprintf('%s [%s, %s]', epochs(i).name, fc_num_to_str(epochs(i).start), fc_num_to_str(epochs(i).end));
end
end

function s = fc_num_to_str(v)
if isinf(v)
    s = 'inf';
elseif isnan(v)
    s = 'NaN';
else
    s = num2str(v);
end
end

function nm = fc_sanitize_epoch_name(s, idx)
nm = strtrim(char(s));
if isempty(nm)
    nm = sprintf('Epoch_%02d', idx);
end
end

function [seedResults, roiResults, compResults, groupSeedStats, groupRoiStats] = ...
    fc_expand_epoch_storage(seedResults, roiResults, compResults, groupSeedStats, groupRoiStats)

nSub = size(seedResults,1);
nEpNew = size(seedResults,2) + 1;

seedResults(:,nEpNew) = cell(nSub,1);
roiResults(:,nEpNew)  = cell(nSub,1);
compResults(:,nEpNew) = cell(nSub,1);
groupSeedStats{nEpNew} = [];
groupRoiStats{nEpNew}  = [];
end

function lst = fc_roi_method_list()
lst = {'Mean Pearson','Mean Partial','PC1 Pearson','PC1 Partial','RV coefficient'};
end

function code = fc_roi_method_code(label)
s = lower(strtrim(label));
if ~isempty(strfind(s,'mean')) && ~isempty(strfind(s,'partial'))
    code = 'mean_partial';
elseif ~isempty(strfind(s,'mean')) && ~isempty(strfind(s,'pearson'))
    code = 'mean_pearson';
elseif ~isempty(strfind(s,'pc1')) && ~isempty(strfind(s,'partial'))
    code = 'pc1_partial';
elseif ~isempty(strfind(s,'pc1')) && ~isempty(strfind(s,'pearson'))
    code = 'pc1_pearson';
elseif ~isempty(strfind(s,'rv'))
    code = 'rv';
else
    code = 'mean_pearson';
end
end

function lst = fc_group_test_list()
lst = {'One-sample t-test','Paired t-test','Two-sample t-test', ...
       'One-sample Wilcoxon','Paired Wilcoxon','Two-sample Wilcoxon'};
end

function code = fc_group_test_code(listStr, idx)
s = lower(strtrim(listStr{idx}));
if ~isempty(strfind(s,'one')) && ~isempty(strfind(s,'t'))
    code = 'one_sample_t';
elseif ~isempty(strfind(s,'paired')) && ~isempty(strfind(s,'t'))
    code = 'paired_t';
elseif ~isempty(strfind(s,'two')) && ~isempty(strfind(s,'t'))
    code = 'two_sample_t';
elseif ~isempty(strfind(s,'one')) && ~isempty(strfind(s,'wilcoxon'))
    code = 'one_sample_wilcoxon';
elseif ~isempty(strfind(s,'paired')) && ~isempty(strfind(s,'wilcoxon'))
    code = 'paired_wilcoxon';
elseif ~isempty(strfind(s,'two')) && ~isempty(strfind(s,'wilcoxon'))
    code = 'two_sample_wilcoxon';
else
    code = 'one_sample_t';
end
end

function res = fc_compute_seed_fc(I4, TR, mask, seedX, seedY, seedZ, seedBoxSize, seedGeometry, useSliceOnly, chunkVox)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>
if isempty(mask)
    mask = fc_auto_mask(I4);
end

seedMask2D = fc_make_seed_mask(Y, X, seedY, seedX, seedBoxSize, seedGeometry);
seedMask3D = false(Y,X,Z);
seedMask3D(:,:,seedZ) = seedMask2D;
seedMask3D = seedMask3D & mask;
seedV = find(seedMask3D(:));

if isempty(seedV)
    seedMask3D = false(Y,X,Z);
    seedMask3D(seedY, seedX, seedZ) = true;
    seedV = find(seedMask3D(:));
end

V = Y*X*Z;
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
    voxMask = false(Y,X,Z);
    voxMask(:,:,seedZ) = mask(:,:,seedZ);
else
    voxMask = mask;
end
voxIdx = find(voxMask(:));
if isempty(voxIdx)
    error('Mask is empty for seed FC.');
end

chunk = max(1000, round(chunkVox));
sSingle = single(s);

for i0 = 1:chunk:numel(voxIdx)
    i1 = min(numel(voxIdx), i0+chunk-1);
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
res.TR = TR;
res.seedInfo = struct( ...
    'seedX',seedX, ...
    'seedY',seedY, ...
    'seedZ',seedZ, ...
    'seedBoxSize',seedBoxSize, ...
    'seedGeometry',seedGeometry, ...
    'useSliceOnly',useSliceOnly);
end

function res = fc_compute_roi_fc(I4, TR, mask, roiAtlas, opts)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>
if isempty(mask), mask = fc_auto_mask(I4); end

V = Y*X*Z;
Xvt = reshape(I4, [V T]);
maskV = mask(:);
atlasV = roiAtlas(:);

labelsAll = unique(atlasV(maskV & atlasV > 0));
labelsAll = labelsAll(:);

if isempty(labelsAll)
    error('No ROI labels inside mask.');
end

labels = [];
names = {};
counts = [];
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
    if isempty(Xroi), continue; end

    m = mean(Xroi,2);
    Xc = bsxfun(@minus, Xroi, mean(Xroi,1));

    if all(abs(Xc(:)) < eps)
        pc1 = m;
        rvF = fc_zscore_safe(m);
    else
        [U,S,~] = svd(Xc,'econ');
        pc1 = U(:,1) * S(1,1);
        if fc_corr_scalar(pc1, m) < 0, pc1 = -pc1; end

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

    labels(end+1,1) = lab; %#ok<AGROW>
    counts(end+1,1) = numel(idx); %#ok<AGROW>
    names{end+1,1} = fc_resolve_roi_name(lab, opts.roiNames); %#ok<AGROW>
    meanTS(:,end+1) = m; %#ok<AGROW>
    pc1TS(:,end+1) = pc1; %#ok<AGROW>
    rvFeat{end+1,1} = rvF; %#ok<AGROW>
end

if isempty(labels)
    error('No ROI survived roiMinVox.');
end

res = struct();
res.labels = labels;
res.counts = counts;
res.names = names;
res.meanTS = meanTS;
res.pc1TS = pc1TS;
res.M_mean_pearson = fc_corrcoef_safe(meanTS);
res.M_mean_partial = fc_partial_corr_safe(meanTS);
res.M_pc1_pearson  = fc_corrcoef_safe(pc1TS);
res.M_pc1_partial  = fc_partial_corr_safe(pc1TS);
res.M_rv = fc_rv_matrix(rvFeat);
res.TR = TR;
end

function out = fc_compute_components(I4, TR, mask, opts)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>
if isempty(mask), mask = fc_auto_mask(I4); end

V = Y*X*Z;
Xvt = reshape(I4, [V T]);
id = find(mask(:));
Xmask = double(Xvt(id,:))';
Xmask = bsxfun(@minus, Xmask, mean(Xmask,1));

[U,S,Vv] = svd(Xmask,'econ');
s2 = diag(S).^2;
expl = s2 / max(sum(s2), eps);

nPCA = min([opts.pcaN size(U,2) size(Vv,2)]);

out = struct();
out.TR = TR;
out.nMasked = numel(id);
out.nPCA = nPCA;
out.pcaTS = U(:,1:nPCA) * S(1:nPCA,1:nPCA);
out.pcaSpatial = Vv(:,1:nPCA);
out.pcaExplained = expl(:);
out.hasICA = false;
out.nICA = 0;
out.icaTS = [];
out.icaSpatial = [];

if exist('fastica','file') == 2
    try
        nICA = min([opts.icaN size(Xmask,2)-1]);
        if nICA >= 1
            [icasig, A, ~] = fastica(Xmask', 'numOfIC', nICA, 'verbose','off', 'displayMode','off');
            out.hasICA = true;
            out.nICA = nICA;
            out.icaTS = icasig';
            out.icaSpatial = A;
        end
    catch
        out.hasICA = false;
    end
end
end

function G = fc_group_stats_seed(st, ep)
groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};

idxA = find(fc_strcmp_cell(groups, grpAName));
idxB = find(fc_strcmp_cell(groups, grpBName));
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
    ZA(:,i) = double(st.seedResults{idxA(i),ep}.zMap(featIdx));
end

switch st.groupTest
    case 'one_sample_t'
        [stat,p,meanVal] = fc_stat_onesample_t(ZA);
    case 'one_sample_wilcoxon'
        [stat,p,meanVal] = fc_stat_onesample_signrank(ZA);
    case 'paired_t'
        ZB = fc_matched_seed_Z(st, idxA, idxB, featIdx, ep);
        [stat,p,meanVal] = fc_stat_paired_t(ZA, ZB);
    case 'paired_wilcoxon'
        ZB = fc_matched_seed_Z(st, idxA, idxB, featIdx, ep);
        [stat,p,meanVal] = fc_stat_paired_signrank(ZA, ZB);
    case 'two_sample_t'
        if isempty(idxB), error('Group B is empty.'); end
        ZB = zeros(numel(featIdx), numel(idxB));
        for i = 1:numel(idxB)
            ZB(:,i) = double(st.seedResults{idxB(i),ep}.zMap(featIdx));
        end
        [stat,p,meanVal] = fc_stat_twosample_t(ZA, ZB);
    case 'two_sample_wilcoxon'
        if isempty(idxB), error('Group B is empty.'); end
        ZB = zeros(numel(featIdx), numel(idxB));
        for i = 1:numel(idxB)
            ZB(:,i) = double(st.seedResults{idxB(i),ep}.zMap(featIdx));
        end
        [stat,p,meanVal] = fc_stat_twosample_ranksum(ZA, ZB);
    otherwise
        error('Unknown group test.');
end

q = nan(size(p));
q(isfinite(p)) = fc_bh_fdr(p(isfinite(p)));

statMap = nan(st.Y, st.X, st.Z);
pMap    = nan(st.Y, st.X, st.Z);
qMap    = nan(st.Y, st.X, st.Z);
meanMap = nan(st.Y, st.X, st.Z);

statMap(featIdx) = stat;
pMap(featIdx)    = p;
qMap(featIdx)    = q;
meanMap(featIdx) = meanVal;

G = struct();
G.test = st.groupTest;
G.groupA = grpAName;
G.groupB = grpBName;
G.nA = numel(idxA);
G.nB = numel(idxB);
G.maskGroup = maskGroup;
G.statMap = statMap;
G.pMap = pMap;
G.qMap = qMap;
G.meanMap = meanMap;
G.nSignificant = nnz(qMap(maskGroup) <= st.groupAlpha);
end

function ZB = fc_matched_seed_Z(st, idxA, idxB, featIdx, ep)
if isempty(idxB), error('Group B empty for paired test.'); end

pairA = cellfun(@fc_pair_to_string, {st.subjects(idxA).pairID}, 'UniformOutput', false);
pairB = cellfun(@fc_pair_to_string, {st.subjects(idxB).pairID}, 'UniformOutput', false);
common = intersect(pairA, pairB);

if isempty(common)
    nUse = min(numel(idxA), numel(idxB));
    idxB = idxB(1:nUse);
else
    keep = [];
    for i = 1:numel(common)
        ib = find(strcmp(pairB, common{i}), 1, 'first');
        if ~isempty(ib), keep(end+1) = idxB(ib); end %#ok<AGROW>
    end
    idxB = keep;
end

ZB = zeros(numel(featIdx), numel(idxB));
for i = 1:numel(idxB)
    ZB(:,i) = double(st.seedResults{idxB(i),ep}.zMap(featIdx));
end
end

function G = fc_group_stats_roi(st, ep)
groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};

idxA = find(fc_strcmp_cell(groups, grpAName));
idxB = find(fc_strcmp_cell(groups, grpBName));
if isempty(idxA), error('Group A is empty.'); end

labelSets = cell(st.nSub,1);
for i = 1:st.nSub
    labelSets{i} = st.roiResults{i,ep}.labels(:);
end

labels = labelSets{1};
for i = 2:st.nSub
    labels = intersect(labels, labelSets{i});
end
labels = labels(:);

if isempty(labels)
    error('No common ROI labels across subjects.');
end

method = st.hmMatrixType;
isFisher = fc_is_correlation_like_method(method);
nR = numel(labels);
stack = nan(nR,nR,st.nSub);
names = cell(nR,1);

for k = 1:nR
    names{k} = fc_resolve_roi_name(labels(k), st.opts.roiNames);
end

for s = 1:st.nSub
    res = st.roiResults{s,ep};
    M = fc_pick_roi_matrix(res, method);
    Ms = nan(nR,nR);
    for i = 1:nR
        ii = find(res.labels == labels(i), 1, 'first');
        for j = 1:nR
            jj = find(res.labels == labels(j), 1, 'first');
            if ~isempty(ii) && ~isempty(jj)
                Ms(i,j) = M(ii,jj);
            end
        end
    end
    if isFisher
        Ms = fc_atanh_clip(Ms);
    end
    stack(:,:,s) = Ms;
end

ut = find(triu(true(nR),1));
XA = reshape(stack(:,:,idxA), nR*nR, []);
XA = XA(ut,:);

switch st.groupTest
    case 'one_sample_t'
        [stat,p,meanVal] = fc_stat_onesample_t(XA);
    case 'one_sample_wilcoxon'
        [stat,p,meanVal] = fc_stat_onesample_signrank(XA);
    case 'paired_t'
        XB = fc_matched_roi_edges(st, stack, idxA, idxB, ut);
        [stat,p,meanVal] = fc_stat_paired_t(XA, XB);
    case 'paired_wilcoxon'
        XB = fc_matched_roi_edges(st, stack, idxA, idxB, ut);
        [stat,p,meanVal] = fc_stat_paired_signrank(XA, XB);
    case 'two_sample_t'
        if isempty(idxB), error('Group B is empty.'); end
        XB = reshape(stack(:,:,idxB), nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal] = fc_stat_twosample_t(XA, XB);
    case 'two_sample_wilcoxon'
        if isempty(idxB), error('Group B is empty.'); end
        XB = reshape(stack(:,:,idxB), nR*nR, []);
        XB = XB(ut,:);
        [stat,p,meanVal] = fc_stat_twosample_ranksum(XA, XB);
    otherwise
        error('Unknown group test.');
end

q = nan(size(p));
q(isfinite(p)) = fc_bh_fdr(p(isfinite(p)));

statM = zeros(nR);
pM = ones(nR);
qM = ones(nR);
meanM = zeros(nR);

statM(ut) = stat;
pM(ut) = p;
qM(ut) = q;
meanM(ut) = meanVal;

statM = statM + statM';
pM = pM + pM';
qM = qM + qM';
meanM = meanM + meanM';

statM(1:nR+1:end) = 0;
pM(1:nR+1:end) = 1;
qM(1:nR+1:end) = 1;
meanM(1:nR+1:end) = 0;

G = struct();
G.test = st.groupTest;
G.groupA = grpAName;
G.groupB = grpBName;
G.nA = numel(idxA);
G.nB = numel(idxB);
G.labels = labels;
G.names = names;
G.isFisher = isFisher;
G.statMatrix = statM;
G.pMatrix = pM;
G.qMatrix = qM;
G.qVector = q;
G.nSignificantEdges = nnz(q <= st.groupAlpha);
end

function XB = fc_matched_roi_edges(st, stack, idxA, idxB, ut)
if isempty(idxB), error('Group B empty for paired test.'); end

pairA = cellfun(@fc_pair_to_string, {st.subjects(idxA).pairID}, 'UniformOutput', false);
pairB = cellfun(@fc_pair_to_string, {st.subjects(idxB).pairID}, 'UniformOutput', false);
common = intersect(pairA, pairB);

if isempty(common)
    nUse = min(numel(idxA), numel(idxB));
    idxB = idxB(1:nUse);
else
    keep = [];
    for i = 1:numel(common)
        ib = find(strcmp(pairB, common{i}), 1, 'first');
        if ~isempty(ib), keep(end+1) = idxB(ib); end %#ok<AGROW>
    end
    idxB = keep;
end

nR = size(stack,1);
XB = reshape(stack(:,:,idxB), nR*nR, []);
XB = XB(ut,:);
end

function M = fc_pick_roi_matrix(res, method)
switch lower(method)
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
end

function [M2, names2, order] = fc_reorder_matrix_names(M, names, labels, opts, mode)
n = numel(labels);
order = (1:n)';

switch lower(mode)
    case 'label'
        [~, order] = sort(labels);
    case 'ontology'
        order = fc_ontology_order(names, labels, opts);
    otherwise
        order = (1:n)';
end

M2 = M(order, order);
names2 = names(order);
end

function order = fc_ontology_order(names, labels, opts)
n = numel(labels);
order = (1:n)';

if isfield(opts,'roiOntology') && ~isempty(opts.roiOntology)
    ont = opts.roiOntology;
    try
        if isnumeric(ont) && numel(ont) == n
            [~, order] = sortrows([ont(:) labels(:)], [1 2]);
            return;
        elseif iscell(ont) && numel(ont) == n
            [~, order] = sort(lower(ont(:)));
            return;
        end
    catch
    end
end

group = zeros(n,1);
hemi  = zeros(n,1);
for i = 1:n
    s = lower(names{i});
    if ~isempty(strfind(s,'ctx')) || ~isempty(strfind(s,'cortex'))
        group(i) = 1;
    elseif ~isempty(strfind(s,'thal'))
        group(i) = 2;
    elseif ~isempty(strfind(s,'hip'))
        group(i) = 3;
    elseif ~isempty(strfind(s,'str'))
        group(i) = 4;
    else
        group(i) = 9;
    end

    if ~isempty(strfind(s,'_l')) || ~isempty(strfind(s,' left')) || ~isempty(strfind(s,'-l'))
        hemi(i) = 1;
    elseif ~isempty(strfind(s,'_r')) || ~isempty(strfind(s,' right')) || ~isempty(strfind(s,'-r'))
        hemi(i) = 2;
    else
        hemi(i) = 0;
    end
end
[~, order] = sortrows([group hemi labels(:)], [1 2 3]);
end

function G = fc_graph_summary(M, thr, roiNames)
if isempty(M)
    G = struct('A',[],'degree',[],'density',NaN,'meanDegree',NaN,'meanClustering',NaN,'charPathLength',NaN,'nComponents',NaN,'topHubs',{{}});
    return;
end

A = abs(M) >= thr;
A(1:size(A,1)+1:end) = 0;
A = double(A);
deg = sum(A,2);
n = size(A,1);

if n <= 1
    density = NaN;
else
    density = nnz(triu(A,1)) / (n*(n-1)/2);
end

cc = zeros(n,1);
for i = 1:n
    nei = find(A(i,:));
    k = numel(nei);
    if k < 2
        cc(i) = 0;
    else
        sub = A(nei,nei);
        cc(i) = sum(sub(:)) / (k*(k-1));
    end
end

cpl = NaN;
comps = NaN;
try
    Gg = graph(A);
    D = distances(Gg);
    vals = D(isfinite(D) & D > 0);
    if ~isempty(vals), cpl = mean(vals); end
    comps = max(conncomp(Gg));
catch
end

[~, ord] = sort(deg, 'descend');
nHub = min(5, numel(ord));
top = cell(nHub,1);
for i = 1:nHub
    idx = ord(i);
    if ~isempty(roiNames) && idx <= numel(roiNames)
        top{i} = [fc_short_name(roiNames{idx}) ' (deg=' num2str(deg(idx)) ')'];
    else
        top{i} = ['ROI ' num2str(idx) ' (deg=' num2str(deg(idx)) ')'];
    end
end

G = struct();
G.A = A;
G.degree = deg;
G.density = density;
G.meanDegree = mean(deg);
G.meanClustering = mean(cc);
G.charPathLength = cpl;
G.nComponents = comps;
G.topHubs = top;
end

function s = fc_graph_info(G)
if isempty(G) || isempty(G.A)
    s = 'Graph view not ready.';
    return;
end
s = sprintf('Density: %.4f\nMean degree: %.2f\nMean clustering: %.3f\nChar path length: %.3f\nComponents: %d\n\nTop hubs:\n%s', ...
    G.density, G.meanDegree, G.meanClustering, G.charPathLength, G.nComponents, fc_join_lines(G.topHubs));
end

function s = fc_pair_info(res, ia, ib, nameA, nameB)
s = sprintf('Pair: %s <-> %s\nMean Pearson: %.4f\nMean Partial: %.4f\nPC1 Pearson: %.4f\nPC1 Partial: %.4f\nRV: %.4f', ...
    fc_short_name(nameA), fc_short_name(nameB), ...
    res.M_mean_pearson(ia,ib), res.M_mean_partial(ia,ib), ...
    res.M_pc1_pearson(ia,ib), res.M_pc1_partial(ia,ib), ...
    res.M_rv(ia,ib));
end

function s = fc_group_seed_info(G, alpha)
s = sprintf('Target: seed maps\nTest: %s\nGroup A: %s (n=%d)\nGroup B: %s (n=%d)\nBH q thr: %.3f\nSignificant voxels: %d', ...
    G.test, G.groupA, G.nA, G.groupB, G.nB, alpha, G.nSignificant);
end

function s = fc_group_roi_info(G, alpha)
s = sprintf('Target: ROI edges\nTest: %s\nGroup A: %s (n=%d)\nGroup B: %s (n=%d)\nROIs: %d\nBH q thr: %.3f\nSignificant edges: %d', ...
    G.test, G.groupA, G.nA, G.groupB, G.nB, numel(G.labels), alpha, G.nSignificantEdges);
end

function name = fc_resolve_roi_name(label, roiNames)
name = sprintf('ROI_%03d', label);
try
    if isempty(roiNames), return; end
    if iscell(roiNames)
        if label >= 1 && label <= numel(roiNames) && ~isempty(roiNames{label})
            name = char(roiNames{label});
        end
    elseif isstruct(roiNames)
        if isfield(roiNames,'label') && isfield(roiNames,'name')
            labs = [roiNames.label];
            idx = find(labs == label, 1, 'first');
            if ~isempty(idx)
                name = char(roiNames(idx).name);
            end
        end
    end
catch
end
end

function out = fc_join_lines(c)
if isempty(c)
    out = 'none';
    return;
end
out = c{1};
for i = 2:numel(c)
    out = sprintf('%s\n%s', out, c{i});
end
end

function s = fc_short_name(s0)
s = char(s0);
if numel(s) > 30
    s = [s(1:27) '...'];
end
end

function out = fc_shorten_name_list(c, n)
out = c;
for i = 1:numel(out)
    s = char(out{i});
    if numel(s) > n
        s = [s(1:max(1,n-3)) '...'];
    end
    out{i} = s;
end
end

function tf = fc_strcmp_cell(c, s)
tf = false(numel(c),1);
for i = 1:numel(c)
    tf(i) = strcmp(char(c{i}), char(s));
end
end

function out = fc_cellstr(c)
out = c;
for i = 1:numel(out)
    if isempty(out{i}), out{i} = ''; end
    out{i} = char(out{i});
end
end

function s = fc_pair_to_string(x)
if isnumeric(x)
    s = num2str(x);
elseif ischar(x)
    s = x;
else
    try
        s = char(x);
    catch
        s = '';
    end
end
end

function m = fc_disk_mask(Y, X, cy, cx, r)
m = false(Y,X);
if r <= 0
    if cy>=1 && cy<=Y && cx>=1 && cx<=X
        m(cy,cx) = true;
    end
    return;
end
[xx,yy] = meshgrid(1:X,1:Y);
m = ((xx-cx).^2 + (yy-cy).^2) <= r^2;
end

function m = fc_make_seed_mask(Y, X, cy, cx, boxSize, geometry)
m = false(Y,X);

if nargin < 6 || isempty(geometry)
    geometry = 'square';
end

switch lower(geometry)
    case 'disk'
        r = max(0, round(boxSize));
        m = fc_disk_mask(Y, X, cy, cx, r);

    otherwise
        hlf = floor(boxSize/2);
        x1 = max(1, cx-hlf);
        x2 = min(X, cx+hlf);
        y1 = max(1, cy-hlf);
        y2 = min(Y, cy+hlf);
        m(y1:y2, x1:x2) = true;
end
end


function clim = fc_auto_clim(vals, fallback)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    clim = [-fallback fallback];
    return;
end
p = fc_prctile_safe(abs(vals), 99);
if ~isfinite(p) || p <= 0, p = fallback; end
clim = [-p p];
end

function rgb = fc_map_to_rgb(M, cmap, clim)
M = double(M);
cmin = clim(1);
cmax = clim(2);

if ~isfinite(cmin) || ~isfinite(cmax) || cmax <= cmin
    cmin = min(M(:));
    cmax = max(M(:));
    if cmax <= cmin, cmax = cmin + 1; end
end

u = (M - cmin) / (cmax - cmin);
u = max(0, min(1, u));

idx = 1 + floor(u * (size(cmap,1)-1));
idx(~isfinite(idx)) = 1;
idx = max(1, min(size(cmap,1), idx));

rgb = zeros(size(M,1), size(M,2), 3, 'single');
for k = 1:3
    tmp = cmap(idx, k);
    rgb(:,:,k) = reshape(single(tmp), size(M,1), size(M,2));
end
end

function [rgb, A] = fc_overlay_atlas_rgb(atlasS, col)
edge = fc_edge_mask(atlasS > 0 & atlasS ~= 0, atlasS);
rgb = nan(size(atlasS,1), size(atlasS,2), 3);
for k = 1:3
    tmp = zeros(size(atlasS), 'single');
    tmp(edge) = single(col(k));
    rgb(:,:,k) = tmp;
end
A = 0.85 * double(edge);
end

function [rgb, A] = fc_overlay_mask_rgb(maskS, col)
edge = fc_edge_mask(maskS > 0, double(maskS));
rgb = nan(size(maskS,1), size(maskS,2), 3);
for k = 1:3
    tmp = zeros(size(maskS), 'single');
    tmp(edge) = single(col(k));
    rgb(:,:,k) = tmp;
end
A = 0.90 * double(edge);
end

function edge = fc_edge_mask(mask, labels)
edge = false(size(mask));
if nargin < 2 || isempty(labels)
    labels = double(mask);
end
if isempty(mask), return; end

edge(1:end-1,:) = edge(1:end-1,:) | (labels(1:end-1,:) ~= labels(2:end,:));
edge(:,1:end-1) = edge(:,1:end-1) | (labels(:,1:end-1) ~= labels(:,2:end));
edge = edge & mask;
end

function cmap = fc_named_cmap(name, n)
if nargin < 2, n = 256; end
switch lower(strtrim(name))
    case 'parula'
        cmap = parula(n);
    case 'hot'
        cmap = hot(n);
    case 'gray'
        cmap = gray(n);
    case 'jet'
        cmap = jet(n);
    otherwise
        cmap = fc_bluewhitered(n);
end
end

function cmap = fc_bluewhitered(n)
if nargin < 1, n = 256; end
n1 = floor(n/2);
n2 = n - n1;
b = [0.00 0.25 0.95];
w = [1 1 1];
r = [0.95 0.20 0.20];
c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];
cmap = [c1; c2];
end

function x = fc_prctile_safe(a, p)
a = double(a(:));
a = a(isfinite(a));
if isempty(a), x = NaN; return; end
a = sort(a);
if numel(a) == 1, x = a; return; end
t = (p/100) * (numel(a)-1) + 1;
i1 = floor(t);
i2 = ceil(t);
if i1 == i2
    x = a(i1);
else
    w = t - i1;
    x = (1-w)*a(i1) + w*a(i2);
end
end

function z = fc_zscore_safe(x)
x = double(x(:));
sd = std(x);
if ~isfinite(sd) || sd <= 0
    z = zeros(size(x));
else
    z = (x - mean(x)) / sd;
end
end

function r = fc_corr_scalar(x, y)
x = double(x(:));
y = double(y(:));
x = x - mean(x);
y = y - mean(y);
den = sqrt(sum(x.^2) * sum(y.^2));
if den <= 0 || ~isfinite(den)
    r = 0;
else
    r = sum(x.*y) / den;
end
end

function M = fc_corrcoef_safe(X)
X = double(X);
if isempty(X), M = []; return; end
X = bsxfun(@minus, X, mean(X,1));
sd = std(X,0,1);
sd(sd <= 0 | ~isfinite(sd)) = 1;
X = bsxfun(@rdivide, X, sd);
M = (X' * X) / max(1, size(X,1)-1);
M = max(-1, min(1, M));
M(1:size(M,1)+1:end) = 1;
end

function P = fc_partial_corr_safe(X)
R = fc_corrcoef_safe(X);
if isempty(R), P = []; return; end
n = size(R,1);
lam = 1e-6;
Ri = pinv(R + lam*eye(n));
d = sqrt(abs(diag(Ri)));
den = d*d';
P = -Ri ./ max(den, eps);
P(1:n+1:end) = 1;
P = max(-1, min(1, P));
end

function M = fc_rv_matrix(featCell)
n = numel(featCell);
M = eye(n);
for i = 1:n
    Xi = double(featCell{i});
    Xi = bsxfun(@minus, Xi, mean(Xi,1));
    for j = i+1:n
        Xj = double(featCell{j});
        Xj = bsxfun(@minus, Xj, mean(Xj,1));
        Sij = Xi' * Xj;
        Sii = Xi' * Xi;
        Sjj = Xj' * Xj;
        num = trace(Sij * Sij');
        den = sqrt(trace(Sii*Sii) * trace(Sjj*Sjj));
        if den <= 0 || ~isfinite(den)
            rv = 0;
        else
            rv = num / den;
        end
        rv = max(0, min(1, rv));
        M(i,j) = rv;
        M(j,i) = rv;
    end
end
M(1:n+1:end) = 1;
end

function Z = fc_atanh_clip(M)
Z = double(M);
Z = min(0.999999, max(-0.999999, Z));
Z = atanh(Z);
end

function tf = fc_is_correlation_like_method(method)
tf = ~strcmpi(method,'rv');
end

function Mout = fc_apply_matrix_display_filter(M, thr, signMode)
Mout = M;
switch lower(signMode)
    case 'pos'
        Mout(Mout < thr) = 0;
    case 'neg'
        Mout(Mout > -thr) = 0;
    case 'none'
        % no threshold
    otherwise
        Mout(abs(Mout) < thr) = 0;
end
end

function q = fc_bh_fdr(p)
p = p(:);
m = numel(p);
[ps, ord] = sort(p);
qs = ps .* m ./ (1:m)';
for i = m-1:-1:1
    qs(i) = min(qs(i), qs(i+1));
end
qs = min(qs, 1);
q = nan(size(p));
q(ord) = qs;
end

function [t,p,meanVal] = fc_stat_onesample_t(X)
n = sum(isfinite(X),2);
m = fc_nanmean(X,2);
sd = fc_nanstd(X,0,2);
se = sd ./ sqrt(max(n,1));
t = m ./ max(se, eps);
df = max(n-1, 1);
p = 2 * tcdf(-abs(t), df);
t(n<2) = NaN;
p(n<2) = NaN;
meanVal = m;
end

function [t,p,meanVal] = fc_stat_paired_t(A,B)
D = A - B;
[t,p,meanVal] = fc_stat_onesample_t(D);
end

function [t,p,meanVal] = fc_stat_twosample_t(A,B)
nA = sum(isfinite(A),2);
nB = sum(isfinite(B),2);
mA = fc_nanmean(A,2);
mB = fc_nanmean(B,2);
vA = fc_nanvar(A,0,2);
vB = fc_nanvar(B,0,2);

se = sqrt(vA./max(nA,1) + vB./max(nB,1));
t = (mA - mB) ./ max(se, eps);

df_num = (vA./max(nA,1) + vB./max(nB,1)).^2;
df_den = ((vA./max(nA,1)).^2 ./ max(nA-1,1)) + ((vB./max(nB,1)).^2 ./ max(nB-1,1));
df = df_num ./ max(df_den, eps);

p = 2 * tcdf(-abs(t), df);
bad = (nA<2) | (nB<2);
t(bad) = NaN;
p(bad) = NaN;
meanVal = mA - mB;
end

function [stat,p,meanVal] = fc_stat_onesample_signrank(X)
nF = size(X,1);
stat = nan(nF,1);
p = nan(nF,1);
meanVal = fc_nanmean(X,2);
for i = 1:nF
    xi = X(i,:);
    xi = xi(isfinite(xi));
    if numel(xi) >= 2
        p(i) = signrank(xi,0);
        stat(i) = median(xi);
    end
end
end

function [stat,p,meanVal] = fc_stat_paired_signrank(A,B)
D = A - B;
[stat,p,meanVal] = fc_stat_onesample_signrank(D);
end

function [stat,p,meanVal] = fc_stat_twosample_ranksum(A,B)
nF = size(A,1);
stat = nan(nF,1);
p = nan(nF,1);
meanVal = fc_nanmean(A,2) - fc_nanmean(B,2);
for i = 1:nF
    a = A(i,:);
    a = a(isfinite(a));
    b = B(i,:);
    b = b(isfinite(b));
    if ~isempty(a) && ~isempty(b)
        p(i) = ranksum(a,b);
        stat(i) = median(a) - median(b);
    end
end
end

function m = fc_nanmean(X, dim)
if nargin < 2, dim = 1; end
mask = isfinite(X);
num = sum(X .* mask, dim);
den = sum(mask, dim);
m = num ./ max(den,1);
m(den==0) = NaN;
end

function s = fc_nanstd(X, flag, dim)
if nargin < 2, flag = 0; end
if nargin < 3, dim = 1; end
m = fc_nanmean(X, dim);
Xm = bsxfun(@minus, X, m);
Xm(~isfinite(X)) = NaN;
mask = isfinite(Xm);
num = sum((Xm.^2) .* mask, dim);
den = sum(mask, dim);
if flag == 0
    den = max(den-1,1);
else
    den = max(den,1);
end
s = sqrt(num ./ den);
s(sum(mask,dim)==0) = NaN;
end

function v = fc_nanvar(X, flag, dim)
sd = fc_nanstd(X, flag, dim);
v = sd.^2;
end

function vol = fc_masked_vec_to_vol(vec, mask)
vol = zeros(size(mask),'single');
id = find(mask(:));
n = min(numel(id), numel(vec));
vol(id(1:n)) = single(vec(1:n));
end

function fc_plot_nodata(ax, ttl, C)
cla(ax);
text(ax,0.5,0.5,'No data', ...
    'HorizontalAlignment','center', ...
    'Color',C.fg);
set(ax,'Color',C.bgAx,'XColor',C.fgDim,'YColor',C.fgDim);
title(ax,ttl,'Color',C.fg,'FontWeight','bold');
end

function fc_save_axes_png(ax, fig, outFile)
tmp = figure('Visible','off');
ax2 = copyobj(ax, tmp);
set(ax2,'Units','normalized','Position',[0.08 0.08 0.84 0.84]);
set(tmp,'Color',get(fig,'Color'),'Position',[100 100 900 800]);
saveas(tmp, outFile);
close(tmp);
end

function fc_open_help_window(C)
hf = figure('Name','Functional Connectivity - Help', ...
    'Color',[0.06 0.06 0.07], ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Units','pixels', ...
    'Position',[150 80 1000 780]);

uipanel('Parent',hf,'Units','normalized','Position',[0.02 0.02 0.96 0.96], ...
    'BackgroundColor',[0.08 0.08 0.09], ...
    'ForegroundColor',C.fg, ...
    'Title','Functional Connectivity Tutorial', ...
    'FontWeight','bold','FontSize',13);

txt = [ ...
'INTRODUCTION',10, ...
'Functional connectivity (FC) measures similarity over time between brain signals.',10, ...
'This GUI supports seed FC, ROI heatmaps, pair analysis, group stats, graph summaries, and PCA/ICA.',10,10, ...
'WHAT TO LOAD',10, ...
'Load functional data as [Y X T] or [Y X Z T].',10, ...
'Optionally load a brain mask, anatomy underlay, and ROI atlas.',10, ...
'ROI atlas must be an integer label map in the same space as the functional data.',10,10, ...
'EPOCHS',10, ...
'Use the epoch manager to define named windows such as Pre, During, Post.',10, ...
'Seed/ROI/Group results are stored per epoch.',10,10, ...
'SEED FC',10, ...
'Place a seed and compute voxelwise correlation maps.',10, ...
'Use Fisher z for averaging/statistics and Pearson r for intuitive display.',10,10, ...
'HEATMAPS',10, ...
'ROI heatmaps are generated from atlas-defined regions.',10, ...
'You can change matrix type, display space, colormap, threshold, and ordering.',10,10, ...
'GROUP STATISTICS',10, ...
'Group seed stats operate voxelwise.',10, ...
'Group ROI stats operate on ROI-to-ROI edges.',10, ...
'Use paired tests when pairID matches across conditions.',10,10, ...
'RECOMMENDED WORKFLOW',10, ...
'1) Load dataset, mask, and ROI atlas.',10, ...
'2) Define epochs.',10, ...
'3) Compute Seed or ROI for the epoch of interest.',10, ...
'4) Inspect Heatmap / Pair / Group tabs.',10, ...
'5) Save MAT, PNG, and CSV exports.',10 ];

uicontrol('Parent',hf,'Style','edit','Max',80,'Min',0,'Enable','inactive', ...
    'Units','normalized','Position',[0.04 0.06 0.92 0.88], ...
    'String',txt, ...
    'HorizontalAlignment','left', ...
    'BackgroundColor',[0.10 0.10 0.11], ...
    'ForegroundColor',C.fg, ...
    'FontName','Courier New', ...
    'FontSize',11);
end

function fc_warnlog(opts, msg)
try
    if ~isempty(opts) && isstruct(opts) && isfield(opts,'logFcn') && ~isempty(opts.logFcn) && isa(opts.logFcn,'function_handle')
        opts.logFcn(msg);
    end
catch
end
end

function fc_log_stack(opts, ME)
try
    st = ME.stack;
    for k = 1:numel(st)
        fc_warnlog(opts, sprintf('[FC] at %s line %d (%s)', st(k).name, st(k).line, st(k).file));
    end
catch
end
end

function txt = fc_build_summary_text(st)
subj = st.subjects(st.currentSubject);

if isempty(subj.mask)
    maskTxt = 'no';
else
    maskTxt = 'yes';
end

if isempty(subj.roiAtlas)
    atlasTxt = 'no';
else
    atlasTxt = 'yes';
end

if isempty(subj.anat)
    anatTxt = 'no';
else
    anatTxt = 'yes';
end

txt = sprintf(['Subject: %s | TR: %.4g s | Size: [%d x %d x %d x %d]\n' ...
    'Epoch: %s [%s, %s] | Mask: %s | ROI atlas: %s | Anat: %s\n' ...
    'Underlay: %s | Overlay: %s | Slice: %d'], ...
    subj.name, subj.TR, size(subj.I4,1), size(subj.I4,2), size(subj.I4,3), size(subj.I4,4), ...
    st.epochs(st.currentEpoch).name, fc_num_to_str(st.analysisSecStart), fc_num_to_str(st.analysisSecEnd), ...
    maskTxt, atlasTxt, anatTxt, st.underlayMode, st.overlayMode, st.slice);
end

function [Mexp, namesExp] = fc_get_current_heatmap_for_export(st)
Mexp = [];
namesExp = {};

res = st.roiResults{st.currentSubject, st.currentEpoch};
if isempty(res), return; end

M0 = fc_pick_roi_matrix(res, st.hmMatrixType);
[M0, namesExp] = fc_reorder_matrix_names(M0, res.names, res.labels, st.opts, st.reorderMode);

if strcmpi(st.hmDisplaySpace,'z') && fc_is_correlation_like_method(st.hmMatrixType)
    Mexp = fc_atanh_clip(M0);
    Mexp(1:size(Mexp,1)+1:end) = 0;
else
    Mexp = M0;
end
end

function fc_write_matrix_csv(csvFile, M, names)
fid = fopen(csvFile,'w');
if fid < 0
    error('Could not open CSV file for writing.');
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'ROI');
for j = 1:numel(names)
    fprintf(fid, ',%s', fc_csv_escape(names{j}));
end
fprintf(fid, '\n');

for i = 1:size(M,1)
    fprintf(fid, '%s', fc_csv_escape(names{i}));
    for j = 1:size(M,2)
        fprintf(fid, ',%.10g', M(i,j));
    end
    fprintf(fid, '\n');
end
end

function s = fc_csv_escape(s0)
s = char(s0);
s = strrep(s, '"', '""');
s = ['"' s '"'];
end