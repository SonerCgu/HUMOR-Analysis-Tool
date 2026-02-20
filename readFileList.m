% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Auxiliary function
% Reads a list of brain regions and generates a structure of regions
% Internal use in 'select_brain_regions.m' and 'print_regions_list.m'
%%
function D=readFileList(filename,sa)
fid=fopen(filename,'r+t');
s=char(fread(fid,'char'))';
fclose(fid);

D=tokenLines(s);
D=eliminateComments(D);
D=compactRegions(D,sa);
end

%% divide the text file in tokens 
function D=tokenLines(txt)
txt(end+1)=char(10);
txt=regexprep(txt,'//',' // ');     %introduce spaces between comment idn
[tokL,nL]=regexp(txt,'\n','split');
[tok,nt]=regexp(txt,'\S+','match');
lines=zeros(length(tok),1);
for i=1:length(tok)
    lines(i)=find((nL-nt(i))>0,1,'first');
end
D.tok=tok;
D.lines=lines;
end

%% is a token is // eliminate the following tokens of the line
function D=eliminateComments(D0)
D=D0;
tok=D.tok;
n=length(tok);
c=ones(n,1);
ElimLine=-1;
for i=1:n
    token=tok{i};
    if   strcmp(token, '//')
        ElimLine=D.lines(i);
    end
    if (D.lines(i)==ElimLine)
        c(i)=0;
    end
end
ind=find(c==0);
D.tok(ind)=[];
D.lines(ind)=[];
end

%%
function D=compactRegions(D0,sa)

LineToProcess=0;
Region=0;
subregion=0;

for  itok=1:length(D0.tok)
    if D0.lines(itok)~=LineToProcess
        
        Region=Region+1;
        subregion=0;
        LineToProcess=D0.lines(itok);
        tmp=D0.tok{itok};
        
        if tmp(1)=='%'
            acr{Region}=tmp(2:end);
            vol(Region)=0;
            name{Region}=sa.name{numberInAtlas};
        else
            acr{Region}=tmp;
            subregion=subregion+1;
            numberInAtlas=acr2num(sa,D0.tok{itok});
            parts{Region}(subregion)=numberInAtlas;
            vol(Region)=sa.vol(numberInAtlas);
            name{Region}=sa.name{numberInAtlas};
        end
    else
        subregion=subregion+1;
        numberInAtlas=acr2num(sa,D0.tok{itok});
        parts{Region}(subregion)=acr2num(sa,D0.tok{itok});
        vol(Region)=vol(Region)+sa.vol(acr2num(sa,D0.tok{itok}));
        name{Region}=sa.name{numberInAtlas};
    end
    
    
end

D.acr=acr;
D.parts=parts;
D.vol=vol;
D.name=name;
end

%% get the  region number from the acronim.
function nr=acr2num(sa,acr)

nreg=length(sa.acr);
find=0;
i=0;
while( find==0 && i<nreg)
    i=i+1;
    if strcmp(sa.acr(i),acr)==1
        find=1;
    end
end

if find==0
    error([acr ' not found']);
else
    nr=i;
end
end