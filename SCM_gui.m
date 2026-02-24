function fig = SCM_gui(PSC, bg, TR, par, baseline, nVolsOrig, varargin)
% SCM_gui — Studio version (MATLAB 2017b + 2023b)
% ==========================================================
% FIXES IN THIS VERSION:
%  1) Window extended (width + height)
%  2) IMPORTANT labels are plain text (NO "<html>..." showing), no yellow
%  3) Value readouts for underlay brightness/contrast/gamma + vessel size/lev
%     are in boxed fields with WHITE font (consistent look)
%  4) Popup menus use white text + dark background (colormap, underlay view)
%  5) Vessel enhance made STRONGER (more visible); wider conectSize range
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
state.alphaPct = 100;
state.thresh   = 50;
state.cax      = [0 100];
state.sigma    = 0;
state.z        = max(1, round(nZ/2));

% ROI
roi.size = 12;
roi.colors = lines(12);
roi.isFrozen = false;

ROI_byZ = cell(1,nZ);
for zz=1:nZ
    ROI_byZ{zz} = struct('x1',{},'x2',{},'y1',{},'y2',{},'color',{});
end
roiHandles = gobjects(0);
roiPlotPSC = gobjects(0);

% Underlay view modes
% 1 Legacy, 2 Robust clip, 3 VideoGUI robust, 4 Vessel enhance
uState.mode       = 3;
uState.brightness = -0.04;   % -0.8..0.8
uState.contrast   = 1.10;    % 0.1..5
uState.gamma      = 0.95;    % 0.2..4

% Larger ranges (0..MAX). Negative size doesn't make physical sense, so we keep 0..MAX.
MAX_CONSIZE = 300;   % 0..300 px (large values can be slow!)
MAX_CONLEV  = 500;   % 0..500

uState.conectSize = 18;
uState.conectLev  = 35;

%% ---------------- FIGURE (BIGGER) ----------------
figW = 1820; figH = 1120;   % extended width + height
scr = get(0,'ScreenSize');
x0 = max(20, round((scr(3)-figW)/2));
y0 = max(40, round((scr(4)-figH)/2));

fig = figure( ...
    'Name','SCM Viewer', ...
    'Color',[0.05 0.05 0.05], ...
    'Position',[x0 y0 figW figH], ...
    'MenuBar','none','ToolBar','none','NumberTitle','off');

set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',14);

annotation(fig,'textbox',[0.62 0.004 0.37 0.03], ...
    'String','SCM GUI · Soner Caner Cagun · MPI Biological Cybernetics', ...
    'Color',[0.70 0.70 0.70], 'FontSize',10, ...
    'HorizontalAlignment','right','EdgeColor','none','Interpreter','none');

%% ---------------- MAIN IMAGE AXIS ----------------
ax = axes('Parent',fig,'Units','pixels','Position',[60 350 980 710]);
axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','reverse'); hold(ax,'on');

text(ax,0.5,1.04,fileLabel,'Units','normalized', ...
    'Color',[0.95 0.95 0.95],'FontSize',17,'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','bottom','Interpreter','none');

bg2 = getBg2DForSlice(state.z);
hBG = image(ax, toRGB(processUnderlay(bg2)));

hOV = imagesc(ax, zeros(nY,nX));
set(hOV,'AlphaData',0);

% colormap options (overlay only)
cmapNames = { ...
    'hot','parula','turbo','jet','gray','bone','copper','pink', ...
    'viridis','plasma','magma','inferno'};

setOverlayColormap('hot');
caxis(ax,state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.FontSize = 12;

hold(ax,'off');

%% ---------------- SLICE SLIDER ----------------
slZ = [];
txtZ = [];
if nZ > 1
    axPos = get(ax,'Position');
    slZ = uicontrol(fig,'Style','slider', ...
        'Units','pixels', ...
        'Position',[axPos(1)-32, axPos(2), 22, axPos(4)], ...
        'Min',1,'Max',nZ,'Value',state.z, ...
        'SliderStep',[1/max(1,nZ-1) 5/max(1,nZ-1)], ...
        'Callback',@sliceChanged);

    txtZ = uicontrol(fig,'Style','text', ...
        'Units','pixels', ...
        'Position',[axPos(1)-60, axPos(2)+axPos(4)+8, 300, 28], ...
        'String',sprintf('Slice: %d / %d',state.z,nZ), ...
        'ForegroundColor',[0.85 0.9 1], ...
        'BackgroundColor',get(fig,'Color'), ...
        'HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',13);
end

%% ---------------- TIMECOURSE AXIS ----------------
axTC = axes('Parent',fig,'Units','pixels','Position',[60 95 980 230], ...
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

hLivePSC = plot(axTC, tmin, nan(1,nT), ':', 'LineWidth', 3.2);
hLivePSC.Color = [1.00 0.60 0.10];
hLivePSC.Visible = 'off';

axes(ax); %#ok<LAXES>
hLiveRect = rectangle(ax,'Position',[1 1 1 1], ...
    'EdgeColor',[0 1 0],'LineWidth',2,'Visible','off');

%% ---------------- MASK INIT ----------------
mask2D = true(nY,nX);
if ~isempty(passedMask)
    mask2D = collapseMaskForSlice(passedMask,nY,nX,state.z,nZ);
end
if ~passedMaskIsInclude && ~isempty(passedMask)
    mask2D = ~mask2D;
end

%% ==========================================================
% RIGHT PANEL — bigger, no overlap
%% ==========================================================
panelX = 1100; panelY = 245; panelW = 680; panelH = 860;
panel = uipanel('Parent',fig,'Title','SCM Controls', ...
    'Units','pixels','Position',[panelX panelY panelW panelH], ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w','FontSize',16,'FontWeight','bold');

pad = 18;
gap = 9;
rowH = 34;
sliderH = 18;

xLabel  = pad;
wLabel  = 295;
xSlider = xLabel + wLabel + 10;
xVal    = panelW - pad - 130;
wVal    = 130;
wSlider = xVal - xSlider - 12;

y = panelH - 62;

mkLbl = @(s,yy) uicontrol(panel,'Style','text','String',s, ...
    'Units','pixels','Position',[xLabel yy wLabel rowH], ...
    'ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',13,'FontWeight','bold');

% IMPORTANT label (plain, no HTML, not yellow)
mkLblImp = @(s,yy) uicontrol(panel,'Style','text','String',s, ...
    'Units','pixels','Position',[xLabel yy wLabel rowH], ...
    'ForegroundColor',[1.00 0.55 0.55],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',13,'FontWeight','bold');

% Boxed value field (white text) — looks like "threshold" edits
mkValBox = @(s,yy) uicontrol(panel,'Style','edit','String',s, ...
    'Units','pixels','Position',[xVal yy wVal rowH], ...
    'BackgroundColor',[0.18 0.18 0.18],'ForegroundColor','w', ...
    'HorizontalAlignment','center','FontSize',13,'FontWeight','bold', ...
    'Enable','inactive');

mkEdit = @(s,yy,cbk) uicontrol(panel,'Style','edit','String',s, ...
    'Units','pixels','Position',[xVal yy wVal rowH], ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w','FontSize',13, ...
    'Callback',cbk);

mkSlider = @(minv,maxv,val,yy,cbk) uicontrol(panel,'Style','slider', ...
    'Units','pixels','Position',[xSlider yy+round((rowH-sliderH)/2) wSlider sliderH], ...
    'Min',minv,'Max',maxv,'Value',val,'Callback',cbk);

mkPopup = @(choices,yy,val,cbk) uicontrol(panel,'Style','popupmenu', ...
    'String',choices,'Value',val, ...
    'Units','pixels','Position',[xSlider yy (wSlider+wVal+12) rowH], ...
    'Callback',cbk, ...
    'BackgroundColor',[0.20 0.20 0.20], ...
    'ForegroundColor','w', ...        % make popup text white (may be OS-limited)
    'FontSize',13);

% ROI size
mkLbl('ROI size (px)', y);
slROI = mkSlider(1,220,roi.size,y,@(~,~)setROIsize());
txtROIsz = mkValBox(sprintf('%d',roi.size), y);
y = y - (rowH + gap);

% Baseline window (IMPORTANT)
mkLblImp('Baseline window (s)', y);
ebBase = mkEdit(sprintf('%g-%g',baseline.start,baseline.end), y, @onWindowEdited);
y = y - (rowH + gap);

% Signal window (IMPORTANT)
mkLblImp('Signal window (s)', y);
ebSig  = mkEdit(sprintf('%g-%g',baseline.end+10,baseline.end+40), y, @onWindowEdited);
y = y - (rowH + gap);

% Overlay alpha
mkLbl('Overlay alpha (%)', y);
slAlpha = mkSlider(0,100,100,y,@updateView);
txtAlpha = mkValBox('100', y);
y = y - (rowH + gap);

% Threshold (IMPORTANT)
mkLblImp('Threshold (abs %)', y);
ebThr = mkEdit('50', y, @updateView);
y = y - (rowH + gap);

% Color scale range (IMPORTANT)
mkLblImp('Color scale range (%)', y);
ebCax = mkEdit('0 100', y, @updateView);
y = y - (rowH + gap);

% Smoothing sigma (IMPORTANT)
mkLblImp('SCM smoothing sigma', y);
ebSigma = mkEdit('0', y, @computeSCM);
y = y - (rowH + gap);


% --- make key numeric edit fields red (typed text) ---
keyRed = [1.00 0.35 0.35];        % red-ish
keyBg  = [0.20 0.20 0.20];        % dark box (optional)

set(ebBase,  'ForegroundColor', keyRed, 'BackgroundColor', keyBg);
set(ebSig,   'ForegroundColor', keyRed, 'BackgroundColor', keyBg);
set(ebThr,   'ForegroundColor', keyRed, 'BackgroundColor', keyBg);
set(ebCax,   'ForegroundColor', keyRed, 'BackgroundColor', keyBg);
set(ebSigma, 'ForegroundColor', keyRed, 'BackgroundColor', keyBg);

% Colormap
mkLbl('Colormap', y);
popMap = mkPopup(cmapNames, y, 1, @updateView);
y = y - (rowH + gap);

% Underlay view
mkLbl('Underlay view', y);
popUnder = mkPopup({ ...
    '1) Legacy (mat2gray)', ...
    '2) Robust clip (1..99%)', ...
    '3) VideoGUI robust (0.5..99.5%)', ...
    '4) Vessel enhance (conectSize/Lev)'}, y, uState.mode, @underlayModeChanged);
y = y - (rowH + gap);

% Brightness (boxed value)
mkLbl('Underlay brightness', y);
slBri = mkSlider(-0.80,0.80,uState.brightness,y,@underlaySliderChanged);
txtBri = mkValBox(sprintf('%.2f',uState.brightness), y);
y = y - (rowH + gap);

% Contrast (boxed value)
mkLbl('Underlay contrast', y);
slCon = mkSlider(0.10,5.00,uState.contrast,y,@underlaySliderChanged);
txtCon = mkValBox(sprintf('%.2f',uState.contrast), y);
y = y - (rowH + gap);

% Gamma (boxed value)
mkLbl('Underlay gamma', y);
slGam = mkSlider(0.20,4.00,uState.gamma,y,@underlaySliderChanged);
txtGam = mkValBox(sprintf('%.2f',uState.gamma), y);
y = y - (rowH + gap);

% conectSize (boxed value)
mkLbl('Vessel conectSize (px)', y);
slVsz = mkSlider(0,MAX_CONSIZE,uState.conectSize,y,@underlaySliderChanged);
set(slVsz,'SliderStep',[1/max(1,MAX_CONSIZE) 10/max(1,MAX_CONSIZE)]);
txtVsz = mkValBox(sprintf('%d',uState.conectSize), y);
y = y - (rowH + gap);

% conectLev (boxed value)
mkLbl(sprintf('Vessel conectLev (0..%d)',MAX_CONLEV), y);
slVlv = mkSlider(0,MAX_CONLEV,uState.conectLev,y,@underlaySliderChanged);
set(slVlv,'SliderStep',[1/max(1,MAX_CONLEV) 10/max(1,MAX_CONLEV)]);
txtVlv = mkValBox(sprintf('%d',uState.conectLev), y);
y = y - (rowH + gap);

% Mask row (buttons inside)
mkLbl('Mask', y);
availW = (panelW - xSlider - pad);
btnGap = 12;
btnW = floor((availW - btnGap)/2);

btnMaskLoad = uicontrol(panel,'Style','pushbutton','String','Load mask', ...
    'Units','pixels','Position',[xSlider y btnW rowH], ...
    'Callback',@loadMaskCB,'FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w');

btnMaskClr  = uicontrol(panel,'Style','pushbutton','String','Clear mask', ...
    'Units','pixels','Position',[xSlider+btnW+btnGap y btnW rowH], ...
    'Callback',@clearMaskCB,'FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w');

y = y - (rowH + gap);

% Unfreeze hover (full width)
btnUnfreeze = uicontrol(panel,'Style','pushbutton','String','Unfreeze Hover', ...
    'Units','pixels','Position',[xLabel y panelW-2*pad rowH], ...
    'Callback',@unfreezeHover, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold');

% Use space below Unfreeze Hover for info lines
yInfo = y - (3*(rowH+7));

info1 = uicontrol(panel,'Style','text','String','', ...
    'Units','pixels','Position',[xLabel yInfo+2*(rowH+7) panelW-2*pad rowH], ...
    'ForegroundColor',[0.80 0.90 1.00],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12,'FontWeight','bold');

info2 = uicontrol(panel,'Style','text','String','', ...
    'Units','pixels','Position',[xLabel yInfo+1*(rowH+7) panelW-2*pad rowH], ...
    'ForegroundColor',[0.85 0.85 0.85],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12);

info3 = uicontrol(panel,'Style','text','String','', ...
    'Units','pixels','Position',[xLabel yInfo+0*(rowH+7) panelW-2*pad rowH], ...
    'ForegroundColor',[0.85 0.85 0.85],'BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12);

%% ---- Bottom buttons outside panel ----
mkBtn('Compute SCM',    panelX, 160, panelW, 56, @computeSCM,   [0.30 0.30 0.30], 15);
mkBtn('Open Video GUI', panelX,  98, panelW, 56, @openVideo,    [0.25 0.55 0.25], 15);
mkBtn('HELP',           panelX,  32, floor(panelW/2)-6, 56, @showHelp, [0.10 0.35 0.95], 15);
mkBtn('CLOSE',          panelX+floor(panelW/2)+6,  32, floor(panelW/2)-6, 56, @(~,~) close(fig), [0.75 0.15 0.15], 15);

%% ---------------- MOUSE CALLBACKS ----------------
set(fig,'WindowButtonMotionFcn',@mouseMove);
set(fig,'WindowButtonDownFcn',@mouseClick);
set(fig,'WindowScrollWheelFcn',@mouseScroll);

%% ---------------- INITIAL ----------------
updateInfoLines();
updateUnderlayControlsEnable();
computeSCM();
drawTimeWindows();
redrawROIsForCurrentSlice();
updateView();

%% ==========================================================
% CALLBACKS
%% ==========================================================
function onWindowEdited(~,~)
    drawTimeWindows();
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

    updateInfoLines();
    computeSCM();
    redrawROIsForCurrentSlice();
end

function unfreezeHover(~,~)
    roi.isFrozen = false;
    set(hLiveRect,'Visible','off');
    set(hLivePSC,'Visible','off');
end

function setROIsize()
    roi.size = max(1, round(get(slROI,'Value')));
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
        return;
    end

    hlf = floor(roi.size/2);
    x1=max(1,x-hlf); x2=min(nX,x+hlf);
    y1=max(1,ypix-hlf); y2=min(nY,ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}),size(roi.colors,1))+1,:);
    set(hLiveRect,'Position',[x1 y1 x2-x1+1 y2-y1+1],'EdgeColor',col,'Visible','on');

    tc = computeRoiPSC(x1,x2,y1,y2);
    if numel(tc)==nT
        set(hLivePSC,'YData',tc,'Visible','on');
    else
        set(hLivePSC,'Visible','off');
    end
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
        ROI_byZ{state.z}(end+1)=struct('x1',x1,'x2',x2,'y1',y1,'y2',y2,'color',col);
        redrawROIsForCurrentSlice();
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
    end
end

function computeSCM(~,~)
    [b0,b1]=parseRangeSafe(get(ebBase,'String'),baseline.start,baseline.end);
    [s0,s1]=parseRangeSafe(get(ebSig,'String'), baseline.end+10, baseline.end+40);

    sig = str2double(get(ebSigma,'String'));
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

    set(hOV,'CData',map);
    updateView();
    drawTimeWindows();
end

function updateView(~,~)
    a = get(slAlpha,'Value');
    set(txtAlpha,'String',sprintf('%.0f',a));

    thr = str2double(get(ebThr,'String')); if ~isfinite(thr), thr=0; end

    caxv = sscanf(char(get(ebCax,'String')),'%f');
    if numel(caxv)>=2 && isfinite(caxv(1)) && isfinite(caxv(2)) && caxv(2)>caxv(1)
        state.cax = caxv(1:2)';
    end

    maps = get(popMap,'String');
    idx  = get(popMap,'Value');
    if iscell(maps), cmapName = maps{idx}; else, cmapName = strtrim(maps(idx,:)); end
    setOverlayColormap(cmapName);

    ov = get(hOV,'CData');
    alpha = (a/100) .* (abs(ov) >= thr) .* double(mask2D);
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
    m = uState.mode;
    if m<1 || m>4, m=3; end

    note = '';
    if uState.conectSize > 150
        note = ' (NOTE: >150 can be slow)';
    end

    set(info1,'String',sprintf('TR = %.4gs | Slice %d/%d | Underlay mode: %s',TR,state.z,nZ,modeNames{m}));
    set(info2,'String',sprintf('Underlay: bri %.2f | con %.2f | gam %.2f',uState.brightness,uState.contrast,uState.gamma));
    set(info3,'String',sprintf('Vessel: conectSize %d px | conectLev %d%s',uState.conectSize,uState.conectLev,note));
end

function s = onoff(tf), if tf, s='on'; else, s='off'; end, end

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

    % brightness/contrast only affect underlay
    U = U*uState.contrast + uState.brightness;
    U = min(max(U,0),1);

    % gamma only affects underlay
    g = uState.gamma; if ~isfinite(g) || g<=0, g=1; end
    U = U.^g;
    U = min(max(U,0),1);
end

function U = vesselEnhanceStrong(U01, conectSizePx, conectLev_0_MAX)
    % Stronger than previous: uses local "vessel density" map and boosts it
    if conectSizePx <= 0
        U = U01; return;
    end

    % Map conectLev -> threshold in [0..1] (slightly compressed so it has effect earlier)
    lev01 = (conectLev_0_MAX / max(1,MAX_CONLEV));
    lev01 = lev01^0.75;                 % makes low-mid slider values more effective
    lev01 = min(max(lev01,0),1);

    thrMask = (U01 > lev01);

    r = max(1, round(conectSizePx));
    r = min(r, MAX_CONSIZE);
    h = diskKernel(r);

    % density map in [0..1]
    try
        D = filter2(h, double(thrMask), 'same');
    catch
        D = conv2(double(thrMask), h, 'same');
    end
    D = min(max(D,0),1);

    % Boost strength increases with size (but stays stable)
    strength = 0.8 + 1.6 * min(1, r/120);   % ~0.8..2.4
    D2 = D.^2;

    % Two-part enhancement: amplify vessels + add small additive ridge
    U = U01 .* (1 + strength*D2) + 0.15*D2;

    % keep within [0..1] before final robust clip
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
    name = lower(strtrim(name));

    % Built-ins (safe in 2017b)
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
        if exist('turbo','file')
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
    [b0,b1]=parseRangeSafe(get(ebBase,'String'),baseline.start,baseline.end);
    [s0,s1]=parseRangeSafe(get(ebSig,'String'), baseline.end+10, baseline.end+40);

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

%% ---------------- ROI PSC ----------------
function tc = computeRoiPSC(x1,x2,y1,y2)
    PSCz = getPSCForSlice(state.z);
    tc = squeeze(mean(mean(PSCz(y1:y2,x1:x2,:),1),2));
    tc = tc(:)';

    if numel(tc)~=nT, tc=[]; return; end

    if all(isfinite(tc))
        mn=min(tc); mx=max(tc);
        if mx>mn
            padY=0.15*(mx-mn);
            set(axTC,'YLim',[mn-padY mx+padY]);
        end
    end
end

function redrawROIsForCurrentSlice()
    deleteIfValid(roiHandles); roiHandles = gobjects(0);
    deleteIfValid(roiPlotPSC); roiPlotPSC = gobjects(0);

    ROI = ROI_byZ{state.z};
    if isempty(ROI), return; end

    for k=1:numel(ROI)
        r=ROI(k);
        roiHandles(end+1)=rectangle(ax,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor',r.color,'LineWidth',2); %#ok<AGROW>
        tc=computeRoiPSC(r.x1,r.x2,r.y1,r.y2);
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
    if ~passedMaskIsInclude, mask2D = ~mask2D; end
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
'IMPORTANT CONTROLS'
'  • Baseline window / Signal window define what gets averaged:'
'        SCM = mean(SignalWindow) - mean(BaselineWindow)'
'  • Threshold hides low |SCM| values (overlay only).'
'  • Color scale range sets overlay caxis.'
'  • SCM smoothing sigma blurs SCM map only (underlay unaffected).'
''
'UNDERLAY (BACKGROUND ONLY)'
'  • Brightness: additive shift after normalization.'
'  • Contrast: multiplicative scaling after normalization.'
'  • Gamma: power-law ( <1 boosts bright vessels; >1 darkens them ).'
''
'UNDERLAY VIEW MODES'
'  1) Legacy: min-max scaling (mat2gray style)'
'  2) Robust clip (1..99%): ignores extreme outliers'
'  3) VideoGUI robust (0.5..99.5%): closest to Video GUI look (recommended)'
'  4) Vessel enhance: stronger vessel emphasis using conectSize + conectLev'
''
'VESSEL ENHANCE'
'  • conectSize (px): disk radius; larger = stronger vessel emphasis.'
'  • conectLev (0..500): threshold on normalized underlay (higher = stricter).'
'  • Note: conectSize > 150 can be slow.'
''
'ROI'
'  • Hover shows live ROI PSC in timecourse.'
'  • Left click adds ROI; right click removes nearest ROI.'
'  • Unfreeze Hover re-enables live hover after a click.'
''
'OVERLAY'
'  • Overlay alpha affects SCM overlay only.'
'  • Colormap changes overlay only (underlay stays grayscale).'
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
    if size(M2,1)<ny, M2(end+1:ny,:) = true; end
    if size(M2,2)<nx, M2(:,end+1:nx) = true; end
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
        return;
    end

    [~,~,e]=fileparts(f);
    if strcmpi(e,'.mat')
        S = load(f); fn = fieldnames(S); M = S.(fn{1});
    else
        M = niftiread(f);
    end
end

function rgb = toRGB(im01)
    im = double(im01); im(~isfinite(im))=0;
    im = min(max(im,0),1);
    idx = uint8(round(im*255));
    rgb = ind2rgb(idx, gray(256));
end

function mkBtn(lbl,x,y,w,h,cb,bgcol,fs)
    uicontrol(fig,'Style','pushbutton','String',lbl,'Units','pixels', ...
        'Position',[x y w h],'Callback',cb, ...
        'BackgroundColor',bgcol,'ForegroundColor','w', ...
        'FontSize',fs,'FontWeight','bold');
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

end