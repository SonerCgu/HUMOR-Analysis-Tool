function [I3D, motorInfo] = motor(I, TR, qcFolder)
% =========================================================
% MOTOR RECONSTRUCTION (FRAME-BASED, TWO MODES, STUDIO-SAFE)
%
% Supports:
%   1) Continuous mode
%      - One long raw movie [Y x X x T]
%      - Motor stays N frames per slice
%      - Optional sequential initial baseline per slice
%
%   2) Split mode
%      - Many MAT files in a selected folder
%      - Expected naming like: slice1_t001.mat, slice2_t001.mat, ...
%      - Automatically groups by slice and t-index
%      - Concatenates slice1_t001 + slice1_t002 + ...
%      - Concatenates slice2_t001 + slice2_t002 + ...
%
% IMPORTANT
%   - Core reconstruction is FRAME-BASED only
%   - TR is used only for reporting/QC labels if valid
%   - Robust to dynamic / imperfect GUI-derived TR
%
% INPUT
%   I        : raw continuous movie [Y x X x T] for continuous mode
%              can be [] if using split mode
%   TR       : optional scalar in seconds/frame
%   qcFolder : QC output folder
%
% OUTPUT
%   I3D      : reconstructed data [Y x X x nSlices x Tnew]
%   motorInfo: reconstruction metadata / legacy compatibility
%
% MATLAB 2017b / 2023b compatible
% =========================================================

if nargin < 1
    I = [];
end
if nargin < 2
    TR = [];
end
if nargin < 3 || isempty(qcFolder)
    qcFolder = pwd;
end

if ~isempty(I)
    if ndims(I) ~= 3
        error('Continuous input I must be 3D [Y x X x T].');
    end
    I = single(I);
end

% TR is optional for frame-based logic
if isempty(TR) || ~isscalar(TR) || ~isfinite(TR) || TR <= 0
    TR = NaN;
end

if ~exist(qcFolder, 'dir')
    mkdir(qcFolder);
end

hasInputMovie = ~isempty(I);
defaults = localMotorDefaults(TR, hasInputMovie);

P = localMotorDialog(defaults, TR, hasInputMovie);
if isempty(P)
    error('Motor cancelled.');
end

switch P.sourceMode
    case 1  % continuous
        if isempty(I)
            error('Continuous mode selected, but no input movie I was provided.');
        end

        [I3D_raw, recInfo, sourceInfo] = localBuildContinuousRaw(I, P);
        localWriteContinuousRawQC(I, recInfo, qcFolder, TR);

    case 2  % split folder
        [I3D_raw, recInfo, sourceInfo] = localBuildSplitRaw(P);
        localWriteSplitSourceQC(sourceInfo, qcFolder);

    otherwise
        error('Unknown motor source mode.');
end

[I3D, procInfo] = localApplyCorrectionAndDespike(I3D_raw, recInfo, P);
localWriteReconstructedQC(I3D, recInfo, procInfo, qcFolder, TR);

motorInfo = struct();
motorInfo.nSlices = recInfo.nSlices;

% legacy fields
motorInfo.volumesPerSlice = recInfo.reconstructedFramesPerSlice;
if isfinite(TR)
    motorInfo.minutesPerSlice = (recInfo.reconstructedFramesPerSlice * TR) / 60;
else
    motorInfo.minutesPerSlice = NaN;
end
motorInfo.TR = TR;
motorInfo.cycles = recInfo.nCycles;

% source / mode info
motorInfo.sourceMode = sourceInfo.mode;
motorInfo.frameBasedReconstruction = true;
motorInfo.timeIndependentCore = true;
motorInfo.qcFolder = qcFolder;

% frame logic
motorInfo.trimFrames = P.trimFrames;
motorInfo.motorFramesPerSlice = recInfo.motorFramesPerSlice;
motorInfo.baselineFramesPerSlice = recInfo.baselineFramesPerSlice;
motorInfo.baselineBlocksPerSlice = recInfo.baselineBlocksPerSlice;
motorInfo.validFramesPerBlock = recInfo.validFramesPerBlock;
motorInfo.reconstructedFramesPerSlice = recInfo.reconstructedFramesPerSlice;
motorInfo.fillCountPerSlice = recInfo.fillCountPerSlice;
motorInfo.sliceBlockCount = recInfo.sliceBlockCount;
motorInfo.blockRanges = recInfo.blockRanges;
motorInfo.blockSourceLabels = recInfo.blockSourceLabels;

% baseline / correction
motorInfo.baselineFramesUsed = recInfo.baselineFramesUsed;
motorInfo.baselineScalar = recInfo.baselineScalar;
motorInfo.baselineMode = recInfo.baselineMode;
motorInfo.rebuildRule = recInfo.rebuildRule;
motorInfo.correctionMode = procInfo.correctionModeText;

% despike
motorInfo.despikeApplied = P.doDespike;
motorInfo.spikeThreshold = P.spikeThr;
motorInfo.spikeMask = procInfo.spikeMask;

% source details
motorInfo.sourceInfo = sourceInfo;

% optional seconds-only reporting
if isfinite(TR)
    motorInfo.sliceSeconds = recInfo.validFramesPerBlock * TR;
    motorInfo.trimSeconds = P.trimFrames * TR;
    motorInfo.totalInitialBaselineSeconds = recInfo.totalInitialBaselineFrames * TR;
else
    motorInfo.sliceSeconds = NaN;
    motorInfo.trimSeconds = NaN;
    motorInfo.totalInitialBaselineSeconds = NaN;
end

% ---------------------------------------------------------
% Save final reconstructed motor dataset
% ---------------------------------------------------------
try
    outFile = fullfile(qcFolder, 'motor_reconstructed_I3D.mat');
    motorInfo.reconstructedMatFile = outFile;
    save(outFile, 'I3D', 'motorInfo', '-v7.3');
    fprintf('Saved reconstructed motor dataset: %s\n', outFile);
catch ME
    warning('Could not save reconstructed motor dataset: %s', ME.message);
end

end

% =========================================================
% DEFAULTS
% =========================================================
function defaults = localMotorDefaults(TR, hasInputMovie)

defaults = struct();

% 1 = continuous single movie
% 2 = split folder with many MAT files
if hasInputMovie
    defaults.sourceMode = 1;
else
    defaults.sourceMode = 2;
end


if hasInputMovie
    defaults.nSlices = 7;   % continuous mode default
else
    defaults.nSlices = 0;   % split mode auto-detect
end

% continuous mode
defaults.motorFramesPerSlice = 188;
defaults.baseFramesPerSlice  = 188;

% split mode
defaults.splitBaselineBlocksPerSlice = 0;
defaults.rawFolder = '';

% common
defaults.trimFrames = 0;
defaults.correctionMode = 2;   % 1 none, 2 additive, 3 PSC
defaults.doDespike = true;
defaults.spikeThr  = 4.0;

if isfinite(TR)
    defaults.infoTRString = sprintf('TR = %.4f s/frame', TR);
else
    defaults.infoTRString = 'TR unavailable (OK: reconstruction is frame-based)';
end

end

% =========================================================
% CONTINUOUS MODE
% =========================================================
function [I3D_raw, recInfo, sourceInfo] = localBuildContinuousRaw(I, P)

[Y, X, T] = size(I);

nSlices             = round(P.nSlices);
motorFramesPerSlice = round(P.motorFramesPerSlice);
baseFramesPerSlice  = round(P.baseFramesPerSlice);
trimFrames          = round(P.trimFrames);

if nSlices < 1 || mod(nSlices,1) ~= 0
    error('Number of slices must be a positive integer.');
end
if motorFramesPerSlice < 1
    error('Motor frames per slice must be >= 1.');
end
if baseFramesPerSlice < 0
    error('Baseline frames per slice must be >= 0.');
end
if trimFrames < 0
    error('Trim frames must be >= 0.');
end

validFramesPerBlock = motorFramesPerSlice - 2*trimFrames;
if validFramesPerBlock < 1
    error('Trim frames too large for continuous block length.');
end

if baseFramesPerSlice > 0
    validBaseFrames = baseFramesPerSlice - 2*trimFrames;
    if validBaseFrames < 1
        error('Trim frames too large for continuous baseline block length.');
    end
else
    validBaseFrames = 0;
end

totalBaseFrames = nSlices * baseFramesPerSlice;
cycleFrames     = nSlices * motorFramesPerSlice;
availableFrames = T - totalBaseFrames;

if availableFrames <= 0
    error('Initial baseline frames exceed total recording length.');
end

nCycles = floor(availableFrames / cycleFrames);
if nCycles < 1
    error('Not enough frames for one complete motor cycle.');
end

TnewMax = nCycles * validFramesPerBlock;
I3D_raw = zeros(Y, X, nSlices, TnewMax, 'single');

fillCount = zeros(nSlices,1);
blockRanges = cell(nSlices,1);
blockSourceLabels = cell(nSlices,1);

for s = 1:nSlices
    cnt = 0;
    ranges = zeros(nCycles, 2);
    keepN  = 0;
    labels = cell(1, nCycles);

    for c = 1:nCycles
        rawBlockStart = totalBaseFrames + (c-1)*cycleFrames + (s-1)*motorFramesPerSlice + 1;
        rawBlockEnd   = rawBlockStart + motorFramesPerSlice - 1;

        idxStart = rawBlockStart + trimFrames;
        idxEnd   = rawBlockEnd   - trimFrames;

        if idxStart < 1 || idxEnd > T || idxEnd < idxStart
            continue;
        end

        idx = idxStart:idxEnd;
        if numel(idx) ~= validFramesPerBlock
            continue;
        end

        st = cnt + 1;
        en = cnt + validFramesPerBlock;

        I3D_raw(:,:,s,st:en) = I(:,:,idx);

        keepN = keepN + 1;
        ranges(keepN,:) = [st en];
        labels{keepN} = sprintf('cycle%03d_rawFrames_%d_%d', c, idxStart, idxEnd);

        cnt = en;
    end

    fillCount(s) = cnt;
    blockRanges{s} = ranges(1:keepN,:);
    blockSourceLabels{s} = labels(1:keepN);
end

Tnew = min(fillCount);
if Tnew < 1
    error('No valid reconstructed frames produced in continuous mode.');
end

I3D_raw = I3D_raw(:,:,:,1:Tnew);

% Clip block ranges to final common length
for s = 1:nSlices
    rr = blockRanges{s};
    keep = rr(:,2) <= Tnew;
    blockRanges{s} = rr(keep,:);
    blockSourceLabels{s} = blockSourceLabels{s}(keep);
end

baselineScalar = nan(nSlices,1);
baselineFramesUsed = zeros(nSlices,1);

if baseFramesPerSlice > 0
    for s = 1:nSlices
        rawStart = (s-1)*baseFramesPerSlice + 1;
        rawEnd   = s*baseFramesPerSlice;

        idxStart = rawStart + trimFrames;
        idxEnd   = rawEnd   - trimFrames;

        if idxEnd < idxStart
            error('Invalid trimmed baseline range for slice %d.', s);
        end

        idxBase = idxStart:idxEnd;
        tr = localMeanTrace(I(:,:,idxBase));
        baselineScalar(s) = median(tr);
        baselineFramesUsed(s) = numel(tr);
    end
end

% Fallback baseline if no explicit baseline was defined
for s = 1:nSlices
    if ~isfinite(baselineScalar(s))
        rr = blockRanges{s};
        if ~isempty(rr)
            st = rr(1,1);
            en = rr(1,2);
            tr = localMeanTrace(I3D_raw(:,:,s,st:en));
        else
            tr = localMeanTrace(I3D_raw(:,:,s,:));
        end
        baselineScalar(s) = median(tr);
        baselineFramesUsed(s) = numel(tr);
    end
end

recInfo = struct();
recInfo.nSlices = nSlices;
recInfo.nCycles = nCycles;
recInfo.motorFramesPerSlice = motorFramesPerSlice;
recInfo.baselineFramesPerSlice = baseFramesPerSlice;
recInfo.baselineBlocksPerSlice = 0;
recInfo.validFramesPerBlock = validFramesPerBlock;
recInfo.totalInitialBaselineFrames = totalBaseFrames;
recInfo.reconstructedFramesPerSlice = Tnew;
recInfo.fillCountPerSlice = fillCount;
recInfo.sliceBlockCount = cellfun(@(x)size(x,1), blockRanges);
recInfo.blockRanges = blockRanges;
recInfo.blockSourceLabels = blockSourceLabels;
recInfo.baselineScalar = baselineScalar;
recInfo.baselineFramesUsed = baselineFramesUsed;
recInfo.baselineMode = 'Continuous mode: sequential initial baseline per slice';
recInfo.rebuildRule = 'After the initial sequential baseline, each slice block is taken every cycle and concatenated in cycle order.';
recInfo.sourceMode = 'CONTINUOUS_SINGLE_FILE';

sourceInfo = struct();
sourceInfo.mode = 'CONTINUOUS_SINGLE_FILE';
sourceInfo.rawInputFrames = T;
sourceInfo.rawInputSize = size(I);
sourceInfo.outputBlockInfo = [];
sourceInfo.rawFolder = '';

end

% =========================================================
% SPLIT MODE
% =========================================================
function [I3D_raw, recInfo, sourceInfo] = localBuildSplitRaw(P)

rawFolder = strtrim(P.rawFolder);
trimFrames = round(P.trimFrames);
splitBaselineBlocksPerSlice = round(P.splitBaselineBlocksPerSlice);

if isempty(rawFolder) || ~exist(rawFolder, 'dir')
    error('Split mode requires a valid raw folder.');
end
if trimFrames < 0
    error('Trim frames must be >= 0.');
end
if splitBaselineBlocksPerSlice < 0
    error('Split baseline blocks per slice must be >= 0.');
end

listing = dir(fullfile(rawFolder, '*.mat'));
if isempty(listing)
    error('No MAT files found in selected raw folder.');
end

entries = struct( ...
    'fileName', {}, ...
    'filePath', {}, ...
    'sliceIndex', {}, ...
    'timeIndex', {}, ...
    'fileDatenum', {}, ...
    'fileTimestampString', {}, ...
    'metaTimestamp', {}, ...
    'globalFrameStart', {}, ...
    'globalFrameEnd', {}, ...
    'movie', {}, ...
    'origFrames', {});

for i = 1:numel(listing)
    fpath = fullfile(rawFolder, listing(i).name);
    [mov, meta] = localLoadMovieFromMat(fpath);

    if isempty(mov) || ndims(mov) ~= 3
        error('Could not load a valid 3D movie from file: %s', listing(i).name);
    end

    [sliceIdx, timeIdx, metaTs, gStart, gEnd] = ...
        localInferSplitFileInfo(listing(i).name, meta);

    if ~isfinite(sliceIdx)
        error(['Could not infer slice index from file: ' listing(i).name ...
               '. Use names like slice1_t001.mat or save motorMeta.sliceIndex.']);
    end

    ent = struct();
    ent.fileName = listing(i).name;
    ent.filePath = fpath;
    ent.sliceIndex = double(sliceIdx);
    ent.timeIndex = double(timeIdx);
    ent.fileDatenum = listing(i).datenum;
    ent.fileTimestampString = datestr(listing(i).datenum, 30);
    ent.metaTimestamp = metaTs;
    ent.globalFrameStart = gStart;
    ent.globalFrameEnd = gEnd;
    ent.movie = single(mov);
    ent.origFrames = size(mov,3);

    entries(end+1) = ent; %#ok<AGROW>
end

allSlices = [entries.sliceIndex];
if isempty(allSlices)
    error('No valid split files could be parsed.');
end

if round(P.nSlices) > 0
    nSlices = round(P.nSlices);
else
    nSlices = max(allSlices);
end

if any(allSlices < 1 | mod(allSlices,1) ~= 0)
    error('Parsed invalid slice indices in split files.');
end
if any(allSlices > nSlices)
    error('Detected slice index larger than requested number of slices.');
end

% Organize files per slice
blockCells = cell(nSlices,1);
outputBlockInfo = cell(nSlices,1);
baselineScalar = nan(nSlices,1);
baselineFramesUsed = zeros(nSlices,1);
sliceBlockCount = zeros(nSlices,1);
sliceDetectedTimes = cell(nSlices,1);

for s = 1:nSlices
    idx = find([entries.sliceIndex] == s);
    if isempty(idx)
        error('No split files found for slice %d.', s);
    end

    subset = entries(idx);

    % If some time indices are missing, assign them in file-date order
    subset = localAssignMissingTimeIndices(subset);

    % Sort by time index, then file date
    subset = localSortSplitEntries(subset);

    nBase = min(splitBaselineBlocksPerSlice, numel(subset));

    % Baseline from first N blocks, excluded from final reconstructed output
    if nBase > 0
        baseTraceAll = [];
        for k = 1:nBase
            blk = localTrimMovieBlock(subset(k).movie, trimFrames, subset(k).fileName);
            tr = localMeanTrace(blk);
            baseTraceAll = [baseTraceAll; tr(:)]; %#ok<AGROW>
            baselineFramesUsed(s) = baselineFramesUsed(s) + numel(tr);
        end
        if ~isempty(baseTraceAll)
            baselineScalar(s) = median(baseTraceAll);
        end
    end

    outIdx = (nBase+1):numel(subset);
    if isempty(outIdx)
        error('After removing split baseline blocks, slice %d has no data left.', s);
    end

    blocksThisSlice = {};
    infoThisSlice   = {};

    for k = outIdx
        blk = localTrimMovieBlock(subset(k).movie, trimFrames, subset(k).fileName);

        metaInfo = struct();
        metaInfo.fileName = subset(k).fileName;
        metaInfo.filePath = subset(k).filePath;
        metaInfo.sliceIndex = subset(k).sliceIndex;
        metaInfo.timeIndex = subset(k).timeIndex;
        metaInfo.fileTimestampString = subset(k).fileTimestampString;
        metaInfo.metaTimestamp = subset(k).metaTimestamp;
        metaInfo.globalFrameStart = subset(k).globalFrameStart;
        metaInfo.globalFrameEnd = subset(k).globalFrameEnd;
        metaInfo.originalFrames = subset(k).origFrames;
        metaInfo.usedFrames = size(blk,3);

        blocksThisSlice{end+1} = blk; %#ok<AGROW>
        infoThisSlice{end+1}   = metaInfo; %#ok<AGROW>
    end

    blockCells{s} = blocksThisSlice;
    outputBlockInfo{s} = infoThisSlice;
    sliceBlockCount(s) = numel(blocksThisSlice);
    sliceDetectedTimes{s} = cellfun(@(z)z.timeIndex, infoThisSlice);
end

% Validate dimensions from first block
[Y, X] = deal([]);
for s = 1:nSlices
    if ~isempty(blockCells{s})
        Y = size(blockCells{s}{1}, 1);
        X = size(blockCells{s}{1}, 2);
        break;
    end
end

if isempty(Y) || isempty(X)
    error('Could not determine split block dimensions.');
end

for s = 1:nSlices
    for k = 1:numel(blockCells{s})
        sz = size(blockCells{s}{k});
        if sz(1) ~= Y || sz(2) ~= X
            error('Split block dimensions do not match across files.');
        end
    end
end

fillCount = zeros(nSlices,1);
for s = 1:nSlices
    totalFrames = 0;
    for k = 1:numel(blockCells{s})
        totalFrames = totalFrames + size(blockCells{s}{k}, 3);
    end
    fillCount(s) = totalFrames;
end

Tnew = min(fillCount);
if Tnew < 1
    error('No valid reconstructed frames produced in split mode.');
end

I3D_raw = zeros(Y, X, nSlices, Tnew, 'single');
blockRanges = cell(nSlices,1);
blockSourceLabels = cell(nSlices,1);

for s = 1:nSlices
    cnt = 0;
    rr = zeros(numel(blockCells{s}), 2);
    keepN = 0;
    labels = cell(1, numel(blockCells{s}));

    for k = 1:numel(blockCells{s})
        blk = blockCells{s}{k};
        nF  = size(blk,3);

        st = cnt + 1;
        if st > Tnew
            break;
        end

        en = min(Tnew, cnt + nF);
        useN = en - st + 1;

        I3D_raw(:,:,s,st:en) = blk(:,:,1:useN);

        keepN = keepN + 1;
        rr(keepN,:) = [st en];
        labels{keepN} = outputBlockInfo{s}{k}.fileName;
        outputBlockInfo{s}{k}.usedFramesReconstructed = useN;

        cnt = en;
        if cnt >= Tnew
            break;
        end
    end

    blockRanges{s} = rr(1:keepN,:);
    blockSourceLabels{s} = labels(1:keepN);
end

% Fallback baseline if split baseline blocks were not defined
for s = 1:nSlices
    if ~isfinite(baselineScalar(s))
        rr = blockRanges{s};
        if ~isempty(rr)
            st = rr(1,1);
            en = rr(1,2);
            tr = localMeanTrace(I3D_raw(:,:,s,st:en));
        else
            tr = localMeanTrace(I3D_raw(:,:,s,:));
        end
        baselineScalar(s) = median(tr);
        baselineFramesUsed(s) = numel(tr);
    end
end

% Estimate cycles from max detected time index across slices
maxT = [];
for s = 1:nSlices
    if ~isempty(sliceDetectedTimes{s})
        maxT = [maxT max(sliceDetectedTimes{s})]; %#ok<AGROW>
    end
end
if isempty(maxT)
    nCycles = NaN;
else
    nCycles = max(maxT);
end

recInfo = struct();
recInfo.nSlices = nSlices;
recInfo.nCycles = nCycles;
recInfo.motorFramesPerSlice = NaN;
recInfo.baselineFramesPerSlice = 0;
recInfo.baselineBlocksPerSlice = splitBaselineBlocksPerSlice;
recInfo.validFramesPerBlock = NaN;
recInfo.totalInitialBaselineFrames = sum(baselineFramesUsed);
recInfo.reconstructedFramesPerSlice = Tnew;
recInfo.fillCountPerSlice = fillCount;
recInfo.sliceBlockCount = sliceBlockCount;
recInfo.blockRanges = blockRanges;
recInfo.blockSourceLabels = blockSourceLabels;
recInfo.baselineScalar = baselineScalar;
recInfo.baselineFramesUsed = baselineFramesUsed;
recInfo.baselineMode = 'Split mode: first N blocks per slice used as baseline (or first kept block if N=0)';
recInfo.rebuildRule = 'For each slice, concatenate split files in ascending t-index: sliceS_t001 + sliceS_t002 + ...';
recInfo.sourceMode = 'SPLIT_MULTI_FILE_FOLDER';

sourceInfo = struct();
sourceInfo.mode = 'SPLIT_MULTI_FILE_FOLDER';
sourceInfo.rawFolder = rawFolder;
sourceInfo.nInputFiles = numel(entries);
sourceInfo.outputBlockInfo = outputBlockInfo;
sourceInfo.detectedSlices = unique(allSlices);
sourceInfo.sliceDetectedTimes = sliceDetectedTimes;

% Keep a lightweight record of all parsed files
lite = rmfield(entries, 'movie');
sourceInfo.allParsedFiles = lite;

end

% =========================================================
% CORRECTION + DESPIKE
% =========================================================
function [I3D, procInfo] = localApplyCorrectionAndDespike(I3D_raw, recInfo, P)

I3D = I3D_raw;
nSlices = recInfo.nSlices;
Tnew = recInfo.reconstructedFramesPerSlice;
baselineScalar = recInfo.baselineScalar;
blockRanges = recInfo.blockRanges;
correctionMode = round(P.correctionMode);

switch correctionMode
    case 1
        correctionModeText = 'RAW_NONE';

    case 2
        for s = 1:nSlices
            refLevel = baselineScalar(s);
            rr = blockRanges{s};

            for k = 1:size(rr,1)
                st = rr(k,1);
                en = rr(k,2);
                tr = localMeanTrace(I3D(:,:,s,st:en));
                blockLevel = median(tr);
                delta = blockLevel - refLevel;
                I3D(:,:,s,st:en) = I3D(:,:,s,st:en) - single(delta);
            end
        end
        correctionModeText = 'ADDITIVE_BLOCK_MATCH_TO_SLICE_BASELINE';

    case 3
        epsVal = 1e-6;
        for s = 1:nSlices
            refLevel = baselineScalar(s);
            if ~isfinite(refLevel) || abs(refLevel) < epsVal
                refLevel = epsVal;
            end

            for t = 1:Tnew
                I3D(:,:,s,t) = 100 * (I3D_raw(:,:,s,t) - single(refLevel)) / single(refLevel);
            end
        end
        correctionModeText = 'SCALAR_PSC_TO_SLICE_BASELINE';

    otherwise
        error('Unknown correction mode.');
end

spikeMask = false(nSlices, Tnew);

if P.doDespike
    for s = 1:nSlices
        tr = localMeanTrace(I3D(:,:,s,:));

        medRun = localRunningMedian(tr, 7);
        resid  = tr - medRun;
        resid0 = median(resid);
        sigma1 = 1.4826 * median(abs(resid - resid0));
        if sigma1 <= 0 || ~isfinite(sigma1)
            sigma1 = std(resid);
        end

        dtr = [0; diff(tr)];
        d0  = median(dtr);
        sigma2 = 1.4826 * median(abs(dtr - d0));
        if sigma2 <= 0 || ~isfinite(sigma2)
            sigma2 = std(dtr);
        end

        idx1 = false(size(tr));
        idx2 = false(size(tr));

        if isfinite(sigma1) && sigma1 > 0
            idx1 = abs(resid - resid0) > P.spikeThr * sigma1;
        end
        if isfinite(sigma2) && sigma2 > 0
            idx2 = abs(dtr - d0) > P.spikeThr * sigma2;
        end

        idxSpike = idx1 | idx2;
        spikeMask(s, idxSpike) = true;

        spikeIdx = find(idxSpike);
        for k = 1:numel(spikeIdx)
            t = spikeIdx(k);

            neigh = max(1, t-2):min(Tnew, t+2);
            neigh(neigh == t) = [];
            neigh = neigh(~spikeMask(s, neigh));

            if isempty(neigh)
                neigh = max(1, t-1):min(Tnew, t+1);
                neigh(neigh == t) = [];
            end

            if ~isempty(neigh)
                repl = squeeze(median(I3D(:,:,s,neigh), 4));
                I3D(:,:,s,t) = single(repl);
            end
        end
    end
end

procInfo = struct();
procInfo.correctionModeText = correctionModeText;
procInfo.spikeMask = spikeMask;

end

% =========================================================
% QC: CONTINUOUS RAW
% =========================================================
function localWriteContinuousRawQC(I, recInfo, qcFolder, TR)

rawGlobal = localMeanTrace(I);
T = numel(rawGlobal);
x = 1:T;

fig = figure('Visible', 'off', 'Position', [100 100 1450 850]);

subplot(2,1,1)
plot(x, rawGlobal, 'k', 'LineWidth', 1.2);
grid on;
xlabel('Frame');
ylabel('Intensity');
title('Continuous raw movie: global mean trace');

yl = ylim;
if recInfo.totalInitialBaselineFrames > 0
    line([recInfo.totalInitialBaselineFrames + 1 recInfo.totalInitialBaselineFrames + 1], yl, ...
        'Color', [0 0.45 0.9], 'LineStyle', '--', 'LineWidth', 1.5);
    text(recInfo.totalInitialBaselineFrames + 1, yl(2), '  motor start', ...
        'Color', [0 0.45 0.9], 'VerticalAlignment', 'top', 'FontWeight', 'bold');
end

subplot(2,1,2)
bar(1:recInfo.nSlices, recInfo.baselineScalar, 0.6);
grid on;
xlabel('Slice');
ylabel('Baseline reference');
title('Continuous mode: baseline reference per slice');

if isfinite(TR)
    txt = sprintf('Frame-based reconstruction | TR shown only for reference: %.4f s/frame', TR);
else
    txt = 'Frame-based reconstruction | TR unavailable';
end

annotation('textbox', [0 0.96 1 0.03], ...
    'String', txt, ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', ...
    'FontSize', 12);

saveas(fig, fullfile(qcFolder, 'motor_QC_continuous_raw.png'));
close(fig);

end

% =========================================================
% QC: SPLIT FILE SOURCE
% =========================================================
function localWriteSplitSourceQC(sourceInfo, qcFolder)

if ~isfield(sourceInfo, 'outputBlockInfo') || isempty(sourceInfo.outputBlockInfo)
    return;
end

nSlices = numel(sourceInfo.outputBlockInfo);

fig = figure('Visible', 'off', 'Position', [120 80 1500 950]);

for s = 1:nSlices
    subplot(nSlices, 1, s);

    infoList = sourceInfo.outputBlockInfo{s};

    if isempty(infoList)
        plot(0,0);
        title(sprintf('Slice %d: no files', s));
        axis tight;
        continue;
    end

    tIdx = zeros(1, numel(infoList));
    nFrm = zeros(1, numel(infoList));

    for k = 1:numel(infoList)
        tIdx(k) = infoList{k}.timeIndex;
        nFrm(k) = infoList{k}.usedFrames;
    end

    bar(tIdx, nFrm, 0.75);
    grid on;
    xlabel('t index');
    ylabel('Frames');
    title(sprintf('Slice %d split blocks used for reconstruction', s));
end

annotation('textbox', [0 0.96 1 0.03], ...
    'String', sprintf('Split mode source QC | Folder: %s', sourceInfo.rawFolder), ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', ...
    'FontSize', 12);

saveas(fig, fullfile(qcFolder, 'motor_QC_split_source_blocks.png'));
close(fig);

end

% =========================================================
% QC: RECONSTRUCTED
% =========================================================
function localWriteReconstructedQC(I3D, recInfo, procInfo, qcFolder, TR)

nSlices = recInfo.nSlices;
Tnew = recInfo.reconstructedFramesPerSlice;

fig = figure('Visible', 'off', 'Position', [120 70 1450 980]);

for s = 1:nSlices
    subplot(nSlices+1, 1, s);

    tr = localMeanTrace(I3D(:,:,s,:));
    x = 1:numel(tr);

    plot(x, tr, 'r', 'LineWidth', 1.1);
    hold on;

    if any(procInfo.spikeMask(s,:))
        plot(find(procInfo.spikeMask(s,:)), tr(procInfo.spikeMask(s,:)), ...
            'ko', 'MarkerSize', 4, 'LineWidth', 1.0);
    end

    grid on;
    xlabel('Frame');

    if strcmpi(procInfo.correctionModeText, 'SCALAR_PSC_TO_SLICE_BASELINE')
        ylabel('PSC (%)');
    else
        ylabel('Intensity');
    end

    title(sprintf('Slice %d | baseline ref = %.3f | frames = %d | blocks = %d', ...
        s, recInfo.baselineScalar(s), Tnew, recInfo.sliceBlockCount(s)));
end

subplot(nSlices+1, 1, nSlices+1)
bar(1:nSlices, recInfo.baselineScalar, 0.6);
grid on;
xlabel('Slice');
ylabel('Baseline');
title('Baseline reference per slice');

if isfinite(TR)
    hdr = sprintf('%s | Frame-based reconstruction | TR reference = %.4f s/frame', ...
        recInfo.sourceMode, TR);
else
    hdr = sprintf('%s | Frame-based reconstruction | TR unavailable', recInfo.sourceMode);
end

annotation('textbox', [0 0.96 1 0.03], ...
    'String', hdr, ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', ...
    'FontSize', 12);

saveas(fig, fullfile(qcFolder, 'motor_QC_reconstructed.png'));
close(fig);

end

% =========================================================
% LOAD MOVIE FROM MAT
% =========================================================
function [mov, meta] = localLoadMovieFromMat(fpath)

S = load(fpath);
mov = [];
movieField = '';

preferredFields = { ...
    'I', 'movie', 'Movie', 'data', 'Data', ...
    'DopplerMovie', 'dopplerMovie', 'PDI', 'pdi', ...
    'img', 'Img', 'frames', 'Frames'};

for i = 1:numel(preferredFields)
    fn = preferredFields{i};
    if isfield(S, fn)
        cand = localForce3DMovie(S.(fn));
        if ~isempty(cand)
            mov = cand;
            movieField = fn;
            break;
        end
    end
end

if isempty(mov)
    fns = fieldnames(S);
    for i = 1:numel(fns)
        v = S.(fns{i});

        if isnumeric(v)
            cand = localForce3DMovie(v);
            if ~isempty(cand)
                mov = cand;
                movieField = fns{i};
                break;
            end
        elseif isstruct(v) && isscalar(v)
            subNames = fieldnames(v);
            for j = 1:numel(subNames)
                subVal = v.(subNames{j});
                if isnumeric(subVal)
                    cand = localForce3DMovie(subVal);
                    if ~isempty(cand)
                        mov = cand;
                        movieField = '';
                        break;
                    end
                end
            end
        end

        if ~isempty(mov)
            break;
        end
    end
end

if isempty(mov)
    error('No valid 3D movie found in MAT file: %s', fpath);
end

if ~isempty(movieField) && isfield(S, movieField)
    S = rmfield(S, movieField);
end

meta = S;

end

function out = localForce3DMovie(A)

out = [];

if ~isnumeric(A) || isempty(A)
    return;
end

if ndims(A) == 3
    out = single(A);
    return;
end

if ndims(A) == 4
    sz = size(A);
    if sz(3) == 1
        out = single(squeeze(A));
        return;
    end
    if sz(4) == 1
        out = single(squeeze(A));
        return;
    end
end

end

% =========================================================
% SPLIT FILE PARSING
% =========================================================
function [sliceIdx, timeIdx, metaTs, gStart, gEnd] = localInferSplitFileInfo(fileName, meta)

sliceIdx = NaN;
timeIdx  = NaN;
metaTs   = '';
gStart   = NaN;
gEnd     = NaN;

% filename patterns
tok = regexpi(fileName, 'slice[_\- ]*(\d+)', 'tokens', 'once');
if isempty(tok)
    tok = regexpi(fileName, '(^|[_\-])s[_\- ]*(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        tok = tok(2);
    end
end
if ~isempty(tok)
    sliceIdx = str2double(tok{1});
end

tok = regexpi(fileName, '(^|[_\-])t[_\- ]*(\d+)', 'tokens', 'once');
if ~isempty(tok)
    timeIdx = str2double(tok{2});
else
    tok = regexpi(fileName, 'time[_\- ]*(\d+)', 'tokens', 'once');
    if ~isempty(tok)
        timeIdx = str2double(tok{1});
    end
end

% metadata fallback
if ~isfinite(sliceIdx)
    v = localGetMetaField(meta, {'sliceIndex','slice','motorSlice','slice_id'});
    if ~isempty(v)
        sliceIdx = double(v);
    end
end

if ~isfinite(timeIdx)
    v = localGetMetaField(meta, {'timeIndex','tIndex','blockIndex','time_id','cycleIndex'});
    if ~isempty(v)
        timeIdx = double(v);
    end
end

v = localGetMetaField(meta, {'timestamp','timeStamp','createdOn','saveTime','acqTime','datetime'});
if ~isempty(v)
    if ischar(v)
        metaTs = v;
    elseif isnumeric(v) && isscalar(v)
        try
            metaTs = datestr(v, 30);
        catch
            metaTs = num2str(v);
        end
    end
end

v = localGetMetaField(meta, {'globalFrameStart','frameStartGlobal','startFrameGlobal'});
if ~isempty(v)
    gStart = double(v);
end

v = localGetMetaField(meta, {'globalFrameEnd','frameEndGlobal','endFrameGlobal'});
if ~isempty(v)
    gEnd = double(v);
end

end

function subset = localAssignMissingTimeIndices(subset)

if isempty(subset)
    return;
end

hasTime = isfinite([subset.timeIndex]);

if all(~hasTime)
    [~, ord] = sort([subset.fileDatenum]);
    subset = subset(ord);
    for k = 1:numel(subset)
        subset(k).timeIndex = k;
    end
    return;
end

if any(~hasTime)
    known = [subset(hasTime).timeIndex];
    nextT = max(known) + 1;

    missIdx = find(~hasTime);
    [~, ord] = sort([subset(missIdx).fileDatenum]);
    missIdx = missIdx(ord);

    for i = 1:numel(missIdx)
        subset(missIdx(i)).timeIndex = nextT;
        nextT = nextT + 1;
    end
end

end

function subset = localSortSplitEntries(subset)

if isempty(subset)
    return;
end

key1 = [subset.timeIndex];
key2 = [subset.fileDatenum];

M = [(1:numel(subset))' key1(:) key2(:)];
M = sortrows(M, [2 3 1]);
subset = subset(M(:,1));

end

function blk = localTrimMovieBlock(mov, trimFrames, fileLabel)

nF = size(mov,3);
st = 1 + trimFrames;
en = nF - trimFrames;

if en < st
    error('Trim frames too large for block: %s', fileLabel);
end

blk = mov(:,:,st:en);

end

% =========================================================
% METADATA FIELD SEARCH
% =========================================================
function v = localGetMetaField(S, candidates)

v = [];

if isempty(S)
    return;
end

if isstruct(S)
    % direct hit
    for i = 1:numel(candidates)
        if isfield(S, candidates{i})
            tmp = S.(candidates{i});
            if isnumeric(tmp) && isscalar(tmp)
                v = tmp;
                return;
            elseif ischar(tmp)
                v = tmp;
                return;
            end
        end
    end

    % one-level recursive hit
    fns = fieldnames(S);
    for i = 1:numel(fns)
        tmp = S.(fns{i});
        if isstruct(tmp) && isscalar(tmp)
            v = localGetMetaField(tmp, candidates);
            if ~isempty(v)
                return;
            end
        end
    end
end

end

% =========================================================
% BASIC HELPERS
% =========================================================
function tr = localMeanTrace(A)
tmp = squeeze(mean(mean(A,1),2));
tr = double(tmp(:));
end

function y = localRunningMedian(x, win)
x = double(x(:));
n = numel(x);
halfW = floor(win/2);
y = zeros(n,1);

for i = 1:n
    i1 = max(1, i-halfW);
    i2 = min(n, i+halfW);
    y(i) = median(x(i1:i2));
end
end

% =========================================================
% UI DIALOG
% =========================================================
function P = localMotorDialog(defaults, TR, hasInputMovie)

P = [];

bg  = [0.09 0.11 0.14];
bg2 = [0.13 0.15 0.19];
fg  = [1.00 1.00 1.00];
mut = [0.78 0.84 0.92];
edb = [0.18 0.20 0.24];
green = [0.16 0.64 0.32];
red   = [0.78 0.18 0.18];
blue  = [0.14 0.45 0.82];
yellow= [0.96 0.80 0.22];

dlgW = 900;
dlgH = 620;
scr = get(0, 'ScreenSize');
dlgX = max(50, round((scr(3)-dlgW)/2));
dlgY = max(50, round((scr(4)-dlgH)/2));

d = dialog( ...
    'Name', 'Motor Reconstruction (frame-based)', ...
    'Position', [dlgX dlgY dlgW dlgH], ...
    'WindowStyle', 'modal', ...
    'Resize', 'off', ...
    'Color', bg, ...
    'CloseRequestFcn', @(~,~)localCancel());

uicontrol(d, 'Style', 'text', ...
    'Position', [20 580 860 26], ...
    'String', 'Motor Reconstruction (Frame-Based)', ...
    'BackgroundColor', bg, ...
    'ForegroundColor', fg, ...
    'FontSize', 16, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');

uicontrol(d, 'Style', 'text', ...
    'Position', [20 556 860 18], ...
    'String', defaults.infoTRString, ...
    'BackgroundColor', bg, ...
    'ForegroundColor', mut, ...
    'FontSize', 10, ...
    'HorizontalAlignment', 'center');

uicontrol(d, 'Style', 'text', ...
    'Position', [24 528 852 18], ...
    'String', ['Continuous = one long scan.  Split = separate MAT files per slice/timepoint ' ...
               '(example: slice1_t001.mat, slice2_t001.mat, slice1_t002.mat ...)'], ...
    'BackgroundColor', bg, ...
    'ForegroundColor', [0.65 0.90 0.75], ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

uipanel('Parent', d, ...
    'Units', 'pixels', ...
    'Position', [20 118 860 392], ...
    'BackgroundColor', bg2, ...
    'ForegroundColor', blue, ...
    'Title', 'Settings', ...
    'FontWeight', 'bold', ...
    'FontSize', 11);

labelX = 40;
editX  = 560;
editW  = 250;
rowH   = 28;
rowY   = [472 432 392 352 312 272 232 192 152];

mkLbl = @(txt,y) uicontrol(d, 'Style', 'text', ...
    'Position', [labelX y 500 rowH], ...
    'String', txt, ...
    'BackgroundColor', bg2, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

mkEdit = @(txt,y) uicontrol(d, 'Style', 'edit', ...
    'Position', [editX y editW rowH], ...
    'String', txt, ...
    'BackgroundColor', edb, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

mkLbl('Source mode', rowY(1));
hSource = uicontrol(d, 'Style', 'popupmenu', ...
    'Position', [editX rowY(1) editW rowH], ...
    'String', { ...
        '1) Continuous single raw movie', ...
        '2) Split MAT files from raw folder'}, ...
    'Value', defaults.sourceMode, ...
    'BackgroundColor', edb, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localRefreshMode());

mkLbl('Number of slices (split mode: 0 = auto detect)', rowY(2));
hSlices = mkEdit(num2str(defaults.nSlices), rowY(2));

mkLbl('Continuous mode: frames per slice', rowY(3));
hMotorFrames = mkEdit(num2str(defaults.motorFramesPerSlice), rowY(3));

mkLbl('Continuous mode: initial baseline frames per slice', rowY(4));
hBaseFrames = mkEdit(num2str(defaults.baseFramesPerSlice), rowY(4));

mkLbl('Split mode: baseline blocks per slice to exclude/use as reference', rowY(5));
hSplitBaseBlocks = mkEdit(num2str(defaults.splitBaselineBlocksPerSlice), rowY(5));

mkLbl('Trim frames at start and end of each block/file', rowY(6));
hTrim = mkEdit(num2str(defaults.trimFrames), rowY(6));

mkLbl('Residual spike threshold (robust SD)', rowY(7));
hSpike = mkEdit(num2str(defaults.spikeThr), rowY(7));

mkLbl('Correction mode', rowY(8));
hMode = uicontrol(d, 'Style', 'popupmenu', ...
    'Position', [editX rowY(8) editW rowH], ...
    'String', { ...
        '1) None (raw only)', ...
        '2) Additive match to slice baseline', ...
        '3) Scalar PSC to slice baseline'}, ...
    'Value', defaults.correctionMode, ...
    'BackgroundColor', edb, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold');

mkLbl('Split mode: raw folder containing MAT files', rowY(9));
hFolder = mkEdit(defaults.rawFolder, rowY(9));

hBrowse = uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [820 rowY(9) 52 rowH], ...
    'String', '...', ...
    'BackgroundColor', yellow, ...
    'ForegroundColor', [0 0 0], ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localBrowseFolder());

hDespike = uicontrol(d, 'Style', 'checkbox', ...
    'Position', [42 104 360 22], ...
    'String', 'Apply residual whole-frame despiking after reconstruction', ...
    'Value', defaults.doDespike, ...
    'BackgroundColor', bg, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold');

hModeText = uicontrol(d, 'Style', 'text', ...
    'Position', [20 78 860 18], ...
    'String', '', ...
    'BackgroundColor', bg, ...
    'ForegroundColor', [1.0 0.82 0.35], ...
    'FontSize', 10, ...
    'HorizontalAlignment', 'center');

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [150 22 130 40], ...
    'String', 'Use 188', ...
    'BackgroundColor', blue, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localPreset188());

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [320 22 120 40], ...
    'String', 'Cancel', ...
    'BackgroundColor', red, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localCancel());

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [480 22 230 40], ...
    'String', 'Run Reconstruction', ...
    'BackgroundColor', green, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localOK());

localRefreshMode();
uiwait(d);

if ishandle(d)
    out = getappdata(d, 'MotorDialogOutput');
    if ~isempty(out)
        P = out;
    end
    delete(d);
end

    function localPreset188()
        set(hMotorFrames, 'String', '188');
        set(hBaseFrames,  'String', '188');
    end

    function localBrowseFolder()
        pth = uigetdir(pwd, 'Select raw folder with split MAT files');
        if isequal(pth, 0)
            return;
        end
        set(hFolder, 'String', pth);
    end

    function localRefreshMode()
        v = get(hSource, 'Value');

        if v == 1
            set(hMotorFrames,     'Enable', 'on');
            set(hBaseFrames,      'Enable', 'on');
            set(hSplitBaseBlocks, 'Enable', 'off');
            set(hFolder,          'Enable', 'off');
            set(hBrowse,          'Enable', 'off');

            if hasInputMovie
                msg = 'Continuous mode uses the input movie I directly.';
                col = [0.70 0.92 0.78];
            else
                msg = 'Continuous mode needs a provided input movie I.';
                col = [1.00 0.62 0.62];
            end
        else
            set(hMotorFrames,     'Enable', 'off');
            set(hBaseFrames,      'Enable', 'off');
            set(hSplitBaseBlocks, 'Enable', 'on');
            set(hFolder,          'Enable', 'on');
            set(hBrowse,          'Enable', 'on');

            msg = 'Split mode loads all MAT files from the selected folder and rebuilds by slice + t index.';
            col = [0.70 0.92 0.78];
        end

        set(hModeText, 'String', msg, 'ForegroundColor', col);
    end

    function localOK()
        out = struct();

        out.sourceMode = get(hSource, 'Value');
        out.nSlices = str2double(strtrim(get(hSlices, 'String')));
        out.motorFramesPerSlice = str2double(strtrim(get(hMotorFrames, 'String')));
        out.baseFramesPerSlice = str2double(strtrim(get(hBaseFrames, 'String')));
        out.splitBaselineBlocksPerSlice = str2double(strtrim(get(hSplitBaseBlocks, 'String')));
        out.trimFrames = str2double(strtrim(get(hTrim, 'String')));
        out.spikeThr = str2double(strtrim(get(hSpike, 'String')));
        out.correctionMode = get(hMode, 'Value');
        out.doDespike = logical(get(hDespike, 'Value'));
        out.rawFolder = strtrim(get(hFolder, 'String'));

        vals = [out.nSlices out.motorFramesPerSlice out.baseFramesPerSlice ...
                out.splitBaselineBlocksPerSlice out.trimFrames out.spikeThr];
        if any(isnan(vals))
            errordlg('Please enter valid numeric values.', 'Invalid input', 'modal');
            return;
        end

        if out.sourceMode == 1
            if ~hasInputMovie
                errordlg('Continuous mode was selected, but no input movie I is available.', ...
                    'Missing input movie', 'modal');
                return;
            end
            if out.nSlices < 1 || mod(out.nSlices,1) ~= 0
                errordlg('Number of slices must be a positive integer for continuous mode.', ...
                    'Invalid slices', 'modal');
                return;
            end
            if out.motorFramesPerSlice < 1 || mod(out.motorFramesPerSlice,1) ~= 0
                errordlg('Continuous frames per slice must be an integer >= 1.', ...
                    'Invalid frames', 'modal');
                return;
            end
            if out.baseFramesPerSlice < 0 || mod(out.baseFramesPerSlice,1) ~= 0
                errordlg('Continuous baseline frames per slice must be an integer >= 0.', ...
                    'Invalid baseline', 'modal');
                return;
            end
        else
            if out.nSlices < 0 || mod(out.nSlices,1) ~= 0
                errordlg('Number of slices must be an integer >= 0 in split mode.', ...
                    'Invalid slices', 'modal');
                return;
            end
            if isempty(out.rawFolder) || ~exist(out.rawFolder, 'dir')
                errordlg('Please select a valid raw folder for split mode.', ...
                    'Invalid folder', 'modal');
                return;
            end
            if out.splitBaselineBlocksPerSlice < 0 || mod(out.splitBaselineBlocksPerSlice,1) ~= 0
                errordlg('Split baseline blocks per slice must be an integer >= 0.', ...
                    'Invalid split baseline', 'modal');
                return;
            end
        end

        if out.trimFrames < 0 || mod(out.trimFrames,1) ~= 0
            errordlg('Trim frames must be an integer >= 0.', 'Invalid trim', 'modal');
            return;
        end

        if out.spikeThr <= 0
            errordlg('Spike threshold must be > 0.', 'Invalid spike threshold', 'modal');
            return;
        end

        setappdata(d, 'MotorDialogOutput', out);
        uiresume(d);
    end

    function localCancel()
        setappdata(d, 'MotorDialogOutput', []);
        if strcmp(get(d, 'Visible'), 'on')
            uiresume(d);
        else
            delete(d);
        end
    end

end