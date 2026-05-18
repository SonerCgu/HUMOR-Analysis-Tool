function loadDataCallback(src,~)
fig = ancestor(src,'figure');
if isempty(fig) || ~ishghandle(fig)
    error('Could not find Studio figure.');
end
studio = guidata(fig);
startPath = localDefaultStart(studio);
[file,path] = uigetfile({'*.mat;*.nii;*.nii.gz','fUSI Data (*.mat, *.nii, *.nii.gz)'},'Select fUSI dataset',startPath);
if isequal(file,0)
    localLog(fig,'Load cancelled.');
    return;
end
localLog(fig,'Loading dataset...');
localStatus(fig,false);
drawnow;
try
    fullInputFile = fullfile(path,file);
    [data,meta] = loadFUSIData(fullInputFile,[]);
    if ~isstruct(data) || ~isfield(data,'I') || isempty(data.I)
        error('Loaded data does not contain data.I.');
    end
    [probeType,defaultTR] = localDetectProbe(data,meta);
    chosenTR = defaultTR;
    data.TR = chosenTR;
    data.nVols = size(data.I,ndims(data.I));
    data.TotalTimeSec = data.nVols * data.TR;
    data.TotalTimeMin = data.TotalTimeSec / 60;
    data.totalTime = data.TotalTimeSec;
    data.totalTimeMin = data.TotalTimeMin;
    if ~isstruct(meta), meta = struct(); end
    if ~isfield(meta,'rawMetadata') || isempty(meta.rawMetadata), meta.rawMetadata = struct(); end

    [rawRoot,analysedRoot] = localRoots(path);
    localMkdir(analysedRoot);

    datasetName = regexprep(file,'\.nii\.gz$','','ignorecase');
    datasetName = regexprep(datasetName,'\.nii$','','ignorecase');
    datasetName = regexprep(datasetName,'\.mat$','','ignorecase');
    datasetName = regexprep(datasetName,'[^\w\-]+','_');
    datasetName = regexprep(datasetName,'_+','_');
    datasetName = regexprep(datasetName,'^_+|_+$','');
    if isempty(datasetName), datasetName = 'item'; end

    rawRootNorm = strrep(rawRoot,'/',filesep);
    pathNorm = strrep(path,'/',filesep);
    if numel(pathNorm) >= numel(rawRootNorm) && strcmpi(pathNorm(1:numel(rawRootNorm)),rawRootNorm)
        relPath = pathNorm(numel(rawRootNorm)+1:end);
        while ~isempty(relPath) && any(relPath(1)==[filesep '/' char(92)])
            relPath = relPath(2:end);
        end
        datasetFolder = fullfile(analysedRoot,relPath,datasetName);
    else
        datasetFolder = fullfile(analysedRoot,datasetName);
    end

    if exist('studio_load_options_dark_dialog_patch16','file') == 2
        [chosenTR,datasetFolder,cancelled,probeType,defaultTR] = studio_load_options_dark_dialog_patch16(chosenTR,datasetFolder,analysedRoot,datasetName,probeType,defaultTR,data,meta);
        if cancelled
            localLog(fig,'Load cancelled during TR/output-folder selection.');
            localStatus(fig,true);
            return;
        end
    end

    data.TR = chosenTR;
    data.nVols = size(data.I,ndims(data.I));
    data.TotalTimeSec = data.nVols * data.TR;
    data.TotalTimeMin = data.TotalTimeSec / 60;
    data.totalTime = data.TotalTimeSec;
    data.totalTimeMin = data.TotalTimeMin;

    localMkdir(datasetFolder);
    qcFolder = fullfile(datasetFolder,'QC');
    preFolder = fullfile(datasetFolder,'Preprocessing');
    visFolder = fullfile(datasetFolder,'Visualization');
    regFolder = fullfile(datasetFolder,'Registration');
    reg2DFolder = fullfile(datasetFolder,'Registration2D');
    pscFolder = fullfile(datasetFolder,'PSC');
    folders = {qcFolder,preFolder,visFolder,regFolder,reg2DFolder,pscFolder};
    for kk = 1:numel(folders), localMkdir(folders{kk}); end

    studio = guidata(fig);
    studio.datasets = struct();
    data.displayNameFull = localCleanName(datasetName);
    data.sourceFileName = file;
    data.sourcePath = path;
    studio.datasets.raw = data;
    studio.activeDataset = 'raw';
    studio.meta = meta;
    studio.isLoaded = true;
    studio.loadedFile = file;
    studio.loadedPath = path;
    studio.loadedName = datasetName;
    studio.exportPath = datasetFolder;
    studio.registrationPath = regFolder;
    studio.registration2DPath = reg2DFolder;
    studio.visualizationPath = visFolder;
    studio.maskStartPath = visFolder;
    studio.underlayStartPath = reg2DFolder;
    studio.transformStartPath = reg2DFolder;
    studio.pipeline = struct('loadDone',true,'qcDone',false,'preprocDone',false,'pscDone',false,'visualDone',false);

    if isempty(studio.meta) || ~isstruct(studio.meta), studio.meta = struct(); end
    studio.meta.exportPath = datasetFolder;
    studio.meta.savePath = datasetFolder;
    studio.meta.outPath = datasetFolder;
    studio.meta.loadedPath = path;
    studio.meta.loadedFile = fullInputFile;
    studio.meta.registrationPath = regFolder;
    studio.meta.registration2DPath = reg2DFolder;
    studio.meta.visualizationPath = visFolder;
    studio.meta.preprocessingPath = preFolder;
    studio.meta.pscPath = pscFolder;

    guidata(fig,studio);
    localUnlock(fig);
    localRefreshDropdown(fig);

    dims = size(data.I);
    localLog(fig,'---------------------------------------');
    localLog(fig,'DATASET LOADED SUCCESSFULLY');
    localLog(fig,['Input file: ' fullInputFile]);
    localLog(fig,['Loaded name: ' datasetName]);
    localLog(fig,['Dataset folder: ' datasetFolder]);
    if ndims(data.I) == 3
        localLog(fig,sprintf('Dimensions: %d x %d | Volumes: %d',dims(1),dims(2),dims(3)));
    elseif ndims(data.I) >= 4
        localLog(fig,sprintf('Dimensions: %d x %d x %d | Volumes: %d',dims(1),dims(2),dims(3),dims(4)));
    else
        localLog(fig,['Dimensions: ' mat2str(dims)]);
    end
    localLog(fig,['Probe: ' probeType]);
    localLog(fig,sprintf('TR: %.0f ms (%.3f sec)',data.TR*1000,data.TR));
    localLog(fig,sprintf('Total time: %.2f sec',data.TotalTimeSec));
    localLog(fig,'---------------------------------------');
    localStatus(fig,true);
catch ME
    localLog(fig,['LOAD ERROR: ' ME.message]);
    localStatus(fig,true);
    errordlg(ME.message,'Load Failure');
end
end

function localLog(fig,msg)
studio = guidata(fig);
timestamp = datestr(now,'HH:MM:SS');
entry = sprintf('[%s] %s',timestamp,msg);
if isfield(studio,'logBoxJava') && ~isempty(studio.logBoxJava)
    try
        old = char(studio.logBoxJava.getText());
        if isempty(old), newTxt = entry; else, newTxt = [old sprintf('\n') entry]; end
        studio.logBoxJava.setText(newTxt);
        studio.logBoxJava.setCaretPosition(studio.logBoxJava.getDocument().getLength());
        drawnow;
        return;
    catch
    end
end
if isfield(studio,'logBox') && ~isempty(studio.logBox) && ishghandle(studio.logBox)
    cur = get(studio.logBox,'String');
    if isempty(cur), cur = {}; elseif ischar(cur), cur = cellstr(cur); elseif ~iscell(cur), cur = {cur}; end
    if numel(cur)==1 && isempty(strtrim(cur{1})), cur = {}; end
    set(studio.logBox,'String',[cur; {entry}]);
    drawnow;
end
end

function localStatus(fig,isReady)
studio = guidata(fig);
if ~isfield(studio,'statusPanel') || ~ishghandle(studio.statusPanel), return; end
if isReady
    bg = [0.15 0.60 0.20]; label = 'PROGRAM READY';
else
    bg = [0.85 0.20 0.20]; label = 'PROGRAM NOT READY';
end
set(studio.statusPanel,'BackgroundColor',bg,'HighlightColor',bg,'ShadowColor',bg);
if isfield(studio,'statusText') && ishghandle(studio.statusText)
    set(studio.statusText,'BackgroundColor',bg,'ForegroundColor',[1 1 1],'String',label,'FontWeight','bold','FontSize',16);
end
drawnow;
end

function localUnlock(fig)
studio = guidata(fig);
if ~isfield(studio,'allButtons') || isempty(studio.allButtons), return; end
for i = 1:numel(studio.allButtons)
    h = studio.allButtons{i};
    if ~isempty(h) && ishghandle(h)
        try, set(h,'Enable','on','BackgroundColor',[0.25 0.25 0.25]); catch, end
    end
end
guidata(fig,studio);
end

function localRefreshDropdown(fig)
studio = guidata(fig);
dd = findobj(fig,'Tag','datasetDropdown');
if isempty(dd) || ~ishghandle(dd), return; end
keys = fieldnames(studio.datasets);
if isempty(keys)
    set(dd,'String',{'<none>'},'Value',1,'UserData',{{}});
    return;
end
labels = cell(size(keys));
for i = 1:numel(keys)
    labels{i} = localShort(localGetName(studio,keys{i}),85);
end
set(dd,'String',labels,'UserData',keys);
idx = find(strcmp(keys,studio.activeDataset),1);
if isempty(idx), idx = 1; studio.activeDataset = keys{1}; end
set(dd,'Value',idx);
if isfield(studio,'activeDatasetText') && ishghandle(studio.activeDatasetText)
    fullName = localGetName(studio,studio.activeDataset);
    set(studio.activeDatasetText,'String',['ACTIVE DATASET: ' localShort(fullName,85)],'TooltipString',['ACTIVE DATASET: ' fullName]);
end
guidata(fig,studio);
end

function name = localGetName(studio,key)
name = key;
try
    d = studio.datasets.(key);
    if isstruct(d) && isfield(d,'displayNameFull') && ~isempty(d.displayNameFull)
        name = d.displayNameFull;
    end
catch
end
end

function s = localShort(s,n)
if nargin < 2, n = 85; end
if numel(s) > n
    s = [s(1:ceil((n-3)/2)) '...' s(end-floor((n-3)/2)+1:end)];
end
end

function startPath = localDefaultStart(studio)
startPath = pwd;
try
    if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
        startPath = studio.loadedPath;
        return;
    end
catch
end
if ispc
    p = 'Z:\fUS\Project_PACAP_AVATAR_SC\RawData';
    if exist(p,'dir'), startPath = p; end
end
end

function [rawRoot,analysedRoot] = localRoots(inputPath)
p = char(inputPath);
if isempty(p) || exist(p,'dir') ~= 7, p = pwd; end
while numel(p) > 1 && any(p(end)==[filesep '/' char(92)])
    p(end) = [];
end
pf = strrep(p,char(92),'/');
if ~isempty(regexp(pf,'(^|/)RawData(/|$)','once'))
    rr = regexprep(pf,'(^.*?/RawData)(/.*)?$','$1','ignorecase');
    ar = regexprep(rr,'RawData$','AnalysedData','ignorecase');
    rawRoot = strrep(rr,'/',filesep);
    analysedRoot = strrep(ar,'/',filesep);
else
    rawRoot = p;
    analysedRoot = fullfile(p,'AnalysedData');
end
end

function localMkdir(p)
if ~exist(p,'dir'), mkdir(p); end
end

function [probeType,defaultTR] = localDetectProbe(data,meta)
probeType = '2D Probe';
defaultTR = 0.320;
try
    if isstruct(meta) && isfield(meta,'rawMetadata') && isfield(meta.rawMetadata,'probeTypeAutoDetected') && ~isempty(meta.rawMetadata.probeTypeAutoDetected)
        probeType = meta.rawMetadata.probeTypeAutoDetected;
    elseif isstruct(data) && isfield(data,'I') && ndims(data.I) >= 4 && size(data.I,3) > 1
        probeType = 'Matrix (3D) Probe';
        defaultTR = 0.480;
    end
catch
end
end

function name = localCleanName(name)
name = regexprep(name,'^raw_','');
name = regexprep(name,'(^|_)FUS(_|$)','$1$2');
name = regexprep(name,'_+','_');
name = regexprep(name,'^_+|_+$','');
if isempty(name), name = 'dataset'; end
end
