function [I3D, motorInfo] = motor(I, TR, qcFolder)
% =========================================================
% MOTOR RECONSTRUCTION (FRAME-BASED, STUDIO-SAFE)
% 2D -> 3D reconstruction for step-motor acquisitions
%
% INPUT
%   I        : raw data [Y x X x T]
%   TR       : seconds per frame
%   qcFolder : QC output folder
%
% OUTPUT
%   I3D      : reconstructed data [Y x X x nSlices x Tnew]
%   motorInfo: info struct (includes legacy fields used by Studio)
%
% DESIGN
%   - Frame-based reconstruction (more robust than time find() logic)
%   - Supports initial sequential baseline per slice
%   - Recommended correction: additive block matching to each slice baseline
%   - Residual despiking after reconstruction
%
% BASELINE INTERPRETATION
%   If baseline frames per slice = 188 and nSlices = 7, then:
%     frames   1:188     = slice 1 baseline
%     frames 189:376     = slice 2 baseline
%     ...
%   Motor-run starts only after all baseline blocks are finished.
%
% MATLAB 2017b / 2023b compatible
% =========================================================

if ndims(I) ~= 3
    error('Motor expects 2D data [Y x X x T].');
end

if nargin < 3 || isempty(qcFolder)
    qcFolder = pwd;
end

I = single(I);
[Y, X, T] = size(I);

if ~isscalar(TR) || ~isfinite(TR) || TR <= 0
    error('TR must be a positive scalar.');
end

%% --------------------------------------------------------
% DEFAULTS
%% --------------------------------------------------------
defaults = struct();
defaults.nSlices            = 7;
defaults.motorFramesPerSlice= max(1, round(60/TR));   % use frames, safer
defaults.baseFramesPerSlice = max(1, round(60/TR));
defaults.secTrim            = 3;
defaults.correctionMode     = 2;   % 1=none, 2=additive match, 3=scalar PSC
defaults.doDespike          = true;
defaults.spikeThr           = 4.0;

P = localMotorDialog(defaults, TR);
if isempty(P)
    error('Motor cancelled.');
end

nSlices             = round(P.nSlices);
motorFramesPerSlice = round(P.motorFramesPerSlice);
baseFramesPerSlice  = round(P.baseFramesPerSlice);
secTrim             = P.secTrim;
correctionMode      = P.correctionMode;
doDespike           = logical(P.doDespike);
spikeThr            = P.spikeThr;

if nSlices < 1 || mod(nSlices,1) ~= 0
    error('Number of slices must be a positive integer.');
end
if motorFramesPerSlice < 1
    error('Motor frames per slice must be >= 1.');
end
if baseFramesPerSlice < 0
    error('Baseline frames per slice must be >= 0.');
end
if ~isfinite(secTrim) || secTrim < 0
    error('Trim seconds must be >= 0.');
end
if ~isfinite(spikeThr) || spikeThr <= 0
    error('Spike threshold must be > 0.');
end

trimFrames = round(secTrim / TR);
if trimFrames < 0
    trimFrames = 0;
end

validFramesPerSlice = motorFramesPerSlice - 2*trimFrames;
if validFramesPerSlice < 1
    error('Trim too large. Reduce trim or increase frames per slice.');
end

if baseFramesPerSlice > 0
    validBaseFrames = baseFramesPerSlice - 2*trimFrames;
    if validBaseFrames < 3
        error('Baseline block too short after trimming. Increase baseline frames or reduce trim.');
    end
else
    validBaseFrames = 0;
end

sliceSeconds = motorFramesPerSlice * TR;
baselineSeconds = baseFramesPerSlice * TR;

%% --------------------------------------------------------
% FRAME LAYOUT
%% --------------------------------------------------------
totalBaseFrames = nSlices * baseFramesPerSlice;
cycleFrames     = nSlices * motorFramesPerSlice;

availableFrames = T - totalBaseFrames;
if availableFrames <= 0
    error('Initial baseline frames exceed total recording length.');
end

nCycles = floor(availableFrames / cycleFrames);
if nCycles < 1
    error('Not enough frames for one complete motor cycle.');
end

TnewMax = nCycles * validFramesPerSlice;

%% --------------------------------------------------------
% BASELINE REFERENCES
%% --------------------------------------------------------
baselineScalar = nan(nSlices,1);
baselineFramesUsed = zeros(nSlices,1);

if baseFramesPerSlice > 0
    for s = 1:nSlices
        rawStart = (s-1)*baseFramesPerSlice + 1;
        rawEnd   = s*baseFramesPerSlice;

        idxStart = rawStart + trimFrames;
        idxEnd   = rawEnd   - trimFrames;

        if idxEnd < idxStart
            error('Baseline indices invalid after trimming for slice %d.', s);
        end

        idxBase = idxStart:idxEnd;
        if numel(idxBase) < 3
            error('Not enough baseline frames for slice %d.', s);
        end

        bt = localMeanTrace(I(:,:,idxBase));
        baselineScalar(s) = median(bt);
        baselineFramesUsed(s) = numel(idxBase);
    end
end

%% --------------------------------------------------------
% RECONSTRUCTION
%% --------------------------------------------------------
I3D_raw = zeros(Y, X, nSlices, TnewMax, 'single');
fillCount   = zeros(nSlices,1);
blockStartIdx = nan(nSlices, nCycles);
blockEndIdx   = nan(nSlices, nCycles);

for s = 1:nSlices
    cnt = 0;

    for c = 1:nCycles
        rawBlockStart = totalBaseFrames + (c-1)*cycleFrames + (s-1)*motorFramesPerSlice + 1;
        rawBlockEnd   = rawBlockStart + motorFramesPerSlice - 1;

        idxStart = rawBlockStart + trimFrames;
        idxEnd   = rawBlockEnd   - trimFrames;

        if idxEnd > T || idxStart < 1 || idxEnd < idxStart
            continue;
        end

        idx = idxStart:idxEnd;
        if numel(idx) ~= validFramesPerSlice
            continue;
        end

        st = cnt + 1;
        en = cnt + validFramesPerSlice;

        I3D_raw(:,:,s,st:en) = I(:,:,idx);
        blockStartIdx(s,c) = st;
        blockEndIdx(s,c)   = en;
        cnt = en;
    end

    fillCount(s) = cnt;
end

Tnew = min(fillCount);
if Tnew < 5
    error('Not enough usable reconstructed frames after trimming.');
end

I3D_raw = I3D_raw(:,:,:,1:Tnew);

%% --------------------------------------------------------
% FALLBACK BASELINE REFERENCES
% If no explicit initial baseline exists, use first reconstructed block
%% --------------------------------------------------------
if baseFramesPerSlice == 0
    for s = 1:nSlices
        gotRef = false;

        for c = 1:nCycles
            st = blockStartIdx(s,c);
            en = blockEndIdx(s,c);

            if ~isnan(st) && ~isnan(en) && en <= Tnew
                rt = localMeanTrace(I3D_raw(:,:,s,st:en));
                baselineScalar(s) = median(rt);
                baselineFramesUsed(s) = en - st + 1;
                gotRef = true;
                break;
            end
        end

        if ~gotRef
            rt = localMeanTrace(I3D_raw(:,:,s,:));
            baselineScalar(s) = median(rt);
            baselineFramesUsed(s) = Tnew;
        end
    end
end

%% --------------------------------------------------------
% CORRECTION
% 1 = none
% 2 = additive block matching to slice baseline (recommended)
% 3 = scalar PSC to slice baseline
%% --------------------------------------------------------
I3D = I3D_raw;

switch correctionMode
    case 1
        % raw only

    case 2
        for s = 1:nSlices
            refLevel = baselineScalar(s);

            for c = 1:nCycles
                st = blockStartIdx(s,c);
                en = blockEndIdx(s,c);

                if isnan(st) || isnan(en) || en > Tnew
                    continue;
                end

                tr = localMeanTrace(I3D(:,:,s,st:en));
                blockLevel = median(tr);
                delta = blockLevel - refLevel;

                I3D(:,:,s,st:en) = I3D(:,:,s,st:en) - single(delta);
            end
        end

    case 3
        epsVal = 1e-6;
        for s = 1:nSlices
            refLevel = baselineScalar(s);
            if abs(refLevel) < epsVal
                refLevel = epsVal;
            end
            for t = 1:Tnew
                I3D(:,:,s,t) = 100 * (I3D_raw(:,:,s,t) - single(refLevel)) / single(refLevel);
            end
        end

    otherwise
        error('Unknown correction mode.');
end

%% --------------------------------------------------------
% DESPIKE
% Combined robust residual + derivative check
%% --------------------------------------------------------
spikeMask = false(nSlices, Tnew);

if doDespike
    for s = 1:nSlices
        tr = localMeanTrace(I3D(:,:,s,:));

        medRun = localRunningMedian(tr, 7);
        resid  = tr - medRun;
        resid0 = median(resid);
        sigma1 = 1.4826 * median(abs(resid - resid0));
        if sigma1 <= 0
            sigma1 = std(resid);
        end

        dtr = [0; diff(tr)];
        d0  = median(dtr);
        sigma2 = 1.4826 * median(abs(dtr - d0));
        if sigma2 <= 0
            sigma2 = std(dtr);
        end

        idx1 = false(size(tr));
        idx2 = false(size(tr));

        if isfinite(sigma1) && sigma1 > 0
            idx1 = abs(resid - resid0) > spikeThr * sigma1;
        end
        if isfinite(sigma2) && sigma2 > 0
            idx2 = abs(dtr - d0) > spikeThr * sigma2;
        end

        idxSpike = idx1 | idx2;
        spikeMask(s, idxSpike) = true;

        spikeIdx = find(idxSpike);
        for k = 1:numel(spikeIdx)
            t = spikeIdx(k);

            neigh = max(1, t-2):min(Tnew, t+2);
            neigh(neigh == t) = [];
            neigh = neigh(~spikeMask(s, neigh));

            if isempty(neigh)
                neigh = max(1, t-1):min(Tnew, t+1);
                neigh(neigh == t) = [];
            end

            if ~isempty(neigh)
                repl = squeeze(median(I3D(:,:,s,neigh), 4));
                I3D(:,:,s,t) = single(repl);
            end
        end
    end
end

%% --------------------------------------------------------
% QC
%% --------------------------------------------------------
if ~exist(qcFolder, 'dir')
    mkdir(qcFolder);
end

timeSec = (0:T-1) * TR;
timeMin = timeSec / 60;

fig1 = figure('Visible', 'off', 'Position', [100 80 1450 900]);

rawGlobal = localMeanTrace(I);

subplot(2,1,1)
plot(rawGlobal, 'k', 'LineWidth', 1.2);
title('Global RAW Mean (Entire Recording)');
ylabel('Intensity');
grid on;
hold on;

yl = ylim;
if totalBaseFrames > 0
    motorStartFrame = totalBaseFrames + 1;
    line([motorStartFrame motorStartFrame], yl, 'Color', [0 0.45 0.9], ...
        'LineStyle', '--', 'LineWidth', 1.5);
    text(motorStartFrame, yl(2), '  Motor start', 'Color', [0 0.45 0.9], ...
        'VerticalAlignment', 'top', 'FontWeight', 'bold');
end

subplot(2,1,2)
plot(timeMin, rawGlobal, 'k', 'LineWidth', 1.2);
title('Global RAW Mean vs Time');
xlabel('Time (min)');
ylabel('Intensity');
grid on;
hold on;
yl = ylim;
if totalBaseFrames > 0
    line([totalBaseFrames*TR/60 totalBaseFrames*TR/60], yl, ...
        'Color', [0 0.45 0.9], 'LineStyle', '--', 'LineWidth', 1.5);
end

annotation('textbox', [0 0.96 1 0.03], ...
    'String', 'Motor QC - Original Raw Timeline', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', 'FontSize', 14);

saveas(fig1, fullfile(qcFolder, 'motor_QC_raw_timeline.png'));
close(fig1);

fig2 = figure('Visible', 'off', 'Position', [120 70 1450 980]);

for s = 1:nSlices
    subplot(nSlices+1,1,s)
    tr = localMeanTrace(I3D(:,:,s,:));
    plot(tr, 'r', 'LineWidth', 1.1);
    hold on;
    if doDespike && any(spikeMask(s,:))
        plot(find(spikeMask(s,:)), tr(spikeMask(s,:)), 'ko', 'MarkerSize', 4, 'LineWidth', 1.0);
    end
    grid on;

    if correctionMode == 3
        ylabel('PSC (%)');
    else
        ylabel('Intensity');
    end

    title(sprintf('Slice %d | baseline ref = %.3f | frames = %d', ...
        s, baselineScalar(s), Tnew));
end

subplot(nSlices+1,1,nSlices+1)
bar(baselineScalar);
xlabel('Slice');
ylabel('Baseline');
title('Baseline Reference per Slice');
grid on;

annotation('textbox', [0 0.96 1 0.03], ...
    'String', 'Motor QC - Reconstructed Slice Traces', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', 'FontSize', 14);

saveas(fig2, fullfile(qcFolder, 'motor_QC_reconstructed.png'));
close(fig2);

drawnow;

%% --------------------------------------------------------
% OUTPUT / LEGACY COMPATIBILITY
%% --------------------------------------------------------
motorInfo = struct();
motorInfo.nSlices = nSlices;

% legacy fields used elsewhere in Studio
motorInfo.volumesPerSlice = Tnew;
motorInfo.minutesPerSlice = (Tnew * TR) / 60;
motorInfo.TR = TR;
motorInfo.cycles = nCycles;
motorInfo.trimSeconds = secTrim;
motorInfo.sliceSeconds = sliceSeconds;
motorInfo.baselineSeconds = baselineSeconds;

% new fields
motorInfo.trimFrames = trimFrames;
motorInfo.motorFramesPerSlice = motorFramesPerSlice;
motorInfo.baselineFramesPerSlice = baseFramesPerSlice;
motorInfo.validFramesPerSlice = validFramesPerSlice;
motorInfo.reconstructedFramesPerSlice = Tnew;
motorInfo.totalInitialBaselineFrames = totalBaseFrames;
motorInfo.totalInitialBaselineSeconds = totalBaseFrames * TR;
motorInfo.fillCountPerSlice = fillCount;
motorInfo.baselineFramesUsed = baselineFramesUsed;
motorInfo.baselineScalar = baselineScalar;
motorInfo.despikeApplied = doDespike;
motorInfo.spikeThreshold = spikeThr;
motorInfo.spikeMask = spikeMask;
motorInfo.baselineMode = 'Sequential per-slice baseline at recording start';

switch correctionMode
    case 1
        motorInfo.correctionMode = 'RAW_NONE';
    case 2
        motorInfo.correctionMode = 'ADDITIVE_BLOCK_MATCH_TO_SLICE_BASELINE';
    case 3
        motorInfo.correctionMode = 'SCALAR_PSC_TO_SLICE_BASELINE';
end

clear rawGlobal tr

end

% =========================================================
% LOCAL FUNCTIONS
% =========================================================
function tr = localMeanTrace(A)
tmp = squeeze(mean(mean(A,1),2));
tr = double(tmp(:));
end

function y = localRunningMedian(x, win)
x = double(x(:));
n = numel(x);
halfW = floor(win/2);
y = zeros(n,1);

for i = 1:n
    i1 = max(1, i-halfW);
    i2 = min(n, i+halfW);
    y(i) = median(x(i1:i2));
end
end

function P = localMotorDialog(defaults, TR)
P = [];

bg  = [0.09 0.11 0.14];
bg2 = [0.13 0.15 0.19];
fg  = [1.00 1.00 1.00];
mut = [0.78 0.84 0.92];
edb = [0.18 0.20 0.24];
green = [0.16 0.64 0.32];
red   = [0.78 0.18 0.18];
blue  = [0.14 0.45 0.82];

dlgW = 760;
dlgH = 500;
scr = get(0, 'ScreenSize');
dlgX = max(50, round((scr(3)-dlgW)/2));
dlgY = max(50, round((scr(4)-dlgH)/2));

d = dialog( ...
    'Name', 'Motor Reconstruction', ...
    'Position', [dlgX dlgY dlgW dlgH], ...
    'WindowStyle', 'modal', ...
    'Resize', 'off', ...
    'Color', bg, ...
    'CloseRequestFcn', @(~,~)localCancel());

uicontrol(d, 'Style', 'text', ...
    'Position', [20 452 720 26], ...
    'String', 'Motor Reconstruction', ...
    'BackgroundColor', bg, ...
    'ForegroundColor', fg, ...
    'FontSize', 15, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center');

uicontrol(d, 'Style', 'text', ...
    'Position', [20 426 720 18], ...
    'String', sprintf('TR = %.4f s  |  Recommended: 188 frames = %.2f s', TR, 188*TR), ...
    'BackgroundColor', bg, ...
    'ForegroundColor', mut, ...
    'FontSize', 10, ...
    'HorizontalAlignment', 'center');

uicontrol(d, 'Style', 'text', ...
    'Position', [28 396 704 20], ...
    'String', 'Baseline is sequential at the start: slice1 baseline, then slice2 baseline, ..., then motor run.', ...
    'BackgroundColor', bg, ...
    'ForegroundColor', [0.65 0.90 0.75], ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

uipanel('Parent', d, ...
    'Units', 'pixels', ...
    'Position', [20 112 720 270], ...
    'BackgroundColor', bg2, ...
    'ForegroundColor', blue, ...
    'Title', 'Settings', ...
    'FontWeight', 'bold', ...
    'FontSize', 11);

labelX = 40;
editX  = 500;
editW  = 150;
rowY   = [336 294 252 210 168 126];
rowH   = 28;

mkLbl = @(txt,y) uicontrol(d, 'Style', 'text', ...
    'Position', [labelX y 420 rowH], ...
    'String', txt, ...
    'BackgroundColor', bg2, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left');

mkEdit = @(txt,y) uicontrol(d, 'Style', 'edit', ...
    'Position', [editX y editW rowH], ...
    'String', txt, ...
    'BackgroundColor', edb, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold');

mkLbl('Number of slices', rowY(1));
hSlices = mkEdit(num2str(defaults.nSlices), rowY(1));

mkLbl('Motor frames per slice', rowY(2));
hMotorFrames = mkEdit(num2str(defaults.motorFramesPerSlice), rowY(2));

mkLbl('Initial baseline frames per slice (0 allowed)', rowY(3));
hBaseFrames = mkEdit(num2str(defaults.baseFramesPerSlice), rowY(3));

mkLbl('Trim seconds at start and end of each block', rowY(4));
hTrim = mkEdit(num2str(defaults.secTrim), rowY(4));

mkLbl('Residual spike threshold (robust SD)', rowY(5));
hSpike = mkEdit(num2str(defaults.spikeThr), rowY(5));

mkLbl('Correction mode', rowY(6));
hMode = uicontrol(d, 'Style', 'popupmenu', ...
    'Position', [360 rowY(6) 290 rowH], ...
    'String', { ...
        '1) None (raw only)', ...
        '2) Additive match to slice baseline', ...
        '3) Scalar PSC to slice baseline'}, ...
    'Value', defaults.correctionMode, ...
    'BackgroundColor', edb, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold');

hDespike = uicontrol(d, 'Style', 'checkbox', ...
    'Position', [40 92 360 22], ...
    'String', 'Apply residual whole-frame despiking', ...
    'Value', defaults.doDespike, ...
    'BackgroundColor', bg, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold');

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [170 26 120 40], ...
    'String', 'Use 188', ...
    'BackgroundColor', blue, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localPreset188());

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [320 26 120 40], ...
    'String', 'Cancel', ...
    'BackgroundColor', red, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localCancel());

uicontrol(d, 'Style', 'pushbutton', ...
    'Position', [470 26 180 40], ...
    'String', 'Run Reconstruction', ...
    'BackgroundColor', green, ...
    'ForegroundColor', fg, ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'Callback', @(~,~)localOK());

uiwait(d);

if ishandle(d)
    out = getappdata(d, 'MotorDialogOutput');
    if ~isempty(out)
        P = out;
    end
    delete(d);
end

    function localPreset188()
        set(hMotorFrames, 'String', '188');
        set(hBaseFrames,  'String', '188');
    end

    function localOK()
        out = struct();
        out.nSlices             = str2double(strtrim(get(hSlices, 'String')));
        out.motorFramesPerSlice = str2double(strtrim(get(hMotorFrames, 'String')));
        out.baseFramesPerSlice  = str2double(strtrim(get(hBaseFrames, 'String')));
        out.secTrim             = str2double(strtrim(get(hTrim, 'String')));
        out.spikeThr            = str2double(strtrim(get(hSpike, 'String')));
        out.correctionMode      = get(hMode, 'Value');
        out.doDespike           = logical(get(hDespike, 'Value'));

        vals = [out.nSlices out.motorFramesPerSlice out.baseFramesPerSlice out.secTrim out.spikeThr];
        if any(isnan(vals))
            errordlg('Please enter valid numeric values.', 'Invalid input', 'modal');
            return;
        end

        setappdata(d, 'MotorDialogOutput', out);
        uiresume(d);
    end

    function localCancel()
        setappdata(d, 'MotorDialogOutput', []);
        if strcmp(get(d, 'Visible'), 'on')
            uiresume(d);
        else
            delete(d);
        end
    end
end