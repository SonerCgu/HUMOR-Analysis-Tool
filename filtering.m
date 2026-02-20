function [I_filt, stats] = filtering(I, TR, exportPath, opts)
% =========================================================================
% fUSI Studio — Advanced Butterworth Filtering Engine
% =========================================================================
% Features:
%   - Low / High / Band pass
%   - Order 1–6
%   - Nyquist safety
%   - Filter stability check
%   - Gaussian tapering at trim edges
%   - Memory chunking
%   - Vectorized fast filtering
%   - QC plots
%   - Frequency response preview
%   - QC saved to Preprocessing/QC_filtering
% =========================================================================

tStart = tic;

I = double(I);
dims = size(I);
nd = ndims(I);

if nd == 3
    [ny,nx,nt] = size(I);
elseif nd == 4
    [ny,nx,nz,nt] = size(I);
else
    error('Data must be 3D or 4D.');
end

Fs  = 1/TR;
Nyq = Fs/2;

% =========================================================
% SAFETY CHECKS
% =========================================================
order = max(1,min(6,round(opts.order)));

if Fs <= 0
    error('Invalid TR.');
end

% Nyquist safety
if strcmp(opts.type,'low') || strcmp(opts.type,'band')
    if opts.FcHigh >= Nyq
        opts.FcHigh = 0.99 * Nyq;
    end
end

if strcmp(opts.type,'high') || strcmp(opts.type,'band')
    if opts.FcLow <= 0
        opts.FcLow = 0.001;
    end
end

% =========================================================
% TRIMMING
% =========================================================
trimStartFrames = round(opts.trimStart/TR);
trimEndFrames   = round(opts.trimEnd/TR);

idx1 = 1 + trimStartFrames;
idx2 = nt - trimEndFrames;

if idx1 >= idx2
    error('Trimming removes entire signal.');
end

% =========================================================
% FILTER DESIGN
% =========================================================
switch opts.type

    case 'low'
        Wn = opts.FcHigh / Nyq;
        [b,a] = butter(order,Wn,'low');

    case 'high'
        Wn = opts.FcLow / Nyq;
        [b,a] = butter(order,Wn,'high');

    case 'band'
        Wn = [opts.FcLow opts.FcHigh] / Nyq;
        [b,a] = butter(order,Wn,'bandpass');
end

% Stability check
if any(abs(roots(a)) >= 1)
    warning('Filter may be unstable.');
end

% =========================================================
% PREVIEW FREQUENCY RESPONSE
% =========================================================
qcFolder = fullfile(exportPath,'Preprocessing','QC_filtering');
if ~exist(qcFolder,'dir')
    mkdir(qcFolder);
end

[H,F] = freqz(b,a,1024,Fs);

figResp = figure('Visible','off');
plot(F,abs(H));
xlabel('Frequency (Hz)');
ylabel('|H(f)|');
title('Butterworth Frequency Response');
saveas(figResp, fullfile(qcFolder,'Filter_FrequencyResponse.png'));
close(figResp);

% =========================================================
% GLOBAL SIGNAL BEFORE
% =========================================================
flat = reshape(I,[],nt);
gs_before = mean(flat,1);

% =========================================================
% GAUSSIAN TAPERING
% =========================================================
if opts.trimStart > 0 || opts.trimEnd > 0
    taperLength = min( round(2/TR), floor((idx2-idx1)/4) );
    if taperLength > 5
        g = gausswin(2*taperLength)';
        left  = g(1:taperLength);
        right = g(taperLength+1:end);

        flat(:,idx1:idx1+taperLength-1) = ...
            flat(:,idx1:idx1+taperLength-1) .* left;

        flat(:,idx2-taperLength+1:idx2) = ...
            flat(:,idx2-taperLength+1:idx2) .* fliplr(right);
    end
end

% =========================================================
% FAST VECTORIZED FILTERING WITH CHUNKING
% =========================================================
flatWork = flat(:,idx1:idx2);
nVox = size(flatWork,1);

chunkSize = 50000;   % safe for large matrix probes
nChunks = ceil(nVox/chunkSize);

for c = 1:nChunks

    s = (c-1)*chunkSize + 1;
    e = min(c*chunkSize,nVox);

    block = flatWork(s:e,:);

    % Remove constant voxels
    valid = std(block,0,2) > 1e-8;
    block(valid,:) = filtfilt(b,a,block(valid,:)')';

    flatWork(s:e,:) = block;
end

flat(:,idx1:idx2) = flatWork;
I_filt = reshape(flat,dims);

% =========================================================
% GLOBAL SIGNAL AFTER
% =========================================================
flat2 = reshape(I_filt,[],nt);
gs_after = mean(flat2,1);

t = (0:nt-1)*TR;

% =========================================================
% QC TIMECOURSE
% =========================================================
fig1 = figure('Visible','off');
plot(t,gs_before,'k'); hold on;
plot(t,gs_after,'r','LineWidth',1.5);
xlabel('Time (s)');
ylabel('Global Mean');
legend('Before','After');
title('Filtering QC — Global Mean');
saveas(fig1, fullfile(qcFolder,'GlobalMean_overlay.png'));
close(fig1);

% =========================================================
% QC SPECTRUM
% =========================================================
f = linspace(0,Nyq,floor(nt/2));
X1 = abs(fft(gs_before));
X2 = abs(fft(gs_after));

fig2 = figure('Visible','off');
plot(f,X1(1:length(f)),'k'); hold on;
plot(f,X2(1:length(f)),'r','LineWidth',1.5);
xlabel('Frequency (Hz)');
ylabel('Amplitude');
legend('Before','After');
title('Filtering QC — Spectrum');
saveas(fig2, fullfile(qcFolder,'Spectrum_overlay.png'));
close(fig2);

% =========================================================
% STATS
% =========================================================
stats.filterType = opts.type;
stats.order = order;
stats.Fs = Fs;
stats.processingTime = toc(tStart);
stats.qcFolder = qcFolder;
stats.trimStart = opts.trimStart;
stats.trimEnd   = opts.trimEnd;

end
