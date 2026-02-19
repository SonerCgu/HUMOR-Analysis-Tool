function [out, stats] = scrubbing(data, TR, saveRoot, tag)

% ==========================================================
% SCRUBBING (rDVARS) WITH OPTIONAL TRIMMING
% No waitbars
% Full QC PNG saving
% Returns full stats for Studio log
% ==========================================================

if nargin < 4 || isempty(tag)
    tag = datestr(now,'yyyymmdd_HHMMSS');
end

if nargin < 3 || isempty(saveRoot)
    saveRoot = pwd;
end

if numel(TR) > 1
    TR = TR(end);
end
TR = double(TR);

%% ---------------------------------------------------------
% FORCE 4D
%% ---------------------------------------------------------
sz = size(data);

if ndims(data) == 3
    Y = sz(1); X = sz(2); T = sz(3);
    Z = 1;
    data4D = reshape(data,Y,X,1,T);
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

%% ---------------------------------------------------------
% OPTIONAL TRIMMING
%% ---------------------------------------------------------
choice = questdlg('Trim before scrubbing?',...
                  'Scrubbing','Yes','No','No');

if strcmp(choice,'Yes')

    answer = inputdlg({'Trim START seconds:',...
                       'Trim END seconds:'},...
                       'Trimming',[1 40],{'30','30'});

    if ~isempty(answer)

        startSec = str2double(answer{1});
        endSec   = str2double(answer{2});

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

%% ---------------------------------------------------------
% MASK
%% ---------------------------------------------------------
meanVol = mean(data4D,4);
mask = meanVol > 0.05 * max(meanVol(:));
if ~any(mask(:))
    mask = true(size(meanVol));
end

flatAll = reshape(double(data4D),[],T);
maskVec = mask(:);
flatMasked = flatAll(maskVec,:);

%% ---------------------------------------------------------
% DVARS
%% ---------------------------------------------------------
diffVol = diff(flatMasked,1,2);
DVARS = sqrt(mean(diffVol.^2,1));
DVARS = [0 DVARS];

medDV = median(DVARS);
madDV = mad(DVARS,1);

TH = medDV + 2.5 * madDV;
badMask = DVARS > TH;
badIdx = find(badMask);

%% ---------------------------------------------------------
% INTERPOLATE BAD VOLUMES
%% ---------------------------------------------------------
if any(badMask)

    goodIdx = find(~badMask);

    if numel(goodIdx) >= 2
        interpData = interp1(goodIdx,...
                             flatAll(:,goodIdx)',...
                             1:T,'linear','extrap')';
        flatAll(:,badMask) = interpData(:,badMask);
    end
end

out = reshape(flatAll,Y,X,Z,T);

%% ---------------------------------------------------------
% STATS
%% ---------------------------------------------------------
stats.originalVolumes = origT;
stats.finalVolumes = T;
stats.removedVolumes = numel(badIdx);
stats.percentRemoved = 100 * numel(badIdx) / T;
stats.threshold = TH;

stats.trimmed = trimmed;
stats.trimStartVol = trimStartVol;
stats.trimEndVol   = trimEndVol;
stats.trimStartSec = trimStartVol * TR;
stats.trimEndSec   = trimEndVol   * TR;
stats.newTotalTime = T * TR;

%% ---------------------------------------------------------
% QC SAVE (ALWAYS)
%% ---------------------------------------------------------
qcDir = fullfile(saveRoot,'Preprocessing','QC_Scrubbing');
if ~exist(qcDir,'dir')
    mkdir(qcDir);
end

qcFile = fullfile(qcDir,['Scrubbing_QC_' tag '.png']);

% Compute global signal
globalSig = mean(flatMasked,1);

fig = figure('Visible','off','Color','w');

subplot(2,1,1)
plot(DVARS,'k','LineWidth',1)
hold on
plot([1 length(DVARS)], [TH TH], 'r--', 'LineWidth',1.5)
plot(find(badMask), DVARS(badMask),'ro','MarkerSize',4)
title('rDVARS')
legend({'rDVARS','Threshold','Flagged volumes'},'Location','best')
xlabel('Volume')
ylabel('rDVARS')

subplot(2,1,2)
plot(globalSig,'b','LineWidth',1)
hold on
plot(find(badMask), globalSig(badMask),'ro','MarkerSize',4)
title('Global Signal')
legend({'Global signal','Flagged volumes'},'Location','best')
xlabel('Volume')
ylabel('Signal')

saveas(fig,qcFile);
close(fig);

stats.qcFile = qcFile;

end
