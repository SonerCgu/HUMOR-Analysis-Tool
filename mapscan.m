% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020

%% auxiliary class to manage a 3D volume
classdef mapscan < handle
    
    properties
        D
        nx
        ny
        nz
        x0
        y0
        z0
        cmap
        caxis
        method
    end
    
    methods
        function M=mapscan(data,cmap,method)
            M.D=data;
            [M.nx,M.ny,M.nz]=size(data);
            M.x0=round(M.nx/2);
            M.y0=round(M.ny/2);
            M.z0=round(M.nz/2);
            M.cmap= gray(128);
            M.method='auto';
            if nargin>1, M.cmap=cmap;  end
            if nargin>2
                M.method=method;
                if strcmp(method,'fix')
                    M.caxis=double([min(data(:)),max(data(:))]);
                end
            end
        end
        
        function [ax,ay,az]=cuts(M)
           if M.x0>0 && M.x0<=M.nx
                ax=rgbfunc(double(squeeze(M.D(M.x0,:,:))),M);
           else
               ax=zeros(M.ny,M.nz,3);
           end
            
           if M.y0>0 && M.y0<=M.ny
                ay=rgbfunc(double(squeeze(M.D(:,M.y0,:))),M);
           else
               ay=zeros(M.nx,M.nz,3);
           end
            
           if M.z0>0 && M.z0<=M.nz
                az=rgbfunc(double(squeeze(M.D(:,:,M.z0))),M);
           else
               az=zeros(M.nx,M.ny,3);
           end
            
        end
        
        function setData(M,data)
            M.D=data;
            M.nx=size(data,1);
            M.ny=size(data,2);
            M.nz=size(data,3);
        end
        
    end
    
    
    events
        eventRefresh
    end
    
end



function b=rgbfunc(a,M)
[nx,ny]=size(a);
aa=a(:);
method=M.method;
cmap=M.cmap;

if strcmp(method,'auto')
    norm=max(aa)-min(aa);
    aa=(aa-min(aa))/norm;
    aa=uint16(round(aa(:)*(length(cmap)-1)+1));
    aa(aa==0)=1;
    b=cmap(aa,:);
    b=reshape(b,nx,ny,3);
elseif strcmp(method,'fix')
    aa=(aa-M.caxis(1))/(M.caxis(2)-M.caxis(1));
    aa=uint16(round(aa(:)*(length(cmap)-1)+1));
    aa(aa<1)=1;
    aa(aa>length(cmap))=length(cmap);
    b=cmap(aa,:);
    b=reshape(b,nx,ny,3);
elseif strcmp(method,'index')
    aa(aa==0)=1;
    b=cmap(abs(aa),:);
    b=reshape(b,nx,ny,3);
else
    error('mapscan unknown rgb method')
end

end

