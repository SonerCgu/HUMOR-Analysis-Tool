function fig = play_fusi_video_final( ...
    I, I_interp, PSC, bg, par, fps, maxFPS, TR, Tmax, baseline, ...
    loadedMask, loadedMaskIsInclude, nVols, applyRejection, QC, fileLabel, sliceIdx)

% =========================================================
% fUSI Video GUI (MATLAB 2023b)
% - Right panel with 3 tabs: Video/Mask, Underlay, Overlay
% - Alpha modulation + Threshold moved to Overlay tab
% - Underlay selection + processing moved to Underlay tab
% - Bottom buttons remain (HELP/CLOSE/Open SCM/Play/Replay/Save MP4)
% - Restored colorbar
% - Mask now affects overlay like SCM_gui (prevents outside lighting up)
% - Adaptive vertical spacing so tabs are not cramped or empty
% - ASCII only (Windows-1252 safe)
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

% Ensure previewCaxis exists (robust PSC scaling)
if ~isfield(par,'previewCaxis') || isempty(par.previewCaxis)
    tmp = PSC(:); tmp = tmp(isfinite(tmp));
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

% ---------------- DIMENSIONS (PSC) ----------------
bgDefaultFull = bg;   % default underlay passed in
ndPSC = ndims(PSC);

switch ndPSC
    case 4  % [Y X Z T]
        [ny, nx, nZ, nFrames] = size(PSC);
    case 3  % [Y X T]
        [ny, nx, nFrames] = size(PSC);
        nZ = 1;
    case 2  % [Y X]
        [ny, nx] = size(PSC);
        nZ = 1;
        nFrames = 1;
    otherwise
        error('PSC must be 2D, 3D or 4D.');
end

% ---- Ensure slice index ----
if nargin < 17 || isempty(sliceIdx) || ~isfinite(sliceIdx)
    if nZ > 1, sliceIdx = round(nZ/2); else, sliceIdx = 1; end
end
sliceIdx = max(1, min(nZ, round(sliceIdx)));

% =========================================================
% UNDERLAY STATE (Underlay tab)
% =========================================================
% underSrc: 1 Default(bg), 2 Mean(I), 3 Median(I), 4 Load file
underSrc = 1;
underSrcLabel = 'Default(bg)';
bgMeanFull   = [];
bgMedianFull = [];
bgFileFull   = [];

% Underlay processing state (SCM-like defaults)
uState.mode       = 3;
uState.brightness = -0.04;
uState.contrast   = 1.10;
uState.gamma      = 0.95;

MAX_CONSIZE = 300;
MAX_CONLEV  = 500;
uState.conectSize = 18;
uState.conectLev  = 35;

% =========================================================
% OVERLAY STATE (Overlay tab)
% =========================================================
Nc = 256;
cmapNames = { ...
    'blackbdy_iso', ...
    'hot','parula','turbo','jet','gray','bone','copper','pink', ...
    'viridis','plasma','magma','inferno'};

overlayCmapName = 'blackbdy_iso';
mapA = getCmap(overlayCmapName, Nc);

% Threshold slider range defaults from PSC
[tmpThrMin, tmpThrMax] = getSuggestedThresholdRange(PSC, par.previewCaxis);
tmpThrMin = 0;   % abs threshold should always allow 0

% Alpha modulation (SCM identical) - moved to Overlay tab
alphaModEnable = true;
alphaPct  = 100;
modMinAbs = 50;
modMaxAbs = 100;

maskThreshold = 0; % abs PSC threshold - moved to Overlay tab
% Spatial smoothing of overlay only (display-only, like SCM overlay control)
overlaySmoothSigma = 0;   % 0 = OFF
overlaySmoothMax   = 5;   % slider max

% =========================================================
% MASK STATE (Video/Mask tab)
% =========================================================
mask = false(ny, nx, nZ, nVols);
maskIsInclude = true;
statusLine = '';

if exist('loadedMask','var') && ~isempty(loadedMask)
    loadedMask = logical(loadedMask);
    switch ndims(loadedMask)
        case 2
            mask(:,:,sliceIdx,:) = repmat(loadedMask,[1 1 1 nVols]);
            statusLine = '2D mask expanded to all volumes (current slice).';
        case 3
            for zz = 1:min(nZ,size(loadedMask,3))
                mask(:,:,zz,:) = repmat(loadedMask(:,:,zz),[1 1 1 nVols]);
            end
            statusLine = '3D mask expanded to all volumes.';
        case 4
            if isequal(size(loadedMask), size(mask))
                mask = loadedMask;
                statusLine = '4D mask restored.';
            else
                statusLine = '4D mask size mismatch - ignored.';
            end
    end
    maskIsInclude = loadedMaskIsInclude;
end

% Playback + view state
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
% FIGURE (bigger opening window to avoid overlap)
% =========================================================
scr = get(0,'ScreenSize');
figW = min(max(1650, round(scr(3)*0.92)), scr(3)-40);
figH = min(max(950,  round(scr(4)*0.88)), scr(4)-80);
x0 = max(20, round((scr(3)-figW)/2));
y0 = max(40, round((scr(4)-figH)/2));

fig = figure('Color','k', ...
    'Position',[x0 y0 figW figH], ...
    'Name','fUSI Video Analysis', ...
    'NumberTitle','off', ...
    'MenuBar','none', ...
    'ToolBar','none');

set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',12);
set(fig,'CloseRequestFcn',@onCloseVideo);

% Remove accidental colorbars BEFORE creating ours
try, delete(findall(fig,'Type','ColorBar')); catch, end

% =========================================================
% MAIN AXES + COLORBAR (pixel layout, no overlap)
% =========================================================
ax = axes('Parent',fig,'Units','pixels');
axis(ax,'off','image');
img = image(ax, zeros(ny, nx, 3, 'single'));
set(ax,'HitTest','on'); set(img,'HitTest','off');

txtSliceAx = text(ax, 0.99, 0.02, '', ...
    'Units','normalized', 'Color',[0.80 0.90 1.00], ...
    'FontSize',12, 'FontWeight','bold', ...
    'HorizontalAlignment','right', 'VerticalAlignment','bottom', ...
    'Interpreter','none');

% Top slice label
txtSliceTop = uicontrol(fig,'Style','text','Units','pixels', ...
    'String', sliceString(sliceIdx,nZ), ...
    'ForegroundColor',[0.85 0.90 1.00], ...
    'BackgroundColor','k', ...
    'FontSize',12,'FontWeight','bold', ...
    'HorizontalAlignment','left');

% File label (center above axes)
txtTitle = uicontrol(fig,'Style','text','Units','pixels', ...
    'String', safeStr(fileLabel), ...
    'ForegroundColor',[0.95 0.95 0.95], ...
    'BackgroundColor','k', ...
    'FontSize',14,'FontWeight','bold', ...
    'HorizontalAlignment','center');

% Info line (top, two lines)
info = uicontrol(fig,'Style','text','Units','pixels', ...
    'ForegroundColor','w', 'BackgroundColor','k', ...
    'FontName','Courier New', 'FontSize',13, ...
    'HorizontalAlignment','left');

% Colorbar (PSC only) - restored
try, colormap(ax, mapA); catch, end
caxis(ax, par.previewCaxis);
cbar = colorbar(ax);
set(cbar,'Color','w','FontSize',13);
cbar.Label.String = 'Signal Change (%)';
cbar.Label.FontSize = 14;
cbar.Label.Color = 'w';
set(cbar,'Limits',par.previewCaxis);

btnColorbarRange = uicontrol(fig,'Style','pushbutton','Units','pixels', ...
    'String','Color Bar Range', ...
    'FontWeight','bold', ...
    'Callback',@setColorbarRange);

% Footer
footer = uicontrol(fig,'Style','text','Units','pixels', ...
    'String','fUSI Video Analysis - HUMoR Analysis Tool - MPI Biological Cybernetics', ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',11);

% =========================================================
% RIGHT PANEL WITH TABS (pixel layout)
% =========================================================
uiFontName = 'Arial';
uiFontSize = 12;

% Layout constants (pixels)
rightM = 30;
panelW = 520;

btnW  = 120;
btnH  = 42;
gapX  = 18;
gapY  = 18;

row1Y = 18;
row2Y = row1Y + btnH + gapY;
bottomButtonsTop = row2Y + btnH;

topM = 20;

controlsPanel = uipanel('Parent',fig,'Title','Controls', ...
    'Units','pixels', ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold', ...
    'BorderType','line', ...
    'HighlightColor',[1 1 1], ...
    'ShadowColor',[1 1 1]);

% Tab bar (make it look clean)
tabBarH = 36;
tabBar = uipanel('Parent',controlsPanel,'Units','pixels', ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'BorderType','line', ...
    'HighlightColor',[1 1 1], ...
    'ShadowColor',[1 1 1]);

btnTabVideo  = uicontrol(tabBar,'Style','togglebutton','String','Video/Mask', ...
    'Units','pixels', 'Callback',@(~,~)switchTab('video'), ...
    'BackgroundColor',[0.24 0.24 0.24],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','Value',1);

btnTabUnder  = uicontrol(tabBar,'Style','togglebutton','String','Underlay', ...
    'Units','pixels', 'Callback',@(~,~)switchTab('underlay'), ...
    'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','Value',0);

btnTabOverlay = uicontrol(tabBar,'Style','togglebutton','String','Overlay', ...
    'Units','pixels', 'Callback',@(~,~)switchTab('overlay'), ...
    'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','Value',0);

% Content panels
pVideo   = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10], 'Visible','on');
pUnder   = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10], 'Visible','off');
pOverlay = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10], 'Visible','off');

% Helpers for consistent UI
pad = 14; rowHc = 32; sliderH = 16;

mkLbl = @(pp,s) uicontrol(pp,'Style','text','String',s,'Units','pixels', ...
    'ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkLblImp = @(pp,s) uicontrol(pp,'Style','text','String',s,'Units','pixels', ...
    'ForegroundColor',[1.00 0.55 0.55],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkValBox = @(pp,s) uicontrol(pp,'Style','edit','String',s,'Units','pixels', ...
    'BackgroundColor',[0.18 0.18 0.18],'ForegroundColor','w', ...
    'HorizontalAlignment','center','FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold', ...
    'Enable','inactive');

mkEdit = @(pp,s,cbk) uicontrol(pp,'Style','edit','String',s,'Units','pixels', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'HorizontalAlignment','center','FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',cbk);

mkSlider = @(pp,minv,maxv,val,cbk) uicontrol(pp,'Style','slider','Units','pixels', ...
    'Min',minv,'Max',maxv,'Value',val,'Callback',cbk);

mkPopup = @(pp,choices,val,cbk) uicontrol(pp,'Style','popupmenu','String',choices,'Value',val, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

mkChk = @(pp,s,val,cbk) uicontrol(pp,'Style','checkbox','String',s,'Value',val, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',[0.10 0.10 0.10],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold');

mkBtn = @(pp,lbl,cbk,bgcol,fs) uicontrol(pp,'Style','pushbutton','String',lbl, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',bgcol,'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',fs,'FontWeight','bold');

% -----------------------------
% VIDEO/MASK TAB CONTROLS
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

lblAuto = mkLbl(pVideo,'Auto apply');
tglApplyAll = uicontrol(pVideo,'Style','togglebutton','String','AUTO: ALL', ...
    'Units','pixels','Callback',@toggleApplyAll, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize,'FontWeight','bold','Value',1);

btnAutoMask = mkBtn(pVideo,'AUTO MASK (M)',@autoMaskButton,[0.25 0.55 0.25],12);

lblBrush = mkLbl(pVideo,'Brush radius (px)');
slBrush  = mkSlider(pVideo,1,60,brushRadius,@brushSliderChanged);
txtBrush = mkValBox(pVideo,sprintf('%d',brushRadius));

lblMaskA = mkLbl(pVideo,'Mask overlay alpha');
slMaskA  = mkSlider(pVideo,0,1,maskAlpha,@maskAlphaSliderChanged);
txtMaskA = mkValBox(pVideo,sprintf('%.2f',maskAlpha));

btnColor = mkBtn(pVideo,'Color...',@pickColor,[0.20 0.20 0.20],12);
btnFill  = mkBtn(pVideo,'Fill (F)',@fillRegion,[0.20 0.20 0.20],12);
btnClear = mkBtn(pVideo,'Clear mask',@clearMaskAll,[0.35 0.20 0.20],12);

btnApplyAllMask = mkBtn(pVideo,'Apply mask to all volumes (this slice)',@applyMaskToAllFrames,[0.20 0.45 0.25],12);

btnSaveMask = mkBtn(pVideo,'Save mask (.mat)',@saveMaskMat,[0.10 0.35 0.95],12);
btnSaveInterp = mkBtn(pVideo,'Save interpolated data (.mat)',@saveInterpolatedMat,[0.15 0.65 0.55],12);

% -----------------------------
% UNDERLAY TAB CONTROLS
% -----------------------------
lblUSrc = mkLbl(pUnder,'Underlay source');
popUSrc = mkPopup(pUnder,{'1) Default(bg)','2) Mean(I)','3) Median(I) robust','4) Load file...'},underSrc,@underSrcChanged);

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

% -----------------------------
% OVERLAY TAB CONTROLS
% -----------------------------
lblMap = mkLbl(pOverlay,'Colormap');
idxMap = find(strcmp(cmapNames,overlayCmapName),1,'first'); if isempty(idxMap), idxMap=1; end
popMap = mkPopup(pOverlay,cmapNames,idxMap,@overlayMapChanged);

lblRange = mkLblImp(pOverlay,'Display range (min max)');
edRange  = mkEdit(pOverlay,sprintf('%.6g %.6g',par.previewCaxis(1),par.previewCaxis(2)),@overlayRangeApply);
btnRange = mkBtn(pOverlay,'Apply range',@overlayRangeApply,[0.25 0.40 0.65],12);

lblThr = mkLblImp(pOverlay,'Threshold abs (%)');
slThr  = mkSlider(pOverlay,tmpThrMin,tmpThrMax,maskThreshold,@overlayThrSliderChanged);
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

% ---------------------------------------------------------
% Bottom buttons (UNCHANGED conceptually)
% ---------------------------------------------------------
helpBtn = uicontrol(fig,'Style','pushbutton','String','HELP', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.40 0.65],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@showHelpDialog);

closeBtn = uicontrol(fig,'Style','pushbutton','String','CLOSE', ...
    'Units','pixels', ...
    'BackgroundColor',[0.65 0.25 0.25],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@(s,e) close(fig));

scmBtn = uicontrol(fig,'Style','pushbutton','String','Open SCM', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.55 0.35],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@openSCM);

playBtn = uicontrol(fig,'Style','togglebutton','String','Play', ...
    'Units','pixels', ...
    'BackgroundColor',[0.20 0.45 0.20],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@playPause);

replayBtn = uicontrol(fig,'Style','pushbutton','String','Replay', ...
    'Units','pixels', ...
    'BackgroundColor',[0.35 0.35 0.35],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@replayVid);

saveMP4Btn = uicontrol(fig,'Style','pushbutton','String','Save MP4', ...
    'Units','pixels', ...
    'BackgroundColor',[0.25 0.40 0.65],'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@saveVideo);

% Figure callbacks
set(fig,'WindowButtonDownFcn',@mouseDown);
set(fig,'WindowButtonUpFcn',@mouseUp);
set(fig,'WindowButtonMotionFcn',@mouseMoveVideo);
set(fig,'KeyPressFcn',@keyPressHandler);
set(fig,'WindowScrollWheelFcn',@mouseScrollSlice);
set(fig,'ResizeFcn',@(~,~)layoutUI());

% Initial layout and render
layoutUI();
render();

% =========================================================
% TIMER
% =========================================================
playTimer = timer('ExecutionMode','fixedSpacing', ...
    'Period',1/max(fps,0.1), 'TimerFcn',@timerTick);

    function timerTick(~,~)
        if ~ishandle(fig) || ~playing, return; end

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
            set(btnTabVideo,'Value',1,'BackgroundColor',[0.24 0.24 0.24]);
            set(btnTabUnder,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
            set(btnTabOverlay,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
        elseif strcmp(which,'underlay')
            set(pVideo,'Visible','off');
            set(pUnder,'Visible','on');
            set(pOverlay,'Visible','off');
            set(btnTabVideo,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
            set(btnTabUnder,'Value',1,'BackgroundColor',[0.24 0.24 0.24]);
            set(btnTabOverlay,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
        else
            set(pVideo,'Visible','off');
            set(pUnder,'Visible','off');
            set(pOverlay,'Visible','on');
            set(btnTabVideo,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
            set(btnTabUnder,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
            set(btnTabOverlay,'Value',1,'BackgroundColor',[0.24 0.24 0.24]);
        end
        layoutUI();
    end

% =========================================================
% LAYOUT
% =========================================================
    function layoutUI()
        pos = get(fig,'Position');
        W = pos(3); H = pos(4);

        panelX = W - rightM - panelW;

        panelY = (row2Y + btnH) + 20;
        panelH = max(360, H - panelY - topM);

        % Controls panel
        set(controlsPanel,'Position',[panelX panelY panelW panelH]);

        % Bottom buttons
        set(helpBtn,'Position',[panelX row2Y btnW btnH]);
        set(closeBtn,'Position',[panelX+btnW+gapX row2Y btnW btnH]);
        set(scmBtn,'Position',[panelX+2*(btnW+gapX) row2Y btnW btnH]);

        set(playBtn,'Position',[panelX row1Y btnW btnH]);
        set(replayBtn,'Position',[panelX+btnW+gapX row1Y btnW btnH]);
        set(saveMP4Btn,'Position',[panelX+2*(btnW+gapX) row1Y btnW btnH]);

        % Tab bar
        set(tabBar,'Position',[10 panelH-tabBarH-18 panelW-20 tabBarH]);
        btnWTab = floor((panelW-20-16)/3);
        set(btnTabVideo,'Position',[2 2 btnWTab-2 tabBarH-4]);
        set(btnTabUnder,'Position',[2+btnWTab+8 2 btnWTab-2 tabBarH-4]);
        set(btnTabOverlay,'Position',[2+2*(btnWTab+8) 2 btnWTab-2 tabBarH-4]);

        % Content region
        contentX = 10;
        contentY = 10;
        contentW = panelW - 20;
        contentH = panelH - tabBarH - 30;

        set(pVideo,'Position',[contentX contentY contentW contentH]);
        set(pUnder,'Position',[contentX contentY contentW contentH]);
        set(pOverlay,'Position',[contentX contentY contentW contentH]);

        % Adaptive gaps so controls fill the tab (no huge empty space)
        layoutVideoTab(contentW, contentH);
        layoutUnderTab(contentW, contentH);
        layoutOverlayTab(contentW, contentH);

        % LEFT SIDE LAYOUT (axes + colorbar + title + info)
        leftM = 120;
        gapToPanel = 40;
        axW = max(520, panelX - gapToPanel - leftM);
        axH = max(420, H - 220);
        axY = 90;
        axX = leftM;

        set(ax,'Position',[axX axY axW axH]);
        set(txtTitle,'Position',[axX axY+axH+10 axW 26]);

        set(info,'Position',[20 H-90 panelX-40 70]);
        set(txtSliceTop,'Position',[20 H-118 300 22]);

        % Colorbar left of axes
        cbarW = 18;
        cbarX = max(20, axX-70);
        cbarY = axY + 40;
        cbarH = max(220, axH - 80);
        set(cbar,'Units','pixels','Position',[cbarX cbarY cbarW cbarH]);

        set(btnColorbarRange,'Position',[cbarX-12 axY-42 140 32]);

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
        wLabel = 200;
        xCtrl  = xLabel + wLabel + 10;
        xVal   = w - pad - 110;
        wVal   = 110;
        wCtrl  = max(120, xVal - xCtrl - 10);

        % Estimate fixed heights to spread vertically
        fixed = 0;
        fixed = fixed + 2*rowHc;          % FPS, Vol
        fixed = fixed + 3*rowHc;          % Editor, View, Auto
        fixed = fixed + 2*rowHc;          % Brush, Mask alpha
        fixed = fixed + rowHc;            % Color/Fill/Clear
        fixed = fixed + 34;               % Apply mask all volumes
        fixed = fixed + 2*32;             % Save buttons
        nGaps = 10;
        gapc = adaptiveGap(h, fixed, nGaps, 8, 10);
        gapBig = gapc + 6;

        y0 = h - 46;

        % FPS
        set(lblFPS,'Position',[xLabel y0 wLabel rowHc]);
        set(slFPS,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtFPS,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        % Volume
        set(lblVol,'Position',[xLabel y0 wLabel rowHc]);
        set(slVol,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtVol,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapBig);

        % Editor
        set(lblEditor,'Position',[xLabel y0 wLabel rowHc]);
        set(tglEditor,'Position',[xCtrl y0 wCtrl+wVal+10 rowHc]);
        y0 = y0 - (rowHc + gapc);

        % View
        set(lblView,'Position',[xLabel y0 wLabel rowHc]);
        halfW = floor((wCtrl+wVal+10)/2)-6;
        set(tglView,'Position',[xCtrl y0 halfW rowHc]);
        set(popIncExc,'Position',[xCtrl+halfW+12 y0 halfW rowHc]);
        y0 = y0 - (rowHc + gapc);

        % Auto
        set(lblAuto,'Position',[xLabel y0 wLabel rowHc]);
        set(tglApplyAll,'Position',[xCtrl y0 halfW rowHc]);
        set(btnAutoMask,'Position',[xCtrl+halfW+12 y0 halfW rowHc]);
        y0 = y0 - (rowHc + gapc);

        % Brush
        set(lblBrush,'Position',[xLabel y0 wLabel rowHc]);
        set(slBrush,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtBrush,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        % Mask alpha
        set(lblMaskA,'Position',[xLabel y0 wLabel rowHc]);
        set(slMaskA,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtMaskA,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapBig);

        % Color/Fill/Clear
        bw = floor((w-2*pad-20)/3);
        set(btnColor,'Position',[xLabel y0 bw rowHc]);
        set(btnFill,'Position',[xLabel+bw+10 y0 bw rowHc]);
        set(btnClear,'Position',[xLabel+2*(bw+10) y0 bw rowHc]);
        y0 = y0 - (rowHc + gapc);

        % Apply mask all volumes
        set(btnApplyAllMask,'Position',[xLabel y0 (w-2*pad) 34]);
        y0 = y0 - (34 + gapc);

        % Save buttons
        set(btnSaveMask,'Position',[xLabel y0 (w-2*pad) 32]);
        y0 = y0 - (32 + gapc);
        set(btnSaveInterp,'Position',[xLabel y0 (w-2*pad) 32]);
    end

    function layoutUnderTab(w, h)
        xLabel = pad;
        wLabel = 220;
        xCtrl  = xLabel + wLabel + 10;
        xVal   = w - pad - 110;
        wVal   = 110;
        wCtrl  = max(120, xVal - xCtrl - 10);

        fixed = 0;
        fixed = fixed + 2*rowHc;          % source + mode
        fixed = fixed + 3*rowHc;          % bri/con/gam
        fixed = fixed + 2*rowHc;          % vsz/vlv
        nGaps = 7;
        gapc = adaptiveGap(h, fixed, nGaps, 8, 10);
        gapBig = gapc + 6;

        y0 = h - 46;

        set(lblUSrc,'Position',[xLabel y0 wLabel rowHc]);
        set(popUSrc,'Position',[xCtrl y0 (wCtrl+wVal+10) rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblUMode,'Position',[xLabel y0 wLabel rowHc]);
        set(popUMode,'Position',[xCtrl y0 (wCtrl+wVal+10) rowHc]);
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
        y0 = y0 - (rowHc + gapc);

        set(lblVsz,'Position',[xLabel y0 wLabel rowHc]);
        set(slVsz,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtVsz,'Position',[xVal y0 wVal rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblVlv,'Position',[xLabel y0 wLabel rowHc]);
        set(slVlv,'Position',[xCtrl y0+round((rowHc-sliderH)/2) wCtrl sliderH]);
        set(txtVlv,'Position',[xVal y0 wVal rowHc]);

        updateUnderlayEnable();
    end

    function layoutOverlayTab(w, h)
        xLabel = pad;
        wLabel = 220;
        xCtrl  = xLabel + wLabel + 10;
        xVal   = w - pad - 110;
        wVal   = 110;
        wCtrl  = max(120, xVal - xCtrl - 10);

      fixed = 0;
fixed = fixed + rowHc;            % cmap
fixed = fixed + rowHc;            % range row (plus button)
fixed = fixed + rowHc;            % thr slider row
fixed = fixed + rowHc;            % alpha slider row
fixed = fixed + rowHc;            % smoothing row
fixed = fixed + rowHc;            % alpha mod checkbox row
fixed = fixed + 2*rowHc;          % mod min/max
nGaps = 8;
        gapc = adaptiveGap(h, fixed, nGaps, 8, 10);
        gapBig = gapc + 6;

        y0 = h - 46;

        set(lblMap,'Position',[xLabel y0 wLabel rowHc]);
        set(popMap,'Position',[xCtrl y0 (wCtrl+wVal+10) rowHc]);
        y0 = y0 - (rowHc + gapc);

        set(lblRange,'Position',[xLabel y0 wLabel rowHc]);
        set(edRange,'Position',[xCtrl y0 floor((wCtrl+wVal+10)*0.62) rowHc]);
        set(btnRange,'Position',[xCtrl+floor((wCtrl+wVal+10)*0.62)+10 y0 floor((wCtrl+wVal+10)*0.38)-10 rowHc]);
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
y0 = y0 - (rowHc + gapc);

        set(lblAlphaMod,'Position',[xLabel y0 wLabel rowHc]);
        set(chkAlphaMod,'Position',[xCtrl y0 (wCtrl+wVal+10) rowHc]);
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

        % Underlay
        bgFullActive = getUnderlayFull();
        bg2 = getBg2DForSlice(bgFullActive, sliceIdx);
        bg2(~isfinite(bg2)) = 0;

        bg01 = processUnderlay(bg2);
        bgRGB = toRGB(bg01);

        if frame < 1 || frame > nFrames
            img.CData = bgRGB;
            return;
        end

        % PSC slice/frame
     if ndPSC == 4
    A = squeeze(PSC(:,:,sliceIdx, frame));
elseif ndPSC == 3
    A = PSC(:,:,frame);
else
    A = PSC;
end
A = double(A);
A(~isfinite(A)) = 0;

% Display-only spatial smoothing of overlay
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
        % fallback: leave A unchanged if smoothing fails
    end
end

        % Keep caxis valid
        cax = par.previewCaxis;
        if numel(cax) ~= 2 || ~isfinite(cax(1)) || ~isfinite(cax(2)) || diff(cax) <= 0
            cax = [-10 10];
            par.previewCaxis = cax;
        end
        try
            set(cbar,'Limits',cax);
        catch
        end

        % PSC -> RGB
        A_scaled = (A - cax(1)) ./ (cax(2) - cax(1) + eps);
        A_scaled = max(0, min(1, A_scaled));
        pscRGB = ind2rgb(uint8(A_scaled * (Nc-1)), mapA);

        % Mask for this slice+volume
        M = squeeze(mask(:,:,sliceIdx, volume));
        M = logical(M);
        M = M(1:size(bg2,1), 1:size(bg2,2));

        % -----------------------------------------------------
        % IMPORTANT FIX: SCM-like overlay masking
        % If a mask exists on this slice/volume, ALWAYS apply it to overlay alpha.
        % Include: show inside mask
        % Exclude: show outside mask
        % If mask empty -> do not restrict overlay (baseMaskOverlay = 1)
        % -----------------------------------------------------
        if any(M(:))
            if maskIsInclude
                showMask = M;
            else
                showMask = ~M;
            end
            baseMaskOverlay = double(showMask);
        else
            showMask = true(size(M)); % for dimming logic fallback
            baseMaskOverlay = 1;      % do not restrict if empty mask
        end

        % VIEW: MASKED -> dim outside showMask (so it differs from FULL)
        if viewMaskedOnly && any(M(:))
            dimFactor = 0.12;
            show3 = repmat(showMask,[1 1 3]);
            bgRGB = bgRGB .* (show3 + dimFactor*(~show3));
        end

        % Threshold and alpha modulation (SCM identical)
        thr = maskThreshold;
        thrMask = double(abs(A) >= thr);

        a = max(0, min(100, alphaPct));
        if ~alphaModEnable
            alphaMap = (a/100) .* thrMask .* baseMaskOverlay;
        else
            effLo = max(modMinAbs, thr);
            effHi = modMaxAbs;

            if ~isfinite(effHi) || effHi <= effLo
                effHi = max(abs(A(:)));
            end
            if ~isfinite(effHi) || effHi <= effLo
                effHi = effLo + eps;
            end

            modv = (abs(A) - effLo) ./ max(eps, (effHi - effLo));
            modv(~isfinite(modv)) = 0;
            modv = min(max(modv,0),1);

            alphaMap = (a/100) .* modv .* thrMask .* baseMaskOverlay;
        end
        alphaMap(~isfinite(alphaMap)) = 0;
        alphaMap = min(max(alphaMap,0),1);

        a3 = repmat(alphaMap,[1 1 3]);
        baseRGB = (1-a3).*bgRGB + a3.*pscRGB;

        outRGB = baseRGB;

        % Mask overlay tint (editor visual)
        if ~viewMaskedOnly && any(M(:))
            maskRGB = cat(3, ones(size(bg2))*maskColor(1), ones(size(bg2))*maskColor(2), ones(size(bg2))*maskColor(3));
            M3 = repmat(M,[1 1 3]);
            alphaUse = maskAlpha;
            if editorMode, alphaUse = max(0.6, maskAlpha); end
            outRGB = outRGB .* (1 - alphaUse .* M3) + maskRGB .* (alphaUse .* M3);
        end

        img.CData = outRGB;

        % Info line
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
        if ~isempty(statusLine), extra = [' | ' statusLine]; end

        set(info,'String',sprintf([ ...
            't = %.1f / %.1f s | Vol %d / %d | View: %s (%s)\n' ...
           'Baseline: %g-%g %s | Editor: %s | Underlay: %s | Smooth=%.2f | AlphaMod: %s | alpha=%g%% min=%g max=%g thr=%g%s'], ...
            t, Tmax, volume, nVols, vm, ms, ...
           baseline.start, baseline.end, modeStr, ...
em, underSrcLabel, overlaySmoothSigma, alphaState, alphaPct, modMinAbs, modMaxAbs, maskThreshold, extra));

        % Update value boxes
        set(txtFPS,'String',sprintf('%d',fps));
        set(txtVol,'String',sprintf('%d / %d',volume,nVols));
        set(txtBrush,'String',sprintf('%d',brushRadius));
        set(txtMaskA,'String',sprintf('%.2f',maskAlpha));
        set(txtAlpha,'String',sprintf('%.0f',alphaPct));
        set(edThr,'String',sprintf('%.3g',maskThreshold));

        txtSliceAx.String = sliceString(sliceIdx, nZ);
    end

% =========================================================
% VIDEO TAB CALLBACKS (robust slider handling)
% =========================================================
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
            if playing, start(playTimer); end
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
        set(src,'String',tern(applyToAllFrames,'AUTO: ALL','AUTO: FRAME'));
        statusLine = '';
        render();
    end

    function autoMaskButton(~,~)
        autoMask();
    end

    function setBrush(v)
        brushRadius = max(1, min(60, round(v)));
        set(slBrush,'Value',brushRadius);
        statusLine = '';
        render();
    end

    function pickColor(~,~)
        c = uisetcolor(maskColor, 'Pick mask overlay color');
        if numel(c) == 3, maskColor = c; end
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
        v = get(src,'Value');
        if v == 4
            [U, lab] = loadUnderlayInteractive();
            if isempty(U)
                set(src,'Value',underSrc);
                return;
            end
            bgFileFull = U;
            underSrc = 4;
            underSrcLabel = lab;
        else
            underSrc = v;
            if underSrc == 1, underSrcLabel = 'Default(bg)'; end
            if underSrc == 2, underSrcLabel = 'Mean(I)'; end
            if underSrc == 3, underSrcLabel = 'Median(I)'; end
        end
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
        s = get(src,'String'); idx = get(src,'Value');
        if iscell(s), overlayCmapName = s{idx}; else, overlayCmapName = strtrim(s(idx,:)); end
        mapA = getCmap(overlayCmapName, Nc);
        try, colormap(ax, mapA); catch, end
        render();
    end

    function overlayRangeApply(~,~)
        v = sscanf(get(edRange,'String'),'%f');
        if numel(v) < 2 || any(~isfinite(v(1:2))) || v(2) == v(1)
            errordlg('Invalid range. Use: "min max"');
            return;
        end
        lo = v(1); hi = v(2);
        if hi < lo, tmp=lo; lo=hi; hi=tmp; end
        par.previewCaxis = [lo hi];
        caxis(ax, par.previewCaxis);
        try, set(cbar,'Limits',par.previewCaxis); catch, end

      % Update threshold slider range too (ABS threshold must allow 0)
absMax = max(abs([lo hi]));
if ~isfinite(absMax) || absMax <= 0, absMax = 1; end

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
        if ~isfinite(v), v = maskThreshold; end
        lo = get(slThr,'Min'); hi = get(slThr,'Max');
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
        if ~isfinite(v), v = modMinAbs; end
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
        if ~isfinite(v), v = modMaxAbs; end
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
        if nZ <= 1 || playing, return; end

        hobj = hittest(fig);
        if isempty(hobj), return; end
        axHit = ancestor(hobj,'axes');
        if isempty(axHit) || axHit ~= ax, return; end

        dz = -sign(evt.VerticalScrollCount);
        if dz == 0, return; end

        newZ = max(1, min(nZ, sliceIdx + dz));
        if newZ == sliceIdx, return; end

        sliceIdx = newZ;
        render();
    end

% =========================================================
% OPEN SCM (transfer mask collapsed over time)
% =========================================================
    function openSCM(~,~)
        try
            PSC_fast = PSC;
            bg_fast  = getUnderlayFull();

            if nZ == 1
                mask_fast = any(mask(:,:,1,:), 4); % [Y X]
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
    oldVolume  = volume;
    oldPlaying = playing;

    try
        % -------------------------------------------------
        % Resolve analysed root folder robustly
        % -------------------------------------------------
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

        % -------------------------------------------------
        % Create Videos subfolder
        % -------------------------------------------------
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

if contains(rawLabel,'raw'),      tags{end+1} = 'raw'; end
if contains(rawLabel,'gabriel'),  tags{end+1} = 'gab'; end
if contains(rawLabel,'median'),   tags{end+1} = 'median'; end
if contains(rawLabel,'mean'),     tags{end+1} = 'mean'; end
if contains(rawLabel,'pca'),      tags{end+1} = 'pca'; end
if contains(rawLabel,'despike') || contains(rawLabel,'despiked')
    tags{end+1} = 'despike';
end
if contains(rawLabel,'smooth') || contains(rawLabel,'smoothed')
    tags{end+1} = 'smooth';
end
if contains(rawLabel,'interp') || contains(rawLabel,'interpol')
    tags{end+1} = 'interp';
end
if contains(rawLabel,'psc'),      tags{end+1} = 'psc'; end
if contains(rawLabel,'brainonly'), tags{end+1} = 'brain'; end

if isempty(tags)
    shortLabel = 'video';
else
    shortLabel = strjoin(tags,'_');
end

timeTag = datestr(now,'yyyymmdd_HHMMSS');
outFile = fullfile(videosDir, ['video_' shortLabel '_' timeTag '.mp4']);  

        disp('--- SAVE VIDEO DEBUG ---');
        disp(['analysedRoot = ' analysedRoot]);
        disp(['videosDir    = ' videosDir]);
        disp(['outFile      = ' outFile]);
        disp(['path length  = ' num2str(numel(outFile))]);

        % -------------------------------------------------
        % Prepare video writer
        % -------------------------------------------------
        exportFPS = fps;
        if ~isfinite(exportFPS) || exportFPS <= 0
            exportFPS = 4;
        end

        vid = VideoWriter(outFile, 'MPEG-4');
        vid.FrameRate = exportFPS;
        vid.Quality   = 95;
        open(vid);

        % -------------------------------------------------
        % Export overlay text shown only in MP4
        % -------------------------------------------------
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

        % -------------------------------------------------
        % Write all frames
        % -------------------------------------------------
        for v = 1:nVols
            volume = v;
            if ishandle(slVol)
                set(slVol,'Value',v);
            end

            frame = (v - 1) * par.interpol + 1;
            frame = max(1, min(nFrames, round(frame)));

            render();

            t = (v - 1) * TR;
            set(txt,'String',sprintf('t = %.1f / %.1f s | Volume %d / %d', t, Tmax, v, nVols));

            drawnow;
            fr = getframe(ax);

repeatEachFrame = 2;   % 2 = slower, 3 = even slower
for rr = 1:repeatEachFrame
    writeVideo(vid, fr);
end
        end

        % cleanup
        if ~isempty(txt) && isgraphics(txt)
            delete(txt);
            txt = [];
        end

        if ~isempty(vid)
            close(vid);
            vid = [];
        end

        volume  = oldVolume;
        playing = oldPlaying;

        if ishandle(slVol)
            set(slVol,'Value',volume);
        end

        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));
        render();

        statusLine = ['Video saved: ' outFile];
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

        volume  = oldVolume;
        playing = oldPlaying;

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
        [f,p] = uiputfile('*.mat','Save mask');
        if isequal(f,0), return; end

        out = struct();
        out.mask = mask;
        out.maskIsInclude = maskIsInclude;

        out.metadata = struct();
        out.metadata.TR = TR;
        out.metadata.nVols = nVols;
        out.metadata.nZ = nZ;
        out.metadata.created = datestr(now);
        out.metadata.script = mfilename;
        out.metadata.note = 'Mask saved from fUSI video GUI';

        save(fullfile(p,f),'-struct','out','-v7.3');
        statusLine = 'Mask saved.';
        render();
    end

% =========================================================
% SAVE INTERPOLATED DATA
% =========================================================
    function saveInterpolatedMat(~,~)
        [f,p] = uiputfile('*.mat','Save interpolated fUSI data');
        if isequal(f,0), return; end

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
            'Color',[0.06 0.06 0.06], 'MenuBar','none','ToolBar','none', ...
            'NumberTitle','off', 'Position',[250 120 920 740], ...
            'Resize','on', 'WindowStyle','modal');

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
            'Units','normalized', 'Position',[0.03 0.03 0.94 0.94], ...
            'String',sprintf(msg), ...
            'ForegroundColor',[0.90 0.90 0.90], ...
            'BackgroundColor',[0.12 0.12 0.12], ...
            'FontName','Arial', 'FontSize',14, ...
            'HorizontalAlignment','left', 'Max',2, 'Min',0, ...
            'Enable','inactive');
    end

% =========================================================
% MOUSE PAINTING
% =========================================================
    function mouseDown(~,~)
        if playing || ~editorMode, return; end
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
        if ~ishandle(ax), return; end

        cp = get(ax,'CurrentPoint');
        x = cp(1,1); yv = cp(1,2);
        if x>=1 && x<=nx && yv>=1 && yv<=ny
            lastMouseXY = [x yv];
        end

        if ~mouseIsDown || ~editorMode || playing, return; end
        applyPaintAtCursor();
    end

    function applyPaintAtCursor()
        cp = get(ax,'CurrentPoint');
        x = round(cp(1,1));
        yv = round(cp(1,2));
        if x<1 || x>nx || yv<1 || yv>ny, return; end

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
        if ~isfield(evt,'Key'), return; end
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
        x0 = round(xf); y0 = round(yf);
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
            try, autoM = bwareafilt(autoM,1); catch, end
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
        y1 = max(1, y0-Ww); y2 = min(ny, y0+Ww);
        x1 = max(1, x0-Ww); x2 = min(nx, x0+Ww);

        block = P(y1:y2, x1:x2);
        sigmaLocal = std(block(:));
        if ~isfinite(sigmaLocal) || sigmaLocal == 0, sigmaLocal = 0.05; end

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
        if isempty(answer), return; end

        low = str2double(answer{1});
        high = str2double(answer{2});
        if isnan(low) || isnan(high) || high <= low
            errordlg('Invalid colorbar limits.');
            return;
        end

        par.previewCaxis = [low high];
        caxis(ax, par.previewCaxis);
        try, set(cbar,'Limits',par.previewCaxis); catch, end

      
  % Sync overlay tab range and threshold slider (ABS threshold must allow 0)
set(edRange,'String',sprintf('%.6g %.6g',low,high));

absMax = max(abs([low high]));
if ~isfinite(absMax) || absMax <= 0, absMax = 1; end

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
            case 4
                bgFull = bgFileFull;
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
        T  = sz(dimT);
        maxFrames = 600;
        if T <= maxFrames
            idx = 1:T;
        else
            step = ceil(T / maxFrames);
            idx  = 1:step:T;
        end
        subs = repmat({':'},1,dimT);
        subs{dimT} = idx;
        Isub = double(I(subs{:}));
        bgFull = median(Isub, dimT);
    end

    function bg2 = getBg2DForSlice(bgIn, z)
        if ndims(bgIn) == 2
            bg2 = bgIn;
        elseif ndims(bgIn) == 3
            z = max(1,min(size(bgIn,3),z));
            bg2 = bgIn(:,:,z);
        elseif ndims(bgIn) == 4
            tmp = mean(bgIn,4);
            z = max(1,min(size(tmp,3),z));
            bg2 = tmp(:,:,z);
        else
            bg2 = bgIn(:,:,1);
        end
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
        if ~isfinite(g) || g<=0, g=1; end
        U01 = min(max(U.^g,0),1);
    end

    function U = vesselEnhanceStrong(U01, conectSizePx, conectLev_0_MAX)
        if conectSizePx <= 0, U = U01; return; end

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
        if s>0, h = h/s; end
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
        if isequal(f,0), return; end
        fullf = fullfile(p,f);

        U = loadUnderlayFile(fullf);
        if isempty(U), return; end

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
                tmpDir = tempname; mkdir(tmpDir);
                gunzip(f, tmpDir);
                d = dir(fullfile(tmpDir,'*.nii'));
                if isempty(d), error('gunzip failed.'); end
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
                    U = v.I; return;
                end
            end
            for k = 1:numel(fn)
                v = S.(fn{k});
                if isnumeric(v)
                    U = v; return;
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
            R = X(:,:,1); Gc = X(:,:,2); B = X(:,:,3);
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
            case 'hot',     cm = hot(n);
            case 'parula',  cm = parula(n);
            case 'jet',     cm = jet(n);
            case 'gray',    cm = gray(n);
            case 'bone',    cm = bone(n);
            case 'copper',  cm = copper(n);
            case 'pink',    cm = pink(n);
            otherwise
                if strcmp(name,'turbo')
                    if exist('turbo','file'), cm = turbo(n); else, cm = jet(n); end
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
        v = PSC0(:); v = v(isfinite(v));
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
    function s = onoff(tf), if tf, s='on'; else, s='off'; end, end

    function out = tern(cond, a, b)
        if cond, out = a; else, out = b; end
    end

    function s = sliceString(k, nZ0)
        if nZ0 > 1
            s = sprintf('Slice: %d / %d', k, nZ0);
        else
            s = '';
        end
    end

    function B = makeBrushMask(x0, y0, r, ny0, nx0)
        [X,Y] = meshgrid(1:nx0, 1:ny0);
        B = (X-x0).^2 + (Y-y0).^2 <= r^2;
    end

    function U = mat2gray_safe(U)
        mn = min(U(:)); mx = max(U(:));
        if ~isfinite(mn) || ~isfinite(mx) || mx<=mn
            U(:)=0; return;
        end
        U = (U - mn) ./ (mx - mn);
        U = min(max(U,0),1);
    end

    function U = clip01_percentile(A,pLow,pHigh)
        v=A(:); v=v(isfinite(v));
        if isempty(v), U=zeros(size(A)); return; end
        lo=prctile_fallback(v,pLow);
        hi=prctile_fallback(v,pHigh);
        if ~isfinite(lo) || ~isfinite(hi) || hi<=lo
            U=mat2gray_safe(A); return;
        end
        U=A; U(U<lo)=lo; U(U>hi)=hi;
        U=(U-lo)/max(eps,(hi-lo));
        U=min(max(U,0),1);
    end

    function q = prctile_fallback(v,p)
        try
            q = prctile(v,p);
            return;
        catch
        end
        v = sort(v(:)); n=numel(v);
        if n==0, q=0; return; end
        k = 1 + (n-1)*(p/100);
        k1 = floor(k); k2 = ceil(k);
        k1 = max(1,min(n,k1)); k2 = max(1,min(n,k2));
        if k1==k2
            q = v(k1);
        else
            q = v(k1) + (k-k1)*(v(k2)-v(k1));
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