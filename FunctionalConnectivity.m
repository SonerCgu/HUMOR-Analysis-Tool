function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity.m
%
% fUSI Studio functional connectivity GUI
% MATLAB 2017b compatible
% ASCII safe / dark theme
%
% Features
%   1) Startup mask selection:
%        - use provided subject masks
%        - build auto masks
%        - load one common mask from MAT file
%   2) Automatic functional-data extraction from struct inputs
%   3) Multi-animal input support
%   4) Seed-based voxelwise FC:
%        - Pearson r
%        - Fisher z
%   5) ROI-to-ROI FC:
%        - mean Pearson
%        - mean partial
%        - PC1 Pearson
%        - PC1 partial
%        - RV coefficient
%   6) Group statistics:
%        - one-sample t-test
%        - one-sample Wilcoxon signed-rank
%        - paired t-test
%        - paired Wilcoxon signed-rank
%        - two-sample t-test
%        - two-sample Wilcoxon rank-sum
%   7) BH-FDR correction
%   8) Voxelwise seed-map group stats
%   9) ROI edgewise group stats
%  10) Network/module reordering
%  11) PCA + optional ICA (fastica if available)
%  12) Save outputs (MAT + PNG)
%
% Input forms
%   dataIn can be:
%     - numeric [Y X T] or [Y X Z T]
%     - single struct with fields like:
%         .I or .PSC or .data or .functional or .func
%         .TR, .mask, .anat, .roiAtlas, .name, .group, .pairID
%     - struct array
%     - cell array of structs / numeric arrays
%
% roiAtlas options
%   See bottom of final chat message for explanation.
%
% ASCII only

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4, opts = struct(); end

opts = normalizeOpts(opts);

% -------------------------------------------------------------------------
% Normalize subjects
% -------------------------------------------------------------------------
subjects = normalizeSubjects(dataIn, opts);
nSub = numel(subjects);
if nSub < 1
    error('No valid subjects found.');
end

% -------------------------------------------------------------------------
% Geometry checks
% -------------------------------------------------------------------------
[Y, X, Z] = getSpatialSize(subjects(1).I4);
for i = 2:nSub
    [Yi, Xi, Zi] = getSpatialSize(subjects(i).I4);
    if Yi ~= Y || Xi ~= X || Zi ~= Z
        error('All subjects must have identical spatial dimensions for this GUI.');
    end
end

% -------------------------------------------------------------------------
% Startup mask selection
% -------------------------------------------------------------------------
[subjects, startupMaskInfo] = applyStartupMaskStrategy(subjects, opts);

% -------------------------------------------------------------------------
% Startup atlas fallback
% -------------------------------------------------------------------------
if isempty(subjects(1).roiAtlas) && opts.askAtlasAtStart
    [atlasLoaded, okAtlas] = maybeLoadCommonAtlas(Y, X, Z);
    if okAtlas
        for i = 1:nSub
            subjects(i).roiAtlas = atlasLoaded;
        end
    end
end

% -------------------------------------------------------------------------
% State
% -------------------------------------------------------------------------
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
st.seedAbsThr = 0.20;
st.seedAlpha = 0.70;

st.roiMethod = 'mean_pearson';
st.roiAbsThr = opts.roiAbsThr;
st.reorderMode = 'none';

st.seedResults = cell(nSub,1);      % each: rMap zMap seedTS seedInfo
st.roiResults = cell(nSub,1);       % each: ROI matrices etc
st.compResults = cell(nSub,1);      % each: PCA / ICA
st.groupSeedStats = [];
st.groupRoiStats = [];

st.groupTarget = 'seed';
st.groupTest = 'one_sample_t';
st.groupA = 1;
st.groupB = 1;
st.groupAlpha = 0.05;

st.datasetName = opts.datasetName;
st.tag = tag;
st.opts = opts;
st.startupMaskInfo = startupMaskInfo;

qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(qcDir,'dir'), mkdir(qcDir); end
st.qcDir = qcDir;
st.fcCmap = blueWhiteRed(256);

st.subjectNames = {subjects.name}';
st.groupNames = uniqueCellstr({subjects.group});
if isempty(st.groupNames)
    st.groupNames = {'All'};
end

% -------------------------------------------------------------------------
% Theme
% -------------------------------------------------------------------------
bgFig  = [0.05 0.05 0.06];
bgPane = [0.08 0.08 0.09];
bgAx   = [0.10 0.10 0.11];
fg     = [0.92 0.92 0.94];
fgDim  = [0.74 0.74 0.78];
accent = [0.20 0.65 1.00];
goodC  = [0.25 0.78 0.35];
warnC  = [1.00 0.35 0.35];

% -------------------------------------------------------------------------
% Figure
% -------------------------------------------------------------------------
fig = figure( ...
    'Name','fUSI Studio - Functional Connectivity', ...
    'Color',bgFig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[50 40 1700 960]);

try, set(fig,'Renderer','opengl'); catch, end

panelCtrl = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.015 0.03 0.290 0.94], ...
    'BackgroundColor',bgPane, ...
    'ForegroundColor',fg, ...
    'Title','Controls', ...
    'FontWeight','bold','FontSize',12);

panelViewWrap = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.315 0.03 0.67 0.94], ...
    'BackgroundColor',bgPane, ...
    'ForegroundColor',fg, ...
    'Title','Views', ...
    'FontWeight','bold','FontSize',12);

% -------------------------------------------------------------------------
% Button style tab switching
% -------------------------------------------------------------------------
tabBtnY = 0.945;
tabBtnH = 0.040;
tabBtnW = 0.13;
tabNames = {'Seed','ROI','Pair','Group','Graph','Components'};

btnSeedTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.015 tabBtnY tabBtnW tabBtnH], ...
    'String','Seed', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('Seed'));

btnROITab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.150 tabBtnY tabBtnW tabBtnH], ...
    'String','ROI', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('ROI'));

btnPairTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.285 tabBtnY tabBtnW tabBtnH], ...
    'String','Pair', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('Pair'));

btnGroupTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.420 tabBtnY tabBtnW tabBtnH], ...
    'String','Group', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('Group'));

btnGraphTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.555 tabBtnY tabBtnW tabBtnH], ...
    'String','Graph', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('Graph'));

btnCompTab = uicontrol('Parent',panelViewWrap,'Style','togglebutton','Units','normalized', ...
    'Position',[0.690 tabBtnY tabBtnW tabBtnH], ...
    'String','Components', 'FontWeight','bold', ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@(src,evt)switchPanel('Components'));

panelSeed = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none');

panelROI = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none', 'Visible','off');

panelPair = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none', 'Visible','off');

panelGroup = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none', 'Visible','off');

panelGraph = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none', 'Visible','off');

panelComp = uipanel('Parent',panelViewWrap,'Units','normalized', ...
    'Position',[0.01 0.01 0.98 0.92], 'BackgroundColor',bgPane, 'BorderType','none', 'Visible','off');

% -------------------------------------------------------------------------
% Controls
% -------------------------------------------------------------------------
y = 0.955;
dy = 0.040;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.028], ...
    'String','Current subject', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
y = y - dy;

ddSubject = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.90 0.035], ...
    'String',st.subjectNames, ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@onSubjectChanged);
y = y - dy;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.028], ...
    'String','Underlay', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
y = y - dy;

ddUnder = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.90 0.035], ...
    'String',underlayList(st.subjects(st.currentSubject).anat), ...
    'BackgroundColor',[0.16 0.16 0.18], 'ForegroundColor',fg, ...
    'Callback',@onUnderlayChanged);
y = y - dy;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.028], ...
    'String','Slice (Z)', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
y = y - dy;

slZ = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.05 y 0.90 0.025], ...
    'Min',1,'Max',max(1,Z),'Value',st.slice, ...
    'SliderStep',sliderStep(Z), ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onSliceChanged);
y = y - dy;

edZ = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.05 y 0.25 0.033], ...
    'String',sprintf('%d',st.slice), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onSliceEdit);

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.34 y 0.38 0.030], ...
    'String','Seed radius', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);

edR = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.77 y 0.18 0.033], ...
    'String',sprintf('%d',st.seedR), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onRadiusEdit);
y = y - dy;

cbSliceOnly = uicontrol('Parent',panelCtrl,'Style','checkbox','Units','normalized', ...
    'Position',[0.05 y 0.90 0.030], ...
    'String','Compute seed FC only on current slice', ...
    'Value',st.useSliceOnly, ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'Callback',@onComputeModeChanged);
y = y - dy;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.028], ...
    'String','Seed map type', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);
y = y - dy;

bgMap = uibuttongroup('Parent',panelCtrl,'Units','normalized', ...
    'Position',[0.05 y 0.90 0.050], ...
    'BackgroundColor',bgPane, ...
    'SelectionChangedFcn',@onMapModeChanged);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.02 0.12 0.46 0.76], ...
    'String','Fisher z', 'Value',1, ...
    'BackgroundColor',bgPane,'ForegroundColor',fg);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.52 0.12 0.46 0.76], ...
    'String','Pearson r', 'Value',0, ...
    'BackgroundColor',bgPane,'ForegroundColor',fg);
y = y - dy - 0.01;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.024], ...
    'String','Seed overlay threshold |r|', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');
y = y - dy + 0.01;

slThr = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.05 y 0.90 0.022], ...
    'Min',0,'Max',0.99,'Value',st.seedAbsThr, ...
    'SliderStep',[0.01 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onThrChanged);
y = y - 0.03;

txtThr = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.022], ...
    'String',sprintf('|r| >= %.2f',st.seedAbsThr), ...
    'BackgroundColor',bgPane,'ForegroundColor',accent, ...
    'HorizontalAlignment','left','FontWeight','bold');
y = y - 0.03;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.022], ...
    'String','Seed overlay alpha', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
y = y - 0.028;

slAlpha = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.05 y 0.90 0.022], ...
    'Min',0,'Max',1,'Value',st.seedAlpha, ...
    'SliderStep',[0.02 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], ...
    'Callback',@onAlphaChanged);
y = y - 0.038;

txtSeed = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.032], ...
    'String',seedString(st), ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');
y = y - 0.040;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.024], ...
    'String','ROI method', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');
y = y - 0.032;

ddRoiMethod = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.90 0.035], ...
    'String',roiMethodList(), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onRoiMethodChanged);
y = y - 0.042;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.48 0.024], ...
    'String','ROI threshold', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
edRoiThr = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.56 y 0.18 0.030], ...
    'String',sprintf('%.2f',st.roiAbsThr), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onRoiThrEdit);

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.76 y 0.18 0.024], ...
    'String','Reorder', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
y = y - 0.032;

ddReorder = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.76 y 0.19 0.035], ...
    'String',{'None','Label','Ontology'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onReorderChanged);
y = y - 0.045;

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y 0.90 0.024], ...
    'String','Group statistics', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');
y = y - 0.032;

ddGroupTarget = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.40 0.035], ...
    'String',{'Seed maps','ROI edges'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onGroupTargetChanged);

edAlpha = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.76 y 0.19 0.035], ...
    'String',sprintf('%.3f',st.groupAlpha), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onAlphaEdit);

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.48 y 0.24 0.024], ...
    'String','alpha / q', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
y = y - 0.042;

ddGroupTest = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.90 0.035], ...
    'String',groupTestList(), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onGroupTestChanged);
y = y - 0.042;

ddGroupA = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.05 y 0.42 0.035], ...
    'String',st.groupNames, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onGroupAChanged);

ddGroupB = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.53 y 0.42 0.035], ...
    'String',st.groupNames, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onGroupBChanged);

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 y+0.030 0.20 0.020], ...
    'String','Group A', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.53 y+0.030 0.20 0.020], ...
    'String','Group B', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left');
y = y - 0.055;

btnComputeSeed = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Compute seed FC', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.12 0.45 0.85],'ForegroundColor','w', ...
    'Callback',@onComputeSeed);
y = y - 0.055;

btnComputeROI = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Compute ROI FC', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.16 0.55 0.78],'ForegroundColor','w', ...
    'Callback',@onComputeROI);
y = y - 0.055;

btnComputeGroup = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Compute group statistics', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.33 0.45 0.74],'ForegroundColor','w', ...
    'Callback',@onComputeGroup);
y = y - 0.055;

btnComp = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Compute PCA / ICA', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.40 0.38 0.70],'ForegroundColor','w', ...
    'Callback',@onComputeComp);
y = y - 0.055;

btnSave = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Save outputs (MAT + PNG)', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.20 0.45 0.25],'ForegroundColor','w', ...
    'Callback',@onSave);
y = y - 0.055;

btnHelp = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Help / Tutorial', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.25 0.25 0.28],'ForegroundColor','w', ...
    'Callback',@onHelp);
y = y - 0.055;

btnClose = uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.05 y 0.90 0.046], ...
    'String','Close', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.65 0.20 0.20],'ForegroundColor','w', ...
    'Callback',@(~,~)delete(fig));
y = y - 0.060;

txtStatus = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.05 0.010 0.90 0.100], ...
    'String','Ready. Click in the Seed panel to place a seed and start.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------------------------------------------------------------
% Seed panel
% -------------------------------------------------------------------------
axSeedMap = axes('Parent',panelSeed,'Units','normalized', ...
    'Position',[0.03 0.12 0.60 0.80], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
axis(axSeedMap,'image'); axis(axSeedMap,'off');

axSeedTS = axes('Parent',panelSeed,'Units','normalized', ...
    'Position',[0.68 0.56 0.28 0.26], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axSeedTS,'on');

axSeedHist = axes('Parent',panelSeed,'Units','normalized', ...
    'Position',[0.68 0.18 0.28 0.26], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axSeedHist,'on');

hUnder = imagesc(axSeedMap, getUnderlaySlice(st));
colormap(axSeedMap, gray(256));
hold(axSeedMap,'on');
hOver = imagesc(axSeedMap, nan(st.Y,st.X,3));
set(hOver,'AlphaData',0);
hCross1 = line(axSeedMap,[1 st.X],[st.seedY st.seedY],'Color',warnC,'LineWidth',1.0);
hCross2 = line(axSeedMap,[st.seedX st.seedX],[1 st.Y],'Color',warnC,'LineWidth',1.0);
hold(axSeedMap,'off');
set(hUnder,'ButtonDownFcn',@onMapClick);
set(hOver,'ButtonDownFcn',@onMapClick);
set(axSeedMap,'ButtonDownFcn',@onMapClick);

% -------------------------------------------------------------------------
% ROI panel
% -------------------------------------------------------------------------
axRoiMat = axes('Parent',panelROI,'Units','normalized', ...
    'Position',[0.05 0.14 0.56 0.76], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);

axRoiTS = axes('Parent',panelROI,'Units','normalized', ...
    'Position',[0.67 0.55 0.28 0.27], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axRoiTS,'on');

txtRoiInfo = uicontrol('Parent',panelROI,'Style','text','Units','normalized', ...
    'Position',[0.66 0.14 0.30 0.28], ...
    'String','ROI FC not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------------------------------------------------------------
% Pair panel
% -------------------------------------------------------------------------
uicontrol('Parent',panelPair,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.10 0.03], ...
    'String','ROI A', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');

ddPairA = uicontrol('Parent',panelPair,'Style','popupmenu','Units','normalized', ...
    'Position',[0.14 0.93 0.32 0.035], ...
    'String',{'n/a'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onPairPopup);

uicontrol('Parent',panelPair,'Style','text','Units','normalized', ...
    'Position',[0.52 0.93 0.10 0.03], ...
    'String','ROI B', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');

ddPairB = uicontrol('Parent',panelPair,'Style','popupmenu','Units','normalized', ...
    'Position',[0.61 0.93 0.32 0.035], ...
    'String',{'n/a'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onPairPopup);

txtPairInfo = uicontrol('Parent',panelPair,'Style','text','Units','normalized', ...
    'Position',[0.05 0.82 0.90 0.08], ...
    'String','ROI pair view not ready yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

axPairTS = axes('Parent',panelPair,'Units','normalized', ...
    'Position',[0.08 0.50 0.84 0.24], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axPairTS,'on');

axPairScatter = axes('Parent',panelPair,'Units','normalized', ...
    'Position',[0.08 0.15 0.36 0.24], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axPairScatter,'on');

axPairLag = axes('Parent',panelPair,'Units','normalized', ...
    'Position',[0.55 0.15 0.36 0.24], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axPairLag,'on');

% -------------------------------------------------------------------------
% Group panel
% -------------------------------------------------------------------------
axGroupMain = axes('Parent',panelGroup,'Units','normalized', ...
    'Position',[0.05 0.14 0.56 0.76], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);

axGroupAux = axes('Parent',panelGroup,'Units','normalized', ...
    'Position',[0.68 0.55 0.26 0.26], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axGroupAux,'on');

txtGroupInfo = uicontrol('Parent',panelGroup,'Style','text','Units','normalized', ...
    'Position',[0.66 0.14 0.30 0.30], ...
    'String','Group statistics not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------------------------------------------------------------
% Graph panel
% -------------------------------------------------------------------------
axAdj = axes('Parent',panelGraph,'Units','normalized', ...
    'Position',[0.05 0.15 0.42 0.74], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);

axDeg = axes('Parent',panelGraph,'Units','normalized', ...
    'Position',[0.57 0.58 0.33 0.24], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axDeg,'on');

txtGraphInfo = uicontrol('Parent',panelGraph,'Style','text','Units','normalized', ...
    'Position',[0.55 0.16 0.38 0.30], ...
    'String','Graph view not ready yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------------------------------------------------------------
% Components panel
% -------------------------------------------------------------------------
uicontrol('Parent',panelComp,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.08 0.03], ...
    'String','Type', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');

ddCompType = uicontrol('Parent',panelComp,'Style','popupmenu','Units','normalized', ...
    'Position',[0.12 0.93 0.18 0.035], ...
    'String',{'PCA','ICA'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onCompSelector);

uicontrol('Parent',panelComp,'Style','text','Units','normalized', ...
    'Position',[0.34 0.93 0.12 0.03], ...
    'String','Component', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold');

ddCompIdx = uicontrol('Parent',panelComp,'Style','popupmenu','Units','normalized', ...
    'Position',[0.45 0.93 0.18 0.035], ...
    'String',{'1'}, ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onCompSelector);

axCompMap = axes('Parent',panelComp,'Units','normalized', ...
    'Position',[0.05 0.18 0.40 0.68], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);

axCompTS = axes('Parent',panelComp,'Units','normalized', ...
    'Position',[0.57 0.55 0.34 0.24], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axCompTS,'on');

axCompAux = axes('Parent',panelComp,'Units','normalized', ...
    'Position',[0.57 0.18 0.34 0.22], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axCompAux,'on');

txtCompInfo = uicontrol('Parent',panelComp,'Style','text','Units','normalized', ...
    'Position',[0.05 0.04 0.86 0.08], ...
    'String','Components not computed yet.', ...
    'BackgroundColor',bgPane,'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontSize',10);

guidata(fig, st);
switchPanel('Seed');
refreshAll();

% =========================================================================
% Nested callbacks
% =========================================================================
    function switchPanel(name)
        st = guidata(fig);

        set(panelSeed,'Visible','off');
        set(panelROI,'Visible','off');
        set(panelPair,'Visible','off');
        set(panelGroup,'Visible','off');
        set(panelGraph,'Visible','off');
        set(panelComp,'Visible','off');

        set(btnSeedTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnROITab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnPairTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnGroupTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnGraphTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);
        set(btnCompTab,'Value',0,'BackgroundColor',[0.16 0.16 0.18]);

        switch lower(name)
            case 'seed'
                set(panelSeed,'Visible','on');
                set(btnSeedTab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
            case 'roi'
                set(panelROI,'Visible','on');
                set(btnROITab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
            case 'pair'
                set(panelPair,'Visible','on');
                set(btnPairTab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
            case 'group'
                set(panelGroup,'Visible','on');
                set(btnGroupTab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
            case 'graph'
                set(panelGraph,'Visible','on');
                set(btnGraphTab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
            case 'components'
                set(panelComp,'Visible','on');
                set(btnCompTab,'Value',1,'BackgroundColor',[0.10 0.35 0.70]);
        end
    end

    function onSubjectChanged(~,~)
        st = guidata(fig);
        st.currentSubject = get(ddSubject,'Value');
        set(ddUnder,'String',underlayList(st.subjects(st.currentSubject).anat),'Value',1);
        guidata(fig,st);
        refreshAll();
    end

    function onUnderlayChanged(~,~)
        refreshSeedViewOnly();
    end

    function onSliceChanged(~,~)
        st = guidata(fig);
        st.slice = clamp(round(get(slZ,'Value')),1,st.Z);
        set(edZ,'String',sprintf('%d',st.slice));
        guidata(fig,st);
        refreshAll();
    end

    function onSliceEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edZ,'String'));
        if ~isfinite(v), v = st.slice; end
        st.slice = clamp(round(v),1,st.Z);
        set(edZ,'String',sprintf('%d',st.slice));
        set(slZ,'Value',st.slice);
        guidata(fig,st);
        refreshAll();
    end

    function onRadiusEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edR,'String'));
        if ~isfinite(v), v = st.seedR; end
        st.seedR = max(0,round(v));
        set(edR,'String',sprintf('%d',st.seedR));
        set(txtSeed,'String',seedString(st));
        guidata(fig,st);
    end

    function onComputeModeChanged(~,~)
        st = guidata(fig);
        st.useSliceOnly = logical(get(cbSliceOnly,'Value'));
        guidata(fig,st);
    end

    function onMapModeChanged(~,evt)
        st = guidata(fig);
        if strcmpi(evt.NewValue.String,'Fisher z')
            st.seedMapMode = 'z';
        else
            st.seedMapMode = 'r';
        end
        guidata(fig,st);
        refreshSeedViewOnly();
    end

    function onThrChanged(~,~)
        st = guidata(fig);
        st.seedAbsThr = double(get(slThr,'Value'));
        set(txtThr,'String',sprintf('|r| >= %.2f',st.seedAbsThr));
        guidata(fig,st);
        refreshSeedViewOnly();
    end

    function onAlphaChanged(~,~)
        st = guidata(fig);
        st.seedAlpha = double(get(slAlpha,'Value'));
        guidata(fig,st);
        refreshSeedViewOnly();
    end

    function onRoiMethodChanged(~,~)
        st = guidata(fig);
        lst = roiMethodList();
        idx = get(ddRoiMethod,'Value');
        st.roiMethod = roiMethodCode(lst{idx});
        guidata(fig,st);
        refreshROIView();
        refreshPairView();
        refreshGraphView();
    end

    function onRoiThrEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edRoiThr,'String'));
        if ~isfinite(v), v = st.roiAbsThr; end
        st.roiAbsThr = max(0,min(1,abs(v)));
        set(edRoiThr,'String',sprintf('%.2f',st.roiAbsThr));
        guidata(fig,st);
        refreshROIView();
        refreshGraphView();
    end

    function onReorderChanged(~,~)
        st = guidata(fig);
        strs = get(ddReorder,'String');
        idx = get(ddReorder,'Value');
        choice = lower(strtrim(strs{idx}));
        if ~isempty(strfind(choice,'none'))
            st.reorderMode = 'none';
        elseif ~isempty(strfind(choice,'label'))
            st.reorderMode = 'label';
        else
            st.reorderMode = 'ontology';
        end
        guidata(fig,st);
        refreshROIView();
        refreshGraphView();
        refreshGroupView();
    end

    function onGroupTargetChanged(~,~)
        st = guidata(fig);
        strs = get(ddGroupTarget,'String');
        idx = get(ddGroupTarget,'Value');
        if idx == 1
            st.groupTarget = 'seed';
        else
            st.groupTarget = 'roi';
        end
        guidata(fig,st);
        refreshGroupView();
    end

    function onGroupTestChanged(~,~)
        st = guidata(fig);
        st.groupTest = groupTestCode(get(ddGroupTest));
        guidata(fig,st);
    end

    function onGroupAChanged(~,~)
        st = guidata(fig);
        st.groupA = get(ddGroupA,'Value');
        guidata(fig,st);
    end

    function onGroupBChanged(~,~)
        st = guidata(fig);
        st.groupB = get(ddGroupB,'Value');
        guidata(fig,st);
    end

    function onAlphaEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edAlpha,'String'));
        if ~isfinite(v) || v <= 0 || v >= 1, v = st.groupAlpha; end
        st.groupAlpha = v;
        set(edAlpha,'String',sprintf('%.3f',st.groupAlpha));
        guidata(fig,st);
    end

    function onMapClick(~,~)
        st = guidata(fig);
        cp = get(axSeedMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x < 1 || x > st.X || y < 1 || y > st.Y, return; end
        st.seedX = x;
        st.seedY = y;
        set(txtSeed,'String',seedString(st));
        guidata(fig,st);
        refreshSeedViewOnly();
    end

    function onPairPopup(~,~)
        refreshPairView();
    end

    function onComputeSeed(~,~)
        st = guidata(fig);
        setStatus('Computing seed FC for current subject ...',accent);

        try
            s = st.subjects(st.currentSubject);
            res = compute_seed_fc_subject(s, st.seedX, st.seedY, st.slice, st.seedR, st.useSliceOnly, st.opts);
            st.seedResults{st.currentSubject} = res;
            guidata(fig,st);
            refreshSeedViewOnly();
            setStatus(sprintf('Seed FC done for %s.', s.name),goodC);
        catch ME
            setStatus(['SEED ERROR: ' ME.message],warnC);
            logStack(st.opts,ME);
            if st.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeROI(~,~)
        st = guidata(fig);
        setStatus('Computing ROI FC for all subjects ...',accent);

        try
            for i = 1:st.nSub
                if isempty(st.subjects(i).roiAtlas)
                    error('Subject %d (%s) has no roiAtlas.', i, st.subjects(i).name);
                end
                st.roiResults{i} = compute_roi_fc_subject(st.subjects(i), st.opts);
            end
            guidata(fig,st);
            refreshROIView();
            refreshPairView();
            refreshGraphView();
            setStatus('ROI FC done for all subjects.',goodC);
        catch ME
            setStatus(['ROI ERROR: ' ME.message],warnC);
            logStack(st.opts,ME);
            if st.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeGroup(~,~)
        st = guidata(fig);
        setStatus('Computing group statistics ...',accent);

        try
            if strcmpi(st.groupTarget,'seed')
                st = ensureAllSeedComputed(st);
                st.groupSeedStats = compute_group_seed_stats(st);
            else
                st = ensureAllROIComputed(st);
                st.groupRoiStats = compute_group_roi_stats(st);
            end
            guidata(fig,st);
            refreshGroupView();
            switchPanel('Group');
            setStatus('Group statistics finished.',goodC);
        catch ME
            setStatus(['GROUP ERROR: ' ME.message],warnC);
            logStack(st.opts,ME);
            if st.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onComputeComp(~,~)
        st = guidata(fig);
        setStatus('Computing PCA / ICA for current subject ...',accent);

        try
            st.compResults{st.currentSubject} = compute_components_subject(st.subjects(st.currentSubject), st.opts);
            guidata(fig,st);
            refreshComponentsView();
            switchPanel('Components');
            setStatus(sprintf('Component analysis done for %s.', st.subjects(st.currentSubject).name),goodC);
        catch ME
            setStatus(['COMP ERROR: ' ME.message],warnC);
            logStack(st.opts,ME);
            if st.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onCompSelector(~,~)
        refreshComponentsView();
    end

    function onSave(~,~)
        st = guidata(fig);

        try
            out = struct();
            out.subjects = st.subjects;
            out.seedResults = st.seedResults;
            out.roiResults = st.roiResults;
            out.groupSeedStats = st.groupSeedStats;
            out.groupRoiStats = st.groupRoiStats;
            out.compResults = st.compResults;
            out.gui = st;

            matFile = fullfile(st.qcDir, sprintf('FunctionalConnectivity_%s.mat', st.tag));
            save(matFile, 'out', '-v7.3');

            saveAxesPNG(axSeedMap, fig, fullfile(st.qcDir, sprintf('FC_seed_%s.png', st.tag)));
            saveAxesPNG(axRoiMat, fig, fullfile(st.qcDir, sprintf('FC_roi_%s.png', st.tag)));
            saveAxesPNG(axGroupMain, fig, fullfile(st.qcDir, sprintf('FC_group_%s.png', st.tag)));
            saveAxesPNG(axAdj, fig, fullfile(st.qcDir, sprintf('FC_graph_%s.png', st.tag)));
            saveAxesPNG(axCompMap, fig, fullfile(st.qcDir, sprintf('FC_comp_%s.png', st.tag)));
            saveas(fig, fullfile(st.qcDir, sprintf('FC_GUI_snapshot_%s.png', st.tag)));

            setStatus(['Saved outputs to ' st.qcDir],goodC);

        catch ME
            setStatus(['SAVE ERROR: ' ME.message],warnC);
            logStack(st.opts,ME);
            if st.opts.debugRethrow, rethrow(ME); end
        end
    end

    function onHelp(~,~)
        helpMsg = { ...
            'Functional Connectivity GUI - Tutorial', ...
            ' ', ...
            '1) Input', ...
            '   - You can pass one subject, a struct array, or a cell array of subjects.', ...
            '   - The GUI tries to find functional data in fields like I, PSC, data, functional, or func.', ...
            ' ', ...
            '2) Mask selection at startup', ...
            '   - Use provided masks: keeps subject-specific masks if available.', ...
            '   - Auto masks: builds masks from each subject mean image.', ...
            '   - Load common mask: loads one MAT mask and applies it to all subjects.', ...
            ' ', ...
            '3) Seed FC workflow', ...
            '   - Open Seed panel.', ...
            '   - Click inside the image to place the seed.', ...
            '   - Set seed radius and slice.', ...
            '   - Press "Compute seed FC".', ...
            '   - Use the threshold and alpha sliders to change the display.', ...
            ' ', ...
            '4) ROI FC workflow', ...
            '   - Provide roiAtlas for every subject.', ...
            '   - Press "Compute ROI FC".', ...
            '   - Switch ROI method to mean Pearson, partial, PC1, or RV.', ...
            '   - ROI panel shows the current-subject matrix.', ...
            '   - Pair panel shows the selected ROI pair timecourses and scatter.', ...
            ' ', ...
            '5) Group statistics', ...
            '   - Select target: Seed maps or ROI edges.', ...
            '   - Select test type.', ...
            '   - Choose Group A and Group B if needed.', ...
            '   - Press "Compute group statistics".', ...
            '   - Group panel shows BH-FDR corrected results.', ...
            ' ', ...
            '6) Reordering', ...
            '   - None: keep ROI order as computed.', ...
            '   - Label: sort by ROI numeric labels.', ...
            '   - Ontology: use opts.roiOntology or ROI names for left/right grouping.', ...
            ' ', ...
            '7) Components', ...
            '   - Press "Compute PCA / ICA".', ...
            '   - PCA always runs.', ...
            '   - ICA runs only if fastica is on your MATLAB path.', ...
            ' ', ...
            '8) Save', ...
            '   - Saves MAT results and panel PNGs to Connectivity/fc_QC.' ...
            };
        helpdlg(helpMsg, 'Functional Connectivity GUI Help');
    end

% =========================================================================
% Refresh helpers
% =========================================================================
    function refreshAll()
        refreshSeedViewOnly();
        refreshROIView();
        refreshPairView();
        refreshGraphView();
        refreshGroupView();
        refreshComponentsView();
    end

    function refreshSeedViewOnly()
        st = guidata(fig);
        set(txtSeed,'String',seedString(st));
        set(hCross1,'YData',[st.seedY st.seedY]);
        set(hCross2,'XData',[st.seedX st.seedX]);

        set(hUnder,'CData',getUnderlaySlice(st));
        title(axSeedMap, buildSeedTitle(st), 'Color', fg, 'FontWeight','bold');

        res = st.seedResults{st.currentSubject};
        if isempty(res)
            set(hOver,'CData',nan(st.Y,st.X,3));
            set(hOver,'AlphaData',0);
            plotNoData(axSeedTS,'Seed timecourse');
            plotNoData(axSeedHist,'Correlation histogram');
            return;
        end

        rS = res.rMap(:,:,st.slice);
        zS = res.zMap(:,:,st.slice);
        vis = abs(rS) >= st.seedAbsThr;
        vis = vis & st.subjects(st.currentSubject).mask(:,:,st.slice);

        if strcmpi(st.seedMapMode,'z')
            M = zS;
            clim = autoClim(M(vis),2.5);
        else
            M = rS;
            clim = [-1 1];
        end

        rgb = mapToRGB(M, st.fcCmap, clim);
        set(hOver,'CData',rgb);
        set(hOver,'AlphaData',st.seedAlpha * double(vis));

        ts = double(res.seedTS(:));
        tmin = ((0:numel(ts)-1) * st.subjects(st.currentSubject).TR) / 60;
        cla(axSeedTS);
        plot(axSeedTS,tmin,ts,'LineWidth',1.3);
        set(axSeedTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axSeedTS,'on');
        xlabel(axSeedTS,'Time (min)','Color',fgDim);
        ylabel(axSeedTS,'a.u.','Color',fgDim);
        title(axSeedTS,'Seed timecourse','Color',fg,'FontWeight','bold');

        r = res.rMap(st.subjects(st.currentSubject).mask);
        r = double(r(isfinite(r)));
        cla(axSeedHist);
        if isempty(r)
            plotNoData(axSeedHist,'Correlation histogram');
        else
            histogram(axSeedHist,r,60);
            set(axSeedHist,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axSeedHist,'on');
            xlabel(axSeedHist,'Pearson r','Color',fgDim);
            ylabel(axSeedHist,'Count','Color',fgDim);
            title(axSeedHist,'Correlation histogram','Color',fg,'FontWeight','bold');
        end
    end

    function refreshROIView()
        st = guidata(fig);
        cla(axRoiMat);
        cla(axRoiTS);

        res = st.roiResults{st.currentSubject};
        if isempty(res)
            plotNoData(axRoiMat,'ROI matrix');
            plotNoData(axRoiTS,'Selected ROI mean traces');
            set(txtRoiInfo,'String','ROI FC not computed yet.');
            set(ddPairA,'String',{'n/a'},'Value',1);
            set(ddPairB,'String',{'n/a'},'Value',1);
            return;
        end

        [M, names, order, infoStr] = getDisplayedRoiMatrix(st, res);
        imagesc(axRoiMat, M, [-1 1]);
        axis(axRoiMat,'image');
        colormap(axRoiMat, blueWhiteRed(256));
        set(axRoiMat,'XColor',fgDim,'YColor',fgDim);
        xlabel(axRoiMat,'ROI index','Color',fgDim);
        ylabel(axRoiMat,'ROI index','Color',fgDim);
        title(axRoiMat, buildRoiTitle(st), 'Color',fg,'FontWeight','bold');

        set(txtRoiInfo,'String',infoStr);

        set(ddPairA,'String',names);
        set(ddPairB,'String',names);
        vA = min(max(1, getSafePopupValue(ddPairA)), numel(names));
        vB = min(max(1, getSafePopupValue(ddPairB)), numel(names));
        set(ddPairA,'Value',vA);
        set(ddPairB,'Value',vB);

        if ~isempty(res.meanTS)
            tmin = ((0:size(res.meanTS,1)-1)*st.subjects(st.currentSubject).TR)/60;
            ia = order(vA);
            ib = order(vB);
            ta = zscoreSafe(double(res.meanTS(:,ia)));
            tb = zscoreSafe(double(res.meanTS(:,ib)));

            plot(axRoiTS,tmin,ta,'LineWidth',1.3);
            hold(axRoiTS,'on');
            plot(axRoiTS,tmin,tb,'LineWidth',1.3);
            hold(axRoiTS,'off');
            set(axRoiTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axRoiTS,'on');
            xlabel(axRoiTS,'Time (min)','Color',fgDim);
            ylabel(axRoiTS,'z-scored signal','Color',fgDim);
            legend(axRoiTS,{shortRoiName(names{vA}), shortRoiName(names{vB})}, ...
                'TextColor',fg,'Color',bgAx,'Location','best');
            title(axRoiTS,'Selected ROI mean traces','Color',fg,'FontWeight','bold');
        else
            plotNoData(axRoiTS,'Selected ROI mean traces');
        end
    end

    function refreshPairView()
        st = guidata(fig);
        cla(axPairTS); cla(axPairScatter); cla(axPairLag);

        res = st.roiResults{st.currentSubject};
        if isempty(res)
            plotNoData(axPairTS,'Pair timecourses');
            plotNoData(axPairScatter,'Pair scatter');
            plotNoData(axPairLag,'Cross-correlation');
            set(txtPairInfo,'String','ROI pair view not ready yet.');
            return;
        end

        [~, names, order] = getDisplayedRoiMatrix(st, res);
        a = min(max(1, getSafePopupValue(ddPairA)), numel(names));
        b = min(max(1, getSafePopupValue(ddPairB)), numel(names));
        ia = order(a);
        ib = order(b);

        tmin = ((0:size(res.meanTS,1)-1)*st.subjects(st.currentSubject).TR)/60;
        ta = double(res.meanTS(:,ia));
        tb = double(res.meanTS(:,ib));

        plot(axPairTS,tmin,zscoreSafe(ta),'LineWidth',1.3);
        hold(axPairTS,'on');
        plot(axPairTS,tmin,zscoreSafe(tb),'LineWidth',1.3);
        hold(axPairTS,'off');
        set(axPairTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axPairTS,'on');
        xlabel(axPairTS,'Time (min)','Color',fgDim);
        ylabel(axPairTS,'z-scored signal','Color',fgDim);
        title(axPairTS,'ROI pair mean traces','Color',fg,'FontWeight','bold');
        legend(axPairTS,{shortRoiName(names{a}), shortRoiName(names{b})}, ...
            'TextColor',fg,'Color',bgAx,'Location','best');

        scatter(axPairScatter,ta,tb,20,'filled');
        set(axPairScatter,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        grid(axPairScatter,'on');
        xlabel(axPairScatter,shortRoiName(names{a}),'Color',fgDim);
        ylabel(axPairScatter,shortRoiName(names{b}),'Color',fgDim);
        title(axPairScatter,'Scatter','Color',fg,'FontWeight','bold');

        maxLag = min(20, numel(ta)-1);
        if maxLag >= 1
            [xc,lags] = xcorr(zscoreSafe(ta), zscoreSafe(tb), maxLag, 'coeff');
            plot(axPairLag,lags*st.subjects(st.currentSubject).TR,xc,'LineWidth',1.3);
            set(axPairLag,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axPairLag,'on');
            xlabel(axPairLag,'Lag (sec)','Color',fgDim);
            ylabel(axPairLag,'xcorr','Color',fgDim);
            title(axPairLag,'Cross-correlation','Color',fg,'FontWeight','bold');
        else
            plotNoData(axPairLag,'Cross-correlation');
        end

        valStr = buildPairInfoString(res, ia, ib, names{a}, names{b});
        set(txtPairInfo,'String',valStr);
    end

    function refreshGroupView()
        st = guidata(fig);
        cla(axGroupMain); cla(axGroupAux);

        if strcmpi(st.groupTarget,'seed')
            G = st.groupSeedStats;
            if isempty(G)
                plotNoData(axGroupMain,'Group seed statistics');
                plotNoData(axGroupAux,'Significant voxel histogram');
                set(txtGroupInfo,'String','Group statistics not computed yet.');
                return;
            end

            S = G.statMap(:,:,st.slice);
            Q = G.qMap(:,:,st.slice);
            Smask = S;
            Smask(Q > st.groupAlpha) = 0;
            imagesc(axGroupMain, Smask);
            axis(axGroupMain,'image'); axis(axGroupMain,'off');
            colormap(axGroupMain, blueWhiteRed(256));
            title(axGroupMain,'Group seed statistics (BH-FDR masked)','Color',fg,'FontWeight','bold');

            qvals = G.qMap(G.maskGroup);
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                plotNoData(axGroupAux,'q-value histogram');
            else
                histogram(axGroupAux,qvals,40);
                set(axGroupAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q-value','Color',fgDim);
                ylabel(axGroupAux,'Count','Color',fgDim);
                title(axGroupAux,'Voxel q-value histogram','Color',fg,'FontWeight','bold');
            end

            set(txtGroupInfo,'String',buildGroupSeedInfoString(G, st.groupAlpha));

        else
            G = st.groupRoiStats;
            if isempty(G)
                plotNoData(axGroupMain,'Group ROI statistics');
                plotNoData(axGroupAux,'q-value histogram');
                set(txtGroupInfo,'String','Group statistics not computed yet.');
                return;
            end

            [Mshow, namesShow, order] = reorderMatrixAndNames(G.statMatrix, G.names, G.labels, st.opts, st.reorderMode);
            Qshow = G.qMatrix(order, order);
            Mshow(Qshow > st.groupAlpha) = 0;

            imagesc(axGroupMain, Mshow);
            axis(axGroupMain,'image');
            colormap(axGroupMain, blueWhiteRed(256));
            set(axGroupMain,'XColor',fgDim,'YColor',fgDim);
            xlabel(axGroupMain,'ROI index','Color',fgDim);
            ylabel(axGroupMain,'ROI index','Color',fgDim);
            title(axGroupMain,'Group ROI statistics (BH-FDR masked)','Color',fg,'FontWeight','bold');

            qvals = G.qVector;
            qvals = qvals(isfinite(qvals));
            if isempty(qvals)
                plotNoData(axGroupAux,'q-value histogram');
            else
                histogram(axGroupAux,qvals,40);
                set(axGroupAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
                grid(axGroupAux,'on');
                xlabel(axGroupAux,'q-value','Color',fgDim);
                ylabel(axGroupAux,'Count','Color',fgDim);
                title(axGroupAux,'Edge q-value histogram','Color',fg,'FontWeight','bold');
            end

            set(txtGroupInfo,'String',buildGroupRoiInfoString(G, st.groupAlpha));
        end
    end

    function refreshGraphView()
        st = guidata(fig);
        cla(axAdj); cla(axDeg);

        res = st.roiResults{st.currentSubject};
        if isempty(res)
            plotNoData(axAdj,'Adjacency');
            plotNoData(axDeg,'Degree histogram');
            set(txtGraphInfo,'String','Graph view not ready yet.');
            return;
        end

        [M, namesShow, labelsShow] = getDisplayedRoiMatrix(st, res);
        G = compute_graph_summary(M, st.roiAbsThr, namesShow);

        imagesc(axAdj, G.A);
        axis(axAdj,'image');
        colormap(axAdj, gray(256));
        set(axAdj,'XColor',fgDim,'YColor',fgDim);
        xlabel(axAdj,'ROI index','Color',fgDim);
        ylabel(axAdj,'ROI index','Color',fgDim);
        title(axAdj,'Adjacency from current ROI matrix','Color',fg,'FontWeight','bold');

        if isempty(G.degree)
            plotNoData(axDeg,'Degree histogram');
        else
            histogram(axDeg, G.degree);
            set(axDeg,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axDeg,'on');
            xlabel(axDeg,'Degree','Color',fgDim);
            ylabel(axDeg,'Count','Color',fgDim);
            title(axDeg,'Degree histogram','Color',fg,'FontWeight','bold');
        end

        set(txtGraphInfo,'String',buildGraphInfoString(G));
    end

    function refreshComponentsView()
        st = guidata(fig);
        cla(axCompMap); cla(axCompTS); cla(axCompAux);

        res = st.compResults{st.currentSubject};
        if isempty(res)
            plotNoData(axCompMap,'Component map');
            plotNoData(axCompTS,'Component timecourse');
            plotNoData(axCompAux,'Component summary');
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
            n = res.nPCA;
        else
            n = res.nICA;
        end
        if n < 1, n = 1; end
        idxList = cell(n,1);
        for i = 1:n, idxList{i} = sprintf('%d',i); end
        set(ddCompIdx,'String',idxList);
        idx = min(max(1, getSafePopupValue(ddCompIdx)), n);
        set(ddCompIdx,'Value',idx);

        if strcmpi(typ,'pca')
            vol = maskedVectorToVol(res.pcaSpatial(:,idx), st.subjects(st.currentSubject).mask);
            sli = vol(:,:,st.slice);
            imagesc(axCompMap, sli);
            axis(axCompMap,'image'); axis(axCompMap,'off');
            colormap(axCompMap, blueWhiteRed(256));
            title(axCompMap,sprintf('PCA component %d',idx),'Color',fg,'FontWeight','bold');

            tc = res.pcaTS(:,idx);
            tmin = ((0:numel(tc)-1)*st.subjects(st.currentSubject).TR)/60;
            plot(axCompTS,tmin,tc,'LineWidth',1.3);
            set(axCompTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',fgDim);
            ylabel(axCompTS,'score','Color',fgDim);
            title(axCompTS,'PCA timecourse','Color',fg,'FontWeight','bold');

            nShow = min(10,numel(res.pcaExplained));
            bar(axCompAux,100*res.pcaExplained(1:nShow));
            set(axCompAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Component','Color',fgDim);
            ylabel(axCompAux,'Explained variance (%)','Color',fgDim);
            title(axCompAux,'PCA explained variance','Color',fg,'FontWeight','bold');

            set(txtCompInfo,'String',sprintf( ...
                'PCA computed for %s. nMaskedVox=%d, nPCA=%d. Component %d explains %.2f%% variance.', ...
                st.subjects(st.currentSubject).name, res.nMasked, res.nPCA, idx, 100*res.pcaExplained(idx)));

        else
            if ~res.hasICA
                plotNoData(axCompMap,'ICA unavailable');
                plotNoData(axCompTS,'ICA unavailable');
                plotNoData(axCompAux,'ICA unavailable');
                set(txtCompInfo,'String','ICA unavailable. Put fastica on the MATLAB path.');
                return;
            end

            vol = maskedVectorToVol(res.icaSpatial(:,idx), st.subjects(st.currentSubject).mask);
            sli = vol(:,:,st.slice);
            imagesc(axCompMap, sli);
            axis(axCompMap,'image'); axis(axCompMap,'off');
            colormap(axCompMap, blueWhiteRed(256));
            title(axCompMap,sprintf('ICA component %d',idx),'Color',fg,'FontWeight','bold');

            tc = res.icaTS(:,idx);
            tmin = ((0:numel(tc)-1)*st.subjects(st.currentSubject).TR)/60;
            plot(axCompTS,tmin,tc,'LineWidth',1.3);
            set(axCompTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompTS,'on');
            xlabel(axCompTS,'Time (min)','Color',fgDim);
            ylabel(axCompTS,'source','Color',fgDim);
            title(axCompTS,'ICA timecourse','Color',fg,'FontWeight','bold');

            histogram(axCompAux,tc,40);
            set(axCompAux,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
            grid(axCompAux,'on');
            xlabel(axCompAux,'Value','Color',fgDim);
            ylabel(axCompAux,'Count','Color',fgDim);
            title(axCompAux,'ICA histogram','Color',fg,'FontWeight','bold');

            set(txtCompInfo,'String',sprintf( ...
                'ICA computed for %s. nMaskedVox=%d, nICA=%d.', ...
                st.subjects(st.currentSubject).name, res.nMasked, res.nICA));
        end
    end

    function setStatus(msg, colorIn)
        set(txtStatus,'String',msg,'ForegroundColor',colorIn);
        drawnow limitrate;
    end

    function st = ensureAllSeedComputed(st)
        for ii = 1:st.nSub
            if isempty(st.seedResults{ii})
                st.seedResults{ii} = compute_seed_fc_subject(st.subjects(ii), st.seedX, st.seedY, st.slice, st.seedR, st.useSliceOnly, st.opts);
            else
                si = st.seedResults{ii}.seedInfo;
                if si.seedX ~= st.seedX || si.seedY ~= st.seedY || si.seedZ ~= st.slice || ...
                        si.seedRadius ~= st.seedR || logical(si.useSliceOnly) ~= logical(st.useSliceOnly)
                    st.seedResults{ii} = compute_seed_fc_subject(st.subjects(ii), st.seedX, st.seedY, st.slice, st.seedR, st.useSliceOnly, st.opts);
                end
            end
        end
    end

    function st = ensureAllROIComputed(st)
        for ii = 1:st.nSub
            if isempty(st.roiResults{ii})
                st.roiResults{ii} = compute_roi_fc_subject(st.subjects(ii), st.opts);
            end
        end
    end

end

% =========================================================================
% Subject normalization and startup utilities
% =========================================================================
function subjects = normalizeSubjects(dataIn, opts)

if iscell(dataIn)
    n = numel(dataIn);
    rawList = dataIn;
elseif isstruct(dataIn) && numel(dataIn) > 1
    n = numel(dataIn);
    rawList = cell(n,1);
    for i = 1:n, rawList{i} = dataIn(i); end
else
    n = 1;
    rawList = {dataIn};
end

subjects = repmat(struct('I4',[],'TR',1,'mask',[],'anat',[],'roiAtlas',[], ...
    'name','','group','All','pairID',[]), n, 1);

chosenField = '';
for i = 1:n
    [I4, TR, mask, anat, roiAtlas, name, group, pairID, chosenField] = ...
        normalizeOneSubject(rawList{i}, opts, i, chosenField);

    subjects(i).I4 = I4;
    subjects(i).TR = TR;
    subjects(i).mask = mask;
    subjects(i).anat = anat;
    subjects(i).roiAtlas = roiAtlas;
    subjects(i).name = name;
    subjects(i).group = group;
    subjects(i).pairID = pairID;
end
end

function [I4, TR, mask, anat, roiAtlas, name, group, pairID, chosenField] = ...
    normalizeOneSubject(in, opts, idx, chosenField)

TR = 1;
mask = [];
anat = [];
roiAtlas = [];
pairID = idx;
group = 'All';
name = sprintf('Subject_%02d', idx);

if isnumeric(in)
    I4 = force4Dsingle(in);
    if isempty(opts.datasetName)
        name = sprintf('Subject_%02d', idx);
    else
        name = sprintf('%s_%02d', opts.datasetName, idx);
    end
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

[Y,X,Z] = getSpatialSize(I4);

if isfield(in,'mask') && ~isempty(in.mask)
    mask = interpretVolume(in.mask, Y, X, Z, true);
end
if isempty(mask) && isfield(in,'brainMask') && ~isempty(in.brainMask)
    mask = interpretVolume(in.brainMask, Y, X, Z, true);
end

if isfield(in,'anat') && ~isempty(in.anat)
    anat = interpretVolume(in.anat, Y, X, Z, false);
end
if isempty(anat) && isfield(in,'bg') && ~isempty(in.bg)
    anat = interpretVolume(in.bg, Y, X, Z, false);
end

if isfield(in,'roiAtlas') && ~isempty(in.roiAtlas)
    roiAtlas = interpretVolume(in.roiAtlas, Y, X, Z, false);
elseif isfield(in,'atlas') && ~isempty(in.atlas)
    roiAtlas = interpretVolume(in.atlas, Y, X, Z, false);
elseif isfield(in,'regions') && ~isempty(in.regions)
    roiAtlas = interpretVolume(in.regions, Y, X, Z, false);
end

if ~isempty(roiAtlas)
    roiAtlas = round(double(roiAtlas));
end
end

function [fieldName, Iraw] = extractFunctionalData(s, opts)

cand = {'I','PSC','data','functional','func','movie','brain','img','volume'};
avail = {};
for i = 1:numel(cand)
    if isfield(s,cand{i}) && ~isempty(s.(cand{i})) && isnumeric(s.(cand{i}))
        dims = ndims(s.(cand{i}));
        if dims == 3 || dims == 4
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

if isfield(opts,'functionalField') && ~isempty(opts.functionalField) && isfield(s,opts.functionalField)
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
    Y = sz(1); X = sz(2); T = sz(3); Z = 1;
    I4 = reshape(single(I), Y, X, 1, T);
elseif ndims(I) == 4
    I4 = single(I);
else
    error('Functional data must be [Y X T] or [Y X Z T].');
end
end

function [Y,X,Z] = getSpatialSize(I4)
sz = size(I4);
Y = sz(1); X = sz(2); Z = sz(3);
end

function [subjects, info] = applyStartupMaskStrategy(subjects, opts)

[Y,X,Z] = getSpatialSize(subjects(1).I4);

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
    if ~isempty(subjects(i).mask), hasAnyProvided = true; break; end
end

if hasAnyProvided
    choice = questdlg( ...
        'Mask selection: choose startup strategy.', ...
        'Startup mask selection', ...
        'Use provided masks', 'Auto masks', 'Load one common mask', ...
        'Use provided masks');
else
    choice = questdlg( ...
        'No provided subject masks found. Choose startup strategy.', ...
        'Startup mask selection', ...
        'Auto masks', 'Load one common mask', 'Auto masks');
end

if isempty(choice)
    choice = 'Auto masks';
end

switch lower(strtrim(choice))
    case 'use provided masks'
        for i = 1:numel(subjects)
            if isempty(subjects(i).mask)
                subjects(i).mask = buildAutoMask(subjects(i).I4);
            end
        end
        info = 'Used provided masks; auto fallback where missing.';
    case 'load one common mask'
        [f,p] = uigetfile('*.mat','Select common mask MAT file');
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
            info = ['Loaded one common mask from ' f];
        end
    otherwise
        for i = 1:numel(subjects)
            subjects(i).mask = buildAutoMask(subjects(i).I4);
        end
        info = 'Used auto masks.';
end
end

function [atlas, ok] = maybeLoadCommonAtlas(Y, X, Z)
ok = false;
atlas = [];
q = questdlg('No roiAtlas found. Load one common ROI atlas MAT now?', ...
    'Load ROI atlas', 'Yes', 'No', 'No');
if ~strcmpi(q,'Yes')
    return;
end

[f,p] = uigetfile('*.mat','Select common ROI atlas MAT file');
if isequal(f,0)
    return;
end

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

function mask = buildAutoMask(I4)
mimg = mean(I4,4);
thr = prctileSafe(mimg(:), 25);
mask = logical(mimg > thr);
end

% =========================================================================
% Single-subject computation
% =========================================================================
function res = compute_seed_fc_subject(subj, seedX, seedY, sliceZ, seedR, useSliceOnly, opts)

I4 = subj.I4;
mask = subj.mask;
[Y,X,Z,T] = size(I4);

seedMask2D = diskMask(Y, X, seedY, seedX, seedR);
seedMask3D = false(Y,X,Z);
seedMask3D(:,:,sliceZ) = seedMask2D;
seedMask3D = seedMask3D & mask;

seedV = find(seedMask3D(:));
if isempty(seedV)
    seedMask3D = false(Y,X,Z);
    seedMask3D(seedY, seedX, sliceZ) = true;
    seedV = find(seedMask3D(:));
end

V = Y*X*Z;
Xvt = reshape(I4,[V T]);

seedTS = mean(double(Xvt(seedV,:)),1);
seedTS = seedTS(:);
s = double(seedTS - mean(seedTS));
sNorm = sqrt(sum(s.^2));
if sNorm <= 0 || ~isfinite(sNorm)
    error('Seed timecourse has zero variance.');
end

r = nan(V,1,'single');

if useSliceOnly
    voxMask = false(Y,X,Z);
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
    i1 = min(numel(voxIdx), i0+chunkVox-1);
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

rMap = reshape(r,[Y X Z]);
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

[Y,X,Z,T] = size(subj.I4);
V = Y*X*Z;
Xvt = reshape(subj.I4,[V T]);
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

    Xroi = double(Xvt(idx,:))';  % [T x nvox]
    if isempty(Xroi)
        continue;
    end

    m = mean(Xroi,2);

    Xc = bsxfun(@minus, Xroi, mean(Xroi,1));
    if all(abs(Xc(:)) < eps)
        pc = m;
        rvF = zscoreSafe(m);
    else
        [U,S,~] = svd(Xc,'econ');
        pc = U(:,1) * S(1,1);
        if corrScalarSafe(pc,m) < 0
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

Xvt = reshape(subj.I4,[],size(subj.I4,4));
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
            [icasig, A, ~] = fastica(Xmask, ...
                'numOfIC', nICA, ...
                'verbose', 'off', ...
                'displayMode', 'off');
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

% =========================================================================
% Group statistics
% =========================================================================
function G = compute_group_seed_stats(st)

groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};

idxA = find(strcmpCellstr(groups, grpAName));
idxB = find(strcmpCellstr(groups, grpBName));

if isempty(idxA)
    error('Group A is empty.');
end

% Stack z maps
V = st.Y * st.X * st.Z;
maskGroup = true(st.Y, st.X, st.Z);
for i = idxA(:)'
    maskGroup = maskGroup & st.subjects(i).mask;
end
for i = idxB(:)'
    maskGroup = maskGroup & st.subjects(i).mask;
end
maskV = maskGroup(:);
featIdx = find(maskV);

ZA = zeros(numel(featIdx), numel(idxA));
for i = 1:numel(idxA)
    z = st.seedResults{idxA(i)}.zMap;
    ZA(:,i) = double(z(featIdx));
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
            z = st.seedResults{idxB(i)}.zMap;
            ZB(:,i) = double(z(featIdx));
        end
        [stat,p,meanVal,nUsed] = stat_twosample_t(ZA, ZB);
    case 'two_sample_wilcoxon'
        if isempty(idxB), error('Group B is empty.'); end
        ZB = zeros(numel(featIdx), numel(idxB));
        for i = 1:numel(idxB)
            z = st.seedResults{idxB(i)}.zMap;
            ZB(:,i) = double(z(featIdx));
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
    idxA = idxA(1:nUse);
    idxB = idxB(1:nUse);
else
    iAkeep = [];
    iBkeep = [];
    for i = 1:numel(commonPairs)
        ia = find(strcmp(pairA, commonPairs{i}), 1, 'first');
        ib = find(strcmp(pairB, commonPairs{i}), 1, 'first');
        if ~isempty(ia) && ~isempty(ib)
            iAkeep(end+1) = idxA(ia); %#ok<AGROW>
            iBkeep(end+1) = idxB(ib); %#ok<AGROW>
        end
    end
    idxA = iAkeep;
    idxB = iBkeep;
end

ZB = zeros(numel(featIdx), numel(idxB));
for i = 1:numel(idxB)
    z = st.seedResults{idxB(i)}.zMap;
    ZB(:,i) = double(z(featIdx));
end
end

function G = compute_group_roi_stats(st)

groups = {st.subjects.group};
grpAName = st.groupNames{st.groupA};
grpBName = st.groupNames{st.groupB};

idxA = find(strcmpCellstr(groups, grpAName));
idxB = find(strcmpCellstr(groups, grpBName));

if isempty(idxA)
    error('Group A is empty.');
end

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
    groupAvgMatrix = nan(nR);
    groupAvgMatrix(ut) = tanh(groupAvgA);
    groupAvgMatrix = groupAvgMatrix + groupAvgMatrix';
else
    groupAvgA = nanmean_safe(XA,2);
    groupAvgMatrix = nan(nR);
    groupAvgMatrix(ut) = groupAvgA;
    groupAvgMatrix = groupAvgMatrix + groupAvgMatrix';
end
groupAvgMatrix(1:nR+1:end) = 1;

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
G.groupAverageMatrix = groupAvgMatrix;
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
stack = nan(nR,nR,st.nSub);
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

    Ms = nan(nR,nR);
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
    idxA = idxA(1:nUse);
    idxB = idxB(1:nUse);
else
    iAkeep = [];
    iBkeep = [];
    for i = 1:numel(commonPairs)
        ia = find(strcmp(pairA, commonPairs{i}), 1, 'first');
        ib = find(strcmp(pairB, commonPairs{i}), 1, 'first');
        if ~isempty(ia) && ~isempty(ib)
            iAkeep(end+1) = idxA(ia); %#ok<AGROW>
            iBkeep(end+1) = idxB(ib); %#ok<AGROW>
        end
    end
    idxA = iAkeep;
    idxB = iBkeep;
end

XB = stack(:,:,idxB);
end

% =========================================================================
% Statistical tests
% =========================================================================
function [stat,p,meanVal,nUsed] = stat_onesample_t(X)
% X: features x subjects
n = sum(isfinite(X),2);
m = nanmean_safe(X,2);
sd = nanstd_safe(X,0,2);
se = sd ./ sqrt(max(n,1));
t = m ./ max(se, eps);
df = max(n-1, 1);
p = 2 * tcdf(-abs(t), df);
t(n < 2) = NaN;
p(n < 2) = NaN;
stat = t;
meanVal = m;
nUsed = median(n(n>0));
end

function [stat,p,meanVal,nUsed] = stat_paired_t(XA, XB)
D = XA - XB;
[stat,p,meanVal,nUsed] = stat_onesample_t(D);
end

function [stat,p,meanVal,nUsed] = stat_twosample_t(XA, XB)
nA = sum(isfinite(XA),2);
nB = sum(isfinite(XB),2);
mA = nanmean_safe(XA,2);
mB = nanmean_safe(XB,2);
vA = nanvar_safe(XA,0,2);
vB = nanvar_safe(XB,0,2);

se = sqrt(vA ./ max(nA,1) + vB ./ max(nB,1));
t = (mA - mB) ./ max(se, eps);

df_num = (vA ./ max(nA,1) + vB ./ max(nB,1)).^2;
df_den = ((vA ./ max(nA,1)).^2 ./ max(nA-1,1)) + ((vB ./ max(nB,1)).^2 ./ max(nB-1,1));
df = df_num ./ max(df_den, eps);

p = 2 * tcdf(-abs(t), df);
bad = nA < 2 | nB < 2;
t(bad) = NaN;
p(bad) = NaN;

stat = t;
meanVal = mA - mB;
nUsed = [median(nA(nA>0)) median(nB(nB>0))];
end

function [stat,p,meanVal,nUsed] = stat_onesample_signrank(X)
nF = size(X,1);
stat = nan(nF,1);
p = nan(nF,1);
meanVal = nanmean_safe(X,2);
for i = 1:nF
    xi = X(i,:);
    xi = xi(isfinite(xi));
    if numel(xi) >= 2
        try
            p(i) = signrank(xi, 0);
            stat(i) = median(xi);
        catch
            p(i) = NaN;
            stat(i) = NaN;
        end
    end
end
nUsed = median(sum(isfinite(X),2));
end

function [stat,p,meanVal,nUsed] = stat_paired_signrank(XA, XB)
D = XA - XB;
[stat,p,meanVal,nUsed] = stat_onesample_signrank(D);
end

function [stat,p,meanVal,nUsed] = stat_twosample_ranksum(XA, XB)
nF = size(XA,1);
stat = nan(nF,1);
p = nan(nF,1);
meanVal = nanmean_safe(XA,2) - nanmean_safe(XB,2);
for i = 1:nF
    a = XA(i,:); a = a(isfinite(a));
    b = XB(i,:); b = b(isfinite(b));
    if numel(a) >= 1 && numel(b) >= 1
        try
            p(i) = ranksum(a,b);
            stat(i) = median(a) - median(b);
        catch
            p(i) = NaN;
            stat(i) = NaN;
        end
    end
end
nUsed = [median(sum(isfinite(XA),2)) median(sum(isfinite(XB),2))];
end

function q = bh_fdr_vector(p)
p = p(:);
m = numel(p);
[ps, ord] = sort(p);
qsorted = ps .* m ./ (1:m)';
for i = m-1:-1:1
    qsorted(i) = min(qsorted(i), qsorted(i+1));
end
qsorted = min(qsorted, 1);
q = nan(size(p));
q(ord) = qsorted;
end

% =========================================================================
% ROI display / ordering
% =========================================================================
function [Mout, namesOut, order, infoStr, labelsOut] = getDisplayedRoiMatrix(st, res)

switch lower(st.roiMethod)
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

[Mout, namesOut, order] = reorderMatrixAndNames(M, res.names, res.labels, st.opts, st.reorderMode);
labelsOut = res.labels(order);

Mplot = Mout;
Mplot(abs(Mplot) < st.roiAbsThr) = 0;
Mout = Mplot;

infoStr = sprintf(['Subject: %s\n' ...
    'nROI: %d\n' ...
    'Method: %s\n' ...
    'Threshold |value| >= %.2f\n' ...
    'Reorder: %s'], ...
    st.subjects(st.currentSubject).name, numel(res.labels), st.roiMethod, st.roiAbsThr, st.reorderMode);
end

function [M2, names2, order] = reorderMatrixAndNames(M, names, labels, opts, mode)

n = numel(labels);
order = (1:n)';

switch lower(mode)
    case 'label'
        [~, order] = sort(labels);
    case 'ontology'
        order = ontologyOrder(names, labels, opts);
    otherwise
        order = (1:n)';
end

M2 = M(order, order);
names2 = names(order);
end

function order = ontologyOrder(names, labels, opts)

n = numel(labels);
order = (1:n)';

if isfield(opts,'roiOntology') && ~isempty(opts.roiOntology)
    ont = opts.roiOntology;
    if isnumeric(ont) && numel(ont) == n
        [~, order] = sortrows([ont(:) labels(:)], [1 2]);
        return;
    elseif iscell(ont) && numel(ont) == n
        [~, idx] = sort(lower(ont(:)));
        order = idx;
        return;
    end
end

% Fallback heuristic from ROI names
group = zeros(n,1);
hemi = zeros(n,1);
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

% =========================================================================
% Graph summary
% =========================================================================
function G = compute_graph_summary(M, thr, roiNames)

if isempty(M)
    G = struct('A',[],'degree',[],'density',NaN,'meanDegree',NaN, ...
        'meanClustering',NaN,'charPathLength',NaN,'nComponents',NaN,'topHubs',{{}});
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

try
    GG = graph(A);
    D = distances(GG);
    vals = D(isfinite(D) & D > 0);
    if isempty(vals)
        cpl = NaN;
    else
        cpl = mean(vals);
    end
    comps = max(conncomp(GG));
catch
    cpl = NaN;
    comps = NaN;
end

[~, ord] = sort(deg,'descend');
nHub = min(5,numel(ord));
topHubs = cell(nHub,1);
for i = 1:nHub
    idx = ord(i);
    if nargin >= 3 && ~isempty(roiNames) && idx <= numel(roiNames)
        topHubs{i} = sprintf('%s (deg=%d)', shortRoiName(roiNames{idx}), deg(idx));
    else
        topHubs{i} = sprintf('ROI %d (deg=%d)', idx, deg(idx));
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
G.topHubs = topHubs;
end

% =========================================================================
% Display strings
% =========================================================================
function s = seedString(st)
s = sprintf('Seed: x=%d, y=%d, z=%d, radius=%d', st.seedX, st.seedY, st.slice, st.seedR);
end

function s = buildSeedTitle(st)
nm = st.subjects(st.currentSubject).name;
if strcmpi(st.seedMapMode,'z')
    s = sprintf('Seed-based FC (Fisher z) - %s', nm);
else
    s = sprintf('Seed-based FC (Pearson r) - %s', nm);
end
end

function s = buildRoiTitle(st)
s = sprintf('ROI FC matrix - %s - %s', st.roiMethod, st.subjects(st.currentSubject).name);
end

function s = buildPairInfoString(res, ia, ib, nameA, nameB)
s = sprintf(['Pair: %s <-> %s\n' ...
    'Mean Pearson   = %.4f\n' ...
    'Mean Partial   = %.4f\n' ...
    'PC1 Pearson    = %.4f\n' ...
    'PC1 Partial    = %.4f\n' ...
    'RV coefficient = %.4f'], ...
    shortRoiName(nameA), shortRoiName(nameB), ...
    res.M_mean_pearson(ia,ib), ...
    res.M_mean_partial(ia,ib), ...
    res.M_pc1_pearson(ia,ib), ...
    res.M_pc1_partial(ia,ib), ...
    res.M_rv(ia,ib));
end

function s = buildGraphInfoString(G)
if isempty(G) || isempty(G.A)
    s = 'Graph view not ready yet.';
    return;
end
s = sprintf(['Density              = %.4f\n' ...
    'Mean degree          = %.4f\n' ...
    'Mean clustering      = %.4f\n' ...
    'Characteristic path  = %.4f\n' ...
    'Connected components = %d\n\n' ...
    'Top hubs:\n%s'], ...
    G.density, G.meanDegree, G.meanClustering, G.charPathLength, G.nComponents, ...
    joinCellLines(G.topHubs));
end

function s = buildGroupSeedInfoString(G, alpha)
s = sprintf(['Target: seed maps\n' ...
    'Test: %s\n' ...
    'Group A: %s (n=%d)\n' ...
    'Group B: %s (n=%d)\n' ...
    'BH q threshold: %.3f\n' ...
    'Significant voxels: %d'], ...
    G.test, G.groupA, G.nA, G.groupB, G.nB, alpha, G.nSignificant);
end

function s = buildGroupRoiInfoString(G, alpha)
s = sprintf(['Target: ROI edges\n' ...
    'Test: %s\n' ...
    'Group A: %s (n=%d)\n' ...
    'Group B: %s (n=%d)\n' ...
    'Common ROIs: %d\n' ...
    'BH q threshold: %.3f\n' ...
    'Significant edges: %d'], ...
    G.test, G.groupA, G.nA, G.groupB, G.nB, numel(G.labels), alpha, G.nSignificantEdges);
end

function s = joinCellLines(c)
if isempty(c), s = 'none'; return; end
s = c{1};
for i = 2:numel(c)
    s = sprintf('%s\n%s', s, c{i});
end
end

% =========================================================================
% Low-level helpers
% =========================================================================
function opts = normalizeOpts(opts)
if nargin < 1 || isempty(opts) || ~isstruct(opts)
    opts = struct();
end
if ~isfield(opts,'datasetName'), opts.datasetName = ''; end
if ~isfield(opts,'functionalField'), opts.functionalField = ''; end
if ~isfield(opts,'mask'), opts.mask = []; end
if ~isfield(opts,'anat'), opts.anat = []; end
if ~isfield(opts,'roiAtlas'), opts.roiAtlas = []; end
if ~isfield(opts,'roiNames'), opts.roiNames = {}; end
if ~isfield(opts,'roiOntology'), opts.roiOntology = []; end
if ~isfield(opts,'seedRadius') || isempty(opts.seedRadius), opts.seedRadius = 1; end
if ~isfield(opts,'chunkVox') || isempty(opts.chunkVox), opts.chunkVox = 6000; end
if ~isfield(opts,'useSliceOnly') || isempty(opts.useSliceOnly), opts.useSliceOnly = false; end
if ~isfield(opts,'roiMinVox') || isempty(opts.roiMinVox), opts.roiMinVox = 9; end
if ~isfield(opts,'roiAbsThr') || isempty(opts.roiAbsThr), opts.roiAbsThr = 0.20; end
if ~isfield(opts,'rvVarExplained') || isempty(opts.rvVarExplained), opts.rvVarExplained = 0.20; end
if ~isfield(opts,'pcaN') || isempty(opts.pcaN), opts.pcaN = 5; end
if ~isfield(opts,'icaN') || isempty(opts.icaN), opts.icaN = 5; end
if ~isfield(opts,'askMaskAtStart') || isempty(opts.askMaskAtStart), opts.askMaskAtStart = true; end
if ~isfield(opts,'askAtlasAtStart') || isempty(opts.askAtlasAtStart), opts.askAtlasAtStart = true; end
if ~isfield(opts,'askDataFieldAtStart') || isempty(opts.askDataFieldAtStart), opts.askDataFieldAtStart = true; end
if ~isfield(opts,'debugRethrow') || isempty(opts.debugRethrow), opts.debugRethrow = false; end
if ~isfield(opts,'logFcn'), opts.logFcn = []; end
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

function lst = underlayList(anat)
lst = {'Mean (data)','Median (data)'};
if ~isempty(anat)
    lst{end+1} = 'Anat (provided)';
end
end

function img = getUnderlaySlice(st)
subj = st.subjects(st.currentSubject);
lst = underlayList(subj.anat);
% infer current underlay from popup not stored
% use popup order directly
img = [];
try
    fig = gcbf;
catch
end

% safe fallback: always mean if anat unavailable
% actual popup selection handled outside by always requerying ddUnder in main refresh
% but subfunction does not know ddUnder, so use simple default logic:
% mean unless anat exists and popup later changed - here use mean/median/anat not critical
% To support the control correctly, use stored heuristic via appdata
mode = getappdata(0, 'FC_UNDERLAY_MODE_TEMP');
if isempty(mode), mode = 'mean'; end

switch lower(mode)
    case 'median'
        img = squeeze(median(subj.I4,4));
        img = img(:,:,st.slice);
    case 'anat'
        if ~isempty(subj.anat)
            img = subj.anat(:,:,st.slice);
        else
            img = squeeze(mean(subj.I4,4));
            img = img(:,:,st.slice);
        end
    otherwise
        img = squeeze(mean(subj.I4,4));
        img = img(:,:,st.slice);
end

img = single(img);
mn = prctileSafe(img(:),1);
mx = prctileSafe(img(:),99);
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    mn = min(img(:));
    mx = max(img(:));
    if mx <= mn, mx = mn + 1; end
end
img = (img - mn) / (mx - mn);
img = max(0,min(1,img));
end

function m = diskMask(Y, X, cy, cx, r)
m = false(Y,X);
if r <= 0
    if cy >= 1 && cy <= Y && cx >= 1 && cx <= X
        m(cy,cx) = true;
    end
    return;
end
[xx,yy] = meshgrid(1:X,1:Y);
m = ((xx-cx).^2 + (yy-cy).^2) <= r^2;
end

function clim = autoClim(vals, fallback)
vals = vals(isfinite(vals));
if isempty(vals)
    clim = [-fallback fallback];
    return;
end
p = prctileSafe(abs(vals),99);
if ~isfinite(p) || p <= 0, p = fallback; end
clim = [-p p];
end

function rgb = mapToRGB(M, cmap, clim)
M = double(M);
cmin = clim(1); cmax = clim(2);
if ~isfinite(cmin) || ~isfinite(cmax) || cmax <= cmin
    cmin = min(M(:)); cmax = max(M(:));
    if cmax <= cmin, cmax = cmin + 1; end
end
u = (M - cmin) / (cmax - cmin);
u = max(0,min(1,u));
idx = 1 + floor(u * (size(cmap,1)-1));
idx(~isfinite(idx)) = 1;
idx = max(1,min(size(cmap,1),idx));

rgb = zeros([size(M,1) size(M,2) 3],'single');
for k = 1:3
    tmp = cmap(idx,k);
    rgb(:,:,k) = reshape(single(tmp), size(M,1), size(M,2));
end
end

function cmap = blueWhiteRed(n)
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

function st = sliderStep(Z)
if Z <= 1
    st = [1 1];
else
    st = [1/(Z-1) min(10/(Z-1),1)];
end
end

function v = clamp(v, lo, hi)
v = max(lo, min(hi, v));
end

function plotNoData(ax, ttl)
cla(ax);
text(ax,0.5,0.5,'No data','HorizontalAlignment','center','Color',[0.92 0.92 0.94]);
set(ax,'Color',[0.10 0.10 0.11],'XColor',[0.74 0.74 0.78],'YColor',[0.74 0.74 0.78]);
title(ax,ttl,'Color',[0.92 0.92 0.94],'FontWeight','bold');
end

function saveAxesPNG(ax, fig, outFile)
tmp = figure('Visible','off');
ax2 = copyobj(ax, tmp);
set(ax2,'Units','normalized','Position',[0.08 0.08 0.84 0.84]);
set(tmp,'Color',get(fig,'Color'),'Position',[100 100 900 800]);
saveas(tmp, outFile);
close(tmp);
end

function q = prctileSafe(x, p)
x = double(x(:));
x = x(isfinite(x));
if isempty(x), q = NaN; return; end
x = sort(x);
if numel(x) == 1, q = x; return; end
t = (p/100) * (numel(x)-1) + 1;
i1 = floor(t);
i2 = ceil(t);
if i1 == i2
    q = x(i1);
else
    w = t - i1;
    q = (1-w)*x(i1) + w*x(i2);
end
end

function z = zscoreSafe(x)
x = double(x(:));
sd = std(x);
if ~isfinite(sd) || sd <= 0
    z = zeros(size(x));
else
    z = (x - mean(x)) / sd;
end
end

function r = corrScalarSafe(x, y)
x = double(x(:)); y = double(y(:));
x = x - mean(x); y = y - mean(y);
den = sqrt(sum(x.^2) * sum(y.^2));
if den <= 0 || ~isfinite(den)
    r = 0;
else
    r = sum(x.*y) / den;
end
end

function M = corrcoefSafe(X)
X = double(X);
if isempty(X), M = []; return; end
X = bsxfun(@minus, X, mean(X,1));
sd = std(X,0,1);
sd(sd <= 0 | ~isfinite(sd)) = 1;
X = bsxfun(@rdivide, X, sd);
M = (X' * X) / max(1,size(X,1)-1);
M = max(-1,min(1,M));
M(1:size(M,1)+1:end) = 1;
end

function P = partialCorrMatrixSafe(X)
R = corrcoefSafe(X);
if isempty(R), P = []; return; end
n = size(R,1);
lam = 1e-6;
Ri = pinv(R + lam*eye(n));
d = sqrt(abs(diag(Ri)));
den = d * d';
P = -Ri ./ max(den, eps);
P(1:size(P,1)+1:end) = 1;
P = max(-1,min(1,P));
end

function M = rvCoefficientMatrix(featCell)
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
        den = sqrt(trace(Sii * Sii) * trace(Sjj * Sjj));
        if den <= 0 || ~isfinite(den)
            rv = 0;
        else
            rv = num / den;
        end
        M(i,j) = rv;
        M(j,i) = rv;
    end
end
M = max(0,min(1,M));
M(1:size(M,1)+1:end) = 1;
end

function name = resolveRoiName(label, roiNames)
name = sprintf('ROI_%03d', label);
if isempty(roiNames), return; end

try
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

function out = maskedVectorToVol(vec, mask)
out = zeros(size(mask),'single');
id = find(mask(:));
n = min(numel(id), numel(vec));
out(id(1:n)) = single(vec(1:n));
end

function out = atanh_clip(M)
out = double(M);
out = min(0.999999, max(-0.999999, out));
out = atanh(out);
end

function a = nanmean_safe(X, dim)
if nargin < 2, dim = 1; end
mask = isfinite(X);
num = sum(X .* mask, dim);
den = sum(mask, dim);
a = num ./ max(den, 1);
a(den == 0) = NaN;
end

function a = nanstd_safe(X, flag, dim)
if nargin < 2, flag = 0; end
if nargin < 3, dim = 1; end
m = nanmean_safe(X,dim);
Xm = bsxfun(@minus, X, m);
Xm(~isfinite(X)) = NaN;
mask = isfinite(Xm);
num = nansum_local(Xm.^2, dim);
den = sum(mask, dim);
if flag == 0
    den = max(den-1, 1);
else
    den = max(den, 1);
end
a = sqrt(num ./ den);
a(sum(mask,dim) == 0) = NaN;
end

function a = nanvar_safe(X, flag, dim)
sd = nanstd_safe(X, flag, dim);
a = sd.^2;
end

function s = nansum_local(X, dim)
X(~isfinite(X)) = 0;
s = sum(X, dim);
end

function out = uniqueCellstr(c)
if isempty(c), out = {}; return; end
out = unique(c(:));
end

function tf = strcmpCellstr(c, s)
tf = false(numel(c),1);
for i = 1:numel(c)
    tf(i) = strcmp(char(c{i}), char(s));
end
end

function code = groupTestCode(dd)
lst = get(dd,'String');
idx = get(dd,'Value');
lbl = lower(strtrim(lst{idx}));
if ~isempty(strfind(lbl,'one-sample t'))
    code = 'one_sample_t';
elseif ~isempty(strfind(lbl,'one-sample wilcoxon'))
    code = 'one_sample_wilcoxon';
elseif ~isempty(strfind(lbl,'paired t'))
    code = 'paired_t';
elseif ~isempty(strfind(lbl,'paired wilcoxon'))
    code = 'paired_wilcoxon';
elseif ~isempty(strfind(lbl,'two-sample t'))
    code = 'two_sample_t';
else
    code = 'two_sample_wilcoxon';
end
end

function lst = groupTestList()
lst = { ...
    'One-sample t-test (vs 0)', ...
    'One-sample Wilcoxon (vs 0)', ...
    'Paired t-test', ...
    'Paired Wilcoxon', ...
    'Two-sample t-test', ...
    'Two-sample Wilcoxon'};
end

function lst = roiMethodList()
lst = { ...
    'Mean Pearson', ...
    'Mean Partial', ...
    'PC1 Pearson', ...
    'PC1 Partial', ...
    'RV coefficient'};
end

function code = roiMethodCode(lbl)
switch lower(strtrim(lbl))
    case 'mean pearson'
        code = 'mean_pearson';
    case 'mean partial'
        code = 'mean_partial';
    case 'pc1 pearson'
        code = 'pc1_pearson';
    case 'pc1 partial'
        code = 'pc1_partial';
    case 'rv coefficient'
        code = 'rv';
    otherwise
        code = 'mean_pearson';
end
end

function s = shortRoiName(s0)
s = char(s0);
if numel(s) > 28
    s = [s(1:25) '...'];
end
end

function val = getSafePopupValue(h)
try
    val = get(h,'Value');
catch
    val = 1;
end
end

function str = pairToString(x)
if isnumeric(x)
    str = num2str(x);
elseif ischar(x)
    str = x;
else
    try
        str = char(x);
    catch
        str = '';
    end
end
end

function logStack(opts, ME)
try
    st = ME.stack;
    for k = 1:numel(st)
        warnlog(opts, sprintf('[FC] at %s line %d (%s)', st(k).name, st(k).line, st(k).file));
    end
catch
end
end

function warnlog(opts, msg)
try
    if ~isempty(opts) && isstruct(opts) && isfield(opts,'logFcn') && ~isempty(opts.logFcn) ...
            && isa(opts.logFcn,'function_handle')
        opts.logFcn(msg);
    end
catch
end
end