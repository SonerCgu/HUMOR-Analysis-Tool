function [newData, stats] = ica_denoise(dataIn, saveRoot, tag, opts)
% ICA_DENOISE - interactive ICA removal (MATLAB 2017b + 2023b)
% ==========================================================
% Similar spirit to PCA_DENOISE, but uses:
%   PCA reduction -> whitening -> symmetric FastICA
%
% Outputs:
%   newData.I : denoised data
%   stats     : selection, energy proxy, QC files, convergence info

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4, opts = struct(); end

% ---- defaults ----
if ~isfield(opts,'nCompMax'),         opts.nCompMax = 30; end
if ~isfield(opts,'maxDisplayPoints'), opts.maxDisplayPoints = 2000; end
if ~isfield(opts,'chunkT'),           opts.chunkT = 250; end
if ~isfield(opts,'centerMode'),       opts.centerMode = 'voxel'; end
if ~isfield(opts,'verbose'),          opts.verbose = true; end
if ~isfield(opts,'icaMaxIter'),       opts.icaMaxIter = 400; end
if ~isfield(opts,'icaTol'),           opts.icaTol = 1e-5; end
if ~isfield(opts,'onApply'),          opts.onApply = []; end
if ~isfield(opts,'onCancel'),         opts.onCancel = []; end
if ~isfield(opts,'logFcn'),           opts.logFcn = []; end

% ---- extract data + TR ----
isStruct = isstruct(dataIn);
if isStruct
    if ~isfield(dataIn,'I'), error('ica_denoise: input struct must contain .I'); end
    I  = dataIn.I;
    TR = 1;
    if isfield(dataIn,'TR'), TR = double(dataIn.TR); end
    newData = dataIn;
else
    I = dataIn;
    TR = 1;
    newData = struct('I',I);
end
if ~isscalar(TR) || ~isfinite(TR) || TR <= 0, TR = 1; end

% ---- force 4D [Y X Z T] ----
sz = size(I);
if ndims(I) == 3
    Y = sz(1); X = sz(2); T = sz(3);
    Z = 1;
    I4 = reshape(I, Y, X, 1, T);
elseif ndims(I) == 4
    Y = sz(1); X = sz(2); Z = sz(3); T = sz(4);
    I4 = I;
else
    error('Data must be 3D [Y X T] or 4D [Y X Z T].');
end
V = Y * X * Z;

Xvt = reshape(single(I4), [V, T]);
gmean_before = mean(Xvt, 1);

% ---- center ----
switch lower(opts.centerMode)
    case 'global'
        mu = mean(Xvt(:));
        Xc = Xvt - single(mu);
        muVec = [];
    otherwise
        muVec = mean(Xvt, 2);
        Xc = bsxfun(@minus, Xvt, muVec);
        mu = [];
end

% ---- choose K ----
K = min([opts.nCompMax, T-1, 100]);
if K < 2
    stats = emptyStats(tag);
    stats.method = 'ICA (none)';
    newData.I = I;
    return;
end

if opts.verbose
    fprintf('[ICA] V=%d, T=%d, PCA reduction to K=%d...\n', V, T, K);
end
if ~isempty(opts.logFcn) && isa(opts.logFcn,'function_handle')
    try, opts.logFcn(sprintf('[ICA] PCA reduction to K=%d...', K)); catch, end
end

% ==========================================================
% PCA reduction / whitening basis
% Xc approx W * S * U'
% ==========================================================
Xtv = double(Xc');  % [T x V]
useFallback = false;

try
    [U,S,W] = svds(Xtv, K);
catch
    useFallback = true;
end

if useFallback
    if opts.verbose, fprintf('[ICA] svds failed -> eigs fallback\n'); end
    Ct = Xtv * Xtv';
    Ct = (Ct + Ct') * 0.5;
    [U,L] = eigs(Ct, K, 'largestreal');
    s = sqrt(max(diag(L),0));
    S = diag(s);
    W = (Xtv' * U);
    for i = 1:K
        if s(i) > 0
            W(:,i) = W(:,i) ./ s(i);
        end
    end
end

sing = diag(S);
[sing, ord] = sort(sing(:), 'descend');
U = U(:, ord);
W = W(:, ord);

% ==========================================================
% FastICA on whitened reduced data Z = U'
% ==========================================================
Zwhite = U';  % [K x T]

if opts.verbose
    fprintf('[ICA] Running symmetric FastICA...\n');
end
if ~isempty(opts.logFcn) && isa(opts.logFcn,'function_handle')
    try, opts.logFcn('[ICA] Running symmetric FastICA...'); catch, end
end

[B, Sica, fastStats] = fastica_symm(Zwhite, opts.icaMaxIter, opts.icaTol);

% U' = Ared * Sica, because Sica = B * U'
Ared = B';
Avox = double(W) * diag(double(sing)) * Ared;   % [V x K]
TC   = double(Sica);                            % [K x T]

% ---- energy proxy (since ICA components are not variance-ranked) ----
proxy = zeros(1, K);
for k = 1:K
    proxy(k) = sum(Avox(:,k).^2) * sum(TC(k,:).^2);
end
if sum(proxy) > 0
    proxy = proxy / sum(proxy);
else
    proxy(:) = 1 / K;
end

% sort ICs by proxy for cleaner GUI ordering
[proxy, ord2] = sort(proxy(:)', 'descend');
TC = TC(ord2, :);
Avox = Avox(:, ord2);

% ==========================================================
% GUI selection
% ==========================================================
[selected, applyFlag] = ica_selector_gui_grid(TC', proxy, Avox, [Y X Z], TR, opts.maxDisplayPoints);

stats = emptyStats(tag);
stats.nComponents = K;
stats.energyProxyPerComponent = proxy(:)';
stats.selectedComponents = [];
stats.percentEnergyRemoved = 0;
stats.applied = false;
stats.method = 'ICA (cancelled)';
stats.qcGridFiles = {};
stats.nIter = fastStats.nIter;
stats.converged = fastStats.converged;

if ~applyFlag
    if ~isempty(opts.onCancel) && isa(opts.onCancel,'function_handle')
        try, opts.onCancel(); catch, end
    end
    newData.I = I;
    return;
end

selected = unique(selected(:)');
selected = selected(selected >= 1 & selected <= K);

if ~isempty(opts.onApply) && isa(opts.onApply,'function_handle')
    try, opts.onApply(selected); catch, end
end

stats.selectedComponents = selected;
stats.percentEnergyRemoved = 100 * sum(proxy(selected));
stats.applied = true;
stats.method = 'ICA denoise (FastICA + grid select)';

if isempty(selected)
    if ~isempty(opts.logFcn) && isa(opts.logFcn,'function_handle')
        try, opts.logFcn('ICA applied: no ICs selected (no change).'); catch, end
    end
    newData.I = I;
    return;
end

% ==========================================================
% Remove selected ICs
% Xc_clean = Xc - Avox_sel * TC_sel
% ==========================================================
AvoxSel = Avox(:, selected);
TCsel   = TC(selected, :);

Xclean = Xc;
chunkT = max(50, round(opts.chunkT));

if opts.verbose
    fprintf('[ICA] Removing %d ICs (%.2f%% energy proxy)...\n', numel(selected), stats.percentEnergyRemoved);
end

for t0 = 1:chunkT:T
    t1 = min(T, t0 + chunkT - 1);
    recon = AvoxSel * TCsel(:, t0:t1);
    Xclean(:, t0:t1) = Xclean(:, t0:t1) - single(recon);
end

% ---- add mean back ----
switch lower(opts.centerMode)
    case 'global'
        Xout = Xclean + single(mu);
    otherwise
        Xout = bsxfun(@plus, Xclean, muVec);
end

gmean_after = mean(Xout, 1);

Iout4 = reshape(Xout, [Y, X, Z, T]);
if Z == 1
    Iout = reshape(Iout4, [Y, X, T]);
else
    Iout = Iout4;
end

newData.I = Iout;
newData.preprocessing = 'ICA denoise (FastICA)';

% ==========================================================
% QC save
% ==========================================================
stats.qcFile = '';
stats.qcGlobalMeanFile = '';
stats.qcMeanImageFile = '';
stats.qcGridFiles = {};

try
    qcDir = fullfile(saveRoot, 'Preprocessing', 'ica_QC');
    if ~exist(qcDir,'dir'), mkdir(qcDir); end

    qc1 = fullfile(qcDir, sprintf('ICA_selected_%s.png', tag));
    make_qc_plot_selected_ica(proxy, selected, qc1);
    stats.qcFile = qc1;

    qc2 = fullfile(qcDir, sprintf('ICA_globalMean_before_after_%s.png', tag));
    make_qc_globalmean_plot_ica(gmean_before, gmean_after, TR, qc2);
    stats.qcGlobalMeanFile = qc2;

    qc3 = fullfile(qcDir, sprintf('ICA_meanImage_before_after_%s.png', tag));
    make_qc_meanimage_plot(single(I4), single(Iout4), qc3);
    stats.qcMeanImageFile = qc3;

    gridFiles = make_qc_grid_dark_exact_ica(TC', proxy, TR, selected, qcDir, tag);
    stats.qcGridFiles = gridFiles;

catch ME
    if opts.verbose
        fprintf('[ICA] QC save warning: %s\n', ME.message);
    end
end

end

% ======================================================================
% ICA selector GUI
% ======================================================================
function [selected, applyFlag] = ica_selector_gui_grid(TC, proxy, Avox, volSize, TR, maxPts)

T = size(TC,1);
K = size(TC,2);

if T > maxPts
    idx = unique(round(linspace(1, T, maxPts)));
else
    idx = 1:T;
end

tmin_full = ((0:T-1) * TR) / 60;
tmin = tmin_full(idx);
tmax = tmin_full(end);
xticks = niceMinuteTicks(tmax);

selected = [];
applyFlag = false;

perPage = 25;
nPages = max(1, ceil(K / perPage));
page = 1;
currentPreviewK = 1; %#ok<NASGU>
currentMap2D = [];
currentMapTitle = '';

% theme
bgFig     = [0.06 0.06 0.07];
bgAx      = [0.09 0.09 0.10];
bgPanel   = [0.08 0.08 0.09];
fg        = [0.90 0.90 0.92];
fgDim     = [0.70 0.70 0.74];
selRed    = [1.00 0.25 0.25];
lineCol   = [0.35 0.80 1.00];

fig = figure('Name','ICA Components - left click select, right click deselect', ...
    'Color',bgFig,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Position',[160 90 1580 900]);

try, set(fig,'Renderer','opengl'); catch, end

gridX = 0.03; gridY = 0.08; gridW = 0.66; gridH = 0.90;
rightX = 0.705; rightY = 0.035; rightW = 0.285; rightH = 0.93;

hdr = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
    'Position',[gridX 0.97 gridW 0.03], ...
    'String','', ...
    'BackgroundColor',bgFig,'ForegroundColor',fg,'FontSize',13,'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',fig,'Style','text','Units','normalized', ...
    'Position',[gridX gridY-0.05 gridW 0.03], ...
    'String','Time (min)', ...
    'BackgroundColor',bgFig,'ForegroundColor',fgDim, ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

rightPanel = uipanel('Parent',fig,'Units','normalized','Position',[rightX rightY rightW rightH], ...
    'BackgroundColor',bgPanel,'ForegroundColor',fg,'Title','Selection', ...
    'FontWeight','bold','FontSize',12);

% ----------------------------------------------------------
% Timecourse preview (top)
% ----------------------------------------------------------
axPrev = axes('Parent',rightPanel,'Units','normalized','Position',[0.10 0.67 0.82 0.19], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim, ...
    'Box','on','LineWidth',1.0);
title(axPrev,'Preview','Color',fg,'FontWeight','bold');
grid(axPrev,'on');

% ----------------------------------------------------------
% Bigger spatial map preview + separate title text
% ----------------------------------------------------------
mapTitleText = uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.07 0.605 0.50 0.03], ...
    'String','Spatial weight preview', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontWeight','bold','FontSize',12);

axMap = axes('Parent',rightPanel,'Units','normalized','Position',[0.07 0.36 0.50 0.25], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim, ...
    'Box','on','LineWidth',1.0);

% ----------------------------------------------------------
% Display controls (bigger fonts, tighter layout)
% ----------------------------------------------------------
uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.58 0.61 0.24 0.03], ...
    'String','Map Display', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',12);

uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.58 0.545 0.16 0.03], ...
    'String','Contrast', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

contrastSlider = uicontrol('Parent',rightPanel,'Style','slider', ...
    'Units','normalized','Position',[0.58 0.512 0.20 0.032], ...
    'Min',0.5,'Max',3.0,'Value',2.0, ...
    'BackgroundColor',[0.18 0.18 0.19], ...
    'Callback',@updateSpatialControls);

contrastValueText = uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.80 0.510 0.10 0.032], ...
    'String','2.00', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',[0.70 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',10);

uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.58 0.465 0.16 0.03], ...
    'String','Gamma', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

gammaSlider = uicontrol('Parent',rightPanel,'Style','slider', ...
    'Units','normalized','Position',[0.58 0.432 0.20 0.032], ...
    'Min',0.30,'Max',1.50,'Value',0.75, ...
    'BackgroundColor',[0.18 0.18 0.19], ...
    'Callback',@updateSpatialControls);

gammaValueText = uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.80 0.430 0.10 0.032], ...
    'String','0.75', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',[0.70 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',10);

uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.58 0.385 0.18 0.03], ...
    'String','Colormap', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fgDim, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

mapDropdown = uicontrol('Parent',rightPanel,'Style','popupmenu', ...
    'Units','normalized','Position',[0.58 0.350 0.28 0.038], ...
    'String',{'gray','hot','parula','jet','winter'}, ...
    'Value',2, ...
    'BackgroundColor',[0.18 0.18 0.19], ...
    'ForegroundColor',fg, ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@updateSpatialControls);

txtInfo = uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.10 0.295 0.82 0.04], ...
    'String','Selected: 0 ICs | Removed: 0.00%', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',[0.70 0.90 1.00], ...
    'FontSize',11,'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.10 0.252 0.82 0.03], ...
    'String','Selected for removal:', ...
    'BackgroundColor',bgPanel, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

lb = uicontrol('Parent',rightPanel,'Style','listbox','Units','normalized', ...
    'Position',[0.10 0.165 0.82 0.075], ...
    'String',{'<none>'}, ...
    'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, ...
    'FontName','Courier New', ...
    'FontSize',11);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.10 0.082 0.38 0.075], 'String','Apply & Close', ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[0.20 0.45 0.25], 'ForegroundColor','w', ...
    'Callback',@applyAndClose);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.54 0.082 0.38 0.075], 'String','Cancel', ...
    'FontWeight','bold','FontSize',12, ...
    'BackgroundColor',[0.65 0.20 0.20], 'ForegroundColor','w', ...
    'Callback',@cancelAndClose);

btnPrev = uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.10 0.012 0.24 0.062], 'String','Prev', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.22 0.22 0.25], 'ForegroundColor','w', ...
    'Callback',@prevPage);

btnNext = uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.38 0.012 0.24 0.062], 'String','Next', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.22 0.22 0.25], 'ForegroundColor','w', ...
    'Callback',@nextPage);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.66 0.012 0.26 0.062], 'String','HELP', ...
    'FontWeight','bold','FontSize',11, ...
    'BackgroundColor',[0.10 0.35 0.95], 'ForegroundColor','w', ...
    'Callback',@showHelp);

% Build 5x5 axes like PCA
nRow = 5; nCol = 5;
axGrid = gobjects(25,1);
lnGrid = gobjects(25,1);
icLabel = gobjects(25,1);
compIdx = nan(25,1);

pad = 0.008;
cellW = gridW / nCol;
cellH = gridH / nRow;

for i = 1:25
    r = floor((i-1)/nCol);
    c = mod((i-1), nCol);

    x0 = gridX + c*cellW + pad;
    y0 = gridY + (nRow-1-r)*cellH + pad;
    w0 = cellW - 2*pad;
    h0 = cellH - 2*pad;

    axGrid(i) = axes('Parent',fig,'Units','normalized','Position',[x0 y0 w0 h0], ...
        'Color',bgAx);

    set(axGrid(i),'Box','on','LineWidth',1.0, ...
        'XColor',fgDim*0.35,'YColor',fgDim*0.35);

    set(axGrid(i),'YTick',[]);
    set(axGrid(i),'XLim',[0 tmax]);

    hold(axGrid(i),'on');
    lnGrid(i) = plot(axGrid(i), tmin, zeros(size(tmin)), 'LineWidth', 1.0);
    set(lnGrid(i),'Color',lineCol);

    icLabel(i) = text(axGrid(i), 0.02, 0.92, '', ...
        'Units','normalized', 'Color',fg, 'FontSize',11, ...
        'FontWeight','bold', 'Interpreter','none');

    hold(axGrid(i),'off');

    set(axGrid(i), 'ButtonDownFcn', @(h,~)onCellClick(h));
    set(lnGrid(i), 'ButtonDownFcn', @(h,~)onCellClick(h));
    try, set(axGrid(i),'PickableParts','all'); catch, end
    try, set(lnGrid(i),'PickableParts','all'); catch, end
    set(axGrid(i),'HitTest','on');
    set(lnGrid(i),'HitTest','on');
end

set(fig,'WindowKeyPressFcn',@onKey);
set(fig,'CloseRequestFcn',@onCloseCancel);

renderPage();
previewComponent(1);

uiwait(fig);

    function renderPage()
        firstIC = (page-1)*perPage + 1;
        lastIC  = min(K, page*perPage);
        set(hdr,'String',sprintf('ICs %d-%d of %d   (Page %d/%d)', firstIC, lastIC, K, page, nPages));

        set(btnPrev,'Enable', onoff(page>1));
        set(btnNext,'Enable', onoff(page<nPages));

        for i2 = 1:25
            k = (page-1)*perPage + i2;
            compIdx(i2) = k;

            if k <= K
                tc = TC(:,k);
                tc = tc(idx);

                set(lnGrid(i2),'XData',tmin,'YData',tc,'Visible','on');
                set(axGrid(i2),'XLim',[0 tmax]);

                rr = floor((i2-1)/nCol);
                if rr == (nRow-1)
                    set(axGrid(i2),'XTick',xticks, ...
                        'XTickLabel',arrayfun(@(x)sprintf('%d',round(x)),xticks,'uni',0), ...
                        'XColor',fgDim);
                else
                    set(axGrid(i2),'XTick',[], 'XTickLabel',{}, 'XColor',fgDim*0.35);
                end

                s = sprintf('IC%d  %.2f%%', k, 100*proxy(k));
                set(icLabel(i2),'String',s);

                if any(selected == k)
                    set(axGrid(i2),'XColor',selRed,'YColor',selRed,'LineWidth',2.2);
                    set(icLabel(i2),'Color',selRed);
                else
                    set(axGrid(i2),'XColor',fgDim*0.35,'YColor',fgDim*0.35,'LineWidth',1.0);
                    set(icLabel(i2),'Color',fg);
                end

                set(axGrid(i2),'Visible','on');
            else
                set(axGrid(i2),'Visible','off');
            end
        end

        safeDrawnow();
    end

    function onCellClick(hObj)
        axh = [];
        if strcmp(get(hObj,'Type'),'axes')
            axh = hObj;
        else
            axh = ancestor(hObj,'axes');
        end
        if isempty(axh), return; end

        iCell = find(axGrid == axh, 1);
        if isempty(iCell), return; end

        k = compIdx(iCell);
        if ~isfinite(k) || k < 1 || k > K, return; end

        typ = get(fig,'SelectionType');
        if strcmp(typ,'alt')
            selected(selected == k) = [];
        else
            if any(selected == k)
                selected(selected == k) = [];
            else
                selected(end+1) = k; %#ok<AGROW>
            end
        end

        selected = sort(unique(selected));
        refreshSelectionUI();
        previewComponent(k);
        renderPage();
    end

    function previewComponent(k)
        if k < 1 || k > K, return; end
        currentPreviewK = k; %#ok<NASGU>

        cla(axPrev);
        tc = TC(:,k);
        tc = tc(idx);

        plot(axPrev, tmin, tc, 'LineWidth', 1.6, 'Color', lineCol);
        grid(axPrev,'on');
        set(axPrev,'XColor',fgDim,'YColor',fgDim,'Color',bgAx);
        title(axPrev, sprintf('IC%d | %.2f%%', k, 100*proxy(k)), 'Color',fg, 'FontWeight','bold');
        xlabel(axPrev,'Time (min)','Color',fgDim);
        ylabel(axPrev,'Amplitude (a.u.)','Color',fgDim);
        set(axPrev,'XLim',[0 tmax], 'XTick',xticks);

        mapk = reshape(Avox(:,k), volSize);

        if volSize(3) > 1
            sliceScore = zeros(1, volSize(3));
            for zz = 1:volSize(3)
                tmp = abs(mapk(:,:,zz));
                sliceScore(zz) = max(tmp(:));
            end
            [~, zShow] = max(sliceScore);
            currentMap2D = abs(mapk(:,:,zShow));
            currentMapTitle = sprintf('Spatial weight preview (Z=%d)', zShow);
        else
            currentMap2D = abs(mapk(:,:,1));
            currentMapTitle = 'Spatial weight preview';
        end

        refreshSpatialPreview();
        safeDrawnow();
    end

    function refreshSpatialPreview()
        cla(axMap);

        if isempty(currentMap2D)
            return;
        end

        map2 = double(currentMap2D);

        lo = prctile(map2(:), 5);
        hi = prctile(map2(:), 99);

        if ~isfinite(lo), lo = min(map2(:)); end
        if ~isfinite(hi), hi = max(map2(:)); end
        if hi <= lo
            hi = lo + eps;
        end

        map2 = (map2 - lo) / (hi - lo);
        map2 = max(0, min(1, map2));

        previewContrast = get(contrastSlider,'Value');
        previewGamma    = get(gammaSlider,'Value');

        map2 = map2 * previewContrast;
        map2 = max(0, min(1, map2));
        map2 = map2 .^ previewGamma;

        imagesc(axMap, map2, [0 1]);
        axis(axMap,'image');
        axis(axMap,'off');

        set(mapTitleText,'String',currentMapTitle);

        maps = get(mapDropdown,'String');
        cmapName = maps{get(mapDropdown,'Value')};
        colormap(axMap, cmapName);
    end

    function updateSpatialControls(~,~)
        set(contrastValueText,'String',sprintf('%.2f', get(contrastSlider,'Value')));
        set(gammaValueText,'String',sprintf('%.2f', get(gammaSlider,'Value')));
        refreshSpatialPreview();
        safeDrawnow();
    end

    function refreshSelectionUI()
        if isempty(selected)
            set(lb,'String',{'<none>'},'Value',1);
        else
            s = arrayfun(@(x)sprintf('IC%-3d  (%.2f%%)', x, 100*proxy(x)), selected, 'uni',0);
            set(lb,'String',s,'Value',1);
        end
        pct = 100 * sum(proxy(selected));
        set(txtInfo,'String',sprintf('Selected: %d ICs | Removed: %.2f%%', numel(selected), pct));
        safeDrawnow();
    end

    function prevPage(~,~)
        if page > 1
            page = page - 1;
            renderPage();
            previewComponent((page-1)*perPage + 1);
        end
    end

    function nextPage(~,~)
        if page < nPages
            page = page + 1;
            renderPage();
            previewComponent((page-1)*perPage + 1);
        end
    end

    function showHelp(~,~)
        msg = {
            'What ICA does'
            ''
            'ICA first whitens the data using PCA, then finds statistically independent components.'
            'Each IC has a timecourse and a spatial weight map.'
            ''
            'Spatial weight preview'
            'This shows where that IC contributes strongly across voxels.'
            'Use the small Contrast/Gamma/Colormap controls only for display.'
            ''
            'Display hints'
            '  Lower gamma (< 1) brightens weak structures.'
            '  Higher contrast makes strong IC weights more visible.'
            '  Gray is often easiest for anatomical-style inspection.'
            ''
            'How to use it'
            '  - Remove ICs that look like drift, edge artifact, stripes, motion bursts, or non-biological patterns.'
            '  - Keep ICs that look anatomically plausible or stimulus-related.'
            ''
            'Controls'
            '  Left click  : toggle select'
            '  Right click : deselect'
            '  Prev/Next   : page through ICs'
            '  Apply       : apply removal and close'
            '  Cancel      : close with no changes'
            ''
            'Important'
            'ICA is more powerful than PCA for source separation, but easier to misuse.'
            'Always review both timecourse and spatial map before removing an IC.'
            };
        helpdlg(msg,'ICA Help');
    end

    function onKey(~,evt)
        switch evt.Key
            case {'return','enter'}
                applyAndClose();
            case {'escape'}
                cancelAndClose();
            case {'rightarrow'}
                nextPage();
            case {'leftarrow'}
                prevPage();
        end
    end

    function applyAndClose(~,~)
        applyFlag = true;
        try, uiresume(fig); catch, end
        try, delete(fig); catch, end
    end

    function cancelAndClose(~,~)
        applyFlag = false;
        selected = [];
        try, uiresume(fig); catch, end
        try, delete(fig); catch, end
    end

    function onCloseCancel(~,~)
        cancelAndClose();
    end

end

% ======================================================================
% Symmetric FastICA
% ======================================================================
function [B, Sica, out] = fastica_symm(Z, maxIter, tol)

K = size(Z,1);
T = size(Z,2);

rng('default');

B = randn(K,K);
[uu,~,vv] = svd(B, 'econ');
B = uu * vv';

converged = false;
nIter = 0;

for it = 1:maxIter
    nIter = it;

    Y = B * Z;
    G = tanh(Y);
    Gp = 1 - G.^2;

    Bnew = (G * Z') / T - diag(mean(Gp,2)) * B;

    [u2,~,v2] = svd(Bnew, 'econ');
    Bnew = u2 * v2';

    lim = max(abs(abs(diag(Bnew * B')) - 1));
    B = Bnew;

    if lim < tol
        converged = true;
        break;
    end
end

Sica = B * Z;

out = struct();
out.nIter = nIter;
out.converged = converged;
end

% ======================================================================
% QC plots
% ======================================================================
function make_qc_plot_selected_ica(proxy, selected, outFile)

qcBlue = [0.00 0.15 0.55];
qcSel  = [0.15 0.15 0.15];
qcEdge = [0.85 0.10 0.10];

fig = figure('Visible','off','Color','w','Position',[100 100 1100 380]);
ax = axes('Parent',fig);

bar(ax, 100*proxy(:), 'FaceColor', qcBlue, 'EdgeColor', 'none');
hold(ax,'on');

if ~isempty(selected)
    bar(ax, selected, 100*proxy(selected), 'FaceColor', qcSel, 'EdgeColor', qcEdge, 'LineWidth', 1.2);
end

xlabel(ax,'IC index');
ylabel(ax,'Energy proxy (%)');
title(ax,'ICA component energy proxy (dark bars = removed ICs)');
grid(ax,'on');
set(ax,'LineWidth',1.2,'FontSize',11,'GridAlpha',0.25);

saveas(fig, outFile);
close(fig);
end

function make_qc_globalmean_plot_ica(gb, ga, TR, outFile)

T = numel(gb);
tmin = ((0:T-1)*TR)/60;

qcBlue  = [0.00 0.15 0.55];
qcAfter = [0.20 0.20 0.20];

fig = figure('Visible','off','Color','w','Position',[120 120 1100 380]);
ax = axes('Parent',fig);

plot(ax, tmin, double(gb), 'LineWidth', 1.9, 'Color', qcBlue); hold(ax,'on');
plot(ax, tmin, double(ga), 'LineWidth', 1.9, 'Color', qcAfter);

grid(ax,'on');
xlabel(ax,'Time (min)');
ylabel(ax,'Global mean intensity');
legend(ax, {'Before','After'}, 'Location','best');
title(ax,'Global mean intensity: before vs after ICA removal');

set(ax,'LineWidth',1.2,'FontSize',11,'GridAlpha',0.25);

saveas(fig, outFile);
close(fig);
end

function make_qc_meanimage_plot(I4_before, I4_after, outFile)

mBefore = mean(single(I4_before), 4);
mAfter  = mean(single(I4_after), 4);

Z = size(mBefore,3);
zMid = max(1, round(Z/2));

im1 = mBefore(:,:,zMid);
im2 = mAfter(:,:,zMid);

mn = min([im1(:); im2(:)]);
mx = max([im1(:); im2(:)]);
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    mn = 0; mx = 1;
end

fig = figure('Visible','off','Color','w','Position',[140 140 1100 420]);

ax1 = subplot(1,2,1);
imagesc(ax1, im1); axis(ax1,'image'); axis(ax1,'off');
colormap(ax1, gray(256)); caxis(ax1, [mn mx]);
title(ax1, sprintf('Mean BEFORE (Z=%d)', zMid));

ax2 = subplot(1,2,2);
imagesc(ax2, im2); axis(ax2,'image'); axis(ax2,'off');
colormap(ax2, gray(256)); caxis(ax2, [mn mx]);
title(ax2, sprintf('Mean AFTER (Z=%d)', zMid));

saveas(fig, outFile);
close(fig);
end

function files = make_qc_grid_dark_exact_ica(TC, proxy, TR, selected, qcDir, tag)

files = {};
K = size(TC,2);
T = size(TC,1);

maxPts = 2000;
if T > maxPts
    idx = unique(round(linspace(1, T, maxPts)));
else
    idx = 1:T;
end

tmin_full = ((0:T-1)*TR)/60;
tmin = tmin_full(idx);
tmax = tmin_full(end);
xticks = niceMinuteTicks(tmax);

perPage = 25;
nPages = max(1, ceil(K/perPage));

savePages = false(1,nPages);
savePages(1) = true;
for s = selected(:)'
    p = ceil(s/perPage);
    if p >= 1 && p <= nPages
        savePages(p) = true;
    end
end

bgFig   = [0.06 0.06 0.07];
bgAx    = [0.09 0.09 0.10];
fg      = [0.90 0.90 0.92];
fgDim   = [0.70 0.70 0.74];
selRed  = [1.00 0.25 0.25];
lineCol = [0.35 0.80 1];
lineW   = 1.35;

for p = 1:nPages
    if ~savePages(p), continue; end

    fig = figure('Visible','off','Color',bgFig,'Position',[80 60 1500 860]);

    annotation(fig,'textbox',[0.03 0.965 0.66 0.03], ...
        'String',sprintf('ICA grid (exact look) - Page %d/%d - tag=%s', p, nPages, tag), ...
        'Color',fg,'FontSize',13,'FontWeight','bold','EdgeColor','none', ...
        'Interpreter','none','HorizontalAlignment','left');

    annotation(fig,'textbox',[0.03 0.03 0.66 0.03], ...
        'String','Time (min)', ...
        'Color',fgDim,'FontSize',11,'FontWeight','bold','EdgeColor','none', ...
        'Interpreter','none','HorizontalAlignment','center');

    gridX=0.03; gridY=0.08; gridW=0.66; gridH=0.90;
    nRow=5; nCol=5;
    pad=0.008; cellW=gridW/nCol; cellH=gridH/nRow;

    for i = 1:25
        r = floor((i-1)/nCol);
        c = mod((i-1), nCol);

        x0 = gridX + c*cellW + pad;
        y0 = gridY + (nRow-1-r)*cellH + pad;
        w0 = cellW - 2*pad;
        h0 = cellH - 2*pad;

        ax = axes('Parent',fig,'Units','normalized','Position',[x0 y0 w0 h0], 'Color',bgAx);
        set(ax,'Box','on','YTick',[],'XLim',[0 tmax]);

        k = (p-1)*perPage + i;
        if k <= K
            tc = TC(:,k); tc = tc(idx);
            plot(ax, tmin, tc, 'LineWidth', lineW, 'Color', lineCol);
            grid(ax,'on');

            rr = floor((i-1)/nCol);
            if rr == (nRow-1)
                set(ax,'XTick',xticks,'XTickLabel',arrayfun(@(x)sprintf('%d',round(x)),xticks,'uni',0), ...
                    'XColor',fgDim);
            else
                set(ax,'XTick',[],'XTickLabel',{}, 'XColor',fgDim*0.35);
            end

            isSel = any(selected == k);
            labCol = fg; boxCol = fgDim*0.35; lw = 1.0;

            if isSel
                boxCol = selRed; lw = 2.2; labCol = selRed;
                text(ax,0.02,0.78,'REMOVED', 'Units','normalized', ...
                    'Color',selRed,'FontWeight','bold','FontSize',10,'Interpreter','none');
            end

            text(ax,0.02,0.92,sprintf('IC%d  %.2f%%',k,100*proxy(k)), 'Units','normalized', ...
                'Color',labCol,'FontWeight','bold','FontSize',10,'Interpreter','none');

            set(ax,'XColor',boxCol,'YColor',boxCol,'LineWidth',lw);
        else
            axis(ax,'off');
        end
    end

    outFile = fullfile(qcDir, sprintf('ICA_grid_dark_page%02d_%s.png', p, tag));
    saveas(fig, outFile);
    close(fig);

    files{end+1} = outFile; %#ok<AGROW>
end
end

% ======================================================================
% Helpers
% ======================================================================
function s = emptyStats(tag)
s = struct();
s.tag = tag;
s.selectedComponents = [];
s.percentEnergyRemoved = 0;
s.energyProxyPerComponent = [];
s.qcFile = '';
s.qcGlobalMeanFile = '';
s.qcMeanImageFile = '';
s.qcGridFiles = {};
s.nComponents = 0;
s.method = '';
s.applied = false;
s.nIter = 0;
s.converged = false;
end

function safeDrawnow()
try
    drawnow limitrate;
catch
    drawnow;
end
end

function out = onoff(tf)
if tf, out = 'on'; else, out = 'off'; end
end

function ticks = niceMinuteTicks(tmax)
if ~isfinite(tmax) || tmax <= 0
    ticks = [0 1];
    return;
end

candidates = [0.5 1 2 5 10 15 20 30 60 120];
best = candidates(end);

for i = 1:numel(candidates)
    dt = candidates(i);
    n = floor(tmax/dt) + 1;
    if n <= 7
        best = dt;
        break;
    end
end

ticks = 0:best:tmax;
if ticks(end) < tmax
    ticks(end+1) = tmax;
end
ticks = unique(ticks);
end