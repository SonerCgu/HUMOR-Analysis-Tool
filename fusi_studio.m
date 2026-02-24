function fusi_studio
clc;

%% =========================================================
%  SECTION A — INTERNAL STATE & GUI CONSTRUCTION
% =========================================================
studio = struct();
studio.datasets = struct();      % raw + preproc + PSC versions
studio.activeDataset = '';       % dataset key
studio.meta  = [];
studio.isLoaded = false;
studio.loadedFile = '';
studio.loadedPath = '';
studio.exportPath = '';
studio.atlasTransform = [];
studio.atlasTransformFile = '';
studio.allButtons = {};          % proper handle container
studio.figure = [];              % store figure handle

% Optional shared mask/underlay refs (set by Mask Editor)
studio.mask = [];
studio.maskIsInclude = true;
studio.brainMask = [];
studio.brainImageFile = '';
studio.anatomicalReferenceRaw = [];
studio.anatomicalReference = [];

% Pipeline state tracking
studio.pipeline = struct( ...
    'loadDone', false, ...
    'qcDone', false, ...
    'preprocDone', false, ...
    'pscDone', false, ...
    'visualDone', false);

%% =========================================================
%  FIGURE WINDOW
% =========================================================
fig = figure('Name','HUMoR Analysis Tool', ...
    'Color',[0.05 0.05 0.05], ...
    'Position',[300 200 1900 1080], ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'CloseRequestFcn',@onCloseStudio);

studio.figure = fig;
guidata(fig, studio);

%% =========================================================
%  TITLE
% =========================================================
uicontrol(fig,'Style','text', ...
    'String','HUMoR Analysis Tool', ...
    'Units','normalized', ...
    'Position',[0.52 0.95 0.35 0.04], ...
    'FontSize',26, ...
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
    'Position',[0.03 0.10 leftWidth 0.83], ...
    'BackgroundColor',[0.07 0.07 0.07], ...
    'BorderType','none');

%% =========================================================
%  LOG PANEL
% =========================================================
logPanel = uipanel(fig, ...
    'Title','Studio Log', ...
    'Units','normalized', ...
    'Position',[0.50 0.19 0.47 0.70], ...
    'BackgroundColor',[0.07 0.07 0.07], ...
    'ForegroundColor','w', ...
    'FontSize',14, ...
    'FontWeight','bold');

activeDatasetText = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.50 0.91 0.47 0.04], ...
    'FontSize',14, ...
    'FontWeight','bold', ...
    'ForegroundColor',[0.3 0.9 0.3], ...
    'BackgroundColor',[0.05 0.05 0.05], ...
    'HorizontalAlignment','left', ...
    'String','ACTIVE DATASET: none');

studio = guidata(fig);
studio.activeDatasetText = activeDatasetText;
guidata(fig,studio);

logBox = uicontrol(logPanel,'Style','listbox', ...
    'Units','normalized', ...
    'Position',[0.02 0.02 0.96 0.94], ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',[0.6 0.85 1], ...
    'FontName','Courier New', ...
    'FontSize',11);

studio = guidata(fig);
studio.logBox = logBox;
guidata(fig, studio);

addLog('fUSI Studio initialized.');

%% =========================================================
%  SECTION DEFINITIONS
% =========================================================
sectionHeights = [0.11 0.11 0.20 0.11 0.12 0.10 0.12];

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
    {'Frame Rejection','Subsampling','Scrubbing','Motor'}, ...
    {'Will be Removed (was PSC Computation)','Filtering', 'PCA', 'Despike'}, ...
    {'Time-Course Viewer','SCM','Video & SCM Mask', 'Mask Editor'}, ...
    {'Registration to Atlas'}, ...
    {'Functional connectivity','Group analysis'}};

%% =========================================================
%  SECTION RENDERING LOOP
% =========================================================
gapBetweenSections = 0.016;
y = 0.98;

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
        'HighlightColor',[1 1 1], ...
        'ShadowColor',[1 1 1]);

    drawButtons(panel, buttons{i}, i);

    y = y - gapBetweenSections;
end

%% =========================================================
%  STATUS BAR
% =========================================================
statusPanel = uipanel(fig, ...
    'Units','normalized', ...
    'Position',[0.03 0.05 leftWidth 0.055], ...
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
guidata(fig,studio);

setProgramStatus(false);

%% =========================================================
%  BOTTOM BUTTONS
% =========================================================
btnY = 0.05;
btnH = 0.055;

uicontrol(fig,'Style','pushbutton', ...
    'String','HELP', ...
    'Units','normalized', ...
    'Position',[0.50 btnY 0.10 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.30 0.50 0.95], ...
    'ForegroundColor','w', ...
    'Callback',@helpCallback);

uicontrol(fig,'Style','pushbutton', ...
    'String','EXPORT STUDIO LOG', ...
    'Units','normalized', ...
    'Position',[0.62 btnY 0.14 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.15 0.65 0.55], ...
    'ForegroundColor','w', ...
    'Callback',@exportSessionCallback);

uicontrol(fig,'Style','pushbutton', ...
    'String','CLOSE', ...
    'Units','normalized', ...
    'Position',[0.79 btnY 0.10 btnH], ...
    'FontWeight','bold', ...
    'FontSize',13, ...
    'BackgroundColor',[0.85 0.25 0.25], ...
    'ForegroundColor','w', ...
    'Callback',@(s,e) close(fig));

%% =========================================================
%  FOOTER LABEL (BOTTOM-RIGHT)
% =========================================================
studio = guidata(fig);

footerText = uicontrol(fig,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.50 0.008 0.47 0.028], ...
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
%  BUTTON DRAWING FUNCTION WITH DROPDOWN
% =========================================================
function drawButtons(parent, btns, sectionIndex)

    studio = guidata(fig);

    % Normal two-column layout EXCEPT Section 1
    n = length(btns);
    cols = 2;
    btnWidth  = 0.40;
    btnHeight = 0.40;
    xGap = 0.10;
    yStart = 0.55;
    yGap = 0.48;

    for k = 1:n
        label = btns{k};

        % -------- SPECIAL: SECTION 1 (Load + Dropdown) --------
        if sectionIndex == 1 && strcmp(label,'Load fUSI Data')

            xpos = 0.08;
            ypos = yStart;

            loadBtn = uicontrol(parent, ...
                'Style','pushbutton', ...
                'String','Load fUSI Data', ...
                'Units','normalized', ...
                'Position',[xpos ypos btnWidth btnHeight], ...
                'FontWeight','bold', ...
                'FontSize',14, ...
                'ForegroundColor','w', ...
                'Enable','on', ...
                'BackgroundColor',[0.35 0.35 0.35], ...
                'Callback',@loadDataCallback);

            studio.allButtons{end+1} = loadBtn;

            % -------- DROPDOWN --------
            ddX = xpos + btnWidth + 0.06;

            uicontrol(parent, ...
                'Style','popupmenu', ...
                'String',{'<none>'}, ...
                'Units','normalized', ...
                'Position',[ddX ypos btnWidth btnHeight], ...
                'BackgroundColor',[0.2 0.2 0.2], ...
                'ForegroundColor','w', ...
                'FontSize',13, ...
                'Callback',@datasetDropdownCallback, ...
                'Tag','datasetDropdown', ...
                'UserData',{{}});

            guidata(fig, studio);
            return;
        end

        % -------- ALL OTHER BUTTONS --------
        r = floor((k-1)/cols);
        c = mod(k-1, cols);

        xpos = 0.08 + c*(btnWidth + xGap);
        ypos = yStart - r*yGap;

        callback = @dummyNotImplemented;

        % SAFE label key (case/space stable)
        labelKey = lower(regexprep(strtrim(label),'\s+',' '));

        switch labelKey
            case 'full qc',                 callback = @runFullQCCallback;
            case 'specific qc',             callback = @runSpecificQCCallback;
            case 'frame rejection',         callback = @frameRateCallback;
            case 'subsampling',             callback = @gabrielCallback;
            case 'scrubbing',               callback = @scrubbingCallback;
            case 'motor',                   callback = @stepMotorCallback;

            % keep PSC computation (deprecated but accessible)
            case 'will be removed (was psc computation)', callback = @computePSCCallback;

            case 'filtering',               callback = @filteringCallback;
            case 'pca',                     callback = @pcaCallback;
            case 'despike',                 callback = @despikeCallback;

            case 'time-course viewer',      callback = @liveViewerCallback;
            case 'scm',                     callback = @scmCallback;

            % IMPORTANT FIX: this label must match after lower()
            case 'video & scm mask',        callback = @videoGUICallback;

            case 'mask editor',             callback = @maskEditorCallback;

            case 'registration to atlas',   callback = @coregCallback;
            case 'functional connectivity', callback = @functionalConnectivityCallback;
            case 'group analysis',          callback = @groupAnalysisCallback;
        end

        btn = uicontrol(parent, ...
            'Style','pushbutton', ...
            'String',label, ...
            'Units','normalized', ...
            'Position',[xpos ypos btnWidth btnHeight], ...
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
%  SECTION B — CORE CALLBACKS
% =========================================================

%% =========================================================
%  LOAD DATA CALLBACK
% =========================================================
function loadDataCallback(~,~)

    studio = guidata(fig);

    startPath = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
    if ~exist(startPath,'dir'), startPath = pwd; end

    [file,path] = uigetfile({'*.mat;*.nii','fUSI Data'}, ...
        'Select fUSI dataset',startPath);

    if isequal(file,0)
        addLog('Load cancelled.');
        return;
    end

    addLog('Loading dataset...');
    setProgramStatus(false); drawnow;

    % RESET INTERNAL STATE
    studio.datasets = struct();
    studio.activeDataset = '';
    studio.meta = [];
    studio.isLoaded = false;
    studio.loadedFile = '';
    studio.loadedPath = '';
    studio.exportPath = '';
    studio.atlasTransform = [];
    studio.atlasTransformFile = '';
    studio.pipeline = struct( ...
        'loadDone', false, ...
        'qcDone', false, ...
        'preprocDone', false, ...
        'pscDone', false, ...
        'visualDone', false);

    guidata(fig,studio);

    fallbackTR = 0.32;

    try
        [data, meta] = loadFUSIData(fullfile(path,file), fallbackTR);

        % AUTO EXPORT FOLDER MIRROR
        rawRoot    = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
        exportRoot = 'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData';

        if ~exist(exportRoot,'dir')
            mkdir(exportRoot);
        end

        [~,datasetName,~] = fileparts(file);
        relPath = strrep(path, rawRoot, '');
        if startsWith(relPath, filesep)
            relPath = relPath(2:end);
        end

        datasetFolder = fullfile(exportRoot, relPath, datasetName);
        if ~exist(datasetFolder,'dir'), mkdir(datasetFolder); end

        % Subfolders
        qcFolder  = fullfile(datasetFolder,'QC');
        pngFolder = fullfile(qcFolder,'png');
        matFolder = fullfile(qcFolder,'mat');
        preFolder = fullfile(datasetFolder,'Preprocessing');
        pscFolder = fullfile(datasetFolder,'PSC');
        visFolder = fullfile(datasetFolder,'Visualization');

        folders = {qcFolder,pngFolder,matFolder,preFolder,pscFolder,visFolder};
        for kk = 1:numel(folders)
            if ~exist(folders{kk},'dir'), mkdir(folders{kk}); end
        end

        % STORE RAW DATASET
        studio = guidata(fig);

        studio.datasets.raw = data;
        studio.activeDataset = 'raw';
        studio.meta = meta;
        studio.isLoaded = true;
        studio.loadedFile = file;
        studio.loadedPath = path;
        studio.exportPath = datasetFolder;
        studio.pipeline.loadDone = true;

        % REGISTER EXISTING PSC + PREPROCESSING FILES (LAZY LOAD)
        pscFiles = dir(fullfile(datasetFolder,'PSC','*.mat'));
        for kk = 1:numel(pscFiles)
            fullName = erase(pscFiles(kk).name,'.mat');
            safeKey  = makeSafeKey(fullName, studio.datasets);
            studio.datasets.(safeKey) = struct( ...
                'lazyFile', fullfile(pscFiles(kk).folder, pscFiles(kk).name), ...
                'isLazy', true, ...
                'displayNameFull', fullName);
        end

        preFiles = dir(fullfile(datasetFolder,'Preprocessing','*.mat'));
        for kk = 1:numel(preFiles)
            fullName = erase(preFiles(kk).name,'.mat');
            safeKey  = makeSafeKey(fullName, studio.datasets);

            studio.datasets.(safeKey) = struct( ...
                'lazyFile', fullfile(preFiles(kk).folder, preFiles(kk).name), ...
                'isLazy', true, ...
                'displayNameFull', fullName);
        end

        guidata(fig, studio);

        % ENABLE ALL BUTTONS
        unlockAllButtons();

        % REFRESH DROPDOWN
        refreshDatasetDropdown();

        % LOG METADATA
        dims = size(data.I);
        nz = 1;
        try
            if isfield(meta,'rawMetadata') && isfield(meta.rawMetadata,'imageDim')
                if numel(meta.rawMetadata.imageDim) == 3
                    nz = meta.rawMetadata.imageDim(3);
                end
            end
        catch
        end
        probeType = iff(nz>1,'Matrix (3D) Probe','2D Probe');

        addLog('---------------------------------------');
        addLog('DATASET LOADED SUCCESSFULLY');
        addLog(['Dataset folder: ' datasetFolder]);
        addLog(sprintf('Dimensions: %d x %d x %d', dims(1), dims(2), nz));
        addLog(sprintf('Volumes: %d', data.nVols));
        addLog(['Probe: ' probeType]);
        addLog(sprintf('TR: %.3f sec', data.TR));
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
    setProgramStatus(false); drawnow;

    opts = struct();
    opts.frequency   = true;
    opts.spatial     = true;
    opts.temporal    = true;
    opts.motion      = true;
    opts.stability   = true;
    opts.framerate   = true;
    opts.pca         = true;

    opts.burst       = true;
    opts.cnr         = true;
    opts.commonmode  = true;

    opts.datasetTag = studio.activeDataset;
    opts.useTimestampSubfolder = false;

    data = getActiveData();

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);

        addLog(['FULL QC completed. Saved under: QC\' opts.datasetTag]);
        studio.pipeline.qcDone = true;
        guidata(fig,studio);

    catch ME
        addLog(['QC ERROR: ' ME.message]);
        errordlg(ME.message,'QC Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  SPECIFIC QC
% =========================================================
function runSpecificQCCallback(~,~)

    studio = guidata(fig);
    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    list = { ...
        'Frequency QC', ...
        'Spatial QC (Mean/CV/tSNR)', ...
        'Temporal QC (GS/rGS/DVARS/spikes)', ...
        'Motion QC (COM drift)', ...
        'Stability QC (intensity distribution + rejection)', ...
        'Frame-rate QC (global rejection/stability)', ...
        'PCA QC', ...
        'Burst Error QC', ...
        'CNR QC', ...
        'Common-Mode QC'};

    choice = listdlg( ...
        'PromptString','Select QC modules:', ...
        'SelectionMode','multiple', ...
        'ListString',list, ...
        'ListSize',[460 320]);

    if isempty(choice)
        addLog('QC selection cancelled.');
        return;
    end

    opts = struct();
    opts.frequency   = ismember(1,choice);
    opts.spatial     = ismember(2,choice);
    opts.temporal    = ismember(3,choice);
    opts.motion      = ismember(4,choice);
    opts.stability   = ismember(5,choice);
    opts.framerate   = ismember(6,choice);
    opts.pca         = ismember(7,choice);

    opts.burst       = ismember(8,choice);
    opts.cnr         = ismember(9,choice);
    opts.commonmode  = ismember(10,choice);

    opts.datasetTag = studio.activeDataset;
    opts.useTimestampSubfolder = false;

    addLog('Running selected QC...');
    setProgramStatus(false); drawnow;

    data = getActiveData();

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);

        addLog(['Selected QC completed. Saved under: QC\' opts.datasetTag]);
        studio.pipeline.qcDone = true;
        guidata(fig,studio);

    catch ME
        addLog(['QC ERROR: ' ME.message]);
        errordlg(ME.message,'QC Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  GABRIEL PREPROCESSING
% =========================================================
function gabrielCallback(~,~)

    studio = guidata(fig);
    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    answ = inputdlg({'Enter subsampling factor (nsub >= 2):'}, ...
        'Gabriel Preprocessing', 1, {'50'});
    if isempty(answ)
        addLog('Gabriel preprocessing cancelled.');
        return;
    end

    nsub = str2double(answ{1});
    if isnan(nsub) || nsub < 2
        errordlg('Invalid nsub (>=2).'); return;
    end

    setProgramStatus(false);
    addLog(sprintf('Running Gabriel preprocessing (nsub = %d)...', nsub));
    drawnow;

    data = getActiveData();

    opts = struct();
    opts.nsub = nsub;
    opts.regSmooth = 1.3;
    opts.saveQC = true;
    opts.showQC = false;
    opts.qcDir = fullfile(studio.exportPath,'Preprocessing','gabriel_QC');

    try
        out = gabriel_preprocess(data.I, data.TR, opts);

        newData = data;
        newData.I = out.I;
        newData.TR = out.blockDur;
        if isfield(out,'nVols'), newData.nVols = out.nVols; end
        if isfield(out,'totalTime'), newData.totalTime = out.totalTime; end
        if isfield(out,'method'), newData.preprocessing = out.method; end

        ts = datestr(now,'yyyymmdd_HHMMSS');
        baseName = studio.activeDataset;
        fullName = [baseName '_gabriel_' ts];

        keyName = makeSafeKey(fullName, studio.datasets);
        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Gabriel preprocessing -> ' fullName]);

    catch ME
        addLog(['GABRIEL ERROR: ' ME.message]);
        errordlg(ME.message,'Gabriel Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  FRAME-RATE REJECTION (QC + VALIDATION QC)
% =========================================================
function frameRateCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog('Running Frame-rate QC (ORIGINAL)...');
    setProgramStatus(false);
    drawnow;

    try
        QC_before = frameRateQC(data.I, data.TR, 'ORIGINAL', false);
        addLog(sprintf('Original rejected: %.2f %%', QC_before.rejPct));

        qcFolder = fullfile(studio.exportPath,'QC','png');
        if ~exist(qcFolder,'dir'), mkdir(qcFolder); end

        ts = datestr(now,'yyyymmdd_HHMMSS');

        try
            saveas(QC_before.figIntensity, fullfile(qcFolder,['FrameRate_ORIGINAL_Intensity_' ts '.png']));
            saveas(QC_before.figRejected,  fullfile(qcFolder,['FrameRate_ORIGINAL_Rejected_'  ts '.png']));
        catch
        end

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
            saveas(QC_after.figIntensity, fullfile(qcFolder,['FrameRate_INTERPOLATED_Intensity_' ts '.png']));
            saveas(QC_after.figRejected,  fullfile(qcFolder,['FrameRate_INTERPOLATED_Rejected_'  ts '.png']));
        catch
        end

        newData = data;
        newData.I = Iclean;
        newData.frameRateQC_before = QC_before;
        newData.frameRateQC_after  = QC_after;
        newData.preprocessing = 'Frame-rate rejection (validated)';

        ts2 = datestr(now,'yyyymmdd_HHMMSS');
        baseName = studio.activeDataset;
        fullName = [baseName '_frrej_' ts2];

        keyName = makeSafeKey(fullName, studio.datasets);
        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing', [fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        addLog(['Frame-rate rejection validated -> ' fullName]);

    catch ME
        addLog(['Frame-rate ERROR: ' ME.message]);
        errordlg(ME.message,'Frame-rate Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  SCRUBBING
% =========================================================
function scrubbingCallback(src, ~)

    studio = guidata(fig);
    if isempty(studio) || ~isstruct(studio) || ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Scrubbing');
        return;
    end

    data = getActiveData();

    addLog('Running scrubbing...');
    setProgramStatus(false); drawnow;

    ts  = datestr(now,'yyyymmdd_HHMMSS');
    tag = ['scrub_' ts];

    try
        [outI, stats] = scrubbing(data.I, data.TR, studio.exportPath, tag);

        method = 'Unknown';
        if isfield(stats,'method') && ~isempty(stats.method), method = stats.method; end

        interpMethod = 'linear';
        if isfield(stats,'interpMethod') && ~isempty(stats.interpMethod)
            interpMethod = stats.interpMethod;
        end

        methKey   = regexprep(method, '\s+','');
        interpKey = lower(regexprep(interpMethod,'\s+',''));

        baseName    = studio.activeDataset;
        fullName    = [baseName '_scrub_' methKey '_' interpKey '_' ts];
        keyName     = makeSafeKey(fullName, studio.datasets);

        newData = data;
        newData.I = single(outI);
        newData.preprocessing = sprintf('Scrubbing (%s, %s)', method, interpMethod);
        newData.scrubbingStats = stats;

        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
             'newData','-v7.3');

        guidata(fig, studio);
        refreshDatasetDropdown();

        nFlag = NaN; pct = NaN;
        if isfield(stats,'removedVolumes'), nFlag = stats.removedVolumes; end
        if isfield(stats,'percentRemoved'), pct = stats.percentRemoved; end

        addLog(sprintf('Scrubbing done: %s + %s | flagged=%g (%.2f%%)', methKey, interpKey, nFlag, pct));
        addLog(['Saved dataset -> ' fullName]);

    catch ME
        addLog(['SCRUBBING ERROR: ' ME.message]);
        errordlg(ME.message,'Scrubbing Failure');
    end

    setProgramStatus(true);
end

%% =========================================================
%  MOTOR RECONSTRUCTION (FINAL STABLE VERSION)
% =========================================================
function stepMotorCallback(src,~)

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
        if ~exist(qcFolder,'dir'); mkdir(qcFolder); end

        [I3D, motorInfo] = motor(data.I, data.TR, qcFolder);

        newData = data;
        newData.I = I3D;
        if ndims(I3D) == 4
            newData.nVols = size(I3D,4);
        end
        newData.preprocessing = 'Motor slice reconstruction';
        newData.motorInfo = motorInfo;

        ts = datestr(now,'yyyymmdd_HHMMSS');
        fullName = [studio.activeDataset '_motor_' ts];
        keyName  = makeSafeKey(fullName, studio.datasets);

        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing', [fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig,studio);
        refreshDatasetDropdown();

        addLog(sprintf('Slices: %d | Volumes per slice: %d | Minutes per slice: %.2f', ...
            motorInfo.nSlices, motorInfo.volumesPerSlice, motorInfo.minutesPerSlice));

        addLog('Motor reconstruction complete.');

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
                      'Despike',1,{'5'});

    if isempty(answer)
        addLog('Despiking cancelled.');
        return;
    end

    zthr = str2double(answer{1});
    if isnan(zthr) || zthr <= 0
        errordlg('Invalid Z-threshold.');
        return;
    end

    addLog(sprintf('Running voxel-wise despiking (Z = %.2f)...',zthr));
    setProgramStatus(false);
    drawnow;

    try
        ts = datestr(now,'yyyymmdd_HHMMSS');

        [outI, stats] = despike(data.I, zthr, studio.exportPath, ['despike_' ts]);

        if isfield(stats,'percentRemoved') && isfield(stats,'removedPoints')
            addLog(sprintf('Despiking removed %.4f%% of data points (%d spikes).', ...
                   stats.percentRemoved, stats.removedPoints));
        end
        if isfield(stats,'qcFile')
            addLog(['Despike QC saved: ' stats.qcFile]);
        end

        newData = data;
        newData.I = outI;
        newData.preprocessing = 'Voxel-wise MAD Despiking';
        newData.despikeZ = zthr;

        fullName = [studio.activeDataset '_despike_' ts];
        keyName  = makeSafeKey(fullName, studio.datasets);

        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing', [fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig,studio);
        refreshDatasetDropdown();

        addLog(['Despiking complete -> ' fullName]);

    catch ME
        addLog(['DESPIKE ERROR: ' ME.message]);
        errordlg(ME.message,'Despike Failure');
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

    opts.onApply  = @(sel) pca_onApply(sel);
    opts.onCancel = @() pca_onCancel();

    try
        [newData, stats] = pca_denoise(data, studio.exportPath, ['pca_' ts], opts);

        if ~isfield(stats,'applied') || ~stats.applied
            setProgramStatus(true);
            return;
        end

        fullName = [studio.activeDataset '_pca_' ts];
        keyName  = makeSafeKey(fullName, studio.datasets);

        newData.preprocessing = 'PCA denoising';

        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig,studio);
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
            addLog(['PCA applied, dropping PCs: ' sprintf('%d ', sel) '— please wait...']);
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
%  PSC COMPUTATION (deprecated but kept)
% =========================================================
function computePSCCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.'); return;
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
    par.gaussSig  = 0.5;

    addLog('Computing PSC...');
    setProgramStatus(false); drawnow;

    try
        proc = computePSC(data.I, data.TR, par, baseline);

        newData = data;
        newData.PSC = single(proc.PSC);
        newData.bg  = single(proc.bg);
        if isfield(proc,'TR_eff'),   newData.TR_eff   = proc.TR_eff; end
        if isfield(proc,'nFrames'),  newData.nFrames  = proc.nFrames; end

        fullName = ['psc_' datestr(now,'yyyymmdd_HHMMSS')];
        keyName  = makeSafeKey(fullName, studio.datasets);

        studio.datasets.(keyName) = newData;
        studio.pipeline.pscDone = true;

        save(fullfile(studio.exportPath,'PSC',[fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig,studio);
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
            if isempty(answer), return; end
            opts.FcHigh = str2double(answer{1});
            opts.order  = str2double(answer{2});
            opts.FcLow  = 0;

        case 'High-pass'
            opts.type = 'high';
            answer = inputdlg({'High-pass cutoff (Hz):','Order (1-6):'}, ...
                              'High-pass',1,{'0.01','4'});
            if isempty(answer), return; end
            opts.FcLow  = str2double(answer{1});
            opts.order  = str2double(answer{2});
            opts.FcHigh = 0;

        case 'Band-pass'
            opts.type = 'band';
            answer = inputdlg({'Low cutoff (Hz):','High cutoff (Hz):','Order (1-6):'}, ...
                              'Band-pass',1,{'0.01','0.2','4'});
            if isempty(answer), return; end
            opts.FcLow  = str2double(answer{1});
            opts.FcHigh = str2double(answer{2});
            opts.order  = str2double(answer{3});
    end

    trimAns = inputdlg({'Trim start (sec):','Trim end (sec):'}, ...
                       'Trimming',1,{'0','0'});
    if isempty(trimAns), return; end

    opts.trimStart = str2double(trimAns{1});
    opts.trimEnd   = str2double(trimAns{2});

    addLog('Running Butterworth filtering...');
    setProgramStatus(false);
    drawnow;

    try
        [I_filt, stats] = filtering(data.I, data.TR, studio.exportPath, opts);

        newData = data;
        newData.I = single(I_filt);
        newData.filtering = stats;

        ts = datestr(now,'yyyymmdd_HHMMSS');
        fullName = [studio.activeDataset '_filt_' ts];
        keyName  = makeSafeKey(fullName, studio.datasets);

        studio.datasets.(keyName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing', [fullName '.mat']), ...
            'newData','-v7.3');

        guidata(fig,studio);
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

        guidata(fig,studio);

        addLog('Atlas coregistration completed.');
        addLog('Transformation stored in studio.atlasTransform');
        addLog(['Transformation file: ' studio.atlasTransformFile]);

        try
            msgbox('Transformation saved and stored in Studio.','Atlas Coregistration','help');
        catch
        end

    catch ME
        addLog(['COREG ERROR: ' ME.message]);
        errordlg(ME.message,'Coregistration Failed');
    end

    setProgramStatus(true);
end

%% =========================================================
%  GROUP ANALYSIS
% =========================================================
function groupAnalysisCallback(src,~)

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
function functionalConnectivityCallback(src,~)

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
    if isempty(saveRoot) || ~exist(saveRoot,'dir'), saveRoot = pwd; end

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
%  SECTION D — VISUALIZATION CALLBACKS
% =========================================================

%% ---------------------------------------------------------
%  LIVE VIEWER CALLBACK
% ---------------------------------------------------------
function liveViewerCallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    if isfield(data,'PSC') && ~isempty(data.PSC)
        I = data.PSC;    % keep single
    else
        I = data.I;      % keep single
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
        viewerFig = fUSI_Live_Studio(I, data.TR, studio.meta, studio.activeDataset);
        addlistener(viewerFig,'ObjectBeingDestroyed', @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Live Viewer ERROR: ' ME.message]);
        errordlg(ME.message,'Live Viewer Failed');
        setProgramStatus(true);
    end

    clear I
    drawnow
end

%% ---------------------------------------------------------
%  SCM GUI CALLBACK (UNDERLAY SELECTION) — UPDATED
% ---------------------------------------------------------
function scmCallback(src,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','SCM');
        return;
    end

    data = getActiveData();

    par = struct();
    par.interpol = 1;
    par.previewCaxis = [];
    par.exportPath = studio.exportPath;
    par.datasetTag = studio.activeDataset;

    if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath)
        par.loadedPath = studio.loadedPath;
        par.rawPath    = studio.loadedPath;
    else
        par.loadedPath = '';
        par.rawPath    = '';
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

    baseline = struct('start',0,'end',10,'mode','sec');

    % Default PSC+bg like VideoGUI: use existing if present
    if isfield(data,'PSC') && ~isempty(data.PSC) && isfield(data,'bg') && ~isempty(data.bg)
        PSCsig    = data.PSC;
        bgDefault = data.bg;
    else
        try
            proc      = computePSC(data.I, data.TR, par, baseline);
            PSCsig    = proc.PSC;
            bgDefault = proc.bg;
        catch
            proc      = computePSC(double(data.I), data.TR, par, baseline);
            PSCsig    = proc.PSC;
            bgDefault = proc.bg;
        end
    end

    [bgUnderlay, underlayLabel] = chooseSCMUnderlay(studio, data, bgDefault);
    if isempty(bgUnderlay)
        addLog('SCM cancelled (no underlay selected).');
        return;
    end

    loadedMask = [];
    loadedMaskIsInclude = true;
    if isfield(studio,'mask') && ~isempty(studio.mask)
        loadedMask = studio.mask;
        if isfield(studio,'maskIsInclude') && ~isempty(studio.maskIsInclude)
            loadedMaskIsInclude = logical(studio.maskIsInclude);
        end
    end

    addLog(['Opening SCM GUI (Dataset: ' studio.activeDataset ')']);
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

%% ---------------------------------------------------------
%  VIDEO GUI CALLBACK (ACTIVE DATASET ONLY)
% ---------------------------------------------------------
function videoGUICallback(~,~)

    studio = guidata(fig);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog(['Opening Video GUI (Dataset: ' studio.activeDataset ')']);

    answer = inputdlg( ...
        {'Baseline START (seconds):','Baseline END (seconds):'}, ...
        'Video GUI Baseline', ...
        1, {'0','10'});

    if isempty(answer)
        addLog('Video GUI cancelled.');
        return;
    end

    blStart = str2double(answer{1});
    blEnd   = str2double(answer{2});

    if isnan(blStart) || isnan(blEnd) || blEnd <= blStart
        errordlg('Invalid baseline range (seconds).');
        return;
    end

    baseline = struct('start',blStart,'end',blEnd,'mode','sec');

    par = struct();
    par.interpol = 1;
    par.LPF = 0;
    par.HPF = 0;
    par.gaussSize = 0;
    par.gaussSig = 0;
    par.previewCaxis = [];
    par.caxis = [];

    Iraw = data.I;  % keep original precision (usually single)

    if isfield(data,'PSC') && ~isempty(data.PSC) && isfield(data,'bg') && ~isempty(data.bg)
        PSCsig = data.PSC;
        bg     = data.bg;
    else
        try
            proc   = computePSC(Iraw, data.TR, par, baseline);
        catch
            proc   = computePSC(double(Iraw), data.TR, par, baseline);
        end
        PSCsig = proc.PSC;
        bg     = proc.bg;
    end

    Iinterp = Iraw;

    initialFPS = 10;
    maxFPS     = 240;

    if isfield(studio,'mask') && ~isempty(studio.mask)
        loadedMask = studio.mask;
        loadedMaskIsInclude = studio.maskIsInclude;
    else
        loadedMask = [];
        loadedMaskIsInclude = true;
    end

    setProgramStatus(false);
    drawnow;

    try
        videoFig = play_fusi_video_final( ...
            Iraw, Iinterp, PSCsig, bg, ...
            par, initialFPS, maxFPS, ...
            data.TR, (data.nVols-1)*data.TR, ...
            baseline, ...
            loadedMask, loadedMaskIsInclude, ...
            data.nVols, false, struct(), ...
            studio.activeDataset);

        addlistener(videoFig,'ObjectBeingDestroyed', @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Video GUI ERROR: ' ME.message]);
        errordlg(ME.message,'Video GUI Failed');
        setProgramStatus(true);
    end
end

%% ---------------------------------------------------------
%  MASK EDITOR CALLBACK (STANDALONE)
% ---------------------------------------------------------
function maskEditorCallback(~,~)

    studio = guidata(fig);

    if ~isfield(studio,'isLoaded') || ~studio.isLoaded
        errordlg('Load data first.','Mask Editor');
        return;
    end

    data = getActiveData();

    addLog(['Opening Mask Editor (Dataset: ' studio.activeDataset ')']);
    setProgramStatus(false); drawnow;

    try
        out = mask(studio, data.I, studio.activeDataset);

        if ~isstruct(out) || (isfield(out,'cancelled') && out.cancelled)
            addLog('Mask Editor cancelled.');
            setProgramStatus(true);
            return;
        end

        if isfield(out,'mask') && ~isempty(out.mask)
            studio.mask = logical(out.mask);
            studio.brainMask = studio.mask;
            studio.maskIsInclude = true;
            addLog('Mask stored in Studio (studio.mask).');
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
        showName = makeDropdownLabel(getDatasetDisplayName(studio, studio.activeDataset));
        maxLen = 90;
        if length(showName) > maxLen
            showName = [showName(1:maxLen) '...'];
        end
        set(studio.activeDatasetText,'String',['ACTIVE DATASET: ' showName]);
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
        showName = getDatasetDisplayName(studio, studio.activeDataset);
        maxLen = 90;
        if length(showName) > maxLen
            showName = [showName(1:maxLen) '...'];
        end
        set(studio.activeDatasetText,'String',['ACTIVE DATASET: ' showName]);
    end

    guidata(fig, studio);
end

%% =========================================================
%  GET ACTIVE DATASET (SAFE LAZY LOAD)  ***FIG SAFE***
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
            m = matfile(data.lazyFile);
            tmp = m.newData;
            data = tmp;

            data.isLazy = false;

            studio.datasets.(selected) = data;
            guidata(fig, studio);

            addLog(['Dataset loaded: ' selected]);

        catch ME
            addLog(['Lazy load ERROR: ' ME.message]);
            setProgramStatus(true);
            rethrow(ME);
        end

        setProgramStatus(true);
    end
end

%% =========================================================
%  UNLOCK ALL BUTTONS AFTER LOAD
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
%  EXPORT Log Session
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

    logContent = get(studio.logBox,'String');
    if isempty(logContent)
        errordlg('Studio log is empty.');
        return;
    end

    if ~iscell(logContent)
        logContent = {logContent};
    end

    ts = datestr(now,'yyyymmdd_HHMMSS');
    outFile = fullfile(studio.exportPath, ['StudioLog_' ts '.txt']);

    fid = fopen(outFile,'w');
    for i = 1:numel(logContent)
        fprintf(fid,'%s\n',logContent{i});
    end
    fclose(fid);

    addLog(['Studio log exported -> ' outFile]);
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
    'functional ultrasound imaging (fUSI).'
    ''
    'Supported data formats:'
    '  - 2D probe  : Y x X x T'
    '  - 3D matrix : Y x X x Z x T'
    ''
    'When loading a dataset, the system automatically:'
    '  - Extracts TR (temporal resolution)'
    '  - Computes number of volumes'
    '  - Computes total acquisition time'
    '  - Detects probe type (2D or 3D)'
    '  - Creates a mirrored AnalysedData folder'
    '  - Creates subfolders: QC / Preprocessing / PSC / Visualization'
    ''
    '==========================================================================='
    'RECOMMENDED WORKFLOW'
    '==========================================================================='
    '1) Load Data'
    '2) Run Full QC'
    '3) Apply Frame Rejection or Scrubbing'
    '4) (Optional) Filtering / PCA / Despike'
    '5) Visualization (Live / SCM / Video)'
    '6) Atlas registration'
    '7) Connectivity or Group Analysis'
    '==========================================================================='
    };

    set(txtBox,'String',strjoin(guide,newline));
end

%% =========================================================
%  LOGGING UTILITY
% =========================================================
function addLog(msg)

    if isempty(fig) || ~ishandle(fig), return; end

    studio = guidata(fig);

    if isfield(studio,'logBox') && ~isempty(studio.logBox) && ishghandle(studio.logBox)
        lb = studio.logBox;
    else
        lb = findobj(fig,'Style','listbox');
        if isempty(lb), return; end
        lb = lb(1);
    end

    current = get(lb,'String');
    if ~iscell(current), current = {current}; end

    timestamp = datestr(now,'HH:MM:SS');
    newEntry = sprintf('[%s] %s',timestamp,msg);

    set(lb,'String',[current; {newEntry}]);
    drawnow;
end

%% =========================================================
%  FOOTER LABEL
% =========================================================
function s = buildFooterLabel()
    person = 'Soner Caner Cagun';
    tool   = 'HUMoR Analysis Tool';
    inst   = 'Max-Planck Institute for Biological Cybernetics';
    dt     = datestr(now,'yyyy-mm-dd HH:MM');
    s = sprintf('%s - %s - %s - %s', person, tool, inst, dt);
end

%% =========================================================
%  STATUS BAR HANDLER
% =========================================================
function setProgramStatus(isReady)

    studio = guidata(fig);
    statusPanel = studio.statusPanel;
    statusText  = studio.statusText;

    bgReady    = [0.15 0.60 0.20];
    bgNotReady = [0.85 0.20 0.20];
    fg         = [1 1 1];

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
%  SMALL HELPERS (iff)
% =========================================================
function out = iff(cond, a, b)
    if cond, out = a; else, out = b; end
end

%% =========================================================
%  HELPERS for dataset naming (safe keys + nice labels)
% =========================================================
function label = makeDropdownLabel(fullName)

    ts = regexp(fullName, '_\d{8}_\d{6}', 'match');

    if isempty(ts)
        label = regexprep(fullName,'_+','_');
        label = regexprep(label,'^_','');
        label = regexprep(label,'_$','');
        return;
    end

    lastTS = ts{end};
    lastTS = lastTS(2:end);

    base = regexprep(fullName, '_\d{8}_\d{6}', '');

    base = regexprep(base,'_+','_');
    base = regexprep(base,'^_','');
    base = regexprep(base,'_$','');

    label = sprintf('%s (%s)', base, lastTS);
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

%% =========================================================
%  SCM UNDERLAY CHOOSER + LOADER (kept from your version)
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

    choice = questdlg('Choose SCM underlay image:', ...
                      'SCM Underlay', ...
                      opts{1}, opts{2}, opts{4}, opts{1});

    if isempty(choice) || strcmp(choice, opts{5})
        return;
    end

    switch choice
        case opts{1}
            bg = bgDefault;
            label = 'Default (VideoGUI bg)';

        case opts{2}
            bg = computeUnderlayFromActive(data,'mean');
            label = 'Mean(I)';

        case opts{3}
            bg = computeUnderlayFromActive(data,'median');
            label = 'Median(I)';

        case opts{4}
            startPath = pwd;
            if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
                startPath = studio.loadedPath;
            end

            [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.tif;*.tiff', ...
                               'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.tif)'}, ...
                               'Select underlay (DP/anatomy)', startPath);
            if isequal(f,0), return; end

            bg = loadUnderlayFile(fullfile(p,f));
            if isempty(bg), return; end

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
    T  = sz(dimT);

    maxFrames = 600;
    if T <= maxFrames
        idx = 1:T;
    else
        step = ceil(T / maxFrames);
        idx  = 1:step:T;
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
            if isempty(d), error('gunzip failed for %s', f); end
            niiFile = fullfile(tmpDir, d(1).name);
            V = niftiread(niiFile);
            try, rmdir(tmpDir,'s'); catch, end
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
            U = pickNumericFromMat(S);
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

function U = pickNumericFromMat(S)
    if isstruct(S)
        fn = fieldnames(S);
        for k = 1:numel(fn)
            v = S.(fn{k});
            if isstruct(v) && isfield(v,'I') && isnumeric(v.I)
                U = v.I; return;
            end
        end
        for k = 1:numel(fn)
            v = S.(fn{k});
            if isnumeric(v)
                U = v; return;
            end
        end
    end
    error('No numeric underlay found in MAT file.');
end

function X = squeezeTo2Dor3D(X)
    while ndims(X) > 3
        X = mean(X, ndims(X));
    end
end

function G = toGray(X)
    if ndims(X) == 3 && size(X,3) == 3
        R = X(:,:,1); Gc = X(:,:,2); B = X(:,:,3);
        G = 0.2989*R + 0.5870*Gc + 0.1140*B;
        return;
    end
    G = X;
end

%% =========================================================
%  MakeSafeKey (struct field-safe, unique, <= namelengthmax)
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
%  CLOSE HANDLER
% =========================================================
function onCloseStudio(~,~)
    try
        delete(fig);
    catch
    end
end

end