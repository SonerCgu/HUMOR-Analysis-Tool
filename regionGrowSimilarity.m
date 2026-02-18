function region = regionGrowSimilarity(sig, sy, sx, winR, sigmaFactor, maxPix)
% regionGrowSimilarity
% ------------------------------------------------------------
% Very permissive region growing based on local signal similarity.
%
% INPUT
%   sig         : 2D signal image (PSC frame)
%   sy, sx      : seed coordinates (row, col)
%   winR        : local window radius
%   sigmaFactor : tolerance multiplier
%   maxPix      : maximum grown pixels
%
% OUTPUT
%   region      : logical region mask
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

[H,W] = size(sig);
region = false(H,W);

% Local window
yMin = max(1, sy-winR);
yMax = min(H, sy+winR);
xMin = max(1, sx-winR);
xMax = min(W, sx+winR);

patch = sig(yMin:yMax, xMin:xMax);
mu = mean(patch(:));
sd = std(patch(:));
if sd < 1e-6, sd = 1e-6; end

% Very permissive tolerance
tol = max(sigmaFactor * sd, 0.25 * abs(mu));

% BFS queue
qy = zeros(maxPix,1);
qx = zeros(maxPix,1);
head = 1; tail = 1;

qy(1) = sy; qx(1) = sx;
region(sy,sx) = true;

while head <= tail && tail < maxPix

    y = qy(head);
    x = qx(head);
    head = head + 1;

    % 4-connected neighbors
    if y>1 && ~region(y-1,x)
        if abs(sig(y-1,x) - mu) <= tol
            tail = tail + 1;
            qy(tail) = y-1; qx(tail) = x;
            region(y-1,x) = true;
        end
    end
    if y<H && ~region(y+1,x)
        if abs(sig(y+1,x) - mu) <= tol
            tail = tail + 1;
            qy(tail) = y+1; qx(tail) = x;
            region(y+1,x) = true;
        end
    end
    if x>1 && ~region(y,x-1)
        if abs(sig(y,x-1) - mu) <= tol
            tail = tail + 1;
            qy(tail) = y; qx(tail) = x-1;
            region(y,x-1) = true;
        end
    end
    if x<W && ~region(y,x+1)
        if abs(sig(y,x+1) - mu) <= tol
            tail = tail + 1;
            qy(tail) = y; qx(tail) = x+1;
            region(y,x+1) = true;
        end
    end
end

end
