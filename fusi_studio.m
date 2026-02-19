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
studio.allButtons = {};   % proper handle container
studio.figure = [];              % store figure handle

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
fig = figure('Name','fUSI Studio',...
    'Color',[0.05 0.05 0.05],...
    'Position',[100 40 1900 1080],...
    'MenuBar','none',...
    'ToolBar','none',...
    'NumberTitle','off');

studio.figure = fig;
guidata(fig, studio);

%% =========================================================
%  TITLE
% =========================================================
uicontrol(fig,'Style','text',...
    'String','fUSI Studio',...
    'Units','normalized',...
    'Position',[0.52 0.95 0.35 0.04],...
    'FontSize',30,...
    'FontWeight','bold',...
    'ForegroundColor',[0.95 0.95 0.95],...
    'BackgroundColor',[0.05 0.05 0.05],...
    'HorizontalAlignment','center');

%% =========================================================
%  LEFT PANEL
% =========================================================
leftWidth = 0.45;
leftPanel = uipanel(fig,...
    'Units','normalized',...
    'Position',[0.03 0.10 leftWidth 0.83],...
    'BackgroundColor',[0.07 0.07 0.07],...
    'BorderType','none');


%% =========================================================
%  LOG PANEL
% =========================================================
logPanel = uipanel(fig,...
    'Title','Studio Log',...
    'Units','normalized',...
    'Position',[0.50 0.19 0.47 0.70],...
    'BackgroundColor',[0.07 0.07 0.07],...
    'ForegroundColor','w',...
    'FontSize',14,...
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

studio.activeDatasetText = activeDatasetText;
guidata(fig,studio);

logBox = uicontrol(logPanel,'Style','listbox',...
    'Units','normalized',...
    'Position',[0.02 0.02 0.96 0.94],...
    'BackgroundColor',[0 0 0],...
    'ForegroundColor',[0.6 0.85 1],...
    'FontName','Courier New',...
    'FontSize',11);

% attach in figure for later access
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
    '2. Quality Control', ...
    '3. Recommended Processing Steps', ...
    '4. Advanced Processing', ...
    '5. Visualization', ...
    '6. Coregistration', ...
    '7. Advanced Analysis'};

buttons = { ...
    {'Load fUSI Data'}, ...
    {'Full QC','Specific QC'}, ...
    {'Frame Rejection','Subsampling','Scrubbing','Motor'}, ...
    {'Compute PSC','Filtering', 'PCA', 'Despike'}, ...
    {'Time-Course Viewer','SCM','Video & Mask'}, ...
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

    panel = uipanel(leftPanel,...
        'Title',titles{i},...
        'Units','normalized',...
        'Position',[0.03 y 0.94 h],...
        'BackgroundColor',[0.10 0.10 0.10],...
        'ForegroundColor','w',...
        'FontSize',16,...
        'FontWeight','bold',...
        'BorderType','line',...
        'HighlightColor',[1 1 1],...
        'ShadowColor',[1 1 1]);

    drawButtons(panel, buttons{i}, i);

    y = y - gapBetweenSections;
end

%% =========================================================
%  STATUS BAR
% =========================================================
statusPanel = uipanel(fig,...
    'Units','normalized',...
    'Position',[0.03 0.05 leftWidth 0.055],...
    'BorderType','line', ...     % <--- FIXED
    'HighlightColor',[0 0 0], ...% <--- FIXED
    'ShadowColor',[0 0 0]);      % <--- FIXED


statusText = uicontrol(statusPanel,'Style','text',...
    'Units','normalized',...
    'Position',[0 0 1 1],...
    'FontWeight','bold',...
    'FontSize',16,...
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

uicontrol(fig,'Style','pushbutton',...
    'String','HELP',...
    'Units','normalized',...
    'Position',[0.50 btnY 0.10 btnH],...
    'FontWeight','bold',...
    'FontSize',13,...
    'BackgroundColor',[0.30 0.50 0.95],...
    'ForegroundColor','w',...
    'Callback',@helpCallback);


uicontrol(fig,'Style','pushbutton',...
    'String','EXPORT STUDIO LOG',...
    'Units','normalized',...
    'Position',[0.62 btnY 0.14 btnH],...
    'FontWeight','bold',...
    'FontSize',13,...
    'BackgroundColor',[0.15 0.65 0.55],...
    'ForegroundColor','w',...
    'Callback',@exportSessionCallback);

uicontrol(fig,'Style','pushbutton',...
    'String','CLOSE',...
    'Units','normalized',...
    'Position',[0.79 btnY 0.10 btnH],...
    'FontWeight','bold',...
    'FontSize',13,...
    'BackgroundColor',[0.85 0.25 0.25],...
    'ForegroundColor','w',...
    'Callback',@(s,e) close(fig));

%% =========================================================
%  BUTTON DRAWING FUNCTION WITH DROPDOWN
% =========================================================
function drawButtons(parent, btns, sectionIndex)

    % ? Must use FIG always — never gcbf here.
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

            loadBtn = uicontrol(parent,...
                'Style','pushbutton',...
                'String','Load fUSI Data',...
                'Units','normalized',...
                'Position',[xpos ypos btnWidth btnHeight],...
                'FontWeight','bold',...
                'FontSize',14,...
                'ForegroundColor','w',...
                'Enable','on',...
                'BackgroundColor',[0.35 0.35 0.35],...
                'Callback',@loadDataCallback);

            studio.allButtons{end+1} = loadBtn;

            % -------- DROPDOWN --------
            ddX = xpos + btnWidth + 0.06;

            uicontrol(parent,...
                'Style','popupmenu',...
                'String',{'<none>'},...
                'Units','normalized',...
                'Position',[ddX ypos btnWidth btnHeight],...
                'BackgroundColor',[0.2 0.2 0.2],...
                'ForegroundColor','w',...
                'FontSize',13,...
                'Callback',@datasetDropdownCallback,...
                'Tag','datasetDropdown');

            guidata(fig, studio);
            return;
        end

        % -------- ALL OTHER BUTTONS --------
        r = floor((k-1)/cols);
        c = mod(k-1, cols);

        xpos = 0.08 + c*(btnWidth + xGap);
        ypos = yStart - r*yGap;

        callback = [];
        
switch label
    case 'Full QC',                 callback = @runFullQCCallback;
    case 'Specific QC',             callback = @runSpecificQCCallback;
    case 'Frame Rejection',         callback = @frameRateCallback;
    case 'Subsampling',             callback = @gabrielCallback;
    case 'Scrubbing',               callback = @scrubbingCallback;
    case 'Motor',                   callback = @stepMotorCallback;
    case 'Compute PSC',             callback = @computePSCCallback;
    case 'Filtering',               callback = @filteringCallback;
    case 'PCA',                     callback = @pcaCallback;
    case 'Despike',                 callback = @despikeCallback;
    case 'Time-Course Viewer',      callback = @liveViewerCallback;
    case 'SCM',                     callback = @scmCallback;
    case 'Video & Mask',            callback = @videoGUICallback;
    case 'Registration to Atlas',   callback = @coregCallback;
end


        btn = uicontrol(parent,...
            'Style','pushbutton',...
            'String',label,...
            'Units','normalized',...
            'Position',[xpos ypos btnWidth btnHeight],...
            'FontWeight','bold',...
            'FontSize',14,...
            'ForegroundColor','w',...
            'BackgroundColor',[0.18 0.18 0.18],...
            'Enable','off',...   % locked until load
            'Callback',callback);

        studio.allButtons{end+1} = btn;
    end

    guidata(fig, studio);
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

    studio = guidata(gcbf);

    startPath = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
    if ~exist(startPath,'dir'), startPath = pwd; end

    [file,path] = uigetfile({'*.mat;*.nii','fUSI Data'},...
        'Select fUSI dataset',startPath);

    if isequal(file,0)
        addLog('Load cancelled.');
        return;
    end

    addLog('Loading dataset...');
    setProgramStatus(false); drawnow;

    %% RESET INTERNAL STATE
    studio.datasets = struct();
    studio.activeDataset = '';
    studio.meta = [];
    studio.isLoaded = false;
    studio.loadedFile = '';
    studio.loadedPath = '';
    studio.exportPath = '';
    studio.pipeline = struct( ...
        'loadDone', false, ...
        'qcDone', false, ...
        'preprocDone', false, ...
        'pscDone', false, ...
        'visualDone', false);

    guidata(gcbf,studio);

    fallbackTR = 0.32;

    try
        [data, meta] = loadFUSIData(fullfile(path,file), fallbackTR);

        %% AUTO EXPORT FOLDER MIRROR
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
        for k = 1:numel(folders)
            if ~exist(folders{k},'dir'), mkdir(folders{k}); end
        end

        %% STORE RAW DATASET
        studio = guidata(gcbf);

        studio.datasets.raw = data;
        studio.activeDataset = 'raw';
        studio.meta = meta;
        studio.isLoaded = true;
        studio.loadedFile = file;
        studio.loadedPath = path;
        studio.exportPath = datasetFolder;
        studio.pipeline.loadDone = true;
        
%% ---------------------------------------------------------
%  REGISTER EXISTING PSC + PREPROCESSING FILES (LAZY LOAD)
% ---------------------------------------------------------
pscFiles = dir(fullfile(datasetFolder,'PSC','*.mat'));
for k = 1:numel(pscFiles)
    name = erase(pscFiles(k).name,'.mat');
    studio.datasets.(name) = struct( ...
        'lazyFile', fullfile(pscFiles(k).folder, pscFiles(k).name), ...
        'isLazy', true);
end

preFiles = dir(fullfile(datasetFolder,'Preprocessing','*.mat'));
for k = 1:numel(preFiles)
    name = erase(preFiles(k).name,'.mat');
    studio.datasets.(name) = struct( ...
        'lazyFile', fullfile(preFiles(k).folder, preFiles(k).name), ...
        'isLazy', true);
end


        guidata(gcbf, studio);

        %% ENABLE ALL BUTTONS
        unlockAllButtons();

        %% REFRESH DROPDOWN
        refreshDatasetDropdown();

        %% LOG METADATA
        dims = size(data.I);
        nz = 1;
        if isfield(meta.rawMetadata,'imageDim')
            if numel(meta.rawMetadata.imageDim) == 3
                nz = meta.rawMetadata.imageDim(3);
            end
        end
        probeType = iff(nz>1,'Matrix (3D) Probe','2D Probe');

        addLog('---------------------------------------');
        addLog('DATASET LOADED SUCCESSFULLY');
        addLog(['Dataset folder: ' datasetFolder]);
        addLog(sprintf('Dimensions: %d x %d x %d', dims(1), dims(2), nz));
        addLog(sprintf('Volumes: %d', data.nVols));
        addLog(['Probe: ' probeType]);
        addLog(sprintf('TR: %.3f sec', data.TR));
        addLog(sprintf('Total time: %.2f sec', data.TotalTimeSec));
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

    studio = guidata(gcbf);
    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    addLog('Running FULL QC...');
    setProgramStatus(false); drawnow;

    opts = struct();
    opts.frequency  = true;
    opts.spatial    = true;
    opts.temporal   = true;
    opts.motion     = true;
    opts.stability  = true;
    opts.pca        = true;
    opts.framerate  = true;

    data = getActiveData(); 
par = struct();
par.interpol = 1;
par.LPF = 0;
par.HPF = 0;
par.gaussSize = 0;
par.gaussSig = 0;
par.previewCaxis = [];
par.caxis = [];

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);
        addLog('FULL QC completed.');
        studio.pipeline.qcDone = true;
        guidata(gcbf,studio);
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

    studio = guidata(gcbf);
    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    list = { ...
        'Frequency QC','Spatial QC','Temporal QC',...
        'Motion QC','Stability QC','Frame-rate QC','PCA QC'};

    choice = listdlg( ...
        'PromptString','Select QC modules:', ...
        'SelectionMode','multiple', ...
        'ListString',list, ...
        'ListSize',[350 260]);

    if isempty(choice)
        addLog('QC selection cancelled.');
        return;
    end

    opts = struct( ...
        'frequency',  ismember(1,choice), ...
        'spatial',    ismember(2,choice), ...
        'temporal',   ismember(3,choice), ...
        'motion',     ismember(4,choice), ...
        'stability',  ismember(5,choice), ...
        'framerate',  ismember(6,choice), ...
        'pca',        ismember(7,choice));

    addLog('Running selected QC...');
    setProgramStatus(false); drawnow;

    data = getActiveData(); 

    try
        qc_fusi(data, studio.meta, studio.exportPath, opts);
        addLog('Selected QC completed.');
        studio.pipeline.qcDone = true;
        guidata(gcbf,studio);
    catch ME
        addLog(['QC ERROR: ' ME.message]);
        errordlg(ME.message,'QC Failure');
    end

    setProgramStatus(true);
end


%% =========================================================
%  ATLAS COREGISTRATION
% =========================================================
function coregCallback(~,~)

    studio = guidata(gcbf);
    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    addLog('Preparing anatomical image...');
    setProgramStatus(false); drawnow;

    rawFolder = studio.loadedPath;
    files = dir(rawFolder);

    anatFiles = {};
    for i = 1:length(files)
        f = files(i).name;
        f2 = lower(f);
        if contains(f2,'anat') || contains(f2,'t2') || contains(f2,'struct')
            if endsWith(f2,{'.nii','.nii.gz','.mat'})
                anatFiles{end+1} = f;
            end
        end
    end

    anatomy = [];
    useManual = false;

    if ~isempty(anatFiles)
        [idx,tf] = listdlg( ...
            'PromptString','Select anatomical file:', ...
            'SelectionMode','single', ...
            'ListString',anatFiles);
        if tf
            anatomy = loadAnatomy(fullfile(rawFolder, anatFiles{idx}));
            addLog(['Using anatomy: ' anatFiles{idx}]);
        else
            useManual = true;
        end
    else
        useManual = true;
    end

    if useManual
        [file,path2] = uigetfile( ...
            {'*.nii;*.nii.gz;*.mat','Anatomy'}, ...
            'Select anatomical scan (Cancel = mean functional)');
        if isequal(file,0)
            % fallback
            data = getActiveData(); 
            anatomy = mean(data.I, ndims(data.I));
            addLog('Using mean functional as anatomy.');
        else
            anatomy = loadAnatomy(fullfile(path2,file));
            addLog(['Using anatomy: ' file]);
        end
    end

    try
        addLog('Launching atlas coreg...');
        data = getActiveData(); 

        T = coreg(studio, anatomy);
        studio.meta.atlasTransf = T;
        studio.pipeline.atlasDone = true;
        guidata(gcbf, studio);

        addLog('Atlas coregistration complete.');

    catch ME
        addLog(['Atlas ERROR: ' ME.message]);
        errordlg(ME.message,'Atlas Failure');
    end

    setProgramStatus(true);
end


%% =========================================================
%  GABRIEL PREPROCESSING
% =========================================================
function gabrielCallback(~,~)

    studio = guidata(gcbf);
    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    %% Ask nsub
    answ = inputdlg({'Enter subsampling factor (nsub ? 2):'}, ...
        'Gabriel Preprocessing', 1, {'50'});
    if isempty(answ)
        addLog('Gabriel preprocessing cancelled.');
        return;
    end

    nsub = str2double(answ{1});
    if isnan(nsub) || nsub < 2
        errordlg('Invalid nsub (?2).'); return;
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
        newData.nVols = out.nVols;
        newData.totalTime = out.totalTime;
        newData.preprocessing = out.method;

       ts = datestr(now,'yyyymmdd_HHMMSS');
baseName = studio.activeDataset;
versionName = [baseName '_gabriel_' ts];


        studio.datasets.(versionName) = newData;
        studio.pipeline.preprocDone = true;

        save(fullfile(studio.exportPath,'Preprocessing',[versionName '.mat']), ...
            'newData','-v7.3');

        guidata(gcbf, studio);

        refreshDatasetDropdown();
        %
        guidata(gcbf,studio);

        addLog(['Gabriel preprocessing ? ' versionName]);

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

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog('Running Frame-rate QC (ORIGINAL)...');
    setProgramStatus(false);
    drawnow;

    try

        % --------------------------------------------------
        % 1) QC ON ORIGINAL
        % --------------------------------------------------
        QC_before = frameRateQC(data.I, data.TR, 'ORIGINAL', false);

        addLog(sprintf('Original rejected: %.2f %%', QC_before.rejPct));

        qcFolder = fullfile(studio.exportPath,'QC','png');
        if ~exist(qcFolder,'dir'), mkdir(qcFolder); end

        ts = datestr(now,'yyyymmdd_HHMMSS');

        saveas(QC_before.figIntensity, ...
            fullfile(qcFolder,['FrameRate_ORIGINAL_Intensity_' ts '.png']));
        saveas(QC_before.figRejected, ...
            fullfile(qcFolder,['FrameRate_ORIGINAL_Rejected_' ts '.png']));

        % --------------------------------------------------
        % 2) ASK FOR INTERPOLATION
        % --------------------------------------------------
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

        % --------------------------------------------------
        % 3) INTERPOLATE
        % --------------------------------------------------
        Iclean = interpolateRejectedVolumes(data.I, QC_before.outliers);

        % --------------------------------------------------
        % 4) QC AGAIN (VALIDATION)
        % --------------------------------------------------
        addLog('Running Frame-rate QC (INTERPOLATED)...');

        QC_after = frameRateQC(Iclean, data.TR, 'INTERPOLATED', false);

        addLog(sprintf('After interpolation rejected: %.2f %%', QC_after.rejPct));

        saveas(QC_after.figIntensity, ...
            fullfile(qcFolder,['FrameRate_INTERPOLATED_Intensity_' ts '.png']));
        saveas(QC_after.figRejected, ...
            fullfile(qcFolder,['FrameRate_INTERPOLATED_Rejected_' ts '.png']));

        % --------------------------------------------------
        % 5) CREATE NEW DATASET VERSION
        % --------------------------------------------------
        newData = data;
        newData.I = Iclean;
        newData.frameRateQC_before = QC_before;
        newData.frameRateQC_after  = QC_after;
        newData.preprocessing = 'Frame-rate rejection (validated)';

    ts = datestr(now,'yyyymmdd_HHMMSS');
baseName = studio.activeDataset;
versionName = [baseName '_frrej_' ts];


        studio.datasets.(versionName) = newData;
        studio.pipeline.preprocDone = true;

        % SAVE MAT
        save(fullfile(studio.exportPath,'Preprocessing', ...
            [versionName '.mat']), ...
            'newData','-v7.3');

        guidata(gcbf, studio);

        refreshDatasetDropdown();
        %
        guidata(gcbf,studio);

        addLog(['Frame-rate rejection validated ? ' versionName]);

    catch ME
        addLog(['Frame-rate ERROR: ' ME.message]);
        errordlg(ME.message,'Frame-rate Failure');
    end

    setProgramStatus(true);
end

function scrubbingCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog('Running Scrubbing (rDVARS)...');
    setProgramStatus(false);
    drawnow;

    try

        ts = datestr(now,'yyyymmdd_HHMMSS');

        % ? Correct function call
        [outI, stats] = scrubbing(data.I, ...
                                  data.TR, ...
                                  studio.exportPath, ...
                                  ['scrub_' ts]);

        % ---- Log trimming info ----
        if stats.trimmed
            addLog(sprintf('Dataset trimmed: -%.2fs start, -%.2fs end.',...
                   stats.trimStartSec,stats.trimEndSec));
            addLog(sprintf('New total time: %.2f seconds.',...
                   stats.newTotalTime));
        end

        % ---- Log scrubbing stats ----
        addLog(sprintf('Scrubbing replaced %.2f%% volumes (%d/%d).',...
               stats.percentRemoved,...
               stats.removedVolumes,...
               stats.finalVolumes));

        addLog(['Scrubbing QC saved: ' stats.qcFile]);

        % ---- Create new dataset version ----
        newData = data;
        newData.I = outI;
        newData.preprocessing = 'Scrubbing (rDVARS)';
        newData.scrubbingTimestamp = ts;

        baseName = studio.activeDataset;
        versionName = [baseName '_scrub_' ts];

        studio.datasets.(versionName) = newData;
        studio.pipeline.preprocDone = true;

        % ---- Save ----
        save(fullfile(studio.exportPath,'Preprocessing',...
            [versionName '.mat']),...
            'newData','-v7.3');

        guidata(gcbf, studio);
        refreshDatasetDropdown();

        addLog(['Scrubbing complete ? ' versionName]);

    catch ME
        addLog(['SCRUBBING ERROR: ' ME.message]);
        errordlg(ME.message,'Scrubbing Failure');
    end

    setProgramStatus(true);

end

function despikeCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    answer = inputdlg('Z-threshold (default = 5):',...
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

        % ? Correct single call
        [outI, stats] = despike(data.I,...
                                zthr,...
                                studio.exportPath,...
                                ['despike_' ts]);

        % ---- Log stats ----
        addLog(sprintf('Despiking removed %.4f%% of data points (%d spikes).',...
               stats.percentRemoved,...
               stats.removedPoints));

        addLog(['Despike QC saved: ' stats.qcFile]);

        % ---- Create dataset version ----
        newData = data;
        newData.I = outI;
        newData.preprocessing = 'Voxel-wise MAD Despiking';
        newData.despikeZ = zthr;

        baseName = studio.activeDataset;
        versionName = [baseName '_despike_' ts];

        studio.datasets.(versionName) = newData;
        studio.pipeline.preprocDone = true;

        % ---- Save ----
        save(fullfile(studio.exportPath,'Preprocessing',...
            [versionName '.mat']),...
            'newData','-v7.3');

        guidata(gcbf,studio);
        refreshDatasetDropdown();

        addLog(['Despiking complete ? ' versionName]);

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

studio = guidata(gcbf);

if ~studio.isLoaded
    errordlg('Load data first.');
    return;
end

data = getActiveData();

addLog('Running PCA denoising...');
setProgramStatus(false);
drawnow;

try

    ts = datestr(now,'yyyymmdd_HHMMSS');

 [newData, stats] = pca_denoise(data,...
                               studio.exportPath,...
                               ['pca_' ts]);

versionName = [studio.activeDataset '_pca_' ts];

studio.datasets.(versionName) = newData;
studio.pipeline.preprocDone = true;

save(fullfile(studio.exportPath,'Preprocessing',...
     [versionName '.mat']),...
     'newData','-v7.3');

guidata(gcbf,studio);
refreshDatasetDropdown();

addLog(sprintf('PCA removed %.2f%% variance.',...
       stats.percentExplainedRemoved));
addLog(['PCA QC saved: ' stats.qcFile]);
addLog(['PCA complete ? ' versionName]);

    newData.preprocessing = 'PCA denoising';

    versionName = [studio.activeDataset '_pca_' ts];
    studio.datasets.(versionName)=newData;

    save(fullfile(studio.exportPath,'Preprocessing',...
         [versionName '.mat']),'newData','-v7.3');

    guidata(gcbf,studio);
    refreshDatasetDropdown();

    addLog(sprintf('PCA removed %.2f%% variance.',...
           stats.percentExplainedRemoved));
    addLog(['PCA QC saved: ' stats.qcFile]);
    addLog(['PCA complete ? ' versionName]);

catch ME
    addLog(['PCA ERROR: ' ME.message]);
    errordlg(ME.message,'PCA Failure');
end

setProgramStatus(true);
end

%% =========================================================
%  PSC COMPUTATION  (deprecated but kept)
% =========================================================
function computePSCCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.'); return;
    end

    data = getActiveData(); 

    baseline.start = 0;
    baseline.end = min(5, data.nVols * data.TR);

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

        newData.bg  = proc.bg;
        newData.TR_eff = proc.TR_eff;
        newData.nFrames = proc.nFrames;

        versionName = ['psc_' datestr(now,'yyyymmdd_HHMMSS')];
        studio.datasets.(versionName) = newData;
        studio.pipeline.pscDone = true;

        save(fullfile(studio.exportPath,'PSC',[versionName '.mat']), ...
            'newData','-v7.3');

        guidata(gcbf,studio);

        refreshDatasetDropdown();
        %
        guidata(gcbf, studio);

        addLog(['PSC computation ? ' versionName]);

    catch ME
        addLog(['PSC ERROR: ' ME.message]);
        errordlg(ME.message,'PSC Failure');
    end

    setProgramStatus(true);
end

%% ---------------------------------------------------------
%  FILTERING PLACEHOLDER
% ---------------------------------------------------------
function filteringCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    addLog('Filtering module not implemented yet.');
    msgbox('Filtering module coming soon.','Filtering','help');

end

%% =========================================================
%  CHOOSE SIGNAL SOURCE HELPER  (LIVE/SCM/VIDEO)
% =========================================================
function [sig, bg, desc] = chooseSignalForViz()
    studio = guidata(gcbf);

    list = {'Raw (I)','PSC','Preprocessed (Gabriel)'};

    [idx,tf] = listdlg( ...
        'PromptString','Select data source for visualization:', ...
        'SelectionMode','single', ...
        'ListString',list,...
        'ListSize',[300 200]);

    if ~tf
        sig = []; bg = []; desc = '';
        return;
    end

    desc = list{idx};
    data = getActiveData(); 

    switch desc
        case 'Raw (I)'
            sig = data.I;
            bg  = mean(data.I, ndims(data.I));
        case 'PSC'
            if ~isfield(data,'PSC')
                errordlg('PSC not computed for this dataset.');
                sig = []; bg = []; return;
            end
            sig = data.PSC;
            bg  = data.bg;
        case 'Preprocessed (Gabriel)'
            sig = data.I;   % Gabriel result already in I
            bg  = mean(data.I, ndims(data.I));
    end
end
%% =========================================================
%  SECTION C — HELPERS & UTILITY FUNCTIONS
% =========================================================

%% ---------------------------------------------------------
%  DATASET DROPDOWN CALLBACK
%% ---------------------------------------------------------
function datasetDropdownCallback(src,~)

    % Always use MAIN figure handle
    studio = guidata(fig);

    items = get(src,'String');
    idx   = get(src,'Value');

    if isempty(items) || strcmp(items{idx},'<none>')
        return;
    end

    % Update active dataset
    studio.activeDataset = items{idx};

    % Save properly to MAIN figure
    guidata(fig, studio);

    % Optional: update active dataset display label
   if isfield(studio,'activeDatasetText') && isgraphics(studio.activeDatasetText)

    maxLen = 60;   % adjust if needed
    name = studio.activeDataset;

    if length(name) > maxLen
        name = [name(1:maxLen) '...'];
    end

    set(studio.activeDatasetText, ...
        'String',['ACTIVE DATASET: ' name]);
end
end

%% ---------------------------------------------------------
%  REFRESH DATASET DROPDOWN (ADD THIS BACK)
%% ---------------------------------------------------------
function refreshDatasetDropdown()

    studio = guidata(fig);
    dd = findobj(fig,'Tag','datasetDropdown');

    if isempty(dd)
        return;
    end

    names = fieldnames(studio.datasets);

    if isempty(names)
        set(dd,'String',{'<none>'},'Value',1);
        return;
    end

    set(dd,'String',names);

    % Keep current active dataset if still valid
    idx = find(strcmp(names, studio.activeDataset),1);

    if isempty(idx)
        idx = 1;
        studio.activeDataset = names{1};
    end

    set(dd,'Value',idx);

    % Update active dataset label
    if isfield(studio,'activeDatasetText') && isgraphics(studio.activeDatasetText)
        set(studio.activeDatasetText, ...
            'String',['ACTIVE DATASET: ' studio.activeDataset]);
    end

    guidata(fig, studio);

end

%% ---------------------------------------------------------
%  INLINE IF FUNCTION (MATLAB has no built-in iff)
% ---------------------------------------------------------
function out = iff(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end

%% ---------------------------------------------------------
%  SELECT ACTIVE DATASET (List dialog)
% ---------------------------------------------------------
function selectActiveDataset()

    studio = guidata(gcbf);
    names = fieldnames(studio.datasets);

    if isempty(names)
        addLog('No datasets available to select.');
        return;
    end

    [idx,tf] = listdlg( ...
        'PromptString','Select dataset', ...
        'SelectionMode','single', ...
        'ListString',names, ...
        'ListSize',[350 300]);

    if tf
        studio.activeDataset = names{idx};
        guidata(gcbf,studio);

        % update dropdown as well
        dd = findobj(gcbf,'Tag','datasetDropdown');
        if ~isempty(dd)
            set(dd,'Value',idx);
        end

        addLog(['Active dataset set to: ' names{idx}]);
    else
        addLog('Dataset selection cancelled.');
    end
end



%% ---------------------------------------------------------
%  GET ACTIVE DATASET  (SAFE LAZY LOAD)
% ---------------------------------------------------------
function data = getActiveData()

    studio = guidata(gcbf);
    selected = studio.activeDataset;

    if isempty(selected)
        error('No active dataset selected.');
    end

    data = studio.datasets.(selected);

    % -------------------------------------------------
    % LAZY LOAD ONLY IF NEEDED
    % -------------------------------------------------
    if isstruct(data) && isfield(data,'isLazy') && data.isLazy

        addLog(['Loading dataset from disk: ' selected]);
        setProgramStatus(false);
        drawnow;

        try
            m = matfile(data.lazyFile);

            tmp = m.newData;   % load full struct once
            data = tmp;

            % IMPORTANT: clear lazy flag
            data.isLazy = false;

            % store fully loaded data back
            studio.datasets.(selected) = data;
            guidata(gcbf, studio);

            addLog(['Dataset loaded: ' selected]);

        catch ME
            addLog(['Lazy load ERROR: ' ME.message]);
            setProgramStatus(true);
            rethrow(ME);
        end

        setProgramStatus(true);
    end
end



%% ---------------------------------------------------------
%  UNLOCK ALL BUTTONS AFTER LOAD
% ---------------------------------------------------------
function unlockAllButtons()

    studio = guidata(gcbf);

    % Safety: ensure allButtons exists and is a cell array
    if ~isfield(studio,'allButtons') || isempty(studio.allButtons)
        return;
    end

    for i = 1:length(studio.allButtons)

        % retrieve stored handle
        h = studio.allButtons{i};

        % validate handle
        if ~isempty(h) && ishghandle(h)
            try
                set(h, ...
                    'Enable','on', ...
                    'BackgroundColor',[0.25 0.25 0.25]);
            catch
                % If a button was deleted accidentally, skip
            end
        end
    end

    guidata(gcbf, studio);
end



%% ---------------------------------------------------------
%  LOAD ANATOMY FILE (nii / nii.gz / mat)
% ---------------------------------------------------------
function anatomy = loadAnatomy(path)

    [~,~,ext] = fileparts(path);
    ext = lower(ext);

    switch ext

        case '.nii'
            info = niftiinfo(path);
            anatomy = niftiread(info);

        case '.gz'
            info = niftiinfo(path);   % MATLAB handles .nii.gz
            anatomy = niftiread(info);

        case '.mat'
            S = load(path);
            fn = fieldnames(S);

            % Priorities
            if isfield(S,'anatomy')
                anatomy = S.anatomy;
            elseif isfield(S,'meanVol')
                anatomy = S.meanVol;
            elseif isfield(S,'I')
                anatomy = mean(S.I,4);
            else
                anatomy = S.(fn{1});
            end

        otherwise
            error(['Unsupported anatomy file type: ' ext]);
    end

    anatomy = double(anatomy);
end



%% ---------------------------------------------------------
%  EXPORT Log Session
% ---------------------------------------------------------
function exportSessionCallback(~,~)

    studio = guidata(gcbf);

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

    % Auto-save into analysed folder
    ts = datestr(now,'yyyymmdd_HHMMSS');
    outFile = fullfile(studio.exportPath, ...
                      ['StudioLog_' ts '.txt']);

    fid = fopen(outFile,'w');
    for i = 1:numel(logContent)
        fprintf(fid,'%s\n',logContent{i});
    end
    fclose(fid);

    addLog(['Studio log exported ? ' outFile]);

end

%% ---------------------------------------------------------
%  Help Button
% ---------------------------------------------------------
function helpCallback(~,~)

% =========================================================
%  fUSI STUDIO - COMPLETE USER GUIDE (STABLE VERSION)
% =========================================================

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

% =========================================================
% FULL GUIDE TEXT
% =========================================================

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
'Internally all datasets are stored as:'
'  I(Y, X, Z, T)'
''
'When loading a dataset, the system automatically:'
'  - Extracts TR (temporal resolution)'
'  - Computes number of volumes'
'  - Computes total acquisition time'
'  - Detects probe type (2D or 3D)'
'  - Creates a mirrored AnalysedData folder'
'  - Creates subfolders:'
'       QC'
'       Preprocessing'
'       PSC'
'       Visualization'
''
''
'==========================================================================='
'1. DATASET'
'==========================================================================='
''
'Load fUSI Data'
'  Loads .mat or .nii files.'
'  Reads metadata and stores raw dataset as "raw".'
''
'Dataset Dropdown'
'  Switch between raw and all processed versions.'
'  Lazy loading ensures memory efficiency.'
''
''
'==========================================================================='
'2. QUALITY CONTROL (QC)'
'==========================================================================='
''
'Full QC runs all diagnostics automatically.'
''
'Frequency QC'
'  Uses Fast Fourier Transform (FFT).'
'  Identifies oscillatory artifacts and instability.'
''
'Spatial QC'
'  Computes mean and variance maps across time.'
''
'Temporal QC'
'  Detects drift and slow fluctuations.'
''
'PCA QC'
'  Singular Value Decomposition:'
'     X = U * S * V^T'
'  Evaluates dominant variance components.'
''
''
'==========================================================================='
'3. RECOMMENDED PROCESSING STEPS'
'==========================================================================='
''
'Frame Rejection'
'  Detects global intensity outliers.'
'  Optional interpolation replaces unstable volumes.'
''
'Scrubbing (rDVARS)'
'  DVARS(t) = sqrt(mean((V_t - V_(t-1))^2))'
''
'  Threshold rule:'
'     TH = median(DVARS) + k * MAD'
''
'  Flagged volumes are linearly interpolated.'
''
''
'==========================================================================='
'4. ADVANCED PROCESSING'
'==========================================================================='
''
'Percent Signal Change (PSC)'
'  PSC = 100 * (S - baseline) / baseline'
''
'Filtering'
'  Temporal bandpass filtering.'
'  Removes physiological and slow drift noise.'
''
'Despiking'
'  Voxel-wise Median Absolute Deviation (MAD) method.'
'  z = (x - median) / MAD'
''
'PCA Denoising'
'  Principal Component Analysis.'
'  Interactive component removal.'
'  Reconstruction suppresses structured noise.'
''
''
'==========================================================================='
'5. VISUALIZATION'
'==========================================================================='
''
'Live Viewer'
'  Dynamic slice visualization.'
''
'SCM (Slice Correlation Map)'
'  Computes correlation structure across regions.'
''
'Video & Mask'
'  Overlay PSC onto anatomical reference.'
''
''
'==========================================================================='
'6. COREGISTRATION'
'==========================================================================='
''
'Atlas Registration'
'  Affine transformation: translation, rotation, scaling.'
'  Aligns functional data to anatomical atlas.'
''
''
'==========================================================================='
'7. ADVANCED ANALYSIS'
'==========================================================================='
''
'Functional Connectivity'
'  Correlation matrix between voxels or ROIs.'
''
'Group Analysis'
'  Multi-session comparison and statistical evaluation.'
''
''
'==========================================================================='
'RECOMMENDED WORKFLOW'
'==========================================================================='
''
'1) Load Data'
'2) Run Full QC'
'3) Apply Frame Rejection or Scrubbing'
'4) Compute PSC'
'5) Optional PCA or Despike'
'6) Visualization'
'7) Connectivity or Group Analysis'
''
'==========================================================================='
};

set(txtBox,'String',strjoin(guide,newline));

end


%% ---------------------------------------------------------
%  LOGGING UTILITY
% ---------------------------------------------------------
function addLog(msg)

    logBox = findobj(gcbf,'Style','listbox');

    if isempty(logBox)
        return;
    end

    current = get(logBox,'String');

    if ~iscell(current)
        current = {current};
    end

    timestamp = datestr(now,'HH:MM:SS');
    newEntry = sprintf('[%s] %s',timestamp,msg);

    set(logBox,'String',[current; {newEntry}]);
    drawnow;
end



%% ---------------------------------------------------------
%  STATUS BAR HANDLER
% ---------------------------------------------------------
function setProgramStatus(isReady)

    studio = guidata(fig);
    statusPanel = studio.statusPanel;
    statusText  = studio.statusText;

    % Colors
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


    % Apply colors without MATLAB overriding them
    set(statusPanel,...
        'BackgroundColor',bg,...
        'HighlightColor',bg,...   % Prevent white edging
        'ShadowColor',bg);        % Prevent white edging

    set(statusText,...
        'BackgroundColor',bg,...
        'ForegroundColor',fg,...
        'String',txt,...
        'FontWeight','bold',...
        'FontSize',16);

    drawnow;
end
%% =========================================================
%  SECTION D — VISUALIZATION CALLBACKS (STABLE VERSION)
% =========================================================


%% ---------------------------------------------------------
%  SIGNAL SELECTION DIALOG
% ---------------------------------------------------------
function signalType = selectSignalDialog()

    choices = {'RAW (I)','PSC','Preprocessed (Gabriel)'};

    [idx, tf] = listdlg( ...
        'PromptString','Select signal to visualize:', ...
        'ListString',choices, ...
        'SelectionMode','single', ...
        'ListSize',[300 150]);

    if ~tf
        signalType = '';
    else
        signalType = choices{idx};
    end

end


%% ---------------------------------------------------------
%  LIVE VIEWER CALLBACK
% ---------------------------------------------------------

function liveViewerCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    if isfield(data,'PSC')
        I = double(data.PSC);
    else
        I = double(data.I);
    end

    addLog(['Opening Live Viewer (Dataset: ' studio.activeDataset ')']);

    setProgramStatus(false);
    drawnow;

    try
        viewerFig = fUSI_Live_Studio(I, data.TR, studio.meta, studio.activeDataset);

        addlistener(viewerFig,'ObjectBeingDestroyed', ...
            @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Live Viewer ERROR: ' ME.message]);
        errordlg(ME.message,'Live Viewer Failed');
        setProgramStatus(true);
    end
end


%% ---------------------------------------------------------
%  SCM GUI CALLBACK (SAFE MINIMAL VERSION)
% ---------------------------------------------------------
function scmCallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    par = struct();
    par.interpol = 1;
    par.previewCaxis = [];

    baseline = struct('start',0,'end',10,'mode','sec');

    if isfield(data,'PSC')
        PSCsig = double(data.PSC);
        bg     = double(data.bg);
    else
        proc = computePSC(double(data.I), data.TR, par, baseline);
        PSCsig = double(proc.PSC);
        bg     = double(proc.bg);
    end

    addLog(['Opening SCM GUI (Dataset: ' studio.activeDataset ')']);

    setProgramStatus(false);
    drawnow;

    try
        scmFig = SCM_gui( ...
            PSCsig, bg, data.TR, par, baseline, ...
            data.I, data.I, ...
            10, 240, ...
            [], false, struct(), ...
            studio.activeDataset);

        addlistener(scmFig,'ObjectBeingDestroyed', ...
            @(~,~) setProgramStatus(true));

    catch ME
        addLog(['SCM ERROR: ' ME.message]);
        errordlg(ME.message,'SCM Failed');
        setProgramStatus(true);
    end
end



%% ---------------------------------------------------------
%  VIDEO GUI CALLBACK (CLEAN + CORRECT)
% ---------------------------------------------------------
 %% ---------------------------------------------------------
%  VIDEO GUI CALLBACK (ACTIVE DATASET ONLY)
%% ---------------------------------------------------------
function videoGUICallback(~,~)

    studio = guidata(gcbf);

    if ~studio.isLoaded
        errordlg('Load data first.');
        return;
    end

    data = getActiveData();

    addLog(['Opening Video GUI (Dataset: ' studio.activeDataset ')']);

    % -------- Baseline dialog (seconds) --------
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

    % -------- Define processing parameters --------
    par = struct();
    par.interpol = 1;
    par.LPF = 0;
    par.HPF = 0;
    par.gaussSize = 0;
    par.gaussSig = 0;
    par.previewCaxis = [];
    par.caxis = [];

    % -------- Use ACTIVE dataset only --------
    Iraw = double(data.I);

    if isfield(data,'PSC')
        PSCsig = double(data.PSC);
        bg     = double(data.bg);
    else
        proc   = computePSC(Iraw, data.TR, par, baseline);
        PSCsig = double(proc.PSC);
        bg     = double(proc.bg);
    end

    Iinterp = Iraw;

    initialFPS = 10;
    maxFPS     = 240;

    % -------- Mask handling --------
    if isfield(studio,'mask')
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

        addlistener(videoFig,'ObjectBeingDestroyed', ...
            @(~,~) setProgramStatus(true));

    catch ME
        addLog(['Video GUI ERROR: ' ME.message]);
        errordlg(ME.message,'Video GUI Failed');
        setProgramStatus(true);
    end

end
end