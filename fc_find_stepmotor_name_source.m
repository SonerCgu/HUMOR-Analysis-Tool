function info = fc_find_stepmotor_name_source(folder)
% Detect step-motor FC/Segmentation helper files from selected folder.
info = struct();
info.folder = '';
info.nameFile = '';
info.labelFile = '';
info.segmentationFile = '';
info.summary = '';
if nargin < 1 || isempty(folder) || exist(folder,'dir') ~= 7, return; end
info.folder = folder;
files = localFiles(folder);
nameCand = struct('file',{},'score',{},'dn',{});
labelCand = struct('file',{},'score',{},'dn',{});
segCand = struct('file',{},'score',{},'dn',{});
for k = 1:numel(files)
    f = files{k};
    nm = lower(localShort(f));
    ext = localExt(f);
    isMat = strcmp(ext,'.mat');
    isTxt = strcmp(ext,'.txt') || strcmp(ext,'.csv') || strcmp(ext,'.tsv');
    isVol = strcmp(ext,'.nii') || strcmp(ext,'.nii.gz') || strcmp(ext,'.tif') || strcmp(ext,'.tiff');
    if isMat && ~isempty(strfind(nm,'segmentation_'))
        segCand = localAdd(segCand,f,300);
        nameCand = localAdd(nameCand,f,260);
    end
    if isTxt || isMat
        scN = localScore(nm,{'segmentation_regiontable','regiontable','region_table','region_names','regionnames','roi_names','roinames','inforegions','atlas_regions','atlasunderlay_regions','labels_names','names','acronym'});
        if scN > 0
            nameCand = localAdd(nameCand,f,scN);
        end
    end
    if isMat || isVol
        scL = localScore(nm,{'atlasregionlabelslr2d','atlasregionlabels2d','atlasregionlabelslr','regionlabelslr','regionlabels','labelmap','label_map','annotation','roi_atlas','roiatlas','atlas_labels','labels','regions'});
        if scL > 0 && isempty(strfind(nm,'region_names')) && isempty(strfind(nm,'regiontable'))
            labelCand = localAdd(labelCand,f,scL);
        end
    end
end
info.nameFile = localPick(nameCand);
info.labelFile = localPick(labelCand);
info.segmentationFile = localPick(segCand);
if isempty(info.nameFile) && ~isempty(info.segmentationFile), info.nameFile = info.segmentationFile; end
info.summary = sprintf('Names=%s | Labels=%s | Seg=%s',localShort2(info.nameFile),localShort2(info.labelFile),localShort2(info.segmentationFile));
end

function files = localFiles(folder)
files = {};
d = dir(folder);
for i = 1:numel(d)
    nm = d(i).name;
    if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
    f = fullfile(folder,nm);
    if d(i).isdir
        sub = localFiles(f);
        files = [files sub]; %#ok<AGROW>
    else
        files{end+1} = f; %#ok<AGROW>
    end
end
end

function sc = localScore(nm,keys)
sc = 0;
for i = 1:numel(keys)
    if ~isempty(strfind(nm,lower(keys{i})))
        sc = sc + 100 - i;
    end
end
end

function C = localAdd(C,f,score)
dn = 0;
try, d = dir(f); if ~isempty(d), dn = d(1).datenum; end, catch, end
n = numel(C)+1;
C(n).file = f;
C(n).score = score;
C(n).dn = dn;
end

function f = localPick(C)
f = '';
if isempty(C), return; end
s = zeros(numel(C),1); dn = zeros(numel(C),1);
for i = 1:numel(C), s(i)=C(i).score; dn(i)=C(i).dn; end
[~,ord] = sortrows([-s -dn]);
f = C(ord(1)).file;
end

function ext = localExt(f)
if numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz')
    ext = '.nii.gz';
else
    [~,~,ext] = fileparts(f); ext = lower(ext);
end
end

function nm = localShort(f)
[~,a,b] = fileparts(f);
if strcmpi(b,'.gz')
    [~,a2,b2] = fileparts(a); nm = [a2 b2 b];
else
    nm = [a b];
end
end

function nm = localShort2(f)
if isempty(f), nm = 'none'; else, nm = localShort(f); end
end
