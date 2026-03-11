function fig = SCM_gui(PSC, bg, TR, par, baseline, nVolsOrig, varargin)
% SCM_gui — Studio version (MATLAB 2017b + 2023b)
% ==========================================================
% (UNCHANGED UI/behavior from your version)
%
% FIXES/FEATURES IN THIS COPY:
%   1) ROI export no longer overwrites: continues roi1, roi2, roi3... (next free index)
%   2) ROI export creates subfolders by dataset type (raw / gabriel / ...):
%        AnalysedData/<dataset>/ROI/<type>/<datasetTag>/roiN.txt
%      type is derived from loaded dataset (par.* or fileLabel)
%   3) SCM-series export:
%        - PNG tiles + 6-per-slide montage PNGs
%        - Robust PPT export that just drops each montage PNG on a slide
%          via writePptFromSlidePNGs (simple, 2017b + 2023b safe)
% ==========================================================

%% ---------------- SAFETY ----------------
assert(isscalar(TR) && isfinite(TR) && TR > 0, 'TR must be positive scalar');

d = ndims(PSC);
assert(d==3 || d==4, 'PSC must be [Y X T] or [Y X Z T]');

if d==3
    [nY,nX,nT] = size(PSC); nZ = 1;
else
    [nY,nX,nZ,nT] = size(PSC);
end
tsec = (0:nT-1)*TR;
tmin = tsec/60;
% ---------------- FAST HOVER (shows PSC but stays responsive) ----------------
state.hoverMaxPts   = 1200;                           % hover preview length
state.hoverStride   = max(1, ceil(nT/state.hoverMaxPts));
state.hoverIdx      = 1:state.hoverStride:nT;
state.tminHover     = tmin(state.hoverIdx);

roi.lastHoverStamp  = 0;
roi.lastHoverXY     = [-inf -inf];
state.hoverMinDtSec = 0.06;                           % ~16 fps max
% Backward-compat shim for old arg order
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
        (isnumeric(v6) && isscalar(v6) && (v6==0 || v6==1));
    if ~isempty(passedMask) && isBoolScalar
        passedMaskIsInclude = logical(v6);
    end
end

%% ---------------- BASELINE MODE ----------------
modeStr = 'sec';
if isfield(baseline,'mode') && ~isempty(baseline.mode)
    try, modeStr = lower(char(baseline.mode)); catch, modeStr = 'sec'; end
end
isVolMode = (strncmpi(modeStr,'vol',3) || strncmpi(modeStr,'idx',3));

%% ---------------- STATE ----------------
state.z   = max(1, round(nZ/2));
state.cax = [0 100];

% simplified alpha modulation
state.alphaModOn = true;
state.modMin = 20;
state.modMax = 30;

% ROI
roi.size = 5;
roi.colors = lines(12);
roi.isFrozen = false;

ROI_byZ = cell(1,nZ);
for zz=1:nZ
    ROI_byZ{zz} = struct('id',{},'x1',{},'x2',{},'y1',{},'y2',{},'color',{}); %#ok<AGROW>
end
roiHandles = gobjects(0);
roiPlotPSC = gobjects(0);
roiTextHandles = gobjects(0);   % NEW: labels on the image

roi.nextId = 1;                 % NEW: global ROI counter (per GUI session)
roi.lastAddStamp = 0;   % seconds since midnight in "now" units
roi.exportSetId = [];   % ROI set number (ROI1, ROI2, ...) assigned on first export
% Underlay
uState.mode       = 3;
uState.brightness = -0.04;   % -0.8..0.8
uState.contrast   = 1.10;    % 0.1..5
uState.gamma      = 0.95;    % 0.2..4

MAX_CONSIZE = 300;
MAX_CONLEV  = 500;
uState.conectSize = 18;
uState.conectLev  = 35;

%% ---------------- FIGURE (minimally bigger) ----------------
figW0 = 1880; figH0 = 1160;
scr = get(0,'ScreenSize');
x0 = max(20, round((scr(3)-figW0)/2));
y0 = max(40, round((scr(4)-figH0)/2));

fig = figure( ...
    'Name','SCM Viewer', ...
    'Color',[0.05 0.05 0.05], ...
    'Position',[x0 y0 figW0 figH0], ...
    'MenuBar','none','ToolBar','none','NumberTitle','off');

set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',14);

annotation(fig,'textbox',[0.62 0.004 0.37 0.03], ...
    'String','SCM GUI - Soner Caner Cagun - MPI Biological Cybernetics', ...
    'Color',[0.70 0.70 0.70], 'FontSize',10, ...
    'HorizontalAlignment','right','EdgeColor','none','Interpreter','none');

%% ---------------- MAIN IMAGE AXIS ----------------
ax = axes('Parent',fig,'Units','pixels');
axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','reverse'); hold(ax,'on');

bg2 = getBg2DForSlice(state.z);
hBG = image(ax, toRGB(processUnderlay(bg2)));

hOV = imagesc(ax, zeros(nY,nX));
set(hOV,'AlphaData',0);

% Overlay colormap
cmapNames = { ...
    'blackbdy_iso', ...
    'hot','parula','turbo','jet','gray','bone','copper','pink', ...
    'viridis','plasma','magma','inferno'};
setOverlayColormap('blackbdy_iso');
caxis(ax,state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.FontSize = 12;

hold(ax,'off');

% Dedicated title above axis
txtTitle = uicontrol(fig,'Style','text','String',fileLabel, ...
    'Units','pixels','ForegroundColor',[0.95 0.95 0.95], ...
    'BackgroundColor',[0.05 0.05 0.05], ...
    'FontSize',16,'FontWeight','bold', ...
    'HorizontalAlignment','center');

%% ---------------- TIMECOURSE AXIS ----------------
axTC = axes('Parent',fig,'Units','pixels', ...
    'Color',[0.05 0.05 0.05],'XColor','w','YColor','w');
hold(axTC,'on'); grid(axTC,'on');
axTC.FontSize = 12;
xlabel(axTC,'Time (min)','Color','w','FontSize',13,'FontWeight','bold');
ylabel(axTC,'PSC (%)','Color','w','FontSize',13,'FontWeight','bold');

hBasePatch = patch(axTC,[0 0 0 0],[0 0 0 0],[1 1 1], ...
    'FaceAlpha',0.10,'EdgeColor','none','Visible','off');
hSigPatch  = patch(axTC,[0 0 0 0],[0 0 0 0],[1 1 1], ...
    'FaceAlpha',0.10,'EdgeColor','none','Visible','off');

hBaseTxt = text(axTC,0,0,'','Color',[1.00 0.35 0.35], ...
    'FontSize',11,'FontWeight','bold','Visible','off');
hSigTxt  = text(axTC,0,0,'','Color',[1.00 0.75 0.35], ...
    'FontSize',11,'FontWeight','bold','Visible','off');

% Live hover PSC (downsampled)
hLivePSC = plot(axTC, state.tminHover, nan(1,numel(state.tminHover)), ':', 'LineWidth', 3.2);
hLivePSC.Color = [1.00 0.60 0.10];
hLivePSC.Visible = 'off';


% live ROI coordinate label in top-right of timecourse axis
hRoiCoordTxt = text(axTC, 0.99, 0.98, '', ...
    'Units','normalized', ...
    'HorizontalAlignment','right', ...
    'VerticalAlignment','top', ...
    'Color',[0.92 0.92 0.92], ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Interpreter','none', ...
    'Visible','off');

axes(ax); %#ok<LAXES>
hLiveRect = rectangle(ax,'Position',[1 1 1 1], ...
    'EdgeColor',[0 1 0],'LineWidth',2,'Visible','off');

%% ---------------- SLICE SLIDER ----------------
slZ = [];
txtZ = [];
if nZ > 1
    slZ = uicontrol(fig,'Style','slider', ...
        'Units','pixels', ...
        'Min',1,'Max',nZ,'Value',state.z, ...
        'SliderStep',[1/max(1,nZ-1) 5/max(1,nZ-1)], ...
        'Callback',@sliceChanged);

    txtZ = uicontrol(fig,'Style','text', ...
        'Units','pixels', ...
        'String',sprintf('Slice: %d / %d',state.z,nZ), ...
        'ForegroundColor',[0.85 0.9 1], ...
        'BackgroundColor',get(fig,'Color'), ...
        'HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',13);
end

%% ---------------- MASK INIT ----------------
if isempty(passedMask)
    passedMask = deriveMaskFromUnderlay(bg, nY, nX, nZ, nT);
    passedMaskIsInclude = true;
end

mask2D = true(nY,nX);
if ~isempty(passedMask)
    mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
end
if ~passedMaskIsInclude && ~isempty(passedMask)
    mask2D = ~mask2D;
end

%% ==========================================================
% RIGHT PANEL (CUSTOM BLACK TABS)
%% ==========================================================
controlsPanel = uipanel('Parent',fig,'Title','SCM Controls', ...
    'Units','pixels', ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w','FontSize',16,'FontWeight','bold');

tabBar = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10]);

btnTabOverlay  = uicontrol(tabBar,'Style','togglebutton','String','Overlay', ...
    'Units','pixels','Callback',@(~,~)switchTab('overlay'), ...
    'BackgroundColor',[0.22 0.22 0.22],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','Value',1);

btnTabUnderlay = uicontrol(tabBar,'Style','togglebutton','String','Underlay', ...
    'Units','pixels','Callback',@(~,~)switchTab('underlay'), ...
    'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','Value',0);

pOverlay  = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10]);
pUnderlay = uipanel('Parent',controlsPanel,'Units','pixels','BorderType','none', ...
    'BackgroundColor',[0.10 0.10 0.10],'Visible','off');

% Status/info line
info1 = uicontrol(controlsPanel,'Style','text','String','', ...
    'Units','pixels', ...
    'ForegroundColor',[0.80 0.90 1.00], ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12,'FontWeight','bold');

% UI helpers
pad = 16; rowH = 30; gap = 8; sliderH = 16;

mkLbl = @(pp,s) uicontrol(pp,'Style','text','String',s, ...
    'Units','pixels', ...
    'ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12,'FontWeight','bold');

mkLblImp = @(pp,s) uicontrol(pp,'Style','text','String',s, ...
    'Units','pixels', ...
    'ForegroundColor',[1.00 0.55 0.55],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12,'FontWeight','bold');

mkValBox = @(pp,s) uicontrol(pp,'Style','edit','String',s, ...
    'Units','pixels', ...
    'BackgroundColor',[0.18 0.18 0.18],'ForegroundColor','w', ...
    'HorizontalAlignment','center','FontSize',12,'FontWeight','bold', ...
    'Enable','inactive');

mkEdit = @(pp,s,cbk) uicontrol(pp,'Style','edit','String',s, ...
    'Units','pixels', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w','FontSize',12, ...
    'Callback',cbk);

mkSlider = @(pp,minv,maxv,val,cbk) uicontrol(pp,'Style','slider', ...
    'Units','pixels', ...
    'Min',minv,'Max',maxv,'Value',val,'Callback',cbk);

mkPopup = @(pp,choices,val,cbk) uicontrol(pp,'Style','popupmenu', ...
    'String',choices,'Value',val, ...
    'Units','pixels', ...
    'Callback',cbk, ...
    'BackgroundColor',[0.20 0.20 0.20], ...
    'ForegroundColor','w', ...
    'FontSize',12);

mkChk = @(pp,s,val,cbk) uicontrol(pp,'Style','checkbox','String',s, ...
    'Units','pixels', ...
    'Value',val,'Callback',cbk, ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold');

mkBtn = @(pp,lbl,cbk,bgcol,fs) uicontrol(pp,'Style','pushbutton','String',lbl, ...
    'Units','pixels','Callback',cbk, ...
    'BackgroundColor',bgcol,'ForegroundColor','w', ...
    'FontSize',fs,'FontWeight','bold');

% ---------------- Overlay panel controls ----------------
lblROIsz  = mkLbl(pOverlay,'ROI size (px)');
slROI     = mkSlider(pOverlay,1,220,roi.size,@(~,~)setROIsize());
txtROIsz = mkEdit(pOverlay, sprintf('%d',roi.size), @onRoiSizeEdited);
set(txtROIsz,'TooltipString','Type ROI size in pixels, press Enter.');

% --- NEW: Add ROI by entering center (x y) ---
lblRoiXY    = mkLbl(pOverlay,'Add ROI by center (x y)');
% Edit box: do NOT add ROI on focus-loss. Only Enter key should add.
ebRoiXY = mkEdit(pOverlay,'',@roiXYNoop);
set(ebRoiXY,'TooltipString','Type x y (pixels), e.g. 120 80 (or 120,80). Press ENTER to add ROI on current slice.');
set(ebRoiXY,'KeyPressFcn',@roiXYKey);

% Button: adds ROI
btnRoiAddXY = mkBtn(pOverlay,'ADD ROI',@addRoiFromXY,[0.30 0.30 0.30],12);
set(btnRoiAddXY,'TooltipString','Adds ROI at the typed x,y (center) using current ROI size on current slice.');
lblBase   = mkLblImp(pOverlay,'Baseline window (s)');
ebBase = mkEdit(pOverlay,'30-240',@onWindowEdited);
set(ebBase,'ForegroundColor',[1.00 0.35 0.35]);

lblSig    = mkLblImp(pOverlay,'Signal window (s)');
ebSig  = mkEdit(pOverlay,'840-900',@onWindowEdited);
set(ebSig,'ForegroundColor',[1.00 0.35 0.35]);

lblAlpha  = mkLbl(pOverlay,'Overlay alpha (%)');
slAlpha   = mkSlider(pOverlay,0,100,100,@updateView);
txtAlpha  = mkValBox(pOverlay,'100');

lblThr    = mkLblImp(pOverlay,'Threshold (abs %)'); 
ebThr    = mkEdit(pOverlay,'0',@updateView);
set(ebThr,'ForegroundColor',[1.00 0.35 0.35]);

lblCax    = mkLblImp(pOverlay,'Display range (min max)');
ebCax     = mkEdit(pOverlay,'0 100',@updateView);
set(ebCax,'ForegroundColor',[1.00 0.35 0.35]);

lblAlphaMod = mkLblImp(pOverlay,'Alpha modulation');
cbAlphaMod  = mkChk(pOverlay,'Alpha modulate by |SCM|',double(state.alphaModOn),@alphaModToggled);

lblModMin = mkLblImp(pOverlay,'Mod Min (abs %)'); 
ebModMin = mkEdit(pOverlay,'20',@updateView);
set(ebModMin,'ForegroundColor',[1.00 0.35 0.35]);

lblModMax = mkLblImp(pOverlay,'Mod Max (abs %)');
ebModMax = mkEdit(pOverlay,'30',@updateView);
set(ebModMax,'ForegroundColor',[1.00 0.35 0.35]);

lblMap    = mkLbl(pOverlay,'Colormap');
popMap    = mkPopup(pOverlay,cmapNames,1,@updateView);

lblSigma  = mkLblImp(pOverlay,'SCM smoothing sigma');
ebSigma  = mkEdit(pOverlay,'1',@computeSCM);
set(ebSigma,'ForegroundColor',[1.00 0.35 0.35]);

lblMask   = mkLbl(pOverlay,'Mask');
btnMaskLoad = mkBtn(pOverlay,'Load mask',@loadMaskCB,[0.20 0.20 0.20],12);
btnMaskClr  = mkBtn(pOverlay,'Clear mask',@clearMaskCB,[0.20 0.20 0.20],12);

btnRoiExport = mkBtn(pOverlay,'EXPORT ROIs (TXT)',@exportROIsCB,[0.10 0.35 0.95],14);
btnScmExport = mkBtn(pOverlay,'EXPORT SCM IMAGE',@exportSCMImageCB,[0.25 0.55 0.25],14);

btnScmSeries = mkBtn(pOverlay,'EXPORT SCM Time SERIES',@exportScmSeries1minCB,[0.55 0.15 0.65],12);

btnUnfreeze  = mkBtn(pOverlay,'Unfreeze Hover',@unfreezeHover,[0.20 0.20 0.20],12);

% ---------------- Underlay panel controls ----------------
lblUnderMode = mkLbl(pUnderlay,'Underlay view');
popUnder = mkPopup(pUnderlay,{ ...
    '1) Legacy (mat2gray)', ...
    '2) Robust clip (1..99%)', ...
    '3) VideoGUI robust (0.5..99.5%)', ...
    '4) Vessel enhance (conectSize/Lev)'}, uState.mode, @underlayModeChanged);

lblBri = mkLbl(pUnderlay,'Underlay brightness');
slBri  = mkSlider(pUnderlay,-0.80,0.80,uState.brightness,@underlaySliderChanged);
txtBri = mkValBox(pUnderlay,sprintf('%.2f',uState.brightness));

lblCon = mkLbl(pUnderlay,'Underlay contrast');
slCon  = mkSlider(pUnderlay,0.10,5.00,uState.contrast,@underlaySliderChanged);
txtCon = mkValBox(pUnderlay,sprintf('%.2f',uState.contrast));

lblGam = mkLbl(pUnderlay,'Underlay gamma');
slGam  = mkSlider(pUnderlay,0.20,4.00,uState.gamma,@underlaySliderChanged);
txtGam = mkValBox(pUnderlay,sprintf('%.2f',uState.gamma));

lblVsz = mkLbl(pUnderlay,'Vessel conectSize (px)');
slVsz  = mkSlider(pUnderlay,0,MAX_CONSIZE,uState.conectSize,@underlaySliderChanged);
set(slVsz,'SliderStep',[1/max(1,MAX_CONSIZE) 10/max(1,MAX_CONSIZE)]);
txtVsz = mkValBox(pUnderlay,sprintf('%d',uState.conectSize));

lblVlv = mkLbl(pUnderlay,sprintf('Vessel conectLev (0..%d)',MAX_CONLEV));
slVlv  = mkSlider(pUnderlay,0,MAX_CONLEV,uState.conectLev,@underlaySliderChanged);
set(slVlv,'SliderStep',[1/max(1,MAX_CONLEV) 10/max(1,MAX_CONLEV)]);
txtVlv = mkValBox(pUnderlay,sprintf('%d',uState.conectLev));

%% ---- Bottom right buttons ----
btnCompute = uicontrol(fig,'Style','pushbutton','String','Compute SCM', ...
    'Units','pixels','Callback',@computeSCM, ...
    'BackgroundColor',[0.30 0.30 0.30],'ForegroundColor','w', ...
    'FontSize',15,'FontWeight','bold');

btnOpenVid = uicontrol(fig,'Style','pushbutton','String','Open Video GUI', ...
    'Units','pixels','Callback',@openVideo, ...
    'BackgroundColor',[0.25 0.55 0.25],'ForegroundColor','w', ...
    'FontSize',15,'FontWeight','bold');

btnHelp = uicontrol(fig,'Style','pushbutton','String','HELP', ...
    'Units','pixels','Callback',@showHelp, ...
    'BackgroundColor',[0.10 0.35 0.95],'ForegroundColor','w', ...
    'FontSize',15,'FontWeight','bold');

btnClose = uicontrol(fig,'Style','pushbutton','String','CLOSE', ...
    'Units','pixels','Callback',@(~,~) close(fig), ...
    'BackgroundColor',[0.75 0.15 0.15],'ForegroundColor','w', ...
    'FontSize',15,'FontWeight','bold');

%% ---------------- MOUSE CALLBACKS ----------------
set(fig,'WindowButtonMotionFcn',@mouseMove);
set(fig,'WindowButtonDownFcn',@mouseClick);
set(fig,'WindowScrollWheelFcn',@mouseScroll);

%% ---------------- RESIZE ----------------
set(fig,'ResizeFcn',@(~,~)layoutUI());

%% ---------------- INITIAL ----------------
alphaModToggled();
updateUnderlayControlsEnable();
updateInfoLines();
layoutUI();

computeSCM();                 % already updates view + windows
redrawROIsForCurrentSlice();  % just draws any stored ROIs

%% ==========================================================
% UI / TAB SWITCHING
%% ==========================================================
function switchTab(which)
    which = lower(char(which));
    if strcmp(which,'overlay')
        set(pOverlay,'Visible','on');
        set(pUnderlay,'Visible','off');
        set(btnTabOverlay,'Value',1,'BackgroundColor',[0.22 0.22 0.22]);
        set(btnTabUnderlay,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
    else
        set(pOverlay,'Visible','off');
        set(pUnderlay,'Visible','on');
        set(btnTabOverlay,'Value',0,'BackgroundColor',[0.12 0.12 0.12]);
        set(btnTabUnderlay,'Value',1,'BackgroundColor',[0.22 0.22 0.22]);
    end
end

function layoutUI()
    pos = get(fig,'Position');
    W = pos(3); Hh = pos(4);

    leftM   = 60;
    rightM  = 40;
    topM    = 72;
    botM    = 60;
    gapX    = 40;
    gapY    = 25;

    panelW  = min(680, max(520, round(0.34*W)));
    btnH    = 56;
    btnGap  = 10;

    yClose  = 32;
    yHelp   = yClose;
    yOpen   = yClose + btnH + btnGap;
    yComp   = yOpen  + btnH + btnGap;
    buttonsTop = yComp + btnH;

    panelX = W - rightM - panelW;
    panelY = buttonsTop + 20;
    panelH = max(280, Hh - panelY - topM);

    set(controlsPanel,'Position',[panelX panelY panelW panelH]);

    set(btnCompute,'Position',[panelX yComp panelW btnH]);
    set(btnOpenVid,'Position',[panelX yOpen panelW btnH]);

    halfW = floor(panelW/2) - 6;
    set(btnHelp ,'Position',[panelX yHelp halfW btnH]);
    set(btnClose,'Position',[panelX+halfW+12 yClose halfW btnH]);

    leftW = max(740, panelX - leftM - gapX);

    tcH   = 230;
    axH   = max(520, Hh - botM - tcH - gapY - topM);

    axX = leftM;
    axY = botM + tcH + gapY;
    set(ax,'Position',[axX axY leftW axH]);
    set(axTC,'Position',[axX botM leftW tcH]);

    set(txtTitle,'Position',[axX axY+axH+10 leftW 26]);

    if ~isempty(slZ) && isgraphics(slZ)
        set(slZ,'Position',[axX-32 axY 22 axH]);
    end
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ,'Position',[axX-60 axY+axH+40 300 28]);
    end

    tabH = 36;
    statusH = 60;

    titlePad = 36;
    set(tabBar,'Position',[10 panelH-tabH-titlePad panelW-20 tabH]);

    btnW = floor((panelW-20-8)/2);
    set(btnTabOverlay ,'Position',[0 0 btnW tabH]);
    set(btnTabUnderlay,'Position',[btnW+8 0 btnW tabH]);

    contentX = 10;
    contentY = 16 + statusH;
    contentW = panelW - 20;
    contentH = panelH - tabH - (titlePad+10) - statusH;

    set(pOverlay ,'Position',[contentX contentY contentW contentH]);
    set(pUnderlay,'Position',[contentX contentY contentW contentH]);

    set(info1,'Position',[contentX 16 contentW statusH]);

    layoutOverlay(contentW, contentH);
    layoutUnder(contentW, contentH);
end

function layoutOverlay(w, h)
    xLabel  = pad;
    wLabel  = 280;
    xCtrl   = xLabel + wLabel + 10;
    xVal    = w - pad - 120;
    wVal    = 120;
    wCtrl   = max(120, xVal - xCtrl - 10);

    y = h - 46;

    setRowSlider(lblROIsz, slROI, txtROIsz);
    % --- NEW row: ROI center (x y) + ADD button ---
set(lblRoiXY,'Position',[xLabel y wLabel rowH]);
set(ebRoiXY ,'Position',[xCtrl  y wCtrl  rowH]);
set(btnRoiAddXY,'Position',[xVal y wVal  rowH]);
y = y - (rowH + gap);
    setRowEdit(lblBase, ebBase);
    setRowEdit(lblSig,  ebSig);

    setRowSlider(lblAlpha, slAlpha, txtAlpha);
    setRowEdit(lblThr, ebThr);
    setRowEdit(lblCax, ebCax);

    set(lblAlphaMod,'Position',[xLabel y wLabel rowH]);
    set(cbAlphaMod ,'Position',[xCtrl y (wCtrl+wVal+10) rowH]);
    y = y - (rowH + gap);

    setRowEdit(lblModMin, ebModMin);
    setRowEdit(lblModMax, ebModMax);

    set(lblMap,'Position',[xLabel y wLabel rowH]);
    set(popMap,'Position',[xCtrl y (wCtrl+wVal+10) rowH]);
    y = y - (rowH + gap);

    setRowEdit(lblSigma, ebSigma);

    set(lblMask,'Position',[xLabel y wLabel rowH]);
    btnGap2 = 12;
    btnW2 = floor((wCtrl+wVal+10 - btnGap2)/2);
    set(btnMaskLoad,'Position',[xCtrl y btnW2 rowH]);
    set(btnMaskClr ,'Position',[xCtrl+btnW2+btnGap2 y btnW2 rowH]);
    y = y - (rowH + gap);

    % gap before export buttons
    gapFromMask = 10;
    y = y - gapFromMask;

    exportDown = 6;
    set(btnRoiExport,'Position',[xLabel (y-exportDown) (w-2*pad) 42]);
    y = y - (42 + gap + exportDown);

    set(btnScmExport,'Position',[xLabel y (w-2*pad) 38]);
    y = y - (38 + gap);

    set(btnScmSeries,'Position',[xLabel y (w-2*pad) 34]);
    y = y - (34 + gap);

    set(btnUnfreeze,'Position',[xLabel y (w-2*pad) rowH]);

    function setRowSlider(lbl, sl, valbox)
        set(lbl,'Position',[xLabel y wLabel rowH]);
        set(sl ,'Position',[xCtrl y+round((rowH-sliderH)/2) wCtrl sliderH]);
        set(valbox,'Position',[xVal y wVal rowH]);
        y = y - (rowH + gap);
    end

    function setRowEdit(lbl, ed)
        set(lbl,'Position',[xLabel y wLabel rowH]);
        set(ed ,'Position',[xVal y wVal rowH]);
        y = y - (rowH + gap);
    end
end

function layoutUnder(w, h)
    xLabel  = pad;
    wLabel  = 280;
    xCtrl   = xLabel + wLabel + 10;
    xVal    = w - pad - 120;
    wVal    = 120;
    wCtrl   = max(120, xVal - xCtrl - 10);

    y = h - 46;

    set(lblUnderMode,'Position',[xLabel y wLabel rowH]);
    set(popUnder,'Position',[xCtrl y (wCtrl+wVal+10) rowH]);
    y = y - (rowH + gap);

    setRowSlider(lblBri, slBri, txtBri);
    setRowSlider(lblCon, slCon, txtCon);
    setRowSlider(lblGam, slGam, txtGam);
    setRowSlider(lblVsz, slVsz, txtVsz);
    setRowSlider(lblVlv, slVlv, txtVlv);

    function setRowSlider(lbl, sl, valbox)
        set(lbl,'Position',[xLabel y wLabel rowH]);
        set(sl ,'Position',[xCtrl y+round((rowH-sliderH)/2) wCtrl sliderH]);
        set(valbox,'Position',[xVal y wVal rowH]);
        y = y - (rowH + gap);
    end
end

%% ==========================================================
% CALLBACKS
%% ==========================================================
    function onWindowEdited(~,~)
    computeSCM();
    end

function sliceChanged(~,~)
    zNew = round(get(slZ,'Value'));
    zNew = max(1,min(nZ,zNew));
    state.z = zNew;
    set(slZ,'Value',state.z);
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ,'String',sprintf('Slice: %d / %d',state.z,nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask,nY,nX,state.z,nZ);
    else
        mask2D = true(nY,nX);
    end
    if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG,'CData',toRGB(processUnderlay(bg2)));

    roi.isFrozen = false;
    set(hLiveRect,'Visible','off');
    set(hLivePSC,'Visible','off');
    set(hRoiCoordTxt,'Visible','off','String','');

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
end

function unfreezeHover(~,~)
    roi.isFrozen = false;
    set(hLiveRect,'Visible','off');
    set(hLivePSC,'Visible','off');
    set(hRoiCoordTxt,'Visible','off','String','');
end

    function setROIsize()
    roi.size = max(1, round(get(slROI,'Value')));
    set(txtROIsz,'String',sprintf('%d',roi.size));
    end

function onRoiSizeEdited(~,~)
    v = str2double(strtrim(getStr(txtROIsz)));
    if ~isfinite(v), v = roi.size; end
    v = round(v);
    v = max(1, min(220, v));     % same slider max
    roi.size = v;
    set(slROI,'Value',roi.size);
    set(txtROIsz,'String',sprintf('%d',roi.size));
end

function mouseMove(~,~)
    if roi.isFrozen, return; end
    if ~isPointerOverImageAxis(), return; end

    cp = get(ax,'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));
    if x<1 || x>nX || ypix<1 || ypix>nY
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
        set(hRoiCoordTxt,'Visible','off','String','');
        return;
    end

    % If pixel hasn't changed, skip
    if x==roi.lastHoverXY(1) && ypix==roi.lastHoverXY(2)
        return;
    end
    roi.lastHoverXY = [x ypix];

    hlf = floor(roi.size/2);
    x1=max(1,x-hlf); x2=min(nX,x+hlf);
    y1=max(1,ypix-hlf); y2=min(nY,ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}),size(roi.colors,1))+1,:);
    set(hLiveRect,'Position',[x1 y1 x2-x1+1 y2-y1+1],'EdgeColor',col,'Visible','on');

    set(hRoiCoordTxt,'String',sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1,x2,y1,y2), ...
        'Visible','on');

    % Throttle PSC update
    tNow = now;
    if roi.lastHoverStamp ~= 0 && (tNow - roi.lastHoverStamp)*86400 < state.hoverMinDtSec
        return;
    end
    roi.lastHoverStamp = tNow;

    tc = computeRoiPSC_idx(x1,x2,y1,y2, state.hoverIdx);
if isempty(tc) || numel(tc) ~= numel(state.tminHover)
    set(hLivePSC,'Visible','off');
    return;
end

set(hLivePSC,'XData', state.tminHover, 'YData', tc, 'Visible','on');

    % Light autoscale (optional)
    mn = min(tc); mx = max(tc);
    if isfinite(mn) && isfinite(mx) && mx>mn
        padY = 0.15*(mx-mn);
        set(axTC,'YLim',[mn-padY mx+padY]);
    end

    drawnow limitrate nocallbacks;
end

function roiXYNoop(~,~)
    % Intentionally empty: prevents double-add when edit box loses focus.
end

function roiXYKey(src, evt)
    try
        if isfield(evt,'Key') && (strcmpi(evt.Key,'return') || strcmpi(evt.Key,'enter'))
            addRoiFromXY();
        end
    catch
    end
end

    function tc = computeRoiPSC(x1,x2,y1,y2)
    % FULL length timecourse (nT) for current slice state.z
    try
        if ndims(PSC)==3
            blk = PSC(y1:y2, x1:x2, :);
            tc  = squeeze(mean(mean(blk,1),2));
        else
            blk = PSC(y1:y2, x1:x2, state.z, :);
            tc  = squeeze(mean(mean(blk,1),2));
        end
        tc = tc(:)'; % row
    catch
        tc = [];
    end

    % Auto-scale (safe)
    if ~isempty(tc) && all(isfinite(tc))
        mn = min(tc); mx = max(tc);
        if isfinite(mn) && isfinite(mx) && mx>mn
            padY = 0.15*(mx-mn);
            set(axTC,'YLim',[mn-padY mx+padY]);
        end
    end
end

function tc = computeRoiPSC_idx(x1,x2,y1,y2, idx)
    % DOWNSAMPLED timecourse for hover (length = numel(idx))
    try
        if ndims(PSC)==3
            blk = PSC(y1:y2, x1:x2, idx);
            tc  = squeeze(mean(mean(blk,1),2));
        else
            blk = PSC(y1:y2, x1:x2, state.z, idx);
            tc  = squeeze(mean(mean(blk,1),2));
        end
        tc = tc(:)'; % row
    catch
        tc = [];
    end
end

function addRoiFromXY(~,~)
    % --- Debounce: prevents accidental double-add (focus loss + click) ---
    tNow = now;
    if roi.lastAddStamp ~= 0
        if (tNow - roi.lastAddStamp) * 86400 < 0.20   % 200 ms
            return;
        end
    end
    roi.lastAddStamp = tNow;

    % Read "x y" or "x,y"
    s = strtrim(getStr(ebRoiXY));
    if isempty(s), return; end
    s = strrep(s,',',' ');
    v = sscanf(s,'%f');
    if numel(v) < 2 || ~isfinite(v(1)) || ~isfinite(v(2))
        warndlg('Enter ROI center as:  x y   (e.g., 120 80 or 120,80)','Add ROI');
        return;
    end

    x = round(v(1));
    ypix = round(v(2));

    % Clamp to bounds
    x    = clamp(x,    1, nX);
    ypix = clamp(ypix, 1, nY);

    % Center -> rectangle (same logic as mouseClick)
    hlf = floor(roi.size/2);
    x1 = max(1, x-hlf); x2 = min(nX, x+hlf);
    y1 = max(1, ypix-hlf); y2 = min(nY, ypix+hlf);

    % Color chosen like existing
    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1)) + 1, :);

    % Add ROI with stable ID
    ROI_byZ{state.z}(end+1) = struct( ...
        'id', roi.nextId, 'x1', x1, 'x2', x2, 'y1', y1, 'y2', y2, 'color', col);
    roi.nextId = roi.nextId + 1;

    roi.isFrozen = true;

    redrawROIsForCurrentSlice();

    % Show live rectangle + PSC
    set(hLiveRect,'Position',[x1 y1 x2-x1+1 y2-y1+1],'EdgeColor',col,'Visible','on');
   tcHover = computeRoiPSC_idx(x1,x2,y1,y2, state.hoverIdx);
if ~isempty(tcHover) && numel(tcHover)==numel(state.tminHover)
    set(hLivePSC,'XData', state.tminHover, 'YData', tcHover, 'Visible','on');
else
    set(hLivePSC,'Visible','off');
end

    set(hRoiCoordTxt,'String',sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1,x2,y1,y2), ...
        'Visible','on');

    drawTimeWindows();
end


function mouseScroll(~,evt)
    if nZ<=1, return; end
    if ~isPointerOverImageAxis(), return; end
    dz = -sign(evt.VerticalScrollCount);
    if dz==0, return; end
    state.z = max(1,min(nZ,state.z+dz));
    if ~isempty(slZ) && isgraphics(slZ), set(slZ,'Value',state.z); end
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ,'String',sprintf('Slice: %d / %d',state.z,nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask,nY,nX,state.z,nZ);
    else
        mask2D = true(nY,nX);
    end
    if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG,'CData',toRGB(processUnderlay(bg2)));

    roi.isFrozen = false;
    set(hRoiCoordTxt,'Visible','off','String','');

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
end

function mouseClick(~,~)
    if ~isPointerOverImageAxis(), return; end
    cp = get(ax,'CurrentPoint');
    x=round(cp(1,1)); ypix=round(cp(1,2));
    if x<1||x>nX||ypix<1||ypix>nY, return; end

    hlf=floor(roi.size/2);
    x1=max(1,x-hlf); x2=min(nX,x+hlf);
    y1=max(1,ypix-hlf); y2=min(nY,ypix+hlf);

    type=get(fig,'SelectionType');
    if strcmp(type,'normal')
        roi.isFrozen=true;
        tc=computeRoiPSC(x1,x2,y1,y2);
        if numel(tc)~=nT, return; end
        col=roi.colors(mod(numel(ROI_byZ{state.z}),size(roi.colors,1))+1,:);
        ROI_byZ{state.z}(end+1)=struct( ...
    'id',roi.nextId,'x1',x1,'x2',x2,'y1',y1,'y2',y2,'color',col);
roi.nextId = roi.nextId + 1;
        redrawROIsForCurrentSlice();
        % Also show hover-like live trace for the clicked ROI
tcHover = computeRoiPSC_idx(x1,x2,y1,y2, state.hoverIdx);
if ~isempty(tcHover) && numel(tcHover)==numel(state.tminHover)
    set(hLivePSC,'XData', state.tminHover, 'YData', tcHover, 'Visible','on');
end

        set(hRoiCoordTxt,'String',sprintf('ROI z=%d | x:%d-%d  y:%d-%d', state.z, x1,x2,y1,y2), ...
            'Visible','on');

        drawTimeWindows();
    elseif strcmp(type,'alt')
        roi.isFrozen=false;
        if ~isempty(ROI_byZ{state.z})
            ROI=ROI_byZ{state.z};
            ctr=arrayfun(@(r)[(r.x1+r.x2)/2,(r.y1+r.y2)/2],ROI,'uni',0);
            ctr=cat(1,ctr{:});
            [~,i]=min(sum((ctr-[x ypix]).^2,2));
            ROI(i)=[];
            ROI_byZ{state.z}=ROI;
            redrawROIsForCurrentSlice();
        end
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
        set(hRoiCoordTxt,'Visible','off','String','');
    end
end

function computeSCM(~,~)
    [b0,b1]=parseRangeSafe(getStr(ebBase),baseline.start,baseline.end);
    [s0,s1]=parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

    sig = str2double(getStr(ebSigma));
    if ~isfinite(sig), sig = 0; end

    if ~isVolMode
        b0i=clamp(round(b0/TR)+1,1,nT); b1i=clamp(round(b1/TR)+1,1,nT);
        s0i=clamp(round(s0/TR)+1,1,nT); s1i=clamp(round(s1/TR)+1,1,nT);
    else
        b0i=clamp(round(b0),1,nT); b1i=clamp(round(b1),1,nT);
        s0i=clamp(round(s0),1,nT); s1i=clamp(round(s1),1,nT);
    end
    if b1i<b0i, tmp=b0i; b0i=b1i; b1i=tmp; end
    if s1i<s0i, tmp=s0i; s0i=s1i; s1i=tmp; end

    PSCz = getPSCForSlice(state.z);
    baseMap = mean(PSCz(:,:,b0i:b1i),3);
    sigMap  = mean(PSCz(:,:,s0i:s1i),3);
    map     = sigMap - baseMap;

    if sig>0
        map = smooth2D_gauss(map, sig);
    end

    % Hard mask outside brain
    map(~mask2D) = 0;
    set(hOV,'CData',map);
    updateView();
    drawTimeWindows();
end

function alphaModToggled(~,~)
    state.alphaModOn = logical(get(cbAlphaMod,'Value'));
    if state.alphaModOn
        set(ebModMin,'Enable','on','ForegroundColor',[1.00 0.35 0.35],'BackgroundColor',[0.20 0.20 0.20]);
        set(ebModMax,'Enable','on','ForegroundColor',[1.00 0.35 0.35],'BackgroundColor',[0.20 0.20 0.20]);
    else
        set(ebModMin,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
        set(ebModMax,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
    end
    updateView();
end

function updateView(~,~)
    a = get(slAlpha,'Value');
    set(txtAlpha,'String',sprintf('%.0f',a));

    thr = str2double(getStr(ebThr)); if ~isfinite(thr), thr=0; end

    caxv = sscanf(getStr(ebCax),'%f');
    if numel(caxv)>=2 && isfinite(caxv(1)) && isfinite(caxv(2)) && caxv(2)~=caxv(1)
        state.cax = caxv(1:2)';
        if state.cax(2) < state.cax(1)
            state.cax = fliplr(state.cax);
        end
    end

    maps = get(popMap,'String');
    idx  = get(popMap,'Value');
    if iscell(maps), cmapName = maps{idx};
    else,            cmapName = strtrim(maps(idx,:));
    end
    setOverlayColormap(cmapName);

    mMin = str2double(getStr(ebModMin)); if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax)); if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin, tmp=mMin; mMin=mMax; mMax=tmp; end
    state.modMin = mMin; state.modMax = mMax;

    ov = get(hOV,'CData');

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
        mod = min(max(mod,0),1);

        alpha = (a/100) .* mod .* thrMask .* baseMask;
    end

    set(hOV,'AlphaData',alpha);
    caxis(ax, state.cax);
end

function underlayModeChanged(~,~)
    uState.mode = get(popUnder,'Value');
    updateUnderlayControlsEnable();
    set(hBG,'CData',toRGB(processUnderlay(getBg2DForSlice(state.z))));
    updateInfoLines();
end

function underlaySliderChanged(~,~)
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

    set(hBG,'CData',toRGB(processUnderlay(getBg2DForSlice(state.z))));
    updateInfoLines();
end

function updateUnderlayControlsEnable()
    isVessel = (uState.mode==4);
    set(slVsz,'Enable',onoff(isVessel)); set(txtVsz,'Enable',onoff(isVessel));
    set(slVlv,'Enable',onoff(isVessel)); set(txtVlv,'Enable',onoff(isVessel));
end

function updateInfoLines()
    modeNames = {'Legacy','Robust(1..99)','VideoGUI(0.5..99.5)','Vessel enhance'};
    m = uState.mode; if m<1 || m>4, m=3; end
    set(info1,'String',sprintf('TR = %.4gs | Slice %d/%d | Underlay: %s',TR,state.z,nZ,modeNames{m}));
end
function s = onoff(tf), if tf, s='on'; else, s='off'; end, end %#ok<SEPEX>

%% ===================== ROI EXPORT =====================
function exportROIsCB(~,~)
    % Export all ROIs currently stored in ROI_byZ.
    % Naming:
    %   ROI<SET>_d1.txt, ROI<SET>_d2.txt, ...
    % SET is auto-chosen once per SCM_gui session by scanning existing ROI*.txt.
    % Within the same SCM_gui session, repeated exports continue d numbering.

    % Count total ROIs in memory
    nTot = 0;
    for zz=1:nZ
        nTot = nTot + numel(ROI_byZ{zz});
    end
    if nTot == 0
        warndlg('No ROIs to export. Add ROIs first.','Export ROIs');
        return;
    end

    try
        roiDir = getAutoRoiDir();
        if ~exist(roiDir,'dir'), mkdir(roiDir); end

        % --- 1) Choose ROI<SET> once per GUI session ---
        if ~isfield(roi,'exportSetId') || isempty(roi.exportSetId) || ~isfinite(roi.exportSetId)
            roi.exportSetId = detectNextRoiSetId(roiDir);   % ROI1, ROI2, ...
        end
        setId = roi.exportSetId;

        % --- 2) Continue d index for this ROI<SET> if files already exist ---
        dStart = detectNextDIndexForSet(roiDir, setId);      % next free d#

        % --- 3) Flatten all ROIs (stable order: slice then ROI marker id) ---
        flat = struct('z',{},'id',{},'x1',{},'x2',{},'y1',{},'y2',{},'color',{});
        for zz=1:nZ
            ROI = ROI_byZ{zz};
            for k=1:numel(ROI)
                r = ROI(k);
                flat(end+1) = struct('z',zz,'id',r.id,'x1',r.x1,'x2',r.x2,'y1',r.y1,'y2',r.y2,'color',r.color); %#ok<AGROW>
            end
        end

        % sort by z then id (so exported order is deterministic)
        if ~isempty(flat)
            Zs  = [flat.z]';
            IDs = [flat.id]';
            [~,ord] = sortrows([Zs IDs],[1 2]);
            flat = flat(ord);
        end

        % --- 4) Write files ROI<SET>_d#.txt ---
        dIdx = dStart;
        for i=1:numel(flat)
            r = flat(i);

            outFile = fullfile(roiDir, sprintf('ROI%d_d%d.txt', setId, dIdx));

            % safety: if somehow exists, bump until free
            while exist(outFile,'file')==2
                dIdx = dIdx + 1;
                outFile = fullfile(roiDir, sprintf('ROI%d_d%d.txt', setId, dIdx));
            end

            fid = fopen(outFile,'w');
            if fid<0
                error('Could not write ROI file: %s', outFile);
            end

            fprintf(fid,'# ROI export from SCM_gui\n');
            fprintf(fid,'# Date: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
            fprintf(fid,'# FileLabel: %s\n', fileLabel);
            fprintf(fid,'# TR_sec: %.6g\n', TR);
            fprintf(fid,'# nY nX nZ nT: %d %d %d %d\n', nY,nX,nZ,nT);

            fprintf(fid,'# ROI_SET_ID: %d\n', setId);     % ROI<SET>
            fprintf(fid,'# ROI_D_INDEX: %d\n', dIdx);     % d#
            fprintf(fid,'# ROI_MARKER_ID: %d\n', r.id);   % number shown on GUI rectangle
            fprintf(fid,'# SLICE: %d\n', r.z);

            fprintf(fid,'# BaselineWindow: %s\n', getStr(ebBase));
            fprintf(fid,'# SignalWindow:   %s\n', getStr(ebSig));

            fprintf(fid,'# x1 x2 y1 y2\n');
            fprintf(fid,'%d %d %d %d\n', r.x1, r.x2, r.y1, r.y2);

            fprintf(fid,'# color_rgb\n');
            fprintf(fid,'%.6f %.6f %.6f\n', r.color(1), r.color(2), r.color(3));

            % PSC timecourse for this ROI
            % (needs correct slice for computeRoiPSC -> temporarily set state.z)
            zOld = state.z;
            state.z = r.z;
            tc = computeRoiPSC(r.x1,r.x2,r.y1,r.y2);
            state.z = zOld;

            if isempty(tc) || numel(tc) ~= nT
                tc = nan(1,nT);
            end

            fprintf(fid,'# columns: time_sec\ttime_min\tPSC\n');
            for ii=1:nT
                fprintf(fid,'%.6f\t%.6f\t%.6f\n', tsec(ii), tmin(ii), tc(ii));
            end

            fclose(fid);
            dIdx = dIdx + 1;
        end

        msgbox(sprintf('Exported %d ROI(s) to:\n%s\n(as ROI%d_d#.txt)', numel(flat), roiDir, setId), ...
            'Export ROIs');

    catch ME
        errordlg(ME.message,'ROI export failed');
    end
end

function nextIdx = getNextRoiIndex(roiDir)
    nextIdx = 1;
    if exist(roiDir,'dir')~=7, return; end
    d = dir(fullfile(roiDir,'roi*.txt'));
    if isempty(d), return; end

    nums = nan(1,numel(d));
    for i=1:numel(d)
        m = regexp(d(i).name,'^roi(\d+)\.txt$','tokens','once');
        if ~isempty(m)
            nums(i) = str2double(m{1});
        end
    end
    nums = nums(isfinite(nums) & nums>=1);
    if isempty(nums), nextIdx = 1; else, nextIdx = max(nums) + 1; end
end

function roiDir = getAutoRoiDir()
    base = '';

    try
        if isstruct(par)
            if isfield(par,'loadedPath') && ~isempty(par.loadedPath)
                base = char(par.loadedPath);
            end
            if isempty(base) && isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf,'file'), base = fileparts(lf); end
            end
            if isempty(base) && isfield(par,'rawPath') && ~isempty(par.rawPath)
                base = char(par.rawPath);
            end
            if isempty(base) && isfield(par,'exportPath') && ~isempty(par.exportPath)
                base = char(par.exportPath);
            end
        end
    catch
        base = '';
    end
    if isempty(base), base = pwd; end

    analysedRoot = '';
    try
        if isstruct(par) && isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir')
            analysedRoot = char(par.exportPath);
        end
    catch
    end
    if isempty(analysedRoot)
        analysedRoot = guessAnalysedRoot(base);
    end

    dsType = deriveDatasetType();
    tag0   = deriveDatasetTag();
    tag    = stripLeadingType(tag0, dsType);

    roiDir = fullfile(analysedRoot, 'ROI', dsType, tag);
end

%% ===================== SCM IMAGE EXPORT =====================
function exportSCMImageCB(~,~)
    tf = [];
    try
        outDir = getAutoScmDir();
        if ~exist(outDir,'dir'), mkdir(outDir); end

        baseName = sprintf('%s_SCM_z%02d_%s', sanitizeName(fileLabel), state.z, datestr(now,'yyyymmdd_HHMMSS'));

        outPng = fullfile(outDir, [baseName '.png']);
        outTif = fullfile(outDir, [baseName '.tif']);
        outJpg = fullfile(outDir, [baseName '.jpg']);

        tf = figure('Visible','off', ...
            'Color',[0.05 0.05 0.05], ...
            'InvertHardcopy','off', ...
            'Units','pixels', ...
            'Position',[200 120 1400 980]);

        ax2 = axes('Parent',tf,'Units','normalized','Position',[0.06 0.10 0.74 0.84]);
        axis(ax2,'image'); axis(ax2,'off'); set(ax2,'YDir','reverse'); hold(ax2,'on');

        bgRGB = get(hBG,'CData');
        image(ax2, bgRGB);

        ov  = get(hOV,'CData');
        al  = get(hOV,'AlphaData');
        h2  = imagesc(ax2, ov);
        set(h2,'AlphaData', al);

        try
            colormap(ax2, colormap(ax));
        catch
            colormap(ax2, colormap(fig));
        end
        caxis(ax2, state.cax);

        ROI = ROI_byZ{state.z};
        for k=1:numel(ROI)
            r = ROI(k);
            rectangle(ax2,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
                'EdgeColor',r.color,'LineWidth',2);
        end

        title(ax2, sprintf('%s | Slice %d/%d', fileLabel, state.z, nZ), ...
            'Color','w','FontWeight','bold','Interpreter','none');

        cb2 = colorbar(ax2);
        cb2.Color = 'w';
        cb2.Label.String = 'Signal change (%)';
        cb2.FontSize = 12;

        set(tf,'PaperPositionMode','auto');

        print(tf, outPng, '-dpng',  '-r300', '-opengl');
        print(tf, outTif, '-dtiff', '-r300', '-opengl');
        print(tf, outJpg, '-djpeg', '-r300', '-opengl');

        if isgraphics(tf), close(tf); end
        tf = [];

        try
            set(info1,'String',sprintf('Saved SCM: %s (png/tif/jpg)', outDir));
        catch
        end

    catch ME
        try, if ~isempty(tf) && isgraphics(tf), close(tf); end, catch, end
        errordlg(ME.message,'Export SCM Image failed');
    end
end

function scmDir = getAutoScmDir()
    base = '';
    try
        if isstruct(par)
            if isfield(par,'loadedPath') && ~isempty(par.loadedPath)
                base = char(par.loadedPath);
            end
            if isempty(base) && isfield(par,'loadedFile') && ~isempty(par.loadedFile)
                lf = char(par.loadedFile);
                if exist(lf,'file'), base = fileparts(lf); end
            end
            if isempty(base) && isfield(par,'rawPath') && ~isempty(par.rawPath)
                base = char(par.rawPath);
            end
            if isempty(base) && isfield(par,'exportPath') && ~isempty(par.exportPath)
                base = char(par.exportPath);
            end
        end
    catch
        base = '';
    end
    if isempty(base), base = pwd; end

    analysedRoot = '';
    try
        if isstruct(par) && isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir')
            analysedRoot = char(par.exportPath);
        end
    catch
    end
    if isempty(analysedRoot)
        analysedRoot = guessAnalysedRoot(base);
    end

    scmDir = fullfile(analysedRoot, 'SCM');
end

%% ===================== EXPORT 1-MIN SCM SERIES =====================
function exportScmSeries1minCB(~,~)

    EXPORT_DPI_TILES  = 200;
    EXPORT_DPI_SLIDES = 200;
    SAVE_TIF = true;
    SAVE_JPG = true;

    try
        a = inputdlg({ ...
            'Injection start (sec). Empty if unknown:', ...
            'Window length (sec) (default 60):', ...
            'Max minutes to export (empty=all):', ...
            'Export PPT too? (1=yes,0=no) (default 1):'}, ...
            'Export SCM series', 1, {'', '60', '', '1'});
        if isempty(a), return; end

        injSec = str2double(strtrim(a{1})); if ~isfinite(injSec), injSec = NaN; end
        winLen = str2double(strtrim(a{2})); if ~isfinite(winLen) || winLen<=0, winLen = 60; end
        maxMin = str2double(strtrim(a{3})); if ~isfinite(maxMin) || maxMin<=0, maxMin = NaN; end
        doPPT  = str2double(strtrim(a{4})); if ~isfinite(doPPT), doPPT = 1; end
        doPPT  = (doPPT ~= 0);

        rootScm = getAutoScmDir();
        if ~exist(rootScm,'dir'), mkdir(rootScm); end
        stamp = datestr(now,'yyyymmdd_HHMMSS');
        outDir = fullfile(rootScm, ['SCM_series_' stamp]);
        if ~exist(outDir,'dir'), mkdir(outDir); end

        dirPNG = fullfile(outDir,'tiles_png'); if ~exist(dirPNG,'dir'), mkdir(dirPNG); end
        dirTIF = fullfile(outDir,'tiles_tif'); if ~exist(dirTIF,'dir'), mkdir(dirTIF); end
        dirJPG = fullfile(outDir,'tiles_jpg'); if ~exist(dirJPG,'dir'), mkdir(dirJPG); end

        tmpSLD = tempname;
        mkdir(tmpSLD);

        try
            set(info1,'String',{ ...
                'Saving to:', ...
                shortenPath(outDir, 120), ...
                'Tip: hover here to see full path'});
            set(info1,'TooltipString',outDir);
            drawnow;
        catch
        end

        [b0,b1] = parseRangeSafe(getStr(ebBase), baseline.start, baseline.end);
        if ~isVolMode
            b0i = clamp(round(b0/TR)+1,1,nT);
            b1i = clamp(round(b1/TR)+1,1,nT);
        else
            b0i = clamp(round(b0),1,nT);
            b1i = clamp(round(b1),1,nT);
        end
        if b1i<b0i, tmp=b0i; b0i=b1i; b1i=tmp; end

        PSCz = getPSCForSlice(state.z);
        baseMap = mean(PSCz(:,:,b0i:b1i),3);

        bgRGB = get(hBG,'CData');
        cm    = colormap(ax);
        caxV  = state.cax;

        sigma = str2double(getStr(ebSigma));
        if ~isfinite(sigma), sigma = 0; end

        thrStr  = strtrim(getStr(ebThr));
        caxStr  = strtrim(getStr(ebCax));
        baseStr = strtrim(getStr(ebBase));
        aStr    = sprintf('Alpha=%s%%', strtrim(getStr(txtAlpha)));
        modStr  = sprintf('AlphaMod=%d [%s..%s]', double(state.alphaModOn), strtrim(getStr(ebModMin)), strtrim(getStr(ebModMax)));
        sigStr  = sprintf('Sigma=%g', sigma);

        footerInfo = sprintf('Thr=%s | CAX=%s | Base=%s | %s | %s | %s', thrStr, caxStr, baseStr, aStr, modStr, sigStr);

        totalSec = (nT-1)*TR;
        starts = 0:winLen:(floor(totalSec/winLen)*winLen);
        if isfinite(maxMin)
            maxSec = maxMin*60;
            starts = starts(starts < maxSec);
        end

        figT = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
        set(figT,'Units','pixels','Position',[50 50 1200 880]);
        axT = axes('Parent',figT,'Units','normalized','Position',[0 0 1 1]);
        axis(axT,'image'); axis(axT,'off'); set(axT,'YDir','reverse'); hold(axT,'on');
        image(axT, bgRGB);
        hT = imagesc(axT, zeros(nY,nX));
        set(hT,'AlphaData', zeros(nY,nX));
        colormap(axT, cm); caxis(axT, caxV);
        hold(axT,'off');
        set(figT,'PaperPositionMode','auto');

        tilePNG = {};
        tileLBL = {};
        nSaved = 0;

        for wi = 1:numel(starts)
            s0 = starts(wi);
            s1 = s0 + winLen;

            idxSig = find(tsec >= s0 & tsec < s1);
            if isempty(idxSig), continue; end

            sigMap = mean(PSCz(:,:,idxSig),3);
            map = sigMap - baseMap;

            if sigma > 0
                map = smooth2D_gauss(map, sigma);
            end
            map(~mask2D) = 0;

            alpha = alphaFromCurrentSettings(map);

            minIdx = floor(s0/winLen) + 1;

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
                lbl = sprintf('%.0f–%.0fs | %d min', s0, s1, minIdx);
            else
                lbl = sprintf('%.0f–%.0fs | %d min (%s)', s0, s1, minIdx, phase);
            end

            baseName = sprintf('%s_z%02d_w%03d_%0.0f-%0.0fs', sanitizeName(fileLabel), state.z, minIdx, s0, s1);

            outPng = fullfile(dirPNG, [baseName '.png']);
            outTif = fullfile(dirTIF, [baseName '.tif']);
            outJpg = fullfile(dirJPG, [baseName '.jpg']);

            set(hT,'CData',map);
            set(hT,'AlphaData',alpha);
            colormap(axT, cm); caxis(axT, caxV);

            print(figT, outPng, '-dpng',  sprintf('-r%d',EXPORT_DPI_TILES), '-opengl');
            if SAVE_TIF
                print(figT, outTif, '-dtiff', sprintf('-r%d',EXPORT_DPI_TILES), '-opengl');
            end
            if SAVE_JPG
                print(figT, outJpg, '-djpeg', sprintf('-r%d',EXPORT_DPI_TILES), '-opengl');
            end

            nSaved = nSaved + 1;
            tilePNG{end+1} = outPng; %#ok<AGROW>
            tileLBL{end+1} = lbl;    %#ok<AGROW>

            try
                set(info1,'String',sprintf('Exporting tiles... %d / %d  |  %s', nSaved, numel(starts), shortenPath(outDir, 55)));
                set(info1,'TooltipString',outDir);
                drawnow limitrate;
            catch
            end
        end

        if isgraphics(figT), close(figT); end

        if isempty(tilePNG)
            errordlg('No windows exported (maybe too short recording / window settings).','SCM series');
            return;
        end

        % ---- build montage slide PNGs (6 per slide) ----
        slidePNGs = {};
        perSlide = 6;
        nSlides = ceil(numel(tilePNG)/perSlide);

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
            slidePNGs{end+1} = outSlide; %#ok<AGROW>

            try
                set(info1,'String',sprintf('Building slide PNGs... %d / %d  |  %s', si, nSlides, shortenPath(outDir, 55)));
                set(info1,'TooltipString',outDir);
                drawnow limitrate;
            catch
            end
        end

        % ---- PPT: now use SIMPLE helper on montage PNGs ----
        pptPath = '';
        if doPPT
            hasPpt = (exist('mlreportgen.ppt.Presentation','class') == 8);
            if hasPpt
                pptPath = fullfile(outDir, sprintf('%s_series_%s.pptx', sanitizeName(fileLabel), stamp));
                try
                    writePptFromSlidePNGs(pptPath, slidePNGs);
                catch MEppt
                    warning('[SCM SERIES] PPT creation failed: %s', MEppt.message);
                    pptPath = '';
                end
            else
                fprintf('[SCM SERIES] PPT API not available (mlreportgen.ppt). Kept PNGs only.\n');
            end
        end

        % ---- cleanup temporary slidePNGs and folder ----
        try
            for ii = 1:numel(slidePNGs)
                if exist(slidePNGs{ii},'file')==2
                    delete(slidePNGs{ii});
                end
            end
            if exist(tmpSLD,'dir')==7
                rmdir(tmpSLD,'s');
            end
        catch
        end

        % ---- final status ----
        try
            if ~isempty(pptPath)
                set(info1,'String',['DONE. Saved: ' shortenPath(outDir, 80) '  (PPT + PNGs)']);
            else
                set(info1,'String',['DONE. Saved: ' shortenPath(outDir, 80) '  (PNGs)']);
            end
            set(info1,'TooltipString',outDir);
        catch
        end
        fprintf('[SCM SERIES] DONE. Folder: %s\n', outDir);
        if ~isempty(pptPath), fprintf('[SCM SERIES] PPT: %s\n', pptPath); end

    catch ME
        errordlg(ME.message,'Export SCM series failed');
    end
end

function alpha = alphaFromCurrentSettings(ov)
    a = get(slAlpha,'Value'); 
    thr = str2double(getStr(ebThr)); if ~isfinite(thr), thr = 0; end

    mMin = str2double(getStr(ebModMin)); if ~isfinite(mMin), mMin = state.modMin; end
    mMax = str2double(getStr(ebModMax)); if ~isfinite(mMax), mMax = state.modMax; end
    if mMax < mMin, tmp=mMin; mMin=mMax; mMax=tmp; end

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
        mod = min(max(mod,0),1);

        alpha = (a/100) .* mod .* thrMask .* baseMask;
    end
end

function renderSlideMontagePNG(outFile, pngList, lblList, cm, caxV, titleStr, footerStr, dpiVal)
    figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
    set(figS,'Units','inches','Position',[0.5 0.5 13.333 7.5]);
    set(figS,'PaperPositionMode','auto');

    annotation(figS,'textbox',[0.02 0.885 0.96 0.11], ...
        'String',titleStr, ...
        'Color','w','EdgeColor','none', ...
        'FontName','Arial','FontSize',14,'FontWeight','bold', ...
        'HorizontalAlignment','center','Interpreter','none');

    annotation(figS,'textbox',[0.42 0.01 0.56 0.06], ...
        'String',footerStr, 'Color','w', 'EdgeColor','none', ...
        'FontName','Arial','FontSize',11,'FontWeight','bold', ...
        'HorizontalAlignment','right','Interpreter','none');

    axCB = axes('Parent',figS,'Position',[0.03 0.14 0.02 0.74],'Visible','off');
    imagesc(axCB,[0 1;0 1]);
    colormap(axCB, cm);
    caxis(axCB, caxV);
    cbx = colorbar(axCB,'Position',[0.03 0.14 0.02 0.74]);
    cbx.Color = 'w';
    cbx.FontName = 'Arial';
    cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)';
    cbx.Label.Color = 'w';

    x0 = 0.08; x1 = 0.98;
    yBot = 0.12; yTop = 0.86;
    gridH = (yTop - yBot);
    rowGap = 0.06;
    colGap = 0.02;

    cellH = (gridH - rowGap) / 2;
    cellW = (x1 - x0 - 2*colGap) / 3;

    % top row
    for k=1:3
        if k>numel(pngList), break; end
        x = x0 + (k-1)*(cellW+colGap);
        y = yBot + cellH + rowGap;
        axI = axes('Parent',figS,'Position',[x y cellW cellH]);
        imshow(imread(pngList{k}),'Parent',axI);
        axis(axI,'off');

        annotation(figS,'textbox',[x y+cellH+0.005 cellW 0.035], ...
            'String',lblList{k},'Color','w','EdgeColor','none', ...
            'FontName','Arial','FontSize',13,'FontWeight','bold', ...
            'HorizontalAlignment','center','Interpreter','none');
    end

    % bottom row
    for k=4:6
        if k>numel(pngList), break; end
        c = k-3;
        x = x0 + (c-1)*(cellW+colGap);
        y = yBot;
        axI = axes('Parent',figS,'Position',[x y cellW cellH]);
        imshow(imread(pngList{k}),'Parent',axI);
        axis(axI,'off');

        annotation(figS,'textbox',[x y+cellH+0.005 cellW 0.035], ...
            'String',lblList{k},'Color','w','EdgeColor','none', ...
            'FontName','Arial','FontSize',13,'FontWeight','bold', ...
            'HorizontalAlignment','center','Interpreter','none');
    end

    print(figS, outFile, '-dpng', sprintf('-r%d',dpiVal), '-opengl');
    close(figS);
end

function writePptFromSlidePNGs(pptPath, slidePNGs)
    import mlreportgen.ppt.*

    ppt = Presentation(pptPath);
    open(ppt);

    for i = 1:numel(slidePNGs)
        if exist(slidePNGs{i},'file') ~= 2
            warning('Slide image missing, skipping: %s', slidePNGs{i});
            continue;
        end

        try
            slide = add(ppt,'Blank');
        catch
            slide = add(ppt);
        end

        pic = Picture(slidePNGs{i});
        pic.X = '0in';  
        pic.Y = '0in';
        pic.Width  = '13.333in';
        pic.Height = '7.5in';
        add(slide, pic);
    end

    close(ppt);
end

function titleStr = makeFullTitle(lbl)
    s = char(lbl);
    s = regexprep(s,'\|?\s*File:.*$','');
    s = shortenMiddle(s, 110);
    titleStr = s;
end

function s = getAnimalID(lbl)
    s0 = char(lbl);
    tok = regexp(s0,'(WT\d+[A-Za-z]?(?:_\w+)?_S\d+)','tokens','once');
    if ~isempty(tok), s = tok{1}; return; end
    tok = regexp(s0,'(WT\d+[A-Za-z]?)','tokens','once');
    if ~isempty(tok), s = tok{1}; return; end
    s = 'Animal';
end

function out = shortenMiddle(s, maxLen)
    s = char(s);
    if numel(s) <= maxLen, out = s; return; end
    keep = floor((maxLen-3)/2);
    out = [s(1:keep) '...' s(end-keep+1:end)];
end

function s = shortenPath(p, maxLen)
    p = char(p);
    if numel(p) <= maxLen, s = p; return; end
    keep = floor((maxLen-3)/2);
    s = [p(1:keep) '...' p(end-keep+1:end)];
end

function analysedRoot = guessAnalysedRoot(p0)
    p0 = char(p0);
    if exist(p0,'dir') ~= 7
        try, p0 = fileparts(p0); catch, end
    end

    if contains(p0,'AnalysedData')
        analysedRoot = p0;
        return;
    end
    if contains(p0,'RawData')
        analysedRoot = strrep(p0,'RawData','AnalysedData');
        if exist(analysedRoot,'dir')~=7
            try, mkdir(analysedRoot); catch, end
        end
        return;
    end

    parent = fileparts(p0);
    sib = fullfile(parent,'AnalysedData');
    if exist(sib,'dir')==7
        analysedRoot = sib;
        return;
    end

    analysedRoot = p0;
end

function dsType = deriveDatasetType()
    s = '';
    try
        if isstruct(par)
            if isfield(par,'activeDataset') && ~isempty(par.activeDataset), s = char(par.activeDataset); end
            if isempty(s) && isfield(par,'loadedName') && ~isempty(par.loadedName), s = char(par.loadedName); end
            if isempty(s) && isfield(par,'loadedFile') && ~isempty(par.loadedFile), s = char(par.loadedFile); end
            if isempty(s) && isfield(par,'file') && ~isempty(par.file), s = char(par.file); end
        end
    catch
        s = '';
    end
    if isempty(s), s = fileLabel; end
    
    try
        ss = char(s);
        ss = regexprep(ss,'\.nii\.gz$','', 'ignorecase');
        if contains(ss, filesep) || contains(ss,'/') || contains(ss,'\')
            [~, ss] = fileparts(ss);
        end
        s = ss;
    catch
    end

    if isstring(s), s = char(s); end
    s = lower(strtrim(s));
    s = regexprep(s,'\|.*$','');
    s = regexprep(s,'\(.*$','');
    s = strtrim(s);

    if contains(s,'gabriel'), dsType = 'gabriel'; return; end
    if ~isempty(regexp(s,'(^|[_\-\s])raw([_\-\s]|$)','once'))
        dsType = 'raw'; return;
    end

    tok = regexp(s,'^[a-z0-9]+','match','once');
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
            if isfield(par,'loadedFile') && ~isempty(par.loadedFile), s = char(par.loadedFile); end
            if isempty(s) && isfield(par,'loadedName') && ~isempty(par.loadedName), s = char(par.loadedName); end
            if isempty(s) && isfield(par,'file') && ~isempty(par.file), s = char(par.file); end
            if isempty(s) && isfield(par,'activeDataset') && ~isempty(par.activeDataset), s = char(par.activeDataset); end
        end
    catch
        s = '';
    end
    if isempty(s), s = fileLabel; end

    s = regexprep(s,'\|.*$','');
    s = regexprep(s,'\(.*$','');
    s = strtrim(s);

    s = regexprep(s,'\.nii(\.gz)?$','', 'ignorecase');
    s = regexprep(s,'\.mat$','', 'ignorecase');

    sp = strfind(s,' ');
    if ~isempty(sp), s = s(1:sp(1)-1); end

    s = sanitizeName(s);
    if isempty(s), s = 'dataset'; end
    tag = s;
end

function s = sanitizeName(s)
    if isstring(s), s = char(s); end
    s = char(s);
    s = strrep(s, filesep, '_');
    s = regexprep(s,'[^\w\-]+','_');
    s = regexprep(s,'_+','_');
    s = strtrim(s);
    if numel(s) > 80, s = s(1:80); end
end

%% ---------------- MASK ----------------
function loadMaskCB(~,~)
    startPath = getStartPath();
    [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz','Mask files (*.mat,*.nii,*.nii.gz)'}, ...
        'Select mask', startPath);
    if isequal(f,0), return; end
    try
        passedMask = readMask(fullfile(p,f));
        mask2D = collapseMaskForSlice(passedMask,nY,nX,state.z,nZ);
        if ~passedMaskIsInclude, mask2D = ~mask2D; end
        updateView();
    catch ME
        errordlg(ME.message,'Mask load failed');
    end
end

function clearMaskCB(~,~)
    passedMask = [];
    mask2D = true(nY,nX);
    if ~passedMaskIsInclude, mask2D = ~mask2D; end %#ok<NASGU>
    updateView();
end

function startPath = getStartPath()
    startPath = pwd;
    try
        if isstruct(par)
            if isfield(par,'startPath') && ~isempty(par.startPath) && exist(par.startPath,'dir')
                startPath = par.startPath; return;
            end
            if isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath,'dir')
                startPath = par.loadedPath; return;
            end
            if isfield(par,'rawPath') && ~isempty(par.rawPath) && exist(par.rawPath,'dir')
                startPath = par.rawPath; return;
            end
        end
    catch
    end
end

%% ---------------- VIDEO GUI ----------------
function openVideo(~,~)
    try
        play_fusi_video_final( ...
            PSC, PSC, PSC, bg, ...
            par, 10, 240, ...
            TR, (nT-1)*TR, baseline, ...
            [], true, ...
            nT, false, struct(), ...
            fileLabel, state.z);
    catch ME
        errordlg(ME.message,'Video GUI failed');
    end
end

function showHelp(~,~)
    bgFig   = [0.06 0.06 0.07];
    bgText  = [0.12 0.12 0.14];
    colTxt  = [0.94 0.94 0.96];

    hf = figure('Name','SCM Help','Color',bgFig, ...
        'MenuBar','none','ToolBar','none','NumberTitle','off', ...
        'Resize','on','Position',[200 100 980 780],'WindowStyle','modal');

    guide = {
'SCM Viewer — Guide'
''
'OVERLAY'
'  • Threshold hides low |SCM|.'
'  • Display range sets overlay caxis.'
'  • Alpha modulation:'
'       - OFF: hard threshold alpha'
'       - ON : alpha ramps 0..1 between Mod Min and Mod Max'
''
'UNDERLAY'
'  • Brightness / Contrast / Gamma control background only.'
'  • Vessel enhance uses conectSize + conectLev.'
''
'ROI'
'  • Hover shows live ROI PSC.'
'  • Left click adds ROI; right click removes nearest ROI.'
'  • Unfreeze Hover re-enables hover after a click.'
'  • Export ROIs saves roi1.txt, roi2.txt, ... into AnalysedData/.../ROI/<type>/<datasetTag>/'
};

    uicontrol(hf,'Style','edit','Units','normalized', ...
        'Position',[0.03 0.03 0.94 0.94], ...
        'String',strjoin(guide,newline), ...
        'Max',2,'Min',0, ...
        'BackgroundColor',bgText,'ForegroundColor',colTxt, ...
        'FontName','Arial','FontSize',13,'HorizontalAlignment','left');
end

%% ---------------- POINTER HIT TEST ----------------
function tf = isPointerOverImageAxis()
    tf = false;
    try
        h = hittest(fig);
        if isempty(h), return; end
        axHit = ancestor(h,'axes');
        tf = ~isempty(axHit) && axHit == ax;
    catch
        try
            tf = isequal(gca,ax);
        catch
            tf = false;
        end
    end
end

%% ---------------- UNDERLAY PROCESSING ----------------
function U = processUnderlay(Uin)
    U = double(Uin); U(~isfinite(U)) = 0;

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

    g = uState.gamma; if ~isfinite(g) || g<=0, g=1; end
    U = U.^g;
    U = min(max(U,0),1);
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

%% ---------------- COLORMAP ----------------
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

    if strcmp(name,'blackbdy_iso')
        if exist('blackbdy_iso','file')
            cm = blackbdy_iso(n);
        else
            cm = hot(n);
        end
        return;
    end

    switch name
        case 'hot',     cm = hot(n); return;
        case 'parula',  cm = parula(n); return;
        case 'jet',     cm = jet(n); return;
        case 'gray',    cm = gray(n); return;
        case 'bone',    cm = bone(n); return;
        case 'copper',  cm = copper(n); return;
        case 'pink',    cm = pink(n); return;
    end

    if strcmp(name,'turbo')
        if exist('turbo','file'), cm = turbo(n);
        else, cm = jet(n);
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
            cm = interpAnchors(anchors,n); return;

        case 'plasma'
            anchors = [ ...
                0.050 0.030 0.528;
                0.280 0.040 0.650;
                0.500 0.060 0.650;
                0.700 0.170 0.550;
                0.850 0.350 0.420;
                0.940 0.550 0.260;
                0.990 0.750 0.140];
            cm = interpAnchors(anchors,n); return;

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
            cm = interpAnchors(anchors,n); return;

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
            cm = interpAnchors(anchors,n); return;
    end

    cm = hot(n);
end

function cm = interpAnchors(anchors, n)
    x = linspace(0,1,size(anchors,1));
    xi = linspace(0,1,n);
    cm = zeros(n,3);
    for k=1:3
        cm(:,k) = interp1(x, anchors(:,k), xi, 'linear');
    end
    cm = min(max(cm,0),1);
end

%% ---------------- TIME WINDOWS ----------------
function drawTimeWindows()
    [b0,b1]=parseRangeSafe(getStr(ebBase),baseline.start,baseline.end);
    [s0,s1]=parseRangeSafe(getStr(ebSig), baseline.end+10, baseline.end+40);

    if isVolMode
        b0s=(clamp(round(b0),1,nT)-1)*TR; b1s=(clamp(round(b1),1,nT)-1)*TR;
        s0s=(clamp(round(s0),1,nT)-1)*TR; s1s=(clamp(round(s1),1,nT)-1)*TR;
    else
        b0s=b0; b1s=b1; s0s=s0; s1s=s1;
    end
    if b1s<b0s, tmp=b0s; b0s=b1s; b1s=tmp; end
    if s1s<s0s, tmp=s0s; s0s=s1s; s1s=tmp; end

    yl=get(axTC,'YLim');
    if any(~isfinite(yl)) || yl(2)<=yl(1)
        yl=[-5 5]; set(axTC,'YLim',yl);
    end

    xb=[b0s b1s b1s b0s]/60; yb=[yl(1) yl(1) yl(2) yl(2)];
    set(hBasePatch,'XData',xb,'YData',yb,'FaceColor',[1.00 0.20 0.20],'Visible','on');

    xs=[s0s s1s s1s s0s]/60; ys=[yl(1) yl(1) yl(2) yl(2)];
    set(hSigPatch,'XData',xs,'YData',ys,'FaceColor',[1.00 0.55 0.15],'Visible','on');

    set(hBaseTxt,'Position',[mean(xb) yl(2)],'String','Bas.','Visible','on', ...
        'HorizontalAlignment','center','VerticalAlignment','top');
    set(hSigTxt,'Position',[mean(xs) yl(2)],'String','Sig.','Visible','on', ...
        'HorizontalAlignment','center','VerticalAlignment','top');

    uistack(hBasePatch,'bottom'); uistack(hSigPatch,'bottom');
end


function redrawROIsForCurrentSlice()
   deleteIfValid(roiHandles);     roiHandles = gobjects(0);
deleteIfValid(roiPlotPSC);     roiPlotPSC = gobjects(0);
deleteIfValid(roiTextHandles); roiTextHandles = gobjects(0);  % NEW

    ROI = ROI_byZ{state.z};
    if isempty(ROI), return; end

    for k=1:numel(ROI)
        r=ROI(k);
        roiHandles(end+1)=rectangle(ax,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor',r.color,'LineWidth',2); %#ok<AGROW>
% NEW: draw ROI id label near top-left of rectangle
xLab = r.x1;
yLab = max(1, r.y1 - 2);
roiTextHandles(end+1) = text(ax, xLab, yLab, sprintf('%d', r.id), ...
    'Color', r.color, ...
    'FontWeight','bold', ...
    'FontSize', 12, ...
    'Interpreter','none', ...
    'VerticalAlignment','bottom', ...
    'BackgroundColor',[0 0 0], ...
    'Margin', 1); %#ok<AGROW>
        tc = computeRoiPSC(r.x1,r.x2,r.y1,r.y2);
        if numel(tc)==nT
            roiPlotPSC(end+1)=plot(axTC,tmin,tc,':','Color',r.color,'LineWidth',2.4); %#ok<AGROW>
        end
    end
end

function deleteIfValid(h)
    if isempty(h), return; end
    for i=1:numel(h)
        if isgraphics(h(i)), delete(h(i)); end
    end
end

%% ---------------- DATA HELPERS ----------------
function PSCz = getPSCForSlice(z)
    if ndims(PSC)==3
        PSCz = PSC;
    else
        PSCz = squeeze(PSC(:,:,z,:));
    end
end

function bg2 = getBg2DForSlice(z)
    if ndims(bg)==2
        bg2 = bg; return;
    end
    if ndims(bg)==3
        if size(bg,3)==nT && nZ==1
            bg2 = mean(bg,3);
        else
            z = max(1,min(size(bg,3),z));
            bg2 = bg(:,:,z);
        end
        return;
    end
    if ndims(bg)==4
        tmp = mean(bg,4);
        z = max(1,min(size(tmp,3),z));
        bg2 = tmp(:,:,z);
        return;
    end
    bg2 = bg(:,:,1);
end

function [a,b] = parseRangeSafe(s, da, db)
    if nargin<2, da=0; end
    if nargin<3, db=da; end
    s = strrep(char(s),'–','-');
    v = sscanf(s,'%f-%f');
    if numel(v)~=2 || any(~isfinite(v))
        a=da; b=db;
    else
        a=v(1); b=v(2);
    end
end

function out = clamp(x, lo, hi)
    out = min(max(x,lo),hi);
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
                V = reshape(mean(double(bgIn), 3), [ny nx 1]);
            else
                V = reshape(double(bgIn(:,:,1)), [ny nx 1]);
            end

        elseif ndims(bgIn) == 4
            V = mean(double(bgIn), 4);

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
    if isempty(M0), M2=true(ny,nx); return; end
    M0 = logical(M0);

    if ndims(M0)==2
        M2 = M0;
    elseif ndims(M0)==3
        if nZ_>1 && size(M0,3)==nZ_
            z = max(1,min(size(M0,3),z));
            M2 = M0(:,:,z);
        else
            M2 = any(M0,3);
        end
    else
        tmp = M0;
        while ndims(tmp)>3
            tmp = any(tmp, ndims(tmp));
        end
        if ndims(tmp)==3 && nZ_>1 && size(tmp,3)==nZ_
            z = max(1,min(size(tmp,3),z));
            M2 = tmp(:,:,z);
        else
            while ndims(tmp)>2
                tmp = any(tmp, ndims(tmp));
            end
            M2 = tmp;
        end
    end

    M2 = M2(1:min(ny,size(M2,1)), 1:min(nx,size(M2,2)));
    if size(M2,1)<ny, M2(end+1:ny,:) = false; end
    if size(M2,2)<nx, M2(:,end+1:nx) = false; end
end

function M = readMask(f)
    if ~exist(f,'file'), error('Mask file not found: %s', f); end
    isNiiGz = (numel(f)>=7 && strcmpi(f(end-6:end),'.nii.gz'));

    if isNiiGz
        tmpDir = tempname; mkdir(tmpDir);
        gunzip(f,tmpDir);
        d = dir(fullfile(tmpDir,'*.nii'));
        if isempty(d), error('Failed to gunzip .nii.gz mask.'); end
        niiFile = fullfile(tmpDir,d(1).name);
        M = niftiread(niiFile);
        try, rmdir(tmpDir,'s'); catch, end
        M = logical(M);
        return;
    end

    [~,~,e] = fileparts(f);

    if strcmpi(e,'.mat')
        S = load(f);

        if isfield(S,'brainMask')
            M = S.brainMask;
        elseif isfield(S,'mask')
            M = S.mask;
        elseif isfield(S,'M')
            M = S.M;
        elseif isfield(S,'brainImage')
            M = (S.brainImage > 0);
        else
            fn = fieldnames(S);
            M = [];
            for k = 1:numel(fn)
                v = S.(fn{k});
                if islogical(v) || isnumeric(v)
                    M = v; break;
                end
            end
            if isempty(M)
                error('MAT mask file has no usable variable (brainMask/mask/brainImage).');
            end
        end

        M = logical(M);
        return;
    end

    M = niftiread(f);
    M = logical(M);
end

function rgb = toRGB(im01)
    im = double(im01); im(~isfinite(im))=0;
    im = min(max(im,0),1);
    idx = uint8(round(im*255));
    rgb = ind2rgb(idx, gray(256));
end

function out = smooth2D_gauss(in, sigma)
    try
        out = imgaussfilt(in, sigma);
        return;
    catch
    end
    if sigma<=0, out=in; return; end
    r = max(1, ceil(3*sigma));
    x = -r:r;
    g = exp(-(x.^2)/(2*sigma^2)); g = g/sum(g);
    out = conv2(conv2(in,g,'same'),g','same');
end

function U = mat2gray_safe(U)
    mn=min(U(:)); mx=max(U(:));
    if ~isfinite(mn) || ~isfinite(mx) || mx<=mn
        U(:)=0; return;
    end
    U=(U-mn)/(mx-mn);
    U=min(max(U,0),1);
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


function nextSetId = detectNextRoiSetId(roiDir)
    % Looks for existing files ROI<SET>_d<k>.txt and returns max(SET)+1
    nextSetId = 1;
    if exist(roiDir,'dir')~=7, return; end

    d = dir(fullfile(roiDir,'*.txt'));
    if isempty(d), return; end

    maxSet = 0;
    for i=1:numel(d)
        name = d(i).name;
        tok = regexp(name,'(?i)^ROI(\d+)_d(\d+)\.txt$','tokens','once');
        if isempty(tok), continue; end
        sId = str2double(tok{1});
        if isfinite(sId)
            maxSet = max(maxSet, sId);
        end
    end
    nextSetId = maxSet + 1;
end

function nextD = detectNextDIndexForSet(roiDir, setId)
    % For a given ROI<SET>, finds max d# already present and returns max+1
    nextD = 1;
    if exist(roiDir,'dir')~=7, return; end

    d = dir(fullfile(roiDir,'*.txt'));
    if isempty(d), return; end

    maxD = 0;
    for i=1:numel(d)
        name = d(i).name;
        tok = regexp(name, sprintf('(?i)^ROI%d_d(\\d+)\\.txt$', setId), 'tokens','once');
        if isempty(tok), continue; end
        di = str2double(tok{1});
        if isfinite(di)
            maxD = max(maxD, di);
        end
    end
    nextD = maxD + 1;
end
function q = prctile_fallback(v,p)
    try
        q = prctile(v,p); return;
    catch
    end
    v=sort(v(:)); n=numel(v);
    if n==0, q=0; return; end
    k=1+(n-1)*(p/100);
    k1=floor(k); k2=ceil(k);
    k1=max(1,min(n,k1)); k2=max(1,min(n,k2));
    if k1==k2
        q=v(k1);
    else
        q=v(k1)+(k-k1)*(v(k2)-v(k1));
    end
end

function s = getStr(h)
    try
        s = get(h,'String');
    catch
        s = '';
        return;
    end
    if iscell(s)
        if isempty(s), s=''; else, s=s{1}; end
    end
    if isstring(s)
        if numel(s)>1, s = s(1); end
        s = char(s);
    end
    if isnumeric(s)
        s = num2str(s);
    end
    s = char(s);
end

end