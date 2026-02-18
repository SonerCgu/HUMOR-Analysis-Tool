function t = volumeToTime(volume, TR)
% volumeToTime
% ------------------------------------------------------------
% Convert volume index to time (seconds).
%
% INPUT
%   volume : scalar or array (1-based index)
%   TR     : repetition time (sec)
%
% OUTPUT
%   t      : time in seconds
%
% LOGIC:
%   IDENTICAL to usage in fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

t = (volume - 1) .* TR;

end
