% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% Internal class, Moves the image placed in an axes object
%
% PATCH (fUSI Studio):
%   + Robustly selects the intended image (prefers HitTest='on')
%   + Drag continues even if pointer leaves axes (better UX)
%   + setImageData() for RGB/scalar refresh
%   + resetTransform() for apply()
%
classdef moveimage < handle

   properties
        a         % original image data (RGB ok)
        at        % moved image data
        T0        % affine transformation (3x3)
   end

   properties(Access=protected)
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
        function M = moveimage(axesHandle, imageHandle)
            % moveimage(axesHandle)
            % moveimage(axesHandle, imageHandle)   % optional explicit image handle

            if nargin < 1 || isempty(axesHandle) || ~ishandle(axesHandle)
                error('moveimage: invalid axes handle.');
            end

            M.axes   = axesHandle;
            M.figure = ancestor(axesHandle,'figure');

            % Choose target image
            if nargin >= 2 && ~isempty(imageHandle) && ishandle(imageHandle)
                M.himage = imageHandle;
            else
                M.himage = searchImageInChildren(axesHandle);
            end

            % Cache base data
            M.a  = M.himage.CData;
            M.at = M.himage.CData;

            % Reference for warping (always 2D)
            M.ref = imref2d([size(M.a,1) size(M.a,2)]);

            M.T0 = eye(3);
            M.T1 = eye(3);
            M.v0 = zeros(1,2);
            M.v1 = zeros(1,2);
            M.dv = zeros(1,2);
            M.alfa = 0;
            M.flagmove = 0;

            % Make sure the image can be clicked
            try
                set(M.himage,'HitTest','on');
            catch
            end

            % Start interaction only when user clicks the image
            set(M.himage,'ButtonDownFcn',{@startrotation, M});
        end

       function refresh(M)
    if ishandle(M.himage)
        M.himage.CData = M.at;
        drawnow limitrate;   % <- makes movement visible during drag
    end
end


        % NEW: update base image for later dragging (RGB or scalar)
        function setImageData(M,newCData)
            if isempty(newCData)
                return;
            end
            M.a  = newCData;
            M.at = newCData;

            if ishandle(M.himage)
                M.himage.CData = newCData;
            end

            M.ref = imref2d([size(newCData,1) size(newCData,2)]);
        end

        % NEW: reset after apply()
        function resetTransform(M)
            M.T0 = eye(3);
            M.T1 = eye(3);
            M.v0 = zeros(1,2);
            M.v1 = zeros(1,2);
            M.dv = zeros(1,2);
            M.alfa = 0;
            M.flagmove = 0;
            M.at = M.a;
            M.refresh();
        end
    end
end

% ==========================================================
% Interaction callbacks (local functions)
% ==========================================================
function startrotation(~,~, M)
    % Attach figure-level callbacks for drag interaction
    set(M.figure, 'WindowButtonUpFcn',    {@mouseUp,     M});
    set(M.figure, 'WindowButtonDownFcn',  {@mouseDown,   M});
    set(M.figure, 'WindowButtonMotionFcn',{@mouseMove,   M});
    set(M.figure,'Pointer','hand');
end

function mouseUp (~,~,M)
    % Finish current gesture
    M.flagmove = 0;
    M.T0 = M.T0 * M.T1;
    M.T1 = eye(3);
    M.v0 = zeros(1,2);
    M.v1 = zeros(1,2);
    M.dv = zeros(1,2);
    M.alfa = 0;

    % Keep callbacks installed (so next click works immediately)
    % (Do NOT clear here; registration_ccf scroll now uses pointer position anyway.)
end

function mouseDown (~,~, M)
    % Start gesture if click is inside the axis
    C0 = get(M.axes, 'CurrentPoint');

    if isPointerInAxis(M.axes)
        M.v0 = C0(1,1:2);
        M.flagmove = 1;
        set(M.figure,'Pointer','hand');
    else
        % Click outside: stop interaction cleanly
        M.flagmove = 0;
        set(M.figure, 'WindowButtonUpFcn',    '');
        set(M.figure, 'WindowButtonDownFcn',  '');
        set(M.figure, 'WindowButtonMotionFcn','');
        set(M.figure,'Pointer','arrow');
    end
end

function mouseMove (~,~, M)

    % If currently dragging, allow motion even when cursor leaves axes
    % (prevents “it stops moving” feeling)
    if M.flagmove == 1
        C0 = get(M.axes, 'CurrentPoint');
        M.v1 = C0(1,1:2);
        M.dv = M.v1 - M.v0;

        % Rotation angle estimate (kept compatible with original behavior)
        tmp0 = M.v0(1) + 1i*M.v0(2);
        tmp1 = M.v1(1) - 1i*M.v1(2);
        M.alfa = angle(tmp0 * tmp1) * 180/pi;

        % Right click -> rotate, left click -> translate
        if strcmp(M.figure.SelectionType,'alt')
            M.T1 = rotz(M.alfa);
        else
            M.T1 = eye(3);
            M.T1(3,1:2) = M.dv;   % affine2d translation
        end

        m = affine2d(M.T0 * M.T1);

        % Warp (works for scalar + RGB)
        try
            M.at = imwarp(M.a, m, 'OutputView', M.ref);
        catch
            % In rare cases imwarp can fail for type issues; fall back to double
            M.at = imwarp(double(M.a), m, 'OutputView', M.ref);
        end
        M.refresh();
        return;
    end

    % Not dragging: just pointer feedback and auto-disarm if far away
    if isPointerInAxis(M.axes)
        set(M.figure,'Pointer','hand');
    else
        set(M.figure,'Pointer','arrow');
        % Don’t forcibly clear callbacks here unless you want strict behavior.
        % Keeping them is fine and avoids “locked” states elsewhere.
    end
end

% ==========================================================
% Helpers
% ==========================================================
function h = searchImageInChildren(ax)
    % Prefer topmost Image with HitTest 'on' (overlay), else any Image.
    kids = ax.Children;
    imgHits = [];
    imgAny  = [];

    for i = 1:numel(kids)
        if isa(kids(i),'matlab.graphics.primitive.Image')
            imgAny(end+1) = i; %#ok<AGROW>
            try
                ht = get(kids(i),'HitTest');
            catch
                ht = 'on';
            end
            if ischar(ht) && strcmpi(ht,'on')
                imgHits(end+1) = i; %#ok<AGROW>
            end
        end
    end

    if ~isempty(imgHits)
        % Children are in stacking order (topmost first) in HG2
        h = kids(imgHits(1));
        return;
    end

    if ~isempty(imgAny)
        h = kids(imgAny(1));
        return;
    end

    error('moveimage: no image found in children of this axis.');
end

function a = isPointerInAxis(ax)
    C0 = get(ax, 'CurrentPoint');
    a = C0(1,1) > ax.XLim(1) && C0(1,1) < ax.XLim(2) && ...
        C0(1,2) > ax.YLim(1) && C0(1,2) < ax.YLim(2);
end
