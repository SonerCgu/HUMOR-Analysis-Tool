function res = HUMOR_FC_make_slice_roi_result(s,subIdx,resIn,zSel)
% True slice-specific ROI FC result.
% Recomputes ROI time courses using only voxels from selected Z slice.

res = resIn;
try
    if nargin < 4 || isempty(zSel), zSel = s.slice; end
    if isempty(resIn) || ~isstruct(resIn), return; end
    if ~isfield(s,'Z') || s.Z <= 1, return; end
    if isfield(resIn,'sliceOnly') && isequal(resIn.sliceOnly,true), return; end
    if isfield(s,'sliceRegionOnly') && ~s.sliceRegionOnly, return; end
    if ~isfield(s,'subjects') || subIdx < 1 || subIdx > numel(s.subjects), return; end

    subj = s.subjects(subIdx);
    if ~isfield(subj,'I4') || isempty(subj.I4), return; end
    if ~isfield(subj,'roiAtlas') || isempty(subj.roiAtlas), return; end

    I4 = subj.I4;
    atlas = subj.roiAtlas;
    [Y,X,Z,T] = size(I4); %#ok<ASGLU>
    z = max(1,min(Z,round(zSel)));

    if ndims(atlas) < 3
        atlasS = round(double(atlas));
    else
        zA = max(1,min(size(atlas,3),z));
        atlasS = round(double(atlas(:,:,zA)));
    end
    if size(atlasS,1) ~= Y || size(atlasS,2) ~= X
        atlasS = localResizeNearest(atlasS,Y,X);
    end

    if isfield(subj,'mask') && ~isempty(subj.mask)
        M0 = subj.mask;
        if ndims(M0) >= 3
            zM = max(1,min(size(M0,3),z));
            maskS = logical(M0(:,:,zM));
        else
            maskS = logical(M0);
        end
        if size(maskS,1) ~= Y || size(maskS,2) ~= X
            maskS = logical(localResizeNearest(double(maskS),Y,X));
        end
    else
        maskS = true(Y,X);
    end

    if isfield(resIn,'timeIdx') && ~isempty(resIn.timeIdx)
        idxT = round(double(resIn.timeIdx(:)));
        idxT = idxT(isfinite(idxT) & idxT >= 1 & idxT <= size(I4,4));
        if isempty(idxT), idxT = 1:size(I4,4); end
    else
        idxT = 1:size(I4,4);
    end

    Izt = I4(:,:,z,idxT);
    D = reshape(double(Izt),Y*X,numel(idxT));

    atlasV = atlasS(:);
    maskV = maskS(:);
    labsAll = unique(atlasV(maskV & atlasV ~= 0));
    labsAll = labsAll(:);
    labsAll = labsAll(isfinite(labsAll) & labsAll ~= 0);
    if isempty(labsAll), return; end

    minVox = 1;
    try
        if isfield(s,'opts') && isfield(s.opts,'roiMinVox')
            minVox = max(1,round(double(s.opts.roiMinVox)));
        end
    catch
        minVox = 1;
    end

    keepLabels = [];
    names = {};
    counts = [];
    meanTS = [];

    for k = 1:numel(labsAll)
        lab = round(double(labsAll(k)));
        nm = localROIName(lab,s);
        if localIsBackground(lab,nm), continue; end
        pix = find(maskV & atlasV == lab);
        if numel(pix) < minVox, continue; end
        ts = mean(D(pix,:),1)';
        keepLabels(end+1,1) = lab; %#ok<AGROW>
        counts(end+1,1) = numel(pix); %#ok<AGROW>
        names{end+1,1} = nm; %#ok<AGROW>
        meanTS(:,end+1) = ts; %#ok<AGROW>
    end

    if numel(keepLabels) < 2, return; end
    R = localCorr(meanTS);

    res = resIn;
    res.labels = keepLabels;
    res.names = names;
    res.counts = counts;
    res.meanTS = meanTS;
    res.M = R;
    res.R = R;
    res.TR = subj.TR;
    res.timeIdx = idxT;
    res.sliceOnly = true;
    res.sliceIndex = z;
    res.sliceLabel = sprintf('Z %d/%d',z,Z);
    res.sourceNote = 'True slice-specific FC: ROI time courses recomputed from selected Z slice only.';
catch
    res = resIn;
end
end

function name = localROIName(label,s)
name = sprintf('ROI_%g',label);
try
    if isfield(s,'opts') && isfield(s.opts,'roiNameTable')
        T = s.opts.roiNameTable;
        if isstruct(T) && isfield(T,'labels') && isfield(T,'names') && ~isempty(T.labels)
            labs = double(T.labels(:));
            ix = find(labs == double(label),1,'first');
            if isempty(ix), ix = find(abs(labs) == abs(double(label)),1,'first'); end
            if ~isempty(ix) && ix <= numel(T.names)
                nm = strtrim(char(T.names{ix}));
                if ~isempty(nm), name = sprintf('%s [%g]',nm,label); end
            end
        end
    end
catch
end
end

function tf = localIsBackground(label,name)
tf = false;
try
    if ~isfinite(label) || label == 0, tf = true; return; end
    n = lower(char(name));
    bad = {'background','outside','root','void','unknown'};
    for i = 1:numel(bad)
        if ~isempty(strfind(n,bad{i})), tf = true; return; end
    end
catch
    tf = false;
end
end

function R = localCorr(X)
X = double(X);
X = bsxfun(@minus,X,mean(X,1));
sd = std(X,0,1);
sd(sd <= 0 | ~isfinite(sd)) = 1;
X = bsxfun(@rdivide,X,sd);
R = (X' * X) ./ max(1,size(X,1)-1);
R = max(-1,min(1,R));
R(1:size(R,1)+1:end) = 1;
end

function B = localResizeNearest(A,Y,X)
A = double(A);
if isequal(size(A),[Y X]), B = A; return; end
try
    if exist('imresize','file') == 2
        B = imresize(A,[Y X],'nearest');
    else
        yy = round(linspace(1,size(A,1),Y));
        xx = round(linspace(1,size(A,2),X));
        B = A(yy,xx);
    end
catch
    yy = round(linspace(1,size(A,1),Y));
    xx = round(linspace(1,size(A,2),X));
    B = A(yy,xx);
end
B = round(double(B));
end
