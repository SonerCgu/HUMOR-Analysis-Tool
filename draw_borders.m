% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Draw the border of the brain regions in coronal, sagittal or transversal 
% planes in the current figure
%
% draw_borders(atlas, orientation, plane)
%   atlas, the Allen Mouse Brain Atlas provided in the 'allen_brain_atlas.mat' file,
%   orientation, a string containing 'coronal', 'sagittal' or 'transversal' indicating the orientation of the section.
%   plane, number of plane to display in the section.
%
% Example: example03_correlation.m
%%
function draw_borders(atlas,orientation,plane)

if    strcmp(orientation,'coronal')
   L=atlas.Lines.Cor{plane}; 
elseif  strcmp(orientation,'sagittal')
   L=atlas.Lines.Sag{plane}; 
elseif strcmp(orientation,'transversal')
   L=atlas.Lines.Tra{plane}; 
else
   error('cut must be: coronal sagittal or transversal')
end

hold on;
nb=length(L);
for ib=1:nb
    x=L{ib};
    plot(x(:,2),x(:,1),'k:');        % change the color of the line
end
hold off
end
