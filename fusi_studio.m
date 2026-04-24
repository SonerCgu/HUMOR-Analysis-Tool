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
jLog.setBackground(java.awt.Color(0,0,0));
jLog.setForeground(java.awt.Color(0.60,0.85,1.00));
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
    {'Temporal Smoothing/Subsampling','Filtering','PCA','Despike'}, ...
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

folders = {qcFolder, preFolder, visFolder};
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
if isempty(studio.meta) || ~isstruct(studio.meta)
    studio.meta = struct();
end

studio.meta.exportPath = datasetFolder;
studio.meta.savePath   = datasetFolder;
studio.meta.outPath    = datasetFolder;
studio.meta.loadedPath = path;
studio.meta.loadedFile = fullInputFile;
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
    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    ch = questdlg( ...
        'Imregdemons: use MEDIAN (robust) or MEAN?', ...
        'Imregdemons', ...
        'Median','Mean','Cancel','Median');

    if isempty(ch) || strcmpi(ch,'Cancel')
        addLog('Imregdemons preprocessing cancelled.');
        return;
    end

    blockMethod = lower(ch);

    answ = inputdlg({'Enter subsampling factor (nsub >= 2):'}, ...
        'Imregdemons', 1, {'50'});

    if isempty(answ)
        addLog('Imregdemons preprocessing cancelled.');
        return;
    end

    nsub = str2double(answ{1});
    if isnan(nsub) || nsub < 2
        errordlg('Invalid nsub (>= 2).');
        return;
    end

    % Cleanup any old lingering QC / preprocessing windows first
    closeLingeringQCFigures();

    setProgramStatus(false);
    addLog(sprintf('Running Imregdemons preprocessing (%s, nsub = %d)...', ...
        upper(blockMethod), nsub));
    drawnow;

    data = getActiveData();

    % Track figure state so any figures created by gabriel_preprocess
    % can be closed afterwards
    figsBefore = findall(0, 'Type', 'figure');

    opts = struct();
    opts.nsub = nsub;
    opts.blockMethod = blockMethod;
    opts.regSmooth = 1.3;
    opts.saveQC = true;
    opts.showQC = false;
    opts.qcDir = fullfile(studio.exportPath, 'Preprocessing', ...
        sprintf('imregdemons_QC_%s', blockMethod));

    try
        out = gabriel_preprocess(data.I, data.TR, opts);

        % Close any new figures created during preprocessing
        drawnow;
        closeNewFigures(figsBefore);
        closeLingeringQCFigures();

        newData = data;
        newData.I = out.I;

        if isfield(out,'blockDur') && ~isempty(out.blockDur)
            newData.TR = out.blockDur;
        end
        if isfield(out,'nVols') && ~isempty(out.nVols)
            newData.nVols = out.nVols;
        end
        if isfield(out,'totalTime') && ~isempty(out.totalTime)
            newData.totalTime = out.totalTime;
        end
        if isfield(out,'method') && ~isempty(out.method)
            newData.preprocessing = out.method;
        else
            newData.preprocessing = sprintf('Imregdemons (%s, nsub=%d)', blockMethod, nsub);
        end

        ts = datestr(now,'yyyymmdd_HHMMSS');
        baseStem = getCurrentNamingStem(studio);
        fullName = sprintf('%s_imregdemons_%s_nsub%d_%s', ...
            baseStem, blockMethod, nsub, ts);

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

        addLog(['Imregdemons preprocessing -> ' fullName]);

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

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        errordlg('Active dataset has no data.I to process.');
        return;
    end

    modeChoice = questdlg( ...
        ['Choose operation:' newline newline ...
         ' - Sliding temporal smoothing = moving average with same number of volumes' newline ...
         ' - Block averaging / subsampling = non-overlapping blocks, fewer volumes, larger TR'], ...
        'Temporal Smoothing/Subsampling', ...
        'Sliding temporal smoothing', ...
        'Block averaging / subsampling', ...
        'Cancel', ...
        'Sliding temporal smoothing');

    if isempty(modeChoice) || strcmpi(modeChoice,'Cancel')
        addLog('Temporal smoothing/subsampling cancelled.');
        return;
    end

    defaultBlockSec = max(data.TR * 50, data.TR);
    defaultBlockSecStr = num2str(defaultBlockSec,'%.6g');

    setProgramStatus(false);
    drawnow;

    try
        opts = struct();
        opts.chunkVoxels = 50000;
        opts.logFcn = [];

        newData = data;
        ts = datestr(now,'yyyymmdd_HHMMSS');
        baseStem = getCurrentNamingStem(studio);

        if strcmpi(modeChoice,'Sliding temporal smoothing')

            answ = inputdlg( ...
                {'Temporal smoothing window (seconds):'}, ...
                'Temporal Smoothing/Subsampling', ...
                1, {'60'});

            if isempty(answ)
                addLog('Temporal smoothing cancelled.');
                setProgramStatus(true);
                return;
            end

            winSec = str2double(answ{1});
            if isnan(winSec) || ~isfinite(winSec) || winSec <= 0
                errordlg('Invalid smoothing window (seconds). Must be > 0.');
                setProgramStatus(true);
                return;
            end

            addLog(sprintf('Running temporal smoothing (window = %.6g s, TR = %.6g s)...', ...
                winSec, data.TR));

            opts.mode = 'sliding';

            [Iout, stats] = temporalsmoothing(data.I, data.TR, winSec, opts);

            newData.I = single(Iout);
            newData.temporalSmoothing = stats;
            newData.preprocessing = sprintf('Temporal smoothing (moving average, %.6g s)', stats.winSec);

            % avoid stale PSC/bg from an older dataset version
            if isfield(newData,'PSC'), newData.PSC = []; end
            if isfield(newData,'bg'),  newData.bg  = []; end

            secTag = num2str(winSec,'%.6g');
            secTag = strrep(secTag,'.','p');
            secTag = strrep(secTag,'-','m');

            fullName = sprintf('%s_temporalSmooth_%ss_%s', baseStem, secTag, ts);

            addLog(sprintf('Temporal smoothing complete: %.6g s (%d vols), runtime %.2f s', ...
                stats.winSec, stats.winVol, stats.runtimeSec));

        else
            methodChoice = questdlg( ...
                'Use MEAN or MEDIAN for each non-overlapping block?', ...
                'Block averaging / subsampling', ...
                'Mean','Median','Cancel','Mean');

            if isempty(methodChoice) || strcmpi(methodChoice,'Cancel')
                addLog('Subsampling cancelled.');
                setProgramStatus(true);
                return;
            end

            defaultNsub = max(2, round(50));

answ = inputdlg( ...
    {'Subsampling factor n (frames per block, n >= 2):'}, ...
    'Temporal Smoothing/Subsampling', ...
    1, {num2str(defaultNsub)});

if isempty(answ)
    addLog('Subsampling cancelled.');
    setProgramStatus(true);
    return;
end

nsub = str2double(answ{1});
if isnan(nsub) || ~isfinite(nsub) || nsub < 2
    errordlg('Invalid n. It must be >= 2.');
    setProgramStatus(true);
    return;
end
nsub = round(nsub);

winSec = nsub * data.TR;

opts.mode = 'block';
opts.blockMethod = lower(strtrim(methodChoice));

addLog(sprintf('Running subsampling (%s, n = %d frames, block = %.6g s, TR = %.6g s)...', ...
    upper(opts.blockMethod), nsub, winSec, data.TR));

[Iout, stats] = temporalsmoothing(data.I, data.TR, winSec, opts);

            newData.I = single(Iout);
            newData.temporalSmoothing = stats;
            newData.subsampling = stats;
            newData.TR = stats.TRout;
            newData.nVols = stats.nVolsOut;
            newData.totalTime = stats.totalTimeSec;
            newData.TotalTimeSec = stats.totalTimeSec;
          newData.preprocessing = sprintf('Subsampling (%s, n=%d)', ...
    upper(stats.blockMethod), stats.winVol);

            % avoid stale PSC/bg from an older dataset version
            if isfield(newData,'PSC'), newData.PSC = []; end
            if isfield(newData,'bg'),  newData.bg  = []; end

            fullName = sprintf('%s_subsample_%s_nsub%d_%s', ...
                baseStem, lower(stats.blockMethod), stats.winVol, ts);

           addLog(sprintf(['Subsampling complete: %s, n=%d frames/block (%.6g s), ' ...
                'TR %.6g -> %.6g s, nVols %d -> %d, runtime %.2f s'], ...
    upper(stats.blockMethod), stats.winVol, stats.winSec, ...
    stats.TR, stats.TRout, stats.nVolsIn, stats.nVolsOut, stats.runtimeSec));
        end

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

        addLog(['Saved dataset -> ' fullName]);

    catch ME
        addLog(['TEMPORAL / SUBSAMPLING ERROR: ' ME.message]);
        errordlg(ME.message,'Temporal Smoothing/Subsampling failed');
    end

    setProgramStatus(true);
end

%% =========================================================
%  PCA
% =========================================================
function pcaCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog('Running PCA denoising... (select PCs to remove)');
    setProgramStatus(false);
    drawnow;

    ts = datestr(now,'yyyymmdd_HHMMSS');

    opts = struct();
    opts.nCompMax = 50;
    opts.maxDisplayPoints = 2000;
    opts.chunkT = 250;
    opts.centerMode = 'voxel';
    opts.onApply = @(sel) pca_onApply(sel);
    opts.onCancel = @() pca_onCancel();

    try
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

    catch ME
        addLog(['PCA ERROR: ' ME.message]);
        errordlg(ME.message,'PCA Failure');
    end

    setProgramStatus(true);

    function pca_onApply(sel)
        if isempty(sel)
            addLog('PCA applied: no components selected. Please wait...');
        else
            sel = unique(sel(:)');
            addLog(['PCA applied, dropping PCs: ' sprintf('%d ', sel) ' - please wait...']);
        end
        drawnow;
    end

    function pca_onCancel()
        addLog('PCA cancelled.');
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
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    choice = questdlg('Select filter type:', ...
                      'Filtering', ...
                      'Low-pass','High-pass','Band-pass','Low-pass');

    if isempty(choice)
        return;
    end

    opts = struct();

    switch choice
        case 'Low-pass'
            opts.type = 'low';
            answer = inputdlg({'Low-pass cutoff (Hz):','Order (1-6):'}, ...
                              'Low-pass',1,{'0.2','4'});
            if isempty(answer)
                return;
            end
            opts.FcHigh = str2double(answer{1});
            opts.order = str2double(answer{2});
            opts.FcLow = 0;

        case 'High-pass'
            opts.type = 'high';
            answer = inputdlg({'High-pass cutoff (Hz):','Order (1-6):'}, ...
                              'High-pass',1,{'0.01','4'});
            if isempty(answer)
                return;
            end
            opts.FcLow = str2double(answer{1});
            opts.order = str2double(answer{2});
            opts.FcHigh = 0;

        case 'Band-pass'
            opts.type = 'band';
            answer = inputdlg({'Low cutoff (Hz):','High cutoff (Hz):','Order (1-6):'}, ...
                              'Band-pass',1,{'0.01','0.2','4'});
            if isempty(answer)
                return;
            end
            opts.FcLow = str2double(answer{1});
            opts.FcHigh = str2double(answer{2});
            opts.order = str2double(answer{3});
    end

    trimAns = inputdlg({'Trim start (sec):','Trim end (sec):'}, ...
                       'Trimming',1,{'0','0'});
    if isempty(trimAns)
        return;
    end

    opts.trimStart = str2double(trimAns{1});
    opts.trimEnd = str2double(trimAns{2});

    addLog('Running Butterworth filtering...');
    setProgramStatus(false);
    drawnow;

    try
        [I_filt, stats] = filtering(data.I, data.TR, studio.exportPath, opts);

        newData = data;
        newData.I = single(I_filt);
        newData.filtering = stats;

        ts = datestr(now,'yyyymmdd_HHMMSS');
        baseStem = getCurrentNamingStem(studio);
filterTag = makeFilterTag(opts);
fullName = sprintf('%s_%s_%s', baseStem, filterTag, ts);;
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

        addLog(['Filtering complete -> ' fullName]);
        if isfield(stats,'qcFolder')
            addLog(['QC saved -> ' stats.qcFolder]);
        end

    catch ME
        addLog(['FILTER ERROR: ' ME.message]);
        errordlg(ME.message,'Filtering Failure');
    end

    setProgramStatus(true);
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
        Transf = coreg(studio);

        if isempty(Transf)
            addLog('Coregistration cancelled.');
            setProgramStatus(true);
            return;
        end

        studio.atlasTransform = Transf;

        if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
            studio.atlasTransformFile = fullfile(studio.loadedPath,'Transformation.mat');
        else
            studio.atlasTransformFile = 'Transformation.mat';
        end

        guidata(fig, studio);

        addLog('Atlas coregistration completed.');
        addLog('Transformation stored in studio.atlasTransform');
        addLog(['Transformation file: ' studio.atlasTransformFile]);

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

    if isempty(studio.atlasTransform)
        warndlg('Run Registration to Atlas first.');
        addLog('Segmentation cancelled: no atlas transform found.');
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
        return;
    end

    data = getActiveData();
    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        addLog('[FC] Active dataset has no .I.');
        return;
    end

    saveRoot = studio.exportPath;
    if isempty(saveRoot) || ~exist(saveRoot,'dir')
        saveRoot = pwd;
    end

    tag = ['fc_' datestr(now,'yyyymmdd_HHMMSS')];

    opts = struct();
    opts.datasetName = studio.activeDataset;

    if isfield(data,'mask') && ~isempty(data.mask)
        opts.mask = data.mask;
    elseif isfield(studio,'mask') && ~isempty(studio.mask)
        opts.mask = studio.mask;
    end

    if isfield(data,'anat') && ~isempty(data.anat)
        opts.anat = data.anat;
    elseif isfield(studio,'anatomicalReference') && ~isempty(studio.anatomicalReference)
        opts.anat = studio.anatomicalReference;
    elseif isfield(studio,'anatomicalReferenceRaw') && ~isempty(studio.anatomicalReferenceRaw)
        opts.anat = studio.anatomicalReferenceRaw;
    end

    opts.logFcn = @(m) addLog(['[FC] ' m]);

    try
        fcFig = FunctionalConnectivity(data, saveRoot, tag, opts);

        if ~isempty(fcFig) && ishandle(fcFig)
            addlistener(fcFig,'ObjectBeingDestroyed', @(~,~) addLog('[FC] Closed.'));
        end

        addLog('[FC] GUI launched.');
    catch ME
        addLog(['FC ERROR: ' ME.message]);
        errordlg(ME.message,'Functional Connectivity');
    end
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

        if isfield(out,'anatomical_reference_raw') && ~isempty(out.anatomical_reference_raw)
            studio.anatomicalReferenceRaw = out.anatomical_reference_raw;
        end
        if isfield(out,'anatomical_reference') && ~isempty(out.anatomical_reference)
            studio.anatomicalReference = out.anatomical_reference;
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

end