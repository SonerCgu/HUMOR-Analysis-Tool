function volume = timeToVolume(t, TR, nVols)
% timeToVolume
% ------------------------------------------------------------
% Convert time (seconds) to nearest valid volume index.
%
% INPUT
%   t     : time (sec)
%   TR    : repetition time (sec)
%   nVols : total number of volumes
%
% OUTPUT
%   volume: valid volume index (1..nVols)
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

volume = round(t ./ TR) + 1;
volume = min(max(volume, 1), nVols);

end
