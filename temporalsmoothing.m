function [Iout, stats] = temporalsmoothing(Iin, TR, winSec, opts)
% temporalsmoothing
% ============================================================
% Centered temporal moving-average smoothing (TRUE sliding window)
% with endpoint replication (like np.pad(..., mode='edge')).
%
% Supports:
%   - 3D input:  [Y X T]
%   - 4D input:  [Y X Z T]
%
% Usage:
%   [Iout, stats] = temporalsmoothing(I, TR, winSec)
%   [Iout, stats] = temporalsmoothing(I, TR, winSec, opts)
%
% Notes:
%   - This is NOT block averaging.
%   - Window length in volumes: winVol = max(1, round(winSec/TR))
%   - Output length equals input length.
%
% MATLAB: 2023b compatible (also works in older versions).
% No toolboxes required.

% ------------------- inputs -------------------
if nargin < 3
    error('temporalsmoothing requires (Iin, TR, winSec).');
end
if nargin < 4 || isempty(opts), opts = struct(); end

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

sz = size(Iin);
T  = sz(dimT);
if T < 2
    Iout = Iin;
    stats = struct('TR',TR,'winSec',winSec,'winVol',1,'note','T<2, unchanged');
    return;
end

% ------------------- options -------------------
if ~isfield(opts,'chunkVoxels') || isempty(opts.chunkVoxels)
    opts.chunkVoxels = 50000; % safe default
end
if ~isfield(opts,'logFcn') || isempty(opts.logFcn)
    opts.logFcn = []; % e.g. @(s) disp(s)
end

% ------------------- window -------------------
winVol = max(1, round(winSec / TR));
prePad  = floor(winVol/2);
postPad = winVol - 1 - prePad;

stats = struct();
stats.TR      = TR;
stats.winSec  = winSec;
stats.winVol  = winVol;
stats.prePad  = prePad;
stats.postPad = postPad;

if winVol <= 1
    Iout = Iin;
    stats.note = 'winVol<=1, unchanged';
    return;
end

% keep precision (usually single)
Iwork = Iin;
if ~isa(Iwork,'single') && ~isa(Iwork,'double')
    Iwork = single(Iwork);
end

% Flatten to [Nvox, T] without copying (copy-on-write)
flat = reshape(Iwork, [], T);
Nvox = size(flat,1);

% kernel in same class as data
k = ones(1, winVol, 'like', flat) / cast(winVol, 'like', flat);

outFlat = zeros(Nvox, T, 'like', flat);

chunk = max(1, round(opts.chunkVoxels));
nChunks = ceil(Nvox / chunk);

tStart = tic;
for c = 1:nChunks
    a = (c-1)*chunk + 1;
    b = min(Nvox, c*chunk);
    X = flat(a:b, :); % [nv, T]

    % replicate endpoints in time
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

    Xpad = [L, X, R]; %#ok<AGROW>  % [nv, T+winVol-1]

    % true sliding window, centered via padding + 'valid'
    Y = conv2(Xpad, k, 'valid'); % [nv, T]

    outFlat(a:b, :) = Y;

    if ~isempty(opts.logFcn)
        opts.logFcn(sprintf('Temporal smoothing: %d/%d chunks', c, nChunks));
    end
end

Iout = reshape(outFlat, size(Iwork));

% if original was e.g. single, keep; if original was integer, we already cast
if isa(Iin,'double')
    Iout = double(Iout);
elseif isa(Iin,'single')
    Iout = single(Iout);
end

stats.runtimeSec = toc(tStart);
end