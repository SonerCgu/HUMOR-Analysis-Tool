function [newData, stats] = pca_denoise(dataIn, saveRoot, tag, opts)
% PCA_DENOISE — interactive PCA removal (MATLAB 2017b + 2023b)
% ==========================================================
% - 25 PCs/page grid selector (dark theme)
% - Left-click: toggle select (red border = removed)
% - Right-click: deselect
% - Clean minutes axis ticks + labels
% - Logs apply/cancel reliably in fUSI Studio by calling opts.onApply/onCancel
%   ONLY AFTER the selector closes (important for Studio log correctness)
%
% QC PNGs saved (in <saveRoot>/Preprocessing/pca_QC):
%   1) PCA_selected_<tag>.png                       (variance proxy bar; removed dark)
%   2) PCA_globalMean_before_after_<tag>.png        (minutes; dark blue + dark gray)
%   3) PCA_meanImage_before_after_<tag>.png         (middle Z slice)
%   4) PCA_grid_dark_pageXX_<tag>.png               (exact-look grid pages; removed marked)
%
% Inputs:
%   dataIn: struct with .I (and optional .TR) OR raw array [Y X T] / [Y X Z T]
%   saveRoot: studio.exportPath
%   tag: e.g. ['pca_' datestr(now,'yyyymmdd_HHMMSS')]
%   opts:
%       .nCompMax (default 50)
%       .maxDisplayPoints (default 2000)
%       .chunkT (default 250)
%       .centerMode = 'voxel' (default) or 'global'
%       .verbose (default true)
%       .onApply  = @(sel) ...   % called immediately AFTER selector closes with Apply
%       .onCancel = @() ...      % called immediately AFTER selector closes with Cancel
%       .logFcn   = @(msg) ...   % optional log for internal progress messages

if nargin < 2 || isempty(saveRoot), saveRoot = pwd; end
if nargin < 3 || isempty(tag), tag = datestr(now,'yyyymmdd_HHMMSS'); end
if nargin < 4, opts = struct(); end

% ---- defaults ----
if ~isfield(opts,'nCompMax'),         opts.nCompMax = 50; end
if ~isfield(opts,'maxDisplayPoints'), opts.maxDisplayPoints = 2000; end
if ~isfield(opts,'chunkT'),           opts.chunkT = 250; end
if ~isfield(opts,'centerMode'),       opts.centerMode = 'voxel'; end % 'voxel' or 'global'
if ~isfield(opts,'verbose'),          opts.verbose = true; end
if ~isfield(opts,'onApply'),          opts.onApply = []; end
if ~isfield(opts,'onCancel'),         opts.onCancel = []; end
if ~isfield(opts,'logFcn'),           opts.logFcn = []; end

% ---- extract data + TR ----
isStruct = isstruct(dataIn);
if isStruct
    if ~isfield(dataIn,'I'), error('pca_denoise: input struct must contain .I'); end
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
V = Y*X*Z;

Xvt = reshape(single(I4), [V, T]);

% ---- global mean BEFORE (QC) ----
gmean_before = mean(Xvt, 1);

% ---- center ----
switch lower(opts.centerMode)
    case 'global'
        mu = mean(Xvt(:));
        Xc = Xvt - single(mu);
        muVec = [];
    otherwise % voxel
        muVec = mean(Xvt, 2);
        Xc = bsxfun(@minus, Xvt, muVec);
        mu = [];
end

% ---- choose K ----
K = min([opts.nCompMax, T-1, 200]);
if K < 1
    stats = emptyStats(tag);
    stats.method = 'PCA (none)';
    newData.I = I;
    return;
end

if opts.verbose
    fprintf('[PCA] V=%d, T=%d, computing top K=%d...\n', V, T, K);
end

% ==========================================================
% PCA via svds on Xc' [T x V]
% ==========================================================
Xtv = double(Xc');  % [T x V]
useFallback = false;

try
    [U,S,W] = svds(Xtv, K);       % U:[T x K], W:[V x K]
catch
    useFallback = true;
end

if useFallback
    if opts.verbose, fprintf('[PCA] svds failed -> eigs fallback\n'); end
    Ct = Xtv * Xtv';              % [T x T]
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

expl = sing.^2;
expl = expl / max(eps, sum(expl));

% ==========================================================
% GUI selection (25/page)
% IMPORTANT: selector does NOT call Studio log itself.
% We call opts.onApply/opts.onCancel only AFTER selector closes.
% ==========================================================
[selected, applyFlag] = pca_selector_gui_grid(U, expl, TR, opts.maxDisplayPoints);

stats = emptyStats(tag);
stats.nComponents = K;
stats.explainedPerComponent = expl(:)';
stats.selectedComponents = [];
stats.percentExplainedRemoved = 0;
stats.applied = false;
stats.method = 'PCA (cancelled)';
stats.qcGridFiles = {};

if ~applyFlag
    % user cancelled
    if ~isempty(opts.onCancel) && isa(opts.onCancel,'function_handle')
        try, opts.onCancel(); catch, end
    end
    newData.I = I;
    return;
end

selected = unique(selected(:)');
selected = selected(selected >= 1 & selected <= K);

% NOW we can safely log/apply hook in Studio context
if ~isempty(opts.onApply) && isa(opts.onApply,'function_handle')
    try, opts.onApply(selected); catch, end
end

stats.selectedComponents = selected;
stats.percentExplainedRemoved = 100 * sum(expl(selected));
stats.applied = true;
stats.method = 'PCA denoise (grid select)';

if isempty(selected)
    if ~isempty(opts.logFcn) && isa(opts.logFcn,'function_handle')
        try, opts.logFcn('PCA applied: no PCs selected (no change).'); catch, end
    end
    newData.I = I;
    return;
end

% ==========================================================
% Remove selected PCs: Xc_clean = Xc - Wsel*Ssel*Usel'
% chunked time
% ==========================================================
Wsel = double(W(:, selected));                 % [V x R]
Ssel = diag(double(sing(selected)));           % [R x R]

Xclean = Xc;                                   % [V x T] single
chunkT = max(50, round(opts.chunkT));

if opts.verbose
    fprintf('[PCA] Removing %d PCs (%.2f%% variance proxy)...\n', numel(selected), stats.percentExplainedRemoved);
end

for t0 = 1:chunkT:T
    t1 = min(T, t0 + chunkT - 1);
    Ut = double(U(t0:t1, selected));          % [chunk x R]
    A  = Ssel * Ut';                          % [R x chunk]
    recon = Wsel * A;                         % [V x chunk]
    Xclean(:, t0:t1) = Xclean(:, t0:t1) - single(recon);
end

% add mean back
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
newData.preprocessing = 'PCA denoise (grid select)';

% ==========================================================
% QC save
% ==========================================================
stats.qcFile = '';
stats.qcGlobalMeanFile = '';
stats.qcMeanImageFile = '';
stats.qcGridFiles = {};

try
    qcDir = fullfile(saveRoot, 'Preprocessing', 'pca_QC');
    if ~exist(qcDir,'dir'), mkdir(qcDir); end

    qc1 = fullfile(qcDir, sprintf('PCA_selected_%s.png', tag));
    make_qc_plot_selected(expl, selected, qc1); % (colors upgraded)
    stats.qcFile = qc1;

    qc2 = fullfile(qcDir, sprintf('PCA_globalMean_before_after_%s.png', tag));
    make_qc_globalmean_plot(gmean_before, gmean_after, TR, qc2); % (colors upgraded)
    stats.qcGlobalMeanFile = qc2;

    qc3 = fullfile(qcDir, sprintf('PCA_meanImage_before_after_%s.png', tag));
    make_qc_meanimage_plot(single(I4), single(Iout4), qc3);
    stats.qcMeanImageFile = qc3;

    % Exact-look dark grid pages (always save page 1, plus pages containing removed)
    gridFiles = make_qc_grid_dark_exact(U, expl, TR, selected, qcDir, tag); % (colors upgraded)
    stats.qcGridFiles = gridFiles;

catch ME
    if opts.verbose
        fprintf('[PCA] QC save warning: %s\n', ME.message);
    end
end

end

% ======================================================================
% PCA selector GUI (25/page grid)
% ======================================================================
function [selected, applyFlag] = pca_selector_gui_grid(U, expl, TR, maxPts)

T = size(U,1);
K = size(U,2);

% downsample for speed
if T > maxPts
    idx = unique(round(linspace(1, T, maxPts)));
else
    idx = 1:T;
end

tmin_full = ((0:T-1) * TR) / 60;
tmin = tmin_full(idx);
tmax = tmin_full(end);

% nice ticks in minutes (shared)
xticks = niceMinuteTicks(tmax);

selected = [];
applyFlag = false;

perPage = 25;
nPages = max(1, ceil(K / perPage));
page = 1;

% theme
bgFig   = [0.06 0.06 0.07];
bgAx    = [0.09 0.09 0.10];
fg      = [0.90 0.90 0.92];
fgDim   = [0.70 0.70 0.74];
selRed  = [1.00 0.25 0.25];

% STRONGER (less washed) blue for UI
lineCol = [0.35 0.80 1];   % lightblue (more visible than light blue)

fig = figure('Name','PCA Components — left click select, right click deselect', ...
    'Color',bgFig,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Position',[160 90 1500 860]);

try, set(fig,'Renderer','opengl'); catch, end

gridX = 0.03; gridY = 0.08; gridW = 0.66; gridH = 0.90;
rightX = 0.71; rightY = 0.08; rightW = 0.27; rightH = 0.90;

hdr = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
    'Position',[gridX 0.97 gridW 0.03], ...
    'String','', ...
    'BackgroundColor',bgFig,'ForegroundColor',fg,'FontSize',13,'FontWeight','bold', ...
    'HorizontalAlignment','left');

% single shared x-axis label for grid
uicontrol('Parent',fig,'Style','text','Units','normalized', ...
    'Position',[gridX gridY-0.05 gridW 0.03], ...
    'String','Time (min)', ...
    'BackgroundColor',bgFig,'ForegroundColor',fgDim, ...
    'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

rightPanel = uipanel('Parent',fig,'Units','normalized','Position',[rightX rightY rightW rightH], ...
    'BackgroundColor',[0.08 0.08 0.09],'ForegroundColor',fg,'Title','Selection', ...
    'FontWeight','bold','FontSize',12);

axPrev = axes('Parent',rightPanel,'Units','normalized','Position',[0.10 0.60 0.82 0.34], ...
    'Color',bgAx,'XColor',fgDim,'YColor',fgDim);
title(axPrev,'Preview','Color',fg,'FontWeight','bold');
grid(axPrev,'on');

txtInfo = uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.10 0.52 0.82 0.07], ...
    'String','Selected: 0 PCs | Removed: 0.00%', ...
    'BackgroundColor',get(rightPanel,'BackgroundColor'), ...
    'ForegroundColor',[0.70 0.90 1.00], ...
    'FontSize',11,'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',rightPanel,'Style','text','Units','normalized', ...
    'Position',[0.10 0.47 0.82 0.04], 'String','Selected for removal:', ...
    'BackgroundColor',get(rightPanel,'BackgroundColor'), 'ForegroundColor',fg, ...
    'HorizontalAlignment','left','FontWeight','bold','FontSize',11);

lb = uicontrol('Parent',rightPanel,'Style','listbox','Units','normalized', ...
    'Position',[0.10 0.22 0.82 0.25], ...
    'String',{'<none>'}, 'BackgroundColor',[0.16 0.16 0.18], ...
    'ForegroundColor',fg, 'FontName','Courier New','FontSize',11);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.10 0.12 0.38 0.08], 'String','Apply & Close', ...
    'FontWeight','bold','FontSize',12, 'BackgroundColor',[0.20 0.45 0.25], 'ForegroundColor','w', ...
    'Callback',@applyAndClose);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.54 0.12 0.38 0.08], 'String','Cancel', ...
    'FontWeight','bold','FontSize',12, 'BackgroundColor',[0.65 0.20 0.20], 'ForegroundColor','w', ...
    'Callback',@cancelAndClose);

btnPrev = uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.10 0.03 0.24 0.07], 'String','Prev', ...
    'FontWeight','bold','FontSize',11, 'BackgroundColor',[0.22 0.22 0.25], 'ForegroundColor','w', ...
    'Callback',@prevPage);

btnNext = uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.38 0.03 0.24 0.07], 'String','Next', ...
    'FontWeight','bold','FontSize',11, 'BackgroundColor',[0.22 0.22 0.25], 'ForegroundColor','w', ...
    'Callback',@nextPage);

uicontrol('Parent',rightPanel,'Style','pushbutton','Units','normalized', ...
    'Position',[0.66 0.03 0.26 0.07], 'String','HELP', ...
    'FontWeight','bold','FontSize',11, 'BackgroundColor',[0.10 0.35 0.95], 'ForegroundColor','w', ...
    'Callback',@showHelp);

% Build 5x5 axes
nRow = 5; nCol = 5;
axGrid = gobjects(25,1);
lnGrid = gobjects(25,1);
pcLabel = gobjects(25,1);
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

    % label INSIDE axis so it never disappears
    pcLabel(i) = text(axGrid(i), 0.02, 0.92, '', ...
        'Units','normalized', 'Color',fg, 'FontSize',11, ...
        'FontWeight','bold', 'Interpreter','none', 'Tag','PCLABEL');

    hold(axGrid(i),'off');

    % clickable
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
        firstPC = (page-1)*perPage + 1;
        lastPC  = min(K, page*perPage);
        set(hdr,'String',sprintf('PCs %d–%d of %d   (Page %d/%d)', firstPC, lastPC, K, page, nPages));

        set(btnPrev,'Enable', onoff(page>1));
        set(btnNext,'Enable', onoff(page<nPages));

        for i2 = 1:25
            k = (page-1)*perPage + i2;
            compIdx(i2) = k;

            if k <= K
                tc = U(:,k);
                tc = tc(idx);

                set(lnGrid(i2),'XData',tmin,'YData',tc,'Visible','on');

                % consistent x-limits/ticks
                set(axGrid(i2),'XLim',[0 tmax]);

                % bottom row gets ticks/labels, others none (clean)
                rr = floor((i2-1)/nCol); % 0..4 top->bottom
                if rr == (nRow-1)
                    set(axGrid(i2),'XTick',xticks, 'XTickLabel',arrayfun(@(x)sprintf('%d',round(x)),xticks,'uni',0), ...
                        'XColor',fgDim);
                else
                    set(axGrid(i2),'XTick',[], 'XTickLabel',{}, 'XColor',fgDim*0.35);
                end

                % label inside axis
                s = sprintf('PC%d  %.2f%%', k, 100*expl(k));
                set(pcLabel(i2),'String',s);

                % selection styling
                if any(selected == k)
                    set(axGrid(i2),'XColor',selRed,'YColor',selRed,'LineWidth',2.2);
                    set(pcLabel(i2),'Color',selRed);
                else
                    set(axGrid(i2),'XColor',fgDim*0.35,'YColor',fgDim*0.35,'LineWidth',1.0);
                    set(pcLabel(i2),'Color',fg);
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
        cla(axPrev);

        tc = U(:,k);
        tc = tc(idx);

        plot(axPrev, tmin, tc, 'LineWidth', 1.6, 'Color', lineCol);
        grid(axPrev,'on');
        set(axPrev,'XColor',fgDim,'YColor',fgDim,'Color',bgAx);
        title(axPrev, sprintf('PC%d | %.2f%%', k, 100*expl(k)), 'Color',fg, 'FontWeight','bold');
        xlabel(axPrev,'Time (min)','Color',fgDim);
        ylabel(axPrev,'Amplitude (a.u.)','Color',fgDim);
        set(axPrev,'XLim',[0 tmax], 'XTick',xticks);

        safeDrawnow();
    end

    function refreshSelectionUI()
        if isempty(selected)
            set(lb,'String',{'<none>'},'Value',1);
        else
            s = arrayfun(@(x)sprintf('PC%-3d  (%.2f%%)', x, 100*expl(x)), selected, 'uni',0);
            set(lb,'String',s,'Value',1);
        end
        pct = 100 * sum(expl(selected));
        set(txtInfo,'String',sprintf('Selected: %d PCs | Removed: %.2f%%', numel(selected), pct));
        safeDrawnow();
    end

    function prevPage(~,~)
        if page > 1
            page = page - 1;
            renderPage();
        end
    end

    function nextPage(~,~)
        if page < nPages
            page = page + 1;
            renderPage();
        end
    end

    function showHelp(~,~)
        msg = {
            'What PCA does'
            ''
            'PCA decomposes the data into orthogonal components (PCs) ranked by explained variance.'
            'Removing a PC subtracts a structured temporal pattern from all voxels (via reconstruction).'
            ''
            'Use-case'
            'Remove PCs that represent drift, motion-like global patterns, stripes, or scanner artifacts.'
            ''
            'Controls'
            '  Left click  : toggle select (red border means removed)'
            '  Right click : deselect'
            '  Prev/Next   : page through PCs'
            '  Apply       : apply removal and close'
            '  Cancel      : close with no changes'
            };
        helpdlg(msg,'PCA Help');
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
% QC: variance proxy bar plot (UPGRADED COLORS)
% ======================================================================
function make_qc_plot_selected(expl, selected, outFile)

% Strong QC palette
qcBlue = [0.00 0.15 0.55];   % dark blue
qcSel  = [0.15 0.15 0.15];   % dark charcoal (selected/removed)
qcEdge = [0.85 0.10 0.10];   % red edge for removed bars (keeps clarity)

fig = figure('Visible','off','Color','w','Position',[100 100 1100 380]);
ax = axes('Parent',fig);

hb = bar(ax, 100*expl(:), 'FaceColor', qcBlue, 'EdgeColor', 'none'); %#ok<NASGU>
hold(ax,'on');

if ~isempty(selected)
    hs = bar(ax, selected, 100*expl(selected), 'FaceColor', qcSel, 'EdgeColor', qcEdge, 'LineWidth', 1.2); %#ok<NASGU>
end

xlabel(ax,'PC index');
ylabel(ax,'Variance proxy (%)');
title(ax,'PCA variance proxy (dark bars = removed PCs)');
grid(ax,'on');

% Make grid/axes a bit stronger
set(ax,'LineWidth',1.2,'FontSize',11);
set(ax,'GridAlpha',0.25);

saveas(fig, outFile);
close(fig);
end

% ======================================================================
% QC: global mean timecourse before/after (minutes) (UPGRADED COLORS)
% ======================================================================
function make_qc_globalmean_plot(gb, ga, TR, outFile)

T = numel(gb);
tmin = ((0:T-1)*TR)/60;

% Strong QC palette
qcBlue  = [0.00 0.15 0.55];   % dark blue (Before)
qcAfter = [0.20 0.20 0.20];   % dark gray (After)

fig = figure('Visible','off','Color','w','Position',[120 120 1100 380]);
ax = axes('Parent',fig);

plot(ax, tmin, double(gb), 'LineWidth', 1.9, 'Color', qcBlue); hold(ax,'on');
plot(ax, tmin, double(ga), 'LineWidth', 1.9, 'Color', qcAfter);

grid(ax,'on');
xlabel(ax,'Time (min)');
ylabel(ax,'Global mean intensity');
legend(ax, {'Before','After'}, 'Location','best');
title(ax,'Global mean intensity: before vs after PCA removal');

set(ax,'LineWidth',1.2,'FontSize',11);
set(ax,'GridAlpha',0.25);

saveas(fig, outFile);
close(fig);
end

% ======================================================================
% QC: mean image before/after (middle Z)
% ======================================================================
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

% ======================================================================
% QC: exact-look dark grid pages (UPGRADED COLORS)
% ======================================================================
function files = make_qc_grid_dark_exact(U, expl, TR, selected, qcDir, tag)

files = {};
K = size(U,2);
T = size(U,1);

% downsample like GUI
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

% determine which pages to save
savePages = false(1,nPages);
savePages(1) = true;
for s = selected(:)'
    p = ceil(s/perPage);
    if p >= 1 && p <= nPages
        savePages(p) = true;
    end
end

% theme
bgFig   = [0.06 0.06 0.07];
bgAx    = [0.09 0.09 0.10];
fg      = [0.90 0.90 0.92];
fgDim   = [0.70 0.70 0.74];
selRed  = [1.00 0.25 0.25];

% STRONGER blue for QC grid lines
lineCol = [0.35 0.80 1];  % light blue
lineW   = 1.35;              % slightly thicker for visibility

for p = 1:nPages
    if ~savePages(p), continue; end

    fig = figure('Visible','off','Color',bgFig,'Position',[80 60 1500 860]);

    % header (sgtitle not in 2017b)
    annotation(fig,'textbox',[0.03 0.965 0.66 0.03], ...
        'String',sprintf('PCA grid (exact look) — Page %d/%d — tag=%s', p, nPages, tag), ...
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
            tc = U(:,k); tc = tc(idx);
            plot(ax, tmin, tc, 'LineWidth', lineW, 'Color', lineCol);
            grid(ax,'on');

            rr = floor((i-1)/nCol);
            if rr == (nRow-1)
                set(ax,'XTick',xticks,'XTickLabel',arrayfun(@(x)sprintf('%d',round(x)),xticks,'uni',0), ...
                    'XColor',fgDim);
            else
                set(ax,'XTick',[],'XTickLabel',{}, 'XColor',fgDim*0.35);
            end

            % label inside axis
            isSel = any(selected == k);
            labCol = fg; boxCol = fgDim*0.35; lw = 1.0;

            if isSel
                boxCol = selRed; lw = 2.2; labCol = selRed;
                text(ax,0.02,0.78,sprintf('REMOVED'), 'Units','normalized', ...
                    'Color',selRed,'FontWeight','bold','FontSize',10,'Interpreter','none');
            end

            text(ax,0.02,0.92,sprintf('PC%d  %.2f%%',k,100*expl(k)), 'Units','normalized', ...
                'Color',labCol,'FontWeight','bold','FontSize',10,'Interpreter','none');

            set(ax,'XColor',boxCol,'YColor',boxCol,'LineWidth',lw);

        else
            axis(ax,'off');
        end
    end

    outFile = fullfile(qcDir, sprintf('PCA_grid_dark_page%02d_%s.png', p, tag));
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
s.percentExplainedRemoved = 0;
s.explainedPerComponent = [];
s.qcFile = '';
s.qcGlobalMeanFile = '';
s.qcMeanImageFile = '';
s.qcGridFiles = {};
s.nComponents = 0;
s.method = '';
s.applied = false;
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
% choose a step so we get ~5-7 ticks
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