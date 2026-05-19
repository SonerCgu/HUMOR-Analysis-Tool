function T = HUMOR_read_region_names_file(fullFile)
T = struct('labels',[],'names',{{}});
if nargin < 1 || isempty(fullFile) || exist(fullFile,'file') ~= 2, return; end
[~,~,ext] = fileparts(fullFile); ext = lower(ext);
if strcmpi(ext,'.mat')
    S = load(fullFile);
    try
        if isfield(S,'Seg') && isstruct(S.Seg) && isfield(S.Seg,'region')
            T = localRegion(S.Seg.region); if ~isempty(T.labels), return; end
        end
        if isfield(S,'region') && isstruct(S.region)
            T = localRegion(S.region); if ~isempty(T.labels), return; end
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
    catch
    end
    return;
end
fid = fopen(fullFile,'r'); if fid < 0, return; end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
labels = []; names = {};
while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line), continue; end
    line = strtrim(line);
    if isempty(line) || line(1)=='#' || line(1)=='%', continue; end
    line = strrep(line,char(9),','); line = strrep(line,';',',');
    parts = regexp(line,',','split');
    if numel(parts) < 2, parts = regexp(line,'\s+','split'); end
    if numel(parts) < 2, continue; end
    lab = str2double(strtrim(parts{1}));
    if ~isfinite(lab), continue; end
    nm = strtrim(parts{2});
    if numel(parts) > 2
        for k = 3:numel(parts)
            pk = strtrim(parts{k});
            if ~isempty(pk), nm = [nm ' ' pk]; end %#ok<AGROW>
        end
    end
    labels(end+1,1) = lab; %#ok<AGROW>
    names{end+1,1} = nm; %#ok<AGROW>
end
T.labels = labels; T.names = names;
end

function T = localRegion(r)
T = struct('labels',[],'names',{{}});
if isfield(r,'labels'), T.labels = double(r.labels(:)); end
if isfield(r,'names') && ~isempty(r.names)
    T.names = cellstr(r.names(:));
elseif isfield(r,'acronyms') && ~isempty(r.acronyms)
    T.names = cellstr(r.acronyms(:));
end
if ~isempty(T.labels) && ~isempty(T.names)
    n = min(numel(T.labels),numel(T.names));
    T.labels = T.labels(1:n); T.names = T.names(1:n);
else
    T = struct('labels',[],'names',{{}});
end
end
