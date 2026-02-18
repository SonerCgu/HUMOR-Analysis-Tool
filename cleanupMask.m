function BW = cleanupMask(BW, minPix)
% cleanupMask
% ------------------------------------------------------------
% Remove small disconnected components from binary mask.
% Toolbox-safe: works with or without Image Processing Toolbox.
%
% INPUT
%   BW     : logical mask
%   minPix : minimum cluster size (default = 15)
%
% OUTPUT
%   BW     : cleaned logical mask
%
% LOGIC:
%   IDENTICAL behavior to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

if nargin < 2 || isempty(minPix)
    minPix = 15;
end

try
    % Image Processing Toolbox
    BW = bwareaopen(BW, minPix);
catch
    % Toolbox-free fallback
    CC = bwconncomp(BW, 4);
    BW(:) = false;
    for i = 1:CC.NumObjects
        if numel(CC.PixelIdxList{i}) >= minPix
            BW(CC.PixelIdxList{i}) = true;
        end
    end
end

end
