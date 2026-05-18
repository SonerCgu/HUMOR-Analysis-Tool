function Uplane = HUMOR_pickReg2DUnderlayField(matFile, T, outSize2, contextTag)
% HUMOR_pickReg2DUnderlayField
% Chooses which target-space underlay to use after atlas warp.
% Supports histology / vascular / atlas regions / registered target.

if nargin < 2, T = struct(); end
if nargin < 3 || isempty(outSize2), outSize2 = []; end
if nargin < 4 || isempty(contextTag), contextTag = 'Atlas warp'; end

Uplane = [];

if isempty(matFile) || exist(matFile,'file') ~= 2
    return;
end

try
    L = load(matFile);
catch
    return;
end

try
    mode = getappdata(0,'HUMOR_ATLAS_UNDERLAY_MODE');
catch
    mode = '';
end

if isempty(mode)
    opts = {'Regions / atlas labels', 'Vascular / vessels', 'Histology', 'Registered target underlay'};
    mode = '';
    try
        [idx,ok] = listdlg('PromptString',{'Choose atlas-space underlay for functional warp:','This choice is reused for this MATLAB session.'}, ...
            'SelectionMode','single', ...
            'ListString',opts, ...
            'InitialValue',3, ...
            'Name',[char(contextTag) ' underlay'], ...
            'ListSize',[360 130]);
        if ok && ~isempty(idx)
            mode = opts{idx};
        end
    catch
    end
    if isempty(mode)
        try
            idx = menu('Choose atlas-space underlay after warp', opts{:});
            if idx >= 1 && idx <= numel(opts), mode = opts{idx}; end
        catch
        end
    end
    if isempty(mode)
        mode = 'Registered target underlay';
    end
    try, setappdata(0,'HUMOR_ATLAS_UNDERLAY_MODE',mode); catch, end
end

cands = struct('path',{},'value',{},'score',{});
cands = collectCandidates(L,'',0,cands);
if isstruct(T)
    cands = collectCandidates(T,'T',0,cands);
end

if isempty(cands)
    return;
end

for i = 1:numel(cands)
    cands(i).score = scoreCandidate(cands(i).path, cands(i).value, mode);
end

scores = [cands.score];
[bestScore,bestIdx] = max(scores);
if isempty(bestIdx) || ~isfinite(bestScore) || bestScore < 0
    return;
end

Uplane = toPlane(cands(bestIdx).value, outSize2);
if isempty(Uplane)
    return;
end

Uplane = double(Uplane);
Uplane(~isfinite(Uplane)) = 0;

if max(Uplane(:)) > min(Uplane(:))
    Uplane = (Uplane - min(Uplane(:))) ./ max(eps, max(Uplane(:)) - min(Uplane(:)));
end

try
    fprintf('[HUMoR atlas warp] Underlay mode: %s | field: %s | file: %s\n', mode, cands(bestIdx).path, matFile);
catch
end

end

function cands = collectCandidates(v, pathStr, depth, cands)
if depth > 5, return; end

if isnumeric(v) || islogical(v)
    if looksLikeImage(v)
        c.path = pathStr;
        c.value = v;
        c.score = 0;
        cands(end+1) = c;
    end
    return;
end

if isstruct(v)
    fn = fieldnames(v);
    for k = 1:numel(fn)
        f = fn{k};
        if isempty(pathStr)
            p2 = f;
        else
            p2 = [pathStr '.' f];
        end
        try
            cands = collectCandidates(v.(f), p2, depth+1, cands);
        catch
        end
    end
end
end

function tf = looksLikeImage(A)
tf = false;
try
    if isempty(A) || isvector(A) || isscalar(A)
        return;
    end
    sz = size(A);
    if numel(sz) < 2 || sz(1) < 16 || sz(2) < 16
        return;
    end
    if numel(A) < 256
        return;
    end
    if ndims(A) > 4
        return;
    end
    tf = true;
catch
    tf = false;
end
end

function sc = scoreCandidate(pathStr, A, mode)
sc = 0;
p = lower(pathStr);
m = lower(mode);

bad = {'transform','affine','matrix','warp','tform','inverse','movingpoints','fixedpoints','points','landmark'};
for i = 1:numel(bad)
    if ~isempty(strfind(p,bad{i})) && numel(A) < 100000
        sc = sc - 200;
    end
end

if ~isempty(strfind(m,'region'))
    keys = {'region','annotation','label','allen','atlaslabel','atlas_labels','ccf'};
elseif ~isempty(strfind(m,'vascular'))
    keys = {'vascular','vessel','vasculature','angiography','angio','doppler'};
elseif ~isempty(strfind(m,'histology'))
    keys = {'histology','histo','fixed','target','underlay','reference','movingfixed'};
else
    keys = {'fixed','target','underlay','reference','histology','vascular','region','atlas'};
end

for i = 1:numel(keys)
    if ~isempty(strfind(p,keys{i}))
        sc = sc + 100 - i;
    end
end

if ~isempty(strfind(p,'underlay')), sc = sc + 25; end
if ~isempty(strfind(p,'fixed')),    sc = sc + 20; end
if ~isempty(strfind(p,'target')),   sc = sc + 18; end
if ~isempty(strfind(p,'rgb')),      sc = sc + 5;  end

try
    B = double(A(:));
    B = B(isfinite(B));
    if isempty(B)
        sc = sc - 100;
    else
        u = unique(B(1:min(numel(B),50000)));
        if numel(u) <= 2
            sc = sc - 20;
        end
        if max(B) > min(B)
            sc = sc + 5;
        end
    end
catch
end
end

function P = toPlane(A, outSize2)
P = [];
try
    A = squeeze(double(A));
    A(~isfinite(A)) = 0;
    if ndims(A) == 2
        P = A;
    elseif ndims(A) == 3
        if size(A,3) == 3
            P = 0.2989*A(:,:,1) + 0.5870*A(:,:,2) + 0.1140*A(:,:,3);
        else
            z = round(size(A,3)/2);
            P = A(:,:,z);
        end
    elseif ndims(A) == 4
        A = mean(A,4);
        P = toPlane(A,outSize2);
    else
        return;
    end
    if ~isempty(outSize2) && numel(outSize2) >= 2
        yy = round(outSize2(1)); xx = round(outSize2(2));
        P = resize2(P, yy, xx);
    end
catch
    P = [];
end
end

function B = resize2(A, yy, xx)
if size(A,1) == yy && size(A,2) == xx
    B = A;
    return;
end
try
    B = imresize(A,[yy xx]);
catch
    [x0,y0] = meshgrid(linspace(1,size(A,2),size(A,2)), linspace(1,size(A,1),size(A,1)));
    [x1,y1] = meshgrid(linspace(1,size(A,2),xx), linspace(1,size(A,1),yy));
    B = interp2(x0,y0,A,x1,y1,'linear',0);
end
end
