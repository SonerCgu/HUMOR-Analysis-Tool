function Seg = Segmentation(studio, data, logFcn)
% Segmentation.m
% HUMoR fUSI Studio atlas-based segmentation / region-time extraction.
%
% MATLAB 2017b + 2023b compatible, ASCII-safe.
%
% IMPORTANT IDEA
%   This is atlas-based segmentation, not AI/image segmentation.
%   The function takes functional fUSI data and an anatomical label map
%   from the Allen atlas / Registration2D / registered atlas-space data and
%   extracts one time course per anatomical region.
%
% OUTPUT
%   <exportPath>/Segmentation/Segmentation_yyyymmdd_HHMMSS.mat
%   <exportPath>/Segmentation/Segmentation_Both_zscore_*.csv
%   <exportPath>/Segmentation/Segmentation_Both_raw_*.csv
%   <exportPath>/Segmentation/Segmentation_RegionTable_*.csv
%
% RECOMMENDED WORKFLOWS
%   3D matrix / atlas-space workflow:
%       Registration to Atlas -> save *_registered_to_atlas_*.mat
%       Segmentation -> Source = Load registered functional MAT
%       Atlas source = Allen 3D atlas.Regions, or manual matching label map
%
%   2D / step-motor workflow:
%       Registration to Atlas -> Simple 2D coronal registration
%       Save Reg2D for each source slice
%       Segmentation -> Source = Active data.I or data.PSC
%       Atlas source = Step-motor Reg2D files from Registration2D
%
%   Baseline start/end are entered in seconds and converted to frames using TR.
%   Default baseline is 30-240 sec.
%
% Author/workflow: Soner Caner Cagun HUMoR Studio patch.

if nargin < 3 || isempty(logFcn)
    logFcn = @(s) fprintf('%s\n',s);
end

Seg = [];
logMsg(logFcn,'--- HUMoR Atlas Segmentation ---');

if nargin < 1 || isempty(studio) || ~isstruct(studio)
    error('studio struct is required.');
end
if nargin < 2 || isempty(data) || ~isstruct(data)
    error('active data struct is required.');
end

saveRoot = getStructString(studio,'exportPath',pwd);
if isempty(saveRoot) || ~exist(saveRoot,'dir')
    saveRoot = pwd;
end
segDir = fullfile(saveRoot,'Segmentation');
if ~exist(segDir,'dir')
    mkdir(segDir);
end

TR = getTRFromData(data);

% One modern dialog collects all settings.
cfg = showSegmentationSetupDialog(studio, data, TR, saveRoot, logFcn);
if isempty(cfg) || ~isstruct(cfg) || ~isfield(cfg,'cancelled') || cfg.cancelled
    logMsg(logFcn,'Segmentation cancelled.');
    return;
end

% -------------------------------------------------------------------------
% 1) Load functional source
% -------------------------------------------------------------------------
[D0, sourceInfo] = loadSegmentationFunctionalSource(cfg, studio, data, logFcn);
if isempty(D0)
    logMsg(logFcn,'Segmentation cancelled: no functional source.');
    return;
end

% -------------------------------------------------------------------------
% 2) Load/create atlas label map
% -------------------------------------------------------------------------
% Special step-motor mode: functional slices are warped to 2D atlas space
% using the saved Reg2D transforms, and region labels are stacked slice-wise.
if strcmpi(cfg.atlasMode,'step_reg2d')
    [D4, R, labelInfo] = buildStepMotorReg2DSegmentationInput(D0, cfg, studio, logFcn);
else
    D4 = force4DForSegmentation(D0, sourceInfo);
    [Y,X,Z,T] = size(D4);

% Fail-safe: Functional connectivity needs a real time series.
% If T is very small, the selected source is usually a static 3D registered
% atlas/anatomy/mean file that was accidentally interpreted as time.
if T < 10
    error(['Segmentation source has only %d time points after loading. ' ...
           'This is too short for functional connectivity and usually means ' ...
           'you selected a static 3D registered/atlas/anatomy/mean file. ' ...
           'Re-run Segmentation using active data.I / active data.PSC with real time, ' ...
           'or load a registered 4D functional MAT [Y X Z T].'], T);
end %#ok<ASGLU>
    [R, labelInfo] = loadSegmentationLabelMap(cfg, studio, data, Y, X, Z, logFcn);
end

if isempty(D4) || isempty(R)
    logMsg(logFcn,'Segmentation cancelled: missing functional data or label map.');
    return;
end

D4 = double(D4);
D4(~isfinite(D4)) = NaN;
R = round(double(R));
R(~isfinite(R)) = 0;

[Y,X,Z,T] = size(D4);

% Fail-safe: Functional connectivity needs a real time series.
% If T is very small, the selected source is usually a static 3D registered
% atlas/anatomy/mean file that was accidentally interpreted as time.
if T < 10
    error(['Segmentation source has only %d time points after loading. ' ...
           'This is too short for functional connectivity and usually means ' ...
           'you selected a static 3D registered/atlas/anatomy/mean file. ' ...
           'Re-run Segmentation using active data.I / active data.PSC with real time, ' ...
           'or load a registered 4D functional MAT [Y X Z T].'], T);
end
if ~isequal(size(R), [Y X Z])
    logMsg(logFcn,sprintf('Label map size %s differs from functional size [%d %d %d]. Resizing labels by nearest-neighbor.', mat2str(size(R)), Y, X, Z));
    R = resizeLabelVolumeNearest(R, Y, X, Z);
end

% -------------------------------------------------------------------------
% 3) Convert baseline seconds to frames
% -------------------------------------------------------------------------
[baseFrames, bStartFrame, bEndFrame, baseNote] = baselineSecondsToFrames(cfg.baselineStartSec, cfg.baselineEndSec, TR, T);
if ~isempty(baseNote)
    logMsg(logFcn,baseNote);
end

% -------------------------------------------------------------------------
% 4) Optional PSC conversion
% -------------------------------------------------------------------------
if cfg.computePSC
    logMsg(logFcn,sprintf('Converting functional source to PSC using baseline %.3g-%.3g sec (frames %d-%d).', cfg.baselineStartSec, cfg.baselineEndSec, bStartFrame, bEndFrame));
    D4 = computePSC4DLocal(D4, baseFrames);
else
    logMsg(logFcn,'PSC conversion OFF. Region raw table uses the selected source values as-is.');
end

% Valid data mask
validDataMask = true(Y,X,Z);
try
    tmpMean = nanmeanLocal(D4,4);
    validDataMask = isfinite(tmpMean);
catch
end

% -------------------------------------------------------------------------
% 5) Region extraction
% -------------------------------------------------------------------------
logMsg(logFcn,'Extracting left/right/bilateral region time courses...');
[LeftRaw, RightRaw, BothRaw, region] = extractRegionTimecourses(D4, R, validDataMask, labelInfo, cfg.minVoxels, logFcn);

LeftZ  = zscoreBaselineMatrix(LeftRaw,  baseFrames);
RightZ = zscoreBaselineMatrix(RightRaw, baseFrames);
BothZ  = zscoreBaselineMatrix(BothRaw,  baseFrames);

% -------------------------------------------------------------------------
% 6) Save outputs
% -------------------------------------------------------------------------
ts = datestr(now,'yyyymmdd_HHMMSS');

Seg = struct();
Seg.Left.raw = single(LeftRaw);
Seg.Right.raw = single(RightRaw);
Seg.Both.raw = single(BothRaw);
Seg.Left.z = single(LeftZ);
Seg.Right.z = single(RightZ);
Seg.Both.z = single(BothZ);
Seg.region = region;
Seg.settings = cfg;
Seg.settings.baselineFrames = baseFrames;
Seg.settings.baselineStartFrame = bStartFrame;
Seg.settings.baselineEndFrame = bEndFrame;
Seg.source = sourceInfo;
Seg.labelInfo = labelInfo;
Seg.labelMap = int32(R);
Seg.TR = TR;
Seg.timeSec = (0:T-1) .* TR;
Seg.timeMin = Seg.timeSec ./ 60;
Seg.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
Seg.description = 'Atlas-based region-time segmentation: mean signal per Allen CCF region.';

Seg.files = struct();
Seg.files.mat = fullfile(segDir, ['Segmentation_' ts '.mat']);
Seg.files.csvBothZ = fullfile(segDir, ['Segmentation_Both_zscore_' ts '.csv']);
Seg.files.csvBothRaw = fullfile(segDir, ['Segmentation_Both_raw_' ts '.csv']);
Seg.files.csvRegionTable = fullfile(segDir, ['Segmentation_RegionTable_' ts '.csv']);

save(Seg.files.mat, 'Seg', '-v7.3');
writeRegionTimeCSV(Seg.files.csvBothZ, Seg.Both.z, region, Seg.timeSec, 'zscore');
writeRegionTimeCSV(Seg.files.csvBothRaw, Seg.Both.raw, region, Seg.timeSec, 'raw');
writeRegionTableCSV(Seg.files.csvRegionTable, region);

try
    figFile = fullfile(segDir, ['Segmentation_Both_zscore_heatmap_' ts '.png']);
    makeSegmentationHeatmap(Seg.Both.z, region, figFile);
    Seg.files.heatmap = figFile;
    save(Seg.files.mat, 'Seg', '-v7.3');
catch MEfig
    logMsg(logFcn,['Could not save segmentation heatmap: ' MEfig.message]);
end

logMsg(logFcn,['Segmentation MAT saved: ' Seg.files.mat]);
logMsg(logFcn,['Segmentation CSV saved: ' Seg.files.csvBothZ]);
logMsg(logFcn,sprintf('Regions exported: %d | Time points: %d | Duration: %.3f min | TR: %.6g sec', numel(region.labels), T, max(Seg.timeSec(:))/60, TR));
logMsg(logFcn,'--- Segmentation finished ---');

end

%% ========================================================================
% One modern setup GUI
%% ========================================================================
function cfg = showSegmentationSetupDialog(studio, data, TR, saveRoot, logFcn)

cfg = struct();
cfg.cancelled = true;
cfg.sourceMode = 'active_i';
cfg.sourceFile = '';
cfg.atlasMode = 'manual_label';
cfg.labelFile = '';
cfg.reg2DFiles = {};
cfg.baselineStartSec = 30;
cfg.baselineEndSec = 240;
cfg.minVoxels = 5;
cfg.computePSC = false;

I = [];
if isfield(data,'I') && ~isempty(data.I)
    I = data.I;
end
if isempty(I) && isfield(data,'PSC') && ~isempty(data.PSC)
    I = data.PSC;
end

if isempty(I)
    dimTxt = 'No active functional data found';
    T = 1;
else
    sz = size(I);
    if ndims(I) == 3
        dimTxt = sprintf('%d x %d x %d  [2D time-series: Y x X x T]', sz(1), sz(2), sz(3));
        T = sz(3);
    elseif ndims(I) >= 4
        dimTxt = sprintf('%d x %d x %d x %d  [3D/step-motor: Y x X x Z x T]', sz(1), sz(2), sz(3), sz(4));
        T = sz(4);
    else
        dimTxt = mat2str(sz);
        T = max(1,sz(end));
    end
end

regDir = getRegistrationDir(studio, saveRoot);
reg2DDir = getRegistration2DDir(studio, saveRoot);

hasPSC = isfield(data,'PSC') && ~isempty(data.PSC);
hasAtlasField = dataHasAtlasField(data);

% GUI colors
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
yellow  = fgDim;  % yellow guidance text removed; keep variable for compatibility

dlg = figure( ...
    'Name','HUMoR Atlas Segmentation Setup', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Resize','off', ...
    'Units','pixels', ...
    'Position',[50 35 1420 780], ...
    'WindowStyle','modal', ...
    'Visible','off', ...
    'CloseRequestFcn',@onCancel, ...
    'KeyPressFcn',@onKey);

try, movegui(dlg,'center'); catch, end

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.035 0.935 0.93 0.045], ...
    'String','Atlas Segmentation / Region-Time Extraction', ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',27, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.037 0.895 0.93 0.032], ...
    'String','Segmentation means: atlas region labels + fUSI data -> one time course per Allen brain region. It is not machine-learning segmentation.', ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',13, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

infoPanel = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.035 0.812 0.93 0.070], ...
    'BackgroundColor',panel3, ...
    'ForegroundColor',[0.35 0.35 0.38], ...
    'BorderType','line');

uicontrol('Parent',infoPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.025 0.50 0.95 0.35], ...
    'String',['Active data: ' dimTxt], ...
    'BackgroundColor',panel3, ...
    'ForegroundColor',[0.72 0.86 1.00], ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',infoPanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.025 0.10 0.95 0.35], ...
    'String',sprintf('TR %.6g s | Total %.2f min | Registration2D start folder: %s', TR, (T*TR)/60, reg2DDir), ...
    'TooltipString',reg2DDir, ...
    'BackgroundColor',panel3, ...
    'ForegroundColor',[0.45 1.00 0.62], ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

% ---------------------------------------------------------------------
% Left: source + atlas labels
% ---------------------------------------------------------------------
srcPanel = uipanel('Parent',dlg, ...
    'Title','1. Functional source', ...
    'Units','normalized', ...
    'Position',[0.035 0.510 0.455 0.290], ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',16, ...
    'FontWeight','bold', ...
    'BorderType','line');

sourceStrings = {'Active data.I  [recommended for step-motor / current dataset]'};
sourceModes = {'active_i'};
if hasPSC
    sourceStrings{end+1} = 'Active data.PSC  [already percent signal change]';
    sourceModes{end+1} = 'active_psc';
end
sourceStrings{end+1} = 'Load registered functional MAT from Registration';
sourceModes{end+1} = 'registered_file';

makeText(srcPanel,[0.040 0.700 0.22 0.13],'Functional data',fg,12,'bold');
hSource = uicontrol('Parent',srcPanel,'Style','popupmenu', ...
    'Units','normalized', ...
    'Position',[0.280 0.700 0.52 0.15], ...
    'String',sourceStrings, ...
    'Value',1, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'Callback',@updateSummary);

uicontrol('Parent',srcPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.820 0.700 0.14 0.15], ...
    'String','LOAD', ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@onLoadSource);

hSourceStatus = makeText(srcPanel,[0.040 0.450 0.92 0.180], ...
    'No manual source loaded. Active dataset will be used unless Load registered MAT is selected.', fgDim, 10.5, 'bold');

uicontrol('Parent',srcPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.040 0.155 0.28 0.165], ...
    'String','Use Active I', ...
    'BackgroundColor',[0.30 0.30 0.34], ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@presetActiveI);

uicontrol('Parent',srcPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.350 0.155 0.28 0.165], ...
    'String','Load Registered', ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@presetRegistered);

atlasPanel = uipanel('Parent',dlg, ...
    'Title','2. Atlas / label source', ...
    'Units','normalized', ...
    'Position',[0.510 0.510 0.455 0.290], ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',16, ...
    'FontWeight','bold', ...
    'BorderType','line');

atlasStrings = { ...
    'Manual atlas label map from Registration2D  [pre-selected]', ...
    'Step-motor Reg2D files from Registration2D  [warps slices first]', ...
    'Allen 3D atlas.Regions  [for true 3D atlas-space data]', ...
    'Active dataset atlas / labels field'};
atlasModes = {'manual_label','step_reg2d','allen_3d','active_atlas'};

makeText(atlasPanel,[0.040 0.700 0.22 0.13],'Label source',fg,12,'bold');
hAtlas = uicontrol('Parent',atlasPanel,'Style','popupmenu', ...
    'Units','normalized', ...
    'Position',[0.280 0.700 0.52 0.15], ...
    'String',atlasStrings, ...
    'Value',1, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'Callback',@onAtlasChanged);

uicontrol('Parent',atlasPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.820 0.700 0.14 0.15], ...
    'String','LOAD', ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@onLoadAtlas);

hAtlasStatus = makeText(atlasPanel,[0.040 0.450 0.92 0.180], ...
    'Manual label map selected. Click LOAD or it will ask on RUN. Start folder = Registration2D.', fgDim, 10.5, 'bold');

uicontrol('Parent',atlasPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.040 0.155 0.28 0.165], ...
    'String','Manual labels', ...
    'BackgroundColor',[0.30 0.30 0.34], ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@presetManualLabels);

uicontrol('Parent',atlasPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.350 0.155 0.28 0.165], ...
    'String','Step Reg2D', ...
    'BackgroundColor',orange, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@presetStepReg2D);

uicontrol('Parent',atlasPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.660 0.155 0.28 0.165], ...
    'String','Auto-find Reg2D', ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'Callback',@autoFindReg2D);

% ---------------------------------------------------------------------
% Settings / explanation
% ---------------------------------------------------------------------
setPanel = uipanel('Parent',dlg, ...
    'Title','3. Baseline and extraction settings', ...
    'Units','normalized', ...
    'Position',[0.035 0.195 0.930 0.290], ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',16, ...
    'FontWeight','bold', ...
    'BorderType','line');

makeText(setPanel,[0.040 0.695 0.155 0.110],'Baseline START',fg,12,'bold');
hBaseStart = makeEdit(setPanel,[0.215 0.700 0.100 0.110],'30');
makeText(setPanel,[0.325 0.695 0.060 0.110],'sec',fgDim,11,'bold');

makeText(setPanel,[0.420 0.695 0.145 0.110],'Baseline END',fg,12,'bold');
hBaseEnd = makeEdit(setPanel,[0.570 0.700 0.100 0.110],'240');
makeText(setPanel,[0.680 0.695 0.060 0.110],'sec',fgDim,11,'bold');

makeText(setPanel,[0.040 0.500 0.250 0.110],'Minimum voxels / region',fg,12,'bold');
hMinVox = makeEdit(setPanel,[0.315 0.505 0.100 0.110],'5');
hPSC = uicontrol('Parent',setPanel,'Style','checkbox', ...
    'Units','normalized', ...
    'Position',[0.040 0.290 0.390 0.110], ...
    'String','Convert selected source to PSC before extraction', ...
    'Value',0, ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'Callback',@updateSummary);

makeText(setPanel,[0.455 0.285 0.500 0.110], ...
    'PSC ON = raw Doppler to percent signal change. OFF = already PSC/z-score or direct z-traces.', ...
    fgDim, 11, 'normal');

uicontrol('Parent',setPanel,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.740 0.655 0.210 0.155], ...
    'String','RESET: 30-240 s', ...
    'BackgroundColor',[0.30 0.30 0.34], ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'Callback',@presetBaseline);

hSummary = makeText(dlg,[0.035 0.115 0.930 0.070], '', [0.70 1.00 0.80], 11, 'bold');

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.500 0.035 0.260 0.060], ...
    'String','RUN SEGMENTATION', ...
    'BackgroundColor',green, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'Callback',@onRun);

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'Units','normalized', ...
    'Position',[0.790 0.035 0.175 0.060], ...
    'String','CANCEL', ...
    'BackgroundColor',red, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'Callback',@onCancel);

updateSummary();
set(dlg,'Visible','on');
waitfor(dlg);

    function h = makeText(parent,pos,str,col,fs,fw)
        if nargin < 6, fw = 'normal'; end
        h = uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',pos, ...
            'String',str, ...
            'BackgroundColor',getBg(parent,bg), ...
            'ForegroundColor',col, ...
            'FontName','Arial', ...
            'FontSize',fs, ...
            'FontWeight',fw, ...
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
            'HorizontalAlignment','center', ...
            'Callback',@updateSummary);
    end

    function c = getBg(h,defaultBg)
        c = defaultBg;
        try
            if isprop(h,'BackgroundColor')
                c = get(h,'BackgroundColor');
            end
        catch
        end
    end

    function updateSummary(varargin)
        b0 = str2double(get(hBaseStart,'String'));
        b1 = str2double(get(hBaseEnd,'String'));
        if ~isfinite(b0), b0 = NaN; end
        if ~isfinite(b1), b1 = NaN; end
        [~,f0,f1,note] = baselineSecondsToFrames(b0,b1,TR,T); %#ok<ASGLU>
        sourceList = get(hSource,'String');
        sourceTxt = sourceList{get(hSource,'Value')};
        atlasList = get(hAtlas,'String');
        atlasTxt = atlasList{get(hAtlas,'Value')};
        minV = str2double(get(hMinVox,'String'));
        pscTxt = 'OFF';
        if get(hPSC,'Value') ~= 0, pscTxt = 'ON'; end
        if isempty(note)
            note = sprintf('Baseline frames will be %d-%d.', f0, f1);
        end
        txt = sprintf('%s | %s | Baseline %.3g-%.3g s -> frames %d-%d | min voxels %.0f | PSC %s | %s', ...
            shortTxt(sourceTxt,44), shortTxt(atlasTxt,48), b0, b1, f0, f1, minV, pscTxt, note);
        if ishghandle(hSummary)
            set(hSummary,'String',txt);
        end
    end

    function onAtlasChanged(varargin)
        v = get(hAtlas,'Value');
        mode = atlasModes{v};
        if strcmpi(mode,'manual_label')
            set(hAtlasStatus,'String','Manual label map selected. Click LOAD or it will ask on RUN. Start folder = Registration2D.');
        elseif strcmpi(mode,'step_reg2d')
            set(hAtlasStatus,'String','Step-motor Reg2D selected. It will auto-find CoronalRegistration2D_source*.mat in Registration2D, or use LOAD.');
        elseif strcmpi(mode,'allen_3d')
            set(hAtlasStatus,'String','Allen 3D atlas.Regions selected. Best for true 3D atlas-space data.');
        else
            if hasAtlasField
                set(hAtlasStatus,'String','Active dataset atlas/labels field selected.');
            else
                set(hAtlasStatus,'String','No obvious active atlas field found; this may fail.');
            end
        end
        updateSummary();
    end

    function onLoadSource(varargin)
        v = get(hSource,'Value');
        mode = sourceModes{v};
        if ~strcmpi(mode,'registered_file')
            set(hSource,'Value',numel(sourceModes));
        end
        [f,p] = uigetfileStart({'*.mat','Registered functional MAT (*.mat)'}, ...
            'Load registered functional MAT', regDir);
        if isequal(f,0)
            return;
        end
        cfg.sourceFile = fullfile(p,f);
        set(hSourceStatus,'String',['Loaded source: ' shortTxt(f,80)]);
        updateSummary();
    end

    function onLoadAtlas(varargin)
        v = get(hAtlas,'Value');
        mode = atlasModes{v};
        if strcmpi(mode,'step_reg2d')
            files = autoFindReg2DFiles(reg2DDir);
            if isempty(files)
                [f,p] = uigetfileStart({'*.mat','Reg2D MAT files (*.mat)'}, ...
                    'Select one or multiple Reg2D files', reg2DDir, 'MultiSelect','on');
                if isequal(f,0), return; end
                if ischar(f)
                    files = {fullfile(p,f)};
                else
                    files = cell(size(f));
                    for ii = 1:numel(f), files{ii} = fullfile(p,f{ii}); end
                end
            end
            cfg.reg2DFiles = sortReg2DFiles(files);
            set(hAtlasStatus,'String',sprintf('Loaded/auto-found %d Reg2D files from Registration2D.', numel(cfg.reg2DFiles)));
        elseif strcmpi(mode,'manual_label')
            [f,p] = uigetfileStart({'*.mat;*.nii;*.nii.gz;*.tif;*.tiff','Atlas label files (*.mat,*.nii,*.nii.gz,*.tif)'}, ...
                'Load atlas integer label map', reg2DDir);
            if isequal(f,0), return; end
            cfg.labelFile = fullfile(p,f);
            set(hAtlasStatus,'String',['Loaded label map: ' shortTxt(f,80)]);
        else
            set(hAtlasStatus,'String','This atlas mode does not need manual loading.');
        end
        updateSummary();
    end

    function autoFindReg2D(varargin)
        set(hAtlas,'Value',2);
        files = autoFindReg2DFiles(reg2DDir);
        cfg.reg2DFiles = sortReg2DFiles(files);
        if isempty(files)
            set(hAtlasStatus,'String','No CoronalRegistration2D_source*.mat files found in Registration2D. Click LOAD to select manually.');
        else
            set(hAtlasStatus,'String',sprintf('Auto-found %d Reg2D files in Registration2D.', numel(files)));
        end
        updateSummary();
    end

    function presetActiveI(varargin)
        set(hSource,'Value',1);
        set(hSourceStatus,'String','Active data.I selected.');
        updateSummary();
    end

    function presetRegistered(varargin)
        set(hSource,'Value',numel(sourceModes));
        onLoadSource([],[]);
    end

    function presetManualLabels(varargin)
        set(hAtlas,'Value',1);
        onAtlasChanged([],[]);
    end

    function presetStepReg2D(varargin)
        set(hAtlas,'Value',2);
        autoFindReg2D([],[]);
    end

    function presetBaseline(varargin)
        set(hBaseStart,'String','30');
        set(hBaseEnd,'String','240');
        set(hMinVox,'String','5');
        set(hPSC,'Value',0);
        updateSummary();
    end

    function onRun(varargin)
        sourceVal = get(hSource,'Value');
        cfg.sourceMode = sourceModes{sourceVal};
        atlasVal = get(hAtlas,'Value');
        cfg.atlasMode = atlasModes{atlasVal};
        cfg.baselineStartSec = str2double(get(hBaseStart,'String'));
        cfg.baselineEndSec = str2double(get(hBaseEnd,'String'));
        cfg.minVoxels = round(str2double(get(hMinVox,'String')));
        cfg.computePSC = logical(get(hPSC,'Value'));
        cfg.cancelled = false;

        if ~isfinite(cfg.baselineStartSec) || cfg.baselineStartSec < 0
            uiwait(errordlg('Baseline START must be a number >= 0 sec.','Segmentation','modal'));
            return;
        end
        if ~isfinite(cfg.baselineEndSec) || cfg.baselineEndSec <= cfg.baselineStartSec
            uiwait(errordlg('Baseline END must be larger than START.','Segmentation','modal'));
            return;
        end
        if ~isfinite(cfg.minVoxels) || cfg.minVoxels < 1
            uiwait(errordlg('Minimum voxels per region must be >= 1.','Segmentation','modal'));
            return;
        end

        if strcmpi(cfg.atlasMode,'active_atlas') && ~hasAtlasField
            choice = questdlg('No obvious active atlas label field was detected. Continue anyway?', ...
                'Segmentation','Continue','Cancel','Cancel');
            if isempty(choice) || strcmpi(choice,'Cancel')
                return;
            end
        end

        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(varargin)
        cfg.cancelled = true;
        if ishghandle(dlg)
            delete(dlg);
        end
    end

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel([],[]);
            elseif strcmpi(ev.Key,'return')
                onRun([],[]);
            end
        catch
        end
    end

    function s = shortTxt(s,n)
        if nargin < 2, n = 40; end
        s = char(s);
        if numel(s) > n
            s = [s(1:max(1,n-3)) '...'];
        end
    end
end

%% ========================================================================
% Functional source loading
%% ========================================================================
function [D,info] = loadSegmentationFunctionalSource(cfg, studio, data, logFcn)

D = [];
info = struct();
info.type = cfg.sourceMode;
info.file = '';
info.isRegistered = false;
info.isStatic3D = false;

switch lower(cfg.sourceMode)
    case 'active_i'
        if ~isfield(data,'I') || isempty(data.I)
            error('Active data.I is missing.');
        end
        D = data.I;
        info.type = 'active_I';
        logMsg(logFcn,'Segmentation source: active data.I');

    case 'active_psc'
        if ~isfield(data,'PSC') || isempty(data.PSC)
            error('Active data.PSC is missing.');
        end
        D = data.PSC;
        info.type = 'active_PSC';
        logMsg(logFcn,'Segmentation source: active data.PSC');

    case 'registered_file'
        f = cfg.sourceFile;
        if isempty(f) || exist(f,'file') ~= 2
            regDir = getRegistrationDir(studio, getStructString(studio,'exportPath',pwd));
            [ff,pp] = uigetfileStart({'*.mat','Registered functional MAT (*.mat)'}, ...
                'Load registered functional MAT', regDir);
            if isequal(ff,0)
                return;
            end
            f = fullfile(pp,ff);
        end
        [D,info] = loadRegisteredSegmentationFile(f);
        info.type = 'registered_file';
        info.file = f;
        info.isRegistered = true;
        logMsg(logFcn,['Segmentation source: registered file -> ' f]);

    otherwise
        error('Unknown segmentation source mode: %s', cfg.sourceMode);
end

if ~isempty(D) && ndims(D) == 3 && isfield(info,'isRegistered') && info.isRegistered
    info.isStatic3D = false;
end
end

function [D,info] = loadRegisteredSegmentationFile(fullFile)
D = [];
info = struct();
info.file = fullFile;
info.isRegistered = true;
info.isStatic3D = false;

S = load(fullFile);

if isfield(S,'registered') && isstruct(S.registered) && isfield(S.registered,'Data')
    D = S.registered.Data;
    info.field = 'registered.Data';
elseif isfield(S,'registered') && isstruct(S.registered) && isfield(S.registered,'I')
    D = S.registered.I;
    info.field = 'registered.I';
elseif isfield(S,'newData') && isstruct(S.newData) && isfield(S.newData,'I')
    D = S.newData.I;
    info.field = 'newData.I';
elseif isfield(S,'Data')
    D = S.Data;
    info.field = 'Data';
elseif isfield(S,'I')
    D = S.I;
    info.field = 'I';
else
    fns = fieldnames(S);
    for k = 1:numel(fns)
        x = S.(fns{k});
        if isnumeric(x) && ndims(x) >= 3 && numel(x) > 1000
            D = x;
            info.field = fns{k};
            break;
        elseif isstruct(x) && isfield(x,'Data') && isnumeric(x.Data)
            D = x.Data;
            info.field = [fns{k} '.Data'];
            break;
        elseif isstruct(x) && isfield(x,'I') && isnumeric(x.I)
            D = x.I;
            info.field = [fns{k} '.I'];
            break;
        end
    end
end

if isempty(D)
    error('Selected MAT file does not contain registered.Data, newData.I, Data, I, or another usable numeric volume.');
end

if ndims(D) == 3
    info.isStatic3D = false;
end
end

function D4 = force4DForSegmentation(D, info)
D = squeeze(D);
if ndims(D) == 2
    D4 = reshape(D, size(D,1), size(D,2), 1, 1);
elseif ndims(D) == 3
    if isfield(info,'isStatic3D') && info.isStatic3D
        D4 = reshape(D, size(D,1), size(D,2), size(D,3), 1);
    else
        D4 = reshape(D, size(D,1), size(D,2), 1, size(D,3));
    end
elseif ndims(D) == 4
    D4 = D;
else
    error('Segmentation functional source must be 2D, 3D, or 4D numeric data.');
end
end

%% ========================================================================
% Label map loading
%% ========================================================================
function [R,info] = loadSegmentationLabelMap(cfg, studio, data, Y, X, Z, logFcn)

R = [];
info = struct();
info.type = cfg.atlasMode;
info.file = '';
info.atlasInfoRegions = [];
info.hasSignedHemisphereLabels = false;

switch lower(cfg.atlasMode)
    case 'manual_label'
        f = cfg.labelFile;
        if isempty(f) || exist(f,'file') ~= 2
            reg2DDir = getRegistration2DDir(studio, getStructString(studio,'exportPath',pwd));
            [ff,pp] = uigetfileStart({'*.mat;*.nii;*.nii.gz;*.tif;*.tiff','Atlas label files (*.mat,*.nii,*.nii.gz,*.tif)'}, ...
                'Load atlas INTEGER label map from Registration2D', reg2DDir);
            if isequal(ff,0)
                return;
            end
            f = fullfile(pp,ff);
        end
        [R,info] = loadLabelMapFile(f);
        info.type = 'manual_label';
        info.file = f;
        logMsg(logFcn,['Atlas label source: manual file -> ' f]);

    case 'allen_3d'
        atlas = loadAllenAtlasLocal();
        R = round(double(atlas.Regions));
        info.type = 'allen_3d';
        if isfield(atlas,'infoRegions')
            info.atlasInfoRegions = atlas.infoRegions;
        end
        logMsg(logFcn,'Atlas label source: Allen atlas.Regions');

    case 'active_atlas'
        [R,info] = pickAtlasFromData(data);
        info.type = 'active_atlas';
        logMsg(logFcn,'Atlas label source: active data atlas/labels field');

    otherwise
        error('Unsupported atlas label mode: %s', cfg.atlasMode);
end

if isempty(R)
    error('No atlas label map could be loaded.');
end

R = squeeze(R);
if ndims(R) == 2
    R = reshape(R, size(R,1), size(R,2), 1);
elseif ndims(R) > 3
    R = squeezeTo3DLabels(R);
end

if ~isequal(size(R), [Y X Z])
    R = resizeLabelVolumeNearest(R, Y, X, Z);
end

info.hasSignedHemisphereLabels = any(R(:) < 0);
end

function [R,info] = loadLabelMapFile(fullFile)

R = [];
info = struct();
info.file = fullFile;
info.atlasInfoRegions = [];
info.hasSignedHemisphereLabels = false;
info.field = '';

if ~exist(fullFile,'file')
    error('Label file does not exist: %s', fullFile);
end

if isNiiGzFile(fullFile)
    tmpDir = tempname;
    mkdir(tmpDir);
    cleanupObj = onCleanup(@() cleanupTmpDir(tmpDir)); %#ok<NASGU>
    gunzip(fullFile,tmpDir);
    d = dir(fullfile(tmpDir,'*.nii'));
    if isempty(d), error('Could not unzip NIfTI label file.'); end
    R = double(niftiread(fullfile(tmpDir,d(1).name)));
    info.field = 'nifti';
    return;
end

[~,~,ext] = fileparts(fullFile);
ext = lower(ext);

if strcmpi(ext,'.nii')
    R = double(niftiread(fullFile));
    info.field = 'nifti';
    return;
end

if strcmpi(ext,'.tif') || strcmpi(ext,'.tiff')
    R = double(imread(fullFile));
    info.field = 'tiff';
    return;
end

if strcmpi(ext,'.mat')
    S = load(fullFile);

    if isfield(S,'atlasInfoRegions')
        info.atlasInfoRegions = S.atlasInfoRegions;
    elseif isfield(S,'atlas') && isstruct(S.atlas) && isfield(S.atlas,'infoRegions')
        info.atlasInfoRegions = S.atlas.infoRegions;
    end

    preferred = { ...
        'atlasRegionLabelsLR2D', ...
        'atlasRegionLabels2D', ...
        'regionLabelsLR', ...
        'regionLabels', ...
        'labelMap', ...
        'labels', ...
        'annotation', ...
        'roiAtlas', ...
        'regions', ...
        'Regions', ...
        'registeredLabels', ...
        'warpedLabels', ...
        'atlasLabels', ...
        'atlasUnderlay'};

    [ok,R,field] = findPreferredLabelField(S, preferred);
    if ok
        info.field = field;
        return;
    end

    % Check Reg2D package. regionsImage is actual atlas.Regions slice.
    if isfield(S,'Reg2D') && isstruct(S.Reg2D)
        if isfield(S.Reg2D,'regionsImage') && ~isempty(S.Reg2D.regionsImage)
            R = makeSignedHemisphereLabels2DLocal(S.Reg2D.regionsImage);
            info.field = 'Reg2D.regionsImage';
            return;
        elseif isfield(S.Reg2D,'atlasSliceIndex')
            atlas = loadAllenAtlasLocal();
            L = squeeze(atlas.Regions(S.Reg2D.atlasSliceIndex,:,:));
            R = makeSignedHemisphereLabels2DLocal(L);
            info.field = 'atlas.Regions(Reg2D.atlasSliceIndex,:,:)';
            if isfield(atlas,'infoRegions')
                info.atlasInfoRegions = atlas.infoRegions;
            end
            return;
        end
    end

    error(['No usable integer atlas label map found in selected MAT file. ' ...
           'For segmentation, choose AtlasUnderlay_regions_*.mat or a file containing atlasRegionLabelsLR2D / atlasRegionLabels2D / labels. ' ...
           'Do not choose histology or vascular underlay files.']);
end

error('Unsupported label file extension: %s', ext);
end

function [ok,R,fieldName] = findPreferredLabelField(S, preferred)
ok = false;
R = [];
fieldName = '';
for ii = 1:numel(preferred)
    fn = preferred{ii};
    if isfield(S,fn)
        V = S.(fn);
        if isnumeric(V) || islogical(V)
            if looksLikeLabelMap(V)
                R = V;
                fieldName = fn;
                ok = true;
                return;
            end
        elseif isstruct(V)
            [ok2,R2,field2] = findPreferredLabelField(V, preferred);
            if ok2
                R = R2;
                fieldName = [fn '.' field2];
                ok = true;
                return;
            end
        end
    end
end

% fallback any likely label map, but avoid RGB/images.
fns = fieldnames(S);
for ii = 1:numel(fns)
    fn = fns{ii};
    V = S.(fn);
    if isnumeric(V) || islogical(V)
        if looksLikeLabelMap(V)
            R = V;
            fieldName = fn;
            ok = true;
            return;
        end
    end
end
end

function tf = looksLikeLabelMap(A)
tf = false;
try
    A = squeeze(double(A));
    if isempty(A) || isvector(A) || ndims(A) > 3
        return;
    end
    if ndims(A) == 3 && size(A,3) == 3
        % RGB image is not a label map unless it has very few labels.
        return;
    end
    if numel(A) < 100
        return;
    end
    vals = A(isfinite(A));
    if isempty(vals)
        return;
    end
    if numel(vals) > 100000
        idx = round(linspace(1,numel(vals),100000));
        vals = vals(idx);
    end
    fracInt = mean(abs(vals - round(vals)) < 1e-6);
    if fracInt < 0.98
        return;
    end
    U = unique(round(vals(:)));
    U = U(U ~= 0);
    if numel(U) < 2
        return;
    end
    if numel(U) > 5000
        return;
    end
    tf = true;
catch
    tf = false;
end
end

function [R,info] = pickAtlasFromData(data)
R = [];
info = struct();
info.atlasInfoRegions = [];
info.field = '';

preferred = {'roiAtlas','atlas','labels','labelMap','regions','Regions','annotation'};
for ii = 1:numel(preferred)
    fn = preferred{ii};
    if isfield(data,fn) && looksLikeLabelMap(data.(fn))
        R = data.(fn);
        info.field = fn;
        return;
    end
end
error('Active dataset does not contain a usable atlas/labels field.');
end

function tf = dataHasAtlasField(data)
tf = false;
try
    preferred = {'roiAtlas','atlas','labels','labelMap','regions','Regions','annotation'};
    for ii = 1:numel(preferred)
        fn = preferred{ii};
        if isfield(data,fn) && looksLikeLabelMap(data.(fn))
            tf = true;
            return;
        end
    end
catch
    tf = false;
end
end

%% ========================================================================
% Step-motor Reg2D handling
%% ========================================================================
function [Dout, Rout, info] = buildStepMotorReg2DSegmentationInput(Din, cfg, studio, logFcn)

D4src = force4DForSegmentation(Din, struct('isStatic3D',false));
[Y0,X0,Z0,T] = size(D4src); %#ok<ASGLU>

files = cfg.reg2DFiles;
if isempty(files)
    reg2DDir = getRegistration2DDir(studio, getStructString(studio,'exportPath',pwd));
    files = autoFindReg2DFiles(reg2DDir);
    files = sortReg2DFiles(files);
end

if isempty(files)
    reg2DDir = getRegistration2DDir(studio, getStructString(studio,'exportPath',pwd));
    [f,p] = uigetfileStart({'*.mat','Reg2D MAT files (*.mat)'}, ...
        'Select one or multiple Reg2D files', reg2DDir, 'MultiSelect','on');
    if isequal(f,0)
        Dout = [];
        Rout = [];
        info = struct();
        return;
    end
    if ischar(f)
        files = {fullfile(p,f)};
    else
        files = cell(size(f));
        for ii = 1:numel(f)
            files{ii} = fullfile(p,f{ii});
        end
    end
    files = sortReg2DFiles(files);
end

logMsg(logFcn,sprintf('Step-motor Reg2D segmentation: %d Reg2D files selected/found.', numel(files)));

warpedCells = {};
labelCells = {};
sourceUsed = [];
fileUsed = {};
infoRegions = [];

for ii = 1:numel(files)
    f = files{ii};
    try
        S = load(f);
        Reg2D = [];
        if isfield(S,'Reg2D') && isstruct(S.Reg2D)
            Reg2D = S.Reg2D;
        elseif isfield(S,'StepMotorReg2D') && isstruct(S.StepMotorReg2D) && isfield(S.StepMotorReg2D,'Reg2DList')
            % Expand bundle by processing list entries.
            list = S.StepMotorReg2D.Reg2DList;
            for kk = 1:numel(list)
                tmpFile = sprintf('%s::Reg2DList{%d}', f, kk);
                [Dtmp,Rtmp,okTmp,srcIdxTmp,infRegTmp] = processOneReg2D(list{kk}, D4src, []);
                if okTmp
                    warpedCells{end+1} = Dtmp; %#ok<AGROW>
                    labelCells{end+1} = Rtmp; %#ok<AGROW>
                    sourceUsed(end+1) = srcIdxTmp; %#ok<AGROW>
                    fileUsed{end+1} = tmpFile; %#ok<AGROW>
                    if isempty(infoRegions) && ~isempty(infRegTmp), infoRegions = infRegTmp; end
                end
            end
            continue;
        else
            % A regions underlay file may contain Reg2D and labels, but if no Reg2D it cannot warp source.
            continue;
        end

        [Dtmp,Rtmp,okTmp,srcIdxTmp,infRegTmp] = processOneReg2D(Reg2D, D4src, S);
        if okTmp
            warpedCells{end+1} = Dtmp; %#ok<AGROW>
            labelCells{end+1} = Rtmp; %#ok<AGROW>
            sourceUsed(end+1) = srcIdxTmp; %#ok<AGROW>
            fileUsed{end+1} = f; %#ok<AGROW>
            if isempty(infoRegions) && ~isempty(infRegTmp), infoRegions = infRegTmp; end
        end
    catch ME
        logMsg(logFcn,['  skipped Reg2D file: ' localFileName(f) ' | ' ME.message]);
    end
end

if isempty(warpedCells)
    error(['No usable Reg2D files could be applied. Make sure Registration2D contains ' ...
           'CoronalRegistration2D_sourceXXX_atlasYYY_*.mat files with Reg2D.A and Reg2D.outputSize.']);
end

% Sort by source slice index.
[~,ord] = sort(sourceUsed);
warpedCells = warpedCells(ord);
labelCells = labelCells(ord);
sourceUsed = sourceUsed(ord);
fileUsed = fileUsed(ord);

Y = size(warpedCells{1},1);
X = size(warpedCells{1},2);
Z = numel(warpedCells);
Dout = zeros(Y,X,Z,T,'single');
Rout = zeros(Y,X,Z,'double');

for zz = 1:Z
    Dout(:,:,zz,:) = reshape(warpedCells{zz}, Y, X, 1, T);
    Rz = labelCells{zz};
    if ~isequal(size(Rz), [Y X])
        Rz = resizeLabelVolumeNearest(reshape(Rz,size(Rz,1),size(Rz,2),1),Y,X,1);
        Rz = Rz(:,:,1);
    end
    Rout(:,:,zz) = Rz;
end

info = struct();
info.type = 'step_reg2d';
info.files = fileUsed;
info.sourceSliceIndex = sourceUsed;
info.atlasInfoRegions = infoRegions;
info.hasSignedHemisphereLabels = any(Rout(:) < 0);
info.note = 'Functional source slices were warped into 2D atlas slice space using Reg2D.A before region extraction.';

logMsg(logFcn,sprintf('Step-motor atlas-space stack built: %d x %d x %d x %d', Y, X, Z, T));

end

function [Dwarp,Rlabel,ok,sourceIdx,atlasInfoRegions] = processOneReg2D(Reg2D, D4src, S)
Dwarp = [];
Rlabel = [];
ok = false;
atlasInfoRegions = [];

if nargin < 3
    S = [];
end

if ~isfield(Reg2D,'A') || ~isfield(Reg2D,'outputSize')
    error('Reg2D lacks A or outputSize.');
end

sourceIdx = 1;
if isfield(Reg2D,'sourceSliceIndex') && ~isempty(Reg2D.sourceSliceIndex)
    sourceIdx = round(double(Reg2D.sourceSliceIndex));
end
sourceIdx = max(1,sourceIdx);

Z0 = size(D4src,3);
T = size(D4src,4);
if sourceIdx > Z0
    error('Reg2D source index %d exceeds source data slices %d.', sourceIdx, Z0);
end

srcStack = squeeze(D4src(:,:,sourceIdx,:));
if T == 1
    srcStack = reshape(srcStack,size(D4src,1),size(D4src,2),1);
end

[Dwarp,~] = applyReg2DToStackLocal(srcStack, Reg2D);

% Prefer labels saved in a regions underlay file.
if ~isempty(S)
    if isfield(S,'atlasRegionLabelsLR2D') && ~isempty(S.atlasRegionLabelsLR2D)
        Rlabel = round(double(S.atlasRegionLabelsLR2D));
    elseif isfield(S,'atlasRegionLabels2D') && ~isempty(S.atlasRegionLabels2D)
        Rlabel = makeSignedHemisphereLabels2DLocal(S.atlasRegionLabels2D);
    elseif isfield(S,'regionsImage') && ~isempty(S.regionsImage)
        Rlabel = makeSignedHemisphereLabels2DLocal(S.regionsImage);
    end

    if isfield(S,'atlasInfoRegions')
        atlasInfoRegions = S.atlasInfoRegions;
    end
end

if isempty(Rlabel)
    if isfield(Reg2D,'regionsImage') && ~isempty(Reg2D.regionsImage)
        Rlabel = makeSignedHemisphereLabels2DLocal(Reg2D.regionsImage);
    elseif isfield(Reg2D,'atlasSliceIndex')
        atlas = loadAllenAtlasLocal();
        atlasSliceIndex = max(1,min(size(atlas.Regions,1),round(Reg2D.atlasSliceIndex)));
        L = squeeze(atlas.Regions(atlasSliceIndex,:,:));
        Rlabel = makeSignedHemisphereLabels2DLocal(L);
        if isfield(atlas,'infoRegions')
            atlasInfoRegions = atlas.infoRegions;
        end
    else
        error('Could not derive labels from Reg2D.');
    end
end

Rlabel = round(double(squeeze(Rlabel)));
if ndims(Rlabel) ~= 2
    error('Reg2D labels are not 2D.');
end

% Fit labels to warped output size.
Y = size(Dwarp,1);
X = size(Dwarp,2);
if ~isequal(size(Rlabel), [Y X])
    Rtmp = resizeLabelVolumeNearest(reshape(Rlabel,size(Rlabel,1),size(Rlabel,2),1),Y,X,1);
    Rlabel = Rtmp(:,:,1);
end

ok = true;
end

function [J,coverageMask] = applyReg2DToStackLocal(I, Reg2D)
if ~(ndims(I)==2 || ndims(I)==3)
    error('applyReg2DToStackLocal: I must be 2D or 3D [Y X T].');
end
if ~isfield(Reg2D,'A') || ~isfield(Reg2D,'outputSize')
    error('Reg2D must contain A and outputSize.');
end

I = single(I);
I(~isfinite(I)) = 0;
tform = affine2d(Reg2D.A);
ref2d = imref2d(Reg2D.outputSize);

if ndims(I) == 2
    J = imwarp(I, tform, 'OutputView', ref2d);
    coverageMask = imwarp(single(ones(size(I,1),size(I,2))), tform, 'OutputView', ref2d) > 0.5;
    return;
end

nT = size(I,3);
J = zeros(Reg2D.outputSize(1), Reg2D.outputSize(2), nT, 'single');
for t = 1:nT
    J(:,:,t) = imwarp(I(:,:,t), tform, 'OutputView', ref2d);
end
coverageMask = imwarp(single(ones(size(I,1),size(I,2))), tform, 'OutputView', ref2d) > 0.5;
end

function files = autoFindReg2DFiles(reg2DDir)
files = {};
if isempty(reg2DDir) || exist(reg2DDir,'dir') ~= 7
    return;
end
allFiles = recursiveDirMat(reg2DDir);
for ii = 1:numel(allFiles)
    f = allFiles{ii};
    nm = lower(localFileName(f));
    if ~isempty(strfind(nm,'coronalregistration2d')) && isempty(strfind(nm,'stepmotor_reg2d_session'))
        files{end+1} = f; %#ok<AGROW>
    end
end
files = sortReg2DFiles(files);
end

function out = recursiveDirMat(rootDir)
out = {};
d = dir(rootDir);
for ii = 1:numel(d)
    nm = d(ii).name;
    if strcmp(nm,'.') || strcmp(nm,'..')
        continue;
    end
    fp = fullfile(rootDir,nm);
    if d(ii).isdir
        sub = recursiveDirMat(fp);
        out = [out sub]; %#ok<AGROW>
    else
        [~,~,ext] = fileparts(nm);
        if strcmpi(ext,'.mat')
            out{end+1} = fp; %#ok<AGROW>
        end
    end
end
end

function filesOut = sortReg2DFiles(filesIn)
filesOut = filesIn;
if isempty(filesIn)
    return;
end
idx = nan(numel(filesIn),1);
for ii = 1:numel(filesIn)
    idx(ii) = parseSourceIndex(filesIn{ii});
    if ~isfinite(idx(ii))
        idx(ii) = ii + 1e6;
    end
end
[~,ord] = sort(idx);
filesOut = filesIn(ord);
end

function idx = parseSourceIndex(s)
idx = NaN;
s = lower(char(s));
tok = regexp(s,'source[_\-\s]*0*([0-9]+)','tokens','once');
if isempty(tok)
    tok = regexp(s,'slice[_\-\s]*0*([0-9]+)','tokens','once');
end
if ~isempty(tok)
    idx = str2double(tok{1});
end
end

function labelsLR = makeSignedHemisphereLabels2DLocal(labels2D)
labelsLR = round(double(labels2D));
labelsLR(~isfinite(labelsLR)) = 0;
nCols = size(labelsLR,2);
midCol = round(nCols/2);
labelsLR(:,1:midCol) = -abs(labelsLR(:,1:midCol));
if midCol < nCols
    labelsLR(:,midCol+1:end) = abs(labelsLR(:,midCol+1:end));
end
end

%% ========================================================================
% Region extraction
%% ========================================================================
function [LeftRaw, RightRaw, BothRaw, region] = extractRegionTimecourses(D, R, validDataMask, labelInfo, minVoxels, logFcn)

[Y,X,Z,T] = size(D);
R = round(double(R));
R(~isfinite(R)) = 0;

ids = unique(abs(R(:)));
ids = ids(isfinite(ids));
ids = ids(ids > 0);
ids = ids(:)';

nReg = numel(ids);
LeftRaw = nan(nReg,T);
RightRaw = nan(nReg,T);
BothRaw = nan(nReg,T);

D2 = reshape(D, [], T);
Rvec = R(:);
valid = validDataMask(:) & isfinite(Rvec) & (abs(Rvec) > 0);

hasSigned = any(Rvec < 0);

% If labels are unsigned, keep bilateral output correct. Left/right is only
% approximate. For Allen 3D atlas in whole-brain fUS, LR is usually dim 3.
leftVec = false(numel(Rvec),1);
rightVec = false(numel(Rvec),1);
hemiNote = '';
if hasSigned
    hemiNote = 'Left/right from signed 2D labels: negative=left, positive=right.';
else
    if Z > 1
        mid = round(Z/2);
        leftMask = false(Y,X,Z);
        rightMask = false(Y,X,Z);
        leftMask(:,:,1:mid) = true;
        if mid < Z, rightMask(:,:,mid+1:end) = true; end
        leftVec = leftMask(:);
        rightVec = rightMask(:);
        hemiNote = 'Labels are unsigned. Left/right approximated by splitting dimension 3. Bilateral Both is reliable; verify hemisphere orientation.';
    else
        mid = round(X/2);
        leftMask = false(Y,X,Z);
        rightMask = false(Y,X,Z);
        leftMask(:,1:mid,:) = true;
        if mid < X, rightMask(:,mid+1:end,:) = true; end
        leftVec = leftMask(:);
        rightVec = rightMask(:);
        hemiNote = 'Labels are unsigned 2D. Left/right approximated by splitting image columns. Bilateral Both is reliable; verify orientation.';
    end
end

countsLeft = zeros(nReg,1);
countsRight = zeros(nReg,1);
countsBoth = zeros(nReg,1);

for i = 1:nReg
    lab = ids(i);

    idxBoth = valid & (abs(Rvec) == lab);

    if hasSigned
        idxLeft = valid & (Rvec == -abs(lab));
        idxRight = valid & (Rvec == abs(lab));
    else
        idxLeft = idxBoth & leftVec;
        idxRight = idxBoth & rightVec;
    end

    countsBoth(i) = sum(idxBoth);
    countsLeft(i) = sum(idxLeft);
    countsRight(i) = sum(idxRight);

    if countsBoth(i) >= minVoxels
        BothRaw(i,:) = nanmeanLocal(D2(idxBoth,:),1);
    end
    if countsLeft(i) >= minVoxels
        LeftRaw(i,:) = nanmeanLocal(D2(idxLeft,:),1);
    end
    if countsRight(i) >= minVoxels
        RightRaw(i,:) = nanmeanLocal(D2(idxRight,:),1);
    end

    if mod(i,50)==0
        logMsg(logFcn,sprintf('  segmented %d/%d regions...',i,nReg));
    end
end

[acr,names,vols] = atlasRegionNames(labelInfo, ids);

region = struct();
region.labels = ids(:);
region.acronyms = acr(:);
region.names = names(:);
region.volumeAtlas = vols(:);
region.countsLeft = countsLeft;
region.countsRight = countsRight;
region.countsBoth = countsBoth;
region.hemisphereNote = hemiNote;
region.minVoxels = minVoxels;

end

function Mz = zscoreBaselineMatrix(M, baseIdx)
% Robust baseline z-scoring for region x time matrices.
%
% Important fix:
% If the baseline standard deviation is zero/NaN for a region, the old
% implementation made the whole region trace NaN. This broke Functional
% Connectivity because all rows could become NaN even though raw traces were
% present. Here we fall back to the whole-trace SD, and if the whole trace is
% also constant we use SD=1 so the z-trace becomes finite instead of NaN.

Mz = nan(size(M));

if isempty(M)
    return;
end

baseIdx = baseIdx(baseIdx >= 1 & baseIdx <= size(M,2));

if isempty(baseIdx)
    baseIdx = 1:min(size(M,2), max(1,round(size(M,2)/3)));
end

mu = nanmeanLocal(M(:,baseIdx),2);
sd = nanstdLocal(M(:,baseIdx),0,2);

badSd = ~isfinite(sd) | sd < eps;

if any(badSd)
    sdAll = nanstdLocal(M,0,2);
    repl = sdAll;
    repl(~isfinite(repl) | repl < eps) = 1;
    sd(badSd) = repl(badSd);
end

mu(~isfinite(mu)) = 0;
sd(~isfinite(sd) | sd < eps) = 1;

for t = 1:size(M,2)
    Mz(:,t) = (M(:,t) - mu) ./ sd;
end

end

function Dpsc = computePSC4DLocal(D, baseIdx)
baseIdx = baseIdx(baseIdx >= 1 & baseIdx <= size(D,4));
if isempty(baseIdx)
    baseIdx = 1:min(size(D,4), max(1,round(size(D,4)/3)));
end
B = nanmeanLocal(D(:,:,:,baseIdx),4);
B(~isfinite(B) | abs(B) < eps) = NaN;
Dpsc = zeros(size(D));
for t = 1:size(D,4)
    Dpsc(:,:,:,t) = ((D(:,:,:,t) - B) ./ B) .* 100;
end
end

function [baseFrames, bStartFrame, bEndFrame, note] = baselineSecondsToFrames(bStartSec, bEndSec, TR, T)
note = '';
if ~isfinite(TR) || TR <= 0, TR = 1; end
if ~isfinite(bStartSec) || bStartSec < 0, bStartSec = 0; end
if ~isfinite(bEndSec) || bEndSec <= bStartSec, bEndSec = bStartSec + TR; end
bStartFrame = max(1, floor(bStartSec / TR) + 1);
bEndFrame = min(T, max(bStartFrame, round(bEndSec / TR)));
if bStartFrame > T
    bStartFrame = 1;
    bEndFrame = min(T, max(1,round(T/3)));
    note = sprintf('Requested baseline %.3g-%.3g sec is outside data duration. Using frames %d-%d.', bStartSec, bEndSec, bStartFrame, bEndFrame);
elseif bEndFrame < round(bEndSec / TR)
    note = sprintf('Baseline end %.3g sec exceeds data duration. Clamped to frame %d.', bEndSec, bEndFrame);
end
baseFrames = bStartFrame:bEndFrame;
if isempty(baseFrames)
    baseFrames = 1:min(T, max(1,round(T/3)));
    bStartFrame = baseFrames(1);
    bEndFrame = baseFrames(end);
end
end

%% ========================================================================
% Atlas / region-name helpers
%% ========================================================================
function atlas = loadAllenAtlasLocal()
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
    [f,p] = uigetfile({'*.mat','Allen atlas MAT (*.mat)'}, 'Select allen_brain_atlas.mat');
    if isequal(f,0)
        error('No atlas selected.');
    end
    atlasPath = fullfile(p,f);
end
S = load(atlasPath);
if isfield(S,'atlas')
    atlas = S.atlas;
else
    error('Selected atlas MAT does not contain variable atlas.');
end
end

function [acr,names,vols] = atlasRegionNames(labelInfo, labels)
acr = cell(numel(labels),1);
names = cell(numel(labels),1);
vols = nan(numel(labels),1);
for i = 1:numel(labels)
    acr{i} = sprintf('REG%d',labels(i));
    names{i} = sprintf('Region %d',labels(i));
end

info = [];
try
    if isstruct(labelInfo) && isfield(labelInfo,'atlasInfoRegions') && ~isempty(labelInfo.atlasInfoRegions)
        info = labelInfo.atlasInfoRegions;
    end
catch
    info = [];
end
if isempty(info)
    try
        atlas = loadAllenAtlasLocal();
        if isfield(atlas,'infoRegions')
            info = atlas.infoRegions;
        end
    catch
        info = [];
    end
end
if isempty(info)
    return;
end

try
    if isfield(info,'acr')
        acrList = info.acr;
    elseif isfield(info,'acronym')
        acrList = info.acronym;
    else
        acrList = {};
    end
    if isfield(info,'name')
        nameList = info.name;
    else
        nameList = {};
    end
    if isfield(info,'vol')
        volList = info.vol;
    else
        volList = [];
    end
    for i = 1:numel(labels)
        lab = labels(i);
        if lab >= 1 && lab <= numel(acrList)
            acr{i} = char(acrList{lab});
        end
        if lab >= 1 && lab <= numel(nameList)
            names{i} = char(nameList{lab});
        end
        if ~isempty(volList) && lab >= 1 && lab <= numel(volList)
            vols(i) = double(volList(lab));
        end
    end
catch
end
end

function Rout = resizeLabelVolumeNearest(R,Y,X,Z)
R = double(squeeze(R));
if ndims(R) == 2
    R = reshape(R,size(R,1),size(R,2),1);
end
sy = size(R,1);
sx = size(R,2);
sz = size(R,3);
yi = round(linspace(1, sy, Y));
xi = round(linspace(1, sx, X));
zi = round(linspace(1, sz, Z));
yi = max(1,min(sy,yi));
xi = max(1,min(sx,xi));
zi = max(1,min(sz,zi));
Rout = R(yi,xi,zi);
Rout = round(Rout);
end

function R = squeezeTo3DLabels(R)
R = squeeze(R);
while ndims(R) > 3
    R = R(:,:,:,1);
    R = squeeze(R);
end
if ndims(R) == 2
    R = reshape(R,size(R,1),size(R,2),1);
end
end

%% ========================================================================
% Export helpers
%% ========================================================================
function writeRegionTimeCSV(fileName, M, region, timeSec, modeName)
fid = fopen(fileName,'w');
if fid < 0
    error('Could not write CSV: %s',fileName);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'Label,Acronym,Name,Mode');
for t = 1:numel(timeSec)
    fprintf(fid,',t%.6g_sec',timeSec(t));
end
fprintf(fid,'\n');

for i = 1:size(M,1)
    fprintf(fid,'%g,%s,%s,%s', region.labels(i), csvClean(region.acronyms{i}), csvClean(region.names{i}), modeName);
    for t = 1:size(M,2)
        fprintf(fid,',%.9g', M(i,t));
    end
    fprintf(fid,'\n');
end
end

function writeRegionTableCSV(fileName, region)
fid = fopen(fileName,'w');
if fid < 0
    error('Could not write CSV: %s',fileName);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'Label,Acronym,Name,AtlasVolume,CountLeft,CountRight,CountBoth,MinVoxels,HemisphereNote\n');
for i = 1:numel(region.labels)
    fprintf(fid,'%g,%s,%s,%.9g,%d,%d,%d,%d,%s\n', ...
        region.labels(i), csvClean(region.acronyms{i}), csvClean(region.names{i}), ...
        region.volumeAtlas(i), region.countsLeft(i), region.countsRight(i), region.countsBoth(i), ...
        region.minVoxels, csvClean(region.hemisphereNote));
end
end

function makeSegmentationHeatmap(M, region, figFile)
fig = figure('Visible','off','Color','w','Position',[100 100 1200 700]);
imagesc(M);
axis tight;
colormap(jet);
colorbar;
caxis([-6 6]);
xlabel('Time point');
ylabel('Atlas region');
title('Bilateral region x time z-score');
set(gca,'FontName','Arial','FontSize',10);
if size(M,1) <= 80
    set(gca,'YTick',1:size(M,1));
    set(gca,'YTickLabel',region.acronyms);
else
    step = max(1,round(size(M,1)/40));
    yt = 1:step:size(M,1);
    set(gca,'YTick',yt);
    set(gca,'YTickLabel',region.acronyms(yt));
end
try
    print(fig,figFile,'-dpng','-r200');
catch
    saveas(fig,figFile);
end
close(fig);
end

function s = csvClean(s)
if isempty(s), s = ''; end
s = char(s);
s = strrep(s,'"','''');
s = strrep(s,',',';');
s = strrep(s,sprintf('\n'),' ');
s = strrep(s,sprintf('\r'),' ');
end

%% ========================================================================
% Small utilities
%% ========================================================================
function tr = getTRFromData(data)
tr = 1;
try
    if isfield(data,'TR') && ~isempty(data.TR) && isfinite(data.TR) && data.TR > 0
        tr = double(data.TR);
    end
catch
end
end

function s = getStructString(S, fieldName, defaultVal)
s = defaultVal;
try
    if isstruct(S) && isfield(S,fieldName) && ~isempty(S.(fieldName))
        s = S.(fieldName);
    end
catch
end
end

function regDir = getRegistrationDir(studio, saveRoot)
regDir = fullfile(saveRoot,'Registration');
try
    if isfield(studio,'registrationPath') && ~isempty(studio.registrationPath) && exist(studio.registrationPath,'dir')
        regDir = studio.registrationPath;
    elseif exist(regDir,'dir') ~= 7
        mkdir(regDir);
    end
catch
end
end

function reg2DDir = getRegistration2DDir(studio, saveRoot)
reg2DDir = fullfile(saveRoot,'Registration2D');
try
    if isfield(studio,'registration2DPath') && ~isempty(studio.registration2DPath) && exist(studio.registration2DPath,'dir')
        reg2DDir = studio.registration2DPath;
    elseif exist(reg2DDir,'dir') ~= 7
        mkdir(reg2DDir);
    end
catch
end
end

function [f,p] = uigetfileStart(filterSpec, titleStr, startDir, varargin)
if nargin < 3 || isempty(startDir) || exist(startDir,'dir') ~= 7
    startDir = pwd;
end
oldDir = pwd;
cleanupObj = onCleanup(@() cd(oldDir)); %#ok<NASGU>
try, cd(startDir); catch, end
try
    [f,p] = uigetfile(filterSpec, titleStr, startDir, varargin{:});
catch
    [f,p] = uigetfile(filterSpec, titleStr, varargin{:});
end
end

function name = localFileName(f)
[~,nm,ext] = fileparts(f);
if strcmpi(ext,'.gz')
    [~,nm2,ext2] = fileparts(nm);
    name = [nm2 ext2 ext];
else
    name = [nm ext];
end
end

function tf = isNiiGzFile(f)
tf = numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz');
end

function cleanupTmpDir(tmpDir)
try
    if exist(tmpDir,'dir')
        rmdir(tmpDir,'s');
    end
catch
end
end

function logMsg(logFcn,msg)
try
    logFcn(msg);
catch
    fprintf('%s\n',msg);
end
end

function y = nanmeanLocal(x,dim)
if nargin < 2, dim = 1; end
mask = isfinite(x);
x(~mask) = 0;
n = sum(mask,dim);
y = sum(x,dim) ./ max(n,1);
y(n==0) = NaN;
end

function y = nanstdLocal(x,flag,dim)
if nargin < 2 || isempty(flag), flag = 0; end
if nargin < 3, dim = 1; end
mu = nanmeanLocal(x,dim);
rep = ones(1,ndims(x));
rep(dim) = size(x,dim);
muFull = repmat(mu,rep);
mask = isfinite(x);
d = x - muFull;
d(~mask) = 0;
n = sum(mask,dim);
if flag == 0
    denom = max(n-1,1);
else
    denom = max(n,1);
end
y = sqrt(sum(d.^2,dim) ./ denom);
y(n==0) = NaN;
end
