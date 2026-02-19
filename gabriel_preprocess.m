function out = gabriel_preprocess(Iin, TRin, opts)
% gabriel_preprocess
% ============================================================
% Clean Gabriel-style preprocessing (MATLAB 2017b compatible)
%
% Supports:
%   - 3D input: Iin [Y X T]
%   - 4D input: Iin [Y X Z T]
%
% Steps:
%   1) Mean temporal block-averaging (no offset, no frame loss)
%   2) Non-rigid drift correction (demons)
%   3) QC figures: DISPLAY (optional) + PNG export (optional)
%
% Notes:
%   - TRin is the original TR
%   - blockDur = TRin * nsub
%   - totalTime reflects true experiment length
% ============================================================

%% ------------------ INPUT CHECKS ------------------
if nargin < 3
    error('gabriel_preprocess requires inputs: Iin, TRin, opts');
end

if ~isfield(opts,'nsub')
    error('opts.nsub is required');
end

nsub = opts.nsub;
if ~isscalar(nsub) || nsub < 2
    error('opts.nsub must be an integer >= 2');
end

if ~isfield(opts,'regSmooth') || isempty(opts.regSmooth)
    opts.regSmooth = 1.3;
end

if ~isfield(opts,'saveQC') || isempty(opts.saveQC)
    opts.saveQC = true;
end

if ~isfield(opts,'showQC') || isempty(opts.showQC)
    opts.showQC = true;
end

if ~isfield(opts,'qcDir') || isempty(opts.qcDir)
    opts.qcDir = 'gabriel_QC';
end

nd = ndims(Iin);
if nd ~= 3 && nd ~= 4
    error('Iin must be 3D [Y X T] or 4D [Y X Z T]');
end

%% ------------------ DIMENSIONS ------------------
if nd == 3
    [ny,nx,nt] = size(Iin);
    nz = 1;
else
    [ny,nx,nz,nt] = size(Iin);
end

nr = floor(nt / nsub);
if nr < 1
    error('Not enough frames (%d) for nsub = %d', nt, nsub);
end

fprintf('[Gabriel] Mean block averaging (nsub = %d)\n', nsub);
fprintf('[Gabriel] Using %d / %d frames\n', nr*nsub, nt);

%% ------------------ STEP 1: SUBSAMPLING ------------------
if nd == 3
    % 2D probe
    Ir = zeros(ny, nx, nr, 'like', Iin);
    for i = 1:nr
        idx = (i-1)*nsub + (1:nsub);
        Ir(:,:,i) = mean(Iin(:,:,idx), 3);
    end
else
    % Matrix probe
    Ir = zeros(ny, nx, nz, nr, 'like', Iin);
    for i = 1:nr
        idx = (i-1)*nsub + (1:nsub);
        Ir(:,:,:,i) = mean(Iin(:,:,:,idx), 4);
    end
end

%% ------------------ STEP 2: REGISTRATION ------------------
fprintf('[Gabriel] Non-rigid registration (demons)\n');

nRef = min(10, nr);
assert(nRef <= nr, 'gabriel_preprocess: nRef exceeds number of blocks');

Ic = Ir;

if nd == 3
    Iref = mean(Ir(:,:,1:nRef), 3);
    for i = 1:nr
        [~, tmp] = imregdemons( ...
            Ir(:,:,i), Iref, ...
            'DisplayWaitbar', false, ...
            'AccumulatedFieldSmoothing', opts.regSmooth);
        Ic(:,:,i) = tmp;
    end
else
    Iref = mean(Ir(:,:,:,1:nRef), 4);
    for i = 1:nr
        [~, tmp] = imregdemons( ...
            Ir(:,:,:,i), Iref, ...
            'DisplayWaitbar', false, ...
            'AccumulatedFieldSmoothing', opts.regSmooth);
        Ic(:,:,:,i) = tmp;
    end
end

%% ------------------ QC: DISPLAY +/or EXPORT ------------------
QC = struct('figIntensity',[],'figRejected',[]);

if opts.saveQC || opts.showQC

    if opts.saveQC && ~exist(opts.qcDir,'dir')
        mkdir(opts.qcDir);
    end

    % ---- Global mean QC (dimension-safe) ----
    g_raw = globalMeanOverTime(Iin);
    g_sub = globalMeanOverTime(Ir);
    g_reg = globalMeanOverTime(Ic);

    t_raw = (0:numel(g_raw)-1) * TRin;
    t_sub = linspace(t_raw(1), t_raw(end), numel(g_sub));

    QC.figIntensity = figure('Color','w','Position',[100 100 950 380], ...
        'Name','Gabriel QC — Global mean','NumberTitle','off');

    plot(t_raw, g_raw,'k','LineWidth',0.8); hold on;
    plot(t_sub, g_sub,'b','LineWidth',1.8);
    plot(t_sub, g_reg,'r','LineWidth',1.8);
    grid on;
    legend({'Raw','Subsampled','Registered'},'Location','best');
    xlabel('Time (s)');
    ylabel('Mean intensity');
    title('QC — Global mean signal');

    if opts.saveQC
        saveas(QC.figIntensity, fullfile(opts.qcDir,'QC_globalMean.png'));
    end

    % ---- Registration QC (robust for 2D & 3D) ----
    if nd == 3
        Ipre  = mean(Ir(:,:,1:nRef), 3);
        Ipost = mean(Ic(:,:,1:nRef), 3);
    else
        Ipre  = mean(Ir(:,:,:,1:nRef), 4);
        Ipost = mean(Ic(:,:,:,1:nRef), 4);
    end

    Ipre2D  = reduceTo2D(Ipre);
    Ipost2D = reduceTo2D(Ipost);
    Idiff2D = Ipost2D - Ipre2D;

    clim = prctile(abs(Idiff2D(:)), 99);

    QC.figRejected = figure('Color','w','Position',[100 520 1250 420], ...
        'Name','Gabriel QC — Registration check','NumberTitle','off');

    subplot(1,3,1); imagesc(Ipre2D);  axis image off; title('Before registration');
    subplot(1,3,2); imagesc(Ipost2D); axis image off; title('After registration');
    subplot(1,3,3); imagesc(Idiff2D); axis image off;
    caxis([-clim clim]); title('Difference (post - pre)');
    colormap gray;

    if opts.saveQC
        saveas(QC.figRejected, fullfile(opts.qcDir,'QC_registration.png'));
    end

    if ~opts.showQC
        if ishandle(QC.figIntensity), close(QC.figIntensity); end
        if ishandle(QC.figRejected),  close(QC.figRejected);  end
        QC.figIntensity = [];
        QC.figRejected  = [];
    end
end

%% ------------------ OUTPUT ------------------
out = struct();
out.I         = Ic;
out.TR = TRin * nsub;
out.blockDur  = TRin * nsub;
out.nVols     = nr;
out.totalTime = nt * TRin;
out.method    = sprintf('Mean block avg (nsub=%d) + demons', nsub);
out.QC        = QC;

fprintf('[Gabriel] blockDur  : %.3f s\n', out.blockDur);
fprintf('[Gabriel] nVols     : %d\n', nr);
fprintf('[Gabriel] totalTime : %.1f s\n', out.totalTime);

end

%% ===================== HELPERS =====================

function g = globalMeanOverTime(X)
    tdim = ndims(X);
    T = size(X, tdim);
    Xp = permute(X, [tdim, 1:tdim-1]);
    Xp = reshape(Xp, T, []);
    g  = mean(Xp, 2).';
end

function I2 = reduceTo2D(V)
    while ndims(V) > 2
        V = mean(V, ndims(V));
    end
    I2 = V;
end
