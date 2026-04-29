function RegOut = coreg(studio, mode)
% coreg.m
% Unified atlas-registration launcher
%
% Updated robust version
%   - MATLAB 2017b + 2023b compatible
%   - ASCII-safe
%   - Pure MATLAB source selector (no Java list dependency)
%   - Launches Simple 2D coronal or Complex 3D atlas registration
%
% Usage:
%   RegOut = coreg(studio)
%   RegOut = coreg(studio,'2d')
%   RegOut = coreg(studio,'3d')

RegOut = [];

if nargin < 1 || isempty(studio) || ~isstruct(studio)
    error('A valid studio struct is required.');
end

if nargin < 2
    mode = '';
end

if ~isempty(mode)
    cfg = struct();
    cfg.mode = normalizeCoregMode(mode);
    cfg.sourceFile = '';
else
    [cfg, ok] = showUnifiedCoregLauncher(studio);
    if ~ok
        return;
    end
end

switch cfg.mode
    case '2d'
        if exist('coreg_coronal_2d','file') ~= 2
            error('coreg_coronal_2d.m not found.');
        end
        RegOut = coreg_coronal_2d(studio, cfg.sourceFile);

    case '3d'
        if exist('coreg_3d','file') ~= 2
            error(['coreg_3d.m not found.' char(10) ...
                   'Save your complex 3D coreg code as coreg_3d.m.']);
        end
        RegOut = coreg_3d(studio, cfg.sourceFile);

    otherwise
        error('Unknown registration mode.');
end
end


%% =======================================================================
% Unified launcher GUI
%% =======================================================================
function [cfg, ok] = showUnifiedCoregLauncher(studio)

ok = false;
cfg = struct();
cfg.mode = '2d';
cfg.sourceFile = '';

[fileList, labelList] = collectCoregSourceCandidates(studio);
if isempty(fileList)
    fileList = {''};
    labelList = {'AUTO / FALLBACK: no filtered source found'};
end

defaultIdx = chooseDefaultCandidateIndex(labelList);

bg      = [0.045 0.045 0.050];
panel   = [0.085 0.085 0.095];
panel2  = [0.120 0.120 0.135];
fg      = [0.96 0.96 0.96];
fgDim   = [0.72 0.72 0.76];
blue    = [0.20 0.48 0.95];
green   = [0.15 0.68 0.35];
red     = [0.80 0.25 0.25];

scr = get(0,'ScreenSize');
dlgW = min(1520, scr(3)-80);
dlgH = min(900,  scr(4)-80);
dlgX = max(40, floor((scr(3)-dlgW)/2));
dlgY = max(40, floor((scr(4)-dlgH)/2));

dlg = figure( ...
    'Name','Atlas Registration Launcher', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Resize','off', ...
    'Units','pixels', ...
    'Position',[dlgX dlgY dlgW dlgH], ...
    'WindowStyle','modal', ...
    'CloseRequestFcn',@onCancel, ...
    'KeyPressFcn',@onKey);

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.03 0.925 0.65 0.055], ...
    'String','Atlas Registration', ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',26, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.03 0.885 0.91 0.035], ...
    'String','Choose registration mode and a source image. For step-motor data use Simple 2D coronal registration.', ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fgDim, ...
    'FontName','Arial', ...
    'FontSize',13, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

modePanel = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.03 0.775 0.94 0.095], ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'Title','Registration mode', ...
    'FontName','Arial', ...
    'FontSize',14, ...
    'FontWeight','bold');

hMode = uicontrol('Parent',modePanel,'Style','popupmenu', ...
    'Units','normalized', ...
    'Position',[0.03 0.24 0.32 0.46], ...
    'String',{'Simple 2D coronal registration','Complex 3D atlas registration'}, ...
    'Value',1, ...
    'BackgroundColor',panel2, ...
    'ForegroundColor',fg, ...
    'FontName','Arial', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'Callback',@onModeChanged);

hModeHelp = uicontrol('Parent',modePanel,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.38 0.16 0.58 0.60], ...
    'String','', ...
    'BackgroundColor',panel, ...
    'ForegroundColor',[0.80 0.92 1.00], ...
    'FontName','Arial', ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left');

legendPanel = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.03 0.725 0.94 0.035], ...
    'BackgroundColor',bg, ...
    'BorderType','none');

makeLegendText(legendPanel, 0.00, '[BRAINIMAGE]', [1.00 0.55 0.75]);
makeLegendText(legendPanel, 0.13, '[UNDERLAY]',   [0.45 0.78 1.00]);
makeLegendText(legendPanel, 0.25, '[OVERLAY]',    [1.00 0.70 0.35]);
makeLegendText(legendPanel, 0.36, '[MASK]',       [0.55 1.00 0.65]);
makeLegendText(legendPanel, 0.45, '[ANATOMY]',    [0.90 0.80 1.00]);
makeLegendText(legendPanel, 0.56, '[SOURCE]',     [0.95 0.95 0.95]);

listPanel = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.03 0.16 0.94 0.55], ...
    'BackgroundColor',panel, ...
    'ForegroundColor',fg, ...
    'Title','Source / anatomy file', ...
    'FontName','Arial', ...
    'FontSize',14, ...
    'FontWeight','bold');

hList = uicontrol('Parent',listPanel,'Style','listbox', ...
    'Units','normalized', ...
    'Position',[0.02 0.12 0.96 0.84], ...
    'String',labelList, ...
    'Value',defaultIdx, ...
    'BackgroundColor',[0 0 0], ...
    'ForegroundColor',[1 1 1], ...
    'FontName','Consolas', ...
    'FontSize',13, ...
    'Max',1, ...
    'Min',0, ...
    'Callback',@onListClick);

hSelected = uicontrol('Parent',listPanel,'Style','edit', ...
    'Units','normalized', ...
    'Position',[0.02 0.02 0.96 0.075], ...
    'String','', ...
    'Max',2, ...
    'Min',0, ...
    'Enable','inactive', ...
    'BackgroundColor',[0.03 0.03 0.035], ...
    'ForegroundColor',[0.70 1.00 0.80], ...
    'FontName','Consolas', ...
    'FontSize',11, ...
    'HorizontalAlignment','left');

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'String','Refresh List', ...
    'Units','normalized', ...
    'Position',[0.03 0.055 0.14 0.065], ...
    'BackgroundColor',blue, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',13, ...
    'FontWeight','bold', ...
    'Callback',@onRefresh);

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'String','Start Registration', ...
    'Units','normalized', ...
    'Position',[0.67 0.050 0.18 0.075], ...
    'BackgroundColor',green, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'Callback',@onStart);

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'String','Cancel', ...
    'Units','normalized', ...
    'Position',[0.865 0.050 0.105 0.075], ...
    'BackgroundColor',red, ...
    'ForegroundColor','w', ...
    'FontName','Arial', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'Callback',@onCancel);

updateSelectedText();
onModeChanged();
uiwait(dlg);

    function makeLegendText(parent, x, str, col)
        uicontrol('Parent',parent,'Style','text', ...
            'Units','normalized', ...
            'Position',[x 0.05 0.12 0.80], ...
            'String',str, ...
            'BackgroundColor',bg, ...
            'ForegroundColor',col, ...
            'FontName','Arial', ...
            'FontSize',11, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    end

    function onModeChanged(~,~)
        v = get(hMode,'Value');
        if v == 1
            set(hModeHelp,'String', ...
                '2D coronal mode: recommended for Mask Editor brainImage, underlay/overlay masks, step-motor slices, and simple atlas visualization.');
        else
            set(hModeHelp,'String', ...
                '3D mode: use only when the selected source is a true 3D anatomical volume. For step-motor data, prefer slice-wise 2D.');
        end
    end

    function onListClick(~,~)
        updateSelectedText();
        try
            if strcmpi(get(dlg,'SelectionType'),'open')
                onStart();
            end
        catch
        end
    end

    function idx = getSelectedIndex()
        idx = get(hList,'Value');
        if isempty(idx) || ~isfinite(idx) || idx < 1
            idx = 1;
        end
        idx = max(1, min(numel(fileList), round(idx)));
    end

    function updateSelectedText()
        idx = getSelectedIndex();
        if isempty(fileList{idx})
            txt = 'Selected: AUTO / fallback';
        else
            txt = ['Selected: ' fileList{idx}];
        end
        if ishandle(hSelected)
            set(hSelected,'String',txt);
        end
    end

    function onRefresh(~,~)
        [fileList, labelList] = collectCoregSourceCandidates(studio);
        if isempty(fileList)
            fileList = {''};
            labelList = {'AUTO / FALLBACK: no filtered source found'};
        end
        defaultIdx = chooseDefaultCandidateIndex(labelList);
        set(hList,'String',labelList,'Value',defaultIdx);
        updateSelectedText();
    end

    function onStart(~,~)
        idx = getSelectedIndex();
        modeVal = get(hMode,'Value');
        if modeVal == 1
            cfg.mode = '2d';
        else
            cfg.mode = '3d';
        end
        cfg.sourceFile = fileList{idx};
        ok = true;
        try, uiresume(dlg); catch, end
        try, delete(dlg); catch, end
    end

    function onCancel(~,~)
        ok = false;
        cfg.mode = '2d';
        cfg.sourceFile = '';
        try, uiresume(dlg); catch, end
        try, delete(dlg); catch, end
    end

    function onKey(~,ev)
        try
            if strcmpi(ev.Key,'escape')
                onCancel();
            elseif strcmpi(ev.Key,'return') || strcmpi(ev.Key,'enter')
                onStart();
            end
        catch
        end
    end
end


%% =======================================================================
% Candidate collection
%% =======================================================================
function [fileList, labelList] = collectCoregSourceCandidates(studio)

fileList = {};
labelList = {};

rawFolder = '';
if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
    rawFolder = studio.loadedPath;
end

analysedFolder = '';
if isfield(studio,'exportPath') && ~isempty(studio.exportPath) && exist(studio.exportPath,'dir')
    analysedFolder = studio.exportPath;
end
if isempty(analysedFolder)
    analysedFolder = inferAnalysedFromRaw(rawFolder);
end

registration3D = '';
registration2D = '';
if ~isempty(analysedFolder)
    registration3D = fullfile(analysedFolder,'Registration');
    registration2D = fullfile(analysedFolder,'Registration2D');
end

directFiles = {};
if isfield(studio,'brainImageFile') && ~isempty(studio.brainImageFile) && exist(studio.brainImageFile,'file') == 2
    directFiles{end+1} = studio.brainImageFile; %#ok<AGROW>
end
if isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
    lf = studio.loadedFile;
    if exist(lf,'file') == 2
        directFiles{end+1} = lf; %#ok<AGROW>
    elseif ~isempty(rawFolder)
        cand = fullfile(rawFolder, lf);
        if exist(cand,'file') == 2
            directFiles{end+1} = cand; %#ok<AGROW>
        end
    end
end

for i = 1:numel(directFiles)
    [fileList, labelList] = addCandidate(fileList, labelList, directFiles{i}, rawFolder, analysedFolder, registration3D, registration2D, true);
end

searchFolders = { ...
    rawFolder, ...
    fullfile(rawFolder,'Visualization'), ...
    fullfile(rawFolder,'visualization'), ...
    fullfile(rawFolder,'Visualisation'), ...
    fullfile(rawFolder,'Mask'), ...
    fullfile(rawFolder,'Masks'), ...
    analysedFolder, ...
    fullfile(analysedFolder,'Visualization'), ...
    fullfile(analysedFolder,'visualization'), ...
    fullfile(analysedFolder,'Visualisation'), ...
    fullfile(analysedFolder,'Mask'), ...
    fullfile(analysedFolder,'Masks'), ...
    registration2D, ...
    registration3D};

searchFolders = cleanFolderCell(searchFolders);
skipTerms = getCoregSkipFolderTerms();

for i = 1:numel(searchFolders)
    filesHere = collectFilesRecursiveFiltered(searchFolders{i}, skipTerms);
    for k = 1:numel(filesHere)
        [fileList, labelList] = addCandidate(fileList, labelList, filesHere{k}, rawFolder, analysedFolder, registration3D, registration2D, false);
    end
end

if isempty(fileList)
    return;
end

keys = cell(size(fileList));
for i = 1:numel(fileList)
    keys{i} = normalizePathKey(fileList{i});
end
[~, ia] = unique(keys,'stable');
fileList = fileList(ia);
labelList = labelList(ia);

[fileList, labelList] = sortCoregCandidates(fileList, labelList);
end


function [fileList, labelList] = addCandidate(fileList, labelList, fp, rawRoot, analysedRoot, reg3D, reg2D, forceAdd)
if isempty(fp) || exist(fp,'file') ~= 2
    return;
end
if nargin < 8
    forceAdd = false;
end
if ~forceAdd && ~isCoregSourceCandidate(fp)
    return;
end
fileList{end+1} = fp; %#ok<AGROW>
labelList{end+1} = makeCoregDisplayName(fp, rawRoot, analysedRoot, reg3D, reg2D); %#ok<AGROW>
end


function tf = isCoregSourceCandidate(fp)
tf = false;
[folder,nm,ext] = fileparts(fp);
folderL = lower(folder);
nameL = lower(nm);
fullL = lower([nm ext]);

if pathHasAnyTerm(folderL, getCoregSkipFolderTerms())
    return;
end

badNames = {'transformation','coronalregistration2d','allen_brain_atlas','registered_to_atlas', ...
    'warpeddata','framerate','frame_rate','rejection','dvars','timeseries','trace','plot', ...
    'histogram','heatmap','qc','pca','ica','despike','scrub','filter','temporal','powerpoint','video'};

if nameHasAnyTerm(nameL, badNames)
    return;
end
if strcmpi(fullL,'transformation.mat') || strcmpi(fullL,'allen_brain_atlas.mat')
    return;
end
if ~(isImageFileLocal(fp) || isNiftiFileLocal(fp) || strcmpi(ext,'.mat'))
    return;
end

goodTerms = getCoregGoodNameTerms();
if nameHasAnyTerm(nameL, goodTerms)
    tf = true;
    return;
end
if folderLooksCoregSourceLike(folderL)
    tf = true;
    return;
end
if strcmpi(ext,'.mat') && matHasPreferredSourceVars(fp)
    tf = true;
end
end


function tf = matHasPreferredSourceVars(matFile)
tf = false;
try
    info = whos('-file', matFile);
    goodTerms = getCoregGoodNameTerms();
    for i = 1:numel(info)
        nm = lower(info(i).name);
        cl = info(i).class;
        sz = info(i).size;
        if nameHasAnyTerm(nm, goodTerms)
            if strcmp(cl,'struct')
                tf = true;
                return;
            end
            if isNumericClassName(cl) && numel(sz) >= 2 && numel(sz) <= 4 && prod(double(sz)) > 100
                tf = true;
                return;
            end
        end
    end
catch
    tf = false;
end
end


function tf = isNumericClassName(cl)
tf = strcmp(cl,'double') || strcmp(cl,'single') || strcmp(cl,'uint16') || ...
     strcmp(cl,'uint8') || strcmp(cl,'int16') || strcmp(cl,'logical');
end


function files = collectFilesRecursiveFiltered(rootDir, skipTerms)
files = {};
if isempty(rootDir) || exist(rootDir,'dir') ~= 7
    return;
end

d = dir(rootDir);
for i = 1:numel(d)
    nm = d(i).name;
    fp = fullfile(rootDir,nm);
    if d(i).isdir
        if strcmp(nm,'.') || strcmp(nm,'..')
            continue;
        end
        if pathHasAnyTerm(lower(fp), skipTerms)
            continue;
        end
        sub = collectFilesRecursiveFiltered(fp, skipTerms);
        if ~isempty(sub)
            files = [files sub]; %#ok<AGROW>
        end
    else
        if isImageFileLocal(fp) || isNiftiFileLocal(fp) || endsWithLowerLocal(fp,'.mat')
            files{end+1} = fp; %#ok<AGROW>
        end
    end
end
end


function folders = cleanFolderCell(folders)
out = {};
for i = 1:numel(folders)
    f = folders{i};
    if isempty(f), continue; end
    if exist(f,'dir') == 7
        out{end+1} = f; %#ok<AGROW>
    end
end
if isempty(out)
    folders = {};
    return;
end
keys = cell(size(out));
for i = 1:numel(out)
    keys{i} = normalizePathKey(out{i});
end
[~, ia] = unique(keys,'stable');
folders = out(ia);
end


function idx = chooseDefaultCandidateIndex(labels)
idx = 1;
priorityTerms = {'brainimage','brainonly','underlay','overlay','mask','anatomical','histology','vascular'};
for p = 1:numel(priorityTerms)
    for i = 1:numel(labels)
        if ~isempty(strfind(lower(labels{i}), priorityTerms{p})) %#ok<STREMP>
            idx = i;
            return;
        end
    end
end
end


function [fileListOut, labelListOut] = sortCoregCandidates(fileList, labelList)
prio = zeros(numel(labelList),1);
for i = 1:numel(labelList)
    s = lower(labelList{i});
    if ~isempty(strfind(s,'brainimage')) || ~isempty(strfind(s,'brainonly')) %#ok<STREMP>
        prio(i) = 1;
    elseif ~isempty(strfind(s,'underlay')) %#ok<STREMP>
        prio(i) = 2;
    elseif ~isempty(strfind(s,'overlay')) %#ok<STREMP>
        prio(i) = 3;
    elseif ~isempty(strfind(s,'mask')) %#ok<STREMP>
        prio(i) = 4;
    elseif ~isempty(strfind(s,'anatom')) || ~isempty(strfind(s,'reference')) %#ok<STREMP>
        prio(i) = 5;
    else
        prio(i) = 9;
    end
end
[~, ord] = sort(prio,'ascend');
fileListOut = fileList(ord);
labelListOut = labelList(ord);
end


function s = makeCoregDisplayName(fp, rawRoot, analysedRoot, reg3D, reg2D)
tag = classifyCoregFile(fp);
try
    if ~isempty(reg2D) && strncmpi(fp, reg2D, numel(reg2D))
        rel = fp(numel(reg2D)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = sprintf('[%s] REG2D: %s', tag, rel);
        return;
    end
catch
end
try
    if ~isempty(reg3D) && strncmpi(fp, reg3D, numel(reg3D))
        rel = fp(numel(reg3D)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = sprintf('[%s] REG3D: %s', tag, rel);
        return;
    end
catch
end
try
    if ~isempty(analysedRoot) && strncmpi(fp, analysedRoot, numel(analysedRoot))
        rel = fp(numel(analysedRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = sprintf('[%s] ANA: %s', tag, rel);
        return;
    end
catch
end
try
    if ~isempty(rawRoot) && strncmpi(fp, rawRoot, numel(rawRoot))
        rel = fp(numel(rawRoot)+1:end);
        if ~isempty(rel) && rel(1)==filesep, rel = rel(2:end); end
        s = sprintf('[%s] RAW: %s', tag, rel);
        return;
    end
catch
end
s = sprintf('[%s] %s', tag, fp);
end


function tag = classifyCoregFile(fp)
[~,nm,~] = fileparts(fp);
s = lower(nm);
if ~isempty(strfind(s,'brainimage')) || ~isempty(strfind(s,'brainonly')) %#ok<STREMP>
    tag = 'BRAINIMAGE';
elseif ~isempty(strfind(s,'underlay')) %#ok<STREMP>
    tag = 'UNDERLAY';
elseif ~isempty(strfind(s,'overlay')) %#ok<STREMP>
    tag = 'OVERLAY';
elseif ~isempty(strfind(s,'mask')) %#ok<STREMP>
    tag = 'MASK';
elseif ~isempty(strfind(s,'histology')) %#ok<STREMP>
    tag = 'HISTOLOGY';
elseif ~isempty(strfind(s,'vascular')) %#ok<STREMP>
    tag = 'VASCULAR';
elseif ~isempty(strfind(s,'anatom')) || ~isempty(strfind(s,'reference')) %#ok<STREMP>
    tag = 'ANATOMY';
else
    tag = 'SOURCE';
end
end


function modeOut = normalizeCoregMode(modeIn)
modeIn = lower(strtrim(char(modeIn)));
switch modeIn
    case {'2d','simple','simple2d','coronal','coronal2d'}
        modeOut = '2d';
    case {'3d','complex','complex3d','volume','volumetric'}
        modeOut = '3d';
    otherwise
        error('Unknown mode. Use ''2d'' or ''3d''.');
end
end


function terms = getCoregGoodNameTerms()
terms = {'underlay','overlay','brainimage','brain_image','brainonly','brain_only', ...
    'brainmask','brain_mask','mask','anatom','anatomical','reference','histology','vascular'};
end


function terms = getCoregSkipFolderTerms()
terms = {[filesep '.git' filesep], [filesep 'qc' filesep], [filesep 'scm' filesep], ...
    [filesep 'roi' filesep], [filesep 'video' filesep], [filesep 'videos' filesep], ...
    [filesep 'ppt' filesep], [filesep 'powerpoint' filesep], [filesep 'presentation' filesep], ...
    [filesep 'presentations' filesep], [filesep 'temp' filesep], [filesep 'tmp' filesep], ...
    [filesep 'logs' filesep]};
end


function tf = folderLooksCoregSourceLike(folderL)
terms = {[filesep 'visualization'], [filesep 'visualisation'], [filesep 'mask'], ...
    [filesep 'masks'], [filesep 'registration2d'], [filesep 'registration']};
tf = pathHasAnyTerm(folderL, terms);
end


function tf = pathHasAnyTerm(pathStr, terms)
tf = false;
pathStr = lower(pathStr);
for i = 1:numel(terms)
    if ~isempty(strfind(pathStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end
end


function tf = nameHasAnyTerm(nameStr, terms)
tf = false;
nameStr = lower(nameStr);
for i = 1:numel(terms)
    if ~isempty(strfind(nameStr, lower(terms{i}))) %#ok<STREMP>
        tf = true;
        return;
    end
end
end


function tf = isImageFileLocal(f)
f = lower(char(f));
tf = endsWithLowerLocal(f,'.png') || endsWithLowerLocal(f,'.jpg') || ...
     endsWithLowerLocal(f,'.jpeg') || endsWithLowerLocal(f,'.tif') || ...
     endsWithLowerLocal(f,'.tiff') || endsWithLowerLocal(f,'.bmp');
end


function tf = isNiftiFileLocal(f)
f = lower(char(f));
tf = endsWithLowerLocal(f,'.nii') || endsWithLowerLocal(f,'.nii.gz');
end


function tf = endsWithLowerLocal(str, suffix)
str = lower(char(str));
suffix = lower(char(suffix));
if numel(str) < numel(suffix)
    tf = false;
    return;
end
tf = strcmp(str(end-numel(suffix)+1:end), suffix);
end


function k = normalizePathKey(p)
if isempty(p)
    k = '';
    return;
end
try
    p = char(java.io.File(p).getCanonicalPath());
catch
    p = char(p);
end
p = strrep(p, '/', filesep);
p = strrep(p, '\\', filesep);
if ispc
    p = lower(p);
end
k = p;
end


function out = inferAnalysedFromRaw(rawFolder)
out = '';
if isempty(rawFolder)
    return;
end
cand = strrep(rawFolder, [filesep 'RawData' filesep], [filesep 'AnalysedData' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
    return;
end
cand = strrep(rawFolder, [filesep 'rawdata' filesep], [filesep 'analyseddata' filesep]);
if ~strcmp(cand, rawFolder) && exist(cand,'dir')
    out = cand;
end
end
