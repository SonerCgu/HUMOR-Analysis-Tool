function out = GA_exportGroupMeanSCMPPT_20260511b(hFig)
% GA_exportGroupMeanSCMPPT_20260511b
% GroupAnalysis PPT-only exporter. No TextBox constructor is used.
out = [];
if nargin < 1 || isempty(hFig) || ~ishghandle(hFig), hFig = gcf; end
if isempty(hFig) || ~ishghandle(hFig), error('Invalid GroupAnalysis figure handle.'); end
S = guidata(hFig);
if isempty(S) || ~isstruct(S), error('Could not read GroupAnalysis GUI state.'); end

[rows,bundles,metaRows] = ga_collect_bundles_b(S);
if isempty(bundles)
    error(['No SCM_GroupExport bundle paths found in GroupAnalysis table column 8.' char(10) ...
           'Open/add SCM bundles first, then run Export PPT again.']);
end

baseWin = ga_default_base_b(S,bundles{1});
R = ga_render_settings_b(S,bundles{1});
sigmaDefault = ga_default_sigma_b(S,bundles{1});
injDefault = 300;

a = inputdlg({ ...
    'Injection END / PI start (sec):', ...
    'Window length (sec):', ...
    'Max minutes to export. Empty = all:', ...
    'Baseline window sec (start end):', ...
    'Spatial smoothing sigma:', ...
    'Start time sec. Empty = 0:'}, ...
    'GroupAnalysis PPT export settings', 1, ...
    {num2str(injDefault),'60','',sprintf('%g %g',baseWin(1),baseWin(2)),num2str(sigmaDefault),''});
if isempty(a), return; end

injEndSec = str2double(strtrim(a{1})); if ~isfinite(injEndSec), injEndSec = NaN; end
winLen = str2double(strtrim(a{2})); if ~isfinite(winLen) || winLen <= 0, winLen = 60; end
maxMin = str2double(strtrim(a{3})); if ~isfinite(maxMin) || maxMin <= 0, maxMin = NaN; end
bw = sscanf(strrep(strtrim(a{4}),'-',' '),'%f');
if numel(bw) >= 2 && all(isfinite(bw(1:2))), baseWin = sort(double(bw(1:2))).'; end
sigma = str2double(strtrim(a{5})); if ~isfinite(sigma) || sigma < 0, sigma = sigmaDefault; end
startSec = str2double(strtrim(a{6})); if ~isfinite(startSec) || startSec < 0, startSec = 0; end

% Let user choose destination BEFORE slow rendering.
startDir = ga_start_dir_b(S);
defName = ['GroupMean_SCM_series_' datestr(now,'yyyymmdd_HHMMSS') '.pptx'];
[f,p] = uiputfile({'*.pptx','PowerPoint (*.pptx)'}, 'Save GroupAnalysis SCM PPT', fullfile(startDir,defName));
if isequal(f,0), return; end
pptFile = fullfile(p,f);
[~,pptBase] = fileparts(pptFile);
assetDir = fullfile(p,[pptBase '_assets']);
tileDir = fullfile(assetDir,'tiles_png');
slideDir = fullfile(assetDir,'slides_png');
ga_mkdir_b(assetDir); ga_mkdir_b(tileDir); ga_mkdir_b(slideDir);

ga_status_b(hFig,S,sprintf('Export PPT: loading %d SCM bundle(s) ...',numel(bundles)));

Glist = cell(numel(bundles),1);
TRs = nan(numel(bundles),1);
nTs = nan(numel(bundles),1);
for i = 1:numel(bundles)
    Glist{i} = ga_load_bundle_b(bundles{i});
    [TRs(i),nTs(i)] = ga_tr_nt_b(Glist{i});
end
TR = median(TRs(isfinite(TRs) & TRs > 0));
if isempty(TR) || ~isfinite(TR) || TR <= 0, error('Could not determine a valid TR from SCM bundles.'); end
nT = min(nTs(isfinite(nTs) & nTs >= 2));
if isempty(nT) || ~isfinite(nT) || nT < 2, error('Could not determine a valid time dimension from SCM bundles.'); end
totalSec = (nT-1) * TR;
starts = startSec:winLen:(floor(totalSec/winLen)*winLen);
if isfinite(maxMin), starts = starts(starts < maxMin*60); end
if isempty(starts), error('No export windows found. Check start time, max minutes, and window length.'); end

% Determine common spatial dimensions and z count from first bundle.
X0 = double(Glist{1}.pscAtlas4D);
if ndims(X0) == 3
    nY = size(X0,1); nX = size(X0,2); nZ = 1;
elseif ndims(X0) == 4
    nY = size(X0,1); nX = size(X0,2); nZ = size(X0,3);
else
    error('Unsupported PSC dimensions in first bundle.');
end

cm = ga_cmap_b(R);
summaryPng = fullfile(slideDir,'slide_000_summary.png');
ga_render_summary_b(summaryPng,metaRows,R,TR,baseWin,winLen,injEndSec,sigma,starts);

slideSpecs = {}; 
nTiles = 0;
perSlide = 6;

ga_status_b(hFig,S,sprintf('Rendering FULL group mean PSC series: %d animals | %d time points | TR %.4g sec | %.2f min',numel(bundles),nT,TR,totalSec/60));
fprintf('[GroupAnalysis export] Rendering FULL group mean PSC series: %d animals | %d time points | TR %.4g sec | %.4g min\n',numel(bundles),nT,TR,totalSec/60);

for z = 1:nZ
    tileFiles = {}; tileLabels = {};
    for wi = 1:numel(starts)
        s0 = starts(wi);
        s1 = s0 + winLen;
        [mapMean, underMean] = ga_group_window_map_b(Glist,metaRows,z,nZ,nY,nX,nT,TR,baseWin,[s0 s1],sigma);
        label = ga_window_label_b(s0,s1,injEndSec,winLen);
        tileFile = fullfile(tileDir,sprintf('tile_z%02d_w%03d_%04.0f_%04.0fs.png',z,wi,s0,s1));
        ga_write_tile_b(tileFile,underMean,mapMean,R,cm);
        tileFiles{end+1} = tileFile; %#ok<AGROW>
        tileLabels{end+1} = label; %#ok<AGROW>
        nTiles = nTiles + 1;
        if mod(nTiles,10) == 0
            ga_status_b(hFig,S,sprintf('Export PPT: rendered %d brain images ...',nTiles));
            fprintf('[GroupAnalysis export] Export PPT: rendered %d brain images ...\n',nTiles);
        end
    end

    nSlides = ceil(numel(tileFiles)/perSlide);
    for si = 1:nSlides
        idx0 = (si-1)*perSlide + 1;
        idx1 = min(si*perSlide,numel(tileFiles));
        idx = idx0:idx1;
        titleStr = sprintf('Group mean SCM | z=%d/%d | %d animals | aligned: %s',z,nZ,numel(bundles),ga_get_char_b(S,'mapFlipMode','Off'));
        footerStr = sprintf('TR=%.4gs | base=%g-%gs | win=%gs | thr=%g | caxis=[%g %g] | alpha=%g%% | alphaMod=%d [%g %g] | sigma=%g | cmap=%s', ...
            TR,baseWin(1),baseWin(2),winLen,R.threshold,R.caxis(1),R.caxis(2),R.alphaPercent,double(R.alphaModOn),R.modMin,R.modMax,sigma,R.colormapName);
        bgPng = fullfile(slideDir,sprintf('slide_z%02d_%02d_background.png',z,si));
        ga_render_data_bg_b(bgPng,tileLabels(idx),cm,R.caxis,titleStr,footerStr);
        spec = struct();
        spec.bg = bgPng;
        spec.tiles = tileFiles(idx);
        spec.labels = tileLabels(idx);
        slideSpecs{end+1} = spec; %#ok<AGROW>
    end
end

ga_status_b(hFig,S,'Export PPT: writing PowerPoint ...');
ga_write_ppt_b(pptFile,summaryPng,slideSpecs);

fprintf('[GroupAnalysis export] Export PPT complete: %d brain PNGs, %d data slides + summary + PPT\n',nTiles,numel(slideSpecs));
fprintf('[GroupAnalysis export] Tiles: %s\n',tileDir);
fprintf('[GroupAnalysis export] Slides: %s\n',slideDir);
fprintf('[GroupAnalysis export] PPT: %s\n',pptFile);
ga_status_b(hFig,S,['Export PPT complete: ' pptFile]);
out = pptFile;
end

function [rows,bundles,metaRows] = ga_collect_bundles_b(S)
rows = []; bundles = {}; metaRows = struct('row',{},'animal',{},'session',{},'scan',{},'side',{},'flipLR',{},'bundle',{});
if ~isfield(S,'subj') || isempty(S.subj) || size(S.subj,2) < 8, return; end
n = size(S.subj,1);
for r = 1:n
    active = true;
    try, active = ga_to_logical_b(S.subj{r,1}); catch, active = true; end
    if ~active, continue; end
    bf = ''; try, bf = strtrim(char(S.subj{r,8})); catch, end
    if isempty(bf) || exist(bf,'file') ~= 2, continue; end
    rows(end+1) = r; %#ok<AGROW>
    bundles{end+1} = bf; %#ok<AGROW>
    m = struct();
    m.row = r;
    m.animal = ga_cellstr_b(S,r,2,'Animal');
    m.session = ga_cellstr_b(S,r,3,'');
    m.scan = ga_cellstr_b(S,r,4,'');
    m.side = ga_side_b(S,r);
    m.flipLR = ga_should_flip_b(S,m.side);
    m.bundle = bf;
    metaRows(end+1) = m; %#ok<AGROW>
end
end

function s = ga_cellstr_b(S,r,c,fb)
s = fb;
try
    if size(S.subj,2) >= c && ~isempty(S.subj{r,c})
        s = strtrim(char(S.subj{r,c}));
    end
catch
end
end

function side = ga_side_b(S,r)
side = 'Unknown';
try
    if isfield(S,'rowPacapSide') && numel(S.rowPacapSide) >= r && ~isempty(S.rowPacapSide{r})
        side = strtrim(char(S.rowPacapSide{r})); return;
    end
catch
end
for c = 1:min(10,size(S.subj,2))
    try
        x = strtrim(char(S.subj{r,c}));
        if strcmpi(x,'Left') || strcmpi(x,'Right'), side = x; return; end
    catch
    end
end
end

function tf = ga_should_flip_b(S,side)
tf = false;
mode = ga_get_char_b(S,'mapFlipMode','Off');
ref = ga_get_char_b(S,'mapRefPacapSide','Left');
if strcmpi(mode,'Flip right-injected animals') && strcmpi(side,'Right'), tf = true; end
if strcmpi(mode,'Flip left-injected animals') && strcmpi(side,'Left'), tf = true; end
if strcmpi(mode,'Align to Reference Hemisphere')
    if strcmpi(ref,'Left') && strcmpi(side,'Right'), tf = true; end
    if strcmpi(ref,'Right') && strcmpi(side,'Left'), tf = true; end
end
end

function tf = ga_to_logical_b(x)
tf = false;
try
    if islogical(x), tf = logical(x(1));
    elseif isnumeric(x), tf = isfinite(x(1)) && x(1) ~= 0;
    else
        s = lower(strtrim(char(x)));
        tf = any(strcmp(s,{'1','true','yes','y','on'}));
    end
catch
    tf = false;
end
end

function G = ga_load_bundle_b(bf)
L = load(bf); G = [];
if isfield(L,'G') && isstruct(L.G)
    G = L.G;
else
    fn = fieldnames(L);
    for k = 1:numel(fn)
        v = L.(fn{k});
        if isstruct(v) && (isfield(v,'pscAtlas4D') || isfield(v,'psc4D') || isfield(v,'PSC') || isfield(v,'underlayAtlas'))
            G = v; break;
        end
    end
end
if isempty(G) || ~isstruct(G), error('No SCM group bundle struct found in %s',bf); end
if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
    flds = {'psc4D','PSC4D','PSC','functionalPSC','Ipsc','I'};
    for k = 1:numel(flds)
        f = flds{k};
        if isfield(G,f) && ~isempty(G.(f)) && isnumeric(G.(f))
            X = G.(f);
            if (ndims(X)==3 && size(X,3)>=2) || (ndims(X)==4 && size(X,4)>=2)
                G.pscAtlas4D = X; break;
            end
        end
    end
end
if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
    error('Could not find full PSC time-series. Expected G.pscAtlas4D in %s',bf);
end
end

function [TR,nT] = ga_tr_nt_b(G)
TR = NaN; nT = NaN;
try, TR = double(G.TR(1)); catch, end
if (~isfinite(TR) || TR <= 0) && isfield(G,'tsec') && numel(G.tsec) >= 2
    TR = median(diff(double(G.tsec(:))));
end
if (~isfinite(TR) || TR <= 0) && isfield(G,'tmin') && numel(G.tmin) >= 2
    TR = 60 * median(diff(double(G.tmin(:))));
end
X = G.pscAtlas4D;
if ndims(X) == 3, nT = size(X,3); elseif ndims(X) == 4, nT = size(X,4); end
end

function [mapMean, underMean] = ga_group_window_map_b(Glist,metaRows,z,nZ,nY,nX,nT,TR,baseWin,sigWin,sigma)
N = numel(Glist);
stackMap = nan(nY,nX,N);
stackUnder = nan(nY,nX,N);
for i = 1:N
    G = Glist{i};
    X = double(G.pscAtlas4D);
    if ndims(X) == 3
        P = X(:,:,1:min(nT,size(X,3)));
    else
        zz = min(max(1,z),size(X,3));
        P = squeeze(X(:,:,zz,1:min(nT,size(X,4))));
    end
    b0 = max(1,min(size(P,3),floor(baseWin(1)/TR)+1));
    b1 = max(1,min(size(P,3),floor(baseWin(2)/TR)+1));
    s0 = max(1,min(size(P,3),floor(sigWin(1)/TR)+1));
    s1 = max(1,min(size(P,3),ceil(sigWin(2)/TR)));
    if b1 < b0, tmp=b0; b0=b1; b1=tmp; end
    if s1 < s0, tmp=s0; s0=s1; s1=tmp; end
    baseMap = mean(P(:,:,b0:b1),3);
    sigMap = mean(P(:,:,s0:s1),3);
    M = sigMap - baseMap;
    if sigma > 0, M = ga_smooth2_b(M,sigma); end
    U = ga_underlay_for_z_b(G,z,nZ,[nY nX]);
    if metaRows(i).flipLR
        M = fliplr(M);
        U = fliplr(U);
    end
    stackMap(:,:,i) = M;
    stackUnder(:,:,i) = U;
end
mapMean = ga_nanmean3_b(stackMap);
underMean = ga_nanmean3_b(stackUnder);
mapMean(~isfinite(mapMean)) = 0;
underMean(~isfinite(underMean)) = 0;
end

function U = ga_underlay_for_z_b(G,z,nZ,sz)
U = [];
names = {'underlayAtlas','underlay2D','underlayAtlas2D','commonUnderlay','brainImage','bg','bgAtlas','meanAtlas','anatomyAtlas'};
for k = 1:numel(names)
    if isfield(G,names{k}) && ~isempty(G.(names{k}))
        U = G.(names{k}); break;
    end
end
if isempty(U), U = zeros(sz); end
U = squeeze(double(U));
if ndims(U) == 3
    if size(U,3) == 3 && nZ == 1
        U = 0.2989*U(:,:,1) + 0.5870*U(:,:,2) + 0.1140*U(:,:,3);
    else
        zz = min(max(1,z),size(U,3));
        U = U(:,:,zz);
    end
elseif ndims(U) > 3
    U = squeeze(U);
    if ndims(U) > 2, U = U(:,:,1); end
end
U = ga_resize_b(U,sz);
end

function R = ga_render_settings_b(S,bf)
G = [];
try, G = ga_load_bundle_b(bf); catch, end
R = struct();
R.threshold = ga_get_num_b(S,'mapThreshold',NaN);
R.caxis = ga_get_vec_b(S,'mapCaxis',[NaN NaN]);
R.alphaPercent = ga_get_num_b(S,'mapAlphaPercent',NaN);
R.alphaModOn = ga_get_logical_b(S,'mapAlphaModOn',true);
R.modMin = ga_get_num_b(S,'mapModMin',NaN);
R.modMax = ga_get_num_b(S,'mapModMax',NaN);
R.colormapName = ga_get_char_b(S,'mapColormap','');
if ~isempty(G) && isfield(G,'display') && isstruct(G.display)
    D = G.display;
    if ~isfinite(R.threshold) && isfield(D,'threshold') && ~isempty(D.threshold), R.threshold = double(D.threshold(1)); end
    if any(~isfinite(R.caxis)) && isfield(D,'caxis') && numel(D.caxis)>=2, R.caxis = double(D.caxis(1:2)); end
    if ~isfinite(R.alphaPercent) && isfield(D,'alphaPercent') && ~isempty(D.alphaPercent), R.alphaPercent = double(D.alphaPercent(1)); end
    if isfield(D,'alphaModOn') && ~isempty(D.alphaModOn), R.alphaModOn = logical(D.alphaModOn(1)); end
    if ~isfinite(R.modMin) && isfield(D,'modMin') && ~isempty(D.modMin), R.modMin = double(D.modMin(1)); end
    if ~isfinite(R.modMax) && isfield(D,'modMax') && ~isempty(D.modMax), R.modMax = double(D.modMax(1)); end
    if isempty(R.colormapName) && isfield(D,'colormapName') && ~isempty(D.colormapName), R.colormapName = char(D.colormapName); end
    if isfield(D,'cmapMatrix') && ~isempty(D.cmapMatrix), R.cmapMatrix = double(D.cmapMatrix); end
end
if ~isfinite(R.threshold), R.threshold = 0; end
if numel(R.caxis)<2 || any(~isfinite(R.caxis(1:2))) || R.caxis(2)==R.caxis(1), R.caxis = [0 100]; end
if R.caxis(2) < R.caxis(1), R.caxis = fliplr(R.caxis); end
if ~isfinite(R.alphaPercent), R.alphaPercent = 100; end
R.alphaPercent = max(0,min(100,R.alphaPercent));
if ~isfinite(R.modMin), R.modMin = 15; end
if ~isfinite(R.modMax), R.modMax = 30; end
if R.modMax < R.modMin, tmp=R.modMin; R.modMin=R.modMax; R.modMax=tmp; end
if isempty(R.colormapName), R.colormapName = 'blackbdy_iso'; end
end

function sigma = ga_default_sigma_b(S,bf)
sigma = ga_get_num_b(S,'mapSigma',NaN);
if isfinite(sigma), return; end
try
    G = ga_load_bundle_b(bf);
    if isfield(G,'sigma') && ~isempty(G.sigma) && isfinite(G.sigma(1)), sigma = double(G.sigma(1)); end
catch
end
if ~isfinite(sigma), sigma = 1; end
end

function bw = ga_default_base_b(S,bf)
bw = [30 240];
try
    if isfield(S,'mapGlobalBaseSec') && numel(S.mapGlobalBaseSec) >= 2
        v = double(S.mapGlobalBaseSec(1:2));
        if all(isfinite(v)) && v(2)>v(1), bw = v(:)'; return; end
    end
catch
end
try
    G = ga_load_bundle_b(bf);
    if isfield(G,'baseWindowSec') && numel(G.baseWindowSec) >= 2
        v = double(G.baseWindowSec(1:2));
        if all(isfinite(v)) && v(2)>v(1), bw = v(:)'; return; end
    end
catch
end
end

function ga_write_tile_b(outFile,U,M,R,cm)
U = ga_gray01_b(U);
bg = repmat(U,[1 1 3]);
M = double(M); M(~isfinite(M)) = 0;
thr = abs(R.threshold);
mag = abs(M);
showMask = isfinite(M) & M > thr;
effLo = max(R.modMin,thr);
effHi = R.modMax;
if effHi <= effLo, effHi = effLo + eps; end
if ~R.alphaModOn
    A = (R.alphaPercent/100) .* double(showMask);
else
    ramp = (mag-effLo) ./ max(eps,(effHi-effLo));
    ramp(~isfinite(ramp)) = 0;
    ramp = min(max(ramp,0),1);
    ramp(mag <= effLo) = 0;
    A = (R.alphaPercent/100) .* ramp .* double(showMask);
end
A = min(max(A,0),1);
idx = round((M - R.caxis(1)) ./ max(eps,(R.caxis(2)-R.caxis(1))) * (size(cm,1)-1)) + 1;
idx = max(1,min(size(cm,1),idx));
ov = reshape(cm(idx(:),:),[size(M,1) size(M,2) 3]);
rgb = bg .* (1 - repmat(A,[1 1 3])) + ov .* repmat(A,[1 1 3]);
rgb = min(max(rgb,0),1);
imwrite(rgb,outFile);
end

function ga_render_data_bg_b(outFile,lblList,cm,caxV,titleStr,footerStr)
fig = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(fig,'Units','pixels','Position',[100 100 1920 1080]);
axes('Parent',fig,'Units','normalized','Position',[0 0 1 1],'Visible','off');
annotation(fig,'textbox',[0.02 0.935 0.96 0.045],'String',titleStr,'Color','w','EdgeColor','none','FontName','Arial','FontSize',20,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');

% Manual non-squeezed colorbar.
axCB = axes('Parent',fig,'Units','normalized','Position',[0.042 0.18 0.030 0.64]);
grad = repmat((1:256).',1,24);
imagesc(axCB,grad);
set(axCB,'YDir','normal','XTick',[],'YAxisLocation','right','YColor','w','XColor','w','Color',[0 0 0],'FontName','Arial','FontSize',12,'LineWidth',1.0);
colormap(axCB,cm);
yt = linspace(1,256,6);
ylab = linspace(caxV(1),caxV(2),6);
set(axCB,'YTick',yt,'YTickLabel',arrayfun(@(x)sprintf('%g',x),ylab,'UniformOutput',false));
title(axCB,'PSC (%)','Color','w','FontName','Arial','FontSize',13,'FontWeight','bold');
ylabel(axCB,'Signal change (%)','Color','w','FontName','Arial','FontSize',12,'FontWeight','bold');

[pos,labpos] = ga_slide_positions_b(numel(lblList));
for k = 1:numel(lblList)
    annotation(fig,'textbox',labpos(k,:),'String',lblList{k},'Color',[1 1 1],'EdgeColor','none','FontName','Arial','FontSize',17,'FontWeight','bold','HorizontalAlignment','center','VerticalAlignment','middle','Interpreter','none');
end
annotation(fig,'textbox',[0.36 0.030 0.60 0.055],'String',footerStr,'Color',[1 1 1],'EdgeColor','none','FontName','Arial','FontSize',14,'FontWeight','bold','HorizontalAlignment','right','Interpreter','none');
print(fig,outFile,'-dpng','-r150','-opengl');
close(fig);
end

function ga_render_summary_b(outFile,metaRows,R,TR,baseWin,winLen,injEndSec,sigma,starts)
fig = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(fig,'Units','pixels','Position',[100 100 1920 1080]);
axes('Parent',fig,'Units','normalized','Position',[0 0 1 1],'Visible','off');
annotation(fig,'textbox',[0.03 0.925 0.94 0.055],'String','GroupAnalysis SCM Time-Series Export','Color','w','EdgeColor','none','FontName','Arial','FontSize',26,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
info = sprintf('N=%d | TR=%.4gs | baseline=%g-%gs | window=%gs | PI starts at %gs | caxis=[%g %g] | thr=%g | alpha=%g%% | alphaMod=%d [%g %g] | sigma=%g | cmap=%s', ...
    numel(metaRows),TR,baseWin(1),baseWin(2),winLen,injEndSec,R.caxis(1),R.caxis(2),R.threshold,R.alphaPercent,double(R.alphaModOn),R.modMin,R.modMax,sigma,R.colormapName);
annotation(fig,'textbox',[0.04 0.870 0.92 0.045],'String',info,'Color',[0.90 0.95 1.00],'EdgeColor','none','FontName','Arial','FontSize',14,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');

cols = {'Row','Animal','Session','Scan','Injection side','Flip LR','Bundle'};
cw = [0.055 0.145 0.105 0.125 0.145 0.085 0.300];
x0 = 0.045; y0 = 0.790; rowH = 0.080; headH = 0.070;
x = x0;
for c = 1:numel(cols)
    annotation(fig,'rectangle',[x y0 cw(c) headH],'FaceColor',[0.12 0.18 0.25],'Color',[0.55 0.65 0.75]);
    annotation(fig,'textbox',[x+0.006 y0+0.006 cw(c)-0.012 headH-0.012],'String',cols{c},'Color',[1 1 1],'EdgeColor','none','FontName','Arial','FontSize',17,'FontWeight','bold','HorizontalAlignment','left','VerticalAlignment','middle','Interpreter','none');
    x = x + cw(c) + 0.010;
end
for r = 1:numel(metaRows)
    yy = y0 - r*rowH;
    if yy < 0.13, break; end
    vals = {num2str(metaRows(r).row),metaRows(r).animal,metaRows(r).session,metaRows(r).scan,metaRows(r).side,num2str(double(metaRows(r).flipLR)),ga_short_b(metaRows(r).bundle,55)};
    x = x0;
    for c = 1:numel(cols)
        if mod(r,2)==1, fc = [0.025 0.025 0.028]; else, fc = [0.055 0.055 0.060]; end
        annotation(fig,'rectangle',[x yy cw(c) rowH],'FaceColor',fc,'Color',[0.28 0.32 0.36]);
        col = [0.92 0.92 0.94];
        if c == 5 && strcmpi(vals{c},'Right'), col = [1.00 0.78 0.45]; end
        if c == 5 && strcmpi(vals{c},'Left'),  col = [0.50 0.78 1.00]; end
        annotation(fig,'textbox',[x+0.006 yy+0.008 cw(c)-0.012 rowH-0.016],'String',vals{c},'Color',col,'EdgeColor','none','FontName','Arial','FontSize',15,'FontWeight','bold','HorizontalAlignment','left','VerticalAlignment','middle','Interpreter','none');
        x = x + cw(c) + 0.010;
    end
end
winTxt = sprintf('Windows exported: %d | first: %.0f-%.0fs | last: %.0f-%.0fs',numel(starts),starts(1),starts(1)+winLen,starts(end),starts(end)+winLen);
annotation(fig,'textbox',[0.04 0.045 0.92 0.055],'String',winTxt,'Color',[0.85 0.95 1.00],'EdgeColor','none','FontName','Arial','FontSize',16,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
print(fig,outFile,'-dpng','-r150','-opengl');
close(fig);
end

function ga_write_ppt_b(pptFile,summaryPng,slideSpecs)
if exist(pptFile,'file') == 2
    try, delete(pptFile); catch, error('Could not overwrite existing PPT file: %s',pptFile); end
end
if ~isempty(which('mlreportgen.ppt.Presentation'))
    import mlreportgen.ppt.*
    ppt = [];
    try
        ppt = Presentation(pptFile); open(ppt);
        slide = add(ppt,'Blank');
        pic = Picture(summaryPng); pic.X='0in'; pic.Y='0in'; pic.Width='13.333in'; pic.Height='7.5in'; add(slide,pic);
        for i = 1:numel(slideSpecs)
            sp = slideSpecs{i};
            slide = add(ppt,'Blank');
            bg = Picture(sp.bg); bg.X='0in'; bg.Y='0in'; bg.Width='13.333in'; bg.Height='7.5in'; add(slide,bg);
            [pos,~] = ga_slide_positions_b(numel(sp.tiles));
            for k = 1:numel(sp.tiles)
                if exist(sp.tiles{k},'file') ~= 2, continue; end
                [xIn,yIn,wIn,hIn] = ga_fit_pic_in_cell_b(sp.tiles{k},pos(k,:));
                p2 = Picture(sp.tiles{k});
                p2.X = sprintf('%.4fin',xIn);
                p2.Y = sprintf('%.4fin',yIn);
                p2.Width = sprintf('%.4fin',wIn);
                p2.Height = sprintf('%.4fin',hIn);
                add(slide,p2);
            end
        end
        close(ppt);
    catch ME
        try, if ~isempty(ppt), close(ppt); end, catch, end
        error('mlreportgen PPT export failed: %s',ME.message);
    end
elseif ispc && exist('actxserver','file') == 2
    ppt = []; pres = [];
    try
        ppt = actxserver('PowerPoint.Application'); ppt.Visible = 1;
        pres = ppt.Presentations.Add;
        sw = pres.PageSetup.SlideWidth; sh = pres.PageSetup.SlideHeight;
        slide = pres.Slides.Add(1,12);
        slide.Shapes.AddPicture(summaryPng,0,1,0,0,sw,sh);
        for i = 1:numel(slideSpecs)
            sp = slideSpecs{i};
            slide = pres.Slides.Add(i+1,12);
            slide.Shapes.AddPicture(sp.bg,0,1,0,0,sw,sh);
            [pos,~] = ga_slide_positions_b(numel(sp.tiles));
            for k = 1:numel(sp.tiles)
                [xIn,yIn,wIn,hIn] = ga_fit_pic_in_cell_b(sp.tiles{k},pos(k,:));
                slide.Shapes.AddPicture(sp.tiles{k},0,1,xIn*72,yIn*72,wIn*72,hIn*72);
            end
        end
        pres.SaveAs(pptFile); pres.Close; ppt.Quit;
    catch ME
        try, if ~isempty(pres), pres.Close; end, catch, end
        try, if ~isempty(ppt), ppt.Quit; end, catch, end
        error('PowerPoint COM export failed: %s',ME.message);
    end
else
    error('No PowerPoint writer found. Slide PNGs were saved, but PPTX was not created.');
end
pause(0.2);
if exist(pptFile,'file') ~= 2, error('PPT file was not created: %s',pptFile); end
end

function [xIn,yIn,wIn,hIn] = ga_fit_pic_in_cell_b(imgFile,cellNorm)
slideW = 13.333; slideH = 7.5;
x = cellNorm(1); y = cellNorm(2); w = cellNorm(3); h = cellNorm(4);
cellW = w*slideW; cellH = h*slideH;
try
    info = imfinfo(imgFile);
    asp = info.Width / max(1,info.Height);
catch
    asp = cellW / max(eps,cellH);
end
cellAsp = cellW / max(eps,cellH);
if asp >= cellAsp
    wIn = cellW;
    hIn = wIn / asp;
else
    hIn = cellH;
    wIn = hIn * asp;
end
xIn = x*slideW + (cellW-wIn)/2;
yIn = (1 - y - h)*slideH + (cellH-hIn)/2;
end

function [pos,labpos] = ga_slide_positions_b(n)
x0 = 0.135; x1 = 0.970; yBot = 0.145; yTop = 0.805;
rowGap = 0.100; colGap = 0.030;
cellH = (yTop-yBot-rowGap)/2;
cellW = (x1-x0-2*colGap)/3;
pos = zeros(max(1,n),4); labpos = zeros(max(1,n),4);
for k = 1:max(1,n)
    if k <= 3
        cc = k-1; y = yBot + cellH + rowGap;
    else
        cc = k-4; y = yBot;
    end
    x = x0 + cc*(cellW+colGap);
    pos(k,:) = [x y cellW cellH];
    labpos(k,:) = [x y+cellH+0.008 cellW 0.045];
end
end

function label = ga_window_label_b(s0,s1,injEndSec,winLen)
if isfinite(injEndSec)
    if s1 <= injEndSec
        label = sprintf('Pre %.1f-%.1f min\n%.0f-%.0fs',s0/60,s1/60,s0,s1);
    elseif s0 < injEndSec && s1 > injEndSec
        label = sprintf('Injection end\n%.0f-%.0fs',s0,s1);
    else
        piIdx = floor((s0-injEndSec)/winLen) + 1;
        if piIdx < 1, piIdx = 1; end
        label = sprintf('PI %d min\n%.0f-%.0fs',piIdx,s0,s1);
    end
else
    label = sprintf('%.1f-%.1f min\n%.0f-%.0fs',s0/60,s1/60,s0,s1);
end
end

function cm = ga_cmap_b(R)
if isfield(R,'cmapMatrix') && ~isempty(R.cmapMatrix) && size(R.cmapMatrix,2)==3
    cm = double(R.cmapMatrix); cm = max(0,min(1,cm)); return;
end
name = lower(strtrim(char(R.colormapName)));
n = 256;
switch name
    case 'blackbdy_iso'
        if exist('blackbdy_iso','file') == 2, cm = blackbdy_iso(n); else, cm = hot(n); end
    case 'hot'
        cm = hot(n);
    case 'parula'
        cm = parula(n);
    case 'turbo'
        if exist('turbo','file') == 2, cm = turbo(n); else, cm = hot(n); end
    case 'jet'
        cm = jet(n);
    case 'gray'
        cm = gray(n);
    case 'winter_brain_fsl'
        if exist('winter_brain_fsl','file') == 2, cm = winter_brain_fsl(n); else, cm = winter(n); end
    otherwise
        cm = hot(n);
end
cm = max(0,min(1,cm));
end

function G = ga_gray01_b(U)
U = double(U);
if ndims(U) == 3 && size(U,3) == 3
    U = 0.2989*U(:,:,1) + 0.5870*U(:,:,2) + 0.1140*U(:,:,3);
end
U(~isfinite(U)) = 0;
v = U(:); v = v(isfinite(v));
if isempty(v), G = zeros(size(U)); return; end
lo = ga_prctile_b(v,0.5); hi = ga_prctile_b(v,99.5);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(v); hi = max(v);
end
if hi <= lo, G = zeros(size(U)); return; end
G = (U-lo) ./ (hi-lo);
G = min(max(G,0),1);
end

function B = ga_resize_b(A,sz)
if numel(sz)>2, sz = sz(1:2); end
A = double(A);
if isequal(size(A),sz), B = A; return; end
try
    B = imresize(A,sz,'bilinear');
catch
    [Y,X] = size(A);
    [xq,yq] = meshgrid(linspace(1,X,sz(2)),linspace(1,Y,sz(1)));
    B = interp2(A,xq,yq,'linear',0);
end
end

function B = ga_smooth2_b(A,sigma)
if sigma <= 0, B = A; return; end
try, B = imgaussfilt(A,sigma); return; catch, end
r = max(1,ceil(3*sigma));
x = -r:r; g = exp(-(x.^2)/(2*sigma^2)); g = g./sum(g);
B = conv2(conv2(double(A),g,'same'),g','same');
end

function M = ga_nanmean3_b(X)
n = sum(isfinite(X),3);
X(~isfinite(X)) = 0;
M = sum(X,3) ./ max(1,n);
M(n==0) = NaN;
end

function q = ga_prctile_b(v,p)
try, q = prctile(v,p); return; catch, end
v = sort(v(:)); n = numel(v);
if n == 0, q = NaN; return; end
k = 1 + (n-1)*(p/100);
k1 = floor(k); k2 = ceil(k);
k1 = max(1,min(n,k1)); k2 = max(1,min(n,k2));
if k1 == k2, q = v(k1); else, q = v(k1) + (k-k1)*(v(k2)-v(k1)); end
end

function d = ga_start_dir_b(S)
d = pwd;
try, if isfield(S,'outDir') && ~isempty(S.outDir) && exist(S.outDir,'dir') == 7, d = char(S.outDir); return; end, catch, end
try, if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(S.opt.startDir,'dir') == 7, d = char(S.opt.startDir); return; end, catch, end
end

function v = ga_get_num_b(S,f,fb)
v = fb;
try, if isfield(S,f) && ~isempty(S.(f)), v = double(S.(f)(1)); end, catch, end
if ~isfinite(v), v = fb; end
end

function v = ga_get_vec_b(S,f,fb)
v = fb;
try
    if isfield(S,f) && numel(S.(f)) >= 2
        vv = double(S.(f)(1:2));
        if all(isfinite(vv)), v = vv(:)'; end
    end
catch
end
end

function v = ga_get_logical_b(S,f,fb)
v = fb;
try, if isfield(S,f) && ~isempty(S.(f)), v = logical(S.(f)(1)); end, catch, end
end

function s = ga_get_char_b(S,f,fb)
s = fb;
try, if isfield(S,f) && ~isempty(S.(f)), s = strtrim(char(S.(f))); end, catch, end
end

function s = ga_short_b(s,n)
try, s = char(s); catch, s = ''; end
if numel(s) > n, s = [s(1:max(1,n-3)) '...']; end
end

function ga_mkdir_b(d)
if exist(d,'dir') ~= 7
    ok = mkdir(d);
    if ~ok, error('Could not create folder: %s',d); end
end
end

function ga_status_b(hFig,S,msg)
try, fprintf('[GroupAnalysis export] %s\n',msg); catch, end
try, set(hFig,'Name',['GroupAnalysis - ' msg]); catch, end
names = {'txtStatus','statusText','infoText','txtInfo','hStatus','status'};
for k = 1:numel(names)
    try
        if isfield(S,names{k}) && ishghandle(S.(names{k}))
            set(S.(names{k}),'String',msg);
        end
    catch
    end
end
try, drawnow limitrate; catch, drawnow; end
end
