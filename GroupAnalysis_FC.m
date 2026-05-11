function varargout = GroupAnalysis_FC(action, varargin)

if nargin < 1 || isempty(action)
    error('GroupAnalysis_FC requires an action string.');
end

actionIn = strtrim(char(action));
fnLocal = resolveLocalActionName_GA_dispatch(actionIn);

if isempty(fnLocal)
    error('Unknown GroupAnalysis_FC action: %s', actionIn);
end

fh = str2func(fnLocal);

try
    if nargout == 0
        fh(varargin{:});
    else
        [varargout{1:nargout}] = fh(varargin{:});
    end
catch ME
    try, GA_printErrorLocal(ME,'caught error in GroupAnalysis_FC.m'); catch, end
    ga_print_module_error_local(ME, actionIn, fnLocal, 'GroupAnalysis_FC');
    rethrow(ME);
end
end

function ga_print_module_error_local(ME, actionIn, fnLocal, moduleName)
% Print full module errors in Command Window.
try
    nl = char(10);
    sep = repmat('=', 1, 70);
    fprintf(2, '%s%c', sep, 10);
    fprintf(2, 'ERROR in %s action: %s%c', moduleName, actionIn, 10);
    fprintf(2, 'Local function: %s%c', fnLocal, 10);
    fprintf(2, 'Message: %s%c', ME.message, 10);
    fprintf(2, '%s%c', sep, 10);
    try
        fprintf(2, '%s%c', getReport(ME, 'extended', 'hyperlinks', 'on'), 10);
    catch
        for kk = 1:numel(ME.stack)
            fprintf(2, '  %s | line %d | %s%c', ...
                ME.stack(kk).name, ME.stack(kk).line, ME.stack(kk).file, 10);
        end
    end
    fprintf(2, '%s%c%c', sep, 10, 10);
catch
    try
        fprintf(2, 'GroupAnalysis module error: %s%c', ME.message, 10);
    catch
    end
end
end

function fnLocal = resolveLocalActionName_GA_dispatch(actionIn)
fnLocal = '';

try
    thisFile = [mfilename('fullpath') '.m'];
    txtLocal = fileread(thisFile);
catch
    return;
end

% Collect all function names in this module.
tok = regexp(txtLocal, '(?m)^\s*function\s+(?:\[[^\]]*\]\s*=\s*|[A-Za-z]\w*\s*=\s*)?([A-Za-z]\w*)\s*(?:\(|$)', 'tokens');

if isempty(tok)
    return;
end

names = cell(size(tok));
for ii = 1:numel(tok)
    names{ii} = tok{ii}{1};
end

skip = strcmpi(names, mfilename) | strcmpi(names, 'resolveLocalActionName_GA_dispatch');
names = names(~skip);

% First try exact case-insensitive match.
hit = find(strcmpi(names, actionIn), 1, 'first');
if ~isempty(hit)
    fnLocal = names{hit};
    return;
end

% Then try normalized match: removes underscores, spaces, dashes, punctuation.
normAction = lower(regexprep(actionIn, '[^A-Za-z0-9]', ''));
for ii = 1:numel(names)
    normName = lower(regexprep(names{ii}, '[^A-Za-z0-9]', ''));
    if strcmp(normName, normAction)
        fnLocal = names{ii};
        return;
    end
end
end


% =====================================================================
% COPIED LOCAL FUNCTIONS FROM GroupAnalysis.m
% =====================================================================

function fileList = findFCBundlesRecursive(rootDir)
fileList = {};

if nargin < 1 || isempty(rootDir) || exist(rootDir,'dir') ~= 7
    return;
end

d = dir(fullfile(rootDir,'FC_GroupBundle_*.mat'));
for i = 1:numel(d)
    fileList{end+1,1} = fullfile(d(i).folder,d(i).name); %#ok<AGROW>
end

sub = dir(rootDir);
for i = 1:numel(sub)
    if ~sub(i).isdir
        continue;
    end

    nm = sub(i).name;
    if strcmp(nm,'.') || strcmp(nm,'..')
        continue;
    end

    more = findFCBundlesRecursive(fullfile(rootDir,nm));
    if ~isempty(more)
        fileList = [fileList; more(:)]; %#ok<AGROW>
    end
end
end

function tf = isFCGroupBundleFile(fp)
tf = false;

if nargin < 1 || isempty(fp) || exist(fp,'file') ~= 2
    return;
end

try
    info = whos('-file',fp);
    vars = {info.name};
    if any(strcmp(vars,'fcBundle'))
        tf = true;
        return;
    end
catch
end

[~,nm,ext] = fileparts(fp);
if strcmpi(ext,'.mat') && ~isempty(regexpi(nm,'^FC_GroupBundle_','once'))
    tf = true;
end
end

function [B, cache] = getCachedFCBundle(cache, fp)
key = makeCacheKey('FCBUNDLE',fp);

if isstruct(cache) && isfield(cache,'fcBundle') && isa(cache.fcBundle,'containers.Map')
    try
        if isKey(cache.fcBundle,key)
            B = cache.fcBundle(key);
            return;
        end
    catch
    end
end

L = load(fp);

if isfield(L,'fcBundle')
    B = L.fcBundle;
else
    error('File does not contain variable fcBundle: %s', fp);
end

if ~isstruct(B) || ~isfield(B,'subjects')
    error('Invalid FC group bundle: %s', fp);
end

if isstruct(cache) && isfield(cache,'fcBundle') && isa(cache.fcBundle,'containers.Map')
    try
        cache.fcBundle(key) = B;
    catch
    end
end
end

function [FC, cache] = loadFCGroupBundlesFromFiles(fileList, cache)
FC = struct();
FC.files = fileList(:);
FC.subjects = struct([]);
FC.nSubjects = 0;

idx = 0;

for i = 1:numel(fileList)
    fp = fileList{i};

    if ~isFCGroupBundleFile(fp)
        continue;
    end

    [B, cache] = getCachedFCBundle(cache, fp);

    for j = 1:numel(B.subjects)
        subj = B.subjects(j);

        if ~isfield(subj,'labels') || isempty(subj.labels)
            continue;
        end

        if ~isfield(subj,'R') || isempty(subj.R)
            continue;
        end

        idx = idx + 1;

        FC.subjects(idx).sourceFile = fp;

        if isfield(subj,'name') && ~isempty(subj.name)
            FC.subjects(idx).name = strtrimSafe(subj.name);
        else
            FC.subjects(idx).name = sprintf('FC_Subject_%02d',idx);
        end

        if isfield(subj,'group') && ~isempty(subj.group)
            FC.subjects(idx).group = strtrimSafe(subj.group);
        else
            FC.subjects(idx).group = inferFCGroupFromText([FC.subjects(idx).name ' ' fp]);
        end

        if isempty(FC.subjects(idx).group) || strcmpi(FC.subjects(idx).group,'All')
            FC.subjects(idx).group = inferFCGroupFromText([FC.subjects(idx).name ' ' fp]);
        end

        FC.subjects(idx).labels = double(subj.labels(:));

        if isfield(subj,'names') && ~isempty(subj.names)
            FC.subjects(idx).names = subj.names(:);
        else
            FC.subjects(idx).names = makeDefaultFCNames(FC.subjects(idx).labels);
        end

        FC.subjects(idx).R = double(subj.R);

        if isfield(subj,'Z') && ~isempty(subj.Z)
            FC.subjects(idx).Z = double(subj.Z);
        else
            Rtmp = double(subj.R);
            Rtmp = max(-0.999999,min(0.999999,Rtmp));
            Ztmp = atanh(Rtmp);
            Ztmp(1:size(Ztmp,1)+1:end) = 0;
            FC.subjects(idx).Z = Ztmp;
        end
    end
end

FC.nSubjects = idx;
end

function names = makeDefaultFCNames(labels)
names = cell(numel(labels),1);
for i = 1:numel(labels)
    names{i} = sprintf('ROI_%g',labels(i));
end
end

function g = inferFCGroupFromText(txt)
g = 'Unassigned';

u = upper(strtrimSafe(txt));

if contains(u,'PACAP') || contains(u,'GROUPA') || contains(u,'CONDA')
    g = 'PACAP';
elseif contains(u,'VEHICLE') || contains(u,'VEH') || contains(u,'CONTROL') || contains(u,'GROUPB') || contains(u,'CONDB')
    g = 'Vehicle';
end
end

function G = alignFCSubjectsToCommonROIs(FC)
if ~isfield(FC,'subjects') || isempty(FC.subjects)
    error('No FC subjects loaded.');
end

nSub = numel(FC.subjects);

commonLabels = FC.subjects(1).labels(:);

for i = 2:nSub
    commonLabels = intersect(commonLabels,FC.subjects(i).labels(:));
end

commonLabels = sort(commonLabels(:));

if isempty(commonLabels)
    error('No common ROI labels found across FC subjects.');
end

nR = numel(commonLabels);
Zstack = nan(nR,nR,nSub);
Rstack = nan(nR,nR,nSub);
names = cell(nR,1);

for i = 1:nSub
    labs = FC.subjects(i).labels(:);

    idx = nan(nR,1);
    for k = 1:nR
        hit = find(double(labs) == double(commonLabels(k)),1,'first');
        if ~isempty(hit)
            idx(k) = hit;
        end
    end

    if any(~isfinite(idx))
        error('Internal FC ROI alignment error.');
    end

    idx = double(idx(:));

    Zstack(:,:,i) = FC.subjects(i).Z(idx,idx);
    Rstack(:,:,i) = FC.subjects(i).R(idx,idx);

    if i == 1
        for k = 1:nR
            srcIdx = idx(k);
            if srcIdx <= numel(FC.subjects(i).names)
                names{k} = strtrimSafe(FC.subjects(i).names{srcIdx});
            else
                names{k} = sprintf('ROI_%g',commonLabels(k));
            end
        end
    end
end

G = struct();
G.labels = commonLabels;
G.names = names;
G.Zstack = Zstack;
G.Rstack = Rstack;
G.nSubjects = nSub;

G.subjectNames = cell(nSub,1);
G.groups = cell(nSub,1);
G.sourceFiles = cell(nSub,1);

for i = 1:nSub
    G.subjectNames{i} = FC.subjects(i).name;
    G.groups{i} = FC.subjects(i).group;
    G.sourceFiles{i} = FC.subjects(i).sourceFile;
end
end

function R = computeGroupFCStats(G, groupA, groupB)
idxA = strcmpi(G.groups,groupA);
idxB = strcmpi(G.groups,groupB);

if ~any(idxA)
    error(['No FC subjects found for Group A: ' groupA]);
end

if ~any(idxB)
    error(['No FC subjects found for Group B: ' groupB]);
end

ZA = G.Zstack(:,:,idxA);
ZB = G.Zstack(:,:,idxB);

meanZA = fcNanMean3(ZA);
meanZB = fcNanMean3(ZB);

diffZ = meanZA - meanZB;

[nR,~,~] = size(G.Zstack);
pMat = nan(nR,nR);
tMat = nan(nR,nR);

for r = 1:nR
    for c = 1:nR
        a = squeeze(ZA(r,c,:));
        b = squeeze(ZB(r,c,:));

        a = a(isfinite(a));
        b = b(isfinite(b));

        if numel(a) >= 2 && numel(b) >= 2
            [t,p,~] = welchT_vec(a,b);
            tMat(r,c) = t;
            pMat(r,c) = p;
        end
    end
end

R = struct();
R.mode = 'Functional Connectivity';
R.groupA = groupA;
R.groupB = groupB;
R.nA = sum(idxA);
R.nB = sum(idxB);

R.labels = G.labels;
R.names = G.names;

R.meanZA = meanZA;
R.meanZB = meanZB;
R.meanRA = tanh(meanZA);
R.meanRB = tanh(meanZB);

R.diffZ = diffZ;
R.diffR = tanh(meanZA) - tanh(meanZB);

R.pMat = pMat;
R.tMat = tMat;

R.subjectNames = G.subjectNames;
R.groups = G.groups;
R.sourceFiles = G.sourceFiles;
R.note = 'Statistics are computed on Fisher z. Pearson r matrices are tanh(mean z) for display.';
end

function M = fcNanMean3(X)
[n1,n2,~] = size(X);
M = nan(n1,n2);

for r = 1:n1
    for c = 1:n2
        v = squeeze(X(r,c,:));
        v = v(isfinite(v));
        if ~isempty(v)
            M(r,c) = mean(v);
        end
    end
end
end

function fcNoData(ax,titleStr,C)
cla(ax);

text(ax,0.5,0.5,'No data', ...
    'HorizontalAlignment','center', ...
    'VerticalAlignment','middle', ...
    'Color',C.txt, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold');

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'XTick',[], ...
    'YTick',[]);

title(ax,titleStr,'Color',C.txt,'FontWeight','bold','Interpreter','none');
end

function fcPlotMatrix(ax,M,climVal,titleStr,names,C)
cla(ax);

if isempty(M)
    fcNoData(ax,titleStr,C);
    return;
end

imagesc(ax,M);
axis(ax,'image');
caxis(ax,climVal);
colormap(ax,fcBlueWhiteRed(256));
cb = colorbar(ax);
try, set(cb,'Color',[1 1 1]); catch, end

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'FontName','Arial', ...
    'FontSize',8, ...
    'TickLength',[0 0]);

title(ax,titleStr,'Color',C.txt,'FontWeight','bold','Interpreter','none');

nR = size(M,1);
tickIdx = fcTickIdx(nR);

set(ax,'XTick',tickIdx,'YTick',tickIdx, ...
    'XTickLabel',fcAbbrevNames(names(tickIdx),10), ...
    'YTickLabel',fcAbbrevNames(names(tickIdx),10));

try
    xtickangle(ax,90);
catch
end
end

function fcPlotPMatrix(ax,P,titleStr,names,C)
cla(ax);

if isempty(P)
    fcNoData(ax,titleStr,C);
    return;
end

Plog = -log10(P);
Plog(~isfinite(Plog)) = NaN;

imagesc(ax,Plog);
axis(ax,'image');
caxis(ax,[0 3]);
colormap(ax,hot(256));
cb = colorbar(ax);
try, set(cb,'Color',[1 1 1]); catch, end

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'FontName','Arial', ...
    'FontSize',8, ...
    'TickLength',[0 0]);

title(ax,[titleStr ' (-log10 p)'],'Color',C.txt,'FontWeight','bold','Interpreter','none');

nR = size(P,1);
tickIdx = fcTickIdx(nR);

set(ax,'XTick',tickIdx,'YTick',tickIdx, ...
    'XTickLabel',fcAbbrevNames(names(tickIdx),10), ...
    'YTickLabel',fcAbbrevNames(names(tickIdx),10));

try
    xtickangle(ax,90);
catch
end
end

function idx = fcTickIdx(nR)
if nR <= 35
    step = 1;
elseif nR <= 70
    step = 2;
elseif nR <= 120
    step = 4;
elseif nR <= 200
    step = 6;
else
    step = max(8,ceil(nR/30));
end

idx = 1:step:nR;
end

function out = fcAbbrevNames(names,n)
if nargin < 2
    n = 10;
end

out = names;

for i = 1:numel(out)
    s = strtrimSafe(out{i});
    s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
    parts = regexp(s,'\s+','split');

    if ~isempty(parts)
        s = parts{1};
    end

    if numel(s) > n
        s = [s(1:max(1,n-3)) '...'];
    end

    out{i} = s;
end
end

function cmap = fcBlueWhiteRed(n)
if nargin < 1
    n = 256;
end

n1 = floor(n/2);
n2 = n - n1;

b = [0.00 0.25 0.95];
w = [1.00 1.00 1.00];
r = [0.95 0.20 0.20];

c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];

cmap = [c1; c2];
end

function writeFCMatrixCSV(fileName,M,names)
fid = fopen(fileName,'w');

if fid < 0
    error(['Could not write CSV: ' fileName]);
end

cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'ROI');

for j = 1:numel(names)
    fprintf(fid,',%s',csvEscapeFC(names{j}));
end

fprintf(fid,'\n');

for i = 1:size(M,1)
    fprintf(fid,'%s',csvEscapeFC(names{i}));

    for j = 1:size(M,2)
        fprintf(fid,',%.10g',M(i,j));
    end

    fprintf(fid,'\n');
end
end

function s = csvEscapeFC(s0)
s = char(s0);
s = strrep(s,'"','""');
s = ['"' s '"'];
end

function saveFCAxisPNG(ax,fileName,C)
try
    f = figure('Visible','off', ...
        'Color',C.bg, ...
        'InvertHardcopy','off', ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off');

    set(f,'Position',[100 100 1100 900]);

    ax2 = copyobj(ax,f);
    set(ax2,'Units','normalized','Position',[0.10 0.13 0.74 0.74]);

    set(f,'PaperPositionMode','auto');
    print(f,fileName,'-dpng','-r250');
    close(f);
catch
end
end

function h = mkBtn(parent, txt, pos, bg, cb)
h = uicontrol(parent,'Style','pushbutton','String',txt, ...
    'Units','normalized','Position',pos, ...
    'BackgroundColor',bg,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',12,'Callback',cb);
end

function h = mkTabBtn(parent, txt, pos, cb)
h = uicontrol(parent,'Style','pushbutton','String',txt, ...
    'Units','normalized','Position',pos, ...
    'BackgroundColor',[0.18 0.18 0.18], ...
    'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',11,'Callback',cb);
end

function d = defaultOutDir(opt)
d = pwd;
if isfield(opt,'studio') && isstruct(opt.studio)
    P = studio_resolve_paths(opt.studio, 'GroupAnalysis', '');
    d = P.groupDir;
end
end

function s = sanitizeFilename(s)
if isstring(s), s = char(s); end
s = strtrim(char(s));
if isempty(s), s = 'export'; end
s = regexprep(s,'[<>:"/\\|?*\x00-\x1F]','_');
s = regexprep(s,'[^A-Za-z0-9_\-]','_');
s = regexprep(s,'_+','_');
s = regexprep(s,'^[\._]+','');
s = regexprep(s,'[\._]+$','');
if isempty(s), s = 'export'; end
maxLen = 60;
if numel(s) > maxLen, s = s(1:maxLen); end
end

function A = flipud_any(A)
if isempty(A), return; end
if ndims(A) == 2
    A = flipud(A);
elseif ndims(A) == 3
    A = A(end:-1:1,:,:);
else
    error('flipud_any supports 2D or 3D arrays only.');
end
end

function s = strtrimSafe(x)
try
    if isempty(x)
        s = '';
    else
        s = strtrim(char(x));
    end
catch
    s = '';
end
end

function v = safeNum(str, fallback)
v = str2double(str);
if isnan(v) || ~isfinite(v)
    v = fallback;
end
end

function v = logicalCellValue(x)
try
    if islogical(x)
        v = x;
    elseif isnumeric(x)
        v = (x ~= 0);
    elseif ischar(x) || isstring(x)
        s = lower(strtrim(char(x)));
        v = any(strcmp(s, {'1','true','yes','y','on'}));
    else
        v = logical(x);
    end
catch
    v = false;
end
end

function Rm = makeMapRenderStruct(S)
Rm = struct();
Rm.threshold = 0;
Rm.caxis = S.mapCaxis;
Rm.alphaModOn = S.mapAlphaModOn;
Rm.modMin = S.mapModMin;
Rm.modMax = S.mapModMax;
Rm.blackBody = S.mapBlackBody;
Rm.colormapName = S.mapColormap;
Rm.flipUDPreview = true;
end

function sel = clampSelRows(sel, nRows)
if isempty(sel)
    sel = [];
    return;
end
sel = unique(sel(:)');
sel = sel(sel>=1 & sel<=nRows);
end

function tf = logicalCol(tbl, col)
tf = true(size(tbl,1),1);
for i = 1:size(tbl,1)
    try
        tf(i) = logical(tbl{i,col});
    catch
        tf(i) = true;
    end
end
end

function idx = findActiveROIRowsGA(subj)
idx = [];
for i = 1:size(subj,1)
    if ~logicalCellValue(subj{i,1})
        continue;
    end
    roiFile = strtrimSafe(subj{i,7});
    if ~isempty(roiFile) && exist(roiFile,'file') == 2
        idx(end+1) = i; %#ok<AGROW>
    end
end
end

      function [idx, missingIdx] = findActiveBundleRowsGA(S)
    idx = [];
    missingIdx = [];

    dispRows = findBundleDisplayRowsGA(S);

    for i = 1:numel(dispRows)
        r = dispRows(i);
        key = makeBundleEntityKeyForRow(S, r);

        if isempty(key)
            continue;
        end

        if ~entityUseStateForKey(S, key)
            continue;
        end

        bf = strtrimSafe(S.subj{r,8});
        if isempty(bf)
            try
                bf = resolveGroupBundlePath(S, S.subj(r,:));
            catch
                bf = '';
            end
        end

        if isempty(bf) || ~isScmGroupBundleFile(bf)
            missingIdx = [missingIdx getRowsForBundleEntityKey(S, key)]; %#ok<AGROW>
        else
            idx(end+1) = r; %#ok<AGROW>
        end
    end

    missingIdx = unique(missingIdx,'stable');
end

function col = colAsStr(C, j)
col = cell(size(C,1),1);
for i = 1:size(C,1)
    col{i} = strtrimSafe(C{i,j});
end
end

function u = uniqueStable(C)
C = C(:);
C = C(~cellfun(@isempty,C));
u = {};
for i = 1:numel(C)
    if ~any(strcmpi(u, C{i}))
        u{end+1,1} = C{i}; %#ok<AGROW>
    end
end
end

function S = rememberGroupCondPair(S, groupName, condName)
groupName = strtrimSafe(groupName);
condName  = strtrimSafe(condName);

if isempty(groupName) || isempty(condName)
    return;
end

try
    if isa(S.groupToCondMap,'containers.Map')
        S.groupToCondMap(upper(groupName)) = condName;
    end
catch
end
end

function S = sanitizeTableStruct(S)
if isempty(S.subj), return; end
if size(S.subj,2) < 9, S.subj(:,end+1:9) = {''}; end
if size(S.subj,2) > 9, S.subj = S.subj(:,1:9); end

for r = 1:size(S.subj,1)
    if isempty(S.subj{r,1}) || ...
            ~(islogical(S.subj{r,1}) || isnumeric(S.subj{r,1}) || ischar(S.subj{r,1}) || isstring(S.subj{r,1}))
        S.subj{r,1} = true;
    else
        S.subj{r,1} = logicalCellValue(S.subj{r,1});
    end

    meta = extractMetaFromSources(S.subj{r,2}, S.subj{r,6}, S.subj{r,7}, S.subj{r,8});

    if strcmpi(meta.animalID,'N/A') || isempty(meta.animalID)
        if isempty(strtrimSafe(S.subj{r,2}))
            S.subj{r,2} = ['S' num2str(r)];
        else
            S.subj{r,2} = strtrimSafe(S.subj{r,2});
        end
    else
        S.subj{r,2} = meta.animalID;
    end

    if isempty(strtrimSafe(S.subj{r,3})), S.subj{r,3} = S.defaultGroup; end
    if isempty(strtrimSafe(S.subj{r,4})), S.subj{r,4} = S.defaultCond;  end

    if isempty(strtrimSafe(S.subj{r,9})) && ~logicalCellValue(S.subj{r,1})
        S.subj{r,9} = 'Not used';
    end
end
end

function out = mergeUniqueStable(a,b)
if isempty(a), a={}; end
if isempty(b), b={}; end
out = a(:).';
for i = 1:numel(b)
    if isempty(b{i}), continue; end
    if ~any(strcmpi(out,b{i}))
        out{end+1} = b{i}; %#ok<AGROW>
    end
end
end

    function V = subjToUITable(subj)
n = size(subj,1);
V = cell(n,9);

for i = 1:n
    meta = extractMetaFromSources(subj{i,2}, subj{i,6}, subj{i,7}, subj{i,8});

    V{i,1} = logicalCellValue(subj{i,1});
    V{i,2} = meta.animalID;
    V{i,3} = meta.session;
    V{i,4} = displayScanID(meta.scanID);
    V{i,5} = strtrimSafe(subj{i,3});
    V{i,6} = strtrimSafe(subj{i,4});
    V{i,7} = simplifyROIFileLabel(strtrimSafe(subj{i,7}));
    V{i,8} = bundlePresenceLabel(strtrimSafe(subj{i,8}));
    V{i,9} = deriveRowStatus(subj(i,:));
end
end

function subj = applyUITableToSubj(subj, V)
n = size(V,1);

if isempty(subj)
    subj = cell(n,9);
end

if size(subj,1) < n
    subj(end+1:n,1:9) = {''};
end
if size(subj,1) > n
    subj = subj(1:n,:);
end

for i = 1:n
    subj{i,1} = logicalCellValue(V{i,1});
    subj{i,2} = strtrimSafe(V{i,2});
    subj{i,3} = strtrimSafe(V{i,5});
    subj{i,4} = strtrimSafe(V{i,6});

    if isempty(subj{i,5}), subj{i,5} = ''; end
    if isempty(subj{i,6}), subj{i,6} = ''; end
    if isempty(subj{i,7}), subj{i,7} = ''; end
    if isempty(subj{i,8}), subj{i,8} = ''; end
    if isempty(subj{i,9}), subj{i,9} = ''; end
end
end

   function s = deriveRowStatus(row)
    roi    = '';
    bundle = '';
    st     = '';
    use    = true;

    try, roi    = strtrimSafe(row{7}); catch, end
    try, bundle = strtrimSafe(row{8}); catch, end
    try, st     = lower(strtrimSafe(row{9})); catch, end
    try, use    = logicalCellValue(row{1}); catch, end

    % IMPORTANT:
    % Do not call exist(...) on every redraw for network paths.
    % Just treat non-empty paths as "set".
    roiSet    = ~isempty(roi);
    bundleSet = ~isempty(bundle);

    if contains(st,'excluded')
        s = 'Excluded';
    elseif ~use
        s = 'Not used';
    elseif roiSet || bundleSet
        s = 'OK';
    elseif isempty(roi) && isempty(bundle)
        s = 'Not set';
    else
        s = 'Missing';
    end
end

function [hAuto,hZero,hStep,hYmin,hYmax,hYminM,hYminP,hYmaxM,hYmaxP] = mkYControlsStepCompact(parent, y0, label, cfg, C, cbEdit, cbYminM, cbYminP, cbYmaxM, cbYmaxP)
bg = get(parent,'BackgroundColor');
rowH = 0.18;

uicontrol(parent,'Style','text','String',[label ':'], ...
    'Units','normalized','Position',[0.02 y0 0.08 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hAuto = uicontrol(parent,'Style','checkbox','String','Auto', ...
    'Units','normalized','Position',[0.11 y0 0.12 rowH], ...
    'Value',double(cfg.auto), 'BackgroundColor',bg,'ForegroundColor','w','Callback',cbEdit);

hZero = uicontrol(parent,'Style','checkbox','String','Force 0', ...
    'Units','normalized','Position',[0.24 y0 0.14 rowH], ...
    'Value',double(cfg.forceZero), 'BackgroundColor',bg,'ForegroundColor','w','Callback',cbEdit);

uicontrol(parent,'Style','text','String','Step:', ...
    'Units','normalized','Position',[0.40 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hStep = uicontrol(parent,'Style','edit','String',num2str(cfg.step), ...
    'Units','normalized','Position',[0.46 y0+0.01 0.06 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

uicontrol(parent,'Style','text','String','Ymin:', ...
    'Units','normalized','Position',[0.54 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmin = uicontrol(parent,'Style','edit','String',num2str(cfg.ymin), ...
    'Units','normalized','Position',[0.60 y0+0.01 0.08 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

hYminM = uicontrol(parent,'Style','pushbutton','String','-', ...
    'Units','normalized','Position',[0.69 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYminM);

hYminP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.73 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYminP);

uicontrol(parent,'Style','text','String','Ymax:', ...
    'Units','normalized','Position',[0.78 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmax = uicontrol(parent,'Style','edit','String',num2str(cfg.ymax), ...
    'Units','normalized','Position',[0.84 y0+0.01 0.07 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

hYmaxM = uicontrol(parent,'Style','pushbutton','String','-', ...
    'Units','normalized','Position',[0.92 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYmaxM);

hYmaxP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.96 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYmaxP);
end

function fixAxesInset(ax)
try
    ti = get(ax,'TightInset');
    li = [max(ti(1),0.02) max(ti(2),0.02) max(ti(3),0.02) max(ti(4),0.02)];
    set(ax,'LooseInset',li);
catch
end
end

function [bg,fg] = previewColors(styleName)
if strcmpi(styleName,'Dark')
    bg = [0 0 0];
    fg = [1 1 1];
else
    bg = [1 1 1];
    fg = [0 0 0];
end
end

function styleAxesMode(ax, styleName, showGrid)
[bg,fg] = previewColors(styleName);
set(ax,'Color',bg,'XColor',fg,'YColor',fg);
if strcmpi(styleName,'Dark')
    try, set(ax,'GridColor',[0.7 0.7 0.7]); catch, end
    try, set(ax,'MinorGridColor',[0.8 0.8 0.8]); catch, end
else
    try, set(ax,'GridColor',[0.2 0.2 0.2]); catch, end
    try, set(ax,'MinorGridColor',[0.3 0.3 0.3]); catch, end
end
try, set(ax,'GridAlpha',0.18); catch, end
try, set(ax,'MinorGridAlpha',0.10); catch, end
if showGrid
    grid(ax,'on');
else
    grid(ax,'off');
end
box(ax,'off');
end

function recolorAxesText(ax, styleName)
[~,fg] = previewColors(styleName);
try, set(ax,'XColor',fg,'YColor',fg); catch, end
try, set(get(ax,'Title'),'Color',fg); catch, end
try, set(get(ax,'XLabel'),'Color',fg); catch, end
try, set(get(ax,'YLabel'),'Color',fg); catch, end
end

function styleColorbarMode(cb, styleName)
[~,fg] = previewColors(styleName);
try, set(cb,'Color',fg); catch, end
try, set(get(cb,'Label'),'Color',fg); catch, end
try, set(cb,'Box','off'); catch, end
end

function styleLegendMode(lg, styleName)
[bg,fg] = previewColors(styleName);
try, set(lg,'TextColor',fg); catch, end
try, set(lg,'Color',bg); catch, end
try, set(lg,'EdgeColor','none'); catch, end
end

function moveTitleUp(ax, yPos)
if nargin < 2, yPos = 1.09; end
th = get(ax,'Title');
set(th,'Units','normalized');
pos = get(th,'Position');
pos(2) = yPos;
set(th,'Position',pos);
end

function y = titleYForStyle(styleName)
if strcmpi(styleName,'Light')
    y = 1.01;
else
    y = 1.05;
end
end

function deleteAllColorbars(h)
try
    delete(findall(h,'Type','ColorBar'));
catch
    try, delete(findall(h,'Tag','Colorbar')); catch, end
end
end

function hardClearAx(ax, styleName, showGrid, ttl)
if isempty(ax) || ~ishandle(ax), return; end

try
    lg = legend(ax);
    if ishghandle(lg), delete(lg); end
catch
end

try, set(ax,'NextPlot','replace'); catch, end
try, hold(ax,'off'); catch, end

try
    cla(ax,'reset');
catch
    try, cla(ax); catch, end
    try, delete(allchild(ax)); catch, end
end

styleAxesMode(ax, styleName, showGrid);
recolorAxesText(ax, styleName);
title(ax, ttl, 'FontWeight','bold');
moveTitleUp(ax, titleYForStyle(styleName));
fixAxesInset(ax);
end

function stylePreviewPanels(S)
isLight = strcmpi(S.previewStyle,'Light');

if isLight
    bgMain = [1 1 1];
    bgTop  = [0.96 0.96 0.96];
    fg     = [0 0 0];
    editBg = [1 1 1];
    btnBg  = [0.86 0.86 0.86];
else
    bgMain = S.C.bg;
    bgTop  = S.C.panel2;
    fg     = [1 1 1];
    editBg = S.C.editBg;
    btnBg  = [0.14 0.14 0.14];
end

set(S.hPrevBG,  'BackgroundColor',bgMain);
set(S.hPrevTop, 'BackgroundColor',bgTop, 'ForegroundColor',fg);

setIfHandle(S,'hPrevExportTop','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');
setIfHandle(S,'hPrevExportBot','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');
setIfHandle(S,'hPrevExportBoth','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');

setIfHandle(S,'hPrevLblView','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hPrevLblWin','BackgroundColor',bgTop,'ForegroundColor',fg);

setIfHandle(S,'hPrevStyle','BackgroundColor',editBg,'ForegroundColor',fg);
setIfHandle(S,'hPrevGrid','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hSmoothEnable','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hSmoothWin','BackgroundColor',editBg,'ForegroundColor',fg);
end

function setIfHandle(S, fieldName, varargin)
if isfield(S,fieldName)
    h = S.(fieldName);
    if ishghandle(h)
        try
            set(h, varargin{:});
        catch
        end
    end
end
end

    function colors = buildTableRowColors(subj)
neutral  = [0.12 0.12 0.12];
excluded = [0.30 0.12 0.12];

n = size(subj,1);
if n <= 0
    colors = [neutral; neutral];
    return;
end

colors = repmat(neutral, max(n,2), 1);

for i = 1:n
    use  = logicalCellValue(subj{i,1});
    st   = lower(strtrimSafe(subj{i,9}));
    grp  = strtrimSafe(subj{i,3});
    cond = strtrimSafe(subj{i,4});

    if contains(st,'excluded') || ~use
        colors(i,:) = excluded;
    else
        colors(i,:) = groupRowColorGA(grp, cond);
    end
end
end

function colors = buildTableRowColorsDisplay(subj, minRows)
if nargin < 2, minRows = 0; end

neutral  = [0.12 0.12 0.12];
excluded = [0.30 0.12 0.12];

n = size(subj,1);
nOut = max(max(n,2), minRows);
colors = repmat(neutral, nOut, 1);

for i = 1:n
    use  = logicalCellValue(subj{i,1});
    st   = lower(strtrimSafe(subj{i,9}));
    grp  = strtrimSafe(subj{i,3});
    cond = strtrimSafe(subj{i,4});

    if contains(st,'excluded') || ~use
        colors(i,:) = excluded;
    else
        colors(i,:) = groupRowColorGA(grp, cond);
    end
end
end


%%% =====================================================================
%%% NESTED CALLBACKS CONTINUED
%%% =====================================================================

function s = simplifyROIFileLabel(fp)
s = '';
fp = strtrimSafe(fp);
if isempty(fp)
    return;
end

[~,bn,~] = fileparts(fp);
bnL = lower(bn);

roiTok = regexp(bn, '(?i)(roi\s*[_-]*\d+)', 'tokens', 'once');
roiPart = '';
if ~isempty(roiTok)
    roiPart = regexprep(roiTok{1}, '[_-]+', '');
    roiPart = upper(strrep(roiPart,'roi','ROI'));
end

kind = '';
if contains(bnL,'target')
    kind = 'Target';
elseif contains(bnL,'ctrl') || contains(bnL,'control')
    kind = 'Ctrl';
elseif contains(bnL,'mask')
    kind = 'Mask';
elseif contains(bnL,'ref')
    kind = 'Ref';
else
    kind = 'ROI';
end

if ~isempty(roiPart)
    s = [roiPart ' ' kind];
else
    s = kind;
end
end

function s = bundlePresenceLabel(fp)
fp = strtrimSafe(fp);
if isempty(fp)
    s = '';
elseif exist(fp,'file') == 2
    s = 'Exists';
else
    s = 'Missing';
end
end

function applyYLim(ax, dataVec, plotCfg)
if isempty(dataVec), return; end
dataVec = dataVec(isfinite(dataVec));
if isempty(dataVec), return; end

if plotCfg.auto
    lo = min(dataVec);
    hi = max(dataVec);
    if plotCfg.forceZero, lo = 0; end
    if lo == hi
        lo = lo - 1;
        hi = hi + 1;
    else
        pad = 0.06 * (hi - lo);
        lo = lo - pad;
        hi = hi + pad;
        if plotCfg.forceZero, lo = 0; end
    end
    ylim(ax,[lo hi]);
else
    lo = plotCfg.ymin;
    hi = plotCfg.ymax;
    if plotCfg.forceZero, lo = 0; end
    if isfinite(lo) && isfinite(hi) && lo < hi
        ylim(ax,[lo hi]);
    end
end

step = plotCfg.step;
if ~isfinite(step) || step <= 0
    try, set(ax,'YTickMode','auto'); catch, end
    return;
end

yl = ylim(ax);
lo = yl(1);
hi = yl(2);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, return; end

if plotCfg.forceZero
    t0 = 0;
else
    t0 = floor(lo/step)*step;
end
t1 = ceil(hi/step)*step;

ticks = t0:step:t1;
ticks = ticks(ticks >= lo-1e-9 & ticks <= hi+1e-9);

if numel(ticks) > 60
    try, set(ax,'YTickMode','auto'); catch, end
    return;
end

if ~isempty(ticks)
    try, set(ax,'YTick',ticks); catch, end
end
end

function h = drawInjectionPatch(ax, x0, x1, col, alphaVal)
if ~isfinite(x0) || ~isfinite(x1)
    h = [];
    return;
end
if x1 <= x0
    h = [];
    return;
end

yl = ylim(ax);
h = patch(ax,[x0 x1 x1 x0],[yl(1) yl(1) yl(2) yl(2)],col, ...
    'FaceAlpha',alphaVal, ...
    'EdgeColor','none', ...
    'HitTest','off', ...
    'HandleVisibility','off', ...
    'Tag','GA_InjectionPatch');

try
    ann = get(h,'Annotation');
    leg = get(ann,'LegendInformation');
    set(leg,'IconDisplayStyle','off');
catch
end

try
    uistack(h,'bottom');
catch
end
end

function y2 = smooth1D_edgeCentered(y, dtSec, winSec)
y = double(y(:)');
n = numel(y);
y2 = y;

if n < 2 || ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(winSec) || winSec <= 0
    return;
end

if any(~isfinite(y))
    idx = find(isfinite(y));
    if numel(idx) < 2
        return;
    end
    y = interp1(idx, y(idx), 1:n, 'linear', 'extrap');
end

winVol = max(1, round(winSec / dtSec));
if winVol <= 1
    y2 = y;
    return;
end

prePad  = floor(winVol/2);
postPad = winVol - 1 - prePad;

L = repmat(y(1), 1, prePad);
R = repmat(y(end), 1, postPad);
ypad = [L y R];

k = ones(1, winVol) / winVol;
y2 = conv(ypad, k, 'valid');
end

function [hLine,hPatch] = shadedLineColored(ax, x, y, e, lineColor, fillColor, semAlpha)
if nargin < 7 || isempty(semAlpha)
    semAlpha = 0.20;
end

x = x(:)';
y = y(:)';
e = e(:)';

up = y + e;
dn = y - e;

hPatch = patch(ax, [x fliplr(x)], [up fliplr(dn)], fillColor, ...
    'FaceAlpha',semAlpha, ...
    'EdgeColor','none', ...
    'HandleVisibility','off');

try
    ann = get(hPatch,'Annotation');
    leg = get(ann,'LegendInformation');
    set(leg,'IconDisplayStyle','off');
catch
end

hLine = plot(ax, x, y, 'LineWidth',2.4, 'Color',lineColor);
end

function dispNames = resolveDisplayGroupNames(rawNames, S)
n = numel(rawNames);
dispNames = cell(size(rawNames));
isPAC = false(1,n);
isVEH = false(1,n);

for i = 1:n
    u = upper(strtrimSafe(rawNames{i}));
    isPAC(i) = contains(u,'PACAP');
    isVEH(i) = contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL');
end

if strcmpi(S.colorScheme,'PACAP/Vehicle') && n==2
    if sum(isPAC)==1
        pacIdx = find(isPAC,1,'first');
        otherIdx = setdiff(1:2,pacIdx);
        dispNames{pacIdx} = 'PACAP';
        dispNames{otherIdx} = 'Vehicle';
        return;
    elseif sum(isVEH)==1
        vehIdx = find(isVEH,1,'first');
        otherIdx = setdiff(1:2,vehIdx);
        dispNames{vehIdx} = 'Vehicle';
        dispNames{otherIdx} = 'PACAP';
        return;
    else
        dispNames{1} = 'PACAP';
        dispNames{2} = 'Vehicle';
        return;
    end
end

for i = 1:n
    rawName = strtrimSafe(rawNames{i});
    u = upper(rawName);
    if contains(u,'PACAP')
        dispNames{i} = 'PACAP';
    elseif contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL')
        dispNames{i} = 'Vehicle';
    else
        if strcmpi(S.colorMode,'Manual A/B')
            if i==1 && ~isempty(strtrimSafe(S.manualGroupA))
                dispNames{i} = strtrimSafe(S.manualGroupA);
            elseif i==2 && ~isempty(strtrimSafe(S.manualGroupB))
                dispNames{i} = strtrimSafe(S.manualGroupB);
            else
                dispNames{i} = rawName;
            end
        else
            dispNames{i} = rawName;
        end
    end
    if isempty(dispNames{i})
        dispNames{i} = sprintf('Group%d',i);
    end
end
end

function c = groupRowColorGA(groupName, condName)
g = upper(strtrimSafe(groupName));
cnd = upper(strtrimSafe(condName));

% Group A / PACAP / CondA -> light green
if contains(g,'PACAP') || contains(g,'GROUPA') || strcmp(g,'A') || ...
   contains(cnd,'CONDA')
    c = [0.22 0.42 0.22];

% Group B / Vehicle / Control / CondB -> dark green
elseif contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || ...
       contains(g,'GROUPB') || strcmp(g,'B') || contains(cnd,'CONDB')
    c = [0.08 0.22 0.10];

% Fallback used color
else
    c = [0.12 0.30 0.16];
end
end

function dispNames = getDisplayNamesFromR(R)
if isfield(R,'groupDisplayNames') && ~isempty(R.groupDisplayNames)
    dispNames = R.groupDisplayNames;
else
    dispNames = R.groupNames;
end
end

function j = deterministicJitter(key, amp)
if nargin < 2 || isempty(amp), amp = 0.22; end
if isempty(key), key = 'x'; end

s = uint8(char(key));
h = uint32(2166136261);
for k = 1:numel(s)
    h = bitxor(h, uint32(s(k)));
    h = uint32(mod(uint64(h) * 16777619, 2^32));
end

u = double(h) / double(intmax('uint32'));
j = (u - 0.5) * amp;
end

function highlightOutliersOnScatter(ax, R, S, rowX, styleName)
if isempty(S.outlierKeys), return; end
if ~isfield(R,'subjTable') || isempty(R.subjTable), return; end
if numel(rowX) ~= size(R.subjTable,1), return; end

[bg,fg] = previewColors(styleName);
keysAll = makeRowKeys(R.subjTable);
y = R.metricVals(:);

for i = 1:numel(S.outlierKeys)
    hit = find(strcmp(keysAll, S.outlierKeys{i}), 1, 'first');
    if isempty(hit), continue; end
    if ~isfinite(rowX(hit)) || ~isfinite(y(hit)), continue; end

    scatter(ax, rowX(hit), y(hit), 150, ...
        'MarkerFaceColor','none', ...
        'MarkerEdgeColor',[1 0.45 0.45], ...
        'LineWidth',2.0);

    sid = strtrimSafe(R.subjTable{hit,2});
    txt = sprintf('%s: %.4g', sid, y(hit));
    text(ax, rowX(hit)+0.03, y(hit), txt, ...
        'Color',fg, ...
        'FontSize',9, ...
        'FontWeight','bold', ...
        'BackgroundColor',bg, ...
        'Margin',1, ...
        'Clipping','on', ...
        'HorizontalAlignment','left', ...
        'VerticalAlignment','middle');
end
end

function A = flipLR_3D_local(A)
    A = A(:,end:-1:1,:);
end

function rgb = toRGB_local(A)
A = mat2gray_local(A);
rgb = repmat(A, [1 1 3]);
end

function rgb = normalizeRgbLocal(U)
rgb = double(U);
mx = max(rgb(:));
if isfinite(mx) && mx > 1
    rgb = rgb / 255;
end
rgb(~isfinite(rgb)) = 0;
rgb = min(max(rgb,0),1);
end

function A = mat2gray_local(A)
A = double(A);
A(~isfinite(A)) = 0;
mn = min(A(:));
mx = max(A(:));
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    A = zeros(size(A));
else
    A = (A - mn) / (mx - mn);
end
A = min(max(A,0),1);
end

function cm = getNamedCmapLocal(name, n)
if nargin < 2, n = 256; end
name = lower(strtrimSafe(name));

switch name
    case 'blackbdy_iso'
        if exist('blackbdy_iso','file') == 2
            cm = blackbdy_iso(n);
        else
            cm = hot(n);
        end
    case 'hot'
        cm = hot(n);
    case 'parula'
        cm = parula(n);
    case 'jet'
        cm = jet(n);
    case 'gray'
        cm = gray(n);
    otherwise
        if strcmp(name,'turbo') && exist('turbo','file') == 2
            cm = turbo(n);
        else
            cm = hot(n);
        end
end
end

function B = smooth2D_gauss_local(A, sigma)
try
    B = imgaussfilt(A, sigma);
    return;
catch
end

if sigma <= 0
    B = A;
    return;
end

r = max(1, ceil(3*sigma));
x = -r:r;
g = exp(-(x.^2)/(2*sigma^2));
g = g / sum(g);

B = conv2(conv2(double(A), g, 'same'), g', 'same');
end

function exportPreviewPNG(outFile, which, S)
[figBg,~] = previewColors(S.previewStyle);

% Export-only geometry
if which == 1
    % Top plot: make wider again
    figPos = [100 100 1320 620];
   axPos  = [0.10 0.36 0.96 0.34];
    boxAsp = [2.00 1 1];
else
    % Bottom plot: keep mostly as before, only slightly broader
    figPos = [100 100 980 620];
    axPos  = [0.25 0.24 0.44 0.28];
    boxAsp = [0.92 1 1];
end

f = figure( ...
    'Visible','off', ...
    'Color',figBg, ...
    'InvertHardcopy','off', ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Renderer','opengl');

set(f,'Position',figPos);

ax = axes( ...
    'Parent',f, ...
    'Units','normalized', ...
    'Position',axPos);

styleAxesMode(ax, S.previewStyle, S.previewShowGrid);
recolorAxesText(ax, S.previewStyle);

try, set(ax,'LineWidth',1.0); catch, end
try, set(ax,'TickDir','out'); catch, end
try, set(ax,'TickLength',[0.012 0.012]); catch, end
try, set(ax,'ActivePositionProperty','position'); catch, end

exportOnePreview(ax, which, S, S.previewStyle);

% Apply aspect after plotting
try, pbaspect(ax, boxAsp); catch, end

if which == 2
    % Slight extra headroom for stats annotation
    try
        yl = ylim(ax);
        dy = yl(2) - yl(1);
        if isfinite(dy) && dy > 0
            ylim(ax, [yl(1) yl(2) + 0.12*dy]);
        end
    catch
    end

    % Remove bottom export title
    try
        title(ax,'');
    catch
    end

    % Move p-text / stars slightly upward and to the right
    moveExportStatsForExport(ax, 0, -0.08);
end

set(f,'PaperPositionMode','auto');
print(f, outFile, '-dpng', '-r300');
close(f);
end

   function moveExportStatsForExport(ax, xFracRight, pGapBelowStar)
if nargin < 2 || isempty(xFracRight)
    xFracRight = 0.06;
end
if nargin < 3 || isempty(pGapBelowStar)
    pGapBelowStar = 0.05;
end

if isempty(ax) || ~ishandle(ax)
    return;
end

try
    xl = xlim(ax);
    yl = ylim(ax);
catch
    return;
end

dx = xl(2) - xl(1);
dy = yl(2) - yl(1);

if ~isfinite(dx) || dx <= 0 || ~isfinite(dy) || dy <= 0
    return;
end

txts = findall(ax,'Type','text');
if isempty(txts)
    return;
end

hP = [];
hStar = [];

for k = 1:numel(txts)
    h = txts(k);

    try
        s = get(h,'String');
    catch
        continue;
    end

    if iscell(s)
        try
            s = strjoin(s,' ');
        catch
            s = '';
        end
    end

    s = strtrimSafe(s);
    sLow = lower(s);
    sNoSpace = strrep(sLow,' ','');

    isPText = contains(sNoSpace,'p=');
    isStar  = strcmp(s,'*') || strcmp(s,'**') || strcmp(s,'***') || strcmpi(s,'n.s.');

    if isPText
        hP = h;
    elseif isStar
        hStar = h;
    end
end

if isempty(hP) || ~ishandle(hP)
    return;
end

try
    posP = get(hP,'Position');
catch
    return;
end

if ~isempty(hStar) && ishandle(hStar)
    try
        posS = get(hStar,'Position');

        % place p-text slightly to the right of the star center
        posP(1) = min(xl(2) - 0.05*dx, posS(1) + xFracRight*dx);

        % place p-text BELOW the star by a fixed gap
        posP(2) = max(yl(1) + 0.03*dy, posS(2) - pGapBelowStar*dy);
    catch
    end
else
    % fallback if no star text found
    posP(1) = min(xl(2) - 0.05*dx, posP(1) + xFracRight*dx);
end

try
    set(hP,'Position',posP);
    set(hP,'HorizontalAlignment','center');
    set(hP,'VerticalAlignment','top');
    set(hP,'FontSize',9);   % smaller p-value text
catch
end
end

function y = tern(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end

function keys = makeRowKeys(tbl)
n = size(tbl,1);
keys = cell(n,1);
for i = 1:n
    sid = strtrimSafe(tbl{i,2});
    grp = strtrimSafe(tbl{i,3});
    cd  = strtrimSafe(tbl{i,4});
    pid = strtrimSafe(tbl{i,5});
    keys{i} = [sid '|' grp '|' cd '|' pid];
end
end

function writeCellCSV_UTF8(fn, C)
fid = fopen(fn,'w');
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8([239 187 191]), 'uint8');

[nr,nc] = size(C);
for r = 1:nr
    row = cell(1,nc);
    for c = 1:nc
        v = C{r,c};
        if isnumeric(v)
            if isempty(v) || ~isfinite(v)
                s = '';
            else
                s = num2str(v);
            end
        else
            try
                s = char(v);
            catch
                s = '';
            end
        end
        s = strrep(s,'"','""');
        row{c} = ['"' s '"'];
    end
    fprintf(fid,'%s\n', strjoin(row,','));
end
end
%%% =====================================================================
%%% EXCEL EXPORT / METADATA / STATS / ROI ANALYSIS
%%% =====================================================================

function exportGroupAnalysisExcelWorkbook(outFile, S)
metaSheet = buildMetadataSheetForExcel(S.subj);

condNames = uniqueStable(colAsStr(S.subj,4));
condASheet = {'Info','No condition found'};
condBSheet = {'Info','No second condition found'};

if numel(condNames) >= 1
    condASheet = buildConditionWideSheetForExcel(S.subj, condNames{1});
end
if numel(condNames) >= 2
    condBSheet = buildConditionWideSheetForExcel(S.subj, condNames{2});
end

auditSheet = buildOutlierAuditSheetForExcel(S);

if exist(outFile,'file') == 2
    try
        delete(outFile);
    catch
        error('Could not overwrite existing Excel file: %s', outFile);
    end
end

writeExcelSheetCompat(outFile, 'Metadata', metaSheet);
writeExcelSheetCompat(outFile, 'Condition_A', condASheet);
writeExcelSheetCompat(outFile, 'Condition_B', condBSheet);
writeExcelSheetCompat(outFile, 'Outlier_Audit', auditSheet);

try
    styleGroupAnalysisWorkbook(outFile);
catch
end
end

function writeExcelSheetCompat(outFile, sheetName, C)
if exist('writecell','file') == 2
    writecell(C, outFile, 'Sheet', sheetName);
else
    [ok,msg] = xlswrite(outFile, C, sheetName);
    if ~ok
        if ischar(msg)
            error('Excel write failed on sheet %s: %s', sheetName, msg);
        else
            error('Excel write failed on sheet %s.', sheetName);
        end
    end
end
end

function C = buildMetadataSheetForExcel(subj)
hdr = { ...
    'Use (TRUE/FALSE)','Animal ID','Session ID','Scan ID','Group','Condition', ...
    'Notes','Excluded','Publication Ready', ...
    'Baseline Window','Signal Window','ROI Index','Slice','x1','x2','y1','y2', ...
    'Animal Status','TR (s)','N Volumes','ROI File'};

rows = cell(size(subj,1), numel(hdr));

for i = 1:size(subj,1)
    info = extractRowMetaForExcel(subj(i,:));
    roiH = readROITxtHeaderMeta(info.roiFile);

    rows{i,1}  = logicalToText(subj{i,1});
    rows{i,2}  = info.animalID;
    rows{i,3}  = info.session;
    rows{i,4}  = info.scanID;
    rows{i,5}  = info.group;
    rows{i,6}  = info.condition;
    rows{i,7}  = info.notes;
    rows{i,8}  = info.exclusion;
    rows{i,9}  = info.useForPublication;

    rows{i,10} = roiH.baselineText;
    rows{i,11} = roiH.signalText;
    rows{i,12} = roiH.roiNo;
    rows{i,13} = roiH.slice;
    rows{i,14} = roiH.x1;
    rows{i,15} = roiH.x2;
    rows{i,16} = roiH.y1;
    rows{i,17} = roiH.y2;

    rows{i,18} = info.animalStatus;
    rows{i,19} = info.TR_sec;
    rows{i,20} = info.NVols;
    rows{i,21} = info.roiFile;
end

rows = sortMetadataRows(rows);

C = hdr;
C = appendGroupedRows(C, rows, 5);
end

function C = buildOutlierAuditSheetForExcel(S)
fullTbl = S.subj;

hdr = { ...
    'Use','AnimalID','Session','ScanID','Group','Condition', ...
    'Analyzed','RowState', ...
    'MetricValue','MetricName','MetricSource', ...
    'MetricRobustZ','OutlierMethod','Threshold','IsOutlierByMethod', ...
    'RawMedianPSC','RawMADPSC','RawQ1PSC','RawQ3PSC','RawIQRPSC', ...
    'ROIFile','Status'};

rows = cell(size(fullTbl,1), numel(hdr));

metricVals = nan(size(fullTbl,1),1);
analyzed   = false(size(fullTbl,1),1);
metricNameNow = '';
metricSourceNow = '';

if isfield(S,'lastROI') && ~isempty(fieldnames(S.lastROI)) && ...
   isfield(S.lastROI,'metricVals') && isfield(S.lastROI,'subjTable')


    anaTbl = S.lastROI.subjTable;
    anaMet = double(S.lastROI.metricVals(:));

    if isfield(S.lastROI,'metricName')
    metricNameNow = strtrimSafe(S.lastROI.metricName);
end
    if isempty(metricNameNow)
        metricNameNow = 'Bottom plot metric';
    end
    metricSourceNow = 'Per-animal value used for the bottom plot / outlier detection';

    anaKeys = cell(size(anaTbl,1),1);
    for i = 1:size(anaTbl,1)
        anaKeys{i} = makeAuditMatchKey(anaTbl(i,:));
    end

    for i = 1:size(fullTbl,1)
        k = makeAuditMatchKey(fullTbl(i,:));
        hit = find(strcmp(anaKeys, k), 1, 'first');
        if ~isempty(hit)
            metricVals(i) = anaMet(hit);
            analyzed(i) = true;
        end
    end
end

xAnal = metricVals(isfinite(metricVals));
gMed = NaN;
gMad = NaN;
rz = nan(size(metricVals));

if ~isempty(xAnal)
    gMed = median(xAnal);
    gMad = median(abs(xAnal - gMed));
    if isfinite(gMad) && gMad > 0
        rz(isfinite(metricVals)) = 0.6745 * (metricVals(isfinite(metricVals)) - gMed) / gMad;
    end
end

for i = 1:size(fullTbl,1)
    info = extractRowMetaForExcel(fullTbl(i,:));
    rowState = deriveAuditRowState(fullTbl(i,:));

    rawMed = NaN; rawMad = NaN; rawQ1 = NaN; rawQ3 = NaN; rawIQR = NaN;
    [ok,~,psc] = tryReadSCMroiExportTxt(info.roiFile);
    if ok
        psc = double(psc(:));
        psc = psc(isfinite(psc));
        if ~isempty(psc)
            rawMed = median(psc);
            rawMad = median(abs(psc - rawMed));
            rawQ1  = prctile(psc,25);
            rawQ3  = prctile(psc,75);
            rawIQR = rawQ3 - rawQ1;
        end
    end

    thrTxt = '';
    isOut = false;

    if strcmpi(S.outlierMethod,'MAD robust z-score')
        thrTxt = num2str(S.outMADthr);
        isOut = isfinite(rz(i)) && abs(rz(i)) > S.outMADthr;
    elseif strcmpi(S.outlierMethod,'IQR rule')
        thrTxt = num2str(S.outIQRk);
        if ~isempty(xAnal)
            q1 = prctile(xAnal,25);
            q3 = prctile(xAnal,75);
            iqrV = q3 - q1;
            lo = q1 - S.outIQRk * iqrV;
            hi = q3 + S.outIQRk * iqrV;
            isOut = isfinite(metricVals(i)) && (metricVals(i) < lo || metricVals(i) > hi);
        end
    end

    rows{i,1}  = logicalToText(fullTbl{i,1});
    rows{i,2}  = info.animalID;
    rows{i,3}  = info.session;
    rows{i,4}  = info.scanID;
    rows{i,5}  = info.group;
    rows{i,6}  = info.condition;
    rows{i,7}  = yesNoText(analyzed(i));
    rows{i,8}  = rowState;
    rows{i,9}  = metricVals(i);
    rows{i,10} = metricNameNow;
    rows{i,11} = metricSourceNow;
    rows{i,12} = rz(i);
    rows{i,13} = S.outlierMethod;
    rows{i,14} = thrTxt;
    rows{i,15} = yesNoText(isOut);
    rows{i,16} = rawMed;
    rows{i,17} = rawMad;
    rows{i,18} = rawQ1;
    rows{i,19} = rawQ3;
    rows{i,20} = rawIQR;
    rows{i,21} = info.roiFile;
    rows{i,22} = info.status;
end

rows = sortMetadataRows(rows);

C = hdr;
C = appendGroupedRows(C, rows, 5);
end

function info = extractRowMetaForExcel(row)
info = struct();

info.subject    = strtrimSafe(row{2});
info.group      = strtrimSafe(row{3});
info.condition  = strtrimSafe(row{4});
info.pairID     = strtrimSafe(row{5});
info.dataFile   = strtrimSafe(row{6});
info.roiFile    = strtrimSafe(row{7});
info.bundleFile = strtrimSafe(row{8});
info.status     = strtrimSafe(row{9});

meta = extractMetaFromSources(info.subject, info.dataFile, info.roiFile, info.bundleFile);

info.animalID = meta.animalID;
info.session  = meta.session;
info.scanID   = meta.scanID;

info.notes             = '';
info.useForPublication = '';
info.animalStatus      = '';

if logicalCellValue(row{1}) && ~contains(lower(info.status),'excluded')
    info.exclusion = '';
else
    info.exclusion = 'Yes';
end

[info.TR_sec, info.NVols, ~] = extractDataSummaryQuick(info.dataFile);
end

function sh = makeSafeExcelSheetName(s)
sh = strtrimSafe(s);
if isempty(sh), sh = 'Sheet'; end
sh = regexprep(sh,'[:\\/\?\*\[\]]','_');
if numel(sh) > 31
    sh = sh(1:31);
end
end

    function info = extractRowMetaLight(row)
info = struct();

info.subject    = strtrimSafe(row{2});
info.group      = strtrimSafe(row{3});
info.condition  = strtrimSafe(row{4});
info.pairID     = strtrimSafe(row{5});
info.dataFile   = strtrimSafe(row{6});
info.roiFile    = strtrimSafe(row{7});
info.bundleFile = strtrimSafe(row{8});
info.status     = strtrimSafe(row{9});

meta = extractMetaFromSources(info.subject, info.dataFile, info.roiFile, info.bundleFile);

info.animalID = meta.animalID;
info.session  = meta.session;
info.scanID   = meta.scanID;

info.notes             = '';
info.useForPublication = '';
info.animalStatus      = '';

if logicalCellValue(row{1}) && ~contains(lower(info.status),'excluded')
    info.exclusion = '';
else
    info.exclusion = 'Yes';
end

% IMPORTANT:
% Keep these lightweight here. Do NOT load large data mats in UI/path code.
info.TR_sec = NaN;
info.NVols  = NaN;
end

function state = deriveAuditRowState(row)
use = logicalCellValue(row{1});
roi = strtrimSafe(row{7});
st  = lower(strtrimSafe(row{9}));

if contains(st,'excluded') || ~use
    state = 'Excluded';
elseif isempty(roi)
    state = 'ROI not set';
elseif exist(roi,'file') == 2
    state = 'OK';
else
    state = 'Missing ROI';
end
end

function C = buildConditionWideSheetForExcel(subj, condFilter)
idxKeep = find(strcmpi(colAsStr(subj,4), condFilter));
idxKeep = sortSubjectIdxForMetadata(subj, idxKeep);

if isempty(idxKeep)
    C = {'Info', ['No rows for condition: ' condFilter]};
    return;
end

nScan = numel(idxKeep);
infos   = cell(nScan,1);
tSecAll = cell(nScan,1);
tMinAll = cell(nScan,1);
pAll    = cell(nScan,1);
maxPts  = 0;

for j = 1:nScan
    row = subj(idxKeep(j),:);
    info = extractRowMetaForExcel(row);
    infos{j} = info;

    [ok, tMin, psc] = tryReadSCMroiExportTxt(info.roiFile);
    if ok
        tMin = double(tMin(:));
        psc  = double(psc(:));

        tSecAll{j} = 60 .* tMin;
        tMinAll{j} = tMin;
        pAll{j}    = psc;

        maxPts = max(maxPts, numel(tMin));
    else
        tSecAll{j} = [];
        tMinAll{j} = [];
        pAll{j}    = [];
    end
end

rowAnimal  = 1;
rowSession = 2;
rowScan    = 3;
rowGroup   = 4;
rowCond    = 5;
rowInfo    = 8;
rowHeader  = 9;
rowData0   = 10;

nRows = max(rowData0 + maxPts - 1, rowHeader);
nCols = 2 + 2*nScan;

C = cell(nRows, nCols);

C{rowAnimal,1}  = 'Animal ID';
C{rowSession,1} = 'Session ID';
C{rowScan,1}    = 'Scan ID';
C{rowGroup,1}   = 'Group';
C{rowCond,1}    = 'Condition';

C{rowInfo,1}    = '% signal change (%SC)';
C{rowInfo,2}    = 'Values come from ROI txt and use the respective baseline window of each ROI export';

C{rowHeader,1}  = 'time_sec';
C{rowHeader,2}  = 'time_min';

refSec = nan(maxPts,1);
refMin = nan(maxPts,1);
for k = 1:maxPts
    for j = 1:nScan
        if numel(tSecAll{j}) >= k
            refSec(k) = tSecAll{j}(k);
            refMin(k) = tMinAll{j}(k);
            break;
        end
    end
end

for k = 1:maxPts
    r = rowData0 + k - 1;
    if isfinite(refSec(k)), C{r,1} = refSec(k); end
    if isfinite(refMin(k)), C{r,2} = refMin(k); end
end

for j = 1:nScan
    dataCol = 3 + 2*(j-1);
    info = infos{j};

    C{rowAnimal,dataCol}  = info.animalID;
    C{rowSession,dataCol} = info.session;
    C{rowScan,dataCol}    = info.scanID;
    C{rowGroup,dataCol}   = info.group;
    C{rowCond,dataCol}    = info.condition;

    C{rowHeader,dataCol}  = sprintf('%s | %s | %s', info.animalID, info.session, info.scanID);

    for k = 1:maxPts
        r = rowData0 + k - 1;
        if numel(pAll{j}) >= k
            C{r,dataCol} = pAll{j}(k);
        end
    end
end
end

function rows = appendGroupedRows(rows0, rows, groupCol)
C = rows0;
nCol = size(rows0,2);

if isempty(rows)
    blank = repmat({''},1,nCol);
    blank{1} = 'No rows found.';
    rows = blank;
    rows = rows(:).';
    rows = reshape(rows,1,[]);
    rows = rows(:,1:nCol);
    C = [C; rows];
    rows = C;
    return;
end

groups = uniqueStable(rows(:,groupCol));

for g = 1:numel(groups)
    titleRow = repmat({''},1,nCol);
    titleRow{1} = ['GROUP: ' groups{g}];
    C(end+1,:) = titleRow;

    idx = strcmpi(rows(:,groupCol), groups{g});
    C = [C; rows(idx,:)]; %#ok<AGROW>

    if g < numel(groups)
        C(end+1,:) = repmat({''},1,nCol);
    end
end

rows = C;
end

function rows = sortMetadataRows(rows)
if isempty(rows), return; end

keys = cell(size(rows,1),1);
for i = 1:size(rows,1)
    condRank = conditionRankForExport(rows{i,6});
    keys{i} = sprintf('%s|%03d|%s|%s', ...
        lower(safeKeyStr(rows{i,5})), ...
        condRank, ...
        lower(safeKeyStr(rows{i,6})), ...
        lower(safeKeyStr(rows{i,2})));
end

[~,ord] = sort(keys);
rows = rows(ord,:);
end

function idxOut = sortSubjectIdxForMetadata(subj, idxIn)
idxOut = idxIn(:)';
if isempty(idxOut), return; end

keys = cell(numel(idxOut),1);
for k = 1:numel(idxOut)
    info = extractRowMetaForExcel(subj(idxOut(k),:));
    condRank = conditionRankForExport(info.condition);
    keys{k} = sprintf('%s|%03d|%s|%s', ...
        lower(safeKeyStr(info.group)), ...
        condRank, ...
        lower(safeKeyStr(info.condition)), ...
        lower(safeKeyStr(info.animalID)));
end

[~,ord] = sort(keys);
idxOut = idxOut(ord);
end

function roiH = readROITxtHeaderMeta(fname)
roiH = struct( ...
    'baselineText','', ...
    'signalText','', ...
    'roiNo','', ...
    'slice','', ...
    'x1',NaN, ...
    'x2',NaN, ...
    'y1',NaN, ...
    'y2',NaN);

if nargin < 1 || isempty(fname) || exist(fname,'file') ~= 2
    return;
end

try
    [~,bn,~] = fileparts(fname);
    tok = regexpi(bn,'roi\s*([0-9]+)','tokens','once');
    if ~isempty(tok)
        roiH.roiNo = tok{1};
    end
catch
end

fid = fopen(fname,'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

maxLines = 120;
expectXYLine = false;

for k = 1:maxLines
    ln = fgetl(fid);
    if ~ischar(ln), break; end

    lnRaw = strtrim(ln);
    if isempty(lnRaw)
        continue;
    end

    if expectXYLine
        vals = sscanf(lnRaw,'%f');
        if numel(vals) >= 4
            roiH.x1 = vals(1);
            roiH.x2 = vals(2);
            roiH.y1 = vals(3);
            roiH.y2 = vals(4);
        end
        expectXYLine = false;
        continue;
    end

    if lnRaw(1) ~= '#' && lnRaw(1) ~= '%' && lnRaw(1) ~= ';'
        break;
    end

    txt = regexprep(lnRaw,'^[#%;\s]+','');
    txtL = lower(txt);

    if isempty(roiH.baselineText) && ~isempty(strfind(txtL,'baselinewindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.baselineText = strtrim(parts{2});
        else
            roiH.baselineText = strtrim(txt);
        end
    end

    if isempty(roiH.signalText) && ~isempty(strfind(txtL,'signalwindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.signalText = strtrim(parts{2});
        else
            roiH.signalText = strtrim(txt);
        end
    end

    if isempty(roiH.roiNo) && ~isempty(strfind(txtL,'roi_index'))
        tok = regexp(txt,'ROI_INDEX\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.roiNo = tok{1};
        end
    end

    if isempty(roiH.slice) && ~isempty(strfind(txtL,'slice'))
        tok = regexp(txt,'SLICE\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.slice = tok{1};
        end
    end

    if ~isempty(regexp(txtL,'^x1\s+x2\s+y1\s+y2$', 'once'))
        expectXYLine = true;
        continue;
    end

    tok = regexp(txt,'x1\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*x2\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*y1\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*y2\s*[:=]\s*([-+]?\d*\.?\d+)','tokens','once','ignorecase');
    if ~isempty(tok)
        roiH.x1 = str2double(tok{1});
        roiH.x2 = str2double(tok{2});
        roiH.y1 = str2double(tok{3});
        roiH.y2 = str2double(tok{4});
    end
end
end

function rows = sortConditionRows(rows)
if isempty(rows), return; end

keys = cell(size(rows,1),1);
for i = 1:size(rows,1)
    keys{i} = sprintf('%s|%s', ...
        lower(safeKeyStr(rows{i,5})), ...
        lower(safeKeyStr(rows{i,2})));
end

[~,ord] = sort(keys);
rows = rows(ord,:);
end

function r = conditionRankForExport(x)
s = lower(strtrimSafe(x));
if contains(s,'conda') || strcmp(s,'a')
    r = 1;
elseif contains(s,'condb') || strcmp(s,'b')
    r = 2;
else
    r = 50;
end
end

function s = safeKeyStr(x)
if isnumeric(x)
    if isempty(x) || ~isfinite(x)
        s = '';
    else
        s = num2str(x);
    end
else
    s = strtrimSafe(x);
end
end

function s = logicalToText(v)
try
    if logical(v)
        s = 'TRUE';
    else
        s = 'FALSE';
    end
catch
    s = 'FALSE';
end
end

function s = yesNoText(v)
if logicalCellValue(v)
    s = 'Yes';
else
    s = 'No';
end
end

function styleGroupAnalysisWorkbook(outFile)
if ~ispc
    return;
end
if exist('actxserver','file') ~= 2
    return;
end

excel = [];
wb = [];

try
    excel = actxserver('Excel.Application');
    excel.Visible = false;
    excel.DisplayAlerts = false;

    wb = excel.Workbooks.Open(outFile, 0, false);
    nSheets = wb.Worksheets.Count;

    for s = 1:nSheets
        ws = wb.Worksheets.Item(s);
        nCols = ws.UsedRange.Columns.Count;
        nRows = ws.UsedRange.Rows.Count;
        lastCol = excelColLetter(nCols);
        sheetName = char(ws.Name);

        hdrRg = ws.Range(sprintf('A1:%s1', lastCol));
        hdrRg.Font.Bold = true;
        hdrRg.Font.Size = 12;
        hdrRg.Interior.Color = excelRGB(217,217,217);
        hdrRg.HorizontalAlignment = -4108;
        hdrRg.VerticalAlignment   = -4108;
        hdrRg.WrapText = true;

        if strcmpi(sheetName,'Metadata')
            for r = 2:nRows
                aVal = excelCellChar(ws.Range(sprintf('A%d',r)).Value);
                grp  = excelCellChar(ws.Range(sprintf('E%d',r)).Value);
                excl = excelCellChar(ws.Range(sprintf('H%d',r)).Value);
                usev = excelCellChar(ws.Range(sprintf('A%d',r)).Value);

                rowRg = ws.Range(sprintf('A%d:%s%d', r, lastCol, r));

                if strncmpi(strtrim(aVal), 'GROUP:', 6)
                    grpName = strtrim(strrep(aVal,'GROUP:',''));
                    rowRg.Font.Bold = true;
                    rowRg.Font.Size = 14;
                    try
                        rowRg.Font.Underline = 2;
                    catch
                    end
                    rowRg.HorizontalAlignment = -4108;
                    rowRg.VerticalAlignment   = -4108;

                    if isGroupAName(grpName)
                        rowRg.Interior.Color = excelRGB(221,235,247);
                    elseif isGroupBName(grpName)
                        rowRg.Interior.Color = excelRGB(252,228,214);
                    else
                        rowRg.Interior.Color = excelRGB(230,230,230);
                    end
                    continue;
                end

                if strcmpi(excl,'Yes') || strcmpi(usev,'FALSE')
                    rowRg.Interior.Color = excelRGB(255,210,210);
                elseif isGroupAName(grp)
                    rowRg.Interior.Color = excelRGB(221,235,247);
                elseif isGroupBName(grp)
                    rowRg.Interior.Color = excelRGB(252,228,214);
                end

                try
                    ws.Range(sprintf('E%d',r)).Font.Bold = true;
                    ws.Range(sprintf('E%d',r)).Font.Size = 11;
                catch
                end
            end
        end

        if strncmpi(sheetName,'Condition_',10)
            ws.Range('A1:B5').Font.Bold = true;
            ws.Range('A1:B5').Font.Size = 13;
            ws.Range('A1:B5').Interior.Color = excelRGB(217,217,217);
            ws.Range('A1:B5').HorizontalAlignment = -4108;
            ws.Range('A1:B5').VerticalAlignment   = -4108;
            try
                ws.Range('A1:B5').Font.Underline = 2;
            catch
            end

            if nRows >= 6
                ws.Range(sprintf('A6:%s7', lastCol)).Interior.Color = excelRGB(255,255,255);
            end

            if nRows >= 8
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Bold = true;
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Size = 11;
                ws.Range(sprintf('A8:%s8', lastCol)).Interior.Color = excelRGB(242,242,242);
            end

            if nRows >= 9
                ws.Range(sprintf('A9:%s9', lastCol)).Font.Bold = true;
                ws.Range(sprintf('A9:%s9', lastCol)).Font.Size = 12;
                ws.Range(sprintf('A9:%s9', lastCol)).Interior.Color = excelRGB(217,217,217);
                ws.Range(sprintf('A9:%s9', lastCol)).HorizontalAlignment = -4108;
                ws.Range(sprintf('A9:%s9', lastCol)).VerticalAlignment   = -4108;
            end

            animalIdx = 0;
            c = 3;
            while c <= nCols
                animalIdx = animalIdx + 1;
                dataCol = excelColLetter(c);

                blockRg = ws.Range(sprintf('%s1:%s%d', dataCol, dataCol, nRows));
                blockRg.Interior.Color = excelPastelColor(animalIdx);
                blockRg.HorizontalAlignment = -4108;
                blockRg.VerticalAlignment   = -4108;

                topRg = ws.Range(sprintf('%s1:%s5', dataCol, dataCol));
                topRg.Font.Bold = true;
                topRg.Font.Size = 12;
                topRg.WrapText = true;

                if nRows >= 9
                    hdr2Rg = ws.Range(sprintf('%s9:%s9', dataCol, dataCol));
                    hdr2Rg.Font.Bold = true;
                    hdr2Rg.Font.Size = 12;
                    hdr2Rg.WrapText = true;
                end

                if nRows >= 10
                    dataRg = ws.Range(sprintf('%s10:%s%d', dataCol, dataCol, nRows));
                    dataRg.Font.Size = 10;
                    dataRg.HorizontalAlignment = -4108;
                    dataRg.VerticalAlignment   = -4108;
                end

                applyExcelBoxBorder(blockRg);

                if c+1 <= nCols
                    spCol = excelColLetter(c+1);
                    spRg = ws.Range(sprintf('%s1:%s%d', spCol, spCol, nRows));
                    spRg.Interior.Color = excelRGB(255,255,255);
                end

                c = c + 2;
            end

            if nRows >= 10
                ws.Range(sprintf('A10:B%d', nRows)).Font.Size = 10;
                ws.Range(sprintf('A10:B%d', nRows)).HorizontalAlignment = -4108;
                ws.Range(sprintf('A10:B%d', nRows)).VerticalAlignment   = -4108;
            end
        end

        if strcmpi(sheetName,'Outlier_Audit')
            for r = 2:nRows
                aVal = excelCellChar(ws.Range(sprintf('A%d',r)).Value);
                stateVal = excelCellChar(ws.Range(sprintf('H%d', r)).Value);
                grpVal   = excelCellChar(ws.Range(sprintf('E%d', r)).Value);
                rowRg = ws.Range(sprintf('A%d:%s%d', r, lastCol, r));

                if strncmpi(strtrim(aVal), 'GROUP:', 6)
                    grpName = strtrim(strrep(aVal,'GROUP:',''));
                    rowRg.Font.Bold = true;
                    rowRg.Font.Size = 13;
                    try
                        rowRg.Font.Underline = 2;
                    catch
                    end
                    rowRg.HorizontalAlignment = -4108;
                    rowRg.VerticalAlignment   = -4108;

                    if isGroupAName(grpName)
                        rowRg.Interior.Color = excelRGB(221,235,247);
                    elseif isGroupBName(grpName)
                        rowRg.Interior.Color = excelRGB(252,228,214);
                    else
                        rowRg.Interior.Color = excelRGB(230,230,230);
                    end
                    continue;
                end

                if strcmpi(strtrim(stateVal), 'Excluded')
                    rowRg.Interior.Color = excelRGB(255,210,210);
                elseif strcmpi(strtrim(stateVal), 'OK')
                    rowRg.Interior.Color = excelRGB(210,255,210);
                else
                    if isGroupAName(grpVal)
                        try
                            ws.Range(sprintf('E%d',r)).Interior.Color = excelRGB(221,235,247);
                        catch
                        end
                    elseif isGroupBName(grpVal)
                        try
                            ws.Range(sprintf('E%d',r)).Interior.Color = excelRGB(252,228,214);
                        catch
                        end
                    end
                end
            end
        end

        ws.Columns.AutoFit;
    end

    wb.Save;
    wb.Close(false);
    excel.Quit;

catch ME

    try, GA_printErrorLocal(ME,'caught error in GroupAnalysis_FC.m'); catch, end
    try
        if ~isempty(wb), wb.Close(false); end
    catch
    end
    try
        if ~isempty(excel), excel.Quit; end
    catch
    end
    try
        if ~isempty(excel), delete(excel); end
    catch
    end
    rethrow(ME);
end

try
    if ~isempty(excel), delete(excel); end
catch
end
end

function c = excelRGB(r,g,b)
c = double(r) + 256*double(g) + 65536*double(b);
end

function s = excelColLetter(n)
s = '';
while n > 0
    r = rem(n-1,26);
    s = [char(65+r) s]; %#ok<AGROW>
    n = floor((n-1)/26);
end
end

function closeExcelSafe(excel, wb)
try
    if ~isempty(wb)
        wb.Close(false);
    end
catch
end
try
    if ~isempty(excel)
        excel.Quit;
    end
catch
end
try
    if ~isempty(excel)
        delete(excel);
    end
catch
end
end

function [names, rgb] = palette20()
names = {'Blue','Red','Green','Purple','Orange','Cyan','Magenta','Yellow','Gray','White', ...
         'Navy','DarkRed','Teal','Lime','Pink','Brown','Olive','Violet','Sky','Steel'};
rgb = [ ...
    0.20 0.65 0.90;
    0.90 0.25 0.25;
    0.25 0.85 0.55;
    0.65 0.40 0.95;
    0.95 0.55 0.20;
    0.20 0.85 0.85;
    0.90 0.35 0.80;
    0.95 0.90 0.25;
    0.75 0.75 0.75;
    0.95 0.95 0.95;
    0.10 0.20 0.55;
    0.55 0.10 0.10;
    0.10 0.55 0.55;
    0.60 0.90 0.20;
    0.95 0.55 0.75;
    0.55 0.35 0.20;
    0.55 0.55 0.15;
    0.55 0.30 0.75;
    0.35 0.75 0.95;
    0.45 0.55 0.65];
end

function p = tcdf_local(x, v)
x = double(x);
v = double(v);
p = nan(size(x));
ok = isfinite(x) & isfinite(v) & (v > 0);
if ~any(ok), return; end
xo = x(ok);
p_ok = zeros(size(xo));
for i = 1:numel(xo)
    xi = xo(i);
    vi = v;
    z = vi / (vi + xi*xi);
    ib = betainc(z, vi/2, 0.5);
    if xi >= 0
        p_ok(i) = 1 - 0.5*ib;
    else
        p_ok(i) = 0.5*ib;
    end
end
p(ok) = p_ok;
end

function p = fcdf_local(x, v1, v2)
x = double(x);
v1 = double(v1);
v2 = double(v2);
p = nan(size(x));
ok = isfinite(x) & (x>=0) & isfinite(v1) & isfinite(v2) & (v1>0) & (v2>0);
if ~any(ok), return; end
xo = x(ok);
z = (v1 .* xo) ./ (v1 .* xo + v2);
p(ok) = betainc(z, v1/2, v2/2);
end

function mu = nanmean_local(X, dim)
try
    mu = mean(X, dim, 'omitnan');
catch
    n = sum(isfinite(X),dim);
    X2 = X;
    X2(~isfinite(X2)) = 0;
    mu = sum(X2,dim) ./ max(1,n);
end
end

function sd = nanstd_local(X, flag, dim)
if nargin < 2, flag = 0; end
try
    sd = std(X, flag, dim, 'omitnan');
catch
    mu = nanmean_local(X,dim);
    muRep = repmat(mu, repSize(size(X),dim));
    D = X - muRep;
    D(~isfinite(D)) = 0;
    n = sum(isfinite(X),dim);
    v = sum(D.^2,dim) ./ max(1, (n - (flag==0)));
    sd = sqrt(max(0,v));
end
end

function rs = repSize(sz, dim)
rs = ones(1,numel(sz));
rs(dim) = sz(dim);
end

function [ok, tMin, psc] = tryReadSCMroiExportTxt(fname)
ok = false;
tMin = [];
psc = [];
if nargin<1 || isempty(fname), return; end
fname = strtrim(char(fname));
if exist(fname,'file')~=2, return; end
fid = fopen(fname,'r');
if fid<0, return; end
cln = onCleanup(@() fclose(fid)); %#ok<NASGU>

inTable = false;
while true
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end
    if ln(1)=='#'
        if ~isempty(strfind(lower(ln),'# columns:')) && ~isempty(strfind(lower(ln),'psc'))
            inTable = true;
        end
        continue;
    end
    if inTable
        vals = sscanf(ln,'%f');
        if numel(vals) >= 3
            tMin(end+1,1) = vals(2); %#ok<AGROW>
            psc(end+1,1)  = vals(3); %#ok<AGROW>
        end
    end
end
if numel(tMin) >= 5 && numel(psc)==numel(tMin), ok = true; end
end

function D = loadPipelineStruct(fp)
L = load(fp);
if isfield(L,'newData') && isstruct(L.newData), D = pullFields(L.newData); return; end
if isfield(L,'data')    && isstruct(L.data),    D = pullFields(L.data);    return; end
fn = fieldnames(L);
for i=1:numel(fn)
    if isstruct(L.(fn{i}))
        D = pullFields(L.(fn{i}));
        if ~isempty(D.I) || ~isempty(D.TR), return; end
    end
end
error('Could not find pipeline struct with I/TR in: %s', fp);
end

function D = pullFields(S)
D = struct();
if isfield(S,'I'),  D.I  = S.I;  else, D.I  = []; end
if isfield(S,'TR'), D.TR = S.TR; else, D.TR = []; end
end

function roi = readROITxt(f)
A = dlmread(f);
A = double(A);
A = A(~any(isnan(A),2),:);
if isempty(A), error('ROI txt empty: %s', f); end
if any(A(:)==0) && all(A(:) >= 0), A = A + 1; end
roi = A;
end

function tc = roiMeanTimecourse(I, roi)
d = ndims(I);
if d~=3 && d~=4, error('I must be [Y X T] or [Y X Z T].'); end
sz = size(I);
Y = sz(1);
X = sz(2);
if d==4
    Z = sz(3);
    T = sz(4);
else
    Z = 1;
    T = sz(3);
end

roi = double(roi);
if size(roi,2)==1
    lin = round(roi(:,1));
    if d==3
        lin = lin(lin>=1 & lin<=Y*X);
    else
        lin = lin(lin>=1 & lin<=Y*X*Z);
    end
elseif size(roi,2)==2
    r = round(roi(:,1));
    c = round(roi(:,2));
    z = ones(size(r));
    keep = (r>=1 & r<=Y & c>=1 & c<=X);
    r = r(keep); c = c(keep); z = z(keep);
    lin = sub2ind([Y X Z], r, c, z);
else
    r = round(roi(:,1));
    c = round(roi(:,2));
    z = round(roi(:,3));
    keep = (r>=1 & r<=Y & c>=1 & c<=X & z>=1 & z<=Z);
    r = r(keep); c = c(keep); z = z(keep);
    lin = sub2ind([Y X Z], r, c, z);
end

lin = unique(lin(:));
if isempty(lin), error('ROI has no valid points after bounds check.'); end

if d==3
    flat = reshape(I, Y*X, T);
else
    flat = reshape(I, Y*X*Z, T);
end

vals = double(flat(lin,:));
tc = mean(vals,1);
tc(~isfinite(tc)) = NaN;
end

function [tcRaw, tMin] = extractROITC_fromDataAndROI(dataFile, roiFile)
D = loadPipelineStruct(dataFile);
if ~isfield(D,'I') || isempty(D.I), error('DATA file missing I: %s', dataFile); end
if ~isfield(D,'TR') || isempty(D.TR), error('DATA file missing TR: %s', dataFile); end
I = D.I;
TR = double(D.TR);
roi = readROITxt(roiFile);
tcRaw = roiMeanTimecourse(I, roi);
T = numel(tcRaw);
tMin = (0:(T-1))*(TR/60);
end

function [tcRaw, tMin] = extractROITC_legacyMat(fp)
L = load(fp);
if isfield(L,'roiTC')
    tc = L.roiTC;
elseif isfield(L,'TC')
    tc = L.TC;
else
    error('ROI mat must contain roiTC or TC: %s', fp);
end
tc = double(tc);
if size(tc,1) > size(tc,2), tc = tc.'; end
if size(tc,1) > 1
    try
        tc = mean(tc,1,'omitnan');
    catch
        tc = mean(tc,1);
    end
end
tcRaw = tc(:)';

if isfield(L,'tSec') && ~isempty(L.tSec)
    tMin = double(L.tSec(:)')/60;
elseif isfield(L,'TR') && ~isempty(L.TR)
    TR = double(L.TR);
    tMin = (0:(numel(tcRaw)-1))*(TR/60);
else
    error('ROI mat must contain tSec or TR.');
end
end

function m = trimmedMean(x, trimPct)
x = x(:);
x = x(isfinite(x));
if isempty(x), m = NaN; return; end
x = sort(x,'ascend');
n = numel(x);
tp = max(0, min(49, round(trimPct)));
k = floor((tp/100)*n/2);
i0 = 1+k;
i1 = n-k;
if i1 < i0
    m = mean(x);
else
    m = mean(x(i0:i1));
end
end

function pv = robustPeak(y, tMin, s0, s1, winMin, trimPct)
y = double(y(:)');
tMin = double(tMin(:)');
pv = NaN;
idxAll = find(tMin>=s0 & tMin<=s1);
if numel(idxAll)<1, return; end
dt = median(diff(tMin));
if ~isfinite(dt) || dt<=0, dt = 0.1; end
w = max(1, round(winMin/dt));
iStart = idxAll(1);
iEnd = idxAll(end);
best = -Inf;
for i=iStart:(iEnd-w+1)
    j = i+w-1;
    seg = y(i:j);
    seg = seg(isfinite(seg));
    if isempty(seg), continue; end
    val = trimmedMean(seg, trimPct);
    if val > best, best = val; end
end
if isfinite(best), pv = best; end
end

function colors = assignGroupColorsWithMode(gNames, S)
colors = struct();
[~,pal] = palette20();

if strcmpi(S.colorMode,'Manual A/B')
    colA = pal(max(1,min(size(pal,1),S.manualColorA)),:);
    colB = pal(max(1,min(size(pal,1),S.manualColorB)),:);
    gA = strtrimSafe(S.manualGroupA);
    gB = strtrimSafe(S.manualGroupB);
    base = lines(max(1,numel(gNames)));
    for i=1:numel(gNames)
        nm = strtrimSafe(gNames{i});
        if ~isempty(gA) && strcmpi(nm,gA)
            col = colA;
        elseif ~isempty(gB) && strcmpi(nm,gB)
            col = colB;
        else
            col = base(i,:);
        end
        colors.(makeField(nm)) = col;
    end
    return;
end

scheme = strtrimSafe(S.colorScheme);

if strcmpi(scheme,'Blue/Red')
    base = [0.20 0.65 0.90; 0.90 0.25 0.25];
elseif strcmpi(scheme,'Purple/Green')
    base = [0.65 0.40 0.95; 0.25 0.85 0.55];
elseif strcmpi(scheme,'Gray/Orange')
    base = [0.65 0.65 0.65; 0.95 0.55 0.20];
elseif strcmpi(scheme,'Distinct')
    base = lines(max(2,numel(gNames)));
else
    base = [];
end

if ~isempty(base) && ~strcmpi(scheme,'PACAP/Vehicle')
    for i=1:numel(gNames)
        colors.(makeField(gNames{i})) = base(1+mod(i-1,size(base,1)),:);
    end
    return;
end

if strcmpi(scheme,'PACAP/Vehicle')
    n = numel(gNames);
    isPAC = false(1,n);
    isVEH = false(1,n);
    for i=1:n
        nmU = upper(strtrimSafe(gNames{i}));
        isPAC(i) = contains(nmU,'PACAP');
        isVEH(i) = contains(nmU,'VEH') || contains(nmU,'CONTROL') || contains(nmU,'VEHICLE');
    end

    if n==2 && sum(isPAC)==1
        pacIdx = find(isPAC,1,'first');
        otherIdx = setdiff(1:2,pacIdx);
        colors.(makeField(gNames{pacIdx})) = [0.20 0.65 0.90];
        colors.(makeField(gNames{otherIdx})) = [0.65 0.65 0.65];
        return;
    elseif n==2 && sum(isVEH)==1
        vehIdx = find(isVEH,1,'first');
        otherIdx = setdiff(1:2,vehIdx);
        colors.(makeField(gNames{vehIdx})) = [0.65 0.65 0.65];
        colors.(makeField(gNames{otherIdx})) = [0.20 0.65 0.90];
        return;
    elseif n==2
        colors.(makeField(gNames{1})) = [0.20 0.65 0.90];
        colors.(makeField(gNames{2})) = [0.65 0.65 0.65];
        return;
    end

    for i=1:n
        nmU = upper(strtrimSafe(gNames{i}));
        if contains(nmU,'PACAP')
            col = [0.20 0.65 0.90];
        elseif contains(nmU,'VEH') || contains(nmU,'CONTROL') || contains(nmU,'VEHICLE')
            col = [0.65 0.65 0.65];
        else
            b2 = lines(n);
            col = b2(i,:);
        end
        colors.(makeField(gNames{i})) = col;
    end
    return;
end

base = lines(max(1,numel(gNames)));
for i=1:numel(gNames)
    colors.(makeField(gNames{i})) = base(i,:);
end
end

function clr = excelPastelColor(idx)
pal = [ ...
    221 235 247;
    252 228 214;
    226 239 218;
    242 220 219;
    217 225 242;
    255 242 204;
    234 209 220;
    208 224 227];
i = 1 + mod(idx-1, size(pal,1));
clr = excelRGB(pal(i,1), pal(i,2), pal(i,3));
end

function applyExcelBoxBorder(rg)
try
    rg.Borders.LineStyle = 1;
    rg.Borders.Weight = 2;
catch
end
end

function s = excelCellChar(v)
if ischar(v)
    s = strtrim(v);
elseif isstring(v)
    s = strtrim(char(v));
elseif isnumeric(v)
    if isempty(v) || ~isfinite(v)
        s = '';
    else
        s = strtrim(num2str(v));
    end
else
    s = '';
end
end

function tf = isGroupAName(g)
g = upper(strtrimSafe(g));
tf = contains(g,'PACAP') || contains(g,'GROUPA') || strcmp(g,'A');
end

function tf = isGroupBName(g)
g = upper(strtrimSafe(g));
tf = contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || contains(g,'GROUPB') || strcmp(g,'B');
end

function [TR_sec, NVols, durationMin] = extractDataSummaryQuick(dataFile)
TR_sec = NaN;
NVols = NaN;
durationMin = NaN;

if nargin < 1 || isempty(dataFile) || exist(dataFile,'file') ~= 2
    return;
end

try
    D = loadPipelineStruct(dataFile);

    if isfield(D,'TR') && ~isempty(D.TR)
        TR_sec = double(D.TR);
    end

    if isfield(D,'I') && ~isempty(D.I)
        NVols = size(D.I, ndims(D.I));
    end

    if isfinite(TR_sec) && isfinite(NVols)
        durationMin = ((NVols - 1) * TR_sec) / 60;
    end
catch
end
end

function stats = computeStats(metricVals, grpCol, S)
stats = struct('type',S.testType,'alpha',S.alpha,'p',NaN,'t',NaN,'F',NaN,'df',NaN,'desc','');
testType = strtrimSafe(S.testType);

if strcmpi(testType,'None')
    stats.desc = 'No test.';
    return;
end

gNames = uniqueStable(grpCol);
gNames = sortGroupNamesStableGA(gNames, S);

if strcmpi(testType,'One-sample t-test (vs 0)')
    [t,p,df] = oneSampleT_vec(metricVals);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = 'One-sample vs 0';

elseif strcmpi(testType,'Two-sample t-test (Student, equal var)')
    if numel(gNames) < 2
        error('Need >=2 groups.');
    end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = studentT_equalVar_vec(a,b);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = [gNames{1} ' vs ' gNames{2}];

elseif strcmpi(testType,'Two-sample t-test (Welch)')
    if numel(gNames) < 2
        error('Need >=2 groups.');
    end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = welchT_vec(a,b);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = [gNames{1} ' vs ' gNames{2}];

else
    [F,p,df] = oneWayANOVA_metric(metricVals, grpCol);
    stats.F = F;
    stats.p = p;
    stats.df = df;
    stats.desc = 'ANOVA';
end
end

function [t,p,df] = oneSampleT_vec(x)
x = x(:);
x = x(isfinite(x));
n = numel(x);
if n < 2, t = NaN; p = NaN; df = max(0,n-1); return; end
mu = mean(x);
sd = std(x,0);
se = sd/sqrt(n);
t = mu / max(eps,se);
df = n-1;
p = 2 * tcdf_local(-abs(t), df);
end

function [t,p,df] = studentT_equalVar_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1 = numel(a); n2 = numel(b);
if n1<2 || n2<2, t = NaN; p = NaN; df = NaN; return; end
m1 = mean(a); m2 = mean(b);
v1 = var(a,0); v2 = var(b,0);
df = n1 + n2 - 2;
sp2 = ((n1-1)*v1 + (n2-1)*v2) / max(1,df);
den = sqrt(sp2 * (1/n1 + 1/n2));
t = (m1 - m2) / max(eps, den);
p = 2 * tcdf_local(-abs(t), df);
end

function [t,p,df] = welchT_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1 = numel(a); n2 = numel(b);
if n1<2 || n2<2, t = NaN; p = NaN; df = NaN; return; end
m1 = mean(a); m2 = mean(b);
v1 = var(a,0); v2 = var(b,0);
den = sqrt(v1/n1 + v2/n2);
t = (m1-m2) / max(eps,den);
df = (v1/n1 + v2/n2)^2 / ((v1^2)/(n1^2*max(1,n1-1)) + (v2^2)/(n2^2*max(1,n2-1)));
df = max(1, df);
p = 2 * tcdf_local(-abs(t), df);
end

function [F,p,df] = oneWayANOVA_metric(x, groupLabels)
x = x(:);
keep = isfinite(x);
x = x(keep);
g = groupLabels(keep);
g = cellfun(@(s) strtrimSafe(s), g, 'UniformOutput',false);
u = uniqueStable(g);
k = numel(u);
n = numel(x);
if k < 2 || n < 3, F = NaN; p = NaN; df = [k-1 n-k]; return; end
grand = mean(x);
SSb = 0;
SSw = 0;
for i=1:k
    xi = x(strcmpi(g,u{i}));
    if isempty(xi), continue; end
    mi = mean(xi);
    SSb = SSb + numel(xi)*(mi-grand)^2;
    SSw = SSw + sum((xi-mi).^2);
end
df1 = k-1;
df2 = n-k;
MSb = SSb / max(1,df1);
MSw = SSw / max(1,df2);
F = MSb / max(eps,MSw);
df = [df1 df2];
p = 1 - fcdf_local(F, df1, df2);
end

function [keysOut, info] = detectOutliers(metricVals, subjTable, S)
keysOut = {};
info = {};
x = metricVals(:);
valid = isfinite(x);
if sum(valid) < 3, return; end

method = strtrimSafe(S.outlierMethod);

if strcmpi(method,'MAD robust z-score')
    thr = S.outMADthr;
    xv = x(valid);
    med = median(xv);
    madv = median(abs(xv - med));
    if madv <= 0 || ~isfinite(madv), return; end
    rz = 0.6745 * (x - med) / madv;
    idxOut = find(valid & abs(rz) > thr);

    keysAll = makeRowKeys(subjTable);
    for ii = idxOut(:)'
        sid = strtrimSafe(subjTable{ii,2});
        grp = strtrimSafe(subjTable{ii,3});
        cd  = strtrimSafe(subjTable{ii,4});
        info{end+1,1} = sprintf('%s | %s | %s | metric=%.4g | MADz=%.4g > %.4g', ...
            sid, grp, cd, x(ii), abs(rz(ii)), thr); %#ok<AGROW>
        keysOut{end+1,1} = keysAll{ii}; %#ok<AGROW>
    end

elseif strcmpi(method,'IQR rule')
    k = S.outIQRk;
    xv = x(valid);
    q1 = prctile(xv,25);
    q3 = prctile(xv,75);
    iqrV = q3-q1;
    lo = q1 - k*iqrV;
    hi = q3 + k*iqrV;
    idxOut = find(valid & (x<lo | x>hi));

    keysAll = makeRowKeys(subjTable);
    for ii = idxOut(:)'
        sid = strtrimSafe(subjTable{ii,2});
        grp = strtrimSafe(subjTable{ii,3});
        cd  = strtrimSafe(subjTable{ii,4});
        info{end+1,1} = sprintf('%s | %s | %s | metric=%.4g | outside [%.4g, %.4g]', ...
            sid, grp, cd, x(ii), lo, hi); %#ok<AGROW>
        keysOut{end+1,1} = keysAll{ii}; %#ok<AGROW>
    end
else
    return;
end
end

function key = makeCacheKey(varargin)
parts = cellfun(@(x) strtrimSafe(x), varargin, 'UniformOutput', false);
key = strjoin(parts,'||');
end

function [entry, cache] = getCachedROIEntry(cache, dataFile, roiFile)
entry = [];
key = makeCacheKey('ROI',dataFile,roiFile);

if isstruct(cache) && isfield(cache,'roiTC') && isa(cache.roiTC,'containers.Map')
    if isKey(cache.roiTC, key)
        entry = cache.roiTC(key);
        return;
    end
end

[okTxt, tMin, psc] = tryReadSCMroiExportTxt(roiFile);
if okTxt
    entry.tc = double(psc(:))';
    entry.tMin = double(tMin(:))';
    entry.isPSCInput = true;
else
    if isempty(roiFile) || exist(roiFile,'file')~=2
        error('ROIFile missing or not found: %s', roiFile);
    end
    [~,~,ext] = fileparts(roiFile);
    ext = lower(ext);
    if strcmp(ext,'.mat')
        [tcRaw, tMin2] = extractROITC_legacyMat(roiFile);
        entry.tc = double(tcRaw(:))';
        entry.tMin = double(tMin2(:))';
        entry.isPSCInput = false;
    else
        if isempty(dataFile) || exist(dataFile,'file')~=2
            error('DATA .mat required for raw ROI txt: %s', dataFile);
        end
        [tcRaw, tMin2] = extractROITC_fromDataAndROI(dataFile, roiFile);
        entry.tc = double(tcRaw(:))';
        entry.tMin = double(tMin2(:))';
        entry.isPSCInput = false;
    end
end

if isstruct(cache) && isfield(cache,'roiTC') && isa(cache.roiTC,'containers.Map')
    try
        cache.roiTC(key) = entry;
    catch
    end
end
end

function [R, cache] = runROITimecourseAnalysis(S, subjActive, cache)
grpCol = colAsStr(subjActive,3);
grpCol(cellfun(@isempty,grpCol)) = {'GroupA'};

gNames = uniqueStable(grpCol);
gNames = sortGroupNamesStableGA(gNames, S);

if isempty(gNames)
    error('No groups defined.');
end

N = size(subjActive,1);
tcAll = cell(N,1);
tAll  = cell(N,1);
isPSCInput = false(N,1);

for i = 1:N
    dataFile = strtrimSafe(subjActive{i,6});
    roiFile  = strtrimSafe(subjActive{i,7});
    [entry, cache] = getCachedROIEntry(cache, dataFile, roiFile);
    tcAll{i} = entry.tc;
    tAll{i}  = entry.tMin;
    isPSCInput(i) = entry.isPSCInput;
end

t0 = max(cellfun(@(x) x(1), tAll));
t1 = min(cellfun(@(x) x(end), tAll));
dtAll = nan(N,1);
for i = 1:N
    di = diff(tAll{i});
    di = di(isfinite(di) & di > 0);
    if ~isempty(di)
        dtAll(i) = median(di);
    end
end
dt = median(dtAll(isfinite(dtAll)));
if ~isfinite(dt) || dt <= 0
    dt = 0.1;
end
if t1 <= t0
    error('Time axes do not overlap across subjects.');
end
tCommon = t0:dt:t1;

Xraw = nan(N,numel(tCommon));
for i = 1:N
    Xraw(i,:) = interp1(tAll{i}(:), tcAll{i}(:), tCommon(:), 'linear', NaN).';
end

X = Xraw;

if S.tc_computePSC
    baseIdx = (tCommon >= S.tc_baseMin0) & (tCommon <= S.tc_baseMin1);
    if ~any(baseIdx)
        error('Baseline window has no samples.');
    end
    for i = 1:N
        if isPSCInput(i)
            continue;
        end
        b = nanmean_local(Xraw(i,baseIdx),2);
        if ~isfinite(b) || b == 0
            b = eps;
        end
        X(i,:) = 100 * (Xraw(i,:) - b) ./ b;
    end
end

unitsPercent = any(isPSCInput) || S.tc_computePSC;
groupColors = assignGroupColorsWithMode(gNames, S);

groupTC = struct([]);
for g = 1:numel(gNames)
    idx = strcmpi(grpCol, gNames{g});
    mu = nanmean_local(X(idx,:),1);
    sd = nanstd_local(X(idx,:),0,1);
    n  = sum(isfinite(X(idx,:)),1);
    se = sd ./ sqrt(max(1,n));

    groupTC(g).name = gNames{g};
    groupTC(g).mean = mu;
    groupTC(g).sem  = se;
    groupTC(g).n    = sum(idx);
end

platIdx = (tCommon >= S.tc_plateauMin0) & (tCommon <= S.tc_plateauMin1);
if ~any(platIdx)
    error('Plateau window has no samples.');
end

plateau = nan(N,1);
for i = 1:N
    plateau(i) = nanmean_local(X(i,platIdx),2);
end

peakVal = nan(N,1);
for i = 1:N
    peakVal(i) = robustPeak(X(i,:), tCommon, ...
        S.tc_peakSearchMin0, S.tc_peakSearchMin1, ...
        S.tc_peakWinMin, S.tc_trimPct);
end

if strcmpi(S.tc_metric,'Plateau')
    metricVals = plateau;
    metricName = sprintf('Plateau mean (%.1f-%.1f min)', S.tc_plateauMin0, S.tc_plateauMin1);
else
    metricVals = peakVal;
    metricName = sprintf('Robust peak (%.1f-%.1f min)', S.tc_peakSearchMin0, S.tc_peakSearchMin1);
end

stats = computeStats(metricVals, grpCol, S);

Tcell = cell(N+1,6);
Tcell(1,:) = {'Subject','Group','Condition','PairID','Metric','MetricName'};
for i = 1:N
    Tcell{i+1,1} = strtrimSafe(subjActive{i,2});
    Tcell{i+1,2} = strtrimSafe(subjActive{i,3});
    Tcell{i+1,3} = strtrimSafe(subjActive{i,4});
    Tcell{i+1,4} = strtrimSafe(subjActive{i,5});
    Tcell{i+1,5} = metricVals(i);
    Tcell{i+1,6} = metricName;
end

R = struct();
R.mode = 'ROI Timecourse';
R.tMin = tCommon;
R.group = groupTC;
R.groupNames = gNames;
R.groupDisplayNames = resolveDisplayGroupNames(gNames, S);
R.groupColors = groupColors;
R.unitsPercent = unitsPercent;
R.metricName = metricName;
R.metricVals = metricVals;
R.stats = stats;
R.metrics = struct('table',{Tcell});
R.subjTable = subjActive;
R.plotTop = S.plotTop;
R.plotBot = S.plotBot;
R.showSEM = S.tc_showSEM;
end

function p = p_to_stars(pv)
if ~isfinite(pv)
    p = 'p=?';
elseif pv < 0.001
    p = '***';
elseif pv < 0.01
    p = '**';
elseif pv < 0.05
    p = '*';
else
    p = 'n.s.';
end
end

function annotateStatsBottom(ax, R, S)
p = R.stats.p;
alpha = R.stats.alpha;
stars = p_to_stars(p);
[~,fg] = previewColors(S.previewStyle);

yl = ylim(ax);
ySpan = yl(2)-yl(1);
if ~isfinite(ySpan) || ySpan<=0, ySpan = 1; end
yBar = yl(2) - 0.10*ySpan;

gN = numel(R.groupNames);
tType = '';
if isfield(R.stats,'type'), tType = strtrimSafe(R.stats.type); end

isTwo = contains(lower(tType),'student') || contains(lower(tType),'welch') || contains(lower(tType),'two-sample') || contains(lower(tType),'t-test');

if gN >= 2 && isTwo
    x1 = 1;
    x2 = 2;
    plot(ax, [x1 x1 x2 x2], [yBar-0.02*ySpan yBar yBar yBar-0.02*ySpan], '-', 'LineWidth', 2, 'Color', fg);
    text(ax, (x1+x2)/2, yBar + 0.02*ySpan, stars, ...
        'Color',fg,'FontSize',16,'FontWeight','bold', ...
        'HorizontalAlignment','center','VerticalAlignment','bottom');
   if S.showPText
    text(ax, (x1+x2)/2, yBar - 0.06*ySpan, sprintf('p = %.3g', p), ...
        'Color',fg,'FontSize',11, ...
        'HorizontalAlignment','center','VerticalAlignment','top');
end
else
    txt = sprintf('%s | p=%.3g', shortType(tType), p);
    text(ax, mean(xlim(ax)), yl(2)-0.04*ySpan, txt, ...
        'Color',fg,'FontSize',12,'FontWeight','bold', ...
        'HorizontalAlignment','center','VerticalAlignment','top');
    if isfinite(p) && p < alpha
        text(ax, mean(xlim(ax)), yl(2)-0.09*ySpan, stars, ...
            'Color',fg,'FontSize',16,'FontWeight','bold', ...
            'HorizontalAlignment','center','VerticalAlignment','top');
    end
end
end

function annotateStatsTopText(ax, R, S)
p = R.stats.p;
alpha = R.stats.alpha;
stars = p_to_stars(p);
[~,fg] = previewColors(S.previewStyle);

xl = xlim(ax);
yl = ylim(ax);
x = xl(2) - 0.02*(xl(2)-xl(1));
y = yl(2) - 0.05*(yl(2)-yl(1));

txt = sprintf('%s  p=%.3g', stars, p);
text(ax, x, y, txt, ...
    'Color',fg,'FontSize',12,'FontWeight','bold', ...
    'HorizontalAlignment','right','VerticalAlignment','top');
if S.showPText
    text(ax, x, y - 0.06*(yl(2)-yl(1)), sprintf('alpha=%.3g', alpha), ...
        'Color',0.7*fg,'FontSize',10, ...
        'HorizontalAlignment','right','VerticalAlignment','top');
end
end

function s = shortType(s)
s = strtrimSafe(s);
if isempty(s), s = 'Test'; end
if numel(s)>26, s = [s(1:26) '...']; end
end

function M = meanOverFrames(I, idx, dimT)
subs = repmat({':'},1,ndims(I));
subs{dimT} = idx;
X = I(subs{:});
M = mean(double(X), dimT);
end

function X = catAlong4(cellMaps)
N = numel(cellMaps);
sz = size(cellMaps{1});
if numel(sz)==2
    X = zeros(sz(1),sz(2),N);
    for i=1:N, X(:,:,i)=double(cellMaps{i}); end
else
    X = zeros(sz(1),sz(2),sz(3),N);
    for i=1:N, X(:,:,:,i)=double(cellMaps{i}); end
end
end

function m = meanCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmean_local(X, ndims(X));
end

function m = medianCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmedian_local(X, ndims(X));
end

function md = nanmedian_local(X, dim)
try
    md = median(X, dim, 'omitnan');
catch
    sz = size(X);
    nd = numel(sz);
    dim = max(1, min(nd, dim));
    perm = 1:nd;
    perm([dim nd]) = [nd dim];
    Y = permute(X, perm);
    Y = reshape(Y, [], sz(dim));
    Y(~isfinite(Y)) = NaN;
    Y = sort(Y, 2, 'ascend');
    n = sum(isfinite(Y), 2);
    mdFlat = NaN(size(n));
    for i = 1:numel(n)
        ni = n(i);
        if ni<=0, continue; end
        if mod(ni,2)==1
            mdFlat(i) = Y(i,(ni+1)/2);
        else
            mdFlat(i) = 0.5*(Y(i,ni/2)+Y(i,ni/2+1));
        end
    end
    Y2 = reshape(mdFlat, sz(perm(1:end-1)));
    md = ipermute(Y2, perm);
end
end

function meta = extractMetaFromSources(subjectTxt, dataFile, roiFile, bundleFile)
if nargin < 4, bundleFile = ''; end

meta = struct('animalID','N/A','session','N/A','scanID','N/A');
cands = {bundleFile, roiFile, dataFile, subjectTxt};

for i = 1:numel(cands)
    txt = strtrimSafe(cands{i});
    if isempty(txt), continue; end

    m = parseMetaSingleText(txt);

    if strcmpi(meta.animalID,'N/A') && ~strcmpi(m.animalID,'N/A')
        meta.animalID = m.animalID;
    end
    if strcmpi(meta.session,'N/A') && ~strcmpi(m.session,'N/A')
        meta.session = m.session;
    end
    if strcmpi(meta.scanID,'N/A') && ~strcmpi(m.scanID,'N/A')
        meta.scanID = m.scanID;
    end

    if ~strcmpi(meta.animalID,'N/A') && ~strcmpi(meta.session,'N/A') && ~strcmpi(meta.scanID,'N/A')
        return;
    end
end
end

    function meta = parseMetaSingleText(txt)
meta = struct('animalID','N/A','session','N/A','scanID','N/A');

if nargin < 1 || isempty(txt)
    return;
end

try
    txt = char(txt);
catch
    return;
end

txt = strrep(txt,'\','/');
txtU = upper(txt);

% ---------------------------------------------------------
% OLD STYLE 1: ANIMAL_S1_FUS_2
% ---------------------------------------------------------
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)_(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = strtrim(tok{1});
    meta.session  = strtrim(tok{2});
    meta.scanID   = strtrim(tok{3});
    return;
end

% ---------------------------------------------------------
% OLD STYLE 2: ANIMAL_S1
% ---------------------------------------------------------
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = strtrim(tok{1});
    meta.session  = strtrim(tok{2});
end

% ---------------------------------------------------------
% OLD STYLE 3: FUS_2
% ---------------------------------------------------------
tok = regexpi(txtU,'(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.scanID = strtrim(tok{1});
end

if ~strcmpi(meta.animalID,'N/A') || ~strcmpi(meta.session,'N/A') || ~strcmpi(meta.scanID,'N/A')
    return;
end

% ---------------------------------------------------------
% NEW STYLE:
% RGRO_260407_1024_MM_B6J_1059_scan2_SB
% -> animalID = 1059
% -> session  = N/A
% -> scanID   = scan2_SB
%
% Also works for scan3_M, scan4_ES, etc.
% We parse from the FULL PATH so it still works if the ROI filename
% itself is generic but the folder contains the dataset name.
% ---------------------------------------------------------
txtTok = regexprep(txt,'[^A-Za-z0-9/_\-]','_');
parts = regexp(txtTok,'[/_\-]+','split');
parts = parts(~cellfun(@isempty,parts));

scanIdx = [];
for k = 1:numel(parts)
    if ~isempty(regexpi(parts{k},'^scan\d+$','once'))
        scanIdx = k;

        scanID = parts{k};

        % Optional suffix after scan token, e.g. SB / M / ES
        if k < numel(parts)
            nxt = parts{k+1};

            if ~isempty(regexpi(nxt,'^[A-Za-z]{1,6}[A-Za-z0-9]*$','once')) && ...
               isempty(regexpi(nxt,'^S\d+$','once')) && ...
               isempty(regexpi(nxt,'^\d+$','once'))
                scanID = [scanID '_' nxt];
            end
        end

        meta.scanID = scanID;
        break;
    end
end

% Session only if explicit S<number> exists somewhere
for k = 1:numel(parts)
    if ~isempty(regexpi(parts{k},'^S\d+$','once'))
        meta.session = parts{k};
        break;
    end
end

% Animal ID = numeric token immediately before scan token
if ~isempty(scanIdx)
    for k = scanIdx-1:-1:max(1,scanIdx-3)
        if ~isempty(regexpi(parts{k},'^\d{3,6}$','once'))
            meta.animalID = parts{k};
            break;
        end
    end
end

% ---------------------------------------------------------
% Fallbacks
% ---------------------------------------------------------
if strcmpi(meta.scanID,'N/A')
    tok = regexpi(txt,'(scan\d+(?:_[A-Za-z0-9]+)?)','tokens','once');
    if ~isempty(tok)
        meta.scanID = tok{1};
    end
end

if strcmpi(meta.animalID,'N/A')
    tok = regexpi(txtU,'\b([A-Z]{1,8}\d{6}[A-Z]?)\b','tokens','once');
    if ~isempty(tok)
        meta.animalID = strtrim(tok{1});
    end
end
end

function animalID = extractAnimalIDFromText(txt)
m = parseMetaSingleText(txt);
animalID = m.animalID;
if strcmpi(animalID,'N/A'), animalID = ''; end
end

function sess = extractSessionFromText(txt)
m = parseMetaSingleText(txt);
sess = m.session;
if strcmpi(sess,'N/A'), sess = ''; end
end

function scanID = extractScanIDFromText(txt)
m = parseMetaSingleText(txt);
scanID = m.scanID;
if strcmpi(scanID,'N/A'), scanID = ''; end
end

function idx = secToIdx(s0,s1,TR,T)
i0 = floor(s0/TR) + 1;
i1 = floor(s1/TR);
i0 = max(1, min(T, i0));
i1 = max(1, min(T, i1));
if i1 < i0
    idx = i0;
else
    idx = i0:i1;
end
end

function M = extractPSCMap(fp, b0, b1, s0, s1)
D = loadPipelineStruct(fp);
if ~isfield(D,'TR') || isempty(D.TR), error('Missing TR in %s', fp); end
if ~isfield(D,'I')  || isempty(D.I),  error('Missing I in %s', fp); end
I = D.I;
TR = double(D.TR);
dimT = ndims(I);
T = size(I, dimT);

bIdx = secToIdx(b0,b1,TR,T);
sIdx = secToIdx(s0,s1,TR,T);

baseMean = meanOverFrames(I, bIdx, dimT);
sigMean  = meanOverFrames(I, sIdx, dimT);

baseMean = double(baseMean);
sigMean  = double(sigMean);
baseMean(baseMean==0) = eps;
M = 100 * (sigMean - baseMean) ./ baseMean;
M(~isfinite(M)) = 0;
end

function [mapOut, cache] = getCachedPSCMap(cache, dataFile, b0, b1, s0, s1)
key = makeCacheKey('PSC',dataFile,num2str(b0),num2str(b1),num2str(s0),num2str(s1));
if isstruct(cache) && isfield(cache,'pscMap') && isa(cache.pscMap,'containers.Map')
    if isKey(cache.pscMap,key)
        mapOut = cache.pscMap(key);
        return;
    end
end

mapOut = extractPSCMap(dataFile, b0, b1, s0, s1);

if isstruct(cache) && isfield(cache,'pscMap') && isa(cache.pscMap,'containers.Map')
    try
        cache.pscMap(key) = mapOut;
    catch
    end
end
end

%%% =====================================================================
%%% Group Map function %%%%
%%% =====================================================================

function V = makeUITableDisplayData(subj, minRows)
if nargin < 2 || isempty(minRows)
    minRows = 0;
end

V = subjToUITable(subj);
n = size(V,1);

if minRows > 0 && n < minRows
    pad = cell(minRows - n, 9);
    for i = 1:size(pad,1)
        pad{i,1} = false;
        for j = 2:9
            pad{i,j} = '';
        end
    end
    V = [V; pad];
end
end

function V = stripUITablePlaceholders(V)
if isempty(V), return; end

keep = false(size(V,1),1);

for i = 1:size(V,1)
    useVal = false;
    try
        useVal = logicalCellValue(V{i,1});
    catch
    end

    hasContent = false;
    for j = 2:9
        x = V{i,j};
        if ischar(x) || isstring(x)
            if ~isempty(strtrim(char(x)))
                hasContent = true;
                break;
            end
        elseif isnumeric(x)
            if ~isempty(x) && any(isfinite(x(:)))
                hasContent = true;
                break;
            end
        elseif islogical(x)
            if any(x(:))
                hasContent = true;
                break;
            end
        else
            try
                if ~isempty(x)
                    hasContent = true;
                    break;
                end
            catch
            end
        end
    end

    keep(i) = useVal || hasContent;
end

V = V(keep,:);
end

function condName = mapConditionFromGroup(S, groupName)
condName = '';
g = upper(strtrimSafe(groupName));

if isempty(g)
    return;
end

try
    if isa(S.groupToCondMap,'containers.Map') && isKey(S.groupToCondMap, g)
        condName = strtrimSafe(S.groupToCondMap(g));
        return;
    end
catch
end

if contains(g,'PACAP') || contains(g,'CONDA') || strcmp(g,'A') || contains(g,'GROUPA')
    condName = 'CondA';
elseif contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || contains(g,'CONDB') || strcmp(g,'B') || contains(g,'GROUPB')
    condName = 'CondB';
end
end

function pairs = exportGroupCondPairs(mapObj)
pairs = cell(0,2);
try
    if isa(mapObj,'containers.Map')
        k = keys(mapObj);
        for i = 1:numel(k)
            pairs(end+1,1:2) = {k{i}, mapObj(k{i})}; %#ok<AGROW>
        end
    end
catch
end
end

function mapObj = importGroupCondPairs(pairs, mapObj)
try
    if isempty(mapObj)
        mapObj = containers.Map('KeyType','char','ValueType','char');
    end
catch
    return;
end

if isempty(pairs)
    return;
end

for i = 1:size(pairs,1)
    g = strtrimSafe(pairs{i,1});
    c = strtrimSafe(pairs{i,2});
    if ~isempty(g) && ~isempty(c)
        try
            mapObj(upper(g)) = c;
        catch
        end
    end
end
end

function S = removeRowsFromState(S, sel)
sel = unique(sel(:)');
sel = sel(sel >= 1 & sel <= size(S.subj,1));
if isempty(sel)
    return;
end

oldPreviewRow = S.mapPreviewRow;

S.subj(sel,:) = [];

if isfield(S,'rowPacapSide') && ~isempty(S.rowPacapSide)
    keep = true(numel(S.rowPacapSide),1);
    keep(sel(sel <= numel(keep))) = false;
    S.rowPacapSide = S.rowPacapSide(keep);
end

if ~isempty(S.selectedRows)
    keepSel = setdiff(S.selectedRows(:)', sel, 'stable');
    for k = 1:numel(keepSel)
        keepSel(k) = keepSel(k) - sum(sel < keepSel(k));
    end
    S.selectedRows = keepSel;
else
    S.selectedRows = [];
end

if isempty(oldPreviewRow) || ~isfinite(oldPreviewRow)
    S.mapPreviewRow = NaN;
elseif any(sel == oldPreviewRow)
    S.mapPreviewRow = NaN;
else
    S.mapPreviewRow = oldPreviewRow - sum(sel < oldPreviewRow);
end

S.lastROI = struct();
S.lastMAP = struct();
S.outlierKeys = {};
S.outlierInfo = {};

S = ensureRowPacapSideSize(S);
end

function gNames = sortGroupNamesStableGA(gNames, S)
if isempty(gNames)
    return;
end

n = numel(gNames);
rank = 100 + (1:n);

for i = 1:n
    nm  = strtrimSafe(gNames{i});
    nmU = upper(nm);

    if strcmpi(S.colorMode,'Manual A/B')
        if strcmpi(nm, strtrimSafe(S.manualGroupA))
            rank(i) = min(rank(i), 1);
        elseif strcmpi(nm, strtrimSafe(S.manualGroupB))
            rank(i) = min(rank(i), 2);
        end
    end

    if contains(nmU,'CONDA') || strcmp(nmU,'A') || contains(nmU,'PACAP') || contains(nmU,'GROUPA')
        rank(i) = min(rank(i), 1);
    elseif contains(nmU,'CONDB') || strcmp(nmU,'B') || contains(nmU,'VEH') || contains(nmU,'VEHICLE') || contains(nmU,'CONTROL') || contains(nmU,'GROUPB')
        rank(i) = min(rank(i), 2);
    elseif contains(nmU,'BASELINE')
        rank(i) = min(rank(i), 3);
    elseif contains(nmU,'POST')
        rank(i) = min(rank(i), 4);
    end
end

[~,ord] = sort(rank);
gNames = gNames(ord);
end

    function d = getSmartBrowseDir(S, purpose)
if nargin < 2 || isempty(purpose)
    purpose = 'add';
end

d = '';

sel = clampSelRows(S.selectedRows, size(S.subj,1));
rowOrder = [sel(:).' setdiff(1:size(S.subj,1), sel(:).', 'stable')];

for k = 1:numel(rowOrder)
    r = rowOrder(k);
    info = extractRowMetaLight(S.subj(r,:));

    fpList = {info.bundleFile, info.roiFile, info.dataFile};
    for j = 1:numel(fpList)
        fp = strtrimSafe(fpList{j});
        if ~isempty(fp) && exist(fp,'file') == 2
            d0 = fileparts(fp);
            if exist(d0,'dir') == 7
                d = d0;
                break;
            end
        end
    end

    if ~isempty(d)
        break;
    end
end

if isempty(d)
    if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(char(S.opt.startDir),'dir') == 7
        d = char(S.opt.startDir);
    else
        d = pwd;
    end
end

if strcmpi(purpose,'save')
    gaDir = fullfile(d, 'GroupAnalysis');
    if exist(gaDir,'dir') ~= 7
        try
            mkdir(gaDir);
        catch
        end
    end
    if exist(gaDir,'dir') == 7
        d = gaDir;
    end
end

if exist(d,'dir') ~= 7
    d = pwd;
end
end

    function d = getBundleBrowseDir(S)
    d = '';

    sel = clampSelRows(S.selectedRows, size(S.subj,1));

    % 1) Strongest preference: selected rows
    candRows = sel(:).';

    % 2) If nothing selected, try active USE rows
    if isempty(candRows)
        candRows = find(logicalCol(S.subj,1)).';
    end

    % 3) If still nothing, try all rows
    if isempty(candRows)
        candRows = 1:size(S.subj,1);
    end

    for k = 1:numel(candRows)
        r = candRows(k);
        try
            d = buildBundleBrowseDirFromRow(S, S.subj(r,:));
        catch
            d = '';
        end
        if exist(d,'dir') == 7
            return;
        end
    end

    % 4) Project root fallback
    d = getPreferredPacapRootDir(S);
    if exist(d,'dir') == 7
        return;
    end

    % 5) Generic fallback
    d = getSmartBrowseDir(S,'add');
    end

function d = buildBundleBrowseDirFromRow(S, row)
    d = '';

    info = extractRowMetaLight(row);

    animalID  = strtrimSafe(info.animalID);
    sessionID = strtrimSafe(info.session);
    scanID    = upper(strtrimSafe(info.scanID));

    animalSessFolder = '';
    scanFolder = '';

    if ~isempty(animalID) && ~strcmpi(animalID,'N/A') && ...
       ~isempty(sessionID) && ~strcmpi(sessionID,'N/A')
        animalSessFolder = [animalID '_' sessionID];
    end

    % THIS WAS THE MISSING PART IN YOUR CURRENT CODE
    if ~isempty(animalSessFolder) && ~isempty(scanID) && ~strcmpi(scanID,'N/A')
        scanFolder = [animalSessFolder '_' scanID];
    end

    % Fast exact path first
    rootPACAP = getPreferredPacapRootDir(S);
    if ~isempty(rootPACAP) && exist(rootPACAP,'dir') == 7 && ...
       ~isempty(animalSessFolder) && ~isempty(scanFolder)

        cands = { ...
            fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles', 'SCM'), ...
            fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles'), ...
            fullfile(rootPACAP, animalSessFolder, scanFolder)};

        for kk = 1:numel(cands)
            if exist(cands{kk},'dir') == 7
                d = cands{kk};
                return;
            end
        end
    end

    % Fallback: infer from already stored file paths
    probeList = {info.bundleFile, info.dataFile, info.roiFile};

    for ii = 1:numel(probeList)
        probe = strtrimSafe(probeList{ii});
        if isempty(probe)
            continue;
        end

        if exist(probe,'file') == 2 || exist(probe,'dir') == 7
            if ~isempty(animalSessFolder) && ~isempty(scanFolder)
                dTry = findBundleDirFromProbe(probe, animalSessFolder, scanFolder);
                if exist(dTry,'dir') == 7
                    d = dTry;
                    return;
                end
            end

            if exist(probe,'file') == 2
                d = fileparts(probe);
            else
                d = probe;
            end

            if exist(d,'dir') == 7
                return;
            end
        end
    end

    % Last fallback
    try
        if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(char(S.opt.startDir),'dir') == 7
            d = char(S.opt.startDir);
        end
    catch
    end

    if isempty(d) || exist(d,'dir') ~= 7
        d = pwd;
    end
end

function d = findAnimalFolderFromPath(startDir, animalID)
d = startDir;
cur = startDir;
prev = '';

animalID = upper(strtrimSafe(animalID));

while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    leafU = upper(strtrimSafe(leaf));

    if ~isempty(animalID)
        if strcmp(leafU, animalID) || ...
           (numel(leafU) > numel(animalID) && strncmp(leafU, [animalID '_'], numel(animalID)+1))
            d = cur;
            return;
        end
    end

    if isempty(parent) || strcmp(parent, cur)
        break;
    end

    prev = cur;
    cur = parent;
end
end

function d = findFolderBeforeAnimal(fp, animalID)
if exist(fp,'file') == 2
    cur = fileparts(fp);
else
    cur = fp;
end

if isempty(cur) || exist(cur,'dir') ~= 7
    d = pwd;
    return;
end

animalID = upper(strtrimSafe(animalID));
d = cur;
prev = '';

while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    if isempty(parent) || strcmp(parent, cur)
        break;
    end

    leafU = upper(strtrimSafe(leaf));
    if ~isempty(animalID)
        if strcmp(leafU, animalID) || ...
           (numel(leafU) > numel(animalID) && strncmp(leafU, [animalID '_'], numel(animalID)+1))
            d = parent;
            return;
        end
    end

    prev = cur;
    cur = parent;
end

[parent,~] = fileparts(d);
if ~isempty(parent) && exist(parent,'dir') == 7
    d = parent;
end
end

function startDir = getExcelExportStartDir(S)
startDir = getSmartBrowseDir(S, 'save');
end

function c = conditionRowColorGA(condName)
u = upper(strtrimSafe(condName));

if contains(u,'CONDA') || strcmp(u,'A') || contains(u,'PACAP') || contains(u,'GROUPA')
    c = [0.14 0.34 0.18];
elseif contains(u,'CONDB') || strcmp(u,'B') || contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL') || contains(u,'GROUPB')
    c = [0.08 0.22 0.12];
elseif contains(u,'BASELINE')
    c = [0.10 0.24 0.22];
elseif contains(u,'POST')
    c = [0.18 0.26 0.12];
else
    c = [0.10 0.24 0.14];
end
end

function f = makeField(s)
s = strtrimSafe(s);

if isempty(s)
    s = 'Group';
end

try
    f = matlab.lang.makeValidName(s);
catch
    f = regexprep(s,'[^A-Za-z0-9_]','_');
    if isempty(f)
        f = 'Group';
    end
    if ~isletter(f(1))
        f = ['x_' f];
    end
end

if isempty(f)
    f = 'Group';
end
end

function subj = guessSubjectID(txt)
subj = '';

if nargin < 1 || isempty(txt)
    subj = ['S' datestr(now,'HHMMSS')];
    return;
end

txt = strtrimSafe(txt);

try
    m = parseMetaSingleText(txt);
    if isfield(m,'animalID') && ~strcmpi(strtrimSafe(m.animalID),'N/A')
        subj = strtrimSafe(m.animalID);
        return;
    end
catch
end

try
    [~,bn,~] = fileparts(txt);
    bn = strtrimSafe(bn);
    if ~isempty(bn)
        subj = bn;
        return;
    end
catch
end

subj = ['S' datestr(now,'HHMMSS')];
end

function dataFile = findDataMatNearROI(roiFile)
dataFile = '';

if nargin < 1 || isempty(roiFile)
    return;
end

roiFile = strtrimSafe(roiFile);
if exist(roiFile,'file') ~= 2
    return;
end

roiDir = fileparts(roiFile);
if isempty(roiDir) || exist(roiDir,'dir') ~= 7
    return;
end

meta = parseMetaSingleText(roiFile);
targetAnimal = strtrimSafe(meta.animalID);
targetSess   = strtrimSafe(meta.session);
targetScan   = strtrimSafe(meta.scanID);

cand = dir(fullfile(roiDir,'*.mat'));
bestScore = -inf;
bestFile = '';

for i = 1:numel(cand)
    fp = fullfile(cand(i).folder, cand(i).name);

    % skip obvious non-data files
    if isScmGroupBundleFile(fp)
        continue;
    end

    nmL = lower(cand(i).name);
    if contains(nmL,'roi') || contains(nmL,'groupanalysis') || contains(nmL,'groupexport')
        continue;
    end

    score = 0;
    m2 = parseMetaSingleText(fp);

    if ~isempty(targetAnimal) && ~strcmpi(targetAnimal,'N/A') && strcmpi(strtrimSafe(m2.animalID), targetAnimal)
        score = score + 10;
    end
    if ~isempty(targetSess) && ~strcmpi(targetSess,'N/A') && strcmpi(strtrimSafe(m2.session), targetSess)
        score = score + 5;
    end
    if ~isempty(targetScan) && ~strcmpi(targetScan,'N/A') && strcmpi(strtrimSafe(m2.scanID), targetScan)
        score = score + 5;
    end

    % prefer files that at least look like main data files
    if contains(lower(fp),'brain') || contains(lower(fp),'raw') || contains(lower(fp),'data')
        score = score + 1;
    end

    if score > bestScore
        bestScore = score;
        bestFile = fp;
    end
end

if ~isempty(bestFile)
    dataFile = bestFile;
    return;
end

% fallback: also try parent folder
parDir = fileparts(roiDir);
if ~isempty(parDir) && exist(parDir,'dir') == 7
    cand = dir(fullfile(parDir,'*.mat'));
    bestScore = -inf;
    bestFile = '';

    for i = 1:numel(cand)
        fp = fullfile(cand(i).folder, cand(i).name);

        if isScmGroupBundleFile(fp)
            continue;
        end

        nmL = lower(cand(i).name);
        if contains(nmL,'roi') || contains(nmL,'groupanalysis') || contains(nmL,'groupexport')
            continue;
        end

        score = 0;
        m2 = parseMetaSingleText(fp);

        if ~isempty(targetAnimal) && ~strcmpi(targetAnimal,'N/A') && strcmpi(strtrimSafe(m2.animalID), targetAnimal)
            score = score + 10;
        end
        if ~isempty(targetSess) && ~strcmpi(targetSess,'N/A') && strcmpi(strtrimSafe(m2.session), targetSess)
            score = score + 5;
        end
        if ~isempty(targetScan) && ~strcmpi(targetScan,'N/A') && strcmpi(strtrimSafe(m2.scanID), targetScan)
            score = score + 5;
        end

        if score > bestScore
            bestScore = score;
            bestFile = fp;
        end
    end

    if ~isempty(bestFile)
        dataFile = bestFile;
    end
end
end

function P = studio_resolve_paths(studio, moduleName, datasetLabel)
if nargin < 1 || isempty(studio) || ~isstruct(studio)
    studio = struct();
end
if nargin < 2 || isempty(moduleName)
    moduleName = 'GroupAnalysis';
end
if nargin < 3
    datasetLabel = '';
end

rootBase = '';
try
    if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(char(studio.exportPath),'dir') == 7
        rootBase = char(studio.exportPath);
    elseif isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(char(studio.loadedPath),'dir') == 7
        rootBase = char(studio.loadedPath);
    elseif isfield(studio,'loadedFile') && ~isempty(studio.loadedFile) && exist(char(studio.loadedFile),'file') == 2
        rootBase = fileparts(char(studio.loadedFile));
    end
catch
    rootBase = '';
end

if isempty(rootBase)
    rootBase = pwd;
end

analysedRoot = guessAnalysedRoot(rootBase);
groupDir = fullfile(analysedRoot, 'GroupAnalysis');
safeMkdirIfNeeded(groupDir);

datasetKey = sanitizeName(datasetLabel);
if isempty(datasetKey)
    datasetKey = 'General';
end

P = struct();
P.rootBase     = rootBase;
P.analysedRoot = analysedRoot;
P.groupDir     = groupDir;
P.moduleDir    = fullfile(groupDir, datasetKey);
P.bundleDir    = fullfile(groupDir, 'Bundles');
end

function root = guessAnalysedRoot(rootBase)
root = rootBase;
if isempty(root) || exist(root,'dir') ~= 7
    root = pwd;
end

cur = root;
prev = '';
while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    if strcmpi(leaf,'AnalysedData')
        root = cur;
        return;
    end
    if isempty(parent) || strcmp(parent, cur)
        break;
    end
    prev = cur;
    cur = parent;
end

root = fullfile(rootBase, 'AnalysedData');
safeMkdirIfNeeded(root);
end

function d = getPreferredPacapRootDir(S)
    d = '';

    cands = {'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData\AprilStayLeuven\PACAP'};

    try
        if isfield(S,'opt') && isfield(S.opt,'studio') && isstruct(S.opt.studio)
            if isfield(S.opt.studio,'exportPath') && ~isempty(S.opt.studio.exportPath)
                cands{end+1} = char(S.opt.studio.exportPath); %#ok<AGROW>
            end
            if isfield(S.opt.studio,'loadedPath') && ~isempty(S.opt.studio.loadedPath)
                cands{end+1} = char(S.opt.studio.loadedPath); %#ok<AGROW>
            end
        end
    catch
    end

    for i = 1:numel(cands)
        cc = strtrimSafe(cands{i});
        if ~isempty(cc) && exist(cc,'dir') == 7
            d = cc;
            return;
        end
    end
end

    function updateMapGroupSideLabels()
    S0 = guidata(hFig);

    if isfield(S0,'hMapPreviewSideLabel') && ishghandle(S0.hMapPreviewSideLabel)
        set(S0.hMapPreviewSideLabel,'String','Inj side:','FontSize',10);
    end

    if isfield(S0,'hMapRefSideLabel') && ishghandle(S0.hMapRefSideLabel)
        set(S0.hMapRefSideLabel,'String','Ref hemi:','FontSize',10);
    end
end

    function [S, nApplied] = applyUseStateToMatchingRows(S, rRef, useVal)
    nApplied = 0;

    rows = findMatchingRowsByMetaOrBundle(S, rRef);
    if isempty(rows)
        rows = rRef;
    end

    for i = 1:numel(rows)
        rr = rows(i);
        S.subj{rr,1} = logical(useVal);

        if useVal
            st = lower(strtrimSafe(S.subj{rr,9}));
            if contains(st,'not used') || contains(st,'excluded')
                S.subj{rr,9} = '';
            end
        else
            S.subj{rr,9} = 'Not used';
        end

        nApplied = nApplied + 1;
    end

    S = sanitizeTableStruct(S);
    S = ensureRowPacapSideSize(S);
end

    function colors = buildMapSideTableColors(rows, mapRows)
    n = size(rows,1);
    colors = repmat([0.12 0.12 0.12], max(n,2), 1);

    for i = 1:n
        if isempty(mapRows) || i > numel(mapRows) || ~isfinite(mapRows(i))
            colors(i,:) = [0.12 0.12 0.12];
            continue;
        end

        if logicalCellValue(rows{i,1})
            colors(i,:) = [0.12 0.30 0.16];
        else
            colors(i,:) = [0.35 0.12 0.12];
        end
    end
end

function safeMkdirIfNeeded(d)
if isempty(d), return; end
if exist(d,'dir') ~= 7
    mkdir(d);
end
end

function s = sanitizeName(s)
% Standalone safe filename/folder sanitizer.
% Do not call sanitizeFilename here, because sanitizeFilename may be nested
% inside GroupAnalysis and invisible to file-level helper functions.

if nargin < 1 || isempty(s)
    s = 'export';
    return;
end

try
    if isstring(s)
        s = char(s);
    end
    if ~ischar(s)
        s = char(string(s));
    end
catch
    s = 'export';
    return;
end

s = strtrim(s);

if isempty(s)
    s = 'export';
    return;
end

% Remove Windows/macOS-invalid filename characters
s = regexprep(s,'[<>:"/\\|?*\x00-\x1F]','_');

% Keep ASCII-safe folder/file names
s = regexprep(s,'[^A-Za-z0-9_\-]','_');

% Clean repeated and edge underscores/dots
s = regexprep(s,'_+','_');
s = regexprep(s,'^[\._]+','');
s = regexprep(s,'[\._]+$','');

if isempty(s)
    s = 'export';
end

maxLen = 60;
if numel(s) > maxLen
    s = s(1:maxLen);
end
end

   function tf = metaLooseFieldMatch(a, b)
    a = strtrimSafe(a);
    b = strtrimSafe(b);

    aUnknown = isempty(a) || strcmpi(a,'N/A');
    bUnknown = isempty(b) || strcmpi(b,'N/A');

    % both unknown -> okay, treat as equal
    if aUnknown && bUnknown
        tf = true;
        return;
    end

    % one known and one unknown -> NOT a match
    if aUnknown || bUnknown
        tf = false;
        return;
    end

    % both known -> exact match only
    tf = strcmpi(a, b);
end

    function idx = findBestMetaBundleRow(S0, metaIn, preferPacap, requireEmptyBundle)
        idx = [];
        firstAny = [];

        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});

            if ~metaMatchesGA(metaRow, metaIn)
                continue;
            end

            if isempty(firstAny)
                firstAny = r;
            end

            if requireEmptyBundle && ~isempty(strtrimSafe(S0.subj{r,8}))
                continue;
            end

            if preferPacap
                if isPacapRowGA(S0.subj(r,:))
                    idx = r;
                    return;
                end
            else
                idx = r;
                return;
            end
        end

        if ~requireEmptyBundle && isempty(idx)
            idx = firstAny;
        end
    end

    function tf = isPacapRowGA(row)
        grp = upper(strtrimSafe(row{3}));
        cnd = upper(strtrimSafe(row{4}));

        tf = contains(grp,'PACAP') || contains(grp,'GROUPA') || strcmp(grp,'A') || ...
             contains(cnd,'CONDA') || strcmp(cnd,'A');
    end

    function row = makeEmptyGARow(subj, gdef, cdef, S0)
        row = {true, subj, gdef, cdef, '', '', '', '', ''};
        if get(S0.hAutoPair,'Value') == 1
            row{5} = subj;
        end
    end


