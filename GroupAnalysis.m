function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m  (MATLAB 2017b compatible)
% =========================================================
% fUSI Studio — Group-Level Analysis GUI (PACAP-style ROI plots)
%
% FIXED / IMPROVED (based on your issues):
%  1) ROI .txt exported from SCM_gui (with # headers + columns time_sec time_min PSC)
%     is parsed directly (NO need for DATA .mat in that case).
%  2) Prevents "double PSC": if ROI txt already contains PSC, it will NEVER
%     compute %SC again (even if checkbox is ON).
%  3) Peak metric is now transparent + configurable:
%       - choose Peak search window [min]
%       - choose Peak averaging window [min]
%       - choose Peak method:
%           a) Single-point max
%           b) Window mean
%           c) Window trimmed mean (uses Trim%)
%           d) Window median
%       -> Peak value + Peak time are stored + exported
%  4) NEW lower plot option:
%       - "Metric scatter" (old style)
%       - "Peak window view" (visualize the detected peak window on group mean
%         inside the selected search interval, with markers + text)
%
% Subject table columns:
%   Subject | Group | Condition | PairID | DataFile | ROIFile
%
% ROI Timecourse mode needs per row:
%   - ROIFile (.txt) from SCM_gui OR coordinate txt
%   - DataFile only required if ROIFile is coordinate txt (not PSC-table txt)
%
% Calling styles:
%   GroupAnalysis('studio',studio,'logFcn',@(...),'statusFcn',@(...),'startDir',...,'onClose',...)
%   GroupAnalysis(studio, onClose, 'logFcn',..., 'statusFcn',..., 'startDir',...)
% =========================================================

% -------------------- Pre-parse positional args -----------------------
posStudio = [];
posOnClose = [];
args = varargin;

if ~isempty(args) && isstruct(args{1}) && ~ischar(args{1}) && ~isstring(args{1})
    posStudio = args{1};
    args = args(2:end);
end
if ~isempty(args) && isa(args{1},'function_handle')
    posOnClose = args{1};
    args = args(2:end);
end

% -------------------- Parse inputs -----------------------
P = inputParser;
P.addParameter('studio', struct(), @(x) isstruct(x));
P.addParameter('logFcn', [], @(x) isempty(x) || isa(x,'function_handle'));
P.addParameter('statusFcn', [], @(x) isempty(x) || isa(x,'function_handle'));
P.addParameter('startDir', '', @(x) ischar(x) || isstring(x));
P.addParameter('onClose', [], @(x) isempty(x) || isa(x,'function_handle'));
P.parse(args{:});
opt = P.Results;

if ~isempty(posStudio),  opt.studio = posStudio; end
if ~isempty(posOnClose), opt.onClose = posOnClose; end

if isempty(opt.startDir), opt.startDir = pwd; end
if isfield(opt.studio,'exportPath') && ~isempty(opt.studio.exportPath) && exist(opt.studio.exportPath,'dir')
    opt.startDir = opt.studio.exportPath;
end

% -------------------- Theme ------------------------------
C.bg     = [0.06 0.06 0.06];
C.panel  = [0.10 0.10 0.10];
C.panel2 = [0.08 0.08 0.08];
C.txt    = [0.95 0.95 0.95];
C.muted  = [0.65 0.75 0.85];
C.accent = [0.25 0.70 0.55];
C.warn   = [0.90 0.35 0.25];
C.btn    = [0.18 0.18 0.18];

% PACAP-style default colors
C.pacapLine   = [0.20 0.65 0.90];
C.pacapFill   = [0.20 0.65 0.90];
C.vehicleLine = [0.00 0.00 0.00];
C.vehicleFill = [0.60 0.60 0.60];

% -------------------- Figure -----------------------------
hFig = figure('Name','fUSI Studio — Group Analysis', ...
    'Color',C.bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[150 80 1750 930], ...
    'CloseRequestFcn', @closeMe);

% -------------------- State ------------------------------
S = struct();
S.opt = opt;
S.C = C;

S.subj = cell(0,6);    % Subject | Group | Condition | PairID | DataFile | ROIFile
S.selectedRows = [];
S.isClosing = false;

S.last = struct();
S.mode = 'PSC Map';

% PSC map defaults (sec)
S.baseStart = 0;  S.baseEnd = 10;
S.sigStart  = 10; S.sigEnd  = 30;

% ROI defaults (minutes)
S.tc_computePSC = false;     % IMPORTANT default OFF (because SCM txt often already PSC)
S.tc_baseMin0   = 0;  S.tc_baseMin1 = 10;

S.tc_injMin0    = 10; S.tc_injMin1  = 20;      % shading only
S.tc_plateauMin0 = 30; S.tc_plateauMin1 = 40;

S.tc_peakSearchMin0 = 10; S.tc_peakSearchMin1 = 20; % you can change
S.tc_peakWinMin = 3;
S.tc_trimPct    = 10;

S.tc_peakMethod = 'Window trimmed mean';  % Single-point max | Window mean | Window trimmed mean | Window median
S.tc_metric     = 'Robust Peak';          % Plateau | Robust Peak
S.tc_lowerPlot  = 'Metric scatter';       % Metric scatter | Peak window view

% Stats defaults
S.testType = 'None';
S.alpha = 0.05;
S.mcc = 'None';

% Output folder default
S.outDir = defaultOutDir(opt);

% -------------------- Layout panels ----------------------
leftW = 0.44;
pLeft = uipanel(hFig,'Units','normalized','Position',[0.02 0.05 leftW 0.93], ...
    'Title','Subjects / Groups', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold');

pRight = uipanel(hFig,'Units','normalized','Position',[0.02+leftW+0.02 0.05 0.96-(0.02+leftW+0.02) 0.93], ...
    'Title','Analysis + Preview', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold');

% -------------------- Subject table -----------------------
colNames = {'Subject','Group','Condition','PairID','DataFile','ROIFile'};
colEdit  = [true true true true false false];

S.hTable = uitable(pLeft, ...
    'Units','normalized', ...
    'Position',[0.03 0.32 0.94 0.65], ...
    'Data',S.subj, ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'RowName',[], ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',C.muted, ...
    'FontName','Courier New', ...
    'FontSize',11, ...
    'CellSelectionCallback', @onCellSelect);

S.hAddFiles = uicontrol(pLeft,'Style','pushbutton','String','Add Files (DATA/ROI)', ...
    'Units','normalized','Position',[0.03 0.25 0.30 0.06], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onAddFiles);

S.hAddFolder = uicontrol(pLeft,'Style','pushbutton','String','Add Folder (scan)', ...
    'Units','normalized','Position',[0.35 0.25 0.30 0.06], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onAddFolder);

S.hRemove = uicontrol(pLeft,'Style','pushbutton','String','Remove Selected', ...
    'Units','normalized','Position',[0.67 0.25 0.30 0.06], ...
    'BackgroundColor',C.warn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onRemoveSelected);

S.hSetData = uicontrol(pLeft,'Style','pushbutton','String','Set DATA for selected', ...
    'Units','normalized','Position',[0.03 0.19 0.46 0.055], ...
    'BackgroundColor',[0.25 0.55 0.95],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onSetDataSelected);

S.hSetROI = uicontrol(pLeft,'Style','pushbutton','String','Set ROI for selected', ...
    'Units','normalized','Position',[0.51 0.19 0.46 0.055], ...
    'BackgroundColor',[0.75 0.35 0.80],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onSetROISelected);

S.hSaveList = uicontrol(pLeft,'Style','pushbutton','String','Save Subject List', ...
    'Units','normalized','Position',[0.03 0.13 0.46 0.055], ...
    'BackgroundColor',[0.20 0.55 0.95],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onSaveList);

S.hLoadList = uicontrol(pLeft,'Style','pushbutton','String','Load Subject List', ...
    'Units','normalized','Position',[0.51 0.13 0.46 0.055], ...
    'BackgroundColor',[0.15 0.65 0.55],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onLoadList);

uicontrol(pLeft,'Style','text','String','Output folder:', ...
    'Units','normalized','Position',[0.03 0.075 0.25 0.04], ...
    'BackgroundColor',C.panel,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.28 0.075 0.54 0.045], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',11, ...
    'Callback',@onOutEdit);

S.hOutBrowse = uicontrol(pLeft,'Style','pushbutton','String','Browse', ...
    'Units','normalized','Position',[0.84 0.075 0.13 0.045], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onBrowseOut);

S.hHint = uicontrol(pLeft,'Style','text', ...
    'String',['Tip: ROI txt from SCM_gui already contains PSC. DATA .mat is only needed if ROI txt is coordinates.'], ...
    'Units','normalized','Position',[0.03 0.015 0.94 0.05], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------- Right panel: options ----------------
uicontrol(pRight,'Style','text','String','Mode:', ...
    'Units','normalized','Position',[0.03 0.93 0.10 0.04], ...
    'BackgroundColor',C.panel,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',12);

S.hMode = uicontrol(pRight,'Style','popupmenu', ...
    'String',{'PSC Map','ROI Timecourse'}, ...
    'Units','normalized','Position',[0.13 0.93 0.22 0.05], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'FontSize',12,'Callback',@onModeChanged);

% PSC windows panel
S.pPSC = uipanel(pRight,'Units','normalized','Position',[0.03 0.73 0.32 0.18], ...
    'Title','PSC Map: windows (sec)', ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','FontWeight','bold');
makeWinRow(S.pPSC,0.60,'Baseline start',num2str(S.baseStart),@onPSCEdit,'baseStart');
makeWinRow(S.pPSC,0.38,'Baseline end',  num2str(S.baseEnd),  @onPSCEdit,'baseEnd');
makeWinRow(S.pPSC,0.16,'Signal start',  num2str(S.sigStart), @onPSCEdit,'sigStart');
makeWinRow(S.pPSC,0.00,'Signal end',    num2str(S.sigEnd),   @onPSCEdit,'sigEnd');

% Aggregation panel (maps)
S.pAgg = uipanel(pRight,'Units','normalized','Position',[0.03 0.61 0.32 0.10], ...
    'Title','Fixed effect summary (maps)', ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','FontWeight','bold');
uicontrol(S.pAgg,'Style','text','String','Summary:', ...
    'Units','normalized','Position',[0.05 0.20 0.25 0.55], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');
S.hSummary = uicontrol(S.pAgg,'Style','popupmenu', ...
    'String',{'Mean','Median'}, ...
    'Units','normalized','Position',[0.32 0.25 0.63 0.55], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@(~,~)0);

% ROI options panel (UPDATED)
S.pROI = uipanel(pRight,'Units','normalized','Position',[0.03 0.44 0.32 0.28], ...
    'Title','ROI Timecourse: Peak / Plateau settings', ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','FontWeight','bold');

S.hTC_ComputePSC = uicontrol(S.pROI,'Style','checkbox', ...
    'String','Compute %SC from raw using baseline window (ignored if ROI txt already PSC)', ...
    'Units','normalized','Position',[0.05 0.88 0.92 0.10], ...
    'Value', double(S.tc_computePSC), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Baseline
uicontrol(S.pROI,'Style','text','String','Baseline (min):', ...
    'Units','normalized','Position',[0.05 0.78 0.40 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Base0 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_baseMin0), ...
    'Units','normalized','Position',[0.46 0.78 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);
S.hTC_Base1 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_baseMin1), ...
    'Units','normalized','Position',[0.71 0.78 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Infusion shade
uicontrol(S.pROI,'Style','text','String','Infusion shade (min):', ...
    'Units','normalized','Position',[0.05 0.68 0.40 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Inj0 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_injMin0), ...
    'Units','normalized','Position',[0.46 0.68 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);
S.hTC_Inj1 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_injMin1), ...
    'Units','normalized','Position',[0.71 0.68 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Plateau window
uicontrol(S.pROI,'Style','text','String','Plateau (min):', ...
    'Units','normalized','Position',[0.05 0.58 0.40 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Plat0 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_plateauMin0), ...
    'Units','normalized','Position',[0.46 0.58 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);
S.hTC_Plat1 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_plateauMin1), ...
    'Units','normalized','Position',[0.71 0.58 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Peak search window
uicontrol(S.pROI,'Style','text','String','Peak search (min):', ...
    'Units','normalized','Position',[0.05 0.48 0.40 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_PeakS0 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_peakSearchMin0), ...
    'Units','normalized','Position',[0.46 0.48 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);
S.hTC_PeakS1 = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_peakSearchMin1), ...
    'Units','normalized','Position',[0.71 0.48 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Peak averaging window + trim
uicontrol(S.pROI,'Style','text','String','Peak avg win (min):', ...
    'Units','normalized','Position',[0.05 0.38 0.40 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_PeakWin = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_peakWinMin), ...
    'Units','normalized','Position',[0.46 0.38 0.22 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

uicontrol(S.pROI,'Style','text','String','Trim %:', ...
    'Units','normalized','Position',[0.71 0.38 0.12 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Trim = uicontrol(S.pROI,'Style','edit','String',num2str(S.tc_trimPct), ...
    'Units','normalized','Position',[0.83 0.38 0.10 0.09], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Peak method popup
uicontrol(S.pROI,'Style','text','String','Peak method:', ...
    'Units','normalized','Position',[0.05 0.26 0.30 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_PeakMethod = uicontrol(S.pROI,'Style','popupmenu', ...
    'String',{'Single-point max','Window mean','Window trimmed mean','Window median'}, ...
    'Units','normalized','Position',[0.36 0.27 0.57 0.09], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Metric popup (what the scatter uses)
uicontrol(S.pROI,'Style','text','String','Metric:', ...
    'Units','normalized','Position',[0.05 0.14 0.25 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Metric = uicontrol(S.pROI,'Style','popupmenu', ...
    'String',{'Plateau','Robust Peak'}, ...
    'Units','normalized','Position',[0.32 0.15 0.30 0.09], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Lower plot mode
uicontrol(S.pROI,'Style','text','String','Lower plot:', ...
    'Units','normalized','Position',[0.64 0.14 0.25 0.08], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_LowerPlot = uicontrol(S.pROI,'Style','popupmenu', ...
    'String',{'Metric scatter','Peak window view'}, ...
    'Units','normalized','Position',[0.64 0.05 0.29 0.09], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onTCParamsChanged);

% Stats panel
S.pStats = uipanel(pRight,'Units','normalized','Position',[0.03 0.26 0.32 0.16], ...
    'Title','Statistics (metric)', ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','FontWeight','bold');

uicontrol(S.pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.05 0.62 0.20 0.25], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hTest = uicontrol(S.pStats,'Style','popupmenu', ...
    'String',{'None','One-sample (vs 0)','Two-sample (GroupA vs GroupB)','Paired (CondA vs CondB)','One-way ANOVA (groups)'}, ...
    'Units','normalized','Position',[0.27 0.64 0.68 0.25], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onTestChanged);

uicontrol(S.pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.05 0.25 0.20 0.20], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hAlpha = uicontrol(S.pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.27 0.25 0.22 0.22], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onAlphaChanged);

% Run/Export
S.hRun = uicontrol(pRight,'Style','pushbutton','String','RUN ANALYSIS', ...
    'Units','normalized','Position',[0.03 0.18 0.32 0.06], ...
    'BackgroundColor',C.accent,'ForegroundColor','w','FontWeight','bold','FontSize',13, ...
    'Callback',@onRun);

S.hExport = uicontrol(pRight,'Style','pushbutton','String','EXPORT RESULTS', ...
    'Units','normalized','Position',[0.03 0.11 0.32 0.06], ...
    'BackgroundColor',[0.30 0.50 0.95],'ForegroundColor','w','FontWeight','bold','FontSize',13, ...
    'Callback',@onExport);

% Preview axes
S.ax1 = axes('Parent',pRight,'Units','normalized','Position',[0.40 0.53 0.57 0.42], ...
    'Color',[0 0 0], 'XColor','w','YColor','w');
title(S.ax1,'Preview 1','Color','w','FontWeight','bold');

S.ax2 = axes('Parent',pRight,'Units','normalized','Position',[0.40 0.06 0.57 0.42], ...
    'Color',[0 0 0], 'XColor','w','YColor','w');
title(S.ax2,'Preview 2','Color','w','FontWeight','bold');

% Store + initial UI state
guidata(hFig,S);
setStatus(false);
applyModeUI();
syncROIUIfromState();
clearPreview();
logMsg('Group Analysis GUI ready.');

% =========================================================
% Callbacks
% =========================================================
    function closeMe(src,~)
        S = guidata(src);
        if isempty(S), delete(src); return; end
        if isfield(S,'isClosing') && S.isClosing
            delete(src); return;
        end
        S.isClosing = true;
        guidata(src,S);

        try, setStatus(true); catch, end
        try, logMsg('Group Analysis closed.'); catch, end
        if isfield(S.opt,'onClose') && ~isempty(S.opt.onClose)
            try, S.opt.onClose(); catch, end
        end
        delete(src);
    end

    function onCellSelect(~, evt)
        S = guidata(hFig);
        if isempty(evt) || ~isfield(evt,'Indices') || isempty(evt.Indices)
            S.selectedRows = [];
        else
            S.selectedRows = unique(evt.Indices(:,1));
        end
        guidata(hFig,S);
    end

    function onModeChanged(src,~)
        S = guidata(hFig);
        v = get(src,'Value');
        if v == 1, S.mode = 'PSC Map'; else, S.mode = 'ROI Timecourse'; end
        guidata(hFig,S);
        applyModeUI();
        clearPreview();
        logMsg(['Mode set: ' S.mode]);
    end

    function applyModeUI()
        S = guidata(hFig);
        if strcmpi(S.mode,'PSC Map')
            set(S.pPSC,'Visible','on');
            set(S.pAgg,'Visible','on');
            set(S.pROI,'Visible','off');
            set(S.pStats,'Visible','on');
        else
            set(S.pPSC,'Visible','off');
            set(S.pAgg,'Visible','off');
            set(S.pROI,'Visible','on');
            set(S.pStats,'Visible','on');
        end
    end

    function onPSCEdit(src,~,fieldName)
        S = guidata(hFig);
        v = str2double(get(src,'String'));
        if isnan(v), setPSCUI(); return; end
        S.(fieldName) = v;
        guidata(hFig,S);
    end

    function setPSCUI()
        S = guidata(hFig);
        e = findobj(S.pPSC,'Style','edit');
        for k = 1:numel(e)
            tag = get(e(k),'Tag');
            if isfield(S,tag), set(e(k),'String',num2str(S.(tag))); end
        end
    end

    function onTCParamsChanged(~,~)
        S = guidata(hFig);

        S.tc_computePSC = logical(get(S.hTC_ComputePSC,'Value'));
        S.tc_baseMin0   = safeNum(get(S.hTC_Base0,'String'), S.tc_baseMin0);
        S.tc_baseMin1   = safeNum(get(S.hTC_Base1,'String'), S.tc_baseMin1);

        S.tc_injMin0    = safeNum(get(S.hTC_Inj0,'String'), S.tc_injMin0);
        S.tc_injMin1    = safeNum(get(S.hTC_Inj1,'String'), S.tc_injMin1);

        S.tc_plateauMin0 = safeNum(get(S.hTC_Plat0,'String'), S.tc_plateauMin0);
        S.tc_plateauMin1 = safeNum(get(S.hTC_Plat1,'String'), S.tc_plateauMin1);

        S.tc_peakSearchMin0 = safeNum(get(S.hTC_PeakS0,'String'), S.tc_peakSearchMin0);
        S.tc_peakSearchMin1 = safeNum(get(S.hTC_PeakS1,'String'), S.tc_peakSearchMin1);

        S.tc_peakWinMin = safeNum(get(S.hTC_PeakWin,'String'), S.tc_peakWinMin);
        S.tc_trimPct    = safeNum(get(S.hTC_Trim,'String'), S.tc_trimPct);

        % popups
        pm = get(S.hTC_PeakMethod,'String');
        S.tc_peakMethod = pm{get(S.hTC_PeakMethod,'Value')};

        mt = get(S.hTC_Metric,'String');
        S.tc_metric = mt{get(S.hTC_Metric,'Value')};

        lp = get(S.hTC_LowerPlot,'String');
        S.tc_lowerPlot = lp{get(S.hTC_LowerPlot,'Value')};

        guidata(hFig,S);
    end

    function syncROIUIfromState()
        S = guidata(hFig);

        set(S.hTC_ComputePSC,'Value',double(S.tc_computePSC));
        set(S.hTC_Base0,'String',num2str(S.tc_baseMin0));
        set(S.hTC_Base1,'String',num2str(S.tc_baseMin1));
        set(S.hTC_Inj0,'String',num2str(S.tc_injMin0));
        set(S.hTC_Inj1,'String',num2str(S.tc_injMin1));
        set(S.hTC_Plat0,'String',num2str(S.tc_plateauMin0));
        set(S.hTC_Plat1,'String',num2str(S.tc_plateauMin1));
        set(S.hTC_PeakS0,'String',num2str(S.tc_peakSearchMin0));
        set(S.hTC_PeakS1,'String',num2str(S.tc_peakSearchMin1));
        set(S.hTC_PeakWin,'String',num2str(S.tc_peakWinMin));
        set(S.hTC_Trim,'String',num2str(S.tc_trimPct));

        setPopupToValue(S.hTC_PeakMethod, S.tc_peakMethod);
        setPopupToValue(S.hTC_Metric, S.tc_metric);
        setPopupToValue(S.hTC_LowerPlot, S.tc_lowerPlot);
    end

    function setPopupToValue(h, desired)
        items = get(h,'String');
        v = 1;
        for k=1:numel(items)
            if strcmpi(items{k}, desired), v = k; break; end
        end
        set(h,'Value',v);
    end

    function onTestChanged(~,~)
        S = guidata(hFig);
        items = get(S.hTest,'String');
        S.testType = items{get(S.hTest,'Value')};
        guidata(hFig,S);
    end

    function onAlphaChanged(src,~)
        S = guidata(hFig);
        a = str2double(get(src,'String'));
        if isnan(a) || a<=0 || a>=1
            set(src,'String',num2str(S.alpha)); return;
        end
        S.alpha = a;
        guidata(hFig,S);
    end

    function onAddFiles(~,~)
        S = guidata(hFig);
        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        [f,p] = uigetfile({'*.mat;*.txt','MAT or TXT (*.mat, *.txt)'}, ...
            'Select DATA (.mat) and/or ROI (.txt) files', startPath, 'MultiSelect','on');
        if isequal(f,0), return; end
        if ischar(f), f = {f}; end

        for i = 1:numel(f)
            addFileSmart(fullfile(p,f{i}));
        end
        refreshTable();
    end

    function onAddFolder(~,~)
        S = guidata(hFig);
        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        folder = uigetdir(startPath,'Select a folder to scan for .mat and .txt files');
        if isequal(folder,0), return; end

        dm = dir(fullfile(folder,'*.mat'));
        dt = dir(fullfile(folder,'*.txt'));

        for i = 1:numel(dm), addFileSmart(fullfile(dm(i).folder, dm(i).name)); end
        for i = 1:numel(dt), addFileSmart(fullfile(dt(i).folder, dt(i).name)); end

        refreshTable();
    end

    function onRemoveSelected(~,~)
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), return; end
        S.subj(sel,:) = [];
        S.selectedRows = [];
        guidata(hFig,S);
        refreshTable();
    end

    function onSetDataSelected(~,~)
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), return; end
        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select DATA (.mat)', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);

        for r = sel(:)'
            S.subj{r,5} = fp;
        end
        guidata(hFig,S);
        refreshTable();
    end

    function onSetROISelected(~,~)
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), return; end
        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        [f,p] = uigetfile({'*.txt;*.mat','ROI files (*.txt, *.mat)'}, 'Select ROI file', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);

        for r = sel(:)'
            S.subj{r,6} = fp;
        end
        guidata(hFig,S);
        refreshTable();
    end

    function onSaveList(~,~)
        S = guidata(hFig);
        [f,p] = uiputfile('GroupSubjects.mat','Save subject list');
        if isequal(f,0), return; end

        subj = S.subj; %#ok<NASGU>
        mode = S.mode; %#ok<NASGU>

        baseStart = S.baseStart; baseEnd = S.baseEnd; %#ok<NASGU>
        sigStart  = S.sigStart;  sigEnd  = S.sigEnd;  %#ok<NASGU>

        tc_computePSC = S.tc_computePSC; %#ok<NASGU>
        tc_baseMin0 = S.tc_baseMin0; tc_baseMin1 = S.tc_baseMin1; %#ok<NASGU>
        tc_injMin0 = S.tc_injMin0; tc_injMin1 = S.tc_injMin1; %#ok<NASGU>
        tc_plateauMin0 = S.tc_plateauMin0; tc_plateauMin1 = S.tc_plateauMin1; %#ok<NASGU>
        tc_peakSearchMin0 = S.tc_peakSearchMin0; tc_peakSearchMin1 = S.tc_peakSearchMin1; %#ok<NASGU>
        tc_peakWinMin = S.tc_peakWinMin; tc_trimPct = S.tc_trimPct; %#ok<NASGU>
        tc_peakMethod = S.tc_peakMethod; %#ok<NASGU>
        tc_metric = S.tc_metric; %#ok<NASGU>
        tc_lowerPlot = S.tc_lowerPlot; %#ok<NASGU>

        outDir = S.outDir; %#ok<NASGU>

        save(fullfile(p,f), ...
            'subj','mode','baseStart','baseEnd','sigStart','sigEnd', ...
            'tc_computePSC','tc_baseMin0','tc_baseMin1','tc_injMin0','tc_injMin1', ...
            'tc_plateauMin0','tc_plateauMin1','tc_peakSearchMin0','tc_peakSearchMin1', ...
            'tc_peakWinMin','tc_trimPct','tc_peakMethod','tc_metric','tc_lowerPlot', ...
            'outDir');
    end

    function onLoadList(~,~)
        S = guidata(hFig);
        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'},'Load subject list');
        if isequal(f,0), return; end
        L = load(fullfile(p,f));

        if isfield(L,'subj') && iscell(L.subj)
            if size(L.subj,2)==5
                subjNew = cell(size(L.subj,1),6);
                subjNew(:,1:4) = L.subj(:,1:4);
                subjNew(:,5)   = L.subj(:,5);
                subjNew(:,6)   = {''};
                S.subj = subjNew;
            else
                S.subj = L.subj;
            end
        end
        if isfield(L,'mode'), S.mode = L.mode; end
        if isfield(L,'baseStart'), S.baseStart = L.baseStart; end
        if isfield(L,'baseEnd'),   S.baseEnd   = L.baseEnd;   end
        if isfield(L,'sigStart'),  S.sigStart  = L.sigStart;  end
        if isfield(L,'sigEnd'),    S.sigEnd    = L.sigEnd;    end
        if isfield(L,'outDir'),    S.outDir    = L.outDir;    end

        if isfield(L,'tc_computePSC'), S.tc_computePSC = L.tc_computePSC; end
        if isfield(L,'tc_baseMin0'), S.tc_baseMin0 = L.tc_baseMin0; end
        if isfield(L,'tc_baseMin1'), S.tc_baseMin1 = L.tc_baseMin1; end
        if isfield(L,'tc_injMin0'), S.tc_injMin0 = L.tc_injMin0; end
        if isfield(L,'tc_injMin1'), S.tc_injMin1 = L.tc_injMin1; end
        if isfield(L,'tc_plateauMin0'), S.tc_plateauMin0 = L.tc_plateauMin0; end
        if isfield(L,'tc_plateauMin1'), S.tc_plateauMin1 = L.tc_plateauMin1; end
        if isfield(L,'tc_peakSearchMin0'), S.tc_peakSearchMin0 = L.tc_peakSearchMin0; end
        if isfield(L,'tc_peakSearchMin1'), S.tc_peakSearchMin1 = L.tc_peakSearchMin1; end
        if isfield(L,'tc_peakWinMin'), S.tc_peakWinMin = L.tc_peakWinMin; end
        if isfield(L,'tc_trimPct'), S.tc_trimPct = L.tc_trimPct; end
        if isfield(L,'tc_peakMethod'), S.tc_peakMethod = L.tc_peakMethod; end
        if isfield(L,'tc_metric'), S.tc_metric = L.tc_metric; end
        if isfield(L,'tc_lowerPlot'), S.tc_lowerPlot = L.tc_lowerPlot; end

        guidata(hFig,S);

        set(S.hMode,'Value', iff(strcmpi(S.mode,'PSC Map'),1,2));
        applyModeUI();
        setPSCUI();
        set(S.hOutEdit,'String',S.outDir);
        syncROIUIfromState();
        refreshTable();
        clearPreview();
    end

    function onOutEdit(src,~)
        S = guidata(hFig);
        S.outDir = strtrim(get(src,'String'));
        guidata(hFig,S);
    end

    function onBrowseOut(~,~)
        S = guidata(hFig);
        d = uigetdir(S.outDir,'Select output folder');
        if isequal(d,0), return; end
        S.outDir = d;
        guidata(hFig,S);
        set(S.hOutEdit,'String',S.outDir);
    end

    function onRun(~,~)
        S = guidata(hFig);
        if isempty(S.subj)
            errordlg('Add subject files first.','Group Analysis'); return;
        end

        % force-sync ROI edits before run (important)
        try, onTCParamsChanged([],[]); catch, end
        S = guidata(hFig);

        setStatus(false);
        logMsg('Running group analysis...');
        drawnow;

        try
            S.subj = get(S.hTable,'Data');
            guidata(hFig,S);

            if strcmpi(S.mode,'PSC Map')
                R = runPSCMapAnalysis();
            else
                R = runROITimecourseAnalysis();
            end

            S = guidata(hFig);
            S.last = R;
            guidata(hFig,S);

            updatePreview();
            logMsg('Group analysis finished.');
        catch ME
            logMsg(['RUN ERROR: ' ME.message]);
            errordlg(ME.message,'Group Analysis');
        end
    end

    function onExport(~,~)
        S = guidata(hFig);
        if ~isfield(S,'last') || isempty(fieldnames(S.last))
            errordlg('Run analysis first.','Export'); return;
        end

        outDir = S.outDir;
        if isempty(outDir), outDir = pwd; end
        if ~exist(outDir,'dir'), mkdir(outDir); end

        ts = datestr(now,'yyyymmdd_HHMMSS');
        outFolder = fullfile(outDir, ['GroupAnalysis_' ts]);
        mkdir(outFolder);

        R = S.last; %#ok<NASGU>
        save(fullfile(outFolder,'Results.mat'),'R','-v7.3');

        try
            f1 = figure('Visible','off','Color','w'); ax = axes('Parent',f1);
            exportOnePreview(ax,1);
            saveas(f1, fullfile(outFolder,'Preview1.png')); close(f1);
        catch
        end
        try
            f2 = figure('Visible','off','Color','w'); ax = axes('Parent',f2);
            exportOnePreview(ax,2);
            saveas(f2, fullfile(outFolder,'Preview2.png')); close(f2);
        catch
        end

        % CSV metrics (ROI mode)
        try
            if isfield(S.last,'metrics') && isfield(S.last.metrics,'table') && ~isempty(S.last.metrics.table)
                writeCellCSV(fullfile(outFolder,'Metrics.csv'), S.last.metrics.table);
            end
        catch
        end

        logMsg(['Exported results to: ' outFolder]);
    end

% =========================================================
% Analysis runners
% =========================================================
    function R = runPSCMapAnalysis()
        S = guidata(hFig);

        if S.baseEnd <= S.baseStart, error('Baseline end must be > baseline start.'); end
        if S.sigEnd  <= S.sigStart,  error('Signal end must be > signal start.'); end

        [G, files] = splitByGroup(S.subj, 5);
        if isempty(G.names), error('No groups defined.'); end

        maps = cell(1,numel(files));
        meta = struct('subject',[],'group',[],'file',[]);

        for i = 1:numel(files)
            row = S.subj(i,:);
            subj = row{1}; grp = row{2}; fp = row{5};
            if isempty(fp) || exist(fp,'file')~=2
                error('Missing DATA file for row %d.', i);
            end
            M = extractPSCMap(fp, S.baseStart, S.baseEnd, S.sigStart, S.sigEnd);
            maps{i} = M;
            meta(i).subject = subj;
            meta(i).group   = grp;
            meta(i).file    = fp;
        end

        summaryType = getPopupString(S.hSummary);
        groupSummary = struct();
        for g = 1:numel(G.names)
            idx = strcmp(G.labels, G.names{g});
            groupMaps = maps(idx);
            groupSummary(g).name = G.names{g};
            if strcmpi(summaryType,'Median'), groupSummary(g).map = medianCat(groupMaps);
            else,                            groupSummary(g).map = meanCat(groupMaps);
            end
        end

        R = struct();
        R.mode = 'PSC Map';
        R.windows = struct('baseStart',S.baseStart,'baseEnd',S.baseEnd,'sigStart',S.sigStart,'sigEnd',S.sigEnd);
        R.summaryType = summaryType;
        R.group = groupSummary;
        R.meta = meta;
    end

    function R = runROITimecourseAnalysis()
        S = guidata(hFig);

        [G, ~] = splitByGroup(S.subj, 2);
        if isempty(G.names), error('No groups defined.'); end

        N = size(S.subj,1);

        subjName = cell(N,1);
        grpName  = cell(N,1);
        condName = cell(N,1);
        pairID   = cell(N,1);

        tcRawAll = cell(N,1);
        tMinAll  = cell(N,1);

        isPSCInput = false(N,1);  % TRUE if ROI txt already contains PSC values

        for i = 1:N
            row = S.subj(i,:);

            subjName{i} = row{1};
            grpName{i}  = row{2};
            condName{i} = row{3};
            pairID{i}   = row{4};

            dataFile = '';
            roiFile  = '';
            if size(row,2)>=5 && ~isempty(row{5}), dataFile = strtrim(char(row{5})); end
            if size(row,2)>=6 && ~isempty(row{6}), roiFile  = strtrim(char(row{6})); end

            usedTxtPSC = false;
            tcRaw = [];
            tMin  = [];

            % 1) Try PSC-table txt (SCM export)
            [okTxt, tMinFile, pscFile, metaTxt] = tryReadSCMroiExportTxt(roiFile); %#ok<ASGLU>
            if okTxt
                tcRaw = double(pscFile(:))';
                tMin  = double(tMinFile(:))';
                usedTxtPSC = true;
                isPSCInput(i) = true;
            end

            % 2) Fallback: needs DATA .mat if ROI is coordinates
            if ~usedTxtPSC
                if isempty(dataFile) || exist(dataFile,'file')~=2
                    error('Row %d missing DATA .mat (required because ROI txt is not PSC-table).', i);
                end
                [tcRaw, tMin] = extractROITC_fromDataAndROI(dataFile, roiFile);
            end

            tcRawAll{i} = tcRaw(:)';
            tMinAll{i}  = tMin(:)';

            logMsg(sprintf('Loaded %d/%d | %s | %s | PSCtxt=%d', i, N, char(grpName{i}), char(subjName{i}), usedTxtPSC));
            drawnow;
        end

        % Build common time axis by overlap
        t0 = max(cellfun(@(x) x(1), tMinAll));
        t1 = min(cellfun(@(x) x(end), tMinAll));
        dt = median(diff(tMinAll{1}));
        if ~isfinite(dt) || dt<=0, dt = 0.1; end
        if t1 <= t0, error('Time axes do not overlap across subjects.'); end

        tCommon = t0:dt:t1;

        Xraw = nan(N, numel(tCommon));
        for i = 1:N
            Xraw(i,:) = interp1(tMinAll{i}(:), tcRawAll{i}(:), tCommon(:), 'linear', 'extrap').';
        end

        % Convert to %SC ONLY for rows that are NOT already PSC input
        X = Xraw;
        if S.tc_computePSC
            baseIdx = (tCommon >= S.tc_baseMin0) & (tCommon <= S.tc_baseMin1);
            if ~any(baseIdx)
                error('Baseline window has no samples. Adjust baseline minutes.');
            end
            for i = 1:N
                if isPSCInput(i)
                    continue; % already PSC from txt -> never compute again
                end
                b = nanmean_local(Xraw(i,baseIdx),2);
                if ~isfinite(b) || b==0, b = eps; end
                X(i,:) = 100 * (Xraw(i,:) - b) ./ b;
            end
        end

        unitsArePercent = any(isPSCInput) || S.tc_computePSC;

        % Group mean/SEM (for top plot)
        groupTC = struct();
        for g = 1:numel(G.names)
            idx = strcmpi(cellfun(@(z) strtrim(char(z)), grpName, 'UniformOutput',false), G.names{g});
            mu = nanmean_local(X(idx,:),1);
            sd = nanstd_local(X(idx,:),0,1);
            n  = sum(isfinite(X(idx,:)),1);
            se = sd ./ sqrt(max(1,n));

            groupTC(g).name = G.names{g};
            groupTC(g).mean = mu;
            groupTC(g).sem  = se;
            groupTC(g).n    = sum(idx);
        end

        % Per-subject metrics
        plateau = nan(N,1);
        peakVal = nan(N,1);
        peakTime = nan(N,1);
        peakWin = nan(N,2); % [start end] minutes

        platIdx = (tCommon >= S.tc_plateauMin0) & (tCommon <= S.tc_plateauMin1);
        if ~any(platIdx)
            error('Plateau window has no samples.');
        end

        for i = 1:N
            plateau(i) = nanmean_local(X(i,platIdx),2);

            [pv, pt, pw] = computePeakMetric( ...
                X(i,:), tCommon, ...
                S.tc_peakSearchMin0, S.tc_peakSearchMin1, ...
                S.tc_peakWinMin, S.tc_trimPct, S.tc_peakMethod);

            peakVal(i)  = pv;
            peakTime(i) = pt;
            peakWin(i,:) = pw;
        end

        % Metric selection (for scatter + stats)
        if strcmpi(S.tc_metric,'Plateau')
            metricVals = plateau;
            metricName = sprintf('Plateau mean (%.1f–%.1f min)', S.tc_plateauMin0, S.tc_plateauMin1);
        else
            metricVals = peakVal;
            metricName = sprintf('Peak (%s) in %.1f–%.1f min', S.tc_peakMethod, S.tc_peakSearchMin0, S.tc_peakSearchMin1);
        end

        % Stats on metricVals
        testType = getPopupString(S.hTest);
        alpha = S.alpha;
        stats = struct('type',testType,'alpha',alpha,'p',[],'t',[],'F',[],'df',[],'desc','');

        if strcmpi(testType,'None')
            stats.desc = 'No statistical test.';
        elseif strcmpi(testType,'One-sample (vs 0)')
            [t,p,df] = oneSampleT_vec(metricVals);
            stats.t = t; stats.p = p; stats.df = df;
            stats.desc = 'One-sample t-test (metric vs 0).';
        elseif strcmpi(testType,'Two-sample (GroupA vs GroupB)')
            if numel(G.names) < 2, error('Need at least 2 groups.'); end
            a = metricVals(strcmpi(cellfun(@(z) strtrim(char(z)), grpName, 'UniformOutput',false), G.names{1}));
            b = metricVals(strcmpi(cellfun(@(z) strtrim(char(z)), grpName, 'UniformOutput',false), G.names{2}));
            [t,p,df] = welchT_vec(a,b);
            stats.t = t; stats.p = p; stats.df = df;
            stats.desc = sprintf('Welch t-test | %s vs %s', G.names{1}, G.names{2});
        elseif strcmpi(testType,'Paired (CondA vs CondB)')
            [t,p,df,desc] = pairedT_metric_fromTable(S.subj, metricVals);
            stats.t = t; stats.p = p; stats.df = df;
            stats.desc = desc;
        elseif strcmpi(testType,'One-way ANOVA (groups)')
            [F,p,df] = oneWayANOVA_metric(metricVals, grpName);
            stats.F = F; stats.p = p; stats.df = df;
            stats.desc = 'One-way ANOVA across groups.';
        end

        % Group-mean peak (for "Peak window view" in lower plot)
        groupPeak = struct();
        for g = 1:numel(groupTC)
            [pv, pt, pw] = computePeakMetric( ...
                groupTC(g).mean, tCommon, ...
                S.tc_peakSearchMin0, S.tc_peakSearchMin1, ...
                S.tc_peakWinMin, S.tc_trimPct, S.tc_peakMethod);
            groupPeak(g).name = groupTC(g).name;
            groupPeak(g).val = pv;
            groupPeak(g).time = pt;
            groupPeak(g).win = pw;
        end

        % CSV metrics table
        Tcell = cell(N+1, 8);
        Tcell(1,:) = {'Subject','Group','Condition','PairID','Plateau_%','Peak_%','PeakTime_min','PeakWin_min'};
        for i=1:N
            Tcell{i+1,1} = subjName{i};
            Tcell{i+1,2} = grpName{i};
            Tcell{i+1,3} = condName{i};
            Tcell{i+1,4} = pairID{i};
            Tcell{i+1,5} = plateau(i);
            Tcell{i+1,6} = peakVal(i);
            Tcell{i+1,7} = peakTime(i);
            Tcell{i+1,8} = sprintf('%.2f-%.2f', peakWin(i,1), peakWin(i,2));
        end

        R = struct();
        R.mode = 'ROI Timecourse';
        R.tMin = tCommon;
        R.group = groupTC;
        R.groupPeak = groupPeak;
        R.infusion = [S.tc_injMin0 S.tc_injMin1];
        R.unitsPercent = unitsArePercent;

        R.metricName = metricName;
        R.metricVals = metricVals;
        R.stats = stats;

        R.metrics = struct();
        R.metrics.plateau = plateau;
        R.metrics.peakVal = peakVal;
        R.metrics.peakTime = peakTime;
        R.metrics.peakWin = peakWin;
        R.metrics.table = Tcell;

        R.subjTable = S.subj;
        R.lowerPlotMode = S.tc_lowerPlot;
        R.peakMethod = S.tc_peakMethod;
        R.peakSearch = [S.tc_peakSearchMin0 S.tc_peakSearchMin1];
        R.peakWinMin = S.tc_peakWinMin;
        R.trimPct = S.tc_trimPct;
    end

% =========================================================
% Preview rendering
% =========================================================
    function clearPreview()
        S = guidata(hFig);
        cla(S.ax1); cla(S.ax2);
        title(S.ax1,'Preview 1','Color','w','FontWeight','bold');
        title(S.ax2,'Preview 2','Color','w','FontWeight','bold');
    end

    function updatePreview()
        S = guidata(hFig);
        clearPreview();
        if ~isfield(S,'last') || isempty(fieldnames(S.last)), return; end
        R = S.last;

        if strcmpi(R.mode,'PSC Map')
            if ~isempty(R.group)
                imagesc_auto(S.ax1, squeeze2D(R.group(1).map));
                title(S.ax1, ['Group: ' R.group(1).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax1);
            end
            if numel(R.group) >= 2
                imagesc_auto(S.ax2, squeeze2D(R.group(2).map));
                title(S.ax2, ['Group: ' R.group(2).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax2);
            end
            return;
        end

        t = R.tMin(:)';

        % ---- TOP: mean ± SEM ----
        axes(S.ax1); %#ok<LAXES>
        cla(S.ax1); hold(S.ax1,'on');

        % infusion shading
        if isfield(R,'infusion') && numel(R.infusion)==2
            x0 = R.infusion(1); x1 = R.infusion(2);
            yL = get(S.ax1,'YLim');
            if ~isfinite(yL(1)) || ~isfinite(yL(2)) || yL(1)==yL(2)
                yL = [-10 150];
            end
            patch(S.ax1, [x0 x1 x1 x0], [yL(1) yL(1) yL(2) yL(2)], ...
                [0.8 0.8 0.8], 'FaceAlpha',0.15,'EdgeColor','none');
        end

        leg = {};
        for g = 1:numel(R.group)
            [lc, fc] = colorForGroup(R.group(g).name, S.C);
            shadedLineColored(S.ax1, t, R.group(g).mean(:)', R.group(g).sem(:)', lc, fc);
            leg{end+1} = sprintf('%s (n=%d)', R.group(g).name, R.group(g).n); %#ok<AGROW>
        end
        grid(S.ax1,'on');
        set(S.ax1,'XColor','w','YColor','w','Color',[0 0 0]);
        xlabel(S.ax1,'Time (min)','Color','w');
        if R.unitsPercent, ylabel(S.ax1,'Signal change (%)','Color','w');
        else,             ylabel(S.ax1,'ROI signal','Color','w');
        end
        title(S.ax1,'Mean ROI timecourse ± SEM','Color','w','FontWeight','bold');
        legend(S.ax1, leg, 'TextColor','w','Location','northwest','Box','off');
        hold(S.ax1,'off');

        % ---- BOTTOM: depends on lower plot mode ----
        axes(S.ax2); %#ok<LAXES>
        cla(S.ax2); hold(S.ax2,'on');

        if strcmpi(R.lowerPlotMode,'Metric scatter')
            gNames = cell(numel(R.group),1);
            for g=1:numel(R.group), gNames{g} = R.group(g).name; end

            subjTbl = R.subjTable;
            grpCol = subjTbl(:,2);
            metricVals = R.metricVals;

            xTicks = 1:numel(gNames);
            for g = 1:numel(gNames)
                idx = strcmpi(cellfun(@(x) strtrim(char(x)), grpCol, 'UniformOutput',false), gNames{g});
                y = metricVals(idx);
                y = y(isfinite(y));
                if isempty(y), continue; end

                [lc, ~] = colorForGroup(gNames{g}, S.C);
                x0 = xTicks(g);
                jitter = (rand(size(y)) - 0.5) * 0.18;
                scatter(S.ax2, x0 + jitter, y, 70, lc, 'filled');

                m = mean(y);
                plot(S.ax2, [x0-0.25 x0+0.25], [m m], 'LineWidth',2.5, 'Color',lc);
            end

            set(S.ax2,'XLim',[0.5 numel(gNames)+0.5], 'XTick',xTicks, 'XTickLabel',gNames, ...
                'XColor','w','YColor','w','Color',[0 0 0]);
            if R.unitsPercent, ylabel(S.ax2,'Signal change (%)','Color','w');
            else,             ylabel(S.ax2,'Metric (a.u.)','Color','w');
            end

            titleStr = ['Metric: ' R.metricName];
            if isfield(R,'stats') && isfield(R.stats,'p') && ~isempty(R.stats.p) && isfinite(R.stats.p)
                titleStr = sprintf('%s | p=%.4g', titleStr, R.stats.p);
            end
            title(S.ax2, titleStr, 'Color','w','FontWeight','bold');
            grid(S.ax2,'on');

        else
            % Peak window view: show group means + highlight detected peak window
            % Shade search interval
            s0 = R.peakSearch(1); s1 = R.peakSearch(2);
            yL = get(S.ax2,'YLim');
            if ~isfinite(yL(1)) || ~isfinite(yL(2)) || yL(1)==yL(2)
                yL = [-10 150];
            end
            patch(S.ax2, [s0 s1 s1 s0], [yL(1) yL(1) yL(2) yL(2)], ...
                [0.8 0.8 0.8], 'FaceAlpha',0.10,'EdgeColor','none');

            for g=1:numel(R.group)
                [lc, ~] = colorForGroup(R.group(g).name, S.C);
                plot(S.ax2, t, R.group(g).mean(:)', 'LineWidth',2.0, 'Color',lc);

                if isfield(R,'groupPeak') && numel(R.groupPeak)>=g
                    pw = R.groupPeak(g).win;
                    pv = R.groupPeak(g).val;
                    pt = R.groupPeak(g).time;

                    % highlight window
                    plot(S.ax2, [pw(1) pw(2)], [pv pv], 'LineWidth',4.0, 'Color',lc);
                    plot(S.ax2, pt, pv, 'o', 'MarkerSize',7, 'LineWidth',2, 'Color',lc);
                end
            end

            set(S.ax2,'XColor','w','YColor','w','Color',[0 0 0]);
            xlabel(S.ax2,'Time (min)','Color','w');
            if R.unitsPercent, ylabel(S.ax2,'Signal change (%)','Color','w');
            else,             ylabel(S.ax2,'Signal (a.u.)','Color','w');
            end
            grid(S.ax2,'on');

            % title includes method + settings
            title(S.ax2, sprintf('Peak view | %s | search %.1f–%.1f min | win %.1f min | trim %.0f%%', ...
                R.peakMethod, R.peakSearch(1), R.peakSearch(2), R.peakWinMin, R.trimPct), ...
                'Color','w','FontWeight','bold');
        end

        hold(S.ax2,'off');
    end

    function exportOnePreview(ax, which)
        S = guidata(hFig);
        R = S.last;
        cla(ax);

        if strcmpi(R.mode,'PSC Map')
            if which==1
                imagesc(ax, squeeze2D(R.group(1).map)); axis(ax,'image'); axis(ax,'off'); title(ax,R.group(1).name); colorbar(ax);
            else
                if numel(R.group)>=2
                    imagesc(ax, squeeze2D(R.group(2).map)); axis(ax,'image'); axis(ax,'off'); title(ax,R.group(2).name); colorbar(ax);
                end
            end
            return;
        end

        if which==1
            % export top plot
            t = R.tMin(:)';
            hold(ax,'on');
            if isfield(R,'infusion') && numel(R.infusion)==2
                x0=R.infusion(1); x1=R.infusion(2);
                patch(ax,[x0 x1 x1 x0],[-1e9 -1e9 1e9 1e9],[0.85 0.85 0.85],'FaceAlpha',0.25,'EdgeColor','none');
            end
            for g=1:numel(R.group)
                [lc, fc] = colorForGroup(R.group(g).name, S.C);
                shadedLineColored(ax,t,R.group(g).mean(:)',R.group(g).sem(:)',lc,fc);
            end
            grid(ax,'on'); xlabel(ax,'Time (min)');
            if R.unitsPercent, ylabel(ax,'Signal change (%)'); else, ylabel(ax,'ROI signal'); end
            title(ax,'Mean ROI timecourse ± SEM');
            hold(ax,'off');
        else
            % export bottom plot as metric scatter
            t = R.tMin(:)'; %#ok<NASGU>
            subjTbl = R.subjTable;
            grpCol = subjTbl(:,2);
            metricVals = R.metricVals;

            gNames = cell(numel(R.group),1);
            for g=1:numel(R.group), gNames{g}=R.group(g).name; end
            xTicks = 1:numel(gNames);

            hold(ax,'on');
            for g=1:numel(gNames)
                idx = strcmpi(cellfun(@(x) strtrim(char(x)), grpCol,'UniformOutput',false), gNames{g});
                y = metricVals(idx); y = y(isfinite(y));
                if isempty(y), continue; end
                [lc, ~] = colorForGroup(gNames{g}, S.C);
                x0 = xTicks(g);
                jitter = (rand(size(y)) - 0.5) * 0.18;
                scatter(ax, x0+jitter, y, 60, lc, 'filled');
                plot(ax,[x0-0.25 x0+0.25],[mean(y) mean(y)],'LineWidth',2.5,'Color',lc);
            end
            set(ax,'XLim',[0.5 numel(gNames)+0.5],'XTick',xTicks,'XTickLabel',gNames);
            if R.unitsPercent, ylabel(ax,'Signal change (%)'); else, ylabel(ax,'Metric'); end
            title(ax,['Metric: ' R.metricName]);
            grid(ax,'on');
            hold(ax,'off');
        end
    end

% =========================================================
% Helpers: subject handling
% =========================================================
    function addFileSmart(fp)
        S = guidata(hFig);
        ext = lower(fileExt(fp));

        subj = guessSubjectID(fp);
        if isempty(subj), subj = ['S' num2str(size(S.subj,1)+1)]; end

        rowIdx = find(strcmpi(S.subj(:,1), subj), 1, 'first');

        if strcmp(ext,'.txt')
            if ~isempty(rowIdx)
                S.subj{rowIdx,6} = fp;
            else
                S.subj(end+1,:) = {subj,'PACAP','CondA','', '', fp};
            end
        else
            if ~isempty(rowIdx)
                S.subj{rowIdx,5} = fp;
            else
                S.subj(end+1,:) = {subj,'PACAP','CondA','', fp, ''};
            end
        end

        guidata(hFig,S);
    end

    function refreshTable()
        S = guidata(hFig);
        set(S.hTable,'Data',S.subj);
        drawnow;
    end

% =========================================================
% Extraction: PSC map + ROI TC
% =========================================================
    function M = extractPSCMap(fp, b0, b1, s0, s1)
        [ok, M] = tryLoadNumericMap(fp);
        if ok, M = double(M); return; end

        D = loadPipelineStruct(fp);
        if ~isfield(D,'TR') || isempty(D.TR), error('Missing TR in %s', fp); end
        if ~isfield(D,'I')  || isempty(D.I),  error('Missing I in %s', fp);  end

        I = D.I;
        TR = double(D.TR);
        dimT = ndims(I);
        T = size(I, dimT);

        bIdx = secToIdx(b0,b1,TR,T);
        sIdx = secToIdx(s0,s1,TR,T);

        baseMean = meanOverFrames(I, bIdx, dimT);
        sigMean  = meanOverFrames(I, sIdx, dimT);

        baseMean = double(baseMean);
        sigMean  = double(sigMean);

        baseMean(baseMean==0) = eps;
        M = 100 * (sigMean - baseMean) ./ baseMean;
        M(~isfinite(M)) = 0;
    end

    function [tcRaw, tMin] = extractROITC_fromDataAndROI(dataFile, roiFile)
        if nargin < 2, roiFile = ''; end
        roiFile = strtrim(char(roiFile));
        dataFile = strtrim(char(dataFile));

        if isempty(roiFile)
            [tcRaw, tMin] = extractROITC_legacyMat(dataFile);
            return;
        end

        if exist(roiFile,'file')~=2
            error('ROI file not found: %s', roiFile);
        end

        [~,~,ext] = fileparts(roiFile);
        ext = lower(ext);

        if strcmp(ext,'.mat')
            [tcRaw, tMin] = extractROITC_legacyMat(roiFile);
            return;
        end

        if ~strcmp(ext,'.txt')
            error('ROI file must be .txt or .mat: %s', roiFile);
        end

        % coordinate ROI txt -> need DATA .mat
        D = loadPipelineStruct(dataFile);
        if ~isfield(D,'I') || isempty(D.I), error('DATA file missing I: %s', dataFile); end
        if ~isfield(D,'TR') || isempty(D.TR), error('DATA file missing TR: %s', dataFile); end
        I = D.I; TR = double(D.TR);

        roi = readROITxt(roiFile);
        tcRaw = roiMeanTimecourse(I, roi);
        T = numel(tcRaw);
        tMin = (0:(T-1))*(TR/60);
    end

% =========================================================
% Studio integration hooks
% =========================================================
    function setStatus(isReady)
        if ~isempty(opt.statusFcn)
            try, opt.statusFcn(logical(isReady)); catch, end
        end
    end

    function logMsg(msg)
        if ~isempty(opt.logFcn)
            try, opt.logFcn(msg); catch, end
        else
            try, disp(msg); catch, end
        end
    end

end % end main function


% =========================================================
% Local helper functions (file scope)
% =========================================================
function d = defaultOutDir(opt)
d = pwd;
if isfield(opt,'studio') && isstruct(opt.studio) && isfield(opt.studio,'exportPath') && ~isempty(opt.studio.exportPath)
    d = fullfile(opt.studio.exportPath,'GroupAnalysis');
end
end

function makeWinRow(parent, y, label, init, cb, tag)
bg = get(parent,'BackgroundColor');
uicontrol(parent,'Style','text','String',[label ':'], ...
    'Units','normalized','Position',[0.05 y 0.45 0.18], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);
uicontrol(parent,'Style','edit','String',init, ...
    'Units','normalized','Position',[0.52 y+0.01 0.40 0.18], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Tag',tag,'Callback',@(s,e) cb(s,e,tag));
end

function s = getPopupString(h)
items = get(h,'String');
s = items{get(h,'Value')};
end

function out = iff(cond,a,b)
if cond, out = a; else, out = b; end
end

function sel = clampSelRows(sel, nRows)
if isempty(sel), sel = []; return; end
sel = unique(sel(:)');
sel = sel(sel>=1 & sel<=nRows);
end

function v = safeNum(str, fallback)
v = str2double(str);
if isnan(v) || ~isfinite(v), v = fallback; end
end

function ext = fileExt(fp)
[~,~,ext] = fileparts(fp);
end

function subj = guessSubjectID(fp)
[~,name,~] = fileparts(fp);
subj = name;
subj = regexprep(subj,'(?i)_roi\d+$','');
subj = regexprep(subj,'(?i)roi\d+$','');
subj = regexprep(subj,'(?i)_roi$','');
subj = regexprep(subj,'\s+','_');
subj = regexprep(subj,'[^A-Za-z0-9_]+','_');
subj = regexprep(subj,'_+','_');
subj = regexprep(subj,'^_','');
subj = regexprep(subj,'_$','');
end

function [G, files] = splitByGroup(subjTable, fileCol)
if nargin < 2, fileCol = 5; end
files = subjTable(:,fileCol);
labels = subjTable(:,2);
labels = cellfun(@(x) strtrim(char(x)), labels, 'UniformOutput',false);
labels(cellfun(@isempty,labels)) = {'GroupA'};
names = unique(labels,'stable');
G = struct('labels',{labels},'names',{names});
end

function [ok, M] = tryLoadNumericMap(fp)
ok = false; M = [];
try, L = load(fp); catch, return; end
cands = {'PSCmap','pscMap','map','Map','beta','Beta','tMap','T','Tmap','meanMap'};
for i = 1:numel(cands)
    if isfield(L,cands{i}) && isnumeric(L.(cands{i}))
        M = L.(cands{i}); ok = true; return;
    end
end
end

function D = loadPipelineStruct(fp)
L = load(fp);

if isfield(L,'newData') && isstruct(L.newData), D = pullFields(L.newData); return; end
if isfield(L,'data')    && isstruct(L.data),    D = pullFields(L.data);    return; end

fn = fieldnames(L);
for i = 1:numel(fn)
    if isstruct(L.(fn{i}))
        D = pullFields(L.(fn{i}));
        if ~isempty(D.I) || ~isempty(D.TR), return; end
    end
end
error('Could not find pipeline struct with I/TR in: %s', fp);
end

function D = pullFields(S)
D = struct();
if isfield(S,'I'),  D.I  = S.I;  else, D.I  = []; end
if isfield(S,'TR'), D.TR = S.TR; else, D.TR = []; end
end

function idx = secToIdx(s0,s1,TR,T)
i0 = floor(s0/TR) + 1;
i1 = floor(s1/TR);
i0 = max(1, min(T, i0));
i1 = max(1, min(T, i1));
if i1 < i0, idx = i0; else, idx = i0:i1; end
end

function M = meanOverFrames(I, idx, dimT)
subs = repmat({':'},1,ndims(I));
subs{dimT} = idx;
X = I(subs{:});
M = mean(double(X), dimT);
end

function Y = squeeze2D(X)
if ndims(X)==3 && size(X,3)>1
    z = round(size(X,3)/2);
    Y = X(:,:,z);
else
    Y = X;
end
end

function imagesc_auto(ax, A)
A = double(A);
A(~isfinite(A)) = 0;
imagesc(ax, A);
axis(ax,'image'); axis(ax,'off');
set(ax,'XColor','w','YColor','w');
end

function m = meanCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmean_local(X, ndims(X));
end

function m = medianCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmedian_local(X, ndims(X));
end

function X = catAlong4(cellMaps)
N = numel(cellMaps);
sz = size(cellMaps{1});
if numel(sz)==2
    X = zeros(sz(1),sz(2),N);
    for i=1:N, X(:,:,i)=double(cellMaps{i}); end
else
    X = zeros(sz(1),sz(2),sz(3),N);
    for i=1:N, X(:,:,:,i)=double(cellMaps{i}); end
end
end

function shadedLineColored(ax, x, y, e, lineColor, fillColor)
x = x(:)'; y = y(:)'; e = e(:)';
up = y+e; dn = y-e;
patch(ax, [x fliplr(x)], [up fliplr(dn)], fillColor, 'FaceAlpha',0.20, 'EdgeColor','none');
plot(ax, x, y, 'LineWidth',2.2, 'Color',lineColor);
end

function [lc, fc] = colorForGroup(name, C)
nm = upper(strtrim(name));
if ~isempty(strfind(nm,'PACAP'))
    lc = C.pacapLine; fc = C.pacapFill; return;
end
if ~isempty(strfind(nm,'VEH')) || ~isempty(strfind(nm,'VEHICLE')) || ~isempty(strfind(nm,'CONTROL'))
    lc = C.vehicleLine; fc = C.vehicleFill; return;
end
lc = [0.85 0.85 0.30]; fc = lc;
end

function mu = nanmean_local(X, dim)
try
    mu = mean(X, dim, 'omitnan');
catch
    n = sum(isfinite(X),dim);
    X2 = X; X2(~isfinite(X2)) = 0;
    mu = sum(X2,dim) ./ max(1,n);
end
end

function md = nanmedian_local(X, dim)
try
    md = median(X, dim, 'omitnan');
catch
    % fallback
    sz = size(X); nd = numel(sz);
    dim = max(1, min(nd, dim));
    perm = 1:nd; perm([dim nd]) = [nd dim];
    Y = permute(X, perm);
    Y = reshape(Y, [], sz(dim));
    Y(~isfinite(Y)) = NaN;
    Y = sort(Y, 2, 'ascend');
    n = sum(isfinite(Y), 2);
    mdFlat = NaN(size(n));
    for i = 1:numel(n)
        ni = n(i);
        if ni<=0, continue; end
        if mod(ni,2)==1
            mdFlat(i) = Y(i,(ni+1)/2);
        else
            mdFlat(i) = 0.5*(Y(i,ni/2)+Y(i,ni/2+1));
        end
    end
    Y2 = reshape(mdFlat, sz(perm(1:end-1)));
    md = ipermute(Y2, perm);
end
end

function sd = nanstd_local(X, flag, dim)
if nargin < 2, flag = 0; end
try
    sd = std(X, flag, dim, 'omitnan');
catch
    mu = nanmean_local(X,dim);
    muRep = repmat(mu, repSize(size(X),dim));
    D = X - muRep;
    D(~isfinite(D)) = 0;
    n = sum(isfinite(X),dim);
    v = sum(D.^2,dim) ./ max(1, (n - (flag==0)));
    sd = sqrt(max(0,v));
end
end

function rs = repSize(sz, dim)
rs = ones(1,numel(sz));
rs(dim) = sz(dim);
end

% ---------------- ROI coordinate txt readers ----------------
function roi = readROITxt(f)
A = dlmread(f);
A = double(A);
A = A(~any(isnan(A),2),:);
if isempty(A), error('ROI txt is empty: %s', f); end
if any(A(:)==0) && all(A(:) >= 0), A = A + 1; end
roi = A;
end

function tc = roiMeanTimecourse(I, roi)
d = ndims(I);
if d~=3 && d~=4, error('I must be [Y X T] or [Y X Z T].'); end

sz = size(I);
Y = sz(1); X = sz(2);
if d==4, Z = sz(3); T = sz(4); else, Z = 1; T = sz(3); end

roi = double(roi);

if size(roi,2)==1
    lin = roi(:,1);
    lin = lin(lin>=1);
    if d==3
        lin = lin(lin<=Y*X);
        [r,c] = ind2sub([Y X], lin);
        z = ones(size(r));
    else
        lin = lin(lin<=Y*X*Z);
        [r,c,z] = ind2sub([Y X Z], lin);
    end
elseif size(roi,2)==2
    r = roi(:,1); c = roi(:,2); z = ones(size(r));
else
    r = roi(:,1); c = roi(:,2); z = roi(:,3);
end

r = round(r); c = round(c); z = round(z);
keep = (r>=1 & r<=Y & c>=1 & c<=X & z>=1 & z<=Z);
r = r(keep); c = c(keep); z = z(keep);
if isempty(r), error('ROI has no valid points after bounds check.'); end

tc = zeros(1,T);
if d==3
    lin = sub2ind([Y X], r, c);
    for t=1:T
        frame = double(I(:,:,t));
        tc(t) = mean(frame(lin));
    end
else
    lin = sub2ind([Y X Z], r, c, z);
    for t=1:T
        frame = double(I(:,:,:,t));
        tc(t) = mean(frame(lin));
    end
end
tc(~isfinite(tc)) = NaN;
end

function [tcRaw, tMin] = extractROITC_legacyMat(fp)
L = load(fp);
if isfield(L,'roiTC'), tc = L.roiTC;
elseif isfield(L,'TC'), tc = L.TC;
else, error('MAT file must contain roiTC (or TC): %s', fp);
end
tc = double(tc);
if size(tc,1) > size(tc,2), tc = tc.'; end
if size(tc,1) > 1, tc = nanmean_local(tc,1); end
tcRaw = tc(:)';

if isfield(L,'tSec') && ~isempty(L.tSec)
    tMin = double(L.tSec(:)')/60;
elseif isfield(L,'TR') && ~isempty(L.TR)
    TR = double(L.TR);
    tMin = (0:(numel(tcRaw)-1))*(TR/60);
else
    error('ROI mat must contain tSec or TR.');
end
end

% ---------------- SCM_gui ROI export parser (PSC table txt) ----------------
function [ok, tMin, psc, meta] = tryReadSCMroiExportTxt(fname)
% Reads SCM_gui ROI export text format:
%  - header lines start with '#'
%  - contains line: "# columns: time_sec time_min PSC"
%  - followed by numeric table rows
ok = false; tMin = []; psc = [];
meta = struct();

if nargin < 1 || isempty(fname), return; end
fname = strtrim(char(fname));
if exist(fname,'file')~=2, return; end

fid = fopen(fname,'r');
if fid < 0, return; end
cln = onCleanup(@() fclose(fid)); %#ok<NASGU>

inTable = false;

while true
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end

    if startsWith(ln,'#')
        % basic meta parsing (optional)
        if contains(ln,'TR_sec:')
            meta.TR_sec = str2double(strtrim(afterToken(ln,'TR_sec:')));
        elseif contains(ln,'BaselineWindow:')
            meta.BaselineWindow_sec = parseRangeSec(afterToken(ln,'BaselineWindow:'));
        elseif contains(ln,'SignalWindow:')
            meta.SignalWindow_sec = parseRangeSec(afterToken(ln,'SignalWindow:'));
        end

        if contains(lower(ln),'# columns:') && contains(lower(ln),'psc')
            inTable = true;
        end
        continue;
    end

    if inTable
        vals = sscanf(ln,'%f');
        if numel(vals) >= 3
            tMin(end+1,1) = vals(2); %#ok<AGROW>
            psc(end+1,1)  = vals(3); %#ok<AGROW>
        end
    end
end

if numel(tMin) >= 5 && numel(psc)==numel(tMin)
    ok = true;
end

if isfield(meta,'SignalWindow_sec') && numel(meta.SignalWindow_sec)==2
    meta.SignalWindow_min = meta.SignalWindow_sec/60;
end
if isfield(meta,'BaselineWindow_sec') && numel(meta.BaselineWindow_sec)==2
    meta.BaselineWindow_min = meta.BaselineWindow_sec/60;
end
end

function s = afterToken(line, token)
k = strfind(line, token);
if isempty(k), s=''; return; end
s = line(k(1)+numel(token):end);
end

function r = parseRangeSec(s)
s = strtrim(s);
s = strrep(s,' ','');
parts = strsplit(s,'-');
if numel(parts)~=2, r=[NaN NaN]; return; end
r = [str2double(parts{1}) str2double(parts{2})];
end

% ---------------- Peak metric core ----------------
function [pkVal, pkTime, pkWin] = computePeakMetric(y, tMin, s0, s1, winMin, trimPct, method)
y = double(y(:)');
tMin = double(tMin(:)');

pkVal = NaN; pkTime = NaN; pkWin = [NaN NaN];

idxAll = find(tMin>=s0 & tMin<=s1);
if numel(idxAll) < 1, return; end

dt = median(diff(tMin));
if ~isfinite(dt) || dt<=0, dt = 0.1; end

method = strtrim(char(method));
if strcmpi(method,'Single-point max')
    [pkVal, j] = max(y(idxAll));
    pkTime = tMin(idxAll(j));
    pkWin = [pkTime pkTime];
    return;
end

w = max(1, round(winMin / dt));
iStart = idxAll(1);
iEnd   = idxAll(end);

best = -Inf;
bestStart = NaN;
bestEnd = NaN;

for i = iStart:(iEnd - w + 1)
    j = i + w - 1;
    if j > iEnd, break; end
    if tMin(j) > s1, break; end

    seg = y(i:j);
    seg = seg(isfinite(seg));
    if isempty(seg), continue; end

    if strcmpi(method,'Window mean')
        val = mean(seg);
    elseif strcmpi(method,'Window median')
        val = median(seg);
    else
        % Window trimmed mean
        val = trimmedMean(seg, trimPct);
    end

    if val > best
        best = val;
        bestStart = i;
        bestEnd = j;
    end
end

if ~isfinite(best), return; end

pkVal = best;
pkWin = [tMin(bestStart) tMin(bestEnd)];
pkTime = mean(pkWin);
end

function m = trimmedMean(x, trimPct)
x = x(:); x = x(isfinite(x));
if isempty(x), m = NaN; return; end
x = sort(x,'ascend');
n = numel(x);
tp = max(0, min(49, round(trimPct)));
k = floor((tp/100)*n/2);
i0 = 1+k;
i1 = n-k;
if i1 < i0, m = mean(x);
else,        m = mean(x(i0:i1));
end
end

% ---------------- Metric stats ----------------
function [t,p,df] = oneSampleT_vec(x)
x = x(:); x = x(isfinite(x));
n = numel(x);
if n < 2, t = NaN; p = NaN; df = max(0,n-1); return; end
mu = mean(x); sd = std(x,0); se = sd/sqrt(n);
t = mu / max(eps,se);
df = n-1;
if exist('tcdf','file')==2, p = 2*tcdf(-abs(t),df); else, p = NaN; end
end

function [t,p,df] = welchT_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1 = numel(a); n2 = numel(b);
if n1<2 || n2<2, t=NaN; p=NaN; df=NaN; return; end
m1 = mean(a); m2 = mean(b);
v1 = var(a,0); v2 = var(b,0);
den = sqrt(v1/n1 + v2/n2);
t = (m1-m2) / max(eps,den);
df = (v1/n1 + v2/n2)^2 / ( (v1^2)/(n1^2*max(1,n1-1)) + (v2^2)/(n2^2*max(1,n2-1)) );
df = max(1, df);
if exist('tcdf','file')==2, p = 2*tcdf(-abs(t),df); else, p = NaN; end
end

function [F,p,df] = oneWayANOVA_metric(x, groupLabels)
x = x(:);
keep = isfinite(x);
x = x(keep);
g = groupLabels(keep);
g = cellfun(@(s) strtrim(char(s)), g, 'UniformOutput',false);
u = unique(g,'stable');
k = numel(u);
n = numel(x);
if k < 2 || n < 3, F=NaN; p=NaN; df=[k-1 n-k]; return; end

grand = mean(x);
SSb = 0; SSw = 0;
for i=1:k
    xi = x(strcmpi(g,u{i}));
    if isempty(xi), continue; end
    mi = mean(xi);
    SSb = SSb + numel(xi)*(mi-grand)^2;
    SSw = SSw + sum((xi-mi).^2);
end

df1 = k-1; df2 = n-k;
MSb = SSb / max(1,df1);
MSw = SSw / max(1,df2);
F = MSb / max(eps,MSw);
df = [df1 df2];

if exist('fcdf','file')==2, p = 1 - fcdf(F,df1,df2); else, p = NaN; end
end

function [t,p,df,desc] = pairedT_metric_fromTable(subjTable, metricVals)
pairs = subjTable(:,4);
conds = subjTable(:,3);

pairs = cellfun(@(x) strtrim(char(x)), pairs, 'UniformOutput',false);
conds = cellfun(@(x) strtrim(char(x)), conds, 'UniformOutput',false);

uPairs = unique(pairs(~cellfun(@isempty,pairs)),'stable');
uConds = unique(conds(~cellfun(@isempty,conds)),'stable');

if numel(uPairs) < 2, error('Paired test needs PairID filled.'); end
if numel(uConds) < 2, error('Paired test needs 2 Condition labels.'); end

condA = uConds{1}; condB = uConds{2};
desc = ['Paired t-test (metric) | ' condA ' vs ' condB];

diffs = [];
for i = 1:numel(uPairs)
    pid = uPairs{i};
    idxA = find(strcmp(pairs,pid) & strcmp(conds,condA), 1);
    idxB = find(strcmp(pairs,pid) & strcmp(conds,condB), 1);
    if isempty(idxA) || isempty(idxB), continue; end
    a = metricVals(idxA); b = metricVals(idxB);
    if isfinite(a) && isfinite(b), diffs(end+1,1) = a - b; %#ok<AGROW>
    end
end
[t,p,df] = oneSampleT_vec(diffs);
end

% ---------------- CSV export ----------------
function writeCellCSV(fn, C)
fid = fopen(fn,'w');
if fid<0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

[nr,nc] = size(C);
for r=1:nr
    row = cell(1,nc);
    for c=1:nc
        v = C{r,c};
        if isnumeric(v)
            if isempty(v) || ~isfinite(v), s = ''; else, s = num2str(v); end
        else
            s = char(v);
        end
        s = strrep(s,'"','""');
        row{c} = ['"' s '"'];
    end
    fprintf(fid,'%s\n', strjoin(row,','));
end
end