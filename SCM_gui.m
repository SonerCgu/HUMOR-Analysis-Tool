function fig = SCM_gui(PSC, bg, TR, par, baseline, nVolsOrig, varargin)
% SCM_gui — 2D + TRUE 3D SLICE SUPPORT (MATLAB 2017b + 2023b)
% ==========================================================
% Supports:
%   - 2D probe:     PSC [Y X T]
%   - Matrix probe: PSC [Y X Z T]  -> slice slider (left of image)
%
% Preserved layout + fixes:
%   ? Strict original range parsing (prevents silent shifts vs old results)
%   ? Slice slider left of image when Z>1
%   ? ROIs stored per-slice
%   ? Mask load supports .mat, .nii, .nii.gz (nii.gz works in 2017b)
%   ? Right-click: unfreeze + remove nearest ROI
%   ? Works MATLAB 2017b and 2023b
%
% ROI behavior:
%   - Hover: live PSC shown (orange dotted)
%   - Left-click: add ROI + freezes hover
%   - Unfreeze: button OR right-click
%   - Right-click: unfreeze + remove nearest ROI

%% ---------------- SAFETY ----------------
assert(isscalar(TR) && isfinite(TR) && TR > 0, 'TR must be positive scalar');

pscDims = ndims(PSC);
assert(pscDims == 3 || pscDims == 4, 'PSC must be [Y X T] or [Y X Z T]');

if pscDims == 3
    [nY, nX, nT] = size(PSC);
    nZ = 1;
else
    [nY, nX, nZ, nT] = size(PSC);
end

tsec = (0:nT-1) * TR;
tmin = tsec / 60;

%% ---------------- BACKWARD COMPAT SHIM (arg#6) ----------------
% Some callers still pass I_raw as 6th argument instead of nVolsOrig.
if ~(isnumeric(nVolsOrig) && isscalar(nVolsOrig) && isfinite(nVolsOrig))
    varargin  = [{nVolsOrig} varargin];
    nVolsOrig = nT; %#ok<NASGU>
end

%% ---------------- OPTIONAL INPUTS ----------------
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

I_raw = []; I_interp = [];
initialFPS = 10; maxFPS = 120; %#ok<NASGU>
passedMask = [];
passedMaskIsInclude = true;  % optional
applyRejection = false; QC = struct(); %#ok<NASGU>

if numel(varargin) >= 1, I_raw        = varargin{1}; end %#ok<NASGU>
if numel(varargin) >= 2, I_interp     = varargin{2}; end
if numel(varargin) >= 3, initialFPS   = varargin{3}; end %#ok<NASGU>
if numel(varargin) >= 4, maxFPS       = varargin{4}; end %#ok<NASGU>
if numel(varargin) >= 5, passedMask   = varargin{5}; end

% If maskIsInclude is provided, it is usually position 6 (after passedMask)
if numel(varargin) >= 6
    v6 = varargin{6};

    isBoolScalar = (islogical(v6) && isscalar(v6)) || ...
                   (isnumeric(v6) && isscalar(v6) && (v6==0 || v6==1));

    if ~isempty(passedMask) && isBoolScalar
        % Only interpret v6 as maskIsInclude if a mask was actually passed
        passedMaskIsInclude = logical(v6);
        if numel(varargin) >= 7, applyRejection = varargin{7}; end %#ok<NASGU>
        if numel(varargin) >= 8, QC            = varargin{8}; end %#ok<NASGU>
    else
        % Otherwise v6 is applyRejection
        applyRejection = v6; %#ok<NASGU>
        if numel(varargin) >= 7, QC = varargin{7}; end %#ok<NASGU>
    end
end
%% ---------------- BASELINE MODE (SEC vs VOL) ----------------
modeStr = 'sec';
if isfield(baseline,'mode') && ~isempty(baseline.mode)
    try
        modeStr = lower(char(baseline.mode));
    catch
        modeStr = 'sec';
    end
end
isVolMode = (strncmpi(modeStr,'vol',3) || strncmpi(modeStr,'idx',3));

%% ---------------- STATE ----------------
state.alphaPct = 100;
state.thresh   = 50;
state.cax      = [0 100];
state.sigma    = 0;
state.cmap     = 'hot';

state.z = max(1, round(nZ/2));

%% ---------------- ROI STATE ----------------
roi.enable   = true;
roi.size     = 12;
roi.colors   = lines(12);
roi.isFrozen = false;

ROI_byZ = cell(1, nZ);
for zz = 1:nZ
    ROI_byZ{zz} = struct('x1',{},'x2',{},'y1',{},'y2',{},'color',{});
end

roiHandles = gobjects(0);
roiPlotPSC = gobjects(0);

%% ---------------- FIGURE ----------------
fig = figure( ...
    'Name', 'SCM Viewer', ...
    'Color',[0.05 0.05 0.05], ...
    'Position',[100 80 1280 800], ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off');

set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',12);

annotation(fig,'textbox', ...
    [0.62 0.005 0.37 0.03], ...
    'String','SCM GUI · Soner Caner Cagun · MPI Biological Cybernetics', ...
    'Color',[0.70 0.70 0.70], ...
    'FontSize',10, ...
    'HorizontalAlignment','right', ...
    'EdgeColor','none', ...
    'Interpreter','none');

%% ---------------- MAIN IMAGE AXIS ----------------
ax = axes('Parent',fig,'Units','pixels','Position',[60 210 780 560]);
if ~isempty(fileLabel)
    text(ax, 0.5, 1.04, fileLabel, ...
        'Units','normalized', ...
        'Color',[0.95 0.95 0.95], ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', ...
        'Interpreter','none');
end

axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','reverse'); hold(ax,'on');

bg2 = getBg2DForSlice(state.z);
hBG = image(ax, toRGB(bg2));

hOV = imagesc(ax, zeros(nY,nX));
set(hOV,'AlphaData',0);

colormap(ax, state.cmap);
caxis(ax, state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.FontSize = 12;
hold(ax,'off');

%% ---------------- SLICE SLIDER (LEFT OF IMAGE) ----------------
slZ = [];
txtZ = [];

if nZ > 1
    axPos = get(ax,'Position');

    slZ = uicontrol(fig,'Style','slider', ...
        'Units','pixels', ...
        'Position',[axPos(1)-26, axPos(2), 18, axPos(4)], ...
        'Min',1,'Max',nZ,'Value',state.z, ...
        'SliderStep',[1/max(1,nZ-1) 5/max(1,nZ-1)], ...
        'Callback',@sliceChanged);

    txtZ = uicontrol(fig,'Style','text', ...
        'Units','pixels', ...
        'Position',[axPos(1)-40, axPos(2)+axPos(4)+6, 120, 20], ...
        'String',sprintf('Slice: %d / %d',state.z,nZ), ...
        'ForegroundColor',[0.85 0.9 1], ...
        'BackgroundColor',get(fig,'Color'), ...
        'HorizontalAlignment','left', ...
        'FontWeight','bold');
end

%% ---------------- TIMECOURSE AXIS ----------------
axTC = axes('Parent',fig,'Units','pixels','Position',[60 35 780 150], ...
    'Color',[0.05 0.05 0.05],'XColor','w','YColor','w');
hold(axTC,'on'); grid(axTC,'on');
axTC.FontSize = 12;

xlabel(axTC,'Time (min)','Color','w','FontSize',13,'FontWeight','bold');
ylabel(axTC,'PSC (%)','Color','w','FontSize',13,'FontWeight','bold');

hBasePatch = patch(axTC,[0 0 0 0],[0 0 0 0],[1 1 1], ...
    'FaceAlpha',0.10,'EdgeColor','none','Visible','off');
hSigPatch  = patch(axTC,[0 0 0 0],[0 0 0 0],[1 1 1], ...
    'FaceAlpha',0.10,'EdgeColor','none','Visible','off');

hBaseTxt = text(axTC,0,0,'','Color',[0.75 0.90 1.00], ...
    'FontSize',11,'FontWeight','bold','Visible','off');
hSigTxt  = text(axTC,0,0,'','Color',[1.00 0.85 0.60], ...
    'FontSize',11,'FontWeight','bold','Visible','off');

hLivePSC = plot(axTC, tmin, nan(1,nT), ':', 'LineWidth', 3.0);
hLivePSC.Color = [1.00 0.60 0.10];
hLivePSC.Visible = 'off';

%% ---------------- LIVE ROI RECTANGLE ----------------
axes(ax); %#ok<LAXES>
hLiveRect = rectangle(ax,'Position',[1 1 1 1], ...
    'EdgeColor',[0 1 0],'LineWidth',2,'Visible','off');

%% ---------------- CONTROL PANEL (ORIGINAL LAYOUT) ----------------
panel = uipanel('Parent',fig,'Title','SCM Controls', ...
    'Units','pixels','Position',[875 105 370 665], ...
    'BackgroundColor',[0.10 0.10 0.10],'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold');

pad = 18; lineH = 24; editH = 32; sliderH = 18;
gap = 14; gapBig = 18;

xL = pad; xR = 240; wEdit = 110; wWide = 370-2*pad;
y = 612;

mkTxt  = @(s,yy) uicontrol(panel,'Style','text','String',s, ...
    'Units','pixels','Position',[xL yy wWide lineH], ...
    'ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10], ...
    'HorizontalAlignment','left','FontSize',12,'FontWeight','bold');

mkEdit = @(v,yy) uicontrol(panel,'Style','edit','String',v, ...
    'Units','pixels','Position',[xR yy wEdit editH], ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w','FontSize',12);

mkSlider = @(yy,minv,maxv,val,cbk) uicontrol(panel,'Style','slider', ...
    'Units','pixels','Position',[xL yy wWide sliderH], ...
    'Min',minv,'Max',maxv,'Value',val,'Callback',cbk);

%% ---- ROI CONTROLS ----
cbROI = uicontrol(panel,'Style','checkbox','String','Enable ROI (hover + click)', ...
    'Units','pixels','Position',[xL y wWide editH], ...
    'Value',roi.enable,'ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10], ...
    'FontSize',12,'FontWeight','bold','Callback',@toggleROI);
y = y - (editH + 8);

btnUnfreeze = uicontrol(panel,'Style','pushbutton','String','Unfreeze Hover', ...
    'Units','pixels','Position',[xL y wWide editH], ...
    'Callback',@unfreezeHover, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold');
y = y - (editH + gap);

mkTxt('ROI size (px)', y);
slROI = mkSlider(y-22,1,200,roi.size,@(~,~)setROIsize());
txtROIsz = uicontrol(panel,'Style','text','String',sprintf('%d px',roi.size), ...
    'Units','pixels','Position',[xR y-56 wEdit editH], ...
    'BackgroundColor',[0.10 0.10 0.10],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
y = y - (52 + gapBig);

%% ---- WINDOWS ----
mkTxt('Baseline window (s)', y);
ebBase = mkEdit(sprintf('%g-%g',baseline.start,baseline.end),y-8);
y = y - (editH + gap);

mkTxt('Signal window (s)', y);
ebSig  = mkEdit(sprintf('%g-%g',baseline.end+10,baseline.end+40),y-8);
y = y - (editH + gap/2);

%% ---- DISPLAY ----
mkTxt('Overlay alpha (%)', y);
slAlpha = mkSlider(y-22,0,100,state.alphaPct,@updateView);
txtAlpha = uicontrol(panel,'Style','text','String',sprintf('%.0f',state.alphaPct), ...
    'Units','pixels','Position',[xR y-56 wEdit editH], ...
    'BackgroundColor',[0.10 0.10 0.10],'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
y = y - (52 + gapBig);

mkTxt('Threshold (abs %)', y);
ebThr = mkEdit(num2str(state.thresh),y-8);
y = y - (editH + gap);

mkTxt('Color scale range (%)', y);
ebCax = mkEdit(sprintf('%g %g',state.cax),y-8);
y = y - (editH + gap);

mkTxt('SCM smoothing sigma', y);
ebSigma = mkEdit(num2str(state.sigma),y-8);
y = y - (editH + gapBig);

mkTxt('Colormap', y);
popMap = uicontrol(panel,'Style','popupmenu', ...
    'String',{'hot','parula','jet','gray'}, ...
    'Units','pixels','Position',[xL y-30 wWide editH], ...
    'Callback',@updateView,'FontSize',12, ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w');
y = y - (editH + gapBig);

%% ---- MASK ----
mkTxt('Mask', y);
uicontrol(panel,'Style','pushbutton','String','Load mask', ...
    'Units','pixels','Position',[xL y-34 wWide*0.48 editH], ...
    'Callback',@loadMaskCB,'FontSize',12,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w');
uicontrol(panel,'Style','pushbutton','String','Clear mask', ...
    'Units','pixels','Position',[xL+wWide*0.52 y-34 wWide*0.48 editH], ...
    'Callback',@clearMaskCB,'FontSize',12,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.20 0.20],'ForegroundColor','w');

%% ---- BOTTOM BUTTONS (on figure) ----
mkBtn('Compute SCM',    875, 130, 370, 42, @computeSCM,   [0.30 0.30 0.30], 13);
mkBtn('Open Video GUI', 875,  82, 370, 42, @openVideo,    [0.25 0.55 0.25], 13);
mkBtn('HELP',           875,  32, 180, 40, @showHelp,     [0.10 0.35 0.95], 13);
mkBtn('CLOSE',         1065,  32, 180, 40, @(~,~)close(fig),[0.75 0.15 0.15],13);

%% ---------------- MOUSE CALLBACKS ----------------
set(fig,'WindowButtonMotionFcn',@mouseMove);
set(fig,'WindowButtonDownFcn',@mouseClick);
set(fig,'WindowScrollWheelFcn',@mouseScroll);

%% ---------------- MASK INIT (PER SLICE) ----------------
mask2D = true(nY,nX);
if ~isempty(passedMask)
    mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
end
if ~passedMaskIsInclude && ~isempty(passedMask)
    mask2D = ~mask2D;
end

%% ---------------- INITIAL COMPUTE ----------------
computeSCM();
drawTimeWindows();
redrawROIsForCurrentSlice();

%% ============================================================
% CALLBACKS
%% ============================================================

function sliceChanged(varargin) %#ok<INUSD>
    if isempty(slZ) || ~isgraphics(slZ), return; end
    zNew = round(get(slZ,'Value'));
    zNew = max(1, min(nZ, zNew));
    if zNew == state.z, return; end

    state.z = zNew;
    set(slZ,'Value',state.z);
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ,'String',sprintf('Slice: %d / %d',state.z,nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
    else
        mask2D = true(nY,nX);
    end
 if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG,'CData',toRGB(bg2));

    set(hLiveRect,'Visible','off');
    set(hLivePSC,'Visible','off');
    roi.isFrozen = false;

    computeSCM();
    redrawROIsForCurrentSlice();
end

function toggleROI(varargin)
    roi.enable = logical(get(cbROI,'Value'));
    roi.isFrozen = false;
    if ~roi.enable
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
    end
end

function unfreezeHover(varargin)
    roi.isFrozen = false;
end

function setROIsize()
    roi.size = max(1, round(get(slROI,'Value')));
    set(txtROIsz,'String',sprintf('%d px',roi.size));
end

function mouseMove(varargin)
    if ~roi.enable || roi.isFrozen
        return;
    end
    if ~isPointerOverImageAxis()
        return;
    end

    cp = get(ax,'CurrentPoint');
    x = round(cp(1,1));
    ypix = round(cp(1,2));

    if x < 1 || x > nX || ypix < 1 || ypix > nY
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
        return;
    end

    hlf = floor(roi.size/2);
    x1  = max(1, x-hlf);     x2 = min(nX, x+hlf);
    y1  = max(1, ypix-hlf);  y2 = min(nY, ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1)) + 1, :);

    set(hLiveRect,'Position',[x1 y1 x2-x1+1 y2-y1+1], ...
        'EdgeColor',col,'Visible','on');

    tc_psc = computeRoiPSC(x1,x2,y1,y2);
    if numel(tc_psc) == nT
        set(hLivePSC,'YData',tc_psc,'Visible','on');
    else
        set(hLivePSC,'Visible','off');
    end

    drawTimeWindows();
end

function mouseScroll(~, evt)
    if nZ <= 1, return; end
    if ~isPointerOverImageAxis(), return; end

    dz = -sign(evt.VerticalScrollCount);
    if dz == 0, return; end

    zNew = max(1, min(nZ, state.z + dz));
    if zNew == state.z, return; end

    state.z = zNew;

    if ~isempty(slZ) && isgraphics(slZ)
        set(slZ,'Value',state.z);
    end
    if ~isempty(txtZ) && isgraphics(txtZ)
        set(txtZ,'String',sprintf('Slice: %d / %d', state.z, nZ));
    end

    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
    else
        mask2D = true(nY,nX);
    end
    if ~passedMaskIsInclude && ~isempty(passedMask)
        mask2D = ~mask2D;
    end

    bg2 = getBg2DForSlice(state.z);
    set(hBG,'CData',toRGB(bg2));

    computeSCM();
    redrawROIsForCurrentSlice();
end

function mouseClick(varargin)
    if ~roi.enable, return; end
    if ~isPointerOverImageAxis(), return; end

    cp = get(ax,'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));
    if x < 1 || x > nX || ypix < 1 || ypix > nY
        return;
    end

    hlf = floor(roi.size/2);
    x1  = max(1, x-hlf);     x2 = min(nX, x+hlf);
    y1  = max(1, ypix-hlf);  y2 = min(nY, ypix+hlf);

    type = get(fig,'SelectionType');

    if strcmp(type,'normal')
        roi.isFrozen = true;

        tc_psc = computeRoiPSC(x1,x2,y1,y2);
        if numel(tc_psc) ~= nT, return; end

        col = roi.colors(mod(numel(ROI_byZ{state.z}), size(roi.colors,1)) + 1, :);
        ROI_byZ{state.z}(end+1) = struct('x1',x1,'x2',x2,'y1',y1,'y2',y2,'color',col);

        redrawROIsForCurrentSlice();
        drawTimeWindows();

    elseif strcmp(type,'alt')
        % RIGHT-CLICK: unfreeze + remove nearest ROI
        roi.isFrozen = false;

        if ~isempty(ROI_byZ{state.z})
            ROI = ROI_byZ{state.z};
            ctr = arrayfun(@(r)[(r.x1+r.x2)/2, (r.y1+r.y2)/2], ROI, 'uni', 0);
            ctr = cat(1, ctr{:});
            [~,i] = min(sum((ctr - [x ypix]).^2, 2));
            if i >= 1 && i <= numel(ROI)
                ROI(i) = [];
                ROI_byZ{state.z} = ROI;
                redrawROIsForCurrentSlice();
            end
        end

        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
    end
end

%% ---------------- SCM COMPUTATION ----------------
function computeSCM(varargin) %#ok<INUSD>
    [b0,b1] = parseRangeSafe(get(ebBase,'String'), baseline.start, baseline.end);
    [s0,s1] = parseRangeSafe(get(ebSig,'String'),  baseline.end+10, baseline.end+40);

    sig = str2double(get(ebSigma,'String'));
    if ~isfinite(sig), sig = state.sigma; end
    state.sigma = sig;

    % ---- convert to indices (ORIGINAL behavior for sec mode) ----
    if ~isVolMode
        b0i = clamp(round(b0/TR)+1,1,nT);
        b1i = clamp(round(b1/TR)+1,1,nT);
        s0i = clamp(round(s0/TR)+1,1,nT);
        s1i = clamp(round(s1/TR)+1,1,nT);
    else
        % baseline/signal given as volume indices (1-based)
        b0i = clamp(round(b0),1,nT);
        b1i = clamp(round(b1),1,nT);
        s0i = clamp(round(s0),1,nT);
        s1i = clamp(round(s1),1,nT);
    end

    if b1i < b0i, tmp=b0i; b0i=b1i; b1i=tmp; end
    if s1i < s0i, tmp=s0i; s0i=s1i; s1i=tmp; end

    PSCz = getPSCForSlice(state.z); % [Y X T]

    baseMap = mean(PSCz(:,:,b0i:b1i),3);
    sigMap  = mean(PSCz(:,:,s0i:s1i),3);
    map     = sigMap - baseMap;

    if sig > 0
        map = smooth2D_gauss(map, sig);
    end

    set(hOV,'CData',map);
    updateView();
    drawTimeWindows();
end

function updateView(varargin) %#ok<INUSD>
    state.alphaPct = get(slAlpha,'Value');
    set(txtAlpha,'String',sprintf('%.0f',state.alphaPct));

    thr = str2double(get(ebThr,'String'));
    if ~isfinite(thr), thr = 0; end
    state.thresh = thr;

    cax = parse2(get(ebCax,'String'), state.cax);
    if numel(cax)==2 && isfinite(cax(1)) && isfinite(cax(2)) && cax(2) > cax(1)
        state.cax = cax(:)';
    end

    maps = get(popMap,'String');
    idx  = get(popMap,'Value');
    if iscell(maps)
        state.cmap = maps{idx};
    else
        state.cmap = strtrim(maps(idx,:));
    end

    ov = get(hOV,'CData');
    alpha = (state.alphaPct/100) .* (abs(ov) >= state.thresh) .* double(mask2D);
    set(hOV,'AlphaData',alpha);

    colormap(ax, state.cmap);
    caxis(ax, state.cax);
end

%% ---------------- TIME WINDOW OVERLAYS ----------------
function drawTimeWindows()
    [b0,b1] = parseRangeSafe(get(ebBase,'String'), baseline.start, baseline.end);
    [s0,s1] = parseRangeSafe(get(ebSig,'String'),  baseline.end+10, baseline.end+40);

    % Convert to seconds for patch positions (x-axis is minutes)
    if isVolMode
        b0s = (clamp(round(b0),1,nT) - 1) * TR;
        b1s = (clamp(round(b1),1,nT) - 1) * TR;
        s0s = (clamp(round(s0),1,nT) - 1) * TR;
        s1s = (clamp(round(s1),1,nT) - 1) * TR;
    else
        b0s = b0; b1s = b1; s0s = s0; s1s = s1;
    end

    if b1s < b0s, tmp=b0s; b0s=b1s; b1s=tmp; end
    if s1s < s0s, tmp=s0s; s0s=s1s; s1s=tmp; end

    yl = get(axTC,'YLim');
    if any(~isfinite(yl)) || yl(2) <= yl(1)
        yl = [-5 5];
        set(axTC,'YLim',yl);
    end

    xb = [b0s b1s b1s b0s] / 60;
    yb = [yl(1) yl(1) yl(2) yl(2)];
    set(hBasePatch,'XData',xb,'YData',yb,'FaceColor',[0.6 0.8 1.0],'Visible','on');

    xs = [s0s s1s s1s s0s] / 60;
    ys = [yl(1) yl(1) yl(2) yl(2)];
    set(hSigPatch,'XData',xs,'YData',ys,'FaceColor',[1.0 0.7 0.4],'Visible','on');

    set(hBaseTxt,'Position',[mean(xb) yl(2)],'String','Bas.', ...
        'HorizontalAlignment','center','VerticalAlignment','top','Visible','on');
    set(hSigTxt,'Position',[mean(xs) yl(2)],'String','Sig.', ...
        'HorizontalAlignment','center','VerticalAlignment','top','Visible','on');

    uistack(hBasePatch,'bottom');
    uistack(hSigPatch,'bottom');
end

%% ---------------- ROI PSC ----------------
function tc_psc = computeRoiPSC(x1,x2,y1,y2)
    PSCz = getPSCForSlice(state.z);
    tc = squeeze(mean(mean(PSCz(y1:y2, x1:x2, :), 1), 2));
    if isempty(tc)
        tc_psc = [];
        return;
    end
    tc = tc(:)'; % row
    if numel(tc) ~= nT
        tc_psc = [];
        return;
    end
    tc_psc = tc;

    if all(isfinite(tc_psc))
        mn = min(tc_psc);
        mx = max(tc_psc);
        if mx > mn
            padY = 0.15 * (mx - mn);
            set(axTC,'YLim',[mn-padY mx+padY]);
        end
    end
end

function redrawROIsForCurrentSlice()
    deleteIfValid(roiHandles); roiHandles = gobjects(0);
    deleteIfValid(roiPlotPSC); roiPlotPSC = gobjects(0);

    ROI = ROI_byZ{state.z};
    if isempty(ROI), return; end

    for k = 1:numel(ROI)
        r = ROI(k);
        roiHandles(end+1) = rectangle(ax,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor',r.color,'LineWidth',2); %#ok<AGROW>

        tc = computeRoiPSC(r.x1,r.x2,r.y1,r.y2);
        if numel(tc) == nT
            roiPlotPSC(end+1) = plot(axTC, tmin, tc, ':', 'Color', r.color, 'LineWidth', 2.2); %#ok<AGROW>
        end
    end
end

function deleteIfValid(h)
    if isempty(h), return; end
    for i = 1:numel(h)
        if isgraphics(h(i)), delete(h(i)); end
    end
end

%% ---------------- MASK ----------------
function loadMaskCB(varargin) %#ok<INUSD>
    [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz','Mask files (*.mat,*.nii,*.nii.gz)'});
    if isequal(f,0), return; end
    try
        passedMask = readMask(fullfile(p,f));
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);
        if ~passedMaskIsInclude, mask2D = ~mask2D; end
        updateView();
    catch ME
        warning('Mask load failed: %s', ME.message);
    end
end

function clearMaskCB(varargin) %#ok<INUSD>
    passedMask = [];
    mask2D = true(nY,nX);
    if ~passedMaskIsInclude, mask2D = ~mask2D; end
    updateView();
end

%% ---------------- VIDEO GUI ----------------
function openVideo(varargin) %#ok<INUSD>
    initialFPS = 10;
    maxFPS     = 240;

    if exist('I_raw','var') && ~isempty(I_raw)
        Iraw = I_raw;
    else
        Iraw = PSC;
    end
    if exist('I_interp','var') && ~isempty(I_interp)
        Iinterp = I_interp;
    else
        Iinterp = Iraw;
    end

    loadedMask = [];
    if ~isempty(passedMask)
        M = logical(passedMask);
        while ndims(M) > 2
            M = any(M, ndims(M));
        end
        fixedMask = false(nY, nX);
        yMax = min(nY, size(M,1));
        xMax = min(nX, size(M,2));
        fixedMask(1:yMax, 1:xMax) = M(1:yMax, 1:xMax);
        loadedMask = fixedMask;
    end

    play_fusi_video_final( ...
        Iraw, Iinterp, PSC, bg, ...
        par, initialFPS, maxFPS, ...
        TR, (nT-1)*TR, baseline, ...
        loadedMask, passedMaskIsInclude, ...
        nT, false, struct(), ...
        fileLabel, state.z );
end

function showHelp(varargin)
% Dark themed, modern HELP window (MATLAB 2017b + 2023b)
% - Dark background, white text
% - Big bold title, section headers
% - Scrollable content (slider + mouse wheel)
% - Modal (blocks interaction until closed)

% ---------------- Window ----------------
W = 920; H = 740;
scr = get(0,'ScreenSize');  % [left bottom width height]
x0 = max(20, round((scr(3)-W)/2));
y0 = max(20, round((scr(4)-H)/2));

bgFig   = [0.06 0.06 0.07];
bgPanel = [0.10 0.10 0.12];
bgText  = [0.12 0.12 0.14];
colTxt  = [0.94 0.94 0.96];
colSub  = [0.76 0.86 1.00];

hf = figure( ...
    'Name','SCM Help', ...
    'Color',bgFig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Resize','on', ...
    'Position',[x0 y0 W H], ...
    'WindowStyle','modal');

% ---------------- Title ----------------
titleAx = uicontrol('Style','text','Parent',hf, ...
    'Units','pixels', ...
    'Position',[20 H-62 W-40 44], ...
    'String','SCM Viewer — Help', ...
    'ForegroundColor',colTxt, ...
    'BackgroundColor',bgFig, ...
    'FontName','Arial', ...
    'FontSize',22, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

subAx = uicontrol('Style','text','Parent',hf, ...
    'Units','pixels', ...
    'Position',[22 H-86 W-44 20], ...
    'String','Dark UI • 2D + Matrix probe (Z-slices) • ROI hover/click • Mask-aware overlay', ...
    'ForegroundColor',[0.75 0.75 0.78], ...
    'BackgroundColor',bgFig, ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','normal', ...
    'HorizontalAlignment','left');

% ---------------- Main panel ----------------
p = uipanel('Parent',hf, ...
    'Units','pixels', ...
    'Position',[20 80 W-40 H-120], ...
    'BackgroundColor',bgPanel, ...
    'BorderType','line', ...
    'HighlightColor',[0.18 0.18 0.20]);

% Text content (use a listbox for reliable colors + scrolling in 2017b)
lines = {
' '
'SCM MAP (what you are seeing)'
'  • SCM is computed as: mean(SIGNAL window) - mean(BASELINE window).'
'  • The overlay is masked by:  (|SCM| > Threshold) AND (Mask, if loaded).'
' '
'NAVIGATION (Matrix probe / Z-slices)'
'  • Slice slider (left of image): change slice.'
'  • Mouse wheel over image: change slice.'
'  • ROIs are stored per slice — switching slices keeps your ROIs.'
' '
'ROI TOOL (Hover + Click)'
'  • Enable ROI must be ON.'
'  • Hover: live ROI box + live PSC curve (orange dotted).'
'  • Left-click: add a persistent ROI (rectangle + dotted PSC curve).'
'  • Right-click: remove the nearest ROI.'
'  • Tip: if you use “freeze hover” mode, right-click can also unfreeze.'
' '
'DISPLAY CONTROLS'
'  • Overlay alpha (%): transparency of SCM overlay.'
'  • Threshold (abs %): show only pixels with |SCM| ? threshold.'
'  • Color scale range: sets the colorbar/caxis limits for the overlay.'
'  • SCM smoothing sigma: Gaussian smoothing of SCM map (0 = off).'
'  • Colormap: changes the overlay palette.'
' '
'TIMECOURSE'
'  • X-axis is time in minutes.'
'  • Hover PSC (orange) + persistent ROIs (colored) are plotted as dotted lines.'
'  • Baseline and Signal windows are shaded on the timecourse.'
' '
'MASK'
'  • Load mask: supports .mat, .nii, .nii.gz.'
'  • Clear mask: removes masking (overlay visible everywhere again).'
' '
'SHORTCUTS / MOUSE'
'  • Mouse wheel over image: change slice (if Z > 1).'
'  • Left-click: add ROI.'
'  • Right-click: remove nearest ROI (or unfreeze if you implement it that way).'
' '
'NOTES'
'  • If the overlay looks empty: lower Threshold, increase alpha, or widen caxis.'
'  • If you load a mask and see nothing: verify mask matches data orientation/size.'
' '
};

% Make section headers stand out by inserting a marker. We’ll color the whole list,
% and add a small legend box to indicate headers.
lb = uicontrol('Style','listbox','Parent',p, ...
    'Units','pixels', ...
    'Position',[14 14 (W-40)-60 (H-120)-28], ...
    'String',lines, ...
    'Value',1, ...
    'BackgroundColor',bgText, ...
    'ForegroundColor',colTxt, ...
    'FontName','Consolas', ...
    'FontSize',12, ...
    'Max',2,'Min',0);

% Slider (mirrors listbox scroll)
sl = uicontrol('Style','slider','Parent',p, ...
    'Units','pixels', ...
    'Position',[(W-40)-38 14 18 (H-120)-28], ...
    'Min',1,'Max',max(2,numel(lines)), ...
    'Value',1, ...
    'SliderStep',[1/max(1,numel(lines)-1) 10/max(1,numel(lines)-1)], ...
    'Callback',@onScroll);

% Legend hint (subtle)
uicontrol('Style','text','Parent',hf, ...
    'Units','pixels', ...
    'Position',[24 52 W-200 18], ...
    'String','Scroll with mouse wheel or slider • Close to return to SCM', ...
    'ForegroundColor',[0.72 0.72 0.74], ...
    'BackgroundColor',bgFig, ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'HorizontalAlignment','left');

% Close button
btn = uicontrol('Style','pushbutton','Parent',hf, ...
    'Units','pixels', ...
    'Position',[W-160 30 130 38], ...
    'String','Close', ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'ForegroundColor','w', ...
    'BackgroundColor',[0.75 0.15 0.15], ...
    'Callback',@(~,~) close(hf));

% Mouse wheel scroll
set(hf,'WindowScrollWheelFcn',@onWheel);

% Keep layout responsive
set(hf,'SizeChangedFcn',@onResize);
onResize();

% ---------------- Nested callbacks ----------------
    function onResize(~,~)
        pos = get(hf,'Position');
        Wc = pos(3); Hc = pos(4);

        set(titleAx,'Position',[20 Hc-62 Wc-40 44]);
        set(subAx,  'Position',[22 Hc-86 Wc-44 20]);

        set(p,'Position',[20 80 Wc-40 Hc-120]);

        set(lb,'Position',[14 14 (Wc-40)-60 (Hc-120)-28]);
        set(sl,'Position',[(Wc-40)-38 14 18 (Hc-120)-28]);

        set(btn,'Position',[Wc-160 30 130 38]);
    end

    function onScroll(~,~)
        v = round(get(sl,'Value'));
        v = max(1, min(numel(lines), v));
        set(sl,'Value',v);

        % listbox shows a window of items; set Value to bring v into view
        set(lb,'Value',v);
    end

    function onWheel(~,evt)
        % Scroll: positive -> down; negative -> up (match typical feel)
        v = round(get(sl,'Value'));
        v = v + evt.VerticalScrollCount;
        v = max(1, min(numel(lines), v));
        set(sl,'Value',v);
        set(lb,'Value',v);
    end

end

%% ---------------- POINTER HIT TEST ----------------
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

%% ---------------- HELPERS ----------------
function PSCz = getPSCForSlice(z)
    if ndims(PSC) == 3
        PSCz = PSC;
    else
        PSCz = squeeze(PSC(:,:,z,:));  % [Y X T]
    end
end

function bg2 = getBg2DForSlice(z)
    if ndims(bg) == 2
        bg2 = bg; return;
    end
    if ndims(bg) == 3
        if size(bg,3) == nT && nZ == 1
            bg2 = mean(bg,3);
        else
            z = max(1, min(size(bg,3), z));
            bg2 = bg(:,:,z);
        end
        return;
    end
    if ndims(bg) == 4
        tmp = mean(bg,4);
        z = max(1, min(size(tmp,3), z));
        bg2 = tmp(:,:,z);
        return;
    end
    error('bg must be 2D/3D/4D');
end

function [a,b] = parseRangeSafe(s, da, db)
    % ---- RESTORED ORIGINAL STRICT PARSING ----
    % This matches your original behavior and avoids unintended shifts.
    if nargin < 2, da = 0; end
    if nargin < 3, db = da; end
    s = strrep(char(s),'–','-');
    v = sscanf(s,'%f-%f');
    if numel(v) ~= 2 || any(~isfinite(v))
        a = da; b = db;
    else
        a = v(1); b = v(2);
    end
end

function v = parse2(s, dflt)
    % ---- RESTORED ORIGINAL ----
    v = sscanf(char(s),'%f');
    if numel(v) < 2
        v = dflt(:)';
    else
        v = v(1:2);
    end
end

function out = clamp(x, lo, hi)
    out = min(max(x,lo),hi);
end

function M2 = collapseMaskForSlice(M0, ny, nx, z, nZ_)
    if isempty(M0)
        M2 = true(ny,nx);
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
            M2 = any(M0,3);
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
    if size(M2,1) < ny, M2(end+1:ny,:) = true; end
    if size(M2,2) < nx, M2(:,end+1:nx) = true; end
end

function M = readMask(f)
    if ~exist(f,'file')
        error('Mask file not found: %s', f);
    end

    isNiiGz = false;
    if numel(f) >= 7
        isNiiGz = strcmpi(f(end-6:end), '.nii.gz');
    end

    if isNiiGz
        tmpDir = tempname;
        mkdir(tmpDir);
        gunzip(f, tmpDir);
        d = dir(fullfile(tmpDir,'*.nii'));
        if isempty(d)
            error('Failed to gunzip .nii.gz mask.');
        end
        niiFile = fullfile(tmpDir, d(1).name);
        M = niftiread(niiFile);
        try, rmdir(tmpDir,'s'); catch, end
        return;
    end

    [~,~,e] = fileparts(f);
    if strcmpi(e,'.mat')
        S = load(f);
        fn = fieldnames(S);
        M = S.(fn{1});
    else
        M = niftiread(f);
    end
end

function rgb = toRGB(im)
    im = double(im);
    im(~isfinite(im)) = 0;
    rgb = ind2rgb(uint8(mat2gray(im)*255), gray(256));
end

function mkBtn(lbl,x,y,w,h,cb,bgcol,fs)
    uicontrol(fig,'Style','pushbutton','String',lbl,'Units','pixels', ...
        'Position',[x y w h],'Callback',cb, ...
        'BackgroundColor',bgcol,'ForegroundColor','w', ...
        'FontSize',fs,'FontWeight','bold');
end

function out = smooth2D_gauss(in, sigma)
    % Prefer imgaussfilt when available (matches your old code).
    try
        out = imgaussfilt(in, sigma);
        return;
    catch
        % deterministic fallback (conv2)
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

end