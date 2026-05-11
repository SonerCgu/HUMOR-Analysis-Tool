function out = GA_exportGroupAnalysisPPTBundleFix_20260511(fig, mode)
% GroupAnalysis full SCM/PPT exporter hotfix.
% Writes SCM_gui-compatible G bundles and renders full group mean PSC series.

if nargin < 1 || isempty(fig) || ~ishandle(fig), fig = gcf; end
if nargin < 2 || isempty(mode), mode = 'ppt'; end

if islogical(mode)
    if mode, mode = 'ppt'; else, mode = 'scm'; end
elseif isnumeric(mode) && isscalar(mode)
    if mode ~= 0, mode = 'ppt'; else, mode = 'scm'; end
else
    mode = lower(strtrim(char(mode)));
end

switch lower(mode)
    case {'ppt','powerpoint','exportppt'}
        out = localExportPPT(fig);
    case {'scm','bundle','data','exportdata'}
        out = localExportSCM(fig);
    otherwise
        error('Unknown mode. Use GA_exportGroupAnalysisPPTBundleFix_20260511(gcf,''ppt'') or (gcf,''scm'').');
end
end

function outFile = localExportSCM(fig)
statusMsg(fig,'Export Data SCM: collecting full SCM bundles ...');
B = collectBundles(fig);
if isempty(B)
    error(['No full SCM_GroupExport bundles found.' char(10) 'Need source files containing G.pscAtlas4D.']);
end
[G,rep] = makeGroupMeanG(B);
outDir = exportDir(fig,B);
safeMkdir(outDir);
outFile = fullfile(outDir, ['GroupAnalysis_FULL_SCM_GroupExport_' datestr(now,'yyyymmdd_HHMMSS') '.mat']);
save(outFile,'G','-v7.3');
statusMsg(fig, sprintf('Export Data SCM complete: %d animals, %d time points, TR %.6g sec, %.2f min', rep.nAnimals, rep.nT, rep.TR, rep.totalMin));
fprintf('\n[GroupAnalysis export] Saved SCM_gui-compatible G bundle:\n%s\n', outFile);
fprintf('[GroupAnalysis export] nAnimals=%d | nT=%d | TR=%.9g sec | total=%.4f min\n', rep.nAnimals, rep.nT, rep.TR, rep.totalMin);
end

function pptPath = localExportPPT(fig)
% GA_PPT_BUSY_LOCK_20260511_FASTPATCH
pptPath = '';
busyKey = 'GA_EXPORT_PPT_BUSY_20260511_FASTPATCH';
try
    if isappdata(fig,busyKey) && isequal(getappdata(fig,busyKey),true)
        fprintf('[GroupAnalysis export] PPT export already running. Duplicate callback ignored.\n');
        return;
    end
    setappdata(fig,busyKey,true);
catch
end
cleanupBusy_20260511 = onCleanup(@()GA_clearPptBusy_20260511(fig,busyKey)); %#ok<NASGU>

cfgFast_20260511 = GA_askPptCfgFast_20260511();
if isempty(cfgFast_20260511)
    return;
end
try
    setappdata(fig,'GA_PPT_CFG_PREFETCH_20260511',cfgFast_20260511);
catch
end


statusMsg(fig,'Export PPT: collecting full SCM bundles ...');
B = collectBundles(fig);
if isempty(B)
    error(['No full SCM_GroupExport bundles found for PPT export.' char(10) 'Static 2D group maps are ignored.']);
end
[G,rep] = makeGroupMeanG(B);
fprintf('\n[GroupAnalysis export] Rendering FULL group mean PSC series: %d animals | %d time points | TR %.9g sec | %.4f min\n', rep.nAnimals, rep.nT, rep.TR, rep.totalMin);
cfg = [];
try
    if isappdata(fig,'GA_PPT_CFG_PREFETCH_20260511')
        cfg = getappdata(fig,'GA_PPT_CFG_PREFETCH_20260511');
        rmappdata(fig,'GA_PPT_CFG_PREFETCH_20260511');
    end
catch
    cfg = [];
end
if isempty(cfg)
    cfg = askPptCfg(G);
end
if isempty(cfg), pptPath = ''; return; end
outRoot = exportDir(fig,B);
stamp = datestr(now,'yyyymmdd_HHMMSS');
outDir = fullfile(outRoot, ['GroupMean_SCM_PPT_' stamp]);
tileDir = fullfile(outDir,'tiles_png');
slideDir = fullfile(outDir,'slides_png');
safeMkdir(tileDir); safeMkdir(slideDir);
[slidePNGs,nTiles] = renderGroupSeries(G,cfg,tileDir,slideDir,fig);
if isempty(slidePNGs), error('No SCM windows were exported. Check TR/window settings.'); end
pptPath = fullfile(outDir, ['GroupMean_SCM_series_' stamp '.pptx']);
if canUsePPT()
    writePPT(pptPath,slidePNGs);
    statusMsg(fig, sprintf('Export PPT complete: %d brain PNGs, %d slides + PPT', nTiles, numel(slidePNGs)));
else
    pptPath = '';
    statusMsg(fig, sprintf('Export PPT complete: %d brain PNGs, %d slide PNGs only', nTiles, numel(slidePNGs)));
end
fprintf('[GroupAnalysis export] Tiles: %s\n', tileDir);
fprintf('[GroupAnalysis export] Slides: %s\n', slideDir);
if ~isempty(pptPath), fprintf('[GroupAnalysis export] PPT: %s\n', pptPath); end
end

function B = collectBundles(fig)
paths = collectPaths(fig);
paths = unique(paths,'stable');
B = struct('G',{},'file',{});
for i = 1:numel(paths)
    try
        G = loadG(paths{i});
        if ~isempty(G)
            B(end+1).G = G;
            B(end).file = paths{i};
        end
    catch ME
        fprintf('[GroupAnalysis export] Skipped %s: %s\n', paths{i}, ME.message);
    end
end

if isempty(B)
    try
        [f,p] = uigetfile({'SCM_GroupExport*.mat;*.mat','SCM group bundles (*.mat)'}, 'Select SCM_GroupExport bundles', 'MultiSelect','on');
        if isequal(f,0), return; end
        if ischar(f), f = {f}; end
        for k = 1:numel(f)
            fullf = fullfile(p,f{k});
            try
                G = loadG(fullf);
                if ~isempty(G)
                    B(end+1).G = G;
                    B(end).file = fullf;
                end
            catch ME
                fprintf('[GroupAnalysis export] Skipped selected file %s: %s\n', fullf, ME.message);
            end
        end
    catch
    end
end
fprintf('[GroupAnalysis export] Found %d full SCM bundle(s).\n', numel(B));
end

function paths = collectPaths(fig)
paths = {};
try
    hT = findall(fig,'Type','uitable');
    for i = 1:numel(hT)
        try, paths = [paths pathsFromAny(get(hT(i),'Data'),0)]; catch, end
    end
catch
end
try, paths = [paths pathsFromAny(getappdata(fig),0)]; catch, end
try, paths = [paths pathsFromAny(get(fig,'UserData'),0)]; catch, end
try
    kids = findall(fig);
    for i = 1:min(numel(kids),300)
        try, paths = [paths pathsFromAny(get(kids(i),'UserData'),0)]; catch, end
    end
catch
end
clean = {};
for i = 1:numel(paths)
    p = strtrim(char(paths{i}));
    if exist(p,'file') == 2 && ~isempty(regexpi(p,'\.mat$','once'))
        clean{end+1} = p;
    end
end
paths = unique(clean,'stable');
end

function paths = pathsFromAny(x,depth)
paths = {};
if depth > 7 || isempty(x), return; end
if ischar(x), paths = pathsFromChar(x); return; end
try
    if exist('isstring','builtin') && isstring(x)
        for i = 1:numel(x), paths = [paths pathsFromChar(char(x(i)))]; end
        return;
    end
catch
end
if iscell(x)
    for i = 1:numel(x), try, paths = [paths pathsFromAny(x{i},depth+1)]; catch, end, end
    return;
end
if isstruct(x)
    fn = fieldnames(x);
    for i = 1:numel(x)
        for f = 1:numel(fn)
            try, paths = [paths pathsFromAny(x(i).(fn{f}),depth+1)]; catch, end
        end
    end
end
end

function paths = pathsFromChar(s)
paths = {}; s = char(s);
if exist(s,'file') == 2, paths = {s}; return; end
hits = regexp(s,'([A-Za-z]:[^\n\r\t<>|"]*?\.mat)','match');
hits2 = regexp(s,'(\\\\[^\n\r\t<>|"]*?\.mat)','match');
hits = [hits hits2];
for i = 1:numel(hits)
    p = regexprep(strtrim(hits{i}),'[\]\),;]+$','');
    if exist(p,'file') == 2, paths{end+1} = p; end
end
end

function G = loadG(fullf)
G = [];
S = load(fullf);
if isfield(S,'G') && isstruct(S.G)
    G = S.G;
else
    fn = fieldnames(S);
    for k = 1:numel(fn)
        v = S.(fn{k});
        if isstruct(v) && (isfield(v,'pscAtlas4D') || isfield(v,'PSC') || isfield(v,'psc4D'))
            G = v; break;
        end
    end
end
if isempty(G), return; end
G = normalizeG(G,fullf);
end

function G = normalizeG(G,fullf)
X = [];
flds = {'pscAtlas4D','PSC','psc4D','PSC4D','functionalPSC','Ipsc'};
for k = 1:numel(flds)
    if isfield(G,flds{k}) && ~isempty(G.(flds{k})) && isnumeric(G.(flds{k}))
        X = G.(flds{k}); break;
    end
end
if isempty(X), error('No full PSC field found in %s. Need G.pscAtlas4D.', fullf); end
X = double(X); X(~isfinite(X)) = NaN; X = squeeze(X);
if ndims(X) == 2, error('Static 2D map only, not full time series: %s', fullf); end
if ndims(X) == 4 && size(X,3) > 20 && size(X,4) <= 20
    X = permute(X,[1 2 4 3]);
end
if ~(ndims(X) == 3 || ndims(X) == 4), error('PSC must be [Y X T] or [Y X Z T]. File: %s', fullf); end
nT = getNT(X);
TR = getTR(G,nT,fullf);
G.pscAtlas4D = X;
G.TR = TR;
G.tsec = (0:nT-1) * TR;
G.tmin = G.tsec / 60;
G.nY = size(X,1); G.nX = size(X,2);
if ndims(X) == 3, G.nZ = 1; else, G.nZ = size(X,3); end
G.nT = nT;
if ~isfield(G,'fileLabel') || isempty(G.fileLabel), [~,nm,~] = fileparts(fullf); G.fileLabel = nm; end
if ~isfield(G,'display') || ~isstruct(G.display), G.display = struct(); end
G.display = repairDisplay(G.display);
if ~isfield(G,'underlayAtlas') || isempty(G.underlayAtlas), G.underlayAtlas = makeUnderlay(X); end
end

function TR = getTR(G,nT,fullf)
TR = NaN;
flds = {'TR','TRsec','TR_sec','framePeriod','dt'};
for k = 1:numel(flds)
    try
        if isfield(G,flds{k}) && isnumeric(G.(flds{k})) && isscalar(G.(flds{k}))
            TR = double(G.(flds{k})); break;
        end
    catch
    end
end
if ~(isfinite(TR) && TR > 0)
    try
        if isfield(G,'tsec') && numel(G.tsec) >= 2
            TR = median(diff(double(G.tsec(:))));
        elseif isfield(G,'tmin') && numel(G.tmin) >= 2
            TR = 60 * median(diff(double(G.tmin(:))));
        end
    catch
    end
end
TR = repairTR(TR,nT,fullf);
end

function TR = repairTR(TR,nT,fullf)
if ~(isfinite(TR) && TR > 0)
    TR = 18; fprintf('[GroupAnalysis export] WARNING: missing TR in %s. Using 18 sec.\n', fullf); return;
end
orig = TR;
if nT >= 80 && TR < 0.1
    cand = TR * 1000;
    if ((nT-1)*cand/60) >= 10 && ((nT-1)*cand/60) <= 300, TR = cand; end
end
if nT >= 80 && TR < 1
    totalSecMode = ((nT-1)*TR)/60;
    totalMinMode = (nT-1)*TR;
    if totalSecMode < 10 && totalMinMode >= 10 && totalMinMode <= 300, TR = TR * 60; end
end
if nT >= 80 && ((nT-1)*TR/60) < 10
    TR = 18;
end
if abs(TR-orig) > eps
    fprintf('[GroupAnalysis export] WARNING: repaired TR in %s: %.9g -> %.9g sec | total %.3f min\n', fullf, orig, TR, ((nT-1)*TR)/60);
end
end

function [G,rep] = makeGroupMeanG(B)
X0 = B(1).G.pscAtlas4D; sz0 = size(X0); nT = getNT(X0);
Xc = {}; names = {}; files = {}; TRs = [];
for i = 1:numel(B)
    X = B(i).G.pscAtlas4D;
    if isequal(size(X),sz0)
        Xc{end+1} = X; files{end+1} = B(i).file; TRs(end+1) = B(i).G.TR;
        try, names{end+1} = char(B(i).G.fileLabel); catch, names{end+1} = B(i).file; end
    else
        fprintf('[GroupAnalysis export] Skipping mismatching PSC size: %s\n', B(i).file);
    end
end
if isempty(Xc), error('No matching PSC arrays found.'); end
stack = cat(ndims(Xc{1})+1, Xc{:});
PSCmean = nanmeanLocal(stack, ndims(stack));
G = B(1).G;
G.kind = 'SCM_GROUP_EXPORT';
G.version = 'GroupAnalysisFullTimeV20260511';
G.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
G.fileLabel = sprintf('Group mean SCM (%d animals)', numel(Xc));
G.groupAnalysisMean = true;
G.sourceFiles = files(:);
G.sourceAnimalNames = names(:);
G.nAnimals = numel(Xc);
G.pscAtlas4D = PSCmean;
TR = median(TRs(isfinite(TRs) & TRs > 0));
TR = repairTR(TR,nT,'GROUP_MEAN');
G.TR = TR;
G.tsec = (0:nT-1) * TR;
G.tmin = G.tsec / 60;
G.nY = size(PSCmean,1); G.nX = size(PSCmean,2);
if ndims(PSCmean) == 3, G.nZ = 1; else, G.nZ = size(PSCmean,3); end
G.nT = nT;
G.underlayAtlas = groupUnderlay(B);
G.display = repairDisplay(G.display);
G.display.exportStyle = 'SCM_gui_6tile_black_ppt';
try, G.display.cmapMatrix = getCmapLocal(G.display.colormapName,256); catch, end
rep = struct('nAnimals',numel(Xc),'nT',nT,'TR',TR,'totalMin',((nT-1)*TR)/60);
end

function U = groupUnderlay(B)
U = []; Uc = {};
for i = 1:numel(B)
    try
        u = double(B(i).G.underlayAtlas);
        if isempty(U), U = u; end
        if isequal(size(u),size(U)), Uc{end+1} = u; end
    catch
    end
end
if ~isempty(Uc)
    try, U = nanmeanLocal(cat(ndims(Uc{1})+1,Uc{:}), ndims(Uc{1})+1); catch, U = Uc{1}; end
end
end

function cfg = askPptCfg(G)
totalMin = G.tmin(end);
injDefault = '300';
try
    if isfield(G,'sigWindowSec') && numel(G.sigWindowSec) >= 2 && isfinite(G.sigWindowSec(2))
        injDefault = sprintf('%g', G.sigWindowSec(2));
    end
catch
end
a = inputdlg({'Injection END time (sec). PI labels start after this:','Window length (sec):',sprintf('Max minutes to export (empty = all %.1f min):', totalMin)}, ...
    'Export Group Mean SCM PPT', 1, {injDefault,'60',''});
if isempty(a), cfg = []; return; end
cfg = struct();
cfg.injEndSec = str2double(strtrim(a{1})); if ~isfinite(cfg.injEndSec), cfg.injEndSec = 300; end
cfg.winSec = str2double(strtrim(a{2})); if ~isfinite(cfg.winSec) || cfg.winSec <= 0, cfg.winSec = 60; end
cfg.maxMin = str2double(strtrim(a{3})); if ~isfinite(cfg.maxMin) || cfg.maxMin <= 0, cfg.maxMin = NaN; end
cfg.perSlide = 6;
cfg.dpiTile = 200;
cfg.dpiSlide = 200;
end

function [slidePNGs,nTiles] = renderGroupSeries(G,cfg,tileDir,slideDir,fig)
X = G.pscAtlas4D; TR = G.TR; nT = getNT(X); tsec = (0:nT-1)*TR;
D = repairDisplay(G.display); cm = displayCmap(D); caxV = D.caxis;
baseSec = [30 240];
try, if isfield(G,'baseWindowSec') && numel(G.baseWindowSec) >= 2, baseSec = double(G.baseWindowSec(1:2)); end, catch, end
baseIdx = find(tsec >= min(baseSec) & tsec <= max(baseSec));
if isempty(baseIdx), baseIdx = 1:max(1,min(nT,round(240/TR)+1)); end
if ndims(X) == 3, nZ = 1; else, nZ = size(X,3); end
totalSec = (nT-1)*TR;
starts = 0:cfg.winSec:(floor(totalSec/cfg.winSec)*cfg.winSec);
if isfinite(cfg.maxMin), starts = starts(starts < cfg.maxMin*60); end
slidePNGs = {}; nTiles = 0;
for z = 1:nZ
    Xz = getSlicePSC(X,z);
    bg2 = getUnderlaySlice(G.underlayAtlas,z,nZ,size(Xz,1),size(Xz,2));
    baseMap = nanmeanLocal(Xz(:,:,baseIdx),3);
    tileList = {}; labelList = {};
    for wi = 1:numel(starts)
        s0 = starts(wi); s1 = s0 + cfg.winSec;
        idx = find(tsec >= s0 & tsec < s1);
        if isempty(idx), continue; end
        sigMap = nanmeanLocal(Xz(:,:,idx),3);
        map = sigMap - baseMap; map(~isfinite(map)) = 0;
        [dispMap,alpha] = buildOverlay(map,D);
        lbl = windowLabel(s0,s1,cfg.injEndSec);
        tileFile = fullfile(tileDir, sprintf('GroupMean_z%02d_w%03d_%04.0f-%04.0fs.png', z, wi, s0, s1));
        renderTile(tileFile,bg2,dispMap,alpha,cm,caxV,cfg.dpiTile);
        nTiles = nTiles + 1;
        tileList{end+1} = tileFile; labelList{end+1} = lbl;
        if mod(nTiles,10) == 0, statusMsg(fig,sprintf('Export PPT: rendered %d brain images ...',nTiles)); end
    end
    nSlides = ceil(numel(tileList)/cfg.perSlide);
    for si = 1:nSlides
        ii0 = (si-1)*cfg.perSlide + 1; ii1 = min(si*cfg.perSlide,numel(tileList));
        idx = ii0:ii1;
        ttl = sprintf('%s | Group mean | z=%d/%d', char(G.fileLabel), z, nZ);
        foot = sprintf('TR=%.6g sec | Base=%g-%g sec | Win=%g sec | Thr=%g | CAX=%g %g | AlphaMod=%d [%g..%g] | %s', TR, baseSec(1), baseSec(2), cfg.winSec, D.threshold, caxV(1), caxV(2), double(D.alphaModOn), D.modMin, D.modMax, char(D.colormapName));
        slideFile = fullfile(slideDir, sprintf('slide_z%02d_%03d.png', z, si));
        renderSlide(slideFile,tileList(idx),labelList(idx),cm,caxV,ttl,foot,cfg.dpiSlide);
        slidePNGs{end+1} = slideFile;
    end
end
end

function renderTile(outFile,bg2,map,alpha,cm,caxV,dpiVal)
figT = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','Units','pixels','Position',[100 100 900 760]);
ax = axes('Parent',figT,'Units','normalized','Position',[0 0 1 1]);
axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','reverse'); hold(ax,'on');
image(ax,toGrayRGB(bg2));
h = imagesc(ax,map); set(h,'AlphaData',alpha);
colormap(ax,cm); caxis(ax,caxV); hold(ax,'off');
set(figT,'PaperPositionMode','auto');
print(figT,outFile,'-dpng',sprintf('-r%d',dpiVal),'-opengl');
close(figT);
end

function renderSlide(outFile,pngList,lblList,cm,caxV,titleStr,footerStr,dpiVal)
figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
set(figS,'Units','inches','Position',[0.5 0.5 13.333 7.5],'PaperPositionMode','auto');
annotation(figS,'textbox',[0.02 0.90 0.96 0.085],'String',titleStr,'Color','w','EdgeColor','none','FontName','Arial','FontSize',15,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
annotation(figS,'textbox',[0.39 0.01 0.59 0.055],'String',footerStr,'Color','w','EdgeColor','none','FontName','Arial','FontSize',9,'FontWeight','bold','HorizontalAlignment','right','Interpreter','none');
axCB = axes('Parent',figS,'Position',[0.010 0.14 0.001 0.74],'Visible','off','XTick',[],'YTick',[],'XColor','none','YColor','none','Box','off');
imagesc(axCB,[0 1;0 1]); colormap(axCB,cm); caxis(axCB,caxV);
cb = colorbar(axCB,'Position',[0.018 0.14 0.015 0.74]);
cb.Color = 'w'; cb.FontName = 'Arial'; cb.FontSize = 10; cb.Label.String = 'Signal change (%)'; cb.Label.Color = 'w'; cb.TickDirection = 'out'; cb.Box = 'off';
x0 = 0.095; x1 = 0.98; yBot = 0.12; yTop = 0.86; rowGap = 0.06; colGap = 0.02;
cellH = (yTop-yBot-rowGap)/2; cellW = (x1-x0-2*colGap)/3;
for k = 1:min(6,numel(pngList))
    if k <= 3, cc = k-1; y = yBot + cellH + rowGap; else, cc = k-4; y = yBot; end
    x = x0 + cc*(cellW+colGap);
    axI = axes('Parent',figS,'Position',[x y cellW cellH]);
    imshow(imread(pngList{k}),'Parent',axI); axis(axI,'off');
    annotation(figS,'textbox',[x y+cellH+0.005 cellW 0.035],'String',lblList{k},'Color','w','EdgeColor','none','FontName','Arial','FontSize',13,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
end
print(figS,outFile,'-dpng',sprintf('-r%d',dpiVal),'-opengl');
close(figS);
end

function writePPT(pptPath,slidePNGs)
import mlreportgen.ppt.*
if exist(pptPath,'file') == 2, delete(pptPath); end
ppt = Presentation(pptPath); open(ppt);
for i = 1:numel(slidePNGs)
    try, slide = add(ppt,'Blank'); catch, slide = add(ppt); end
    pic = Picture(slidePNGs{i});
    pic.X = '0in'; pic.Y = '0in'; pic.Width = '13.333in'; pic.Height = '7.5in';
    add(slide,pic);
end
close(ppt); pause(0.2);
if exist(pptPath,'file') ~= 2, error('PowerPoint file was not created: %s', pptPath); end
end

function [dispMap,alpha] = buildOverlay(rawMap,D)
rawMap = double(rawMap); thr = D.threshold;
switch D.signMode
    case 1, showMask = rawMap > 0; dispMap = rawMap;
    case 2, showMask = rawMap < 0; dispMap = abs(min(rawMap,0));
    otherwise, showMask = isfinite(rawMap) & rawMap ~= 0; dispMap = rawMap;
end
thrMask = (abs(rawMap) >= thr) & showMask & isfinite(rawMap);
if ~D.alphaModOn, alpha = (D.alphaPercent/100) .* double(thrMask); return; end
lo = max(D.modMin,thr); hi = D.modMax; if hi <= lo, hi = lo + eps; end
modv = (abs(rawMap)-lo) ./ max(eps,hi-lo); modv(~isfinite(modv)) = 0; modv = min(max(modv,0),1); modv(~showMask) = 0;
alpha = (D.alphaPercent/100) .* modv .* double(thrMask);
end

function D = repairDisplay(D)
if ~isfield(D,'threshold') || isempty(D.threshold) || ~isscalar(D.threshold) || ~isfinite(D.threshold), D.threshold = 0; end
if ~isfield(D,'caxis') || numel(D.caxis) < 2 || any(~isfinite(double(D.caxis(1:2)))), D.caxis = [0 100]; else, D.caxis = double(D.caxis(1:2)); end
if D.caxis(2) < D.caxis(1), D.caxis = fliplr(D.caxis); end
if ~isfield(D,'alphaPercent') || isempty(D.alphaPercent) || ~isscalar(D.alphaPercent) || ~isfinite(D.alphaPercent), D.alphaPercent = 100; end
if ~isfield(D,'alphaModOn') || isempty(D.alphaModOn), D.alphaModOn = true; else, D.alphaModOn = logical(D.alphaModOn); end
if ~isfield(D,'modMin') || isempty(D.modMin) || ~isscalar(D.modMin) || ~isfinite(D.modMin), D.modMin = 15; end
if ~isfield(D,'modMax') || isempty(D.modMax) || ~isscalar(D.modMax) || ~isfinite(D.modMax), D.modMax = 30; end
if D.modMax < D.modMin, tmp = D.modMin; D.modMin = D.modMax; D.modMax = tmp; end
if ~isfield(D,'colormapName') || isempty(D.colormapName), D.colormapName = 'blackbdy_iso'; end
if ~isfield(D,'signMode') || isempty(D.signMode) || ~isscalar(D.signMode) || ~isfinite(D.signMode), D.signMode = 1; else, D.signMode = max(1,min(3,round(double(D.signMode)))); end
end

function cm = displayCmap(D)
if isfield(D,'cmapMatrix') && isnumeric(D.cmapMatrix) && size(D.cmapMatrix,2) == 3
    cm = min(max(double(D.cmapMatrix),0),1);
else
    cm = getCmapLocal(D.colormapName,256);
end
end

function cm = getCmapLocal(name,n)
if nargin < 2, n = 256; end
try, name = lower(strtrim(char(name))); catch, name = 'hot'; end
switch name
    case 'blackbdy_iso'
        if exist('blackbdy_iso','file') == 2, cm = blackbdy_iso(n); else, cm = hot(n); end
    case 'winter_brain_fsl'
        if exist('winter_brain_fsl','file') == 2, cm = winter_brain_fsl(n); else, cm = winter(n); end
    case 'signed_blackbdy_winter'
        nNeg = floor(n/2); nPos = n-nNeg;
        if exist('winter_brain_fsl','file') == 2, neg = winter_brain_fsl(max(nNeg,2)); else, neg = winter(max(nNeg,2)); end
        if exist('blackbdy_iso','file') == 2, pos = blackbdy_iso(max(nPos,2)); else, pos = hot(max(nPos,2)); end
        neg = neg(1:nNeg,:); pos = pos(1:nPos,:); if ~isempty(neg), neg(end,:) = [0 0 0]; end; if ~isempty(pos), pos(1,:) = [0 0 0]; end; cm = [neg; pos];
    case 'hot', cm = hot(n);
    case 'parula', cm = parula(n);
    case 'turbo', if exist('turbo','file') == 2, cm = turbo(n); else, cm = jet(n); end
    case 'jet', cm = jet(n);
    case 'gray', cm = gray(n);
    case 'bone', cm = bone(n);
    case 'copper', cm = copper(n);
    case 'pink', cm = pink(n);
    case 'winter', cm = winter(n);
    otherwise, cm = hot(n);
end
cm = min(max(double(cm),0),1);
end

function Xz = getSlicePSC(X,z)
if ndims(X) == 3, Xz = X; else, Xz = squeeze(X(:,:,z,:)); end
end

function bg2 = getUnderlaySlice(bg,z,nZ,ny,nx)
if isempty(bg), bg2 = zeros(ny,nx); return; end
bg = squeeze(double(bg)); bg(~isfinite(bg)) = 0;
if ndims(bg) == 2
    bg2 = bg;
elseif ndims(bg) == 3
    if size(bg,3) == nZ, bg2 = bg(:,:,z);
    elseif size(bg,3) == 3 && nZ == 1, bg2 = 0.2989*bg(:,:,1)+0.5870*bg(:,:,2)+0.1140*bg(:,:,3);
    else, bg2 = bg(:,:,min(size(bg,3),z)); end
elseif ndims(bg) == 4 && size(bg,3) == 3
    RGB = squeeze(bg(:,:,:,min(size(bg,4),z)));
    bg2 = 0.2989*RGB(:,:,1)+0.5870*RGB(:,:,2)+0.1140*RGB(:,:,3);
else
    bg2 = squeeze(bg(:,:,1));
end
if size(bg2,1) ~= ny || size(bg2,2) ~= nx
    try, bg2 = imresize(bg2,[ny nx],'bilinear');
    catch, tmp = zeros(ny,nx); yy = min(ny,size(bg2,1)); xx = min(nx,size(bg2,2)); tmp(1:yy,1:xx) = bg2(1:yy,1:xx); bg2 = tmp; end
end
end

function lbl = windowLabel(s0,s1,injEnd)
if isfinite(injEnd) && s0 >= injEnd
    lbl = sprintf('PI %.0f-%.0f s', s0-injEnd, s1-injEnd);
else
    lbl = sprintf('%.0f-%.0f s', s0, s1);
end
end

function rgb = toGrayRGB(U)
U = double(U); U(~isfinite(U)) = 0; v = U(:); v = v(isfinite(v));
if isempty(v), U(:) = 0;
else
    lo = prctileLocal(v,0.5); hi = prctileLocal(v,99.5);
    if hi <= lo, lo = min(v); hi = max(v); end
    if hi <= lo, U(:) = 0; else, U = (U-lo)/(hi-lo); end
end
U = min(max(U,0),1);
rgb = ind2rgb(uint8(round(U*255)),gray(256));
end

function U = makeUnderlay(X)
if ndims(X) == 3, U = nanmeanLocal(abs(X),3); else, U = nanmeanLocal(abs(X),4); end
U(~isfinite(U)) = 0;
end

function nT = getNT(X)
if ndims(X) == 3, nT = size(X,3); elseif ndims(X) == 4, nT = size(X,4); else, nT = 0; end
end

function M = nanmeanLocal(X,dim)
mask = isfinite(X); X(~mask) = 0; n = sum(mask,dim); n(n==0) = NaN; M = sum(X,dim) ./ n;
end

function q = prctileLocal(v,p)
try, q = prctile(v,p); return; catch, end
v = sort(v(:)); n = numel(v); if n == 0, q = 0; return; end
k = 1 + (n-1)*(p/100); k1 = floor(k); k2 = ceil(k); k1 = max(1,min(n,k1)); k2 = max(1,min(n,k2));
if k1 == k2, q = v(k1); else, q = v(k1) + (k-k1)*(v(k2)-v(k1)); end
end

function tf = canUsePPT()
try, tf = ~isempty(which('mlreportgen.ppt.Presentation')); catch, tf = false; end
end

function outDir = exportDir(fig,B)
outDir = pwd;
try
    if nargin >= 2 && ~isempty(B)
        G = B(1).G;
        if isfield(G,'exportPath') && exist(char(G.exportPath),'dir') == 7, outDir = char(G.exportPath);
        elseif isfield(G,'loadedPath') && exist(char(G.loadedPath),'dir') == 7, outDir = char(G.loadedPath); end
    end
catch
end
outDir = fullfile(outDir,'GroupAnalysis_Exports'); safeMkdir(outDir);
end

function safeMkdir(d)
if exist(d,'dir') ~= 7, ok = mkdir(d); if ~ok, error('Could not create folder: %s', d); end, end
end

function statusMsg(fig,msg)
fprintf('[GroupAnalysis export] %s\n', msg);
try, setappdata(fig,'GA_lastExportStatus',msg); catch, end
drawnow;
end


function cfg = GA_askPptCfgFast_20260511()
a = inputdlg({ ...
    'Injection END time (sec). PI labels start after this:', ...
    'Window length (sec):', ...
    'Max minutes to export (empty = all):'}, ...
    'Export Group Mean SCM PPT', 1, {'300','60',''});
if isempty(a)
    cfg = [];
    return;
end
cfg = struct();
cfg.injEndSec = str2double(strtrim(a{1}));
if ~isfinite(cfg.injEndSec), cfg.injEndSec = 300; end
cfg.winSec = str2double(strtrim(a{2}));
if ~isfinite(cfg.winSec) || cfg.winSec <= 0, cfg.winSec = 60; end
cfg.maxMin = str2double(strtrim(a{3}));
if ~isfinite(cfg.maxMin) || cfg.maxMin <= 0, cfg.maxMin = NaN; end
cfg.perSlide = 6;
cfg.dpiTile = 200;
cfg.dpiSlide = 200;
end

function GA_clearPptBusy_20260511(fig,busyKey)
try
    if ~isempty(fig) && ishghandle(fig)
        setappdata(fig,busyKey,false);
    end
catch
end
end
