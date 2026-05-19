function out = HUMOR_FC_stepmotor_read_folder(folder,Y,X,Z,preferredNameFile)
% Recursively finds step-motor region TXT/CSV/MAT names and per-slice atlas labels.

if nargin < 5, preferredNameFile = ''; end
out = struct();
out.folder = folder;
out.names = struct('labels',[] ,'names',{{}});
out.nameFiles = {};
out.atlas = [];
out.labelFiles = {};
out.segmentationFile = '';
out.summary = '';

if nargin < 4 || isempty(folder) || exist(folder,'dir') ~= 7
    return;
end

files = localFiles(folder);

% Latest Segmentation file, if available.
segFiles = {}; segTime = [];
for i = 1:numel(files)
    nm = lower(localShort(files{i}));
    if ~isempty(strfind(nm,'segmentation_')) && ~isempty(strfind(nm,'.mat')) && isempty(strfind(nm,'heatmap'))
        segFiles{end+1} = files{i}; %#ok<AGROW>
        segTime(end+1) = localMTime(files{i}); %#ok<AGROW>
    end
end
if ~isempty(segFiles)
    [~,ix] = max(segTime);
    out.segmentationFile = segFiles{ix};
end

% Names: preferred TXT/MAT first, then every name-like file in all subfolders.
if ~isempty(preferredNameFile) && exist(preferredNameFile,'file') == 2
    T = HUMOR_FC_read_region_names_file(preferredNameFile);
    if ~isempty(T.labels)
        out.names = localMerge(out.names,T);
        out.nameFiles{end+1} = preferredNameFile;
    end
end

for i = 1:numel(files)
    f = files{i};
    if strcmp(f,preferredNameFile), continue; end
    ext = localExt(f);
    if ~(strcmp(ext,'.txt') || strcmp(ext,'.csv') || strcmp(ext,'.tsv') || strcmp(ext,'.mat'))
        continue;
    end
    nm = lower(localShort(f));
    score = 0;
    keys = {'segmentation_','regiontable','region_table','regionnames','region_names','roi_names','roinames','inforegions','atlasregions','atlas_regions','labels','names','acr','acronym'};
    for kk = 1:numel(keys)
        if ~isempty(strfind(nm,keys{kk})), score = score + 1; end
    end
    if score <= 0, continue; end
    T = HUMOR_FC_read_region_names_file(f);
    if ~isempty(T.labels)
        out.names = localMerge(out.names,T);
        out.nameFiles{end+1} = f; %#ok<AGROW>
    end
end

% Atlas from Segmentation first.
if ~isempty(out.segmentationFile)
    try
        S = load(out.segmentationFile);
        if isfield(S,'Seg'), Seg = S.Seg; else, Seg = S; end
        if isfield(Seg,'labelMap') && isnumeric(Seg.labelMap)
            out.atlas = localFitVolume(Seg.labelMap,Y,X,Z);
        elseif isfield(Seg,'R') && isnumeric(Seg.R)
            out.atlas = localFitVolume(Seg.R,Y,X,Z);
        end
    catch
    end
end

% Atlas from Reg2D / AtlasUnderlay region MAT files in subfolders.
if isempty(out.atlas)
    maps = {}; idx = []; labelFiles = {};
    for i = 1:numel(files)
        f = files{i};
        if ~strcmp(localExt(f),'.mat'), continue; end
        nm = lower(localShort(f));
        score = 0;
        if ~isempty(strfind(nm,'atlasunderlay_regions')), score = score + 10; end
        if ~isempty(strfind(nm,'coronalregistration2d')), score = score + 8; end
        if ~isempty(strfind(nm,'stepmotor_reg2d')) || ~isempty(strfind(nm,'step_motor_reg2d')), score = score + 8; end
        if ~isempty(strfind(nm,'regionlabels')), score = score + 6; end
        if ~isempty(strfind(nm,'labelmap')), score = score + 6; end
        if score <= 0, continue; end
        [R,ok] = localReadLabelMap(f);
        if ok && ~isempty(R)
            if ndims(R) == 3
                out.atlas = localFitVolume(R,Y,X,Z);
                labelFiles{end+1} = f; %#ok<AGROW>
                break;
            else
                maps{end+1} = localResize2D(R,Y,X); %#ok<AGROW>
                idx(end+1) = localIndex(f); %#ok<AGROW>
                labelFiles{end+1} = f; %#ok<AGROW>
            end
        end
    end
    if isempty(out.atlas) && ~isempty(maps)
        if all(isfinite(idx))
            [~,ord] = sort(idx);
        else
            ord = 1:numel(maps);
        end
        maps = maps(ord);
        labelFiles = labelFiles(ord);
        out.atlas = zeros(Y,X,Z);
        useIdx = round(linspace(1,numel(maps),Z));
        useIdx = max(1,min(numel(maps),useIdx));
        for z = 1:Z
            out.atlas(:,:,z) = maps{useIdx(z)};
        end
    end
    out.labelFiles = labelFiles;
end

if ~isempty(out.atlas)
    out.atlas = round(double(out.atlas));
end

out.summary = sprintf('names=%d labels from %d files | atlas=%s from %d files | seg=%s', ...
    numel(out.names.labels), numel(out.nameFiles), localYesNo(~isempty(out.atlas)), numel(out.labelFiles), localShort2(out.segmentationFile));
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

function T = localMerge(A,B)
T = A;
if isempty(B.labels), return; end
for k = 1:numel(B.labels)
    lab = double(B.labels(k));
    nm = B.names{k};
    if isempty(T.labels) || ~any(double(T.labels(:)) == lab)
        T.labels(end+1,1) = lab; %#ok<AGROW>
        T.names{end+1,1} = nm; %#ok<AGROW>
    end
end
end

function [R,ok] = localReadLabelMap(f)
R = []; ok = false;
try
    S = load(f);
    pref = {'atlasRegionLabelsLR2D','atlasRegionLabels2D','regionLabelsLR','regionLabels','labelMap','roiAtlas','annotation','regions','registeredLabels','warpedLabels','atlasLabels'};
    for k = 1:numel(pref)
        fn = pref{k};
        if isfield(S,fn) && isnumeric(S.(fn))
            V = squeeze(double(S.(fn)));
            if ndims(V) == 2 || ndims(V) == 3
                if localLooksLabel(V)
                    R = V; ok = true; return;
                end
            end
        end
    end
    if isfield(S,'Reg2D') && isstruct(S.Reg2D)
        if isfield(S.Reg2D,'regionsImage') && isnumeric(S.Reg2D.regionsImage)
            R = squeeze(double(S.Reg2D.regionsImage)); ok = true; return;
        end
        if isfield(S.Reg2D,'atlasRegionLabels2D') && isnumeric(S.Reg2D.atlasRegionLabels2D)
            R = squeeze(double(S.Reg2D.atlasRegionLabels2D)); ok = true; return;
        end
    end
catch
end
end

function tf = localLooksLabel(V)
V = double(V(:));
V = V(isfinite(V));
if isempty(V), tf = false; return; end
u = unique(round(V));
tf = numel(u) >= 2 && numel(u) <= 10000 && mean(abs(V-round(V)) < 1e-6) > 0.95;
end

function V = localFitVolume(V0,Y,X,Z)
V = [];
try
    V0 = squeeze(double(V0));
    if ndims(V0) == 2
        A = localResize2D(V0,Y,X);
        V = repmat(A,[1 1 Z]);
    elseif ndims(V0) == 3
        V = zeros(Y,X,Z);
        useIdx = round(linspace(1,size(V0,3),Z));
        useIdx = max(1,min(size(V0,3),useIdx));
        for z = 1:Z
            V(:,:,z) = localResize2D(V0(:,:,useIdx(z)),Y,X);
        end
    end
catch
    V = [];
end
end

function B = localResize2D(A,Y,X)
A = squeeze(double(A));
if isequal(size(A),[Y X]), B = round(A); return; end
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

function idx = localIndex(f)
s = lower(localShort(f)); idx = NaN;
tok = regexp(s,'source[_\-\s]*0*([0-9]+)','tokens','once');
if isempty(tok), tok = regexp(s,'slice[_\-\s]*0*([0-9]+)','tokens','once'); end
if isempty(tok), tok = regexp(s,'z[_\-\s]*0*([0-9]+)','tokens','once'); end
if ~isempty(tok), idx = str2double(tok{1}); end
end

function dn = localMTime(f)
dn = 0; try, d = dir(f); if ~isempty(d), dn = d(1).datenum; end, catch, end
end

function ext = localExt(f)
if numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz'), ext = '.nii.gz'; else, [~,~,ext] = fileparts(f); ext = lower(ext); end
end

function nm = localShort(f)
[~,a,b] = fileparts(f);
if strcmpi(b,'.gz'), [~,a2,b2] = fileparts(a); nm = [a2 b2 b]; else, nm = [a b]; end
end

function nm = localShort2(f)
if isempty(f), nm = 'none'; else, nm = localShort(f); end
end

function s = localYesNo(tf)
if tf, s = 'yes'; else, s = 'no'; end
end
