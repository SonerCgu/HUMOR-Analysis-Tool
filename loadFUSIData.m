function [data, meta] = loadFUSIData(dataFile, fallbackTR)
% loadFUSIData
% ------------------------------------------------------------
% Robust fUSI data loader with TR / time inference
%
% INPUT
%   dataFile   : full path to .mat / .nii / .nii.gz
%   fallbackTR : fallback TR (sec) if nothing found
%
% OUTPUT
%   data.I             : [Y x X x T] or [Y x X x Z x T] single
%   data.TR            : repetition time (sec)
%   data.TotalTimeSec  : total acquisition time (sec)
%   data.TotalTimeMin  : total acquisition time (min)
%   data.nVols         : number of volumes
%
%   meta.loadedPar
%   meta.loadedBaseline
%   meta.loadedMask
%   meta.loadedMaskIsInclude
%   meta.rawMetadata
%
% NOTES
%   - Accepts variable names such as I, IQR, img, image, data, volume
%   - Falls back to the best 3D/4D numeric array in the MAT file
%   - Keeps last dimension as time
%   - MATLAB 2017b compatible
% ------------------------------------------------------------

if nargin < 2 || isempty(fallbackTR) || ~isfinite(fallbackTR) || fallbackTR <= 0
    fallbackTR = 0.3;
end

meta = struct( ...
    'loadedPar', [], ...
    'loadedBaseline', [], ...
    'loadedMask', [], ...
    'loadedMaskIsInclude', true, ...
    'rawMetadata', struct() );

extKey = getFileTypeKey(dataFile);

switch extKey

    case '.mat'
        S = load(dataFile);

        % -------------------------------------------------
        % RAW METADATA PASS-THROUGH
        % -------------------------------------------------
meta.rawMetadata = struct();

if isfield(S,'metadata') && isstruct(S.metadata)
    meta.rawMetadata.metadata = S.metadata;
end

if isfield(S,'md') && isstruct(S.md)
    meta.rawMetadata.md = S.md;
end

        geomFields = {'imageDim','imageSize','voxelSize','imageType','origin','t0'};
        for iF = 1:numel(geomFields)
            f = geomFields{iF};
            if isfield(S,f)
                meta.rawMetadata.(f) = S.(f);
            end
        end

        % -------------------------------------------------
        % FIND BEST IMAGE STACK
        % -------------------------------------------------
        [I, pickedVarName] = findBestImagingVariable(S);

        if isempty(I)
            if isfield(S,'Pipeline_Cell') && numel(fieldnames(S)) == 1
                error(['This MAT file appears to be an OFUSA pipeline file, not an imaging dataset.' sprintf('\n') ...
                       'Found only variable: Pipeline_Cell  class=' class(S.Pipeline_Cell) sprintf('\n') ...
                       'Please load the actual raw/exported image data file instead.']);
            end

            error(['MAT file does not contain a valid 3D/4D fUSI image stack.' sprintf('\n') ...
                   'Accepted examples: I, IQR, img, image, data, volume.']);
        end

        I = single(I);
        meta.rawMetadata.loadedVarName = pickedVarName;
% -------------------------------------------------
% THEO / PYFUS GEOMETRY RECONSTRUCTION
% Rebuild data using md.size / md.imageSize first,
% then standardize to [DV LR AP T] for downstream use.
% -------------------------------------------------
meta.rawMetadata.sizeBeforeTheoFix = size(I);

if isfield(S, 'md') && isstruct(S.md)

    meta.rawMetadata.md = S.md;

    spatialSize = [];
    if isfield(S.md, 'size') && isnumeric(S.md.size) && numel(S.md.size) >= 3
        spatialSize = double(S.md.size(:))';
        meta.rawMetadata.sourceSpatialField = 'md.size';
    elseif isfield(S.md, 'imageSize') && isnumeric(S.md.imageSize) && numel(S.md.imageSize) >= 3
        spatialSize = double(S.md.imageSize(:))';
        meta.rawMetadata.sourceSpatialField = 'md.imageSize';
    end

    dirStr = '';
    if isfield(S.md, 'Direction') && ~isempty(S.md.Direction)
        try
            dirStr = upper(strrep(char(S.md.Direction), ' ', ''));
        catch
            dirStr = '';
        end
    end
    meta.rawMetadata.Direction = dirStr;

    if ~isempty(spatialSize)
        spatialSize = round(spatialSize(1:3));
        meta.rawMetadata.targetSpatialSizeTheo = spatialSize;

        % -------------------------------------------------
        % CASE A:
        % Theo flattened storage, e.g. I is [DV x (AP*LR) x T]
        % Python does:
        %   size_ = [size(1) size(3) size(2)]
        %   reshape(I, [size_ T])
        % -------------------------------------------------
        if ndims(I) == 3
            nTraw = size(I, 3);
            theoShape = [spatialSize(1) spatialSize(3) spatialSize(2) nTraw];

            if numel(I) == prod(theoShape)
                I = reshape(I, theoShape);
                meta.rawMetadata.theoFixApplied = 'reshape_to_[DV_LR_AP_T]';
                meta.rawMetadata.reshapeApplied = theoShape;
            end
        end

        % -------------------------------------------------
        % CASE B:
        % Already 4D, but maybe still ordered as [DV AP LR T]
        % Convert to [DV LR AP T]
        % -------------------------------------------------
        if ndims(I) == 4
            szI = size(I);

            if numel(szI) >= 4
                if isequal(szI(1:3), spatialSize(1:3))
                    % [DV AP LR T] -> [DV LR AP T]
                    I = permute(I, [1 3 2 4]);
                    meta.rawMetadata.theoFixApplied = 'permute_[1_3_2_4]';
                    meta.rawMetadata.permuteApplied = [1 3 2 4];

                elseif isequal(szI(1:3), spatialSize([1 3 2]))
                    % already [DV LR AP T]
                    meta.rawMetadata.theoFixApplied = 'already_[DV_LR_AP_T]';
                    meta.rawMetadata.permuteApplied = [1 2 3 4];
                end
            end
        end
    end
end

meta.rawMetadata.sizeAfterTheoFix = size(I);
        % -------------------------------------------------
        % TR / TOTAL TIME DETECTION
        % -------------------------------------------------
        TR = [];
        TotalTimeSec = [];

        TR = firstPositiveScalarFound(S, {'TR','tr','dt','Dt','deltaT','DeltaT'});
        if isempty(TR)
            Fs = firstPositiveScalarFound(S, {'Fs','fs','samplingRate','SampleRate'});
            if ~isempty(Fs)
                TR = 1 / double(Fs);
            end
        end

        TotalTimeSec = firstPositiveScalarFound(S, ...
            {'TotalTimeSec','totalTimeSec','TotalTime','totalTime'});

        timeVec = firstNumericVectorFound(S, {'t','time','timestamps','Time','Timestamps'});
        if ~isempty(timeVec)
            dt = diff(double(timeVec(:)));
            dt = dt(isfinite(dt) & dt > 0);

            if ~isempty(dt)
                if isempty(TR)
                    TR = median(dt);
                end
                if isempty(TotalTimeSec)
                    TotalTimeSec = (timeVec(end) - timeVec(1)) + median(dt);
                end
            end
        end

        if isempty(TR) || ~isfinite(TR) || TR <= 0
    warning('loadFUSIData:FallbackTR', ...
        'TR not found - using fallback TR = %.3f s', fallbackTR);
    TR = fallbackTR;
elseif TR > 1.0
    warning('loadFUSIData:SuspiciousTR', ...
        'Suspicious TR = %.3f s found in file. Using fallback TR = %.3f s instead.', ...
        TR, fallbackTR);
    TR = fallbackTR;
end

        if isempty(TotalTimeSec) || ~isfinite(TotalTimeSec) || TotalTimeSec <= 0
            TotalTimeSec = size(I, ndims(I)) * TR;
        end

        % -------------------------------------------------
        % OPTIONAL FIELDS
        % -------------------------------------------------
        if isfield(S,'par')
            meta.loadedPar = S.par;
        end
        if isfield(S,'baseline')
            meta.loadedBaseline = S.baseline;
        end
        if isfield(S,'mask')
            try
                meta.loadedMask = logical(S.mask);
            catch
            end
        end
        if isfield(S,'maskIsInclude')
            try
                meta.loadedMaskIsInclude = logical(S.maskIsInclude);
            catch
            end
        end

    case '.nii'
        V = niftiread(dataFile);
        I = convertNiftiToI(V);

        TR = fallbackTR;
        TotalTimeSec = size(I, ndims(I)) * TR;

    case '.nii.gz'
        tmpDir = tempname;
        mkdir(tmpDir);

        try
            gunzip(dataFile, tmpDir);
            d = dir(fullfile(tmpDir,'*.nii'));
            if isempty(d)
                error('Could not unpack .nii.gz file.');
            end

            niiFile = fullfile(tmpDir, d(1).name);
            V = niftiread(niiFile);
            I = convertNiftiToI(V);
        catch ME
            try
                rmdir(tmpDir,'s');
            catch
            end
            rethrow(ME);
        end

        try
            rmdir(tmpDir,'s');
        catch
        end

        TR = fallbackTR;
        TotalTimeSec = size(I, ndims(I)) * TR;

    otherwise
        error('Unsupported file type: %s', extKey);
end

% -----------------------------------------------------
% VOLUME CONSISTENCY
% -----------------------------------------------------
nVols_data = size(I, ndims(I));
nVols_req  = round(TotalTimeSec / TR);

if nVols_req <= 0 || abs(nVols_req - nVols_data) > 1
    nVols = nVols_data;
else
    nVols = nVols_req;

    if nVols_data > nVols
        subs = repmat({':'}, 1, ndims(I));
        subs{end} = 1:nVols;
        I = I(subs{:});

    elseif nVols_data < nVols
        subsLast = repmat({':'}, 1, ndims(I));
        subsLast{end} = nVols_data;
        lastVol = I(subsLast{:});

        reps = ones(1, ndims(I));
        reps(end) = nVols - nVols_data;

        I = cat(ndims(I), I, repmat(lastVol, reps));
    end
end

TotalTimeSec = nVols * TR;

data = struct();
data.I            = single(I);
data.TR           = double(TR);
data.nVols        = double(nVols);
data.TotalTimeSec = double(TotalTimeSec);
data.TotalTimeMin = double(TotalTimeSec / 60);
data.totalTime    = data.TotalTimeSec;
data.totalTimeMin = data.TotalTimeMin;

end


% =====================================================
% FILE TYPE
% =====================================================
function extKey = getFileTypeKey(dataFile)

if numel(dataFile) >= 7 && strcmpi(dataFile(end-6:end), '.nii.gz')
    extKey = '.nii.gz';
else
    [~,~,ext] = fileparts(dataFile);
    extKey = lower(ext);
end

end


% =====================================================
% NIFTI CONVERSION
% =====================================================
function I = convertNiftiToI(V)

V = squeeze(V);
nd = ndims(V);

if nd == 2
    I = single(permute(V, [2 1]));
elseif nd == 3
    I = single(permute(V, [2 1 3]));
elseif nd == 4
    I = single(permute(V, [2 1 3 4]));
else
    error('Unsupported NIfTI dimensionality: ndims=%d', nd);
end

end


% =====================================================
% FIND BEST IMAGE VARIABLE
% =====================================================
function [bestData, bestName] = findBestImagingVariable(S)

bestData = [];
bestName = '';

candidates = struct('name',{},'score',{},'value',{});
candidates = collectImagingCandidates(S, '', 0, candidates);

if isempty(candidates)
    return;
end

scores = zeros(1, numel(candidates));
for k = 1:numel(candidates)
    scores(k) = candidates(k).score;
end

[bestScore, idx] = max(scores);
if ~isfinite(bestScore)
    return;
end

bestData = candidates(idx).value;
bestName = candidates(idx).name;

end


function candidates = collectImagingCandidates(v, pathStr, depth, candidates)

if depth > 5
    return;
end

% numeric candidate
if isnumeric(v) && ~isempty(v)
    sc = scoreImagingCandidate(v, pathStr);
    if isfinite(sc)
        c.name = pathStr;
        c.score = sc;
        c.value = v;
        candidates(end+1) = c; %#ok<AGROW>
    end
    return;
end

% cell recursion
if iscell(v) && ~isempty(v)
    nMax = min(numel(v), 24);
    for ii = 1:nMax
        try
            if isempty(pathStr)
                nextPath = sprintf('{%d}', ii);
            else
                nextPath = sprintf('%s{%d}', pathStr, ii);
            end
            candidates = collectImagingCandidates(v{ii}, nextPath, depth+1, candidates);
        catch
        end
    end
    return;
end

% struct recursion
if isstruct(v) && ~isempty(v)
    nMaxStruct = min(numel(v), 12);
    for jj = 1:nMaxStruct
        try
            vv = v(jj);
        catch
            continue;
        end

        try
            fn = fieldnames(vv);
        catch
            fn = {};
        end

        for ii = 1:numel(fn)
            f = fn{ii};
            try
                if isempty(pathStr)
                    if numel(v) == 1
                        nextPath = f;
                    else
                        nextPath = sprintf('(%d).%s', jj, f);
                    end
                else
                    if numel(v) == 1
                        nextPath = [pathStr '.' f];
                    else
                        nextPath = sprintf('%s(%d).%s', pathStr, jj, f);
                    end
                end
                candidates = collectImagingCandidates(vv.(f), nextPath, depth+1, candidates);
            catch
            end
        end
    end
    return;
end

% object recursion
if isobject(v) && ~isempty(v)
    nMaxObj = min(numel(v), 12);

    for jj = 1:nMaxObj
        try
            vv = v(jj);
        catch
            continue;
        end

        try
            props = properties(vv);
        catch
            props = {};
        end

        preferred = {'I','IQR','img','image','data','volume','vol','scan','Image','Images'};
        orderedProps = [preferred(:); props(:)];
        orderedProps = unique(orderedProps, 'stable');

        for ii = 1:numel(orderedProps)
            p = orderedProps{ii};

            if ~ismember(p, props)
                continue;
            end

            try
                pv = vv.(p);
            catch
                continue;
            end

            if isempty(pathStr)
                if numel(v) == 1
                    nextPath = p;
                else
                    nextPath = sprintf('(%d).%s', jj, p);
                end
            else
                if numel(v) == 1
                    nextPath = [pathStr '.' p];
                else
                    nextPath = sprintf('%s(%d).%s', pathStr, jj, p);
                end
            end

            candidates = collectImagingCandidates(pv, nextPath, depth+1, candidates);
        end
    end
end

end


function sc = scoreImagingCandidate(v, nameStr)

sc = -Inf;

if isempty(v) || islogical(v) || isscalar(v) || isvector(v)
    return;
end

nd = ndims(v);
sz = size(v);

if nd < 3
    return;
end

sc = 0;

if nd == 3
    sc = sc + 60;
elseif nd == 4
    sc = sc + 85;
elseif nd > 4
    sc = sc + 30;
end

if sz(end) > 1
    sc = sc + 20;
end

if numel(sz) >= 2 && sz(1) >= 16 && sz(2) >= 16
    sc = sc + 10;
end

if isa(v,'single') || isa(v,'double') || isa(v,'uint16') || isa(v,'int16')
    sc = sc + 5;
end

lname = lower(nameStr);

goodKeys = {'i','iqr','data','img','image','stack','movie','frames', ...
            'volume','vol','fus','doppler','power','scan','brain','func'};
badKeys  = {'tr','dt','time','timestamps','mask','atlas','roi','label','coord', ...
            'mean','median','std','var','pipeline','proc','process','handler', ...
            'project','corr','fc','conn','tc','timecourse'};

for k = 1:numel(goodKeys)
    if ~isempty(strfind(lname, goodKeys{k})) %#ok<STREMP>
        sc = sc + 12;
    end
end

for k = 1:numel(badKeys)
    if ~isempty(strfind(lname, badKeys{k})) %#ok<STREMP>
        sc = sc - 20;
    end
end

% penalize likely binary masks
try
    samp = double(v(1:min(numel(v),5000)));
    samp = samp(isfinite(samp));
    if ~isempty(samp)
        u = unique(samp(:));
        if numel(u) <= 3
            sc = sc - 25;
        end
    end
catch
end

end


% =====================================================
% FIND SCALARS / TIME VECTORS
% =====================================================
function out = firstPositiveScalarFound(v, names)

out = [];
result = searchByNames(v, names, 0, 'scalar');
if ~isempty(result)
    out = result;
end

end


function out = firstNumericVectorFound(v, names)

out = [];
result = searchByNames(v, names, 0, 'vector');
if ~isempty(result)
    out = result;
end

end


function out = searchByNames(v, names, depth, mode, matchedContext)

if nargin < 5
    matchedContext = false;
end

out = [];

if depth > 5
    return;
end

% Only accept raw numeric values if we are already inside
% a field whose NAME matched one of the requested names.
if isnumeric(v) && ~isempty(v)
    if ~matchedContext
        return;
    end

    if strcmp(mode,'scalar')
        if isscalar(v) && isfinite(v) && v > 0
            out = double(v);
            return;
        end
    elseif strcmp(mode,'vector')
        if isvector(v) && numel(v) >= 2
            vv = double(v(:));
            vv = vv(isfinite(vv));
            if numel(vv) >= 2
                out = vv;
                return;
            end
        end
    end
end

if iscell(v) && ~isempty(v)
    nMax = min(numel(v), 24);
    for ii = 1:nMax
        try
            out = searchByNames(v{ii}, names, depth+1, mode, matchedContext);
            if ~isempty(out), return; end
        catch
        end
    end
    return;
end

if isstruct(v) && ~isempty(v)
    nMaxStruct = min(numel(v), 12);
    for jj = 1:nMaxStruct
        try
            vv = v(jj);
            fn = fieldnames(vv);
        catch
            continue;
        end

        ordered = [names(:); fn(:)];
        ordered = unique(ordered, 'stable');

        for ii = 1:numel(ordered)
            f = ordered{ii};
            if ~ismember(f, fn)
                continue;
            end
            try
                out = tryFieldValue(vv.(f), f, names, depth, mode);
                if ~isempty(out), return; end
            catch
            end
        end
    end
    return;
end

if isobject(v) && ~isempty(v)
    nMaxObj = min(numel(v), 12);
    for jj = 1:nMaxObj
        try
            vv = v(jj);
            props = properties(vv);
        catch
            continue;
        end

        ordered = [names(:); props(:)];
        ordered = unique(ordered, 'stable');

        for ii = 1:numel(ordered)
            p = ordered{ii};
            if ~ismember(p, props)
                continue;
            end
            try
                pv = vv.(p);
                out = tryFieldValue(pv, p, names, depth, mode);
                if ~isempty(out), return; end
            catch
            end
        end
    end
end

end


function out = tryFieldValue(val, fieldName, names, depth, mode)

out = [];

matched = false;
for k = 1:numel(names)
    if strcmpi(fieldName, names{k})
        matched = true;
        break;
    end
end

if matched
    % direct hit: field name itself matches
    if strcmp(mode,'scalar')
        if isnumeric(val) && isscalar(val) && isfinite(val) && val > 0
            out = double(val);
            return;
        end
    elseif strcmp(mode,'vector')
        if isnumeric(val) && isvector(val) && numel(val) >= 2
            vv = double(val(:));
            vv = vv(isfinite(vv));
            if numel(vv) >= 2
                out = vv;
                return;
            end
        end
    end

    % if the matched field contains nested data, allow searching inside it
    out = searchByNames(val, names, depth+1, mode, true);
    return;
end

% field name did not match -> continue searching,
% but DO NOT allow arbitrary numerics to be accepted
out = searchByNames(val, names, depth+1, mode, false);

end