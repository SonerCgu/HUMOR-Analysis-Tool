% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020

%% This section allows, with the GUI, the registration of the anatomical scan to the Allen Mouse Common Coordinate Framework
% Note: The GUI fits better with large screen.
load('allen_brain_atlas.mat','atlas'); % loads the Allen Mouse CCF (atlas) 
load('scan_anatomy.mat','anatomic');   % loads the anatomical scan (scananat)

registration_ccf(atlas,anatomic); 
% The affine transformation is saved in the file 'Transformation.mat'

%% Adjustment of the registration between Anatomical Scan & Atlas using a preexistent transformation matrix
% One can use the previous transformation to start the process from the last version of the transformation
% Uncomment and run the next two lines 

% load('Transformation.mat');         % loads the previous transformation matrix file
% registration_ccf(atlas,anatomic,Transf);
% The affine transformation is saved in the file  'Transformation.mat'

