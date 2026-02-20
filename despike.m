function [out, stats] = despike(data, zthr, saveRoot, tag)

% ==========================================================
% VOXEL-WISE MAD DESPIKING (STABLE VERSION)
% ==========================================================

if nargin < 2 || isempty(zthr)
    zthr = 5;
end

if nargin < 4 || isempty(tag)
    tag = datestr(now,'yyyymmdd_HHMMSS');
end

if nargin < 3 || isempty(saveRoot)
    saveRoot = pwd;
end

data = single(data);
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

flat = reshape(data4D,[],T);
Nvox = size(flat,1);

totalPoints = numel(flat);
removedPoints = 0;

spikesPerFrame = zeros(1,T,'single');
spikeMap = zeros(Y,X,Z,'single');

for v = 1:Nvox

    sig = flat(v,:);
    med = median(sig);
    madv = median(abs(sig - med));

    if madv < eps
        continue
    end

    robustZ = 0.6745 * (sig - med) / madv;
    spikeMask = abs(robustZ) > zthr;

    if any(spikeMask)

        removedPoints = removedPoints + sum(spikeMask);
        spikesPerFrame = spikesPerFrame + spikeMask;

        [yy,xx,zz] = ind2sub([Y,X,Z],v);
        spikeMap(yy,xx,zz) = spikeMap(yy,xx,zz) + sum(spikeMask);

        good = ~spikeMask;

        if nnz(good) >= 2
            x = 1:T;
            sig(spikeMask) = interp1(x(good),sig(good),...
                                     x(spikeMask),'linear','extrap');
            flat(v,:) = sig;
        end
    end
end

out = reshape(flat,Y,X,Z,T);

% =========================
% STATS
% =========================
stats.totalPoints = totalPoints;
stats.removedPoints = removedPoints;
stats.percentRemoved = 100 * removedPoints / totalPoints;
stats.zThreshold = zthr;

% =========================
% QC FIGURE
% =========================
qcFolder = fullfile(saveRoot,'Preprocessing','despike_QC');
if ~exist(qcFolder,'dir')
    mkdir(qcFolder);
end

qcFile = fullfile(qcFolder,['despike_QC_' tag '.png']);

fig = figure('Visible','off','Color','w','Position',[200 200 1200 800]);

subplot(3,1,1)
plot(spikesPerFrame,'k','LineWidth',1)
title('Spikes per frame')
xlabel('Frame')
ylabel('# spikes')
grid on

subplot(3,1,2)
hist(spikesPerFrame,50)
title('Distribution of spikes per frame')
xlabel('# spikes')
ylabel('Count')

subplot(3,1,3)
midSlice = round(Z/2);
imagesc(spikeMap(:,:,midSlice))
colorbar
title('Spike spatial map (mid slice)')
xlabel('X')
ylabel('Y')

annotation('textbox',[0 0.95 1 0.04],...
    'String','Voxel-wise MAD Despiking QC',...
    'EdgeColor','none',...
    'HorizontalAlignment','center',...
    'FontWeight','bold');

saveas(fig,qcFile);
close(fig)

stats.qcFile = qcFile;

clear flat spikeMap spikesPerFrame
drawnow

end
