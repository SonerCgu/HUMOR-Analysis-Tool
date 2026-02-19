function [out, stats] = despike(data, zthr, saveRoot, tag)

% ==========================================================
% VOXEL-WISE MAD DESPIKING
% No waitbars
% Full QC PNG saving
% Returns full stats
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

flat = reshape(double(data4D),[],T);
Nvox = size(flat,1);

totalPoints = numel(flat);
removedPoints = 0;
allRobustZ = [];

for v = 1:Nvox

    sig = flat(v,:);
    med = median(sig,'omitnan');
    madv = median(abs(sig - med),'omitnan');

    if madv < eps
        continue
    end

    robustZ = 0.6745 * (sig - med) / madv;
    allRobustZ = [allRobustZ robustZ];

    spikeMask = abs(robustZ) > zthr;

    if any(spikeMask)

        removedPoints = removedPoints + sum(spikeMask);

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

%% ---------------------------------------------------------
% STATS
%% ---------------------------------------------------------
stats.totalPoints = totalPoints;
stats.removedPoints = removedPoints;
stats.percentRemoved = 100 * removedPoints / totalPoints;
stats.zThreshold = zthr;


% -------------------------------------------------------
% QC FIGURE
% -------------------------------------------------------
fig = figure('Visible','off','Color','w');

subplot(3,1,1)
plot(spikesPerFrame,'k','LineWidth',1)
title('Spikes per frame')
xlabel('Frame')
ylabel('# spikes')
legend({'Spikes per frame'},'Location','best')

subplot(3,1,2)
histogram(spikesPerFrame,50)
title('Distribution of spikes per frame')
xlabel('# spikes')
ylabel('Count')

subplot(3,1,3)
imagesc(spikeMap(:,:,round(Z/2)))
colorbar
title('Spike spatial map (mid slice)')
xlabel('X')
ylabel('Y')

saveas(fig,qcFile)
close(fig)

close(f);

stats.qcFile = qcFile;

end
