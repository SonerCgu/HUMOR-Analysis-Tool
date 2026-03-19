function [Iout, stats] = temporalsmoothing(Iin, TR, winSec, opts)
% temporalsmoothing
% ============================================================
% Two modes in one file:
%
%   1) Sliding temporal smoothing
%      - centered moving average
%      - endpoint replication
%      - output length equals input length
%
%   2) Block averaging / subsampling
%      - non-overlapping temporal blocks
%      - output length is reduced
%      - output TR becomes TR * winVol
%      - supports MEAN or MEDIAN block reduction
%
% Supports:
%   - 3D input: [Y X T]
%   - 4D input: [Y X Z T]
%
% Usage:
%   [Iout, stats] = temporalsmoothing(I, TR, winSec)
%   [Iout, stats] = temporalsmoothing(I, TR, winSec, opts)
%
% Required:
%   Iin     : numeric data [Y X T] or [Y X Z T]
%   TR      : input TR in seconds
%   winSec  : smoothing window or block duration in seconds
%
% Optional opts:
%   .mode         = 'sliding' (default) or 'block'
%   .blockMethod  = 'mean' (default) or 'median'   [for block mode]
%   .chunkVoxels  = 50000 default
%   .logFcn       = [] or function handle
%
% Notes:
%   - winVol = max(1, round(winSec/TR))
%   - For block mode, trailing incomplete frames are discarded.
%   - No registration is performed here.
%
% MATLAB 2017b / 2023b compatible
% No toolboxes required.
% ============================================================

% ------------------- inputs -------------------
if nargin < 3
    error('temporalsmoothing requires (Iin, TR, winSec).');
end
if nargin < 4 || isempty(opts)
    opts = struct();
end

if ~isscalar(TR) || ~isfinite(TR) || TR <= 0
    error('TR must be a positive scalar.');
end
if ~isscalar(winSec) || ~isfinite(winSec) || winSec <= 0
    error('winSec must be a positive scalar (seconds).');
end
if ~isnumeric(Iin) || isempty(Iin)
    error('Iin must be a non-empty numeric array.');
end

dimT = ndims(Iin);
if dimT ~= 3 && dimT ~= 4
    error('Iin must be 3D [Y X T] or 4D [Y X Z T].');
end

% ------------------- options -------------------
if ~isfield(opts,'chunkVoxels') || isempty(opts.chunkVoxels)
    opts.chunkVoxels = 50000;
end
if ~isfield(opts,'logFcn') || isempty(opts.logFcn)
    opts.logFcn = [];
end
if ~isfield(opts,'mode') || isempty(opts.mode)
    opts.mode = 'sliding';
end
if ~isfield(opts,'blockMethod') || isempty(opts.blockMethod)
    opts.blockMethod = 'mean';
end

opts.mode = lower(strtrim(opts.mode));
opts.blockMethod = lower(strtrim(opts.blockMethod));

if ~ismember(opts.mode, {'sliding','block'})
    error('opts.mode must be ''sliding'' or ''block''.');
end
if ~ismember(opts.blockMethod, {'mean','median'})
    error('opts.blockMethod must be ''mean'' or ''median''.');
end

% ------------------- dimensions -------------------
sz = size(Iin);
T  = sz(dimT);

stats = struct();
stats.TR = TR;
stats.winSec = winSec;
stats.mode = opts.mode;
stats.blockMethod = opts.blockMethod;
stats.nVolsIn = T;
stats.totalTimeSec = T * TR;

if T < 2
    Iout = Iin;
    stats.winVol = 1;
    stats.TRout = TR;
    stats.nVolsOut = T;
    stats.note = 'T<2, unchanged';
    stats.runtimeSec = 0;
    return;
end

% ------------------- window -------------------
winVol = max(1, round(winSec / TR));
stats.winVol = winVol;

if strcmp(opts.mode,'sliding')
    prePad  = floor(winVol/2);
    postPad = winVol - 1 - prePad;
else
    prePad  = 0;
    postPad = 0;
end

stats.prePad = prePad;
stats.postPad = postPad;

if winVol <= 1
    Iout = Iin;
    stats.TRout = TR;
    stats.nVolsOut = T;
    if strcmp(opts.mode,'sliding')
        stats.note = 'winVol<=1, unchanged';
    else
        stats.note = 'winVol<=1, no subsampling applied';
    end
    stats.runtimeSec = 0;
    return;
end

% ------------------- preserve working precision -------------------
Iwork = Iin;
origClass = class(Iin);

if ~isa(Iwork,'single') && ~isa(Iwork,'double')
    Iwork = single(Iwork);
end

flat = reshape(Iwork, [], T);
Nvox = size(flat,1);

chunk = max(1, round(opts.chunkVoxels));
nChunks = ceil(Nvox / chunk);

tStart = tic;

% ============================================================
% MODE 1: sliding temporal smoothing
% ============================================================
if strcmp(opts.mode,'sliding')

    k = ones(1, winVol, 'like', flat) / cast(winVol, 'like', flat);
    outFlat = zeros(Nvox, T, 'like', flat);

    for c = 1:nChunks
        a = (c-1)*chunk + 1;
        b = min(Nvox, c*chunk);

        X = flat(a:b, :);

        if prePad > 0
            L = repmat(X(:,1), 1, prePad);
        else
            L = [];
        end

        if postPad > 0
            R = repmat(X(:,end), 1, postPad);
        else
            R = [];
        end

        Xpad = [L, X, R];

        % centered sliding window via padding + valid convolution
        Y = conv2(Xpad, k, 'valid');

        outFlat(a:b, :) = Y;

        if ~isempty(opts.logFcn)
            opts.logFcn(sprintf('Temporal smoothing: %d/%d chunks', c, nChunks));
        end
    end

    outSz = sz;
    Iout = reshape(outFlat, outSz);

    stats.TRout = TR;
    stats.nVolsOut = T;
    stats.operation = 'temporal_smoothing';

% ============================================================
% MODE 2: block averaging / subsampling
% ============================================================
else

    nBlocks = floor(T / winVol);
    nUsed = nBlocks * winVol;
    nDiscard = T - nUsed;

    if nBlocks < 1
        error('Not enough frames (%d) for block size %d volumes.', T, winVol);
    end

    outFlat = zeros(Nvox, nBlocks, 'like', flat);

    for c = 1:nChunks
        a = (c-1)*chunk + 1;
        b = min(Nvox, c*chunk);

        X = flat(a:b, 1:nUsed);
        X = reshape(X, size(X,1), winVol, nBlocks);

        if strcmp(opts.blockMethod,'median')
            Y = median(X, 2);
        else
            Y = mean(X, 2);
        end

        Y = reshape(Y, size(X,1), nBlocks);
        outFlat(a:b, :) = Y;

        if ~isempty(opts.logFcn)
            opts.logFcn(sprintf('Subsampling (%s): %d/%d chunks', ...
                upper(opts.blockMethod), c, nChunks));
        end
    end

    outSz = [sz(1:dimT-1), nBlocks];
    Iout = reshape(outFlat, outSz);

    stats.TRout = TR * winVol;
    stats.nVolsOut = nBlocks;
    stats.nBlocks = nBlocks;
    stats.nUsedInputVolumes = nUsed;
    stats.nDiscardedTailVolumes = nDiscard;
    stats.blockDurSec = stats.TRout;
    stats.operation = 'subsampling';
end

stats.runtimeSec = toc(tStart);

% ------------------- restore original numeric class -------------------
if strcmp(origClass,'double')
    Iout = double(Iout);
elseif strcmp(origClass,'single')
    Iout = single(Iout);
end

end