function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity.m
% fUSI Studio - Functional Connectivity GUI
% MATLAB 2017b compatible, ASCII-only.
%
% This version restores the clean RIGHT-SIDE MODE TABS:
%   Seed Map | ROI Heatmap | Compare ROI | Pair | Graph
%
% Core workflow:
%   1) Load data / mask / ROI atlas / region names.
%   2) Compute seed-based voxelwise Pearson FC.
%   3) Compute atlas region-based Pearson FC.
%   4) Select a region such as CPU/CPu and compare it to all other regions.
%   5) Save MAT, PNG, and CSV outputs.
%
% INPUT
%   dataIn:
%       numeric [Y X T] or [Y X Z T]
%       struct with fields I / PSC / data / functional / func / movie / volume
%       cell array or struct array for multiple subjects
%
% OPTIONAL subject fields:
%   .TR
%   .mask / .brainMask
%   .anat / .bg
%   .roiAtlas / .atlas / .regions
%   .name
%   .group
%   .analysisDir / .loadedPath
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

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4 || isempty(opts), opts = struct(); end

opts = fc_defaults(opts);
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

[subjects, maskMsg] = fc_startup_masks(subjects, opts);

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

st.underlayMode = 'mean';    % mean / median / anat / atlas / loaded
st.overlayMode = 'seed_fc';  % seed_fc / atlas / mask / roi_compare / none

st.loadedUnderlay = [];
st.loadedUnderlayIsRGB = false;
st.loadedUnderlayName = '';

st.showAtlasLines = true;
st.showMaskLine = false;

st.seedAbsThr = 0.20;
st.seedAlpha = 0.70;
st.seedDisplay = 'z';        % z / r

st.roiAbsThr = 0.20;
st.roiDisplaySpace = 'r';    % r / z
st.roiOrder = 'label';       % label / name

st.compareROI = 1;
st.compareTopN = 20;
st.compareSort = 'abs';      % abs / positive / negative / label

st.seedResults = cell(nSub, numel(st.epochs));
st.roiResults  = cell(nSub, numel(st.epochs));

st.saveRoot = saveRoot;
st.tag = tag;
st.qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(st.qcDir,'dir'), mkdir(st.qcDir); end

st.opts = opts;

% -------------------------------------------------------------------------
% COLORS
% -------------------------------------------------------------------------
C = struct();
C.bgFig   = [0.05 0.05 0.06];
C.bgPane  = [0.08 0.08 0.09];
C.bgAx    = [0.10 0.10 0.11];
C.bgEdit  = [0.16 0.16 0.18];
C.bgBtn   = [0.24 0.24 0.28];
C.blue    = [0.12 0.40 0.82];
C.green   = [0.16 0.54 0.24];
C.red     = [0.70 0.20 0.20];
C.fg      = [0.94 0.94 0.96];
C.dim     = [0.72 0.72 0.76];
C.warn    = [1.00 0.35 0.35];
C.good    = [0.25 0.85 0.35];
C.cross   = [1.00 0.20 0.20];
C.line    = [0.95 0.95 0.95];
C.mask    = [0.20 0.95 0.40];

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

try, set(fig,'WindowState','maximized'); catch, end
try, set(fig,'Renderer','opengl'); catch, end

panelCtrl = uipanel('Parent',fig,'Units','normalized','Position',[0.01 0.02 0.39 0.96], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Controls','FontSize',13,'FontWeight','bold');

panelViewWrap = uipanel('Parent',fig,'Units','normalized','Position',[0.41 0.02 0.58 0.96], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'Title','Views','FontSize',13,'FontWeight','bold');

% -------------------------------------------------------------------------
% CONTROL PANELS
% -------------------------------------------------------------------------
pData = fc_panel(panelCtrl,[0.02 0.76 0.96 0.23],'Data / Atlas / Region names',C);
pSeed = fc_panel(panelCtrl,[0.02 0.58 0.96 0.17],'Seed FC',C);
pROI  = fc_panel(panelCtrl,[0.02 0.34 0.96 0.23],'Region-based FC',C);
pSave = fc_panel(panelCtrl,[0.02 0.18 0.96 0.15],'Overlay / Save',C);
pStat = fc_panel(panelCtrl,[0.02 0.02 0.96 0.15],'Status',C);

% -------------------------------------------------------------------------
% DATA PANEL
% -------------------------------------------------------------------------
fc_label(pData,[0.02 0.84 0.20 0.10],'Subject',C);

subNames = cell(nSub,1);
for i = 1:nSub
    subNames{i} = subjects(i).name;
end

ddSubject = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.72 0.46 0.12], ...
    'String',subNames,'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSubject);

fc_label(pData,[0.54 0.84 0.18 0.10],'Slice Z',C);

slSlice = uicontrol('Parent',pData,'Style','slider','Units','normalized', ...
    'Position',[0.54 0.75 0.30 0.08], ...
    'Min',1,'Max',max(1,Z),'Value',st.slice, ...
    'SliderStep',fc_slider_step(Z), ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onSliceSlider);

edSlice = uicontrol('Parent',pData,'Style','edit','Units','normalized', ...
    'Position',[0.86 0.72 0.10 0.12], ...
    'String',num2str(st.slice), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSliceEdit);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.53 0.22 0.12], ...
    'String','Load data', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadData);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.26 0.53 0.22 0.12], ...
    'String','Load mask', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadMask);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.50 0.53 0.22 0.12], ...
    'String','Load atlas', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadAtlas);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.74 0.53 0.22 0.12], ...
    'String','Load names', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadNames);

fc_label(pData,[0.02 0.36 0.20 0.10],'Underlay',C);
ddUnderlay = uicontrol('Parent',pData,'Style','popupmenu','Units','normalized', ...
    'Position',[0.02 0.25 0.30 0.12], ...
    'String',fc_underlay_list(st), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onUnderlay);

uicontrol('Parent',pData,'Style','pushbutton','Units','normalized', ...
    'Position',[0.34 0.25 0.24 0.12], ...
    'String','Load underlay', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadUnderlay);

cbAtlasLine = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.62 0.28 0.16 0.10], ...
    'String','Atlas lines', ...
    'Value',1, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onAtlasLine);

cbMaskLine = uicontrol('Parent',pData,'Style','checkbox','Units','normalized', ...
    'Position',[0.80 0.28 0.16 0.10], ...
    'String','Mask line', ...
    'Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onMaskLine);

txtSummary = uicontrol('Parent',pData,'Style','text','Units','normalized', ...
    'Position',[0.02 0.03 0.94 0.18], ...
    'String','', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontSize',9);

% -------------------------------------------------------------------------
% SEED PANEL
% -------------------------------------------------------------------------
fc_label(pSeed,[0.02 0.73 0.05 0.12],'X',C);
edSeedX = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.07 0.72 0.10 0.13], ...
    'String',num2str(st.seedX), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSeedEdit);

fc_label(pSeed,[0.20 0.73 0.05 0.12],'Y',C);
edSeedY = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.25 0.72 0.10 0.13], ...
    'String',num2str(st.seedY), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSeedEdit);

fc_label(pSeed,[0.39 0.73 0.10 0.12],'Size',C);
edSeedSize = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.48 0.72 0.10 0.13], ...
    'String',num2str(st.seedBoxSize), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSeedEdit);

cbSliceOnly = uicontrol('Parent',pSeed,'Style','checkbox','Units','normalized', ...
    'Position',[0.62 0.74 0.22 0.10], ...
    'String','Slice only', ...
    'Value',0, ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onSliceOnly);

fc_label(pSeed,[0.02 0.49 0.20 0.10],'Seed map',C);
ddSeedDisplay = uicontrol('Parent',pSeed,'Style','popupmenu','Units','normalized', ...
    'Position',[0.20 0.47 0.20 0.12], ...
    'String',{'Fisher z','Pearson r'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSeedDisplay);

fc_label(pSeed,[0.45 0.49 0.16 0.10],'|r| thr',C);
edSeedThr = uicontrol('Parent',pSeed,'Style','edit','Units','normalized', ...
    'Position',[0.60 0.47 0.10 0.12], ...
    'String',sprintf('%.2f',st.seedAbsThr), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onSeedThr);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.18 0.28 0.16], ...
    'String','Seed current', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeSeedCurrent);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.32 0.18 0.22 0.16], ...
    'String','Seed all', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeSeedAll);

uicontrol('Parent',pSeed,'Style','pushbutton','Units','normalized', ...
    'Position',[0.56 0.18 0.28 0.16], ...
    'String','Load SCM ROI TXT', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onLoadScmROI);

txtSeed = uicontrol('Parent',pSeed,'Style','text','Units','normalized', ...
    'Position',[0.02 0.03 0.94 0.10], ...
    'String','', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',9);

% -------------------------------------------------------------------------
% ROI PANEL
% -------------------------------------------------------------------------
uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.02 0.77 0.23 0.13], ...
    'String','ROI current', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeROICurrent);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.27 0.77 0.20 0.13], ...
    'String','ROI all', ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onComputeROIAll);

fc_label(pROI,[0.52 0.80 0.12 0.10],'Space',C);
ddROISpace = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.64 0.77 0.12 0.13], ...
    'String',{'r','z'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onROISpace);

fc_label(pROI,[0.79 0.80 0.08 0.10],'Thr',C);
edROIThr = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.87 0.77 0.09 0.13], ...
    'String',sprintf('%.2f',st.roiAbsThr), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onROIThr);

fc_label(pROI,[0.02 0.56 0.18 0.10],'Compare ROI',C);
ddCompareROI = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.20 0.54 0.42 0.13], ...
    'String',{'n/a'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onCompareROI);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.64 0.54 0.18 0.13], ...
    'String','Compare', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onCompareROI);

fc_label(pROI,[0.84 0.56 0.08 0.10],'Top',C);
edTopN = uicontrol('Parent',pROI,'Style','edit','Units','normalized', ...
    'Position',[0.91 0.54 0.06 0.13], ...
    'String',num2str(st.compareTopN), ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onTopN);

fc_label(pROI,[0.02 0.34 0.14 0.10],'Sort',C);
ddSort = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.16 0.32 0.20 0.13], ...
    'String',{'Abs','Positive','Negative','Label'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onCompareSort);

fc_label(pROI,[0.40 0.34 0.14 0.10],'Order',C);
ddOrder = uicontrol('Parent',pROI,'Style','popupmenu','Units','normalized', ...
    'Position',[0.54 0.32 0.20 0.13], ...
    'String',{'Label','Name'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onROIOrder);

uicontrol('Parent',pROI,'Style','pushbutton','Units','normalized', ...
    'Position',[0.76 0.32 0.20 0.13], ...
    'String','Export CSV', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onExportCSV);

txtROI = uicontrol('Parent',pROI,'Style','text','Units','normalized', ...
    'Position',[0.02 0.04 0.94 0.22], ...
    'String','Load ROI atlas and region names, then click ROI current. Select CPU/CPu in Compare ROI.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontSize',9);

% -------------------------------------------------------------------------
% OVERLAY / SAVE PANEL
% -------------------------------------------------------------------------
fc_label(pSave,[0.02 0.74 0.16 0.12],'Overlay',C);
ddOverlay = uicontrol('Parent',pSave,'Style','popupmenu','Units','normalized', ...
    'Position',[0.18 0.72 0.34 0.14], ...
    'String',{'Seed FC','Atlas lines','Mask line','ROI compare map','None'}, ...
    'Value',1, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onOverlay);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.55 0.72 0.18 0.14], ...
    'String','Refresh', ...
    'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg, ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@(~,~)refreshAll());

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.76 0.72 0.20 0.14], ...
    'String','Save all', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onSaveAll);

uicontrol('Parent',pSave,'Style','text','Units','normalized', ...
    'Position',[0.02 0.42 0.94 0.16], ...
    'String','Views are controlled by the right-side tabs above the plots.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontSize',9);

uicontrol('Parent',pSave,'Style','pushbutton','Units','normalized', ...
    'Position',[0.76 0.15 0.20 0.14], ...
    'String','Close', ...
    'BackgroundColor',C.red,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10, ...
    'Callback',@onClose);

txtStatus = uicontrol('Parent',pStat,'Style','text','Units','normalized', ...
    'Position',[0.02 0.05 0.94 0.86], ...
    'String',['Ready. ' maskMsg], ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.dim, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------------------------------------------------------------
% RIGHT-SIDE TAB STRIP
% -------------------------------------------------------------------------
tabNames = {'Seed Map','ROI Heatmap','Compare ROI','Pair','Graph'};
tabKeys  = {'seed','heatmap','compare','pair','graph'};
tabBtns = gobjects(numel(tabNames),1);

for k = 1:numel(tabNames)
    tabBtns(k) = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
        'Position',[0.02 + (k-1)*0.145 0.94 0.13 0.04], ...
        'String',tabNames{k}, ...
        'Value',double(k==1), ...
        'BackgroundColor',fc_if(k==1,C.blue,C.bgBtn), ...
        'ForegroundColor',fc_if(k==1,[1 1 1],C.fg), ...
        'FontWeight','bold','FontSize',10, ...
        'Callback',@(src,evt)switchTab(tabKeys{k}));
end

% -------------------------------------------------------------------------
% VIEW PANELS
% -------------------------------------------------------------------------
pSeedView = fc_view(panelViewWrap,C,'on');
pHeatView = fc_view(panelViewWrap,C,'off');
pCompView = fc_view(panelViewWrap,C,'off');
pPairView = fc_view(panelViewWrap,C,'off');
pGraphView = fc_view(panelViewWrap,C,'off');

viewPanels = struct();
viewPanels.seed = pSeedView;
viewPanels.heatmap = pHeatView;
viewPanels.compare = pCompView;
viewPanels.pair = pPairView;
viewPanels.graph = pGraphView;

% Seed Map tab
axMap = axes('Parent',pSeedView,'Units','normalized','Position',[0.04 0.08 0.58 0.84], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axis(axMap,'image'); axis(axMap,'off');

hUnder = image(axMap,fc_get_underlay(st));
hold(axMap,'on');
hOver = imagesc(axMap,nan(Y,X,3));
set(hOver,'AlphaData',0);
hAtlas = imagesc(axMap,nan(Y,X,3));
set(hAtlas,'AlphaData',0);
hMask = imagesc(axMap,nan(Y,X,3));
set(hMask,'AlphaData',0);
hCrossH = line(axMap,[1 X],[st.seedY st.seedY],'Color',C.cross,'LineWidth',1.1);
hCrossV = line(axMap,[st.seedX st.seedX],[1 Y],'Color',C.cross,'LineWidth',1.1);
hold(axMap,'off');

set([hUnder hOver hAtlas hMask],'ButtonDownFcn',@onMapClick);
set(axMap,'ButtonDownFcn',@onMapClick);

axSeedTS = axes('Parent',pSeedView,'Units','normalized','Position',[0.68 0.62 0.28 0.27], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axSeedHist = axes('Parent',pSeedView,'Units','normalized','Position',[0.68 0.21 0.28 0.27], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);

% ROI Heatmap tab
axHeat = axes('Parent',pHeatView,'Units','normalized','Position',[0.06 0.12 0.62 0.78], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axHeatTS = axes('Parent',pHeatView,'Units','normalized','Position',[0.72 0.60 0.24 0.27], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtHeat = uicontrol('Parent',pHeatView,'Style','text','Units','normalized', ...
    'Position',[0.72 0.14 0.24 0.38], ...
    'String','No heatmap yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',10);

% Compare ROI tab
axCompareBar = axes('Parent',pCompView,'Units','normalized','Position',[0.06 0.57 0.88 0.34], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axCompareMap = axes('Parent',pCompView,'Units','normalized','Position',[0.06 0.12 0.36 0.34], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axCompareTS = axes('Parent',pCompView,'Units','normalized','Position',[0.52 0.20 0.42 0.26], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtCompare = uicontrol('Parent',pCompView,'Style','text','Units','normalized', ...
    'Position',[0.52 0.05 0.42 0.11], ...
    'String','Compute ROI FC and select region.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',10);

% Pair tab
uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.05 0.93 0.08 0.04], ...
    'String','ROI A','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddPairA = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.13 0.93 0.34 0.04], ...
    'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onPair);

uicontrol('Parent',pPairView,'Style','text','Units','normalized','Position',[0.52 0.93 0.08 0.04], ...
    'String','ROI B','BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);

ddPairB = uicontrol('Parent',pPairView,'Style','popupmenu','Units','normalized', ...
    'Position',[0.60 0.93 0.34 0.04], ...
    'String',{'n/a'}, ...
    'BackgroundColor',C.bgEdit,'ForegroundColor',C.fg, ...
    'FontSize',10,'Callback',@onPair);

txtPair = uicontrol('Parent',pPairView,'Style','text','Units','normalized', ...
    'Position',[0.06 0.82 0.88 0.08], ...
    'String','No pair selected.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',10);

axPairTS = axes('Parent',pPairView,'Units','normalized','Position',[0.08 0.55 0.84 0.22], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axPairScat = axes('Parent',pPairView,'Units','normalized','Position',[0.08 0.18 0.38 0.28], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axPairLag = axes('Parent',pPairView,'Units','normalized','Position',[0.54 0.18 0.38 0.28], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);

% Graph tab
axAdj = axes('Parent',pGraphView,'Units','normalized','Position',[0.06 0.14 0.52 0.78], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
axDeg = axes('Parent',pGraphView,'Units','normalized','Position',[0.66 0.60 0.28 0.28], ...
    'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
txtGraph = uicontrol('Parent',pGraphView,'Style','text','Units','normalized', ...
    'Position',[0.64 0.14 0.32 0.38], ...
    'String','No graph yet.', ...
    'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontSize',10);

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

    function setStatus(msg,col)
        if nargin < 2, col = C.dim; end
        if ishandle(txtStatus)
            set(txtStatus,'String',msg,'ForegroundColor',col);
            drawnow limitrate;
        end
        fc_log(st.opts,msg);
    end

    function switchTab(whichTab)
        set(pSeedView,'Visible','off');
        set(pHeatView,'Visible','off');
        set(pCompView,'Visible','off');
        set(pPairView,'Visible','off');
        set(pGraphView,'Visible','off');

        for kk = 1:numel(tabBtns)
            set(tabBtns(kk),'Value',0,'BackgroundColor',C.bgBtn,'ForegroundColor',C.fg);
        end

        switch lower(whichTab)
            case 'seed'
                set(pSeedView,'Visible','on');
                idx = 1;
            case 'heatmap'
                set(pHeatView,'Visible','on');
                idx = 2;
            case 'compare'
                set(pCompView,'Visible','on');
                idx = 3;
            case 'pair'
                set(pPairView,'Visible','on');
                idx = 4;
            case 'graph'
                set(pGraphView,'Visible','on');
                idx = 5;
            otherwise
                set(pSeedView,'Visible','on');
                idx = 1;
        end

        set(tabBtns(idx),'Value',1,'BackgroundColor',C.blue,'ForegroundColor','w');
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
        if get(ddSeedDisplay,'Value') == 1
            s.seedDisplay = 'z';
        else
            s.seedDisplay = 'r';
        end
        guidata(fig,s);
        refreshSeedView();
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
        s.roiAbsThr = max(0,min(0.99,abs(v)));
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
            s.roiDisplaySpace = 'z';
        end
        guidata(fig,s);
        refreshHeatmapView();
    end

    function onROIOrder(~,~)
        s = guidata(fig);
        if get(ddOrder,'Value') == 1
            s.roiOrder = 'label';
        else
            s.roiOrder = 'name';
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
        val = get(ddUnderlay,'Value');
        choice = lower(lst{val});

        if ~isempty(strfind(choice,'loaded'))
            s.underlayMode = 'loaded';
        elseif ~isempty(strfind(choice,'median'))
            s.underlayMode = 'median';
        elseif ~isempty(strfind(choice,'anat'))
            s.underlayMode = 'anat';
        elseif ~isempty(strfind(choice,'atlas'))
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
                s.overlayMode = 'atlas';
            case 3
                s.overlayMode = 'mask';
            case 4
                s.overlayMode = 'roi_compare';
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
        s.seedX = x;
        s.seedY = y;
        guidata(fig,s);
        refreshAll();
    end

    function onLoadData(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'},'Load functional MAT',fc_start_dir(subj,s.opts));
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
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'},'Load mask MAT',fc_start_dir(subj,s.opts));
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
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'},'Load ROI atlas MAT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end

        S = load(fullfile(p,f));
        a = fc_pick_volume(S,s.Y,s.X,s.Z);
        if isempty(a)
            errordlg('No compatible ROI atlas volume found.');
            return;
        end

        choice = questdlg('Apply atlas to current subject or all subjects?', ...
            'ROI atlas','Current','All','Current');

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
        setStatus(['Loaded atlas: ' f],C.good);
        refreshAll();
    end

    function onLoadNames(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = uigetfile({'*.txt;*.csv;*.tsv;*.mat','Region names (*.txt,*.csv,*.tsv,*.mat)'}, ...
            'Load region names',fc_start_dir(subj,s.opts));
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
        [f,p] = uigetfile({'*.mat;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Underlay files'}, ...
            'Load underlay',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end

        try
            [U,isRGB] = fc_read_underlay(fullfile(p,f),s.Y,s.X,s.Z);
            s.loadedUnderlay = U;
            s.loadedUnderlayIsRGB = isRGB;
            s.loadedUnderlayName = f;
            s.underlayMode = 'loaded';
            guidata(fig,s);
            setStatus(['Loaded underlay: ' f],C.good);
            refreshAll();
        catch ME
            setStatus(['Underlay error: ' ME.message],C.warn);
        end
    end

    function onLoadScmROI(~,~)
        s = guidata(fig);
        subj = s.subjects(s.currentSubject);
        [f,p] = uigetfile({'*.txt','SCM ROI TXT (*.txt)'},'Load SCM ROI TXT',fc_start_dir(subj,s.opts));
        if isequal(f,0), return; end

        try
            info = fc_read_scm_roi(fullfile(p,f));
            s.seedX = round((info.x1 + info.x2)/2);
            s.seedY = round((info.y1 + info.y2)/2);
            s.seedBoxSize = max(info.x2-info.x1+1, info.y2-info.y1+1);

            if isfinite(info.slice)
                s.slice = fc_clip(round(info.slice),1,s.Z);
            end

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
            if s.opts.debugRethrow, rethrow(ME); end
        end
    end

    function s = computeROI(s,subIdx,epIdx)
        subj = s.subjects(subIdx);

        if isempty(subj.roiAtlas)
            error('No ROI atlas loaded for subject %s.',subj.name);
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

        set(edSeedThr,'String',sprintf('%.2f',s.seedAbsThr));
        set(edROIThr,'String',sprintf('%.2f',s.roiAbsThr));
        set(edTopN,'String',num2str(s.compareTopN));

        set(ddUnderlay,'String',fc_underlay_list(s));
        set(txtSummary,'String',fc_summary(s));
        set(txtSeed,'String',sprintf('Seed: x=%d, y=%d, z=%d, box=%d | slice-only=%d', ...
            s.seedX,s.seedY,s.slice,s.seedBoxSize,s.useSliceOnly));

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

        ovRGB = nan(s.Y,s.X,3);
        ovA = zeros(s.Y,s.X);

        switch lower(s.overlayMode)
            case 'seed_fc'
                res = s.seedResults{s.currentSubject,s.currentEpoch};
                if ~isempty(res)
                    rS = res.rMap(:,:,s.slice);
                    zS = res.zMap(:,:,s.slice);

                    vis = abs(rS) >= s.seedAbsThr;
                    if ~isempty(subj.mask)
                        vis = vis & subj.mask(:,:,s.slice);
                    end

                    if strcmpi(s.seedDisplay,'z')
                        M = zS;
                        clim = fc_auto_clim(M(vis),2.5);
                    else
                        M = rS;
                        clim = [-1 1];
                    end

                    ovRGB = fc_map_rgb(M,fc_bwr(256),clim);
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
                    ovRGB = fc_map_rgb(mapS,fc_bwr(256),[-1 1]);
                    ovA = 0.65 * double(isfinite(mapS) & abs(mapS) >= s.roiAbsThr);
                end
        end

        set(hOver,'CData',ovRGB,'AlphaData',ovA);

        atlasRGB = nan(s.Y,s.X,3);
        atlasA = zeros(s.Y,s.X);
        if s.showAtlasLines
            atlasS = fc_atlas_slice(s);
            if ~isempty(atlasS)
                [atlasRGB,atlasA] = fc_line_overlay(atlasS > 0,atlasS,C.line);
            end
        end
        set(hAtlas,'CData',atlasRGB,'AlphaData',atlasA);

        maskRGB = nan(s.Y,s.X,3);
        maskA = zeros(s.Y,s.X);
        if s.showMaskLine && ~isempty(subj.mask)
            [maskRGB,maskA] = fc_line_overlay(subj.mask(:,:,s.slice),double(subj.mask(:,:,s.slice)),C.mask);
        end
        set(hMask,'CData',maskRGB,'AlphaData',maskA);

        axis(axMap,'image');
        axis(axMap,'ij');
        axis(axMap,'off');

        res = s.seedResults{s.currentSubject,s.currentEpoch};
        if isempty(res)
            fc_nodata(axSeedTS,'Seed timecourse',C);
            fc_nodata(axSeedHist,'Correlation histogram',C);
            return;
        end

        ts = double(res.seedTS(:));
        t = ((0:numel(ts)-1) * subj.TR) / 60;

        cla(axSeedTS);
        plot(axSeedTS,t,ts,'LineWidth',1.5,'Color',[0.2 0.75 1.0]);
        fc_ax(axSeedTS,C);
        grid(axSeedTS,'on');
        xlabel(axSeedTS,'Time (min)','Color',C.dim);
        ylabel(axSeedTS,'a.u.','Color',C.dim);
        title(axSeedTS,'Seed timecourse','Color',C.fg);

        rr = double(res.rMap(:));
        if ~isempty(subj.mask)
            rr = rr(subj.mask(:));
        end
        rr = rr(isfinite(rr));

        cla(axSeedHist);
        if isempty(rr)
            fc_nodata(axSeedHist,'Correlation histogram',C);
        else
            histogram(axSeedHist,rr,60,'FaceColor',[0.2 0.65 1.0],'EdgeColor',[0.1 0.35 0.8]);
            fc_ax(axSeedHist,C);
            grid(axSeedHist,'on');
            xlabel(axSeedHist,'Pearson r','Color',C.dim);
            ylabel(axSeedHist,'Count','Color',C.dim);
            title(axSeedHist,'Correlation histogram','Color',C.fg);
        end
    end

    function refreshHeatmapView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        cla(axHeat);
        cla(axHeatTS);

        if isempty(res)
            fc_nodata(axHeat,'ROI heatmap',C);
            fc_nodata(axHeatTS,'ROI traces',C);
            set(txtHeat,'String','No ROI FC yet. Click ROI current.');
            updateROIDropdowns({'n/a'});
            return;
        end

        [M,names,order] = fc_current_matrix(s,res);

        Mshow = M;
        if strcmpi(s.roiDisplaySpace,'z')
            Mshow = fc_atanh_safe(Mshow);
            Mshow(1:size(Mshow,1)+1:end) = 0;
            clim = fc_auto_clim(Mshow(triu(true(size(Mshow)),1)),2.5);
        else
            clim = [-1 1];
        end

        Mdisp = Mshow;
        Mdisp(abs(Mdisp) < s.roiAbsThr) = 0;

        imagesc(axHeat,Mdisp,clim);
        axis(axHeat,'image');
        fc_ax(axHeat,C);
        colormap(axHeat,fc_bwr(256));
        title(axHeat,['ROI Pearson heatmap - ' s.subjects(s.currentSubject).name],'Color',C.fg);
        xlabel(axHeat,'ROI','Color',C.dim);
        ylabel(axHeat,'ROI','Color',C.dim);

        nR = size(Mdisp,1);
        if nR <= 35
            set(axHeat,'XTick',1:nR,'YTick',1:nR);
            set(axHeat,'XTickLabel',fc_short_list(names,18),'YTickLabel',fc_short_list(names,18));
            try, xtickangle(axHeat,90); catch, end
        else
            set(axHeat,'XTick',[],'YTick',[]);
        end

        updateROIDropdowns(names);

        a = get(ddPairA,'Value');
        b = get(ddPairB,'Value');
        a = fc_clip(a,1,numel(names));
        b = fc_clip(b,1,numel(names));

        rawA = order(a);
        rawB = order(b);

        t = ((0:size(res.meanTS,1)-1) * s.subjects(s.currentSubject).TR) / 60;
        plot(axHeatTS,t,fc_z(res.meanTS(:,rawA)),'LineWidth',1.4);
        hold(axHeatTS,'on');
        plot(axHeatTS,t,fc_z(res.meanTS(:,rawB)),'LineWidth',1.4);
        hold(axHeatTS,'off');
        fc_ax(axHeatTS,C);
        grid(axHeatTS,'on');
        xlabel(axHeatTS,'Time (min)','Color',C.dim);
        ylabel(axHeatTS,'z-scored','Color',C.dim);
        title(axHeatTS,'Selected ROI traces','Color',C.fg);
        legend(axHeatTS,{fc_short(names{a}),fc_short(names{b})},'Location','best');

        set(txtHeat,'String',sprintf(['Subject: %s\nROIs: %d\nDisplay: %s\nThreshold: %.2f\n\n' ...
            'Use Compare ROI to select CPU/CPu and plot correlation to all regions.'], ...
            s.subjects(s.currentSubject).name,numel(names),s.roiDisplaySpace,s.roiAbsThr));
    end

    function refreshCompareView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        cla(axCompareBar);
        cla(axCompareMap);
        cla(axCompareTS);

        if isempty(res)
            fc_nodata(axCompareBar,'ROI-to-all bar graph',C);
            fc_nodata(axCompareMap,'Atlas correlation map',C);
            fc_nodata(axCompareTS,'Traces',C);
            set(txtCompare,'String','Compute ROI FC first, then select CPU/CPu or any region.');
            return;
        end

        [M,names,order] = fc_current_matrix(s,res);
        updateROIDropdowns(names);

        sel = fc_clip(get(ddCompareROI,'Value'),1,numel(names));
        rawSel = order(sel);

        r = M(sel,:);
        r(sel) = NaN;

        [idxShow,valShow] = fc_rank_vector(r,s.compareTopN,s.compareSort);

        if isempty(idxShow)
            fc_nodata(axCompareBar,'ROI-to-all bar graph',C);
        else
            bar(axCompareBar,valShow);
            fc_ax(axCompareBar,C);
            grid(axCompareBar,'on');
            ylabel(axCompareBar,'Pearson r','Color',C.dim);
            title(axCompareBar,['Selected region: ' fc_short(names{sel})],'Color',C.fg);
            set(axCompareBar,'XTick',1:numel(idxShow),'XTickLabel',fc_short_list(names(idxShow),16));
            try, xtickangle(axCompareBar,60); catch, end
        end

        [mapS,ok] = fc_compare_slice(s);
        if ok
            imagesc(axCompareMap,mapS,[-1 1]);
            axis(axCompareMap,'image');
            axis(axCompareMap,'ij');
            axis(axCompareMap,'off');
            colormap(axCompareMap,fc_bwr(256));
            title(axCompareMap,'Atlas map: r to selected region','Color',C.fg);
        else
            fc_nodata(axCompareMap,'Atlas correlation map',C);
        end

        t = ((0:size(res.meanTS,1)-1) * s.subjects(s.currentSubject).TR) / 60;

        plot(axCompareTS,t,fc_z(res.meanTS(:,rawSel)),'LineWidth',1.8);
        hold(axCompareTS,'on');

        if ~isempty(idxShow)
            rawBest = order(idxShow(1));
            plot(axCompareTS,t,fc_z(res.meanTS(:,rawBest)),'LineWidth',1.4);
            legend(axCompareTS,{fc_short(names{sel}),fc_short(names{idxShow(1)})},'Location','best');
        end

        hold(axCompareTS,'off');
        fc_ax(axCompareTS,C);
        grid(axCompareTS,'on');
        xlabel(axCompareTS,'Time (min)','Color',C.dim);
        ylabel(axCompareTS,'z-scored','Color',C.dim);
        title(axCompareTS,'Selected ROI and strongest partner','Color',C.fg);

        if isempty(idxShow)
            txtTop = 'none';
        else
            nList = min(6,numel(idxShow));
            lines = cell(nList,1);
            for k = 1:nList
                lines{k} = sprintf('%s: %.3f',fc_short(names{idxShow(k)}),valShow(k));
            end
            txtTop = fc_join(lines);
        end

        set(txtCompare,'String',sprintf('Selected: %s\nLabel: %g\nTop partners:\n%s', ...
            names{sel},res.labels(rawSel),txtTop));
    end

    function refreshPairView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        cla(axPairTS);
        cla(axPairScat);
        cla(axPairLag);

        if isempty(res)
            fc_nodata(axPairTS,'Pair traces',C);
            fc_nodata(axPairScat,'Scatter',C);
            fc_nodata(axPairLag,'Cross-corr',C);
            set(txtPair,'String','No ROI result yet.');
            return;
        end

        [~,names,order] = fc_current_matrix(s,res);
        updateROIDropdowns(names);

        aSel = fc_clip(get(ddPairA,'Value'),1,numel(names));
        bSel = fc_clip(get(ddPairB,'Value'),1,numel(names));

        a = order(aSel);
        b = order(bSel);

        ta = double(res.meanTS(:,a));
        tb = double(res.meanTS(:,b));

        t = ((0:numel(ta)-1) * s.subjects(s.currentSubject).TR) / 60;

        plot(axPairTS,t,fc_z(ta),'LineWidth',1.4);
        hold(axPairTS,'on');
        plot(axPairTS,t,fc_z(tb),'LineWidth',1.4);
        hold(axPairTS,'off');
        fc_ax(axPairTS,C);
        grid(axPairTS,'on');
        xlabel(axPairTS,'Time (min)','Color',C.dim);
        ylabel(axPairTS,'z-scored','Color',C.dim);
        title(axPairTS,'ROI pair traces','Color',C.fg);
        legend(axPairTS,{fc_short(names{aSel}),fc_short(names{bSel})},'Location','best');

        scatter(axPairScat,ta,tb,22,'filled');
        fc_ax(axPairScat,C);
        grid(axPairScat,'on');
        xlabel(axPairScat,fc_short(names{aSel}),'Color',C.dim);
        ylabel(axPairScat,fc_short(names{bSel}),'Color',C.dim);
        title(axPairScat,'Scatter','Color',C.fg);

        maxLag = min(20,numel(ta)-1);
        if maxLag >= 1
            [xc,lags] = xcorr(fc_z(ta),fc_z(tb),maxLag,'coeff');
            plot(axPairLag,lags*s.subjects(s.currentSubject).TR,xc,'LineWidth',1.4);
            fc_ax(axPairLag,C);
            grid(axPairLag,'on');
            xlabel(axPairLag,'Lag (s)','Color',C.dim);
            ylabel(axPairLag,'xcorr','Color',C.dim);
            title(axPairLag,'Cross-correlation','Color',C.fg);
        else
            fc_nodata(axPairLag,'Cross-corr',C);
        end

        r = fc_corr_scalar(ta,tb);
        set(txtPair,'String',sprintf('Pair: %s <-> %s | Pearson r = %.4f', ...
            names{aSel},names{bSel},r));
    end

    function refreshGraphView()
        s = guidata(fig);
        res = s.roiResults{s.currentSubject,s.currentEpoch};

        cla(axAdj);
        cla(axDeg);

        if isempty(res)
            fc_nodata(axAdj,'Adjacency',C);
            fc_nodata(axDeg,'Degree',C);
            set(txtGraph,'String','No graph yet.');
            return;
        end

        [M,names] = fc_current_matrix(s,res);
        A = abs(M) >= s.roiAbsThr;
        A(1:size(A,1)+1:end) = false;

        imagesc(axAdj,double(A));
        axis(axAdj,'image');
        colormap(axAdj,gray(256));
        fc_ax(axAdj,C);
        title(axAdj,'Adjacency |r| >= threshold','Color',C.fg);
        xlabel(axAdj,'ROI','Color',C.dim);
        ylabel(axAdj,'ROI','Color',C.dim);

        if size(A,1) <= 35
            set(axAdj,'XTick',1:size(A,1),'YTick',1:size(A,1));
            set(axAdj,'XTickLabel',fc_short_list(names,18),'YTickLabel',fc_short_list(names,18));
            try, xtickangle(axAdj,90); catch, end
        else
            set(axAdj,'XTick',[],'YTick',[]);
        end

        deg = sum(A,2);

        histogram(axDeg,deg,'FaceColor',[0.30 0.70 1.00],'EdgeColor',[0.15 0.35 0.80]);
        fc_ax(axDeg,C);
        grid(axDeg,'on');
        xlabel(axDeg,'Degree','Color',C.dim);
        ylabel(axDeg,'Count','Color',C.dim);
        title(axDeg,'Degree histogram','Color',C.fg);

        density = nnz(triu(A,1)) / max(1,(size(A,1)*(size(A,1)-1)/2));
        [~,ord] = sort(deg,'descend');

        nHub = min(5,numel(ord));
        lines = cell(nHub,1);
        for k = 1:nHub
            lines{k} = sprintf('%s: degree %d',fc_short(names{ord(k)}),deg(ord(k)));
        end

        set(txtGraph,'String',sprintf('Density: %.4f\nMean degree: %.2f\n\nTop hubs:\n%s', ...
            density,mean(deg),fc_join(lines)));
    end

    function updateROIDropdowns(names)
        if isempty(names)
            names = {'n/a'};
        end

        oldC = get(ddCompareROI,'Value');
        oldA = get(ddPairA,'Value');
        oldB = get(ddPairB,'Value');

        set(ddCompareROI,'String',names,'Value',fc_clip(oldC,1,numel(names)));
        set(ddPairA,'String',names,'Value',fc_clip(oldA,1,numel(names)));
        set(ddPairB,'String',names,'Value',fc_clip(oldB,1,numel(names)));
    end

    function [mapS,ok] = fc_compare_slice(s)
        ok = false;
        mapS = [];

        res = s.roiResults{s.currentSubject,s.currentEpoch};
        subj = s.subjects(s.currentSubject);

        if isempty(res) || isempty(subj.roiAtlas)
            return;
        end

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

        if ~isempty(subj.mask)
            mapS(~subj.mask(:,:,s.slice)) = NaN;
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
    'Title',titleStr,'FontWeight','bold','FontSize',12);
end

function p = fc_view(parent,C,vis)
p = uipanel('Parent',parent,'Units','normalized','Position',[0.01 0.01 0.98 0.91], ...
    'BackgroundColor',C.bgPane,'BorderType','none','Visible',vis);
end

function h = fc_label(parent,pos,str,C)
h = uicontrol('Parent',parent,'Style','text','Units','normalized','Position',pos, ...
    'String',str,'BackgroundColor',C.bgPane,'ForegroundColor',C.fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',10);
end

function out = fc_if(cond,a,b)
if cond
    out = a;
else
    out = b;
end
end

function opts = fc_defaults(opts)
if ~isfield(opts,'statusFcn'), opts.statusFcn = []; end
if ~isfield(opts,'logFcn'), opts.logFcn = []; end
if ~isfield(opts,'functionalField'), opts.functionalField = ''; end
if ~isfield(opts,'roiNames'), opts.roiNames = {}; end
if ~isfield(opts,'roiNameTable'), opts.roiNameTable = struct('labels',[],'names',{{}}); end
if ~isfield(opts,'roiMinVox') || isempty(opts.roiMinVox), opts.roiMinVox = 9; end
if ~isfield(opts,'seedBoxSize') || isempty(opts.seedBoxSize), opts.seedBoxSize = 3; end
if ~isfield(opts,'chunkVox') || isempty(opts.chunkVox), opts.chunkVox = 6000; end
if ~isfield(opts,'askMaskAtStart') || isempty(opts.askMaskAtStart), opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart), opts.askAtlasAtStart = true; end
if ~isfield(opts,'debugRethrow') || isempty(opts.debugRethrow), opts.debugRethrow = false; end
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
    if ~ok
        error('Invalid subject at index %d.',i);
    end
    subjects(i) = s;
end
end

function s = fc_empty_subject()
s = struct();
s.I4 = [];
s.TR = 1;
s.mask = [];
s.anat = [];
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

if ~isstruct(in)
    return;
end

if isfield(in,'name') && ~isempty(in.name), s.name = char(in.name); end
if isfield(in,'group') && ~isempty(in.group), s.group = char(in.group); end
if isfield(in,'TR') && ~isempty(in.TR), s.TR = double(in.TR); end
if ~isscalar(s.TR) || ~isfinite(s.TR) || s.TR <= 0, s.TR = 1; end

[I,okI] = fc_get_functional(in,opts);
if ~okI
    return;
end

s.I4 = fc_force4d(I);
[Y,X,Z] = fc_size3(s.I4);

if isfield(in,'mask') && ~isempty(in.mask)
    s.mask = fc_fit_volume(in.mask,Y,X,Z,true);
elseif isfield(in,'brainMask') && ~isempty(in.brainMask)
    s.mask = fc_fit_volume(in.brainMask,Y,X,Z,true);
end

if isfield(in,'anat') && ~isempty(in.anat)
    s.anat = fc_fit_volume(in.anat,Y,X,Z,false);
elseif isfield(in,'bg') && ~isempty(in.bg)
    s.anat = fc_fit_volume(in.bg,Y,X,Z,false);
end

if isfield(in,'roiAtlas') && ~isempty(in.roiAtlas)
    s.roiAtlas = fc_fit_volume(in.roiAtlas,Y,X,Z,false);
elseif isfield(in,'atlas') && ~isempty(in.atlas)
    s.roiAtlas = fc_fit_volume(in.atlas,Y,X,Z,false);
elseif isfield(in,'regions') && ~isempty(in.regions)
    s.roiAtlas = fc_fit_volume(in.regions,Y,X,Z,false);
end

if ~isempty(s.roiAtlas)
    s.roiAtlas = round(double(s.roiAtlas));
end

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
ok = false;
I = [];

if ~isempty(opts.functionalField) && isfield(s,opts.functionalField)
    x = s.(opts.functionalField);
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        I = x;
        ok = true;
        return;
    end
end

cand = {'I','PSC','data','functional','func','movie','volume'};
for i = 1:numel(cand)
    if isfield(s,cand{i})
        x = s.(cand{i});
        if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
            I = x;
            ok = true;
            return;
        end
    end
end

fn = fieldnames(s);
for i = 1:numel(fn)
    x = s.(fn{i});
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        I = x;
        ok = true;
        return;
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
sz = size(I4);
Y = sz(1);
X = sz(2);
Z = sz(3);
end

function V = fc_fit_volume(V0,Y,X,Z,makeLogical)
V = [];
V0 = squeeze(V0);

if ndims(V0)==2 && Z==1 && size(V0,1)==Y && size(V0,2)==X
    V = reshape(V0,Y,X,1);
elseif ndims(V0)==3 && all(size(V0)==[Y X Z])
    V = V0;
end

if ~isempty(V) && makeLogical
    V = logical(V);
end
end

function [subjects,msg] = fc_startup_masks(subjects,opts)
if ~opts.askMaskAtStart
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask)
            subjects(i).mask = fc_auto_mask(subjects(i).I4);
        end
    end
    msg = 'Mask: auto for missing.';
    return;
end

hasMask = false;
for i = 1:numel(subjects)
    if ~isempty(subjects(i).mask)
        hasMask = true;
        break;
    end
end

if hasMask
    choice = questdlg('Mask startup:', ...
        'Mask startup','Use provided','Auto masks','Use provided');
else
    choice = questdlg('No mask provided. Use automatic masks?', ...
        'Mask startup','Auto masks','No mask','Auto masks');
end

if isempty(choice), choice = 'Auto masks'; end

if strcmpi(choice,'Use provided')
    for i = 1:numel(subjects)
        if isempty(subjects(i).mask)
            subjects(i).mask = fc_auto_mask(subjects(i).I4);
        end
    end
    msg = 'Mask: provided with auto fallback.';
elseif strcmpi(choice,'No mask')
    msg = 'Mask: none.';
else
    for i = 1:numel(subjects)
        subjects(i).mask = fc_auto_mask(subjects(i).I4);
    end
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
q = questdlg('No ROI atlas found. Load common ROI atlas MAT now?', ...
    'ROI atlas','Yes','No','No');

if ~strcmpi(q,'Yes')
    return;
end

[f,p] = uigetfile({'*.mat','MAT files (*.mat)'},'Load ROI atlas',fc_start_dir(subj,opts));
if isequal(f,0), return; end

S = load(fullfile(p,f));
atlas = fc_pick_volume(S,Y,X,Z);

if isempty(atlas)
    errordlg('No compatible ROI atlas found.');
else
    atlas = round(double(atlas));
end
end

function startDir = fc_start_dir(subj,opts)
if isfield(subj,'analysisDir') && ~isempty(subj.analysisDir) && exist(subj.analysisDir,'dir')
    startDir = subj.analysisDir;
elseif isfield(opts,'saveRoot') && exist(opts.saveRoot,'dir')
    startDir = opts.saveRoot;
else
    startDir = pwd;
end
end

function [I,varName] = fc_pick_data_from_mat(S)
I = [];
varName = '';

fn = fieldnames(S);
cand = {};

for i = 1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x) && (ndims(x)==3 || ndims(x)==4)
        cand{end+1} = fn{i}; %#ok<AGROW>
    elseif isstruct(x) && isfield(x,'Data') && isnumeric(x.Data) && ...
            (ndims(x.Data)==3 || ndims(x.Data)==4)
        cand{end+1} = [fn{i} '.Data']; %#ok<AGROW>
    end
end

if isempty(cand), return; end

if numel(cand)==1
    varName = cand{1};
else
    [sel,ok] = listdlg('PromptString','Select data variable:', ...
        'SelectionMode','single','ListString',cand);
    if ok && ~isempty(sel)
        varName = cand{sel};
    else
        varName = cand{1};
    end
end

if ~isempty(strfind(varName,'.Data'))
    base = strrep(varName,'.Data','');
    I = S.(base).Data;
else
    I = S.(varName);
end
end

function V = fc_pick_volume(S,Y,X,Z)
V = [];
fn = fieldnames(S);

preferred = {'roiAtlas','atlas','regions','annotation','labels','mask','brainMask','loadedMask','Data'};
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

if isstruct(x) && isfield(x,'Data')
    x = x.Data;
end

if ~(isnumeric(x) || islogical(x))
    return;
end

x = squeeze(x);

if ndims(x)==2 && Z==1 && size(x,1)==Y && size(x,2)==X
    V = reshape(x,Y,X,1);
elseif ndims(x)==3 && all(size(x)==[Y X Z])
    V = x;
end
end

function [U,isRGB] = fc_read_underlay(fullf,Y,X,Z)
U = [];
isRGB = false;
[~,~,ext] = fileparts(fullf);
ext = lower(ext);

if strcmp(ext,'.mat')
    S = load(fullf);
    U = fc_pick_volume(S,Y,X,Z);
    if isempty(U)
        [U,~] = fc_pick_data_from_mat(S);
    end
else
    U = double(imread(fullf));
end

if isempty(U)
    error('No compatible underlay found.');
end

U = squeeze(U);

if ndims(U)==3 && size(U,3)==3
    isRGB = true;
    if max(U(:)) > 1, U = U/255; end
    if size(U,1)~=Y || size(U,2)~=X
        U = fc_resize_rgb(U,Y,X);
    end
    return;
end

if ndims(U)==2
    if size(U,1)~=Y || size(U,2)~=X
        U = fc_resize2(U,Y,X);
    end
elseif ndims(U)==3
    if size(U,1)~=Y || size(U,2)~=X
        tmp = zeros(Y,X,size(U,3));
        for z = 1:size(U,3)
            tmp(:,:,z) = fc_resize2(U(:,:,z),Y,X);
        end
        U = tmp;
    end
    if size(U,3)~=Z
        zi = round(linspace(1,size(U,3),Z));
        U = U(:,:,zi);
    end
else
    error('Unsupported underlay dimensions.');
end
end

function B = fc_resize2(A,Y,X)
if exist('imresize','file') == 2
    B = imresize(A,[Y X],'nearest');
else
    yy = round(linspace(1,size(A,1),Y));
    xx = round(linspace(1,size(A,2),X));
    B = A(yy,xx);
end
end

function R = fc_resize_rgb(R,Y,X)
tmp = zeros(Y,X,3);
for k = 1:3
    tmp(:,:,k) = fc_resize2(R(:,:,k),Y,X);
end
R = tmp;
end

function T = fc_read_region_names(fullf)
T = struct('labels',[],'names',{{}});
[~,~,ext] = fileparts(fullf);
ext = lower(ext);

if strcmp(ext,'.mat')
    S = load(fullf);
    T = fc_region_names_from_mat(S);
    return;
end

fid = fopen(fullf,'r');
if fid < 0
    error('Could not open region-name file.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

labels = [];
names = {};

while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line), continue; end
    line = strtrim(line);
    if isempty(line), continue; end
    if line(1)=='#' || line(1)=='%', continue; end

    line = strrep(line,char(9),',');
    line = strrep(line,';',',');

    parts = regexp(line,',','split');
    if numel(parts) < 2
        parts = regexp(line,'\s+','split');
    end
    if numel(parts) < 2, continue; end

    lab = str2double(strtrim(parts{1}));
    if ~isfinite(lab), continue; end

    nm = strtrim(parts{2});
    if numel(parts) > 2
        for k = 3:numel(parts)
            pk = strtrim(parts{k});
            if ~isempty(pk)
                nm = [nm ' ' pk]; %#ok<AGROW>
            end
        end
    end

    labels(end+1,1) = lab; %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
end

T.labels = labels;
T.names = names;
end

function T = fc_region_names_from_mat(S)
T = struct('labels',[],'names',{{}});

if isfield(S,'roiNameTable')
    x = S.roiNameTable;
    if isstruct(x) && isfield(x,'labels') && isfield(x,'names')
        T.labels = x.labels(:);
        T.names = x.names(:);
        return;
    end
end

if isfield(S,'labels') && isfield(S,'names')
    T.labels = S.labels(:);
    T.names = cellstr(S.names);
    return;
end

fn = fieldnames(S);
for i = 1:numel(fn)
    x = S.(fn{i});

    if isstruct(x) && numel(x) > 1
        f = fieldnames(x);
        idField = '';
        nameField = '';

        if any(strcmp(f,'id')), idField = 'id'; end
        if any(strcmp(f,'label')), idField = 'label'; end

        if any(strcmp(f,'acronym')), nameField = 'acronym'; end
        if any(strcmp(f,'name')), nameField = 'name'; end

        if ~isempty(idField) && ~isempty(nameField)
            labs = zeros(numel(x),1);
            nms = cell(numel(x),1);
            for k = 1:numel(x)
                labs(k) = double(x(k).(idField));
                nms{k} = char(x(k).(nameField));
            end
            T.labels = labs;
            T.names = nms;
            return;
        end
    end
end
end

function info = fc_read_scm_roi(txtFile)
fid = fopen(txtFile,'r');
if fid < 0
    error('Could not open ROI TXT.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

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
            info.x1 = v(1);
            info.x2 = v(2);
            info.y1 = v(3);
            info.y2 = v(4);
        end
    end
end

if ~all(isfinite([info.x1 info.x2 info.y1 info.y2]))
    error('Could not parse x1 x2 y1 y2.');
end
end

function res = fc_seed_fc(I4,TR,mask,seedX,seedY,seedZ,boxSize,useSliceOnly,chunkVox)
[Y,X,Z,T] = size(I4);

if isempty(mask)
    mask = fc_auto_mask(I4);
end

seedX = fc_clip(seedX,1,X);
seedY = fc_clip(seedY,1,Y);
seedZ = fc_clip(seedZ,1,Z);

seedMask2D = false(Y,X);
h = floor(boxSize/2);
x1 = max(1,seedX-h);
x2 = min(X,seedX+h);
y1 = max(1,seedY-h);
y2 = min(Y,seedY+h);
seedMask2D(y1:y2,x1:x2) = true;

seedMask = false(Y,X,Z);
seedMask(:,:,seedZ) = seedMask2D;
seedMask = seedMask & mask;

seedIdx = find(seedMask(:));
if isempty(seedIdx)
    seedMask(seedY,seedX,seedZ) = true;
    seedIdx = find(seedMask(:));
end

V = Y*X*Z;
D = reshape(I4,[V T]);

seedTS = mean(double(D(seedIdx,:)),1)';
s = seedTS - mean(seedTS);
sNorm = sqrt(sum(s.^2));

if sNorm <= 0 || ~isfinite(sNorm)
    error('Seed timecourse has zero variance.');
end

if useSliceOnly
    voxMask = false(Y,X,Z);
    voxMask(:,:,seedZ) = mask(:,:,seedZ);
else
    voxMask = mask;
end

voxIdx = find(voxMask(:));
r = nan(V,1,'single');

chunk = max(1000,round(chunkVox));
s = single(s);

for i0 = 1:chunk:numel(voxIdx)
    i1 = min(numel(voxIdx),i0+chunk-1);
    id = voxIdx(i0:i1);

    Xc = D(id,:);
    Xc = bsxfun(@minus,Xc,mean(Xc,2));

    num = Xc * s;
    den = sqrt(sum(Xc.^2,2)) * single(sNorm);

    rr = num ./ max(den,single(eps));
    rr(~isfinite(rr)) = 0;
    rr = max(-1,min(1,rr));

    r(id) = rr;
end

rMap = reshape(r,[Y X Z]);
zMap = single(atanh(max(-0.999999,min(0.999999,double(rMap)))));

res = struct();
res.rMap = rMap;
res.zMap = zMap;
res.seedTS = seedTS;
res.seedMask = seedMask;
res.TR = TR;
res.seedInfo = struct('x',seedX,'y',seedY,'z',seedZ,'boxSize',boxSize,'useSliceOnly',useSliceOnly);
end

function res = fc_roi_fc(I4,TR,mask,atlas,opts)
[Y,X,Z,T] = size(I4); %#ok<ASGLU>

if isempty(mask)
    mask = fc_auto_mask(I4);
end

V = Y*X*Z;
D = reshape(I4,[V size(I4,4)]);

atlasV = atlas(:);
maskV = mask(:);

labels = unique(atlasV(maskV & atlasV > 0));
labels = labels(:);

if isempty(labels)
    error('No atlas labels inside mask.');
end

keepLabels = [];
names = {};
counts = [];
meanTS = [];

for k = 1:numel(labels)
    lab = labels(k);
    idx = find(maskV & atlasV == lab);

    if numel(idx) < opts.roiMinVox
        continue;
    end

    ts = mean(double(D(idx,:)),1)';

    keepLabels(end+1,1) = lab; %#ok<AGROW>
    counts(end+1,1) = numel(idx); %#ok<AGROW>
    names{end+1,1} = fc_roi_name(lab,opts); %#ok<AGROW>
    meanTS(:,end+1) = ts; %#ok<AGROW>
end

if isempty(keepLabels)
    error('No ROI survived roiMinVox.');
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

function [M,names,order] = fc_current_matrix(s,res)
M0 = res.M;
names0 = res.names;
labels = res.labels;

switch lower(s.roiOrder)
    case 'name'
        [~,order] = sort(lower(names0));
    otherwise
        [~,order] = sort(labels);
end

M = M0(order,order);
names = names0(order);
end

function name = fc_roi_name(label,opts)
name = sprintf('ROI_%03d',label);

try
    T = opts.roiNameTable;

    if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
        idx = find(double(T.labels(:)) == double(label),1,'first');
        if ~isempty(idx) && idx <= numel(T.names)
            nm = char(T.names{idx});
            if ~isempty(strtrim(nm))
                name = sprintf('%s [%g]',nm,label);
                return;
            end
        end
    end

    if iscell(opts.roiNames) && label >= 1 && label <= numel(opts.roiNames)
        if ~isempty(opts.roiNames{label})
            name = sprintf('%s [%g]',char(opts.roiNames{label}),label);
        end
    end
catch
end
end

function idxT = fc_time_idx(TR,T,t0,t1)
if ~isfinite(TR) || TR <= 0
    TR = 1;
end

sec = (0:T-1) * TR;
idxT = find(sec >= t0 & sec <= t1);

if isempty(idxT)
    idxT = 1:T;
end
end

function rgb = fc_get_underlay(s)
subj = s.subjects(s.currentSubject);
I4 = subj.I4;

meanImg = squeeze(mean(I4,4));
medImg = squeeze(median(I4,4));

switch lower(s.underlayMode)
    case 'median'
        rgb = fc_gray_rgb(medImg(:,:,s.slice));

    case 'anat'
        if ~isempty(subj.anat)
            rgb = fc_gray_rgb(subj.anat(:,:,s.slice));
        else
            rgb = fc_gray_rgb(meanImg(:,:,s.slice));
        end

    case 'atlas'
        if ~isempty(subj.roiAtlas)
            a = double(subj.roiAtlas(:,:,s.slice));
            rgb = fc_map_rgb(a,jet(256),[0 max(1,max(a(:)))]);
        else
            rgb = fc_gray_rgb(meanImg(:,:,s.slice));
        end

    case 'loaded'
        U = s.loadedUnderlay;
        if isempty(U)
            rgb = fc_gray_rgb(meanImg(:,:,s.slice));
        elseif s.loadedUnderlayIsRGB
            rgb = single(U);
            if max(rgb(:)) > 1
                rgb = rgb/255;
            end
        elseif ndims(U)==2
            rgb = fc_gray_rgb(U);
        else
            rgb = fc_gray_rgb(U(:,:,s.slice));
        end

    otherwise
        rgb = fc_gray_rgb(meanImg(:,:,s.slice));
end
end

function rgb = fc_gray_rgb(A)
A = single(A);
lo = fc_prctile(A(:),1);
hi = fc_prctile(A(:),99);

if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(A(:));
    hi = max(A(:));
    if hi <= lo
        hi = lo + 1;
    end
end

A = (A - lo) / (hi - lo);
A = max(0,min(1,A));
rgb = repmat(A,[1 1 3]);
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
    tmp = zeros(size(mask),'single');
    tmp(edge) = col(k);
    rgb(:,:,k) = tmp;
end

A = 0.90 * double(edge);
end

function rgb = fc_map_rgb(M,cmap,clim)
M = double(M);
cmin = clim(1);
cmax = clim(2);

if ~isfinite(cmin) || ~isfinite(cmax) || cmax <= cmin
    cmin = min(M(:));
    cmax = max(M(:));
    if cmax <= cmin
        cmax = cmin + 1;
    end
end

u = (M - cmin) / (cmax - cmin);
u = max(0,min(1,u));

idx = 1 + floor(u * (size(cmap,1)-1));
idx(~isfinite(idx)) = 1;
idx = max(1,min(size(cmap,1),idx));

rgb = zeros(size(M,1),size(M,2),3,'single');

for k = 1:3
    tmp = cmap(idx,k);
    rgb(:,:,k) = reshape(single(tmp),size(M,1),size(M,2));
end
end

function cmap = fc_bwr(n)
if nargin < 1, n = 256; end

n1 = floor(n/2);
n2 = n - n1;

b = [0.00 0.25 0.95];
w = [1.00 1.00 1.00];
r = [0.95 0.20 0.20];

c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];

cmap = [c1; c2];
end

function [idx,vals] = fc_rank_vector(r,topN,mode)
r = double(r(:)');
valid = find(isfinite(r));

if isempty(valid)
    idx = [];
    vals = [];
    return;
end

switch lower(mode)
    case 'positive'
        [~,ord] = sort(r(valid),'descend');
    case 'negative'
        [~,ord] = sort(r(valid),'ascend');
    case 'label'
        ord = 1:numel(valid);
    otherwise
        [~,ord] = sort(abs(r(valid)),'descend');
end

idx = valid(ord);
idx = idx(1:min(numel(idx),topN));
vals = r(idx);
end

function T = fc_compare_export_table(s,res)
T = [];

[M,names,order] = fc_current_matrix(s,res);

sel = fc_clip(s.compareROI,1,numel(names));
vals = M(sel,:)';
labels = res.labels(order);

T.selectedName = names{sel};
T.labels = labels(:);
T.names = names(:);
T.values = vals(:);
end

function fc_write_matrix_csv(fileName,M,names)
fid = fopen(fileName,'w');
if fid < 0
    error('Could not open CSV file.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'ROI');
for j = 1:numel(names)
    fprintf(fid,',%s',fc_csv(names{j}));
end
fprintf(fid,'\n');

for i = 1:size(M,1)
    fprintf(fid,'%s',fc_csv(names{i}));
    for j = 1:size(M,2)
        fprintf(fid,',%.10g',M(i,j));
    end
    fprintf(fid,'\n');
end
end

function fc_write_compare_csv(fileName,T)
fid = fopen(fileName,'w');
if fid < 0
    error('Could not open compare CSV.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'Selected,%s\n',fc_csv(T.selectedName));
fprintf(fid,'Label,Region,Value\n');

for i = 1:numel(T.values)
    fprintf(fid,'%.10g,%s,%.10g\n',T.labels(i),fc_csv(T.names{i}),T.values(i));
end
end

function s = fc_csv(s0)
s = char(s0);
s = strrep(s,'"','""');
s = ['"' s '"'];
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
if Z <= 1
    stp = [1 1];
else
    stp = [1/(Z-1) min(10/(Z-1),1)];
end
end

function v = fc_clip(v,lo,hi)
v = max(lo,min(hi,v));
end

function z = fc_z(x)
x = double(x(:));
sd = std(x);
if ~isfinite(sd) || sd <= 0
    z = zeros(size(x));
else
    z = (x - mean(x)) / sd;
end
end

function r = fc_corr_scalar(x,y)
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

function Z = fc_atanh_safe(M)
Z = double(M);
Z = max(-0.999999,min(0.999999,Z));
Z = atanh(Z);
end

function clim = fc_auto_clim(vals,fallback)
vals = double(vals(:));
vals = vals(isfinite(vals));

if isempty(vals)
    clim = [-fallback fallback];
    return;
end

p = fc_prctile(abs(vals),99);
if ~isfinite(p) || p <= 0
    p = fallback;
end

clim = [-p p];
end

function x = fc_prctile(a,p)
a = double(a(:));
a = a(isfinite(a));

if isempty(a)
    x = NaN;
    return;
end

a = sort(a);

if numel(a)==1
    x = a;
    return;
end

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

function fc_ax(ax,C)
set(ax,'Color',C.bgAx,'XColor',C.dim,'YColor',C.dim);
end

function fc_nodata(ax,titleStr,C)
cla(ax);
text(ax,0.5,0.5,'No data','HorizontalAlignment','center','Color',C.fg);
fc_ax(ax,C);
title(ax,titleStr,'Color',C.fg);
end

function s = fc_summary(st)
subj = st.subjects(st.currentSubject);

if isempty(subj.mask), maskTxt = 'no'; else, maskTxt = 'yes'; end
if isempty(subj.roiAtlas), atlasTxt = 'no'; else, atlasTxt = 'yes'; end
if isempty(subj.anat), anatTxt = 'no'; else, anatTxt = 'yes'; end

nNames = 0;
if isfield(st.opts,'roiNameTable') && isstruct(st.opts.roiNameTable) && isfield(st.opts.roiNameTable,'labels')
    nNames = numel(st.opts.roiNameTable.labels);
end

s = sprintf(['Subject: %s | TR %.4g s | Size [%d x %d x %d x %d]\n' ...
    'Mask: %s | Atlas: %s | Region names: %d | Anat: %s\n' ...
    'Underlay: %s | Overlay: %s | Slice: %d'], ...
    subj.name,subj.TR,size(subj.I4,1),size(subj.I4,2),size(subj.I4,3),size(subj.I4,4), ...
    maskTxt,atlasTxt,nNames,anatTxt,st.underlayMode,st.overlayMode,st.slice);
end

function lst = fc_underlay_list(st)
subj = st.subjects(st.currentSubject);

lst = {'Mean data','Median data'};

if ~isempty(st.loadedUnderlay)
    lst{end+1} = 'Loaded underlay';
end

if ~isempty(subj.anat)
    lst{end+1} = 'Anat';
end

if ~isempty(subj.roiAtlas)
    lst{end+1} = 'Atlas labels';
end
end

function out = fc_short_list(c,n)
out = c;
for i = 1:numel(out)
    s = char(out{i});
    if numel(s) > n
        s = [s(1:max(1,n-3)) '...'];
    end
    out{i} = s;
end
end

function s = fc_short(s)
s = char(s);
if numel(s) > 32
    s = [s(1:29) '...'];
end
end

function out = fc_join(c)
if isempty(c)
    out = 'none';
    return;
end

out = c{1};
for i = 2:numel(c)
    out = sprintf('%s\n%s',out,c{i});
end
end

function fc_log(opts,msg)
try
    if isfield(opts,'logFcn') && isa(opts.logFcn,'function_handle')
        opts.logFcn(msg);
    end
catch
end
end
