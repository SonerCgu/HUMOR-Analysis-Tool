
function studio_mkdir(p)
if exist(p,'dir') ~= 7
    mkdir(p);
end
end