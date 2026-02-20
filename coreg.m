function Transf = coreg(studio)
% =========================================================
% fUSI Studio – Atlas Coregistration
% STRICT paper-faithful version (no geometry manipulation)
%
% - Select .mat anatomy from studio.loadedPath via popup
% - Robustly detects the anatomy struct (with Data field)
% - Optionally loads previous Transformation.mat
% - Launches registration_ccf GUI (updated version)
% - Logs when Transformation.mat is saved (transformSaved event)
% - Saves/loads Transformation.mat in the dataset folder (studio.loadedPath)
%
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

% Work inside dataset folder so Transformation.mat lands there
oldDir = pwd;
cleanupDir = onCleanup(@() cd(oldDir));
cd(studio.loadedPath);

%% ---------------------------------------------------------
% 1) LOAD ATLAS (exactly like paper)
%% ---------------------------------------------------------
atlasFile = 'allen_brain_atlas.mat';

atlasPath = which(atlasFile);
if isempty(atlasPath)
    % also try same folder as this coreg.m
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
% 2) SELECT ANATOMY FILE FROM DATASET FOLDER
%% ---------------------------------------------------------
rawFolder = studio.loadedPath;
matFiles  = dir(fullfile(rawFolder,'*.mat'));

if isempty(matFiles)
    error('No .mat files found in loaded dataset folder: %s', rawFolder);
end

fileNames = {matFiles.name};

[idx, tf] = listdlg( ...
    'PromptString','Select anatomical MAT file:', ...
    'SelectionMode','single', ...
    'ListString',fileNames, ...
    'ListSize',[420 320]);

if ~tf
    fprintf('Coregistration cancelled.\n');
    return;
end

anatomyFile = fullfile(rawFolder, fileNames{idx});

%% ---------------------------------------------------------
% 3) DETECT ANATOMY STRUCT
%% ---------------------------------------------------------
S = load(anatomyFile);

% Find ALL candidate structs with a Data field (and preferably VoxelSize)
fields = fieldnames(S);
candNames = {};
candStruct = {};

for i = 1:numel(fields)
    v = S.(fields{i});
    if isstruct(v) && isfield(v,'Data')
        candNames{end+1}  = fields{i}; %#ok<AGROW>
        candStruct{end+1} = v;        %#ok<AGROW>
    end
end

if isempty(candStruct)
    error('Selected file does not contain any struct with field "Data".');
end

% If multiple candidates exist, let user pick the correct one
if numel(candStruct) > 1
    pretty = candNames;
    for k=1:numel(candStruct)
        try
            sz = size(candStruct{k}.Data);
            pretty{k} = sprintf('%s   [%s]', candNames{k}, strjoin(string(sz),'x'));
        catch
        end
    end

    [jdx, tf2] = listdlg( ...
        'PromptString','Multiple anatomy structs found. Select one:', ...
        'SelectionMode','single', ...
        'ListString',pretty, ...
        'ListSize',[520 300]);

    if ~tf2
        fprintf('Coregistration cancelled.\n');
        return;
    end

    anatomic = candStruct{jdx};
else
    anatomic = candStruct{1};
end

% Validate Data
if ~isfield(anatomic,'Data') || isempty(anatomic.Data) || ~isnumeric(anatomic.Data)
    error('Anatomy struct has no valid numeric "Data".');
end

% Ensure VoxelSize exists
if ~isfield(anatomic,'VoxelSize') || isempty(anatomic.VoxelSize)
    anatomic.VoxelSize = [1 1 1];
end

% Force double like original code typically expects
anatomic.Data = double(anatomic.Data);

fprintf('Anatomy file: %s\n', anatomyFile);
fprintf('Anatomy size: %s\n', mat2str(size(anatomic.Data)));

%% ---------------------------------------------------------
% 4) OPTIONAL LOAD PREVIOUS TRANSFORMATION (from dataset folder)
%% ---------------------------------------------------------
usePrevious = false;
prevFile = fullfile(rawFolder,'Transformation.mat');

if exist(prevFile,'file')
    choice = questdlg( ...
        'Load previous Transformation.mat from this dataset folder?', ...
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

% Create GUI object
if usePrevious
    R = registration_ccf(atlas, anatomic, Transf);
else
    R = registration_ccf(atlas, anatomic);
end

% Listen to saves coming from the GUI (registration_ccf now notifies 'transformSaved')
try
    addlistener(R,'transformSaved', @(src,evt)onTransformSaved(studio, prevFile));
catch
    % If older registration_ccf without event, ignore
end

% Wait until GUI closes
try
    if isfield(R,'H') && isstruct(R.H) && isfield(R.H,'figure1') && isgraphics(R.H.figure1)
        waitfor(R.H.figure1);
    else
        % fallback: wait for any figure handle in object
        if isprop(R,'H') && isfield(R.H,'figure1') && isgraphics(R.H.figure1)
            waitfor(R.H.figure1);
        end
    end
catch
    % last resort: do nothing
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

% Console
fprintf('[COREG] %s\n', msg);

% Try to write into Studio log (robust against different implementations)
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
        % common pattern: a uicontrol editbox/listbox
        old = get(studio.logHandle,'String');
        if ischar(old), old = {old}; end
        ts = datestr(now,'HH:MM:SS');
        newLine = sprintf('[%s] %s', ts, msg);
        set(studio.logHandle,'String',[old; {newLine}]);
        drawnow limitrate nocallbacks;
        return;
    end
end

% If nothing matched, do nothing (avoid crashing)
end
