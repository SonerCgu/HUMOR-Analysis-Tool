function Transf = coreg(studio)
% =========================================================
% fUSI Studio - Atlas Coregistration
% STRICT paper-faithful version (no geometry manipulation)
%
% UPDATED (ASCII ONLY - Windows-1252 safe):
%   - Anatomy selection searches BOTH:
%       * RAW dataset folder (studio.loadedPath) + common subfolders
%       * ANALYSED folder (studio.exportPath OR inferred AnalysedData) + Visualization
%   - Allows selecting anatomy from:
%       * MAT struct with .Data
%       * MAT numeric/logical 2D/3D arrays (e.g. brainMask)
%       * NIfTI (.nii / .nii.gz)
%       * 2D image files (.png/.jpg/.tif/...)
%
% Saves/loads Transformation.mat in the RAW dataset folder.
% MATLAB 2017b compatible
% =========================================================

fprintf('\n--- fUSI Atlas Coregistration ---\n');

Transf = [];

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

% Work inside RAW dataset folder so Transformation.mat lands there
oldDir = pwd;
cleanupDir = onCleanup(@() cd(oldDir)); %#ok<NASGU>
cd(rawFolder);

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
    error('allen_brain_atlas.mat not found on path or next to coreg.m.');
end

SAtlas = load(atlasPath,'atlas');
if ~isfield(SAtlas,'atlas')
    error('Loaded allen_brain_atlas.mat but variable "atlas" is missing.');
end
atlas = SAtlas.atlas;

%% ---------------------------------------------------------
% 2) SELECT ANATOMY SOURCE (RAW + ANALYSED + VISUALIZATION)
%% ---------------------------------------------------------
analysedFolder = '';
if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
    analysedFolder = studio.exportPath;
end
if isempty(analysedFolder)
    analysedFolder = inferAnalysedFromRaw(rawFolder);
end

searchFolders = { ...
    rawFolder, ...
    fullfile(rawFolder,'Visualization'), ...
    fullfile(rawFolder,'visualization'), ...
    fullfile(rawFolder,'Visualisation'), ...
    fullfile(rawFolder,'Mask'), ...
    fullfile(rawFolder,'Masks'), ...
    analysedFolder, ...
    fullfile(analysedFolder,'Visualization'), ...
    fullfile(analysedFolder,'visualization'), ...
    fullfile(analysedFolder,'Visualisation'), ...
    fullfile(analysedFolder,'Mask'), ...
    fullfile(analysedFolder,'Masks') ...
    };

% keep only existing dirs + remove empties + deduplicate
searchFolders = searchFolders(~cellfun(@isempty, searchFolders));
searchFolders = searchFolders(cellfun(@(p) exist(p,'dir')==7, searchFolders));
searchFolders = unique(searchFolders,'stable');

[fileList, displayList] = collectAnatomyFiles(searchFolders, rawFolder, analysedFolder);

if isempty(fileList)
    error('No anatomy candidates found in RAW or ANALYSED folders.');
end

[idx, tf] = listdlg( ...
    'PromptString','Select anatomical source (RAW/ANA, MAT/NIfTI/image/mask):', ...
    'SelectionMode','single', ...
    'ListString',displayList, ...
    'ListSize',[760 380]);

if ~tf
    fprintf('Coregistration cancelled.\n');
    return;
end

anatomyFile = fileList{idx};

%% ---------------------------------------------------------
% 3) LOAD + DETECT ANATOMY VOLUME
%% ---------------------------------------------------------
anatomic = [];

if endsWithLower(anatomyFile,'.mat')
    S = load(anatomyFile);
    [candNames, candStruct] = detectAnatomyCandidatesFromMat(S);

    if isempty(candStruct)
        error('Selected MAT contains no usable anatomy: no struct.Data and no numeric/logical 2D/3D arrays.');
    end

    if numel(candStruct) > 1
        pretty = candNames;
        for k=1:numel(candStruct)
            try
                sz = size(candStruct{k}.Data);
                pretty{k} = sprintf('%s   [%s]', candNames{k}, joinDims(sz));
            catch
            end
        end

        [jdx, tf2] = listdlg( ...
            'PromptString','Multiple anatomy candidates found. Select one:', ...
            'SelectionMode','single', ...
            'ListString',pretty, ...
            'ListSize',[820 360]);

        if ~tf2
            fprintf('Coregistration cancelled.\n');
            return;
        end

        anatomic = candStruct{jdx};
    else
        anatomic = candStruct{1};
    end

elseif endsWithLower(anatomyFile,'.nii') || endsWithLower(anatomyFile,'.nii.gz')
    [D, vox] = loadNiftiMaybeGz(anatomyFile);
    anatomic = struct();
    anatomic.Data = double(D);
    if isempty(vox), vox = [1 1 1]; end
    anatomic.VoxelSize = vox;

elseif isImageFile(anatomyFile)
    V = load2DImageAsVolume(anatomyFile);
    anatomic = struct();
    anatomic.Data = double(V);
    anatomic.VoxelSize = [1 1 1];

else
    error('Unsupported file type: %s', anatomyFile);
end

% Validate
if ~isfield(anatomic,'Data') || isempty(anatomic.Data) || ~isnumeric(anatomic.Data)
    error('Selected anatomy does not contain valid numeric Data.');
end

% Ensure 3D
if ndims(anatomic.Data) == 2
    anatomic.Data = reshape(anatomic.Data, size(anatomic.Data,1), size(anatomic.Data,2), 1);
end

% Ensure VoxelSize exists
if ~isfield(anatomic,'VoxelSize') || isempty(anatomic.VoxelSize)
    anatomic.VoxelSize = [1 1 1];
end

fprintf('Anatomy source: %s\n', anatomyFile);
fprintf('Anatomy size  : %s\n', mat2str(size(anatomic.Data)));
fprintf('VoxelSize     : %s\n', mat2str(anatomic.VoxelSize));

%% ---------------------------------------------------------
% 4) OPTIONAL LOAD PREVIOUS TRANSFORMATION (RAW folder)
%% ---------------------------------------------------------
usePrevious = false;
prevFile = fullfile(rawFolder,'Transformation.mat');

if exist(prevFile,'file')
    choice = questdlg( ...
        'Load previous Transformation.mat from RAW dataset folder?', ...
        'Previous Transformation', ...
        'Yes','No','No');

    if strcmp(choice,'Yes')
        tmp = load(prevFile,'Transf');
        if isfield(tmp,'Transf') && isstruct(tmp.Transf) && isfield(tmp.Transf,'M')
            usePrevious = true;
            Transf = tmp.Transf;
        else
            warning('Transformation.mat found but variable "Transf" is missing/invalid. Starting fresh.');
            usePrevious = false;
            Transf = [];
        end
    end
end

%% ---------------------------------------------------------
% 5) LAUNCH registration_ccf GUI
%% ---------------------------------------------------------
fprintf('Launching registration_ccf GUI...\n');

if usePrevious
    R = registration_ccf(atlas, anatomic, Transf);
else
    R = registration_ccf(atlas, anatomic);
end

% Listen to saves coming from the GUI (if registration_ccf defines the event)
try
    addlistener(R,'transformSaved', @(src,evt)onTransformSaved(studio, prevFile)); %#ok<NASGU>
catch
end

% Wait until GUI closes
try
    if isfield(R,'H') && isstruct(R.H) && isfield(R.H,'figure1') && isgraphics(R.H.figure1)
        waitfor(R.H.figure1);
    elseif isprop(R,'H') && isfield(R.H,'figure1') && isgraphics(R.H.figure1)
        waitfor(R.H.figure1);
    end
catch
end

%% ---------------------------------------------------------
% 6) RETURN TRANSFORMATION
%% ---------------------------------------------------------
if exist(prevFile,'file')
    tmp = load(prevFile,'Transf');
    if isfield(tmp,'Transf')
        Transf = tmp.Transf;
    else
        warning('Transformation.mat exists but does not contain Transf.');
        Transf = [];
    end
else
    warning('Transformation.mat not found after registration.');
    Transf = [];
end

fprintf('--- Coregistration finished ---\n');

end


%% =======================================================================
% Helper: log + notify studio on save
%% =======================================================================
function onTransformSaved(studio, transfPath)

msg = sprintf('Saved Transformation.mat: %s', transfPath);

fprintf('[COREG] %s\n', msg);

% Try to write into Studio log (robust)
try
    if isfield(studio,'addLog') && isa(studio.addLog,'function_handle')
        studio.addLog(msg);
        return;
    end
end

try
    if isfield(studio,'log') && isa(studio.log,'function_handle')
        studio.log(msg);
        return;
    end
end

try
    if isfield(studio,'logHandle') && isgraphics(studio.logHandle)
        old = get(studio.logHandle,'String');
        if ischar(old), old = {old}; end
        ts = datestr(now,'HH:MM:SS');
        newLine = sprintf('[%s] %s', ts, msg);
        set(studio.logHandle,'String',[old; {newLine}]);
        drawnow limitrate nocallbacks;
        return;
    end
end

end


%% =======================================================================
% File collection helpers
%% =======================================================================
function [fileList, displayList] = collectAnatomyFiles(searchFolders, rawRoot, analysedRoot)

fileList = {};
displayList = {};

for i = 1:numel(searchFolders)
    f = searchFolders{i};
    if isempty(f) || ~exist(f,'dir'), continue; end

    % MAT
    d = dir(fullfile(f,'*.mat'));
    for k = 1:numel(d)
        fp = fullfile(f, d(k).name);

        if strcmpi(d(k).name,'Transformation.mat'), continue; end
        if strcmpi(d(k).name,'allen_brain_atlas.mat'), continue; end

        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot); %#ok<AGROW>
    end

    % NIfTI
    d = dir(fullfile(f,'*.nii'));
    for k = 1:numel(d)
        fp = fullfile(f, d(k).name);
        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot); %#ok<AGROW>
    end

    d = dir(fullfile(f,'*.nii.gz'));
    for k = 1:numel(d)
        fp = fullfile(f, d(k).name);
        fileList{end+1} = fp; %#ok<AGROW>
        displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot); %#ok<AGROW>
    end

    % Images
    exts = {'*.png','*.jpg','*.jpeg','*.tif','*.tiff','*.bmp'};
    for e = 1:numel(exts)
        d = dir(fullfile(f, exts{e}));
        for k = 1:numel(d)
            fp = fullfile(f, d(k).name);
            fileList{end+1} = fp; %#ok<AGROW>
            displayList{end+1} = makeDisplayName(fp, rawRoot, analysedRoot); %#ok<AGROW>
        end
    end
end

% de-dup by display name (stable)
[displayList, ia] = unique(displayList, 'stable');
fileList = fileList(ia);

end


function s = makeDisplayName(fullpath, rawRoot, analysedRoot)
% Prefix so you see origin instantly.
try
    if ~isempty(rawRoot) && strncmpi(fullpath, rawRoot, numel(rawRoot))
        rel = fullpath(numel(rawRoot)+1:end);
        if ~isempty(rel) && (rel(1)==filesep), rel = rel(2:end); end
        s = ['RAW: ' rel];
        return;
    end
catch
end

try
    if ~isempty(analysedRoot) && strncmpi(fullpath, analysedRoot, numel(analysedRoot))
        rel = fullpath(numel(analysedRoot)+1:end);
        if ~isempty(rel) && (rel(1)==filesep), rel = rel(2:end); end
        s = ['ANA: ' rel];
        return;
    end
catch
end

s = fullpath;
end


function out = inferAnalysedFromRaw(rawFolder)
out = '';
if isempty(rawFolder), return; end

cand = strrep(rawFolder, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand; return;
end

cand = strrep(rawFolder, [filesep 'rawdata' filesep], [filesep 'analyseddata' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand; return;
end
end


%% =======================================================================
% Data loading helpers
%% =======================================================================
function tf = endsWithLower(str, suffix)
str = lower(str);
suffix = lower(suffix);
if numel(str) < numel(suffix)
    tf = false; return;
end
tf = strcmp(str(end-numel(suffix)+1:end), suffix);
end


function [candNames, candStruct] = detectAnatomyCandidatesFromMat(S)
fields = fieldnames(S);
candNames = {};
candStruct = {};

% voxel size hint if present
voxHint = [];
try
    if isfield(S,'VoxelSize'), voxHint = S.VoxelSize; end
    if isempty(voxHint) && isfield(S,'meta') && isstruct(S.meta) && isfield(S.meta,'VoxelSize')
        voxHint = S.meta.VoxelSize;
    end
catch
end
if isempty(voxHint), voxHint = [1 1 1]; end

for i = 1:numel(fields)
    v = S.(fields{i});

    % Case A: struct with Data
    if isstruct(v) && isfield(v,'Data') && ~isempty(v.Data) && isnumeric(v.Data)
        tmp = v;
        tmp.Data = double(tmp.Data);
        if ~isfield(tmp,'VoxelSize') || isempty(tmp.VoxelSize)
            tmp.VoxelSize = voxHint;
        end
        candNames{end+1}  = fields{i}; %#ok<AGROW>
        candStruct{end+1} = tmp;       %#ok<AGROW>
        continue;
    end

    % Case B: numeric/logical 2D/3D array (mask)
    if (isnumeric(v) || islogical(v)) && ~isempty(v)
        d = ndims(v);
        if d==2 || d==3
            tmp = struct();
            tmp.Data = double(v);
            if d==2
                tmp.Data = reshape(tmp.Data, size(tmp.Data,1), size(tmp.Data,2), 1);
            end
            tmp.VoxelSize = voxHint;
            candNames{end+1}  = fields{i}; %#ok<AGROW>
            candStruct{end+1} = tmp;       %#ok<AGROW>
        end
    end
end

end


function [D, vox] = loadNiftiMaybeGz(f)
vox = [];
isGz = (numel(f)>=7 && strcmpi(f(end-6:end),'.nii.gz'));

if isGz
    tmpDir = tempname; mkdir(tmpDir);
    gunzip(f, tmpDir);
    d = dir(fullfile(tmpDir,'*.nii'));
    if isempty(d), error('Failed to gunzip: %s', f); end
    niiFile = fullfile(tmpDir, d(1).name);

    info = niftiinfo(niiFile);
    D = niftiread(info);

    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions)>=3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end

    try, rmdir(tmpDir,'s'); catch, end
else
    info = niftiinfo(f);
    D = niftiread(info);
    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions)>=3
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


function V = load2DImageAsVolume(f)
I = imread(f);

% Convert to grayscale without requiring IPT
if ndims(I) == 3
    I = double(I);
    I = (I(:,:,1) + I(:,:,2) + I(:,:,3)) / 3;
else
    I = double(I);
end

% Normalize to [0..1]
mn = min(I(:)); mx = max(I(:));
if mx > mn
    I = (I - mn) ./ (mx - mn);
end

V = reshape(I, size(I,1), size(I,2), 1);
end


function s = joinDims(sz)
% MATLAB 2017b-safe axbxc formatting
if isempty(sz), s = ''; return; end
s = num2str(sz(1));
for k = 2:numel(sz)
    s = [s 'x' num2str(sz(k))]; %#ok<AGROW>
end
end