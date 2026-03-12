function [J, coverageMask] = apply_reg2d_to_stack(I, Reg2D)
% apply_reg2d_to_stack
% Applies a saved 2D affine registration to a 2D image or 3D stack [Y X T]
%
% INPUT
%   I      : [Y X] or [Y X T]
%   Reg2D  : struct with fields .A and .outputSize
%
% OUTPUT
%   J            : warped image/stack in atlas space, single precision
%   coverageMask : logical mask of valid warped pixels

if nargin < 2 || isempty(Reg2D) || ~isstruct(Reg2D)
    error('apply_reg2d_to_stack: Reg2D must be a valid struct.');
end
if ~isfield(Reg2D,'A') || ~isfield(Reg2D,'outputSize')
    error('apply_reg2d_to_stack: Reg2D must contain fields A and outputSize.');
end

if ~(ndims(I)==2 || ndims(I)==3)
    error('apply_reg2d_to_stack: I must be 2D or 3D [Y X T].');
end

if islogical(I)
    I = single(I);
elseif ~isa(I,'single')
    I = single(I);
end

I(~isfinite(I)) = 0;

tform = affine2d(Reg2D.A);
ref2d = imref2d(Reg2D.outputSize);

if ndims(I) == 2
    J = imwarp(I, tform, 'OutputView', ref2d);
    coverageMask = imwarp(single(ones(size(I,1), size(I,2))), tform, 'OutputView', ref2d) > 0.5;
    return;
end

nT = size(I,3);
J = zeros(Reg2D.outputSize(1), Reg2D.outputSize(2), nT, 'single');

for t = 1:nT
    J(:,:,t) = imwarp(I(:,:,t), tform, 'OutputView', ref2d);
end

coverageMask = imwarp(single(ones(size(I,1), size(I,2))), tform, 'OutputView', ref2d) > 0.5;
end