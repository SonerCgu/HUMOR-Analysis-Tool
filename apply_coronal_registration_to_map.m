function [mapReg, atlasRGB, Reg2D, coverageMask] = apply_coronal_registration_to_map(mapData, regInput, atlasInput)
% apply_coronal_registration_to_map.m
%
% Apply saved 2D coronal registration to a 2D map or YxXxT data
%
% Inputs:
%   mapData   : 2D matrix or 3D YxXxT matrix
%   regInput  : Reg2D struct OR path to CoronalRegistration2D.mat
%   atlasInput: optional atlas struct OR path to allen_brain_atlas.mat
%
% Outputs:
%   mapReg       : registered map in atlas 2D coronal slice space
%   atlasRGB     : atlas underlay RGB for the chosen slice/mode
%   Reg2D        : loaded registration struct
%   coverageMask : warped support mask
%
% ASCII only
% MATLAB 2017b compatible

%% ---------------------------------------------------------
% 1) LOAD Reg2D
%% ---------------------------------------------------------
if ischar(regInput) || isstring(regInput)
    tmp = load(char(regInput),'Reg2D');
    if ~isfield(tmp,'Reg2D')
        error('Reg2D variable not found in registration file.');
    end
    Reg2D = tmp.Reg2D;
elseif isstruct(regInput)
    Reg2D = regInput;
else
    error('regInput must be a Reg2D struct or path to Reg2D file.');
end

if ~isfield(Reg2D,'A') || ~isfield(Reg2D,'outputSize')
    error('Invalid Reg2D structure.');
end

%% ---------------------------------------------------------
% 2) LOAD ATLAS
%% ---------------------------------------------------------
if nargin < 3 || isempty(atlasInput)
    atlasFile = 'allen_brain_atlas.mat';
    atlasPath = which(atlasFile);
    if isempty(atlasPath)
        here = fileparts(mfilename('fullpath'));
        atlasPath = fullfile(here, atlasFile);
    end
    if ~exist(atlasPath,'file')
        error('allen_brain_atlas.mat not found.');
    end
    tmpA = load(atlasPath,'atlas');
    atlas = tmpA.atlas;
elseif ischar(atlasInput) || isstring(atlasInput)
    tmpA = load(char(atlasInput),'atlas');
    if ~isfield(tmpA,'atlas')
        error('atlas variable not found in atlas file.');
    end
    atlas = tmpA.atlas;
elseif isstruct(atlasInput)
    atlas = atlasInput;
else
    error('atlasInput must be atlas struct or path.');
end

atlasRGB = getAtlasSliceRGB(atlas, Reg2D.atlasMode, Reg2D.atlasSliceIndex);

%% ---------------------------------------------------------
% 3) APPLY 2D WARP
%% ---------------------------------------------------------
mapData = double(mapData);
mapData(~isfinite(mapData)) = 0;

A = affine2d(Reg2D.A);
Rout = imref2d(Reg2D.outputSize);

if ndims(mapData) == 2
    mapReg = imwarp(mapData, A, 'OutputView', Rout);
    coverageMask = imwarp(ones(size(mapData)), A, 'OutputView', Rout) > 0.5;

elseif ndims(mapData) == 3
    nT = size(mapData,3);
    mapReg = zeros(Reg2D.outputSize(1), Reg2D.outputSize(2), nT);
    coverageMask = [];

    for t = 1:nT
        frame = mapData(:,:,t);
        mapReg(:,:,t) = imwarp(frame, A, 'OutputView', Rout);
    end

    coverageMask = imwarp(ones(size(mapData(:,:,1))), A, 'OutputView', Rout) > 0.5;

else
    error('mapData must be 2D or 3D YxXxT.');
end

end


%% =======================================================================
% Helpers
%% =======================================================================
function RGB = getAtlasSliceRGB(atlas, modeName, sliceIdx)

sliceIdx = max(1, min(size(atlas.Vascular,1), round(sliceIdx)));

switch lower(modeName)
    case 'vascular'
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);

    case 'histology'
        A = squeeze(atlas.Histology(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);

    case 'regions'
        L = squeeze(atlas.Regions(sliceIdx,:,:));
        RGB = labelToRGB(L, atlas.infoRegions.rgb);

    otherwise
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);
end

end


function RGB = grayToRGB(A)
A = rescale01(double(A));
RGB = zeros(size(A,1), size(A,2), 3);
RGB(:,:,1) = A;
RGB(:,:,2) = A;
RGB(:,:,3) = A;
end


function RGB = labelToRGB(L, cmap)
L = round(double(L));
idx = abs(L);
idx(idx < 1) = 1;
idx(idx > size(cmap,1)) = 1;

rgbFlat = cmap(idx(:), :);
RGB = reshape(rgbFlat, [size(L,1) size(L,2) 3]);

zeroMask = (L == 0);
for c = 1:3
    tmp = RGB(:,:,c);
    tmp(zeroMask) = 0;
    RGB(:,:,c) = tmp;
end
end


function A = rescale01(A)
A = double(A);
A(~isfinite(A)) = 0;
mn = min(A(:));
mx = max(A(:));
if mx > mn
    A = (A - mn) ./ (mx - mn);
else
    A = zeros(size(A));
end
end