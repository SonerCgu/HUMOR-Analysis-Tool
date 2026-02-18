function proc = computeGabrielSignalChange(Ic, temporalWin)
% computeGabrielSignalChange
% ------------------------------------------------------------
% Gabriel-style signal change computation
% IDENTICAL logic to original reference script
%
% INPUT
%   Ic          : [nz x nx x nVols] (output of gabriel_preprocess)
%   temporalWin : sliding window length (volumes), e.g. 10
%
% OUTPUT
%   proc.PSC    : fractional signal change (NOT percent)
%   proc.bg     : background anatomy
%   proc.nVols
% ------------------------------------------------------------

Ic = single(Ic);
[nz,nx,nVols] = size(Ic);

% ---- Fixed baseline (first 10 volumes) ----
nBase = min(10, nVols);
I0 = mean(Ic(:,:,1:nBase),3);
I0(I0 <= 0 | ~isfinite(I0)) = eps;

% ---- Sliding window signal change ----
w = max(1, min(temporalWin, nVols));
PSC = zeros(nz,nx,nVols,'single');

for k = 1:nVols
    k0 = k;
    k1 = min(nVols, k + w - 1);
    Ik = mean(Ic(:,:,k0:k1),3);
    PSC(:,:,k) = (Ik - I0) ./ I0;   % FRACTIONAL change
end

% ---- Background ----
bg = mean(Ic,3);
m = max(bg(:));
if m > 0 && isfinite(m)
    bg = bg / m;
else
    bg = zeros(size(bg));
end

% ---- Output ----
proc = struct();
proc.PSC   = PSC;
proc.bg    = bg;
proc.nVols = nVols;

end
