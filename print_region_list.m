% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Generates list of brain regions
% 3 files with the information of the file list in sorted 
% alphabetically by region number, by volume.
%
% print_region_list(atlas, fileRegions)
% print_region_list(atlas)
%   atlas, the Allen Mouse Brain Atlas provided in the atlas.mat file,
%   fileRegions, sting with the name of a text file listing the selected regions.
%
%   3 text files with the same names as "list_selected_brain_regions", extensions _number.txt, 
%   _alpha.txt and _volume.txt, containing the regions sorted alphabetically, by the number of region or the volume of the region. 
%   If the argument fileRegions is absent, 3 files named atlas_alpha.txt,
%   atlas_number.txt and atlas_volume.txt are generated with the list of all the atlas regions.
%
% Example:  example08_print_region_list.m
%%
function print_region_list(atlas,namefile)

if nargin==1
sa=atlas.infoRegions;
namefile='atlas';
else
sa=readFileList(namefile,atlas.infoRegions);
end

[~,name,~]=fileparts(namefile);

[acrs,idx]=sort(sa.acr);
names=sa.name(idx);
vols=sa.vol(idx);


fid=fopen([name '_alpha.txt'], 'w+t');
for i=1:length(idx)
    ac='               ';
    ac(1:length(acrs{i}))=acrs{i};
    fprintf(fid,'  %s %4d %6.2f %s\n',ac,idx(i),vols(i),names{i});
end
fclose(fid);



[vols,idx]=sort(sa.vol,'descend');
names=sa.name(idx);
acrs=sa.acr(idx);

fid=fopen([name '_volume.txt'], 'w+t');
for i=1:length(idx)
    ac='               ';
    ac(1:length(acrs{i}))=acrs{i};
    fprintf(fid,'  %s %4d %6.2f %s\n',ac,idx(i),vols(i),names{i});
end
fclose(fid);

% list index
acrs=sa.acr;
names=sa.name;
vols=sa.vol;
fid=fopen([name '_number.txt'], 'w+t');
for i=1:length(vols)
    ac='               ';
    ac(1:length(acrs{i}))=acrs{i};
    fprintf(fid,'  %s %4d %6.2f %s\n',ac,i,vols(i),names{i});
end
fclose(fid);

end
