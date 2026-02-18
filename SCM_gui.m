function fig = SCM_gui(PSC, bg, TR, par, baseline, varargin)
% SCM_gui — UPDATED: 2D + TRUE 3D SLICE SUPPORT (MATLAB 2017b)
% ============================================================
% Supports:
%   - 2D probe:     PSC [Y X T]
%   - Matrix probe: PSC [Y X Z T]  -> adds slice slider (left of image)
%
% Features preserved:
%   - ROI toggle ON/OFF (hover + click)
%   - Freeze for screenshots: click freezes hover; "Unfreeze" resumes
%   - ROI size slider
%   - Time axis = minutes
%   - Timecourse shows ONLY PSC (hover orange dotted; ROIs colored dotted)
%   - Baseline + signal windows shaded on timecourse
%   - Robust parsing/clamping
%
% New:
%   - Slice slider (when Z>1) positioned LEFT of image axis
%   - ROI storage per slice (switch slices without losing ROIs)
% ============================================================

%% ---------------- SAFETY ----------------
assert(isscalar(TR) && isfinite(TR) && TR>0,'TR must be positive scalar');

pscDims = ndims(PSC);
assert(pscDims==3 || pscDims==4, 'PSC must be [Y X T] or [Y X Z T]');

if pscDims == 3
    [nY,nX,nT] = size(PSC);
    nZ = 1;
else
    [nY,nX,nZ,nT] = size(PSC);
end

if nZ > 1
    fprintf('[SCM] nZ = %d ? slice slider ENABLED\n', nZ);
else
    fprintf('[SCM] nZ = %d ? slice slider DISABLED\n', nZ);
end


tsec = (0:nT-1) * TR;
tmin = tsec / 60;

%% ---------------- OPTIONAL INPUTS ----------------
fileLabel = '';

if ~isempty(varargin)
    lastArg = varargin{end};
    if ischar(lastArg) || (isstring(lastArg) && isscalar(lastArg))
        fileLabel = char(lastArg);
    end
end

if isempty(fileLabel)
    fileLabel = 'SCM';
end


% ---- SAFETY: force char (MATLAB 2017b compatible) ----
if isstring(fileLabel)
    fileLabel = char(fileLabel);
elseif ~ischar(fileLabel)
    fileLabel = 'SCM';
end


I_raw = []; I_interp = [];
initialFPS = 10; maxFPS = 120;
passedMask = [];
applyRejection = false; QC = struct();

if numel(varargin)>=1, I_raw = varargin{1}; end %#ok<NASGU>
if numel(varargin)>=2, I_interp = varargin{2}; end
if numel(varargin)>=3, initialFPS = varargin{3}; end %#ok<NASGU>
if numel(varargin)>=4, maxFPS = varargin{4}; end %#ok<NASGU>
if numel(varargin)>=5, passedMask = varargin{5}; end
if numel(varargin)>=6, applyRejection = varargin{6}; end %#ok<NASGU>
if numel(varargin)>=7, QC = varargin{7}; end %#ok<NASGU>

%% ---------------- STATE ----------------
state.alphaPct = 60;
state.thresh   = 0;
state.cax      = [0 80];
state.sigma    = 1.0;
state.cmap     = 'hot';

% current slice
% ---------------- SLICE INIT ----------------
% current slice: always start from middle by default
state.z = max(1, round(nZ/2));   % default = middle slice

fprintf('[SCM] init slice = %d (nZ=%d)\n', state.z, nZ);


%% ---------------- ROI STATE ----------------
roi.enable   = true;
roi.size     = 12;
roi.colors   = lines(12);
roi.isFrozen = false;

% Store ROIs per slice (so slice switching keeps them)
ROI_byZ = cell(1,nZ);     % each cell: struct array of ROIs
for zz=1:nZ, ROI_byZ{zz} = struct('x1',{},'x2',{},'y1',{},'y2',{},'color',{}); end

roiHandles = gobjects(0);  % visible rects for current slice
roiPlotPSC = gobjects(0);  % visible curves for current slice

%% ---------------- FIGURE ----------------
fig = figure( ...
    'Name', 'SCM Viewer', ...
    'Color',[0.05 0.05 0.05], ...
    'Position',[100 80 1280 800], ...
    'MenuBar','none', ...
    'ToolBar','none');



set(fig,'DefaultUicontrolFontName','Arial');
set(fig,'DefaultUicontrolFontSize',12);

% ---- FEATURE 2: bottom-right credits ----
annotation(fig,'textbox', ...
    [0.62 0.005 0.37 0.03], ...   % normalized: bottom-right strip
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

% Background image handle (updates on slice change)
bg2 = getBg2DForSlice(state.z);
hBG = image(ax, toRGB(bg2));

% Overlay handle (SCM map)
hOV = imagesc(ax, zeros(nY,nX));
set(hOV,'AlphaData',0);

colormap(ax,state.cmap);
caxis(ax,state.cax);

cb = colorbar(ax);
cb.Color = 'w';
cb.Label.String = 'Signal change (%)';
cb.FontSize = 12;
hold(ax,'off');

%% ---------------- SLICE SLIDER (LEFT OF IMAGE) ----------------
slZ = [];
txtZ = [];

if nZ > 1
    % place slider JUST LEFT of image axis (but inside figure)
    axPos = get(ax,'Position');   % [x y w h]

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

    % ? make sure slider is visible above everything
    uistack(slZ,'top');
    uistack(txtZ,'top');
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

%% ---------------- CONTROL PANEL ----------------
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


%% ---------------- INITIAL COMPUTE ----------------
computeSCM();
drawTimeWindows();
redrawROIsForCurrentSlice();

%% ============================================================
% CALLBACKS
%% ============================================================

function sliceChanged(~,~)
    if isempty(slZ), return; end
    zNew = round(slZ.Value);
    zNew = max(1, min(nZ, zNew));
    if zNew == state.z, return; end

    % store nothing special: ROI definitions are already in ROI_byZ{state.z}
    % switch
    state.z = zNew;
    slZ.Value = state.z;
    if ~isempty(txtZ)
        txtZ.String = sprintf('Slice: %d/%d',state.z,nZ);
    end

    % update mask for this slice (if 3D/4D mask was passed or loaded)
if ~isempty(passedMask)
    mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);

end

    % update background
    bg2 = getBg2DForSlice(state.z);
    set(hBG,'CData',toRGB(bg2));

    % clear hover visuals
    set(hLiveRect,'Visible','off');
    set(hLivePSC,'Visible','off');
    roi.isFrozen = false;

    % update SCM + alpha
    computeSCM();
    redrawROIsForCurrentSlice();
end

function toggleROI(~,~)
    roi.enable = logical(cbROI.Value);
    roi.isFrozen = false;

    if ~roi.enable
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
    end
end

function unfreezeHover(~,~)
    roi.isFrozen = false;
end

function setROIsize()
    roi.size = max(1, round(slROI.Value));
    set(txtROIsz,'String',sprintf('%d px',roi.size));
end

function mouseMove(~,~)
    if ~roi.enable || roi.isFrozen
        return;
    end

    % IMPORTANT: only react when cursor is over IMAGE AXIS
    if ~isequal(gco, []) && ~isempty(gco)
        % ok
    end
    if ~isequal(gca, ax)
        return;
    end

    cp = get(ax,'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));

    if x<1 || x>nX || ypix<1 || ypix>nY
        set(hLiveRect,'Visible','off');
        set(hLivePSC,'Visible','off');
        return;
    end

    hlf = floor(roi.size/2);
    x1  = max(1, x-hlf);  x2 = min(nX, x+hlf);
    y1  = max(1, ypix-hlf); y2 = min(nY, ypix+hlf);

    col = roi.colors(mod(numel(ROI_byZ{state.z}),size(roi.colors,1))+1,:);

    set(hLiveRect,'Position',[x1 y1 x2-x1+1 y2-y1+1], ...
        'EdgeColor',col,'Visible','on');

    tc_psc = computeRoiPSC(x1,x2,y1,y2);
    if numel(tc_psc)==nT
        set(hLivePSC,'YData',tc_psc,'Visible','on');
    else
        set(hLivePSC,'Visible','off');
    end

    drawTimeWindows();
end

function mouseScroll(~, evt)
    if nZ <= 1
        return;
    end

    % Determine what object the mouse is over
    h = hittest(fig);
    if isempty(h)
        return;
    end

    axHit = ancestor(h, 'axes');
    if isempty(axHit) || axHit ~= ax
        return;   % only scroll when over image axis
    end

    % Scroll direction (natural)
    dz = -sign(evt.VerticalScrollCount);
    if dz == 0
        return;
    end

    zNew = state.z + dz;
    zNew = max(1, min(nZ, zNew));

    if zNew == state.z
        return;
    end

    % Update slice state
    state.z = zNew;

    % Sync slider
    if ~isempty(slZ) && isgraphics(slZ)
        slZ.Value = state.z;
    end

    % Update label
    if ~isempty(txtZ)
        txtZ.String = sprintf('Slice: %d / %d', state.z, nZ);
    end

    % Update mask for this slice
    if ~isempty(passedMask)
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);

    end

    % Update background + SCM
    bg2 = getBg2DForSlice(state.z);
    set(hBG, 'CData', toRGB(bg2));

    computeSCM();
    redrawROIsForCurrentSlice();
end

function mouseClick(~,~)
    if ~roi.enable
        return;
    end
    if ~isequal(gca, ax)
        return;
    end

    cp = get(ax,'CurrentPoint');
    x = round(cp(1,1)); ypix = round(cp(1,2));
    if x<1 || x>nX || ypix<1 || ypix>nY
        return;
    end

    hlf = floor(roi.size/2);
    x1  = max(1, x-hlf);  x2 = min(nX, x+hlf);
    y1  = max(1, ypix-hlf); y2 = min(nY, ypix+hlf);

    type = get(fig,'SelectionType');

    if strcmp(type,'normal')
        roi.isFrozen = true;

        tc_psc = computeRoiPSC(x1,x2,y1,y2);
        if numel(tc_psc)~=nT
            return;
        end

        col = roi.colors(mod(numel(ROI_byZ{state.z}),size(roi.colors,1))+1,:);

        ROI_byZ{state.z}(end+1) = struct('x1',x1,'x2',x2,'y1',y1,'y2',y2,'color',col);

        % draw immediately
        redrawROIsForCurrentSlice();
        drawTimeWindows();

    elseif strcmp(type,'alt')
        if isempty(ROI_byZ{state.z}), return; end

        ROI = ROI_byZ{state.z};
        ctr = arrayfun(@(r)[(r.x1+r.x2)/2,(r.y1+r.y2)/2],ROI,'uni',0);
        ctr = cat(1,ctr{:});
        [~,i] = min(sum((ctr-[x ypix]).^2,2));

        if i>=1 && i<=numel(ROI)
            ROI(i) = [];
            ROI_byZ{state.z} = ROI;
            redrawROIsForCurrentSlice();
        end
    end
end


disp([b0 b1 s0 s1]);
disp([b0i b1i s0i s1i]);

%% ---------------- SCM COMPUTATION ----------------
function computeSCM(~,~)
    [b0,b1] = parseRangeSafe(get(ebBase,'String'), baseline.start, baseline.end);
    [s0,s1] = parseRangeSafe(get(ebSig,'String'),  baseline.end+10, baseline.end+40);

    sig = str2double(get(ebSigma,'String'));
    if ~isfinite(sig), sig = state.sigma; end
    state.sigma = sig;

    % convert to indices (inclusive)
    b0i = clamp(round(b0/TR)+1,1,nT);
    b1i = clamp(round(b1/TR)+1,1,nT);
    if b1i < b0i, tmp=b0i; b0i=b1i; b1i=tmp; end

    s0i = clamp(round(s0/TR)+1,1,nT);
    s1i = clamp(round(s1/TR)+1,1,nT);
    if s1i < s0i, tmp=s0i; s0i=s1i; s1i=tmp; end

    PSCz = getPSCForSlice(state.z); % [Y X T]

    base = mean(PSCz(:,:,b0i:b1i),3);
    sigm = mean(PSCz(:,:,s0i:s1i),3);
    map  = sigm - base;

    if sig>0
        map = imgaussfilt(map, sig);
    end

    set(hOV,'CData',map);
    updateView();
    drawTimeWindows();
end

function updateView(~,~)
    state.alphaPct = slAlpha.Value;
    set(txtAlpha,'String',sprintf('%.0f',state.alphaPct));

    thr = str2double(get(ebThr,'String'));
    if ~isfinite(thr), thr = 0; end
    state.thresh = thr;

    cax = parse2(get(ebCax,'String'), state.cax);
    if numel(cax)==2 && isfinite(cax(1)) && isfinite(cax(2)) && cax(2)>cax(1)
        state.cax = cax(:)';
    end

    state.cmap = popMap.String{popMap.Value};

    ov = get(hOV,'CData');
    alpha = (state.alphaPct/100) .* (abs(ov) >= state.thresh) .* double(mask2D);
    set(hOV,'AlphaData',alpha);

    colormap(ax,state.cmap);
    caxis(ax,state.cax);
end

%% ---------------- TIME WINDOW OVERLAYS ----------------
function drawTimeWindows()
    [b0,b1] = parseRangeSafe(get(ebBase,'String'), baseline.start, baseline.end);
    [s0,s1] = parseRangeSafe(get(ebSig,'String'),  baseline.end+10, baseline.end+40);

    if b1 < b0, tmp=b0; b0=b1; b1=tmp; end
    if s1 < s0, tmp=s0; s0=s1; s1=tmp; end

    yl = get(axTC,'YLim');
    if any(~isfinite(yl)) || yl(2)<=yl(1)
        yl = [-5 5];
        set(axTC,'YLim',yl);
    end

    xb = [b0 b1 b1 b0] / 60;
    yb = [yl(1) yl(1) yl(2) yl(2)];
    set(hBasePatch,'XData',xb,'YData',yb,'FaceColor',[0.6 0.8 1.0],'Visible','on');

    xs = [s0 s1 s1 s0] / 60;
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
    PSCz = getPSCForSlice(state.z); % [Y X T]
    tc = squeeze(mean(mean(PSCz(y1:y2, x1:x2, :), 1), 2));
    if isempty(tc)
        tc_psc = [];
        return;
    end

    tc = tc(:)';   % row
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
    % delete currently drawn ROI handles/curves
    deleteIfValid(roiHandles); roiHandles = gobjects(0);
    deleteIfValid(roiPlotPSC); roiPlotPSC = gobjects(0);

    ROI = ROI_byZ{state.z};
    if isempty(ROI)
        return;
    end

    for k = 1:numel(ROI)
        r = ROI(k);
        roiHandles(end+1) = rectangle(ax,'Position',[r.x1 r.y1 r.x2-r.x1+1 r.y2-r.y1+1], ...
            'EdgeColor',r.color,'LineWidth',2); %#ok<AGROW>

        tc = computeRoiPSC(r.x1,r.x2,r.y1,r.y2);
        if numel(tc)==nT
            roiPlotPSC(end+1) = plot(axTC, tmin, tc, ':', 'Color', r.color, 'LineWidth', 2.2); %#ok<AGROW>
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
    [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz','Mask files (*.mat,*.nii,*.nii.gz)'});
    if isequal(f,0), return; end
    try
        passedMask = readMask(fullfile(p,f));    % store full mask so slice changes work
        mask2D = collapseMaskForSlice(passedMask, nY, nX, state.z, nZ);

        updateView();
    catch ME
        warning('Mask load failed: %s', ME.message);
    end
end

function clearMaskCB(~,~)
    passedMask = [];
    mask2D = true(nY,nX);
    updateView();
end

%% ---------------- VIDEO GUI (UNCHANGED CALL SIGNATURE) ----------------
function openVideo(~,~)
    if isempty(I_interp)
        return;
    end

    % SCM does not track include/exclude; default = Include
    loadedMaskIsInclude = true;

    % Play video GUI with mask passed from SCM viewer
    play_fusi_video_final( ...
        I_raw, I_interp, PSC, bg, ...
        par, initialFPS, maxFPS, ...
        TR, (nT-1)*TR, baseline, ...
        passedMask, loadedMaskIsInclude, ...
        nT, applyRejection, QC, fileLabel );
end



function showHelp(~,~)
    msg = {
        'SCM Viewer'
        ''
        'Matrix probe: use the slice slider (left of image) to change slices.'
        ''
        'ROI: enable checkbox toggles hover + click.'
        'Hover: live PSC shown (orange dotted).'
        'Left-click: add ROI (persistent PSC curve) + freezes hover for screenshots.'
        'Unfreeze Hover: resumes live hover updates.'
        'Right-click: remove nearest ROI.'
        ''
        'Time axis: minutes.'
        'Baseline and Signal windows are shaded.'
    };
    helpdlg(msg,'SCM Help');
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
    % Accept bg:
    %   [Y X]
    %   [Y X Z]
    %   [Y X Z T]
    %   [Y X T]  (rare) -> mean over T
    if ndims(bg)==2
        bg2 = bg;
        return;
    end
    if ndims(bg)==3
        % could be [Y X Z] or [Y X T]
        if size(bg,3) == nT && nZ==1
            bg2 = mean(bg,3);
        else
            z = max(1, min(size(bg,3), z));
            bg2 = bg(:,:,z);
        end
        return;
    end
    if ndims(bg)==4
        % [Y X Z T] -> mean over T, then slice
        tmp = mean(bg,4);  % [Y X Z]
        z = max(1, min(size(tmp,3), z));
        bg2 = tmp(:,:,z);
        return;
    end
    error('bg must be 2D/3D/4D');
end

function [a,b] = parseRangeSafe(s, da, db)
    if nargin<2, da = 0; end
    if nargin<3, db = da; end
    s = strrep(s,'–','-');
    v = sscanf(s,'%f-%f');
    if numel(v)~=2 || any(~isfinite(v))
        a = da; b = db;
    else
        a = v(1); b = v(2);
    end
end

function v = parse2(s, dflt)
    v = sscanf(s,'%f');
    if numel(v)<2
        v = dflt(:)';
    else
        v = v(1:2);
    end
end

function out = clamp(x, lo, hi)
    out = min(max(x,lo),hi);
end

function M2 = collapseMaskForSlice(M0, ny, nx, z, nZ)
    % M0 can be:
    % 2D: [Y X]
    % 3D: [Y X Z]  OR  [Y X nVols]  (from Video GUI)
    % 4D: [Y X Z T] or [Y X T something]
    %
    % Rule:
    % - If nZ>1 and dim3 == nZ -> treat as Z-slices
    % - Otherwise treat dim3 as time/volumes and collapse with ANY()

    if isempty(M0)
        M2 = true(ny,nx);
        return;
    end

    M0 = logical(M0);

    if ndims(M0) == 2
        M2 = M0;

    elseif ndims(M0) == 3
        if nZ > 1 && size(M0,3) == nZ
            z = max(1, min(size(M0,3), z));
            M2 = M0(:,:,z);             % true slice mask
        else
            M2 = any(M0,3);             % collapse volumes/time -> 2D
        end

    else
        % 4D or higher: collapse last dim(s) first
        tmp = M0;
        while ndims(tmp) > 3
            tmp = any(tmp, ndims(tmp));
        end

        if ndims(tmp)==3 && nZ > 1 && size(tmp,3) == nZ
            z = max(1, min(size(tmp,3), z));
            M2 = tmp(:,:,z);
        else
            while ndims(tmp) > 2
                tmp = any(tmp, ndims(tmp));
            end
            M2 = tmp;
        end
    end

    % crop/pad to [ny nx]
    M2 = M2(1:min(ny,size(M2,1)), 1:min(nx,size(M2,2)));
    if size(M2,1) < ny, M2(end+1:ny,:) = true; end
    if size(M2,2) < nx, M2(:,end+1:nx) = true; end
end


function M = readMask(f)
    [~,~,e] = fileparts(f);
    if strcmpi(e,'.gz')
        M = niftiread(f);
        return;
    end
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

end
