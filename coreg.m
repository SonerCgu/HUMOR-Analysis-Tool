function Transf = coreg(studio, anatomyInput)

% =========================================================
% fUSI Studio – Atlas Coregistration
% Clean, robust, no Direction dependency
% =========================================================

if ~studio.isLoaded
    error('Load dataset first.');
end

if nargin < 2 || isempty(anatomyInput)
    anatomyInput = mean(studio.data.I,4);
end

fprintf('\n--- fUSI Atlas Coregistration ---\n');

%% =========================================================
% LOAD ATLAS
%% =========================================================

atlasFile = 'allen_brain_atlas.mat';
if ~exist(atlasFile,'file')
    error('Allen atlas file not found.');
end

load(atlasFile,'atlas');

if ~isfield(atlas,'Histology')
    error('Atlas struct must contain atlas.Histology');
end

atlasVol = double(atlas.Histology);

if ~isfield(atlas,'VoxelSize')
    error('Atlas must contain VoxelSize field.');
end

%% =========================================================
% PREPARE ANATOMY
%% =========================================================

anatomyVol = double(anatomyInput);

% Ensure 3D
if ndims(anatomyVol) == 2
    anatomyVol = repmat(anatomyVol,1,1,1);
end

%% =========================================================
% GET VOXEL SIZE SAFELY
%% =========================================================

if isfield(studio.data,'VoxelSize')
    voxelSize = studio.data.VoxelSize;

elseif isfield(studio.meta,'VoxelSize')
    voxelSize = studio.meta.VoxelSize;

elseif isfield(studio.meta,'rawMetadata') && ...
       isfield(studio.meta.rawMetadata,'voxelSize')

    voxelSize = studio.meta.rawMetadata.voxelSize;

else
    warning('Voxel size not found. Assuming isotropic 100 µm.');
    voxelSize = [0.1 0.1 0.1]; % mm
end

if numel(voxelSize) == 2
    voxelSize = [voxelSize 1];
end

%% =========================================================
% RESAMPLE ANATOMY TO ATLAS RESOLUTION
%% =========================================================

anatomyVol = interpolateToAtlas(anatomyVol, voxelSize, atlas.VoxelSize);

%% =========================================================
% INTERACTIVE AFFINE REGISTRATION
%% =========================================================

Transf = interactiveAffine(atlasVol, anatomyVol, atlas.VoxelSize);

%% =========================================================
% SAVE
%% =========================================================

atlasFolder = fullfile(studio.exportPath,'Atlas');
if ~exist(atlasFolder,'dir')
    mkdir(atlasFolder);
end

save(fullfile(atlasFolder,'atlas_affine.mat'),'Transf');

fprintf('Affine saved successfully.\n');

end
function outVol = interpolateToAtlas(vol, voxelSize, atlasVoxelSize)

vol = double(vol);

dz = voxelSize(1);
dx = voxelSize(2);
dy = voxelSize(3);

dzint = atlasVoxelSize(1);
dxint = atlasVoxelSize(2);
dyint = atlasVoxelSize(3);

[nz,nx,ny] = size(vol);

n1x = round((nx-1)*dx/dxint)+1;
n1y = round((ny-1)*dy/dyint)+1;
n1z = round((nz-1)*dz/dzint)+1;

[Xq,Yq,Zq] = meshgrid( ...
    (0:n1x-1)*dxint/dx+1,...
    (0:n1z-1)*dzint/dz+1,...
    (0:n1y-1)*dyint/dy+1);

outVol = interp3(vol,Xq,Yq,Zq,'linear',0);

end
function Transf = interactiveAffine(atlasVol, scanVol, atlasVoxelSize)

atlasVol = double(atlasVol);
scanVol  = double(scanVol);

[~,~,nz] = size(atlasVol);

T = eye(4);
scale = ones(3,1);

fig = figure('Name','Atlas Coregistration',...
    'Color','k','Position',[200 100 1200 800]);

ax = axes(fig);
slice = round(nz/2);

updateDisplay();

set(fig,'WindowScrollWheelFcn',@scrollSlice);
set(fig,'WindowButtonDownFcn',@mouseTranslate);
set(fig,'WindowKeyPressFcn',@keyRotate);

uiwait(msgbox({'Adjust alignment using:', ...
               'Mouse click = translate', ...
               'Left/Right arrows = rotate', ...
               'Up/Down arrows = scale', ...
               'Scroll wheel = change slice', ...
               'Close window when done.'}));

Transf.M = T;
Transf.VoxelSize = atlasVoxelSize;
Transf.size = size(atlasVol);
Transf.scale = scale;

if isvalid(fig)
    close(fig);
end

    function updateDisplay()
        imshow(atlasVol(:,:,slice),[],'Parent',ax);
        hold(ax,'on');
        overlay = imwarp(scanVol,affine3d(T));
        h = imshow(overlay(:,:,slice),[],'Parent',ax);
        set(h,'AlphaData',0.4);
        hold(ax,'off');
    end

    function scrollSlice(~,event)
        slice = max(1,min(nz,slice + event.VerticalScrollCount));
        updateDisplay();
    end

    function mouseTranslate(~,~)
        cp = get(ax,'CurrentPoint');
        dx = cp(1,1)/100;
        dy = cp(1,2)/100;
        T(4,1:2) = T(4,1:2) + [dx dy];
        updateDisplay();
    end

    function keyRotate(~,event)
        switch event.Key
            case 'leftarrow'
                T = T * makehgtform('zrotate',deg2rad(-1));
            case 'rightarrow'
                T = T * makehgtform('zrotate',deg2rad(1));
            case 'uparrow'
                scale = scale * 1.01;
                T(1:3,1:3) = T(1:3,1:3)*1.01;
            case 'downarrow'
                scale = scale * 0.99;
                T(1:3,1:3) = T(1:3,1:3)*0.99;
        end
        updateDisplay();
    end

end
