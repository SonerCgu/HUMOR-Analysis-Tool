function BW = autoThreshold(sig, mode, pKeep)
% autoThreshold
% ------------------------------------------------------------
% Automatic vessel-like thresholding for fUSI masks.
%
% INPUT
%   sig   : 2D signal image (PSC frame)
%   mode  : 2 = Method A (robust MAD)
%           3 = Method B (percentile-based)
%   pKeep : percentile slider value (used for Method B)
%
% OUTPUT
%   BW    : logical mask
%
% LOGIC:
%   IDENTICAL to fusi_video_soner10
%   Always permissive; guaranteed fallback.
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

v = sig(:);
v = v(~isnan(v) & ~isinf(v));

if isempty(v)
    BW = false(size(sig));
    return;
end

switch mode

    case 2
        % ---------------- METHOD A ----------------
        % Robust, permissive MAD-based threshold
        med  = median(v);
        madv = mad(v,1);
        thr  = med + 0.3 * madv;

    case 3
        % ---------------- METHOD B ----------------
        % Percentile-based, heavily softened
        pSoft = max(40, pKeep - 40);
        thr   = prctile(v, pSoft);

    otherwise
        BW = false(size(sig));
        return;
end

BW = sig > thr;

% Fallback if mask too small
if nnz(BW) < 20
    thr2 = prctile(v, 30);
    BW = sig > thr2;
end

end
