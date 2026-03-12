function outFiles = save_atlas_underlays_from_reg2d(atlas, Reg2D, saveDir)
% save_atlas_underlays_from_reg2d
% Saves vascular/histology/regions atlas underlay MAT files for one Reg2D slice

if nargin < 3 || isempty(saveDir)
    saveDir = pwd;
end
if ~exist(saveDir,'dir')
    mkdir(saveDir);
end

if ~isfield(Reg2D,'atlasSliceIndex')
    error('Reg2D.atlasSliceIndex missing.');
end

sliceIdx = Reg2D.atlasSliceIndex;
modes = {'vascular','histology','regions'};

outFiles = struct();

for i = 1:numel(modes)
    modeName = modes{i};

    atlasUnderlay = getAtlasSliceNumericLocal(atlas, modeName, sliceIdx);
    atlasUnderlayRGB = getAtlasSliceRGBLocal(atlas, modeName, sliceIdx);
    brainImage = atlasUnderlay; %#ok<NASGU>
    atlasMode = modeName; %#ok<NASGU>

    outFile = fullfile(saveDir, sprintf('atlasUnderlay_%s_slice%03d.mat', lower(modeName), sliceIdx));
    save(outFile, 'atlasUnderlay', 'brainImage', 'atlasUnderlayRGB', 'atlasMode', 'Reg2D');

    outFiles.(modeName) = outFile;
end
end


function atlasSlice = getAtlasSliceNumericLocal(atlas, modeName, sliceIdx)

sliceIdx = max(1, min(size(atlas.Vascular,1), round(sliceIdx)));

switch lower(modeName)
    case 'vascular'
        atlasSlice = squeeze(atlas.Vascular(sliceIdx,:,:));
        atlasSlice = rescale01Local(double(atlasSlice));

    case 'histology'
        atlasSlice = squeeze(atlas.Histology(sliceIdx,:,:));
        atlasSlice = rescale01Local(double(atlasSlice));

    case 'regions'
        atlasSlice = double(squeeze(atlas.Regions(sliceIdx,:,:)));

    otherwise
        atlasSlice = squeeze(atlas.Vascular(sliceIdx,:,:));
        atlasSlice = rescale01Local(double(atlasSlice));
end
end


function RGB = getAtlasSliceRGBLocal(atlas, modeName, sliceIdx)

sliceIdx = max(1, min(size(atlas.Vascular,1), round(sliceIdx)));

switch lower(modeName)
    case 'vascular'
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01Local(double(A));
        RGB = grayToRGBLocal(A);

    case 'histology'
        A = squeeze(atlas.Histology(sliceIdx,:,:));
        A = rescale01Local(double(A));
        RGB = grayToRGBLocal(A);

    case 'regions'
        L = squeeze(atlas.Regions(sliceIdx,:,:));
        RGB = labelToRGBLocal(L, atlas.infoRegions.rgb);

    otherwise
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01Local(double(A));
        RGB = grayToRGBLocal(A);
end
end


function RGB = grayToRGBLocal(A)
A = rescale01Local(double(A));
RGB = zeros(size(A,1), size(A,2), 3);
RGB(:,:,1) = A;
RGB(:,:,2) = A;
RGB(:,:,3) = A;
end


function RGB = labelToRGBLocal(L, cmap)
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


function A = rescale01Local(A)
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