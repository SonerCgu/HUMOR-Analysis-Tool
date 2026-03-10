function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m (MATLAB 2017b + 2023b) — FULL SINGLE-FILE
% =========================================================
% FIXES (based on your screenshots):
% 1) Y-axis scaling: revert to normal Ymin/Ymax editable boxes
%    + add Step (small) + tiny +/- nudges (no giant blocks)
% 2) Ymax is editable again (no overlap)
% 3) Preview tab background fixed (dark panel behind axes) -> no weird look
% 4) UTF-8 CSV export (avoids Windows-1252 error)
% 5) Display style layout kept clean (Group A/Color A, Group B/Color B separate lines)
%
% Table columns:
%   Use | Subject | Group | Condition | PairID | DataFile | ROIFile | Status
% =========================================================

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

if ~isempty(posStudio),  opt.studio = posStudio; end
if ~isempty(posOnClose), opt.onClose = posOnClose; end

if isempty(opt.startDir), opt.startDir = pwd; end
if isfield(opt.studio,'exportPath') && ~isempty(opt.studio.exportPath) && exist(opt.studio.exportPath,'dir')
    opt.startDir = opt.studio.exportPath;
end

% -------------------- Theme + Fonts ----------------------
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
hFig = figure('Name','fUSI Studio — Group Analysis', ...
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
S.opt = opt; S.C = C; S.F = F;

S.subj = cell(0,8);        % Use|Subject|Group|Condition|PairID|DataFile|ROIFile|Status
S.selectedRows = [];
S.isClosing = false;
S.last = struct();
S.mode = 'ROI Timecourse';

S.groupList = {'PACAP','Vehicle','Control','GroupA','GroupB'};
S.condList  = {'CondA','CondB','Baseline','Post'};
S.defaultGroup = 'PACAP';
S.defaultCond  = 'CondA';

S.applyAllIfNoneSelected = true;

% ROI defaults (minutes)
S.tc_computePSC = false;
S.tc_baseMin0   = 0;  S.tc_baseMin1 = 10;
S.tc_injMin0    = 10; S.tc_injMin1  = 20;
S.tc_plateauMin0 = 30; S.tc_plateauMin1 = 40;
S.tc_peakSearchMin0 = 10; S.tc_peakSearchMin1 = 20;
S.tc_peakWinMin = 3;
S.tc_trimPct    = 10;
S.tc_metric     = 'Robust Peak';
S.tc_baselineZero = 'Subtract baseline mean';
S.tc_showSEM = true;

% PSC map defaults (sec)
S.baseStart = 0;  S.baseEnd = 10;
S.sigStart  = 10; S.sigEnd  = 30;
S.mapSummary = 'Mean';

% Display style / colors
S.colorMode = 'Scheme';               % Scheme | Manual A/B
S.colorScheme = 'PACAP/Vehicle';
S.manualGroupA = 'PACAP';
S.manualGroupB = 'Vehicle';
S.manualColorA = 1;
S.manualColorB = 2;

% Plot scaling + step size (REVERTED normal)
S.plotTop = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150,'step',5);
S.plotBot = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150,'step',5);

% Stats
S.testType = 'None';
S.alpha = 0.05;

% Outliers
S.outlierMethod = 'None';
S.outMADthr = 3.5;
S.outIQRk   = 1.5;
S.outlierKeys = {};
S.outlierInfo = {};

S.outDir = defaultOutDir(opt);

% -------------------- Layout panels ----------------------
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

% -------------------- Quick Assign panel -----------------
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

% -------------------- Left-side buttons ------------------
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
    'String','Tip: Edit Group/Condition in table dropdown OR Quick Assign. Uncheck Auto to set Ymin/Ymax.', ...
    'Units','normalized','Position',[0.03 0.02 0.70 0.055], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',F.small);

% -------------------- Tabs (Right) -----------------------
S.tabGroup = uitabgroup(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.96]);
try, set(S.tabGroup,'FontSize',F.tab); catch, end

S.tabROI   = uitab(S.tabGroup,'Title','ROI Timecourse');
S.tabMAP   = uitab(S.tabGroup,'Title','PSC Maps');
S.tabSTATS = uitab(S.tabGroup,'Title','Stats');
S.tabPREV  = uitab(S.tabGroup,'Title','Preview');

% -------------------- ROI TAB ----------------------------
bg2 = C.panel2;

pROItop = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.92 0.96 0.07], ...
    'Title','', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pROItop,'Style','text','String','Active mode:', ...
    'Units','normalized','Position',[0.02 0.15 0.18 0.70], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hMode = uicontrol(pROItop,'Style','popupmenu', ...
    'String',{'ROI Timecourse','PSC Map'}, ...
    'Units','normalized','Position',[0.20 0.18 0.25 0.70], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onModeChanged);

pROI = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.60 0.96 0.30], ...
    'Title','ROI settings', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hTC_ComputePSC = uicontrol(pROI,'Style','checkbox', ...
    'String','Compute %SC from raw using baseline (ignored if ROI txt already PSC)', ...
    'Units','normalized','Position',[0.02 0.82 0.96 0.15], ...
    'Value', double(S.tc_computePSC), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

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

% ---------- Display style (clean) ----------
pStyle = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.36 0.96 0.22], ...
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

S.hShowSEM = uicontrol(pStyle,'Style','checkbox','String','Show SEM shading', ...
    'Units','normalized','Position',[0.80 0.72 0.18 0.22], ...
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

% ---------- Y scaling (REVERTED normal + small step nudges) ----------
pY = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.02 0.96 0.32], ...
    'Title','Y-axis scaling (Step nudges; uncheck Auto to use Ymin/Ymax)', ...
    'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

[S.hTopAuto,S.hTopZero,S.hTopStep,S.hTopYmin,S.hTopYmax, ...
 S.hTopYminM,S.hTopYminP,S.hTopYmaxM,S.hTopYmaxP] = mkYControlsStepCompact( ...
    pY,0.62,'Top',S.plotTop,C,@onPlotScaleChanged,@onYStep);

[S.hBotAuto,S.hBotZero,S.hBotStep,S.hBotYmin,S.hBotYmax, ...
 S.hBotYminM,S.hBotYminP,S.hBotYmaxM,S.hBotYmaxP] = mkYControlsStepCompact( ...
    pY,0.20,'Bottom',S.plotBot,C,@onPlotScaleChanged,@onYStep);

% -------------------- MAP TAB ----------------------------
pMap = uipanel(S.tabMAP,'Units','normalized','Position',[0.02 0.55 0.96 0.43], ...
    'Title','PSC map windows (seconds)', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');
S.hBaseStart = makeWinRowDark(pMap,0.70,'Baseline start',num2str(S.baseStart),@onPSCEdit,'baseStart',C);
S.hBaseEnd   = makeWinRowDark(pMap,0.48,'Baseline end',  num2str(S.baseEnd),  @onPSCEdit,'baseEnd',C);
S.hSigStart  = makeWinRowDark(pMap,0.26,'Signal start',  num2str(S.sigStart), @onPSCEdit,'sigStart',C);
S.hSigEnd    = makeWinRowDark(pMap,0.04,'Signal end',    num2str(S.sigEnd),   @onPSCEdit,'sigEnd',C);

uicontrol(S.tabMAP,'Style','text','String','Summary (per group):', ...
    'Units','normalized','Position',[0.04 0.45 0.25 0.05], ...
    'BackgroundColor',C.bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hMapSummary = uicontrol(S.tabMAP,'Style','popupmenu','String',{'Mean','Median'}, ...
    'Units','normalized','Position',[0.28 0.44 0.20 0.06], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onMapChanged);

% -------------------- STATS TAB --------------------------
pStats = uipanel(S.tabSTATS,'Units','normalized','Position',[0.02 0.62 0.96 0.36], ...
    'Title','Metric statistics', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.02 0.62 0.12 0.30], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hTest = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','One-sample t-test (vs 0)','Two-sample t-test (Welch)','One-way ANOVA (groups)'}, ...
    'Units','normalized','Position',[0.14 0.64 0.60 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.77 0.62 0.10 0.30], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hAlpha = uicontrol(pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.86 0.64 0.12 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onStatsChanged);

pOut = uipanel(pStats,'Units','normalized','Position',[0.02 0.05 0.96 0.52], ...
    'Title','Outlier detection', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pOut,'Style','text','String','Method:', ...
    'Units','normalized','Position',[0.02 0.62 0.14 0.28], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hOutMethod = uicontrol(pOut,'Style','popupmenu','String',{'None','MAD robust z-score','IQR rule'}, ...
    'Units','normalized','Position',[0.16 0.64 0.30 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onOutlierChanged);

S.hOutParamLbl = uicontrol(pOut,'Style','text','String','Thr (z):', ...
    'Units','normalized','Position',[0.48 0.62 0.12 0.28], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');
S.hOutParam = uicontrol(pOut,'Style','edit','String',num2str(S.outMADthr), ...
    'Units','normalized','Position',[0.60 0.64 0.12 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',@onOutlierChanged);

S.hDetectOut = mkBtn(pOut,'Detect',[0.74 0.64 0.24 0.30],C.btnAction,@onDetectOutliers);

S.hOutList = uicontrol(pOut,'Style','listbox','String',{}, ...
    'Units','normalized','Position',[0.02 0.06 0.72 0.50], ...
    'BackgroundColor',[0 0 0],'ForegroundColor','w', ...
    'FontName','Consolas','FontSize',F.small);

S.hExcludeOut = mkBtn(pOut,'EXCLUDE outliers',[0.76 0.30 0.22 0.26],C.btnDanger,@onExcludeOutliers);
S.hRevertOut  = mkBtn(pOut,'REVERT excluded',[0.76 0.06 0.22 0.20],C.btnSecondary,@onRevertExcluded);

pRun = uipanel(S.tabSTATS,'Units','normalized','Position',[0.02 0.02 0.96 0.56], ...
    'Title','Run / Export', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hRun    = mkBtn(pRun,'RUN ANALYSIS',[0.02 0.62 0.30 0.30],C.btnPrimary,@onRun);
S.hExport = mkBtn(pRun,'EXPORT RESULTS',[0.34 0.62 0.30 0.30],C.btnAction,@onExport);

S.hStatus = uicontrol(pRun,'Style','text','String','Ready.', ...
    'Units','normalized','Position',[0.02 0.10 0.96 0.42], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontSize',F.small);

% -------------------- PREVIEW TAB (FIXED background) -----
pPrevBG = uipanel(S.tabPREV,'Units','normalized','Position',[0 0 1 1], ...
    'BorderType','none','BackgroundColor',C.bg);

pPrevTop = uipanel(pPrevBG,'Units','normalized','Position',[0.02 0.94 0.96 0.05], ...
    'Title','', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

mkBtn(pPrevTop,'Export TOP PNG',   [0.02 0.10 0.20 0.80],C.btnAction,@(~,~) onExportPreviewPNG(1));
mkBtn(pPrevTop,'Export BOTTOM PNG',[0.24 0.10 0.23 0.80],C.btnAction,@(~,~) onExportPreviewPNG(2));
mkBtn(pPrevTop,'Export BOTH PNGs', [0.49 0.10 0.22 0.80],C.btnAction,@(~,~) onExportPreviewPNG(3));

S.hPrevMsg = uicontrol(pPrevTop,'Style','text','String','', ...
    'Units','normalized','Position',[0.73 0.10 0.25 0.80], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontSize',F.small);

S.ax1 = axes('Parent',pPrevBG,'Units','normalized','Position',[0.08 0.56 0.88 0.35], ...
    'Color',C.axisBg,'XColor','w','YColor','w');
title(S.ax1,'Top plot','Color','w','FontWeight','bold');

S.ax2 = axes('Parent',pPrevBG,'Units','normalized','Position',[0.08 0.10 0.88 0.35], ...
    'Color',C.axisBg,'XColor','w','YColor','w');
title(S.ax2,'Bottom plot','Color','w','FontWeight','bold');

fixAxesInset(S.ax1); fixAxesInset(S.ax2);

% -------------------- init -------------------------------
guidata(hFig,S);
syncUIFromState();
refreshTable();
clearPreview();
setStatus(false);
setStatusText('Ready. (Y scaling reverted; Step nudges are small)');

% =========================================================
% Callbacks
% =========================================================
    function closeMe(src,~)
        S = guidata(src);
        if isempty(S), delete(src); return; end
        if isfield(S,'isClosing') && S.isClosing, delete(src); return; end
        S.isClosing = true; guidata(src,S);
        try, setStatus(true); catch, end
        if isfield(S.opt,'onClose') && ~isempty(S.opt.onClose)
            try, S.opt.onClose(); catch, end
        end
        delete(src);
    end

    function onCellSelect(~,evt)
        S = guidata(hFig);
        if isempty(evt) || ~isfield(evt,'Indices') || isempty(evt.Indices)
            S.selectedRows = [];
        else
            S.selectedRows = unique(evt.Indices(:,1));
        end
        guidata(hFig,S);
        updateSelLabel();
    end

    function onCellEdit(~,~)
        syncSubjFromTable();
        S = guidata(hFig);

        S.groupList = mergeUniqueStable(S.groupList, uniqueStable(colAsStr(S.subj,3)));
        S.condList  = mergeUniqueStable(S.condList,  uniqueStable(colAsStr(S.subj,4)));
        guidata(hFig,S);

        refreshTable();
    end

    function onApplyAllToggle(src,~)
        S = guidata(hFig);
        S.applyAllIfNoneSelected = logical(get(src,'Value'));
        guidata(hFig,S);
    end

    function rows = getTargetRows()
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if ~isempty(sel)
            rows = sel; return;
        end
        if S.applyAllIfNoneSelected
            rows = find(logicalCol(S.subj,1));
        else
            rows = [];
        end
    end

    function onApplyGroup(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows), setStatusText('No rows selected.'); return; end
        g = getSelectedPopupString(S.hQuickGroup);
        for r=rows(:)', S.subj{r,3} = g; end
        guidata(hFig,S);
        refreshTable();
        setStatusText(sprintf('Applied Group "%s" to %d row(s).', g, numel(rows)));
    end

    function onApplyCond(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        rows = getTargetRows();
        if isempty(rows), setStatusText('No rows selected.'); return; end
        c = getSelectedPopupString(S.hQuickCond);
        for r=rows(:)', S.subj{r,4} = c; end
        guidata(hFig,S);
        refreshTable();
        setStatusText(sprintf('Applied Condition "%s" to %d row(s).', c, numel(rows)));
    end

    function onApplyBoth(~,~)
        onApplyGroup();
        onApplyCond();
    end

    function onAddGroup(~,~)
        S = guidata(hFig);
        answ = inputdlg({'New group name:'},'Add group',1,{''});
        if isempty(answ), return; end
        nm = strtrim(answ{1});
        if isempty(nm), return; end
        S.groupList = mergeUniqueStable(S.groupList,{nm});
        guidata(hFig,S);
        refreshTable();
        setStatusText(['Added group: ' nm]);
    end

    function onAddCond(~,~)
        S = guidata(hFig);
        answ = inputdlg({'New condition name:'},'Add condition',1,{''});
        if isempty(answ), return; end
        nm = strtrim(answ{1});
        if isempty(nm), return; end
        S.condList = mergeUniqueStable(S.condList,{nm});
        guidata(hFig,S);
        refreshTable();
        setStatusText(['Added condition: ' nm]);
    end

    function onHelp(~,~)
        msg = [ ...
            "GROUP ANALYSIS — HELP" newline newline ...
            "FAST group/condition:" newline ...
            "  - Use table dropdowns in Group/Condition columns" newline ...
            "  - Or select rows -> Quick Assign -> Apply" newline newline ...
            "Y-axis scaling:" newline ...
            "  - If Auto is ON, Ymin/Ymax are ignored." newline ...
            "  - Uncheck Auto to manually set Ymin/Ymax." newline ...
            "  - Step + tiny +/- nudges change Ymin/Ymax by that step." newline newline ...
            "Export:" newline ...
            "  - Metrics.csv is written in UTF-8 to avoid Windows-1252 errors." ];
        msgbox(char(msg),'GroupAnalysis Help','help');
    end

    function onAddFiles(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        startPath = S.opt.startDir; if ~exist(startPath,'dir'), startPath=pwd; end
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
        S = guidata(hFig);
        startPath = S.opt.startDir; if ~exist(startPath,'dir'), startPath=pwd; end
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
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), setStatusText('No rows selected.'); return; end
        S.subj(sel,:) = [];
        S.selectedRows = [];
        guidata(hFig,S);
        refreshTable();
        setStatusText(sprintf('Removed %d row(s).', numel(sel)));
    end

    function onSetDataSelected(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end
        startPath = S.opt.startDir; if ~exist(startPath,'dir'), startPath=pwd; end
        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, 'Select DATA (.mat)', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);
        for r=sel(:)', S.subj{r,6} = fp; end
        guidata(hFig,S);
        refreshTable();
        setStatusText('DATA assigned to selected rows.');
    end

    function onSetROISelected(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end
        startPath = S.opt.startDir; if ~exist(startPath,'dir'), startPath=pwd; end
        [f,p] = uigetfile({'*.txt;*.mat','ROI files (*.txt, *.mat)'}, 'Select ROI file', startPath);
        if isequal(f,0), return; end
        fp = fullfile(p,f);

        for r=sel(:)'
            S.subj{r,7} = fp;
            subj = strtrimSafe(S.subj{r,2});
            if get(S.hAutoPair,'Value')==1 && isempty(strtrimSafe(S.subj{r,5}))
                S.subj{r,5} = subj;
            end
            if isempty(strtrimSafe(S.subj{r,6}))
                df = findDataMatNearROI(fp);
                if isempty(df), df = subj; end
                S.subj{r,6} = df;
            end
        end
        guidata(hFig,S);
        refreshTable();
        setStatusText('ROI assigned (DATA auto-filled if possible).');
    end

    function onSaveList(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        [f,p] = uiputfile('GroupSubjects.mat','Save subject list');
        if isequal(f,0), return; end
        subj = S.subj; groupList=S.groupList; condList=S.condList;
        save(fullfile(p,f), 'subj','groupList','condList','-v7');
        setStatusText('Saved list.');
    end

    function onLoadList(~,~)
        S = guidata(hFig);
        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'},'Load subject list');
        if isequal(f,0), return; end
        L = load(fullfile(p,f));
        if isfield(L,'subj'), S.subj = L.subj; end
        if isfield(L,'groupList'), S.groupList = L.groupList; end
        if isfield(L,'condList'),  S.condList  = L.condList;  end
        S = sanitizeTable(S);
        guidata(hFig,S);
        refreshTable();
        clearPreview();
        setStatusText('Loaded list.');
    end

    function onFillFromROISelected(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel), setStatusText('Select rows first.'); return; end

        for r=sel(:)'
            roi  = strtrimSafe(S.subj{r,7});
            subj = strtrimSafe(S.subj{r,2});
            if isempty(subj) && ~isempty(roi)
                subj = guessSubjectID(roi);
                S.subj{r,2} = subj;
            end
            if get(S.hAutoPair,'Value')==1
                S.subj{r,5} = subj;
            end
            if isempty(strtrimSafe(S.subj{r,6})) && ~isempty(roi)
                df = findDataMatNearROI(roi);
                if isempty(df), df = subj; end
                S.subj{r,6} = df;
            end
        end

        guidata(hFig,S);
        refreshTable();
        setStatusText('Filled PairID/DATA from ROI folder.');
    end

    function onRevertExcluded(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        for r=1:size(S.subj,1)
            st = strtrimSafe(S.subj{r,8});
            if contains(lower(st),'excluded')
                S.subj{r,1} = true;
                S.subj{r,8} = '';
            end
        end
        S.outlierKeys = {};
        S.outlierInfo = {};
        guidata(hFig,S);
        refreshTable();
        try, set(S.hOutList,'String',{}); catch, end
        setStatusText('Reverted excluded rows.');
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

    function onModeChanged(src,~)
        S = guidata(hFig);
        items = get(src,'String');
        S.mode = items{get(src,'Value')};
        guidata(hFig,S);
        clearPreview();
    end

    function onROIChanged(~,~)
        S = guidata(hFig);
        S.tc_computePSC = logical(get(S.hTC_ComputePSC,'Value'));
        S.tc_baseMin0 = safeNum(get(S.hBase0,'String'), S.tc_baseMin0);
        S.tc_baseMin1 = safeNum(get(S.hBase1,'String'), S.tc_baseMin1);
        S.tc_peakSearchMin0 = safeNum(get(S.hPkS0,'String'), S.tc_peakSearchMin0);
        S.tc_peakSearchMin1 = safeNum(get(S.hPkS1,'String'), S.tc_peakSearchMin1);
        S.tc_plateauMin0 = safeNum(get(S.hPlat0,'String'), S.tc_plateauMin0);
        S.tc_plateauMin1 = safeNum(get(S.hPlat1,'String'), S.tc_plateauMin1);
        S.tc_peakWinMin = safeNum(get(S.hTC_PeakWin,'String'), S.tc_peakWinMin);
        S.tc_trimPct    = safeNum(get(S.hTC_Trim,'String'), S.tc_trimPct);
        mt = get(S.hTC_Metric,'String');
        S.tc_metric = mt{get(S.hTC_Metric,'Value')};
        guidata(hFig,S);
        if isfield(S,'last') && ~isempty(fieldnames(S.last)), updatePreview(); end
    end

    function onStyleChanged(~,~)
        S = guidata(hFig);
        cm = get(S.hColorMode,'String');   S.colorMode = cm{get(S.hColorMode,'Value')};
        sc = get(S.hColorScheme,'String'); S.colorScheme = sc{get(S.hColorScheme,'Value')};
        S.tc_showSEM = logical(get(S.hShowSEM,'Value'));

        S.manualGroupA = getSelectedPopupString(S.hManGroupA);
        S.manualGroupB = getSelectedPopupString(S.hManGroupB);
        S.manualColorA = get(S.hManColorA,'Value');
        S.manualColorB = get(S.hManColorB,'Value');

        guidata(hFig,S);
        if isfield(S,'last') && ~isempty(fieldnames(S.last)), updatePreview(); end
    end

    function onPlotScaleChanged(~,~)
        S = guidata(hFig);

        S.plotTop.auto      = logical(get(S.hTopAuto,'Value'));
        S.plotTop.forceZero = logical(get(S.hTopZero,'Value'));
        S.plotTop.step      = max(0, safeNum(get(S.hTopStep,'String'), S.plotTop.step));
        S.plotTop.ymin      = safeNum(get(S.hTopYmin,'String'), S.plotTop.ymin);
        S.plotTop.ymax      = safeNum(get(S.hTopYmax,'String'), S.plotTop.ymax);

        S.plotBot.auto      = logical(get(S.hBotAuto,'Value'));
        S.plotBot.forceZero = logical(get(S.hBotZero,'Value'));
        S.plotBot.step      = max(0, safeNum(get(S.hBotStep,'String'), S.plotBot.step));
        S.plotBot.ymin      = safeNum(get(S.hBotYmin,'String'), S.plotBot.ymin);
        S.plotBot.ymax      = safeNum(get(S.hBotYmax,'String'), S.plotBot.ymax);

        guidata(hFig,S);
        if isfield(S,'last') && ~isempty(fieldnames(S.last)), updatePreview(); end
    end

    function onYStep(whichBtn)
        S = guidata(hFig);
        switch whichBtn
            case 'TopYminM'
                step = max(0, safeNum(get(S.hTopStep,'String'), S.plotTop.step));
                set(S.hTopYmin,'String',num2str(safeNum(get(S.hTopYmin,'String'),S.plotTop.ymin)-step));
            case 'TopYminP'
                step = max(0, safeNum(get(S.hTopStep,'String'), S.plotTop.step));
                set(S.hTopYmin,'String',num2str(safeNum(get(S.hTopYmin,'String'),S.plotTop.ymin)+step));
            case 'TopYmaxM'
                step = max(0, safeNum(get(S.hTopStep,'String'), S.plotTop.step));
                set(S.hTopYmax,'String',num2str(safeNum(get(S.hTopYmax,'String'),S.plotTop.ymax)-step));
            case 'TopYmaxP'
                step = max(0, safeNum(get(S.hTopStep,'String'), S.plotTop.step));
                set(S.hTopYmax,'String',num2str(safeNum(get(S.hTopYmax,'String'),S.plotTop.ymax)+step));

            case 'BottomYminM'
                step = max(0, safeNum(get(S.hBotStep,'String'), S.plotBot.step));
                set(S.hBotYmin,'String',num2str(safeNum(get(S.hBotYmin,'String'),S.plotBot.ymin)-step));
            case 'BottomYminP'
                step = max(0, safeNum(get(S.hBotStep,'String'), S.plotBot.step));
                set(S.hBotYmin,'String',num2str(safeNum(get(S.hBotYmin,'String'),S.plotBot.ymin)+step));
            case 'BottomYmaxM'
                step = max(0, safeNum(get(S.hBotStep,'String'), S.plotBot.step));
                set(S.hBotYmax,'String',num2str(safeNum(get(S.hBotYmax,'String'),S.plotBot.ymax)-step));
            case 'BottomYmaxP'
                step = max(0, safeNum(get(S.hBotStep,'String'), S.plotBot.step));
                set(S.hBotYmax,'String',num2str(safeNum(get(S.hBotYmax,'String'),S.plotBot.ymax)+step));
        end
        onPlotScaleChanged([],[]);
    end

    function onPSCEdit(src,~,fieldName)
        S = guidata(hFig);
        v = str2double(get(src,'String'));
        if ~isfinite(v), return; end
        S.(fieldName) = v;
        guidata(hFig,S);
    end

    function onMapChanged(~,~)
        S = guidata(hFig);
        items = get(S.hMapSummary,'String');
        S.mapSummary = items{get(S.hMapSummary,'Value')};
        guidata(hFig,S);
    end

    function onStatsChanged(~,~)
        S = guidata(hFig);
        items = get(S.hTest,'String');
        S.testType = items{get(S.hTest,'Value')};
        a = str2double(get(S.hAlpha,'String'));
        if isfinite(a) && a>0 && a<1, S.alpha = a; else, set(S.hAlpha,'String',num2str(S.alpha)); end
        guidata(hFig,S);
    end

    function onOutlierChanged(~,~)
        S = guidata(hFig);
        items = get(S.hOutMethod,'String');
        S.outlierMethod = items{get(S.hOutMethod,'Value')};

        if strcmpi(S.outlierMethod,'MAD robust z-score')
            set(S.hOutParamLbl,'String','Thr (z):');
            v = str2double(get(S.hOutParam,'String'));
            if isfinite(v) && v>0, S.outMADthr=v; else, set(S.hOutParam,'String',num2str(S.outMADthr)); end
        elseif strcmpi(S.outlierMethod,'IQR rule')
            set(S.hOutParamLbl,'String','k (IQR):');
            v = str2double(get(S.hOutParam,'String'));
            if isfinite(v) && v>0, S.outIQRk=v; else, set(S.hOutParam,'String',num2str(S.outIQRk)); end
        end
        guidata(hFig,S);
    end

    function onRun(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        if isempty(S.subj), errordlg('Add subject files first.','Group Analysis'); return; end
        subjActive = getActiveRows(S.subj);
        if isempty(subjActive), errordlg('No active rows (Use=true).','Group Analysis'); return; end

        setStatus(false);
        setStatusText('Running...');
        drawnow;

        try
            if strcmpi(S.mode,'ROI Timecourse')
                R = runROITimecourseAnalysis(S, subjActive);
            else
                R = runPSCMapAnalysis(S, subjActive);
            end
            S = guidata(hFig);
            S.last = R;
            guidata(hFig,S);
            updatePreview();
            try, set(S.hOutList,'String',{}); catch, end
            setStatusText('Done.');
        catch ME
            setStatusText(['ERROR: ' ME.message]);
            errordlg(ME.message,'Group Analysis');
        end
    end

    function onDetectOutliers(~,~)
        S = guidata(hFig);
        if ~isfield(S,'last') || isempty(fieldnames(S.last)) || ~isfield(S.last,'metricVals')
            errordlg('Run ROI Timecourse analysis first.','Outliers'); return;
        end
        if ~strcmpi(S.last.mode,'ROI Timecourse')
            errordlg('Outlier detection applies to ROI Timecourse only.','Outliers'); return;
        end
        onOutlierChanged([],[]);
        S = guidata(hFig);

        [keysOut, info] = detectOutliers(double(S.last.metricVals(:)), S.last.subjTable, S);
        S.outlierKeys = keysOut;
        S.outlierInfo = info;
        guidata(hFig,S);

        set(S.hOutList,'String',S.outlierInfo);
        updatePreview();
        setStatusText(sprintf('Outlier detection: %d outlier(s).', numel(keysOut)));
    end

    function onExcludeOutliers(~,~)
        syncSubjFromTable();
        S = guidata(hFig);
        if isempty(S.outlierKeys)
            errordlg('No outliers detected. Click Detect first.','Exclude outliers'); return;
        end
        keysAll = makeRowKeys(S.subj);
        for i=1:numel(S.outlierKeys)
            hit = find(strcmp(keysAll, S.outlierKeys{i}), 1, 'first');
            if ~isempty(hit)
                S.subj{hit,1} = false;
                S.subj{hit,8} = htmlRed('EXCLUDED (outlier)');
            end
        end
        guidata(hFig,S);
        refreshTable();
        setStatusText('Outliers excluded (Use=false + red Status). RUN again.');
    end

    function outBase = exportStartFolder()
        if exist('Z:\fUS','dir')
            outBase = 'Z:\fUS';
        else
            outBase = S.outDir;
            if isempty(outBase) || ~exist(outBase,'dir'), outBase = pwd; end
        end
    end

    function onExport(~,~)
        S = guidata(hFig);
        if ~isfield(S,'last') || isempty(fieldnames(S.last))
            errordlg('Run analysis first.','Export'); return;
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

        R = S.last; %#ok<NASGU>
        save(fullfile(outFolder,'Results.mat'),'R','-v7.3');

        % UTF-8 CSV export
        try
            if isfield(S.last,'metrics') && isfield(S.last.metrics,'table') && ~isempty(S.last.metrics.table)
                writeCellCSV_UTF8(fullfile(outFolder,'Metrics.csv'), S.last.metrics.table);
            end
        catch
        end

        setStatusText(['Exported: ' outFolder]);
    end

    function onExportPreviewPNG(which)
        S = guidata(hFig);
        if ~isfield(S,'last') || isempty(fieldnames(S.last))
            errordlg('Run analysis first.','Preview export'); return;
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
                f = figure('Visible','off','Color',S.C.axisBg); ax = axes('Parent',f);
                exportOnePreview(ax,1,S,'dark');
                saveas(f, fullfile(outDir, [baseName '_Top.png'])); close(f);
            end
            if which==2 || which==3
                f = figure('Visible','off','Color',S.C.axisBg); ax = axes('Parent',f);
                exportOnePreview(ax,2,S,'dark');
                saveas(f, fullfile(outDir, [baseName '_Bottom.png'])); close(f);
            end
            set(S.hPrevMsg,'String','Saved PNG(s).');
            setStatusText(['Saved preview PNG(s) to: ' outDir]);
        catch ME
            set(S.hPrevMsg,'String',['Export failed: ' ME.message]);
            errordlg(ME.message,'Preview export');
        end
    end

% =========================================================
% Preview rendering
% =========================================================
    function clearPreview()
        cla(S.ax1); cla(S.ax2);
        title(S.ax1,'Top plot','Color','w','FontWeight','bold');
        title(S.ax2,'Bottom plot','Color','w','FontWeight','bold');
        fixAxesInset(S.ax1); fixAxesInset(S.ax2);
    end

    function updatePreview()
        S = guidata(hFig);
        clearPreview();
        if ~isfield(S,'last') || isempty(fieldnames(S.last)), return; end
        R = S.last;

        if strcmpi(R.mode,'PSC Map')
            if ~isempty(R.group)
                imagesc_auto(S.ax1, squeeze2D(R.group(1).map));
                title(S.ax1, ['PSC Map: ' R.group(1).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax1);
            end
            if numel(R.group) >= 2
                imagesc_auto(S.ax2, squeeze2D(R.group(2).map));
                title(S.ax2, ['PSC Map: ' R.group(2).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax2);
            end
            fixAxesInset(S.ax1); fixAxesInset(S.ax2);
            return;
        end

        t = R.tMin(:)';

        % TOP timecourse
        cla(S.ax1); hold(S.ax1,'on');
        set(S.ax1,'Color',S.C.axisBg,'XColor','w','YColor','w','FontSize',S.F.base);

        if isfield(R,'infusion') && numel(R.infusion)==2
            x0=R.infusion(1); x1=R.infusion(2);
            patch(S.ax1,[x0 x1 x1 x0],[-1e9 -1e9 1e9 1e9],[0.8 0.8 0.8],'FaceAlpha',0.10,'EdgeColor','none');
        end

        leg = {};
        allTop = [];
        for g=1:numel(R.group)
            col = R.groupColors.(makeField(R.group(g).name));
            mu  = R.group(g).mean(:)';
            se  = R.group(g).sem(:)';
            if R.showSEM
                shadedLineColored(S.ax1, t, mu, se, col, col);
            else
                plot(S.ax1, t, mu, 'LineWidth',2.4, 'Color',col);
            end
            allTop = [allTop, mu, mu+se, mu-se]; %#ok<AGROW>
            leg{end+1} = sprintf('%s (n=%d)', R.group(g).name, R.group(g).n); %#ok<AGROW>
        end

        grid(S.ax1,'on');
        xlabel(S.ax1,'Time (min)','Color','w');
        ylabel(S.ax1, tern(R.unitsPercent,'Signal change (%)','ROI signal (a.u.)'), 'Color','w');
        title(S.ax1, sprintf('Mean ROI timecourse | baseline: %s', R.baselineZero), 'Color','w','FontWeight','bold');
        legend(S.ax1, leg, 'TextColor','w','Location','northwest','Box','off');

        applyYLim(S.ax1, allTop, R.plotTop);
        fixAxesInset(S.ax1);
        hold(S.ax1,'off');

        % BOTTOM metric scatter
        cla(S.ax2); hold(S.ax2,'on');
        set(S.ax2,'Color',S.C.axisBg,'XColor','w','YColor','w','FontSize',S.F.base);
        grid(S.ax2,'on');

        gNames = R.groupNames;
        metricVals = R.metricVals(:);
        grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,3), 'UniformOutput',false);
        xTicks = 1:numel(gNames);

        allBot = [];
        keysActive = makeRowKeys(R.subjTable);

        for g=1:numel(gNames)
            idxG = strcmpi(grpCol, gNames{g});
            rowsG = find(idxG);
            if isempty(rowsG), continue; end
            col = R.groupColors.(makeField(gNames{g}));

            for rr = rowsG(:)'
                y = metricVals(rr);
                if ~isfinite(y), continue; end
                jitter = (rand-0.5)*0.18;
                xx = xTicks(g)+jitter;

                h = scatter(S.ax2, xx, y, 70, col, 'filled');
                if ~isempty(S.outlierKeys) && any(strcmp(S.outlierKeys, keysActive{rr}))
                    set(h,'MarkerEdgeColor',[1 0.2 0.2],'LineWidth',1.8);
                else
                    set(h,'MarkerEdgeColor',col,'LineWidth',0.8);
                end

                allBot = [allBot; y]; %#ok<AGROW>
            end

            yAll = metricVals(idxG); yAll = yAll(isfinite(yAll));
            if ~isempty(yAll)
                plot(S.ax2,[xTicks(g)-0.25 xTicks(g)+0.25],[mean(yAll) mean(yAll)],'LineWidth',2.8,'Color',col);
            end
        end

        set(S.ax2,'XLim',[0.5 numel(gNames)+0.5], 'XTick',xTicks, 'XTickLabel',gNames);
        ylabel(S.ax2, tern(R.unitsPercent,'Signal change (%)','Metric (a.u.)'), 'Color','w');

        ttl = ['Metric: ' R.metricName];
        if isfield(R,'stats') && isfield(R.stats,'p') && ~isempty(R.stats.p) && isfinite(R.stats.p)
            ttl = sprintf('%s | p=%.4g', ttl, R.stats.p);
        end
        title(S.ax2, ttl, 'Color','w','FontWeight','bold');

        applyYLim(S.ax2, allBot, R.plotBot);
        fixAxesInset(S.ax2);
        hold(S.ax2,'off');
    end

% =========================================================
% UI helpers
% =========================================================
    function updateSelLabel()
        S = guidata(hFig);
        sel = clampSelRows(S.selectedRows, size(S.subj,1));
        if isempty(sel)
            set(S.hSelInfo,'String','Selected: none');
        else
            set(S.hSelInfo,'String',sprintf('Selected: %d row(s)', numel(sel)));
        end
    end

    function syncSubjFromTable()
        S = guidata(hFig);
        try
            dt = get(S.hTable,'Data');
            if iscell(dt), S.subj = dt; end
        catch
        end
        S = sanitizeTable(S);
        guidata(hFig,S);
    end

    function refreshTable()
        S = guidata(hFig);
        S = sanitizeTable(S);

        S.groupList = mergeUniqueStable(S.groupList, uniqueStable(colAsStr(S.subj,3)));
        S.condList  = mergeUniqueStable(S.condList,  uniqueStable(colAsStr(S.subj,4)));

        colFmt = {'logical','char',S.groupList,S.condList,'char','char','char','char'};
        try, set(S.hTable,'ColumnFormat',colFmt); catch, end
        set(S.hTable,'Data',S.subj);
        set(S.hTable,'RowName','numbered');

        set(S.hQuickGroup,'String',S.groupList);
        set(S.hQuickCond,'String',S.condList);

        set(S.hManGroupA,'String',S.groupList);
        set(S.hManGroupB,'String',S.groupList);

        guidata(hFig,S);
        drawnow;
        updateSelLabel();
    end

    function addFileSmart(fp)
        S = guidata(hFig);
        [~,~,ext] = fileparts(fp);
        ext = lower(ext);

        subj = guessSubjectID(fp);
        if isempty(subj), subj = ['S' num2str(size(S.subj,1)+1)]; end

        rowIdx = [];
        if ~isempty(S.subj)
            rowIdx = find(strcmpi(colAsStr(S.subj,2), subj), 1, 'first');
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

        gdef = getSelectedPopupString(S.hQuickGroup);
        cdef = getSelectedPopupString(S.hQuickCond);
        if isempty(gdef), gdef = S.defaultGroup; end
        if isempty(cdef), cdef = S.defaultCond; end

        if isempty(rowIdx)
            newRow = {true, subj, gdef, cdef, '', '', '', ''};
            if get(S.hAutoPair,'Value')==1, newRow{5} = subj; end
            if isROI
                newRow{7} = fp;
                df = findDataMatNearROI(fp);
                if isempty(df), df = subj; end
                newRow{6} = df;
            else
                newRow{6} = fp;
            end
            S.subj(end+1,:) = newRow;
        else
            if isROI
                S.subj{rowIdx,7} = fp;
                if get(S.hAutoPair,'Value')==1 && isempty(strtrimSafe(S.subj{rowIdx,5}))
                    S.subj{rowIdx,5} = subj;
                end
                if isempty(strtrimSafe(S.subj{rowIdx,6}))
                    df = findDataMatNearROI(fp);
                    if isempty(df), df = subj; end
                    S.subj{rowIdx,6} = df;
                end
            else
                S.subj{rowIdx,6} = fp;
            end
        end

        S = sanitizeTable(S);
        guidata(hFig,S);
    end

    function syncUIFromState()
        S = guidata(hFig);
        set(S.hTC_ComputePSC,'Value',double(S.tc_computePSC));
        set(S.hBase0,'String',num2str(S.tc_baseMin0));
        set(S.hBase1,'String',num2str(S.tc_baseMin1));
        set(S.hPkS0,'String',num2str(S.tc_peakSearchMin0));
        set(S.hPkS1,'String',num2str(S.tc_peakSearchMin1));
        set(S.hPlat0,'String',num2str(S.tc_plateauMin0));
        set(S.hPlat1,'String',num2str(S.tc_plateauMin1));
        set(S.hTC_PeakWin,'String',num2str(S.tc_peakWinMin));
        set(S.hTC_Trim,'String',num2str(S.tc_trimPct));
        set(S.hShowSEM,'Value',double(S.tc_showSEM));
        set(S.hOutEdit,'String',S.outDir);

        set(S.hTopAuto,'Value',double(S.plotTop.auto));
        set(S.hTopZero,'Value',double(S.plotTop.forceZero));
        set(S.hTopStep,'String',num2str(S.plotTop.step));
        set(S.hTopYmin,'String',num2str(S.plotTop.ymin));
        set(S.hTopYmax,'String',num2str(S.plotTop.ymax));

        set(S.hBotAuto,'Value',double(S.plotBot.auto));
        set(S.hBotZero,'Value',double(S.plotBot.forceZero));
        set(S.hBotStep,'String',num2str(S.plotBot.step));
        set(S.hBotYmin,'String',num2str(S.plotBot.ymin));
        set(S.hBotYmax,'String',num2str(S.plotBot.ymax));

        setPopupToString(S.hColorMode, S.colorMode);
        setPopupToString(S.hColorScheme, S.colorScheme);
        setPopupToString(S.hManGroupA, S.manualGroupA);
        setPopupToString(S.hManGroupB, S.manualGroupB);
        try, set(S.hManColorA,'Value',S.manualColorA); catch, end
        try, set(S.hManColorB,'Value',S.manualColorB); catch, end
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
        try, set(S.hStatus,'String',txt); catch, end
        drawnow;
    end

    function setStatus(isReady)
        if ~isempty(opt.statusFcn)
            try, opt.statusFcn(logical(isReady)); catch, end
        end
    end

end % END main function


% ======================================================================
% =======================  LOCAL FUNCTIONS  ============================
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
s = regexprep(s,'[^A-Za-z0-9_\-]','_'); % ASCII-only to avoid encoding issues
s = regexprep(s,'_+','_');
s = regexprep(s,'^[\._]+',''); s = regexprep(s,'[\._]+$','');
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
sel = unique(sel(:)'); sel = sel(sel>=1 & sel<=nRows);
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

function S = sanitizeTable(S)
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

function [hAuto,hZero,hStep,hYmin,hYmax,hYminM,hYminP,hYmaxM,hYmaxP] = mkYControlsStepCompact(parent, y0, label, cfg, C, cbEdit, cbStep)
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
    'Callback',@(s,e) cbStep([label 'YminM']));

hYminP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.73 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(s,e) cbStep([label 'YminP']));

uicontrol(parent,'Style','text','String','Ymax:', ...
    'Units','normalized','Position',[0.78 y0 0.06 rowH], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmax = uicontrol(parent,'Style','edit','String',num2str(cfg.ymax), ...
    'Units','normalized','Position',[0.84 y0+0.01 0.07 rowH], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w','Callback',cbEdit);

hYmaxM = uicontrol(parent,'Style','pushbutton','String','-', ...
    'Units','normalized','Position',[0.92 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(s,e) cbStep([label 'YmaxM']));

hYmaxP = uicontrol(parent,'Style','pushbutton','String','+', ...
    'Units','normalized','Position',[0.96 y0+0.01 0.035 rowH], ...
    'BackgroundColor',C.btnSecondary,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@(s,e) cbStep([label 'YmaxP']));
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

function applyYLim(ax, dataVec, plotCfg)
if isempty(dataVec), return; end
dataVec = dataVec(isfinite(dataVec));
if isempty(dataVec), return; end
if plotCfg.auto
    lo = min(dataVec); hi = max(dataVec);
    if plotCfg.forceZero, lo = 0; end
    if lo==hi
        lo = lo-1; hi = hi+1;
    else
        pad = 0.06*(hi-lo);
        lo = lo - pad; hi = hi + pad;
        if plotCfg.forceZero, lo = 0; end
    end
    ylim(ax,[lo hi]);
else
    lo = plotCfg.ymin; hi = plotCfg.ymax;
    if plotCfg.forceZero, lo = 0; end
    if isfinite(lo) && isfinite(hi) && lo<hi, ylim(ax,[lo hi]); end
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
            fpData = fn; return;
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

function imagesc_auto(ax, A)
A = double(A);
A(~isfinite(A)) = 0;
imagesc(ax, A);
axis(ax,'image'); axis(ax,'off');
set(ax,'XColor','w','YColor','w');
end

function Y = squeeze2D(X)
if ndims(X)==3 && size(X,3)>1
    z = round(size(X,3)/2);
    Y = X(:,:,z);
else
    Y = X;
end
end

function shadedLineColored(ax, x, y, e, lineColor, fillColor)
x = x(:)'; y = y(:)'; e = e(:)';
up = y+e; dn = y-e;
patch(ax, [x fliplr(x)], [up fliplr(dn)], fillColor, 'FaceAlpha',0.20, 'EdgeColor','none');
plot(ax, x, y, 'LineWidth',2.4, 'Color',lineColor);
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
fid = fopen(fn,'w','n','UTF-8');
if fid<0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
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

% ===================== BACKEND ANALYSIS =====================
% (kept minimal but functional; same behavior as before)

function mu = nanmean_local(X, dim)
try
    mu = mean(X, dim, 'omitnan');
catch
    n = sum(isfinite(X),dim);
    X2 = X; X2(~isfinite(X2)) = 0;
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
ok=false; tMin=[]; psc=[];
if nargin<1 || isempty(fname), return; end
fname = strtrim(char(fname));
if exist(fname,'file')~=2, return; end
fid = fopen(fname,'r');
if fid<0, return; end
cln = onCleanup(@() fclose(fid)); %#ok<NASGU>

inTable=false;
while true
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end
    if ln(1)=='#'
        if ~isempty(strfind(lower(ln),'# columns:')) && ~isempty(strfind(lower(ln),'psc'))
            inTable=true;
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
if numel(tMin) >= 5 && numel(psc)==numel(tMin), ok=true; end
end

function X = applyBaselineZero(X, tMin, b0, b1, mode)
mode = strtrimSafe(mode);
if strcmpi(mode,'None'), return; end
baseIdx = (tMin>=b0) & (tMin<=b1);
if ~any(baseIdx), return; end
for i=1:size(X,1)
    try
        b = mean(X(i,baseIdx),2,'omitnan');
    catch
        bb = X(i,baseIdx); bb = bb(isfinite(bb));
        if isempty(bb), b=0; else, b=mean(bb); end
    end
    if ~isfinite(b), b=0; end
    X(i,:) = X(i,:) - b;
end
end

function [tcRaw, tMin] = extractROITC_legacyMat(fp)
L = load(fp);
if isfield(L,'roiTC'), tc = L.roiTC;
elseif isfield(L,'TC'), tc = L.TC;
else, error('ROI mat must contain roiTC or TC: %s', fp);
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
Y = sz(1); X = sz(2);
if d==4, Z = sz(3); T = sz(4); else, Z=1; T=sz(3); end

roi = double(roi);
if size(roi,2)==1
    lin = roi(:,1); lin = lin(lin>=1);
    if d==3
        lin = lin(lin<=Y*X);
        [r,c] = ind2sub([Y X], lin); z = ones(size(r));
    else
        lin = lin(lin<=Y*X*Z);
        [r,c,z] = ind2sub([Y X Z], lin);
    end
elseif size(roi,2)==2
    r=roi(:,1); c=roi(:,2); z=ones(size(r));
else
    r=roi(:,1); c=roi(:,2); z=roi(:,3);
end

r=round(r); c=round(c); z=round(z);
keep = (r>=1 & r<=Y & c>=1 & c<=X & z>=1 & z<=Z);
r=r(keep); c=c(keep); z=z(keep);
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

function [tcRaw, tMin] = extractROITC_fromDataAndROI(dataFile, roiFile)
D = loadPipelineStruct(dataFile);
if ~isfield(D,'I') || isempty(D.I), error('DATA file missing I: %s', dataFile); end
if ~isfield(D,'TR') || isempty(D.TR), error('DATA file missing TR: %s', dataFile); end
I = D.I; TR = double(D.TR);
roi = readROITxt(roiFile);
tcRaw = roiMeanTimecourse(I, roi);
T = numel(tcRaw);
tMin = (0:(T-1))*(TR/60);
end

function m = trimmedMean(x, trimPct)
x = x(:); x = x(isfinite(x));
if isempty(x), m=NaN; return; end
x = sort(x,'ascend');
n = numel(x);
tp = max(0, min(49, round(trimPct)));
k = floor((tp/100)*n/2);
i0 = 1+k; i1 = n-k;
if i1 < i0, m = mean(x); else, m = mean(x(i0:i1)); end
end

function pv = robustPeak(y, tMin, s0, s1, winMin, trimPct)
y = double(y(:)'); tMin = double(tMin(:)');
pv = NaN;
idxAll = find(tMin>=s0 & tMin<=s1);
if numel(idxAll)<1, return; end
dt = median(diff(tMin)); if ~isfinite(dt) || dt<=0, dt=0.1; end
w = max(1, round(winMin/dt));
iStart = idxAll(1); iEnd = idxAll(end);
best=-Inf;
for i=iStart:(iEnd-w+1)
    j=i+w-1;
    seg = y(i:j); seg = seg(isfinite(seg));
    if isempty(seg), continue; end
    val = trimmedMean(seg, trimPct);
    if val > best, best=val; end
end
if isfinite(best), pv=best; end
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
        if ~isempty(gA) && strcmpi(nm,gA), col = colA;
        elseif ~isempty(gB) && strcmpi(nm,gB), col = colB;
        else, col = base(i,:);
        end
        colors.(makeField(nm)) = col;
    end
    return;
end

scheme = strtrimSafe(S.colorScheme);
if strcmpi(scheme,'PACAP/Vehicle')
    for i=1:numel(gNames)
        nmU = upper(strtrimSafe(gNames{i}));
        if ~isempty(strfind(nmU,'PACAP'))
            col = [0.20 0.65 0.90];
        elseif ~isempty(strfind(nmU,'VEH')) || ~isempty(strfind(nmU,'CONTROL')) || ~isempty(strfind(nmU,'VEHICLE'))
            col = [0.80 0.80 0.80];
        else
            base = lines(numel(gNames));
            col = base(i,:);
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
stats = struct('type',S.testType,'alpha',S.alpha,'p',[],'t',[],'F',[],'df',[],'desc','');
testType = strtrimSafe(S.testType);
if strcmpi(testType,'None')
    stats.desc = 'No test.';
    return;
end
gNames = uniqueStable(grpCol);
if strcmpi(testType,'One-sample t-test (vs 0)')
    [t,p,df] = oneSampleT_vec(metricVals);
    stats.t=t; stats.p=p; stats.df=df; stats.desc='One-sample t-test vs 0';
elseif strcmpi(testType,'Two-sample t-test (Welch)')
    if numel(gNames)<2, error('Need >=2 groups.'); end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = welchT_vec(a,b);
    stats.t=t; stats.p=p; stats.df=df; stats.desc=[gNames{1} ' vs ' gNames{2}];
else
    [F,p,df] = oneWayANOVA_metric(metricVals, grpCol);
    stats.F=F; stats.p=p; stats.df=df; stats.desc='One-way ANOVA';
end
end

function [t,p,df] = oneSampleT_vec(x)
x = x(:); x = x(isfinite(x));
n = numel(x);
if n < 2, t=NaN; p=NaN; df=max(0,n-1); return; end
mu = mean(x); sd = std(x,0); se = sd/sqrt(n);
t = mu / max(eps,se);
df = n-1;
if exist('tcdf','file')==2, p = 2*tcdf(-abs(t),df); else, p = NaN; end
end

function [t,p,df] = welchT_vec(a,b)
a = a(:); b = b(:);
a = a(isfinite(a)); b = b(isfinite(b));
n1=numel(a); n2=numel(b);
if n1<2 || n2<2, t=NaN; p=NaN; df=NaN; return; end
m1=mean(a); m2=mean(b);
v1=var(a,0); v2=var(b,0);
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
g = cellfun(@(s) strtrimSafe(s), g, 'UniformOutput',false);
u = uniqueStable(g);
k = numel(u);
n = numel(x);
if k < 2 || n < 3, F=NaN; p=NaN; df=[k-1 n-k]; return; end
grand = mean(x);
SSb=0; SSw=0;
for i=1:k
    xi = x(strcmpi(g,u{i}));
    if isempty(xi), continue; end
    mi = mean(xi);
    SSb = SSb + numel(xi)*(mi-grand)^2;
    SSw = SSw + sum((xi-mi).^2);
end
df1=k-1; df2=n-k;
MSb = SSb / max(1,df1);
MSw = SSw / max(1,df2);
F = MSb / max(eps,MSw);
df = [df1 df2];
if exist('fcdf','file')==2, p = 1 - fcdf(F,df1,df2); else, p = NaN; end
end

function [keysOut, info] = detectOutliers(metricVals, subjTable, S)
keysOut = {}; info = {};
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
elseif strcmpi(method,'IQR rule')
    k = S.outIQRk;
    xv = x(valid);
    q1 = prctile(xv,25); q3 = prctile(xv,75);
    iqrV = q3-q1;
    lo = q1 - k*iqrV;
    hi = q3 + k*iqrV;
    idxOut = find(valid & (x<lo | x>hi));
else
    return;
end

keysAll = makeRowKeys(subjTable);
for ii = idxOut(:)'
    sid = strtrimSafe(subjTable{ii,2});
    grp = strtrimSafe(subjTable{ii,3});
    cd  = strtrimSafe(subjTable{ii,4});
    info{end+1,1} = sprintf('%s | %s | %s | %.4g', sid, grp, cd, x(ii)); %#ok<AGROW>
    keysOut{end+1,1} = keysAll{ii}; %#ok<AGROW>
end
end

function R = runROITimecourseAnalysis(S, subjActive)
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

    [okTxt, tMin, psc] = tryReadSCMroiExportTxt(roiFile);
    if okTxt
        tcAll{i} = double(psc(:))';
        tAll{i}  = double(tMin(:))';
        isPSCInput(i) = true;
    else
        if isempty(roiFile) || exist(roiFile,'file')~=2
            error('Row %d: ROIFile missing or not found.', i);
        end
        [~,~,ext] = fileparts(roiFile);
        ext = lower(ext);
        if strcmp(ext,'.mat')
            [tcRaw, tMin2] = extractROITC_legacyMat(roiFile);
            tcAll{i} = tcRaw(:)'; tAll{i} = tMin2(:)';
        else
            if isempty(dataFile) || exist(dataFile,'file')~=2
                error('Row %d: DATA .mat required (ROI is not SCM PSC-table txt).', i);
            end
            [tcRaw, tMin2] = extractROITC_fromDataAndROI(dataFile, roiFile);
            tcAll{i} = tcRaw(:)'; tAll{i} = tMin2(:)';
        end
    end
end

t0 = max(cellfun(@(x) x(1), tAll));
t1 = min(cellfun(@(x) x(end), tAll));
dt = median(diff(tAll{1}));
if ~isfinite(dt) || dt<=0, dt = 0.1; end
if t1<=t0, error('Time axes do not overlap across subjects.'); end
tCommon = t0:dt:t1;

Xraw = nan(N,numel(tCommon));
for i=1:N
    Xraw(i,:) = interp1(tAll{i}(:), tcAll{i}(:), tCommon(:), 'linear','extrap').';
end

X = Xraw;
if S.tc_computePSC
    baseIdx = (tCommon>=S.tc_baseMin0) & (tCommon<=S.tc_baseMin1);
    if ~any(baseIdx), error('Baseline window has no samples.'); end
    for i=1:N
        if isPSCInput(i), continue; end
        b = nanmean_local(Xraw(i,baseIdx),2);
        if ~isfinite(b) || b==0, b=eps; end
        X(i,:) = 100*(Xraw(i,:)-b)./b;
    end
end

unitsPercent = any(isPSCInput) || S.tc_computePSC;
X = applyBaselineZero(X, tCommon, S.tc_baseMin0, S.tc_baseMin1, S.tc_baselineZero);

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
R.groupColors = groupColors;
R.infusion = [S.tc_injMin0 S.tc_injMin1];
R.unitsPercent = unitsPercent;
R.metricName = metricName;
R.metricVals = metricVals;
R.stats = stats;
R.metrics = struct('table',{Tcell});
R.subjTable = subjActive;
R.plotTop = S.plotTop;
R.plotBot = S.plotBot;
R.showSEM = S.tc_showSEM;
R.baselineZero = S.tc_baselineZero;
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

function M = extractPSCMap(fp, b0, b1, s0, s1)
D = loadPipelineStruct(fp);
if ~isfield(D,'TR') || isempty(D.TR), error('Missing TR in %s', fp); end
if ~isfield(D,'I')  || isempty(D.I),  error('Missing I in %s', fp); end
I = D.I; TR = double(D.TR);
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

function R = runPSCMapAnalysis(S, subjActive)
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
    maps{i} = extractPSCMap(fp, S.baseStart, S.baseEnd, S.sigStart, S.sigEnd);
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
end

function exportOnePreview(ax, which, S, style)
if nargin<4, style='light'; end
R = S.last;
cla(ax);
isDark = strcmpi(style,'dark');
if isDark
    set(ax,'Color',S.C.axisBg,'XColor','w','YColor','w');
else
    set(ax,'Color','w','XColor','k','YColor','k');
end

if strcmpi(R.mode,'PSC Map')
    if which==1
        imagesc(ax, squeeze2D(R.group(1).map)); axis(ax,'image'); axis(ax,'off'); colorbar(ax);
        title(ax,R.group(1).name,'Color', tern(isDark,'w','k'));
    else
        if numel(R.group)>=2
            imagesc(ax, squeeze2D(R.group(2).map)); axis(ax,'image'); axis(ax,'off'); colorbar(ax);
            title(ax,R.group(2).name,'Color', tern(isDark,'w','k'));
        end
    end
    return;
end

t = R.tMin(:)';
if which==1
    hold(ax,'on');
    for g=1:numel(R.group)
        col = R.groupColors.(makeField(R.group(g).name));
        mu  = R.group(g).mean(:)';
        se  = R.group(g).sem(:)';
        if R.showSEM, shadedLineColored(ax,t,mu,se,col,col);
        else, plot(ax,t,mu,'LineWidth',2.2,'Color',col);
        end
    end
    grid(ax,'on');
    xlabel(ax,'Time (min)','Color',tern(isDark,'w','k'));
    ylabel(ax, tern(R.unitsPercent,'Signal change (%)','ROI signal'), 'Color',tern(isDark,'w','k'));
    title(ax,'Mean ROI timecourse','Color',tern(isDark,'w','k'));
    hold(ax,'off');
else
    gNames = R.groupNames;
    metricVals = R.metricVals(:);
    grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,3), 'UniformOutput',false);
    xTicks = 1:numel(gNames);
    hold(ax,'on');
    for g=1:numel(gNames)
        idx = strcmpi(grpCol,gNames{g});
        y = metricVals(idx); y = y(isfinite(y));
        if isempty(y), continue; end
        col = R.groupColors.(makeField(gNames{g}));
        jitter = (rand(size(y))-0.5)*0.18;
        scatter(ax,xTicks(g)+jitter,y,60,col,'filled');
        plot(ax,[xTicks(g)-0.25 xTicks(g)+0.25],[mean(y) mean(y)],'LineWidth',2.5,'Color',col);
    end
    set(ax,'XLim',[0.5 numel(gNames)+0.5],'XTick',xTicks,'XTickLabel',gNames);
    ylabel(ax,'Metric','Color',tern(isDark,'w','k'));
    title(ax,['Metric: ' R.metricName],'Color',tern(isDark,'w','k'));
    grid(ax,'on');
    hold(ax,'off');
end
end