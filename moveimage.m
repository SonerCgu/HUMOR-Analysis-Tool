% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Internal class, Moves the image placed in an axes object
% PATCH:
%   + setImageData() for RGB refresh
%   + resetTransform() for apply()
%
classdef moveimage < handle

   properties
        a         % original image data (RGB ok)
        at        % moved image data
        T0        % affine transformation
   end

   properties(Access=protected )
        himage
        figure
        flagmove
        axes
        v0
        v1
        T1
        ref
        alfa
        dv
   end

    methods
        function M=moveimage(axesHandle)
            M.himage = searchImageInChildren(axesHandle);
            M.figure = ancestor(axesHandle,'figure');
            M.axes   = axesHandle;

            M.a  = M.himage.CData;
            M.at = M.himage.CData;

            M.ref = imref2d([size(M.a,1) size(M.a,2)]);

            M.T0=eye(3);
            M.T1=eye(3);
            M.v0=zeros(1,2);
            M.v1=zeros(1,2);
            M.dv=zeros(1,2);
            M.alfa=0;
            M.flagmove=0;

            set(M.himage,'ButtonDownFcn',{@startrotation, M});
        end

        function refresh(M)
            M.himage.CData = M.at;
        end

        % NEW: update base image for later dragging
        function setImageData(M,newCData)
            M.a  = newCData;
            M.at = newCData;
            M.himage.CData = newCData;
            M.ref = imref2d([size(newCData,1) size(newCData,2)]);
        end

        % NEW: reset after apply()
        function resetTransform(M)
            M.T0 = eye(3);
            M.T1 = eye(3);
            M.v0=zeros(1,2);
            M.v1=zeros(1,2);
            M.dv=zeros(1,2);
            M.alfa=0;
            M.flagmove=0;
            M.at = M.a;
            M.refresh();
        end
    end
end

function startrotation(~,~, M)
set (M.figure, 'WindowButtonUpFcn',    {@mouseUp,     M});
set (M.figure, 'WindowButtonDownFcn',  {@mouseDown,   M});
set (M.figure, 'WindowButtonMotionFcn',{@mouseMove,   M});
set (M.figure,'Pointer','hand');
end

function mouseUp (~,~,M)
M.flagmove=0;
M.T0=M.T0*M.T1;
M.T1=eye(3);
M.v0=zeros(1,2);
M.v1=zeros(1,2);
M.dv=zeros(1,2);
M.alfa=0;
end

function mouseDown (~,~, M)
C0 = get (M.axes, 'CurrentPoint');
if isPointerInAxis(M.axes)
   M.v0=C0(1,1:2);
   M.flagmove=1;
else
  set (M.figure, 'WindowButtonUpFcn',    '');
  set (M.figure, 'WindowButtonDownFcn',  '');
  set (M.figure, 'WindowButtonMotionFcn','');
  set (M.figure,'Pointer','arrow');
end
end

function mouseMove (~,~, M)

if(isPointerInAxis(M.axes))
    set (M.figure,'Pointer','hand');
else
    set (M.figure, 'WindowButtonUpFcn',    '');
    set (M.figure, 'WindowButtonDownFcn',  '');
    set (M.figure, 'WindowButtonMotionFcn','');
    set(M.figure,'Pointer','arrow');
end

if  M.flagmove==1
    C0 = get (M.axes, 'CurrentPoint');
    M.v1=C0(1,1:2);
    M.dv=M.v1-M.v0;

    tmp0=M.v0(1)+1i*M.v0(2);
    tmp1=M.v1(1)-1i*M.v1(2);
    M.alfa=angle(tmp0*tmp1)*180/pi;

    if strcmp( M.figure.SelectionType,'alt')
        M.T1=rotz(M.alfa);
    else
        M.T1=eye(3);
        M.T1(3,1:2)=M.dv;
    end

    m=affine2d(M.T0*M.T1);
    M.at=imwarp(M.a,m,'OutputView',M.ref);
    M.refresh();
end
end

function h=searchImageInChildren(ax)
isit=0;
for i=1:length(ax.Children)
     if isa(ax.Children(i),'matlab.graphics.primitive.Image')
        isit=i;
     end
end
if isit==0
   error('no image in children of this axis');
end
h=ax.Children(isit);
end

function a=isPointerInAxis(ax)
C0 = get (ax, 'CurrentPoint');
a= C0(1,1)>ax.XLim(1) && C0(1,1)<ax.XLim(2) && C0(1,2)>ax.YLim(1) && C0(1,2)<ax.YLim(2);
end
