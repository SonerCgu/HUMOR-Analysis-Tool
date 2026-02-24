function fig = play_fusi_video_final( ...
    I, I_interp, PSC, bg, par, fps, maxFPS, TR, Tmax, baseline, ...
    loadedMask, loadedMaskIsInclude, nVols, applyRejection, QC, fileLabel, sliceIdx)

disp('fps ='); disp(fps);
disp('maxFPS ='); disp(maxFPS);

% =========================================================
%  fUSI Video GUI — MATRIX PROBE + 2D SUPPORT
% Ensure previewCaxis exists (robust symmetric PSC scaling)
% =========================================================
if ~isfield(par,'previewCaxis') || isempty(par.previewCaxis)

    tmp = PSC(:);
    tmp = tmp(isfinite(tmp));

    if isempty(tmp)
        par.previewCaxis = [-5 5];
    else
        % Percentile window scaling (better for Gabriel)
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
    case 4         % [Y X Z T]
        [nz, nx, nZ, nFrames] = size(PSC);
    case 3         % [Y X T]  (2D probe ? treat as Z=1)
        [nz, nx, nFrames] = size(PSC);
        nZ = 1;
    case 2         % [Y X]   (rare; treat as Z=1, T=1)
        [nz, nx] = size(PSC);
        nZ      = 1;
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
% ===== Studio-safe close handler =====
set(fig,'CloseRequestFcn',@onCloseVideo);

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

% --- Colormaps ---
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
y0   = 800;   % FPS row anchor

% -------- FPS --------
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y0 100 rowH], ...
    'String','FPS', ...
    'ForegroundColor','w', 'BackgroundColor','k', ...
    'FontName',uiFontName, 'FontSize',uiFontSize, ...
    'HorizontalAlignment','right');

fpsValue = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+105 y0 80 rowH], ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName, 'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

fpsSlider = uicontrol('Style','slider', ...
    'Min',1,'Max',maxFPS,'Value',fps, ...
    'Units','pixels', ...
    'Position',[rightX y0-rowH 360 rowH], ...
    'Callback',@(s,~) setFPS(s.Value));

% -------- VOLUME --------
y1 = y0 - (rowH*2 + gap);

uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX y1 100 rowH], ...
    'String','Volume', ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','right');

volValue = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX+105 y1 120 rowH], ...
    'ForegroundColor','w','BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

volSlider = uicontrol('Style','slider', ...
    'Min',1,'Max',nVols,'Value',1, ...
    'Units','pixels', ...
    'Position',[rightX y1-rowH 360 rowH], ...
    'Callback',@(s,~) scrubVol(round(s.Value)));

% Colorbar (left, thin)
cbar = colorbar('Position',[0.06 0.18 0.014 0.58]);
colormap(cbar,'hot');
cbar.Color = 'w';
cbar.FontSize = 13;
cbar.Label.String = 'Percent Signal Change (%)';
cbar.Label.FontSize = 14;
cbar.Label.Color = 'w';
% ---- Bind colorbar to PSC units, not normalized [0–1] ----
caxis(ax, par.previewCaxis);     % PSC range
set(cbar, 'Limits', par.previewCaxis);


% Button BELOW colorbar (bottom-left corner)
uicontrol('Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.045 0.10 0.06 0.035], ... % adjust if needed
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

%  Accepts: [Y X], [Y X Z], [Y X Z T]
%  Normalizes internally to [Y X Z T]
% =========================================================

maskIsInclude = true;
statusLine    = '';

if exist('loadedMask','var') && ~isempty(loadedMask)

    loadedMask = logical(loadedMask);

    switch ndims(loadedMask)

        case 2
            % -------- 2D mask [Y X] --------
            mask(:,:,sliceIdx,:) = repmat(loadedMask,[1 1 1 nVols]);
            statusLine = '2D mask expanded to all frames (current slice).';

        case 3
            % -------- 3D mask [Y X Z] --------
            for z = 1:min(nZ,size(loadedMask,3))
                mask(:,:,z,:) = repmat(loadedMask(:,:,z),[1 1 1 nVols]);
            end
            statusLine = '3D mask expanded to all frames.';

        case 4
            % -------- 4D mask [Y X Z T] --------
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

applyToAllFrames = true;  % If true ? apply painting to all volumes
                          % ALWAYS slice-specific now

% Editor state
editorMode     = false;
viewMaskedOnly = false;

% Brush settings
brushRadius   = 12;
maskAlpha     = 0.35;
maskColor     = [1 1 1];
maskThreshold = 0.25;


% AUTO MASK mode  (1=Off, 2=A, 3=B)
strictMode     = 2;
percentileKeep = 90;
percentileMin  = 60;
percentileMax  = 99;

% Fill parameters
fillWindowR     = 18;
fillSigmaFactor = 1.8;
fillMaxPixels   = 300000;

% Mouse / keyboard
mouseIsDown = false;
paintMode   = '';
lastMouseXY = [NaN NaN];

% ===================== MASK EDITOR UI =====================
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 680 360 20], ...
    'String','Mask / Auto Tools', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');


maskPanelTopY = 680;   % anchor for all mask-related controls

editBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX 650 360 28], ...
    'String','Editor OFF', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleEditor);

viewBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX 615 175 28], ...
    'String','VIEW: FULL', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleViewMasked);

posView = get(viewBtn,'Position');
includeDrop = uicontrol('Style','popupmenu','Units','pixels', ...
    'Position',[posView(1)+posView(3)+10 posView(2) posView(3) posView(4)], ...
    'String',{'Include','Exclude'}, ...
    'Value',1, ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setIncludeExclude);

applyAllBtn = uicontrol('Style','togglebutton','Units','pixels', ...
    'Position',[rightX 580 175 28], ...
    'String','AUTO: ALL', ...
    'Value',1, ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@toggleApplyAll);

autoBtn = uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+185 580 175 28], ...
    'String','AUTO MASK (M)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'FontWeight','bold', ...
    'Callback',@autoMaskButton);

% Brush size
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 555 120 18], ...
    'String','Brush size', ...
    'ForegroundColor',[0.8 0.8 0.8], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

brushSlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX 535 360 18], ...
    'Min',1,'Max',25,'Value',brushRadius, ...
    'Callback',@(s,~) setBrush(round(s.Value)));

brushVal = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 515 360 16], ...
    'String',sprintf('Radius: %d px',brushRadius), ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

% Fill / Color / Clear
uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX 480 110 28], ...
    'String','Color...', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@pickColor);

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+120 480 110 28], ...
    'String','Fill (F)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@fillRegion);

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX+240 480 120 28], ...
    'String','Clear mask', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@clearMaskAll);

% Strict selector for AUTO MASK
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 450 360 18], ...
    'String','Auto method (A/B)', ...
    'ForegroundColor',[0.8 0.8 0.8], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

strictDrop = uicontrol('Style','popupmenu','Units','pixels', ...
    'Position',[rightX 425 360 26], ...
    'String',{'Off','A: robust','B: percentile'}, ...
    'Value',strictMode, ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@setStrictMode);

percSlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX 395 360 16], ...
    'Min',percentileMin,'Max',percentileMax,'Value',percentileKeep, ...
    'Callback',@setPercentileKeep);

percVal = uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX 375 360 18], ...
    'String',sprintf('Percentile: %.0f (lower = more voxels)',percentileKeep), ...
    'ForegroundColor',[0.7 0.7 0.7], ...
    'BackgroundColor','k', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'HorizontalAlignment','left');

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX 330 360 32], ...
    'String','Save Mask (.mat)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@saveMaskMat);

uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX 290 360 32], ...
    'String','Save Interpolated Data (.mat)', ...
    'FontName',uiFontName,'FontSize',uiFontSize, ...
    'Callback',@saveInterpolatedMat);


% ============================================================
%  MASK OVERLAY & THRESHOLD BLOCK (ONLY THESE ARE UPDATED)
%  -- Positioned safely BELOW the Save buttons
% ============================================================

% ============================================================
%  BUTTON GEOMETRY — MUST BE DEFINED FIRST
% ============================================================
btnW  = 120;
btnH  = 42;
gapX  = 18;
gapY  = 18;

row1Y = 40;                         % bottom row
row2Y = row1Y + btnH + gapY;        % row above


% ============================================================
%  MASK OVERLAY + THRESHOLD + APPLY MASK (COMPACT LAYOUT)
% ============================================================

% Get Y-position of Save Interpolated button
saveInterpPos = get(findobj(fig,'String','Save Interpolated Data (.mat)'),'Position');
baseY = saveInterpPos(2);

% Compact spacing
overlayY = baseY - 55;      % was -70 ? now tighter
gapSmall = 34;              % gap between sliders
btnGap   = 90;              % distance to apply-mask button

labelW = 220;
sliderW = 350;

% ---------- Mask Overlay Alpha ----------
uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX overlayY+18 labelW 18], ...
    'String','Mask Intensity Overlay', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k');

overlaySlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX overlayY sliderW 18], ...
    'Min',0,'Max',1,'Value',maskAlpha, ...
    'Callback',@(s,~) setOverlayAlpha(s.Value));



% ---------- Mask Threshold ----------
thY = overlayY - gapSmall;

uicontrol('Style','text','Units','pixels', ...
    'Position',[rightX thY+18 labelW 18], ...
    'String','Signal Change Threshold (%)', ...
    'ForegroundColor',[0.9 0.9 0.9], ...
    'BackgroundColor','k');

% Use real PSC distribution
tmpPSC = PSC(:);
tmpPSC = tmpPSC(isfinite(tmpPSC));

if isempty(tmpPSC)
    thrMin = -5;
    thrMax = 5;
else
    thrMin = prctile(tmpPSC,1);
    thrMax = prctile(tmpPSC,99);
end

maskThreshold = 0;   % start at 0% PSC

maskThreshSlider = uicontrol('Style','slider','Units','pixels', ...
    'Position',[rightX thY sliderW 18], ...
    'Min',thrMin, ...
    'Max',thrMax, ...
    'Value',maskThreshold, ...
    'Callback',@(s,~) setMaskThreshold(s.Value));



% ---------- Apply Slice Mask ? ALL Volumes ----------
applyMaskY = thY - btnH - 14;   % 14 px padding below threshold slider

applyAllMaskBtn = uicontrol('Style','pushbutton','Units','pixels', ...
    'Position',[rightX applyMaskY sliderW btnH], ...
    'String','Apply Mask to all Volumes', ...
    'FontWeight','bold', ...
    'ForegroundColor','w', ...
    'BackgroundColor',[0.20 0.45 0.25], ...
    'Callback',@applyMaskToAllFrames);

% ---------------- CALLBACKS ----------------
function setOverlayAlpha(v)
    maskAlpha = v;
    statusLine = sprintf('Mask alpha = %.2f', v);
    render();
end

function setMaskThreshold(v)
    maskThreshold = v;
    statusLine = sprintf('Mask threshold = %.2f', v);
    render();
end

% ---------------------------------------------------------
%  FIGURE CALLBACKS (mouse / keyboard / scroll)
% ---------------------------------------------------------
set(fig,'WindowButtonDownFcn',@mouseDown);
set(fig,'WindowButtonUpFcn',@mouseUp);
set(fig,'WindowButtonMotionFcn',@mouseMoveVideo);
set(fig,'KeyPressFcn',@keyPressHandler);
set(fig,'WindowScrollWheelFcn',@mouseScrollSlice);





% ============================================================
%  BOTTOM PANEL — NOW row1Y/row2Y EXIST
% ============================================================

% -------- ROW 2 (HELP / CLOSE / OPEN SCM)
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


% -------- ROW 1 (PLAY / REPLAY / SAVE MP4)
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




    function mouseScrollSlice(~, evt)
        if nZ <= 1 || playing
            return;
        end

        % Only scroll when mouse is over image axis
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

        render();   % redraw SAME time / volume
    end

% ================= INITIAL RENDER + MAIN LOOP =================
render();
% =========================================================
%  PLAYBACK TIMER (Studio-safe replacement for while loop)
% =========================================================
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

playTimer = timer( ...
    'ExecutionMode','fixedSpacing', ...
    'Period',1/max(fps,0.1), ...
    'TimerFcn',@timerTick);

% =========================================================
%  RENDER FUNCTION — FINAL, FULLY CORRECTED VERSION
% =========================================================
function render()


    % -----------------------------------------------------
    % 1. SLICE SAFETY
    % -----------------------------------------------------
    sliceIdx = max(1, min(nZ, sliceIdx));

    % -----------------------------------------------------
    % 2. BACKGROUND 2D SLICE
    % -----------------------------------------------------
    bg2 = getBg2DForSlice(bgFull, sliceIdx, nZ);
    bg2(~isfinite(bg2)) = 0;

    mn = min(bg2(:));
    mx = max(bg2(:));
    if mx > mn
        bgNorm = (bg2 - mn) ./ (mx - mn);
    else
        bgNorm = zeros(size(bg2));
    end
    bgRGB = ind2rgb(uint8(bgNorm * 127), gray(128));   % [Y X 3]

    outRGB = bgRGB;   % safe default
    % -----------------------------------------------------
    % 3. FRAME SAFETY
    % -----------------------------------------------------
    if frame < 1 || frame > nFrames
        img.CData = bgRGB;
        return;
    end
    curVol = volume;

    % -----------------------------------------------------
    % 4. PSC SLICE 2D
    % -----------------------------------------------------
    if ndPSC == 4
        A = squeeze(PSC(:,:,sliceIdx, frame));
    else
        A = PSC(:,:,frame);
    end
    A(~isfinite(A)) = 0;

    % PSC scaling
 cax = par.previewCaxis;
if numel(cax) ~= 2 || diff(cax) <= 0
    cax = [-10 10];
    par.previewCaxis = cax;
end

% ---- update colorbar in PSC units ----
if ishandle(cbar)
    set(cbar, 'Limits', cax);
end


    A_scaled = (A - cax(1)) ./ (cax(2) - cax(1) + eps);
    A_scaled = max(0, min(1, A_scaled));  % clamp

    pscRGB = ind2rgb(uint8(A_scaled * (Nc-1)), mapA);   % [Y X 3]

    % -----------------------------------------------------
    % 5. MASK EXTRACTION — ALWAYS 2D
    % -----------------------------------------------------
    if editorMode
    alphaUse = max(0.6, maskAlpha);   % stronger during editing
else
    alphaUse = maskAlpha;
end

    
    if ndims(mask) == 4
        M = squeeze(mask(:,:,sliceIdx, curVol));
    elseif ndims(mask) == 3
        M = squeeze(mask(:,:,sliceIdx));
    else
        M = mask;
    end

    M = logical(M);
    M = M(1:size(bg2,1), 1:size(bg2,2));  % ensure size match


% -----------------------------------------------------
% IMPORTANT:
% - While EDITING ? show RAW mask (no threshold)
% - While VIEWING ? apply threshold
% -----------------------------------------------------
if ~editorMode
    M = M & (A >= maskThreshold);
end

   % -----------------------------------------------------
% 6. BASE PSC OVERLAY
% -----------------------------------------------------
alphaPSC = 0.70;
baseRGB = (1-alphaPSC).*bgRGB + alphaPSC.*pscRGB;

% -----------------------------------------------------
% 7. FINAL VIEW LOGIC (RESTORED ORIGINAL BEHAVIOUR)
% -----------------------------------------------------

if viewMaskedOnly
    % ===== MASKED MODE =====
    
    show = M;
    if ~maskIsInclude
        show = ~M;
    end
    
    show3 = repmat(show,[1 1 3]);
    
    outRGB = bgRGB;                % background everywhere
    outRGB(show3) = baseRGB(show3);  % PSC only inside mask
    
else
    % ===== FULL MODE =====
    
    outRGB = baseRGB;   % show PSC everywhere
    
    % Editor overlay (ONLY when editing)
 outRGB = baseRGB;

if any(M(:))

    maskRGB = cat(3, ...
        ones(size(bg2))*maskColor(1), ...
        ones(size(bg2))*maskColor(2), ...
        ones(size(bg2))*maskColor(3));

    M3 = repmat(M,[1 1 3]);

    outRGB = outRGB .* (1 - maskAlpha .* M3) + ...
             maskRGB .* (maskAlpha .* M3);
end

end

    % -----------------------------------------------------
    % 8. DISPLAY
    % -----------------------------------------------------
    img.CData = outRGB;

    % -----------------------------------------------------
    % 9. INFO STRING
    % -----------------------------------------------------
    t = (volume - 1) * TR;

    em = tern(editorMode,'ON','OFF');
    vm = tern(viewMaskedOnly,'MASKED','FULL');
    ms = tern(maskIsInclude,'Include','Exclude');
    methodLabel = autoMethodLabel();

    extra = '';
    if ~isempty(statusLine)
        extra = [' | ' statusLine];
    end

    
    if isfield(baseline,'mode')
    modeStr = baseline.mode;
else
    modeStr = 'sec';
end

    info.String = sprintf( ...
        ['t = %.1f / %.1f s   |   Vol %d / %d   |   View: %s (%s)\n' ...
         'Baseline: %g–%g %s   |   Editor: %s   |   AUTO: %s%s'], ...
        t, Tmax, volume, nVols, vm, ms, ...
        baseline.start, baseline.end, modeStr, ...
        em, methodLabel, extra);

    fpsValue.String = sprintf('%d FPS', fps);
    volValue.String = sprintf('%d / %d', volume, nVols);

    txtSliceAx.String = sliceString(sliceIdx, nZ);

end

% =========================================================
%  PLAYBACK / SCRUB / OPEN SCM / SAVE VIDEO
% ========================================================
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

    if isvalid(playTimer)
        stop(playTimer);
        set(playTimer,'Period',1/fps);
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

        if strcmp(playTimer.Running,'off')
            set(playTimer,'Period',1/max(fps,0.1));
            start(playTimer);
        end
    else
        src.String = 'Play';

        if strcmp(playTimer.Running,'on')
            stop(playTimer);
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

    stop(playTimer);
    set(playTimer,'Period',1/max(fps,0.1));
    start(playTimer);

    render();
end


% =========================================================
%  OPEN SCM GUI — FIXED & COMPLETE
%  - Transfers FULL slice-wise mask to SCM
%  - Collapses time, preserves Z
% =========================================================
function openSCM(~,~)
    try
        % -------------------------------------------------
        % Pass full PSC + background (SCM keeps slice slider)
        % -------------------------------------------------
        PSC_fast = PSC;
        bg_fast  = bgFull;

        % -------------------------------------------------
        % Build SCM-compatible mask
        %   Video GUI mask: [Y X Z T]
        %   SCM expects:
        %     - 2D probe    -> [Y X]
        %     - Matrix probe -> [Y X Z]
        % -------------------------------------------------
        if nZ == 1
            % ---------- 2D probe ----------
            % Collapse time only
            mask_fast = any(mask(:,:,1,:), 4);     % [Y X]

        else
            % ---------- Matrix probe ----------
            % Collapse time for EACH slice
            mask_fast = false(size(bg_fast));      % [Y X Z]

            for z = 1:nZ
                mask_fast(:,:,z) = any(mask(:,:,z,:), 4);
            end
        end

        % -------------------------------------------------
        % Launch SCM
        % -------------------------------------------------
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

        % Temporary text overlay on AXES
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
        out.mask          = mask;           % now 4D mask (Y x X x Z x T)
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
        if exist('S','var') && isfield(S,'metadata') && isstruct(S.metadata)
            metadata = S.metadata;
        end

        metadata.TR     = TR;
        metadata.time   = (0:size(I_interp,3)-1) * TR;
        metadata.system = 'fUSI';

        if exist('S','var')
            if isfield(S,'imageDim'),  metadata.imageDim  = S.imageDim;  end
            if isfield(S,'imageSize'), metadata.imageSize = S.imageSize; end
            if isfield(S,'voxelSize'), metadata.voxelSize = S.voxelSize; end
            if isfield(S,'imageType'), metadata.imageType = S.imageType; end
            if isfield(S,'origin'),    metadata.origin    = S.origin;    end
            if isfield(S,'t0'),        metadata.t0        = S.t0;        end
        end

        metadata.frameRateQC = struct( ...
            'applied',      applyRejection, ...
            'outliers',     QC.outliers, ...
            'thresholdLow', QC.thresholdLow, ...
            'thresholdHigh',QC.thresholdHigh, ...
            'sigma',        QC.sigma, ...
            'rejPct',       QC.rejPct);

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
            'SLICE-WISE MASKING\n' ...
            '============================================================\n' ...
            'Each slice has its own mask (Y x X x Z x T).\n' ...
            'Painting, fill, auto mask operate ONLY on current slice.\n\n' ...
            ...
            'RECOMMENDED WORKFLOW\n' ...
            '============================================================\n' ...
            '1) Select AUTO MASK method (A or B)\n' ...
            '2) Press M or click AUTO MASK\n' ...
            '3) Use FILL (F) to expand coherent regions\n' ...
            '4) Refine mask manually with paint tools\n' ...
            '5) Switch VIEW: MASKED for final visualization\n\n' ...
            ...
            'VIEW MODES\n' ...
            '============================================================\n' ...
            '- VIEW: FULL   -> show PSC everywhere\n' ...
            '- VIEW: MASKED -> show PSC only inside mask\n' ...
            '- Include/Exclude flips mask interpretation\n' ...
            '- Contrast remains identical in all modes\n\n' ...
            ...
            'KEYBOARD SHORTCUTS\n' ...
            '============================================================\n' ...
            '- M  -> Automatic mask (A / B)\n' ...
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

        closeBtn = uicontrol('Style','pushbutton','Parent',hf, ...
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
            set(closeBtn,'Position',[W-150 25 130 42]);
        end
    end
% =========================================================
%  UI CALLBACKS: EDITOR / VIEW / AUTO FLAGS
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
            for z = 1:nZ
                mask(:,:,z,v) = refMask;
            end
        end

        statusLine = sprintf('Mask of slice %d was applied', sliceIdx);
        render();
    end

    function autoMaskButton(~, ~)
        autoMask();   % defined below
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

    function setStrictMode(src, ~)
        strictMode = src.Value;
        statusLine = '';
        render();
    end

    function setPercentileKeep(src, ~)
        percentileKeep = round(src.Value);
        percVal.String = sprintf('Percentile: %.0f (lower = more voxels)', percentileKeep);
        statusLine = '';
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
        y = cp(1,2);

        % store cursor for Fill region
        if x>=1 && x<=nx && y>=1 && y<=nz
            lastMouseXY = [x y];
        end

        if ~mouseIsDown || ~editorMode || playing, return; end

        applyPaintAtCursor();
    end

    function applyPaintAtCursor()
        cp = get(ax,'CurrentPoint');
        x  = round(cp(1,1));
        y  = round(cp(1,2));

        if x<1 || x>nx || y<1 || y>nz, return; end

        brush = makeBrushMask(x, y, brushRadius, nz, nx);

        if strcmp(paintMode,'add')
            if applyToAllFrames
                mask(:,:,sliceIdx,:) = mask(:,:,sliceIdx,:) | repmat(brush,[1 1 1 nVols]);
            else
                mask(:,:,sliceIdx,volume) = mask(:,:,sliceIdx,volume) | brush;
            end
        else % remove
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
%  AUTO MASK + REGION GROWING — SLICE WISE
% =========================================================
    function autoMask()
        if strictMode == 1
            statusLine = 'AUTO MASK: Off (no changes).';
            render();
            return;
        end

        % PSC magnitude for this slice
        if ndPSC == 4
            P = squeeze(max(abs(PSC(:,:,sliceIdx,:)),[],4));
        else
            P = max(abs(PSC),[],3);
        end

        P(~isfinite(P)) = 0;
        vec = P(:);

        switch strictMode
            case 2
                medv = median(vec);
                madv = median(abs(vec - medv)) + eps;
                thr  = medv + 1.2*madv;
            case 3
                thr = prctile(vec, percentileKeep);
        end

        autoM = P >= thr;

        % clean
        se = strel('disk', max(1,round(fillWindowR/3)));
        autoM = imopen(autoM,se);
        autoM = imclose(autoM,se);
        autoM = imfill(autoM,'holes');
        autoM = bwareaopen(autoM, 20);

        if nnz(autoM) > fillMaxPixels
            autoM = bwareafilt(autoM,1);
        end

        if applyToAllFrames
            mask(:,:,sliceIdx,:) = repmat(autoM,[1 1 1 nVols]);
            statusLine = sprintf('AUTO MASK (%s) applied to ALL volumes (slice %d).', autoMethodLabel(), sliceIdx);
        else
            mask(:,:,sliceIdx,volume) = autoM;
            statusLine = sprintf('AUTO MASK (%s) applied to volume %d (slice %d).', autoMethodLabel(), volume, sliceIdx);
        end

        render();
    end

    function fillRegionAtSeed(x0, y0)
        if ndPSC == 4
            P = squeeze(max(abs(PSC(:,:,sliceIdx,:)),[],4));
        else
            P = max(abs(PSC),[],3);
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
        region = bwareaopen(region, 5);
        region = imfill(region,'holes');

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
    function bg2 = getBg2DForSlice(bgIn, z, nZ_)
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

    function str = autoMethodLabel()
        switch strictMode
            case 2, str = 'A';
            case 3, str = 'B';
            otherwise, str = 'Off';
        end
    end

    function out = tern(cond, a, b)
        if cond, out = a; else, out = b; end
    end

function onCloseVideo(~,~)

    % Stop timer safely
    try
        if exist('playTimer','var') && isa(playTimer,'timer')
            stop(playTimer);
            delete(playTimer);
        end
    catch
    end

    % Push mask back safely (if it exists)
    try
        if exist('mask','var')
            setappdata(fig,'updatedMask',mask);
        end

        if exist('maskIsInclude','var')
            setappdata(fig,'updatedMaskIsInclude',maskIsInclude);
        end
    catch
    end

    delete(fig);
end
function setColorbarRange(~,~)

    answer = inputdlg( ...
        {'Colorbar LOWER limit (%):','Colorbar UPPER limit (%):'}, ...
        'Set PSC Color Range', ...
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

    % Update axis scaling
    caxis(ax, par.previewCaxis);
    set(cbar,'Limits',par.previewCaxis);

    % Also update threshold slider range
    set(maskThreshSlider,'Min',low,'Max',high);

    render();
end
end % END OF MAIN FUNCTION