function out = gabriel_preprocess(Iin, TRin, opts)
% gabriel_preprocess
% ============================================================
% Supports:
%   - 3D input: Iin [Y X T]
%   - 4D input: Iin [Y X Z T]
%
% Steps:
%   1) Block-averaging with MEAN or MEDIAN (user-selectable)
%   2) Non-rigid drift correction (imregdemons)
%   3) QC figures: DISPLAY (optional) + PNG export (optional)
%
% NEW MOTOR SUPPORT:
%   - Standard 4D data [Y X Z T] can still be treated as true 3D volume data
%   - Step motor data [Y X Z T] can now be treated as independent 2D slices
%     and registered slice-by-slice over time
%   - Force this with:
%         opts.stepMotorMode = true;
%     or let it auto-detect from opts fields
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
if ~isscalar(nsub) || nsub < 2 || isnan(nsub)
    error('opts.nsub must be an integer >= 2');
end
nsub = round(nsub);

if ~isfield(opts,'regSmooth') || isempty(opts.regSmooth)
    opts.regSmooth = 1.3;
end

if ~isfield(opts,'saveQC') || isempty(opts.saveQC)
    opts.saveQC = true;
end

if ~isfield(opts,'showQC') || isempty(opts.showQC)
    opts.showQC = true;
end

if ~isfield(opts,'tag') || isempty(opts.tag)
    opts.tag = datestr(now,'yyyymmdd_HHMMSS');
end

if ~isfield(opts,'qcDir') || isempty(opts.qcDir)
    if isfield(opts,'exportPath') && ~isempty(opts.exportPath)
        opts.qcDir = fullfile(opts.exportPath, 'Preprocessing', 'QC_gabriel');
    else
        opts.qcDir = fullfile(pwd, 'Preprocessing', 'QC_gabriel');
    end
end

% ------------------ block method (median vs mean) ------------------
if ~isfield(opts,'blockMethod') || isempty(opts.blockMethod)
    opts.blockMethod = 'median';
end
opts.blockMethod = lower(strtrim(opts.blockMethod));
if ~ismember(opts.blockMethod, {'median','mean'})
    opts.blockMethod = 'median';
end

if strcmp(opts.blockMethod,'mean')
    blockReduce = @(X,dim) mean(X, dim);
else
    blockReduce = @(X,dim) median(X, dim);
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

% NEW: detect whether 4D data should be treated as step motor slices
isStepMotor = detectStepMotorMode(opts, nd);

nr = floor(nt / nsub);
if nr < 1
    error('Not enough frames (%d) for nsub = %d', nt, nsub);
end

fprintf('[Gabriel] Block averaging (%s, nsub = %d)\n', opts.blockMethod, nsub);
fprintf('[Gabriel] Using %d / %d frames\n', nr*nsub, nt);

if nd == 4 && isStepMotor
    fprintf('[Gabriel] Step motor mode detected: using PER-SLICE 2D demons over Z slices\n');
elseif nd == 4
    fprintf('[Gabriel] Standard 4D mode detected: using 3D demons\n');
end

%% ------------------ STEP 1: SUBSAMPLING (MEAN or MEDIAN) ------------------
if nd == 3
    % 2D probe or already split single slice
    Ir = zeros(ny, nx, nr, 'like', Iin);
    for i = 1:nr
        idx = (i-1)*nsub + (1:nsub);
        Ir(:,:,i) = blockReduce(Iin(:,:,idx), 3);
    end
else
    % 4D input [Y X Z T]
    Ir = zeros(ny, nx, nz, nr, 'like', Iin);
    for i = 1:nr
        idx = (i-1)*nsub + (1:nsub);
        Ir(:,:,:,i) = blockReduce(Iin(:,:,:,idx), 4);
    end
end

%% ------------------ STEP 2: REGISTRATION ------------------
fprintf('[Gabriel] Non-rigid registration (demons)\n');

nRef = min(10, nr);
assert(nRef <= nr, 'gabriel_preprocess: nRef exceeds number of blocks');

Ic = Ir;

if nd == 3
    % Normal 2D per-time registration
    Iref = blockReduce(Ir(:,:,1:nRef), 3);
    for i = 1:nr
        Ic(:,:,i) = runDemonsSafe(Ir(:,:,i), Iref, opts.regSmooth);
    end

else
    if isStepMotor
        % NEW: motor stack support
        % Treat each Z slice independently as a 2D time-series
        Iref = zeros(ny, nx, nz, 'like', Ir);

        for iz = 1:nz
            Iref(:,:,iz) = squeeze(blockReduce(Ir(:,:,iz,1:nRef), 4));
        end

        for iz = 1:nz
            ref2D = Iref(:,:,iz);
            fprintf('[Gabriel]   Registering motor slice %d / %d\n', iz, nz);

            for i = 1:nr
                moving2D = Ir(:,:,iz,i);
                Ic(:,:,iz,i) = runDemonsSafe(moving2D, ref2D, opts.regSmooth);
            end
        end

    else
        % Original 3D volume registration
        Iref = blockReduce(Ir(:,:,:,1:nRef), 4);
        for i = 1:nr
            Ic(:,:,:,i) = runDemonsSafe(Ir(:,:,:,i), Iref, opts.regSmooth);
        end
    end
end

%% ------------------ QC: DISPLAY +/or EXPORT ------------------
QC = struct('figIntensity',[],'figRejected',[]);

if opts.saveQC || opts.showQC

    if opts.saveQC && ~exist(opts.qcDir,'dir')
        mkdir(opts.qcDir);
    end

    % ---- Global median QC (dimension-safe; stays median by design) ----
    g_raw = globalMedianOverTime(Iin);
    g_sub = globalMedianOverTime(Ir);
    g_reg = globalMedianOverTime(Ic);

    t_raw = (0:numel(g_raw)-1) * TRin;
    t_sub = linspace(t_raw(1), t_raw(end), numel(g_sub));

    QC.figIntensity = figure('Color','w','Position',[100 100 950 380], ...
        'Name','Gabriel QC - Global median','NumberTitle','off');

    plot(t_raw, g_raw,'k','LineWidth',0.8); hold on;
    plot(t_sub, g_sub,'b','LineWidth',1.8);
    plot(t_sub, g_reg,'r','LineWidth',1.8);
    grid on;
    legend({'Raw','Subsampled','Registered'},'Location','best');
    xlabel('Time (s)');
    ylabel('Median intensity');
    title('QC - Global median signal');

    if opts.saveQC
        saveas(QC.figIntensity, fullfile(opts.qcDir, ['QC_gabriel_globalMedian_' opts.tag '.png']));
    end

    % ---- Registration QC ----
    if nd == 3
        Ipre  = blockReduce(Ir(:,:,1:nRef), 3);
        Ipost = blockReduce(Ic(:,:,1:nRef), 3);

        Ipre2D  = reduceTo2D(Ipre);
        Ipost2D = reduceTo2D(Ipost);
        Idiff2D = Ipost2D - Ipre2D;

        clim = prctile(abs(Idiff2D(:)), 99);
        if ~isfinite(clim) || clim <= 0
            clim = 1;
        end

        QC.figRejected = figure('Color','w','Position',[100 520 1250 420], ...
            'Name','Gabriel QC - Registration check','NumberTitle','off');

        subplot(1,3,1); imagesc(Ipre2D);  axis image off; title('Before registration');
        subplot(1,3,2); imagesc(Ipost2D); axis image off; title('After registration');
        subplot(1,3,3); imagesc(Idiff2D); axis image off;
        caxis([-clim clim]); title('Difference (post - pre)');
        colormap gray;

    elseif isStepMotor
        % NEW: per-slice QC for motor stacks
        showSlices = unique(round(linspace(1, nz, min(nz, 6))));
        nShow = numel(showSlices);

        QC.figRejected = figure('Color','w', ...
            'Position',[100 520 1250 max(420, 220*nShow)], ...
            'Name','Gabriel QC - Registration check (step motor slices)', ...
            'NumberTitle','off');

        for k = 1:nShow
            iz = showSlices(k);

            Ipre2D  = squeeze(blockReduce(Ir(:,:,iz,1:nRef), 4));
            Ipost2D = squeeze(blockReduce(Ic(:,:,iz,1:nRef), 4));
            Idiff2D = Ipost2D - Ipre2D;

            clim = prctile(abs(Idiff2D(:)), 99);
            if ~isfinite(clim) || clim <= 0
                clim = 1;
            end

            subplot(nShow,3,(k-1)*3+1);
            imagesc(Ipre2D); axis image off;
            title(sprintf('Slice %d before', iz));

            subplot(nShow,3,(k-1)*3+2);
            imagesc(Ipost2D); axis image off;
            title(sprintf('Slice %d after', iz));

            subplot(nShow,3,(k-1)*3+3);
            imagesc(Idiff2D); axis image off;
            caxis([-clim clim]);
            title(sprintf('Slice %d diff', iz));
        end
        colormap gray;

    else
        % Original 3D QC path
        Ipre  = blockReduce(Ir(:,:,:,1:nRef), 4);
        Ipost = blockReduce(Ic(:,:,:,1:nRef), 4);

        Ipre2D  = reduceTo2D(Ipre);
        Ipost2D = reduceTo2D(Ipost);
        Idiff2D = Ipost2D - Ipre2D;

        clim = prctile(abs(Idiff2D(:)), 99);
        if ~isfinite(clim) || clim <= 0
            clim = 1;
        end

        QC.figRejected = figure('Color','w','Position',[100 520 1250 420], ...
            'Name','Gabriel QC - Registration check','NumberTitle','off');

        subplot(1,3,1); imagesc(Ipre2D);  axis image off; title('Before registration');
        subplot(1,3,2); imagesc(Ipost2D); axis image off; title('After registration');
        subplot(1,3,3); imagesc(Idiff2D); axis image off;
        caxis([-clim clim]); title('Difference (post - pre)');
        colormap gray;
    end

    if opts.saveQC
        saveas(QC.figRejected, fullfile(opts.qcDir, ['QC_gabriel_registration_' opts.tag '.png']));
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
out.I           = Ic;
out.TR          = TRin * nsub;
out.blockDur    = TRin * nsub;
out.nVols       = nr;
out.totalTime   = nt * TRin;
out.QC          = QC;
out.isStepMotor = isStepMotor;
out.nSlices     = nz;

if nd == 4 && isStepMotor
    out.registrationMode = 'per-slice-2D-demons';
    out.method = sprintf('%s block avg (nsub=%d) + demons per slice (motor)', ...
        [upper(opts.blockMethod(1)) opts.blockMethod(2:end)], nsub);
elseif nd == 4
    out.registrationMode = '3D-demons';
    out.method = sprintf('%s block avg (nsub=%d) + demons 3D', ...
        [upper(opts.blockMethod(1)) opts.blockMethod(2:end)], nsub);
else
    out.registrationMode = '2D-demons';
    out.method = sprintf('%s block avg (nsub=%d) + demons', ...
        [upper(opts.blockMethod(1)) opts.blockMethod(2:end)], nsub);
end

fprintf('[Gabriel] blockDur  : %.3f s\n', out.blockDur);
fprintf('[Gabriel] nVols     : %d\n', nr);
fprintf('[Gabriel] totalTime : %.1f s\n', out.totalTime);

end

%% ===================== HELPERS =====================

function g = globalMedianOverTime(X)
    tdim = ndims(X);
    T = size(X, tdim);
    Xp = permute(X, [tdim, 1:tdim-1]);
    Xp = reshape(Xp, T, []);
    g  = median(Xp, 2).';
end

function I2 = reduceTo2D(V)
    while ndims(V) > 2
        V = median(V, ndims(V));
    end
    I2 = V;
end

function tf = detectStepMotorMode(opts, nd)
% Conservative auto-detection.
% Explicit user flag wins. Otherwise look for common motor keywords/flags.

    tf = false;

    if nd ~= 4
        return;
    end

    % Explicit flags first
    explicitFields = {'stepMotorMode','isStepMotor','perSliceDemons','motorSlicesAreIndependent'};
    for iF = 1:numel(explicitFields)
        fn = explicitFields{iF};
        if isfield(opts, fn) && ~isempty(opts.(fn))
            tf = toLogicalLocal(opts.(fn));
            return;
        end
    end

    % Flat string / char fields in opts
    tf = tf || structHasMotorKeyword(opts);

    % Nested common structs
    nestedFields = {'meta','md','dataset','info','datasetInfo'};
    for iF = 1:numel(nestedFields)
        fn = nestedFields{iF};
        if isfield(opts, fn) && isstruct(opts.(fn))
            if structHasMotorKeyword(opts.(fn))
                tf = true;
                return;
            end
        end
    end
end

function tf = structHasMotorKeyword(S)
    tf = false;

    if ~isstruct(S)
        return;
    end

    fns = fieldnames(S);
    for iF = 1:numel(fns)
        v = S.(fns{iF});

        % direct logical/numeric motor flags
        if any(strcmpi(fns{iF}, {'stepMotorMode','isStepMotor','perSliceDemons','motorSlicesAreIndependent'}))
            tf = toLogicalLocal(v);
            if tf
                return;
            end
        end

        % string-like fields
        if ischar(v)
            s = lower(strtrim(v));
            if hasMotorKeyword(s)
                tf = true;
                return;
            end
        elseif exist('isstring','builtin') && isstring(v) && isscalar(v)
            s = lower(strtrim(char(v)));
            if hasMotorKeyword(s)
                tf = true;
                return;
            end
        end
    end
end

function tf = hasMotorKeyword(s)
    tf = false;

    if isempty(s)
        return;
    end

    keys = {'step motor','stepmotor','motor','zaber','slice stack','slice-stack','multislice','multi-slice'};
    for iK = 1:numel(keys)
        if ~isempty(strfind(s, keys{iK})); %#ok<STREMP>
            tf = true;
            return;
        end
    end
end

function tf = toLogicalLocal(v)
    if islogical(v)
        tf = v(1);
    elseif isnumeric(v)
        tf = logical(v(1));
    elseif ischar(v)
        s = lower(strtrim(v));
        tf = any(strcmp(s, {'1','true','yes','y','on','step motor','stepmotor','motor'}));
    elseif exist('isstring','builtin') && isstring(v) && isscalar(v)
        s = lower(strtrim(char(v)));
        tf = any(strcmp(s, {'1','true','yes','y','on','step motor','stepmotor','motor'}));
    else
        tf = false;
    end
end

function tmp = runDemonsSafe(moving, fixed, regSmooth)
% Safe wrapper around imregdemons with adaptive PyramidLevels.
% Needed for small motor slices where default PyramidLevels=3 can fail.

    szM = size(moving);
    szF = size(fixed);

    minDim = min([szM(:); szF(:)]);

    if minDim >= 8
        pLevel = 3;
    elseif minDim >= 4
        pLevel = 2;
    else
        pLevel = 1;
    end

    try
        [~, tmp] = imregdemons( ...
            moving, fixed, ...
            'DisplayWaitbar', false, ...
            'AccumulatedFieldSmoothing', regSmooth, ...
            'PyramidLevels', pLevel);
    catch ME
        error('imregdemons failed (minDim=%d, PyramidLevels=%d): %s', ...
            minDim, pLevel, ME.message);
    end
end