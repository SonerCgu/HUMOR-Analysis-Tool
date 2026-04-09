function proc = computeGabrielSignalChange(Ic, temporalWin)
% computeGabrielSignalChange
% ------------------------------------------------------------
% Gabriel-style signal change computation
%
% Supports:
%   3D input: [Y X T]
%   4D input: [Y X Z T]   (step motor / multi-slice)
%
% OUTPUT
%   proc.PSC    : percent signal change
%   proc.bg     : background anatomy
%   proc.nVols
% ------------------------------------------------------------

Ic = single(Ic);

nd = ndims(Ic);
if nd ~= 3 && nd ~= 4
    error('Ic must be 3D [Y X T] or 4D [Y X Z T].');
end

nVols = size(Ic, nd);

% ---- Fixed baseline (first 10 volumes) ----
nBase = min(10, nVols);

if nd == 3
    I0 = median(Ic(:,:,1:nBase),3);
else
    I0 = median(Ic(:,:,:,1:nBase),4);
end

I0(I0 <= 0 | ~isfinite(I0)) = eps;

% ---- Sliding window signal change ----
w = max(1, min(temporalWin, nVols));
PSC = zeros(size(Ic), 'single');

for k = 1:nVols
    k0 = k;
    k1 = min(nVols, k + w - 1);

    if nd == 3
        Ik = median(Ic(:,:,k0:k1),3);
        PSC(:,:,k) = 100 * (Ik - I0) ./ I0;
    else
        Ik = median(Ic(:,:,:,k0:k1),4);
        PSC(:,:,:,k) = 100 * (Ik - I0) ./ I0;
    end
end

% ---- Background ----
if nd == 3
    bg = median(Ic,3);
else
    bg = median(Ic,4);
end

m = max(bg(:));
if m > 0 && isfinite(m)
    bg = bg / m;
else
    bg = zeros(size(bg), 'like', bg);
end

% ---- Output ----
proc = struct();
proc.PSC   = PSC;
proc.bg    = bg;
proc.nVols = nVols;

if nd == 4
    proc.nSlices = size(Ic,3);
end

end