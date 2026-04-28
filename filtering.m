function [I_filt, stats] = filtering(I, TR, exportPath, opts)
% =========================================================================
% fUSI Studio - Advanced Butterworth Filtering Engine
% =========================================================================
% MATLAB 2017b + 2023b compatible
%
% Processing only.
% No GUI popup is created here.
%
% Recommended GUI/default settings are handled in fusi_studio:
%   type      = 'band'
%   FcLow     = 0.01 Hz
%   FcHigh    = 0.20 Hz
%   order     = 4
%   trimStart = 0 sec
%   trimEnd   = 0 sec
%   useTaper  = true
%
% Features:
%   - Low-pass / high-pass / band-pass Butterworth filtering
%   - Order 1-6
%   - Nyquist safety and validation
%   - Stability check
%   - Optional Gaussian tapering at filtered segment edges
%   - Memory-safe chunked filtering
%   - QC plots saved to Preprocessing/QC_filtering
% =========================================================================

tStart = tic;

% -------------------------------------------------------------------------
% Defaults
% -------------------------------------------------------------------------
if nargin < 3 || isempty(exportPath)
    exportPath = pwd;
end

if nargin < 4 || isempty(opts)
    opts = struct();
end

if numel(TR) > 1
    TR = TR(end);
end

TR = double(TR);

if ~isfinite(TR) || TR <= 0
    error('Invalid TR. TR must be a positive scalar in seconds.');
end

opts.type      = lower(strtrim(char(getOpt(opts,'type','band'))));
opts.FcLow     = scalarNum(getOpt(opts,'FcLow',0.01), 0.01);
opts.FcHigh    = scalarNum(getOpt(opts,'FcHigh',0.20), 0.20);
opts.order     = scalarNum(getOpt(opts,'order',4), 4);
opts.trimStart = scalarNum(getOpt(opts,'trimStart',0), 0);
opts.trimEnd   = scalarNum(getOpt(opts,'trimEnd',0), 0);
opts.useTaper  = logical(getOpt(opts,'useTaper',true));
opts.saveQC    = logical(getOpt(opts,'saveQC',true));
opts.chunkSize = scalarNum(getOpt(opts,'chunkSize',50000), 50000);
opts.tag       = char(getOpt(opts,'tag',datestr(now,'yyyymmdd_HHMMSS')));

opts.tag = regexprep(opts.tag,'[^\w\-]','_');

% Accept common type names
if strcmpi(opts.type,'low-pass') || strcmpi(opts.type,'lowpass') || strcmpi(opts.type,'lpf')
    opts.type = 'low';
elseif strcmpi(opts.type,'high-pass') || strcmpi(opts.type,'highpass') || strcmpi(opts.type,'hpf')
    opts.type = 'high';
elseif strcmpi(opts.type,'band-pass') || strcmpi(opts.type,'bandpass') || strcmpi(opts.type,'bpf')
    opts.type = 'band';
end

if ~ismember(opts.type, {'low','high','band'})
    error('Invalid filter type. Use opts.type = low, high, or band.');
end

opts.order = max(1,min(6,round(opts.order)));
opts.trimStart = max(0,opts.trimStart);
opts.trimEnd   = max(0,opts.trimEnd);
opts.chunkSize = max(1000,round(opts.chunkSize));

% -------------------------------------------------------------------------
% Input dimensions
% -------------------------------------------------------------------------
if isempty(I) || ~isnumeric(I)
    error('Input I must be a non-empty numeric 3D or 4D array.');
end

dims = size(I);
nd = ndims(I);

if nd == 3
    nt = dims(3);
elseif nd == 4
    nt = dims(4);
else
    error('Data must be 3D [Y X T] or 4D [Y X Z T].');
end

if nt < 10
    error('Too few time points for temporal filtering.');
end

Fs  = 1 / TR;
Nyq = Fs / 2;

if Fs <= 0 || Nyq <= 0
    error('Invalid sampling frequency computed from TR.');
end

% -------------------------------------------------------------------------
% Cutoff validation and Nyquist safety
% -------------------------------------------------------------------------
FcLow  = opts.FcLow;
FcHigh = opts.FcHigh;

switch opts.type
    case 'low'
        if ~isfinite(FcHigh) || FcHigh <= 0
            error('Low-pass cutoff FcHigh must be > 0.');
        end
        if FcHigh >= Nyq
            FcHigh = 0.99 * Nyq;
        end
        FcLow = 0;

    case 'high'
        if ~isfinite(FcLow) || FcLow <= 0
            error('High-pass cutoff FcLow must be > 0.');
        end
        if FcLow >= Nyq
            error('High-pass cutoff must be below Nyquist frequency %.6g Hz.', Nyq);
        end
        FcHigh = 0;

    case 'band'
        if ~isfinite(FcLow) || FcLow <= 0
            error('Band-pass low cutoff FcLow must be > 0.');
        end
        if ~isfinite(FcHigh) || FcHigh <= 0
            error('Band-pass high cutoff FcHigh must be > 0.');
        end
        if FcHigh >= Nyq
            FcHigh = 0.99 * Nyq;
        end
        if FcLow >= FcHigh
            error('Band-pass requires FcLow < FcHigh.');
        end
end

opts.FcLow = FcLow;
opts.FcHigh = FcHigh;

% -------------------------------------------------------------------------
% Trimming window
% -------------------------------------------------------------------------
trimStartFrames = round(opts.trimStart / TR);
trimEndFrames   = round(opts.trimEnd   / TR);

idx1 = 1 + trimStartFrames;
idx2 = nt - trimEndFrames;

if idx1 >= idx2
    error('Trimming removes the entire signal. Reduce trimStart/trimEnd.');
end

nFiltFrames = idx2 - idx1 + 1;

% -------------------------------------------------------------------------
% Filter design
% -------------------------------------------------------------------------
switch opts.type
    case 'low'
        Wn = FcHigh / Nyq;
        [b,a] = butter(opts.order, Wn, 'low');

    case 'high'
        Wn = FcLow / Nyq;
        [b,a] = butter(opts.order, Wn, 'high');

    case 'band'
        Wn = [FcLow FcHigh] / Nyq;
        [b,a] = butter(opts.order, Wn, 'bandpass');
end

minFiltLen = 3 * max(length(a), length(b));

if nFiltFrames <= minFiltLen
    error(['Filtered segment is too short for filtfilt. ', ...
           'Available frames = %d, minimum recommended = %d.'], ...
           nFiltFrames, minFiltLen + 1);
end

unstable = any(abs(roots(a)) >= 1);

if unstable
    warning('Butterworth filter may be unstable. Consider reducing filter order.');
end

% -------------------------------------------------------------------------
% QC folder
% -------------------------------------------------------------------------
qcFolder = fullfile(exportPath,'Preprocessing','QC_filtering');

if opts.saveQC
    if ~exist(qcFolder,'dir')
        mkdir(qcFolder);
    end
end

tag = opts.tag;

freqRespFile = '';
globalMeanFile = '';
spectrumFile = '';

% -------------------------------------------------------------------------
% Frequency response QC
% -------------------------------------------------------------------------
if opts.saveQC
    try
        [H,F] = freqz(b,a,1024,Fs);

        figResp = figure('Visible','off','Color','w');
        plot(F,abs(H),'LineWidth',1.5);
        xlabel('Frequency (Hz)');
        ylabel('|H(f)|');
        title('Butterworth Frequency Response');
        grid on;

        freqRespFile = fullfile(qcFolder, ['QC_filtering_FrequencyResponse_' tag '.png']);
        saveas(figResp, freqRespFile);
        close(figResp);
    catch ME
        warning('Could not save filtering frequency response QC: %s', ME.message);
    end
end

% -------------------------------------------------------------------------
% Prepare data
% -------------------------------------------------------------------------
I = double(I);
flat = reshape(I, [], nt);

% Global signal before filtering
gs_before = mean(flat, 1);

% -------------------------------------------------------------------------
% Optional Gaussian tapering at filtering segment edges
% -------------------------------------------------------------------------
taperLength = 0;

if opts.useTaper && (opts.trimStart > 0 || opts.trimEnd > 0)
    taperLength = min(round(2/TR), floor(nFiltFrames/4));

    if taperLength > 5
        try
            g = gausswin(2*taperLength)';
        catch
            x = linspace(-2.5, 2.5, 2*taperLength);
            g = exp(-0.5 * x.^2);
        end

        g = g ./ max(g);

        left  = g(1:taperLength);
        right = g(taperLength+1:end);

        flat(:, idx1:idx1+taperLength-1) = bsxfun( ...
            @times, flat(:, idx1:idx1+taperLength-1), left);

        flat(:, idx2-taperLength+1:idx2) = bsxfun( ...
            @times, flat(:, idx2-taperLength+1:idx2), right);
    end
end

% -------------------------------------------------------------------------
% Chunked filtfilt
% -------------------------------------------------------------------------
flatWork = flat(:, idx1:idx2);

nVox = size(flatWork,1);
chunkSize = opts.chunkSize;
nChunks = ceil(nVox / chunkSize);

for c = 1:nChunks

    s = (c-1)*chunkSize + 1;
    e = min(c*chunkSize, nVox);

    block = flatWork(s:e,:);

    valid = all(isfinite(block),2) & std(block,0,2) > 1e-8;

    if any(valid)
        block(valid,:) = filtfilt(b,a,block(valid,:)')';
    end

    flatWork(s:e,:) = block;
end

flat(:, idx1:idx2) = flatWork;

I_filt = reshape(flat, dims);

% -------------------------------------------------------------------------
% Global signal after filtering
% -------------------------------------------------------------------------
gs_after = mean(flat, 1);
t = (0:nt-1) * TR;

% -------------------------------------------------------------------------
% QC global mean
% -------------------------------------------------------------------------
if opts.saveQC
    try
        fig1 = figure('Visible','off','Color','w');
        plot(t, gs_before, 'k', 'LineWidth', 1.0);
        hold on;
        plot(t, gs_after, 'r', 'LineWidth', 1.5);
        xlabel('Time (s)');
        ylabel('Global Mean');
        legend('Before','After');
        title('Filtering QC - Global Mean');
        grid on;

        globalMeanFile = fullfile(qcFolder, ['QC_filtering_GlobalMean_' tag '.png']);
        saveas(fig1, globalMeanFile);
        close(fig1);
    catch ME
        warning('Could not save filtering global mean QC: %s', ME.message);
    end
end

% -------------------------------------------------------------------------
% QC spectrum
% -------------------------------------------------------------------------
if opts.saveQC
    try
        nHalf = floor(nt/2) + 1;
        f = (0:nHalf-1) * (Fs / nt);

        X1 = abs(fft(gs_before));
        X2 = abs(fft(gs_after));

        fig2 = figure('Visible','off','Color','w');
        plot(f, X1(1:nHalf), 'k', 'LineWidth', 1.0);
        hold on;
        plot(f, X2(1:nHalf), 'r', 'LineWidth', 1.5);
        xlabel('Frequency (Hz)');
        ylabel('Amplitude');
        legend('Before','After');
        title('Filtering QC - Spectrum');
        grid on;

        spectrumFile = fullfile(qcFolder, ['QC_filtering_Spectrum_' tag '.png']);
        saveas(fig2, spectrumFile);
        close(fig2);
    catch ME
        warning('Could not save filtering spectrum QC: %s', ME.message);
    end
end

% -------------------------------------------------------------------------
% Stats
% -------------------------------------------------------------------------
stats = struct();

stats.filterType = opts.type;
stats.order = opts.order;

stats.Fs = Fs;
stats.TR = TR;
stats.Nyquist = Nyq;

stats.FcLow = FcLow;
stats.FcHigh = FcHigh;
stats.Wn = Wn;

stats.trimStart = opts.trimStart;
stats.trimEnd = opts.trimEnd;
stats.trimStartFrames = trimStartFrames;
stats.trimEndFrames = trimEndFrames;
stats.filteredFrameStart = idx1;
stats.filteredFrameEnd = idx2;
stats.nFilteredFrames = nFiltFrames;

stats.useTaper = opts.useTaper;
stats.taperLengthFrames = taperLength;

stats.chunkSize = chunkSize;
stats.nChunks = nChunks;
stats.nVoxels = nVox;

stats.unstable = unstable;
stats.b = b;
stats.a = a;

stats.qcFolder = qcFolder;
stats.qcFrequencyResponseFile = freqRespFile;
stats.qcGlobalMeanFile = globalMeanFile;
stats.qcSpectrumFile = spectrumFile;

stats.processingTime = toc(tStart);
stats.optsResolved = opts;

end

% =========================================================================
% Helper functions
% =========================================================================
function v = getOpt(s, name, defaultVal)

if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
    v = s.(name);
else
    v = defaultVal;
end

end

function x = scalarNum(x, defaultVal)

try
    x = double(x);
    if isempty(x)
        x = defaultVal;
        return;
    end
    x = x(1);
catch
    x = defaultVal;
end

if ~isfinite(x)
    x = defaultVal;
end

end