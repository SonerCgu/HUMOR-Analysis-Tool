function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m
% MATLAB 2017b + 2023b compatible
% ASCII-safe copy
%
% ROI txt PSC files are plotted directly without baseline subtraction.

% -------------------- Parse inputs -----------------------
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

if ~isempty(posStudio), opt.studio = posStudio; end
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
C.muted  = [0.70 0.80 0.90];
C.axisBg = [0.00 0.00 0.00];
C.editBg = [0.14 0.14 0.14];

C.btnSecondary = [0.18 0.18 0.18];
C.btnPrimary   = [0.22 0.70 0.52];
C.btnAction    = [0.25 0.55 0.95];
C.btnDanger    = [0.90 0.25 0.25];
C.btnHelp      = [0.20 0.60 0.95];

F.name   = 'Arial';
F.base   = 13;
F.small  = 12;
F.big    = 16;
F.table  = 12;
F.tab    = 15;

% -------------------- Figure -----------------------------
hFig = figure('Name','fUSI Studio - Group Analysis', ...
    'Color',C.bg, 'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Position',[120 60 1860 980], 'CloseRequestFcn', @closeMe);

set(hFig, ...
    'DefaultUicontrolFontName',F.name, ...
    'DefaultUicontrolFontSize',F.base, ...
    'DefaultUipanelFontName',F.name, ...
    'DefaultUipanelFontSize',F.base, ...
    'DefaultAxesFontName',F.name, ...
    'DefaultAxesFontSize',F.base);

% -------------------- State ------------------------------
S = struct();
S.opt = opt;
S.C = C;
S.F = F;

S.subj = cell(0,8);   % Use|Subject|Group|Condition|PairID|DataFile|ROIFile|Status
S.selectedRows = [];
S.isClosing = false;
S.last = struct();
S.mode = 'ROI Timecourse';

S.groupList = {'PACAP','Vehicle','Control','GroupA','GroupB'};
S.condList  = {'CondA','CondB','Baseline','Post'};
S.defaultGroup = 'PACAP';
S.defaultCond  = 'CondA';
S.applyAllIfNoneSelected = true;

% Caches for speed
try
    S.cache.roiTC = containers.Map('KeyType','char','ValueType','any');
    S.cache.pscMap = containers.Map('KeyType','char','ValueType','any');
catch
    S.cache.roiTC = [];
    S.cache.pscMap = [];
end

% ROI defaults
S.tc_computePSC = false;
S.tc_baseMin0   = 0;
S.tc_baseMin1   = 10;
S.tc_injMin0    = 5;
S.tc_injMin1    = 15;
S.tc_plateauMin0 = 30;
S.tc_plateauMin1 = 40;
S.tc_peakSearchMin0 = 10;
S.tc_peakSearchMin1 = 20;
S.tc_peakWinMin = 3;
S.tc_trimPct    = 10;
S.tc_metric     = 'Robust Peak';
S.tc_baselineZero = 'None';
S.tc_showSEM = true;
S.tc_showInjectionBox = true;
S.displaySemAlpha = 0.35;
S.exportSemAlpha  = 0.20;

% PSC map defaults
S.baseStart = 0;
S.baseEnd   = 10;
S.sigStart  = 10;
S.sigEnd    = 30;
S.mapSummary = 'Mean';

% Color/style
S.colorMode = 'Scheme';
S.colorScheme = 'PACAP/Vehicle';
S.manualGroupA = 'PACAP';
S.manualGroupB = 'Vehicle';
S.manualColorA = 1;
S.manualColorB = 2;

% Plot scaling
S.plotTop = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150,'step',5);
S.plotBot = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150,'step',5);

% Preview style
S.previewStyle = 'Light';
S.previewShowGrid = false;

% Stats
S.testType = 'None';
S.alpha = 0.05;
S.annotMode = 'Bottom only';
S.showPText = true;

% Outliers
S.outlierMethod = 'None';
S.outMADthr = 3.5;
S.outIQRk   = 1.5;
S.outlierKeys = {};
S.outlierInfo = {};

S.outDir = defaultOutDir(opt);
% Preview-only temporal smoothing (upper plot)
S.tc_previewSmooth = false;     % checkbox
S.tc_previewSmoothWinSec = 60;  % seconds (e.g., 60 / 100)

% -------------------- Layout -----------------------------
leftW = 0.46;

pLeft = uipanel(hFig,'Units','normalized','Position',[0.02 0.05 leftW 0.93], ...
    'Title','Subjects / Groups', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',F.big,'FontWeight','bold');

pRight = uipanel(hFig,'Units','normalized','Position',[0.02+leftW+0.02 0.05 0.96-(0.02+leftW+0.02) 0.93], ...
    'Title','Analysis', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',F.big,'FontWeight','bold');

% -------------------- Table ------------------------------
colNames = {'Use','Animal ID','Session','Scan ID','Group','Condition','ROI File','ROI Status'};
colEdit  = [true true false false true true false false];
colFmt   = {'logical','char','char','char',S.groupList,S.condList,'char','char'};

S.hTable = uitable(pLeft, ...
    'Units','normalized','Position',[0.03 0.33 0.70 0.64], ...
    'Data',subjToUITable(S.subj), ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'ColumnFormat',colFmt, ...
    'RowName','numbered', ...
    'BackgroundColor',[1 1 1], ...
    'ForegroundColor',[0 0 0], ...
    'FontName','Consolas', ...
    'FontSize',F.table, ...
    'CellSelectionCallback',@onCellSelect, ...
    'CellEditCallback',@onCellEdit);
% -------------------- Quick Assign -----------------------
pQuick = uipanel(pLeft,'Units','normalized','Position',[0.75 0.33 0.22 0.64], ...
    'Title','Quick Assign', 'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontSize',F.base,'FontWeight','bold');

S.hSelInfo = uicontrol(pQuick,'Style','text','String','Selected: none', ...
    'Units','normalized','Position',[0.05 0.93 0.90 0.05], ...
    'BackgroundColor',C.panel2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hApplyAllIfNone = uicontrol(pQuick,'Style','checkbox', ...
    'String','If none selected -> active USE rows', ...
    'Units','normalized','Position',[0.05 0.87 0.90 0.05], ...
    'Value', double(S.applyAllIfNoneSelected), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'Callback',@onApplyAllToggle);

uicontrol(pQuick,'Style','text','String','Group', ...
    'Units','normalized','Position',[0.05 0.79 0.90 0.045], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hQuickGroup = uicontrol(pQuick,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.05 0.735 0.90 0.055], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

uicontrol(pQuick,'Style','text','String','Condition', ...
    'Units','normalized','Position',[0.05 0.655 0.90 0.045], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hQuickCond = uicontrol(pQuick,'Style','popupmenu','String',S.condList, ...
    'Units','normalized','Position',[0.05 0.60 0.90 0.055], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

S.hApplyGroup = mkBtn(pQuick,'Apply Group',[0.05 0.50 0.43 0.075],C.btnAction,@onApplyGroup);
S.hApplyCond  = mkBtn(pQuick,'Apply Cond',[0.52 0.50 0.43 0.075],C.btnAction,@onApplyCond);
S.hApplyBoth  = mkBtn(pQuick,'Apply Both',[0.05 0.405 0.90 0.075],C.btnPrimary,@onApplyBoth);

S.hAddGroup = mkBtn(pQuick,'Add Group',[0.05 0.305 0.43 0.070],C.btnSecondary,@onAddGroup);
S.hAddCond  = mkBtn(pQuick,'Add Cond',[0.52 0.305 0.43 0.070],C.btnSecondary,@onAddCond);

S.hRevertExcluded = mkBtn(pQuick,'Revert Excluded',[0.05 0.205 0.90 0.070],C.btnSecondary,@onRevertExcluded);
S.hHelp = mkBtn(pQuick,'Help',[0.05 0.105 0.90 0.070],C.btnHelp,@onHelp);

% Hidden compatibility handles (kept so old logic still works safely)
S.hAutoPair = uicontrol(pQuick,'Style','checkbox','String','Auto PairID = Subject', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','Value',1,'Visible','off');

S.hFillFromROI = uicontrol(pQuick,'Style','pushbutton','String','Fill DATA from ROI folder', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w', ...
    'Visible','off','Callback',@onFillFromROISelected);


% -------------------- Left buttons -----------------------
S.hAddFiles  = mkBtn(pLeft,'Add Files',[0.03 0.24 0.22 0.065],C.btnSecondary,@onAddFiles);
S.hAddFolder = mkBtn(pLeft,'Add Folder (scan)',[0.26 0.24 0.22 0.065],C.btnSecondary,@onAddFolder);
S.hRemove    = mkBtn(pLeft,'Remove Selected',[0.49 0.24 0.24 0.065],C.btnDanger,@onRemoveSelected);

S.hSaveList = mkBtn(pLeft,'Save List',[0.03 0.155 0.34 0.060],C.btnSecondary,@onSaveList);
S.hLoadList = mkBtn(pLeft,'Load List',[0.39 0.155 0.34 0.060],C.btnSecondary,@onLoadList);

% Hidden legacy controls so callbacks remain harmless
S.hSetData = uicontrol(pLeft,'Style','pushbutton','String','Set DATA for selected', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnAction,'ForegroundColor','w','Visible','off', ...
    'Callback',@onSetDataSelected);

S.hSetROI = uicontrol(pLeft,'Style','pushbutton','String','Set ROI for selected', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnAction,'ForegroundColor','w','Visible','off', ...
    'Callback',@onSetROISelected);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',F.base, ...
    'Visible','off','Callback',@onOutEdit);

S.hOutBrowse = uicontrol(pLeft,'Style','pushbutton','String','Browse', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w', ...
    'Visible','off','Callback',@onBrowseOut);

S.hHint = uicontrol(pLeft,'Style','text', ...
    'String','', ...
    'Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',F.small, ...
    'Visible','off');

% -------------------- Tabs -------------------------------
S.tabGroup = uitabgroup(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.96]);
try, set(S.tabGroup,'FontSize',F.tab); catch, end

S.tabROI   = uitab(S.tabGroup,'Title','ROI Timecourse');
S.tabMAP   = uitab(S.tabGroup,'Title','PSC Maps');
S.tabSTATS = uitab(S.tabGroup,'Title','Statistics / Export');
S.tabPREV  = uitab(S.tabGroup,'Title','Preview');

pROIBG   = uipanel(S.tabROI,  'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
pMAPBG   = uipanel(S.tabMAP,  'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);
pSTATSBG = uipanel(S.tabSTATS,'Units','normalized','Position',[0 0 1 1], 'BorderType','none','BackgroundColor',C.bg);

% -------------------- ROI TAB ----------------------------
bg2 = C.panel2;

pROItop = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.92 0.96 0.07], ...
    'Title','', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pROItop,'Style','text','String','Active mode:', ...
    'Units','normalized','Position',[0.02 0.15 0.18 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hMode = uicontrol(pROItop,'Style','popupmenu', ...
    'String',{'ROI Timecourse','PSC Map'}, ...
    'Units','normalized','Position',[0.20 0.18 0.25 0.70], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onModeChanged);

pROI = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.60 0.96 0.30], ...
    'Title','ROI settings', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hTC_ComputePSC = uicontrol(pROI,'Style','checkbox', ...
    'String','Compute %SC from raw using baseline (ignored if ROI txt already PSC)', ...
    'Units','normalized','Position',[0.02 0.82 0.58 0.15], ...
    'Value', double(S.tc_computePSC), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Injection (min):', ...
    'Units','normalized','Position',[0.62 0.84 0.16 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
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
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_PeakWin = uicontrol(pROI,'Style','edit','String',num2str(S.tc_peakWinMin), ...
    'Units','normalized','Position',[0.84 0.62 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Trim %:', ...
    'Units','normalized','Position',[0.66 0.42 0.18 0.12], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Trim = uicontrol(pROI,'Style','edit','String',num2str(S.tc_trimPct), ...
    'Units','normalized','Position',[0.84 0.42 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Metric:', ...
    'Units','normalized','Position',[0.66 0.22 0.18 0.12], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTC_Metric = uicontrol(pROI,'Style','popupmenu','String',{'Plateau','Robust Peak'}, ...
    'Units','normalized','Position',[0.84 0.22 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onROIChanged);

pStyle = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.36 0.96 0.22], ...
    'Title','Display style', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStyle,'Style','text','String','Color mode:', ...
    'Units','normalized','Position',[0.02 0.70 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hColorMode = uicontrol(pStyle,'Style','popupmenu','String',{'Scheme','Manual A/B'}, ...
    'Units','normalized','Position',[0.20 0.72 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Scheme:', ...
    'Units','normalized','Position',[0.44 0.70 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hColorScheme = uicontrol(pStyle,'Style','popupmenu', ...
    'String',{'PACAP/Vehicle','Blue/Red','Purple/Green','Gray/Orange','Distinct'}, ...
    'Units','normalized','Position',[0.56 0.72 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

S.hShowSEM = uicontrol(pStyle,'Style','checkbox','String','Show SEM', ...
    'Units','normalized','Position',[0.80 0.72 0.16 0.22], ...
    'Value', double(S.tc_showSEM), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onStyleChanged);

[pNames,~] = palette20();
uicontrol(pStyle,'Style','text','String','Group A:', ...
    'Units','normalized','Position',[0.02 0.40 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hManGroupA = uicontrol(pStyle,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.20 0.42 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Color A:', ...
    'Units','normalized','Position',[0.44 0.40 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hManColorA = uicontrol(pStyle,'Style','popupmenu','String',pNames, ...
    'Units','normalized','Position',[0.56 0.42 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

S.hShowInjBox = uicontrol(pStyle,'Style','checkbox','String','Injection box', ...
    'Units','normalized','Position',[0.80 0.42 0.18 0.22], ...
    'Value', double(S.tc_showInjectionBox), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Group B:', ...
    'Units','normalized','Position',[0.02 0.10 0.18 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hManGroupB = uicontrol(pStyle,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.20 0.12 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

uicontrol(pStyle,'Style','text','String','Color B:', ...
    'Units','normalized','Position',[0.44 0.10 0.12 0.22], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hManColorB = uicontrol(pStyle,'Style','popupmenu','String',pNames, ...
    'Units','normalized','Position',[0.56 0.12 0.22 0.22], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStyleChanged);

pY = uipanel(pROIBG,'Units','normalized','Position',[0.02 0.02 0.96 0.32], ...
    'Title','Y-Axis Scaling', ...
    'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

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

% -------------------- MAP TAB ----------------------------
pMap = uipanel(pMAPBG,'Units','normalized','Position',[0.02 0.55 0.96 0.43], ...
    'Title','PSC map windows (seconds)', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');
S.hBaseStart = makeWinRowDark(pMap,0.70,'Baseline start',num2str(S.baseStart),@onPSCEdit,'baseStart',C);
S.hBaseEnd   = makeWinRowDark(pMap,0.48,'Baseline end',  num2str(S.baseEnd),  @onPSCEdit,'baseEnd',C);
S.hSigStart  = makeWinRowDark(pMap,0.26,'Signal start',  num2str(S.sigStart), @onPSCEdit,'sigStart',C);
S.hSigEnd    = makeWinRowDark(pMap,0.04,'Signal end',    num2str(S.sigEnd),   @onPSCEdit,'sigEnd',C);

uicontrol(pMAPBG,'Style','text','String','Summary (per group):', ...
    'Units','normalized','Position',[0.04 0.45 0.25 0.05], ...
    'BackgroundColor',C.bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hMapSummary = uicontrol(pMAPBG,'Style','popupmenu','String',{'Mean','Median'}, ...
    'Units','normalized','Position',[0.28 0.44 0.20 0.06], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onMapChanged);

% -------------------- STATS TAB --------------------------
pStats = uipanel(pSTATSBG,'Units','normalized','Position',[0.02 0.54 0.96 0.44], ...
    'Title','Metric statistics', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.02 0.72 0.12 0.20], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTest = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','One-sample t-test (vs 0)','Two-sample t-test (Student, equal var)','Two-sample t-test (Welch)','One-way ANOVA (groups)'}, ...
    'Units','normalized','Position',[0.14 0.74 0.50 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.66 0.72 0.10 0.20], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hAlpha = uicontrol(pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.75 0.74 0.10 0.20], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Annotate:', ...
    'Units','normalized','Position',[0.02 0.52 0.12 0.14], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hAnnotMode = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','Bottom only','Both'}, ...
    'Units','normalized','Position',[0.14 0.54 0.25 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onAnnotChanged);

S.hShowPText = uicontrol(pStats,'Style','checkbox','String','Show p-value text', ...
    'Units','normalized','Position',[0.42 0.54 0.25 0.16], ...
    'Value', double(S.showPText), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onAnnotChanged);

uicontrol(pStats,'Style','text', ...
    'String','Stars: * p<0.05  ** p<0.01  *** p<0.001', ...
    'Units','normalized','Position',[0.69 0.53 0.29 0.16], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left');

pOut = uipanel(pStats,'Units','normalized','Position',[0.02 0.02 0.96 0.46], ...
    'Title','Outlier detection', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pOut,'Style','text','String','Method:', ...
    'Units','normalized','Position',[0.02 0.77 0.10 0.15], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hOutMethod = uicontrol(pOut,'Style','popupmenu','String',{'None','MAD robust z-score','IQR rule'}, ...
    'Units','normalized','Position',[0.12 0.79 0.20 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onOutlierChanged);

S.hOutParamLbl = uicontrol(pOut,'Style','text','String','Thr (z):', ...
    'Units','normalized','Position',[0.34 0.77 0.10 0.15], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

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
    'Title','Run / Export', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hRun         = mkBtn(pRun,'Run Analysis',[0.08 0.62 0.24 0.24],C.btnPrimary,@onRun);
S.hExport      = mkBtn(pRun,'Export Results',[0.38 0.62 0.24 0.24],C.btnSecondary,@onExport);
S.hExportExcel = mkBtn(pRun,'Export Excel',[0.68 0.62 0.24 0.24],C.btnAction,@onExportExcel);

S.hStatus = uicontrol(pRun,'Style','text','String','Ready.', ...
    'Units','normalized','Position',[0.04 0.10 0.92 0.36], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontSize',F.small);


% -------------------- PREVIEW TAB ------------------------
S.hPrevBG = uipanel(S.tabPREV,'Units','normalized','Position',[0 0 1 1], ...
    'BorderType','none','BackgroundColor',C.bg);

S.hPrevTop = uipanel(S.hPrevBG,'Units','normalized','Position',[0.02 0.94 0.96 0.05], ...
    'Title','', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hPrevExportTop = mkBtn(S.hPrevTop,'Export Top PNG',   [0.02 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(1));
S.hPrevExportBot = mkBtn(S.hPrevTop,'Export Bottom PNG',[0.18 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(2));
S.hPrevExportBoth = mkBtn(S.hPrevTop,'Export Both PNGs',[0.34 0.10 0.15 0.80],C.btnSecondary,@(~,~) onExportPreviewPNG(3));

S.hPrevLblView = uicontrol(S.hPrevTop,'Style','text','String','View:', ...
    'Units','normalized','Position',[0.52 0.15 0.05 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hPrevStyle = uicontrol(S.hPrevTop,'Style','popupmenu','String',{'Dark','Light'}, ...
    'Units','normalized','Position',[0.57 0.18 0.09 0.64], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

S.hPrevGrid = uicontrol(S.hPrevTop,'Style','checkbox','String','Grid', ...
    'Units','normalized','Position',[0.67 0.15 0.07 0.70], ...
    'Value', double(S.previewShowGrid), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

S.hSmoothEnable = uicontrol(S.hPrevTop,'Style','checkbox','String','Smoothing', ...
    'Units','normalized','Position',[0.75 0.15 0.14 0.70], ...
    'Value', double(S.tc_previewSmooth), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onSmoothChanged);

S.hPrevLblWin = uicontrol(S.hPrevTop,'Style','text','String','Win. (s):', ...
    'Units','normalized','Position',[0.89 0.15 0.08 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

S.hSmoothWin = uicontrol(S.hPrevTop,'Style','edit','String',num2str(S.tc_previewSmoothWinSec), ...
    'Units','normalized','Position',[0.965 0.18 0.03 0.64], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onSmoothChanged);


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

% -------------------- Init -------------------------------
guidata(hFig,S);
S = guidata(hFig);
stylePreviewPanels(S);
syncUIFromState();
refreshTable();
clearPreview();
updateOutlierBox();
setStatus(false);
setStatusText('Ready. Preview redraw is clean and cached computations are enabled.');

% =========================================================
% Nested callbacks
% =========================================================
    function closeMe(src,~)
        S0 = guidata(src);
        if isempty(S0), delete(src); return; end
        if isfield(S0,'isClosing') && S0.isClosing, delete(src); return; end
        S0.isClosing = true;
        guidata(src,S0);
        try, setStatus(true); catch, end
        if isfield(S0.opt,'onClose') && ~isempty(S0.opt.onClose)
            try, S0.opt.onClose(); catch, end
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

    function onCellEdit(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        S0.groupList = mergeUniqueStable(S0.groupList, uniqueStable(colAsStr(S0.subj,3)));
        S0.condList  = mergeUniqueStable(S0.condList,  uniqueStable(colAsStr(S0.subj,4)));
        guidata(hFig,S0);
        refreshTable();
    end

    function onApplyAllToggle(src,~)
        S0 = guidata(hFig);
        S0.applyAllIfNoneSelected = logical(get(src,'Value'));
        guidata(hFig,S0);
    end

    function rows = getTargetRows()
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if ~isempty(sel), rows = sel; return; end
        if S0.applyAllIfNoneSelected
            rows = find(logicalCol(S0.subj,1));
        else
            rows = [];
        end
    end

    function onApplyGroup(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows), setStatusText('No rows selected.'); return; end
        g = getSelectedPopupString(S0.hQuickGroup);
        for r=rows(:)', S0.subj{r,3} = g; end
        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Applied Group "%s" to %d row(s).', g, numel(rows)));
    end

    function onApplyCond(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows), setStatusText('No rows selected.'); return; end
        c = getSelectedPopupString(S0.hQuickCond);
        for r=rows(:)', S0.subj{r,4} = c; end
        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Applied Condition "%s" to %d row(s).', c, numel(rows)));
    end

    function onApplyBoth(~,~)
        onApplyGroup([],[]);
        onApplyCond([],[]);
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
        'This window lets you organize animals into groups and conditions, run ROI timecourse or PSC map analysis, inspect group-level trends, detect outliers, and export a clean Excel overview for record keeping and publication decisions.\n\n' ...
        'Typical workflow:\n' ...
        '1. Add Files or Add Folder.\n' ...
        '2. Check that Animal ID, Group, Condition, ROI File, and ROI Status look correct.\n' ...
        '3. Use Quick Assign to batch-set Group and Condition.\n' ...
        '4. In ROI Timecourse, define baseline, peak-search, plateau, and metric settings.\n' ...
        '5. In Stats, choose your statistical test and optional outlier detection.\n' ...
        '6. Click Run Analysis.\n' ...
        '7. Inspect Preview plots and outlier markings.\n' ...
        '8. Export results or Excel summary.\n\n' ...
        'Key notes:\n' ...
        '- Subject is treated as Animal ID and is extracted from the folder/path when possible.\n' ...
        '- Green rows indicate usable rows with a valid ROI file.\n' ...
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
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        [f,p] = uigetfile({'*.mat;*.txt','MAT or TXT (*.mat, *.txt)'}, ...
            'Select DATA (.mat) and/or ROI (.txt/.mat) files', startPath, 'MultiSelect','on');
        if isequal(f,0), return; end
        if ischar(f), f={f}; end
        for i=1:numel(f), addFileSmart(fullfile(p,f{i})); end
        refreshTable();
        setStatusText(sprintf('Added %d file(s).', numel(f)));
    end

    function onAddFolder(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        folder = uigetdir(startPath,'Select a folder to scan for .mat and .txt files');
        if isequal(folder,0), return; end
        dm = dir(fullfile(folder,'*.mat'));
        dt = dir(fullfile(folder,'*.txt'));
        for i=1:numel(dm), addFileSmart(fullfile(dm(i).folder, dm(i).name)); end
        for i=1:numel(dt), addFileSmart(fullfile(dt(i).folder, dt(i).name)); end
        refreshTable();
        setStatusText(sprintf('Scanned folder. Added %d file(s).', numel(dm)+numel(dt)));
    end

    function onRemoveSelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel), setStatusText('No rows selected.'); return; end
        S0.subj(sel,:) = [];
        S0.selectedRows = [];
        guidata(hFig,S0);
        refreshTable();
        setStatusText(sprintf('Removed %d row(s).', numel(sel)));
    end

    function onSetDataSelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select DATA (.mat)', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);
        for r=sel(:)', S0.subj{r,6} = fp; end
        guidata(hFig,S0);
        refreshTable();
        setStatusText('DATA assigned to selected rows.');
    end

    function onSetROISelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end
        startPath = S0.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end
        [f,p] = uigetfile({'*.txt;*.mat','ROI files (*.txt, *.mat)'}, 'Select ROI file', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);

        for r=sel(:)'
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
        [f,p] = uiputfile('GroupSubjects.mat','Save subject list');
        if isequal(f,0), return; end
        subj = S0.subj;
        groupList = S0.groupList;
        condList = S0.condList;
        save(fullfile(p,f), 'subj','groupList','condList','-v7');
        setStatusText('Saved list.');
    end

    function onLoadList(~,~)
        S0 = guidata(hFig);
        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'},'Load subject list');
        if isequal(f,0), return; end
        L = load(fullfile(p,f));
        if isfield(L,'subj'), S0.subj = L.subj; end
        if isfield(L,'groupList'), S0.groupList = L.groupList; end
        if isfield(L,'condList'),  S0.condList  = L.condList;  end
        S0 = sanitizeTableStruct(S0);
        guidata(hFig,S0);
        refreshTable();
        clearPreview();
        setStatusText('Loaded list.');
    end

    function onFillFromROISelected(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        sel = clampSelRows(S0.selectedRows, size(S0.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end

        for r=sel(:)'
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
        for r=1:size(S0.subj,1)
            st = strtrimSafe(S0.subj{r,8});
            if contains(lower(st),'excluded')
                S0.subj{r,1} = true;
                S0.subj{r,8} = '';
            end
        end
        S0.outlierKeys = {};
        S0.outlierInfo = {};
        guidata(hFig,S0);
        refreshTable();
        updateOutlierBox();
        if isfield(S0,'last') && ~isempty(fieldnames(S0.last))
            updatePreview();
        else
            clearPreview();
        end
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

    function onModeChanged(src,~)
        S0 = guidata(hFig);
        items = get(src,'String');
        S0.mode = items{get(src,'Value')};
        guidata(hFig,S0);
        clearPreview();
    end

    function onROIChanged(~,~)
        S0 = guidata(hFig);
        S0.tc_computePSC = logical(get(S0.hTC_ComputePSC,'Value'));
        S0.tc_baseMin0 = safeNum(get(S0.hBase0,'String'), S0.tc_baseMin0);
        S0.tc_baseMin1 = safeNum(get(S0.hBase1,'String'), S0.tc_baseMin1);
        S0.tc_injMin0  = safeNum(get(S0.hInj0,'String'),  S0.tc_injMin0);
        S0.tc_injMin1  = safeNum(get(S0.hInj1,'String'),  S0.tc_injMin1);
        S0.tc_peakSearchMin0 = safeNum(get(S0.hPkS0,'String'), S0.tc_peakSearchMin0);
        S0.tc_peakSearchMin1 = safeNum(get(S0.hPkS1,'String'), S0.tc_peakSearchMin1);
        S0.tc_plateauMin0 = safeNum(get(S0.hPlat0,'String'), S0.tc_plateauMin0);
        S0.tc_plateauMin1 = safeNum(get(S0.hPlat1,'String'), S0.tc_plateauMin1);
        S0.tc_peakWinMin = safeNum(get(S0.hTC_PeakWin,'String'), S0.tc_peakWinMin);
        S0.tc_trimPct    = safeNum(get(S0.hTC_Trim,'String'), S0.tc_trimPct);
        mt = get(S0.hTC_Metric,'String');
        S0.tc_metric = mt{get(S0.hTC_Metric,'Value')};
        guidata(hFig,S0);
        if isfield(S0,'last') && ~isempty(fieldnames(S0.last)), updatePreview(); end
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
        if isfield(S0,'last') && ~isempty(fieldnames(S0.last)), updatePreview(); end
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

    if isfield(S0,'last') && ~isempty(fieldnames(S0.last))
        updatePreview();  % full redraw so SEM stays correct

        dtSec = median(diff(S0.last.tMin))*60; % tMin is minutes
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
        if isfield(S0,'last') && ~isempty(fieldnames(S0.last)), updatePreview(); end
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

        % Always redraw preview so SEM + outliers + stats are consistent
if isfield(S0,'last') && ~isempty(fieldnames(S0.last))
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

    function onPSCEdit(src,~,fieldName)
        S0 = guidata(hFig);
        v = str2double(get(src,'String'));
        if ~isfinite(v), return; end
        S0.(fieldName) = v;
        guidata(hFig,S0);
    end

    function onMapChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hMapSummary,'String');
        S0.mapSummary = items{get(S0.hMapSummary,'Value')};
        guidata(hFig,S0);
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
        if isfield(S0,'last') && ~isempty(fieldnames(S0.last)), updatePreview(); end
    end

    function onOutlierChanged(~,~)
        S0 = guidata(hFig);
        items = get(S0.hOutMethod,'String');
        S0.outlierMethod = items{get(S0.hOutMethod,'Value')};

        if strcmpi(S0.outlierMethod,'MAD robust z-score')
            set(S0.hOutParamLbl,'String','Thr (z):');
            v = str2double(get(S0.hOutParam,'String'));
            if isfinite(v) && v>0, S0.outMADthr = v; else, set(S0.hOutParam,'String',num2str(S0.outMADthr)); end
        elseif strcmpi(S0.outlierMethod,'IQR rule')
            set(S0.hOutParamLbl,'String','k (IQR):');
            v = str2double(get(S0.hOutParam,'String'));
            if isfinite(v) && v>0, S0.outIQRk = v; else, set(S0.hOutParam,'String',num2str(S0.outIQRk)); end
        else
            set(S0.hOutParamLbl,'String','Param:');
        end
        guidata(hFig,S0);
    end

    function onDetectOutliers(~,~)
        S0 = guidata(hFig);
        if ~isfield(S0,'last') || isempty(fieldnames(S0.last)) || ~isfield(S0.last,'metricVals')
            errordlg('Run ROI Timecourse analysis first.','Outliers');
            return;
        end
        if ~strcmpi(S0.last.mode,'ROI Timecourse')
            errordlg('Outlier detection applies to ROI Timecourse only.','Outliers');
            return;
        end
        onOutlierChanged([],[]);
        S0 = guidata(hFig);

        [keysOut, info] = detectOutliers(double(S0.last.metricVals(:)), S0.last.subjTable, S0);
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
        for i=1:numel(S0.outlierKeys)
            hit = find(strcmp(keysAll, S0.outlierKeys{i}), 1, 'first');
            if ~isempty(hit)
                S0.subj{hit,1} = false;
                S0.subj{hit,8} = 'EXCLUDED (outlier)';
            end
        end
        guidata(hFig,S0);
        refreshTable();
        % Clear preview so user never sees stale results after excluding
S0.last = struct();
guidata(hFig,S0);
clearPreview();
        setStatusText('Outliers excluded. RUN again.');
    end

    function onRun(~,~)
        syncSubjFromTable();
        S0 = guidata(hFig);
        if isempty(S0.subj)
            errordlg('Add subject files first.','Group Analysis');
            return;
        end
        subjActive = getActiveRows(S0.subj);
        if isempty(subjActive)
            errordlg('No active rows (Use=true).','Group Analysis');
            return;
        end

        setStatus(false);
        setStatusText('Running...');
        drawnow;

        try
            onStatsChanged([],[]);
            onAnnotChanged([],[]);
            onROIChanged([],[]);
            onStyleChanged([],[]);
            onPlotScaleChanged([],[]);

            S0 = guidata(hFig);
            S0.outlierKeys = {};
            S0.outlierInfo = {};
            guidata(hFig,S0);
            updateOutlierBox();

            if strcmpi(S0.mode,'ROI Timecourse')
                [R, cacheOut] = runROITimecourseAnalysis(S0, subjActive, S0.cache);
            else
                [R, cacheOut] = runPSCMapAnalysis(S0, subjActive, S0.cache);
            end

            R.plotTop = S0.plotTop;
            R.plotBot = S0.plotBot;

            S0 = guidata(hFig);
            S0.last = R;
            S0.cache = cacheOut;
            guidata(hFig,S0);

            updatePreview();
            setStatusText('Done.');
        catch ME
            setStatusText(['ERROR: ' ME.message]);
            errordlg(ME.message,'Group Analysis');
        end
    end

    function outBase = exportStartFolder()
        S0 = guidata(hFig);
        if exist('Z:\fUS','dir')
            outBase = 'Z:\fUS';
        else
            outBase = S0.outDir;
            if isempty(outBase) || ~exist(outBase,'dir'), outBase = pwd; end
        end
    end

    function onExport(~,~)
        S0 = guidata(hFig);
        if ~isfield(S0,'last') || isempty(fieldnames(S0.last))
            errordlg('Run analysis first.','Export');
            return;
        end

        outParent = uigetdir(exportStartFolder(),'Choose export folder (will create a subfolder)');
        if isequal(outParent,0), return; end

        defName = ['GroupAnalysis_' datestr(now,'yyyymmdd_HHMMSS')];
        answ = inputdlg({'Folder name:'},'Export Results',1,{defName});
        if isempty(answ), return; end
        folderName = sanitizeFilename(strtrim(answ{1}));
        if isempty(folderName), folderName = defName; end

        outFolder = fullfile(outParent, folderName);
        if ~exist(outFolder,'dir'), mkdir(outFolder); end

        R = S0.last; %#ok<NASGU>
        save(fullfile(outFolder,'Results.mat'),'R','-v7.3');

        try
            if isfield(S0.last,'metrics') && isfield(S0.last.metrics,'table') && ~isempty(S0.last.metrics.table)
                writeCellCSV_UTF8(fullfile(outFolder,'Metrics.csv'), S0.last.metrics.table);
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

        startDir = getExcelExportStartDir(S0);

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
            setStatusText(['Excel exported: ' outFile]);
        catch ME
            setStatusText(['Excel export failed: ' ME.message]);
            errordlg(ME.message,'Export Excel');
        end

        setStatus(true);
    end
    function onExportPreviewPNG(which)
        S0 = guidata(hFig);
        if ~isfield(S0,'last') || isempty(fieldnames(S0.last))
            errordlg('Run analysis first.','Preview export');
            return;
        end

        outDir = uigetdir(exportStartFolder(),'Choose folder to save preview PNG(s)');
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
            setStatusText('Saved PNG(s).');
            setStatusText(['Saved PNG(s) to: ' outDir]);
        catch ME
            setStatusText(['Export failed: ' ME.message]);
            errordlg(ME.message,'Preview export');
        end
    end

   function clearPreview()
    S0 = guidata(hFig);

    % Remove any old colorbars that might sit around
    deleteAllColorbars(hFig);

    % EXTRA SAFETY: if any stray axes were created earlier, delete them
    try
        axAll = findall(S0.hPrevBG,'Type','axes');
        for k = 1:numel(axAll)
            if axAll(k) ~= S0.ax1 && axAll(k) ~= S0.ax2
                delete(axAll(k));
            end
        end
    catch
    end

    % Hard-clear the two preview axes (removes lines, patches, text, legends)
    hardClearAx(S0.ax1, S0.previewStyle, S0.previewShowGrid, 'Top plot');
    hardClearAx(S0.ax2, S0.previewStyle, S0.previewShowGrid, 'Bottom plot');
   end

function hardClearAx(ax, styleName, showGrid, ttl)
    if isempty(ax) || ~ishandle(ax), return; end

    % kill legend explicitly (legend isn't always removed by cla in older versions)
    try
        lg = legend(ax);
        if ishghandle(lg), delete(lg); end
    catch
    end

    % force replace mode so nothing ever "adds"
    try, set(ax,'NextPlot','replace'); catch, end
    try, hold(ax,'off'); catch, end

    % strongest clear
    try
        cla(ax,'reset');   % removes children + resets state that can cause accumulation
    catch
        try, cla(ax); catch, end
        try, delete(allchild(ax)); catch, end
    end

    % restore style
    styleAxesMode(ax, styleName, showGrid);
    recolorAxesText(ax, styleName);
    title(ax, ttl, 'FontWeight','bold');
    moveTitleUp(ax, titleYForStyle(styleName));
    fixAxesInset(ax);
end

    function updatePreview()
        S0 = guidata(hFig);
        clearPreview();

        if ~isfield(S0,'last') || isempty(fieldnames(S0.last))
            return;
        end

        R = S0.last;
        [~,fg] = previewColors(S0.previewStyle);

        if strcmpi(R.mode,'PSC Map')
            styleAxesMode(S0.ax1, S0.previewStyle, false);
            styleAxesMode(S0.ax2, S0.previewStyle, false);

            if ~isempty(R.group)
                displayNames = getDisplayNamesFromR(R);
                imagesc_mode(S0.ax1, squeeze2D(R.group(1).map), S0.previewStyle);
                title(S0.ax1, ['PSC Map: ' displayNames{1}], 'Color', fg, 'FontWeight', 'bold');
                moveTitleUp(S0.ax1, titleYForStyle(S0.previewStyle));
                cb1 = colorbar(S0.ax1);
                styleColorbarMode(cb1, S0.previewStyle);
                recolorAxesText(S0.ax1, S0.previewStyle);
            end

            if numel(R.group) >= 2
                displayNames = getDisplayNamesFromR(R);
                imagesc_mode(S0.ax2, squeeze2D(R.group(2).map), S0.previewStyle);
                title(S0.ax2, ['PSC Map: ' displayNames{2}], 'Color', fg, 'FontWeight', 'bold');
                moveTitleUp(S0.ax2, titleYForStyle(S0.previewStyle));
                cb2 = colorbar(S0.ax2);
                styleColorbarMode(cb2, S0.previewStyle);
                recolorAxesText(S0.ax2, S0.previewStyle);
            else
                title(S0.ax2, 'No second group map', 'Color', fg, 'FontWeight', 'bold');
                moveTitleUp(S0.ax2, titleYForStyle(S0.previewStyle));
                recolorAxesText(S0.ax2, S0.previewStyle);
            end

            fixAxesInset(S0.ax1);
            fixAxesInset(S0.ax2);
            drawnow limitrate;
            return;
        end

        t = R.tMin(:)';

        % ---------------- TOP plot ----------------
        hold(S0.ax1, 'on');
        styleAxesMode(S0.ax1, S0.previewStyle, S0.previewShowGrid);

        displayNames = getDisplayNamesFromR(R);
        leg = {};
        lineHs = [];
        allTop = [];

       for g = 1:numel(R.group)

    % ---- get data FIRST (must exist!) ----
    mu = R.group(g).mean(:)';   % 1 x T
    se = R.group(g).sem(:)';    % 1 x T

    % ---- optional smoothing (must happen AFTER mu/se assignment) ----
    if S0.tc_previewSmooth
        dtSec = median(diff(t)) * 60;  % t is minutes
        mu = smooth1D_edgeCentered(mu, dtSec, S0.tc_previewSmoothWinSec);
        se = smooth1D_edgeCentered(se, dtSec, S0.tc_previewSmoothWinSec);
        se(se<0) = 0;
    end

    % ---- colors ----
    col = R.groupColors.(makeField(R.group(g).name));

    lineCol = col;
    fillCol = col;

    % PACAP/Vehicle: make Vehicle line black, SEM stays gray
    if strcmpi(S0.colorScheme,'PACAP/Vehicle') && strcmpi(displayNames{g},'Vehicle')
        lineCol = [0.10 0.10 0.10]; % softer "black" (dark gray)
% or [0.30 0.30 0.30] for even lighter
        fillCol = [0.65 0.65 0.65];
    end

    % ---- plot ----
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

        % ---------------- BOTTOM plot ----------------
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
            for ii=1:numel(rowKeys)
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
            S0.subj = applyUITableToSubj(S0.subj, dt);
        end
    catch
    end
    S0 = sanitizeTableStruct(S0);
    guidata(hFig,S0);
end

  function refreshTable()
    S0 = guidata(hFig);
    S0 = sanitizeTableStruct(S0);

    S0.groupList = mergeUniqueStable(S0.groupList, uniqueStable(colAsStr(S0.subj,3)));
    S0.condList  = mergeUniqueStable(S0.condList,  uniqueStable(colAsStr(S0.subj,4)));

    colFmt = {'logical','char','char','char',S0.groupList,S0.condList,'char','char'};
    try, set(S0.hTable,'ColumnFormat',colFmt); catch, end
    set(S0.hTable,'Data',subjToUITable(S0.subj));
    set(S0.hTable,'RowName','numbered');

    try
        set(S0.hTable,'BackgroundColor',buildTableRowColors(S0.subj));
    catch
    end

    set(S0.hQuickGroup,'String',S0.groupList);
    set(S0.hQuickCond,'String',S0.condList);
    set(S0.hManGroupA,'String',S0.groupList);
    set(S0.hManGroupB,'String',S0.groupList);

    guidata(hFig,S0);
    drawnow limitrate;
    updateSelLabel();
end

    function addFileSmart(fp)
        S0 = guidata(hFig);
        [~,~,ext] = fileparts(fp);
        ext = lower(ext);

        subj = guessSubjectID(fp);
        if isempty(subj), subj = ['S' num2str(size(S0.subj,1)+1)]; end

        rowIdx = [];
        if ~isempty(S0.subj)
            rowIdx = find(strcmpi(colAsStr(S0.subj,2), subj), 1, 'first');
        end

        isROI = false;
        if strcmp(ext,'.txt')
            isROI = true;
        elseif strcmp(ext,'.mat')
            try
                L = load(fp);
                if isfield(L,'roiTC') || isfield(L,'TC')
                    isROI = true;
                end
            catch
            end
        end

        gdef = getSelectedPopupString(S0.hQuickGroup);
        cdef = getSelectedPopupString(S0.hQuickCond);
        if isempty(gdef), gdef = S0.defaultGroup; end
        if isempty(cdef), cdef = S0.defaultCond; end

        if isempty(rowIdx)
            newRow = {true, subj, gdef, cdef, '', '', '', ''};
            if get(S0.hAutoPair,'Value')==1, newRow{5} = subj; end
            if isROI
                newRow{7} = fp;
                df = findDataMatNearROI(fp);
                if isempty(df), df = subj; end
                newRow{6} = df;
            else
                newRow{6} = fp;
            end
            S0.subj(end+1,:) = newRow;
        else
            if isROI
                S0.subj{rowIdx,7} = fp;
                if get(S0.hAutoPair,'Value')==1 && isempty(strtrimSafe(S0.subj{rowIdx,5}))
                    S0.subj{rowIdx,5} = subj;
                end
                if isempty(strtrimSafe(S0.subj{rowIdx,6}))
                    df = findDataMatNearROI(fp);
                    if isempty(df), df = subj; end
                    S0.subj{rowIdx,6} = df;
                end
            else
                S0.subj{rowIdx,6} = fp;
            end
        end

        S0 = sanitizeTableStruct(S0);
        guidata(hFig,S0);
    end

    function syncUIFromState()
        S0 = guidata(hFig);
        set(S0.hTC_ComputePSC,'Value',double(S0.tc_computePSC));
        set(S0.hBase0,'String',num2str(S0.tc_baseMin0));
        set(S0.hBase1,'String',num2str(S0.tc_baseMin1));
        set(S0.hInj0,'String',num2str(S0.tc_injMin0));
        set(S0.hInj1,'String',num2str(S0.tc_injMin1));
        set(S0.hPkS0,'String',num2str(S0.tc_peakSearchMin0));
        set(S0.hPkS1,'String',num2str(S0.tc_peakSearchMin1));
        set(S0.hPlat0,'String',num2str(S0.tc_plateauMin0));
        set(S0.hPlat1,'String',num2str(S0.tc_plateauMin1));
        set(S0.hTC_PeakWin,'String',num2str(S0.tc_peakWinMin));
        set(S0.hTC_Trim,'String',num2str(S0.tc_trimPct));
        set(S0.hShowSEM,'Value',double(S0.tc_showSEM));
        set(S0.hShowInjBox,'Value',double(S0.tc_showInjectionBox));
        set(S0.hOutEdit,'String',S0.outDir);

        set(S0.hTopAuto,'Value',double(S0.plotTop.auto));
        set(S0.hTopZero,'Value',double(S0.plotTop.forceZero));
        set(S0.hTopStep,'String',num2str(S0.plotTop.step));
        set(S0.hTopYmin,'String',num2str(S0.plotTop.ymin));
        set(S0.hTopYmax,'String',num2str(S0.plotTop.ymax));

        set(S0.hBotAuto,'Value',double(S0.plotBot.auto));
        set(S0.hBotZero,'Value',double(S0.plotBot.forceZero));
        set(S0.hBotStep,'String',num2str(S0.plotBot.step));
        set(S0.hBotYmin,'String',num2str(S0.plotBot.ymin));
        set(S0.hBotYmax,'String',num2str(S0.plotBot.ymax));

        setPopupToString(S0.hColorMode, S0.colorMode);
        setPopupToString(S0.hColorScheme, S0.colorScheme);
        setPopupToString(S0.hManGroupA, S0.manualGroupA);
        setPopupToString(S0.hManGroupB, S0.manualGroupB);
        try, set(S0.hManColorA,'Value',S0.manualColorA); catch, end
        try, set(S0.hManColorB,'Value',S0.manualColorB); catch, end
        try, set(S0.hSmoothEnable,'Value',double(S0.tc_previewSmooth)); catch, end
try, set(S0.hSmoothWin,'String',num2str(S0.tc_previewSmoothWinSec)); catch, end

        setPopupToString(S0.hTest, S0.testType);
        set(S0.hAlpha,'String',num2str(S0.alpha));
        setPopupToString(S0.hAnnotMode, S0.annotMode);
        set(S0.hShowPText,'Value',double(S0.showPText));

        setPopupToString(S0.hPrevStyle, S0.previewStyle);
        set(S0.hPrevGrid,'Value',double(S0.previewShowGrid));
        % Metric dropdown
if strcmpi(S0.tc_metric,'Robust Peak')
    set(S0.hTC_Metric,'Value',2);   % {'Plateau','Robust Peak'}
else
    set(S0.hTC_Metric,'Value',1);
end
    end

    function setPopupToString(h, desired)
        items = get(h,'String');
        v = 1;
        for k=1:numel(items)
            if strcmpi(items{k}, desired), v = k; break; end
        end
        set(h,'Value',v);
    end

    function setStatusText(txt)
        S0 = guidata(hFig);
        try, set(S0.hStatus,'String',txt); catch, end
        drawnow limitrate;
    end

    function setStatus(isReady)
        if ~isempty(opt.statusFcn)
            try, opt.statusFcn(logical(isReady)); catch, end
        end
    end
end


% ======================================================================
% Local helpers
% ======================================================================

function h = mkBtn(parent, txt, pos, bg, cb)
h = uicontrol(parent,'Style','pushbutton','String',txt, ...
    'Units','normalized','Position',pos, ...
    'BackgroundColor',bg,'ForegroundColor','w', ...
    'FontWeight','bold', 'Callback',cb);
end

function d = defaultOutDir(opt)
d = pwd;
if isfield(opt,'studio') && isstruct(opt.studio) && isfield(opt.studio,'exportPath') && ~isempty(opt.studio.exportPath)
    d = fullfile(opt.studio.exportPath,'GroupAnalysis');
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

function s = strtrimSafe(x)
try
    if isempty(x), s=''; else, s=strtrim(char(x)); end
catch
    s='';
end
end

function v = safeNum(str, fallback)
v = str2double(str);
if isnan(v) || ~isfinite(v), v = fallback; end
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


function sel = clampSelRows(sel, nRows)
if isempty(sel), sel=[]; return; end
sel = unique(sel(:)');
sel = sel(sel>=1 & sel<=nRows);
end

function tf = logicalCol(tbl, col)
tf = true(size(tbl,1),1);
for i=1:size(tbl,1)
    try, tf(i) = logical(tbl{i,col}); catch, tf(i)=true; end
end
end

function rows = getActiveRows(subjTable)
use = logicalCol(subjTable,1);
rows = subjTable(use,:);
end


function col = colAsStr(C, j)
col = cell(size(C,1),1);
for i=1:size(C,1)
    col{i} = strtrimSafe(C{i,j});
end
end

function u = uniqueStable(C)
C = C(:);
C = C(~cellfun(@isempty,C));
u = {};
for i=1:numel(C)
    if ~any(strcmpi(u, C{i})), u{end+1,1}=C{i}; end %#ok<AGROW>
end
end


function S = sanitizeTableStruct(S)
if isempty(S.subj), return; end
if size(S.subj,2) < 8, S.subj(:,end+1:8) = {''}; end
if size(S.subj,2) > 8, S.subj = S.subj(:,1:8); end

for r = 1:size(S.subj,1)
    if isempty(S.subj{r,1}) || ...
       ~(islogical(S.subj{r,1}) || isnumeric(S.subj{r,1}) || ischar(S.subj{r,1}) || isstring(S.subj{r,1}))
        S.subj{r,1} = true;
    else
        S.subj{r,1} = logicalCellValue(S.subj{r,1});
    end

    meta = extractMetaFromSources(S.subj{r,2}, S.subj{r,6}, S.subj{r,7});

    if strcmpi(meta.animalID,'N/A') || isempty(meta.animalID)
        if isempty(strtrimSafe(S.subj{r,2}))
            S.subj{r,2} = ['S' num2str(r)];
        else
            S.subj{r,2} = strtrimSafe(S.subj{r,2});
        end
    else
        S.subj{r,2} = meta.animalID;  % internal Subject column stores Animal ID only
    end

    if isempty(strtrimSafe(S.subj{r,3})), S.subj{r,3} = S.defaultGroup; end
    if isempty(strtrimSafe(S.subj{r,4})), S.subj{r,4} = S.defaultCond;  end

    if isempty(strtrimSafe(S.subj{r,8})) && ~logicalCellValue(S.subj{r,1})
        S.subj{r,8} = 'Not used';
    end
end
end

function out = mergeUniqueStable(a,b)
if isempty(a), a={}; end
if isempty(b), b={}; end
out = a(:).';
for i=1:numel(b)
    if isempty(b{i}), continue; end
    if ~any(strcmpi(out,b{i})), out{end+1}=b{i}; end %#ok<AGROW>
end
end

function V = subjToUITable(subj)
n = size(subj,1);
V = cell(n,8);

for i = 1:n
    meta = extractMetaFromSources(subj{i,2}, subj{i,6}, subj{i,7});

    V{i,1} = logicalCellValue(subj{i,1});   % Use
    V{i,2} = meta.animalID;                 % Animal ID
    V{i,3} = meta.session;                  % Session
    V{i,4} = meta.scanID;                   % Scan ID
    V{i,5} = strtrimSafe(subj{i,3});        % Group
    V{i,6} = strtrimSafe(subj{i,4});        % Condition
    V{i,7} = strtrimSafe(subj{i,7});        % ROI File
    V{i,8} = deriveROIStatus(subj(i,:));    % ROI Status
end
end

function subj = applyUITableToSubj(subj, V)
n = size(V,1);

if isempty(subj)
    subj = cell(n,8);
end

if size(subj,1) < n
    subj(end+1:n,1:8) = {''};
end

if size(subj,1) > n
    subj = subj(1:n,:);
end

for i = 1:n
    subj{i,1} = logicalCellValue(V{i,1});  % Use
    subj{i,2} = strtrimSafe(V{i,2});       % Animal ID
    subj{i,3} = strtrimSafe(V{i,5});       % Group
    subj{i,4} = strtrimSafe(V{i,6});       % Condition
    % Session + Scan ID are display-only in the table
    % ROI File + ROI Status are read-only in the table

    if isempty(subj{i,5}), subj{i,5} = ''; end
    if isempty(subj{i,6}), subj{i,6} = ''; end
    if isempty(subj{i,7}), subj{i,7} = ''; end
    if isempty(subj{i,8}), subj{i,8} = ''; end
end
end

function s = deriveROIStatus(row)
roi = '';
st  = '';
use = true;

try, roi = strtrimSafe(row{7}); catch, end
try, st  = lower(strtrimSafe(row{8})); catch, end
try, use = logicalCellValue(row{1}); catch, end

if contains(st,'excluded')
    s = 'Excluded';
elseif ~use
    s = 'Not used';
elseif isempty(roi)
    s = 'ROI not set';
elseif exist(roi,'file') == 2
    s = 'OK';
else
    s = 'Missing';
end
end

function y2 = smooth1D_edgeCentered(y, dtSec, winSec)
% Centered moving-average smoothing with endpoint replication (edge pad)
% y: row or column vector
% dtSec: sampling interval in seconds
% winSec: window in seconds

y = double(y(:)');  % row
n = numel(y);
y2 = y;

if n < 2 || ~isfinite(dtSec) || dtSec <= 0 || ~isfinite(winSec) || winSec <= 0
    return;
end

% Fill NaNs (so smoothing doesn't collapse)
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
y2 = conv(ypad, k, 'valid');  % length n
end
function col = getSelectedPopupString(hPop)
col = '';
try
    items = get(hPop,'String');
    v = get(hPop,'Value');
    v = max(1,min(numel(items),v));
    col = strtrim(char(items{v}));
catch
end
end

function s = htmlRed(txt)
s = ['<html><font color="red"><b>' txt '</b></font></html>'];
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

function hEdit = makeWinRowDark(parent, y, label, init, cb, tag, C)
bg = get(parent,'BackgroundColor');
uicontrol(parent,'Style','text','String',[label ':'], ...
    'Units','normalized','Position',[0.05 y 0.35 0.16], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');
hEdit = uicontrol(parent,'Style','edit','String',init, ...
    'Units','normalized','Position',[0.42 y+0.01 0.50 0.16], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Tag',tag, 'Callback',@(s,e) cb(s,e,tag));
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

function clearAxisClean(ax, styleName, showGrid, ttl)
try
    lg = legend(ax);
    if ishghandle(lg), delete(lg); end
catch
end
try
    cla(ax);
catch
end
styleAxesMode(ax, styleName, showGrid);
recolorAxesText(ax, styleName);
title(ax,ttl,'FontWeight','bold');
moveTitleUp(ax,titleYForStyle(styleName));
try
    xlabel(ax,'');
    ylabel(ax,'');
    hold(ax,'off');
catch
end
end

function applyYLim(ax, dataVec, plotCfg)
    if isempty(dataVec), return; end
    dataVec = dataVec(isfinite(dataVec));
    if isempty(dataVec), return; end

    % ---- set YLim ----
    if plotCfg.auto
        lo = min(dataVec);
        hi = max(dataVec);
        if plotCfg.forceZero, lo = 0; end
        if lo==hi
            lo = lo-1;
            hi = hi+1;
        else
            pad = 0.06*(hi-lo);
            lo = lo - pad;
            hi = hi + pad;
            if plotCfg.forceZero, lo = 0; end
        end
        ylim(ax,[lo hi]);
    else
        lo = plotCfg.ymin;
        hi = plotCfg.ymax;
        if plotCfg.forceZero, lo = 0; end
        if isfinite(lo) && isfinite(hi) && lo<hi
            ylim(ax,[lo hi]);
        end
    end

    % ---- set YTick using plotCfg.step ----
    step = plotCfg.step;
    if ~isfinite(step) || step <= 0
        % let MATLAB decide
        try, set(ax,'YTickMode','auto'); catch, end
        return;
    end

    yl = ylim(ax);
    lo = yl(1); hi = yl(2);
    if ~isfinite(lo) || ~isfinite(hi) || hi<=lo, return; end

    if plotCfg.forceZero
        t0 = 0;
    else
        t0 = floor(lo/step)*step;
    end
    t1 = ceil(hi/step)*step;

    ticks = t0:step:t1;

    % keep ticks inside current limits
    ticks = ticks(ticks >= lo-1e-9 & ticks <= hi+1e-9);

    % avoid insane tick counts
    if numel(ticks) > 60
        try, set(ax,'YTickMode','auto'); catch, end
        return;
    end

    if ~isempty(ticks)
        try, set(ax,'YTick',ticks); catch, end
    end
end

function h = drawInjectionPatch(ax, x0, x1, col, alphaVal)
if ~isfinite(x0) || ~isfinite(x1), h = []; return; end
if x1 <= x0, h = []; return; end

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

function subj = guessSubjectID(fp)
subj = extractAnimalIDFromText(fp);

if isempty(subj)
    [parent,name,~] = fileparts(fp);
    [~,folderName] = fileparts(parent);

    subj = extractAnimalIDFromText(folderName);
    if isempty(subj)
        subj = extractAnimalIDFromText(name);
    end
end

if isempty(subj)
    subj = '';
end
end

function fpData = findDataMatNearROI(roiFile)
fpData = '';
if isempty(roiFile) || exist(roiFile,'file')~=2, return; end
d = fileparts(roiFile);
cand = [dir(fullfile(d,'*.mat')); dir(fullfile(fileparts(d),'*.mat'))];
if isempty(cand), return; end
for i=1:numel(cand)
    fn = fullfile(cand(i).folder, cand(i).name);
    nlow = lower(cand(i).name);
    if contains(nlow,'roi') || contains(nlow,'groupsubjects') || contains(nlow,'transformation')
        continue;
    end
    try
        w = whos('-file', fn);
        names = {w.name};
        if any(strcmp(names,'newData')) || any(strcmp(names,'data')) || any(strcmp(names,'I')) || any(strcmp(names,'TR'))
            fpData = fn;
            return;
        end
    catch
    end
end
end

function field = makeField(name)
field = upper(strtrim(char(name)));
field = regexprep(field,'[^A-Z0-9_]','_');
if isempty(field), field='GROUP'; end
end

function imagesc_mode(ax, A, styleName)
A = double(A);
A(~isfinite(A)) = 0;
cla(ax);
styleAxesMode(ax, styleName, false);
imagesc(ax, A);
axis(ax,'image');
axis(ax,'off');
recolorAxesText(ax, styleName);
end

function Y = squeeze2D(X)
if ndims(X)==3 && size(X,3)>1
    z = round(size(X,3)/2);
    Y = X(:,:,z);
else
    Y = X;
end
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

for i=1:n
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

for i=1:n
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

function dispNames = getDisplayNamesFromR(R)
if isfield(R,'groupDisplayNames') && ~isempty(R.groupDisplayNames)
    dispNames = R.groupDisplayNames;
else
    dispNames = R.groupNames;
end
end

function j = deterministicJitter(key, amp)
% Stable jitter from a string key (no toolboxes). Works in 2017b+.
% Returns a deterministic value in [-amp/2, +amp/2].

if nargin < 2 || isempty(amp), amp = 0.22; end
if isempty(key), key = 'x'; end

% FNV-1a 32-bit hash over bytes
s = uint8(char(key));
h = uint32(2166136261);
for k = 1:numel(s)
    h = bitxor(h, uint32(s(k)));
    h = uint32(mod(uint64(h) * 16777619, 2^32));
end

u = double(h) / double(intmax('uint32'));  % [0,1]
j = (u - 0.5) * amp;                       % [-amp/2, +amp/2]
end

function highlightOutliersOnScatter(ax, R, S, rowX, styleName)
if isempty(S.outlierKeys), return; end
if ~isfield(R,'subjTable') || isempty(R.subjTable), return; end
if numel(rowX) ~= size(R.subjTable,1), return; end

[bg,fg] = previewColors(styleName);
keysAll = makeRowKeys(R.subjTable);
y = R.metricVals(:);

for i=1:numel(S.outlierKeys)
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

function exportPreviewPNG(outFile, which, S)
[figBg,~] = previewColors(S.previewStyle);
f = figure('Visible','off','Color',figBg,'InvertHardcopy','off', ...
    'MenuBar','none','ToolBar','none','NumberTitle','off','Renderer','opengl');
set(f,'Position',[100 100 1400 820]);

ax = axes('Parent',f,'Units','normalized','Position',[0.09 0.12 0.86 0.62]);
styleAxesMode(ax, S.previewStyle, S.previewShowGrid);
recolorAxesText(ax, S.previewStyle);

exportOnePreview(ax, which, S, S.previewStyle);

set(f,'InvertHardcopy','off');
set(f,'PaperPositionMode','auto');
print(f, outFile, '-dpng', '-r250');
close(f);
end

function y = tern(cond,a,b)
if cond, y=a; else, y=b; end
end

function keys = makeRowKeys(tbl)
n = size(tbl,1);
keys = cell(n,1);
for i=1:n
    sid = strtrimSafe(tbl{i,2});
    grp = strtrimSafe(tbl{i,3});
    cd  = strtrimSafe(tbl{i,4});
    pid = strtrimSafe(tbl{i,5});
    keys{i} = [sid '|' grp '|' cd '|' pid];
end
end

function writeCellCSV_UTF8(fn, C)
fid = fopen(fn,'w');
if fid<0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, uint8([239 187 191]), 'uint8');

[nr,nc] = size(C);
for r=1:nr
    row = cell(1,nc);
    for c=1:nc
        v = C{r,c};
        if isnumeric(v)
            if isempty(v) || ~isfinite(v), s=''; else, s=num2str(v); end
        else
            try, s = char(v); catch, s=''; end
        end
        s = strrep(s,'"','""');
        row{c} = ['"' s '"'];
    end
    fprintf(fid,'%s\n', strjoin(row,','));
end
end

%%%%%%% -------------%%%%%%
%%%%%%% EXCEL Export %%%%%%
%%%%%%% -------------%%%%%%
function startDir = getExcelExportStartDir(S)
root1 = 'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData\GroupAnalysis';
root2 = 'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData';

if exist(root1,'dir') == 7
    startDir = root1;
elseif exist(root2,'dir') == 7
    startDir = root2;
elseif isfield(S,'outDir') && ~isempty(S.outDir) && exist(S.outDir,'dir') == 7
    startDir = S.outDir;
elseif isfield(S,'opt') && isfield(S.opt,'startDir') && ~isempty(S.opt.startDir) && exist(S.opt.startDir,'dir') == 7
    startDir = S.opt.startDir;
else
    startDir = pwd;
end
end

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

if isfield(S,'last') && ~isempty(fieldnames(S.last)) && ...
   isfield(S.last,'mode') && strcmpi(S.last.mode,'ROI Timecourse') && ...
   isfield(S.last,'metricVals') && isfield(S.last,'subjTable')

    anaTbl = S.last.subjTable;
    anaMet = double(S.last.metricVals(:));

    if isfield(S.last,'metricName')
        metricNameNow = strtrimSafe(S.last.metricName);
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

info.subject   = strtrimSafe(row{2});
info.group     = strtrimSafe(row{3});
info.condition = strtrimSafe(row{4});
info.pairID    = strtrimSafe(row{5});
info.dataFile  = strtrimSafe(row{6});
info.roiFile   = strtrimSafe(row{7});
info.status    = strtrimSafe(row{8});

meta = extractMetaFromSources(info.subject, info.dataFile, info.roiFile);

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


function key = makeAuditMatchKey(row)
info = extractRowMetaForExcel(row);
key = lower([ ...
    info.animalID '|' ...
    info.session  '|' ...
    info.scanID   '|' ...
    info.group    '|' ...
    info.condition ]);
end

function state = deriveAuditRowState(row)
use = logicalCellValue(row{1});
roi = strtrimSafe(row{7});
st  = lower(strtrimSafe(row{8}));

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

% Layout
rowAnimal  = 1;
rowSession = 2;
rowScan    = 3;
rowGroup   = 4;
rowCond    = 5;
rowGap1    = 6;
rowGap2    = 7;
rowInfo    = 8;
rowHeader  = 9;
rowData0   = 10;

nRows = max(rowData0 + maxPts - 1, rowHeader);
nCols = 2 + 2*nScan;   % A=time_sec, B=time_min, then [animalCol spacerCol]

C = cell(nRows, nCols);

% Left-side labels
C{rowAnimal,1}  = 'Animal ID';
C{rowSession,1} = 'Session ID';
C{rowScan,1}    = 'Scan ID';
C{rowGroup,1}   = 'Group';
C{rowCond,1}    = 'Condition';

C{rowInfo,1}    = '% signal change (%SC)';
C{rowInfo,2}    = 'Values come from ROI txt and use the respective baseline window of each ROI export';

C{rowHeader,1}  = 'time_sec';
C{rowHeader,2}  = 'time_min';

% Reference time columns
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

% spacer columns intentionally left empty
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

% fallback ROI number from filename, e.g. roi5.txt
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

    % If previous line was '# x1 x2 y1 y2', read this numeric row
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

    % Stop once data table starts
    if lnRaw(1) ~= '#' && lnRaw(1) ~= '%' && lnRaw(1) ~= ';'
        break;
    end

    txt = regexprep(lnRaw,'^[#%;\s]+','');
    txtL = lower(txt);

    % Baseline window
    if isempty(roiH.baselineText) && ~isempty(strfind(txtL,'baselinewindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.baselineText = strtrim(parts{2});
        else
            roiH.baselineText = strtrim(txt);
        end
    end

    % Signal window
    if isempty(roiH.signalText) && ~isempty(strfind(txtL,'signalwindow'))
        parts = regexp(txt,'[:]','split');
        if numel(parts) >= 2
            roiH.signalText = strtrim(parts{2});
        else
            roiH.signalText = strtrim(txt);
        end
    end

    % ROI index
    if isempty(roiH.roiNo) && ~isempty(strfind(txtL,'roi_index'))
        tok = regexp(txt,'ROI_INDEX\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.roiNo = tok{1};
        end
    end

    % Slice
    if isempty(roiH.slice) && ~isempty(strfind(txtL,'slice'))
        tok = regexp(txt,'SLICE\s*:\s*([0-9]+)','tokens','once','ignorecase');
        if ~isempty(tok)
            roiH.slice = tok{1};
        end
    end

    % x1 x2 y1 y2 header
    if ~isempty(regexp(txtL,'^x1\s+x2\s+y1\s+y2$', 'once'))
        expectXYLine = true;
        continue;
    end

    % fallback inline style if ever present
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

        % Global header
        hdrRg = ws.Range(sprintf('A1:%s1', lastCol));
        hdrRg.Font.Bold = true;
        hdrRg.Font.Size = 12;
        hdrRg.Interior.Color = excelRGB(217,217,217);
        hdrRg.HorizontalAlignment = -4108;
        hdrRg.VerticalAlignment   = -4108;
        hdrRg.WrapText = true;

        % ============================================================
        % Metadata
        % ============================================================
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

        % ============================================================
        % Condition_A / Condition_B
        % ============================================================
        if strncmpi(sheetName,'Condition_',10)
            % Layout used:
            % rows 1..5 top labels/values
            % rows 6..7 blank
            % row 8 info
            % row 9 time/animal header
            % row 10+ raw values

            % Left labels
            ws.Range('A1:B5').Font.Bold = true;
            ws.Range('A1:B5').Font.Size = 13;
            ws.Range('A1:B5').Interior.Color = excelRGB(217,217,217);
            ws.Range('A1:B5').HorizontalAlignment = -4108;
            ws.Range('A1:B5').VerticalAlignment   = -4108;
            try
                ws.Range('A1:B5').Font.Underline = 2;
            catch
            end

            % blank rows stay white
            if nRows >= 6
                ws.Range(sprintf('A6:%s7', lastCol)).Interior.Color = excelRGB(255,255,255);
            end

            % PSC info row
            if nRows >= 8
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Bold = true;
                ws.Range(sprintf('A8:%s8', lastCol)).Font.Size = 11;
                ws.Range(sprintf('A8:%s8', lastCol)).Interior.Color = excelRGB(242,242,242);
            end

            % time header row
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

                % whole animal column
                blockRg = ws.Range(sprintf('%s1:%s%d', dataCol, dataCol, nRows));
                blockRg.Interior.Color = excelPastelColor(animalIdx);
                blockRg.HorizontalAlignment = -4108;
                blockRg.VerticalAlignment   = -4108;

                % top responses larger than raw values
                topRg = ws.Range(sprintf('%s1:%s5', dataCol, dataCol));
                topRg.Font.Bold = true;
                topRg.Font.Size = 12;
                topRg.WrapText = true;

                % header row with animal label
                if nRows >= 9
                    hdr2Rg = ws.Range(sprintf('%s9:%s9', dataCol, dataCol));
                    hdr2Rg.Font.Bold = true;
                    hdr2Rg.Font.Size = 12;
                    hdr2Rg.WrapText = true;
                end

                % raw values smaller
                if nRows >= 10
                    dataRg = ws.Range(sprintf('%s10:%s%d', dataCol, dataCol, nRows));
                    dataRg.Font.Size = 10;
                    dataRg.HorizontalAlignment = -4108;
                    dataRg.VerticalAlignment   = -4108;
                end

                applyExcelBoxBorder(blockRg);

                % spacer column white
                if c+1 <= nCols
                    spCol = excelColLetter(c+1);
                    spRg = ws.Range(sprintf('%s1:%s%d', spCol, spCol, nRows));
                    spRg.Interior.Color = excelRGB(255,255,255);
                end

                c = c + 2;
            end

            % time columns formatting
            if nRows >= 10
                ws.Range(sprintf('A10:B%d', nRows)).Font.Size = 10;
                ws.Range(sprintf('A10:B%d', nRows)).HorizontalAlignment = -4108;
                ws.Range(sprintf('A10:B%d', nRows)).VerticalAlignment   = -4108;
            end
        end

        % ============================================================
        % Outlier_Audit
        % ============================================================
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

function stars = p_to_stars(p)
if ~isfinite(p)
    stars = 'p=?';
elseif p < 0.001
    stars = '***';
elseif p < 0.01
    stars = '**';
elseif p < 0.05
    stars = '*';
else
    stars = 'n.s.';
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
        text(ax, (x1+x2)/2, yBar - 0.06*ySpan, sprintf('p=%.3g (alpha=%.3g)', p, alpha), ...
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
    try, tc = mean(tc,1,'omitnan'); catch, tc = mean(tc,1); end
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

if strcmpi(testType,'One-sample t-test (vs 0)')
    [t,p,df] = oneSampleT_vec(metricVals);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = 'One-sample vs 0';

elseif strcmpi(testType,'Two-sample t-test (Student, equal var)')
    if numel(gNames)<2, error('Need >=2 groups.'); end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = studentT_equalVar_vec(a,b);
    stats.t = t;
    stats.p = p;
    stats.df = df;
    stats.desc = [gNames{1} ' vs ' gNames{2}];

elseif strcmpi(testType,'Two-sample t-test (Welch)')
    if numel(gNames)<2, error('Need >=2 groups.'); end
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
if isempty(gNames), error('No groups defined.'); end

N = size(subjActive,1);
tcAll = cell(N,1);
tAll  = cell(N,1);
isPSCInput = false(N,1);

for i=1:N
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
for i=1:N
    di = diff(tAll{i});
    di = di(isfinite(di) & di>0);
    if ~isempty(di), dtAll(i) = median(di); end
end
dt = median(dtAll(isfinite(dtAll)));
if ~isfinite(dt) || dt<=0, dt = 0.1; end
if t1<=t0, error('Time axes do not overlap across subjects.'); end
tCommon = t0:dt:t1;

Xraw = nan(N,numel(tCommon));
for i=1:N
    Xraw(i,:) = interp1(tAll{i}(:), tcAll{i}(:), tCommon(:), 'linear', NaN).';
end

X = Xraw;

if S.tc_computePSC
    baseIdx = (tCommon>=S.tc_baseMin0) & (tCommon<=S.tc_baseMin1);
    if ~any(baseIdx), error('Baseline window has no samples.'); end
    for i=1:N
        if isPSCInput(i), continue; end
        b = nanmean_local(Xraw(i,baseIdx),2);
        if ~isfinite(b) || b==0, b = eps; end
        X(i,:) = 100*(Xraw(i,:)-b)./b;
    end
end

unitsPercent = any(isPSCInput) || S.tc_computePSC;
groupColors = assignGroupColorsWithMode(gNames, S);

groupTC = struct([]);
for g=1:numel(gNames)
    idx = strcmpi(grpCol,gNames{g});
    mu = nanmean_local(X(idx,:),1);
    sd = nanstd_local(X(idx,:),0,1);
    n  = sum(isfinite(X(idx,:)),1);
    se = sd./sqrt(max(1,n));
    groupTC(g).name = gNames{g};
    groupTC(g).mean = mu;
    groupTC(g).sem  = se;
    groupTC(g).n    = sum(idx);
end

platIdx = (tCommon>=S.tc_plateauMin0) & (tCommon<=S.tc_plateauMin1);
if ~any(platIdx), error('Plateau window has no samples.'); end
plateau = nan(N,1);
for i=1:N
    plateau(i) = nanmean_local(X(i,platIdx),2);
end

peakVal = nan(N,1);
for i=1:N
    peakVal(i) = robustPeak(X(i,:), tCommon, S.tc_peakSearchMin0, S.tc_peakSearchMin1, S.tc_peakWinMin, S.tc_trimPct);
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
for i=1:N
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

    function meta = extractMetaFromSources(subjectTxt, dataFile, roiFile)
meta = struct('animalID','N/A','session','N/A','scanID','N/A');

cands = {roiFile, dataFile, subjectTxt};

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

if nargin < 1 || isempty(txt), return; end
try
    txt = char(txt);
catch
    return;
end

txt = strrep(txt,'\','/');
txtU = upper(txt);

% Best case:
% WT250409_S2_FUS_105305
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)_(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = upper(strtrim(tok{1}));
    meta.session  = upper(strtrim(tok{2}));
    meta.scanID   = upper(strtrim(tok{3}));
    return;
end

% Animal + session
tok = regexpi(txtU,'([A-Z]{1,8}\d{6}[A-Z]?)_(S\d+)','tokens','once');
if ~isempty(tok)
    meta.animalID = upper(strtrim(tok{1}));
    meta.session  = upper(strtrim(tok{2}));
end

% Scan ID
tok = regexpi(txtU,'(FUS_\d+)','tokens','once');
if ~isempty(tok)
    meta.scanID = upper(strtrim(tok{1}));
end

% Animal only fallback
if strcmpi(meta.animalID,'N/A')
    tok = regexpi(txtU,'\b([A-Z]{1,8}\d{6}[A-Z]?)\b','tokens','once');
    if ~isempty(tok)
        meta.animalID = upper(strtrim(tok{1}));
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
if i1 < i0, idx = i0; else, idx = i0:i1; end
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

function [R, cache] = runPSCMapAnalysis(S, subjActive, cache)
if S.baseEnd <= S.baseStart, error('Baseline end must be > baseline start.'); end
if S.sigEnd  <= S.sigStart,  error('Signal end must be > signal start.'); end

grpCol = colAsStr(subjActive,3);
grpCol(cellfun(@isempty,grpCol)) = {'GroupA'};
gNames = uniqueStable(grpCol);
if isempty(gNames), error('No groups defined.'); end

maps = cell(size(subjActive,1),1);
for i=1:size(subjActive,1)
    fp = strtrimSafe(subjActive{i,6});
    if isempty(fp) || exist(fp,'file')~=2
        error('Row %d missing DATA .mat for PSC Map mode.', i);
    end
    [maps{i}, cache] = getCachedPSCMap(cache, fp, S.baseStart, S.baseEnd, S.sigStart, S.sigEnd);
end

groupSummary = struct([]);
for g=1:numel(gNames)
    idx = strcmpi(grpCol, gNames{g});
    groupMaps = maps(idx);
    groupSummary(g).name = gNames{g};
    if strcmpi(S.mapSummary,'Median')
        groupSummary(g).map = medianCat(groupMaps);
    else
        groupSummary(g).map = meanCat(groupMaps);
    end
end

R = struct();
R.mode = 'PSC Map';
R.group = groupSummary;
R.groupNames = gNames;
R.groupDisplayNames = resolveDisplayGroupNames(gNames, S);
R.stats = struct('p',NaN,'alpha',S.alpha,'type','None');
end



function colors = buildTableRowColors(subj)
n = size(subj,1);
if n <= 0
    colors = [1 1 1];
    return;
end

colors = repmat([1.00 1.00 1.00], n, 1);

for i = 1:n
    use = logicalCellValue(subj{i,1});
    roi = strtrimSafe(subj{i,7});
    st  = lower(strtrimSafe(subj{i,8}));

    if contains(st,'excluded') || ~use
        colors(i,:) = [1.00 0.80 0.80];   % light red
    elseif ~isempty(roi) && exist(roi,'file') == 2
        colors(i,:) = [0.80 1.00 0.80];   % light green
    elseif isempty(roi)
        colors(i,:) = [0.97 0.97 0.97];
    else
        colors(i,:) = [1.00 0.93 0.82];   % light orange
    end
end
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

function exportOnePreview(ax, which, S, style)
R = S.last;
cla(ax);
styleAxesMode(ax, style, S.previewShowGrid);
recolorAxesText(ax, style);
[~,fg] = previewColors(style);

if strcmpi(R.mode,'PSC Map')
    displayNames = getDisplayNamesFromR(R);

    if which == 1
        imagesc_mode(ax, squeeze2D(R.group(1).map), style);
        cb = colorbar(ax);
        styleColorbarMode(cb, style);
        title(ax, ['PSC Map: ' displayNames{1}], 'Color', fg);
        moveTitleUp(ax, titleYForStyle(style));
        recolorAxesText(ax, style);
    else
        if numel(R.group) >= 2
            imagesc_mode(ax, squeeze2D(R.group(2).map), style);
            cb = colorbar(ax);
            styleColorbarMode(cb, style);
            title(ax, ['PSC Map: ' displayNames{2}], 'Color', fg);
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
            lineCol = [0 0 0];
            fillCol = [0.65 0.65 0.65];
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
    title(ax, ['Metric: ' R.metricName], 'Color', fg);
    moveTitleUp(ax, titleYForStyle(style));

    applyYLim(ax, allBot, S.plotBot);

    highlightOutliersOnScatter(ax, R, S, rowX, style);
    recolorAxesText(ax, style);

    if isfield(R,'stats') && isfield(R.stats,'p') && isfinite(R.stats.p)
        annotateStatsBottom(ax, R, S);
    end

    hold(ax,'off');
end
end