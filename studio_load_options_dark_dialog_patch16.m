function [TR, datasetFolder, wasCancelled, probeType, defaultTR] = studio_load_options_dark_dialog_patch16(initialTR, autoDatasetFolder, analysedRoot, datasetName, probeTypeIn, defaultTRIn, data, meta, fullInputFile)
% studio_load_options_dark_dialog_patch16
% Dark modern Load Dataset popup for HUMoR / fUSI Studio.
% MATLAB 2017b + 2023b compatible.

if nargin < 1, initialTR = []; end
if nargin < 2, autoDatasetFolder = ''; end
if nargin < 3, analysedRoot = ''; end
if nargin < 4, datasetName = 'Dataset'; end
if nargin < 5, probeTypeIn = ''; end
if nargin < 6, defaultTRIn = []; end
if nargin < 7, data = struct(); end
if nargin < 8, meta = struct(); end
if nargin < 9, fullInputFile = ''; end

info = localProbeInfoPatch16(probeTypeIn, defaultTRIn, data, meta);
probeType = info.displayName;
defaultTR = info.defaultTR;

if isempty(autoDatasetFolder)
    autoDatasetFolder = fullfile(pwd,'AnalysedData',datasetName);
end
if isempty(analysedRoot)
    analysedRoot = fileparts(autoDatasetFolder);
end
if isempty(analysedRoot) || exist(analysedRoot,'dir') ~= 7
    analysedRoot = pwd;
end

[fileTR, fileTRSource] = localFindFileTRPatch16(data, meta, fullInputFile);
hasFileTR = ~isempty(fileTR) && isfinite(fileTR) && fileTR > 0;

customTRDefault = defaultTR;
if hasFileTR
    customTRDefault = fileTR;
end

TR = defaultTR;
datasetFolder = autoDatasetFolder;
wasCancelled = false;

bg     = [0.065 0.075 0.095];
panel  = [0.115 0.125 0.155];
panel2 = [0.165 0.175 0.215];
fg     = [0.94 0.94 0.94];
muted  = [0.74 0.76 0.80];
green  = [0.10 0.50 0.24];
red    = [0.62 0.13 0.12];
blue   = [0.12 0.28 0.52];
orange = [0.92 0.55 0.16];
cyan   = [0.32 0.72 0.95];

W = 1080;
H = 780;
scr = get(0,'ScreenSize');
x0 = max(30, round((scr(3)-W)/2));
y0 = max(30, round((scr(4)-H)/2));

dlg = figure('Name','Load dataset options', 'NumberTitle','off', 'MenuBar','none', 'ToolBar','none', 'Color',bg, 'Units','pixels', 'Position',[x0 y0 W H], 'Resize','off', 'WindowStyle','modal', 'CloseRequestFcn',@onCancel);

result = struct('cancel',true,'TR',defaultTR,'datasetFolder',autoDatasetFolder);
setappdata(dlg,'result',result);

uicontrol(dlg,'Style','text', 'String','Load dataset options', 'Units','pixels', 'Position',[40 720 980 38], 'BackgroundColor',bg, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',24, 'FontWeight','bold', 'HorizontalAlignment','left');
uicontrol(dlg,'Style','text', 'String','Confirm probe type, temporal resolution, and output location before importing.', 'Units','pixels', 'Position',[40 690 980 25], 'BackgroundColor',bg, 'ForegroundColor',muted, 'FontName','Arial', 'FontSize',13, 'HorizontalAlignment','left');

% Probe / TR panel
uipanel('Parent',dlg, 'Units','pixels', 'Position',[40 455 1000 210], 'BackgroundColor',panel, 'ForegroundColor',fg, 'BorderType','line', 'HighlightColor',panel2);

uicontrol(dlg,'Style','text', 'String','Probe and temporal resolution', 'Units','pixels', 'Position',[70 625 800 28], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',17, 'FontWeight','bold', 'HorizontalAlignment','left');

probeLine = sprintf('Detected probe type: %s', probeType);
defaultLine = sprintf('Probe default TR: %.0f ms (%.3f s)', defaultTR*1000, defaultTR);
if hasFileTR
    fileLine = sprintf('File TR candidate: %.0f ms (%.3f s)   |   Source: %s', fileTR*1000, fileTR, fileTRSource);
else
    fileLine = 'File TR candidate: not found in metadata/timestamps';
end

uicontrol(dlg,'Style','text', 'String',probeLine, 'Units','pixels', 'Position',[70 592 920 24], 'BackgroundColor',panel, 'ForegroundColor',cyan, 'FontName','Arial', 'FontSize',13, 'FontWeight','bold', 'HorizontalAlignment','left');
uicontrol(dlg,'Style','text', 'String',defaultLine, 'Units','pixels', 'Position',[70 565 920 24], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',13, 'HorizontalAlignment','left');
uicontrol(dlg,'Style','text', 'String',fileLine, 'Units','pixels', 'Position',[70 538 920 24], 'BackgroundColor',panel, 'ForegroundColor',muted, 'FontName','Arial', 'FontSize',12, 'HorizontalAlignment','left');

hUseDefaultTR = uicontrol(dlg,'Style','radiobutton', 'String',sprintf('Use probe default TR: %.0f ms', defaultTR*1000), 'Value',1, 'Units','pixels', 'Position',[70 500 390 30], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',13, 'FontWeight','bold', 'Callback',@onDefaultTR);
hUseCustomTR = uicontrol(dlg,'Style','radiobutton', 'String','Use custom TR', 'Value',0, 'Units','pixels', 'Position',[490 500 180 30], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',13, 'Callback',@onCustomTR);
hCustomTRms = uicontrol(dlg,'Style','edit', 'String',sprintf('%.0f',customTRDefault*1000), 'Units','pixels', 'Position',[675 497 120 34], 'BackgroundColor',[0.24 0.24 0.27], 'ForegroundColor',[0.85 0.85 0.85], 'FontName','Arial', 'FontSize',14, 'HorizontalAlignment','center', 'Enable','off');
uicontrol(dlg,'Style','text', 'String','ms', 'Units','pixels', 'Position',[805 502 50 24], 'BackgroundColor',panel, 'ForegroundColor',muted, 'FontName','Arial', 'FontSize',13, 'HorizontalAlignment','left');

if hasFileTR
    hintText = 'Probe default is selected. The detected file TR is pre-filled in Custom TR in case you want to use it.';
else
    hintText = 'Probe default is selected. Enter Custom TR only if the acquisition used another value.';
end
hTRHint = uicontrol(dlg,'Style','text', 'String',hintText, 'Units','pixels', 'Position',[70 465 920 24], 'BackgroundColor',panel, 'ForegroundColor',orange, 'FontName','Arial', 'FontSize',11, 'HorizontalAlignment','left');

% Output panel
uipanel('Parent',dlg, 'Units','pixels', 'Position',[40 125 1000 300], 'BackgroundColor',panel, 'ForegroundColor',fg, 'BorderType','line', 'HighlightColor',panel2);
uicontrol(dlg,'Style','text', 'String','Output folder', 'Units','pixels', 'Position',[70 385 500 28], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',17, 'FontWeight','bold', 'HorizontalAlignment','left');

hAutoOut = uicontrol(dlg,'Style','radiobutton', 'String','Automatic output folder (recommended)', 'Value',1, 'Units','pixels', 'Position',[70 348 430 30], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',13, 'FontWeight','bold', 'Callback',@onAutoOut);
hCustomOut = uicontrol(dlg,'Style','radiobutton', 'String','Choose custom output parent folder', 'Value',0, 'Units','pixels', 'Position',[540 348 390 30], 'BackgroundColor',panel, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',13, 'Callback',@onCustomOut);

uicontrol(dlg,'Style','text', 'String','Automatic dataset folder:', 'Units','pixels', 'Position',[70 315 500 24], 'BackgroundColor',panel, 'ForegroundColor',muted, 'FontName','Arial', 'FontSize',11, 'HorizontalAlignment','left');
hAutoPath = uicontrol(dlg,'Style','edit', 'String',autoDatasetFolder, 'Units','pixels', 'Position',[70 282 900 32], 'BackgroundColor',panel2, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',10, 'HorizontalAlignment','left', 'Enable','inactive');

uicontrol(dlg,'Style','text', 'String','Custom parent folder. The dataset folder will be created inside this parent folder:', 'Units','pixels', 'Position',[70 242 820 24], 'BackgroundColor',panel, 'ForegroundColor',muted, 'FontName','Arial', 'FontSize',11, 'HorizontalAlignment','left');

startDir = analysedRoot;
try
    if ispref('fusi_studio','lastOutputParent')
        p0 = getpref('fusi_studio','lastOutputParent');
        if ischar(p0) && exist(p0,'dir') == 7
            startDir = p0;
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

hParent = uicontrol(dlg,'Style','edit', 'String',startDir, 'Units','pixels', 'Position',[70 202 760 36], 'BackgroundColor',[0.24 0.24 0.27], 'ForegroundColor',[0.85 0.85 0.85], 'FontName','Arial', 'FontSize',11, 'HorizontalAlignment','left', 'Enable','off');
hBrowse = uicontrol(dlg,'Style','pushbutton', 'String','Browse', 'Units','pixels', 'Position',[850 202 120 36], 'BackgroundColor',blue, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',12, 'FontWeight','bold', 'Enable','off', 'Callback',@onBrowse);
hOutHint = uicontrol(dlg,'Style','text', 'String','Automatic mode keeps the current HUMoR/fUSI Studio folder workflow unchanged.', 'Units','pixels', 'Position',[70 160 900 26], 'BackgroundColor',panel, 'ForegroundColor',orange, 'FontName','Arial', 'FontSize',11, 'HorizontalAlignment','left');

uicontrol(dlg,'Style','pushbutton', 'String','Cancel', 'Units','pixels', 'Position',[710 50 150 52], 'BackgroundColor',red, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',14, 'FontWeight','bold', 'Callback',@onCancel);
uicontrol(dlg,'Style','pushbutton', 'String','Proceed', 'Units','pixels', 'Position',[885 50 155 52], 'BackgroundColor',green, 'ForegroundColor',fg, 'FontName','Arial', 'FontSize',14, 'FontWeight','bold', 'Callback',@onProceed);

drawnow;
uiwait(dlg);

if ishandle(dlg)
    result = getappdata(dlg,'result');
    try delete(dlg); catch, end
else
    result = struct('cancel',true,'TR',defaultTR,'datasetFolder',autoDatasetFolder);
end

if isfield(result,'cancel') && result.cancel
    wasCancelled = true;
    TR = defaultTR;
    datasetFolder = autoDatasetFolder;
    return;
end

TR = result.TR;
datasetFolder = result.datasetFolder;
wasCancelled = false;
try setpref('fusi_studio','lastTR',TR); catch, end

    function onDefaultTR(~,~)
        if ~ishandle(dlg), return; end
        set(hUseDefaultTR,'Value',1);
        set(hUseCustomTR,'Value',0);
        set(hCustomTRms,'Enable','off','BackgroundColor',[0.24 0.24 0.27],'ForegroundColor',[0.85 0.85 0.85]);
        set(hTRHint,'String','Probe default TR is selected. Use Custom TR only if needed.','ForegroundColor',orange);
    end

    function onCustomTR(~,~)
        if ~ishandle(dlg), return; end
        set(hUseDefaultTR,'Value',0);
        set(hUseCustomTR,'Value',1);
        set(hCustomTRms,'Enable','on','BackgroundColor',[0.98 0.98 0.98],'ForegroundColor',[0 0 0]);
        if hasFileTR
            set(hTRHint,'String','Custom TR selected. The box is pre-filled with the file TR candidate.','ForegroundColor',muted);
        else
            set(hTRHint,'String','Custom TR selected. Enter the acquisition TR in milliseconds.','ForegroundColor',muted);
        end
    end

    function onAutoOut(~,~)
        if ~ishandle(dlg), return; end
        set(hAutoOut,'Value',1);
        set(hCustomOut,'Value',0);
        set(hParent,'Enable','off','BackgroundColor',[0.24 0.24 0.27],'ForegroundColor',[0.85 0.85 0.85]);
        set(hBrowse,'Enable','off');
        set(hOutHint,'String','Automatic mode keeps the current HUMoR/fUSI Studio folder workflow unchanged.','ForegroundColor',orange);
    end

    function onCustomOut(~,~)
        if ~ishandle(dlg), return; end
        set(hAutoOut,'Value',0);
        set(hCustomOut,'Value',1);
        set(hParent,'Enable','on','BackgroundColor',[0.98 0.98 0.98],'ForegroundColor',[0 0 0]);
        set(hBrowse,'Enable','on');
        set(hOutHint,'String','Custom mode: the dataset folder will be created inside the selected parent folder.','ForegroundColor',muted);
    end

    function onBrowse(~,~)
        if ~ishandle(dlg), return; end
        cur = get(hParent,'String');
        if isempty(cur) || exist(cur,'dir') ~= 7
            cur = startDir;
        end
        picked = uigetdir(cur,'Select output parent folder');
        if isequal(picked,0), return; end
        set(hParent,'String',picked);
        onCustomOut();
    end

    function onProceed(~,~)
        if ~ishandle(dlg), return; end

        if get(hUseDefaultTR,'Value') == 1
            trVal = defaultTR;
        else
            trMs = str2double(strtrim(get(hCustomTRms,'String')));
            if isempty(trMs) || ~isfinite(trMs) || trMs <= 0
                errordlg('Please enter a valid positive custom TR in milliseconds.','Invalid TR');
                return;
            end
            trVal = trMs / 1000;
        end

        if isempty(trVal) || ~isfinite(trVal) || trVal <= 0.02 || trVal > 20
            errordlg('TR must be between 20 ms and 20 seconds.','Invalid TR');
            return;
        end

        if get(hCustomOut,'Value') == 1
            parentDir = strtrim(get(hParent,'String'));
            if isempty(parentDir) || exist(parentDir,'dir') ~= 7
                errordlg('Please choose a valid output parent folder.','Invalid output folder');
                return;
            end
            outFolder = fullfile(parentDir,datasetName);
            try setpref('fusi_studio','lastOutputParent',parentDir); catch, end
        else
            outFolder = autoDatasetFolder;
        end

        result = struct();
        result.cancel = false;
        result.TR = trVal;
        result.datasetFolder = outFolder;
        setappdata(dlg,'result',result);
        uiresume(dlg);
    end

    function onCancel(~,~)
        if ishandle(dlg)
            result = struct('cancel',true,'TR',defaultTR,'datasetFolder',autoDatasetFolder);
            setappdata(dlg,'result',result);
            uiresume(dlg);
        end
    end
end

function info = localProbeInfoPatch16(probeTypeIn, defaultTRIn, data, meta)
info = struct();
info.displayName = '2D probe';
info.defaultTR = 0.320;

summary = lower([localToCharPatch16(probeTypeIn) ' ' localStructSummaryPatch16(meta,0) ' ' localStructSummaryPatch16(data,0)]);

explicit3D = localHasAnyPatch16(summary,{'3d','3-d','matrix','volumetric','volumeprobe','probe3d'});
isStep = localHasAnyPatch16(summary,{'stepmotor','step motor','zaber','motorreconstruction','framesperplane','frameperplane','nplanes','numplanes'});

try
    if isstruct(data)
        if isfield(data,'isStepMotor') && logical(data.isStepMotor), isStep = true; end
        if isfield(data,'stepMotor') && ~isempty(data.stepMotor), isStep = true; end
        if isfield(data,'motor') && ~isempty(data.motor), isStep = true; end
        if isfield(data,'motorMeta') && ~isempty(data.motorMeta), isStep = true; end
    end
catch
end

% Only use data dimensionality as 3D evidence if it is not step-motor.
try
    if ~isStep && ~explicit3D && isstruct(data) && isfield(data,'I') && ~isempty(data.I)
        if ndims(data.I) >= 4 && size(data.I,3) > 1
            explicit3D = true;
        end
    end
catch
end

if explicit3D
    info.displayName = '3D / matrix probe';
    info.defaultTR = 0.480;
elseif isStep
    info.displayName = 'step-motor data (2D probe workflow)';
    info.defaultTR = 0.320;
else
    info.displayName = '2D probe';
    info.defaultTR = 0.320;
end

% Do not allow old file TR values to overwrite probe default TR.
% defaultTRIn is intentionally only used as weak fallback if everything above failed.
if isempty(info.defaultTR) || ~isfinite(info.defaultTR) || info.defaultTR <= 0
    if isnumeric(defaultTRIn) && isscalar(defaultTRIn) && isfinite(defaultTRIn) && defaultTRIn > 0
        info.defaultTR = double(defaultTRIn);
    else
        info.defaultTR = 0.320;
    end
end
end

function [tr, source] = localFindFileTRPatch16(data, meta, fullInputFile)
tr = [];
source = 'not found';

try
    if isstruct(meta) && isfield(meta,'rawMetadata') && isstruct(meta.rawMetadata)
        rm = meta.rawMetadata;
        if isfield(rm,'TRDetectedFromFileSec') && localGoodTRPatch16(rm.TRDetectedFromFileSec)
            tr = double(rm.TRDetectedFromFileSec);
            source = 'rawMetadata.TRDetectedFromFileSec';
            return;
        end
        if isfield(rm,'fileTRCandidateSec') && localGoodTRPatch16(rm.fileTRCandidateSec)
            tr = double(rm.fileTRCandidateSec);
            source = 'rawMetadata.fileTRCandidateSec';
            return;
        end
        if isfield(rm,'TRWasImputed') && isequal(rm.TRWasImputed,false)
            if isfield(rm,'TRBeforeUserChoiceSec') && localGoodTRPatch16(rm.TRBeforeUserChoiceSec)
                tr = double(rm.TRBeforeUserChoiceSec);
                source = 'rawMetadata.TRBeforeUserChoiceSec';
                return;
            end
        end
    end
catch
end

useDataTR = true;
try
    if isstruct(meta) && isfield(meta,'rawMetadata') && isstruct(meta.rawMetadata)
        if isfield(meta.rawMetadata,'TRWasImputed') && isequal(meta.rawMetadata.TRWasImputed,true)
            useDataTR = false;
        end
    end
catch
end

try
    if useDataTR && isstruct(data) && isfield(data,'TR') && localGoodTRPatch16(data.TR)
        tr = double(data.TR);
        source = 'data.TR';
        return;
    end
catch
end

try
    [tr, source] = localRecursiveFindTRPatch16(meta,'meta',0);
    if ~isempty(tr), return; end
catch
end

try
    [tr, source] = localRecursiveFindTRPatch16(data,'data',0);
    if ~isempty(tr), return; end
catch
end

% Lightweight MAT-file fallback: load only small candidate variables.
try
    if ischar(fullInputFile) && exist(fullInputFile,'file') == 2
        [~,~,ext] = fileparts(fullInputFile);
        if strcmpi(ext,'.mat')
            info = whos('-file',fullInputFile);
            for k = 1:numel(info)
                nm = lower(info(k).name);
                isCandidate = localHasAnyPatch16(nm,{'tr','dt','fs','fps','time','timestamp','framerate','samplingrate'});
                if isCandidate && info(k).bytes < 10000000
                    tmp = load(fullInputFile,info(k).name);
                    [tr, source] = localRecursiveFindTRPatch16(tmp,'matfile',0);
                    if ~isempty(tr)
                        return;
                    end
                end
            end
        end
    end
catch
    tr = [];
    source = 'not found';
end
end

function [tr, source] = localRecursiveFindTRPatch16(v, pathStr, depth)
tr = [];
source = 'not found';
if depth > 5 || isempty(v)
    return;
end

[tr, source] = localTRFromValuePatch16(v,pathStr);
if ~isempty(tr)
    return;
end

if isstruct(v)
    if numel(v) > 1, v = v(1); end
    fn = fieldnames(v);
    for i = 1:numel(fn)
        f = fn{i};
        lf = lower(f);
        skip = localHasAnyPatch16(lf,{'image','images','volume','volumes','functional','psc','underlay','overlay','mask','map','beforeuserchoice','afteruserchoice','chosentr','defaulttr','imputed'});
        if skip
            continue;
        end
        try
            [tr, source] = localRecursiveFindTRPatch16(v.(f),[pathStr '.' f],depth+1);
            if ~isempty(tr), return; end
        catch
        end
    end
elseif iscell(v) && numel(v) <= 25
    for i = 1:numel(v)
        try
            [tr, source] = localRecursiveFindTRPatch16(v{i},sprintf('%s{%d}',pathStr,i),depth+1);
            if ~isempty(tr), return; end
        catch
        end
    end
end
end

function [tr, source] = localTRFromValuePatch16(val, fieldPath)
tr = [];
source = 'not found';
nm = localLastNamePatch16(fieldPath);

if isnumeric(val) && isscalar(val) && isfinite(val) && val > 0
    v = double(val);
    cand = [];
    if localNameEqualsAnyPatch16(nm,{'trms','trmillisec','trmilliseconds','repetitiontimems','frameperiodms','framedurationms','volumeperiodms','samplingintervalms'})
        cand = v / 1000;
    elseif localNameEqualsAnyPatch16(nm,{'fs','fps','framerate','frameratehz','samplingrate','samplerate','volumerate'})
        cand = 1 / v;
    elseif localNameEqualsAnyPatch16(nm,{'tr','trs','trsec','trseconds','dt','deltat','repetitiontime','temporaldresolution','temporalresolution','frameperiod','frameduration','volumeperiod','samplinginterval','acquisitionperiod'})
        cand = v;
    end
    if ~isempty(cand) && localGoodTRPatch16(cand)
        tr = cand;
        source = fieldPath;
    end
    return;
end

if isnumeric(val) && isvector(val) && numel(val) >= 3
    if ~(localHasAnyPatch16(nm,{'time','timestamp','timestamps'}))
        return;
    end
    vv = double(val(:));
    vv = vv(isfinite(vv));
    if numel(vv) < 3, return; end
    d = diff(vv);
    d = d(isfinite(d) & d > 0);
    if isempty(d), return; end
    cand = median(d);
    if cand > 20
        cand = cand / 1000;
    end
    if localGoodTRPatch16(cand)
        tr = cand;
        source = fieldPath;
    end
end
end

function tf = localGoodTRPatch16(v)
tf = false;
try
    if isnumeric(v) && isscalar(v) && isfinite(v) && double(v) >= 0.02 && double(v) <= 20
        tf = true;
    end
catch
end
end

function nm = localLastNamePatch16(pathStr)
nm = char(pathStr);
d = strfind(nm,'.');
if ~isempty(d)
    nm = nm(d(end)+1:end);
end
b = strfind(nm,'{');
if ~isempty(b)
    nm = nm(1:b(1)-1);
end
nm = lower(regexprep(nm,'[^a-zA-Z0-9]',''));
end

function tf = localNameEqualsAnyPatch16(nm, keys)
tf = false;
nm = lower(regexprep(char(nm),'[^a-zA-Z0-9]',''));
for i = 1:numel(keys)
    kk = lower(regexprep(char(keys{i}),'[^a-zA-Z0-9]',''));
    if strcmp(nm,kk)
        tf = true;
        return;
    end
end
end

function s = localStructSummaryPatch16(x, depth)
s = '';
if depth > 2 || isempty(x)
    return;
end
try
    if ischar(x)
        s = x;
        return;
    end
    if iscell(x) && numel(x) <= 20
        for i = 1:numel(x)
            s = [s ' ' localStructSummaryPatch16(x{i},depth+1)];
        end
        return;
    end
    if isstruct(x)
        if numel(x) > 1, x = x(1); end
        fn = fieldnames(x);
        for i = 1:numel(fn)
            f = fn{i};
            s = [s ' ' f];
            try
                y = x.(f);
                if ischar(y) && numel(y) < 250
                    s = [s ' ' y];
                elseif iscell(y) && numel(y) <= 10
                    s = [s ' ' localStructSummaryPatch16(y,depth+1)];
                elseif isstruct(y) && depth < 2
                    s = [s ' ' localStructSummaryPatch16(y,depth+1)];
                end
            catch
            end
        end
    end
catch
    s = '';
end
end

function tf = localHasAnyPatch16(s, keys)
tf = false;
try
    s = lower(char(s));
catch
    s = '';
end
for i = 1:numel(keys)
    if ~isempty(strfind(s,lower(char(keys{i}))))
        tf = true;
        return;
    end
end
end

function s = localToCharPatch16(x)
try
    if isempty(x)
        s = '';
    else
        s = char(x);
    end
catch
    s = '';
end
end
