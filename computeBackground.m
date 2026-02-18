function bg = computeBackground(I)
% computeBackground
% ------------------------------------------------------------
% Compute log-compressed background anatomy for visualization.
%
% INPUT
%   I  : [nz x nx x nVols] raw fUSI data
%
% OUTPUT
%   bg : [nz x nx] background image (double)
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

bg = mean(I, 3);

m = max(bg(:));
if m <= 0 || ~isfinite(m)
    bg = zeros(size(bg));
else
    bg = 20 * log10(bg ./ m);
end

end
