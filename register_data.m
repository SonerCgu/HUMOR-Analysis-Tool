% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Interpolates and registers a volumetric data with the Allen Mouse Common Coordinate Framework using an affine transformation
%
% xreg=register_data(atlas, x, Transf)
%   atlas, Allen Mouse Common Coordinate Framework provided in the allen_brain_atlas.mat file,
%   x, fus-structure of type volume,
%   Transf, transformation structure obtained with the registering function.
%   xreg, a fus-structure of type volume with the registered data.
%
% Example: example03_correlation.m
%%
function ras=register_data(atlas,x,Transf)
Dint=interpolate3D(atlas,x);
T=affine3d(Transf.M);
ref=imref3d(Transf.size);
ras=imwarp(Dint.Data,T,'OutputView',ref);
end




