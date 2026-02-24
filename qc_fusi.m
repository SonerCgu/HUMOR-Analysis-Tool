function qc_fusi(data, meta, exportPath, opts)
% qc_fusi — fUSI Studio QC engine (MATLAB 2017b)
% ============================================================
% Keeps existing QC plots and ADDS paper-style QC:
%   - Burst error QC (ratio map + noisy voxels + coverage over time)
%   - tSNR map + histogram (baseline noise), mean image, temporal CV
%   - CNR QC (true if stim/baseline known; else pseudo)
%   - Common-mode QC (block correlation)
%   - Integrated QC summary (Burst * tSNR * CNR * CommonMode)
%   - PCA QC auto-saves AND auto-closes (no CloseRequestFcn)
%
% Output folders (NEW):
%   exportPath/QC/<datasetTag>/png
%   exportPath/QC/<datasetTag>/mat
%   optionally: /QC/<datasetTag>/<timestamp>/...
%
% Inputs:
%   data.I  : 3D [Y X T] or 4D [Y X Z T]
%   data.TR : scalar TR (sec)
%   meta    : optional; used for baseline/stim frames if present
%   exportPath : analysed dataset root
%   opts    : flags + thresholds
%
% Required opts fields (if missing -> defaults):
%   frequency spatial temporal motion stability framerate pca
%   burst cnr commonmode
%   datasetTag, useTimestampSubfolder

if nargin < 4
    error('qc_fusi requires data, meta, exportPath, opts');
end
if ~isfield(data,'I') || isempty(data.I), error('qc_fusi: data.I missing'); end
if ~isfield(data,'TR') || isempty(data.TR), error('qc_fusi: data.TR missing'); end

I  = data.I;
TR = data.TR;
if numel(TR) > 1, TR = TR(end); end
TR = double(TR);

% ------------------ flags (old + new) ------------------
opts = setFlagDefault(opts,'frequency',false);
opts = setFlagDefault(opts,'spatial',false);
opts = setFlagDefault(opts,'temporal',false);
opts = setFlagDefault(opts,'motion',false);
opts = setFlagDefault(opts,'stability',false);
opts = setFlagDefault(opts,'pca',false);
opts = setFlagDefault(opts,'framerate',false);

opts = setFlagDefault(opts,'burst',false);
opts = setFlagDefault(opts,'cnr',false);
opts = setFlagDefault(opts,'commonmode',false);

% If user didn’t request burst/cnr/commonmode explicitly, tie them to temporal
if ~isfield(opts,'burst') || isempty(opts.burst), opts.burst = opts.temporal; end
if ~isfield(opts,'cnr') || isempty(opts.cnr), opts.cnr = opts.temporal; end
if ~isfield(opts,'commonmode') || isempty(opts.commonmode), opts.commonmode = opts.temporal; end

% ------------------ dataset output folder controls (NEW) ------------------
if ~isfield(opts,'datasetTag') || isempty(opts.datasetTag)
    opts.datasetTag = 'raw';
end
if ~isfield(opts,'useTimestampSubfolder') || isempty(opts.useTimestampSubfolder)
    opts.useTimestampSubfolder = false;
end

datasetTagSafe = sanitizeTag(opts.datasetTag);

% ------------------ thresholds / params ------------------
opts = setDefault(opts,'THbursterror', 4.0);     % voxel burst ratio threshold
opts = setDefault(opts,'THnoisyvoxels', 0.10);   % fraction noisy voxels allowed
opts = setDefault(opts,'baselineSec', 30);       % fallback baseline window length (sec)
opts = setDefault(opts,'THSNR', 20);             % global tSNR threshold
opts = setDefault(opts,'THCNR', 0.5);            % global CNR threshold
opts = setDefault(opts,'PCNR', 0.05);            % top fraction for CNR pooling
opts = setDefault(opts,'Nblock', 10);            % common-mode block grid
opts = setDefault(opts,'THCM', 0.6);             % corr threshold
opts = setDefault(opts,'THpor', 0.20);           % portion threshold
opts = setDefault(opts,'maxTCorrFrames', 1500);  % time downsample cap for common-mode
opts = setDefault(opts,'maxVoxPCA', 6000);       % voxel subsample for PCA
opts = setDefault(opts,'maxTPCA', 2500);         % time subsample for PCA

% ------------------ dims ------------------
nd = ndims(I);
if nd == 3
    [ny,nx,T] = size(I);
    nz = 1;
elseif nd == 4
    [ny,nx,nz,T] = size(I);
else
    error('Unsupported dimensionality. I must be 3D or 4D.');
end

fprintf('[QC] Data size: %d x %d x %d x %d  (TR=%.4g s)  dataset=%s\n', ny,nx,nz,T,TR,opts.datasetTag);

% ------------------ output dirs (NEW structure) ------------------
qcBase = fullfile(exportPath,'QC', datasetTagSafe);
if opts.useTimestampSubfolder
    qcBase = fullfile(qcBase, datestr(now,'yyyymmdd_HHMMSS'));
end
pngDir = fullfile(qcBase,'png');
matDir = fullfile(qcBase,'mat');
ensureDir(pngDir);
ensureDir(matDir);

% ============================================================
% 0) Compute mean/std ONLY if needed
% ============================================================
needMeanStd = (opts.spatial || opts.motion || opts.burst || opts.cnr || opts.commonmode);
meanImg = [];
stdImg  = [];

if needMeanStd
    fprintf('[QC] Computing mean/std (streaming)...\n');
    [meanImg, stdImg] = meanStdOverTime_streaming(I, nd, ny,nx,nz,T);
end

% Brain mask
if needMeanStd
    brainMask = makeBrainMask(meanImg);
else
    brainMask = true(ny,nx,nz);
end

% ============================================================
% 1) Burst error QC
% ============================================================
burst = struct('has',false);
noisyVoxelMask = false(ny,nx,nz);
maskUse = brainMask;

if opts.burst
    fprintf('[QC] Burst error QC...\n');

    baselineVol = meanImg;
    baselineVol(~isfinite(baselineVol)) = 0;

    maxVol = maxOverTime_streaming(I, nd, ny,nx,nz,T);

    burstRatio = maxVol ./ (baselineVol + 1e-12);
    burstRatio(~brainMask) = 0;

    noisyVoxelMask = (burstRatio >= opts.THbursterror) & brainMask;
    noisyFrac = nnz(noisyVoxelMask) / max(1, nnz(brainMask));

    % Exclude noisy voxels for subsequent metrics
    maskUse = brainMask & ~noisyVoxelMask;
    if nnz(maskUse) < 50
        maskUse = brainMask; % fallback
    end

    % Coverage over time
    thrVol = opts.THbursterror * baselineVol;
    nV = max(1, nnz(brainMask));
    burstCoverage = zeros(1,T);
    for tt = 1:T
        fr = getFrame(I, nd, tt);
        hit = (fr >= thrVol) & brainMask;
        burstCoverage(tt) = nnz(hit) / nV;
    end

    % Plot: ratio map + noisy mask + histogram
    fig = figure('Color','w','Position',[120 120 1200 480]);
    subplot(1,3,1);
    imagesc(clipForDisplay(reduceTo2D(burstRatio), 1, 99)); axis image off; colormap gray;
    title(sprintf('BurstRatio=max/baseline (clipped)  TH=%.2f', opts.THbursterror));

    subplot(1,3,2);
    imagesc(reduceTo2D(noisyVoxelMask)); axis image off; colormap gray;
    title(sprintf('Noisy voxels (%.2f%% of brain)', 100*noisyFrac));

    subplot(1,3,3);
    v = burstRatio(brainMask); v = v(isfinite(v));
    histogram(double(v), 90); grid on;
    xlabel('BurstRatio'); ylabel('Count');
    title('BurstRatio histogram (brain)');

    saveas(fig, fullfile(pngDir,'QC_burst_ratio.png'));
    close(fig);

    % Plot: coverage timecourse
    fig = figure('Color','w','Position',[140 140 1100 380]);
    plot(burstCoverage,'k','LineWidth',1.1); grid on; hold on;
plot([1 T], [opts.THnoisyvoxels opts.THnoisyvoxels], 'r', 'LineWidth', 2);
    xlabel('Volume');
    ylabel('Burst coverage (fraction of brain voxels)');
    title('Burst coverage over time (fraction voxels > THbursterror*baseline)');
    saveas(fig, fullfile(pngDir,'QC_burst_coverage.png'));
    close(fig);

    burst.has = true;
    burst.noisyFrac = noisyFrac;
    burst.burstCoverage = burstCoverage;

    try
        save(fullfile(matDir,'qc_burst.mat'), ...
            'baselineVol','maxVol','burstRatio','noisyVoxelMask','noisyFrac','burstCoverage','-v7.3');
    catch
    end
end

maskInd = find(maskUse(:));

% ============================================================
% 2) Global mean (masked, streaming)
% ============================================================
g = maskedGlobalMean_streaming(I, nd, maskInd, T);
t = (0:T-1) * TR;

% ============================================================
% 3) Frequency QC
% ============================================================
if opts.frequency
    fprintf('[QC] Frequency QC...\n');
    g0 = detrendSafe(double(g(:)));
    [f, Pxx] = psdSafe(g0, TR);

    fig = figure('Color','w','Position',[120 120 900 420]);
    plotPSD(f, Pxx, [0 2], 'Frequency QC (0–2 Hz)');
    saveas(fig, fullfile(pngDir,'QC_frequency.png'));
    close(fig);

    fig = figure('Color','w','Position',[140 140 900 420]);
    plotPSD(f, Pxx, [0 0.1], 'Frequency QC (0–0.1 Hz)');
    saveas(fig, fullfile(pngDir,'QC_frequency_0p1Hz.png'));
    close(fig);
end

% ============================================================
% 4) Spatial QC (mean image, CV, tSNR map+hist)
% ============================================================
global_tSNR = NaN; acceptSNR = true;
if opts.spatial
    fprintf('[QC] Spatial QC...\n');

    if isempty(meanImg) || isempty(stdImg)
        [meanImg, stdImg] = meanStdOverTime_streaming(I, nd, ny,nx,nz,T);
    end

    cvImg = stdImg ./ (meanImg + eps);
    cvImg(~maskUse) = 0;

    % Baseline frames for noise estimate (meta-aware)
    [baseIdx, stimIdx] = getBaselineStimFrames(meta, TR, T, opts.baselineSec);
    if isempty(baseIdx)
        baseIdx = 1:min(T, max(10, round(opts.baselineSec/TR)));
    end
    if isempty(stimIdx)
        sigIdx = 1:T;
    else
        sigIdx = stimIdx;
    end

    baseStd = stdOverFrames_streaming(I, nd, baseIdx, ny,nx,nz,T);
    sigMean = meanOverFrames_streaming(I, nd, sigIdx, ny,nx,nz,T);

    baseStd(~maskUse) = 0;
    sigMean(~maskUse) = 0;

    tsnr = sigMean ./ (baseStd + eps);
    tsnr(~maskUse) = 0;

    vals = tsnr(maskInd); vals = vals(isfinite(vals));
    if isempty(vals), vals = tsnr(:); vals = vals(isfinite(vals)); end

    if ~isempty(vals)
        lo = prctile(vals,2); hi = prctile(vals,98);
        vals2 = vals(vals>=lo & vals<=hi);
        global_tSNR = mean(double(vals2));
    end
    acceptSNR = (global_tSNR >= opts.THSNR);

    fig = figure('Color','w','Position',[120 120 1200 820]);

    subplot(2,2,1);
    imagesc(clipForDisplay(reduceTo2D(meanImg), 2, 99.5)); axis image off; colormap gray;
    title('Mean image (clipped)');

    subplot(2,2,2);
    imagesc(clipForDisplay(reduceTo2D(cvImg), 2, 99.5)); axis image off; colormap gray;
    title('Temporal CV = std/mean (clipped)');

    subplot(2,2,3);
    imagesc(clipForDisplay(reduceTo2D(tsnr), 2, 99.5)); axis image off; colormap gray;
    title(sprintf('tSNR map (baseline-noise)  global=%.1f', global_tSNR));

    subplot(2,2,4);
    histogram(double(vals), 90); grid on;
    xlabel('tSNR'); ylabel('Count');
    title(sprintf('tSNR histogram (masked)  THSNR=%.1f  ACCEPT=%d', opts.THSNR, acceptSNR));

    saveas(fig, fullfile(pngDir,'QC_spatial_tSNR.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_spatial_maps.mat'), ...
            'meanImg','stdImg','cvImg','tsnr','global_tSNR','acceptSNR','baseIdx','sigIdx','-v7.3');
    catch
    end
end

% ============================================================
% 5) Temporal QC (GS/rGS/DVARS/spikes)
% ============================================================
if opts.temporal
    fprintf('[QC] Temporal QC...\n');

    d10 = prctile(double(g),10);
    rGS = 100*(double(g)-d10)/(d10+eps);

    DVARS = computeDVARS_streaming(I, nd, maskInd, T);
    tDiff = t(2:end);

    dg = diff(double(g));
    spikeThr = 3*std(dg);
    spikes = abs(dg) > spikeThr;

    fig = figure('Color','w','Position',[120 120 1100 820]);

    subplot(4,1,1);
    plot(t,double(g),'k','LineWidth',1.0);
    title('Masked global mean'); xlabel('Time (s)'); grid on;

    subplot(4,1,2);
    plot(t,double(rGS),'b','LineWidth',1.0);
    title('Relative global signal (rGS)'); xlabel('Time (s)'); grid on;

    subplot(4,1,3);
    plot(tDiff,double(DVARS),'r','LineWidth',1.0);
    title('Masked DVARS'); xlabel('Time (s)'); grid on;

    subplot(4,1,4);
    plot(tDiff,dg,'k','LineWidth',0.9); hold on;
    plot(tDiff(spikes),dg(spikes),'ro','MarkerFaceColor','r','MarkerSize',4);
    title('Frame-to-frame global change (spikes marked)'); xlabel('Time (s)'); grid on;

    saveas(fig, fullfile(pngDir,'QC_temporal.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_temporal_values.mat'),'g','rGS','DVARS','spikes','spikeThr','-v7.3');
    catch
    end
end

% ============================================================
% 6) Stability QC (Urban/Montaldo-style intensity stability)
% ============================================================
if opts.stability
    fprintf('[QC] Stability QC...\n');

    gNorm = double(g) ./ (median(double(g)) + 1e-12);

    lowerVals = gNorm(gNorm <= 1);
    if numel(lowerVals) > 10
        sigma = 1.4826 * median(abs(lowerVals - 1));
    else
        sigma = 1.4826 * median(abs(gNorm - 1));
    end
    sigma = max(sigma, 0.02);

    thrU = 1 + 3*sigma;
    thrL = 1 - 3*sigma;

    rejected = (gNorm > thrU) | (gNorm < thrL);
    rejPercent = 100 * sum(rejected) / numel(rejected);

    if rejPercent < 10
        interpretation = 'Stable acquisition';
    elseif rejPercent < 30
        interpretation = 'Moderate instability';
    else
        interpretation = 'Strong instability';
    end

    fig = figure('Color','w','Position',[200 200 1100 650]);

    subplot(2,1,1);
    stem(1:numel(rejected), double(rejected), 'LineWidth',1.2, 'Marker','o', 'MarkerSize',3);
    ylim([-0.1 1.1]); yticks([0 1]); yticklabels({'Accepted','Rejected'});
    xlabel('Volume'); title('Rejected volumes over time'); grid on;

    subplot(2,1,2);
    plot(gNorm,'k','LineWidth',1.2); hold on;
    xl = xlim;
    plot(xl,[thrU thrU],'r','LineWidth',2);
    plot(xl,[thrL thrL],'r','LineWidth',2);
    xlim(xl);
    xlabel('Volume'); ylabel('Normalized global intensity');
    title('Global signal stability'); grid on;

    txt = sprintf(['Threshold: [%.3f , %.3f]\n' ...
                   'Rejected volumes: %.2f%%\n' ...
                   'Interpretation: %s'], thrL, thrU, rejPercent, interpretation);

    annotation('textbox',[0.63 0.18 0.32 0.22], ...
        'String',txt,'FitBoxToText','on', ...
        'BackgroundColor',[1 1 1],'EdgeColor',[0 0 0]);

    saveas(fig, fullfile(pngDir,'QC_stability_trace.png'));
    close(fig);

    fig = figure('Color','w','Position',[240 240 900 420]);
    histogram(gNorm, 90); hold on; grid on;
    yl = ylim;
    plot([thrU thrU], yl,'r','LineWidth',2);
    plot([thrL thrL], yl,'r','LineWidth',2);
    title(sprintf('Stability histogram (Rejected %.2f%%)', rejPercent));
    xlabel('Normalized global intensity'); ylabel('Count');
    saveas(fig, fullfile(pngDir,'QC_stability_hist.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_stability.mat'), ...
            'sigma','thrU','thrL','rejPercent','rejected','-v7.3');
    catch
    end
end

% ============================================================
% 7) Motion QC (COM drift)
% ============================================================
if opts.motion
    fprintf('[QC] Motion QC (COM drift)...\n');

    if isempty(meanImg)
        [meanImg, ~] = meanStdOverTime_streaming(I, nd, ny,nx,nz,T);
    end

    [dx,dy,dz] = computeCOMDrift_streaming(I, nd, meanImg, ny,nx,nz,T);

    fig = figure('Color','w','Position',[120 120 1000 720]);
    subplot(3,1,1); plot(dx,'k'); title('\Deltax (COM drift)'); xlabel('Volume'); grid on;
    subplot(3,1,2); plot(dy,'k'); title('\Deltay (COM drift)'); xlabel('Volume'); grid on;
    subplot(3,1,3); plot(dz,'k'); title('\Deltaz (COM drift)'); xlabel('Volume'); grid on;
    saveas(fig, fullfile(pngDir,'QC_motion_COM.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_motion_COM.mat'),'dx','dy','dz','-v7.3');
    catch
    end
end

% ============================================================
% 8) CNR QC
% ============================================================
globalCNR = NaN; acceptCNR = true;

if opts.cnr
    fprintf('[QC] CNR QC...\n');

    [baseIdx, stimIdx] = getBaselineStimFrames(meta, TR, T, opts.baselineSec);

    label = 'CNR (true)';
    if isempty(baseIdx) || isempty(stimIdx)
        [baseIdx, stimIdx] = pseudoStimBaselineFromGlobal(g);
        label = 'CNR (PSEUDO: high-vs-low global frames)';
    end

    IbaseMean = meanOverFrames_streaming(I, nd, baseIdx, ny,nx,nz,T);
    IbaseStd  = stdOverFrames_streaming(I, nd, baseIdx, ny,nx,nz,T);
    IstimMean = meanOverFrames_streaming(I, nd, stimIdx, ny,nx,nz,T);

    CNRv = (IstimMean - IbaseMean) ./ (IbaseStd + eps);
    CNRv(~maskUse) = 0;

    vals = CNRv(maskInd); vals = vals(isfinite(vals));
    if isempty(vals), vals = CNRv(:); vals = vals(isfinite(vals)); end

    p = max(0.001, min(0.50, double(opts.PCNR)));
    thrP = prctile(double(vals), 100*(1-p));
    topVals = double(vals(vals >= thrP));
    globalCNR = mean(topVals);
    acceptCNR = (globalCNR >= opts.THCNR);

    fig = figure('Color','w','Position',[120 120 1200 520]);

    subplot(1,3,1);
    imagesc(clipForDisplay(reduceTo2D(CNRv), 2, 99.5)); axis image off; colormap gray;
    title(sprintf('%s\nCNR map (clipped)', label));

    subplot(1,3,2);
    histogram(double(vals), 90); grid on; hold on;
yl = ylim;
plot([thrP thrP], yl, 'r', 'LineWidth', 2);

    xlabel('CNRv'); ylabel('Count');
    title(sprintf('CNR histogram (masked)  top %.1f%% thr', 100*p));

    subplot(1,3,3);
    text(0.05,0.85,sprintf('global CNR (top %.1f%%) = %.3f\nTHCNR = %.3f\nACCEPT = %d', ...
        100*p, globalCNR, opts.THCNR, acceptCNR), 'FontSize',13,'FontWeight','bold');
    axis off;

    saveas(fig, fullfile(pngDir,'QC_CNR.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_cnr.mat'), ...
            'CNRv','globalCNR','acceptCNR','baseIdx','stimIdx','thrP','label','-v7.3');
    catch
    end
end

% ============================================================
% 9) Common Mode QC (block correlation)
% ============================================================
cmPortion = NaN; acceptCM = true;

if opts.commonmode
    fprintf('[QC] Common mode QC...\n');

    [cmPortion, cmInfo] = commonMode_blockCorr(I, nd, maskUse, opts.Nblock, opts.THCM, opts.maxTCorrFrames, ny,nx,nz,T);
    acceptCM = (cmPortion < opts.THpor);

    fig = figure('Color','w','Position',[120 120 1200 520]);

    subplot(1,3,1);
    histogram(cmInfo.corrVals, 80); grid on; hold on;
yl = ylim;
plot([opts.THCM opts.THCM], yl, 'r', 'LineWidth', 2);

    xlabel('Block-block correlation'); ylabel('Count');
    title('Common-mode correlation histogram');

    subplot(1,3,2);
    imagesc(cmInfo.corrMatPreview); axis image; colormap gray; colorbar;
    title('Correlation matrix preview (subset)');

    subplot(1,3,3);
    text(0.05,0.85,sprintf('THCM = %.2f\nPortion >= THCM = %.3f\nTHpor = %.3f\nACCEPT = %d\nBlocks used = %d\nFrames used = %d', ...
        opts.THCM, cmPortion, opts.THpor, acceptCM, cmInfo.nBlocksUsed, cmInfo.nFramesUsed), ...
        'FontSize',13,'FontWeight','bold');
    axis off;

    saveas(fig, fullfile(pngDir,'QC_common_mode.png'));
    close(fig);

    try
        save(fullfile(matDir,'qc_common_mode.mat'),'cmPortion','acceptCM','cmInfo','-v7.3');
    catch
    end
end

% ============================================================
% 10) Integrated acceptance summary
% ============================================================
acceptBurst = true;
if opts.burst && burst.has
    acceptBurst = (burst.noisyFrac < opts.THnoisyvoxels);
end
if ~opts.spatial,     acceptSNR = true; end
if ~opts.cnr,         acceptCNR = true; end
if ~opts.commonmode,  acceptCM  = true; end

acceptAll = acceptBurst && acceptSNR && acceptCNR && acceptCM;

fig = figure('Color','w','Position',[180 180 950 420]);
axis off;
title('QC summary (trial-level acceptance)','FontWeight','bold','FontSize',14);

txt = {};
txt{end+1} = sprintf('Burst:      ACCEPT=%d   (noisyFrac=%.3f, THnoisy=%.3f, THburst=%.2f)', ...
    acceptBurst, ternary(opts.burst && burst.has, burst.noisyFrac, NaN), opts.THnoisyvoxels, opts.THbursterror);
txt{end+1} = sprintf('tSNR:       ACCEPT=%d   (global_tSNR=%.2f, THSNR=%.2f)', ...
    acceptSNR, ternary(isfinite(global_tSNR), global_tSNR, NaN), opts.THSNR);
txt{end+1} = sprintf('CNR:        ACCEPT=%d   (globalCNR=%.3f, THCNR=%.3f, PCNR=%.1f%%)', ...
    acceptCNR, ternary(isfinite(globalCNR), globalCNR, NaN), opts.THCNR, 100*opts.PCNR);
txt{end+1} = sprintf('CommonMode: ACCEPT=%d   (portion=%.3f, THCM=%.2f, THpor=%.3f)', ...
    acceptCM, ternary(isfinite(cmPortion), cmPortion, NaN), opts.THCM, opts.THpor);
txt{end+1} = ' ';
txt{end+1} = sprintf('FINAL ACCEPT (all criteria) = %d', acceptAll);

text(0.02,0.85,txt,'FontSize',12,'FontName','Courier New','VerticalAlignment','top');
saveas(fig, fullfile(pngDir,'QC_summary.png'));
close(fig);

try
    save(fullfile(matDir,'qc_summary.mat'), ...
        'acceptBurst','acceptSNR','acceptCNR','acceptCM','acceptAll', ...
        'global_tSNR','globalCNR','cmPortion','-v7.3');
catch
end

% ============================================================
% 11) PCA QC (AUTO CLOSE; no CloseRequestFcn)
% ============================================================
if opts.pca
    fprintf('[QC] PCA QC...\n');

    % Subsample voxels
    ind = maskInd;
    if numel(ind) > opts.maxVoxPCA
        step = floor(numel(ind)/opts.maxVoxPCA);
        ind = ind(1:step:end);
        ind = ind(1:min(opts.maxVoxPCA, numel(ind)));
    end

    % Subsample time
    if T > opts.maxTPCA
        stepT = ceil(T/opts.maxTPCA);
        tIdx = 1:stepT:T;
    else
        tIdx = 1:T;
    end
    Tp = numel(tIdx);

    X = zeros(Tp, numel(ind), 'single');
    for k = 1:Tp
        fr = getFrame(I, nd, tIdx(k));
        v = single(fr(ind));
        v(~isfinite(v)) = 0;
        X(k,:) = v;
    end

    X = bsxfun(@minus, X, mean(X,1));

    nComp = min([25, Tp, 250]);

    try
        [~, score, ~, ~, explained] = pca(double(X), 'NumComponents', nComp, 'Algorithm','svd');
    catch ME
        warning('[QC] PCA failed: %s', ME.message);
        explained = [];
        score = [];
        nComp = 0;
    end

    if nComp > 0
        figVar = figure('Color','w','Position',[100 100 650 420]);
        plot(1:nComp, explained(1:nComp), 'ko-','LineWidth',1.2,'MarkerFaceColor','k');
        xlim([1 nComp]); xlabel('Component'); ylabel('Explained Variance (%)');
        title('PCA Explained Variance'); grid on;
        saveas(figVar, fullfile(pngDir,'QC_pca_variance.png'));
        close(figVar);

        figGrid = figure('Color','w','Position',[100 100 1200 800]);
        for i = 1:nComp
            subplot(5,5,i);
            tc = score(:,i);
            tc = (tc-mean(tc)) / (std(tc)+1e-6);
            plot(tc,'k','LineWidth',0.7);
            title(sprintf('PC%d (%.1f%%)',i,explained(i)));
            axis tight; set(gca,'XTick',[],'YTick',[]);
        end
        annotation(figGrid,'textbox',[0 0.95 1 0.04],...
            'String','First PCA Components (auto-saved + auto-closed)',...
            'EdgeColor','none','HorizontalAlignment','center',...
            'FontWeight','bold','FontSize',12);

        saveas(figGrid, fullfile(pngDir,'QC_pca_components_grid.png'));
        close(figGrid);

        try
            save(fullfile(matDir,'qc_pca.mat'), 'explained','score','nComp','ind','tIdx','-v7.3');
        catch
        end
    end
end

fprintf('[QC] Done. PNGs saved to: %s\n', pngDir);

% ============================= HELPERS =============================

function opts = setFlagDefault(opts, field, val)
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = val;
    end
end

function opts = setDefault(opts, field, val)
    if ~isfield(opts, field) || isempty(opts.(field))
        opts.(field) = val;
    end
end

function y = ternary(cond, a, b)
    if cond, y = a; else, y = b; end
end

function ensureDir(p)
    if ~exist(p,'dir')
        mkdir(p);
    end
end

function tag = sanitizeTag(s)
    s = char(s);
    s = regexprep(s, '[^A-Za-z0-9_\-]', '_');
    s = regexprep(s, '_+', '_');
    s = regexprep(s, '^_','');
    s = regexprep(s, '_$','');
    if isempty(s), s = 'dataset'; end
    tag = s;
end

function fr = getFrame(Iin, ndIn, tt)
    if ndIn == 3
        fr = double(Iin(:,:,tt));
        fr = reshape(fr, [size(fr,1) size(fr,2) 1]);
    else
        fr = double(Iin(:,:,:,tt));
    end
    fr(~isfinite(fr)) = 0;
end

function [m, s] = meanStdOverTime_streaming(Iin, ndIn, ny,nx,nz,Tin)
    m = zeros(ny,nx,nz);
    M2 = zeros(ny,nx,nz);
    for tt = 1:Tin
        x = getFrame(Iin, ndIn, tt);
        if tt == 1
            m = x;
            M2(:) = 0;
        else
            d  = x - m;
            m  = m + d/tt;
            d2 = x - m;
            M2 = M2 + d.*d2;
        end
    end
    if Tin > 1
        v = M2/(Tin-1);
    else
        v = zeros(size(M2));
    end
    s = sqrt(max(v,0));
end

function mx = maxOverTime_streaming(Iin, ndIn, ny,nx,nz,Tin)
    mx = -inf(ny,nx,nz);
    for tt = 1:Tin
        x = getFrame(Iin, ndIn, tt);
        mx = max(mx, x);
    end
    mx(~isfinite(mx)) = 0;
end

function mask = makeBrainMask(meanVol)
    A = double(meanVol);
    A(~isfinite(A)) = 0;
    v = A(:);
    p1 = prctile(v, 1);
    p99 = prctile(v, 99);
    A = min(max(A,p1),p99);
    thr = prctile(A(:), 70);
    mask = A > thr;
    if nnz(mask) < 50
        mask = true(size(meanVol));
    end
end

function gOut = maskedGlobalMean_streaming(Iin, ndIn, maskInd, Tin)
    gOut = zeros(1,Tin);
    for tt=1:Tin
        fr = getFrame(Iin, ndIn, tt);
        v = fr(maskInd);
        gOut(tt) = mean(v);
    end
end

function DV = computeDVARS_streaming(Iin, ndIn, maskInd, Tin)
    if Tin < 2
        DV = [];
        return;
    end
    DV = zeros(1, Tin-1);
    prev = getFrame(Iin, ndIn, 1);
    prevV = prev(maskInd);
    for tt=2:Tin
        cur = getFrame(Iin, ndIn, tt);
        curV = cur(maskInd);
        d = double(curV) - double(prevV);
        DV(tt-1) = sqrt(mean(d.^2));
        prevV = curV;
    end
end

function V2 = reduceTo2D(V)
    V = double(V);
    while ndims(V) > 2
        V = mean(V, ndims(V));
    end
    V2 = V;
end

function X = clipForDisplay(X, pLow, pHigh)
    v = X(:); v = v(isfinite(v));
    if isempty(v), return; end
    lo = prctile(v, pLow);
    hi = prctile(v, pHigh);
    if hi <= lo, return; end
    X = min(max(X, lo), hi);
end

function y = detrendSafe(x)
    x = double(x(:));
    x(~isfinite(x)) = 0;
    n = numel(x);
    if n < 3, y = x; return; end
    tt = (1:n)';
    A = [ones(n,1) tt];
    b = A \ x;
    y = x - A*b;
end

function [fOut, PxxOut] = psdSafe(x, TRlocal)
    Fs = 1 / TRlocal;
    x = double(x(:)); x(~isfinite(x)) = 0;

    if exist('pwelch','file') == 2
        nfft = max(256, 2^nextpow2(min(numel(x), 8192)));
        win = min(numel(x), 1024);
        if win < 64, win = min(numel(x), 256); end
        if win < 16, win = numel(x); end
        nover = floor(0.5*win);
        [PxxOut, fOut] = pwelch(x, win, nover, nfft, Fs);
        PxxOut = double(PxxOut(:));
        fOut = double(fOut(:));
    else
        N = numel(x);
        nfft = 2^nextpow2(N);
        Xf = fft(x, nfft);
        P2 = (abs(Xf).^2) / (N*Fs);
        P1 = P2(1:floor(nfft/2)+1);
        if numel(P1) > 2, P1(2:end-1) = 2*P1(2:end-1); end
        fOut = (0:floor(nfft/2))' * (Fs/nfft);
        PxxOut = P1(:);
    end
end

function plotPSD(fq, P, xlimHz, ttl)
    fq = double(fq(:)); P = double(P(:));
    keep = fq >= xlimHz(1) & fq <= xlimHz(2);
    fq = fq(keep); P = P(keep);
    semilogy(fq, P, 'k','LineWidth',1.2);
    xlabel('Frequency (Hz)'); ylabel('Power (a.u.)');
    title(ttl); grid on; xlim(xlimHz);
end

function M = meanOverFrames_streaming(Iin, ndIn, frames, ny,nx,nz,Tin)
    frames = unique(frames(:)');
    frames = frames(frames>=1 & frames<=Tin);
    if isempty(frames)
        M = zeros(ny,nx,nz);
        return;
    end
    M = zeros(ny,nx,nz);
    for k=1:numel(frames)
        fr = getFrame(Iin, ndIn, frames(k));
        M = M + fr;
    end
    M = M / numel(frames);
end

function S = stdOverFrames_streaming(Iin, ndIn, frames, ny,nx,nz,Tin)
    frames = unique(frames(:)');
    frames = frames(frames>=1 & frames<=Tin);
    if numel(frames) < 2
        S = zeros(ny,nx,nz);
        return;
    end
    mu = meanOverFrames_streaming(Iin, ndIn, frames, ny,nx,nz,Tin);
    M2 = zeros(ny,nx,nz);
    for k=1:numel(frames)
        fr = getFrame(Iin, ndIn, frames(k));
        d = fr - mu;
        M2 = M2 + d.^2;
    end
    S = sqrt(M2 / max(1,(numel(frames)-1)));
end

function [baseIdx, stimIdx] = getBaselineStimFrames(meta, TRlocal, Tin, baselineSec)
    baseIdx = [];
    stimIdx = [];
    if isempty(meta) || ~isstruct(meta), return; end

    if isfield(meta,'baselineFrames') && ~isempty(meta.baselineFrames)
        baseIdx = unique(meta.baselineFrames(:)');
    end
    if isfield(meta,'stimFrames') && ~isempty(meta.stimFrames)
        stimIdx = unique(meta.stimFrames(:)');
    end
    if isempty(baseIdx) && isfield(meta,'baselineSec') && ~isempty(meta.baselineSec)
        nB = max(1, round(double(meta.baselineSec)/TRlocal));
        baseIdx = 1:min(Tin,nB);
    end
    if isempty(baseIdx)
        nB = max(1, round(double(baselineSec)/TRlocal));
        baseIdx = 1:min(Tin,nB);
    end
    baseIdx = baseIdx(baseIdx>=1 & baseIdx<=Tin);
    stimIdx = stimIdx(stimIdx>=1 & stimIdx<=Tin);
end

function [bIdx, sIdx] = pseudoStimBaselineFromGlobal(g)
    g = double(g(:));
    loThr = prctile(g, 40);
    hiThr = prctile(g, 90);
    bIdx = find(g <= loThr);
    sIdx = find(g >= hiThr);
    if numel(bIdx) < 20, bIdx = 1:max(20, round(0.2*numel(g))); end
    if numel(sIdx) < 10, sIdx = max(1,round(0.9*numel(g))):numel(g); end
end

function [portion, info] = commonMode_blockCorr(Iin, ndIn, maskVol, Nblock, THCM, maxFrames, ny,nx,nz,Tin)
    Nblock = max(2, round(Nblock));
    xe = round(linspace(1, nx+1, Nblock+1));
    ye = round(linspace(1, ny+1, Nblock+1));
    ze = round(linspace(1, nz+1, Nblock+1));

    if Tin > maxFrames
        step = ceil(Tin/maxFrames);
        tidx = 1:step:Tin;
    else
        tidx = 1:Tin;
    end
    nT = numel(tidx);

    tc = [];
    bcount = 0;

    for bz=1:Nblock
        z1 = ze(bz); z2 = ze(bz+1)-1; if z2<z1, continue; end
        for by=1:Nblock
            y1 = ye(by); y2 = ye(by+1)-1; if y2<y1, continue; end
            for bx=1:Nblock
                x1 = xe(bx); x2 = xe(bx+1)-1; if x2<x1, continue; end
                m = maskVol(y1:y2, x1:x2, z1:z2);
                if nnz(m) < 30, continue; end

                bcount = bcount + 1;
                tc(bcount,1:nT) = 0; %#ok<AGROW>
                for k=1:nT
                    fr = getFrame(Iin, ndIn, tidx(k));
                    sub = fr(y1:y2, x1:x2, z1:z2);
                    v = sub(m);
                    tc(bcount,k) = mean(double(v));
                end
            end
        end
    end

    if isempty(tc) || size(tc,1) < 5
        portion = 0;
        info = struct('corrVals',[],'corrMatPreview',[],'nBlocksUsed',size(tc,1),'nFramesUsed',nT);
        return;
    end

    X = double(tc'); % [nT x nBlocks]
    X = detrendColumns(X);

    C = corrcoef(X);
    nB = size(C,1);
    off = C(~eye(nB));
    off = off(isfinite(off));

    portion = sum(off >= THCM) / max(1,numel(off));

    nPrev = min(200, nB);
    info = struct();
    info.corrVals = off;
    info.corrMatPreview = C(1:nPrev,1:nPrev);
    info.nBlocksUsed = nB;
    info.nFramesUsed = nT;
end

function X = detrendColumns(X)
    [Tn,Nn] = size(X);
    tt = (1:Tn)';
    A = [ones(Tn,1) tt];
    for j=1:Nn
        y = X(:,j);
        b = A \ y;
        X(:,j) = y - A*b;
    end
end

function h = xlineCompat(x, varargin)
% MATLAB 2017b replacement for xline(x, ...)
% Supports: xlineCompat(x,'r','LineWidth',2) and name/value pairs.

ax = gca;

% defaults
col = 'k';
lw  = 1.5;
ls  = '-';

% allow first arg color shorthand like 'r'
if ~isempty(varargin) && ischar(varargin{1}) && numel(varargin{1}) <= 2
    col = varargin{1};
    varargin(1) = [];
end

% parse name/value pairs
k = 1;
while k <= numel(varargin)
    if ischar(varargin{k})
        switch lower(varargin{k})
            case 'color'
                col = varargin{k+1};
                k = k + 2;
                continue;
            case 'linewidth'
                lw = varargin{k+1};
                k = k + 2;
                continue;
            case 'linestyle'
                ls = varargin{k+1};
                k = k + 2;
                continue;
        end
    end
    k = k + 1;
end

holdState = ishold(ax);
hold(ax,'on');
yl = get(ax,'YLim');
h = plot(ax, [x x], yl, 'Color', col, 'LineWidth', lw, 'LineStyle', ls);
if ~holdState, hold(ax,'off'); end
end


function h = ylineCompat(y, varargin)
% MATLAB 2017b replacement for yline(y, ...)
% Supports: ylineCompat(y,'r','LineWidth',2) and name/value pairs.

ax = gca;

% defaults
col = 'k';
lw  = 1.5;
ls  = '-';

% allow first arg color shorthand like 'r'
if ~isempty(varargin) && ischar(varargin{1}) && numel(varargin{1}) <= 2
    col = varargin{1};
    varargin(1) = [];
end

% parse name/value pairs
k = 1;
while k <= numel(varargin)
    if ischar(varargin{k})
        switch lower(varargin{k})
            case 'color'
                col = varargin{k+1};
                k = k + 2;
                continue;
            case 'linewidth'
                lw = varargin{k+1};
                k = k + 2;
                continue;
            case 'linestyle'
                ls = varargin{k+1};
                k = k + 2;
                continue;
        end
    end
    k = k + 1;
end

holdState = ishold(ax);
hold(ax,'on');
xl = get(ax,'XLim');
h = plot(ax, xl, [y y], 'Color', col, 'LineWidth', lw, 'LineStyle', ls);
if ~holdState, hold(ax,'off'); end
end

function [dx,dy,dz] = computeCOMDrift_streaming(Iin, ndIn, refMeanVol, ny,nx,nz,Tin)
    [X,Y,Z] = ndgrid(1:ny, 1:nx, 1:nz);
    dx = zeros(1,Tin); dy=zeros(1,Tin); dz=zeros(1,Tin);

    ref = double(refMeanVol);
    refSum = sum(ref(:)) + eps;
    cx0 = sum(X(:).*ref(:))/refSum;
    cy0 = sum(Y(:).*ref(:))/refSum;
    cz0 = sum(Z(:).*ref(:))/refSum;

    for tt=1:Tin
        fr = getFrame(Iin, ndIn, tt);
        s = sum(fr(:)) + eps;
        cx = sum(X(:).*fr(:))/s;
        cy = sum(Y(:).*fr(:))/s;
        cz = sum(Z(:).*fr(:))/s;
        dx(tt)=cx-cx0; dy(tt)=cy-cy0; dz(tt)=cz-cz0;
    end
end

end
