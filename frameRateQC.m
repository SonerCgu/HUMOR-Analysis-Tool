function QC = frameRateQC(I, TR, tag, savePNG)
% frameRateQC
% Single-window diagnostic frame-rate / rejected-volume QC.
% Shows ONE combined QC figure per run:
%   left  = intensity distribution
%   right = rejected volumes over time

if nargin < 3 || isempty(tag), tag = 'ORIGINAL'; end
if nargin < 4, savePNG = false; end %#ok<NASGU>
if nargin < 2 || isempty(TR) || ~isfinite(TR) || TR <= 0, TR = 1; end

D = double(I);
nd = ndims(D);
nVols = size(D, nd);
D = reshape(D, [], nVols);

g = nan(nVols,1);
for ii = 1:nVols
    v = D(:,ii);
    v = v(isfinite(v));
    if isempty(v)
        g(ii) = NaN;
    else
        g(ii) = mean(v);
    end
end

good = isfinite(g);
if ~any(good)
    g(:) = 1;
    good = true(size(g));
end

medg = median(g(good));
if ~isfinite(medg) || medg == 0
    medg = mean(g(good)) + eps;
end

gNorm = g ./ (medg + eps);
gNorm(~isfinite(gNorm)) = 1;

gLow = gNorm(gNorm < 1 & isfinite(gNorm));
if isempty(gLow), gLow = gNorm(isfinite(gNorm)); end

sigma = sqrt(mean((gLow - 1).^2));
if ~isfinite(sigma) || sigma <= 0, sigma = std(gNorm); end
if ~isfinite(sigma) || sigma <= 0, sigma = 0.02; end

k = 3;
thresholdHigh = 1 + k*sigma;
thresholdLow  = 1 - k*sigma;
outliers = (gNorm > thresholdHigh) | (gNorm < thresholdLow);
outliers = outliers(:);
rejPct = 100 * mean(outliers);

fig = figure('Name', ['Frame-rate QC PNG preview - ' tag], ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'InvertHardcopy', 'off', ...
    'Position', [80 80 1500 720], ...
    'Resize', 'on');
set(fig, 'PaperPositionMode', 'auto');

annotation(fig, 'textbox', [0.02 0.93 0.96 0.055], ...
    'String', ['Frame-rate QC - ' tag '   |   Combined intensity + rejected-volume view'], ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'Color', 'k', ...
    'FontSize', 17, ...
    'FontWeight', 'bold');

%% Left panel: Intensity distribution
ax1 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.07 0.16 0.40 0.70]);
hold(ax1, 'on');

nbins = 100;
minG = min(gNorm);
maxG = max(gNorm);
if ~isfinite(minG) || ~isfinite(maxG) || minG == maxG
    minG = 0.98;
    maxG = 1.02;
end

edges = linspace(minG, maxG, nbins+1);
[counts, edges] = histcounts(gNorm, edges);
centers = edges(1:end-1) + diff(edges)/2;

bar(ax1, centers, counts, 'FaceColor', [0.70 0.70 0.70], 'EdgeColor', 'none');

if numel(centers) > 1
    x = linspace(minG, maxG, 500);
    gauss = exp(-0.5*((x-1)/sigma).^2);
    binW = centers(2)-centers(1);
    gauss = gauss * sum(counts) * binW / (sigma*sqrt(2*pi));
    plot(ax1, x, gauss, 'k', 'LineWidth', 2.2);
end

yl = ylim(ax1);
plot(ax1, [thresholdHigh thresholdHigh], yl, 'r', 'LineWidth', 2.2);
plot(ax1, [thresholdLow thresholdLow], yl, 'r', 'LineWidth', 2.2);

xlabel(ax1, 'Normalized global intensity', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 13);
ylabel(ax1, 'Number of volumes', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 13);
title(ax1, ['Intensity distribution - ' tag], 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 15);
grid(ax1, 'on');
set(ax1, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75], 'FontSize', 12, ...
    'FontWeight', 'bold', 'LineWidth', 1.25, 'Box', 'on');

txt1 = sprintf('Thresholds 3 sigma: [%.3f  %.3f]\nRejected volumes: %.1f %%\nQC only - no data modified.', ...
    thresholdLow, thresholdHigh, rejPct);
text(ax1, 0.03, 0.95, txt1, 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Color', 'k', 'BackgroundColor', 'w', ...
    'EdgeColor', [0.4 0.4 0.4], 'FontWeight', 'bold', 'FontSize', 11);
hold(ax1, 'off');

%% Right panel: Rejected volumes over time
ax2 = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.55 0.16 0.40 0.70]);
hold(ax2, 'on');

t = (0:nVols-1) * TR;
hStem = stem(ax2, t, double(outliers), 'filled', 'LineWidth', 2.2, 'MarkerSize', 6);
try
    set(hStem, 'Color', [0 0.20 0.55], ...
        'MarkerFaceColor', [0 0.20 0.55], ...
        'MarkerEdgeColor', [0 0.20 0.55]);
catch
end

try
    b = get(hStem, 'BaseLine');
    set(b, 'Color', [0.35 0.35 0.35], 'LineWidth', 1.2);
catch
end

ylim(ax2, [-0.15 1.15]);
if ~isempty(t), xlim(ax2, [min(t) max(t)+eps]); end
set(ax2, 'YTick', [0 1], 'YTickLabel', {'Accepted', 'Rejected'});
xlabel(ax2, 'Time (s)', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 13);
ylabel(ax2, 'Frame status', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 13);
title(ax2, ['Rejected volumes - ' tag], 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 15);
grid(ax2, 'on');
set(ax2, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
    'GridColor', [0.75 0.75 0.75], 'FontSize', 12, ...
    'FontWeight', 'bold', 'LineWidth', 1.25, 'Box', 'on');

txt2 = sprintf('Rejected: %.1f %%  (%d / %d volumes)', rejPct, sum(outliers), nVols);
text(ax2, 0.03, 0.95, txt2, 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Color', 'k', 'BackgroundColor', 'w', ...
    'EdgeColor', [0.4 0.4 0.4], 'FontWeight', 'bold', 'FontSize', 11);
hold(ax2, 'off');

drawnow;

QC = struct();
QC.globalNormSignal = gNorm;
QC.outliers        = outliers;
QC.sigma           = sigma;
QC.thresholdLow    = thresholdLow;
QC.thresholdHigh   = thresholdHigh;
QC.rejPct          = rejPct;
QC.figIntensity    = fig;
QC.figRejected     = fig;
QC.figCombined     = fig;
end
