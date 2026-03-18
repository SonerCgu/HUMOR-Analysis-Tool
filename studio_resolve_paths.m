function P = studio_resolve_paths(par, fileLabel, exportRootOverride)

if nargin < 3
    exportRootOverride = '';
end
if nargin < 2 || isempty(fileLabel)
    fileLabel = 'dataset';
end

base = '';

if ~isempty(exportRootOverride) && exist(exportRootOverride,'dir') == 7
    base = char(exportRootOverride);

elseif isstruct(par)
    if isfield(par,'exportPath') && ~isempty(par.exportPath) && exist(par.exportPath,'dir') == 7
        base = char(par.exportPath);

    elseif isfield(par,'loadedPath') && ~isempty(par.loadedPath) && exist(par.loadedPath,'dir') == 7
        base = char(par.loadedPath);

    elseif isfield(par,'loadedFile') && ~isempty(par.loadedFile)
        lf = char(par.loadedFile);
        if exist(lf,'file') == 2
            base = fileparts(lf);
        end
    end
end

if isempty(base)
    base = pwd;
end

if contains(base, [filesep 'RawData' filesep])
    analysedRoot = strrep(base, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
elseif contains(base, 'RawData')
    analysedRoot = strrep(base, 'RawData', 'AnalysedData');
else
    analysedRoot = base;
end

datasetType = studio_clean_name(local_dataset_type(par, fileLabel));
datasetTag  = studio_clean_name(local_dataset_tag(par, fileLabel));
datasetTag  = strip_leading_type(datasetTag, datasetType);

P = struct();
P.root = analysedRoot;
P.datasetType = datasetType;
P.datasetTag  = datasetTag;

P.roiDir        = fullfile(analysedRoot, 'ROI', datasetType, datasetTag);
P.scmDir        = fullfile(analysedRoot, 'SCM', datasetType, datasetTag);
P.scmImageDir   = fullfile(P.scmDir, 'Images');
P.scmSeriesDir  = fullfile(P.scmDir, 'Series');
P.scmTcDir      = fullfile(P.scmDir, 'TimeCoursePNG');

P.preprocRoot   = fullfile(analysedRoot, 'Preprocessing');
P.qcGabrielDir  = fullfile(P.preprocRoot, 'QC_gabriel');
P.qcDespikeDir  = fullfile(P.preprocRoot, 'QC_despike');
P.qcFilterDir   = fullfile(P.preprocRoot, 'QC_filtering');
P.qcScrubDir    = fullfile(P.preprocRoot, 'QC_scrubbing');

P.groupDir      = fullfile(analysedRoot, 'GroupAnalysis');
P.reg2dDir      = fullfile(analysedRoot, 'Registration2D');

if isempty(datasetTag)
    P.fileStem = datasetType;
else
    P.fileStem = [datasetType '_' datasetTag];
end

end

function s = local_dataset_type(par, fileLabel)
s = '';

if isstruct(par)
    if isfield(par,'activeDataset') && ~isempty(par.activeDataset)
        s = char(par.activeDataset);
    end
    if isempty(s) && isfield(par,'loadedName') && ~isempty(par.loadedName)
        s = char(par.loadedName);
    end
    if isempty(s) && isfield(par,'loadedFile') && ~isempty(par.loadedFile)
        s = char(par.loadedFile);
    end
end

if isempty(s)
    s = char(fileLabel);
end

s = lower(strtrim(s));

if contains(s,'gabriel')
    s = 'gabriel';

elseif ~isempty(regexp(s,'(^|[_\-\s])raw([_\-\s]|$)','once'))
    s = 'raw';

else
    tok = regexp(s,'^[a-z0-9]+','match','once');
    if isempty(tok)
        tok = 'dataset';
    end
    s = tok;
end
end

function s = local_dataset_tag(par, fileLabel)
s = '';

if isstruct(par)
    if isfield(par,'loadedFile') && ~isempty(par.loadedFile)
        s = char(par.loadedFile);
    end
    if isempty(s) && isfield(par,'loadedName') && ~isempty(par.loadedName)
        s = char(par.loadedName);
    end
    if isempty(s) && isfield(par,'activeDataset') && ~isempty(par.activeDataset)
        s = char(par.activeDataset);
    end
end

if isempty(s)
    s = char(fileLabel);
end

s = regexprep(s,'\|.*$','');
s = regexprep(s,'\(.*$','');
s = regexprep(s,'\.nii(\.gz)?$','','ignorecase');
s = regexprep(s,'\.mat$','','ignorecase');

[~,s] = fileparts(s);
s = studio_clean_name(s);
end

function s = strip_leading_type(tag, dtype)
s = tag;
if isempty(tag) || isempty(dtype)
    return;
end

a = lower(tag);
t = lower(dtype);

if startsWith(a, [t '_'])
    s = tag(numel(t)+2:end);
elseif startsWith(a, [t '-'])
    s = tag(numel(t)+2:end);
elseif startsWith(a, [t ' '])
    s = tag(numel(t)+2:end);
end

s = strtrim(s);
end

function s = studio_clean_name(s)
if isstring(s)
    s = char(s);
end

s = char(s);
s = strrep(s, '/', '_');
s = strrep(s, '\', '_');
s = regexprep(s,'[^\w\-]+','_');
s = regexprep(s,'_+','_');
s = regexprep(s,'^_+','');
s = regexprep(s,'_+$','');

if isempty(s)
    s = 'item';
end
end