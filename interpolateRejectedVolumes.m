function Iout = interpolateRejectedVolumes(I, outliers)
% interpolateRejectedVolumes
% ------------------------------------------------------------
% Interpolate rejected volumes along time (Urban/Montaldo style)
%
% INPUT
%   I        : [nz x nx x nVols]
%   outliers : logical [nVols x 1]
%
% OUTPUT
%   Iout     : same size as I
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

[nz,nx,nVols] = size(I);
Iout = I;

good = find(~outliers);
bad  = find(outliers); %#ok<NASGU>

% Safety: too few valid volumes
if numel(good) < 2
    warning('Too few valid volumes for interpolation. Data left unchanged.');
    return;
end

tAll = 1:nVols;

for z = 1:nz
    for x = 1:nx
        sig = squeeze(I(z,x,good));
        Iout(z,x,:) = interp1(good, sig, tAll, 'linear', 'extrap');
    end
end

end
