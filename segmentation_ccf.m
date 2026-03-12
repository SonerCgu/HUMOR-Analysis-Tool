% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Interpolates and registers all images of the functional scan.
% Registered images are segmented based on anatomical regions of the Allen Mouse Common Coordinate Framework
% All pixels from the same region are added.
%
% segmented=segmentation_ccf(atlas, scanfus, Transf)
%   atlas, theAllen Mouse Common Coordinate Framework provided in the allen_brain_atlas.mat file,
%   scanfus, fus-structure of fusvolume type,
%   Transf, the transformation matrix, obtained with the registration function 
%   segmented, a structure with 2 fields containing temporal traces for either the left or the right hemisphere. 
%       Each field is a 2D matrix of 509*nt. The 509 lines are all brain regions from the Allen Mouse Common Coordinate Framework and nt the number of time points. 
%
% Example: 'example05_segmentation.m'
%%
function segmented=segmentation_ccf(atlas,scanfus,Transf)     

[nz,nx,ny,nt]=size(scanfus.Data);        

maxReg=max(abs(atlas.Regions(:)));
segmented.Left=zeros(maxReg,nt);
segmented.Right=zeros(maxReg,nt);

% the left part of the atlas is mark with negative values.
RegionsSim=atlas.Regions;
nt2=round(size(RegionsSim,3)/2);
RegionsSim(:,:,1:nt2)=-RegionsSim(:,:,1:nt2);

% normalization (optional can be commented)
for iz=1:nz
    for ix=1:nx
        for iy=1:ny
            s=squeeze(scanfus.Data(iz,ix,iy,:));
            s=s./mean(s);
            scanfus.Data(iz,ix,iy,:)=s;
        end
    end
end

% main loop 
for it=1:nt
    if mod(it,10)==1, fprintf(' segmentation time %d...\n',it); end 
    
    % build a temporary fus-structure with the it volume
    tmp.Data=squeeze(scanfus.Data(:,:,:,it));
    tmp.VoxelSize=scanfus.VoxelSize;
 
    tmpReg=register_data(atlas,tmp,Transf); % register the volume
   
    % average the signal in each region of the atlas.
    [pl,pr]=projectorRL(RegionsSim,tmpReg,maxReg);
    segmented.Left(:,it)=pl;
    segmented.Right(:,it)=pr;
end
end


%% auxiliar function
% add all points of the same atlas structure
function [PL,PR]=projectorRL(A,D,STRUCMAX)
PL=zeros(STRUCMAX,1,'single');
PR=zeros(STRUCMAX,1,'single');
ndat=numel(D);
for i=1:ndat
    tmp=A(i);
    if tmp>0
        PL(tmp)=PL(tmp)+D(i);
    else
        tmp=-tmp;
        PR(tmp)=PR(tmp)+D(i);
    end
end
end


