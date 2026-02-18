function [data, meta] = loadFUSIData(dataFile, fallbackTR)
% loadFUSIData
% ------------------------------------------------------------
% Robust fUSI data loader with TR / time inference
%
% INPUT
%   dataFile   : full path to .mat or .nii
%   fallbackTR : fallback TR (sec) if nothing found
%
% OUTPUT
%   data.I             : [nz x nx x nVols] single
%   data.TR            : repetition time (sec)
%   data.TotalTimeSec  : total acquisition time (sec)
%   data.nVols         : number of volumes
%
%   meta.loadedPar
%   meta.loadedBaseline
%   meta.loadedMask
%   meta.loadedMaskIsInclude
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%   No processing, no GUI, no modification
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

if nargin < 2 || isempty(fallbackTR)
    fallbackTR = 0.3;
end

meta = struct( ...
    'loadedPar', [], ...
    'loadedBaseline', [], ...
    'loadedMask', [], ...
    'loadedMaskIsInclude', true, ...
    'rawMetadata', struct() );


[~,~,ext] = fileparts(dataFile);

switch lower(ext)

    case '.mat'
        S = load(dataFile);
        % -------------------------------------------------
        % RAW METADATA PASS-THROUGH (for GUI save functions)
        % -------------------------------------------------
        meta.rawMetadata = struct();

        % Full metadata struct (if present)
        if isfield(S,'metadata') && isstruct(S.metadata)
            meta.rawMetadata = S.metadata;
        end

        % Common acquisition / geometry fields (flat)
        geomFields = {'imageDim','imageSize','voxelSize', ...
                      'imageType','origin','t0'};

        for iF = 1:numel(geomFields)
            f = geomFields{iF};
            if isfield(S,f)
                meta.rawMetadata.(f) = S.(f);
            end
        end

        if ~isfield(S,'I')
            error('MAT file must contain variable I.');
        end

        I = single(S.I);

        % -----------------------------------------------------
        % AUTO-DETECT TR AND TOTAL ACQUISITION TIME (FAIL-SAFE)
        % -----------------------------------------------------
        TR_found = false;
        T_found  = false;
        timeVec  = [];

        % ---- direct fields ----
        if isfield(S,'TR') && isnumeric(S.TR) && isscalar(S.TR) && S.TR>0
            TR = double(S.TR);
            TR_found = true;
        end

        if isfield(S,'TotalTimeSec') && isnumeric(S.TotalTimeSec) && ...
                isscalar(S.TotalTimeSec) && S.TotalTimeSec>0
            TotalTimeSec = double(S.TotalTimeSec);
            T_found = true;
        end

        % ---- time vectors ----
        if isfield(S,'t') && isnumeric(S.t)
            timeVec = S.t;
        elseif isfield(S,'time') && isnumeric(S.time)
            timeVec = S.time;
        elseif isfield(S,'timestamps') && isnumeric(S.timestamps)
            timeVec = S.timestamps;
        end

        if ~isempty(timeVec)
            timeVec = double(timeVec(:));
            dt = diff(timeVec);
            dt = dt(dt>0 & isfinite(dt));

            if ~isempty(dt)
                if ~TR_found
                    TR = median(dt);
                    TR_found = true;
                end
                if ~T_found
                    TotalTimeSec = (timeVec(end) - timeVec(1)) + TR;
                    T_found = true;
                end
            end
        end

        % ---- sampling rate ----
        if ~TR_found && isfield(S,'Fs') && isnumeric(S.Fs) && S.Fs>0
            TR = 1 / double(S.Fs);
            TR_found = true;
        end

        % ---- final fallbacks ----
        if ~TR_found
            warning('TR not found — using fallback TR = %.3f s', fallbackTR);
            TR = fallbackTR;
        end

        if ~T_found
            TotalTimeSec = size(I,3) * TR;
        end

        % ---- restore optional fields ----
        if isfield(S,'par'),        meta.loadedPar = S.par; end
        if isfield(S,'baseline'),   meta.loadedBaseline = S.baseline; end
        if isfield(S,'mask'),       meta.loadedMask = logical(S.mask); end
        if isfield(S,'maskIsInclude')
            meta.loadedMaskIsInclude = logical(S.maskIsInclude);
        end

    case '.nii'
        V = niftiread(dataFile);
        I = convertNiftiToI(V);

        TR = fallbackTR;
        TotalTimeSec = size(I,3) * TR;

    otherwise
        error('Unsupported file type: %s', ext);
end

% -----------------------------------------------------
% VOLUME CONSISTENCY (FAIL-SAFE, IDENTICAL LOGIC)
% -----------------------------------------------------
nVols_data = size(I,3);
nVols_req  = round(TotalTimeSec / TR);

if nVols_req <= 0 || abs(nVols_req - nVols_data) > 1
    nVols = nVols_data;
    TotalTimeSec = nVols * TR;
else
    nVols = nVols_req;

    if nVols_data > nVols
        I = I(:,:,1:nVols);
    elseif nVols_data < nVols
        I(:,:,end+1:nVols) = repmat(I(:,:,end), [1 1 (nVols-nVols_data)]);
    end
end

data = struct();
data.I            = I;
data.TR           = TR;
data.TotalTimeSec = TotalTimeSec;
data.nVols        = nVols;

end


% -----------------------------------------------------
function I = convertNiftiToI(V)
    if ndims(V) == 4
        V = squeeze(mean(V,3));
    end
    I = single(permute(V,[2 1 3]));
end
