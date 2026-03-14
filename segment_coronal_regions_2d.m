function segmented = segment_coronal_regions_2d(scan2D, atlasRegionLabelsLR2D, atlasInfoRegions)
% segment_coronal_regions_2d.m
%
% Region-wise segmentation for 2D registered coronal data.
%
% Inputs
%   scan2D               : HxW or HxWxT numeric array
%   atlasRegionLabelsLR2D: signed region labels
%                          negative = left hemisphere
%                          positive = right hemisphere
%   atlasInfoRegions     : atlas.infoRegions struct
%
% Output
%   segmented.Left       : [nRegions x T]
%   segmented.Right      : [nRegions x T]
%   segmented.All        : [nRegions x T]
%   segmented.ids
%   segmented.acr
%   segmented.name
%   segmented.pixelCountLeft
%   segmented.pixelCountRight
%
% ASCII only
% MATLAB 2017b compatible

if nargin < 3
    atlasInfoRegions = [];
end

if ndims(scan2D) == 2
    scan2D = reshape(scan2D, size(scan2D,1), size(scan2D,2), 1);
end

if ndims(scan2D) ~= 3
    error('scan2D must be HxW or HxWxT.');
end

labels = round(double(atlasRegionLabelsLR2D));
if size(scan2D,1) ~= size(labels,1) || size(scan2D,2) ~= size(labels,2)
    error('scan2D size does not match atlasRegionLabelsLR2D.');
end

ids = unique(abs(labels(:)));
ids(ids == 0) = [];

T = size(scan2D,3);
nR = numel(ids);

segmented = struct();
segmented.Left  = zeros(nR, T, 'single');
segmented.Right = zeros(nR, T, 'single');
segmented.All   = zeros(nR, T, 'single');

segmented.ids = ids(:);
segmented.acr = cell(nR,1);
segmented.name = cell(nR,1);
segmented.pixelCountLeft = zeros(nR,1);
segmented.pixelCountRight = zeros(nR,1);

for ir = 1:nR
    rid = ids(ir);

    maskL = (labels == -rid);
    maskR = (labels ==  rid);
    maskA = maskL | maskR;

    segmented.pixelCountLeft(ir)  = nnz(maskL);
    segmented.pixelCountRight(ir) = nnz(maskR);

    if ~isempty(atlasInfoRegions)
        if isfield(atlasInfoRegions,'acr') && rid <= numel(atlasInfoRegions.acr)
            segmented.acr{ir} = atlasInfoRegions.acr{rid};
        else
            segmented.acr{ir} = '';
        end

        if isfield(atlasInfoRegions,'name') && rid <= numel(atlasInfoRegions.name)
            segmented.name{ir} = atlasInfoRegions.name{rid};
        else
            segmented.name{ir} = '';
        end
    else
        segmented.acr{ir} = '';
        segmented.name{ir} = '';
    end

    for it = 1:T
        frame = double(scan2D(:,:,it));

        if any(maskL(:))
            segmented.Left(ir,it) = single(mean(frame(maskL)));
        end
        if any(maskR(:))
            segmented.Right(ir,it) = single(mean(frame(maskR)));
        end
        if any(maskA(:))
            segmented.All(ir,it) = single(mean(frame(maskA)));
        end
    end
end
end