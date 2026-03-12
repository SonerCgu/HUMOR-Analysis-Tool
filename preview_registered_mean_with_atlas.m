function [meanReg, atlasUnder] = preview_registered_mean_with_atlas(scanfus, atlas, Transf, atlasMode)

if nargin < 4 || isempty(atlasMode)
    atlasMode = 'vascular';
end

tmp = struct();
tmp.Data = mean(double(scanfus.Data),4);
tmp.VoxelSize = scanfus.VoxelSize;

meanReg = register_data(atlas, tmp, Transf);

switch lower(atlasMode)
    case 'vascular'
        atlasUnder = atlas.Vascular;
    case 'histology'
        atlasUnder = atlas.Histology;
    case 'regions'
        atlasUnder = atlas.Regions;
    otherwise
        atlasUnder = atlas.Vascular;
end

z = round(size(meanReg,3)/2);

figure('Color','k');
imagesc(atlasUnder(:,:,z));
axis image off;

if strcmpi(atlasMode,'regions')
    colormap(gca, atlas.infoRegions.rgb);
else
    colormap(gca, gray);
end

hold on;
h = imagesc(meanReg(:,:,z));
set(h,'AlphaData',0.45);

title(sprintf('Registered mean functional on atlas (%s), z = %d', atlasMode, z), 'Color','w');
end