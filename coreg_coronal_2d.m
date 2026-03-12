function Reg2D = coreg_coronal_2d(studio)
% coreg_coronal_2d.m
%
% Simple manual 2D coronal registration to atlas
%
% Uses:
%   - source image for manual alignment (e.g. brainImage from mask editor)
%   - actual functional dataset from Studio or file candidates for warp/export
%
% Exports (via registration_coronal_2d.m):
%   Registration2D/CoronalRegistration2D.mat
%   Registration2D/atlasUnderlay_<mode>_sliceXXX.mat
%   Registration2D/warpedData_<dataset>_toAtlas2D_<timestamp>.mat
%
% ASCII only
% MATLAB 2017b compatible

fprintf('\n--- Simple 2D Coronal Atlas Registration ---\n');

Reg2D = [];

%% ---------------------------------------------------------
% 0) CHECK
%% ---------------------------------------------------------
if nargin < 1 || isempty(studio) || ~isfield(studio,'isLoaded') || ~studio.isLoaded
    error('Load dataset first.');
end

if ~isfield(studio,'loadedPath') || isempty(studio.loadedPath) || ~exist(studio.loadedPath,'dir')
    error('studio.loadedPath is missing or invalid.');
end

rawFolder = studio.loadedPath;

%% ---------------------------------------------------------
% 1) LOAD ATLAS
%% ---------------------------------------------------------
atlasFile = 'allen_brain_atlas.mat';

atlasPath = which(atlasFile);
if isempty(atlasPath)
    here = fileparts(mfilename('fullpath'));
    cand = fullfile(here, atlasFile);
    if exist(cand,'file')
        atlasPath = cand;
    end
end

if isempty(atlasPath) || ~exist(atlasPath,'file')
    error('allen_brain_atlas.mat not found on path or next to coreg_coronal_2d.m.');
end

SAtlas = load(atlasPath,'atlas');
if ~isfield(SAtlas,'atlas')
    error('Loaded allen_brain_atlas.mat but variable "atlas" is missing.');
end
atlas = SAtlas.atlas;

%% ---------------------------------------------------------
% 2) ANALYSED + REGISTRATION2D FOLDER
%% ---------------------------------------------------------
analysedFolder = '';

if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
    analysedFolder = studio.exportPath;
end

if isempty(analysedFolder)
    analysedFolder = inferAnalysedFromRaw(rawFolder);
end

if isempty(analysedFolder)
    analysedFolder = rawFolder;
end

registrationDir = fullfile(analysedFolder,'Registration2D');
if ~exist(registrationDir,'dir')
    mkdir(registrationDir);
end

fprintf('RAW folder         : %s\n', rawFolder);
fprintf('ANALYSED folder    : %s\n', analysedFolder);
fprintf('Registration2D dir : %s\n', registrationDir);

%% ---------------------------------------------------------
% 3) SOURCE IMAGE CANDIDATES
%% ---------------------------------------------------------
searchFolders = { ...
    fullfile(rawFolder,'Visualization'), ...
    fullfile(rawFolder,'visualization'), ...
    fullfile(rawFolder,'Visualisation'), ...
    fullfile(rawFolder,'Mask'), ...
    fullfile(rawFolder,'Masks'), ...
    fullfile(analysedFolder,'Visualization'), ...
    fullfile(analysedFolder,'visualization'), ...
    fullfile(analysedFolder,'Visualisation'), ...
    fullfile(analysedFolder,'Mask'), ...
    fullfile(analysedFolder,'Masks'), ...
    registrationDir ...
    };

searchFolders = searchFolders(~cellfun(@isempty, searchFolders));
searchFolders = searchFolders(cellfun(@(p) exist(p,'dir')==7, searchFolders));
searchFolders = unique(searchFolders,'stable');

[sourceFiles, sourceLabels] = collectSourceFiles(searchFolders, rawFolder, analysedFolder, registrationDir);

if isempty(sourceFiles)
    error('No suitable source files found.');
end

[idx, tf] = listdlg( ...
    'PromptString','Select coronal source image (brainImage, mask image, MAT, NIfTI, image file):', ...
    'SelectionMode','single', ...
    'ListString',sourceLabels, ...
    'ListSize',[860 420]);

if ~tf
    fprintf('2D coronal registration cancelled.\n');
    return;
end

sourceFile = sourceFiles{idx};

%% ---------------------------------------------------------
% 4) LOAD SOURCE IMAGE + OPTIONAL MASK
%% ---------------------------------------------------------
[source2D, sourceInfo] = loadSourceAs2D(sourceFile);

fprintf('Source file  : %s\n', sourceFile);
fprintf('Source label : %s\n', sourceInfo.label);
fprintf('Source size  : %s\n', mat2str(size(source2D)));

if isfield(sourceInfo,'mask2D') && ~isempty(sourceInfo.mask2D)
    fprintf('Source mask  : attached [%s]\n', mat2str(size(sourceInfo.mask2D)));
end

%% ---------------------------------------------------------
% 5) BUILD FUNCTIONAL CANDIDATES
%% ---------------------------------------------------------
funcCandidates = buildFunctionalCandidates(studio, rawFolder, analysedFolder, registrationDir, sourceFile);
fprintf('Functional candidates found: %d\n', numel(funcCandidates.items));

%% ---------------------------------------------------------
% 6) OPTIONAL LOAD PREVIOUS Reg2D
%% ---------------------------------------------------------
prevFile = fullfile(registrationDir,'CoronalRegistration2D.mat');
initialReg = [];

if exist(prevFile,'file')
    choice = questdlg( ...
        sprintf('Load previous CoronalRegistration2D.mat from:\n%s', registrationDir), ...
        'Previous 2D Registration', ...
        'Yes','No','No');

    if strcmp(choice,'Yes')
        tmp = load(prevFile,'Reg2D');
        if isfield(tmp,'Reg2D')
            initialReg = tmp.Reg2D;
        end
    end
end

%% ---------------------------------------------------------
% 7) LAUNCH GUI
%% ---------------------------------------------------------
Reg2D = registration_coronal_2d(atlas, source2D, sourceInfo, initialReg, ...
    registrationDir, funcCandidates, funcCandidates.defaultIndex, []);

if isempty(Reg2D)
    fprintf('No 2D registration returned.\n');
    return;
end

fprintf('--- Simple 2D Coronal Atlas Registration finished ---\n');

end


%% =======================================================================
% Build functional candidates
%% =======================================================================
function funcCandidates = buildFunctionalCandidates(studio, rawRoot, analysedRoot, registrationRoot, sourceFile)

funcCandidates = struct();
funcCandidates.items = {};
funcCandidates.labels = {};
funcCandidates.defaultIndex = 1;

% 1) Prefer Studio datasets
[studioItems, studioLabels, studioDefault] = collectStudioFunctionalCandidates(studio);

funcCandidates.items = [funcCandidates.items studioItems];
funcCandidates.labels = [funcCandidates.labels studioLabels];

if ~isempty(studioItems)
    funcCandidates.defaultIndex = studioDefault;
end

% 2) Add file-based candidates
rootFolders = {rawRoot, analysedRoot, registrationRoot};
rootFolders = rootFolders(~cellfun(@isempty, rootFolders));
rootFolders = rootFolders(cellfun(@(p) exist(p,'dir')==7, rootFolders));
rootFolders = unique(rootFolders,'stable');

[fileList, fileLabels] = collectFunctionalFilesRecursive(rootFolders, rawRoot, analysedRoot, registrationRoot);

for k = 1:numel(fileList)
    fp = fileList{k};

    if strcmpi(fp, sourceFile)
        continue;
    end

    item = struct();
    item.type = 'file';
    item.file = fp;
    item.label = fileLabels{k};

    funcCandidates.items{end+1} = item; %#ok<AGROW>
    funcCandidates.labels{end+1} = fileLabels{k}; %#ok<AGROW>
end

if isempty(funcCandidates.items)
    funcCandidates.defaultIndex = 1;
else
    funcCandidates.defaultIndex = max(1, min(numel(funcCandidates.items), funcCandidates.defaultIndex));
end

end


function [items, labels, defaultIndex] = collectStudioFunctionalCandidates(studio)

items = {};
labels = {};
defaultIndex = 1;

if ~isfield(studio,'datasets') || ~isstruct(studio.datasets) || isempty(fieldnames(studio.datasets))
    return;
end

ds = studio.datasets;
keys = fieldnames(ds);

activeKey = '';
if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
    activeKey = char(studio.activeDataset);
end

ordered = {};
if ~isempty(activeKey) && isfield(ds, activeKey)
    ordered{end+1} = activeKey; %#ok<AGROW>
end

for i = 1:numel(keys)
    if isempty(find(strcmp(ordered, keys{i}),1))
        ordered{end+1} = keys{i}; %#ok<AGROW>
    end
end

for i = 1:numel(ordered)
    key = ordered{i};
    d = ds.(key);

    item = struct();

    if isstruct(d) && isfield(d,'isLazy') && d.isLazy && isfield(d,'lazyFile') && exist(d.lazyFile,'file')==2
        item.type = 'file';
        item.file = d.lazyFile;
    else
        item.type = 'studio';
        item.payload = d;
    end

    item.datasetKey = key;

    if strcmp(key, activeKey)
        lab = ['STUDIO ACTIVE: ' key];
        defaultIndex = i;
    else
        lab = ['STUDIO: ' key];
    end

    item.label = lab;

    items{end+1} = item; %#ok<AGROW>
    labels{end+1} = lab; %#ok<AGROW>
end

end


%% =======================================================================
% Source file collection
%% =======================================================================
function [fileList, displayList] = collectSourceFiles(searchFolders, rawRoot, analysedRoot, registrationRoot)

fileList = {};
displayList = {};

patterns = {'*.mat','*.nii','*.nii.gz','*.png','*.jpg','*.jpeg','*.tif','*.tiff','*.bmp'};

for i = 1:numel(searchFolders)
    f = searchFolders{i};
    if isempty(f) || ~exist(f,'dir')
        continue;
    end

    for p = 1:numel(patterns)
        d = dir(fullfile(f, patterns{p}));
        for k = 1:numel(d)
            fp = fullfile(f, d(k).name);

            if ~isAllowedSourceFile(fp)
                continue;
            end

            fileList{end+1} = fp; %#ok<AGROW>
            displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot); %#ok<AGROW>
        end
    end
end

[displayList, ia] = unique(displayList,'stable');
fileList = fileList(ia);

end


function tf = isAllowedSourceFile(fp)

tf = false;

[folder, nm, ext] = fileparts(fp);
folderL = lower(folder);
nameL   = lower(nm);
fullName = [nm ext];

% Only allow source-like folders
okFolder = false;
if ~isempty(strfind(folderL, [filesep 'visualization'])) %#ok<STREMP>
    okFolder = true;
end
if ~isempty(strfind(folderL, [filesep 'visualisation'])) %#ok<STREMP>
    okFolder = true;
end
if ~isempty(strfind(folderL, [filesep 'mask'])) %#ok<STREMP>
    okFolder = true;
end
if ~isempty(strfind(folderL, [filesep 'masks'])) %#ok<STREMP>
    okFolder = true;
end
if ~isempty(strfind(folderL, [filesep 'registration2d'])) %#ok<STREMP>
    okFolder = true;
end

if ~okFolder
    return;
end

% Reject specific files
if strcmpi(fullName,'Transformation.mat') || ...
   strcmpi(fullName,'CoronalRegistration2D.mat') || ...
   strcmpi(fullName,'allen_brain_atlas.mat')
    return;
end

% Reject obvious QC / preprocessing / plot names
badNameTerms = { ...
    'framerate','frame_rate','frame', ...
    'rotation','translation','spike','dvars','motion', ...
    'pca','despike','scrub','qc','rejected', ...
    'timeseries','trace','plot','powerpoint', ...
    'warpeddata','coronalregistration2d','transformation', ...
    'globalmean','burst','cnr','commonmode', ...
    'intensity','interpolated','original'};

for i = 1:numel(badNameTerms)
    if ~isempty(strfind(nameL, badNameTerms{i})) %#ok<STREMP>
        return;
    end
end

% Allow image files only if they look source-like
goodNameTerms = { ...
    'brainonly','brainimage','brainmask', ...
    'anatom','underlay','histology','vascular','regions','mask','atlasunderlay'};

isClearlyGood = false;
for i = 1:numel(goodNameTerms)
    if ~isempty(strfind(nameL, goodNameTerms{i})) %#ok<STREMP>
        isClearlyGood = true;
        break;
    end
end

if isImageFile(fp)
    tf = isClearlyGood;
    return;
end

if strcmpi(ext,'.nii') || strcmpi(ext,'.gz')
    tf = true;
    return;
end

if strcmpi(ext,'.mat')
    tf = hasLikelySourceContent(fp);
    return;
end

end


function tf = hasLikelySourceContent(matFile)

tf = false;

try
    info = whos('-file', matFile);
    if isempty(info)
        return;
    end

    preferredNames = { ...
        'brainImage', ...
        'anatomical_reference', ...
        'anatomical_reference_raw', ...
        'brainMask', ...
        'mask', ...
        'Data', ...
        'I'};

    for i = 1:numel(info)
        nm = info(i).name;
        sz = info(i).size;
        cl = info(i).class;

        if any(strcmp(nm, preferredNames))
            if (strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
                strcmp(cl,'uint8') || strcmp(cl,'logical')) && ...
                numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end

    % Allow structs because loadSourceAs2D can inspect them safely
    for i = 1:numel(info)
        if strcmp(info(i).class,'struct')
            tf = true;
            return;
        end
    end

    % Fallback: numeric 2D or 3D image-like array only
    for i = 1:numel(info)
        cl = info(i).class;
        sz = info(i).size;

        if strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
           strcmp(cl,'uint8') || strcmp(cl,'logical')
            if numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end

catch
    tf = false;
end

end

%% =======================================================================
% Functional file collection
%% =======================================================================
function [fileList, displayList] = collectFunctionalFilesRecursive(rootFolders, rawRoot, analysedRoot, registrationRoot)

fileList = {};
displayList = {};

for i = 1:numel(rootFolders)
    rootDir = rootFolders{i};
    if isempty(rootDir) || ~exist(rootDir,'dir')
        continue;
    end

    filesHere = collectFilesRecursive(rootDir);

    for k = 1:numel(filesHere)
        fp = filesHere{k};

        if ~isAllowedFunctionalFile(fp)
            continue;
        end

        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot); %#ok<AGROW>
    end
end

[displayList, ia] = unique(displayList,'stable');
fileList = fileList(ia);

end


function files = collectFilesRecursive(rootDir)

files = {};

if isempty(rootDir) || ~exist(rootDir,'dir')
    return;
end

d = dir(rootDir);

for i = 1:numel(d)
    nm = d(i).name;

    if d(i).isdir
        if strcmp(nm,'.') || strcmp(nm,'..')
            continue;
        end

        subFiles = collectFilesRecursive(fullfile(rootDir, nm));
        if ~isempty(subFiles)
            files = [files subFiles]; %#ok<AGROW>
        end
    else
        files{end+1} = fullfile(rootDir, nm); %#ok<AGROW>
    end
end

end


function tf = isAllowedFunctionalFile(fp)

tf = false;

[folder, nm, ext] = fileparts(fp);
folderL = lower(folder);
nameLower = lower(nm);

% reject clearly irrelevant folders
badFolderTerms = { ...
    [filesep 'qc' filesep], ...
    [filesep 'scm' filesep]};
if pathHasAnyTerm(folderL, badFolderTerms)
    return;
end

if strcmpi([nm ext],'Transformation.mat')
    return;
end
if strcmpi([nm ext],'CoronalRegistration2D.mat')
    return;
end
if strcmpi([nm ext],'allen_brain_atlas.mat')
    return;
end

if ~isempty(strfind(nameLower,'atlasunderlay')) %#ok<STREMP>
    return;
end
if ~isempty(strfind(nameLower,'brainonly')) %#ok<STREMP>
    return;
end
if ~isempty(strfind(nameLower,'coronalregistration2d')) %#ok<STREMP>
    return;
end
if ~isempty(strfind(nameLower,'warpeddata')) %#ok<STREMP>
    return;
end
if ~isempty(strfind(nameLower,'transformation')) %#ok<STREMP>
    return;
end

if strcmpi(ext,'.nii') || strcmpi(ext,'.gz')
    tf = true;
    return;
end

if strcmpi(ext,'.mat')
    tf = hasLikelyFunctionalContent(fp);
end

end


function tf = hasLikelyFunctionalContent(matFile)

tf = false;

try
    info = whos('-file', matFile);
    if isempty(info)
        return;
    end

    % Preferred direct variables
    preferredNames = {'I','Data','PSC','newData','data'};

    for i = 1:numel(info)
        nm = info(i).name;
        sz = info(i).size;
        cl = info(i).class;

        if any(strcmp(nm, preferredNames))
            if strcmp(cl,'struct')
                tf = true;
                return;
            end
            if (strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
                strcmp(cl,'uint8') || strcmp(cl,'logical')) && ...
                numel(sz) >= 2 && numel(sz) <= 4 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end

    % Accept struct containers
    for i = 1:numel(info)
        if strcmp(info(i).class,'struct')
            tf = true;
            return;
        end
    end

    % Fallback numeric 2D..4D
    for i = 1:numel(info)
        nm = lower(info(i).name);
        sz = info(i).size;
        cl = info(i).class;

        if ~isempty(strfind(nm,'brainimage')) || ~isempty(strfind(nm,'brainmask')) || ...
           ~isempty(strfind(nm,'atlasunderlay')) || ~isempty(strfind(nm,'reg2d')) || ...
           ~isempty(strfind(nm,'transf')) %#ok<STREMP>
            continue;
        end

        if strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
           strcmp(cl,'uint8') || strcmp(cl,'logical')
            if numel(sz) >= 2 && numel(sz) <= 4 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end

catch
    tf = false;
end

end


%% =======================================================================
% Display naming
%% =======================================================================
function s = makeDisplayName(fullpath, rawRoot, analysedRoot, registrationRoot)

try
    if ~isempty(registrationRoot) && strncmpi(fullpath, registrationRoot, numel(registrationRoot))
        rel = fullpath(numel(registrationRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep
            rel = rel(2:end);
        end
        s = ['REG2D: ' rel];
        return;
    end
catch
end

try
    if ~isempty(rawRoot) && strncmpi(fullpath, rawRoot, numel(rawRoot))
        rel = fullpath(numel(rawRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep
            rel = rel(2:end);
        end
        s = ['RAW: ' rel];
        return;
    end
catch
end

try
    if ~isempty(analysedRoot) && strncmpi(fullpath, analysedRoot, numel(analysedRoot))
        rel = fullpath(numel(analysedRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep
            rel = rel(2:end);
        end
        s = ['ANA: ' rel];
        return;
    end
catch
end

s = fullpath;
end


%% =======================================================================
% Load source as 2D + attach mask if found
%% =======================================================================
function [img2D, info] = loadSourceAs2D(sourceFile)

info = struct();
info.path = sourceFile;
info.label = sourceFile;
info.mask2D = [];

if endsWithLower(sourceFile,'.mat')
    S = load(sourceFile);
    [candNames, candData] = detect2DCandidatesFromMat(S);

    if isempty(candData)
        error('Selected MAT contains no suitable 2D or 3D image candidate.');
    end

    if numel(candData) > 1
        pretty = candNames;
        for k = 1:numel(candData)
            pretty{k} = sprintf('%s   [%s]', candNames{k}, joinDims(size(candData{k})));
        end

        [jdx, tf] = listdlg( ...
            'PromptString','Select source variable:', ...
            'SelectionMode','single', ...
            'ListString',pretty, ...
            'ListSize',[760 320]);

        if ~tf
            error('Source selection cancelled.');
        end
    else
        jdx = 1;
    end

    tmp = candData{jdx};
    info.label = candNames{jdx};
    img2D = choose2DSlice(tmp, info.label);

    % Try to auto-attach corresponding mask from same MAT
    info.mask2D = chooseBestMaskForSource(S, tmp, info.label);

elseif endsWithLower(sourceFile,'.nii') || endsWithLower(sourceFile,'.nii.gz')
    [D, ~] = loadNiftiMaybeGz(sourceFile);
    img2D = choose2DSlice(double(D), sourceFile);
    info.label = sourceFile;

elseif isImageFile(sourceFile)
    img2D = load2DImage(sourceFile);
    info.label = sourceFile;

else
    error('Unsupported source file type.');
end

img2D = double(img2D);
img2D(~isfinite(img2D)) = 0;

end


function [candNames, candData] = detect2DCandidatesFromMat(S)

fields = fieldnames(S);
candNames = {};
candData = {};

preferred = { ...
    'brainImage', ...
    'anatomical_reference', ...
    'anatomical_reference_raw', ...
    'I', ...
    'Data', ...
    'brainMask', ...
    'mask' ...
    };

ordered = {};
for i = 1:numel(preferred)
    if isfield(S, preferred{i})
        ordered{end+1} = preferred{i}; %#ok<AGROW>
    end
end
for i = 1:numel(fields)
    if isempty(find(strcmp(ordered, fields{i}),1))
        ordered{end+1} = fields{i}; %#ok<AGROW>
    end
end

for i = 1:numel(ordered)
    nm = ordered{i};
    v = S.(nm);

    if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
        D = double(v.Data);
        if ndims(D) == 2 || ndims(D) == 3
            candNames{end+1} = nm; %#ok<AGROW>
            candData{end+1} = D; %#ok<AGROW>
        end
        continue;
    end

    if (isnumeric(v) || islogical(v)) && ~isempty(v)
        D = double(v);
        if ndims(D) == 2 || ndims(D) == 3
            candNames{end+1} = nm; %#ok<AGROW>
            candData{end+1} = D; %#ok<AGROW>
        end
    end
end

end


function mask2D = chooseBestMaskForSource(S, selectedData, selectedLabel)

mask2D = [];

fields = fieldnames(S);
selectedSize = size(selectedData);

preferredMaskNames = { ...
    'brainMask', ...
    'mask', ...
    'brain_mask', ...
    'Mask' ...
    };

% First try preferred names
for i = 1:numel(preferredMaskNames)
    nm = preferredMaskNames{i};
    if isfield(S, nm)
        m = S.(nm);
        tmp = tryConvertMaskTo2D(m, selectedSize, selectedLabel);
        if ~isempty(tmp)
            mask2D = tmp;
            return;
        end
    end
end

% Then try any logical / likely-mask variable
for i = 1:numel(fields)
    nm = fields{i};
    if strcmp(nm, selectedLabel)
        continue;
    end

    try
        m = S.(nm);
    catch
        continue;
    end

    nameLower = lower(nm);
    if isempty(strfind(nameLower,'mask')) && ~islogical(m)
        continue;
    end

    tmp = tryConvertMaskTo2D(m, selectedSize, selectedLabel);
    if ~isempty(tmp)
        mask2D = tmp;
        return;
    end
end

end


function mask2D = tryConvertMaskTo2D(m, selectedSize, selectedLabel)

mask2D = [];

if isempty(m)
    return;
end

if isstruct(m) && isfield(m,'Data') && ~isempty(m.Data)
    m = m.Data;
end

if ~(isnumeric(m) || islogical(m))
    return;
end

m = double(m);

if ndims(m) == 2
    if isequal(size(m), selectedSize(1:2))
        mask2D = logical(m ~= 0);
        return;
    end
end

if ndims(m) == 3
    if numel(selectedSize) == 2
        nz = size(m,3);
        idx = chooseSliceIndexForMask(nz, selectedLabel);
        tmp = squeeze(m(:,:,idx));
        if isequal(size(tmp), selectedSize(1:2))
            mask2D = logical(tmp ~= 0);
            return;
        end
    elseif numel(selectedSize) == 3
        if size(m,3) == selectedSize(3)
            idx = chooseSliceIndexForMask(size(m,3), selectedLabel);
            tmp = squeeze(m(:,:,idx));
            if isequal(size(tmp), selectedSize(1:2))
                mask2D = logical(tmp ~= 0);
                return;
            end
        end
    end
end

end


function idx = chooseSliceIndexForMask(nz, labelText)

defaultIdx = round(nz/2);

answ = inputdlg( ...
    {sprintf('Mask candidate is 3D. Choose slice index for contour guide (1..%d):', nz)}, ...
    ['Mask slice - ' labelText], ...
    1, ...
    {num2str(defaultIdx)});

if isempty(answ)
    idx = defaultIdx;
else
    idx = round(str2double(answ{1}));
    if ~isfinite(idx)
        idx = defaultIdx;
    end
end

idx = max(1, min(nz, idx));

end


function img2D = choose2DSlice(D, labelText)

if ndims(D) == 2
    img2D = D;
    return;
end

if ndims(D) ~= 3
    error('Only 2D or 3D data supported for simple 2D registration.');
end

nz = size(D,3);
defaultIdx = round(nz/2);

answ = inputdlg( ...
    {sprintf('Selected data is 3D [%s]. Enter coronal slice index along 3rd dimension (1..%d):', joinDims(size(D)), nz)}, ...
    ['Choose slice - ' labelText], ...
    1, ...
    {num2str(defaultIdx)});

if isempty(answ)
    error('Slice selection cancelled.');
end

idx = round(str2double(answ{1}));
if ~isfinite(idx)
    idx = defaultIdx;
end
idx = max(1, min(nz, idx));

img2D = squeeze(D(:,:,idx));

end


%% =======================================================================
% Generic utilities
%% =======================================================================
function out = inferAnalysedFromRaw(rawFolder)

out = '';
if isempty(rawFolder)
    return;
end

cand = strrep(rawFolder, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
    return;
end

cand = strrep(rawFolder, [filesep 'rawdata' filesep], [filesep 'analyseddata' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
    return;
end

end


function tf = endsWithLower(str, suffix)

str = lower(str);
suffix = lower(suffix);
if numel(str) < numel(suffix)
    tf = false;
    return;
end
tf = strcmp(str(end-numel(suffix)+1:end), suffix);

end


function [D, vox] = loadNiftiMaybeGz(f)

vox = [];
isGz = (numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz'));

if isGz
    tmpDir = tempname;
    mkdir(tmpDir);
    gunzip(f, tmpDir);
    d = dir(fullfile(tmpDir,'*.nii'));
    if isempty(d)
        error('Failed to gunzip: %s', f);
    end
    niiFile = fullfile(tmpDir, d(1).name);

    info = niftiinfo(niiFile);
    D = niftiread(info);

    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions) >= 3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end

    try
        rmdir(tmpDir,'s');
    catch
    end
else
    info = niftiinfo(f);
    D = niftiread(info);

    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions) >= 3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end
end

end


function tf = isImageFile(f)

f = lower(f);
tf = endsWithLower(f,'.png') || endsWithLower(f,'.jpg') || endsWithLower(f,'.jpeg') || ...
     endsWithLower(f,'.tif') || endsWithLower(f,'.tiff') || endsWithLower(f,'.bmp');

end


function I = load2DImage(f)

I = imread(f);
if ndims(I) == 3
    I = double(I);
    I = (I(:,:,1) + I(:,:,2) + I(:,:,3)) / 3;
else
    I = double(I);
end

end


function s = joinDims(sz)

if isempty(sz)
    s = '';
    return;
end
s = num2str(sz(1));
for k = 2:numel(sz)
    s = [s 'x' num2str(sz(k))]; %#ok<AGROW>
end

end


function tf = pathHasAnyTerm(pathStr, terms)

tf = false;
for i = 1:numel(terms)
    if ~isempty(strfind(pathStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end

end


function tf = nameHasAnyTerm(nameStr, terms)

tf = false;
for i = 1:numel(terms)
    if ~isempty(strfind(nameStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end

end