% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Internal function 
% that interpolates the data of 'scan' to the same voxel size than the 'atlas'
% it also manipulates the order of the axis to fit with the atlas
%%
function scanInt=interpolate3D(atlas,scan)

dz=scan.VoxelSize(1);
dx=scan.VoxelSize(2);
dy=scan.VoxelSize(3);

dzint=atlas.VoxelSize(1);
dxint=atlas.VoxelSize(2);
dyint=atlas.VoxelSize(3);

[nz,nx,ny]=size(scan.Data);

n1x=round((nx-1)*dx/dxint)+1;
n1y=round((ny-1)*dy/dyint)+1;
n1z=round((nz-1)*dz/dzint)+1;

% warning!! X and Y are permuted in matlab meshgrid axis1=Y axis2=X axis3=Z
[Xq,Yq,Zq] = meshgrid( (0:n1x-1)*dxint/dx+1,(0:n1z-1)*dzint/dz+1 ,(0:n1y-1)*dyint/dy+1);
ai=interp3(scan.Data,Xq,Yq,Zq,'linear',0);

% permute and flip axes to have the same than the atlas
ai=flip(ai,3);
ai=flip(ai,2);
ai=permute(ai,[3,1,2]);

scanInt.Data=ai;
scanInt.VoxelSize=atlas.VoxelSize;
end
