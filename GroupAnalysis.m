function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m
% MATLAB 2017b + 2023b compatible
% UTF-8 / ASCII-safe source
%
% PURPOSE
%   - Organize animals / sessions into groups and conditions
%   - Run ROI timecourse analysis
%   - Run group-map analysis from exported SCM group bundles
%   - Preview results, detect outliers, and export Excel summaries
%
% INTERNAL SUBJECT TABLE LAYOUT (S.subj)
%   {1} Use
%   {2} Animal ID
%   {3} Group
%   {4} Condition
%   {5} PairID
%   {6} DataFile
%   {7} ROIFile
%   {8} BundleFile
%   {9} Status
%
% VISIBLE UITABLE COLUMNS
%   1 Use
%   2 Animal ID
%   3 Session
%   4 Scan ID
%   5 Group
%   6 Condition
%   7 ROI File
%   8 Bundle File
%   9 Status

%%% =====================================================================
%%% INPUT PARSING
%%% =====================================================================
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

if isempty(opt.startDir)
    opt.startDir = pwd;
end

if isfield(opt.studio,'exportPath') && ~isempty(opt.studio.exportPath) && exist(opt.studio.exportPath,'dir')
    opt.startDir = opt.studio.exportPath;
end

%%% =====================================================================
%%% THEME
%%% =====================================================================
C.bg     = [0.06 0.06 0.06];
C.panel  = [0.10 0.10 0.10];
C.panel2 = [0.08 0.08 0.08];
C.txt    = [0.95 0.95 0.95];
C.muted  = [0.70 0.80 0.90];
C.axisBg = [0.00 0.00 0.00];
C.editBg = [0.14 0.14 0.14];

C.btnSecondary = [0.18 0.18 0.18];
C.btnPrimary   = [0.22 0.70 0.52];
C.btnAction    = [0.25 0.55 0.95];
C.btnDanger    = [0.90 0.25 0.25];
C.btnHelp      = [0.20 0.60 0.95];

F.name  = 'Arial';
F.base  = 13;
F.small = 12;
F.big   = 16;
F.table = 12;
F.tab   = 15;

%%% =====================================================================
%%% FIGURE
%%% =====================================================================
hFig = figure( ...
    'Name','fUSI Studio - Group Analysis', ...
    'Color',C.bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[120 60 1860 980], ...
    'CloseRequestFcn',@closeMe);

set(hFig, ...
    'DefaultUicontrolFontName',F.name, ...
    'DefaultUicontrolFontSize',F.base, ...
    'DefaultUipanelFontName',F.name, ...
    'DefaultUipanelFontSize',F.base, ...
    'DefaultAxesFontName',F.name, ...
    'DefaultAxesFontSize',F.base);

%%% =====================================================================
%%% STATE
%%% =====================================================================
S = struct();
S.opt = opt;
S.C = C;
S.F = F;

S.subj = cell(0,9);
S.selectedRows = [];
S.isClosing = false;
S.lastROI = struct();
S.lastMAP = struct();
S.lastFC  = struct();
S.lastMapDisplay = struct();   % currently visible map in Group Maps tab
S.mode = 'ROI Timecourse';

% Functional Connectivity group-analysis state
S.FC = struct();
S.FC.files = {};
S.FC.subjects = struct([]);
S.FC.loaded = false;

S.fcDisplayValue = 'Pearson r';
S.fcThreshold = 0;
S.fcGroupA = 'PACAP';
S.fcGroupB = 'Vehicle';

S.groupList = {'PACAP','Vehicle','Control','GroupA','GroupB'};
S.condList  = {'CondA','CondB','Baseline','Post'};
S.defaultGroup = 'PACAP';
S.defaultCond  = 'CondA';
S.applyAllIfNoneSelected = true;
S.tableMinRows = 2;
% Fixed table widths so they do not shrink back after refreshTable()
% Use | Animal ID | Session | Scan ID | Group | Condition | ROI File | Bundle File | Status
S.tableColWidths = {38 126 56 96 94 78 78 62 112};

try
    S.groupToCondMap = containers.Map('KeyType','char','ValueType','char');
catch
    S.groupToCondMap = [];
end

S = rememberGroupCondPair(S,'PACAP','CondA');
S = rememberGroupCondPair(S,'Vehicle','CondB');
S = rememberGroupCondPair(S,'Control','CondB');
S = rememberGroupCondPair(S,'GroupA','CondA');
S = rememberGroupCondPair(S,'GroupB','CondB');

try
    S.cache.roiTC = containers.Map('KeyType','char','ValueType','any');
    S.cache.pscMap = containers.Map('KeyType','char','ValueType','any');
    S.cache.groupBundle = containers.Map('KeyType','char','ValueType','any');
    S.cache.fcBundle = containers.Map('KeyType','char','ValueType','any');
catch
    S.cache.roiTC = [];
    S.cache.pscMap = [];
    S.cache.groupBundle = [];
    S.cache.fcBundle = [];
end

%%% ROI defaults
S.tc_computePSC      = false;
S.tc_baseMin0        = 0;
S.tc_baseMin1        = 10;
S.tc_injMin0         = 5;
S.tc_injMin1         = 15;
S.tc_plateauMin0     = 30;
S.tc_plateauMin1     = 40;
S.tc_peakSearchMin0  = 10;
S.tc_peakSearchMin1  = 20;
S.tc_peakWinMin      = 3;
S.tc_trimPct         = 10;
S.tc_metric          = 'Robust Peak';
S.tc_baselineZero    = 'None';
S.tc_showSEM         = true;
S.tc_showInjectionBox = true;
S.displaySemAlpha    = 0.35;
S.exportSemAlpha     = 0.20;

%%% Group map defaults
S.baseStart = 0;
S.baseEnd   = 10;
S.sigStart  = 10;
S.sigEnd    = 30;

S.mapSummary          = 'Mean';

% Recommended default:
% use explicit global windows and PSC recomputation from exported bundle PSC
S.mapUseGlobalWindows = true;
S.mapGlobalBaseSec    = [30 240];
S.mapGlobalSigSec     = [840 900];

S.mapSource           = 'Recompute from exported PSC';
S.mapUseBundleWindows = true;
S.mapSigma            = 1;

S.mapUnderlayMode     = 'Bundle underlay';
S.mapCustomUnderlayFile = '';
S.mapLoadedUnderlay   = [];

S.rowPacapSide        = cell(0,1);
S.mapRefPacapSide     = 'Left';
S.mapPreviewRow       = NaN;

S.mapExportLog        = {'Ready.'};

S.mapThreshold       = 0;
S.mapCaxis           = [0 100];
S.mapAlphaModOn      = true;
S.mapModMin          = 10;
S.mapModMax          = 20;
S.mapBlackBody       = true;
S.mapFlipMode        = 'Off';
S.mapColormap        = 'blackbdy_iso';

%%% color/style
S.colorMode     = 'Scheme';
S.colorScheme   = 'PACAP/Vehicle';
S.manualGroupA  = 'PACAP';
S.manualGroupB  = 'Vehicle';
S.manualColorA  = 1;
S.manualColorB  = 2;

%%% plot scaling
S.plotTop = struct('auto',false,'forceZero',true,'ymin',0,'ymax',300,'step',50);
S.plotBot = struct('auto',false,'forceZero',true,'ymin',0,'ymax',300,'step',50);

%%% preview
S.previewStyle    = 'Dark';
S.previewShowGrid = false;
S.tc_previewSmooth = false;
S.tc_previewSmoothWinSec = 60;

%%% stats
S.testType  = 'Two-sample t-test (Student, equal var)';
S.alpha     = 0.05;
S.annotMode = 'Bottom only';
S.showPText = true;

%%% outliers
S.outlierMethod = 'None';
S.outMADthr     = 3.5;
S.outIQRk       = 1.5;
S.outlierKeys   = {};
S.outlierInfo   = {};

S.outDir = defaultOutDir(opt);

%%% =====================================================================
%%% LAYOUT
%%% =====================================================================
leftW = 0.46;

pLeft = uipanel(hFig, ...
    'Units','normalized', ...
    'Position',[0.02 0.05 leftW 0.93], ...
    'Title','Subjects / Groups', ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor','w', ...
    'FontSize',F.big, ...
    'FontWeight','bold');

pRight = uipanel(hFig, ...
    'Units','normalized', ...
    'Position',[0.02+leftW+0.02 0.05 0.96-(0.02+leftW+0.02) 0.93], ...
    'Title','', ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor','w', ...
    'FontSize',F.big, ...
    'FontWeight','bold');

%%% =====================================================================
%%% LEFT: MAIN TABLE
%%% =====================================================================
colNames = {'Use','Animal ID','Session','Scan ID','Group','Condition','ROI File','Bundle File','Status'};
colEdit  = [true true false false true true false false false];
colFmt   = {'logical','char','char','char',S.groupList,S.condList,'char','char','char'};

S.hTable = uitable(pLeft, ...
    'Units','normalized', ...
    'Position',[0.03 0.42 0.70 0.55], ...
    'Data',makeUITableDisplayData(S.subj, S.tableMinRows), ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'ColumnFormat',colFmt, ...
    'RowName','numbered', ...
    'BackgroundColor',buildTableRowColorsDisplay(S.subj, S.tableMinRows), ...
    'ForegroundColor',[1 1 1], ...
    'FontName','Consolas', ...
    'FontSize',F.table, ...
    'CellSelectionCallback',@onCellSelect, ...
    'CellEditCallback',@onCellEdit);

%%% =====================================================================
%%% LEFT: QUICK ASSIGN
%%% =====================================================================
pQuick = uipanel(pLeft, ...
    'Units','normalized', ...
    'Position',[0.75 0.42 0.22 0.55], ...
    'Title','Quick Assign', ...
    'BackgroundColor',C.panel2, ...
    'ForegroundColor','w', ...
    'FontSize',F.base, ...
    'FontWeight','bold');

S.hSelInfo = uicontrol(pQuick, ...
    'Style','text', ...
    'String','Selected: none', ...
    'Units','normalized', ...
    'Position',[0.05 0.93 0.90 0.05], ...
    'BackgroundColor',C.panel2, ...
    'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hApplyAllIfNone = uicontrol(pQuick, ...
    'Style','checkbox', ...
    'String','If none selected -> active USE rows', ...
    'Units','normalized', ...
    'Position',[0.05 0.87 0.90 0.05], ...
    'Value',double(S.applyAllIfNoneSelected), ...
    'BackgroundColor',C.panel2, ...
    'ForegroundColor','w', ...
    'Callback',@onApplyAllToggle);

uicontrol(pQuick,'Style','text','String','Group', ...
    'Units','normalized','Position',[0.05 0.79 0.90 0.045], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hQuickGroup = uicontrol(pQuick,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.05 0.735 0.90 0.055], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onQuickGroupChanged);

uicontrol(pQuick,'Style','text','String','Condition', ...
    'Units','normalized','Position',[0.05 0.655 0.90 0.045], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hQuickCond = uicontrol(pQuick,'Style','popupmenu','String',S.condList, ...
    'Units','normalized','Position',[0.05 0.60 0.90 0.055], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

S.hApplyGroup = mkBtn(pQuick,'Apply Group',[0.05 0.50 0.43 0.075],C.btnAction,@onApplyGroup);
S.hApplyCond  = mkBtn(pQuick,'Apply Cond',[0.52 0.50 0.43 0.075],C.btnAction,@onApplyCond);
S.hApplyBoth  = mkBtn(pQuick,'Apply Both',[0.05 0.405 0.90 0.075],C.btnPrimary,@onApplyBoth);

S.hAddGroup = mkBtn(pQuick,'Add Group',[0.05 0.305 0.43 0.070],C.btnSecondary,@onAddGroup);
S.hAddCond  = mkBtn(pQuick,'Add Cond',[0.52 0.305 0.43 0.070],C.btnSecondary,@onAddCond);

S.hRevertExcluded = mkBtn(pQuick,'Revert Excluded',[0.05 0.145 0.90 0.075],C.btnSecondary,@onRevertExcluded);
S.hHelp = [];

%%% hidden compatibility handles
S.hAutoPair = uicontrol(pQuick, ...
    'Style','checkbox', ...
    'String','Auto PairID = Subject', ...
    'Units','normalized', ...
    'Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.panel2, ...
    'ForegroundColor','w', ...
    'Value',1, ...
    'Visible','off');

S.hFillFromROI = uicontrol(pQuick, ...
    'Style','pushbutton', ...
    'String','Fill DATA from ROI folder', ...
    'Units','normalized', ...
    'Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnSecondary, ...
    'ForegroundColor','w', ...
    'Visible','off', ...
    'Callback',@onFillFromROISelected);

%%% =====================================================================
%%% LEFT: ACTION BUTTONS
%%% =====================================================================
S.hAddBundles = mkBtn(pLeft,'Add Bundles',[0.03 0.285 0.22 0.060],C.btnAction,@onAddBundles);
S.hAddFiles   = mkBtn(pLeft,'Add ROI / DATA',[0.27 0.285 0.22 0.060],C.btnSecondary,@onAddFiles);
S.hAddFolder  = mkBtn(pLeft,'Add Folder',[0.51 0.285 0.14 0.060],C.btnSecondary,@onAddFolder);
S.hRemove     = mkBtn(pLeft,'Remove Selected / USE',[0.67 0.285 0.30 0.060],C.btnDanger,@onRemoveSelected);

S.hSaveList = mkBtn(pLeft,'Save List',[0.03 0.210 0.45 0.055],C.btnSecondary,@onSaveList);
S.hLoadList = mkBtn(pLeft,'Load List',[0.52 0.210 0.45 0.055],C.btnSecondary,@onLoadList);

S.hHelp  = mkBtn(pLeft,'Help',[0.47 0.060 0.24 0.050],C.btnHelp,@onHelp);
S.hClose = mkBtn(pLeft,'Close',[0.73 0.060 0.24 0.050],C.btnDanger,@(~,~) closeMe(hFig,[]));

%%% hidden legacy controls
S.hSetData = uicontrol(pLeft,'Style','pushbutton','String','Set DATA for selected', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnAction,'ForegroundColor','w', ...
    'Visible','off','Callback',@onSetDataSelected);

S.hSetROI = uicontrol(pLeft,'Style','pushbutton','String','Set ROI for selected', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnAction,'ForegroundColor','w', ...
    'Visible','off','Callback',@onSetROISelected);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',F.base, ...
    'Visible','off','Callback',@onOutEdit);

S.hOutBrowse = uicontrol(pLeft,'Style','pushbutton','String','Browse', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w', ...
    'Visible','off','Callback',@onBrowseOut);

S.hHint = uicontrol(pLeft,'Style','text','String','', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',F.small, ...
    'Visible','off');

%%% =====================================================================
%%% RIGHT: MANUAL TABS
%%% =====================================================================
S.activeTab = 'ROI';

S.hAnalysisTitle = uicontrol(pRight,'Style','text','String','Analysis', ...
    'Units','normalized','Position',[0.02 0.965 0.18 0.025], ...
    'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'HorizontalAlignment','left', ...
    'FontSize',F.big,'FontWeight','bold');

S.hTabBar = uipanel(pRight,'Units','normalized','Position',[0.02 0.935 0.96 0.035], ...
    'BorderType','none','BackgroundColor',C.panel);

S.hTabROI   = mkTabBtn(S.hTabBar,'ROI Timecourse',      [0.000 0.05 0.175 0.90],@(s,e) onTabClicked('ROI'));
S.hTabMAP   = mkTabBtn(S.hTabBar,'Group Maps',          [0.185 0.05 0.135 0.90],@(s,e) onTabClicked('MAP'));
S.hTabFC    = mkTabBtn(S.hTabBar,'Functional Conn.',    [0.330 0.05 0.185 0.90],@(s,e) onTabClicked('FC'));
S.hTabSTATS = mkTabBtn(S.hTabBar,'Statistics / Export', [0.525 0.05 0.225 0.90],@(s,e) onTabClicked('STATS'));
S.hTabPREV  = mkTabBtn(S.hTabBar,'ROI Preview',         [0.760 0.05 0.130 0.90],@(s,e) onTabClicked('PREV'));

S.tabROI   = uipanel(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.90], ...
    'BorderType','none','BackgroundColor',C.bg);
S.tabMAP   = uipanel(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.90], ...
    'BorderType','none','BackgroundColor',C.bg,'Visible','off');
S.tabFC    = uipanel(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.90], ...
    'BorderType','none','BackgroundColor',C.bg,'Visible','off');
S.tabSTATS = uipanel(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.90], ...
    'BorderType','none','BackgroundColor',C.bg,'Visible','off');
S.tabPREV  = uipanel(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.90], ...
    'BorderType','none','BackgroundColor',C.bg,'Visible','off');

pROIBG   = uipanel(S.tabROI,  'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
pMAPBG   = uipanel(S.tabMAP,  'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
pFCBG    = uipanel(S.tabFC,   'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
pSTATSBG = uipanel(S.tabSTATS,'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
bg2 = C.panel2;

%%% =====================================================================
%%% FUNCTIONAL CONNECTIVITY TAB
%%% =====================================================================
pFCTop = uipanel(pFCBG,'Units','normalized','Position',[0.02 0.875 0.96 0.115], ...
    'Title','Functional Connectivity group analysis', ...
    'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hFCLoad = mkBtn(pFCTop,'Load FC Bundles',[0.015 0.52 0.145 0.34],C.btnAction,@onLoadFCGroupBundles);
S.hFCScan = mkBtn(pFCTop,'Scan Folder',[0.175 0.52 0.125 0.34],C.btnSecondary,@onScanFCGroupFolder);

uicontrol(pFCTop,'Style','text','String','Group A:', ...
    'Units','normalized','Position',[0.325 0.60 0.075 0.25], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hFCGroupA = uicontrol(pFCTop,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.405 0.59 0.125 0.27], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

uicontrol(pFCTop,'Style','text','String','Group B:', ...
    'Units','normalized','Position',[0.545 0.60 0.075 0.25], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hFCGroupB = uicontrol(pFCTop,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.625 0.59 0.125 0.27], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

uicontrol(pFCTop,'Style','text','String','Display:', ...
    'Units','normalized','Position',[0.765 0.60 0.065 0.25], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hFCDisplay = uicontrol(pFCTop,'Style','popupmenu','String',{'Pearson r','Fisher z'}, ...
    'Units','normalized','Position',[0.835 0.59 0.145 0.27], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

uicontrol(pFCTop,'Style','text','String','Abs threshold:', ...
    'Units','normalized','Position',[0.325 0.16 0.120 0.25], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hFCThreshold = uicontrol(pFCTop,'Style','edit','String','0', ...
    'Units','normalized','Position',[0.450 0.14 0.080 0.28], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

S.hFCCompute = mkBtn(pFCTop,'Compute Group FC',[0.560 0.10 0.170 0.36],C.btnPrimary,@onComputeGroupFC);
S.hFCExport  = mkBtn(pFCTop,'Export FC Results',[0.750 0.10 0.170 0.36],C.btnAction,@onExportGroupFC);

S.hFCInfo = uicontrol(pFCBG,'Style','text', ...
    'String','Load FC_GroupBundle_*.mat files exported from FunctionalConnectivity.m.', ...
    'Units','normalized','Position',[0.02 0.825 0.96 0.035], ...
    'BackgroundColor',C.bg,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontName','Consolas','FontSize',10);

pFCAx = uipanel(pFCBG,'Units','normalized','Position',[0.02 0.02 0.96 0.790], ...
    'Title','FC matrices', ...
    'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.axFCA = axes('Parent',pFCAx,'Units','normalized','Position',[0.060 0.565 0.365 0.360]);
S.axFCB = axes('Parent',pFCAx,'Units','normalized','Position',[0.570 0.565 0.365 0.360]);
S.axFCD = axes('Parent',pFCAx,'Units','normalized','Position',[0.060 0.090 0.365 0.360]);
S.axFCP = axes('Parent',pFCAx,'Units','normalized','Position',[0.570 0.090 0.365 0.360]);

fcNoData(S.axFCA,'Group A mean FC',C);
fcNoData(S.axFCB,'Group B mean FC',C);
fcNoData(S.axFCD,'Difference: A - B',C);
fcNoData(S.axFCP,'p-value map',C);

%%% =====================================================================
%%% ROI TAB
%%% =====================================================================


pROItop = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.92 0.96 0.07], ...
    'Title','','BorderType','none','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pROItop,'Style','text','String','Active mode:', ...
    'Units','normalized','Position',[0.02 0.15 0.18 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMode = uicontrol(pROItop,'Style','popupmenu', ...
    'String',{'ROI Timecourse','Group Maps'}, ...
    'Units','normalized','Position',[0.20 0.18 0.25 0.70], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onModeChanged);

pROI = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.60 0.96 0.30], ...
    'Title','ROI settings','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hTC_ComputePSC = uicontrol(pROI,'Style','checkbox', ...
    'String','Compute %SC from raw using baseline (ignored if ROI txt already PSC)', ...
    'Units','normalized','Position',[0.02 0.82 0.58 0.15], ...
    'Value',double(S.tc_computePSC), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Injection (min):', ...
    'Units','normalized','Position',[0.62 0.84 0.16 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hInj0 = uicontrol(pROI,'Style','edit','String',num2str(S.tc_injMin0), ...
    'Units','normalized','Position',[0.79 0.84 0.08 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

S.hInj1 = uicontrol(pROI,'Style','edit','String',num2str(S.tc_injMin1), ...
    'Units','normalized','Position',[0.88 0.84 0.08 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

[S.hBase0,S.hBase1] = addPairEditsDark(pROI,0.62,'Baseline (min):',S.tc_baseMin0,S.tc_baseMin1,C,@onROIChanged);
[S.hPkS0,S.hPkS1]   = addPairEditsDark(pROI,0.42,'Peak search (min):',S.tc_peakSearchMin0,S.tc_peakSearchMin1,C,@onROIChanged);
[S.hPlat0,S.hPlat1] = addPairEditsDark(pROI,0.22,'Plateau (min):',S.tc_plateauMin0,S.tc_plateauMin1,C,@onROIChanged);

uicontrol(pROI,'Style','text','String','Peak win (min):', ...
    'Units','normalized','Position',[0.66 0.62 0.18 0.12], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hTC_PeakWin = uicontrol(pROI,'Style','edit','String',num2str(S.tc_peakWinMin), ...
    'Units','normalized','Position',[0.84 0.62 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Trim %:', ...
    'Units','normalized','Position',[0.66 0.42 0.18 0.12], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hTC_Trim = uicontrol(pROI,'Style','edit','String',num2str(S.tc_trimPct), ...
    'Units','normalized','Position',[0.84 0.42 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Metric:', ...
    'Units','normalized','Position',[0.66 0.22 0.18 0.12], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hTC_Metric = uicontrol(pROI,'Style','popupmenu','String',{'Plateau','Robust Peak'}, ...
    'Units','normalized','Position',[0.84 0.22 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

pStyle = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.36 0.96 0.22], ...
    'Title','Display style','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStyle,'Style','text','String','Color mode:', ...
    'Units','normalized','Position',[0.02 0.70 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hColorMode = uicontrol(pStyle,'Style','popupmenu','String',{'Scheme','Manual A/B'}, ...
    'Units','normalized','Position',[0.20 0.72 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Scheme:', ...
    'Units','normalized','Position',[0.44 0.70 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hColorScheme = uicontrol(pStyle,'Style','popupmenu', ...
    'String',{'PACAP/Vehicle','Blue/Red','Purple/Green','Gray/Orange','Distinct'}, ...
    'Units','normalized','Position',[0.56 0.72 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

S.hShowSEM = uicontrol(pStyle,'Style','checkbox','String','Show SEM', ...
    'Units','normalized','Position',[0.80 0.72 0.16 0.22], ...
    'Value',double(S.tc_showSEM), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onStyleChanged);

[pNames,~] = palette20();

uicontrol(pStyle,'Style','text','String','Group A:', ...
    'Units','normalized','Position',[0.02 0.40 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hManGroupA = uicontrol(pStyle,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.20 0.42 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Color A:', ...
    'Units','normalized','Position',[0.44 0.40 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hManColorA = uicontrol(pStyle,'Style','popupmenu','String',pNames, ...
    'Units','normalized','Position',[0.56 0.42 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

S.hShowInjBox = uicontrol(pStyle,'Style','checkbox','String','Injection box', ...
    'Units','normalized','Position',[0.80 0.42 0.18 0.22], ...
    'Value',double(S.tc_showInjectionBox), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Group B:', ...
    'Units','normalized','Position',[0.02 0.10 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hManGroupB = uicontrol(pStyle,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.20 0.12 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Color B:', ...
    'Units','normalized','Position',[0.44 0.10 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hManColorB = uicontrol(pStyle,'Style','popupmenu','String',pNames, ...
    'Units','normalized','Position',[0.56 0.12 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

pY = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.02 0.96 0.32], ...
    'Title','Y-Axis Scaling','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

[S.hTopAuto,S.hTopZero,S.hTopStep,S.hTopYmin,S.hTopYmax, ...
 S.hTopYminM,S.hTopYminP,S.hTopYmaxM,S.hTopYmaxP] = mkYControlsStepCompact( ...
    pY,0.62,'Top',S.plotTop,C,@onPlotScaleChanged, ...
    @(varargin) onYStep('Top','ymin',-1), ...
    @(varargin) onYStep('Top','ymin',+1), ...
    @(varargin) onYStep('Top','ymax',-1), ...
    @(varargin) onYStep('Top','ymax',+1));

[S.hBotAuto,S.hBotZero,S.hBotStep,S.hBotYmin,S.hBotYmax, ...
 S.hBotYminM,S.hBotYminP,S.hBotYmaxM,S.hBotYmaxP] = mkYControlsStepCompact( ...
    pY,0.20,'Bottom',S.plotBot,C,@onPlotScaleChanged, ...
    @(varargin) onYStep('Bottom','ymin',-1), ...
    @(varargin) onYStep('Bottom','ymin',+1), ...
    @(varargin) onYStep('Bottom','ymax',-1), ...
    @(varargin) onYStep('Bottom','ymax',+1));

%%% =====================================================================
%%% GROUP MAPS TAB
%%% =====================================================================
pMapDisp = uipanel(pMAPBG,'Units','normalized','Position',[0.02 0.855 0.96 0.140], ...
    'Title','Render style','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

% -------------------- Row 1 --------------------
uicontrol(pMapDisp,'Style','text','String','Summary:', ...
    'Units','normalized','Position',[0.02 0.66 0.09 0.18], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapSummary = uicontrol(pMapDisp,'Style','popupmenu','String',{'Mean','Median'}, ...
    'Units','normalized','Position',[0.12 0.64 0.12 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onMapChanged);

uicontrol(pMapDisp,'Style','text','String','Source:', ...
    'Units','normalized','Position',[0.30 0.66 0.08 0.18], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapSource = uicontrol(pMapDisp,'Style','popupmenu', ...
    'String',{'Use exported SCM map','Recompute from exported PSC'}, ...
    'Units','normalized','Position',[0.39 0.64 0.30 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

% -------------------- Row 2 --------------------
uicontrol(pMapDisp,'Style','text','String','Colormap:', ...
    'Units','normalized','Position',[0.02 0.36 0.09 0.18], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapColormap = uicontrol(pMapDisp,'Style','popupmenu', ...
    'String',{'blackbdy_iso','hot','parula','turbo','jet','gray'}, ...
    'Units','normalized','Position',[0.12 0.34 0.16 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

S.hMapBlackBody = uicontrol(pMapDisp,'Style','checkbox', ...
    'String','Black body', ...
    'Units','normalized','Position',[0.31 0.34 0.12 0.20], ...
    'Value',double(S.mapBlackBody), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

uicontrol(pMapDisp,'Style','text','String','Flip mode:', ...
    'Units','normalized','Position',[0.46 0.36 0.09 0.18], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapFlipMode = uicontrol(pMapDisp,'Style','popupmenu', ...
    'String',{'Off','Flip right-injected animals','Flip left-injected animals','Align to Reference Hemisphere'}, ...
    'Units','normalized','Position',[0.56 0.34 0.40 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

% -------------------- Row 3 --------------------
uicontrol(pMapDisp,'Style','text','String','Alpha min:', ...
    'Units','normalized','Position',[0.02 0.08 0.08 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapModMin = uicontrol(pMapDisp,'Style','edit','String',num2str(S.mapModMin), ...
    'Units','normalized','Position',[0.11 0.06 0.09 0.18], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

uicontrol(pMapDisp,'Style','text','String','Alpha max:', ...
    'Units','normalized','Position',[0.23 0.08 0.08 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapModMax = uicontrol(pMapDisp,'Style','edit','String',num2str(S.mapModMax), ...
    'Units','normalized','Position',[0.32 0.06 0.09 0.18], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

uicontrol(pMapDisp,'Style','text','String','Sigma:', ...
    'Units','normalized','Position',[0.45 0.08 0.06 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapSigma = uicontrol(pMapDisp,'Style','edit','String',num2str(S.mapSigma), ...
    'Units','normalized','Position',[0.52 0.06 0.08 0.18], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

uicontrol(pMapDisp,'Style','text','String','Caxis:', ...
    'Units','normalized','Position',[0.64 0.08 0.06 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapCaxis = uicontrol(pMapDisp,'Style','edit','String',sprintf('%g %g',S.mapCaxis(1),S.mapCaxis(2)), ...
    'Units','normalized','Position',[0.71 0.06 0.14 0.18], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapDisplayChanged);

pMapPrev = uipanel(pMAPBG,'Units','normalized','Position',[0.02 0.115 0.96 0.725], ...
    'Title','Preview','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pMapPrev,'Style','text','String','Preview', ...
    'Units','normalized','Position',[0.02 0.945 0.070 0.040], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hMapPreviewPopup = uicontrol(pMapPrev,'Style','popupmenu', ...
    'String',{'No bundle rows'}, ...
    'Units','normalized','Position',[0.10 0.938 0.33 0.050], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapPreviewPopup, ...
    'UserData',[]);

S.hMapPreviewSideLabel = uicontrol(pMapPrev,'Style','text','String','Inj side:', ...
    'Units','normalized','Position',[0.46 0.945 0.08 0.040], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapPreviewSide = uicontrol(pMapPrev,'Style','popupmenu', ...
    'String',{'Unknown','Left','Right'}, ...
    'Units','normalized','Position',[0.55 0.938 0.10 0.050], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapPreviewSideChanged);

S.hMapRefSideLabel = uicontrol(pMapPrev,'Style','text','String','Ref hemi:', ...
    'Units','normalized','Position',[0.68 0.945 0.09 0.040], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapRefSide = uicontrol(pMapPrev,'Style','popupmenu', ...
    'String',{'Left','Right'}, ...
    'Units','normalized','Position',[0.79 0.938 0.11 0.050], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapRefSideChanged);

S.axMap1 = axes('Parent',pMapPrev,'Units','normalized','Position',[0.03 0.14 0.49 0.74]);
S.axMap2 = axes('Parent',pMapPrev,'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'Visible','off');

styleAxesMode(S.axMap1, 'Dark', false);
styleAxesMode(S.axMap2, 'Dark', false);
axis(S.axMap1,'off');
axis(S.axMap2,'off');

S.hMapUnderlayInfo = uicontrol(pMapPrev,'Style','text', ...
    'String','Underlay: Bundle underlay', ...
    'Units','normalized','Position',[0.03 0.055 0.58 0.030], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left', ...
    'FontSize',10);

S.hMapSideBox = uipanel(pMapPrev, ...
    'Units','normalized', ...
    'Position',[0.66 0.09 0.31 0.79], ...
    'Title','Side assignment / Map options', ...
    'BackgroundColor',bg2, ...
    'ForegroundColor','w', ...
    'FontWeight','bold');


%%% Assignment Table %%%
S.hMapAlignLabel = uicontrol(S.hMapSideBox,'Style','text', ...
    'String','Side alignment: Native sides', ...
    'Units','normalized','Position',[0.05 0.905 0.90 0.085], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapSideTable = uitable(S.hMapSideBox, ...
    'Units','normalized', ...
    'Position',[0.04 0.64 0.92 0.24], ...
    'Data',cell(0,4), ...
    'ColumnName',{'Animal','Sess','Scan','Inj Side'}, ...
    'ColumnEditable',[false false false false], ...
    'RowName',[], ...
    'BackgroundColor',[0.12 0.12 0.12; 0.10 0.10 0.10], ...
    'ForegroundColor',[1 1 1], ...
    'FontName','Consolas', ...
    'FontSize',10);

S.hMapExportTable = mkBtn(S.hMapSideBox,'Export Table',[0.24 0.55 0.52 0.075],C.btnAction,@onExportMapSideTable);

S.hMapUseGlobalWin = uicontrol(S.hMapSideBox, ...
    'Style','checkbox', ...
    'String','Use custom global baseline / signal windows', ...
    'Units','normalized', ...
    'Position',[0.05 0.47 0.90 0.05], ...
    'Value',double(S.mapUseGlobalWindows), ...
    'BackgroundColor',bg2, ...
    'ForegroundColor','w', ...
    'Callback',@onMapWindowChanged);

S.hMapRecomputeNote = uicontrol(S.hMapSideBox,'Style','text', ...
    'String',{'IMPORTANT: After changing baseline / signal', ...
              'windows, click "Compute Group Maps" again.'}, ...
    'Units','normalized','Position',[0.05 0.375 0.90 0.085], ...
    'BackgroundColor',bg2,'ForegroundColor',[1 0.35 0.35], ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',9);

uicontrol(S.hMapSideBox,'Style','text','String','Base win(s):', ...
    'Units','normalized','Position',[0.05 0.285 0.28 0.055], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapBase0 = uicontrol(S.hMapSideBox,'Style','edit', ...
    'String',num2str(S.mapGlobalBaseSec(1)), ...
    'Units','normalized','Position',[0.40 0.278 0.15 0.080], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapWindowChanged);

S.hMapBase1 = uicontrol(S.hMapSideBox,'Style','edit', ...
    'String',num2str(S.mapGlobalBaseSec(2)), ...
    'Units','normalized','Position',[0.59 0.278 0.15 0.080], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapWindowChanged);

uicontrol(S.hMapSideBox,'Style','text','String','Signal win(s):', ...
    'Units','normalized','Position',[0.05 0.175 0.28 0.055], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapSig0 = uicontrol(S.hMapSideBox,'Style','edit', ...
    'String',num2str(S.mapGlobalSigSec(1)), ...
    'Units','normalized','Position',[0.40 0.168 0.15 0.080], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapWindowChanged);

S.hMapSig1 = uicontrol(S.hMapSideBox,'Style','edit', ...
    'String',num2str(S.mapGlobalSigSec(2)), ...
    'Units','normalized','Position',[0.59 0.168 0.15 0.080], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapWindowChanged);

uicontrol(S.hMapSideBox,'Style','text','String','Underlay:', ...
    'Units','normalized','Position',[0.05 0.085 0.20 0.050], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold', ...
    'FontSize',10);

S.hMapUnderlayMode = uicontrol(S.hMapSideBox,'Style','popupmenu', ...
    'String',{'Bundle underlay','Loaded custom underlay'}, ...
    'Units','normalized','Position',[0.28 0.078 0.64 0.060], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'FontSize',9, ...
    'Callback',@onMapUnderlayModeChanged);

S.hMapLoadUnderlay = mkBtn(S.hMapSideBox,'Load Underlay',[0.22 0.010 0.56 0.060],C.btnAction,@onLoadCustomUnderlay);


pMapBottom = uipanel(pMAPBG,'Units','normalized','Position',[0.02 0.015 0.96 0.085], ...
    'Title','','BorderType','none','BackgroundColor',bg2,'ForegroundColor','w');

S.hMapPreviewSel  = mkBtn(pMapBottom,'Preview Only',[0.02 0.48 0.16 0.42],C.btnSecondary,@onPreviewSelectedBundle);
S.hMapCompute     = mkBtn(pMapBottom,'Compute Group Maps',[0.20 0.48 0.24 0.42],C.btnPrimary,@onComputeGroupMaps);
S.hMapExportData  = mkBtn(pMapBottom,'Export Group Data',[0.50 0.48 0.14 0.42],C.btnAction,@onExportGroupMapData);
S.hMapExportPNG   = mkBtn(pMapBottom,'Export PNG',[0.66 0.48 0.14 0.42],C.btnAction,@onExportGroupMapPNG);
S.hMapExportPPT   = mkBtn(pMapBottom,'Export PPT',[0.82 0.48 0.14 0.42],C.btnAction,@onExportGroupMapPPT);

S.hMapExportStatus = uicontrol(pMapBottom,'Style','text', ...
    'String','Ready.', ...
    'Units','normalized','Position',[0.02 0.06 0.96 0.18], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left', ...
    'FontName','Consolas', ...
    'FontSize',10);
%%% =====================================================================
%%% STATS TAB
%%% =====================================================================
pStats = uipanel(pSTATSBG,'Units','normalized','Position',[0.02 0.54 0.96 0.44], ...
    'Title','Metric statistics','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.02 0.72 0.12 0.20], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hTest = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','One-sample t-test (vs 0)','Two-sample t-test (Student, equal var)','Two-sample t-test (Welch)','One-way ANOVA (groups)'}, ...
    'Units','normalized','Position',[0.14 0.74 0.50 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.66 0.72 0.10 0.20], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hAlpha = uicontrol(pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.75 0.74 0.10 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Annotate:', ...
    'Units','normalized','Position',[0.02 0.52 0.12 0.14], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hAnnotMode = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','Bottom only','Both'}, ...
    'Units','normalized','Position',[0.14 0.54 0.25 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onAnnotChanged);

S.hShowPText = uicontrol(pStats,'Style','checkbox','String','Show p-value text', ...
    'Units','normalized','Position',[0.42 0.54 0.25 0.16], ...
    'Value',double(S.showPText), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onAnnotChanged);

uicontrol(pStats,'Style','text', ...
    'String','Stars: * p<0.05  ** p<0.01  *** p<0.001', ...
    'Units','normalized','Position',[0.69 0.53 0.29 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left');

pOut = uipanel(pStats,'Units','normalized','Position',[0.02 0.02 0.96 0.46], ...
    'Title','Outlier detection','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pOut,'Style','text','String','Method:', ...
    'Units','normalized','Position',[0.02 0.77 0.10 0.15], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hOutMethod = uicontrol(pOut,'Style','popupmenu','String',{'None','MAD robust z-score','IQR rule'}, ...
    'Units','normalized','Position',[0.12 0.79 0.20 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onOutlierChanged);

S.hOutParamLbl = uicontrol(pOut,'Style','text','String','Thr (z):', ...
    'Units','normalized','Position',[0.34 0.77 0.10 0.15], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hOutParam = uicontrol(pOut,'Style','edit','String',num2str(S.outMADthr), ...
    'Units','normalized','Position',[0.43 0.79 0.08 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onOutlierChanged);

S.hDetectOut  = mkBtn(pOut,'Detect',[0.53 0.79 0.11 0.16],C.btnAction,@onDetectOutliers);
S.hExcludeOut = mkBtn(pOut,'Exclude',[0.66 0.79 0.11 0.16],C.btnDanger,@onExcludeOutliers);
S.hRevertOut  = mkBtn(pOut,'Revert',[0.79 0.79 0.11 0.16],C.btnSecondary,@onRevertExcluded);

uicontrol(pOut,'Style','text', ...
    'String','Detected outliers (subject | group | condition | metric | score/range):', ...
    'Units','normalized','Position',[0.02 0.60 0.96 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hOutInfo = uicontrol(pOut,'Style','listbox', ...
    'Units','normalized','Position',[0.02 0.06 0.96 0.50], ...
    'String',{'No outliers detected yet.'}, ...
    'BackgroundColor',C.axisBg,'ForegroundColor','w', ...
    'FontName','Consolas','FontSize',11, ...
    'Min',0,'Max',2);

pRun = uipanel(pSTATSBG,'Units','normalized','Position',[0.02 0.02 0.96 0.48], ...
    'Title','Run / Export','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hRun         = mkBtn(pRun,'Run Analysis',[0.14 0.62 0.22 0.24],C.btnPrimary,@onRun);
S.hExport      = mkBtn(pRun,'Export Results',[0.39 0.62 0.22 0.24],C.btnSecondary,@onExport);
S.hExportExcel = mkBtn(pRun,'Export Excel',[0.64 0.62 0.22 0.24],C.btnAction,@onExportExcel);

S.hStatus = uicontrol(pRun,'Style','text','String','Ready.', ...
    'Units','normalized','Position',[0.04 0.10 0.92 0.36], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','center','FontSize',F.small);

%%% =====================================================================
%%% PREVIEW TAB
%%% =====================================================================
S.hPrevBG = uipanel(S.tabPREV,'Units','normalized','Position',[0 0 1 1], ...
    'BorderType','none','BackgroundColor',C.bg);

S.hPrevTop = uipanel(S.hPrevBG,'Units','normalized','Position',[0.02 0.94 0.96 0.05], ...
    'Title','','BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hPrevExportTop  = mkBtn(S.hPrevTop,'Export Top PNG',[0.02 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(1));
S.hPrevExportBot  = mkBtn(S.hPrevTop,'Export Bottom PNG',[0.18 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(2));
S.hPrevExportBoth = mkBtn(S.hPrevTop,'Export Both PNGs',[0.34 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(3));

S.hPrevLblView = uicontrol(S.hPrevTop,'Style','text','String','View:', ...
    'Units','normalized','Position',[0.52 0.15 0.05 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hPrevStyle = uicontrol(S.hPrevTop,'Style','popupmenu','String',{'Dark','Light'}, ...
    'Units','normalized','Position',[0.57 0.18 0.09 0.64], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

S.hPrevGrid = uicontrol(S.hPrevTop,'Style','checkbox','String','Grid', ...
    'Units','normalized','Position',[0.67 0.15 0.07 0.70], ...
    'Value',double(S.previewShowGrid), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

S.hSmoothEnable = uicontrol(S.hPrevTop,'Style','checkbox','String','Smoothing', ...
    'Units','normalized','Position',[0.75 0.15 0.14 0.70], ...
    'Value',double(S.tc_previewSmooth), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onSmoothChanged);

S.hPrevLblWin = uicontrol(S.hPrevTop,'Style','text','String','Win. (s):', ...
    'Units','normalized','Position',[0.89 0.15 0.08 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hSmoothWin = uicontrol(S.hPrevTop,'Style','edit','String',num2str(S.tc_previewSmoothWinSec), ...
    'Units','normalized','Position',[0.965 0.18 0.03 0.64], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onSmoothChanged);

S.ax1 = axes('Parent',S.hPrevBG,'Units','normalized','Position',[0.09 0.50 0.86 0.27]);
styleAxesMode(S.ax1, S.previewStyle, S.previewShowGrid);
recolorAxesText(S.ax1, S.previewStyle);
title(S.ax1,'Top plot','FontWeight','bold');
moveTitleUp(S.ax1,titleYForStyle(S.previewStyle));

S.ax2 = axes('Parent',S.hPrevBG,'Units','normalized','Position',[0.09 0.10 0.86 0.27]);
styleAxesMode(S.ax2, S.previewStyle, S.previewShowGrid);
recolorAxesText(S.ax2, S.previewStyle);
title(S.ax2,'Bottom plot','FontWeight','bold');
moveTitleUp(S.ax2,titleYForStyle(S.previewStyle));

fixAxesInset(S.ax1);
fixAxesInset(S.ax2);

%%% =====================================================================
%%% INITIALIZATION
%%% =====================================================================
guidata(hFig,S);
S = guidata(hFig);

stylePreviewPanels(S);
% syncUIFromState();   % removed - function is missing
updateMapGroupSideLabels();
updateManualTabs();
refreshTable();
clearPreview();
updateOutlierBox();
updateMapAlignmentLabel();
updateMapUnderlayInfoLabel();
updateMapSideSummaryTable();
drawnow;
pause(0.05);
applyDarkUITableViewport(S.hTable, C);

setStatus(false);
setStatusText('Ready. Preview redraw is clean and cached computations are enabled.');

%%% =====================================================================
%%% NESTED CALLBACKS
%%% =====================================================================
  function onExportGroupMapData(~,~)
    S0 = guidata(hFig);

    [mapIdx,~] = findActiveBundleRowsGA(S0);
    if isempty(mapIdx)
        errordlg('No valid bundle rows available for export.','Export Group Data');
        return;
    end

    startDir = getAnalysedBrowseDir(S0);
    defName  = ['GA_GroupVideoExport_' datestr(now,'yyyymmdd_HHMMSS') '.mat'];

    [f,p] = uiputfile({'*.mat','MAT-file (*.mat)'}, ...
        'Save Group Analysis Video Export', ...
        fullfile(startDir, defName));

    if isequal(f,0)
        return;
    end

    outFile = fullfile(p,f);

    setStatus(false);
    setStatusText('Exporting group-analysis video bundle...');
    drawnow;

    try
        E = buildGroupAnalysisVideoExportGA(S0, mapIdx);
        GA = E;
underlay2D  = E.underlay2D;
brainImage  = E.underlay2D;
overlay2D   = E.overlay2D;
groupMap2D  = E.groupMap2D;
functional4D = E.functional4D;
psc4D       = E.psc4D;

save(outFile, ...
    'E','GA', ...
    'underlay2D','brainImage', ...
    'overlay2D','groupMap2D', ...
    'functional4D','psc4D', ...
    '-v7.3');

        S0.opt.startDir = p;
        guidata(hFig,S0);

        setStatusText(['Group-analysis video bundle saved: ' outFile]);
    catch ME
        setStatusText(['Group-analysis video export failed: ' ME.message]);
        errordlg(ME.message,'Export Group Data');
    end

    setStatus(true);
end
    
    
    function D = buildGroupMapDisplayStructGA(S0, R)
    dispUnderlay = R.commonUnderlay;

    if strcmpi(S0.mapUnderlayMode,'Loaded custom underlay') && ~isempty(S0.mapLoadedUnderlay)
        dispUnderlay = matchUnderlayToMap2D(S0.mapLoadedUnderlay, R.groupMap);
    else
        dispUnderlay = matchUnderlayToMap2D(dispUnderlay, R.groupMap);
    end

    if strcmpi(strtrimSafe(R.mapSummary),'Median')
        ttl = sprintf('Group median map (n=%d)', R.n);
    else
        ttl = sprintf('Group mean map (n=%d)', R.n);
    end

    D = struct();
    D.map      = R.groupMap;
    D.underlay = dispUnderlay;
    D.title    = ttl;
    D.render   = makeMapRenderStruct(S0);
end

function [D, S0] = computeCurrentGroupMapDisplayGA(S0, forceRecompute)
    if nargin < 2
        forceRecompute = false;
    end

    needRecompute = forceRecompute;

    if ~isfield(S0,'lastMAP') || isempty(fieldnames(S0.lastMAP))
        needRecompute = true;
    end

    if ~needRecompute
        if S0.mapUseGlobalWindows || strcmpi(S0.mapSource,'Recompute from exported PSC')
            needRecompute = true;
        end
    end

    if needRecompute
        [mapIdx, mapMissingIdx] = findActiveBundleRowsGA(S0); %#ok<ASGLU>

        if isempty(mapIdx)
            error('No valid bundle rows available for group-map export.');
        end

        subjActive = S0.subj(mapIdx,:);
        [Rtmp, cacheOut] = runPSCMapAnalysis(S0, subjActive, mapIdx, S0.cache);

        S0.cache   = cacheOut;
        S0.lastMAP = Rtmp;
        guidata(hFig,S0);
    else
        Rtmp = S0.lastMAP;
    end

    D = buildGroupMapDisplayStructGA(S0, Rtmp);
end
    
    function pushMapExportLog(msg, doReset)
    if nargin < 2
        doReset = false;
    end

    S0 = guidata(hFig);

    msg = strtrimSafe(msg);
    if isempty(msg)
        return;
    end

    if isfield(S0,'hMapExportStatus') && ishghandle(S0.hMapExportStatus)
        try
            set(S0.hMapExportStatus,'String',msg);
        catch
        end
    end

    guidata(hFig,S0);
    drawnow limitrate;
end
    
    function onMapWindowChanged(~,~)
    S0 = guidata(hFig);

    S0.mapUseGlobalWindows = logical(get(S0.hMapUseGlobalWin,'Value'));

    b0 = safeNum(get(S0.hMapBase0,'String'), S0.mapGlobalBaseSec(1));
    b1 = safeNum(get(S0.hMapBase1,'String'), S0.mapGlobalBaseSec(2));
    s0 = safeNum(get(S0.hMapSig0,'String'),  S0.mapGlobalSigSec(1));
    s1 = safeNum(get(S0.hMapSig1,'String'),  S0.mapGlobalSigSec(2));

    if b1 <= b0
        b1 = b0 + 1;
        set(S0.hMapBase1,'String',num2str(b1));
    end
    if s1 <= s0
        s1 = s0 + 1;
        set(S0.hMapSig1,'String',num2str(s1));
    end

    S0.mapGlobalBaseSec = [b0 b1];
    S0.mapGlobalSigSec  = [s0 s1];

    guidata(hFig,S0);

    % Update selected-row preview immediately
    if isfinite(S0.mapPreviewRow)
        try
            previewBundleRow(S0.mapPreviewRow);
        catch
        end
    end

    % Do NOT silently fake a new group computation
    if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
        setStatusText('Selected preview updated. Click "Compute Group Maps" to rebuild the group map with the new windows.');
    else
        setStatusText(sprintf('Preview windows set: baseline %.0f-%.0fs, signal %.0f-%.0fs.', b0,b1,s0,s1));
    end
end

    function onMapUnderlayModeChanged(~,~)
    S0 = guidata(hFig);

    items = get(S0.hMapUnderlayMode,'String');
    S0.mapUnderlayMode = items{get(S0.hMapUnderlayMode,'Value')};
    guidata(hFig,S0);
    updateMapUnderlayInfoLabel();

    % Redraw current single preview immediately
    if isfinite(S0.mapPreviewRow)
        try
            previewBundleRow(S0.mapPreviewRow);
        catch
        end
    end

    % Group map itself does not need recomputation for underlay-only changes
    if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
        updateMapTabPreview();
    end

    setStatusText(['Underlay mode: ' S0.mapUnderlayMode]);
    end

    function onLoadCustomUnderlay(~,~)
    S0 = guidata(hFig);

    startDir = getSmartBrowseDir(S0,'add');
    [f,p] = uigetfile({'*.mat;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp', ...
        'Underlay files (*.mat,*.png,*.jpg,*.jpeg,*.tif,*.tiff,*.bmp)'}, ...
        'Select custom underlay', startDir);

    if isequal(f,0)
        return;
    end

    fp = fullfile(p,f);

    try
        U = loadGroupUnderlayFile(fp);
        S0.mapLoadedUnderlay = U;
        S0.mapCustomUnderlayFile = fp;
        S0.mapUnderlayMode = 'Loaded custom underlay';

        guidata(hFig,S0);

        try
            setPopupToString(S0.hMapUnderlayMode,'Loaded custom underlay');
        catch
        end
        updateMapUnderlayInfoLabel();

        % Immediate redraw of selected bundle preview
        if isfinite(S0.mapPreviewRow)
            try
                previewBundleRow(S0.mapPreviewRow);
            catch
            end
        end

        % Immediate redraw of already computed group display
        if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
            updateMapTabPreview();
        end

        setStatusText(['Custom underlay loaded: ' shortPathForTable(fp,40)]);
    catch ME
        errordlg(ME.message,'Load custom underlay');
        setStatusText(['Custom underlay load failed: ' ME.message]);
    end
    end

    function closeMe(src,~)
        S0 = guidata(src);
        if isempty(S0)
            delete(src);
            return;
        end
        if isfield(S0,'isClosing') && S0.isClosing
            delete(src);
            return;
        end
        S0.isClosing = true;
        guidata(src,S0);
        try, setStatus(true); catch, end
        if isfield(S0.opt,'onClose') && ~isempty(S0.opt.onClose)
            try
                S0.opt.onClose();
            catch
            end
        end
        delete(src);
    end

    function onCellSelect(~,evt)
        S0 = guidata(hFig);
        if isempty(evt) || ~isfield(evt,'Indices') || isempty(evt.Indices)
            S0.selectedRows = [];
        else
            S0.selectedRows = unique(evt.Indices(:,1));
        end
        guidata(hFig,S0);
        updateSelLabel();
    end

    function onCellEdit(~,evt)
        S0 = guidata(hFig);

        try
            if ~isempty(evt) && isfield(evt,'Indices') && ~isempty(evt.Indices)
                S0.selectedRows = unique(evt.Indices(:,1));
                guidata(hFig,S0);
            end
        catch
        end

        syncSubjFromTable();
        S0 = guidata(hFig);

        try
            if ~isempty(evt) && isfield(evt,'Indices') && numel(evt.Indices) >= 2
                r = evt.Indices(1);
                c = evt.Indices(2);

                % Visible table columns:
                % 1 Use | 2 Animal | 3 Session | 4 Scan | 5 Group | 6 Condition | 7 ROI | 8 Bundle | 9 Status
                %
                % Internal S.subj columns:
                % 1 Use | 2 Animal | 3 Group | 4 Condition | 5 PairID | 6 Data | 7 ROI | 8 Bundle | 9 Status

                if r >= 1 && r <= size(S0.subj,1)
                    if c == 5
                        gNow = strtrimSafe(S0.subj{r,3});
                        cAuto = mapConditionFromGroup(S0, gNow);
                        if ~isempty(cAuto)
                            S0.subj{r,4} = cAuto;
                        end

                    elseif c == 6
                        gNow = strtrimSafe(S0.subj{r,3});
                        cNow = strtrimSafe(S0.subj{r,4});
                        S0 = rememberGroupCondPair(S0, gNow, cNow);
                    end
                end
            end
        catch
        end

        S0 = sanitizeTableStruct(S0);
        S0.groupList = mergeUniqueStable(S0.groupList, uniqueStable(colAsStr(S0.subj,3)));
        S0.condList  = mergeUniqueStable(S0.condList,  uniqueStable(colAsStr(S0.subj,4)));
        guidata(hFig,S0);
        refreshTable();
    end

    function onQuickGroupChanged(src,~)
    S0 = guidata(hFig);
    g = getSelectedPopupString(src);
    c = mapConditionFromGroup(S0, g);
    if ~isempty(c)
        setPopupToString(S0.hQuickCond, c);
    end
    guidata(hFig,S0);

    updateMapGroupSideLabels();
    try, updateMapSideSummaryTable(); catch, end
end

    function onComputeGroupMaps(~,~)
        S0 = guidata(hFig);
        S0.activeTab = 'MAP';
        S0.mode = 'Group Maps';
        guidata(hFig,S0);

        updateManualTabs();
        try, set(S0.hMode,'Value',2); catch, end

        setStatusText('Computing group maps... please wait.');
        drawnow;

        onRun([],[]);
    end

    function onApplyAllToggle(src,~)
        S0 = guidata(hFig);
        S0.applyAllIfNoneSelected = logical(get(src,'Value'));
        guidata(hFig,S0);
    end

    function rows = getTargetRows()
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if ~isempty(sel)
            rows = sel;
            return;
        end
        if S0.applyAllIfNoneSelected
            rows = find(logicalCol(S0.subj,1));
        else
            rows = [];
        end
    end

    function onPreviewSelectedBundle(~,~)
    S0 = guidata(hFig);

    sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
    r = [];

    if ~isempty(sel)
        r = resolvePreviewRowFromSelection(S0, sel(1));
    elseif isfinite(S0.mapPreviewRow)
        r = S0.mapPreviewRow;
    end

    if isempty(r) || ~isfinite(r)
        errordlg('Select one row first or choose one in the preview dropdown.','Group Maps');
        return;
    end

    previewBundleRow(r);
    refreshMapBundlePopup();
end

    function onMapPreviewPopup(src,~)
        S0 = guidata(hFig);
        rows = get(src,'UserData');
        if isempty(rows) || ~all(isfinite(rows))
            return;
        end
        v = get(src,'Value');
        v = max(1,min(numel(rows),v));
        r = rows(v);

        S0.mapPreviewRow = r;
        guidata(hFig,S0);

        syncMapPreviewSideUI(r);
        previewBundleRow(r);
    end

    function onMapPreviewSideChanged(src,~)
    S0 = guidata(hFig);
    S0 = ensureRowPacapSideSize(S0);

    r = S0.mapPreviewRow;
    if isempty(r) || ~isfinite(r) || r < 1 || r > size(S0.subj,1)
        return;
    end

    items = get(src,'String');
    newSide = items{get(src,'Value')};

    refMeta   = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});
    refBundle = strtrimSafe(S0.subj{r,8});

    nApplied = 0;
    for rr = 1:size(S0.subj,1)
        rrMeta   = extractMetaFromSources(S0.subj{rr,2}, S0.subj{rr,6}, S0.subj{rr,7}, S0.subj{rr,8});
        rrBundle = strtrimSafe(S0.subj{rr,8});

        sameMeta = strcmpi(strtrimSafe(rrMeta.animalID), strtrimSafe(refMeta.animalID)) && ...
                   metaLooseFieldMatch(rrMeta.session, refMeta.session) && ...
                   metaLooseFieldMatch(rrMeta.scanID,  refMeta.scanID);

        sameBundle = ~isempty(refBundle) && ~isempty(rrBundle) && strcmpi(refBundle, rrBundle);

        if sameMeta || sameBundle
            S0.rowPacapSide{rr} = newSide;
            nApplied = nApplied + 1;
        end
    end

    guidata(hFig,S0);
    refreshMapBundlePopup();
    previewBundleRow(r);
    updateMapSideSummaryTable();
updateMapAlignmentLabel();
setStatusText(sprintf('%s side "%s" applied to %d matching row(s).', getMapInjectedGroupLabel(S0), newSide, nApplied));
end

    function S0 = ensureRowPacapSideSize(S0)
        n = size(S0.subj,1);

        if ~isfield(S0,'rowPacapSide') || isempty(S0.rowPacapSide)
            S0.rowPacapSide = repmat({'Unknown'}, n, 1);
        end

        if numel(S0.rowPacapSide) < n
            S0.rowPacapSide(end+1:n,1) = {'Unknown'};
        elseif numel(S0.rowPacapSide) > n
            S0.rowPacapSide = S0.rowPacapSide(1:n);
        end

        for ii = 1:n
            s = strtrimSafe(S0.rowPacapSide{ii});
            if strcmpi(s,'L'), s = 'Left'; end
            if strcmpi(s,'R'), s = 'Right'; end
            if isempty(s), s = 'Unknown'; end
            if ~any(strcmpi(s,{'Unknown','Left','Right'}))
                s = 'Unknown';
            end
            S0.rowPacapSide{ii} = s;
        end
    end

    function syncMapPreviewSideUI(r)
        S0 = guidata(hFig);
        S0 = ensureRowPacapSideSize(S0);
        guidata(hFig,S0);

        if isempty(r) || ~isfinite(r) || r < 1 || r > numel(S0.rowPacapSide)
            return;
        end
        setPopupToString(S0.hMapPreviewSide, S0.rowPacapSide{r});
    end

   function refreshMapBundlePopup()
    S0 = guidata(hFig);
    S0 = ensureRowPacapSideSize(S0);

    rows = findBundleDisplayRowsGA(S0);
    labels = {};

    if isempty(rows)
        labels = {'No bundle rows'};
        rows = NaN;
    else
        for i = 1:numel(rows)
            r = rows(i);
            info = extractRowMetaLight(S0.subj(r,:));
            labels{end+1} = sprintf('Row %d | %s', ...
                r, makeBundleDisplayTitle(info.animalID, info.session, info.scanID)); %#ok<AGROW>
        end
    end

    set(S0.hMapPreviewPopup,'String',labels,'UserData',rows);

    if isempty(S0.mapPreviewRow) || ~isfinite(S0.mapPreviewRow) || ~any(rows == S0.mapPreviewRow)
        if all(isfinite(rows))
            S0.mapPreviewRow = rows(1);
        else
            S0.mapPreviewRow = NaN;
        end
    end

    if all(isfinite(rows))
        v = find(rows == S0.mapPreviewRow, 1, 'first');
        if isempty(v), v = 1; end
        set(S0.hMapPreviewPopup,'Value',v);
        syncMapPreviewSideUI(S0.mapPreviewRow);
    end

    guidata(hFig,S0);
end

    function previewBundleRow(r)
    S0 = guidata(hFig);

    if isempty(r) || ~isfinite(r) || r < 1 || r > size(S0.subj,1)
        return;
    end

    S0.activeTab = 'MAP';
    S0.mode = 'Group Maps';
    S0.mapPreviewRow = r;
    guidata(hFig,S0);

    updateManualTabs();
    try, set(S0.hMode,'Value',2); catch, end

    bundleFile = strtrimSafe(S0.subj{r,8});
    if isempty(bundleFile)
        bundleFile = resolveGroupBundlePath(S0, S0.subj(r,:));
    end

    setStatusText(sprintf('Loading bundle preview (row %d)...', r));
    drawnow;

    try
        [G, cacheOut] = getCachedGroupBundle(S0.cache, bundleFile);
        S0.cache = cacheOut;
        guidata(hFig,S0);

        % --- IMPORTANT: preview must respect source/global-window settings
        [mapNow, winInfoTxt] = buildPreviewMapFromBundle(S0, G);

        % --- IMPORTANT: preview underlay must use best bundle field or custom underlay
        underlayNow = resolvePreviewUnderlay(S0, G, mapNow);

        try, deleteAllColorbars(S0.tabMAP); catch, end
        cla(S0.axMap1);
        cla(S0.axMap2);

        layoutMapPreviewMain(S0);

        mapStyle = 'Dark';
        [~,fg] = previewColors(mapStyle);

        renderPSCOverlay(S0.axMap1, underlayNow, mapNow, makeMapRenderStruct(S0), mapStyle, false);
        recolorAxesText(S0.axMap1, mapStyle);
        updateMapAlignmentLabel();
        updateMapSideSummaryTable();

        info = extractRowMetaLight(S0.subj(r,:));

        animalTxt = strtrimSafe(info.animalID);
        sessTxt   = strtrimSafe(info.session);
        scanTxt   = displayScanID(info.scanID);

        if isempty(animalTxt) || strcmpi(animalTxt,'N/A')
            animalTxt = strtrimSafe(G.animalID);
        end
        if isempty(sessTxt) || strcmpi(sessTxt,'N/A')
            sessTxt = strtrimSafe(G.session);
        end
        if isempty(scanTxt) || strcmpi(scanTxt,'N/A')
            scanTxt = displayScanID(strtrimSafe(G.scanID));
        end

        mapTitle = makeBundleDisplayTitle(animalTxt, sessTxt, scanTxt);
       % keep title clean; window info is no longer appended above the image
% if ~isempty(winInfoTxt)
%     mapTitle = sprintf('%s | %s', mapTitle, winInfoTxt);
% end

        title(S0.axMap1, mapTitle, ...
            'Color',fg,'FontWeight','bold');

       placeSingleMapColorbar(S0.axMap1);
        S0.lastMapDisplay = struct();
        S0.lastMapDisplay.map = mapNow;
        S0.lastMapDisplay.underlay = underlayNow;
        S0.lastMapDisplay.title = mapTitle;
        S0.lastMapDisplay.render = makeMapRenderStruct(S0);
        guidata(hFig,S0);

        setStatusText('Selected bundle preview updated.');
    catch ME
        setStatusText(['Bundle preview failed: ' ME.message]);
        errordlg(ME.message,'Bundle preview failed');
    end
end

   function onMapRefSideChanged(src,~)
    S0 = guidata(hFig);
    items = get(src,'String');
    S0.mapRefPacapSide = items{get(src,'Value')};
    guidata(hFig,S0);

    updateMapAlignmentLabel();
    updateMapSideSummaryTable();

    if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
        updateMapTabPreview();
    end
end

 function updateMapTabPreview()
    S0 = guidata(hFig);

    if ~isfield(S0,'lastMAP') || isempty(fieldnames(S0.lastMAP))
        return;
    end

    R = S0.lastMAP;
    if ~strcmpi(R.mode,'Group Maps')
        return;
    end

    try, deleteAllColorbars(S0.tabMAP); catch, end

    mapStyle = 'Dark';
    [~,fg] = previewColors(mapStyle);

    cla(S0.axMap1);
    cla(S0.axMap2);
    layoutMapPreviewMain(S0);

    D = buildGroupMapDisplayStructGA(S0, R);

    renderPSCOverlay(S0.axMap1, D.underlay, D.map, D.render, mapStyle, false);
    recolorAxesText(S0.axMap1, mapStyle);
    title(S0.axMap1, D.title, 'Color', fg, 'FontWeight','bold');
    placeSingleMapColorbar(S0.axMap1);

    S0.lastMapDisplay = D;
    guidata(hFig,S0);

    updateMapAlignmentLabel();
    updateMapSideSummaryTable();
end

    function onApplyGroup(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows)
            setStatusText('No rows selected.');
            return;
        end

        g = getSelectedPopupString(S0.hQuickGroup);
        c = getSelectedPopupString(S0.hQuickCond);

        S0 = rememberGroupCondPair(S0, g, c);

        for r = rows(:)'
            S0.subj{r,3} = g;
            cAuto = mapConditionFromGroup(S0, g);
            if ~isempty(cAuto)
                S0.subj{r,4} = cAuto;
            end
        end

        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Applied Group "%s" and synced Condition for %d row(s).', g, numel(rows)));
    end

    function onApplyCond(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows)
            setStatusText('No rows selected.');
            return;
        end

        g = getSelectedPopupString(S0.hQuickGroup);
        c = getSelectedPopupString(S0.hQuickCond);

        S0 = rememberGroupCondPair(S0, g, c);

        for r = rows(:)'
            S0.subj{r,4} = c;
        end

        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Applied Condition "%s" to %d row(s).', c, numel(rows)));
    end

    function onApplyBoth(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows)
            setStatusText('No rows selected.');
            return;
        end

        g = getSelectedPopupString(S0.hQuickGroup);
        c = getSelectedPopupString(S0.hQuickCond);

        S0 = rememberGroupCondPair(S0, g, c);

        for r = rows(:)'
            S0.subj{r,3} = g;
            S0.subj{r,4} = c;
        end

        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Applied Group "%s" and Condition "%s" to %d row(s).', g, c, numel(rows)));
    end

    function onAddGroup(~,~)
        S0 = guidata(hFig);
        answ = inputdlg({'New group name:'},'Add group',1,{''});
        if isempty(answ), return; end
        nm = strtrim(answ{1});
        if isempty(nm), return; end
        S0.groupList = mergeUniqueStable(S0.groupList,{nm});
        guidata(hFig,S0);
        refreshTable();
        setStatusText(['Added group: ' nm]);
    end

    function onAddCond(~,~)
        S0 = guidata(hFig);
        answ = inputdlg({'New condition name:'},'Add condition',1,{''});
        if isempty(answ), return; end
        nm = strtrim(answ{1});
        if isempty(nm), return; end
        S0.condList = mergeUniqueStable(S0.condList,{nm});
        guidata(hFig,S0);
        refreshTable();
        setStatusText(['Added condition: ' nm]);
    end

    function onHelp(~,~)
        txt = sprintf([ ...
            'GROUP ANALYSIS GUIDE\n\n' ...
            'What this GUI is for:\n' ...
            'This window lets you organize animals into groups and conditions, run ROI timecourse or Group Map analysis, inspect group-level trends, detect outliers, and export a clean Excel overview for record keeping and publication decisions.\n\n' ...
            'Typical workflow:\n' ...
            '1. Add Files, Add Bundles, or Add Folder.\n' ...
            '2. Check that Animal ID, Group, Condition, ROI File, and Status look correct.\n' ...
            '3. Use Quick Assign to batch-set Group and Condition.\n' ...
            '4. In ROI Timecourse, define baseline, peak-search, plateau, and metric settings.\n' ...
            '5. In Stats, choose your statistical test and optional outlier detection.\n' ...
            '6. Click Run Analysis.\n' ...
            '7. Inspect Preview plots and outlier markings.\n' ...
            '8. Export results or Excel summary.\n\n' ...
            'Key notes:\n' ...
            '- Subject is treated as Animal ID and is extracted from the folder/path when possible.\n' ...
            '- Green rows indicate usable rows with a valid ROI file or bundle.\n' ...
            '- Red rows indicate excluded or inactive rows.\n' ...
            '- ROI txt PSC exports are plotted directly.\n' ...
            '- If raw ROI data are used, percent signal change can be computed from the chosen baseline.\n' ...
            '- Temporal smoothing in Preview affects only display, not the stored analysis result.\n\n' ...
            'Outliers:\n' ...
            '- MAD robust z-score flags values far from the median using MAD-based scaling.\n' ...
            '- IQR rule flags values outside the [Q1-k*IQR, Q3+k*IQR] range.\n' ...
            '- Excluding outliers disables those rows for the next analysis run.\n\n' ...
            'Exports:\n' ...
            '- Export Results saves the current result structure and metrics table.\n' ...
            '- Export Excel writes a workbook with metadata, per-condition sheets, and outlier audit information.\n' ...
            ]);

        d = dialog('Name','Group Analysis Help', ...
            'Position',[300 150 760 560], ...
            'Color',[0.08 0.08 0.08], ...
            'WindowStyle','normal');

        uicontrol(d,'Style','edit', ...
            'Units','normalized','Position',[0.04 0.12 0.92 0.83], ...
            'Max',2,'Min',0, ...
            'Enable','inactive', ...
            'HorizontalAlignment','left', ...
            'FontName','Consolas','FontSize',11, ...
            'BackgroundColor',[0.12 0.12 0.12], ...
            'ForegroundColor',[1 1 1], ...
            'String',txt);

        uicontrol(d,'Style','pushbutton','String','Close', ...
            'Units','normalized','Position',[0.40 0.03 0.20 0.06], ...
            'BackgroundColor',[0.20 0.20 0.20], ...
            'ForegroundColor',[1 1 1], ...
            'FontWeight','bold', ...
            'Callback',@(src,evt) delete(d));
    end

    function onAddFiles(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);

        startPath = getSmartBrowseDir(S0, 'add');
        if ~exist(startPath,'dir')
            startPath = pwd;
        end

        [f,p] = uigetfile({'*.mat;*.txt','MAT or TXT (*.mat, *.txt)'}, ...
            'Select DATA (.mat) and/or ROI (.txt/.mat) files', ...
            startPath, 'MultiSelect','on');

        if isequal(f,0)
            return;
        end
        if ischar(f)
            f = {f};
        end

        S0.opt.startDir = p;
        guidata(hFig,S0);

        for i = 1:numel(f)
            addFileSmart(fullfile(p,f{i}));
        end

        refreshTable();
        setStatusText(sprintf('Added %d file(s).', numel(f)));
    end

   function onAddBundles(~,~)
    syncSubjFromTable();
    S0 = guidata(hFig);

    startPath = getBundleBrowseDir(S0);
    if ~exist(startPath,'dir')
        startPath = getSmartBrowseDir(S0, 'add');
    end
    if ~exist(startPath,'dir')
        startPath = pwd;
    end

    [f,p] = uigetfile({'*.mat','SCM Group bundle MAT (*.mat)'}, ...
        'Select SCM Group bundle MAT files', ...
        startPath, 'MultiSelect','on');

    if isequal(f,0)
        return;
    end
    if ischar(f)
        f = {f};
    end

    sel = clampSelRows(S0.selectedRows, size(S0.subj,1));

    if ~isempty(sel)
        nDirect = min(numel(sel), numel(f));

        for ii = 1:nDirect
            fpNow = fullfile(p, f{ii});
            S0 = assignBundleToExplicitRow(S0, sel(ii), fpNow);
        end

        for ii = (nDirect+1):numel(f)
            fpNow = fullfile(p, f{ii});
            S0 = addBundleFileSmartLight(S0, fpNow);
        end

        msgTail = sprintf('%d selected row(s) assigned directly', nDirect);
    else
        for ii = 1:numel(f)
            fpNow = fullfile(p, f{ii});
            S0 = addBundleFileSmartLight(S0, fpNow);
        end
        msgTail = 'no explicit selection, used lightweight smart matching';
    end

    % IMPORTANT: sanitize only once
    S0 = sanitizeTableStruct(S0);
    S0 = ensureRowPacapSideSize(S0);
    S0.opt.startDir = p;

    guidata(hFig,S0);

    refreshTable();
    setStatusText(sprintf('Added %d bundle file(s) (%s).', numel(f), msgTail));
end

    function S0 = assignBundleToExplicitRow(S0, r, fp)
    if isempty(r) || r < 1 || r > size(S0.subj,1)
        return;
    end

    metaIn = extractMetaFromSources('', '', '', fp);

    S0.subj{r,8} = fp;
    S0.subj{r,1} = true;

    if isempty(strtrimSafe(S0.subj{r,2})) || strcmpi(strtrimSafe(S0.subj{r,2}),'N/A')
        if ~strcmpi(strtrimSafe(metaIn.animalID),'N/A')
            S0.subj{r,2} = strtrimSafe(metaIn.animalID);
        end
    end

    if get(S0.hAutoPair,'Value')==1 && isempty(strtrimSafe(S0.subj{r,5}))
        S0.subj{r,5} = strtrimSafe(S0.subj{r,2});
    end

    if isempty(strtrimSafe(S0.subj{r,3}))
        S0.subj{r,3} = S0.defaultGroup;
    end
    if isempty(strtrimSafe(S0.subj{r,4}))
        S0.subj{r,4} = S0.defaultCond;
    end

    st = lower(strtrimSafe(S0.subj{r,9}));
    if contains(st,'excluded') || contains(st,'not used') || contains(st,'missing') || contains(st,'not set')
        S0.subj{r,9} = '';
    end
end

function S0 = addBundleFileSmartLight(S0, fp)
    % IMPORTANT:
    % This function does NOT load the MAT file.
    % It only uses filename/path metadata and assigns the bundle path.

    metaIn = extractMetaFromSources('', '', '', fp);

    subj = strtrimSafe(metaIn.animalID);
    if isempty(subj) || strcmpi(subj,'N/A')
        subj = guessSubjectID(fp);
    end

    gdef = getSelectedPopupString(S0.hQuickGroup);
    cdef = getSelectedPopupString(S0.hQuickCond);
    if isempty(gdef), gdef = S0.defaultGroup; end
    if isempty(cdef), cdef = S0.defaultCond;  end

    rowIdx      = findSingleBundleTargetRow(S0, metaIn);
    templateIdx = findTemplateRowByMeta(S0, metaIn);

    if isempty(rowIdx)
        newRow = makeEmptyGARow(subj, gdef, cdef, S0);

        if ~isempty(templateIdx)
            if ~isempty(strtrimSafe(S0.subj{templateIdx,3})), newRow{3} = strtrimSafe(S0.subj{templateIdx,3}); end
            if ~isempty(strtrimSafe(S0.subj{templateIdx,4})), newRow{4} = strtrimSafe(S0.subj{templateIdx,4}); end
            if ~isempty(strtrimSafe(S0.subj{templateIdx,6})), newRow{6} = strtrimSafe(S0.subj{templateIdx,6}); end
            if ~isempty(strtrimSafe(S0.subj{templateIdx,7})), newRow{7} = strtrimSafe(S0.subj{templateIdx,7}); end
        end

        newRow{8} = fp;
        S0.subj(end+1,:) = newRow;

    else
        S0.subj{rowIdx,8} = fp;
        S0.subj{rowIdx,1} = true;

        if isempty(strtrimSafe(S0.subj{rowIdx,2})) || strcmpi(strtrimSafe(S0.subj{rowIdx,2}),'N/A')
            if ~isempty(subj) && ~strcmpi(subj,'N/A')
                S0.subj{rowIdx,2} = subj;
            end
        end

        if get(S0.hAutoPair,'Value') == 1 && isempty(strtrimSafe(S0.subj{rowIdx,5}))
            S0.subj{rowIdx,5} = strtrimSafe(S0.subj{rowIdx,2});
        end

        if isempty(strtrimSafe(S0.subj{rowIdx,3}))
            S0.subj{rowIdx,3} = gdef;
        end
        if isempty(strtrimSafe(S0.subj{rowIdx,4}))
            S0.subj{rowIdx,4} = cdef;
        end
    end
end


    function onAddFolder(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        startPath = getSmartBrowseDir(S0, 'add');
        if ~exist(startPath,'dir')
            startPath = pwd;
        end
        folder = uigetdir(startPath,'Select a folder to scan for .mat and .txt files');
        if isequal(folder,0), return; end

        dm = dir(fullfile(folder,'*.mat'));
        dt = dir(fullfile(folder,'*.txt'));

        for i = 1:numel(dm)
            addFileSmart(fullfile(dm(i).folder, dm(i).name));
        end
        for i = 1:numel(dt)
            addFileSmart(fullfile(dt(i).folder, dt(i).name));
        end

        refreshTable();
        setStatusText(sprintf('Scanned folder. Added %d file(s).', numel(dm)+numel(dt)));
    end

    function onRemoveSelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);

        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel)
            sel = find(logicalCol(S0.subj,1));
        end

        if isempty(sel)
            setStatusText('No rows selected. Click a row or tick USE.');
            return;
        end

        S0 = removeRowsFromState(S0, sel);
        guidata(hFig,S0);

        refreshTable();
        clearPreview();
        updateOutlierBox();
        setStatusText(sprintf('Removed %d row(s). Nothing else was remapped.', numel(sel)));
    end

    function onSetDataSelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel)
            setStatusText('Select rows first.');
            return;
        end
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select DATA (.mat)', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);
        for r = sel(:)'
            S0.subj{r,6} = fp;
        end
        guidata(hFig,S0);
        refreshTable();
        setStatusText('DATA assigned to selected rows.');
    end

    function onSetROISelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel)
            setStatusText('Select rows first.');
            return;
        end
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        [f,p] = uigetfile({'*.txt;*.mat','ROI files (*.txt, *.mat)'}, 'Select ROI file', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);

        for r = sel(:)'
            S0.subj{r,7} = fp;
            subj = strtrimSafe(S0.subj{r,2});
            if get(S0.hAutoPair,'Value')==1 && isempty(strtrimSafe(S0.subj{r,5}))
                S0.subj{r,5} = subj;
            end
            if isempty(strtrimSafe(S0.subj{r,6}))
                df = findDataMatNearROI(fp);
                if isempty(df), df = subj; end
                S0.subj{r,6} = df;
            end
        end
        guidata(hFig,S0);
        refreshTable();
        setStatusText('ROI assigned (DATA auto-filled if possible).');
    end

    function onSaveList(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);

        startPath = getSmartBrowseDir(S0, 'save');
        defFile = fullfile(startPath, 'GroupSubjects.mat');

        [f,p] = uiputfile({'*.mat','MAT list (*.mat)'}, 'Save subject list', defFile);
        if isequal(f,0)
            return;
        end

        subj = S0.subj;
        groupList = S0.groupList;
        condList = S0.condList;
        rowPacapSide = S0.rowPacapSide;
        groupCondPairs = exportGroupCondPairs(S0.groupToCondMap);

        save(fullfile(p,f), 'subj','groupList','condList','rowPacapSide','groupCondPairs','-v7');

        S0.opt.startDir = p;
        guidata(hFig,S0);

        setStatusText('Saved list.');
    end

    function onLoadList(~,~)
        S0 = guidata(hFig);

        startPath = getPreferredPacapRootDir(S0);
if isempty(startPath) || exist(startPath,'dir') ~= 7
    startPath = getSmartBrowseDir(S0, 'save');
end
        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'}, 'Load subject list', startPath);
        if isequal(f,0)
            return;
        end

        L = load(fullfile(p,f));

        if isfield(L,'subj')
            S0.subj = L.subj;
        end
        if isfield(L,'groupList')
            S0.groupList = L.groupList;
        end
        if isfield(L,'condList')
            S0.condList = L.condList;
        end

        if isfield(L,'rowPacapSide')
            S0.rowPacapSide = L.rowPacapSide;
        else
            S0.rowPacapSide = cell(size(S0.subj,1),1);
        end

        try
            S0.groupToCondMap = importGroupCondPairs(L.groupCondPairs, S0.groupToCondMap);
        catch
        end

        S0 = rememberGroupCondPair(S0,'PACAP','CondA');
        S0 = rememberGroupCondPair(S0,'Vehicle','CondB');
        S0 = rememberGroupCondPair(S0,'Control','CondB');
        S0 = rememberGroupCondPair(S0,'GroupA','CondA');
        S0 = rememberGroupCondPair(S0,'GroupB','CondB');

        S0 = sanitizeTableStruct(S0);
        S0 = ensureRowPacapSideSize(S0);
        S0.opt.startDir = p;
       S0.lastROI = struct();
S0.lastMAP = struct();
        S0.selectedRows = [];

        guidata(hFig,S0);
        refreshTable();
        clearPreview();
        setStatusText('Loaded list.');
    end

    function onFillFromROISelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel)
            setStatusText('Select rows first.');
            return;
        end

        for r = sel(:)'
            roi  = strtrimSafe(S0.subj{r,7});
            subj = strtrimSafe(S0.subj{r,2});
            if isempty(subj) && ~isempty(roi)
                subj = guessSubjectID(roi);
                S0.subj{r,2} = subj;
            end
            if get(S0.hAutoPair,'Value')==1
                S0.subj{r,5} = subj;
            end
            if isempty(strtrimSafe(S0.subj{r,6})) && ~isempty(roi)
                df = findDataMatNearROI(roi);
                if isempty(df), df = subj; end
                S0.subj{r,6} = df;
            end
        end

        guidata(hFig,S0);
        refreshTable();
        setStatusText('Filled PairID/DATA from ROI folder.');
    end

    function onRevertExcluded(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        for r = 1:size(S0.subj,1)
            st = strtrimSafe(S0.subj{r,9});
            if contains(lower(st),'excluded')
                S0.subj{r,1} = true;
                S0.subj{r,9} = '';
            end
        end
        S0.outlierKeys = {};
        S0.outlierInfo = {};
               S0 = sanitizeTableStruct(S0);
        S0.lastROI = struct();
        S0.lastMAP = struct();
        S0.lastMapDisplay = struct();
        guidata(hFig,S0);

        refreshTable();
        updateOutlierBox();
        clearPreview();
        setStatusText('Reverted excluded rows.');
    end

    function onOutEdit(src,~)
        S0 = guidata(hFig);
        S0.outDir = strtrim(get(src,'String'));
        guidata(hFig,S0);
    end

    function onBrowseOut(~,~)
        S0 = guidata(hFig);
        d = uigetdir(S0.outDir,'Select output folder');
        if isequal(d,0), return; end
        S0.outDir = d;
        guidata(hFig,S0);
        set(S0.hOutEdit,'String',S0.outDir);
    end

  function onTabClicked(tabName)
    S0 = guidata(hFig);
    tabName = upper(strtrimSafe(tabName));

        switch tabName
        case 'ROI'
            S0.mode = 'ROI Timecourse';
            try, set(S0.hMode,'Value',1); catch, end

        case 'MAP'
            S0.mode = 'Group Maps';
            try, set(S0.hMode,'Value',2); catch, end
            guidata(hFig,S0);

            try, refreshMapBundlePopup(); catch, end
            try, updateMapSideSummaryTable(); catch, end
            try, updateMapAlignmentLabel(); catch, end

        case 'FC'
            S0.mode = 'Functional Connectivity';
            guidata(hFig,S0);

            try
                refreshFCGroupPopups();
            catch
            end

        case 'PREV'
            % ROI Preview should always show ROI results, not group maps
            S0.mode = 'ROI Timecourse';
            try, set(S0.hMode,'Value',1); catch, end

        case 'STATS'
            % Statistics / Export is ROI-only
            S0.mode = 'ROI Timecourse';
            try, set(S0.hMode,'Value',1); catch, end
    end
    S0.activeTab = tabName;
    guidata(hFig,S0);
    updateManualTabs();

      if strcmpi(tabName,'PREV')
        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
            updatePreview();
        else
            clearPreview();
        end

    elseif strcmpi(tabName,'MAP')
        if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
            updateMapTabPreview();
        end

    elseif strcmpi(tabName,'FC')
        if isfield(S0,'lastFC') && ~isempty(fieldnames(S0.lastFC))
            updateFCTabPreview();
        end
    end
end

    function updateManualTabs()
        S0 = guidata(hFig);

           set(S0.tabROI,'Visible','off');
        set(S0.tabMAP,'Visible','off');
        set(S0.tabFC,'Visible','off');
        set(S0.tabSTATS,'Visible','off');
        set(S0.tabPREV,'Visible','off');

        tabOff = [0.18 0.18 0.18];
        tabOn  = [0.34 0.34 0.34];

              set(S0.hTabROI,  'BackgroundColor',tabOff,'ForegroundColor','w');
        set(S0.hTabMAP,  'BackgroundColor',tabOff,'ForegroundColor','w');
        set(S0.hTabFC,   'BackgroundColor',tabOff,'ForegroundColor','w');
        set(S0.hTabSTATS,'BackgroundColor',tabOff,'ForegroundColor','w');
        set(S0.hTabPREV, 'BackgroundColor',tabOff,'ForegroundColor','w');

                switch upper(S0.activeTab)
            case 'ROI'
                set(S0.tabROI,'Visible','on');
                set(S0.hTabROI,'BackgroundColor',tabOn);

            case 'MAP'
                set(S0.tabMAP,'Visible','on');
                set(S0.hTabMAP,'BackgroundColor',tabOn);

            case 'FC'
                set(S0.tabFC,'Visible','on');
                set(S0.hTabFC,'BackgroundColor',tabOn);

            case 'STATS'
                set(S0.tabSTATS,'Visible','on');
                set(S0.hTabSTATS,'BackgroundColor',tabOn);

            case 'PREV'
                set(S0.tabPREV,'Visible','on');
                set(S0.hTabPREV,'BackgroundColor',tabOn);
        end
    end

    function onModeChanged(src,~)
        S0 = guidata(hFig);
        items = get(src,'String');
        S0.mode = items{get(src,'Value')};

        if strcmpi(S0.mode,'Group Maps')
            S0.activeTab = 'MAP';
        else
            S0.activeTab = 'ROI';
        end

        guidata(hFig,S0);
        updateManualTabs();
        clearPreview();
    end

    function onROIChanged(~,~)
        S0 = guidata(hFig);
        S0.tc_computePSC     = logical(get(S0.hTC_ComputePSC,'Value'));
        S0.tc_baseMin0       = safeNum(get(S0.hBase0,'String'), S0.tc_baseMin0);
        S0.tc_baseMin1       = safeNum(get(S0.hBase1,'String'), S0.tc_baseMin1);
        S0.tc_injMin0        = safeNum(get(S0.hInj0,'String'),  S0.tc_injMin0);
        S0.tc_injMin1        = safeNum(get(S0.hInj1,'String'),  S0.tc_injMin1);
        S0.tc_peakSearchMin0 = safeNum(get(S0.hPkS0,'String'), S0.tc_peakSearchMin0);
        S0.tc_peakSearchMin1 = safeNum(get(S0.hPkS1,'String'), S0.tc_peakSearchMin1);
        S0.tc_plateauMin0    = safeNum(get(S0.hPlat0,'String'), S0.tc_plateauMin0);
        S0.tc_plateauMin1    = safeNum(get(S0.hPlat1,'String'), S0.tc_plateauMin1);
        S0.tc_peakWinMin     = safeNum(get(S0.hTC_PeakWin,'String'), S0.tc_peakWinMin);
        S0.tc_trimPct        = safeNum(get(S0.hTC_Trim,'String'), S0.tc_trimPct);

        mt = get(S0.hTC_Metric,'String');
        S0.tc_metric = mt{get(S0.hTC_Metric,'Value')};

        guidata(hFig,S0);
        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end
    end

    function onStyleChanged(~,~)
        S0 = guidata(hFig);
        cm = get(S0.hColorMode,'String');
        S0.colorMode = cm{get(S0.hColorMode,'Value')};

        sc = get(S0.hColorScheme,'String');
        S0.colorScheme = sc{get(S0.hColorScheme,'Value')};

        S0.tc_showSEM = logical(get(S0.hShowSEM,'Value'));
        S0.tc_showInjectionBox = logical(get(S0.hShowInjBox,'Value'));

        S0.manualGroupA = getSelectedPopupString(S0.hManGroupA);
        S0.manualGroupB = getSelectedPopupString(S0.hManGroupB);
        S0.manualColorA = get(S0.hManColorA,'Value');
        S0.manualColorB = get(S0.hManColorB,'Value');

        guidata(hFig,S0);
        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end
    end

    function onPreviewStyleChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hPrevStyle,'String');
        S0.previewStyle = items{get(S0.hPrevStyle,'Value')};
        S0.previewShowGrid = logical(get(S0.hPrevGrid,'Value'));
        guidata(hFig,S0);
        stylePreviewPanels(S0);
        updatePreview();
    end

    function onSmoothChanged(~,~)
        S0 = guidata(hFig);

        S0.tc_previewSmooth = logical(get(S0.hSmoothEnable,'Value'));

        v = str2double(get(S0.hSmoothWin,'String'));
        if ~(isfinite(v) && v > 0)
            v = S0.tc_previewSmoothWinSec;
            set(S0.hSmoothWin,'String',num2str(v));
        end
        S0.tc_previewSmoothWinSec = v;

        guidata(hFig,S0);

        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();

    dtSec = median(diff(S0.lastROI.tMin))*60;
            winVol = max(1, round(S0.tc_previewSmoothWinSec / dtSec));
            setStatusText(sprintf('Preview smoothing: win=%.1fs => %d pts (dt=%.2fs)', ...
                S0.tc_previewSmoothWinSec, winVol, dtSec));
        end
    end

    function onAnnotChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hAnnotMode,'String');
        S0.annotMode = items{get(S0.hAnnotMode,'Value')};
        S0.showPText = logical(get(S0.hShowPText,'Value'));
        guidata(hFig,S0);
      if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end
    end

    function onPlotScaleChanged(~,~)
        S0 = guidata(hFig);

        S0.plotTop.auto      = logical(get(S0.hTopAuto,'Value'));
        S0.plotTop.forceZero = logical(get(S0.hTopZero,'Value'));
        S0.plotTop.step      = max(0, safeNum(get(S0.hTopStep,'String'), S0.plotTop.step));
        S0.plotTop.ymin      = safeNum(get(S0.hTopYmin,'String'), S0.plotTop.ymin);
        S0.plotTop.ymax      = safeNum(get(S0.hTopYmax,'String'), S0.plotTop.ymax);

        S0.plotBot.auto      = logical(get(S0.hBotAuto,'Value'));
        S0.plotBot.forceZero = logical(get(S0.hBotZero,'Value'));
        S0.plotBot.step      = max(0, safeNum(get(S0.hBotStep,'String'), S0.plotBot.step));
        S0.plotBot.ymin      = safeNum(get(S0.hBotYmin,'String'), S0.plotBot.ymin);
        S0.plotBot.ymax      = safeNum(get(S0.hBotYmax,'String'), S0.plotBot.ymax);

        set(S0.hTopStep,'String',num2str(S0.plotTop.step));
        set(S0.hTopYmin,'String',num2str(S0.plotTop.ymin));
        set(S0.hTopYmax,'String',num2str(S0.plotTop.ymax));
        set(S0.hBotStep,'String',num2str(S0.plotBot.step));
        set(S0.hBotYmin,'String',num2str(S0.plotBot.ymin));
        set(S0.hBotYmax,'String',num2str(S0.plotBot.ymax));

        guidata(hFig,S0);

        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end
    end

    function onYStep(whichAxis, whichField, signDir)
        S0 = guidata(hFig);

        if strcmpi(whichAxis,'Top')
            step = max(0, safeNum(get(S0.hTopStep,'String'), S0.plotTop.step));
            S0.plotTop.auto = false;
            set(S0.hTopAuto,'Value',0);

            if strcmpi(whichField,'ymin')
                S0.plotTop.forceZero = false;
                set(S0.hTopZero,'Value',0);
                v = safeNum(get(S0.hTopYmin,'String'), S0.plotTop.ymin);
                v = v + signDir * step;
                S0.plotTop.ymin = v;
                set(S0.hTopYmin,'String',num2str(v));
            else
                v = safeNum(get(S0.hTopYmax,'String'), S0.plotTop.ymax);
                v = v + signDir * step;
                S0.plotTop.ymax = v;
                set(S0.hTopYmax,'String',num2str(v));
            end
        else
            step = max(0, safeNum(get(S0.hBotStep,'String'), S0.plotBot.step));
            S0.plotBot.auto = false;
            set(S0.hBotAuto,'Value',0);

            if strcmpi(whichField,'ymin')
                S0.plotBot.forceZero = false;
                set(S0.hBotZero,'Value',0);
                v = safeNum(get(S0.hBotYmin,'String'), S0.plotBot.ymin);
                v = v + signDir * step;
                S0.plotBot.ymin = v;
                set(S0.hBotYmin,'String',num2str(v));
            else
                v = safeNum(get(S0.hBotYmax,'String'), S0.plotBot.ymax);
                v = v + signDir * step;
                S0.plotBot.ymax = v;
                set(S0.hBotYmax,'String',num2str(v));
            end
        end

        guidata(hFig,S0);
        onPlotScaleChanged([],[]);
    end

    function onMapChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hMapSummary,'String');
        S0.mapSummary = items{get(S0.hMapSummary,'Value')};
        guidata(hFig,S0);

       if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
    onComputeGroupMaps([],[]);
end
        end
  


    
   

    function onMapDisplayChanged(~,~)
       S0 = guidata(hFig);

    % Do not trigger bundle preview / map refresh while user is in ROI-only workflow
    if ~strcmpi(strtrimSafe(S0.activeTab),'MAP') && ~strcmpi(strtrimSafe(S0.mode),'Group Maps')
        return;
    end

        items = get(S0.hMapSource,'String');
        S0.mapSource = items{get(S0.hMapSource,'Value')};

       S0.mapAlphaModOn = true;
S0.mapThreshold  = 0;

if isfield(S0,'hMapUseGlobalWin') && ishghandle(S0.hMapUseGlobalWin)
    S0.mapUseGlobalWindows = logical(get(S0.hMapUseGlobalWin,'Value'));
end

if isfield(S0,'hMapBase0') && ishghandle(S0.hMapBase0)
    S0.mapGlobalBaseSec(1) = safeNum(get(S0.hMapBase0,'String'), S0.mapGlobalBaseSec(1));
end
if isfield(S0,'hMapBase1') && ishghandle(S0.hMapBase1)
    S0.mapGlobalBaseSec(2) = safeNum(get(S0.hMapBase1,'String'), S0.mapGlobalBaseSec(2));
end
if isfield(S0,'hMapSig0') && ishghandle(S0.hMapSig0)
    S0.mapGlobalSigSec(1) = safeNum(get(S0.hMapSig0,'String'), S0.mapGlobalSigSec(1));
end
if isfield(S0,'hMapSig1') && ishghandle(S0.hMapSig1)
    S0.mapGlobalSigSec(2) = safeNum(get(S0.hMapSig1,'String'), S0.mapGlobalSigSec(2));
end

if isfield(S0,'hMapUnderlayMode') && ishghandle(S0.hMapUnderlayMode)
    itemsU = get(S0.hMapUnderlayMode,'String');
    S0.mapUnderlayMode = itemsU{get(S0.hMapUnderlayMode,'Value')};
end

        S0.mapSigma  = max(0, safeNum(get(S0.hMapSigma,'String'),  S0.mapSigma));
        S0.mapModMin = safeNum(get(S0.hMapModMin,'String'), S0.mapModMin);
        S0.mapModMax = safeNum(get(S0.hMapModMax,'String'), S0.mapModMax);

        if ~isfinite(S0.mapModMin), S0.mapModMin = 0; end
        if ~isfinite(S0.mapModMax), S0.mapModMax = S0.mapModMin + 1; end
        if S0.mapModMax <= S0.mapModMin
            S0.mapModMax = S0.mapModMin + 1;
            set(S0.hMapModMax,'String',num2str(S0.mapModMax));
        end

        caxv = sscanf(get(S0.hMapCaxis,'String'), '%f');
        if numel(caxv) >= 2 && all(isfinite(caxv(1:2))) && caxv(2) ~= caxv(1)
            S0.mapCaxis = caxv(1:2).';
            if S0.mapCaxis(2) < S0.mapCaxis(1)
                S0.mapCaxis = fliplr(S0.mapCaxis);
            end
        else
            set(S0.hMapCaxis,'String',sprintf('%g %g',S0.mapCaxis(1),S0.mapCaxis(2)));
        end

        S0.mapBlackBody = logical(get(S0.hMapBlackBody,'Value'));

items = get(S0.hMapFlipMode,'String');
S0.mapFlipMode = items{get(S0.hMapFlipMode,'Value')};

items = get(S0.hMapColormap,'String');
S0.mapColormap = items{get(S0.hMapColormap,'Value')};

        guidata(hFig,S0);

        if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
    S0.lastMAP.mapRender = makeMapRenderStruct(S0);
    guidata(hFig,S0);
    updateMapTabPreview();
end

if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end
updateMapAlignmentLabel();
updateMapSideSummaryTable();
if isfinite(S0.mapPreviewRow)
    try
        previewBundleRow(S0.mapPreviewRow);
    catch
    end
end

if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
    updateMapTabPreview();
    if S0.mapUseGlobalWindows || strcmpi(S0.mapSource,'Recompute from exported PSC')
        setStatusText('Selected preview updated. Click "Compute Group Maps" to rebuild the full group map with current settings.');
    end
end

    end

    function onStatsChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hTest,'String');
        S0.testType = items{get(S0.hTest,'Value')};
        a = str2double(get(S0.hAlpha,'String'));
        if isfinite(a) && a>0 && a<1
            S0.alpha = a;
        else
            set(S0.hAlpha,'String',num2str(S0.alpha));
        end
       guidata(hFig,S0);

if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
    updatePreview();
end

if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
    updateMapTabPreview();
end
    end

    function onOutlierChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hOutMethod,'String');
        S0.outlierMethod = items{get(S0.hOutMethod,'Value')};

        if strcmpi(S0.outlierMethod,'MAD robust z-score')
            set(S0.hOutParamLbl,'String','Thr (z):');
            v = str2double(get(S0.hOutParam,'String'));
            if isfinite(v) && v>0
                S0.outMADthr = v;
            else
                set(S0.hOutParam,'String',num2str(S0.outMADthr));
            end
        elseif strcmpi(S0.outlierMethod,'IQR rule')
            set(S0.hOutParamLbl,'String','k (IQR):');
            v = str2double(get(S0.hOutParam,'String'));
            if isfinite(v) && v>0
                S0.outIQRk = v;
            else
                set(S0.hOutParam,'String',num2str(S0.outIQRk));
            end
        else
            set(S0.hOutParamLbl,'String','Param:');
        end
        guidata(hFig,S0);
    end

    function onDetectOutliers(~,~)
        S0 = guidata(hFig);
        if ~isfield(S0,'lastROI') || isempty(fieldnames(S0.lastROI)) || ~isfield(S0.lastROI,'metricVals')
    errordlg('Run ROI Timecourse analysis first.','Outliers');
    return;
end
if ~strcmpi(S0.lastROI.mode,'ROI Timecourse')
    errordlg('Outlier detection applies to ROI Timecourse only.','Outliers');
    return;
end
        onOutlierChanged([],[]);
        S0 = guidata(hFig);

        [keysOut, info] = detectOutliers(double(S0.lastROI.metricVals(:)), S0.lastROI.subjTable, S0);
        S0.outlierKeys = keysOut;
        S0.outlierInfo = info;
        guidata(hFig,S0);

        updateOutlierBox();

        if isempty(info)
            setStatusText('No outliers detected.');
        else
            setStatusText(sprintf('Detected %d outlier(s). Preview updated.', numel(info)));
        end
        updatePreview();
    end

    function onExcludeOutliers(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        if isempty(S0.outlierKeys)
            errordlg('No outliers detected. Click Detect first.','Exclude outliers');
            return;
        end
        keysAll = makeRowKeys(S0.subj);
        for i = 1:numel(S0.outlierKeys)
            hit = find(strcmp(keysAll, S0.outlierKeys{i}), 1, 'first');
            if ~isempty(hit)
                S0.subj{hit,1} = false;
                S0.subj{hit,9} = 'EXCLUDED (outlier)';
            end
        end
        S0 = sanitizeTableStruct(S0);
        S0.lastROI = struct();
        S0.lastMAP = struct();
        S0.lastMapDisplay = struct();
        guidata(hFig,S0);

        refreshTable();
        clearPreview();
        setStatusText('Outliers excluded. RUN again.');
    end

    function updateSelLabel()
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel)
            set(S0.hSelInfo,'String','Selected: none');
        else
            set(S0.hSelInfo,'String',sprintf('Selected: %d row(s)', numel(sel)));
        end
    end

    function updateOutlierBox()
        S0 = guidata(hFig);
        if isempty(S0.outlierInfo)
            msg = {'No outliers detected yet.'};
        else
            msg = S0.outlierInfo(:);
        end
        try
            set(S0.hOutInfo,'String',msg,'Value',1);
        catch
            try, set(S0.hOutInfo,'String',msg); catch, end
        end
    end

    function syncSubjFromTable()
        S0 = guidata(hFig);
        try
            dt = get(S0.hTable,'Data');
            if iscell(dt)
                dt = stripUITablePlaceholders(dt);
                if isempty(dt)
                    S0.subj = cell(0,9);
                else
                    S0.subj = applyUITableToSubj(S0.subj, dt);
                end
            end
        catch
        end
        S0 = sanitizeTableStruct(S0);
        guidata(hFig,S0);
    end

    function refreshTable()
    S0 = guidata(hFig);
    S0 = sanitizeTableStruct(S0);
    S0 = ensureRowPacapSideSize(S0);

    oldQuickGroup = '';
    oldQuickCond  = '';
    oldManA = '';
    oldManB = '';

    try, oldQuickGroup = getSelectedPopupString(S0.hQuickGroup); catch, end
    try, oldQuickCond  = getSelectedPopupString(S0.hQuickCond);  catch, end
    try, oldManA       = getSelectedPopupString(S0.hManGroupA);  catch, end
    try, oldManB       = getSelectedPopupString(S0.hManGroupB);  catch, end

    if isempty(oldQuickGroup), oldQuickGroup = S0.defaultGroup; end
    if isempty(oldQuickCond),  oldQuickCond  = S0.defaultCond;  end
    if isempty(oldManA),       oldManA       = S0.manualGroupA; end
    if isempty(oldManB),       oldManB       = S0.manualGroupB; end

    S0.groupList = mergeUniqueStable(S0.groupList, uniqueStable(colAsStr(S0.subj,3)));
    S0.condList  = mergeUniqueStable(S0.condList,  uniqueStable(colAsStr(S0.subj,4)));

    colFmt = {'logical','char','char','char',S0.groupList,S0.condList,'char','char','char'};

    dispData  = makeUITableDisplayData(S0.subj, S0.tableMinRows);
    rowColors = buildTableRowColorsDisplay(S0.subj, S0.tableMinRows);

    try
        set(S0.hTable,'ColumnFormat',colFmt);
    catch
    end

    try
        set(S0.hTable,'Data',dispData);
        set(S0.hTable,'RowName','numbered');
        set(S0.hTable,'BackgroundColor',rowColors);
    catch
    end

    drawnow limitrate;

    try
        if ~isfield(S0,'tableColWidths') || isempty(S0.tableColWidths)
            S0.tableColWidths = compactTableColWidths(S0.hTable);
        end
        set(S0.hTable,'ColumnWidth',S0.tableColWidths);
        guidata(hFig,S0);
    catch
    end

    try
        set(S0.hQuickGroup,'String',S0.groupList);
        setPopupToString(S0.hQuickGroup, oldQuickGroup);
    catch
    end

    try
        set(S0.hQuickCond,'String',S0.condList);
        setPopupToString(S0.hQuickCond, oldQuickCond);
    catch
    end

    try
        set(S0.hManGroupA,'String',S0.groupList);
        setPopupToString(S0.hManGroupA, oldManA);
    catch
    end

    try
        set(S0.hManGroupB,'String',S0.groupList);
        setPopupToString(S0.hManGroupB, oldManB);
    catch
    end

    styleKey = sprintf('MAIN_%d_%d_%d', size(dispData,1), numel(S0.groupList), numel(S0.condList));
    restyleUITableIfNeeded(S0.hTable, S0.C, styleKey);

    guidata(hFig,S0);

    try
        onQuickGroupChanged(S0.hQuickGroup, []);
    catch
    end

    drawnow limitrate;
    updateSelLabel();

    S0 = guidata(hFig);
    S0 = ensureRowPacapSideSize(S0);
    guidata(hFig,S0);

  doMapRefresh = strcmpi(strtrimSafe(S0.activeTab),'MAP') || strcmpi(strtrimSafe(S0.mode),'Group Maps');

if doMapRefresh
    try
        refreshMapBundlePopup();
    catch
    end
    try
        updateMapAlignmentLabel();
    catch
    end
    try
        updateMapSideSummaryTable();
    catch
    end
end
end

function addFileSmart(fp)
    S0 = guidata(hFig);
    [~,~,ext] = fileparts(fp);
    ext = lower(ext);

    subj = guessSubjectID(fp);
    isROI = false;
    isBundle = false;
    isData = false;

    if strcmp(ext,'.txt')
        isROI = true;

    elseif strcmp(ext,'.mat')
        try
            L = load(fp,'G');

            if isfield(L,'G') && isstruct(L.G) && ...
                    isfield(L.G,'kind') && strcmpi(strtrimSafe(L.G.kind),'SCM_GROUP_EXPORT')

                isBundle = true;

                if isfield(L.G,'animalID') && ~isempty(L.G.animalID)
                    subj = strtrimSafe(L.G.animalID);
                end

            else
                L2 = load(fp);
                if isfield(L2,'roiTC') || isfield(L2,'TC')
                    isROI = true;
                else
                    isData = true;
                end
            end
        catch
            isData = true;
        end
    else
        isData = true;
    end

    if isempty(subj)
        subj = ['S' num2str(size(S0.subj,1)+1)];
    end

    gdef = getSelectedPopupString(S0.hQuickGroup);
    cdef = getSelectedPopupString(S0.hQuickCond);
    if isempty(gdef), gdef = S0.defaultGroup; end
    if isempty(cdef), cdef = S0.defaultCond; end

    if isBundle
        metaIn = extractMetaFromSources(subj,'','',fp);
    elseif isROI
        metaIn = extractMetaFromSources(subj,'',fp,'');
    else
        metaIn = extractMetaFromSources(subj,fp,'','');
    end

    if isBundle
        % Assign one bundle to ONE row only.
        rowIdx = findSingleBundleTargetRow(S0, metaIn);

        if isempty(rowIdx)
            % No reusable row found -> create a new one
            newRow = makeEmptyGARow(subj, gdef, cdef, S0);
            templateIdx = findTemplateRowByMeta(S0, metaIn);

            if ~isempty(templateIdx)
                if ~isempty(strtrimSafe(S0.subj{templateIdx,3})), newRow{3} = strtrimSafe(S0.subj{templateIdx,3}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,4})), newRow{4} = strtrimSafe(S0.subj{templateIdx,4}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,6})), newRow{6} = strtrimSafe(S0.subj{templateIdx,6}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,7})), newRow{7} = strtrimSafe(S0.subj{templateIdx,7}); end
            end

            newRow{8} = fp;
            S0.subj(end+1,:) = newRow;

        else
            % Assign SAME bundle to ONE chosen row only
            S0.subj{rowIdx,8} = fp;

            if isempty(strtrimSafe(S0.subj{rowIdx,2})) || strcmpi(strtrimSafe(S0.subj{rowIdx,2}), 'N/A')
                S0.subj{rowIdx,2} = subj;
            end

            if get(S0.hAutoPair,'Value')==1 && isempty(strtrimSafe(S0.subj{rowIdx,5}))
                S0.subj{rowIdx,5} = strtrimSafe(S0.subj{rowIdx,2});
            end
        end

    elseif isROI
        rowIdx = findReusableROIRowByMeta(S0, metaIn);
        templateIdx = findTemplateRowByMeta(S0, metaIn);

        if isempty(rowIdx)
            newRow = makeEmptyGARow(subj, gdef, cdef, S0);
            newRow{7} = fp;

            if ~isempty(templateIdx)
                if ~isempty(strtrimSafe(S0.subj{templateIdx,3})), newRow{3} = strtrimSafe(S0.subj{templateIdx,3}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,4})), newRow{4} = strtrimSafe(S0.subj{templateIdx,4}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,6})), newRow{6} = strtrimSafe(S0.subj{templateIdx,6}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,8})), newRow{8} = strtrimSafe(S0.subj{templateIdx,8}); end
            end

            if isempty(strtrimSafe(newRow{6}))
                df = findDataMatNearROI(fp);
                if isempty(df), df = subj; end
                newRow{6} = df;
            end

            S0.subj(end+1,:) = newRow;

        else
            S0.subj{rowIdx,7} = fp;

            if get(S0.hAutoPair,'Value')==1 && isempty(strtrimSafe(S0.subj{rowIdx,5}))
                S0.subj{rowIdx,5} = subj;
            end

            if isempty(strtrimSafe(S0.subj{rowIdx,6}))
                df = findDataMatNearROI(fp);
                if isempty(df) && ~isempty(templateIdx)
                    df = strtrimSafe(S0.subj{templateIdx,6});
                end
                if isempty(df), df = subj; end
                S0.subj{rowIdx,6} = df;
            end

            if isempty(strtrimSafe(S0.subj{rowIdx,8})) && ~isempty(templateIdx)
                S0.subj{rowIdx,8} = strtrimSafe(S0.subj{templateIdx,8});
            end
        end

    else
        rowIdx = findReusableDataRowByMeta(S0, metaIn);

        if isempty(rowIdx)
            newRow = makeEmptyGARow(subj, gdef, cdef, S0);
            newRow{6} = fp;

            templateIdx = findTemplateRowByMeta(S0, metaIn);
            if ~isempty(templateIdx)
                if ~isempty(strtrimSafe(S0.subj{templateIdx,3})), newRow{3} = strtrimSafe(S0.subj{templateIdx,3}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,4})), newRow{4} = strtrimSafe(S0.subj{templateIdx,4}); end
                if ~isempty(strtrimSafe(S0.subj{templateIdx,8})), newRow{8} = strtrimSafe(S0.subj{templateIdx,8}); end
            end

            S0.subj(end+1,:) = newRow;
        else
            S0.subj{rowIdx,6} = fp;
        end
    end

    S0 = sanitizeTableStruct(S0);
    guidata(hFig,S0);
end

    function row = makeEmptyGARow(subj, gdef, cdef, S0)
        row = {true, subj, gdef, cdef, '', '', '', '', ''};
        if get(S0.hAutoPair,'Value') == 1
            row{5} = subj;
        end
    end

    function idx = findReusableROIRowByMeta(S0, metaIn)
        idx = [];
        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});
            if metaMatchesGA(metaRow, metaIn) && isempty(strtrimSafe(S0.subj{r,7}))
                idx = r;
                return;
            end
        end
    end

    function idx = findReusableDataRowByMeta(S0, metaIn)
        idx = [];
        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});
            if metaMatchesGA(metaRow, metaIn) && isempty(strtrimSafe(S0.subj{r,6}))
                idx = r;
                return;
            end
        end
    end

    function idx = findReusableBundleRowByMeta(S0, metaIn)
        idx = [];
        firstHit = [];

        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});

            if metaMatchesGA(metaRow, metaIn)
                if isempty(firstHit)
                    firstHit = r;
                end

                % Prefer a matching row whose bundle slot is still empty
                if isempty(strtrimSafe(S0.subj{r,8}))
                    idx = r;
                    return;
                end
            end
        end

        % Fallback: if an exact metadata match already exists, reuse that row
        idx = firstHit;
    end



    function rows = findBundleTargetRows(S0, metaIn)
        rows = [];

        % 1) If user selected rows, use ALL selected rows
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if ~isempty(sel)
            rows = sel(:).';
            return;
        end

        % 2) Otherwise collect ALL metadata-matching rows
        rowsMatch = [];
        rowsEmpty = [];

        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});

            if metaMatchesGA(metaRow, metaIn)
                rowsMatch(end+1) = r; %#ok<AGROW>

                if isempty(strtrimSafe(S0.subj{r,8}))
                    rowsEmpty(end+1) = r; %#ok<AGROW>
                end
            end
        end

        % Prefer matching rows whose bundle slot is still empty
        if ~isempty(rowsEmpty)
            rows = rowsEmpty;
            return;
        end

        % Otherwise reuse all matching rows
        if ~isempty(rowsMatch)
            rows = rowsMatch;
            return;
        end

        % 3) Fallback: active USE rows with empty bundle slot
        useRows = find(logicalCol(S0.subj,1));
        tmp = [];
        for r = useRows(:)'
            if isempty(strtrimSafe(S0.subj{r,8}))
                tmp(end+1) = r; %#ok<AGROW>
            end
        end

        if ~isempty(tmp)
            rows = tmp;
            return;
        end

        % 4) If exactly one USE row exists, allow overwrite
        if numel(useRows) == 1
            rows = useRows;
        end
    end

    function idx = findEmptySelectedOrUsedBundleRow(S0)
        idx = [];

        % 1) Prefer explicitly selected rows
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        for r = sel(:)'
            if isempty(strtrimSafe(S0.subj{r,8}))
                idx = r;
                return;
            end
        end

        % If exactly one row is selected, allow overwrite/reassign
        if numel(sel) == 1
            idx = sel(1);
            return;
        end

        % 2) Otherwise use active USE rows with empty bundle slot
        useRows = find(logicalCol(S0.subj,1));
        for r = useRows(:)'
            if isempty(strtrimSafe(S0.subj{r,8}))
                idx = r;
                return;
            end
        end

        % If exactly one USE row exists, allow overwrite/reassign
        if numel(useRows) == 1
            idx = useRows(1);
            return;
        end
    end


    function idx = findTemplateRowByMeta(S0, metaIn)
        idx = [];
        firstHit = [];

        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});
            if metaMatchesGA(metaRow, metaIn)
                if isempty(firstHit)
                    firstHit = r;
                end
                if ~isempty(strtrimSafe(S0.subj{r,8}))
                    idx = r;
                    return;
                end
            end
        end

        idx = firstHit;
    end

        function idx = findSingleBundleTargetRow(S0, metaIn)
    idx = [];

    sel = clampSelRows(S0.selectedRows, size(S0.subj,1));

    % 1) Explicit user selection: prefer first selected row with empty bundle
    for r = sel(:)'
        if isempty(strtrimSafe(S0.subj{r,8}))
            idx = r;
            return;
        end
    end

    % 2) If exactly one row is selected, allow overwrite
    if numel(sel) == 1
        idx = sel(1);
        return;
    end

    % 3) Prefer strict metadata-matching PACAP/CondA row with empty bundle
    idx = findBestMetaBundleRow(S0, metaIn, true, true);
    if ~isempty(idx), return; end

    % 4) Otherwise any strict metadata-matching row with empty bundle
    idx = findBestMetaBundleRow(S0, metaIn, false, true);
    if ~isempty(idx), return; end

    % 5) Then strict metadata-matching PACAP/CondA row even if already filled
    idx = findBestMetaBundleRow(S0, metaIn, true, false);
    if ~isempty(idx), return; end

    % 6) Then any strict metadata-matching row
    idx = findBestMetaBundleRow(S0, metaIn, false, false);
    if ~isempty(idx), return; end

    % 7) SAFE fallback only if there is exactly one active USE row with empty bundle
    useRows = find(logicalCol(S0.subj,1));
    emptyUse = [];
    for r = useRows(:)'
        if isempty(strtrimSafe(S0.subj{r,8}))
            emptyUse(end+1) = r; %#ok<AGROW>
        end
    end

    if numel(emptyUse) == 1
        idx = emptyUse(1);
        return;
    end

    % 8) If exactly one USE row exists, allow overwrite
    if numel(useRows) == 1
        idx = useRows(1);
        return;
    end

    % otherwise leave empty -> caller will create a new row
end

    function idx = findBestMetaBundleRow(S0, metaIn, preferPacap, requireEmptyBundle)
        idx = [];
        firstAny = [];

        for r = 1:size(S0.subj,1)
            metaRow = extractMetaFromSources(S0.subj{r,2}, S0.subj{r,6}, S0.subj{r,7}, S0.subj{r,8});

            if ~metaMatchesGA(metaRow, metaIn)
                continue;
            end

            if isempty(firstAny)
                firstAny = r;
            end

            if requireEmptyBundle && ~isempty(strtrimSafe(S0.subj{r,8}))
                continue;
            end

            if preferPacap
                if isPacapRowGA(S0.subj(r,:))
                    idx = r;
                    return;
                end
            else
                idx = r;
                return;
            end
        end

        if ~requireEmptyBundle && isempty(idx)
            idx = firstAny;
        end
    end

    function tf = isPacapRowGA(row)
        grp = upper(strtrimSafe(row{3}));
        cnd = upper(strtrimSafe(row{4}));

        tf = contains(grp,'PACAP') || contains(grp,'GROUPA') || strcmp(grp,'A') || ...
             contains(cnd,'CONDA') || strcmp(cnd,'A');
    end


    function tf = metaMatchesGA(metaRow, metaIn)
        tf = false;

        a1 = strtrimSafe(metaRow.animalID);
        a2 = strtrimSafe(metaIn.animalID);

        if isempty(a1) || isempty(a2) || strcmpi(a1,'N/A') || strcmpi(a2,'N/A')
            return;
        end

        if ~strcmpi(a1, a2)
            return;
        end

        sessOK = metaLooseFieldMatch(metaRow.session, metaIn.session);
        scanOK = metaLooseFieldMatch(metaRow.scanID,  metaIn.scanID);

        tf = sessOK && scanOK;
    end

   function tf = metaLooseFieldMatch(a, b)
    a = strtrimSafe(a);
    b = strtrimSafe(b);

    aUnknown = isempty(a) || strcmpi(a,'N/A');
    bUnknown = isempty(b) || strcmpi(b,'N/A');

    % both unknown -> okay, treat as equal
    if aUnknown && bUnknown
        tf = true;
        return;
    end

    % one known and one unknown -> NOT a match
    if aUnknown || bUnknown
        tf = false;
        return;
    end

    % both known -> exact match only
    tf = strcmpi(a, b);
end

    function setPopupToString(h, desired)
        items = get(h,'String');
        v = 1;
        for k = 1:numel(items)
            if strcmpi(items{k}, desired)
                v = k;
                break;
            end
        end
        set(h,'Value',v);
    end

function s = getSelectedPopupString(h)
s = '';

if nargin < 1 || isempty(h) || ~ishandle(h)
    return;
end

try
    items = get(h,'String');
    val   = get(h,'Value');
catch
    return;
end

if isempty(items)
    return;
end

if ischar(items)
    s = strtrim(items);
    return;
end

if isstring(items)
    items = cellstr(items);
end

if iscell(items)
    val = max(1, min(numel(items), double(val)));
    try
        s = strtrim(char(items{val}));
    catch
        s = '';
    end
    return;
end

try
    s = strtrim(char(items));
catch
    s = '';
end
end

    function setStatusText(txt)
        S0 = guidata(hFig);
        try
            set(S0.hStatus,'String',txt);
        catch
        end
        drawnow limitrate;
    end

    function setStatus(isReady)
        if ~isempty(opt.statusFcn)
            try
                opt.statusFcn(logical(isReady));
            catch
            end
        end
    end
%%% =====================================================================
%%% FUNCTIONAL CONNECTIVITY CALLBACKS
%%% =====================================================================

    function onLoadFCGroupBundles(~,~)
        S0 = guidata(hFig);

        startPath = getSmartBrowseDir(S0,'add');
        if exist(fullfile(startPath,'Connectivity','GroupBundles'),'dir') == 7
            startPath = fullfile(startPath,'Connectivity','GroupBundles');
        elseif exist(fullfile(S0.outDir,'Connectivity','GroupBundles'),'dir') == 7
            startPath = fullfile(S0.outDir,'Connectivity','GroupBundles');
        end

        [f,p] = uigetfile({'FC_GroupBundle_*.mat;*.mat','FC group bundles (*.mat)'}, ...
            'Select FC_GroupBundle MAT files', ...
            startPath, ...
            'MultiSelect','on');

        if isequal(f,0)
            return;
        end

        if ischar(f)
            f = {f};
        end

        fileList = cell(numel(f),1);
        for ii = 1:numel(f)
            fileList{ii} = fullfile(p,f{ii});
        end

        loadFCFileListIntoState(fileList);
    end

    function onScanFCGroupFolder(~,~)
        S0 = guidata(hFig);

        startPath = getSmartBrowseDir(S0,'add');
        rootDir = uigetdir(startPath,'Select folder to scan for FC_GroupBundle_*.mat');

        if isequal(rootDir,0)
            return;
        end

        fileList = findFCBundlesRecursive(rootDir);

        if isempty(fileList)
            errordlg('No FC_GroupBundle_*.mat files found in the selected folder.','Functional Connectivity');
            return;
        end

        loadFCFileListIntoState(fileList);
    end

    function loadFCFileListIntoState(fileList)
        S0 = guidata(hFig);

        if isempty(fileList)
            return;
        end

        setStatus(false);
        setStatusText('Loading Functional Connectivity group bundles...');
        drawnow;

        try
            [FC, cacheOut] = loadFCGroupBundlesFromFiles(fileList, S0.cache);

            if FC.nSubjects < 1
                error('No valid subjects with ROI FC matrices were found in the selected FC bundles.');
            end

            S0.cache = cacheOut;
            S0.FC = FC;
            S0.FC.loaded = true;
            S0.lastFC = struct();
            S0.activeTab = 'FC';
            S0.mode = 'Functional Connectivity';

            guidata(hFig,S0);

            refreshFCGroupPopups();
            updateManualTabs();

            fcNoData(S0.axFCA,'Group A mean FC',S0.C);
            fcNoData(S0.axFCB,'Group B mean FC',S0.C);
            fcNoData(S0.axFCD,'Difference: A - B',S0.C);
            fcNoData(S0.axFCP,'p-value map',S0.C);

            set(S0.hFCInfo,'String',sprintf('Loaded %d FC subject(s) from %d bundle file(s). Choose groups and click Compute Group FC.', ...
                FC.nSubjects, numel(fileList)));

        catch ME
            errordlg(ME.message,'Load FC bundles');
            setStatusText(['FC loading failed: ' ME.message]);
        end

        setStatus(true);
    end

    function refreshFCGroupPopups()
        S0 = guidata(hFig);

        groups = S0.groupList;

        if isfield(S0,'FC') && isfield(S0.FC,'subjects') && ~isempty(S0.FC.subjects)
            g2 = cell(numel(S0.FC.subjects),1);
            for ii = 1:numel(S0.FC.subjects)
                g2{ii} = strtrimSafe(S0.FC.subjects(ii).group);
                if isempty(g2{ii})
                    g2{ii} = 'Unassigned';
                end
            end
            groups = mergeUniqueStable(groups, uniqueStable(g2));
        end

        if isempty(groups)
            groups = {'PACAP','Vehicle'};
        end

        try
            oldA = getSelectedPopupString(S0.hFCGroupA);
            oldB = getSelectedPopupString(S0.hFCGroupB);
        catch
            oldA = '';
            oldB = '';
        end

        set(S0.hFCGroupA,'String',groups);
        set(S0.hFCGroupB,'String',groups);

        if ~isempty(oldA)
            setPopupToString(S0.hFCGroupA, oldA);
        elseif any(strcmpi(groups,'PACAP'))
            setPopupToString(S0.hFCGroupA, 'PACAP');
        else
            set(S0.hFCGroupA,'Value',1);
        end

        if ~isempty(oldB)
            setPopupToString(S0.hFCGroupB, oldB);
        elseif any(strcmpi(groups,'Vehicle'))
            setPopupToString(S0.hFCGroupB, 'Vehicle');
        elseif numel(groups) >= 2
            set(S0.hFCGroupB,'Value',2);
        else
            set(S0.hFCGroupB,'Value',1);
        end
    end

    function onComputeGroupFC(~,~)
        S0 = guidata(hFig);

        if ~isfield(S0,'FC') || ~isfield(S0.FC,'loaded') || ~S0.FC.loaded
            errordlg('Load FC_GroupBundle files first.','Functional Connectivity');
            return;
        end

        groupA = getSelectedPopupString(S0.hFCGroupA);
        groupB = getSelectedPopupString(S0.hFCGroupB);

        if isempty(groupA) || isempty(groupB)
            errordlg('Choose Group A and Group B first.','Functional Connectivity');
            return;
        end

        if strcmpi(groupA,groupB)
            errordlg('Group A and Group B must be different.','Functional Connectivity');
            return;
        end

        thr = safeNum(get(S0.hFCThreshold,'String'),0);
        if ~isfinite(thr) || thr < 0
            thr = 0;
        end
        S0.fcThreshold = thr;
        set(S0.hFCThreshold,'String',num2str(thr));

        dispItems = get(S0.hFCDisplay,'String');
        S0.fcDisplayValue = dispItems{get(S0.hFCDisplay,'Value')};

        setStatus(false);
        setStatusText('Computing group Functional Connectivity...');
        drawnow;

        try
            G = alignFCSubjectsToCommonROIs(S0.FC);
            R = computeGroupFCStats(G, groupA, groupB);

            S0.lastFC = R;
            S0.mode = 'Functional Connectivity';
            S0.activeTab = 'FC';

            guidata(hFig,S0);
            updateManualTabs();
            updateFCTabPreview();

            set(S0.hFCInfo,'String',sprintf('Computed FC: %s n=%d, %s n=%d, common ROIs=%d. Stats are on Fisher z.', ...
                groupA, R.nA, groupB, R.nB, numel(R.labels)));

            setStatusText('Functional Connectivity group analysis complete.');

        catch ME
            errordlg(ME.message,'Functional Connectivity');
            setStatusText(['FC analysis failed: ' ME.message]);
        end

        setStatus(true);
    end

    function updateFCTabPreview()
        S0 = guidata(hFig);

        if ~isfield(S0,'lastFC') || isempty(fieldnames(S0.lastFC))
            return;
        end

        R = S0.lastFC;

        thr = safeNum(get(S0.hFCThreshold,'String'), S0.fcThreshold);
        if ~isfinite(thr) || thr < 0
            thr = 0;
        end

        dispItems = get(S0.hFCDisplay,'String');
        dispMode = dispItems{get(S0.hFCDisplay,'Value')};

        if strcmpi(dispMode,'Fisher z')
            A = R.meanZA;
            B = R.meanZB;
            D = R.diffZ;
            climMain = [-2.5 2.5];
            climDiff = [-1.0 1.0];
            valTxt = 'Fisher z';
        else
            A = R.meanRA;
            B = R.meanRB;
            D = R.diffR;
            climMain = [-1 1];
            climDiff = [-1 1];
            valTxt = 'Pearson r';
        end

        if thr > 0
            A(abs(A) < thr) = 0;
            B(abs(B) < thr) = 0;
            D(abs(D) < thr) = 0;
        end

        fcPlotMatrix(S0.axFCA,A,climMain,['Mean FC: ' R.groupA ' (' valTxt ')'],R.names,S0.C);
        fcPlotMatrix(S0.axFCB,B,climMain,['Mean FC: ' R.groupB ' (' valTxt ')'],R.names,S0.C);
        fcPlotMatrix(S0.axFCD,D,climDiff,[R.groupA ' - ' R.groupB],R.names,S0.C);
        fcPlotPMatrix(S0.axFCP,R.pMat,['p-values: ' R.groupA ' vs ' R.groupB],R.names,S0.C);
    end

    function onExportGroupFC(~,~)
        S0 = guidata(hFig);

        if ~isfield(S0,'lastFC') || isempty(fieldnames(S0.lastFC))
            errordlg('Compute group FC first.','Functional Connectivity export');
            return;
        end

        startDir = getAnalysedBrowseDir(S0);
        outDir = fullfile(startDir,'GroupAnalysis','FunctionalConnectivity');

        if exist(outDir,'dir') ~= 7
            mkdir(outDir);
        end

        tag = datestr(now,'yyyymmdd_HHMMSS');

        setStatus(false);
        setStatusText('Exporting Functional Connectivity results...');
        drawnow;

        try
            R = S0.lastFC;

            matFile = fullfile(outDir,['GroupFC_' tag '.mat']);
            save(matFile,'R','-v7.3');

            writeFCMatrixCSV(fullfile(outDir,['GroupFC_meanR_' sanitizeFilename(R.groupA) '_' tag '.csv']),R.meanRA,R.names);
            writeFCMatrixCSV(fullfile(outDir,['GroupFC_meanR_' sanitizeFilename(R.groupB) '_' tag '.csv']),R.meanRB,R.names);
            writeFCMatrixCSV(fullfile(outDir,['GroupFC_diffR_' sanitizeFilename(R.groupA) '_minus_' sanitizeFilename(R.groupB) '_' tag '.csv']),R.diffR,R.names);
            writeFCMatrixCSV(fullfile(outDir,['GroupFC_pvalues_' sanitizeFilename(R.groupA) '_vs_' sanitizeFilename(R.groupB) '_' tag '.csv']),R.pMat,R.names);

            saveFCAxisPNG(S0.axFCA,fullfile(outDir,['GroupFC_mean_' sanitizeFilename(R.groupA) '_' tag '.png']),S0.C);
            saveFCAxisPNG(S0.axFCB,fullfile(outDir,['GroupFC_mean_' sanitizeFilename(R.groupB) '_' tag '.png']),S0.C);
            saveFCAxisPNG(S0.axFCD,fullfile(outDir,['GroupFC_diff_' sanitizeFilename(R.groupA) '_minus_' sanitizeFilename(R.groupB) '_' tag '.png']),S0.C);
            saveFCAxisPNG(S0.axFCP,fullfile(outDir,['GroupFC_pvalues_' sanitizeFilename(R.groupA) '_vs_' sanitizeFilename(R.groupB) '_' tag '.png']),S0.C);

            set(S0.hFCInfo,'String',['Exported FC results to: ' outDir]);
            setStatusText(['Functional Connectivity exported: ' outDir]);

        catch ME
            errordlg(ME.message,'Functional Connectivity export');
            setStatusText(['FC export failed: ' ME.message]);
        end

        setStatus(true);
    end


%%% =====================================================================
%%% LOCAL HELPERS
%%% =====================================================================

function h = mkBtn(parent, txt, pos, bg, cb)
h = uicontrol(parent,'Style','pushbutton','String',txt, ...
    'Units','normalized','Position',pos, ...
    'BackgroundColor',bg,'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',12,'Callback',cb);
end

function h = mkTabBtn(parent, txt, pos, cb)
h = uicontrol(parent,'Style','pushbutton','String',txt, ...
    'Units','normalized','Position',pos, ...
    'BackgroundColor',[0.18 0.18 0.18], ...
    'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',11,'Callback',cb);
end

function d = defaultOutDir(opt)
d = pwd;
if isfield(opt,'studio') && isstruct(opt.studio)
    P = studio_resolve_paths(opt.studio, 'GroupAnalysis', '');
    d = P.groupDir;
end
end

function s = sanitizeFilename(s)
if isstring(s), s = char(s); end
s = strtrim(char(s));
if isempty(s), s = 'export'; end
s = regexprep(s,'[<>:"/\\|?*\x00-\x1F]','_');
s = regexprep(s,'[^A-Za-z0-9_\-]','_');
s = regexprep(s,'_+','_');
s = regexprep(s,'^[\._]+','');
s = regexprep(s,'[\._]+$','');
if isempty(s), s = 'export'; end
maxLen = 60;
if numel(s) > maxLen, s = s(1:maxLen); end
end

function A = flipud_any(A)
if isempty(A), return; end
if ndims(A) == 2
    A = flipud(A);
elseif ndims(A) == 3
    A = A(end:-1:1,:,:);
else
    error('flipud_any supports 2D or 3D arrays only.');
end
end

function s = strtrimSafe(x)
try
    if isempty(x)
        s = '';
    else
        s = strtrim(char(x));
    end
catch
    s = '';
end
end

function v = safeNum(str, fallback)
v = str2double(str);
if isnan(v) || ~isfinite(v)
    v = fallback;
end
end

function v = logicalCellValue(x)
try
    if islogical(x)
        v = x;
    elseif isnumeric(x)
        v = (x ~= 0);
    elseif ischar(x) || isstring(x)
        s = lower(strtrim(char(x)));
        v = any(strcmp(s, {'1','true','yes','y','on'}));
    else
        v = logical(x);
    end
catch
    v = false;
end
end

    function side = getPacapSideForRow(S, rowIdx, G, row)
side = 'Unknown';

% 1) direct row assignment
try
    if isfield(S,'rowPacapSide') && rowIdx >= 1 && rowIdx <= numel(S.rowPacapSide)
        s = strtrimSafe(S.rowPacapSide{rowIdx});
        if strcmpi(s,'L'), s = 'Left'; end
        if strcmpi(s,'R'), s = 'Right'; end
        if any(strcmpi(s,{'Left','Right'}))
            side = s;
            return;
        end
    end
catch
end

% 2) reuse PACAP side from sibling row with same animal/session/scan or same bundle
try
    refMeta   = extractMetaFromSources(row{2}, row{6}, row{7}, row{8});
    refBundle = strtrimSafe(row{8});

    for rr = 1:size(S.subj,1)
        if rr == rowIdx
            continue;
        end

        sibSide = 'Unknown';
        try
            if isfield(S,'rowPacapSide') && rr >= 1 && rr <= numel(S.rowPacapSide)
                sibSide = strtrimSafe(S.rowPacapSide{rr});
                if strcmpi(sibSide,'L'), sibSide = 'Left'; end
                if strcmpi(sibSide,'R'), sibSide = 'Right'; end
            end
        catch
            sibSide = 'Unknown';
        end

        if ~any(strcmpi(sibSide,{'Left','Right'}))
            continue;
        end

        sameBundle = false;
        try
            rrBundle = strtrimSafe(S.subj{rr,8});
            if ~isempty(refBundle) && ~isempty(rrBundle) && strcmpi(refBundle, rrBundle)
                sameBundle = true;
            end
        catch
        end

        sameMeta = false;
        try
            rrMeta = extractMetaFromSources(S.subj{rr,2}, S.subj{rr,6}, S.subj{rr,7}, S.subj{rr,8});
            sameMeta = strcmpi(strtrimSafe(rrMeta.animalID), strtrimSafe(refMeta.animalID)) && ...
                       metaLooseFieldMatch(rrMeta.session, refMeta.session) && ...
                       metaLooseFieldMatch(rrMeta.scanID,  refMeta.scanID);
        catch
        end

        if sameBundle || sameMeta
            side = sibSide;
            return;
        end
    end
catch
end

% 3) fallback: bundle-stored side
try
    s = upper(strtrimSafe(G.injectionSide));
    if strcmp(s,'L') || strcmp(s,'LEFT')
        side = 'Left';
        return;
    elseif strcmp(s,'R') || strcmp(s,'RIGHT')
        side = 'Right';
        return;
    end
catch
end

% 4) fallback: infer from filenames/text
try
    txt = upper([strtrimSafe(row{2}) ' ' strtrimSafe(row{6}) ' ' strtrimSafe(row{7}) ' ' strtrimSafe(row{8})]);
    if contains(txt,'LEFT') || contains(txt,'_L_')
        side = 'Left';
        return;
    elseif contains(txt,'RIGHT') || contains(txt,'_R_')
        side = 'Right';
        return;
    end
catch
end
end

function Rm = makeMapRenderStruct(S)
Rm = struct();
Rm.threshold = 0;
Rm.caxis = S.mapCaxis;
Rm.alphaModOn = S.mapAlphaModOn;
Rm.modMin = S.mapModMin;
Rm.modMax = S.mapModMax;
Rm.blackBody = S.mapBlackBody;
Rm.colormapName = S.mapColormap;
Rm.flipUDPreview = true;
end

function sel = clampSelRows(sel, nRows)
if isempty(sel)
    sel = [];
    return;
end
sel = unique(sel(:)');
sel = sel(sel>=1 & sel<=nRows);
end

function tf = logicalCol(tbl, col)
tf = true(size(tbl,1),1);
for i = 1:size(tbl,1)
    try
        tf(i) = logical(tbl{i,col});
    catch
        tf(i) = true;
    end
end
end

function idx = findActiveROIRowsGA(subj)
idx = [];
for i = 1:size(subj,1)
    if ~logicalCellValue(subj{i,1})
        continue;
    end
    roiFile = strtrimSafe(subj{i,7});
    if ~isempty(roiFile) && exist(roiFile,'file') == 2
        idx(end+1) = i; %#ok<AGROW>
    end
end
end

      function [idx, missingIdx] = findActiveBundleRowsGA(S)
    idx = [];
    missingIdx = [];

    dispRows = findBundleDisplayRowsGA(S);

    for i = 1:numel(dispRows)
        r = dispRows(i);
        key = makeBundleEntityKeyForRow(S, r);

        if isempty(key)
            continue;
        end

        if ~entityUseStateForKey(S, key)
            continue;
        end

        bf = strtrimSafe(S.subj{r,8});
        if isempty(bf)
            try
                bf = resolveGroupBundlePath(S, S.subj(r,:));
            catch
                bf = '';
            end
        end

        if isempty(bf) || ~isScmGroupBundleFile(bf)
            missingIdx = [missingIdx getRowsForBundleEntityKey(S, key)]; %#ok<AGROW>
        else
            idx(end+1) = r; %#ok<AGROW>
        end
    end

    missingIdx = unique(missingIdx,'stable');
end

function col = colAsStr(C, j)
col = cell(size(C,1),1);
for i = 1:size(C,1)
    col{i} = strtrimSafe(C{i,j});
end
end

function u = uniqueStable(C)
C = C(:);
C = C(~cellfun(@isempty,C));
u = {};
for i = 1:numel(C)
    if ~any(strcmpi(u, C{i}))
        u{end+1,1} = C{i}; %#ok<AGROW>
    end
end
end

function S = rememberGroupCondPair(S, groupName, condName)
groupName = strtrimSafe(groupName);
condName  = strtrimSafe(condName);

if isempty(groupName) || isempty(condName)
    return;
end

try
    if isa(S.groupToCondMap,'containers.Map')
        S.groupToCondMap(upper(groupName)) = condName;
    end
catch
end
end

function S = sanitizeTableStruct(S)
if isempty(S.subj), return; end
if size(S.subj,2) < 9, S.subj(:,end+1:9) = {''}; end
if size(S.subj,2) > 9, S.subj = S.subj(:,1:9); end

for r = 1:size(S.subj,1)
    if isempty(S.subj{r,1}) || ...
            ~(islogical(S.subj{r,1}) || isnumeric(S.subj{r,1}) || ischar(S.subj{r,1}) || isstring(S.subj{r,1}))
        S.subj{r,1} = true;
    else
        S.subj{r,1} = logicalCellValue(S.subj{r,1});
    end

    meta = extractMetaFromSources(S.subj{r,2}, S.subj{r,6}, S.subj{r,7}, S.subj{r,8});

    if strcmpi(meta.animalID,'N/A') || isempty(meta.animalID)
        if isempty(strtrimSafe(S.subj{r,2}))
            S.subj{r,2} = ['S' num2str(r)];
        else
            S.subj{r,2} = strtrimSafe(S.subj{r,2});
        end
    else
        S.subj{r,2} = meta.animalID;
    end

    if isempty(strtrimSafe(S.subj{r,3})), S.subj{r,3} = S.defaultGroup; end
    if isempty(strtrimSafe(S.subj{r,4})), S.subj{r,4} = S.defaultCond;  end

    if isempty(strtrimSafe(S.subj{r,9})) && ~logicalCellValue(S.subj{r,1})
        S.subj{r,9} = 'Not used';
    end
end
end

function out = mergeUniqueStable(a,b)
if isempty(a), a={}; end
if isempty(b), b={}; end
out = a(:).';
for i = 1:numel(b)
    if isempty(b{i}), continue; end
    if ~any(strcmpi(out,b{i}))
        out{end+1} = b{i}; %#ok<AGROW>
    end
end
end

    function V = subjToUITable(subj)
n = size(subj,1);
V = cell(n,9);

for i = 1:n
    meta = extractMetaFromSources(subj{i,2}, subj{i,6}, subj{i,7}, subj{i,8});

    V{i,1} = logicalCellValue(subj{i,1});
    V{i,2} = meta.animalID;
    V{i,3} = meta.session;
    V{i,4} = displayScanID(meta.scanID);
    V{i,5} = strtrimSafe(subj{i,3});
    V{i,6} = strtrimSafe(subj{i,4});
    V{i,7} = simplifyROIFileLabel(strtrimSafe(subj{i,7}));
    V{i,8} = bundlePresenceLabel(strtrimSafe(subj{i,8}));
    V{i,9} = deriveRowStatus(subj(i,:));
end
end

function subj = applyUITableToSubj(subj, V)
n = size(V,1);

if isempty(subj)
    subj = cell(n,9);
end

if size(subj,1) < n
    subj(end+1:n,1:9) = {''};
end
if size(subj,1) > n
    subj = subj(1:n,:);
end

for i = 1:n
    subj{i,1} = logicalCellValue(V{i,1});
    subj{i,2} = strtrimSafe(V{i,2});
    subj{i,3} = strtrimSafe(V{i,5});
    subj{i,4} = strtrimSafe(V{i,6});

    if isempty(subj{i,5}), subj{i,5} = ''; end
    if isempty(subj{i,6}), subj{i,6} = ''; end
    if isempty(subj{i,7}), subj{i,7} = ''; end
    if isempty(subj{i,8}), subj{i,8} = ''; end
    if isempty(subj{i,9}), subj{i,9} = ''; end
end
end

   function s = deriveRowStatus(row)
    roi    = '';
    bundle = '';
    st     = '';
    use    = true;

    try, roi    = strtrimSafe(row{7}); catch, end
    try, bundle = strtrimSafe(row{8}); catch, end
    try, st     = lower(strtrimSafe(row{9})); catch, end
    try, use    = logicalCellValue(row{1}); catch, end

    % IMPORTANT:
    % Do not call exist(...) on every redraw for network paths.
    % Just treat non-empty paths as "set".
    roiSet    = ~isempty(roi);
    bundleSet = ~isempty(bundle);

    if contains(st,'excluded')
        s = 'Excluded';
    elseif ~use
        s = 'Not used';
    elseif roiSet || bundleSet
        s = 'OK';
    elseif isempty(roi) && isempty(bundle)
        s = 'Not set';
    else
        s = 'Missing';
    end
end


function [hAuto,hZero,hStep,hYmin,hYmax,hYminM,hYminP,hYmaxM,hYmaxP] = mkYControlsStepCompact(parent, y0, label, cfg, C, cbEdit, cbYminM, cbYminP, cbYmaxM, cbYmaxP)
bg = get(parent,'BackgroundColor');
rowH = 0.18;

uicontrol(parent,'Style','text','String',[label ':'], ...
    'Units','normalized','Position',[0.02 y0 0.08 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hAuto = uicontrol(parent,'Style','checkbox','String','Auto', ...
    'Units','normalized','Position',[0.11 y0 0.12 rowH], ...
    'Value',double(cfg.auto), 'BackgroundColor',bg,'ForegroundColor','w','Callback',cbEdit);

hZero = uicontrol(parent,'Style','checkbox','String','Force 0', ...
    'Units','normalized','Position',[0.24 y0 0.14 rowH], ...
    'Value',double(cfg.forceZero), 'BackgroundColor',bg,'ForegroundColor','w','Callback',cbEdit);

uicontrol(parent,'Style','text','String','Step:', ...
    'Units','normalized','Position',[0.40 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hStep = uicontrol(parent,'Style','edit','String',num2str(cfg.step), ...
    'Units','normalized','Position',[0.46 y0+0.01 0.06 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

uicontrol(parent,'Style','text','String','Ymin:', ...
    'Units','normalized','Position',[0.54 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmin = uicontrol(parent,'Style','edit','String',num2str(cfg.ymin), ...
    'Units','normalized','Position',[0.60 y0+0.01 0.08 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

hYminM = uicontrol(parent,'Style','pushbutton','String','-', ...
    'Units','normalized','Position',[0.69 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYminM);

hYminP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.73 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYminP);

uicontrol(parent,'Style','text','String','Ymax:', ...
    'Units','normalized','Position',[0.78 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmax = uicontrol(parent,'Style','edit','String',num2str(cfg.ymax), ...
    'Units','normalized','Position',[0.84 y0+0.01 0.07 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

hYmaxM = uicontrol(parent,'Style','pushbutton','String','-', ...
    'Units','normalized','Position',[0.92 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYmaxM);

hYmaxP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.96 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',cbYmaxP);
end

function fixAxesInset(ax)
try
    ti = get(ax,'TightInset');
    li = [max(ti(1),0.02) max(ti(2),0.02) max(ti(3),0.02) max(ti(4),0.02)];
    set(ax,'LooseInset',li);
catch
end
end

function [bg,fg] = previewColors(styleName)
if strcmpi(styleName,'Dark')
    bg = [0 0 0];
    fg = [1 1 1];
else
    bg = [1 1 1];
    fg = [0 0 0];
end
end

function styleAxesMode(ax, styleName, showGrid)
[bg,fg] = previewColors(styleName);
set(ax,'Color',bg,'XColor',fg,'YColor',fg);
if strcmpi(styleName,'Dark')
    try, set(ax,'GridColor',[0.7 0.7 0.7]); catch, end
    try, set(ax,'MinorGridColor',[0.8 0.8 0.8]); catch, end
else
    try, set(ax,'GridColor',[0.2 0.2 0.2]); catch, end
    try, set(ax,'MinorGridColor',[0.3 0.3 0.3]); catch, end
end
try, set(ax,'GridAlpha',0.18); catch, end
try, set(ax,'MinorGridAlpha',0.10); catch, end
if showGrid
    grid(ax,'on');
else
    grid(ax,'off');
end
box(ax,'off');
end

function recolorAxesText(ax, styleName)
[~,fg] = previewColors(styleName);
try, set(ax,'XColor',fg,'YColor',fg); catch, end
try, set(get(ax,'Title'),'Color',fg); catch, end
try, set(get(ax,'XLabel'),'Color',fg); catch, end
try, set(get(ax,'YLabel'),'Color',fg); catch, end
end

function styleColorbarMode(cb, styleName)
[~,fg] = previewColors(styleName);
try, set(cb,'Color',fg); catch, end
try, set(get(cb,'Label'),'Color',fg); catch, end
try, set(cb,'Box','off'); catch, end
end

function styleLegendMode(lg, styleName)
[bg,fg] = previewColors(styleName);
try, set(lg,'TextColor',fg); catch, end
try, set(lg,'Color',bg); catch, end
try, set(lg,'EdgeColor','none'); catch, end
end

function moveTitleUp(ax, yPos)
if nargin < 2, yPos = 1.09; end
th = get(ax,'Title');
set(th,'Units','normalized');
pos = get(th,'Position');
pos(2) = yPos;
set(th,'Position',pos);
end

function y = titleYForStyle(styleName)
if strcmpi(styleName,'Light')
    y = 1.01;
else
    y = 1.05;
end
end

function deleteAllColorbars(h)
try
    delete(findall(h,'Type','ColorBar'));
catch
    try, delete(findall(h,'Tag','Colorbar')); catch, end
end
end

function hardClearAx(ax, styleName, showGrid, ttl)
if isempty(ax) || ~ishandle(ax), return; end

try
    lg = legend(ax);
    if ishghandle(lg), delete(lg); end
catch
end

try, set(ax,'NextPlot','replace'); catch, end
try, hold(ax,'off'); catch, end

try
    cla(ax,'reset');
catch
    try, cla(ax); catch, end
    try, delete(allchild(ax)); catch, end
end

styleAxesMode(ax, styleName, showGrid);
recolorAxesText(ax, styleName);
title(ax, ttl, 'FontWeight','bold');
moveTitleUp(ax, titleYForStyle(styleName));
fixAxesInset(ax);
end

function stylePreviewPanels(S)
isLight = strcmpi(S.previewStyle,'Light');

if isLight
    bgMain = [1 1 1];
    bgTop  = [0.96 0.96 0.96];
    fg     = [0 0 0];
    editBg = [1 1 1];
    btnBg  = [0.86 0.86 0.86];
else
    bgMain = S.C.bg;
    bgTop  = S.C.panel2;
    fg     = [1 1 1];
    editBg = S.C.editBg;
    btnBg  = [0.14 0.14 0.14];
end

set(S.hPrevBG,  'BackgroundColor',bgMain);
set(S.hPrevTop, 'BackgroundColor',bgTop, 'ForegroundColor',fg);

setIfHandle(S,'hPrevExportTop','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');
setIfHandle(S,'hPrevExportBot','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');
setIfHandle(S,'hPrevExportBoth','BackgroundColor',btnBg,'ForegroundColor',fg,'FontWeight','bold');

setIfHandle(S,'hPrevLblView','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hPrevLblWin','BackgroundColor',bgTop,'ForegroundColor',fg);

setIfHandle(S,'hPrevStyle','BackgroundColor',editBg,'ForegroundColor',fg);
setIfHandle(S,'hPrevGrid','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hSmoothEnable','BackgroundColor',bgTop,'ForegroundColor',fg);
setIfHandle(S,'hSmoothWin','BackgroundColor',editBg,'ForegroundColor',fg);
end

function setIfHandle(S, fieldName, varargin)
if isfield(S,fieldName)
    h = S.(fieldName);
    if ishghandle(h)
        try
            set(h, varargin{:});
        catch
        end
    end
end
end




    function colors = buildTableRowColors(subj)
neutral  = [0.12 0.12 0.12];
excluded = [0.30 0.12 0.12];

n = size(subj,1);
if n <= 0
    colors = [neutral; neutral];
    return;
end

colors = repmat(neutral, max(n,2), 1);

for i = 1:n
    use  = logicalCellValue(subj{i,1});
    st   = lower(strtrimSafe(subj{i,9}));
    grp  = strtrimSafe(subj{i,3});
    cond = strtrimSafe(subj{i,4});

    if contains(st,'excluded') || ~use
        colors(i,:) = excluded;
    else
        colors(i,:) = groupRowColorGA(grp, cond);
    end
end
end


function colors = buildTableRowColorsDisplay(subj, minRows)
if nargin < 2, minRows = 0; end

neutral  = [0.12 0.12 0.12];
excluded = [0.30 0.12 0.12];

n = size(subj,1);
nOut = max(max(n,2), minRows);
colors = repmat(neutral, nOut, 1);

for i = 1:n
    use  = logicalCellValue(subj{i,1});
    st   = lower(strtrimSafe(subj{i,9}));
    grp  = strtrimSafe(subj{i,3});
    cond = strtrimSafe(subj{i,4});

    if contains(st,'excluded') || ~use
        colors(i,:) = excluded;
    else
        colors(i,:) = groupRowColorGA(grp, cond);
    end
end
end



%%% =====================================================================
%%% NESTED CALLBACKS CONTINUED
%%% =====================================================================

    function onExportMapSideTable(~,~)
    S0 = guidata(hFig);

    data = get(S0.hMapSideTable,'Data');
    if isempty(data)
        errordlg('No table data to export.','Export Table');
        return;
    end

    startDir = getAnalysedBrowseDir(S0);
    [f,p] = uiputfile({'*.csv','CSV (*.csv)'}, ...
        'Save Side Assignment Table', ...
        fullfile(startDir, 'GroupMap_SideAssignment.csv'));

    if isequal(f,0)
        return;
    end

    hdr = get(S0.hMapSideTable,'ColumnName');
    C = [hdr; data];
    outFile = fullfile(p,f);

    setStatus(false);
    setStatusText('Exporting side assignment table...');
    drawnow;

    try
        writeCellCSV_UTF8(outFile, C);
        setStatusText(['Side assignment table saved: ' outFile]);
    catch ME
        setStatusText(['Side assignment table export failed: ' ME.message]);
        errordlg(ME.message,'Export Table');
    end

    setStatus(true);
end
    
  function onExportGroupMapPNG(~,~)
    S0 = guidata(hFig);

    if ~isfield(S0,'lastMAP') || isempty(fieldnames(S0.lastMAP))
        errordlg('Compute a group map first.','Export Group Map PNG');
        return;
    end

    startDir = getAnalysedBrowseDir(S0);

    pushMapExportLog('Preparing current group-map PNG export...', true);

    try
        [D, S0] = computeCurrentGroupMapDisplayGA(S0, true);
        guidata(hFig,S0);
    catch ME
        pushMapExportLog(['PNG export failed: ' ME.message], false);
        errordlg(ME.message,'Export Group Map PNG');
        return;
    end

    defName = sanitizeFilename(D.title);
    if isempty(defName)
        defName = ['GroupMap_' datestr(now,'yyyymmdd_HHMMSS')];
    end

    [f,p] = uiputfile({'*.png','PNG (*.png)'}, ...
        'Save Group Map PNG', ...
        fullfile(startDir, [defName '.png']));

    if isequal(f,0)
        pushMapExportLog('PNG export cancelled.', false);
        return;
    end

    outFile = fullfile(p,f);

    setStatus(false);
    setStatusText('Exporting group map PNG...');
    drawnow;

    try
        exportMapDisplayPNG(outFile, D, 'Dark');
        S0.opt.startDir = p;
        guidata(hFig,S0);

       pushMapExportLog(['Done saved: ' outFile], false);
        setStatusText(['Group map PNG saved: ' outFile]);
    catch ME
        pushMapExportLog(['PNG export failed: ' ME.message], false);
        setStatusText(['Group map PNG export failed: ' ME.message]);
        errordlg(ME.message,'Export Group Map PNG');
    end

    setStatus(true);
end

    function onExportGroupMapPPT(~,~)
    S0 = guidata(hFig);

    if ~canUsePptApiGA()
        errordlg('PowerPoint export requires mlreportgen.ppt support in this MATLAB installation.','Export Group Map PPT');
        return;
    end

    a = inputdlg({ ...
        'Injection start (sec). Empty if unknown:', ...
        'Window length (sec) (default 60):', ...
        'Max minutes to export (empty = all available):'}, ...
        'Export Group Map PPT / Series', 1, {'', '60', ''});

    if isempty(a)
        return;
    end

    injSec = str2double(strtrim(a{1}));
    if ~isfinite(injSec)
        injSec = NaN;
    end

    winLen = str2double(strtrim(a{2}));
    if ~isfinite(winLen) || winLen <= 0
        winLen = 60;
    end

    maxMin = str2double(strtrim(a{3}));
    if ~isfinite(maxMin) || maxMin <= 0
        maxMin = NaN;
    end

    startDir = getAnalysedBrowseDir(S0);
    defName  = ['GroupMapSeries_' datestr(now,'yyyymmdd_HHMMSS') '.pptx'];

    [f,p] = uiputfile({'*.pptx','PowerPoint (*.pptx)'}, ...
        'Save Group Map PowerPoint Series', ...
        fullfile(startDir, defName));

    if isequal(f,0)
        return;
    end

    outFile = fullfile(p,f);
stamp   = datestr(now,'yyyymmdd_HHMMSSFFF');

% IMPORTANT:
% Store individual map PNGs next to the PPT, like SCM GUI export.
% Do not use tempdir, otherwise the individual exported panels are lost.
[~, pptBase, ~] = fileparts(outFile);
tmpRoot = fullfile(p, [pptBase '_individual_PNGs']);

oldState   = struct();
tilePNGs   = {};
tileLBLs   = {};
lastRender = struct();

    setStatus(false);
    setStatusText('Exporting group map PPT series...');
    try
        pushMapExportLog('Starting PPT export / series export...', true);
    catch
    end
    drawnow;

    try
        if exist(tmpRoot,'dir') ~= 7
            mkdir(tmpRoot);
        end

        oldState = captureMapSeriesExportStateGA();

        % Force PSC recomputation mode for time-window export
        forceMapSeriesExportStateGA();

        % Make sure GUI is in map mode
        S1 = guidata(hFig);
        S1.mode = 'Group Maps';
        S1.activeTab = 'MAP';
        guidata(hFig,S1);
        try, set(S1.hMode,'Value',2); catch, end
        updateManualTabs();

        totalSec = estimateGroupSeriesTotalSecGA(guidata(hFig));
        if ~isfinite(totalSec) || totalSec <= 0
            error('Could not determine available duration from exported PSC group bundles.');
        end

        exportEndSec = totalSec;
        if isfinite(maxMin)
            exportEndSec = min(exportEndSec, maxMin * 60);
        end
        if ~isfinite(exportEndSec) || exportEndSec <= 0
            error('No valid export duration available.');
        end

        baseSec = getCurrentMapBaseWindowSecGA();

        % Build all windows:
        % 0-60, 60-120, ... and include a final partial window if needed.
        starts = 0:winLen:max(0, exportEndSec - winLen);
        if isempty(starts)
            starts = 0;
        end
        if starts(end) < exportEndSec - 1e-9
            if (starts(end) + winLen) < exportEndSec - 1e-9
                starts(end+1) = starts(end) + winLen; %#ok<AGROW>
            end
        end
        starts = unique(starts, 'stable');

        % Safety: remove any starts at/after the export end
        starts = starts(starts < exportEndSec);
        if isempty(starts)
            starts = 0;
        end

        nWin = numel(starts);

        for wi = 1:nWin
            s0 = starts(wi);
            s1 = min(s0 + winLen, exportEndSec);

            if s1 <= s0
                continue;
            end

            % Update current export window in state/UI
            S1 = guidata(hFig);
            S1.mapUseGlobalWindows = true;
            S1.mapGlobalBaseSec    = baseSec;
            S1.mapGlobalSigSec     = [s0 s1];
            guidata(hFig,S1);

            syncMapWindowUiGA();

            setStatusText(sprintf('Rendering window %d/%d (%.0f-%.0fs) ...', wi, nWin, s0, s1));
            try
                pushMapExportLog(sprintf('Rendering window %d/%d (%.0f-%.0fs) ...', wi, nWin, s0, s1), wi==1);
            catch
            end
            drawnow;

            % IMPORTANT:
            % Recompute the GROUP MAP for THIS window.
            % Do not only redraw the previous lastMAP.
            S1 = guidata(hFig);
            [mapIdxNow, ~] = findActiveBundleRowsGA(S1);

            if isempty(mapIdxNow)
                error('No valid bundle rows available for PPT export.');
            end

            subjNow = S1.subj(mapIdxNow,:);

            [Rtmp, cacheOut] = runPSCMapAnalysis(S1, subjNow, mapIdxNow, S1.cache);

            S1 = guidata(hFig);
            S1.cache   = cacheOut;
            S1.lastMAP = Rtmp;
            guidata(hFig,S1);

            updateMapTabPreview();
            S2 = guidata(hFig);

            if ~isfield(S2,'lastMapDisplay') || isempty(fieldnames(S2.lastMapDisplay)) || ...
               ~isfield(S2.lastMapDisplay,'map') || isempty(S2.lastMapDisplay.map)
                error('Could not build group-map display for window %.0f-%.0fs.', s0, s1);
            end

          % SCM-style label:
% Show signal window in seconds, baseline window in seconds,
% and PI timing in minutes relative to injection/PI zero.
lbl = makeSCMStyleTileLabelGA(s0, s1, baseSec, injSec);

            tileFile = fullfile(tmpRoot, sprintf('tile_%03d.png', wi));

            % Export each tile without per-tile title and without per-tile colorbar
            expOpt = struct();
            expOpt.showTitle    = false;
            expOpt.showColorbar = false;
            expOpt.axPos        = [0.03 0.04 0.94 0.92];

            exportMapDisplayPNG(tileFile, S2.lastMapDisplay, 'Dark', expOpt);

            lastRender = S2.lastMapDisplay.render;
            tilePNGs{end+1} = tileFile; %#ok<AGROW>
            tileLBLs{end+1} = lbl; %#ok<AGROW>
        end

        if isempty(tilePNGs)
            error('No group-map windows could be rendered.');
        end

        footerStr = sprintf('Base = %.0f-%.0fs | Window = %.0fs', ...
            baseSec(1), baseSec(2), winLen);

        % -----------------------------------------------------------------
% Editable PPT export:
%   - each brain/map tile is inserted as an individual Picture object
%   - labels/footer are editable PPT text boxes
%   - individual PNGs remain saved beside the PPT
% -----------------------------------------------------------------
Sfinal = guidata(hFig);

[animalIDsUsed, animalDetailsUsed] = getGroupMapAnimalsUsedGA(Sfinal);

footerStr = makeGroupMapPPTFooterGA( ...
    Sfinal, ...
    baseSec, ...
    winLen, ...
    injSec, ...
    animalIDsUsed);

setStatusText('Building editable PowerPoint with individual map panels...');
try
    pushMapExportLog('Building editable PowerPoint with individual map panels...', false);
catch
end
drawnow;

writeGroupMapSeriesPPTEditableGA( ...
    outFile, ...
    tilePNGs, ...
    tileLBLs, ...
    Sfinal, ...
    footerStr, ...
    lastRender, ...
    tmpRoot);

        try
            pushMapExportLog(['Done saved: ' outFile], false);
        catch
        end
        setStatusText(['Group map PPT series saved: ' outFile]);
        drawnow;

    catch ME
        try
            restoreMapSeriesExportStateGA(oldState);
        catch
        end

    

        try
            pushMapExportLog(['PPT export failed: ' ME.message], false);
        catch
        end
        setStatusText(['Group map PPT export failed: ' ME.message]);
        setStatus(true);
        errordlg(ME.message,'Export Group Map PPT');
        return;
    end

    try
        restoreMapSeriesExportStateGA(oldState);
    catch
    end

   

    setStatus(true);
end

function d = getAnalysedBrowseDir(S)
    pref = getPreferredPacapRootDir(S);
if ~isempty(pref) && exist(pref,'dir') == 7
    d = pref;
    return;
end
d = '';

try
    if isfield(S,'opt') && isfield(S.opt,'studio') && isstruct(S.opt.studio)
        P = studio_resolve_paths(S.opt.studio, 'GroupAnalysis', '');
        d = P.analysedRoot;
    end
catch
    d = '';
end

if isempty(d)
    try
        d = guessAnalysedRoot(getSmartBrowseDir(S,'add'));
    catch
        d = '';
    end
end

if isempty(d) || exist(d,'dir') ~= 7
    d = pwd;
end
end

    function exportMapDisplayPNG(outFile, D, styleName, opts)
if nargin < 3 || isempty(styleName)
    styleName = 'Dark';
end

if nargin < 4 || isempty(opts)
    opts = struct();
end

if ~isfield(opts,'showTitle'),    opts.showTitle = true; end
if ~isfield(opts,'showColorbar'), opts.showColorbar = true; end

if ~isfield(opts,'axPos') || isempty(opts.axPos)
    if opts.showColorbar
        opts.axPos = [0.08 0.10 0.72 0.78];
    else
        opts.axPos = [0.04 0.04 0.92 0.92];
    end
end

[figBg,fg] = previewColors(styleName);

f = figure('Visible','off', ...
    'Color',figBg, ...
    'InvertHardcopy','off', ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Renderer','opengl');

set(f,'Position',[100 100 1500 950]);

ax = axes('Parent',f,'Units','normalized','Position',opts.axPos);

cbPos = [];
if opts.showColorbar
    cbPos = [0.83 0.10 0.022 0.78];
end

renderPSCOverlay(ax, D.underlay, D.map, D.render, styleName, opts.showColorbar, cbPos);
recolorAxesText(ax, styleName);

if opts.showTitle
    title(ax, D.title, 'Color', fg, 'FontWeight','bold');
    moveTitleUp(ax, titleYForStyle(styleName));
else
    title(ax,'');
end

set(f,'PaperPositionMode','auto');
print(f, outFile, '-dpng', '-r250');
close(f);
end
    

    function exportSingleGroupMapPPT(outFile, pngFile, slideTitle)
    if ~ispc || exist('actxserver','file') ~= 2
        error('PowerPoint export currently requires Windows MATLAB with COM support.');
    end

    ppt = [];
    pres = [];

    try
        if exist(outFile,'file') == 2
            delete(outFile);
        end

        ppt = actxserver('PowerPoint.Application');
        set(ppt,'Visible',1);

        presentations = get(ppt,'Presentations');
        pres = invoke(presentations,'Add');

        slides = get(pres,'Slides');
        slide = invoke(slides,'Add',1,12);   % 12 = blank slide

        pageW = get(pres.PageSetup,'SlideWidth');
        pageH = get(pres.PageSetup,'SlideHeight');

        try
            set(slide,'FollowMasterBackground',0);
            bgFill = get(slide.Background,'Fill');
            invoke(bgFill,'Solid');
            set(bgFill.ForeColor,'RGB',0);
        catch
        end

        titleLeft = 18;
        titleTop  = 8;
        titleW    = pageW - 36;
        titleH    = 30;

        shapes = get(slide,'Shapes');

        tb = invoke(shapes,'AddTextbox',1,titleLeft,titleTop,titleW,titleH);
        tr = get(get(tb,'TextFrame'),'TextRange');
        set(tr,'Text',slideTitle);
        set(tr.Font,'Name','Arial');
        set(tr.Font,'Size',22);
        set(tr.Font,'Bold',1);
        try
            set(tr.Font.Color,'RGB',16777215);
        catch
        end

        pic = invoke(shapes,'AddPicture',pngFile,0,1,0,0,-1,-1);

        topMargin  = 46;
        leftMargin = 18;
        botMargin  = 18;
        maxW = pageW - 2*leftMargin;
        maxH = pageH - topMargin - botMargin;

        pw = double(get(pic,'Width'));
        ph = double(get(pic,'Height'));
        sc = min(maxW / max(eps,pw), maxH / max(eps,ph));

        set(pic,'Width', pw * sc);
        set(pic,'Height', ph * sc);
        set(pic,'Left', leftMargin + 0.5*(maxW - get(pic,'Width')));
        set(pic,'Top',  topMargin + 0.5*(maxH - get(pic,'Height')));

        invoke(pres,'SaveAs',outFile);
        invoke(pres,'Close');
        invoke(ppt,'Quit');
        delete(ppt);

    catch ME
        try
            if ~isempty(pres)
                invoke(pres,'Close');
            end
        catch
        end
        try
            if ~isempty(ppt)
                invoke(ppt,'Quit');
            end
        catch
        end
        try
            if ~isempty(ppt)
                delete(ppt);
            end
        catch
        end
        rethrow(ME);
    end
end

  function onRun(~,~)
    syncSubjFromTable();
    S0 = guidata(hFig);

      runTab = upper(strtrimSafe(S0.activeTab));

    % Functional Connectivity tab has its own loader and does not require
    % the ROI / SCM subject table to be populated.
    if strcmpi(runTab,'FC')
        onComputeGroupFC([],[]);
        return;
    end

    if isempty(S0.subj)
        errordlg('Add subject files first.','Group Analysis');
        return;
    end

    roiIdx = findActiveROIRowsGA(S0.subj);
    [mapIdx, mapMissingIdx] = findActiveBundleRowsGA(S0); %#ok<ASGLU>

    % -------------------------------------------------------------
    % Run button behavior:
    %   MAP tab              -> Group Maps only
    %   ROI / PREV / STATS   -> ROI Timecourse / metric analysis only
    % -------------------------------------------------------------
    preferMaps = strcmpi(runTab,'MAP');

    % -------------------------------------------------------------
    % Pull current UI values into S0 WITHOUT calling callbacks
    % (important: avoid map preview/bundle resolution during ROI run)
    % -------------------------------------------------------------

    % ---- ROI settings ----
    try, S0.tc_computePSC     = logical(get(S0.hTC_ComputePSC,'Value')); catch, end
    try, S0.tc_baseMin0       = safeNum(get(S0.hBase0,'String'),    S0.tc_baseMin0); end
    try, S0.tc_baseMin1       = safeNum(get(S0.hBase1,'String'),    S0.tc_baseMin1); end
    try, S0.tc_injMin0        = safeNum(get(S0.hInj0,'String'),     S0.tc_injMin0); end
    try, S0.tc_injMin1        = safeNum(get(S0.hInj1,'String'),     S0.tc_injMin1); end
    try, S0.tc_peakSearchMin0 = safeNum(get(S0.hPkS0,'String'),     S0.tc_peakSearchMin0); end
    try, S0.tc_peakSearchMin1 = safeNum(get(S0.hPkS1,'String'),     S0.tc_peakSearchMin1); end
    try, S0.tc_plateauMin0    = safeNum(get(S0.hPlat0,'String'),    S0.tc_plateauMin0); end
    try, S0.tc_plateauMin1    = safeNum(get(S0.hPlat1,'String'),    S0.tc_plateauMin1); end
    try, S0.tc_peakWinMin     = safeNum(get(S0.hTC_PeakWin,'String'), S0.tc_peakWinMin); end
    try, S0.tc_trimPct        = safeNum(get(S0.hTC_Trim,'String'),  S0.tc_trimPct); end

    try
        mt = get(S0.hTC_Metric,'String');
        S0.tc_metric = mt{get(S0.hTC_Metric,'Value')};
    catch
    end

    % ---- style / preview settings ----
    try
        cm = get(S0.hColorMode,'String');
        S0.colorMode = cm{get(S0.hColorMode,'Value')};
    catch
    end

    try
        sc = get(S0.hColorScheme,'String');
        S0.colorScheme = sc{get(S0.hColorScheme,'Value')};
    catch
    end

    try, S0.tc_showSEM = logical(get(S0.hShowSEM,'Value')); catch, end
    try, S0.tc_showInjectionBox = logical(get(S0.hShowInjBox,'Value')); catch, end

    try, S0.manualGroupA = getSelectedPopupString(S0.hManGroupA); catch, end
    try, S0.manualGroupB = getSelectedPopupString(S0.hManGroupB); catch, end
    try, S0.manualColorA = get(S0.hManColorA,'Value'); catch, end
    try, S0.manualColorB = get(S0.hManColorB,'Value'); catch, end

    % ---- y-axis scaling ----
    try, S0.plotTop.auto      = logical(get(S0.hTopAuto,'Value')); catch, end
    try, S0.plotTop.forceZero = logical(get(S0.hTopZero,'Value')); catch, end
    try, S0.plotTop.step      = max(0, safeNum(get(S0.hTopStep,'String'), S0.plotTop.step)); catch, end
    try, S0.plotTop.ymin      = safeNum(get(S0.hTopYmin,'String'), S0.plotTop.ymin); catch, end
    try, S0.plotTop.ymax      = safeNum(get(S0.hTopYmax,'String'), S0.plotTop.ymax); catch, end

    try, S0.plotBot.auto      = logical(get(S0.hBotAuto,'Value')); catch, end
    try, S0.plotBot.forceZero = logical(get(S0.hBotZero,'Value')); catch, end
    try, S0.plotBot.step      = max(0, safeNum(get(S0.hBotStep,'String'), S0.plotBot.step)); catch, end
    try, S0.plotBot.ymin      = safeNum(get(S0.hBotYmin,'String'), S0.plotBot.ymin); catch, end
    try, S0.plotBot.ymax      = safeNum(get(S0.hBotYmax,'String'), S0.plotBot.ymax); catch, end

    try, set(S0.hTopStep,'String',num2str(S0.plotTop.step)); catch, end
    try, set(S0.hTopYmin,'String',num2str(S0.plotTop.ymin)); catch, end
    try, set(S0.hTopYmax,'String',num2str(S0.plotTop.ymax)); catch, end
    try, set(S0.hBotStep,'String',num2str(S0.plotBot.step)); catch, end
    try, set(S0.hBotYmin,'String',num2str(S0.plotBot.ymin)); catch, end
    try, set(S0.hBotYmax,'String',num2str(S0.plotBot.ymax)); catch, end

    % ---- stats settings ----
    try
        tt = get(S0.hTest,'String');
        S0.testType = tt{get(S0.hTest,'Value')};
    catch
    end

    try
        a = str2double(get(S0.hAlpha,'String'));
        if isfinite(a) && a > 0 && a < 1
            S0.alpha = a;
        else
            set(S0.hAlpha,'String',num2str(S0.alpha));
        end
    catch
    end

    try
        am = get(S0.hAnnotMode,'String');
        S0.annotMode = am{get(S0.hAnnotMode,'Value')};
    catch
    end

    try, S0.showPText = logical(get(S0.hShowPText,'Value')); catch, end

    % ---- map settings: ONLY read these if actually running MAP analysis ----
    if preferMaps
        try
            ms = get(S0.hMapSummary,'String');
            S0.mapSummary = ms{get(S0.hMapSummary,'Value')};
        catch
        end

        try
            src = get(S0.hMapSource,'String');
            S0.mapSource = src{get(S0.hMapSource,'Value')};
        catch
        end

        try, S0.mapUseGlobalWindows = logical(get(S0.hMapUseGlobalWin,'Value')); catch, end
        try, S0.mapGlobalBaseSec(1) = safeNum(get(S0.hMapBase0,'String'), S0.mapGlobalBaseSec(1)); catch, end
        try, S0.mapGlobalBaseSec(2) = safeNum(get(S0.hMapBase1,'String'), S0.mapGlobalBaseSec(2)); catch, end
        try, S0.mapGlobalSigSec(1)  = safeNum(get(S0.hMapSig0,'String'),  S0.mapGlobalSigSec(1));  catch, end
        try, S0.mapGlobalSigSec(2)  = safeNum(get(S0.hMapSig1,'String'),  S0.mapGlobalSigSec(2));  catch, end

        if S0.mapGlobalBaseSec(2) <= S0.mapGlobalBaseSec(1)
            S0.mapGlobalBaseSec(2) = S0.mapGlobalBaseSec(1) + 1;
            try, set(S0.hMapBase1,'String',num2str(S0.mapGlobalBaseSec(2))); catch, end
        end
        if S0.mapGlobalSigSec(2) <= S0.mapGlobalSigSec(1)
            S0.mapGlobalSigSec(2) = S0.mapGlobalSigSec(1) + 1;
            try, set(S0.hMapSig1,'String',num2str(S0.mapGlobalSigSec(2))); catch, end
        end

        try
            um = get(S0.hMapUnderlayMode,'String');
            S0.mapUnderlayMode = um{get(S0.hMapUnderlayMode,'Value')};
        catch
        end

        try, S0.mapSigma  = max(0, safeNum(get(S0.hMapSigma,'String'),  S0.mapSigma)); catch, end
        try, S0.mapModMin = safeNum(get(S0.hMapModMin,'String'), S0.mapModMin); catch, end
        try, S0.mapModMax = safeNum(get(S0.hMapModMax,'String'), S0.mapModMax); catch, end

        if ~isfinite(S0.mapModMin), S0.mapModMin = 0; end
        if ~isfinite(S0.mapModMax) || S0.mapModMax <= S0.mapModMin
            S0.mapModMax = S0.mapModMin + 1;
            try, set(S0.hMapModMax,'String',num2str(S0.mapModMax)); catch, end
        end

        try
            caxv = sscanf(get(S0.hMapCaxis,'String'), '%f');
            if numel(caxv) >= 2 && all(isfinite(caxv(1:2))) && caxv(2) ~= caxv(1)
                S0.mapCaxis = caxv(1:2).';
                if S0.mapCaxis(2) < S0.mapCaxis(1)
                    S0.mapCaxis = fliplr(S0.mapCaxis);
                end
            else
                set(S0.hMapCaxis,'String',sprintf('%g %g',S0.mapCaxis(1),S0.mapCaxis(2)));
            end
        catch
        end

        try, S0.mapBlackBody = logical(get(S0.hMapBlackBody,'Value')); catch, end

        try
            fm = get(S0.hMapFlipMode,'String');
            S0.mapFlipMode = fm{get(S0.hMapFlipMode,'Value')};
        catch
        end

        try
            cm2 = get(S0.hMapColormap,'String');
            S0.mapColormap = cm2{get(S0.hMapColormap,'Value')};
        catch
        end

        S0.mapAlphaModOn = true;
        S0.mapThreshold  = 0;
    end

    % -------------------------------------------------------------
    % Decide analysis type
    % -------------------------------------------------------------
    activeIdx = [];
    subjActive = {};

    if preferMaps
        if isempty(mapIdx)
            errordlg([ ...
                'No valid bundle rows found for group-map analysis.' newline ...
                'Use "Compute Group Maps" in the Group Maps tab after adding valid bundle files.' ], ...
                'Group Analysis');
            return;
        end

        S0.mode = 'Group Maps';
        try, set(S0.hMode,'Value',2); catch, end

        activeIdx = mapIdx;
        subjActive = S0.subj(activeIdx,:);

        if ~isempty(mapMissingIdx)
            setStatusText(sprintf([ ...
                'Computing group maps using %d valid bundle row(s). ' ...
                'Skipping %d active row(s) without bundle.' ], ...
                numel(mapIdx), numel(mapMissingIdx)));
        else
            setStatusText('Computing group maps... please wait.');
        end

    else
        if isempty(roiIdx)
            errordlg([ ...
                'No valid ROI rows found.' newline ...
                'Run Analysis in ROI / Preview / Statistics works only for ROI timecourse / metric analysis.' newline ...
                'For maps, use "Compute Group Maps" in the Group Maps tab.' ], ...
                'Group Analysis');
            return;
        end

        S0.mode = 'ROI Timecourse';
        try, set(S0.hMode,'Value',1); catch, end

        activeIdx = roiIdx;
        subjActive = S0.subj(activeIdx,:);

        setStatusText(sprintf('Running ROI timecourse analysis using %d valid ROI row(s)...', numel(activeIdx)));
    end

    S0.outlierKeys = {};
    S0.outlierInfo = {};
    guidata(hFig,S0);

    updateOutlierBox();
    setStatus(false);
    drawnow;

    try
        if strcmpi(S0.mode,'ROI Timecourse')
            [R, cacheOut] = runROITimecourseAnalysis(S0, subjActive, S0.cache);
            R.plotTop = S0.plotTop;
            R.plotBot = S0.plotBot;

            S0 = guidata(hFig);
            S0.cache = cacheOut;
            S0.lastROI = R;

            % ROI run:
            %   STATS -> stay in STATS
            %   ROI/PREV -> show PREVIEW
            if strcmpi(runTab,'STATS')
                S0.activeTab = 'STATS';
            else
                S0.activeTab = 'PREV';
            end

            guidata(hFig,S0);
            updateManualTabs();

            if strcmpi(S0.activeTab,'PREV')
                updatePreview();
            end

            setStatusText(sprintf('ROI analysis complete (%d row(s)).', size(subjActive,1)));

        else
            [R, cacheOut] = runPSCMapAnalysis(S0, subjActive, activeIdx, S0.cache);

            S0 = guidata(hFig);
            S0.cache = cacheOut;
            S0.lastMAP = R;
            S0.activeTab = 'MAP';

            guidata(hFig,S0);
            updateManualTabs();
            updateMapTabPreview();
            setStatusText(sprintf('Group map analysis complete (%d bundle row(s)).', size(subjActive,1)));
        end

    catch ME
        setStatusText(['Analysis failed: ' ME.message]);
        errordlg(ME.message,'Group Analysis');
    end

        setStatus(true);
  end

  function onExport(~,~)
    S0 = guidata(hFig);
    if isfield(S0,'activeTab') && strcmpi(S0.activeTab,'FC')
        onExportGroupFC([],[]);
        return;
    end
    R = struct();
    if strcmpi(S0.mode,'Group Maps')
        if isfield(S0,'lastMAP') && ~isempty(fieldnames(S0.lastMAP))
            R = S0.lastMAP;
        end
    else
        if isfield(S0,'lastROI') && ~isempty(fieldnames(S0.lastROI))
            R = S0.lastROI;
        end
    end

    if isempty(fieldnames(R))
        errordlg('Run analysis first.','Export');
        return;
    end

    outParent = uigetdir(getSmartBrowseDir(S0,'save'), 'Choose export folder (will create a subfolder)');
    if isequal(outParent,0), return; end

    defName = ['GroupAnalysis_' datestr(now,'yyyymmdd_HHMMSS')];
    answ = inputdlg({'Folder name:'},'Export Results',1,{defName});
    if isempty(answ), return; end
    folderName = sanitizeFilename(strtrim(answ{1}));
    if isempty(folderName), folderName = defName; end

    outFolder = fullfile(outParent, folderName);
    if ~exist(outFolder,'dir'), mkdir(outFolder); end

    save(fullfile(outFolder,'Results.mat'),'R','-v7.3');

    try
        if isfield(R,'metrics') && isfield(R.metrics,'table') && ~isempty(R.metrics.table)
            writeCellCSV_UTF8(fullfile(outFolder,'Metrics.csv'), R.metrics.table);
        end
    catch
    end

    setStatusText(['Exported: ' outFolder]);
end

    function onExportExcel(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);

        if isempty(S0.subj)
            errordlg('No rows available to export.','Export Excel');
            return;
        end

        startDir = getSmartBrowseDir(S0, 'save');
        defFile = fullfile(startDir, ['GroupAnalysisExport_' datestr(now,'yyyymmdd_HHMMSS') '.xlsx']);

        [f,p] = uiputfile({'*.xlsx','Excel workbook (*.xlsx)'}, ...
            'Save Group Analysis Excel', defFile);

        if isequal(f,0)
            return;
        end

        outFile = fullfile(p,f);

        setStatus(false);
        setStatusText('Exporting Excel workbook...');
        drawnow;

        try
            exportGroupAnalysisExcelWorkbook(outFile, S0);
            S0.opt.startDir = p;
            guidata(hFig,S0);
            setStatusText(['Excel exported: ' outFile]);
        catch ME
            setStatusText(['Excel export failed: ' ME.message]);
            errordlg(ME.message,'Export Excel');
        end

        setStatus(true);
    end

    function onExportPreviewPNG(which)
        S0 = guidata(hFig);
        if ~isfield(S0,'lastROI') || isempty(fieldnames(S0.lastROI))
    errordlg('Run ROI Timecourse analysis first.','Preview export');
    return;
end

        outDir = uigetdir(getSmartBrowseDir(S0,'save'),'Choose folder to save preview PNG(s)');
        if isequal(outDir,0), return; end

        defBase = ['Preview_' datestr(now,'yyyymmdd_HHMMSS')];
        answ = inputdlg({'Base file name:'},'Preview PNG export',1,{defBase});
        if isempty(answ), return; end
        baseName = sanitizeFilename(strtrim(answ{1}));
        if isempty(baseName), baseName = defBase; end

        try
            if which==1 || which==3
                exportPreviewPNG(fullfile(outDir, [baseName '_Top.png']), 1, S0);
            end
            if which==2 || which==3
                exportPreviewPNG(fullfile(outDir, [baseName '_Bottom.png']), 2, S0);
            end
            setStatusText(['Saved PNG(s) to: ' outDir]);
        catch ME
            setStatusText(['Export failed: ' ME.message]);
            errordlg(ME.message,'Preview export');
        end
    end

    function clearPreview()
        S0 = guidata(hFig);

        deleteAllColorbars(hFig);

        try
            axAll = findall(S0.hPrevBG,'Type','axes');
            for k = 1:numel(axAll)
                if axAll(k) ~= S0.ax1 && axAll(k) ~= S0.ax2
                    delete(axAll(k));
                end
            end
        catch
        end

        hardClearAx(S0.ax1, S0.previewStyle, S0.previewShowGrid, 'Top plot');
        hardClearAx(S0.ax2, S0.previewStyle, S0.previewShowGrid, 'Bottom plot');
    end

    function updatePreview()
      S0 = guidata(hFig);
clearPreview();

if ~isfield(S0,'lastROI') || isempty(fieldnames(S0.lastROI))
    return;
end

R = S0.lastROI;
        [~,fg] = previewColors(S0.previewStyle);

      

        t = R.tMin(:)';

        %%% ---------------- TOP PLOT ----------------
        hold(S0.ax1, 'on');
        styleAxesMode(S0.ax1, S0.previewStyle, S0.previewShowGrid);

        displayNames = getDisplayNamesFromR(R);
        leg = {};
        lineHs = [];
        allTop = [];

        for g = 1:numel(R.group)
            mu = R.group(g).mean(:)';
            se = R.group(g).sem(:)';

            if S0.tc_previewSmooth
                dtSec = median(diff(t)) * 60;
                mu = smooth1D_edgeCentered(mu, dtSec, S0.tc_previewSmoothWinSec);
                se = smooth1D_edgeCentered(se, dtSec, S0.tc_previewSmoothWinSec);
                se(se<0) = 0;
            end

            col = R.groupColors.(makeField(R.group(g).name));

            lineCol = col;
            fillCol = col;

           if strcmpi(S0.colorScheme,'PACAP/Vehicle') && strcmpi(displayNames{g},'Vehicle')
    lineCol = [0.40 0.40 0.40];
    fillCol = [0.78 0.78 0.78];
end

            if R.showSEM
                [hLine, ~] = shadedLineColored(S0.ax1, t, mu, se, lineCol, fillCol, S0.displaySemAlpha);
            else
                hLine = plot(S0.ax1, t, mu, 'LineWidth', 2.4, 'Color', lineCol);
            end

            lineHs = [lineHs hLine]; %#ok<AGROW>
            leg{end+1} = sprintf('%s (n=%d)', displayNames{g}, R.group(g).n); %#ok<AGROW>
            allTop = [allTop, mu, mu+se, mu-se]; %#ok<AGROW>
        end

        xlabel(S0.ax1, 'Time (min)', 'Color', fg);
        ylabel(S0.ax1, tern(R.unitsPercent, 'Signal change (%)', 'ROI signal (a.u.)'), 'Color', fg);
        title(S0.ax1, 'Mean ROI timecourse', 'Color', fg, 'FontWeight', 'bold');
        moveTitleUp(S0.ax1, titleYForStyle(S0.previewStyle));

        if ~isempty(lineHs)
            lg = legend(S0.ax1, lineHs, leg, 'Location', 'northwest', 'Box', 'off');
            styleLegendMode(lg, S0.previewStyle);
        end

        applyYLim(S0.ax1, allTop, S0.plotTop);

        if S0.tc_showInjectionBox
            drawInjectionPatch(S0.ax1, S0.tc_injMin0, S0.tc_injMin1, [0.60 0.60 0.60], 0.35);
        end

        recolorAxesText(S0.ax1, S0.previewStyle);
        fixAxesInset(S0.ax1);
        hold(S0.ax1, 'off');

        %%% ---------------- BOTTOM PLOT ----------------
        hold(S0.ax2, 'on');
        styleAxesMode(S0.ax2, S0.previewStyle, S0.previewShowGrid);

        gNames = R.groupNames;
        metricVals = R.metricVals(:);
        grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,3), 'UniformOutput', false);
        xTicks = 1:numel(gNames);

        allBot = [];
        rowX = nan(size(metricVals));

        for g = 1:numel(gNames)
            idxG = strcmpi(grpCol, gNames{g});
            idxRows = find(idxG & isfinite(metricVals));
            yAll = metricVals(idxRows);
            if isempty(yAll)
                continue;
            end

            col = R.groupColors.(makeField(gNames{g}));
            rowKeys = makeRowKeys(R.subjTable(idxRows,:));
            jitter = zeros(size(yAll));
            for ii = 1:numel(rowKeys)
                jitter(ii) = deterministicJitter(rowKeys{ii}, 0.18);
            end
            rowX(idxRows) = xTicks(g) + jitter;

            scatter(S0.ax2, rowX(idxRows), yAll, 70, col, 'filled', ...
                'MarkerEdgeColor', col, 'LineWidth', 0.8);

            plot(S0.ax2, [xTicks(g)-0.25 xTicks(g)+0.25], [mean(yAll) mean(yAll)], ...
                'LineWidth', 2.8, 'Color', col);

            allBot = [allBot; yAll(:)]; %#ok<AGROW>
        end

        set(S0.ax2, 'XLim', [0.5 numel(gNames)+0.5], 'XTick', xTicks, 'XTickLabel', displayNames);
        ylabel(S0.ax2, tern(R.unitsPercent, 'Signal change (%)', 'Metric (a.u.)'), 'Color', fg);
        title(S0.ax2, ['Metric: ' R.metricName], 'Color', fg, 'FontWeight', 'bold');
        moveTitleUp(S0.ax2, titleYForStyle(S0.previewStyle));

        applyYLim(S0.ax2, allBot, S0.plotBot);

        highlightOutliersOnScatter(S0.ax2, R, S0, rowX, S0.previewStyle);
        recolorAxesText(S0.ax2, S0.previewStyle);
        fixAxesInset(S0.ax2);

        if isfield(R, 'stats') && isfield(R.stats, 'p') && isfinite(R.stats.p)
            if strcmpi(S0.annotMode, 'Bottom only') || strcmpi(S0.annotMode, 'Both')
                annotateStatsBottom(S0.ax2, R, S0);
            end
            if strcmpi(S0.annotMode, 'Both')
                annotateStatsTopText(S0.ax1, R, S0);
            end
        end

        hold(S0.ax2, 'off');
        drawnow limitrate;
    end

%%% =====================================================================
%%% LOCAL HELPERS PART 2
%%% =====================================================================
function s = simplifyROIFileLabel(fp)
s = '';
fp = strtrimSafe(fp);
if isempty(fp)
    return;
end

[~,bn,~] = fileparts(fp);
bnL = lower(bn);

roiTok = regexp(bn, '(?i)(roi\s*[_-]*\d+)', 'tokens', 'once');
roiPart = '';
if ~isempty(roiTok)
    roiPart = regexprep(roiTok{1}, '[_-]+', '');
    roiPart = upper(strrep(roiPart,'roi','ROI'));
end

kind = '';
if contains(bnL,'target')
    kind = 'Target';
elseif contains(bnL,'ctrl') || contains(bnL,'control')
    kind = 'Ctrl';
elseif contains(bnL,'mask')
    kind = 'Mask';
elseif contains(bnL,'ref')
    kind = 'Ref';
else
    kind = 'ROI';
end

if ~isempty(roiPart)
    s = [roiPart ' ' kind];
else
    s = kind;
end
end

function s = bundlePresenceLabel(fp)
fp = strtrimSafe(fp);
if isempty(fp)
    s = '';
elseif exist(fp,'file') == 2
    s = 'Exists';
else
    s = 'Missing';
end
end
function applyYLim(ax, dataVec, plotCfg)
if isempty(dataVec), return; end
dataVec = dataVec(isfinite(dataVec));
if isempty(dataVec), return; end

if plotCfg.auto
    lo = min(dataVec);
    hi = max(dataVec);
    if plotCfg.forceZero, lo = 0; end
    if lo == hi
        lo = lo - 1;
        hi = hi + 1;
    else
        pad = 0.06 * (hi - lo);
        lo = lo - pad;
        hi = hi + pad;
        if plotCfg.forceZero, lo = 0; end
    end
    ylim(ax,[lo hi]);
else
    lo = plotCfg.ymin;
    hi = plotCfg.ymax;
    if plotCfg.forceZero, lo = 0; end
    if isfinite(lo) && isfinite(hi) && lo < hi
        ylim(ax,[lo hi]);
    end
end

step = plotCfg.step;
if ~isfinite(step) || step <= 0
    try, set(ax,'YTickMode','auto'); catch, end
    return;
end

yl = ylim(ax);
lo = yl(1);
hi = yl(2);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo, return; end

if plotCfg.forceZero
    t0 = 0;
else
    t0 = floor(lo/step)*step;
end
t1 = ceil(hi/step)*step;

ticks = t0:step:t1;
ticks = ticks(ticks >= lo-1e-9 & ticks <= hi+1e-9);

if numel(ticks) > 60
    try, set(ax,'YTickMode','auto'); catch, end
    return;
end

if ~isempty(ticks)
    try, set(ax,'YTick',ticks); catch, end
end
end

function h = drawInjectionPatch(ax, x0, x1, col, alphaVal)
if ~isfinite(x0) || ~isfinite(x1)
    h = [];
    return;
end
if x1 <= x0
    h = [];
    return;
end

yl = ylim(ax);
h = patch(ax,[x0 x1 x1 x0],[yl(1) yl(1) yl(2) yl(2)],col, ...
    'FaceAlpha',alphaVal, ...
    'EdgeColor','none', ...
    'HitTest','off', ...
    'HandleVisibility','off', ...
    'Tag','GA_InjectionPatch');

try
    ann = get(h,'Annotation');
    leg = get(ann,'LegendInformation');
    set(leg,'IconDisplayStyle','off');
catch
end

try
    uistack(h,'bottom');
catch
end
end

function y2 = smooth1D_edgeCentered(y, dtSec, winSec)
y = double(y(:)');
n = numel(y);
y2 = y;

if n < 2 || ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(winSec) || winSec <= 0
    return;
end

if any(~isfinite(y))
    idx = find(isfinite(y));
    if numel(idx) < 2
        return;
    end
    y = interp1(idx, y(idx), 1:n, 'linear', 'extrap');
end

winVol = max(1, round(winSec / dtSec));
if winVol <= 1
    y2 = y;
    return;
end

prePad  = floor(winVol/2);
postPad = winVol - 1 - prePad;

L = repmat(y(1), 1, prePad);
R = repmat(y(end), 1, postPad);
ypad = [L y R];

k = ones(1, winVol) / winVol;
y2 = conv(ypad, k, 'valid');
end

function [hLine,hPatch] = shadedLineColored(ax, x, y, e, lineColor, fillColor, semAlpha)
if nargin < 7 || isempty(semAlpha)
    semAlpha = 0.20;
end

x = x(:)';
y = y(:)';
e = e(:)';

up = y + e;
dn = y - e;

hPatch = patch(ax, [x fliplr(x)], [up fliplr(dn)], fillColor, ...
    'FaceAlpha',semAlpha, ...
    'EdgeColor','none', ...
    'HandleVisibility','off');

try
    ann = get(hPatch,'Annotation');
    leg = get(ann,'LegendInformation');
    set(leg,'IconDisplayStyle','off');
catch
end

hLine = plot(ax, x, y, 'LineWidth',2.4, 'Color',lineColor);
end

function dispNames = resolveDisplayGroupNames(rawNames, S)
n = numel(rawNames);
dispNames = cell(size(rawNames));
isPAC = false(1,n);
isVEH = false(1,n);

for i = 1:n
    u = upper(strtrimSafe(rawNames{i}));
    isPAC(i) = contains(u,'PACAP');
    isVEH(i) = contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL');
end

if strcmpi(S.colorScheme,'PACAP/Vehicle') && n==2
    if sum(isPAC)==1
        pacIdx = find(isPAC,1,'first');
        otherIdx = setdiff(1:2,pacIdx);
        dispNames{pacIdx} = 'PACAP';
        dispNames{otherIdx} = 'Vehicle';
        return;
    elseif sum(isVEH)==1
        vehIdx = find(isVEH,1,'first');
        otherIdx = setdiff(1:2,vehIdx);
        dispNames{vehIdx} = 'Vehicle';
        dispNames{otherIdx} = 'PACAP';
        return;
    else
        dispNames{1} = 'PACAP';
        dispNames{2} = 'Vehicle';
        return;
    end
end

for i = 1:n
    rawName = strtrimSafe(rawNames{i});
    u = upper(rawName);
    if contains(u,'PACAP')
        dispNames{i} = 'PACAP';
    elseif contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL')
        dispNames{i} = 'Vehicle';
    else
        if strcmpi(S.colorMode,'Manual A/B')
            if i==1 && ~isempty(strtrimSafe(S.manualGroupA))
                dispNames{i} = strtrimSafe(S.manualGroupA);
            elseif i==2 && ~isempty(strtrimSafe(S.manualGroupB))
                dispNames{i} = strtrimSafe(S.manualGroupB);
            else
                dispNames{i} = rawName;
            end
        else
            dispNames{i} = rawName;
        end
    end
    if isempty(dispNames{i})
        dispNames{i} = sprintf('Group%d',i);
    end
end
end

function c = groupRowColorGA(groupName, condName)
g = upper(strtrimSafe(groupName));
cnd = upper(strtrimSafe(condName));

% Group A / PACAP / CondA -> light green
if contains(g,'PACAP') || contains(g,'GROUPA') || strcmp(g,'A') || ...
   contains(cnd,'CONDA')
    c = [0.22 0.42 0.22];

% Group B / Vehicle / Control / CondB -> dark green
elseif contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || ...
       contains(g,'GROUPB') || strcmp(g,'B') || contains(cnd,'CONDB')
    c = [0.08 0.22 0.10];

% Fallback used color
else
    c = [0.12 0.30 0.16];
end
end

function dispNames = getDisplayNamesFromR(R)
if isfield(R,'groupDisplayNames') && ~isempty(R.groupDisplayNames)
    dispNames = R.groupDisplayNames;
else
    dispNames = R.groupNames;
end
end

function j = deterministicJitter(key, amp)
if nargin < 2 || isempty(amp), amp = 0.22; end
if isempty(key), key = 'x'; end

s = uint8(char(key));
h = uint32(2166136261);
for k = 1:numel(s)
    h = bitxor(h, uint32(s(k)));
    h = uint32(mod(uint64(h) * 16777619, 2^32));
end

u = double(h) / double(intmax('uint32'));
j = (u - 0.5) * amp;
end

function highlightOutliersOnScatter(ax, R, S, rowX, styleName)
if isempty(S.outlierKeys), return; end
if ~isfield(R,'subjTable') || isempty(R.subjTable), return; end
if numel(rowX) ~= size(R.subjTable,1), return; end

[bg,fg] = previewColors(styleName);
keysAll = makeRowKeys(R.subjTable);
y = R.metricVals(:);

for i = 1:numel(S.outlierKeys)
    hit = find(strcmp(keysAll, S.outlierKeys{i}), 1, 'first');
    if isempty(hit), continue; end
    if ~isfinite(rowX(hit)) || ~isfinite(y(hit)), continue; end

    scatter(ax, rowX(hit), y(hit), 150, ...
        'MarkerFaceColor','none', ...
        'MarkerEdgeColor',[1 0.45 0.45], ...
        'LineWidth',2.0);

    sid = strtrimSafe(R.subjTable{hit,2});
    txt = sprintf('%s: %.4g', sid, y(hit));
    text(ax, rowX(hit)+0.03, y(hit), txt, ...
        'Color',fg, ...
        'FontSize',9, ...
        'FontWeight','bold', ...
        'BackgroundColor',bg, ...
        'Margin',1, ...
        'Clipping','on', ...
        'HorizontalAlignment','left', ...
        'VerticalAlignment','middle');
end
end

function E = buildGroupAnalysisVideoExportGA(S0, activeIdx)
    nA = numel(activeIdx);
    if nA < 1
        error('No active bundle rows available.');
    end

    allPSC   = cell(nA,1);
    allUnder = cell(nA,1);
    sideInfo = cell(nA,1);
    trList   = nan(nA,1);
    nTList   = nan(nA,1);

    for i = 1:nA
        r = activeIdx(i);

        bundleFile = strtrimSafe(S0.subj{r,8});
        if isempty(bundleFile)
            bundleFile = resolveGroupBundlePath(S0, S0.subj(r,:));
        end

        [G, ~] = getCachedGroupBundle(S0.cache, bundleFile);

        if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
            error('Bundle has no exported PSC series: %s', bundleFile);
        end
        if ~isfield(G,'TR') || isempty(G.TR) || ~isfinite(G.TR) || G.TR <= 0
            error('Bundle has no valid TR: %s', bundleFile);
        end

        psc4 = extractBundlePSC2DSeriesLocal(G);

        % optional mask
        if isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
            m2 = logical(G.mask2DCurrentSlice);
            if isequal(size(m2), size(psc4(:,:,1)))
                for tt = 1:size(psc4,3)
                    tmp = psc4(:,:,tt);
                    tmp(~m2) = 0;
                    psc4(:,:,tt) = tmp;
                end
            end
        end

        % optional smoothing
        if isfield(S0,'mapSigma') && isfinite(S0.mapSigma) && S0.mapSigma > 0
            for tt = 1:size(psc4,3)
                psc4(:,:,tt) = smooth2D_gauss_local(psc4(:,:,tt), S0.mapSigma);
            end
        end

        underlayNow = resolvePreviewUnderlay(S0, G, mean(psc4,3));

        pacapSide = getPacapSideForRow(S0, r, G, S0.subj(r,:));
        if strcmpi(pacapSide,'Unknown')
            info = extractRowMetaLight(S0.subj(r,:));
            error('Injection side unknown for %s | %s | %s. Set it first in Group Maps preview.', ...
                info.animalID, info.session, info.scanID);
        end

        needFlip = shouldFlipForCurrentMapModeGA(S0, pacapSide);
        if needFlip
            psc4 = flipLR_3D_local(psc4);
            if ~isempty(underlayNow)
                underlayNow = flipLR_any(underlayNow);
            end
        end

        psc4(~isfinite(psc4)) = 0;

        allPSC{i}   = psc4;
        allUnder{i} = underlayNow;
        sideInfo{i} = pacapSide;
        trList(i)   = double(G.TR);
        nTList(i)   = size(psc4,3);
    end

    trGood = trList(isfinite(trList) & trList > 0);
    if isempty(trGood)
        error('No valid TR found across bundles.');
    end
    if max(trGood) - min(trGood) > 1e-9
        error('Bundles do not share the same TR. Group video export requires the same TR.');
    end
    TR = trGood(1);

    nT = min(nTList(isfinite(nTList) & nTList > 0));
    if isempty(nT) || nT < 2
        error('No valid shared time dimension found.');
    end

    for i = 1:nA
        allPSC{i} = allPSC{i}(:,:,1:nT);
    end

    if strcmpi(S0.mapSummary,'Median')
        groupPSC = medianCat(allPSC);
    else
        groupPSC = meanCat(allPSC);
    end
    groupPSC(~isfinite(groupPSC)) = 0;

    validU = allUnder(~cellfun(@isempty,allUnder));
    commonUnder = [];
    if ~isempty(validU)
        if ndims(validU{1}) == 3 && size(validU{1},3) == 3
            commonUnder = meanRgbUnderlays(validU);
        else
            commonUnder = meanCat(validU);
        end
    end

    % Use current GUI windows for exported preview map
    baseSec = S0.mapGlobalBaseSec;
    sigSec  = S0.mapGlobalSigSec;

    groupMap = computeMapFromPSC4DGA(groupPSC, TR, baseSec, sigSec, S0.mapSigma);

    E = struct();
    E.kind            = 'GA_GROUP_VIDEO_EXPORT';
    E.version         = 1;
    E.createdAt       = datestr(now,30);

    E.functional4D    = groupPSC;      % group-average PSC movie
    E.psc4D           = groupPSC;      % same content, alternate field name
    E.underlay2D      = commonUnder;
    E.overlay2D       = groupMap;
    E.groupMap2D      = groupMap;

    E.TR              = TR;
    E.nT              = nT;
    E.tSec            = (0:nT-1) * TR;

    E.baseWindowSec   = baseSec;
    E.sigWindowSec    = sigSec;

    E.render          = makeMapRenderStruct(S0);
    E.mapSummary      = S0.mapSummary;
    E.mapFlipMode     = S0.mapFlipMode;
    E.mapRefPacapSide = S0.mapRefPacapSide;
    E.mapColormap     = S0.mapColormap;
    E.mapCaxis        = S0.mapCaxis;
    E.mapModMin       = S0.mapModMin;
    E.mapModMax       = S0.mapModMax;
    E.mapSigma        = S0.mapSigma;

    E.sideInfo        = sideInfo;
    E.subjTable       = S0.subj(activeIdx,:);
    E.activeIdx       = activeIdx;
    E.nAnimals        = nA;
end

function P = extractBundlePSC2DSeriesLocal(G)
    P = double(G.pscAtlas4D);

    if ndims(P) == 3
        % already [Y X T]
    elseif ndims(P) == 4
        if isfield(G,'atlasSliceIndex') && ~isempty(G.atlasSliceIndex) && isfinite(G.atlasSliceIndex)
            zSel = round(G.atlasSliceIndex);
        elseif isfield(G,'currentSlice') && ~isempty(G.currentSlice) && isfinite(G.currentSlice)
            zSel = round(G.currentSlice);
        else
            zSel = round(size(P,3)/2);
        end
        zSel = max(1, min(size(P,3), zSel));
        P = squeeze(P(:,:,zSel,:));
    else
        error('pscAtlas4D must be [Y X T] or [Y X Z T].');
    end

    if ndims(P) ~= 3
        error('Could not extract 2D PSC movie from bundle.');
    end

    P(~isfinite(P)) = 0;
end

function M = computeMapFromPSC4DGA(P, TR, baseWinSec, sigWinSec, sigma)
    nT = size(P,3);

    b0 = max(1, min(nT, round(baseWinSec(1)/TR) + 1));
    b1 = max(1, min(nT, round(baseWinSec(2)/TR) + 1));
    s0 = max(1, min(nT, round(sigWinSec(1)/TR)  + 1));
    s1 = max(1, min(nT, round(sigWinSec(2)/TR)  + 1));

    if b1 < b0, tmp = b0; b0 = b1; b1 = tmp; end
    if s1 < s0, tmp = s0; s0 = s1; s1 = tmp; end

    M = mean(P(:,:,s0:s1),3) - mean(P(:,:,b0:b1),3);

    if nargin >= 5 && isfinite(sigma) && sigma > 0
        M = smooth2D_gauss_local(M, sigma);
    end

    M(~isfinite(M)) = 0;
end

function tf = shouldFlipForCurrentMapModeGA(S0, pacapSide)
    tf = false;

    mode = upper(strtrimSafe(S0.mapFlipMode));
    refSide = upper(strtrimSafe(S0.mapRefPacapSide));
    if isempty(refSide)
        refSide = 'LEFT';
    end

    switch mode
        case 'FLIP RIGHT-INJECTED ANIMALS'
            tf = strcmpi(pacapSide,'Right');

        case 'FLIP LEFT-INJECTED ANIMALS'
            tf = strcmpi(pacapSide,'Left');

        case 'ALIGN TO REFERENCE HEMISPHERE'
            if strcmp(refSide(1),'L')
                tf = strcmpi(pacapSide,'Right');
            else
                tf = strcmpi(pacapSide,'Left');
            end

        otherwise
            tf = false;
    end
end

function A = flipLR_3D_local(A)
    A = A(:,end:-1:1,:);
end



function exportPreviewPNG(outFile, which, S)
[figBg,~] = previewColors(S.previewStyle);

% Export-only geometry
if which == 1
    % Top plot: make wider again
    figPos = [100 100 1320 620];
   axPos  = [0.10 0.36 0.96 0.34];
    boxAsp = [2.00 1 1];
else
    % Bottom plot: keep mostly as before, only slightly broader
    figPos = [100 100 980 620];
    axPos  = [0.25 0.24 0.44 0.28];
    boxAsp = [0.92 1 1];
end

f = figure( ...
    'Visible','off', ...
    'Color',figBg, ...
    'InvertHardcopy','off', ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Renderer','opengl');

set(f,'Position',figPos);

ax = axes( ...
    'Parent',f, ...
    'Units','normalized', ...
    'Position',axPos);

styleAxesMode(ax, S.previewStyle, S.previewShowGrid);
recolorAxesText(ax, S.previewStyle);

try, set(ax,'LineWidth',1.0); catch, end
try, set(ax,'TickDir','out'); catch, end
try, set(ax,'TickLength',[0.012 0.012]); catch, end
try, set(ax,'ActivePositionProperty','position'); catch, end

exportOnePreview(ax, which, S, S.previewStyle);

% Apply aspect after plotting
try, pbaspect(ax, boxAsp); catch, end

if which == 2
    % Slight extra headroom for stats annotation
    try
        yl = ylim(ax);
        dy = yl(2) - yl(1);
        if isfinite(dy) && dy > 0
            ylim(ax, [yl(1) yl(2) + 0.12*dy]);
        end
    catch
    end

    % Remove bottom export title
    try
        title(ax,'');
    catch
    end

    % Move p-text / stars slightly upward and to the right
    moveExportStatsForExport(ax, 0, -0.08);
end

set(f,'PaperPositionMode','auto');
print(f, outFile, '-dpng', '-r300');
close(f);
end

   function moveExportStatsForExport(ax, xFracRight, pGapBelowStar)
if nargin < 2 || isempty(xFracRight)
    xFracRight = 0.06;
end
if nargin < 3 || isempty(pGapBelowStar)
    pGapBelowStar = 0.05;
end

if isempty(ax) || ~ishandle(ax)
    return;
end

try
    xl = xlim(ax);
    yl = ylim(ax);
catch
    return;
end

dx = xl(2) - xl(1);
dy = yl(2) - yl(1);

if ~isfinite(dx) || dx <= 0 || ~isfinite(dy) || dy <= 0
    return;
end

txts = findall(ax,'Type','text');
if isempty(txts)
    return;
end

hP = [];
hStar = [];

for k = 1:numel(txts)
    h = txts(k);

    try
        s = get(h,'String');
    catch
        continue;
    end

    if iscell(s)
        try
            s = strjoin(s,' ');
        catch
            s = '';
        end
    end

    s = strtrimSafe(s);
    sLow = lower(s);
    sNoSpace = strrep(sLow,' ','');

    isPText = contains(sNoSpace,'p=');
    isStar  = strcmp(s,'*') || strcmp(s,'**') || strcmp(s,'***') || strcmpi(s,'n.s.');

    if isPText
        hP = h;
    elseif isStar
        hStar = h;
    end
end

if isempty(hP) || ~ishandle(hP)
    return;
end

try
    posP = get(hP,'Position');
catch
    return;
end

if ~isempty(hStar) && ishandle(hStar)
    try
        posS = get(hStar,'Position');

        % place p-text slightly to the right of the star center
        posP(1) = min(xl(2) - 0.05*dx, posS(1) + xFracRight*dx);

        % place p-text BELOW the star by a fixed gap
        posP(2) = max(yl(1) + 0.03*dy, posS(2) - pGapBelowStar*dy);
    catch
    end
else
    % fallback if no star text found
    posP(1) = min(xl(2) - 0.05*dx, posP(1) + xFracRight*dx);
end

try
    set(hP,'Position',posP);
    set(hP,'HorizontalAlignment','center');
    set(hP,'VerticalAlignment','top');
    set(hP,'FontSize',9);   % smaller p-value text
catch
end
end

function y = tern(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end

function keys = makeRowKeys(tbl)
n = size(tbl,1);
keys = cell(n,1);
for i = 1:n
    sid = strtrimSafe(tbl{i,2});
    grp = strtrimSafe(tbl{i,3});
    cd  = strtrimSafe(tbl{i,4});
    pid = strtrimSafe(tbl{i,5});
    keys{i} = [sid '|' grp '|' cd '|' pid];
end
end

function writeCellCSV_UTF8(fn, C)
fid = fopen(fn,'w');
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8([239 187 191]), 'uint8');

[nr,nc] = size(C);
for r = 1:nr
    row = cell(1,nc);
    for c = 1:nc
        v = C{r,c};
        if isnumeric(v)
            if isempty(v) || ~isfinite(v)
                s = '';
            else
                s = num2str(v);
            end
        else
            try
                s = char(v);
            catch
                s = '';
            end
        end
        s = strrep(s,'"','""');
        row{c} = ['"' s '"'];
    end
    fprintf(fid,'%s\n', strjoin(row,','));
end
end
%%% =====================================================================
%%% EXCEL EXPORT / METADATA / STATS / ROI ANALYSIS
%%% =====================================================================

function exportGroupAnalysisExcelWorkbook(outFile, S)
metaSheet = buildMetadataSheetForExcel(S.subj);

condNames = uniqueStable(colAsStr(S.subj,4));
condASheet = {'Info','No condition found'};
condBSheet = {'Info','No second condition found'};

if numel(condNames) >= 1
    condASheet = buildConditionWideSheetForExcel(S.subj, condNames{1});
end
if numel(condNames) >= 2
    condBSheet = buildConditionWideSheetForExcel(S.subj, condNames{2});
end

auditSheet = buildOutlierAuditSheetForExcel(S);

if exist(outFile,'file') == 2
    try
        delete(outFile);
    catch
        error('Could not overwrite existing Excel file: %s', outFile);
    end
end

writeExcelSheetCompat(outFile, 'Metadata', metaSheet);
writeExcelSheetCompat(outFile, 'Condition_A', condASheet);
writeExcelSheetCompat(outFile, 'Condition_B', condBSheet);
writeExcelSheetCompat(outFile, 'Outlier_Audit', auditSheet);

try
    styleGroupAnalysisWorkbook(outFile);
catch
end
end

function writeExcelSheetCompat(outFile, sheetName, C)
if exist('writecell','file') == 2
    writecell(C, outFile, 'Sheet', sheetName);
else
    [ok,msg] = xlswrite(outFile, C, sheetName);
    if ~ok
        if ischar(msg)
            error('Excel write failed on sheet %s: %s', sheetName, msg);
        else
            error('Excel write failed on sheet %s.', sheetName);
        end
    end
end
end

function C = buildMetadataSheetForExcel(subj)
hdr = { ...
    'Use (TRUE/FALSE)','Animal ID','Session ID','Scan ID','Group','Condition', ...
    'Notes','Excluded','Publication Ready', ...
    'Baseline Window','Signal Window','ROI Index','Slice','x1','x2','y1','y2', ...
    'Animal Status','TR (s)','N Volumes','ROI File'};

rows = cell(size(subj,1), numel(hdr));

for i = 1:size(subj,1)
    info = extractRowMetaForExcel(subj(i,:));
    roiH = readROITxtHeaderMeta(info.roiFile);

    rows{i,1}  = logicalToText(subj{i,1});
    rows{i,2}  = info.animalID;
    rows{i,3}  = info.session;
    rows{i,4}  = info.scanID;
    rows{i,5}  = info.group;
    rows{i,6}  = info.condition;
    rows{i,7}  = info.notes;
    rows{i,8}  = info.exclusion;
    rows{i,9}  = info.useForPublication;

    rows{i,10} = roiH.baselineText;
    rows{i,11} = roiH.signalText;
    rows{i,12} = roiH.roiNo;
    rows{i,13} = roiH.slice;
    rows{i,14} = roiH.x1;
    rows{i,15} = roiH.x2;
    rows{i,16} = roiH.y1;
    rows{i,17} = roiH.y2;

    rows{i,18} = info.animalStatus;
    rows{i,19} = info.TR_sec;
    rows{i,20} = info.NVols;
    rows{i,21} = info.roiFile;
end

rows = sortMetadataRows(rows);

C = hdr;
C = appendGroupedRows(C, rows, 5);
end

function C = buildOutlierAuditSheetForExcel(S)
fullTbl = S.subj;

hdr = { ...
    'Use','AnimalID','Session','ScanID','Group','Condition', ...
    'Analyzed','RowState', ...
    'MetricValue','MetricName','MetricSource', ...
    'MetricRobustZ','OutlierMethod','Threshold','IsOutlierByMethod', ...
    'RawMedianPSC','RawMADPSC','RawQ1PSC','RawQ3PSC','RawIQRPSC', ...
    'ROIFile','Status'};

rows = cell(size(fullTbl,1), numel(hdr));

metricVals = nan(size(fullTbl,1),1);
analyzed   = false(size(fullTbl,1),1);
metricNameNow = '';
metricSourceNow = '';

if isfield(S,'lastROI') && ~isempty(fieldnames(S.lastROI)) && ...
   isfield(S.lastROI,'metricVals') && isfield(S.lastROI,'subjTable')


    anaTbl = S.lastROI.subjTable;
    anaMet = double(S.lastROI.metricVals(:));

    if isfield(S.lastROI,'metricName')
    metricNameNow = strtrimSafe(S.lastROI.metricName);
end
    if isempty(metricNameNow)
        metricNameNow = 'Bottom plot metric';
    end
    metricSourceNow = 'Per-animal value used for the bottom plot / outlier detection';

    anaKeys = cell(size(anaTbl,1),1);
    for i = 1:size(anaTbl,1)
        anaKeys{i} = makeAuditMatchKey(anaTbl(i,:));
    end

    for i = 1:size(fullTbl,1)
        k = makeAuditMatchKey(fullTbl(i,:));
        hit = find(strcmp(anaKeys, k), 1, 'first');
        if ~isempty(hit)
            metricVals(i) = anaMet(hit);
            analyzed(i) = true;
        end
    end
end

xAnal = metricVals(isfinite(metricVals));
gMed = NaN;
gMad = NaN;
rz = nan(size(metricVals));

if ~isempty(xAnal)
    gMed = median(xAnal);
    gMad = median(abs(xAnal - gMed));
    if isfinite(gMad) && gMad > 0
        rz(isfinite(metricVals)) = 0.6745 * (metricVals(isfinite(metricVals)) - gMed) / gMad;
    end
end

for i = 1:size(fullTbl,1)
    info = extractRowMetaForExcel(fullTbl(i,:));
    rowState = deriveAuditRowState(fullTbl(i,:));

    rawMed = NaN; rawMad = NaN; rawQ1 = NaN; rawQ3 = NaN; rawIQR = NaN;
    [ok,~,psc] = tryReadSCMroiExportTxt(info.roiFile);
    if ok
        psc = double(psc(:));
        psc = psc(isfinite(psc));
        if ~isempty(psc)
            rawMed = median(psc);
            rawMad = median(abs(psc - rawMed));
            rawQ1  = prctile(psc,25);
            rawQ3  = prctile(psc,75);
            rawIQR = rawQ3 - rawQ1;
        end
    end

    thrTxt = '';
    isOut = false;

    if strcmpi(S.outlierMethod,'MAD robust z-score')
        thrTxt = num2str(S.outMADthr);
        isOut = isfinite(rz(i)) && abs(rz(i)) > S.outMADthr;
    elseif strcmpi(S.outlierMethod,'IQR rule')
        thrTxt = num2str(S.outIQRk);
        if ~isempty(xAnal)
            q1 = prctile(xAnal,25);
            q3 = prctile(xAnal,75);
            iqrV = q3 - q1;
            lo = q1 - S.outIQRk * iqrV;
            hi = q3 + S.outIQRk * iqrV;
            isOut = isfinite(metricVals(i)) && (metricVals(i) < lo || metricVals(i) > hi);
        end
    end

    rows{i,1}  = logicalToText(fullTbl{i,1});
    rows{i,2}  = info.animalID;
    rows{i,3}  = info.session;
    rows{i,4}  = info.scanID;
    rows{i,5}  = info.group;
    rows{i,6}  = info.condition;
    rows{i,7}  = yesNoText(analyzed(i));
    rows{i,8}  = rowState;
    rows{i,9}  = metricVals(i);
    rows{i,10} = metricNameNow;
    rows{i,11} = metricSourceNow;
    rows{i,12} = rz(i);
    rows{i,13} = S.outlierMethod;
    rows{i,14} = thrTxt;
    rows{i,15} = yesNoText(isOut);
    rows{i,16} = rawMed;
    rows{i,17} = rawMad;
    rows{i,18} = rawQ1;
    rows{i,19} = rawQ3;
    rows{i,20} = rawIQR;
    rows{i,21} = info.roiFile;
    rows{i,22} = info.status;
end

rows = sortMetadataRows(rows);

C = hdr;
C = appendGroupedRows(C, rows, 5);
end

function info = extractRowMetaForExcel(row)
info = struct();

info.subject    = strtrimSafe(row{2});
info.group      = strtrimSafe(row{3});
info.condition  = strtrimSafe(row{4});
info.pairID     = strtrimSafe(row{5});
info.dataFile   = strtrimSafe(row{6});
info.roiFile    = strtrimSafe(row{7});
info.bundleFile = strtrimSafe(row{8});
info.status     = strtrimSafe(row{9});

meta = extractMetaFromSources(info.subject, info.dataFile, info.roiFile, info.bundleFile);

info.animalID = meta.animalID;
info.session  = meta.session;
info.scanID   = meta.scanID;

info.notes             = '';
info.useForPublication = '';
info.animalStatus      = '';

if logicalCellValue(row{1}) && ~contains(lower(info.status),'excluded')
    info.exclusion = '';
else
    info.exclusion = 'Yes';
end

[info.TR_sec, info.NVols, ~] = extractDataSummaryQuick(info.dataFile);
end

function sh = makeSafeExcelSheetName(s)
sh = strtrimSafe(s);
if isempty(sh), sh = 'Sheet'; end
sh = regexprep(sh,'[:\\/\?\*\[\]]','_');
if numel(sh) > 31
    sh = sh(1:31);
end
end


    function info = extractRowMetaLight(row)
info = struct();

info.subject    = strtrimSafe(row{2});
info.group      = strtrimSafe(row{3});
info.condition  = strtrimSafe(row{4});
info.pairID     = strtrimSafe(row{5});
info.dataFile   = strtrimSafe(row{6});
info.roiFile    = strtrimSafe(row{7});
info.bundleFile = strtrimSafe(row{8});
info.status     = strtrimSafe(row{9});

meta = extractMetaFromSources(info.subject, info.dataFile, info.roiFile, info.bundleFile);

info.animalID = meta.animalID;
info.session  = meta.session;
info.scanID   = meta.scanID;

info.notes             = '';
info.useForPublication = '';
info.animalStatus      = '';

if logicalCellValue(row{1}) && ~contains(lower(info.status),'excluded')
    info.exclusion = '';
else
    info.exclusion = 'Yes';
end

% IMPORTANT:
% Keep these lightweight here. Do NOT load large data mats in UI/path code.
info.TR_sec = NaN;
info.NVols  = NaN;
end


function state = deriveAuditRowState(row)
use = logicalCellValue(row{1});
roi = strtrimSafe(row{7});
st  = lower(strtrimSafe(row{9}));

if contains(st,'excluded') || ~use
    state = 'Excluded';
elseif isempty(roi)
    state = 'ROI not set';
elseif exist(roi,'file') == 2
    state = 'OK';
else
    state = 'Missing ROI';
end
end

function C = buildConditionWideSheetForExcel(subj, condFilter)
idxKeep = find(strcmpi(colAsStr(subj,4), condFilter));
idxKeep = sortSubjectIdxForMetadata(subj, idxKeep);

if isempty(idxKeep)
    C = {'Info', ['No rows for condition: ' condFilter]};
    return;
end

nScan = numel(idxKeep);
infos   = cell(nScan,1);
tSecAll = cell(nScan,1);
tMinAll = cell(nScan,1);
pAll    = cell(nScan,1);
maxPts  = 0;

for j = 1:nScan
    row = subj(idxKeep(j),:);
    info = extractRowMetaForExcel(row);
    infos{j} = info;

    [ok, tMin, psc] = tryReadSCMroiExportTxt(info.roiFile);
    if ok
        tMin = double(tMin(:));
        psc  = double(psc(:));

        tSecAll{j} = 60 .* tMin;
        tMinAll{j} = tMin;
        pAll{j}    = psc;

        maxPts = max(maxPts, numel(tMin));
    else
        tSecAll{j} = [];
        tMinAll{j} = [];
        pAll{j}    = [];
    end
end

rowAnimal  = 1;
rowSession = 2;
rowScan    = 3;
rowGroup   = 4;
rowCond    = 5;
rowInfo    = 8;
rowHeader  = 9;
rowData0   = 10;

nRows = max(rowData0 + maxPts - 1, rowHeader);
nCols = 2 + 2*nScan;

C = cell(nRows, nCols);

C{rowAnimal,1}  = 'Animal ID';
C{rowSession,1} = 'Session ID';
C{rowScan,1}    = 'Scan ID';
C{rowGroup,1}   = 'Group';
C{rowCond,1}    = 'Condition';

C{rowInfo,1}    = '% signal change (%SC)';
C{rowInfo,2}    = 'Values come from ROI txt and use the respective baseline window of each ROI export';

C{rowHeader,1}  = 'time_sec';
C{rowHeader,2}  = 'time_min';

refSec = nan(maxPts,1);
refMin = nan(maxPts,1);
for k = 1:maxPts
    for j = 1:nScan
        if numel(tSecAll{j}) >= k
            refSec(k) = tSecAll{j}(k);
            refMin(k) = tMinAll{j}(k);
            break;
        end
    end
end

for k = 1:maxPts
    r = rowData0 + k - 1;
    if isfinite(refSec(k)), C{r,1} = refSec(k); end
    if isfinite(refMin(k)), C{r,2} = refMin(k); end
end

for j = 1:nScan
    dataCol = 3 + 2*(j-1);
    info = infos{j};

    C{rowAnimal,dataCol}  = info.animalID;
    C{rowSession,dataCol} = info.session;
    C{rowScan,dataCol}    = info.scanID;
    C{rowGroup,dataCol}   = info.group;
    C{rowCond,dataCol}    = info.condition;

    C{rowHeader,dataCol}  = sprintf('%s | %s | %s', info.animalID, info.session, info.scanID);

    for k = 1:maxPts
        r = rowData0 + k - 1;
        if numel(pAll{j}) >= k
            C{r,dataCol} = pAll{j}(k);
        end
    end
end
end

function rows = appendGroupedRows(rows0, rows, groupCol)
C = rows0;
nCol = size(rows0,2);

if isempty(rows)
    blank = repmat({''},1,nCol);
    blank{1} = 'No rows found.';
    rows = blank;
    rows = rows(:).';
    rows = reshape(rows,1,[]);
    rows = rows(:,1:nCol);
    C = [C; rows];
    rows = C;
    return;
end

groups = uniqueStable(rows(:,groupCol));

for g = 1:numel(groups)
    titleRow = repmat({''},1,nCol);
    titleRow{1} = ['GROUP: ' groups{g}];
    C(end+1,:) = titleRow;

    idx = strcmpi(rows(:,groupCol), groups{g});
    C = [C; rows(idx,:)]; %#ok<AGROW>

    if g < numel(groups)
        C(end+1,:) = repmat({''},1,nCol);
    end
end

rows = C;
end

function rows = sortMetadataRows(rows)
if isempty(rows), return; end

keys = cell(size(rows,1),1);
for i = 1:size(rows,1)
    condRank = conditionRankForExport(rows{i,6});
    keys{i} = sprintf('%s|%03d|%s|%s', ...
        lower(safeKeyStr(rows{i,5})), ...
        condRank, ...
        lower(safeKeyStr(rows{i,6})), ...
        lower(safeKeyStr(rows{i,2})));
end

[~,ord] = sort(keys);
rows = rows(ord,:);
end

function idxOut = sortSubjectIdxForMetadata(subj, idxIn)
idxOut = idxIn(:)';
if isempty(idxOut), return; end

keys = cell(numel(idxOut),1);
for k = 1:numel(idxOut)
    info = extractRowMetaForExcel(subj(idxOut(k),:));
    condRank = conditionRankForExport(info.condition);
    keys{k} = sprintf('%s|%03d|%s|%s', ...
        lower(safeKeyStr(info.group)), ...
        condRank, ...
        lower(safeKeyStr(info.condition)), ...
        lower(safeKeyStr(info.animalID)));
end

[~,ord] = sort(keys);
idxOut = idxOut(ord);
end

function roiH = readROITxtHeaderMeta(fname)
roiH = struct( ...
    'baselineText','', ...
    'signalText','', ...
    'roiNo','', ...
    'slice','', ...
    'x1',NaN, ...
    'x2',NaN, ...
    'y1',NaN, ...
    'y2',NaN);

if nargin < 1 || isempty(fname) || exist(fname,'file') ~= 2
    return;
end

try
    [~,bn,~] = fileparts(fname);
    tok = regexpi(bn,'roi\s*([0-9]+)','tokens','once');
    if ~isempty(tok)
        roiH.roiNo = tok{1};
    end
catch
end

fid = fopen(fname,'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

maxLines = 120;
expectXYLine = false;

for k = 1:maxLines
    ln = fgetl(fid);
    if ~ischar(ln), break; end

    lnRaw = strtrim(ln);
    if isempty(lnRaw)
        continue;
    end

    if expectXYLine
        vals = sscanf(lnRaw,'%f');
        if numel(vals) >= 4
            roiH.x1 = vals(1);
            roiH.x2 = vals(2);
            roiH.y1 = vals(3);
            roiH.y2 = vals(4);
        end
        expectXYLine = false;
        continue;
    end

    if lnRaw(1) ~= '#' && lnRaw(1) ~= '%' && lnRaw(1) ~= ';'
        break;
    end

    txt = regexprep(lnRaw,'^[#%;\s]+','');
    txtL = lower(txt);

    if isempty(roiH.baselineText) && ~isempty(strfind(txtL,'baselinewindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.baselineText = strtrim(parts{2});
        else
            roiH.baselineText = strtrim(txt);
        end
    end

    if isempty(roiH.signalText) && ~isempty(strfind(txtL,'signalwindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.signalText = strtrim(parts{2});
        else
            roiH.signalText = strtrim(txt);
        end
    end

    if isempty(roiH.roiNo) && ~isempty(strfind(txtL,'roi_index'))
        tok = regexp(txt,'ROI_INDEX\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.roiNo = tok{1};
        end
    end

    if isempty(roiH.slice) && ~isempty(strfind(txtL,'slice'))
        tok = regexp(txt,'SLICE\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.slice = tok{1};
        end
    end

    if ~isempty(regexp(txtL,'^x1\s+x2\s+y1\s+y2$', 'once'))
        expectXYLine = true;
        continue;
    end

    tok = regexp(txt,'x1\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*x2\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*y1\s*[:=]\s*([-+]?\d*\.?\d+)\s+.*y2\s*[:=]\s*([-+]?\d*\.?\d+)','tokens','once','ignorecase');
    if ~isempty(tok)
        roiH.x1 = str2double(tok{1});
        roiH.x2 = str2double(tok{2});
        roiH.y1 = str2double(tok{3});
        roiH.y2 = str2double(tok{4});
    end
end
end

function rows = sortConditionRows(rows)
if isempty(rows), return; end

keys = cell(size(rows,1),1);
for i = 1:size(rows,1)
    keys{i} = sprintf('%s|%s', ...
        lower(safeKeyStr(rows{i,5})), ...
        lower(safeKeyStr(rows{i,2})));
end

[~,ord] = sort(keys);
rows = rows(ord,:);
end

function r = conditionRankForExport(x)
s = lower(strtrimSafe(x));
if contains(s,'conda') || strcmp(s,'a')
    r = 1;
elseif contains(s,'condb') || strcmp(s,'b')
    r = 2;
else
    r = 50;
end
end

function s = safeKeyStr(x)
if isnumeric(x)
    if isempty(x) || ~isfinite(x)
        s = '';
    else
        s = num2str(x);
    end
else
    s = strtrimSafe(x);
end
end

function s = logicalToText(v)
try
    if logical(v)
        s = 'TRUE';
    else
        s = 'FALSE';
    end
catch
    s = 'FALSE';
end
end

function s = yesNoText(v)
if logicalCellValue(v)
    s = 'Yes';
else
    s = 'No';
end
end

function styleGroupAnalysisWorkbook(outFile)
if ~ispc
    return;
end
if exist('actxserver','file') ~= 2
    return;
end

excel = [];
wb = [];

try
    excel = actxserver('Excel.Application');
    excel.Visible = false;
    excel.DisplayAlerts = false;

    wb = excel.Workbooks.Open(outFile, 0, false);
    nSheets = wb.Worksheets.Count;

    for s = 1:nSheets
        ws = wb.Worksheets.Item(s);
        nCols = ws.UsedRange.Columns.Count;
        nRows = ws.UsedRange.Rows.Count;
        lastCol = excelColLetter(nCols);
        sheetName = char(ws.Name);

        hdrRg = ws.Range(sprintf('A1:%s1', lastCol));
        hdrRg.Font.Bold = true;
        hdrRg.Font.Size = 12;
        hdrRg.Interior.Color = excelRGB(217,217,217);
        hdrRg.HorizontalAlignment = -4108;
        hdrRg.VerticalAlignment   = -4108;
        hdrRg.WrapText = true;

        if strcmpi(sheetName,'Metadata')
            for r = 2:nRows
                aVal = excelCellChar(ws.Range(sprintf('A%d',r)).Value);
                grp  = excelCellChar(ws.Range(sprintf('E%d',r)).Value);
                excl = excelCellChar(ws.Range(sprintf('H%d',r)).Value);
                usev = excelCellChar(ws.Range(sprintf('A%d',r)).Value);

                rowRg = ws.Range(sprintf('A%d:%s%d', r, lastCol, r));

                if strncmpi(strtrim(aVal), 'GROUP:', 6)
                    grpName = strtrim(strrep(aVal,'GROUP:',''));
                    rowRg.Font.Bold = true;
                    rowRg.Font.Size = 14;
                    try
                        rowRg.Font.Underline = 2;
                    catch
                    end
                    rowRg.HorizontalAlignment = -4108;
                    rowRg.VerticalAlignment   = -4108;

                    if isGroupAName(grpName)
                        rowRg.Interior.Color = excelRGB(221,235,247);
                    elseif isGroupBName(grpName)
                        rowRg.Interior.Color = excelRGB(252,228,214);
                    else
                        rowRg.Interior.Color = excelRGB(230,230,230);
                    end
                    continue;
                end

                if strcmpi(excl,'Yes') || strcmpi(usev,'FALSE')
                    rowRg.Interior.Color = excelRGB(255,210,210);
                elseif isGroupAName(grp)
                    rowRg.Interior.Color = excelRGB(221,235,247);
                elseif isGroupBName(grp)
                    rowRg.Interior.Color = excelRGB(252,228,214);
                end

                try
                    ws.Range(sprintf('E%d',r)).Font.Bold = true;
                    ws.Range(sprintf('E%d',r)).Font.Size = 11;
                catch
                end
            end
        end

        if strncmpi(sheetName,'Condition_',10)
            ws.Range('A1:B5').Font.Bold = true;
            ws.Range('A1:B5').Font.Size = 13;
            ws.Range('A1:B5').Interior.Color = excelRGB(217,217,217);
            ws.Range('A1:B5').HorizontalAlignment = -4108;
            ws.Range('A1:B5').VerticalAlignment   = -4108;
            try
                ws.Range('A1:B5').Font.Underline = 2;
            catch
            end

            if nRows >= 6
                ws.Range(sprintf('A6:%s7', lastCol)).Interior.Color = excelRGB(255,255,255);
            end

            if nRows >= 8
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Bold = true;
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Size = 11;
                ws.Range(sprintf('A8:%s8', lastCol)).Interior.Color = excelRGB(242,242,242);
            end

            if nRows >= 9
                ws.Range(sprintf('A9:%s9', lastCol)).Font.Bold = true;
                ws.Range(sprintf('A9:%s9', lastCol)).Font.Size = 12;
                ws.Range(sprintf('A9:%s9', lastCol)).Interior.Color = excelRGB(217,217,217);
                ws.Range(sprintf('A9:%s9', lastCol)).HorizontalAlignment = -4108;
                ws.Range(sprintf('A9:%s9', lastCol)).VerticalAlignment   = -4108;
            end

            animalIdx = 0;
            c = 3;
            while c <= nCols
                animalIdx = animalIdx + 1;
                dataCol = excelColLetter(c);

                blockRg = ws.Range(sprintf('%s1:%s%d', dataCol, dataCol, nRows));
                blockRg.Interior.Color = excelPastelColor(animalIdx);
                blockRg.HorizontalAlignment = -4108;
                blockRg.VerticalAlignment   = -4108;

                topRg = ws.Range(sprintf('%s1:%s5', dataCol, dataCol));
                topRg.Font.Bold = true;
                topRg.Font.Size = 12;
                topRg.WrapText = true;

                if nRows >= 9
                    hdr2Rg = ws.Range(sprintf('%s9:%s9', dataCol, dataCol));
                    hdr2Rg.Font.Bold = true;
                    hdr2Rg.Font.Size = 12;
                    hdr2Rg.WrapText = true;
                end

                if nRows >= 10
                    dataRg = ws.Range(sprintf('%s10:%s%d', dataCol, dataCol, nRows));
                    dataRg.Font.Size = 10;
                    dataRg.HorizontalAlignment = -4108;
                    dataRg.VerticalAlignment   = -4108;
                end

                applyExcelBoxBorder(blockRg);

                if c+1 <= nCols
                    spCol = excelColLetter(c+1);
                    spRg = ws.Range(sprintf('%s1:%s%d', spCol, spCol, nRows));
                    spRg.Interior.Color = excelRGB(255,255,255);
                end

                c = c + 2;
            end

            if nRows >= 10
                ws.Range(sprintf('A10:B%d', nRows)).Font.Size = 10;
                ws.Range(sprintf('A10:B%d', nRows)).HorizontalAlignment = -4108;
                ws.Range(sprintf('A10:B%d', nRows)).VerticalAlignment   = -4108;
            end
        end

        if strcmpi(sheetName,'Outlier_Audit')
            for r = 2:nRows
                aVal = excelCellChar(ws.Range(sprintf('A%d',r)).Value);
                stateVal = excelCellChar(ws.Range(sprintf('H%d', r)).Value);
                grpVal   = excelCellChar(ws.Range(sprintf('E%d', r)).Value);
                rowRg = ws.Range(sprintf('A%d:%s%d', r, lastCol, r));

                if strncmpi(strtrim(aVal), 'GROUP:', 6)
                    grpName = strtrim(strrep(aVal,'GROUP:',''));
                    rowRg.Font.Bold = true;
                    rowRg.Font.Size = 13;
                    try
                        rowRg.Font.Underline = 2;
                    catch
                    end
                    rowRg.HorizontalAlignment = -4108;
                    rowRg.VerticalAlignment   = -4108;

                    if isGroupAName(grpName)
                        rowRg.Interior.Color = excelRGB(221,235,247);
                    elseif isGroupBName(grpName)
                        rowRg.Interior.Color = excelRGB(252,228,214);
                    else
                        rowRg.Interior.Color = excelRGB(230,230,230);
                    end
                    continue;
                end

                if strcmpi(strtrim(stateVal), 'Excluded')
                    rowRg.Interior.Color = excelRGB(255,210,210);
                elseif strcmpi(strtrim(stateVal), 'OK')
                    rowRg.Interior.Color = excelRGB(210,255,210);
                else
                    if isGroupAName(grpVal)
                        try
                            ws.Range(sprintf('E%d',r)).Interior.Color = excelRGB(221,235,247);
                        catch
                        end
                    elseif isGroupBName(grpVal)
                        try
                            ws.Range(sprintf('E%d',r)).Interior.Color = excelRGB(252,228,214);
                        catch
                        end
                    end
                end
            end
        end

        ws.Columns.AutoFit;
    end

    wb.Save;
    wb.Close(false);
    excel.Quit;

catch ME
    try
        if ~isempty(wb), wb.Close(false); end
    catch
    end
    try
        if ~isempty(excel), excel.Quit; end
    catch
    end
    try
        if ~isempty(excel), delete(excel); end
    catch
    end
    rethrow(ME);
end

try
    if ~isempty(excel), delete(excel); end
catch
end
end

function c = excelRGB(r,g,b)
c = double(r) + 256*double(g) + 65536*double(b);
end

function s = excelColLetter(n)
s = '';
while n > 0
    r = rem(n-1,26);
    s = [char(65+r) s]; %#ok<AGROW>
    n = floor((n-1)/26);
end
end

function closeExcelSafe(excel, wb)
try
    if ~isempty(wb)
        wb.Close(false);
    end
catch
end
try
    if ~isempty(excel)
        excel.Quit;
    end
catch
end
try
    if ~isempty(excel)
        delete(excel);
    end
catch
end
end

function [names, rgb] = palette20()
names = {'Blue','Red','Green','Purple','Orange','Cyan','Magenta','Yellow','Gray','White', ...
         'Navy','DarkRed','Teal','Lime','Pink','Brown','Olive','Violet','Sky','Steel'};
rgb = [ ...
    0.20 0.65 0.90;
    0.90 0.25 0.25;
    0.25 0.85 0.55;
    0.65 0.40 0.95;
    0.95 0.55 0.20;
    0.20 0.85 0.85;
    0.90 0.35 0.80;
    0.95 0.90 0.25;
    0.75 0.75 0.75;
    0.95 0.95 0.95;
    0.10 0.20 0.55;
    0.55 0.10 0.10;
    0.10 0.55 0.55;
    0.60 0.90 0.20;
    0.95 0.55 0.75;
    0.55 0.35 0.20;
    0.55 0.55 0.15;
    0.55 0.30 0.75;
    0.35 0.75 0.95;
    0.45 0.55 0.65];
end

function p = tcdf_local(x, v)
x = double(x);
v = double(v);
p = nan(size(x));
ok = isfinite(x) & isfinite(v) & (v > 0);
if ~any(ok), return; end
xo = x(ok);
p_ok = zeros(size(xo));
for i = 1:numel(xo)
    xi = xo(i);
    vi = v;
    z = vi / (vi + xi*xi);
    ib = betainc(z, vi/2, 0.5);
    if xi >= 0
        p_ok(i) = 1 - 0.5*ib;
    else
        p_ok(i) = 0.5*ib;
    end
end
p(ok) = p_ok;
end

function p = fcdf_local(x, v1, v2)
x = double(x);
v1 = double(v1);
v2 = double(v2);
p = nan(size(x));
ok = isfinite(x) & (x>=0) & isfinite(v1) & isfinite(v2) & (v1>0) & (v2>0);
if ~any(ok), return; end
xo = x(ok);
z = (v1 .* xo) ./ (v1 .* xo + v2);
p(ok) = betainc(z, v1/2, v2/2);
end

function mu = nanmean_local(X, dim)
try
    mu = mean(X, dim, 'omitnan');
catch
    n = sum(isfinite(X),dim);
    X2 = X;
    X2(~isfinite(X2)) = 0;
    mu = sum(X2,dim) ./ max(1,n);
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

function [ok, tMin, psc] = tryReadSCMroiExportTxt(fname)
ok = false;
tMin = [];
psc = [];
if nargin<1 || isempty(fname), return; end
fname = strtrim(char(fname));
if exist(fname,'file')~=2, return; end
fid = fopen(fname,'r');
if fid<0, return; end
cln = onCleanup(@() fclose(fid)); %#ok<NASGU>

inTable = false;
while true
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end
    if ln(1)=='#'
        if ~isempty(strfind(lower(ln),'# columns:')) && ~isempty(strfind(lower(ln),'psc'))
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
if numel(tMin) >= 5 && numel(psc)==numel(tMin), ok = true; end
end

function D = loadPipelineStruct(fp)
L = load(fp);
if isfield(L,'newData') && isstruct(L.newData), D = pullFields(L.newData); return; end
if isfield(L,'data')    && isstruct(L.data),    D = pullFields(L.data);    return; end
fn = fieldnames(L);
for i=1:numel(fn)
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

function roi = readROITxt(f)
A = dlmread(f);
A = double(A);
A = A(~any(isnan(A),2),:);
if isempty(A), error('ROI txt empty: %s', f); end
if any(A(:)==0) && all(A(:) >= 0), A = A + 1; end
roi = A;
end

function tc = roiMeanTimecourse(I, roi)
d = ndims(I);
if d~=3 && d~=4, error('I must be [Y X T] or [Y X Z T].'); end
sz = size(I);
Y = sz(1);
X = sz(2);
if d==4
    Z = sz(3);
    T = sz(4);
else
    Z = 1;
    T = sz(3);
end

roi = double(roi);
if size(roi,2)==1
    lin = round(roi(:,1));
    if d==3
        lin = lin(lin>=1 & lin<=Y*X);
    else
        lin = lin(lin>=1 & lin<=Y*X*Z);
    end
elseif size(roi,2)==2
    r = round(roi(:,1));
    c = round(roi(:,2));
    z = ones(size(r));
    keep = (r>=1 & r<=Y & c>=1 & c<=X);
    r = r(keep); c = c(keep); z = z(keep);
    lin = sub2ind([Y X Z], r, c, z);
else
    r = round(roi(:,1));
    c = round(roi(:,2));
    z = round(roi(:,3));
    keep = (r>=1 & r<=Y & c>=1 & c<=X & z>=1 & z<=Z);
    r = r(keep); c = c(keep); z = z(keep);
    lin = sub2ind([Y X Z], r, c, z);
end

lin = unique(lin(:));
if isempty(lin), error('ROI has no valid points after bounds check.'); end

if d==3
    flat = reshape(I, Y*X, T);
else
    flat = reshape(I, Y*X*Z, T);
end

vals = double(flat(lin,:));
tc = mean(vals,1);
tc(~isfinite(tc)) = NaN;
end

function [tcRaw, tMin] = extractROITC_fromDataAndROI(dataFile, roiFile)
D = loadPipelineStruct(dataFile);
if ~isfield(D,'I') || isempty(D.I), error('DATA file missing I: %s', dataFile); end
if ~isfield(D,'TR') || isempty(D.TR), error('DATA file missing TR: %s', dataFile); end
I = D.I;
TR = double(D.TR);
roi = readROITxt(roiFile);
tcRaw = roiMeanTimecourse(I, roi);
T = numel(tcRaw);
tMin = (0:(T-1))*(TR/60);
end

function [tcRaw, tMin] = extractROITC_legacyMat(fp)
L = load(fp);
if isfield(L,'roiTC')
    tc = L.roiTC;
elseif isfield(L,'TC')
    tc = L.TC;
else
    error('ROI mat must contain roiTC or TC: %s', fp);
end
tc = double(tc);
if size(tc,1) > size(tc,2), tc = tc.'; end
if size(tc,1) > 1
    try
        tc = mean(tc,1,'omitnan');
    catch
        tc = mean(tc,1);
    end
end
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

function m = trimmedMean(x, trimPct)
x = x(:);
x = x(isfinite(x));
if isempty(x), m = NaN; return; end
x = sort(x,'ascend');
n = numel(x);
tp = max(0, min(49, round(trimPct)));
k = floor((tp/100)*n/2);
i0 = 1+k;
i1 = n-k;
if i1 < i0
    m = mean(x);
else
    m = mean(x(i0:i1));
end
end

function pv = robustPeak(y, tMin, s0, s1, winMin, trimPct)
y = double(y(:)');
tMin = double(tMin(:)');
pv = NaN;
idxAll = find(tMin>=s0 & tMin<=s1);
if numel(idxAll)<1, return; end
dt = median(diff(tMin));
if ~isfinite(dt) || dt<=0, dt = 0.1; end
w = max(1, round(winMin/dt));
iStart = idxAll(1);
iEnd = idxAll(end);
best = -Inf;
for i=iStart:(iEnd-w+1)
    j = i+w-1;
    seg = y(i:j);
    seg = seg(isfinite(seg));
    if isempty(seg), continue; end
    val = trimmedMean(seg, trimPct);
    if val > best, best = val; end
end
if isfinite(best), pv = best; end
end

function colors = assignGroupColorsWithMode(gNames, S)
colors = struct();
[~,pal] = palette20();

if strcmpi(S.colorMode,'Manual A/B')
    colA = pal(max(1,min(size(pal,1),S.manualColorA)),:);
    colB = pal(max(1,min(size(pal,1),S.manualColorB)),:);
    gA = strtrimSafe(S.manualGroupA);
    gB = strtrimSafe(S.manualGroupB);
    base = lines(max(1,numel(gNames)));
    for i=1:numel(gNames)
        nm = strtrimSafe(gNames{i});
        if ~isempty(gA) && strcmpi(nm,gA)
            col = colA;
        elseif ~isempty(gB) && strcmpi(nm,gB)
            col = colB;
        else
            col = base(i,:);
        end
        colors.(makeField(nm)) = col;
    end
    return;
end

scheme = strtrimSafe(S.colorScheme);

if strcmpi(scheme,'Blue/Red')
    base = [0.20 0.65 0.90; 0.90 0.25 0.25];
elseif strcmpi(scheme,'Purple/Green')
    base = [0.65 0.40 0.95; 0.25 0.85 0.55];
elseif strcmpi(scheme,'Gray/Orange')
    base = [0.65 0.65 0.65; 0.95 0.55 0.20];
elseif strcmpi(scheme,'Distinct')
    base = lines(max(2,numel(gNames)));
else
    base = [];
end

if ~isempty(base) && ~strcmpi(scheme,'PACAP/Vehicle')
    for i=1:numel(gNames)
        colors.(makeField(gNames{i})) = base(1+mod(i-1,size(base,1)),:);
    end
    return;
end

if strcmpi(scheme,'PACAP/Vehicle')
    n = numel(gNames);
    isPAC = false(1,n);
    isVEH = false(1,n);
    for i=1:n
        nmU = upper(strtrimSafe(gNames{i}));
        isPAC(i) = contains(nmU,'PACAP');
        isVEH(i) = contains(nmU,'VEH') || contains(nmU,'CONTROL') || contains(nmU,'VEHICLE');
    end

    if n==2 && sum(isPAC)==1
        pacIdx = find(isPAC,1,'first');
        otherIdx = setdiff(1:2,pacIdx);
        colors.(makeField(gNames{pacIdx})) = [0.20 0.65 0.90];
        colors.(makeField(gNames{otherIdx})) = [0.65 0.65 0.65];
        return;
    elseif n==2 && sum(isVEH)==1
        vehIdx = find(isVEH,1,'first');
        otherIdx = setdiff(1:2,vehIdx);
        colors.(makeField(gNames{vehIdx})) = [0.65 0.65 0.65];
        colors.(makeField(gNames{otherIdx})) = [0.20 0.65 0.90];
        return;
    elseif n==2
        colors.(makeField(gNames{1})) = [0.20 0.65 0.90];
        colors.(makeField(gNames{2})) = [0.65 0.65 0.65];
        return;
    end

    for i=1:n
        nmU = upper(strtrimSafe(gNames{i}));
        if contains(nmU,'PACAP')
            col = [0.20 0.65 0.90];
        elseif contains(nmU,'VEH') || contains(nmU,'CONTROL') || contains(nmU,'VEHICLE')
            col = [0.65 0.65 0.65];
        else
            b2 = lines(n);
            col = b2(i,:);
        end
        colors.(makeField(gNames{i})) = col;
    end
    return;
end

base = lines(max(1,numel(gNames)));
for i=1:numel(gNames)
    colors.(makeField(gNames{i})) = base(i,:);
end
end

function clr = excelPastelColor(idx)
pal = [ ...
    221 235 247;
    252 228 214;
    226 239 218;
    242 220 219;
    217 225 242;
    255 242 204;
    234 209 220;
    208 224 227];
i = 1 + mod(idx-1, size(pal,1));
clr = excelRGB(pal(i,1), pal(i,2), pal(i,3));
end

function applyExcelBoxBorder(rg)
try
    rg.Borders.LineStyle = 1;
    rg.Borders.Weight = 2;
catch
end
end

function s = excelCellChar(v)
if ischar(v)
    s = strtrim(v);
elseif isstring(v)
    s = strtrim(char(v));
elseif isnumeric(v)
    if isempty(v) || ~isfinite(v)
        s = '';
    else
        s = strtrim(num2str(v));
    end
else
    s = '';
end
end

function tf = isGroupAName(g)
g = upper(strtrimSafe(g));
tf = contains(g,'PACAP') || contains(g,'GROUPA') || strcmp(g,'A');
end

function tf = isGroupBName(g)
g = upper(strtrimSafe(g));
tf = contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || contains(g,'GROUPB') || strcmp(g,'B');
end

function [TR_sec, NVols, durationMin] = extractDataSummaryQuick(dataFile)
TR_sec = NaN;
NVols = NaN;
durationMin = NaN;

if nargin < 1 || isempty(dataFile) || exist(dataFile,'file') ~= 2
    return;
end

try
    D = loadPipelineStruct(dataFile);

    if isfield(D,'TR') && ~isempty(D.TR)
        TR_sec = double(D.TR);
    end

    if isfield(D,'I') && ~isempty(D.I)
        NVols = size(D.I, ndims(D.I));
    end

    if isfinite(TR_sec) && isfinite(NVols)
        durationMin = ((NVols - 1) * TR_sec) / 60;
    end
catch
end
end

function stats = computeStats(metricVals, grpCol, S)
stats = struct('type',S.testType,'alpha',S.alpha,'p',NaN,'t',NaN,'F',NaN,'df',NaN,'desc','');
testType = strtrimSafe(S.testType);

if strcmpi(testType,'None')
    stats.desc = 'No test.';
    return;
end

gNames = uniqueStable(grpCol);
gNames = sortGroupNamesStableGA(gNames, S);

if strcmpi(testType,'One-sample t-test (vs 0)')
    [t,p,df] = oneSampleT_vec(metricVals);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = 'One-sample vs 0';

elseif strcmpi(testType,'Two-sample t-test (Student, equal var)')
    if numel(gNames) < 2
        error('Need >=2 groups.');
    end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = studentT_equalVar_vec(a,b);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = [gNames{1} ' vs ' gNames{2}];

elseif strcmpi(testType,'Two-sample t-test (Welch)')
    if numel(gNames) < 2
        error('Need >=2 groups.');
    end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = welchT_vec(a,b);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = [gNames{1} ' vs ' gNames{2}];

else
    [F,p,df] = oneWayANOVA_metric(metricVals, grpCol);
    stats.F = F;
    stats.p = p;
    stats.df = df;
    stats.desc = 'ANOVA';
end
end

function [t,p,df] = oneSampleT_vec(x)
x = x(:);
x = x(isfinite(x));
n = numel(x);
if n < 2, t = NaN; p = NaN; df = max(0,n-1); return; end
mu = mean(x);
sd = std(x,0);
se = sd/sqrt(n);
t = mu / max(eps,se);
df = n-1;
p = 2 * tcdf_local(-abs(t), df);
end

function [t,p,df] = studentT_equalVar_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1 = numel(a); n2 = numel(b);
if n1<2 || n2<2, t = NaN; p = NaN; df = NaN; return; end
m1 = mean(a); m2 = mean(b);
v1 = var(a,0); v2 = var(b,0);
df = n1 + n2 - 2;
sp2 = ((n1-1)*v1 + (n2-1)*v2) / max(1,df);
den = sqrt(sp2 * (1/n1 + 1/n2));
t = (m1 - m2) / max(eps, den);
p = 2 * tcdf_local(-abs(t), df);
end

function [t,p,df] = welchT_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1 = numel(a); n2 = numel(b);
if n1<2 || n2<2, t = NaN; p = NaN; df = NaN; return; end
m1 = mean(a); m2 = mean(b);
v1 = var(a,0); v2 = var(b,0);
den = sqrt(v1/n1 + v2/n2);
t = (m1-m2) / max(eps,den);
df = (v1/n1 + v2/n2)^2 / ((v1^2)/(n1^2*max(1,n1-1)) + (v2^2)/(n2^2*max(1,n2-1)));
df = max(1, df);
p = 2 * tcdf_local(-abs(t), df);
end

function [F,p,df] = oneWayANOVA_metric(x, groupLabels)
x = x(:);
keep = isfinite(x);
x = x(keep);
g = groupLabels(keep);
g = cellfun(@(s) strtrimSafe(s), g, 'UniformOutput',false);
u = uniqueStable(g);
k = numel(u);
n = numel(x);
if k < 2 || n < 3, F = NaN; p = NaN; df = [k-1 n-k]; return; end
grand = mean(x);
SSb = 0;
SSw = 0;
for i=1:k
    xi = x(strcmpi(g,u{i}));
    if isempty(xi), continue; end
    mi = mean(xi);
    SSb = SSb + numel(xi)*(mi-grand)^2;
    SSw = SSw + sum((xi-mi).^2);
end
df1 = k-1;
df2 = n-k;
MSb = SSb / max(1,df1);
MSw = SSw / max(1,df2);
F = MSb / max(eps,MSw);
df = [df1 df2];
p = 1 - fcdf_local(F, df1, df2);
end

function [keysOut, info] = detectOutliers(metricVals, subjTable, S)
keysOut = {};
info = {};
x = metricVals(:);
valid = isfinite(x);
if sum(valid) < 3, return; end

method = strtrimSafe(S.outlierMethod);

if strcmpi(method,'MAD robust z-score')
    thr = S.outMADthr;
    xv = x(valid);
    med = median(xv);
    madv = median(abs(xv - med));
    if madv <= 0 || ~isfinite(madv), return; end
    rz = 0.6745 * (x - med) / madv;
    idxOut = find(valid & abs(rz) > thr);

    keysAll = makeRowKeys(subjTable);
    for ii = idxOut(:)'
        sid = strtrimSafe(subjTable{ii,2});
        grp = strtrimSafe(subjTable{ii,3});
        cd  = strtrimSafe(subjTable{ii,4});
        info{end+1,1} = sprintf('%s | %s | %s | metric=%.4g | MADz=%.4g > %.4g', ...
            sid, grp, cd, x(ii), abs(rz(ii)), thr); %#ok<AGROW>
        keysOut{end+1,1} = keysAll{ii}; %#ok<AGROW>
    end

elseif strcmpi(method,'IQR rule')
    k = S.outIQRk;
    xv = x(valid);
    q1 = prctile(xv,25);
    q3 = prctile(xv,75);
    iqrV = q3-q1;
    lo = q1 - k*iqrV;
    hi = q3 + k*iqrV;
    idxOut = find(valid & (x<lo | x>hi));

    keysAll = makeRowKeys(subjTable);
    for ii = idxOut(:)'
        sid = strtrimSafe(subjTable{ii,2});
        grp = strtrimSafe(subjTable{ii,3});
        cd  = strtrimSafe(subjTable{ii,4});
        info{end+1,1} = sprintf('%s | %s | %s | metric=%.4g | outside [%.4g, %.4g]', ...
            sid, grp, cd, x(ii), lo, hi); %#ok<AGROW>
        keysOut{end+1,1} = keysAll{ii}; %#ok<AGROW>
    end
else
    return;
end
end

function key = makeCacheKey(varargin)
parts = cellfun(@(x) strtrimSafe(x), varargin, 'UniformOutput', false);
key = strjoin(parts,'||');
end

function [entry, cache] = getCachedROIEntry(cache, dataFile, roiFile)
entry = [];
key = makeCacheKey('ROI',dataFile,roiFile);

if isstruct(cache) && isfield(cache,'roiTC') && isa(cache.roiTC,'containers.Map')
    if isKey(cache.roiTC, key)
        entry = cache.roiTC(key);
        return;
    end
end

[okTxt, tMin, psc] = tryReadSCMroiExportTxt(roiFile);
if okTxt
    entry.tc = double(psc(:))';
    entry.tMin = double(tMin(:))';
    entry.isPSCInput = true;
else
    if isempty(roiFile) || exist(roiFile,'file')~=2
        error('ROIFile missing or not found: %s', roiFile);
    end
    [~,~,ext] = fileparts(roiFile);
    ext = lower(ext);
    if strcmp(ext,'.mat')
        [tcRaw, tMin2] = extractROITC_legacyMat(roiFile);
        entry.tc = double(tcRaw(:))';
        entry.tMin = double(tMin2(:))';
        entry.isPSCInput = false;
    else
        if isempty(dataFile) || exist(dataFile,'file')~=2
            error('DATA .mat required for raw ROI txt: %s', dataFile);
        end
        [tcRaw, tMin2] = extractROITC_fromDataAndROI(dataFile, roiFile);
        entry.tc = double(tcRaw(:))';
        entry.tMin = double(tMin2(:))';
        entry.isPSCInput = false;
    end
end

if isstruct(cache) && isfield(cache,'roiTC') && isa(cache.roiTC,'containers.Map')
    try
        cache.roiTC(key) = entry;
    catch
    end
end
end

function [R, cache] = runROITimecourseAnalysis(S, subjActive, cache)
grpCol = colAsStr(subjActive,3);
grpCol(cellfun(@isempty,grpCol)) = {'GroupA'};

gNames = uniqueStable(grpCol);
gNames = sortGroupNamesStableGA(gNames, S);

if isempty(gNames)
    error('No groups defined.');
end

N = size(subjActive,1);
tcAll = cell(N,1);
tAll  = cell(N,1);
isPSCInput = false(N,1);

for i = 1:N
    dataFile = strtrimSafe(subjActive{i,6});
    roiFile  = strtrimSafe(subjActive{i,7});
    [entry, cache] = getCachedROIEntry(cache, dataFile, roiFile);
    tcAll{i} = entry.tc;
    tAll{i}  = entry.tMin;
    isPSCInput(i) = entry.isPSCInput;
end

t0 = max(cellfun(@(x) x(1), tAll));
t1 = min(cellfun(@(x) x(end), tAll));
dtAll = nan(N,1);
for i = 1:N
    di = diff(tAll{i});
    di = di(isfinite(di) & di > 0);
    if ~isempty(di)
        dtAll(i) = median(di);
    end
end
dt = median(dtAll(isfinite(dtAll)));
if ~isfinite(dt) || dt <= 0
    dt = 0.1;
end
if t1 <= t0
    error('Time axes do not overlap across subjects.');
end
tCommon = t0:dt:t1;

Xraw = nan(N,numel(tCommon));
for i = 1:N
    Xraw(i,:) = interp1(tAll{i}(:), tcAll{i}(:), tCommon(:), 'linear', NaN).';
end

X = Xraw;

if S.tc_computePSC
    baseIdx = (tCommon >= S.tc_baseMin0) & (tCommon <= S.tc_baseMin1);
    if ~any(baseIdx)
        error('Baseline window has no samples.');
    end
    for i = 1:N
        if isPSCInput(i)
            continue;
        end
        b = nanmean_local(Xraw(i,baseIdx),2);
        if ~isfinite(b) || b == 0
            b = eps;
        end
        X(i,:) = 100 * (Xraw(i,:) - b) ./ b;
    end
end

unitsPercent = any(isPSCInput) || S.tc_computePSC;
groupColors = assignGroupColorsWithMode(gNames, S);

groupTC = struct([]);
for g = 1:numel(gNames)
    idx = strcmpi(grpCol, gNames{g});
    mu = nanmean_local(X(idx,:),1);
    sd = nanstd_local(X(idx,:),0,1);
    n  = sum(isfinite(X(idx,:)),1);
    se = sd ./ sqrt(max(1,n));

    groupTC(g).name = gNames{g};
    groupTC(g).mean = mu;
    groupTC(g).sem  = se;
    groupTC(g).n    = sum(idx);
end

platIdx = (tCommon >= S.tc_plateauMin0) & (tCommon <= S.tc_plateauMin1);
if ~any(platIdx)
    error('Plateau window has no samples.');
end

plateau = nan(N,1);
for i = 1:N
    plateau(i) = nanmean_local(X(i,platIdx),2);
end

peakVal = nan(N,1);
for i = 1:N
    peakVal(i) = robustPeak(X(i,:), tCommon, ...
        S.tc_peakSearchMin0, S.tc_peakSearchMin1, ...
        S.tc_peakWinMin, S.tc_trimPct);
end

if strcmpi(S.tc_metric,'Plateau')
    metricVals = plateau;
    metricName = sprintf('Plateau mean (%.1f-%.1f min)', S.tc_plateauMin0, S.tc_plateauMin1);
else
    metricVals = peakVal;
    metricName = sprintf('Robust peak (%.1f-%.1f min)', S.tc_peakSearchMin0, S.tc_peakSearchMin1);
end

stats = computeStats(metricVals, grpCol, S);

Tcell = cell(N+1,6);
Tcell(1,:) = {'Subject','Group','Condition','PairID','Metric','MetricName'};
for i = 1:N
    Tcell{i+1,1} = strtrimSafe(subjActive{i,2});
    Tcell{i+1,2} = strtrimSafe(subjActive{i,3});
    Tcell{i+1,3} = strtrimSafe(subjActive{i,4});
    Tcell{i+1,4} = strtrimSafe(subjActive{i,5});
    Tcell{i+1,5} = metricVals(i);
    Tcell{i+1,6} = metricName;
end

R = struct();
R.mode = 'ROI Timecourse';
R.tMin = tCommon;
R.group = groupTC;
R.groupNames = gNames;
R.groupDisplayNames = resolveDisplayGroupNames(gNames, S);
R.groupColors = groupColors;
R.unitsPercent = unitsPercent;
R.metricName = metricName;
R.metricVals = metricVals;
R.stats = stats;
R.metrics = struct('table',{Tcell});
R.subjTable = subjActive;
R.plotTop = S.plotTop;
R.plotBot = S.plotBot;
R.showSEM = S.tc_showSEM;
end

function p = p_to_stars(pv)
if ~isfinite(pv)
    p = 'p=?';
elseif pv < 0.001
    p = '***';
elseif pv < 0.01
    p = '**';
elseif pv < 0.05
    p = '*';
else
    p = 'n.s.';
end
end

function annotateStatsBottom(ax, R, S)
p = R.stats.p;
alpha = R.stats.alpha;
stars = p_to_stars(p);
[~,fg] = previewColors(S.previewStyle);

yl = ylim(ax);
ySpan = yl(2)-yl(1);
if ~isfinite(ySpan) || ySpan<=0, ySpan = 1; end
yBar = yl(2) - 0.10*ySpan;

gN = numel(R.groupNames);
tType = '';
if isfield(R.stats,'type'), tType = strtrimSafe(R.stats.type); end

isTwo = contains(lower(tType),'student') || contains(lower(tType),'welch') || contains(lower(tType),'two-sample') || contains(lower(tType),'t-test');

if gN >= 2 && isTwo
    x1 = 1;
    x2 = 2;
    plot(ax, [x1 x1 x2 x2], [yBar-0.02*ySpan yBar yBar yBar-0.02*ySpan], '-', 'LineWidth', 2, 'Color', fg);
    text(ax, (x1+x2)/2, yBar + 0.02*ySpan, stars, ...
        'Color',fg,'FontSize',16,'FontWeight','bold', ...
        'HorizontalAlignment','center','VerticalAlignment','bottom');
   if S.showPText
    text(ax, (x1+x2)/2, yBar - 0.06*ySpan, sprintf('p = %.3g', p), ...
        'Color',fg,'FontSize',11, ...
        'HorizontalAlignment','center','VerticalAlignment','top');
end
else
    txt = sprintf('%s | p=%.3g', shortType(tType), p);
    text(ax, mean(xlim(ax)), yl(2)-0.04*ySpan, txt, ...
        'Color',fg,'FontSize',12,'FontWeight','bold', ...
        'HorizontalAlignment','center','VerticalAlignment','top');
    if isfinite(p) && p < alpha
        text(ax, mean(xlim(ax)), yl(2)-0.09*ySpan, stars, ...
            'Color',fg,'FontSize',16,'FontWeight','bold', ...
            'HorizontalAlignment','center','VerticalAlignment','top');
    end
end
end

function annotateStatsTopText(ax, R, S)
p = R.stats.p;
alpha = R.stats.alpha;
stars = p_to_stars(p);
[~,fg] = previewColors(S.previewStyle);

xl = xlim(ax);
yl = ylim(ax);
x = xl(2) - 0.02*(xl(2)-xl(1));
y = yl(2) - 0.05*(yl(2)-yl(1));

txt = sprintf('%s  p=%.3g', stars, p);
text(ax, x, y, txt, ...
    'Color',fg,'FontSize',12,'FontWeight','bold', ...
    'HorizontalAlignment','right','VerticalAlignment','top');
if S.showPText
    text(ax, x, y - 0.06*(yl(2)-yl(1)), sprintf('alpha=%.3g', alpha), ...
        'Color',0.7*fg,'FontSize',10, ...
        'HorizontalAlignment','right','VerticalAlignment','top');
end
end

function s = shortType(s)
s = strtrimSafe(s);
if isempty(s), s = 'Test'; end
if numel(s)>26, s = [s(1:26) '...']; end
end

function M = meanOverFrames(I, idx, dimT)
subs = repmat({':'},1,ndims(I));
subs{dimT} = idx;
X = I(subs{:});
M = mean(double(X), dimT);
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

function m = meanCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmean_local(X, ndims(X));
end

function m = medianCat(cellMaps)
X = catAlong4(cellMaps);
m = nanmedian_local(X, ndims(X));
end

function md = nanmedian_local(X, dim)
try
    md = median(X, dim, 'omitnan');
catch
    sz = size(X);
    nd = numel(sz);
    dim = max(1, min(nd, dim));
    perm = 1:nd;
    perm([dim nd]) = [nd dim];
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

function meta = extractMetaFromSources(subjectTxt, dataFile, roiFile, bundleFile)
if nargin < 4, bundleFile = ''; end

meta = struct('animalID','N/A','session','N/A','scanID','N/A');
cands = {bundleFile, roiFile, dataFile, subjectTxt};

for i = 1:numel(cands)
    txt = strtrimSafe(cands{i});
    if isempty(txt), continue; end

    m = parseMetaSingleText(txt);

    if strcmpi(meta.animalID,'N/A') && ~strcmpi(m.animalID,'N/A')
        meta.animalID = m.animalID;
    end
    if strcmpi(meta.session,'N/A') && ~strcmpi(m.session,'N/A')
        meta.session = m.session;
    end
    if strcmpi(meta.scanID,'N/A') && ~strcmpi(m.scanID,'N/A')
        meta.scanID = m.scanID;
    end

    if ~strcmpi(meta.animalID,'N/A') && ~strcmpi(meta.session,'N/A') && ~strcmpi(meta.scanID,'N/A')
        return;
    end
end
end

    function meta = parseMetaSingleText(txt)
meta = struct('animalID','N/A','session','N/A','scanID','N/A');

if nargin < 1 || isempty(txt)
    return;
end

try
    txt = char(txt);
catch
    return;
end

txt = strrep(txt,'\','/');
txtU = upper(txt);

% ---------------------------------------------------------
% OLD STYLE 1: ANIMAL_S1_FUS_2
% ---------------------------------------------------------
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)_(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = strtrim(tok{1});
    meta.session  = strtrim(tok{2});
    meta.scanID   = strtrim(tok{3});
    return;
end

% ---------------------------------------------------------
% OLD STYLE 2: ANIMAL_S1
% ---------------------------------------------------------
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = strtrim(tok{1});
    meta.session  = strtrim(tok{2});
end

% ---------------------------------------------------------
% OLD STYLE 3: FUS_2
% ---------------------------------------------------------
tok = regexpi(txtU,'(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.scanID = strtrim(tok{1});
end

if ~strcmpi(meta.animalID,'N/A') || ~strcmpi(meta.session,'N/A') || ~strcmpi(meta.scanID,'N/A')
    return;
end

% ---------------------------------------------------------
% NEW STYLE:
% RGRO_260407_1024_MM_B6J_1059_scan2_SB
% -> animalID = 1059
% -> session  = N/A
% -> scanID   = scan2_SB
%
% Also works for scan3_M, scan4_ES, etc.
% We parse from the FULL PATH so it still works if the ROI filename
% itself is generic but the folder contains the dataset name.
% ---------------------------------------------------------
txtTok = regexprep(txt,'[^A-Za-z0-9/_\-]','_');
parts = regexp(txtTok,'[/_\-]+','split');
parts = parts(~cellfun(@isempty,parts));

scanIdx = [];
for k = 1:numel(parts)
    if ~isempty(regexpi(parts{k},'^scan\d+$','once'))
        scanIdx = k;

        scanID = parts{k};

        % Optional suffix after scan token, e.g. SB / M / ES
        if k < numel(parts)
            nxt = parts{k+1};

            if ~isempty(regexpi(nxt,'^[A-Za-z]{1,6}[A-Za-z0-9]*$','once')) && ...
               isempty(regexpi(nxt,'^S\d+$','once')) && ...
               isempty(regexpi(nxt,'^\d+$','once'))
                scanID = [scanID '_' nxt];
            end
        end

        meta.scanID = scanID;
        break;
    end
end

% Session only if explicit S<number> exists somewhere
for k = 1:numel(parts)
    if ~isempty(regexpi(parts{k},'^S\d+$','once'))
        meta.session = parts{k};
        break;
    end
end

% Animal ID = numeric token immediately before scan token
if ~isempty(scanIdx)
    for k = scanIdx-1:-1:max(1,scanIdx-3)
        if ~isempty(regexpi(parts{k},'^\d{3,6}$','once'))
            meta.animalID = parts{k};
            break;
        end
    end
end

% ---------------------------------------------------------
% Fallbacks
% ---------------------------------------------------------
if strcmpi(meta.scanID,'N/A')
    tok = regexpi(txt,'(scan\d+(?:_[A-Za-z0-9]+)?)','tokens','once');
    if ~isempty(tok)
        meta.scanID = tok{1};
    end
end

if strcmpi(meta.animalID,'N/A')
    tok = regexpi(txtU,'\b([A-Z]{1,8}\d{6}[A-Z]?)\b','tokens','once');
    if ~isempty(tok)
        meta.animalID = strtrim(tok{1});
    end
end
end

function animalID = extractAnimalIDFromText(txt)
m = parseMetaSingleText(txt);
animalID = m.animalID;
if strcmpi(animalID,'N/A'), animalID = ''; end
end

function sess = extractSessionFromText(txt)
m = parseMetaSingleText(txt);
sess = m.session;
if strcmpi(sess,'N/A'), sess = ''; end
end

function scanID = extractScanIDFromText(txt)
m = parseMetaSingleText(txt);
scanID = m.scanID;
if strcmpi(scanID,'N/A'), scanID = ''; end
end

function idx = secToIdx(s0,s1,TR,T)
i0 = floor(s0/TR) + 1;
i1 = floor(s1/TR);
i0 = max(1, min(T, i0));
i1 = max(1, min(T, i1));
if i1 < i0
    idx = i0;
else
    idx = i0:i1;
end
end

function M = extractPSCMap(fp, b0, b1, s0, s1)
D = loadPipelineStruct(fp);
if ~isfield(D,'TR') || isempty(D.TR), error('Missing TR in %s', fp); end
if ~isfield(D,'I')  || isempty(D.I),  error('Missing I in %s', fp); end
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

function [mapOut, cache] = getCachedPSCMap(cache, dataFile, b0, b1, s0, s1)
key = makeCacheKey('PSC',dataFile,num2str(b0),num2str(b1),num2str(s0),num2str(s1));
if isstruct(cache) && isfield(cache,'pscMap') && isa(cache.pscMap,'containers.Map')
    if isKey(cache.pscMap,key)
        mapOut = cache.pscMap(key);
        return;
    end
end

mapOut = extractPSCMap(dataFile, b0, b1, s0, s1);

if isstruct(cache) && isfield(cache,'pscMap') && isa(cache.pscMap,'containers.Map')
    try
        cache.pscMap(key) = mapOut;
    catch
    end
end
end

%%% =====================================================================
%%% Group Map function %%%%
%%% =====================================================================
function [mapMean, mapT, mapP] = summarizeGroupMapStack(allMaps)
X = catAlong4(allMaps);
dimN = ndims(X);
nMap = size(X, dimN);

mapMean = nanmean_local(X, dimN);
mapMean(~isfinite(mapMean)) = 0;

if nMap < 2
    mapT = zeros(size(mapMean));
    mapP = ones(size(mapMean));
    return;
end

mapStd = nanstd_local(X, 0, dimN);
den = mapStd ./ sqrt(nMap);
den(~isfinite(den) | den <= 0) = eps;

mapT = mapMean ./ den;
mapP = 2 * tcdf_local(-abs(mapT), nMap - 1);

mapT(~isfinite(mapT)) = 0;
mapP(~isfinite(mapP)) = 1;
end

function [R, cache] = runPSCMapAnalysis(S, subjActive, activeIdx, cache)

nAnimals = size(subjActive,1);
if nAnimals < 1
    error('No active rows for Group Maps.');
end

refSide = upper(strtrimSafe(S.mapRefPacapSide));
if isempty(refSide), refSide = 'LEFT'; end
refSide = refSide(1);

allMaps   = cell(nAnimals,1);
underlays = cell(nAnimals,1);
sideInfo  = cell(nAnimals,1);

for i = 1:nAnimals
    bundleFile = strtrimSafe(subjActive{i,8});
    if isempty(bundleFile)
        bundleFile = resolveGroupBundlePath(S, subjActive(i,:));
    end

    [G, cache] = getCachedGroupBundle(cache, bundleFile);

    if ~isfield(G,'isAtlasWarped') || ~G.isAtlasWarped
        error('Bundle is not atlas-warped: %s', bundleFile);
    end

    if isfield(S,'mapUseGlobalWindows') && S.mapUseGlobalWindows
    if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
        error('Global windows require exported PSC series in bundle: %s', bundleFile);
    end

    b0 = S.mapGlobalBaseSec(1);
    b1 = S.mapGlobalBaseSec(2);
    s0 = S.mapGlobalSigSec(1);
    s1 = S.mapGlobalSigSec(2);

    mapNow = recomputeScmFromBundlePSC(G, [b0 b1], [s0 s1], S.mapSigma);

    if isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
        m2 = logical(G.mask2DCurrentSlice);
        if isequal(size(m2), size(mapNow))
            mapNow(~m2) = 0;
        end
    end

else
    if strcmpi(S.mapSource,'Use exported SCM map')
        if ~isfield(G,'scmMapAtlas') || isempty(G.scmMapAtlas)
            error('Bundle has no exported SCM map: %s', bundleFile);
        end
        mapNow = squeezeBundleMap2D(G.scmMapAtlas);

    else
        if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
            error('Bundle has no exported PSC series: %s', bundleFile);
        end
        if ~isfield(G,'baseWindowSec') || isempty(G.baseWindowSec) || ...
           ~isfield(G,'sigWindowSec')  || isempty(G.sigWindowSec)
            error('Bundle is missing exported baseline/signal windows: %s', bundleFile);
        end

        b0 = G.baseWindowSec(1);
        b1 = G.baseWindowSec(2);
        s0 = G.sigWindowSec(1);
        s1 = G.sigWindowSec(2);

        mapNow = recomputeScmFromBundlePSC(G, [b0 b1], [s0 s1], S.mapSigma);

        if isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
            m2 = logical(G.mask2DCurrentSlice);
            if isequal(size(m2), size(mapNow))
                mapNow(~m2) = 0;
            end
        end
    end
end

       if strcmpi(S.mapUnderlayMode,'Loaded custom underlay') && ~isempty(S.mapLoadedUnderlay)
        underlayNow = matchUnderlayToMap2D(S.mapLoadedUnderlay, mapNow);
    else
        underlayNow = getBestBundleUnderlay2D(G);
        underlayNow = matchUnderlayToMap2D(underlayNow, mapNow);
    end

    pacapSide = getPacapSideForRow(S, activeIdx(i), G, subjActive(i,:));
    sideInfo{i} = pacapSide;

    if strcmpi(pacapSide,'Unknown')
        info = extractRowMetaForExcel(subjActive(i,:));
        error('PACAP side is unknown for %s | %s | %s. Set it in the map preview dropdown first.', ...
            info.animalID, info.session, info.scanID);
    end

    needFlip = false;
flipMode = upper(strtrimSafe(S.mapFlipMode));

switch flipMode
    case 'FLIP RIGHT-INJECTED ANIMALS'
        needFlip = strcmpi(pacapSide,'Right');

    case 'FLIP LEFT-INJECTED ANIMALS'
        needFlip = strcmpi(pacapSide,'Left');

    case 'ALIGN TO REFERENCE HEMISPHERE'
        if refSide == 'L' && strcmpi(pacapSide,'Right')
            needFlip = true;
        elseif refSide == 'R' && strcmpi(pacapSide,'Left')
            needFlip = true;
        end

    otherwise
        needFlip = false;
end

    if needFlip
        mapNow = flipLR_any(mapNow);
        if ~isempty(underlayNow)
            underlayNow = flipLR_any(underlayNow);
        end
    end

    mapNow = double(mapNow);
    mapNow(~isfinite(mapNow)) = 0;

    allMaps{i}   = mapNow;
    underlays{i} = underlayNow;
end

if strcmpi(S.mapSummary,'Median')
    groupMap = medianCat(allMaps);
else
    groupMap = meanCat(allMaps);
end

[mapMean, mapT, mapP] = summarizeGroupMapStack(allMaps);

commonUnderlay = [];
validU = underlays(~cellfun(@isempty,underlays));
if ~isempty(validU)
    if ndims(validU{1}) == 3 && size(validU{1},3) == 3
        commonUnderlay = meanRgbUnderlays(validU);
    else
        commonUnderlay = meanCat(validU);
    end
end

R = struct();
R.mode = 'Group Maps';
R.groupMap = groupMap;
R.mapMean = mapMean;
R.mapTscore = mapT;
R.mapPvalue = mapP;
R.mapSummary = S.mapSummary;
R.n = nAnimals;
R.commonUnderlay = commonUnderlay;
R.sideInfo = sideInfo;
R.subjTable = subjActive;
R.activeIdx = activeIdx;

R.mapRender = struct();
R.mapRender.threshold = 0;
R.mapRender.caxis = S.mapCaxis;
R.mapRender.alphaModOn = S.mapAlphaModOn;
R.mapRender.modMin = S.mapModMin;
R.mapRender.modMax = S.mapModMax;
R.mapRender.blackBody = S.mapBlackBody;
R.mapRender.colormapName = S.mapColormap;
R.mapRender.flipUDPreview = true;
if isfield(S,'mapUseGlobalWindows') && S.mapUseGlobalWindows
    R.windowSource = 'Global';
    R.baseWindowSec = S.mapGlobalBaseSec;
    R.sigWindowSec  = S.mapGlobalSigSec;
else
    R.windowSource = 'Per bundle';
    R.baseWindowSec = [];
    R.sigWindowSec  = [];
end
R.stats = struct('p',NaN,'alpha',S.alpha,'type','One-sample map t-test');
end



%%% =====================================================================
%%% TAIL HELPERS / TABLE / JAVA UITABLE / BUNDLE / RENDER / EXPORT
%%% =====================================================================

    
    function st = captureMapSeriesExportStateGA()
    S0 = guidata(hFig);
    st = struct();

    st.mapUseGlobalWindows = S0.mapUseGlobalWindows;
    st.mapGlobalBaseSec    = S0.mapGlobalBaseSec;
    st.mapGlobalSigSec     = S0.mapGlobalSigSec;

    st.mapSourceString = '';
    try
        st.mapSourceString = getPopupStringSafeGA(S0.hMapSource);
    catch
    end
end

function restoreMapSeriesExportStateGA(st)
    if nargin < 1 || isempty(st)
        return;
    end

    S0 = guidata(hFig);

    if isfield(st,'mapUseGlobalWindows')
        S0.mapUseGlobalWindows = st.mapUseGlobalWindows;
    end
    if isfield(st,'mapGlobalBaseSec')
        S0.mapGlobalBaseSec = st.mapGlobalBaseSec;
    end
    if isfield(st,'mapGlobalSigSec')
        S0.mapGlobalSigSec = st.mapGlobalSigSec;
    end

    guidata(hFig,S0);

    try
        if isfield(st,'mapSourceString') && ~isempty(st.mapSourceString)
            setPopupToString(S0.hMapSource, st.mapSourceString);
        end
    catch
    end

    syncMapWindowUiGA();
    updateMapTabPreview();
end

function forceMapSeriesExportStateGA()
    S0 = guidata(hFig);

    S0.mapUseGlobalWindows = true;
    guidata(hFig,S0);

    try
        set(S0.hMapUseGlobalWin,'Value',1);
    catch
    end

    try
        setPopupToString(S0.hMapSource,'Recompute from exported PSC');
    catch
    end

    syncMapWindowUiGA();
end

function syncMapWindowUiGA()
    S0 = guidata(hFig);

    try
        set(S0.hMapUseGlobalWin,'Value',double(S0.mapUseGlobalWindows));
    catch
    end
    try
        set(S0.hMapBase0,'String',num2str(S0.mapGlobalBaseSec(1)));
        set(S0.hMapBase1,'String',num2str(S0.mapGlobalBaseSec(2)));
    catch
    end
    try
        set(S0.hMapSig0,'String',num2str(S0.mapGlobalSigSec(1)));
        set(S0.hMapSig1,'String',num2str(S0.mapGlobalSigSec(2)));
    catch
    end
end

function s = getPopupStringSafeGA(hPop)
    s = '';
    try
        items = get(hPop,'String');
        v = get(hPop,'Value');
        if iscell(items)
            v = max(1,min(numel(items),v));
            s = char(items{v});
        else
            v = max(1,min(size(items,1),v));
            s = strtrim(items(v,:));
        end
    catch
        s = '';
    end
end

function baseSec = getCurrentMapBaseWindowSecGA()
    S0 = guidata(hFig);

    baseSec = [30 240];

    try
        b0 = str2double(strtrim(get(S0.hMapBase0,'String')));
        b1 = str2double(strtrim(get(S0.hMapBase1,'String')));
        if isfinite(b0) && isfinite(b1)
            baseSec = [b0 b1];
        elseif isfield(S0,'mapGlobalBaseSec') && numel(S0.mapGlobalBaseSec) == 2
            baseSec = S0.mapGlobalBaseSec;
        end
    catch
        try
            if isfield(S0,'mapGlobalBaseSec') && numel(S0.mapGlobalBaseSec) == 2
                baseSec = S0.mapGlobalBaseSec;
            end
        catch
        end
    end

    if baseSec(2) < baseSec(1)
        baseSec = fliplr(baseSec);
    end
end

function totalSec = estimateGroupSeriesTotalSecGA(S0)
    totalSec = 0;

    try
        dispRows = findBundleDisplayRowsGA(S0);
    catch
        dispRows = [];
    end

    if isempty(dispRows)
        return;
    end

    secs = [];

    for i = 1:numel(dispRows)
        r = dispRows(i);
        f = '';

        try
            f = strtrimSafe(S0.subj{r,8});
        catch
            f = '';
        end

        if isempty(f) || exist(f,'file') ~= 2
            continue;
        end

        try
            L = load(f,'G');
            if ~isfield(L,'G') || isempty(L.G)
                continue;
            end
            G = L.G;

            if isfield(G,'tsec') && ~isempty(G.tsec)
                secs(end+1) = double(G.tsec(end)); %#ok<AGROW>
            elseif isfield(G,'TR') && isfield(G,'nT') && isfinite(G.TR) && isfinite(G.nT)
                secs(end+1) = double((G.nT - 1) * G.TR); %#ok<AGROW>
            elseif isfield(G,'pscAtlas4D') && isfield(G,'TR') && ~isempty(G.pscAtlas4D)
                sz = size(G.pscAtlas4D);
                secs(end+1) = double((sz(end) - 1) * G.TR); %#ok<AGROW>
            end
        catch
        end
    end

    if ~isempty(secs)
        totalSec = min(secs);
    end
end

    function renderGroupMapMontageSlidePNG(outFile, pngList, lblList, titleStr, footerStr, dpiVal, renderInfo)
if nargin < 7
    renderInfo = struct();
end

figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
set(figS,'Units','inches','Position',[0.5 0.5 13.333 7.5]);
set(figS,'PaperPositionMode','auto');

annotation(figS,'textbox',[0.02 0.91 0.96 0.06], ...
    'String',titleStr, ...
    'Color','w', ...
    'EdgeColor','none', ...
    'FontName','Arial', ...
    'FontSize',16, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','center', ...
    'Interpreter','none');

annotation(figS,'textbox',[0.02 0.01 0.96 0.04], ...
    'String',footerStr, ...
    'Color','w', ...
    'EdgeColor','none', ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'Interpreter','none');

% Shared colorbar on the LEFT for the whole slide
drawSharedColorbarForMontage(figS, renderInfo);

x0 = 0.13;
x1 = 0.98;
yBot = 0.08;
yTop = 0.88;
rowGap = 0.05;
colGap = 0.02;

cellH = ((yTop - yBot) - rowGap) / 2;
cellW = (x1 - x0 - 2*colGap) / 3;

for k = 1:min(6,numel(pngList))
    if k <= 3
        col = k;
        x = x0 + (col-1)*(cellW+colGap);
        y = yBot + cellH + rowGap;
    else
        col = k - 3;
        x = x0 + (col-1)*(cellW+colGap);
        y = yBot;
    end

    axI = axes('Parent',figS,'Position',[x y cellW cellH]);
    imshow(imread(pngList{k}),'Parent',axI);
    axis(axI,'off');

    annotation(figS,'textbox',[x y+cellH+0.003 cellW 0.028], ...
        'String',lblList{k}, ...
        'Color','w', ...
        'EdgeColor','none', ...
        'FontName','Arial', ...
        'FontSize',11, ...
        'FontWeight','bold', ...
        'HorizontalAlignment','center', ...
        'Interpreter','none');
end

print(figS,outFile,'-dpng',sprintf('-r%d',dpiVal),'-opengl');
close(figS);
    end

    
  function drawSharedColorbarForMontage(figS, renderInfo)
    cax = [0 100];

    try
        if isfield(renderInfo,'caxis') && numel(renderInfo.caxis) >= 2
            cax = double(renderInfo.caxis(1:2));
        end
    catch
    end

    % Force PPT colorbar to blackbdy
    cm = getNamedCmapLocal('blackbdy_iso', 512);
    if isempty(cm) || size(cm,2) ~= 3
        cm = hot(512);
    end

    % ---- exact tuning knobs ----
    barX    = 0.045;
barY    = 0.120;
barW    = 0.018;
barH    = 0.760;
tickLen = 0.008;
numGap  = 0.006;
lblGap  = 0.045;   % was smaller
    % ----------------------------

    try
        delete(findall(figS,'Type','ColorBar'));
    catch
    end

    % Bar image only
    axBar = axes('Parent',figS, ...
        'Units','normalized', ...
        'Position',[barX barY barW barH], ...
        'Color','none', ...
        'XColor','none', ...
        'YColor','none', ...
        'XTick',[], ...
        'YTick',[], ...
        'Visible','off');

    image(axBar, [0 1], [cax(1) cax(2)], reshape(cm,[size(cm,1) 1 3]));
    set(axBar,'YDir','normal');
    axis(axBar,'tight');
    axis(axBar,'off');

    annotation(figS,'rectangle',[barX barY barW barH], ...
        'Color','w', ...
        'LineWidth',0.8);

    ticks = linspace(cax(1), cax(2), 6);

    for i = 1:numel(ticks)
        tval = ticks(i);
        ty = barY + barH * ((tval - cax(1)) / max(eps, diff(cax)));

        annotation(figS,'line', ...
            [barX + barW, barX + barW + tickLen], ...
            [ty ty], ...
            'Color','w', ...
            'LineWidth',0.8);

        annotation(figS,'textbox', ...
            [barX + barW + tickLen + numGap, ty - 0.015, 0.040, 0.030], ...
            'String',sprintf('%g', round(tval)), ...
            'Color','w', ...
            'EdgeColor','none', ...
            'BackgroundColor','none', ...
            'FontName','Arial', ...
            'FontSize',12, ...
            'HorizontalAlignment','left', ...
            'VerticalAlignment','middle', ...
            'Interpreter','none');
    end

    axLbl = axes('Parent',figS, ...
        'Units','normalized', ...
        'Position',[barX + barW + lblGap, barY, 0.060, barH], ...
        'Color','none', ...
        'XColor','none', ...
        'YColor','none', ...
        'XTick',[], ...
        'YTick',[], ...
        'Visible','off');

    text(axLbl,0.40,0.5,'Signal change (%)', ...
        'Color','w', ...
        'FontName','Arial', ...
        'FontSize',10, ...
        'FontWeight','bold', ...
        'Rotation',90, ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', ...
        'Interpreter','none');

    axis(axLbl,'off');
end

    function renderGroupMapInfoSlidePNG(outFile, S0, footerStr, dpiVal)
figS = figure('Visible','off','Color',[0 0 0],'InvertHardcopy','off');
set(figS,'Units','inches','Position',[0.5 0.5 13.333 7.5]);
set(figS,'PaperPositionMode','auto');

annotation(figS,'textbox',[0.02 0.91 0.96 0.06], ...
    'String','Group map export overview', ...
    'Color','w', ...
    'EdgeColor','none', ...
    'FontName','Arial', ...
    'FontSize',18, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','center', ...
    'Interpreter','none');

winTxt = 'Per-bundle exported windows';
try
    if isfield(S0,'mapUseGlobalWindows') && S0.mapUseGlobalWindows
        winTxt = sprintf('Global windows | base %.0f-%.0fs | signal %.0f-%.0fs', ...
            S0.mapGlobalBaseSec(1), S0.mapGlobalBaseSec(2), ...
            S0.mapGlobalSigSec(1),  S0.mapGlobalSigSec(2));
    end
catch
end

[hdr, tbl, nKept, nRemoved] = buildGroupMapExportOverviewTableGA(S0);

infoLines = { ...
    sprintf('Animals kept for maps: %d', nKept), ...
    sprintf('Animals removed / inactive: %d', nRemoved), ...
    sprintf('Summary: %s', strtrimSafe(S0.mapSummary)), ...
    sprintf('Source: %s', strtrimSafe(S0.mapSource)), ...
    sprintf('Windows: %s', winTxt), ...
    sprintf('Alpha modulation: min %.3g | max %.3g', S0.mapModMin, S0.mapModMax), ...
    sprintf('Spatial smoothing sigma: %.3g', S0.mapSigma), ...
    sprintf('C-axis: [%.3g %.3g]', S0.mapCaxis(1), S0.mapCaxis(2)), ...
    sprintf('Flip mode: %s', strtrimSafe(S0.mapFlipMode)), ...
    sprintf('Reference hemisphere: %s', strtrimSafe(S0.mapRefPacapSide)), ...
    sprintf('Underlay: %s', strtrimSafe(S0.mapUnderlayMode)), ...
    sprintf('Alignment: %s', mapAlignmentModeText(S0))};

annotation(figS,'textbox',[0.05 0.66 0.90 0.18], ...
    'String',infoLines, ...
    'Color','w', ...
    'EdgeColor',[0.40 0.40 0.40], ...
    'BackgroundColor',[0.08 0.08 0.08], ...
    'FontName','Consolas', ...
    'FontSize',12, ...
    'HorizontalAlignment','left', ...
    'Interpreter','none');

tableLines = buildFixedWidthGroupMapInfoTable(hdr, tbl);

annotation(figS,'textbox',[0.05 0.12 0.90 0.46], ...
    'String',tableLines, ...
    'Color','w', ...
    'EdgeColor',[0.40 0.40 0.40], ...
    'BackgroundColor',[0.06 0.06 0.06], ...
    'FontName','Consolas', ...
    'FontSize',13, ...
    'HorizontalAlignment','left', ...
    'Interpreter','none');

annotation(figS,'textbox',[0.02 0.01 0.96 0.04], ...
    'String',footerStr, ...
    'Color','w', ...
    'EdgeColor','none', ...
    'FontName','Arial', ...
    'FontSize',10, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'Interpreter','none');

print(figS,outFile,'-dpng',sprintf('-r%d',dpiVal),'-opengl');
close(figS);
end


function lines = buildFixedWidthGroupMapInfoTable(hdr, tbl)
    if nargin < 1 || isempty(hdr)
        hdr = {'Animal','Sess','Scan','Inj Side','Action','Use'};
    end

    if nargin < 2 || isempty(tbl)
        tbl = {'-','-','-','-','-','-'};
    end

    nCol = numel(hdr);
    widths = zeros(1,nCol);

    % header widths
    for c = 1:nCol
        widths(c) = numel(strtrimSafe(hdr{c}));
    end

    % table widths
    for r = 1:size(tbl,1)
        for c = 1:min(nCol,size(tbl,2))
            widths(c) = max(widths(c), numel(strtrimSafe(tbl{r,c})));
        end
    end

    % a little padding
    widths = widths + 2;

    fmt = '';
    for c = 1:nCol
        fmt = [fmt '%-' num2str(widths(c)) 's']; %#ok<AGROW>
    end

    lines = cell(size(tbl,1)+2,1);
    lines{1} = sprintf(fmt, hdr{:});

    sep = '';
    for c = 1:nCol
        sep = [sep repmat('-',1,widths(c))]; %#ok<AGROW>
    end
    lines{2} = sep;

    for r = 1:size(tbl,1)
        row = cell(1,nCol);
        for c = 1:nCol
            if c <= size(tbl,2)
                row{c} = strtrimSafe(tbl{r,c});
            else
                row{c} = '';
            end
        end
        lines{r+2} = sprintf(fmt, row{:});
    end
end



function tf = canUsePptApiGA()
    tf = false;
    try
        tf = ~isempty(which('mlreportgen.ppt.Presentation'));
    catch
        tf = false;
    end
end


function lbl = makeSCMStyleTileLabelGA(s0, s1, baseSec, injSec)
% Label shown above each exported PPT map panel.
% SCM-style: signal seconds + PI minutes + baseline seconds.

    if nargin < 4
        injSec = NaN;
    end

    if nargin < 3 || isempty(baseSec) || numel(baseSec) < 2
        baseSec = [NaN NaN];
    end

    sigTxt = sprintf('Signal %.0f-%.0fs', s0, s1);

    if isfinite(injSec)
        if s1 <= injSec
            piTxt = sprintf('pre-PI %.1f-%.1f min', ...
                (s0 - injSec) / 60, ...
                (s1 - injSec) / 60);
        elseif s0 < injSec && s1 > injSec
            piTxt = sprintf('PI crossing %.1f-%.1f min', ...
                (s0 - injSec) / 60, ...
                (s1 - injSec) / 60);
        else
            piTxt = sprintf('PI %.1f-%.1f min', ...
                (s0 - injSec) / 60, ...
                (s1 - injSec) / 60);
        end
    else
        piTxt = sprintf('%.1f-%.1f min', s0/60, s1/60);
    end

    if all(isfinite(baseSec(1:2)))
        baseTxt = sprintf('Base %.0f-%.0fs', baseSec(1), baseSec(2));
    else
        baseTxt = 'Base unknown';
    end

    lbl = sprintf('%s | %s\n%s', sigTxt, piTxt, baseTxt);
end


function footerStr = makeGroupMapPPTFooterGA(S0, baseSec, winLen, injSec, animalIDsUsed)
% Footer shown on all exported PPT slides.

    if nargin < 5 || isempty(animalIDsUsed)
        animalIDsUsed = {'unknown'};
    end

    animalTxt = strjoin(animalIDsUsed(:).', ', ');

    % Avoid ultra-long footer if many animals
    if numel(animalTxt) > 150
        animalTxt = [animalTxt(1:147) '...'];
    end

    if isfinite(injSec)
        piTxt = sprintf('PI zero/injection %.0fs (%.2f min)', injSec, injSec/60);
    else
        piTxt = 'PI zero/injection not set';
    end

    footerStr = sprintf([ ...
        'Base %.0f-%.0fs | Window %.0fs | %s | ' ...
        'Alpha mod min/max %.3g/%.3g | Caxis [%.3g %.3g] | Sigma %.3g | ' ...
        'Animals n=%d: %s'], ...
        baseSec(1), baseSec(2), ...
        winLen, ...
        piTxt, ...
        S0.mapModMin, S0.mapModMax, ...
        S0.mapCaxis(1), S0.mapCaxis(2), ...
        S0.mapSigma, ...
        numel(animalIDsUsed), ...
        animalTxt);
end


function [animalIDsUsed, animalDetailsUsed] = getGroupMapAnimalsUsedGA(S0)
% Return animal IDs and detailed labels used for current group-map export.

    animalIDsUsed = {};
    animalDetailsUsed = {};

    rows = [];

    try
        [rows, ~] = findActiveBundleRowsGA(S0);
    catch
        rows = [];
    end

    if isempty(rows)
        try
            rows = findBundleDisplayRowsGA(S0);
        catch
            rows = 1:size(S0.subj,1);
        end
    end

    if isempty(rows)
        animalIDsUsed = {'unknown'};
        animalDetailsUsed = {'unknown'};
        return;
    end

    for ii = 1:numel(rows)
        r = rows(ii);

        if r < 1 || r > size(S0.subj,1)
            continue;
        end

        useThis = true;
        try
            key = makeBundleEntityKeyForRow(S0, r);
            if ~isempty(key)
                useThis = entityUseStateForKey(S0, key);
            else
                useThis = logicalCellValue(S0.subj{r,1});
            end
        catch
            try
                useThis = logicalCellValue(S0.subj{r,1});
            catch
                useThis = true;
            end
        end

        if ~useThis
            continue;
        end

        try
            info = extractRowMetaLight(S0.subj(r,:));
        catch
            info = struct();
            info.animalID = strtrimSafe(S0.subj{r,2});
            info.session  = '';
            info.scanID   = '';
        end

        animalID = strtrimSafe(info.animalID);
        if isempty(animalID) || strcmpi(animalID,'N/A')
            animalID = strtrimSafe(S0.subj{r,2});
        end
        if isempty(animalID)
            animalID = sprintf('row%d', r);
        end

        detail = makeBundleDisplayTitle(animalID, info.session, info.scanID);

        if ~any(strcmpi(animalIDsUsed, animalID))
            animalIDsUsed{end+1} = animalID; %#ok<AGROW>
        end

        if ~any(strcmpi(animalDetailsUsed, detail))
            animalDetailsUsed{end+1} = detail; %#ok<AGROW>
        end
    end

    if isempty(animalIDsUsed)
        animalIDsUsed = {'unknown'};
    end

    if isempty(animalDetailsUsed)
        animalDetailsUsed = animalIDsUsed;
    end
end


function oneLine = makeGroupMapSlideInfoLineGA(S0, animalIDsUsed)
% Compact subtitle for each PPT map slide.

    if nargin < 2 || isempty(animalIDsUsed)
        animalIDsUsed = {'unknown'};
    end

    animalTxt = strjoin(animalIDsUsed(:).', ', ');
    if numel(animalTxt) > 120
        animalTxt = [animalTxt(1:117) '...'];
    end

    oneLine = sprintf('Animals n=%d: %s | Alpha mod min/max %.3g/%.3g | Caxis [%.3g %.3g] | Colormap %s', ...
        numel(animalIDsUsed), ...
        animalTxt, ...
        S0.mapModMin, S0.mapModMax, ...
        S0.mapCaxis(1), S0.mapCaxis(2), ...
        strtrimSafe(S0.mapColormap));
end

function writeGroupMapSeriesPPTEditableGA(pptPath, tilePNGs, tileLBLs, S0, footerStr, renderInfo, assetDir)
% writeGroupMapSeriesPPTEditableGA
% Editable PowerPoint export for GroupAnalysis group-map series.
%
% Main difference from old writePptFromSlidePNGsGA:
%   OLD: each slide was one flattened PNG.
%   NEW: each map tile is inserted as a separate PowerPoint Picture object.
%
% This makes the export behave like SCM GUI:
%   - each brain/map panel can be clicked/copied separately
%   - labels/footer are editable text boxes
%   - individual tile PNGs remain saved beside the PPT

    import mlreportgen.ppt.*

    if nargin < 2 || isempty(tilePNGs)
        error('No tile PNGs were provided for editable PPT export.');
    end

    if nargin < 3 || isempty(tileLBLs)
        tileLBLs = cell(size(tilePNGs));
        for i = 1:numel(tilePNGs)
            tileLBLs{i} = sprintf('Window %d', i);
        end
    end

    if nargin < 7 || isempty(assetDir)
        assetDir = fileparts(pptPath);
    end
    if isempty(assetDir)
        assetDir = pwd;
    end
    if exist(assetDir,'dir') ~= 7
        mkdir(assetDir);
    end

    pptDir = fileparts(pptPath);
    if ~isempty(pptDir) && exist(pptDir,'dir') ~= 7
        mkdir(pptDir);
    end

    if exist(pptPath,'file') == 2
        delete(pptPath);
    end

    % Basic 16:9 coordinates in inches
    slideW = 13.333;
    slideH = 7.500;

    % Create reusable background and colorbar assets
    bgPng = fullfile(assetDir, 'PPT_black_background.png');
    makeSolidPngGA(bgPng, [0 0 0]);

    cbPng = fullfile(assetDir, 'PPT_shared_colorbar.png');
    renderSharedColorbarPNGGA(cbPng, renderInfo);
[animalIDsUsed, animalDetailsUsed] = getGroupMapAnimalsUsedGA(S0);
slideInfoLine = makeGroupMapSlideInfoLineGA(S0, animalIDsUsed);
    ppt = [];
    try
        ppt = Presentation(pptPath);

        try
            ppt.Layout = 'widescreen';
        catch
        end

        open(ppt);

        % =========================================================
        % Slide 1: editable overview slide
        % =========================================================
        slide = add(ppt,'Blank');
        addPptPictureStretchGA(slide, bgPng, 0, 0, slideW, slideH);

        addPptTextBoxGA(slide, ...
            'Group map export overview', ...
            0.35, 0.22, 12.60, 0.45, ...
            22, true, 'FFFFFF', 'center', 'Arial');

        [hdr, tbl, nKept, nRemoved] = buildGroupMapExportOverviewTableGA(S0);

        winTxt = 'Per-bundle exported windows';
        try
            if isfield(S0,'mapUseGlobalWindows') && S0.mapUseGlobalWindows
                winTxt = sprintf('Global windows | base %.0f-%.0fs | signal %.0f-%.0fs', ...
                    S0.mapGlobalBaseSec(1), S0.mapGlobalBaseSec(2), ...
                    S0.mapGlobalSigSec(1),  S0.mapGlobalSigSec(2));
            end
        catch
        end

     infoLines = { ...
    sprintf('Animals kept for maps: %d', nKept), ...
    sprintf('Animals removed / inactive: %d', nRemoved), ...
    sprintf('Animal IDs used: %s', strjoin(animalIDsUsed(:).', ', ')), ...
    sprintf('Animal/session/scan used: %s', strjoin(animalDetailsUsed(:).', '; ')), ...
    sprintf('Summary: %s', strtrimSafe(S0.mapSummary)), ...
            sprintf('Source: %s', strtrimSafe(S0.mapSource)), ...
            sprintf('Windows: %s', winTxt), ...
            sprintf('Alpha modulation: min %.3g | max %.3g', S0.mapModMin, S0.mapModMax), ...
            sprintf('Spatial smoothing sigma: %.3g', S0.mapSigma), ...
            sprintf('C-axis: [%.3g %.3g]', S0.mapCaxis(1), S0.mapCaxis(2)), ...
            sprintf('Colormap: %s', strtrimSafe(S0.mapColormap)), ...
            sprintf('Flip mode: %s', strtrimSafe(S0.mapFlipMode)), ...
            sprintf('Reference hemisphere: %s', strtrimSafe(S0.mapRefPacapSide)), ...
            sprintf('Underlay: %s', strtrimSafe(S0.mapUnderlayMode))};

        addPptTextBoxGA(slide, ...
            strjoin(infoLines, newline), ...
            0.55, 0.95, 12.25, 1.65, ...
            12, false, 'FFFFFF', 'left', 'Consolas');

        tableLines = buildFixedWidthGroupMapInfoTable(hdr, tbl);

        addPptTextBoxGA(slide, ...
            strjoin(tableLines, newline), ...
            0.55, 2.90, 12.25, 3.90, ...
            11, false, 'FFFFFF', 'left', 'Consolas');

        addPptTextBoxGA(slide, ...
            footerStr, ...
            0.35, 7.13, 12.60, 0.22, ...
            9, false, 'CCCCCC', 'right', 'Arial');

        % =========================================================
        % Main map slides: 6 individual panels per slide
        % =========================================================
        perSlide = 6;
        nSlides  = ceil(numel(tilePNGs) / perSlide);

        for si = 1:nSlides
            i0 = (si - 1) * perSlide + 1;
            i1 = min(si * perSlide, numel(tilePNGs));
            idx = i0:i1;

            slide = add(ppt,'Blank');
            addPptPictureStretchGA(slide, bgPng, 0, 0, slideW, slideH);

           addPptTextBoxGA(slide, ...
    sprintf('Group signal change maps | slide %d/%d', si, nSlides), ...
    0.35, 0.14, 12.60, 0.34, ...
    18, true, 'FFFFFF', 'center', 'Arial');

addPptTextBoxGA(slide, ...
    slideInfoLine, ...
    0.35, 0.52, 12.60, 0.24, ...
    9, false, 'CCCCCC', 'center', 'Arial');

            % Shared colorbar as its own movable object
           % Larger SCM-style shared colorbar
addPptPictureFitGA(slide, cbPng, 0.10, 0.95, 1.08, 6.10);

            % Grid geometry
           % Leave more room for larger colorbar and two-line labels
x0 = 1.32;
xR = 13.05;
y0 = 1.24;

colGap = 0.18;
rowGap = 0.55;

tileW = (xR - x0 - 2*colGap) / 3;
tileH = 2.45;

labelH = 0.36;

            for kk = 1:numel(idx)
                localK = kk;
                globalK = idx(kk);

                row = floor((localK - 1) / 3);   % 0 or 1
                col = mod(localK - 1, 3);        % 0,1,2

                x = x0 + col * (tileW + colGap);
                y = y0 + row * (tileH + rowGap);

                lbl = tileLBLs{globalK};

                % Editable label above each map tile
                addPptTextBoxGA(slide, ...
                    lbl, ...
                   x, max(0.78, y - labelH - 0.05), tileW, labelH, ...
9, true, 'FFFFFF', 'center', 'Arial');

                % Individual image object
                addPptPictureFitGA(slide, tilePNGs{globalK}, x, y, tileW, tileH);
            end

            addPptTextBoxGA(slide, ...
                footerStr, ...
                0.35, 7.13, 12.60, 0.22, ...
                9, false, 'CCCCCC', 'right', 'Arial');
        end

        close(ppt);

    catch ME
        try
            if ~isempty(ppt)
                close(ppt);
            end
        catch
        end
        error('Editable PowerPoint export failed: %s', ME.message);
    end

    pause(0.25);

    if exist(pptPath,'file') ~= 2
        error('PowerPoint file was not created: %s', pptPath);
    end
end


function addPptPictureStretchGA(slide, imgFile, x, y, w, h)
% Add picture with exact stretch. Used for black background only.
    import mlreportgen.ppt.*

    pic = Picture(imgFile);
    pic.X = inchStrGA(x);
    pic.Y = inchStrGA(y);
    pic.Width  = inchStrGA(w);
    pic.Height = inchStrGA(h);
    add(slide, pic);
end

function addPptPictureFitGA(slide, imgFile, x, y, boxW, boxH)
% Add picture while preserving aspect ratio and centering inside box.
    import mlreportgen.ppt.*

    if exist(imgFile,'file') ~= 2
        return;
    end

    try
        info = imfinfo(imgFile);
        imW = double(info.Width);
        imH = double(info.Height);
    catch
        imW = boxW;
        imH = boxH;
    end

    if imW <= 0 || imH <= 0
        imW = boxW;
        imH = boxH;
    end

    imAR  = imW / imH;
    boxAR = boxW / boxH;

    if boxAR > imAR
        h = boxH;
        w = h * imAR;
    else
        w = boxW;
        h = w / imAR;
    end

    xx = x + 0.5 * (boxW - w);
    yy = y + 0.5 * (boxH - h);

    pic = Picture(imgFile);
    pic.X = inchStrGA(xx);
    pic.Y = inchStrGA(yy);
    pic.Width  = inchStrGA(w);
    pic.Height = inchStrGA(h);
    add(slide, pic);
end

function addPptTextBoxGA(slide, txt, x, y, w, h, fontSizePt, isBold, colorHex, hAlign, fontName)
% Add editable PPT text box.
% Uses robust try/catch so older MATLAB/PPT API versions do not crash on style.

    import mlreportgen.ppt.*

    if nargin < 7 || isempty(fontSizePt), fontSizePt = 11; end
    if nargin < 8 || isempty(isBold),     isBold = false; end
    if nargin < 9 || isempty(colorHex),   colorHex = 'FFFFFF'; end
    if nargin < 10 || isempty(hAlign),    hAlign = 'left'; end
    if nargin < 11 || isempty(fontName),  fontName = 'Arial'; end

    try
        if iscell(txt)
            txt = strjoin(txt, newline);
        end
    catch
    end

    txt = char(txt);

    tb = TextBox();
    tb.X = inchStrGA(x);
    tb.Y = inchStrGA(y);
    tb.Width  = inchStrGA(w);
    tb.Height = inchStrGA(h);

    lines = regexp(txt, '\r\n|\n|\r', 'split');
    if isempty(lines)
        lines = {txt};
    end

    for i = 1:numel(lines)
        p = Paragraph(lines{i});

        try
            st = { ...
                FontFamily(fontName), ...
                FontSize(sprintf('%dpt', round(fontSizePt))), ...
                Color(colorHex)};

            if isBold
                st{end+1} = Bold(true); %#ok<AGROW>
            end

            if ~isempty(hAlign)
                st{end+1} = HAlign(hAlign); %#ok<AGROW>
            end

            p.Style = st;
        catch
        end

        try
            add(tb, p);
        catch
        end
    end

    add(slide, tb);
end

function s = inchStrGA(v)
    s = sprintf('%.3fin', double(v));
end

function makeSolidPngGA(outFile, rgb)
% Create tiny solid PNG used as slide background.
    if nargin < 2 || isempty(rgb)
        rgb = [0 0 0];
    end

    rgb = double(rgb(:)');
    if max(rgb) <= 1
        rgb = uint8(round(255 * rgb));
    else
        rgb = uint8(rgb);
    end

    I = zeros(20,20,3,'uint8');
    I(:,:,1) = rgb(1);
    I(:,:,2) = rgb(2);
    I(:,:,3) = rgb(3);

    try
        imwrite(I, outFile);
    catch
    end
end

    function renderSharedColorbarPNGGA(outFile, renderInfo)
% Render shared colorbar as a separate PNG object.
% Larger SCM-style colorbar for editable PPT export.

    cax = [0 100];
    cmName = 'blackbdy_iso';

    try
        if isfield(renderInfo,'caxis') && numel(renderInfo.caxis) >= 2
            cax = double(renderInfo.caxis(1:2));
        end
    catch
    end

    try
        if isfield(renderInfo,'colormapName') && ~isempty(renderInfo.colormapName)
            cmName = char(renderInfo.colormapName);
        end
    catch
    end

    if ~isfinite(cax(1)) || ~isfinite(cax(2)) || cax(2) <= cax(1)
        cax = [0 100];
    end

    cm = getNamedCmapLocal(cmName, 512);
    if isempty(cm) || size(cm,2) ~= 3
        cm = hot(512);
    end

    f = figure('Visible','off', ...
        'Color',[0 0 0], ...
        'InvertHardcopy','off', ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off');

    % Bigger source image = sharper and larger in PPT
    set(f,'Position',[100 100 420 1250]);

    ax = axes('Parent',f, ...
        'Units','normalized', ...
        'Position',[0.16 0.06 0.24 0.88]);

    image(ax, [0 1], [cax(1) cax(2)], reshape(cm,[size(cm,1) 1 3]));
    set(ax,'YDir','normal');
    set(ax,'XTick',[]);
    set(ax,'YAxisLocation','right');
    set(ax,'YTick',linspace(cax(1), cax(2), 6));
    set(ax,'YColor',[1 1 1]);
    set(ax,'XColor',[1 1 1]);
    set(ax,'Color',[0 0 0]);
    set(ax,'FontName','Arial');
    set(ax,'FontSize',17);
    set(ax,'FontWeight','bold');
    set(ax,'LineWidth',1.2);
    box(ax,'on');

    ylabel(ax,'Signal change (%)', ...
        'Color',[1 1 1], ...
        'FontName','Arial', ...
        'FontSize',16, ...
        'FontWeight','bold');

    try
        print(f, outFile, '-dpng', '-r300', '-opengl');
    catch
        print(f, outFile, '-dpng', '-r300');
    end

    close(f);
end

function writePptFromSlidePNGsGA(pptPath, slidePNGs)
    import mlreportgen.ppt.*

    if nargin < 2 || isempty(slidePNGs)
        error('No slide PNGs were provided for PPT export.');
    end

    pptDir = fileparts(pptPath);
    if ~isempty(pptDir) && exist(pptDir,'dir') ~= 7
        mkdir(pptDir);
    end

    if exist(pptPath,'file') == 2
        delete(pptPath);
    end

    ppt = [];
    try
        ppt = Presentation(pptPath);
        open(ppt);

        for i = 1:numel(slidePNGs)
            imgFile = slidePNGs{i};
            if exist(imgFile,'file') ~= 2
                continue;
            end

            try
                slide = add(ppt,'Blank');
            catch
                slide = add(ppt);
            end

            pic = Picture(imgFile);
            pic.X = '0in';
            pic.Y = '0in';
            pic.Width  = '13.333in';
            pic.Height = '7.5in';
            add(slide,pic);
        end

        close(ppt);

    catch ME
        try
            if ~isempty(ppt)
                close(ppt);
            end
        catch
        end
        error('PowerPoint export failed: %s', ME.message);
    end

    pause(0.25);

    if exist(pptPath,'file') ~= 2
        error('PowerPoint file was not created: %s', pptPath);
    end
end

function [hdr, tbl, nKept, nRemoved] = buildGroupMapExportOverviewTableGA(S0)
hdr = {'Animal','Sess','Scan','Inj Side','Map Use'};
tbl = cell(0,5);
nKept = 0;
nRemoved = 0;

S0 = ensureRowPacapSideSize(S0);
dispRows = findBundleDisplayRowsGA(S0);

if isempty(dispRows)
    tbl = {'-','-','-','-','-'};
    return;
end

for i = 1:numel(dispRows)
    r = dispRows(i);
    info = extractRowMetaLight(S0.subj(r,:));

    injSide = 'Unknown';
    try
        if r <= numel(S0.rowPacapSide)
            injSide = strtrimSafe(S0.rowPacapSide{r});
        end
    catch
    end

    if strcmpi(injSide,'L'), injSide = 'Left';  end
    if strcmpi(injSide,'R'), injSide = 'Right'; end
    if isempty(injSide),     injSide = 'Unknown'; end

    keepState = 'Removed';
    try
        key = makeBundleEntityKeyForRow(S0, r);
        if entityUseStateForKey(S0, key)
            keepState = 'Kept';
            nKept = nKept + 1;
        else
            nRemoved = nRemoved + 1;
        end
    catch
        nRemoved = nRemoved + 1;
    end

    tbl(end+1,1:5) = { ...
        strtrimSafe(info.animalID), ...
        strtrimSafe(info.session), ...
        displayScanID(info.scanID), ...
        injSide, ...
        keepState}; %#ok<AGROW>
end
end

    
    function [mapNow, winInfoTxt] = buildPreviewMapFromBundle(S0, G)
    winInfoTxt = '';

    % Global windows always force recomputation from exported PSC
    if isfield(S0,'mapUseGlobalWindows') && S0.mapUseGlobalWindows
        if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
            error('Global windows require exported PSC series in the bundle.');
        end

        bw = double(S0.mapGlobalBaseSec(:)).';
        sw = double(S0.mapGlobalSigSec(:)).';

        mapNow = recomputeScmFromBundlePSC(G, bw, sw, S0.mapSigma);
        winInfoTxt = sprintf('base %.0f-%.0fs | sig %.0f-%.0fs', bw(1), bw(2), sw(1), sw(2));

    else
        % Otherwise use selected Source mode
        if strcmpi(S0.mapSource,'Recompute from exported PSC')
            if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
                error('Bundle has no exported PSC series.');
            end
            if ~isfield(G,'baseWindowSec') || isempty(G.baseWindowSec) || ...
               ~isfield(G,'sigWindowSec')  || isempty(G.sigWindowSec)
                error('Bundle is missing exported baseline/signal windows.');
            end

            bw = double(G.baseWindowSec(:)).';
            sw = double(G.sigWindowSec(:)).';

            mapNow = recomputeScmFromBundlePSC(G, bw, sw, S0.mapSigma);
            winInfoTxt = sprintf('bundle base %.0f-%.0fs | sig %.0f-%.0fs', bw(1), bw(2), sw(1), sw(2));

        else
            if ~isfield(G,'scmMapAtlas') || isempty(G.scmMapAtlas)
                error('Bundle has no exported SCM map.');
            end
            mapNow = squeezeBundleMap2D(G.scmMapAtlas);
            winInfoTxt = 'exported SCM';
        end
    end

    if isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
        m2 = logical(G.mask2DCurrentSlice);
        if isequal(size(m2), size(mapNow))
            mapNow(~m2) = 0;
        end
    end

    mapNow(~isfinite(mapNow)) = 0;
end
    
    function underlayNow = resolvePreviewUnderlay(S0, G, mapNow)
    underlayNow = [];

    if strcmpi(S0.mapUnderlayMode,'Loaded custom underlay') && ~isempty(S0.mapLoadedUnderlay)
        underlayNow = matchUnderlayToMap2D(S0.mapLoadedUnderlay, mapNow);
        return;
    end

    underlayNow = getBestBundleUnderlay2D(G);
    underlayNow = matchUnderlayToMap2D(underlayNow, mapNow);
    end

function U = getBestBundleUnderlay2D(G)
    U = [];

    % Put the most likely "real display underlay" fields first
    pref = { ...
        'underlayDisplayRGB', ...
        'displayUnderlayRGB', ...
        'underlayRGB', ...
        'histologyRGB', ...
        'histologyAtlasRGB', ...
        'atlasUnderlayRGB', ...
        'underlayAtlasRGB', ...
        'underlayDisplay', ...
        'histologyDisplay', ...
        'underlayAtlas', ...
        'atlasUnderlay', ...
        'brainImageAtlas', ...
        'brainImage', ...
        'underlay', ...
        'bg'};

    for i = 1:numel(pref)
        fn = pref{i};
        if isfield(G,fn) && ~isempty(G.(fn))
            try
                U = squeezeBundleUnderlay2D(G.(fn));
                if ~isempty(U)
                    return;
                end
            catch
            end
        end
    end
end



    
    function Uout = matchUnderlayToMap2D(Uin, mapRef)
    Uout = Uin;

    if isempty(Uin) || isempty(mapRef)
        return;
    end

    tgt = size(mapRef);
    tgt = tgt(1:2);

    usz = size(Uin);
    if numel(usz) >= 2 && isequal(usz(1:2), tgt)
        return;
    end

    try
        if ndims(Uin) == 3 && size(Uin,3) == 3
            Uout = imresize(double(Uin), tgt, 'bilinear');
            Uout = normalizeRgbLocal(Uout);
        else
            Uout = imresize(double(Uin), tgt, 'bilinear');
        end
    catch
        yy = round(linspace(1, size(Uin,1), tgt(1)));
        xx = round(linspace(1, size(Uin,2), tgt(2)));

        if ndims(Uin) == 3 && size(Uin,3) == 3
            Uout = double(Uin(yy,xx,:));
            Uout = normalizeRgbLocal(Uout);
        else
            Uout = double(Uin(yy,xx));
        end
    end
end
    
    function colors = buildMapSideTableColorsDisplayOnly(rows, mapRows)
    n = size(rows,1);
    colors = repmat([0.12 0.12 0.12], max(n,2), 1);

    S0 = guidata(hFig);

    for i = 1:n
        if isempty(mapRows) || i > numel(mapRows) || ~isfinite(mapRows(i))
            colors(i,:) = [0.12 0.12 0.12];
            continue;
        end

        r = mapRows(i);
        useVal = true;
        try
            useVal = logicalCellValue(S0.subj{r,1});
        catch
        end

        if useVal
            colors(i,:) = [0.12 0.30 0.16];
        else
            colors(i,:) = [0.35 0.12 0.12];
        end
    end
end
    
   
 function key = makeBundleEntityKeyForRow(S, r)
    key = '';

    if isempty(r) || ~isfinite(r) || r < 1 || r > size(S.subj,1)
        return;
    end

    info = extractRowMetaLight(S.subj(r,:));

    animalID = lower(strtrimSafe(info.animalID));
    session  = lower(strtrimSafe(info.session));
    scanID   = lower(strtrimSafe(info.scanID));

    haveAnimal = ~isempty(animalID) && ~strcmpi(animalID,'n/a');
    haveSess   = ~isempty(session)  && ~strcmpi(session,'n/a');
    haveScan   = ~isempty(scanID)   && ~strcmpi(scanID,'n/a');

    % Only collapse rows when full identity is known
    if haveAnimal && haveSess && haveScan
        key = [animalID '|' session '|' scanID];
        return;
    end

    % Otherwise keep row unique to avoid accidental merging
    key = sprintf('row_%d', r);
end

function rows = getRowsForBundleEntityKey(S, key)
    rows = [];
    if isempty(key), return; end

    for r = 1:size(S.subj,1)
        if strcmpi(makeBundleEntityKeyForRow(S, r), key)
            rows(end+1) = r; %#ok<AGROW>
        end
    end
end

    function tf = entityUseStateForKey(S, key)
    tf = false;

    rows = getRowsForBundleEntityKey(S, key);
    if isempty(rows)
        return;
    end

    tf = true;
    for i = 1:numel(rows)
        if ~logicalCellValue(S.subj{rows(i),1})
            tf = false;
            return;
        end
    end
end

    function rRep = representativeRowForBundleEntityKey(S, key)
    rRep = [];
    rows = getRowsForBundleEntityKey(S, key);
    if isempty(rows), return; end

    for i = 1:numel(rows)
        r = rows(i);
        bf = strtrimSafe(S.subj{r,8});
        if ~isempty(bf)
            rRep = r;
            return;
        end
    end

    rRep = rows(1);
end
    
    function restyleUITableIfNeeded(hTable, C, styleKey)
if isempty(hTable) || ~ishandle(hTable)
    return;
end

needStyle = true;

try
    oldKey = getappdata(hTable,'GA_DarkStyleKey');
    if ischar(oldKey) && strcmp(oldKey, styleKey)
        needStyle = false;
    end
catch
    needStyle = true;
end

if needStyle
    try
        applyDarkUITableViewport(hTable, C);
    catch
    end
    try
        setappdata(hTable,'GA_DarkStyleKey',styleKey);
    catch
    end
end
end
function V = makeUITableDisplayData(subj, minRows)
if nargin < 2 || isempty(minRows)
    minRows = 0;
end

V = subjToUITable(subj);
n = size(V,1);

if minRows > 0 && n < minRows
    pad = cell(minRows - n, 9);
    for i = 1:size(pad,1)
        pad{i,1} = false;
        for j = 2:9
            pad{i,j} = '';
        end
    end
    V = [V; pad];
end
end

function V = stripUITablePlaceholders(V)
if isempty(V), return; end

keep = false(size(V,1),1);

for i = 1:size(V,1)
    useVal = false;
    try
        useVal = logicalCellValue(V{i,1});
    catch
    end

    hasContent = false;
    for j = 2:9
        x = V{i,j};
        if ischar(x) || isstring(x)
            if ~isempty(strtrim(char(x)))
                hasContent = true;
                break;
            end
        elseif isnumeric(x)
            if ~isempty(x) && any(isfinite(x(:)))
                hasContent = true;
                break;
            end
        elseif islogical(x)
            if any(x(:))
                hasContent = true;
                break;
            end
        else
            try
                if ~isempty(x)
                    hasContent = true;
                    break;
                end
            catch
            end
        end
    end

    keep(i) = useVal || hasContent;
end

V = V(keep,:);
end

function condName = mapConditionFromGroup(S, groupName)
condName = '';
g = upper(strtrimSafe(groupName));

if isempty(g)
    return;
end

try
    if isa(S.groupToCondMap,'containers.Map') && isKey(S.groupToCondMap, g)
        condName = strtrimSafe(S.groupToCondMap(g));
        return;
    end
catch
end

if contains(g,'PACAP') || contains(g,'CONDA') || strcmp(g,'A') || contains(g,'GROUPA')
    condName = 'CondA';
elseif contains(g,'VEH') || contains(g,'VEHICLE') || contains(g,'CONTROL') || contains(g,'CONDB') || strcmp(g,'B') || contains(g,'GROUPB')
    condName = 'CondB';
end
end

function pairs = exportGroupCondPairs(mapObj)
pairs = cell(0,2);
try
    if isa(mapObj,'containers.Map')
        k = keys(mapObj);
        for i = 1:numel(k)
            pairs(end+1,1:2) = {k{i}, mapObj(k{i})}; %#ok<AGROW>
        end
    end
catch
end
end

function mapObj = importGroupCondPairs(pairs, mapObj)
try
    if isempty(mapObj)
        mapObj = containers.Map('KeyType','char','ValueType','char');
    end
catch
    return;
end

if isempty(pairs)
    return;
end

for i = 1:size(pairs,1)
    g = strtrimSafe(pairs{i,1});
    c = strtrimSafe(pairs{i,2});
    if ~isempty(g) && ~isempty(c)
        try
            mapObj(upper(g)) = c;
        catch
        end
    end
end
end

function S = removeRowsFromState(S, sel)
sel = unique(sel(:)');
sel = sel(sel >= 1 & sel <= size(S.subj,1));
if isempty(sel)
    return;
end

oldPreviewRow = S.mapPreviewRow;

S.subj(sel,:) = [];

if isfield(S,'rowPacapSide') && ~isempty(S.rowPacapSide)
    keep = true(numel(S.rowPacapSide),1);
    keep(sel(sel <= numel(keep))) = false;
    S.rowPacapSide = S.rowPacapSide(keep);
end

if ~isempty(S.selectedRows)
    keepSel = setdiff(S.selectedRows(:)', sel, 'stable');
    for k = 1:numel(keepSel)
        keepSel(k) = keepSel(k) - sum(sel < keepSel(k));
    end
    S.selectedRows = keepSel;
else
    S.selectedRows = [];
end

if isempty(oldPreviewRow) || ~isfinite(oldPreviewRow)
    S.mapPreviewRow = NaN;
elseif any(sel == oldPreviewRow)
    S.mapPreviewRow = NaN;
else
    S.mapPreviewRow = oldPreviewRow - sum(sel < oldPreviewRow);
end

S.lastROI = struct();
S.lastMAP = struct();
S.outlierKeys = {};
S.outlierInfo = {};

S = ensureRowPacapSideSize(S);
end

function gNames = sortGroupNamesStableGA(gNames, S)
if isempty(gNames)
    return;
end

n = numel(gNames);
rank = 100 + (1:n);

for i = 1:n
    nm  = strtrimSafe(gNames{i});
    nmU = upper(nm);

    if strcmpi(S.colorMode,'Manual A/B')
        if strcmpi(nm, strtrimSafe(S.manualGroupA))
            rank(i) = min(rank(i), 1);
        elseif strcmpi(nm, strtrimSafe(S.manualGroupB))
            rank(i) = min(rank(i), 2);
        end
    end

    if contains(nmU,'CONDA') || strcmp(nmU,'A') || contains(nmU,'PACAP') || contains(nmU,'GROUPA')
        rank(i) = min(rank(i), 1);
    elseif contains(nmU,'CONDB') || strcmp(nmU,'B') || contains(nmU,'VEH') || contains(nmU,'VEHICLE') || contains(nmU,'CONTROL') || contains(nmU,'GROUPB')
        rank(i) = min(rank(i), 2);
    elseif contains(nmU,'BASELINE')
        rank(i) = min(rank(i), 3);
    elseif contains(nmU,'POST')
        rank(i) = min(rank(i), 4);
    end
end

[~,ord] = sort(rank);
gNames = gNames(ord);
end

    function d = getSmartBrowseDir(S, purpose)
if nargin < 2 || isempty(purpose)
    purpose = 'add';
end

d = '';

sel = clampSelRows(S.selectedRows, size(S.subj,1));
rowOrder = [sel(:).' setdiff(1:size(S.subj,1), sel(:).', 'stable')];

for k = 1:numel(rowOrder)
    r = rowOrder(k);
    info = extractRowMetaLight(S.subj(r,:));

    fpList = {info.bundleFile, info.roiFile, info.dataFile};
    for j = 1:numel(fpList)
        fp = strtrimSafe(fpList{j});
        if ~isempty(fp) && exist(fp,'file') == 2
            d0 = fileparts(fp);
            if exist(d0,'dir') == 7
                d = d0;
                break;
            end
        end
    end

    if ~isempty(d)
        break;
    end
end

if isempty(d)
    if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(char(S.opt.startDir),'dir') == 7
        d = char(S.opt.startDir);
    else
        d = pwd;
    end
end

if strcmpi(purpose,'save')
    gaDir = fullfile(d, 'GroupAnalysis');
    if exist(gaDir,'dir') ~= 7
        try
            mkdir(gaDir);
        catch
        end
    end
    if exist(gaDir,'dir') == 7
        d = gaDir;
    end
end

if exist(d,'dir') ~= 7
    d = pwd;
end
end

    function d = getBundleBrowseDir(S)
    d = '';

    sel = clampSelRows(S.selectedRows, size(S.subj,1));

    % 1) Strongest preference: selected rows
    candRows = sel(:).';

    % 2) If nothing selected, try active USE rows
    if isempty(candRows)
        candRows = find(logicalCol(S.subj,1)).';
    end

    % 3) If still nothing, try all rows
    if isempty(candRows)
        candRows = 1:size(S.subj,1);
    end

    for k = 1:numel(candRows)
        r = candRows(k);
        try
            d = buildBundleBrowseDirFromRow(S, S.subj(r,:));
        catch
            d = '';
        end
        if exist(d,'dir') == 7
            return;
        end
    end

    % 4) Project root fallback
    d = getPreferredPacapRootDir(S);
    if exist(d,'dir') == 7
        return;
    end

    % 5) Generic fallback
    d = getSmartBrowseDir(S,'add');
    end

function d = buildBundleBrowseDirFromRow(S, row)
    d = '';

    info = extractRowMetaLight(row);

    animalID  = strtrimSafe(info.animalID);
    sessionID = strtrimSafe(info.session);
    scanID    = upper(strtrimSafe(info.scanID));

    animalSessFolder = '';
    scanFolder = '';

    if ~isempty(animalID) && ~strcmpi(animalID,'N/A') && ...
       ~isempty(sessionID) && ~strcmpi(sessionID,'N/A')
        animalSessFolder = [animalID '_' sessionID];
    end

    % THIS WAS THE MISSING PART IN YOUR CURRENT CODE
    if ~isempty(animalSessFolder) && ~isempty(scanID) && ~strcmpi(scanID,'N/A')
        scanFolder = [animalSessFolder '_' scanID];
    end

    % Fast exact path first
    rootPACAP = getPreferredPacapRootDir(S);
    if ~isempty(rootPACAP) && exist(rootPACAP,'dir') == 7 && ...
       ~isempty(animalSessFolder) && ~isempty(scanFolder)

        cands = { ...
            fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles', 'SCM'), ...
            fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles'), ...
            fullfile(rootPACAP, animalSessFolder, scanFolder)};

        for kk = 1:numel(cands)
            if exist(cands{kk},'dir') == 7
                d = cands{kk};
                return;
            end
        end
    end

    % Fallback: infer from already stored file paths
    probeList = {info.bundleFile, info.dataFile, info.roiFile};

    for ii = 1:numel(probeList)
        probe = strtrimSafe(probeList{ii});
        if isempty(probe)
            continue;
        end

        if exist(probe,'file') == 2 || exist(probe,'dir') == 7
            if ~isempty(animalSessFolder) && ~isempty(scanFolder)
                dTry = findBundleDirFromProbe(probe, animalSessFolder, scanFolder);
                if exist(dTry,'dir') == 7
                    d = dTry;
                    return;
                end
            end

            if exist(probe,'file') == 2
                d = fileparts(probe);
            else
                d = probe;
            end

            if exist(d,'dir') == 7
                return;
            end
        end
    end

    % Last fallback
    try
        if isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(char(S.opt.startDir),'dir') == 7
            d = char(S.opt.startDir);
        end
    catch
    end

    if isempty(d) || exist(d,'dir') ~= 7
        d = pwd;
    end
end





function d = findAnimalFolderFromPath(startDir, animalID)
d = startDir;
cur = startDir;
prev = '';

animalID = upper(strtrimSafe(animalID));

while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    leafU = upper(strtrimSafe(leaf));

    if ~isempty(animalID)
        if strcmp(leafU, animalID) || ...
           (numel(leafU) > numel(animalID) && strncmp(leafU, [animalID '_'], numel(animalID)+1))
            d = cur;
            return;
        end
    end

    if isempty(parent) || strcmp(parent, cur)
        break;
    end

    prev = cur;
    cur = parent;
end
end

function d = findFolderBeforeAnimal(fp, animalID)
if exist(fp,'file') == 2
    cur = fileparts(fp);
else
    cur = fp;
end

if isempty(cur) || exist(cur,'dir') ~= 7
    d = pwd;
    return;
end

animalID = upper(strtrimSafe(animalID));
d = cur;
prev = '';

while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    if isempty(parent) || strcmp(parent, cur)
        break;
    end

    leafU = upper(strtrimSafe(leaf));
    if ~isempty(animalID)
        if strcmp(leafU, animalID) || ...
           (numel(leafU) > numel(animalID) && strncmp(leafU, [animalID '_'], numel(animalID)+1))
            d = parent;
            return;
        end
    end

    prev = cur;
    cur = parent;
end

[parent,~] = fileparts(d);
if ~isempty(parent) && exist(parent,'dir') == 7
    d = parent;
end
end

function startDir = getExcelExportStartDir(S)
startDir = getSmartBrowseDir(S, 'save');
end

function c = conditionRowColorGA(condName)
u = upper(strtrimSafe(condName));

if contains(u,'CONDA') || strcmp(u,'A') || contains(u,'PACAP') || contains(u,'GROUPA')
    c = [0.14 0.34 0.18];
elseif contains(u,'CONDB') || strcmp(u,'B') || contains(u,'VEH') || contains(u,'VEHICLE') || contains(u,'CONTROL') || contains(u,'GROUPB')
    c = [0.08 0.22 0.12];
elseif contains(u,'BASELINE')
    c = [0.10 0.24 0.22];
elseif contains(u,'POST')
    c = [0.18 0.26 0.12];
else
    c = [0.10 0.24 0.14];
end
end



    function txt = mapAlignmentModeText(S)
    mode = upper(strtrimSafe(S.mapFlipMode));

    switch mode
        case 'FLIP RIGHT-INJECTED ANIMALS'
            txt = 'Side alignment: Right-injected animals flipped';
        case 'FLIP LEFT-INJECTED ANIMALS'
            txt = 'Side alignment: Left-injected animals flipped';
        case 'ALIGN TO REFERENCE HEMISPHERE'
            txt = ['Side alignment: Aligned to ' strtrimSafe(S.mapRefPacapSide)];
        otherwise
            txt = 'Side alignment: Native sides';
    end
end

    function act = mapAlignmentActionText(S, pacapSide)
    pacapSide = strtrimSafe(pacapSide);

    if isempty(pacapSide) || strcmpi(pacapSide,'Unknown')
        act = '?';
        return;
    end

    mode = upper(strtrimSafe(S.mapFlipMode));

    switch mode
        case 'FLIP RIGHT-INJECTED ANIMALS'
            if strcmpi(pacapSide,'Right')
                act = 'Flip';
            else
                act = 'Keep';
            end

        case 'FLIP LEFT-INJECTED ANIMALS'
            if strcmpi(pacapSide,'Left')
                act = 'Flip';
            else
                act = 'Keep';
            end

        case 'ALIGN TO REFERENCE HEMISPHERE'
            refSide = upper(strtrimSafe(S.mapRefPacapSide));
            if isempty(refSide), refSide = 'LEFT'; end

            if strcmpi(pacapSide, refSide)
                act = 'Keep';
            else
                act = 'Flip';
            end

        otherwise
            act = 'Keep';
    end
end

function updateMapAlignmentLabel()
S0 = guidata(hFig);
if isfield(S0,'hMapAlignLabel') && ishghandle(S0.hMapAlignLabel)
    set(S0.hMapAlignLabel,'String',mapAlignmentModeText(S0));
end
end


    function updateMapUnderlayInfoLabel()
    S0 = guidata(hFig);

    if ~isfield(S0,'hMapUnderlayInfo') || ~ishghandle(S0.hMapUnderlayInfo)
        return;
    end

    txt = 'Underlay: Bundle underlay';

    if strcmpi(strtrimSafe(S0.mapUnderlayMode),'Loaded custom underlay')
        if isfield(S0,'mapCustomUnderlayFile') && ~isempty(strtrimSafe(S0.mapCustomUnderlayFile))
            txt = ['Underlay: ' shortPathForTable(S0.mapCustomUnderlayFile, 52)];
        else
            txt = 'Underlay: Loaded custom underlay';
        end
    end

    set(S0.hMapUnderlayInfo,'String',txt);
end

   function updateMapSideSummaryTable()
    S0 = guidata(hFig);

    if ~isfield(S0,'hMapSideTable') || ~ishghandle(S0.hMapSideTable)
        return;
    end

    S0 = ensureRowPacapSideSize(S0);
    guidata(hFig,S0);

    dispRows = findBundleDisplayRowsGA(S0);

    if isempty(dispRows)
        rows = {'-','-','-','-'};
        mapRows = NaN;
    else
        rows = cell(numel(dispRows),4);
        mapRows = dispRows(:);

        for i = 1:numel(dispRows)
            r = dispRows(i);
            info = extractRowMetaLight(S0.subj(r,:));

            injSide = 'Unknown';
            try
                if r <= numel(S0.rowPacapSide)
                    injSide = strtrimSafe(S0.rowPacapSide{r});
                end
            catch
            end

            if strcmpi(injSide,'L'), injSide = 'Left'; end
            if strcmpi(injSide,'R'), injSide = 'Right'; end
            if isempty(injSide), injSide = 'Unknown'; end

            rows{i,1} = strtrimSafe(info.animalID);
            rows{i,2} = strtrimSafe(info.session);
            rows{i,3} = displayScanID(info.scanID);
            rows{i,4} = injSide;
        end
    end

    set(S0.hMapSideTable, ...
        'Data',rows, ...
        'UserData',mapRows, ...
        'ColumnName',{'Animal','Sess','Scan','Inj Side'}, ...
        'BackgroundColor',buildMapSideTableColorsDisplayOnly(rows,mapRows), ...
        'RowName',[], ...
        'FontSize',9);

    try
        set(S0.hMapSideTable,'ColumnWidth',{96 46 58 72});
    catch
    end

    drawnow;
    pause(0.03);

    try
        applyDarkUITableViewport(S0.hMapSideTable, S0.C);
    catch
    end
end

    function s = displayScanID(scanID)
s = strtrimSafe(scanID);
if isempty(s)
    return;
end

% old style cleanup
s = regexprep(s, '(?i)^FUS_?', '');

% new style cleanup: show scan2_SB instead of SCAN2_SB
s = regexprep(s, '(?i)^SCAN', 'scan');
end

function s = makeBundleDisplayTitle(animalID, sessionID, scanID)
parts = {};

animalID = strtrimSafe(animalID);
sessionID = strtrimSafe(sessionID);
scanID = displayScanID(scanID);

if ~isempty(animalID) && ~strcmpi(animalID,'N/A')
    parts{end+1} = animalID; %#ok<AGROW>
end
if ~isempty(sessionID) && ~strcmpi(sessionID,'N/A')
    parts{end+1} = sessionID; %#ok<AGROW>
end
if ~isempty(scanID) && ~strcmpi(scanID,'N/A')
    parts{end+1} = scanID; %#ok<AGROW>
end

if isempty(parts)
    s = 'Bundle preview';
else
    s = strjoin(parts, ' | ');
end
end

function s = shortPathForTable(fp, maxLen)
if nargin < 2 || isempty(maxLen)
    maxLen = 34;
end

s = strtrimSafe(fp);
if isempty(s)
    return;
end

[~,name,ext] = fileparts(s);
leaf = [name ext];
s = leaf;

if numel(s) <= maxLen
    return;
end

keepName = max(8, maxLen - numel(ext) - 3);
keepName = min(keepName, numel(name));
s = [name(1:keepName) '...' ext];
end


function [h0,h1] = addPairEditsDark(parent, y, label, v0, v1, C, cb)
bg = get(parent,'BackgroundColor');

uicontrol(parent,'Style','text','String',label, ...
    'Units','normalized','Position',[0.02 y 0.35 0.12], ...
    'BackgroundColor',bg, ...
    'ForegroundColor','w', ...
    'HorizontalAlignment','left', ...
    'FontWeight','bold');

h0 = uicontrol(parent,'Style','edit','String',num2str(v0), ...
    'Units','normalized','Position',[0.38 y 0.12 0.12], ...
    'BackgroundColor',C.editBg, ...
    'ForegroundColor','w', ...
    'Callback',cb);

h1 = uicontrol(parent,'Style','edit','String',num2str(v1), ...
    'Units','normalized','Position',[0.52 y 0.12 0.12], ...
    'BackgroundColor',C.editBg, ...
    'ForegroundColor','w', ...
    'Callback',cb);
end

function ok = applyDarkUITableViewport(hTable, C)
ok = false;

if isempty(hTable) || ~ishandle(hTable)
    return;
end

if exist('findjobj','file') ~= 2 && exist('findjobj','file') ~= 6
    return;
end

try
    drawnow;
    pause(0.05);

    jObj = findjobj(hTable);
    if isempty(jObj)
        return;
    end
    if iscell(jObj)
        jObj = jObj{1};
    end

    [jScroll, jTable] = findJavaScrollAndTable(jObj);
    if isempty(jScroll) || isempty(jTable)
        return;
    end

    bgBody = java.awt.Color(C.editBg(1), C.editBg(2), C.editBg(3));
    bgHead = java.awt.Color(0.18, 0.18, 0.18);
    fgMain = java.awt.Color(1.00, 1.00, 1.00);
    selBg  = java.awt.Color(0.18, 0.55, 0.28);
    selFg  = java.awt.Color(1.00, 1.00, 1.00);
    gridC  = java.awt.Color(0.28, 0.28, 0.28);

    try, jTable.setOpaque(true); catch, end
    try, jTable.setBackground(bgBody); catch, end
    try, jTable.setForeground(fgMain); catch, end
    try, jTable.setSelectionBackground(selBg); catch, end
    try, jTable.setSelectionForeground(selFg); catch, end
    try, jTable.setGridColor(gridC); catch, end
    try, jTable.setShowHorizontalLines(true); catch, end
    try, jTable.setShowVerticalLines(true); catch, end
    try, jTable.setFillsViewportHeight(true); catch, end

    try, jScroll.setOpaque(true); catch, end
    try, jScroll.setBackground(bgBody); catch, end
    try, jScroll.getViewport.setOpaque(true); catch, end
    try, jScroll.getViewport.setBackground(bgBody); catch, end

    try
        jHeader = jTable.getTableHeader;
        if ~isempty(jHeader)
            jHeader.setOpaque(true);
            jHeader.setBackground(bgHead);
            jHeader.setForeground(fgMain);

            try
                hr = jHeader.getDefaultRenderer;
                if ~isempty(hr)
                    hr.setBackground(bgHead);
                    hr.setForeground(fgMain);
                    hr.setOpaque(true);
                end
            catch
            end
        end
    catch
    end

    try
        jCH = jScroll.getColumnHeader;
        if ~isempty(jCH)
            jCH.setOpaque(true);
            jCH.setBackground(bgHead);
            try
                jCHv = jCH.getView;
                if ~isempty(jCHv)
                    jCHv.setBackground(bgHead);
                    jCHv.setForeground(fgMain);
                end
            catch
            end
        end
    catch
    end

    try
        jRH = jScroll.getRowHeader;
        if ~isempty(jRH)
            jRH.setOpaque(true);
            jRH.setBackground(bgHead);

            try
                jRowView = jRH.getView;
                if ~isempty(jRowView)
                    jRowView.setOpaque(true);
                    jRowView.setBackground(bgHead);
                    jRowView.setForeground(fgMain);

                    try
                        rr = jRowView.getCellRenderer;
                        if ~isempty(rr)
                            rr.setBackground(bgHead);
                            rr.setForeground(fgMain);
                            rr.setOpaque(true);
                        end
                    catch
                    end
                end
            catch
            end
        end
    catch
    end

    try
        sc = javax.swing.ScrollPaneConstants;
        c1 = jScroll.getCorner(sc.UPPER_RIGHT_CORNER);
        if ~isempty(c1), c1.setOpaque(true); c1.setBackground(bgHead); end
        c2 = jScroll.getCorner(sc.UPPER_LEFT_CORNER);
        if ~isempty(c2), c2.setOpaque(true); c2.setBackground(bgHead); end
        c3 = jScroll.getCorner(sc.LOWER_RIGHT_CORNER);
        if ~isempty(c3), c3.setOpaque(true); c3.setBackground(bgBody); end
        c4 = jScroll.getCorner(sc.LOWER_LEFT_CORNER);
        if ~isempty(c4), c4.setOpaque(true); c4.setBackground(bgBody); end
    catch
    end

    try, jTable.repaint; catch, end
    try, jScroll.repaint; catch, end
    drawnow;

    ok = true;

catch
    ok = false;
end
end

function [jScroll, jTable] = findJavaScrollAndTable(jObj)
jScroll = [];
jTable  = [];

if isempty(jObj)
    return;
end

try
    if isa(jObj,'javax.swing.JScrollPane')
        jScroll = jObj;
        try
            v = jScroll.getViewport.getView;
            if ~isempty(v) && isa(v,'javax.swing.JTable')
                jTable = v;
            else
                jTable = findJavaTableDeep(v);
            end
        catch
        end
        return;
    end
catch
end

try
    if isa(jObj,'javax.swing.JTable')
        jTable = jObj;
        jScroll = findJavaAncestorOfClass(jObj, 'javax.swing.JScrollPane');
        return;
    end
catch
end

try
    n = jObj.getComponentCount;
    for k = 1:n
        child = jObj.getComponent(k-1);
        [jScroll, jTable] = findJavaScrollAndTable(child);
        if ~isempty(jScroll) || ~isempty(jTable)
            return;
        end
    end
catch
end
end

function jTable = findJavaTableDeep(jObj)
jTable = [];
if isempty(jObj)
    return;
end

try
    if isa(jObj,'javax.swing.JTable')
        jTable = jObj;
        return;
    end
catch
end

try
    n = jObj.getComponentCount;
    for k = 1:n
        child = jObj.getComponent(k-1);
        jTable = findJavaTableDeep(child);
        if ~isempty(jTable)
            return;
        end
    end
catch
end
end

    function cw = compactTableColWidths(hTable)
oldUnits = get(hTable,'Units');
set(hTable,'Units','pixels');
pos = get(hTable,'Position');
set(hTable,'Units',oldUnits);

avail = max(720, round(pos(3) - 46));

% Use | Animal | Session | Scan | Group | Condition | ROI | Bundle | Status
w = round(avail * [0.05 0.16 0.07 0.11 0.12 0.10 0.09 0.07 0.13]);
wmin = [38 126 56 96 94 78 78 62 112];
w = max(w, wmin);

extra = sum(w) - avail;
order = [2 4 5 6 9 7 8 3 1];

while extra > 0
    changed = false;
    for k = 1:numel(order)
        j = order(k);
        if w(j) > wmin(j)
            w(j) = w(j) - 1;
            extra = extra - 1;
            changed = true;
            if extra <= 0
                break;
            end
        end
    end
    if ~changed
        break;
    end
end

w = max(20, round(double(w(:)')));
cw = num2cell(w);
end

function anc = findJavaAncestorOfClass(jObj, className)
anc = [];
try
    p = jObj;
    while ~isempty(p)
        if isa(p, className)
            anc = p;
            return;
        end
        p = p.getParent;
    end
catch
    anc = [];
end
end

    function tf = isScmGroupBundleFile(fp)
    tf = false;

    if nargin < 1 || isempty(fp)
        return;
    end

    fp = strtrimSafe(fp);
    if exist(fp,'file') ~= 2
        return;
    end

    [~,nm,ext] = fileparts(fp);
    if ~strcmpi(ext,'.mat')
        return;
    end

    % Fast path: exported bundle naming convention
    if ~isempty(regexpi(nm,'^SCM_GroupExport_','once'))
        tf = true;
        return;
    end

    % Lightweight file-variable inspection only
    try
        info = whos('-file', fp);
        vars = {info.name};
        tf = any(strcmp(vars,'G'));
    catch
        tf = false;
    end
end


    function bundleFile = resolveGroupBundlePath(S, row)
bundleFile = '';

dataFile    = '';
roiFile     = '';
bundleFile0 = '';

try, dataFile    = strtrimSafe(row{6}); catch, end
try, roiFile     = strtrimSafe(row{7}); catch, end
try, bundleFile0 = strtrimSafe(row{8}); catch, end

if isScmGroupBundleFile(bundleFile0)
    bundleFile = bundleFile0;
    return;
end
if isScmGroupBundleFile(dataFile)
    bundleFile = dataFile;
    return;
end
if isScmGroupBundleFile(roiFile)
    bundleFile = roiFile;
    return;
end

meta = extractRowMetaLight(row);
subKey = sanitizeFilename([meta.animalID '_' meta.session '_' meta.scanID]);
animalSessFolder = '';
scanFolder = '';

if ~isempty(strtrimSafe(meta.animalID)) && ~strcmpi(strtrimSafe(meta.animalID),'N/A') && ...
   ~isempty(strtrimSafe(meta.session))  && ~strcmpi(strtrimSafe(meta.session),'N/A')
    animalSessFolder = [strtrimSafe(meta.animalID) '_' strtrimSafe(meta.session)];
end

if ~isempty(animalSessFolder) && ~isempty(strtrimSafe(meta.scanID)) && ~strcmpi(strtrimSafe(meta.scanID),'N/A')
    scanFolder = [animalSessFolder '_' upper(strtrimSafe(meta.scanID))];
end

candDirs = {};

rootPACAP = getPreferredPacapRootDir(S);
if ~isempty(rootPACAP) && ~isempty(animalSessFolder) && ~isempty(scanFolder)
    candDirs{end+1} = fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles', 'SCM');
    candDirs{end+1} = fullfile(rootPACAP, animalSessFolder, scanFolder, 'GroupAnalysis', 'Bundles');
    candDirs{end+1} = fullfile(rootPACAP, animalSessFolder, scanFolder);
end

try
    if isfield(S,'opt') && isfield(S.opt,'studio') && isstruct(S.opt.studio)
        P = studio_resolve_paths(S.opt.studio, 'GroupAnalysis', '');
        candDirs{end+1} = fullfile(P.groupDir, 'Bundles', subKey); %#ok<AGROW>
        candDirs{end+1} = fullfile(P.groupDir, 'Bundles'); %#ok<AGROW>
    end
catch
end

try
    if ~isempty(dataFile)
        d0 = fileparts(dataFile);
        candDirs{end+1} = d0; %#ok<AGROW>
        candDirs{end+1} = fullfile(d0, 'GroupAnalysis', 'Bundles', subKey); %#ok<AGROW>
        candDirs{end+1} = fullfile(d0, 'GroupAnalysis', 'Bundles'); %#ok<AGROW>
    end
catch
end

try
    if ~isempty(roiFile)
        d0 = fileparts(roiFile);
        candDirs{end+1} = d0; %#ok<AGROW>
        candDirs{end+1} = fullfile(d0, 'GroupAnalysis', 'Bundles', subKey); %#ok<AGROW>
        candDirs{end+1} = fullfile(d0, 'GroupAnalysis', 'Bundles'); %#ok<AGROW>
    end
catch
end

bestFile = '';
bestTime = -inf;

for i = 1:numel(candDirs)
    d = candDirs{i};
    if isempty(d) || exist(d,'dir') ~= 7
        continue;
    end

    dd = dir(fullfile(d, 'SCM_GroupExport_*.mat'));
    for k = 1:numel(dd)
        fp = fullfile(dd(k).folder, dd(k).name);
        if isScmGroupBundleFile(fp) && dd(k).datenum > bestTime
            bestFile = fp;
            bestTime = dd(k).datenum;
        end
    end
end

if isempty(bestFile)
    error(['Could not resolve SCM GroupAnalysis bundle for row: ' meta.animalID ...
           ' | ' meta.session ' | ' meta.scanID ...
           '. Add the exported bundle MAT directly with "Add Bundles".']);
end

bundleFile = bestFile;
end

function [G, cache] = getCachedGroupBundle(cache, bundleFile)
key = makeCacheKey('GB', bundleFile);

if isstruct(cache) && isfield(cache,'groupBundle') && isa(cache.groupBundle,'containers.Map')
    try
        if isKey(cache.groupBundle, key)
            G = cache.groupBundle(key);
            return;
        end
    catch
    end
end

L = load(bundleFile,'G');
if ~isfield(L,'G') || ~isstruct(L.G)
    error('Bundle MAT does not contain valid G struct: %s', bundleFile);
end
G = L.G;

if isstruct(cache) && isfield(cache,'groupBundle') && isa(cache.groupBundle,'containers.Map')
    try
        cache.groupBundle(key) = G;
    catch
    end
end
end

    function map2 = recomputeScmFromBundlePSC(G, baseWinSec, sigWinSec, sigma)
% recomputeScmFromBundlePSC
% Recompute SCM from exported bundle PSC exactly like SCM_gui:
%   map = mean(signal window) - mean(baseline window)
%   optional Gaussian smoothing
%   optional masking
%
% INPUTS
%   G           : exported bundle struct
%   baseWinSec  : [startSec endSec]
%   sigWinSec   : [startSec endSec]
%   sigma       : smoothing sigma (set 0 for none)
%
% OUTPUT
%   map2        : 2D SCM map

    if nargin < 4 || isempty(sigma) || ~isfinite(sigma)
        sigma = 0;
    end

    if ~isstruct(G)
        error('Input G must be a struct.');
    end

    if ~isfield(G,'pscAtlas4D') || isempty(G.pscAtlas4D)
        error('Bundle has no pscAtlas4D.');
    end

    if ~isfield(G,'TR') || isempty(G.TR) || ~isfinite(G.TR) || G.TR <= 0
        error('Bundle has no valid TR.');
    end

    if numel(baseWinSec) ~= 2 || any(~isfinite(baseWinSec))
        error('baseWinSec must be [startSec endSec].');
    end

    if numel(sigWinSec) ~= 2 || any(~isfinite(sigWinSec))
        error('sigWinSec must be [startSec endSec].');
    end

    PSC = double(G.pscAtlas4D);
    TR  = double(G.TR);

    % -------------------------------------------------------------
    % Select slice
    % -------------------------------------------------------------
    if ndims(PSC) == 3
        % [Y X T]
        PSCz = PSC;

    elseif ndims(PSC) == 4
        % [Y X Z T]
        if isfield(G,'atlasSliceIndex') && ~isempty(G.atlasSliceIndex) && isfinite(G.atlasSliceIndex)
            zSel = round(G.atlasSliceIndex);
        elseif isfield(G,'currentSlice') && ~isempty(G.currentSlice) && isfinite(G.currentSlice)
            zSel = round(G.currentSlice);
        else
            zSel = round(size(PSC,3) / 2);
        end

        zSel = max(1, min(size(PSC,3), zSel));
        PSCz = squeeze(PSC(:,:,zSel,:));

    else
        error('pscAtlas4D must be [Y X T] or [Y X Z T].');
    end

    if ndims(PSCz) ~= 3
        error('Selected PSC slice is not [Y X T].');
    end

    nT = size(PSCz, 3);

    % -------------------------------------------------------------
    % Convert seconds to indices exactly like SCM_gui
    % -------------------------------------------------------------
    b0i = max(1, min(nT, round(baseWinSec(1) / TR) + 1));
    b1i = max(1, min(nT, round(baseWinSec(2) / TR) + 1));
    s0i = max(1, min(nT, round(sigWinSec(1)  / TR) + 1));
    s1i = max(1, min(nT, round(sigWinSec(2)  / TR) + 1));

    if b1i < b0i
        tmp = b0i; b0i = b1i; b1i = tmp;
    end
    if s1i < s0i
        tmp = s0i; s0i = s1i; s1i = tmp;
    end

    % -------------------------------------------------------------
    % SCM_gui-consistent computation:
    % mean(signal) - mean(baseline)
    % -------------------------------------------------------------
    baseMap = mean(PSCz(:,:,b0i:b1i), 3);
    sigMap  = mean(PSCz(:,:,s0i:s1i), 3);
    map2    = sigMap - baseMap;

    % -------------------------------------------------------------
    % Optional smoothing
    % -------------------------------------------------------------
    if isfinite(sigma) && sigma > 0
        map2 = smooth2D_gauss_local(map2, sigma);
    end

    % -------------------------------------------------------------
    % Optional masking
    % -------------------------------------------------------------
    mask2D = extractBundleMask2D_local(G, size(map2));

    if ~isempty(mask2D)
        try
            map2(~mask2D) = 0;
        catch
        end
    end

    map2(~isfinite(map2)) = 0;
end


function mask2D = extractBundleMask2D_local(G, szMap)
% Return best available 2D mask matching current map size

    mask2D = [];

    try
        if isfield(G,'mask2DCurrentSlice') && ~isempty(G.mask2DCurrentSlice)
            M = logical(G.mask2DCurrentSlice);
            if isequal(size(M), szMap)
                mask2D = M;
                return;
            end
        end
    catch
    end

    try
        if isfield(G,'maskAtlas') && ~isempty(G.maskAtlas)
            M = logical(G.maskAtlas);

            if ismatrix(M)
                if isequal(size(M), szMap)
                    mask2D = M;
                    return;
                end

            elseif ndims(M) == 3
                if isfield(G,'atlasSliceIndex') && ~isempty(G.atlasSliceIndex) && isfinite(G.atlasSliceIndex)
                    zSel = round(G.atlasSliceIndex);
                elseif isfield(G,'currentSlice') && ~isempty(G.currentSlice) && isfinite(G.currentSlice)
                    zSel = round(G.currentSlice);
                else
                    zSel = round(size(M,3) / 2);
                end

                zSel = max(1, min(size(M,3), zSel));
                M2 = M(:,:,zSel);

                if isequal(size(M2), szMap)
                    mask2D = M2;
                    return;
                end
            end
        end
    catch
    end
end




function M2 = squeezeBundleMap2D(M)
M = double(M);
if isempty(M)
    M2 = [];
    return;
end

if ndims(M) == 2
    M2 = M;
elseif ndims(M) == 3
    if size(M,3) == 1
        M2 = M(:,:,1);
    else
        z = max(1, round(size(M,3)/2));
        M2 = M(:,:,z);
    end
else
    error('Unsupported SCM map dimensionality.');
end

M2(~isfinite(M2)) = 0;
end

function U2 = squeezeBundleUnderlay2D(U)
if isempty(U)
    U2 = [];
    return;
end

U = double(U);

if ndims(U) == 2
    U2 = U;
    return;
end

if ndims(U) == 3
    if size(U,3) == 3
        U2 = normalizeRgbLocal(U);
    else
        z = max(1, round(size(U,3)/2));
        U2 = U(:,:,z);
    end
    return;
end

if ndims(U) == 4
    if size(U,3) == 3
        z = max(1, round(size(U,4)/2));
        U2 = normalizeRgbLocal(squeeze(U(:,:,:,z)));
    else
        U2 = squeeze(mean(U,4));
        if ndims(U2) == 3
            z = max(1, round(size(U2,3)/2));
            U2 = U2(:,:,z);
        end
    end
    return;
end

error('Unsupported underlay dimensionality.');
end

function Umean = meanRgbUnderlays(Ulist)
if isempty(Ulist)
    Umean = [];
    return;
end

for i = 1:numel(Ulist)
    U = Ulist{i};
    if ndims(U) == 2
        U = toRGB_local(U);
    else
        U = normalizeRgbLocal(U);
    end
    Ulist{i} = U;
end

sz = size(Ulist{1});
acc = zeros(sz);

for i = 1:numel(Ulist)
    U = Ulist{i};
    if ~isequal(size(U), sz)
        error('Underlay sizes do not match for averaging.');
    end
    acc = acc + double(U);
end

Umean = acc / max(1, numel(Ulist));
Umean = min(max(Umean,0),1);
end

function A = flipLR_any(A)
if isempty(A), return; end
if ndims(A) == 2
    A = fliplr(A);
elseif ndims(A) == 3
    A = A(:, end:-1:1, :);
else
    error('flipLR_any supports 2D or 3D arrays only.');
end
end

function side = inferInjectionSideFromBundleOrRow(G, row, ~)
side = 'L';

try
    s = upper(strtrimSafe(G.injectionSide));
    if strcmp(s,'L') || strcmp(s,'LEFT')
        side = 'L';
        return;
    elseif strcmp(s,'R') || strcmp(s,'RIGHT')
        side = 'R';
        return;
    end
catch
end

try
    txt = upper([strtrimSafe(row{2}) ' ' strtrimSafe(row{6}) ' ' strtrimSafe(row{7}) ' ' strtrimSafe(row{8})]);
    if contains(txt,' RIGHT ') || contains(txt,'_R_')
        side = 'R';
    end
catch
end
end

function U = loadGroupUnderlayFile(fp)
if nargin < 1 || isempty(fp) || exist(fp,'file') ~= 2
    error('Underlay file not found.');
end

[~,~,ext] = fileparts(fp);
ext = lower(ext);

switch ext
    case '.mat'
        S = load(fp);
        pref = {'underlayDisplayRGB','underlayAtlas','brainImage','atlasUnderlayRGB','atlasUnderlay','bg','underlay','img','I','Data'};
        U = [];
        for i = 1:numel(pref)
            if isfield(S, pref{i}) && ~isempty(S.(pref{i}))
                U = S.(pref{i});
                break;
            end
        end
        if isempty(U)
            fn = fieldnames(S);
            for i = 1:numel(fn)
                v = S.(fn{i});
                if isnumeric(v) || islogical(v)
                    U = v;
                    break;
                end
            end
        end
        if isempty(U)
            error('MAT file has no usable underlay variable.');
        end
        U = squeezeBundleUnderlay2D(U);

    case {'.png','.jpg','.jpeg','.tif','.tiff','.bmp'}
        U = imread(fp);
        if ndims(U) == 3
            U = normalizeRgbLocal(double(U));
        else
            U = double(U);
        end

    otherwise
        error('Unsupported underlay type: %s', ext);
end
end

   function renderPSCOverlay(ax, underlay, map, render, styleName, showColorbar, cbPos)
if nargin < 6 || isempty(showColorbar)
    showColorbar = true;
end
if nargin < 7
    cbPos = [];
end

cla(ax);
styleAxesMode(ax, styleName, false);
hold(ax,'on');

if isempty(map)
    axis(ax,'off');
    hold(ax,'off');
    return;
end

map = double(map);
map(~isfinite(map)) = 0;

if isfield(render,'flipUDPreview') && render.flipUDPreview
    map = flipud_any(map);
    if ~isempty(underlay)
        underlay = flipud_any(underlay);
    end
end

if ~isempty(underlay)
    if ndims(underlay) == 2
        image(ax, toRGB_local(underlay));
    else
        image(ax, normalizeRgbLocal(underlay));
    end
else
    image(ax, toRGB_local(zeros(size(map))));
end

thr = 0;
if isfield(render,'threshold')
    thr = double(render.threshold);
end

alphaMask = double(abs(map) >= thr);
alpha = alphaMask;

if isfield(render,'alphaModOn') && render.alphaModOn
    lo = thr;
    hi = max(abs(map(:)));

    if isfield(render,'modMin')
        lo = max(lo, double(render.modMin));
    end
    if isfield(render,'modMax')
        hi = double(render.modMax);
    end

    if ~isfinite(hi) || hi <= lo
        hi = lo + eps;
    end

    modv = (abs(map) - lo) ./ max(eps, hi - lo);
    modv(~isfinite(modv)) = 0;
    modv = min(max(modv,0),1);
    alpha = modv .* alphaMask;
end

h = imagesc(ax, map);
set(h,'AlphaData',0.95 * alpha);

cmName = 'blackbdy_iso';
if isfield(render,'colormapName') && ~isempty(render.colormapName)
    cmName = char(render.colormapName);
end
colormap(ax, getNamedCmapLocal(cmName, 256));

if isfield(render,'caxis') && numel(render.caxis) >= 2
    caxis(ax, double(render.caxis(1:2)));
end

axis(ax,'image');
set(ax,'YDir','normal');
axis(ax,'off');

if showColorbar
    cb = colorbar(ax);
    cb.Label.String = 'Signal change (%)';
    styleColorbarMode(cb, styleName);

    if ~isempty(cbPos)
        try
            set(cb,'Units','normalized','Position',cbPos);
        catch
        end
    end
end

hold(ax,'off');
end

function rgb = toRGB_local(A)
A = mat2gray_local(A);
rgb = repmat(A, [1 1 3]);
end

function rgb = normalizeRgbLocal(U)
rgb = double(U);
mx = max(rgb(:));
if isfinite(mx) && mx > 1
    rgb = rgb / 255;
end
rgb(~isfinite(rgb)) = 0;
rgb = min(max(rgb,0),1);
end

function A = mat2gray_local(A)
A = double(A);
A(~isfinite(A)) = 0;
mn = min(A(:));
mx = max(A(:));
if ~isfinite(mn) || ~isfinite(mx) || mx <= mn
    A = zeros(size(A));
else
    A = (A - mn) / (mx - mn);
end
A = min(max(A,0),1);
end

function cm = getNamedCmapLocal(name, n)
if nargin < 2, n = 256; end
name = lower(strtrimSafe(name));

switch name
    case 'blackbdy_iso'
        if exist('blackbdy_iso','file') == 2
            cm = blackbdy_iso(n);
        else
            cm = hot(n);
        end
    case 'hot'
        cm = hot(n);
    case 'parula'
        cm = parula(n);
    case 'jet'
        cm = jet(n);
    case 'gray'
        cm = gray(n);
    otherwise
        if strcmp(name,'turbo') && exist('turbo','file') == 2
            cm = turbo(n);
        else
            cm = hot(n);
        end
end
end

function B = smooth2D_gauss_local(A, sigma)
try
    B = imgaussfilt(A, sigma);
    return;
catch
end

if sigma <= 0
    B = A;
    return;
end

r = max(1, ceil(3*sigma));
x = -r:r;
g = exp(-(x.^2)/(2*sigma^2));
g = g / sum(g);

B = conv2(conv2(double(A), g, 'same'), g', 'same');
end

function fp = resolveGroupAnalysisBundleFile(par, fileLabel, stamp)
if nargin < 3 || isempty(stamp)
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
end

root = '';

try
    if isstruct(par)
        if isfield(par, 'exportPath') && ~isempty(par.exportPath) && exist(char(par.exportPath), 'dir') == 7
            root = char(par.exportPath);
        elseif isfield(par, 'loadedPath') && ~isempty(par.loadedPath) && exist(char(par.loadedPath), 'dir') == 7
            root = char(par.loadedPath);
        elseif isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
            lf = char(par.loadedFile);
            if exist(lf, 'file') == 2
                root = fileparts(lf);
            end
        end
    end
catch
    root = '';
end

if isempty(root)
    root = pwd;
end

root = guessAnalysedRoot(root);

[animalID, sessionID, scanID] = parseBundleMetaFromLabel(par, fileLabel);

if isempty(animalID), animalID = 'Animal'; end
if isempty(sessionID), sessionID = 'Session'; end
if isempty(scanID),   scanID   = 'Scan'; end

subFolder = sanitizeName([animalID '_' sessionID '_' scanID]);

outDir = fullfile(root, 'GroupAnalysis', 'Bundles', subFolder);
safeMkdirIfNeeded(outDir);

fp = fullfile(outDir, ['SCM_GroupExport_' stamp '.mat']);
end

function [animalID, sessionID, scanID] = parseBundleMetaFromLabel(par, fileLabel)
animalID = '';
sessionID = '';
scanID = '';

cands = {};

try
    if isstruct(par)
        if isfield(par, 'loadedFile') && ~isempty(par.loadedFile)
            cands{end+1} = char(par.loadedFile); %#ok<AGROW>
        end
        if isfield(par, 'loadedPath') && ~isempty(par.loadedPath)
            cands{end+1} = char(par.loadedPath); %#ok<AGROW>
        end
        if isfield(par, 'loadedName') && ~isempty(par.loadedName)
            cands{end+1} = char(par.loadedName); %#ok<AGROW>
        end
        if isfield(par, 'activeDataset') && ~isempty(par.activeDataset)
            cands{end+1} = char(par.activeDataset); %#ok<AGROW>
        end
    end
catch
end

try
    if ~isempty(fileLabel)
        cands{end+1} = char(fileLabel); %#ok<AGROW>
    end
catch
end

for i = 1:numel(cands)
    txt = char(cands{i});
    txt = strrep(txt, '\', '/');

    tok = regexpi(txt, '([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)_(FUS_\d+)', 'tokens', 'once');
    if ~isempty(tok)
        animalID  = upper(strtrim(tok{1}));
        sessionID = upper(strtrim(tok{2}));
        scanID    = upper(strtrim(tok{3}));
        return;
    end
end

for i = 1:numel(cands)
    txt = char(cands{i});
    txt = strrep(txt, '\', '/');

    if isempty(animalID)
        tok = regexpi(txt, '\b([A-Z]{1,8}\d{6}[A-Z]?)\b', 'tokens', 'once');
        if ~isempty(tok)
            animalID = upper(strtrim(tok{1}));
        end
    end

    if isempty(sessionID)
        tok = regexpi(txt, '\b(S\d+)\b', 'tokens', 'once');
        if ~isempty(tok)
            sessionID = upper(strtrim(tok{1}));
        end
    end

    if isempty(scanID)
        tok = regexpi(txt, '\b(FUS_\d+)\b', 'tokens', 'once');
        if ~isempty(tok)
            scanID = upper(strtrim(tok{1}));
        end
    end
end
end

function exportOnePreview(ax, which, S, style)
R = S.lastROI;
cla(ax);
styleAxesMode(ax, style, S.previewShowGrid);
recolorAxesText(ax, style);
[~,fg] = previewColors(style);

if strcmpi(R.mode,'Group Maps')
    displayNames = getDisplayNamesFromR(R);

    if which == 1
        renderPSCOverlay(ax, R.commonUnderlay, R.group(1).map, R.mapRender, style);
        title(ax, ['Group Map: ' displayNames{1}], 'Color', fg);
        moveTitleUp(ax, titleYForStyle(style));
        recolorAxesText(ax, style);
    else
        if numel(R.group) >= 2
            renderPSCOverlay(ax, R.commonUnderlay, R.group(2).map, R.mapRender, style);
            title(ax, ['Group Map: ' displayNames{2}], 'Color', fg);
            moveTitleUp(ax, titleYForStyle(style));
            recolorAxesText(ax, style);
        else
            title(ax, 'No second group map', 'Color', fg);
            moveTitleUp(ax, titleYForStyle(style));
            recolorAxesText(ax, style);
        end
    end
    return;
end

t = R.tMin(:)';
displayNames = getDisplayNamesFromR(R);

if which == 1
    hold(ax,'on');
    allTop = [];
    leg = {};
    lineHs = [];

    for g = 1:numel(R.group)
        mu = R.group(g).mean(:)';
        se = R.group(g).sem(:)';

        if S.tc_previewSmooth
            dtSec = median(diff(t)) * 60;
            mu = smooth1D_edgeCentered(mu, dtSec, S.tc_previewSmoothWinSec);
            se = smooth1D_edgeCentered(se, dtSec, S.tc_previewSmoothWinSec);
            se(se < 0) = 0;
        end

        col = R.groupColors.(makeField(R.group(g).name));

        lineCol = col;
        fillCol = col;
       if strcmpi(S.colorScheme,'PACAP/Vehicle') && strcmpi(displayNames{g},'Vehicle')
    lineCol = [0.40 0.40 0.40];
    fillCol = [0.78 0.78 0.78];
end

        if R.showSEM
            [hLine,~] = shadedLineColored(ax, t, mu, se, lineCol, fillCol, S.exportSemAlpha);
        else
            hLine = plot(ax, t, mu, 'LineWidth', 2.4, 'Color', lineCol);
        end

        lineHs = [lineHs hLine]; %#ok<AGROW>
        leg{end+1} = sprintf('%s (n=%d)', displayNames{g}, R.group(g).n); %#ok<AGROW>
        allTop = [allTop, mu, mu+se, mu-se]; %#ok<AGROW>
    end

    xlabel(ax,'Time (min)','Color',fg);
    ylabel(ax, tern(R.unitsPercent,'Signal change (%)','ROI signal'), 'Color',fg);
    title(ax,'Mean ROI timecourse','Color',fg);
    moveTitleUp(ax, titleYForStyle(style));

    if ~isempty(lineHs)
        lg = legend(ax, lineHs, leg, 'Location','northwest', 'Box','off');
        styleLegendMode(lg, style);
    end

    applyYLim(ax, allTop, S.plotTop);

    if S.tc_showInjectionBox
        drawInjectionPatch(ax, S.tc_injMin0, S.tc_injMin1, [0.60 0.60 0.60], 0.25);
    end

    recolorAxesText(ax, style);
    hold(ax,'off');

else
    gNames = R.groupNames;
    metricVals = R.metricVals(:);
    grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,3), 'UniformOutput', false);
    xTicks = 1:numel(gNames);

    hold(ax,'on');
    allBot = [];
    rowX = nan(size(metricVals));

    for g = 1:numel(gNames)
        idx = strcmpi(grpCol, gNames{g});
        idxRows = find(idx & isfinite(metricVals));
        y = metricVals(idxRows);
        if isempty(y), continue; end

        col = R.groupColors.(makeField(gNames{g}));
        rowKeys = makeRowKeys(R.subjTable(idxRows,:));
        jitter = zeros(size(y));
        for ii = 1:numel(rowKeys)
            jitter(ii) = deterministicJitter(rowKeys{ii}, 0.18);
        end
        rowX(idxRows) = xTicks(g) + jitter;

        scatter(ax, rowX(idxRows), y, 60, col, 'filled');
        plot(ax, [xTicks(g)-0.25 xTicks(g)+0.25], [mean(y) mean(y)], ...
            'LineWidth', 2.5, 'Color', col);

        allBot = [allBot; y(:)]; %#ok<AGROW>
    end

 set(ax,'XLim',[0.5 numel(gNames)+0.5], 'XTick',xTicks, 'XTickLabel',displayNames);
ylabel(ax, tern(R.unitsPercent,'Signal change (%)','Metric (a.u.)'), 'Color',fg);
title(ax, '', 'Color', fg);

    applyYLim(ax, allBot, S.plotBot);

    highlightOutliersOnScatter(ax, R, S, rowX, style);
    recolorAxesText(ax, style);

    if isfield(R,'stats') && isfield(R.stats,'p') && isfinite(R.stats.p)
        annotateStatsBottom(ax, R, S);
    end

    hold(ax,'off');
end
end

%%% =====================================================================
%%% PATH / STUDIO HELPERS
%%% =====================================================================
function f = makeField(s)
s = strtrimSafe(s);

if isempty(s)
    s = 'Group';
end

try
    f = matlab.lang.makeValidName(s);
catch
    f = regexprep(s,'[^A-Za-z0-9_]','_');
    if isempty(f)
        f = 'Group';
    end
    if ~isletter(f(1))
        f = ['x_' f];
    end
end

if isempty(f)
    f = 'Group';
end
end


function subj = guessSubjectID(txt)
subj = '';

if nargin < 1 || isempty(txt)
    subj = ['S' datestr(now,'HHMMSS')];
    return;
end

txt = strtrimSafe(txt);

try
    m = parseMetaSingleText(txt);
    if isfield(m,'animalID') && ~strcmpi(strtrimSafe(m.animalID),'N/A')
        subj = strtrimSafe(m.animalID);
        return;
    end
catch
end

try
    [~,bn,~] = fileparts(txt);
    bn = strtrimSafe(bn);
    if ~isempty(bn)
        subj = bn;
        return;
    end
catch
end

subj = ['S' datestr(now,'HHMMSS')];
end


function dataFile = findDataMatNearROI(roiFile)
dataFile = '';

if nargin < 1 || isempty(roiFile)
    return;
end

roiFile = strtrimSafe(roiFile);
if exist(roiFile,'file') ~= 2
    return;
end

roiDir = fileparts(roiFile);
if isempty(roiDir) || exist(roiDir,'dir') ~= 7
    return;
end

meta = parseMetaSingleText(roiFile);
targetAnimal = strtrimSafe(meta.animalID);
targetSess   = strtrimSafe(meta.session);
targetScan   = strtrimSafe(meta.scanID);

cand = dir(fullfile(roiDir,'*.mat'));
bestScore = -inf;
bestFile = '';

for i = 1:numel(cand)
    fp = fullfile(cand(i).folder, cand(i).name);

    % skip obvious non-data files
    if isScmGroupBundleFile(fp)
        continue;
    end

    nmL = lower(cand(i).name);
    if contains(nmL,'roi') || contains(nmL,'groupanalysis') || contains(nmL,'groupexport')
        continue;
    end

    score = 0;
    m2 = parseMetaSingleText(fp);

    if ~isempty(targetAnimal) && ~strcmpi(targetAnimal,'N/A') && strcmpi(strtrimSafe(m2.animalID), targetAnimal)
        score = score + 10;
    end
    if ~isempty(targetSess) && ~strcmpi(targetSess,'N/A') && strcmpi(strtrimSafe(m2.session), targetSess)
        score = score + 5;
    end
    if ~isempty(targetScan) && ~strcmpi(targetScan,'N/A') && strcmpi(strtrimSafe(m2.scanID), targetScan)
        score = score + 5;
    end

    % prefer files that at least look like main data files
    if contains(lower(fp),'brain') || contains(lower(fp),'raw') || contains(lower(fp),'data')
        score = score + 1;
    end

    if score > bestScore
        bestScore = score;
        bestFile = fp;
    end
end

if ~isempty(bestFile)
    dataFile = bestFile;
    return;
end

% fallback: also try parent folder
parDir = fileparts(roiDir);
if ~isempty(parDir) && exist(parDir,'dir') == 7
    cand = dir(fullfile(parDir,'*.mat'));
    bestScore = -inf;
    bestFile = '';

    for i = 1:numel(cand)
        fp = fullfile(cand(i).folder, cand(i).name);

        if isScmGroupBundleFile(fp)
            continue;
        end

        nmL = lower(cand(i).name);
        if contains(nmL,'roi') || contains(nmL,'groupanalysis') || contains(nmL,'groupexport')
            continue;
        end

        score = 0;
        m2 = parseMetaSingleText(fp);

        if ~isempty(targetAnimal) && ~strcmpi(targetAnimal,'N/A') && strcmpi(strtrimSafe(m2.animalID), targetAnimal)
            score = score + 10;
        end
        if ~isempty(targetSess) && ~strcmpi(targetSess,'N/A') && strcmpi(strtrimSafe(m2.session), targetSess)
            score = score + 5;
        end
        if ~isempty(targetScan) && ~strcmpi(targetScan,'N/A') && strcmpi(strtrimSafe(m2.scanID), targetScan)
            score = score + 5;
        end

        if score > bestScore
            bestScore = score;
            bestFile = fp;
        end
    end

    if ~isempty(bestFile)
        dataFile = bestFile;
    end
end
end
function P = studio_resolve_paths(studio, moduleName, datasetLabel)
if nargin < 1 || isempty(studio) || ~isstruct(studio)
    studio = struct();
end
if nargin < 2 || isempty(moduleName)
    moduleName = 'GroupAnalysis';
end
if nargin < 3
    datasetLabel = '';
end

rootBase = '';
try
    if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(char(studio.exportPath),'dir') == 7
        rootBase = char(studio.exportPath);
    elseif isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(char(studio.loadedPath),'dir') == 7
        rootBase = char(studio.loadedPath);
    elseif isfield(studio,'loadedFile') && ~isempty(studio.loadedFile) && exist(char(studio.loadedFile),'file') == 2
        rootBase = fileparts(char(studio.loadedFile));
    end
catch
    rootBase = '';
end

if isempty(rootBase)
    rootBase = pwd;
end

analysedRoot = guessAnalysedRoot(rootBase);
groupDir = fullfile(analysedRoot, 'GroupAnalysis');
safeMkdirIfNeeded(groupDir);

datasetKey = sanitizeName(datasetLabel);
if isempty(datasetKey)
    datasetKey = 'General';
end

P = struct();
P.rootBase     = rootBase;
P.analysedRoot = analysedRoot;
P.groupDir     = groupDir;
P.moduleDir    = fullfile(groupDir, datasetKey);
P.bundleDir    = fullfile(groupDir, 'Bundles');
end

function root = guessAnalysedRoot(rootBase)
root = rootBase;
if isempty(root) || exist(root,'dir') ~= 7
    root = pwd;
end

cur = root;
prev = '';
while ~isempty(cur) && ~strcmp(cur, prev)
    [parent, leaf] = fileparts(cur);
    if strcmpi(leaf,'AnalysedData')
        root = cur;
        return;
    end
    if isempty(parent) || strcmp(parent, cur)
        break;
    end
    prev = cur;
    cur = parent;
end

root = fullfile(rootBase, 'AnalysedData');
safeMkdirIfNeeded(root);
end


    function layoutMapPreviewMain(S)
    try
        set(S.axMap1,'Visible','on','Position',[0.03 0.17 0.56 0.77]);
    catch
    end
    try
        set(S.axMap2,'Visible','off','Position',[0.01 0.01 0.01 0.01]);
        axis(S.axMap2,'off');
    catch
    end
end

    function placeSingleMapColorbar(ax, pos)
    if nargin < 2 || isempty(pos)
        pb = getAxesPlotBoxPosNorm(ax);

        % ---- exact tuning knobs ----
        cbGap    = 0;   % smaller => more left
        cbW      = 0.020;   % larger  => thicker
        cbExtraH = 0.125;   % larger  => taller
        % ----------------------------

        y0 = max(0, pb(2) - 0.5*cbExtraH);
        h0 = min(1 - y0, pb(4) + cbExtraH);

        pos = [ ...
            pb(1) + pb(3) + cbGap, ...
            y0, ...
            cbW, ...
            h0];
    end

    try
        cb = colorbar(ax);
        cb.Label.String = 'Signal change (%)';
        styleColorbarMode(cb, 'Dark');

        set(cb,'Units','normalized','Position',pos);

        try, set(cb,'Color',[1 1 1]); catch, end
        try, set(get(cb,'Label'),'Color',[1 1 1]); catch, end
        try, set(cb,'LineWidth',0.75); catch, end
        try, set(cb,'Box','off'); catch, end
    catch
    end
end

function pb = getAxesPlotBoxPosNorm(ax)
    % Returns the actual plot box inside the axes, in normalized figure units.
    % This is what you want for a colorbar that should match the image height,
    % not the full axes rectangle.

    oldUnits = get(ax,'Units');
    set(ax,'Units','normalized');
    axPos = get(ax,'Position');
    set(ax,'Units',oldUnits);

    pb = axPos;

    try
        xl = xlim(ax);
        yl = ylim(ax);
    catch
        return;
    end

    dx = abs(diff(xl));
    dy = abs(diff(yl));

    if ~(isfinite(dx) && dx > 0 && isfinite(dy) && dy > 0)
        return;
    end

    dataAR = dx / dy;              % displayed image aspect ratio
    axAR   = axPos(3) / axPos(4);  % axes rectangle aspect ratio

    if axAR > dataAR
        % axes is wider than the image area -> empty left/right margins
        pbW = axPos(4) * dataAR;
        pb(1) = axPos(1) + 0.5 * (axPos(3) - pbW);
        pb(3) = pbW;
    else
        % axes is taller than the image area -> empty top/bottom margins
        pbH = axPos(3) / dataAR;
        pb(2) = axPos(2) + 0.5 * (axPos(4) - pbH);
        pb(4) = pbH;
    end
end


function d = getPreferredPacapRootDir(S)
    d = '';

    cands = {'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData\AprilStayLeuven\PACAP'};

    try
        if isfield(S,'opt') && isfield(S.opt,'studio') && isstruct(S.opt.studio)
            if isfield(S.opt.studio,'exportPath') && ~isempty(S.opt.studio.exportPath)
                cands{end+1} = char(S.opt.studio.exportPath); %#ok<AGROW>
            end
            if isfield(S.opt.studio,'loadedPath') && ~isempty(S.opt.studio.loadedPath)
                cands{end+1} = char(S.opt.studio.loadedPath); %#ok<AGROW>
            end
        end
    catch
    end

    for i = 1:numel(cands)
        cc = strtrimSafe(cands{i});
        if ~isempty(cc) && exist(cc,'dir') == 7
            d = cc;
            return;
        end
    end
end

function g = getMapInjectedGroupLabel(S)
    g = '';
    try
        g = getSelectedPopupString(S.hQuickGroup);
    catch
    end
    g = strtrimSafe(g);
    if isempty(g) && isfield(S,'defaultGroup')
        g = strtrimSafe(S.defaultGroup);
    end
    if isempty(g)
        g = 'Group';
    end
end

    function updateMapGroupSideLabels()
    S0 = guidata(hFig);

    if isfield(S0,'hMapPreviewSideLabel') && ishghandle(S0.hMapPreviewSideLabel)
        set(S0.hMapPreviewSideLabel,'String','Inj side:','FontSize',10);
    end

    if isfield(S0,'hMapRefSideLabel') && ishghandle(S0.hMapRefSideLabel)
        set(S0.hMapRefSideLabel,'String','Ref hemi:','FontSize',10);
    end
end

    function [S, nApplied] = applyUseStateToMatchingRows(S, rRef, useVal)
    nApplied = 0;

    rows = findMatchingRowsByMetaOrBundle(S, rRef);
    if isempty(rows)
        rows = rRef;
    end

    for i = 1:numel(rows)
        rr = rows(i);
        S.subj{rr,1} = logical(useVal);

        if useVal
            st = lower(strtrimSafe(S.subj{rr,9}));
            if contains(st,'not used') || contains(st,'excluded')
                S.subj{rr,9} = '';
            end
        else
            S.subj{rr,9} = 'Not used';
        end

        nApplied = nApplied + 1;
    end

    S = sanitizeTableStruct(S);
    S = ensureRowPacapSideSize(S);
end

    function rows = findBundleDisplayRowsGA(S)
    rows = [];
    keysSeen = {};

    for r = 1:size(S.subj,1)
        key = makeBundleEntityKeyForRow(S, r);
        if isempty(key)
            continue;
        end

        if any(strcmpi(keysSeen, key))
            continue;
        end

        keysSeen{end+1} = key; %#ok<AGROW>
        rows(end+1) = representativeRowForBundleEntityKey(S, key); %#ok<AGROW>
    end
end

    function colors = buildMapSideTableColors(rows, mapRows)
    n = size(rows,1);
    colors = repmat([0.12 0.12 0.12], max(n,2), 1);

    for i = 1:n
        if isempty(mapRows) || i > numel(mapRows) || ~isfinite(mapRows(i))
            colors(i,:) = [0.12 0.12 0.12];
            continue;
        end

        if logicalCellValue(rows{i,1})
            colors(i,:) = [0.12 0.30 0.16];
        else
            colors(i,:) = [0.35 0.12 0.12];
        end
    end
end

function rOut = resolvePreviewRowFromSelection(S, rSel)
    rOut = [];

    if isempty(rSel) || ~isfinite(rSel) || rSel < 1 || rSel > size(S.subj,1)
        return;
    end

    keySel = makeBundleEntityKeyForRow(S, rSel);
    if ~isempty(keySel)
        dispRows = findBundleDisplayRowsGA(S);
        for i = 1:numel(dispRows)
            rr = dispRows(i);
            if strcmpi(makeBundleEntityKeyForRow(S, rr), keySel)
                rOut = rr;
                return;
            end
        end
    end

    % fallback
    bf = strtrimSafe(S.subj{rSel,8});
    if isempty(bf)
        try
            bf = resolveGroupBundlePath(S, S.subj(rSel,:));
        catch
            bf = '';
        end
    end

    if ~isempty(bf)
        rOut = rSel;
    end
end

function s = mapAlignmentShortTitle(S)
    mode = upper(strtrimSafe(S.mapFlipMode));

    switch mode
        case 'FLIP RIGHT-INJECTED ANIMALS'
            s = 'right injected flipped';
        case 'FLIP LEFT-INJECTED ANIMALS'
            s = 'left injected flipped';
        case 'ALIGN TO REFERENCE HEMISPHERE'
            s = ['aligned to ' strtrimSafe(S.mapRefPacapSide)];
        otherwise
            s = '';
    end
end
end
%%% =====================================================================
%%% FUNCTIONAL CONNECTIVITY HELPERS
%%% =====================================================================

function fileList = findFCBundlesRecursive(rootDir)
fileList = {};

if nargin < 1 || isempty(rootDir) || exist(rootDir,'dir') ~= 7
    return;
end

d = dir(fullfile(rootDir,'FC_GroupBundle_*.mat'));
for i = 1:numel(d)
    fileList{end+1,1} = fullfile(d(i).folder,d(i).name); %#ok<AGROW>
end

sub = dir(rootDir);
for i = 1:numel(sub)
    if ~sub(i).isdir
        continue;
    end

    nm = sub(i).name;
    if strcmp(nm,'.') || strcmp(nm,'..')
        continue;
    end

    more = findFCBundlesRecursive(fullfile(rootDir,nm));
    if ~isempty(more)
        fileList = [fileList; more(:)]; %#ok<AGROW>
    end
end
end

function tf = isFCGroupBundleFile(fp)
tf = false;

if nargin < 1 || isempty(fp) || exist(fp,'file') ~= 2
    return;
end

try
    info = whos('-file',fp);
    vars = {info.name};
    if any(strcmp(vars,'fcBundle'))
        tf = true;
        return;
    end
catch
end

[~,nm,ext] = fileparts(fp);
if strcmpi(ext,'.mat') && ~isempty(regexpi(nm,'^FC_GroupBundle_','once'))
    tf = true;
end
end

function [B, cache] = getCachedFCBundle(cache, fp)
key = makeCacheKey('FCBUNDLE',fp);

if isstruct(cache) && isfield(cache,'fcBundle') && isa(cache.fcBundle,'containers.Map')
    try
        if isKey(cache.fcBundle,key)
            B = cache.fcBundle(key);
            return;
        end
    catch
    end
end

L = load(fp);

if isfield(L,'fcBundle')
    B = L.fcBundle;
else
    error('File does not contain variable fcBundle: %s', fp);
end

if ~isstruct(B) || ~isfield(B,'subjects')
    error('Invalid FC group bundle: %s', fp);
end

if isstruct(cache) && isfield(cache,'fcBundle') && isa(cache.fcBundle,'containers.Map')
    try
        cache.fcBundle(key) = B;
    catch
    end
end
end

function [FC, cache] = loadFCGroupBundlesFromFiles(fileList, cache)
FC = struct();
FC.files = fileList(:);
FC.subjects = struct([]);
FC.nSubjects = 0;

idx = 0;

for i = 1:numel(fileList)
    fp = fileList{i};

    if ~isFCGroupBundleFile(fp)
        continue;
    end

    [B, cache] = getCachedFCBundle(cache, fp);

    for j = 1:numel(B.subjects)
        subj = B.subjects(j);

        if ~isfield(subj,'labels') || isempty(subj.labels)
            continue;
        end

        if ~isfield(subj,'R') || isempty(subj.R)
            continue;
        end

        idx = idx + 1;

        FC.subjects(idx).sourceFile = fp;

        if isfield(subj,'name') && ~isempty(subj.name)
            FC.subjects(idx).name = strtrimSafe(subj.name);
        else
            FC.subjects(idx).name = sprintf('FC_Subject_%02d',idx);
        end

        if isfield(subj,'group') && ~isempty(subj.group)
            FC.subjects(idx).group = strtrimSafe(subj.group);
        else
            FC.subjects(idx).group = inferFCGroupFromText([FC.subjects(idx).name ' ' fp]);
        end

        if isempty(FC.subjects(idx).group) || strcmpi(FC.subjects(idx).group,'All')
            FC.subjects(idx).group = inferFCGroupFromText([FC.subjects(idx).name ' ' fp]);
        end

        FC.subjects(idx).labels = double(subj.labels(:));

        if isfield(subj,'names') && ~isempty(subj.names)
            FC.subjects(idx).names = subj.names(:);
        else
            FC.subjects(idx).names = makeDefaultFCNames(FC.subjects(idx).labels);
        end

        FC.subjects(idx).R = double(subj.R);

        if isfield(subj,'Z') && ~isempty(subj.Z)
            FC.subjects(idx).Z = double(subj.Z);
        else
            Rtmp = double(subj.R);
            Rtmp = max(-0.999999,min(0.999999,Rtmp));
            Ztmp = atanh(Rtmp);
            Ztmp(1:size(Ztmp,1)+1:end) = 0;
            FC.subjects(idx).Z = Ztmp;
        end
    end
end

FC.nSubjects = idx;
end

function names = makeDefaultFCNames(labels)
names = cell(numel(labels),1);
for i = 1:numel(labels)
    names{i} = sprintf('ROI_%g',labels(i));
end
end

function g = inferFCGroupFromText(txt)
g = 'Unassigned';

u = upper(strtrimSafe(txt));

if contains(u,'PACAP') || contains(u,'GROUPA') || contains(u,'CONDA')
    g = 'PACAP';
elseif contains(u,'VEHICLE') || contains(u,'VEH') || contains(u,'CONTROL') || contains(u,'GROUPB') || contains(u,'CONDB')
    g = 'Vehicle';
end
end

function G = alignFCSubjectsToCommonROIs(FC)
if ~isfield(FC,'subjects') || isempty(FC.subjects)
    error('No FC subjects loaded.');
end

nSub = numel(FC.subjects);

commonLabels = FC.subjects(1).labels(:);

for i = 2:nSub
    commonLabels = intersect(commonLabels,FC.subjects(i).labels(:));
end

commonLabels = sort(commonLabels(:));

if isempty(commonLabels)
    error('No common ROI labels found across FC subjects.');
end

nR = numel(commonLabels);
Zstack = nan(nR,nR,nSub);
Rstack = nan(nR,nR,nSub);
names = cell(nR,1);

for i = 1:nSub
    labs = FC.subjects(i).labels(:);

    idx = nan(nR,1);
    for k = 1:nR
        hit = find(double(labs) == double(commonLabels(k)),1,'first');
        if ~isempty(hit)
            idx(k) = hit;
        end
    end

    if any(~isfinite(idx))
        error('Internal FC ROI alignment error.');
    end

    idx = double(idx(:));

    Zstack(:,:,i) = FC.subjects(i).Z(idx,idx);
    Rstack(:,:,i) = FC.subjects(i).R(idx,idx);

    if i == 1
        for k = 1:nR
            srcIdx = idx(k);
            if srcIdx <= numel(FC.subjects(i).names)
                names{k} = strtrimSafe(FC.subjects(i).names{srcIdx});
            else
                names{k} = sprintf('ROI_%g',commonLabels(k));
            end
        end
    end
end

G = struct();
G.labels = commonLabels;
G.names = names;
G.Zstack = Zstack;
G.Rstack = Rstack;
G.nSubjects = nSub;

G.subjectNames = cell(nSub,1);
G.groups = cell(nSub,1);
G.sourceFiles = cell(nSub,1);

for i = 1:nSub
    G.subjectNames{i} = FC.subjects(i).name;
    G.groups{i} = FC.subjects(i).group;
    G.sourceFiles{i} = FC.subjects(i).sourceFile;
end
end

function R = computeGroupFCStats(G, groupA, groupB)
idxA = strcmpi(G.groups,groupA);
idxB = strcmpi(G.groups,groupB);

if ~any(idxA)
    error(['No FC subjects found for Group A: ' groupA]);
end

if ~any(idxB)
    error(['No FC subjects found for Group B: ' groupB]);
end

ZA = G.Zstack(:,:,idxA);
ZB = G.Zstack(:,:,idxB);

meanZA = fcNanMean3(ZA);
meanZB = fcNanMean3(ZB);

diffZ = meanZA - meanZB;

[nR,~,~] = size(G.Zstack);
pMat = nan(nR,nR);
tMat = nan(nR,nR);

for r = 1:nR
    for c = 1:nR
        a = squeeze(ZA(r,c,:));
        b = squeeze(ZB(r,c,:));

        a = a(isfinite(a));
        b = b(isfinite(b));

        if numel(a) >= 2 && numel(b) >= 2
            [t,p,~] = welchT_vec(a,b);
            tMat(r,c) = t;
            pMat(r,c) = p;
        end
    end
end

R = struct();
R.mode = 'Functional Connectivity';
R.groupA = groupA;
R.groupB = groupB;
R.nA = sum(idxA);
R.nB = sum(idxB);

R.labels = G.labels;
R.names = G.names;

R.meanZA = meanZA;
R.meanZB = meanZB;
R.meanRA = tanh(meanZA);
R.meanRB = tanh(meanZB);

R.diffZ = diffZ;
R.diffR = tanh(meanZA) - tanh(meanZB);

R.pMat = pMat;
R.tMat = tMat;

R.subjectNames = G.subjectNames;
R.groups = G.groups;
R.sourceFiles = G.sourceFiles;
R.note = 'Statistics are computed on Fisher z. Pearson r matrices are tanh(mean z) for display.';
end

function M = fcNanMean3(X)
[n1,n2,~] = size(X);
M = nan(n1,n2);

for r = 1:n1
    for c = 1:n2
        v = squeeze(X(r,c,:));
        v = v(isfinite(v));
        if ~isempty(v)
            M(r,c) = mean(v);
        end
    end
end
end

function fcNoData(ax,titleStr,C)
cla(ax);

text(ax,0.5,0.5,'No data', ...
    'HorizontalAlignment','center', ...
    'VerticalAlignment','middle', ...
    'Color',C.txt, ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold');

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'XTick',[], ...
    'YTick',[]);

title(ax,titleStr,'Color',C.txt,'FontWeight','bold','Interpreter','none');
end

function fcPlotMatrix(ax,M,climVal,titleStr,names,C)
cla(ax);

if isempty(M)
    fcNoData(ax,titleStr,C);
    return;
end

imagesc(ax,M);
axis(ax,'image');
caxis(ax,climVal);
colormap(ax,fcBlueWhiteRed(256));
cb = colorbar(ax);
try, set(cb,'Color',[1 1 1]); catch, end

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'FontName','Arial', ...
    'FontSize',8, ...
    'TickLength',[0 0]);

title(ax,titleStr,'Color',C.txt,'FontWeight','bold','Interpreter','none');

nR = size(M,1);
tickIdx = fcTickIdx(nR);

set(ax,'XTick',tickIdx,'YTick',tickIdx, ...
    'XTickLabel',fcAbbrevNames(names(tickIdx),10), ...
    'YTickLabel',fcAbbrevNames(names(tickIdx),10));

try
    xtickangle(ax,90);
catch
end
end

function fcPlotPMatrix(ax,P,titleStr,names,C)
cla(ax);

if isempty(P)
    fcNoData(ax,titleStr,C);
    return;
end

Plog = -log10(P);
Plog(~isfinite(Plog)) = NaN;

imagesc(ax,Plog);
axis(ax,'image');
caxis(ax,[0 3]);
colormap(ax,hot(256));
cb = colorbar(ax);
try, set(cb,'Color',[1 1 1]); catch, end

set(ax,'Color',C.axisBg, ...
    'XColor',C.muted, ...
    'YColor',C.muted, ...
    'FontName','Arial', ...
    'FontSize',8, ...
    'TickLength',[0 0]);

title(ax,[titleStr ' (-log10 p)'],'Color',C.txt,'FontWeight','bold','Interpreter','none');

nR = size(P,1);
tickIdx = fcTickIdx(nR);

set(ax,'XTick',tickIdx,'YTick',tickIdx, ...
    'XTickLabel',fcAbbrevNames(names(tickIdx),10), ...
    'YTickLabel',fcAbbrevNames(names(tickIdx),10));

try
    xtickangle(ax,90);
catch
end
end

function idx = fcTickIdx(nR)
if nR <= 35
    step = 1;
elseif nR <= 70
    step = 2;
elseif nR <= 120
    step = 4;
elseif nR <= 200
    step = 6;
else
    step = max(8,ceil(nR/30));
end

idx = 1:step:nR;
end

function out = fcAbbrevNames(names,n)
if nargin < 2
    n = 10;
end

out = names;

for i = 1:numel(out)
    s = strtrimSafe(out{i});
    s = regexprep(s,'\s*\[[^\]]*\]\s*$','');
    parts = regexp(s,'\s+','split');

    if ~isempty(parts)
        s = parts{1};
    end

    if numel(s) > n
        s = [s(1:max(1,n-3)) '...'];
    end

    out{i} = s;
end
end

function cmap = fcBlueWhiteRed(n)
if nargin < 1
    n = 256;
end

n1 = floor(n/2);
n2 = n - n1;

b = [0.00 0.25 0.95];
w = [1.00 1.00 1.00];
r = [0.95 0.20 0.20];

c1 = [linspace(b(1),w(1),n1)' linspace(b(2),w(2),n1)' linspace(b(3),w(3),n1)'];
c2 = [linspace(w(1),r(1),n2)' linspace(w(2),r(2),n2)' linspace(w(3),r(3),n2)'];

cmap = [c1; c2];
end

function writeFCMatrixCSV(fileName,M,names)
fid = fopen(fileName,'w');

if fid < 0
    error(['Could not write CSV: ' fileName]);
end

cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'ROI');

for j = 1:numel(names)
    fprintf(fid,',%s',csvEscapeFC(names{j}));
end

fprintf(fid,'\n');

for i = 1:size(M,1)
    fprintf(fid,'%s',csvEscapeFC(names{i}));

    for j = 1:size(M,2)
        fprintf(fid,',%.10g',M(i,j));
    end

    fprintf(fid,'\n');
end
end

function s = csvEscapeFC(s0)
s = char(s0);
s = strrep(s,'"','""');
s = ['"' s '"'];
end

function saveFCAxisPNG(ax,fileName,C)
try
    f = figure('Visible','off', ...
        'Color',C.bg, ...
        'InvertHardcopy','off', ...
        'MenuBar','none', ...
        'ToolBar','none', ...
        'NumberTitle','off');

    set(f,'Position',[100 100 1100 900]);

    ax2 = copyobj(ax,f);
    set(ax2,'Units','normalized','Position',[0.10 0.13 0.74 0.74]);

    set(f,'PaperPositionMode','auto');
    print(f,fileName,'-dpng','-r250');
    close(f);
catch
end
end

function safeMkdirIfNeeded(d)
if isempty(d), return; end
if exist(d,'dir') ~= 7
    mkdir(d);
end
end

function s = sanitizeName(s)
% Standalone safe filename/folder sanitizer.
% Do not call sanitizeFilename here, because sanitizeFilename may be nested
% inside GroupAnalysis and invisible to file-level helper functions.

if nargin < 1 || isempty(s)
    s = 'export';
    return;
end

try
    if isstring(s)
        s = char(s);
    end
    if ~ischar(s)
        s = char(string(s));
    end
catch
    s = 'export';
    return;
end

s = strtrim(s);

if isempty(s)
    s = 'export';
    return;
end

% Remove Windows/macOS-invalid filename characters
s = regexprep(s,'[<>:"/\\|?*\x00-\x1F]','_');

% Keep ASCII-safe folder/file names
s = regexprep(s,'[^A-Za-z0-9_\-]','_');

% Clean repeated and edge underscores/dots
s = regexprep(s,'_+','_');
s = regexprep(s,'^[\._]+','');
s = regexprep(s,'[\._]+$','');

if isempty(s)
    s = 'export';
end

maxLen = 60;
if numel(s) > maxLen
    s = s(1:maxLen);
end
end
