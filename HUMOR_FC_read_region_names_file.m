function T = HUMOR_FC_read_region_names_file(fullFile)
% Robust FC region-name reader.
% Supports files like AtlasRegions_slice111.txt, CSV/TSV, MAT, Segmentation_*.mat.

T = struct('labels',[] ,'names',{{}});

if nargin < 1 || isempty(fullFile) || exist(fullFile,'file') ~= 2
    return;
end

[~,~,ext] = fileparts(fullFile);
ext = lower(ext);

if strcmp(ext,'.mat')
    try
        S = load(fullFile);
        T = localFromMat(S);
        T = localUnique(T);
    catch
        T = struct('labels',[] ,'names',{{}});
    end
    return;
end

fid = fopen(fullFile,'r');
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

labels = [];
names = {};

while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line), continue; end
    line = strtrim(line);
    if isempty(line), continue; end
    if line(1)=='#' || line(1)=='%', continue; end

    line = strrep(line,char(9),',');
    line = strrep(line,';',',');
    line = strrep(line,'|',',');

    parts = regexp(line,',','split');
    if numel(parts) < 2
        parts = regexp(line,'\s+','split');
    end
    if numel(parts) < 2, continue; end

    lab = NaN;
    labPos = NaN;

    % Accept either: label,name OR acronym,label,name OR id,acronym,name
    for k = 1:min(5,numel(parts))
        v = str2double(strtrim(parts{k}));
        if isfinite(v)
            lab = v;
            labPos = k;
            break;
        end
    end

    if ~isfinite(lab), continue; end

    nameParts = parts;
    nameParts(labPos) = [];
    nm = '';
    for k = 1:numel(nameParts)
        pk = strtrim(nameParts{k});
        if isempty(pk), continue; end
        if strcmpi(pk,'id') || strcmpi(pk,'label') || strcmpi(pk,'name') || strcmpi(pk,'acronym')
            continue;
        end
        if isempty(nm)
            nm = pk;
        else
            nm = [nm ' - ' pk]; %#ok<AGROW>
        end
    end

    if isempty(nm)
        nm = sprintf('REG%d',round(lab));
    end

    labels(end+1,1) = lab; %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
end

T.labels = labels;
T.names = names;
T = localUnique(T);
end

function T = localFromMat(S)
T = struct('labels',[] ,'names',{{}});

try
    if isfield(S,'Seg') && isstruct(S.Seg) && isfield(S.Seg,'region')
        T = localFromRegion(S.Seg.region);
        if ~isempty(T.labels), return; end
    end

    if isfield(S,'region') && isstruct(S.region)
        T = localFromRegion(S.region);
        if ~isempty(T.labels), return; end
    end

    if isfield(S,'roiNameTable') && isstruct(S.roiNameTable)
        x = S.roiNameTable;
        if isfield(x,'labels') && isfield(x,'names')
            T.labels = double(x.labels(:));
            T.names = cellstr(x.names(:));
            return;
        end
    end

    if isfield(S,'labels') && isfield(S,'names')
        T.labels = double(S.labels(:));
        T.names = cellstr(S.names(:));
        return;
    end

    if isfield(S,'atlasInfoRegions')
        T = localFromInfoRegions(S.atlasInfoRegions);
        if ~isempty(T.labels), return; end
    end

    if isfield(S,'atlas') && isstruct(S.atlas) && isfield(S.atlas,'infoRegions')
        T = localFromInfoRegions(S.atlas.infoRegions);
        if ~isempty(T.labels), return; end
    end

    fns = fieldnames(S);
    for i = 1:numel(fns)
        x = S.(fns{i});
        if isstruct(x) && numel(x) > 1
            T = localFromInfoRegions(x);
            if ~isempty(T.labels), return; end
        end
    end
catch
    T = struct('labels',[] ,'names',{{}});
end
end

function T = localFromRegion(r)
T = struct('labels',[] ,'names',{{}});
try
    if ~isstruct(r) || ~isfield(r,'labels'), return; end
    labs = double(r.labels(:));
    n = numel(labs);

    acr = cell(n,1);
    nam = cell(n,1);

    if isfield(r,'acronyms') && ~isempty(r.acronyms)
        a0 = cellstr(r.acronyms(:));
        acr(1:min(n,numel(a0))) = a0(1:min(n,numel(a0)));
    end

    if isfield(r,'names') && ~isempty(r.names)
        n0 = cellstr(r.names(:));
        nam(1:min(n,numel(n0))) = n0(1:min(n,numel(n0)));
    end

    outNames = cell(n,1);
    for k = 1:n
        a = strtrim(char(acr{k}));
        b = strtrim(char(nam{k}));
        if isempty(a), a = sprintf('REG%d',round(labs(k))); end
        if isempty(b) || strcmpi(a,b)
            outNames{k} = a;
        else
            outNames{k} = [a ' - ' b];
        end
    end

    T.labels = labs;
    T.names = outNames;
catch
    T = struct('labels',[] ,'names',{{}});
end
end

function T = localFromInfoRegions(info)
T = struct('labels',[] ,'names',{{}});
try
    if ~isstruct(info) || numel(info) < 1, return; end

    f = fieldnames(info);
    idField = '';
    acrField = '';
    nameField = '';

    if any(strcmpi(f,'id')), idField = 'id'; end
    if any(strcmpi(f,'label')), idField = 'label'; end
    if any(strcmpi(f,'structure_id')), idField = 'structure_id'; end
    if any(strcmpi(f,'acr')), acrField = 'acr'; end
    if any(strcmpi(f,'acronym')), acrField = 'acronym'; end
    if any(strcmpi(f,'name')), nameField = 'name'; end

    if isempty(idField), return; end

    n = numel(info);
    labs = zeros(n,1);
    names = cell(n,1);

    for k = 1:n
        labs(k) = double(info(k).(idField));
        a = '';
        b = '';
        if ~isempty(acrField), a = char(info(k).(acrField)); end
        if ~isempty(nameField), b = char(info(k).(nameField)); end
        if isempty(a), a = sprintf('REG%d',round(labs(k))); end
        if isempty(b) || strcmpi(a,b)
            names{k} = a;
        else
            names{k} = [a ' - ' b];
        end
    end

    T.labels = labs;
    T.names = names;
catch
    T = struct('labels',[] ,'names',{{}});
end
end

function T = localUnique(T)
try
    if isempty(T.labels), return; end
    labs = double(T.labels(:));
    names = cellstr(T.names(:));
    [labsU,ia] = unique(labs,'stable');
    T.labels = labsU;
    T.names = names(ia);
catch
end
end
