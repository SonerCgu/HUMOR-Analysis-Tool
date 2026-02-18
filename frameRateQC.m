function QC = frameRateQC(I, TR, tag, savePNG)
% frameRateQC
% ------------------------------------------------------------
% Frame-rate / PNS QC (Urban / Montaldo style)
% Diagnostic only — NO data modification.
%
% INPUT
%   I       : [nz x nx x nVols] fUSI data
%   TR      : repetition time (sec)
%   tag     : optional label (e.g. 'ORIGINAL', 'INTERPOLATED')
%   savePNG : logical (unused here, kept for compatibility)
%
% OUTPUT (QC struct)
%   QC.globalNormSignal
%   QC.outliers
%   QC.sigma
%   QC.thresholdLow
%   QC.thresholdHigh
%   QC.rejPct
%   QC.figIntensity
%   QC.figRejected
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

if nargin < 3 || isempty(tag)
    tag = 'ORIGINAL';
end
if nargin < 4
    savePNG = false; %#ok<NASGU>
end

[nz,nx,nVols] = size(I); %#ok<ASGLU>

% ------------------------------------------------------------
% Global mean per volume
% ------------------------------------------------------------
g = squeeze(mean(mean(I,1),2));
g = g(:);

% Normalize by median
gNorm = g ./ median(g);

% ------------------------------------------------------------
% Robust noise estimation (LOWER tail only)
% ------------------------------------------------------------
gLow = gNorm(gNorm < 1);
sigma = sqrt(mean((gLow - 1).^2));

k = 3;   % same as script
thresholdHigh = 1 + k*sigma;
thresholdLow  = 1 - k*sigma;

outliers = (gNorm > thresholdHigh) | (gNorm < thresholdLow);

% ------------------------------------------------------------
% Expand rejection window (pad = 0 in your script)
% ------------------------------------------------------------
pad = 0;
outliersDilated = outliers;

for i = 1:pad
    outliersDilated = outliersDilated | ...
                      circshift(outliers, i) | ...
                      circshift(outliers, -i);
end

outliers = outliersDilated;

rejPct = 100 * mean(outliers);

% ------------------------------------------------------------
% FIGURE 1 — Intensity distribution
% ------------------------------------------------------------
fig1 = figure( ...
    'Name',['Frame-rate / PNS QC — Intensity distribution (' tag ')'], ...
    'Color','w','Position',[200 200 900 450]);

nbins = 100;
[counts, edges] = histcounts(gNorm, nbins);
centers = edges(1:end-1) + diff(edges)/2;

bar(centers, counts, 'FaceColor',[0.7 0.7 0.7], 'EdgeColor','none'); hold on

x = linspace(min(gNorm), max(gNorm), 500);
gauss = exp(-0.5*((x-1)/sigma).^2);
gauss = gauss * sum(counts) * (centers(2)-centers(1)) / ...
        (sigma*sqrt(2*pi));

plot(x, gauss,'k','LineWidth',2)

yl = ylim;
plot([thresholdHigh thresholdHigh], yl,'r','LineWidth',2)
plot([thresholdLow  thresholdLow ], yl,'r','LineWidth',2)

xlabel('Normalized global intensity')
ylabel('Number of volumes')
title('Global signal stability (Urban / Montaldo)')
grid on

annotation(fig1,'textbox',[0.60 0.60 0.35 0.30], ...
    'String',sprintf([ ...
        'Thresholds (±%.1f?): [%.3f  %.3f]\n' ...
        'Rejected volumes: %.1f %%\n\n' ...
        'Interpretation:\n' ...
        '• < 10 %%  ? stable acquisition\n' ...
        '• > 10 %%  ? mechanical / motion instability\n' ...
        '• Clustered rejections ? task-related movement\n\n' ...
        'QC only — no data modified.' ], ...
        k, thresholdLow, thresholdHigh, rejPct), ...
    'FitBoxToText','on', ...
    'BackgroundColor','w', ...
    'FontSize',11);

hold off

% ------------------------------------------------------------
% FIGURE 2 — Rejected volumes over time
% ------------------------------------------------------------
fig2 = figure( ...
    'Name',['Frame-rate / PNS QC — Rejected volumes (' tag ')'], ...
    'Color','w','Position',[200 700 900 250]);

t = (0:nVols-1) * TR;
stem(t, outliers, 'filled', 'MarkerSize',4);
ylim([-0.1 1.1])
xlabel('Time (s)')
ylabel('0 = accepted   1 = rejected')
title('Rejected volumes over time')
grid on

% ------------------------------------------------------------
% OUTPUT
% ------------------------------------------------------------
QC = struct();
QC.globalNormSignal = gNorm;
QC.outliers        = outliers;
QC.sigma           = sigma;
QC.thresholdLow    = thresholdLow;
QC.thresholdHigh   = thresholdHigh;
QC.rejPct          = rejPct;
QC.figIntensity    = fig1;
QC.figRejected     = fig2;

end
