function cfg = showScmVideoSetupDialog(modeName, defaultBaseStart, defaultBaseEnd, defaultUnderlayIdx, varargin)

if nargin < 1 || isempty(modeName),           modeName = 'SCM / Video'; end
if nargin < 2 || isempty(defaultBaseStart),   defaultBaseStart = 30; end
if nargin < 3 || isempty(defaultBaseEnd),     defaultBaseEnd = 240; end
if nargin < 4 || isempty(defaultUnderlayIdx), defaultUnderlayIdx = 5; end

% -------------------------------------------------------------------------
% UNDERLAY CHOICES
%   1 = Default (current SCM / Video bg)
%   2 = Mean of ACTIVE dataset
%   3 = Median of ACTIVE dataset
%   4 = External underlay file
%   5 = Recommended Standard (same as Mask Editor default)
% -------------------------------------------------------------------------

defaultUnderlayIdx = round(defaultUnderlayIdx);
if ~isfinite(defaultUnderlayIdx) || defaultUnderlayIdx < 1 || defaultUnderlayIdx > 5
    defaultUnderlayIdx = 5;
end

I = pickInputVolume(varargin{:});

cfg = struct();
cfg.cancelled = true;
cfg.baselineStart = defaultBaseStart;
cfg.baselineEnd   = defaultBaseEnd;
cfg.underlayChoice = defaultUnderlayIdx;
cfg.underlayIdx = defaultUnderlayIdx;
cfg.underlayLabel = '';
cfg.externalFile = '';
cfg.requiresExternalFile = false;

% These are the important outputs for the caller
cfg.precomputedUnderlay = [];
cfg.precomputedUnderlayDisplay = [];
cfg.precomputedUnderlayMode = [];
cfg.precomputedDisplaySettings = struct();

bg    = [0.06 0.06 0.07];
bg2   = [0.10 0.10 0.11];
fg    = [0.96 0.96 0.96];
fgDim = [0.72 0.72 0.75];

dlg = figure( ...
    'Name', [modeName ' Setup'], ...
    'Color', bg, ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'NumberTitle', 'off', ...
    'Resize', 'off', ...
    'Units', 'pixels', ...
    'Position', [250 150 760 540], ...
    'WindowStyle', 'modal', ...
    'Visible', 'off', ...
    'CloseRequestFcn', @onCancel);

movegui(dlg, 'center');

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.05 0.92 0.90 0.055], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'FontSize',18, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'String',[modeName ' Setup']);

uicontrol('Parent',dlg,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.05 0.865 0.90 0.04], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fgDim, ...
    'FontSize',11, ...
    'HorizontalAlignment','left', ...
    'String','Choose baseline and underlay before opening the GUI.');

p1 = uipanel('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.05 0.60 0.90 0.20], ...
    'BackgroundColor',bg2, ...
    'ForegroundColor',[0.35 0.35 0.35], ...
    'BorderType','line', ...
    'Title','Baseline', ...
    'FontSize',12, ...
    'FontWeight','bold');

uicontrol('Parent',p1,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.05 0.57 0.36 0.22], ...
    'BackgroundColor',bg2, ...
    'ForegroundColor',fg, ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'String','Baseline START (sec)');

ebStart = uicontrol('Parent',p1,'Style','edit', ...
    'Units','normalized', ...
    'Position',[0.45 0.57 0.20 0.24], ...
    'BackgroundColor',[0.18 0.18 0.19], ...
    'ForegroundColor',fg, ...
    'FontSize',12, ...
    'String',num2str(defaultBaseStart));

uicontrol('Parent',p1,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.05 0.20 0.36 0.22], ...
    'BackgroundColor',bg2, ...
    'ForegroundColor',fg, ...
    'FontSize',12, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'String','Baseline END (sec)');

ebEnd = uicontrol('Parent',p1,'Style','edit', ...
    'Units','normalized', ...
    'Position',[0.45 0.20 0.20 0.24], ...
    'BackgroundColor',[0.18 0.18 0.19], ...
    'ForegroundColor',fg, ...
    'FontSize',12, ...
    'String',num2str(defaultBaseEnd));

if isempty(I)
    dataMsg = 'No active dataset passed into dialog. Mean / Median / Recommended cannot be computed.';
    dataCol = [0.95 0.55 0.35];
else
    dataMsg = 'Active dataset detected. Mean / Median / Recommended will be computed directly.';
    dataCol = [0.55 0.90 0.60];
end

uicontrol('Parent',p1,'Style','text', ...
    'Units','normalized', ...
    'Position',[0.69 0.18 0.28 0.30], ...
    'BackgroundColor',bg2, ...
    'ForegroundColor',dataCol, ...
    'FontSize',10.5, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'String',dataMsg);

p2 = uibuttongroup('Parent',dlg, ...
    'Units','normalized', ...
    'Position',[0.05 0.18 0.90 0.36], ...
    'BackgroundColor',bg2, ...
    'ForegroundColor',[0.35 0.35 0.35], ...
    'BorderType','line', ...
    'Title','Underlay', ...
    'FontSize',12, ...
    'FontWeight','bold');

rb1 = uicontrol('Parent',p2,'Style','radiobutton', ...
    'Units','normalized','Position',[0.05 0.77 0.90 0.13], ...
    'BackgroundColor',bg2,'ForegroundColor',fg, ...
    'FontSize',12,'FontWeight','bold', ...
    'String','Default (current SCM / Video reference bg)');

rb2 = uicontrol('Parent',p2,'Style','radiobutton', ...
    'Units','normalized','Position',[0.05 0.59 0.90 0.13], ...
    'BackgroundColor',bg2,'ForegroundColor',fg, ...
    'FontSize',12,'FontWeight','bold', ...
    'String','Mean of ACTIVE dataset');

rb3 = uicontrol('Parent',p2,'Style','radiobutton', ...
    'Units','normalized','Position',[0.05 0.41 0.90 0.13], ...
    'BackgroundColor',bg2,'ForegroundColor',fg, ...
    'FontSize',12,'FontWeight','bold', ...
    'String','Median of ACTIVE dataset (robust)');

rb4 = uicontrol('Parent',p2,'Style','radiobutton', ...
    'Units','normalized','Position',[0.05 0.23 0.90 0.13], ...
    'BackgroundColor',bg2,'ForegroundColor',fg, ...
    'FontSize',12,'FontWeight','bold', ...
    'String','Select external underlay file');

rb5 = uicontrol('Parent',p2,'Style','radiobutton', ...
    'Units','normalized','Position',[0.05 0.05 0.90 0.13], ...
    'BackgroundColor',bg2,'ForegroundColor',fg, ...
    'FontSize',12,'FontWeight','bold', ...
    'String','Recommended Standard (same as Mask Editor default)');

switch defaultUnderlayIdx
    case 1
        set(p2,'SelectedObject',rb1);
    case 2
        set(p2,'SelectedObject',rb2);
    case 3
        set(p2,'SelectedObject',rb3);
    case 4
        set(p2,'SelectedObject',rb4);
    otherwise
        set(p2,'SelectedObject',rb5);
end

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'String','Open', ...
    'Units','normalized', ...
    'Position',[0.62 0.055 0.17 0.085], ...
    'FontWeight','bold', ...
    'FontSize',12, ...
    'BackgroundColor',[0.15 0.70 0.35], ...
    'ForegroundColor','w', ...
    'Callback',@onOpen);

uicontrol('Parent',dlg,'Style','pushbutton', ...
    'String','Cancel', ...
    'Units','normalized', ...
    'Position',[0.81 0.055 0.14 0.085], ...
    'FontWeight','bold', ...
    'FontSize',12, ...
    'BackgroundColor',[0.75 0.25 0.25], ...
    'ForegroundColor','w', ...
    'Callback',@onCancel);

set(dlg,'Visible','on');
waitfor(dlg);

    function onOpen(~,~)
        b0 = str2double(get(ebStart,'String'));
        b1 = str2double(get(ebEnd,'String'));

        if ~isfinite(b0) || ~isfinite(b1) || b1 <= b0
            errordlg('Invalid baseline range.','Setup');
            return;
        end

        sel = get(p2,'SelectedObject');
        if isequal(sel,rb1)
            idx = 1;
        elseif isequal(sel,rb2)
            idx = 2;
        elseif isequal(sel,rb3)
            idx = 3;
        elseif isequal(sel,rb4)
            idx = 4;
        else
            idx = 5;
        end

        cfg.cancelled = false;
        cfg.baselineStart = b0;
        cfg.baselineEnd = b1;
        cfg.underlayChoice = idx;
        cfg.underlayIdx = idx;
        cfg.precomputedUnderlay = [];
        cfg.precomputedUnderlayDisplay = [];
        cfg.precomputedUnderlayMode = [];
        cfg.precomputedDisplaySettings = struct();
        cfg.externalFile = '';
        cfg.requiresExternalFile = false;

        switch idx
            case 1
                cfg.underlayLabel = 'Default bg';
                cfg.precomputedUnderlayMode = 1;

            case 2
                if isempty(I)
                    errordlg('No active dataset was passed into showScmVideoSetupDialog, so Mean cannot be computed. Call it with ..., I.','Setup');
                    return;
                end
                U = underlayMeanLinear(I);
                cfg.underlayLabel = 'Mean(T) [linear]';
                cfg.precomputedUnderlay = U;
                cfg.precomputedUnderlayDisplay = buildLinearDisplay(U);
                cfg.precomputedUnderlayMode = 2;
                cfg.precomputedDisplaySettings = linearDisplayDefaults();

            case 3
                if isempty(I)
                    errordlg('No active dataset was passed into showScmVideoSetupDialog, so Median cannot be computed. Call it with ..., I.','Setup');
                    return;
                end
                U = underlayMedianLinear(I);
                cfg.underlayLabel = 'Median(T) [linear]';
                cfg.precomputedUnderlay = U;
                cfg.precomputedUnderlayDisplay = buildLinearDisplay(U);
                cfg.precomputedUnderlayMode = 3;
                cfg.precomputedDisplaySettings = linearDisplayDefaults();

            case 4
                cfg.requiresExternalFile = true;
                cfg.underlayLabel = 'External underlay';

                [f,p] = uigetfile( ...
                    {'*.mat;*.nii;*.nii.gz;*.tif;*.tiff;*.png;*.jpg;*.jpeg', ...
                     'Underlay (*.mat,*.nii,*.nii.gz, images)'}, ...
                    'Select external underlay');

                if isequal(f,0)
                    cfg.cancelled = true;
                    if ishandle(dlg)
                        delete(dlg);
                    end
                    return;
                end

                cfg.externalFile = fullfile(p,f);

            case 5
                if isempty(I)
                    errordlg('No active dataset was passed into showScmVideoSetupDialog, so the recommended underlay cannot be computed. Call it with ..., I.','Setup');
                    return;
                end

                U = underlayStandardizedEqualized(I, 2.0);

                cfg.underlayLabel = 'Standardized Doppler equalized';
                cfg.precomputedUnderlay = U;
                cfg.precomputedUnderlayDisplay = buildRecommendedDisplay(U);
                cfg.precomputedUnderlayMode = 7;
                cfg.precomputedDisplaySettings = recommendedDisplayDefaults();
        end

        if ishandle(dlg)
            delete(dlg);
        end
    end

    function onCancel(~,~)
        cfg.cancelled = true;
        if ishandle(dlg)
            delete(dlg);
        end
    end

end


% =========================================================================
% Helper: pick active volume from extra inputs
% =========================================================================
function I = pickInputVolume(varargin)

I = [];

for k = 1:numel(varargin)
    a = varargin{k};

    if isnumeric(a) && (ndims(a) == 3 || ndims(a) == 4)
        I = a;
        return;
    end

    if isstruct(a)
        if isfield(a,'I') && isnumeric(a.I) && (ndims(a.I) == 3 || ndims(a.I) == 4)
            I = a.I;
            return;
        end
        if isfield(a,'data') && isnumeric(a.data) && (ndims(a.data) == 3 || ndims(a.data) == 4)
            I = a.data;
            return;
        end
        if isfield(a,'volume') && isnumeric(a.volume) && (ndims(a.volume) == 3 || ndims(a.volume) == 4)
            I = a.volume;
            return;
        end
    end
end

end


% =========================================================================
% Mean underlay
% =========================================================================
function U = underlayMeanLinear(Iin)

Iin = double(Iin);

if ndims(Iin) == 3
    U = mean(Iin, 3);
    U = reshape(U, [size(U,1) size(U,2) 1]);
else
    U = mean(Iin, 4);
end

U(~isfinite(U)) = 0;

end


% =========================================================================
% Median underlay
% =========================================================================
function U = underlayMedianLinear(Iin)

Iin = double(Iin);

if ndims(Iin) == 3
    T = size(Iin,3);
    idx = pickSubsampleIdx(T, 600);
    U = median(Iin(:,:,idx), 3);
    U = reshape(U, [size(U,1) size(U,2) 1]);
else
    T = size(Iin,4);
    idx = pickSubsampleIdx(T, 600);
    U = median(Iin(:,:,:,idx), 4);
end

U(~isfinite(U)) = 0;

end


% =========================================================================
% Recommended underlay: same idea as mask editor mode 7
% =========================================================================
function U = underlayStandardizedEqualized(Iin, gain)

gain = max(0, min(5, double(gain)));
Iin = double(Iin);

if ndims(Iin) == 3
    a0 = mean(Iin, 3);
    U2 = equalizeImageVasc_local(a0, gain);
    U = reshape(U2, [size(U2,1) size(U2,2) 1]);
    return;
end

nY = size(Iin,1);
nX = size(Iin,2);
nZ = size(Iin,3);

a0 = mean(Iin, 4);
U = zeros(nY, nX, nZ, 'double');

for zz = 1:nZ
    U(:,:,zz) = equalizeImageVasc_local(a0(:,:,zz), gain);
end

U(~isfinite(U)) = 0;

end


% =========================================================================
% Equalization used by recommended underlay
% =========================================================================
function ae = equalizeImageVasc_local(a, gain)

a = double(a);
a(~isfinite(a)) = 0;

[nz_, nx_] = size(a);

mx = max(a(:));
if ~isfinite(mx) || mx <= 0
    ae = zeros(size(a));
    return;
end

a = a ./ mx;
ae = zeros(nz_, nx_);

g = 1 + (0:nz_-1)' / max(1,nz_) * gain;
gg = g * ones(1, nx_);

tmp = a;
tmp = tmp - min(tmp(:));
tmp = tmp .* gg;

mx2 = max(tmp(:));
if ~isfinite(mx2) || mx2 <= 0
    ae = zeros(size(a));
    return;
end
tmp = tmp ./ mx2;

m = median(tmp(:));
if ~isfinite(m) || m <= 0
    m = eps;
end

comp = -1 / log2(m);
if ~isfinite(comp) || comp <= 0
    comp = 1;
end

tmp = tmp .^ comp;

mx3 = max(tmp(:));
if ~isfinite(mx3) || mx3 <= 0
    ae = zeros(size(a));
    return;
end
tmp = tmp ./ mx3;

ae = tmp;
ae = ae - min(ae(:));

mx4 = max(ae(:));
if ~isfinite(mx4) || mx4 <= 0
    ae = zeros(size(a));
    return;
end
ae = ae ./ mx4;

end


% =========================================================================
% Display builders
% =========================================================================
function Udisp = buildRecommendedDisplay(Uraw)

stdLow  = 0.40;
stdHigh = 0.80;

brightness = 0.10;
contrast   = 0.50;
gamma      = 1.10;
sharpness  = 150.0;

softToneEnable   = true;
softToneStrength = 0.40;
softToneMid      = 0.48;
softToneToe      = 0.08;

Udisp = Uraw;
for zz = 1:size(Uraw,3)
    X = scaleFixed(Uraw(:,:,zz), stdLow, stdHigh);
    X = applyDisplayAdjust(X, brightness, contrast, gamma, sharpness);
    X = applySoftToneMaybe(X, softToneEnable, softToneStrength, softToneMid, softToneToe);
    X = min(max(X,0),1);
    Udisp(:,:,zz) = X;
end

end


function Udisp = buildLinearDisplay(Uraw)

Udisp = Uraw;
for zz = 1:size(Uraw,3)
    X = scale01_local(Uraw(:,:,zz), 1, 99);
    X = min(max(X,0),1);
    Udisp(:,:,zz) = X;
end

end


% =========================================================================
% Display defaults metadata
% =========================================================================
function S = recommendedDisplayDefaults()

S = struct();
S.stdLow = 0.40;
S.stdHigh = 0.80;
S.stdGain = 2.0;

S.brightness = 0.10;
S.contrast   = 0.50;
S.gamma      = 1.10;
S.sharpness  = 150.0;

S.softToneEnable   = true;
S.softToneStrength = 0.40;
S.softToneMid      = 0.48;
S.softToneToe      = 0.08;

S.vesselEnable = false;
S.vesselSigma  = 0.20;
S.vesselGain   = 0.50;
S.vesselThresh = 0.80;
S.vesselConnect = true;

S.cmapMode = 1;
S.globalScaling = false;

end


function S = linearDisplayDefaults()

S = struct();
S.brightness = 0.00;
S.contrast   = 1.00;
S.gamma      = 1.00;
S.sharpness  = 0.0;
S.softToneEnable = false;
S.softToneStrength = 0.20;
S.softToneMid = 0.48;
S.softToneToe = 0.08;
S.cmapMode = 1;
S.globalScaling = false;

end


% =========================================================================
% Display math
% =========================================================================
function U01 = scaleFixed(U, lo, hi)

U = double(U);
if ~isfinite(lo), lo = min(U(:)); end
if ~isfinite(hi), hi = max(U(:)); end
if hi <= lo + eps
    hi = lo + 1;
end

U(~isfinite(U)) = lo;
U = min(max(U, lo), hi);
U01 = (U - lo) / max(eps, (hi - lo));
U01 = min(max(U01,0),1);

end


function U01 = scale01_local(U, pLow, pHigh)

U = double(U);
U(~isfinite(U)) = 0;

v = U(:);
p1 = safePercentile(v, pLow);
p99 = safePercentile(v, pHigh);

if ~isfinite(p1) || ~isfinite(p99) || p99 <= p1
    p1 = min(U(:));
    p99 = max(U(:));
    if p99 <= p1
        U01 = zeros(size(U));
        return;
    end
end

U = min(max(U, p1), p99);
U01 = (U - p1) / max(eps, (p99 - p1));
U01 = min(max(U01,0),1);

end


function p = safePercentile(v, q)

v = double(v(:));
v = v(isfinite(v));

if isempty(v)
    p = 0;
    return;
end

q = max(0, min(100, double(q)));

try
    p = prctile(v, q);
catch
    v = sort(v);
    if numel(v) == 1
        p = v(1);
        return;
    end
    pos = 1 + (numel(v)-1) * (q/100);
    i0 = floor(pos);
    i1 = ceil(pos);
    if i0 == i1
        p = v(i0);
    else
        p = v(i0) + (pos - i0) * (v(i1) - v(i0));
    end
end

end


function U01 = applyDisplayAdjust(U01, bright, cont, gam, sharp)

U01 = double(U01);

U01 = U01 * cont + bright;
U01 = min(max(U01,0),1);

U01 = U01 .^ (1 / max(eps, gam));
U01 = min(max(U01,0),1);

sharp = max(0, min(300, double(sharp)));
if sharp > 0
    amountMax = 4.5;
    amount = amountMax * (1 - exp(-sharp/60));
    sigma = 1.10 + 0.90*(sharp/300);

    B = gaussBlur2D(U01, sigma);
    hi = U01 - B;
    hi = 0.35 * tanh(hi / 0.35);

    U01 = U01 + amount * hi;
    U01 = min(max(U01,0),1);
end

end


function U01 = applySoftToneMaybe(U01, enabled, strength, mid, toe)

U01 = double(U01);
U01 = min(max(U01,0),1);

if ~enabled
    return;
end

a = max(0, min(1, double(strength)));
mid = max(0.05, min(0.95, double(mid)));
toe = max(0, min(0.35, double(toe)));
gain = 1 + 10*a;

L = 0.5 + 0.5*tanh(gain*(U01 - mid));
L0 = 0.5 + 0.5*tanh(gain*(0 - mid));
L1 = 0.5 + 0.5*tanh(gain*(1 - mid));
L = (L - L0) / max(eps, (L1 - L0));
L = min(max(L,0),1);

L = (1 - toe) * L + toe * sqrt(L);
U01 = (1 - a) * U01 + a * L;
U01 = min(max(U01,0),1);

end


function B = gaussBlur2D(A, sigma)

sigma = max(0, double(sigma));
if sigma <= 0
    B = A;
    return;
end

try
    B = imgaussfilt(A, sigma);
catch
    rad = max(1, ceil(3*sigma));
    x = -rad:rad;
    g = exp(-(x.^2)/(2*sigma^2));
    g = g / sum(g);
    B = conv2(conv2(A, g, 'same'), g', 'same');
end

end


% =========================================================================
% Median subsampling helper
% =========================================================================
function idx = pickSubsampleIdx(T, maxFrames)

if T <= maxFrames
    idx = 1:T;
else
    step = ceil(T/maxFrames);
    idx = 1:step:T;
end

end