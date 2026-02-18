function B = makeBrushMask(x, y, r, nz, nx)
% makeBrushMask
% ------------------------------------------------------------
% Create circular brush mask.
%
% INPUT
%   x,y : center coordinates (col, row)
%   r   : radius (pixels)
%   nz  : image height
%   nx  : image width
%
% OUTPUT
%   B   : logical [nz x nx] mask
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

B = false(nz,nx);

xMin = max(1, x-r);
xMax = min(nx, x+r);
yMin = max(1, y-r);
yMax = min(nz, y+r);

for yy = yMin:yMax
    for xx = xMin:xMax
        if (xx-x)^2 + (yy-y)^2 <= r^2
            B(yy,xx) = true;
        end
    end
end

end
