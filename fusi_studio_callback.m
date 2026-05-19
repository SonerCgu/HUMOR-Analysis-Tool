function out = fusi_studio_callback(action)
% fusi_studio_callback - callback/helper source part 2 of the split Studio
%
% This is a valid MATLAB file that stores one source chunk for the split
% HUMoR / fUSI Studio. Run run_fusi_studio.m to assemble and launch.

if nargin == 0
    run_fusi_studio;
    if nargout > 0
        out = [];
    end
    return;
end

if ischar(action) && strcmpi(action,'source')
    out = localExtractSource(mfilename('fullpath'));
else
    error('HUMoR:SplitSource','Unknown action. Use run_fusi_studio.m to launch.');
end

end

function txt = localExtractSource(thisFile)
raw = fileread([thisFile '.m']);
startMarker = '%%%FUSI_STUDIO_SOURCE_BEGIN%%%';
endMarker   = '%%%FUSI_STUDIO_SOURCE_END%%%';
a = strfind(raw,startMarker);
b = strfind(raw,endMarker);
if isempty(a) || isempty(b) || b(1) <= a(1)
    error('HUMoR:SplitSource','Could not find embedded source markers in %s.m', thisFile);
end
a = a(end) + length(startMarker);
b = b(end) - 1;
txt = raw(a:b);
% Remove one leading newline after marker if present.
if ~isempty(txt) && (txt(1) == sprintf('\n') || txt(1) == sprintf('\r'))
    txt = regexprep(txt,'^\r?\n','', 'once');
end
end

%{
%%%FUSI_STUDIO_SOURCE_BEGIN%%%
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
T = HUMOR_FC_read_region_names_file(fullFile);
if isempty(T.labels)
    error('Could not parse region names from selected file.');
end
end
% =========================================================
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
par.selectorRoot = studio.exportPath;

par.visualizationPath = fullfile(studio.exportPath,'Visualization');
par.registrationPath   = fullfile(studio.exportPath,'Registration');
par.registration2DPath = fullfile(studio.exportPath,'Registration2D');

par.maskStartPath      = par.visualizationPath;
par.underlayStartPath  = par.registration2DPath;
par.transformStartPath = par.registration2DPath;
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
% Resolve underlay from SCM/Video setup popup
% -----------------------------------------------------
underlayInfo = scmVideoEmptyUnderlayInfo();

if isfield(launchCfg,'precomputedUnderlayDisplay') && ...
        ~isempty(launchCfg.precomputedUnderlayDisplay)

    bgUnderlay = launchCfg.precomputedUnderlayDisplay;

    if isfield(launchCfg,'underlayLabel') && ~isempty(launchCfg.underlayLabel)
        underlayLabel = launchCfg.underlayLabel;
    else
        underlayLabel = 'Selected underlay';
    end

    % IMPORTANT:
    % If showScmVideoSetupDialog created detailed underlayInfo
    % for Step Motor Registration2D, preserve it here.
    if isfield(launchCfg,'underlayInfo') && ...
            isstruct(launchCfg.underlayInfo) && ...
            isfield(launchCfg.underlayInfo,'mode') && ...
            ~isempty(launchCfg.underlayInfo.mode)

        underlayInfo = launchCfg.underlayInfo;

    else
        % Backward-compatible fallback for older launchCfg outputs.
        underlayInfo = scmVideoEmptyUnderlayInfo();
        underlayInfo.label = underlayLabel;
        underlayInfo.isDisplayReady = true;

        if isfield(launchCfg,'underlayChoice')
            switch launchCfg.underlayChoice
                case 2
                    underlayInfo.mode = 'step_motor_registration2D';
                    underlayInfo.selectedFile = underlayLabel;

                case 4
                    underlayInfo.mode = 'external_registration2D_file_preloaded';
                    underlayInfo.selectedFile = underlayLabel;

                case 5
                    underlayInfo.mode = 'recommended_standard_mask_editor_style';
                    underlayInfo.isDisplayReady = true;

                otherwise
                    underlayInfo.mode = 'precomputed_underlay';
            end
        else
            underlayInfo.mode = 'precomputed_underlay';
        end
    end

else

    [bgUnderlay, underlayLabel, underlayInfo] = resolveScmVideoUnderlayChoice( ...
        studio, data, bgDefault, launchCfg.underlayChoice);
end

if isempty(bgUnderlay)
    addLog([winTitleForLog() ' cancelled (no underlay selected).']);
    return;
end

par.scmInitialUnderlayInfo = underlayInfo;
if isstruct(underlayInfo) && isfield(underlayInfo,'isMulti') && underlayInfo.isMulti
    par.scmPerSliceUnderlayFiles = underlayInfo.files;
    par.scmPerSliceUnderlaySourceIdx = underlayInfo.sourceIdx;
    par.scmInitialUnderlayMode = underlayInfo.mode;

    addLog(sprintf('SCM per-slice underlay mode: %d files selected.', numel(underlayInfo.files)));

    for uu = 1:numel(underlayInfo.files)
        addLog(sprintf('  Slice/source %d -> %s', underlayInfo.sourceIdx(uu), underlayInfo.files{uu}));
    end
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

if isempty(launchCfg) || ~isstruct(launchCfg) || ...
        ~isfield(launchCfg,'cancelled') || launchCfg.cancelled
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
par.selectorRoot = studio.exportPath;

par.visualizationPath = fullfile(studio.exportPath,'Visualization');
par.registrationPath   = fullfile(studio.exportPath,'Registration');
par.registration2DPath = fullfile(studio.exportPath,'Registration2D');

par.maskStartPath      = par.visualizationPath;
par.underlayStartPath  = par.registration2DPath;
par.transformStartPath = par.registration2DPath;
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

% -----------------------------------------------------
% Resolve underlay from SCM/Video setup popup
% -----------------------------------------------------
underlayInfo = scmVideoEmptyUnderlayInfo();

if isfield(launchCfg,'precomputedUnderlayDisplay') && ...
        ~isempty(launchCfg.precomputedUnderlayDisplay)

    bgUnderlay = launchCfg.precomputedUnderlayDisplay;

    if isfield(launchCfg,'underlayLabel') && ~isempty(launchCfg.underlayLabel)
        underlayLabel = launchCfg.underlayLabel;
    else
        underlayLabel = 'Selected underlay';
    end

    % IMPORTANT:
    % If showScmVideoSetupDialog created detailed underlayInfo
    % for Step Motor Registration2D, preserve it here.
    if isfield(launchCfg,'underlayInfo') && ...
            isstruct(launchCfg.underlayInfo) && ...
            isfield(launchCfg.underlayInfo,'mode') && ...
            ~isempty(launchCfg.underlayInfo.mode)

        underlayInfo = launchCfg.underlayInfo;

    else
        % Backward-compatible fallback for older launchCfg outputs.
        underlayInfo = scmVideoEmptyUnderlayInfo();
        underlayInfo.label = underlayLabel;
        underlayInfo.isDisplayReady = true;

        if isfield(launchCfg,'underlayChoice')
            switch launchCfg.underlayChoice
                case 2
                    underlayInfo.mode = 'step_motor_registration2D';
                    underlayInfo.selectedFile = underlayLabel;

                case 4
                    underlayInfo.mode = 'external_registration2D_file_preloaded';
                    underlayInfo.selectedFile = underlayLabel;

                case 5
                    underlayInfo.mode = 'recommended_standard_mask_editor_style';
                    underlayInfo.isDisplayReady = true;

                otherwise
                    underlayInfo.mode = 'precomputed_underlay';
            end
        else
            underlayInfo.mode = 'precomputed_underlay';
        end
    end

else

    [bgUnderlay, underlayLabel, underlayInfo] = resolveScmVideoUnderlayChoice( ...
        studio, data, bgDefault, launchCfg.underlayChoice);
end

if isempty(bgUnderlay)
    addLog([winTitleForLog() ' cancelled (no underlay selected).']);
    return;
end

par.scmInitialUnderlayInfo = underlayInfo;

if isstruct(underlayInfo) && isfield(underlayInfo,'isMulti') && underlayInfo.isMulti
    par.scmPerSliceUnderlayFiles = underlayInfo.files;
    par.scmPerSliceUnderlaySourceIdx = underlayInfo.sourceIdx;
    par.scmInitialUnderlayMode = underlayInfo.mode;

    addLog(sprintf('Video GUI per-slice underlay mode: %d files selected.', numel(underlayInfo.files)));

    for uu = 1:numel(underlayInfo.files)
        addLog(sprintf('  Slice/source %d -> %s', underlayInfo.sourceIdx(uu), underlayInfo.files{uu}));
    end
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
            'String',['DATASET: ' showName], ...
            'TooltipString',['DATASET: ' fullName]);
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
        labels{i} = getDatasetDisplayName(studio, k);
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
            'String',['DATASET: ' showName], ...
            'TooltipString',['DATASET: ' fullName]);
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

    try, HUMoR_popup_autofit_apply(dlg); catch, end
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

% Legacy fallback only. The interactive TR choice is now handled by
% studio_load_options_dark_dialog during dataset loading.
[probeType, defaultTR] = detectProbeTypeFromMeta(data, meta);
    defaultTR = studio_probe_default_tr_seconds(probeType, data);
TR = defaultTR;
wasCancelled = false;

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

    label = shortenMiddle(label, 45);
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

function cfg = showScmVideoSetupDialog(winTitle, defaultBaseStart, defaultBaseEnd, defaultChoice, studio, I)

    cfg = struct();
    cfg.cancelled = true;
    cfg.baselineStart = defaultBaseStart;
    cfg.baselineEnd   = defaultBaseEnd;
    cfg.underlayChoice = defaultChoice;
    cfg.precomputedUnderlayDisplay = [];
    cfg.underlayLabel = '';
    cfg.recommendedStyle = scmVideoDefaultRecommendedStyle();
cfg.underlayInfo = scmVideoEmptyUnderlayInfo();
cfg.stepMotorUnderlayKind = 'histology';
    if nargin < 4 || isempty(defaultChoice)
        defaultChoice = 5;
    end

    defaultChoice = max(1,min(5,round(defaultChoice)));

 loadedFileUnderlay = [];
loadedFileLabel = '';
loadedFileInfo = scmVideoEmptyUnderlayInfo();

stepMotorUnderlayKind = 'histology';

    recStyle = scmVideoDefaultRecommendedStyle();

    sz = size(I);
    nd = ndims(I);

    if nd == 3
        dimTxt = sprintf('%d x %d x %d', sz(1), sz(2), sz(3));
    elseif nd >= 4
        dimTxt = sprintf('%d x %d x %d x %d', sz(1), sz(2), sz(3), sz(4));
    else
        dimTxt = mat2str(sz);
    end

    datasetTxt = 'Active dataset detected.';
    try
        if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
            datasetTxt = ['Active dataset: ' getDatasetDisplayName(studio, studio.activeDataset)];
        end
    catch
    end

    startDirTxt = scmVideoGetRegistration2DStartDir(studio);

    bg      = [0.045 0.045 0.052];
    panel   = [0.085 0.085 0.098];
    panel2  = [0.120 0.120 0.135];
    panel3  = [0.060 0.060 0.070];
    fg      = [0.96 0.96 0.96];
    fgDim   = [0.74 0.76 0.80];
    blue    = [0.20 0.48 0.95];
    green   = [0.14 0.68 0.34];
    red     = [0.78 0.24 0.24];
    orange  = [0.95 0.58 0.18];
    yellow  = [0.95 0.84 0.35];

    dlg = figure( ...
        'Name',[winTitle ' Setup'], ...
        'Color',bg, ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off', ...
        'Resize','off', ...
        'Units','pixels', ...
        'Position',[40 20 1500 930], ...
        'WindowStyle','modal', ...
        'Visible','off', ...
        'CloseRequestFcn',@onCancel, ...
        'KeyPressFcn',@onKey);

    try
        movegui(dlg,'center');
    catch
    end

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.940 0.93 0.040], ...
        'String',[winTitle ' Setup'], ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',28, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.037 0.905 0.93 0.030], ...
        'String','Choose baseline, underlay source, and Recommended Standard display parameters before opening SCM / Video.', ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    infoPanel = uipanel('Parent',dlg, ...
        'Units','normalized', ...
        'Position',[0.035 0.815 0.93 0.075], ...
        'BackgroundColor',panel3, ...
        'ForegroundColor',[0.35 0.35 0.38], ...
        'BorderType','line');

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.025 0.52 0.95 0.34], ...
        'String',shortenMiddle(datasetTxt,150), ...
        'TooltipString',datasetTxt, ...
        'BackgroundColor',panel3, ...
        'ForegroundColor',[0.45 1.00 0.62], ...
        'FontName','Arial', ...
        'FontSize',14, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',infoPanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.025 0.13 0.95 0.32], ...
        'String',sprintf('Input size: %s     |     Registration2D folder: %s', dimTxt, startDirTxt), ...
        'TooltipString',startDirTxt, ...
        'BackgroundColor',panel3, ...
        'ForegroundColor',[0.72 0.86 1.00], ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    basePanel = uipanel('Parent',dlg, ...
        'Title','Baseline window', ...
        'Units','normalized', ...
        'Position',[0.035 0.670 0.93 0.120], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'BorderType','line');

    makeLabel(basePanel,[0.035 0.47 0.21 0.28],'Baseline START (sec)',14,fg);
    edBaseStart = makeEdit(basePanel,[0.255 0.49 0.13 0.28],num2str(defaultBaseStart));

    makeLabel(basePanel,[0.420 0.47 0.19 0.28],'Baseline END (sec)',14,fg);
    edBaseEnd = makeEdit(basePanel,[0.615 0.49 0.13 0.28],num2str(defaultBaseEnd));

    uicontrol('Parent',basePanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.770 0.18 0.20 0.62], ...
        'String',{'Default: 30-240 sec', 'Change only if needed.'}, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',yellow, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    underPanel = uipanel('Parent',dlg, ...
        'Title','Startup underlay source', ...
        'Units','normalized', ...
        'Position',[0.035 0.270 0.50 0.375], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'BorderType','line');

    bgGroup = uibuttongroup('Parent',underPanel, ...
        'Units','normalized', ...
        'Position',[0.025 0.055 0.95 0.89], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','none', ...
        'SelectionChangedFcn',@onUnderlaySelectionChanged);

    rb = zeros(1,5);

  labels = { ...
    'Default current reference bg from PSC', ...
    'Step Motor Registration2D per-slice underlay', ...
    'Median of ACTIVE dataset', ...
    'Select external underlay / histology from Registration2D', ...
    'Recommended Standard - same logic as Mask Editor'};

descriptions = { ...
    'Fast fallback. Uses the bg created during computePSC.', ...
    'For step-motor: choose histology / vascular / regions and load several source folders.', ...
    'Computes robust median from the current active dataset.', ...
    'Manual single underlay file selection. Good for one histology image.', ...
    'Mean(T) -> standardized Doppler equalized -> fixed window -> display FX.'};

    yVals = [0.81 0.62 0.43 0.24 0.05];

    for ii = 1:5
        rb(ii) = uicontrol('Parent',bgGroup,'Style','radiobutton', ...
            'Units','normalized', ...
            'Position',[0.025 yVals(ii)+0.055 0.93 0.085], ...
            'String',labels{ii}, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',14, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left', ...
            'UserData',ii);

        uicontrol('Parent',bgGroup,'Style','text', ...
            'Units','normalized', ...
            'Position',[0.070 yVals(ii)-0.005 0.88 0.060], ...
            'String',descriptions{ii}, ...
            'BackgroundColor',panel, ...
            'ForegroundColor',fgDim, ...
            'FontName','Arial', ...
            'FontSize',11, ...
            'HorizontalAlignment','left');
    end

    set(bgGroup,'SelectedObject',rb(defaultChoice));

    stylePanel = uipanel('Parent',dlg, ...
        'Title','Recommended Standard parameters', ...
        'Units','normalized', ...
        'Position',[0.555 0.270 0.410 0.375], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'BorderType','line');

    uicontrol('Parent',stylePanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.040 0.895 0.920 0.060], ...
        'String','These match Mask Editor mode 7. Change here only if you want a different SCM/Video startup look.', ...
        'BackgroundColor',panel, ...
        'ForegroundColor',yellow, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    makeLabel(stylePanel,[0.045 0.760 0.180 0.060],'Std low',13,fg);
    edStdLow = makeEdit(stylePanel,[0.235 0.755 0.120 0.075],num2str(recStyle.stdLow,'%.2f'));

    makeLabel(stylePanel,[0.390 0.760 0.180 0.060],'Std high',13,fg);
    edStdHigh = makeEdit(stylePanel,[0.585 0.755 0.120 0.075],num2str(recStyle.stdHigh,'%.2f'));

    makeLabel(stylePanel,[0.735 0.760 0.100 0.060],'Gain',13,fg);
    edGain = makeEdit(stylePanel,[0.835 0.755 0.110 0.075],num2str(recStyle.stdGain,'%.2f'));

    makeLabel(stylePanel,[0.045 0.615 0.180 0.060],'Brightness',13,fg);
    edBright = makeEdit(stylePanel,[0.235 0.610 0.120 0.075],num2str(recStyle.brightness,'%.2f'));

    makeLabel(stylePanel,[0.390 0.615 0.180 0.060],'Contrast',13,fg);
    edContrast = makeEdit(stylePanel,[0.585 0.610 0.120 0.075],num2str(recStyle.contrast,'%.2f'));

    makeLabel(stylePanel,[0.735 0.615 0.100 0.060],'Gamma',13,fg);
    edGamma = makeEdit(stylePanel,[0.835 0.610 0.110 0.075],num2str(recStyle.gamma,'%.2f'));

    makeLabel(stylePanel,[0.045 0.470 0.180 0.060],'Sharpness',13,fg);
    edSharp = makeEdit(stylePanel,[0.235 0.465 0.120 0.075],num2str(recStyle.sharpness,'%.2f'));

    hSoftTone = uicontrol('Parent',stylePanel,'Style','checkbox', ...
        'Units','normalized', ...
        'Position',[0.390 0.465 0.300 0.075], ...
        'String','Soft tone', ...
        'Value',double(recStyle.softToneEnable), ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold');

    makeLabel(stylePanel,[0.705 0.470 0.130 0.060],'Strength',13,fg);
    edSoftTone = makeEdit(stylePanel,[0.835 0.465 0.110 0.075],num2str(recStyle.softToneStrength,'%.2f'));

    uicontrol('Parent',stylePanel,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.045 0.285 0.900 0.105], ...
        'String',{'Mask Editor defaults:', ...
                  'stdLow 0.40 | stdHigh 0.80 | gain 2.00 | brightness 0.10 | contrast 0.50 | gamma 1.10 | sharpness 75 | soft tone 0.40'}, ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fgDim, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',stylePanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.045 0.115 0.410 0.105], ...
        'String','RESET MASK EDITOR DEFAULTS', ...
        'BackgroundColor',blue, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@onResetRecommendedDefaults);

    uicontrol('Parent',stylePanel,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.535 0.115 0.410 0.105], ...
        'String','USE RECOMMENDED', ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'FontWeight','bold', ...
        'Callback',@onRecommendedPreset);

    filePanel = uipanel('Parent',dlg, ...
        'Title','Manual file loading', ...
        'Units','normalized', ...
        'Position',[0.035 0.165 0.930 0.080], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',14, ...
        'FontWeight','bold', ...
        'BorderType','line');

    txtUnderlayStatus = uicontrol('Parent',filePanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.025 0.18 0.450 0.55], ...
    'String','No Step Motor / external underlay loaded yet.', ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',filePanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.490 0.62 0.120 0.25], ...
    'String','Step kind', ...
    'BackgroundColor',panel, ...
    'ForegroundColor',yellow, ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

hStepKind = uicontrol('Parent',filePanel,'Style','popupmenu', ...
    'Units','normalized', ...
    'Position',[0.490 0.18 0.120 0.45], ...
    'String',{'histology','vascular','regions'}, ...
    'Value',1, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@onStepKindChanged);

uicontrol('Parent',filePanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.625 0.18 0.205 0.58], ...
    'String','LOAD / AUTO-FIND', ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'Callback',@onManualLoadUnderlay);

uicontrol('Parent',filePanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.845 0.18 0.130 0.55], ...
    'String','Step mode: select parent folder, then subfolders.', ...
    'BackgroundColor',panel, ...
    'ForegroundColor',yellow, ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

    txtStatus = uicontrol('Parent',dlg,'Style','text', ...
        'Units','normalized', ...
        'Position',[0.035 0.085 0.930 0.060], ...
        'String','', ...
        'BackgroundColor',[0.030 0.030 0.036], ...
        'ForegroundColor',[0.70 1.00 0.80], ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.500 0.025 0.260 0.045], ...
        'String',['OPEN ' upper(winTitle)], ...
        'BackgroundColor',green, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'Callback',@onOpen);

    uicontrol('Parent',dlg,'Style','pushbutton', ...
        'Units','normalized', ...
        'Position',[0.790 0.025 0.175 0.045], ...
        'String','CANCEL', ...
        'BackgroundColor',red, ...
        'ForegroundColor','w', ...
        'FontName','Arial', ...
        'FontSize',15, ...
        'FontWeight','bold', ...
        'Callback',@onCancel);

    setStatusForChoice(defaultChoice);

    set(dlg,'Visible','on');
    try, HUMoR_popup_autofit_apply(dlg); catch, end
    waitfor(dlg);

    function h = makeLabel(parent,pos,str,fs,col)
        h = uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',pos, ...
            'String',str, ...
            'BackgroundColor',get(parent,'BackgroundColor'), ...
            'ForegroundColor',col, ...
            'FontName','Arial', ...
            'FontSize',fs, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function h = makeEdit(parent,pos,str)
        h = uicontrol('Parent',parent,'Style','edit', ...
            'Units','normalized', ...
            'Position',pos, ...
            'String',str, ...
            'BackgroundColor',panel2, ...
            'ForegroundColor',fg, ...
            'FontName','Arial', ...
            'FontSize',14, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','center');
    end

    function onUnderlaySelectionChanged(~,event)
        try
            selectedIdx = get(event.NewValue,'UserData');
        catch
            selectedIdx = defaultChoice;
        end

        cfg.underlayChoice = selectedIdx;
        setStatusForChoice(selectedIdx);
    end

    function setStatusForChoice(idx)
    switch idx
        case 1
            setStatus('Default bg selected. Fast fallback.', [0.70 1.00 0.80]);

        case 2
            stepMotorUnderlayKind = getStepKindFromPopup();
            setStatus(['Step Motor Registration2D selected. Kind = ' stepMotorUnderlayKind ...
                '. Click LOAD / AUTO-FIND, or it will ask on Open.'], [0.78 0.90 1.00]);

        case 3
            setStatus('Median active dataset selected. It will be computed on Open.', [0.70 1.00 0.80]);

        case 4
            setStatus('Single external underlay selected. Click LOAD / AUTO-FIND, or it will ask on Open.', [0.78 0.90 1.00]);

        case 5
            setStatus('Recommended Standard selected. This uses the same calculation as Mask Editor standardized mode.', [0.70 1.00 0.80]);

        otherwise
            setStatus('Ready.', [0.70 1.00 0.80]);
    end
end
function kind = getStepKindFromPopup()
    kindList = get(hStepKind,'String');
    kind = kindList{get(hStepKind,'Value')};
    kind = lower(strtrim(kind));
end

function onStepKindChanged(~,~)
    stepMotorUnderlayKind = getStepKindFromPopup();
    cfg.stepMotorUnderlayKind = stepMotorUnderlayKind;

    selectedObj = get(bgGroup,'SelectedObject');
    selectedIdx = get(selectedObj,'UserData');

    if selectedIdx == 2
        setStatus(['Step Motor Registration2D selected: ' stepMotorUnderlayKind], [0.78 0.90 1.00]);
    end
end
    function onManualLoadUnderlay(~,~)

    selectedObj = get(bgGroup,'SelectedObject');
    selectedIdx = get(selectedObj,'UserData');

    try
        if selectedIdx == 2

            stepMotorUnderlayKind = getStepKindFromPopup();
            cfg.stepMotorUnderlayKind = stepMotorUnderlayKind;

            [U,labelText,ok,info] = scmVideoAskAndLoadStepMotorRegistration2D( ...
                studio, I, stepMotorUnderlayKind);

        elseif selectedIdx == 4

            [U,labelText,ok] = scmVideoAskAndLoadUnderlayFromRegistration2D(studio, I, 'external');

            info = scmVideoEmptyUnderlayInfo();
            info.mode = 'external_registration2D_file_preloaded';
            info.label = labelText;
            info.selectedFile = labelText;
            info.isMulti = false;
            info.isDisplayReady = true;

        else

            set(bgGroup,'SelectedObject',rb(2));
            cfg.underlayChoice = 2;

            stepMotorUnderlayKind = getStepKindFromPopup();
            cfg.stepMotorUnderlayKind = stepMotorUnderlayKind;

            [U,labelText,ok,info] = scmVideoAskAndLoadStepMotorRegistration2D( ...
                studio, I, stepMotorUnderlayKind);
        end

        if ~ok || isempty(U)
            loadedFileUnderlay = [];
            loadedFileLabel = '';
            loadedFileInfo = scmVideoEmptyUnderlayInfo();

            set(txtUnderlayStatus,'String','No underlay loaded.');
            setStatus('No underlay loaded.', orange);
            return;
        end

        loadedFileUnderlay = U;
        loadedFileLabel = labelText;
        loadedFileInfo = info;

        set(txtUnderlayStatus,'String',shortenMiddle(['Loaded: ' labelText],90));
        setStatus(['Loaded underlay: ' labelText], [0.70 1.00 0.80]);

    catch ME
        loadedFileUnderlay = [];
        loadedFileLabel = '';
        loadedFileInfo = scmVideoEmptyUnderlayInfo();

        set(txtUnderlayStatus,'String','Load failed.');
        setStatus(['Underlay load failed: ' ME.message], orange);
    end
end

    function onRecommendedPreset(~,~)
        set(bgGroup,'SelectedObject',rb(5));
        cfg.underlayChoice = 5;
        setStatusForChoice(5);
    end

    function onResetRecommendedDefaults(~,~)
        recStyle = scmVideoDefaultRecommendedStyle();

        set(edStdLow,  'String',num2str(recStyle.stdLow,'%.2f'));
        set(edStdHigh, 'String',num2str(recStyle.stdHigh,'%.2f'));
        set(edGain,    'String',num2str(recStyle.stdGain,'%.2f'));

        set(edBright,   'String',num2str(recStyle.brightness,'%.2f'));
        set(edContrast, 'String',num2str(recStyle.contrast,'%.2f'));
        set(edGamma,    'String',num2str(recStyle.gamma,'%.2f'));
        set(edSharp,    'String',num2str(recStyle.sharpness,'%.2f'));

        set(hSoftTone,  'Value',double(recStyle.softToneEnable));
        set(edSoftTone, 'String',num2str(recStyle.softToneStrength,'%.2f'));

        setStatus('Mask Editor defaults restored.', [0.70 1.00 0.80]);
    end

    function style = collectRecommendedStyle()

        style = scmVideoDefaultRecommendedStyle();

        style.stdLow   = str2double(get(edStdLow,'String'));
        style.stdHigh  = str2double(get(edStdHigh,'String'));
        style.stdGain  = str2double(get(edGain,'String'));

        style.brightness = str2double(get(edBright,'String'));
        style.contrast   = str2double(get(edContrast,'String'));
        style.gamma      = str2double(get(edGamma,'String'));
        style.sharpness  = str2double(get(edSharp,'String'));

        style.softToneEnable = logical(get(hSoftTone,'Value'));
        style.softToneStrength = str2double(get(edSoftTone,'String'));

        if ~isfinite(style.stdLow)
            error('Std low must be numeric.');
        end

        if ~isfinite(style.stdHigh) || style.stdHigh <= style.stdLow
            error('Std high must be numeric and larger than Std low.');
        end

        if ~isfinite(style.stdGain)
            error('Gain must be numeric.');
        end

        style.stdGain = max(0,min(5,style.stdGain));

        if ~isfinite(style.brightness)
            error('Brightness must be numeric.');
        end

        if ~isfinite(style.contrast) || style.contrast < 0
            error('Contrast must be numeric and >= 0.');
        end

        if ~isfinite(style.gamma) || style.gamma <= 0
            error('Gamma must be numeric and > 0.');
        end

        if ~isfinite(style.sharpness)
            error('Sharpness must be numeric.');
        end

        style.sharpness = max(0,min(300,style.sharpness));

        if ~isfinite(style.softToneStrength)
            error('Soft tone strength must be numeric.');
        end

        style.softToneStrength = max(0,min(1,style.softToneStrength));
    end

    function onOpen(~,~)

        b0 = str2double(get(edBaseStart,'String'));
        b1 = str2double(get(edBaseEnd,'String'));

        if ~isfinite(b0) || b0 < 0
            setStatus('Baseline START must be a valid number >= 0.', orange);
            return;
        end

        if ~isfinite(b1) || b1 <= b0
            setStatus('Baseline END must be larger than START.', orange);
            return;
        end

        selectedObj = get(bgGroup,'SelectedObject');
        selectedIdx = get(selectedObj,'UserData');

        cfg.cancelled = false;
        cfg.baselineStart = b0;
        cfg.baselineEnd = b1;
        cfg.underlayChoice = selectedIdx;
        cfg.precomputedUnderlayDisplay = [];
        cfg.underlayLabel = '';

       if selectedIdx == 2

    if isempty(loadedFileUnderlay)

        stepMotorUnderlayKind = getStepKindFromPopup();
        cfg.stepMotorUnderlayKind = stepMotorUnderlayKind;

        [U,labelText,ok,info] = scmVideoAskAndLoadStepMotorRegistration2D( ...
            studio, I, stepMotorUnderlayKind);

        if ~ok || isempty(U)
            setStatus('No Step Motor Registration2D underlay selected. Load folders or choose Recommended Standard.', orange);
            return;
        end

        loadedFileUnderlay = U;
        loadedFileLabel = labelText;
        loadedFileInfo = info;
    end

    cfg.precomputedUnderlayDisplay = loadedFileUnderlay;
    cfg.underlayLabel = loadedFileLabel;
    cfg.underlayInfo = loadedFileInfo;

elseif selectedIdx == 4

    if isempty(loadedFileUnderlay)

        [U,labelText,ok] = scmVideoAskAndLoadUnderlayFromRegistration2D(studio, I, 'external');

        if ~ok || isempty(U)
            setStatus('No external underlay selected. Load a file or choose Recommended Standard.', orange);
            return;
        end

        loadedFileUnderlay = U;
        loadedFileLabel = labelText;

        loadedFileInfo = scmVideoEmptyUnderlayInfo();
        loadedFileInfo.mode = 'external_registration2D_file_preloaded';
        loadedFileInfo.label = labelText;
        loadedFileInfo.selectedFile = labelText;
        loadedFileInfo.isMulti = false;
        loadedFileInfo.isDisplayReady = true;
    end

    cfg.precomputedUnderlayDisplay = loadedFileUnderlay;
    cfg.underlayLabel = loadedFileLabel;
    cfg.underlayInfo = loadedFileInfo;

elseif selectedIdx == 5

    try
        recStyle = collectRecommendedStyle();

        setStatus('Computing Recommended Standard underlay with Mask Editor logic...', [0.78 0.90 1.00]);
        drawnow;

        cfg.recommendedStyle = recStyle;
        cfg.precomputedUnderlayDisplay = scmVideoMakeRecommendedStandardUnderlay(I, recStyle);
        cfg.underlayLabel = sprintf( ...
            'Recommended Standard | B%.2f C%.2f G%.2f S%.0f Tone%.2f', ...
            recStyle.brightness, recStyle.contrast, recStyle.gamma, ...
            recStyle.sharpness, recStyle.softToneStrength);

        cfg.underlayInfo = scmVideoEmptyUnderlayInfo();
        cfg.underlayInfo.mode = 'recommended_standard_mask_editor_style';
        cfg.underlayInfo.label = cfg.underlayLabel;
        cfg.underlayInfo.isDisplayReady = true;

    catch ME
        setStatus(['Recommended Standard failed: ' ME.message], orange);
        cfg.cancelled = true;
        return;
    end
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

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel();
            elseif strcmpi(ev.Key,'return')
                onOpen();
            end
        catch
        end
    end

    function setStatus(msg,col)
        if ishghandle(txtStatus)
            set(txtStatus,'String',msg,'ForegroundColor',col);
        end
    end
end
    
%% =========================================================
%  BACKWARD-COMPATIBLE MENU CHOOSER
% =========================================================
function [bg, label] = chooseSCMUnderlay(studio, data, bgDefault)

    bg = [];
    label = '';

    opts = { ...
        'Default (current SCM / Video reference bg)', ...
        'Atlas multi-slice / registered underlay from Registration2D', ...
        'Median of ACTIVE dataset (robust)', ...
        'Select external underlay file from Registration2D', ...
        'Recommended Standard (same as Mask Editor default)', ...
        'Cancel'};

    idx = menu('Choose SCM underlay image:', opts{:});

    if idx == 0 || idx == 6
        return;
    end

    [bg,label] = resolveScmVideoUnderlayChoice(studio, data, bgDefault, idx);
end


%% =========================================================
%  RESOLVE SCM / VIDEO UNDERLAY CHOICE
% =========================================================
%% =========================================================
%  RESOLVE SCM / VIDEO UNDERLAY CHOICE
% =========================================================
function [bg, label, underlayInfo] = resolveScmVideoUnderlayChoice(studio, data, bgDefault, idx)

    bg = [];
    label = '';
   underlayInfo = scmVideoEmptyUnderlayInfo();

    switch idx

        case 1
            bg = bgDefault;
            label = 'Default reference bg';

            underlayInfo.mode = 'default_bg';
            underlayInfo.label = label;

        case 2
    [U,labelText,ok,info] = scmVideoAskAndLoadStepMotorRegistration2D(studio, data.I, 'histology');
    if ~ok || isempty(U)
        return;
    end

    bg = U;
    label = labelText;
    underlayInfo = info;

        case 3
            bg = computeUnderlayFromActive(data,'median');
            bg = scmVideoFitUnderlayToData(bg, data.I);
            label = 'Median active dataset';

            underlayInfo.mode = 'median_active';
            underlayInfo.label = label;

        case 4
            [U,labelText,ok] = scmVideoAskAndLoadUnderlayFromRegistration2D(studio, data.I, 'external');
            if ~ok || isempty(U)
                return;
            end

            bg = U;
            label = labelText;

            underlayInfo.mode = 'external_registration2D_file';
            underlayInfo.label = labelText;
            underlayInfo.selectedFile = labelText;
            underlayInfo.isMulti = false;

        case 5
            bg = scmVideoMakeRecommendedStandardUnderlay(data.I);
            label = 'Recommended Standard';

            underlayInfo.mode = 'recommended_standard';
            underlayInfo.label = label;

        otherwise
            bg = bgDefault;
            label = 'Default reference bg';

            underlayInfo.mode = 'default_bg';
            underlayInfo.label = label;
    end
end

%% =========================================================
%  LOAD UNDERLAY FROM REGISTRATION2D
% =========================================================
function [U,labelText,ok] = scmVideoAskAndLoadUnderlayFromRegistration2D(studio, I, kind)

    U = [];
    labelText = '';
    ok = false;

    startDir = scmVideoGetRegistration2DStartDir(studio);

    if strcmpi(kind,'atlas')
        titleStr = 'Select atlas multi-slice / registered underlay from Registration2D';
    else
        titleStr = 'Select external underlay / histology from Registration2D';
    end

    [f,p] = scmVideo_uigetfile_start( ...
        {'*.mat;*.nii;*.nii.gz;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
         'Underlay files (*.mat,*.nii,*.nii.gz,*.png,*.jpg,*.tif,*.bmp)'}, ...
        titleStr, startDir);

    if isequal(f,0)
        return;
    end

    fullFile = fullfile(p,f);

    Uraw = loadUnderlayFile(fullFile);

    if isempty(Uraw)
        return;
    end

    U = scmVideoFitUnderlayToData(Uraw, I);

    [~,nm,ext] = fileparts(f);
    if strcmpi(ext,'.gz')
        [~,nm2,ext2] = fileparts(nm);
        labelText = ['File: ' nm2 ext2 ext];
    else
        labelText = ['File: ' nm ext];
    end

    ok = true;
end

%% =========================================================
%  STEP MOTOR REGISTRATION2D PER-SLICE UNDERLAY LOADER
% =========================================================
function [U,labelText,ok,info] = scmVideoAskAndLoadStepMotorRegistration2D(studio, I, kind)

    U = [];
    labelText = '';
    ok = false;
    info = scmVideoEmptyUnderlayInfo();

    kind = lower(strtrim(kind));
    if isempty(kind)
        kind = 'histology';
    end

    [Y,X,Z] = scmVideoGetFunctionalYXZ(I);

    startDir = scmVideoGetStepMotorKindStartDir(studio, kind);

    parentDir = uigetdir(startDir, ...
        ['Select parent folder containing Step Motor source folders for ' kind]);

    if isequal(parentDir,0)
        return;
    end

    [selectedDirs, okDirs] = scmVideoSelectStepMotorSubfolders(parentDir, kind);

    if ~okDirs || isempty(selectedDirs)
        return;
    end

    files = {};
    sourceIdx = [];

    for ii = 1:numel(selectedDirs)

        thisDir = selectedDirs{ii};

        f = scmVideoFindBestStepMotorUnderlayFile(thisDir, kind);

        if isempty(f)
            continue;
        end

        idx = scmVideoParseSourceIndex([thisDir filesep f]);

        if ~isfinite(idx) || idx < 1
            idx = ii;
        end

        files{end+1} = fullfile(thisDir,f); %#ok<AGROW>
        sourceIdx(end+1) = idx; %#ok<AGROW>
    end

    if isempty(files)
        uiwait(errordlg({ ...
            ['No matching AtlasUnderlay_' kind '_slice*.mat files found.'], ...
            '', ...
            'Expected examples:', ...
            ['  AtlasUnderlay_' kind '_slice001.mat'], ...
            ['  AtlasUnderlay_' kind '_source001.mat'], ...
            ['  source001\AtlasUnderlay_' kind '_slice001.mat']}, ...
            'Step Motor Registration2D'));
        return;
    end

    % Sort by parsed source/slice index.
    [sourceIdx, ord] = sort(sourceIdx);
    files = files(ord);

    U = zeros(Y,X,Z,'double');
    have = false(1,Z);

    usedFiles = {};
    usedIdx = [];

    for ii = 1:numel(files)

        z = sourceIdx(ii);

        if z < 1 || z > Z
            continue;
        end

        try
            Uraw = loadUnderlayFile(files{ii});
            U2 = scmVideoFitOneUnderlayToSlice(Uraw,Y,X);

            U(:,:,z) = U2;
            have(z) = true;

            usedFiles{end+1} = files{ii}; %#ok<AGROW>
            usedIdx(end+1) = z; %#ok<AGROW>

        catch ME
            warning('Could not load Step Motor underlay file: %s\n%s', files{ii}, ME.message);
        end
    end

    if ~any(have)
        U = [];
        return;
    end

    % Fill missing slices by nearest available underlay so SCM/Video never starts with black slices.
    missing = find(~have);
    available = find(have);

    if ~isempty(missing)
        for mm = 1:numel(missing)
            zMiss = missing(mm);
            [~,nearestPos] = min(abs(available - zMiss));
            zNear = available(nearestPos);
            U(:,:,zMiss) = U(:,:,zNear);
        end

        uiwait(warndlg(sprintf([ ...
            'Found %d Step Motor underlay files for %d functional slices.\n\n' ...
            'Missing slices were filled using the nearest available source underlay.'], ...
            numel(available), Z), ...
            'Step Motor Registration2D'));
    end

    info = scmVideoEmptyUnderlayInfo();
    info.mode = ['step_motor_registration2D_' kind];
    info.kind = kind;
    info.isMulti = true;
    info.files = usedFiles;
    info.sourceIdx = usedIdx;
    info.selectedPath = parentDir;
    info.isDisplayReady = true;

    labelText = sprintf('Step Motor Reg2D %s: %d files -> sources %s', ...
        kind, numel(usedFiles), mat2str(usedIdx));

    info.label = labelText;

    ok = true;
end


function startDir = scmVideoGetStepMotorKindStartDir(studio, kind)

    reg2D = scmVideoGetRegistration2DStartDir(studio);
    kind = lower(strtrim(kind));

    candidates = { ...
        fullfile(reg2D, kind), ...
        fullfile(reg2D, upperFirst(kind)), ...
        fullfile(reg2D, ['AtlasUnderlay_' kind]), ...
        fullfile(reg2D, ['AtlasUnderlay_' upperFirst(kind)]), ...
        reg2D};

    startDir = reg2D;

    for ii = 1:numel(candidates)
        if exist(candidates{ii},'dir')
            startDir = candidates{ii};
            return;
        end
    end
end


function [dirsOut, ok] = scmVideoSelectStepMotorSubfolders(parentDir, kind)

    dirsOut = {};
    ok = false;

    d = dir(parentDir);
    isGood = [d.isdir] & ~ismember({d.name},{'.','..'});
    d = d(isGood);

    listNames = {};
    listDirs = {};

    % Include current folder in case files are directly inside parentDir.
    if ~isempty(scmVideoFindBestStepMotorUnderlayFile(parentDir, kind))
        listNames{end+1} = '<current folder>'; %#ok<AGROW>
        listDirs{end+1} = parentDir; %#ok<AGROW>
    end

    for ii = 1:numel(d)
        p = fullfile(parentDir,d(ii).name);

        % Show all subfolders, but preselect likely source folders below.
        listNames{end+1} = d(ii).name; %#ok<AGROW>
        listDirs{end+1} = p; %#ok<AGROW>
    end

    if isempty(listDirs)
        dirsOut = {parentDir};
        ok = true;
        return;
    end

    preselect = [];

    for ii = 1:numel(listDirs)
        nm = lower(listNames{ii});
        hasFile = ~isempty(scmVideoFindBestStepMotorUnderlayFile(listDirs{ii}, kind));

        if hasFile || ~isempty(strfind(nm,'source')) || ~isempty(strfind(nm,'slice'))
            preselect(end+1) = ii; %#ok<AGROW>
        end
    end

    if isempty(preselect)
        preselect = 1:numel(listDirs);
    end

    [idx,tf] = listdlg( ...
        'PromptString',{ ...
            ['Select Step Motor source folders for ' kind '.'], ...
            'source001 maps to z=1, source002 maps to z=2, etc.'}, ...
        'SelectionMode','multiple', ...
        'ListString',listNames, ...
        'InitialValue',preselect, ...
        'ListSize',[650 420], ...
        'Name','Step Motor Registration2D source folders');

    if ~tf || isempty(idx)
        return;
    end

    dirsOut = listDirs(idx);
    ok = true;
end


function fileName = scmVideoFindBestStepMotorUnderlayFile(folderPath, kind)

    fileName = '';

    if ~exist(folderPath,'dir')
        return;
    end

    kind = lower(strtrim(kind));

    exactPatterns = { ...
        ['AtlasUnderlay_' kind '_slice*.mat'], ...
        ['AtlasUnderlay_' kind '_source*.mat'], ...
        ['AtlasUnderlay_' kind '*.mat'], ...
        ['*' kind '*slice*.mat'], ...
        ['*' kind '*source*.mat'], ...
        ['*' kind '*.mat']};

    for pp = 1:numel(exactPatterns)
        d = dir(fullfile(folderPath,exactPatterns{pp}));
        d = scmVideoRemoveBadTransformFiles(d);

        if ~isempty(d)
            fileName = d(1).name;
            return;
        end
    end

    d = dir(fullfile(folderPath,'*.mat'));
    d = scmVideoRemoveBadTransformFiles(d);

    if isempty(d)
        return;
    end

    scores = -Inf(1,numel(d));

    for ii = 1:numel(d)
        nm = lower(d(ii).name);
        sc = 0;

        if ~isempty(strfind(nm,'atlasunderlay')), sc = sc + 50; end
        if ~isempty(strfind(nm,kind)), sc = sc + 40; end
        if ~isempty(strfind(nm,'slice')), sc = sc + 20; end
        if ~isempty(strfind(nm,'source')), sc = sc + 20; end
        if ~isempty(strfind(nm,'underlay')), sc = sc + 15; end

        scores(ii) = sc;
    end

    [bestScore,bestIdx] = max(scores);

    if isfinite(bestScore) && bestScore > 0
        fileName = d(bestIdx).name;
    end
end


function d2 = scmVideoRemoveBadTransformFiles(d)

    keep = true(1,numel(d));

    bad = { ...
        'transformation', ...
        'coronalregistration2d', ...
        'transform', ...
        'transf', ...
        'trafo', ...
        'affine', ...
        'registrationmatrix'};

    for ii = 1:numel(d)
        nm = lower(d(ii).name);

        for bb = 1:numel(bad)
            if ~isempty(strfind(nm,bad{bb}))
                keep(ii) = false;
                break;
            end
        end
    end

    d2 = d(keep);
end


function idx = scmVideoParseSourceIndex(s)

    idx = NaN;
    s = lower(char(s));

    tok = regexp(s,'source[_\-\s]*0*([0-9]+)','tokens','once');
    if isempty(tok)
        tok = regexp(s,'slice[_\-\s]*0*([0-9]+)','tokens','once');
    end
    if isempty(tok)
        tok = regexp(s,'z[_\-\s]*0*([0-9]+)','tokens','once');
    end

    if ~isempty(tok)
        idx = str2double(tok{1});
    end
end


function [Y,X,Z] = scmVideoGetFunctionalYXZ(I)

    sz = size(I);

    Y = sz(1);
    X = sz(2);

    if ndims(I) >= 4
        Z = sz(3);
    else
        Z = 1;
    end
end


function U2 = scmVideoFitOneUnderlayToSlice(Uraw,Y,X)

    Uraw = double(squeeze(Uraw));
    Uraw = toGray(Uraw);

    while ndims(Uraw) > 3
        Uraw = mean(Uraw, ndims(Uraw));
        Uraw = squeeze(Uraw);
    end

    if ndims(Uraw) == 3
        if size(Uraw,3) == 3
            Uraw = toGray(Uraw);
        else
            mid = max(1,round(size(Uraw,3)/2));
            Uraw = Uraw(:,:,mid);
        end
    end

    Uraw = double(squeeze(Uraw));

    if ndims(Uraw) ~= 2
        error('Selected Step Motor underlay could not be converted to a 2D slice.');
    end

    U2 = scmVideoResize2D(Uraw,Y,X);
end


function s = upperFirst(s)

    if isempty(s)
        return;
    end

    s = lower(char(s));
    s(1) = upper(s(1));
end
%% =========================================================
%  REGISTRATION2D START FOLDER
% =========================================================
function startDir = scmVideoGetRegistration2DStartDir(studio)

    startDir = pwd;

    % 1) Preferred: analysed dataset Registration2D folder
    try
        if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
            reg2DDir = fullfile(studio.exportPath,'Registration2D');

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

    % 2) Explicit studio.registration2DPath
    try
        if isfield(studio,'registration2DPath') && ~isempty(studio.registration2DPath) && exist(studio.registration2DPath,'dir')
            startDir = studio.registration2DPath;
            return;
        end
    catch
    end

    % 3) Registration folder fallback
    try
        if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
            regDir = fullfile(studio.exportPath,'Registration');
            if exist(regDir,'dir')
                startDir = regDir;
                return;
            end

            startDir = studio.exportPath;
            return;
        end
    catch
    end

    % 4) Raw folder fallback
    try
        if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
            startDir = studio.loadedPath;
            return;
        end
    catch
    end
end


function [f,p] = scmVideo_uigetfile_start(filterSpec, titleStr, startDir)

    if nargin < 3 || isempty(startDir) || ~exist(startDir,'dir')
        startDir = pwd;
    end

    oldDir = pwd;
    cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>

    try
        cd(startDir);
    catch
    end

    try
        [f,p] = uigetfile(filterSpec, titleStr, startDir);
    catch
        [f,p] = uigetfile(filterSpec, titleStr);
    end
end


%% =========================================================
%  COMPUTE BASIC UNDERLAY FROM ACTIVE DATA
% =========================================================
function bg = computeUnderlayFromActive(data, method)

    I = data.I;
    bg = scmVideoComputeUnderlayFromArray(I, method);
end


function bg = scmVideoComputeUnderlayFromArray(I, method)

    I = single(I);
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


%% =========================================================
%  SCM / VIDEO RECOMMENDED STANDARD STYLE
%  This matches Mask Editor mode 7 defaults.
% =========================================================
function style = scmVideoDefaultRecommendedStyle()

    style = struct();

    % Mask Editor standardized Doppler equalized mode
    style.stdLow  = 0.40;
    style.stdHigh = 0.80;
    style.stdGain = 2.00;

    % Mask Editor display preset for mode 7
    style.brightness = 0.10;
style.contrast   = 0.50;
style.gamma      = 1.10;
style.sharpness  = 75.0;

style.softToneEnable = true;
style.softToneStrength = 0.40;
style.softToneMid = 0.48;
style.softToneToe = 0.08;

style.stdLow  = 0.40;
style.stdHigh = 0.80;
style.stdGain = 2.00;
end


%% =========================================================
%  RECOMMENDED STANDARD UNDERLAY
%  Exact Mask Editor logic:
%  mean(T) -> equalizeImageVasc_local -> scaleFixed(0.40,0.80)
%  -> brightness/contrast/gamma/sharpness -> soft tone
% =========================================================
function Udisp = scmVideoMakeRecommendedStandardUnderlay(I, style)

    if nargin < 2 || isempty(style) || ~isstruct(style)
        style = scmVideoDefaultRecommendedStyle();
    end

    Ueq = scmVideoMaskEditorEqualizedMean(I, style.stdGain);

    Udisp = scmVideoMaskEditorDisplayPipeline(Ueq, style);
end


function Ueq = scmVideoMaskEditorEqualizedMean(Iin, gain)

    gain = max(0,min(5,double(gain)));

    if ndims(Iin) == 3
        % Mask Editor mode 7 for 2D data:
        % I = Y x X x T, use mean over time
        a0 = mean(double(Iin),3);
        U2 = scmVideoEqualizeImageVascLocal2D(a0,gain);
        Ueq = reshape(U2,[size(a0,1) size(a0,2) 1]);
        return;
    end

    if ndims(Iin) >= 4
        % Mask Editor mode 7 for 3D data:
        % I = Y x X x Z x T, use mean over time
        a0 = mean(double(Iin),4);

        nY = size(a0,1);
        nX = size(a0,2);
        nZ = size(a0,3);

        Ueq = zeros(nY,nX,nZ,'double');

        for zz = 1:nZ
            Ueq(:,:,zz) = scmVideoEqualizeImageVascLocal2D(a0(:,:,zz),gain);
        end

        return;
    end

    error('Recommended Standard requires 3D [Y X T] or 4D [Y X Z T] data.');
end


function ae = scmVideoEqualizeImageVascLocal2D(a, gain)

    a = double(a);
    a(~isfinite(a)) = 0;

    [nz_, nx_] = size(a);

    mx = max(a(:));

    if ~isfinite(mx) || mx <= 0
        ae = zeros(size(a));
        return;
    end

    a = a ./ mx;
    ae = zeros(nz_, nx_);

    g = 1 + (0:nz_-1)' / max(1,nz_) * gain;
    gg = g * ones(1,nx_);

    tmp = a;
    tmp = tmp - min(tmp(:));
    tmp = tmp .* gg;

    mx2 = max(tmp(:));

    if ~isfinite(mx2) || mx2 <= 0
        ae = zeros(size(a));
        return;
    end

    tmp = tmp ./ mx2;

    m = median(tmp(:));

    if ~isfinite(m) || m <= 0
        m = eps;
    end

    comp = -1 / log2(m);

    if ~isfinite(comp) || comp <= 0
        comp = 1;
    end

    tmp = tmp .^ comp;

    mx3 = max(tmp(:));

    if ~isfinite(mx3) || mx3 <= 0
        ae = zeros(size(a));
        return;
    end

    tmp = tmp ./ mx3;

    ae = tmp;
    ae = ae - min(ae(:));

    mx4 = max(ae(:));

    if ~isfinite(mx4) || mx4 <= 0
        ae = zeros(size(a));
        return;
    end

    ae = ae ./ mx4;
end


function Udisp = scmVideoMaskEditorDisplayPipeline(Ueq, style)

    Ueq = double(squeeze(Ueq));
    Ueq(~isfinite(Ueq)) = 0;

    if ndims(Ueq) == 2
        Udisp = scmVideoMaskEditorDisplay2D(Ueq, style);
        return;
    end

    if ndims(Ueq) == 3
        Udisp = zeros(size(Ueq),'double');

        for zz = 1:size(Ueq,3)
            Udisp(:,:,zz) = scmVideoMaskEditorDisplay2D(Ueq(:,:,zz), style);
        end

        return;
    end

    error('Display pipeline received unsupported underlay dimensions.');
end


function U01 = scmVideoMaskEditorDisplay2D(U, style)

    % Mask Editor buildDisplayUnderlay for mode 7:
    % scaleFixed -> vessel maybe -> display adjust -> soft tone maybe

    U01 = scmVideoScaleFixedLocal(U, style.stdLow, style.stdHigh);

    if isfield(style,'vesselEnable') && style.vesselEnable
        U01 = scmVideoApplyVesselEnhanceLocal(U01, style);
    end

    U01 = scmVideoApplyDisplayAdjustLocal( ...
        U01, ...
        style.brightness, ...
        style.contrast, ...
        style.gamma, ...
        style.sharpness);

    if isfield(style,'softToneEnable') && style.softToneEnable
        U01 = scmVideoApplySoftToneLocal( ...
            U01, ...
            style.softToneStrength, ...
            style.softToneMid, ...
            style.softToneToe);
    end

    U01 = min(max(U01,0),1);
end


function U01 = scmVideoScaleFixedLocal(U, lo, hi)

    U = double(U);

    if ~isfinite(lo)
        lo = min(U(:));
    end

    if ~isfinite(hi)
        hi = max(U(:));
    end

    if hi <= lo + eps
        hi = lo + 1;
    end

    U(~isfinite(U)) = lo;
    U = min(max(U,lo),hi);

    U01 = (U - lo) ./ max(eps,(hi - lo));
    U01 = min(max(U01,0),1);
end


function U01 = scmVideoApplyDisplayAdjustLocal(U01, bright, cont, gam, sharp)

    U01 = double(U01);
    U01(~isfinite(U01)) = 0;

    U01 = U01 .* cont + bright;
    U01 = min(max(U01,0),1);

    U01 = U01 .^ (1 / max(eps,gam));
    U01 = min(max(U01,0),1);

    sharp = max(0,min(300,double(sharp)));

    if sharp > 0
        amountMax = 4.5;
        amount = amountMax * (1 - exp(-sharp/60));
        sigma = 1.10 + 0.90 * (sharp/300);

        B = scmVideoGaussBlur2DLocal(U01, sigma);
        hi = U01 - B;
        hi = 0.35 * tanh(hi / 0.35);

        U01 = U01 + amount * hi;
        U01 = min(max(U01,0),1);
    end
end


function U01 = scmVideoApplySoftToneLocal(U01, strength, mid, toe)

    U01 = double(U01);
    U01 = min(max(U01,0),1);

    a = max(0,min(1,double(strength)));
    mid = max(0.05,min(0.95,double(mid)));
    toe = max(0,min(0.35,double(toe)));

    gain = 1 + 10*a;

    L = 0.5 + 0.5*tanh(gain*(U01 - mid));
    L0 = 0.5 + 0.5*tanh(gain*(0 - mid));
    L1 = 0.5 + 0.5*tanh(gain*(1 - mid));

    L = (L - L0) ./ max(eps,(L1 - L0));
    L = min(max(L,0),1);

    L = (1 - toe) .* L + toe .* sqrt(L);

    U01 = (1 - a) .* U01 + a .* L;
    U01 = min(max(U01,0),1);
end


function U01 = scmVideoApplyVesselEnhanceLocal(U01, style)

    U01 = double(U01);
    U01 = min(max(U01,0),1);

    sig = max(0,min(5,double(style.vesselSigma)));
    gain = max(0,double(style.vesselGain));
    thr = max(0,min(1,double(style.vesselThresh)));

    b1 = scmVideoGaussBlur2DLocal(U01, sig);
    b2 = scmVideoGaussBlur2DLocal(U01, max(sig*2.5, sig+0.35));

    detail = max(0, b1 - b2);

    d99 = scmVideoLocalPercentile(detail(:),99.0);

    if d99 <= 0
        d99 = max(detail(:));
    end

    if d99 > 0
        detail = detail ./ d99;
    end

    detail = min(max(detail,0),1);

    boost = min(1, U01 + gain * detail .* (0.20 + 0.80*U01));

    maskV = detail >= thr;

    if isfield(style,'vesselConnect') && style.vesselConnect
        maskV = scmVideoBinaryCloseLocal(maskV, max(1,round(sig)));
    end

    if any(maskV(:))
        boost(maskV) = min(1, boost(maskV) + 0.15 + 0.20*gain*detail(maskV));
    end

    U01 = 0.55*U01 + 0.45*boost;
    U01 = min(max(U01,0),1);
end


function B = scmVideoGaussBlur2DLocal(A, sigma)

    sigma = max(0,double(sigma));

    if sigma <= 0
        B = A;
        return;
    end

    try
        B = imgaussfilt(A, sigma);
    catch
        rad = max(1,ceil(3*sigma));
        x = -rad:rad;
        g = exp(-(x.^2)/(2*sigma^2));
        g = g ./ sum(g);

        B = conv2(conv2(A,g,'same'),g','same');
    end
end


function p = scmVideoLocalPercentile(v,q)

    v = double(v(:));
    v = v(isfinite(v));

    if isempty(v)
        p = 0;
        return;
    end

    q = max(0,min(100,double(q)));

    try
        p = prctile(v,q);
    catch
        v = sort(v);

        if numel(v) == 1
            p = v(1);
            return;
        end

        pos = 1 + (numel(v)-1) * (q/100);
        i0 = floor(pos);
        i1 = ceil(pos);

        i0 = max(1,min(numel(v),i0));
        i1 = max(1,min(numel(v),i1));

        if i0 == i1
            p = v(i0);
        else
            p = v(i0) + (pos - i0) * (v(i1) - v(i0));
        end
    end
end


function M = scmVideoBinaryCloseLocal(M, rad)

    M = logical(M);
    rad = max(1,round(rad));

    try
        se = strel('disk',rad);
        M = imclose(M,se);
    catch
        K = ones(2*rad+1);
        D = conv2(double(M),K,'same') > 0;
        E = conv2(double(D),K,'same') >= numel(K);
        M = E;
    end
end


%% =========================================================
%  FIT UNDERLAY TO FUNCTIONAL DIMENSIONS
% =========================================================
function U = scmVideoFitUnderlayToData(Uraw, I)

    Uraw = double(squeeze(Uraw));
    Uraw = toGray(Uraw);

    sz = size(I);
    Y = sz(1);
    X = sz(2);

    if ndims(I) >= 4
        Z = sz(3);
    else
        Z = 1;
    end

    % Remove extra dimensions safely
    while ndims(Uraw) > 3
        Uraw = mean(Uraw, ndims(Uraw));
        Uraw = squeeze(Uraw);
    end

    if ndims(Uraw) == 2
        U2 = scmVideoResize2D(Uraw,Y,X);

        if Z == 1
            U = reshape(U2,Y,X,1);
        else
            U = repmat(U2,[1 1 Z]);
        end

        return;
    end

    if ndims(Uraw) == 3

        % RGB after toGray should not remain, but keep safety.
        if size(Uraw,3) == 3 && Z ~= 3
            Uraw = toGray(Uraw);
            Uraw = scmVideoResize2D(Uraw,Y,X);
            if Z == 1
                U = reshape(Uraw,Y,X,1);
            else
                U = repmat(Uraw,[1 1 Z]);
            end
            return;
        end

        Utmp = zeros(Y,X,size(Uraw,3));

        for zz = 1:size(Uraw,3)
            Utmp(:,:,zz) = scmVideoResize2D(Uraw(:,:,zz),Y,X);
        end

        if size(Utmp,3) == Z
            U = Utmp;
            return;
        end

        if Z == 1
            mid = round(size(Utmp,3)/2);
            U = reshape(Utmp(:,:,mid),Y,X,1);
            return;
        end

        zi = round(linspace(1,size(Utmp,3),Z));
        zi = max(1,min(size(Utmp,3),zi));
        U = Utmp(:,:,zi);
        return;
    end

    error('Could not fit underlay to functional dimensions.');
end


function B = scmVideoResize2D(A,Y,X)

    A = double(A);

    if size(A,1) == Y && size(A,2) == X
        B = A;
        return;
    end

    if exist('imresize','file') == 2
        try
            B = imresize(A,[Y X],'bilinear');
        catch
            B = imresize(A,[Y X]);
        end
    else
        yy = round(linspace(1,size(A,1),Y));
        xx = round(linspace(1,size(A,2),X));
        yy = max(1,min(size(A,1),yy));
        xx = max(1,min(size(A,2),xx));
        B = A(yy,xx);
    end
end


function U = scmVideoNormalizeUnderlayDisplay(U)

    U = double(U);
    U(~isfinite(U)) = 0;

    if ndims(U) == 2
        U = scmVideoNormalize2D(U);
        return;
    end

    if ndims(U) == 3
        for zz = 1:size(U,3)
            U(:,:,zz) = scmVideoNormalize2D(U(:,:,zz));
        end
    end
end


function B = scmVideoNormalize2D(A)

    A = double(A);
    A(~isfinite(A)) = 0;

    vals = A(isfinite(A));

    if isempty(vals)
        B = zeros(size(A));
        return;
    end

    lo = scmVideoPercentile(vals,1);
    hi = scmVideoPercentile(vals,99);

    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        lo = min(vals);
        hi = max(vals);
    end

    if hi <= lo
        B = zeros(size(A));
        return;
    end

    B = (A - lo) ./ (hi - lo);
    B(B < 0) = 0;
    B(B > 1) = 1;
end


function p = scmVideoPercentile(x,prc)

    x = double(x(:));
    x = x(isfinite(x));

    if isempty(x)
        p = NaN;
        return;
    end

    x = sort(x);
    n = numel(x);

    if n == 1
        p = x(1);
        return;
    end

    pos = 1 + (prc/100) * (n-1);
    lo = floor(pos);
    hi = ceil(pos);

    lo = max(1,min(n,lo));
    hi = max(1,min(n,hi));

    if lo == hi
        p = x(lo);
    else
        w = pos - lo;
        p = x(lo) * (1-w) + x(hi) * w;
    end
end


%% =========================================================
%  LOAD UNDERLAY FILE
% =========================================================
function U = loadUnderlayFile(f)

    if ~exist(f,'file')
        error('Underlay file not found: %s', f);
    end

    isNiiGz = numel(f) >= 7 && strcmpi(f(end-6:end), '.nii.gz');

    try
        if isNiiGz
            tmpDir = tempname;
            mkdir(tmpDir);

            cleanupObj = onCleanup(@() cleanupTmpDir(tmpDir)); %#ok<NASGU>

            gunzip(f, tmpDir);
            d = dir(fullfile(tmpDir,'*.nii'));

            if isempty(d)
                error('gunzip failed for %s', f);
            end

            V = niftiread(fullfile(tmpDir, d(1).name));
            U = double(V);
            U = squeezeTo2Dor3D(U);
            U = toGray(U);
            return;
        end

        [~,~,ext] = fileparts(f);
        ext = lower(ext);

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


function cleanupTmpDir(tmpDir)

    try
        if exist(tmpDir,'dir')
            rmdir(tmpDir,'s');
        end
    catch
    end
end


%% =========================================================
%  PICK UNDERLAY FROM MAT
% =========================================================
function U = studio_pickUnderlayFromMat(S)

    hasBundle = isfield(S,'maskBundle') && isstruct(S.maskBundle) && ~isempty(S.maskBundle);

    if hasBundle
        B = S.maskBundle;
    else
        B = S;
    end

    % Prefer display-ready / registered / multi-slice underlays.
    pref = { ...
        'savedUnderlayDisplay', ...
        'savedUnderlayForReload', ...
        'anatomical_reference', ...
        'anatomicalReference', ...
        'brainImage', ...
        'atlasUnderlayMultiSlice', ...
        'atlasUnderlayStack', ...
        'registeredUnderlay', ...
        'registeredHistology', ...
        'registeredHistologyStack', ...
        'warpedUnderlay', ...
        'warpedHistology', ...
        'histologyStack', ...
        'histology', ...
        'Histology', ...
        'anatomical_reference_raw', ...
        'anatomicalReferenceRaw', ...
        'underlay', ...
        'bg', ...
        'atlasUnderlayRGB', ...
        'atlasUnderlay', ...
        'img', ...
        'image', ...
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
        'overlayMaskIsInclude', ...
        'M', ...
        'A', ...
        'T', ...
        'Transformation', ...
        'Transf', ...
        'RegOut', ...
        'Reg2D', ...
        'outputSize', ...
        'atlasSliceIndex'};

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

    error(['No usable underlay variable found in MAT file. ' ...
           'Avoid selecting tiny transformation-only MAT files. ' ...
           'Select a saved histology / atlas-underlay / brainImage MAT instead.']);
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
            v = v.Data;
        elseif isfield(v,'I') && isnumeric(v.I) && ~isempty(v.I)
            v = v.I;
        else
            return;
        end
    end

    if ~(isnumeric(v) || islogical(v)) || isempty(v)
        return;
    end

    if ~studio_isImageLikeNumeric(v)
        return;
    end

    ok = true;
    U = v;
end


function tf = studio_isImageLikeNumeric(A)

    tf = false;

    try
        A = squeeze(A);
        sz = size(A);

        % Reject tiny transform matrices like 3x3 / 4x4 / affine matrices.
        if numel(A) < 1000
            return;
        end

        if ndims(A) < 2
            return;
        end

        if sz(1) < 16 || sz(2) < 16
            return;
        end

        tf = true;

    catch
        tf = false;
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

        if numel(A) > 200000
            idx = round(linspace(1,numel(A),200000));
            A = A(idx);
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

    X = squeeze(X);

    while ndims(X) > 3
        X = mean(X, ndims(X));
        X = squeeze(X);
    end
end


function G = toGray(X)

    X = squeeze(X);

    if ndims(X) == 3 && size(X,3) == 3
        R = double(X(:,:,1));
        Gc = double(X(:,:,2));
        B = double(X(:,:,3));
        G = 0.2989*R + 0.5870*Gc + 0.1140*B;
        return;
    end

    G = X;
end

%% =========================================================
%  EMPTY SCM / VIDEO UNDERLAY INFO
% =========================================================
function info = scmVideoEmptyUnderlayInfo()

    info = struct();

    info.mode = '';
    info.isMulti = false;
    info.files = {};
    info.sourceIdx = [];
    info.selectedFile = '';
    info.selectedPath = '';
    info.label = '';
    info.isDisplayReady = false;
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

    studioRootForIcon = fileparts(mfilename('fullpath'));
    iconFile = fullfile(studioRootForIcon, 'Icon.png');

    % HUMOR_ICON_PATH_PATCH_20260518B
    % In split-runtime mode mfilename points to tempdir; fall back to toolbox root.
    if ~exist(iconFile,'file')
        try
            candRoots = {};
            w = which('run_fusi_studio');
            if ~isempty(w), candRoots{end+1} = fileparts(w); end
            w = which('fusi_studio_GUI');
            if ~isempty(w), candRoots{end+1} = fileparts(w); end
            candRoots{end+1} = pwd;
            for cc = 1:numel(candRoots)
                f2 = fullfile(candRoots{cc}, 'Icon.png');
                if exist(f2,'file') == 2
                    iconFile = f2;
                    break;
                end
            end
        catch
        end
    end

    if ~exist(iconFile,'file')
        disp(['Icon file not found: ' iconFile]);
        return;
    end

    try
        [img, ~, alpha] = imread(iconFile);

        if isempty(alpha)
            alpha = 255 * ones(size(img,1), size(img,2), 'uint8');
        end

        padTop = 0;
        padBottom = 0;
        padLeft = 0;
        padRight = 0;

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
            'Position',[0.900 0.925 0.088 0.067], ...
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
%  PATH HELPERS
% =========================================================
function startPath = studio_default_load_start_path(studio)
    startPath = '';

    try
        if isstruct(studio) && isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
            startPath = studio.loadedPath;
        end
    catch
        startPath = '';
    end

    if isempty(startPath) && ispc
        winDefault = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
        if exist(winDefault,'dir')
            startPath = winDefault;
        end
    end

    if isempty(startPath)
        startPath = pwd;
    end
end

function [rawRoot, analysedRoot] = studio_auto_roots_from_input(inputPath)
    if nargin < 1 || isempty(inputPath)
        inputPath = pwd;
    end

    p = char(inputPath);
    if isempty(p) || exist(p,'dir') ~= 7
        p = pwd;
    end

    while numel(p) > 1 && (p(end) == filesep || any(p(end) == ['/', char(92)]))
        p(end) = [];
    end

    pForward = strrep(p, char(92), '/');

    if ~isempty(regexp(pForward, '(^|/)RawData(/|$)', 'once'))
        rawRootForward = regexprep(pForward, '(^.*?/RawData)(/.*)?$', '$1', 'ignorecase');
        analysedRootForward = regexprep(rawRootForward, 'RawData$', 'AnalysedData', 'ignorecase');
        rawRoot = strrep(rawRootForward, '/', filesep);
        analysedRoot = strrep(analysedRootForward, '/', filesep);
    else
        rawRoot = p;
        analysedRoot = fullfile(p, 'AnalysedData');
    end

    if isempty(rawRoot)
        rawRoot = pwd;
    end

    if isempty(analysedRoot)
        analysedRoot = fullfile(pwd, 'AnalysedData');
    end
end


%% =========================================================
%  OUTPUT FOLDER CHOOSER
% =========================================================
function [datasetFolder, wasCancelled] = studio_choose_output_folder(autoDatasetFolder, analysedRoot, datasetName)
    datasetFolder = autoDatasetFolder;
    wasCancelled = false;

    if nargin < 2 || isempty(analysedRoot)
        analysedRoot = pwd;
    end
    if nargin < 3 || isempty(datasetName)
        datasetName = 'Dataset';
    end

    msg = sprintf(['Output folder for this dataset:\n\n%s\n\nUse this automatic folder, or choose a different output parent folder?'], autoDatasetFolder);

    choice = questdlg(msg, ...
        'Choose output folder', ...
        'Automatic', ...
        'Choose parent folder', ...
        'Cancel load', ...
        'Automatic');

    if isempty(choice) || strcmp(choice,'Cancel load')
        wasCancelled = true;
        return;
    end

    if strcmp(choice,'Automatic')
        datasetFolder = autoDatasetFolder;
        return;
    end

    startDir = analysedRoot;

    try
        if ispref('fusi_studio','lastOutputParent')
            prefDir = getpref('fusi_studio','lastOutputParent');
            if ischar(prefDir) && exist(prefDir,'dir')
                startDir = prefDir;
            end
        end
    catch
    end

    if isempty(startDir) || exist(startDir,'dir') ~= 7
        try
            startDir = fileparts(autoDatasetFolder);
        catch
            startDir = pwd;
        end
    end

    if isempty(startDir) || exist(startDir,'dir') ~= 7
        startDir = pwd;
    end

    titleStr = sprintf('Select OUTPUT PARENT folder. Dataset folder "%s" will be created inside it.', datasetName);
    parentDir = uigetdir(startDir, titleStr);

    if isequal(parentDir,0)
        wasCancelled = true;
        return;
    end

    try
        setpref('fusi_studio','lastOutputParent',parentDir);
    catch
    end

    datasetFolder = fullfile(parentDir, datasetName);
end


%% =========================================================
%  DARK LOAD OPTIONS DIALOG
% =========================================================
function defaultTR = studio_get_last_tr_default()
    defaultTR = 0.320;
    try
        if ispref('fusi_studio','lastTR')
            tmp = getpref('fusi_studio','lastTR');
            if isnumeric(tmp) && isfinite(tmp) && tmp > 0
                defaultTR = tmp;
            end
        end
    catch
    end
end

function answ = studio_silent_tr_answer_for_old_prompt()
    answ = {num2str(studio_get_last_tr_default())};
end

function [TR, datasetFolder, wasCancelled, probeType, defaultTR] = studio_load_options_dark_dialog(initialTR, autoDatasetFolder, analysedRoot, datasetName, probeType, defaultTR, data, meta)
    TR = initialTR;
    datasetFolder = autoDatasetFolder;
    wasCancelled = false;

    if nargin < 7
        data = struct();
    end
    if nargin < 8
        meta = struct();
    end

    if nargin < 5 || isempty(probeType) || nargin < 6 || isempty(defaultTR) || ~isnumeric(defaultTR) || ~isfinite(defaultTR) || defaultTR <= 0
        try
            [probeType, defaultTR] = detectProbeTypeFromMeta(data, meta);
    defaultTR = studio_probe_default_tr_seconds(probeType, data);
        catch
            probeType = '2D Probe';
            defaultTR = 0.320;
        end
    end

    if nargin < 1 || isempty(initialTR) || ~isnumeric(initialTR) || ~isfinite(initialTR) || initialTR <= 0
        initialTR = defaultTR;
    end
    if nargin < 2 || isempty(autoDatasetFolder)
        autoDatasetFolder = fullfile(pwd,'AnalysedData', 'Dataset');
    end
    if nargin < 3 || isempty(analysedRoot)
        analysedRoot = fileparts(autoDatasetFolder);
    end
    if nargin < 4 || isempty(datasetName)
        datasetName = 'Dataset';
    end

    fileTR = [];
    fileTRSource = 'not found';
    try
        [fileTR, fileTRSource] = studio_get_file_tr_candidate(data, meta);
    catch
        fileTR = [];
        fileTRSource = 'not found';
    end

    customTRmsDefault = defaultTR * 1000;
    if ~isempty(fileTR) && isfinite(fileTR) && fileTR > 0
        customTRmsDefault = fileTR * 1000;
    end

    bg       = [0.07 0.08 0.10];
    panel    = [0.12 0.13 0.16];
    panel2   = [0.16 0.17 0.21];
    fg       = [0.94 0.94 0.94];
    muted    = [0.72 0.74 0.78];
    green    = [0.10 0.50 0.24];
    red      = [0.62 0.13 0.12];
    blue     = [0.12 0.28 0.52];
    orange   = [0.85 0.45 0.12];

    W = 1000;
    H = 760;
    scr = get(0,'ScreenSize');
    x0 = max(30, round((scr(3)-W)/2));
    y0 = max(30, round((scr(4)-H)/2));

    dlg = figure('Name','Load dataset options', ...
        'NumberTitle','off', ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'Color',bg, ...
        'Units','pixels', ...
        'Position',[x0 y0 W H], ...
        'Resize','off', ...
        'WindowStyle','modal', ...
        'CloseRequestFcn',@onCancel);

    result = struct();
    result.cancel = true;
    result.TR = defaultTR;
    result.datasetFolder = autoDatasetFolder;
    setappdata(dlg,'result',result);

    uicontrol(dlg,'Style','text', ...
        'String','Load dataset options', ...
        'Units','pixels', ...
        'Position',[35 595 790 36], ...
        'BackgroundColor',bg, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',21, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    uicontrol(dlg,'Style','text', ...
        'String','Confirm probe/TR settings and choose where analysed data should be saved.', ...
        'Units','pixels', ...
        'Position',[35 565 790 24], ...
        'BackgroundColor',bg, ...
        'ForegroundColor',muted, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'HorizontalAlignment','left');

    % Probe/TR panel
    uipanel('Parent',dlg, ...
        'Units','pixels', ...
        'Position',[35 390 790 160], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',panel2);

    uicontrol(dlg,'Style','text', ...
        'String','Probe and temporal resolution', ...
        'Units','pixels', ...
        'Position',[60 515 500 26], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',14, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    infoText = sprintf('Detected probe: %s     |     Probe default TR: %.0f ms (%.3f s)', probeType, defaultTR*1000, defaultTR);
    if ~isempty(fileTR)
        infoText = sprintf('%s     |     File TR: %.0f ms (%.3f s)', infoText, fileTR*1000, fileTR);
    end

    uicontrol(dlg,'Style','text', ...
        'String',infoText, ...
        'Units','pixels', ...
        'Position',[60 487 735 24], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',muted, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'HorizontalAlignment','left');

    hUseDefaultTR = uicontrol(dlg,'Style','radiobutton', ...
        'String',sprintf('Use probe default TR: %.0f ms', defaultTR*1000), ...
        'Value',1, ...
        'Units','pixels', ...
        'Position',[60 450 320 28], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@onUseDefaultTR);

    hUseCustomTR = uicontrol(dlg,'Style','radiobutton', ...
        'String','Use custom TR', ...
        'Value',0, ...
        'Units','pixels', ...
        'Position',[410 450 190 28], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@onUseCustomTR);

    hCustomTRms = uicontrol(dlg,'Style','edit', ...
        'String',sprintf('%.0f', customTRmsDefault), ...
        'Units','pixels', ...
        'Position',[590 448 105 32], ...
        'BackgroundColor',[0.24 0.24 0.27], ...
        'ForegroundColor',[0.85 0.85 0.85], ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'HorizontalAlignment','center', ...
        'Enable','off');

    uicontrol(dlg,'Style','text', ...
        'String','ms', ...
        'Units','pixels', ...
        'Position',[705 452 40 24], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',muted, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'HorizontalAlignment','left');

    if ~isempty(fileTR) && isfinite(fileTR) && fileTR > 0
        trHintString = sprintf('Default TR is 320 ms. File TR %.0f ms is pre-filled in Custom TR. Source: %s', fileTR*1000, fileTRSource);
    else
        trHintString = 'Default TR is 320 ms and is pre-selected. Use Custom TR if needed.';
    end

    hTRHint = uicontrol(dlg,'Style','text', ...
        'String',trHintString, ...
        'Units','pixels', ...
        'Position',[60 414 735 24], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',orange, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    % Output panel
    uipanel('Parent',dlg, ...
        'Units','pixels', ...
        'Position',[35 115 790 260], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'BorderType','line', ...
        'HighlightColor',panel2);

    uicontrol(dlg,'Style','text', ...
        'String','Output folder', ...
        'Units','pixels', ...
        'Position',[60 340 250 26], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',14, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','left');

    hAuto = uicontrol(dlg,'Style','radiobutton', ...
        'String','Automatic output folder (recommended)', ...
        'Value',1, ...
        'Units','pixels', ...
        'Position',[60 305 360 28], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@onAuto);

    hCustom = uicontrol(dlg,'Style','radiobutton', ...
        'String','Choose custom output parent folder', ...
        'Value',0, ...
        'Units','pixels', ...
        'Position',[440 305 330 28], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',12, ...
        'Callback',@onCustom);

    uicontrol(dlg,'Style','text', ...
        'String','Automatic dataset folder:', ...
        'Units','pixels', ...
        'Position',[60 272 300 22], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',muted, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    hAutoPath = uicontrol(dlg,'Style','edit', ...
        'String',autoDatasetFolder, ...
        'Units','pixels', ...
        'Position',[60 238 710 30], ...
        'BackgroundColor',panel2, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left', ...
        'Enable','inactive');

    uicontrol(dlg,'Style','text', ...
        'String','Custom parent folder. The dataset folder will be created inside this folder:', ...
        'Units','pixels', ...
        'Position',[60 202 650 22], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',muted, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    startDir = analysedRoot;
    try
        if ispref('fusi_studio','lastOutputParent')
            prefDir = getpref('fusi_studio','lastOutputParent');
            if ischar(prefDir) && exist(prefDir,'dir')
                startDir = prefDir;
            end
        end
    catch
    end
    if isempty(startDir) || exist(startDir,'dir') ~= 7
        startDir = fileparts(autoDatasetFolder);
    end
    if isempty(startDir) || exist(startDir,'dir') ~= 7
        startDir = pwd;
    end

    hParent = uicontrol(dlg,'Style','edit', ...
        'String',startDir, ...
        'Units','pixels', ...
        'Position',[60 165 585 32], ...
        'BackgroundColor',[0.24 0.24 0.27], ...
        'ForegroundColor',[0.85 0.85 0.85], ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left', ...
        'Enable','off');

    hBrowse = uicontrol(dlg,'Style','pushbutton', ...
        'String','Browse', ...
        'Units','pixels', ...
        'Position',[660 165 110 32], ...
        'BackgroundColor',blue, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'Enable','off', ...
        'Callback',@onBrowse);

    hHint = uicontrol(dlg,'Style','text', ...
        'String','Automatic mode is selected. This keeps your current workflow unchanged.', ...
        'Units','pixels', ...
        'Position',[60 128 710 24], ...
        'BackgroundColor',panel, ...
        'ForegroundColor',orange, ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'HorizontalAlignment','left');

    % Buttons
    uicontrol(dlg,'Style','pushbutton', ...
        'String','Cancel', ...
        'Units','pixels', ...
        'Position',[535 40 130 46], ...
        'BackgroundColor',red, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onCancel);

    uicontrol(dlg,'Style','pushbutton', ...
        'String','Proceed', ...
        'Units','pixels', ...
        'Position',[685 40 140 46], ...
        'BackgroundColor',green, ...
        'ForegroundColor',fg, ...
        'FontName','Arial', ...
        'FontSize',13, ...
        'FontWeight','bold', ...
        'Callback',@onProceed);

    try
        studio_scale_load_options_dialog(dlg, 1.16, 1.12, 1.18);
    catch
    end

    drawnow;
    try, HUMoR_popup_autofit_apply(dlg); catch, end
    uiwait(dlg);

    if ishandle(dlg)
        result = getappdata(dlg,'result');
        try delete(dlg); catch, end
    else
        result = struct('cancel',true,'TR',defaultTR,'datasetFolder',autoDatasetFolder);
    end

    if isfield(result,'cancel') && result.cancel
        wasCancelled = true;
        return;
    end

    TR = result.TR;
    datasetFolder = result.datasetFolder;
    wasCancelled = false;

    function onUseDefaultTR(~,~)
        if ~ishandle(dlg), return; end
        set(hUseDefaultTR,'Value',1);
        set(hUseCustomTR,'Value',0);
        set(hCustomTRms,'Enable','off','BackgroundColor',[0.24 0.24 0.27],'ForegroundColor',[0.85 0.85 0.85]);
        set(hTRHint,'String','Probe default TR is pre-selected. If file TR is detected, it is pre-filled in Custom TR.','ForegroundColor',orange);
    end

    function onUseCustomTR(~,~)
        if ~ishandle(dlg), return; end
        set(hUseDefaultTR,'Value',0);
        set(hUseCustomTR,'Value',1);
        set(hCustomTRms,'Enable','on','BackgroundColor',[0.98 0.98 0.98],'ForegroundColor',[0 0 0]);
        set(hTRHint,'String','Custom TR selected. Enter the value in milliseconds.','ForegroundColor',muted);
    end

    function onAuto(~,~)
        if ~ishandle(dlg), return; end
        set(hAuto,'Value',1);
        set(hCustom,'Value',0);
        set(hParent,'Enable','off','BackgroundColor',[0.24 0.24 0.27],'ForegroundColor',[0.85 0.85 0.85]);
        set(hBrowse,'Enable','off');
        set(hHint,'String','Automatic mode is selected. This keeps your current workflow unchanged.','ForegroundColor',orange);
    end

    function onCustom(~,~)
        if ~ishandle(dlg), return; end
        set(hAuto,'Value',0);
        set(hCustom,'Value',1);
        set(hParent,'Enable','on','BackgroundColor',[0.98 0.98 0.98],'ForegroundColor',[0 0 0]);
        set(hBrowse,'Enable','on');
        set(hHint,'String','Custom mode: DatasetName folder will be created inside the selected parent folder.','ForegroundColor',muted);
    end

    function onBrowse(~,~)
        if ~ishandle(dlg), return; end
        currentDir = get(hParent,'String');
        if isempty(currentDir) || exist(currentDir,'dir') ~= 7
            currentDir = startDir;
        end
        picked = uigetdir(currentDir, 'Select output parent folder');
        if isequal(picked,0)
            return;
        end
        set(hParent,'String',picked);
        onCustom();
    end

    function onProceed(~,~)
        if ~ishandle(dlg), return; end

        useCustomTR = get(hUseCustomTR,'Value') == 1;
        if useCustomTR
            trMs = str2double(strtrim(get(hCustomTRms,'String')));
            if isempty(trMs) || ~isfinite(trMs) || trMs <= 0
                errordlg('Please enter a valid positive custom TR in milliseconds.','Invalid TR');
                return;
            end
            trVal = trMs / 1000;
        else
            trVal = defaultTR;
        end

        useCustomOutput = get(hCustom,'Value') == 1;

        if useCustomOutput
            parentDir = strtrim(get(hParent,'String'));
            if isempty(parentDir) || exist(parentDir,'dir') ~= 7
                errordlg('Please choose a valid output parent folder.','Invalid output folder');
                return;
            end
            outFolder = fullfile(parentDir, datasetName);
            try setpref('fusi_studio','lastOutputParent',parentDir); catch, end
        else
            outFolder = autoDatasetFolder;
        end

        try setpref('fusi_studio','lastTR',trVal); catch, end

        result = struct();
        result.cancel = false;
        result.TR = trVal;
        result.datasetFolder = outFolder;
        setappdata(dlg,'result',result);
        uiresume(dlg);
    end

    function onCancel(~,~)
        if ishandle(dlg)
            result = struct();
            result.cancel = true;
            result.TR = defaultTR;
            result.datasetFolder = autoDatasetFolder;
            setappdata(dlg,'result',result);
            uiresume(dlg);
        end
    end
end


%% =========================================================
%  LOAD OPTIONS DIALOG SCALING HELPER
% =========================================================
function studio_scale_load_options_dialog(dlg, sx, sy, fontScale)
    if nargin < 2 || isempty(sx), sx = 1.0; end
    if nargin < 3 || isempty(sy), sy = sx; end
    if nargin < 4 || isempty(fontScale), fontScale = max(sx,sy); end

    try
        hs = findall(dlg);
    catch
        return;
    end

    for ii = 1:numel(hs)
        h = hs(ii);

        try
            if isequal(h, dlg)
                continue;
            end
        catch
        end

        try
            typ = get(h,'Type');
        catch
            typ = '';
        end

        if ~(strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel'))
            continue;
        end

        try
            oldUnits = get(h,'Units');
            set(h,'Units','pixels');
            p = get(h,'Position');
            if isnumeric(p) && numel(p) >= 4
                p(1) = round(p(1) * sx);
                p(2) = round(p(2) * sy);
                p(3) = round(p(3) * sx);
                p(4) = round(p(4) * sy);
                set(h,'Position',p);
            end
            set(h,'Units',oldUnits);
        catch
        end

        try
            fs = get(h,'FontSize');
            if isnumeric(fs) && isfinite(fs) && fs > 0
                set(h,'FontSize',max(9, round(fs * fontScale)));
            end
        catch
        end
    end
end

%% =========================================================
%  ROBUST FILE PICKER HELPER
% =========================================================
function [file,path] = studio_uigetfile_robust(filterSpec, titleStr, startDir)
    if nargin < 3 || isempty(startDir) || exist(startDir,'dir') ~= 7
        startDir = '';
        try
            if ispref('fusi_studio','lastLoadPath')
                p = getpref('fusi_studio','lastLoadPath');
                if ischar(p) && exist(p,'dir')
                    startDir = p;
                end
            end
        catch
        end
    end

    if isempty(startDir) || exist(startDir,'dir') ~= 7
        if ispc
            homeDir = getenv('USERPROFILE');
        else
            homeDir = getenv('HOME');
        end
        if ~isempty(homeDir) && exist(homeDir,'dir')
            desktopDir = fullfile(homeDir,'Desktop');
            if exist(desktopDir,'dir')
                startDir = desktopDir;
            else
                startDir = homeDir;
            end
        else
            startDir = pwd;
        end
    end

    try
        [file,path] = uigetfile(filterSpec, titleStr, startDir);
    catch
        try
            [file,path] = uigetfile(filterSpec, titleStr, pwd);
        catch
            [file,path] = uigetfile(filterSpec, titleStr);
        end
    end

    try
        if ~isequal(file,0) && ischar(path) && exist(path,'dir')
            setpref('fusi_studio','lastLoadPath',path);
        end
    catch
    end
end


%% =========================================================
%  CUSTOM TR DEFAULT HELPER
% =========================================================
function ms = studio_custom_tr_ms_default(data, meta, defaultTR)
    ms = defaultTR * 1000;

    try
        [tr, ~] = studio_get_file_tr_candidate(data, meta);
        if ~isempty(tr) && isnumeric(tr) && isscalar(tr) && isfinite(tr) && tr > 0
            ms = double(tr) * 1000;
        end
    catch
    end
end

%% =========================================================
%  PROBE DEFAULT TR HELPER
% =========================================================
function tr = studio_probe_default_tr_seconds(probeType, data)
    %#ok<INUSD>
    tr = 0.320;

    try
        s = lower(strtrim(char(probeType)));
    catch
        s = '';
    end

    is3D = false;

    if ~isempty(s)
        if ~isempty(strfind(s,'3d')) || ~isempty(strfind(s,'matrix'))
            is3D = true;
        end
    end

    if is3D
        tr = 0.480;
    else
        tr = 0.320;
    end
end

%% =========================================================
%  FILE TR DETECTION HELPER
% =========================================================
function [tr, source] = studio_get_file_tr_candidate(data, meta)
    tr = [];
    source = 'not found';

    try
        if isstruct(meta) && isfield(meta,'rawMetadata') && isstruct(meta.rawMetadata)
            rm = meta.rawMetadata;

            if isfield(rm,'TRDetectedFromFileSec') && ~isempty(rm.TRDetectedFromFileSec)
                v = rm.TRDetectedFromFileSec;
                if isnumeric(v) && isscalar(v) && isfinite(v) && v > 0
                    tr = double(v);
                    source = 'TRDetectedFromFileSec';
                    return;
                end
            end

            if isfield(rm,'TRWasImputed') && isequal(rm.TRWasImputed,false)
                if isfield(rm,'TRBeforeUserChoiceSec') && ~isempty(rm.TRBeforeUserChoiceSec)
                    v = rm.TRBeforeUserChoiceSec;
                    if isnumeric(v) && isscalar(v) && isfinite(v) && v > 0
                        tr = double(v);
                        source = 'TRBeforeUserChoiceSec';
                        return;
                    end
                end
            end
        end
    catch
    end

    try
        if isstruct(data) && isfield(data,'TR') && ~isempty(data.TR)
            v = data.TR;
            if isnumeric(v) && isscalar(v) && isfinite(v) && v > 0
                if isstruct(meta) && isfield(meta,'rawMetadata') && isstruct(meta.rawMetadata) && ...
                        isfield(meta.rawMetadata,'TRWasImputed') && isequal(meta.rawMetadata.TRWasImputed,false)
                    tr = double(v);
                    source = 'data.TR from file';
                    return;
                end
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




%% =========================================================
%  SETUP POPUP SIZE HELPER
% =========================================================
function studio_enlarge_setup_popup_if_needed(hFig)
    try
        if isempty(hFig) || ~ishghandle(hFig)
            return;
        end
        if ~strcmpi(get(hFig,'Type'),'figure')
            return;
        end

        tagName = 'Patch25SetupPopupScaled';
        try
            if isappdata(hFig,tagName)
                return;
            end
            setappdata(hFig,tagName,true);
        catch
        end

        blob = '';
        try
            blob = lower(char(get(hFig,'Name')));
        catch
            blob = '';
        end

        try
            hsText = findall(hFig,'Type','uicontrol');
            for kk = 1:numel(hsText)
                try
                    s = get(hsText(kk),'String');
                    if iscell(s)
                        tmp = '';
                        for jj = 1:numel(s)
                            tmp = [tmp ' ' char(s{jj})]; %#ok<AGROW>
                        end
                        s = tmp;
                    end
                    if isnumeric(s)
                        s = num2str(s);
                    end
                    blob = [blob ' ' lower(char(s))]; %#ok<AGROW>
                catch
                end
            end
        catch
        end

        isScrub = ~isempty(strfind(blob,'scrub')) || ~isempty(strfind(blob,'dvars'));
        isTemp  = ~isempty(strfind(blob,'temporal smoothing')) || ~isempty(strfind(blob,'subsampling')) || ~isempty(strfind(blob,'subsample'));
        isFilt  = ~isempty(strfind(blob,'filtering')) || ~isempty(strfind(blob,' filter')) || ~isempty(strfind(blob,'bandpass')) || ~isempty(strfind(blob,'high-pass')) || ~isempty(strfind(blob,'low-pass'));

        if ~(isScrub || isTemp || isFilt)
            return;
        end

        if isScrub
            growW = 1.38;
            growH = 1.30;
            fontScale = 1.35;
            minFont = 13;
        elseif isTemp
            growW = 1.36;
            growH = 1.24;
            fontScale = 1.24;
            minFont = 12;
        else
            growW = 1.34;
            growH = 1.24;
            fontScale = 1.24;
            minFont = 12;
        end

        try
            set(hFig,'Units','pixels');
            pos = get(hFig,'Position');
            scr = get(0,'ScreenSize');

            hs = findall(hFig);
            maxX = pos(3);
            maxY = pos(4);
            minX = inf;
            minY = inf;
            for kk = 1:numel(hs)
                h = hs(kk);
                if isequal(h,hFig)
                    continue;
                end
                try
                    typ = get(h,'Type');
                catch
                    typ = '';
                end
                if strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel') || strcmpi(typ,'axes')
                    try
                        oldUnits = get(h,'Units');
                        set(h,'Units','pixels');
                        p = get(h,'Position');
                        set(h,'Units',oldUnits);
                        if isnumeric(p) && numel(p) >= 4
                            minX = min(minX,p(1));
                            minY = min(minY,p(2));
                            maxX = max(maxX,p(1)+p(3));
                            maxY = max(maxY,p(2)+p(4));
                        end
                    catch
                    end
                end
            end

            margin = 70;
            needW = max(round(pos(3)*growW), round(maxX + margin));
            needH = max(round(pos(4)*growH), round(maxY + margin));

            maxAllowedW = max(760, scr(3) - 80);
            maxAllowedH = max(560, scr(4) - 110);

            newW = min(needW, maxAllowedW);
            newH = min(needH, maxAllowedH);

            newX = round((scr(3)-newW)/2);
            newY = round((scr(4)-newH)/2);
            newX = max(20,newX);
            newY = max(35,newY);

            set(hFig,'Position',[newX newY newW newH]);
        catch
            newW = [];
            newH = [];
        end

        try
            hs = findall(hFig);
            for kk = 1:numel(hs)
                h = hs(kk);
                if isequal(h,hFig)
                    continue;
                end

                try
                    typ = get(h,'Type');
                catch
                    typ = '';
                end

                if strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel')
                    try
                        oldUnits = get(h,'Units');
                        set(h,'Units','pixels');
                        p = get(h,'Position');
                        if isnumeric(p) && numel(p) >= 4
                            p(3) = round(p(3) * 1.04);
                            p(4) = round(p(4) * 1.08);
                            set(h,'Position',p);
                        end
                        set(h,'Units',oldUnits);
                    catch
                    end
                end

                try
                    fs = get(h,'FontSize');
                    if isnumeric(fs) && isfinite(fs) && fs > 0
                        set(h,'FontSize',max(minFont,round(fs*fontScale)));
                    end
                catch
                end

                try
                    set(h,'FontWeight','bold');
                catch
                end
            end
        catch
        end

        try
            studio_fit_popup_children_to_window(hFig);
        catch
        end

        try
            drawnow;
        catch
        end
    catch
    end
end

function studio_fit_popup_children_to_window(hFig)
    if isempty(hFig) || ~ishghandle(hFig)
        return;
    end

    try
        set(hFig,'Units','pixels');
        figPos = get(hFig,'Position');
    catch
        return;
    end

    marginLeft = 35;
    marginRight = 45;
    marginBottom = 35;
    marginTop = 35;

    hs = findall(hFig);
    maxX = -inf;
    maxY = -inf;
    minX = inf;
    minY = inf;

    keep = false(size(hs));
    posCell = cell(size(hs));

    for kk = 1:numel(hs)
        h = hs(kk);
        if isequal(h,hFig)
            continue;
        end
        try
            typ = get(h,'Type');
        catch
            typ = '';
        end
        if strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel') || strcmpi(typ,'axes')
            try
                oldUnits = get(h,'Units');
                set(h,'Units','pixels');
                p = get(h,'Position');
                set(h,'Units',oldUnits);
                if isnumeric(p) && numel(p) >= 4
                    keep(kk) = true;
                    posCell{kk} = p;
                    minX = min(minX,p(1));
                    minY = min(minY,p(2));
                    maxX = max(maxX,p(1)+p(3));
                    maxY = max(maxY,p(2)+p(4));
                end
            catch
            end
        end
    end

    if ~isfinite(maxX) || ~isfinite(maxY)
        return;
    end

    scr = get(0,'ScreenSize');
    needW = round(maxX + marginRight);
    needH = round(maxY + marginTop);
    maxAllowedW = max(760, scr(3)-80);
    maxAllowedH = max(560, scr(4)-110);

    newW = min(max(figPos(3),needW),maxAllowedW);
    newH = min(max(figPos(4),needH),maxAllowedH);

    if newW ~= figPos(3) || newH ~= figPos(4)
        figPos(3) = newW;
        figPos(4) = newH;
        figPos(1) = max(20,round((scr(3)-newW)/2));
        figPos(2) = max(35,round((scr(4)-newH)/2));
        set(hFig,'Position',figPos);
    end

    figW = figPos(3);
    figH = figPos(4);

    overflowX = maxX - (figW - marginRight);
    overflowY = maxY - (figH - marginTop);

    shiftX = 0;
    shiftY = 0;
    if minX < marginLeft
        shiftX = marginLeft - minX;
    elseif overflowX > 0
        shiftX = -overflowX;
    end
    if minY < marginBottom
        shiftY = marginBottom - minY;
    elseif overflowY > 0
        shiftY = -overflowY;
    end

    for kk = 1:numel(hs)
        if ~keep(kk)
            continue;
        end
        h = hs(kk);
        p = posCell{kk};
        try
            oldUnits = get(h,'Units');
            set(h,'Units','pixels');
            p(1) = p(1) + shiftX;
            p(2) = p(2) + shiftY;

            if p(1) + p(3) > figW - marginRight
                p(3) = max(40, figW - marginRight - p(1));
            end
            if p(2) + p(4) > figH - marginTop
                p(4) = max(20, figH - marginTop - p(2));
            end
            if p(1) < marginLeft
                p(1) = marginLeft;
            end
            if p(2) < marginBottom
                p(2) = marginBottom;
            end

            set(h,'Position',p);
            set(h,'Units',oldUnits);
        catch
        end
    end
end





function tf = studio_is_step_motor_dataset(data, studio)
% HUMOR_STUDIO_IMREG_FORCE_MOTOR_PATCH_V2
tf = false;
try
    if isstruct(data)
        if isfield(data,'motorInfo') && ~isempty(data.motorInfo)
            tf = true; return;
        end
        if isfield(data,'isStepMotor') && ~isempty(data.isStepMotor) && logical(data.isStepMotor(1))
            tf = true; return;
        end
        if isfield(data,'stepMotorMode') && ~isempty(data.stepMotorMode) && logical(data.stepMotorMode(1))
            tf = true; return;
        end
        if isfield(data,'preprocessing') && ischar(data.preprocessing)
            s = lower(data.preprocessing);
            if ~isempty(strfind(s,'motor')) || ~isempty(strfind(s,'step'))
                tf = true; return;
            end
        end
    end
    if isstruct(studio)
        if isfield(studio,'loadedFile') && ischar(studio.loadedFile)
            s = lower(studio.loadedFile);
            if ~isempty(strfind(s,'motor')) || ~isempty(strfind(s,'step'))
                tf = true; return;
            end
        end
        if isfield(studio,'loadedName') && ischar(studio.loadedName)
            s = lower(studio.loadedName);
            if ~isempty(strfind(s,'motor')) || ~isempty(strfind(s,'step'))
                tf = true; return;
            end
        end
        if isfield(studio,'meta') && isstruct(studio.meta) && isfield(studio.meta,'rawMetadata') && isstruct(studio.meta.rawMetadata)
            R = studio.meta.rawMetadata;
            if isfield(R,'isStepMotor') && ~isempty(R.isStepMotor) && logical(R.isStepMotor(1))
                tf = true; return;
            end
            if isfield(R,'motorInfo') && ~isempty(R.motorInfo)
                tf = true; return;
            end
        end
    end
catch
    tf = false;
end
end

function s = studio_short_output_stem(s, maxN)
% HUMOR_STUDIO_SHORT_NAMES_PATCH_V2
if nargin < 2 || isempty(maxN), maxN = 48; end
try, s = char(s); catch, s = 'dataset'; end
s = regexprep(s,'[^A-Za-z0-9_\-]','_');
s = regexprep(s,'_+','_');
s = regexprep(s,'^_+|_+$','');
if isempty(s), s = 'dataset'; end
if numel(s) > maxN
    s = s(1:maxN);
    s = regexprep(s,'_+$','');
end
end
%%%FUSI_STUDIO_SOURCE_END%%%
%}
