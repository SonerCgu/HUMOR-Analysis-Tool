function fig = SCM_gui(PSC, bg, TR, par, baseline, nVolsOrig, varargin)
% SCM_gui - fUSI Studio SCM viewer/controller
% MATLAB 2017b + 2023b compatible, ASCII-safe.
%
% Corrected robust version for copy-paste use.
% Main fixes included:
%   1) Removed duplicate safeCdBack nested function conflict.
%   2) Robust uigetfileStartIn() that really opens in requested folder.
%   3) LOAD MASK starts in Masks/Mask/ROI/Registration before Visualization.
%   4) LOAD NEW UNDERLAY starts in Visualization first.
%   5) WARP FUNCTIONAL TO ATLAS starts in Registration2D/Registration first.
%   6) If par.exportPath/loadedPath points to Visualization, root is normalized one level up.
%   7) Atlas transform auto-detection accepts CoronalRegistration2D*.mat,
%      Transformation*.mat, source/atlas/histology-style filenames.
%   8) Load mask/bundle supports MAT/NIfTI and resizes safely to current SCM display.
%   9) Load underlay/bundle avoids stretching by validating/warping/resizing explicitly.
%  10) Open Video GUI passes selector path hints to video GUI through parVideo.
%
% Expected PSC dimensions:
%   [Y X T] or [Y X Z T]

%% ---------------- SAFETY ----------------
if nargin < 4 || isempty(par), par = struct(); end
if nargin < 5 || isempty(baseline), baseline = struct(); end
if nargin < 6 || isempty(nVolsOrig), nVolsOrig = []; end

assert(isscalar(TR) && isfinite(TR) && TR > 0, 'TR must be positive scalar');

d = ndims(PSC);
assert(d == 3 || d == 4, 'PSC must be [Y X T] or [Y X Z T]');

if d == 3
    [nY, nX, nT] = size(PSC);
    nZ = 1;
else
    [nY, nX, nZ, nT] = size(PSC);
end

if ~(isnumeric(nVolsOrig) && isscalar(nVolsOrig) && isfinite(nVolsOrig))
    varargin  = [{nVolsOrig} varargin];
    nVolsOrig = nT; %#ok<NASGU>
end

%% ---------------- OPTIONALS ----------------
fileLabel = '';
if ~isempty(varargin)
    lastArg = varargin{end};
    if ischar(lastArg) || (exist('isstring','builtin') && isstring(lastArg) && isscalar(lastArg))
        fileLabel = char(lastArg);
        varargin  = varargin(1:end-1);
    end
end
if isempty(fileLabel), fileLabel = 'SCM'; end
if exist('isstring','builtin') && isstring(fileLabel), fileLabel = char(fileLabel); end
if ~ischar(fileLabel), fileLabel = 'SCM'; end

passedMask = [];
passedMaskIsInclude = true;
if numel(varargin) >= 5
    passedMask = varargin{5};
end
if numel(varargin) >= 6
    v6 = varargin{6};
    isBoolScalar = (islogical(v6) && isscalar(v6)) || ...
        (isnumeric(v6) && isscalar(v6) && (v6 == 0 || v6 == 1));
    if ~isempty(passedMask) && isBoolScalar
        passedMaskIsInclude = logical(v6);
    end
end

%% ---------------- TIME / BASELINE MODE ----------------
tsec = (0:nT-1) * TR;
tmin = tsec / 60;

modeStr = 'sec';
if isstruct(baseline) && isfield(baseline,'mode') && ~isempty(baseline.mode)
    try
        modeStr = lower(char(baseline.mode));
    catch
        modeStr = 'sec';
    end
end
isVolMode = (strncmpi(modeStr, 'vol', 3) || strncmpi(modeStr, 'idx', 3));

baseStart0 = 30;
baseEnd0   = 240;
sigStart0  = 840;
sigEnd0    = 900;
if isstruct(baseline)
    if isfield(baseline,'start')    && isfiniteScalar(baseline.start),    baseStart0 = baseline.start; end
    if isfield(baseline,'end')      && isfiniteScalar(baseline.end),      baseEnd0   = baseline.end;   end
    if isfield(baseline,'sigStart') && isfiniteScalar(baseline.sigStart), sigStart0  = baseline.sigStart; end
    if isfield(baseline,'sigEnd')   && isfiniteScalar(baseline.sigEnd),   sigEnd0    = baseline.sigEnd;   end
end

%% ---------------- STATE ----------------
state = struct();
state.z   = max(1, round(nZ/2));
state.cax = [0 100];
state.alphaModOn = true;
state.modMin = 15;
state.modMax = 30;
state.signMode = 1;           % 1 positive, 2 negative magnitude, 3 signed
state.prevSignMode = 1;
state.lastSignedMap = zeros(nY, nX);
state.hoverMaxPts   = 1200;
state.hoverStride   = max(1, ceil(nT / state.hoverMaxPts));
state.hoverIdx      = 1:state.hoverStride:nT;
state.tminHover     = tmin(state.hoverIdx);
state.hoverMinDtSec = 0.06;
state.tcFixY = false;
state.tcFixX = false;
state.tcYLim = [0 100];
state.tcXLim = [0 max(tmin)];
state.isAtlasWarped = false;
state.atlasTransformFile = '';
state.lastAtlasTransformFile = '';
state.atlas2DWarpDirection = 'ask';   % 'as_saved' or 'inverse'
% Step-motor multi-slice atlas warp metadata
state.isStepMotorAtlasWarped = false;
state.stepMotorAtlasFolder = '';
state.stepMotorAtlasTransformFiles = {};
state.stepMotorAtlasSourceIdx = [];
state.stepMotorAtlasAtlasIdx = [];
state.isColorUnderlay = false;
state.regionLabelUnderlay = [];
state.regionColorLUT = [];
state.regionInfo = struct();
state.lastTcExportLabel = 'Target';
state.singleScmExportBusy = false;
state.lastSingleScmExportStampSec = -inf;
state.seriesExportBusy = false;
state.lastSeriesExportStampSec = -inf;

roi = struct();
roi.size = 5;
roi.colors = lines(12);
roi.isFrozen = false;
roi.nextId = 1;
roi.lastAddStamp = 0;
roi.lastHoverStamp = 0;
roi.lastHoverXY = [-inf -inf];
roi.sessionSetId = 0;
roi.lastExportLabel = 'Target';
roi.exportBusy = false;
roi.lastExportStampSec = -inf;

ROI_byZ = cell(1, nZ);
for zz = 1:nZ
    ROI_byZ{zz} = struct('id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
end
roiHandles = gobjects(0);
roiPlotPSC = gobjects(0);
roiTextHandles = gobjects(0);

uState = struct();
uState.mode       = 3;
uState.brightness = -0.04;
uState.contrast   = 1.10;
uState.gamma      = 0.95;
uState.conectSize = 18;
uState.conectLev  = 35;
MAX_CONSIZE = 300;
MAX_CONLEV  = 500;

origPSC = PSC;
origBG  = bg;
origPassedMask = passedMask;
startupAtlasNote = '';

% Auto-fix bad startup case: atlas/histology underlay with native PSC.
autoFixStartupAtlasUnderlayIfNeeded();

%% ---------------- MASK INIT ----------------
if isempty(passedMask)
    passedMask = deriveMaskFromUnderlay(bg, nY, nX, nZ, nT);
    passedMaskIsInclude = true;
end
mask2D = getMaskForCurrentSlice();

%% ---------------- FIGURE ----------------
figW0 = 1880;
figH0 = 1160;
scr = get(0, 'ScreenSize');
x0 = max(20, round((scr(3)-figW0)/2));
y0 = max(40, round((scr(4)-figH0)/2));

fig = figure( ...
    'Name', 'SCM Viewer', ...
    'Color', [0.05 0.05 0.05], ...
    'Position', [x0 y0 figW0 figH0], ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'NumberTitle', 'off');

set(fig, 'DefaultUicontrolFontName', 'Arial');
set(fig, 'DefaultUicontrolFontSize', 15);
try
    set(fig, 'WindowState', 'maximized');
catch
    scr2 = get(0, 'ScreenSize');
    set(fig, 'Position', [1 1 max(1200, scr2(3)-20) max(850, scr2(4)-80)]);
end

%% ---------------- COLORS ----------------
bgPanel   = [0.10 0.10 0.11];
bgTabOn   = [0.24 0.24 0.25];
bgTabOff  = [0.14 0.14 0.15];
bgEdit    = [0.18 0.18 0.19];
bgEditDis = [0.22 0.22 0.23];
fgMain    = [0.97 0.97 0.98];
fgSub     = [0.82 0.90 1.00];
fgImp     = [1.00 0.60 0.60];
colBtnPrimary = [0.24 0.52 0.30];
colBtnExport  = [0.20 0.38 0.62];
colBtnNeutral = [0.28 0.28 0.30];
colBtnDanger  = [0.72 0.18 0.18];

%% ---------------- MAIN IMAGE AXIS ----------------
ax = axes('Parent', fig, 'Units', 'pixels');
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
hold(ax, 'on');

bg2 = getBg2DForSlice(state.z);
hBG = image(ax, renderUnderlayRGB(bg2));
hOV = imagesc(ax, zeros(nY, nX));
set(hOV, 'AlphaData', zeros(nY, nX));

cmapNames = { ...
    'blackbdy_iso', ...
    'winter_brain_fsl', ...
    'signed_blackbdy_winter', ...
    'hot', 'parula', 'turbo', 'jet', 'gray', 'bone', 'copper', 'pink', ...
    'viridis', 'plasma', 'magma', 'inferno'};
setOverlayColormap('blackbdy_iso');
caxis(ax, state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.Label.FontWeight = 'bold';
cb.FontSize = 12;
set(cb, 'Units', 'pixels');

hLiveRect = rectangle(ax, 'Position', [1 1 1 1], ...
    'EdgeColor', [0 1 0], 'LineWidth', 2, 'Visible', 'off');

txtSliceOverlay = text(ax, 0.985, 0.985, '', ...
    'Units', 'normalized', 'Color', [0.86 0.93 1.00], ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
    'Interpreter', 'none', 'Visible', 'off');
hold(ax, 'off');

txtTitle = uicontrol(fig, 'Style', 'text', 'String', makeFullTitle(fileLabel), ...
    'Units', 'pixels', 'ForegroundColor', [0.95 0.95 0.95], ...
    'BackgroundColor', [0.05 0.05 0.05], 'FontSize', 16, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'center');

%% ---------------- TIMECOURSE AXIS ----------------
axTC = axes('Parent', fig, 'Units', 'pixels', ...
    'Color', [0.05 0.05 0.05], 'XColor', 'w', 'YColor', 'w', ...
    'LineWidth', 1.2, 'Box', 'on', 'Layer', 'top');
hold(axTC, 'on');
grid(axTC, 'on');
axTC.FontSize = 12;
try
    axTC.GridAlpha = 0.18;
    axTC.MinorGridAlpha = 0.10;
    axTC.XMinorGrid = 'off';
    axTC.YMinorGrid = 'off';
catch
end
xlabel(axTC, 'Time (min)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
ylTC = ylabel(axTC, 'PSC (%)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
try
    set(ylTC, 'Units', 'normalized', 'Position', [-0.022 0.50 0], 'Clipping', 'off');
catch
end

hBasePatch = patch(axTC, [0 0 0 0], [0 0 0 0], [1 0.2 0.2], ...
    'FaceAlpha', 0.16, 'EdgeColor', 'none', 'Visible', 'off');
hSigPatch = patch(axTC, [0 0 0 0], [0 0 0 0], [1 0.6 0.15], ...
    'FaceAlpha', 0.16, 'EdgeColor', 'none', 'Visible', 'off');
hBaseTxt = text(axTC, 0, 0, '', 'Color', [1.00 0.35 0.35], ...
    'FontSize', 11, 'FontWeight', 'bold', 'Visible', 'off');
hSigTxt = text(axTC, 0, 0, '', 'Color', [1.00 0.75 0.35], ...
    'FontSize', 11, 'FontWeight', 'bold', 'Visible', 'off');
hLivePSC = plot(axTC, state.tminHover, nan(1, numel(state.tminHover)), ':', 'LineWidth', 3.0);
hLivePSC.Color = [1.00 0.60 0.10];
hLivePSC.Visible = 'off';
hRoiCoordTxt = text(axTC, 0.99, 0.98, '', ...
    'Units', 'normalized', 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', 'Color', [0.92 0.92 0.92], ...
    'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none', 'Visible', 'off');

%% ---------------- HIDDEN SLICE SLIDER ----------------
slZ = uicontrol(fig, 'Style', 'slider', 'Units', 'pixels', ...
    'Min', 1, 'Max', max(1,nZ), 'Value', nZ-state.z+1, ...
    'SliderStep', [1/max(1,nZ-1) 5/max(1,nZ-1)], ...
    'Callback', @sliceChanged, 'Visible', 'off', 'Enable', 'off');
txtZ = uicontrol(fig, 'Style', 'text', 'Units', 'pixels', 'String', '', ...
    'ForegroundColor', [0.85 0.9 1], 'BackgroundColor', get(fig,'Color'), ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 13, ...
    'Visible', 'off');

%% ---------------- RIGHT PANEL ----------------
controlsPanel = uipanel('Parent', fig, 'Title', 'SCM Controls', ...
    'Units', 'pixels', 'BackgroundColor', bgPanel, 'ForegroundColor', fgMain, ...
    'FontSize', 17, 'FontWeight', 'bold');

tabBar = uipanel('Parent', controlsPanel, 'Units', 'pixels', ...
    'BorderType', 'none', 'BackgroundColor', bgPanel);
btnTabOverlay = uicontrol(tabBar, 'Style', 'togglebutton', 'String', 'Overlay', ...
    'Units', 'pixels', 'Callback', @(~,~)switchTab('overlay'), ...
    'BackgroundColor', bgTabOn, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', 14, 'FontWeight', 'bold', 'Value', 1);
btnTabUnderlay = uicontrol(tabBar, 'Style', 'togglebutton', 'String', 'Underlay', ...
    'Units', 'pixels', 'Callback', @(~,~)switchTab('underlay'), ...
    'BackgroundColor', bgTabOff, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', 14, 'FontWeight', 'bold', 'Value', 0);

pOverlay = uipanel('Parent', controlsPanel, 'Units', 'pixels', ...
    'BorderType', 'none', 'BackgroundColor', bgPanel);
pUnderlay = uipanel('Parent', controlsPanel, 'Units', 'pixels', ...
    'BorderType', 'none', 'BackgroundColor', bgPanel, 'Visible', 'off');
info1 = uicontrol(controlsPanel, 'Style', 'text', 'String', '', ...
    'Units', 'pixels', 'ForegroundColor', fgSub, 'BackgroundColor', bgPanel, ...
    'HorizontalAlignment', 'left', 'FontName', 'Arial', 'FontSize', 12, 'FontWeight', 'bold');

pad = 18; rowH = 36; gap = 9; sliderH = 20; groupGap = 15; wideBtnH = 38; smallBtnH = 34;

mkLbl = @(pp,s) uicontrol(pp, 'Style', 'text', 'String', s, 'Units', 'pixels', ...
    'ForegroundColor', fgMain, 'BackgroundColor', bgPanel, 'HorizontalAlignment', 'left', ...
    'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
mkLblImp = @(pp,s) uicontrol(pp, 'Style', 'text', 'String', s, 'Units', 'pixels', ...
    'ForegroundColor', fgImp, 'BackgroundColor', bgPanel, 'HorizontalAlignment', 'left', ...
    'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
mkValBox = @(pp,s) uicontrol(pp, 'Style', 'edit', 'String', s, 'Units', 'pixels', ...
    'BackgroundColor', bgEditDis, 'ForegroundColor', fgMain, 'HorizontalAlignment', 'center', ...
    'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold', 'Enable', 'inactive');
mkEdit = @(pp,s,cbk) uicontrol(pp, 'Style', 'edit', 'String', s, 'Units', 'pixels', ...
    'BackgroundColor', bgEdit, 'ForegroundColor', fgMain, 'FontName', 'Arial', ...
    'FontSize', 13, 'FontWeight', 'bold', 'Callback', cbk);
mkSlider = @(pp,minv,maxv,val,cbk) uicontrol(pp, 'Style', 'slider', 'Units', 'pixels', ...
    'Min', minv, 'Max', maxv, 'Value', val, 'Callback', cbk);
mkPopup = @(pp,choices,val,cbk) uicontrol(pp, 'Style', 'popupmenu', 'String', choices, ...
    'Value', val, 'Units', 'pixels', 'Callback', cbk, 'BackgroundColor', bgEdit, ...
    'ForegroundColor', fgMain, 'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
mkChk = @(pp,s,val,cbk) uicontrol(pp, 'Style', 'checkbox', 'String', s, 'Units', 'pixels', ...
    'Value', val, 'Callback', cbk, 'BackgroundColor', bgPanel, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', 13, 'FontWeight', 'bold');
mkBtn = @(pp,lbl,cbk,bgcol,fs) uicontrol(pp, 'Style', 'pushbutton', 'String', lbl, ...
    'Units', 'pixels', 'Callback', cbk, 'BackgroundColor', bgcol, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', fs, 'FontWeight', 'bold');

%% ---------------- Overlay controls ----------------
lblROIsz = mkLbl(pOverlay, 'ROI size (px)');
slROI = mkSlider(pOverlay, 1, 220, roi.size, @(~,~)setROIsize());
txtROIsz = mkEdit(pOverlay, sprintf('%d', roi.size), @onRoiSizeEdited);
set(txtROIsz, 'TooltipString', 'Type ROI size in pixels, then press Enter.');

lblRoiXY = mkLbl(pOverlay, 'Add ROI by center (x y)');
ebRoiXY = mkEdit(pOverlay, '', @roiXYNoop);
set(ebRoiXY, 'TooltipString', 'Type x y, for example 120 80 or 120,80, then press Enter.');
set(ebRoiXY, 'KeyPressFcn', @roiXYKey);
btnRoiAddXY = mkBtn(pOverlay, 'ADD ROI', @addRoiFromXY, colBtnNeutral, 12);

lblBase = mkLblImp(pOverlay, 'Baseline window (s)');
ebBase = mkEdit(pOverlay, sprintf('%g-%g', baseStart0, baseEnd0), @onWindowEdited);
set(ebBase, 'ForegroundColor', [1.00 0.35 0.35]);
lblSig = mkLblImp(pOverlay, 'Signal window (s)');
ebSig = mkEdit(pOverlay, sprintf('%g-%g', sigStart0, sigEnd0), @onWindowEdited);
set(ebSig, 'ForegroundColor', [1.00 0.35 0.35]);

lblAlpha = mkLbl(pOverlay, 'Overlay alpha (%)');
slAlpha = mkSlider(pOverlay, 0, 100, 100, @updateView);
txtAlpha = mkValBox(pOverlay, '100');
lblThr = mkLblImp(pOverlay, 'Threshold (abs %)');
ebThr = mkEdit(pOverlay, '0', @updateView);
set(ebThr, 'ForegroundColor', [1.00 0.35 0.35]);
lblCax = mkLblImp(pOverlay, 'Display range (min max)');
ebCax = mkEdit(pOverlay, '0 100', @updateView);
set(ebCax, 'ForegroundColor', [1.00 0.35 0.35]);
lblSignMode = mkLblImp(pOverlay, 'Signal sign display');
popSignMode = mkPopup(pOverlay, {'Positive only','Negative only','Positive + Negative'}, state.signMode, @updateView);
lblAlphaMod = mkLblImp(pOverlay, 'Alpha modulation');
cbAlphaMod = mkChk(pOverlay, 'Alpha modulate by |SCM|', double(state.alphaModOn), @alphaModToggled);
lblModMin = mkLblImp(pOverlay, 'Mod Min (abs %)');
ebModMin = mkEdit(pOverlay, '15', @updateView);
set(ebModMin, 'ForegroundColor', [1.00 0.35 0.35]);
lblModMax = mkLblImp(pOverlay, 'Mod Max (abs %)');
ebModMax = mkEdit(pOverlay, '30', @updateView);
set(ebModMax, 'ForegroundColor', [1.00 0.35 0.35]);
lblMap = mkLbl(pOverlay, 'Colormap');
popMap = mkPopup(pOverlay, cmapNames, 1, @updateView);
lblSigma = mkLblImp(pOverlay, 'SCM smoothing sigma');
ebSigma = mkEdit(pOverlay, '1', @computeSCM);
set(ebSigma, 'ForegroundColor', [1.00 0.35 0.35]);

btnRoiExport   = mkBtn(pOverlay, 'EXPORT ROIs (TXT)', @exportROIsCB, colBtnExport, 13);
btnScmExport   = mkBtn(pOverlay, 'EXPORT SCM IMAGE', @exportSCMImageCB, colBtnExport, 13);
btnTcPng       = mkBtn(pOverlay, 'EXPORT TIME COURSE PNG', @exportTimecoursePngCB, colBtnExport, 13);
btnScmSeries   = mkBtn(pOverlay, 'EXPORT PPT', @exportScmSeries1minCB, colBtnExport, 12);
btnGroupBundle = mkBtn(pOverlay, 'EXPORT SCM BUNDLE', @exportForGroupAnalysisCB, colBtnPrimary, 12);
btnOpenGroupBundle = mkBtn(pOverlay, 'OPEN GROUP BUNDLE', @openGroupBundleCB, colBtnPrimary, 12);
btnUnfreeze    = mkBtn(pOverlay, 'UNFREEZE HOVER', @unfreezeHover, colBtnNeutral, 12);

%% ---------------- Underlay controls ----------------
lblUnderMode = mkLbl(pUnderlay, 'Underlay view');
popUnder = mkPopup(pUnderlay, { ...
    '1) Legacy (mat2gray)', ...
    '2) Robust clip (1..99%)', ...
    '3) VideoGUI robust (0.5..99.5%)', ...
    '4) Vessel enhance (conectSize/Lev)'}, uState.mode, @underlayModeChanged);
lblBri = mkLbl(pUnderlay, 'Underlay brightness');
slBri = mkSlider(pUnderlay, -0.80, 0.80, uState.brightness, @underlaySliderChanged);
txtBri = mkValBox(pUnderlay, sprintf('%.2f', uState.brightness));
lblCon = mkLbl(pUnderlay, 'Underlay contrast');
slCon = mkSlider(pUnderlay, 0.10, 5.00, uState.contrast, @underlaySliderChanged);
txtCon = mkValBox(pUnderlay, sprintf('%.2f', uState.contrast));
lblGam = mkLbl(pUnderlay, 'Underlay gamma');
slGam = mkSlider(pUnderlay, 0.20, 4.00, uState.gamma, @underlaySliderChanged);
txtGam = mkValBox(pUnderlay, sprintf('%.2f', uState.gamma));
lblVsz = mkLbl(pUnderlay, 'Vessel conectSize (px)');
slVsz = mkSlider(pUnderlay, 0, MAX_CONSIZE, uState.conectSize, @underlaySliderChanged);
set(slVsz, 'SliderStep', [1/max(1,MAX_CONSIZE) 10/max(1,MAX_CONSIZE)]);
txtVsz = mkValBox(pUnderlay, sprintf('%d', uState.conectSize));
lblVlv = mkLbl(pUnderlay, sprintf('Vessel conectLev (0..%d)', MAX_CONLEV));
slVlv = mkSlider(pUnderlay, 0, MAX_CONLEV, uState.conectLev, @underlaySliderChanged);
set(slVlv, 'SliderStep', [1/max(1,MAX_CONLEV) 10/max(1,MAX_CONLEV)]);
txtVlv = mkValBox(pUnderlay, sprintf('%d', uState.conectLev));

btnLoadUnder = mkBtn(pUnderlay, 'LOAD NEW UNDERLAY', @loadNewUnderlayCB, colBtnNeutral, 12);
btnWarpAtlas = mkBtn(pUnderlay, 'WARP FUNCTIONAL TO ATLAS', @warpFunctionalToAtlasCB, colBtnExport, 12);
btnResetWarp = mkBtn(pUnderlay, 'RESET TO NATIVE', @resetWarpToNativeCB, colBtnNeutral, 12);

%% ---------------- Time-course axis controls ----------------
tcAxisBar = uipanel('Parent', fig, 'Units', 'pixels', 'BorderType', 'none', ...
    'BackgroundColor', [0.05 0.05 0.05]);
cbTcFixY = uicontrol(tcAxisBar, 'Style', 'checkbox', 'String', 'Fix Y', ...
    'Units', 'pixels', 'Value', double(state.tcFixY), 'Callback', @tcAxisModeChanged, ...
    'BackgroundColor', [0.05 0.05 0.05], 'ForegroundColor', [0.95 0.95 0.95], ...
    'FontName', 'Arial', 'FontSize', 11, 'FontWeight', 'bold');
ebTcYLim = uicontrol(tcAxisBar, 'Style', 'edit', 'String', sprintf('%g %g', state.tcYLim(1), state.tcYLim(2)), ...
    'Units', 'pixels', 'BackgroundColor', bgEdit, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', 11, 'FontWeight', 'bold', 'Callback', @tcAxisModeChanged);
btnTcYFromCax = uicontrol(tcAxisBar, 'Style', 'pushbutton', 'String', 'Y = CAX', ...
    'Units', 'pixels', 'Callback', @tcYFromCax, 'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', fgMain, 'FontName', 'Arial', 'FontSize', 10, 'FontWeight', 'bold');
cbTcFixX = uicontrol(tcAxisBar, 'Style', 'checkbox', 'String', 'Fix X', ...
    'Units', 'pixels', 'Value', double(state.tcFixX), 'Callback', @tcAxisModeChanged, ...
    'BackgroundColor', [0.05 0.05 0.05], 'ForegroundColor', [0.95 0.95 0.95], ...
    'FontName', 'Arial', 'FontSize', 11, 'FontWeight', 'bold');
ebTcXLim = uicontrol(tcAxisBar, 'Style', 'edit', 'String', sprintf('%g %g', state.tcXLim(1), state.tcXLim(2)), ...
    'Units', 'pixels', 'BackgroundColor', bgEdit, 'ForegroundColor', fgMain, ...
    'FontName', 'Arial', 'FontSize', 11, 'FontWeight', 'bold', 'Callback', @tcAxisModeChanged);
btnTcXAll = uicontrol(tcAxisBar, 'Style', 'pushbutton', 'String', 'X = ALL', ...
    'Units', 'pixels', 'Callback', @tcXAll, 'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', fgMain, 'FontName', 'Arial', 'FontSize', 10, 'FontWeight', 'bold');

%% ---------------- Bottom buttons ----------------
btnCompute = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Compute SCM', ...
    'Units', 'pixels', 'Callback', @computeSCM, 'BackgroundColor', colBtnPrimary, ...
    'ForegroundColor', 'w', 'FontSize', 15, 'FontWeight', 'bold');
btnMaskQuick = uicontrol(fig, 'Style', 'pushbutton', 'String', 'LOAD MASK', ...
    'Units', 'pixels', 'Callback', @loadMaskCB, 'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', 'w', 'FontSize', 15, 'FontWeight', 'bold');
btnOpenVid = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Open Video GUI', ...
    'Units', 'pixels', 'Callback', @openVideo, 'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', 'w', 'FontSize', 15, 'FontWeight', 'bold');
btnHelp = uicontrol(fig, 'Style', 'pushbutton', 'String', 'HELP', ...
    'Units', 'pixels', 'Callback', @showHelp, 'BackgroundColor', colBtnExport, ...
    'ForegroundColor', 'w', 'FontSize', 15, 'FontWeight', 'bold');
btnClose = uicontrol(fig, 'Style', 'pushbutton', 'String', 'CLOSE', ...
    'Units', 'pixels', 'Callback', @(~,~)close(fig), 'BackgroundColor', colBtnDanger, ...
    'ForegroundColor', 'w', 'FontSize', 15, 'FontWeight', 'bold');

%% ---------------- CALLBACKS / INIT ----------------
set(fig, 'WindowButtonMotionFcn', @mouseMove);
set(fig, 'WindowButtonDownFcn', @mouseClick);
set(fig, 'WindowScrollWheelFcn', @mouseScroll);
set(fig, 'ResizeFcn', @(~,~)layoutUI());

alphaModToggled();
updateUnderlayControlsEnable();
updateInfoLines();
layoutUI();
tcAxisModeChanged();
updateSliceIndicators();
computeSCM();
redrawROIsForCurrentSlice();

if ~isempty(startupAtlasNote)
    try
        set(info1, 'String', shortenPath(startupAtlasNote, 110), 'TooltipString', startupAtlasNote);
    catch
    end
end

%% ==========================================================
% UI LAYOUT
%% ==========================================================
function switchTab(which)
    which = lower(char(which));
    if strcmp(which, 'overlay')
        set(pOverlay, 'Visible', 'on');
        set(pUnderlay, 'Visible', 'off');
        set(btnTabOverlay, 'Value', 1, 'BackgroundColor', bgTabOn, 'ForegroundColor', fgMain);
        set(btnTabUnderlay, 'Value', 0, 'BackgroundColor', bgTabOff, 'ForegroundColor', [0.88 0.88 0.90]);
    else
        set(pOverlay, 'Visible', 'off');
        set(pUnderlay, 'Visible', 'on');
        set(btnTabOverlay, 'Value', 0, 'BackgroundColor', bgTabOff, 'ForegroundColor', [0.88 0.88 0.90]);
        set(btnTabUnderlay, 'Value', 1, 'BackgroundColor', bgTabOn, 'ForegroundColor', fgMain);
    end
end

function layoutUI()
    if ~isgraphics(fig), return; end
    pos = get(fig, 'Position');
    W = pos(3); Hh = pos(4);

    leftM = 64; rightM = 36; topM = 58; botM = 60; gapX = 36; gapY = 24;
    panelW = min(760, max(520, round(0.36 * W)));
    if Hh < 980
        btnH = 46; btnGap = 8;
    else
        btnH = 54; btnGap = 12;
    end

    yClose = 28; yHelp = yClose;
    yOpen = yClose + btnH + btnGap;
    yMask = yOpen + btnH + btnGap;
    yComp = yMask + btnH + btnGap;
    buttonsTop = yComp + btnH;

    panelX = W - rightM - panelW;
    panelY = buttonsTop + 14;
    panelH = max(320, Hh - panelY - topM);
    set(controlsPanel, 'Position', [panelX panelY panelW panelH]);
    set(btnCompute,   'Position', [panelX yComp panelW btnH]);
    set(btnMaskQuick, 'Position', [panelX yMask panelW btnH]);
    set(btnOpenVid,   'Position', [panelX yOpen panelW btnH]);
    halfW = floor((panelW - 14) / 2);
    set(btnHelp,  'Position', [panelX yHelp halfW btnH]);
    set(btnClose, 'Position', [panelX + halfW + 14 yClose halfW btnH]);

    tcCtrlH = 30;
    tcCtrlGap = 20;
    tcHfull = min(250, max(190, round(0.24 * Hh)));
    tcPlotH = max(120, tcHfull - tcCtrlH - tcCtrlGap);
    cbW = 18; cbGap = 10; imgRightGap = 26;
    axH = max(340, Hh - botM - tcHfull - gapY - topM);
    axX = leftM;
    leftW = max(360, panelX - axX - gapX - cbW - cbGap - imgRightGap);
    axY = botM + tcHfull + gapY;
    set(ax, 'Position', [axX axY leftW axH]);
    cbH = round(0.84 * axH); cbY = axY + round(0.08 * axH); cbX = axX + leftW + cbGap;
    try, set(cb, 'Position', [cbX cbY cbW cbH]); catch, end
    tcLeftPad = 8;
    set(axTC, 'Position', [axX + tcLeftPad, botM + tcCtrlH + tcCtrlGap, leftW - tcLeftPad, tcPlotH]);
    set(tcAxisBar, 'Position', [axX + tcLeftPad, botM - 6, leftW - tcLeftPad, tcCtrlH]);

    x = 0; y = 4; hh = tcCtrlH - 8;
    wChk = 62; wEdit = 95; wBtn = 72; g = 8;
    set(cbTcFixY, 'Position', [x+4 y wChk hh]); x = x + wChk + g;
    set(ebTcYLim, 'Position', [x y wEdit hh]); x = x + wEdit + g;
    set(btnTcYFromCax, 'Position', [x y wBtn hh]); x = x + wBtn + 20;
    set(cbTcFixX, 'Position', [x y wChk hh]); x = x + wChk + g;
    set(ebTcXLim, 'Position', [x y wEdit hh]); x = x + wEdit + g;
    set(btnTcXAll, 'Position', [x y wBtn hh]);

    set(slZ, 'Visible', 'off', 'Enable', 'off');
    set(txtZ, 'Visible', 'off');
    set(txtTitle, 'Position', [axX axY + axH + 10 leftW + cbGap + cbW 28], ...
        'String', makeFullTitle(fileLabel), 'Visible', 'on');
    try
        set(ylTC, 'Units', 'normalized', 'Position', [-0.022 0.50 0], 'Clipping', 'off');
    catch
    end

    tabH = 42; statusH = 58; titlePad = 30;
    set(tabBar, 'Position', [12 panelH - tabH - titlePad panelW - 24 tabH]);
    btnW = floor((panelW - 24 - 10) / 2);
    set(btnTabOverlay, 'Position', [0 0 btnW tabH]);
    set(btnTabUnderlay, 'Position', [btnW + 10 0 btnW tabH]);
    contentX = 12; contentY = 14 + statusH;
    contentW = panelW - 24;
    contentH = panelH - tabH - titlePad - statusH - 20;
    set(pOverlay, 'Position', [contentX contentY contentW contentH]);
    set(pUnderlay, 'Position', [contentX contentY contentW contentH]);
    set(info1, 'Position', [contentX 8 contentW statusH]);
    layoutOverlay(contentW, contentH);
    layoutUnder(contentW, contentH);
end

function layoutOverlay(w, h)
    compact = (h < 700);
    if compact
        rowHLoc = 30; gapLoc = 5; groupGapLoc = 8; sliderHLoc = 16; wideBtnHLoc = 32; smallBtnHLoc = 30;
    else
        rowHLoc = rowH; gapLoc = gap; groupGapLoc = groupGap; sliderHLoc = sliderH; wideBtnHLoc = wideBtnH; smallBtnHLoc = smallBtnH;
    end
    xLabel = pad; wLabel = 240; wVal = 120; xVal = w - pad - wVal;
    xCtrl = xLabel + wLabel + 16; wCtrl = max(90, xVal - xCtrl - 12);
    y = h - rowHLoc;

    set(lblROIsz, 'Position', [xLabel y wLabel rowHLoc]);
    set(slROI, 'Position', [xCtrl y + round((rowHLoc-sliderHLoc)/2) wCtrl sliderHLoc]);
    set(txtROIsz, 'Position', [xVal y wVal rowHLoc]);
    y = y - (rowHLoc + gapLoc);

    set(lblRoiXY, 'Position', [xLabel y wLabel rowHLoc]);
    set(ebRoiXY, 'Position', [xCtrl y wCtrl rowHLoc]);
    set(btnRoiAddXY, 'Position', [xVal y wVal rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);

    setRowEditOverlay(lblBase, ebBase); setRowEditOverlay(lblSig, ebSig);
    y = y + (gapLoc - groupGapLoc);
    setRowSliderOverlay(lblAlpha, slAlpha, txtAlpha);
    setRowEditOverlay(lblThr, ebThr);
    setRowEditOverlay(lblCax, ebCax);
    set(lblSignMode, 'Position', [xLabel y wLabel rowHLoc]);
    set(popSignMode, 'Position', [xCtrl y (w-xCtrl-pad) rowHLoc]);
    y = y - (rowHLoc + gapLoc);
    set(lblAlphaMod, 'Position', [xLabel y wLabel rowHLoc]);
    set(cbAlphaMod, 'Position', [xCtrl y (w-xCtrl-pad) rowHLoc]);
    y = y - (rowHLoc + gapLoc);
    setRowEditOverlay(lblModMin, ebModMin);
    setRowEditOverlay(lblModMax, ebModMax);
    set(lblMap, 'Position', [xLabel y wLabel rowHLoc]);
    set(popMap, 'Position', [xCtrl y (w-xCtrl-pad) rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);
    setRowEditOverlay(lblSigma, ebSigma);
    y = y - 2;
btnW2 = floor((w - 2*pad - 10) / 2);

set(btnRoiExport, 'Position', [xLabel y btnW2 wideBtnHLoc]);
set(btnScmExport, 'Position', [xLabel + btnW2 + 10 y btnW2 wideBtnHLoc]);
y = y - (wideBtnHLoc + gapLoc);

set(btnTcPng, 'Position', [xLabel y btnW2 wideBtnHLoc]);
set(btnScmSeries, 'Position', [xLabel + btnW2 + 10 y btnW2 wideBtnHLoc]);
y = y - (wideBtnHLoc + gapLoc);

set(btnGroupBundle, 'Position', [xLabel y btnW2 wideBtnHLoc]);
set(btnOpenGroupBundle, 'Position', [xLabel + btnW2 + 10 y btnW2 wideBtnHLoc]);
y = y - (wideBtnHLoc + groupGapLoc);

set(btnUnfreeze, 'Position', [xLabel y (w-2*pad) smallBtnHLoc]);

    function setRowEditOverlay(lbl, ed)
        set(lbl, 'Position', [xLabel y wLabel rowHLoc]);
        set(ed, 'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end
    function setRowSliderOverlay(lbl, sl, valbox)
        set(lbl, 'Position', [xLabel y wLabel rowHLoc]);
        set(sl, 'Position', [xCtrl y + round((rowHLoc-sliderHLoc)/2) wCtrl sliderHLoc]);
        set(valbox, 'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end
end

function layoutUnder(w, h)
    compact = (h < 700);
    if compact
        rowHLoc = 30; gapLoc = 5; groupGapLoc = 8; sliderHLoc = 16; wideBtnHLoc = 32;
    else
        rowHLoc = rowH; gapLoc = gap; groupGapLoc = groupGap; sliderHLoc = sliderH; wideBtnHLoc = wideBtnH;
    end
    xLabel = pad; wLabel = 250; wVal = 120; xVal = w - pad - wVal;
    xCtrl = xLabel + wLabel + 16; wCtrl = max(90, xVal - xCtrl - 12);
    y = h - rowHLoc;
    set(lblUnderMode, 'Position', [xLabel y wLabel rowHLoc]);
    set(popUnder, 'Position', [xCtrl y (w-xCtrl-pad) rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);
    setRowSliderUnder(lblBri, slBri, txtBri);
    setRowSliderUnder(lblCon, slCon, txtCon);
    setRowSliderUnder(lblGam, slGam, txtGam);
    setRowSliderUnder(lblVsz, slVsz, txtVsz);
    setRowSliderUnder(lblVlv, slVlv, txtVlv);
    y = y - 2;
    set(btnLoadUnder, 'Position', [xLabel y (w-2*pad) wideBtnHLoc]);
    y = y - (wideBtnHLoc + gapLoc);
    set(btnWarpAtlas, 'Position', [xLabel y (w-2*pad) wideBtnHLoc]);
    y = y - (wideBtnHLoc + gapLoc);
    set(btnResetWarp, 'Position', [xLabel y (w-2*pad) wideBtnHLoc]);

    function setRowSliderUnder(lbl, sl, valbox)
        set(lbl, 'Position', [xLabel y wLabel rowHLoc]);
        set(sl, 'Position', [xCtrl y + round((rowHLoc-sliderHLoc)/2) wCtrl sliderHLoc]);
        set(valbox, 'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end
end

%% ==========================================================
% CALLBACKS
%% ==========================================================
function onWindowEdited(~,~), computeSCM(); end
function roiXYNoop(~,~), end

function sliceChanged(~,~)
    zNew = round(nZ - get(slZ, 'Value') + 1);
    state.z = clamp(zNew, 1, nZ);
    set(slZ, 'Value', nZ - state.z + 1);
    mask2D = getMaskForCurrentSlice();
    set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    roi.isFrozen = false;
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    updateSliceIndicators(); updateInfoLines(); computeSCM(); redrawROIsForCurrentSlice();
end

function unfreezeHover(~,~)
    roi.isFrozen = false;
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    applyTimecourseAxisMode();
end

function setROIsize()
    roi.size = max(1, round(get(slROI, 'Value')));
    set(txtROIsz, 'String', sprintf('%d', roi.size));
    applyTimecourseAxisMode();
end

function onRoiSizeEdited(~,~)
    v = str2double(strtrim(getStr(txtROIsz)));
    if ~isfinite(v), v = roi.size; end
    roi.size = max(1, min(220, round(v)));
    set(slROI, 'Value', roi.size);
    set(txtROIsz, 'String', sprintf('%d', roi.size));
end

function roiXYKey(~, evt)
    try
        if isfield(evt,'Key') && (strcmpi(evt.Key,'return') || strcmpi(evt.Key,'enter'))
            addRoiFromXY();
        end
    catch
    end
end

function mouseMove(~,~)
    if roi.isFrozen || ~isPointerOverImageAxis(), return; end
    cp = get(ax, 'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));
    if x < 1 || x > nX || ypix < 1 || ypix > nY
        set(hLiveRect, 'Visible', 'off');
        set(hLivePSC, 'Visible', 'off');
        set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
        applyTimecourseAxisMode();
        return;
    end
    if x == roi.lastHoverXY(1) && ypix == roi.lastHoverXY(2), return; end
    roi.lastHoverXY = [x ypix];
    [x1,x2,y1,y2] = roiBounds(x, ypix);
    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1))+1, :);
    set(hLiveRect, 'Position', [x1 y1 x2-x1+1 y2-y1+1], 'EdgeColor', col, 'Visible', 'on');
    set(hRoiCoordTxt, 'String', sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1, x2, y1, y2), 'Visible', 'on');
    tNow = now;
    if roi.lastHoverStamp ~= 0 && (tNow - roi.lastHoverStamp)*86400 < state.hoverMinDtSec, return; end
    roi.lastHoverStamp = tNow;
    tc = computeRoiPSC_idx(state.z, x1, x2, y1, y2, state.hoverIdx);
    if isempty(tc) || numel(tc) ~= numel(state.tminHover)
        set(hLivePSC, 'Visible', 'off');
        return;
    end
    set(hLivePSC, 'XData', state.tminHover, 'YData', tc, 'Visible', 'on');
    applyTimecourseAxisMode();
end

function mouseClick(~,~)
    if ~isPointerOverImageAxis(), return; end
    cp = get(ax, 'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));
    if x < 1 || x > nX || ypix < 1 || ypix > nY, return; end
    type = get(fig, 'SelectionType');
    if strcmp(type, 'normal')
        addRoiAtCenter(x, ypix);
    elseif strcmp(type, 'alt')
        removeNearestRoi(x, ypix);
    end
end

function mouseScroll(~, evt)
    if nZ <= 1 || ~isPointerOverImageAxis(), return; end
    dz = sign(evt.VerticalScrollCount);
    if dz == 0, return; end
    state.z = clamp(state.z + dz, 1, nZ);
    mask2D = getMaskForCurrentSlice();
    set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    roi.isFrozen = false;
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    updateSliceIndicators(); updateInfoLines(); computeSCM(); redrawROIsForCurrentSlice();
end

function addRoiFromXY(~,~)
    tNow = now;
    if roi.lastAddStamp ~= 0 && (tNow - roi.lastAddStamp) * 86400 < 0.20, return; end
    roi.lastAddStamp = tNow;
    s = strtrim(getStr(ebRoiXY));
    if isempty(s), return; end
    s = strrep(s, ',', ' ');
    v = sscanf(s, '%f');
    if numel(v) < 2 || ~isfinite(v(1)) || ~isfinite(v(2))
        warndlg('Enter ROI center as: x y   for example 120 80 or 120,80', 'Add ROI');
        return;
    end
    addRoiAtCenter(round(v(1)), round(v(2)));
end

function addRoiAtCenter(x, ypix)
    x = clamp(round(x), 1, nX); ypix = clamp(round(ypix), 1, nY);
    [x1,x2,y1,y2] = roiBounds(x, ypix);
    tc = computeRoiPSC_atSlice(state.z, x1, x2, y1, y2);
    if numel(tc) ~= nT, return; end
    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1))+1, :);
    ROI_byZ{state.z}(end+1) = struct('id', roi.nextId, 'x1', x1, 'x2', x2, 'y1', y1, 'y2', y2, 'color', col);
    roi.nextId = roi.nextId + 1;
    roi.isFrozen = true;
    redrawROIsForCurrentSlice();
    set(hLiveRect, 'Position', [x1 y1 x2-x1+1 y2-y1+1], 'EdgeColor', col, 'Visible', 'on');
    tcHover = computeRoiPSC_idx(state.z, x1, x2, y1, y2, state.hoverIdx);
    if ~isempty(tcHover) && numel(tcHover) == numel(state.tminHover)
        set(hLivePSC, 'XData', state.tminHover, 'YData', tcHover, 'Visible', 'on');
    else
        set(hLivePSC, 'Visible', 'off');
    end
    set(hRoiCoordTxt, 'String', sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1, x2, y1, y2), 'Visible', 'on');
    applyTimecourseAxisMode();
end

function removeNearestRoi(x, ypix)
    roi.isFrozen = false;
    if ~isempty(ROI_byZ{state.z})
        ROI = ROI_byZ{state.z};
        ctr = arrayfun(@(r)[(r.x1+r.x2)/2, (r.y1+r.y2)/2], ROI, 'UniformOutput', false);
        ctr = cat(1, ctr{:});
        [~, i] = min(sum((ctr - [x ypix]).^2, 2));
        ROI(i) = [];
        ROI_byZ{state.z} = ROI;
        redrawROIsForCurrentSlice();
    end
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    applyTimecourseAxisMode();
end

function [x1,x2,y1,y2] = roiBounds(x, ypix)
    hlf = floor(roi.size/2);
    x1 = max(1, x-hlf); x2 = min(nX, x+hlf);
    y1 = max(1, ypix-hlf); y2 = min(nY, ypix+hlf);
end

%% ==========================================================
% SCM COMPUTATION / DISPLAY
%% ==========================================================
function computeSCM(~,~)
    [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
    [s0,s1] = parseRangeSafe(getStr(ebSig), 840, 900);
    sig = str2double(getStr(ebSigma));
    if ~isfinite(sig), sig = 1; end
    if ~isVolMode
        b0i = clamp(round(b0/TR)+1, 1, nT);
        b1i = clamp(round(b1/TR)+1, 1, nT);
        s0i = clamp(round(s0/TR)+1, 1, nT);
        s1i = clamp(round(s1/TR)+1, 1, nT);
    else
        b0i = clamp(round(b0), 1, nT);
        b1i = clamp(round(b1), 1, nT);
        s0i = clamp(round(s0), 1, nT);
        s1i = clamp(round(s1), 1, nT);
    end
    if b1i < b0i, tmp=b0i; b0i=b1i; b1i=tmp; end
    if s1i < s0i, tmp=s0i; s0i=s1i; s1i=tmp; end
    PSCz = getPSCForSlice(state.z);
    baseMap = mean(PSCz(:,:,b0i:b1i), 3);
    sigMap = mean(PSCz(:,:,s0i:s1i), 3);
    map = sigMap - baseMap;
    if sig > 0, map = smooth2D_gauss(map, sig); end
    map(~mask2D) = 0;
    state.lastSignedMap = map;
    set(hOV, 'CData', map);
    updateView();
    applyTimecourseAxisMode();
end

function alphaModToggled(~,~)
    state.alphaModOn = logical(get(cbAlphaMod, 'Value'));
    if state.alphaModOn
        set(ebModMin, 'Enable', 'on', 'ForegroundColor', [1.00 0.35 0.35], 'BackgroundColor', [0.20 0.20 0.20]);
        set(ebModMax, 'Enable', 'on', 'ForegroundColor', [1.00 0.35 0.35], 'BackgroundColor', [0.20 0.20 0.20]);
    else
        set(ebModMin, 'Enable', 'off', 'ForegroundColor', [0.55 0.55 0.55], 'BackgroundColor', [0.16 0.16 0.16]);
        set(ebModMax, 'Enable', 'off', 'ForegroundColor', [0.55 0.55 0.55], 'BackgroundColor', [0.16 0.16 0.16]);
    end
    updateView();
end

function updateView(~,~)
    a = get(slAlpha, 'Value');
    set(txtAlpha, 'String', sprintf('%.0f', a));
    caxv = sscanf(strrep(getStr(ebCax), ',', ' '), '%f');
    if numel(caxv) >= 2 && all(isfinite(caxv(1:2))) && caxv(2) ~= caxv(1)
        state.cax = caxv(1:2).';
        if state.cax(2) < state.cax(1), state.cax = fliplr(state.cax); end
    end
    newSignMode = get(popSignMode, 'Value');
    state.signMode = newSignMode;
    if newSignMode ~= state.prevSignMode
        if newSignMode == 3
            set(popMap, 'Value', findPopupIndexByName(popMap, 'signed_blackbdy_winter'));
        elseif newSignMode == 2
            set(popMap, 'Value', findPopupIndexByName(popMap, 'winter_brain_fsl'));
        else
            set(popMap, 'Value', findPopupIndexByName(popMap, 'blackbdy_iso'));
        end
        state.prevSignMode = newSignMode;
    end
    setOverlayColormap(getCurrentPopupStringLocal(popMap));
    mMin = str2double(getStr(ebModMin)); if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax)); if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin, tmp=mMin; mMin=mMax; mMax=tmp; end
    state.modMin = mMin; state.modMax = mMax;
    [dispMap, alpha] = buildDisplayedOverlay(state.lastSignedMap, mask2D);
    set(hOV, 'CData', dispMap, 'AlphaData', alpha);
    caxis(ax, state.cax);
end

function [dispMap, alpha] = buildDisplayedOverlay(rawMap, localMask)
    a = get(slAlpha, 'Value');
    thr = str2double(getStr(ebThr)); if ~isfinite(thr), thr = 0; end
    mMin = str2double(getStr(ebModMin)); if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax)); if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin, tmp=mMin; mMin=mMax; mMax=tmp; end
    switch state.signMode
        case 1
            showMask = rawMap > 0;
            dispMap = rawMap;
        case 2
            showMask = rawMap < 0;
            dispMap = abs(min(rawMap, 0));
        otherwise
            showMask = isfinite(rawMap) & rawMap ~= 0;
            dispMap = rawMap;
    end
    baseMask = double(localMask);
    thrMask = double((abs(rawMap) >= thr) & showMask) .* baseMask;
    if ~state.alphaModOn
        alpha = (a/100) .* thrMask;
        return;
    end
    effLo = max(mMin, thr);
    effHi = mMax;
    mag = abs(rawMap); mag(~showMask) = NaN;
    if ~isfinite(effHi) || effHi <= effLo
        tmpv = mag(isfinite(mag));
        if isempty(tmpv), effHi = effLo + eps; else, effHi = max(tmpv); end
    end
    if ~isfinite(effHi) || effHi <= effLo, effHi = effLo + eps; end
    modv = (abs(rawMap) - effLo) ./ max(eps, (effHi - effLo));
    modv(~isfinite(modv)) = 0;
    modv = min(max(modv, 0), 1);
    modv(~showMask) = 0;
    if state.signMode == 1
        alpha = (a/100) .* modv .* thrMask;
    else
        alpha = (a/100) .* (0.20 + 0.80 .* modv) .* thrMask;
    end
end

%% ==========================================================
% UNDERLAY CONTROLS
%% ==========================================================
function underlayModeChanged(~,~)
    uState.mode = get(popUnder, 'Value');
    updateUnderlayControlsEnable();
    set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    updateInfoLines();
end

function underlaySliderChanged(~,~)
    uState.brightness = get(slBri, 'Value');
    uState.contrast   = get(slCon, 'Value');
    uState.gamma      = get(slGam, 'Value');
    uState.conectSize = clamp(round(get(slVsz, 'Value')), 0, MAX_CONSIZE);
    uState.conectLev  = clamp(round(get(slVlv, 'Value')), 0, MAX_CONLEV);
    set(txtBri, 'String', sprintf('%.2f', uState.brightness));
    set(txtCon, 'String', sprintf('%.2f', uState.contrast));
    set(txtGam, 'String', sprintf('%.2f', uState.gamma));
    set(txtVsz, 'String', sprintf('%d', uState.conectSize));
    set(txtVlv, 'String', sprintf('%d', uState.conectLev));
    set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    updateInfoLines();
end

function updateUnderlayControlsEnable()
    isVessel = (uState.mode == 4);
    set(slVsz, 'Enable', onoff(isVessel)); set(txtVsz, 'Enable', onoff(isVessel));
    set(slVlv, 'Enable', onoff(isVessel)); set(txtVlv, 'Enable', onoff(isVessel));
end

function updateSliceIndicators()
    if nZ > 1
        if isgraphics(slZ), set(slZ, 'Value', nZ - state.z + 1); end
        if isgraphics(txtZ), set(txtZ, 'String', '', 'Visible', 'off'); end
        if isgraphics(txtSliceOverlay)
            set(txtSliceOverlay, 'String', sprintf('Slice %d / %d', state.z, nZ), 'Visible', 'on');
        end
    else
        if isgraphics(txtZ), set(txtZ, 'String', '', 'Visible', 'off'); end
        if isgraphics(txtSliceOverlay), set(txtSliceOverlay, 'String', '', 'Visible', 'off'); end
    end
end

function updateInfoLines()
    modeNames = {'Legacy','Robust(1..99)','VideoGUI(0.5..99.5)','Vessel enhance'};
    m = uState.mode; if m < 1 || m > 4, m = 3; end
    atlasTxt = '';
    if state.isAtlasWarped, atlasTxt = ' | ATLAS'; end
    set(info1, 'String', sprintf('TR = %.4gs | Slice %d/%d | Underlay: %s%s', TR, state.z, nZ, modeNames{m}, atlasTxt));
end

function s = onoff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

%% ==========================================================
% MASK / UNDERLAY FILE PICKERS
%% ==========================================================
function loadMaskCB(~,~)
    startPath = getMaskStartPath();
    [f,p] = uigetfileStartIn( ...
        {'*.mat;*.nii;*.nii.gz', 'Mask / bundle files (*.mat, *.nii, *.nii.gz)'; ...
         '*.mat', 'MAT mask bundle (*.mat)'; ...
         '*.nii;*.nii.gz', 'NIfTI mask (*.nii, *.nii.gz)'; ...
         '*.*', 'All files (*.*)'}, ...
        'Select overlay mask / bundle', startPath);
    if isequal(f,0), return; end
fullf = fullfile(p,f);
try
    % If user accidentally selects an SCM_GroupExport bundle via LOAD MASK,
    % load it properly as a full SCM bundle instead of trying to read it as a mask.
    if isScmGroupBundleFileLocal(fullf)
        G = loadScmGroupBundleLocal(fullf);
        applyScmGroupBundleLocal(G, fullf);
        return;
    end

    B = [];
        [~,~,ext] = fileparts(fullf); ext = lower(ext);
        if strcmp(ext, '.mat')
            B = readScmBundleFile(fullf);
            if ~isempty(B.overlayMask)
                passedMask = fitBundleMaskToCurrentScm(B.overlayMask);
                passedMaskIsInclude = B.overlayMaskIsInclude;
            elseif ~isempty(B.brainMask)
                passedMask = fitBundleMaskToCurrentScm(B.brainMask);
                passedMaskIsInclude = B.brainMaskIsInclude;
            else
                [passedMask, passedMaskIsInclude] = readMask(fullf, 'overlayPreferred');
                passedMask = fitBundleMaskToCurrentScm(passedMask);
            end
           if ~isempty(B) && isstruct(B) && ~isempty(B.brainImage)
    U = squeeze(double(B.brainImage));

    if isValidBundleUnderlayForCurrentScm(U)
        bg = prepareBundleUnderlayForCurrentScm(U);
        applyUnderlayMeta(defaultUnderlayMeta(), bg);
        origBG = bg;

        fprintf('[SCM] Loaded bundle underlay with size: %s\n', mat2str(size(bg)));
    else
        fprintf(['[SCM] Bundle underlay ignored because it is not a true slice-matched underlay.\n' ...
                 '      Underlay size: %s | SCM expects Y X Z = [%d %d %d]\n'], ...
                 mat2str(size(U)), nY, nX, nZ);
    end
end
        else
            [passedMask, passedMaskIsInclude] = readMask(fullf, 'overlayPreferred');
            passedMask = fitBundleMaskToCurrentScm(passedMask);
        end
        mask2D = getMaskForCurrentSlice();
        set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
        if ~isempty(B) && isstruct(B)
            set(info1, 'String', sprintf('Loaded mask bundle: %s | field: %s', shortenPath(fullf,65), B.loadedField));
        else
            set(info1, 'String', sprintf('Loaded mask: %s', shortenPath(fullf,65)));
        end
        set(info1, 'TooltipString', fullf);
        computeSCM();
    catch ME
        errordlg(ME.message, 'Mask / bundle load failed');
    end
end

function clearMaskCB(~,~) %#ok<DEFNU>
    passedMask = [];
    passedMaskIsInclude = true;
    mask2D = true(nY, nX);
    set(info1, 'String', 'Overlay mask cleared.', 'TooltipString', '');
    computeSCM();
end

function loadNewUnderlayCB(~,~)
    ensureUnderlayStateFields();
    startPath = getUnderlayStartPathFast();
    [f,p] = uigetfileStartIn( ...
        {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.jpeg,*.tif,*.tiff,*.bmp)'}, ...
        'Select new underlay', startPath);
    if isequal(f,0), return; end
    fullf = fullfile(p,f);
    try
        [Uraw, meta] = readUnderlayFile(fullf);
        Uraw = squeeze(Uraw);
        if isempty(Uraw) || ~(isnumeric(Uraw) || islogical(Uraw))
            error('Selected underlay is empty or not numeric/RGB: %s', fullf);
        end

        if state.isAtlasWarped
            if doesUnderlayMatchCurrentDisplay(Uraw)
                U = validateAndPrepareUnderlay(Uraw, fullf);
            elseif doesUnderlayMatchOriginalDisplay(Uraw)
                tfFile = getBestTransformForUnderlay(fullf, Uraw);
                if isempty(tfFile) || exist(tfFile,'file') ~= 2
                    error('Current SCM is atlas-warped, but no transform could be found to warp native underlay.');
                end
                S = load(tfFile); T = extractAtlasWarpStruct(S);
                U = warpUnderlayForCurrentDisplay(Uraw, T);
                U = validateAndPrepareUnderlay(U, fullf);
            else
                error('Selected underlay does not match current atlas display or original native display.');
            end
            bg = U; applyUnderlayMeta(meta, bg);
            set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
            set(info1, 'String', ['Loaded atlas-space underlay: ' shortenPath(fullf,85)], 'TooltipString', fullf);
            drawnow;
            return;
        end

       % ---------------------------------------------------------
% Important atlas/histology guard:
% If this file looks like an atlas/histology registration export,
% try to use its transform even if image size already matches native PSC.
% Otherwise SCM wrongly treats atlas-space histology as native underlay.
% ---------------------------------------------------------
if doesUnderlayMatchCurrentDisplay(Uraw)

    didAtlasApply = false;

    if isAtlasLikeUnderlayFile(fullf)
        tfFile0 = getBestTransformForUnderlay(fullf, Uraw);

        if ~isempty(tfFile0) && exist(tfFile0,'file') == 2
            try
           S0 = load(tfFile0);
T0 = extractAtlasWarpStruct(S0);
T0 = force2DOutputSizeFromTargetUnderlay(T0, Uraw);
T0 = askAndApply2DWarpDirection(T0, 'Atlas/histology underlay warp');

                if doesUnderlayMatchTransformOutput(Uraw, T0)
                    PSC = warpFunctionalSeriesToAtlas(origPSC, T0);

                    passedMask = [];
                    passedMaskIsInclude = true;

                    state.isAtlasWarped = true;
                    state.atlasTransformFile = tfFile0;
                    state.lastAtlasTransformFile = tfFile0;

                    bg = validateAndPrepareUnderlay(Uraw, fullf);
                    applyUnderlayMeta(meta, bg);

                    try
                        set(btnWarpAtlas, 'String', 'ALREADY WARPED TO ATLAS');
                    catch
                    end

                    setTitleAtlas(T0);
                    resetRoisAndRefreshAfterDataChange();

                    set(info1, 'String', ...
                        ['Loaded atlas/histology underlay and warped functional: ' shortenPath(fullf,70)], ...
                        'TooltipString', fullf);

                    didAtlasApply = true;
                    drawnow;
                    return;
                end

            catch MEatlas
                % Fall through to normal native underlay loading.
                try
                    set(info1, 'String', ...
                        ['Atlas-like file found, but transform use failed: ' MEatlas.message], ...
                        'TooltipString', fullf);
                catch
                end
            end
        end
    end

    if ~didAtlasApply
        bg = validateAndPrepareUnderlay(Uraw, fullf);
        applyUnderlayMeta(meta, bg);
        origBG = bg;
        set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
        set(info1, 'String', ['Loaded native underlay: ' shortenPath(fullf,85)], 'TooltipString', fullf);
        drawnow;
        return;
    end
end

        tfFile = getBestTransformForUnderlay(fullf, Uraw);
        if isempty(tfFile) || exist(tfFile,'file') ~= 2
            [ft,pt] = uigetfileStartIn({'*.mat','Transform files (*.mat)'}, ...
                sprintf('Auto-detection failed. Select transform file manually.\nExamples: CoronalRegistration2D*.mat or Transformation*.mat'), ...
                getTransformStartPath());
            if isequal(ft,0), return; end
            tfFile = fullfile(pt,ft);
        end
       S = load(tfFile);
T = extractAtlasWarpStruct(S);
T = force2DOutputSizeFromTargetUnderlay(T, Uraw);
T = askAndApply2DWarpDirection(T, 'Atlas/histology underlay warp');
        if ~doesUnderlayMatchTransformOutput(Uraw, T)
            error(['Selected underlay size [%d %d] does not match current native SCM size [%d %d] ' ...
                   'and also does not match transform output size.'], size(Uraw,1), size(Uraw,2), nY, nX);
        end
        PSC = warpFunctionalSeriesToAtlas(origPSC, T);
        passedMask = [];
        passedMaskIsInclude = true;
        state.isAtlasWarped = true;
        state.atlasTransformFile = tfFile;
        state.lastAtlasTransformFile = tfFile;
        try, set(btnWarpAtlas, 'String', 'ALREADY WARPED TO ATLAS'); catch, end
        resetRoisAndRefreshAfterDataChange();
        bg = validateAndPrepareUnderlay(Uraw, fullf);
        applyUnderlayMeta(meta, bg);
        set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
        setTitleAtlas(T);
        set(info1, 'String', ['Loaded atlas underlay and warped functional: ' shortenPath(fullf,70)], 'TooltipString', fullf);
        drawnow;
    catch ME
        errordlg(ME.message, 'Load underlay failed');
    end
end

%% ==========================================================
% ATLAS WARP
%% ==========================================================
function warpFunctionalToAtlasCB(~,~)

    if state.isAtlasWarped
        choice0 = questdlg(['Functional data is already in atlas space.' newline newline ...
            'Reapply atlas warp from original native PSC?'], ...
            'Already atlas-warped', ...
            'Reapply from native', 'Cancel', 'Cancel');

        if isempty(choice0) || strcmpi(choice0,'Cancel')
            return;
        end
    end

    % For step-motor / multi-slice data, default to folder mode.
    if nZ > 1
        defaultMode = 'Step Motor folder';
    else
        defaultMode = 'Single transform';
    end

    modeChoice = questdlg([ ...
        'Choose atlas warp mode:' newline newline ...
        'Single transform:' newline ...
        '  Uses one CoronalRegistration2D / Transformation MAT file.' newline ...
        '  For 4D data with a 2D transform, this warps only one source slice.' newline newline ...
        'Step Motor folder:' newline ...
        '  Select a folder. SCM searches all MAT files inside it.' newline ...
        '  Files are matched by source001, source002, slice001, etc.' newline ...
        '  Each transform is applied to the matching functional slice.'], ...
        'Warp functional to atlas', ...
        'Single transform', 'Step Motor folder', 'Cancel', defaultMode);

    if isempty(modeChoice) || strcmpi(modeChoice,'Cancel')
        return;
    end

    if strcmpi(modeChoice,'Step Motor folder')
        warpFunctionalToAtlasStepMotorFolder();
    else
        warpFunctionalToAtlasSingleFile();
    end
end

function warpFunctionalToAtlasSingleFile()

    startDir = getTransformStartPath();

    [f,p] = uigetfileStartIn({'*.mat','Transform files (*.mat)'}, ...
        'Select atlas Transformation / CoronalRegistration2D', startDir);

    if isequal(f,0)
        return;
    end

    try
        tfFile = fullfile(p,f);

        S = load(tfFile);
T = extractAtlasWarpStruct(S);
T = askAndApply2DWarpDirection(T, 'Single atlas warp');

PSC = warpFunctionalSeriesToAtlas(origPSC, T);

        passedMask = [];
        passedMaskIsInclude = true;

        state.isAtlasWarped = true;
        state.isStepMotorAtlasWarped = false;

        state.atlasTransformFile = tfFile;
        state.lastAtlasTransformFile = tfFile;

        state.stepMotorAtlasFolder = '';
        state.stepMotorAtlasTransformFiles = {};
        state.stepMotorAtlasSourceIdx = [];
        state.stepMotorAtlasAtlasIdx = [];

        try
            set(btnWarpAtlas, 'String', 'ALREADY WARPED TO ATLAS');
        catch
        end

        setTitleAtlas(T);
        resetRoisAndRefreshAfterDataChange();

        msg = 'Functional data warped to atlas.';

        if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d')
            msg = 'Functional data warped with 2D coronal registration.';
        end

        set(info1, 'String', msg, 'TooltipString', tfFile);

    catch ME
        errordlg(ME.message, 'Atlas warp failed');
    end
end


function warpFunctionalToAtlasStepMotorFolder()

    startDir = getStepMotorTransformStartPath();

    folderPath = uigetdir(startDir, ...
        'Select Step Motor Registration2D folder containing source001/source002 transforms');

    if isequal(folderPath,0)
        return;
    end

    try
        regList = collectStepMotorRegistration2DTransforms(folderPath);
regList = askAndApply2DWarpDirectionToRegList(regList, 'Step Motor atlas warp');
        if isempty(regList)
            error(['No valid Step Motor Registration2D transforms found in:' newline ...
                   folderPath newline newline ...
                   'Expected files like:' newline ...
                   '  CoronalRegistration2D_source001_atlas112_histology.mat' newline ...
                   '  CoronalRegistration2D_source002_atlas115_histology.mat' newline ...
                   'or filenames containing source001 / source002 / slice001.']);
        end

        if ndims(origPSC) == 4
            nSourceSlices = size(origPSC,3);
        else
            nSourceSlices = 1;
        end

        foundIdx = [regList.sourceIdx];
        foundIdx = foundIdx(isfinite(foundIdx));
        foundIdx = unique(foundIdx(:).');

        missingIdx = setdiff(1:nSourceSlices, foundIdx);

        if nSourceSlices > 1 && ~isempty(missingIdx)
            msg = sprintf([ ...
                'Found transforms for %d/%d source slices.\n\n' ...
                'Found source slices:\n%s\n\n' ...
                'Missing source slices:\n%s\n\n' ...
                'Continue using only the found slices?'], ...
                numel(foundIdx), nSourceSlices, ...
                compactIndexList(foundIdx), ...
                compactIndexList(missingIdx));

            ch = questdlg(msg, ...
                'Missing Step Motor transforms', ...
                'Continue', 'Cancel', 'Cancel');

            if isempty(ch) || strcmpi(ch,'Cancel')
                return;
            end
        end

        [PSCnew, report] = warpFunctionalSeriesToAtlasStepMotor(origPSC, regList);

        if isempty(PSCnew) || report.nUsed < 1
            error('No slices were warped. Check source001/source002 numbering and transform files.');
        end

        PSC = PSCnew;

        passedMask = [];
        passedMaskIsInclude = true;

        state.isAtlasWarped = true;
        state.isStepMotorAtlasWarped = true;

        state.atlasTransformFile = folderPath;
        state.lastAtlasTransformFile = report.files{1};

        state.stepMotorAtlasFolder = folderPath;
        state.stepMotorAtlasTransformFiles = report.files;
        state.stepMotorAtlasSourceIdx = report.sourceIdx;
        state.stepMotorAtlasAtlasIdx = report.atlasIdx;

       % ---------------------------------------------------------
% Build FIXED atlas/histology underlay.
%
% Do NOT open another file selector here.
% The user already selected the Step Motor Registration2D folder.
% ---------------------------------------------------------
[bgNew, bgMsg] = buildStepMotorFixedAtlasUnderlayOnly(report.usedRegList, report.outSize, bg);

% If no fixed atlas/histology image was found inside the Reg2D MAT files,
% try to keep the already-loaded underlay if it matches atlas output size.
if isempty(bgNew)
    [bgNew, bgMsg] = keepAlreadyLoadedAtlasUnderlayIfPossible(bg, report.outSize, report.nUsed);
end

% Last fallback:
% Do NOT use a blank black canvas.
% If fixed histology is not saved in the Reg2D files, use the warped
% functional contrast as a temporary diagnostic underlay.
if isempty(bgNew)
    bgNew = makeFunctionalContrastFallbackUnderlay(PSCnew);
    bgMsg = 'functional contrast fallback; fixed histology was not saved in Reg2D files';
end

bg = bgNew;

forceStepMotorAtlasGrayUnderlay();
        try
            set(btnWarpAtlas, 'String', 'STEP MOTOR ATLAS-WARPED');
        catch
        end

        setTitleAtlasStepMotor(report);
        resetRoisAndRefreshAfterDataChange();

       msg = sprintf('Step Motor atlas warp complete: %d slices warped. Underlay: %s', report.nUsed, bgMsg);
        set(info1, 'String', msg, 'TooltipString', folderPath);

    catch ME
        errordlg(ME.message, 'Step Motor atlas warp failed');
    end
end

function resetWarpToNativeCB(~,~)
    try
        PSC = origPSC;
        bg = origBG;
        passedMask = origPassedMask;
        passedMaskIsInclude = true;
       state.isAtlasWarped = false;
state.isStepMotorAtlasWarped = false;

state.atlasTransformFile = '';
state.lastAtlasTransformFile = '';

state.stepMotorAtlasFolder = '';
state.stepMotorAtlasTransformFiles = {};
state.stepMotorAtlasSourceIdx = [];
state.stepMotorAtlasAtlasIdx = [];
        try, set(btnWarpAtlas, 'String', 'WARP FUNCTIONAL TO ATLAS'); catch, end
        set(txtTitle, 'String', fileLabel);
        resetRoisAndRefreshAfterDataChange();
        set(info1, 'String', 'Returned to native functional space.', 'TooltipString', '');
    catch ME
        errordlg(ME.message, 'Reset to native failed');
    end
end

function setTitleAtlas(T)
    try
        if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d') && ...
                isfield(T,'atlasSliceIndex') && isfinite(T.atlasSliceIndex)
            set(txtTitle, 'String', sprintf('%s | warped to atlas coronal slice %d', fileLabel, round(T.atlasSliceIndex)));
        else
            set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
        end
    catch
        set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
    end
end

function resetRoisAndRefreshAfterDataChange()
    refreshDimsAfterPSCChange();
    ROI_byZ = cell(1, nZ);
    for zzi = 1:nZ
        ROI_byZ{zzi} = struct('id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
    end
    roi.nextId = 1; roi.isFrozen = false;
    deleteIfValid(roiHandles); roiHandles = gobjects(0);
    deleteIfValid(roiPlotPSC); roiPlotPSC = gobjects(0);
    deleteIfValid(roiTextHandles); roiTextHandles = gobjects(0);
    mask2D = getMaskForCurrentSlice();
    if isgraphics(slZ)
        set(slZ, 'Min', 1, 'Max', max(1,nZ), 'Value', nZ-state.z+1, ...
            'SliderStep', [1/max(1,max(1,nZ-1)) 5/max(1,max(1,nZ-1))], ...
            'Visible', 'off', 'Enable', 'off');
    end
    if isgraphics(txtZ), set(txtZ, 'String', '', 'Visible', 'off'); end
    updateSliceIndicators();
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'XData', state.tminHover, 'YData', nan(1,numel(state.tminHover)), 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    set(hOV, 'CData', zeros(nY,nX), 'AlphaData', zeros(nY,nX));
    updateInfoLines(); computeSCM(); redrawROIsForCurrentSlice(); drawnow;
end

function autoFixStartupAtlasUnderlayIfNeeded()
    try
        if isempty(bg) || ~(isnumeric(bg) || islogical(bg)), return; end
        U = squeeze(bg);
        if isempty(U) || ndims(U) < 2, return; end
       % Do not automatically return only because the pixel size matches.
% Atlas/histology exports can have the same pixel dimensions as native data
% but still be in atlas coordinates.
sameSizeAsFunctional = (size(U,1) == nY && size(U,2) == nX);

if sameSizeAsFunctional
    % Without a filename, startup auto-fix cannot safely know whether this is
    % native or atlas space. Therefore keep it native here.
    % Atlas-like files loaded via LOAD NEW UNDERLAY are handled in loadNewUnderlayCB.
    return;
end
        tfFile = getBestTransformForUnderlay('', U);
        if isempty(tfFile) || exist(tfFile,'file') ~= 2
            startupAtlasNote = ['Startup underlay size did not match PSC, but no atlas transform was found. Using fallback native underlay.'];
            bg = makeNativeFallbackUnderlayFromPSC(origPSC);
            return;
        end
        S = load(tfFile); T = extractAtlasWarpStruct(S);
        if ~doesUnderlayMatchTransformOutput(U, T)
            startupAtlasNote = ['Startup underlay did not match PSC size or transform output. Using fallback native underlay.'];
            bg = makeNativeFallbackUnderlayFromPSC(origPSC);
            return;
        end
        PSC = warpFunctionalSeriesToAtlas(origPSC, T);
        state.isAtlasWarped = true;
        state.atlasTransformFile = tfFile;
        state.lastAtlasTransformFile = tfFile;
        refreshDimsAfterPSCChange();
        bg = validateAndPrepareUnderlay(U, 'startup underlay');
        applyUnderlayMeta(defaultUnderlayMeta(), bg);
        startupAtlasNote = ['Startup atlas underlay detected. Functional data auto-warped using: ' tfFile];
    catch ME
        startupAtlasNote = ['Startup atlas guard failed: ' ME.message];
        try, bg = makeNativeFallbackUnderlayFromPSC(origPSC); catch, end
    end
end

function refreshDimsAfterPSCChange()
    dNow = ndims(PSC);
    if dNow == 3
        [nY, nX, nT] = size(PSC); nZ = 1;
    elseif dNow == 4
        [nY, nX, nZ, nT] = size(PSC);
    else
        error('PSC must be [Y X T] or [Y X Z T].');
    end
    tsec = (0:nT-1) * TR;
    tmin = tsec / 60;
    state.hoverStride = max(1, ceil(nT / state.hoverMaxPts));
    state.hoverIdx = 1:state.hoverStride:nT;
    state.tminHover = tmin(state.hoverIdx);
    state.z = max(1, min(state.z, nZ));
    state.lastSignedMap = zeros(nY, nX);
end

%% ==========================================================
% EXPORTS
%% ==========================================================
function exportROIsCB(~,~)
    if roi.exportBusy, return; end
    tNowSec = now * 86400;
    if (tNowSec - roi.lastExportStampSec) < 0.75, return; end
    roi.exportBusy = true;
    cleanupObj = onCleanup(@releaseRoiExportLock); %#ok<NASGU>
    try
        nTot = 0;
        for zz = 1:nZ, nTot = nTot + numel(ROI_byZ{zz}); end
        if nTot == 0
            warndlg('No ROIs to export. Add ROIs first.', 'Export ROIs'); return;
        end
        P = getSimpleExportPaths(); roiDir = P.roiDir; safeMkdirIfNeeded(roiDir);
        labelTag = askExportLabel(roi.lastExportLabel, 'ROI export label');
        if isempty(labelTag), return; end
        roi.lastExportLabel = labelTag;
        roi.sessionSetId = roi.sessionSetId + 1;
        setId = roi.sessionSetId;
        dIdx = 1;
        flat = struct('z', {}, 'id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
        for zz = 1:nZ
            ROI = ROI_byZ{zz};
            for k = 1:numel(ROI)
                r = ROI(k);
                flat(end+1) = struct('z', zz, 'id', r.id, 'x1', r.x1, 'x2', r.x2, 'y1', r.y1, 'y2', r.y2, 'color', r.color); %#ok<AGROW>
            end
        end
        keys = cell(numel(flat),1);
        for i = 1:numel(flat)
            keys{i} = sprintf('%d_%d_%d_%d_%d', flat(i).z, flat(i).x1, flat(i).x2, flat(i).y1, flat(i).y2);
        end
        [~, ia] = unique(keys, 'stable'); flat = flat(sort(ia));
        A = [[flat.z].' [flat.id].']; [~, ord] = sortrows(A, [1 2]); flat = flat(ord);
        for i = 1:numel(flat)
            r = flat(i);
            outFile = fullfile(roiDir, sprintf('ROI%d_%s_d%d.txt', setId, labelTag, dIdx));
            while exist(outFile,'file') == 2
                dIdx = dIdx + 1;
                outFile = fullfile(roiDir, sprintf('ROI%d_%s_d%d.txt', setId, labelTag, dIdx));
            end
            fid = fopen(outFile, 'w');
            if fid < 0, error('Could not write ROI file: %s', outFile); end
            fprintf(fid, '# ROI export from SCM_gui\n');
            fprintf(fid, '# Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fid, '# FileLabel: %s\n', fileLabel);
            fprintf(fid, '# TR_sec: %.6g\n', TR);
            fprintf(fid, '# nY nX nZ nT: %d %d %d %d\n', nY,nX,nZ,nT);
            fprintf(fid, '# ROI_SET_ID: %d\n', setId);
            fprintf(fid, '# ROI_LABEL: %s\n', labelTag);
            fprintf(fid, '# ROI_D_INDEX: %d\n', dIdx);
            fprintf(fid, '# ROI_MARKER_ID: %d\n', r.id);
            fprintf(fid, '# SLICE: %d\n', r.z);
            fprintf(fid, '# BaselineWindow: %s\n', getStr(ebBase));
            fprintf(fid, '# SignalWindow: %s\n', getStr(ebSig));
            fprintf(fid, '# x1 x2 y1 y2\n%d %d %d %d\n', r.x1,r.x2,r.y1,r.y2);
            fprintf(fid, '# color_rgb\n%.6f %.6f %.6f\n', r.color(1),r.color(2),r.color(3));
            tc = computeRoiPSC_atSlice(r.z, r.x1, r.x2, r.y1, r.y2);
            if isempty(tc) || numel(tc) ~= nT, tc = nan(1,nT); end
            fprintf(fid, '# columns: time_sec\ttime_min\tPSC\n');
            for ii = 1:nT, fprintf(fid, '%.6f\t%.6f\t%.6f\n', tsec(ii), tmin(ii), tc(ii)); end
            fclose(fid);
            dIdx = dIdx + 1;
        end
        msgbox(sprintf('Exported %d ROI(s) to:\n%s\n(as ROI%d_%s_d#.txt)', numel(flat), roiDir, setId, labelTag), 'Export ROIs');
    catch ME
        errordlg(ME.message, 'ROI export failed');
    end
end

function releaseRoiExportLock()
    roi.exportBusy = false;
    roi.lastExportStampSec = now * 86400;
end

function exportSCMImageCB(~,~)
    if state.singleScmExportBusy, return; end
    tNowSec = now * 86400;
    if (tNowSec - state.lastSingleScmExportStampSec) < 0.75, return; end
    state.singleScmExportBusy = true;
    cleanupObj = onCleanup(@releaseSingleScmExportLock); %#ok<NASGU>

    tf = [];
    slidePng = '';
    try
        P = getSimpleExportPaths(); outDir = P.scmImageDir; safeMkdirIfNeeded(outDir);
        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        baseName = sprintf('SCM_z%02d_%s', state.z, stamp);
        outPng = fullfile(outDir, [baseName '.png']);
        outTif = fullfile(outDir, [baseName '.tif']);
        outJpg = fullfile(outDir, [baseName '.jpg']);

        tf = figure('Visible','off','Color',[0.05 0.05 0.05],'InvertHardcopy','off','Units','pixels','Position',[200 120 1400 980]);
        ax2 = axes('Parent',tf,'Units','normalized','Position',[0.06 0.10 0.74 0.84]);
        axis(ax2,'image'); axis(ax2,'off'); set(ax2,'YDir','reverse'); hold(ax2,'on');
        image(ax2, get(hBG,'CData'));
        h2 = imagesc(ax2, get(hOV,'CData')); set(h2,'AlphaData',get(hOV,'AlphaData'));
        try, colormap(ax2, colormap(ax)); catch, colormap(ax2, colormap(fig)); end
        caxis(ax2, state.cax);

        ROI = ROI_byZ{state.z};
        for k = 1:numel(ROI)
            r = ROI(k);
            rectangle(ax2, 'Position', [r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], 'EdgeColor', r.color, 'LineWidth', 2);
            text(ax2, r.x1, max(1,r.y1-2), sprintf('%d',r.id), 'Color', r.color, 'FontWeight','bold', ...
                'FontSize',12,'Interpreter','none','VerticalAlignment','bottom','BackgroundColor',[0 0 0],'Margin',1);
        end

        title(ax2, sprintf('%s | Slice %d/%d', fileLabel, state.z, nZ), 'Color','w','FontWeight','bold','Interpreter','none');
        cb2 = colorbar(ax2); cb2.Color = 'w'; cb2.Label.String = 'Signal change (%)'; cb2.FontSize = 12;
        set(tf,'PaperPositionMode','auto');
        print(tf,outPng,'-dpng','-r300','-opengl');
        print(tf,outTif,'-dtiff','-r300','-opengl');
        print(tf,outJpg,'-djpeg','-r300','-opengl');
        if isgraphics(tf), close(tf); end
        tf = [];

        pptPath = '';
        if canUsePptApi()
            slidePng = fullfile(outDir, [baseName '_slide.png']);
            renderSingleScmSlidePNG(slidePng, outPng, fileLabel, state.z, nZ, state.cax, colormap(ax));
            pptPath = chooseShortSinglePptPath(outDir, fileLabel, stamp);
            writePptFromSlidePNGs(pptPath, {slidePng});
            try
                if exist(slidePng, 'file') == 2, delete(slidePng); end
            catch
            end
        end

        if ~isempty(pptPath)
            set(info1,'String',sprintf('Saved SCM: %s (png/tif/jpg/ppt)', shortenPath(outDir,85)), 'TooltipString', outDir);
        else
            set(info1,'String',sprintf('Saved SCM: %s (png/tif/jpg)', shortenPath(outDir,85)), 'TooltipString', outDir);
        end

    catch ME
        try, if ~isempty(tf) && isgraphics(tf), close(tf); end, catch, end
        try, if ~isempty(slidePng) && exist(slidePng,'file') == 2, delete(slidePng); end, catch, end
        errordlg(ME.message, 'Export SCM Image failed');
    end
end

function releaseSingleScmExportLock()
    state.singleScmExportBusy = false;
    state.lastSingleScmExportStampSec = now * 86400;
end

function exportTimecoursePngCB(~,~)
    tf = [];
    try
        P = getSimpleExportPaths(); outDir = P.scmTcDir; safeMkdirIfNeeded(outDir);
        labelTag = askExportLabel(state.lastTcExportLabel, 'Time course export label');
        if isempty(labelTag), return; end
        state.lastTcExportLabel = labelTag;
        stamp = datestr(now,'yyyymmdd_HHMMSS');
        baseName = sprintf('%s_%s_TimeCourse_%s', P.fileStem, labelTag, stamp);
        outPngGrid = fullfile(outDir, [baseName '_grid.png']);
        outPngNoGrid = fullfile(outDir, [baseName '_nogrid.png']);
        tf = figure('Visible','off','Color',[0.05 0.05 0.05],'InvertHardcopy','off','Units','pixels','Position',[150 120 1500 780]);
        ax2 = axes('Parent',tf,'Units','normalized','Position',[0.11 0.14 0.84 0.76], ...
            'Color',[0.05 0.05 0.05],'XColor','w','YColor','w','LineWidth',1.2,'Box','on','Layer','top');
        hold(ax2,'on'); grid(ax2,'on');
        xlabel(ax2,'Time (min)','Color','w','FontSize',13,'FontWeight','bold');
        hY = ylabel(ax2,'PSC (%)','Color','w','FontSize',13,'FontWeight','bold');
        try, set(hY,'Units','normalized','Position',[-0.028 0.50 0],'Clipping','off'); catch, end
        title(ax2, sprintf('%s | %s ROI Time Course', fileLabel, labelTag), 'Color','w','FontWeight','bold','Interpreter','none');
        ROI = ROI_byZ{state.z};
        for k = 1:numel(ROI)
            r = ROI(k); tc = computeRoiPSC_atSlice(state.z, r.x1, r.x2, r.y1, r.y2);
            if numel(tc) == nT, plot(ax2, tmin, tc, ':', 'Color', r.color, 'LineWidth', 2.6); end
        end
        if strcmp(get(hLivePSC,'Visible'),'on')
            plot(ax2, get(hLivePSC,'XData'), get(hLivePSC,'YData'), ':', 'Color', get(hLivePSC,'Color'), 'LineWidth', 3.0);
        end
        yl = get(axTC,'YLim'); if any(~isfinite(yl)) || yl(2) <= yl(1), yl = [-5 5]; end
        xl = get(axTC,'XLim'); if any(~isfinite(xl)) || xl(2) <= xl(1), xl = [tmin(1) tmin(end)]; end
        set(ax2,'YLim',yl,'XLim',xl);
        applyExportWindowPatches(ax2, yl);
        print(tf,outPngGrid,'-dpng','-r300','-opengl');
        grid(ax2,'off'); print(tf,outPngNoGrid,'-dpng','-r300','-opengl');
        if isgraphics(tf), close(tf); end
        set(info1,'String',['Saved time course PNGs to: ' shortenPath(outDir,90)], 'TooltipString', outDir);
    catch ME
        try, if ~isempty(tf) && isgraphics(tf), close(tf); end, catch, end
        errordlg(ME.message, 'Export time course PNG failed');
    end
end

function exportScmSeries1minCB(~,~)
    if state.seriesExportBusy, return; end
    tNowSec = now * 86400;
    if (tNowSec - state.lastSeriesExportStampSec) < 0.75, return; end
    state.seriesExportBusy = true;
    cleanupObj = onCleanup(@releaseSeriesExportLock); %#ok<NASGU>

    EXPORT_DPI_TILES  = 200;
    EXPORT_DPI_SLIDES = 200;
    SAVE_TIF = true;
    SAVE_JPG = true;

    figT = [];
    tmpSLD = '';
    slidePNGs = {};
    slideSpecs = {};

    try
        a = inputdlg({ ...
            'Injection start (sec). Empty if unknown:', ...
            'Window length (sec) (default 60):', ...
            'Max minutes to export (empty=all):', ...
            'Export PPT too? (1=yes,0=no) (default 1):'}, ...
            'Export SCM series', 1, {'', '60', '', '1'});
        if isempty(a), return; end

        injSec = str2double(strtrim(a{1}));
        if ~isfinite(injSec), injSec = NaN; end

        winLen = str2double(strtrim(a{2}));
        if ~isfinite(winLen) || winLen <= 0, winLen = 60; end

        maxMin = str2double(strtrim(a{3}));
        if ~isfinite(maxMin) || maxMin <= 0, maxMin = NaN; end

        doPPT = str2double(strtrim(a{4}));
        if ~isfinite(doPPT), doPPT = 1; end
        doPPT = (doPPT ~= 0);

        P = getSimpleExportPaths();
        rootScm = P.scmSeriesDir;
        safeMkdirIfNeeded(rootScm);

        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        outDir = fullfile(rootScm, ['SCM_series_' stamp]);
        safeMkdirIfNeeded(outDir);

        dirPNG = fullfile(outDir, 'tiles_png');
        dirTIF = fullfile(outDir, 'tiles_tif');
        dirJPG = fullfile(outDir, 'tiles_jpg');
        safeMkdirIfNeeded(dirPNG);
        safeMkdirIfNeeded(dirTIF);
        safeMkdirIfNeeded(dirJPG);

        tmpSLD = fullfile(outDir, '_tmp_slide_pngs');
        safeMkdirIfNeeded(tmpSLD);

        try
            set(info1, 'String', {'Saving to:', shortenPath(outDir,120), 'Tip: hover here to see full path'});
            set(info1, 'TooltipString', outDir);
            drawnow;
        catch
        end

        [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
        if ~isVolMode
            b0i = clamp(round(b0/TR)+1, 1, nT);
            b1i = clamp(round(b1/TR)+1, 1, nT);
        else
            b0i = clamp(round(b0), 1, nT);
            b1i = clamp(round(b1), 1, nT);
        end
        if b1i < b0i
            tmp = b0i; b0i = b1i; b1i = tmp;
        end

        cm = colormap(ax);
        caxV = state.cax;

        sigma = str2double(getStr(ebSigma));
        if ~isfinite(sigma), sigma = 1; end

        thrStr  = strtrim(getStr(ebThr));
        caxStr  = strtrim(getStr(ebCax));
        baseStr = strtrim(getStr(ebBase));
        aStr    = sprintf('Alpha=%s%%', strtrim(getStr(txtAlpha)));
        modStr  = sprintf('AlphaMod=%d [%s..%s]', double(state.alphaModOn), ...
            strtrim(getStr(ebModMin)), strtrim(getStr(ebModMax)));
        sigStr  = sprintf('Sigma=%g', sigma);
        footerInfo = sprintf('Thr=%s | CAX=%s | Base=%s | %s | %s | %s', ...
            thrStr, caxStr, baseStr, aStr, modStr, sigStr);

        totalSec = (nT-1) * TR;
        starts = 0:winLen:(floor(totalSec/winLen)*winLen);
        if isfinite(maxMin)
            starts = starts(starts < maxMin*60);
        end

        figT = figure('Visible','off','Color',[0 0 0], ...
            'InvertHardcopy','off','Units','pixels','Position',[50 50 1200 880]);
        axT = axes('Parent',figT,'Units','normalized','Position',[0 0 1 1]);
        axis(axT,'image'); axis(axT,'off'); set(axT,'YDir','reverse'); hold(axT,'on');
        hBgT = image(axT, zeros(nY,nX,3));
        hT = imagesc(axT, zeros(nY,nX));
        set(hT,'AlphaData',zeros(nY,nX));
        colormap(axT, cm);
        caxis(axT, caxV);
        hold(axT,'off');
        set(figT,'PaperPositionMode','auto');

        nSavedTotal = 0;

        for zSel = 1:nZ
            PSCz = getPSCForSlice(zSel);
            baseMap = mean(PSCz(:,:,b0i:b1i), 3);
            maskLocal = getMaskForSlice(zSel);

            bgRGB = renderUnderlayRGB(getBg2DForSlice(zSel));
            set(hBgT, 'CData', bgRGB);

            tilePNG = {};
            tileLBL = {};

            for wi = 1:numel(starts)
                s0 = starts(wi);
                s1 = s0 + winLen;
                idxSig = find(tsec >= s0 & tsec < s1);
                if isempty(idxSig), continue; end

                sigMap = mean(PSCz(:,:,idxSig), 3);
                map = sigMap - baseMap;
                if sigma > 0, map = smooth2D_gauss(map, sigma); end
                map(~maskLocal) = 0;

                [dispMap, alpha] = buildDisplayedOverlay(map, maskLocal);
                set(hT, 'CData', dispMap, 'AlphaData', alpha);
                colormap(axT, cm);
                caxis(axT, caxV);

                minIdx = floor(s0 / winLen) + 1;
                phase = '';
                if isfinite(injSec)
                    if s1 <= injSec
                        phase = 'Baseline';
                    elseif s0 < injSec && s1 > injSec
                        phase = 'Injection';
                    else
                        piMin = floor((s0 - injSec)/winLen) + 1;
                        if piMin < 1, piMin = 1; end
                        phase = sprintf('%d min PI', piMin);
                    end
                end

                if isempty(phase)
                    lbl = sprintf('z=%d/%d | %.0f-%.0fs | %d min', zSel, nZ, s0, s1, minIdx);
                else
                    lbl = sprintf('z=%d/%d | %.0f-%.0fs | %d min (%s)', zSel, nZ, s0, s1, minIdx, phase);
                end

                baseName = sprintf('SCM_z%02d_w%03d_%0.0f-%0.0fs', zSel, minIdx, s0, s1);
                outPng = fullfile(dirPNG, [baseName '.png']);
                outTif = fullfile(dirTIF, [baseName '.tif']);
                outJpg = fullfile(dirJPG, [baseName '.jpg']);

                print(figT, outPng, '-dpng', sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
                if SAVE_TIF
                    print(figT, outTif, '-dtiff', sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
                end
                if SAVE_JPG
                    print(figT, outJpg, '-djpeg', sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
                end

                nSavedTotal = nSavedTotal + 1;
                tilePNG{end+1} = outPng; %#ok<AGROW>
                tileLBL{end+1} = lbl; %#ok<AGROW>

                try
                    set(info1, 'String', sprintf('Exporting tiles... slice %d/%d | %d total | %s', ...
                        zSel, nZ, nSavedTotal, shortenPath(outDir,55)));
                    set(info1, 'TooltipString', outDir);
                    drawnow limitrate;
                catch
                end
            end

            if isempty(tilePNG), continue; end

            perSlide = 6;
            nSlides = ceil(numel(tilePNG) / perSlide);
            fullTitle = sprintf('%s | z=%d/%d', makeFullTitle(fileLabel), zSel, nZ);
            shortTitle = sprintf('%s | z=%d/%d', getAnimalID(fileLabel), zSel, nZ);

            for si = 1:nSlides
                i0 = (si-1)*perSlide + 1;
                i1 = min(si*perSlide, numel(tilePNG));
                idx = i0:i1;
                if si == 1
                    tStr = fullTitle;
                else
                    tStr = shortTitle;
                end

                outSlide = fullfile(tmpSLD, sprintf('slide_z%02d_%02d.png', zSel, si));
                renderSlideMontagePNG(outSlide, tilePNG(idx), tileLBL(idx), cm, caxV, tStr, footerInfo, EXPORT_DPI_SLIDES);
                if exist(outSlide, 'file') ~= 2
                    error('Failed to create slide PNG: %s', outSlide);
                end

                slidePNGs{end+1} = outSlide; %#ok<AGROW>
                slideSpecs{end+1} = struct('pngList', {tilePNG(idx)}); %#ok<AGROW>

                try
                    set(info1, 'String', sprintf('Building PPT slides... slice %d/%d | slide %d/%d', ...
                        zSel, nZ, si, nSlides));
                    set(info1, 'TooltipString', outDir);
                    drawnow limitrate;
                catch
                end
            end
        end

        if ~isempty(figT) && isgraphics(figT)
            close(figT); figT = [];
        end

        if isempty(slidePNGs)
            errordlg('No windows exported (maybe too short recording or window settings).', 'SCM series');
            return;
        end

        pptPath = '';
        pptMsg = '';
        if doPPT
            if canUsePptApi()
                pptPath = chooseShortPptPath(outDir, fileLabel, stamp);
                try
                    writePptFromSlidePNGsWithEditableTiles(pptPath, slidePNGs, slideSpecs);
                    if exist(pptPath, 'file') ~= 2
                        error('PPT writer finished, but file was not found on disk.');
                    end
                    pptMsg = 'PPT + PNGs';
                catch MEppt
                    warning('[SCM SERIES] PPT creation failed: %s', MEppt.message);
                    pptPath = '';
                    pptMsg = ['PNGs only (PPT failed: ' MEppt.message ')'];
                end
            else
                pptMsg = 'PNGs only (PowerPoint API unavailable)';
            end
        else
            pptMsg = 'PNGs only';
        end

        try
            if exist(tmpSLD, 'dir') == 7, rmdir(tmpSLD, 's'); end
        catch
        end

        if isempty(pptPath)
            set(info1, 'String', ['DONE. Saved: ' shortenPath(outDir,80) '  (' pptMsg ')'], 'TooltipString', outDir);
        else
            set(info1, 'String', ['DONE. Saved: ' shortenPath(outDir,80) '  (PPT + PNGs)'], 'TooltipString', outDir);
        end

        fprintf('[SCM SERIES] DONE. Folder: %s\n', outDir);
        if ~isempty(pptPath), fprintf('[SCM SERIES] PPT: %s\n', pptPath); end

    catch ME
        try, if ~isempty(figT) && isgraphics(figT), close(figT); end, catch, end
        try, if ~isempty(tmpSLD) && exist(tmpSLD,'dir') == 7, rmdir(tmpSLD,'s'); end, catch, end
        errordlg(ME.message, 'Export SCM series failed');
    end
end

function releaseSeriesExportLock()
    state.seriesExportBusy = false;
    state.lastSeriesExportStampSec = now * 86400;
end


function renderSingleScmSlidePNG(outFile, imagePng, titleLabel, zSel, nZSel, caxV, cm)
    figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
    set(figS, 'Units','inches', 'Position',[0.5 0.5 13.333 7.5]);
    set(figS, 'PaperPositionMode','auto');

    ttl = sprintf('%s | z=%d/%d', makeFullTitle(titleLabel), zSel, nZSel);
    annotation(figS, 'textbox', [0.02 0.90 0.96 0.08], ...
        'String', ttl, 'Color','w', 'EdgeColor','none', 'FontName','Arial', ...
        'FontSize',16, 'FontWeight','bold', 'HorizontalAlignment','center', ...
        'Interpreter','none');

    axI = axes('Parent', figS, 'Position', [0.08 0.10 0.82 0.78]);
    imshow(imread(imagePng), 'Parent', axI);
    axis(axI, 'off');

    axCB = axes('Parent', figS, 'Position', [0.885 0.16 0.001 0.66], ...
        'Visible','off', 'XTick',[], 'YTick',[], 'XColor','none', 'YColor','none', 'Box','off');
    imagesc(axCB, [0 1; 0 1]);
    colormap(axCB, cm);
    caxis(axCB, caxV);
    cbx = colorbar(axCB, 'Position', [0.895 0.16 0.015 0.66]);
    cbx.Color = 'w';
    cbx.FontName = 'Arial';
    cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)';
    cbx.Label.Color = 'w';
    cbx.TickDirection = 'out';
    cbx.Box = 'off';
    try, cbx.AxisLocation = 'out'; catch, end

    print(figS, outFile, '-dpng', '-r220', '-opengl');
    close(figS);
end

function renderSlideMontagePNG(outFile, pngList, lblList, cm, caxV, titleStr, footerStr, dpiVal)
    figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
    set(figS, 'Units','inches', 'Position',[0.5 0.5 13.333 7.5]);
    set(figS, 'PaperPositionMode','auto');

    annotation(figS, 'textbox', [0.02 0.885 0.96 0.11], ...
        'String', titleStr, 'Color','w', 'EdgeColor','none', 'FontName','Arial', ...
        'FontSize',14, 'FontWeight','bold', 'HorizontalAlignment','center', ...
        'Interpreter','none');

    annotation(figS, 'textbox', [0.42 0.01 0.56 0.06], ...
        'String', footerStr, 'Color','w', 'EdgeColor','none', 'FontName','Arial', ...
        'FontSize',11, 'FontWeight','bold', 'HorizontalAlignment','right', ...
        'Interpreter','none');

    axCB = axes('Parent', figS, 'Position', [0.010 0.14 0.001 0.74], ...
        'Visible','off', 'XTick',[], 'YTick',[], 'XColor','none', 'YColor','none', 'Box','off');
    imagesc(axCB, [0 1; 0 1]);
    colormap(axCB, cm);
    caxis(axCB, caxV);
    cbx = colorbar(axCB, 'Position', [0.018 0.14 0.015 0.74]);
    cbx.Color = 'w';
    cbx.FontName = 'Arial';
    cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)';
    cbx.Label.Color = 'w';
    cbx.TickDirection = 'out';
    cbx.Box = 'off';
    try, cbx.AxisLocation = 'out'; catch, end

    x0 = 0.095;
    x1 = 0.98;
    yBot = 0.12;
    yTop = 0.86;
    gridH = (yTop - yBot);
    rowGap = 0.06;
    colGap = 0.02;
    cellH = (gridH - rowGap) / 2;
    cellW = (x1 - x0 - 2*colGap) / 3;

    for k = 1:3
        if k > numel(pngList), break; end
        x = x0 + (k-1)*(cellW+colGap);
        y = yBot + cellH + rowGap;
        axI = axes('Parent', figS, 'Position', [x y cellW cellH]);
        imshow(imread(pngList{k}), 'Parent', axI);
        axis(axI, 'off');
        annotation(figS, 'textbox', [x y+cellH+0.005 cellW 0.035], ...
            'String', lblList{k}, 'Color','w', 'EdgeColor','none', ...
            'FontName','Arial', 'FontSize',13, 'FontWeight','bold', ...
            'HorizontalAlignment','center', 'Interpreter','none');
    end

    for k = 4:6
        if k > numel(pngList), break; end
        ccol = k - 3;
        x = x0 + (ccol-1)*(cellW+colGap);
        y = yBot;
        axI = axes('Parent', figS, 'Position', [x y cellW cellH]);
        imshow(imread(pngList{k}), 'Parent', axI);
        axis(axI, 'off');
        annotation(figS, 'textbox', [x y+cellH+0.005 cellW 0.035], ...
            'String', lblList{k}, 'Color','w', 'EdgeColor','none', ...
            'FontName','Arial', 'FontSize',13, 'FontWeight','bold', ...
            'HorizontalAlignment','center', 'Interpreter','none');
    end

    print(figS, outFile, '-dpng', sprintf('-r%d', dpiVal), '-opengl');
    close(figS);
end

function writePptFromSlidePNGs(pptPath, slidePNGs)
    import mlreportgen.ppt.*
    if nargin < 2 || isempty(slidePNGs)
        error('No slide PNGs were provided for PPT export.');
    end
    pptDir = fileparts(pptPath);
    safeMkdirIfNeeded(pptDir);
    if exist(pptPath, 'file') == 2
        try
            delete(pptPath);
        catch
            error('Could not overwrite existing PPT file: %s', pptPath);
        end
    end
    ppt = [];
    try
        ppt = Presentation(pptPath);
        open(ppt);
        for i = 1:numel(slidePNGs)
            imgFile = slidePNGs{i};
            if exist(imgFile, 'file') ~= 2
                warning('Slide image missing, skipping: %s', imgFile);
                continue;
            end
            try
                slide = add(ppt, 'Blank');
            catch
                slide = add(ppt);
            end
            pic = Picture(imgFile);
            pic.X = '0in';
            pic.Y = '0in';
            pic.Width = '13.333in';
            pic.Height = '7.5in';
            add(slide, pic);
        end
        close(ppt);
    catch ME
        try, if ~isempty(ppt), close(ppt); end, catch, end
        error('PowerPoint export failed: %s', ME.message);
    end
    pause(0.3);
    if exist(pptPath, 'file') ~= 2
        error('PowerPoint file was not created: %s', pptPath);
    end
    dpp = dir(pptPath);
    if isempty(dpp) || dpp.bytes <= 0
        error('PowerPoint file exists but is empty or corrupt: %s', pptPath);
    end
end

function writePptFromSlidePNGsWithEditableTiles(pptPath, slidePNGs, slideSpecs)
    import mlreportgen.ppt.*
    if nargin < 2 || isempty(slidePNGs)
        error('No slide PNGs were provided for PPT export.');
    end
    pptDir = fileparts(pptPath);
    safeMkdirIfNeeded(pptDir);
    if exist(pptPath, 'file') == 2
        try
            delete(pptPath);
        catch
            error('Could not overwrite existing PPT file: %s', pptPath);
        end
    end

    slideW = 13.333;
    slideH = 7.5;
    x0 = 0.08;
    colGap = 0.02;
    yBot = 0.12;
    rowGap = 0.06;
    cellH = (0.86 - 0.12 - rowGap) / 2;
    cellW = (0.98 - 0.08 - 2*colGap) / 3;

    ppt = [];
    try
        ppt = Presentation(pptPath);
        open(ppt);
        for i = 1:numel(slidePNGs)
            bgFile = slidePNGs{i};
            if exist(bgFile, 'file') ~= 2
                warning('Slide background missing, skipping: %s', bgFile);
                continue;
            end
            try
                slide = add(ppt, 'Blank');
            catch
                slide = add(ppt);
            end

            bgPic = Picture(bgFile);
            bgPic.X = '0in';
            bgPic.Y = '0in';
            bgPic.Width = sprintf('%.3fin', slideW);
            bgPic.Height = sprintf('%.3fin', slideH);
            add(slide, bgPic);

            if i <= numel(slideSpecs) && isfield(slideSpecs{i}, 'pngList')
                pngList = slideSpecs{i}.pngList;
                nThis = min(6, numel(pngList));
                for k = 1:nThis
                    imgFile = pngList{k};
                    if exist(imgFile, 'file') ~= 2, continue; end
                    if k <= 3
                        cc = k - 1;
                        yNorm = yBot + cellH + rowGap;
                    else
                        cc = k - 4;
                        yNorm = yBot;
                    end
                    xNorm = x0 + cc*(cellW + colGap);
                    xIn = xNorm * slideW;
                    wIn = cellW * slideW;
                    hIn = cellH * slideH;
                    yIn = (1 - (yNorm + cellH)) * slideH;
                    pic = Picture(imgFile);
                    pic.X = sprintf('%.3fin', xIn);
                    pic.Y = sprintf('%.3fin', yIn);
                    pic.Width = sprintf('%.3fin', wIn);
                    pic.Height = sprintf('%.3fin', hIn);
                    add(slide, pic);
                end
            end
        end
        close(ppt);
    catch ME
        try, if ~isempty(ppt), close(ppt); end, catch, end
        error('PowerPoint export failed: %s', ME.message);
    end
    pause(0.3);
    if exist(pptPath, 'file') ~= 2
        error('PowerPoint file was not created: %s', pptPath);
    end
    dpp = dir(pptPath);
    if isempty(dpp) || dpp.bytes <= 0
        error('PowerPoint file exists but is empty or corrupt: %s', pptPath);
    end
end

function tf = canUsePptApi()
    tf = false;
    try
        tf = ~isempty(which('mlreportgen.ppt.Presentation'));
    catch
        tf = false;
    end
end

function pptPath = chooseShortPptPath(outDir, ~, stamp)
    pptPath = fullfile(outDir, sprintf('SCM_series_%s.pptx', stamp));
end

function pptPath = chooseShortSinglePptPath(outDir, ~, stamp)
    pptPath = fullfile(outDir, sprintf('SCM_%s.pptx', stamp));
end

function exportForGroupAnalysisCB(~,~)
    if ~state.isAtlasWarped
        warndlg(['Export for Group Analysis requires atlas-warped functional data.' newline ...
            'Please use "WARP FUNCTIONAL TO ATLAS" first.'], 'Group Analysis export');
        return;
    end
    try
        Pexp = getGroupBundleExportPathsLocal();
        safeMkdirIfNeeded(Pexp.bundleRoot); safeMkdirIfNeeded(Pexp.bundleDir);
        [b0,b1] = parseRangeSafe(getStr(ebBase),30,240);
        [s0,s1] = parseRangeSafe(getStr(ebSig),840,900);
        sigma = str2double(getStr(ebSigma)); if ~isfinite(sigma), sigma = 1; end
        thr = str2double(getStr(ebThr)); if ~isfinite(thr), thr = 0; end
        stamp = datestr(now,'yyyymmdd_HHMMSS');
        outFile = fullfile(Pexp.bundleDir, sprintf('SCM_GroupExport_%s_%s_%s_%s.mat', Pexp.animalID, Pexp.session, Pexp.scanID, stamp));
        G = struct();
        G.kind = 'SCM_GROUP_EXPORT'; G.version = '1.0'; G.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
        G.fileLabel = fileLabel; G.loadedFile = safeParFieldLocal('loadedFile'); G.loadedPath = safeParFieldLocal('loadedPath'); G.exportPath = safeParFieldLocal('exportPath');
        G.animalID = Pexp.animalID; G.session = Pexp.session; G.scanID = Pexp.scanID; G.subjectKey = Pexp.subjectKey;
        G.isAtlasWarped = logical(state.isAtlasWarped); G.atlasTransformFile = state.atlasTransformFile; G.atlasSliceIndex = state.z;
        G.baseWindowStr = getStr(ebBase); G.sigWindowStr = getStr(ebSig); G.baseWindowSec = [b0 b1]; G.sigWindowSec = [s0 s1]; G.sigma = sigma;
        G.display = struct('threshold',thr,'caxis',state.cax,'alphaPercent',get(slAlpha,'Value'), ...
    'alphaModOn',logical(state.alphaModOn),'modMin',state.modMin,'modMax',state.modMax, ...
    'colormapName',getCurrentPopupStringLocal(popMap),'signMode',state.signMode);

% Store exact SCM colormap for GroupAnalysis PPT export.
try
    G.display.cmapMatrix = colormap(ax);
catch
    G.display.cmapMatrix = getCmap(getCurrentPopupStringLocal(popMap), 256);
end

% Useful marker so GroupAnalysis knows this bundle can be exported SCM-style.
G.display.exportStyle = 'SCM_gui_6tile_black_editable_ppt';
        G.TR = TR; G.tsec = tsec; G.tmin = tmin; G.nY = nY; G.nX = nX; G.nZ = nZ; G.nT = nT;
        G.pscAtlas4D = PSC; G.scmMapSignedAtlas = state.lastSignedMap; G.scmMapDisplayAtlas = get(hOV,'CData'); G.alphaAtlas = get(hOV,'AlphaData');
        G.underlayAtlas = bg; G.underlayInfo = struct();
        G.underlayInfo.isColorUnderlay = logical(state.isColorUnderlay);
        G.underlayInfo.regionLabelUnderlay = state.regionLabelUnderlay;
        G.underlayInfo.regionInfo = state.regionInfo;
        G.mask2DCurrentSlice = mask2D; G.maskAtlas = passedMask; G.maskIsInclude = passedMaskIsInclude; G.injectionSide = '?';
        save(outFile, 'G', '-v7.3');
        set(info1,'String',['Group bundle saved: ' shortenPath(outFile,85)], 'TooltipString', outFile);
        msgbox(sprintf('Saved GroupAnalysis bundle:\n%s', outFile), 'SCM group export');
    catch ME
        errordlg(ME.message, 'Export for Group Analysis failed');
    end
end


function openGroupBundleCB(~,~)
    startPath = getGroupBundleOpenStartPathLocal();

    [f,p] = uigetfileStartIn( ...
        {'SCM_GroupExport*.mat;*.mat', 'SCM Group bundle (*.mat)'; ...
         '*.mat', 'MAT files (*.mat)'; ...
         '*.*', 'All files (*.*)'}, ...
        'Open SCM GroupAnalysis bundle', startPath);

    if isequal(f,0)
        return;
    end

    fullf = fullfile(p,f);

    try
        G = loadScmGroupBundleLocal(fullf);
        applyScmGroupBundleLocal(G, fullf);
    catch ME
        errordlg(ME.message, 'Open SCM group bundle failed');
    end
end


function tf = isScmGroupBundleFileLocal(fullf)
    tf = false;

    try
        if isempty(fullf) || exist(fullf,'file') ~= 2
            return;
        end

        W = whos('-file', fullf);
        names = {W.name};

        if any(strcmp(names, 'G'))
            tf = true;
            return;
        end

        % Fallback: detect by filename.
        [~,nm,~] = fileparts(fullf);
        nm = lower(nm);

        if ~isempty(strfind(nm, 'scm_groupexport')) || ...
                ~isempty(strfind(nm, 'group_export')) || ...
                ~isempty(strfind(nm, 'scm_group'))
            tf = true;
        end

    catch
        tf = false;
    end
end


function G = loadScmGroupBundleLocal(fullf)
    if isempty(fullf) || exist(fullf,'file') ~= 2
        error('Group bundle file not found: %s', fullf);
    end

    S = load(fullf);

    if isfield(S,'G') && isstruct(S.G)
        G = S.G;
    else
        % Fallback: search for a struct that looks like an SCM group export.
        G = [];
        fn = fieldnames(S);

        for ii = 1:numel(fn)
            v = S.(fn{ii});

            if isstruct(v)
                if isfield(v,'kind') && strcmpi(char(v.kind), 'SCM_GROUP_EXPORT')
                    G = v;
                    break;
                end

                if isfield(v,'pscAtlas4D') || isfield(v,'underlayAtlas') || isfield(v,'scmMapSignedAtlas')
                    G = v;
                    break;
                end
            end
        end

        if isempty(G)
            error(['This MAT file does not look like an SCM GroupAnalysis bundle.' newline ...
                   'Expected variable G with fields like G.pscAtlas4D and G.underlayAtlas.']);
        end
    end

    if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
        error(['The selected bundle has no G.pscAtlas4D field.' newline ...
               'This means it cannot be reopened as a full SCM dataset.']);
    end
end


function applyScmGroupBundleLocal(G, fullf)

    % ---------------------------------------------------------
    % 1) Load PSC data from bundle
    % ---------------------------------------------------------
    PSC = G.pscAtlas4D;

    if ~(isnumeric(PSC) || islogical(PSC))
        error('G.pscAtlas4D is not numeric.');
    end

    if ~(ndims(PSC) == 3 || ndims(PSC) == 4)
        error('G.pscAtlas4D must be [Y X T] or [Y X Z T].');
    end

    % Treat loaded bundle as the new native/base state for this SCM session.
    origPSC = PSC;

    % ---------------------------------------------------------
    % 2) Load TR if present
    % ---------------------------------------------------------
    if isfield(G,'TR') && ~isempty(G.TR) && isnumeric(G.TR) && isscalar(G.TR) && isfinite(G.TR) && G.TR > 0
        TR = double(G.TR);
    end

    % Refresh nY/nX/nZ/nT/tsec/tmin after replacing PSC.
    refreshDimsAfterPSCChange();

    % ---------------------------------------------------------
    % 3) Load underlay
    % ---------------------------------------------------------
    if isfield(G,'underlayAtlas') && ~isempty(G.underlayAtlas)
        bg = G.underlayAtlas;
    else
        bg = makeNativeFallbackUnderlayFromPSC(PSC);
    end

    origBG = bg;

    % ---------------------------------------------------------
    % 4) Restore underlay metadata if present
    % ---------------------------------------------------------
    ensureUnderlayStateFields();

    state.isColorUnderlay = false;
    state.regionLabelUnderlay = [];
    state.regionColorLUT = [];
    state.regionInfo = struct();

    if isfield(G,'underlayInfo') && isstruct(G.underlayInfo)
        UI = G.underlayInfo;

        if isfield(UI,'isColorUnderlay') && ~isempty(UI.isColorUnderlay)
            state.isColorUnderlay = logical(UI.isColorUnderlay);
        end

        if isfield(UI,'regionLabelUnderlay') && ~isempty(UI.regionLabelUnderlay)
            state.regionLabelUnderlay = UI.regionLabelUnderlay;
        end

        if isfield(UI,'regionInfo') && ~isempty(UI.regionInfo)
            state.regionInfo = UI.regionInfo;
        end
    else
        applyUnderlayMeta(defaultUnderlayMeta(), bg);
    end

    % Important for Step Motor nZ == 3:
    % avoid interpreting Y X 3 grayscale slices as one RGB image.
    try
        if nZ > 1 && ndims(bg) == 3 && size(bg,3) == nZ
            state.isColorUnderlay = false;
        end
    catch
    end

    % ---------------------------------------------------------
    % 5) Load mask if present
    % ---------------------------------------------------------
    passedMask = [];
    passedMaskIsInclude = true;

    if isfield(G,'maskAtlas') && ~isempty(G.maskAtlas)
        passedMask = fitBundleMaskToCurrentScm(G.maskAtlas);
    elseif isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
        passedMask = fitBundleMaskToCurrentScm(G.mask2DCurrentSlice);
    end

    if isfield(G,'maskIsInclude') && ~isempty(G.maskIsInclude)
        passedMaskIsInclude = logical(G.maskIsInclude);
    end

    origPassedMask = passedMask;

    % ---------------------------------------------------------
    % 6) Restore label/title/meta
    % ---------------------------------------------------------
    if isfield(G,'fileLabel') && ~isempty(G.fileLabel)
        try
            fileLabel = char(G.fileLabel);
        catch
        end
    else
        [~,nm,~] = fileparts(fullf);
        fileLabel = nm;
    end

    state.isAtlasWarped = true;
    state.isStepMotorAtlasWarped = false;

    if isfield(G,'atlasTransformFile') && ~isempty(G.atlasTransformFile)
        try
            state.atlasTransformFile = char(G.atlasTransformFile);
            state.lastAtlasTransformFile = char(G.atlasTransformFile);
        catch
            state.atlasTransformFile = '';
            state.lastAtlasTransformFile = '';
        end
    else
        state.atlasTransformFile = fullf;
        state.lastAtlasTransformFile = fullf;
    end

    try
        if isfield(G,'atlasSliceIndex') && ~isempty(G.atlasSliceIndex) && isfinite(G.atlasSliceIndex)
            state.z = clamp(round(G.atlasSliceIndex), 1, nZ);
        else
            state.z = clamp(state.z, 1, nZ);
        end
    catch
        state.z = clamp(state.z, 1, nZ);
    end

    % ---------------------------------------------------------
    % 7) Restore GUI windows/settings
    % ---------------------------------------------------------
    if isfield(G,'baseWindowStr') && ~isempty(G.baseWindowStr)
        set(ebBase, 'String', char(G.baseWindowStr));
    elseif isfield(G,'baseWindowSec') && numel(G.baseWindowSec) >= 2
        set(ebBase, 'String', sprintf('%g-%g', G.baseWindowSec(1), G.baseWindowSec(2)));
    end

    if isfield(G,'sigWindowStr') && ~isempty(G.sigWindowStr)
        set(ebSig, 'String', char(G.sigWindowStr));
    elseif isfield(G,'sigWindowSec') && numel(G.sigWindowSec) >= 2
        set(ebSig, 'String', sprintf('%g-%g', G.sigWindowSec(1), G.sigWindowSec(2)));
    end

    if isfield(G,'sigma') && ~isempty(G.sigma) && isnumeric(G.sigma) && isscalar(G.sigma) && isfinite(G.sigma)
        set(ebSigma, 'String', sprintf('%g', G.sigma));
    end

    if isfield(G,'display') && isstruct(G.display)
        applyDisplaySettingsFromGroupBundleLocal(G.display);
    end

    % ---------------------------------------------------------
    % 8) Reset ROIs and redraw
    % ---------------------------------------------------------
    try
        set(btnWarpAtlas, 'String', 'GROUP BUNDLE LOADED');
    catch
    end

    try
        set(txtTitle, 'String', sprintf('%s | loaded SCM group bundle', makeFullTitle(fileLabel)));
    catch
        set(txtTitle, 'String', 'Loaded SCM group bundle');
    end

    resetRoisAndRefreshAfterDataChange();

    if isfield(G,'display') && isstruct(G.display)
        applyDisplaySettingsFromGroupBundleLocal(G.display);
        updateView();
    end

    mask2D = getMaskForCurrentSlice();

    try
        set(hBG, 'CData', renderUnderlayRGB(getBg2DForSlice(state.z)));
    catch
    end

    updateSliceIndicators();
    updateInfoLines();
    computeSCM();

    set(info1, 'String', ['Loaded SCM group bundle: ' shortenPath(fullf,85)], ...
        'TooltipString', fullf);

    fprintf('[SCM] Loaded GroupAnalysis SCM bundle:\n%s\n', fullf);
end


function applyDisplaySettingsFromGroupBundleLocal(D)

    if isempty(D) || ~isstruct(D)
        return;
    end

    try
        if isfield(D,'threshold') && ~isempty(D.threshold) && isfinite(D.threshold)
            set(ebThr, 'String', sprintf('%g', D.threshold));
        end
    catch
    end

    try
        if isfield(D,'caxis') && numel(D.caxis) >= 2 && all(isfinite(D.caxis(1:2)))
            state.cax = double(D.caxis(1:2));
            if state.cax(2) < state.cax(1)
                state.cax = fliplr(state.cax);
            end
            set(ebCax, 'String', sprintf('%g %g', state.cax(1), state.cax(2)));
        end
    catch
    end

    try
        if isfield(D,'alphaPercent') && ~isempty(D.alphaPercent) && isfinite(D.alphaPercent)
            set(slAlpha, 'Value', clamp(double(D.alphaPercent), 0, 100));
        end
    catch
    end

    try
        if isfield(D,'alphaModOn') && ~isempty(D.alphaModOn)
            state.alphaModOn = logical(D.alphaModOn);
            set(cbAlphaMod, 'Value', double(state.alphaModOn));
        end
    catch
    end

    try
        if isfield(D,'modMin') && ~isempty(D.modMin) && isfinite(D.modMin)
            state.modMin = double(D.modMin);
            set(ebModMin, 'String', sprintf('%g', state.modMin));
        end
    catch
    end

    try
        if isfield(D,'modMax') && ~isempty(D.modMax) && isfinite(D.modMax)
            state.modMax = double(D.modMax);
            set(ebModMax, 'String', sprintf('%g', state.modMax));
        end
    catch
    end

    try
        if isfield(D,'signMode') && ~isempty(D.signMode) && isfinite(D.signMode)
            state.signMode = clamp(round(double(D.signMode)), 1, 3);
            state.prevSignMode = state.signMode;
            set(popSignMode, 'Value', state.signMode);
        end
    catch
    end

    try
        if isfield(D,'colormapName') && ~isempty(D.colormapName)
            cmName = char(D.colormapName);
            set(popMap, 'Value', findPopupIndexByName(popMap, cmName));
        end
    catch
    end

    alphaModToggled();

    try
        if isfield(D,'cmapMatrix') && ~isempty(D.cmapMatrix) && size(D.cmapMatrix,2) == 3
            colormap(ax, D.cmapMatrix);
        end
    catch
    end
end


function startPath = getGroupBundleOpenStartPathLocal()
    try
        root = getDatasetRootForSelectors();
        root = guessAnalysedRoot(root);

        cand = { ...
            fullfile(root,'GroupAnalysis','Bundles','SCM'), ...
            fullfile(root,'GroupAnalysis','Bundles'), ...
            fullfile(root,'SCM'), ...
            fullfile(root,'Bundles'), ...
            root, ...
            getStartPath(), ...
            pwd};

        startPath = firstExistingDir(cand);
    catch
        startPath = pwd;
    end
end

function applyExportWindowPatches(ax2, yl)
    [b0,b1] = parseRangeSafe(getStr(ebBase),30,240);
    [s0,s1] = parseRangeSafe(getStr(ebSig),840,900);
    if isVolMode
        b0s = (clamp(round(b0),1,nT)-1)*TR; b1s = (clamp(round(b1),1,nT)-1)*TR;
        s0s = (clamp(round(s0),1,nT)-1)*TR; s1s = (clamp(round(s1),1,nT)-1)*TR;
    else
        b0s = b0; b1s = b1; s0s = s0; s1s = s1;
    end
    if b1s < b0s, tmp=b0s; b0s=b1s; b1s=tmp; end
    if s1s < s0s, tmp=s0s; s0s=s1s; s1s=tmp; end
    yr = yl(2)-yl(1); if ~isfinite(yr) || yr <= 0, yr = 1; end
    yTxt = yl(2) - 0.06*yr;
    patch(ax2,[b0s b1s b1s b0s]/60,[yl(1) yl(1) yl(2) yl(2)],[1.0 0.2 0.2],'FaceAlpha',0.16,'EdgeColor','none');
    patch(ax2,[s0s s1s s1s s0s]/60,[yl(1) yl(1) yl(2) yl(2)],[1.0 0.6 0.15],'FaceAlpha',0.16,'EdgeColor','none');
    text(ax2,mean([b0s b1s])/60,yTxt,'Bas.','Color',[1.00 0.35 0.35],'FontSize',11,'FontWeight','bold','HorizontalAlignment','center','BackgroundColor',[0 0 0],'Margin',1,'Clipping','on');
    text(ax2,mean([s0s s1s])/60,yTxt,'Sig.','Color',[1.00 0.80 0.35],'FontSize',11,'FontWeight','bold','HorizontalAlignment','center','BackgroundColor',[0 0 0],'Margin',1,'Clipping','on');
    try, uistack(findobj(ax2,'Type','line'),'top'); catch, end
end

%% ==========================================================
% VIDEO GUI
%% ==========================================================
function openVideo(~,~)
    try
        bStart = baseStart0; bEnd = baseEnd0;
        launchCfg = showScmVideoSetupDialogLocal('Video GUI', bStart, bEnd, 1);
        if isempty(launchCfg) || ~isstruct(launchCfg) || ~isfield(launchCfg,'cancelled') || launchCfg.cancelled, return; end
        baselineLocal = baseline;
        if ~isstruct(baselineLocal), baselineLocal = struct(); end
        baselineLocal.start = launchCfg.baselineStart;
        baselineLocal.end = launchCfg.baselineEnd;
        baselineLocal.mode = 'sec';
        parVideo = par;
        parVideo.selectorRoot = getDatasetRootForSelectors();
        parVideo.maskStartPath = getMaskStartPath();
        parVideo.underlayStartPath = getUnderlayStartPathFast();
        parVideo.transformStartPath = getTransformStartPath();
        play_fusi_video_final(PSC, PSC, PSC, bg, parVideo, 10, 240, TR, (nT-1)*TR, baselineLocal, ...
            passedMask, passedMaskIsInclude, nT, false, struct(), fileLabel, state.z);
    catch ME
        errordlg(ME.message, 'Open Video GUI failed');
    end
end

function cfg = showScmVideoSetupDialogLocal(titleStr, bStart, bEnd, interpDefault)
    cfg = [];
    try
        if exist('showScmVideoSetupDialog','file') == 2
            cfg = showScmVideoSetupDialog(titleStr, bStart, bEnd, interpDefault);
            return;
        end
    catch
    end
    a = inputdlg({'Baseline start (s):','Baseline end (s):','Interpolation factor:'}, titleStr, 1, ...
        {num2str(bStart), num2str(bEnd), num2str(interpDefault)});
    if isempty(a)
        cfg = struct('cancelled', true);
        return;
    end
    cfg = struct();
    cfg.cancelled = false;
    cfg.baselineStart = str2double(a{1}); if ~isfinite(cfg.baselineStart), cfg.baselineStart = bStart; end
    cfg.baselineEnd = str2double(a{2}); if ~isfinite(cfg.baselineEnd), cfg.baselineEnd = bEnd; end
    cfg.interp = str2double(a{3}); if ~isfinite(cfg.interp), cfg.interp = interpDefault; end
end

function showHelp(~,~)
    bgFig = [0.06 0.06 0.07]; bgText = [0.12 0.12 0.14]; colTxt = [0.94 0.94 0.96];
    hf = figure('Name','SCM Help','Color',bgFig,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
        'Resize','on','Position',[200 100 980 780],'WindowStyle','modal');
    guide = { ...
        'SCM Viewer - Guide'; ''; ...
        'OVERLAY'; ...
        '  - Threshold hides low |SCM|.'; ...
        '  - Display range sets overlay caxis.'; ...
        '  - Alpha modulation ON ramps alpha between Mod Min and Mod Max.'; ''; ...
        'UNDERLAY / FOLDERS'; ...
        '  - LOAD MASK starts in Masks/Mask/ROI/Registration first.'; ...
        '  - LOAD NEW UNDERLAY starts in Visualization first.'; ...
        '  - WARP FUNCTIONAL TO ATLAS starts in Registration2D/Registration first.'; ''; ...
        'ROI'; ...
        '  - Hover shows live ROI PSC.'; ...
        '  - Left click adds ROI.'; ...
        '  - Right click removes nearest ROI.'; ''; ...
        'EXPORT'; ...
        '  - Export ROI TXT, SCM image, time-course PNG, SCM series, and GroupAnalysis bundle.'};
    uicontrol(hf,'Style','edit','Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
        'String',strjoin(guide,newline),'Max',2,'Min',0,'BackgroundColor',bgText,'ForegroundColor',colTxt, ...
        'FontName','Arial','FontSize',13,'HorizontalAlignment','left');
end

%% ==========================================================
% ROI / TIME COURSE HELPERS
%% ==========================================================
function tc = computeRoiPSC_atSlice(zSel, x1, x2, y1, y2)
    try
        if ndims(PSC) == 3
            blk = PSC(y1:y2, x1:x2, :);
        else
            zSel = clamp(round(zSel),1,nZ);
            blk = PSC(y1:y2, x1:x2, zSel, :);
        end
        tc = squeeze(mean(mean(blk, 1), 2));
        tc = tc(:).';
    catch
        tc = [];
    end
end

function tc = computeRoiPSC_idx(zSel, x1, x2, y1, y2, idx)
    try
        if ndims(PSC) == 3
            blk = PSC(y1:y2, x1:x2, idx);
        else
            zSel = clamp(round(zSel),1,nZ);
            blk = PSC(y1:y2, x1:x2, zSel, idx);
        end
        tc = squeeze(mean(mean(blk, 1), 2));
        tc = tc(:).';
    catch
        tc = [];
    end
end

function redrawROIsForCurrentSlice()
    deleteIfValid(roiHandles); roiHandles = gobjects(0);
    deleteIfValid(roiPlotPSC); roiPlotPSC = gobjects(0);
    deleteIfValid(roiTextHandles); roiTextHandles = gobjects(0);
    ROI = ROI_byZ{state.z};
    if isempty(ROI), applyTimecourseAxisMode(); return; end
    for k = 1:numel(ROI)
        r = ROI(k);
        roiHandles(end+1) = rectangle(ax,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor',r.color,'LineWidth',2); %#ok<AGROW>
        roiTextHandles(end+1) = text(ax,r.x1,max(1,r.y1-2),sprintf('%d',r.id), ...
            'Color',r.color,'FontWeight','bold','FontSize',12,'Interpreter','none', ...
            'VerticalAlignment','bottom','BackgroundColor',[0 0 0],'Margin',1); %#ok<AGROW>
        tc = computeRoiPSC_atSlice(state.z, r.x1, r.x2, r.y1, r.y2);
        if numel(tc) == nT
            roiPlotPSC(end+1) = plot(axTC,tmin,tc,':','Color',r.color,'LineWidth',2.4); %#ok<AGROW>
        end
    end
    applyTimecourseAxisMode();
end

function deleteIfValid(h)
    if isempty(h), return; end
    for i = 1:numel(h)
        if isgraphics(h(i)), delete(h(i)); end
    end
end

function tcAxisModeChanged(~,~)
    state.tcFixY = logical(get(cbTcFixY,'Value'));
    state.tcFixX = logical(get(cbTcFixX,'Value'));
    [y0,y1] = parseAxisPair(getStr(ebTcYLim), state.tcYLim(1), state.tcYLim(2));
    [x0,x1] = parseAxisPair(getStr(ebTcXLim), state.tcXLim(1), state.tcXLim(2));
    state.tcYLim = [y0 y1]; state.tcXLim = [x0 x1];
    if state.tcFixY, set(ebTcYLim,'Enable','on','BackgroundColor',bgEdit); else, set(ebTcYLim,'Enable','off','BackgroundColor',bgEditDis); end
    if state.tcFixX, set(ebTcXLim,'Enable','on','BackgroundColor',bgEdit); else, set(ebTcXLim,'Enable','off','BackgroundColor',bgEditDis); end
    applyTimecourseAxisMode();
end

function tcYFromCax(~,~)
    set(ebTcYLim, 'String', sprintf('%g %g', state.cax(1), state.cax(2)));
    set(cbTcFixY, 'Value', 1);
    tcAxisModeChanged();
end

function tcXAll(~,~)
    set(ebTcXLim, 'String', sprintf('%g %g', tmin(1), tmin(end)));
    set(cbTcFixX, 'Value', 1);
    tcAxisModeChanged();
end

function applyTimecourseAxisMode()
    if ~isgraphics(axTC), return; end
    [xAuto, yAuto] = getAutoTcLimits();
    if state.tcFixX, xUse = state.tcXLim; else, xUse = xAuto; end
    if state.tcFixY, yUse = state.tcYLim; else, yUse = yAuto; end
    set(axTC, 'XLim', xUse, 'YLim', yUse);
    applyTimecourseXTicks(xUse);
    drawTimeWindows();
end

function [xLimAuto, yLimAuto] = getAutoTcLimits()
    xAll = []; yAll = [];
    if isgraphics(hLivePSC) && strcmp(get(hLivePSC,'Visible'),'on')
        xAll = [xAll get(hLivePSC,'XData')]; %#ok<AGROW>
        yAll = [yAll get(hLivePSC,'YData')]; %#ok<AGROW>
    end
    for kk = 1:numel(roiPlotPSC)
        if isgraphics(roiPlotPSC(kk)) && strcmp(get(roiPlotPSC(kk),'Visible'),'on')
            xAll = [xAll get(roiPlotPSC(kk),'XData')]; %#ok<AGROW>
            yAll = [yAll get(roiPlotPSC(kk),'YData')]; %#ok<AGROW>
        end
    end
    xAll = xAll(isfinite(xAll)); yAll = yAll(isfinite(yAll));
    if numel(xAll) >= 2
        xLimAuto = [min(xAll) max(xAll)]; if xLimAuto(2) <= xLimAuto(1), xLimAuto(2) = xLimAuto(1) + eps; end
    else
        xLimAuto = [tmin(1) tmin(end)];
    end
    if numel(yAll) >= 2
        y0 = min(yAll); y1 = max(yAll);
        if y1 > y0
            padY = max(0.15*(y1-y0), 0.5); yLimAuto = [y0-padY y1+padY];
        else
            yLimAuto = [y0-1 y1+1];
        end
    else
        yLimAuto = [-5 5];
    end
end

function applyTimecourseXTicks(xLimNow)
    span = xLimNow(2)-xLimNow(1);
    if ~isfinite(span) || span <= 0
        set(axTC,'XTickMode','auto','XTickLabelMode','auto'); return;
    end
    if span <= 5, stepMin = 1; elseif span <= 15, stepMin = 2; else, stepMin = 5; end
    ticks = ceil(xLimNow(1)/stepMin)*stepMin : stepMin : floor(xLimNow(2)/stepMin)*stepMin;
    if isempty(ticks), ticks = [xLimNow(1) xLimNow(2)]; end
    if numel(ticks) == 1, ticks = unique([xLimNow(1) ticks xLimNow(2)]); end
    ticks = ticks(isfinite(ticks));
    set(axTC,'XTick',ticks,'XTickMode','manual','XTickLabelMode','auto');
end

function drawTimeWindows()
    if ~isgraphics(axTC), return; end
    [b0,b1] = parseRangeSafe(getStr(ebBase),30,240);
    [s0,s1] = parseRangeSafe(getStr(ebSig),840,900);
    if isVolMode
        b0s = (clamp(round(b0),1,nT)-1)*TR; b1s = (clamp(round(b1),1,nT)-1)*TR;
        s0s = (clamp(round(s0),1,nT)-1)*TR; s1s = (clamp(round(s1),1,nT)-1)*TR;
    else
        b0s = b0; b1s = b1; s0s = s0; s1s = s1;
    end
    if b1s < b0s, tmp=b0s; b0s=b1s; b1s=tmp; end
    if s1s < s0s, tmp=s0s; s0s=s1s; s1s=tmp; end
    yl = get(axTC,'YLim'); if any(~isfinite(yl)) || yl(2) <= yl(1), yl = [-5 5]; set(axTC,'YLim',yl); end
    yr = yl(2)-yl(1); if ~isfinite(yr) || yr <= 0, yr = 1; end
    xb = [b0s b1s b1s b0s]/60; xs = [s0s s1s s1s s0s]/60;
    yb = [yl(1) yl(1) yl(2) yl(2)]; ys = yb;
    set(hBasePatch,'XData',xb,'YData',yb,'FaceColor',[1.00 0.20 0.20],'FaceAlpha',0.16,'Visible','on');
    set(hSigPatch,'XData',xs,'YData',ys,'FaceColor',[1.00 0.60 0.15],'FaceAlpha',0.16,'Visible','on');
    yTxt = yl(2) - 0.06*yr;
    set(hBaseTxt,'Position',[mean(xb) yTxt 0],'String','Bas.','Visible','on','HorizontalAlignment','center','VerticalAlignment','middle','BackgroundColor',[0 0 0],'Margin',1,'Clipping','on');
    set(hSigTxt,'Position',[mean(xs) yTxt 0],'String','Sig.','Visible','on','HorizontalAlignment','center','VerticalAlignment','middle','BackgroundColor',[0 0 0],'Margin',1,'Clipping','on');
    try, uistack(hBasePatch,'bottom'); uistack(hSigPatch,'bottom'); catch, end
end

%% ==========================================================
% DATA HELPERS
%% ==========================================================
function PSCz = getPSCForSlice(z)
    if ndims(PSC) == 3
        PSCz = PSC;
    else
        PSCz = squeeze(PSC(:,:,clamp(round(z),1,nZ),:));
    end
end

function tf = isValidBundleUnderlayForCurrentScm(U)
    tf = false;

    try
        if isempty(U)
            return;
        end

        U = squeeze(U);

        % 2D underlay is valid only for single-slice SCM.
        % For multi-slice data, accepting 2D is exactly what causes
        % the same underlay to appear on all slices.
        if ndims(U) == 2
            tf = (nZ == 1 && size(U,1) == nY && size(U,2) == nX);
            return;
        end

        % Grayscale stack: Y x X x Z
        if ndims(U) == 3
            if size(U,1) ~= nY || size(U,2) ~= nX
                return;
            end

            % Correct multi-slice underlay stack.
            if size(U,3) == nZ
                tf = true;
                return;
            end

            % RGB image is allowed only for single-slice display.
            if nZ == 1 && size(U,3) == 3
                tf = true;
                return;
            end

            return;
        end

        % RGB stack: Y x X x 3 x Z
        if ndims(U) == 4
            tf = (size(U,1) == nY && ...
                  size(U,2) == nX && ...
                  size(U,3) == 3  && ...
                  size(U,4) == nZ);
            return;
        end

    catch
        tf = false;
    end
end


function Uout = prepareBundleUnderlayForCurrentScm(U)
    U = squeeze(double(U));
    U(~isfinite(U)) = 0;

    if ndims(U) == 2
        Uout = U;
        return;
    end

    if ndims(U) == 3
        Uout = U;
        return;
    end

    % Convert RGB stack Y x X x 3 x Z to grayscale stack Y x X x Z.
    if ndims(U) == 4 && size(U,3) == 3 && size(U,4) == nZ
        Uout = zeros(nY,nX,nZ);

        for zz0 = 1:nZ
            RGB = squeeze(U(:,:,:,zz0));
            Uout(:,:,zz0) = 0.2989 .* RGB(:,:,1) + ...
                             0.5870 .* RGB(:,:,2) + ...
                             0.1140 .* RGB(:,:,3);
        end

        return;
    end

    error('prepareBundleUnderlayForCurrentScm: unsupported underlay size %s', mat2str(size(U)));
end


function bg2 = getBg2DForSlice(z)
    ensureUnderlayStateFields(); z = clamp(round(z),1,nZ);
    if isempty(bg), bg2 = zeros(nY,nX); return; end
    if ndims(bg) == 2
        bg2 = fitUnderlayPlaneToCurrentDisplay(bg); return;
    end
    if ndims(bg) == 3
        if size(bg,3) == 3 && state.isColorUnderlay
            bg2 = fitUnderlayPlaneToCurrentDisplay(bg); return;
        end
        if nZ > 1 && size(bg,3) == nZ
            bg2 = fitUnderlayPlaneToCurrentDisplay(bg(:,:,z)); return;
        end
        if nZ == 1 && size(bg,3) == nT
            bg2 = fitUnderlayPlaneToCurrentDisplay(mean(bg,3)); return;
        end
        bg2 = fitUnderlayPlaneToCurrentDisplay(bg(:,:,max(1,min(size(bg,3),z)))); return;
    end
    if ndims(bg) == 4
        if size(bg,3) == 3 && state.isColorUnderlay && size(bg,4) >= 1
            zUse = max(1,min(size(bg,4),z)); bg2 = squeeze(bg(:,:,:,zUse)); bg2 = fitUnderlayPlaneToCurrentDisplay(bg2); return;
        end
        tmp = mean(bg,4);
        if ndims(tmp) == 3
            bg2 = tmp(:,:,max(1,min(size(tmp,3),z)));
        else
            bg2 = squeeze(tmp(:,:,1));
        end
        bg2 = fitUnderlayPlaneToCurrentDisplay(bg2); return;
    end
    bg2 = squeeze(bg); if ndims(bg2) > 2, bg2 = bg2(:,:,1); end
    bg2 = fitUnderlayPlaneToCurrentDisplay(bg2);
end

function U2 = fitUnderlayPlaneToCurrentDisplay(U2)
    if isempty(U2), U2 = zeros(nY,nX); return; end
    U2 = squeeze(U2);
    if ndims(U2) == 2
        if size(U2,1) ~= nY || size(U2,2) ~= nX
            try
                U2 = imresize(double(U2), [nY nX], 'bilinear');
            catch
                tmp = zeros(nY,nX); yy = min(nY,size(U2,1)); xx = min(nX,size(U2,2));
                tmp(1:yy,1:xx) = double(U2(1:yy,1:xx)); U2 = tmp;
            end
        end
        return;
    end
    if ndims(U2) == 3 && size(U2,3) == 3
        if size(U2,1) ~= nY || size(U2,2) ~= nX
            try
                U2 = imresize(double(U2), [nY nX], 'bilinear');
            catch
                tmp = zeros(nY,nX,3); yy = min(nY,size(U2,1)); xx = min(nX,size(U2,2));
                tmp(1:yy,1:xx,:) = double(U2(1:yy,1:xx,:)); U2 = tmp;
            end
        end
        return;
    end
    if ndims(U2) > 2
        U2 = fitUnderlayPlaneToCurrentDisplay(U2(:,:,1));
    end
end

function maskLocal = getMaskForCurrentSlice()
    maskLocal = getMaskForSlice(state.z);
end

function maskLocal = getMaskForSlice(zSel)
    if isempty(passedMask)
        maskLocal = true(nY,nX);
    else
        maskLocal = collapseMaskForSlice(passedMask, nY, nX, zSel, nZ);
        if ~passedMaskIsInclude, maskLocal = ~maskLocal; end
    end
end

function M = fitBundleMaskToCurrentScm(M0)
    M = [];
    if isempty(M0), return; end
    M0 = logical(M0);
    if ismatrix(M0)
        M = resizeMask2D(M0, nY, nX); return;
    end
    if ndims(M0) == 3
        if size(M0,1) ~= nY || size(M0,2) ~= nX
            tmp = false(nY,nX,size(M0,3));
            for zz = 1:size(M0,3), tmp(:,:,zz) = resizeMask2D(M0(:,:,zz), nY, nX); end
            M0 = tmp;
        end
        if nZ > 1 && size(M0,3) == nZ
            M = M0;
        elseif nZ == 1
            M = any(M0,3);
        else
            zIdx = round(linspace(1,size(M0,3),nZ)); zIdx = max(1,min(size(M0,3),zIdx));
            M = M0(:,:,zIdx);
        end
        return;
    end
    while ndims(M0) > 3, M0 = any(M0, ndims(M0)); end
    M = fitBundleMaskToCurrentScm(M0);
end

function M2 = resizeMask2D(M0, ny, nx)
    if size(M0,1) == ny && size(M0,2) == nx
        M2 = logical(M0);
    else
        try
            M2 = imresize(double(M0), [ny nx], 'nearest') > 0.5;
        catch
            M2 = false(ny,nx); yy = min(ny,size(M0,1)); xx = min(nx,size(M0,2));
            M2(1:yy,1:xx) = logical(M0(1:yy,1:xx));
        end
    end
end

function M2 = collapseMaskForSlice(M0, ny, nx, z, nZ_)
    if isempty(M0), M2 = true(ny,nx); return; end
    M0 = logical(M0);
    if ndims(M0) == 2
        M2 = M0;
    elseif ndims(M0) == 3
        if nZ_ > 1 && size(M0,3) == nZ_
            z = max(1,min(size(M0,3),round(z))); M2 = M0(:,:,z);
        else
            M2 = any(M0,3);
        end
    else
        tmp = M0;
        while ndims(tmp) > 3, tmp = any(tmp, ndims(tmp)); end
        M2 = collapseMaskForSlice(tmp, ny, nx, z, nZ_);
        return;
    end
    M2 = resizeMask2D(M2, ny, nx);
end

function M = deriveMaskFromUnderlay(bgIn, ny, nx, nz, nt)
    M = [];
    if isempty(bgIn) || ~(isnumeric(bgIn) || islogical(bgIn)), return; end
    try
        if ndims(bgIn) == 2
            V = reshape(double(bgIn), [ny nx 1]);
        elseif ndims(bgIn) == 3
            if nz > 1 && size(bgIn,3) == nz
                V = double(bgIn);
            elseif nz == 1 && size(bgIn,3) == nt
                V = reshape(mean(double(bgIn),3), [ny nx 1]);
            else
                V = reshape(double(bgIn(:,:,1)), [ny nx 1]);
            end
        elseif ndims(bgIn) == 4
            V = mean(double(bgIn),4);
        else
            return;
        end
        V = V(1:min(ny,size(V,1)),1:min(nx,size(V,2)),1:min(nz,size(V,3)));
        if size(V,1) < ny, V(end+1:ny,:,:) = 0; end
        if size(V,2) < nx, V(:,end+1:nx,:) = 0; end
        if size(V,3) < nz, V(:,:,end+1:nz) = 0; end
        fracZero = mean(V(:) == 0);
        if ~isfinite(fracZero) || fracZero < 0.02, M = []; return; end
        M = logical(V ~= 0);
        try
            for zz = 1:size(M,3), M(:,:,zz) = imfill(M(:,:,zz), 'holes'); end
        catch
        end
    catch
        M = [];
    end
end

function U = makeNativeFallbackUnderlayFromPSC(X)
    if ndims(X) == 3
        U = mean(double(X),3);
    elseif ndims(X) == 4
        U = mean(double(X),4);
    else
        U = zeros(nY,nX);
    end
    U(~isfinite(U)) = 0;
    if ndims(U) > 3
        U = squeeze(U);
        if ndims(U) > 3, U = U(:,:,1); end
    end
end

%% ==========================================================
% UNDERLAY PROCESSING / COLORMAPS
%% ==========================================================
function rgb = renderUnderlayRGB(Uin)
    ensureUnderlayStateFields();
    if state.isColorUnderlay
        rgb = convertUnderlayToColorRGB(Uin);
    else
        rgb = toRGB(processUnderlay(Uin));
    end
end

function U = processUnderlay(Uin)
    U = double(Uin); U(~isfinite(U)) = 0;
    switch uState.mode
        case 1
            U = mat2gray_safe(U);
        case 2
            U = clip01_percentile(U, 1, 99);
        case 3
            U = clip01_percentile(U, 0.5, 99.5);
        case 4
            U = clip01_percentile(U, 0.5, 99.5);
            U = vesselEnhanceStrong(U, uState.conectSize, uState.conectLev);
            U = clip01_percentile(U, 0.5, 99.5);
        otherwise
            U = mat2gray_safe(U);
    end
    U = U*uState.contrast + uState.brightness;
    U = min(max(U,0),1);
    g = uState.gamma; if ~isfinite(g) || g <= 0, g = 1; end
    U = min(max(U.^g,0),1);
end

function U = vesselEnhanceStrong(U01, conectSizePx, conectLev_0_MAX)
    if conectSizePx <= 0, U = U01; return; end
    lev01 = (conectLev_0_MAX / max(1, MAX_CONLEV)); lev01 = min(max(lev01^0.75,0),1);
    thrMask = (U01 > lev01);
    r = max(1, min(MAX_CONSIZE, round(conectSizePx)));
    h = diskKernel(r);
    try, D = filter2(h, double(thrMask), 'same'); catch, D = conv2(double(thrMask), h, 'same'); end
    D = min(max(D,0),1);
    strength = 0.8 + 1.6*min(1, r/120);
    D2 = D.^2;
    U = min(max(U01 .* (1 + strength*D2) + 0.15*D2,0),1);
end

function h = diskKernel(r)
    r = max(1,round(r)); [x,y] = meshgrid(-r:r,-r:r); m = (x.^2 + y.^2) <= r^2;
    h = double(m); s = sum(h(:)); if s > 0, h = h/s; end
end

function rgb = convertUnderlayToColorRGB(U)
    U = squeeze(U);
    if ndims(U) == 3 && size(U,3) == 3
        rgb = double(U); if max(rgb(:)) > 1, rgb = rgb/255; end
        rgb = min(max(rgb,0),1); return;
    end
    L = double(U); L(~isfinite(L)) = 0;
    maxLab = max(L(:));
    if isempty(state.regionColorLUT) || size(state.regionColorLUT,1) < max(1,maxLab)
        state.regionColorLUT = makeRegionColorLUT(max(1, maxLab));
    end
    rgb = zeros([size(L,1) size(L,2) 3], 'double');
    zmask = (L == 0);
    rgb(:,:,1) = 0.85*zmask; rgb(:,:,2) = 0.85*zmask; rgb(:,:,3) = 0.85*zmask;
    pos = find(L > 0);
    if ~isempty(pos)
        labs = round(L(pos)); labs(labs < 1) = 1; labs(labs > size(state.regionColorLUT,1)) = size(state.regionColorLUT,1);
        c = state.regionColorLUT(labs,:);
        tmp = reshape(rgb, [], 3); tmp(pos,:) = c; rgb = reshape(tmp, size(rgb));
    end
    rgb = min(max(rgb,0),1);
end

function lut = makeRegionColorLUT(n)
    if n <= 0, lut = zeros(1,3); return; end
    base = lines(max(n,12)); lut = base(1:n,:);
    if n > size(base,1)
        x = linspace(0,1,size(base,1)); xi = linspace(0,1,n); tmp = zeros(n,3);
        for k = 1:3, tmp(:,k) = interp1(x,base(:,k),xi,'linear'); end
        lut = min(max(tmp,0),1);
    end
end

function setOverlayColormap(name)
    cm = getCmap(name, 256);
    try, colormap(ax, cm); catch, colormap(fig, cm); end
end

function cm = getCmap(name, n)
    if nargin < 2, n = 256; end
    if exist('isstring','builtin') && isstring(name), name = char(name); end
    name = lower(strtrim(char(name)));
    if strcmp(name,'blackbdy_iso')
        if exist('blackbdy_iso','file'), cm = blackbdy_iso(n); else, cm = hot(n); end
        return;
    end
    if strcmp(name,'winter_brain_fsl')
        if exist('winter_brain_fsl','file'), cm = winter_brain_fsl(n); else, cm = winter(n); end
        return;
    end
    if strcmp(name,'signed_blackbdy_winter')
        nNeg = floor(n/2); nPos = n - nNeg;
        if exist('winter_brain_fsl','file'), neg = winter_brain_fsl(max(nNeg,2)); else, neg = winter(max(nNeg,2)); end
        neg = neg(1:nNeg,:); neg = neg .* repmat(linspace(1,0,nNeg)',1,3); if ~isempty(neg), neg(end,:) = [0 0 0]; end
        if exist('blackbdy_iso','file'), pos = blackbdy_iso(max(nPos,2)); else, pos = hot(max(nPos,2)); end
        pos = pos(1:nPos,:); if ~isempty(pos), pos(1,:) = [0 0 0]; end
        cm = min(max([neg; pos],0),1); return;
    end
    switch name
        case 'winter', cm = winter(n); return;
        case 'hot', cm = hot(n); return;
        case 'parula', cm = parula(n); return;
        case 'jet', cm = jet(n); return;
        case 'gray', cm = gray(n); return;
        case 'bone', cm = bone(n); return;
        case 'copper', cm = copper(n); return;
        case 'pink', cm = pink(n); return;
        case 'turbo'
            if exist('turbo','file'), cm = turbo(n); else, cm = jet(n); end
            return;
        case 'viridis'
            cm = interpAnchors([0.267 0.005 0.329;0.283 0.141 0.458;0.254 0.265 0.530;0.207 0.372 0.553;0.164 0.471 0.558;0.128 0.567 0.551;0.135 0.659 0.518;0.267 0.749 0.441;0.478 0.821 0.318;0.741 0.873 0.150],n); return;
        case 'plasma'
            cm = interpAnchors([0.050 0.030 0.528;0.280 0.040 0.650;0.500 0.060 0.650;0.700 0.170 0.550;0.850 0.350 0.420;0.940 0.550 0.260;0.990 0.750 0.140],n); return;
        case 'magma'
            cm = interpAnchors([0.001 0.000 0.015;0.100 0.060 0.230;0.250 0.080 0.430;0.450 0.120 0.500;0.650 0.210 0.420;0.820 0.370 0.280;0.930 0.610 0.210;0.990 0.870 0.400],n); return;
        case 'inferno'
            cm = interpAnchors([0.002 0.002 0.014;0.120 0.030 0.220;0.280 0.050 0.400;0.480 0.090 0.430;0.680 0.180 0.330;0.820 0.350 0.210;0.930 0.590 0.110;0.990 0.860 0.240],n); return;
    end
    cm = hot(n);
end

function cm = interpAnchors(anchors, n)
    x = linspace(0,1,size(anchors,1)); xi = linspace(0,1,n); cm = zeros(n,3);
    for k = 1:3, cm(:,k) = interp1(x,anchors(:,k),xi,'linear'); end
    cm = min(max(cm,0),1);
end

%% ==========================================================
% FILE READING / TRANSFORMS
%% ==========================================================
function [f,p] = uigetfileStartIn(filterSpec, dlgTitle, startPath)
    if nargin < 3 || isempty(startPath) || exist(startPath,'dir') ~= 7, startPath = pwd; end
    oldDir = pwd;
    cleanupObj = onCleanup(@()scmSafeCdBack(oldDir)); %#ok<NASGU>
    try, cd(startPath); catch, startPath = pwd; end
    try
        [f,p] = uigetfile(filterSpec, dlgTitle, fullfile(startPath, '*.*'));
    catch
        [f,p] = uigetfile(filterSpec, dlgTitle);
    end
end

function scmSafeCdBack(oldDir)
    try
        if ~isempty(oldDir) && exist(oldDir,'dir') == 7, cd(oldDir); end
    catch
    end
end

    function startPath = getMaskStartPath()
% Best folder for LOAD MASK / LOAD BUNDLE.
% Mask Editor exports and SCM/Video underlay-overlay bundles are usually
% in Visualization, so Visualization should stay first.

    try
        if isstruct(par) && isfield(par,'maskStartPath') && ...
                ~isempty(par.maskStartPath) && exist(char(par.maskStartPath),'dir') == 7
            startPath = char(par.maskStartPath);
            return;
        end
    catch
    end

    root = getDatasetRootForSelectors();

    cand = { ...
        fullfile(root,'Visualization'), ...
        fullfile(root,'Masks'), ...
        fullfile(root,'Mask'), ...
        fullfile(root,'ROI'), ...
        fullfile(root,'Registration2D'), ...
        fullfile(root,'Registration'), ...
        root, ...
        getStartPath(), ...
        pwd};

    startPath = firstExistingDir(cand);
end
    function startPath = getTransformStartPath()
% Best folder for WARP FUNCTIONAL TO ATLAS.
% CoronalRegistration2D*.mat should usually be in Registration2D.

    try
        if isstruct(par) && isfield(par,'transformStartPath') && ...
                ~isempty(par.transformStartPath) && exist(char(par.transformStartPath),'dir') == 7
            startPath = char(par.transformStartPath);
            return;
        end
    catch
    end

    root = getDatasetRootForSelectors();

    cand = { ...
        fullfile(root,'Registration2D'), ...
        fullfile(root,'Registration'), ...
        root, ...
        getStartPath(), ...
        pwd};

    startPath = firstExistingDir(cand);
end

    function startPath = getUnderlayStartPathFast()
% Best folder for LOAD NEW UNDERLAY.
% For atlas/histology/coregistration underlays, Registration2D should be first.

    % Explicit path passed from fusi_studio has highest priority
    try
        if isstruct(par) && isfield(par,'underlayStartPath') && ...
                ~isempty(par.underlayStartPath) && exist(char(par.underlayStartPath),'dir') == 7
            startPath = char(par.underlayStartPath);
            return;
        end
    catch
    end

    root = getDatasetRootForSelectors();
    cand = {};

    % If already atlas-warped, start where the transform came from
    try
        if state.isAtlasWarped && ~isempty(state.atlasTransformFile) && ...
                exist(state.atlasTransformFile,'file') == 2
            cand{end+1} = fileparts(char(state.atlasTransformFile)); %#ok<AGROW>
        end
    catch
    end

    cand = [cand { ...
        fullfile(root,'Registration2D'), ...
        fullfile(root,'Registration'), ...
        fullfile(root,'Visualization'), ...
        fullfile(root,'Masks'), ...
        fullfile(root,'Mask'), ...
        root, ...
        getStartPath(), ...
        pwd}];

    startPath = firstExistingDir(cand);
end

function startPath = getStartPath()
    candDirs = {};
    try
        if isstruct(par)
            if isfield(par,'exportPath') && ~isempty(par.exportPath), candDirs{end+1} = char(par.exportPath); end %#ok<AGROW>
            if isfield(par,'loadedPath') && ~isempty(par.loadedPath), candDirs{end+1} = char(par.loadedPath); end %#ok<AGROW>
            if isfield(par,'rawPath') && ~isempty(par.rawPath), candDirs{end+1} = char(par.rawPath); end %#ok<AGROW>
            if isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile); if exist(lf,'file') == 2, candDirs{end+1} = fileparts(lf); end %#ok<AGROW>
            end
        end
    catch
    end
    candDirs{end+1} = pwd;
    startPath = firstExistingDir(candDirs);
end

function root = getDatasetRootForSelectors()
    root = '';
    try
        if isstruct(par)
            if isfield(par,'selectorRoot') && ~isempty(par.selectorRoot) && exist(char(par.selectorRoot),'dir') == 7
                root = char(par.selectorRoot);
            elseif isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(char(par.exportPath),'dir') == 7
                root = char(par.exportPath);
            elseif isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(char(par.loadedPath),'dir') == 7
                root = char(par.loadedPath);
            elseif isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile); if exist(lf,'file') == 2, root = fileparts(lf); end
            elseif isfield(par,'rawPath') && ~isempty(par.rawPath) && exist(char(par.rawPath),'dir') == 7
                root = char(par.rawPath);
            end
        end
    catch
        root = '';
    end
    if isempty(root), root = pwd; end
    try, root = guessAnalysedRoot(root); catch, end
    root = normalizeSelectorRoot(root);
end

function root = normalizeSelectorRoot(root)
    if isempty(root) || exist(root,'dir') ~= 7, root = pwd; return; end
    leafFolders = {'Visualization','Masks','Mask','ROI','Registration2D','Registration','SCM','Images','Series','Timecourse','PSC','Preprocessing','QC','Bundles'};
    for kk = 1:4
        [parentDir, leafName] = fileparts(root);
        if isempty(parentDir) || strcmp(parentDir,root), break; end
        if any(strcmpi(leafName, leafFolders)), root = parentDir; else, break; end
    end
end

function d = firstExistingDir(cand)
    d = pwd;
    for ii = 1:numel(cand)
        try
            c0 = cand{ii};
            if ~isempty(c0) && exist(c0,'dir') == 7, d = c0; return; end
        catch
        end
    end
end

function [U, meta] = readUnderlayFile(f)
    if ~exist(f,'file'), error('Underlay file not found: %s', f); end
    meta = defaultUnderlayMeta();
    isNiiGz = (numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz'));
    if isNiiGz
        tmpDir = tempname; mkdir(tmpDir); gunzip(f,tmpDir); ddd = dir(fullfile(tmpDir,'*.nii'));
        if isempty(ddd), error('Failed to gunzip .nii.gz underlay.'); end
        U = double(niftiread(fullfile(tmpDir,ddd(1).name)));
        try, rmdir(tmpDir,'s'); catch, end
        return;
    end
    [~,~,e] = fileparts(f); e = lower(e);
    switch e
        case '.mat'
            S = load(f); [U,meta] = extractUnderlayFromMatStruct(S);
        case '.nii'
            U = double(niftiread(f));
        case {'.png','.jpg','.jpeg','.tif','.tiff','.bmp'}
            U = imread(f); U = double(U); if ndims(U) == 3 && size(U,3) == 3, meta.isColor = true; end
        otherwise
            error('Unsupported underlay file type: %s', e);
    end
end

function meta = defaultUnderlayMeta()
    meta = struct('isColor',false,'regionLabels',[],'regionInfo',struct(),'atlasMode','');
end

function [U, meta] = extractUnderlayFromMatStruct(S)
    meta = defaultUnderlayMeta();
    if isfield(S,'atlasMode') && ~isempty(S.atlasMode)
        try, meta.atlasMode = char(S.atlasMode); catch, meta.atlasMode = ''; end
    end
    if strcmpi(meta.atlasMode,'regions')
        if isfield(S,'atlasUnderlayRGB') && ~isempty(S.atlasUnderlayRGB)
            U = double(S.atlasUnderlayRGB); meta.isColor = true;
        elseif isfield(S,'brainImage') && ~isempty(S.brainImage)
            U = double(S.brainImage); if ndims(U) == 3 && size(U,3) == 3, meta.isColor = true; end
        else
            error('Regions MAT file has no atlasUnderlayRGB / brainImage.');
        end
        if isfield(S,'atlasRegionLabels2D') && ~isempty(S.atlasRegionLabels2D), meta.regionLabels = double(S.atlasRegionLabels2D);
        elseif isfield(S,'atlasUnderlay') && ~isempty(S.atlasUnderlay), meta.regionLabels = double(S.atlasUnderlay); end
        if isfield(S,'atlasInfoRegions') && ~isempty(S.atlasInfoRegions), meta.regionInfo = S.atlasInfoRegions;
        elseif isfield(S,'infoRegions') && ~isempty(S.infoRegions), meta.regionInfo = S.infoRegions; end
        return;
    end
 pref = { ...
    'sliceUnderlayRaw', ...
    'sliceUnderlayProcessed', ...
    'anatomical_reference_raw', ...
    'anatomical_reference', ...
    'atlasUnderlayRGB', ...
    'atlasUnderlay', ...
    'underlay', ...
    'bg', ...
    'brainImage', ...
    'img', ...
    'I', ...
    'vascular', ...
    'histology', ...
    'regions', ...
    'Data'};
    for ii = 1:numel(pref)
        if isfield(S,pref{ii})
            v = S.(pref{ii});
            if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data)
                U = double(v.Data); if ndims(U)==3 && size(U,3)==3, meta.isColor = true; end; return;
            elseif isnumeric(v) || islogical(v)
                U = double(v); if ndims(U)==3 && size(U,3)==3, meta.isColor = true; end; return;
            end
        end
    end
    fn = fieldnames(S);
    for ii = 1:numel(fn)
        v = S.(fn{ii});
        if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data)
            U = double(v.Data); if ndims(U)==3 && size(U,3)==3, meta.isColor = true; end; return;
        elseif isnumeric(v) || islogical(v)
            U = double(v); if ndims(U)==3 && size(U,3)==3, meta.isColor = true; end; return;
        end
    end
    error('MAT underlay file has no usable numeric variable.');
end

function U = validateAndPrepareUnderlay(U, fullf)
    U = squeeze(U);
    if isempty(U) || ~(isnumeric(U) || islogical(U)), error('Loaded underlay is not numeric or logical: %s', fullf); end
    U = double(U);
end

function applyUnderlayMeta(meta, U)
    ensureUnderlayStateFields();
    state.isColorUnderlay = false; state.regionLabelUnderlay = []; state.regionColorLUT = []; state.regionInfo = struct();
    explicitRegionMode = false;
    if nargin >= 1 && isstruct(meta)
        if isfield(meta,'regionLabels') && ~isempty(meta.regionLabels)
            state.regionLabelUnderlay = double(meta.regionLabels); state.isColorUnderlay = true; explicitRegionMode = true;
        end
        if isfield(meta,'regionInfo') && ~isempty(meta.regionInfo), state.regionInfo = meta.regionInfo; end
        if isfield(meta,'atlasMode') && ~isempty(meta.atlasMode)
            try
                if strcmpi(char(meta.atlasMode),'regions'), explicitRegionMode = true; state.isColorUnderlay = true; end
            catch
            end
        end
        if isfield(meta,'isColor') && meta.isColor, state.isColorUnderlay = true; end
    end
    if nargin < 2 || isempty(U), return; end
    U = squeeze(U);
    ambiguousThreeSliceStack = ndims(U) == 3 && size(U,3) == 3 && nZ > 1 && size(U,1) == nY && size(U,2) == nX;
    if explicitRegionMode, state.isColorUnderlay = true; return; end
    if ndims(U) == 3 && size(U,3) == 3
        state.isColorUnderlay = ~ambiguousThreeSliceStack;
    end
end

function ensureUnderlayStateFields()
    if ~isfield(state,'isColorUnderlay') || isempty(state.isColorUnderlay), state.isColorUnderlay = false; end
    if ~isfield(state,'regionLabelUnderlay') || isempty(state.regionLabelUnderlay), state.regionLabelUnderlay = []; end
    if ~isfield(state,'regionColorLUT') || isempty(state.regionColorLUT), state.regionColorLUT = []; end
    if ~isfield(state,'regionInfo') || isempty(state.regionInfo), state.regionInfo = struct(); end
end

function B = readScmBundleFile(fullf)
    if ~exist(fullf,'file'), error('File not found: %s', fullf); end
    S = load(fullf);
    if isfield(S,'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle), R = S.maskBundle; else, R = S; end
    B = struct('brainImage',[],'overlayMask',[],'brainMask',[],'overlayMaskIsInclude',true,'brainMaskIsInclude',true,'loadedField','','source',fullf);
    overlayFields = {'loadedMask','overlayMask','signalMask','overlay','overlay_mask','signal_mask','mask','activeMask'};
    for k = 1:numel(overlayFields)
        fn = overlayFields{k};
        if isfield(R,fn) && ~isempty(R.(fn)) && (isnumeric(R.(fn)) || islogical(R.(fn)))
            B.overlayMask = logical(R.(fn)); B.loadedField = fn; break;
        elseif isfield(S,fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
            B.overlayMask = logical(S.(fn)); B.loadedField = fn; break;
        end
    end
    brainFields = {'brainMask','underlayMask','brain_mask','underlay_mask'};
    for k = 1:numel(brainFields)
        fn = brainFields{k};
        if isfield(R,fn) && ~isempty(R.(fn)) && (isnumeric(R.(fn)) || islogical(R.(fn)))
            B.brainMask = logical(R.(fn)); break;
        elseif isfield(S,fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
            B.brainMask = logical(S.(fn)); break;
        end
    end
    % Prefer full saved underlay stacks from Mask Editor.
% brainImage can be masked or accidentally 2D, so use it only after
% anatomical_reference / anatomical_reference_raw.
underlayFields = { ...
    'anatomical_reference', ...
    'anatomical_reference_raw', ...
    'brainImage', ...
    'underlay', ...
    'bg', ...
    'brain_image'};

for k = 1:numel(underlayFields)
    fn = underlayFields{k};

    if isfield(R,fn) && ~isempty(R.(fn)) && (isnumeric(R.(fn)) || islogical(R.(fn)))
        B.brainImage = double(R.(fn));
        break;

    elseif isfield(S,fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
        B.brainImage = double(S.(fn));
        break;
    end
end
    if isfield(R,'overlayMaskIsInclude') && ~isempty(R.overlayMaskIsInclude), B.overlayMaskIsInclude = logical(R.overlayMaskIsInclude);
    elseif isfield(S,'overlayMaskIsInclude') && ~isempty(S.overlayMaskIsInclude), B.overlayMaskIsInclude = logical(S.overlayMaskIsInclude);
    elseif isfield(R,'loadedMaskIsInclude') && ~isempty(R.loadedMaskIsInclude), B.overlayMaskIsInclude = logical(R.loadedMaskIsInclude);
    elseif isfield(S,'loadedMaskIsInclude') && ~isempty(S.loadedMaskIsInclude), B.overlayMaskIsInclude = logical(S.loadedMaskIsInclude);
    elseif isfield(R,'maskIsInclude') && ~isempty(R.maskIsInclude), B.overlayMaskIsInclude = logical(R.maskIsInclude);
    elseif isfield(S,'maskIsInclude') && ~isempty(S.maskIsInclude), B.overlayMaskIsInclude = logical(S.maskIsInclude); end
    if isfield(R,'brainMaskIsInclude') && ~isempty(R.brainMaskIsInclude), B.brainMaskIsInclude = logical(R.brainMaskIsInclude);
    elseif isfield(S,'brainMaskIsInclude') && ~isempty(S.brainMaskIsInclude), B.brainMaskIsInclude = logical(S.brainMaskIsInclude); end
end


function [Ubg, pickedField] = readMaskEditorUnderlayStackStrict(fullf)
    Ubg = [];
    pickedField = '';

    if isempty(fullf) || exist(fullf,'file') ~= 2
        return;
    end

    try
        S0 = load(fullf);
    catch
        return;
    end

    sources = {};
    sourceNames = {};

    if isfield(S0,'maskBundle') && isstruct(S0.maskBundle)
        sources{end+1} = S0.maskBundle;
        sourceNames{end+1} = 'maskBundle';
    end

    sources{end+1} = S0;
    sourceNames{end+1} = 'top';

    % Strict priority:
    % These are real underlay fields.
    % Do NOT add mask / loadedMask / overlayMask here.
    pref = { ...
        'sliceUnderlayRaw', ...
        'sliceUnderlayProcessed', ...
        'anatomical_reference_raw', ...
        'anatomical_reference', ...
        'brainImage'};

    for ss = 1:numel(sources)
        R = sources{ss};

        for kk = 1:numel(pref)
            fn = pref{kk};

            if isfield(R,fn) && ~isempty(R.(fn)) && ...
                    (isnumeric(R.(fn)) || islogical(R.(fn)))

                U = squeeze(double(R.(fn)));

                if isValidStrictBundleUnderlay(U)
                    Ubg = prepareStrictBundleUnderlay(U);
                    pickedField = [sourceNames{ss} '.' fn];
                    return;
                else
                    fprintf('[SCM] Rejected bundle underlay candidate %s.%s with size %s\n', ...
                        sourceNames{ss}, fn, mat2str(size(U)));
                end
            end
        end
    end
end


function tf = isValidStrictBundleUnderlay(U)
    tf = false;

    try
        if isempty(U)
            return;
        end

        U = squeeze(U);

        % ---------------------------------------------------------
        % Single-slice SCM:
        % 2D underlay is okay.
        % ---------------------------------------------------------
        if nZ == 1
            if ndims(U) == 2 && size(U,1) == nY && size(U,2) == nX
                tf = true;
                return;
            end

            if ndims(U) == 3 && size(U,1) == nY && size(U,2) == nX
                % Could be RGB or Y X 1 after squeeze.
                tf = true;
                return;
            end
        end

        % ---------------------------------------------------------
        % Multi-slice / Step Motor SCM:
        % 2D underlay is NOT okay because it would be reused for all slices.
        % Require true Y X Z stack.
        % ---------------------------------------------------------
        if nZ > 1
            if ndims(U) == 3 && ...
                    size(U,1) == nY && ...
                    size(U,2) == nX && ...
                    size(U,3) == nZ

                tf = true;
                return;
            end

            % RGB stack: Y X 3 Z
            if ndims(U) == 4 && ...
                    size(U,1) == nY && ...
                    size(U,2) == nX && ...
                    size(U,3) == 3 && ...
                    size(U,4) == nZ

                tf = true;
                return;
            end
        end

    catch
        tf = false;
    end
end


function Uout = prepareStrictBundleUnderlay(U)
    U = squeeze(double(U));
    U(~isfinite(U)) = 0;

    if ndims(U) == 2
        Uout = U;
        return;
    end

    if ndims(U) == 3
        Uout = U;
        return;
    end

    % RGB stack: Y X 3 Z -> grayscale Y X Z
    if ndims(U) == 4 && size(U,3) == 3 && size(U,4) == nZ
        Uout = zeros(nY,nX,nZ);

        for zz0 = 1:nZ
            RGB = squeeze(U(:,:,:,zz0));
            Uout(:,:,zz0) = 0.2989 .* RGB(:,:,1) + ...
                             0.5870 .* RGB(:,:,2) + ...
                             0.1140 .* RGB(:,:,3);
        end

        return;
    end

    error('Unsupported bundle underlay size: %s', mat2str(size(U)));
end


function forceLoadedBundleUnderlayToGrayStackIfNeeded()
    ensureUnderlayStateFields();

    try
        if nZ > 1 && ndims(bg) == 3 && size(bg,3) == nZ
            % Important for nZ == 3:
            % Prevent SCM from mistaking Y X 3 grayscale slices for one RGB image.
            state.isColorUnderlay = false;
            state.regionLabelUnderlay = [];
            state.regionColorLUT = [];
            state.regionInfo = struct();
        end
    catch
    end
end

function [M, maskIsInclude, pickedField] = readMask(f, mode)
    if nargin < 2 || isempty(mode), mode = 'overlayPreferred'; end %#ok<NASGU>
    if ~exist(f,'file'), error('Mask file not found: %s', f); end
    maskIsInclude = true; pickedField = '';
    isNiiGz = (numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz'));
    if isNiiGz
        tmpDir = tempname; mkdir(tmpDir); gunzip(f,tmpDir); ddd = dir(fullfile(tmpDir,'*.nii'));
        if isempty(ddd), error('Failed to gunzip .nii.gz mask.'); end
        M = logical(niftiread(fullfile(tmpDir,ddd(1).name))); pickedField = 'nifti';
        try, rmdir(tmpDir,'s'); catch, end
        return;
    end
    [~,~,e] = fileparts(f);
    if strcmpi(e,'.mat')
        S = load(f); if isfield(S,'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle), B = S.maskBundle; else, B = S; end
        searchFields = {'loadedMask','overlayMask','signalMask','mask','activeMask','brainMask','underlayMask','M'};
        M = [];
        for k = 1:numel(searchFields)
            fn = searchFields{k};
            if isfield(B,fn) && ~isempty(B.(fn)) && (isnumeric(B.(fn)) || islogical(B.(fn)))
                M = logical(B.(fn)); pickedField = fn; break;
            end
        end
        if isempty(M) && isfield(B,'brainImage') && ~isempty(B.brainImage), M = logical(B.brainImage > 0); pickedField = 'brainImage>0'; end
        if isempty(M), error('MAT mask file has no usable mask variable.'); end
        if isfield(B,'loadedMaskIsInclude') && ~isempty(B.loadedMaskIsInclude), maskIsInclude = logical(B.loadedMaskIsInclude);
        elseif isfield(B,'overlayMaskIsInclude') && ~isempty(B.overlayMaskIsInclude), maskIsInclude = logical(B.overlayMaskIsInclude);
        elseif isfield(B,'maskIsInclude') && ~isempty(B.maskIsInclude), maskIsInclude = logical(B.maskIsInclude); end
        return;
    end
    M = logical(niftiread(f)); pickedField = 'nifti';
end

    function T = force2DOutputSizeFromTargetUnderlay(T, Utarget)
    try
        if isempty(T) || ~isfield(T,'warpA') || isempty(T.warpA)
            return;
        end

        if ~isequal(size(double(T.warpA)), [3 3])
            return;
        end

        hasOut = isfield(T,'outSize') && ~isempty(T.outSize) && ...
            numel(T.outSize) >= 2 && all(isfinite(T.outSize(1:2))) && ...
            all(round(T.outSize(1:2)) > 0);

        if hasOut
            return;
        end

        if nargin >= 2 && ~isempty(Utarget)
            U = squeeze(Utarget);
            if ndims(U) >= 2
                T.outSize = [size(U,1) size(U,2)];
                T.outputSize = T.outSize;
            end
        end
    catch
    end
end


function T = askAndApply2DWarpDirection(T, dlgTitle)
    % Ask once whether to use saved affine matrix or its inverse.
    % For your current symptom, inverse is the first thing to test.

    try
                % Simple coronal 2D Reg2D files from registration_coronal_2d.m
        % are already saved as MATLAB affine2d source -> atlas matrices.
        % Do not ask saved/inverse and do not invert.
        if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d')
            T.scmWarpDirection = 'as_saved';
            T.scmAffineChoice = 'row_saved';
            state.atlas2DWarpDirection = 'as_saved';
            return;
        end
        if isempty(T) || ~isfield(T,'warpA') || isempty(T.warpA)
            return;
        end

        A = double(T.warpA);

        if ~isequal(size(A), [3 3])
            return;
        end

        if nargin < 2 || isempty(dlgTitle)
            dlgTitle = '2D atlas transform direction';
        end

        if isfield(state,'atlas2DWarpDirection') && ...
                ~isempty(state.atlas2DWarpDirection) && ...
                ~strcmpi(state.atlas2DWarpDirection,'ask')

            T.scmWarpDirection = state.atlas2DWarpDirection;
            return;
        end

        msg = [ ...
            'Choose how SCM should apply the 2D affine transform.' newline newline ...
            'Use saved matrix:' newline ...
            '  Functional image is warped using T directly.' newline newline ...
            'Use inverse matrix:' newline ...
            '  Functional image is warped using inv(T).' newline ...
            '  Try this if histology appears in the right place but functional data does not align.' newline newline ...
            'Recommendation for your current problem: Use inverse matrix first.'];

        ch = questdlg(msg, dlgTitle, ...
            'Use saved matrix', 'Use inverse matrix', 'Cancel', ...
            'Use inverse matrix');

        if isempty(ch) || strcmpi(ch,'Cancel')
            error('Atlas warp cancelled.');
        end

        if strcmpi(ch,'Use inverse matrix')
            state.atlas2DWarpDirection = 'inverse';
        else
            state.atlas2DWarpDirection = 'as_saved';
        end

        T.scmWarpDirection = state.atlas2DWarpDirection;

    catch ME
        if strcmpi(ME.message,'Atlas warp cancelled.')
            rethrow(ME);
        end
        T.scmWarpDirection = 'as_saved';
    end
end


function regList = askAndApply2DWarpDirectionToRegList(regList, dlgTitle)
    if isempty(regList)
        return;
    end

    try
        T0 = regList(1).T;
        T0 = askAndApply2DWarpDirection(T0, dlgTitle);
        dirUse = T0.scmWarpDirection;

        for rr = 1:numel(regList)
            regList(rr).T.scmWarpDirection = dirUse;
        end
    catch ME
        rethrow(ME);
    end
end


    function Ause = apply2DWarpDirectionToMatrix(Araw, T)
    % Convert saved 2D transform to a MATLAB affine2d-compatible matrix.
    %
    % MATLAB affine2d requires translation in the LAST ROW:
    %   [a b 0
    %    c d 0
    %    tx ty 1]
    %
    % Many manual registration tools save column-vector matrices:
    %   [a b tx
    %    c d ty
    %    0 0 1]
    %
    % For those, MATLAB needs Araw'.

    Araw = double(Araw);
        % New Reg2D files save A directly in MATLAB affine2d row-vector format.
    % Use it directly.
    try
        if isfield(T,'scmAffineChoice') && strcmpi(char(T.scmAffineChoice), 'row_saved')
            if ~isValidMatlabAffine2D(Araw)
                error('Saved Reg2D.A is not a valid MATLAB affine2d row-vector matrix.');
            end
            Ause = Araw;
            return;
        end
    catch ME
        error(ME.message);
    end

    if ~isequal(size(Araw), [3 3])
        error('2D affine matrix must be 3x3.');
    end

    if any(~isfinite(Araw(:)))
        error('2D affine matrix contains NaN/Inf.');
    end

    cand = {};
    label = {};
    key = {};

    % Candidate 1: raw already valid for MATLAB affine2d.
    if isValidMatlabAffine2D(Araw)
        cand{end+1} = Araw; %#ok<AGROW>
        label{end+1} = 'saved matrix, MATLAB row-vector format'; %#ok<AGROW>
        key{end+1} = 'row_saved'; %#ok<AGROW>

        if abs(det(Araw(1:2,1:2))) > eps
            Ai = inv(Araw);
            if isValidMatlabAffine2D(Ai)
                cand{end+1} = Ai; %#ok<AGROW>
                label{end+1} = 'inverse saved matrix, MATLAB row-vector format'; %#ok<AGROW>
                key{end+1} = 'row_inverse'; %#ok<AGROW>
            end
        end
    end

    % Candidate 2: raw is column-vector style, transpose for affine2d.
    At = Araw.';
    if isValidMatlabAffine2D(At)
        cand{end+1} = At; %#ok<AGROW>
        label{end+1} = 'transpose saved matrix, column-vector source -> atlas'; %#ok<AGROW>
        key{end+1} = 'col_saved_transpose'; %#ok<AGROW>

        if abs(det(At(1:2,1:2))) > eps
            Ati = inv(At);
            if isValidMatlabAffine2D(Ati)
                cand{end+1} = Ati; %#ok<AGROW>
                label{end+1} = 'inverse transpose, column-vector atlas -> source'; %#ok<AGROW>
                key{end+1} = 'col_inverse_transpose'; %#ok<AGROW>
            end
        end
    end

    if isempty(cand)
        error(['No valid affine2d matrix could be made from saved A.' newline ...
               'This means A is not in a valid 2D affine format.']);
    end

    % Strong default:
    % If raw is invalid but transpose is valid, use transpose.
    useIdx = 1;
    if ~isValidMatlabAffine2D(Araw) && isValidMatlabAffine2D(At)
        hit = find(strcmp(key, 'col_saved_transpose'), 1);
        if ~isempty(hit), useIdx = hit; end
    end

    % Optional override stored in T.
    try
        if isfield(T,'scmAffineChoice') && ~isempty(T.scmAffineChoice)
            hit = find(strcmp(key, char(T.scmAffineChoice)), 1);
            if ~isempty(hit), useIdx = hit; end
        end
    catch
    end

    Ause = cand{useIdx};

    try
        fprintf('\n[SCM affine2d] Using %s\n', label{useIdx});
        fprintf('[SCM affine2d] Raw saved A:\n');
        disp(Araw);
        fprintf('[SCM affine2d] MATLAB affine2d Ause:\n');
        disp(Ause);
    catch
    end
end


function tf = isValidMatlabAffine2D(A)
    tf = false;
    try
        A = double(A);
        if ~isequal(size(A), [3 3]), return; end
        if any(~isfinite(A(:))), return; end

        % affine2d requires third column [0;0;1]
        tf = norm(A(:,3) - [0;0;1]) < 1e-8;
    catch
        tf = false;
    end
end
function T = extractAtlasWarpStruct(S)
    if isfield(S,'Transf') && isstruct(S.Transf)
        T = S.Transf;
    elseif isfield(S,'Reg2D') && isstruct(S.Reg2D)
        T = S.Reg2D;
    elseif isfield(S,'RegOut') && isstruct(S.RegOut)
        T = S.RegOut;
    elseif isfield(S,'Registration2D') && isstruct(S.Registration2D)
        T = S.Registration2D;
    else
        T = S;
    end
    if isfield(T,'A') && ~isempty(T.A), T.warpA = T.A;
    elseif isfield(T,'M') && ~isempty(T.M), T.warpA = T.M;
    elseif isfield(T,'T') && ~isempty(T.T), T.warpA = T.T;
    elseif isfield(T,'tform') && ~isempty(T.tform)
        try, T.warpA = T.tform.T; catch, error('Found tform field, but could not extract numeric matrix.'); end
    else
        error('Transform file has no usable matrix field. Expected A, M, T, or tform.T.');
    end
    if isfield(T,'outputSize') && ~isempty(T.outputSize), T.outSize = double(T.outputSize);
    elseif isfield(T,'size') && ~isempty(T.size), T.outSize = double(T.size);
    elseif isfield(T,'atlasSize') && ~isempty(T.atlasSize), T.outSize = double(T.atlasSize);
    elseif isfield(T,'outSize') && ~isempty(T.outSize), T.outSize = double(T.outSize);
    else, T.outSize = []; end
    if ~isfield(T,'type') || isempty(T.type), T.type = 'unknown'; end
    if ~isfield(T,'atlasSliceIndex') || isempty(T.atlasSliceIndex), T.atlasSliceIndex = NaN; end
    if ~isfield(T,'atlasMode') || isempty(T.atlasMode), T.atlasMode = ''; end
   % Do NOT rebuild simple_coronal_2d transforms here.
% registration_coronal_2d.m already saved a valid MATLAB affine2d matrix.
if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d')
    if isfield(T,'A') && ~isempty(T.A)
        T.warpA = double(T.A);
    end

    if isfield(T,'outputSize') && ~isempty(T.outputSize)
        T.outSize = double(T.outputSize);
    end

    T.scmAffineChoice = 'row_saved';
end
end

function Y = warpFunctionalSeriesToAtlas(X, T)
    A = double(T.warpA);
    if ndims(X) == 4 && isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3, error('3D atlas warp requires output size.'); end
        outSize3 = round(T.outSize(1:3)); if any(outSize3 < 1), error('Invalid 3D output size.'); end
        tform3 = affine3d(A); Rout3 = imref3d(outSize3); nTT = size(X,4); Y = zeros([outSize3 nTT], 'single');
        for tt = 1:nTT, Y(:,:,:,tt) = imwarp(single(X(:,:,:,tt)), tform3, 'linear', 'OutputView', Rout3); end
        return;
    end
    if isequal(size(A), [3 3])
    if isempty(T.outSize) || numel(T.outSize) < 2
        error('2D atlas warp requires output size.');
    end

    outSize2 = round(double(T.outSize(1:2)));
    if any(outSize2 < 1)
        error('Invalid 2D output size.');
    end

    Ause = apply2DWarpDirectionToMatrix(A, T);
    tform2 = affine2d(Ause);
    Rout2 = imref2d(outSize2);

    if ndims(X) == 3
        X2 = X;
        zSel = 1;

        X2 = prepareFunctionalSliceForReg2D(X2, T, zSel);

        nTT = size(X2,3);
        Y = zeros([outSize2 nTT], 'single');

        for tt = 1:nTT
            Y(:,:,tt) = imwarp(single(X2(:,:,tt)), ...
                tform2, 'linear', 'OutputView', Rout2);
        end
        return;

    elseif ndims(X) == 4
        if isfield(T,'sourceSliceIndex') && ~isempty(T.sourceSliceIndex) && isfinite(T.sourceSliceIndex)
            zSel = round(T.sourceSliceIndex);
        elseif isfield(T,'sourceSlice') && ~isempty(T.sourceSlice) && isfinite(T.sourceSlice)
            zSel = round(T.sourceSlice);
        else
            zSel = state.z;
        end

        zSel = max(1,min(size(X,3),zSel));
        X2 = squeeze(X(:,:,zSel,:));

        X2 = prepareFunctionalSliceForReg2D(X2, T, zSel);

        nTT = size(X2,3);
        Y = zeros([outSize2 nTT], 'single');

        for tt = 1:nTT
            Y(:,:,tt) = imwarp(single(X2(:,:,tt)), ...
                tform2, 'linear', 'OutputView', Rout2);
        end

        try
            set(info1,'String',sprintf( ...
                'Applied 2D atlas warp: source slice %d -> atlas slice %d | output [%d %d]', ...
                zSel, round(T.atlasSliceIndex), outSize2(1), outSize2(2)));
        catch
        end

        return;
    else
        error('For 2D atlas warp, PSC must be [Y X T] or [Y X Z T].');
    end
end
    error('Unsupported transform matrix size: %dx%d', size(A,1), size(A,2));
end

function [Y, report] = warpFunctionalSeriesToAtlasStepMotor(X, regList)

    Y = [];

    report = struct();
    report.nUsed = 0;
    report.sourceIdx = [];
    report.atlasIdx = [];
    report.files = {};
    report.outSize = [];

    if isempty(regList)
        return;
    end

    if ndims(X) == 3
        nSrc = 1;
        nTT = size(X,3);
    elseif ndims(X) == 4
        nSrc = size(X,3);
        nTT = size(X,4);
    else
        error('Step Motor atlas warp requires PSC [Y X T] or [Y X Z T].');
    end

    srcIdxAll = [regList.sourceIdx];
    valid = find(isfinite(srcIdxAll) & srcIdxAll >= 1 & srcIdxAll <= nSrc);

    if isempty(valid)
        error('No transform source index matches the available functional slices.');
    end

    regList = regList(valid);
    srcIdxAll = [regList.sourceIdx];

    [~,ord] = sort(srcIdxAll);
    regList = regList(ord);

    % Remove duplicate source indices, keeping the first/best candidate.
    srcSorted = [regList.sourceIdx];
    [~,ia] = unique(srcSorted, 'stable');
    regList = regList(ia);

    % Validate first transform.
    T0 = regList(1).T;
    A0 = double(T0.warpA);

    if ~isequal(size(A0), [3 3])
        error('Step Motor folder warp currently expects 2D affine transforms with 3x3 matrices.');
    end

    if ~isfield(T0,'outSize') || isempty(T0.outSize) || numel(T0.outSize) < 2
        error('First Step Motor transform has no valid outputSize/outSize.');
    end

    outSize2 = round(double(T0.outSize(1:2)));

    if any(outSize2 < 1)
        error('Invalid atlas output size in first Step Motor transform.');
    end

    nUse = numel(regList);
    Y = zeros([outSize2 nUse nTT], 'single');

    for rr = 1:nUse

        T = regList(rr).T;
        A = double(T.warpA);

        if ~isequal(size(A), [3 3])
            error('Transform for source %d is not a 2D 3x3 transform.', regList(rr).sourceIdx);
        end

        if ~isfield(T,'outSize') || isempty(T.outSize) || numel(T.outSize) < 2
            error('Transform for source %d has no valid output size.', regList(rr).sourceIdx);
        end

        thisOut = round(double(T.outSize(1:2)));

        if any(thisOut ~= outSize2)
            error(['All Step Motor transforms must have the same atlas output size.' newline ...
                   'First output size: [%d %d]' newline ...
                   'Source %d output size: [%d %d]'], ...
                   outSize2(1), outSize2(2), regList(rr).sourceIdx, thisOut(1), thisOut(2));
        end

        zSrc = regList(rr).sourceIdx;
A = apply2DWarpDirectionToMatrix(A, T);
        tform2 = affine2d(A);
        Rout2 = imref2d(outSize2);

      if ndims(X) == 3
    X2 = X;
else
    X2 = squeeze(X(:,:,zSrc,:));
end

X2 = prepareFunctionalSliceForReg2D(X2, T, zSrc);

for tt = 1:nTT
    Y(:,:,rr,tt) = imwarp(single(X2(:,:,tt)), ...
        tform2, 'linear', 'OutputView', Rout2);
end
    end

    report.nUsed = nUse;
    report.outSize = outSize2;
    report.sourceIdx = [regList.sourceIdx];

    report.atlasIdx = nan(1,nUse);
    report.files = cell(1,nUse);

    for rr = 1:nUse
    report.files{rr} = regList(rr).file;

    try
        if isfield(regList(rr).T,'atlasSliceIndex') && ...
                ~isempty(regList(rr).T.atlasSliceIndex) && ...
                isfinite(regList(rr).T.atlasSliceIndex)
            report.atlasIdx(rr) = round(regList(rr).T.atlasSliceIndex);
        end
    catch
    end
end

report.usedRegList = regList;
end


function regList = collectStepMotorRegistration2DTransforms(folderPath)

    regList = struct('sourceIdx',{},'file',{},'T',{},'score',{});

    if isempty(folderPath) || exist(folderPath,'dir') ~= 7
        return;
    end

    files = listMatFilesRecursive(folderPath, 4);

    if isempty(files)
        return;
    end

    cand = struct('sourceIdx',{},'file',{},'T',{},'score',{});

    for ii = 1:numel(files)

        f = files{ii};
        [~,nameOnly,extOnly] = fileparts(f);
        nameL = lower(nameOnly);

        if ~strcmpi(extOnly,'.mat')
            continue;
        end

        % The StepMotor session file is only an index.
        % It is NOT a transform file and must not be used by SCM.
        if ~isempty(strfind(nameL,'stepmotor_reg2d_session')) %#ok<STREMP>
            continue;
        end

        % For step-motor SCM, only use per-source-slice transform files.
        if isempty(strfind(nameL,'coronalregistration2d_source')) %#ok<STREMP>
            continue;
        end
        try
            S = load(f);
            T = extractAtlasWarpStruct(S);
        catch
            continue;
        end

        if ~isfield(T,'warpA') || isempty(T.warpA)
            continue;
        end

        A = double(T.warpA);

        % For this Step Motor workflow, keep 2D coronal transforms only.
        if ~isequal(size(A), [3 3])
            continue;
        end

        if ~isfield(T,'outSize') || isempty(T.outSize) || numel(T.outSize) < 2
            continue;
        end

        srcIdx = parseStepMotorSourceIndex(f, T);

        if ~isfinite(srcIdx) || srcIdx < 1
            continue;
        end

        srcIdx = round(srcIdx);

        score = scoreStepMotorTransformFile(f, T);

        c = struct();
        c.sourceIdx = srcIdx;
        c.file = f;
        c.T = T;
        c.score = score;

        cand(end+1) = c; %#ok<AGROW>
    end

    if isempty(cand)
        return;
    end

    srcAll = [cand.sourceIdx];
    srcUni = unique(srcAll);

    for ss = 1:numel(srcUni)
        idx = find(srcAll == srcUni(ss));

        scores = [cand(idx).score];
        [~,bestLocal] = max(scores);

        regList(end+1) = cand(idx(bestLocal)); %#ok<AGROW>
    end

    [~,ord] = sort([regList.sourceIdx]);
    regList = regList(ord);
end


function files = listMatFilesRecursive(rootDir, maxDepth)

    files = {};

    if nargin < 2 || isempty(maxDepth)
        maxDepth = 4;
    end

    walkDir(rootDir, 0);

    function walkDir(d, depth)

        if depth > maxDepth || exist(d,'dir') ~= 7
            return;
        end

        dd = dir(fullfile(d,'*.mat'));

        for kk = 1:numel(dd)
            if ~dd(kk).isdir
                files{end+1} = fullfile(dd(kk).folder, dd(kk).name); %#ok<AGROW>
            end
        end

        sub = dir(d);

        for kk = 1:numel(sub)

            if ~sub(kk).isdir
                continue;
            end

            nm = sub(kk).name;

            if strcmp(nm,'.') || strcmp(nm,'..')
                continue;
            end

            if strcmpi(nm,'private') || strcmpi(nm,'@')
                continue;
            end

            walkDir(fullfile(d,nm), depth + 1);
        end
    end
end


function idx = parseStepMotorSourceIndex(f, T)

    idx = NaN;

    try
        [~,nameOnly,~] = fileparts(f);
        s = lower(nameOnly);

        patterns = { ...
            'source[_\- ]*0*(\d+)', ...
            'src[_\- ]*0*(\d+)', ...
            'slice[_\- ]*0*(\d+)', ...
            'sl[_\- ]*0*(\d+)', ...
            'z[_\- ]*0*(\d+)'};

        for pp = 1:numel(patterns)
            tok = regexp(s, patterns{pp}, 'tokens', 'once');

            if ~isempty(tok)
                idx = str2double(tok{1});

                if isfinite(idx)
                    return;
                end
            end
        end
    catch
    end

    try
        if isfield(T,'sourceSliceIndex') && ~isempty(T.sourceSliceIndex) && isfinite(T.sourceSliceIndex)
            idx = double(T.sourceSliceIndex);
            return;
        end
    catch
    end

    try
        if isfield(T,'sourceSlice') && ~isempty(T.sourceSlice) && isfinite(T.sourceSlice)
            idx = double(T.sourceSlice);
            return;
        end
    catch
    end

    try
        if isfield(T,'sourceIndex') && ~isempty(T.sourceIndex) && isfinite(T.sourceIndex)
            idx = double(T.sourceIndex);
            return;
        end
    catch
    end
end


function score = scoreStepMotorTransformFile(f, T)

    score = 0;

    try
        [folder0,name0,~] = fileparts(f);
        s = lower([folder0 filesep name0]);

        if ~isempty(strfind(s,'coronalregistration2d')), score = score + 120; end
        if ~isempty(strfind(s,'registration2d')),        score = score + 100; end
        if ~isempty(strfind(s,'transformation')),         score = score + 70;  end
        if ~isempty(strfind(s,'source')),                 score = score + 50;  end
        if ~isempty(strfind(s,'slice')),                  score = score + 40;  end
        if ~isempty(strfind(s,'atlas')),                  score = score + 20;  end
        if ~isempty(strfind(s,'histology')),              score = score + 15;  end
        if ~isempty(strfind(s,'vascular')),               score = score + 15;  end
        if ~isempty(strfind(s,'regions')),                score = score + 15;  end
    catch
    end

    try
        if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
            score = score + 20;
        end
    catch
    end

    try
        dd = dir(f);

        % Small files are often pure transform MAT files.
        if ~isempty(dd) && dd.bytes > 0 && dd.bytes < 300000
            score = score + 10;
        end
    catch
    end
end


function startPath = getStepMotorTransformStartPath()

    startPath = getTransformStartPath();

    % If Step Motor underlay files were passed from fusi_studio,
    % start close to those selected per-slice files.
    try
        if isstruct(par) && isfield(par,'scmPerSliceUnderlayFiles') && ...
                ~isempty(par.scmPerSliceUnderlayFiles)

            f0 = par.scmPerSliceUnderlayFiles{1};

            if exist(f0,'file') == 2
                startPath = fileparts(f0);
                return;
            elseif exist(f0,'dir') == 7
                startPath = f0;
                return;
            end
        end
    catch
    end

    % Otherwise use the normal Registration2D start path.
    try
        p0 = getTransformStartPath();

        if exist(p0,'dir') == 7
            startPath = p0;
        end
    catch
    end
end


function tf = underlayMatchesTargetDims(U, yy, xx, zz)

    tf = false;

    try
        if isempty(U)
            return;
        end

        U = squeeze(U);

        % ---------------------------------------------------------
        % 2D underlay can only match a single-slice display.
        % Do NOT allow one 2D atlas image to count as a full
        % Step Motor Z-stack.
        % ---------------------------------------------------------
        if ndims(U) == 2
            tf = (zz == 1 && size(U,1) == yy && size(U,2) == xx);
            return;
        end

        % ---------------------------------------------------------
        % 3D underlay ambiguity:
        %
        % [Y X 3] can mean either:
        %   A) RGB image
        %   B) 3 grayscale slices
        %
        % For Step Motor nZ == 3, this ambiguity is dangerous.
        % Use state.isColorUnderlay to decide.
        % ---------------------------------------------------------
        if ndims(U) == 3

            if size(U,1) ~= yy || size(U,2) ~= xx
                return;
            end

            if size(U,3) == 3
                if zz == 1 && state.isColorUnderlay
                    % true RGB single-slice underlay
                    tf = true;
                    return;
                elseif zz == 3 && ~state.isColorUnderlay
                    % true 3-slice grayscale stack
                    tf = true;
                    return;
                else
                    % Do not treat RGB as Step Motor stack.
                    tf = false;
                    return;
                end
            end

            % Normal grayscale multi-slice stack.
            tf = (size(U,3) == zz);
            return;
        end

        % ---------------------------------------------------------
        % 4D RGB stack: [Y X 3 Z]
        % This is a true color stack only if Z matches.
        % ---------------------------------------------------------
        if ndims(U) == 4
            tf = (size(U,1) == yy && ...
                  size(U,2) == xx && ...
                  size(U,3) == 3  && ...
                  size(U,4) == zz);
            return;
        end

    catch
        tf = false;
    end
end

function s = compactIndexList(v)

    if isempty(v)
        s = '<none>';
        return;
    end

    v = unique(sort(round(v(:).')));

    parts = {};
    i = 1;

    while i <= numel(v)
        j = i;

        while j < numel(v) && v(j+1) == v(j) + 1
            j = j + 1;
        end

        if i == j
            parts{end+1} = sprintf('%d', v(i)); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%d-%d', v(i), v(j)); %#ok<AGROW>
        end

        i = j + 1;
    end

    s = strjoin(parts, ', ');
end


function setTitleAtlasStepMotor(report)

    try
        srcTxt = compactIndexList(report.sourceIdx);

        atlasTxt = '';

        if isfield(report,'atlasIdx') && ~isempty(report.atlasIdx)
            a = report.atlasIdx;
            a = a(isfinite(a));

            if ~isempty(a)
                atlasTxt = sprintf(' | atlas slices %s', compactIndexList(a));
            end
        end

        set(txtTitle, 'String', sprintf('%s | Step Motor atlas warp | source %s%s', ...
            fileLabel, srcTxt, atlasTxt));

    catch
        set(txtTitle, 'String', sprintf('%s | Step Motor atlas warp', fileLabel));
    end
end


function [Uatlas, msg] = buildStepMotorAtlasUnderlay(origUnderlay, currentUnderlay, regList, report, Xnative, Xatlas)

    Uatlas = [];
    msg = 'none';

    if isempty(Xatlas)
        return;
    end

    yy = size(Xatlas,1);
    xx = size(Xatlas,2);

    if ndims(Xatlas) == 4
        zz = size(Xatlas,3);
    else
        zz = 1;
    end

    % ---------------------------------------------------------
    % Use exactly the transforms that were actually used for
    % the functional warp.
    % ---------------------------------------------------------
    usedRegList = [];

    try
        if isfield(report,'usedRegList') && ~isempty(report.usedRegList)
            usedRegList = report.usedRegList;
        end
    catch
        usedRegList = [];
    end

    if isempty(usedRegList)
        usedRegList = regList;
    end

    % ---------------------------------------------------------
    % BEST CASE:
    % Use atlas/histology/vascular underlay stored inside the
    % same Registration2D MAT files.
    %
    % This is the Step Motor equivalent of the working single-slice
    % behavior:
    %
    %   PSC = warpFunctionalSeriesToAtlas(origPSC,T);
    %   bg  = atlas histology underlay directly;
    %
    % No extra warp is applied to atlas histology.
    % ---------------------------------------------------------
    try
        [UfromReg, okReg] = buildStepMotorAtlasUnderlayFromRegFiles(usedRegList, yy, xx, zz);

        if okReg && hasUsableUnderlaySignal(UfromReg)
            Uatlas = UfromReg;
            msg = 'used per-slice atlas/histology underlays from Registration2D files';
            return;
        end
    catch
        Uatlas = [];
    end

    % ---------------------------------------------------------
    % If current underlay already truly matches the atlas display
    % dimensions, keep it.
    %
    % The stricter underlayMatchesTargetDims prevents a single
    % RGB [Y X 3] histology image from being mistaken for a
    % 3-slice Step Motor stack.
    % ---------------------------------------------------------
    if underlayMatchesTargetDims(currentUnderlay, yy, xx, zz)
        Uatlas = currentUnderlay;
        msg = 'kept existing atlas-space underlay';
        return;
    end

    if underlayMatchesTargetDims(origUnderlay, yy, xx, zz)
        Uatlas = origUnderlay;
        msg = 'used existing atlas-space original underlay';
        return;
    end

    % ---------------------------------------------------------
    % FALLBACK:
    % Warp the original native Doppler/anatomical underlay
    % slice-by-slice with the same transforms.
    % ---------------------------------------------------------
    [Ustack, ok] = prepareNativeUnderlayStackForStepMotor(origUnderlay, Xnative);

    if ok
        try
            Uatlas = warpNativeUnderlayStackToAtlasStepMotor(Ustack, usedRegList, report);
            if hasUsableUnderlaySignal(Uatlas)
                msg = 'warped original native underlay slice-by-slice';
                return;
            end
        catch
            Uatlas = [];
        end
    end

    % ---------------------------------------------------------
    % Second fallback:
    % Try current displayed underlay only if it is native-space.
    % ---------------------------------------------------------
    [Ustack, ok] = prepareNativeUnderlayStackForStepMotor(currentUnderlay, Xnative);

    if ok
        try
            Uatlas = warpNativeUnderlayStackToAtlasStepMotor(Ustack, usedRegList, report);
            if hasUsableUnderlaySignal(Uatlas)
                msg = 'warped current native underlay slice-by-slice';
                return;
            end
        catch
           Uatlas = makeFunctionalContrastFallbackUnderlay(Xatlas);
    msg = 'functional contrast fallback';
        end
    end
    end 
   


function [Uatlas, ok] = buildStepMotorAtlasUnderlayFromRegFiles(usedRegList, yy, xx, zz)

    Uatlas = [];
    ok = false;

    if isempty(usedRegList)
        return;
    end

    nUse = min(numel(usedRegList), zz);

    Utmp = zeros(yy, xx, nUse, 'single');
    got = false(1, nUse);

    for rr = 1:nUse

        T = usedRegList(rr).T;

        outSize2 = [yy xx];
        try
            if isfield(T,'outSize') && ~isempty(T.outSize) && numel(T.outSize) >= 2
                outSize2 = round(double(T.outSize(1:2)));
            end
        catch
            outSize2 = [yy xx];
        end

        if any(outSize2 ~= [yy xx])
            % Functional output and underlay output must agree.
            continue;
        end

        Uplane = extractAtlasUnderlayPlaneFromRegistrationFile(usedRegList(rr).file, T, outSize2);

        if isempty(Uplane)
            continue;
        end

        Uplane = fitPlaneToSizeLocal(Uplane, yy, xx);
        Uplane(~isfinite(Uplane)) = 0;

        if hasUsableUnderlaySignal(Uplane)
            Utmp(:,:,rr) = single(Uplane);
            got(rr) = true;
        end
    end

    if all(got)
        Uatlas = double(Utmp);
        ok = true;
    end
end


function Uplane = extractAtlasUnderlayPlaneFromRegistrationFile(matFile, T, outSize2)

    Uplane = [];

    if isempty(matFile) || exist(matFile,'file') ~= 2
        return;
    end

    try
        S = load(matFile);
    catch
        return;
    end

    % Prefer fields that are likely atlas/histology/vascular display images.
    pref = { ...
        'atlasUnderlayRGB', ...
        'atlasUnderlay', ...
        'atlasImage', ...
        'histology', ...
        'histologyImage', ...
        'vascular', ...
        'vascularImage', ...
        'brainImage', ...
        'underlay', ...
        'bg', ...
        'fixedImage', ...
        'fixed', ...
        'img', ...
        'I', ...
        'Data'};

    % First search top-level fields.
    for ii = 1:numel(pref)
        if isfield(S, pref{ii})
            Uplane = acceptAtlasUnderlayCandidate(S.(pref{ii}), T, outSize2);
            if ~isempty(Uplane)
                return;
            end
        end
    end

    % Then search common registration structs.
    wrappers = {'Transf','Reg2D','RegOut','Registration2D'};

    for ww = 1:numel(wrappers)
        if isfield(S, wrappers{ww}) && isstruct(S.(wrappers{ww}))
            R = S.(wrappers{ww});

            for ii = 1:numel(pref)
                if isfield(R, pref{ii})
                    Uplane = acceptAtlasUnderlayCandidate(R.(pref{ii}), T, outSize2);
                    if ~isempty(Uplane)
                        return;
                    end
                end
            end

            fnR = fieldnames(R);
            for ii = 1:numel(fnR)
                Uplane = acceptAtlasUnderlayCandidate(R.(fnR{ii}), T, outSize2);
                if ~isempty(Uplane)
                    return;
                end
            end
        end
    end

    % Last pass: scan all top-level numeric fields.
    % Small matrices such as A/M/T are rejected inside acceptAtlasUnderlayCandidate.
    fn = fieldnames(S);
    for ii = 1:numel(fn)
        Uplane = acceptAtlasUnderlayCandidate(S.(fn{ii}), T, outSize2);
        if ~isempty(Uplane)
            return;
        end
    end
end


function Uplane = acceptAtlasUnderlayCandidate(v, T, outSize2)

    Uplane = [];

    if isempty(v)
        return;
    end

    % Struct wrapper.
    if isstruct(v)
        subPref = {'Data','data','img','image','I','underlay','atlasUnderlay','brainImage','histology','vascular'};

        for ss = 1:numel(subPref)
            if isfield(v, subPref{ss})
                Uplane = acceptAtlasUnderlayCandidate(v.(subPref{ss}), T, outSize2);
                if ~isempty(Uplane)
                    return;
                end
            end
        end
        return;
    end

    if ~(isnumeric(v) || islogical(v))
        return;
    end

    U = squeeze(double(v));

    if isempty(U) || ndims(U) < 2
        return;
    end

    % Reject tiny transform matrices such as 3x3 or 4x4.
    if size(U,1) < 16 || size(U,2) < 16
        return;
    end

    % Atlas underlay must already match transform output size.
    % This prevents accidentally using native/source images here.
    if size(U,1) ~= outSize2(1) || size(U,2) ~= outSize2(2)
        return;
    end

    if ndims(U) == 2
        Uplane = U;
        return;
    end

    if ndims(U) == 3

        % RGB single atlas/histology plane.
        if size(U,3) == 3
            Uplane = rgbToGrayLocal(U);
            return;
        end

        % Atlas volume: choose atlasSliceIndex if available.
        zPick = round(size(U,3) / 2);

        try
            if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
                zPick = round(T.atlasSliceIndex);
            end
        catch
        end

        zPick = max(1, min(size(U,3), zPick));
        Uplane = U(:,:,zPick);
        return;
    end

    if ndims(U) == 4

        % RGB stack: [Y X 3 Z]
        if size(U,3) == 3
            zPick = 1;

            try
                if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
                    zPick = round(T.atlasSliceIndex);
                end
            catch
            end

            zPick = max(1, min(size(U,4), zPick));
            RGB = squeeze(U(:,:,:,zPick));
            Uplane = rgbToGrayLocal(RGB);
            return;
        end

        % RGB stack: [Y X Z 3]
        if size(U,4) == 3
            zPick = round(size(U,3) / 2);

            try
                if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
                    zPick = round(T.atlasSliceIndex);
                end
            catch
            end

            zPick = max(1, min(size(U,3), zPick));
            RGB = squeeze(U(:,:,zPick,:));
            Uplane = rgbToGrayLocal(RGB);
            return;
        end
    end
end
function T = repairSimpleCoronal2DTransformForSCM(T)
    % Rebuild simple_coronal_2d transform for MATLAB imwarp/affine2d.
    %
    % Reason:
    % Registration GUI stores sourceSize/outputSize and manual parameters.
    % Directly using A can miss the initial source->atlas canvas scaling.
    %
    % MATLAB affine2d uses row-vector convention:
    % [x y 1] * A = [x2 y2 1]

    try
        if ~isfield(T,'type') || ~strcmpi(char(T.type), 'simple_coronal_2d')
            return;
        end

        if ~isfield(T,'sourceSize') || isempty(T.sourceSize) || numel(T.sourceSize) < 2
            return;
        end

        if ~isfield(T,'outputSize') || isempty(T.outputSize) || numel(T.outputSize) < 2
            return;
        end

        srcSize = round(double(T.sourceSize(1:2)));   % [Y X]
        outSize = round(double(T.outputSize(1:2)));   % [Y X]

        srcY = srcSize(1);
        srcX = srcSize(2);
        outY = outSize(1);
        outX = outSize(2);

        if any(srcSize < 1) || any(outSize < 1)
            return;
        end

        tx = 0;
        ty = 0;
        rotDeg = 0;
        sx = 1;
        sy = 1;

        if isfield(T,'tx') && ~isempty(T.tx) && isfinite(T.tx), tx = double(T.tx); end
        if isfield(T,'ty') && ~isempty(T.ty) && isfinite(T.ty), ty = double(T.ty); end
        if isfield(T,'rotDeg') && ~isempty(T.rotDeg) && isfinite(T.rotDeg), rotDeg = double(T.rotDeg); end
        if isfield(T,'sx') && ~isempty(T.sx) && isfinite(T.sx), sx = double(T.sx); end
        if isfield(T,'sy') && ~isempty(T.sy) && isfinite(T.sy), sy = double(T.sy); end

        % ---------------------------------------------------------
        % Important:
        % Use anisotropic base scaling by default:
        % native source [267 256] -> atlas canvas [160 228].
        %
        % This matches a GUI where the source image was first displayed
        % across the atlas canvas before manual sx/sy/rotation/translation.
        % ---------------------------------------------------------
        baseSx = outX / srcX;
        baseSy = outY / srcY;

        cxSrc = (srcX + 1) / 2;
        cySrc = (srcY + 1) / 2;
        cxOut = (outX + 1) / 2;
        cyOut = (outY + 1) / 2;

        A_centerSrc = [1 0 0; 0 1 0; -cxSrc -cySrc 1];
        A_base      = [baseSx 0 0; 0 baseSy 0; 0 0 1];
        A_manual    = [sx 0 0; 0 sy 0; 0 0 1];

        c = cosd(rotDeg);
        s = sind(rotDeg);

        % Row-vector rotation.
        A_rot = [c s 0; -s c 0; 0 0 1];

        A_toOut = [1 0 0; 0 1 0; cxOut + tx cyOut + ty 1];

        A_scm = A_centerSrc * A_base * A_manual * A_rot * A_toOut;

        T.warpA = A_scm;
        T.outSize = outSize;
        T.outputSize = outSize;
        T.scmRebuiltFromSimpleCoronal2D = true;

        fprintf('\n[SCM] Rebuilt simple_coronal_2d transform for imwarp.\n');
        fprintf('[SCM] sourceSize = [%d %d], outputSize = [%d %d]\n', srcY, srcX, outY, outX);
        fprintf('[SCM] baseSx/baseSy = %.6f / %.6f\n', baseSx, baseSy);
        fprintf('[SCM] tx/ty/rot/sx/sy = %.4f / %.4f / %.4f / %.4f / %.4f\n', tx, ty, rotDeg, sx, sy);
        fprintf('[SCM] MATLAB affine2d matrix:\n');
        disp(A_scm);

    catch ME
        warning('[SCM] Could not rebuild simple_coronal_2d transform: %s', ME.message);
    end
end

function G = rgbToGrayLocal(RGB)

    RGB = double(RGB);

    if ndims(RGB) ~= 3 || size(RGB,3) ~= 3
        G = double(RGB);
        return;
    end

    G = 0.2989 .* RGB(:,:,1) + ...
        0.5870 .* RGB(:,:,2) + ...
        0.1140 .* RGB(:,:,3);
end


function U2 = fitPlaneToSizeLocal(U2, yy, xx)

    U2 = squeeze(double(U2));

    if ndims(U2) > 2
        U2 = U2(:,:,1);
    end

    if size(U2,1) == yy && size(U2,2) == xx
        return;
    end

    try
        U2 = imresize(U2, [yy xx], 'bilinear');
    catch
        tmp = zeros(yy, xx);
        y0 = min(yy, size(U2,1));
        x0 = min(xx, size(U2,2));
        tmp(1:y0,1:x0) = U2(1:y0,1:x0);
        U2 = tmp;
    end
end
function [Uatlas, msg] = buildStepMotorFixedAtlasUnderlayOnly(usedRegList, outSize2, currentUnderlay)
    % Use ONLY fixed atlas/histology target images.
    % Never warp native underlay here.

    Uatlas = [];
    msg = 'none';

    if isempty(usedRegList) || isempty(outSize2)
        return;
    end

    yy = round(outSize2(1));
    xx = round(outSize2(2));
    nUse = numel(usedRegList);

    % ---------------------------------------------------------
    % First: if current underlay already is a true atlas-space stack,
    % keep it. Do NOT transform it.
    % ---------------------------------------------------------
    try
        U = squeeze(currentUnderlay);

        if ~isempty(U)
            if ndims(U) == 2 && nUse == 1 && size(U,1) == yy && size(U,2) == xx
                Uatlas = double(U);
                msg = 'kept current fixed atlas underlay';
                return;
            end

            if ndims(U) == 3 && size(U,1) == yy && size(U,2) == xx
                % Avoid mistaking one RGB image [Y X 3] for 3 Step Motor slices.
                if size(U,3) == nUse && ~state.isColorUnderlay
                    Uatlas = double(U);
                    msg = 'kept current fixed atlas underlay stack';
                    return;
                end
            end
        end
    catch
    end

    % ---------------------------------------------------------
    % Second: read fixed target underlays saved inside Reg2D files.
    % This only accepts fields that look like target/fixed/atlas images.
    % It intentionally does NOT use sourcePath / brainImage / source image.
    % ---------------------------------------------------------
    Utmp = zeros(yy, xx, nUse, 'single');
    got = false(1, nUse);

    for rr = 1:nUse
        try
            T = usedRegList(rr).T;
            Uplane = extractFixedAtlasUnderlayFromReg2DFile(usedRegList(rr).file, T, [yy xx]);

            if isempty(Uplane)
                continue;
            end

            Uplane = fitPlaneToSizeLocal(Uplane, yy, xx);
            Uplane(~isfinite(Uplane)) = 0;

            if hasUsableUnderlaySignal(Uplane)
                Utmp(:,:,rr) = single(Uplane);
                got(rr) = true;
            end
        catch
        end
    end

    if all(got)
        Uatlas = double(Utmp);
        msg = 'used fixed atlas/histology underlays saved in Registration2D files';
        return;
    end
end


function Uplane = extractFixedAtlasUnderlayFromReg2DFile(matFile, T, outSize2)
    % Strict target/fixed underlay extraction.
    % Do not accept generic source fields like brainImage, I, Data, bg.

    Uplane = [];

    if isempty(matFile) || exist(matFile,'file') ~= 2
        return;
    end

    try
        S = load(matFile);
    catch
        return;
    end

    pref = { ...
        'fixedImage', ...
        'fixedUnderlay', ...
        'targetImage', ...
        'targetUnderlay', ...
        'atlasFixedImage', ...
        'atlasImage', ...
        'atlasImage2D', ...
        'atlasSliceImage', ...
        'atlasUnderlay', ...
        'atlasUnderlay2D', ...
        'histologyFixed', ...
        'histologyImage', ...
        'histologyUnderlay', ...
        'vascularFixed', ...
        'vascularImage', ...
        'regionsFixed', ...
        'regionsImage'};

    % Top-level target fields.
    for ii = 1:numel(pref)
        if isfield(S, pref{ii})
            Uplane = acceptFixedAtlasCandidate(S.(pref{ii}), T, outSize2);
            if ~isempty(Uplane)
                return;
            end
        end
    end

    % Common registration structs.
    wrappers = {'Transf','Reg2D','RegOut','Registration2D'};

    for ww = 1:numel(wrappers)
        if isfield(S, wrappers{ww}) && isstruct(S.(wrappers{ww}))
            R = S.(wrappers{ww});

            for ii = 1:numel(pref)
                if isfield(R, pref{ii})
                    Uplane = acceptFixedAtlasCandidate(R.(pref{ii}), T, outSize2);
                    if ~isempty(Uplane)
                        return;
                    end
                end
            end
        end
    end
end


function Uplane = acceptFixedAtlasCandidate(v, T, outSize2)
    Uplane = [];

    if isempty(v)
        return;
    end

    if isstruct(v)
        subPref = { ...
            'fixedImage', ...
            'targetImage', ...
            'atlasImage', ...
            'atlasUnderlay', ...
            'histologyImage', ...
            'vascularImage', ...
            'regionsImage', ...
            'Data', ...
            'image', ...
            'img'};

        for ss = 1:numel(subPref)
            if isfield(v, subPref{ss})
                Uplane = acceptFixedAtlasCandidate(v.(subPref{ss}), T, outSize2);
                if ~isempty(Uplane)
                    return;
                end
            end
        end
        return;
    end

    if ~(isnumeric(v) || islogical(v))
        return;
    end

    U = squeeze(double(v));

    if isempty(U) || ndims(U) < 2
        return;
    end

    if size(U,1) < 16 || size(U,2) < 16
        return;
    end

    % Fixed target must already match atlas output canvas.
    if size(U,1) ~= outSize2(1) || size(U,2) ~= outSize2(2)
        return;
    end

    if ndims(U) == 2
        Uplane = U;
        return;
    end

    if ndims(U) == 3
        if size(U,3) == 3
            Uplane = rgbToGrayLocal(U);
            return;
        end

        zPick = round(size(U,3) / 2);

        try
            if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
                zPick = round(T.atlasSliceIndex);
            end
        catch
        end

        zPick = max(1, min(size(U,3), zPick));
        Uplane = U(:,:,zPick);
        return;
    end

    if ndims(U) == 4
        if size(U,3) == 3
            zPick = 1;

            try
                if isfield(T,'atlasSliceIndex') && ~isempty(T.atlasSliceIndex) && isfinite(T.atlasSliceIndex)
                    zPick = round(T.atlasSliceIndex);
                end
            catch
            end

            zPick = max(1, min(size(U,4), zPick));
            Uplane = rgbToGrayLocal(squeeze(U(:,:,:,zPick)));
            return;
        end
    end
end

function [Uatlas, msg] = keepAlreadyLoadedAtlasUnderlayIfPossible(Uin, outSize2, nUse)

    Uatlas = [];
    msg = 'none';

    try
        if isempty(Uin) || isempty(outSize2) || numel(outSize2) < 2
            return;
        end

        yy = round(outSize2(1));
        xx = round(outSize2(2));

        U = squeeze(double(Uin));
        U(~isfinite(U)) = 0;

        if isempty(U)
            return;
        end

        % Case 1: one 2D atlas/histology underlay.
               if ndims(U) == 2
            if size(U,1) == yy && size(U,2) == xx
                if nUse <= 1
                    Uatlas = U;
                    msg = 'kept already-loaded atlas underlay';
                    return;
                else
                    % Do NOT reuse one 2D underlay for all step-motor slices.
                    % Each source slice has its own atlas slice/background.
                    Uatlas = [];
                    msg = 'single 2D underlay not reused for step-motor stack';
                    return;
                end
            end
        end

        % Case 2: grayscale atlas stack [Y X Z].
        if ndims(U) == 3
            if size(U,1) == yy && size(U,2) == xx
                if size(U,3) == nUse
                    Uatlas = U;
                    msg = 'kept already-loaded atlas underlay stack';
                    return;
                end

                % Avoid interpreting RGB [Y X 3] as a 3-slice stack unless
                % SCM currently treats it as grayscale.
                if size(U,3) == 3 && nUse == 3 && ~state.isColorUnderlay
                    Uatlas = U;
                    msg = 'kept already-loaded 3-slice atlas underlay stack';
                    return;
                end
            end
        end

        % Case 3: RGB atlas image [Y X 3], single fixed underlay.
        if ndims(U) == 3 && size(U,3) == 3 && state.isColorUnderlay
            if size(U,1) == yy && size(U,2) == xx
                Ugray = rgbToGrayLocal(U);
                if nUse <= 1
                    Uatlas = Ugray;
                else
                    Uatlas = repmat(Ugray, [1 1 nUse]);
                end
                msg = 'kept already-loaded RGB atlas underlay as grayscale';
                return;
            end
        end

    catch
        Uatlas = [];
        msg = 'already-loaded underlay could not be reused';
    end
end

function [Uatlas, msg] = askStepMotorFixedAtlasUnderlayStack(outSize2, nUse)
    % Manual fallback: user selects fixed atlas/histology images.
    % These are NOT warped. They are only used as the background target.

    Uatlas = [];
    msg = 'none';

    if isempty(outSize2) || numel(outSize2) < 2
        return;
    end

    yy = round(outSize2(1));
    xx = round(outSize2(2));

    try
        startPath = getTransformStartPath();

        oldDir = pwd;
        cleanupObj = onCleanup(@()scmSafeCdBack(oldDir)); %#ok<NASGU>
        try, cd(startPath); catch, end

        [f,p] = uigetfile( ...
            {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
             'Fixed atlas/histology underlay files'}, ...
            sprintf('Select %d fixed atlas/histology underlay file(s)', nUse), ...
            'MultiSelect', 'on');

        if isequal(f,0)
            return;
        end

        if ischar(f)
            f = {f};
        end

        if numel(f) == 1
            fullf = fullfile(p, f{1});
            [Uraw, ~] = readUnderlayFile(fullf);
            Uraw = squeeze(double(Uraw));

            if ndims(Uraw) == 2
                if nUse == 1
                    Uatlas = fitPlaneToSizeLocal(Uraw, yy, xx);
                    msg = 'selected one fixed atlas/histology underlay';
                    return;
                else
                    Uplane = fitPlaneToSizeLocal(Uraw, yy, xx);
                    Uatlas = repmat(Uplane, [1 1 nUse]);
                    msg = 'selected one fixed atlas/histology underlay and reused it for all slices';
                    return;
                end
            end

            if ndims(Uraw) == 3
                if size(Uraw,3) == 3 && nUse ~= 3
                    Uatlas = fitPlaneToSizeLocal(rgbToGrayLocal(Uraw), yy, xx);
                    if nUse > 1
                        Uatlas = repmat(Uatlas, [1 1 nUse]);
                    end
                    msg = 'selected RGB fixed atlas/histology underlay';
                    return;
                end

                if size(Uraw,3) == nUse
                    Uatlas = zeros(yy, xx, nUse);
                    for zz0 = 1:nUse
                        Uatlas(:,:,zz0) = fitPlaneToSizeLocal(Uraw(:,:,zz0), yy, xx);
                    end
                    msg = 'selected fixed atlas/histology underlay stack';
                    return;
                end
            end
        end

        nFiles = numel(f);
        nStack = min(nFiles, nUse);
        Uatlas = zeros(yy, xx, nUse);

        for rr = 1:nStack
            fullf = fullfile(p, f{rr});
            [Uraw, ~] = readUnderlayFile(fullf);
            Uraw = squeeze(double(Uraw));

            if ndims(Uraw) == 3 && size(Uraw,3) == 3
                Uraw = rgbToGrayLocal(Uraw);
            elseif ndims(Uraw) > 2
                Uraw = Uraw(:,:,1);
            end

            Uatlas(:,:,rr) = fitPlaneToSizeLocal(Uraw, yy, xx);
        end

        if nStack < nUse
            for rr = nStack+1:nUse
                Uatlas(:,:,rr) = Uatlas(:,:,nStack);
            end
        end

        msg = 'selected fixed atlas/histology underlay files manually';

    catch ME
        warning('[SCM] Could not select fixed atlas underlay: %s', ME.message);
        Uatlas = [];
        msg = 'manual fixed atlas underlay selection failed';
    end
end

function forceStepMotorAtlasGrayUnderlay()

    ensureUnderlayStateFields();

    % Step Motor atlas underlay should be treated as a grayscale Z-stack.
    % This prevents RGB single-plane histology from being interpreted as
    % three Step Motor slices.
    state.isColorUnderlay = false;
    state.regionLabelUnderlay = [];
    state.regionColorLUT = [];
    state.regionInfo = struct();

    % Use simple robust grayscale display.
    % Avoid vessel enhancement and avoid odd color interpretation.
    uState.mode = 2;
    uState.brightness = 0;
    uState.contrast = 1;
    uState.gamma = 1;

    try
        set(popUnder, 'Value', uState.mode);
        set(slBri, 'Value', uState.brightness);
        set(slCon, 'Value', uState.contrast);
        set(slGam, 'Value', uState.gamma);

        set(txtBri, 'String', sprintf('%.2f', uState.brightness));
        set(txtCon, 'String', sprintf('%.2f', uState.contrast));
        set(txtGam, 'String', sprintf('%.2f', uState.gamma));

        updateUnderlayControlsEnable();
    catch
    end
end

function X2 = prepareFunctionalSliceForReg2D(X2, T, zSrc)
    % Ensure functional slice matches the source image used during registration.
    % Your metadata says sourceSize = [267 256].
    % If PSC slice is [256 267], SCM is using transposed orientation.

    if ndims(X2) == 2
        X2 = reshape(X2, size(X2,1), size(X2,2), 1);
    end

    if ~isfield(T,'sourceSize') || isempty(T.sourceSize) || numel(T.sourceSize) < 2
        return;
    end

    srcSize = round(double(T.sourceSize(1:2)));
    thisSize = [size(X2,1) size(X2,2)];

    if isequal(thisSize, srcSize)
        return;
    end

    if isequal(thisSize, fliplr(srcSize))
        choice = questdlg(sprintf([ ...
            'Functional source slice %d has size [%d %d], but the transform was made for [%d %d].\n\n' ...
            'This means X/Y are probably transposed between PSC and the registration source image.\n\n' ...
            'Transpose functional frames before warping?'], ...
            zSrc, thisSize(1), thisSize(2), srcSize(1), srcSize(2)), ...
            'SCM source-size mismatch', ...
            'Transpose frames', 'Cancel', 'Transpose frames');

        if isempty(choice) || strcmpi(choice,'Cancel')
            error('Atlas warp cancelled because PSC size does not match transform sourceSize.');
        end

        X2 = permute(X2, [2 1 3]);
        return;
    end

    error(['Functional source slice %d has size [%d %d], but transform sourceSize is [%d %d].' newline ...
           'Do not resize here. The registration was made on a different source image.' newline ...
           'Register the exact SCM/PSC native underlay or fix the MaskEditor source dimensions.'], ...
           zSrc, thisSize(1), thisSize(2), srcSize(1), srcSize(2));
end
function [Ustack, ok] = prepareNativeUnderlayStackForStepMotor(Uin, Xnative)

    Ustack = [];
    ok = false;

    if isempty(Uin) || isempty(Xnative)
        return;
    end

    if ndims(Xnative) == 4
        inY = size(Xnative,1);
        inX = size(Xnative,2);
        nSrc = size(Xnative,3);
        nTT  = size(Xnative,4);
    elseif ndims(Xnative) == 3
        inY = size(Xnative,1);
        inX = size(Xnative,2);
        nSrc = 1;
        nTT  = size(Xnative,3);
    else
        return;
    end

    U = squeeze(double(Uin));
    U(~isfinite(U)) = 0;

    if isempty(U)
        return;
    end

    % Case 1: single 2D native underlay.
    if ndims(U) == 2
        if size(U,1) == inY && size(U,2) == inX
            if nSrc == 1
                Ustack = reshape(U, inY, inX, 1);
            else
                Ustack = repmat(reshape(U, inY, inX, 1), [1 1 nSrc]);
            end
            ok = true;
            return;
        end
    end

    % Case 2: 3D underlay stack.
    if ndims(U) == 3

        if size(U,1) ~= inY || size(U,2) ~= inX
            return;
        end

      % RGB single-plane underlay: convert to grayscale and replicate if needed.
if size(U,3) == 3 && state.isColorUnderlay
    Ugray = rgbToGrayLocal(U);
            if nSrc == 1
                Ustack = reshape(Ugray, inY, inX, 1);
            else
                Ustack = repmat(reshape(Ugray, inY, inX, 1), [1 1 nSrc]);
            end
            ok = true;
            return;
        end

        % Proper Y x X x Z native stack.
        if size(U,3) == nSrc
            Ustack = U;
            ok = true;
            return;
        end

        % Single-slice movie underlay Y x X x T.
        if nSrc == 1 && size(U,3) == nTT
            Ustack = reshape(mean(U,3), inY, inX, 1);
            ok = true;
            return;
        end

        % Mismatched slice count but same XY: resample slice index list.
        if size(U,3) > 1
            zIdx = round(linspace(1, size(U,3), nSrc));
            zIdx = max(1, min(size(U,3), zIdx));
            Ustack = U(:,:,zIdx);
            ok = true;
            return;
        end
    end

    % Case 3: 4D underlay.
    if ndims(U) == 4

        if size(U,1) ~= inY || size(U,2) ~= inX
            return;
        end

        % Native movie stack Y x X x Z x T.
        if size(U,3) == nSrc
            Ustack = mean(U,4);
            ok = true;
            return;
        end

% RGB stack Y x X x 3 x Z.
if size(U,3) == 3 && size(U,4) == nSrc
    Ugray = zeros(inY, inX, nSrc);
    for zz0 = 1:nSrc
        Ugray(:,:,zz0) = rgbToGrayLocal(squeeze(U(:,:,:,zz0)));
    end
    Ustack = Ugray;
    ok = true;
    return;
end
    end
end


function Uatlas = warpNativeUnderlayStackToAtlasStepMotor(Ustack, usedRegList, report)

    if isempty(Ustack)
        Uatlas = [];
        return;
    end

    if isfield(report,'outSize') && ~isempty(report.outSize)
        outSize2 = round(double(report.outSize(1:2)));
    else
        T0 = usedRegList(1).T;
        outSize2 = round(double(T0.outSize(1:2)));
    end

    nUse = numel(usedRegList);
    Uatlas = zeros([outSize2 nUse], 'single');

    for rr = 1:nUse

        T = usedRegList(rr).T;
        A = double(T.warpA);

        if ~isequal(size(A), [3 3])
            error('Underlay Step Motor warp expects 2D 3x3 affine transforms.');
        end

        zSrc = usedRegList(rr).sourceIdx;
        zSrc = max(1, min(size(Ustack,3), round(zSrc)));
A = apply2DWarpDirectionToMatrix(A, T);
        tform2 = affine2d(A);
        Rout2 = imref2d(outSize2);

        Uplane = single(Ustack(:,:,zSrc));
        Uplane(~isfinite(Uplane)) = 0;

        Uatlas(:,:,rr) = imwarp(Uplane, tform2, 'linear', 'OutputView', Rout2);
    end

    Uatlas = double(Uatlas);
end


function tf = hasUsableUnderlaySignal(U)

    tf = false;

    try
        if isempty(U)
            return;
        end

        v = double(U(:));
        v = v(isfinite(v));

        if isempty(v)
            return;
        end

        lo = prctile_fallback(v, 1);
        hi = prctile_fallback(v, 99);

        tf = isfinite(lo) && isfinite(hi) && hi > lo && abs(hi - lo) > eps;
    catch
        tf = false;
    end
end


function U = makeFunctionalContrastFallbackUnderlay(X)

    X = double(X);
    X(~isfinite(X)) = 0;

    if ndims(X) == 4
        % Y x X x Z x T -> use temporal variability as pseudo-underlay.
        U = std(X, 0, 4);

        if ~hasUsableUnderlaySignal(U)
            U = mean(abs(X), 4);
        end

    elseif ndims(X) == 3
        % Y x X x T -> use temporal variability.
        U = std(X, 0, 3);

        if ~hasUsableUnderlaySignal(U)
            U = mean(abs(X), 3);
        end

    else
        U = X;
    end

    U(~isfinite(U)) = 0;
end

function Uout = warpUnderlayForCurrentDisplay(Uin, T)
    A = double(T.warpA);
    if isequal(size(A), [3 3])
        if isempty(T.outSize) || numel(T.outSize) < 2, error('2D underlay warp requires output size.'); end
        outSize2 = round(T.outSize(1:2)); tform2 = affine2d(A); Rout2 = imref2d(outSize2);
        if ndims(Uin) == 2
            Uout = imwarp(single(Uin), tform2, 'linear', 'OutputView', Rout2);
        elseif ndims(Uin) == 3
            if size(Uin,3) == 3 && state.isColorUnderlay
                Uout = zeros([outSize2 3], 'single');
                for kk = 1:3, Uout(:,:,kk) = imwarp(single(Uin(:,:,kk)), tform2, 'linear', 'OutputView', Rout2); end
            else
                n3 = size(Uin,3); Uout = zeros([outSize2 n3], 'single');
                for kk = 1:n3, Uout(:,:,kk) = imwarp(single(Uin(:,:,kk)), tform2, 'linear', 'OutputView', Rout2); end
            end
        else
            error('Unsupported underlay dimensionality for 2D warp.');
        end
        return;
    end
    if isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3, error('3D underlay warp requires output size.'); end
        outSize3 = round(T.outSize(1:3)); tform3 = affine3d(A); Rout3 = imref3d(outSize3);
        if ndims(Uin) == 3
            Uout = imwarp(single(Uin), tform3, 'linear', 'OutputView', Rout3);
        elseif ndims(Uin) == 4
            n4 = size(Uin,4); Uout = zeros([outSize3 n4], 'single');
            for kk = 1:n4, Uout(:,:,:,kk) = imwarp(single(Uin(:,:,:,kk)), tform3, 'linear', 'OutputView', Rout3); end
        else
            error('Unsupported underlay dimensionality for 3D warp.');
        end
        return;
    end
    error('Unsupported transform matrix size for underlay warp: %dx%d', size(A,1), size(A,2));
end

function tf = doesUnderlayMatchCurrentDisplay(U)
    tf = false;
    try, U = squeeze(U); tf = (size(U,1) == nY && size(U,2) == nX); catch, tf = false; end
end

function tf = doesUnderlayMatchOriginalDisplay(U)
    tf = false;
    try, U = squeeze(U); tf = (size(U,1) == size(origPSC,1) && size(U,2) == size(origPSC,2)); catch, tf = false; end
end

function tf = doesUnderlayMatchTransformOutput(U, T)
    tf = false;
    try
        U = squeeze(U); if isempty(T) || ~isfield(T,'outSize') || isempty(T.outSize), return; end
        outSize = round(double(T.outSize)); if numel(outSize) < 2, return; end
        tf = (size(U,1) == outSize(1) && size(U,2) == outSize(2));
    catch, tf = false; end
end

function tfFile = getBestTransformForUnderlay(underlayFile, Ucandidate)
    if nargin < 2, Ucandidate = []; end
    tfFile = ''; candFiles = {}; candScore = []; candDirs = {};
    try, if isfield(state,'atlasTransformFile') && ~isempty(state.atlasTransformFile), addFileCandidate(char(state.atlasTransformFile),300); end, catch, end
    try, if isfield(state,'lastAtlasTransformFile') && ~isempty(state.lastAtlasTransformFile), addFileCandidate(char(state.lastAtlasTransformFile),250); end, catch, end
    try
        if nargin >= 1 && ~isempty(underlayFile)
            udir = fileparts(char(underlayFile)); p1 = fileparts(udir); p2 = fileparts(p1);
            addDirCandidate(udir); addDirCandidate(fullfile(udir,'Registration2D')); addDirCandidate(fullfile(udir,'Registration'));
            addDirCandidate(fullfile(p1,'Registration2D')); addDirCandidate(fullfile(p1,'Registration')); addDirCandidate(p1);
            addDirCandidate(fullfile(p2,'Registration2D')); addDirCandidate(fullfile(p2,'Registration')); addDirCandidate(p2);
        end
    catch
    end
    try
        ep = getDatasetRootForSelectors();
        addDirCandidate(fullfile(ep,'Registration2D')); addDirCandidate(fullfile(ep,'Registration')); addDirCandidate(ep);
        p1 = fileparts(ep); addDirCandidate(fullfile(p1,'Registration2D')); addDirCandidate(fullfile(p1,'Registration')); addDirCandidate(p1);
    catch
    end
    exactNames = {'CoronalRegistration2D.mat','Transformation.mat'};
    wildNames = {'CoronalRegistration2D*.mat','*CoronalRegistration2D*.mat','*Registration2D*.mat','Transformation*.mat','*Transformation*.mat','*source*_atlas*.mat','*histology*.mat','*atlas*.mat'};
    for ii = 1:numel(candDirs)
        d0 = candDirs{ii}; if isempty(d0) || exist(d0,'dir') ~= 7, continue; end
        for kk = 1:numel(exactNames), addFileCandidate(fullfile(d0, exactNames{kk}),120); end
        for kk = 1:numel(wildNames)
            dd = dir(fullfile(d0, wildNames{kk}));
            for jj = 1:numel(dd), if ~dd(jj).isdir, addFileCandidate(fullfile(dd(jj).folder,dd(jj).name),60); end, end
        end
    end
    if isempty(candFiles), return; end
    [candFiles, ia] = uniquePathList(candFiles); candScore = candScore(ia);
    bestScore = -Inf; bestFile = '';
    for ii = 1:numel(candFiles)
        [ok, extraScore] = scoreTransformCandidate(candFiles{ii}, Ucandidate);
        if ~ok, continue; end
        totalScore = candScore(ii) + extraScore;
        if totalScore > bestScore, bestScore = totalScore; bestFile = candFiles{ii}; end
    end
    if ~isempty(bestFile)
        tfFile = bestFile;
        try, set(info1,'String',['Auto-detected transform: ' shortenPath(tfFile,85)],'TooltipString',tfFile); catch, end
    end

    function addDirCandidate(d)
        try, if ~isempty(d) && exist(char(d),'dir') == 7, candDirs{end+1} = char(d); end, catch, end %#ok<AGROW>
    end
    function addFileCandidate(f, baseScore)
        try, if ~isempty(f) && exist(char(f),'file') == 2, candFiles{end+1} = char(f); candScore(end+1) = baseScore; end, catch, end %#ok<AGROW>
    end
    function [ok, score] = scoreTransformCandidate(f, Ucand)
        ok = false; score = -Inf;
        try, S = load(f); T = extractAtlasWarpStruct(S); catch, return; end
        if ~isfield(T,'warpA') || isempty(T.warpA), return; end
        A = double(T.warpA); if ~(isequal(size(A),[3 3]) || isequal(size(A),[4 4])), return; end
        ok = true; score = 0; [folder0,name0,~] = fileparts(f); nameL = lower(name0); folderL = lower(folder0);
        if ~isempty(strfind(nameL,'coronalregistration2d')), score = score + 100; end %#ok<STREMP>
        if ~isempty(strfind(nameL,'registration2d')), score = score + 80; end %#ok<STREMP>
        if ~isempty(strfind(nameL,'transformation')), score = score + 60; end %#ok<STREMP>
        if ~isempty(strfind(nameL,'source')), score = score + 20; end %#ok<STREMP>
        if ~isempty(strfind(nameL,'atlas')), score = score + 20; end %#ok<STREMP>
        if ~isempty(strfind(nameL,'histology')), score = score + 25; end %#ok<STREMP>
        if ~isempty(strfind(folderL,'registration2d')) && isequal(size(A),[3 3]), score = score + 80; end %#ok<STREMP>
        if ~isempty(Ucand)
            if doesUnderlayMatchTransformOutput(Ucand,T), score = score + 600; else, score = score - 200; end
        end
        try, dd = dir(f); if ~isempty(dd) && dd.bytes > 0 && dd.bytes < 200000, score = score + 10; end, catch, end
    end
    function [u, ia] = uniquePathList(c)
        keys = cell(size(c));
        for qq = 1:numel(c)
            try, keys{qq} = char(java.io.File(c{qq}).getCanonicalPath()); catch, keys{qq} = char(c{qq}); end
            keys{qq} = strrep(keys{qq}, '/', filesep); keys{qq} = strrep(keys{qq}, '\\', filesep);
            if ispc, keys{qq} = lower(keys{qq}); end
        end
        [~,ia] = unique(keys,'stable'); u = c(ia);
    end
end

%% ==========================================================
% GENERIC HELPERS
%% ==========================================================
function tf = isPointerOverImageAxis()
    tf = false;
    try
        h = hittest(fig); if isempty(h), return; end
        axHit = ancestor(h, 'axes'); tf = ~isempty(axHit) && axHit == ax;
    catch
        try, tf = isequal(gca, ax); catch, tf = false; end
    end
end

function analysedRoot = guessAnalysedRoot(p0)
    p0 = char(p0);
    if exist(p0,'dir') ~= 7
        try, p0 = fileparts(p0); catch, end
    end
    if containsCompat(p0,'AnalysedData'), analysedRoot = p0; return; end
    if containsCompat(p0,'RawData')
        analysedRoot = strrep(p0,'RawData','AnalysedData');
        if exist(analysedRoot,'dir') ~= 7, try, mkdir(analysedRoot); catch, end, end
        return;
    end
    parent = fileparts(p0); sib = fullfile(parent,'AnalysedData');
    if exist(sib,'dir') == 7, analysedRoot = sib; return; end
    analysedRoot = p0;
end

function tf = containsCompat(s, pat)
    try, tf = contains(s, pat); catch, tf = ~isempty(strfind(s, pat)); end %#ok<STREMP>
end

function P = getSimpleExportPaths()
    root = getDatasetRootForSelectors();
    root = guessAnalysedRoot(root);
    P = struct();
    P.root = root;
    P.roiDir = fullfile(root,'ROI');
    P.scmRootDir = fullfile(root,'SCM');
    P.scmImageDir = fullfile(P.scmRootDir,'Images');
    P.scmSeriesDir = fullfile(P.scmRootDir,'Series');
    P.scmTcDir = fullfile(P.scmRootDir,'Timecourse');
    P.fileStem = sanitizeName(getAnimalID(fileLabel)); if isempty(P.fileStem), P.fileStem = 'SCM'; end
end

function Pexp = getGroupBundleExportPathsLocal()
    base = getDatasetRootForSelectors(); analysedRoot = guessAnalysedRoot(base); meta = deriveGroupBundleMetaLocal();
    bundleRoot = fullfile(analysedRoot,'GroupAnalysis','Bundles','SCM');
    subjectKey = sanitizeName(sprintf('%s_%s_%s', meta.animalID, meta.session, meta.scanID));
    Pexp = struct('root',analysedRoot,'bundleRoot',bundleRoot,'bundleDir',fullfile(bundleRoot,subjectKey), ...
        'subjectKey',subjectKey,'animalID',meta.animalID,'session',meta.session,'scanID',meta.scanID);
end

function meta = deriveGroupBundleMetaLocal()
    meta = struct('animalID','','session','','scanID','');
    txts = {fileLabel, safeParFieldLocal('loadedFile'), safeParFieldLocal('loadedPath')};
    for ii = 1:numel(txts)
        s = txts{ii}; if isempty(s), continue; end
        tok = regexpi(s,'([A-Za-z]{1,16}\d{6}[A-Za-z]?)_(S\d+).*?(FUS_\d+)','tokens','once');
        if ~isempty(tok), meta.animalID=sanitizeName(tok{1}); meta.session=sanitizeName(tok{2}); meta.scanID=sanitizeName(tok{3}); return; end
    end
    for ii = 1:numel(txts)
        s = txts{ii}; if isempty(s), continue; end
        if isempty(meta.animalID), tokA = regexpi(s,'([A-Za-z]{1,16}\d{6}[A-Za-z]?)','tokens','once'); if ~isempty(tokA), meta.animalID=sanitizeName(tokA{1}); end, end
        if isempty(meta.session), tokS = regexpi(s,'(S\d+)','tokens','once'); if ~isempty(tokS), meta.session=sanitizeName(tokS{1}); end, end
        if isempty(meta.scanID), tokF = regexpi(s,'(FUS_\d+)','tokens','once'); if ~isempty(tokF), meta.scanID=sanitizeName(tokF{1}); end, end
    end
    if isempty(meta.animalID), meta.animalID = 'Animal'; end
    if isempty(meta.session), meta.session = 'S1'; end
    if isempty(meta.scanID), meta.scanID = 'FUS_UNKNOWN'; end
end

function s = safeParFieldLocal(fn)
    s = '';
    try, if isstruct(par) && isfield(par,fn) && ~isempty(par.(fn)), s = char(par.(fn)); end, catch, s = ''; end
end

function s = getCurrentPopupStringLocal(hPop)
    s = '';
    try
        items = get(hPop,'String'); v = get(hPop,'Value');
        if iscell(items), v = max(1,min(numel(items),v)); s = char(items{v});
        else, v = max(1,min(size(items,1),v)); s = strtrim(char(items(v,:))); end
    catch, s = ''; end
end

function safeMkdirIfNeeded(pth)
    if isempty(pth), return; end
    if exist(pth,'dir') ~= 7
        ok = mkdir(pth); if ~ok, error('Could not create folder: %s', pth); end
    end
end

function titleStr = makeFullTitle(lbl)
    s = char(lbl); s = regexprep(s, '\|?\s*File:.*$', ''); titleStr = shortenMiddle(s, 110);
end

function s = getAnimalID(lbl)
    s0 = char(lbl);
    tok = regexp(s0,'(WT\d+[A-Za-z]?(?:_\w+)?_S\d+)','tokens','once'); if ~isempty(tok), s = tok{1}; return; end
    tok = regexp(s0,'(WT\d+[A-Za-z]?)','tokens','once'); if ~isempty(tok), s = tok{1}; return; end
    tok = regexp(s0,'([A-Za-z]{1,16}\d{6}[A-Za-z]?)','tokens','once'); if ~isempty(tok), s = tok{1}; return; end
    s = 'Animal';
end

function out = shortenMiddle(s, maxLen)
    s = char(s); if numel(s) <= maxLen, out = s; return; end
    keep = floor((maxLen-3)/2); out = [s(1:keep) '...' s(end-keep+1:end)];
end

function s = shortenPath(p, maxLen)
    p = char(p); if numel(p) <= maxLen, s = p; return; end
    keep = floor((maxLen-3)/2); s = [p(1:keep) '...' p(end-keep+1:end)];
end

function s = sanitizeName(s)
    if exist('isstring','builtin') && isstring(s), s = char(s); end
    s = char(s); s = strrep(s,filesep,'_'); s = regexprep(s,'[^\w\-]+','_'); s = regexprep(s,'_+','_'); s = regexprep(s,'^_+|_+$','');
    if numel(s) > 80, s = s(1:80); end
end

function tag = askExportLabel(defaultTag, dlgTitle)
    if nargin < 1 || isempty(defaultTag), defaultTag = 'Target'; end
    if nargin < 2 || isempty(dlgTitle), dlgTitle = 'Export label'; end
    defaultButton = 'Custom';
    if strcmpi(defaultTag, 'Target')
        defaultButton = 'Target';
    elseif strcmpi(defaultTag, 'Ctrl') || strcmpi(defaultTag, 'Control')
        defaultButton = 'Control';
    end
    choice = questdlg('How should this export be labeled?', dlgTitle, 'Target','Control','Custom', defaultButton);
    if isempty(choice), tag = ''; return; end
    switch lower(choice)
        case 'target', tag = 'Target';
        case 'control', tag = 'Ctrl';
        otherwise
            a = inputdlg({'Enter label (for example Target, Ctrl, Hipp, Cortex):'}, dlgTitle, 1, {defaultTag});
            if isempty(a), tag = ''; return; end
            tag = a{1};
    end
    tag = sanitizeExportTag(tag);
end

function tag = sanitizeExportTag(s)
    if exist('isstring','builtin') && isstring(s), s = char(s); end
    s = strtrim(char(s)); if isempty(s), s = 'Target'; end
    s = regexprep(s,'[^\w\-]+','_'); s = regexprep(s,'_+','_'); s = regexprep(s,'^_+|_+$','');
    if isempty(s), s = 'Target'; end
    tag = s;
end

function idx = findPopupIndexByName(hPop, targetName)
    idx = 1;
    try
        items = get(hPop,'String'); if ischar(items), items = cellstr(items); end
        for ii = 1:numel(items)
            if strcmpi(strtrim(items{ii}), strtrim(targetName)), idx = ii; return; end
        end
    catch
    end
end

function s = getStr(h)
    try, s = get(h,'String'); catch, s = ''; return; end
    if iscell(s), if isempty(s), s = ''; else, s = s{1}; end, end
    if exist('isstring','builtin') && isstring(s), if numel(s)>1, s=s(1); end, s=char(s); end
    if isnumeric(s), s = num2str(s); end
    s = char(s);
end

function [a,b] = parseRangeSafe(s, da, db)
    if nargin < 2, da = 0; end
    if nargin < 3, db = da; end
    s = char(s); s = strrep(s, char(8211), '-'); s = strrep(s, char(8212), '-'); s = strrep(s, ',', ' ');
    v = sscanf(s,'%f-%f');
    if numel(v) ~= 2, v = sscanf(s,'%f %f'); end
    if numel(v) ~= 2 || any(~isfinite(v)), a = da; b = db; else, a = v(1); b = v(2); end
end

function [a,b] = parseAxisPair(s, da, db)
    v = sscanf(strrep(char(s),',',' '),'%f');
    if numel(v) >= 2 && all(isfinite(v(1:2))), a = v(1); b = v(2); else, a = da; b = db; end
    if b < a, tmp=a; a=b; b=tmp; end
    if b == a, b = a + eps; end
end

function out = clamp(x, lo, hi)
    out = min(max(x, lo), hi);
end

function tf = isfiniteScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function rgb = toRGB(im01)
    im = double(im01); im(~isfinite(im)) = 0; im = min(max(im,0),1);
    idx = uint8(round(im*255)); rgb = ind2rgb(idx, gray(256));
end

function out = smooth2D_gauss(in, sigma)
    try, out = imgaussfilt(in, sigma); return; catch, end
    if sigma <= 0, out = in; return; end
    r = max(1,ceil(3*sigma)); x = -r:r; g = exp(-(x.^2)/(2*sigma^2)); g = g/sum(g);
    out = conv2(conv2(in,g,'same'),g','same');
end

function U = mat2gray_safe(U)
    U = double(U); mn = min(U(:)); mx = max(U(:));
    if ~isfinite(mn) || ~isfinite(mx) || mx <= mn, U(:) = 0; return; end
    U = min(max((U-mn)/(mx-mn),0),1);
end

function U = clip01_percentile(A, pLow, pHigh)
    v = A(:); v = v(isfinite(v));
    if isempty(v), U = zeros(size(A)); return; end
    lo = prctile_fallback(v,pLow); hi = prctile_fallback(v,pHigh);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, U = mat2gray_safe(A); return; end
    U = A; U(U < lo) = lo; U(U > hi) = hi; U = min(max((U-lo)/max(eps,(hi-lo)),0),1);
end

function q = prctile_fallback(v, p)
    try, q = prctile(v,p); return; catch, end
    v = sort(v(:)); n = numel(v); if n == 0, q = 0; return; end
    k = 1 + (n-1)*(p/100); k1 = floor(k); k2 = ceil(k); k1 = max(1,min(n,k1)); k2 = max(1,min(n,k2));
    if k1 == k2, q = v(k1); else, q = v(k1) + (k-k1)*(v(k2)-v(k1)); end
end
function tf = isAtlasLikeUnderlayFile(f)
    tf = false;

    try
        s = lower(char(f));

        keys = { ...
            'coronalregistration2d', ...
            'registration2d', ...
            'atlas', ...
            'histology', ...
            'histo', ...
            'registered', ...
            'warped', ...
            'source'};

        for kk = 1:numel(keys)
            if ~isempty(strfind(s, keys{kk})) %#ok<STREMP>
                tf = true;
                return;
            end
        end
    catch
        tf = false;
    end
end
end
