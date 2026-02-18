function qc_fusi(data, meta, exportPath, opts)
% qc_fusi
% ============================================================
% Full MATLAB 2017b compatible QC engine
% ============================================================

if nargin < 4
    error('qc_fusi requires data, meta, exportPath, opts');
end

I  = data.I;
TR = data.TR;

% Ensure flags exist
defaultFlags = {'frequency','spatial','temporal','motion','stability','pca','framerate'};
for i = 1:length(defaultFlags)
    if ~isfield(opts, defaultFlags{i})
        opts.(defaultFlags{i}) = false;
    end
end

nd = ndims(I);

if nd == 3
    [ny,nx,T] = size(I);
    nz = 1;
elseif nd == 4
    [ny,nx,nz,T] = size(I);
else
    error('Unsupported dimensionality.');
end

qcRoot = fullfile(exportPath,'QC');
pngDir = fullfile(qcRoot,'png');
matDir = fullfile(qcRoot,'mat');

if ~exist(qcRoot,'dir'), mkdir(qcRoot); end
if ~exist(pngDir,'dir'), mkdir(pngDir); end
if ~exist(matDir,'dir'), mkdir(matDir); end

%% ============================================================
% GLOBAL MEAN
%% ============================================================

g = globalMean(I);

%% ============================================================
% FREQUENCY QC
%% ============================================================

if opts.frequency

    fprintf('[QC] Frequency QC\n');

    f = (0:floor(T/2)) / (T*TR);
    spec = abs(fft(g));
    spec = spec(1:length(f));

    fig = figure('Color','w');
    plot(f, spec,'LineWidth',1.2);
    xlabel('Frequency (Hz)');
    ylabel('Power');
    title('Frequency QC');
    grid on;

    saveas(fig, fullfile(pngDir,'QC_frequency.png'));
    close(fig);
end

%% ============================================================
% SPATIAL QC + tSNR
%% ============================================================

if opts.spatial

    fprintf('[QC] Spatial QC\n');

    meanImg = meanOverTime(I);
    stdImg  = stdOverTime(I);
    cvImg   = stdImg ./ (meanImg + eps);

    tsnr = meanImg ./ (stdImg + eps);
    tsnrMed = median(tsnr(:));

    fig = figure('Color','w');

    subplot(2,2,1);
    imagesc(reduceTo2D(meanImg)); axis image off;
    title('Mean Image');

    subplot(2,2,2);
    imagesc(reduceTo2D(cvImg)); axis image off;
    title('Temporal CV');

    subplot(2,2,3);
    imagesc(reduceTo2D(tsnr)); axis image off;
    title('tSNR Map');

    subplot(2,2,4);
    histogram(tsnr(:),80);
    title(sprintf('tSNR Histogram (median=%.2f)',tsnrMed));

    colormap gray;

    saveas(fig, fullfile(pngDir,'QC_spatial_tSNR.png'));
    close(fig);
end

%% ============================================================
% TEMPORAL QC
%% ============================================================

if opts.temporal

    fprintf('[QC] Temporal QC\n');

    t = (0:T-1) * TR;
    d10 = prctile(g,10);
    rGS = 100*(g-d10)/(d10+eps);

    DVARS = computeDVARS(I);

    % Spike detection
    dg = [0 diff(g)];
    spikeThr = 3*std(dg);
    spikes = abs(dg) > spikeThr;

    fig = figure('Color','w');

    subplot(4,1,1);
    plot(t,g,'k'); title('Global Mean');

    subplot(4,1,2);
    plot(t,rGS,'b'); title('Relative Global Signal');

    subplot(4,1,3);
    plot(DVARS,'r'); title('DVARS');

    subplot(4,1,4);
    plot(dg,'k'); hold on;
    plot(find(spikes),dg(spikes),'ro');
    title('Frame-to-frame change (Spikes marked)');
    grid on;

    saveas(fig, fullfile(pngDir,'QC_temporal.png'));
    close(fig);
end
%% ============================================================
% FRAME REJECTION + GLOBAL STABILITY QC (Improved Visualization)
%% ============================================================

if opts.stability


    fprintf('[QC] Frame Rejection + Stability QC\n');

    g = globalMean(I);
    gNorm = g ./ (median(g) + 1e-12);

    % Robust sigma estimate (Urban/Montaldo style)
    lowerVals = gNorm(gNorm <= 1);
    if numel(lowerVals) > 10
        sigma = 1.4826 * median(abs(lowerVals - 1));
    else
        sigma = 1.4826 * median(abs(gNorm - 1));
    end

    sigma = max(sigma, 0.02);
    thresholdUpper = 1 + 3*sigma;
    thresholdLower = 1 - 3*sigma;

    rejected = (gNorm > thresholdUpper) | (gNorm < thresholdLower);
    rejPercent = 100 * sum(rejected) / numel(rejected);

    % -------- FIGURE --------
    fig = figure('Color','w','Position',[200 200 1000 600]);

    % ---------------------------------
    % TOP: Rejected volumes over time
    % ---------------------------------
    subplot(2,1,1)

    hold on
    stem(1:length(rejected), rejected, ...
        'LineWidth',1.2, ...
        'Marker','o', ...
        'MarkerFaceColor',[0 0.45 0.75], ...
        'MarkerSize',4);

    ylim([-0.1 1.1]);
    yticks([0 1]);
    yticklabels({'Accepted','Rejected'});
    xlabel('Volume');
    title('Rejected volumes over time');
    grid on

    % ---------------------------------
    % BOTTOM: Global signal stability
    % ---------------------------------
    subplot(2,1,2)
hold on

plot(gNorm,'k','LineWidth',1.2)

% Threshold lines (MATLAB 2017b compatible)
xl = xlim;
plot(xl, [thresholdUpper thresholdUpper], 'r','LineWidth',2)
plot(xl, [thresholdLower thresholdLower], 'r','LineWidth',2)

xlim(xl)


    xlabel('Volume');
    ylabel('Normalized global intensity');
    title('Global signal stability (Urban / Montaldo)');
    grid on

    % Interpretation
    if rejPercent < 10
        interpretation = 'Stable acquisition';
    elseif rejPercent < 30
        interpretation = 'Moderate instability';
    else
        interpretation = 'Strong instability';
    end

    txt = sprintf(['Threshold: [%.3f , %.3f]\n' ...
                   'Rejected volumes: %.2f%%\n' ...
                   'Interpretation: %s'], ...
                   thresholdLower, thresholdUpper, ...
                   rejPercent, interpretation);

    annotation('textbox',[0.62 0.25 0.3 0.18], ...
        'String',txt, ...
        'FitBoxToText','on', ...
        'BackgroundColor',[1 1 1], ...
        'EdgeColor',[0 0 0]);

    saveas(fig, fullfile(pngDir,'frame_rejection_stability_qc.png'));
    close(fig);

    % Save values
    save(fullfile(matDir,'frame_rejection_values.mat'), ...
        'sigma','thresholdUpper','thresholdLower','rejPercent');

end


%% ============================================================
% MOTION QC
%% ============================================================

if opts.motion

    fprintf('[QC] Motion QC\n');

    [dx,dy,dz] = computeCOMDrift(I);

    fig = figure('Color','w');

    subplot(3,1,1); plot(dx); title('?x');
    subplot(3,1,2); plot(dy); title('?y');
    subplot(3,1,3); plot(dz); title('?z');
    xlabel('Volume');

    saveas(fig, fullfile(pngDir,'QC_motion.png'));
    close(fig);
end

%% ============================================================
% STABILITY QC
%% ============================================================

if opts.stability

    fprintf('[QC] Stability QC\n');

    s = planeMeanOverTime(I);
    baseline = median(s(:));
    sNorm = s/(baseline+eps);

    sigma = 1.4826*median(abs(sNorm(:)-1));
    sigma = max(sigma,0.02);
    threshold = 1 + 3*sigma;

    outliers = sNorm > threshold;
    rejPercent = 100*sum(outliers(:))/numel(outliers);

    fig = figure('Color','w');
    histogram(sNorm(:),80); hold on;
    yl = ylim;
    plot([threshold threshold], yl,'r','LineWidth',2);
    title(sprintf('Stability QC (Rejection %.2f%%)',rejPercent));

    saveas(fig, fullfile(pngDir,'QC_stability.png'));
    close(fig);

    save(fullfile(matDir,'stability_values.mat'),...
        'sigma','threshold','rejPercent');
end


%% ============================================================
% PCA QC (First 25 components grid + variance)
%% ============================================================
if isfield(opts,'pca') && opts.pca

    fprintf('[QC] PCA QC\n');

    % --------------------------------------------------------
    % Reshape data ? [voxels x time]
    % --------------------------------------------------------
    if ndims(I)==3
        [ny,nx,T] = size(I);
        flat = reshape(I, ny*nx, T);
    else
        [ny,nx,nz,T] = size(I);
        flat = reshape(I, ny*nx*nz, T);
    end

    % Remove voxel mean (important)
    flat = bsxfun(@minus, flat, mean(flat,2));

    % --------------------------------------------------------
    % Run PCA
    % --------------------------------------------------------
    nComp = min([25, T, 250]); % safety cap
    [coeff,score,~,~,explained] = pca(flat','NumComponents',nComp,'Algorithm','svd');


    % score = timecourses
    C = score;

    % --------------------------------------------------------
    % 1) Variance Plot
    % --------------------------------------------------------
    figVar = figure('Color','w','Position',[100 100 600 400]);

    plot(1:nComp, explained(1:nComp), 'ko-','LineWidth',1.2,'MarkerFaceColor','k');
xlim([1 nComp])

    xlabel('Component');
    ylabel('Explained Variance (%)');
    title('PCA Explained Variance');
    grid on;

    saveas(figVar, fullfile(pngDir,'pca_variance.png'));
    close(figVar);

    % --------------------------------------------------------
    % 2) Component Grid (First 25)
    % --------------------------------------------------------
    figGrid = figure('Color','w','Position',[100 100 1200 800]);

    for i = 1:nComp
        subplot(5,5,i)
        t = C(:,i);

        % z-score normalize for visualization
        t = (t-mean(t)) / (std(t)+1e-6);

        plot(t,'k','LineWidth',0.7)
        title(sprintf('PC%d (%.1f%%)',i,explained(i)))
        axis tight
        set(gca,'XTick',[],'YTick',[])
    end

    % MATLAB 2017b compatible title
    annotation(figGrid,'textbox',[0 0.95 1 0.04],...
        'String','First 25 PCA Components',...
        'EdgeColor','none',...
        'HorizontalAlignment','center',...
        'FontWeight','bold',...
        'FontSize',12);

    % --------------------------------------------------------
    % AUTO-SAVE EVEN IF USER CLOSES WINDOW
    % --------------------------------------------------------
   set(figGrid,'CloseRequestFcn',@(src,ev) closePCA(src, pngDir));

   
    % Also save immediately (in case no manual close)
    saveas(figGrid, fullfile(pngDir,'pca_components_grid.png'));

    % --------------------------------------------------------
    % Save PCA numerical data
    % --------------------------------------------------------
    save(fullfile(matDir,'pca_qc_data.mat'),...
        'explained','coeff','C','nComp');

end



%% ============================================================
% HELPERS
%% ============================================================
function closePCA(hFig, pngDir)
    try
        saveas(hFig, fullfile(pngDir,'pca_components_grid.png'));
    catch
    end
    delete(hFig);   % IMPORTANT
end

function closeAndSave(hFig, pngDir)
    try
        saveas(hFig, fullfile(pngDir,'pca_components_grid.png'));
    catch
    end
    delete(hFig);
end

function g = globalMean(I)
    T = size(I,ndims(I));
    tmp = reshape(I,[],T);
    g = mean(tmp,1);
end

function img = meanOverTime(I)
    img = mean(I,ndims(I));
end

function img = stdOverTime(I)
    img = std(I,0,ndims(I));
end

function DV = computeDVARS(I)
    dI = diff(I,1,ndims(I));
    T = size(dI,ndims(dI));
    tmp = reshape(dI,[],T);
    DV = sqrt(mean(tmp.^2,1));
end

function [dx,dy,dz] = computeCOMDrift(I)

    dims = size(I);
    T = dims(end);

    if ndims(I)==3
        [ny,nx,~] = size(I);
        nz = 1;
    else
        [ny,nx,nz,~] = size(I);
    end

    [X,Y,Z] = ndgrid(1:ny,1:nx,1:nz);

    dx=zeros(1,T); dy=zeros(1,T); dz=zeros(1,T);

    ref = meanOverTime(I);
    refSum = sum(ref(:))+eps;

    cx0 = sum(X(:).*ref(:))/refSum;
    cy0 = sum(Y(:).*ref(:))/refSum;
    cz0 = sum(Z(:).*ref(:))/refSum;

    for t=1:T
        if ndims(I)==3
            frame = I(:,:,t);
        else
            frame = I(:,:,:,t);
        end

        s = sum(frame(:))+eps;

        cx = sum(X(:).*frame(:))/s;
        cy = sum(Y(:).*frame(:))/s;
        cz = sum(Z(:).*frame(:))/s;

        dx(t)=cx-cx0;
        dy(t)=cy-cy0;
        dz(t)=cz-cz0;
    end
end

function s = planeMeanOverTime(I)
    if ndims(I)==3
        s = squeeze(mean(mean(I,1),2));
    else
        s = squeeze(mean(mean(I,1),2));
    end
end

function I2 = reduceTo2D(V)
    while ndims(V)>2
        V = mean(V,ndims(V));
    end
    I2 = V;
end
end