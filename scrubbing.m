function [out, stats] = scrubbing(data, TR, saveRoot, tag)
% ==========================================================
% SCRUBBING (MEMORY-SAFE)
%   - Detection: DVARS or Global Signal
%   - Interp   : Linear or PCHIP
% Optional trimming
% Full QC PNG saving
% MATLAB 2017b compatible
% ==========================================================

if nargin < 4 || isempty(tag)
    tag = datestr(now,'yyyymmdd_HHMMSS');
end
if nargin < 3 || isempty(saveRoot)
    saveRoot = pwd;
end
if numel(TR) > 1, TR = TR(end); end
TR = double(TR);

% ---------------- FORCE 4D ----------------
data = single(data);
sz = size(data);

if ndims(data) == 3
    Y = sz(1); X = sz(2); T = sz(3);
    Z = 1;
    data4D = reshape(data, Y, X, 1, T);
elseif ndims(data) == 4
    Y = sz(1); X = sz(2); Z = sz(3); T = sz(4);
    data4D = data;
else
    error('Data must be 3D or 4D.');
end

origT = T;
trimmed = false;
trimStartVol = 0;
trimEndVol   = 0;

% ---------------- OPTIONAL TRIM ----------------
trimChoice = questdlg('Trim before scrubbing?', 'Scrubbing','Yes','No','No');
if strcmp(trimChoice,'Yes')
    answer = inputdlg({'Trim START seconds:','Trim END seconds:'}, ...
                      'Trimming',[1 40],{'30','30'});
    if ~isempty(answer)
        startSec = str2double(answer{1});
        endSec   = str2double(answer{2});
        if ~isfinite(startSec), startSec = 0; end
        if ~isfinite(endSec),   endSec   = 0; end

        trimStartVol = max(0, round(startSec/TR));
        trimEndVol   = max(0, round(endSec/TR));

        newStart = trimStartVol + 1;
        newEnd   = T - trimEndVol;

        if newEnd > newStart
            data4D = data4D(:,:,:,newStart:newEnd);
            T = size(data4D,4);
            trimmed = true;
        end
    end
end

% ---------------- METHOD ----------------
method = questdlg('Select scrubbing detection method:', ...
                  'Detection Method', ...
                  'DVARS','Global Signal','DVARS');
if isempty(method)
    error('Scrubbing cancelled.');
end

% ---------------- INTERP METHOD ----------------
interpChoice = questdlg('Interpolation method for flagged volumes:', ...
                        'Interpolation', ...
                        'Linear','PCHIP','Linear');
if isempty(interpChoice)
    error('Scrubbing cancelled.');
end

switch interpChoice
    case 'Linear'
        interpMethod = 'linear';
    case 'PCHIP'
        interpMethod = 'pchip';
    otherwise
        interpMethod = 'linear';
end

% ---------------- MASK ----------------
meanVol = mean(data4D,4);
mx = max(meanVol(:));
if mx <= 0 || ~isfinite(mx)
    mask = true(size(meanVol));
else
    mask = meanVol > 0.05 * mx;
    if ~any(mask(:)), mask = true(size(meanVol)); end
end

% ---------------- FLATTEN (SINGLE!) ----------------
flatAll = reshape(data4D, [], T);     % single [V x T]
maskVec = mask(:);
flatMasked = flatAll(maskVec, :);    % single [Vm x T]

% ---------------- METRIC ----------------
switch method
    case 'DVARS'
        % DVARS(t) = sqrt(mean((Vt - Vt-1)^2))
        d = diff(single(flatMasked), 1, 2);                % [Vm x (T-1)]
        metric = sqrt(mean(double(d).^2, 1));              % double [1 x (T-1)]
        metric = [0 metric];                               % [1 x T]
    case 'Global Signal'
        metric = mean(double(flatMasked), 1);              % double [1 x T]
end

% ---------------- THRESHOLD ----------------
medVal = median(metric);
madVal = mad(metric, 1);     % median absolute deviation (robust)
k = 2.5;
TH = medVal + k * madVal;

badMask = metric > TH;
badIdx  = find(badMask);
goodIdx = find(~badMask);

% ---------------- INTERPOLATE (CHUNKED, ONLY BAD FRAMES) ----------------
% This avoids creating interpData for ALL frames.
if ~isempty(badIdx) && numel(goodIdx) >= 2

    V = size(flatAll,1);
    % Chunk size: keep temporary arrays reasonable
    chunkV = 2000;   % safe default; adjust if you have lots of RAM

    tGood = goodIdx(:);          % column vector
    tBad  = badIdx(:);           % column vector

    for v0 = 1:chunkV:V
        v1 = min(V, v0 + chunkV - 1);

        % Ygood: [numGood x chunk] in double for interp1 stability
        Ygood = double(flatAll(v0:v1, tGood)).';   % transpose -> [G x chunk]

        % Interpolate ONLY bad times -> returns [B x chunk]
        Ybad = interp1(tGood, Ygood, tBad, interpMethod, 'extrap');

        % Write back into flatAll (single)
        flatAll(v0:v1, tBad) = single(Ybad.');     % transpose back -> [chunk x B]
    end
end

out = reshape(flatAll, Y, X, Z, T);

% ---------------- STATS ----------------
stats.originalVolumes = origT;
stats.finalVolumes    = T;
stats.flaggedVolumes  = numel(badIdx);
stats.removedVolumes  = numel(badIdx);                 % keep compatibility
stats.percentFlagged  = 100 * numel(badIdx) / max(1,T);
stats.percentRemoved  = stats.percentFlagged;          % keep compatibility
stats.threshold       = TH;
stats.method          = method;
stats.interpMethod    = interpMethod;

stats.trimmed       = trimmed;
stats.trimStartVol  = trimStartVol;
stats.trimEndVol    = trimEndVol;
stats.trimStartSec  = trimStartVol * TR;
stats.trimEndSec    = trimEndVol   * TR;
stats.newTotalTime  = T * TR;

% ---------------- QC SAVE ----------------
qcDir = fullfile(saveRoot,'Preprocessing','QC_Scrubbing');
if ~exist(qcDir,'dir'), mkdir(qcDir); end

qcFile = fullfile(qcDir, sprintf('Scrubbing_%s_%s_%s.png', method, interpMethod, tag));

globalSig = mean(double(flatMasked), 1);

fig = figure('Visible','off','Color','w');

subplot(2,1,1)
plot(metric,'k','LineWidth',1); hold on
plot([1 length(metric)], [TH TH], 'r--', 'LineWidth',1.5)
plot(badIdx, metric(badIdx),'ro','MarkerSize',4)
title(sprintf('Detection Metric - %s', method))
legend({'Metric','Threshold','Flagged volumes'},'Location','best')
xlabel('Volume'); ylabel('Metric')

subplot(2,1,2)
plot(globalSig,'b','LineWidth',1); hold on
plot(badIdx, globalSig(badIdx),'ro','MarkerSize',4)
title('Global Signal (reference)')
legend({'Global signal','Flagged volumes'},'Location','best')
xlabel('Volume'); ylabel('Signal')

saveas(fig, qcFile);
close(fig);

stats.qcFile = qcFile;

end
