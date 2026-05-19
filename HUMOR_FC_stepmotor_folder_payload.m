function out = HUMOR_FC_stepmotor_folder_payload(folder,Y,X,Z,preferredNameFile)
% Loads step-motor FC support files from a folder.
% Returns a real per-slice ROI atlas [Y X Z], region names, and latest Segmentation MAT.

if nargin < 5, preferredNameFile = ''; end
out = struct();
out.folder = folder;
out.atlas = [];
out.names = struct('labels',[] ,'names',{{}});
out.nameFile = '';
out.labelFiles = {};
out.segmentationFile = '';
out.summary = '';

if nargin < 4 || isempty(folder) || exist(folder,'dir') ~= 7
    return;
end

files = localFiles(folder);

% ----- latest Segmentation MAT
segCand = {}; segDn = [];
for i = 1:numel(files)
    nm = lower(localShort(files{i}));
    if ~isempty(strfind(nm,'segmentation_')) && ~isempty(strfind(nm,'.mat')) && isempty(strfind(nm,'heatmap'))
        segCand{end+1} = files{i}; %#ok<AGROW>
        segDn(end+1) = localMTime(files{i}); %#ok<AGROW>
    end
end
if ~isempty(segCand)
    [~,ix] = max(segDn);
    out.segmentationFile = segCand{ix};
end

% ----- first try atlas from Segmentation labelMap
if ~isempty(out.segmentationFile)
    try
        S = load(out.segmentationFile);
        if isfield(S,'Seg'), Seg = S.Seg; else, Seg = S; end
        if isfield(Seg,'labelMap') && ~isempty(Seg.labelMap)
            out.atlas = localFitVolume(double(Seg.labelMap),Y,X,Z);
        elseif isfield(Seg,'R') && ~isempty(Seg.R)
            out.atlas = localFitVolume(double(Seg.R),Y,X,Z);
        end
        out.names = localNamesFromMatStruct(S);
        if ~isempty(out.names.labels)
            out.nameFile = out.segmentationFile;
        end
    catch
    end
end

% ----- collect per-slice label maps from Registration2D / AtlasUnderlay regions
labelFiles = {}; labelScores = []; labelIdx = [];
for i = 1:numel(files)
    f = files{i};
    nm = lower(localShort(f));
    ext = localExt(f);
    if ~strcmp(ext,'.mat'), continue; end
    sc = 0;
    if ~isempty(strfind(nm,'atlasunderlay_regions')), sc = sc + 300; end
    if ~isempty(strfind(nm,'coronalregistration2d')), sc = sc + 260; end
    if ~isempty(strfind(nm,'stepmotor_reg2d')) || ~isempty(strfind(nm,'step_motor_reg2d')), sc = sc + 250; end
    if ~isempty(strfind(nm,'atlasregionlabel')), sc = sc + 240; end
    if ~isempty(strfind(nm,'regionlabels')), sc = sc + 220; end
    if ~isempty(strfind(nm,'labelmap')), sc = sc + 210; end
    if ~isempty(strfind(nm,'segmentation_')), sc = sc + 100; end
    if ~isempty(strfind(nm,'functionalconnectivity')) || ~isempty(strfind(nm,'fc_groupbundle')), sc = sc - 500; end
    if sc <= 0, continue; end
    [R,ok] = localReadLabelMapMat(f);
    if ok && ~isempty(R)
        labelFiles{end+1} = f; %#ok<AGROW>
        labelScores(end+1) = sc; %#ok<AGROW>
        labelIdx(end+1) = localIndexFromName(f); %#ok<AGROW>
    end
end

if ~isempty(labelFiles)
    if all(isfinite(labelIdx))
        [~,ord] = sort(labelIdx);
    else
        [~,ord] = sortrows([-labelScores(:) localFileOrder(labelFiles(:))]);
    end
    labelFiles = labelFiles(ord);
    out.labelFiles = labelFiles;
    maps = {};
    for i = 1:numel(labelFiles)
        try
            [R,ok] = localReadLabelMapMat(labelFiles{i});
            if ok && ~isempty(R)
                if ndims(R) == 2
                    maps{end+1} = localResize2D(double(R),Y,X); %#ok<AGROW>
                elseif ndims(R) == 3
                    R3 = localFitVolume(double(R),Y,X,Z);
                    if ~isempty(R3)
                        out.atlas = R3;
                        break;
                    end
                end
            end
        catch
        end
    end
    if isempty(out.atlas) && ~isempty(maps)
        out.atlas = zeros(Y,X,Z);
        if numel(maps) == Z
            useIdx = 1:Z;
        else
            useIdx = round(linspace(1,numel(maps),Z));
            useIdx = max(1,min(numel(maps),useIdx));
        end
        for z = 1:Z
            out.atlas(:,:,z) = maps{useIdx(z)};
        end
    end
end

% ----- region names: explicit file first, then Segmentation MAT, then all slice TXT/CSV/MAT tables
if ~isempty(preferredNameFile) && exist(preferredNameFile,'file') == 2
    T = localReadRegionNames(preferredNameFile);
    if ~isempty(T.labels)
        out.names = T;
        out.nameFile = preferredNameFile;
    end
end

if isempty(out.names.labels) && ~isempty(out.segmentationFile)
    try
        S = load(out.segmentationFile);
        T = localNamesFromMatStruct(S);
        if ~isempty(T.labels)
            out.names = T;
            out.nameFile = out.segmentationFile;
        end
    catch
    end
end

if isempty(out.names.labels)
    Tmerge = struct('labels',[] ,'names',{{}});
    bestNameFile = '';
    for i = 1:numel(files)
        f = files{i};
        nm = lower(localShort(f));
        ext = localExt(f);
        isNameLike = false;
        if strcmp(ext,'.txt') || strcmp(ext,'.csv') || strcmp(ext,'.tsv') || strcmp(ext,'.mat')
            keys = {'atlasregions','regiontable','region_table','regionnames','region_names','labels','names','acronym','inforegions'};
            for kk = 1:numel(keys)
                if ~isempty(strfind(nm,keys{kk})), isNameLike = true; end
            end
        end
        if ~isNameLike, continue; end
        T = localReadRegionNames(f);
        if ~isempty(T.labels)
            Tmerge = localMergeNames(Tmerge,T);
            if isempty(bestNameFile), bestNameFile = f; end
        end
    end
    if ~isempty(Tmerge.labels)
        out.names = Tmerge;
        out.nameFile = bestNameFile;
    end
end

if ~isempty(out.atlas)
    out.atlas = round(double(out.atlas));
end

out.summary = sprintf('Atlas=%s | nameFile=%s | seg=%s | labelFiles=%d', ...
    localYesNo(~isempty(out.atlas)), localShort2(out.nameFile), localShort2(out.segmentationFile), numel(out.labelFiles));
end

function files = localFiles(folder)
files = {};
d = dir(folder);
for i = 1:numel(d)
    nm = d(i).name;
    if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
    f = fullfile(folder,nm);
    if d(i).isdir
        sub = localFiles(f);
        files = [files sub]; %#ok<AGROW>
    else
        files{end+1} = f; %#ok<AGROW>
    end
end
end

function [R,ok] = localReadLabelMapMat(f)
R = []; ok = false;
try
    S = load(f);
    pref = {'atlasRegionLabelsLR2D','regionLabelsLR','atlasRegionLabels2D','regionLabels','labelMap','labels','annotation','roiAtlas','regions','Regions','registeredLabels','warpedLabels','atlasLabels','atlasUnderlay'};
    for k = 1:numel(pref)
        fn = pref{k};
        if isfield(S,fn) && isnumeric(S.(fn))
            V = squeeze(double(S.(fn)));
            if ndims(V) == 2 || ndims(V) == 3
                if localLooksLikeLabels(V)
                    if strcmpi(fn,'atlasRegionLabels2D') || strcmpi(fn,'regionLabels') || strcmpi(fn,'regions') || strcmpi(fn,'Regions') || strcmpi(fn,'atlasUnderlay')
                        if ndims(V) == 2 && ~any(V(:) < 0)
                            V = localSigned2D(V);
                        end
                    end
                    R = V; ok = true; return;
                end
            end
        end
    end
    if isfield(S,'Reg2D') && isstruct(S.Reg2D)
        if isfield(S.Reg2D,'regionsImage') && ~isempty(S.Reg2D.regionsImage)
            R = localSigned2D(double(S.Reg2D.regionsImage)); ok = true; return;
        end
    end
catch
end
end

function tf = localLooksLikeLabels(V)
V = double(V(:));
V = V(isfinite(V));
if isempty(V), tf = false; return; end
u = unique(round(V));
if numel(u) < 2 || numel(u) > 5000, tf = false; return; end
fracInt = mean(abs(V-round(V)) < 1e-6);
tf = fracInt > 0.95;
end

function R = localSigned2D(R)
R = round(double(R));
mid = floor(size(R,2)/2);
R2 = R;
R2(:,1:mid) = -abs(R2(:,1:mid));
if mid < size(R,2), R2(:,mid+1:end) = abs(R2(:,mid+1:end)); end
R2(R == 0) = 0;
R = R2;
end

function V = localFitVolume(V0,Y,X,Z)
V = [];
try
    V0 = squeeze(double(V0));
    if ndims(V0) == 2
        A = localResize2D(V0,Y,X);
        V = repmat(A,[1 1 Z]);
    elseif ndims(V0) == 3
        if size(V0,3) == Z
            V = zeros(Y,X,Z);
            for z = 1:Z, V(:,:,z) = localResize2D(V0(:,:,z),Y,X); end
        else
            idx = round(linspace(1,size(V0,3),Z));
            idx = max(1,min(size(V0,3),idx));
            V = zeros(Y,X,Z);
            for z = 1:Z, V(:,:,z) = localResize2D(V0(:,:,idx(z)),Y,X); end
        end
    end
catch
    V = [];
end
end

function B = localResize2D(A,Y,X)
A = squeeze(double(A));
if isequal(size(A),[Y X]), B = A; return; end
try
    if exist('imresize','file') == 2
        B = imresize(A,[Y X],'nearest');
    else
        yy = round(linspace(1,size(A,1),Y));
        xx = round(linspace(1,size(A,2),X));
        B = A(yy,xx);
    end
catch
    yy = round(linspace(1,size(A,1),Y));
    xx = round(linspace(1,size(A,2),X));
    B = A(yy,xx);
end
B = round(double(B));
end

function T = localReadRegionNames(f)
T = struct('labels',[] ,'names',{{}});
if isempty(f) || exist(f,'file') ~= 2, return; end
ext = localExt(f);
if strcmp(ext,'.mat')
    try
        S = load(f);
        T = localNamesFromMatStruct(S);
    catch
    end
    return;
end
fid = fopen(f,'r');
if fid < 0, return; end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
labs = []; names = {};
while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line), continue; end
    line = strtrim(line);
    if isempty(line) || line(1)=='#' || line(1)=='%', continue; end
    line = strrep(line,char(9),',');
    line = strrep(line,';',',');
    parts = regexp(line,',','split');
    if numel(parts) < 2, parts = regexp(line,'\s+','split'); end
    if numel(parts) < 2, continue; end
    lab = str2double(strtrim(parts{1}));
    if ~isfinite(lab), continue; end
    acr = strtrim(parts{2});
    nm = acr;
    if numel(parts) >= 3
        fullName = strtrim(parts{3});
        if ~isempty(fullName) && ~strcmpi(fullName,acr) && ~all(isstrprop(fullName,'digit'))
            nm = [acr ' - ' fullName];
        end
    end
    labs(end+1,1) = lab; %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
end
T.labels = labs; T.names = names;
end

function T = localNamesFromMatStruct(S)
T = struct('labels',[] ,'names',{{}});
try
    if isfield(S,'Seg') && isstruct(S.Seg) && isfield(S.Seg,'region')
        T = localNamesFromRegion(S.Seg.region); if ~isempty(T.labels), return; end
    end
    if isfield(S,'region') && isstruct(S.region)
        T = localNamesFromRegion(S.region); if ~isempty(T.labels), return; end
    end
    if isfield(S,'roiNameTable') && isstruct(S.roiNameTable)
        x = S.roiNameTable;
        if isfield(x,'labels') && isfield(x,'names')
            T.labels = double(x.labels(:)); T.names = cellstr(x.names(:)); return;
        end
    end
    if isfield(S,'labels') && isfield(S,'names')
        T.labels = double(S.labels(:)); T.names = cellstr(S.names(:)); return;
    end
    if isfield(S,'atlasInfoRegions')
        T = localNamesFromInfoRegions(S.atlasInfoRegions); if ~isempty(T.labels), return; end
    end
    if isfield(S,'atlas') && isstruct(S.atlas) && isfield(S.atlas,'infoRegions')
        T = localNamesFromInfoRegions(S.atlas.infoRegions); if ~isempty(T.labels), return; end
    end
catch
    T = struct('labels',[] ,'names',{{}});
end
end

function T = localNamesFromRegion(r)
T = struct('labels',[] ,'names',{{}});
if ~isstruct(r), return; end
if isfield(r,'labels'), T.labels = double(r.labels(:)); else, return; end
acr = {}; nam = {};
if isfield(r,'acronyms') && ~isempty(r.acronyms), acr = cellstr(r.acronyms(:)); end
if isfield(r,'names') && ~isempty(r.names), nam = cellstr(r.names(:)); end
n = numel(T.labels); T.names = cell(n,1);
for i = 1:n
    a = ''; b = '';
    if i <= numel(acr), a = strtrim(acr{i}); end
    if i <= numel(nam), b = strtrim(nam{i}); end
    if isempty(a), a = sprintf('REG%d',T.labels(i)); end
    if isempty(b) || strcmpi(a,b), T.names{i} = a; else, T.names{i} = [a ' - ' b]; end
end
end

function T = localNamesFromInfoRegions(info)
T = struct('labels',[] ,'names',{{}});
try
    if isstruct(info) && numel(info) > 1
        n = numel(info); T.labels = zeros(n,1); T.names = cell(n,1);
        for i = 1:n
            if isfield(info,'id'), T.labels(i) = double(info(i).id); elseif isfield(info,'label'), T.labels(i)=double(info(i).label); else, T.labels(i)=i; end
            a=''; b='';
            if isfield(info,'acr'), a=char(info(i).acr); elseif isfield(info,'acronym'), a=char(info(i).acronym); end
            if isfield(info,'name'), b=char(info(i).name); end
            if isempty(a), a=sprintf('REG%d',T.labels(i)); end
            if isempty(b) || strcmpi(a,b), T.names{i}=a; else, T.names{i}=[a ' - ' b]; end
        end
    end
catch
    T = struct('labels',[] ,'names',{{}});
end
end

function T = localMergeNames(A,B)
T = A;
for i = 1:numel(B.labels)
    lab = double(B.labels(i));
    nm = B.names{i};
    if isempty(T.labels) || ~any(double(T.labels(:)) == lab)
        T.labels(end+1,1) = lab; %#ok<AGROW>
        T.names{end+1,1} = nm; %#ok<AGROW>
    end
end
end

function idx = localIndexFromName(f)
s = lower(localShort(f));
idx = NaN;
tok = regexp(s,'source[_\-\s]*0*([0-9]+)','tokens','once');
if isempty(tok), tok = regexp(s,'slice[_\-\s]*0*([0-9]+)','tokens','once'); end
if isempty(tok), tok = regexp(s,'z[_\-\s]*0*([0-9]+)','tokens','once'); end
if ~isempty(tok), idx = str2double(tok{1}); end
end

function ord = localFileOrder(files)
ord = zeros(numel(files),1);
for i = 1:numel(files), ord(i) = localMTime(files{i}); end
end

function dn = localMTime(f)
dn = 0; try, d = dir(f); if ~isempty(d), dn = d(1).datenum; end, catch, end
end

function ext = localExt(f)
if numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz'), ext = '.nii.gz'; else, [~,~,ext] = fileparts(f); ext = lower(ext); end
end

function nm = localShort(f)
[~,a,b] = fileparts(f);
if strcmpi(b,'.gz'), [~,a2,b2] = fileparts(a); nm=[a2 b2 b]; else, nm=[a b]; end
end

function nm = localShort2(f)
if isempty(f), nm = 'none'; else, nm = localShort(f); end
end

function s = localYesNo(tf)
if tf, s = 'yes'; else, s = 'no'; end
end
