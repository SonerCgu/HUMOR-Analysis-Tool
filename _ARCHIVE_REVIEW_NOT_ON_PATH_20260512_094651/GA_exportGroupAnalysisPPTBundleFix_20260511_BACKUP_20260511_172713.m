function out = GA_exportGroupAnalysisPPTBundleFix_20260511(hFig,mode)
% Hotfix for GroupAnalysis group-map exports only.
% PPT = true SCM-style PI-windowed group mean PSC series.
% SCM = no-popup full group mean PSC bundle for SCM_gui.

out = [];
if nargin < 1, hFig = []; end
if nargin < 2, mode = ''; end
if ischar(hFig) || (isstring(hFig) && isscalar(hFig))
    mode = char(hFig);
    hFig = [];
end
if isempty(mode), mode = 'ppt'; end
if islogical(mode) || isnumeric(mode)
    if isempty(mode) || mode(1) ~= 0
        mode = 'ppt';
    else
        mode = 'scm';
    end
end
if isstring(mode), mode = char(mode); end
if ~ischar(mode), mode = 'ppt'; end
mode = lower(strtrim(char(mode)));
if isempty(hFig) || ~ishghandle(hFig)
    try, hFig = gcbf; catch, hFig = []; end
end
if isempty(hFig) || ~ishghandle(hFig)
    try, hFig = gcf; catch, hFig = []; end
end
if isempty(hFig) || ~ishghandle(hFig)
    error('Open GroupAnalysis first, then run this exporter.');
end
try
    if ~strcmpi(get(hFig,'Type'),'figure'), hFig = ancestor(hFig,'figure'); end
catch
end
S = guidata(hFig);
if isempty(S) || ~isstruct(S)
    error('Could not read GroupAnalysis GUI state from the current figure.');
end

try
    ga_status(hFig,'Group map export: collecting full SCM bundles from table column 8 ...');
    [rows,files] = ga_table_files(S);
    if isempty(files)
        error(['No SCM_GroupExport bundle paths found in GroupAnalysis table column 8.' char(10) ...
               'Add/open the SCM bundles in GroupAnalysis first.']);
    end
    ga_status(hFig,sprintf('Group map export: building group mean PSC from %d bundle(s) ...',numel(files)));
    [G,D] = ga_build_group(S,rows,files,hFig);

    if any(strcmp(mode,{'scm','data','bundle','exportdata','exportdatascm'}))
        out = ga_export_scm(G,D,S,hFig);
    else
        cfg = ga_ppt_dialog(D);
        if isempty(cfg)
            ga_status(hFig,'Export PPT cancelled.');
            return;
        end
        out = ga_export_ppt(G,D,S,hFig,cfg);
    end
catch ME
    ga_status(hFig,['Group map export failed: ' ME.message]);
    rethrow(ME);
end
end


function [Gout,D] = ga_build_group(S,rows,files,hFig)
sumX = [];
sumU = [];
sumM = [];
TRs = [];
subjects = {};
usedFiles = {};
skipped = {};
nUsed = 0;
ref = [];
firstDisplay = struct();
baseWin = ga_vec(S,'mapGlobalBaseSec',[30 240]);
sigmaVal = ga_num(S,'mapSigma',1);

for i = 1:numel(files)
    f = files{i};
    try
        L = load(f);
        G = ga_find_G(L);
        X = ga_to_yxzt(ga_get_psc(G));
        tr = ga_tr(G);
        if isfinite(tr) && tr > 0, TRs(end+1) = tr; end %#ok<AGROW>
        if isempty(fieldnames(firstDisplay)) && isfield(G,'display') && isstruct(G.display)
            firstDisplay = G.display;
        end
        if isfield(G,'baseWindowSec') && numel(G.baseWindowSec) >= 2
            b = double(G.baseWindowSec(1:2));
            if all(isfinite(b)) && b(2) > b(1), baseWin = b(:)'; end
        end
        if isfield(G,'sigma') && ~isempty(G.sigma) && isfinite(double(G.sigma(1)))
            sigmaVal = double(G.sigma(1));
        end

        if isempty(ref)
            ref = [size(X,1) size(X,2) size(X,3) size(X,4)];
            sumX = zeros(ref);
        else
            ref(3) = min(ref(3),size(X,3));
            ref(4) = min(ref(4),size(X,4));
            sumX = sumX(:,:,1:ref(3),1:ref(4));
            if ~isempty(sumU), sumU = sumU(:,:,1:ref(3)); end
            if ~isempty(sumM), sumM = sumM(:,:,1:ref(3)); end
        end
        X = ga_fit4(X,ref);
        sumX = sumX + X;

        U = ga_underlay(G,ref(1:3),X);
        M = ga_mask(G,ref(1:3));
        if isempty(sumU), sumU = zeros(size(U)); end
        if isempty(sumM), sumM = zeros(size(M)); end
        sumU = sumU + U;
        sumM = sumM + double(M);

        nUsed = nUsed + 1;
        usedFiles{end+1} = f; %#ok<AGROW>
        subjects{end+1} = ga_subject(S,rows(i),f,G); %#ok<AGROW>
        ga_status(hFig,sprintf('Group map export: loaded %d/%d full bundle(s) ...',nUsed,numel(files)));
    catch ME
        skipped{end+1} = sprintf('%s -> %s',f,ME.message); %#ok<AGROW>
        try, fprintf(2,'[Group map export] skipped %s\n%s\n',f,ME.message); catch, end
    end
end

if nUsed < 1
    msg = 'No full PSC time-series bundle could be loaded.';
    if ~isempty(skipped), msg = [msg char(10) char(10) ga_join(skipped,char(10))]; end
    error(msg);
end

Xmean = sumX ./ nUsed;
Umean = sumU ./ nUsed;
Mmean = sumM ./ nUsed > 0.5;
TR = 1;
TRs = TRs(isfinite(TRs) & TRs > 0);
if ~isempty(TRs), TR = median(TRs); end
if TR > 10, TR = TR/1000; end
nT = size(Xmean,4);
tsec = (0:nT-1).*TR;
tmin = tsec./60;
R = ga_render(S,firstDisplay);
R.sigma = sigmaVal;

Gout = struct();
Gout.kind = 'SCM_GROUP_EXPORT';
Gout.version = 'GroupAnalysis_group_mean_fullPSC_20260511_command_patch';
Gout.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
Gout.source = 'GroupAnalysis mean of SCM_GroupExport bundles';
Gout.isGroupMean = true;
Gout.n = nUsed;
Gout.subjects = subjects;
Gout.usedFiles = usedFiles;
Gout.skippedFiles = skipped;
Gout.TR = TR;
Gout.tsec = tsec;
Gout.tmin = tmin;
Gout.nY = size(Xmean,1);
Gout.nX = size(Xmean,2);
Gout.nZ = size(Xmean,3);
Gout.nT = size(Xmean,4);
if size(Xmean,3) == 1
    Gout.pscAtlas4D = squeeze(Xmean(:,:,1,:));
    Gout.underlayAtlas = squeeze(Umean(:,:,1));
    Gout.maskAtlas = squeeze(Mmean(:,:,1));
else
    Gout.pscAtlas4D = Xmean;
    Gout.underlayAtlas = Umean;
    Gout.maskAtlas = Mmean;
end
Gout.underlay2D = Umean(:,:,1);
Gout.commonUnderlay = Gout.underlayAtlas;
Gout.brainImage = Umean(:,:,1);
Gout.mask2DCurrentSlice = Mmean(:,:,1);
Gout.baseWindowSec = baseWin;
Gout.baseWindowStr = sprintf('%g-%g',baseWin(1),baseWin(2));
Gout.sigWindowSec = [0 min(60,max(tsec))];
Gout.sigWindowStr = sprintf('%g-%g',Gout.sigWindowSec(1),Gout.sigWindowSec(2));
Gout.sigma = sigmaVal;
Gout.display = struct('threshold',R.threshold,'caxis',R.caxis,'alphaPercent',100, ...
    'alphaModOn',R.alphaModOn,'modMin',R.modMin,'modMax',R.modMax, ...
    'colormapName',R.colormapName,'signMode',R.signMode, ...
    'exportStyle','SCM_gui_6tile_black_group_mean_ppt');
if isfield(R,'cmapMatrix'), Gout.display.cmapMatrix = R.cmapMatrix; end
Gout.fileLabel = sprintf('Group mean SCM bundle n=%d',nUsed);
Gout.animalID = sprintf('GroupMean_n%d',nUsed);
Gout.note = 'Full group mean PSC time series. Open in SCM_gui using Open SCM GroupAnalysis bundle.';

D = struct();
D.X4 = Xmean;
D.U3 = Umean;
D.M3 = Mmean;
D.TR = TR;
D.tsec = tsec;
D.tmin = tmin;
D.R = R;
D.baseWindowSec = baseWin;
D.subjects = subjects;
D.usedFiles = usedFiles;
D.skippedFiles = skipped;
D.nUsed = nUsed;
D.sigma = sigmaVal;
end

function G = ga_find_G(L)
G = [];
if isfield(L,'G') && isstruct(L.G), G = L.G; return; end
fn = fieldnames(L);
for k = 1:numel(fn)
    v = L.(fn{k});
    if isstruct(v) && (isfield(v,'pscAtlas4D') || isfield(v,'PSC') || isfield(v,'underlayAtlas'))
        G = v; return;
    end
end
error('No SCM group bundle struct found.');
end

function X = ga_get_psc(G)
X = [];
fields = {'pscAtlas4D','psc4D','PSC4D','PSC','functionalPSC','Ipsc'};
for k = 1:numel(fields)
    f = fields{k};
    if isfield(G,f) && ~isempty(G.(f)) && isnumeric(G.(f))
        X = double(G.(f));
        break;
    end
end
if isempty(X), error('Could not find full PSC time-series field.'); end
X(~isfinite(X)) = 0;
if ndims(X) < 3, error('PSC is only 2D/static, not a full time series.'); end
end

function X = ga_to_yxzt(X)
while ndims(X) > 4, X = squeeze(X); end
if ndims(X) == 3
    X = reshape(X,size(X,1),size(X,2),1,size(X,3));
elseif ndims(X) == 4
    % already [Y X Z T]
else
    error('PSC must be [Y X T] or [Y X Z T].');
end
if size(X,4) < 2, error('PSC has fewer than 2 time frames.'); end
end

function X = ga_fit4(X,ref)
ny = ref(1); nx = ref(2); nz = ref(3); nt = ref(4);
X = X(:,:,:,1:min(nt,size(X,4)));
X = X(:,:,1:min(nz,size(X,3)),:);
if size(X,3) < nz
    X(:,:,end+1:nz,:) = repmat(X(:,:,end,:),[1 1 nz-size(X,3) 1]);
end
if size(X,4) < nt
    X(:,:,:,end+1:nt) = repmat(X(:,:,:,end),[1 1 1 nt-size(X,4)]);
end
if size(X,1) == ny && size(X,2) == nx, return; end
Y = zeros(ny,nx,nz,nt);
for z = 1:nz
    for t = 1:nt
        Y(:,:,z,t) = ga_resize2(X(:,:,z,t),[ny nx]);
    end
end
X = Y;
end

function U = ga_underlay(G,sz,X)
U = [];
fields = {'underlayAtlas','commonUnderlay','underlay2D','brainImage','bg','meanAtlas','anatomyAtlas'};
for k = 1:numel(fields)
    f = fields{k};
    if isfield(G,f) && ~isempty(G.(f)) && isnumeric(G.(f))
        U = double(G.(f)); break;
    end
end
if isempty(U)
    U = mean(abs(X),4);
end
U = ga_fit3(U,sz,false);
end

function M = ga_mask(G,sz)
M = [];
fields = {'maskAtlas','passedMask','loadedMask','mask2DCurrentSlice'};
for k = 1:numel(fields)
    f = fields{k};
    if isfield(G,f) && ~isempty(G.(f))
        M = double(G.(f)); break;
    end
end
if isempty(M), M = true(sz); else, M = ga_fit3(M,sz,true) > 0.5; end
end

function A = ga_fit3(A,sz,isMask)
ny = sz(1); nx = sz(2); nz = sz(3);
A = squeeze(double(A));
if ndims(A) == 2
    B = zeros(ny,nx,nz);
    A2 = ga_resize2(A,[ny nx]);
    for z = 1:nz, B(:,:,z) = A2; end
    A = B; return;
end
if ndims(A) == 3 && size(A,3) == 3 && nz ~= 3
    A = 0.2989*A(:,:,1) + 0.5870*A(:,:,2) + 0.1140*A(:,:,3);
    A = ga_fit3(A,sz,isMask); return;
end
if ndims(A) > 3
    A = squeeze(A);
    if ndims(A) > 3, A = A(:,:,:,1); end
end
A = A(:,:,1:min(nz,size(A,3)));
if size(A,3) < nz, A(:,:,end+1:nz) = repmat(A(:,:,end),[1 1 nz-size(A,3)]); end
B = zeros(ny,nx,nz);
for z = 1:nz
    B(:,:,z) = ga_resize2(A(:,:,z),[ny nx]);
end
if isMask, B = B > 0.5; end
A = B;
end

function cfg = ga_ppt_dialog(D)
defMax = '';
if ~isempty(D.tsec), defMax = sprintf('%g',floor(max(D.tsec))); end
answ = inputdlg({ ...
    'Injection / PI time in seconds:', ...
    'Window size in seconds:', ...
    'Max export seconds (empty = all):'}, ...
    'Export GroupAnalysis PPT',1,{'300','60',defMax});
if isempty(answ), cfg = []; return; end
cfg.injSec = str2double(strtrim(answ{1})); if ~isfinite(cfg.injSec), cfg.injSec = 300; end
cfg.winSec = str2double(strtrim(answ{2})); if ~isfinite(cfg.winSec) || cfg.winSec <= 0, cfg.winSec = 60; end
cfg.maxSec = str2double(strtrim(answ{3})); if ~isfinite(cfg.maxSec) || cfg.maxSec <= 0, cfg.maxSec = max(D.tsec); end
end

function out = ga_export_scm(G,D,S,hFig)
startDir = ga_start_dir(S);
[f,p] = uiputfile({'*.mat','SCM Group bundle (*.mat)'},'Save GroupAnalysis SCM bundle', ...
    fullfile(startDir,['SCM_GroupExport_GroupMean_' datestr(now,'yyyymmdd_HHMMSS') '.mat']));
if isequal(f,0), out = []; return; end
out = fullfile(p,f);
SCM_GroupExport = G; %#ok<NASGU>
groupMeanPSC = D.X4; %#ok<NASGU>
ga_status(hFig,'Export Data SCM: saving full group mean PSC bundle ...');
save(out,'G','SCM_GroupExport','groupMeanPSC','-v7.3');
ga_status(hFig,['Export Data SCM complete: ' out]);
fprintf('\nSaved SCM-openable full group mean bundle:\n%s\n',out);
end

function out = ga_export_ppt(G,D,S,hFig,cfg)
startDir = ga_start_dir(S);
[f,p] = uiputfile({'*.pptx','PowerPoint (*.pptx)'},'Save GroupAnalysis PPT', ...
    fullfile(startDir,['GroupAnalysis_PI_windows_' datestr(now,'yyyymmdd_HHMMSS') '.pptx']));
if isequal(f,0), out = []; return; end
out = fullfile(p,f);
[~,base] = fileparts(out);
assetDir = fullfile(p,[base '_assets']);
tileDir = fullfile(assetDir,'tiles_png');
slideDir = fullfile(assetDir,'slides_png');
ga_mkdir(assetDir); ga_mkdir(tileDir); ga_mkdir(slideDir);

X = D.X4; U = D.U3; M = D.M3; R = D.R;
ny = size(X,1); nx = size(X,2); nz = size(X,3); nt = size(X,4); %#ok<NASGU>
cm = ga_cmap(R);
slidePNGs = {};
slidePNGs{end+1} = ga_cover_slide(slideDir,G,D,cfg,R); %#ok<AGROW>

lastSec = min(cfg.maxSec,max(D.tsec));
starts = 0:cfg.winSec:lastSec;
starts = starts(starts < max(D.tsec));
if isempty(starts), starts = 0; end
nTiles = 0;

for wi = 1:numel(starts)
    s0 = starts(wi); s1 = min(s0 + cfg.winSec, max(D.tsec) + D.TR/2);
    idx = find(D.tsec >= s0 & D.tsec < s1);
    idx = idx(idx>=1 & idx<=size(X,4));
    if isempty(idx), continue; end
    maps = mean(X(:,:,:,idx),4);
    if isfield(R,'sigma') && R.sigma > 0
        for z = 1:nz, maps(:,:,z) = ga_smooth2(maps(:,:,z),R.sigma); end
    end
    tileFiles = {};
    tileLabels = {};
    for z = 1:nz
        img = ga_make_tile(U(:,:,z),maps(:,:,z),M(:,:,z),R,cm);
        tileFile = fullfile(tileDir,sprintf('w%03d_z%03d.png',wi,z));
        imwrite(img,tileFile);
        tileFiles{end+1} = tileFile; %#ok<AGROW>
        tileLabels{end+1} = sprintf('z=%d/%d | %.0f-%.0fs | %s',z,nz,s0,s1,ga_phase(s0,s1,cfg.injSec)); %#ok<AGROW>
        nTiles = nTiles + 1;
    end
    nSlides = ceil(numel(tileFiles)/6);
    for si = 1:nSlides
        jj0 = (si-1)*6 + 1; jj1 = min(si*6,numel(tileFiles)); jj = jj0:jj1;
        titleStr = sprintf('Group mean PSC | %.0f-%.0f s | %s',s0,s1,ga_phase(s0,s1,cfg.injSec));
        footer = sprintf('n=%d | TR=%.4g s | window=%.0f s | caxis=[%g %g] | thr=%g | alphaMod=%d [%g %g] | cmap=%s', ...
            D.nUsed,D.TR,cfg.winSec,R.caxis(1),R.caxis(2),R.threshold,double(R.alphaModOn),R.modMin,R.modMax,R.colormapName);
        slideFile = fullfile(slideDir,sprintf('slide_w%03d_%02d.png',wi,si));
        ga_slide(slideFile,tileFiles(jj),tileLabels(jj),cm,R.caxis,titleStr,footer);
        slidePNGs{end+1} = slideFile; %#ok<AGROW>
    end
    ga_status(hFig,sprintf('Export PPT: rendered window %.0f-%.0f s (%d/%d) ...',s0,s1,wi,numel(starts)));
end
if numel(slidePNGs) < 2, error('No brain-window slides were created.'); end
ga_write_ppt(out,slidePNGs);
ga_status(hFig,['Export PPT complete: ' out]);
fprintf('\nSaved GroupAnalysis PPT:\n%s\nTiles: %d | Slides: %d\n',out,nTiles,numel(slidePNGs));
end

function img = ga_make_tile(U,M,mask,R,cm)
base = ga_under_rgb(U);
M = double(M); M(~isfinite(M)) = 0;
mask = logical(mask);
if ~isequal(size(mask),size(M)), mask = true(size(M)); end
mag = abs(M);
switch round(R.signMode)
    case 2, show = M < 0; val = abs(min(M,0));
    case 3, show = M ~= 0; val = mag;
    otherwise, show = M > 0; val = M;
end
show = show & mask & mag >= abs(R.threshold);
lo = R.caxis(1); hi = R.caxis(2); if hi <= lo, hi = lo + eps; end
idx = round(1 + 255*(val-lo)/(hi-lo));
idx = max(1,min(256,idx));
ov = reshape(cm(idx(:),:),[size(M,1) size(M,2) 3]);
if R.alphaModOn
    a0 = max(abs(R.threshold),R.modMin); a1 = R.modMax; if a1 <= a0, a1 = a0 + eps; end
    A = (mag-a0)./(a1-a0);
else
    A = ones(size(M));
end
A = min(max(A,0),1).*double(show);
img = base.*(1-repmat(A,[1 1 3])) + ov.*repmat(A,[1 1 3]);
img = uint8(255*min(max(img,0),1));
end

function rgb = ga_under_rgb(U)
U = double(U); U(~isfinite(U)) = 0;
lo = ga_pct(U(:),0.5); hi = ga_pct(U(:),99.5);
if hi <= lo, lo = min(U(:)); hi = max(U(:)); end
if hi > lo, g = (U-lo)./(hi-lo); else, g = zeros(size(U)); end
g = min(max(g,0),1);
rgb = repmat(g,[1 1 3]);
end

function slideFile = ga_cover_slide(slideDir,G,D,cfg,R)
slideFile = fullfile(slideDir,'slide_000_cover.png');
fig = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none');
set(fig,'Units','inches','Position',[0.5 0.5 13.333 7.5],'PaperPositionMode','auto');
lines = {};
lines{end+1} = 'GroupAnalysis PSC Time-Series Export';
lines{end+1} = sprintf('Generated: %s',datestr(now,'yyyy-mm-dd HH:MM:SS'));
lines{end+1} = sprintf('Animals/bundles used: n = %d',D.nUsed);
lines{end+1} = sprintf('TR = %.4g s | frames = %d | z-slices = %d | PI time = %.0f s | window = %.0f s',D.TR,G.nT,G.nZ,cfg.injSec,cfg.winSec);
lines{end+1} = sprintf('Display: caxis [%g %g], threshold %g, alphaMod %d [%g %g], cmap %s',R.caxis(1),R.caxis(2),R.threshold,double(R.alphaModOn),R.modMin,R.modMax,R.colormapName);
lines{end+1} = 'Subjects:';
for i = 1:min(numel(D.subjects),20), lines{end+1} = ['  - ' char(D.subjects{i})]; end %#ok<AGROW>
if numel(D.subjects) > 20, lines{end+1} = sprintf('  ... plus %d more',numel(D.subjects)-20); end
annotation(fig,'textbox',[0.05 0.08 0.90 0.84],'String',lines,'Color','w','EdgeColor','none', ...
    'FontName','Arial','FontSize',15,'FontWeight','bold','Interpreter','none','VerticalAlignment','top');
print(fig,slideFile,'-dpng','-r200','-opengl');
close(fig);
end

function ga_slide(outFile,pngList,lblList,cm,caxV,titleStr,footerStr)
fig = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none');
set(fig,'Units','inches','Position',[0.5 0.5 13.333 7.5],'PaperPositionMode','auto');
annotation(fig,'textbox',[0.04 0.90 0.94 0.08],'String',titleStr,'Color','w','EdgeColor','none', ...
    'FontName','Arial','FontSize',15,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
annotation(fig,'textbox',[0.20 0.01 0.78 0.06],'String',footerStr,'Color','w','EdgeColor','none', ...
    'FontName','Arial','FontSize',9,'FontWeight','bold','HorizontalAlignment','right','Interpreter','none');
axCB = axes('Parent',fig,'Position',[0.015 0.16 0.018 0.70]);
imagesc(axCB,linspace(caxV(1),caxV(2),256)'); axis(axCB,'off'); colormap(axCB,cm); caxis(axCB,caxV);
cb = colorbar(axCB,'Position',[0.04 0.16 0.018 0.70]);
try, cb.Color = 'w'; cb.FontName = 'Arial'; cb.FontSize = 10; cb.Label.String = 'PSC (%)'; cb.Label.Color = 'w'; catch, end
x0 = 0.095; x1 = 0.98; y0 = 0.12; y1 = 0.86; cg = 0.02; rg = 0.065;
cw = (x1-x0-2*cg)/3; ch = (y1-y0-rg)/2;
for k = 1:min(6,numel(pngList))
    if k <= 3, row = 1; col = k-1; else, row = 0; col = k-4; end
    x = x0 + col*(cw+cg); y = y0 + row*(ch+rg);
    ax = axes('Parent',fig,'Position',[x y cw ch]);
    image(ax,imread(pngList{k})); axis(ax,'image'); axis(ax,'off');
    annotation(fig,'textbox',[x y+ch+0.004 cw 0.035],'String',lblList{k},'Color','w','EdgeColor','none', ...
        'FontName','Arial','FontSize',11,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
end
print(fig,outFile,'-dpng','-r200','-opengl');
close(fig);
end

function ga_write_ppt(pptFile,slidePNGs)
if exist(pptFile,'file') == 2, delete(pptFile); end
if ~isempty(which('mlreportgen.ppt.Presentation'))
    import mlreportgen.ppt.*
    ppt = Presentation(pptFile); open(ppt);
    for i = 1:numel(slidePNGs)
        try, sl = add(ppt,'Blank'); catch, sl = add(ppt); end
        pic = Picture(slidePNGs{i}); pic.X = '0in'; pic.Y = '0in'; pic.Width = '13.333in'; pic.Height = '7.5in'; add(sl,pic);
    end
    close(ppt);
elseif ispc && exist('actxserver','file') == 2
    ppt = actxserver('PowerPoint.Application'); ppt.Visible = 1;
    pres = ppt.Presentations.Add;
    sw = pres.PageSetup.SlideWidth; sh = pres.PageSetup.SlideHeight;
    for i = 1:numel(slidePNGs)
        sl = pres.Slides.Add(i,12);
        sl.Shapes.AddPicture(slidePNGs{i},0,1,0,0,sw,sh);
    end
    pres.SaveAs(pptFile); pres.Close; ppt.Quit;
else
    error('No PPT writer found. Slide PNGs were created but PPTX could not be written.');
end
if exist(pptFile,'file') ~= 2, error('PPT file was not created.'); end
end

function R = ga_render(S,D)
R = struct();
R.threshold = ga_num(S,'mapThreshold',0);
R.caxis = ga_vec(S,'mapCaxis',[0 100]);
R.alphaModOn = true;
try, R.alphaModOn = ga_bool(S.mapAlphaModOn); catch, end
R.modMin = ga_num(S,'mapModMin',10);
R.modMax = ga_num(S,'mapModMax',20);
R.colormapName = ga_char(S,'mapColormap','blackbdy_iso');
R.signMode = 1;
if isstruct(D)
    try, if isfield(D,'threshold') && ~isempty(D.threshold), R.threshold = double(D.threshold(1)); end, catch, end
    try, if isfield(D,'caxis') && numel(D.caxis)>=2, R.caxis = double(D.caxis(1:2)); end, catch, end
    try, if isfield(D,'alphaModOn') && ~isempty(D.alphaModOn), R.alphaModOn = logical(D.alphaModOn(1)); end, catch, end
    try, if isfield(D,'modMin') && ~isempty(D.modMin), R.modMin = double(D.modMin(1)); end, catch, end
    try, if isfield(D,'modMax') && ~isempty(D.modMax), R.modMax = double(D.modMax(1)); end, catch, end
    try, if isfield(D,'colormapName') && ~isempty(D.colormapName), R.colormapName = char(D.colormapName); end, catch, end
    try, if isfield(D,'signMode') && ~isempty(D.signMode), R.signMode = double(D.signMode(1)); end, catch, end
    try, if isfield(D,'cmapMatrix') && ~isempty(D.cmapMatrix), R.cmapMatrix = double(D.cmapMatrix); end, catch, end
end
if numel(R.caxis)<2 || any(~isfinite(R.caxis(1:2))) || R.caxis(2)==R.caxis(1), R.caxis = [0 100]; end
if R.caxis(2) < R.caxis(1), R.caxis = fliplr(R.caxis); end
if R.modMax <= R.modMin, R.modMax = R.modMin + eps; end
end

function cm = ga_cmap(R)
if isfield(R,'cmapMatrix') && ~isempty(R.cmapMatrix) && size(R.cmapMatrix,2)==3
    cm = double(R.cmapMatrix); cm = min(max(cm,0),1); return;
end
name = lower(strtrim(char(R.colormapName))); n = 256;
switch name
    case {'blackbdy_iso','blackbdy','blackbody'}, cm = hot(n).^0.85;
    case 'hot', cm = hot(n);
    case 'jet', cm = jet(n);
    case 'gray', cm = gray(n);
    case 'bone', cm = bone(n);
    case 'copper', cm = copper(n);
    case {'winter','winter_brain_fsl'}, cm = winter(n);
    case 'parula', try, cm = parula(n); catch, cm = jet(n); end
    case 'turbo', try, cm = turbo(n); catch, cm = jet(n); end
    otherwise, cm = hot(n).^0.85;
end
end

function s = ga_phase(s0,s1,inj)
if ~isfinite(inj), s = sprintf('%.0f-%.0fs',s0,s1); return; end
if s1 <= inj
    s = sprintf('Pre %.0f to %.0f s',s0-inj,s1-inj);
elseif s0 < inj && s1 > inj
    s = 'Injection / PI 0';
else
    s = sprintf('PI %.0f-%.0f s',s0-inj,s1-inj);
end
end

function tr = ga_tr(G)
tr = NaN;
try, if isfield(G,'TR') && ~isempty(G.TR), tr = double(G.TR(1)); end, catch, end
try, if (~isfinite(tr) || tr<=0) && isfield(G,'tsec') && numel(G.tsec)>1, tr = median(diff(double(G.tsec(:)))); end, catch, end
try, if (~isfinite(tr) || tr<=0) && isfield(G,'tmin') && numel(G.tmin)>1, tr = 60*median(diff(double(G.tmin(:)))); end, catch, end
if ~isfinite(tr) || tr <= 0, tr = 1; end
if tr > 10, tr = tr/1000; end
end

function B = ga_resize2(A,sz)
A = double(A);
if isequal(size(A),sz), B = A; return; end
try
    B = imresize(A,sz,'bilinear');
catch
    [y,x] = size(A); [xq,yq] = meshgrid(linspace(1,x,sz(2)),linspace(1,y,sz(1)));
    B = interp2(A,xq,yq,'linear',0);
end
B(~isfinite(B)) = 0;
end

function B = ga_smooth2(A,sigma)
if ~isfinite(sigma) || sigma <= 0, B = A; return; end
try, B = imgaussfilt(A,sigma); return; catch, end
r = max(1,ceil(3*sigma)); x = -r:r; g = exp(-(x.^2)/(2*sigma^2)); g = g/sum(g);
B = conv2(conv2(double(A),g,'same'),g','same');
end

function subj = ga_subject(S,row,f,G)
subj = '';
try, subj = strtrim(char(S.subj{row,2})); catch, end
if isempty(subj) && isfield(G,'animalID') && ~isempty(G.animalID), try, subj = strtrim(char(G.animalID)); catch, end, end
if isempty(subj), [~,subj] = fileparts(f); end
end

function d = ga_start_dir(S)
d = pwd;
fields = {'outDir','saveRoot','exportPath','loadedPath'};
for k = 1:numel(fields)
    try
        v = S.(fields{k});
        if ischar(v) && exist(v,'dir') == 7, d = v; return; end
    catch
    end
end
end

function v = ga_num(S,f,fb)
v = fb;
try, if isfield(S,f) && ~isempty(S.(f)), v = double(S.(f)(1)); end, catch, end
if ~isfinite(v), v = fb; end
end

function v = ga_vec(S,f,fb)
v = fb;
try
    if isfield(S,f) && numel(S.(f)) >= 2
        vv = double(S.(f)(1:2));
        if all(isfinite(vv)), v = vv(:)'; end
    end
catch
end
end

function s = ga_char(S,f,fb)
s = fb;
try, if isfield(S,f) && ~isempty(S.(f)), s = strtrim(char(S.(f))); end, catch, end
end

function tf = ga_bool(x)
tf = false;
try
    if islogical(x), tf = logical(x(1));
    elseif isnumeric(x), tf = isfinite(x(1)) && x(1) ~= 0;
    else, tf = any(strcmp(lower(strtrim(char(x))),{'1','true','yes','y','on'}));
    end
catch
end
end

function q = ga_pct(v,p)
v = double(v(:)); v = v(isfinite(v));
if isempty(v), q = 0; return; end
v = sort(v); pos = 1+(numel(v)-1)*p/100; lo = floor(pos); hi = ceil(pos);
lo = max(1,min(numel(v),lo)); hi = max(1,min(numel(v),hi));
if lo == hi, q = v(lo); else, q = v(lo) + (pos-lo)*(v(hi)-v(lo)); end
end

function ga_mkdir(d)
if exist(d,'dir') ~= 7
    ok = mkdir(d); if ~ok, error('Could not create folder: %s',d); end
end
end

function s = ga_join(C,sep)
s = '';
for i = 1:numel(C)
    if i > 1, s = [s sep]; end %#ok<AGROW>
    s = [s char(C{i})]; %#ok<AGROW>
end
end

function ga_status(hFig,msg)
msg = char(msg);
fprintf('[GroupAnalysis export] %s\n',msg);
try
    txt = findall(hFig,'Style','text');
    for i = 1:numel(txt)
        try
            old = get(txt(i),'String'); if iscell(old), old = old{1}; end
            low = lower(char(old)); tag = ''; try, tag = lower(char(get(txt(i),'Tag'))); catch, end
            if ~isempty(strfind(low,'group map')) || ~isempty(strfind(low,'complete')) || ~isempty(strfind(low,'status')) || ~isempty(strfind(tag,'status'))
                set(txt(i),'String',msg,'ForegroundColor',[1 0.9 0.25]);
                break;
            end
        catch
        end
    end
catch
end
try, set(hFig,'Name',['GroupAnalysis - ' msg]); catch, end
drawnow;
end

% ========================================================================
% Robust helper functions appended by FIX_MISSING_ga_table_files_20260511
% ========================================================================
function [rows,files] = ga_table_files(S)
% Robust SCM bundle discovery.
% Important: this does NOT rely only on table column 8.
% It searches all cells in S.subj, all GUI uitables, appdata, and then asks
% the user to select full SCM_GroupExport bundles if nothing is found.
rows = [];
files = {};
seen = {};

% ---- 1) Search S.subj all columns
try
    if isstruct(S) && isfield(S,'subj') && ~isempty(S.subj)
        D = S.subj;
        if istable(D), D = table2cell(D); end
        if iscell(D)
            for r = 1:size(D,1)
                for c = 1:size(D,2)
                    [rows,files,seen] = ga_scan_value_for_files(D{r,c},r,rows,files,seen,0);
                end
            end
        end
    end
catch ME
    try, fprintf(2,'[GroupAnalysis export] S.subj scan warning: %s\n',ME.message); catch, end
end

% ---- 2) Search all GUI tables in current GroupAnalysis figure
try
    hFig = gcf;
    T = findall(hFig,'Type','uitable');
    for ti = 1:numel(T)
        try
            D = get(T(ti),'Data');
            if istable(D), D = table2cell(D); end
            if iscell(D)
                for r = 1:size(D,1)
                    for c = 1:size(D,2)
                        [rows,files,seen] = ga_scan_value_for_files(D{r,c},r,rows,files,seen,0);
                    end
                end
            end
        catch
        end
    end
catch
end

% ---- 3) Search appdata shallowly
try
    hFig = gcf;
    AD = getappdata(hFig);
    [rows,files,seen] = ga_scan_value_for_files(AD,NaN,rows,files,seen,0);
catch
end

% ---- 4) If still nothing, ask user directly. This avoids slow recursive scans.
if isempty(files)
    try
        [fn,fp] = uigetfile({'*.mat','MAT files (*.mat)'}, ...
            'Select full SCM_GroupExport bundle(s) used for this GroupAnalysis', ...
            'MultiSelect','on');
        if isequal(fn,0)
            return;
        end
        if ischar(fn), fn = {fn}; end
        for k = 1:numel(fn)
            f = fullfile(fp,fn{k});
            [rows,files,seen] = ga_add_candidate_file(f,NaN,rows,files,seen);
        end
    catch ME
        try, fprintf(2,'[GroupAnalysis export] manual file selection warning: %s\n',ME.message); catch, end
    end
end

if isempty(files)
    fprintf(2,'\n[GroupAnalysis export] No full SCM bundle found.\n');
    fprintf(2,'Export PPT/Data SCM needs original SCM_GroupExport MAT files with full PSC time series.\n');
else
    fprintf('\n[GroupAnalysis export] Found %d full SCM bundle candidate(s):\n',numel(files));
    for k = 1:numel(files)
        fprintf('  %02d) %s\n',k,files{k});
    end
end
end

function [rows,files,seen] = ga_scan_value_for_files(v,row,rows,files,seen,depth)
if nargin < 6, depth = 0; end
if depth > 4, return; end
try
    if isempty(v), return; end

    if ischar(v) || isstring(v)
        C = cellstr(v);
        for i = 1:numel(C)
            s = strtrim(char(C{i}));
            if isempty(s), continue; end

            cand = {s};
            extra1 = regexp(s,'[A-Za-z]:[\\/][^;,\n\r]+?\.mat','match');
            extra2 = regexp(s,'[^;,\n\r]+?\.mat','match');
            cand = [cand extra1 extra2];

            for j = 1:numel(cand)
                f = strtrim(cand{j});
                f = regexprep(f,'^["'']+','');
                f = regexprep(f,'["'']+$','');
                [rows,files,seen] = ga_add_candidate_file(f,row,rows,files,seen);
            end
        end

    elseif iscell(v)
        for i = 1:numel(v)
            [rows,files,seen] = ga_scan_value_for_files(v{i},row,rows,files,seen,depth+1);
        end

    elseif isstruct(v)
        fn = fieldnames(v);
        for a = 1:numel(v)
            for i = 1:numel(fn)
                try
                    [rows,files,seen] = ga_scan_value_for_files(v(a).(fn{i}),row,rows,files,seen,depth+1);
                catch
                end
            end
        end
    end
catch
end
end

function [rows,files,seen] = ga_add_candidate_file(f,row,rows,files,seen)
try
    if isempty(f) || ~ischar(f), return; end
    f = strtrim(f);
    if isempty(f), return; end
    if isempty(strfind(lower(f),'.mat')), return; end
    if exist(f,'file') ~= 2, return; end

    key = lower(strrep(f,'/','\'));
    if any(strcmp(seen,key)), return; end

    if ~ga_is_full_scm_candidate(f)
        return;
    end

    seen{end+1} = key;
    rows(end+1) = row;
    files{end+1} = f;
catch
end
end

function tf = ga_is_full_scm_candidate(f)
% Accept only files that look like full SCM/group bundles, not static 2D maps.
tf = false;
try
    w = whos('-file',f);
    if isempty(w), return; end

    names = lower({w.name});
    lowf = lower(f);

    hasFileHint = ~isempty(strfind(lowf,'scm')) || ...
                  ~isempty(strfind(lowf,'groupexport')) || ...
                  ~isempty(strfind(lowf,'bundle'));

    hasStructHint = any(strcmp(names,'g')) || ...
                    any(strcmp(names,'scm_groupexport')) || ...
                    any(strcmp(names,'par'));

    hasPSCName = false;
    hasNumericTimeSeries = false;

    for i = 1:numel(w)
        nm = lower(w(i).name);
        if ~isempty(strfind(nm,'psc')) || ~isempty(strfind(nm,'time'))
            hasPSCName = true;
        end
        if strcmp(w(i).class,'double') || strcmp(w(i).class,'single')
            if numel(w(i).size) >= 3
                hasNumericTimeSeries = true;
            end
        end
    end

    tf = hasFileHint || hasStructHint || hasPSCName || hasNumericTimeSeries;
catch
    tf = false;
end
end
