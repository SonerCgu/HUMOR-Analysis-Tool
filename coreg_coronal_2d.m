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
    rawFolder, ...
    analysedFolder, ...
    registrationDir ...
    };

searchFolders = searchFolders(~cellfun(@isempty, searchFolders));
searchFolders = searchFolders(cellfun(@(p) exist(p,'dir')==7, searchFolders));
searchFolders = unique(searchFolders,'stable');

directFiles = {};
if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile) && exist(studio.loadedFile,'file') == 2
    directFiles{end+1} = studio.loadedFile; %#ok<AGROW>
end

preferredSourceFile = '';

% Prefer the brainImage MAT created by Mask Editor
if isfield(studio,'brainImageFile') && ~isempty(studio.brainImageFile) && exist(studio.brainImageFile,'file') == 2
    preferredSourceFile = studio.brainImageFile;
end

if ~isempty(preferredSourceFile)
    sourceFile = preferredSourceFile;
    fprintf('Auto-selected Mask Editor brainImage file:\n%s\n', sourceFile);
else
    [sourceFiles, sourceLabels] = collectSourceFiles(searchFolders, rawFolder, analysedFolder, registrationDir, directFiles);

    if isempty(sourceFiles)
        error(['No suitable source files found.' char(10) ...
               'Checked loaded file, RAW root, ANALYSED root, Visualization/Mask folders, and Registration2D.' char(10) ...
               'Expected source-like files such as brainImage / anatomical reference / mask / atlas underlay MAT-NIfTI-image files.']);
    end

   [idx, tf] = chooseSourceFileDialog(sourceLabels);

if ~tf
    fprintf('2D coronal registration cancelled.\n');
    return;
end

sourceFile = sourceFiles{idx};
end

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
initialReg = [];

regFiles = collectRegistration2DFiles(registrationDir);

if ~isempty(regFiles.files)
    choice = questdlg( ...
        'Load a previous slice-specific 2D registration?', ...
        'Previous 2D Registration', ...
        'Yes','No','No');

    if strcmp(choice,'Yes')
        [idxReg, tfReg] = listdlg( ...
            'PromptString','Select previous 2D registration:', ...
            'SelectionMode','single', ...
            'ListString',regFiles.labels, ...
            'ListSize',[860 420]);

        if tfReg
            tmp = load(regFiles.files{idxReg}, 'Reg2D');
            if isfield(tmp,'Reg2D')
                initialReg = tmp.Reg2D;
            end
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
function [fileList, displayList] = collectSourceFiles(searchFolders, rawRoot, analysedRoot, registrationRoot, directFiles)

fileList = {};
displayList = {};

% 1) Explicit direct files first (e.g. currently loaded MAT)
if nargin >= 5 && ~isempty(directFiles)
    for i = 1:numel(directFiles)
        fp = directFiles{i};
        if exist(fp,'file') ~= 2
            continue;
        end
        if ~isAllowedSourceFile(fp)
            continue;
        end
        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = ['LOADED: ' makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot)]; %#ok<AGROW>
    end
end

% 2) Search folders recursively but prune irrelevant directories
skipTerms = getSourceSkipFolderTerms();

for i = 1:numel(searchFolders)
    f = searchFolders{i};
    if isempty(f) || ~exist(f,'dir')
        continue;
    end

    filesHere = collectFilesRecursiveFiltered(f, skipTerms);

    for k = 1:numel(filesHere)
        fp = filesHere{k};

        if ~isAllowedSourceFile(fp)
            continue;
        end

        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot); %#ok<AGROW>
    end
end

if isempty(fileList)
    return;
end

normKeys = cell(size(fileList));
for ii = 1:numel(fileList)
    normKeys{ii} = normalizePathKey(fileList{ii});
end

[~, ia] = unique(normKeys,'stable');
fileList = fileList(ia);
displayList = displayList(ia);

[fileList, displayList] = sortSourceEntries(fileList, displayList);

end


function files = collectFilesRecursiveFiltered(rootDir, skipTerms)

files = {};

if isempty(rootDir) || ~exist(rootDir,'dir')
    return;
end

d = dir(rootDir);

for i = 1:numel(d)
    nm = d(i).name;
    fp = fullfile(rootDir, nm);

    if d(i).isdir
        if strcmp(nm,'.') || strcmp(nm,'..')
            continue;
        end

        if folderShouldBeSkipped(fp, skipTerms)
            continue;
        end

        subFiles = collectFilesRecursiveFiltered(fp, skipTerms);
        if ~isempty(subFiles)
            files = [files subFiles]; %#ok<AGROW>
        end
    else
        if isRecognizedSourceExtension(fp)
            files{end+1} = fp; %#ok<AGROW>
        end
    end
end

end


function tf = folderShouldBeSkipped(folderPath, skipTerms)

folderL = lower(folderPath);
tf = pathHasAnyTerm(folderL, skipTerms);

end


function tf = isRecognizedSourceExtension(fp)

tf = false;
if isImageFile(fp) || isNiftiFile(fp)
    tf = true;
    return;
end

[~,~,ext] = fileparts(fp);
if strcmpi(ext,'.mat')
    tf = true;
end

end


function tf = isAllowedSourceFile(fp)

tf = false;

[folder, nm, ext] = fileparts(fp);
folderL = lower(folder);
nameL   = lower(nm);
fullL   = lower([nm ext]);

% Reject by folder first
if folderShouldBeSkipped(folder, getSourceSkipFolderTerms())
    return;
end

% Reject specific files
if strcmpi(fullL,'transformation.mat') || ...
   strcmpi(fullL,'coronalregistration2d.mat') || ...
   strcmpi(fullL,'allen_brain_atlas.mat')
    return;
end

% Reject obvious QC / preprocessing / plot names
if nameHasAnyTerm(nameL, getSourceBadNameTerms())
    return;
end

% Images: require clearly source-like names
if isImageFile(fp)
    tf = nameHasAnyTerm(nameL, getSourceGoodNameTerms());
    return;
end

% NIfTI: accept only if name looks source-like or if it lives in a source-like folder
if isNiftiFile(fp)
    tf = nameHasAnyTerm(nameL, getSourceGoodNameTerms()) || folderLooksSourceLike(folderL);
    return;
end

% MAT: use content-based check
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
        'Mask', ...
        'atlasUnderlay', ...
        'atlasUnderlayRGB', ...
        'Data', ...
        'I'};

    badTerms = getSourceBadNameTerms();
    sourceTerms = getSourceGoodNameTerms();

    % Strong positive matches
    for i = 1:numel(info)
        nm = info(i).name;
        nmL = lower(nm);
        sz = info(i).size;
        cl = info(i).class;

        if nameHasAnyTerm(nmL, badTerms)
            continue;
        end

        if any(strcmp(nm, preferredNames))
            if strcmp(cl,'struct')
                tf = true;
                return;
            end
            if (strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
                strcmp(cl,'uint8') || strcmp(cl,'logical')) && ...
                numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end

        if nameHasAnyTerm(nmL, sourceTerms)
            if strcmp(cl,'struct')
                tf = true;
                return;
            end
            if (strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
                strcmp(cl,'uint8') || strcmp(cl,'logical')) && ...
                numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end

    % Fallback: single-variable MAT with 2D/3D image-like content
    if numel(info) == 1
        nmL = lower(info(1).name);
        sz = info(1).size;
        cl = info(1).class;

        if ~nameHasAnyTerm(nmL, badTerms)
            if strcmp(cl,'struct')
                tf = true;
                return;
            end
            if (strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
                strcmp(cl,'uint8') || strcmp(cl,'logical')) && ...
                numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
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

if isempty(fileList)
    return;
end

[fileList, ia] = unique(fileList,'stable');
displayList = displayList(ia);

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

if isNiftiFile(fp)
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

    jdx = [];

% Auto-prefer brainImage-like variables first
preferredNames = { ...
    'brainImage', ...
    'maskBundle.brainImage', ...
    'loadedMask.brainImage', ...
    'anatomical_reference', ...
    'anatomical_reference_raw'};

for pp = 1:numel(preferredNames)
    hit = find(strcmpi(candNames, preferredNames{pp}), 1);
    if ~isempty(hit)
        jdx = hit;
        break;
    end
end

% Fallback to manual selection only if no preferred source was found
if isempty(jdx)
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
end

    tmp = candData{jdx};
    info.label = candNames{jdx};
    img2D = choose2DSlice(tmp, info.label);

    % Try to auto-attach corresponding mask from same MAT
    info.mask2D = chooseBestMaskForSource(S, tmp, info.label);

elseif isNiftiFile(sourceFile)
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
    'atlasUnderlay', ...
    'brainMask', ...
    'mask', ...
    'Mask', ...
    'I', ...
    'Data' ...
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
    [candNames, candData] = appendSourceCandidatesFromValue(candNames, candData, nm, v);
end

if isempty(candNames)
    return;
end

[candNames, ia] = unique(candNames,'stable');
candData = candData(ia);

end


function [candNames, candData] = appendSourceCandidatesFromValue(candNames, candData, baseName, v)

if isstruct(v)
    nestedPreferred = { ...
        'brainImage', ...
        'anatomical_reference', ...
        'anatomical_reference_raw', ...
        'atlasUnderlay', ...
        'brainMask', ...
        'mask', ...
        'Mask', ...
        'Data', ...
        'I' ...
        };

    for i = 1:numel(nestedPreferred)
        f = nestedPreferred{i};
        if isfield(v, f)
            vv = v.(f);
            [candNames, candData] = addCandidateIfImageLike(candNames, candData, [baseName '.' f], vv);
        end
    end

    if isscalar(v)
        fns = fieldnames(v);
        for i = 1:numel(fns)
            fn = fns{i};
            fnL = lower(fn);
            if nameHasAnyTerm(fnL, getSourceBadNameTerms())
                continue;
            end
            if nameHasAnyTerm(fnL, getSourceGoodNameTerms()) || strcmpi(fn,'Data') || strcmpi(fn,'I')
                vv = v.(fn);
                [candNames, candData] = addCandidateIfImageLike(candNames, candData, [baseName '.' fn], vv);
            end
        end
    end
else
    [candNames, candData] = addCandidateIfImageLike(candNames, candData, baseName, v);
end

end


function [candNames, candData] = addCandidateIfImageLike(candNames, candData, candName, v)

if isempty(v)
    return;
end

if isstruct(v) && isfield(v,'Data') && ~isempty(v.Data)
    v = v.Data;
end

if ~(isnumeric(v) || islogical(v))
    return;
end

D = double(v);
if ndims(D) == 2 || ndims(D) == 3
    if prod(double(size(D))) > 100
        candNames{end+1} = candName; %#ok<AGROW>
        candData{end+1} = D; %#ok<AGROW>
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

function out = collectRegistration2DFiles(registrationDir)

out = struct();
out.files = {};
out.labels = {};

if isempty(registrationDir) || ~exist(registrationDir,'dir')
    return;
end

allFiles = collectFilesRecursive(registrationDir);

for k = 1:numel(allFiles)
    fp = allFiles{k};
    [~,nm,ext] = fileparts(fp);

    if ~strcmpi(ext,'.mat')
        continue;
    end

    nmL = lower(nm);
    if isempty(strfind(nmL,'coronalregistration2d_slice')) %#ok<STREMP>
        continue;
    end

    out.files{end+1} = fp; %#ok<AGROW>
    out.labels{end+1} = makeRegistrationDisplayName(fp, registrationDir); %#ok<AGROW>
end

if isempty(out.files)
    return;
end

normKeys = cell(size(out.files));
for ii = 1:numel(out.files)
    normKeys{ii} = normalizePathKey(out.files{ii});
end

[~, ia] = unique(normKeys,'stable');
out.files = out.files(ia);
out.labels = out.labels(ia);
end


function s = makeRegistrationDisplayName(fullpath, registrationDir)

s = fullpath;

try
    if ~isempty(registrationDir) && strncmpi(fullpath, registrationDir, numel(registrationDir))
        rel = fullpath(numel(registrationDir)+1:end);
        if ~isempty(rel) && rel(1)==filesep
            rel = rel(2:end);
        end
        s = ['REG2D: ' rel];
    end
catch
end
end


function [idx, tf] = chooseSourceFileDialog(sourceLabels)

idx = [];
tf = false;

if isempty(sourceLabels)
    return;
end

bg      = [0.00 0.00 0.00];
fg      = [1.00 1.00 1.00];
subFG   = [0.82 0.82 0.82];
btnBlue = [0.20 0.45 0.92];
btnRed  = [0.85 0.20 0.20];

figSel = figure( ...
    'Name','Select Coronal Source Image', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Resize','off', ...
    'WindowStyle','modal', ...
    'Position',[120 60 1450 900], ...
    'CloseRequestFcn',@onCancel);

uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
    'Position',[0.03 0.94 0.94 0.035], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',18, ...
    'FontWeight','bold', ...
    'String','Select coronal source image');

uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
    'Position',[0.03 0.90 0.94 0.03], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',subFG, ...
    'HorizontalAlignment','left', ...
    'FontSize',12, ...
    'String','Recommended: BrainOnly / brainImage from Mask Editor');

% Optional small legend
% uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
%     'Position',[0.03 0.865 0.18 0.025], ...
%     'BackgroundColor',bg, ...
%     'ForegroundColor',[0.43 0.76 1.00], ...
%     'HorizontalAlignment','left', ...
%     'FontSize',11, ...
%     'FontWeight','bold', ...
%     'String','[RAW]');
% 
% uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
%     'Position',[0.12 0.865 0.18 0.025], ...
%     'BackgroundColor',bg, ...
%     'ForegroundColor',[0.49 1.00 0.70], ...
%     'HorizontalAlignment','left', ...
%     'FontSize',11, ...
%     'FontWeight','bold', ...
%     'String','[ANA]');
% 
% uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
%     'Position',[0.20 0.865 0.18 0.025], ...
%     'BackgroundColor',bg, ...
%     'ForegroundColor',[1.00 0.80 0.40], ...
%     'HorizontalAlignment','left', ...
%     'FontSize',11, ...
%     'FontWeight','bold', ...
%     'String','[REG2D]');
% 
% uicontrol('Style','text','Parent',figSel,'Units','normalized', ...
%     'Position',[0.31 0.865 0.18 0.025], ...
%     'BackgroundColor',bg, ...
%     'ForegroundColor',[1.00 0.55 0.68], ...
%     'HorizontalAlignment','left', ...
%     'FontSize',11, ...
%     'FontWeight','bold', ...
%     'String','[LOADED]');

listLabels = colorizeSourceLabelsForJava(sourceLabels);

jModel = javaObjectEDT('javax.swing.DefaultListModel');
for ii = 1:numel(listLabels)
    jModel.addElement(listLabels{ii});
end

jList = javaObjectEDT('javax.swing.JList', jModel);
jList.setSelectionMode(javax.swing.ListSelectionModel.SINGLE_SELECTION);
jList.setSelectedIndex(0);
jList.setBackground(java.awt.Color(0,0,0));
jList.setForeground(java.awt.Color(1,1,1));
jList.setSelectionBackground(java.awt.Color(0.18,0.18,0.18));
jList.setSelectionForeground(java.awt.Color(1,1,1));
jList.setFont(java.awt.Font('Consolas', java.awt.Font.PLAIN, 16));
jList.setFixedCellHeight(28);

jScroll = javaObjectEDT('javax.swing.JScrollPane', jList);
jScroll.setBackground(java.awt.Color(0,0,0));
jScroll.getViewport.setBackground(java.awt.Color(0,0,0));

[~, hListContainer] = javacomponent(jScroll, [40 90 1365 705], figSel);
set(hListContainer, 'Units','pixels');

set(handle(jList,'CallbackProperties'), 'MouseClickedCallback', @onJListClick);
set(handle(jList,'CallbackProperties'), 'KeyPressedCallback', @onJListKey);

uicontrol('Style','pushbutton','Parent',figSel,'Units','normalized', ...
    'Position',[0.58 0.03 0.18 0.06], ...
    'String','Use Selected', ...
    'BackgroundColor',btnBlue, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'Callback',@onOK);

uicontrol('Style','pushbutton','Parent',figSel,'Units','normalized', ...
    'Position',[0.78 0.03 0.18 0.06], ...
    'String','Cancel', ...
    'BackgroundColor',btnRed, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'Callback',@onCancel);

uiwait(figSel);

    function onOK(~,~)
        try
            idx = double(jList.getSelectedIndex()) + 1;
        catch
            idx = 1;
        end
        tf = ~isempty(idx) && idx >= 1;

        try
            uiresume(figSel);
        catch
        end
        try
            delete(figSel);
        catch
        end
    end

    function onCancel(~,~)
        idx = [];
        tf = false;

        try
            uiresume(figSel);
        catch
        end
        try
            delete(figSel);
        catch
        end
    end

    function onJListClick(~, evt)
        try
            if evt.getClickCount() >= 2
                onOK();
            end
        catch
        end
    end

    function onJListKey(~, evt)
        try
            keyCode = evt.getKeyCode();
            if keyCode == java.awt.event.KeyEvent.VK_ENTER
                onOK();
            elseif keyCode == java.awt.event.KeyEvent.VK_ESCAPE
                onCancel();
            end
        catch
        end
    end
end

function out = colorizeSourceLabelsForJava(sourceLabels)

out = cell(size(sourceLabels));

for i = 1:numel(sourceLabels)
    s = sourceLabels{i};

    prefix = '';
    rest = s;
    colorHex = '#FFFFFF';

    if startsWithLocal(s, 'LOADED: ')
        prefix = '[LOADED] ';
        rest = s(numel('LOADED: ')+1:end);
        colorHex = '#FF8CA8';

    elseif startsWithLocal(s, 'RAW: ')
        prefix = '[RAW] ';
        rest = s(numel('RAW: ')+1:end);
        colorHex = '#6EC1FF';

    elseif startsWithLocal(s, 'ANA: ')
        prefix = '[ANA] ';
        rest = s(numel('ANA: ')+1:end);
        colorHex = '#7DFFB2';

    elseif startsWithLocal(s, 'REG2D: ')
        prefix = '[REG2D] ';
        rest = s(numel('REG2D: ')+1:end);
        colorHex = '#FFCC66';
    end

    rest = strrep(rest, '&', '&amp;');
rest = strrep(rest, '<', '&lt;');
rest = strrep(rest, '>', '&gt;');

    out{i} = sprintf( ...
        '<html><span style="font-family:Consolas; font-size:15px;"><b><font color="%s">%s</font></b><font color="#FFFFFF">%s</font></span></html>', ...
        colorHex, prefix, rest);
end
end
%%%% Other Helpers %%%%

function out = prettifySourceLabels(sourceLabels)

out = sourceLabels;

for i = 1:numel(out)
    s = out{i};

    s = strrep(s, 'LOADED: ', '[LOADED] ');
    s = strrep(s, 'RAW: ',    '[RAW]    ');
    s = strrep(s, 'ANA: ',    '[ANA]    ');
    s = strrep(s, 'REG2D: ',  '[REG2D]  ');

    out{i} = s;
end
end

function tf = isImageFile(f)

f = lower(f);
tf = endsWithLower(f,'.png') || endsWithLower(f,'.jpg') || endsWithLower(f,'.jpeg') || ...
     endsWithLower(f,'.tif') || endsWithLower(f,'.tiff') || endsWithLower(f,'.bmp');

end

function tf = startsWithLocal(s, prefix)

if numel(s) < numel(prefix)
    tf = false;
    return;
end

tf = strcmpi(s(1:numel(prefix)), prefix);
end

function tf = isNiftiFile(f)

f = lower(f);
tf = endsWithLower(f,'.nii') || endsWithLower(f,'.nii.gz');

end

function k = normalizePathKey(p)

try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(p);
end

p = strrep(p, '/', filesep);
p = strrep(p, '\', filesep);

if ispc
    p = lower(p);
end

k = p;
end

function tableData = makeSourceTableData(sourceLabels)

tableData = cell(numel(sourceLabels), 2);

for i = 1:numel(sourceLabels)
    s = sourceLabels{i};

    typeStr = 'OTHER';
    pathStr = s;

    if startsWithLocal(s, 'LOADED: ')
        typeStr = 'LOADED';
        pathStr = s(numel('LOADED: ')+1:end);

    elseif startsWithLocal(s, 'RAW: ')
        typeStr = 'RAW';
        pathStr = s(numel('RAW: ')+1:end);

    elseif startsWithLocal(s, 'ANA: ')
        typeStr = 'ANA';
        pathStr = s(numel('ANA: ')+1:end);

    elseif startsWithLocal(s, 'REG2D: ')
        typeStr = 'REG2D';
        pathStr = s(numel('REG2D: ')+1:end);
    end

    % HTML styling may render in uitable on many MATLAB installs.
    % If not, it will simply show the raw text, which is still okay.
    switch typeStr
        case 'RAW'
            typeDisp = '<html><b><font color="#6EC1FF">RAW</font></b></html>';
        case 'ANA'
            typeDisp = '<html><b><font color="#7CFFB2">ANA</font></b></html>';
        case 'REG2D'
            typeDisp = '<html><b><font color="#FFCC66">REG2D</font></b></html>';
        case 'LOADED'
            typeDisp = '<html><b><font color="#FF8AAE">LOADED</font></b></html>';
        otherwise
            typeDisp = typeStr;
    end

    tableData{i,1} = typeDisp;
    tableData{i,2} = pathStr;
end
end

function [fileListOut, displayListOut] = sortSourceEntries(fileList, displayList)

if isempty(fileList)
    fileListOut = fileList;
    displayListOut = displayList;
    return;
end

prio = zeros(numel(displayList),1);

for i = 1:numel(displayList)
    s = lower(displayList{i});

    if ~isempty(strfind(s,'loaded:')) %#ok<STREMP>
        prio(i) = 1;
    elseif ~isempty(strfind(s,'raw:')) %#ok<STREMP>
        prio(i) = 2;
    elseif ~isempty(strfind(s,'ana:')) %#ok<STREMP>
        prio(i) = 3;
    elseif ~isempty(strfind(s,'reg2d:')) %#ok<STREMP>
        prio(i) = 4;
    else
        prio(i) = 5;
    end
end

[~, ord] = sort(prio, 'ascend');

fileListOut = fileList(ord);
displayListOut = displayList(ord);
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


function tf = folderLooksSourceLike(folderL)

terms = { ...
    [filesep 'visualization'], ...
    [filesep 'visualisation'], ...
    [filesep 'mask'], ...
    [filesep 'masks'], ...
    [filesep 'registration2d'] ...
    };

tf = pathHasAnyTerm(folderL, terms);

end


function terms = getSourceGoodNameTerms()

terms = { ...
    'brainonly', ...
    'brainimage', ...
    'brainmask', ...
    'brain_mask', ...
    'mask', ...
    'anatom', ...
    'anatomical', ...
    'reference', ...
    'underlay', ...
    'histology', ...
    'vascular', ...
    'regions', ...
    'atlasunderlay' ...
    };

end


function terms = getSourceBadNameTerms()

terms = { ...
    'framerate', ...
    'frame_rate', ...
    'framerejection', ...
    'frame_rejection', ...
    'rotation', ...
    'translation', ...
    'spike', ...
    'dvars', ...
    'motion', ...
    'pca', ...
    'despike', ...
    'scrub', ...
    'qc', ...
    'rejected', ...
    'rejection', ...
    'timeseries', ...
    'trace', ...
    'plot', ...
    'powerpoint', ...
    'warpeddata', ...
    'coronalregistration2d', ...
    'transformation', ...
    'globalmean', ...
    'burst', ...
    'cnr', ...
    'snr', ...
    'tsnr', ...
    'intensity', ...
    'spectrum', ...
    'histogram', ...
    'heatmap', ...
    'translation', ...
    'rotation', ...
    'video' ...
    };

end


function terms = getSourceSkipFolderTerms()

terms = { ...
    [filesep 'qc' filesep], ...
    [filesep 'framerate' filesep], ...
    [filesep 'frame_rate' filesep], ...
    [filesep 'scm' filesep], ...
    [filesep 'roi' filesep], ...
    [filesep 'video' filesep], ...
    [filesep 'videos' filesep], ...
    [filesep 'ppt' filesep], ...
    [filesep 'powerpoint' filesep], ...
    [filesep 'presentation' filesep], ...
    [filesep 'presentations' filesep], ...
    [filesep 'temp' filesep], ...
    [filesep 'tmp' filesep], ...
    [filesep 'logs' filesep] ...
    };

end