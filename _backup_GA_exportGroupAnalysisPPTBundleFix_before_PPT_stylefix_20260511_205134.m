function out = GA_exportGroupAnalysisPPTBundleFix_20260511(fig, mode)
% GroupAnalysis SCM/PPT export final hotfix - MATLAB 2017b+ compatible.
% Usage: GA_exportGroupAnalysisPPTBundleFix_20260511(gcf,'ppt')
%        GA_exportGroupAnalysisPPTBundleFix_20260511(gcf,'scm')
%        GA_exportGroupAnalysisPPTBundleFix_20260511(gcf,true/false)
out = [];
if nargin < 1 || isempty(fig) || ~ishghandle(fig), fig = gcf; end
if nargin < 2 || isempty(mode), mode = 'ppt'; end
if islogical(mode) || isnumeric(mode)
    if logical(mode(1)), mode = 'ppt'; else, mode = 'scm'; end
else
    mode = lower(strtrim(char(mode)));
end
if any(strcmpi(mode,{'true','1','ppt','powerpoint'}))
    mode = 'ppt';
elseif any(strcmpi(mode,{'false','0','scm','data','bundle'}))
    mode = 'scm';
else
    error('Unknown mode: %s', char(mode));
end
busyKey = ['GA_EXPORT_BUSY_' upper(mode) '_20260511_FINAL'];
try
    if isappdata(fig,busyKey) && isequal(getappdata(fig,busyKey),true)
        ga_status(fig,'%s export already running. Duplicate callback ignored.',upper(mode));
        return;
    end
    setappdata(fig,busyKey,true);
catch
end
cleanupObj = onCleanup(@()ga_clearbusy(fig,busyKey)); %#ok<NASGU>
S = guidata(fig);
if isempty(S) || ~isstruct(S), error('Could not read GroupAnalysis GUI state.'); end
switch mode
    case 'ppt', out = ga_export_ppt(fig,S);
    case 'scm', out = ga_export_scm(fig,S);
end
end

function ga_clearbusy(fig,busyKey)
try, if ishghandle(fig), setappdata(fig,busyKey,false); end, catch, end
end

function pptFile = ga_export_ppt(fig,S)
pptFile = '';
cfg = ga_ask_ppt_cfg(S);
if isempty(cfg), return; end
destRoot = uigetdir(ga_startdir(S),'Select destination folder for Group Mean SCM PPT export');
if isequal(destRoot,0), return; end
stamp = datestr(now,'yyyymmdd_HHMMSS');
outDir = fullfile(destRoot,['GroupMean_SCM_PPT_' stamp]);
tileDir = fullfile(outDir,'tiles_png');
assetDir = fullfile(outDir,'ppt_assets');
ga_mkdir(outDir); ga_mkdir(tileDir); ga_mkdir(assetDir);
pptFile = fullfile(outDir,['GroupMean_SCM_series_' stamp '.pptx']);
ga_status(fig,'Export PPT: collecting SCM bundles from GroupAnalysis table column 8 ...');
[rows,bundles] = ga_collect_bundles(S);
if isempty(bundles), error(['No SCM_GroupExport bundle paths found in GroupAnalysis table column 8.' char(10) 'Open/add SCM bundles first.']); end
ga_status(fig,'Export PPT: loading %d SCM bundle(s) ...',numel(bundles));
B = ga_load_all(fig,S,rows,bundles);
if isempty(B), error('No valid SCM bundles loaded.'); end
R = ga_render_settings(S,B(1).G);
TR = B(1).TR;
nT = min([B.nT]);
nZ = B(1).nZ;
ga_status(fig,'Rendering aligned group mean SCM series: %d animals | %d time points | TR %.4g sec | %.4g min',numel(B),nT,TR,(nT-1)*TR/60);
starts = 0:cfg.winSec:(floor(((nT-1)*TR)/cfg.winSec)*cfg.winSec);
if isfinite(cfg.maxMin), starts = starts(starts < cfg.maxMin*60); end
if isempty(starts), starts = 0; end
summaryPng = fullfile(assetDir,'slide_000_summary.png');
ga_summary_png(summaryPng,S,B,cfg,R);
cbPng = fullfile(assetDir,'colorbar_left.png');
ga_colorbar_png(cbPng,ga_cmap(R.colormapName,256,R),R.caxis);
blackPng = fullfile(assetDir,'black_background.png');
imwrite(zeros(20,20,3,'uint8'),blackPng);
slideSpecs = {}; tileCount = 0;
for z = 1:nZ
    tilePNGs = {}; tileLbls = {};
    for wi = 1:numel(starts)
        s0 = starts(wi); s1 = s0 + cfg.winSec;
        maps = []; unders = [];
        for bi = 1:numel(B)
            X = B(bi).PSC(:,:,:,1:nT);
            U = ga_underlay_z(B(bi).underlay,z,size(X,1),size(X,2),B(bi).nZ);
            Msk = ga_mask_z(B(bi).mask,z,size(X,1),size(X,2),B(bi).nZ);
            Mi = ga_window_map(X,B(bi).TR,z,cfg.baseWinSec,[s0 s1],R.sigma,Msk);
            if B(bi).doFlipLR, Mi = fliplr(Mi); U = ga_fliplr(U); end
            if isempty(maps)
                maps = nan([size(Mi) numel(B)]);
                unders = nan([size(ga_gray(ga_2d(U,size(Mi)))) numel(B)]);
            end
            maps(:,:,bi) = Mi;
            unders(:,:,bi) = ga_gray(ga_2d(U,size(Mi)));
        end
        groupMap = ga_nanmean3(maps);
        groupUnder = ga_nanmean3(unders);
        lbl = sprintf('%s | %.0f-%.0fs',ga_phase(s0,s1,cfg.injEndSec,cfg.winSec),s0,s1);
        tileFile = fullfile(tileDir,sprintf('GroupMean_z%02d_w%03d_%04.0f_%04.0fs.png',z,wi,s0,s1));
        ga_brain_png(tileFile,groupUnder,groupMap,R);
        tilePNGs{end+1} = tileFile; %#ok<AGROW>
        tileLbls{end+1} = lbl; %#ok<AGROW>
        tileCount = tileCount + 1;
        if mod(tileCount,10)==0, ga_status(fig,'Export PPT: rendered %d individual brain PNGs ...',tileCount); end
        ga_status(fig,'Export PPT: rendering z %d/%d, window %d/%d ...',z,nZ,wi,numel(starts));
    end
    perSlide = 6; nSlides = ceil(numel(tilePNGs)/perSlide);
    for si = 1:nSlides
        idx = (si-1)*perSlide+1:min(si*perSlide,numel(tilePNGs));
        spec = struct();
        spec.title = sprintf('Group mean SCM | z=%d/%d | %d animals | aligned: %s',z,nZ,numel(B),ga_getchar(S,'mapFlipMode','Off'));
        spec.footer = sprintf('TR=%.4gs | base=%g-%gs | win=%gs | thr=%g | caxis=[%g %g] | alphaMod=%d [%g %g] | cmap=%s',TR,cfg.baseWinSec(1),cfg.baseWinSec(2),cfg.winSec,R.threshold,R.caxis(1),R.caxis(2),double(R.alphaModOn),R.modMin,R.modMax,R.colormapName);
        spec.tilePNGs = tilePNGs(idx);
        spec.tileLbls = tileLbls(idx);
        slideSpecs{end+1} = spec; %#ok<AGROW>
    end
end
ga_status(fig,'Export PPT: writing PowerPoint with individual brain PNG objects ...');
ga_write_ppt(pptFile,summaryPng,slideSpecs,cbPng,blackPng);
ga_status(fig,'Export PPT complete: %d brain PNGs, %d data slides + summary slide.',tileCount,numel(slideSpecs));
fprintf('[GroupAnalysis export] Tiles: %s\n',tileDir);
fprintf('[GroupAnalysis export] PPT: %s\n',pptFile);
try, msgbox(sprintf('Saved Group Mean SCM PPT:\n%s\n\nBrain PNGs: %d\nData slides: %d',pptFile,tileCount,numel(slideSpecs)),'GroupAnalysis PPT export'); catch, end
end

function outFile = ga_export_scm(fig,S)
outFile = '';
destRoot = uigetdir(ga_startdir(S),'Select destination folder for Group Mean SCM bundle');
if isequal(destRoot,0), return; end
stamp = datestr(now,'yyyymmdd_HHMMSS');
outDir = fullfile(destRoot,['GroupMean_SCM_Bundle_' stamp]);
ga_mkdir(outDir);
outFile = fullfile(outDir,['SCM_GroupExport_GROUPMEAN_' stamp '.mat']);
ga_status(fig,'Export Data SCM: collecting SCM bundles from GroupAnalysis table column 8 ...');
[rows,bundles] = ga_collect_bundles(S);
if isempty(bundles), error(['No SCM_GroupExport bundle paths found in GroupAnalysis table column 8.' char(10) 'Open/add SCM bundles first.']); end
B = ga_load_all(fig,S,rows,bundles);
TR = B(1).TR; nT = min([B.nT]); nY = size(B(1).PSC,1); nX = size(B(1).PSC,2); nZ = size(B(1).PSC,3);
stack = nan(nY,nX,nZ,nT,numel(B),'single');
ustack = nan(nY,nX,nZ,numel(B),'single');
for bi = 1:numel(B)
    X = single(B(bi).PSC(:,:,:,1:nT));
    U = single(ga_underlay_stack(B(bi).underlay,nY,nX,nZ));
    if B(bi).doFlipLR, X = X(:,end:-1:1,:,:); U = U(:,end:-1:1,:); end
    stack(:,:,:,:,bi) = X; ustack(:,:,:,bi) = U;
    ga_status(fig,'Export Data SCM: aligned and added animal %d/%d ...',bi,numel(B));
end
pscGroup = ga_nanmean5(stack);
underGroup = ga_nanmean4(ustack);
R = ga_render_settings(S,B(1).G); baseWin = ga_default_base(S,B(1).G);
G = struct();
G.kind = 'SCM_GROUP_EXPORT';
G.version = 'GroupAnalysis_group_mean_20260511_final';
G.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
G.fileLabel = sprintf('Group mean SCM (%d animals, aligned: %s)',numel(B),ga_getchar(S,'mapFlipMode','Off'));
G.TR = TR; G.tsec = (0:nT-1)*TR; G.tmin = G.tsec./60;
G.nY = nY; G.nX = nX; G.nZ = nZ; G.nT = nT;
G.pscAtlas4D = pscGroup; if nZ==1, G.pscAtlas4D = squeeze(G.pscAtlas4D); end
G.underlayAtlas = underGroup; if nZ==1, G.underlayAtlas = underGroup(:,:,1); end
G.maskAtlas = []; G.maskIsInclude = true;
G.baseWindowSec = baseWin; G.baseWindowStr = sprintf('%g-%g',baseWin(1),baseWin(2));
G.sigWindowSec = [840 900]; G.sigWindowStr = '840-900'; G.sigma = R.sigma;
D = R; if isfield(D,'sigma'), D = rmfield(D,'sigma'); end; if isfield(D,'flipUDPreview'), D = rmfield(D,'flipUDPreview'); end
G.display = D; G.display.exportStyle = 'SCM_gui_6tile_black_editable_ppt_group_mean';
G.isAtlasWarped = true; G.atlasTransformFile = 'GroupAnalysis aligned group mean export';
G.groupExport = ga_group_table(B);
save(outFile,'G','-v7.3');
ga_status(fig,'Export Data SCM complete: saved full group mean PSC bundle (%d frames, %.4g min).',nT,(nT-1)*TR/60);
fprintf('[GroupAnalysis export] SCM bundle: %s\n',outFile);
try, msgbox(sprintf('Saved full group mean SCM bundle:\n%s\n\nFrames: %d\nDuration: %.3f min',outFile,nT,(nT-1)*TR/60),'Export Data SCM'); catch, end
end

function cfg = ga_ask_ppt_cfg(S)
bw = ga_default_base(S,struct());
a = inputdlg({'Injection END time (sec). PI labels start after this:','Window length (sec):','Max minutes to export (empty = all):','Baseline window sec (start end):'},'Export Group Mean SCM PPT',1,{'300','60','',sprintf('%g %g',bw(1),bw(2))});
if isempty(a), cfg = []; return; end
cfg = struct();
cfg.injEndSec = str2double(strtrim(a{1})); if ~isfinite(cfg.injEndSec), cfg.injEndSec = 300; end
cfg.winSec = str2double(strtrim(a{2})); if ~isfinite(cfg.winSec) || cfg.winSec<=0, cfg.winSec = 60; end
cfg.maxMin = str2double(strtrim(a{3})); if ~isfinite(cfg.maxMin) || cfg.maxMin<=0, cfg.maxMin = NaN; end
v = sscanf(strrep(strtrim(a{4}),'-',' '),'%f');
if numel(v)<2 || any(~isfinite(v(1:2))), v = bw(:); else, v = v(1:2); end
cfg.baseWinSec = sort(double(v(:)'));
end

function [rows,bundles] = ga_collect_bundles(S)
rows = []; bundles = {};
if ~isfield(S,'subj') || isempty(S.subj) || size(S.subj,2)<8, return; end
n = size(S.subj,1);
sel = [];
try, if isfield(S,'selectedRows') && ~isempty(S.selectedRows), sel = unique(round(double(S.selectedRows(:)'))); sel = sel(sel>=1 & sel<=n); end, catch, sel=[]; end
if isempty(sel), cand = 1:n; else, cand = sel; end
[rows,bundles] = ga_collect_rows(S,cand);
if isempty(bundles) && ~isempty(sel), [rows,bundles] = ga_collect_rows(S,1:n); end
end

function [rows,bundles] = ga_collect_rows(S,cand)
rows = []; bundles = {}; seen = {};
for ii = 1:numel(cand)
    r = cand(ii); useRow = true;
    try, useRow = ga_tological(S.subj{r,1}); catch, useRow = true; end
    if ~useRow, continue; end
    bf = ''; try, bf = strtrim(char(S.subj{r,8})); catch, end
    if isempty(bf) || exist(bf,'file')~=2, continue; end
    key = lower(strrep(bf,'/','\'));
    if any(strcmp(seen,key)), continue; end
    seen{end+1}=key; rows(end+1)=r; bundles{end+1}=bf; %#ok<AGROW>
end
end

function B = ga_load_all(fig,S,rows,bundles)
B = struct([]); refSize = []; refTR = NaN;
for i = 1:numel(bundles)
    bf = bundles{i};
    try
        G = ga_load_bundle(bf); [PSC,TR] = ga_psc_tr(G);
        if ndims(PSC)==3, PSC = reshape(PSC,size(PSC,1),size(PSC,2),1,size(PSC,3)); end
        PSC = double(PSC); PSC(~isfinite(PSC)) = 0;
        if isempty(refSize), refSize = size(PSC); refTR = TR;
        else
            if size(PSC,1)~=refSize(1) || size(PSC,2)~=refSize(2) || size(PSC,3)~=refSize(3), error('Bundle size mismatch.'); end
            if abs(TR-refTR) > max(1e-6,0.001*refTR), error('TR mismatch.'); end
        end
        row = rows(i); side = ga_side(S,row); doFlip = ga_should_flip(S,row,side);
        b = struct(); b.file=bf; b.row=row; b.G=G; b.PSC=PSC; b.TR=TR;
        b.nY=size(PSC,1); b.nX=size(PSC,2); b.nZ=size(PSC,3); b.nT=size(PSC,4);
        b.underlay=ga_bundle_underlay(G); b.mask=ga_bundle_mask(G);
        b.side=side; b.doFlipLR=doFlip; b.animal=ga_animal(S,row,bf,G); b.session=ga_session(bf,G); b.scan=ga_scan(bf,G);
        if isempty(B), B=b; else, B(end+1)=b; end %#ok<AGROW>
        ga_status(fig,'Loaded bundle %d/%d: %s | side=%s | flipLR=%d',i,numel(bundles),b.animal,b.side,double(b.doFlipLR));
    catch ME
        ga_status(fig,'Skipped bundle %d/%d: %s | %s',i,numel(bundles),bf,ME.message);
    end
end
if isempty(B), error('No valid full SCM bundles loaded.'); end
end

function G = ga_load_bundle(bf)
L = load(bf); G = [];
if isfield(L,'G') && isstruct(L.G), G = L.G;
else
    fn = fieldnames(L);
    for k=1:numel(fn)
        v = L.(fn{k});
        if isstruct(v) && (isfield(v,'pscAtlas4D') || isfield(v,'psc4D') || isfield(v,'PSC') || isfield(v,'underlayAtlas')), G = v; break; end
    end
end
if isempty(G) || ~isstruct(G), error('No SCM group bundle struct found.'); end
end

function [PSC,TR] = ga_psc_tr(G)
PSC = []; TR = NaN;
names = {'pscAtlas4D','psc4D','PSC4D','PSC','functionalPSC','Ipsc','I'};
for k=1:numel(names)
    if isfield(G,names{k}) && ~isempty(G.(names{k})) && isnumeric(G.(names{k}))
        X = G.(names{k});
        if (ndims(X)==3 && size(X,3)>=2) || (ndims(X)==4 && size(X,4)>=2), PSC = X; break; end
    end
end
try, if isfield(G,'TR') && ~isempty(G.TR) && isfinite(double(G.TR(1))) && double(G.TR(1))>0, TR = double(G.TR(1)); end, catch, end
if ~isfinite(TR) || TR<=0
    try
        if isfield(G,'tsec') && numel(G.tsec)>=2, TR = median(diff(double(G.tsec(:))));
        elseif isfield(G,'tmin') && numel(G.tmin)>=2, TR = 60*median(diff(double(G.tmin(:)))); end
    catch, end
end
if isempty(PSC), error('No full PSC time-series found.'); end
if ~isfinite(TR) || TR<=0, error('Bundle has no valid TR.'); end
end

function M = ga_window_map(X,TR,z,baseWin,sigWin,sigma,maskIn)
nT = size(X,4); z = max(1,min(size(X,3),round(z)));
bi = ga_secidx(baseWin,TR,nT,true); si = ga_secidx(sigWin,TR,nT,false);
P = squeeze(X(:,:,z,:));
M = mean(P(:,:,si),3) - mean(P(:,:,bi),3);
if sigma>0, M = ga_smooth(M,sigma); end
if ~isempty(maskIn), M(~maskIn) = 0; end
M(~isfinite(M)) = 0;
end

function idx = ga_secidx(win,TR,nT,incl)
win = double(win(:)'); if numel(win)<2, win = [0 (nT-1)*TR]; end
if win(2)<win(1), win = fliplr(win); end
t = (0:nT-1)*TR;
if incl, idx = find(t>=win(1) & t<=win(2)); else, idx = find(t>=win(1) & t<win(2)); end
if isempty(idx), idx = max(1,min(nT,round(mean(win)/TR)+1)); end
end

function ga_brain_png(outFile,U,M,R)
f = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(f,'Units','pixels','Position',[100 100 900 700]);
ax = axes('Parent',f,'Units','normalized','Position',[0.02 0.02 0.96 0.96]);
ga_render_overlay(ax,U,M,R,false);
set(f,'PaperPositionMode','auto'); print(f,outFile,'-dpng','-r200','-opengl'); close(f);
end

function ga_render_overlay(ax,U,M,R,showCB)
M = double(M); M(~isfinite(M))=0; U = ga_2d(U,size(M)); Ug = ga_gray(U); RGB = repmat(Ug,[1 1 3]);
if isfield(R,'flipUDPreview') && R.flipUDPreview, M = flipud(M); RGB = RGB(end:-1:1,:,:); Ug = flipud(Ug); end
cla(ax); image(ax,RGB); axis(ax,'image'); axis(ax,'off'); set(ax,'YDir','normal'); hold(ax,'on');
thr = abs(R.threshold); aPct = max(0,min(100,R.alphaPercent));
lo = R.modMin; hi = R.modMax; if hi<lo, tmp=lo; lo=hi; hi=tmp; end; if hi<=lo, hi=lo+eps; end
signMode = 1; try, signMode = round(R.signMode); catch, end
switch signMode
    case 2, showMask = M < -thr; D = abs(min(M,0));
    case 3, showMask = isfinite(M) & abs(M)>=thr; D = M;
    otherwise, showMask = M > thr; D = M;
end
showMask = showMask & ga_brainmask(Ug);
if ~R.alphaModOn
    A = (aPct/100).*double(showMask);
else
    effLo = max(lo,thr); effHi = hi; if effHi<=effLo, effHi=effLo+eps; end
    ramp = (abs(M)-effLo)./max(eps,effHi-effLo); ramp(~isfinite(ramp))=0; ramp=min(max(ramp,0),1); ramp(abs(M)<=effLo)=0;
    A = (aPct/100).*ramp.*double(showMask);
end
D(A<=0)=0; h=imagesc(ax,D); set(h,'AlphaData',A); try, set(h,'AlphaDataMapping','none'); catch, end
colormap(ax,ga_cmap(R.colormapName,256,R)); caxis(ax,R.caxis);
if showCB, cb=colorbar(ax); try, cb.Color='w'; cb.Label.String='Signal change (%)'; catch, end; end
hold(ax,'off');
end

function BW = ga_brainmask(Ug)
BW = true(size(Ug));
try
    v = Ug(:); v = v(isfinite(v)); if isempty(v), return; end
    lo = ga_pct(v,5); hi = ga_pct(v,99); if hi<=lo, return; end
    BW = Ug > max(0.03,lo+0.05*(hi-lo));
    try, BW = imfill(BW,'holes'); catch, end
    try, BW = bwareaopen(BW,max(10,round(0.001*numel(BW)))); catch, end
    if nnz(BW)<10, BW = true(size(Ug)); end
catch, BW = true(size(Ug)); end
end

function ga_colorbar_png(outFile,cm,caxV)
f = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(f,'Units','pixels','Position',[100 100 170 850]);
ax = axes('Parent',f,'Units','normalized','Position',[0.25 0.08 0.25 0.84]);
vals = linspace(caxV(1),caxV(2),256)'; imagesc(ax,1,vals,vals); axis(ax,'xy');
set(ax,'XTick',[],'YAxisLocation','right','YColor','w','Color',[0 0 0],'FontName','Arial','FontSize',11,'LineWidth',1);
colormap(ax,cm); caxis(ax,caxV); ylabel(ax,'Signal change (%)','Color','w','FontName','Arial','FontSize',12,'FontWeight','bold');
set(f,'PaperPositionMode','auto'); print(f,outFile,'-dpng','-r200','-opengl'); close(f);
end

function ga_summary_png(outFile,S,B,cfg,R)
f = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(f,'Units','inches','Position',[0.5 0.5 13.333 7.5]);
ax = axes('Parent',f,'Units','normalized','Position',[0 0 1 1]); axis(ax,'off');
text(ax,0.5,0.94,'Group Mean SCM Export Summary','Color','w','FontName','Arial','FontSize',24,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
info = sprintf(['Animals: %d    Alignment mode: %s    Reference: %s\nInjection end: %.0f sec    Window: %.0f sec    Baseline: %.0f-%.0f sec\nThreshold: %.3g    CAX: [%.3g %.3g]    AlphaMod: %d [%.3g %.3g]    Colormap: %s'],numel(B),ga_getchar(S,'mapFlipMode','Off'),ga_getchar(S,'mapRefPacapSide','Left'),cfg.injEndSec,cfg.winSec,cfg.baseWinSec(1),cfg.baseWinSec(2),R.threshold,R.caxis(1),R.caxis(2),double(R.alphaModOn),R.modMin,R.modMax,R.colormapName);
text(ax,0.04,0.84,info,'Color',[0.92 0.92 0.92],'FontName','Arial','FontSize',13,'FontWeight','bold','HorizontalAlignment','left','VerticalAlignment','top','Interpreter','none');
headers={'Row','Animal','Session','Scan','Injection side','Flip LR','Bundle'};
x=[0.04 0.10 0.25 0.37 0.49 0.64 0.73]; w=[0.05 0.14 0.11 0.11 0.14 0.08 0.23]; y0=0.68; rowH=0.055;
for c=1:numel(headers), rectangle('Parent',ax,'Position',[x(c) y0 w(c) rowH],'FaceColor',[0.12 0.12 0.12],'EdgeColor',[0.7 0.7 0.7]); text(ax,x(c)+0.005,y0+0.032,headers{c},'Color','w','FontName','Arial','FontSize',10,'FontWeight','bold','Interpreter','none'); end
maxRows=min(numel(B),9);
for r=1:maxRows
    y=y0-r*rowH; vals={num2str(B(r).row),B(r).animal,B(r).session,B(r).scan,B(r).side,num2str(double(B(r).doFlipLR)),ga_short(B(r).file,38)};
    for c=1:numel(vals), rectangle('Parent',ax,'Position',[x(c) y w(c) rowH],'FaceColor',[0.02 0.02 0.02],'EdgeColor',[0.35 0.35 0.35]); text(ax,x(c)+0.005,y+0.030,vals{c},'Color',[0.95 0.95 0.95],'FontName','Arial','FontSize',9,'Interpreter','none'); end
end
if numel(B)>maxRows, text(ax,0.04,0.10,sprintf('+ %d more animals not shown.',numel(B)-maxRows),'Color',[1 0.75 0.25],'FontName','Arial','FontSize',12,'FontWeight','bold'); end
set(f,'PaperPositionMode','auto'); print(f,outFile,'-dpng','-r200','-opengl'); close(f);
end

function ga_write_ppt(pptFile,summaryPng,slideSpecs,cbPng,blackPng)
if exist(pptFile,'file')==2, try, delete(pptFile); catch, error('Could not overwrite PPT: %s',pptFile); end, end
if ~isempty(which('mlreportgen.ppt.Presentation'))
    ga_write_ppt_ml(pptFile,summaryPng,slideSpecs,cbPng,blackPng);
elseif ispc && exist('actxserver','file')==2
    ga_write_ppt_com(pptFile,summaryPng,slideSpecs,cbPng,blackPng);
else
    error('No PowerPoint writer found. Brain PNGs were saved, but PPTX could not be created.');
end
pause(0.4); if exist(pptFile,'file')~=2, error('PPT file was not created: %s',pptFile); end
end

function ga_write_ppt_ml(pptFile,summaryPng,slideSpecs,cbPng,blackPng)
% MATLAB 2017b-safe PPT writer.
% IMPORTANT: Do not use mlreportgen.ppt.TextBox here.
% Older MATLAB versions can throw:
% No constructor mlreportgen.ppt.TextBox with matching signature found.
% Therefore all text/table content must already be rendered into PNGs.

import mlreportgen.ppt.*

if nargin < 2, summaryPng = ''; end
if nargin < 3, slideSpecs = {}; end
if nargin < 4, cbPng = ''; end
if nargin < 5, blackPng = ''; end

pptDir = fileparts(pptFile);
if isempty(pptDir), pptDir = pwd; end
if exist(pptDir,'dir') ~= 7, mkdir(pptDir); end

if isempty(blackPng) || exist(blackPng,'file') ~= 2
    blackPng = fullfile(pptDir,'_ga_black_background.png');
    try
        imwrite(uint8(zeros(64,64,3)),blackPng);
    catch
        blackPng = '';
    end
end

if exist(pptFile,'file') == 2
    try
        delete(pptFile);
    catch
        error('Could not overwrite existing PPT: %s',pptFile);
    end
end

ppt = [];
try
    ppt = Presentation(pptFile);
    open(ppt);

    slideW = '13.333in';
    slideH = '7.5in';

    % ---------------------------------------------------------
    % First slide: summary/table PNG, if available.
    % ---------------------------------------------------------
    if ~isempty(summaryPng) && exist(summaryPng,'file') == 2
        try
            slide = add(ppt,'Blank');
        catch
            slide = add(ppt);
        end
        pic = Picture(summaryPng);
        pic.X = '0in';
        pic.Y = '0in';
        pic.Width = slideW;
        pic.Height = slideH;
        add(slide,pic);
    end

    if isempty(slideSpecs)
        close(ppt);
        return;
    end

    if isstruct(slideSpecs)
        nSlides = numel(slideSpecs);
    elseif iscell(slideSpecs)
        nSlides = numel(slideSpecs);
    else
        nSlides = 0;
    end

    for si = 1:nSlides
        if iscell(slideSpecs)
            spec = slideSpecs{si};
        else
            spec = slideSpecs(si);
        end

        try
            slide = add(ppt,'Blank');
        catch
            slide = add(ppt);
        end

        % -----------------------------------------------------
        % Optional pre-rendered full-slide background.
        % This should contain title, labels, footer, PI text, and one colorbar.
        % -----------------------------------------------------
        bgFile = '';
        if isstruct(spec)
            bgFields = {'slidePng','slidePNG','slideFile','backgroundPng','backgroundPNG','montagePng','montagePNG'};
            for ff = 1:numel(bgFields)
                fn = bgFields{ff};
                if isfield(spec,fn) && ~isempty(spec.(fn))
                    try
                        bgFile = char(spec.(fn));
                    catch
                        bgFile = '';
                    end
                    if ~isempty(bgFile) && exist(bgFile,'file') == 2
                        break;
                    else
                        bgFile = '';
                    end
                end
            end
        end

        if ~isempty(bgFile) && exist(bgFile,'file') == 2
            pic = Picture(bgFile);
            pic.X = '0in';
            pic.Y = '0in';
            pic.Width = slideW;
            pic.Height = slideH;
            add(slide,pic);
            hasFullSlideBackground = true;
        else
            hasFullSlideBackground = false;
            if ~isempty(blackPng) && exist(blackPng,'file') == 2
                pic = Picture(blackPng);
                pic.X = '0in';
                pic.Y = '0in';
                pic.Width = slideW;
                pic.Height = slideH;
                add(slide,pic);
            end
        end

        % Only add separate colorbar if there is no full-slide background.
        % This prevents the duplicate white colorbar labeling you saw.
        if ~hasFullSlideBackground && ~isempty(cbPng) && exist(cbPng,'file') == 2
            cbPic = Picture(cbPng);
            cbPic.X = '0.20in';
            cbPic.Y = '1.00in';
            cbPic.Width = '0.35in';
            cbPic.Height = '5.50in';
            add(slide,cbPic);
        end

        % -----------------------------------------------------
        % Add the six brain PNGs as separate selectable pictures.
        % -----------------------------------------------------
        tileList = {};
        if isstruct(spec)
            tileFields = {'tilePNGs','tilePngs','pngList','pngs','tiles','imagePngs','images'};
            for ff = 1:numel(tileFields)
                fn = tileFields{ff};
                if isfield(spec,fn) && ~isempty(spec.(fn))
                    v = spec.(fn);
                    try
                        if exist('isstring','builtin') && isstring(v)
                            v = cellstr(v);
                        end
                    catch
                    end
                    if ischar(v)
                        tileList = {v};
                    elseif iscell(v)
                        tileList = v(:)';
                    end
                    if ~isempty(tileList)
                        break;
                    end
                end
            end
        end

        x0 = 0.095;
        x1 = 0.980;
        yBot = 0.120;
        yTop = 0.860;
        rowGap = 0.060;
        colGap = 0.020;
        slideWnum = 13.333;
        slideHnum = 7.500;
        cellH = (yTop - yBot - rowGap) / 2;
        cellW = (x1 - x0 - 2*colGap) / 3;

        for kk = 1:min(6,numel(tileList))
            imgFile = '';
            try, imgFile = char(tileList{kk}); catch, imgFile = ''; end
            if isempty(imgFile) || exist(imgFile,'file') ~= 2
                continue;
            end

            if kk <= 3
                cc = kk - 1;
                yNorm = yBot + cellH + rowGap;
            else
                cc = kk - 4;
                yNorm = yBot;
            end

            xNorm = x0 + cc * (cellW + colGap);
            xIn = xNorm * slideWnum;
            yIn = (1 - (yNorm + cellH)) * slideHnum;
            wIn = cellW * slideWnum;
            hIn = cellH * slideHnum;

            pic = Picture(imgFile);
            pic.X = sprintf('%.3fin',xIn);
            pic.Y = sprintf('%.3fin',yIn);
            pic.Width = sprintf('%.3fin',wIn);
            pic.Height = sprintf('%.3fin',hIn);
            add(slide,pic);
        end
    end

    close(ppt);

catch ME
    try
        if ~isempty(ppt), close(ppt); end
    catch
    end
    error('mlreportgen PPT export failed: %s',ME.message);
end

pause(0.3);
if exist(pptFile,'file') ~= 2
    error('PPT file was not created: %s',pptFile);
end
end
function ga_ppt_pic(slide,img,x,y,w,h)
import mlreportgen.ppt.*
pic=Picture(img); pic.X=sprintf('%.3fin',x); pic.Y=sprintf('%.3fin',y); pic.Width=sprintf('%.3fin',w); pic.Height=sprintf('%.3fin',h); add(slide,pic);
end

function ga_ppt_text(slide,str,x,y,w,h,fs,boldFlag,alignStr)
import mlreportgen.ppt.*
tb=TextBox(str); tb.X=sprintf('%.3fin',x); tb.Y=sprintf('%.3fin',y); tb.Width=sprintf('%.3fin',w); tb.Height=sprintf('%.3fin',h);
try, tb.Font='Arial'; catch, end
try, tb.FontSize=sprintf('%dpt',fs); catch, end
try, tb.FontColor='FFFFFF'; catch, end
try, tb.Bold=boldFlag; catch, end
try, tb.HorizontalAlignment=alignStr; catch, end
add(slide,tb);
end

function ga_write_ppt_com(pptFile,summaryPng,slideSpecs,cbPng,blackPng)
ppt=[]; pres=[];
try
    ppt=actxserver('PowerPoint.Application'); ppt.Visible=1; pres=ppt.Presentations.Add; sw=pres.PageSetup.SlideWidth; sh=pres.PageSetup.SlideHeight;
    slide=pres.Slides.Add(1,12); slide.Shapes.AddPicture(summaryPng,0,1,0,0,sw,sh);
    for si=1:numel(slideSpecs)
        spec=slideSpecs{si}; slide=pres.Slides.Add(si+1,12); slide.Shapes.AddPicture(blackPng,0,1,0,0,sw,sh);
        ga_com_text(slide,spec.title,15,10,sw-30,30,15,1,2); ga_com_text(slide,spec.footer,sw*0.27,sh-32,sw*0.70,22,8,1,3);
        slide.Shapes.AddPicture(cbPng,0,1,sw*0.009,sh*0.15,sw*0.05,sh*0.74);
        x0=sw*0.086; xGap=sw*0.017; yTop=sh*0.123; yBot=sh*0.536; tileW=sw*0.289; tileH=sh*0.344; labelH=sh*0.034;
        for k=1:min(6,numel(spec.tilePNGs))
            if k<=3, cc=k-1; y=yTop; else, cc=k-4; y=yBot; end
            x=x0+cc*(tileW+xGap); ga_com_text(slide,spec.tileLbls{k},x,y,tileW,labelH,11,1,2); slide.Shapes.AddPicture(spec.tilePNGs{k},0,1,x,y+labelH,tileW,tileH);
        end
    end
    pres.SaveAs(pptFile); pres.Close; ppt.Quit;
catch ME
    try, if ~isempty(pres), pres.Close; end, catch, end; try, if ~isempty(ppt), ppt.Quit; end, catch, end
    error('PowerPoint COM export failed: %s',ME.message);
end
end

function ga_com_text(slide,str,x,y,w,h,fs,boldFlag,alignCode)
tb=slide.Shapes.AddTextbox(1,x,y,w,h); tr=tb.TextFrame.TextRange; tr.Text=str; tr.Font.Name='Arial'; tr.Font.Size=fs; tr.Font.Bold=boldFlag; tr.Font.Color.RGB=16777215; try, tr.ParagraphFormat.Alignment=alignCode; catch, end; try, tb.Fill.Visible=0; tb.Line.Visible=0; catch, end
end

function R = ga_render_settings(S,G)
R=struct();
R.threshold=ga_getnum(S,'mapThreshold',NaN); R.caxis=ga_getvec(S,'mapCaxis',[NaN NaN]); R.alphaModOn=ga_getlog(S,'mapAlphaModOn',true);
R.modMin=ga_getnum(S,'mapModMin',NaN); R.modMax=ga_getnum(S,'mapModMax',NaN); R.alphaPercent=ga_getnum(S,'mapAlphaPercent',100);
R.colormapName=ga_getchar(S,'mapColormap',''); R.sigma=ga_getnum(S,'mapSigma',NaN); R.signMode=ga_getnum(S,'mapSignMode',1); R.flipUDPreview=true;
try
    if isstruct(G) && isfield(G,'display') && isstruct(G.display)
        D=G.display;
        if ~isfinite(R.threshold) && isfield(D,'threshold') && ~isempty(D.threshold), R.threshold=double(D.threshold(1)); end
        if any(~isfinite(R.caxis)) && isfield(D,'caxis') && numel(D.caxis)>=2, R.caxis=double(D.caxis(1:2)); end
        if isfield(D,'alphaModOn') && ~isempty(D.alphaModOn), R.alphaModOn=logical(D.alphaModOn(1)); end
        if ~isfinite(R.modMin) && isfield(D,'modMin') && ~isempty(D.modMin), R.modMin=double(D.modMin(1)); end
        if ~isfinite(R.modMax) && isfield(D,'modMax') && ~isempty(D.modMax), R.modMax=double(D.modMax(1)); end
        if isempty(R.colormapName) && isfield(D,'colormapName') && ~isempty(D.colormapName), R.colormapName=char(D.colormapName); end
        if isfield(D,'cmapMatrix') && ~isempty(D.cmapMatrix), R.cmapMatrix=double(D.cmapMatrix); end
        if isfield(D,'signMode') && ~isempty(D.signMode), R.signMode=double(D.signMode(1)); end
    end
catch, end
if ~isfinite(R.threshold), R.threshold=0; end
if numel(R.caxis)<2 || any(~isfinite(R.caxis(1:2))) || R.caxis(2)==R.caxis(1), R.caxis=[0 100]; end
if R.caxis(2)<R.caxis(1), R.caxis=fliplr(R.caxis); end
if ~isfinite(R.modMin), R.modMin=15; end; if ~isfinite(R.modMax), R.modMax=30; end
if R.modMax<R.modMin, tmp=R.modMin; R.modMin=R.modMax; R.modMax=tmp; end
if ~isfinite(R.alphaPercent), R.alphaPercent=100; end; if isempty(R.colormapName), R.colormapName='blackbdy_iso'; end; if ~isfinite(R.sigma), R.sigma=1; end
end

function bw = ga_default_base(S,G)
bw=[30 240];
try, if isstruct(S) && isfield(S,'mapGlobalBaseSec') && numel(S.mapGlobalBaseSec)>=2, v=double(S.mapGlobalBaseSec(1:2)); if all(isfinite(v)) && v(2)>v(1), bw=v(:)'; return; end, end, catch, end
try, if isstruct(G) && isfield(G,'baseWindowSec') && numel(G.baseWindowSec)>=2, v=double(G.baseWindowSec(1:2)); if all(isfinite(v)) && v(2)>v(1), bw=v(:)'; return; end, end, catch, end
end

function U=ga_bundle_underlay(G)
U=[]; names={'underlayAtlas','underlayAtlas2D','underlay2D','commonUnderlay','brainImage','bg','bgAtlas','meanAtlas','anatomyAtlas'};
for k=1:numel(names), if isfield(G,names{k}) && ~isempty(G.(names{k})) && (isnumeric(G.(names{k})) || islogical(G.(names{k}))), U=G.(names{k}); return; end, end
end
function M=ga_bundle_mask(G)
M=[]; names={'maskAtlas','mask2DCurrentSlice','mask','brainMask','underlayMask'};
for k=1:numel(names), if isfield(G,names{k}) && ~isempty(G.(names{k})) && (isnumeric(G.(names{k})) || islogical(G.(names{k}))), M=logical(G.(names{k})); return; end, end
end

function side=ga_side(S,row)
side='Unknown';
try, if isfield(S,'rowPacapSide') && numel(S.rowPacapSide)>=row && ~isempty(S.rowPacapSide{row}), side=strtrim(char(S.rowPacapSide{row})); if isempty(side), side='Unknown'; end; return; end, catch, end
try, for c=1:size(S.subj,2), s=lower(strtrim(char(S.subj{row,c}))); if any(strcmp(s,{'left','l'})), side='Left'; return; end; if any(strcmp(s,{'right','r'})), side='Right'; return; end; end, catch, end
end
function tf=ga_should_flip(S,row,side)
tf=false; mode=ga_getchar(S,'mapFlipMode','Off'); ref=ga_getchar(S,'mapRefPacapSide','Left');
if strcmpi(mode,'Flip right-injected animals'), tf=strcmpi(side,'Right');
elseif strcmpi(mode,'Flip left-injected animals'), tf=strcmpi(side,'Left');
elseif strcmpi(mode,'Align to Reference Hemisphere'), tf=(strcmpi(ref,'Left')&&strcmpi(side,'Right')) || (strcmpi(ref,'Right')&&strcmpi(side,'Left')); end
if strcmpi(side,'Unknown'), tf=false; end
end

function U=ga_underlay_stack(Uin,nY,nX,nZ)
if isempty(Uin), U=zeros(nY,nX,nZ); return; end
Uin=squeeze(double(Uin)); Uin(~isfinite(Uin))=0;
if ndims(Uin)==2, U2=ga_resize(Uin,[nY nX]); U=repmat(U2,[1 1 nZ]); return; end
if ndims(Uin)==3
    if size(Uin,1)==nY && size(Uin,2)==nX && size(Uin,3)==nZ, U=Uin; return; end
    if size(Uin,3)==3 && nZ==1, U=reshape(ga_resize(ga_gray(Uin),[nY nX]),nY,nX,1); return; end
    zidx=round(linspace(1,size(Uin,3),nZ)); zidx=max(1,min(size(Uin,3),zidx)); U=zeros(nY,nX,nZ); for z=1:nZ, U(:,:,z)=ga_resize(Uin(:,:,zidx(z)),[nY nX]); end; return;
end
if ndims(Uin)==4 && size(Uin,3)==3, U=zeros(nY,nX,nZ); for z=1:nZ, zz=max(1,min(size(Uin,4),z)); U(:,:,z)=ga_resize(ga_gray(squeeze(Uin(:,:,:,zz))),[nY nX]); end; return; end
U=zeros(nY,nX,nZ);
end
function U=ga_underlay_z(Uin,z,nY,nX,nZ), Us=ga_underlay_stack(Uin,nY,nX,nZ); z=max(1,min(size(Us,3),round(z))); U=Us(:,:,z); end
function M=ga_mask_z(Min,z,nY,nX,nZ)
if isempty(Min), M=true(nY,nX); return; end
Min=squeeze(logical(Min));
if ndims(Min)==2, M=ga_resizemask(Min,nY,nX); elseif ndims(Min)==3, if size(Min,3)==nZ, z=max(1,min(size(Min,3),round(z))); M=ga_resizemask(Min(:,:,z),nY,nX); else, M=ga_resizemask(any(Min,3),nY,nX); end; else, M=true(nY,nX); end
end
function M=ga_resizemask(M,nY,nX), if size(M,1)==nY && size(M,2)==nX, M=logical(M); else, try, M=imresize(double(M),[nY nX],'nearest')>0.5; catch, T=false(nY,nX); yy=min(nY,size(M,1)); xx=min(nX,size(M,2)); T(1:yy,1:xx)=M(1:yy,1:xx); M=T; end, end, end

function A=ga_2d(A,sz), sz=sz(1:2); A=squeeze(double(A)); if ndims(A)==3 && size(A,3)==3 && size(A,1)==sz(1) && size(A,2)==sz(2), return; end; if ndims(A)==3, if size(A,3)==3, A=ga_gray(A); else, A=A(:,:,round(size(A,3)/2)); end; elseif ndims(A)>3, A=squeeze(A); if ndims(A)>2, A=A(:,:,1); end; end; A=ga_resize(A,sz); end
function B=ga_resize(A,sz), if ndims(A)==3 && size(A,3)==3, B=zeros(sz(1),sz(2),3); for c=1:3, B(:,:,c)=ga_resize(A(:,:,c),sz); end; return; end; if isequal(size(A),sz), B=A; return; end; try, B=imresize(A,sz,'bilinear'); catch, [Y,X]=size(A); [xq,yq]=meshgrid(linspace(1,X,sz(2)),linspace(1,Y,sz(1))); B=interp2(double(A),xq,yq,'linear',0); end, end
function G=ga_gray(U), U=double(U); if ndims(U)==3 && size(U,3)==3, U=0.2989.*U(:,:,1)+0.5870.*U(:,:,2)+0.1140.*U(:,:,3); end; U(~isfinite(U))=0; mn=min(U(:)); mx=max(U(:)); if isfinite(mx)&&isfinite(mn)&&mx>mn, G=(U-mn)./(mx-mn); else, G=zeros(size(U)); end, end
function A=ga_fliplr(A), if ndims(A)==3 && size(A,3)==3, A=A(:,end:-1:1,:); else, A=fliplr(A); end, end
function M=ga_nanmean3(X), n=sum(isfinite(X),3); X(~isfinite(X))=0; M=sum(X,3)./max(1,n); M(n==0)=NaN; end
function M=ga_nanmean4(X), n=sum(isfinite(X),4); X(~isfinite(X))=0; M=sum(X,4)./max(1,n); M(n==0)=NaN; end
function M=ga_nanmean5(X), n=sum(isfinite(X),5); X(~isfinite(X))=0; M=sum(X,5)./max(1,n); M(n==0)=NaN; end
function B=ga_smooth(A,sigma), if sigma<=0, B=A; return; end; try, B=imgaussfilt(A,sigma); return; catch, end; r=max(1,ceil(3*sigma)); x=-r:r; g=exp(-(x.^2)/(2*sigma^2)); g=g./sum(g); B=conv2(conv2(double(A),g,'same'),g','same'); end
function q=ga_pct(v,p), v=sort(v(:)); n=numel(v); if n==0, q=NaN; return; end; k=1+(n-1)*(p/100); k1=floor(k); k2=ceil(k); k1=max(1,min(n,k1)); k2=max(1,min(n,k2)); if k1==k2, q=v(k1); else, q=v(k1)+(k-k1)*(v(k2)-v(k1)); end, end

function cm=ga_cmap(name,n,R)
if nargin>=3 && isstruct(R) && isfield(R,'cmapMatrix') && ~isempty(R.cmapMatrix) && size(R.cmapMatrix,2)==3, cm=max(0,min(1,double(R.cmapMatrix))); return; end
name=lower(strtrim(char(name)));
switch name
    case 'blackbdy_iso', if exist('blackbdy_iso','file')==2, cm=blackbdy_iso(n); else, cm=hot(n); end
    case 'winter_brain_fsl', if exist('winter_brain_fsl','file')==2, cm=winter_brain_fsl(n); else, cm=winter(n); end
    case 'hot', cm=hot(n); case 'parula', cm=parula(n); case 'turbo', if exist('turbo','file')==2, cm=turbo(n); else, cm=jet(n); end
    case 'jet', cm=jet(n); case 'gray', cm=gray(n); case 'bone', cm=bone(n); case 'copper', cm=copper(n); case 'pink', cm=pink(n);
    otherwise, cm=hot(n);
end
cm=max(0,min(1,cm));
end

function s=ga_phase(s0,s1,injEnd,winSec)
if ~isfinite(injEnd), s=sprintf('%.0f-%.0fs',s0,s1); elseif s1<=injEnd, s='Baseline'; elseif s0<injEnd && s1>injEnd, s='Injection end'; else, m=floor((s0-injEnd)/winSec)+1; if m<1, m=1; end; s=sprintf('PI %d min',m); end
end
function s=ga_getchar(S,name,fb), s=fb; try, if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)), s=strtrim(char(S.(name))); end, catch, s=fb; end, end
function v=ga_getnum(S,name,fb), v=fb; try, if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)), v=double(S.(name)(1)); end, catch, end; if ~isfinite(v), v=fb; end, end
function v=ga_getvec(S,name,fb), v=fb; try, if isstruct(S)&&isfield(S,name)&&numel(S.(name))>=2, vv=double(S.(name)(1:2)); if all(isfinite(vv)), v=vv(:)'; end, end, catch, end; if numel(v)<2, v=fb; end, end
function v=ga_getlog(S,name,fb), v=fb; try, if isstruct(S)&&isfield(S,name)&&~isempty(S.(name)), v=logical(S.(name)(1)); end, catch, end, end
function tf=ga_tological(x), tf=false; try, if islogical(x), tf=logical(x(1)); elseif isnumeric(x), tf=isfinite(x(1))&&x(1)~=0; else, s=lower(strtrim(char(x))); tf=any(strcmp(s,{'1','true','yes','y','on'})); end, catch, tf=false; end, end
function d=ga_startdir(S), d=pwd; try, if isfield(S,'outDir')&&~isempty(S.outDir)&&exist(S.outDir,'dir')==7, d=char(S.outDir); return; end, catch, end; try, if isfield(S,'opt')&&isfield(S.opt,'startDir')&&~isempty(S.opt.startDir)&&exist(S.opt.startDir,'dir')==7, d=char(S.opt.startDir); return; end, catch, end, end
function ga_mkdir(d), if exist(d,'dir')~=7, ok=mkdir(d); if ~ok, error('Could not create folder: %s',d); end, end, end
function s=ga_short(s,n), try, s=char(s); catch, s=''; end; if numel(s)>n, s=[s(1:max(1,n-3)) '...']; end, end
function subj=ga_animal(S,row,bf,G), subj=''; try, if isfield(S,'subj')&&size(S.subj,1)>=row&&size(S.subj,2)>=2, subj=strtrim(char(S.subj{row,2})); end, catch, end; if isempty(subj), try, if isfield(G,'animalID')&&~isempty(G.animalID), subj=strtrim(char(G.animalID)); end, catch, end, end; if isempty(subj), [~,subj]=fileparts(bf); end; subj=ga_short(subj,40); end
function session=ga_session(bf,G), session=''; try, if isfield(G,'session')&&~isempty(G.session), session=char(G.session); end, catch, end; if isempty(session), tok=regexp(bf,'(S\d+)','tokens','once'); if ~isempty(tok), session=tok{1}; end, end; if isempty(session), session='?'; end, end
function scan=ga_scan(bf,G), scan=''; try, if isfield(G,'scanID')&&~isempty(G.scanID), scan=char(G.scanID); end, catch, end; if isempty(scan), tok=regexp(bf,'(FUS_\d+)','tokens','once'); if ~isempty(tok), scan=tok{1}; end, end; if isempty(scan), scan='?'; end, end
function T=ga_group_table(B), T=struct('row',{},'animal',{},'session',{},'scan',{},'side',{},'flipLR',{},'file',{}); for i=1:numel(B), T(i).row=B(i).row; T(i).animal=B(i).animal; T(i).session=B(i).session; T(i).scan=B(i).scan; T(i).side=B(i).side; T(i).flipLR=B(i).doFlipLR; T(i).file=B(i).file; end, end

function ga_status(fig,fmt,varargin)
try, msg=sprintf(fmt,varargin{:}); catch, msg=fmt; end
try, fprintf('[GroupAnalysis export] %s\n',msg); catch, end
try
    if isempty(fig) || ~ishghandle(fig), drawnow; return; end
    h=findobj(fig,'Tag','GA_export_status_20260511');
    if isempty(h) || ~ishghandle(h(1))
        h=uicontrol('Parent',fig,'Style','text','Units','normalized','Position',[0.01 0.005 0.98 0.035],'Tag','GA_export_status_20260511','String','','BackgroundColor',[0.02 0.02 0.02],'ForegroundColor',[1.00 0.85 0.25],'FontName','Arial','FontSize',11,'FontWeight','bold','HorizontalAlignment','left');
    else, h=h(1); end
    set(h,'String',['  ' msg]); drawnow limitrate;
catch, try, drawnow limitrate; catch, end, end
end
