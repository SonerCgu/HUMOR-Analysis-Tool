function Reg2D = coreg_coronal_2d(studio, forcedSourceFile)
% coreg_coronal_2d.m
%
% Simple manual 2D coronal atlas registration launcher.
%
% Updated for 2D step-motor / multi-slice data:
%   - No separate source-slice chooser popup is opened by default.
%   - Full source stack is passed to registration_coronal_2d.m.
%   - Source slice switching happens inside the main 2D registration GUI.
%   - Saves per-source-slice Reg2D transformations.
%
% ASCII only
% MATLAB 2017b compatible

if nargin < 2 || isempty(forcedSourceFile)
    forcedSourceFile = '';
end

fprintf('\n--- Simple 2D Coronal Atlas Registration ---\n');
Reg2D = [];

%% ---------------------------------------------------------
% 0) CHECK
%% ---------------------------------------------------------
if nargin < 1 || isempty(studio) || ~isstruct(studio) || ...
        ~isfield(studio,'isLoaded') || ~studio.isLoaded
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
searchFolders = {rawFolder, analysedFolder, registrationDir};
searchFolders = searchFolders(~cellfun(@isempty, searchFolders));
searchFolders = searchFolders(cellfun(@(p) exist(p,'dir')==7, searchFolders));
searchFolders = unique(searchFolders,'stable');

directFiles = collectDirectFilesFromStudio(studio);
preferredSourceFile = '';

if ~isempty(forcedSourceFile) && exist(forcedSourceFile,'file') == 2
    preferredSourceFile = forcedSourceFile;
elseif isfield(studio,'brainImageFile') && ~isempty(studio.brainImageFile) && ...
        exist(studio.brainImageFile,'file') == 2
    preferredSourceFile = studio.brainImageFile;
end

if ~isempty(preferredSourceFile)
    sourceFile = preferredSourceFile;
    fprintf('Selected 2D coronal source file:\n%s\n', sourceFile);
else
    [sourceFiles, sourceLabels] = collectSourceFiles(searchFolders, rawFolder, analysedFolder, registrationDir, directFiles);
    if isempty(sourceFiles)
        error(['No suitable source files found.' char(10) ...
               'Checked RAW, ANALYSED, Visualization/Mask folders, and Registration2D.' char(10) ...
               'Expected underlay / overlay / brainImage / BrainOnly / anatomical source files.']);
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
% Important: for 3D / step-motor source files, do not pre-select only one
% slice in a popup. Load the stack and pass it to the main GUI.
%% ---------------------------------------------------------
[source2D, sourceInfo] = loadSourceAs2D(sourceFile, true);

fprintf('Source file  : %s\n', sourceFile);
fprintf('Source label : %s\n', sourceInfo.label);
fprintf('Source size  : %s\n', mat2str(size(source2D)));
if isfield(sourceInfo,'sourceWas3D') && sourceInfo.sourceWas3D
    fprintf('Source slices: %d | default source slice: %d\n', sourceInfo.sourceNSlices, sourceInfo.sourceSliceIndex);
end
if isfield(sourceInfo,'mask2D') && ~isempty(sourceInfo.mask2D)
    fprintf('Source mask  : attached [%s]\n', mat2str(size(sourceInfo.mask2D)));
end

%% ---------------------------------------------------------
% 5) BUILD FUNCTIONAL CANDIDATES
%% ---------------------------------------------------------
funcCandidates = buildFunctionalCandidates(studio, rawFolder, analysedFolder, registrationDir, sourceFile);
fprintf('Functional candidates found: %d\n', numel(funcCandidates.items));

%% ---------------------------------------------------------
% 6) LAUNCH ONE SOURCE-SLICE-AWARE GUI
%% ---------------------------------------------------------
initialReg = choosePreviousRegistrationIfWanted(registrationDir, sourceInfo);

Reg2D = registration_coronal_2d(atlas, source2D, sourceInfo, initialReg, ...
    registrationDir, funcCandidates, funcCandidates.defaultIndex, []);

if isempty(Reg2D)
    fprintf('No 2D registration returned.\n');
    return;
end

fprintf('--- Simple 2D Coronal Atlas Registration finished ---\n');
end


%% =======================================================================
% Functional candidates
%% =======================================================================
function funcCandidates = buildFunctionalCandidates(studio, rawRoot, analysedRoot, registrationRoot, sourceFile)

funcCandidates = struct();
funcCandidates.items = {};
funcCandidates.labels = {};
funcCandidates.defaultIndex = 1;

[studioItems, studioLabels, studioDefault] = collectStudioFunctionalCandidates(studio);
funcCandidates.items = [funcCandidates.items studioItems];
funcCandidates.labels = [funcCandidates.labels studioLabels];
if ~isempty(studioItems)
    funcCandidates.defaultIndex = studioDefault;
end

rootFolders = {rawRoot, analysedRoot, registrationRoot};
rootFolders = rootFolders(~cellfun(@isempty, rootFolders));
rootFolders = rootFolders(cellfun(@(p) exist(p,'dir')==7, rootFolders));
rootFolders = unique(rootFolders,'stable');

[fileList, fileLabels] = collectFunctionalFilesRecursive(rootFolders, rawRoot, analysedRoot, registrationRoot);
for k = 1:numel(fileList)
    fp = fileList{k};
    if strcmpi(normalizePathKey(fp), normalizePathKey(sourceFile))
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
    if isstruct(d) && isfield(d,'isLazy') && d.isLazy && ...
            isfield(d,'lazyFile') && exist(d.lazyFile,'file')==2
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
function directFiles = collectDirectFilesFromStudio(studio)
directFiles = {};
try
    if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
        lf = studio.loadedFile;
        if exist(lf,'file') == 2
            directFiles{end+1} = lf; %#ok<AGROW>
        elseif isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
            cand = fullfile(studio.loadedPath, lf);
            if exist(cand,'file') == 2
                directFiles{end+1} = cand; %#ok<AGROW>
            end
        end
    end
catch
end
try
    if isfield(studio,'brainImageFile') && ~isempty(studio.brainImageFile) && ...
            exist(studio.brainImageFile,'file') == 2
        directFiles{end+1} = studio.brainImageFile; %#ok<AGROW>
    end
catch
end
if isempty(directFiles), return; end
keys = cell(size(directFiles));
for i = 1:numel(directFiles)
    keys{i} = normalizePathKey(directFiles{i});
end
[~,ia] = unique(keys,'stable');
directFiles = directFiles(ia);
end


function [fileList, displayList] = collectSourceFiles(searchFolders, rawRoot, analysedRoot, registrationRoot, directFiles)
fileList = {};
displayList = {};

if nargin >= 5 && ~isempty(directFiles)
    for i = 1:numel(directFiles)
        fp = directFiles{i};
        if exist(fp,'file') ~= 2, continue; end
        if ~isAllowedSourceFile(fp), continue; end
        fileList{end+1} = fp; %#ok<AGROW>
        loc = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot);
        displayList{end+1} = makeSourceDisplayLabel(fp, ['LOADED: ' loc]); %#ok<AGROW>
    end
end

skipTerms = getSourceSkipFolderTerms();
for i = 1:numel(searchFolders)
    f = searchFolders{i};
    if isempty(f) || ~exist(f,'dir'), continue; end
    filesHere = collectFilesRecursiveFiltered(f, skipTerms);
    for k = 1:numel(filesHere)
        fp = filesHere{k};
        if ~isAllowedSourceFile(fp), continue; end
        fileList{end+1} = fp; %#ok<AGROW>
        loc = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot);
        displayList{end+1} = makeSourceDisplayLabel(fp, loc); %#ok<AGROW>
    end
end

if isempty(fileList), return; end
normKeys = cell(size(fileList));
for ii = 1:numel(fileList)
    normKeys{ii} = normalizePathKey(fileList{ii});
end
[~, ia] = unique(normKeys,'stable');
fileList = fileList(ia);
displayList = displayList(ia);
[fileList, displayList] = sortSourceEntries(fileList, displayList);
end


function displayLabel = makeSourceDisplayLabel(fp, locationLabel)
cls = classifySourceFile(fp);
displayLabel = [upper(cls) ': ' locationLabel];
end


function cls = classifySourceFile(fp)
[~,nm,~] = fileparts(fp);
nameL = lower(nm);
if ~isempty(strfind(nameL,'underlay')) || ~isempty(strfind(nameL,'atlasunderlay'))
    cls = 'UNDERLAY';
elseif ~isempty(strfind(nameL,'overlay'))
    cls = 'OVERLAY';
elseif ~isempty(strfind(nameL,'brainimage')) || ~isempty(strfind(nameL,'brainonly'))
    cls = 'BRAINIMAGE';
elseif ~isempty(strfind(nameL,'brainmask')) || ~isempty(strfind(nameL,'underlaymask')) || ...
        ~isempty(strfind(nameL,'overlaymask')) || ~isempty(strfind(nameL,'maskbundle')) || strcmpi(nameL,'mask')
    cls = 'MASK';
else
    cls = 'SOURCE';
end
end


function files = collectFilesRecursiveFiltered(rootDir, skipTerms)
files = {};
if isempty(rootDir) || ~exist(rootDir,'dir'), return; end

d = dir(rootDir);
for i = 1:numel(d)
    nm = d(i).name;
    fp = fullfile(rootDir, nm);
    if d(i).isdir
        if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
        if folderShouldBeSkipped(fp, skipTerms), continue; end
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
tf = pathHasAnyTerm(lower(folderPath), skipTerms);
end


function tf = isRecognizedSourceExtension(fp)
tf = isImageFile(fp) || isNiftiFile(fp) || endsWithLower(fp,'.mat');
end


function tf = isAllowedSourceFile(fp)
tf = false;
[folder, nm, ext] = fileparts(fp);
folderL = lower(folder);
nameL   = lower(nm);
fullL   = lower([nm ext]);

if folderShouldBeSkipped(folder, getSourceSkipFolderTerms()), return; end
if strcmpi(fullL,'transformation.mat') || strcmpi(fullL,'coronalregistration2d.mat') || strcmpi(fullL,'allen_brain_atlas.mat')
    return;
end
if nameHasAnyTerm(nameL, getSourceBadNameTerms()), return; end

nameLooksGood = nameHasAnyTerm(nameL, getSourceGoodNameTerms());
folderLooksGood = folderLooksSourceLike(folderL);

if isImageFile(fp) || isNiftiFile(fp)
    tf = nameLooksGood;
    return;
end
if strcmpi(ext,'.mat')
    tf = hasLikelySourceContent(fp) && (nameLooksGood || folderLooksGood);
end
end


function tf = hasLikelySourceContent(matFile)
tf = false;
try
    info = whos('-file', matFile);
    if isempty(info), return; end
    preferredNames = {'brainImage','savedUnderlayDisplay','savedUnderlayForReload','underlay','overlay', ...
        'underlayMask','overlayMask','brainMask','maskBundle','anatomical_reference', ...
        'anatomical_reference_raw','atlasUnderlay','atlasUnderlayRGB'};
    goodTerms = getSourceGoodNameTerms();
    badTerms  = getSourceBadNameTerms();
    for i = 1:numel(info)
        nm = info(i).name;
        nmL = lower(nm);
        sz = info(i).size;
        cl = info(i).class;
        if nameHasAnyTerm(nmL, badTerms), continue; end
        isPreferred = any(strcmp(nm, preferredNames)) || nameHasAnyTerm(nmL, goodTerms);
        if ~isPreferred, continue; end
        if strcmp(cl,'struct')
            tf = true;
            return;
        end
        if isNumericClassName(cl) && numel(sz) >= 2 && numel(sz) <= 3 && prod(double(sz)) > 100
            tf = true;
            return;
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
    if isempty(rootDir) || ~exist(rootDir,'dir'), continue; end
    filesHere = collectFilesRecursive(rootDir);
    for k = 1:numel(filesHere)
        fp = filesHere{k};
        if ~isAllowedFunctionalFile(fp), continue; end
        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot, registrationRoot); %#ok<AGROW>
    end
end
if isempty(fileList), return; end
normKeys = cell(size(fileList));
for i = 1:numel(fileList)
    normKeys{i} = normalizePathKey(fileList{i});
end
[~, ia] = unique(normKeys,'stable');
fileList = fileList(ia);
displayList = displayList(ia);
end


function files = collectFilesRecursive(rootDir)
files = {};
if isempty(rootDir) || ~exist(rootDir,'dir'), return; end

d = dir(rootDir);
for i = 1:numel(d)
    nm = d(i).name;
    if d(i).isdir
        if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
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
badFolderTerms = {[filesep 'qc' filesep], [filesep 'scm' filesep], [filesep 'video' filesep], ...
    [filesep 'videos' filesep], [filesep 'ppt' filesep], [filesep 'powerpoint' filesep]};
if pathHasAnyTerm(folderL, badFolderTerms), return; end
if strcmpi([nm ext],'Transformation.mat') || strcmpi([nm ext],'CoronalRegistration2D.mat') || strcmpi([nm ext],'allen_brain_atlas.mat')
    return;
end
badNameBits = {'atlasunderlay','brainonly','brainimage','coronalregistration2d','warpeddata', ...
    'transformation','underlay','overlay'};
if nameHasAnyTerm(nameLower, badNameBits), return; end
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
            if isNumericClassName(cl) && numel(sz) >= 2 && numel(sz) <= 4 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end
    for i = 1:numel(info)
        if strcmp(info(i).class,'struct')
            tf = true;
            return;
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
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = ['REG2D: ' rel];
        return;
    end
catch
end
try
    if ~isempty(rawRoot) && strncmpi(fullpath, rawRoot, numel(rawRoot))
        rel = fullpath(numel(rawRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = ['RAW: ' rel];
        return;
    end
catch
end
try
    if ~isempty(analysedRoot) && strncmpi(fullpath, analysedRoot, numel(analysedRoot))
        rel = fullpath(numel(analysedRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = ['ANA: ' rel];
        return;
    end
catch
end
s = fullpath;
end


%% =======================================================================
% Load source as 2D + full stack + attached mask if found
%% =======================================================================
function [img2D, info] = loadSourceAs2D(sourceFile, noSlicePopup)

if nargin < 2 || isempty(noSlicePopup)
    noSlicePopup = false;
end

info = struct();
info.path = sourceFile;
info.label = sourceFile;
info.baseLabel = sourceFile;
info.sourceSliceIndex = 1;
info.sourceWas3D = false;
info.sourceNSlices = 1;
info.sourceStack3D = [];
info.mask2D = [];
info.maskStack3D = [];

if endsWithLower(sourceFile,'.mat')
    S = load(sourceFile);
    [candNames, candData] = detect2DCandidatesFromMat(S);
    if isempty(candData)
        error('Selected MAT contains no suitable 2D or 3D source image candidate.');
    end

    jdx = pickPreferredSourceCandidate(candNames, candData);
    tmp = candData{jdx};
    info.baseLabel = candNames{jdx};

    [img2D, info.sourceSliceIndex, info.sourceWas3D, info.sourceStack3D, info.sourceNSlices] = ...
        choose2DSlice(tmp, info.baseLabel, noSlicePopup);

    info.label = makeCurrentSourceLabel(info.baseLabel, info.sourceSliceIndex, info.sourceWas3D);

    info.maskStack3D = chooseBestMaskStackForSource(S, tmp);
    if ~isempty(info.maskStack3D)
        info.mask2D = extractMaskSlice(info.maskStack3D, info.sourceSliceIndex, size(img2D));
    else
        info.mask2D = chooseBestMaskForSource(S, tmp, info.baseLabel, info.sourceSliceIndex, size(img2D));
    end

elseif isNiftiFile(sourceFile)
    [D, ~] = loadNiftiMaybeGz(sourceFile);
    info.baseLabel = sourceFile;
    [img2D, info.sourceSliceIndex, info.sourceWas3D, info.sourceStack3D, info.sourceNSlices] = ...
        choose2DSlice(double(D), sourceFile, noSlicePopup);
    info.label = makeCurrentSourceLabel(sourceFile, info.sourceSliceIndex, info.sourceWas3D);

elseif isImageFile(sourceFile)
    img2D = load2DImage(sourceFile);
    info.baseLabel = sourceFile;
    info.label = sourceFile;
    info.sourceSliceIndex = 1;
    info.sourceWas3D = false;
    info.sourceNSlices = 1;
    info.sourceStack3D = reshape(double(img2D), size(img2D,1), size(img2D,2), 1);

else
    error('Unsupported source file type.');
end

img2D = double(img2D);
img2D(~isfinite(img2D)) = 0;
end


function label = makeCurrentSourceLabel(baseLabel, sliceIdx, was3D)
if was3D
    label = sprintf('%s | source slice %03d', baseLabel, sliceIdx);
else
    label = baseLabel;
end
end


function jdx = pickPreferredSourceCandidate(candNames, candData)
jdx = [];
preferredNames = {'brainImage','maskBundle.brainImage','loadedMask.brainImage','savedUnderlayDisplay', ...
    'savedUnderlayForReload','underlay','overlay','anatomical_reference','anatomical_reference_raw', ...
    'atlasUnderlay','atlasUnderlayRGB'};
for pp = 1:numel(preferredNames)
    hit = find(strcmpi(candNames, preferredNames{pp}), 1);
    if ~isempty(hit)
        jdx = hit;
        break;
    end
end
if isempty(jdx)
    goodTerms = getSourceGoodNameTerms();
    for i = 1:numel(candNames)
        if nameHasAnyTerm(lower(candNames{i}), goodTerms)
            jdx = i;
            break;
        end
    end
end
if isempty(jdx)
    if numel(candData) > 1
        pretty = candNames;
        for k = 1:numel(candData)
            pretty{k} = sprintf('%s   [%s]', candNames{k}, joinDims(size(candData{k})));
        end
        [jdx, tf] = listdlg('PromptString','Select source variable:', 'SelectionMode','single', ...
            'ListString',pretty, 'ListSize',[860 420]);
        if ~tf
            error('Source selection cancelled.');
        end
    else
        jdx = 1;
    end
end
end


function [candNames, candData] = detect2DCandidatesFromMat(S)
fields = fieldnames(S);
candNames = {};
candData = {};
preferred = {'brainImage','savedUnderlayDisplay','savedUnderlayForReload','underlay','overlay', ...
    'anatomical_reference','anatomical_reference_raw','atlasUnderlay','atlasUnderlayRGB', ...
    'brainMask','underlayMask','overlayMask','maskBundle','mask','Mask'};
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
if isempty(candNames), return; end
[candNames, ia] = unique(candNames,'stable');
candData = candData(ia);
end


function [candNames, candData] = appendSourceCandidatesFromValue(candNames, candData, baseName, v)
if isstruct(v)
    nestedPreferred = {'brainImage','savedUnderlayDisplay','savedUnderlayForReload','underlay','overlay', ...
        'anatomical_reference','anatomical_reference_raw','atlasUnderlay','atlasUnderlayRGB', ...
        'brainMask','underlayMask','overlayMask','mask','Mask','Data','I'};
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
            if nameHasAnyTerm(fnL, getSourceBadNameTerms()), continue; end
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
if isempty(v), return; end
if isstruct(v) && isfield(v,'Data') && ~isempty(v.Data)
    v = v.Data;
end
if ~(isnumeric(v) || islogical(v)), return; end
D = double(v);
if ndims(D) == 2 || ndims(D) == 3
    if prod(double(size(D))) > 100
        candNames{end+1} = candName; %#ok<AGROW>
        candData{end+1} = D; %#ok<AGROW>
    end
end
end


function maskStack = chooseBestMaskStackForSource(S, selectedData)
maskStack = [];
fields = fieldnames(S);
preferredMaskNames = {'brainMask','underlayMask','overlayMask','brain_mask','mask','Mask'};
for i = 1:numel(preferredMaskNames)
    nm = preferredMaskNames{i};
    if isfield(S, nm)
        tmp = tryConvertMaskToStack(S.(nm), selectedData);
        if ~isempty(tmp)
            maskStack = tmp;
            return;
        end
    end
end
for i = 1:numel(fields)
    nm = fields{i};
    try
        m = S.(nm);
    catch
        continue;
    end
    nameLower = lower(nm);
    if isempty(strfind(nameLower,'mask')) && ~islogical(m)
        continue;
    end
    tmp = tryConvertMaskToStack(m, selectedData);
    if ~isempty(tmp)
        maskStack = tmp;
        return;
    end
end
end


function maskStack = tryConvertMaskToStack(m, selectedData)
maskStack = [];
if isempty(m), return; end
if isstruct(m) && isfield(m,'Data') && ~isempty(m.Data)
    m = m.Data;
end
if ~(isnumeric(m) || islogical(m)), return; end
m = logical(double(m) ~= 0);
if ndims(selectedData) == 2
    if ndims(m) == 2 && isequal(size(m), size(selectedData))
        maskStack = m;
        return;
    end
end
if ndims(selectedData) == 3
    if ndims(m) == 3 && isequal(size(m), size(selectedData))
        maskStack = m;
        return;
    end
    if ndims(m) == 2 && isequal(size(m), size(selectedData(:,:,1)))
        maskStack = m;
        return;
    end
end
end


function mask2D = chooseBestMaskForSource(S, selectedData, selectedLabel, selectedSliceIdx, targetSize) %#ok<INUSD>
mask2D = [];
if nargin < 4 || isempty(selectedSliceIdx), selectedSliceIdx = 1; end
if nargin < 5, targetSize = []; end
maskStack = chooseBestMaskStackForSource(S, selectedData);
if ~isempty(maskStack)
    mask2D = extractMaskSlice(maskStack, selectedSliceIdx, targetSize);
end
end


function mask2D = extractMaskSlice(maskStack, sliceIdx, targetSize)
mask2D = [];
if isempty(maskStack), return; end
if ndims(maskStack) == 2
    tmp = logical(maskStack);
elseif ndims(maskStack) == 3
    sliceIdx = max(1, min(size(maskStack,3), round(sliceIdx)));
    tmp = logical(squeeze(maskStack(:,:,sliceIdx)));
else
    return;
end
if nargin >= 3 && ~isempty(targetSize)
    if ~isequal(size(tmp), targetSize(1:2))
        return;
    end
end
mask2D = tmp;
end


function [img2D, sliceIdx, was3D, sourceStack3D, nSlices] = choose2DSlice(D, labelText, noSlicePopup)
if nargin < 3 || isempty(noSlicePopup), noSlicePopup = false; end
D = double(D);
D(~isfinite(D)) = 0;
sourceStack3D = [];
nSlices = 1;

if ndims(D) == 2
    img2D = D;
    sliceIdx = 1;
    was3D = false;
    sourceStack3D = reshape(D, size(D,1), size(D,2), 1);
    return;
end
if ndims(D) ~= 3
    error('Only 2D or 3D data supported for simple 2D registration.');
end

if size(D,3) == 3 && isLikelyRGBCandidate(labelText)
    img2D = rgbToGrayDouble(D);
    sliceIdx = 1;
    was3D = false;
    sourceStack3D = reshape(img2D, size(img2D,1), size(img2D,2), 1);
    nSlices = 1;
    return;
end

nSlices = size(D,3);
sourceStack3D = D;
defaultIdx = round(nSlices/2);

if noSlicePopup
    sliceIdx = defaultIdx;
    img2D = squeeze(D(:,:,sliceIdx));
    was3D = nSlices > 1;
    return;
end

[img2D, sliceIdx, tf] = choose2DSliceFromStack(D, labelText, defaultIdx);
if ~tf
    error('Slice selection cancelled.');
end
was3D = true;
end


function [img2D, sliceIdx, tf] = choose2DSliceFromStack(D, labelText, defaultIdx)
% Kept for compatibility. The updated workflow bypasses this popup.
tf = false;
img2D = [];
sliceIdx = [];
D = double(D);
D(~isfinite(D)) = 0;
if ndims(D) ~= 3
    error('choose2DSliceFromStack requires 3D data.');
end
nz = size(D,3);
if nargin < 3 || isempty(defaultIdx) || ~isfinite(defaultIdx)
    defaultIdx = round(nz/2);
end
idx = max(1, min(nz, round(defaultIdx)));

bg = [0.04 0.04 0.05];
panel = [0.09 0.09 0.10];
fg = [0.95 0.95 0.95];
blueBtn = [0.20 0.45 0.92];
greenBtn = [0.18 0.68 0.36];
redBtn = [0.82 0.24 0.24];

dlg = figure('Name','Choose Source Slice','Color',bg,'MenuBar','none','ToolBar','none', ...
    'NumberTitle','off','Resize','off','WindowStyle','modal','Position',[260 120 950 650], ...
    'CloseRequestFcn',@onCancel);

uicontrol('Style','text','Parent',dlg,'Units','normalized','Position',[0.04 0.925 0.92 0.055], ...
    'BackgroundColor',bg,'ForegroundColor',fg,'FontName','Arial','FontSize',19, ...
    'FontWeight','bold','HorizontalAlignment','left','String','Choose source slice for 2D coronal registration');
uicontrol('Style','text','Parent',dlg,'Units','normalized','Position',[0.04 0.875 0.92 0.035], ...
    'BackgroundColor',bg,'ForegroundColor',[0.72 0.72 0.76],'FontName','Arial','FontSize',11, ...
    'HorizontalAlignment','left','String',['Source: ' labelText]);
ax = axes('Parent',dlg,'Units','normalized','Position',[0.08 0.24 0.55 0.58],'Color','k');
axis(ax,'image'); axis(ax,'off');
ctrlPanel = uipanel('Parent',dlg,'Units','normalized','Position',[0.68 0.24 0.25 0.58], ...
    'BackgroundColor',panel,'ForegroundColor',fg,'Title','Slice control','FontSize',12,'FontWeight','bold');
hInfo = uicontrol('Style','text','Parent',ctrlPanel,'Units','normalized','Position',[0.08 0.78 0.84 0.12], ...
    'BackgroundColor',panel,'ForegroundColor',[0.75 0.90 1.00],'FontName','Arial','FontSize',13, ...
    'FontWeight','bold','HorizontalAlignment','center','String','');
hEdit = uicontrol('Style','edit','Parent',ctrlPanel,'Units','normalized','Position',[0.08 0.55 0.38 0.08], ...
    'BackgroundColor',[0.02 0.02 0.025],'ForegroundColor',fg,'FontName','Arial','FontSize',13, ...
    'FontWeight','bold','HorizontalAlignment','center','String',num2str(idx),'Callback',@onEdit);
hSlider = uicontrol('Style','slider','Parent',ctrlPanel,'Units','normalized','Position',[0.08 0.43 0.84 0.08], ...
    'Min',1,'Max',max(2,nz),'Value',idx,'SliderStep',[1/max(1,nz-1) 5/max(1,nz-1)],'Callback',@onSlider);
uicontrol('Style','pushbutton','Parent',ctrlPanel,'Units','normalized','Position',[0.08 0.30 0.84 0.09], ...
    'String','Middle Slice','BackgroundColor',blueBtn,'ForegroundColor','w','FontName','Arial', ...
    'FontWeight','bold','FontSize',11,'Callback',@onMiddle);
uicontrol('Style','pushbutton','Parent',dlg,'Units','normalized','Position',[0.52 0.055 0.22 0.07], ...
    'String','Use This Slice','BackgroundColor',greenBtn,'ForegroundColor','w','FontName','Arial', ...
    'FontWeight','bold','FontSize',13,'Callback',@onOK);
uicontrol('Style','pushbutton','Parent',dlg,'Units','normalized','Position',[0.76 0.055 0.17 0.07], ...
    'String','Cancel','BackgroundColor',redBtn,'ForegroundColor','w','FontName','Arial', ...
    'FontWeight','bold','FontSize',13,'Callback',@onCancel);
renderSlice();
uiwait(dlg);

    function renderSlice()
        idx = max(1, min(nz, round(idx)));
        A = squeeze(D(:,:,idx));
        A = rescale01Local(A);
        imagesc(ax, A);
        axis(ax,'image'); axis(ax,'off'); colormap(ax, gray(256));
        set(hInfo,'String',sprintf('Slice %d / %d', idx, nz));
        set(hEdit,'String',num2str(idx));
        set(hSlider,'Value',idx);
        drawnow;
    end
    function onEdit(~,~)
        v = round(str2double(get(hEdit,'String')));
        if ~isfinite(v), v = idx; end
        idx = max(1, min(nz, v));
        renderSlice();
    end
    function onSlider(src,~)
        idx = round(get(src,'Value'));
        renderSlice();
    end
    function onMiddle(~,~)
        idx = round(nz/2);
        renderSlice();
    end
    function onOK(~,~)
        sliceIdx = idx;
        img2D = squeeze(D(:,:,idx));
        tf = true;
        try, uiresume(dlg); catch, end
        try, delete(dlg); catch, end
    end
    function onCancel(~,~)
        sliceIdx = [];
        img2D = [];
        tf = false;
        try, uiresume(dlg); catch, end
        try, delete(dlg); catch, end
    end
end


function tf = isLikelyRGBCandidate(labelText)
labelL = lower(labelText);
tf = ~isempty(strfind(labelL,'rgb')) || ~isempty(strfind(labelL,'color'));
end


function G = rgbToGrayDouble(RGB)
RGB = double(RGB);
G = 0.2989*RGB(:,:,1) + 0.5870*RGB(:,:,2) + 0.1140*RGB(:,:,3);
end


%% =======================================================================
% Previous registration loader
%% =======================================================================
function initialReg = choosePreviousRegistrationIfWanted(registrationDir, sourceInfo)
initialReg = [];
regFiles = collectRegistration2DFiles(registrationDir);
if isempty(regFiles.files), return; end

msg = 'Load a previous 2D registration as starting point?';
try
    if isfield(sourceInfo,'sourceWas3D') && sourceInfo.sourceWas3D
        msg = sprintf(['Load a previous 2D registration as starting point?\n\n' ...
                       'Current default source slice: %d'], sourceInfo.sourceSliceIndex);
    end
catch
end
choice = questdlg(msg, 'Previous 2D Registration', 'Yes','No','No');
if ~strcmp(choice,'Yes'), return; end

[idxReg, tfReg] = listdlg('PromptString','Select previous 2D registration:', ...
    'SelectionMode','single','ListString',regFiles.labels,'ListSize',[980 460]);
if tfReg
    try
        tmp = load(regFiles.files{idxReg}, 'Reg2D');
        if isfield(tmp,'Reg2D')
            initialReg = tmp.Reg2D;
        end
    catch ME
        warning('Could not load previous Reg2D: %s', ME.message);
        initialReg = [];
    end
end
end


function out = collectRegistration2DFiles(registrationDir)
out = struct();
out.files = {};
out.labels = {};
if isempty(registrationDir) || ~exist(registrationDir,'dir'), return; end
allFiles = collectFilesRecursive(registrationDir);
for k = 1:numel(allFiles)
    fp = allFiles{k};
    [~,nm,ext] = fileparts(fp);
    if ~strcmpi(ext,'.mat'), continue; end
    nmL = lower(nm);
    isOld = ~isempty(strfind(nmL,'coronalregistration2d_slice'));
    isNew = ~isempty(strfind(nmL,'coronalregistration2d_source')) && ~isempty(strfind(nmL,'atlas'));
    if ~(isOld || isNew), continue; end
    out.files{end+1} = fp; %#ok<AGROW>
    out.labels{end+1} = makeRegistrationDisplayName(fp, registrationDir); %#ok<AGROW>
end
if isempty(out.files), return; end
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
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = ['REG2D: ' rel];
    end
catch
end
end


%% =======================================================================
% Source chooser GUI
%% =======================================================================
function [idx, tf] = chooseSourceFileDialog(sourceLabels)
idx = [];
tf = false;
if isempty(sourceLabels), return; end

bg = [0 0 0];
panelBG = [0.08 0.08 0.09];
editBG = [0.03 0.03 0.035];
fg = [1 1 1];
subFG = [0.82 0.82 0.82];
blueBtn = [0.20 0.45 0.92];
redBtn = [0.85 0.20 0.20];

listStrings = cell(size(sourceLabels));
for i = 1:numel(sourceLabels)
    [typ, loc] = splitSourceTypeAndLocation(sourceLabels{i});
    listStrings{i} = sprintf('[%-10s] %s', typ, loc);
end

figSel = figure('Name','Select Coronal Source Image','Color',bg,'MenuBar','none','ToolBar','none', ...
    'NumberTitle','off','Resize','off','WindowStyle','modal','Position',[120 60 1500 900], ...
    'CloseRequestFcn',@onCancel,'KeyPressFcn',@onKey);

uicontrol('Style','text','Parent',figSel,'Units','normalized','Position',[0.03 0.945 0.94 0.035], ...
    'BackgroundColor',bg,'ForegroundColor',fg,'HorizontalAlignment','left','FontName','Arial', ...
    'FontSize',19,'FontWeight','bold','String','Select coronal source image');
uicontrol('Style','text','Parent',figSel,'Units','normalized','Position',[0.03 0.905 0.94 0.030], ...
    'BackgroundColor',bg,'ForegroundColor',subFG,'HorizontalAlignment','left','FontName','Arial', ...
    'FontSize',12,'String','Recommended: underlay / overlay / brainImage / BrainOnly / anatomical reference from Mask Editor. Double-click or press Enter.');

mainPanel = uipanel('Parent',figSel,'Units','normalized','Position',[0.03 0.13 0.94 0.75], ...
    'BackgroundColor',panelBG,'ForegroundColor',fg,'Title','Source files','FontSize',13,'FontWeight','bold');

hList = uicontrol('Style','listbox','Parent',mainPanel,'Units','normalized','Position',[0.02 0.16 0.96 0.80], ...
    'String',listStrings,'Value',1,'BackgroundColor',[0 0 0],'ForegroundColor',[1 1 1], ...
    'FontName','Consolas','FontSize',15,'Max',1,'Min',0,'Callback',@onListSelect);

hDetail = uicontrol('Style','edit','Parent',mainPanel,'Units','normalized','Position',[0.02 0.02 0.96 0.115], ...
    'Max',2,'Min',0,'Enable','inactive','HorizontalAlignment','left','BackgroundColor',editBG, ...
    'ForegroundColor',[0.78 0.92 1.00],'FontName','Consolas','FontSize',12,'String','');

uicontrol('Style','pushbutton','Parent',figSel,'Units','normalized','Position',[0.55 0.035 0.18 0.065], ...
    'String','Use Selected','BackgroundColor',blueBtn,'ForegroundColor','w','FontWeight','bold','FontSize',13,'Callback',@onOK);
uicontrol('Style','pushbutton','Parent',figSel,'Units','normalized','Position',[0.76 0.035 0.17 0.065], ...
    'String','Cancel','BackgroundColor',redBtn,'ForegroundColor','w','FontWeight','bold','FontSize',13,'Callback',@onCancel);

updateDetail();
uiwait(figSel);

    function onListSelect(~,~)
        updateDetail();
        try
            if strcmpi(get(figSel,'SelectionType'),'open')
                onOK();
            end
        catch
        end
    end
    function updateDetail(~,~)
        try
            v = get(hList,'Value');
            v = max(1, min(numel(sourceLabels), v));
            [typ, loc] = splitSourceTypeAndLocation(sourceLabels{v});
            set(hDetail,'String',sprintf('Type: %s\nPath: %s', typ, loc));
        catch
        end
    end
    function onOK(~,~)
        try, idx = get(hList,'Value'); catch, idx = 1; end
        idx = max(1, min(numel(sourceLabels), idx));
        tf = true;
        try, uiresume(figSel); catch, end
        try, delete(figSel); catch, end
    end
    function onCancel(~,~)
        idx = [];
        tf = false;
        try, uiresume(figSel); catch, end
        try, delete(figSel); catch, end
    end
    function onKey(~, ev)
        try
            if strcmpi(ev.Key,'return') || strcmpi(ev.Key,'enter')
                onOK();
            elseif strcmpi(ev.Key,'escape')
                onCancel();
            end
        catch
        end
    end
end


function [typ, loc] = splitSourceTypeAndLocation(s)
typ = 'SOURCE';
loc = s;
known = {'UNDERLAY','OVERLAY','BRAINIMAGE','MASK','SOURCE'};
for i = 1:numel(known)
    p = [known{i} ': '];
    if startsWithLocal(s, p)
        typ = known{i};
        loc = s(numel(p)+1:end);
        return;
    end
end
end


%% =======================================================================
% Generic utilities
%% =======================================================================
function out = inferAnalysedFromRaw(rawFolder)
out = '';
if isempty(rawFolder), return; end
cand = strrep(rawFolder, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
    return;
end
cand = strrep(rawFolder, [filesep 'rawdata' filesep], [filesep 'analyseddata' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
end
end


function tf = endsWithLower(str, suffix)
str = lower(char(str));
suffix = lower(char(suffix));
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
    if isempty(d), error('Failed to gunzip: %s', f); end
    niiFile = fullfile(tmpDir, d(1).name);
    info = niftiinfo(niiFile);
    D = niftiread(info);
    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions) >= 3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end
    try, rmdir(tmpDir,'s'); catch, end
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
f = lower(char(f));
tf = endsWithLower(f,'.png') || endsWithLower(f,'.jpg') || endsWithLower(f,'.jpeg') || ...
     endsWithLower(f,'.tif') || endsWithLower(f,'.tiff') || endsWithLower(f,'.bmp');
end


function tf = isNiftiFile(f)
f = lower(char(f));
tf = endsWithLower(f,'.nii') || endsWithLower(f,'.nii.gz');
end


function I = load2DImage(f)
I = imread(f);
if ndims(I) == 3
    I = double(I);
    I = 0.2989*I(:,:,1) + 0.5870*I(:,:,2) + 0.1140*I(:,:,3);
else
    I = double(I);
end
end


function s = joinDims(sz)
if isempty(sz), s = ''; return; end
s = num2str(sz(1));
for k = 2:numel(sz)
    s = [s 'x' num2str(sz(k))]; %#ok<AGROW>
end
end


function tf = startsWithLocal(s, prefix)
if numel(s) < numel(prefix)
    tf = false;
    return;
end
tf = strcmpi(s(1:numel(prefix)), prefix);
end


function k = normalizePathKey(p)
try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(p);
end
p = strrep(p, '/', filesep);
p = strrep(p, '\\', filesep);
if ispc
    p = lower(p);
end
k = p;
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
    typeScore = 50;
    if ~isempty(strfind(s,'brainimage:')) %#ok<STREMP>
        typeScore = 1;
    elseif ~isempty(strfind(s,'underlay:')) %#ok<STREMP>
        typeScore = 2;
    elseif ~isempty(strfind(s,'overlay:')) %#ok<STREMP>
        typeScore = 3;
    elseif ~isempty(strfind(s,'mask:')) %#ok<STREMP>
        typeScore = 4;
    elseif ~isempty(strfind(s,'source:')) %#ok<STREMP>
        typeScore = 5;
    end
    locScore = 50;
    if ~isempty(strfind(s,'loaded:')) %#ok<STREMP>
        locScore = 1;
    elseif ~isempty(strfind(s,'raw:')) %#ok<STREMP>
        locScore = 2;
    elseif ~isempty(strfind(s,'ana:')) %#ok<STREMP>
        locScore = 3;
    elseif ~isempty(strfind(s,'reg2d:')) %#ok<STREMP>
        locScore = 4;
    end
    prio(i) = typeScore * 100 + locScore;
end
[~, ord] = sort(prio, 'ascend');
fileListOut = fileList(ord);
displayListOut = displayList(ord);
end


function tf = pathHasAnyTerm(pathStr, terms)
tf = false;
pathStr = lower(pathStr);
for i = 1:numel(terms)
    if ~isempty(strfind(pathStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end
end


function tf = nameHasAnyTerm(nameStr, terms)
tf = false;
nameStr = lower(nameStr);
for i = 1:numel(terms)
    if ~isempty(strfind(nameStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end
end


function tf = folderLooksSourceLike(folderL)
terms = {[filesep 'visualization'], [filesep 'visualisation'], [filesep 'mask'], [filesep 'masks'], [filesep 'registration2d']};
tf = pathHasAnyTerm(folderL, terms);
end


function terms = getSourceGoodNameTerms()
terms = {'brainonly','brainimage','brain_image','brain_mask','brainmask','underlay','overlay', ...
    'underlaymask','overlaymask','maskbundle','anatomical_reference','anatomical','anatomy', ...
    'reference','histology','vascular','regions','atlasunderlay','sourceimage'};
end


function terms = getSourceBadNameTerms()
terms = {'framerate','frame_rate','framerejection','frame_rejection','rotation','translation','spike', ...
    'dvars','motion','pca','ica','despike','scrub','qc','rejected','rejection','timeseries', ...
    'trace','plot','powerpoint','warpeddata','coronalregistration2d','transformation','globalmean', ...
    'burst','cnr','snr','tsnr','intensity','spectrum','histogram','heatmap','video'};
end


function terms = getSourceSkipFolderTerms()
terms = {[filesep 'qc' filesep], [filesep 'framerate' filesep], [filesep 'frame_rate' filesep], ...
    [filesep 'scm' filesep], [filesep 'roi' filesep], [filesep 'video' filesep], [filesep 'videos' filesep], ...
    [filesep 'ppt' filesep], [filesep 'powerpoint' filesep], [filesep 'presentation' filesep], ...
    [filesep 'presentations' filesep], [filesep 'temp' filesep], [filesep 'tmp' filesep], [filesep 'logs' filesep]};
end


function A = rescale01Local(A)
A = double(A);
A(~isfinite(A)) = 0;
mn = min(A(:));
mx = max(A(:));
if mx > mn
    A = (A - mn) ./ (mx - mn);
else
    A = zeros(size(A));
end
end


function tf = isNumericClassName(cl)
tf = strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
     strcmp(cl,'uint8') || strcmp(cl,'int16') || strcmp(cl,'logical');
end
