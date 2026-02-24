function fig = FunctionalConnectivity(dataIn, saveRoot, tag, opts)
% FunctionalConnectivity — fUSI Studio module (Seed-based voxelwise FC)
% MATLAB 2017b compatible, dark theme
%
% Computes:
%   r-map  : Pearson correlation(seed_ts, voxel_ts)
%   z-map  : Fisher z = atanh(r)  (with safe clipping)
%
% Inputs:
%   dataIn : struct with .I (and optional .TR, .mask, .anat) OR numeric array
%            I dims: [Y X T] or [Y X Z T]
%   saveRoot: root folder to save QC outputs
%   tag     : string tag for filenames
%   opts (optional):
%       .mask        : [Y X Z] logical/numeric mask (optional)
%       .anat        : [Y X Z] anatomy underlay (optional)
%       .datasetName : label for titles (optional)
%       .seedRadius  : default radius in voxels (default 1)
%       .chunkVox    : voxel chunk size for computation (default 6000)
%       .useSliceOnly: default compute mode (false = whole volume)
%       .logFcn      : @(msg) ... (optional)
%       .debugRethrow: if true, rethrow errors (default false)

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4, opts = struct(); end

% ---- normalize opts (CRITICAL: avoids "Struct contents reference..." ) ----
opts = normalizeOpts(opts);

% ---- extract I/TR/mask/anat ----
if isstruct(dataIn)
    if ~isfield(dataIn,'I') || isempty(dataIn.I)
        error('FunctionalConnectivity: input struct must contain non-empty .I');
    end
    I  = dataIn.I;

    TR = 1;
    if isfield(dataIn,'TR') && ~isempty(dataIn.TR)
        TR = double(dataIn.TR);
    end
    if (~isfield(opts,'mask') || isempty(opts.mask)) && isfield(dataIn,'mask') && ~isempty(dataIn.mask)
        opts.mask = dataIn.mask;
    end
    if (~isfield(opts,'anat') || isempty(opts.anat)) && isfield(dataIn,'anat') && ~isempty(dataIn.anat)
        opts.anat = dataIn.anat;
    end
else
    I = dataIn;
    TR = 1;
end
if ~isscalar(TR) || ~isfinite(TR) || TR <= 0, TR = 1; end

% ---- force 4D [Y X Z T] ----
sz = size(I);
if ndims(I) == 3
    Y = sz(1); X = sz(2); T = sz(3);
    Z = 1;
    I4 = reshape(single(I), Y, X, 1, T);
elseif ndims(I) == 4
    Y = sz(1); X = sz(2); Z = sz(3); T = sz(4);
    I4 = single(I);
else
    error('Data must be [Y X T] or [Y X Z T].');
end

% ---- mask ----
mask = [];
if isfield(opts,'mask') && ~isempty(opts.mask)
    m = opts.mask;
    try
        if ndims(m) == 2 && Z == 1 && size(m,1)==Y && size(m,2)==X
            mask = reshape(logical(m), Y, X, 1);
        elseif ndims(m) == 3 && all(size(m)==[Y X Z])
            mask = logical(m);
        else
            warnlog(opts, '[FC] Provided mask has mismatched size -> ignoring.');
        end
    catch
        warnlog(opts, '[FC] Provided mask could not be interpreted -> ignoring.');
        mask = [];
    end
end

% If no mask: build a conservative auto-mask from mean image
if isempty(mask)
    mimg = mean(I4,4);
    thr  = prctile(mimg(:), 25); % conservative
    mask = (mimg > thr);
    warnlog(opts, '[FC] No mask provided -> using auto mask from mean image (p25 threshold).');
end

% ---- anatomy underlay ----
anat = [];
if isfield(opts,'anat') && ~isempty(opts.anat)
    a = opts.anat;
    try
        if ndims(a)==2 && Z==1 && size(a,1)==Y && size(a,2)==X
            anat = reshape(single(a), Y, X, 1);
        elseif ndims(a)==3 && all(size(a)==[Y X Z])
            anat = single(a);
        else
            warnlog(opts, '[FC] Provided anatomy has mismatched size -> ignoring.');
        end
    catch
        warnlog(opts, '[FC] Provided anatomy could not be interpreted -> ignoring.');
        anat = [];
    end
end

% ---- precompute underlays from data ----
meanImg   = squeeze(mean(I4,4));          % [Y X Z]
medianImg = squeeze(median(I4,4));        % [Y X Z]

% ---- GUI state ----
st = struct();
st.I4 = I4; st.TR = TR;
st.Y=Y; st.X=X; st.Z=Z; st.T=T;
st.mask = mask;
st.anat = anat;
st.meanImg = meanImg;
st.medianImg = medianImg;

st.slice = max(1, round(Z/2));
st.seedY = round(Y/2);
st.seedX = round(X/2);
st.seedR = max(0, round(opts.seedRadius));
st.useSliceOnly = logical(opts.useSliceOnly);

st.lastR = [];  % [Y X Z]
st.lastZ = [];  % [Y X Z]
st.lastSeedTS = [];
st.lastSeedInfo = struct();

st.mapMode = 'z';         % 'r' or 'z'
st.underlayMode = 'mean'; % 'mean' 'median' 'anat'
st.absThr = 0.2;          % threshold on |r| (visual)
st.alpha  = 0.70;         % overlay alpha

% output folder
qcDir = fullfile(saveRoot, 'Connectivity', 'fc_QC');
if ~exist(qcDir,'dir'), mkdir(qcDir); end
st.qcDir = qcDir;
st.tag = tag;
st.datasetName = opts.datasetName;

% ---- figure / theme ----
bgFig = [0.06 0.06 0.07];
bgAx  = [0.09 0.09 0.10];
fg    = [0.90 0.90 0.92];
fgDim = [0.70 0.70 0.74];
accent= [0.20 0.65 1.00];
warnC = [1.00 0.35 0.35];

fig = figure('Name','fUSI Studio — Functional Connectivity (Seed-based)', ...
    'Color',bgFig,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Position',[120 80 1550 900]);
try, set(fig,'Renderer','opengl'); catch, end

% layout
leftX=0.02; leftY=0.05; leftW=0.30; leftH=0.92;
midX =0.34; midY =0.05; midW =0.64; midH =0.92;

panelCtrl = uipanel('Parent',fig,'Units','normalized','Position',[leftX leftY leftW leftH], ...
    'BackgroundColor',[0.08 0.08 0.09],'ForegroundColor',fg, ...
    'Title','Controls','FontWeight','bold','FontSize',12);

panelView = uipanel('Parent',fig,'Units','normalized','Position',[midX midY midW midH], ...
    'BackgroundColor',[0.08 0.08 0.09],'ForegroundColor',fg, ...
    'Title','Maps & Timecourses','FontWeight','bold','FontSize',12);

% --- controls: underlay ---
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.92 0.88 0.05],'String','Underlay', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg, ...
    'FontWeight','bold','HorizontalAlignment','left','FontSize',11);

ddUnder = uicontrol('Parent',panelCtrl,'Style','popupmenu','Units','normalized', ...
    'Position',[0.06 0.885 0.88 0.045], ...
    'String',underlayList(anat), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onUnderlayChanged);

% --- slice ---
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.83 0.88 0.05],'String','Slice (Z)', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg, ...
    'FontWeight','bold','HorizontalAlignment','left','FontSize',11);

slZ = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.06 0.80 0.88 0.03], 'Min',1,'Max',max(1,Z), ...
    'Value',st.slice, 'SliderStep',sliderStep(Z), ...
    'BackgroundColor',[0.12 0.12 0.13], 'Callback',@onSliceChanged);

edZ = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.06 0.765 0.25 0.04], ...
    'String',sprintf('%d',st.slice), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onSliceEdit);

% --- seed radius ---
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.36 0.765 0.40 0.04],'String','Seed radius (vox)', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);

edR = uicontrol('Parent',panelCtrl,'Style','edit','Units','normalized', ...
    'Position',[0.78 0.765 0.16 0.04], ...
    'String',sprintf('%d',st.seedR), ...
    'BackgroundColor',[0.16 0.16 0.18],'ForegroundColor',fg, ...
    'Callback',@onRadiusEdit);

% --- compute mode ---
cbSliceOnly = uicontrol('Parent',panelCtrl,'Style','checkbox','Units','normalized', ...
    'Position',[0.06 0.72 0.88 0.04], ...
    'String','Compute only on current slice (faster)', ...
    'Value',st.useSliceOnly, ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'), 'ForegroundColor',fgDim, ...
    'Callback',@onComputeModeChanged);

% --- map mode ---
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.665 0.88 0.04],'String','Map type', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg, ...
    'FontWeight','bold','HorizontalAlignment','left','FontSize',11);

bgMap = uibuttongroup('Parent',panelCtrl,'Units','normalized','Position',[0.06 0.61 0.88 0.055], ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'), ...
    'SelectionChangedFcn',@onMapModeChanged);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.02 0.15 0.48 0.75],'String','Fisher z','Value',1, ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg);
uicontrol(bgMap,'Style','radiobutton','Units','normalized', ...
    'Position',[0.52 0.15 0.48 0.75],'String','Pearson r','Value',0, ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg);

% --- threshold + alpha ---
uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.555 0.88 0.04],'String','Overlay threshold |r|', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fg, ...
    'FontWeight','bold','HorizontalAlignment','left','FontSize',11);

slThr = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.06 0.525 0.88 0.03], 'Min',0,'Max',0.99, ...
    'Value',st.absThr,'SliderStep',[0.01 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], 'Callback',@onThrChanged);

txtThr = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.495 0.88 0.03], ...
    'String',sprintf('|r| ? %.2f',st.absThr), ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',accent, ...
    'HorizontalAlignment','left','FontWeight','bold');

uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.455 0.88 0.04],'String','Overlay alpha', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'),'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left','FontSize',10);

slAlpha = uicontrol('Parent',panelCtrl,'Style','slider','Units','normalized', ...
    'Position',[0.06 0.43 0.88 0.03], 'Min',0,'Max',1, ...
    'Value',st.alpha,'SliderStep',[0.02 0.10], ...
    'BackgroundColor',[0.12 0.12 0.13], 'Callback',@onAlphaChanged);

% --- info text ---
txtSeed = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.37 0.88 0.05], ...
    'String',seedString(st), ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'), ...
    'ForegroundColor',fg, 'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

txtStatus = uicontrol('Parent',panelCtrl,'Style','text','Units','normalized', ...
    'Position',[0.06 0.30 0.88 0.07], ...
    'String','Click on the image to set seed, then press Compute.', ...
    'BackgroundColor',get(panelCtrl,'BackgroundColor'), ...
    'ForegroundColor',fgDim, 'HorizontalAlignment','left', ...
    'FontSize',10);

% --- buttons ---
uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.06 0.22 0.88 0.07], 'String','Compute FC (seed-based)', ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[0.10 0.45 0.85],'ForegroundColor','w', ...
    'Callback',@onCompute);

uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.06 0.13 0.88 0.07], 'String','Save outputs (MAT + PNG)', ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[0.20 0.45 0.25],'ForegroundColor','w', ...
    'Callback',@onSave);

uicontrol('Parent',panelCtrl,'Style','pushbutton','Units','normalized', ...
    'Position',[0.06 0.04 0.88 0.07], 'String','Close', ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[0.65 0.20 0.20],'ForegroundColor','w', ...
    'Callback',@(~,~)delete(fig));

% --- views: axes ---
axMap = axes('Parent',panelView,'Units','normalized','Position',[0.05 0.22 0.56 0.74], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
axis(axMap,'image'); axis(axMap,'off');
title(axMap,'Seed-based FC map','Color',fg,'FontWeight','bold');

axTS = axes('Parent',panelView,'Units','normalized','Position',[0.66 0.62 0.30 0.34], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axTS,'on');
title(axTS,'Seed timecourse','Color',fg,'FontWeight','bold');

axHist = axes('Parent',panelView,'Units','normalized','Position',[0.66 0.22 0.30 0.34], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
grid(axHist,'on');
title(axHist,'Correlation distribution (masked voxels)','Color',fg,'FontWeight','bold');

% draw initial underlay
st.hUnder = imagesc(axMap, getUnderlaySlice(st)); colormap(axMap, gray(256));
hold(axMap,'on');
st.hOver  = imagesc(axMap, nan(Y,X,3)); %#ok<NASGU>
set(st.hOver,'AlphaData',0); % hidden until compute
st.hCross1 = line(axMap, [1 X],[st.seedY st.seedY],'Color',warnC,'LineWidth',1.0);
st.hCross2 = line(axMap, [st.seedX st.seedX],[1 Y],'Color',warnC,'LineWidth',1.0);
hold(axMap,'off');

% make clicks set seed
set(st.hUnder,'ButtonDownFcn',@onMapClick);
set(axMap,'ButtonDownFcn',@onMapClick);

% diverging colormap for FC overlay
st.fcCmap = blueWhiteRed(256);

refreshMapTitle();
refreshOverlay(); % shows nothing until computed

guidata(fig, st);

% ========================= callbacks =========================

    function onUnderlayChanged(~,~)
        st = guidata(fig);
        lst = get(ddUnder,'String');
        val = get(ddUnder,'Value');
        choice = lower(strtrim(lst{val}));

        if ~isempty(strfind(choice,'mean')),   st.underlayMode = 'mean'; end %#ok<STREMP>
        if ~isempty(strfind(choice,'median')), st.underlayMode = 'median'; end
        if ~isempty(strfind(choice,'anat')),   st.underlayMode = 'anat'; end

        guidata(fig, st);
        redrawUnderlay();
    end

    function onSliceChanged(~,~)
        st = guidata(fig);
        st.slice = clamp(round(get(slZ,'Value')), 1, st.Z);
        set(edZ,'String',sprintf('%d',st.slice));
        guidata(fig, st);
        redrawUnderlay();
        refreshOverlay();
    end

    function onSliceEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edZ,'String'));
        if ~isfinite(v), v = st.slice; end
        st.slice = clamp(round(v),1,st.Z);
        set(edZ,'String',sprintf('%d',st.slice));
        set(slZ,'Value',st.slice);
        guidata(fig, st);
        redrawUnderlay();
        refreshOverlay();
    end

    function onRadiusEdit(~,~)
        st = guidata(fig);
        v = str2double(get(edR,'String'));
        if ~isfinite(v), v = st.seedR; end
        st.seedR = max(0, round(v));
        set(edR,'String',sprintf('%d',st.seedR));
        set(txtSeed,'String',seedString(st));
        guidata(fig, st);
    end

    function onComputeModeChanged(~,~)
        st = guidata(fig);
        st.useSliceOnly = logical(get(cbSliceOnly,'Value'));
        guidata(fig, st);
    end

    function onMapModeChanged(~,evt)
        st = guidata(fig);
        if strcmpi(evt.NewValue.String,'Fisher z')
            st.mapMode = 'z';
        else
            st.mapMode = 'r';
        end
        guidata(fig, st);
        refreshMapTitle();
        refreshOverlay();
    end

    function onThrChanged(~,~)
        st = guidata(fig);
        st.absThr = double(get(slThr,'Value'));
        set(txtThr,'String',sprintf('|r| ? %.2f',st.absThr));
        guidata(fig, st);
        refreshOverlay();
    end

    function onAlphaChanged(~,~)
        st = guidata(fig);
        st.alpha = double(get(slAlpha,'Value'));
        guidata(fig, st);
        refreshOverlay();
    end

    function onMapClick(~,~)
        st = guidata(fig);
        cp = get(axMap,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x<1 || x>st.X || y<1 || y>st.Y, return; end
        st.seedX = x; st.seedY = y;
        set(st.hCross1,'YData',[y y]);
        set(st.hCross2,'XData',[x x]);
        set(txtSeed,'String',seedString(st));
        guidata(fig, st);
    end

    function onCompute(~,~)
        st = guidata(fig);
        set(txtStatus,'String','Computing FC...','ForegroundColor',accent);
        drawnow;

        try
            [rMap, zMap, seedTS, seedInfo] = compute_seed_fc(st, opts);

            st.lastR = rMap;
            st.lastZ = zMap;
            st.lastSeedTS = seedTS;
            st.lastSeedInfo = seedInfo;
            guidata(fig, st);

            plotSeedTS(st);
            plotHist(st);
            refreshOverlay();

            set(txtStatus,'String','Done. Switch r/z, threshold, alpha, slice.', ...
                'ForegroundColor',fgDim);

            warnlog(opts, sprintf('[FC] OK: seed (x=%d,y=%d,z=%d), R=%d, mode=%s', ...
                st.seedX, st.seedY, st.slice, st.seedR, ternary(st.useSliceOnly,'slice','volume')));

        catch ME
            % ALWAYS show stack trace + line numbers
            set(txtStatus,'String',['ERROR: ' ME.message], 'ForegroundColor',warnC);
            warnlog(opts, ['[FC] ERROR: ' ME.message]);
            logStack(opts, ME);

            if isfield(opts,'debugRethrow') && opts.debugRethrow
                rethrow(ME);
            end
        end
    end

    function onSave(~,~)
        st = guidata(fig);
        if isempty(st.lastR)
            set(txtStatus,'String','Nothing to save yet: compute FC first.', 'ForegroundColor',warnC);
            return;
        end

        try
            out = struct();
            out.rMap = st.lastR;
            out.zMap = st.lastZ;
            out.seedTS = st.lastSeedTS;
            out.seedInfo = st.lastSeedInfo;
            out.TR = st.TR;
            out.mask = st.mask;
            out.underlayMode = st.underlayMode;
            out.mapMode = st.mapMode;
            out.absThr = st.absThr;
            out.alpha = st.alpha;

            matFile = fullfile(st.qcDir, sprintf('FC_seed_%s.mat', st.tag));
            save(matFile, 'out', '-v7.3');

            pngFile = fullfile(st.qcDir, sprintf('FC_seedMap_%s.png', st.tag));
            saveMapPNG(fig, axMap, pngFile);

            set(txtStatus,'String',sprintf('Saved: %s  +  %s', shortName(matFile), shortName(pngFile)), ...
                'ForegroundColor',fgDim);

            warnlog(opts, ['[FC] Saved outputs: ' st.qcDir]);

        catch ME
            set(txtStatus,'String',['SAVE ERROR: ' ME.message], 'ForegroundColor',warnC);
            warnlog(opts, ['[FC] SAVE ERROR: ' ME.message]);
            logStack(opts, ME);
        end
    end

% ========================= helpers =========================

    function redrawUnderlay()
        st = guidata(fig);
        set(st.hUnder,'CData', getUnderlaySlice(st));
        refreshOverlay();
        drawnow limitrate;
    end

    function refreshMapTitle()
        st = guidata(fig);
        nm = st.datasetName;
        if isempty(nm), nm = 'Active dataset'; end
        if strcmpi(st.mapMode,'z')
            tt = sprintf('Seed-based FC (Fisher z) — %s', nm);
        else
            tt = sprintf('Seed-based FC (Pearson r) — %s', nm);
        end
        title(axMap, tt, 'Color', fg, 'FontWeight','bold');
    end

    function refreshOverlay()
        st = guidata(fig);
        if isempty(st.lastR)
            set(st.hOver,'CData', nan(st.Y, st.X, 3));
            set(st.hOver,'AlphaData', 0);
            return;
        end

        rS = st.lastR(:,:,st.slice);
        zS = st.lastZ(:,:,st.slice);

        vis = abs(rS) >= st.absThr;
        vis = vis & logical(st.mask(:,:,st.slice));

        if strcmpi(st.mapMode,'z')
            M = zS;
            clim = autoClim(M(vis), 2.5);
        else
            M = rS;
            clim = [-1 1];
        end

        rgb = mapToRGB(M, st.fcCmap, clim);
        set(st.hOver,'CData', rgb);
        set(st.hOver,'AlphaData', st.alpha * double(vis));

        colormap(axMap, gray(256));
        drawnow limitrate;
    end

    function plotSeedTS(st)
        cla(axTS);
        ts = double(st.lastSeedTS(:));
        tmin = ((0:numel(ts)-1)*st.TR)/60;
        plot(axTS, tmin, ts, 'LineWidth', 1.4);
        grid(axTS,'on');
        set(axTS,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        xlabel(axTS,'Time (min)','Color',fgDim);
        ylabel(axTS,'a.u.','Color',fgDim);
        title(axTS,'Seed timecourse','Color',fg,'FontWeight','bold');
        drawnow limitrate;
    end

    function plotHist(st)
        cla(axHist);
        r = st.lastR(:);
        m = st.mask(:);
        r = double(r(m & isfinite(r)));
        if isempty(r)
            text(axHist, 0.1, 0.5, 'No data', 'Color',fg);
            return;
        end
        histogram(axHist, r, 60);
        grid(axHist,'on');
        set(axHist,'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
        xlabel(axHist,'Pearson r','Color',fgDim);
        ylabel(axHist,'Count','Color',fgDim);
        title(axHist,'Correlation distribution','Color',fg,'FontWeight','bold');
        drawnow limitrate;
    end

end

% ======================== core computation =========================
function [rMap, zMap, seedTS, seedInfo] = compute_seed_fc(st, opts)
% opts can be ANYTHING; normalize again for safety
opts = normalizeOpts(opts);

Y=st.Y; X=st.X; Z=st.Z; T=st.T;
I4 = st.I4;
mask = st.mask;

% seed voxel indices in current slice only
seedMask2D = diskMask(Y, X, st.seedY, st.seedX, st.seedR);
seedMask3D = false(Y,X,Z);
seedMask3D(:,:,st.slice) = seedMask2D;
seedMask3D = seedMask3D & mask;

seedV = find(seedMask3D(:));
if isempty(seedV)
    seedMask3D = false(Y,X,Z);
    seedMask3D(st.seedY, st.seedX, st.slice) = true;
    seedV = find(seedMask3D(:));
    warnlog(opts,'[FC] Seed region empty under mask -> using single clicked voxel.');
end

V = Y*X*Z;
Xvt = reshape(I4, [V, T]); % [V x T] single

seedTS = mean(double(Xvt(seedV,:)), 1);
seedTS = seedTS(:);

s = double(seedTS - mean(seedTS));
sNorm = sqrt(sum(s.^2));
if sNorm <= 0 || ~isfinite(sNorm)
    error('Seed timecourse has zero variance.');
end

r = nan(V,1,'single');

% compute voxel set
if st.useSliceOnly
    voxMask = false(Y,X,Z);
    voxMask(:,:,st.slice) = mask(:,:,st.slice);
else
    voxMask = mask;
end
voxIdx = find(voxMask(:));
if isempty(voxIdx)
    error('Mask is empty (no voxels selected for FC).');
end

chunkVox = 6000;
if isfield(opts,'chunkVox') && ~isempty(opts.chunkVox) && isfinite(opts.chunkVox)
    chunkVox = double(opts.chunkVox);
end
chunk = max(1000, round(chunkVox));

sSingle = single(s);

for i0 = 1:chunk:numel(voxIdx)
    i1 = min(numel(voxIdx), i0+chunk-1);
    id = voxIdx(i0:i1);

    Xc = Xvt(id,:);
    Xm = mean(Xc,2);
    Xc = bsxfun(@minus, Xc, Xm);

    num = Xc * sSingle;
    den = sqrt(sum(Xc.^2,2)) * single(sNorm);

    rr = num ./ max(single(eps), den);
    rr(~isfinite(rr)) = 0;
    rr = max(-1, min(1, rr));
    r(id) = rr;
end

rMap = reshape(r, [Y X Z]);

rc = double(rMap);
rc = min(0.999999, max(-0.999999, rc));
zMap = single(atanh(rc));

seedInfo = struct();
seedInfo.seedX = st.seedX;
seedInfo.seedY = st.seedY;
seedInfo.seedZ = st.slice;
seedInfo.seedRadius = st.seedR;
seedInfo.useSliceOnly = st.useSliceOnly;
seedInfo.nSeedVox = nnz(seedMask3D);
seedInfo.nVoxComputed = numel(voxIdx);
end

% ======================== utilities =========================
function opts = normalizeOpts(opts)
% Guarantee struct + defaults (prevents your exact error)
if nargin < 1 || isempty(opts) || ~isstruct(opts)
    opts = struct();
end
if ~isfield(opts,'seedRadius')   || isempty(opts.seedRadius),   opts.seedRadius = 1; end
if ~isfield(opts,'chunkVox')     || isempty(opts.chunkVox),     opts.chunkVox   = 6000; end
if ~isfield(opts,'useSliceOnly') || isempty(opts.useSliceOnly), opts.useSliceOnly = false; end
if ~isfield(opts,'datasetName')  || isempty(opts.datasetName),  opts.datasetName = ''; end
if ~isfield(opts,'logFcn'),       opts.logFcn = []; end
if ~isfield(opts,'debugRethrow'), opts.debugRethrow = false; end
end

function logStack(opts, ME)
% Print full stack with file + line
try
    if isstruct(ME) || isa(ME,'MException')
        st = ME.stack;
        for k = 1:numel(st)
            warnlog(opts, sprintf('[FC]   at %s (line %d)  %s', st(k).name, st(k).line, st(k).file));
        end
    end
catch
end
end

function s = seedString(st)
s = sprintf('Seed: x=%d, y=%d, z=%d  |  radius=%d', st.seedX, st.seedY, st.slice, st.seedR);
end

function lst = underlayList(anat)
lst = {'Mean (data)','Median (data)'};
if ~isempty(anat), lst{end+1} = 'Anat (provided)'; end
end

function img = getUnderlaySlice(st)
switch lower(st.underlayMode)
    case 'anat'
        if ~isempty(st.anat)
            img = st.anat(:,:,st.slice);
        else
            img = st.meanImg(:,:,st.slice);
        end
    case 'median'
        img = st.medianImg(:,:,st.slice);
    otherwise
        img = st.meanImg(:,:,st.slice);
end
img = single(img);

mn = prctile(img(:), 1);
mx = prctile(img(:), 99);
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    mn = min(img(:)); mx = max(img(:));
    if mx <= mn, mx = mn + 1; end
end
img = (img - mn) / (mx - mn);
img = max(0, min(1, img));
end

function m = diskMask(Y,X,cy,cx,r)
m = false(Y,X);
if r <= 0
    if cy>=1 && cy<=Y && cx>=1 && cx<=X
        m(cy,cx) = true;
    end
    return;
end
[xx,yy] = meshgrid(1:X,1:Y);
m = ( (xx - cx).^2 + (yy - cy).^2 ) <= r^2;
end

function clim = autoClim(vals, fallback)
vals = vals(isfinite(vals));
if isempty(vals)
    clim = [-fallback fallback];
    return;
end
p = prctile(abs(vals), 99);
if ~isfinite(p) || p <= 0, p = fallback; end
clim = [-p p];
end

function rgb = mapToRGB(M, cmap, clim)
M = double(M);
cmin = clim(1); cmax = clim(2);
if ~isfinite(cmin) || ~isfinite(cmax) || cmax <= cmin
    cmin = min(M(:)); cmax = max(M(:));
    if cmax <= cmin, cmax = cmin + 1; end
end
u = (M - cmin) / (cmax - cmin);
u = max(0, min(1, u));
idx = 1 + floor(u*(size(cmap,1)-1));
idx(~isfinite(idx)) = 1;
idx = max(1, min(size(cmap,1), idx));

rgb = zeros([size(M,1) size(M,2) 3], 'single');
for k = 1:3
    tmp = cmap(idx, k);
    rgb(:,:,k) = reshape(single(tmp), size(M,1), size(M,2));
end
end

function cmap = blueWhiteRed(n)
if nargin<1, n=256; end
n1 = floor(n/2);
n2 = n - n1;
b = [0.00 0.25 0.95];
w = [1 1 1];
r = [0.95 0.20 0.20];

c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];
cmap = [c1; c2];
end

function st = sliderStep(Z)
if Z <= 1
    st = [1 1];
else
    st = [1/(Z-1) min(10/(Z-1),1)];
end
end

function v = clamp(v, lo, hi)
v = max(lo, min(hi, v));
end

function warnlog(opts, msg)
try
    if ~isempty(opts) && isstruct(opts) && isfield(opts,'logFcn') && ~isempty(opts.logFcn) ...
            && isa(opts.logFcn,'function_handle')
        opts.logFcn(msg);
    end
catch
end
end

function s = shortName(p)
[~,n,e] = fileparts(p);
s = [n e];
end

function saveMapPNG(fig, ax, outFile)
tmp = figure('Visible','off');
ax2 = copyobj(ax, tmp);
set(ax2,'Units','normalized','Position',[0.05 0.05 0.90 0.90]);
set(tmp,'Color',get(fig,'Color'),'Position',[100 100 900 900]);
saveas(tmp, outFile);
close(tmp);
end

function out = ternary(cond, a, b)
if cond, out=a; else, out=b; end
end