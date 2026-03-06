function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m  (MATLAB 2017b compatible)
% =========================================================
% CLEAN / MODERN DARK GUI (tabs) + bigger fonts + fixed y-axis controls
%
% FIXES (your issues):
%  1) Removes the "attempt to add hTopAuto to a static workspace" error:
%     -> NO assignin(), NO caller-workspace tricks. We store handles in S only.
%  2) Tabs are NOT empty anymore:
%     -> ROI Timecourse tab, PSC Maps tab, Stats tab, Preview tab all rebuilt.
%  3) Keeps bigger font / nicer sizes you liked.
%  4) Preview axis labels not cut off (larger margins + LooseInset).
%
% Subject table columns:
%   Subject | Group | Condition | PairID | DataFile | ROIFile
%
% ROI Timecourse mode:
%   - If ROIFile is SCM_gui exported PSC txt (has "# columns: time_sec time_min PSC"):
%       uses PSC directly -> DATA .mat NOT required.
%   - If ROIFile is coordinate txt -> DATA .mat required to extract ROI signal.
%   - If ROIFile is .mat containing roiTC/TC -> uses that as ROI timecourse.
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

% -------------------- Theme + Fonts ----------------------
C.bg     = [0.06 0.06 0.06];
C.panel  = [0.10 0.10 0.10];
C.panel2 = [0.08 0.08 0.08];
C.txt    = [0.95 0.95 0.95];
C.muted  = [0.70 0.80 0.90];
C.accent = [0.25 0.70 0.55];
C.warn   = [0.90 0.35 0.25];
C.btn    = [0.18 0.18 0.18];
C.editBg = [0.14 0.14 0.14];
C.axisBg = [0.00 0.00 0.00];

F.name   = 'Arial';
F.base   = 13;
F.small  = 12;
F.big    = 15;
F.table  = 12;

% -------------------- Figure -----------------------------
hFig = figure('Name','fUSI Studio — Group Analysis', ...
    'Color',C.bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[120 60 1860 980], ...
    'CloseRequestFcn', @closeMe);

% Global defaults -> bigger fonts everywhere
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

S.subj = cell(0,6);    % Subject | Group | Condition | PairID | DataFile | ROIFile
S.selectedRows = [];
S.isClosing = false;

S.last = struct();
S.mode = 'ROI Timecourse'; % default mode

% PSC map defaults (sec)
S.baseStart = 0;  S.baseEnd = 10;
S.sigStart  = 10; S.sigEnd  = 30;
S.mapSummary = 'Mean';

% ROI defaults (minutes)
S.tc_computePSC = false;     % default OFF (SCM txt often already PSC)
S.tc_baseMin0   = 0;  S.tc_baseMin1 = 10;
S.tc_injMin0    = 10; S.tc_injMin1  = 20;      % shading
S.tc_plateauMin0 = 30; S.tc_plateauMin1 = 40;
S.tc_peakSearchMin0 = 10; S.tc_peakSearchMin1 = 20;
S.tc_peakWinMin = 3;
S.tc_trimPct    = 10;
S.tc_peakMethod = 'Window trimmed mean';
S.tc_metric     = 'Robust Peak';
S.tc_lowerPlot  = 'Metric scatter';
S.tc_baselineZero = 'Subtract baseline mean';
S.tc_showSEM = true;

S.tc_colorScheme = 'PACAP/Vehicle'; % PACAP/Vehicle | Blue/Red | Purple/Green | Gray/Orange | Distinct

% Plot scaling
S.plotTop = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150);
S.plotBot = struct('auto',true,'forceZero',true,'ymin',0,'ymax',150);

% Stats
S.testType = 'None';
S.alpha = 0.05;

% Output folder
S.outDir = defaultOutDir(opt);

% -------------------- Layout panels ----------------------
leftW = 0.42;

pLeft = uipanel(hFig,'Units','normalized','Position',[0.02 0.05 leftW 0.93], ...
    'Title','Subjects / Groups', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',F.big,'FontWeight','bold');

pRight = uipanel(hFig,'Units','normalized','Position',[0.02+leftW+0.02 0.05 0.96-(0.02+leftW+0.02) 0.93], ...
    'Title','Analysis', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',F.big,'FontWeight','bold');

% -------------------- Subject table -----------------------
colNames = {'Subject','Group','Condition','PairID','DataFile','ROIFile'};
colEdit  = [true true true true false false];

S.hTable = uitable(pLeft, ...
    'Units','normalized', ...
    'Position',[0.03 0.33 0.94 0.64], ...
    'Data',S.subj, ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'RowName',[], ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',C.txt, ...
    'FontName','Consolas', ...
    'FontSize',F.table, ...
    'CellSelectionCallback', @onCellSelect);

% Buttons
S.hAddFiles = mkBtn(pLeft,'Add Files (DATA/ROI)',[0.03 0.26 0.30 0.06],C.btn,@onAddFiles);
S.hAddFolder= mkBtn(pLeft,'Add Folder (scan)',    [0.35 0.26 0.30 0.06],C.btn,@onAddFolder);
S.hRemove   = mkBtn(pLeft,'Remove Selected',      [0.67 0.26 0.30 0.06],C.warn,@onRemoveSelected);

S.hSetData  = mkBtn(pLeft,'Set DATA for selected',[0.03 0.20 0.46 0.055],[0.25 0.55 0.95],@onSetDataSelected);
S.hSetROI   = mkBtn(pLeft,'Set ROI for selected', [0.51 0.20 0.46 0.055],[0.75 0.35 0.80],@onSetROISelected);

S.hSaveList = mkBtn(pLeft,'Save Subject List',    [0.03 0.135 0.46 0.055],[0.20 0.55 0.95],@onSaveList);
S.hLoadList = mkBtn(pLeft,'Load Subject List',    [0.51 0.135 0.46 0.055],[0.15 0.65 0.55],@onLoadList);

uicontrol(pLeft,'Style','text','String','Output folder:', ...
    'Units','normalized','Position',[0.03 0.085 0.25 0.04], ...
    'BackgroundColor',C.panel,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',F.base);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.28 0.085 0.54 0.045], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',F.base, ...
    'Callback',@onOutEdit);

S.hOutBrowse = mkBtn(pLeft,'Browse',[0.84 0.085 0.13 0.045],C.btn,@onBrowseOut);

S.hHint = uicontrol(pLeft,'Style','text', ...
    'String','Tip: SCM ROI txt already contains PSC. DATA .mat only needed if ROI txt is coordinates.', ...
    'Units','normalized','Position',[0.03 0.02 0.94 0.055], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',F.small);

% -------------------- Tabs -------------------------------
S.tabGroup = uitabgroup(pRight,'Units','normalized','Position',[0.02 0.02 0.96 0.96]);
try, set(S.tabGroup,'BackgroundColor',C.panel); catch, end

S.tabROI   = uitab(S.tabGroup,'Title','ROI Timecourse');
S.tabMAP   = uitab(S.tabGroup,'Title','PSC Maps');
S.tabSTATS = uitab(S.tabGroup,'Title','Stats');
S.tabPREV  = uitab(S.tabGroup,'Title','Preview');

% Make tab page area dark (tab strip may remain OS-themed in 2017b)
try, set(S.tabROI,  'BackgroundColor',C.bg); catch, end
try, set(S.tabMAP,  'BackgroundColor',C.bg); catch, end
try, set(S.tabSTATS,'BackgroundColor',C.bg); catch, end
try, set(S.tabPREV, 'BackgroundColor',C.bg); catch, end

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

pROI = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.50 0.96 0.40], ...
    'Title','ROI settings', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hTC_ComputePSC = uicontrol(pROI,'Style','checkbox', ...
    'String','Compute %SC from raw using baseline (ignored if ROI txt already PSC)', ...
    'Units','normalized','Position',[0.02 0.88 0.96 0.10], ...
    'Value', double(S.tc_computePSC), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

% Pair edits (return handles)
[S.hBase0,S.hBase1] = addPairEditsDark(pROI,0.76,'Baseline (min):',S.tc_baseMin0,S.tc_baseMin1,C,@onROIChanged);
[S.hInj0,S.hInj1]   = addPairEditsDark(pROI,0.63,'Infusion shade (min):',S.tc_injMin0,S.tc_injMin1,C,@onROIChanged);
[S.hPlat0,S.hPlat1] = addPairEditsDark(pROI,0.50,'Plateau (min):',S.tc_plateauMin0,S.tc_plateauMin1,C,@onROIChanged);
[S.hPkS0,S.hPkS1]   = addPairEditsDark(pROI,0.37,'Peak search (min):',S.tc_peakSearchMin0,S.tc_peakSearchMin1,C,@onROIChanged);

% Peak win + trim
uicontrol(pROI,'Style','text','String','Peak avg win (min):', ...
    'Units','normalized','Position',[0.02 0.24 0.25 0.09], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_PeakWin = uicontrol(pROI,'Style','edit','String',num2str(S.tc_peakWinMin), ...
    'Units','normalized','Position',[0.27 0.24 0.10 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Trim %:', ...
    'Units','normalized','Position',[0.40 0.24 0.10 0.09], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_Trim = uicontrol(pROI,'Style','edit','String',num2str(S.tc_trimPct), ...
    'Units','normalized','Position',[0.50 0.24 0.08 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

% Peak method / metric / lower plot
uicontrol(pROI,'Style','text','String','Peak method:', ...
    'Units','normalized','Position',[0.02 0.11 0.18 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_PeakMethod = uicontrol(pROI,'Style','popupmenu', ...
    'String',{'Single-point max','Window mean','Window trimmed mean','Window median'}, ...
    'Units','normalized','Position',[0.20 0.12 0.22 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Metric:', ...
    'Units','normalized','Position',[0.44 0.11 0.10 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_Metric = uicontrol(pROI,'Style','popupmenu', ...
    'String',{'Plateau','Robust Peak'}, ...
    'Units','normalized','Position',[0.54 0.12 0.16 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pROI,'Style','text','String','Lower plot:', ...
    'Units','normalized','Position',[0.72 0.11 0.14 0.10], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_LowerPlot = uicontrol(pROI,'Style','popupmenu', ...
    'String',{'Metric scatter','Peak window view'}, ...
    'Units','normalized','Position',[0.86 0.12 0.12 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

% Style panel
pStyle = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.30 0.96 0.18], ...
    'Title','Display style', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStyle,'Style','text','String','Color scheme:', ...
    'Units','normalized','Position',[0.02 0.55 0.18 0.35], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hColorScheme = uicontrol(pStyle,'Style','popupmenu', ...
    'String',{'PACAP/Vehicle','Blue/Red','Purple/Green','Gray/Orange','Distinct'}, ...
    'Units','normalized','Position',[0.20 0.58 0.28 0.35], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

uicontrol(pStyle,'Style','text','String','Baseline re-zero:', ...
    'Units','normalized','Position',[0.52 0.55 0.18 0.35], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTC_BaseZero = uicontrol(pStyle,'Style','popupmenu', ...
    'String',{'None','Subtract baseline mean','Subtract first point'}, ...
    'Units','normalized','Position',[0.70 0.58 0.28 0.35], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

S.hShowSEM = uicontrol(pStyle,'Style','checkbox','String','Show SEM shading', ...
    'Units','normalized','Position',[0.02 0.12 0.30 0.30], ...
    'Value', double(S.tc_showSEM), ...
    'BackgroundColor',bg2,'ForegroundColor','w', ...
    'Callback',@onROIChanged);

% Y scaling panel
pY = uipanel(S.tabROI,'Units','normalized','Position',[0.02 0.02 0.96 0.26], ...
    'Title','Y-axis scaling (Top=Timecourse, Bottom=Metric/Peak view)', ...
    'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

% Top y controls
[S.hTopAuto,S.hTopZero,S.hTopYmin,S.hTopYmax] = mkYControls(pY,0.56,'Top',S.plotTop,C,@onPlotScaleChanged);
% Bottom y controls
[S.hBotAuto,S.hBotZero,S.hBotYmin,S.hBotYmax] = mkYControls(pY,0.10,'Bottom',S.plotBot,C,@onPlotScaleChanged);

% -------------------- PSC MAP TAB ------------------------
pMap = uipanel(S.tabMAP,'Units','normalized','Position',[0.02 0.55 0.96 0.43], ...
    'Title','PSC map windows (seconds)', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hBaseStart = makeWinRowDark(pMap,0.70,'Baseline start',num2str(S.baseStart),@onPSCEdit,'baseStart',C);
S.hBaseEnd   = makeWinRowDark(pMap,0.48,'Baseline end',  num2str(S.baseEnd),  @onPSCEdit,'baseEnd',C);
S.hSigStart  = makeWinRowDark(pMap,0.26,'Signal start',  num2str(S.sigStart), @onPSCEdit,'sigStart',C);
S.hSigEnd    = makeWinRowDark(pMap,0.04,'Signal end',    num2str(S.sigEnd),   @onPSCEdit,'sigEnd',C);

uicontrol(S.tabMAP,'Style','text','String','Summary (per group):', ...
    'Units','normalized','Position',[0.04 0.45 0.25 0.05], ...
    'BackgroundColor',C.bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hMapSummary = uicontrol(S.tabMAP,'Style','popupmenu', ...
    'String',{'Mean','Median'}, ...
    'Units','normalized','Position',[0.28 0.44 0.20 0.06], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onMapChanged);

uicontrol(S.tabMAP,'Style','text','String','(Map preview will show mid-slice if 3D.)', ...
    'Units','normalized','Position',[0.04 0.38 0.80 0.04], ...
    'BackgroundColor',C.bg,'ForegroundColor',C.muted,'HorizontalAlignment','left');

% -------------------- STATS TAB --------------------------
pStats = uipanel(S.tabSTATS,'Units','normalized','Position',[0.02 0.62 0.96 0.36], ...
    'Title','Metric statistics', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

uicontrol(pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.02 0.62 0.12 0.30], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hTest = uicontrol(pStats,'Style','popupmenu', ...
    'String',{'None','One-sample (vs 0)','Two-sample (GroupA vs GroupB)','Paired (CondA vs CondB)','One-way ANOVA (groups)'}, ...
    'Units','normalized','Position',[0.14 0.64 0.60 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onStatsChanged);

uicontrol(pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.77 0.62 0.10 0.30], ...
    'BackgroundColor',bg2,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

S.hAlpha = uicontrol(pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.86 0.64 0.12 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',@onStatsChanged);

pRun = uipanel(S.tabSTATS,'Units','normalized','Position',[0.02 0.02 0.96 0.56], ...
    'Title','Run / Export', 'BackgroundColor',bg2,'ForegroundColor','w','FontWeight','bold');

S.hRun = mkBtn(pRun,'RUN ANALYSIS',[0.02 0.62 0.30 0.30],C.accent,@onRun);
S.hExport = mkBtn(pRun,'EXPORT RESULTS',[0.34 0.62 0.30 0.30],[0.30 0.50 0.95],@onExport);

S.hStatus = uicontrol(pRun,'Style','text','String','Ready.', ...
    'Units','normalized','Position',[0.02 0.10 0.96 0.42], ...
    'BackgroundColor',bg2,'ForegroundColor',C.muted,'HorizontalAlignment','left', ...
    'FontSize',F.small);

% -------------------- PREVIEW TAB ------------------------
S.ax1 = axes('Parent',S.tabPREV,'Units','normalized','Position',[0.08 0.56 0.88 0.38], ...
    'Color',C.axisBg, 'XColor','w','YColor','w');
title(S.ax1,'Top plot','Color','w','FontWeight','bold');

S.ax2 = axes('Parent',S.tabPREV,'Units','normalized','Position',[0.08 0.10 0.88 0.38], ...
    'Color',C.axisBg, 'XColor','w','YColor','w');
title(S.ax2,'Bottom plot','Color','w','FontWeight','bold');

fixAxesInset(S.ax1);
fixAxesInset(S.ax2);

% Store + initial UI state
guidata(hFig,S);
syncUIFromState();
clearPreview();
setStatus(false);
logMsg('Group Analysis GUI ready.');

% =========================================================
% Callbacks
% =========================================================
    function closeMe(src,~)
        S = guidata(src);
        if isempty(S), delete(src); return; end
        if isfield(S,'isClosing') && S.isClosing, delete(src); return; end
        S.isClosing = true; guidata(src,S);

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
        items = get(src,'String');
        S.mode = items{get(src,'Value')};
        guidata(hFig,S);

        if strcmpi(S.mode,'ROI Timecourse')
            set(S.tabGroup,'SelectedTab',S.tabROI);
        else
            set(S.tabGroup,'SelectedTab',S.tabMAP);
        end
        clearPreview();
    end

    function onROIChanged(~,~)
        S = guidata(hFig);

        S.tc_computePSC = logical(get(S.hTC_ComputePSC,'Value'));

        S.tc_baseMin0 = safeNum(get(S.hBase0,'String'), S.tc_baseMin0);
        S.tc_baseMin1 = safeNum(get(S.hBase1,'String'), S.tc_baseMin1);
        S.tc_injMin0  = safeNum(get(S.hInj0,'String'),  S.tc_injMin0);
        S.tc_injMin1  = safeNum(get(S.hInj1,'String'),  S.tc_injMin1);
        S.tc_plateauMin0 = safeNum(get(S.hPlat0,'String'), S.tc_plateauMin0);
        S.tc_plateauMin1 = safeNum(get(S.hPlat1,'String'), S.tc_plateauMin1);
        S.tc_peakSearchMin0 = safeNum(get(S.hPkS0,'String'), S.tc_peakSearchMin0);
        S.tc_peakSearchMin1 = safeNum(get(S.hPkS1,'String'), S.tc_peakSearchMin1);

        S.tc_peakWinMin = safeNum(get(S.hTC_PeakWin,'String'), S.tc_peakWinMin);
        S.tc_trimPct    = safeNum(get(S.hTC_Trim,'String'), S.tc_trimPct);

        pm = get(S.hTC_PeakMethod,'String'); S.tc_peakMethod = pm{get(S.hTC_PeakMethod,'Value')};
        mt = get(S.hTC_Metric,'String');     S.tc_metric = mt{get(S.hTC_Metric,'Value')};
        lp = get(S.hTC_LowerPlot,'String');  S.tc_lowerPlot = lp{get(S.hTC_LowerPlot,'Value')};

        bz = get(S.hTC_BaseZero,'String');   S.tc_baselineZero = bz{get(S.hTC_BaseZero,'Value')};
        cs = get(S.hColorScheme,'String');   S.tc_colorScheme = cs{get(S.hColorScheme,'Value')};
        S.tc_showSEM = logical(get(S.hShowSEM,'Value'));

        guidata(hFig,S);

        if isfield(S,'last') && ~isempty(fieldnames(S.last))
            updatePreview();
        end
    end

    function onPlotScaleChanged(~,~)
        S = guidata(hFig);

        S.plotTop.auto      = logical(get(S.hTopAuto,'Value'));
        S.plotTop.forceZero = logical(get(S.hTopZero,'Value'));
        S.plotTop.ymin      = safeNum(get(S.hTopYmin,'String'), S.plotTop.ymin);
        S.plotTop.ymax      = safeNum(get(S.hTopYmax,'String'), S.plotTop.ymax);

        S.plotBot.auto      = logical(get(S.hBotAuto,'Value'));
        S.plotBot.forceZero = logical(get(S.hBotZero,'Value'));
        S.plotBot.ymin      = safeNum(get(S.hBotYmin,'String'), S.plotBot.ymin);
        S.plotBot.ymax      = safeNum(get(S.hBotYmax,'String'), S.plotBot.ymax);

        guidata(hFig,S);

        if isfield(S,'last') && ~isempty(fieldnames(S.last))
            updatePreview();
        end
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
        if isfinite(a) && a>0 && a<1
            S.alpha = a;
        else
            set(S.hAlpha,'String',num2str(S.alpha));
        end
        guidata(hFig,S);
    end

    function onAddFiles(~,~)
        S = guidata(hFig);
        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        [f,p] = uigetfile({'*.mat;*.txt','MAT or TXT (*.mat, *.txt)'}, ...
            'Select DATA (.mat) and/or ROI (.txt/.mat) files', startPath, 'MultiSelect','on');
        if isequal(f,0), return; end
        if ischar(f), f={f}; end

        for i=1:numel(f)
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
        for i=1:numel(dm), addFileSmart(fullfile(dm(i).folder, dm(i).name)); end
        for i=1:numel(dt), addFileSmart(fullfile(dt(i).folder, dt(i).name)); end
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

        for r=sel(:)'
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

        for r=sel(:)'
            S.subj{r,6} = fp;
        end
        guidata(hFig,S);
        refreshTable();
    end

    function onSaveList(~,~)
        S = guidata(hFig);
        [f,p] = uiputfile('GroupSubjects.mat','Save subject list');
        if isequal(f,0), return; end

        save(fullfile(p,f),'-struct','S','subj','mode', ...
            'baseStart','baseEnd','sigStart','sigEnd','mapSummary', ...
            'tc_computePSC','tc_baseMin0','tc_baseMin1','tc_injMin0','tc_injMin1', ...
            'tc_plateauMin0','tc_plateauMin1','tc_peakSearchMin0','tc_peakSearchMin1', ...
            'tc_peakWinMin','tc_trimPct','tc_peakMethod','tc_metric','tc_lowerPlot', ...
            'tc_baselineZero','tc_colorScheme','tc_showSEM','plotTop','plotBot', ...
            'testType','alpha','outDir');
    end

    function onLoadList(~,~)
        S = guidata(hFig);
        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'},'Load subject list');
        if isequal(f,0), return; end
        L = load(fullfile(p,f));

        fn = fieldnames(L);
        for k=1:numel(fn)
            try, S.(fn{k}) = L.(fn{k}); catch, end
        end

        guidata(hFig,S);
        syncUIFromState();
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

        % Sync UI -> state
        try, onROIChanged([],[]); catch, end
        try, onStatsChanged([],[]); catch, end
        try, onMapChanged([],[]); catch, end
        S = guidata(hFig);

        setStatus(false);
        set(S.hStatus,'String','Running...');
        drawnow;

        try
            S.subj = get(S.hTable,'Data');
            guidata(hFig,S);

            if strcmpi(S.mode,'ROI Timecourse')
                R = runROITimecourseAnalysis(S);
            else
                R = runPSCMapAnalysis(S);
            end

            S = guidata(hFig);
            S.last = R;
            guidata(hFig,S);

            updatePreview();
            set(S.hStatus,'String','Done.');
        catch ME
            set(S.hStatus,'String',['ERROR: ' ME.message]);
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

        % Save preview PNGs
        try
            f1 = figure('Visible','off','Color','w'); ax = axes('Parent',f1);
            exportOnePreview(ax,1,S);
            saveas(f1, fullfile(outFolder,'PreviewTop.png')); close(f1);
        catch
        end
        try
            f2 = figure('Visible','off','Color','w'); ax = axes('Parent',f2);
            exportOnePreview(ax,2,S);
            saveas(f2, fullfile(outFolder,'PreviewBottom.png')); close(f2);
        catch
        end

        % CSV metrics
        try
            if isfield(S.last,'metrics') && isfield(S.last.metrics,'table') && ~isempty(S.last.metrics.table)
                writeCellCSV(fullfile(outFolder,'Metrics.csv'), S.last.metrics.table);
            end
        catch
        end

        set(S.hStatus,'String',['Exported: ' outFolder]);
    end

% =========================================================
% Preview rendering
% =========================================================
    function clearPreview()
        cla(S.ax1); cla(S.ax2);
        title(S.ax1,'Top plot','Color','w','FontWeight','bold');
        title(S.ax2,'Bottom plot','Color','w','FontWeight','bold');
        fixAxesInset(S.ax1);
        fixAxesInset(S.ax2);
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
            fixAxesInset(S.ax1);
            fixAxesInset(S.ax2);
            return;
        end

        % ROI mode
        t = R.tMin(:)';

        % TOP plot
        axes(S.ax1); %#ok<LAXES>
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
        if R.unitsPercent, ylabel(S.ax1,'Signal change (%)','Color','w');
        else,             ylabel(S.ax1,'ROI signal (a.u.)','Color','w');
        end
        title(S.ax1, sprintf('Mean ROI timecourse | baseline: %s', R.baselineZero), 'Color','w','FontWeight','bold');
        legend(S.ax1, leg, 'TextColor','w','Location','northwest','Box','off');

        applyYLim(S.ax1, allTop, R.plotTop);
        fixAxesInset(S.ax1);
        hold(S.ax1,'off');

        % BOTTOM plot
        axes(S.ax2); %#ok<LAXES>
        cla(S.ax2); hold(S.ax2,'on');
        set(S.ax2,'Color',S.C.axisBg,'XColor','w','YColor','w','FontSize',S.F.base);
        grid(S.ax2,'on');

        if strcmpi(R.lowerPlotMode,'Metric scatter')
            gNames = R.groupNames;
            metricVals = R.metricVals;
            grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,2), 'UniformOutput',false);

            xTicks = 1:numel(gNames);
            allBot = [];

            for g=1:numel(gNames)
                idx = strcmpi(grpCol, gNames{g});
                y = metricVals(idx);
                y = y(isfinite(y));
                if isempty(y), continue; end

                col = R.groupColors.(makeField(gNames{g}));
                jitter = (rand(size(y))-0.5)*0.18;
                scatter(S.ax2, xTicks(g)+jitter, y, 70, col, 'filled');
                plot(S.ax2,[xTicks(g)-0.25 xTicks(g)+0.25],[mean(y) mean(y)],'LineWidth',2.8,'Color',col);

                allBot = [allBot; y(:)]; %#ok<AGROW>
            end

            set(S.ax2,'XLim',[0.5 numel(gNames)+0.5], 'XTick',xTicks, 'XTickLabel',gNames);

            if R.unitsPercent, ylabel(S.ax2,'Signal change (%)','Color','w');
            else,             ylabel(S.ax2,'Metric (a.u.)','Color','w');
            end

            ttl = ['Metric: ' R.metricName];
            if isfield(R,'stats') && isfield(R.stats,'p') && ~isempty(R.stats.p) && isfinite(R.stats.p)
                ttl = sprintf('%s | p=%.4g', ttl, R.stats.p);
            end
            title(S.ax2, ttl, 'Color','w','FontWeight','bold');

            applyYLim(S.ax2, allBot, R.plotBot);
            fixAxesInset(S.ax2);

        else
            s0 = R.peakSearch(1); s1 = R.peakSearch(2);
            patch(S.ax2,[s0 s1 s1 s0],[-1e9 -1e9 1e9 1e9],[0.8 0.8 0.8],'FaceAlpha',0.08,'EdgeColor','none');

            allBot = [];

            for g=1:numel(R.group)
                col = R.groupColors.(makeField(R.group(g).name));
                mu = R.group(g).mean(:)';
                plot(S.ax2, t, mu, 'LineWidth',2.4, 'Color',col);
                allBot = [allBot, mu]; %#ok<AGROW>

                if isfield(R,'groupPeak') && numel(R.groupPeak)>=g
                    pw = R.groupPeak(g).win;
                    pv = R.groupPeak(g).val;
                    pt = R.groupPeak(g).time;
                    plot(S.ax2,[pw(1) pw(2)],[pv pv],'LineWidth',5.0,'Color',col);
                    plot(S.ax2,pt,pv,'o','MarkerSize',8,'LineWidth',2,'Color',col);
                end
            end

            xlabel(S.ax2,'Time (min)','Color','w');
            if R.unitsPercent, ylabel(S.ax2,'Signal change (%)','Color','w');
            else,             ylabel(S.ax2,'Signal (a.u.)','Color','w');
            end
            title(S.ax2, sprintf('Peak view | %s | search %.1f–%.1f min | win %.1f min', ...
                R.peakMethod, R.peakSearch(1), R.peakSearch(2), R.peakWinMin), ...
                'Color','w','FontWeight','bold');

            applyYLim(S.ax2, allBot, R.plotBot);
            fixAxesInset(S.ax2);
        end

        hold(S.ax2,'off');
    end

% =========================================================
% UI sync helpers
% =========================================================
    function syncUIFromState()
        S = guidata(hFig);

        if strcmpi(S.mode,'ROI Timecourse'), set(S.hMode,'Value',1); else, set(S.hMode,'Value',2); end
        setPopupToString(S.hMapSummary, S.mapSummary);

        set(S.hTC_ComputePSC,'Value',double(S.tc_computePSC));
        set(S.hBase0,'String',num2str(S.tc_baseMin0));
        set(S.hBase1,'String',num2str(S.tc_baseMin1));
        set(S.hInj0,'String',num2str(S.tc_injMin0));
        set(S.hInj1,'String',num2str(S.tc_injMin1));
        set(S.hPlat0,'String',num2str(S.tc_plateauMin0));
        set(S.hPlat1,'String',num2str(S.tc_plateauMin1));
        set(S.hPkS0,'String',num2str(S.tc_peakSearchMin0));
        set(S.hPkS1,'String',num2str(S.tc_peakSearchMin1));

        set(S.hTC_PeakWin,'String',num2str(S.tc_peakWinMin));
        set(S.hTC_Trim,'String',num2str(S.tc_trimPct));
        setPopupToString(S.hTC_PeakMethod, S.tc_peakMethod);
        setPopupToString(S.hTC_Metric, S.tc_metric);
        setPopupToString(S.hTC_LowerPlot, S.tc_lowerPlot);
        setPopupToString(S.hTC_BaseZero, S.tc_baselineZero);
        setPopupToString(S.hColorScheme, S.tc_colorScheme);
        set(S.hShowSEM,'Value',double(S.tc_showSEM));

        set(S.hTopAuto,'Value',double(S.plotTop.auto));
        set(S.hTopZero,'Value',double(S.plotTop.forceZero));
        set(S.hTopYmin,'String',num2str(S.plotTop.ymin));
        set(S.hTopYmax,'String',num2str(S.plotTop.ymax));

        set(S.hBotAuto,'Value',double(S.plotBot.auto));
        set(S.hBotZero,'Value',double(S.plotBot.forceZero));
        set(S.hBotYmin,'String',num2str(S.plotBot.ymin));
        set(S.hBotYmax,'String',num2str(S.plotBot.ymax));

        setPopupToString(S.hTest, S.testType);
        set(S.hAlpha,'String',num2str(S.alpha));
        set(S.hOutEdit,'String',S.outDir);
    end

    function setPopupToString(h, desired)
        items = get(h,'String');
        v = 1;
        for k=1:numel(items)
            if strcmpi(items{k}, desired), v = k; break; end
        end
        set(h,'Value',v);
    end

% =========================================================
% Subject add / refresh
% =========================================================
    function addFileSmart(fp)
        S = guidata(hFig);
        [~,~,ext] = fileparts(fp);
        ext = lower(ext);

        subj = guessSubjectID(fp);
        if isempty(subj), subj = ['S' num2str(size(S.subj,1)+1)]; end

        rowIdx = find(strcmpi(S.subj(:,1), subj), 1, 'first');

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

        if isROI
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
% Studio hooks
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

function [h0,h1] = addPairEditsDark(parent, y, label, v0, v1, C, cb)
bg = get(parent,'BackgroundColor');
uicontrol(parent,'Style','text','String',label, ...
    'Units','normalized','Position',[0.02 y 0.25 0.10], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

h0 = uicontrol(parent,'Style','edit','String',num2str(v0), ...
    'Units','normalized','Position',[0.27 y+0.01 0.10 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',cb);

h1 = uicontrol(parent,'Style','edit','String',num2str(v1), ...
    'Units','normalized','Position',[0.39 y+0.01 0.10 0.10], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',cb);

uicontrol(parent,'Style','text','String','start / end', ...
    'Units','normalized','Position',[0.52 y 0.18 0.10], ...
    'BackgroundColor',bg,'ForegroundColor',[0.7 0.7 0.7], ...
    'HorizontalAlignment','left');
end

function [hAuto,hZero,hYmin,hYmax] = mkYControls(parent, y0, label, cfg, C, cb)
bg = get(parent,'BackgroundColor');

uicontrol(parent,'Style','text','String',[label ':'], ...
    'Units','normalized','Position',[0.02 y0 0.08 0.30], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hAuto = uicontrol(parent,'Style','checkbox','String','Auto', ...
    'Units','normalized','Position',[0.12 y0+0.05 0.10 0.22], ...
    'Value',double(cfg.auto), ...
    'BackgroundColor',bg,'ForegroundColor','w', ...
    'Callback',cb);

hZero = uicontrol(parent,'Style','checkbox','String','Force Ymin=0', ...
    'Units','normalized','Position',[0.24 y0+0.05 0.18 0.22], ...
    'Value',double(cfg.forceZero), ...
    'BackgroundColor',bg,'ForegroundColor','w', ...
    'Callback',cb);

uicontrol(parent,'Style','text','String','Ymin:', ...
    'Units','normalized','Position',[0.45 y0 0.06 0.25], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmin = uicontrol(parent,'Style','edit','String',num2str(cfg.ymin), ...
    'Units','normalized','Position',[0.51 y0 0.10 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',cb);

uicontrol(parent,'Style','text','String','Ymax:', ...
    'Units','normalized','Position',[0.64 y0 0.06 0.25], ...
    'BackgroundColor',bg,'ForegroundColor','w','HorizontalAlignment','left','FontWeight','bold');

hYmax = uicontrol(parent,'Style','edit','String',num2str(cfg.ymax), ...
    'Units','normalized','Position',[0.70 y0 0.10 0.30], ...
    'BackgroundColor',C.editBg,'ForegroundColor','w', ...
    'Callback',cb);
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
    'Tag',tag, ...
    'Callback',@(s,e) cb(s,e,tag));
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
        lo = lo - pad;
        hi = hi + pad;
        if plotCfg.forceZero, lo = 0; end
    end
    ylim(ax,[lo hi]);
else
    lo = plotCfg.ymin; hi = plotCfg.ymax;
    if plotCfg.forceZero, lo = 0; end
    if ~isfinite(lo) || ~isfinite(hi) || lo>=hi, return; end
    ylim(ax,[lo hi]);
end
end

function sel = clampSelRows(sel, nRows)
if isempty(sel), sel = []; return; end
sel = unique(sel(:)'); sel = sel(sel>=1 & sel<=nRows);
end

function v = safeNum(str, fallback)
v = str2double(str);
if isnan(v) || ~isfinite(v), v = fallback; end
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

function field = makeField(name)
field = upper(strtrim(char(name)));
field = regexprep(field,'[^A-Z0-9_]','_');
if isempty(field), field = 'GROUP'; end
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
    if startsWith(ln,'#')
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

function colors = assignGroupColors(gNames, scheme, C)
colors = struct();
scheme = strtrim(char(scheme));

if strcmpi(scheme,'PACAP/Vehicle')
    for i=1:numel(gNames)
        nm = upper(strtrim(gNames{i}));
        if ~isempty(strfind(nm,'PACAP'))
            col = [0.20 0.65 0.90];
        elseif ~isempty(strfind(nm,'VEH')) || ~isempty(strfind(nm,'CONTROL')) || ~isempty(strfind(nm,'VEHICLE'))
            col = [0.80 0.80 0.80];
        else
            base = lines(numel(gNames));
            col = base(i,:);
        end
        colors.(makeField(gNames{i})) = col;
    end
    return;
end

if strcmpi(scheme,'Blue/Red')
    base2 = [0.20 0.65 0.90; 0.90 0.25 0.25];
elseif strcmpi(scheme,'Purple/Green')
    base2 = [0.65 0.40 0.95; 0.25 0.85 0.55];
elseif strcmpi(scheme,'Gray/Orange')
    base2 = [0.70 0.70 0.70; 0.95 0.55 0.20];
else
    base = lines(max(1,numel(gNames)));
    for i=1:numel(gNames)
        colors.(makeField(gNames{i})) = base(i,:);
    end
    return;
end

base = lines(max(1,numel(gNames)));
for i=1:numel(gNames)
    if i<=2, col = base2(i,:); else, col = base(i,:); end
    colors.(makeField(gNames{i})) = col;
end
end

function X = applyBaselineZero(X, tMin, b0, b1, mode)
mode = strtrim(char(mode));
if strcmpi(mode,'None'), return; end

if strcmpi(mode,'Subtract first point')
    for i=1:size(X,1)
        if isfinite(X(i,1)), X(i,:) = X(i,:) - X(i,1); end
    end
    return;
end

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

function R = runROITimecourseAnalysis(S)
grpCol = S.subj(:,2);
grpCol = cellfun(@(x) strtrim(char(x)), grpCol, 'UniformOutput',false);
grpCol(cellfun(@isempty,grpCol)) = {'GroupA'};
gNames = unique(grpCol,'stable');
if isempty(gNames), error('No groups defined.'); end

N = size(S.subj,1);
tcAll = cell(N,1);
tAll  = cell(N,1);
isPSCInput = false(N,1);

for i=1:N
    row = S.subj(i,:);
    dataFile = ''; roiFile = '';
    if numel(row)>=5 && ~isempty(row{5}), dataFile = strtrim(char(row{5})); end
    if numel(row)>=6 && ~isempty(row{6}), roiFile  = strtrim(char(row{6})); end

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

% baseline re-zero (visual preference)
X = applyBaselineZero(X, tCommon, S.tc_baseMin0, S.tc_baseMin1, S.tc_baselineZero);

groupColors = assignGroupColors(gNames, S.tc_colorScheme, S.C);

% group mean/SEM
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

% metrics
plateau = nan(N,1);
platIdx = (tCommon>=S.tc_plateauMin0) & (tCommon<=S.tc_plateauMin1);
if ~any(platIdx), error('Plateau window has no samples.'); end
for i=1:N
    plateau(i) = nanmean_local(X(i,platIdx),2);
end

[peakVal, peakTime, peakWin] = computePeakPerRow(X, tCommon, S);

if strcmpi(S.tc_metric,'Plateau')
    metricVals = plateau;
    metricName = sprintf('Plateau mean (%.1f–%.1f min)', S.tc_plateauMin0, S.tc_plateauMin1);
else
    metricVals = peakVal;
    metricName = sprintf('Peak (%s) in %.1f–%.1f min', S.tc_peakMethod, S.tc_peakSearchMin0, S.tc_peakSearchMin1);
end

stats = computeSimpleStats(metricVals, grpCol, S);

% group-mean peak
groupPeak = struct([]);
for g=1:numel(groupTC)
    [pv, pt, pw] = computePeakMetric(groupTC(g).mean, tCommon, ...
        S.tc_peakSearchMin0, S.tc_peakSearchMin1, S.tc_peakWinMin, S.tc_trimPct, S.tc_peakMethod);
    groupPeak(g).name = groupTC(g).name;
    groupPeak(g).val  = pv;
    groupPeak(g).time = pt;
    groupPeak(g).win  = pw;
end

% table export
Tcell = cell(N+1,8);
Tcell(1,:) = {'Subject','Group','Plateau','PeakVal','PeakTime_min','PeakWin_min','UnitsPercent','Metric'};
for i=1:N
    Tcell{i+1,1} = strtrim(char(S.subj{i,1}));
    Tcell{i+1,2} = grpCol{i};
    Tcell{i+1,3} = plateau(i);
    Tcell{i+1,4} = peakVal(i);
    Tcell{i+1,5} = peakTime(i);
    Tcell{i+1,6} = sprintf('%.2f-%.2f', peakWin(i,1), peakWin(i,2));
    Tcell{i+1,7} = double(unitsPercent);
    Tcell{i+1,8} = metricName;
end

R = struct();
R.mode = 'ROI Timecourse';
R.tMin = tCommon;
R.group = groupTC;
R.groupPeak = groupPeak;
R.groupNames = gNames;
R.groupColors = groupColors;
R.infusion = [S.tc_injMin0 S.tc_injMin1];
R.unitsPercent = unitsPercent;
R.metricName = metricName;
R.metricVals = metricVals;
R.stats = stats;
R.metrics = struct('table',{Tcell});
R.subjTable = S.subj;
R.lowerPlotMode = S.tc_lowerPlot;
R.peakMethod = S.tc_peakMethod;
R.peakSearch = [S.tc_peakSearchMin0 S.tc_peakSearchMin1];
R.peakWinMin = S.tc_peakWinMin;
R.trimPct = S.tc_trimPct;
R.plotTop = S.plotTop;
R.plotBot = S.plotBot;
R.showSEM = S.tc_showSEM;
R.baselineZero = S.tc_baselineZero;
end

function [peakVal, peakTime, peakWin] = computePeakPerRow(X, tCommon, S)
N = size(X,1);
peakVal  = nan(N,1);
peakTime = nan(N,1);
peakWin  = nan(N,2);
for i=1:N
    [pv, pt, pw] = computePeakMetric(X(i,:), tCommon, ...
        S.tc_peakSearchMin0, S.tc_peakSearchMin1, S.tc_peakWinMin, S.tc_trimPct, S.tc_peakMethod);
    peakVal(i) = pv;
    peakTime(i)= pt;
    peakWin(i,:)= pw;
end
end

function stats = computeSimpleStats(metricVals, grpCol, S)
stats = struct('type',S.testType,'alpha',S.alpha,'p',[],'t',[],'F',[],'df',[],'desc','');

testType = strtrim(char(S.testType));
if strcmpi(testType,'None')
    stats.desc = 'No test.';
    return;
end

gNames = unique(grpCol,'stable');

if strcmpi(testType,'One-sample (vs 0)')
    [t,p,df] = oneSampleT_vec(metricVals);
    stats.t=t; stats.p=p; stats.df=df; stats.desc='One-sample vs 0';
elseif strcmpi(testType,'Two-sample (GroupA vs GroupB)')
    if numel(gNames)<2, error('Need >=2 groups.'); end
    a = metricVals(strcmpi(grpCol,gNames{1}));
    b = metricVals(strcmpi(grpCol,gNames{2}));
    [t,p,df] = welchT_vec(a,b);
    stats.t=t; stats.p=p; stats.df=df; stats.desc=sprintf('%s vs %s',gNames{1},gNames{2});
elseif strcmpi(testType,'Paired (CondA vs CondB)')
    [t,p,df,desc] = pairedT_metric_fromTable(S.subj, metricVals);
    stats.t=t; stats.p=p; stats.df=df; stats.desc=desc;
else
    [F,p,df] = oneWayANOVA_metric(metricVals, grpCol);
    stats.F=F; stats.p=p; stats.df=df; stats.desc='ANOVA';
end
end

function exportOnePreview(ax, which, S)
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
    grid(ax,'on'); xlabel(ax,'Time (min)');
    if R.unitsPercent, ylabel(ax,'Signal change (%)'); else, ylabel(ax,'ROI signal'); end
    title(ax,'Mean ROI timecourse');
    hold(ax,'off');
else
    gNames = R.groupNames;
    metricVals = R.metricVals;
    grpCol = cellfun(@(x) strtrim(char(x)), R.subjTable(:,2), 'UniformOutput',false);
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
    ylabel(ax,'Metric'); title(ax,['Metric: ' R.metricName]); grid(ax,'on');
    hold(ax,'off');
end
end

function R = runPSCMapAnalysis(S)
if S.baseEnd <= S.baseStart, error('Baseline end must be > baseline start.'); end
if S.sigEnd  <= S.sigStart,  error('Signal end must be > signal start.'); end

[G, files] = splitByGroup(S.subj, 5);
if isempty(G.names), error('No groups defined.'); end

maps = cell(1,numel(files));
meta = struct('subject',[],'group',[],'file',[]);

for i=1:numel(files)
    row = S.subj(i,:);
    fp = strtrim(char(row{5}));
    if isempty(fp) || exist(fp,'file')~=2
        error('Row %d missing DATA .mat for PSC Map mode.', i);
    end
    maps{i} = extractPSCMap(fp, S.baseStart, S.baseEnd, S.sigStart, S.sigEnd);
    meta(i).subject = strtrim(char(row{1}));
    meta(i).group   = strtrim(char(row{2}));
    meta(i).file    = fp;
end

groupSummary = struct([]);
for g=1:numel(G.names)
    idx = strcmp(G.labels, G.names{g});
    groupMaps = maps(idx);
    groupSummary(g).name = G.names{g};
    if strcmpi(S.mapSummary,'Median')
        groupSummary(g).map = medianCat(groupMaps);
    else
        groupSummary(g).map = meanCat(groupMaps);
    end
end

R = struct();
R.mode = 'PSC Map';
R.group = groupSummary;
R.meta = meta;
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

function [pkVal, pkTime, pkWin] = computePeakMetric(y, tMin, s0, s1, winMin, trimPct, method)
y = double(y(:)'); tMin = double(tMin(:)');

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

w = max(1, round(winMin/dt));
iStart = idxAll(1);
iEnd   = idxAll(end);

best = -Inf; bestStart = NaN; bestEnd = NaN;
for i=iStart:(iEnd-w+1)
    j=i+w-1;
    if j>iEnd, break; end
    if tMin(j)>s1, break; end

    seg = y(i:j); seg = seg(isfinite(seg));
    if isempty(seg), continue; end

    if strcmpi(method,'Window mean')
        val = mean(seg);
    elseif strcmpi(method,'Window median')
        val = median(seg);
    else
        val = trimmedMean(seg, trimPct);
    end

    if val > best
        best = val; bestStart = i; bestEnd = j;
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
i0 = 1+k; i1 = n-k;
if i1 < i0, m = mean(x); else, m = mean(x(i0:i1)); end
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
if numel(uConds) < 2, error('Paired test needs >=2 Condition labels.'); end

condA = uConds{1}; condB = uConds{2};
desc = ['Paired t-test | ' condA ' vs ' condB];

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
            if isempty(v) || ~isfinite(v), s=''; else, s=num2str(v); end
        else
            s = char(v);
        end
        s = strrep(s,'"','""');
        row{c} = ['"' s '"'];
    end
    fprintf(fid,'%s\n', strjoin(row,','));
end
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
if d==4, Z = sz(3); T = sz(4); else, Z = 1; T = sz(3); end

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