function fig = SCM_gui(PSC, bg, TR, par, baseline, nVolsOrig, varargin)
% SCM_gui - Studio version (MATLAB 2017b + 2023b)
% ==========================================================
% UPDATED GUI/QOL VERSION
%   1) Overlay tab: unified button/font sizes, larger gaps, cleaner layout
%   2) Underlay tab: unified button/font sizes, larger gaps, cleaner layout
%   3) Warp Functional To Atlas / Reset To Native moved to Underlay tab
%   4) Clear mask button removed from visible UI
%   5) Highlighted Load Mask button moved into bottom workflow buttons
%   6) Added Export Time Course PNG button
%   7) Improved PSC (%) y-label / time-course axis layout and readability
%   8) UTF-8 safe / ASCII-safe text only
%
% Defaults in this copy:
%   - baseline 30-240
%   - threshold 0
%   - caxis 0 100
%   - sigma 1
%   - alpha mod min 10
%   - alpha mod max 20
% ==========================================================

%% ---------------- SAFETY ----------------
assert(isscalar(TR) && isfinite(TR) && TR > 0, 'TR must be positive scalar');

d = ndims(PSC);
assert(d == 3 || d == 4, 'PSC must be [Y X T] or [Y X Z T]');

if d == 3
    [nY, nX, nT] = size(PSC);
    nZ = 1;
else
    [nY, nX, nZ, nT] = size(PSC);
end

tsec = (0:nT-1) * TR;
tmin = tsec / 60;

state.hoverMaxPts   = 1200;
state.hoverStride   = max(1, ceil(nT / state.hoverMaxPts));
state.hoverIdx      = 1:state.hoverStride:nT;
state.tminHover     = tmin(state.hoverIdx);
state.hoverMinDtSec = 0.06;

roi.lastHoverStamp  = 0;
roi.lastHoverXY     = [-inf -inf];

if ~(isnumeric(nVolsOrig) && isscalar(nVolsOrig) && isfinite(nVolsOrig))
    varargin  = [{nVolsOrig} varargin];
    nVolsOrig = nT; %#ok<NASGU>
end

%% ---------------- OPTIONALS ----------------
fileLabel = '';
if ~isempty(varargin)
    lastArg = varargin{end};
    if ischar(lastArg) || (isstring(lastArg) && isscalar(lastArg))
        fileLabel = char(lastArg);
        varargin  = varargin(1:end-1);
    end
end
if isempty(fileLabel), fileLabel = 'SCM'; end
if isstring(fileLabel), fileLabel = char(fileLabel); end
if ~ischar(fileLabel),  fileLabel = 'SCM'; end

passedMask = [];
passedMaskIsInclude = true;
if numel(varargin) >= 5, passedMask = varargin{5}; end
if numel(varargin) >= 6
    v6 = varargin{6};
    isBoolScalar = (islogical(v6) && isscalar(v6)) || ...
        (isnumeric(v6) && isscalar(v6) && (v6 == 0 || v6 == 1));
    if ~isempty(passedMask) && isBoolScalar
        passedMaskIsInclude = logical(v6);
    end
end

%% ---------------- BASELINE MODE ----------------
modeStr = 'sec';
if isfield(baseline, 'mode') && ~isempty(baseline.mode)
    try
        modeStr = lower(char(baseline.mode));
    catch
        modeStr = 'sec';
    end
end
isVolMode = (strncmpi(modeStr, 'vol', 3) || strncmpi(modeStr, 'idx', 3));

%% ---------------- STATE ----------------
state.z   = max(1, round(nZ/2));
state.cax = [0 100];

state.alphaModOn = true;
state.modMin = 10;
state.modMax = 20;

roi.size = 5;
roi.colors = lines(12);
roi.isFrozen = false;
roi.nextId = 1;
roi.lastAddStamp = 0;

% export/session naming
roi.sessionSetId = 0;              % ROI1, ROI2, ROI3 ... per opened SCM session
roi.lastExportLabel = 'Target';    % default label shown in dialog

roi.exportBusy = false;
roi.lastExportStampSec = -inf;

state.lastTcExportLabel = 'Target';

state.singleScmExportBusy = false;
state.lastSingleScmExportStampSec = -inf;
state.seriesExportBusy = false;
state.lastSeriesExportStampSec = -inf;

ROI_byZ = cell(1, nZ);
for zz = 1:nZ
    ROI_byZ{zz} = struct('id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
end

roiHandles = gobjects(0);
roiPlotPSC = gobjects(0);
roiTextHandles = gobjects(0);

uState.mode       = 3;
uState.brightness = -0.04;
uState.contrast   = 1.10;
uState.gamma      = 0.95;

MAX_CONSIZE = 300;
MAX_CONLEV  = 500;
uState.conectSize = 18;
uState.conectLev  = 35;

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


%annotation(fig, 'textbox', [0.62 0.004 0.37 0.03], ...
 %   'String', 'SCM GUI - Soner Caner Cagun - MPI Biological Cybernetics', ...
  %  'Color', [0.70 0.70 0.70], ...
   %  'FontSize', 10, ...
   %  'HorizontalAlignment', 'right', ...
   %  'EdgeColor', 'none', ...
  %   'Interpreter', 'none');

%% ---------------- MAIN IMAGE AXIS ----------------
ax = axes('Parent', fig, 'Units', 'pixels');
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
hold(ax, 'on');

bg2 = getBg2DForSlice(state.z);
hBG = image(ax, renderUnderlayRGB(bg2));

hOV = imagesc(ax, zeros(nY, nX));
set(hOV, 'AlphaData', 0);

cmapNames = { ...
    'blackbdy_iso', ...
    'hot', 'parula', 'turbo', 'jet', 'gray', 'bone', 'copper', 'pink', ...
    'viridis', 'plasma', 'magma', 'inferno'};

setOverlayColormap('blackbdy_iso');
caxis(ax, state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.Label.FontWeight = 'bold';
cb.FontSize = 12;

hold(ax, 'off');

txtTitle = uicontrol(fig, 'Style', 'text', 'String', makeFullTitle(fileLabel), ...
    'Units', 'pixels', ...
    'ForegroundColor', [0.95 0.95 0.95], ...
    'BackgroundColor', [0.05 0.05 0.05], ...
    'FontSize', 16, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');

%% ---------------- TIMECOURSE AXIS ----------------
axTC = axes('Parent', fig, 'Units', 'pixels', ...
    'Color', [0.05 0.05 0.05], ...
    'XColor', 'w', ...
    'YColor', 'w', ...
    'LineWidth', 1.2, ...
    'Box', 'on', ...
    'Layer', 'top');
hold(axTC, 'on');
grid(axTC, 'on');
axTC.FontSize = 12;
axTC.GridAlpha = 0.18;
axTC.MinorGridAlpha = 0.10;
try
    axTC.XMinorGrid = 'off';
    axTC.YMinorGrid = 'off';
catch
end

xlabel(axTC, 'Time (min)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
ylTC = ylabel(axTC, 'PSC (%)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
try
    set(ylTC, 'Units', 'normalized');
    set(ylTC, 'Position', [-0.022 0.50 0]);
    set(ylTC, 'Clipping', 'off');
catch
end

hBasePatch = patch(axTC, [0 0 0 0], [0 0 0 0], [1 1 1], ...
    'FaceAlpha', 0.10, ...
    'EdgeColor', 'none', ...
    'Visible', 'off');
hSigPatch  = patch(axTC, [0 0 0 0], [0 0 0 0], [1 1 1], ...
    'FaceAlpha', 0.10, ...
    'EdgeColor', 'none', ...
    'Visible', 'off');

hBaseTxt = text(axTC, 0, 0, '', ...
    'Color', [1.00 0.35 0.35], ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'Visible', 'off');
hSigTxt  = text(axTC, 0, 0, '', ...
    'Color', [1.00 0.75 0.35], ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'Visible', 'off');

hLivePSC = plot(axTC, state.tminHover, nan(1, numel(state.tminHover)), ':', 'LineWidth', 3.0);
hLivePSC.Color = [1.00 0.60 0.10];
hLivePSC.Visible = 'off';

hRoiCoordTxt = text(axTC, 0.99, 0.98, '', ...
    'Units', 'normalized', ...
    'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', ...
    'Color', [0.92 0.92 0.92], ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'Interpreter', 'none', ...
    'Visible', 'off');

axes(ax); %#ok<LAXES>
hLiveRect = rectangle(ax, 'Position', [1 1 1 1], ...
    'EdgeColor', [0 1 0], ...
    'LineWidth', 2, ...
    'Visible', 'off');

%% ---------------- SLICE SLIDER ----------------
slZ = uicontrol(fig, 'Style', 'slider', ...
    'Units', 'pixels', ...
    'Min', 1, ...
    'Max', max(1, nZ), ...
    'Value', min(max(1, state.z), max(1, nZ)), ...
    'SliderStep', [1/max(1, nZ-1) 5/max(1, nZ-1)], ...
    'Callback', @sliceChanged);

txtZ = uicontrol(fig, 'Style', 'text', ...
    'Units', 'pixels', ...
    'String', sprintf('Slice: %d / %d', state.z, nZ), ...
    'ForegroundColor', [0.85 0.9 1], ...
    'BackgroundColor', get(fig, 'Color'), ...
    'HorizontalAlignment', 'left', ...
    'FontWeight', 'bold', ...
    'FontSize', 13);

if nZ <= 1
    set(slZ, 'Visible', 'off', 'Enable', 'off');
    set(txtZ, 'Visible', 'off');
end

%% ---------------- MASK INIT ----------------
if isempty(passedMask)
    passedMask = deriveMaskFromUnderlay(bg, nY, nX, nZ, nT);
    passedMaskIsInclude = true;
end

mask2D = true(nY, nX);
if ~isempty(passedMask)
    mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
end
if ~passedMaskIsInclude && ~isempty(passedMask)
    mask2D = ~mask2D;
end

%% ---------------- ORIGINAL DATA SNAPSHOT ----------------
origPSC = PSC;
origBG  = bg;
origPassedMask = passedMask;

state.isAtlasWarped          = false;
state.atlasTransformFile     = '';
state.lastAtlasTransformFile = '';

% underlay display state
state.isColorUnderlay     = false;
state.regionLabelUnderlay = [];
state.regionColorLUT      = [];
state.regionInfo          = struct();

%% ---------------- RIGHT PANEL ----------------
bgPanel   = [0.10 0.10 0.11];
bgTabOn   = [0.24 0.24 0.25];
bgTabOff  = [0.14 0.14 0.15];
bgEdit    = [0.18 0.18 0.19];
bgEditDis = [0.22 0.22 0.23];
fgMain    = [0.97 0.97 0.98];
fgSub     = [0.82 0.90 1.00];
fgImp     = [1.00 0.60 0.60];

colBtnPrimary = [0.24 0.52 0.30];   % green -> main action
colBtnExport  = [0.20 0.38 0.62];   % muted blue -> export / transform / info
colBtnNeutral = [0.28 0.28 0.30];   % dark neutral -> normal utility
colBtnDanger  = [0.72 0.18 0.18];   % red -> close / destructive

controlsPanel = uipanel('Parent', fig, 'Title', 'SCM Controls', ...
    'Units', 'pixels', ...
    'BackgroundColor', bgPanel, ...
    'ForegroundColor', fgMain, ...
    'FontSize', 17, ...
    'FontWeight', 'bold');

tabBar = uipanel('Parent', controlsPanel, ...
    'Units', 'pixels', ...
    'BorderType', 'none', ...
    'BackgroundColor', bgPanel);

btnTabOverlay  = uicontrol(tabBar, 'Style', 'togglebutton', 'String', 'Overlay', ...
    'Units', 'pixels', ...
    'Callback', @(~,~)switchTab('overlay'), ...
    'BackgroundColor', bgTabOn, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'Value', 1);

btnTabUnderlay = uicontrol(tabBar, 'Style', 'togglebutton', 'String', 'Underlay', ...
    'Units', 'pixels', ...
    'Callback', @(~,~)switchTab('underlay'), ...
    'BackgroundColor', bgTabOff, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'Value', 0);

pOverlay  = uipanel('Parent', controlsPanel, ...
    'Units', 'pixels', ...
    'BorderType', 'none', ...
    'BackgroundColor', bgPanel);

pUnderlay = uipanel('Parent', controlsPanel, ...
    'Units', 'pixels', ...
    'BorderType', 'none', ...
    'BackgroundColor', bgPanel, ...
    'Visible', 'off');

info1 = uicontrol(controlsPanel, 'Style', 'text', 'String', '', ...
    'Units', 'pixels', ...
    'ForegroundColor', fgSub, ...
    'BackgroundColor', bgPanel, ...
    'HorizontalAlignment', 'left', ...
    'FontName', 'Arial', ...
    'FontSize', 12, ...
    'FontWeight', 'bold');

pad       = 18;
rowH      = 36;
gap       = 9;
sliderH   = 20;
groupGap  = 15;
wideBtnH  = 38;
smallBtnH = 34;

mkLbl = @(pp,s) uicontrol(pp, 'Style', 'text', 'String', s, ...
    'Units', 'pixels', ...
    'ForegroundColor', fgMain, ...
    'BackgroundColor', bgPanel, ...
    'HorizontalAlignment', 'left', ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold');

mkLblImp = @(pp,s) uicontrol(pp, 'Style', 'text', 'String', s, ...
    'Units', 'pixels', ...
    'ForegroundColor', fgImp, ...
    'BackgroundColor', bgPanel, ...
    'HorizontalAlignment', 'left', ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold');

mkValBox = @(pp,s) uicontrol(pp, 'Style', 'edit', 'String', s, ...
    'Units', 'pixels', ...
    'BackgroundColor', bgEditDis, ...
    'ForegroundColor', fgMain, ...
    'HorizontalAlignment', 'center', ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold', ...
    'Enable', 'inactive');

mkEdit = @(pp,s,cbk) uicontrol(pp, 'Style', 'edit', 'String', s, ...
    'Units', 'pixels', ...
    'BackgroundColor', bgEdit, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold', ...
    'Callback', cbk);

mkSlider = @(pp,minv,maxv,val,cbk) uicontrol(pp, 'Style', 'slider', ...
    'Units', 'pixels', ...
    'Min', minv, ...
    'Max', maxv, ...
    'Value', val, ...
    'Callback', cbk);

mkPopup = @(pp,choices,val,cbk) uicontrol(pp, 'Style', 'popupmenu', ...
    'String', choices, ...
    'Value', val, ...
    'Units', 'pixels', ...
    'Callback', cbk, ...
    'BackgroundColor', bgEdit, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold');

mkChk = @(pp,s,val,cbk) uicontrol(pp, 'Style', 'checkbox', 'String', s, ...
    'Units', 'pixels', ...
    'Value', val, ...
    'Callback', cbk, ...
    'BackgroundColor', bgPanel, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', 13, ...
    'FontWeight', 'bold');

mkBtn = @(pp,lbl,cbk,bgcol,fs) uicontrol(pp, 'Style', 'pushbutton', 'String', lbl, ...
    'Units', 'pixels', ...
    'Callback', cbk, ...
    'BackgroundColor', bgcol, ...
    'ForegroundColor', fgMain, ...
    'FontName', 'Arial', ...
    'FontSize', fs, ...
    'FontWeight', 'bold');

%% ---------------- Overlay controls ----------------
lblROIsz  = mkLbl(pOverlay, 'ROI size (px)');
slROI     = mkSlider(pOverlay, 1, 220, roi.size, @(~,~)setROIsize());
txtROIsz  = mkEdit(pOverlay, sprintf('%d', roi.size), @onRoiSizeEdited);
set(txtROIsz, 'TooltipString', 'Type ROI size in pixels, then press Enter.');

lblRoiXY    = mkLbl(pOverlay, 'Add ROI by center (x y)');
ebRoiXY     = mkEdit(pOverlay, '', @roiXYNoop);
set(ebRoiXY, 'TooltipString', 'Type x y, for example 120 80 or 120,80, then press Enter.');
set(ebRoiXY, 'KeyPressFcn', @roiXYKey);
btnRoiAddXY = mkBtn(pOverlay, 'ADD ROI', @addRoiFromXY, colBtnNeutral, 12);

lblBase = mkLblImp(pOverlay, 'Baseline window (s)');
ebBase  = mkEdit(pOverlay, '30-240', @onWindowEdited);
set(ebBase, 'ForegroundColor', [1.00 0.35 0.35]);

lblSig = mkLblImp(pOverlay, 'Signal window (s)');
ebSig  = mkEdit(pOverlay, '840-900', @onWindowEdited);
set(ebSig, 'ForegroundColor', [1.00 0.35 0.35]);

lblAlpha = mkLbl(pOverlay, 'Overlay alpha (%)');
slAlpha  = mkSlider(pOverlay, 0, 100, 100, @updateView);
txtAlpha = mkValBox(pOverlay, '100');

lblThr = mkLblImp(pOverlay, 'Threshold (abs %)');
ebThr  = mkEdit(pOverlay, '0', @updateView);
set(ebThr, 'ForegroundColor', [1.00 0.35 0.35]);

lblCax = mkLblImp(pOverlay, 'Display range (min max)');
ebCax  = mkEdit(pOverlay, '0 100', @updateView);
set(ebCax, 'ForegroundColor', [1.00 0.35 0.35]);

lblAlphaMod = mkLblImp(pOverlay, 'Alpha modulation');
cbAlphaMod  = mkChk(pOverlay, 'Alpha modulate by |SCM|', double(state.alphaModOn), @alphaModToggled);

lblModMin = mkLblImp(pOverlay, 'Mod Min (abs %)');
ebModMin  = mkEdit(pOverlay, '10', @updateView);
set(ebModMin, 'ForegroundColor', [1.00 0.35 0.35]);

lblModMax = mkLblImp(pOverlay, 'Mod Max (abs %)');
ebModMax  = mkEdit(pOverlay, '20', @updateView);
set(ebModMax, 'ForegroundColor', [1.00 0.35 0.35]);

lblMap = mkLbl(pOverlay, 'Colormap');
popMap = mkPopup(pOverlay, cmapNames, 1, @updateView);

lblSigma = mkLblImp(pOverlay, 'SCM smoothing sigma');
ebSigma  = mkEdit(pOverlay, '1', @computeSCM);
set(ebSigma, 'ForegroundColor', [1.00 0.35 0.35]);

btnRoiExport   = mkBtn(pOverlay, 'EXPORT ROIs (TXT)', @exportROIsCB, colBtnExport, 13);
btnScmExport   = mkBtn(pOverlay, 'EXPORT SCM IMAGE', @exportSCMImageCB, colBtnExport, 13);
btnTcPng       = mkBtn(pOverlay, 'EXPORT TIME COURSE PNG', @exportTimecoursePngCB, colBtnExport, 13);
btnScmSeries   = mkBtn(pOverlay, 'EXPORT SCM PPT', @exportScmSeries1minCB, colBtnExport, 12);
btnGroupBundle = mkBtn(pOverlay, 'EXPORT FOR GROUP ANALYSIS', @exportForGroupAnalysisCB, colBtnPrimary, 12);
btnUnfreeze    = mkBtn(pOverlay, 'UNFREEZE HOVER', @unfreezeHover, colBtnNeutral, 12);

%% ---------------- Underlay controls ----------------
lblUnderMode = mkLbl(pUnderlay, 'Underlay view');
popUnder = mkPopup(pUnderlay, { ...
    '1) Legacy (mat2gray)', ...
    '2) Robust clip (1..99%)', ...
    '3) VideoGUI robust (0.5..99.5%)', ...
    '4) Vessel enhance (conectSize/Lev)'}, uState.mode, @underlayModeChanged);

lblBri = mkLbl(pUnderlay, 'Underlay brightness');
slBri  = mkSlider(pUnderlay, -0.80, 0.80, uState.brightness, @underlaySliderChanged);
txtBri = mkValBox(pUnderlay, sprintf('%.2f', uState.brightness));

lblCon = mkLbl(pUnderlay, 'Underlay contrast');
slCon  = mkSlider(pUnderlay, 0.10, 5.00, uState.contrast, @underlaySliderChanged);
txtCon = mkValBox(pUnderlay, sprintf('%.2f', uState.contrast));

lblGam = mkLbl(pUnderlay, 'Underlay gamma');
slGam  = mkSlider(pUnderlay, 0.20, 4.00, uState.gamma, @underlaySliderChanged);
txtGam = mkValBox(pUnderlay, sprintf('%.2f', uState.gamma));

lblVsz = mkLbl(pUnderlay, 'Vessel conectSize (px)');
slVsz  = mkSlider(pUnderlay, 0, MAX_CONSIZE, uState.conectSize, @underlaySliderChanged);
set(slVsz, 'SliderStep', [1/max(1,MAX_CONSIZE) 10/max(1,MAX_CONSIZE)]);
txtVsz = mkValBox(pUnderlay, sprintf('%d', uState.conectSize));

lblVlv = mkLbl(pUnderlay, sprintf('Vessel conectLev (0..%d)', MAX_CONLEV));
slVlv  = mkSlider(pUnderlay, 0, MAX_CONLEV, uState.conectLev, @underlaySliderChanged);
set(slVlv, 'SliderStep', [1/max(1,MAX_CONLEV) 10/max(1,MAX_CONLEV)]);
txtVlv = mkValBox(pUnderlay, sprintf('%d', uState.conectLev));

btnLoadUnder  = mkBtn(pUnderlay, 'LOAD NEW UNDERLAY', @loadNewUnderlayCB, colBtnNeutral, 12);
btnWarpAtlas  = mkBtn(pUnderlay, 'WARP FUNCTIONAL TO ATLAS', @warpFunctionalToAtlasCB, colBtnExport, 12);
btnResetWarp  = mkBtn(pUnderlay, 'RESET TO NATIVE', @resetWarpToNativeCB, colBtnNeutral, 12);

%% ---------------- Bottom buttons ----------------
btnCompute = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Compute SCM', ...
    'Units', 'pixels', ...
    'Callback', @computeSCM, ...
    'BackgroundColor', colBtnPrimary, ...
    'ForegroundColor', 'w', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

btnMaskQuick = uicontrol(fig, 'Style', 'pushbutton', 'String', 'LOAD MASK', ...
    'Units', 'pixels', ...
    'Callback', @loadMaskCB, ...
    'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', 'w', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

btnOpenVid = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Open Video GUI', ...
    'Units', 'pixels', ...
    'Callback', @openVideo, ...
    'BackgroundColor', colBtnNeutral, ...
    'ForegroundColor', 'w', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

btnHelp = uicontrol(fig, 'Style', 'pushbutton', 'String', 'HELP', ...
    'Units', 'pixels', ...
    'Callback', @showHelp, ...
    'BackgroundColor', colBtnExport, ...
    'ForegroundColor', 'w', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

btnClose = uicontrol(fig, 'Style', 'pushbutton', 'String', 'CLOSE', ...
    'Units', 'pixels', ...
    'Callback', @(~,~) close(fig), ...
    'BackgroundColor', colBtnDanger, ...
    'ForegroundColor', 'w', ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

%% ---------------- Mouse callbacks ----------------
set(fig, 'WindowButtonMotionFcn', @mouseMove);
set(fig, 'WindowButtonDownFcn', @mouseClick);
set(fig, 'WindowScrollWheelFcn', @mouseScroll);

%% ---------------- Resize ----------------
set(fig, 'ResizeFcn', @(~,~)layoutUI());

%% ---------------- Initial ----------------
alphaModToggled();
updateUnderlayControlsEnable();
updateInfoLines();
layoutUI();
computeSCM();
redrawROIsForCurrentSlice();

%% ==========================================================
% UI
%% ==========================================================
function switchTab(which)
    which = lower(char(which));
    if strcmp(which, 'overlay')
        set(pOverlay, 'Visible', 'on');
        set(pUnderlay, 'Visible', 'off');

        set(btnTabOverlay, ...
            'Value', 1, ...
            'BackgroundColor', bgTabOn, ...
            'ForegroundColor', fgMain);

        set(btnTabUnderlay, ...
            'Value', 0, ...
            'BackgroundColor', bgTabOff, ...
            'ForegroundColor', [0.88 0.88 0.90]);
    else
        set(pOverlay, 'Visible', 'off');
        set(pUnderlay, 'Visible', 'on');

        set(btnTabOverlay, ...
            'Value', 0, ...
            'BackgroundColor', bgTabOff, ...
            'ForegroundColor', [0.88 0.88 0.90]);

        set(btnTabUnderlay, ...
            'Value', 1, ...
            'BackgroundColor', bgTabOn, ...
            'ForegroundColor', fgMain);
    end
end

function layoutUI()
    pos = get(fig, 'Position');
    W = pos(3);
    Hh = pos(4);

    leftM   = 64;
    rightM  = 36;
    topM    = 58;
    botM    = 60;
    gapX    = 36;
    gapY    = 24;

 panelW  = min(760, max(520, round(0.36 * W)));

if Hh < 980
    btnH   = 46;
    btnGap = 8;
else
    btnH   = 54;
    btnGap = 12;
end

    yClose  = 28;
    yHelp   = yClose;
    yOpen   = yClose + btnH + btnGap;
    yMask   = yOpen  + btnH + btnGap;
    yComp   = yMask  + btnH + btnGap;
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

    leftW = max(520, panelX - leftM - gapX);

tcH = min(238, max(180, round(0.22 * Hh)));
axH = max(360, Hh - botM - tcH - gapY - topM);

    axX = leftM;
    axY = botM + tcH + gapY;
    set(ax,   'Position', [axX axY leftW axH]);

tcLeftPad = 8;
set(axTC, 'Position', [axX + tcLeftPad botM leftW - tcLeftPad tcH]);

set(txtTitle, ...
    'Position', [axX axY + axH + 10 leftW 28], ...
    'String', makeFullTitle(fileLabel), ...
    'Visible', 'on');

try
    set(ylTC, 'Units', 'normalized');
    set(ylTC, 'Position', [-0.022 0.50 0]);
    set(ylTC, 'Clipping', 'off');
catch
end
    tabH     = 42;
    statusH  = 58;
    titlePad = 30;

    set(tabBar, 'Position', [12 panelH - tabH - titlePad panelW - 24 tabH]);

    btnW = floor((panelW - 24 - 10) / 2);
    set(btnTabOverlay,  'Position', [0 0 btnW tabH]);
    set(btnTabUnderlay, 'Position', [btnW + 10 0 btnW tabH]);

    contentX = 12;
    contentY = 14 + statusH;
    contentW = panelW - 24;
    contentH = panelH - tabH - titlePad - statusH - 20;

    set(pOverlay,  'Position', [contentX contentY contentW contentH]);
    set(pUnderlay, 'Position', [contentX contentY contentW contentH]);

    set(info1, 'Position', [contentX 8 contentW statusH]);

    layoutOverlay(contentW, contentH);
    layoutUnder(contentW, contentH);
end

    function layoutOverlay(w, h)
    compact = (h < 700);

    if compact
        rowHLoc      = 30;
        gapLoc       = 5;
        groupGapLoc  = 8;
        sliderHLoc   = 16;
        wideBtnHLoc  = 32;
        smallBtnHLoc = 30;
    else
        rowHLoc      = rowH;
        gapLoc       = gap;
        groupGapLoc  = groupGap;
        sliderHLoc   = sliderH;
        wideBtnHLoc  = wideBtnH;
        smallBtnHLoc = smallBtnH;
    end

    xLabel = pad;
    wLabel = 240;
    wVal   = 120;
    xVal   = w - pad - wVal;
    xCtrl  = xLabel + wLabel + 16;
    wCtrl  = max(90, xVal - xCtrl - 12);

    y = h - rowHLoc;

    setRowSlider(lblROIsz, slROI, txtROIsz);

    set(lblRoiXY,    'Position', [xLabel y wLabel rowHLoc]);
    set(ebRoiXY,     'Position', [xCtrl  y wCtrl  rowHLoc]);
    set(btnRoiAddXY, 'Position', [xVal   y wVal   rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);

    setRowEdit(lblBase, ebBase);
    setRowEdit(lblSig,  ebSig);
    y = y + (gapLoc - groupGapLoc);

    setRowSlider(lblAlpha, slAlpha, txtAlpha);
    setRowEdit(lblThr, ebThr);
    setRowEdit(lblCax, ebCax);

    set(lblAlphaMod, 'Position', [xLabel y wLabel rowHLoc]);
    set(cbAlphaMod,  'Position', [xCtrl y (w - xCtrl - pad) rowHLoc]);
    y = y - (rowHLoc + gapLoc);

    setRowEdit(lblModMin, ebModMin);
    setRowEdit(lblModMax, ebModMax);

    set(lblMap, 'Position', [xLabel y wLabel rowHLoc]);
    set(popMap, 'Position', [xCtrl y (w - xCtrl - pad) rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);

    setRowEdit(lblSigma, ebSigma);
    y = y - 2;

   btnW2 = floor((w - 2*pad - 10) / 2);

set(btnRoiExport, 'Position', [xLabel y btnW2 wideBtnHLoc]);
set(btnScmExport, 'Position', [xLabel + btnW2 + 10 y btnW2 wideBtnHLoc]);
y = y - (wideBtnHLoc + gapLoc);

set(btnTcPng,     'Position', [xLabel y btnW2 wideBtnHLoc]);
set(btnScmSeries, 'Position', [xLabel + btnW2 + 10 y btnW2 wideBtnHLoc]);
y = y - (wideBtnHLoc + gapLoc);

set(btnGroupBundle, 'Position', [xLabel y (w - 2*pad) wideBtnHLoc]);
y = y - (wideBtnHLoc + groupGapLoc);

set(btnUnfreeze, 'Position', [xLabel y (w - 2*pad) smallBtnHLoc]);

    function setRowSlider(lbl, sl, valbox)
        set(lbl,    'Position', [xLabel y wLabel rowHLoc]);
        set(sl,     'Position', [xCtrl y + round((rowHLoc - sliderHLoc)/2) wCtrl sliderHLoc]);
        set(valbox, 'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end

    function setRowEdit(lbl, ed)
        set(lbl, 'Position', [xLabel y wLabel rowHLoc]);
        set(ed,  'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end
end

    function layoutUnder(w, h)
    compact = (h < 700);

    if compact
        rowHLoc     = 30;
        gapLoc      = 5;
        groupGapLoc = 8;
        sliderHLoc  = 16;
        wideBtnHLoc = 32;
    else
        rowHLoc     = rowH;
        gapLoc      = gap;
        groupGapLoc = groupGap;
        sliderHLoc  = sliderH;
        wideBtnHLoc = wideBtnH;
    end

    xLabel = pad;
    wLabel = 250;
    wVal   = 120;
    xVal   = w - pad - wVal;
    xCtrl  = xLabel + wLabel + 16;
    wCtrl  = max(90, xVal - xCtrl - 12);

    y = h - rowHLoc;

    set(lblUnderMode, 'Position', [xLabel y wLabel rowHLoc]);
    set(popUnder,     'Position', [xCtrl y (w - xCtrl - pad) rowHLoc]);
    y = y - (rowHLoc + groupGapLoc);

    setRowSlider(lblBri, slBri, txtBri);
    setRowSlider(lblCon, slCon, txtCon);
    setRowSlider(lblGam, slGam, txtGam);
    setRowSlider(lblVsz, slVsz, txtVsz);
    setRowSlider(lblVlv, slVlv, txtVlv);

    y = y - 2;
    set(btnLoadUnder, 'Position', [xLabel y (w - 2*pad) wideBtnHLoc]);
    y = y - (wideBtnHLoc + gapLoc);

    set(btnWarpAtlas, 'Position', [xLabel y (w - 2*pad) wideBtnHLoc]);
    y = y - (wideBtnHLoc + gapLoc);

    set(btnResetWarp, 'Position', [xLabel y (w - 2*pad) wideBtnHLoc]);

    function setRowSlider(lbl, sl, valbox)
        set(lbl,    'Position', [xLabel y wLabel rowHLoc]);
        set(sl,     'Position', [xCtrl y + round((rowHLoc - sliderHLoc)/2) wCtrl sliderHLoc]);
        set(valbox, 'Position', [xVal y wVal rowHLoc]);
        y = y - (rowHLoc + gapLoc);
    end
end

%% ==========================================================
% Callbacks
%% ==========================================================
function onWindowEdited(~,~)
    computeSCM();
end

function sliceChanged(~,~)
    zNew = round(get(slZ, 'Value'));
    zNew = max(1, min(nZ, zNew));
    state.z = zNew;
    set(slZ, 'Value', state.z);

    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ, 'String', sprintf('Slice: %d / %d', state.z, nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
    else
        mask2D = true(nY, nX);
    end
    if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG, 'CData', renderUnderlayRGB(bg2));

    roi.isFrozen = false;
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
end

function unfreezeHover(~,~)
    roi.isFrozen = false;
    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC, 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
end

function setROIsize()
    roi.size = max(1, round(get(slROI, 'Value')));
    set(txtROIsz, 'String', sprintf('%d', roi.size));
end

function onRoiSizeEdited(~,~)
    v = str2double(strtrim(getStr(txtROIsz)));
    if ~isfinite(v), v = roi.size; end
    v = round(v);
    v = max(1, min(220, v));
    roi.size = v;
    set(slROI, 'Value', roi.size);
    set(txtROIsz, 'String', sprintf('%d', roi.size));
end

function mouseMove(~,~)
    if roi.isFrozen, return; end
    if ~isPointerOverImageAxis(), return; end

    cp = get(ax, 'CurrentPoint');
    x = round(cp(1,1));
    ypix = round(cp(1,2));

    if x < 1 || x > nX || ypix < 1 || ypix > nY
        set(hLiveRect, 'Visible', 'off');
        set(hLivePSC, 'Visible', 'off');
        set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
        return;
    end

    if x == roi.lastHoverXY(1) && ypix == roi.lastHoverXY(2)
        return;
    end
    roi.lastHoverXY = [x ypix];

    hlf = floor(roi.size/2);
    x1 = max(1, x-hlf);
    x2 = min(nX, x+hlf);
    y1 = max(1, ypix-hlf);
    y2 = min(nY, ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1))+1, :);
    set(hLiveRect, 'Position', [x1 y1 x2-x1+1 y2-y1+1], ...
        'EdgeColor', col, ...
        'Visible', 'on');

    set(hRoiCoordTxt, 'String', sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1, x2, y1, y2), ...
        'Visible', 'on');

    tNow = now;
    if roi.lastHoverStamp ~= 0 && (tNow - roi.lastHoverStamp)*86400 < state.hoverMinDtSec
        return;
    end
    roi.lastHoverStamp = tNow;

    tc = computeRoiPSC_idx(state.z, x1, x2, y1, y2, state.hoverIdx);
    if isempty(tc) || numel(tc) ~= numel(state.tminHover)
        set(hLivePSC, 'Visible', 'off');
        return;
    end

    set(hLivePSC, 'XData', state.tminHover, 'YData', tc, 'Visible', 'on');

    mn = min(tc);
    mx = max(tc);
    if isfinite(mn) && isfinite(mx) && mx > mn
        padY = max(0.15 * (mx-mn), 0.5);
        set(axTC, 'YLim', [mn-padY mx+padY]);
        drawTimeWindows();
    end
end

function roiXYNoop(~,~)
end

function roiXYKey(~,evt)
    try
        if isfield(evt, 'Key') && (strcmpi(evt.Key, 'return') || strcmpi(evt.Key, 'enter'))
            addRoiFromXY();
        end
    catch
    end
end

function tc = computeRoiPSC(x1, x2, y1, y2)
    tc = computeRoiPSC_atSlice(state.z, x1, x2, y1, y2);
end

function tc = computeRoiPSC_atSlice(zSel, x1, x2, y1, y2)
    try
        if ndims(PSC) == 3
            blk = PSC(y1:y2, x1:x2, :);
            tc  = squeeze(mean(mean(blk, 1), 2));
        else
            blk = PSC(y1:y2, x1:x2, zSel, :);
            tc  = squeeze(mean(mean(blk, 1), 2));
        end
        tc = tc(:).';
    catch
        tc = [];
    end

        if ~isempty(tc) && all(isfinite(tc))
        mn = min(tc);
        mx = max(tc);
        if isfinite(mn) && isfinite(mx) && mx > mn
            padY = max(0.15 * (mx-mn), 0.5);
            set(axTC, 'YLim', [mn-padY mx+padY]);
            drawTimeWindows();
        end
    end
end

function tc = computeRoiPSC_idx(zSel, x1, x2, y1, y2, idx)
    try
        if ndims(PSC) == 3
            blk = PSC(y1:y2, x1:x2, idx);
            tc  = squeeze(mean(mean(blk, 1), 2));
        else
            blk = PSC(y1:y2, x1:x2, zSel, idx);
            tc  = squeeze(mean(mean(blk, 1), 2));
        end
        tc = tc(:).';
    catch
        tc = [];
    end
end

function addRoiFromXY(~,~)
    tNow = now;
    if roi.lastAddStamp ~= 0
        if (tNow - roi.lastAddStamp) * 86400 < 0.20
            return;
        end
    end
    roi.lastAddStamp = tNow;

    s = strtrim(getStr(ebRoiXY));
    if isempty(s), return; end

    s = strrep(s, ',', ' ');
    v = sscanf(s, '%f');
    if numel(v) < 2 || ~isfinite(v(1)) || ~isfinite(v(2))
        warndlg('Enter ROI center as: x y   for example 120 80 or 120,80', 'Add ROI');
        return;
    end

    x = round(v(1));
    ypix = round(v(2));

    x    = clamp(x, 1, nX);
    ypix = clamp(ypix, 1, nY);

    hlf = floor(roi.size/2);
    x1 = max(1, x-hlf);
    x2 = min(nX, x+hlf);
    y1 = max(1, ypix-hlf);
    y2 = min(nY, ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1))+1, :);

    ROI_byZ{state.z}(end+1) = struct( ...
        'id', roi.nextId, ...
        'x1', x1, 'x2', x2, 'y1', y1, 'y2', y2, 'color', col);
    roi.nextId = roi.nextId + 1;

    roi.isFrozen = true;

    redrawROIsForCurrentSlice();

    set(hLiveRect, 'Position', [x1 y1 x2-x1+1 y2-y1+1], ...
        'EdgeColor', col, ...
        'Visible', 'on');

    tcHover = computeRoiPSC_idx(state.z, x1, x2, y1, y2, state.hoverIdx);
    if ~isempty(tcHover) && numel(tcHover) == numel(state.tminHover)
        set(hLivePSC, 'XData', state.tminHover, 'YData', tcHover, 'Visible', 'on');
    else
        set(hLivePSC, 'Visible', 'off');
    end

    set(hRoiCoordTxt, 'String', sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1, x2, y1, y2), ...
        'Visible', 'on');

    drawTimeWindows();
end

function mouseScroll(~,evt)
    if nZ <= 1, return; end
    if ~isPointerOverImageAxis(), return; end

    dz = -sign(evt.VerticalScrollCount);
    if dz == 0, return; end

    state.z = max(1, min(nZ, state.z+dz));
    if ~isempty(slZ) && isgraphics(slZ), set(slZ, 'Value', state.z); end
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ, 'String', sprintf('Slice: %d / %d', state.z, nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
    else
        mask2D = true(nY, nX);
    end
    if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG, 'CData', renderUnderlayRGB(bg2));

    roi.isFrozen = false;
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
end

function mouseClick(~,~)
    if ~isPointerOverImageAxis(), return; end

    cp = get(ax, 'CurrentPoint');
    x = round(cp(1,1));
    ypix = round(cp(1,2));
    if x < 1 || x > nX || ypix < 1 || ypix > nY, return; end

    hlf = floor(roi.size/2);
    x1 = max(1, x-hlf);
    x2 = min(nX, x+hlf);
    y1 = max(1, ypix-hlf);
    y2 = min(nY, ypix+hlf);

    type = get(fig, 'SelectionType');
    if strcmp(type, 'normal')
        roi.isFrozen = true;
        tc = computeRoiPSC_atSlice(state.z, x1, x2, y1, y2);
        if numel(tc) ~= nT, return; end

        col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1))+1, :);
        ROI_byZ{state.z}(end+1) = struct( ...
            'id', roi.nextId, ...
            'x1', x1, 'x2', x2, 'y1', y1, 'y2', y2, 'color', col);
        roi.nextId = roi.nextId + 1;

        redrawROIsForCurrentSlice();

        tcHover = computeRoiPSC_idx(state.z, x1, x2, y1, y2, state.hoverIdx);
        if ~isempty(tcHover) && numel(tcHover) == numel(state.tminHover)
            set(hLivePSC, 'XData', state.tminHover, 'YData', tcHover, 'Visible', 'on');
        else
            set(hLivePSC, 'Visible', 'off');
        end

        set(hRoiCoordTxt, 'String', sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1, x2, y1, y2), ...
            'Visible', 'on');

        drawTimeWindows();

    elseif strcmp(type, 'alt')
        roi.isFrozen = false;
        if ~isempty(ROI_byZ{state.z})
            ROI = ROI_byZ{state.z};
            ctr = arrayfun(@(r)[(r.x1+r.x2)/2, (r.y1+r.y2)/2], ROI, 'uni', 0);
            ctr = cat(1, ctr{:});
            [~, i] = min(sum((ctr-[x ypix]).^2, 2));
            ROI(i) = [];
            ROI_byZ{state.z} = ROI;
            redrawROIsForCurrentSlice();
        end
        set(hLiveRect, 'Visible', 'off');
        set(hLivePSC, 'Visible', 'off');
        set(hRoiCoordTxt, 'Visible', 'off', 'String', '');
    end
end

function computeSCM(~,~)
    [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
    [s0,s1] = parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

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

    if b1i < b0i, tmp = b0i; b0i = b1i; b1i = tmp; end
    if s1i < s0i, tmp = s0i; s0i = s1i; s1i = tmp; end

    PSCz = getPSCForSlice(state.z);
    baseMap = mean(PSCz(:,:,b0i:b1i), 3);
    sigMap  = mean(PSCz(:,:,s0i:s1i), 3);
    map     = sigMap - baseMap;

    if sig > 0
        map = smooth2D_gauss(map, sig);
    end

    map(~mask2D) = 0;
    set(hOV, 'CData', map);

    updateView();
    drawTimeWindows();
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

    thr = str2double(getStr(ebThr));
    if ~isfinite(thr), thr = 0; end

    caxv = sscanf(getStr(ebCax), '%f');
    if numel(caxv) >= 2 && isfinite(caxv(1)) && isfinite(caxv(2)) && caxv(2) ~= caxv(1)
        state.cax = caxv(1:2).';
        if state.cax(2) < state.cax(1)
            state.cax = fliplr(state.cax);
        end
    end

    maps = get(popMap, 'String');
    idx  = get(popMap, 'Value');
    if iscell(maps)
        cmapName = maps{idx};
    else
        cmapName = strtrim(maps(idx,:));
    end
    setOverlayColormap(cmapName);

    mMin = str2double(getStr(ebModMin));
    if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax));
    if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin
        tmp = mMin; mMin = mMax; mMax = tmp;
    end
    state.modMin = mMin;
    state.modMax = mMax;

    ov = get(hOV, 'CData');

    baseMask = double(mask2D);
    thrMask  = double(abs(ov) >= thr);

    if ~state.alphaModOn
        alpha = (a/100) .* thrMask .* baseMask;
    else
        effLo = max(state.modMin, thr);
        effHi = state.modMax;

        if ~isfinite(effHi) || effHi <= effLo
            effHi = max(abs(ov(:)));
        end
        if ~isfinite(effHi) || effHi <= effLo
            effHi = effLo + eps;
        end

        mod = (abs(ov) - effLo) ./ max(eps, (effHi - effLo));
        mod(~isfinite(mod)) = 0;
        mod = min(max(mod, 0), 1);

        alpha = (a/100) .* mod .* thrMask .* baseMask;
    end

    set(hOV, 'AlphaData', alpha);
    caxis(ax, state.cax);
end

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

    uState.conectSize = round(get(slVsz, 'Value'));
    uState.conectLev  = round(get(slVlv, 'Value'));

    uState.conectSize = max(0, min(MAX_CONSIZE, uState.conectSize));
    uState.conectLev  = max(0, min(MAX_CONLEV,  uState.conectLev));

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
    set(slVsz, 'Enable', onoff(isVessel));
    set(txtVsz, 'Enable', onoff(isVessel));
    set(slVlv, 'Enable', onoff(isVessel));
    set(txtVlv, 'Enable', onoff(isVessel));
end

function updateInfoLines()
    modeNames = {'Legacy', 'Robust(1..99)', 'VideoGUI(0.5..99.5)', 'Vessel enhance'};
    m = uState.mode;
    if m < 1 || m > 4, m = 3; end
    set(info1, 'String', sprintf('TR = %.4gs | Slice %d/%d | Underlay: %s', TR, state.z, nZ, modeNames{m}));
end

function s = onoff(tf)
    if tf
        s = 'on';
    else
        s = 'off';
    end
end

%% ==========================================================
% ROI Export
%% ==========================================================
function exportROIsCB(~,~)
    if roi.exportBusy
        return;
    end

    tNowSec = now * 86400;
    if (tNowSec - roi.lastExportStampSec) < 0.75
        return;
    end

    roi.exportBusy = true;
    c = onCleanup(@releaseRoiExportLock); %#ok<NASGU>

    nTot = 0;
    for zz = 1:nZ
        nTot = nTot + numel(ROI_byZ{zz});
    end
    if nTot == 0
        warndlg('No ROIs to export. Add ROIs first.', 'Export ROIs');
        return;
    end

    try
        roiDir = getAutoRoiDir();
safeMkdirIfNeeded(roiDir);

labelTag = askExportLabel(roi.lastExportLabel, 'ROI export label');
if isempty(labelTag)
    return;
end
roi.lastExportLabel = labelTag;

roi.sessionSetId = roi.sessionSetId + 1;
setId = roi.sessionSetId;

dIdx = 1;

        flat = struct('z', {}, 'id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
        for zz = 1:nZ
            ROI = ROI_byZ{zz};
            for k = 1:numel(ROI)
                r = ROI(k);
                flat(end+1) = struct( ...
                    'z', zz, ...
                    'id', r.id, ...
                    'x1', r.x1, ...
                    'x2', r.x2, ...
                    'y1', r.y1, ...
                    'y2', r.y2, ...
                    'color', r.color); %#ok<AGROW>
            end
        end

        if isempty(flat)
            warndlg('No ROIs to export.', 'Export ROIs');
            return;
        end

        keys = cell(numel(flat), 1);
        for i = 1:numel(flat)
            keys{i} = sprintf('%d_%d_%d_%d_%d', flat(i).z, flat(i).x1, flat(i).x2, flat(i).y1, flat(i).y2);
        end
        [~, ia] = unique(keys, 'stable');
        flat = flat(sort(ia));

        if ~isempty(flat)
            A = [[flat.z].' [flat.id].'];
            [~, ord] = sortrows(A, [1 2]);
            flat = flat(ord);
        end

       for i = 1:numel(flat)
    r = flat(i);

    outFile = fullfile(roiDir, sprintf('ROI%d_%s_d%d.txt', setId, labelTag, dIdx));
    while exist(outFile, 'file') == 2
        dIdx = dIdx + 1;
        outFile = fullfile(roiDir, sprintf('ROI%d_%s_d%d.txt', setId, labelTag, dIdx));
    end

            fid = fopen(outFile, 'w');
            if fid < 0
                error('Could not write ROI file: %s', outFile);
            end

            fprintf(fid, '# ROI export from SCM_gui\n');
            fprintf(fid, '# Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fprintf(fid, '# FileLabel: %s\n', fileLabel);
            fprintf(fid, '# TR_sec: %.6g\n', TR);
            fprintf(fid, '# nY nX nZ nT: %d %d %d %d\n', nY, nX, nZ, nT);
           fprintf(fid, '# ROI_SET_ID: %d\n', setId);
fprintf(fid, '# ROI_LABEL: %s\n', labelTag);
fprintf(fid, '# ROI_D_INDEX: %d\n', dIdx);
fprintf(fid, '# ROI_MARKER_ID: %d\n', r.id);
            fprintf(fid, '# SLICE: %d\n', r.z);
            fprintf(fid, '# BaselineWindow: %s\n', getStr(ebBase));
            fprintf(fid, '# SignalWindow:   %s\n', getStr(ebSig));

            fprintf(fid, '# x1 x2 y1 y2\n');
            fprintf(fid, '%d %d %d %d\n', r.x1, r.x2, r.y1, r.y2);

            fprintf(fid, '# color_rgb\n');
            fprintf(fid, '%.6f %.6f %.6f\n', r.color(1), r.color(2), r.color(3));

            tc = computeRoiPSC_atSlice(r.z, r.x1, r.x2, r.y1, r.y2);
            if isempty(tc) || numel(tc) ~= nT
                tc = nan(1, nT);
            end

            fprintf(fid, '# columns: time_sec\ttime_min\tPSC\n');
            for ii = 1:nT
                fprintf(fid, '%.6f\t%.6f\t%.6f\n', tsec(ii), tmin(ii), tc(ii));
            end

            fclose(fid);
            dIdx = dIdx + 1;
        end

        msgbox(sprintf('Exported %d ROI(s) to:\n%s\n(as ROI%d_%s_d#.txt)', ...
    numel(flat), roiDir, setId, labelTag), 'Export ROIs');

    catch ME
        errordlg(ME.message, 'ROI export failed');
    end
end

function releaseRoiExportLock()
    roi.exportBusy = false;
    roi.lastExportStampSec = now * 86400;
end

    function roiDir = getAutoRoiDir()
    P = getSimpleExportPaths();
    roiDir = P.roiDir;
end

%% ==========================================================
% SCM Image export
%% ==========================================================
function exportSCMImageCB(~,~)
    if state.singleScmExportBusy
        return;
    end

    tNowSec = now * 86400;
    if (tNowSec - state.lastSingleScmExportStampSec) < 0.75
        return;
    end

    state.singleScmExportBusy = true;
    c = onCleanup(@releaseSingleScmExportLock); %#ok<NASGU>

    tf = [];
    slidePng = '';
    try
        P = getSimpleExportPaths();
outDir = P.scmImageDir;
safeMkdirIfNeeded(outDir);

stamp = datestr(now, 'yyyymmdd_HHMMSS');
baseName = sprintf('SCM_z%02d_%s', state.z, stamp);

        outPng = fullfile(outDir, [baseName '.png']);
        outTif = fullfile(outDir, [baseName '.tif']);
        outJpg = fullfile(outDir, [baseName '.jpg']);

        tf = figure('Visible', 'off', ...
            'Color', [0.05 0.05 0.05], ...
            'InvertHardcopy', 'off', ...
            'Units', 'pixels', ...
            'Position', [200 120 1400 980]);

        ax2 = axes('Parent', tf, 'Units', 'normalized', 'Position', [0.06 0.10 0.74 0.84]);
        axis(ax2, 'image');
        axis(ax2, 'off');
        set(ax2, 'YDir', 'reverse');
        hold(ax2, 'on');

        bgRGB = get(hBG, 'CData');
        image(ax2, bgRGB);

        ov = get(hOV, 'CData');
        al = get(hOV, 'AlphaData');
        h2 = imagesc(ax2, ov);
        set(h2, 'AlphaData', al);

        try
            colormap(ax2, colormap(ax));
        catch
            colormap(ax2, colormap(fig));
        end
        caxis(ax2, state.cax);

        ROI = ROI_byZ{state.z};
        for k = 1:numel(ROI)
            r = ROI(k);
            rectangle(ax2, 'Position', [r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
                'EdgeColor', r.color, 'LineWidth', 2);
            text(ax2, r.x1, max(1, r.y1-2), sprintf('%d', r.id), ...
                'Color', r.color, ...
                'FontWeight', 'bold', ...
                'FontSize', 12, ...
                'Interpreter', 'none', ...
                'VerticalAlignment', 'bottom', ...
                'BackgroundColor', [0 0 0], ...
                'Margin', 1);
        end

        title(ax2, sprintf('%s | Slice %d/%d', fileLabel, state.z, nZ), ...
            'Color', 'w', ...
            'FontWeight', 'bold', ...
            'Interpreter', 'none');

        cb2 = colorbar(ax2);
        cb2.Color = 'w';
        cb2.Label.String = 'Signal change (%)';
        cb2.FontSize = 12;

        set(tf, 'PaperPositionMode', 'auto');

        print(tf, outPng, '-dpng',  '-r300', '-opengl');
        print(tf, outTif, '-dtiff', '-r300', '-opengl');
        print(tf, outJpg, '-djpeg', '-r300', '-opengl');

        if isgraphics(tf)
            close(tf);
        end
        tf = [];

        pptPath = '';
        if canUsePptApi()
            slidePng = fullfile(outDir, [baseName '_slide.png']);
            renderSingleScmSlidePNG(slidePng, outPng, fileLabel, state.z, nZ, state.cax, colormap(ax));

            pptPath = chooseShortSinglePptPath(outDir, fileLabel, stamp);
            writePptFromSlidePNGs(pptPath, {slidePng});

            try
                if exist(slidePng, 'file') == 2
                    delete(slidePng);
                end
            catch
            end
        end

        try
            if ~isempty(pptPath)
                set(info1, 'String', sprintf('Saved SCM: %s (png/tif/jpg/ppt)', shortenPath(outDir,85)));
            else
                set(info1, 'String', sprintf('Saved SCM: %s (png/tif/jpg)', shortenPath(outDir,85)));
            end
            set(info1, 'TooltipString', outDir);
        catch
        end

    catch ME
        try
            if ~isempty(tf) && isgraphics(tf), close(tf); end
        catch
        end
        try
            if ~isempty(slidePng) && exist(slidePng, 'file') == 2
                delete(slidePng);
            end
        catch
        end
        errordlg(ME.message, 'Export SCM Image failed');
    end
end

function releaseSingleScmExportLock()
    state.singleScmExportBusy = false;
    state.lastSingleScmExportStampSec = now * 86400;
end

function scmDir = getAutoScmDir()
    base = '';
    try
        if isstruct(par)
            if isfield(par, 'loadedPath') && ~isempty(par.loadedPath)
                base = char(par.loadedPath);
            end
            if isempty(base) && isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf, 'file')
                    base = fileparts(lf);
                end
            end
            if isempty(base) && isfield(par, 'rawPath') && ~isempty(par.rawPath)
                base = char(par.rawPath);
            end
            if isempty(base) && isfield(par, 'exportPath') && ~isempty(par.exportPath)
                base = char(par.exportPath);
            end
        end
    catch
        base = '';
    end
    if isempty(base), base = pwd; end

    analysedRoot = '';
    try
        if isstruct(par) && isfield(par, 'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath, 'dir')
            analysedRoot = char(par.exportPath);
        end
    catch
    end
    if isempty(analysedRoot)
        analysedRoot = guessAnalysedRoot(base);
    end

    scmDir = fullfile(analysedRoot, 'SCM');
end

%% ==========================================================
% SCM time series export
%% ==========================================================
function exportScmSeries1minCB(~,~)
    if state.seriesExportBusy
        return;
    end

    tNowSec = now * 86400;
    if (tNowSec - state.lastSeriesExportStampSec) < 0.75
        return;
    end

    state.seriesExportBusy = true;
    c = onCleanup(@releaseSeriesExportLock); %#ok<NASGU>

    EXPORT_DPI_TILES  = 200;
    EXPORT_DPI_SLIDES = 200;
    SAVE_TIF = true;
    SAVE_JPG = true;

    figT = [];
    tmpSLD = '';
    slidePNGs = {};

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

        doPPT  = str2double(strtrim(a{4}));
        if ~isfinite(doPPT), doPPT = 1; end
        doPPT  = (doPPT ~= 0);

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
            set(info1, 'String', { ...
                'Saving to:', ...
                shortenPath(outDir,120), ...
                'Tip: hover here to see full path'});
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
        if b1i < b0i, tmp = b0i; b0i = b1i; b1i = tmp; end

        PSCz = getPSCForSlice(state.z);
        baseMap = mean(PSCz(:,:,b0i:b1i), 3);

        bgRGB = get(hBG, 'CData');
        cm    = colormap(ax);
        caxV  = state.cax;

        sigma = str2double(getStr(ebSigma));
        if ~isfinite(sigma), sigma = 1; end

        thrStr  = strtrim(getStr(ebThr));
        caxStr  = strtrim(getStr(ebCax));
        baseStr = strtrim(getStr(ebBase));
        aStr    = sprintf('Alpha=%s%%', strtrim(getStr(txtAlpha)));
        modStr  = sprintf('AlphaMod=%d [%s..%s]', double(state.alphaModOn), strtrim(getStr(ebModMin)), strtrim(getStr(ebModMax)));
        sigStr  = sprintf('Sigma=%g', sigma);

        footerInfo = sprintf('Thr=%s | CAX=%s | Base=%s | %s | %s | %s', ...
            thrStr, caxStr, baseStr, aStr, modStr, sigStr);

        totalSec = (nT-1) * TR;
        starts = 0:winLen:(floor(totalSec/winLen)*winLen);
        if isfinite(maxMin)
            maxSec = maxMin * 60;
            starts = starts(starts < maxSec);
        end

        figT = figure('Visible', 'off', 'Color', [0 0 0], 'InvertHardcopy', 'off');
        set(figT, 'Units', 'pixels', 'Position', [50 50 1200 880]);

        axT = axes('Parent', figT, 'Units', 'normalized', 'Position', [0 0 1 1]);
        axis(axT, 'image');
        axis(axT, 'off');
        set(axT, 'YDir', 'reverse');
        hold(axT, 'on');
        image(axT, bgRGB);
        hT = imagesc(axT, zeros(nY, nX));
        set(hT, 'AlphaData', zeros(nY, nX));
        colormap(axT, cm);
        caxis(axT, caxV);
        hold(axT, 'off');
        set(figT, 'PaperPositionMode', 'auto');

        tilePNG = {};
        tileLBL = {};
        nSaved = 0;

        for wi = 1:numel(starts)
            s0 = starts(wi);
            s1 = s0 + winLen;

            idxSig = find(tsec >= s0 & tsec < s1);
            if isempty(idxSig), continue; end

            sigMap = mean(PSCz(:,:,idxSig), 3);
            map = sigMap - baseMap;

            if sigma > 0
                map = smooth2D_gauss(map, sigma);
            end
            map(~mask2D) = 0;

            alpha = alphaFromCurrentSettings(map);

            minIdx = floor(s0 / winLen) + 1;

            phase = '';
            if isfinite(injSec)
                if s1 <= injSec
                    phase = 'Baseline';
                elseif s0 < injSec && s1 > injSec
                    phase = 'Injection';
                else
                    pi = floor((s0 - injSec)/winLen) + 1;
                    if pi < 1, pi = 1; end
                    phase = sprintf('%d min PI', pi);
                end
            end

            if isempty(phase)
                lbl = sprintf('%.0f-%.0fs | %d min', s0, s1, minIdx);
            else
                lbl = sprintf('%.0f-%.0fs | %d min (%s)', s0, s1, minIdx, phase);
            end

           baseName = sprintf('SCM_z%02d_w%03d_%0.0f-%0.0fs', ...
    state.z, minIdx, s0, s1);

            outPng = fullfile(dirPNG, [baseName '.png']);
            outTif = fullfile(dirTIF, [baseName '.tif']);
            outJpg = fullfile(dirJPG, [baseName '.jpg']);

            set(hT, 'CData', map);
            set(hT, 'AlphaData', alpha);
            colormap(axT, cm);
            caxis(axT, caxV);

            print(figT, outPng, '-dpng',  sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
            if SAVE_TIF
                print(figT, outTif, '-dtiff', sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
            end
            if SAVE_JPG
                print(figT, outJpg, '-djpeg', sprintf('-r%d', EXPORT_DPI_TILES), '-opengl');
            end

            nSaved = nSaved + 1;
            tilePNG{end+1} = outPng; %#ok<AGROW>
            tileLBL{end+1} = lbl; %#ok<AGROW>

            try
                set(info1, 'String', sprintf('Exporting tiles... %d / %d  |  %s', ...
                    nSaved, numel(starts), shortenPath(outDir,55)));
                set(info1, 'TooltipString', outDir);
                drawnow limitrate;
            catch
            end
        end

        if ~isempty(figT) && isgraphics(figT)
            close(figT);
            figT = [];
        end

        if isempty(tilePNG)
            errordlg('No windows exported (maybe too short recording or window settings).', 'SCM series');
            return;
        end

        perSlide = 6;
        nSlides = ceil(numel(tilePNG) / perSlide);

        fullTitle  = sprintf('%s | z=%d/%d', makeFullTitle(fileLabel), state.z, nZ);
        shortTitle = sprintf('%s | z=%d/%d', getAnimalID(fileLabel),   state.z, nZ);

        for si = 1:nSlides
            i0 = (si-1)*perSlide + 1;
            i1 = min(si*perSlide, numel(tilePNG));
            idx = i0:i1;

            outSlide = fullfile(tmpSLD, sprintf('slide_%02d.png', si));
            if si == 1
                tStr = fullTitle;
            else
                tStr = shortTitle;
            end

            renderSlideMontagePNG(outSlide, tilePNG(idx), tileLBL(idx), cm, caxV, tStr, footerInfo, EXPORT_DPI_SLIDES);

            if exist(outSlide, 'file') ~= 2
                error('Failed to create slide PNG: %s', outSlide);
            end

            slidePNGs{end+1} = outSlide; %#ok<AGROW>

            try
                set(info1, 'String', sprintf('Building slide PNGs... %d / %d  |  %s', ...
                    si, nSlides, shortenPath(outDir,55)));
                set(info1, 'TooltipString', outDir);
                drawnow limitrate;
            catch
            end
        end

        pptPath = '';
        pptMsg  = '';

        if doPPT
            if canUsePptApi()
                pptPath = chooseShortPptPath(outDir, fileLabel, stamp);
                try
                    writePptFromSlidePNGs(pptPath, slidePNGs);
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
            if exist(tmpSLD, 'dir') == 7
                rmdir(tmpSLD, 's');
            end
        catch
        end

        try
            if isempty(pptPath)
                set(info1, 'String', ['DONE. Saved: ' shortenPath(outDir,80) '  (' pptMsg ')']);
            else
                set(info1, 'String', ['DONE. Saved: ' shortenPath(outDir,80) '  (PPT + PNGs)']);
            end
            set(info1, 'TooltipString', outDir);
        catch
        end

        fprintf('[SCM SERIES] DONE. Folder: %s\n', outDir);
        if ~isempty(pptPath)
            fprintf('[SCM SERIES] PPT: %s\n', pptPath);
        end

    catch ME
        try
            if ~isempty(figT) && isgraphics(figT)
                close(figT);
            end
        catch
        end
        try
            if ~isempty(tmpSLD) && exist(tmpSLD, 'dir') == 7
                rmdir(tmpSLD, 's');
            end
        catch
        end
        errordlg(ME.message, 'Export SCM series failed');
    end
end

function releaseSeriesExportLock()
    state.seriesExportBusy = false;
    state.lastSeriesExportStampSec = now * 86400;
end

function alpha = alphaFromCurrentSettings(ov)
    a = get(slAlpha, 'Value');
    thr = str2double(getStr(ebThr));
    if ~isfinite(thr), thr = 0; end

    mMin = str2double(getStr(ebModMin));
    if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax));
    if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin
        tmp = mMin; mMin = mMax; mMax = tmp;
    end

    baseMask = double(mask2D);
    thrMask  = double(abs(ov) >= thr);

    if ~state.alphaModOn
        alpha = (a/100) .* thrMask .* baseMask;
    else
        effLo = max(mMin, thr);
        effHi = mMax;

        if ~isfinite(effHi) || effHi <= effLo
            effHi = max(abs(ov(:)));
        end
        if ~isfinite(effHi) || effHi <= effLo
            effHi = effLo + eps;
        end

        mod = (abs(ov) - effLo) ./ max(eps, (effHi - effLo));
        mod(~isfinite(mod)) = 0;
        mod = min(max(mod, 0), 1);

        alpha = (a/100) .* mod .* thrMask .* baseMask;
    end
end

%% ==========================================================
% Time-course PNG export
%% ==========================================================
    function exportTimecoursePngCB(~,~)
    try
      P = getSimpleExportPaths();
outDir = P.scmTcDir;
safeMkdirIfNeeded(outDir);

labelTag = askExportLabel(state.lastTcExportLabel, 'Time course export label');
if isempty(labelTag)
    return;
end
state.lastTcExportLabel = labelTag;

stamp = datestr(now, 'yyyymmdd_HHMMSS');
baseName = sprintf('%s_%s_TimeCourse_%s', P.fileStem, labelTag, stamp);

        outPngGrid   = fullfile(outDir, [baseName '_grid.png']);
        outPngNoGrid = fullfile(outDir, [baseName '_nogrid.png']);

        tf = figure('Visible', 'off', ...
            'Color', [0.05 0.05 0.05], ...
            'InvertHardcopy', 'off', ...
            'Units', 'pixels', ...
            'Position', [150 120 1500 780]);

      ax2 = axes('Parent', tf, ...
    'Units', 'normalized', ...
    'Position', [0.11 0.14 0.84 0.76], ...
    'Color', [0.05 0.05 0.05], ...
    'XColor', 'w', ...
    'YColor', 'w', ...
    'LineWidth', 1.2, ...
    'Box', 'on', ...
    'Layer', 'top');
        hold(ax2, 'on');
        grid(ax2, 'on');

        xlabel(ax2, 'Time (min)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
        hY = ylabel(ax2, 'PSC (%)', 'Color', 'w', 'FontSize', 13, 'FontWeight', 'bold');
        title(ax2, sprintf('%s | %s ROI Time Course', fileLabel, labelTag), ...
            'Color', 'w', 'FontWeight', 'bold', 'Interpreter', 'none');

   try
    set(hY, 'Units', 'normalized');
    set(hY, 'Position', [-0.028 0.50 0]);
    set(hY, 'Clipping', 'off');
catch
end

        ROI = ROI_byZ{state.z};
        for k = 1:numel(ROI)
            r = ROI(k);
            tc = computeRoiPSC_atSlice(state.z, r.x1, r.x2, r.y1, r.y2);
            if numel(tc) == nT
                plot(ax2, tmin, tc, ':', 'Color', r.color, 'LineWidth', 2.6);
            end
        end

        if strcmp(get(hLivePSC, 'Visible'), 'on')
            try
                plot(ax2, get(hLivePSC, 'XData'), get(hLivePSC, 'YData'), ':', ...
                    'Color', get(hLivePSC, 'Color'), 'LineWidth', 3.0);
            catch
            end
        end

        yl = get(axTC, 'YLim');
        if any(~isfinite(yl)) || yl(2) <= yl(1)
            yl = [-5 5];
        end
        set(ax2, 'YLim', yl);

        [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
        [s0,s1] = parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

        if isVolMode
            b0s = (clamp(round(b0), 1, nT)-1)*TR;
            b1s = (clamp(round(b1), 1, nT)-1)*TR;
            s0s = (clamp(round(s0), 1, nT)-1)*TR;
            s1s = (clamp(round(s1), 1, nT)-1)*TR;
        else
            b0s = b0; b1s = b1;
            s0s = s0; s1s = s1;
        end
        if b1s < b0s, tmp = b0s; b0s = b1s; b1s = tmp; end
        if s1s < s0s, tmp = s0s; s0s = s1s; s1s = tmp; end

        yr = yl(2) - yl(1);
        if ~isfinite(yr) || yr <= 0
            yr = 1;
        end
        yTxt = yl(2) - 0.06 * yr;

        patch(ax2, [b0s b1s b1s b0s]/60, [yl(1) yl(1) yl(2) yl(2)], [1.0 0.2 0.2], ...
            'FaceAlpha', 0.16, 'EdgeColor', 'none');

        patch(ax2, [s0s s1s s1s s0s]/60, [yl(1) yl(1) yl(2) yl(2)], [1.0 0.60 0.15], ...
            'FaceAlpha', 0.16, 'EdgeColor', 'none');

        text(ax2, mean([b0s b1s])/60, yTxt, 'Bas.', ...
            'Color', [1.00 0.35 0.35], ...
            'FontSize', 11, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'BackgroundColor', [0 0 0], ...
            'Margin', 1, ...
            'Clipping', 'on');

        text(ax2, mean([s0s s1s])/60, yTxt, 'Sig.', ...
            'Color', [1.00 0.80 0.35], ...
            'FontSize', 11, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'BackgroundColor', [0 0 0], ...
            'Margin', 1, ...
            'Clipping', 'on');

        uistack(findobj(ax2, 'Type', 'line'), 'top');

        print(tf, outPngGrid, '-dpng', '-r300', '-opengl');

        grid(ax2, 'off');
        print(tf, outPngNoGrid, '-dpng', '-r300', '-opengl');

        if isgraphics(tf), close(tf); end

        try
            set(info1, 'String', ['Saved time course PNGs to: ' shortenPath(outDir,90)]);
            set(info1, 'TooltipString', outDir);
        catch
        end

    catch ME
        try
            if exist('tf', 'var') && ~isempty(tf) && isgraphics(tf)
                close(tf);
            end
        catch
        end
        errordlg(ME.message, 'Export time course PNG failed');
    end
    end


%% ==========================================================
% Group Analysis Export Button
%% ==========================================================

function exportForGroupAnalysisCB(~,~)
    if ~state.isAtlasWarped
        warndlg(['Export for Group Analysis requires atlas-warped functional data.' newline ...
                 'Please use "WARP FUNCTIONAL TO ATLAS" first.'], ...
                 'Group Analysis export');
        return;
    end

    try
        Pexp = getGroupBundleExportPathsLocal();
        safeMkdirIfNeeded(Pexp.bundleRoot);
        safeMkdirIfNeeded(Pexp.bundleDir);

        [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
        [s0,s1] = parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

        sigma = str2double(getStr(ebSigma));
        if ~isfinite(sigma), sigma = 1; end

        thr = str2double(getStr(ebThr));
        if ~isfinite(thr), thr = 0; end

        alphaPct = get(slAlpha, 'Value');

        cmapName = getCurrentPopupStringLocal(popMap);

        stamp = datestr(now, 'yyyymmdd_HHMMSS');
        outFile = fullfile(Pexp.bundleDir, ...
            sprintf('SCM_GroupExport_%s_%s_%s_%s.mat', ...
            Pexp.animalID, Pexp.session, Pexp.scanID, stamp));

        G = struct();
        G.kind = 'SCM_GROUP_EXPORT';
        G.version = '1.0';
        G.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');

        G.fileLabel = fileLabel;
        G.loadedFile = safeParFieldLocal('loadedFile');
        G.loadedPath = safeParFieldLocal('loadedPath');
        G.exportPath = safeParFieldLocal('exportPath');

        G.animalID = Pexp.animalID;
        G.session  = Pexp.session;
        G.scanID   = Pexp.scanID;
        G.subjectKey = Pexp.subjectKey;

        G.isAtlasWarped = logical(state.isAtlasWarped);
        G.atlasTransformFile = state.atlasTransformFile;
        G.atlasSliceIndex = state.z;

        G.baseWindowStr = getStr(ebBase);
        G.sigWindowStr  = getStr(ebSig);
        G.baseWindowSec = [b0 b1];
        G.sigWindowSec  = [s0 s1];
        G.sigma = sigma;

        G.display = struct();
        G.display.threshold = thr;
        G.display.caxis = state.cax;
        G.display.alphaPercent = alphaPct;
        G.display.alphaModOn = logical(state.alphaModOn);
        G.display.modMin = state.modMin;
        G.display.modMax = state.modMax;
        G.display.colormapName = cmapName;

        G.TR = TR;
        G.tsec = tsec;
        G.tmin = tmin;

        G.nY = nY;
        G.nX = nX;
        G.nZ = nZ;
        G.nT = nT;

        % Current atlas-space numeric content
        G.pscAtlas4D = PSC;                 % atlas-warped PSC series currently loaded in SCM_gui
        G.scmMapAtlas = get(hOV, 'CData');  % currently displayed SCM map
        G.alphaAtlas  = get(hOV, 'AlphaData');

        % Current underlay as shown in atlas space
        G.underlayAtlas = bg;
        G.underlayInfo = struct();
        G.underlayInfo.isColorUnderlay = logical(state.isColorUnderlay);
        G.underlayInfo.regionLabelUnderlay = [];
        G.underlayInfo.regionInfo = struct();
        if isfield(state,'regionLabelUnderlay')
            G.underlayInfo.regionLabelUnderlay = state.regionLabelUnderlay;
        end
        if isfield(state,'regionInfo')
            G.underlayInfo.regionInfo = state.regionInfo;
        end

        % Current mask
        G.mask2DCurrentSlice = mask2D;
        G.maskAtlas = [];
        if ~isempty(passedMask)
            G.maskAtlas = passedMask;
        end
        G.maskIsInclude = passedMaskIsInclude;

        % Optional placeholder for later side normalization
        G.injectionSide = '?';

        save(outFile, 'G', '-v7.3');

        try
            set(info1, 'String', ['Group bundle saved: ' shortenPath(outFile,85)]);
            set(info1, 'TooltipString', outFile);
        catch
        end

        msgbox(sprintf('Saved GroupAnalysis bundle:\n%s', outFile), ...
               'SCM group export');

    catch ME
        errordlg(ME.message, 'Export for Group Analysis failed');
    end
end


    function Pexp = getGroupBundleExportPathsLocal()
    base = '';

    try
        if isstruct(par)
            if isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(char(par.exportPath),'dir') == 7
                base = char(par.exportPath);
            elseif isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(char(par.loadedPath),'dir') == 7
                base = char(par.loadedPath);
            elseif isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf,'file') == 2
                    base = fileparts(lf);
                end
            end
        end
    catch
        base = '';
    end

    if isempty(base)
        base = pwd;
    end

    analysedRoot = guessAnalysedRoot(base);
    meta = deriveGroupBundleMetaLocal();

    bundleRoot = fullfile(analysedRoot, 'GroupAnalysis', 'Bundles', 'SCM');
    subjectKey = sanitizeName(sprintf('%s_%s_%s', meta.animalID, meta.session, meta.scanID));

    Pexp = struct();
    Pexp.root = analysedRoot;
    Pexp.bundleRoot = bundleRoot;
    Pexp.bundleDir = fullfile(bundleRoot, subjectKey);
    Pexp.subjectKey = subjectKey;
    Pexp.animalID = meta.animalID;
    Pexp.session  = meta.session;
    Pexp.scanID   = meta.scanID;
end

    function meta = deriveGroupBundleMetaLocal()
    meta = struct();
    meta.animalID = '';
    meta.session  = '';
    meta.scanID   = '';

    txts = {fileLabel, safeParFieldLocal('loadedFile'), safeParFieldLocal('loadedPath')};

    % ------------------------------------------------------
    % PASS 1: strongest pattern
    % Accepts:
    %   WT250407_S1_FUS_160020
    %   Mouse250407_S1_PACAP_FUS_160020
    %   WT250407_S1_PACAP_FUS_160020
    % ------------------------------------------------------
    for ii = 1:numel(txts)
        s = txts{ii};
        if isempty(s), continue; end

        tok = regexpi(s, '([A-Za-z]{1,16}\d{6}[A-Za-z]?)_(S\d+).*?(FUS_\d+)', 'tokens', 'once');
        if ~isempty(tok)
            meta.animalID = sanitizeName(tok{1});
            meta.session  = sanitizeName(tok{2});
            meta.scanID   = sanitizeName(tok{3});
            return;
        end
    end

    % ------------------------------------------------------
    % PASS 2: recover separately
    % no \b because underscores break word boundaries
    % ------------------------------------------------------
    for ii = 1:numel(txts)
        s = txts{ii};
        if isempty(s), continue; end

        if isempty(meta.animalID)
            tokA = regexpi(s, '([A-Za-z]{1,16}\d{6}[A-Za-z]?)', 'tokens', 'once');
            if ~isempty(tokA)
                meta.animalID = sanitizeName(tokA{1});
            end
        end

        if isempty(meta.session)
            tokS = regexpi(s, '(S\d+)', 'tokens', 'once');
            if ~isempty(tokS)
                meta.session = sanitizeName(tokS{1});
            end
        end

        if isempty(meta.scanID)
            tokF = regexpi(s, '(FUS_\d+)', 'tokens', 'once');
            if ~isempty(tokF)
                meta.scanID = sanitizeName(tokF{1});
            end
        end
    end

    % ------------------------------------------------------
    % PASS 3: if animal still empty, try parent folder style
    % Example:
    %   ...\WT250407_S1\Mouse250407_S1_PACAP_FUS_160020\
    % prefer WT250407 from folder name if available
    % ------------------------------------------------------
    for ii = 1:numel(txts)
        s = txts{ii};
        if isempty(s), continue; end

        if isempty(meta.animalID)
            tokWT = regexpi(s, '(WT\d{6}[A-Za-z]?)', 'tokens', 'once');
            if ~isempty(tokWT)
                meta.animalID = sanitizeName(tokWT{1});
                break;
            end
        end
    end

    % defaults
    if isempty(meta.animalID), meta.animalID = 'Animal'; end
    if isempty(meta.session),  meta.session  = 'S1'; end
    if isempty(meta.scanID),   meta.scanID   = 'FUS_UNKNOWN'; end
end

function s = safeParFieldLocal(fn)
    s = '';
    try
        if isstruct(par) && isfield(par,fn) && ~isempty(par.(fn))
            s = char(par.(fn));
        end
    catch
        s = '';
    end
end

function s = getCurrentPopupStringLocal(hPop)
    s = '';
    try
        items = get(hPop,'String');
        v = get(hPop,'Value');
        v = max(1, min(numel(items), v));
        if iscell(items)
            s = char(items{v});
        else
            s = char(items(v,:));
        end
    catch
        s = '';
    end
end



function renderSingleScmSlidePNG(outFile, imagePng, titleLabel, zSel, nZSel, caxV, cm)
    figS = figure('Visible', 'off', 'Color', [0 0 0], 'InvertHardcopy', 'off');
    set(figS, 'Units', 'inches', 'Position', [0.5 0.5 13.333 7.5]);
    set(figS, 'PaperPositionMode', 'auto');

    ttl = sprintf('%s | z=%d/%d', makeFullTitle(titleLabel), zSel, nZSel);

    annotation(figS, 'textbox', [0.02 0.90 0.96 0.08], ...
        'String', ttl, ...
        'Color', 'w', ...
        'EdgeColor', 'none', ...
        'FontName', 'Arial', ...
        'FontSize', 16, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');

    axI = axes('Parent', figS, 'Position', [0.08 0.10 0.82 0.78]);
    imshow(imread(imagePng), 'Parent', axI);
    axis(axI, 'off');

    axCB = axes('Parent', figS, 'Position', [0.92 0.16 0.02 0.66], 'Visible', 'off');
    imagesc(axCB, [0 1;0 1]);
    colormap(axCB, cm);
    caxis(axCB, caxV);
    cbx = colorbar(axCB, 'Position', [0.92 0.16 0.02 0.66]);
    cbx.Color = 'w';
    cbx.FontName = 'Arial';
    cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)';
    cbx.Label.Color = 'w';

    print(figS, outFile, '-dpng', '-r220', '-opengl');
    close(figS);
end

function renderSlideMontagePNG(outFile, pngList, lblList, cm, caxV, titleStr, footerStr, dpiVal)
    figS = figure('Visible', 'off', 'Color', [0 0 0], 'InvertHardcopy', 'off');
    set(figS, 'Units', 'inches', 'Position', [0.5 0.5 13.333 7.5]);
    set(figS, 'PaperPositionMode', 'auto');

    annotation(figS, 'textbox', [0.02 0.885 0.96 0.11], ...
        'String', titleStr, ...
        'Color', 'w', ...
        'EdgeColor', 'none', ...
        'FontName', 'Arial', ...
        'FontSize', 14, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');

    annotation(figS, 'textbox', [0.42 0.01 0.56 0.06], ...
        'String', footerStr, ...
        'Color', 'w', ...
        'EdgeColor', 'none', ...
        'FontName', 'Arial', ...
        'FontSize', 11, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right', ...
        'Interpreter', 'none');

    axCB = axes('Parent', figS, 'Position', [0.03 0.14 0.02 0.74], 'Visible', 'off');
    imagesc(axCB, [0 1;0 1]);
    colormap(axCB, cm);
    caxis(axCB, caxV);
    cbx = colorbar(axCB, 'Position', [0.03 0.14 0.02 0.74]);
    cbx.Color = 'w';
    cbx.FontName = 'Arial';
    cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)';
    cbx.Label.Color = 'w';

    x0 = 0.08;
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
            'String', lblList{k}, ...
            'Color', 'w', ...
            'EdgeColor', 'none', ...
            'FontName', 'Arial', ...
            'FontSize', 13, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'Interpreter', 'none');
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
            'String', lblList{k}, ...
            'Color', 'w', ...
            'EdgeColor', 'none', ...
            'FontName', 'Arial', ...
            'FontSize', 13, ...
            'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', ...
            'Interpreter', 'none');
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
            pic.Width  = '13.333in';
            pic.Height = '7.5in';
            add(slide, pic);
        end

        close(ppt);

    catch ME
        try
            if ~isempty(ppt)
                close(ppt);
            end
        catch
        end
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


function safeMkdirIfNeeded(pth)
    if isempty(pth), return; end
    if exist(pth, 'dir') ~= 7
        ok = mkdir(pth);
        if ~ok
            error('Could not create folder: %s', pth);
        end
    end
end

function titleStr = makeFullTitle(lbl)
    s = char(lbl);
    s = regexprep(s, '\|?\s*File:.*$', '');
    s = shortenMiddle(s, 110);
    titleStr = s;
end

function s = getAnimalID(lbl)
    s0 = char(lbl);
    tok = regexp(s0, '(WT\d+[A-Za-z]?(?:_\w+)?_S\d+)', 'tokens', 'once');
    if ~isempty(tok)
        s = tok{1};
        return;
    end
    tok = regexp(s0, '(WT\d+[A-Za-z]?)', 'tokens', 'once');
    if ~isempty(tok)
        s = tok{1};
        return;
    end
    s = 'Animal';
end

function out = shortenMiddle(s, maxLen)
    s = char(s);
    if numel(s) <= maxLen
        out = s;
        return;
    end
    keep = floor((maxLen-3)/2);
    out = [s(1:keep) '...' s(end-keep+1:end)];
end

function s = shortenPath(p, maxLen)
    p = char(p);
    if numel(p) <= maxLen
        s = p;
        return;
    end
    keep = floor((maxLen-3)/2);
    s = [p(1:keep) '...' p(end-keep+1:end)];
end

%% ==========================================================
% Helpers
%% ==========================================================
function analysedRoot = guessAnalysedRoot(p0)
    p0 = char(p0);
    if exist(p0, 'dir') ~= 7
        try
            p0 = fileparts(p0);
        catch
        end
    end

    if contains(p0, 'AnalysedData')
        analysedRoot = p0;
        return;
    end

    if contains(p0, 'RawData')
        analysedRoot = strrep(p0, 'RawData', 'AnalysedData');
        if exist(analysedRoot, 'dir') ~= 7
            try
                mkdir(analysedRoot);
            catch
            end
        end
        return;
    end

    parent = fileparts(p0);
    sib = fullfile(parent, 'AnalysedData');
    if exist(sib, 'dir') == 7
        analysedRoot = sib;
        return;
    end

    analysedRoot = p0;
end

function dsType = deriveDatasetType()
    s = '';
    try
        if isstruct(par)
            if isfield(par, 'activeDataset') && ~isempty(par.activeDataset), s = char(par.activeDataset); end
            if isempty(s) && isfield(par, 'loadedName') && ~isempty(par.loadedName), s = char(par.loadedName); end
            if isempty(s) && isfield(par, 'loadedFile') && ~isempty(par.loadedFile), s = char(par.loadedFile); end
            if isempty(s) && isfield(par, 'file') && ~isempty(par.file), s = char(par.file); end
        end
    catch
        s = '';
    end
    if isempty(s), s = fileLabel; end

    try
        ss = char(s);
        ss = regexprep(ss, '\.nii\.gz$', '', 'ignorecase');
        if contains(ss, filesep) || contains(ss, '/') || contains(ss, '\')
            [~, ss] = fileparts(ss);
        end
        s = ss;
    catch
    end

    if isstring(s), s = char(s); end
    s = lower(strtrim(s));
    s = regexprep(s, '\|.*$', '');
    s = regexprep(s, '\(.*$', '');
    s = strtrim(s);

    if contains(s, 'gabriel')
        dsType = 'gabriel';
        return;
    end
    if ~isempty(regexp(s, '(^|[_\-\s])raw([_\-\s]|$)', 'once'))
        dsType = 'raw';
        return;
    end

    tok = regexp(s, '^[a-z0-9]+', 'match', 'once');
    if ~isempty(tok)
        dsType = sanitizeName(tok);
    else
        dsType = 'scm';
    end
    if isempty(dsType), dsType = 'scm'; end
end

function tag = stripLeadingType(tagIn, dsType)
    tag = tagIn;
    if isempty(tag) || isempty(dsType), return; end

    a = lower(tag);
    t = lower(dsType);

    pat1 = [t '_'];
    pat2 = [t '-'];
    pat3 = [t ' '];

    if startsWith(a, pat1), tag = tag(numel(pat1)+1:end); end
    if startsWith(lower(tag), pat2), tag = tag(numel(pat2)+1:end); end
    if startsWith(lower(tag), pat3), tag = tag(numel(pat3)+1:end); end

    tag = strtrim(tag);
    if isempty(tag), tag = tagIn; end
end

function tag = deriveDatasetTag()
    s = '';
    try
        if isstruct(par)
            if isfield(par, 'loadedFile') && ~isempty(par.loadedFile), s = char(par.loadedFile); end
            if isempty(s) && isfield(par, 'loadedName') && ~isempty(par.loadedName), s = char(par.loadedName); end
            if isempty(s) && isfield(par, 'file') && ~isempty(par.file), s = char(par.file); end
            if isempty(s) && isfield(par, 'activeDataset') && ~isempty(par.activeDataset), s = char(par.activeDataset); end
        end
    catch
        s = '';
    end
    if isempty(s), s = fileLabel; end

    s = regexprep(s, '\|.*$', '');
    s = regexprep(s, '\(.*$', '');
    s = strtrim(s);

    s = regexprep(s, '\.nii(\.gz)?$', '', 'ignorecase');
    s = regexprep(s, '\.mat$', '', 'ignorecase');

    sp = strfind(s, ' ');
    if ~isempty(sp), s = s(1:sp(1)-1); end

    s = sanitizeName(s);
    if isempty(s), s = 'dataset'; end
    tag = s;
end

function s = sanitizeName(s)
    if isstring(s), s = char(s); end
    s = char(s);
    s = strrep(s, filesep, '_');
    s = regexprep(s, '[^\w\-]+', '_');
    s = regexprep(s, '_+', '_');
    s = strtrim(s);
    if numel(s) > 80
        s = s(1:80);
    end
end

%% ==========================================================
% Mask
%% ==========================================================
function loadMaskCB(~,~)
    startPath = getStartPath();

    [f,p] = uigetfile( ...
        {'*.mat;*.nii;*.nii.gz', 'Mask / bundle files (*.mat,*.nii,*.nii.gz)'}, ...
        'Select overlay mask / bundle', startPath);

    if isequal(f,0)
        return;
    end

    fullf = fullfile(p,f);

    try
        [~,~,ext] = fileparts(fullf);
        ext = lower(ext);

        if strcmp(ext, '.mat')
            B = readScmBundleFile(fullf);

            if ~isempty(B.overlayMask)
                passedMask = fitBundleMaskToCurrentScm(B.overlayMask);
                passedMaskIsInclude = B.overlayMaskIsInclude;
            elseif ~isempty(B.brainMask)
                passedMask = fitBundleMaskToCurrentScm(B.brainMask);
                passedMaskIsInclude = B.brainMaskIsInclude;
            else
                error('No usable overlay or brain mask found in MAT bundle.');
            end

            if ~isempty(B.brainImage)
                U = squeeze(B.brainImage);

                if ndims(U) == 2
                    if size(U,1) == nY && size(U,2) == nX
                        bg = double(U);
                        state.isColorUnderlay = false;
                    end

                elseif ndims(U) == 3
                    if size(U,1) == nY && size(U,2) == nX
                        if size(U,3) == 3
                            bg = double(U);
                            state.isColorUnderlay = true;
                        else
                            bg = double(U);
                            state.isColorUnderlay = false;
                        end
                    end
                end
            end

        else
            [passedMask, passedMaskIsInclude] = readMask(fullf, 'overlayPreferred');
            passedMask = fitBundleMaskToCurrentScm(passedMask);
        end

        if isempty(passedMask)
            mask2D = true(nY, nX);
        else
            mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
            if ~passedMaskIsInclude
                mask2D = ~mask2D;
            end
        end

        bg2 = getBg2DForSlice(state.z);
        set(hBG, 'CData', renderUnderlayRGB(bg2));

        try
            if exist('B','var') && isstruct(B)
                set(info1, 'String', sprintf('Loaded mask bundle: %s | field: %s', shortenPath(fullf,65), B.loadedField));
            else
                set(info1, 'String', sprintf('Loaded mask: %s', shortenPath(fullf,65)));
            end
            set(info1, 'TooltipString', fullf);
        catch
        end

        computeSCM();

    catch ME
        errordlg(ME.message, 'Mask / bundle load failed');
    end
end

function clearMaskCB(~,~)
    % Kept for compatibility, even though Clear Mask is no longer shown in the UI
    passedMask = [];
    passedMaskIsInclude = true;
    mask2D = true(nY, nX);

    try
        set(info1, 'String', 'Overlay mask cleared.');
        set(info1, 'TooltipString', '');
    catch
    end

    computeSCM();
end

function startPath = getStartPath()
    startPath = '';

    candDirs = {};

    try
        if isstruct(par)
            if isfield(par, 'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath, 'dir') == 7
                candDirs{end+1} = char(par.exportPath); %#ok<AGROW>
            end
            if isfield(par, 'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath, 'dir') == 7
                candDirs{end+1} = char(par.loadedPath); %#ok<AGROW>
            end
            if isfield(par, 'rawPath') && ~isempty(par.rawPath) && exist(par.rawPath, 'dir') == 7
                candDirs{end+1} = char(par.rawPath); %#ok<AGROW>
            end
            if isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf, 'file') == 2
                    candDirs{end+1} = fileparts(lf); %#ok<AGROW>
                end
            end
        end
    catch
    end

    candDirs{end+1} = pwd; %#ok<AGROW>

    for ii = 1:numel(candDirs)
        d = candDirs{ii};
        try
            if ~isempty(d) && exist(d, 'dir') == 7
                startPath = d;
                return;
            end
        catch
        end
    end

    startPath = pwd;
end

%% ==========================================================
% Video GUI
%% ==========================================================
function openVideo(~,~)
    try
        play_fusi_video_final( ...
            PSC, PSC, PSC, bg, ...
            par, 10, 240, ...
            TR, (nT-1)*TR, baseline, ...
            passedMask, passedMaskIsInclude, ...
            nT, false, struct(), ...
            fileLabel, state.z);
    catch ME
        errordlg(ME.message, 'Video GUI failed');
    end
end

function showHelp(~,~)
    bgFig   = [0.06 0.06 0.07];
    bgText  = [0.12 0.12 0.14];
    colTxt  = [0.94 0.94 0.96];

    hf = figure('Name', 'SCM Help', 'Color', bgFig, ...
        'MenuBar', 'none', 'ToolBar', 'none', 'NumberTitle', 'off', ...
        'Resize', 'on', 'Position', [200 100 980 780], 'WindowStyle', 'modal');

    guide = {
'SCM Viewer - Guide'
''
'OVERLAY'
'  - Threshold hides low |SCM|.'
'  - Display range sets overlay caxis.'
'  - Alpha modulation:'
'      OFF = hard threshold alpha'
'      ON  = alpha ramps between Mod Min and Mod Max'
'  - Export Time Course PNG saves the current ROI time-course view.'
''
'UNDERLAY'
'  - Brightness / Contrast / Gamma control background only.'
'  - Vessel enhance uses conectSize + conectLev.'
'  - Warp Functional To Atlas and Reset To Native are in the Underlay tab.'
''
'ROI'
'  - Hover shows live ROI PSC.'
'  - Left click adds ROI.'
'  - Right click removes nearest ROI.'
'  - You can also add ROI by typing center x y.'
'  - Export ROIs saves ROI<set>_d<idx>.txt into AnalysedData/ROI/<type>/<datasetTag>/'
''
'WORKFLOW'
'  - Compute SCM updates the SCM map.'
'  - Load Mask is available as a highlighted bottom button.'
'  - Open Video GUI opens the linked video viewer.'
''
'EXPORT'
'  - Export SCM Image saves png/tif/jpg and ppt when available.'
'  - Export SCM Time Series saves tile images, slide PNGs, and ppt when available.'
};

    uicontrol(hf, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.03 0.03 0.94 0.94], ...
        'String', strjoin(guide, newline), ...
        'Max', 2, 'Min', 0, ...
        'BackgroundColor', bgText, 'ForegroundColor', colTxt, ...
        'FontName', 'Arial', 'FontSize', 13, 'HorizontalAlignment', 'left');
end

function warpFunctionalToAtlasCB(~,~)
    startDir = '';
    candDirs = {};

    try
        if isstruct(par)
            if isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir') == 7
                candDirs{end+1} = fullfile(char(par.exportPath), 'Registration2D'); %#ok<AGROW>
                candDirs{end+1} = fullfile(char(par.exportPath), 'Registration');   %#ok<AGROW>
                candDirs{end+1} = char(par.exportPath);                             %#ok<AGROW>
            end
        end
    catch
    end

    try
        if isstruct(par)
            if isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath,'dir') == 7
                lp = char(par.loadedPath);

                if contains(lp, [filesep 'RawData' filesep])
                    ap = strrep(lp, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
                    candDirs{end+1} = fullfile(ap, 'Registration2D'); %#ok<AGROW>
                    candDirs{end+1} = fullfile(ap, 'Registration');   %#ok<AGROW>
                    candDirs{end+1} = ap;                             %#ok<AGROW>
                end

                candDirs{end+1} = fullfile(lp, 'Registration2D'); %#ok<AGROW>
                candDirs{end+1} = fullfile(lp, 'Registration');   %#ok<AGROW>
                candDirs{end+1} = lp;                             %#ok<AGROW>
            end
        end
    catch
    end

    try
        if isstruct(par)
            if isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf, 'file') == 2
                    ldir = fileparts(lf);

                    if contains(ldir, [filesep 'RawData' filesep])
                        ap = strrep(ldir, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
                        candDirs{end+1} = fullfile(ap, 'Registration2D'); %#ok<AGROW>
                        candDirs{end+1} = fullfile(ap, 'Registration');   %#ok<AGROW>
                        candDirs{end+1} = ap;                             %#ok<AGROW>
                    end

                    candDirs{end+1} = fullfile(ldir, 'Registration2D'); %#ok<AGROW>
                    candDirs{end+1} = fullfile(ldir, 'Registration');   %#ok<AGROW>
                    candDirs{end+1} = ldir;                             %#ok<AGROW>
                end
            end
        end
    catch
    end

    try
        candDirs{end+1} = getStartPath(); %#ok<AGROW>
    catch
        candDirs{end+1} = pwd; %#ok<AGROW>
    end

    candDirs = candDirs(~cellfun('isempty', candDirs));

    if ~isempty(candDirs)
        keep = true(size(candDirs));
        for ii = 2:numel(candDirs)
            for jj = 1:ii-1
                if strcmpi(candDirs{ii}, candDirs{jj})
                    keep(ii) = false;
                    break;
                end
            end
        end
        candDirs = candDirs(keep);
    end

    for ii = 1:numel(candDirs)
        d0 = candDirs{ii};
        if exist(d0, 'dir') == 7
            f0 = fullfile(d0, 'CoronalRegistration2D.mat');
            if exist(f0, 'file') == 2
                startDir = d0;
                break;
            end
        end
    end

    if isempty(startDir)
        for ii = 1:numel(candDirs)
            d0 = candDirs{ii};
            if exist(d0, 'dir') == 7
                [~,nm] = fileparts(d0);
                if strcmpi(nm, 'Registration2D') || strcmpi(nm, 'Registration')
                    startDir = d0;
                    break;
                end
            end
        end
    end

    if isempty(startDir)
        for ii = 1:numel(candDirs)
            d0 = candDirs{ii};
            if exist(d0, 'dir') == 7
                startDir = d0;
                break;
            end
        end
    end

    if isempty(startDir) || exist(startDir,'dir') ~= 7
        startDir = pwd;
    end

    [f,p] = uigetfile( ...
        {'*.mat','Transform files (*.mat)'}, ...
        'Select atlas Transformation / CoronalRegistration2D', ...
        startDir);

    if isequal(f,0)
        return;
    end

    try
        S = load(fullfile(p,f));
        T = extractAtlasWarpStruct(S);

        PSC = warpFunctionalSeriesToAtlas(origPSC, T);

        passedMask = [];
        passedMaskIsInclude = true;

        state.isAtlasWarped = true;
        state.atlasTransformFile = fullfile(p,f);
        state.lastAtlasTransformFile = state.atlasTransformFile;

        try
            if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d') ...
                    && isfield(T,'atlasSliceIndex') && isfinite(T.atlasSliceIndex)
                set(txtTitle, 'String', sprintf('%s | warped to atlas coronal slice %d', ...
                    fileLabel, round(T.atlasSliceIndex)));
            else
                set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
            end
        catch
            set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
        end

        resetRoisAndRefreshAfterDataChange();

        try
            msg = 'Functional data warped to atlas.';
            if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d')
                msg = 'Functional data warped with 2D coronal registration.';
            end
            set(info1, 'String', msg);
            set(info1, 'TooltipString', state.atlasTransformFile);
        catch
        end

    catch ME
        errordlg(ME.message, 'Atlas warp failed');
    end
end

function resetWarpToNativeCB(~,~)
    try
        PSC = origPSC;
        bg  = origBG;
        passedMask = origPassedMask;

        state.isAtlasWarped = false;
        state.atlasTransformFile = '';

        set(txtTitle, 'String', fileLabel);

        resetRoisAndRefreshAfterDataChange();

        try
            set(info1, 'String', 'Returned to native functional space.');
            set(info1, 'TooltipString', '');
        catch
        end
    catch ME
        errordlg(ME.message, 'Reset to native failed');
    end
end

function resetRoisAndRefreshAfterDataChange()
    dNow = ndims(PSC);
    if dNow == 3
        [nY, nX, nT] = size(PSC);
        nZ = 1;
    elseif dNow == 4
        [nY, nX, nZ, nT] = size(PSC);
    else
        error('PSC must remain [Y X T] or [Y X Z T] after warping.');
    end

    tsec = (0:nT-1) * TR;
    tmin = tsec / 60;

    state.hoverStride = max(1, ceil(nT / state.hoverMaxPts));
    state.hoverIdx    = 1:state.hoverStride:nT;
    state.tminHover   = tmin(state.hoverIdx);

    state.z = max(1, min(state.z, nZ));

    ROI_byZ = cell(1, nZ);
    for zz = 1:nZ
        ROI_byZ{zz} = struct('id', {}, 'x1', {}, 'x2', {}, 'y1', {}, 'y2', {}, 'color', {});
    end
    roi.nextId = 1;
    roi.isFrozen = false;

    deleteIfValid(roiHandles);
    roiHandles = gobjects(0);

    deleteIfValid(roiPlotPSC);
    roiPlotPSC = gobjects(0);

    deleteIfValid(roiTextHandles);
    roiTextHandles = gobjects(0);

    if isempty(passedMask)
        mask2D = true(nY, nX);
    else
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
        if ~passedMaskIsInclude
            mask2D = ~mask2D;
        end
    end

    if isgraphics(slZ)
        if nZ > 1
            set(slZ, ...
                'Min', 1, ...
                'Max', nZ, ...
                'Value', state.z, ...
                'SliderStep', [1/max(1,nZ-1) 5/max(1,nZ-1)], ...
                'Visible', 'on', ...
                'Enable', 'on');
            set(txtZ, 'String', sprintf('Slice: %d / %d', state.z, nZ), 'Visible', 'on');
        else
            set(slZ, ...
                'Min', 1, ...
                'Max', 1, ...
                'Value', 1, ...
                'SliderStep', [1 1], ...
                'Visible', 'off', ...
                'Enable', 'off');
            set(txtZ, 'String', '', 'Visible', 'off');
        end
    end

    set(hLiveRect, 'Visible', 'off');
    set(hLivePSC , 'XData', state.tminHover, 'YData', nan(1, numel(state.tminHover)), 'Visible', 'off');
    set(hRoiCoordTxt, 'Visible', 'off', 'String', '');

    bg2 = getBg2DForSlice(state.z);
    set(hBG, 'CData', renderUnderlayRGB(bg2));
    set(hOV, 'CData', zeros(nY, nX), 'AlphaData', zeros(nY, nX));

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
    drawnow;
end

function T = extractAtlasWarpStruct(S)
    if isfield(S, 'Transf') && isstruct(S.Transf)
        T = S.Transf;
    elseif isfield(S, 'Reg2D') && isstruct(S.Reg2D)
        T = S.Reg2D;
    else
        T = S;
    end

    if isfield(T, 'A') && ~isempty(T.A)
        T.warpA = T.A;
    elseif isfield(T, 'M') && ~isempty(T.M)
        T.warpA = T.M;
    elseif isfield(T, 'T') && ~isempty(T.T)
        T.warpA = T.T;
    elseif isfield(T, 'tform') && ~isempty(T.tform)
        try
            T.warpA = T.tform.T;
        catch
            error('Found tform field, but could not extract numeric matrix from it.');
        end
    else
        error('Transform file has no usable matrix field. Expected A, M, T, or tform.T.');
    end

    if isfield(T, 'outputSize') && ~isempty(T.outputSize)
        T.outSize = double(T.outputSize);
    elseif isfield(T, 'size') && ~isempty(T.size)
        T.outSize = double(T.size);
    elseif isfield(T, 'atlasSize') && ~isempty(T.atlasSize)
        T.outSize = double(T.atlasSize);
    elseif isfield(T, 'outSize') && ~isempty(T.outSize)
        T.outSize = double(T.outSize);
    else
        T.outSize = [];
    end

    if ~isfield(T, 'type') || isempty(T.type)
        T.type = 'unknown';
    end
    if ~isfield(T, 'atlasSliceIndex') || isempty(T.atlasSliceIndex)
        T.atlasSliceIndex = NaN;
    end
    if ~isfield(T, 'atlasMode') || isempty(T.atlasMode)
        T.atlasMode = '';
    end
end

function Y = warpFunctionalSeriesToAtlas(X, T)
    A = double(T.warpA);

    if ndims(X) == 4 && isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3
            error('3D atlas warp requires output size in outputSize / size / atlasSize / outSize.');
        end

        outSize3 = round(T.outSize(1:3));
        if any(outSize3 < 1)
            error('Invalid 3D output size in transform file.');
        end

        tform3 = affine3d(A);
        Rout3  = imref3d(outSize3);

        nTT = size(X,4);
        Y = zeros([outSize3 nTT], 'single');

        for tt = 1:nTT
            vol = single(X(:,:,:,tt));
            Y(:,:,:,tt) = imwarp(vol, tform3, 'linear', 'OutputView', Rout3);
        end
        return;
    end

    if isequal(size(A), [3 3])
        if isempty(T.outSize) || numel(T.outSize) < 2
            error('2D atlas warp requires output size in outputSize / size / atlasSize / outSize.');
        end

        outSize2 = round(T.outSize(1:2));
        if any(outSize2 < 1)
            error('Invalid 2D output size in transform file.');
        end

        tform2 = affine2d(A);
        Rout2  = imref2d(outSize2);

        if ndims(X) == 3
            nTT = size(X,3);
            Y = zeros([outSize2 nTT], 'single');

            for tt = 1:nTT
                frm = single(X(:,:,tt));
                Y(:,:,tt) = imwarp(frm, tform2, 'linear', 'OutputView', Rout2);
            end
            return;

        elseif ndims(X) == 4
            zSel = max(1, min(size(X,3), state.z));
            X2   = squeeze(X(:,:,zSel,:));

            nTT = size(X2,3);
            Y = zeros([outSize2 nTT], 'single');

            for tt = 1:nTT
                frm = single(X2(:,:,tt));
                Y(:,:,tt) = imwarp(frm, tform2, 'linear', 'OutputView', Rout2);
            end

            try
                set(info1, 'String', sprintf(['Applied simple 2D coronal atlas warp to current slice %d only. ' ...
                    'SCM now displays one atlas slice.'], zSel));
            catch
            end
            return;
        else
            error('For 2D atlas warp, PSC must be [Y X T] or [Y X Z T].');
        end
    end

    error('Unsupported transform matrix size: %dx%d', size(A,1), size(A,2));
end

%%%%% Load New Underlay %%%%

function loadNewUnderlayCB(~,~)
    ensureUnderlayStateFields();
    startPath = getUnderlayStartPath();

    [f,p] = uigetfile( ...
        {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.jpeg,*.tif,*.tiff,*.bmp)'}, ...
        'Select new underlay', startPath);

    if isequal(f, 0)
        return;
    end

    fullf = fullfile(p, f);

    try
        [Uraw, meta] = readUnderlayFile(fullf);
        Uraw = squeeze(Uraw);

        if isempty(Uraw) || ~(isnumeric(Uraw) || islogical(Uraw))
            error('Selected underlay is empty or not numeric/RGB: %s', fullf);
        end

        if state.isAtlasWarped
            U = [];

            if doesUnderlayMatchCurrentDisplay(Uraw)
                U = validateAndPrepareUnderlay(Uraw, fullf);
                applyUnderlayMeta(meta, U);

            elseif doesUnderlayMatchOriginalDisplay(Uraw)
                tfFile = getBestTransformForUnderlay(fullf);
                if isempty(tfFile) || exist(tfFile, 'file') ~= 2
                    error(['Current SCM is atlas-warped, but no transform file could be found ' ...
                           'to auto-warp the newly selected native underlay.']);
                end

                S = load(tfFile);
                T = extractAtlasWarpStruct(S);

                U = warpUnderlayForCurrentDisplay(Uraw, T);
                U = validateAndPrepareUnderlay(U, fullf);
                applyUnderlayMeta(meta, U);

            else
                error(['Selected underlay does not match either current atlas display ' ...
                       'or original native space.']);
            end

            bg = U;
            bg2 = getBg2DForSlice(state.z);
            set(hBG, 'CData', renderUnderlayRGB(bg2));

            try
                set(info1, 'String', ['Loaded atlas-space underlay: ' shortenPath(fullf,85)]);
                set(info1, 'TooltipString', fullf);
            catch
            end
            drawnow;
            return;
        end

        if doesUnderlayMatchCurrentDisplay(Uraw)
            U = validateAndPrepareUnderlay(Uraw, fullf);
            applyUnderlayMeta(meta, U);

            bg = U;
            origBG = bg;

            bg2 = getBg2DForSlice(state.z);
            set(hBG, 'CData', renderUnderlayRGB(bg2));

            try
                set(info1, 'String', ['Loaded underlay: ' shortenPath(fullf,85)]);
                set(info1, 'TooltipString', fullf);
            catch
            end
            drawnow;
            return;
        end

        tfFile = getBestTransformForUnderlay(fullf);

        if isempty(tfFile) || exist(tfFile, 'file') ~= 2
            [ft,pt] = uigetfile({'*.mat','Transform files (*.mat)'}, ...
                'Selected underlay looks atlas-sized. Select transform file', getUnderlayStartPath());
            if isequal(ft,0)
                return;
            end
            tfFile = fullfile(pt, ft);
        end

        S = load(tfFile);
        T = extractAtlasWarpStruct(S);

        if ~doesUnderlayMatchTransformOutput(Uraw, T)
            error(['Selected underlay size [%d %d] does not match current native SCM size [%d %d] ' ...
                   'and also does not match transform output size.'], ...
                   size(Uraw,1), size(Uraw,2), nY, nX);
        end

        PSC = warpFunctionalSeriesToAtlas(origPSC, T);

        passedMask = [];
        passedMaskIsInclude = true;

        state.isAtlasWarped = true;
        state.atlasTransformFile = tfFile;
        state.lastAtlasTransformFile = tfFile;

        resetRoisAndRefreshAfterDataChange();

        U = validateAndPrepareUnderlay(Uraw, fullf);
        applyUnderlayMeta(meta, U);

        bg = U;

        bg2 = getBg2DForSlice(state.z);
        set(hBG, 'CData', renderUnderlayRGB(bg2));

        try
            if isfield(T,'type') && strcmpi(char(T.type), 'simple_coronal_2d') ...
                    && isfield(T,'atlasSliceIndex') && isfinite(T.atlasSliceIndex)
                set(txtTitle, 'String', sprintf('%s | warped to atlas coronal slice %d', ...
                    fileLabel, round(T.atlasSliceIndex)));
            else
                set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
            end
        catch
            set(txtTitle, 'String', sprintf('%s | warped to atlas', fileLabel));
        end

        try
            set(info1, 'String', ['Loaded atlas underlay and warped functional: ' shortenPath(fullf,70)]);
            set(info1, 'TooltipString', fullf);
        catch
        end

        drawnow;

    catch ME
        errordlg(ME.message, 'Load underlay failed');
    end
end

function U = validateAndPrepareUnderlay(U, fullf)
    U = squeeze(U);

    if isempty(U) || ~(isnumeric(U) || islogical(U))
        error('Loaded underlay is not numeric or logical: %s', fullf);
    end

    if ndims(U) == 2
        U = double(U);
        return;
    end

    if ndims(U) == 3
        if size(U,3) == 3
            U = double(U);
            return;
        else
            U = double(U);
            return;
        end
    end

    if ndims(U) == 4
        if size(U,3) == 3 && size(U,4) >= 1
            U = double(U);
            return;
        end
        U = double(U);
        return;
    end

    error('Unsupported underlay dimensionality in file: %s', fullf);
end

function applyUnderlayMeta(meta, U)
    ensureUnderlayStateFields();

    state.isColorUnderlay     = false;
    state.regionLabelUnderlay = [];
    state.regionColorLUT      = [];
    state.regionInfo          = struct();

    if nargin >= 1 && isstruct(meta)
        if isfield(meta, 'isColor') && ~isempty(meta.isColor)
            state.isColorUnderlay = logical(meta.isColor);
        end
        if isfield(meta, 'regionLabels') && ~isempty(meta.regionLabels)
            state.regionLabelUnderlay = double(meta.regionLabels);
            state.isColorUnderlay = true;
        end
        if isfield(meta, 'regionInfo') && ~isempty(meta.regionInfo)
            state.regionInfo = meta.regionInfo;
        end
    end

    if nargin >= 2 && ~state.isColorUnderlay
        if ndims(U) == 3 && size(U,3) == 3
            state.isColorUnderlay = true;
        end
    end
end

function tf = doesUnderlayMatchTransformOutput(U, T)
    tf = false;
    try
        U = squeeze(U);
        if isempty(T) || ~isfield(T,'outSize') || isempty(T.outSize)
            return;
        end

        outSize = round(double(T.outSize));
        if numel(outSize) < 2
            return;
        end

        tf = (size(U,1) == outSize(1) && size(U,2) == outSize(2));
    catch
        tf = false;
    end
end

function tfFile = getBestTransformForUnderlay(underlayFile)
    tfFile = '';

    cand = {};

    try
        if isfield(state, 'atlasTransformFile') && ~isempty(state.atlasTransformFile) ...
                && exist(state.atlasTransformFile, 'file') == 2
            cand{end+1} = char(state.atlasTransformFile); %#ok<AGROW>
        end
    catch
    end

    try
        if isfield(state, 'lastAtlasTransformFile') && ~isempty(state.lastAtlasTransformFile) ...
                && exist(state.lastAtlasTransformFile, 'file') == 2
            cand{end+1} = char(state.lastAtlasTransformFile); %#ok<AGROW>
        end
    catch
    end

    try
        udir = fileparts(char(underlayFile));
        cand{end+1} = fullfile(udir, 'CoronalRegistration2D.mat'); %#ok<AGROW>
        cand{end+1} = fullfile(udir, 'Transformation.mat'); %#ok<AGROW>

        p1 = fileparts(udir);
        cand{end+1} = fullfile(p1, 'Registration2D', 'CoronalRegistration2D.mat'); %#ok<AGROW>
        cand{end+1} = fullfile(p1, 'Registration',   'Transformation.mat');        %#ok<AGROW>
        cand{end+1} = fullfile(p1, 'CoronalRegistration2D.mat');                   %#ok<AGROW>
        cand{end+1} = fullfile(p1, 'Transformation.mat');                          %#ok<AGROW>

        p2 = fileparts(p1);
        cand{end+1} = fullfile(p2, 'Registration2D', 'CoronalRegistration2D.mat'); %#ok<AGROW>
        cand{end+1} = fullfile(p2, 'Registration',   'Transformation.mat');        %#ok<AGROW>
    catch
    end

    try
        if isstruct(par) && isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir') == 7
            ep = char(par.exportPath);
            cand{end+1} = fullfile(ep, 'Registration2D', 'CoronalRegistration2D.mat'); %#ok<AGROW>
            cand{end+1} = fullfile(ep, 'Registration',   'Transformation.mat');        %#ok<AGROW>
            cand{end+1} = fullfile(ep, 'CoronalRegistration2D.mat');                   %#ok<AGROW>
            cand{end+1} = fullfile(ep, 'Transformation.mat');                          %#ok<AGROW>
        end
    catch
    end

    for ii = 1:numel(cand)
        try
            if ~isempty(cand{ii}) && exist(cand{ii}, 'file') == 2
                tfFile = cand{ii};
                return;
            end
        catch
        end
    end
end

function startPath = getUnderlayStartPath()
    startPath = '';

    candDirs = {};

    try
        if state.isAtlasWarped && isfield(state, 'atlasTransformFile') && ~isempty(state.atlasTransformFile)
            tfDir = fileparts(char(state.atlasTransformFile));
            candDirs{end+1} = tfDir; %#ok<AGROW>
            candDirs{end+1} = fullfile(tfDir, '..'); %#ok<AGROW>
        end
    catch
    end

    try
        if isstruct(par)
            if isfield(par, 'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath, 'dir') == 7
                ep = char(par.exportPath);
                candDirs{end+1} = fullfile(ep, 'Registration2D'); %#ok<AGROW>
                candDirs{end+1} = fullfile(ep, 'Registration');   %#ok<AGROW>
                candDirs{end+1} = fullfile(ep, 'Visualization');  %#ok<AGROW>
                candDirs{end+1} = ep;                             %#ok<AGROW>
            end
        end
    catch
    end

    try
        if isstruct(par)
            if isfield(par, 'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath, 'dir') == 7
                lp = char(par.loadedPath);

                if contains(lp, [filesep 'RawData' filesep])
                    ap = strrep(lp, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
                    candDirs{end+1} = fullfile(ap, 'Registration2D'); %#ok<AGROW>
                    candDirs{end+1} = fullfile(ap, 'Registration');   %#ok<AGROW>
                    candDirs{end+1} = fullfile(ap, 'Visualization');  %#ok<AGROW>
                    candDirs{end+1} = ap;                             %#ok<AGROW>
                end

                candDirs{end+1} = fullfile(lp, 'Registration2D'); %#ok<AGROW>
                candDirs{end+1} = fullfile(lp, 'Registration');   %#ok<AGROW>
                candDirs{end+1} = fullfile(lp, 'Visualization');  %#ok<AGROW>
                candDirs{end+1} = lp;                             %#ok<AGROW>
            end
        end
    catch
    end

    try
        if isstruct(par)
            if isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf, 'file') == 2
                    ldir = fileparts(lf);

                    if contains(ldir, [filesep 'RawData' filesep])
                        ap = strrep(ldir, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
                        candDirs{end+1} = fullfile(ap, 'Registration2D'); %#ok<AGROW>
                        candDirs{end+1} = fullfile(ap, 'Registration');   %#ok<AGROW>
                        candDirs{end+1} = fullfile(ap, 'Visualization');  %#ok<AGROW>
                        candDirs{end+1} = ap;                             %#ok<AGROW>
                    end

                    candDirs{end+1} = fullfile(ldir, 'Registration2D'); %#ok<AGROW>
                    candDirs{end+1} = fullfile(ldir, 'Registration');   %#ok<AGROW>
                    candDirs{end+1} = fullfile(ldir, 'Visualization');  %#ok<AGROW>
                    candDirs{end+1} = ldir;                             %#ok<AGROW>
                end
            end
        end
    catch
    end

    try
        candDirs{end+1} = getStartPath(); %#ok<AGROW>
    catch
    end
    candDirs{end+1} = pwd;

    for ii = 1:numel(candDirs)
        d = candDirs{ii};
        try
            if ~isempty(d) && exist(d, 'dir') == 7
                startPath = d;
                return;
            end
        catch
        end
    end

    startPath = pwd;
end

function [U, meta] = readUnderlayFile(f)
    if ~exist(f, 'file')
        error('Underlay file not found: %s', f);
    end

    meta = defaultUnderlayMeta();

    isNiiGz = (numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz'));
    if isNiiGz
        tmpDir = tempname;
        mkdir(tmpDir);
        gunzip(f, tmpDir);
        ddd = dir(fullfile(tmpDir, '*.nii'));
        if isempty(ddd)
            error('Failed to gunzip .nii.gz underlay.');
        end
        niiFile = fullfile(tmpDir, ddd(1).name);
        U = double(niftiread(niiFile));
        try
            rmdir(tmpDir, 's');
        catch
        end
        return;
    end

    [~,~,e] = fileparts(f);
    e = lower(e);

    switch e
        case '.mat'
            S = load(f);
            [U, meta] = extractUnderlayFromMatStruct(S);

        case '.nii'
            U = double(niftiread(f));

        case {'.png','.jpg','.jpeg','.tif','.tiff','.bmp'}
            U = imread(f);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
                U = double(U);
            else
                U = double(U);
            end

        otherwise
            error('Unsupported underlay file type: %s', e);
    end
end

function meta = defaultUnderlayMeta()
    meta = struct();
    meta.isColor = false;
    meta.regionLabels = [];
    meta.regionInfo = struct();
    meta.atlasMode = '';
end

function [U, meta] = extractUnderlayFromMatStruct(S)
    meta = defaultUnderlayMeta();

    if isfield(S, 'atlasMode') && ~isempty(S.atlasMode)
        try
            meta.atlasMode = char(S.atlasMode);
        catch
            meta.atlasMode = '';
        end
    end

    if strcmpi(meta.atlasMode, 'regions')
        if isfield(S, 'atlasUnderlayRGB') && ~isempty(S.atlasUnderlayRGB)
            U = double(S.atlasUnderlayRGB);
            meta.isColor = true;
        elseif isfield(S, 'brainImage') && ~isempty(S.brainImage)
            U = double(S.brainImage);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
        else
            error('Regions MAT file has no atlasUnderlayRGB / brainImage.');
        end

        if isfield(S, 'atlasRegionLabels2D') && ~isempty(S.atlasRegionLabels2D)
            meta.regionLabels = double(S.atlasRegionLabels2D);
        elseif isfield(S, 'atlasUnderlay') && ~isempty(S.atlasUnderlay)
            meta.regionLabels = double(S.atlasUnderlay);
        end

        if isfield(S, 'atlasInfoRegions') && ~isempty(S.atlasInfoRegions)
            meta.regionInfo = S.atlasInfoRegions;
        elseif isfield(S, 'infoRegions') && ~isempty(S.infoRegions)
            meta.regionInfo = S.infoRegions;
        end
        return;
    end

    pref = {'atlasUnderlayRGB','underlay','bg','brainImage','img','I','atlasUnderlay','vascular','histology','regions','Data'};

    for ii = 1:numel(pref)
        if isfield(S, pref{ii})
            v = S.(pref{ii});

            if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data)
                U = double(v.Data);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                return;

            elseif isnumeric(v) || islogical(v)
                U = double(v);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                return;
            end
        end
    end

    fn = fieldnames(S);
    for ii = 1:numel(fn)
        v = S.(fn{ii});

        if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data)
            U = double(v.Data);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
            return;

        elseif isnumeric(v) || islogical(v)
            U = double(v);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
            return;
        end
    end

    error('MAT underlay file has no usable numeric variable.');
end

function U = convertRgbToGrayIfNeeded(U)
    if ndims(U) == 3 && size(U,3) == 3
        U = mean(double(U), 3);
    else
        U = double(U);
    end
end

function Uout = warpUnderlayForCurrentDisplay(Uin, T)
    A = double(T.warpA);

    if isequal(size(A), [3 3])
        if isempty(T.outSize) || numel(T.outSize) < 2
            error('2D underlay warp requires output size in transform file.');
        end

        outSize2 = round(T.outSize(1:2));
        if any(outSize2 < 1)
            error('Invalid 2D output size in transform file.');
        end

        tform2 = affine2d(A);
        Rout2  = imref2d(outSize2);

        if ndims(Uin) == 2
            Uout = imwarp(single(Uin), tform2, 'linear', 'OutputView', Rout2);

        elseif ndims(Uin) == 3
            if size(Uin,3) == 1
                Uout = imwarp(single(Uin(:,:,1)), tform2, 'linear', 'OutputView', Rout2);
            elseif size(Uin,1) == size(origPSC,1) && size(Uin,2) == size(origPSC,2)
                n3 = size(Uin,3);
                Uout = zeros([outSize2 n3], 'single');
                for kk = 1:n3
                    Uout(:,:,kk) = imwarp(single(Uin(:,:,kk)), tform2, 'linear', 'OutputView', Rout2);
                end
            else
                error('Unsupported 3D underlay layout for 2D warp.');
            end
        else
            error('Unsupported underlay dimensionality for 2D warp.');
        end
        return;
    end

    if isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3
            error('3D underlay warp requires output size in transform file.');
        end

        outSize3 = round(T.outSize(1:3));
        if any(outSize3 < 1)
            error('Invalid 3D output size in transform file.');
        end

        tform3 = affine3d(A);
        Rout3  = imref3d(outSize3);

        if ndims(Uin) == 3
            Uout = imwarp(single(Uin), tform3, 'linear', 'OutputView', Rout3);

        elseif ndims(Uin) == 4
            n4 = size(Uin,4);
            Uout = zeros([outSize3 n4], 'single');
            for kk = 1:n4
                Uout(:,:,:,kk) = imwarp(single(Uin(:,:,:,kk)), tform3, 'linear', 'OutputView', Rout3);
            end
        else
            error('Unsupported underlay dimensionality for 3D warp.');
        end
        return;
    end

    error('Unsupported transform matrix size for underlay warp: %dx%d', size(A,1), size(A,2));
end

function tf = doesUnderlayMatchCurrentDisplay(U)
    tf = false;
    try
        U = squeeze(U);
        if ndims(U) == 2
            tf = (size(U,1) == nY && size(U,2) == nX);
        elseif ndims(U) >= 3
            tf = (size(U,1) == nY && size(U,2) == nX);
        end
    catch
        tf = false;
    end
end

function tf = doesUnderlayMatchOriginalDisplay(U)
    tf = false;
    try
        U = squeeze(U);

        if ndims(origPSC) == 3
            oY = size(origPSC,1);
            oX = size(origPSC,2);
        else
            oY = size(origPSC,1);
            oX = size(origPSC,2);
        end

        tf = (size(U,1) == oY && size(U,2) == oX);
    catch
        tf = false;
    end
end

function rgb = renderUnderlayRGB(Uin)
    ensureUnderlayStateFields();

    if state.isColorUnderlay
        rgb = convertUnderlayToColorRGB(Uin);
    else
        rgb = toRGB(processUnderlay(Uin));
    end
end

function rgb = convertUnderlayToColorRGB(U)
    U = squeeze(U);

    if ndims(U) == 3 && size(U,3) == 3
        rgb = double(U);
        if max(rgb(:)) > 1
            rgb = rgb / 255;
        end
        rgb = min(max(rgb,0),1);
        return;
    end

    if isnumeric(U) || islogical(U)
        L = double(U);
        L(~isfinite(L)) = 0;

        maxLab = max(L(:));
        if isempty(state.regionColorLUT) || size(state.regionColorLUT,1) < max(1,maxLab)
            state.regionColorLUT = makeRegionColorLUT(max(1, maxLab));
        end

        rgb = zeros([size(L,1) size(L,2) 3], 'double');

        zmask = (L == 0);
        rgb(:,:,1) = 0.85 * zmask;
        rgb(:,:,2) = 0.85 * zmask;
        rgb(:,:,3) = 0.85 * zmask;

        pos = find(L > 0);
        if ~isempty(pos)
            labs = round(L(pos));
            labs(labs < 1) = 1;
            labs(labs > size(state.regionColorLUT,1)) = size(state.regionColorLUT,1);

            c = state.regionColorLUT(labs, :);
            tmp = reshape(rgb, [], 3);
            tmp(pos, :) = c;
            rgb = reshape(tmp, size(rgb));
        end

        rgb = min(max(rgb,0),1);
        return;
    end

    rgb = toRGB(processUnderlay(U));
end

function lut = makeRegionColorLUT(n)
    if n <= 0
        lut = zeros(1,3);
        return;
    end

    base = lines(max(n, 12));
    lut = base(1:n, :);

    if n > size(base,1)
        x  = linspace(0,1,size(base,1));
        xi = linspace(0,1,n);
        tmp = zeros(n,3);
        for k = 1:3
            tmp(:,k) = interp1(x, base(:,k), xi, 'linear');
        end
        lut = min(max(tmp,0),1);
    end
end

function ensureUnderlayStateFields()
    if ~isfield(state, 'isColorUnderlay') || isempty(state.isColorUnderlay)
        state.isColorUnderlay = false;
    end
    if ~isfield(state, 'regionLabelUnderlay') || isempty(state.regionLabelUnderlay)
        state.regionLabelUnderlay = [];
    end
    if ~isfield(state, 'regionColorLUT') || isempty(state.regionColorLUT)
        state.regionColorLUT = [];
    end
    if ~isfield(state, 'regionInfo') || isempty(state.regionInfo)
        state.regionInfo = struct();
    end
end

%% ==========================================================
% Pointer hit test
%% ==========================================================
function tf = isPointerOverImageAxis()
    tf = false;
    try
        h = hittest(fig);
        if isempty(h), return; end
        axHit = ancestor(h, 'axes');
        tf = ~isempty(axHit) && axHit == ax;
    catch
        try
            tf = isequal(gca, ax);
        catch
            tf = false;
        end
    end
end

%% ==========================================================
% Underlay processing
%% ==========================================================
function U = processUnderlay(Uin)
    U = double(Uin);
    U(~isfinite(U)) = 0;

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
    U = min(max(U, 0), 1);

    g = uState.gamma;
    if ~isfinite(g) || g <= 0, g = 1; end
    U = U.^g;
    U = min(max(U, 0), 1);
end

function U = vesselEnhanceStrong(U01, conectSizePx, conectLev_0_MAX)
    if conectSizePx <= 0
        U = U01;
        return;
    end

    lev01 = (conectLev_0_MAX / max(1, MAX_CONLEV));
    lev01 = lev01^0.75;
    lev01 = min(max(lev01, 0), 1);

    thrMask = (U01 > lev01);

    r = max(1, round(conectSizePx));
    r = min(r, MAX_CONSIZE);
    h = diskKernel(r);

    try
        D = filter2(h, double(thrMask), 'same');
    catch
        D = conv2(double(thrMask), h, 'same');
    end
    D = min(max(D, 0), 1);

    strength = 0.8 + 1.6 * min(1, r/120);
    D2 = D.^2;

    U = U01 .* (1 + strength*D2) + 0.15*D2;
    U = min(max(U, 0), 1);
end

function h = diskKernel(r)
    r = max(1, round(r));
    [x,y] = meshgrid(-r:r, -r:r);
    m = (x.^2 + y.^2) <= r^2;
    h = double(m);
    s = sum(h(:));
    if s > 0
        h = h/s;
    end
end

%% ==========================================================
% Colormap
%% ==========================================================
function setOverlayColormap(name)
    cm = getCmap(name, 256);
    try
        colormap(ax, cm);
    catch
        colormap(fig, cm);
    end
end

function cm = getCmap(name, n)
    if isstring(name), name = char(name); end
    name = lower(strtrim(name));

    if strcmp(name, 'blackbdy_iso')
        if exist('blackbdy_iso', 'file')
            cm = blackbdy_iso(n);
        else
            cm = hot(n);
        end
        return;
    end

    switch name
        case 'hot'
            cm = hot(n); return;
        case 'parula'
            cm = parula(n); return;
        case 'jet'
            cm = jet(n); return;
        case 'gray'
            cm = gray(n); return;
        case 'bone'
            cm = bone(n); return;
        case 'copper'
            cm = copper(n); return;
        case 'pink'
            cm = pink(n); return;
    end

    if strcmp(name, 'turbo')
        if exist('turbo', 'file')
            cm = turbo(n);
        else
            cm = jet(n);
        end
        return;
    end

    switch name
        case 'viridis'
            anchors = [ ...
                0.267 0.005 0.329;
                0.283 0.141 0.458;
                0.254 0.265 0.530;
                0.207 0.372 0.553;
                0.164 0.471 0.558;
                0.128 0.567 0.551;
                0.135 0.659 0.518;
                0.267 0.749 0.441;
                0.478 0.821 0.318;
                0.741 0.873 0.150];
            cm = interpAnchors(anchors, n);
            return;

        case 'plasma'
            anchors = [ ...
                0.050 0.030 0.528;
                0.280 0.040 0.650;
                0.500 0.060 0.650;
                0.700 0.170 0.550;
                0.850 0.350 0.420;
                0.940 0.550 0.260;
                0.990 0.750 0.140];
            cm = interpAnchors(anchors, n);
            return;

        case 'magma'
            anchors = [ ...
                0.001 0.000 0.015;
                0.100 0.060 0.230;
                0.250 0.080 0.430;
                0.450 0.120 0.500;
                0.650 0.210 0.420;
                0.820 0.370 0.280;
                0.930 0.610 0.210;
                0.990 0.870 0.400];
            cm = interpAnchors(anchors, n);
            return;

        case 'inferno'
            anchors = [ ...
                0.002 0.002 0.014;
                0.120 0.030 0.220;
                0.280 0.050 0.400;
                0.480 0.090 0.430;
                0.680 0.180 0.330;
                0.820 0.350 0.210;
                0.930 0.590 0.110;
                0.990 0.860 0.240];
            cm = interpAnchors(anchors, n);
            return;
    end

    cm = hot(n);
end

function cm = interpAnchors(anchors, n)
    x = linspace(0, 1, size(anchors,1));
    xi = linspace(0, 1, n);
    cm = zeros(n, 3);
    for k = 1:3
        cm(:,k) = interp1(x, anchors(:,k), xi, 'linear');
    end
    cm = min(max(cm, 0), 1);
end

%% ==========================================================
% Time windows
%% ==========================================================
    function drawTimeWindows()
    [b0,b1] = parseRangeSafe(getStr(ebBase), 30, 240);
    [s0,s1] = parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

    if isVolMode
        b0s = (clamp(round(b0), 1, nT)-1)*TR;
        b1s = (clamp(round(b1), 1, nT)-1)*TR;
        s0s = (clamp(round(s0), 1, nT)-1)*TR;
        s1s = (clamp(round(s1), 1, nT)-1)*TR;
    else
        b0s = b0; b1s = b1;
        s0s = s0; s1s = s1;
    end
    if b1s < b0s, tmp = b0s; b0s = b1s; b1s = tmp; end
    if s1s < s0s, tmp = s0s; s0s = s1s; s1s = tmp; end

    yl = get(axTC, 'YLim');
    if any(~isfinite(yl)) || yl(2) <= yl(1)
        yl = [-5 5];
        set(axTC, 'YLim', yl);
    end

    yr = yl(2) - yl(1);
    if ~isfinite(yr) || yr <= 0
        yr = 1;
    end

    xb = [b0s b1s b1s b0s] / 60;
    yb = [yl(1) yl(1) yl(2) yl(2)];
    set(hBasePatch, ...
        'XData', xb, ...
        'YData', yb, ...
        'FaceColor', [1.00 0.20 0.20], ...
        'FaceAlpha', 0.16, ...
        'Visible', 'on');

    xs = [s0s s1s s1s s0s] / 60;
    ys = [yl(1) yl(1) yl(2) yl(2)];
    set(hSigPatch, ...
        'XData', xs, ...
        'YData', ys, ...
        'FaceColor', [1.00 0.60 0.15], ...
        'FaceAlpha', 0.16, ...
        'Visible', 'on');

    yTxt = yl(2) - 0.06 * yr;

    set(hBaseTxt, ...
        'Position', [mean(xb) yTxt 0], ...
        'String', 'Bas.', ...
        'Visible', 'on', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0 0 0], ...
        'Margin', 1, ...
        'Clipping', 'on');

    set(hSigTxt, ...
        'Position', [mean(xs) yTxt 0], ...
        'String', 'Sig.', ...
        'Visible', 'on', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'BackgroundColor', [0 0 0], ...
        'Margin', 1, ...
        'Clipping', 'on');

    uistack(hBasePatch, 'bottom');
    uistack(hSigPatch, 'bottom');
end

%% ==========================================================
% ROI drawing
%% ==========================================================
function redrawROIsForCurrentSlice()
    deleteIfValid(roiHandles);
    roiHandles = gobjects(0);

    deleteIfValid(roiPlotPSC);
    roiPlotPSC = gobjects(0);

    deleteIfValid(roiTextHandles);
    roiTextHandles = gobjects(0);

    ROI = ROI_byZ{state.z};
    if isempty(ROI), return; end

    for k = 1:numel(ROI)
        r = ROI(k);

        roiHandles(end+1) = rectangle(ax, 'Position', [r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor', r.color, ...
            'LineWidth', 2); %#ok<AGROW>

        xLab = r.x1;
        yLab = max(1, r.y1 - 2);
        roiTextHandles(end+1) = text(ax, xLab, yLab, sprintf('%d', r.id), ...
            'Color', r.color, ...
            'FontWeight', 'bold', ...
            'FontSize', 12, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'bottom', ...
            'BackgroundColor', [0 0 0], ...
            'Margin', 1); %#ok<AGROW>

        tc = computeRoiPSC_atSlice(state.z, r.x1, r.x2, r.y1, r.y2);
        if numel(tc) == nT
            roiPlotPSC(end+1) = plot(axTC, tmin, tc, ':', 'Color', r.color, 'LineWidth', 2.4); %#ok<AGROW>
        end
    end
end

function deleteIfValid(h)
    if isempty(h), return; end
    for i = 1:numel(h)
        if isgraphics(h(i))
            delete(h(i));
        end
    end
end

%% ==========================================================
% Data helpers
%% ==========================================================
function PSCz = getPSCForSlice(z)
    if ndims(PSC) == 3
        PSCz = PSC;
    else
        PSCz = squeeze(PSC(:,:,z,:));
    end
end

function bg2 = getBg2DForSlice(z)
    if ndims(bg) == 3 && size(bg,3) == 3
        bg2 = bg;
        return;
    end

    if ndims(bg) == 2
        bg2 = bg;
        return;
    end

    if ndims(bg) == 3
        if size(bg,3) == nT && nZ == 1
            bg2 = mean(bg, 3);
        else
            z = max(1, min(size(bg,3), z));
            bg2 = bg(:,:,z);
        end
        return;
    end

    if ndims(bg) == 4
        if size(bg,3) == 3 && size(bg,4) >= 1
            z = max(1, min(size(bg,4), z));
            bg2 = squeeze(bg(:,:,:,z));
            return;
        end

        tmp = mean(bg, 4);
        z = max(1, min(size(tmp,3), z));
        bg2 = tmp(:,:,z);
        return;
    end

    bg2 = bg(:,:,1);
end

function B = readScmBundleFile(fullf)
    if ~exist(fullf, 'file')
        error('File not found: %s', fullf);
    end

    S = load(fullf);

    if isfield(S, 'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle)
        R = S.maskBundle;
    else
        R = S;
    end

    B = struct();
    B.brainImage = [];
    B.overlayMask = [];
    B.brainMask = [];
    B.overlayMaskIsInclude = true;
    B.brainMaskIsInclude = true;
    B.loadedField = '';
    B.source = fullf;

    overlayFields = { ...
        'loadedMask', ...
        'overlayMask', ...
        'signalMask', ...
        'overlay', ...
        'overlay_mask', ...
        'signal_mask', ...
        'mask', ...
        'activeMask'};

    for k = 1:numel(overlayFields)
        fn = overlayFields{k};
        if isfield(R, fn) && ~isempty(R.(fn)) && (isnumeric(R.(fn)) || islogical(R.(fn)))
            B.overlayMask = logical(R.(fn));
            B.loadedField = fn;
            break;
        elseif isfield(S, fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
            B.overlayMask = logical(S.(fn));
            B.loadedField = fn;
            break;
        end
    end

    brainFields = {'brainMask','underlayMask','brain_mask','underlay_mask'};
    for k = 1:numel(brainFields)
        fn = brainFields{k};
        if isfield(R, fn) && ~isempty(R.(fn)) && (isnumeric(R.(fn)) || islogical(R.(fn)))
            B.brainMask = logical(R.(fn));
            break;
        elseif isfield(S, fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
            B.brainMask = logical(S.(fn));
            break;
        end
    end

    underlayFields = { ...
        'brainImage', ...
        'underlay', ...
        'bg', ...
        'anatomical_reference', ...
        'anatomical_reference_raw', ...
        'brain_image'};

    for k = 1:numel(underlayFields)
        fn = underlayFields{k};
        if isfield(R, fn) && ~isempty(R.(fn)) && isnumeric(R.(fn))
            B.brainImage = double(R.(fn));
            break;
        elseif isfield(S, fn) && ~isempty(S.(fn)) && isnumeric(S.(fn))
            B.brainImage = double(S.(fn));
            break;
        end
    end

    if isfield(R, 'overlayMaskIsInclude') && ~isempty(R.overlayMaskIsInclude)
        B.overlayMaskIsInclude = logical(R.overlayMaskIsInclude);
    elseif isfield(S, 'overlayMaskIsInclude') && ~isempty(S.overlayMaskIsInclude)
        B.overlayMaskIsInclude = logical(S.overlayMaskIsInclude);
    elseif isfield(R, 'loadedMaskIsInclude') && ~isempty(R.loadedMaskIsInclude)
        B.overlayMaskIsInclude = logical(R.loadedMaskIsInclude);
    elseif isfield(S, 'loadedMaskIsInclude') && ~isempty(S.loadedMaskIsInclude)
        B.overlayMaskIsInclude = logical(S.loadedMaskIsInclude);
    elseif isfield(R, 'maskIsInclude') && ~isempty(R.maskIsInclude)
        B.overlayMaskIsInclude = logical(R.maskIsInclude);
    elseif isfield(S, 'maskIsInclude') && ~isempty(S.maskIsInclude)
        B.overlayMaskIsInclude = logical(S.maskIsInclude);
    else
        B.overlayMaskIsInclude = true;
    end

    if isfield(R, 'brainMaskIsInclude') && ~isempty(R.brainMaskIsInclude)
        B.brainMaskIsInclude = logical(R.brainMaskIsInclude);
    elseif isfield(S, 'brainMaskIsInclude') && ~isempty(S.brainMaskIsInclude)
        B.brainMaskIsInclude = logical(S.brainMaskIsInclude);
    elseif isfield(R, 'maskIsInclude') && ~isempty(R.maskIsInclude)
        B.brainMaskIsInclude = logical(R.maskIsInclude);
    elseif isfield(S, 'maskIsInclude') && ~isempty(S.maskIsInclude)
        B.brainMaskIsInclude = logical(S.maskIsInclude);
    else
        B.brainMaskIsInclude = true;
    end
end

function M = fitBundleMaskToCurrentScm(M0)
    M = [];

    if isempty(M0)
        return;
    end

    M0 = logical(M0);

    if ismatrix(M0)
        if size(M0,1) == nY && size(M0,2) == nX
            M = M0;
        else
            try
                M = imresize(double(M0), [nY nX], 'nearest') > 0.5;
            catch
                M = false(nY, nX);
            end
        end
        return;
    end

    if ndims(M0) == 3
        if size(M0,1) ~= nY || size(M0,2) ~= nX
            try
                tmp = false(nY, nX, size(M0,3));
                for zz = 1:size(M0,3)
                    tmp(:,:,zz) = imresize(double(M0(:,:,zz)), [nY nX], 'nearest') > 0.5;
                end
                M0 = tmp;
            catch
                M0 = false(nY, nX, size(M0,3));
            end
        end

        if nZ > 1 && size(M0,3) == nZ
            M = M0;
        elseif nZ == 1
            M = any(M0, 3);
        else
            zIdx = round(linspace(1, size(M0,3), nZ));
            zIdx = max(1, min(size(M0,3), zIdx));
            M = M0(:,:,zIdx);
        end
        return;
    end

    while ndims(M0) > 3
        M0 = any(M0, ndims(M0));
    end

    if ismatrix(M0)
        M = fitBundleMaskToCurrentScm(M0);
    else
        M = fitBundleMaskToCurrentScm(M0);
    end
end

function [a,b] = parseRangeSafe(s, da, db)
    if nargin < 2, da = 0; end
    if nargin < 3, db = da; end
    s = strrep(char(s), '–', '-');
    v = sscanf(s, '%f-%f');
    if numel(v) ~= 2 || any(~isfinite(v))
        a = da;
        b = db;
    else
        a = v(1);
        b = v(2);
    end
end

function out = clamp(x, lo, hi)
    out = min(max(x, lo), hi);
end

function M = deriveMaskFromUnderlay(bgIn, ny, nx, nz, nt)
    M = [];

    if isempty(bgIn) || ~(isnumeric(bgIn) || islogical(bgIn))
        return;
    end

    V = [];
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
    catch
        return;
    end

    V = V(1:min(ny,size(V,1)), 1:min(nx,size(V,2)), 1:min(nz,size(V,3)));
    if size(V,1) < ny, V(end+1:ny,:,:) = 0; end
    if size(V,2) < nx, V(:,end+1:nx,:) = 0; end
    if size(V,3) < nz, V(:,:,end+1:nz) = 0; end

    fracZero = mean(V(:) == 0);
    if ~isfinite(fracZero) || fracZero < 0.02
        M = [];
        return;
    end

    M = (V ~= 0);

    try
        for zz = 1:size(M,3)
            M(:,:,zz) = imfill(M(:,:,zz), 'holes');
        end
    catch
    end

    M = logical(M);
end

function M2 = collapseMaskForSlice(M0, ny, nx, z, nZ_)
    if isempty(M0)
        M2 = true(ny, nx);
        return;
    end
    M0 = logical(M0);

    if ndims(M0) == 2
        M2 = M0;
    elseif ndims(M0) == 3
        if nZ_ > 1 && size(M0,3) == nZ_
            z = max(1, min(size(M0,3), z));
            M2 = M0(:,:,z);
        else
            M2 = any(M0, 3);
        end
    else
        tmp = M0;
        while ndims(tmp) > 3
            tmp = any(tmp, ndims(tmp));
        end
        if ndims(tmp) == 3 && nZ_ > 1 && size(tmp,3) == nZ_
            z = max(1, min(size(tmp,3), z));
            M2 = tmp(:,:,z);
        else
            while ndims(tmp) > 2
                tmp = any(tmp, ndims(tmp));
            end
            M2 = tmp;
        end
    end

    M2 = M2(1:min(ny,size(M2,1)), 1:min(nx,size(M2,2)));
    if size(M2,1) < ny, M2(end+1:ny,:) = false; end
    if size(M2,2) < nx, M2(:,end+1:nx) = false; end
end

function [M, maskIsInclude, pickedField] = readMask(f, mode)
    if nargin < 2 || isempty(mode)
        mode = 'overlayPreferred';
    end

    if ~exist(f, 'file')
        error('Mask file not found: %s', f);
    end

    maskIsInclude = true;
    pickedField = '';

    isNiiGz = (numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz'));

    if isNiiGz
        tmpDir = tempname;
        mkdir(tmpDir);
        gunzip(f, tmpDir);
        ddd = dir(fullfile(tmpDir, '*.nii'));
        if isempty(ddd)
            error('Failed to gunzip .nii.gz mask.');
        end
        niiFile = fullfile(tmpDir, ddd(1).name);
        M = niftiread(niiFile);
        try
            rmdir(tmpDir, 's');
        catch
        end
        M = logical(M);
        pickedField = 'nifti';
        return;
    end

    [~,~,e] = fileparts(f);

    if strcmpi(e, '.mat')
        S = load(f);

        if isfield(S, 'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle)
            B = S.maskBundle;
        else
            B = S;
        end

        switch lower(mode)
            case 'overlaypreferred'
                searchFields = { ...
                    'loadedMask', ...
                    'overlayMask', ...
                    'signalMask', ...
                    'mask', ...
                    'activeMask', ...
                    'brainMask', ...
                    'underlayMask', ...
                    'M'};
            case 'brainpreferred'
                searchFields = { ...
                    'brainMask', ...
                    'underlayMask', ...
                    'mask', ...
                    'activeMask', ...
                    'overlayMask', ...
                    'signalMask', ...
                    'loadedMask', ...
                    'M'};
            otherwise
                searchFields = { ...
                    'loadedMask', ...
                    'overlayMask', ...
                    'signalMask', ...
                    'mask', ...
                    'activeMask', ...
                    'brainMask', ...
                    'underlayMask', ...
                    'M'};
        end

        M = [];
        pickedField = '';

        for k = 1:numel(searchFields)
            fn = searchFields{k};
            if isfield(B, fn) && ~isempty(B.(fn))
                v = B.(fn);
                if isnumeric(v) || islogical(v)
                    M = logical(v);
                    pickedField = fn;
                    break;
                end
            end
        end

        if isempty(M)
            if isfield(B, 'brainImage') && ~isempty(B.brainImage)
                M = logical(B.brainImage > 0);
                pickedField = 'brainImage>0';
            else
                fn = fieldnames(B);
                for k = 1:numel(fn)
                    v = B.(fn{k});
                    if isnumeric(v) || islogical(v)
                        M = logical(v);
                        pickedField = fn{k};
                        break;
                    end
                end
            end
        end

        if isempty(M)
            error('MAT mask file has no usable mask variable.');
        end

        switch lower(pickedField)
            case 'loadedmask'
                if isfield(B, 'loadedMaskIsInclude') && ~isempty(B.loadedMaskIsInclude)
                    maskIsInclude = logical(B.loadedMaskIsInclude);
                elseif isfield(B, 'maskIsInclude') && ~isempty(B.maskIsInclude)
                    maskIsInclude = logical(B.maskIsInclude);
                else
                    maskIsInclude = true;
                end

            case {'overlaymask','signalmask'}
                if isfield(B, 'overlayMaskIsInclude') && ~isempty(B.overlayMaskIsInclude)
                    maskIsInclude = logical(B.overlayMaskIsInclude);
                elseif isfield(B, 'loadedMaskIsInclude') && ~isempty(B.loadedMaskIsInclude)
                    maskIsInclude = logical(B.loadedMaskIsInclude);
                elseif isfield(B, 'maskIsInclude') && ~isempty(B.maskIsInclude)
                    maskIsInclude = logical(B.maskIsInclude);
                else
                    maskIsInclude = true;
                end

            otherwise
                if isfield(B, 'maskIsInclude') && ~isempty(B.maskIsInclude)
                    maskIsInclude = logical(B.maskIsInclude);
                elseif isfield(B, 'loadedMaskIsInclude') && ~isempty(B.loadedMaskIsInclude)
                    maskIsInclude = logical(B.loadedMaskIsInclude);
                else
                    maskIsInclude = true;
                end
        end

        return;
    end

    M = niftiread(f);
    M = logical(M);
    maskIsInclude = true;
    pickedField = 'nifti';
end

function rgb = toRGB(im01)
    im = double(im01);
    im(~isfinite(im)) = 0;
    im = min(max(im, 0), 1);
    idx = uint8(round(im*255));
    rgb = ind2rgb(idx, gray(256));
end

function out = smooth2D_gauss(in, sigma)
    try
        out = imgaussfilt(in, sigma);
        return;
    catch
    end

    if sigma <= 0
        out = in;
        return;
    end

    r = max(1, ceil(3*sigma));
    x = -r:r;
    g = exp(-(x.^2)/(2*sigma^2));
    g = g / sum(g);
    out = conv2(conv2(in, g, 'same'), g', 'same');
end

function U = mat2gray_safe(U)
    mn = min(U(:));
    mx = max(U(:));
    if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
        U(:) = 0;
        return;
    end
    U = (U-mn)/(mx-mn);
    U = min(max(U, 0), 1);
end

function U = clip01_percentile(A, pLow, pHigh)
    v = A(:);
    v = v(isfinite(v));
    if isempty(v)
        U = zeros(size(A));
        return;
    end
    lo = prctile_fallback(v, pLow);
    hi = prctile_fallback(v, pHigh);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        U = mat2gray_safe(A);
        return;
    end
    U = A;
    U(U < lo) = lo;
    U(U > hi) = hi;
    U = (U-lo) / max(eps, (hi-lo));
    U = min(max(U, 0), 1);
end

function q = prctile_fallback(v, p)
    try
        q = prctile(v, p);
        return;
    catch
    end
    v = sort(v(:));
    n = numel(v);
    if n == 0
        q = 0;
        return;
    end
    k = 1 + (n-1)*(p/100);
    k1 = floor(k);
    k2 = ceil(k);
    k1 = max(1, min(n, k1));
    k2 = max(1, min(n, k2));
    if k1 == k2
        q = v(k1);
    else
        q = v(k1) + (k-k1)*(v(k2)-v(k1));
    end
end

function P = getSimpleExportPaths()
    root = '';

    try
        if isstruct(par)
            if isfield(par, 'exportPath') && ~isempty(par.exportPath) && exist(char(par.exportPath), 'dir') == 7
                root = char(par.exportPath);
            elseif isfield(par, 'loadedPath') && ~isempty(par.loadedPath) && exist(char(par.loadedPath), 'dir') == 7
                root = char(par.loadedPath);
            elseif isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf, 'file') == 2
                    root = fileparts(lf);
                end
            end
        end
    catch
        root = '';
    end

    if isempty(root)
        root = pwd;
    end

    root = guessAnalysedRoot(root);

    P = struct();
    P.root         = root;
    P.roiDir       = fullfile(root, 'ROI');
    P.scmRootDir   = fullfile(root, 'SCM');
    P.scmImageDir  = fullfile(P.scmRootDir, 'Images');
    P.scmSeriesDir = fullfile(P.scmRootDir, 'Series');
    P.scmTcDir     = fullfile(P.scmRootDir, 'Timecourse');

    P.fileStem = sanitizeName(getAnimalID(fileLabel));
    if isempty(P.fileStem)
        P.fileStem = 'SCM';
    end
end

function tag = askExportLabel(defaultTag, dlgTitle)
    if nargin < 1 || isempty(defaultTag)
        defaultTag = 'Target';
    end
    if nargin < 2 || isempty(dlgTitle)
        dlgTitle = 'Export label';
    end

    choice = questdlg( ...
        'How should this export be labeled?', ...
        dlgTitle, ...
        'Target', 'Control', 'Custom', defaultTag);

    if isempty(choice)
        tag = '';
        return;
    end

    switch lower(choice)
        case 'target'
            tag = 'Target';
        case 'control'
            tag = 'Ctrl';
        otherwise
            a = inputdlg( ...
                {'Enter label (for example Target, Ctrl, Hipp, Cortex):'}, ...
                dlgTitle, 1, {defaultTag});
            if isempty(a)
                tag = '';
                return;
            end
            tag = a{1};
    end

    tag = sanitizeExportTag(tag);
end

function tag = sanitizeExportTag(s)
    if isstring(s), s = char(s); end
    s = strtrim(char(s));

    if isempty(s)
        s = 'Target';
    end

    s = regexprep(s, '[^\w\-]+', '_');
    s = regexprep(s, '_+', '_');
    s = regexprep(s, '^_+|_+$', '');

    if isempty(s)
        s = 'Target';
    end

    tag = s;
end

function s = getStr(h)
    try
        s = get(h, 'String');
    catch
        s = '';
        return;
    end

    if iscell(s)
        if isempty(s)
            s = '';
        else
            s = s{1};
        end
    end
    if isstring(s)
        if numel(s) > 1
            s = s(1);
        end
        s = char(s);
    end
    if isnumeric(s)
        s = num2str(s);
    end
    s = char(s);
end

end