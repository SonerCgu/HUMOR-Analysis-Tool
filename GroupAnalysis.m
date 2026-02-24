function hFig = GroupAnalysis(varargin)
% GroupAnalysis.m  (MATLAB 2017b compatible)
% =========================================================
% fUSI Studio — Group-Level Analysis GUI
% - Assign subjects to groups
% - Run fixed-effect averaging (mean/median)
% - Run random-effect t-tests:
%     * one-sample (vs 0)
%     * two-sample (GroupA vs GroupB)
%     * paired (ConditionA vs ConditionB using PairID)
% - Works for:
%     (1) PSC MAPS (baseline+signal window -> PSC% map)
%     (2) ROI TIMECOURSES (roiTC matrix per subject)
%
% Expected inputs you can load per subject:
%  A) Map file:
%     - a .mat containing numeric variable named one of:
%         'PSCmap','pscMap','map','beta','Beta','T','tMap'
%     - OR a pipeline .mat containing struct 'newData' with field 'I' (+ TR)
%       (then PSC map is computed from baseline/signal windows without needing full PSC)
%
%  B) ROI timecourse file:
%     - a .mat containing variable 'roiTC'   (size: [R x T] or [T x R])
%     - optional: 'roiNames' (cellstr), 'tSec' (1 x T)
%
% Supported calling styles:
%   1) Name-Value:
%        GroupAnalysis('studio',studio,'logFcn',@(...),'statusFcn',@(...),'startDir',path,'onClose',@(...))
%   2) Positional (for easy Studio integration):
%        GroupAnalysis(studio, onClose, 'logFcn',..., 'statusFcn',..., 'startDir',...)
%
% Name-Value:
%   'studio'     : fusi_studio struct (for default paths)
%   'logFcn'     : @(msg) ... (optional)
%   'statusFcn'  : @(isReady) ... (optional)  % studio-ready flag
%   'startDir'   : default folder for file pickers
%   'onClose'    : callback executed when this window closes (optional)
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

if ~isempty(posStudio)
    opt.studio = posStudio;
end
if ~isempty(posOnClose)
    opt.onClose = posOnClose;
end

if isempty(opt.startDir)
    opt.startDir = pwd;
end
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

% -------------------- Figure -----------------------------
hFig = figure('Name','fUSI Studio — Group Analysis', ...
    'Color',C.bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[150 80 1650 900], ...
    'CloseRequestFcn', @closeMe);

% -------------------- State ------------------------------
S = struct();
S.opt = opt;
S.C = C;

% subject table columns:
% Subject | Group | Condition | PairID | File
S.subj = cell(0,5);
S.selectedRows = [];
S.isClosing = false;

S.last = struct(); % last results
S.mode = 'PSC Map';

% Defaults for PSC map
S.baseStart = 0;
S.baseEnd   = 10;
S.sigStart  = 10;
S.sigEnd    = 30;

% ROI options
S.roiSel = [];      % optional ROI subset indices
S.roiNames = {};    % loaded from first ROI file

% Stats defaults
S.testType = 'None';
S.alpha = 0.05;
S.mcc = 'None'; % None | FDR (BH) | Bonferroni

% Output folder default
S.outDir = defaultOutDir(opt);

% -------------------- Layout panels ----------------------
% Left: subject manager
leftW = 0.44;
pLeft = uipanel(hFig,'Units','normalized','Position',[0.02 0.05 leftW 0.93], ...
    'Title','Subjects / Groups', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold');

% Right: options + preview
pRight = uipanel(hFig,'Units','normalized','Position',[0.02+leftW+0.02 0.05 0.96-(0.02+leftW+0.02) 0.93], ...
    'Title','Analysis + Preview', 'BackgroundColor',C.panel,'ForegroundColor','w', ...
    'FontSize',14,'FontWeight','bold');

% -------------------- Subject table -----------------------
colNames = {'Subject','Group','Condition','PairID','File'};
colEdit  = [true true true true false];

S.hTable = uitable(pLeft, ...
    'Units','normalized', ...
    'Position',[0.03 0.28 0.94 0.69], ...
    'Data',S.subj, ...
    'ColumnName',colNames, ...
    'ColumnEditable',colEdit, ...
    'RowName',[], ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',C.muted, ...
    'FontName','Courier New', ...
    'FontSize',11, ...
    'CellSelectionCallback', @onCellSelect);

% Buttons under table
S.hAddFiles = uicontrol(pLeft,'Style','pushbutton','String','Add .MAT Files', ...
    'Units','normalized','Position',[0.03 0.21 0.30 0.06], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onAddFiles);

S.hAddFolder = uicontrol(pLeft,'Style','pushbutton','String','Add Folder (scan)', ...
    'Units','normalized','Position',[0.35 0.21 0.30 0.06], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onAddFolder);

S.hRemove = uicontrol(pLeft,'Style','pushbutton','String','Remove Selected', ...
    'Units','normalized','Position',[0.67 0.21 0.30 0.06], ...
    'BackgroundColor',C.warn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onRemoveSelected);

S.hSaveList = uicontrol(pLeft,'Style','pushbutton','String','Save Subject List', ...
    'Units','normalized','Position',[0.03 0.14 0.46 0.06], ...
    'BackgroundColor',[0.20 0.55 0.95],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onSaveList);

S.hLoadList = uicontrol(pLeft,'Style','pushbutton','String','Load Subject List', ...
    'Units','normalized','Position',[0.51 0.14 0.46 0.06], ...
    'BackgroundColor',[0.15 0.65 0.55],'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onLoadList);

% Output folder row
uicontrol(pLeft,'Style','text','String','Output folder:', ...
    'Units','normalized','Position',[0.03 0.085 0.25 0.04], ...
    'BackgroundColor',C.panel,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold','FontSize',11);

S.hOutEdit = uicontrol(pLeft,'Style','edit','String',S.outDir, ...
    'Units','normalized','Position',[0.28 0.085 0.54 0.045], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'HorizontalAlignment','left','FontSize',11, ...
    'Callback',@onOutEdit);

S.hOutBrowse = uicontrol(pLeft,'Style','pushbutton','String','Browse', ...
    'Units','normalized','Position',[0.84 0.085 0.13 0.045], ...
    'BackgroundColor',C.btn,'ForegroundColor','w','FontWeight','bold', ...
    'Callback',@onBrowseOut);

% Hint
S.hHint = uicontrol(pLeft,'Style','text', ...
    'String','Tip: Select rows (click/drag) and use Remove Selected. Edit Group/Condition/PairID directly in the table.', ...
    'Units','normalized','Position',[0.03 0.02 0.94 0.05], ...
    'BackgroundColor',C.panel,'ForegroundColor',C.muted, ...
    'HorizontalAlignment','left','FontSize',10);

% -------------------- Right panel: options ----------------
% Mode
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
makeWinRow(S.pPSC,0.00,'Signal end',   num2str(S.sigEnd),   @onPSCEdit,'sigEnd');

% Aggregation panel
S.pAgg = uipanel(pRight,'Units','normalized','Position',[0.03 0.61 0.32 0.10], ...
    'Title','Fixed effect summary', ...
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

% Stats panel
S.pStats = uipanel(pRight,'Units','normalized','Position',[0.03 0.42 0.32 0.17], ...
    'Title','Statistics (random effect)', ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','FontWeight','bold');

uicontrol(S.pStats,'Style','text','String','Test:', ...
    'Units','normalized','Position',[0.05 0.62 0.20 0.25], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hTest = uicontrol(S.pStats,'Style','popupmenu', ...
    'String',{'None','One-sample (vs 0)','Two-sample (GroupA vs GroupB)','Paired (CondA vs CondB)'}, ...
    'Units','normalized','Position',[0.27 0.64 0.68 0.25], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onTestChanged);

uicontrol(S.pStats,'Style','text','String','Alpha:', ...
    'Units','normalized','Position',[0.05 0.33 0.20 0.20], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hAlpha = uicontrol(S.pStats,'Style','edit','String',num2str(S.alpha), ...
    'Units','normalized','Position',[0.27 0.33 0.22 0.22], ...
    'BackgroundColor',[0.15 0.15 0.15],'ForegroundColor','w', ...
    'Callback',@onAlphaChanged);

uicontrol(S.pStats,'Style','text','String','MCC:', ...
    'Units','normalized','Position',[0.53 0.33 0.12 0.20], ...
    'BackgroundColor',C.panel2,'ForegroundColor','w','HorizontalAlignment','left', ...
    'FontWeight','bold');

S.hMCC = uicontrol(S.pStats,'Style','popupmenu', ...
    'String',{'None','FDR (BH)','Bonferroni'}, ...
    'Units','normalized','Position',[0.67 0.33 0.28 0.22], ...
    'BackgroundColor',[0.2 0.2 0.2],'ForegroundColor','w', ...
    'Callback',@onMCCChanged);

% Run/Export
S.hRun = uicontrol(pRight,'Style','pushbutton','String','RUN ANALYSIS', ...
    'Units','normalized','Position',[0.03 0.35 0.32 0.06], ...
    'BackgroundColor',C.accent,'ForegroundColor','w','FontWeight','bold','FontSize',13, ...
    'Callback',@onRun);

S.hExport = uicontrol(pRight,'Style','pushbutton','String','EXPORT RESULTS', ...
    'Units','normalized','Position',[0.03 0.28 0.32 0.06], ...
    'BackgroundColor',[0.30 0.50 0.95],'ForegroundColor','w','FontWeight','bold','FontSize',13, ...
    'Callback',@onExport);

% Preview axes (right side)
S.ax1 = axes('Parent',pRight,'Units','normalized','Position',[0.40 0.53 0.57 0.42], ...
    'Color',[0 0 0], 'XColor','w','YColor','w');
title(S.ax1,'Preview 1','Color','w','FontWeight','bold');

S.ax2 = axes('Parent',pRight,'Units','normalized','Position',[0.40 0.06 0.57 0.42], ...
    'Color',[0 0 0], 'XColor','w','YColor','w');
title(S.ax2,'Preview 2','Color','w','FontWeight','bold');

% Store + initial UI state
guidata(hFig,S);
setStatus(false);           % lock studio while GroupAnalysis window is open
applyModeUI();
clearPreview();
logMsg('Group Analysis GUI ready.');

% =========================================================
% Callbacks
% =========================================================
    function closeMe(src,~)
        S = guidata(src);
        if isempty(S), delete(src); return; end
        if isfield(S,'isClosing') && S.isClosing
            delete(src);
            return;
        end
        S.isClosing = true;
        guidata(src,S);

        % Restore Studio "READY"
        try, setStatus(true); catch, end
        try, logMsg('Group Analysis closed.'); catch, end

        % Optional external close hook
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
        if v == 1
            S.mode = 'PSC Map';
        else
            S.mode = 'ROI Timecourse';
        end
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
        else
            set(S.pPSC,'Visible','off');
            set(S.pAgg,'Visible','off');
        end
    end

    function onAddFiles(~,~)
        S = guidata(hFig);

        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        [f,p] = uigetfile({'*.mat','MAT files (*.mat)'}, ...
            'Select subject files (maps or pipeline mats)', startPath, 'MultiSelect','on');

        if isequal(f,0)
            logMsg('Add files cancelled.');
            return;
        end

        if ischar(f), f = {f}; end

        for i = 1:numel(f)
            fp = fullfile(p,f{i});
            addSubjectRow(fp);
        end

        refreshTable();
        logMsg(sprintf('Added %d file(s).', numel(f)));
    end

    function onAddFolder(~,~)
        S = guidata(hFig);

        startPath = S.opt.startDir;
        if ~exist(startPath,'dir'), startPath = pwd; end

        folder = uigetdir(startPath,'Select a folder to scan for .mat files');
        if isequal(folder,0)
            logMsg('Add folder cancelled.');
            return;
        end

        d = dir(fullfile(folder,'*.mat'));
        if isempty(d)
            logMsg('No .mat files found in selected folder.');
            return;
        end

        for i = 1:numel(d)
            addSubjectRow(fullfile(d(i).folder, d(i).name));
        end

        refreshTable();
        logMsg(sprintf('Scanned folder: %s | added %d files.', folder, numel(d)));
    end

    function onRemoveSelected(~,~)
        S = guidata(hFig);
        sel = S.selectedRows;

        if isempty(sel)
            logMsg('No rows selected to remove. (Click rows in the table first.)');
            return;
        end

        sel = sel(sel>=1 & sel<=size(S.subj,1));
        if isempty(sel)
            logMsg('Selection out of range.');
            return;
        end

        S.subj(sel,:) = [];
        S.selectedRows = [];
        guidata(hFig,S);
        refreshTable();
        logMsg(sprintf('Removed %d row(s).', numel(sel)));
    end

    function onSaveList(~,~)
        S = guidata(hFig);

        [f,p] = uiputfile('GroupSubjects.mat','Save subject list');
        if isequal(f,0), return; end

        subj = S.subj; %#ok<NASGU>
        mode = S.mode; %#ok<NASGU>
        baseStart = S.baseStart; baseEnd = S.baseEnd; %#ok<NASGU>
        sigStart  = S.sigStart;  sigEnd  = S.sigEnd;  %#ok<NASGU>
        outDir = S.outDir; %#ok<NASGU>

        save(fullfile(p,f),'subj','mode','baseStart','baseEnd','sigStart','sigEnd','outDir');
        logMsg(['Saved subject list: ' fullfile(p,f)]);
    end

    function onLoadList(~,~)
        S = guidata(hFig);

        [f,p] = uigetfile({'*.mat','MAT list (*.mat)'},'Load subject list');
        if isequal(f,0), return; end

        L = load(fullfile(p,f));

        if isfield(L,'subj') && iscell(L.subj)
            S.subj = L.subj;
        end
        if isfield(L,'mode'), S.mode = L.mode; end
        if isfield(L,'baseStart'), S.baseStart = L.baseStart; end
        if isfield(L,'baseEnd'),   S.baseEnd   = L.baseEnd;   end
        if isfield(L,'sigStart'),  S.sigStart  = L.sigStart;  end
        if isfield(L,'sigEnd'),    S.sigEnd    = L.sigEnd;    end
        if isfield(L,'outDir'),    S.outDir    = L.outDir;    end

        guidata(hFig,S);

        % reflect UI
        set(S.hMode,'Value', iff(strcmpi(S.mode,'PSC Map'),1,2));
        applyModeUI();
        setPSCUI();
        set(S.hOutEdit,'String',S.outDir);

        refreshTable();
        clearPreview();
        logMsg(['Loaded subject list: ' fullfile(p,f)]);
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
        logMsg(['Output folder set: ' S.outDir]);
    end

    function onPSCEdit(src,~,fieldName)
        S = guidata(hFig);
        v = str2double(get(src,'String'));
        if isnan(v)
            logMsg('Invalid number.');
            setPSCUI();
            return;
        end
        S.(fieldName) = v;
        guidata(hFig,S);
    end

    function setPSCUI()
        S = guidata(hFig);
        e = findobj(S.pPSC,'Style','edit');
        for k = 1:numel(e)
            tag = get(e(k),'Tag');
            if isfield(S,tag)
                set(e(k),'String',num2str(S.(tag)));
            end
        end
    end

    function onTestChanged(~,~)
        S = guidata(hFig);
        items = get(S.hTest,'String');
        S.testType = items{get(S.hTest,'Value')};
        guidata(hFig,S);
        logMsg(['Test set: ' S.testType]);
    end

    function onAlphaChanged(src,~)
        S = guidata(hFig);
        a = str2double(get(src,'String'));
        if isnan(a) || a<=0 || a>=1
            logMsg('Alpha must be between 0 and 1.');
            set(src,'String',num2str(S.alpha));
            return;
        end
        S.alpha = a;
        guidata(hFig,S);
    end

    function onMCCChanged(~,~)
        S = guidata(hFig);
        items = get(S.hMCC,'String');
        S.mcc = items{get(S.hMCC,'Value')};
        guidata(hFig,S);
        logMsg(['MCC set: ' S.mcc]);
    end

    function onRun(~,~)
        S = guidata(hFig);

        if isempty(S.subj)
            errordlg('Add subject files first.','Group Analysis');
            return;
        end

        % keep Studio locked while GA is open
        setStatus(false);
        logMsg('Running group analysis...');
        drawnow;

        try
            % sync any edits the user made in the table
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
            errordlg('Run analysis first.','Export');
            return;
        end

        outDir = S.outDir;
        if isempty(outDir), outDir = pwd; end
        if ~exist(outDir,'dir'), mkdir(outDir); end

        ts = datestr(now,'yyyymmdd_HHMMSS');
        outFolder = fullfile(outDir, ['GroupAnalysis_' ts]);
        mkdir(outFolder);

        R = S.last; %#ok<NASGU>
        save(fullfile(outFolder,'Results.mat'),'R','-v7.3');

        % export preview figures
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

        logMsg(['Exported results to: ' outFolder]);
    end

% =========================================================
% Analysis runners
% =========================================================
    function R = runPSCMapAnalysis()
        S = guidata(hFig);

        % validate windows
        if S.baseEnd <= S.baseStart
            error('Baseline end must be > baseline start.');
        end
        if S.sigEnd <= S.sigStart
            error('Signal end must be > signal start.');
        end

        % group split
        [G, files] = splitByGroup(S.subj);
        if numel(G.names) < 1
            error('No groups defined. Set Group column in the table.');
        end

        % Extract PSC maps per subject
        maps = cell(1,numel(files));
        meta = struct('subject',[],'group',[],'file',[]);

        for i = 1:numel(files)
            row = S.subj(i,:);
            subj = row{1}; grp = row{2}; fp = row{5};

            M = extractPSCMap(fp, S.baseStart, S.baseEnd, S.sigStart, S.sigEnd);

            maps{i} = M;
            meta(i).subject = subj;
            meta(i).group   = grp;
            meta(i).file    = fp;

            logMsg(sprintf('Loaded map %d/%d | %s | %s', i, numel(files), grp, subj));
            drawnow;
        end

        % Ensure consistent size
        sz0 = size(maps{1});
        for i = 2:numel(maps)
            if ~isequal(size(maps{i}), sz0)
                error('Map size mismatch. All subjects must be in same space/dimensions.');
            end
        end

        % summary per group
        summaryType = getPopupString(S.hSummary);
        groupSummary = struct();

        for g = 1:numel(G.names)
            idx = strcmp(G.labels, G.names{g});
            groupMaps = maps(idx);

            groupSummary(g).name = G.names{g};
            if strcmpi(summaryType,'Median')
                groupSummary(g).map  = medianCat(groupMaps);
            else
                groupSummary(g).map  = meanCat(groupMaps);
            end
        end

        % stats
        testType = getPopupString(S.hTest);
        alpha = S.alpha;
        mcc = S.mcc;

        stats = struct('type',testType,'alpha',alpha,'mcc',mcc,'t',[],'p',[],'mask',[],'desc','');

        if strcmpi(testType,'None')
            stats.desc = 'No statistical test.';
        elseif strcmpi(testType,'One-sample (vs 0)')
            if numel(G.names) < 1, error('Need at least 1 group.'); end
            idx = strcmp(G.labels, G.names{1});
            [tMap,pMap] = oneSampleT(maps(idx));
            [pAdj,mask] = applyMCC(pMap, alpha, mcc);
            stats.t = tMap; stats.p = pAdj; stats.mask = mask;
            stats.desc = ['One-sample t-test vs 0 | Group=' G.names{1}];

        elseif strcmpi(testType,'Two-sample (GroupA vs GroupB)')
            if numel(G.names) < 2
                error('Two-sample needs at least 2 groups.');
            end
            idx1 = strcmp(G.labels, G.names{1});
            idx2 = strcmp(G.labels, G.names{2});
            [tMap,pMap] = twoSampleT(maps(idx1), maps(idx2));
            [pAdj,mask] = applyMCC(pMap, alpha, mcc);
            stats.t = tMap; stats.p = pAdj; stats.mask = mask;
            stats.desc = ['Two-sample t-test | ' G.names{1} ' vs ' G.names{2}];

        elseif strcmpi(testType,'Paired (CondA vs CondB)')
            [tMap,pMap,desc] = pairedT_fromTable(S.subj, @extractPSCMap, ...
                S.baseStart,S.baseEnd,S.sigStart,S.sigEnd);
            [pAdj,mask] = applyMCC(pMap, alpha, mcc);
            stats.t = tMap; stats.p = pAdj; stats.mask = mask;
            stats.desc = desc;
        end

        R = struct();
        R.mode = 'PSC Map';
        R.windows = struct('baseStart',S.baseStart,'baseEnd',S.baseEnd,'sigStart',S.sigStart,'sigEnd',S.sigEnd);
        R.summaryType = summaryType;
        R.group = groupSummary;
        R.stats = stats;
        R.meta = meta;
    end

    function R = runROITimecourseAnalysis()
        S = guidata(hFig);

        [G, files] = splitByGroup(S.subj);
        if numel(G.names) < 1
            error('No groups defined. Set Group column in the table.');
        end

        % load ROI timecourses
        TC = cell(1,numel(files));
        tAll = cell(1,numel(files));
        roiNamesAll = {};

        for i = 1:numel(files)
            row = S.subj(i,:);
            subj = row{1}; grp = row{2}; fp = row{5};

            [tc, tSec, roiNames] = extractROITC(fp);
            TC{i} = tc;
            tAll{i} = tSec;

            if isempty(roiNamesAll) && ~isempty(roiNames)
                roiNamesAll = roiNames;
            end

            logMsg(sprintf('Loaded ROI TC %d/%d | %s | %s', i, numel(files), grp, subj));
            drawnow;
        end

        % align ROI dimension
        Rn = size(TC{1},1);
        for i = 2:numel(TC)
            if size(TC{i},1) ~= Rn
                error('ROI count mismatch across subjects.');
            end
        end

        % create common time axis (if tSec available)
        if all(cellfun(@(x) ~isempty(x), tAll))
            tMin = max(cellfun(@(x) x(1), tAll));
            tMax = min(cellfun(@(x) x(end), tAll));
            dt = median(diff(tAll{1}));
            if ~isfinite(dt) || dt<=0, dt = 1; end
            tCommon = tMin:dt:tMax;
            for i = 1:numel(TC)
                TC{i} = interp1(tAll{i}(:), TC{i}.' , tCommon(:), 'linear', 'extrap').'; % keep [R x T]
            end
        else
            % fallback: index axis
            Tn = size(TC{1},2);
            for i = 2:numel(TC)
                if size(TC{i},2) ~= Tn
                    error('Time length mismatch and no tSec provided to align.');
                end
            end
            tCommon = 1:size(TC{1},2);
        end

        % group-wise mean/SEM
        groupTC = struct();
        for g = 1:numel(G.names)
            idx = strcmp(G.labels, G.names{g});
            X = cat(3, TC{idx}); % [R x T x N]
            mu = nanmean_local(X,3);

            n = sum(isfinite(X),3);
            sd = nanstd_local(X,0,3);
            se = sd ./ sqrt(max(1,n));

            groupTC(g).name = G.names{g};
            groupTC(g).mean = mu;
            groupTC(g).sem  = se;
        end

        % stats over time (per ROI)
        testType = getPopupString(S.hTest);
        alpha = S.alpha;
        mcc = S.mcc;

        stats = struct('type',testType,'alpha',alpha,'mcc',mcc,'t',[],'p',[],'mask',[],'desc','');

        if strcmpi(testType,'None')
            stats.desc = 'No statistical test.';
        elseif strcmpi(testType,'One-sample (vs 0)')
            idx = strcmp(G.labels, G.names{1});
            [t,p] = oneSampleT_TC(TC(idx)); % [R x T]
            [pAdj,mask] = applyMCC(p, alpha, mcc);
            stats.t = t; stats.p = pAdj; stats.mask = mask;
            stats.desc = ['One-sample t-test vs 0 | Group=' G.names{1}];

        elseif strcmpi(testType,'Two-sample (GroupA vs GroupB)')
            if numel(G.names) < 2, error('Need at least 2 groups.'); end
            idx1 = strcmp(G.labels, G.names{1});
            idx2 = strcmp(G.labels, G.names{2});
            [t,p] = twoSampleT_TC(TC(idx1), TC(idx2));
            [pAdj,mask] = applyMCC(p, alpha, mcc);
            stats.t = t; stats.p = pAdj; stats.mask = mask;
            stats.desc = ['Two-sample t-test | ' G.names{1} ' vs ' G.names{2}];

        elseif strcmpi(testType,'Paired (CondA vs CondB)')
            [t,p,desc] = pairedT_TC_fromTable(S.subj, @extractROITC);
            [pAdj,mask] = applyMCC(p, alpha, mcc);
            stats.t = t; stats.p = pAdj; stats.mask = mask;
            stats.desc = desc;
        end

        R = struct();
        R.mode = 'ROI Timecourse';
        R.t = tCommon;
        R.roiNames = roiNamesAll;
        R.group = groupTC;
        R.stats = stats;
        R.subjTable = S.subj;
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

        if ~isfield(S,'last') || isempty(fieldnames(S.last))
            return;
        end

        R = S.last;

        if strcmpi(R.mode,'PSC Map')
            if ~isempty(R.group)
                imagesc_auto(S.ax1, squeeze2D(R.group(1).map));
                title(S.ax1, ['Group summary: ' R.group(1).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax1);
            end
            if isfield(R,'stats') && ~isempty(R.stats) && ~isempty(R.stats.t)
                imagesc_auto(S.ax2, squeeze2D(R.stats.t));
                title(S.ax2, ['T-map | ' R.stats.desc], 'Color','w','FontWeight','bold');
                colorbar(S.ax2);
            elseif numel(R.group) >= 2
                imagesc_auto(S.ax2, squeeze2D(R.group(2).map));
                title(S.ax2, ['Group summary: ' R.group(2).name], 'Color','w','FontWeight','bold');
                colorbar(S.ax2);
            end

        else
            roiIdx = 1;

            if ~isempty(R.group)
                hold(S.ax1,'on');
                for g = 1:numel(R.group)
                    mu = R.group(g).mean(roiIdx,:);
                    se = R.group(g).sem(roiIdx,:);
                    shadedLine(S.ax1, R.t, mu, se);
                end
                hold(S.ax1,'off');
                grid(S.ax1,'on');
                set(S.ax1,'XColor','w','YColor','w');
                title(S.ax1,'ROI #1 mean ± SEM','Color','w','FontWeight','bold');
                xlabel(S.ax1,'Time'); ylabel(S.ax1,'Signal');
            end

            if isfield(R,'stats') && ~isempty(R.stats) && ~isempty(R.stats.p)
                p = R.stats.p(roiIdx,:);
                plot(S.ax2, R.t, p, 'LineWidth',1.5);
                hold(S.ax2,'on');
                xl = get(S.ax2,'XLim');
                line(S.ax2, xl, [R.stats.alpha R.stats.alpha], 'LineStyle','--', 'LineWidth',1.2);
                hold(S.ax2,'off');
                grid(S.ax2,'on');
                set(S.ax2,'XColor','w','YColor','w');
                title(S.ax2, ['ROI #1 p-values | ' R.stats.desc], 'Color','w','FontWeight','bold');
                xlabel(S.ax2,'Time'); ylabel(S.ax2,'p');
                ylim(S.ax2,[0 1]);
            end
        end
    end

    function exportOnePreview(ax, which)
        S = guidata(hFig);
        R = S.last;

        cla(ax);
        if strcmpi(R.mode,'PSC Map')
            if which == 1
                imagesc(ax, squeeze2D(R.group(1).map));
                axis(ax,'image'); axis(ax,'off');
                title(ax, ['Group summary: ' R.group(1).name]);
                colorbar(ax);
            else
                if ~isempty(R.stats.t)
                    imagesc(ax, squeeze2D(R.stats.t));
                    axis(ax,'image'); axis(ax,'off');
                    title(ax, ['T-map | ' R.stats.desc]);
                    colorbar(ax);
                elseif numel(R.group) >= 2
                    imagesc(ax, squeeze2D(R.group(2).map));
                    axis(ax,'image'); axis(ax,'off');
                    title(ax, ['Group summary: ' R.group(2).name]);
                    colorbar(ax);
                end
            end
        else
            roiIdx = 1;
            if which == 1
                hold(ax,'on');
                for g = 1:numel(R.group)
                    shadedLine(ax, R.t, R.group(g).mean(roiIdx,:), R.group(g).sem(roiIdx,:));
                end
                hold(ax,'off'); grid(ax,'on');
                title(ax,'ROI #1 mean ± SEM'); xlabel(ax,'Time'); ylabel(ax,'Signal');
            else
                if ~isempty(R.stats.p)
                    plot(ax, R.t, R.stats.p(roiIdx,:), 'LineWidth',1.5);
                    hold(ax,'on');
                    xl = get(ax,'XLim');
                    line(ax, xl, [R.stats.alpha R.stats.alpha], 'LineStyle','--', 'LineWidth',1.2);
                    hold(ax,'off');
                    grid(ax,'on'); ylim(ax,[0 1]);
                    title(ax,['ROI #1 p-values | ' R.stats.desc]); xlabel(ax,'Time'); ylabel(ax,'p');
                end
            end
        end
    end

% =========================================================
% Helpers: subject handling
% =========================================================
    function addSubjectRow(fp)
        S = guidata(hFig);

        subj = guessSubjectID(fp);
        if isempty(subj), subj = ['S' num2str(size(S.subj,1)+1)]; end

        grp  = 'GroupA';
        cond = 'CondA';
        pair = '';

        % avoid duplicates
        if ~isempty(S.subj)
            existing = S.subj(:,5);
            if any(strcmp(existing, fp))
                return;
            end
        end

        S.subj(end+1,:) = {subj, grp, cond, pair, fp};
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
        if ok
            M = double(M);
            return;
        end

        D = loadPipelineStruct(fp);

        if ~isfield(D,'TR') || isempty(D.TR)
            error('Missing TR in file: %s', fp);
        end
        if ~isfield(D,'I') || isempty(D.I)
            error('Missing I in file: %s', fp);
        end

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

    function [tc, tSec, roiNames] = extractROITC(fp)
        roiNames = {};
        tSec = [];

        try
            L = load(fp);
        catch
            error('Failed to load ROI file: %s', fp);
        end

        if isfield(L,'roiTC')
            tc = L.roiTC;
        elseif isfield(L,'TC')
            tc = L.TC;
        else
            error('ROI file must contain variable roiTC (or TC). File: %s', fp);
        end

        if isfield(L,'roiNames'), roiNames = L.roiNames; end
        if isfield(L,'tSec'),     tSec = L.tSec; end

        tc = double(tc);

        % enforce [R x T] (R typically smaller than T)
        if size(tc,1) > size(tc,2)
            tc = tc.'; % [R x T]
        end
    end

% =========================================================
% Stats: maps
% =========================================================
    function [tMap,pMap] = oneSampleT(mapCell)
        X = catAlong4(mapCell);
        [tMap,pMap] = oneSampleT_array(X);
    end

    function [tMap,pMap] = twoSampleT(mapCell1, mapCell2)
        A = catAlong4(mapCell1);
        B = catAlong4(mapCell2);
        [tMap,pMap] = twoSampleT_array(A,B);
    end

% =========================================================
% Utility + UI
% =========================================================
    function setStatus(isReady)
        if ~isempty(opt.statusFcn)
            try, opt.statusFcn(isReady); catch, end
        end
    end

    function logMsg(msg)
        if ~isempty(opt.logFcn)
            try, opt.logFcn(msg); catch, end
        end
    end

end % end main function

% =========================================================
% Local helper functions (below)
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

function subj = guessSubjectID(fp)
[~,name,~] = fileparts(fp);
subj = name;
subj = regexprep(subj,'\s+','_');
subj = regexprep(subj,'[^A-Za-z0-9_]+','_');
subj = regexprep(subj,'_+','_');
subj = regexprep(subj,'^_','');
subj = regexprep(subj,'_$','');
end

function [G, files] = splitByGroup(subjTable)
files = subjTable(:,5);
labels = subjTable(:,2);
labels = cellfun(@(x) strtrim(char(x)), labels, 'UniformOutput',false);
labels(cellfun(@isempty,labels)) = {'GroupA'};
names = unique(labels,'stable');

G = struct();
G.labels = labels;
G.names  = names;
end

function [ok, M] = tryLoadNumericMap(fp)
ok = false; M = [];
try
    L = load(fp);
catch
    return;
end

cands = {'PSCmap','pscMap','map','Map','beta','Beta','tMap','T','Tmap','meanMap'};
for i = 1:numel(cands)
    if isfield(L,cands{i}) && isnumeric(L.(cands{i}))
        M = L.(cands{i});
        ok = true;
        return;
    end
end

fn = fieldnames(L);
numVars = {};
for i = 1:numel(fn)
    v = L.(fn{i});
    if isnumeric(v) && ~isscalar(v) && ndims(v)<=3
        numVars{end+1} = fn{i}; %#ok<AGROW>
    end
end
if numel(numVars)==1
    M = L.(numVars{1});
    ok = true;
end
end

function D = loadPipelineStruct(fp)
L = load(fp);

if isfield(L,'newData') && isstruct(L.newData)
    D = pullFields(L.newData);
    return;
end

if isfield(L,'data') && isstruct(L.data)
    D = pullFields(L.data);
    return;
end

fn = fieldnames(L);
for i = 1:numel(fn)
    if isstruct(L.(fn{i}))
        D = pullFields(L.(fn{i}));
        return;
    end
end

error('Could not find pipeline struct (newData/data) in file: %s', fp);
end

function D = pullFields(S)
D = struct();
if isfield(S,'I'), D.I = S.I; else, D.I = []; end
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

function [t,p] = oneSampleT_array(X)
dimN = ndims(X);
mu = nanmean_local(X, dimN);
sd = nanstd_local(X, 0, dimN);
n  = sum(isfinite(X), dimN);
se = sd ./ sqrt(max(1,n));
t = mu ./ max(eps,se);

df = max(1, n-1);

if exist('tcdf','file')==2
    p = 2 * tcdf(-abs(t), df);
else
    p = ones(size(t));
end

t(~isfinite(t)) = 0;
p(~isfinite(p)) = 1;
end

function [t,p] = twoSampleT_array(A,B)
dA = ndims(A); dB = ndims(B);
if dA~=dB
    error('Array dims mismatch.');
end
dimN = dA;

m1 = nanmean_local(A,dimN);
m2 = nanmean_local(B,dimN);
v1 = nanvar_local(A,dimN);
v2 = nanvar_local(B,dimN);
n1 = sum(isfinite(A),dimN);
n2 = sum(isfinite(B),dimN);

den = sqrt(v1./max(1,n1) + v2./max(1,n2));
t = (m1-m2) ./ max(eps,den);

a = v1./max(1,n1);
b = v2./max(1,n2);
df = (a+b).^2 ./ ( (a.^2)./max(1,(n1-1)) + (b.^2)./max(1,(n2-1)) );
df(~isfinite(df)) = 1;
df = max(1, df);

if exist('tcdf','file')==2
    p = 2 * tcdf(-abs(t), df);
else
    p = ones(size(t));
end

t(~isfinite(t)) = 0;
p(~isfinite(p)) = 1;
end

function [pAdj, mask] = applyMCC(p, alpha, mcc)
p = double(p);
p(~isfinite(p)) = 1;

switch lower(strtrim(mcc))
    case 'none'
        pAdj = p;
        mask = pAdj < alpha;

    case 'bonferroni'
        m = numel(p);
        pAdj = min(1, p * m);
        mask = pAdj < alpha;

    otherwise % FDR (BH)
        [pAdj, mask] = fdr_bh(p, alpha);
end
end

function [pAdj, mask] = fdr_bh(p, q)
p = p(:);
[ps, idx] = sort(p,'ascend');
m = numel(ps);
th = (1:m)'/m * q;
k = find(ps <= th, 1, 'last');

maskFlat = false(m,1);
if ~isempty(k)
    maskFlat(1:k) = true;
end

pAdjSorted = ps .* m ./ (1:m)';
pAdjSorted = min(1, cummin_local(pAdjSorted(end:-1:1)));
pAdjSorted = pAdjSorted(end:-1:1);

pAdj = zeros(m,1);
pAdj(idx) = pAdjSorted;

mask = false(m,1);
mask(idx) = maskFlat;

pAdj = reshape(pAdj, size(p));
mask = reshape(mask, size(p));
end

function y = cummin_local(x)
y = x;
for i = 2:numel(x)
    y(i) = min(y(i), y(i-1));
end
end

function shadedLine(ax, x, y, e)
x = x(:)'; y = y(:)'; e = e(:)';
up = y+e; dn = y-e;
patch(ax, [x fliplr(x)], [up fliplr(dn)], 1, 'FaceAlpha',0.20, 'EdgeColor','none');
plot(ax, x, y, 'LineWidth',1.6);
end

function mu = nanmean_local(X, dim)
if exist('mean','file')==2
    try
        mu = mean(X, dim, 'omitnan');
        return;
    catch
    end
end
n = sum(isfinite(X),dim);
X2 = X; X2(~isfinite(X2)) = 0;
mu = sum(X2,dim) ./ max(1,n);
end

function md = nanmedian_local(X, dim)
% median with omitnan fallback for older toolboxes (MATLAB 2017b safe)

% Try built-in first (works if your toolbox supports omitnan here)
try
    md = median(X, dim, 'omitnan');
    return;
catch
end

sz = size(X);
nd = numel(sz);

% clamp dim
dim = max(1, min(nd, dim));

% Move requested dim to the last dimension
perm = 1:nd;
perm([dim nd]) = [nd dim];   % <-- FIX: use nd, NOT "end" on RHS

Y = permute(X, perm);
Y = reshape(Y, [], sz(dim));

% treat non-finite as NaN
Y(~isfinite(Y)) = NaN;

% sort each row (NaNs go to end)
Y = sort(Y, 2, 'ascend');
n = sum(isfinite(Y), 2);

mdFlat = NaN(size(n));

for i = 1:numel(n)
    ni = n(i);
    if ni <= 0
        continue;
    end

    if mod(ni,2)==1
        k = (ni+1)/2;
        mdFlat(i) = Y(i,k);
    else
        k1 = ni/2;
        k2 = k1 + 1;
        mdFlat(i) = 0.5*(Y(i,k1) + Y(i,k2));
    end
end

Y2 = reshape(mdFlat, sz(perm(1:end-1)));
md = ipermute(Y2, perm);
end

function sd = nanstd_local(X, flag, dim)
if nargin < 2, flag = 0; end
if exist('std','file')==2
    try
        sd = std(X, flag, dim, 'omitnan');
        return;
    catch
    end
end
mu = nanmean_local(X,dim);
muRep = repmat(mu, repSize(size(X),dim));
D = X - muRep;
D(~isfinite(D)) = 0;
n = sum(isfinite(X),dim);
v = sum(D.^2,dim) ./ max(1, (n - (flag==0)));
sd = sqrt(max(0,v));
end

function v = nanvar_local(X, dim)
mu = nanmean_local(X,dim);
muRep = repmat(mu, repSize(size(X),dim));
D = X - muRep;
D(~isfinite(D)) = 0;
n = sum(isfinite(X),dim);
v = sum(D.^2,dim) ./ max(1, (n-1));
v(~isfinite(v)) = 0;
end

function rs = repSize(sz, dim)
rs = ones(1,numel(sz));
rs(dim) = sz(dim);
end

function [t,p] = oneSampleT_TC(TCcell)
X = cat(3, TCcell{:}); % [R x T x N]
mu = nanmean_local(X,3);
sd = nanstd_local(X,0,3);
n  = sum(isfinite(X),3);
se = sd ./ sqrt(max(1,n));
t = mu ./ max(eps,se);
df = max(1,n-1);
if exist('tcdf','file')==2
    p = 2*tcdf(-abs(t),df);
else
    p = ones(size(t));
end
t(~isfinite(t)) = 0;
p(~isfinite(p)) = 1;
end

function [t,p] = twoSampleT_TC(Acell,Bcell)
A = cat(3, Acell{:});
B = cat(3, Bcell{:});
m1 = nanmean_local(A,3); m2 = nanmean_local(B,3);
v1 = nanvar_local(A,3);  v2 = nanvar_local(B,3);
n1 = sum(isfinite(A),3); n2 = sum(isfinite(B),3);
den = sqrt(v1./max(1,n1) + v2./max(1,n2));
t = (m1-m2) ./ max(eps,den);
a = v1./max(1,n1); b = v2./max(1,n2);
df = (a+b).^2 ./ ( (a.^2)./max(1,(n1-1)) + (b.^2)./max(1,(n2-1)) );
df(~isfinite(df)) = 1;
if exist('tcdf','file')==2
    p = 2*tcdf(-abs(t),df);
else
    p = ones(size(t));
end
t(~isfinite(t)) = 0;
p(~isfinite(p)) = 1;
end

function [tMap,pMap,desc] = pairedT_fromTable(subjTable, mapLoaderFcn, b0,b1,s0,s1)
pairs = subjTable(:,4);
conds = subjTable(:,3);

pairs = cellfun(@(x) strtrim(char(x)), pairs, 'UniformOutput',false);
conds = cellfun(@(x) strtrim(char(x)), conds, 'UniformOutput',false);

uPairs = unique(pairs(~cellfun(@isempty,pairs)),'stable');
uConds = unique(conds(~cellfun(@isempty,conds)),'stable');

if numel(uPairs) < 2
    error('Paired test needs PairID filled for matching rows.');
end
if numel(uConds) < 2
    error('Paired test needs at least 2 Condition labels.');
end

condA = uConds{1}; condB = uConds{2};
desc = ['Paired t-test | ' condA ' vs ' condB];

diffMaps = {};
for i = 1:numel(uPairs)
    pid = uPairs{i};
    idxA = find(strcmp(pairs,pid) & strcmp(conds,condA), 1);
    idxB = find(strcmp(pairs,pid) & strcmp(conds,condB), 1);
    if isempty(idxA) || isempty(idxB)
        continue;
    end
    fpA = subjTable{idxA,5};
    fpB = subjTable{idxB,5};
    MA = mapLoaderFcn(fpA,b0,b1,s0,s1);
    MB = mapLoaderFcn(fpB,b0,b1,s0,s1);
    diffMaps{end+1} = double(MA) - double(MB); %#ok<AGROW>
end

if numel(diffMaps) < 2
    error('Not enough paired subjects found for the two conditions.');
end

X = catAlong4(diffMaps);
[tMap,pMap] = oneSampleT_array(X);
end

function [t,p,desc] = pairedT_TC_fromTable(subjTable, tcLoaderFcn)
pairs = subjTable(:,4);
conds = subjTable(:,3);

pairs = cellfun(@(x) strtrim(char(x)), pairs, 'UniformOutput',false);
conds = cellfun(@(x) strtrim(char(x)), conds, 'UniformOutput',false);

uPairs = unique(pairs(~cellfun(@isempty,pairs)),'stable');
uConds = unique(conds(~cellfun(@isempty,conds)),'stable');

if numel(uPairs) < 2
    error('Paired test needs PairID filled.');
end
if numel(uConds) < 2
    error('Need at least 2 conditions.');
end

condA = uConds{1}; condB = uConds{2};
desc = ['Paired t-test | ' condA ' vs ' condB];

diffTC = {};
for i = 1:numel(uPairs)
    pid = uPairs{i};
    idxA = find(strcmp(pairs,pid) & strcmp(conds,condA), 1);
    idxB = find(strcmp(pairs,pid) & strcmp(conds,condB), 1);
    if isempty(idxA) || isempty(idxB), continue; end

    fpA = subjTable{idxA,5};
    fpB = subjTable{idxB,5};
    [TA,~,~] = tcLoaderFcn(fpA);
    [TB,~,~] = tcLoaderFcn(fpB);

    if ~isequal(size(TA),size(TB))
        error('Paired ROI timecourses must have same size (no alignment step here).');
    end

    diffTC{end+1} = double(TA) - double(TB); %#ok<AGROW>
end

if numel(diffTC) < 2
    error('Not enough paired data for conditions.');
end

[t,p] = oneSampleT_TC(diffTC);
end