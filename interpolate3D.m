function scanInt = interpolate3D(atlas, scan)
% interpolate3D (ROBUST)
% ------------------------------------------------------------
% Paper-faithful intent:
%   - Resample scan.Data to atlas.VoxelSize
%   - Then flip/permute axes to match atlas orientation (same as paper code)
%
% Fixes:
%   - Avoids meshgrid/meshgridvectors issues by using ndgrid + interpn
%   - Sanitizes VoxelSize (handles NaN/Inf/<=0)
%   - Guards empty/invalid target sizes
%
% MATLAB 2017b compatible
% ------------------------------------------------------------

% Basic checks
if ~isstruct(scan) || ~isfield(scan,'Data') || isempty(scan.Data)
    error('interpolate3D: scan must be a struct with non-empty field .Data');
end
if ~isstruct(atlas) || ~isfield(atlas,'VoxelSize') || isempty(atlas.VoxelSize)
    error('interpolate3D: atlas must contain field .VoxelSize');
end

D = double(scan.Data);
if ndims(D) == 2
    D = reshape(D, size(D,1), size(D,2), 1);
end

% Ensure scan voxel size exists and is sane
if ~isfield(scan,'VoxelSize') || isempty(scan.VoxelSize)
    scan.VoxelSize = [1 1 1];
end

sv = sanitizeVoxelSize(scan.VoxelSize);
av = sanitizeVoxelSize(atlas.VoxelSize);

dz    = sv(1); dx    = sv(2); dy    = sv(3);
dzint = av(1); dxint = av(2); dyint = av(3);

[nz, nx, ny] = size(D);

% Target sizes (guarded)
n1x = round((nx-1) * dx / dxint) + 1;
n1y = round((ny-1) * dy / dyint) + 1;
n1z = round((nz-1) * dz / dzint) + 1;

if ~isfinite(n1x) || n1x < 1, n1x = 1; end
if ~isfinite(n1y) || n1y < 1, n1y = 1; end
if ~isfinite(n1z) || n1z < 1, n1z = 1; end

% Query coordinates in scan-index space (1-based)
sx = dxint / dx; if ~isfinite(sx) || sx <= 0, sx = 1; end
sy = dyint / dy; if ~isfinite(sy) || sy <= 0, sy = 1; end
sz = dzint / dz; if ~isfinite(sz) || sz <= 0, sz = 1; end

xq = (0:n1x-1) * sx + 1;   % corresponds to dim 2 (x)
yq = (0:n1y-1) * sy + 1;   % corresponds to dim 3 (y)
zq = (0:n1z-1) * sz + 1;   % corresponds to dim 1 (z)

% Use ndgrid in (z,x,y) order to match D = [nz nx ny]
[Zq, Xq, Yq] = ndgrid(zq, xq, yq);

% Interpolate (outside -> 0)
ai = interpn(D, Zq, Xq, Yq, 'linear', 0);

% Paper axis manipulation: flip + permute
ai = flip(ai,3);
ai = flip(ai,2);
ai = permute(ai,[3,1,2]);

scanInt.Data = ai;
scanInt.VoxelSize = av;

end

% ------------------------------------------------------------
% Local helper: sanitize voxel size to [z x y] positive finite
% ------------------------------------------------------------
function v = sanitizeVoxelSize(vin)
v = vin(:)';
if numel(v) < 3
    v = [v, ones(1, 3-numel(v))];
end
v = v(1:3);
for k = 1:3
    if ~isfinite(v(k)) || v(k) <= 0
        v(k) = 1;
    end
end
end