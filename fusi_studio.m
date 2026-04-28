function fusi_studio
clc;

%% =========================================================
%  SECTION A - INTERNAL STATE & GUI CONSTRUCTION - Update
% =========================================================
studio = struct();
studio.datasets = struct();
studio.activeDataset = '';
studio.meta = [];
studio.isLoaded = false;
studio.loadedFile = '';
studio.loadedPath = '';
studio.loadedName = '';
studio.exportPath = '';
studio.atlasTransform = [];
studio.atlasTransformFile = '';

studio.atlasReg2D = [];
studio.atlasReg2DFile = '';
studio.atlasRegistrationMode = '';
studio.allButtons = {};
studio.figure = [];
studio.publicationReady = [];
studio.publicationReadyNote = '';
studio.publicationReadyTime = '';

studio.mask = [];
studio.maskIsInclude = true;
studio.brainMask = [];
studio.brainImageFile = '';
studio.anatomicalReferenceRaw = [];
studio.anatomicalReference = [];
studio.anatomicalReferenceIsDisplayReady = false;
studio.anatomicalReferenceFile = '';

% FC / atlas / registration helper path
studio.registrationPath = '';

studio.pipeline = struct( ...
    'loadDone', false, ...
    'qcDone', false, ...
    'preprocDone', false, ...
    'pscDone', false, ...
    'visualDone', false);

%% =========================================================
%  FIGURE WINDOW
% =========================================================
fig = figure( ...
    'Name','HUMoR Analysis Tool', ...
    'Color',[0.05 0.05 0.05], ...
    'Units','normalized', ...
    'Position',[0 0 1 1], ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Resize','on', ...
    'CloseRequestFcn',@onCloseStudio);

try
    set(fig,'WindowState','maximized');
catch
end

studio.figure = fig;
guidata(fig, studio);

%% =========================================================
%  TITLE
% =========================================================
uicontrol(fig,'Style','text', ...
    'String','HUMoR Analysis Tool', ...
    'Units','normalized', ...
    'Position',[0.61 0.945 0.26 0.045], ...
    'FontSize',32, ...
    'FontWeight','bold', ...
    'ForegroundColor',[0.95 0.95 0.95], ...
    'BackgroundColor',[0.05 0.05 0.05], ...
    'HorizontalAlignment','center');

%% =========================================================
%  LEFT PANEL
% =========================================================
leftWidth = 0.45;
leftPanel = uipanel(fig, ...
    'Units','normalized', ...
    'Position',[0.03 0.095 leftWidth 0.875], ...
    'BackgroundColor',[0.07 0.07 0.07], ...
    'BorderType','none');

%% =========================================================
%  LOG PANEL
% =========================================================
logPanel = uipanel(fig, ...
    'Title','Studio Log', ...
    'Units','normalized', ...
    'Position',[0.50 0.18 0.47 0.71], ...
    'BackgroundColor',[0.07 0.07 0.07], ...
    'ForegroundColor','w', ...
    'FontSize',18, ...
    'FontWeight','bold');

activeDatasetText = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.50 0.905 0.39 0.04], ...
    'FontSize',14, ...
    'FontWeight','bold', ...
    'ForegroundColor',[0.3 0.9 0.3], ...
    'BackgroundColor',[0.05 0.05 0.05], ...
    'HorizontalAlignment','left', ...
    'String','ACTIVE DATASET: none', ...
    'TooltipString','ACTIVE DATASET: none');

studio = guidata(fig);
studio.activeDatasetText = activeDatasetText;
guidata(fig, studio);

addStudioIcon();

jLog = javaObjectEDT('javax.swing.JTextArea');
jLog.setEditable(false);
jLog.setLineWrap(true);
jLog.setWrapStyleWord(true);
jLog.setFont(java.awt.Font('Monospaced', java.awt.Font.PLAIN, 26));

% Safe Java colors. Avoid direct java.awt.Color(...) calls.
jLog.setBackground(studioJavaColor(0,0,0));
jLog.setForeground(studioJavaColor(0.60,0.85,1.00));

jLog.setText('');

jScroll = javaObjectEDT('javax.swing.JScrollPane', jLog);
[~, hLogContainer] = javacomponent(jScroll, [1 1 1 1], logPanel); %#ok<JAVCM>
set(hLogContainer, 'Units','normalized', 'Position',[0.02 0.02 0.96 0.95]);

studio = guidata(fig);
studio.logBox = hLogContainer;
studio.logBoxJava = jLog;
guidata(fig, studio);

addLog('fUSI Studio initialized.');

%% =========================================================
%  SECTION DEFINITIONS
% =========================================================
sectionHeights = [0.115 0.115 0.205 0.115 0.125 0.105 0.125];

titles = { ...
    '1. Dataset', ...
    '2. Quality Control & Data Overview', ...
    '3. Recommended Processing Steps', ...
    '4. Advanced Processing', ...
    '5. Visualization', ...
    '6. Coregistration', ...
    '7. Advanced Analysis'};

buttons = { ...
    {'Load fUSI Data'}, ...
    {'Full QC','Specific QC'}, ...
    {'Frame Rejection','Imregdemons','Scrubbing','Motor'}, ...
    {'Temporal Smoothing/Subsampling','Filtering','PCA / ICA','Despike'}, ...
    {'Time-Course Viewer','SCM','Video & SCM Mask','Mask Editor'}, ...
    {'Registration to Atlas','Segmentation'}, ...
    {'Functional connectivity','Group analysis'}};

%% =========================================================
%  SECTION RENDERING LOOP
% =========================================================
gapBetweenSections = 0.010;
y = 0.996;

for i = 1:length(sectionHeights)
    h = sectionHeights(i);
    y = y - h;

    panel = uipanel(leftPanel, ...
        'Title',titles{i}, ...
        'Units','normalized', ...
        'Position',[0.03 y 0.94 h], ...
        'BackgroundColor',[0.10 0.10 0.10], ...
        'ForegroundColor','w', ...
        'FontSize',16, ...
        'FontWeight','bold', ...
        'BorderType','line', ...
        'HighlightColor',[0.90 0.90 0.90], ...
        'ShadowColor',[0.90 0.90 0.90]);

    drawButtons(panel, buttons{i}, i);
    y = y - gapBetweenSections;
end

%% =========================================================
%  STATUS BAR
% =========================================================
statusPanel = uipanel(fig, ...
    'Units','normalized', ...
    'Position',[0.03 0.04 leftWidth 0.055], ...
    'BorderType','line', ...
    'HighlightColor',[0 0 0], ...
    'ShadowColor',[0 0 0]);

statusText = uicontrol(statusPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0 0 1 1], ...
    'FontWeight','bold', ...
    'FontSize',16, ...
    'HorizontalAlignment','center');

studio = guidata(fig);
studio.statusPanel = statusPanel;
studio.statusText = statusText;
guidata(fig, studio);

setProgramStatus(false);

%% =========================================================
%  BOTTOM HELP/CLOSE/EXPORT SESSION BUTTONS
% =========================================================
btnY = 0.04;
btnH = 0.055;

uicontrol(fig,'Style','pushbutton', ...
    'String','HELP', ...
    'Units','normalized', ...
    'Position',[0.50 btnY 0.08 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.30 0.50 0.95], ...
    'ForegroundColor','w', ...
    'Callback',@helpCallback);

uicontrol(fig,'Style','pushbutton', ...
    'String','EXPORT STUDIO LOG', ...
    'Units','normalized', ...
    'Position',[0.60 btnY 0.14 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.15 0.65 0.55], ...
    'ForegroundColor','w', ...
    'Callback',@exportSessionCallback);

uicontrol(fig,'Style','pushbutton', ...
    'String','MARK PUB READY', ...
    'Units','normalized', ...
    'Position',[0.76 btnY 0.12 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.55 0.25 0.80], ...
    'ForegroundColor','w', ...
    'Callback',@markPublicationReadyCallback);

uicontrol(fig,'Style','pushbutton', ...
    'String','CLOSE', ...
    'Units','normalized', ...
    'Position',[0.90 btnY 0.07 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.85 0.25 0.25], ...
    'ForegroundColor','w', ...
    'Callback',@(s,e) close(fig));

%% =========================================================
%  FOOTER LABEL
% =========================================================
studio = guidata(fig);

footerText = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.50 0.006 0.47 0.024], ...
    'BackgroundColor',[0.05 0.05 0.05], ...
    'ForegroundColor',[0.70 0.70 0.70], ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','normal', ...
    'HorizontalAlignment','right', ...
    'String', buildFooterLabel());

studio.footerText = footerText;
guidata(fig, studio);

%% =========================================================
%  BUTTON DRAWING
% =========================================================
function drawButtons(parent, btns, sectionIndex)

    studio = guidata(fig);
    n = length(btns);

    if sectionIndex == 1 && n == 1 && strcmp(btns{1},'Load fUSI Data')

        loadBtn = uicontrol(parent, ...
            'Style','pushbutton', ...
            'String','Load fUSI Data', ...
            'Units','normalized', ...
            'Position',[0.08 0.46 0.40 0.36], ...
            'FontWeight','bold', ...
            'FontSize',14, ...
            'ForegroundColor','w', ...
            'Enable','on', ...
            'BackgroundColor',[0.35 0.35 0.35], ...
            'Callback',@loadDataCallback);

        studio.allButtons{end+1} = loadBtn;

        uicontrol(parent, ...
            'Style','popupmenu', ...
            'String',{'<none>'}, ...
            'Units','normalized', ...
            'Position',[0.54 0.46 0.38 0.36], ...
            'BackgroundColor',[0.2 0.2 0.2], ...
            'ForegroundColor','w', ...
            'FontSize',13, ...
            'Callback',@datasetDropdownCallback, ...
            'Tag','datasetDropdown', ...
            'UserData',{{}}, ...
            'TooltipString','Select active dataset');

        guidata(fig, studio);
        return;
    end

    if n == 2
        positions = [ ...
            0.08 0.29 0.38 0.42; ...
            0.54 0.29 0.38 0.42];
    elseif n == 4
        positions = [ ...
            0.08 0.57 0.38 0.28; ...
            0.54 0.57 0.38 0.28; ...
            0.08 0.17 0.38 0.28; ...
            0.54 0.17 0.38 0.28];
    else
        positions = zeros(n,4);
        for kk = 1:n
            positions(kk,:) = [0.14 0.30 0.72 0.40];
        end
    end

    for k = 1:n
        label = btns{k};
        callback = @dummyNotImplemented;
        labelKey = lower(regexprep(strtrim(label),'\s+',' '));

        switch labelKey
            case 'full qc'
                callback = @runFullQCCallback;
            case 'specific qc'
                callback = @runSpecificQCCallback;
            case 'frame rejection'
                callback = @frameRateCallback;
            case 'subsampling'
                callback = @gabrielCallback;
            case 'imregdemons'
                callback = @gabrielCallback;
            case 'scrubbing'
                callback = @scrubbingCallback;
            case 'motor'
                callback = @stepMotorCallback;
                        case 'temporal smoothing/subsampling'
                callback = @temporalSmoothingCallback;
            case 'temporal smoothing'
                callback = @temporalSmoothingCallback;
            case 'filtering'
                callback = @filteringCallback;
            case 'pca'
    callback = @pcaCallback;
case 'pca / ica'
    callback = @pcaCallback;
            case 'despike'
                callback = @despikeCallback;
            case 'time-course viewer'
                callback = @liveViewerCallback;
            case 'scm'
                callback = @scmCallback;
            case 'video & scm mask'
                callback = @videoGUICallback;
            case 'mask editor'
                callback = @maskEditorCallback;
            case 'registration to atlas'
                callback = @coregCallback;
            case 'segmentation'
                callback = @segmentationCallback;
            case 'functional connectivity'
                callback = @functionalConnectivityCallback;
            case 'group analysis'
                callback = @groupAnalysisCallback;
        end

        btn = uicontrol(parent, ...
            'Style','pushbutton', ...
            'String',label, ...
            'Units','normalized', ...
            'Position',positions(k,:), ...
            'FontWeight','bold', ...
            'FontSize',14, ...
            'ForegroundColor','w', ...
            'BackgroundColor',[0.18 0.18 0.18], ...
            'Enable','off', ...
            'Callback',callback);

        studio.allButtons{end+1} = btn;
        guidata(fig, studio);
    end
end

%% =========================================================
%  DUMMY PLACEHOLDER
% =========================================================
function dummyNotImplemented(~,~)
    addLog('This module is not implemented yet.');
end

%% =========================================================
%  LOAD DATA CALLBACK
% =========================================================
function loadDataCallback(~,~)

    studio = guidata(fig);

    startPath = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
    if ~exist(startPath,'dir')
        startPath = pwd;
    end

    [file,path] = uigetfile( ...
        {'*.mat;*.nii;*.nii.gz','fUSI Data (*.mat, *.nii, *.nii.gz)'}, ...
        'Select fUSI dataset', startPath);

    if isequal(file,0)
        addLog('Load cancelled.');
        return;
    end

    addLog('Loading dataset...');
    setProgramStatus(false);
    drawnow;

    studio.datasets = struct();
    studio.activeDataset = '';
    studio.meta = [];
    studio.isLoaded = false;
    studio.loadedFile = '';
    studio.loadedPath = '';
    studio.loadedName = '';
    studio.exportPath = '';
    studio.publicationReady = [];
    studio.publicationReadyNote = '';
    studio.publicationReadyTime = '';
   studio.atlasTransform = [];
studio.atlasTransformFile = '';

studio.atlasReg2D = [];
studio.atlasReg2DFile = '';
studio.atlasRegistrationMode = '';

% Important: avoid stale mask-editor underlay/mask from previous animal
studio.mask = [];
studio.maskIsInclude = true;
studio.brainMask = [];
studio.brainImageFile = '';
studio.anatomicalReferenceRaw = [];
studio.anatomicalReference = [];
studio.anatomicalReferenceIsDisplayReady = false;
studio.anatomicalReferenceFile = '';
studio.registrationPath = '';
    studio.pipeline = struct( ...
        'loadDone', false, ...
        'qcDone', false, ...
        'preprocDone', false, ...
        'pscDone', false, ...
        'visualDone', false);

    guidata(fig, studio);

    try
    fullInputFile = fullfile(path,file);
    [data, meta] = loadFUSIData(fullInputFile, []);

    [chosenTR, probeType, defaultTR, wasCancelled] = promptTRAfterLoad(data, meta);

    if wasCancelled
        addLog('Load cancelled during TR selection.');
        setProgramStatus(true);
        return;
    end

    data.TR = chosenTR;
    data.nVols = size(data.I, ndims(data.I));
    data.TotalTimeSec = data.nVols * data.TR;
    data.TotalTimeMin = data.TotalTimeSec / 60;
    data.totalTime = data.TotalTimeSec;
    data.totalTimeMin = data.TotalTimeMin;

    if ~isfield(meta,'rawMetadata') || isempty(meta.rawMetadata)
        meta.rawMetadata = struct();
    end
    meta.rawMetadata.probeTypeUserConfirmed = probeType;
    meta.rawMetadata.defaultTRUserPromptSec = defaultTR;
    meta.rawMetadata.selectedTRUserSec = chosenTR;

        rawRoot = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
        analysedRoot = 'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData';

        studio_mkdir(analysedRoot);

        datasetName = regexprep(file, '\.nii\.gz$', '', 'ignorecase');
        datasetName = regexprep(datasetName, '\.nii$', '', 'ignorecase');
        datasetName = regexprep(datasetName, '\.mat$', '', 'ignorecase');
        datasetName = char(datasetName);
        datasetName = strrep(datasetName, filesep, '_');
        datasetName = regexprep(datasetName,'[^\w\-]+','_');
        datasetName = regexprep(datasetName,'_+','_');
        datasetName = regexprep(datasetName,'^_+','');
        datasetName = regexprep(datasetName,'_+$','');
        if isempty(datasetName)
            datasetName = 'item';
        end

        rawRootNorm = strrep(rawRoot, '/', filesep);
        pathNorm = strrep(path, '/', filesep);

        if numel(pathNorm) >= numel(rawRootNorm) && strcmpi(pathNorm(1:numel(rawRootNorm)), rawRootNorm)
            relPath = pathNorm(numel(rawRootNorm)+1:end);
            while ~isempty(relPath) && any(relPath(1) == [filesep '/' '\'])
                relPath = relPath(2:end);
            end
            datasetFolder = fullfile(analysedRoot, relPath, datasetName);
        else
            datasetFolder = fullfile(analysedRoot, datasetName);
        end

        studio_mkdir(datasetFolder);

        parTmp = struct();
        parTmp.activeDataset = 'raw';
        parTmp.loadedName = datasetName;
        parTmp.loadedFile = fullInputFile;
        parTmp.loadedPath = path;
        parTmp.exportPath = datasetFolder;

        P = studio_resolve_paths(parTmp, datasetName, datasetFolder);

       qcFolder  = fullfile(datasetFolder,'QC');
preFolder = fullfile(datasetFolder,'Preprocessing');
visFolder = fullfile(datasetFolder,'Visualization');
regFolder = fullfile(datasetFolder,'Registration');
reg2DFolder = fullfile(datasetFolder,'Registration2D');
pscFolder = fullfile(datasetFolder,'PSC');

folders = {qcFolder, preFolder, visFolder, regFolder, reg2DFolder, pscFolder};
for kk = 1:numel(folders)
    if ~exist(folders{kk},'dir')
        mkdir(folders{kk});
    end
end

        studio = guidata(fig);

       data.displayNameFull = cleanLoadedDatasetName(datasetName);
        data.sourceFileName = file;
        data.sourcePath = path;

        studio.datasets.raw = data;
        studio.activeDataset = 'raw';
        studio.meta = meta;
        studio.isLoaded = true;
        studio.loadedFile = file;
        studio.loadedPath = path;
        studio.loadedName = datasetName;
        studio.exportPath = datasetFolder;
        studio.pipeline.loadDone = true;
        studio.registrationPath = regFolder;
        studio.registration2DPath = reg2DFolder;
if isempty(studio.meta) || ~isstruct(studio.meta)
    studio.meta = struct();
end

studio.meta.exportPath = datasetFolder;
studio.meta.savePath   = datasetFolder;
studio.meta.outPath    = datasetFolder;
studio.meta.loadedPath = path;
studio.meta.loadedFile = fullInputFile;
studio.meta.registrationPath = regFolder;
studio.meta.registration2DPath = reg2DFolder;
studio.meta.visualizationPath = visFolder;
studio.meta.preprocessingPath = preFolder;
studio.meta.pscPath = pscFolder;
      pscFolder = fullfile(datasetFolder,'PSC');
if exist(pscFolder,'dir')
    pscFiles = dir(fullfile(pscFolder,'*.mat'));
    for kk = 1:numel(pscFiles)
        [~,fullName] = fileparts(pscFiles(kk).name);
        safeKey = makeSafeKey(fullName, studio.datasets);
        studio.datasets.(safeKey) = struct( ...
            'lazyFile', fullfile(pscFiles(kk).folder, pscFiles(kk).name), ...
            'isLazy', true, ...
            'displayNameFull', fullName);
    end
end

        preFiles = dir(fullfile(P.preprocRoot,'*.mat'));
        for kk = 1:numel(preFiles)
            [~,fullName] = fileparts(preFiles(kk).name);
            safeKey = makeSafeKey(fullName, studio.datasets);
            studio.datasets.(safeKey) = struct( ...
                'lazyFile', fullfile(preFiles(kk).folder, preFiles(kk).name), ...
                'isLazy', true, ...
                'displayNameFull', fullName);
        end

        guidata(fig, studio);

        unlockAllButtons();
        refreshDatasetDropdown();
dims = size(data.I);

addLog('---------------------------------------');
addLog('DATASET LOADED SUCCESSFULLY');
addLog(['Input file: ' fullInputFile]);
addLog(['Loaded name: ' datasetName]);
addLog(['Dataset folder: ' datasetFolder]);

if ndims(data.I) == 3
    addLog(sprintf('Dimensions: %d x %d | Volumes: %d', ...
        dims(1), dims(2), dims(3)));
elseif ndims(data.I) >= 4
    addLog(sprintf('Dimensions: %d x %d x %d | Volumes: %d', ...
        dims(1), dims(2), dims(3), dims(4)));
else
    addLog(['Dimensions: ' mat2str(dims)]);
    addLog(sprintf('Volumes: %d', data.nVols));
end

addLog(['Probe: ' probeType]);
addLog(sprintf('TR: %.0f ms (%.3f sec)', data.TR*1000, data.TR));
addLog(sprintf('Preset default TR for detected probe: %.0f ms', defaultTR*1000));

if isfield(data,'TotalTimeSec')
    addLog(sprintf('Total time: %.2f sec', data.TotalTimeSec));
end
addLog('---------------------------------------');

        setProgramStatus(true);

    catch ME
        addLog(['LOAD ERROR: ' ME.message]);
        setProgramStatus(true);
        errordlg(ME.message,'Load Failure');
    end
end
%% =========================================================
%  FULL QC
% =========================================================
function runFullQCCallback(~,~)

    studio = guidata(fig);
    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    addLog('Running FULL QC...');
    setProgramStatus(false);
    drawnow;

    opts = struct();
opts.frequency = true;
opts.spatial = true;
opts.temporal = true;
opts.motion = true;
opts.stability = true;
opts.framerate = true;
opts.pca = true;
opts.burst = true;
opts.cnr = true;
opts.commonmode = true;

% NEW QC modules
opts.outlierframes = true;
opts.reliability   = true;

% optional settings
opts.outlierReplace = false;
opts.saveOutlierCorrectedData = false;
opts.reliabilityThreshold = 0.60;

opts.datasetTag = studio.activeDataset;
opts.useTimestampSubfolder = false;

    data = getActiveData();

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);
        addLog(['FULL QC completed. Saved under: QC\' opts.datasetTag]);
        studio.pipeline.qcDone = true;
        guidata(fig, studio);
    catch ME
        addLog(['QC ERROR: ' ME.message]);
        errordlg(ME.message,'QC Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  SPECIFIC QC + Helper
% =========================================================
    function runSpecificQCCallback(~,~)

    if isempty(fig) || ~ishghandle(fig)
        errordlg('Main Studio figure handle is invalid. Please restart fusi_studio.');
        return;
    end

    studio = guidata(fig);
    if isempty(studio) || ~isstruct(studio) || ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    [choice, choiceNames] = showSpecificQCDialog();

    if isempty(choice)
        addLog('QC selection cancelled.');
        return;
    end

opts = struct();
opts.frequency    = ismember(1, choice);
opts.spatial      = ismember(2, choice);
opts.temporal     = ismember(3, choice);
opts.motion       = ismember(4, choice);
opts.stability    = ismember(5, choice);
opts.framerate    = ismember(6, choice);
opts.pca          = ismember(7, choice);
opts.burst        = ismember(8, choice);
opts.cnr          = ismember(9, choice);
opts.commonmode   = ismember(10, choice);
opts.outlierframes = ismember(11, choice);
opts.reliability   = ismember(12, choice);

% optional settings
opts.outlierReplace = false;
opts.saveOutlierCorrectedData = false;
opts.reliabilityThreshold = 0.60;

opts.datasetTag = studio.activeDataset;
opts.useTimestampSubfolder = false;

    addLog('Running selected QC...');
    for ii = 1:numel(choiceNames)
        thisName = choiceNames{ii};
        addLog(['  - ' thisName]);
    end

    setProgramStatus(false);
    drawnow;

    data = getActiveData();

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);
        addLog(['Selected QC completed. Saved under: QC\' opts.datasetTag]);
        studio.pipeline.qcDone = true;
        guidata(fig, studio);
    catch ME
        addLog(['QC ERROR: ' ME.message]);
        errordlg(ME.message,'QC Failure');
    end

    setProgramStatus(true);
end
    function [choice, choiceNames] = showSpecificQCDialog()

    choice = [];
    choiceNames = {};

  modules = { ...
    'Frequency QC',        'Power spectrum: 0-2 Hz and 0-0.1 Hz',                          [0.20 0.75 1.00]; ...
    'Spatial QC',          'Mean image, temporal CV, tSNR map and histogram',              [0.20 0.90 0.55]; ...
    'Temporal QC',         'Global signal, rGS, DVARS, spike detection',                   [1.00 0.80 0.25]; ...
    'Motion QC',           'Center-of-mass drift over time',                                [1.00 0.50 0.30]; ...
    'Stability QC',        'Intensity distribution and rejected volumes',                   [0.95 0.35 0.75]; ...
    'Frame-rate QC',       'Global rejection and interpolation stability',                  [0.75 0.60 1.00]; ...
    'PCA QC',              'Explained variance and PCA component overview',                 [0.60 0.85 1.00]; ...
    'Burst Error QC',      'Burst ratio, noisy voxels, burst coverage over time',          [1.00 0.35 0.35]; ...
    'CNR QC',              'Contrast-to-noise ratio map and histogram',                     [0.35 0.90 0.90]; ...
    'Common-Mode QC',      'Block-correlation common-mode artifact detection',              [0.85 0.85 0.35]; ...
    'Outlier Line/Frame QC','Line-wise abnormal frame detection and optional interpolation', [1.00 0.60 0.20]; ...
    'Reliability QC',      'Finite/non-NaN voxel reliability map and region summary',       [0.45 0.75 1.00]  ...
};

    n = size(modules,1);

    bg    = [0.06 0.06 0.07];
    bg2   = [0.10 0.10 0.11];
    fg    = [0.96 0.96 0.96];
    fgDim = [0.72 0.72 0.75];

    dlg = figure( ...
        'Name','Select Specific QC Modules', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
        'Position',[200 100 760 610], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel);

    try
        if ~isempty(fig) && ishghandle(fig)
            movegui(dlg,'center');
        end
    catch
        movegui(dlg,'center');
    end

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.04 0.93 0.92 0.05], ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontSize',18, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left', ...
        'String','Specific QC Selection');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.04 0.885 0.92 0.035], ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontSize',11, ...
        'HorizontalAlignment','left', ...
        'String','Choose the QC modules you want to run.');

    mainPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.04 0.18 0.92 0.68], ...
        'BackgroundColor',bg2, ...
        'ForegroundColor',[0.35 0.35 0.35], ...
        'BorderType','line', ...
        'Title','QC Modules', ...
        'FontSize',12, ...
        'FontWeight','bold');

    cb = zeros(1,n);

    y0 = 0.89;
    dy = 0.085;

    for ii = 1:n
        y = y0 - (ii-1)*dy;

        uipanel('Parent',mainPanel, ...
            'Units','normalized', ...
            'Position',[0.03 y-0.005 0.025 0.045], ...
            'BackgroundColor',modules{ii,3}, ...
            'BorderType','line');

        cb(ii) = uicontrol('Parent',mainPanel, ...
            'Style','checkbox', ...
            'Units','normalized', ...
            'Position',[0.07 y 0.30 0.05], ...
            'BackgroundColor',bg2, ...
            'ForegroundColor',fg, ...
            'FontSize',12, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left', ...
            'String',modules{ii,1}, ...
            'Value',0);

        uicontrol('Parent',mainPanel,'Style','text', ...
            'Units','normalized', ...
            'Position',[0.39 y-0.003 0.57 0.05], ...
            'BackgroundColor',bg2, ...
            'ForegroundColor',fgDim, ...
            'FontSize',11, ...
            'HorizontalAlignment','left', ...
            'String',modules{ii,2});
    end

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Select All', ...
        'Units','normalized', ...
        'Position',[0.04 0.09 0.14 0.055], ...
        'FontWeight','bold', ...
        'FontSize',11, ...
        'BackgroundColor',[0.22 0.52 0.95], ...
        'ForegroundColor','w', ...
        'Callback',@onSelectAll);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Clear All', ...
        'Units','normalized', ...
        'Position',[0.20 0.09 0.14 0.055], ...
        'FontWeight','bold', ...
        'FontSize',11, ...
        'BackgroundColor',[0.30 0.30 0.32], ...
        'ForegroundColor','w', ...
        'Callback',@onClearAll);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Core Set', ...
        'Units','normalized', ...
        'Position',[0.36 0.09 0.14 0.055], ...
        'FontWeight','bold', ...
        'FontSize',11, ...
        'BackgroundColor',[0.15 0.65 0.55], ...
        'ForegroundColor','w', ...
        'Callback',@onCoreSet);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Run Selected QC', ...
        'Units','normalized', ...
        'Position',[0.60 0.09 0.20 0.065], ...
        'FontWeight','bold', ...
        'FontSize',12, ...
        'BackgroundColor',[0.15 0.70 0.35], ...
        'ForegroundColor','w', ...
        'Callback',@onRun);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Cancel', ...
        'Units','normalized', ...
        'Position',[0.82 0.09 0.14 0.065], ...
        'FontWeight','bold', ...
        'FontSize',12, ...
        'BackgroundColor',[0.75 0.25 0.25], ...
        'ForegroundColor','w', ...
        'Callback',@onCancel);

    set(dlg,'Visible','on');
    waitfor(dlg);

    function onSelectAll(~,~)
        for kk = 1:n
            if ishandle(cb(kk))
                set(cb(kk),'Value',1);
            end
        end
    end

    function onClearAll(~,~)
        for kk = 1:n
            if ishandle(cb(kk))
                set(cb(kk),'Value',0);
            end
        end
    end

    function onCoreSet(~,~)
        coreIdx = [1 2 3 4 5 8 9 10 11 12];
        for kk = 1:n
            if ishandle(cb(kk))
                set(cb(kk),'Value',ismember(kk,coreIdx));
            end
        end
    end

    function onRun(~,~)
        idx = [];
        for kk = 1:n
            if ishandle(cb(kk))
                if get(cb(kk),'Value') == 1
                    idx(end+1) = kk; %#ok<AGROW>
                end
            end
        end

        if isempty(idx)
            errordlg('Please select at least one QC module.','Specific QC');
            return;
        end

        choice = idx;
        choiceNames = modules(idx,1);

        if ishandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(~,~)
        choice = [];
        choiceNames = {};
        if ishandle(dlg)
            delete(dlg);
        end
    end
end


%% =========================================================
%  IMREGDEMONS / GABRIEL PREPROCESSING
% =========================================================
function gabrielCallback(~,~)

    studio = guidata(fig);

    if isempty(studio) || ~isstruct(studio) || ...
            ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Imregdemons');
        return;
    end

    data = getActiveData();

    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        errordlg('Active dataset has no data.I field.','Imregdemons');
        return;
    end

    if ~isfield(data,'TR') || isempty(data.TR) || ...
            ~isscalar(data.TR) || ~isfinite(data.TR) || data.TR <= 0
        errordlg('Active dataset has invalid TR.','Imregdemons');
        return;
    end

    % -----------------------------------------------------
    % One clean modern black setup popup
    % Default: MEDIAN, nsub = 100
    % -----------------------------------------------------
    cfg = showImregdemonsSetupDialog(data);

    if isempty(cfg) || ~isstruct(cfg) || ...
            ~isfield(cfg,'cancelled') || cfg.cancelled
        addLog('Imregdemons preprocessing cancelled.');
        return;
    end

    blockMethod = lower(strtrim(cfg.blockMethod));
    nsub = round(cfg.nsub);

    % Cleanup old lingering QC / preprocessing windows first
    closeLingeringQCFigures();

    setProgramStatus(false);
    addLog(sprintf('Running Imregdemons preprocessing (%s, nsub = %d)...', ...
        upper(blockMethod), nsub));
    drawnow;

    % Track figure state so any figures created by gabriel_preprocess
    % can be closed afterwards
    figsBefore = findall(0, 'Type', 'figure');

    ts = datestr(now,'yyyymmdd_HHMMSS');

    opts = struct();
    opts.nsub = nsub;
    opts.blockMethod = blockMethod;
    opts.regSmooth = cfg.regSmooth;
    opts.saveQC = cfg.saveQC;
    opts.showQC = cfg.showQC;
    opts.tag = ['imregdemons_' ts];
    opts.exportPath = studio.exportPath;
    opts.qcDir = fullfile(studio.exportPath, 'Preprocessing', ...
        sprintf('imregdemons_QC_%s_nsub%d', blockMethod, nsub));

    % Optional metadata for auto-detection inside gabriel_preprocess
    try
        opts.meta = studio.meta;
    catch
    end

    % Registration mode control:
    %   auto     -> do not force opts.stepMotorMode
    %   standard -> force 3D demons for 4D data
    %   motor    -> force per-slice 2D demons for step-motor 4D data
    if strcmpi(cfg.stepMotorMode,'standard')
        opts.stepMotorMode = false;
    elseif strcmpi(cfg.stepMotorMode,'motor')
        opts.stepMotorMode = true;
    end

    try
        out = gabriel_preprocess(data.I, data.TR, opts);

        % Close any new figures created during preprocessing
        drawnow;
        closeNewFigures(figsBefore);
        closeLingeringQCFigures();

        newData = data;
        newData.I = single(out.I);

        if isfield(out,'TR') && ~isempty(out.TR)
            newData.TR = out.TR;
        elseif isfield(out,'blockDur') && ~isempty(out.blockDur)
            newData.TR = out.blockDur;
        else
            newData.TR = data.TR * nsub;
        end

        if isfield(out,'nVols') && ~isempty(out.nVols)
            newData.nVols = out.nVols;
        else
            newData.nVols = size(newData.I, ndims(newData.I));
        end

        % Store both output duration and original acquisition duration
        newData.TotalTimeSec = newData.nVols * newData.TR;
        newData.TotalTimeMin = newData.TotalTimeSec / 60;
        newData.totalTime = newData.TotalTimeSec;
        newData.totalTimeMin = newData.TotalTimeMin;

        if isfield(out,'totalTime') && ~isempty(out.totalTime)
            newData.originalTotalTimeSec = out.totalTime;
        else
            newData.originalTotalTimeSec = size(data.I, ndims(data.I)) * data.TR;
        end

        if isfield(out,'method') && ~isempty(out.method)
            newData.preprocessing = out.method;
        else
            newData.preprocessing = sprintf('Imregdemons (%s, nsub=%d)', ...
                blockMethod, nsub);
        end

        newData.imregdemons = out;

        % Important: old PSC/bg are no longer valid after motion correction
        if isfield(newData,'PSC'), newData.PSC = []; end
        if isfield(newData,'bg'),  newData.bg  = []; end

        baseStem = getCurrentNamingStem(studio);

        fullName = sprintf('%s_imregdemons_%s_nsub%d_%s', ...
            baseStem, blockMethod, nsub, ts);

        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        preFolder = fullfile(studio.exportPath,'Preprocessing');
        if ~exist(preFolder,'dir')
            mkdir(preFolder);
        end

        save(fullfile(preFolder,[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Imregdemons preprocessing complete -> ' fullName]);

        if isfield(out,'registrationMode')
            addLog(['Registration mode: ' out.registrationMode]);
        end

        addLog(sprintf('Output TR: %.6g s | Output volumes: %d | Output duration: %.2f min', ...
            newData.TR, newData.nVols, newData.TotalTimeMin));

        if opts.saveQC
            addLog(['Imregdemons QC saved -> ' opts.qcDir]);
        end

    catch ME
        % Also cleanup figures on failure
        drawnow;
        closeNewFigures(figsBefore);
        closeLingeringQCFigures();

        addLog(['IMREGDEMONS ERROR: ' ME.message]);
        errordlg(ME.message,'Imregdemons Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  MODERN IMREGDEMONS SETUP POPUP
% =========================================================
function cfg = showImregdemonsSetupDialog(data)

    cfg = struct();
    cfg.cancelled = true;

    TR = double(data.TR);
    I = data.I;
    nd = ndims(I);
    sz = size(I);
    T = sz(nd);

    if nd == 3
        dimTxt = sprintf('%d x %d x %d', sz(1), sz(2), sz(3));
        modeHint = '2D time-series: demons runs frame-by-frame.';
    elseif nd == 4
        dimTxt = sprintf('%d x %d x %d x %d', sz(1), sz(2), sz(3), sz(4));
        modeHint = '4D data: use Auto, or force Step-Motor per-slice mode if this came from motor reconstruction.';
    else
        dimTxt = mat2str(sz);
        modeHint = 'Unsupported dimensionality for Imregdemons.';
    end

    % ---------------- defaults requested ----------------
    defaultNsub = 100;
    defaultMethodIdx = 1;      % 1 = Median, 2 = Mean
    defaultRegSmooth = 1.3;
    defaultModeIdx = 1;        % 1 = Auto, 2 = Standard, 3 = Step-motor
    defaultSaveQC = 1;
    defaultShowQC = 0;

    % ---------------- colors ----------------
    bg      = [0.045 0.045 0.050];
    panel   = [0.085 0.085 0.095];
    panel2  = [0.115 0.115 0.130];
    fg      = [0.96 0.96 0.96];
    fgDim   = [0.72 0.72 0.76];
    blue    = [0.20 0.48 0.95];
    green   = [0.15 0.68 0.35];
    orange  = [0.95 0.55 0.18];
    red     = [0.80 0.25 0.25];

    dlg = figure( ...
        'Name','Imregdemons Preprocessing', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
       'Position',[300 100 880 690], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel, ...
        'KeyPressFcn',@onKey);

    try
        movegui(dlg,'center');
    catch
    end

    % ---------------- title ----------------
    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.925 0.91 0.055], ...
        'String','Imregdemons / Motion Correction Setup', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',20, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.047 0.875 0.91 0.04], ...
        'String','Median + nsub = 100 are pre-selected. Adjust only if needed.', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'HorizontalAlignment','left');

    % ---------------- dataset info ----------------
    infoPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.755 0.91 0.105], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    infoStr = sprintf('Input size: %s     TR: %.6g s     Volumes: %d     Duration: %.2f min', ...
        dimTxt, TR, T, (T*TR)/60);

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.48 0.93 0.38], ...
        'String',infoStr, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.75 0.88 1.00], ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.12 0.93 0.30], ...
        'String',modeHint, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.90 0.82 0.55], ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % ---------------- settings panel ----------------
    settingsPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.205 0.91 0.525], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    % Block method
    addLabel(settingsPanel,'Block averaging method',0.045,0.835);

    methodPopup = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.38 0.835 0.24 0.075], ...
        'String',{'Median','Mean'}, ...
        'Value',defaultMethodIdx, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

 uicontrol('Parent',settingsPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.65 0.805 0.31 0.115], ...
    'String',{'Median is robust'; 'and recommended.'}, ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'HorizontalAlignment','left');

    % nsub
    addLabel(settingsPanel,'Subsampling factor nsub',0.045,0.680);

    nsubEdit = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.38 0.685 0.18 0.075], ...
        'String',num2str(defaultNsub), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

uicontrol('Parent',settingsPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.59 0.660 0.37 0.105], ...
    'String',{'frames/block.'; 'Output TR = TR x nsub.'}, ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'HorizontalAlignment','left');

    % reg smooth
    addLabel(settingsPanel,'Demons smoothing',0.045,0.525);

    regSmoothEdit = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.38 0.530 0.18 0.075], ...
        'String',num2str(defaultRegSmooth), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

uicontrol('Parent',settingsPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.59 0.505 0.37 0.115], ...
    'String',{'Default 1.3.'; 'Higher = smoother field.'}, ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'HorizontalAlignment','left');

    % registration mode
    addLabel(settingsPanel,'Registration mode',0.045,0.370);

    modePopup = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.38 0.375 0.40 0.075], ...
       'String',{ ...
    'Auto-detect', ...
    'Standard 3D demons', ...
    'Step-motor per-slice 2D demons'}, ...
        'Value',defaultModeIdx, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    % QC options
    saveQcBox = uicontrol('Parent',settingsPanel,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.045 0.225 0.38 0.075], ...
        'String','Save QC PNGs', ...
        'Value',defaultSaveQC, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    showQcBox = uicontrol('Parent',settingsPanel,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.45 0.225 0.38 0.075], ...
        'String','Show QC windows after run', ...
        'Value',defaultShowQC, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    % preset buttons
    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.045 0.065 0.25 0.085], ...
        'String','Preset: Median n=100', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetRecommended);

    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.32 0.065 0.25 0.085], ...
        'String','Faster: Median n=50', ...
        'BackgroundColor',orange, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetFast);

    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.595 0.065 0.25 0.085], ...
        'String','Reset Defaults', ...
        'BackgroundColor',[0.30 0.30 0.34], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetRecommended);

    % ---------------- summary panel ----------------
   summaryPanel = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.045 0.105 0.91 0.08], ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.25 0.25 0.28], ...
        'ShadowColor',[0.01 0.01 0.01]);

    summaryText = uicontrol('Parent',summaryPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.025 0.10 0.95 0.80], ...
        'String','', ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',[0.70 1.00 0.80], ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % ---------------- bottom buttons ----------------
    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
       'Position',[0.54 0.025 0.24 0.06], ...
        'String','RUN IMREGDEMONS', ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onRun);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
     'Position',[0.80 0.025 0.155 0.06], ...
        'String','CANCEL', ...
        'BackgroundColor',red, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onCancel);

    updateSummary();

    set(dlg,'Visible','on');
    waitfor(dlg);

    % =====================================================
    % Nested helper functions
    % =====================================================
    function addLabel(parent, str, x, y)
        uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',[x y 0.31 0.065], ...
            'String',str, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',12, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function updateSummary(~,~)

        nsub = str2double(get(nsubEdit,'String'));
        regSmooth = str2double(get(regSmoothEdit,'String'));

        if ~isfinite(nsub) || nsub < 2
            nsubTxt = 'invalid';
            outTR = NaN;
            outBlocks = NaN;
            discard = NaN;
        else
            nsub = round(nsub);
            outTR = TR * nsub;
            outBlocks = floor(T / nsub);
            discard = T - outBlocks * nsub;
            nsubTxt = sprintf('nsub=%d, block=%.6g s', nsub, outTR);
        end

        if ~isfinite(regSmooth) || regSmooth <= 0
            smoothTxt = 'invalid smoothing';
        else
            smoothTxt = sprintf('smooth=%.3g', regSmooth);
        end

        methodList = get(methodPopup,'String');
        methodName = methodList{get(methodPopup,'Value')};

        modeList = get(modePopup,'String');
        modeName = modeList{get(modePopup,'Value')};

        txt = sprintf(['%s block averaging | %s | %s | Output blocks: %d | ' ...
            'Discard tail: %d frames | Mode: %s'], ...
            upper(methodName), nsubTxt, smoothTxt, outBlocks, discard, modeName);

        if ishandle(summaryText)
            set(summaryText,'String',txt);
        end
    end

    function presetRecommended(~,~)
        set(methodPopup,'Value',1);          % Median
        set(nsubEdit,'String','100');
        set(regSmoothEdit,'String','1.3');
        set(modePopup,'Value',1);            % Auto
        set(saveQcBox,'Value',1);
        set(showQcBox,'Value',0);
        updateSummary();
    end

    function presetFast(~,~)
        set(methodPopup,'Value',1);          % Median
        set(nsubEdit,'String','50');
        set(regSmoothEdit,'String','1.3');
        set(modePopup,'Value',1);            % Auto
        set(saveQcBox,'Value',1);
        set(showQcBox,'Value',0);
        updateSummary();
    end

    function onRun(~,~)

        nsub = str2double(get(nsubEdit,'String'));
        regSmooth = str2double(get(regSmoothEdit,'String'));

        if ~isfinite(nsub) || nsub < 2
            uiwait(errordlg('nsub must be a number >= 2.', ...
                'Invalid Imregdemons setting','modal'));
            return;
        end

        nsub = round(nsub);

        if floor(T / nsub) < 1
            uiwait(errordlg(sprintf( ...
                'Not enough frames. Dataset has %d volumes, but nsub = %d.', ...
                T, nsub), ...
                'Invalid nsub','modal'));
            return;
        end

        if floor(T / nsub) < 3
            choice = questdlg(sprintf([ ...
                'Only %d output blocks will remain after nsub = %d.\n\n' ...
                'This is very little for motion correction.\nContinue anyway?'], ...
                floor(T/nsub), nsub), ...
                'Low output block count', ...
                'Continue','Cancel','Cancel');

            if isempty(choice) || strcmpi(choice,'Cancel')
                return;
            end
        end

        if ~isfinite(regSmooth) || regSmooth <= 0
            uiwait(errordlg('Demons smoothing must be a positive number.', ...
                'Invalid Imregdemons setting','modal'));
            return;
        end

        methodList = get(methodPopup,'String');
        methodName = lower(methodList{get(methodPopup,'Value')});

        modeVal = get(modePopup,'Value');
        if modeVal == 1
            stepMode = 'auto';
        elseif modeVal == 2
            stepMode = 'standard';
        else
            stepMode = 'motor';
        end

        cfg.cancelled = false;
        cfg.blockMethod = methodName;
        cfg.nsub = nsub;
        cfg.regSmooth = regSmooth;
        cfg.stepMotorMode = stepMode;
        cfg.saveQC = logical(get(saveQcBox,'Value'));
        cfg.showQC = logical(get(showQcBox,'Value'));

        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(~,~)
        cfg.cancelled = true;
        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel();
            elseif strcmpi(ev.Key,'return')
                onRun();
            end
        catch
        end
    end
end

%% =========================================================
%  FRAME-RATE REJECTION
% =========================================================
function frameRateCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    % Cleanup old lingering QC windows first
    closeLingeringQCFigures();

    data = getActiveData();

    addLog('Running Frame-rate QC (ORIGINAL)...');
    setProgramStatus(false);
    drawnow;

    QC_before = struct();
    QC_after  = struct();

    try
        QC_before = frameRateQC(data.I, data.TR, 'ORIGINAL', false);
        addLog(sprintf('Original rejected: %.2f %%', QC_before.rejPct));

        qcFolder = fullfile(studio.exportPath,'QC','FrameRate');
        if ~exist(qcFolder,'dir')
            mkdir(qcFolder);
        end

        ts = datestr(now,'yyyymmdd_HHMMSS');

        try
            if isfield(QC_before,'figIntensity') && ishghandle(QC_before.figIntensity)
                saveas(QC_before.figIntensity, ...
                    fullfile(qcFolder,['FrameRate_ORIGINAL_Intensity_' ts '.png']));
            end
            if isfield(QC_before,'figRejected') && ishghandle(QC_before.figRejected)
                saveas(QC_before.figRejected, ...
                    fullfile(qcFolder,['FrameRate_ORIGINAL_Rejected_' ts '.png']));
            end
        catch
        end

        safeCloseFigureHandle(QC_before, 'figIntensity');
        safeCloseFigureHandle(QC_before, 'figRejected');
        closeLingeringQCFigures();

        choice = questdlg( ...
            sprintf('%.2f %% volumes rejected.\n\nInterpolate rejected volumes?', QC_before.rejPct), ...
            'Frame-rate rejection', ...
            'Yes','No','No');

        if ~strcmp(choice,'Yes')
            addLog('Interpolation skipped.');
            setProgramStatus(true);
            return;
        end

        addLog('Interpolating rejected volumes...');
        Iclean = interpolateRejectedVolumes(data.I, QC_before.outliers);

        addLog('Running Frame-rate QC (INTERPOLATED)...');
        QC_after = frameRateQC(Iclean, data.TR, 'INTERPOLATED', false);
        addLog(sprintf('After interpolation rejected: %.2f %%', QC_after.rejPct));

        try
            if isfield(QC_after,'figIntensity') && ishghandle(QC_after.figIntensity)
                saveas(QC_after.figIntensity, ...
                    fullfile(qcFolder,['FrameRate_INTERPOLATED_Intensity_' ts '.png']));
            end
            if isfield(QC_after,'figRejected') && ishghandle(QC_after.figRejected)
                saveas(QC_after.figRejected, ...
                    fullfile(qcFolder,['FrameRate_INTERPOLATED_Rejected_' ts '.png']));
            end
        catch
        end

        safeCloseFigureHandle(QC_after, 'figIntensity');
        safeCloseFigureHandle(QC_after, 'figRejected');
        closeLingeringQCFigures();

        newData = data;
        newData.I = Iclean;
        newData.frameRateQC_before = QC_before;
        newData.frameRateQC_after = QC_after;
        newData.preprocessing = 'Frame-rate rejection (validated)';

        ts2 = datestr(now,'yyyymmdd_HHMMSS');
        baseStem = getCurrentNamingStem(studio);
        fullName = [baseStem '_frameRej_' ts2];

        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Frame-rate rejection validated -> ' fullName]);

    catch ME
        safeCloseFigureHandle(QC_before, 'figIntensity');
        safeCloseFigureHandle(QC_before, 'figRejected');
        safeCloseFigureHandle(QC_after,  'figIntensity');
        safeCloseFigureHandle(QC_after,  'figRejected');
        closeLingeringQCFigures();

        addLog(['Frame-rate ERROR: ' ME.message]);
        errordlg(ME.message,'Frame-rate Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  SCRUBBING
% =========================================================
function scrubbingCallback(~,~)

    studio = guidata(fig);
    if isempty(studio) || ~isstruct(studio) || ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Scrubbing');
        return;
    end

    data = getActiveData();

    addLog('Running scrubbing...');
    setProgramStatus(false);
    drawnow;

    ts = datestr(now,'yyyymmdd_HHMMSS');
    tag = ['scrub_' ts];

    try
        [outI, stats] = scrubbing(data.I, data.TR, studio.exportPath, tag);
if isempty(outI) || ...
        (isstruct(stats) && isfield(stats,'cancelled') && stats.cancelled)
    addLog('Scrubbing cancelled.');
    setProgramStatus(true);
    return;
end
        method = 'Unknown';
        if isfield(stats,'method') && ~isempty(stats.method)
            method = stats.method;
        end

        interpMethod = 'linear';
        if isfield(stats,'interpMethod') && ~isempty(stats.interpMethod)
            interpMethod = stats.interpMethod;
        end

        methKey = regexprep(method, '\s+','');
        interpKey = lower(regexprep(interpMethod,'\s+',''));

        baseStem = getCurrentNamingStem(studio);
fullName = [baseStem '_scrub_' methKey '_' interpKey '_' ts];
        keyName = makeSafeKey(fullName, studio.datasets);

        newData = data;
        newData.I = single(outI);
        newData.preprocessing = sprintf('Scrubbing (%s, %s)', method, interpMethod);
        newData.scrubbingStats = stats;
        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
             'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        nFlag = NaN;
        pct = NaN;
        if isfield(stats,'removedVolumes')
            nFlag = stats.removedVolumes;
        end
        if isfield(stats,'percentRemoved')
            pct = stats.percentRemoved;
        end

        addLog(sprintf('Scrubbing done: %s + %s | flagged=%g (%.2f%%)', methKey, interpKey, nFlag, pct));
        addLog(['Saved dataset -> ' fullName]);

    catch ME
        addLog(['SCRUBBING ERROR: ' ME.message]);
        errordlg(ME.message,'Scrubbing Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  MOTOR RECONSTRUCTION
% =========================================================
function stepMotorCallback(~,~)

    studio = guidata(fig);

    if isempty(studio) || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    if ndims(data.I) ~= 3
        errordlg('Motor reconstruction only for 2D probe data.');
        return;
    end

    addLog('Launching Motor Reconstruction...');
    setProgramStatus(false);
    drawnow;

    try
        qcFolder = fullfile(studio.exportPath,'Preprocessing','motor_QC');
        if ~exist(qcFolder,'dir')
            mkdir(qcFolder);
        end

        [I3D, motorInfo] = motor(data.I, data.TR, qcFolder);

        newData = data;
        newData.I = I3D;

        if ndims(I3D) == 4
            newData.nVols = size(I3D,4);
        end

        newData.preprocessing = 'Motor slice reconstruction';
        newData.motorInfo = motorInfo;

        ts = datestr(now,'yyyymmdd_HHMMSS');

        baseStem = getCurrentNamingStem(studio);
fullName = [baseStem '_motor_' ts];

        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(sprintf('Slices: %d | Volumes per slice: %d | Minutes per slice: %.2f', ...
            motorInfo.nSlices, motorInfo.volumesPerSlice, motorInfo.minutesPerSlice));
        addLog(['Motor reconstruction complete -> ' fullName]);

    catch ME
        addLog(['MOTOR ERROR: ' ME.message]);
        errordlg(ME.message,'Motor Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  DESPIKE
% =========================================================
function despikeCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    answer = inputdlg('Z-threshold (default = 5):', ...
                      'Despike', 1, {'5'});

    if isempty(answer)
        addLog('Despiking cancelled.');
        return;
    end

    zthr = str2double(answer{1});
    if isnan(zthr) || zthr <= 0
        errordlg('Invalid Z-threshold.');
        return;
    end

    addLog(sprintf('Running voxel-wise despiking (Z = %.2f)...', zthr));
    setProgramStatus(false);
    drawnow;

    try
        ts = datestr(now,'yyyymmdd_HHMMSS');

        [outI, stats] = despike(data.I, zthr, studio.exportPath, ['despike_' ts]);

        if isfield(stats,'percentRemoved') && isfield(stats,'removedPoints')
            addLog(sprintf('Despiking removed %.4f%% of data points (%d spikes).', ...
                   stats.percentRemoved, stats.removedPoints));
        end

        if isfield(stats,'qcFile') && ~isempty(stats.qcFile)
            addLog(['Despike QC saved: ' stats.qcFile]);
        end

        newData = data;
        newData.I = single(outI);
        newData.preprocessing = sprintf('Voxel-wise MAD despiking (Z=%.3g)', zthr);
        newData.despikeStats = stats;
        newData.despikeZ = zthr;

        baseStem = getCurrentNamingStem(studio);
fullName = sprintf('%s_despike_z%s_%s', baseStem, numTag(zthr), ts);

        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Despiking complete -> ' fullName]);

    catch ME
        addLog(['DESPIKE ERROR: ' ME.message]);
        errordlg(ME.message,'Despike Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  TEMPORAL SMOOTHING / SUBSAMPLING
% =========================================================
function temporalSmoothingCallback(~,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Temporal Smoothing/Subsampling');
        return;
    end

    data = getActiveData();

    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        errordlg('Active dataset has no data.I to process.', ...
            'Temporal Smoothing/Subsampling');
        return;
    end

    if ~isfield(data,'TR') || isempty(data.TR) || ...
            ~isscalar(data.TR) || ~isfinite(data.TR) || data.TR <= 0
        errordlg('Active dataset has invalid TR.', ...
            'Temporal Smoothing/Subsampling');
        return;
    end

    % -----------------------------------------------------
    % Single modern black setup popup
    % -----------------------------------------------------
    cfg = showTemporalSmoothSubsampleDialog(data);

    if isempty(cfg) || ~isstruct(cfg) || ...
            ~isfield(cfg,'cancelled') || cfg.cancelled
        addLog('Temporal smoothing/subsampling cancelled.');
        return;
    end

    setProgramStatus(false);
    drawnow;

    try
        opts = struct();
        opts.chunkVoxels = cfg.chunkVoxels;
        opts.logFcn = [];

        newData = data;
        ts = datestr(now,'yyyymmdd_HHMMSS');
        baseStem = getCurrentNamingStem(studio);

        % =====================================================
        % MODE 1: SLIDING TEMPORAL SMOOTHING
        % =====================================================
        if strcmpi(cfg.mode,'sliding')

            winSec = cfg.winSec;

            opts.mode = 'sliding';
            opts.blockMethod = 'mean';

            addLog(sprintf(['Running temporal smoothing: sliding moving average | ' ...
                'window %.6g s | TR %.6g s'], winSec, data.TR));

            [Iout, stats] = temporalsmoothing(data.I, data.TR, winSec, opts);

            newData.I = single(Iout);
            newData.TR = stats.TRout;
            newData.nVols = stats.nVolsOut;
            newData.TotalTimeSec = stats.nVolsOut * stats.TRout;
            newData.TotalTimeMin = newData.TotalTimeSec / 60;
            newData.totalTime = newData.TotalTimeSec;
            newData.totalTimeMin = newData.TotalTimeMin;

            newData.temporalSmoothing = stats;
            newData.preprocessing = sprintf( ...
                'Temporal smoothing (sliding moving average, %.6g s)', ...
                stats.winSec);

            % avoid stale PSC/bg from older dataset version
            if isfield(newData,'PSC'), newData.PSC = []; end
            if isfield(newData,'bg'),  newData.bg  = []; end

            secTag = numTag(winSec);

            fullName = sprintf('%s_temporalSmooth_%ss_%s', ...
                baseStem, secTag, ts);

            addLog(sprintf(['Temporal smoothing complete: %.6g s window, ' ...
                '%d volumes/window, nVols %d -> %d, runtime %.2f s'], ...
                stats.winSec, stats.winVol, ...
                stats.nVolsIn, stats.nVolsOut, stats.runtimeSec));

        % =====================================================
        % MODE 2: BLOCK AVERAGING / SUBSAMPLING
        % =====================================================
        else

            nsub = cfg.nsub;
            winSec = nsub * data.TR;

            opts.mode = 'block';
            opts.blockMethod = lower(strtrim(cfg.blockMethod));

            addLog(sprintf(['Running subsampling: %s block averaging | ' ...
                'n = %d frames/block | block %.6g s | input TR %.6g s'], ...
                upper(opts.blockMethod), nsub, winSec, data.TR));

            [Iout, stats] = temporalsmoothing(data.I, data.TR, winSec, opts);

            % Correct output timing after discarded tail frames
            outTotalSec = stats.nVolsOut * stats.TRout;
            stats.totalTimeOutSec = outTotalSec;
            stats.totalTimeOutMin = outTotalSec / 60;

            newData.I = single(Iout);
            newData.TR = stats.TRout;
            newData.nVols = stats.nVolsOut;
            newData.TotalTimeSec = outTotalSec;
            newData.TotalTimeMin = outTotalSec / 60;
            newData.totalTime = newData.TotalTimeSec;
            newData.totalTimeMin = newData.TotalTimeMin;

            newData.temporalSmoothing = stats;
            newData.subsampling = stats;
            newData.preprocessing = sprintf('Subsampling (%s, n=%d)', ...
                upper(stats.blockMethod), stats.winVol);

            % avoid stale PSC/bg from older dataset version
            if isfield(newData,'PSC'), newData.PSC = []; end
            if isfield(newData,'bg'),  newData.bg  = []; end

            fullName = sprintf('%s_subsample_%s_nsub%d_%s', ...
                baseStem, lower(stats.blockMethod), stats.winVol, ts);

            addLog(sprintf(['Subsampling complete: %s, n=%d frames/block, ' ...
                'TR %.6g -> %.6g s, nVols %d -> %d, discarded tail = %d, ' ...
                'runtime %.2f s'], ...
                upper(stats.blockMethod), stats.winVol, ...
                stats.TR, stats.TRout, ...
                stats.nVolsIn, stats.nVolsOut, ...
                stats.nDiscardedTailVolumes, stats.runtimeSec));
        end

        % -----------------------------------------------------
        % Save as new active dataset
        % -----------------------------------------------------
        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        preFolder = fullfile(studio.exportPath,'Preprocessing');
        if ~exist(preFolder,'dir')
            mkdir(preFolder);
        end

        save(fullfile(preFolder,[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Saved dataset -> ' fullName]);

    catch ME
        addLog(['TEMPORAL / SUBSAMPLING ERROR: ' ME.message]);
        errordlg(ME.message,'Temporal Smoothing/Subsampling failed');
    end

    setProgramStatus(true);
end
%% =========================================================
%  MODERN TEMPORAL SMOOTHING / SUBSAMPLING POPUP
% =========================================================
function cfg = showTemporalSmoothSubsampleDialog(data)

    cfg = struct();
    cfg.cancelled = true;

    TR = double(data.TR);
    T = size(data.I, ndims(data.I));

    % ---------------- defaults ----------------
    defaultMode = 1;          % 1 = sliding, 2 = block/subsample
    defaultWinSec = 60;       % temporal smoothing default
    defaultNsub = 50;         % subsampling default
    defaultMethod = 1;        % 1 = mean, 2 = median
    defaultChunk = 50000;

    % ---------------- colors ----------------
    bg      = [0.045 0.045 0.050];
    panel   = [0.085 0.085 0.095];
    panel2  = [0.115 0.115 0.130];
    fg      = [0.96 0.96 0.96];
    fgDim   = [0.72 0.72 0.76];
    blue    = [0.20 0.48 0.95];
    green   = [0.15 0.68 0.35];
    orange  = [0.95 0.55 0.18];
    red     = [0.80 0.25 0.25];

    % ---------------- figure ----------------
    dlg = figure( ...
        'Name','Temporal Smoothing / Subsampling', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
        'Position',[300 180 760 560], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel);

    try
        movegui(dlg,'center');
    catch
    end

    % ---------------- title ----------------
    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.915 0.91 0.06], ...
        'String','Temporal Smoothing / Subsampling', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',20, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.047 0.865 0.91 0.04], ...
        'String','Choose one operation and confirm all settings in this single popup.', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'HorizontalAlignment','left');

    % ---------------- dataset info panel ----------------
    infoPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.755 0.91 0.095], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    infoStr = sprintf('Input: %d volumes     TR: %.6g s     Total time: %.2f min', ...
        T, TR, (T*TR)/60);

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.20 0.93 0.60], ...
        'String',infoStr, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.75 0.88 1.00], ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % ---------------- settings panel ----------------
    settingsPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.235 0.91 0.50], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    % operation
    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.835 0.28 0.07], ...
        'String','Operation', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    modePopup = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.35 0.83 0.58 0.08], ...
        'String',{ ...
            'Sliding temporal smoothing  -  same number of volumes', ...
            'Block averaging / subsampling  -  fewer volumes, larger TR'}, ...
        'Value',defaultMode, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@updateSummary);

    % smoothing window
    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.685 0.28 0.07], ...
        'String','Smoothing window', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    winSecEdit = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.35 0.69 0.20 0.075], ...
        'String',num2str(defaultWinSec), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.57 0.685 0.30 0.07], ...
        'String','seconds  (sliding mode)', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'HorizontalAlignment','left');

    % subsampling n
    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.535 0.28 0.07], ...
        'String','Subsampling factor', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    nsubEdit = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.35 0.54 0.20 0.075], ...
        'String',num2str(defaultNsub), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.57 0.535 0.34 0.07], ...
        'String','frames/block  (subsampling mode)', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'HorizontalAlignment','left');

    % block method
    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.385 0.28 0.07], ...
        'String','Block method', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    methodPopup = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.35 0.39 0.25 0.075], ...
        'String',{'Mean','Median'}, ...
        'Value',defaultMethod, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.62 0.385 0.30 0.07], ...
        'String','Mean is recommended default', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'HorizontalAlignment','left');

    % chunk voxels
    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.235 0.28 0.07], ...
        'String','Memory chunk', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    chunkEdit = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.35 0.24 0.20 0.075], ...
        'String',num2str(defaultChunk), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.57 0.235 0.34 0.07], ...
        'String','voxels/chunk  (keep default unless RAM issue)', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'HorizontalAlignment','left');

    % preset buttons
    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.045 0.065 0.25 0.085], ...
        'String','Preset: Smooth 60 s', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetSmooth);

    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.32 0.065 0.25 0.085], ...
        'String','Preset: Subsample n=50', ...
        'BackgroundColor',orange, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetSubsample);

    uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.595 0.065 0.25 0.085], ...
        'String','Reset Defaults', ...
        'BackgroundColor',[0.30 0.30 0.34], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@presetDefaults);

    % ---------------- summary panel ----------------
    summaryPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.115 0.91 0.10], ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.25 0.25 0.28], ...
        'ShadowColor',[0.01 0.01 0.01]);

    summaryText = uicontrol('Parent',summaryPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.025 0.12 0.95 0.76], ...
        'String','', ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',[0.70 1.00 0.80], ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % ---------------- bottom buttons ----------------
    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.56 0.035 0.22 0.06], ...
        'String','RUN PROCESSING', ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onRun);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.80 0.035 0.155 0.06], ...
        'String','CANCEL', ...
        'BackgroundColor',red, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onCancel);

    updateSummary();

    set(dlg,'Visible','on');
    waitfor(dlg);

    % =====================================================
    % Nested callbacks
    % =====================================================
    function updateSummary(~,~)

        modeVal = get(modePopup,'Value');

        winSec = str2double(get(winSecEdit,'String'));
        nsub = str2double(get(nsubEdit,'String'));
        chunkVox = str2double(get(chunkEdit,'String'));

        if ~isfinite(winSec) || winSec <= 0
            winSecTxt = 'invalid';
            winVol = NaN;
        else
            winVol = max(1, round(winSec / TR));
            winSecTxt = sprintf('%.6g s = %d frames', winSec, winVol);
        end

        if ~isfinite(nsub) || nsub < 2
            nsubTxt = 'invalid';
            outTR = NaN;
            outVols = NaN;
            discard = NaN;
        else
            nsub = round(nsub);
            outTR = nsub * TR;
            outVols = floor(T / nsub);
            discard = T - outVols * nsub;
            nsubTxt = sprintf('%d frames/block = %.6g s/block', nsub, outTR);
        end

        if ~isfinite(chunkVox) || chunkVox < 1
            chunkTxt = 'invalid';
        else
            chunkTxt = sprintf('%d voxels/chunk', round(chunkVox));
        end

        if modeVal == 1
            txt = sprintf(['SLIDING SMOOTHING selected | Window: %s | ' ...
                'Output: same TR %.6g s, same %d volumes | Chunk: %s'], ...
                winSecTxt, TR, T, chunkTxt);
        else
            methodList = get(methodPopup,'String');
            methodName = methodList{get(methodPopup,'Value')};
            txt = sprintf(['SUBSAMPLING selected | %s | Method: %s | ' ...
                'Output TR: %.6g s | Output volumes: %d | Discard tail: %d | Chunk: %s'], ...
                nsubTxt, upper(methodName), outTR, outVols, discard, chunkTxt);
        end

        if ishandle(summaryText)
            set(summaryText,'String',txt);
        end
    end

    function presetSmooth(~,~)
        set(modePopup,'Value',1);
        set(winSecEdit,'String','60');
        set(nsubEdit,'String','50');
        set(methodPopup,'Value',1);
        set(chunkEdit,'String','50000');
        updateSummary();
    end

    function presetSubsample(~,~)
        set(modePopup,'Value',2);
        set(winSecEdit,'String','60');
        set(nsubEdit,'String','50');
        set(methodPopup,'Value',1);
        set(chunkEdit,'String','50000');
        updateSummary();
    end

    function presetDefaults(~,~)
        set(modePopup,'Value',defaultMode);
        set(winSecEdit,'String',num2str(defaultWinSec));
        set(nsubEdit,'String',num2str(defaultNsub));
        set(methodPopup,'Value',defaultMethod);
        set(chunkEdit,'String',num2str(defaultChunk));
        updateSummary();
    end

    function onRun(~,~)

        modeVal = get(modePopup,'Value');

        winSec = str2double(get(winSecEdit,'String'));
        nsub = str2double(get(nsubEdit,'String'));
        chunkVox = str2double(get(chunkEdit,'String'));

        if ~isfinite(chunkVox) || chunkVox < 1
            uiwait(errordlg('Memory chunk must be a positive number.', ...
                'Invalid setting','modal'));
            return;
        end

        if modeVal == 1
            if ~isfinite(winSec) || winSec <= 0
                uiwait(errordlg('Smoothing window must be > 0 seconds.', ...
                    'Invalid smoothing window','modal'));
                return;
            end

            cfg.cancelled = false;
            cfg.mode = 'sliding';
            cfg.winSec = winSec;
            cfg.nsub = [];
            cfg.blockMethod = 'mean';
            cfg.chunkVoxels = round(chunkVox);

        else
            if ~isfinite(nsub) || nsub < 2
                uiwait(errordlg('Subsampling factor must be >= 2 frames.', ...
                    'Invalid subsampling factor','modal'));
                return;
            end

            nsub = round(nsub);
            if floor(T / nsub) < 1
                uiwait(errordlg(sprintf( ...
                    'Not enough frames. Dataset has %d volumes, but n = %d.', ...
                    T, nsub), ...
                    'Invalid subsampling factor','modal'));
                return;
            end

            methodList = get(methodPopup,'String');
            methodName = lower(methodList{get(methodPopup,'Value')});

            cfg.cancelled = false;
            cfg.mode = 'block';
            cfg.winSec = nsub * TR;
            cfg.nsub = nsub;
            cfg.blockMethod = methodName;
            cfg.chunkVoxels = round(chunkVox);
        end

        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(~,~)
        cfg.cancelled = true;
        if ishghandle(dlg)
            delete(dlg);
        end
    end
end
%% =========================================================
%  PCA / ICA
% =========================================================
function pcaCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    methodChoice = showPcaIcaMethodDialog();
    if isempty(methodChoice) || strcmpi(methodChoice,'Cancel')
        addLog('PCA / ICA cancelled.');
        return;
    end

    data = getActiveData();
    ts = datestr(now,'yyyymmdd_HHMMSS');

    setProgramStatus(false);
    drawnow;

    try
        switch upper(strtrim(methodChoice))

            % ---------------------------------------------------------
            % PCA branch
            % ---------------------------------------------------------
            case 'PCA'

                addLog('Running PCA denoising... (select PCs to remove)');

                opts = struct();
                opts.nCompMax = 50;
                opts.maxDisplayPoints = 2000;
                opts.chunkT = 250;
                opts.centerMode = 'voxel';
                opts.onApply = @(sel) decomp_onApply('PCA', sel);
                opts.onCancel = @() decomp_onCancel('PCA');

                [newData, stats] = pca_denoise(data, studio.exportPath, ['pca_' ts], opts);

                if ~isfield(stats,'applied') || ~stats.applied
                    setProgramStatus(true);
                    return;
                end

                baseStem = getCurrentNamingStem(studio);

                pcTag = 'dropPCunknown';
                if isfield(stats,'selectedComponents') && ~isempty(stats.selectedComponents)
                    pcTag = makePcDropTag(stats.selectedComponents);
                end

                fullName = sprintf('%s_pca_%s_%s', baseStem, pcTag, ts);
                keyName = makeSafeKey(fullName, studio.datasets);

                newData.preprocessing = 'PCA denoising';
                newData.displayNameFull = fullName;
                newData.sourceDatasetKey = studio.activeDataset;
                newData.pcaStats = stats;

                studio.datasets.(keyName) = newData;
                studio.activeDataset = keyName;
                studio.pipeline.preprocDone = true;

                save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
                    'newData','-v7.3');

                guidata(fig, studio);
                refreshDatasetDropdown();

                if isfield(stats,'percentExplainedRemoved')
                    addLog(sprintf('PCA removed %.2f%% variance proxy.', stats.percentExplainedRemoved));
                end

                if isfield(stats,'selectedComponents') && ~isempty(stats.selectedComponents)
                    addLog(['Dropped PCs: ' sprintf('%d ', stats.selectedComponents)]);
                end

                if isfield(stats,'qcFile') && ~isempty(stats.qcFile)
                    addLog(['PCA QC saved: ' stats.qcFile]);
                end
                if isfield(stats,'qcGlobalMeanFile') && ~isempty(stats.qcGlobalMeanFile)
                    addLog(['PCA QC saved: ' stats.qcGlobalMeanFile]);
                end
                if isfield(stats,'qcMeanImageFile') && ~isempty(stats.qcMeanImageFile)
                    addLog(['PCA QC saved: ' stats.qcMeanImageFile]);
                end
                if isfield(stats,'qcGridFiles') && ~isempty(stats.qcGridFiles)
                    for ii = 1:numel(stats.qcGridFiles)
                        addLog(['PCA QC grid saved: ' stats.qcGridFiles{ii}]);
                    end
                end

                addLog(['PCA complete -> ' fullName]);

            % ---------------------------------------------------------
            % ICA branch
            % ---------------------------------------------------------
            case 'ICA'

                addLog('Running ICA denoising... (compute ICs, then select ICs to remove)');

                opts = struct();
                opts.nCompMax = 30;              % ICA should usually be a bit lower than PCA
                opts.maxDisplayPoints = 2000;
                opts.chunkT = 250;
                opts.centerMode = 'voxel';
                opts.icaMaxIter = 400;
                opts.icaTol = 1e-5;
                opts.verbose = true;
                opts.onApply = @(sel) decomp_onApply('ICA', sel);
                opts.onCancel = @() decomp_onCancel('ICA');

                [newData, stats] = ica_denoise(data, studio.exportPath, ['ica_' ts], opts);

                if ~isfield(stats,'applied') || ~stats.applied
                    setProgramStatus(true);
                    return;
                end

                baseStem = getCurrentNamingStem(studio);

                icTag = 'dropICunknown';
                if isfield(stats,'selectedComponents') && ~isempty(stats.selectedComponents)
                    icTag = makeIcDropTag(stats.selectedComponents);
                end

                fullName = sprintf('%s_ica_%s_%s', baseStem, icTag, ts);
                keyName = makeSafeKey(fullName, studio.datasets);

                newData.preprocessing = 'ICA denoising';
                newData.displayNameFull = fullName;
                newData.sourceDatasetKey = studio.activeDataset;
                newData.icaStats = stats;

                studio.datasets.(keyName) = newData;
                studio.activeDataset = keyName;
                studio.pipeline.preprocDone = true;

                save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
                    'newData','-v7.3');

                guidata(fig, studio);
                refreshDatasetDropdown();

                if isfield(stats,'percentEnergyRemoved')
                    addLog(sprintf('ICA removed %.2f%% component-energy proxy.', stats.percentEnergyRemoved));
                end

                if isfield(stats,'selectedComponents') && ~isempty(stats.selectedComponents)
                    addLog(['Dropped ICs: ' sprintf('%d ', stats.selectedComponents)]);
                end

                if isfield(stats,'qcFile') && ~isempty(stats.qcFile)
                    addLog(['ICA QC saved: ' stats.qcFile]);
                end
                if isfield(stats,'qcGlobalMeanFile') && ~isempty(stats.qcGlobalMeanFile)
                    addLog(['ICA QC saved: ' stats.qcGlobalMeanFile]);
                end
                if isfield(stats,'qcMeanImageFile') && ~isempty(stats.qcMeanImageFile)
                    addLog(['ICA QC saved: ' stats.qcMeanImageFile]);
                end
                if isfield(stats,'qcGridFiles') && ~isempty(stats.qcGridFiles)
                    for ii = 1:numel(stats.qcGridFiles)
                        addLog(['ICA QC grid saved: ' stats.qcGridFiles{ii}]);
                    end
                end

                if isfield(stats,'converged')
                    if stats.converged
                        addLog(sprintf('ICA converged in %d iterations.', stats.nIter));
                    else
                        addLog(sprintf('ICA warning: did not fully converge in %d iterations.', stats.nIter));
                    end
                end

                addLog(['ICA complete -> ' fullName]);

            otherwise
                addLog('PCA / ICA cancelled.');
                setProgramStatus(true);
                return;
        end

    catch ME
        addLog(['PCA / ICA ERROR: ' ME.message]);
        errordlg(ME.message,'PCA / ICA Failure');
    end

    setProgramStatus(true);

    function decomp_onApply(methodName, sel)
        if isempty(sel)
            addLog([methodName ' applied: no components selected. Please wait...']);
        else
            sel = unique(sel(:)');
            addLog([methodName ' applied, dropping ' upper(methodName(1:2)) 's: ' sprintf('%d ', sel) ' - please wait...']);
        end
        drawnow;
    end

    function decomp_onCancel(methodName)
        addLog([methodName ' cancelled.']);
        setProgramStatus(true);
        drawnow;
    end
end

%% =========================================================
%  PSC COMPUTATION
% =========================================================
function computePSCCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    baseline.start = 0;
    baseline.end = min(5, data.nVols * data.TR);
    baseline.mode = 'sec';

    par = struct();
    par.interpol = 1;
    par.LPF = 0.15;
    par.HPF = 0;
    par.gaussSize = 3;
    par.gaussSig = 0.5;

    addLog('Computing PSC...');
    setProgramStatus(false);
    drawnow;

    try
        proc = computePSC(data.I, data.TR, par, baseline);

        newData = data;
        newData.PSC = single(proc.PSC);
        newData.bg = single(proc.bg);
        if isfield(proc,'TR_eff')
            newData.TR_eff = proc.TR_eff;
        end
        if isfield(proc,'nFrames')
            newData.nFrames = proc.nFrames;
        end

        P = studio_resolve_paths(studio, studio.activeDataset, studio.exportPath);
        baseStem = P.fileStem;
        fullName = [baseStem '_psc_' datestr(now,'yyyymmdd_HHMMSS')];
        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.pscDone = true;

        pscFolder = fullfile(studio.exportPath,'PSC');
if ~exist(pscFolder,'dir')
    mkdir(pscFolder);
end

save(fullfile(pscFolder,[fullName '.mat']), ...
    'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['PSC computation -> ' fullName]);

    catch ME
        addLog(['PSC ERROR: ' ME.message]);
        errordlg(ME.message,'PSC Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  FILTERING
% =========================================================
function filteringCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.','Filtering');
        return;
    end

    data = getActiveData();

    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        errordlg('Active dataset has no data.I field.','Filtering');
        return;
    end

    % One clean dark setup window.
    opts = showFilteringSetupDialog(data);

    if isempty(opts) || ...
            (isstruct(opts) && isfield(opts,'cancelled') && opts.cancelled)
        addLog('Filtering cancelled.');
        return;
    end

    ts = datestr(now,'yyyymmdd_HHMMSS');
    opts.tag = ['filter_' ts];

    filterTag = makeFilterTag(opts);

    addLog('Running Butterworth filtering...');
    addLog(sprintf('Type: %s | FcLow: %.6g Hz | FcHigh: %.6g Hz | Order: %d', ...
        upper(opts.type), opts.FcLow, opts.FcHigh, round(opts.order)));
    addLog(sprintf('Trim start: %.3g s | Trim end: %.3g s | Taper: %s', ...
        opts.trimStart, opts.trimEnd, iff(opts.useTaper,'ON','OFF')));

    setProgramStatus(false);
    drawnow;

    try
        [I_filt, stats] = filtering(data.I, data.TR, studio.exportPath, opts);

        newData = data;
        newData.I = single(I_filt);
        newData.filtering = stats;

        % Important: old PSC/bg are no longer valid after filtering.
        if isfield(newData,'PSC')
            newData.PSC = [];
        end
        if isfield(newData,'bg')
            newData.bg = [];
        end

        switch lower(stats.filterType)
            case 'low'
                newData.preprocessing = sprintf( ...
                    'Butterworth low-pass filtering, Fc=%.6g Hz, order=%d', ...
                    stats.FcHigh, stats.order);

            case 'high'
                newData.preprocessing = sprintf( ...
                    'Butterworth high-pass filtering, Fc=%.6g Hz, order=%d', ...
                    stats.FcLow, stats.order);

            case 'band'
                newData.preprocessing = sprintf( ...
                    'Butterworth band-pass filtering, %.6g-%.6g Hz, order=%d', ...
                    stats.FcLow, stats.FcHigh, stats.order);

            otherwise
                newData.preprocessing = 'Butterworth filtering';
        end

        baseStem = getCurrentNamingStem(studio);
        fullName = sprintf('%s_%s_%s', baseStem, filterTag, ts);

        keyName = makeSafeKey(fullName, studio.datasets);

        newData.displayNameFull = fullName;
        newData.sourceDatasetKey = studio.activeDataset;

        studio.datasets.(keyName) = newData;
        studio.activeDataset = keyName;
        studio.pipeline.preprocDone = true;

        preFolder = fullfile(studio.exportPath,'Preprocessing');
        if ~exist(preFolder,'dir')
            mkdir(preFolder);
        end

        save(fullfile(preFolder,[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Filtering complete -> ' fullName]);

        if isfield(stats,'qcFolder') && ~isempty(stats.qcFolder)
            addLog(['Filtering QC saved -> ' stats.qcFolder]);
        end

        addLog(sprintf('Filtering runtime: %.2f sec', stats.processingTime));

    catch ME
        addLog(['FILTER ERROR: ' ME.message]);
        errordlg(ME.message,'Filtering Failure');
    end

    setProgramStatus(true);
end

function opts = showFilteringSetupDialog(data)
% One-window dark setup dialog for Butterworth filtering.
% MATLAB 2017b compatible.

    opts = [];

    TR = data.TR;
    if numel(TR) > 1
        TR = TR(end);
    end
    TR = double(TR);

    nt = size(data.I, ndims(data.I));

    Fs = 1 / TR;
    Nyq = Fs / 2;
    totalSec = nt * TR;

    defaultHighPass = 0.001;   % default high-pass cutoff
defaultLowPass  = 0.20;    % default low-pass cutoff

defaultLow  = defaultHighPass;   % for band-pass low edge
defaultHigh = defaultLowPass;    % for band-pass high edge

    if defaultHigh >= Nyq
        defaultHigh = 0.80 * Nyq;
    end

    if defaultLow >= defaultHigh
        defaultLow = max(0.001, 0.20 * defaultHigh);
    end

    bg      = [0.04 0.04 0.045];
    panel   = [0.09 0.09 0.10];
    panel2  = [0.12 0.12 0.13];
    fg      = [0.96 0.96 0.96];
    fgDim   = [0.74 0.74 0.78];
    blue    = [0.20 0.48 0.95];
    green   = [0.12 0.68 0.35];
    red     = [0.78 0.22 0.22];
    orange  = [0.95 0.55 0.18];

    dlg = figure( ...
        'Name','Butterworth Filtering Setup', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
        'Position',[350 180 760 560], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel, ...
        'KeyPressFcn',@onKey);

    try
        movegui(dlg,'center');
    catch
    end

    % ---------------------------------------------------------------------
    % Title
    % ---------------------------------------------------------------------
    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.04 0.925 0.92 0.055], ...
        'String','Butterworth Filtering', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',20, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    infoStr = sprintf([ ...
        'TR = %.0f ms   |   Fs = %.4g Hz   |   Nyquist = %.4g Hz   |   Volumes = %d   |   Duration = %.2f min'], ...
        TR*1000, Fs, Nyq, nt, totalSec/60);

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.04 0.875 0.92 0.035], ...
        'String',infoStr, ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    % ---------------------------------------------------------------------
    % Main panel
    % ---------------------------------------------------------------------
    mainPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.04 0.18 0.92 0.67], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.35 0.35 0.35], ...
        'BorderType','line');

    % Guidance box
   uicontrol('Parent',mainPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.04 0.805 0.92 0.145], ...
    'String',{ ...
        'Recommended default for fUSI preprocessing:', ...
        'Band-pass 0.001-0.20 Hz, order 4, no trimming.', ...
        'Use trimming only if the beginning/end contains unstable frames.'}, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor',[0.95 0.88 0.55], ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

    % Filter type
    addLabel(mainPanel, 'Filter type', 0.06, 0.72);
    hType = uicontrol('Parent',mainPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.28 0.715 0.28 0.065], ...
        'String',{'Band-pass','Low-pass','High-pass'}, ...
        'Value',1, ...
        'BackgroundColor',[0.16 0.16 0.17], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@onTypeChanged);

    % Order
    addLabel(mainPanel, 'Order', 0.60, 0.72);
    hOrder = uicontrol('Parent',mainPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.73 0.715 0.20 0.065], ...
        'String',{'1','2','3','4','5','6'}, ...
        'Value',4, ...
        'BackgroundColor',[0.16 0.16 0.17], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold');

    % Cutoffs
    addLabel(mainPanel, 'Low cutoff FcLow (Hz)', 0.06, 0.59);
    hLow = uicontrol('Parent',mainPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.36 0.585 0.20 0.065], ...
        'String',num2str(defaultLow,'%.6g'), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    addLabel(mainPanel, 'High cutoff FcHigh (Hz)', 0.06, 0.47);
    hHigh = uicontrol('Parent',mainPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.36 0.465 0.20 0.065], ...
        'String',num2str(defaultHigh,'%.6g'), ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    uicontrol('Parent',mainPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.60 0.47 0.34 0.17], ...
        'String',{ ...
            'Band-pass uses both cutoffs.', ...
            'Low-pass uses only high cutoff.', ...
            'High-pass uses only low cutoff.'}, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    % Trimming
    addLabel(mainPanel, 'Trim start (sec)', 0.06, 0.33);
    hTrimStart = uicontrol('Parent',mainPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.36 0.325 0.20 0.065], ...
        'String','0', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    addLabel(mainPanel, 'Trim end (sec)', 0.06, 0.21);
    hTrimEnd = uicontrol('Parent',mainPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.36 0.205 0.20 0.065], ...
        'String','0', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    hTaper = uicontrol('Parent',mainPanel,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.60 0.315 0.34 0.07], ...
        'String','Use Gaussian taper at trim edges', ...
        'Value',1, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold');

    hSaveQC = uicontrol('Parent',mainPanel,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.60 0.235 0.34 0.07], ...
        'String','Save filtering QC plots', ...
        'Value',1, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold');

    addLabel(mainPanel, 'Chunk size voxels', 0.60, 0.13);
    hChunk = uicontrol('Parent',mainPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.80 0.125 0.14 0.06], ...
        'String','50000', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    hStatus = uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.04 0.105 0.92 0.04], ...
        'String','Ready. Defaults are pre-selected.', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',[0.60 0.90 1.00], ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center');

    % Buttons
    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','RESET DEFAULTS', ...
        'Units','normalized', ...
        'Position',[0.04 0.035 0.20 0.06], ...
        'FontName','Arial', ...
        'FontWeight','bold', ...
        'FontSize',12, ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'Callback',@onReset);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','RUN FILTERING', ...
        'Units','normalized', ...
        'Position',[0.52 0.035 0.24 0.065], ...
        'FontName','Arial', ...
        'FontWeight','bold', ...
        'FontSize',13, ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'Callback',@onRun);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','CANCEL', ...
        'Units','normalized', ...
        'Position',[0.78 0.035 0.18 0.065], ...
        'FontName','Arial', ...
        'FontWeight','bold', ...
        'FontSize',13, ...
        'BackgroundColor',red, ...
        'ForegroundColor','w', ...
        'Callback',@onCancel);

    onTypeChanged();

    set(dlg,'Visible','on');
    drawnow;
    waitfor(dlg);

    % ---------------------------------------------------------------------
    % Nested helpers
    % ---------------------------------------------------------------------
    function addLabel(parent, str, x, y)
        uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',[x y 0.28 0.055], ...
            'String',str, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',11, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function onTypeChanged(~,~)

    typeIdx = get(hType,'Value');

    switch typeIdx

        case 1
            % Band-pass: use both cutoffs
            set(hLow,  'String', num2str(defaultHighPass,'%.6g'));
            set(hHigh, 'String', num2str(defaultLowPass,'%.6g'));

            set(hLow,  'Enable','on');
            set(hHigh, 'Enable','on');

            msg = 'Band-pass selected: 0.001-0.20 Hz will be used.';
            col = [0.60 0.90 1.00];

        case 2
            % Low-pass: use only high cutoff
            set(hLow,  'String','0');
            set(hHigh, 'String', num2str(defaultLowPass,'%.6g'));

            set(hLow,  'Enable','off');
            set(hHigh, 'Enable','on');

            msg = 'Low-pass selected: only FcHigh = 0.20 Hz will be used.';
            col = [0.95 0.82 0.35];

        case 3
            % High-pass: use only low cutoff
            set(hLow,  'String', num2str(defaultHighPass,'%.6g'));
            set(hHigh, 'String','0');

            set(hLow,  'Enable','on');
            set(hHigh, 'Enable','off');

            msg = 'High-pass selected: only FcLow = 0.001 Hz will be used.';
            col = [0.95 0.60 0.35];

        otherwise
            msg = 'Ready.';
            col = [0.60 0.90 1.00];
    end

    if ishandle(hStatus)
        set(hStatus,'String',msg,'ForegroundColor',col);
    end
end
    function onReset(~,~)

        set(hType,'Value',1);
        set(hOrder,'Value',4);
      set(hLow,'String',num2str(defaultHighPass,'%.6g'));
set(hHigh,'String',num2str(defaultLowPass,'%.6g'));
        set(hTrimStart,'String','0');
        set(hTrimEnd,'String','0');
        set(hTaper,'Value',1);
        set(hSaveQC,'Value',1);
        set(hChunk,'String','50000');

        set(hStatus, ...
            'String','Defaults restored: Band-pass 0.001-0.20 Hz, order 4, no trimming.', ...
            'ForegroundColor',[0.60 0.90 1.00]);

        onTypeChanged();
    end

    function onRun(~,~)

        typeStrings = get(hType,'String');
        typeChoice = typeStrings{get(hType,'Value')};

        switch typeChoice
            case 'Band-pass'
                filtType = 'band';
            case 'Low-pass'
                filtType = 'low';
            case 'High-pass'
                filtType = 'high';
            otherwise
                filtType = 'band';
        end

        FcLow = str2double(strtrim(get(hLow,'String')));
        FcHigh = str2double(strtrim(get(hHigh,'String')));

        orderStrings = get(hOrder,'String');
        orderVal = str2double(orderStrings{get(hOrder,'Value')});

        trimStart = str2double(strtrim(get(hTrimStart,'String')));
        trimEnd = str2double(strtrim(get(hTrimEnd,'String')));
        chunkSize = str2double(strtrim(get(hChunk,'String')));

        if ~isfinite(FcLow)
            showBad('FcLow must be numeric.');
            return;
        end

        if ~isfinite(FcHigh)
            showBad('FcHigh must be numeric.');
            return;
        end

        if ~isfinite(orderVal) || orderVal < 1 || orderVal > 6
            showBad('Order must be between 1 and 6.');
            return;
        end

        if ~isfinite(trimStart) || trimStart < 0
            showBad('Trim start must be >= 0 sec.');
            return;
        end

        if ~isfinite(trimEnd) || trimEnd < 0
            showBad('Trim end must be >= 0 sec.');
            return;
        end

        if ~isfinite(chunkSize) || chunkSize < 1000
            showBad('Chunk size must be at least 1000 voxels.');
            return;
        end

        trimStartFrames = round(trimStart / TR);
        trimEndFrames = round(trimEnd / TR);

        if 1 + trimStartFrames >= nt - trimEndFrames
            showBad('Trimming removes the whole signal. Reduce trim values.');
            return;
        end

        switch filtType
            case 'low'
                if FcHigh <= 0 || FcHigh >= Nyq
                    showBad(sprintf('Low-pass FcHigh must be > 0 and < Nyquist %.6g Hz.', Nyq));
                    return;
                end
                FcLow = 0;

            case 'high'
                if FcLow <= 0 || FcLow >= Nyq
                    showBad(sprintf('High-pass FcLow must be > 0 and < Nyquist %.6g Hz.', Nyq));
                    return;
                end
                FcHigh = 0;

            case 'band'
                if FcLow <= 0
                    showBad('Band-pass FcLow must be > 0.');
                    return;
                end
                if FcHigh <= 0 || FcHigh >= Nyq
                    showBad(sprintf('Band-pass FcHigh must be > 0 and < Nyquist %.6g Hz.', Nyq));
                    return;
                end
                if FcLow >= FcHigh
                    showBad('Band-pass requires FcLow < FcHigh.');
                    return;
                end
        end

        opts = struct();
        opts.type = filtType;
        opts.FcLow = FcLow;
        opts.FcHigh = FcHigh;
        opts.order = round(orderVal);
        opts.trimStart = trimStart;
        opts.trimEnd = trimEnd;
        opts.useTaper = logical(get(hTaper,'Value'));
        opts.saveQC = logical(get(hSaveQC,'Value'));
        opts.chunkSize = round(chunkSize);
        opts.cancelled = false;

        if ishandle(dlg)
            delete(dlg);
        end
    end

    function showBad(msg)
        if ishandle(hStatus)
            set(hStatus, ...
                'String',msg, ...
                'ForegroundColor',orange);
        end
    end

    function onCancel(~,~)
        opts = [];
        if ishandle(dlg)
            delete(dlg);
        end
    end

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel();
            elseif strcmpi(ev.Key,'return')
                onRun();
            end
        catch
        end
    end
end

%% =========================================================
%  COREGISTRATION
% =========================================================
    function coregCallback(~,~)

    studio = guidata(fig);
    addLog('--- Atlas Coregistration ---');

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    closeLingeringQCFigures();

    setProgramStatus(false);
    drawnow;

    try
        RegOut = coreg(studio);

        if isempty(RegOut)
            addLog('Coregistration cancelled.');
            setProgramStatus(true);
            return;
        end

        % -----------------------------------------------------
        % 2D coronal registration output
        % -----------------------------------------------------
        if isstruct(RegOut) && ...
                ((isfield(RegOut,'type') && ~isempty(strfind(lower(RegOut.type),'coronal_2d'))) || ...
                 (isfield(RegOut,'A') && isfield(RegOut,'outputSize') && isfield(RegOut,'atlasSliceIndex')))

            studio.atlasReg2D = RegOut;
            studio.atlasRegistrationMode = '2D coronal';

            if isfield(RegOut,'savedFile') && ~isempty(RegOut.savedFile)
                studio.atlasReg2DFile = RegOut.savedFile;
            else
                studio.atlasReg2DFile = '';
            end

            % Avoid confusing 2D Reg2D with old 3D Transf
            studio.atlasTransform = [];
            studio.atlasTransformFile = '';

            guidata(fig, studio);

            addLog('2D coronal atlas registration completed.');
            addLog('Reg2D stored in studio.atlasReg2D.');

            if ~isempty(studio.atlasReg2DFile)
                addLog(['Reg2D file: ' studio.atlasReg2DFile]);
            end

        % -----------------------------------------------------
        % 3D registration output
        % -----------------------------------------------------
        elseif isstruct(RegOut) && isfield(RegOut,'M')

            studio.atlasTransform = RegOut;
            studio.atlasRegistrationMode = '3D';

            if isfield(studio,'exportPath') && ~isempty(studio.exportPath)
                studio.atlasTransformFile = fullfile(studio.exportPath,'Registration','Transformation.mat');
            else
                studio.atlasTransformFile = 'Transformation.mat';
            end

            % Avoid stale 2D registration after new 3D registration
            studio.atlasReg2D = [];
            studio.atlasReg2DFile = '';

            guidata(fig, studio);

            addLog('3D atlas coregistration completed.');
            addLog('3D transformation stored in studio.atlasTransform.');
            addLog(['Transformation file: ' studio.atlasTransformFile]);

        else
            guidata(fig, studio);
            addLog('Coregistration finished, but output type was not recognized.');
        end

    catch ME
        addLog(['COREG ERROR: ' ME.message]);
        errordlg(ME.message,'Coregistration Failed');
    end

    setProgramStatus(true);
end
%% =========================================================
%  SEGMENTATION
% =========================================================
function segmentationCallback(~,~)

    studio = guidata(fig);
    addLog('--- Segmentation ---');

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

  has3D = isfield(studio,'atlasTransform') && ~isempty(studio.atlasTransform);
has2D = isfield(studio,'atlasReg2D') && ~isempty(studio.atlasReg2D);

if ~has3D && ~has2D
    warndlg('Run Registration to Atlas first.');
    addLog('Segmentation cancelled: no atlas registration found.');
    return;
end
    setProgramStatus(false);
    drawnow;

    try
        addLog('Segmentation callback opened successfully.');
        msgbox('Segmentation callback placeholder. Insert your segmentation .mat workflow here.', ...
               'Segmentation');
    catch ME
        addLog(['SEGMENTATION ERROR: ' ME.message]);
        errordlg(ME.message,'Segmentation Failed');
    end

    setProgramStatus(true);
end

%% =========================================================
%  GROUP ANALYSIS
% =========================================================
function groupAnalysisCallback(~,~)

    studio = guidata(fig);
    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Group Analysis');
        return;
    end

    addLog('Opening Group Analysis...');
    setProgramStatus(false);
    drawnow;

    onClose = @() groupAnalysisOnClose();

    try
        gaFig = GroupAnalysis(studio, onClose);

        if isempty(gaFig) || ~ishandle(gaFig)
            addLog('Group Analysis did not return a valid figure handle.');
            setProgramStatus(true);
            return;
        end

        addlistener(gaFig,'ObjectBeingDestroyed', @(~,~) onClose());

    catch ME
        addLog(['GROUP ANALYSIS ERROR: ' ME.message]);
        errordlg(ME.message,'Group Analysis');
        setProgramStatus(true);
    end

    function groupAnalysisOnClose()
        if ~isempty(fig) && ishandle(fig)
            setProgramStatus(true);
            addLog('Group Analysis closed.');
        end
    end
end

%% =========================================================
%  FUNCTIONAL CONNECTIVITY
% =========================================================
function functionalConnectivityCallback(~,~)

    studio = guidata(fig);
    addLog('Opening Functional Connectivity...');

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        addLog('[FC] Load a dataset first.');
        errordlg('Load data first.','Functional Connectivity');
        return;
    end

    data = getActiveData();

    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        addLog('[FC] Active dataset has no .I.');
        errordlg('Active dataset has no .I field.','Functional Connectivity');
        return;
    end

    if ~isfield(data,'TR') || isempty(data.TR) || ...
            ~isscalar(data.TR) || ~isfinite(data.TR) || data.TR <= 0
        addLog('[FC] Active dataset has invalid TR.');
        errordlg('Active dataset has invalid TR.','Functional Connectivity');
        return;
    end

    % -----------------------------------------------------
    % Single modern black setup popup
    % -----------------------------------------------------
    cfg = showFunctionalConnectivitySetupDialog(studio, data);

    if isempty(cfg) || ~isstruct(cfg) || ...
            ~isfield(cfg,'cancelled') || cfg.cancelled
        addLog('[FC] Functional Connectivity cancelled.');
        return;
    end

    saveRoot = studio.exportPath;
    if isempty(saveRoot) || ~exist(saveRoot,'dir')
        saveRoot = pwd;
    end

    tag = ['fc_' datestr(now,'yyyymmdd_HHMMSS')];

    % -----------------------------------------------------
    % Build data object for FunctionalConnectivity
    % -----------------------------------------------------
    dataFC = data;

    % Functional source
    if strcmpi(cfg.functionalSource,'psc')
        dataFC.I = single(data.PSC);
        dataFC.functionalSource = 'PSC';
    else
        dataFC.I = single(data.I);
        dataFC.functionalSource = 'I';
    end

    % Display / bookkeeping
    dataFC.name = getDatasetDisplayName(studio, studio.activeDataset);
    dataFC.analysisDir = saveRoot;
dataFC.exportPath = studio.exportPath;
dataFC.registrationPath = fcGetRegistrationStartDir(studio);
    if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
        dataFC.loadedPath = studio.loadedPath;
    end

    % Mask
    switch lower(cfg.maskMode)
        case 'studio'
            dataFC.mask = logical(cfg.mask);

        case 'loaded'
            dataFC.mask = logical(cfg.mask);

        case 'none'
            if isfield(dataFC,'mask')
                dataFC.mask = [];
            end
            if isfield(dataFC,'brainMask')
                dataFC.brainMask = [];
            end

        otherwise
            % auto mask will be generated inside FunctionalConnectivity
            if isfield(dataFC,'mask')
                dataFC.mask = [];
            end
            if isfield(dataFC,'brainMask')
                dataFC.brainMask = [];
            end
    end

% Underlay / anatomical reference
dataFC.anatIsDisplayReady = false;

if ~isempty(cfg.anat)
    dataFC.anat = cfg.anat;
    dataFC.bg = cfg.anat;
    dataFC.underlay = cfg.anat;

    if isfield(cfg,'anatIsDisplayReady') && ~isempty(cfg.anatIsDisplayReady)
        dataFC.anatIsDisplayReady = logical(cfg.anatIsDisplayReady);
    end

elseif isfield(data,'bg') && ~isempty(data.bg)
    dataFC.anat = data.bg;
    dataFC.bg = data.bg;
    dataFC.underlay = data.bg;
    dataFC.anatIsDisplayReady = false;
end
    % ROI atlas / region atlas
    if ~isempty(cfg.roiAtlas)
        dataFC.roiAtlas = round(double(cfg.roiAtlas));
    end

    % -----------------------------------------------------
    % Options for FunctionalConnectivity
    % -----------------------------------------------------
    opts = struct();
    opts.datasetName = studio.activeDataset;
    opts.functionalField = 'I';

    opts.seedBoxSize = cfg.seedBoxSize;
    opts.roiMinVox = cfg.roiMinVox;
    opts.chunkVox = cfg.chunkVox;

    opts.askMaskAtStart = false;    % important: no extra popup
    opts.askAtlasAtStart = false;   % important: no extra popup
    opts.debugRethrow = false;
opts.defaultUnderlayMode = cfg.defaultUnderlayMode;
if isfield(cfg,'anatIsDisplayReady') && ~isempty(cfg.anatIsDisplayReady)
    opts.anatIsDisplayReady = logical(cfg.anatIsDisplayReady);
else
    opts.anatIsDisplayReady = false;
end
% -----------------------------------------------------
% FC underlay display style
% 3 = SCM / VideoGUI recommended display normalization
% -----------------------------------------------------
if isfield(cfg,'defaultUnderlayViewMode')
    opts.defaultUnderlayViewMode = cfg.defaultUnderlayViewMode;
else
    opts.defaultUnderlayViewMode = 5;   % 5 = SCM log/median underlay
end

if isfield(cfg,'underlayBrightness')
    opts.underlayBrightness = cfg.underlayBrightness;
else
    opts.underlayBrightness = -0.04;
end

if isfield(cfg,'underlayContrast')
    opts.underlayContrast = cfg.underlayContrast;
else
    opts.underlayContrast = 1.10;
end

if isfield(cfg,'underlayGamma')
    opts.underlayGamma = cfg.underlayGamma;
else
    opts.underlayGamma = 0.95;
end

    if ~isempty(cfg.roiNameTable)
        opts.roiNameTable = cfg.roiNameTable;
    else
        opts.roiNameTable = struct('labels',[],'names',{{}});
    end

    opts.statusFcn = @(isReady) setProgramStatus(isReady);
    opts.logFcn = @(m) addLog(['[FC] ' m]);

    % Useful paths for the FC GUI file pickers
 opts.saveRoot = saveRoot;
opts.loadedPath = studio.loadedPath;
opts.exportPath = studio.exportPath;

% Important for atlas / histology / region-name loading
opts.registrationPath = fcGetRegistrationStartDir(studio);
opts.startDirAtlas = opts.registrationPath;
opts.startDirNames = opts.registrationPath;
opts.startDirUnderlay = opts.registrationPath;

% New FC GUI behaviour
opts.showAtlasInSeedTab = false;
opts.seedOverlayAtlas = false;
opts.defaultUnderlayMode = cfg.defaultUnderlayMode;
opts.preferredUnderlayStyle = 'scm_log_median';

    addLog('[FC] Setup complete.');
    addLog(['[FC] Functional source: ' upper(cfg.functionalSource)]);
    addLog(['[FC] Mask mode: ' cfg.maskMode]);
  addLog(['[FC] Underlay mode: ' cfg.defaultUnderlayMode]);

if isfield(cfg,'defaultUnderlayViewMode') && cfg.defaultUnderlayViewMode == 3
    addLog('[FC] Underlay display: SCM/Video recommended normalization.');
end

    if ~isempty(cfg.roiAtlas)
        addLog('[FC] ROI atlas preloaded.');
    else
        addLog('[FC] ROI atlas not preloaded.');
    end

    if ~isempty(cfg.roiNameTable) && isfield(cfg.roiNameTable,'labels')
        addLog(sprintf('[FC] Region names preloaded: %d labels.', ...
            numel(cfg.roiNameTable.labels)));
    else
        addLog('[FC] Region names not preloaded.');
    end

    setProgramStatus(false);
    drawnow;

    try
        fcFig = FunctionalConnectivity(dataFC, saveRoot, tag, opts);

        if ~isempty(fcFig) && ishandle(fcFig)
            addlistener(fcFig,'ObjectBeingDestroyed', @(~,~) fcOnClose());
        else
            setProgramStatus(true);
        end

        addLog('[FC] GUI launched.');

    catch ME
        setProgramStatus(true);
        addLog(['FC ERROR: ' ME.message]);
        errordlg(ME.message,'Functional Connectivity');
    end

    function fcOnClose()
        if ~isempty(fig) && ishandle(fig)
            setProgramStatus(true);
            addLog('[FC] Closed.');
        end
    end
end

%% =========================================================
%  MODERN FUNCTIONAL CONNECTIVITY SETUP POPUP
% =========================================================
function cfg = showFunctionalConnectivitySetupDialog(studio, data)

    cfg = struct();
    cfg.cancelled = true;

    I = data.I;
    nd = ndims(I);
    sz = size(I);

    if nd == 3
        Y = sz(1);
        X = sz(2);
        Z = 1;
        T = sz(3);
        dimTxt = sprintf('%d x %d x %d', Y, X, T);
    elseif nd == 4
        Y = sz(1);
        X = sz(2);
        Z = sz(3);
        T = sz(4);
        dimTxt = sprintf('%d x %d x %d x %d', Y, X, Z, T);
    else
        error('Functional Connectivity requires 3D [Y X T] or 4D [Y X Z T] data.');
    end

    TR = double(data.TR);

    hasPSC = isfield(data,'PSC') && ~isempty(data.PSC) && isnumeric(data.PSC);
    hasDataBg = isfield(data,'bg') && ~isempty(data.bg) && isnumeric(data.bg);

    hasStudioMask = isfield(studio,'mask') && ~isempty(studio.mask);
    hasStudioAnat = false;

    if isfield(studio,'anatomicalReference') && ~isempty(studio.anatomicalReference)
        hasStudioAnat = true;
    elseif isfield(studio,'anatomicalReferenceRaw') && ~isempty(studio.anatomicalReferenceRaw)
        hasStudioAnat = true;
    end

    loadedMask = [];
loadedAtlas = [];
loadedAnat = [];
loadedAnatDisplayReady = false;
loadedNames = struct('labels',[],'names',{{}});

    loadedMaskName = '';
    loadedAtlasName = '';
    loadedAnatName = '';
    loadedNamesName = '';

    % ---------------- colors ----------------
    bg      = [0.045 0.045 0.050];
    panel   = [0.085 0.085 0.095];
    panel2  = [0.115 0.115 0.130];
    fg      = [0.96 0.96 0.96];
    fgDim   = [0.72 0.72 0.76];
    blue    = [0.20 0.48 0.95];
    green   = [0.15 0.68 0.35];
    orange  = [0.95 0.55 0.18];
    red     = [0.80 0.25 0.25];

    dlg = figure( ...
        'Name','Functional Connectivity Setup', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
       'Position',[150 40 1120 820], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel, ...
        'KeyPressFcn',@onKey);

    try
        movegui(dlg,'center');
    catch
    end

    % ---------------- title ----------------
    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.93 0.91 0.05], ...
        'String','Functional Connectivity Setup', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',21, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.047 0.885 0.91 0.035], ...
        'String','Preload functional data, mask, underlay, ROI atlas and region names before launching the FC GUI.', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'HorizontalAlignment','left');

    % ---------------- info panel ----------------
    infoPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.785 0.91 0.085], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    infoStr = sprintf('Input size: %s     TR: %.6g s     Volumes: %d     Duration: %.2f min', ...
        dimTxt, TR, T, (T*TR)/60);

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.22 0.93 0.58], ...
        'String',infoStr, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.75 0.88 1.00], ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % ---------------- settings panel ----------------
    settingsPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.225 0.91 0.54], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.30 0.30 0.34], ...
        'ShadowColor',[0.02 0.02 0.02]);

    % Functional source
    funcList = {'Active data.I'};
    if hasPSC
        funcList{end+1} = 'PSC field';
    end

    addLabel(settingsPanel,'Functional signal',0.045,0.865);
    ddFunc = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.31 0.865 0.30 0.07], ...
        'String',funcList, ...
        'Value',1, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.64 0.855 0.31 0.09], ...
        'String',{'Usually use active data.I.'; 'Use PSC only if already computed.'}, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    % Mask
    addLabel(settingsPanel,'Mask',0.045,0.720);
    ddMask = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.31 0.720 0.30 0.07], ...
        'String',{'Auto mask','Use Studio mask','Use loaded mask','No mask'}, ...
        'Value',fcDefaultMaskValue(), ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    btnLoadMask = uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.64 0.720 0.15 0.07], ...
        'String','Load mask', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Callback',@onLoadMask);

    txtMask = uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.81 0.710 0.15 0.09], ...
        'String','', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',9, ...
        'HorizontalAlignment','left');

    % Underlay
    addLabel(settingsPanel,'Underlay / anatomy',0.045,0.575);
    ddUnderlay = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
    'Units','normalized', ...
    'Position',[0.31 0.575 0.30 0.07], ...
    'String',{ ...
    'SCM log/median underlay [recommended]', ...
    'Mean functional', ...
    'Median functional', ...
    'data.bg / PSC bg', ...
    'Mask Editor anatomical underlay', ...
    'Loaded underlay / histology'}, ...
'Value',1, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@updateSummary);

    btnLoadUnderlay = uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.64 0.575 0.15 0.07], ...
        'String','Load underlay', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Callback',@onLoadUnderlay);

    txtUnderlay = uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.81 0.565 0.15 0.09], ...
        'String','', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',9, ...
        'HorizontalAlignment','left');


    % ROI Atlas
    addLabel(settingsPanel,'ROI atlas / label map',0.045,0.430);
    ddAtlas = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.31 0.430 0.30 0.07], ...
        'String',{'No atlas','Use active dataset atlas','Use loaded atlas'}, ...
        'Value',fcDefaultAtlasValue(), ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    btnLoadAtlas = uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.64 0.430 0.15 0.07], ...
        'String','Load labels', ...
        'BackgroundColor',orange, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Callback',@onLoadAtlas);

    txtAtlas = uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.81 0.420 0.15 0.09], ...
        'String','', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',9, ...
        'HorizontalAlignment','left');

    % Region names
    addLabel(settingsPanel,'Region names',0.045,0.285);
    ddNames = uicontrol('Parent',settingsPanel,'Style','popupmenu', ...
        'Units','normalized', ...
        'Position',[0.31 0.285 0.30 0.07], ...
        'String',{'No region names','Use loaded names'}, ...
        'Value',1, ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Callback',@updateSummary);

    btnLoadNames = uicontrol('Parent',settingsPanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.64 0.285 0.15 0.07], ...
        'String','Load names', ...
        'BackgroundColor',orange, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Callback',@onLoadNames);

    txtNames = uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.81 0.275 0.15 0.09], ...
        'String','', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',9, ...
        'HorizontalAlignment','left');

    % Numeric settings
    addLabel(settingsPanel,'Seed box size',0.045,0.135);
    edSeedBox = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.31 0.140 0.10 0.065], ...
        'String','3', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    uicontrol('Parent',settingsPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.43 0.125 0.12 0.09], ...
        'String','pixels', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    fcLabelSmall(settingsPanel,'ROI min vox',0.57,0.135);
    edMinVox = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.70 0.140 0.09 0.065], ...
        'String','9', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    fcLabelSmall(settingsPanel,'Chunk',0.81,0.135);
    edChunk = uicontrol('Parent',settingsPanel,'Style','edit', ...
        'Units','normalized', ...
        'Position',[0.89 0.140 0.07 0.065], ...
        'String','6000', ...
        'BackgroundColor',[0.02 0.02 0.025], ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Callback',@updateSummary);

    % Summary panel
    summaryPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.045 0.115 0.91 0.085], ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',[0.25 0.25 0.28], ...
        'ShadowColor',[0.01 0.01 0.01]);

    summaryText = uicontrol('Parent',summaryPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.025 0.10 0.95 0.80], ...
        'String','', ...
        'BackgroundColor',[0.035 0.035 0.040], ...
        'ForegroundColor',[0.70 1.00 0.80], ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    % Bottom buttons
    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.045 0.035 0.20 0.06], ...
        'String','AUTO SETUP', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@onAutoSetup);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.54 0.035 0.24 0.06], ...
        'String','RUN CONNECTIVITY', ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onRun);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.80 0.035 0.155 0.06], ...
        'String','CANCEL', ...
        'BackgroundColor',red, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onCancel);

  updateFileLabels();
updateSummary();

% Make this setup popup more readable
fcScaleFcSetupFonts(dlg);

set(dlg,'Visible','on');
waitfor(dlg);

    % =====================================================
    % Nested UI helpers
    % =====================================================
    function addLabel(parent, str, x, y)
        uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',[x y 0.24 0.06], ...
            'String',str, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',12, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function fcLabelSmall(parent, str, x, y)
        uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',[x y 0.12 0.06], ...
            'String',str, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',10, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function v = fcDefaultMaskValue()
        if hasStudioMask
            v = 2;
        else
            v = 1;
        end
    end

   function v = fcDefaultUnderlayValue()
    % Always pre-select SCM/Video recommended underlay display.
    v = 1;
end

    function v = fcDefaultAtlasValue()
        if fcDataHasAtlas(data,Y,X,Z)
            v = 2;
        else
            v = 1;
        end
    end

    function updateFileLabels()
        if isempty(loadedMaskName)
            set(txtMask,'String','no file');
        else
            set(txtMask,'String',shortTxt(loadedMaskName,18));
        end

        if isempty(loadedAnatName)
            set(txtUnderlay,'String','no file');
        else
            set(txtUnderlay,'String',shortTxt(loadedAnatName,18));
        end

        if isempty(loadedAtlasName)
            set(txtAtlas,'String','no file');
        else
            set(txtAtlas,'String',shortTxt(loadedAtlasName,18));
        end

        if isempty(loadedNamesName)
            set(txtNames,'String','no file');
        else
            set(txtNames,'String',shortTxt(loadedNamesName,18));
        end
    end

    function updateSummary(~,~)

        funcStrings = get(ddFunc,'String');
        funcTxt = funcStrings{get(ddFunc,'Value')};

        maskStrings = get(ddMask,'String');
        maskTxt = maskStrings{get(ddMask,'Value')};

        underStrings = get(ddUnderlay,'String');
        underTxt = underStrings{get(ddUnderlay,'Value')};

        atlasStrings = get(ddAtlas,'String');
        atlasTxt = atlasStrings{get(ddAtlas,'Value')};

        namesStrings = get(ddNames,'String');
        namesTxt = namesStrings{get(ddNames,'Value')};

        seedBox = str2double(get(edSeedBox,'String'));
        roiMinVox = str2double(get(edMinVox,'String'));
        chunkVox = str2double(get(edChunk,'String'));

        txt = sprintf(['%s | Mask: %s | Underlay: %s | Atlas: %s | Names: %s | ' ...
            'Seed box: %g | ROI min vox: %g | Chunk: %g'], ...
            funcTxt, maskTxt, underTxt, atlasTxt, namesTxt, ...
            seedBox, roiMinVox, chunkVox);

        if ishandle(summaryText)
            set(summaryText,'String',txt);
        end
    end

    function onAutoSetup(~,~)
        if hasPSC
            set(ddFunc,'Value',1);
        end

        if hasStudioMask
            set(ddMask,'Value',2);
        else
            set(ddMask,'Value',1);
        end

       % Always use SCM/Video recommended display by default.
set(ddUnderlay,'Value',1);

        if fcDataHasAtlas(data,Y,X,Z)
            set(ddAtlas,'Value',2);
        else
            set(ddAtlas,'Value',1);
        end

        updateSummary();
    end

    function onLoadMask(~,~)
        startDir = fcSetupStartDir(studio);
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, ...
            'Load FC mask MAT', startDir);

        if isequal(f,0)
            return;
        end

        try
            S = load(fullfile(p,f));
            loadedMask = fcStudioPickVolume(S,Y,X,Z,true);
            if isempty(loadedMask)
                errordlg('No compatible mask found in selected MAT file.','FC mask');
                return;
            end
            loadedMaskName = f;
            set(ddMask,'Value',3);
            updateFileLabels();
            updateSummary();
        catch ME
            errordlg(ME.message,'FC mask load error');
        end
    end

   function onLoadUnderlay(~,~)
   startDir = fcGetRegistrationStartDir(studio);

[f,p] = fc_uigetfile_start( ...
        {'*.mat;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay / histology files (*.mat,*.png,*.jpg,*.tif)'}, ...
        'Load FC underlay / histology / anatomy', startDir);

    if isequal(f,0)
        return;
    end

    try
        [loadedAnat, loadedAnatDisplayReady] = fcStudioReadUnderlay(fullfile(p,f),Y,X,Z);

        loadedAnatName = f;
        set(ddUnderlay,'Value',6);

        updateFileLabels();
        updateSummary();

    catch ME
        errordlg(ME.message,'FC underlay load error');
    end
end

 function onLoadAtlas(~,~)
    startDir = fcGetRegistrationStartDir(studio);

    [f,p] = fc_uigetfile_start( ...
        {'*.mat;*.nii;*.nii.gz;*.tif;*.tiff', ...
         'ROI label atlas files (*.mat,*.nii,*.nii.gz,*.tif)'}, ...
        'Load FC ROI atlas / integer region labels', startDir);

    if isequal(f,0)
        return;
    end

    try
        loadedAtlas = fcStudioReadAtlas(fullfile(p,f),Y,X,Z);

        if isempty(loadedAtlas)
            errordlg({ ...
                'No compatible ROI atlas label map found.', ...
                '', ...
                'Important:', ...
                '- Histology belongs under Load underlay.', ...
                '- Colored regions underlay is only a display image.', ...
                '- FC ROI heatmap needs an integer region-label volume.'}, ...
                'FC atlas');
            return;
        end

        loadedAtlas = round(double(loadedAtlas));
        loadedAtlasName = f;

        set(ddAtlas,'Value',3);

        updateFileLabels();
        updateSummary();

    catch ME
        errordlg(ME.message,'FC atlas load error');
    end
end

function onLoadNames(~,~)
    startDir = fcGetRegistrationStartDir(studio);

    [f,p] = fc_uigetfile_start( ...
        {'*.txt;*.csv;*.tsv;*.mat', ...
        'Region names (*.txt,*.csv,*.tsv,*.mat)'}, ...
        'Load FC region names', startDir);

    if isequal(f,0)
        return;
    end

        try
            loadedNames = fcStudioReadRegionNames(fullfile(p,f));
            if isempty(loadedNames.labels)
                errordlg('Could not parse labels/names from selected file.','FC names');
                return;
            end
            loadedNamesName = f;
            set(ddNames,'Value',2);
            updateFileLabels();
            updateSummary();
        catch ME
            errordlg(ME.message,'FC region names load error');
        end
    end

    function onRun(~,~)

        seedBox = str2double(get(edSeedBox,'String'));
        roiMinVox = str2double(get(edMinVox,'String'));
        chunkVox = str2double(get(edChunk,'String'));

        if ~isfinite(seedBox) || seedBox < 1
            uiwait(errordlg('Seed box size must be >= 1.','FC setup','modal'));
            return;
        end

        if ~isfinite(roiMinVox) || roiMinVox < 1
            uiwait(errordlg('ROI min vox must be >= 1.','FC setup','modal'));
            return;
        end

        if ~isfinite(chunkVox) || chunkVox < 100
            uiwait(errordlg('Chunk voxels should be at least 100.','FC setup','modal'));
            return;
        end

        % Functional source
        funcStrings = get(ddFunc,'String');
        funcChoice = funcStrings{get(ddFunc,'Value')};

        if ~isempty(strfind(lower(funcChoice),'psc')) %#ok<STREMP>
            if ~hasPSC
                uiwait(errordlg('PSC was selected but data.PSC is missing.','FC setup','modal'));
                return;
            end
            cfg.functionalSource = 'psc';
        else
            cfg.functionalSource = 'i';
        end

        % Mask
        cfg.mask = [];
        switch get(ddMask,'Value')
            case 1
                cfg.maskMode = 'auto';

            case 2
                if ~hasStudioMask
                    uiwait(errordlg('Studio mask selected but no studio.mask exists.','FC setup','modal'));
                    return;
                end
                cfg.maskMode = 'studio';
                cfg.mask = fcStudioFitVolume(studio.mask,Y,X,Z,true);

            case 3
                if isempty(loadedMask)
                    uiwait(errordlg('Loaded mask selected but no mask file was loaded.','FC setup','modal'));
                    return;
                end
                cfg.maskMode = 'loaded';
                cfg.mask = fcStudioFitVolume(loadedMask,Y,X,Z,true);

            otherwise
                cfg.maskMode = 'none';
        end

       % -----------------------------------------------------
% Underlay / anatomy
% -----------------------------------------------------
cfg.anat = [];
cfg.anatIsDisplayReady = false;


cfg.defaultUnderlayMode = 'scm_log_median';

% SCM / VideoGUI recommended display settings.
% These are only used for raw/linear underlays.
% If anatIsDisplayReady=true, FunctionalConnectivity.m should show it as-is.
cfg.defaultUnderlayViewMode = 3;
cfg.underlayBrightness = -0.04;
cfg.underlayContrast   = 1.10;
cfg.underlayGamma      = 0.95;

switch get(ddUnderlay,'Value')

        case 1
        % SCM log/median recommended underlay.
        % Priority:
        %   1) Mask Editor display-ready anatomical underlay
        %   2) Mask Editor raw anatomical underlay
        %   3) let FunctionalConnectivity recompute SCM log/median from data.I

        cfg.defaultUnderlayMode = 'scm_log_median';

        if hasStudioAnat && isfield(studio,'anatomicalReference') && ~isempty(studio.anatomicalReference)

            cfg.anat = fcStudioFitVolume(studio.anatomicalReference,Y,X,Z,false);

            if isfield(studio,'anatomicalReferenceIsDisplayReady') && ...
                    studio.anatomicalReferenceIsDisplayReady
                cfg.anatIsDisplayReady = true;
                cfg.defaultUnderlayMode = 'anat';
            else
                cfg.anatIsDisplayReady = false;
                cfg.defaultUnderlayMode = 'anat';
            end

        elseif hasStudioAnat && isfield(studio,'anatomicalReferenceRaw') && ~isempty(studio.anatomicalReferenceRaw)

            cfg.anat = fcStudioFitVolume(studio.anatomicalReferenceRaw,Y,X,Z,false);
            cfg.anatIsDisplayReady = false;
            cfg.defaultUnderlayMode = 'anat';

        else
            % No preloaded anatomical underlay.
            % FunctionalConnectivity.m will compute the SCM-style log/median underlay.
            cfg.anat = [];
            cfg.anatIsDisplayReady = false;
            cfg.defaultUnderlayMode = 'scm_log_median';
        end

    case 2
        cfg.defaultUnderlayMode = 'mean';

    case 3
        cfg.defaultUnderlayMode = 'median';

    case 4
        if hasDataBg
            cfg.anat = fcStudioFitVolume(data.bg,Y,X,Z,false);
            cfg.anatIsDisplayReady = false;
            cfg.defaultUnderlayMode = 'anat';
        else
            cfg.defaultUnderlayMode = 'mean';
        end

    case 5
        if hasStudioAnat && isfield(studio,'anatomicalReference') && ~isempty(studio.anatomicalReference)

            cfg.anat = fcStudioFitVolume(studio.anatomicalReference,Y,X,Z,false);
            cfg.anatIsDisplayReady = true;
            cfg.defaultUnderlayMode = 'anat';

        elseif hasStudioAnat && isfield(studio,'anatomicalReferenceRaw') && ~isempty(studio.anatomicalReferenceRaw)

            cfg.anat = fcStudioFitVolume(studio.anatomicalReferenceRaw,Y,X,Z,false);
            cfg.anatIsDisplayReady = false;
            cfg.defaultUnderlayMode = 'anat';

        else
            cfg.defaultUnderlayMode = 'mean';
        end

    case 6
        if isempty(loadedAnat)
            uiwait(errordlg('Loaded underlay selected but no underlay was loaded.','FC setup','modal'));
            return;
        end

        cfg.anat = fcStudioFitVolume(loadedAnat,Y,X,Z,false);
        cfg.anatIsDisplayReady = logical(loadedAnatDisplayReady);
        cfg.defaultUnderlayMode = 'anat';
end

        % ROI atlas
        cfg.roiAtlas = [];

        switch get(ddAtlas,'Value')
            case 1
                cfg.roiAtlas = [];

            case 2
                cfg.roiAtlas = fcGetAtlasFromData(data,Y,X,Z);

            case 3
                if isempty(loadedAtlas)
                    uiwait(errordlg('Loaded atlas selected but no atlas was loaded.','FC setup','modal'));
                    return;
                end
                cfg.roiAtlas = fcStudioFitVolume(loadedAtlas,Y,X,Z,false);
        end

        % Region names
        if get(ddNames,'Value') == 2
            cfg.roiNameTable = loadedNames;
        else
            cfg.roiNameTable = struct('labels',[],'names',{{}});
        end

        cfg.seedBoxSize = max(1,round(seedBox));
        cfg.roiMinVox = max(1,round(roiMinVox));
        cfg.chunkVox = max(100,round(chunkVox));

        cfg.cancelled = false;

        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(~,~)
        cfg.cancelled = true;
        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel();
            elseif strcmpi(ev.Key,'return')
                onRun();
            end
        catch
        end
    end

    function s = shortTxt(s,n)
        if nargin < 2
            n = 20;
        end
        s = char(s);
        if numel(s) > n
            s = [s(1:max(1,n-3)) '...'];
        end
    end
    function fcScaleFcSetupFonts(hFig)

    try
        allObj = findall(hFig);

        for ii = 1:numel(allObj)
            h = allObj(ii);

            if ~ishandle(h)
                continue;
            end

            if isprop(h,'FontName')
                try
                    set(h,'FontName','Arial');
                catch
                end
            end

            if ~isprop(h,'FontSize')
                continue;
            end

            try
                typ = get(h,'Type');
            catch
                typ = '';
            end

            if strcmpi(typ,'uicontrol')
                try
                    style = lower(get(h,'Style'));
                catch
                    style = '';
                end

                switch style
                    case 'text'
                        oldSize = get(h,'FontSize');
                        if oldSize >= 18
                            set(h,'FontSize',24,'FontWeight','bold');
                        elseif oldSize >= 12
                            set(h,'FontSize',14);
                        else
                            set(h,'FontSize',12);
                        end

                    case {'popupmenu','edit'}
                        set(h,'FontSize',13,'FontWeight','bold');

                    case 'pushbutton'
                        set(h,'FontSize',13,'FontWeight','bold');

                    case 'checkbox'
                        set(h,'FontSize',12,'FontWeight','bold');

                    otherwise
                        set(h,'FontSize',12);
                end

            elseif strcmpi(typ,'uipanel')
                set(h,'FontSize',13,'FontWeight','bold');

            elseif strcmpi(typ,'axes')
                set(h,'FontSize',11);
            end
        end
    catch
    end
end
end

%% =========================================================
%  FUNCTIONAL CONNECTIVITY SETUP HELPERS
% =========================================================
    function tf = fcDataHasAtlas(data,Y,X,Z)

tf = false;

try
    A = fcStudioPickAtlasVolume(data,Y,X,Z);
    tf = ~isempty(A);
catch
    tf = false;
end
    end

    function atlas = fcGetAtlasFromData(data,Y,X,Z)

atlas = [];

try
    atlas = fcStudioPickAtlasVolume(data,Y,X,Z);
    if ~isempty(atlas)
        atlas = round(double(atlas));
    end
catch
    atlas = [];
end
end
    function startDir = fcSetupStartDir(studio)
% Backward-compatible default start folder.
% For FC, prefer Registration because atlas, histology, region names,
% and transformed files usually live there.

    startDir = fcGetRegistrationStartDir(studio);
end


   function startDir = fcGetRegistrationStartDir(studio)
% FC atlas / labels / names picker start folder.
% Priority:
%   1) <exportPath>\Registration2D
%   2) studio.registration2DPath
%   3) <exportPath>\Registration
%   4) <exportPath>\Coregistration
%   5) <exportPath>
%   6) loaded raw path
%   7) pwd

    startDir = pwd;

    % -----------------------------------------------------
    % 1) Preferred: analysed dataset Registration2D folder
    % -----------------------------------------------------
    try
        if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')

            reg2DDir = fullfile(studio.exportPath,'Registration2D');

            % Create if missing, so uigetfile can start there.
            if ~exist(reg2DDir,'dir')
                try
                    mkdir(reg2DDir);
                catch
                end
            end

            if exist(reg2DDir,'dir')
                startDir = reg2DDir;
                return;
            end
        end
    catch
    end

    % -----------------------------------------------------
    % 2) Explicit studio.registration2DPath, if you store it
    % -----------------------------------------------------
    try
        if isfield(studio,'registration2DPath') && ~isempty(studio.registration2DPath) && ...
                exist(studio.registration2DPath,'dir')
            startDir = studio.registration2DPath;
            return;
        end
    catch
    end

    % -----------------------------------------------------
    % 3) Older fallback: studio.registrationPath
    % -----------------------------------------------------
    try
        if isfield(studio,'registrationPath') && ~isempty(studio.registrationPath) && ...
                exist(studio.registrationPath,'dir')
            startDir = studio.registrationPath;
            return;
        end
    catch
    end

    % -----------------------------------------------------
    % 4) Other analysed folders
    % -----------------------------------------------------
    try
        if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')

            regDir = fullfile(studio.exportPath,'Registration');
            if exist(regDir,'dir')
                startDir = regDir;
                return;
            end

            coregDir = fullfile(studio.exportPath,'Coregistration');
            if exist(coregDir,'dir')
                startDir = coregDir;
                return;
            end

            startDir = studio.exportPath;
            return;
        end
    catch
    end

    % -----------------------------------------------------
    % 5) Raw loaded path fallback
    % -----------------------------------------------------
    try
        if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
            startDir = studio.loadedPath;
        end
    catch
    end
end

function [f,p] = fc_uigetfile_start(filterSpec, titleStr, startDir)
% Robust uigetfile opener.
% MATLAB sometimes remembers the last folder. Temporarily cd() into startDir
% so the file picker really starts in Registration.

if nargin < 3 || isempty(startDir) || ~exist(startDir,'dir')
    startDir = pwd;
end

oldDir = pwd;
cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>

try
    cd(startDir);
catch
end

[f,p] = uigetfile(filterSpec, titleStr);

end

function V = fcStudioPickVolume(S,Y,X,Z,makeLogical)

    V = [];

    preferred = { ...
        'roiAtlas', ...
        'atlas', ...
        'regions', ...
        'annotation', ...
        'labels', ...
        'mask', ...
        'brainMask', ...
        'loadedMask', ...
        'underlay', ...
        'anat', ...
        'bg', ...
        'Data', ...
        'I'};

    for i = 1:numel(preferred)
        fn = preferred{i};
        if isfield(S,fn)
            V = fcStudioVolumeFromAny(S.(fn),Y,X,Z,makeLogical);
            if ~isempty(V)
                return;
            end
        end
    end

    fns = fieldnames(S);
    for i = 1:numel(fns)
        V = fcStudioVolumeFromAny(S.(fns{i}),Y,X,Z,makeLogical);
        if ~isempty(V)
            return;
        end
    end
end

function V = fcStudioVolumeFromAny(x,Y,X,Z,makeLogical)

    V = [];

    try
        if isstruct(x)
            if isfield(x,'Data') && isnumeric(x.Data)
                x = x.Data;
            elseif isfield(x,'I') && isnumeric(x.I)
                x = x.I;
            else
                return;
            end
        end

        if ~(isnumeric(x) || islogical(x))
            return;
        end

        V0 = squeeze(x);

        if ndims(V0) == 2
            if Z == 1 && size(V0,1) == Y && size(V0,2) == X
                V = reshape(V0,Y,X,1);
            elseif size(V0,1) == Y && size(V0,2) == X
                V = repmat(V0,[1 1 Z]);
            end

        elseif ndims(V0) == 3
            if all(size(V0) == [Y X Z])
                V = V0;
            elseif size(V0,1) == Y && size(V0,2) == X && size(V0,3) ~= Z
                zi = round(linspace(1,size(V0,3),Z));
                V = V0(:,:,zi);
            end

        elseif ndims(V0) == 4
            % If a functional 4D volume was accidentally selected as underlay,
            % reduce across time.
            if size(V0,1) == Y && size(V0,2) == X
                V0 = mean(V0,4);
                V = fcStudioVolumeFromAny(V0,Y,X,Z,makeLogical);
            end
        end

        if ~isempty(V) && makeLogical
            V = logical(V);
        end

    catch
        V = [];
    end
end

function V = fcStudioFitVolume(V0,Y,X,Z,makeLogical)

    V = fcStudioVolumeFromAny(V0,Y,X,Z,makeLogical);

    if isempty(V)
        error('Volume cannot be fitted to functional dimensions [%d x %d x %d].',Y,X,Z);
    end
end

function atlas = fcStudioReadAtlas(fullFile,Y,X,Z)

atlas = [];

if ~exist(fullFile,'file')
    error('Atlas file does not exist: %s',fullFile);
end

if numel(fullFile) >= 7 && strcmpi(fullFile(end-6:end),'.nii.gz')
    tmpDir = tempname;
    mkdir(tmpDir);

    try
        gunzip(fullFile,tmpDir);
        d = dir(fullfile(tmpDir,'*.nii'));
        if isempty(d)
            error('Could not unzip NIfTI atlas.');
        end

        A = double(niftiread(fullfile(tmpDir,d(1).name)));
        atlas = fcStudioAtlasVolumeFromAny(A,Y,X,Z);

        try
            rmdir(tmpDir,'s');
        catch
        end

    catch ME
        try
            rmdir(tmpDir,'s');
        catch
        end
        rethrow(ME);
    end

elseif strcmpi(lower(fileparts_ext(fullFile)),'.nii')
    A = double(niftiread(fullFile));
    atlas = fcStudioAtlasVolumeFromAny(A,Y,X,Z);

else
    [~,~,ext] = fileparts(fullFile);
    ext = lower(ext);

    if strcmpi(ext,'.mat')
        S = load(fullFile);
        atlas = fcStudioPickAtlasVolume(S,Y,X,Z);
    else
        A = double(imread(fullFile));
        atlas = fcStudioAtlasVolumeFromAny(A,Y,X,Z);
    end
end

if isempty(atlas)
    error(['No ROI label atlas found. Load histology as underlay. ' ...
           'For ROI FC, choose a regions/labels/annotation file with integer region IDs.']);
end

atlas = round(double(atlas));
end


function ext = fileparts_ext(f)
[~,~,ext] = fileparts(f);
end


function atlas = fcStudioPickAtlasVolume(S,Y,X,Z)

atlas = [];
candidates = struct('name',{},'score',{},'value',{});

candidates = fcStudioCollectAtlasCandidates(S,'root',0,candidates,Y,X,Z);

if isempty(candidates)
    return;
end

scores = zeros(numel(candidates),1);
for ii = 1:numel(candidates)
    scores(ii) = candidates(ii).score;
end

[~,idx] = max(scores);
atlas = candidates(idx).value;
end


function candidates = fcStudioCollectAtlasCandidates(v,pathStr,depth,candidates,Y,X,Z)

if depth > 5
    return;
end

% Numeric candidate.
if isnumeric(v) || islogical(v)
    [A,ok] = fcStudioAtlasVolumeFromAny(v,Y,X,Z);

    if ok && ~isempty(A)
        score = fcStudioScoreAtlasCandidate(A,pathStr);

        if isfinite(score)
            c = struct();
            c.name = pathStr;
            c.score = score;
            c.value = A;
            candidates(end+1) = c; %#ok<AGROW>
        end
    end

    return;
end

% Cell wrapper.
if iscell(v) && numel(v) == 1
    candidates = fcStudioCollectAtlasCandidates(v{1},[pathStr '{1}'],depth+1,candidates,Y,X,Z);
    return;
end

% Struct recursion.
if isstruct(v)
    if numel(v) > 1
        % Region-name structs are not image volumes.
        return;
    end

    fns = fieldnames(v);

    for ii = 1:numel(fns)
        fn = fns{ii};

        if isempty(pathStr)
            p2 = fn;
        else
            p2 = [pathStr '.' fn];
        end

        candidates = fcStudioCollectAtlasCandidates(v.(fn),p2,depth+1,candidates,Y,X,Z);
    end
end
end


function [A,ok] = fcStudioAtlasVolumeFromAny(v,Y,X,Z)

A = [];
ok = false;

try
    v = squeeze(v);

    if isempty(v) || isvector(v)
        return;
    end

    % RGB / colored region underlay is not a label atlas.
    if ndims(v) == 3 && size(v,3) == 3 && Z == 1
        return;
    end

    % 2D label image.
    if ndims(v) == 2

        v2 = double(v);

        % Exact.
        if size(v2,1) == Y && size(v2,2) == X
            A2 = v2;

        % Transposed exact.
        elseif size(v2,1) == X && size(v2,2) == Y
            A2 = v2';

        % Co-registered export with slightly different pixel size.
        else
            A2 = fcStudioResizeLabel2D(v2,Y,X);
        end

        if ~fcStudioLooksLikeRoiLabelMap(A2)
            return;
        end

        if Z == 1
            A = reshape(round(A2),Y,X,1);
        else
            A = repmat(round(A2),[1 1 Z]);
        end

        ok = true;
        return;
    end

    % 3D label volume.
    if ndims(v) == 3

        v3 = double(v);

        % Avoid accidentally resizing the full Allen atlas or huge raw atlases.
        if numel(v3) > 2e7 && ~(size(v3,1)==Y && size(v3,2)==X)
            return;
        end

        if size(v3,1) == Y && size(v3,2) == X
            A3 = v3;

        elseif size(v3,1) == X && size(v3,2) == Y
            A3 = permute(v3,[2 1 3]);

        else
            A3 = zeros(Y,X,size(v3,3));

            for zz = 1:size(v3,3)
                A3(:,:,zz) = fcStudioResizeLabel2D(v3(:,:,zz),Y,X);
            end
        end

        if size(A3,3) ~= Z
            zi = round(linspace(1,size(A3,3),Z));
            zi = max(1,min(size(A3,3),zi));
            A3 = A3(:,:,zi);
        end

        if ~fcStudioLooksLikeRoiLabelMap(A3)
            return;
        end

        A = round(A3);
        ok = true;
        return;
    end

catch
    A = [];
    ok = false;
end
end


function A = fcStudioResizeLabel2D(A,Y,X)

A = double(A);

if size(A,1) == Y && size(A,2) == X
    return;
end

if exist('imresize','file') == 2
    A = imresize(A,[Y X],'nearest');
else
    yy = round(linspace(1,size(A,1),Y));
    xx = round(linspace(1,size(A,2),X));
    A = A(yy,xx);
end

A = round(A);
end


function tf = fcStudioLooksLikeRoiLabelMap(A)

tf = false;

try
    A = double(A);
    A = A(isfinite(A));

    if isempty(A)
        return;
    end

    % Subsample for speed.
    if numel(A) > 200000
        idx = round(linspace(1,numel(A),200000));
        A = A(idx);
    end

    % Must be mostly integer-valued.
    fracInt = mean(abs(A - round(A)) < 1e-6);

    if fracInt < 0.98
        return;
    end

    U = unique(round(A(:)));
    U = U(isfinite(U));
    U = U(U ~= 0);

    % Binary mask is not an atlas.
    if numel(U) < 2
        return;
    end

    % Too many labels usually means colored/intensity image, not atlas IDs.
    if numel(U) > 5000
        return;
    end

    tf = true;

catch
    tf = false;
end
end


function score = fcStudioScoreAtlasCandidate(A,nameStr)

score = -Inf;

if isempty(A)
    return;
end

if ~fcStudioLooksLikeRoiLabelMap(A)
    return;
end

score = 100;

lname = lower(nameStr);

goodKeys = { ...
    'roiatlas','roi_atlas','region','regions','label','labels', ...
    'annotation','atlas','registered','warped','area'};

badKeys = { ...
    'histology','histo','anat','anatomical','underlay','display', ...
    'raw','brainimage','mask','overlay','signal','rgb','image','img'};

for ii = 1:numel(goodKeys)
    if ~isempty(strfind(lname,goodKeys{ii})) %#ok<STREMP>
        score = score + 20;
    end
end

for ii = 1:numel(badKeys)
    if ~isempty(strfind(lname,badKeys{ii})) %#ok<STREMP>
        score = score - 25;
    end
end

try
    U = unique(round(double(A(:))));
    U = U(U ~= 0);
    score = score + min(50,numel(U));
catch
end
end

    function [U,isDisplayReady] = fcStudioReadUnderlay(fullFile,Y,X,Z)

U = [];
isDisplayReady = false;

if ~exist(fullFile,'file')
    error('File does not exist: %s',fullFile);
end

[~,~,ext] = fileparts(fullFile);
ext = lower(ext);

if strcmpi(ext,'.mat')
    S = load(fullFile);

    [U,isDisplayReady] = fcStudioPickUnderlay(S,Y,X,Z);

    if isempty(U)
        error('No compatible underlay variable found in MAT file.');
    end

    U = double(U);
    return;
end

A = imread(fullFile);

if ndims(A) == 3 && size(A,3) == 3
    A = double(A);
    U2 = 0.2989*A(:,:,1) + 0.5870*A(:,:,2) + 0.1140*A(:,:,3);
else
    U2 = double(A);
end

if size(U2,1) ~= Y || size(U2,2) ~= X
    U2 = fcStudioResize2D(U2,Y,X);
end

if Z == 1
    U = reshape(U2,Y,X,1);
else
    U = repmat(U2,[1 1 Z]);
end

isDisplayReady = true;
    end

function [U,isDisplayReady] = fcStudioPickUnderlay(S,Y,X,Z)

U = [];
isDisplayReady = false;

% Prefer Mask Editor bundle first.
if isfield(S,'maskBundle') && isstruct(S.maskBundle)
    [U,isDisplayReady] = fcStudioPickUnderlayFromStruct(S.maskBundle,Y,X,Z);
    if ~isempty(U)
        return;
    end
end

[U,isDisplayReady] = fcStudioPickUnderlayFromStruct(S,Y,X,Z);
end


function [U,isDisplayReady] = fcStudioPickUnderlayFromStruct(S,Y,X,Z)

U = [];
isDisplayReady = false;

% These are already tuned/display-ready.
displayFields = { ...
    'savedUnderlayDisplay', ...
    'savedUnderlayForReload', ...
    'anatomical_reference', ...
    'anatomicalReference', ...
    'brainImage'};

for ii = 1:numel(displayFields)
    fn = displayFields{ii};
    if ~isfield(S,fn)
        continue;
    end

    Ucand = fcStudioUnderlayCandidate(S.(fn),Y,X,Z);

    if isempty(Ucand)
        continue;
    end

    if fcStudioLooksLikeAtlasOrMask(Ucand)
        continue;
    end

    U = Ucand;
    isDisplayReady = true;
    return;
end

% These are raw/base images and should be normalized inside FC.
rawFields = { ...
    'anatomical_reference_raw', ...
    'anatomicalReferenceRaw', ...
    'underlay', ...
    'bg', ...
    'DP', ...
    'dp', ...
    'histology', ...
    'Histology', ...
    'image', ...
    'img', ...
    'I', ...
    'Data'};

for ii = 1:numel(rawFields)
    fn = rawFields{ii};
    if ~isfield(S,fn)
        continue;
    end

    Ucand = fcStudioUnderlayCandidate(S.(fn),Y,X,Z);

    if isempty(Ucand)
        continue;
    end

    if fcStudioLooksLikeAtlasOrMask(Ucand)
        continue;
    end

    U = Ucand;
    isDisplayReady = false;
    return;
end

% Fallback: any numeric non-mask, non-atlas field.
skip = { ...
    'mask','loadedMask','activeMask','brainMask','underlayMask', ...
    'overlayMask','signalMask','roiAtlas','atlas','regions', ...
    'annotation','labels','labelVolume', ...
    'maskIsInclude','loadedMaskIsInclude','overlayMaskIsInclude'};

fns = fieldnames(S);

for ii = 1:numel(fns)
    fn = fns{ii};

    if any(strcmpi(fn,skip))
        continue;
    end

    Ucand = fcStudioUnderlayCandidate(S.(fn),Y,X,Z);

    if isempty(Ucand)
        continue;
    end

    if fcStudioLooksLikeAtlasOrMask(Ucand)
        continue;
    end

    U = Ucand;
    isDisplayReady = false;
    return;
end
end


function U = fcStudioUnderlayCandidate(v,Y,X,Z)

U = [];

try
    if isstruct(v)
        if isfield(v,'Data') && isnumeric(v.Data)
            v = v.Data;
        elseif isfield(v,'I') && isnumeric(v.I)
            v = v.I;
        else
            return;
        end
    end

    if ~(isnumeric(v) || islogical(v))
        return;
    end

    v = squeeze(v);

    if ndims(v) == 2
        if size(v,1) ~= Y || size(v,2) ~= X
            v = fcStudioResize2D(double(v),Y,X);
        end

        if Z == 1
            U = reshape(double(v),Y,X,1);
        else
            U = repmat(double(v),[1 1 Z]);
        end
        return;
    end

    % RGB only if Z==1.
    if ndims(v) == 3 && size(v,3) == 3 && Z == 1
        if size(v,1) ~= Y || size(v,2) ~= X
            tmp = zeros(Y,X,3);
            for cc = 1:3
                tmp(:,:,cc) = fcStudioResize2D(double(v(:,:,cc)),Y,X);
            end
            U = tmp;
        else
            U = double(v);
        end
        return;
    end

    if ndims(v) == 3
        if size(v,1) ~= Y || size(v,2) ~= X
            tmp = zeros(Y,X,size(v,3));
            for zz = 1:size(v,3)
                tmp(:,:,zz) = fcStudioResize2D(double(v(:,:,zz)),Y,X);
            end
            v = tmp;
        end

        if size(v,3) ~= Z
            zi = round(linspace(1,size(v,3),Z));
            zi = max(1,min(size(v,3),zi));
            v = v(:,:,zi);
        end

        U = double(v);
    end

catch
    U = [];
end
end


    function tf = fcStudioLooksLikeAtlasOrMask(A)

tf = false;

try
    A = double(A);
    A = A(isfinite(A));

    if isempty(A)
        tf = true;
        return;
    end

    if numel(A) > 200000
        idx = round(linspace(1,numel(A),200000));
        A = A(idx);
    end

    u = unique(A(:));

    % Binary masks only
    if numel(u) <= 2 && all(ismember(u,[0 1]))
        tf = true;
        return;
    end

    % Only reject very low-count integer label maps.
    % Do NOT reject 8-bit grayscale anatomy/histology with many intensity levels.
    fracInt = mean(abs(A - round(A)) < 1e-6);
    U = unique(round(A(:)));
    U = U(U ~= 0);

    if fracInt > 0.98 && numel(U) >= 2 && numel(U) < 50
        tf = true;
        return;
    end

catch
    tf = false;
end
end

function B = fcStudioResize2D(A,Y,X)

    if exist('imresize','file') == 2
        B = imresize(A,[Y X],'nearest');
    else
        yy = round(linspace(1,size(A,1),Y));
        xx = round(linspace(1,size(A,2),X));
        B = A(yy,xx);
    end
end

function T = fcStudioReadRegionNames(fullFile)

    T = struct('labels',[],'names',{{}});

    if ~exist(fullFile,'file')
        error('Region-name file does not exist.');
    end

    [~,~,ext] = fileparts(fullFile);
    ext = lower(ext);

    if strcmpi(ext,'.mat')
        S = load(fullFile);

        if isfield(S,'roiNameTable')
            x = S.roiNameTable;
            if isstruct(x) && isfield(x,'labels') && isfield(x,'names')
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

        fns = fieldnames(S);
        for i = 1:numel(fns)
            x = S.(fns{i});

            if isstruct(x) && numel(x) > 1
                f = fieldnames(x);
                idField = '';
                nameField = '';

                if any(strcmpi(f,'id')), idField = 'id'; end
                if any(strcmpi(f,'label')), idField = 'label'; end
                if any(strcmpi(f,'acronym')), nameField = 'acronym'; end
                if any(strcmpi(f,'name')), nameField = 'name'; end

                if ~isempty(idField) && ~isempty(nameField)
                    labs = zeros(numel(x),1);
                    nms = cell(numel(x),1);

                    for k = 1:numel(x)
                        labs(k) = double(x(k).(idField));
                        nms{k} = char(x(k).(nameField));
                    end

                    T.labels = labs;
                    T.names = nms;
                    return;
                end
            end
        end

        error('Could not parse region names from MAT file.');
    end

    fid = fopen(fullFile,'r');
    if fid < 0
        error('Could not open region-name file.');
    end

    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

    labels = [];
    names = {};

    while ~feof(fid)
        line = fgetl(fid);

        if ~ischar(line)
            continue;
        end

        line = strtrim(line);

        if isempty(line)
            continue;
        end

        if line(1) == '#' || line(1) == '%'
            continue;
        end

        line = strrep(line,char(9),',');
        line = strrep(line,';',',');

        parts = regexp(line,',','split');

        if numel(parts) < 2
            parts = regexp(line,'\s+','split');
        end

        if numel(parts) < 2
            continue;
        end

        lab = str2double(strtrim(parts{1}));

        if ~isfinite(lab)
            continue;
        end

        nm = strtrim(parts{2});

        if numel(parts) > 2
            for k = 3:numel(parts)
                pk = strtrim(parts{k});
                if ~isempty(pk)
                    nm = [nm ' ' pk]; %#ok<AGROW>
                end
            end
        end

        labels(end+1,1) = lab; %#ok<AGROW>
        names{end+1,1} = nm; %#ok<AGROW>
    end

    T.labels = labels;
    T.names = names;
end
%% =========================================================
%  LIVE VIEWER CALLBACK
% =========================================================
function liveViewerCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    if isfield(data,'PSC') && ~isempty(data.PSC)
        I = data.PSC;
    else
        I = data.I;
    end

    try
        s = whos('I');
        approxGB = s.bytes / 1e9;
        if approxGB > 5
            warndlg(sprintf(['Dataset is %.2f GB in memory.\n' ...
                'LiveViewer may crash on low RAM systems.'], approxGB));
        end
    catch
    end

    addLog(['Opening Live Viewer (Dataset: ' studio.activeDataset ')']);
    setProgramStatus(false);
    drawnow;

    try
        metaForViewer = studio.meta;

        if isempty(metaForViewer) || ~isstruct(metaForViewer)
            metaForViewer = struct();
        end

        % -----------------------------------------------------
        % Pass analysed/save paths explicitly to Live Viewer
        % -----------------------------------------------------
        metaForViewer.exportPath = studio.exportPath;
        metaForViewer.savePath   = studio.exportPath;
        metaForViewer.outPath    = studio.exportPath;
metaForViewer.analysedPath = studio.exportPath;
metaForViewer.datasetName  = getDatasetDisplayName(studio, studio.activeDataset);
metaForViewer.activeDataset = studio.activeDataset;
        % -----------------------------------------------------
        % Also pass raw/load info as fallback
        % -----------------------------------------------------
        metaForViewer.loadedPath = studio.loadedPath;

        if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
            if ~isempty(studio.loadedPath)
                metaForViewer.loadedFile = fullfile(studio.loadedPath, studio.loadedFile);
            else
                metaForViewer.loadedFile = studio.loadedFile;
            end
        end

        % -----------------------------------------------------
        % Helpful labels
        % -----------------------------------------------------
        metaForViewer.activeDataset = studio.activeDataset;
        metaForViewer.datasetDisplayName = getDatasetDisplayName(studio, studio.activeDataset);

        viewerFig = fUSI_Live_Studio( ...
            I, ...
            data.TR, ...
            metaForViewer, ...
            getDatasetDisplayName(studio, studio.activeDataset));

        addlistener(viewerFig,'ObjectBeingDestroyed', @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Live Viewer ERROR: ' ME.message]);
        errordlg(ME.message,'Live Viewer Failed');
        setProgramStatus(true);
    end

    clear I
    drawnow
end

%% =========================================================
%  SCM GUI CALLBACK
% =========================================================
function scmCallback(~,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','SCM');
        return;
    end

    data = getActiveData();

    % -----------------------------------------------------
    % Launch setup popup: baseline + underlay selection
    % -----------------------------------------------------
    launchCfg = showScmVideoSetupDialog('SCM GUI', 30, 240, 5, studio, data.I);
    if isempty(launchCfg) || ~isstruct(launchCfg) || ...
            ~isfield(launchCfg,'cancelled') || launchCfg.cancelled
        addLog('SCM cancelled.');
        return;
    end

   baseline = struct( ...
    'start',    launchCfg.baselineStart, ...
    'end',      launchCfg.baselineEnd, ...
    'sigStart', 840, ...
    'sigEnd',   900, ...
    'mode',     'sec');

    % -----------------------------------------------------
    % Prepare par
    % -----------------------------------------------------
    par = struct();
    par.interpol = 1;
    par.previewCaxis = [];
    par.exportPath = studio.exportPath;
    par.datasetTag = studio.activeDataset;

    if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
        par.loadedPath = studio.loadedPath;
        par.rawPath = studio.loadedPath;
    else
        par.loadedPath = '';
        par.rawPath = '';
    end

    par.loadedFile = '';
    try
        if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
            lf = studio.loadedFile;
            fullLf = lf;
            if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
                cand = fullfile(studio.loadedPath, lf);
                if exist(cand,'file')
                    fullLf = cand;
                end
            end
            par.loadedFile = fullLf;
        end
    catch
        par.loadedFile = '';
    end

    % -----------------------------------------------------
    % Get PSC + default background
    % -----------------------------------------------------
    if isfield(data,'PSC') && ~isempty(data.PSC) && ...
       isfield(data,'bg')  && ~isempty(data.bg)
        PSCsig = data.PSC;
        bgDefault = data.bg;
    else
        try
            proc = computePSC(data.I, data.TR, par, baseline);
            PSCsig = proc.PSC;
            bgDefault = proc.bg;
        catch
            proc = computePSC(double(data.I), data.TR, par, baseline);
            PSCsig = proc.PSC;
            bgDefault = proc.bg;
        end
    end

    % -----------------------------------------------------
    % Resolve underlay from popup choice
    % -----------------------------------------------------
if isfield(launchCfg,'precomputedUnderlayDisplay') && ~isempty(launchCfg.precomputedUnderlayDisplay)
    bgUnderlay = launchCfg.precomputedUnderlayDisplay;
    underlayLabel = launchCfg.underlayLabel;
else
    [bgUnderlay, underlayLabel] = resolveScmVideoUnderlayChoice( ...
        studio, data, bgDefault, launchCfg.underlayChoice);
end

if isempty(bgUnderlay)
    addLog('SCM cancelled (no underlay selected).');
    return;
end

    % -----------------------------------------------------
    % Pass stored mask if available
    % -----------------------------------------------------
    loadedMask = [];
    loadedMaskIsInclude = true;

    if isfield(studio,'mask') && ~isempty(studio.mask)
        loadedMask = studio.mask;
        if isfield(studio,'maskIsInclude') && ~isempty(studio.maskIsInclude)
            loadedMaskIsInclude = logical(studio.maskIsInclude);
        end
    end

    % -----------------------------------------------------
    % Launch SCM GUI
    % -----------------------------------------------------
    addLog(['Opening SCM GUI (Dataset: ' studio.activeDataset ')']);
    addLog(sprintf('SCM baseline: %.3g-%.3g s', baseline.start, baseline.end));
    addLog(['SCM underlay: ' underlayLabel]);

    setProgramStatus(false);
    drawnow;

    try
        fileLabel = [studio.activeDataset ' | ' underlayLabel];

        scmFig = SCM_gui( ...
            PSCsig, bgUnderlay, data.TR, par, baseline, data.nVols, ...
            data.I, data.I, ...
            10, 240, ...
            loadedMask, loadedMaskIsInclude, struct(), ...
            fileLabel);

        addlistener(scmFig,'ObjectBeingDestroyed', @(~,~) setProgramStatus(true));

    catch ME
        addLog(['SCM ERROR: ' ME.message]);
        errordlg(ME.message,'SCM Failed');
        setProgramStatus(true);
    end
end
%% =========================================================
%  VIDEO GUI CALLBACK
% =========================================================
function videoGUICallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog(['Opening Video GUI (Dataset: ' studio.activeDataset ')']);

launchCfg = showScmVideoSetupDialog('Video GUI', 30, 240, 5, studio, data.I);
if launchCfg.cancelled
    addLog('Video GUI cancelled.');
    return;
end

baseline = struct( ...
    'start', launchCfg.baselineStart, ...
    'end',   launchCfg.baselineEnd, ...
    'mode',  'sec');

    par = struct();
    par.interpol = 1;
    par.LPF = 0;
    par.HPF = 0;
    par.gaussSize = 0;
    par.gaussSig = 0;
    par.previewCaxis = [];
    par.caxis = [];
    par.exportPath = studio.exportPath;
    par.datasetTag = studio.activeDataset;
    par.activeDataset = studio.activeDataset;

    if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
        par.loadedPath = studio.loadedPath;
        par.rawPath = studio.loadedPath;
    else
        par.loadedPath = '';
        par.rawPath = '';
    end

    par.loadedFile = '';
    try
        if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
            lf = studio.loadedFile;
            fullLf = lf;
            if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
                cand = fullfile(studio.loadedPath, lf);
                if exist(cand,'file')
                    fullLf = cand;
                end
            end
            par.loadedFile = fullLf;
        end
    catch
        par.loadedFile = '';
    end

    Iraw = data.I;

    if isfield(data,'PSC') && ~isempty(data.PSC) && isfield(data,'bg') && ~isempty(data.bg)
        PSCsig = data.PSC;
        bgDefault = data.bg;
    else
        try
            proc = computePSC(Iraw, data.TR, par, baseline);
        catch
            proc = computePSC(double(Iraw), data.TR, par, baseline);
        end
        PSCsig = proc.PSC;
        bgDefault = proc.bg;
    end

if isfield(launchCfg,'precomputedUnderlayDisplay') && ~isempty(launchCfg.precomputedUnderlayDisplay)
    bgUnderlay = launchCfg.precomputedUnderlayDisplay;
    underlayLabel = launchCfg.underlayLabel;
else
    [bgUnderlay, underlayLabel] = resolveScmVideoUnderlayChoice( ...
        studio, data, bgDefault, launchCfg.underlayChoice);
end

if isempty(bgUnderlay)
    addLog('Video GUI cancelled (no underlay selected).');
    return;
end

    if isfield(studio,'mask') && ~isempty(studio.mask)
        loadedMask = studio.mask;
        loadedMaskIsInclude = studio.maskIsInclude;
    else
        loadedMask = [];
        loadedMaskIsInclude = true;
    end

    initialFPS = 10;
    maxFPS = 240;

    setProgramStatus(false);
    drawnow;

    try
        fileLabel = [studio.activeDataset ' | ' underlayLabel];

        videoFig = play_fusi_video_final( ...
            Iraw, Iraw, PSCsig, bgUnderlay, ...
            par, initialFPS, maxFPS, ...
            data.TR, (data.nVols-1)*data.TR, ...
            baseline, ...
            loadedMask, loadedMaskIsInclude, ...
            data.nVols, false, struct(), ...
            fileLabel);

        addlistener(videoFig,'ObjectBeingDestroyed', @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Video GUI ERROR: ' ME.message]);
        errordlg(ME.message,'Video GUI Failed');
        setProgramStatus(true);
    end
end

%% =========================================================
%  MASK EDITOR CALLBACK
% =========================================================
function maskEditorCallback(~,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Mask Editor');
        return;
    end

    data = getActiveData();

    addLog(['Opening Mask Editor (Dataset: ' studio.activeDataset ')']);
    setProgramStatus(false);
    drawnow;

    try
        out = mask(studio, data.I, studio.activeDataset);

        if ~isstruct(out) || (isfield(out,'cancelled') && out.cancelled)
            addLog('Mask Editor cancelled.');
            setProgramStatus(true);
            return;
        end

     if isfield(out,'mask') && ~isempty(out.mask)
    studio.mask = logical(out.mask);
    studio.maskIsInclude = true;
    addLog('Mask stored in Studio (studio.mask).');
end

if isfield(out,'brainMask') && ~isempty(out.brainMask)
    studio.brainMask = logical(out.brainMask);
end

if isfield(out,'underlayMask') && ~isempty(out.underlayMask)
    studio.underlayMask = logical(out.underlayMask);
end

if isfield(out,'overlayMask') && ~isempty(out.overlayMask)
    studio.overlayMask = logical(out.overlayMask);
end

       % -----------------------------------------------------
% Store Mask Editor underlay/reference robustly
% Priority:
%   1) display-ready Mask Editor underlay
%   2) raw anatomical reference
% -----------------------------------------------------

storedDisplayUnderlay = false;

displayFields = { ...
    'anatomical_reference', ...
    'savedUnderlayDisplay', ...
    'savedUnderlayForReload', ...
    'underlayDisplay', ...
    'brainImage'};

for ii = 1:numel(displayFields)
    fn = displayFields{ii};

    if isfield(out,fn) && ~isempty(out.(fn))
        studio.anatomicalReference = out.(fn);
        studio.anatomicalReferenceIsDisplayReady = true;
        storedDisplayUnderlay = true;
        addLog(['Mask Editor display-ready underlay stored from field: ' fn]);
        break;
    end
end

% Also check maskBundle, if Mask Editor returned a bundle-style output
if ~storedDisplayUnderlay && isfield(out,'maskBundle') && isstruct(out.maskBundle)
    B = out.maskBundle;

    for ii = 1:numel(displayFields)
        fn = displayFields{ii};

        if isfield(B,fn) && ~isempty(B.(fn))
            studio.anatomicalReference = B.(fn);
            studio.anatomicalReferenceIsDisplayReady = true;
            storedDisplayUnderlay = true;
            addLog(['Mask Editor display-ready underlay stored from maskBundle.' fn]);
            break;
        end
    end
end

rawFields = { ...
    'anatomical_reference_raw', ...
    'anatomicalReferenceRaw', ...
    'rawUnderlay', ...
    'underlayRaw'};

for ii = 1:numel(rawFields)
    fn = rawFields{ii};

    if isfield(out,fn) && ~isempty(out.(fn))
        studio.anatomicalReferenceRaw = out.(fn);

        if ~storedDisplayUnderlay
            studio.anatomicalReference = out.(fn);
            studio.anatomicalReferenceIsDisplayReady = false;
            addLog(['Mask Editor raw underlay stored from field: ' fn]);
        end

        break;
    end
end

if isfield(out,'files') && isstruct(out.files)
    if isfield(out.files,'brainImage_mat') && ~isempty(out.files.brainImage_mat)
        studio.anatomicalReferenceFile = out.files.brainImage_mat;
    elseif isfield(out.files,'underlay_mat') && ~isempty(out.files.underlay_mat)
        studio.anatomicalReferenceFile = out.files.underlay_mat;
    end
end

        if isfield(out,'files') && isstruct(out.files) && isfield(out.files,'brainImage_mat') ...
                && ~isempty(out.files.brainImage_mat)
            studio.brainImageFile = out.files.brainImage_mat;
            addLog(['Brain-only image saved: ' studio.brainImageFile]);
        end

        guidata(fig, studio);

    catch ME
        addLog(['Mask Editor ERROR: ' ME.message]);
        errordlg(ME.message,'Mask Editor');
    end

    setProgramStatus(true);
end

%% =========================================================
%  DATASET DROPDOWN CALLBACK
% =========================================================
function datasetDropdownCallback(src,~)

    studio = guidata(fig);

    keys = get(src,'UserData');
    if isempty(keys) || ~iscell(keys)
        return;
    end

    idx = get(src,'Value');
    idx = max(1, min(numel(keys), idx));

    studio.activeDataset = keys{idx};
    guidata(fig, studio);

    if isfield(studio,'activeDatasetText') && isgraphics(studio.activeDatasetText)
        fullName = getDatasetDisplayName(studio, studio.activeDataset);
        showName = makeDropdownLabel(fullName);
        set(studio.activeDatasetText, ...
            'String',['ACTIVE DATASET: ' showName], ...
            'TooltipString',['ACTIVE DATASET: ' fullName]);
    end
end

%% =========================================================
%  REFRESH DATASET DROPDOWN
% =========================================================
function refreshDatasetDropdown()

    studio = guidata(fig);
    dd = findobj(fig,'Tag','datasetDropdown');

    if isempty(dd) || ~ishghandle(dd)
        return;
    end

    keys = fieldnames(studio.datasets);
    if isempty(keys)
        set(dd,'String',{'<none>'},'Value',1,'UserData',{{}});
        return;
    end

    labels = cell(size(keys));
    for i = 1:numel(keys)
        k = keys{i};
        labels{i} = makeDropdownLabel(getDatasetDisplayName(studio, k));
    end

    set(dd,'String',labels,'UserData',keys);

    idx = find(strcmp(keys, studio.activeDataset), 1);
    if isempty(idx)
        idx = 1;
        studio.activeDataset = keys{1};
    end

    set(dd,'Value',idx);

    if isfield(studio,'activeDatasetText') && isgraphics(studio.activeDatasetText)
        fullName = getDatasetDisplayName(studio, studio.activeDataset);
        showName = makeDropdownLabel(fullName);
        set(studio.activeDatasetText, ...
            'String',['ACTIVE DATASET: ' showName], ...
            'TooltipString',['ACTIVE DATASET: ' fullName]);
    end

    guidata(fig, studio);
end

%% =========================================================
%  GET ACTIVE DATASET
% =========================================================
function data = getActiveData()

    studio = guidata(fig);
    selected = studio.activeDataset;

    if isempty(selected)
        error('No active dataset selected.');
    end

    data = studio.datasets.(selected);

    if isstruct(data) && isfield(data,'isLazy') && data.isLazy
        addLog(['Loading dataset from disk: ' selected]);
        setProgramStatus(false);
        drawnow;

        try
            oldLazy = data;
            m = matfile(oldLazy.lazyFile);
            tmp = m.newData;
            data = tmp;

            if ~isfield(data,'displayNameFull') || isempty(data.displayNameFull)
                if isfield(oldLazy,'displayNameFull') && ~isempty(oldLazy.displayNameFull)
                    data.displayNameFull = oldLazy.displayNameFull;
                else
                    data.displayNameFull = selected;
                end
            end

            data.isLazy = false;
            if isfield(oldLazy,'lazyFile')
                data.lazyFile = oldLazy.lazyFile;
            end

            studio.datasets.(selected) = data;
            guidata(fig, studio);

            addLog(['Dataset loaded: ' data.displayNameFull]);

        catch ME
            addLog(['Lazy load ERROR: ' ME.message]);
            setProgramStatus(true);
            rethrow(ME);
        end

        setProgramStatus(true);
    end
end

%% =========================================================
%  UNLOCK ALL BUTTONS
% =========================================================
function unlockAllButtons()

    studio = guidata(fig);

    if ~isfield(studio,'allButtons') || isempty(studio.allButtons)
        return;
    end

    for i = 1:length(studio.allButtons)
        h = studio.allButtons{i};
        if ~isempty(h) && ishghandle(h)
            try
                set(h, 'Enable','on', 'BackgroundColor',[0.25 0.25 0.25]);
            catch
            end
        end
    end

    guidata(fig, studio);
end

%% =========================================================
%  EXPORT STUDIO LOG
% =========================================================
function exportSessionCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    if ~isfield(studio,'logBox') || isempty(studio.logBox)
        errordlg('No log available.');
        return;
    end

    if isfield(studio,'logBoxJava') && ~isempty(studio.logBoxJava)
        rawText = char(studio.logBoxJava.getText());
        if isempty(strtrim(rawText))
            errordlg('Studio log is empty.');
            return;
        end
        logContent = regexp(rawText, '\r\n|\n|\r', 'split');
    else
        logContent = get(studio.logBox,'String');
        if isempty(logContent)
            errordlg('Studio log is empty.');
            return;
        end

        if ischar(logContent)
            logContent = cellstr(logContent);
        elseif ~iscell(logContent)
            logContent = {logContent};
        end
    end

    choice = questdlg( ...
        'Also update publication-ready status before exporting?', ...
        'Export Studio Log', ...
        'Yes','No','Cancel','Yes');

    if isempty(choice) || strcmpi(choice,'Cancel')
        addLog('Studio log export cancelled.');
        return;
    end

    if strcmpi(choice,'Yes')
        pubChoice = questdlg( ...
            'Mark this scan/animal as publication usable?', ...
            'Publication Ready', ...
            'Yes','No','Cancel','Yes');

        if isempty(pubChoice) || strcmpi(pubChoice,'Cancel')
            addLog('Studio log export cancelled.');
            return;
        end

        noteAns = inputdlg( ...
            {'Optional note (e.g. low motion, clean QC, good anatomy):'}, ...
            'Publication Ready Note', ...
            1, {studio.publicationReadyNote});

        if isempty(noteAns)
            note = '';
        else
            note = strtrim(noteAns{1});
        end

        isReady = strcmpi(pubChoice,'Yes');

        studio.publicationReady = isReady;
        studio.publicationReadyNote = note;
        studio.publicationReadyTime = datestr(now,'yyyy-mm-dd HH:MM:SS');
        guidata(fig, studio);

        savePublicationReadyFile(studio, isReady, note);
    end

    ts = datestr(now,'yyyymmdd_HHMMSS');
    outFile = fullfile(studio.exportPath, ['StudioLog_' ts '.txt']);

    fid = fopen(outFile,'w');
    if fid == -1
        errordlg(['Could not write log file: ' outFile]);
        return;
    end

    fprintf(fid,'fUSI Studio Log Export\n');
    fprintf(fid,'Timestamp: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));

    if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
        fprintf(fid,'Loaded file: %s\n', studio.loadedFile);
    end
    if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
        fprintf(fid,'Active dataset: %s\n', studio.activeDataset);
    end
    if isfield(studio,'exportPath') && ~isempty(studio.exportPath)
        fprintf(fid,'Export path: %s\n', studio.exportPath);
    end

    if ~isempty(studio.publicationReady)
        if studio.publicationReady
            pubTxt = 'YES';
        else
            pubTxt = 'NO';
        end
        fprintf(fid,'Publication ready: %s\n', pubTxt);
        fprintf(fid,'Publication decision time: %s\n', studio.publicationReadyTime);
        fprintf(fid,'Publication note: %s\n', studio.publicationReadyNote);
    else
        fprintf(fid,'Publication ready: not set\n');
    end

    fprintf(fid,'\n');
    fprintf(fid,'----------------------------------------\n');
    fprintf(fid,'Studio Log\n');
    fprintf(fid,'----------------------------------------\n');

    for i = 1:numel(logContent)
        fprintf(fid,'%s\n',logContent{i});
    end

    fclose(fid);

    addLog(['Studio log exported -> ' outFile]);
end

%% =========================================================
%  MARK PUBLICATION READY
% =========================================================
function markPublicationReadyCallback(~,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    choice = questdlg( ...
        'Mark this scan/animal as publication usable?', ...
        'Publication Ready', ...
        'Yes','No','Cancel','Yes');

    if isempty(choice) || strcmpi(choice,'Cancel')
        addLog('Publication-ready marking cancelled.');
        return;
    end

    noteAns = inputdlg( ...
        {'Optional note (e.g. stable motion, good mask, atlas ok):'}, ...
        'Publication Ready Note', ...
        1, {''});

    if isempty(noteAns)
        note = '';
    else
        note = strtrim(noteAns{1});
    end

    isReady = strcmpi(choice,'Yes');

    studio.publicationReady = isReady;
    studio.publicationReadyNote = note;
    studio.publicationReadyTime = datestr(now,'yyyy-mm-dd HH:MM:SS');
    guidata(fig, studio);

    try
        savePublicationReadyFile(studio, isReady, note);

        if isReady
            addLog('Marked as PUBLICATION READY.');
        else
            addLog('Marked as NOT publication ready.');
        end

    catch ME
        addLog(['Publication-ready save ERROR: ' ME.message]);
        errordlg(ME.message,'Publication Ready Save Error');
    end
end

%% =========================================================
%  HELP BUTTON
% =========================================================
function helpCallback(~,~)

    bgColor = [0.08 0.08 0.08];
    fgColor = [1 1 1];

    helpFig = figure( ...
        'Name','fUSI Studio - Complete User Guide', ...
        'Color',bgColor, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Position',[200 80 1100 850]);

    txtBox = uicontrol(helpFig, ...
        'Style','edit', ...
        'Max',2, ...
        'Min',0, ...
        'Units','normalized', ...
        'Position',[0.03 0.03 0.94 0.94], ...
        'BackgroundColor',bgColor, ...
        'ForegroundColor',fgColor, ...
        'HorizontalAlignment','left', ...
        'FontName','Arial', ...
        'FontSize',14);

    guide = {
'==========================================================================='
'                        fUSI STUDIO - COMPLETE GUIDE'
'==========================================================================='
''
'OVERVIEW'
'-------------------------------------------------------------------------'
'fUSI Studio is a structured processing and analysis environment for'
'functional ultrasound imaging (fUSI). It helps you load datasets, inspect'
'quality, run preprocessing, create masks, register data to atlas space,'
'visualize signal changes, and perform higher-level analyses.'
''
'Supported data formats:'
'  - 2D probe  : Y x X x T'
'  - 3D matrix : Y x X x Z x T'
''
'When loading a dataset, the system automatically:'
'  - Extracts TR'
'  - Computes number of volumes'
'  - Computes total acquisition time'
'  - Detects probe type'
'  - Creates AnalysedData folder structure'
''
'RECOMMENDED WORKFLOW'
'-------------------------------------------------------------------------'
'1) Load Data'
'2) QC'
'3) Run Pre-Processing'
'4) Mask Editor'
'5) Registration to Atlas'
'6) Visualization'
'7) Further Processing'
'8) Group Analysis / Functional Connectivity'
''
'PRACTICAL ADVICE'
'-------------------------------------------------------------------------'
'  - Keep the raw dataset untouched'
'  - Use the dataset dropdown to switch versions'
'  - Prefer running QC before preprocessing'
'  - Use Mask Editor before final visualization'
'  - Export the Studio Log to keep a workflow record'
''
'END OF GUIDE'
'==========================================================================='
};

    set(txtBox,'String',strjoin(guide,newline));
end

%% =========================================================
%  LOGGING UTILITY
% =========================================================
function addLog(msg)

    if isempty(fig) || ~ishandle(fig)
        return;
    end

    studio = guidata(fig);

    timestamp = datestr(now,'HH:MM:SS');
    newEntry = sprintf('[%s] %s', timestamp, msg);
    wrappedEntries = wrapLogMessage(newEntry, 115);

    if isfield(studio,'logBoxJava') && ~isempty(studio.logBoxJava)
        try
            oldText = char(studio.logBoxJava.getText());
            if isempty(oldText)
                combined = strjoin(wrappedEntries, sprintf('\n'));
            else
                combined = [oldText sprintf('\n') strjoin(wrappedEntries, sprintf('\n'))];
            end

            studio.logBoxJava.setText(combined);
            studio.logBoxJava.setCaretPosition(studio.logBoxJava.getDocument().getLength());
            drawnow;
            return;
        catch
        end
    end

    if isfield(studio,'logBox') && ~isempty(studio.logBox) && ishghandle(studio.logBox)
        current = get(studio.logBox,'String');

        if isempty(current)
            current = {};
        elseif ischar(current)
            current = cellstr(current);
        elseif ~iscell(current)
            current = {current};
        end

        if numel(current) == 1 && isempty(strtrim(current{1}))
            current = {};
        end

        set(studio.logBox,'String',[current; wrappedEntries(:)]);
        drawnow;
    end
end

%% =========================================================
%  FOOTER LABEL
% =========================================================
function s = buildFooterLabel()
    person = 'Soner Caner Cagun';
    tool = 'HUMoR Analysis Tool';
    inst = 'Max-Planck Institute for Biological Cybernetics';
    dt = datestr(now,'yyyy-mm-dd HH:MM');
    s = sprintf('%s - %s - %s - %s', person, tool, inst, dt);
end

%% =========================================================
%  STATUS BAR HANDLER
% =========================================================
function setProgramStatus(isReady)

    studio = guidata(fig);
    statusPanel = studio.statusPanel;
    statusText = studio.statusText;

    bgReady = [0.15 0.60 0.20];
    bgNotReady = [0.85 0.20 0.20];
    fg = [1 1 1];

    if isReady
        bg = bgReady;
        txt = 'PROGRAM READY';
    else
        bg = bgNotReady;
        txt = 'PROGRAM NOT READY';
    end

    set(statusPanel, ...
        'BackgroundColor',bg, ...
        'HighlightColor',bg, ...
        'ShadowColor',bg);

    set(statusText, ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'String',txt, ...
        'FontWeight','bold', ...
        'FontSize',16);

    drawnow;
end

%% =========================================================
%  SMALL HELPER
% =========================================================
function choice = showPcaIcaMethodDialog()

    choice = '';

    bg    = [0.06 0.06 0.07];
    panel = [0.10 0.10 0.11];
    fg    = [0.95 0.95 0.95];
    fgDim = [0.86 0.86 0.89];

    dlg = figure( ...
        'Name','PCA / ICA', ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
        'Position',[500 300 520 270], ...
        'WindowStyle','modal', ...
        'CloseRequestFcn',@onCancel);

    try, movegui(dlg,'center'); catch, end

    uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.02 0.06 0.96 0.88], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',[0.35 0.35 0.35], ...
        'BorderType','line');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized','Position',[0.08 0.70 0.84 0.14], ...
        'String','Choose decomposition mode', ...
        'BackgroundColor',bg,'ForegroundColor',fg, ...
        'FontSize',18,'FontWeight','bold', ...
        'HorizontalAlignment','center');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized','Position',[0.08 0.46 0.84 0.16], ...
        'String',{ ...
            'PCA = fast variance-based cleanup', ...
            'ICA = source separation with IC review'}, ...
        'BackgroundColor',bg,'ForegroundColor',fgDim, ...
        'FontSize',12,'FontWeight','bold', ...
        'HorizontalAlignment','center');

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','PCA', ...
        'Units','normalized','Position',[0.08 0.12 0.24 0.18], ...
        'FontWeight','bold','FontSize',14, ...
        'BackgroundColor',[0.20 0.55 0.90], ...
        'ForegroundColor','w', ...
        'Callback',@onPCA);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','ICA', ...
        'Units','normalized','Position',[0.38 0.12 0.24 0.18], ...
        'FontWeight','bold','FontSize',14, ...
        'BackgroundColor',[0.18 0.72 0.32], ...
        'ForegroundColor','w', ...
        'Callback',@onICA);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'String','Cancel', ...
        'Units','normalized','Position',[0.68 0.12 0.24 0.18], ...
        'FontWeight','bold','FontSize',14, ...
        'BackgroundColor',[0.82 0.30 0.30], ...
        'ForegroundColor','w', ...
        'Callback',@onCancel);

    waitfor(dlg);

    function onPCA(~,~)
        choice = 'PCA';
        if ishghandle(dlg), delete(dlg); end
    end

    function onICA(~,~)
        choice = 'ICA';
        if ishghandle(dlg), delete(dlg); end
    end

    function onCancel(~,~)
        choice = 'Cancel';
        if ishghandle(dlg), delete(dlg); end
    end
end
    function [TR, probeType, defaultTR, wasCancelled] = promptTRAfterLoad(data, meta)

TR = [];
wasCancelled = false;

[probeType, defaultTR] = detectProbeTypeFromMeta(data, meta);

detectedTR = [];
try
    if isfield(data,'TR') && ~isempty(data.TR) && isfinite(data.TR) && data.TR > 0
        detectedTR = double(data.TR);
    end
catch
end

msg = sprintf([ ...
    'Detected probe type: %s\n\n' ...
    'Preset default TR: %.0f ms (%.3f s)\n'], ...
    probeType, defaultTR*1000, defaultTR);

if ~isempty(detectedTR)
    msg = [msg sprintf('\nLoader/file TR before user choice: %.0f ms (%.3f s)\n', ...
        detectedTR*1000, detectedTR)];
end

msg = [msg sprintf('\nChoose "Use Default" or "Custom TR".')];

choice = questdlg(msg, 'TR Selection', ...
    'Use Default', 'Custom TR', 'Cancel', 'Use Default');

if isempty(choice) || strcmpi(choice,'Cancel')
    wasCancelled = true;
    return;
end

if strcmpi(choice,'Use Default')
    TR = defaultTR;
    return;
end

while true
    answ = inputdlg( ...
        {sprintf('Enter TR in ms for %s:', probeType)}, ...
        'Custom TR', 1, {sprintf('%.0f', defaultTR*1000)});

    if isempty(answ)
        wasCancelled = true;
        return;
    end

    trMs = str2double(answ{1});
    if isfinite(trMs) && trMs > 0
        TR = trMs / 1000;
        return;
    end

    uiwait(errordlg('Please enter a positive numeric TR in milliseconds.', ...
        'Invalid TR', 'modal'));
end

end


function [probeType, defaultTR] = detectProbeTypeFromMeta(data, meta)

probeType = '2D Probe';
defaultTR = 0.320;

try
    if isfield(meta,'rawMetadata') && isfield(meta.rawMetadata,'probeTypeAutoDetected') ...
            && ~isempty(meta.rawMetadata.probeTypeAutoDetected)

        probeType = meta.rawMetadata.probeTypeAutoDetected;

        if strcmpi(probeType, 'Matrix (3D) Probe')
            defaultTR = 0.480;
        else
            defaultTR = 0.320;
        end
        return;
    end
catch
end

try
    if ndims(data.I) >= 4 && size(data.I,3) > 1
        probeType = 'Matrix (3D) Probe';
        defaultTR = 0.480;
    end
catch
end

end
    
    function out = iff(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

%% =========================================================
%  DATASET NAME HELPERS
% =========================================================
    function label = makeDropdownLabel(fullName)

    ts = regexp(fullName, '_\d{8}_\d{6}', 'match');

    if isempty(ts)
        base = fullName;
        lastTS = '';
    else
        lastTS = ts{end};
        lastTS = lastTS(2:end);
        base = regexprep(fullName, '_\d{8}_\d{6}', '');
    end

    % remove raw_ and FUS from display
    base = regexprep(base,'^raw_','');
    base = regexprep(base,'(^|_)FUS(_|$)','$1$2');

    % keep old compatibility
    base = strrep(base, '_gabriel_', '_imregdemons_');
    base = strrep(base, '_frrej_', '_frameRej_');
    base = strrep(base, '_temporal_', '_temp_');
    base = strrep(base, '_temporalSmooth_', '_tempSmooth_');
base = strrep(base, '_subsample_', '_subsample_');
    base = strrep(base, '_scrub_', '_scrub_');
    base = strrep(base, '_despike_', '_despike_');
    base = strrep(base, '_filt_', '_filt_');
    base = strrep(base, '_pca_', '_pca_');
    base = strrep(base, '_motor_', '_motor_');
    base = regexprep(base,'_nsub','_n');

    % prettier PCA display: dropPC1-2 -> dropPC1/2
    tok = regexp(base,'dropPC([0-9\-]+)','tokens','once');
    if ~isempty(tok)
        oldStr = ['dropPC' tok{1}];
        newStr = ['dropPC' strrep(tok{1},'-','/')];
        base = strrep(base, oldStr, newStr);
    end

    % prettier ICA display: dropIC1-2 -> dropIC1/2
tok = regexp(base,'dropIC([0-9\-]+)','tokens','once');
if ~isempty(tok)
    oldStr = ['dropIC' tok{1}];
    newStr = ['dropIC' strrep(tok{1},'-','/')];
    base = strrep(base, oldStr, newStr);
end


    base = regexprep(base,'_+','_');
    base = regexprep(base,'^_','');
    base = regexprep(base,'_$','');

    if isempty(lastTS)
        label = base;
    else
        label = sprintf('%s (%s)', base, lastTS);
    end

    label = shortenMiddle(label, 85);
end

function name = getDatasetDisplayName(studio, key)
    name = key;
    try
        d = studio.datasets.(key);
        if isstruct(d) && isfield(d,'displayNameFull') && ~isempty(d.displayNameFull)
            name = d.displayNameFull;
        end
    catch
    end
end

function s = shortenMiddle(s, maxLen)

    if nargin < 2 || isempty(maxLen)
        maxLen = 85;
    end

    if length(s) <= maxLen
        return;
    end

    nFront = ceil((maxLen - 3) / 2);
    nBack = floor((maxLen - 3) / 2);
    s = [s(1:nFront) '...' s(end-nBack+1:end)];
end

function name = cleanLoadedDatasetName(name)

    name = regexprep(name,'^raw_','');
    name = regexprep(name,'(^|_)FUS(_|$)','$1$2');
    name = regexprep(name,'_+','_');
    name = regexprep(name,'^_+','');
    name = regexprep(name,'_+$','');

    if isempty(name)
        name = 'dataset';
    end
end

function stem = getCurrentNamingStem(studio)

    stem = '';

    try
        if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
            stem = getDatasetDisplayName(studio, studio.activeDataset);
        end
    catch
    end

    if isempty(stem) && isfield(studio,'loadedName') && ~isempty(studio.loadedName)
        stem = studio.loadedName;
    end

    if isempty(stem)
        stem = 'dataset';
    end

    % remove only trailing timestamp so chain stays:
    % WT..._imregdemons_median_nsub100_20260317_123456
    % -> WT..._imregdemons_median_nsub100
    stem = regexprep(stem,'_\d{8}_\d{6}$','');

    % remove raw_ and FUS
    stem = regexprep(stem,'^raw_','');
    stem = regexprep(stem,'(^|_)FUS(_|$)','$1$2');

    stem = regexprep(stem,'_+','_');
    stem = regexprep(stem,'^_+','');
    stem = regexprep(stem,'_+$','');

    if isempty(stem)
        stem = 'dataset';
    end
end

function s = numTag(x)
    s = num2str(x,'%.6g');
    s = strrep(s,'.','p');
    s = strrep(s,'-','m');
end

function tag = makePcDropTag(sel)

    if isempty(sel)
        tag = 'dropPCnone';
        return;
    end

    sel = unique(sel(:)');
    parts = arrayfun(@num2str, sel, 'UniformOutput', false);
    tag = ['dropPC' strjoin(parts,'-')];
end

function tag = makeIcDropTag(sel)

    if isempty(sel)
        tag = 'dropICnone';
        return;
    end

    sel = unique(sel(:)');
    parts = arrayfun(@num2str, sel, 'UniformOutput', false);
    tag = ['dropIC' strjoin(parts,'-')];
end

function tag = makeFilterTag(opts)

    ordTag = '';
    if isfield(opts,'order') && ~isempty(opts.order) && isfinite(opts.order)
        ordTag = sprintf('_o%d', round(opts.order));
    end

    switch lower(opts.type)
        case 'low'
            tag = ['LPF' numTag(opts.FcHigh) 'Hz' ordTag];

        case 'high'
            tag = ['HPF' numTag(opts.FcLow) 'Hz' ordTag];

        case 'band'
            tag = ['BPF' numTag(opts.FcLow) 'to' numTag(opts.FcHigh) 'Hz' ordTag];

        otherwise
            tag = ['FILT' ordTag];
    end

    if isfield(opts,'trimStart') && isfield(opts,'trimEnd')
        if opts.trimStart > 0 || opts.trimEnd > 0
            tag = sprintf('%s_trim%s-%ss', ...
                tag, numTag(opts.trimStart), numTag(opts.trimEnd));
        end
    end
end
%% =========================================================
%  SCM UNDERLAY CHOOSER
% =========================================================
function [bg, label] = chooseSCMUnderlay(studio, data, bgDefault)

    bg = [];
    label = '';

    opts = { ...
        'Default (Video GUI reference / PSC bg)', ...
        'Mean of ACTIVE dataset', ...
        'Median of ACTIVE dataset (robust)', ...
        'Select external underlay file (DP/anatomy) from RAW folder...', ...
        'Cancel'};

    idx = menu('Choose SCM underlay image:', opts{:});

    if idx == 0 || idx == 5
        return;
    end

    switch idx
        case 1
            bg = bgDefault;
            label = 'Default (VideoGUI bg)';

        case 2
            bg = computeUnderlayFromActive(data,'mean');
            label = 'Mean(I)';

        case 3
            bg = computeUnderlayFromActive(data,'median');
            label = 'Median(I)';

        case 4
            startPath = pwd;

            if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
                visFolder = fullfile(studio.exportPath,'Visualization');
                if exist(visFolder,'dir')
                    startPath = visFolder;
                else
                    startPath = studio.exportPath;
                end
            elseif isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
                startPath = studio.loadedPath;
            end

            [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.tif;*.tiff', ...
                               'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.tif)'}, ...
                               'Select underlay (DP/anatomy)', startPath);
            if isequal(f,0)
                return;
            end

            bg = loadUnderlayFile(fullfile(p,f));
            if isempty(bg)
                return;
            end

            [~,nm,ext] = fileparts(f);
            label = ['File: ' nm ext];
    end
end

function [bg, label] = resolveScmVideoUnderlayChoice(studio, data, bgDefault, idx)

    bg = [];
    label = '';

    switch idx
        case 1
            bg = bgDefault;
            label = 'Default (VideoGUI bg)';

        case 2
            bg = computeUnderlayFromActive(data,'mean');
            label = 'Mean(I)';

        case 3
            bg = computeUnderlayFromActive(data,'median');
            label = 'Median(I)';

        case 4
            startPath = pwd;

            if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
                visFolder = fullfile(studio.exportPath,'Visualization');
                if exist(visFolder,'dir')
                    startPath = visFolder;
                else
                    startPath = studio.exportPath;
                end
            elseif isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
                startPath = studio.loadedPath;
            end

            [f,p] = uigetfile( ...
                {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.tif;*.tiff', ...
                 'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.tif)'}, ...
                'Select underlay (DP/anatomy)', startPath);

            if isequal(f,0)
                return;
            end

            bg = loadUnderlayFile(fullfile(p,f));
            if isempty(bg)
                return;
            end

            [~,nm,ext] = fileparts(f);
            label = ['File: ' nm ext];
    end
end

function bg = computeUnderlayFromActive(data, method)

    I = data.I;
    dimT = ndims(I);

    if strcmpi(method,'mean')
        bg = mean(double(I), dimT);
        return;
    end

    sz = size(I);
    T = sz(dimT);

    maxFrames = 600;
    if T <= maxFrames
        idx = 1:T;
    else
        step = ceil(T / maxFrames);
        idx = 1:step:T;
    end

    subs = repmat({':'},1,dimT);
    subs{dimT} = idx;

    Isub = double(I(subs{:}));
    bg = median(Isub, dimT);
end

function U = loadUnderlayFile(f)

    if ~exist(f,'file')
        error('Underlay file not found: %s', f);
    end

    isNiiGz = numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz');

    try
        if isNiiGz
            tmpDir = tempname;
            mkdir(tmpDir);
            gunzip(f, tmpDir);
            d = dir(fullfile(tmpDir,'*.nii'));
            if isempty(d)
                error('gunzip failed for %s', f);
            end
            niiFile = fullfile(tmpDir, d(1).name);
            V = niftiread(niiFile);
            try
                rmdir(tmpDir,'s');
            catch
            end
            U = double(V);
            U = squeezeTo2Dor3D(U);
            U = toGray(U);
            return;
        end

        [~,~,ext] = fileparts(f);

        if strcmpi(ext,'.nii')
            V = niftiread(f);
            U = double(V);
            U = squeezeTo2Dor3D(U);
            U = toGray(U);
            return;
        end

      if strcmpi(ext,'.mat')
    S = load(f);
    U = studio_pickUnderlayFromMat(S);
    U = double(U);
    U = squeezeTo2Dor3D(U);
    U = toGray(U);
    return;
end

        A = imread(f);
        U = double(A);
        U = toGray(U);
        return;

    catch ME
        errordlg(ME.message,'Underlay load failed');
        U = [];
    end
end

    function U = studio_pickUnderlayFromMat(S)

    hasBundle = isfield(S,'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle);

    if hasBundle
        B = S.maskBundle;
    else
        B = S;
    end

    pref = { ...
        'savedUnderlayDisplay', ...
        'brainImage', ...
        'anatomical_reference_raw', ...
        'savedUnderlayForReload', ...
        'underlay', ...
        'bg', ...
        'anatomical_reference', ...
        'atlasUnderlayRGB', ...
        'atlasUnderlay', ...
        'img', ...
        'I', ...
        'Data'};

    [ok,U] = studio_findPreferredNumericField(B, pref);
    if ok
        return;
    end

    if hasBundle
        [ok,U] = studio_findPreferredNumericField(S, pref);
        if ok
            return;
        end
    end

    skip = { ...
        'mask', ...
        'loadedMask', ...
        'activeMask', ...
        'brainMask', ...
        'underlayMask', ...
        'overlayMask', ...
        'signalMask', ...
        'maskIsInclude', ...
        'loadedMaskIsInclude', ...
        'overlayMaskIsInclude'};

    [ok,U] = studio_findAnyNonMaskNumericField(B, skip);
    if ok
        return;
    end

    if hasBundle
        [ok,U] = studio_findAnyNonMaskNumericField(S, skip);
        if ok
            return;
        end
    end

    error('No usable underlay variable found in MAT file.');
end

function [ok,U] = studio_findPreferredNumericField(Sx, names)
    ok = false;
    U = [];

    for ii = 1:numel(names)
        fn = names{ii};
        if ~isfield(Sx, fn)
            continue;
        end

        [ok1, val] = studio_unwrapNumericCandidate(Sx.(fn));
        if ok1
            ok = true;
            U = val;
            return;
        end
    end
end

function [ok,U] = studio_findAnyNonMaskNumericField(Sx, skip)
    ok = false;
    U = [];

    fn = fieldnames(Sx);
    for ii = 1:numel(fn)
        name = fn{ii};

        if any(strcmpi(name, skip))
            continue;
        end

        [ok1, val] = studio_unwrapNumericCandidate(Sx.(name));
        if ~ok1
            continue;
        end

        if studio_looksLikeMaskArray(val)
            continue;
        end

        ok = true;
        U = val;
        return;
    end
end

function [ok,U] = studio_unwrapNumericCandidate(v)
    ok = false;
    U = [];

    if isstruct(v)
        if isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
            ok = true;
            U = v.Data;
            return;
        end
        if isfield(v,'I') && isnumeric(v.I) && ~isempty(v.I)
            ok = true;
            U = v.I;
            return;
        end
        return;
    end

    if isnumeric(v) && ~isempty(v)
        ok = true;
        U = v;
    end
end

function tf = studio_looksLikeMaskArray(A)
    tf = false;

    try
        A = double(A);
        A = A(isfinite(A));

        if isempty(A)
            tf = true;
            return;
        end

        u = unique(A);

        if numel(u) <= 2 && all(ismember(u, [0 1]))
            tf = true;
            return;
        end
    catch
        tf = false;
    end
end

function X = squeezeTo2Dor3D(X)
    while ndims(X) > 3
        X = mean(X, ndims(X));
    end
end

function G = toGray(X)
    if ndims(X) == 3 && size(X,3) == 3
        R = X(:,:,1);
        Gc = X(:,:,2);
        B = X(:,:,3);
        G = 0.2989*R + 0.5870*Gc + 0.1140*B;
        return;
    end
    G = X;
end

%% =========================================================
%  SAVE PUBLICATION READY FILE
% =========================================================
function savePublicationReadyFile(studio, isReady, note)

    if ~isfield(studio,'exportPath') || isempty(studio.exportPath) || ~exist(studio.exportPath,'dir')
        error('Export path does not exist.');
    end

    yesFile = fullfile(studio.exportPath,'PUBLICATION_READY_YES.txt');
    noFile = fullfile(studio.exportPath,'PUBLICATION_READY_NO.txt');

    if exist(yesFile,'file')
        delete(yesFile);
    end
    if exist(noFile,'file')
        delete(noFile);
    end

    if isReady
        outFile = yesFile;
        statusText = 'YES';
    else
        outFile = noFile;
        statusText = 'NO';
    end

    fid = fopen(outFile,'w');
    if fid == -1
        error('Could not create file: %s', outFile);
    end

    fprintf(fid,'Publication ready: %s\n', statusText);
    fprintf(fid,'Timestamp: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));

    if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
        fprintf(fid,'Loaded file: %s\n', studio.loadedFile);
    end
    if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
        fprintf(fid,'Active dataset: %s\n', studio.activeDataset);
    end
    if isfield(studio,'exportPath') && ~isempty(studio.exportPath)
        fprintf(fid,'Analysed folder: %s\n', studio.exportPath);
    end

    if nargin >= 3 && ~isempty(note)
        fprintf(fid,'Note: %s\n', note);
    else
        fprintf(fid,'Note: \n');
    end

    fclose(fid);
end

%% =========================================================
%  MAKE SAFE KEY
% =========================================================
function key = makeSafeKey(fullName, datasetsStruct)

    s = regexprep(fullName, '[^A-Za-z0-9_]', '_');

    if exist('matlab.lang.makeValidName','file')
        s = matlab.lang.makeValidName(s);
    else
        s = genvarname(s); %#ok<DEPGENAM>
    end

    maxLen = namelengthmax;
    h = shortHash(fullName);

    if length(s) > maxLen
        keep = maxLen - (1 + length(h));
        keep = max(1, keep);
        s = [s(1:keep) '_' h];
    end

    key = s;

    if isfield(datasetsStruct, key)
        n = 2;
        base = key;
        while true
            suf = sprintf('_v%d', n);
            cand = base;
            if length(cand) + length(suf) > maxLen
                cand = cand(1:maxLen - length(suf));
            end
            cand = [cand suf];
            if ~isfield(datasetsStruct, cand)
                key = cand;
                break;
            end
            n = n + 1;
        end
    end
end

function h = shortHash(s)
    try
        md = java.security.MessageDigest.getInstance('MD5');
        md.update(uint8(s(:)'));
        d = typecast(md.digest,'uint8');
        hx = lower(reshape(dec2hex(d,2).',1,[]));
        h = hx(1:8);
    catch
        h = sprintf('%08x', mod(sum(uint32(s)), 2^32));
    end
end

%% =========================================================
%  WRAP LOG MESSAGE
% =========================================================
function lines = wrapLogMessage(msg, maxChars)

    if nargin < 2 || isempty(maxChars)
        maxChars = 115;
    end

    if isstring(msg)
        msg = char(msg);
    end

    rawLines = regexp(msg, '\r\n|\n|\r', 'split');
    lines = {};

    for ii = 1:numel(rawLines)
        remLine = rawLines{ii};

        if isempty(remLine)
            lines{end+1,1} = ''; %#ok<AGROW>
            continue;
        end

        while length(remLine) > maxChars
            seg = remLine(1:maxChars);
            cut = regexp(seg, '[\\/\s,_:;=-]', 'once');
            if isempty(cut)
                cut = maxChars;
            else
                allCuts = regexp(seg, '[\\/\s,_:;=-]');
                cut = allCuts(end);
            end

            if cut < 1
                cut = maxChars;
            end

            lines{end+1,1} = strtrim(remLine(1:cut)); %#ok<AGROW>

            if cut < length(remLine)
                remLine = ['    ' strtrim(remLine(cut+1:end))];
            else
                remLine = '';
            end
        end

        if ~isempty(remLine)
            lines{end+1,1} = remLine; %#ok<AGROW>
        end
    end
end

%% =========================================================
%  FIGURE CLEANUP HELPERS
% =========================================================
function safeCloseFigureHandle(S, fieldName)

    try
        if isstruct(S) && isfield(S, fieldName)
            h = S.(fieldName);
            if ~isempty(h) && ishghandle(h)
                close(h);
            end
        end
    catch
    end
end


function closeNewFigures(figsBefore)

    try
        figsNow = findall(0, 'Type', 'figure');
    catch
        return;
    end

    if isempty(figsNow)
        return;
    end

    for k = 1:numel(figsNow)
        h = figsNow(k);

        try
            if isequal(h, fig)
                continue;
            end
        catch
        end

        wasPresent = false;
        for j = 1:numel(figsBefore)
            try
                if isequal(h, figsBefore(j))
                    wasPresent = true;
                    break;
                end
            catch
            end
        end

        if ~wasPresent
            try
                if ishghandle(h)
                    close(h);
                end
            catch
            end
        end
    end
end


function closeLingeringQCFigures()

    try
        figs = findall(0, 'Type', 'figure');
    catch
        figs = [];
    end

    if isempty(figs)
        return;
    end

    badTerms = { ...
        'frame-rate', ...
        'frame rate', ...
        'rejected volumes', ...
        'global signal stability', ...
        'urban', ...
        'montaldo', ...
        'imregdemons', ...
        'gabriel', ...
        'subsampling', ...
        'qc'};

    for k = 1:numel(figs)
        h = figs(k);

        try
            if isequal(h, fig)
                continue;
            end
        catch
        end

        try
            nm = get(h, 'Name');
            if isempty(nm)
                nm = '';
            end
            nmL = lower(char(nm));

            shouldClose = false;
            for j = 1:numel(badTerms)
                if ~isempty(strfind(nmL, badTerms{j})) %#ok<STREMP>
                    shouldClose = true;
                    break;
                end
            end

            if shouldClose && ishghandle(h)
                close(h);
            end
        catch
        end
    end
end


%% =========================================================
%  ICON HELPER
% =========================================================
function addStudioIcon()

    iconFile = 'D:\Github\HUMOR-Analysis-Tool\Icon.png';

    if ~exist(iconFile,'file')
        disp(['Icon file not found: ' iconFile]);
        return;
    end

    try
        [img, ~, alpha] = imread(iconFile);

        if isempty(alpha)
            alpha = 255 * ones(size(img,1), size(img,2), 'uint8');
        end

        padTop = 90;
        padBottom = 20;
        padLeft = 20;
        padRight = 20;

        if ndims(img) == 2
            img = repmat(img, [1 1 3]);
        end

        H = size(img,1);
        W = size(img,2);

        newH = H + padTop + padBottom;
        newW = W + padLeft + padRight;

        imgPad = uint8(zeros(newH, newW, 3));
        alphaPad = uint8(zeros(newH, newW));

        imgPad(padTop+1:padTop+H, padLeft+1:padLeft+W, :) = img;
        alphaPad(padTop+1:padTop+H, padLeft+1:padLeft+W) = alpha;

        iconPanel = uipanel('Parent', fig, ...
            'Units','normalized', ...
            'Position',[0.83 0.89 0.14 0.11], ...
            'BorderType','none', ...
            'BackgroundColor',[0.05 0.05 0.05]);

        axIcon = axes('Parent', iconPanel, ...
            'Units','normalized', ...
            'Position',[0 0 1 1], ...
            'Visible','off', ...
            'Color',[0.05 0.05 0.05], ...
            'XColor',[0.05 0.05 0.05], ...
            'YColor',[0.05 0.05 0.05]);

        h = image('Parent', axIcon, 'CData', imgPad);
        set(axIcon,'YDir','reverse');
        xlim(axIcon,[0.5 size(imgPad,2)+0.5]);
        ylim(axIcon,[0.5 size(imgPad,1)+0.5]);

        alphaPad = double(alphaPad);
        if max(alphaPad(:)) > 1
            alphaPad = alphaPad ./ 255;
        end
        set(h, 'AlphaData', alphaPad);

        axis(axIcon, 'image');
        axis(axIcon, 'off');

    catch ME
        disp(['Icon load failed: ' ME.message]);
    end
end
function [data, pickedName] = studio_force_internal_I_field(data, sourceFile, fallbackTR)

    pickedName = '';

    if nargin < 3 || isempty(fallbackTR) || ~isfinite(fallbackTR) || fallbackTR <= 0
        fallbackTR = 0.32;
    end

    % Already in correct internal format
    if isstruct(data) && isfield(data,'I') && isnumeric(data.I) && ~isempty(data.I)
        return;
    end

    % Case 1: loader returned raw numeric array directly
    if isnumeric(data) && ~isempty(data)
        rawI = data;
        data = struct();
        data.I = single(rawI);
        data.TR = fallbackTR;
        data.nVols = size(rawI, ndims(rawI));
        data.TotalTimeSec = data.nVols * data.TR;
        pickedName = '<numeric array returned by loader>';
        return;
    end

    % Case 2: loader returned struct, but main field is not called I
    if isstruct(data)
        [rawI, pickedName] = studio_find_best_numeric_volume(data);

        if isempty(rawI)
            error(['Could not find a valid fUSI volume in loaded MAT struct: ' sourceFile ...
                   '. Expected a 3D or 4D numeric array.']);
        end

        data.I = single(rawI);

        if ~isfield(data,'TR') || isempty(data.TR) || ~isfinite(data.TR) || data.TR <= 0
            data.TR = fallbackTR;
        end

        if ~isfield(data,'nVols') || isempty(data.nVols) || ~isfinite(data.nVols)
            data.nVols = size(data.I, ndims(data.I));
        end

        if ~isfield(data,'TotalTimeSec') || isempty(data.TotalTimeSec) || ~isfinite(data.TotalTimeSec)
            data.TotalTimeSec = data.nVols * data.TR;
        end

        return;
    end

    error('Loaded dataset is neither a struct nor a numeric array.');
end

function [bestData, bestName] = studio_find_best_numeric_volume(S)

    bestData = [];
    bestName = '';

    candidates = struct('name',{},'score',{},'value',{});
    candidates = studio_collect_volume_candidates(S, '', 0, candidates);

    if isempty(candidates)
        return;
    end

    scores = zeros(1, numel(candidates));
    for k = 1:numel(candidates)
        scores(k) = candidates(k).score;
    end

    [~, idx] = max(scores);
    bestData = candidates(idx).value;
    bestName = candidates(idx).name;
end

function candidates = studio_collect_volume_candidates(v, pathStr, depth, candidates)

    if depth > 2
        return;
    end

    if isnumeric(v) && ~isempty(v)
        sc = studio_score_volume_candidate(v, pathStr);
        if isfinite(sc)
            c.name = pathStr;
            c.score = sc;
            c.value = v;
            candidates(end+1) = c; %#ok<AGROW>
        end
        return;
    end

    if iscell(v) && numel(v) == 1
        candidates = studio_collect_volume_candidates(v{1}, [pathStr '{1}'], depth+1, candidates);
        return;
    end

    if isstruct(v) && isscalar(v)
        fn = fieldnames(v);
        for ii = 1:numel(fn)
            f = fn{ii};
            if isempty(pathStr)
                nextPath = f;
            else
                nextPath = [pathStr '.' f];
            end
            candidates = studio_collect_volume_candidates(v.(f), nextPath, depth+1, candidates);
        end
    end
end

function sc = studio_score_volume_candidate(v, nameStr)

    sc = -Inf;

    if isempty(v) || islogical(v) || isvector(v) || isscalar(v)
        return;
    end

    nd = ndims(v);
    sz = size(v);

    % fUSI data should normally be Y x X x T or Y x X x Z x T
    if nd < 3
        return;
    end

    sc = 0;

    % Prefer 3D/4D arrays
    if nd == 3
        sc = sc + 60;
    elseif nd >= 4
        sc = sc + 80;
    end

    % Prefer actual time dimension
    if sz(end) > 1
        sc = sc + 20;
    end

    % Prefer realistic image size
    if numel(sz) >= 2 && sz(1) >= 16 && sz(2) >= 16
        sc = sc + 10;
    end

    % Prefer common data types
    if isa(v,'single') || isa(v,'double') || isa(v,'uint16') || isa(v,'int16')
        sc = sc + 5;
    end

    lname = lower(nameStr);

    goodKeys = {'i','data','img','image','stack','movie','frames','volume','vol','fus','doppler','power'};
    badKeys  = {'tr','dt','time','mask','atlas','roi','label','coord','x','y','z','mean','median','std','var'};

    for k = 1:numel(goodKeys)
        if ~isempty(strfind(lname, goodKeys{k})) %#ok<STREMP>
            sc = sc + 12;
        end
    end

    for k = 1:numel(badKeys)
        if ~isempty(strfind(lname, badKeys{k})) %#ok<STREMP>
            sc = sc - 15;
        end
    end

    % Penalize likely masks / binary arrays
    try
        samp = double(v(1:min(numel(v),5000)));
        samp = samp(isfinite(samp));
        if ~isempty(samp)
            u = unique(samp(:));
            if numel(u) <= 3
                sc = sc - 25;
            end
        end
    catch
    end
end
%% =========================================================
%  CLOSE HANDLER
% =========================================================
function onCloseStudio(~,~)
    try
        delete(fig);
    catch
    end
end
function c = studioJavaColor(r,g,b)
% studioJavaColor
% Safe Java RGB color helper for MATLAB 2017b/2023b.
% Accepts 0..1 or 0..255 RGB and always calls Java int constructor.

if nargin == 1
    rgb = double(r);
else
    rgb = double([r g b]);
end

if numel(rgb) ~= 3
    rgb = [0 0 0];
end

rgb(~isfinite(rgb)) = 0;

if max(rgb) <= 1
    rgb = round(rgb * 255);
else
    rgb = round(rgb);
end

rgb = max(0, min(255, rgb));

c = javaObjectEDT('java.awt.Color', ...
    int32(rgb(1)), int32(rgb(2)), int32(rgb(3)));
end
end