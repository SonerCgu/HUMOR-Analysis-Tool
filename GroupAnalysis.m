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
colNames = {'Use','Subject','Group','Condition','PairID','DataFile','ROIFile','Status'};
colEdit  = [true true true true true false false false];
colFmt   = {'logical','char',S.groupList,S.condList,'char','char','char','char'};

S.hTable = uitable(pLeft, ...
    'Units','normalized','Position',[0.03 0.33 0.70 0.64], ...
    'Data',S.subj, ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'ColumnFormat',colFmt, ...
    'RowName','numbered', ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',C.txt, ...
    'FontName','Consolas', ...
    'FontSize',F.table, ...
    'CellSelectionCallback',@onCellSelect, ...
    'CellEditCallback',@onCellEdit);

% -------------------- Quick Assign -----------------------
pQuick = uipanel(pLeft,'Units','normalized','Position',[0.75 0.33 0.22 0.64], ...
    'Title','Quick Assign', 'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontSize',F.base,'FontWeight','bold');

S.hSelInfo = uicontrol(pQuick,'Style','text','String','Selected: none', ...
    'Units','normalized','Position',[0.05 0.93 0.90 0.06], ...
    'BackgroundColor',C.panel2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hApplyAllIfNone = uicontrol(pQuick,'Style','checkbox', ...
    'String','If none selected: apply to ALL active (Use=true)', ...
    'Units','normalized','Position',[0.05 0.87 0.90 0.06], ...
    'Value', double(S.applyAllIfNoneSelected), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'Callback',@onApplyAllToggle);

uicontrol(pQuick,'Style','text','String','Group:', ...
    'Units','normalized','Position',[0.05 0.79 0.90 0.05], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hQuickGroup = uicontrol(pQuick,'Style','popupmenu','String',S.groupList, ...
    'Units','normalized','Position',[0.05 0.74 0.90 0.06], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

uicontrol(pQuick,'Style','text','String','Condition:', ...
    'Units','normalized','Position',[0.05 0.65 0.90 0.05], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hQuickCond = uicontrol(pQuick,'Style','popupmenu','String',S.condList, ...
    'Units','normalized','Position',[0.05 0.60 0.90 0.06], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w');

S.hApplyGroup = mkBtn(pQuick,'Apply GROUP',[0.05 0.51 0.44 0.07],C.btnAction,@onApplyGroup);
S.hApplyCond  = mkBtn(pQuick,'Apply COND',[0.51 0.51 0.44 0.07],C.btnAction,@onApplyCond);
S.hApplyBoth  = mkBtn(pQuick,'Apply BOTH',[0.05 0.43 0.90 0.07],C.btnPrimary,@onApplyBoth);

S.hAddGroup = mkBtn(pQuick,'Add group...',[0.05 0.34 0.44 0.07],C.btnSecondary,@onAddGroup);
S.hAddCond  = mkBtn(pQuick,'Add cond...',[0.51 0.34 0.44 0.07],C.btnSecondary,@onAddCond);

S.hAutoPair = uicontrol(pQuick,'Style','checkbox','String','Auto PairID = Subject', ...
    'Units','normalized','Position',[0.05 0.27 0.90 0.05], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','Value',1);

S.hFillFromROI = mkBtn(pQuick,'Fill DATA from ROI folder',[0.05 0.20 0.90 0.06],C.btnSecondary,@onFillFromROISelected);
S.hRevertExcluded = mkBtn(pQuick,'Revert EXCLUDED rows',[0.05 0.13 0.90 0.06],C.btnSecondary,@onRevertExcluded);
S.hHelp = mkBtn(pQuick,'HELP',[0.05 0.05 0.90 0.06],C.btnHelp,@onHelp);

% -------------------- Left buttons -----------------------
S.hAddFiles  = mkBtn(pLeft,'Add Files',[0.03 0.26 0.22 0.06],C.btnSecondary,@onAddFiles);
S.hAddFolder = mkBtn(pLeft,'Add Folder (scan)',[0.26 0.26 0.22 0.06],C.btnSecondary,@onAddFolder);
S.hRemove    = mkBtn(pLeft,'Remove selected',[0.49 0.26 0.24 0.06],C.btnDanger,@onRemoveSelected);

S.hSetData = mkBtn(pLeft,'Set DATA for selected',[0.03 0.20 0.34 0.055],C.btnAction,@onSetDataSelected);
S.hSetROI  = mkBtn(pLeft,'Set ROI for selected',[0.39 0.20 0.34 0.055],C.btnAction,@onSetROISelected);

S.hSaveList = mkBtn(pLeft,'Save list',[0.03 0.135 0.34 0.055],C.btnSecondary,@onSaveList);
S.hLoadList = mkBtn(pLeft,'Load list',[0.39 0.135 0.34 0.055],C.btnSecondary,@onLoadList);

uicontrol(pLeft,'Style','text','String','Output folder:', ...
    'Units','normalized','Position',[0.03 0.085 0.20 0.04], ...
    'BackgroundColor',C.panel,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',F.base);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.23 0.085 0.40 0.045], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',F.base, ...
    'Callback',@onOutEdit);

S.hOutBrowse = mkBtn(pLeft,'Browse',[0.64 0.085 0.09 0.045],C.btnSecondary,@onBrowseOut);

S.hHint = uicontrol(pLeft,'Style','text', ...
    'String','Tip: preview is fully redrawn to avoid overlap/stale plots. CSV exports are UTF-8.', ...
    'Units','normalized','Position',[0.03 0.02 0.70 0.055], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',F.small);

% -------------------- Tabs -------------------------------
S.tabGroup = uitabgroup(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.96]);
try, set(S.tabGroup,'FontSize',F.tab); catch, end

S.tabROI   = uitab(S.tabGroup,'Title','ROI Timecourse');
S.tabMAP   = uitab(S.tabGroup,'Title','PSC Maps');
S.tabSTATS = uitab(S.tabGroup,'Title','Stats');
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
    'Title','Y-axis scaling (uncheck Auto to use Ymin/Ymax)', ...
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

S.hRun    = mkBtn(pRun,'RUN ANALYSIS',[0.02 0.62 0.30 0.30],C.btnPrimary,@onRun);
S.hExport = mkBtn(pRun,'EXPORT RESULTS',[0.34 0.62 0.30 0.30],C.btnAction,@onExport);

S.hStatus = uicontrol(pRun,'Style','text','String','Ready.', ...
    'Units','normalized','Position',[0.02 0.10 0.96 0.42], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontSize',F.small);

% -------------------- PREVIEW TAB ------------------------
S.hPrevBG = uipanel(S.tabPREV,'Units','normalized','Position',[0 0 1 1], ...
    'BorderType','none','BackgroundColor',C.bg);

S.hPrevTop = uipanel(S.hPrevBG,'Units','normalized','Position',[0.02 0.94 0.96 0.05], ...
    'Title','', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

mkBtn(S.hPrevTop,'Export TOP PNG',   [0.02 0.10 0.16 0.80],C.btnAction,@(~,~) onExportPreviewPNG(1));
mkBtn(S.hPrevTop,'Export BOTTOM PNG',[0.19 0.10 0.18 0.80],C.btnAction,@(~,~) onExportPreviewPNG(2));
mkBtn(S.hPrevTop,'Export BOTH PNGs', [0.38 0.10 0.16 0.80],C.btnAction,@(~,~) onExportPreviewPNG(3));

uicontrol(S.hPrevTop,'Style','text','String','View:', ...
    'Units','normalized','Position',[0.57 0.15 0.05 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hPrevStyle = uicontrol(S.hPrevTop,'Style','popupmenu','String',{'Dark','Light'}, ...
    'Units','normalized','Position',[0.62 0.18 0.10 0.64], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

S.hPrevGrid = uicontrol(S.hPrevTop,'Style','checkbox','String','Grid', ...
    'Units','normalized','Position',[0.74 0.15 0.08 0.70], ...
    'Value', double(S.previewShowGrid), ...
    'BackgroundColor',bg2,'ForegroundColor','w','Callback',@onPreviewStyleChanged);

% Smooth checkbox
S.hSmoothEnable = uicontrol(S.hPrevTop,'Style','checkbox','String','Smooth', ...
    'Units','normalized','Position',[0.82 0.15 0.08 0.70], ...
    'Value', double(S.tc_previewSmooth), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onSmoothChanged);

% Win label
uicontrol(S.hPrevTop,'Style','text','String','Win (s):', ...
    'Units','normalized','Position',[0.90 0.15 0.05 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontWeight','bold');

% Win edit
S.hSmoothWin = uicontrol(S.hPrevTop,'Style','edit','String',num2str(S.tc_previewSmoothWinSec), ...
    'Units','normalized','Position',[0.95 0.18 0.04 0.64], ...
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
        msg = [ ...
            'ROI txt PSC files are plotted directly.' newline ...
            'No baseline subtraction is applied unless compute %SC is enabled for raw input.' newline newline ...
            'Preview is now always fully redrawn from the stored last result to prevent overlap or missing SEM.' newline ...
            'Repeated analyses reuse cached ROI timecourses and PSC maps when possible.' ];
        msgbox(msg,'GroupAnalysis Help','help');
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
                S0.subj{hit,8} = htmlRed('EXCLUDED (outlier)');
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
            if iscell(dt), S0.subj = dt; end
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

        colFmt = {'logical','char',S0.groupList,S0.condList,'char','char','char','char'};
        try, set(S0.hTable,'ColumnFormat',colFmt); catch, end
        set(S0.hTable,'Data',S0.subj);
        set(S0.hTable,'RowName','numbered');

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

function S = sanitizeTableStruct(S)
if isempty(S.subj), return; end
if size(S.subj,2) < 8, S.subj(:,end+1:8) = {''}; end
if size(S.subj,2) > 8, S.subj = S.subj(:,1:8); end
for r=1:size(S.subj,1)
    if isempty(S.subj{r,1}) || ~(islogical(S.subj{r,1}) || isnumeric(S.subj{r,1}))
        S.subj{r,1} = true;
    else
        S.subj{r,1} = logical(S.subj{r,1});
    end
    if isempty(strtrimSafe(S.subj{r,2})), S.subj{r,2} = ['S' num2str(r)]; end
    if isempty(strtrimSafe(S.subj{r,3})), S.subj{r,3} = S.defaultGroup; end
    if isempty(strtrimSafe(S.subj{r,4})), S.subj{r,4} = S.defaultCond; end
end
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

function out = mergeUniqueStable(a,b)
if isempty(a), a={}; end
if isempty(b), b={}; end
out = a(:).';
for i=1:numel(b)
    if isempty(b{i}), continue; end
    if ~any(strcmpi(out,b{i})), out{end+1}=b{i}; end %#ok<AGROW>
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
if strcmpi(S.previewStyle,'Light')
    set(S.hPrevBG,  'BackgroundColor',[1 1 1]);
    set(S.hPrevTop, 'BackgroundColor',[0.96 0.96 0.96], 'ForegroundColor','k');

    % also recolor smoothing controls (if they exist)
if isfield(S,'hSmoothEnable') && ishghandle(S.hSmoothEnable)
    if strcmpi(S.previewStyle,'Light')
        set(S.hSmoothEnable,'BackgroundColor',[0.96 0.96 0.96],'ForegroundColor','k');
        try, set(S.hSmoothWin,'BackgroundColor',[1 1 1],'ForegroundColor','k'); catch, end
    else
        set(S.hSmoothEnable,'BackgroundColor',S.C.panel2,'ForegroundColor','w');
        try, set(S.hSmoothWin,'BackgroundColor',S.C.editBg,'ForegroundColor','w'); catch, end
    end
end

    try, set(S.hPrevStyle,'BackgroundColor',[1 1 1],'ForegroundColor','k'); catch, end
    try, set(S.hPrevGrid, 'BackgroundColor',[0.96 0.96 0.96],'ForegroundColor','k'); catch, end
    try, set(S.hPrevMsg,  'BackgroundColor',[0.96 0.96 0.96],'ForegroundColor',[0.2 0.2 0.2]); catch, end
else
    set(S.hPrevBG,  'BackgroundColor',S.C.bg);
    set(S.hPrevTop, 'BackgroundColor',S.C.panel2, 'ForegroundColor','w');

    try, set(S.hPrevStyle,'BackgroundColor',S.C.editBg,'ForegroundColor','w'); catch, end
    try, set(S.hPrevGrid, 'BackgroundColor',S.C.panel2,'ForegroundColor','w'); catch, end
    try, set(S.hPrevMsg,  'BackgroundColor',S.C.panel2,'ForegroundColor',S.C.muted); catch, end
end
end

function [h0,h1] = addPairEditsDark(parent, y, label, v0, v1, C, cb)
bg = get(parent,'BackgroundColor');
uicontrol(parent,'Style','text','String',label, ...
    'Units','normalized','Position',[0.02 y 0.35 0.12], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
h0 = uicontrol(parent,'Style','edit','String',num2str(v0), ...
    'Units','normalized','Position',[0.38 y 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cb);
h1 = uicontrol(parent,'Style','edit','String',num2str(v1), ...
    'Units','normalized','Position',[0.52 y 0.12 0.12], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cb);
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

function exportOnePreview(ax, which, S, style)
R = S.last;
cla(ax);
styleAxesMode(ax, style, S.previewShowGrid);
recolorAxesText(ax, style);
[~,fg] = previewColors(style);

if strcmpi(R.mode,'PSC Map')
    displayNames = getDisplayNamesFromR(R);
    if which==1
        imagesc_mode(ax, squeeze2D(R.group(1).map), style);
        cb = colorbar(ax);
        styleColorbarMode(cb, style);
        title(ax, ['PSC Map: ' displayNames{1}], 'Color', fg);
        moveTitleUp(ax, titleYForStyle(style));
        recolorAxesText(ax, style);
    else
        if numel(R.group)>=2
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

if which==1
    hold(ax,'on');
    allTop = [];
    leg = {};
    lineHs = [];

  for g=1:numel(R.group)

    mu = R.group(g).mean(:)';
    se = R.group(g).sem(:)';

    if S.tc_previewSmooth
        dtSec = median(diff(t))*60;
        mu = smooth1D_edgeCentered(mu, dtSec, S.tc_previewSmoothWinSec);
        se = smooth1D_edgeCentered(se, dtSec, S.tc_previewSmoothWinSec);
        se(se<0) = 0;
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
        lg = legend(ax, lineHs, leg, 'Location','northwest','Box','off');
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
    grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,3), 'UniformOutput',false);
    xTicks = 1:numel(gNames);

    hold(ax,'on');
    allBot = [];
    rowX = nan(size(metricVals));

    for g=1:numel(gNames)
        idx = strcmpi(grpCol,gNames{g});
        idxRows = find(idx & isfinite(metricVals));
        y = metricVals(idxRows);
        if isempty(y), continue; end

        col = R.groupColors.(makeField(gNames{g}));
        rowKeys = makeRowKeys(R.subjTable(idxRows,:));
        jitter = zeros(size(y));
        for ii=1:numel(rowKeys)
            jitter(ii) = deterministicJitter(rowKeys{ii}, 0.18);
        end
        rowX(idxRows) = xTicks(g)+jitter;

        scatter(ax,rowX(idxRows),y,60,col,'filled');
        plot(ax,[xTicks(g)-0.25 xTicks(g)+0.25],[mean(y) mean(y)],'LineWidth',2.5,'Color',col);

        allBot = [allBot; y(:)]; %#ok<AGROW>
    end

    set(ax,'XLim',[0.5 numel(gNames)+0.5],'XTick',xTicks,'XTickLabel',displayNames);
    ylabel(ax, tern(R.unitsPercent,'Signal change (%)','Metric (a.u.)'), 'Color',fg);
    title(ax,['Metric: ' R.metricName],'Color',fg);
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