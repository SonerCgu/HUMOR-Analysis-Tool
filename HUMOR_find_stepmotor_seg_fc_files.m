function info = HUMOR_find_stepmotor_seg_fc_files(rootDir)
% Auto-detect step-motor Reg2D, Segmentation, label-map and region-name files.
% MATLAB 2017b compatible.

info = struct();
info.rootDir = '';
info.registration2DDir = '';
info.reg2DFiles = {};
info.labelFile = '';
info.nameFile = '';
info.segmentationFile = '';
info.sourceFile = '';
info.summary = '';

if nargin < 1 || isempty(rootDir) || exist(rootDir,'dir') ~= 7
    return;
end

info.rootDir = rootDir;

reg2DDir = fullfile(rootDir,'Registration2D');
if exist(reg2DDir,'dir') == 7
    info.registration2DDir = reg2DDir;
else
    info.registration2DDir = rootDir;
end

files = localRecursiveFiles(rootDir);
regFiles = {};
segCand = struct('file',{},'score',{},'datenum',{});
labelCand = struct('file',{},'score',{},'datenum',{});
nameCand = struct('file',{},'score',{},'datenum',{});
sourceCand = struct('file',{},'score',{},'datenum',{});

for ii = 1:numel(files)
    f = files{ii};
    nm = lower(localFileName(f));
    ext = lower(localExt(f));
    isMat = strcmp(ext,'.mat');
    isTxt = strcmp(ext,'.txt') || strcmp(ext,'.csv') || strcmp(ext,'.tsv');
    isImgLabel = strcmp(ext,'.nii') || strcmp(ext,'.nii.gz') || strcmp(ext,'.tif') || strcmp(ext,'.tiff');

    if isMat
        if localHasAny(nm,{'coronalregistration2d','stepmotor_reg2d','step_motor_reg2d','reg2d'}) && ...
                ~localHasAny(nm,{'segmentation_','fc_groupbundle','functionalconnectivity_'})
            regFiles{end+1} = f; %#ok<AGROW>
        end

        if localHasAny(nm,{'segmentation_'}) && isempty(strfind(nm,'heatmap'))
            segCand = localAdd(segCand,f,200 + localNameScore(nm,{'segmentation_'}));
        end

        scLab = localNameScore(nm,{'atlasunderlay_regions','atlasregionlabelslr','atlasregionlabels','regionlabels','labelmap','roiatlas','regions','labels','annotation'});
        if scLab > 0 && ~localHasAny(nm,{'histology','histo','underlaydisplay','raw_underlay','functionalconnectivity'})
            labelCand = localAdd(labelCand,f,scLab);
        end

        scName = localNameScore(nm,{'segmentation_regiontable','regiontable','region_names','regionnames','inforegions','roi_names','roinames','allen'});
        if scName > 0
            nameCand = localAdd(nameCand,f,scName);
        end

        scSrc = localNameScore(nm,{'assembled','stepmotor','step_motor','registered_functional','registered_to_atlas','newdata','data'});
        if scSrc > 0 && ~localHasAny(nm,{'segmentation_','coronalregistration2d','reg2d','fc_groupbundle'})
            sourceCand = localAdd(sourceCand,f,scSrc);
        end

    elseif isTxt
        scName = localNameScore(nm,{'segmentation_regiontable','regiontable','region_names','regionnames','inforegions','labels','allen','acr','acronym'});
        if scName > 0
            nameCand = localAdd(nameCand,f,scName);
        end
    elseif isImgLabel
        scLab = localNameScore(nm,{'label','labels','regions','atlas','annotation'});
        if scLab > 0
            labelCand = localAdd(labelCand,f,scLab);
        end
    end
end

info.reg2DFiles = localSortReg2D(regFiles);
info.segmentationFile = localPickBest(segCand);
info.labelFile = localPickBest(labelCand);
info.nameFile = localPickBest(nameCand);
info.sourceFile = localPickBest(sourceCand);

info.summary = sprintf('Reg2D=%d | Seg=%s | Labels=%s | Names=%s', ...
    numel(info.reg2DFiles), localShort(info.segmentationFile), localShort(info.labelFile), localShort(info.nameFile));
end

function files = localRecursiveFiles(rootDir)
files = {};
d = dir(rootDir);
for ii = 1:numel(d)
    nm = d(ii).name;
    if strcmp(nm,'.') || strcmp(nm,'..')
        continue;
    end
    fp = fullfile(rootDir,nm);
    if d(ii).isdir
        sub = localRecursiveFiles(fp);
        files = [files sub]; %#ok<AGROW>
    else
        files{end+1} = fp; %#ok<AGROW>
    end
end
end

function tf = localHasAny(s,keys)
tf = false;
for kk = 1:numel(keys)
    if ~isempty(strfind(s,lower(keys{kk})))
        tf = true;
        return;
    end
end
end

function score = localNameScore(s,keys)
score = 0;
for kk = 1:numel(keys)
    if ~isempty(strfind(s,lower(keys{kk})))
        score = score + 20 + max(0,20-kk);
    end
end
end

function C = localAdd(C,f,score)
dn = 0;
try
    dd = dir(f);
    if ~isempty(dd), dn = dd(1).datenum; end
catch
end
n = numel(C) + 1;
C(n).file = f;
C(n).score = score;
C(n).datenum = dn;
end

function f = localPickBest(C)
f = '';
if isempty(C), return; end
scores = zeros(numel(C),1);
dn = zeros(numel(C),1);
for ii = 1:numel(C)
    scores(ii) = C(ii).score;
    dn(ii) = C(ii).datenum;
end
[~,ord] = sortrows([-scores -dn]);
f = C(ord(1)).file;
end

function filesOut = localSortReg2D(filesIn)
filesOut = filesIn;
if isempty(filesIn), return; end
idx = nan(numel(filesIn),1);
for ii = 1:numel(filesIn)
    idx(ii) = localParseSourceIndex(filesIn{ii});
    if ~isfinite(idx(ii)), idx(ii) = ii + 1e6; end
end
[~,ord] = sort(idx);
filesOut = filesIn(ord);
end

function idx = localParseSourceIndex(s)
idx = NaN;
s = lower(char(s));
tok = regexp(s,'source[_\-\s]*0*([0-9]+)','tokens','once');
if isempty(tok)
    tok = regexp(s,'slice[_\-\s]*0*([0-9]+)','tokens','once');
end
if isempty(tok)
    tok = regexp(s,'z[_\-\s]*0*([0-9]+)','tokens','once');
end
if ~isempty(tok)
    idx = str2double(tok{1});
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

function ext = localExt(f)
if numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz')
    ext = '.nii.gz';
else
    [~,~,ext] = fileparts(f);
end
end

function s = localShort(f)
if isempty(f)
    s = 'none';
else
    s = localFileName(f);
end
end
