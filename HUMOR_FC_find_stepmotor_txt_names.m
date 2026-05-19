function out = HUMOR_FC_find_stepmotor_txt_names(folder)
% Recursively finds AtlasRegions_slice*.txt and other region-name files.

out = struct();
out.folder = folder;
out.names = struct('labels',[] ,'names',{{}});
out.files = {};
out.bestFile = '';
out.summary = '';

if nargin < 1 || isempty(folder) || exist(folder,'dir') ~= 7
    return;
end

files = localFiles(folder);

% Prefer AtlasRegions_slice*.txt, then region/label/name files.
cand = {};
score = [];

for i = 1:numel(files)
    f = files{i};
    ext = localExt(f);
    if ~(strcmp(ext,'.txt') || strcmp(ext,'.csv') || strcmp(ext,'.tsv') || strcmp(ext,'.mat'))
        continue;
    end

    nm = lower(localShort(f));
    sc = 0;

    if ~isempty(strfind(nm,'atlasregions_slice')), sc = sc + 1000; end
    if ~isempty(strfind(nm,'atlasregions')), sc = sc + 900; end
    if ~isempty(strfind(nm,'atlas_regions')), sc = sc + 850; end
    if ~isempty(strfind(nm,'regiontable')), sc = sc + 800; end
    if ~isempty(strfind(nm,'region_table')), sc = sc + 800; end
    if ~isempty(strfind(nm,'regionnames')), sc = sc + 700; end
    if ~isempty(strfind(nm,'region_names')), sc = sc + 700; end
    if ~isempty(strfind(nm,'roinames')), sc = sc + 650; end
    if ~isempty(strfind(nm,'roi_names')), sc = sc + 650; end
    if ~isempty(strfind(nm,'labels')), sc = sc + 300; end
    if ~isempty(strfind(nm,'names')), sc = sc + 300; end
    if ~isempty(strfind(nm,'inforegions')), sc = sc + 600; end
    if ~isempty(strfind(nm,'segmentation_')), sc = sc + 500; end

    if ~isempty(strfind(nm,'functionalconnectivity')), sc = sc - 1000; end
    if ~isempty(strfind(nm,'fc_groupbundle')), sc = sc - 1000; end

    if sc > 0
        T = HUMOR_FC_read_region_names_file(f);
        if ~isempty(T.labels)
            cand{end+1} = f; %#ok<AGROW>
            score(end+1) = sc + numel(T.labels); %#ok<AGROW>
        end
    end
end

if isempty(cand)
    out.summary = sprintf('No readable TXT/CSV/MAT region-name files found recursively under: %s',folder);
    return;
end

[~,ord] = sort(score,'descend');
cand = cand(ord);

Tall = struct('labels',[] ,'names',{{}});
for i = 1:numel(cand)
    T = HUMOR_FC_read_region_names_file(cand{i});
    Tall = localMerge(Tall,T);
end

out.names = Tall;
out.files = cand;
out.bestFile = cand{1};
out.summary = sprintf('Loaded %d unique labels from %d recursive file(s). Best: %s', ...
    numel(out.names.labels), numel(out.files), localShort(out.bestFile));
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
for i = 1:numel(B.labels)
    lab = double(B.labels(i));
    nm = B.names{i};
    if isempty(T.labels) || ~any(double(T.labels(:)) == lab)
        T.labels(end+1,1) = lab; %#ok<AGROW>
        T.names{end+1,1} = nm; %#ok<AGROW>
    end
end
end

function ext = localExt(f)
[~,~,ext] = fileparts(f);
ext = lower(ext);
end

function nm = localShort(f)
[~,a,b] = fileparts(f);
nm = [a b];
end
