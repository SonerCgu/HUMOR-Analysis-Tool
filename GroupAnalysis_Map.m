% GA_AUTO_ERROR_PRINT_PATCH_V1
function varargout = GroupAnalysis_Map(action, varargin)
% GroupAnalysis_Map - self-contained map backend for modular GroupAnalysis.
% MATLAB 2017b + 2023b compatible.

if nargin < 1 || isempty(action)
    error('GroupAnalysis_Map requires an action string.');
end

actionIn = strtrim(char(action));
key = lower(actionIn);
key = regexprep(key,'[^a-z0-9]','');

switch key
    case 'getcachedgroupbundle'
        [G, cache] = localGetCachedGroupBundle(varargin{:});
        varargout = localPackOut(nargout, G, cache);
    case 'buildpreviewmapfrombundle'
        [mapNow, winInfoTxt] = localBuildPreviewMapFromBundle(varargin{:});
        varargout = localPackOut(nargout, mapNow, winInfoTxt);
    case 'resolvepreviewunderlay'
        U = localResolvePreviewUnderlay(varargin{:});
        varargout = localPackOut(nargout, U);
    case 'renderpscoverlay'
        h = localRenderPSCOverlay(varargin{:});
        varargout = localPackOut(nargout, h);
    case 'runpscmapanalysis'
        [R, cacheOut] = localRunPSCMapAnalysis(varargin{:});
        varargout = localPackOut(nargout, R, cacheOut);
    case 'loadgroupunderlayfile'
        U = localLoadGroupUnderlayFile(varargin{:});
        varargout = localPackOut(nargout, U);
    case 'exportmapdisplaypng'
        localExportMapDisplayPNG(varargin{:});
        varargout = {};
    case 'buildgroupanalysisvideoexportga'
        E = localBuildGroupAnalysisVideoExportGA(varargin{:});
        varargout = localPackOut(nargout, E);
    case 'onexportgroupmappptfrommain'
        GA_exportGroupAnalysisPPTBundleFix_20260511(varargin{:});
        varargout = {};
    otherwise
        error('Unsupported GroupAnalysis_Map action: %s', actionIn);
end
end

function out = localPackOut(nout, varargin)
if nout == 0
    out = {};
else
    out = varargin(1:min(nout,numel(varargin)));
end
end

function [G, cache] = localGetCachedGroupBundle(cache, bundleFile)
if nargin < 1 || isempty(cache), cache = struct(); end
if nargin < 2 || isempty(bundleFile), error('Bundle file is empty.'); end
bundleFile = strtrimSafeLocal(bundleFile);
if exist(bundleFile,'file') ~= 2, error('Bundle file not found: %s', bundleFile); end
key = ['GB||' bundleFile];
if isstruct(cache) && isfield(cache,'groupBundle') && isa(cache.groupBundle,'containers.Map')
    try
        if isKey(cache.groupBundle,key), G = cache.groupBundle(key); return; end
    catch
    end
end
L = load(bundleFile);
G = [];
if isfield(L,'G') && isstruct(L.G)
    G = L.G;
else
    f = fieldnames(L);
    for i = 1:numel(f)
        X = L.(f{i});
        if isstruct(X) && (isfield(X,'pscAtlas4D') || isfield(X,'scmMapAtlas') || isfield(X,'underlay2D'))
            G = X;
            break;
        end
    end
end
if isempty(G) || ~isstruct(G), error('Bundle MAT does not contain a valid G/group struct: %s', bundleFile); end
try
    if ~isstruct(cache), cache = struct(); end
    if ~isfield(cache,'groupBundle') || ~isa(cache.groupBundle,'containers.Map')
        cache.groupBundle = containers.Map('KeyType','char','ValueType','any');
    end
    cache.groupBundle(key) = G;
catch
end
end

function [mapNow, winInfoTxt] = localBuildPreviewMapFromBundle(S, G)
winInfoTxt = '';
src = localGetCharField(S,'mapSource','Recompute from exported PSC');
useGlobal = localGetLogicalField(S,'mapUseGlobalWindows',true);
sigma = localGetNumField(S,'mapSigma',0);
hasPSC = isfield(G,'pscAtlas4D') && ~isempty(G.pscAtlas4D);
hasMap = localHasExportedMap(G);
if (useGlobal || ~strcmpi(src,'Use exported SCM map')) && hasPSC
    bw = localGetVecField(S,'mapGlobalBaseSec',[30 240]);
    sw = localGetVecField(S,'mapGlobalSigSec',[840 900]);
    mapNow = localRecomputeMapFromPSC(G,bw,sw,sigma);
    winInfoTxt = sprintf('base %.0f-%.0fs | sig %.0f-%.0fs',bw(1),bw(2),sw(1),sw(2));
elseif hasMap
    mapNow = localGetExportedMap(G);
    if sigma > 0, mapNow = localSmooth2D(mapNow,sigma); end
    winInfoTxt = 'exported SCM map';
elseif hasPSC
    bw = localGetVecField(S,'mapGlobalBaseSec',[30 240]);
    sw = localGetVecField(S,'mapGlobalSigSec',[840 900]);
    mapNow = localRecomputeMapFromPSC(G,bw,sw,sigma);
    winInfoTxt = sprintf('PSC fallback base %.0f-%.0fs | sig %.0f-%.0fs',bw(1),bw(2),sw(1),sw(2));
else
    error('Bundle has neither pscAtlas4D nor an exported SCM map.');
end
mapNow = double(localSqueeze2D(mapNow,G));
mapNow(~isfinite(mapNow)) = 0;
end

function tf = localHasExportedMap(G)
names = {'scmMapAtlas','mapAtlas','pscMapAtlas','scmMap','PSCmap','pscMap','map','overlay2D','groupMap2D'};
tf = false;
for i = 1:numel(names)
    if isfield(G,names{i}) && ~isempty(G.(names{i}))
        tf = true; return;
    end
end
end

function M = localGetExportedMap(G)
names = {'scmMapAtlas','mapAtlas','pscMapAtlas','scmMap','PSCmap','pscMap','map','overlay2D','groupMap2D'};
for i = 1:numel(names)
    if isfield(G,names{i}) && ~isempty(G.(names{i}))
        M = localSqueeze2D(G.(names{i}),G);
        return;
    end
end
error('No exported map field found.');
end

function map2 = localRecomputeMapFromPSC(G,bw,sw,sigma)
PSC = double(G.pscAtlas4D);
TR = localGetNumField(G,'TR',NaN);
if ~isfinite(TR) || TR <= 0, error('Bundle has no valid TR.'); end
if ndims(PSC) == 4
    z = localPickZ(G,size(PSC,3));
    P = squeeze(PSC(:,:,z,:));
elseif ndims(PSC) == 3
    P = PSC;
elseif ndims(PSC) == 2
    map2 = PSC; return;
else
    error('Unsupported pscAtlas4D dimensionality.');
end
if ndims(P) ~= 3, error('Selected PSC data is not [Y X T].'); end
T = size(P,3);
b0 = max(1,min(T,floor(bw(1)/TR)+1));
b1 = max(1,min(T,floor(bw(2)/TR)+1));
s0 = max(1,min(T,floor(sw(1)/TR)+1));
s1 = max(1,min(T,floor(sw(2)/TR)+1));
if b1 < b0, tmp=b0; b0=b1; b1=tmp; end
if s1 < s0, tmp=s0; s0=s1; s1=tmp; end
baseMap = mean(P(:,:,b0:b1),3);
sigMap  = mean(P(:,:,s0:s1),3);
map2 = sigMap - baseMap;
if sigma > 0, map2 = localSmooth2D(map2,sigma); end
map2(~isfinite(map2)) = 0;
end

function U = localResolvePreviewUnderlay(S,G,mapNow)
targetSz = size(mapNow); targetSz = targetSz(1:2);
mode = localGetCharField(S,'mapUnderlayMode','Bundle underlay');
if strcmpi(mode,'Loaded custom underlay') && isfield(S,'mapLoadedUnderlay') && ~isempty(S.mapLoadedUnderlay)
    U = localAnyTo2D(S.mapLoadedUnderlay,targetSz,G); return;
end
names = {'underlay2D','underlayAtlas2D','underlayAtlas','commonUnderlay','brainImage','bg','bgAtlas','meanAtlas','anatomyAtlas'};
U = [];
for i = 1:numel(names)
    if isfield(G,names{i}) && ~isempty(G.(names{i}))
        U = G.(names{i}); break;
    end
end
if isempty(U), U = zeros(targetSz); end
U = localAnyTo2D(U,targetSz,G);
end

function h = localRenderPSCOverlay(ax,U,M,R,styleName,showCB)
% Strict SCM-style renderer with UNDERLAY-BASED OVERLAY MASKING.
% This removes outside-brain spots when using a custom underlay/overlay.

if nargin < 6, showCB = true; end
if nargin < 5 || isempty(styleName), styleName = 'Dark'; end
if isempty(ax) || ~ishghandle(ax)
    error('Invalid axes handle for map rendering.');
end

M = double(M);
M(~isfinite(M)) = 0;

if isfield(R,'flipUDPreview') && logical(R.flipUDPreview)
    M = flipud(M);
    U = localFlipUD(U);
end

% Prepare underlay.
U = localAnyTo2D(U,size(M),struct());
Ug = localToGray(U);
Urgb = localToRGB(U);

% Build a mask from the underlay.
% Pixels outside the underlay support will suppress overlay visibility.
maskThr = 0.03;
try
    gt = graythresh(Ug);
    if isfinite(gt)
        maskThr = max(maskThr, 0.5 * gt);
    end
catch
end

brainMask = Ug > maskThr;
try, brainMask = imfill(brainMask,'holes'); catch, end
try, brainMask = bwareaopen(brainMask, max(10, round(0.001 * numel(brainMask)))); catch, end

% Fail-safe: if masking became too strict, do not destroy the display.
if nnz(brainMask) < 10
    brainMask = true(size(Ug));
end

cla(ax);
try, delete(findall(ancestor(ax,'figure'),'Type','ColorBar')); catch, end

% Draw underlay first.
image(ax,Urgb);
axis(ax,'image');
axis(ax,'off');
hold(ax,'on');

% Display / alpha settings.
cax = localGetVecField(R,'caxis',[0 100]);
thr = abs(localGetNumField(R,'threshold',0));
modMin = localGetNumField(R,'modMin',10);
modMax = localGetNumField(R,'modMax',20);
alphaPct = localGetNumField(R,'alphaPercent',100);
alphaPct = max(0,min(100,alphaPct));
alphaModOn = localGetLogicalField(R,'alphaModOn',true);

if modMax < modMin
    tmp = modMin;
    modMin = modMax;
    modMax = tmp;
end
if modMax <= modMin
    modMax = modMin + eps;
end

% Positive-only overlay like the SCM blackbody display.
D = M;
mag = abs(M);
showMask = isfinite(M) & (M > thr);

% SCM-style alpha ramp.
effLo = max(modMin,thr);
effHi = modMax;
if effHi <= effLo
    effHi = effLo + eps;
end

if ~alphaModOn
    A = (alphaPct/100) .* double(showMask);
else
    ramp = (mag - effLo) ./ max(eps,(effHi - effLo));
    ramp(~isfinite(ramp)) = 0;
    ramp = min(max(ramp,0),1);
    ramp(mag <= effLo) = 0;
    A = (alphaPct/100) .* ramp .* double(showMask);
end

% IMPORTANT: apply underlay-derived brain mask here.
A = A .* double(brainMask);

A(~isfinite(A)) = 0;
A = min(max(A,0),1);

% Extra safety.
A(mag <= effLo) = 0;
D(A <= 0) = 0;

% Draw overlay.
h = imagesc(ax,D);
set(h,'AlphaData',A);
try, set(h,'AlphaDataMapping','none'); catch, end

try, caxis(ax,cax); catch, end
try
    colormap(ax,localCmap(localGetCharField(R,'colormapName','blackbdy_iso'),256));
catch
    colormap(ax,hot(256));
end

if showCB
    cb = colorbar(ax);
    try, set(cb,'Color',[1 1 1]); catch, end
end

if strcmpi(styleName,'Light')
    try, set(ax,'Color',[1 1 1]); catch, end
else
    try, set(ax,'Color',[0 0 0]); catch, end
end

hold(ax,'off');
end

function [R, cacheOut] = localRunPSCMapAnalysis(S,subjActive,mapIdx,cacheIn)
if nargin < 4 || isempty(cacheIn), cacheIn = struct(); end
cacheOut = cacheIn;
maps = {}; underlays = {}; subjects = {};
for i = 1:size(subjActive,1)
    bf = '';
    try, bf = strtrimSafeLocal(subjActive{i,8}); catch, end
    if isempty(bf) || exist(bf,'file') ~= 2, continue; end
    [G, cacheOut] = localGetCachedGroupBundle(cacheOut,bf);
    [m,~] = localBuildPreviewMapFromBundle(S,G);
    u = localResolvePreviewUnderlay(S,G,m);
    origRow = i;
    try, if nargin >= 3 && numel(mapIdx) >= i, origRow = mapIdx(i); end; catch, end
    [m,u] = localApplyHemisphereFlip(S,origRow,m,u);
    maps{end+1,1} = m;
    underlays{end+1,1} = u;
    try, subjects{end+1,1} = subjActive{i,2}; catch, subjects{end+1,1} = sprintf('S%d',i); end
end
if isempty(maps), error('No valid maps could be built from selected bundles.'); end
refSz = size(maps{1}); refSz = refSz(1:2);
N = numel(maps);
stack = nan(refSz(1),refSz(2),N);
ustack = nan(refSz(1),refSz(2),N);
for i = 1:N
    stack(:,:,i) = localResizeLike(double(maps{i}),refSz);
    ug = localToGray(localAnyTo2D(underlays{i},refSz,struct()));
    ustack(:,:,i) = localResizeLike(ug,refSz);
end
summaryName = localGetCharField(S,'mapSummary','Mean');
if strcmpi(summaryName,'Median')
    groupMap = localNanMedian3(stack);
else
    groupMap = localNanMean3(stack);
end
commonUnderlay = localNanMean3(ustack);
R = struct();
R.mode = 'Group Maps';
R.groupMap = groupMap;
R.commonUnderlay = commonUnderlay;
R.n = N;
R.mapSummary = summaryName;
R.subjects = subjects;
R.maps = maps;
R.note = 'Built by GroupAnalysis_Map self-contained backend.';
end

function U = localLoadGroupUnderlayFile(fp)
fp = strtrimSafeLocal(fp);
if exist(fp,'file') ~= 2, error('Underlay file not found: %s',fp); end
[~,~,ext] = fileparts(fp); ext = lower(ext);
if strcmp(ext,'.mat')
    L = load(fp); f = fieldnames(L); U = [];
    for i = 1:numel(f)
        if isnumeric(L.(f{i})) || islogical(L.(f{i}))
            U = L.(f{i}); break;
        end
    end
    if isempty(U), error('No numeric image variable found in MAT underlay.'); end
else
    U = imread(fp);
end
end

function localExportMapDisplayPNG(outFile,D,styleName)
if nargin < 3, styleName = 'Dark'; end
figBg = [0 0 0]; if strcmpi(styleName,'Light'), figBg = [1 1 1]; end
f = figure('Visible','off','Color',figBg,'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(f,'Position',[100 100 1000 800]);
ax = axes('Parent',f,'Units','normalized','Position',[0.06 0.08 0.82 0.84]);
localRenderPSCOverlay(ax,D.underlay,D.map,D.render,styleName,true);
try, title(ax,D.title,'Color',[1 1 1],'FontWeight','bold','Interpreter','none'); catch, end
set(f,'PaperPositionMode','auto');
print(f,outFile,'-dpng','-r300');
close(f);
end

function E = localBuildGroupAnalysisVideoExportGA(S,mapIdx)
if isfield(S,'lastMAP') && isstruct(S.lastMAP) && isfield(S.lastMAP,'groupMap')
    M = S.lastMAP.groupMap; U = S.lastMAP.commonUnderlay;
else
    [R,~] = localRunPSCMapAnalysis(S,S.subj(mapIdx,:),mapIdx,S.cache);
    M = R.groupMap; U = R.commonUnderlay;
end
E = struct();
E.underlay2D = U;
E.brainImage = U;
E.overlay2D = M;
E.groupMap2D = M;
E.functional4D = repmat(double(U),[1 1 1 1]);
E.psc4D = repmat(double(M),[1 1 1 1]);
E.created = datestr(now);
E.note = 'GroupAnalysis video export generated from group map.';
end

function localExportGroupMapPPT(hFig)
GA_exportGroupAnalysisPPTBundleFix_20260511(hFig,true);
end


function [M,U] = localApplyHemisphereFlip(S,rowIdx,M,U)
mode = localGetCharField(S,'mapFlipMode','Off');
if strcmpi(mode,'Off'), return; end
side = 'Unknown';
try, if rowIdx <= numel(S.rowPacapSide), side = strtrimSafeLocal(S.rowPacapSide{rowIdx}); end; catch, end
ref = localGetCharField(S,'mapRefPacapSide','Left');
doFlip = false;
if strcmpi(mode,'Flip right-injected animals') && strcmpi(side,'Right'), doFlip = true; end
if strcmpi(mode,'Flip left-injected animals') && strcmpi(side,'Left'), doFlip = true; end
if strcmpi(mode,'Align to Reference Hemisphere')
    if strcmpi(ref,'Left') && strcmpi(side,'Right'), doFlip = true; end
    if strcmpi(ref,'Right') && strcmpi(side,'Left'), doFlip = true; end
end
if doFlip
    M = fliplr(M);
    if ndims(U) == 3 && size(U,3) == 3, U = U(:,end:-1:1,:); else, U = fliplr(U); end
end
end

function A = localSqueeze2D(A,G)
A = double(A);
if ndims(A) == 2, return; end
if ndims(A) == 3
    if size(A,3) == 1
        A = A(:,:,1);
    else
        z = localPickZ(G,size(A,3));
        A = A(:,:,z);
    end
else
    error('Cannot squeeze this array to 2D.');
end
end

function z = localPickZ(G,nZ)
z = round(nZ/2);
names = {'atlasSliceIndex','currentSlice','sliceIdx','zIndex'};
for i = 1:numel(names)
    try
        if isfield(G,names{i}) && ~isempty(G.(names{i}))
            zz = double(G.(names{i})(1));
            if isfinite(zz), z = round(zz); break; end
        end
    catch
    end
end
z = max(1,min(nZ,z));
end

function U = localAnyTo2D(U,targetSz,G)
if nargin < 3, G = struct(); end
U = double(U);
if ndims(U) == 3 && size(U,3) == 3 && size(U,1) == targetSz(1) && size(U,2) == targetSz(2)
    U = localResizeLike(U,targetSz); return;
end
if ndims(U) == 3
    z = localPickZ(G,size(U,3));
    U = U(:,:,z);
elseif ndims(U) > 3
    U = squeeze(U);
    if ndims(U) > 2, U = U(:,:,1); end
end
U = localResizeLike(U,targetSz);
end

function B = localResizeLike(A,sz)
if numel(sz) > 2, sz = sz(1:2); end
if ndims(A) == 3 && size(A,3) == 3
    B = zeros(sz(1),sz(2),3);
    for c = 1:3, B(:,:,c) = localResizeLike(A(:,:,c),sz); end
    return;
end
if isequal(size(A),sz), B = A; return; end
try
    B = imresize(A,sz,'bilinear');
catch
    [Y,X] = size(A);
    [xq,yq] = meshgrid(linspace(1,X,sz(2)),linspace(1,Y,sz(1)));
    B = interp2(double(A),xq,yq,'linear',0);
end
end

function RGB = localToRGB(U)
if ndims(U) == 3 && size(U,3) == 3
    RGB = double(U);
    mx = max(RGB(:));
    if isfinite(mx) && mx > 1, RGB = RGB ./ 255; end
    RGB = min(max(RGB,0),1);
else
    G = localToGray(U);
    RGB = repmat(G,[1 1 3]);
end
end

function G = localToGray(U)
U = double(U);
if ndims(U) == 3 && size(U,3) == 3
    U = 0.2989*U(:,:,1) + 0.5870*U(:,:,2) + 0.1140*U(:,:,3);
end
U(~isfinite(U)) = 0;
mn = min(U(:)); mx = max(U(:));
if isfinite(mx) && isfinite(mn) && mx > mn
    G = (U-mn)./(mx-mn);
else
    G = zeros(size(U));
end
end

function A = localFlipUD(A)
if ndims(A) == 3 && size(A,3) == 3, A = A(end:-1:1,:,:); else, A = flipud(A); end
end

function cm = localCmap(name,n)
if nargin < 2, n = 256; end
name = lower(strtrimSafeLocal(name));
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
    otherwise
        cm = hot(n);
end
end

function B = localSmooth2D(A,sigma)
if sigma <= 0, B = A; return; end
try, B = imgaussfilt(A,sigma); return; catch, end
r = max(1,ceil(3*sigma));
x = -r:r; g = exp(-(x.^2)/(2*sigma^2)); g = g./sum(g);
B = conv2(conv2(double(A),g,'same'),g','same');
end

function M = localNanMean3(X)
n = sum(isfinite(X),3);
X(~isfinite(X)) = 0;
M = sum(X,3)./max(1,n);
M(n==0) = NaN;
end

function M = localNanMedian3(X)
sz = size(X);
Y = reshape(X,[],sz(3));
m = nan(size(Y,1),1);
for i = 1:size(Y,1)
    v = Y(i,:); v = v(isfinite(v));
    if ~isempty(v), m(i) = median(v); end
end
M = reshape(m,sz(1),sz(2));
end

function s = localGetCharField(S,name,fb)
s = fb;
try, if isstruct(S) && isfield(S,name) && ~isempty(S.(name)), s = strtrimSafeLocal(S.(name)); end; catch, end
end

function v = localGetNumField(S,name,fb)
v = fb;
try, if isstruct(S) && isfield(S,name) && ~isempty(S.(name)), v = double(S.(name)(1)); end; catch, end
if ~isfinite(v), v = fb; end
end

function v = localGetVecField(S,name,fb)
v = fb;
try
    if isstruct(S) && isfield(S,name) && numel(S.(name)) >= 2
        vv = double(S.(name)(1:2));
        if all(isfinite(vv)), v = vv(:)'; end
    end
catch
end
if numel(v) < 2 || v(2) <= v(1), v = fb; end
end

function v = localGetLogicalField(S,name,fb)
v = fb;
try, if isstruct(S) && isfield(S,name) && ~isempty(S.(name)), v = logical(S.(name)); end; catch, end
end

function s = strtrimSafeLocal(x)
try
    if isempty(x), s = ''; else, s = strtrim(char(x)); end
catch
    s = '';
end
end
function onExportGroupMapPPT_fromMain(varargin)
% Parser-safe Group Map PPT export helper.
hFig = [];
if nargin >= 1
    hFig = varargin{1};
end
if isempty(hFig) || ~ishghandle(hFig)
    hFig = gcf;
end
if isempty(hFig) || ~ishghandle(hFig)
    error('Invalid GroupAnalysis figure handle.');
end

S = guidata(hFig);
if isempty(S) || ~isstruct(S)
    error('Could not read GroupAnalysis GUI state.');
end
if ~isfield(S,'axMap1') || ~ishghandle(S.axMap1)
    error('Could not find current Group Map preview axis.');
end

startDir = pwd;
try
    if isfield(S,'outDir') && ~isempty(S.outDir) && exist(S.outDir,'dir') == 7
        startDir = S.outDir;
    elseif isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(S.opt.startDir,'dir') == 7
        startDir = S.opt.startDir;
    end
catch
end

defName = ['GroupMap_' datestr(now,'yyyymmdd_HHMMSS') '.pptx'];
[f,p] = uiputfile({'*.pptx','PowerPoint (*.pptx)'}, 'Save Group Map PPT', fullfile(startDir,defName));
if isequal(f,0)
    return;
end

outFile = fullfile(p,f);
[~,baseName] = fileparts(outFile);
pngFile = fullfile(p,[baseName '_preview.png']);

% Capture the existing preview axis directly. No visible new figure is created.
try
    fr = getframe(S.axMap1);
    imwrite(fr.cdata,pngFile);
catch MEcap
    try, GA_printErrorLocal(MEcap,'caught error in GroupAnalysis_Map.m'); catch, end
    error('Could not capture map preview axis: %s', MEcap.message);
end

if ~(ispc && exist('actxserver','file') == 2)
    error('PowerPoint export requires Windows with PowerPoint installed. PNG was saved here: %s', pngFile);
end

ppt = [];
pres = [];
try
    ppt = actxserver('PowerPoint.Application');
    ppt.Visible = 1;
    pres = ppt.Presentations.Add;

    sw = pres.PageSetup.SlideWidth;
    sh = pres.PageSetup.SlideHeight;

    slide = pres.Slides.Add(1,12);

    tb = slide.Shapes.AddTextbox(1,30,20,sw-60,35);
    tr = tb.TextFrame.TextRange;
    tr.Text = 'Group Map Preview';
    tr.Font.Size = 24;
    tr.Font.Bold = 1;

    slide.Shapes.AddPicture(pngFile,0,1,35,70,sw-70,sh-105);

    pres.SaveAs(outFile);
    pres.Close;
    ppt.Quit;

    fprintf('[saved] %s\n', outFile);
catch MEppt
    try, GA_printErrorLocal(MEppt,'caught error in GroupAnalysis_Map.m'); catch, end
    try, if ~isempty(pres), pres.Close; end, catch, end
    try, if ~isempty(ppt), ppt.Quit; end, catch, end
    error('PowerPoint export failed. PNG was saved here: %s. Reason: %s', pngFile, MEppt.message);
end
end


%%% GA_GROUPANALYSIS_SCM_PPT_PATCH_V3_START
function GA_onExportGroupMapPPT_fromMain_v3(varargin)
hFig = [];
if nargin >= 1, hFig = varargin{1}; end
if isempty(hFig) || ~ishghandle(hFig), hFig = gcf; end
if isempty(hFig) || ~ishghandle(hFig), error('Invalid GroupAnalysis figure handle.'); end

S = guidata(hFig);
if isempty(S) || ~isstruct(S), error('Could not read GroupAnalysis GUI state.'); end

[rows,bundles] = GA_bundleRowsForPPT_v3(S);
if isempty(bundles)
    error(['No SCM_GroupExport bundle paths found in GroupAnalysis table column 8.' char(10) ...
           'Open/add SCM bundles first, then run Export PPT again.']);
end

baseDefault = GA_defaultBaseWin_v3(S,bundles{1});
a = inputdlg({ ...
    'Injection start (sec). Empty if unknown:', ...
    'Window length (sec):', ...
    'Max minutes to export. Empty = all:', ...
    'Baseline window sec (start end):', ...
    'Maximum bundles to export. Empty = selected/all:'}, ...
    'GroupAnalysis full SCM time-series PPT', 1, ...
    {'','60','',sprintf('%g %g',baseDefault(1),baseDefault(2)),''});
if isempty(a), return; end

injSec = str2double(strtrim(a{1})); if ~isfinite(injSec), injSec = NaN; end
winLen = str2double(strtrim(a{2})); if ~isfinite(winLen) || winLen <= 0, winLen = 60; end
maxMin = str2double(strtrim(a{3})); if ~isfinite(maxMin) || maxMin <= 0, maxMin = NaN; end
baseWin = sscanf(strrep(strtrim(a{4}),'-',' '),'%f');
if numel(baseWin) < 2 || any(~isfinite(baseWin(1:2))), baseWin = baseDefault(:); else, baseWin = baseWin(1:2); end
baseWin = sort(double(baseWin(:)'));
maxBundles = str2double(strtrim(a{5}));
if isfinite(maxBundles) && maxBundles > 0
    nKeep = min(numel(bundles),round(maxBundles));
    bundles = bundles(1:nKeep);
    rows = rows(1:nKeep);
end

startDir = GA_startDir_v3(S);
[f,p] = uiputfile({'*.pptx','PowerPoint (*.pptx)'}, ...
    'Save GroupAnalysis full SCM PPT', ...
    fullfile(startDir,['GroupAnalysis_SCM_series_' datestr(now,'yyyymmdd_HHMMSS') '.pptx']));
if isequal(f,0), return; end
pptFile = fullfile(p,f);
[~,baseName] = fileparts(pptFile);
assetDir = fullfile(p,[baseName '_assets']);
tileDir = fullfile(assetDir,'tiles_png');
slideDir = fullfile(assetDir,'slide_png');
GA_mkdir_v3(assetDir); GA_mkdir_v3(tileDir); GA_mkdir_v3(slideDir);

slidePNGs = {};
skipped = {};
nTiles = 0;

for bi = 1:numel(bundles)
    bf = bundles{bi};
    try
        G = GA_loadAndNormalizeBundle_v3(bf);
        [TR,nT] = GA_getTRnT_v3(G);
        if ~isfinite(TR) || TR <= 0 || nT < 2
            error('Bundle has no valid TR/full PSC time dimension.');
        end

        S2 = S;
        S2.mapUseGlobalWindows = true;
        S2.mapSource = 'Recompute from exported PSC';
        S2.mapGlobalBaseSec = baseWin;

        if ~isfield(S2,'mapSigma') || isempty(S2.mapSigma) || ~isfinite(S2.mapSigma)
            if isfield(G,'sigma') && ~isempty(G.sigma) && isfinite(G.sigma(1))
                S2.mapSigma = double(G.sigma(1));
            else
                S2.mapSigma = 1;
            end
        end

        R = GA_renderStructFromState_v3(S2,G);
        cmForSlide = GA_cmapForSlide_v3(R);

        totalSec = (nT-1)*TR;
        starts = 0:winLen:(floor(totalSec/winLen)*winLen);
        if isfinite(maxMin), starts = starts(starts < maxMin*60); end
        if isempty(starts), starts = 0; end

        subj = GA_subjectFromRow_v3(S,rows(bi),bf,G);
        subjSafe = GA_safeName_v3(subj);
        tilePNGs = {};
        tileLbls = {};

        fprintf('\n[GA SCM PPT] %d/%d  %s\n',bi,numel(bundles),bf);

        for wi = 1:numel(starts)
            s0 = starts(wi);
            s1 = s0 + winLen;
            S2.mapGlobalSigSec = [s0 s1];

            [mapNow,winInfoTxt] = localBuildPreviewMapFromBundle(S2,G);
            U = localResolvePreviewUnderlay(S2,G,mapNow);

            try
                [mapNow,U] = localApplyHemisphereFlip(S2,rows(bi),mapNow,U);
            catch
            end

            phase = GA_phase_v3(s0,s1,injSec,winLen);
            lbl = sprintf('%.0f-%.0fs | %s',s0,s1,phase);
            tileTitle = sprintf('%s | %s | %s',subj,lbl,winInfoTxt);

            D = struct();
            D.underlay = U;
            D.map = mapNow;
            D.render = R;
            D.title = tileTitle;

            tileFile = fullfile(tileDir,sprintf('%03d_%s_w%03d.png',bi,subjSafe,wi));
            localExportMapDisplayPNG(tileFile,D,'Dark');

            tilePNGs{end+1} = tileFile; %#ok<AGROW>
            tileLbls{end+1} = lbl; %#ok<AGROW>
            nTiles = nTiles + 1;
        end

        perSlide = 6;
        nSlides = ceil(numel(tilePNGs)/perSlide);
        for si = 1:nSlides
            ii0 = (si-1)*perSlide + 1;
            ii1 = min(si*perSlide,numel(tilePNGs));
            idx = ii0:ii1;
            titleStr = sprintf('%s | %s',subj,GA_short_v3(bf,65));
            footerStr = sprintf('TR=%.4gs | baseline=%g-%gs | window=%gs | threshold=%g | caxis=[%g %g] | alphaMod=%d [%g %g]', ...
                TR,baseWin(1),baseWin(2),winLen,R.threshold,R.caxis(1),R.caxis(2),double(R.alphaModOn),R.modMin,R.modMax);
            slideFile = fullfile(slideDir,sprintf('slide_%03d_%s_%02d.png',bi,subjSafe,si));
            GA_renderMontageSlide_v3(slideFile,tilePNGs(idx),tileLbls(idx),cmForSlide,R.caxis,titleStr,footerStr);
            slidePNGs{end+1} = slideFile; %#ok<AGROW>
        end

    catch ME
        skipped{end+1} = sprintf('%s -> %s',bf,ME.message); %#ok<AGROW>
        try, fprintf(2,'[GA SCM PPT] skipped %s\nReason: %s\n',bf,ME.message); catch, end
    end
end

if isempty(slidePNGs)
    msg = 'No slides were created.';
    if ~isempty(skipped), msg = [msg char(10) char(10) strjoin(skipped,char(10))]; end
    error(msg);
end

GA_writePPTFromPNGs_v3(pptFile,slidePNGs);

fprintf('\nDONE. Saved full SCM time-series PPT:\n%s\n',pptFile);
fprintf('Assets:\n%s\n',assetDir);
fprintf('Slides: %d | Tiles: %d\n',numel(slidePNGs),nTiles);

try
    msgbox(sprintf('Saved:\n%s\n\nSlides: %d\nTiles: %d',pptFile,numel(slidePNGs),nTiles),'GroupAnalysis SCM PPT');
catch
end
end

function [rows,bundles] = GA_bundleRowsForPPT_v3(S)
rows = [];
bundles = {};
if ~isfield(S,'subj') || isempty(S.subj) || size(S.subj,2) < 8, return; end
n = size(S.subj,1);
sel = [];
try
    if isfield(S,'selectedRows') && ~isempty(S.selectedRows)
        sel = unique(round(double(S.selectedRows(:)')));
        sel = sel(sel>=1 & sel<=n);
    end
catch
    sel = [];
end
if isempty(sel), cand = 1:n; else, cand = sel; end
[rows,bundles] = GA_collectBundles_v3(S,cand);
if isempty(bundles) && ~isempty(sel)
    [rows,bundles] = GA_collectBundles_v3(S,1:n);
end
end

function [rows,bundles] = GA_collectBundles_v3(S,cand)
rows = [];
bundles = {};
seen = {};
for ii = 1:numel(cand)
    r = cand(ii);
    useRow = true;
    try, useRow = GA_toLogical_v3(S.subj{r,1}); catch, useRow = true; end
    if ~useRow, continue; end
    bf = '';
    try, bf = strtrim(char(S.subj{r,8})); catch, end
    if isempty(bf) || exist(bf,'file') ~= 2, continue; end
    key = lower(strrep(bf,'/','\'));
    if any(strcmp(seen,key)), continue; end
    seen{end+1} = key; %#ok<AGROW>
    rows(end+1) = r; %#ok<AGROW>
    bundles{end+1} = bf; %#ok<AGROW>
end
end

function tf = GA_toLogical_v3(x)
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

function G = GA_loadAndNormalizeBundle_v3(bf)
L = load(bf);
G = [];
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
if isempty(G) || ~isstruct(G), error('No SCM group bundle struct found.'); end

if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
    flds = {'psc4D','PSC4D','PSC','functionalPSC','Ipsc','I'};
    for k = 1:numel(flds)
        f = flds{k};
        if isfield(G,f) && ~isempty(G.(f)) && isnumeric(G.(f))
            X = G.(f);
            if (ndims(X)==3 && size(X,3)>=2) || (ndims(X)==4 && size(X,4)>=2)
                G.pscAtlas4D = X;
                break;
            end
        end
    end
end

if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
    error('Could not find full PSC time-series. Expected G.pscAtlas4D.');
end
end

function [TR,nT] = GA_getTRnT_v3(G)
TR = NaN;
nT = NaN;
try, TR = double(G.TR(1)); catch, end
X = G.pscAtlas4D;
if ndims(X) == 3
    nT = size(X,3);
elseif ndims(X) == 4
    nT = size(X,4);
end
end

function R = GA_renderStructFromState_v3(S,G)
R = struct();
R.threshold = GA_getNumField_v3(S,'mapThreshold',0);
R.caxis = GA_getVecField_v3(S,'mapCaxis',[0 100]);
R.alphaModOn = GA_getLogicalField_v3(S,'mapAlphaModOn',true);
R.modMin = GA_getNumField_v3(S,'mapModMin',15);
R.modMax = GA_getNumField_v3(S,'mapModMax',30);
R.colormapName = GA_getCharField_v3(S,'mapColormap','blackbdy_iso');
R.flipUDPreview = true;

try
    if isfield(G,'display') && isstruct(G.display)
        D = G.display;
        if isfield(D,'threshold') && ~isempty(D.threshold), R.threshold = double(D.threshold(1)); end
        if isfield(D,'caxis') && numel(D.caxis)>=2, R.caxis = double(D.caxis(1:2)); end
        if isfield(D,'alphaModOn') && ~isempty(D.alphaModOn), R.alphaModOn = logical(D.alphaModOn(1)); end
        if isfield(D,'modMin') && ~isempty(D.modMin), R.modMin = double(D.modMin(1)); end
        if isfield(D,'modMax') && ~isempty(D.modMax), R.modMax = double(D.modMax(1)); end
        if isfield(D,'colormapName') && ~isempty(D.colormapName), R.colormapName = char(D.colormapName); end
        if isfield(D,'cmapMatrix') && ~isempty(D.cmapMatrix), R.cmapMatrix = double(D.cmapMatrix); end
    end
catch
end

if numel(R.caxis)<2 || any(~isfinite(R.caxis(1:2))) || R.caxis(2)==R.caxis(1), R.caxis = [0 100]; end
if R.caxis(2) < R.caxis(1), R.caxis = fliplr(R.caxis); end
if R.modMax < R.modMin, tmp=R.modMin; R.modMin=R.modMax; R.modMax=tmp; end
end

function bw = GA_defaultBaseWin_v3(S,bf)
bw = [30 240];
try
    if isfield(S,'mapGlobalBaseSec') && numel(S.mapGlobalBaseSec)>=2
        v = double(S.mapGlobalBaseSec(1:2));
        if all(isfinite(v)) && v(2)>v(1), bw = v(:)'; return; end
    end
catch
end
try
    G = GA_loadAndNormalizeBundle_v3(bf);
    if isfield(G,'baseWindowSec') && numel(G.baseWindowSec)>=2
        v = double(G.baseWindowSec(1:2));
        if all(isfinite(v)) && v(2)>v(1), bw = v(:)'; return; end
    end
catch
end
end

function d = GA_startDir_v3(S)
d = pwd;
try
    if isfield(S,'outDir') && ~isempty(S.outDir) && exist(S.outDir,'dir')==7, d = char(S.outDir); return; end
catch
end
try
    if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(S.opt.startDir,'dir')==7
        d = char(S.opt.startDir); return;
    end
catch
end
end

function v = GA_getNumField_v3(S,f,fb)
v = fb;
try, if isfield(S,f) && ~isempty(S.(f)), v = double(S.(f)(1)); end, catch, end
if ~isfinite(v), v = fb; end
end

function v = GA_getVecField_v3(S,f,fb)
v = fb;
try
    if isfield(S,f) && numel(S.(f))>=2
        vv = double(S.(f)(1:2));
        if all(isfinite(vv)), v = vv(:)'; end
    end
catch
end
end

function v = GA_getLogicalField_v3(S,f,fb)
v = fb;
try, if isfield(S,f) && ~isempty(S.(f)), v = logical(S.(f)(1)); end, catch, end
end

function s = GA_getCharField_v3(S,f,fb)
s = fb;
try, if isfield(S,f) && ~isempty(S.(f)), s = strtrim(char(S.(f))); end, catch, end
end

function subj = GA_subjectFromRow_v3(S,row,bf,G)
subj = '';
try, subj = strtrim(char(S.subj{row,2})); catch, end
if isempty(subj) && isfield(G,'animalID') && ~isempty(G.animalID)
    try, subj = strtrim(char(G.animalID)); catch, end
end
if isempty(subj), [~,subj] = fileparts(bf); end
end

function s = GA_phase_v3(s0,s1,injSec,winLen)
if ~isfinite(injSec)
    s = sprintf('%d min',floor(s0/winLen)+1);
elseif s1 <= injSec
    s = 'Baseline';
elseif s0 < injSec && s1 > injSec
    s = 'Injection';
else
    m = floor((s0-injSec)/winLen)+1;
    if m < 1, m = 1; end
    s = sprintf('%d min PI',m);
end
end

function cm = GA_cmapForSlide_v3(R)
if isfield(R,'cmapMatrix') && ~isempty(R.cmapMatrix) && size(R.cmapMatrix,2)==3
    cm = double(R.cmapMatrix); cm = max(0,min(1,cm)); return;
end
try
    cm = localCmap(R.colormapName,256);
catch
    cm = hot(256);
end
end

function GA_renderMontageSlide_v3(outFile,pngList,lblList,cm,caxV,titleStr,footerStr)
figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off','MenuBar','none','ToolBar','none','NumberTitle','off');
set(figS,'Units','inches','Position',[0.5 0.5 13.333 7.5]);
set(figS,'PaperPositionMode','auto');

annotation(figS,'textbox',[0.02 0.89 0.96 0.10], ...
    'String',titleStr,'Color','w','EdgeColor','none','FontName','Arial','FontSize',14, ...
    'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
annotation(figS,'textbox',[0.28 0.01 0.70 0.06], ...
    'String',footerStr,'Color','w','EdgeColor','none','FontName','Arial','FontSize',9, ...
    'FontWeight','bold','HorizontalAlignment','right','Interpreter','none');

axCB = axes('Parent',figS,'Position',[0.012 0.14 0.001 0.74], ...
    'Visible','off','XTick',[],'YTick',[],'XColor','none','YColor','none','Box','off');
imagesc(axCB,[0 1; 0 1]);
colormap(axCB,cm);
caxis(axCB,caxV);
cbx = colorbar(axCB,'Position',[0.020 0.14 0.015 0.74]);
try
    cbx.Color = 'w'; cbx.FontName = 'Arial'; cbx.FontSize = 10;
    cbx.Label.String = 'Signal change (%)'; cbx.Label.Color = 'w';
    cbx.TickDirection = 'out'; cbx.Box = 'off';
catch
end

x0 = 0.095; x1 = 0.98; yBot = 0.12; yTop = 0.86;
rowGap = 0.06; colGap = 0.02;
cellH = (yTop-yBot-rowGap)/2;
cellW = (x1-x0-2*colGap)/3;

for k = 1:min(6,numel(pngList))
    if k <= 3
        cc = k-1; y = yBot + cellH + rowGap;
    else
        cc = k-4; y = yBot;
    end
    x = x0 + cc*(cellW+colGap);
    axI = axes('Parent',figS,'Position',[x y cellW cellH]);
    image(axI,imread(pngList{k}));
    axis(axI,'image'); axis(axI,'off');
    annotation(figS,'textbox',[x y+cellH+0.005 cellW 0.035], ...
        'String',lblList{k},'Color','w','EdgeColor','none','FontName','Arial', ...
        'FontSize',12,'FontWeight','bold','HorizontalAlignment','center','Interpreter','none');
end

print(figS,outFile,'-dpng','-r200','-opengl');
close(figS);
end

function GA_writePPTFromPNGs_v3(pptFile,slidePNGs)
if exist(pptFile,'file')==2
    try, delete(pptFile); catch, error('Could not overwrite PPT: %s',pptFile); end
end

if ~isempty(which('mlreportgen.ppt.Presentation'))
    import mlreportgen.ppt.*
    ppt = [];
    try
        ppt = Presentation(pptFile); open(ppt);
        for i = 1:numel(slidePNGs)
            try, slide = add(ppt,'Blank'); catch, slide = add(ppt); end
            pic = Picture(slidePNGs{i});
            pic.X = '0in'; pic.Y = '0in'; pic.Width = '13.333in'; pic.Height = '7.5in';
            add(slide,pic);
        end
        close(ppt);
    catch ME
        try, if ~isempty(ppt), close(ppt); end, catch, end
        error('mlreportgen PPT export failed: %s',ME.message);
    end
elseif ispc && exist('actxserver','file')==2
    ppt = []; pres = [];
    try
        ppt = actxserver('PowerPoint.Application'); ppt.Visible = 1;
        pres = ppt.Presentations.Add;
        sw = pres.PageSetup.SlideWidth; sh = pres.PageSetup.SlideHeight;
        for i = 1:numel(slidePNGs)
            slide = pres.Slides.Add(i,12);
            slide.Shapes.AddPicture(slidePNGs{i},0,1,0,0,sw,sh);
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

pause(0.3);
if exist(pptFile,'file')~=2, error('PPT file was not created: %s',pptFile); end
end

function s = GA_safeName_v3(s)
try, s = char(s); catch, s = 'export'; end
s = regexprep(s,'[<>:"/\\|?*\x00-\x1F]','_');
s = regexprep(s,'[^A-Za-z0-9_\-]','_');
s = regexprep(s,'_+','_');
s = regexprep(s,'^_+|_+$','');
if isempty(s), s = 'export'; end
if numel(s)>50, s = s(1:50); end
end

function s = GA_short_v3(s,n)
try, s = char(s); catch, s = ''; end
if numel(s)>n, s = [s(1:max(1,n-3)) '...']; end
end

function GA_mkdir_v3(d)
if exist(d,'dir')~=7
    ok = mkdir(d);
    if ~ok, error('Could not create folder: %s',d); end
end
end
%%% GA_GROUPANALYSIS_SCM_PPT_PATCH_V3_END
