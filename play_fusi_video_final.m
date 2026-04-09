function fig = play_fusi_video_final( ...
    I, I_interp, PSC, bg, par, fps, maxFPS, TR, Tmax, baseline, ...
    loadedMask, loadedMaskIsInclude, nVols, applyRejection, QC, fileLabel, sliceIdx)

% =========================================================
% fUSI Video GUI (MATLAB 2023b)
% GUI-cleaned version
% ASCII only
% =========================================================

disp('fps ='); disp(fps);
disp('maxFPS ='); disp(maxFPS);

% ---- defaults ----
if ~isfield(par,'interpol') || isempty(par.interpol) || ~isfinite(par.interpol) || par.interpol < 1
    par.interpol = 1;
end

if isempty(I_interp)
    I_interp = I;
end

% Keep robust fallback if missing
if ~isfield(par,'previewCaxis') || isempty(par.previewCaxis)
    tmp = PSC(:);
    tmp = tmp(isfinite(tmp));
    if isempty(tmp)
        par.previewCaxis = [-5 5];
    else
        low  = prctile_fallback(tmp, 1);
        high = prctile_fallback(tmp, 99);
        if ~isfinite(low) || ~isfinite(high) || high <= low
            par.previewCaxis = [-5 5];
        else
            par.previewCaxis = [low high];
        end
    end
end

% Requested overlay start range
par.previewCaxis = [0 100];

% ---------------- DIMENSIONS (PSC) ----------------
bgDefaultFull = bg;
ndPSC = ndims(PSC);

switch ndPSC
    case 4
        [ny, nx, nZ, nFrames] = size(PSC);
    case 3
        [ny, nx, nFrames] = size(PSC);
        nZ = 1;
    case 2
        [ny, nx] = size(PSC);
        nZ = 1;
        nFrames = 1;
    otherwise
        error('PSC must be 2D, 3D or 4D.');
end

if nargin < 17 || isempty(sliceIdx) || ~isfinite(sliceIdx)
    if nZ > 1
        sliceIdx = round(nZ/2);
    else
        sliceIdx = 1;
    end
end
sliceIdx = max(1, min(nZ, round(sliceIdx)));

% =========================================================
% UNDERLAY STATE
% =========================================================
underSrc = 1;
underSrcLabel = 'Default(bg)';
bgMeanFull   = [];
bgMedianFull = [];
bgFileFull   = [];

% native/original snapshots (used by atlas warp + reset)
origI             = I;
origI_interp      = I_interp;
origPSC           = PSC;
origBgDefaultFull = bgDefaultFull;

% atlas state (SCM-style)
state = struct();
state.isAtlasWarped      = false;
state.atlasTransformFile = '';
state.lastAtlasTransformFile = '';
state.isColorUnderlay = false;
if (nZ == 1) && ndims(bgDefaultFull) == 3 && size(bgDefaultFull,3) == 3
    state.isColorUnderlay = true;   % true RGB image for single-slice data
elseif ndims(bgDefaultFull) == 4 && size(bgDefaultFull,3) == 3
    state.isColorUnderlay = true;   % RGB stack [Y X 3 Z]
end
state.regionLabelUnderlay = [];
state.regionColorLUT      = [];
state.regionInfo          = struct();

uState.mode       = 3;
uState.brightness = -0.04;
uState.contrast   = 1.10;
uState.gamma      = 0.95;

MAX_CONSIZE = 300;
MAX_CONLEV  = 500;
uState.conectSize = 18;
uState.conectLev  = 35;

% =========================================================
% OVERLAY STATE
% =========================================================
Nc = 256;
cmapNames = { ...
    'blackbdy_iso', ...
    'hot','parula','turbo','jet','gray','bone','copper','pink', ...
    'viridis','plasma','magma','inferno'};

overlayCmapName = 'blackbdy_iso';
mapA = getCmap(overlayCmapName, Nc);

[tmpThrMin, tmpThrMax] = getSuggestedThresholdRange(PSC, par.previewCaxis);
tmpThrMin = 0;
tmpThrMax = 100;

alphaModEnable = true;
alphaPct  = 100;
modMinAbs = 20;
modMaxAbs = 30;      % <- change from 100 to 30

maskThreshold = 0;

overlaySmoothSigma = 1.0;   % <- change from 0 to 1.0
overlaySmoothMax   = 5;

% =========================================================
% MASK STATE
% =========================================================
mask = false(ny, nx, nZ, nVols);
maskIsInclude = true;
statusLine = '';

if exist('loadedMask','var') && ~isempty(loadedMask)
    try
        [mask, maskIsInclude, bgDefaultFull, statusLine] = normalizeMaskInputForVideo( ...
            loadedMask, loadedMaskIsInclude, bgDefaultFull, ...
            ny, nx, nZ, nVols, sliceIdx);
    catch ME
        mask = false(ny, nx, nZ, nVols);
        maskIsInclude = true;
        statusLine = ['Initial mask load failed: ' ME.message];
    end
end
origMask = mask;
origMaskIsInclude = maskIsInclude;
origBgDefaultFull = bgDefaultFull;

if ndims(bgDefaultFull) == 3 && size(bgDefaultFull,3) == 3
    state.isColorUnderlay = true;
end
volume  = 1;
frame   = 1;
playing = false;

applyToAllFrames = true;
editorMode = false;
viewMaskedOnly = false;

brushRadius = 12;
maskAlpha   = 0.35;
maskColor   = [1 1 1];

fillWindowR     = 18;
fillSigmaFactor = 1.8;
fillMaxPixels   = 300000;

mouseIsDown = false;
paintMode   = '';
lastMouseXY = [NaN NaN];

% =========================================================
% FIGURE
% =========================================================
scr = get(0,'ScreenSize');
figW = min(max(1720, round(scr(3)*0.93)), scr(3)-40);
figH = min(max(980,  round(scr(4)*0.90)), scr(4)-80);
x0 = max(20, round((scr(3)-figW)/2));
y0 = max(40, round((scr(4)-figH)/2));

fig = figure('Color','k', ...
    'Position',[x0 y0 figW figH], ...
    'Name','fUSI Video Analysis', ...
    'NumberTitle','off', ...
    'MenuBar','none', ...
    'ToolBar','none');

set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',13);
set(fig,'CloseRequestFcn',@onCloseVideo);

try
    delete(findall(fig,'Type','ColorBar'));
catch
end

% =========================================================
% MAIN AXES + COLORBAR
% =========================================================
ax = axes('Parent',fig,'Units','pixels');
axis(ax,'off','image');
img = image(ax, zeros(ny, nx, 3, 'single'));
set(ax,'HitTest','on');
set(img,'HitTest','off');

txtSliceAx = text(ax, 0.99, 0.02, '', ...
    'Units','normalized', ...
    'Color',[0.80 0.90 1.00], ...
    'FontSize',13, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'VerticalAlignment','bottom', ...
    'Interpreter','none');

txtSliceTop = uicontrol(fig,'Style','text','Units','pixels', ...
    'String', sliceString(sliceIdx,nZ), ...
    'ForegroundColor',[0.85 0.90 1.00], ...
    'BackgroundColor','k', ...
    'FontSize',13,'FontWeight','bold', ...
    'HorizontalAlignment','left');

txtTitle = uicontrol(fig,'Style','text','Units','pixels', ...
    'String', safeStr(fileLabel), ...
    'ForegroundColor',[0.95 0.95 0.95], ...
    'BackgroundColor','k', ...
    'FontSize',15,'FontWeight','bold', ...
    'HorizontalAlignment','center');

info = uicontrol(fig,'Style','text','Units','pixels', ...
    'ForegroundColor','w', ...
    'BackgroundColor','k', ...
    'FontName','Courier New', ...
    'FontSize',13, ...
    'HorizontalAlignment','left');

try
    colormap(ax, mapA);
catch
end
caxis(ax, par.previewCaxis);
cbar = colorbar(ax);
set(cbar,'Color','w','FontSize',12);
cbar.Label.String = '';   % remove vertical label
set(cbar,'Limits',par.previewCaxis);

title(cbar,'Change (%)', ...
    'Color','w', ...
    'FontSize',11, ...
    'FontWeight','bold');

btnColorbarRange = uicontrol(fig,'Style','pushbutton','Units','pixels', ...
    'String','Color Bar Range', ...
    'FontWeight','bold', ...
    'FontSize',12, ...
    'Callback',@setColorbarRange);

footer = uicontrol(fig,'Style','text','Units','pixels', ...
    'String','fUSI Video Analysis - HUMoR Analysis Tool - MPI Biological Cybernetics', ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',11);

% =========================================================
% RIGHT PANEL WITH TABS
% =========================================================
uiFontName = 'Arial';
uiFontSize = 13;

rightM = 28;
panelW = 570;

btnW  = 150;
btnH  = 48;
gapX  = 14;
gapY  = 14;

row1Y = 20;
row2Y = row1Y + btnH + gapY;

topM = 20;

controlsPanel = uipanel('Parent',fig,'Title','Controls', ...
    'Units','pixels', ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontSize',15,'FontWeight','bold', ...
    'BorderType','line', ...
    'HighlightColor',[0.65 0.65 0.65], ...
    'ShadowColor',[0.65 0.65 0.65]);

tabBarH = 34;

tabBar = uipanel('Parent',controlsPanel,'Units','pixels', ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'BorderType','none');

contentFrame = uipanel('Parent',controlsPanel,'Units','pixels', ...
    'BackgroundColor',[0.08 0.08 0.08], ...
    'BorderType','line', ...
    'HighlightColor',[0.70 0.70 0.70], ...
    'ShadowColor',[0.70 0.70 0.70]);

btnTabVideo = uicontrol(tabBar,'Style','togglebutton','String','Video / Mask', ...
    'Units','pixels', ...
    'Callback',@(~,~)switchTab('video'), ...
    'BackgroundColor',[0.18 0.18 0.18], ...
    'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Value',1);

btnTabUnder = uicontrol(tabBar,'Style','togglebutton','String','Underlay', ...
    'Units','pixels', ...
    'Callback',@(~,~)switchTab('underlay'), ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Value',0);

btnTabOverlay = uicontrol(tabBar,'Style','togglebutton','String','Overlay', ...
    'Units','pixels', ...
    'Callback',@(~,~)switchTab('overlay'), ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Value',0);

pVideo = uipanel('Parent',contentFrame,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.08 0.08 0.08], 'Visible','on');
pUnder = uipanel('Parent',contentFrame,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.08 0.08 0.08], 'Visible','off');
pOverlay = uipanel('Parent',contentFrame,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.08 0.08 0.08], 'Visible','off');

pad = 16;
rowHc = 38;
sliderH = 22;

mkLbl = @(pp,s) uicontrol(pp,'Style','text','String',s,'Units','pixels', ...
    'ForegroundColor','w','BackgroundColor',[0.08 0.08 0.08], ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkLblImp = @(pp,s) uicontrol(pp,'Style','text','String',s,'Units','pixels', ...
    'ForegroundColor',[1.00 0.60 0.60],'BackgroundColor',[0.08 0.08 0.08], ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkValBox = @(pp,s) uicontrol(pp,'Style','edit','String',s,'Units','pixels', ...
    'BackgroundColor',[0.18 0.18 0.18],'ForegroundColor','w', ...
    'HorizontalAlignment','center', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold', ...
    'Enable','inactive');

mkEdit = @(pp,s,cbk) uicontrol(pp,'Style','edit','String',s,'Units','pixels', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'HorizontalAlignment','center', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',cbk);

mkSlider = @(pp,minv,maxv,val,cbk) uicontrol(pp,'Style','slider','Units','pixels', ...
    'Min',minv,'Max',maxv,'Value',val,'Callback',cbk);

mkPopup = @(pp,choices,val,cbk) uicontrol(pp,'Style','popupmenu','String',choices,'Value',val, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

mkChk = @(pp,s,val,cbk) uicontrol(pp,'Style','checkbox','String',s,'Value',val, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',[0.08 0.08 0.08],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkBtn = @(pp,lbl,cbk,bgcol,fs) uicontrol(pp,'Style','pushbutton','String',lbl, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',bgcol,'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',fs,'FontWeight','bold');

% -----------------------------
% VIDEO / MASK TAB
% -----------------------------
lblFPS   = mkLbl(pVideo,'FPS');
slFPS    = mkSlider(pVideo,1,maxFPS,fps,@fpsSliderChanged);
txtFPS   = mkValBox(pVideo,sprintf('%d',fps));

lblVol   = mkLbl(pVideo,'Volume');
slVol    = mkSlider(pVideo,1,nVols,1,@volSliderChanged);
txtVol   = mkValBox(pVideo,sprintf('%d / %d',1,nVols));

lblEditor = mkLbl(pVideo,'Editor');
tglEditor = uicontrol(pVideo,'Style','togglebutton','String','Editor OFF', ...
    'Units','pixels','Callback',@toggleEditor, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold','Value',0);

lblView = mkLbl(pVideo,'View');
tglView = uicontrol(pVideo,'Style','togglebutton','String','VIEW: FULL', ...
    'Units','pixels','Callback',@toggleViewMasked, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold','Value',0);

popIncExc = mkPopup(pVideo,{'Include','Exclude'},1,@setIncludeExclude);

lblAuto = mkLbl(pVideo,'Frames');
tglApplyAll = uicontrol(pVideo,'Style','togglebutton','String','ALL FRAMES', ...
    'Units','pixels','Callback',@toggleApplyAll, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold','Value',1);

lblBrush = mkLbl(pVideo,'Brush radius (px)');
slBrush  = mkSlider(pVideo,1,60,brushRadius,@brushSliderChanged);
txtBrush = mkValBox(pVideo,sprintf('%d',brushRadius));

lblMaskA = mkLbl(pVideo,'Mask overlay alpha');
slMaskA  = mkSlider(pVideo,0,1,maskAlpha,@maskAlphaSliderChanged);
txtMaskA = mkValBox(pVideo,sprintf('%.2f',maskAlpha));

btnColor = mkBtn(pVideo,'Color...',@pickColor,[0.20 0.20 0.20],13);
btnFill  = mkBtn(pVideo,'Fill (F)',@fillRegion,[0.20 0.20 0.20],13);
btnClear = mkBtn(pVideo,'Clear mask',@clearMaskAll,[0.35 0.20 0.20],13);

btnApplyAllMask = mkBtn(pVideo,'Apply mask to all volumes (this slice)',@applyMaskToAllFrames,[0.20 0.45 0.25],13);
btnLoadMask = mkBtn(pVideo,'Load mask / bundle',@loadMaskBundleCB,[0.45 0.28 0.70],13);
btnSaveMask = mkBtn(pVideo,'Save mask (.mat)',@saveMaskMat,[0.10 0.35 0.95],13);
btnSaveInterp = mkBtn(pVideo,'Save interpolated data (.mat)',@saveInterpolatedMat,[0.15 0.65 0.55],13);

% -----------------------------
% UNDERLAY TAB
% -----------------------------
lblUSrc = mkLbl(pUnder,'Underlay source');
popUSrc = mkPopup(pUnder,{'1) Default(bg)','2) Mean(I)','3) Median(I) robust'},underSrc,@underSrcChanged);

lblUMode = mkLbl(pUnder,'Underlay mode');
popUMode = mkPopup(pUnder,{'1) Legacy(mat2gray)','2) Robust(1-99%)','3) Video robust(0.5-99.5%)','4) Vessel enhance'},uState.mode,@underModeChanged);

lblBri = mkLbl(pUnder,'Brightness');
slBri  = mkSlider(pUnder,-0.80,0.80,uState.brightness,@underSliderChanged);
txtBri = mkValBox(pUnder,sprintf('%.2f',uState.brightness));

lblCon = mkLbl(pUnder,'Contrast');
slCon  = mkSlider(pUnder,0.10,5.00,uState.contrast,@underSliderChanged);
txtCon = mkValBox(pUnder,sprintf('%.2f',uState.contrast));

lblGam = mkLbl(pUnder,'Gamma');
slGam  = mkSlider(pUnder,0.20,4.00,uState.gamma,@underSliderChanged);
txtGam = mkValBox(pUnder,sprintf('%.2f',uState.gamma));

lblVsz = mkLbl(pUnder,sprintf('Vessel conectSize (0-%d)',MAX_CONSIZE));
slVsz  = mkSlider(pUnder,0,MAX_CONSIZE,uState.conectSize,@underSliderChanged);
set(slVsz,'SliderStep',[1/max(1,MAX_CONSIZE) 10/max(1,MAX_CONSIZE)]);
txtVsz = mkValBox(pUnder,sprintf('%d',uState.conectSize));

lblVlv = mkLbl(pUnder,sprintf('Vessel conectLev (0-%d)',MAX_CONLEV));
slVlv  = mkSlider(pUnder,0,MAX_CONLEV,uState.conectLev,@underSliderChanged);
set(slVlv,'SliderStep',[1/max(1,MAX_CONLEV) 10/max(1,MAX_CONLEV)]);
txtVlv = mkValBox(pUnder,sprintf('%d',uState.conectLev));

btnLoadUnder   = mkBtn(pUnder,'LOAD NEW UNDERLAY',@loadNewUnderlayCB,[0.20 0.38 0.62],12);
btnLoadGAVideo = mkBtn(pUnder,'LOAD GA VIDEO BUNDLE',@loadGroupVideoBundleCB,[0.55 0.33 0.15],12);
btnWarpAtlas   = mkBtn(pUnder,'WARP FUNCTIONAL TO ATLAS',@warpFunctionalToAtlasCB,[0.20 0.38 0.62],12);
btnResetWarp   = mkBtn(pUnder,'RESET TO NATIVE',@resetWarpToNativeCB,[0.28 0.28 0.30],12);

% -----------------------------
% OVERLAY TAB
% -----------------------------
lblMap = mkLbl(pOverlay,'Colormap');
idxMap = find(strcmp(cmapNames,overlayCmapName),1,'first');
if isempty(idxMap), idxMap = 1; end
popMap = mkPopup(pOverlay,cmapNames,idxMap,@overlayMapChanged);

lblRange = mkLblImp(pOverlay,'Display range (min max)');
edRange  = mkEdit(pOverlay,sprintf('%.6g %.6g',par.previewCaxis(1),par.previewCaxis(2)),@overlayRangeApply);
btnRange = mkBtn(pOverlay,'Apply range',@overlayRangeApply,[0.25 0.40 0.65],13);

lblThr = mkLblImp(pOverlay,'Threshold abs (%)');
slThr  = mkSlider(pOverlay,0,100,maskThreshold,@overlayThrSliderChanged);
edThr  = mkEdit(pOverlay,sprintf('%.3g',maskThreshold),@overlayThrEditChanged);

lblAlpha = mkLbl(pOverlay,'Overlay alpha (%)');
slAlpha  = mkSlider(pOverlay,0,100,alphaPct,@overlayAlphaSliderChanged);
txtAlpha = mkValBox(pOverlay,sprintf('%.0f',alphaPct));

lblSmooth = mkLblImp(pOverlay,'Spatial smoothing sigma');
slSmooth  = mkSlider(pOverlay,0,overlaySmoothMax,overlaySmoothSigma,@overlaySmoothSliderChanged);
edSmooth  = mkEdit(pOverlay,sprintf('%.2f',overlaySmoothSigma),@overlaySmoothEditChanged);

lblAlphaMod = mkLblImp(pOverlay,'Alpha modulation');
chkAlphaMod = mkChk(pOverlay,'Alpha modulate by abs(PSC)',double(alphaModEnable),@overlayAlphaModToggle);

lblModMin = mkLblImp(pOverlay,'Mod Min (abs %)');
edModMin  = mkEdit(pOverlay,sprintf('%.3g',modMinAbs),@overlayModMinEdit);

lblModMax = mkLblImp(pOverlay,'Mod Max (abs %)');
edModMax  = mkEdit(pOverlay,sprintf('%.3g',modMaxAbs),@overlayModMaxEdit);

updateOverlayEnable();
updateUnderlayEnable();

if maskIsInclude
    set(popIncExc,'Value',1);
else
    set(popIncExc,'Value',2);
end

% ---------------------------------------------------------
% Bottom buttons
% ---------------------------------------------------------
helpBtn = uicontrol(fig,'Style','pushbutton','String','HELP', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.40 0.65],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@showHelpDialog);

closeBtn = uicontrol(fig,'Style','pushbutton','String','CLOSE', ...
    'Units','pixels', ...
    'BackgroundColor',[0.65 0.25 0.25],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@(s,e) close(fig));

scmBtn = uicontrol(fig,'Style','pushbutton','String','Open SCM', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.55 0.35],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@openSCM);

playBtn = uicontrol(fig,'Style','togglebutton','String','Play', ...
    'Units','pixels', ...
    'BackgroundColor',[0.20 0.45 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@playPause);

replayBtn = uicontrol(fig,'Style','pushbutton','String','Replay', ...
    'Units','pixels', ...
    'BackgroundColor',[0.35 0.35 0.35],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@replayVid);

saveMP4Btn = uicontrol(fig,'Style','pushbutton','String','Save MP4', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.40 0.65],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',13,'FontWeight','bold', ...
    'Callback',@saveVideo);

set(fig,'WindowButtonDownFcn',@mouseDown);
set(fig,'WindowButtonUpFcn',@mouseUp);
set(fig,'WindowButtonMotionFcn',@mouseMoveVideo);
set(fig,'KeyPressFcn',@keyPressHandler);
set(fig,'WindowScrollWheelFcn',@mouseScrollSlice);
set(fig,'ResizeFcn',@(~,~)layoutUI());

layoutUI();
render();

% =========================================================
% TIMER
% =========================================================
playTimer = timer('ExecutionMode','fixedSpacing', ...
    'Period',1/max(fps,0.1), 'TimerFcn',@timerTick);

    function timerTick(~,~)
        if ~ishandle(fig) || ~playing
            return;
        end

        volume = volume + 1;
        if volume > nVols
            volume = nVols;
            playing = false;
            if ishandle(playBtn)
                set(playBtn,'Value',0,'String','Play');
            end
            stop(playTimer);
            return;
        end

        set(slVol,'Value',volume);
        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));
        render();
    end

% =========================================================
% TAB SWITCH
% =========================================================
    function switchTab(which)
        which = lower(char(which));

        if strcmp(which,'video')
            set(pVideo,'Visible','on');
            set(pUnder,'Visible','off');
            set(pOverlay,'Visible','off');

            set(btnTabVideo,'Value',1,'BackgroundColor',[0.18 0.18 0.18]);
            set(btnTabUnder,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);
            set(btnTabOverlay,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);

        elseif strcmp(which,'underlay')
            set(pVideo,'Visible','off');
            set(pUnder,'Visible','on');
            set(pOverlay,'Visible','off');

            set(btnTabVideo,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);
            set(btnTabUnder,'Value',1,'BackgroundColor',[0.18 0.18 0.18]);
            set(btnTabOverlay,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);

        else
            set(pVideo,'Visible','off');
            set(pUnder,'Visible','off');
            set(pOverlay,'Visible','on');

            set(btnTabVideo,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);
            set(btnTabUnder,'Value',0,'BackgroundColor',[0.10 0.10 0.10]);
            set(btnTabOverlay,'Value',1,'BackgroundColor',[0.18 0.18 0.18]);
        end

        layoutUI();
    end

% =========================================================
% LAYOUT
% =========================================================
    function layoutUI()
        pos = get(fig,'Position');
        W = pos(3);
        H = pos(4);

        panelX = W - rightM - panelW;

        buttonsBlockH = 2*btnH + gapY;
        panelY = buttonsBlockH + 26;
        panelH = max(430, H - panelY - topM);

        set(controlsPanel,'Position',[panelX panelY panelW panelH]);

        totalBtnW = 3*btnW + 2*gapX;
        btnX0 = panelX + round((panelW - totalBtnW)/2);

        set(helpBtn,  'Position',[btnX0 row2Y btnW btnH]);
        set(closeBtn, 'Position',[btnX0 + (btnW+gapX) row2Y btnW btnH]);
        set(scmBtn,   'Position',[btnX0 + 2*(btnW+gapX) row2Y btnW btnH]);

        set(playBtn,   'Position',[btnX0 row1Y btnW btnH]);
        set(replayBtn, 'Position',[btnX0 + (btnW+gapX) row1Y btnW btnH]);
        set(saveMP4Btn,'Position',[btnX0 + 2*(btnW+gapX) row1Y btnW btnH]);

       set(tabBar,'Position',[12 panelH-tabBarH-26 panelW-24 tabBarH+8]);

contentFrameY = 10;
contentFrameH = panelH - tabBarH - 32;
set(contentFrame,'Position',[10 contentFrameY panelW-20 contentFrameH]);

        btnWTab = floor((panelW-24-16)/3);
        set(btnTabVideo,  'Position',[2 6 btnWTab-2 tabBarH]);
        set(btnTabUnder,  'Position',[2+btnWTab+8 6 btnWTab-2 tabBarH]);
        set(btnTabOverlay,'Position',[2+2*(btnWTab+8) 6 btnWTab-2 tabBarH]);

        contentW = panelW - 36;
        contentH = contentFrameH - 16;

        set(pVideo,  'Position',[8 8 contentW contentH]);
        set(pUnder,  'Position',[8 8 contentW contentH]);
        set(pOverlay,'Position',[8 8 contentW contentH]);

        layoutVideoTab(contentW, contentH);
        layoutUnderTab(contentW, contentH);
        layoutOverlayTab(contentW, contentH);

        leftM = 120;
        gapToPanel = 42;
        axW = max(540, panelX - gapToPanel - leftM);
        axH = max(450, H - 230);
        axY = 92;
        axX = leftM;

        set(ax,'Position',[axX axY axW axH]);
        set(txtTitle,'Position',[axX axY+axH+10 axW 28]);

        set(info,'Position',[20 H-92 panelX-40 70]);
        set(txtSliceTop,'Position',[20 H-120 320 24]);

        cbarW = 18;
       cbarX = max(36, axX-58);
        cbarY = axY + 40;
        cbarH = max(240, axH - 80);
        set(cbar,'Units','pixels','Position',[cbarX cbarY cbarW cbarH]);

        set(btnColorbarRange,'Position',[cbarX-14 axY-44 146 34]);
        set(footer,'Position',[10 8 min(1200,W-20) 22]);
    end

    function gap = adaptiveGap(h, fixedHeights, nGaps, baseGap, maxAdd)
        extra = h - (fixedHeights + nGaps*baseGap);
        if extra <= 0
            gap = baseGap;
            return;
        end
        add = floor(extra / max(1,nGaps));
        add = min(maxAdd, add);
        gap = baseGap + add;
    end

    function layoutVideoTab(w, h)
        xLabel = pad;
        wLabel = 210;
        xCtrl  = xLabel + wLabel + 14;
        xVal   = w - pad - 116;
        wVal   = 116;
        wCtrl  = max(140, xVal - xCtrl - 12);

        fixed = 0;
        fixed = fixed + 2*rowHc;
        fixed = fixed + 3*rowHc;
        fixed = fixed + 2*rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + 36;
        fixed = fixed + 3*36;

        nGaps = 10;
        gapc = adaptiveGap(h, fixed, nGaps, 10, 14);
        gapBig = gapc + 8;

        y0 = h - 52;

        set(lblFPS,'Position',[xLabel y0 wLabel rowHc]);
        set(slFPS,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtFPS,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblVol,'Position',[xLabel y0 wLabel rowHc]);
        set(slVol,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtVol,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapBig);

        set(lblEditor,'Position',[xLabel y0 wLabel rowHc]);
        set(tglEditor,'Position',[xCtrl y0 wCtrl+wVal+12 rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblView,'Position',[xLabel y0 wLabel rowHc]);
        halfW = floor((wCtrl+wVal+12)/2)-6;
        set(tglView,'Position',[xCtrl y0 halfW rowHc]);
        set(popIncExc,'Position',[xCtrl+halfW+12 y0 halfW rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblAuto,'Position',[xLabel y0 wLabel rowHc]);
        set(tglApplyAll,'Position',[xCtrl y0 wCtrl+wVal+12 rowHc]);
        y0 = y0 - (rowHc + gapBig);

        set(lblBrush,'Position',[xLabel y0 wLabel rowHc]);
        set(slBrush,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtBrush,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblMaskA,'Position',[xLabel y0 wLabel rowHc]);
        set(slMaskA,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtMaskA,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapBig);

        bw = floor((w-2*pad-20)/3);
        set(btnColor,'Position',[xLabel y0 bw 36]);
        set(btnFill,'Position',[xLabel+bw+10 y0 bw 36]);
        set(btnClear,'Position',[xLabel+2*(bw+10) y0 bw 36]);
        y0 = y0 - (36 + gapc);

        set(btnApplyAllMask,'Position',[xLabel y0 (w-2*pad) 36]);
        y0 = y0 - (36 + gapc);

        set(btnLoadMask,'Position',[xLabel y0 (w-2*pad) 36]);
        y0 = y0 - (36 + gapc);

        set(btnSaveMask,'Position',[xLabel y0 (w-2*pad) 36]);
        y0 = y0 - (36 + gapc);

        set(btnSaveInterp,'Position',[xLabel y0 (w-2*pad) 36]);
    end

   function layoutUnderTab(w, h)
    xLabel = pad;
    wLabel = 230;
    xCtrl  = xLabel + wLabel + 14;
    xVal   = w - pad - 116;
    wVal   = 116;
    wCtrl  = max(140, xVal - xCtrl - 12);

    fixed = 0;
    fixed = fixed + 2*rowHc;
    fixed = fixed + 3*rowHc;
    fixed = fixed + 2*rowHc;
    fixed = fixed + 4*36;   % 4 buttons now

    nGaps = 11;
    gapc = adaptiveGap(h, fixed, nGaps, 10, 14);
    gapBig = gapc + 8;

    y0 = h - 52;

    set(lblUSrc,'Position',[xLabel y0 wLabel rowHc]);
    set(popUSrc,'Position',[xCtrl y0 (wCtrl+wVal+12) rowHc]);
    y0 = y0 - (rowHc + gapc);

    set(lblUMode,'Position',[xLabel y0 wLabel rowHc]);
    set(popUMode,'Position',[xCtrl y0 (wCtrl+wVal+12) rowHc]);
    y0 = y0 - (rowHc + gapBig);

    set(lblBri,'Position',[xLabel y0 wLabel rowHc]);
    set(slBri,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
    set(txtBri,'Position',[xVal y0 wVal rowHc]);
    y0 = y0 - (rowHc + gapc);

    set(lblCon,'Position',[xLabel y0 wLabel rowHc]);
    set(slCon,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
    set(txtCon,'Position',[xVal y0 wVal rowHc]);
    y0 = y0 - (rowHc + gapc);

    set(lblGam,'Position',[xLabel y0 wLabel rowHc]);
    set(slGam,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
    set(txtGam,'Position',[xVal y0 wVal rowHc]);
    y0 = y0 - (rowHc + gapBig);

    set(lblVsz,'Position',[xLabel y0 wLabel rowHc]);
    set(slVsz,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
    set(txtVsz,'Position',[xVal y0 wVal rowHc]);
    y0 = y0 - (rowHc + gapc);

    set(lblVlv,'Position',[xLabel y0 wLabel rowHc]);
    set(slVlv,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
    set(txtVlv,'Position',[xVal y0 wVal rowHc]);
    y0 = y0 - (rowHc + gapBig);

    set(btnLoadUnder,'Position',[xLabel y0 (w-2*pad) 36]);
    y0 = y0 - (36 + gapc);

    set(btnLoadGAVideo,'Position',[xLabel y0 (w-2*pad) 36]);
    y0 = y0 - (36 + gapc);

    set(btnWarpAtlas,'Position',[xLabel y0 (w-2*pad) 36]);
    y0 = y0 - (36 + gapc);

    set(btnResetWarp,'Position',[xLabel y0 (w-2*pad) 36]);

    updateUnderlayEnable();
   end

    function layoutOverlayTab(w, h)
        xLabel = pad;
        wLabel = 230;
        xCtrl  = xLabel + wLabel + 14;
        xVal   = w - pad - 116;
        wVal   = 116;
        wCtrl  = max(140, xVal - xCtrl - 12);

        fixed = 0;
        fixed = fixed + rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + rowHc;
        fixed = fixed + 2*rowHc;

        nGaps = 8;
        gapc = adaptiveGap(h, fixed, nGaps, 10, 14);
        gapBig = gapc + 8;

        y0 = h - 52;

        set(lblMap,'Position',[xLabel y0 wLabel rowHc]);
        set(popMap,'Position',[xCtrl y0 (wCtrl+wVal+12) rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblRange,'Position',[xLabel y0 wLabel rowHc]);
        set(edRange,'Position',[xCtrl y0 floor((wCtrl+wVal+12)*0.62) rowHc]);
        set(btnRange,'Position',[xCtrl+floor((wCtrl+wVal+12)*0.62)+10 y0 floor((wCtrl+wVal+12)*0.38)-10 rowHc]);
        y0 = y0 - (rowHc + gapBig);

        set(lblThr,'Position',[xLabel y0 wLabel rowHc]);
        set(slThr,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(edThr,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblAlpha,'Position',[xLabel y0 wLabel rowHc]);
        set(slAlpha,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtAlpha,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblSmooth,'Position',[xLabel y0 wLabel rowHc]);
        set(slSmooth,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(edSmooth,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapBig);

        set(lblAlphaMod,'Position',[xLabel y0 wLabel rowHc]);
        set(chkAlphaMod,'Position',[xCtrl y0 (wCtrl+wVal+12) rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblModMin,'Position',[xLabel y0 wLabel rowHc]);
        set(edModMin,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblModMax,'Position',[xLabel y0 wLabel rowHc]);
        set(edModMax,'Position',[xVal y0 wVal rowHc]);

        updateOverlayEnable();
    end

% =========================================================
% RENDER
% =========================================================
    function render()
        sliceIdx = max(1, min(nZ, sliceIdx));
        set(txtSliceTop,'String',sliceString(sliceIdx,nZ));

     bgFullActive = getUnderlayFull();
bg2 = getBg2DForSlice(bgFullActive, sliceIdx);
bgRGB = renderUnderlayRGB(bg2);

        if frame < 1 || frame > nFrames
    syncImageAxesToCurrentFrame(bgRGB);
    return;
end

        if ndPSC == 4
            A = squeeze(PSC(:,:,sliceIdx, frame));
        elseif ndPSC == 3
            A = PSC(:,:,frame);
        else
            A = PSC;
        end
        A = double(A);
        A(~isfinite(A)) = 0;
        if size(bgRGB,1) ~= size(A,1) || size(bgRGB,2) ~= size(A,2)
    bgRGB = forceRgbToSize(bgRGB, size(A,1), size(A,2));
end

        if overlaySmoothSigma > 0
            filtSize = max(3, 2*ceil(2*overlaySmoothSigma)+1);
            try
                if exist('imgaussfilt','file')
                    A = imgaussfilt(A, overlaySmoothSigma, ...
                        'FilterSize', filtSize, ...
                        'Padding', 'replicate');
                else
                    h = fspecial('gaussian', [filtSize filtSize], overlaySmoothSigma);
                    A = imfilter(A, h, 'replicate');
                end
            catch
            end
        end

        cax = par.previewCaxis;
        if numel(cax) ~= 2 || ~isfinite(cax(1)) || ~isfinite(cax(2)) || diff(cax) <= 0
            cax = [0 100];
            par.previewCaxis = cax;
        end
        try
            set(cbar,'Limits',cax);
        catch
        end

        A_scaled = (A - cax(1)) ./ (cax(2) - cax(1) + eps);
        A_scaled = max(0, min(1, A_scaled));
        pscRGB = ind2rgb(uint8(A_scaled * (Nc-1)), mapA);

       M = squeeze(mask(:,:,sliceIdx, volume));
M = logical(M);

if size(M,1) ~= size(A,1) || size(M,2) ~= size(A,2)
    M = resizeLogical2D(M, size(A,1), size(A,2));
end

        if any(M(:))
            if maskIsInclude
                showMask = M;
            else
                showMask = ~M;
            end
            baseMaskOverlay = double(showMask);
        else
            showMask = true(size(M));
            baseMaskOverlay = 1;
        end

        if viewMaskedOnly && any(M(:))
            dimFactor = 0.12;
            show3 = repmat(showMask,[1 1 3]);
            bgRGB = bgRGB .* (show3 + dimFactor*(~show3));
        end

    thr = maskThreshold;
a   = max(0, min(100, alphaPct));

ov = A;
baseMask = double(baseMaskOverlay);

% SAME behavior as SCM_gui:
% only show positive values
showMask = (ov > 0);

% threshold only applied to positive values
thrMask = double((abs(ov) >= thr) & showMask);

if ~alphaModEnable
    alphaMap = (a/100) .* thrMask .* baseMask;
else
    effLo = max(modMinAbs, thr);
    effHi = modMaxAbs;

    ovAbsPos = abs(ov);
    ovAbsPos(~showMask) = NaN;

    if ~isfinite(effHi) || effHi <= effLo
        tmp = ovAbsPos(isfinite(ovAbsPos));
        if isempty(tmp)
            effHi = effLo + eps;
        else
            effHi = max(tmp);
        end
    end

    if ~isfinite(effHi) || effHi <= effLo
        effHi = effLo + eps;
    end

    modv = (abs(ov) - effLo) ./ max(eps, (effHi - effLo));
    modv(~isfinite(modv)) = 0;
    modv = min(max(modv,0),1);

    % never show non-positive values
    modv(~showMask) = 0;

    alphaMap = (a/100) .* modv .* thrMask .* baseMask;
end

alphaMap(~isfinite(alphaMap)) = 0;
alphaMap = min(max(alphaMap,0),1);

        a3 = repmat(alphaMap,[1 1 3]);
        baseRGB = (1-a3).*bgRGB + a3.*pscRGB;

        outRGB = baseRGB;

        if ~viewMaskedOnly && any(M(:))
            maskRGB = cat(3, ...
    ones(size(A,1), size(A,2)) * maskColor(1), ...
    ones(size(A,1), size(A,2)) * maskColor(2), ...
    ones(size(A,1), size(A,2)) * maskColor(3));
            M3 = repmat(M,[1 1 3]);
            alphaUse = maskAlpha;
            if editorMode
                alphaUse = max(0.6, maskAlpha);
            end
            outRGB = outRGB .* (1 - alphaUse .* M3) + maskRGB .* (alphaUse .* M3);
        end

   syncImageAxesToCurrentFrame(outRGB);

        t = (volume - 1) * TR;

        em = tern(editorMode,'ON','OFF');
        vm = tern(viewMaskedOnly,'MASKED','FULL');
        ms = tern(maskIsInclude,'Include','Exclude');
        alphaState = tern(alphaModEnable,'ON','OFF');

        modeStr = 'sec';
        if isstruct(baseline) && isfield(baseline,'mode') && ~isempty(baseline.mode)
            modeStr = char(baseline.mode);
        end

        extra = '';
        if ~isempty(statusLine)
            extra = [' | ' statusLine];
        end

        set(info,'String',sprintf([ ...
            't = %.1f / %.1f s | Vol %d / %d | View: %s (%s)\n' ...
            'Baseline: %g-%g %s | Editor: %s | Underlay: %s | Smooth=%.2f | AlphaMod: %s | alpha=%g%% min=%g max=%g thr=%g%s'], ...
            t, Tmax, volume, nVols, vm, ms, ...
            baseline.start, baseline.end, modeStr, ...
            em, underSrcLabel, overlaySmoothSigma, alphaState, alphaPct, modMinAbs, modMaxAbs, maskThreshold, extra));

        set(txtFPS,'String',sprintf('%d',fps));
        set(txtVol,'String',sprintf('%d / %d',volume,nVols));
        set(txtBrush,'String',sprintf('%d',brushRadius));
        set(txtMaskA,'String',sprintf('%.2f',maskAlpha));
        set(txtAlpha,'String',sprintf('%.0f',alphaPct));
        set(edThr,'String',sprintf('%.3g',maskThreshold));

        txtSliceAx.String = sliceString(sliceIdx, nZ);
    end

% =========================================================
% VIDEO TAB CALLBACKS
% =========================================================
   function loadGroupVideoBundleCB(~,~)
    startPath = getStartPath();

    [f,p] = uigetfile({'*.mat','GA group video bundle (*.mat)'}, ...
        'Select Group Analysis video export', startPath);

    if isequal(f,0)
        return;
    end

    fullf = fullfile(p,f);

    try
        S = load(fullf);
        E = extractGroupVideoBundleStruct(S);

        if ~isfield(E,'psc4D') || isempty(E.psc4D) || ...
                ~(isnumeric(E.psc4D) || islogical(E.psc4D))
            error('GA bundle has no usable psc4D field.');
        end

        if ~isfield(E,'functional4D') || isempty(E.functional4D) || ...
                ~(isnumeric(E.functional4D) || islogical(E.functional4D))
            error('GA bundle has no usable functional4D field.');
        end

        if isfield(E,'underlay2D') && ~isempty(E.underlay2D) && ...
                (isnumeric(E.underlay2D) || islogical(E.underlay2D))
            bgNew = double(E.underlay2D);
        elseif isfield(E,'groupMap2D') && ~isempty(E.groupMap2D) && ...
                (isnumeric(E.groupMap2D) || islogical(E.groupMap2D))
            bgNew = double(E.groupMap2D);
        else
            error('GA bundle has no usable underlay2D or groupMap2D field.');
        end

        % Stop playback first
        playing = false;
        if ishandle(playBtn)
            set(playBtn,'Value',0,'String','Play');
        end
        try
            if exist('playTimer','var') && isa(playTimer,'timer') && isvalid(playTimer)
                stop(playTimer);
            end
        catch
        end

        % Replace actual video data
        I        = double(E.functional4D);
        I_interp = double(E.functional4D);
        PSC      = double(E.psc4D);
        bgDefaultFull = double(bgNew);

        % Metadata
        if isfield(E,'TR') && ~isempty(E.TR) && isfinite(E.TR)
            TR = double(E.TR);
        end

        if ~isstruct(baseline) || isempty(baseline)
            baseline = struct();
        end
        if ~isfield(baseline,'start') || isempty(baseline.start), baseline.start = 0; end
        if ~isfield(baseline,'end')   || isempty(baseline.end),   baseline.end   = 0; end
        if ~isfield(baseline,'mode')  || isempty(baseline.mode),  baseline.mode  = 'sec'; end

        if isfield(E,'baseWindowSec') && numel(E.baseWindowSec) >= 2
            baseline.start = double(E.baseWindowSec(1));
            baseline.end   = double(E.baseWindowSec(2));
            baseline.mode  = 'sec';
        end

        if isfield(E,'mapCaxis') && numel(E.mapCaxis) == 2 && all(isfinite(E.mapCaxis))
            par.previewCaxis = double(E.mapCaxis(:)).';
        else
            par.previewCaxis = [0 50];
        end

        par.interpol = 1;

        if isfield(E,'mapSigma') && ~isempty(E.mapSigma) && isfinite(E.mapSigma)
            overlaySmoothSigma = max(0, min(overlaySmoothMax, double(E.mapSigma)));
        end

        if isfield(E,'mapModMin') && ~isempty(E.mapModMin) && isfinite(E.mapModMin)
            modMinAbs = double(E.mapModMin);
        end

        if isfield(E,'mapModMax') && ~isempty(E.mapModMax) && isfinite(E.mapModMax)
            modMaxAbs = double(E.mapModMax);
        end

        if isfield(E,'render') && isstruct(E.render)
            if isfield(E.render,'alphaModEnable') && ~isempty(E.render.alphaModEnable)
                alphaModEnable = logical(E.render.alphaModEnable);
            end
            if isfield(E.render,'alphaPct') && ~isempty(E.render.alphaPct) && isfinite(E.render.alphaPct)
                alphaPct = max(0, min(100, double(E.render.alphaPct)));
            end
            if isfield(E.render,'overlayCmapName') && ~isempty(E.render.overlayCmapName)
                overlayCmapName = safeStr(E.render.overlayCmapName);
                idxMap = find(strcmp(cmapNames, overlayCmapName), 1, 'first');
                if isempty(idxMap)
                    overlayCmapName = 'blackbdy_iso';
                    idxMap = find(strcmp(cmapNames, overlayCmapName), 1, 'first');
                end
                if ~isempty(idxMap) && ishandle(popMap)
                    set(popMap,'Value',idxMap);
                end
                mapA = getCmap(overlayCmapName, Nc);
                try
                    colormap(ax, mapA);
                catch
                end
            end
        end

        % IMPORTANT: derive nVols from PSC BEFORE resetting masks/geometry
        switch ndims(PSC)
            case 4
                nVols = size(PSC,4);
            case 3
                nVols = size(PSC,3);
            otherwise
                nVols = 1;
        end

        Tmax = max(0, (nVols - 1) * TR);

        % Reset atlas state
        state.isAtlasWarped = false;
        state.atlasTransformFile = '';
        state.lastAtlasTransformFile = '';

        % New "native/original" state becomes this GA bundle
        origI             = I;
        origI_interp      = I_interp;
        origPSC           = PSC;
        origBgDefaultFull = bgDefaultFull;

        % Reset underlay source
        underSrc = 1;
        underSrcLabel = 'Default(bg)';
        if ishandle(popUSrc)
            set(popUSrc,'Value',1);
        end

        % Clear masks for GA view
        mask = [];
        maskIsInclude = true;
        origMask = [];
        origMaskIsInclude = true;

        if ishandle(popIncExc)
            set(popIncExc,'Value',1);
        end

        % Reset dimensions / frame / volume
        volume = 1;
        frame  = 1;
        sliceIdx = 1;

        applyUnderlayMeta(defaultUnderlayMeta(), bgDefaultFull);

        resetAfterDataSpaceChange(true);

        % UI sync
        if ishandle(slVol)
            set(slVol,'Min',1,'Max',max(1,nVols),'Value',1);
        end
        if ishandle(txtVol)
            set(txtVol,'String',sprintf('%d / %d',1,nVols));
        end
        if ishandle(edRange)
            set(edRange,'String',sprintf('%.6g %.6g', ...
                par.previewCaxis(1), par.previewCaxis(2)));
        end
        if ishandle(slSmooth)
            set(slSmooth,'Value',overlaySmoothSigma);
        end
        if ishandle(edSmooth)
            set(edSmooth,'String',sprintf('%.2f',overlaySmoothSigma));
        end
        if ishandle(chkAlphaMod)
            set(chkAlphaMod,'Value',double(alphaModEnable));
        end
        if ishandle(slAlpha)
            set(slAlpha,'Value',alphaPct);
        end
        if ishandle(txtAlpha)
            set(txtAlpha,'String',sprintf('%.0f',alphaPct));
        end
        if ishandle(edModMin)
            set(edModMin,'String',sprintf('%.3g',modMinAbs));
        end
        if ishandle(edModMax)
            set(edModMax,'String',sprintf('%.3g',modMaxAbs));
        end

        updateOverlayEnable();

        try
            caxis(ax, par.previewCaxis);
            set(cbar,'Limits',par.previewCaxis);
        catch
        end

        fileLabel = ['GA Group Video: ' f];
        if ishandle(txtTitle)
            set(txtTitle,'String',fileLabel);
        end

        statusLine = ['Loaded GA group video bundle: ' fullf];
        render();

    catch ME
        errordlg(ME.message,'Load GA group video bundle failed');
    end
end
    
    function fpsSliderChanged(src,~)
        setFPS(get(src,'Value'));
    end

    function volSliderChanged(src,~)
        scrubVol(round(get(src,'Value')));
    end

    function brushSliderChanged(src,~)
        setBrush(round(get(src,'Value')));
    end

    function maskAlphaSliderChanged(src,~)
        setOverlayAlpha(get(src,'Value'));
    end

    function setFPS(v)
        fps = max(1, min(maxFPS, round(v)));
        set(slFPS,'Value',fps);

        if exist('playTimer','var') && isa(playTimer,'timer') && isvalid(playTimer)
            stop(playTimer);
            set(playTimer,'Period',1/max(fps,0.1));
            if playing
                start(playTimer);
            end
        end
        render();
    end

    function scrubVol(v)
        playing = false;
        set(playBtn,'Value',0,'String','Play');

        volume = min(max(1, v), nVols);
        set(slVol,'Value',volume);

        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));
        render();
    end

    function toggleEditor(src,~)
        editorMode = logical(get(src,'Value'));
        set(src,'String',tern(editorMode,'Editor ON','Editor OFF'));
        statusLine = '';
        render();
    end

    function toggleViewMasked(src,~)
        viewMaskedOnly = logical(get(src,'Value'));
        set(src,'String',tern(viewMaskedOnly,'VIEW: MASKED','VIEW: FULL'));
        statusLine = '';
        render();
    end

    function setIncludeExclude(src,~)
        maskIsInclude = (get(src,'Value') == 1);
        statusLine = '';
        render();
    end

    function toggleApplyAll(src,~)
        applyToAllFrames = logical(get(src,'Value'));
        set(src,'String',tern(applyToAllFrames,'ALL FRAMES','CURRENT FRAME'));
        statusLine = '';
        render();
    end

    function setBrush(v)
        brushRadius = max(1, min(60, round(v)));
        set(slBrush,'Value',brushRadius);
        statusLine = '';
        render();
    end

    function pickColor(~,~)
        c = uisetcolor(maskColor, 'Pick mask overlay color');
        if numel(c) == 3
            maskColor = c;
        end
        render();
    end

    function clearMaskAll(~,~)
        mask(:) = false;
        statusLine = 'Mask cleared.';
        render();
    end

    function setOverlayAlpha(v)
        maskAlpha = max(0, min(1, v));
        set(slMaskA,'Value',maskAlpha);
        statusLine = '';
        render();
    end

    function applyMaskToAllFrames(~,~)
        refMask = mask(:,:,sliceIdx,volume);
        if ~any(refMask(:))
            statusLine = 'Mask empty - nothing applied.';
            render();
            return;
        end
        for vv = 1:nVols
            mask(:,:,sliceIdx,vv) = refMask;
        end
        statusLine = sprintf('Mask applied to all volumes (slice %d).', sliceIdx);
        render();
    end

% =========================================================
% UNDERLAY TAB CALLBACKS
% =========================================================
  function underSrcChanged(src,~)
    underSrc = get(src,'Value');
    if underSrc == 1, underSrcLabel = 'Default(bg)'; end
    if underSrc == 2, underSrcLabel = 'Mean(I)'; end
    if underSrc == 3, underSrcLabel = 'Median(I)'; end
    statusLine = '';
    render();
end

    function underModeChanged(src,~)
        uState.mode = get(src,'Value');
        updateUnderlayEnable();
        statusLine = '';
        render();
    end

    function underSliderChanged(~,~)
        uState.brightness = get(slBri,'Value');
        uState.contrast   = get(slCon,'Value');
        uState.gamma      = get(slGam,'Value');

        uState.conectSize = round(get(slVsz,'Value'));
        uState.conectLev  = round(get(slVlv,'Value'));

        uState.conectSize = max(0, min(MAX_CONSIZE, uState.conectSize));
        uState.conectLev  = max(0, min(MAX_CONLEV,  uState.conectLev));

        set(txtBri,'String',sprintf('%.2f',uState.brightness));
        set(txtCon,'String',sprintf('%.2f',uState.contrast));
        set(txtGam,'String',sprintf('%.2f',uState.gamma));
        set(txtVsz,'String',sprintf('%d',uState.conectSize));
        set(txtVlv,'String',sprintf('%d',uState.conectLev));

        statusLine = '';
        render();
    end

    function updateUnderlayEnable()
        isVessel = (uState.mode==4);
        set(slVsz,'Enable',onoff(isVessel)); set(txtVsz,'Enable',onoff(isVessel));
        set(slVlv,'Enable',onoff(isVessel)); set(txtVlv,'Enable',onoff(isVessel));
    end

% =========================================================
% OVERLAY TAB CALLBACKS
% =========================================================
    function overlayMapChanged(src,~)
        s = get(src,'String');
        idx = get(src,'Value');
        if iscell(s)
            overlayCmapName = s{idx};
        else
            overlayCmapName = strtrim(s(idx,:));
        end
        mapA = getCmap(overlayCmapName, Nc);
        try
            colormap(ax, mapA);
        catch
        end
        render();
    end

    function overlayRangeApply(~,~)
        v = sscanf(get(edRange,'String'),'%f');
        if numel(v) < 2 || any(~isfinite(v(1:2))) || v(2) == v(1)
            errordlg('Invalid range. Use: "min max"');
            return;
        end

        lo = v(1);
        hi = v(2);
        if hi < lo
            tmp = lo;
            lo = hi;
            hi = tmp;
        end

        par.previewCaxis = [lo hi];
        caxis(ax, par.previewCaxis);
        try
            set(cbar,'Limits',par.previewCaxis);
        catch
        end

        absMax = max(abs([lo hi]));
        if ~isfinite(absMax) || absMax <= 0
            absMax = 1;
        end

        set(slThr,'Min',0,'Max',absMax);
        maskThreshold = min(max(maskThreshold, 0), absMax);
        set(slThr,'Value',maskThreshold);
        set(edThr,'String',sprintf('%.3g',maskThreshold));

        render();
    end

    function overlayThrSliderChanged(src,~)
        maskThreshold = get(src,'Value');
        set(edThr,'String',sprintf('%.3g',maskThreshold));
        render();
    end

    function overlayThrEditChanged(src,~)
        v = str2double(get(src,'String'));
        if ~isfinite(v)
            v = maskThreshold;
        end
        lo = get(slThr,'Min');
        hi = get(slThr,'Max');
        v = min(max(v,lo),hi);
        maskThreshold = v;
        set(slThr,'Value',maskThreshold);
        set(src,'String',sprintf('%.3g',maskThreshold));
        render();
    end

    function overlayAlphaSliderChanged(src,~)
        alphaPct = get(src,'Value');
        alphaPct = max(0, min(100, alphaPct));
        set(slAlpha,'Value',alphaPct);
        set(txtAlpha,'String',sprintf('%.0f',alphaPct));
        render();
    end

    function overlayAlphaModToggle(src,~)
        alphaModEnable = logical(get(src,'Value'));
        updateOverlayEnable();
        render();
    end

    function overlaySmoothSliderChanged(src,~)
        overlaySmoothSigma = get(src,'Value');
        overlaySmoothSigma = max(0, min(overlaySmoothMax, overlaySmoothSigma));
        set(slSmooth,'Value',overlaySmoothSigma);
        set(edSmooth,'String',sprintf('%.2f',overlaySmoothSigma));
        render();
    end

    function overlaySmoothEditChanged(src,~)
        v = str2double(get(src,'String'));
        if ~isfinite(v)
            v = overlaySmoothSigma;
        end

        v = max(0, min(overlaySmoothMax, v));
        overlaySmoothSigma = v;

        set(slSmooth,'Value',overlaySmoothSigma);
        set(src,'String',sprintf('%.2f',overlaySmoothSigma));
        render();
    end

    function overlayModMinEdit(src,~)
        v = str2double(get(src,'String'));
        if ~isfinite(v)
            v = modMinAbs;
        end
        modMinAbs = v;
        if modMaxAbs < modMinAbs
            modMaxAbs = modMinAbs;
            set(edModMax,'String',sprintf('%.3g',modMaxAbs));
        end
        set(src,'String',sprintf('%.3g',modMinAbs));
        render();
    end

    function overlayModMaxEdit(src,~)
        v = str2double(get(src,'String'));
        if ~isfinite(v)
            v = modMaxAbs;
        end
        modMaxAbs = v;
        if modMaxAbs < modMinAbs
            modMinAbs = modMaxAbs;
            set(edModMin,'String',sprintf('%.3g',modMinAbs));
        end
        set(src,'String',sprintf('%.3g',modMaxAbs));
        render();
    end

    function updateOverlayEnable()
        if alphaModEnable
            set(edModMin,'Enable','on','ForegroundColor','w','BackgroundColor',[0.20 0.20 0.20]);
            set(edModMax,'Enable','on','ForegroundColor','w','BackgroundColor',[0.20 0.20 0.20]);
        else
            set(edModMin,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
            set(edModMax,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
        end
    end

% =========================================================
% PLAY/REPLAY
% =========================================================
    function playPause(src,~)
        playing = logical(get(src,'Value'));
        if playing
            set(src,'String','Pause');
            if strcmp(playTimer.Running,'off')
                set(playTimer,'Period',1/max(fps,0.1));
                start(playTimer);
            end
        else
            set(src,'String','Play');
            if strcmp(playTimer.Running,'on')
                stop(playTimer);
            end
        end
    end

    function replayVid(~,~)
        volume = 1;
        set(slVol,'Value',1);
        frame = 1;

        playing = true;
        set(playBtn,'Value',1,'String','Pause');

        stop(playTimer);
        set(playTimer,'Period',1/max(fps,0.1));
        start(playTimer);

        render();
    end

% =========================================================
% SCROLL SLICE
% =========================================================
   function mouseScrollSlice(~,evt)
    if nZ <= 1 || playing
        return;
    end

    if ~isPointerOverImageAxis()
        return;
    end

    % same direction logic as SCM_gui
    dz = sign(evt.VerticalScrollCount);
    if dz == 0
        return;
    end

    newZ = max(1, min(nZ, sliceIdx + dz));
    if newZ == sliceIdx
        return;
    end

    sliceIdx = newZ;
    render();
end

function tf = isPointerOverImageAxis()
    tf = false;

    try
        cpFig = get(fig, 'CurrentPoint');          % figure coordinates
        axPos = getpixelposition(ax, true);        % [x y w h] in figure coordinates

        x = cpFig(1);
        y = cpFig(2);

        tf = x >= axPos(1) && x <= (axPos(1) + axPos(3)) && ...
             y >= axPos(2) && y <= (axPos(2) + axPos(4));
    catch
        tf = false;
    end
end
% =========================================================
% OPEN SCM
% =========================================================
    function openSCM(~,~)
        try
            PSC_fast = PSC;
            bg_fast  = getUnderlayFull();

            if nZ == 1
                mask_fast = any(mask(:,:,1,:), 4);
            else
                mask_fast = false(ny, nx, nZ);
                for zz = 1:nZ
                    mask_fast(:,:,zz) = any(mask(:,:,zz,:), 4);
                end
            end

            SCM_gui( ...
                PSC_fast, bg_fast, TR, par, baseline, ...
                nVols, ...
                I, I_interp, fps, maxFPS, ...
                mask_fast, maskIsInclude, ...
                applyRejection, QC, fileLabel, sliceIdx);

            statusLine = 'SCM opened (mask transferred).';
            render();
        catch ME
            statusLine = ['SCM failed: ' ME.message];
            render();
        end
    end

% =========================================================
% SAVE MP4
% =========================================================
   function saveVideo(~,~)
    txt = [];
    vid = [];

    oldVolume   = volume;
    oldPlaying  = playing;
    oldSliceIdx = sliceIdx;

    try
        analysedRoot = '';

        if isstruct(par) && isfield(par,'exportPath') && ~isempty(par.exportPath)
            analysedRoot = char(par.exportPath);
        elseif isstruct(par) && isfield(par,'savePath') && ~isempty(par.savePath)
            analysedRoot = char(par.savePath);
        elseif isstruct(par) && isfield(par,'outPath') && ~isempty(par.outPath)
            analysedRoot = char(par.outPath);
        else
            analysedRoot = pwd;
        end

        analysedRoot = strtrim(analysedRoot);
        analysedRoot = strrep(analysedRoot,'"','');

        if isempty(analysedRoot) || ~exist(analysedRoot,'dir')
            analysedRoot = pwd;
        end

        videosDir = fullfile(analysedRoot, 'Videos');
        if ~exist(videosDir,'dir')
            [ok,msg] = mkdir(videosDir);
            if ~ok
                error('Could not create Videos folder:\n%s\n\nReason: %s', videosDir, msg);
            end
        end

        rawLabel = lower(safeStr(fileLabel));
        if isempty(rawLabel)
            rawLabel = '';
        end

        tags = {};
        if contains(rawLabel,'raw'), tags{end+1} = 'raw'; end
        if contains(rawLabel,'gabriel'), tags{end+1} = 'gab'; end
        if contains(rawLabel,'median'), tags{end+1} = 'median'; end
        if contains(rawLabel,'mean'), tags{end+1} = 'mean'; end
        if contains(rawLabel,'pca'), tags{end+1} = 'pca'; end
        if contains(rawLabel,'despike') || contains(rawLabel,'despiked')
            tags{end+1} = 'despike';
        end
        if contains(rawLabel,'smooth') || contains(rawLabel,'smoothed')
            tags{end+1} = 'smooth';
        end
        if contains(rawLabel,'interp') || contains(rawLabel,'interpol')
            tags{end+1} = 'interp';
        end
        if contains(rawLabel,'psc'), tags{end+1} = 'psc'; end
        if contains(rawLabel,'brainonly'), tags{end+1} = 'brain'; end

        if isempty(tags)
            shortLabel = 'video';
        else
            shortLabel = strjoin(tags,'_');
        end

        timeTag = datestr(now,'yyyymmdd_HHMMSS');

        exportFPS = fps;
        if ~isfinite(exportFPS) || exportFPS <= 0
            exportFPS = 4;
        end

        playing = false;
        if ishandle(playBtn)
            set(playBtn,'Value',0,'String','Play');
        end
        try
            if exist('playTimer','var') && isa(playTimer,'timer') && isvalid(playTimer)
                stop(playTimer);
            end
        catch
        end

        txt = text(ax, 0.02, 0.98, '', ...
            'Units','normalized', ...
            'Color','w', ...
            'FontName','Courier New', ...
            'FontSize',40, ...
            'FontWeight','bold', ...
            'VerticalAlignment','top', ...
            'HorizontalAlignment','left', ...
            'BackgroundColor','k', ...
            'Margin',8, ...
            'Interpreter','none');

        for zz = 1:max(1,nZ)
            sliceIdx = zz;
            volume = 1;
            frame = 1;

            if ishandle(slVol)
                set(slVol,'Value',1);
            end

            render();
            drawnow;

            outFile = fullfile(videosDir, sprintf('video_%s_z%02d_%s.mp4', shortLabel, zz, timeTag));

            disp('--- SAVE VIDEO DEBUG ---');
            disp(['slice       = ' num2str(zz)]);
            disp(['videosDir   = ' videosDir]);
            disp(['outFile     = ' outFile]);
            disp(['path length = ' num2str(numel(outFile))]);

            vid = VideoWriter(outFile, 'MPEG-4');
            vid.FrameRate = exportFPS;
            vid.Quality   = 95;
            open(vid);

            for v = 1:nVols
                volume = v;
                if ishandle(slVol)
                    set(slVol,'Value',v);
                end

                frame = (v - 1) * par.interpol + 1;
                frame = max(1, min(nFrames, round(frame)));

                render();

                t = (v - 1) * TR;
                set(txt,'String',sprintf('Slice %d / %d | t = %.1f / %.1f s | Volume %d / %d', ...
                    zz, nZ, t, Tmax, v, nVols));

                drawnow;
                fr = getframe(ax);

                repeatEachFrame = 2;
                for rr = 1:repeatEachFrame
                    writeVideo(vid, fr);
                end
            end

            close(vid);
            vid = [];
        end

        if ~isempty(txt) && isgraphics(txt)
            delete(txt);
            txt = [];
        end

        volume   = oldVolume;
        playing  = oldPlaying;
        sliceIdx = oldSliceIdx;

        if ishandle(slVol)
            set(slVol,'Value',volume);
        end

        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));
        render();

        statusLine = sprintf('Videos saved for all %d slice(s) in: %s', max(1,nZ), videosDir);
        render();

    catch ME
        try
            if ~isempty(txt) && isgraphics(txt)
                delete(txt);
            end
        catch
        end

        try
            if ~isempty(vid)
                close(vid);
            end
        catch
        end

        volume   = oldVolume;
        playing  = oldPlaying;
        sliceIdx = oldSliceIdx;

        try
            if ishandle(slVol)
                set(slVol,'Value',volume);
            end
            frame = (volume - 1) * par.interpol + 1;
            frame = max(1, min(nFrames, round(frame)));
            render();
        catch
        end

        statusLine = ['Video save failed: ' ME.message];
        render();
        errordlg(sprintf('MP4 export failed:\n\n%s', ME.message), 'Save MP4 failed');
    end
end
% =========================================================
% SAVE MASK
% =========================================================
    function saveMaskMat(~,~)
        [f,p] = uiputfile('*.mat','Save mask / bundle');
        if isequal(f,0)
            return;
        end

        out = struct();

        out.loadedMask = mask;
        out.loadedMaskIsInclude = maskIsInclude;

        out.overlayMask = mask;
        out.overlayMaskIsInclude = maskIsInclude;

        out.mask = mask;
        out.maskIsInclude = maskIsInclude;

        out.brainImage = bgDefaultFull;

        out.brainMask = deriveBrainMaskFromUnderlayVideo(bgDefaultFull, ny, nx, nZ);
        out.brainMaskIsInclude = true;

        out.metadata = struct();
        out.metadata.TR = TR;
        out.metadata.nVols = nVols;
        out.metadata.nZ = nZ;
        out.metadata.created = datestr(now);
        out.metadata.script = mfilename;
        out.metadata.note = 'Mask bundle saved from fUSI Video GUI';

        maskBundle = struct();
        maskBundle.loadedMask = out.loadedMask;
        maskBundle.loadedMaskIsInclude = out.loadedMaskIsInclude;
        maskBundle.overlayMask = out.overlayMask;
        maskBundle.overlayMaskIsInclude = out.overlayMaskIsInclude;
        maskBundle.mask = out.mask;
        maskBundle.maskIsInclude = out.maskIsInclude;
        maskBundle.brainImage = out.brainImage;
        maskBundle.brainMask = out.brainMask;
        maskBundle.brainMaskIsInclude = out.brainMaskIsInclude;
        maskBundle.metadata = out.metadata;

        out.maskBundle = maskBundle;

        save(fullfile(p,f),'-struct','out','-v7.3');
        statusLine = 'Mask bundle saved.';
        render();
    end

% =========================================================
% SAVE INTERPOLATED DATA
% =========================================================
    function saveInterpolatedMat(~,~)
        [f,p] = uiputfile('*.mat','Save interpolated fUSI data');
        if isequal(f,0)
            return;
        end

        out = struct();
        out.I = I_interp;

        metadata = struct();
        metadata.TR = TR;
        metadata.baseline = baseline;
        metadata.date = datestr(now);
        metadata.script = mfilename;
        out.metadata = metadata;

        save(fullfile(p,f),'-struct','out','-v7.3');
        statusLine = 'Interpolated data saved.';
        render();
    end

% =========================================================
% HELP
% =========================================================
    function showHelpDialog(~,~)
        hf = figure('Name','Help - fUSI Video GUI', ...
            'Color',[0.06 0.06 0.06], ...
            'MenuBar','none','ToolBar','none', ...
            'NumberTitle','off', ...
            'Position',[250 120 920 740], ...
            'Resize','on', ...
            'WindowStyle','modal');

        msg = [ ...
            'TABS:\n' ...
            '  Video/Mask: playback + masking tools\n' ...
            '  Underlay: source + processing (robust, vessel, B/C/G)\n' ...
            '  Overlay: colormap + display range + threshold + alpha modulation\n\n' ...
            'MASK BEHAVIOR (SCM-LIKE):\n' ...
            '  If a mask exists for this slice/volume, overlay is restricted by Include/Exclude.\n' ...
            '  VIEW: MASKED dims outside region for clearer visualization.\n\n' ...
            'ALPHA MODULATION (SCM IDENTICAL):\n' ...
            '  OFF: alpha=(a/100)*thrMask*mask\n' ...
            '  ON : alpha=(a/100)*mod*thrMask*mask\n\n' ...
            'SHORTCUTS:\n' ...
            '  M: Auto mask\n' ...
            '  F: Fill region at cursor\n' ...
            '  Mouse wheel: change slice\n' ...
            ];

        uicontrol('Style','edit','Parent',hf, ...
            'Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
            'String',sprintf(msg), ...
            'ForegroundColor',[0.90 0.90 0.90], ...
            'BackgroundColor',[0.12 0.12 0.12], ...
            'FontName','Arial', ...
            'FontSize',14, ...
            'HorizontalAlignment','left', ...
            'Max',2,'Min',0, ...
            'Enable','inactive');
    end

% =========================================================
% MOUSE PAINTING
% =========================================================
    function mouseDown(~,~)
        if playing || ~editorMode
            return;
        end
        mouseIsDown = true;

        sel = get(fig,'SelectionType');
        if strcmp(sel,'normal')
            paintMode = 'add';
        elseif strcmp(sel,'alt')
            paintMode = 'remove';
        else
            mouseIsDown = false;
            return;
        end

        applyPaintAtCursor();
    end

    function mouseUp(~,~)
        mouseIsDown = false;
        paintMode = '';
    end

    function mouseMoveVideo(~,~)
        if ~ishandle(ax)
            return;
        end

        cp = get(ax,'CurrentPoint');
        x = cp(1,1);
        yv = cp(1,2);
        if x>=1 && x<=nx && yv>=1 && yv<=ny
            lastMouseXY = [x yv];
        end

        if ~mouseIsDown || ~editorMode || playing
            return;
        end
        applyPaintAtCursor();
    end

    function applyPaintAtCursor()
        cp = get(ax,'CurrentPoint');
        x = round(cp(1,1));
        yv = round(cp(1,2));
        if x<1 || x>nx || yv<1 || yv>ny
            return;
        end

        brush = makeBrushMask(x, yv, brushRadius, ny, nx);

        if strcmp(paintMode,'add')
            if applyToAllFrames
                mask(:,:,sliceIdx,:) = mask(:,:,sliceIdx,:) | repmat(brush,[1 1 1 nVols]);
            else
                mask(:,:,sliceIdx,volume) = mask(:,:,sliceIdx,volume) | brush;
            end
        else
            if applyToAllFrames
                mask(:,:,sliceIdx,:) = mask(:,:,sliceIdx,:) & ~repmat(brush,[1 1 1 nVols]);
            else
                mask(:,:,sliceIdx,volume) = mask(:,:,sliceIdx,volume) & ~brush;
            end
        end

        statusLine = '';
        render();
    end

% =========================================================
% KEYBOARD SHORTCUTS
% =========================================================
    function keyPressHandler(~,evt)
        if ~isfield(evt,'Key')
            return;
        end
        switch lower(evt.Key)
            case 'f'
                if any(isnan(lastMouseXY))
                    statusLine = 'Move mouse over image, then press F.';
                    render();
                    return;
                end
                fillAtXY(lastMouseXY(1), lastMouseXY(2));
            case 'm'
                autoMask();
        end
    end

    function fillRegion(~,~)
        if any(isnan(lastMouseXY))
            statusLine = 'Move mouse over image, then press F.';
            render();
            return;
        end
        fillAtXY(lastMouseXY(1), lastMouseXY(2));
    end

    function fillAtXY(xf,yf)
        x0 = round(xf);
        y0 = round(yf);
        if x0<1 || x0>nx || y0<1 || y0>ny
            statusLine = 'Fill aborted: outside image.';
            render();
            return;
        end
        fillRegionAtSeed(x0,y0);
    end

% =========================================================
% AUTO MASK + FILL LOGIC
% =========================================================
    function autoMask()
        if ndPSC == 4
            P = squeeze(max(abs(PSC(:,:,sliceIdx,:)),[],4));
        elseif ndPSC == 3
            P = max(abs(PSC),[],3);
        else
            P = abs(PSC);
        end
        P(~isfinite(P)) = 0;

        vec = P(:);
        medv = median(vec);
        madv = median(abs(vec - medv)) + eps;
        thr = medv + 1.2*madv;

        autoM = P >= thr;

        try
            se = strel('disk', max(1,round(fillWindowR/3)));
            autoM = imopen(autoM,se);
            autoM = imclose(autoM,se);
            autoM = imfill(autoM,'holes');
            autoM = bwareaopen(autoM, 20);
        catch
        end

        if nnz(autoM) > fillMaxPixels
            try
                autoM = bwareafilt(autoM,1);
            catch
            end
        end

        if applyToAllFrames
            mask(:,:,sliceIdx,:) = repmat(autoM,[1 1 1 nVols]);
            statusLine = sprintf('AUTO MASK applied to ALL volumes (slice %d).', sliceIdx);
        else
            mask(:,:,sliceIdx,volume) = autoM;
            statusLine = sprintf('AUTO MASK applied to volume %d (slice %d).', volume, sliceIdx);
        end
        render();
    end

    function fillRegionAtSeed(x0,y0)
        if ndPSC == 4
            P = squeeze(max(abs(PSC(:,:,sliceIdx,:)),[],4));
        elseif ndPSC == 3
            P = max(abs(PSC),[],3);
        else
            P = abs(PSC);
        end
        P(~isfinite(P)) = 0;
        P = mat2gray_safe(P);

        centerVal = P(y0,x0);
        if ~isfinite(centerVal)
            statusLine = 'Fill aborted: invalid seed.';
            render();
            return;
        end

        Ww = max(1, round(fillWindowR));
        y1 = max(1, y0-Ww);
        y2 = min(ny, y0+Ww);
        x1 = max(1, x0-Ww);
        x2 = min(nx, x0+Ww);

        block = P(y1:y2, x1:x2);
        sigmaLocal = std(block(:));
        if ~isfinite(sigmaLocal) || sigmaLocal == 0
            sigmaLocal = 0.05;
        end

        thrDiff = fillSigmaFactor * sigmaLocal;
        region = abs(P - centerVal) <= thrDiff;

        try
            region = bwareaopen(region, 5);
            region = imfill(region,'holes');
        catch
        end

        if applyToAllFrames
            mask(:,:,sliceIdx,:) = mask(:,:,sliceIdx,:) | repmat(region,[1 1 1 nVols]);
        else
            mask(:,:,sliceIdx,volume) = mask(:,:,sliceIdx,volume) | region;
        end

        statusLine = sprintf('Fill grown at (%d,%d).', x0, y0);
        render();
    end

% =========================================================
% COLORBAR RANGE
% =========================================================
    function setColorbarRange(~,~)
        answer = inputdlg({'Lower limit (%):','Upper limit (%):'}, ...
            'Set Signal Change Range', 1, ...
            {num2str(par.previewCaxis(1)), num2str(par.previewCaxis(2))});
        if isempty(answer)
            return;
        end

        low = str2double(answer{1});
        high = str2double(answer{2});
        if isnan(low) || isnan(high) || high <= low
            errordlg('Invalid colorbar limits.');
            return;
        end

        par.previewCaxis = [low high];
        caxis(ax, par.previewCaxis);
        try
            set(cbar,'Limits',par.previewCaxis);
        catch
        end

        set(edRange,'String',sprintf('%.6g %.6g',low,high));

        absMax = max(abs([low high]));
        if ~isfinite(absMax) || absMax <= 0
            absMax = 1;
        end

        set(slThr,'Min',0,'Max',absMax);

        maskThreshold = min(max(maskThreshold, 0), absMax);
        set(slThr,'Value',maskThreshold);
        set(edThr,'String',sprintf('%.3g',maskThreshold));

        render();
    end

% =========================================================
% CLOSE HANDLER
% =========================================================
    function onCloseVideo(~,~)
        try
            if exist('playTimer','var') && isa(playTimer,'timer')
                stop(playTimer);
                delete(playTimer);
            end
        catch
        end
        try
            setappdata(fig,'updatedMask',mask);
            setappdata(fig,'updatedMaskIsInclude',maskIsInclude);
        catch
        end
        delete(fig);
    end

% =========================================================
% UNDERLAY CORE
% =========================================================
  function bgFull = getUnderlayFull()
    switch underSrc
        case 1
            bgFull = bgDefaultFull;
        case 2
            if isempty(bgMeanFull), bgMeanFull = computeUnderlayFromI('mean'); end
            bgFull = bgMeanFull;
        case 3
            if isempty(bgMedianFull), bgMedianFull = computeUnderlayFromI('median'); end
            bgFull = bgMedianFull;
        otherwise
            bgFull = bgDefaultFull;
    end
end

    function bgFull = computeUnderlayFromI(method)
        dimT = ndims(I);
        if strcmpi(method,'mean')
            bgFull = mean(double(I), dimT);
            return;
        end
        sz = size(I);
        T0 = sz(dimT);
        maxFrames = 600;
        if T0 <= maxFrames
            idx = 1:T0;
        else
            step = ceil(T0 / maxFrames);
            idx  = 1:step:T0;
        end
        subs = repmat({':'},1,dimT);
        subs{dimT} = idx;
        Isub = double(I(subs{:}));
        bgFull = median(Isub, dimT);
    end

    function bg2 = getBg2DForSlice(bgIn, z)
    if ndims(bgIn) == 2
        bg2 = bgIn;
        return;
    end

    if ndims(bgIn) == 3
        % IMPORTANT:
        % Treat [Y X 3] as RGB ONLY for single-slice datasets.
        if (nZ == 1) && (size(bgIn,3) == 3)
            bg2 = bgIn;
            return;
        end

        z = max(1, min(size(bgIn,3), z));
        bg2 = bgIn(:,:,z);
        return;
    end

    if ndims(bgIn) == 4
        % RGB stack: [Y X 3 Z]
        if size(bgIn,3) == 3
            z = max(1, min(size(bgIn,4), z));
            bg2 = squeeze(bgIn(:,:,:,z));
            return;
        end

        % grayscale 4D -> mean over 4th dim, then slice
        tmp = mean(bgIn, 4);
        z = max(1, min(size(tmp,3), z));
        bg2 = tmp(:,:,z);
        return;
    end

    bg2 = squeeze(bgIn(:,:,1));
end

    function U01 = processUnderlay(Uin)
        U = double(Uin);
        U(~isfinite(U)) = 0;

        switch uState.mode
            case 1
                U = mat2gray_safe(U);
            case 2
                U = clip01_percentile(U,1,99);
            case 3
                U = clip01_percentile(U,0.5,99.5);
            case 4
                U = clip01_percentile(U,0.5,99.5);
                U = vesselEnhanceStrong(U,uState.conectSize,uState.conectLev);
                U = clip01_percentile(U,0.5,99.5);
            otherwise
                U = mat2gray_safe(U);
        end

        U = U*uState.contrast + uState.brightness;
        U = min(max(U,0),1);

        g = uState.gamma;
        if ~isfinite(g) || g<=0
            g = 1;
        end
        U01 = min(max(U.^g,0),1);
    end

    function U = vesselEnhanceStrong(U01, conectSizePx, conectLev_0_MAX)
        if conectSizePx <= 0
            U = U01;
            return;
        end

        lev01 = (conectLev_0_MAX / max(1,MAX_CONLEV));
        lev01 = lev01^0.75;
        lev01 = min(max(lev01,0),1);

        thrMask = (U01 > lev01);

        r = max(1, round(conectSizePx));
        r = min(r, MAX_CONSIZE);
        h = diskKernel(r);

        try
            D = filter2(h, double(thrMask), 'same');
        catch
            D = conv2(double(thrMask), h, 'same');
        end
        D = min(max(D,0),1);

        strength = 0.8 + 1.6 * min(1, r/120);
        D2 = D.^2;

        U = U01 .* (1 + strength*D2) + 0.15*D2;
        U = min(max(U,0),1);
    end

    function h = diskKernel(r)
        r = max(1,round(r));
        [x,y] = meshgrid(-r:r,-r:r);
        m = (x.^2 + y.^2) <= r^2;
        h = double(m);
        s = sum(h(:));
        if s>0
            h = h/s;
        end
    end

    function rgb = toRGB(im01)
        im = double(im01);
        im(~isfinite(im)) = 0;
        im = min(max(im,0),1);
        idx = uint8(round(im*255));
        rgb = ind2rgb(idx, gray(256));
    end

    function [U, label] = loadUnderlayInteractive()
        U = [];
        label = '';

        [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.tif;*.tiff', ...
                           'Underlay files'}, 'Select underlay file');
        if isequal(f,0)
            return;
        end
        fullf = fullfile(p,f);

        U = loadUnderlayFile(fullf);
        if isempty(U)
            return;
        end

        [~,nm,ext] = fileparts(f);
        label = ['File: ' nm ext];
    end

    function U = loadUnderlayFile(f)
        U = [];
        if ~exist(f,'file')
            errordlg(sprintf('Underlay file not found:\n%s', f),'Underlay');
            return;
        end

        isNiiGz = numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz');

        try
            if isNiiGz
                tmpDir = tempname;
                mkdir(tmpDir);
                gunzip(f, tmpDir);
                d = dir(fullfile(tmpDir,'*.nii'));
                if isempty(d)
                    error('gunzip failed.');
                end
                niiFile = fullfile(tmpDir, d(1).name);
                V = niftiread(niiFile);
                try, rmdir(tmpDir,'s'); catch, end
                U = squeezeTo2Dor3D(double(V));
                return;
            end

            [~,~,ext] = fileparts(f);

            if strcmpi(ext,'.nii')
                V = niftiread(f);
                U = squeezeTo2Dor3D(double(V));
                return;
            end

            if strcmpi(ext,'.mat')
                S = load(f);
                U = pickNumericFromMat(S);
                U = squeezeTo2Dor3D(double(U));
                return;
            end

            A = imread(f);
            U = toGray(double(A));
        catch ME
            errordlg(ME.message,'Underlay load failed');
            U = [];
        end
    end

    function U = pickNumericFromMat(S)
        if isstruct(S)
            fn = fieldnames(S);
            for k = 1:numel(fn)
                v = S.(fn{k});
                if isstruct(v) && isfield(v,'I') && isnumeric(v.I)
                    U = v.I;
                    return;
                end
            end
            for k = 1:numel(fn)
                v = S.(fn{k});
                if isnumeric(v)
                    U = v;
                    return;
                end
            end
        end
        error('No numeric variable found in MAT file.');
    end

    function X = squeezeTo2Dor3D(X)
        while ndims(X) > 3
            X = mean(X, ndims(X));
        end
    end

    function G = toGray(X)
        if ndims(X) == 3 && size(X,3) == 3
            R = X(:,:,1);
            Gc = X(:,:,2);
            B = X(:,:,3);
            G = 0.2989*R + 0.5870*Gc + 0.1140*B;
        else
            G = X;
        end
    end

% =========================================================
% COLORMAP HELPERS
% =========================================================
    function cm = getCmap(name, n)
        name = lower(strtrim(char(name)));

        if strcmp(name,'blackbdy_iso')
            if exist('blackbdy_iso','file')
                cm = blackbdy_iso(n);
            else
                cm = hot(n);
            end
            cm(1,:) = 0;
            return;
        end

        switch name
            case 'hot'
                cm = hot(n);
            case 'parula'
                cm = parula(n);
            case 'jet'
                cm = jet(n);
            case 'gray'
                cm = gray(n);
            case 'bone'
                cm = bone(n);
            case 'copper'
                cm = copper(n);
            case 'pink'
                cm = pink(n);
            otherwise
                if strcmp(name,'turbo')
                    if exist('turbo','file')
                        cm = turbo(n);
                    else
                        cm = jet(n);
                    end
                elseif strcmp(name,'viridis')
                    anchors = [0.267 0.005 0.329; 0.283 0.141 0.458; 0.254 0.265 0.530; ...
                               0.207 0.372 0.553; 0.164 0.471 0.558; 0.128 0.567 0.551; ...
                               0.135 0.659 0.518; 0.267 0.749 0.441; 0.478 0.821 0.318; ...
                               0.741 0.873 0.150];
                    cm = interpAnchors(anchors,n);
                elseif strcmp(name,'plasma')
                    anchors = [0.050 0.030 0.528; 0.280 0.040 0.650; 0.500 0.060 0.650; ...
                               0.700 0.170 0.550; 0.850 0.350 0.420; 0.940 0.550 0.260; ...
                               0.990 0.750 0.140];
                    cm = interpAnchors(anchors,n);
                elseif strcmp(name,'magma')
                    anchors = [0.001 0.000 0.015; 0.100 0.060 0.230; 0.250 0.080 0.430; ...
                               0.450 0.120 0.500; 0.650 0.210 0.420; 0.820 0.370 0.280; ...
                               0.930 0.610 0.210; 0.990 0.870 0.400];
                    cm = interpAnchors(anchors,n);
                elseif strcmp(name,'inferno')
                    anchors = [0.002 0.002 0.014; 0.120 0.030 0.220; 0.280 0.050 0.400; ...
                               0.480 0.090 0.430; 0.680 0.180 0.330; 0.820 0.350 0.210; ...
                               0.930 0.590 0.110; 0.990 0.860 0.240];
                    cm = interpAnchors(anchors,n);
                else
                    cm = hot(n);
                end
        end
        cm(1,:) = 0;
    end

    function cm = interpAnchors(anchors,n)
        x = linspace(0,1,size(anchors,1));
        xi = linspace(0,1,n);
        cm = zeros(n,3);
        for k=1:3
            cm(:,k) = interp1(x, anchors(:,k), xi, 'linear');
        end
        cm = min(max(cm,0),1);
    end

% =========================================================
% THRESHOLD RANGE HELPER
% =========================================================
    function [thrMin, thrMax] = getSuggestedThresholdRange(PSC0, cax0)
        v = PSC0(:);
        v = v(isfinite(v));
        if isempty(v)
            thrMin = cax0(1);
            thrMax = cax0(2);
            return;
        end
        thrMin = prctile_fallback(v,1);
        thrMax = prctile_fallback(v,99);
        if ~isfinite(thrMin) || ~isfinite(thrMax) || thrMax <= thrMin
            thrMin = cax0(1);
            thrMax = cax0(2);
        end
    end

% =========================================================
% SMALL HELPERS
% =========================================================
    function E = extractGroupVideoBundleStruct(S)
    if isfield(S,'E') && isstruct(S.E) && isfield(S.E,'kind') && ...
            strcmpi(safeStr(S.E.kind),'GA_GROUP_VIDEO_EXPORT')
        E = S.E;
        return;
    end

    if isfield(S,'GA') && isstruct(S.GA) && isfield(S.GA,'kind') && ...
            strcmpi(safeStr(S.GA.kind),'GA_GROUP_VIDEO_EXPORT')
        E = S.GA;
        return;
    end

    if isstruct(S) && isfield(S,'kind') && ...
            strcmpi(safeStr(S.kind),'GA_GROUP_VIDEO_EXPORT')
        E = S;
        return;
    end

    error('Selected MAT file is not a GA_GROUP_VIDEO_EXPORT bundle.');
end
    
    function s = onoff(tf)
        if tf
            s = 'on';
        else
            s = 'off';
        end
    end

    function out = tern(cond, a, b)
        if cond
            out = a;
        else
            out = b;
        end
    end

    function s = sliceString(k, nZ0)
        if nZ0 > 1
            s = sprintf('Slice: %d / %d', k, nZ0);
        else
            s = '';
        end
    end

function syncImageAxesToCurrentFrame(C)
    if isempty(C)
        return;
    end

    h = size(C,1);
    w = size(C,2);

    set(img, ...
        'CData', C, ...
        'XData', [1 w], ...
        'YData', [1 h]);

    set(ax, ...
        'XLim', [0.5 w+0.5], ...
        'YLim', [0.5 h+0.5], ...
        'YDir', 'reverse', ...
        'Color', 'k');

    axis(ax,'image');
    axis(ax,'off');
end

    function B = makeBrushMask(x0, y0, r, ny0, nx0)
        [X,Y] = meshgrid(1:nx0, 1:ny0);
        B = (X-x0).^2 + (Y-y0).^2 <= r^2;
    end

    function U = mat2gray_safe(U)
        mn = min(U(:));
        mx = max(U(:));
        if ~isfinite(mn) || ~isfinite(mx) || mx<=mn
            U(:)=0;
            return;
        end
        U = (U - mn) ./ (mx - mn);
        U = min(max(U,0),1);
    end

    function U = clip01_percentile(A,pLow,pHigh)
        v = A(:);
        v = v(isfinite(v));
        if isempty(v)
            U = zeros(size(A));
            return;
        end
        lo = prctile_fallback(v,pLow);
        hi = prctile_fallback(v,pHigh);
        if ~isfinite(lo) || ~isfinite(hi) || hi<=lo
            U = mat2gray_safe(A);
            return;
        end
        U = A;
        U(U<lo)=lo;
        U(U>hi)=hi;
        U=(U-lo)/max(eps,(hi-lo));
        U=min(max(U,0),1);
    end

    function q = prctile_fallback(v,p)
        try
            q = prctile(v,p);
            return;
        catch
        end
        v = sort(v(:));
        n = numel(v);
        if n==0
            q=0;
            return;
        end
        k = 1 + (n-1)*(p/100);
        k1 = floor(k);
        k2 = ceil(k);
        k1 = max(1,min(n,k1));
        k2 = max(1,min(n,k2));
        if k1==k2
            q = v(k1);
        else
            q = v(k1) + (k-k1)*(v(k2)-v(k1));
        end
    end

    function loadMaskBundleCB(~,~)
        startPath = getStartPath();

        [f,p] = uigetfile( ...
            {'*.mat;*.nii;*.nii.gz', 'Mask / bundle files (*.mat,*.nii,*.nii.gz)'}, ...
            'Select mask / bundle', startPath);

        if isequal(f,0)
            return;
        end

        fullf = fullfile(p,f);

        try
            [~,~,ext] = fileparts(fullf);
            ext = lower(ext);

            if strcmp(ext,'.mat')
                S = load(fullf);
                [maskNew, includeNew, bgNew, note] = normalizeMaskInputForVideo( ...
                    S, true, bgDefaultFull, ny, nx, nZ, nVols, sliceIdx);
            else
                M = readMaskFileForVideo(fullf);
                [maskNew, includeNew, bgNew, note] = normalizeMaskInputForVideo( ...
                    M, true, bgDefaultFull, ny, nx, nZ, nVols, sliceIdx);
            end

            mask = maskNew;
            maskIsInclude = includeNew;
            bgDefaultFull = bgNew;
applyUnderlayMeta(defaultUnderlayMeta(), bgDefaultFull);

if ~state.isAtlasWarped
    origMask = mask;
    origMaskIsInclude = maskIsInclude;
    origBgDefaultFull = bgDefaultFull;
end
            underSrc = 1;
            underSrcLabel = 'Default(bg)';
            if ishandle(popUSrc)
                set(popUSrc,'Value',1);
            end

            if ishandle(popIncExc)
                if maskIsInclude
                    set(popIncExc,'Value',1);
                else
                    set(popIncExc,'Value',2);
                end
            end

            statusLine = note;
            render();

        catch ME
            errordlg(ME.message,'Load mask / bundle failed');
        end
    end

    function [maskOut, maskIsIncludeOut, bgOut, note] = normalizeMaskInputForVideo( ...
        maskIn, maskInInclude, bgIn, ny0, nx0, nZ0, nVols0, slice0)

        maskOut = false(ny0, nx0, nZ0, nVols0);
        maskIsIncludeOut = true;
        bgOut = bgIn;
        note = '';

        if nargin >= 2 && ~isempty(maskInInclude)
            try
                maskIsIncludeOut = logical(maskInInclude);
            catch
                maskIsIncludeOut = true;
            end
        end

        if isempty(maskIn)
            return;
        end

        if isstruct(maskIn)
            S = maskIn;
            if isfield(S,'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle)
                S = S.maskBundle;
            end

            pickedField = '';
            M = [];

            overlayFields = {'loadedMask','overlayMask','signalMask','mask','activeMask'};
            for k = 1:numel(overlayFields)
                fn = overlayFields{k};
                if isfield(S,fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
                    M = S.(fn);
                    pickedField = fn;
                    break;
                end
            end

            if isempty(M)
                brainFields = {'brainMask','underlayMask'};
                for k = 1:numel(brainFields)
                    fn = brainFields{k};
                    if isfield(S,fn) && ~isempty(S.(fn)) && (isnumeric(S.(fn)) || islogical(S.(fn)))
                        M = S.(fn);
                        pickedField = fn;
                        break;
                    end
                end
            end

            if isempty(M)
                error('No usable overlay / brain mask field found in bundle.');
            end

            if any(strcmpi(pickedField, {'loadedMask','overlayMask','signalMask'}))
                if isfield(S,'overlayMaskIsInclude') && ~isempty(S.overlayMaskIsInclude)
                    maskIsIncludeOut = logical(S.overlayMaskIsInclude);
                elseif isfield(S,'loadedMaskIsInclude') && ~isempty(S.loadedMaskIsInclude)
                    maskIsIncludeOut = logical(S.loadedMaskIsInclude);
                elseif isfield(S,'maskIsInclude') && ~isempty(S.maskIsInclude)
                    maskIsIncludeOut = logical(S.maskIsInclude);
                else
                    maskIsIncludeOut = true;
                end
            else
                if isfield(S,'brainMaskIsInclude') && ~isempty(S.brainMaskIsInclude)
                    maskIsIncludeOut = logical(S.brainMaskIsInclude);
                elseif isfield(S,'maskIsInclude') && ~isempty(S.maskIsInclude)
                    maskIsIncludeOut = logical(S.maskIsInclude);
                else
                    maskIsIncludeOut = true;
                end
            end

            maskOut = expandMaskToVideoSize(M, ny0, nx0, nZ0, nVols0, slice0);

        bgOut = bgIn;

if isfield(S,'anatomical_reference') && ~isempty(S.anatomical_reference) && isnumeric(S.anatomical_reference)
    bgOut = fitBundleUnderlayToVideo(double(S.anatomical_reference), bgIn, ny0, nx0, nZ0);
elseif isfield(S,'brainImage') && ~isempty(S.brainImage) && isnumeric(S.brainImage)
    bgOut = fitBundleUnderlayToVideo(double(S.brainImage), bgIn, ny0, nx0, nZ0);
elseif isfield(S,'anatomical_reference_raw') && ~isempty(S.anatomical_reference_raw) && isnumeric(S.anatomical_reference_raw)
    bgOut = fitBundleUnderlayToVideo(double(S.anatomical_reference_raw), bgIn, ny0, nx0, nZ0);
end

            note = ['Loaded bundle mask: ' pickedField];
            return;
        end

        if ~(isnumeric(maskIn) || islogical(maskIn))
            error('Mask input must be numeric, logical, or a bundle struct.');
        end

        maskOut = expandMaskToVideoSize(maskIn, ny0, nx0, nZ0, nVols0, slice0);

        if ndims(maskIn) == 2
            note = '2D mask expanded to all volumes (current slice).';
        elseif ndims(maskIn) == 3
            note = '3D mask expanded for video display.';
        elseif ndims(maskIn) == 4
            note = '4D mask restored.';
        else
            note = 'Mask restored.';
        end
    end

    function M4 = expandMaskToVideoSize(Min, ny0, nx0, nZ0, nVols0, slice0)
        Min = logical(Min);

        if ndims(Min) == 2
            M2 = resizeLogical2D(Min, ny0, nx0);
            M4 = false(ny0, nx0, nZ0, nVols0);
            M4(:,:,slice0,:) = repmat(M2, [1 1 1 nVols0]);
            return;
        end

        if ndims(Min) == 3
            n3 = size(Min,3);

            if size(Min,1) ~= ny0 || size(Min,2) ~= nx0
                tmp = false(ny0, nx0, n3);
                for kk = 1:n3
                    tmp(:,:,kk) = resizeLogical2D(Min(:,:,kk), ny0, nx0);
                end
                Min = tmp;
            end

            if n3 == nZ0
                M4 = false(ny0, nx0, nZ0, nVols0);
                for zz = 1:nZ0
                    M4(:,:,zz,:) = repmat(Min(:,:,zz), [1 1 1 nVols0]);
                end
                return;
            end

            if nZ0 == 1 && n3 == nVols0
                M4 = false(ny0, nx0, 1, nVols0);
                M4(:,:,1,:) = reshape(Min, [ny0 nx0 1 nVols0]);
                return;
            end

            M2 = any(Min, 3);
            M4 = false(ny0, nx0, nZ0, nVols0);
            M4(:,:,slice0,:) = repmat(M2, [1 1 1 nVols0]);
            return;
        end

        while ndims(Min) > 4
            Min = any(Min, ndims(Min));
        end

        if ndims(Min) == 4
            if isequal(size(Min), [ny0 nx0 nZ0 nVols0])
                M4 = logical(Min);
                return;
            end

            if size(Min,3) == nZ0 && size(Min,4) == nVols0
                M4 = false(ny0, nx0, nZ0, nVols0);
                for zz = 1:nZ0
                    for tt = 1:nVols0
                        M4(:,:,zz,tt) = resizeLogical2D(Min(:,:,zz,tt), ny0, nx0);
                    end
                end
                return;
            end

            tmp = any(Min, 4);
            M4 = expandMaskToVideoSize(tmp, ny0, nx0, nZ0, nVols0, slice0);
            return;
        end

        error('Unsupported mask dimensionality.');
    end

    function M2 = resizeLogical2D(M0, ny0, nx0)
        if size(M0,1) == ny0 && size(M0,2) == nx0
            M2 = logical(M0);
            return;
        end

        try
            M2 = imresize(double(M0), [ny0 nx0], 'nearest') > 0.5;
        catch
            M2 = false(ny0, nx0);
            yUse = min(ny0, size(M0,1));
            xUse = min(nx0, size(M0,2));
            M2(1:yUse,1:xUse) = logical(M0(1:yUse,1:xUse));
        end
    end

 function bgOut = fitBundleUnderlayToVideo(Uin, bgFallback, ny0, nx0, nZ0)
    bgOut = bgFallback;

    if isempty(Uin) || ~isnumeric(Uin)
        return;
    end

    U = double(Uin);

    % ---------------- 2D ----------------
    if ndims(U) == 2
        if size(U,1) == ny0 && size(U,2) == nx0
            bgOut = U;
        else
            try
                bgOut = imresize(U, [ny0 nx0], 'bilinear');
            catch
                bgOut = bgFallback;
            end
        end
        return;
    end

    % ---------------- 3D ----------------
    if ndims(U) == 3
        % single-slice RGB ONLY if nZ0 == 1
        if nZ0 == 1 && size(U,3) == 3
            if size(U,1) == ny0 && size(U,2) == nx0
                bgOut = U;
            else
                try
                    tmp = zeros(ny0, nx0, 3);
                    for cc = 1:3
                        tmp(:,:,cc) = imresize(U(:,:,cc), [ny0 nx0], 'bilinear');
                    end
                    bgOut = tmp;
                catch
                    bgOut = bgFallback;
                end
            end
            return;
        end

        % grayscale stack [Y X Z]
        n3 = size(U,3);
        tmp = zeros(ny0, nx0, n3);
        for kk = 1:n3
            if size(U,1) == ny0 && size(U,2) == nx0
                tmp(:,:,kk) = U(:,:,kk);
            else
                try
                    tmp(:,:,kk) = imresize(U(:,:,kk), [ny0 nx0], 'bilinear');
                catch
                    tmp(:,:,kk) = 0;
                end
            end
        end

        if nZ0 > 1 && n3 == nZ0
            bgOut = tmp;
        elseif nZ0 == 1
            bgOut = tmp(:,:,1);
        else
            idx = round(linspace(1, n3, nZ0));
            idx = max(1, min(n3, idx));
            bgOut = tmp(:,:,idx);
        end
        return;
    end

    % ---------------- 4D RGB stack [Y X 3 Z] ----------------
    if ndims(U) == 4 && size(U,3) == 3
        n4 = size(U,4);
        tmp = zeros(ny0, nx0, 3, n4);
        for zz = 1:n4
            for cc = 1:3
                if size(U,1) == ny0 && size(U,2) == nx0
                    tmp(:,:,cc,zz) = U(:,:,cc,zz);
                else
                    try
                        tmp(:,:,cc,zz) = imresize(U(:,:,cc,zz), [ny0 nx0], 'bilinear');
                    catch
                        tmp(:,:,cc,zz) = 0;
                    end
                end
            end
        end

        if nZ0 == 1
            bgOut = squeeze(tmp(:,:,:,1));
        else
            if n4 == nZ0
                bgOut = tmp;
            elseif n4 == 1
                bgOut = repmat(tmp, [1 1 1 nZ0]);
            else
                idx = round(linspace(1, n4, nZ0));
                idx = max(1, min(n4, idx));
                bgOut = tmp(:,:,:,idx);
            end
        end
        return;
    end
 end

    function M = readMaskFileForVideo(f)
        if ~exist(f,'file')
            error('Mask file not found: %s', f);
        end

        isNiiGz = numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz');

        if isNiiGz
            tmpDir = tempname;
            mkdir(tmpDir);
            gunzip(f, tmpDir);
            d = dir(fullfile(tmpDir, '*.nii'));
            if isempty(d)
                error('gunzip failed for: %s', f);
            end
            niiFile = fullfile(tmpDir, d(1).name);
            M = logical(niftiread(niiFile));
            try, rmdir(tmpDir,'s'); catch, end
            return;
        end

        [~,~,ext] = fileparts(f);
        ext = lower(ext);

        if strcmp(ext,'.nii')
            M = logical(niftiread(f));
            return;
        end

        if strcmp(ext,'.mat')
            S = load(f); %#ok<NASGU>
            error('Internal MAT load path should not call readMaskFileForVideo directly.');
        end

        error('Unsupported mask file type: %s', ext);
    end

    function BM = deriveBrainMaskFromUnderlayVideo(bgIn, ny0, nx0, nZ0)
        BM = [];

        if isempty(bgIn) || ~(isnumeric(bgIn) || islogical(bgIn))
            return;
        end

        U = double(bgIn);

        if ndims(U) == 3 && size(U,3) == 3
            U = toGray(U);
        end

        if ndims(U) == 2
            BM = U ~= 0;
            if size(BM,1) ~= ny0 || size(BM,2) ~= nx0
                BM = resizeLogical2D(BM, ny0, nx0);
            end
            if nZ0 > 1
                BM = repmat(BM, [1 1 nZ0]);
            end
            return;
        end

        if ndims(U) == 3
            n3 = size(U,3);
            tmp = false(ny0, nx0, n3);
            for kk = 1:n3
                tmp(:,:,kk) = resizeLogical2D(U(:,:,kk) ~= 0, ny0, nx0);
            end

            if nZ0 > 1 && n3 == nZ0
                BM = tmp;
            else
                BM = any(tmp, 3);
                if nZ0 > 1
                    BM = repmat(BM, [1 1 nZ0]);
                end
            end
            return;
        end

        while ndims(U) > 3
            U = mean(U, ndims(U));
        end

        if ndims(U) == 3
            BM = deriveBrainMaskFromUnderlayVideo(U, ny0, nx0, nZ0);
        else
            BM = [];
        end
    end

    function startPath = getStartPath()
        startPath = '';

        candDirs = {};

        try
            if isstruct(par)
                if isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir') == 7
                    candDirs{end+1} = char(par.exportPath);
                end
                if isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath,'dir') == 7
                    candDirs{end+1} = char(par.loadedPath);
                end
                if isfield(par,'rawPath') && ~isempty(par.rawPath) && exist(par.rawPath,'dir') == 7
                    candDirs{end+1} = char(par.rawPath);
                end
                if isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                    lf = char(par.loadedFile);
                    if exist(lf,'file') == 2
                        candDirs{end+1} = fileparts(lf);
                    end
                end
            end
        catch
        end

        candDirs{end+1} = pwd;

        for ii = 1:numel(candDirs)
            d = candDirs{ii};
            try
                if ~isempty(d) && exist(d,'dir') == 7
                    startPath = d;
                    return;
                end
            catch
            end
        end

        startPath = pwd;
    end

   function warpFunctionalToAtlasCB(~,~)
    startDir = getUnderlayStartPath();

    [f,p] = uigetfile({'*.mat','Transform files (*.mat)'}, ...
        'Select atlas Transformation / CoronalRegistration2D', startDir);

    if isequal(f,0)
        return;
    end

    try
        S = load(fullfile(p,f));
        T = extractAtlasWarpStruct(S);

        % Warp ONLY the functional data
        Inew        = warpDataSeriesToAtlas(origI,        T, sliceIdx);
        IinterpNew  = warpDataSeriesToAtlas(origI_interp, T, sliceIdx);
        PSCnew      = warpDataSeriesToAtlas(origPSC,      T, sliceIdx);

        % Commit only after successful warp
        I        = Inew;
        I_interp = IinterpNew;
        PSC      = PSCnew;

        % IMPORTANT:
        % Keep currently loaded underlay unchanged.
        % Do NOT warp bgDefaultFull here, because it may already be atlas-space.
        % This was the source of the mismatch vs SCM GUI.

        state.isAtlasWarped = true;
        state.atlasTransformFile = fullfile(p,f);
        state.lastAtlasTransformFile = state.atlasTransformFile;

        % Recompute dimensions after PSC warp
        resetAfterDataSpaceChange(false);

        underSrc = 1;
        underSrcLabel = 'Default(bg)';
        if ishandle(popUSrc)
            set(popUSrc,'Value',1);
        end

        try
            if isfield(T,'type') && strcmpi(char(T.type),'simple_coronal_2d') && ...
                    isfield(T,'atlasSliceIndex') && isfinite(T.atlasSliceIndex)
                set(txtTitle,'String',sprintf('%s | warped to atlas coronal slice %d', ...
                    safeStr(fileLabel), round(T.atlasSliceIndex)));
            else
                set(txtTitle,'String',sprintf('%s | warped to atlas', safeStr(fileLabel)));
            end
        catch
            set(txtTitle,'String',sprintf('%s | warped to atlas', safeStr(fileLabel)));
        end

        statusLine = 'Functional data warped to atlas.';
        render();

    catch ME
        errordlg(ME.message,'Atlas warp failed');
    end
end

function resetWarpToNativeCB(~,~)
    try
        I            = origI;
        I_interp     = origI_interp;
        PSC          = origPSC;
        bgDefaultFull = origBgDefaultFull;

        state.isAtlasWarped = false;
        state.atlasTransformFile = '';

        applyUnderlayMeta(defaultUnderlayMeta(), bgDefaultFull);

        mask = origMask;
        maskIsInclude = origMaskIsInclude;

        underSrc = 1;
        underSrcLabel = 'Default(bg)';
        if ishandle(popUSrc)
            set(popUSrc,'Value',1);
        end
        if ishandle(popIncExc)
            set(popIncExc,'Value', tern(maskIsInclude,1,2));
        end

        set(txtTitle,'String',safeStr(fileLabel));

        resetAfterDataSpaceChange(false);

        statusLine = 'Returned to native functional space.';
        render();

    catch ME
        errordlg(ME.message,'Reset to native failed');
    end
end

    function resetAfterDataSpaceChange(clearMaskNow)
    if nargin < 1
        clearMaskNow = false;
    end

    bgMeanFull = [];
    bgMedianFull = [];
    bgFileFull = [];

    ndPSC = ndims(PSC);
    switch ndPSC
        case 4
            [ny, nx, nZ, nFrames] = size(PSC);
            nVols = size(PSC,4);
        case 3
            [ny, nx, nFrames] = size(PSC);
            nZ = 1;
            nVols = size(PSC,3);
        case 2
            [ny, nx] = size(PSC);
            nZ = 1;
            nFrames = 1;
            nVols = 1;
        otherwise
            error('PSC must be 2D, 3D or 4D after space change.');
    end

    sliceIdx = max(1, min(nZ, round(sliceIdx)));
    volume   = max(1, min(nVols, volume));
    frame    = (volume - 1) * par.interpol + 1;
    frame    = max(1, min(nFrames, round(frame)));

    if clearMaskNow || isempty(mask) || ~isequal(size(mask), [ny nx nZ nVols])
        mask = false(ny, nx, nZ, nVols);
        maskIsInclude = true;
        if ishandle(popIncExc)
            set(popIncExc,'Value',1);
        end
    end

    try
        set(slVol,'Min',1,'Max',max(1,nVols),'Value',volume);
        set(txtVol,'String',sprintf('%d / %d',volume,nVols));
    catch
    end

    try
        txtSliceAx.String = sliceString(sliceIdx,nZ);
        set(txtSliceTop,'String',sliceString(sliceIdx,nZ));
    catch
    end
end

function T = extractAtlasWarpStruct(S)
    if isfield(S,'Transf') && isstruct(S.Transf)
        T = S.Transf;
    elseif isfield(S,'Reg2D') && isstruct(S.Reg2D)
        T = S.Reg2D;
    else
        T = S;
    end

    if isfield(T,'A') && ~isempty(T.A)
        T.warpA = T.A;
    elseif isfield(T,'M') && ~isempty(T.M)
        T.warpA = T.M;
    elseif isfield(T,'T') && ~isempty(T.T)
        T.warpA = T.T;
    elseif isfield(T,'tform') && ~isempty(T.tform)
        T.warpA = T.tform.T;
    else
        error('Transform file has no usable matrix field.');
    end

    if isfield(T,'outputSize') && ~isempty(T.outputSize)
        T.outSize = double(T.outputSize);
    elseif isfield(T,'size') && ~isempty(T.size)
        T.outSize = double(T.size);
    elseif isfield(T,'atlasSize') && ~isempty(T.atlasSize)
        T.outSize = double(T.atlasSize);
    elseif isfield(T,'outSize') && ~isempty(T.outSize)
        T.outSize = double(T.outSize);
    else
        T.outSize = [];
    end

    if ~isfield(T,'type') || isempty(T.type)
        T.type = 'unknown';
    end
    if ~isfield(T,'atlasSliceIndex') || isempty(T.atlasSliceIndex)
        T.atlasSliceIndex = NaN;
    end
end

function Y = warpDataSeriesToAtlas(X, T, zSel)
    A = double(T.warpA);

    if isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3
            error('3D atlas warp requires output size.');
        end

        outSize3 = round(T.outSize(1:3));
        tform3 = affine3d(A);
        Rout3  = imref3d(outSize3);

        if ndims(X) == 4
            nTT = size(X,4);
            Y = zeros([outSize3 nTT], 'single');
            for tt = 1:nTT
                Y(:,:,:,tt) = imwarp(single(X(:,:,:,tt)), tform3, 'linear', 'OutputView', Rout3);
            end
            return;
        end

        error('3D warp currently expects [Y X Z T].');
    end

    if isequal(size(A), [3 3])
        if isempty(T.outSize) || numel(T.outSize) < 2
            error('2D atlas warp requires output size.');
        end

        outSize2 = round(T.outSize(1:2));
        tform2 = affine2d(A);
        Rout2  = imref2d(outSize2);

        if ndims(X) == 3
            nTT = size(X,3);
            Y = zeros([outSize2 nTT], 'single');
            for tt = 1:nTT
                Y(:,:,tt) = imwarp(single(X(:,:,tt)), tform2, 'linear', 'OutputView', Rout2);
            end
            return;
        elseif ndims(X) == 4
            zSel = max(1, min(size(X,3), zSel));
            X2   = squeeze(X(:,:,zSel,:));
            nTT = size(X2,3);
            Y = zeros([outSize2 nTT], 'single');
            for tt = 1:nTT
                Y(:,:,tt) = imwarp(single(X2(:,:,tt)), tform2, 'linear', 'OutputView', Rout2);
            end
            return;
        elseif ndims(X) == 2
            Y = imwarp(single(X), tform2, 'linear', 'OutputView', Rout2);
            return;
        end
    end

    error('Unsupported transform matrix size.');
end

function loadNewUnderlayCB(~,~)
    ensureUnderlayStateFields();
    startPath = getUnderlayStartPath();

    [f,p] = uigetfile( ...
        {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.jpeg,*.tif,*.tiff,*.bmp)'}, ...
        'Select new underlay', startPath);

    if isequal(f,0)
        return;
    end

    fullf = fullfile(p,f);

    try
        [Uraw, meta] = readUnderlayFile(fullf);
        Uraw = squeeze(Uraw);

        if state.isAtlasWarped
            if doesUnderlayMatchCurrentDisplay(Uraw)
                bgDefaultFull = validateAndPrepareUnderlay(Uraw, fullf);
                applyUnderlayMeta(meta, bgDefaultFull);
                underSrc = 1;
                underSrcLabel = 'Default(bg)';
                set(popUSrc,'Value',1);
                statusLine = ['Loaded atlas-space underlay: ' fullf];
                render();
                return;

            elseif doesUnderlayMatchOriginalDisplay(Uraw)
                tfFile = getBestTransformForUnderlay(fullf);
                if isempty(tfFile) || exist(tfFile,'file') ~= 2
                    error('Current video is atlas-warped, but no transform file was found to warp the selected native underlay.');
                end

                S = load(tfFile);
                T = extractAtlasWarpStruct(S);

                U = warpUnderlayForCurrentDisplay(Uraw, T, sliceIdx);
                bgDefaultFull = validateAndPrepareUnderlay(U, fullf);
                applyUnderlayMeta(meta, bgDefaultFull);

                underSrc = 1;
                underSrcLabel = 'Default(bg)';
                set(popUSrc,'Value',1);

                statusLine = ['Loaded warped atlas underlay: ' fullf];
                render();
                return;
            else
                error('Selected underlay does not match current atlas display or original native display.');
            end
        end

        % native mode
        if doesUnderlayMatchCurrentDisplay(Uraw)
            bgDefaultFull = validateAndPrepareUnderlay(Uraw, fullf);
            applyUnderlayMeta(meta, bgDefaultFull);

            origBgDefaultFull = bgDefaultFull;

            underSrc = 1;
            underSrcLabel = 'Default(bg)';
            set(popUSrc,'Value',1);

            statusLine = ['Loaded native underlay: ' fullf];
            render();
            return;
        end

        % atlas underlay loaded while still in native mode -> auto warp functional
        tfFile = getBestTransformForUnderlay(fullf);
        if isempty(tfFile) || exist(tfFile,'file') ~= 2
            [ft,pt] = uigetfile({'*.mat','Transform files (*.mat)'}, ...
                'Selected underlay looks atlas-sized. Select transform file', getUnderlayStartPath());
            if isequal(ft,0)
                return;
            end
            tfFile = fullfile(pt,ft);
        end

        S = load(tfFile);
        T = extractAtlasWarpStruct(S);

        if ~doesUnderlayMatchTransformOutput(Uraw, T)
            error('Selected underlay does not match native display and also does not match transform output size.');
        end

       Inew        = warpDataSeriesToAtlas(origI,        T, sliceIdx);
IinterpNew  = warpDataSeriesToAtlas(origI_interp, T, sliceIdx);
PSCnew      = warpDataSeriesToAtlas(origPSC,      T, sliceIdx);

ndNew = ndims(PSCnew);
switch ndNew
    case 4
        [nyNew, nxNew, nZNew, ~] = size(PSCnew);
    case 3
        [nyNew, nxNew, ~] = size(PSCnew);
        nZNew = 1;
    case 2
        [nyNew, nxNew] = size(PSCnew);
        nZNew = 1;
    otherwise
        error('Warped PSC has unsupported dimensionality.');
end

bgAtlas = validateAndPrepareUnderlay(Uraw, fullf, nyNew, nxNew, nZNew);

I        = Inew;
I_interp = IinterpNew;
PSC      = PSCnew;

state.isAtlasWarped = true;
state.atlasTransformFile = tfFile;
state.lastAtlasTransformFile = tfFile;

bgDefaultFull = bgAtlas;
applyUnderlayMeta(meta, bgDefaultFull);

        underSrc = 1;
        underSrcLabel = 'Default(bg)';
        set(popUSrc,'Value',1);

        mask = [];
        maskIsInclude = true;

        resetAfterDataSpaceChange(true);

        try
            if isfield(T,'type') && strcmpi(char(T.type),'simple_coronal_2d') ...
                    && isfield(T,'atlasSliceIndex') && isfinite(T.atlasSliceIndex)
                set(txtTitle,'String',sprintf('%s | warped to atlas coronal slice %d', ...
                    safeStr(fileLabel), round(T.atlasSliceIndex)));
            else
                set(txtTitle,'String',sprintf('%s | warped to atlas', safeStr(fileLabel)));
            end
        catch
            set(txtTitle,'String',sprintf('%s | warped to atlas', safeStr(fileLabel)));
        end

        statusLine = ['Loaded atlas underlay and warped functional: ' fullf];
        render();

    catch ME
        errordlg(ME.message,'Load underlay failed');
    end
end

    function U = validateAndPrepareUnderlay(U, fullf, nyTarget, nxTarget, nZTarget)
    U = squeeze(U);

    if isempty(U) || ~(isnumeric(U) || islogical(U))
        error('Loaded underlay is not numeric: %s', fullf);
    end

    if nargin < 3 || isempty(nyTarget), nyTarget = ny; end
    if nargin < 4 || isempty(nxTarget), nxTarget = nx; end
    if nargin < 5 || isempty(nZTarget), nZTarget = nZ; end

    U = double(U);
    U = fitUnderlayToCurrentDisplay(U, nyTarget, nxTarget, nZTarget);
end
    function Uout = fitUnderlayToCurrentDisplay(Uin, ny0, nx0, nZ0)
    U = squeeze(double(Uin));

    % ---------------- RGB 2D ----------------
    if ndims(U) == 3 && size(U,3) == 3
        if size(U,1) == ny0 && size(U,2) == nx0
            Uout = U;
            return;
        end

        if size(U,1) == nx0 && size(U,2) == ny0
            Uout = permute(U, [2 1 3]);
            return;
        end

        Uout = zeros(ny0, nx0, 3, 'double');
        for cc = 1:3
            Uout(:,:,cc) = centerCropPad2D(U(:,:,cc), ny0, nx0);
        end
        return;
    end

    % ---------------- 2D grayscale / labels ----------------
    if ndims(U) == 2
        if size(U,1) == ny0 && size(U,2) == nx0
            Uout = U;
            return;
        end

        if size(U,1) == nx0 && size(U,2) == ny0
            Uout = U.';
            return;
        end

        Uout = centerCropPad2D(U, ny0, nx0);
        return;
    end

    % ---------------- 3D grayscale stack ----------------
    if ndims(U) == 3
        if size(U,1) == nx0 && size(U,2) == ny0
            U = permute(U, [2 1 3]);
        end

        n3 = size(U,3);

        tmp = zeros(ny0, nx0, n3, 'double');
        for kk = 1:n3
            tmp(:,:,kk) = centerCropPad2D(U(:,:,kk), ny0, nx0);
        end

        if n3 == nZ0
            Uout = tmp;
        elseif nZ0 == 1
            Uout = tmp(:,:,max(1, min(n3, 1)));
        else
            idx = round(linspace(1, n3, nZ0));
            idx = max(1, min(n3, idx));
            Uout = tmp(:,:,idx);
        end
        return;
    end

    error('Unsupported underlay dimensionality after squeeze.');
end

function Aout = centerCropPad2D(Ain, nyT, nxT)
    Ain = double(Ain);
    [nyA, nxA] = size(Ain);

    Aout = zeros(nyT, nxT, 'double');

    yCopy = min(nyA, nyT);
    xCopy = min(nxA, nxT);

    yA1 = floor((nyA - yCopy)/2) + 1;
    xA1 = floor((nxA - xCopy)/2) + 1;

    yT1 = floor((nyT - yCopy)/2) + 1;
    xT1 = floor((nxT - xCopy)/2) + 1;

    Aout(yT1:yT1+yCopy-1, xT1:xT1+xCopy-1) = ...
        Ain(yA1:yA1+yCopy-1, xA1:xA1+xCopy-1);
end

function Lout = fitRegionLabelsToCurrentDisplay(Lin, ny0, nx0)
    L = squeeze(double(Lin));

    if isempty(L)
        Lout = [];
        return;
    end

    if ndims(L) ~= 2
        while ndims(L) > 2
            L = L(:,:,1);
        end
    end

    if size(L,1) == ny0 && size(L,2) == nx0
        Lout = L;
        return;
    end

    if size(L,1) == nx0 && size(L,2) == ny0
        Lout = L.';
        return;
    end

    Lout = imresize(L, [ny0 nx0], 'nearest');
end

    function rgb = forceRgbToSize(rgbIn, ny0, nx0)
    rgb = double(rgbIn);

    if ndims(rgb) == 3 && size(rgb,3) == 3
        if size(rgb,1) == ny0 && size(rgb,2) == nx0
            return;
        end

        if size(rgb,1) == nx0 && size(rgb,2) == ny0
            rgb = permute(rgb, [2 1 3]);
            return;
        end

        tmp = zeros(ny0, nx0, 3, 'double');
        for cc = 1:3
            tmp(:,:,cc) = centerCropPad2D(rgb(:,:,cc), ny0, nx0);
        end
        rgb = tmp;
        return;
    end

    error('forceRgbToSize expected RGB image.');
end

function applyUnderlayMeta(meta, U)
    ensureUnderlayStateFields();

    state.isColorUnderlay     = false;
    state.regionLabelUnderlay = [];
    state.regionColorLUT      = [];
    state.regionInfo          = struct();

    if nargin >= 1 && isstruct(meta)
        if isfield(meta,'isColor') && ~isempty(meta.isColor)
            state.isColorUnderlay = logical(meta.isColor);
        end
        if isfield(meta,'regionLabels') && ~isempty(meta.regionLabels)
    state.regionLabelUnderlay = fitRegionLabelsToCurrentDisplay(meta.regionLabels, ny, nx);
    state.isColorUnderlay = true;
end
        if isfield(meta,'regionInfo') && ~isempty(meta.regionInfo)
            state.regionInfo = meta.regionInfo;
        end
    end

if nargin >= 2 && ~state.isColorUnderlay
    if (nZ == 1) && ndims(U) == 3 && size(U,3) == 3
        state.isColorUnderlay = true;   % single-slice RGB
    elseif ndims(U) == 4 && size(U,3) == 3
        state.isColorUnderlay = true;   % RGB stack [Y X 3 Z]
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
        if ~isempty(state.atlasTransformFile) && exist(state.atlasTransformFile,'file') == 2
            cand{end+1} = char(state.atlasTransformFile);
        end
    catch
    end

    try
        if ~isempty(state.lastAtlasTransformFile) && exist(state.lastAtlasTransformFile,'file') == 2
            cand{end+1} = char(state.lastAtlasTransformFile);
        end
    catch
    end

    try
        udir = fileparts(char(underlayFile));
        cand{end+1} = fullfile(udir,'CoronalRegistration2D.mat');
        cand{end+1} = fullfile(udir,'Transformation.mat');

        p1 = fileparts(udir);
        cand{end+1} = fullfile(p1,'Registration2D','CoronalRegistration2D.mat');
        cand{end+1} = fullfile(p1,'Registration','Transformation.mat');
        cand{end+1} = fullfile(p1,'CoronalRegistration2D.mat');
        cand{end+1} = fullfile(p1,'Transformation.mat');
    catch
    end

    try
        if isstruct(par) && isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir') == 7
            ep = char(par.exportPath);
            cand{end+1} = fullfile(ep,'Registration2D','CoronalRegistration2D.mat');
            cand{end+1} = fullfile(ep,'Registration','Transformation.mat');
        end
    catch
    end

    for ii = 1:numel(cand)
        try
            if ~isempty(cand{ii}) && exist(cand{ii},'file') == 2
                tfFile = cand{ii};
                return;
            end
        catch
        end
    end
end

function startPath = getUnderlayStartPath()
    startPath = getStartPath();

    try
        if state.isAtlasWarped && ~isempty(state.atlasTransformFile) && exist(state.atlasTransformFile,'file') == 2
            startPath = fileparts(state.atlasTransformFile);
            return;
        end
    catch
    end
end

function [U, meta] = readUnderlayFile(f)
    if ~exist(f,'file')
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
        try, rmdir(tmpDir,'s'); catch, end
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
            end
            U = double(U);

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

    % =====================================================
    % 1) DIRECT support for Group Analysis video export MAT
    %    saved as: save(...,'E','-v7.3')
    % =====================================================
    if isfield(S,'E') && isstruct(S.E)
        [ok,U,meta] = tryExtractSpecialUnderlayStruct(S.E, meta);
        if ok
            return;
        end
    end

    % Also support files saved directly as struct fields (no E wrapper)
    [ok,U,meta] = tryExtractSpecialUnderlayStruct(S, meta);
    if ok
        return;
    end

    % =====================================================
    % 2) Existing atlas/regions logic
    % =====================================================
    if isfield(S,'atlasMode') && ~isempty(S.atlasMode)
        try
            meta.atlasMode = char(S.atlasMode);
        catch
            meta.atlasMode = '';
        end
    end

    if strcmpi(meta.atlasMode,'regions')
        if isfield(S,'atlasUnderlayRGB') && ~isempty(S.atlasUnderlayRGB)
            U = double(S.atlasUnderlayRGB);
            meta.isColor = true;
        elseif isfield(S,'brainImage') && ~isempty(S.brainImage)
            U = double(S.brainImage);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
        else
            error('Regions MAT file has no atlasUnderlayRGB / brainImage.');
        end

        if isfield(S,'atlasRegionLabels2D') && ~isempty(S.atlasRegionLabels2D)
            meta.regionLabels = double(S.atlasRegionLabels2D);
        elseif isfield(S,'atlasUnderlay') && ~isempty(S.atlasUnderlay)
            meta.regionLabels = double(S.atlasUnderlay);
        end

        if isfield(S,'atlasInfoRegions') && ~isempty(S.atlasInfoRegions)
            meta.regionInfo = S.atlasInfoRegions;
        elseif isfield(S,'infoRegions') && ~isempty(S.infoRegions)
            meta.regionInfo = S.infoRegions;
        end
        return;
    end

    % =====================================================
    % 3) Generic preferred fields
    % =====================================================
    pref = { ...
        'underlay2D', ...
        'brainImage', ...
        'atlasUnderlayRGB', ...
        'underlay', ...
        'bg', ...
        'img', ...
        'I', ...
        'atlasUnderlay', ...
        'vascular', ...
        'histology', ...
        'regions', ...
        'Data'};

    for ii = 1:numel(pref)
        fn = pref{ii};
        if isfield(S,fn)
            v = S.(fn);

            if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
                U = double(v.Data);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                return;
            elseif (isnumeric(v) || islogical(v)) && ~isempty(v)
                U = double(v);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                return;
            end
        end
    end

    % =====================================================
    % 4) Last fallback: first usable numeric field
    % =====================================================
    fn = fieldnames(S);
    for ii = 1:numel(fn)
        v = S.(fn{ii});

        if isstruct(v)
            if isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
                U = double(v.Data);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                return;
            end
        elseif (isnumeric(v) || islogical(v)) && ~isempty(v)
            U = double(v);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
            return;
        end
    end

    error('MAT underlay file has no usable numeric variable.');
    end

function [ok, U, meta] = tryExtractSpecialUnderlayStruct(X, meta)
    ok = false;
    U = [];

    if ~isstruct(X)
        return;
    end

    % -----------------------------------------------
    % Group Analysis video export bundle
    % -----------------------------------------------
   if isfield(X,'kind') && strcmpi(strtrim(safeStr(X.kind)),'GA_GROUP_VIDEO_EXPORT')
        % Preferred underlay
        if isfield(X,'underlay2D') && ~isempty(X.underlay2D) && ...
                (isnumeric(X.underlay2D) || islogical(X.underlay2D))
            U = double(X.underlay2D);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
            meta.atlasMode = 'ga_group_video_export';
            ok = true;
            return;
        end

        % Fallbacks just in case
        if isfield(X,'brainImage') && ~isempty(X.brainImage) && ...
                (isnumeric(X.brainImage) || islogical(X.brainImage))
            U = double(X.brainImage);
            if ndims(U) == 3 && size(U,3) == 3
                meta.isColor = true;
            end
            meta.atlasMode = 'ga_group_video_export';
            ok = true;
            return;
        end

        if isfield(X,'groupMap2D') && ~isempty(X.groupMap2D) && ...
                (isnumeric(X.groupMap2D) || islogical(X.groupMap2D))
            U = double(X.groupMap2D);
            meta.atlasMode = 'ga_group_video_export';
            ok = true;
            return;
        end
    end

    % -----------------------------------------------
    % Generic nested struct with useful underlay names
    % -----------------------------------------------
    cand = {'underlay2D','brainImage','atlasUnderlayRGB','underlay','bg','img','I','Data'};
    for k = 1:numel(cand)
        fn = cand{k};
        if isfield(X,fn)
            v = X.(fn);
            if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
                U = double(v.Data);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                ok = true;
                return;
            elseif (isnumeric(v) || islogical(v)) && ~isempty(v)
                U = double(v);
                if ndims(U) == 3 && size(U,3) == 3
                    meta.isColor = true;
                end
                ok = true;
                return;
            end
        end
    end
end


function Uout = warpUnderlayForCurrentDisplay(Uin, T, zSel)
    A = double(T.warpA);

    if isequal(size(A), [3 3])
        if isempty(T.outSize) || numel(T.outSize) < 2
            error('2D underlay warp requires output size.');
        end

        outSize2 = round(T.outSize(1:2));
        tform2 = affine2d(A);
        Rout2  = imref2d(outSize2);

        if ndims(Uin) == 2
            Uout = imwarp(single(Uin), tform2, 'linear', 'OutputView', Rout2);
            return;
        end

        if ndims(Uin) == 3
            if size(Uin,3) == 3
                Uout = zeros([outSize2 3], 'single');
                for cc = 1:3
                    Uout(:,:,cc) = imwarp(single(Uin(:,:,cc)), tform2, 'linear', 'OutputView', Rout2);
                end
                return;
            else
                zSel = max(1, min(size(Uin,3), zSel));
                Uout = imwarp(single(Uin(:,:,zSel)), tform2, 'linear', 'OutputView', Rout2);
                return;
            end
        end
    end

    if isequal(size(A), [4 4])
        if isempty(T.outSize) || numel(T.outSize) < 3
            error('3D underlay warp requires output size.');
        end

        outSize3 = round(T.outSize(1:3));
        tform3 = affine3d(A);
        Rout3  = imref3d(outSize3);

        if ndims(Uin) == 3
            Uout = imwarp(single(Uin), tform3, 'linear', 'OutputView', Rout3);
            return;
        end
    end

    error('Unsupported transform matrix size for underlay warp.');
end

function tf = doesUnderlayMatchCurrentDisplay(U)
    tf = false;
    try
        U = squeeze(U);
        tf = (size(U,1) == ny && size(U,2) == nx);
    catch
        tf = false;
    end
end

function tf = doesUnderlayMatchOriginalDisplay(U)
    tf = false;
    try
        U = squeeze(U);
        tf = (size(U,1) == size(origPSC,1) && size(U,2) == size(origPSC,2));
    catch
        tf = false;
    end
end

 function rgb = renderUnderlayRGB(Uin)
    ensureUnderlayStateFields();

    isRgbImage = (ndims(Uin) == 3 && size(Uin,3) == 3);
    isRegionLabel = ~isempty(state.regionLabelUnderlay) && ismatrix(Uin);

    if isRgbImage || isRegionLabel
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
            state.regionColorLUT = makeRegionColorLUT(max(1,maxLab));
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

    base = lines(max(n,12));
    lut = base(1:n,:);

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
    if ~isfield(state,'isColorUnderlay') || isempty(state.isColorUnderlay)
        state.isColorUnderlay = false;
    end
    if ~isfield(state,'regionLabelUnderlay') || isempty(state.regionLabelUnderlay)
        state.regionLabelUnderlay = [];
    end
    if ~isfield(state,'regionColorLUT') || isempty(state.regionColorLUT)
        state.regionColorLUT = [];
    end
    if ~isfield(state,'regionInfo') || isempty(state.regionInfo)
        state.regionInfo = struct();
    end
end

    function s = safeStr(x)
        s = '';
        try
            if isempty(x), return; end
            if isstring(x), x = char(x); end
            if iscell(x), x = x{1}; end
            s = char(x);
        catch
            s = '';
        end
    end

end