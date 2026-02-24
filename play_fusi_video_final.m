function fig = play_fusi_video_final( ...
    I, I_interp, PSC, bg, par, fps, maxFPS, TR, Tmax, baseline, ...
    loadedMask, loadedMaskIsInclude, nVols, applyRejection, QC, fileLabel, sliceIdx)

disp('fps ='); disp(fps);
disp('maxFPS ='); disp(maxFPS);

% =========================================================
%  fUSI Video GUI — MATRIX PROBE + 2D SUPPORT
%  (MATLAB 2017b compatible)
%
% THIS UPDATE:
%   ? Alpha intensity modulation is now IDENTICAL to SCM_gui:
%      alpha = (a/100) * thrMask * baseMask                 (if mod OFF)
%      alpha = (a/100) * mod * thrMask * baseMask           (if mod ON)
%        mod = clamp( (|PSC|-effLo)/(effHi-effLo), 0..1 )
%        effLo = max(modMin, thr)
%        effHi = modMax  (fallback to max(|PSC|) if invalid)
%
% Notes:
%   - "Signal Change Threshold [PSC]" now matches SCM behavior:
%       hides low |PSC| by alpha (set thr=0 to show everything)
%   - Controls are EDIT BOXES like SCM (Alpha%, ModMin, ModMax)
% =========================================================

% ---- defaults ----
if ~isfield(par,'interpol') || isempty(par.interpol) || ~isfinite(par.interpol) || par.interpol < 1
    par.interpol = 1;
end

% Ensure previewCaxis exists (robust PSC scaling)
if ~isfield(par,'previewCaxis') || isempty(par.previewCaxis)
    tmp = PSC(:); tmp = tmp(isfinite(tmp));
    if isempty(tmp)
        par.previewCaxis = [-5 5];
    else
        low  = prctile(tmp, 1);
        high = prctile(tmp, 99);
        if ~isfinite(low) || ~isfinite(high) || high <= low
            par.previewCaxis = [-5 5];
        else
            par.previewCaxis = [low high];
        end
    end
end

% ---------------- DIMENSIONS (PSC) ----------------
bgFull = bg;   % keep full [Y X], [Y X Z] or [Y X Z T]
ndPSC = ndims(PSC);

switch ndPSC
    case 4  % [Y X Z T]
        [nz, nx, nZ, nFrames] = size(PSC);
    case 3  % [Y X T]  (2D probe -> Z=1)
        [nz, nx, nFrames] = size(PSC);
        nZ = 1;
    case 2  % [Y X] (rare)
        [nz, nx] = size(PSC);
        nZ = 1;
        nFrames = 1;
    otherwise
        error('PSC must be 2D, 3D or 4D.');
end

% ---- Ensure slice index ----
if nargin < 17 || isempty(sliceIdx) || ~isfinite(sliceIdx)
    if nZ > 1
        sliceIdx = round(nZ/2);
    else
        sliceIdx = 1;
    end
end
sliceIdx = max(1, min(nZ, round(sliceIdx)));

% -------- ensure I_interp exists --------
if isempty(I_interp)
    I_interp = I;
end

% =========================================================
%  FIGURE + LAYOUT
% =========================================================
fig = figure('Color','k','Position',[600 -100 1500 900], ...
    'Name','fUSI Video Analysis — Soner (Auto Mask v3, Slice-wise)', ...
    'NumberTitle','off');

set(fig,'CloseRequestFcn',@onCloseVideo);

% Remove any accidental colorbars (safety)
try
    delete(findall(fig,'Type','ColorBar'));
catch
end

% ---- Slice indicator (top-left text) ----
if nZ > 1
    sliceLabel = sprintf('Slice: %d / %d', sliceIdx, nZ);
else
    sliceLabel = '';
end

txtSlice = annotation(fig,'textbox', ...
    [0.02 0.915 0.30 0.035], ...
    'String', sliceLabel, ...
    'Color',[0.85 0.90 1.00], ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'EdgeColor','none', ...
    'Interpreter','none');

% ---- Main axes ----
ax  = axes('Parent',fig,'Units','normalized', ...
           'Position',[0.14 0.12 0.56 0.70]);
axis(ax,'off','image');

img = image(ax, zeros(nz, nx, 3, 'single'));
set(ax,'HitTest','on');
set(img,'HitTest','off');

% (small slice label inside axes, bottom-right)
txtSliceAx = text(ax, 0.99, 0.02, '', ...
    'Units','normalized', ...
    'Color',[0.80 0.90 1.00], ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'VerticalAlignment','bottom', ...
    'Interpreter','none');

% ================= FILE NAME LABEL (VIDEO GUI) =================
if ~isempty(fileLabel)
    annotation(fig,'textbox', ...
        [0.22 0.82 0.60 0.045], ...
        'String', fileLabel, ...
        'Color',[0.95 0.95 0.95], ...
        'FontSize',14, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left', ...
        'EdgeColor','none', ...
        'Interpreter','none');
end

% --- Colormap for PSC bar (only for colorbar display) ---
Nc   = 128;
mapA = hot(Nc);
mapA(1,:) = 0;    % zero PSC = black

% Info line (top)
info = uicontrol('Style','text','Units','normalized', ...
    'Position',[0.01 0.88 0.74 0.09], ...
    'ForegroundColor','w', 'BackgroundColor','k', ...
    'FontName','Courier', 'FontSize',13, ...
    'HorizontalAlignment','left');

% Right panel placement
figPos = get(fig,'Position');
rightX = round(figPos(3) * 0.72);

uiFontName = 'Helvetica';
uiFontSize = 11;

% ---------------------------------------------------------
%  CONTROL PANEL TITLE
% ---------------------------------------------------------
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 835 360 18], ...
    'String','CONTROL PANEL', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

% ================= PLAYBACK CONTROLS =================
rowH = 28;
gap  = 10;

y = 800;  % rolling Y anchor (top-down layout)

% -------- FPS --------
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y 100 rowH], ...
    'String','FPS', ...
    'ForegroundColor','w', 'BackgroundColor','k', ...
    'FontName',uiFontName, 'FontSize',uiFontSize, ...
    'HorizontalAlignment','right');

fpsValue = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+105 y 120 rowH], ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName, 'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

fpsSlider = uicontrol('Style','slider', ...
    'Min',1,'Max',maxFPS,'Value',fps, ...
    'Units','pixels', ...
    'Position',[rightX y-rowH 360 rowH], ...
    'Callback',@(s,~) setFPS(s.Value));

y = y - (rowH*2 + gap);

% -------- VOLUME --------
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y 100 rowH], ...
    'String','Volume', ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','right');

volValue = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+105 y 140 rowH], ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

volSlider = uicontrol('Style','slider', ...
    'Min',1,'Max',nVols,'Value',1, ...
    'Units','pixels', ...
    'Position',[rightX y-rowH 360 rowH], ...
    'Callback',@(s,~) scrubVol(round(s.Value)));

y = y - (rowH*2 + 18);

% =========================================================
%  SINGLE COLORBAR (PSC ONLY)  — LEFT SIDE
% =========================================================
try
    colormap(ax, mapA);  % only affects the colorbar; the image is RGB
catch
end
caxis(ax, par.previewCaxis);

cbar = colorbar(ax, 'Position',[0.06 0.18 0.014 0.58]);
cbar.Color = 'w';
cbar.FontSize = 13;
cbar.Label.String = 'Signal Change (%)';
cbar.Label.FontSize = 14;
cbar.Label.Color = 'w';
set(cbar,'Limits',par.previewCaxis);

% Button BELOW colorbar (bottom-left corner)
uicontrol('Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.045 0.10 0.075 0.035], ...
    'String','Color Bar Range', ...
    'FontWeight','bold', ...
    'Callback',@setColorbarRange);

% Footer
uicontrol('Style','text','Units','pixels', ...
    'Position',[10 10 700 24], ...
    'String','fUSI Video Analysis — Soner C., MPI for Biological Cybernetics, 2026', ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',11);

% =========================================================
%  INITIALIZE MASK (ALWAYS FIRST)
% =========================================================
mask = false(nz, nx, nZ, nVols);
maskIsInclude = true;
statusLine    = '';

if exist('loadedMask','var') && ~isempty(loadedMask)
    loadedMask = logical(loadedMask);

    switch ndims(loadedMask)
        case 2
            mask(:,:,sliceIdx,:) = repmat(loadedMask,[1 1 1 nVols]);
            statusLine = '2D mask expanded to all frames (current slice).';
        case 3
            for zz = 1:min(nZ,size(loadedMask,3))
                mask(:,:,zz,:) = repmat(loadedMask(:,:,zz),[1 1 1 nVols]);
            end
            statusLine = '3D mask expanded to all frames.';
        case 4
            if isequal(size(loadedMask), size(mask))
                mask = loadedMask;
                statusLine = '4D mask restored.';
            else
                statusLine = '4D mask size mismatch — ignored.';
            end
    end

    maskIsInclude = loadedMaskIsInclude;
end

% =========================================================
%  STATE
% =========================================================
volPos  = 1.0;
volume  = 1;
frame   = 1;
playing = false;

applyToAllFrames = true;  % apply painting to all volumes (THIS SLICE)
editorMode     = false;
viewMaskedOnly = false;

% Brush settings
brushRadius   = 12;
maskAlpha     = 0.35;
maskColor     = [1 1 1];

% Threshold in PSC units (abs %) — matches SCM behavior
maskThreshold = 0;

% AUTO MASK fixed to robust A (no UI)
strictMode     = 2;  %#ok<NASGU>
percentileKeep = 90; %#ok<NASGU>

% Fill parameters
fillWindowR     = 18;
fillSigmaFactor = 1.8;
fillMaxPixels   = 300000;

% Mouse / keyboard
mouseIsDown = false;
paintMode   = '';
lastMouseXY = [NaN NaN];

% ============================================================
%  PSC ALPHA MODULATION (IDENTICAL TO SCM_gui)
% ============================================================
alphaModEnable = true;   % state.alphaModOn
alphaPct       = 100;    % "Overlay alpha (%)" 0..100
modMinAbs      = 50;     % "Mod Min (abs %)"
modMaxAbs      = 100;    % "Mod Max (abs %)"

% =========================================================
%  RIGHT PANEL: MASK / TOOLS  (NO OVERLAPS)
% =========================================================
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y 360 20], ...
    'String','Mask / Tools', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

y = y - 30;

editBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX y 360 28], ...
    'String','Editor OFF', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleEditor);

y = y - 35;

viewBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX y 175 28], ...
    'String','VIEW: FULL', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleViewMasked);

includeDrop = uicontrol('Style','popupmenu','Units','pixels', ...
    'Position',[rightX+185 y 175 28], ...
    'String',{'Include','Exclude'}, ...
    'Value',1, ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setIncludeExclude);

y = y - 35;

applyAllBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX y 175 28], ...
    'String','AUTO: ALL', ...
    'Value',1, ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleApplyAll);

autoBtn = uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+185 y 175 28], ...
    'String','AUTO MASK (M)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'FontWeight','bold', ...
    'Callback',@autoMaskButton);

y = y - 32;

% Brush size
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y 140 18], ...
    'String','Brush size', ...
    'ForegroundColor',[0.8 0.8 0.8], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

y = y - 20;

brushSlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX y 360 18], ...
    'Min',1,'Max',25,'Value',brushRadius, ...
    'Callback',@(s,~) setBrush(round(s.Value)));

y = y - 22;

brushVal = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y 360 16], ...
    'String',sprintf('Radius: %d px',brushRadius), ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

y = y - 32;

% Fill / Color / Clear
uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX y 110 28], ...
    'String','Color...', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@pickColor);

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+120 y 110 28], ...
    'String','Fill (F)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@fillRegion);

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+240 y 120 28], ...
    'String','Clear mask', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@clearMaskAll);

y = y - 44;

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX y 360 32], ...
    'String','Save Mask (.mat)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@saveMaskMat);

y = y - 40;

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX y 360 32], ...
    'String','Save Interpolated Data (.mat)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@saveInterpolatedMat);

y = y - 48;

% ============================================================
%  PSC ALPHA MODULATION (SCM IDENTICAL)
% ============================================================
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y+22 360 18], ...
    'String','PSC Alpha Modulation (IDENTICAL to SCM_gui)', ...
    'ForegroundColor',[0.90 0.90 0.90], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

alphaEnableChk = uicontrol('Style','checkbox','Units','pixels', ...
    'Position',[rightX y 110 18], ...
    'String','Alpha modulate by |PSC|', ...
    'Value',double(alphaModEnable), ...
    'ForegroundColor','w', ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleAlphaMod);

% Alpha %, ModMin, ModMax edit boxes
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+120 y 45 18], ...
    'String','alpha', ...
    'ForegroundColor',[0.85 0.85 0.85], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

editAlphaPct = uicontrol('Style','edit','Units','pixels', ...
    'Position',[rightX+160 y-2 50 22], ...
    'String',sprintf('%.0f',alphaPct), ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setAlphaPctBox);

uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+215 y 35 18], ...
    'String','min', ...
    'ForegroundColor',[0.85 0.85 0.85], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

editModMin = uicontrol('Style','edit','Units','pixels', ...
    'Position',[rightX+245 y-2 50 22], ...
    'String',sprintf('%.3g',modMinAbs), ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setModMinBox);

uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+300 y 35 18], ...
    'String','max', ...
    'ForegroundColor',[0.85 0.85 0.85], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

editModMax = uicontrol('Style','edit','Units','pixels', ...
    'Position',[rightX+330 y-2 50 22], ...
    'String',sprintf('%.3g',modMaxAbs), ...
    'BackgroundColor',[0.10 0.10 0.10], ...
    'ForegroundColor','w', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setModMaxBox);

y = y - 46;

% ============================================================
%  MASK OVERLAY ALPHA
% ============================================================
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y+18 240 18], ...
    'String','Mask Overlay Alpha', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

overlaySlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX y 360 18], ...
    'Min',0,'Max',1,'Value',maskAlpha, ...
    'Callback',@(s,~) setOverlayAlpha(s.Value));

y = y - 38;

% ============================================================
%  SIGNAL CHANGE THRESHOLD (PSC)
% ============================================================
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y+18 360 18], ...
    'String','Signal Change Threshold [PSC] (%)', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k', ...
    'HorizontalAlignment','left', ...
    'FontName',uiFontName,'FontSize',uiFontSize);

tmpPSC = PSC(:); tmpPSC = tmpPSC(isfinite(tmpPSC));
if isempty(tmpPSC)
    thrMin = par.previewCaxis(1);
    thrMax = par.previewCaxis(2);
else
    thrMin = prctile(tmpPSC,1);
    thrMax = prctile(tmpPSC,99);
end
if ~isfinite(thrMin) || ~isfinite(thrMax) || thrMax <= thrMin
    thrMin = par.previewCaxis(1);
    thrMax = par.previewCaxis(2);
end
maskThreshold = 0;

maskThreshSlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX y 360 18], ...
    'Min',thrMin,'Max',thrMax,'Value',maskThreshold, ...
    'Callback',@(s,~) setMaskThreshold(s.Value));

y = y - 52;

% ============================================================
%  APPLY MASK TO ALL VOLUMES (THIS SLICE)
% ============================================================
applyAllMaskBtn = uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX y 360 34], ...
    'String','Apply Mask to all Volumes (THIS SLICE)', ...
    'FontWeight','bold', ...
    'ForegroundColor','w', ...
    'BackgroundColor',[0.20 0.45 0.25], ...
    'Callback',@applyMaskToAllFrames);

% ============================================================
%  BOTTOM PANEL BUTTONS (FIXED)
% ============================================================
btnW  = 120;
btnH  = 42;
gapX  = 18;
gapY  = 18;

row1Y = 40;
row2Y = row1Y + btnH + gapY;

helpBtn = uicontrol('Style','pushbutton','String','HELP', ...
    'Units','pixels', 'Position',[rightX row2Y btnW btnH], ...
    'BackgroundColor',[0.25 0.40 0.65], 'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@showHelpDialog);

closeBtn = uicontrol('Style','pushbutton','String','CLOSE', ...
    'Units','pixels', 'Position',[rightX+btnW+gapX row2Y btnW btnH], ...
    'BackgroundColor',[0.65 0.25 0.25], 'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@(~,~) close(fig));

scmBtn = uicontrol('Style','pushbutton','String','Open SCM', ...
    'Units','pixels', ...
    'Position',[rightX+2*(btnW+gapX) row2Y btnW btnH], ...
    'BackgroundColor',[0.25 0.55 0.35], ...
    'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@openSCM);

playBtn = uicontrol('Style','togglebutton','String','Play', ...
    'Units','pixels', ...
    'Position',[rightX row1Y btnW btnH], ...
    'BackgroundColor',[0.20 0.45 0.20], 'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@playPause);

replayBtn = uicontrol('Style','pushbutton','String','Replay', ...
    'Units','pixels', ...
    'Position',[rightX+btnW+gapX row1Y btnW btnH], ...
    'BackgroundColor',[0.35 0.35 0.35], 'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@replayVid);

saveMP4Btn = uicontrol('Style','pushbutton','String','Save MP4', ...
    'Units','pixels', ...
    'Position',[rightX+2*(btnW+gapX) row1Y btnW btnH], ...
    'BackgroundColor',[0.25 0.40 0.65], 'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',@saveVideo);

% ---------------------------------------------------------
%  FIGURE CALLBACKS (mouse / keyboard / scroll)
% ---------------------------------------------------------
set(fig,'WindowButtonDownFcn',@mouseDown);
set(fig,'WindowButtonUpFcn',@mouseUp);
set(fig,'WindowButtonMotionFcn',@mouseMoveVideo);
set(fig,'KeyPressFcn',@keyPressHandler);
set(fig,'WindowScrollWheelFcn',@mouseScrollSlice);

% ================= INITIAL RENDER + TIMER =================
render();
alphaModToggledUI();

% =========================================================
%  PLAYBACK TIMER
% =========================================================
playTimer = timer( ...
    'ExecutionMode','fixedSpacing', ...
    'Period',1/max(fps,0.1), ...
    'TimerFcn',@timerTick);

    function timerTick(~,~)
        if ~ishandle(fig) || ~playing
            return;
        end

        volume = volume + 1;

        if volume > nVols
            volume = nVols;
            playing = false;

            if ishandle(playBtn)
                playBtn.Value = 0;
                playBtn.String = 'Play';
            end

            stop(playTimer);
            return;
        end

        volSlider.Value = volume;

        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));

        render();
    end

% =========================================================
%  RENDER
% =========================================================
    function render()

        sliceIdx = max(1, min(nZ, sliceIdx));

        % 1) Background slice
        bg2 = getBg2DForSlice(bgFull, sliceIdx, nZ);
        bg2(~isfinite(bg2)) = 0;

        mn = min(bg2(:));
        mx = max(bg2(:));
        if mx > mn
            bgNorm = (bg2 - mn) ./ (mx - mn);
        else
            bgNorm = zeros(size(bg2));
        end
        bgRGB = ind2rgb(uint8(bgNorm * 127), gray(128));

        % 2) Frame safety
        if frame < 1 || frame > nFrames
            img.CData = bgRGB;
            return;
        end

        curVol = volume;

        % 3) PSC slice for current frame
        if ndPSC == 4
            A = squeeze(PSC(:,:,sliceIdx, frame));
        elseif ndPSC == 3
            A = PSC(:,:,frame);
        else
            A = PSC; % 2D
        end
        A(~isfinite(A)) = 0;

        % Colorbar bounds (PSC units)
        cax = par.previewCaxis;
        if numel(cax) ~= 2 || ~isfinite(cax(1)) || ~isfinite(cax(2)) || diff(cax) <= 0
            cax = [-10 10];
            par.previewCaxis = cax;
        end
        if ishandle(cbar)
            set(cbar,'Limits',cax);
        end

        % PSC -> RGB (based on cax)
        A_scaled = (A - cax(1)) ./ (cax(2) - cax(1) + eps);
        A_scaled = max(0, min(1, A_scaled));
        pscRGB = ind2rgb(uint8(A_scaled * (Nc-1)), mapA);

        % 4) Mask extraction (2D for this slice + volume)
        M = squeeze(mask(:,:,sliceIdx, curVol));
        M = logical(M);
        M = M(1:size(bg2,1), 1:size(bg2,2));

        % 5) Determine baseMask (SCM-style): FULL -> all ones, MASKED -> include/exclude
        if viewMaskedOnly
            show = M;
            if ~maskIsInclude
                show = ~M;
            end
            baseMask = double(show);
        else
            baseMask = 1; % scalar OK (expands)
        end

        % 6) SCM-identical alpha modulation using |PSC| and threshold
        thr = maskThreshold; % "Threshold (abs %)" equivalent
        thrMask = double(abs(A) >= thr);

        a = max(0, min(100, alphaPct)); % overlay alpha (%)
        if ~alphaModEnable
            alphaMap = (a/100) .* thrMask .* baseMask;
        else
            effLo = max(modMinAbs, thr);
            effHi = modMaxAbs;

            if ~isfinite(effHi) || effHi <= effLo
                effHi = max(abs(A(:)));
            end
            if ~isfinite(effHi) || effHi <= effLo
                effHi = effLo + eps;
            end

            mod = (abs(A) - effLo) ./ max(eps, (effHi - effLo));
            mod(~isfinite(mod)) = 0;
            mod = min(max(mod,0),1);

            alphaMap = (a/100) .* mod .* thrMask .* baseMask;
        end

        alphaMap(~isfinite(alphaMap)) = 0;
        alphaMap = min(max(alphaMap,0),1);

        a3 = repmat(alphaMap,[1 1 3]);
        baseRGB = (1-a3).*bgRGB + a3.*pscRGB;

        % 7) Apply mask overlay tint (editor visual)
        outRGB = baseRGB;

        if ~viewMaskedOnly
            if any(M(:))
                maskRGB = cat(3, ...
                    ones(size(bg2))*maskColor(1), ...
                    ones(size(bg2))*maskColor(2), ...
                    ones(size(bg2))*maskColor(3));

                M3 = repmat(M,[1 1 3]);

                alphaUse = maskAlpha;
                if editorMode
                    alphaUse = max(0.6, maskAlpha); % stronger during editing
                end

                outRGB = outRGB .* (1 - alphaUse .* M3) + ...
                         maskRGB .* (alphaUse .* M3);
            end
        end

        img.CData = outRGB;

        % 8) Info line
        t = (volume - 1) * TR;

        em = tern(editorMode,'ON','OFF');
        vm = tern(viewMaskedOnly,'MASKED','FULL');
        ms = tern(maskIsInclude,'Include','Exclude');

        if isfield(baseline,'mode')
            modeStr = baseline.mode;
        else
            modeStr = 'sec';
        end

        alphaState = tern(alphaModEnable,'ON','OFF');

        extra = '';
        if ~isempty(statusLine)
            extra = [' | ' statusLine];
        end

        info.String = sprintf( ...
            ['t = %.1f / %.1f s   |   Vol %d / %d   |   View: %s (%s)\n' ...
             'Baseline: %g–%g %s   |   Editor: %s   |   AUTO: A   |   AlphaMod: %s   |   alpha=%g%%  min=%g  max=%g%s'], ...
            t, Tmax, volume, nVols, vm, ms, ...
            baseline.start, baseline.end, modeStr, ...
            em, alphaState, alphaPct, modMinAbs, modMaxAbs, extra);

        fpsValue.String = sprintf('%d FPS', fps);
        volValue.String = sprintf('%d / %d', volume, nVols);

        txtSliceAx.String = sliceString(sliceIdx, nZ);

    end

% =========================================================
%  PLAYBACK / SCRUB / FPS
% =========================================================
    function scrubVol(v)
        playing        = false;
        playBtn.Value  = 0;
        playBtn.String = 'Play';

        volume = min(max(1, v), nVols);
        volPos = volume;

        frame = (volume - 1) * par.interpol + 1;
        frame = max(1, min(nFrames, round(frame)));

        render();
    end

    function setFPS(v)
        fps = max(1, min(maxFPS, round(v)));

        if exist('playTimer','var') && isa(playTimer,'timer') && isvalid(playTimer)
            stop(playTimer);
            set(playTimer,'Period',1/max(fps,0.1));
            if playing
                start(playTimer);
            end
        end

        fpsValue.String = sprintf('%d FPS', fps);
    end

    function playPause(src,~)
        playing = logical(src.Value);

        if playing
            src.String = 'Pause';
            if exist('playTimer','var') && isa(playTimer,'timer')
                if strcmp(playTimer.Running,'off')
                    set(playTimer,'Period',1/max(fps,0.1));
                    start(playTimer);
                end
            end
        else
            src.String = 'Play';
            if exist('playTimer','var') && isa(playTimer,'timer')
                if strcmp(playTimer.Running,'on')
                    stop(playTimer);
                end
            end
        end
    end

    function replayVid(~, ~)
        volume = 1;
        volSlider.Value = 1;
        frame = 1;

        playing = true;
        playBtn.Value = 1;
        playBtn.String = 'Pause';

        if exist('playTimer','var') && isa(playTimer,'timer')
            stop(playTimer);
            set(playTimer,'Period',1/max(fps,0.1));
            start(playTimer);
        end

        render();
    end

% =========================================================
%  SCROLL SLICE
% =========================================================
    function mouseScrollSlice(~, evt)
        if nZ <= 1 || playing
            return;
        end

        h = hittest(fig);
        if isempty(h), return; end
        axHit = ancestor(h,'axes');
        if isempty(axHit) || axHit ~= ax
            return;
        end

        dz = -sign(evt.VerticalScrollCount);
        if dz == 0, return; end

        newZ = max(1, min(nZ, sliceIdx + dz));
        if newZ == sliceIdx, return; end

        sliceIdx = newZ;

        if nZ > 1
            txtSlice.String = sprintf('Slice: %d / %d', sliceIdx, nZ);
        else
            txtSlice.String = '';
        end

        render();
    end

% =========================================================
%  OPEN SCM GUI (transfers mask collapsed over time)
% =========================================================
    function openSCM(~,~)
        try
            PSC_fast = PSC;
            bg_fast  = bgFull;

            if nZ == 1
                mask_fast = any(mask(:,:,1,:), 4);   % [Y X]
            else
                mask_fast = false(size(bg_fast,1), size(bg_fast,2), nZ);
                for zz = 1:nZ
                    mask_fast(:,:,zz) = any(mask(:,:,zz,:), 4);
                end
            end

            SCM_gui( ...
                PSC_fast, bg_fast, TR, par, baseline, ...
                I, I_interp, fps, maxFPS, ...
                mask_fast, maskIsInclude, ...
                applyRejection, QC, fileLabel );

            statusLine = 'SCM opened (full slice-wise mask transferred).';
            render();

        catch ME
            statusLine = ['SCM failed: ' ME.message];
            render();
        end
    end

% =========================================================
%  SAVE MP4 VIDEO
% =========================================================
    function saveVideo(~, ~)
        [f, p] = uiputfile('*.mp4','Save fUSI video');
        if isequal(f,0), return; end

        exportFPS = fps;

        vid = VideoWriter(fullfile(p,f), 'MPEG-4');
        vid.FrameRate = exportFPS;
        vid.Quality   = 95;
        open(vid);

        txt = text(ax, 0.01, 0.99, '', ...
            'Units','normalized', ...
            'Color','w', ...
            'FontName','Courier', ...
            'FontSize',16, ...
            'FontWeight','bold', ...
            'VerticalAlignment','top', ...
            'BackgroundColor','k', ...
            'Margin',4);

        oldVolume  = volume;
        oldPlaying = playing;
        playing    = false;

        for v = 1:nVols
            volume          = v;
            volSlider.Value = v;

            frame = (v - 1) * par.interpol + 1;
            frame = max(1, min(nFrames, round(frame)));

            render();

            t = (v - 1) * TR;
            txt.String = sprintf('t = %.1f / %.1f s   |   Volume %d / %d', ...
                                 t, Tmax, v, nVols);

            drawnow;
            writeVideo(vid, getframe(ax));
        end

        delete(txt);
        close(vid);

        volume  = oldVolume;
        playing = oldPlaying;
        render();

        statusLine = 'Video saved (image-only).';
    end

% =========================================================
%  SAVE MASK (4D)
% =========================================================
    function saveMaskMat(~, ~)
        [f,p] = uiputfile('*.mat','Save mask');
        if isequal(f,0), return; end

        out = struct();
        out.mask          = mask;
        out.maskIsInclude = maskIsInclude;

        out.metadata = struct();
        out.metadata.TR      = TR;
        out.metadata.nVols   = nVols;
        out.metadata.nZ      = nZ;
        out.metadata.created = datestr(now);
        out.metadata.script  = mfilename;
        out.metadata.note    = 'Slice-wise mask saved from fUSI video GUI';

        save(fullfile(p,f),'-struct','out','-v7.3');

        statusLine = 'Mask saved (.mat)';
        render();
    end

% =========================================================
%  SAVE INTERPOLATED DATA
% =========================================================
    function saveInterpolatedMat(~, ~)
        [f,p] = uiputfile('*.mat','Save interpolated fUSI data');
        if isequal(f,0), return; end

        out.I = I_interp;

        metadata = struct();
        metadata.TR     = TR;
        metadata.time   = (0:size(I_interp,3)-1) * TR;
        metadata.system = 'fUSI';

        try
            metadata.frameRateQC = struct( ...
                'applied',      applyRejection, ...
                'outliers',     QC.outliers, ...
                'thresholdLow', QC.thresholdLow, ...
                'thresholdHigh',QC.thresholdHigh, ...
                'sigma',        QC.sigma, ...
                'rejPct',       QC.rejPct);
        catch
        end

        metadata.baseline = baseline;

        metadata.processing = struct( ...
            'script', mfilename, ...
            'date',   datestr(now), ...
            'note',   'Interpolated for video after frame-rate QC (display-safe)');

        out.metadata = metadata;

        save(fullfile(p,f),'-struct','out','-v7.3');

        statusLine = 'Interpolated MAT file saved (with metadata).';
        render();
    end

% =========================================================
%  HELP DIALOG
% =========================================================
    function showHelpDialog(~, ~)
        hf = figure( ...
            'Name','Help — fUSI Auto Mask v3 (Slice-wise Edition)', ...
            'Color',[0.06 0.06 0.06], ...
            'MenuBar','none', ...
            'ToolBar','none', ...
            'NumberTitle','off', ...
            'Position',[250 120 920 740], ...
            'Resize','on', ...
            'WindowStyle','modal');

        colTitle  = [0.98 0.98 0.98];
        colNormal = [0.90 0.90 0.90];

        titleTxt = uicontrol('Style','text','Parent',hf, ...
            'Units','pixels', ...
            'Position',[20 690 880 36], ...
            'String','fUSI VIDEO GUI — HELP', ...
            'ForegroundColor',colTitle, ...
            'BackgroundColor',[0.06 0.06 0.06], ...
            'FontName','Arial', ...
            'FontSize',20, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');

        msg = [ ...
            'ALPHA MODULATION (IDENTICAL to SCM_gui)\n' ...
            '============================================================\n' ...
            'Threshold hides low |PSC| by alpha.\n' ...
            'Alpha (%) is the global overlay strength.\n' ...
            'If alpha modulation is ON, alpha ramps 0..1 between Mod Min and Mod Max.\n\n' ...
            'VIEW MODES\n' ...
            '============================================================\n' ...
            '- VIEW: FULL   -> PSC shown everywhere (threshold still applies)\n' ...
            '- VIEW: MASKED -> PSC shown only inside mask (Include/Exclude)\n\n' ...
            'SHORTCUTS\n' ...
            '============================================================\n' ...
            '- M  -> Automatic mask (robust)\n' ...
            '- F  -> Fill region at cursor\n' ...
            '- Scroll wheel -> change slice\n' ...
            ];

        txtBox = uicontrol('Style','edit','Parent',hf, ...
            'Units','pixels', ...
            'Position',[20 90 880 580], ...
            'String',sprintf(msg), ...
            'ForegroundColor',colNormal, ...
            'BackgroundColor',[0.12 0.12 0.12], ...
            'FontName','Arial', ...
            'FontSize',14, ...
            'HorizontalAlignment','left', ...
            'Max',2,'Min',0, ...
            'Enable','inactive');

        closeBtn2 = uicontrol('Style','pushbutton','Parent',hf, ...
            'Units','pixels', ...
            'Position',[770 25 130 42], ...
            'String','Close', ...
            'FontName','Arial', ...
            'FontSize',13, ...
            'FontWeight','bold', ...
            'ForegroundColor','w', ...
            'BackgroundColor',[0.75 0.15 0.15], ...
            'Callback',@(~,~) close(hf));

        hf.SizeChangedFcn = @onResize;
        onResize();

        function onResize(~,~)
            p = hf.Position;
            W = p(3); H = p(4);
            set(titleTxt,'Position',[20 H-50 W-40 36]);
            set(txtBox,  'Position',[20 90 W-40 H-150]);
            set(closeBtn2,'Position',[W-150 25 130 42]);
        end
    end

% =========================================================
%  UI CALLBACKS: EDITOR / VIEW / MASK
% =========================================================
    function toggleEditor(src, ~)
        editorMode = logical(src.Value);
        src.String = tern(editorMode, 'Editor ON', 'Editor OFF');
        statusLine = '';
        render();
    end

    function toggleViewMasked(src, ~)
        viewMaskedOnly = logical(src.Value);
        src.String = tern(viewMaskedOnly, 'VIEW: MASKED', 'VIEW: FULL');
        statusLine = '';
        render();
    end

    function setIncludeExclude(src, ~)
        maskIsInclude = (src.Value == 1);
        statusLine = '';
        render();
    end

    function toggleApplyAll(src, ~)
        applyToAllFrames = logical(src.Value);
        src.String = tern(applyToAllFrames, 'AUTO: ALL', 'AUTO: FRAME');
        statusLine = '';
        render();
    end

    function applyMaskToAllFrames(~, ~)
        refMask = mask(:,:,sliceIdx,volume);
        if ~any(refMask(:))
            statusLine = 'Current slice mask is empty — nothing to apply.';
            render();
            return;
        end

        for v = 1:nVols
            mask(:,:,sliceIdx,v) = refMask;
        end

        statusLine = sprintf('Mask of slice %d applied to all volumes.', sliceIdx);
        render();
    end

    function autoMaskButton(~, ~)
        autoMask();
    end

    function setBrush(v)
        brushRadius = max(1, round(v));
        brushVal.String = sprintf('Radius: %d px', brushRadius);
    end

    function pickColor(~, ~)
        c = uisetcolor(maskColor, 'Pick mask overlay color');
        if numel(c) == 3
            maskColor = c;
        end
        render();
    end

    function clearMaskAll(~, ~)
        mask(:) = false;
        statusLine = 'Mask cleared.';
        render();
    end

    function setOverlayAlpha(v)
        maskAlpha = max(0, min(1, v));
        statusLine = sprintf('Mask alpha = %.2f', maskAlpha);
        render();
    end

    function setMaskThreshold(v)
        maskThreshold = v;
        statusLine = sprintf('PSC threshold = %.2f', maskThreshold);
        render();
    end

% =========================================================
%  SCM-IDENTICAL ALPHA MOD UI CALLBACKS
% =========================================================
    function toggleAlphaMod(~,~)
        alphaModEnable = logical(get(alphaEnableChk,'Value'));
        alphaModToggledUI();
        render();
    end

    function alphaModToggledUI()
        if alphaModEnable
            set(editModMin,'Enable','on','ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10]);
            set(editModMax,'Enable','on','ForegroundColor','w','BackgroundColor',[0.10 0.10 0.10]);
        else
            set(editModMin,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
            set(editModMax,'Enable','off','ForegroundColor',[0.55 0.55 0.55],'BackgroundColor',[0.16 0.16 0.16]);
        end
    end

    function setAlphaPctBox(src,~)
        v = str2double(src.String);
        if ~isfinite(v), v = alphaPct; end
        v = max(0, min(100, v));
        alphaPct = v;
        set(src,'String',sprintf('%.0f',alphaPct));
        render();
    end

    function setModMinBox(src,~)
        v = str2double(src.String);
        if ~isfinite(v), v = modMinAbs; end
        modMinAbs = v;
        if modMaxAbs < modMinAbs
            modMaxAbs = modMinAbs;
            set(editModMax,'String',sprintf('%.3g',modMaxAbs));
        end
        set(src,'String',sprintf('%.3g',modMinAbs));
        render();
    end

    function setModMaxBox(src,~)
        v = str2double(src.String);
        if ~isfinite(v), v = modMaxAbs; end
        modMaxAbs = v;
        if modMaxAbs < modMinAbs
            modMinAbs = modMaxAbs;
            set(editModMin,'String',sprintf('%.3g',modMinAbs));
        end
        set(src,'String',sprintf('%.3g',modMaxAbs));
        render();
    end

% =========================================================
%  MOUSE PAINTING — SLICE-BY-SLICE
% =========================================================
    function mouseDown(~, ~)
        if playing, return; end
        if ~editorMode, return; end

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

    function mouseUp(~, ~)
        mouseIsDown = false;
        paintMode   = '';
    end

    function mouseMoveVideo(~,~)
        if ~ishandle(ax), return; end

        cp = get(ax,'CurrentPoint');
        x = cp(1,1);
        y2 = cp(1,2);

        if x>=1 && x<=nx && y2>=1 && y2<=nz
            lastMouseXY = [x y2];
        end

        if ~mouseIsDown || ~editorMode || playing, return; end
        applyPaintAtCursor();
    end

    function applyPaintAtCursor()
        cp = get(ax,'CurrentPoint');
        x  = round(cp(1,1));
        y2 = round(cp(1,2));

        if x<1 || x>nx || y2<1 || y2>nz, return; end

        brush = makeBrushMask(x, y2, brushRadius, nz, nx);

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
%  KEYBOARD SHORTCUTS
% =========================================================
    function keyPressHandler(~, evt)
        if ~isfield(evt,'Key'), return; end
        key = evt.Key;

        switch lower(key)
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

    function fillRegion(~, ~)
        if any(isnan(lastMouseXY))
            statusLine = 'Move mouse over image, then press F.';
            render();
            return;
        end
        fillAtXY(lastMouseXY(1), lastMouseXY(2));
    end

    function fillAtXY(xf, yf)
        x0 = round(xf);
        y0 = round(yf);
        if x0<1 || x0>nx || y0<1 || y0>nz
            statusLine = 'Fill aborted: cursor outside image.';
            render();
            return;
        end
        fillRegionAtSeed(x0, y0);
    end

% =========================================================
%  AUTO MASK + REGION GROWING — SLICE WISE (AUTO = robust A)
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
        thr  = medv + 1.2*madv;

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
            statusLine = sprintf('AUTO MASK (A) applied to ALL volumes (slice %d).', sliceIdx);
        else
            mask(:,:,sliceIdx,volume) = autoM;
            statusLine = sprintf('AUTO MASK (A) applied to volume %d (slice %d).', volume, sliceIdx);
        end

        render();
    end

    function fillRegionAtSeed(x0, y0)
        if ndPSC == 4
            P = squeeze(max(abs(PSC(:,:,sliceIdx,:)),[],4));
        elseif ndPSC == 3
            P = max(abs(PSC),[],3);
        else
            P = abs(PSC);
        end

        P(~isfinite(P)) = 0;
        P = mat2gray(P);

        centerVal = P(y0,x0);
        if ~isfinite(centerVal)
            statusLine = 'Fill aborted: seed outside PSC.';
            render();
            return;
        end

        W = max(1, round(fillWindowR));
        y1 = max(1, y0-W);  y2 = min(nz, y0+W);
        x1 = max(1, x0-W);  x2 = min(nx, x0+W);

        block = P(y1:y2, x1:x2);
        sigmaLocal = std(block(:));
        if ~isfinite(sigmaLocal) || sigmaLocal == 0
            sigmaLocal = 0.05;
        end

        thrDiff = fillSigmaFactor * sigmaLocal;
        diffMat = abs(P - centerVal);

        region = diffMat <= thrDiff;

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

        statusLine = sprintf('Fill region grown at (%d,%d).', x0, y0);
        render();
    end

% =========================================================
%  SMALL HELPERS
% =========================================================
    function bg2 = getBg2DForSlice(bgIn, z, nZ_) %#ok<INUSD>
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
            error('bg must be 2D/3D/4D');
        end
    end

    function B = makeBrushMask(x0, y0, r, ny, nx_)
        [X,Y] = meshgrid(1:nx_, 1:ny);
        B = (X-x0).^2 + (Y-y0).^2 <= r^2;
    end

    function s = sliceString(k, nZ_)
        if nZ_ > 1
            s = sprintf('Slice: %d / %d', k, nZ_);
        else
            s = '';
        end
    end

    function out = tern(cond, a, b)
        if cond, out = a; else, out = b; end
    end

% =========================================================
%  CLOSE HANDLER
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
%  COLORBAR RANGE DIALOG (PSC ONLY)
% =========================================================
    function setColorbarRange(~,~)

        answer = inputdlg( ...
            {'Colorbar LOWER limit (%):','Colorbar UPPER limit (%):'}, ...
            'Set Signal Change Range', ...
            1, ...
            {num2str(par.previewCaxis(1)), num2str(par.previewCaxis(2))});

        if isempty(answer)
            return;
        end

        low  = str2double(answer{1});
        high = str2double(answer{2});

        if isnan(low) || isnan(high) || high <= low
            errordlg('Invalid colorbar limits.');
            return;
        end

        par.previewCaxis = [low high];

        caxis(ax, par.previewCaxis);
        if ishandle(cbar)
            set(cbar,'Limits',par.previewCaxis);
        end

        % Update threshold slider range too
        try
            set(maskThreshSlider,'Min',low,'Max',high);
        catch
        end

        render();
    end

end % END OF MAIN FUNCTION