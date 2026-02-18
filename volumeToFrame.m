function frame = volumeToFrame(volume, interpol, nFrames)
% volumeToFrame
% ------------------------------------------------------------
% Convert volume index to interpolated frame index safely.
%
% INPUT
%   volume   : 1-based volume index
%   interpol : interpolation factor
%   nFrames  : total interpolated frames
%
% OUTPUT
%   frame    : valid frame index
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

frame = (volume - 1) * interpol + 1;
frame = min(max(frame, 1), nFrames);

end
