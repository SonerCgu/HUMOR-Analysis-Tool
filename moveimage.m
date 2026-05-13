classdef moveimage < handle
% =========================================================
% Robust image mover for HUMoR registration GUI
% MATLAB 2017b compatible, ASCII-safe
%
% Left mouse drag  = translate overlay
% Right mouse drag = rotate overlay
%
% Drag can start from the overlay image OR the axes underneath.
% This avoids cases where transparent alpha, atlas underlay, or axes
% hit-testing prevents the image ButtonDownFcn from firing.
% =========================================================

   properties
        a
        at
        T0
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

            if nargin < 1 || isempty(axesHandle) || ~ishandle(axesHandle)
                error('moveimage: invalid axes handle.');
            end

            M.axes = axesHandle;
            M.figure = ancestor(axesHandle,'figure');

            if nargin >= 2 && ~isempty(imageHandle) && ishandle(imageHandle)
                M.himage = imageHandle;
            else
                M.himage = M.searchImageInChildren(axesHandle);
            end

            M.a = M.himage.CData;
            M.at = M.himage.CData;
            M.ref = imref2d([size(M.a,1) size(M.a,2)]);

            M.T0 = eye(3);
            M.T1 = eye(3);
            M.v0 = zeros(1,2);
            M.v1 = zeros(1,2);
            M.dv = zeros(1,2);
            M.alfa = 0;
            M.flagmove = 0;

            M.armCallbacks();
        end

        function refresh(M)
            if isgraphics(M.himage)
                try
                    M.himage.CData = M.at;
                catch
                    set(M.himage,'CData',M.at);
                end
                M.armCallbacks();
                drawnow limitrate;
            end
        end

        function setImageData(M, newData)

            if isempty(newData)
                return;
            end

            M.a = newData;
            M.ref = imref2d([size(M.a,1) size(M.a,2)]);

            Tall = M.T0;
            if M.flagmove == 1
                Tall = M.T0 * M.T1;
            end

            if M.isIdentity3x3(Tall)
                M.at = M.a;
            else
                try
                    M.at = imwarp(M.a, affine2d(Tall), 'OutputView', M.ref);
                catch
                    M.at = imwarp(double(M.a), affine2d(Tall), 'OutputView', M.ref);
                end
            end

            M.refresh();
        end

        function resetTransform(M)
            M.T0 = eye(3);
            M.T1 = eye(3);
            M.v0 = zeros(1,2);
            M.v1 = zeros(1,2);
            M.dv = zeros(1,2);
            M.alfa = 0;
            M.flagmove = 0;
            M.at = M.a;
            M.clearMotionCallbacks();
            M.armCallbacks();
            M.refresh();
        end

        function tf = isDragging(M)
            tf = (M.flagmove == 1);
        end

        function rearmCallbacks(M)
            M.armCallbacks();
        end
    end

    methods(Access=private)
        function armCallbacks(M)
            try
                M.safeDisableModes();
            catch
            end

            try
                set(M.himage, ...
                    'HitTest','on', ...
                    'ButtonDownFcn',@(src,evt)M.startDrag(src,evt));
            catch
            end

            try
                set(M.himage,'PickableParts','all');
            catch
            end

            try
                set(M.axes, ...
                    'HitTest','on', ...
                    'ButtonDownFcn',@(src,evt)M.startDrag(src,evt));
            catch
            end

            try
                set(M.axes,'PickableParts','all');
            catch
            end
        end

        function startDrag(M, ~, ~)

            if isempty(M.axes) || ~ishandle(M.axes)
                return;
            end

            M.safeDisableModes();

            try
                axes(M.axes); %#ok<LAXES>
            catch
            end

            C0 = get(M.axes, 'CurrentPoint');
            M.v0 = C0(1,1:2);
            M.v1 = M.v0;
            M.dv = [0 0];
            M.alfa = 0;
            M.T1 = eye(3);
            M.flagmove = 1;

            set(M.figure, 'WindowButtonMotionFcn', @(src,evt)M.mouseMove(src,evt));
            set(M.figure, 'WindowButtonUpFcn', @(src,evt)M.mouseUp(src,evt));
            set(M.figure, 'Pointer', 'hand');
        end

        function mouseMove(M, ~, ~)

            if M.flagmove ~= 1
                return;
            end

            if isempty(M.axes) || ~ishandle(M.axes)
                return;
            end

            C0 = get(M.axes, 'CurrentPoint');
            M.v1 = C0(1,1:2);
            M.dv = M.v1 - M.v0;

            tmp0 = M.v0(1) + sqrt(-1) * M.v0(2);
            tmp1 = M.v1(1) - sqrt(-1) * M.v1(2);
            M.alfa = angle(tmp0 * tmp1) * 180 / pi;

            if strcmp(get(M.figure,'SelectionType'),'alt')
                M.T1 = M.rotz2D(M.alfa);
            else
                M.T1 = eye(3);
                M.T1(3,1:2) = M.dv;
            end

            try
                M.at = imwarp(M.a, affine2d(M.T0 * M.T1), 'OutputView', M.ref);
            catch
                M.at = imwarp(double(M.a), affine2d(M.T0 * M.T1), 'OutputView', M.ref);
            end

            M.refresh();
        end

        function mouseUp(M, ~, ~)

            if M.flagmove ~= 1
                M.clearMotionCallbacks();
                return;
            end

            M.flagmove = 0;
            M.T0 = M.T0 * M.T1;
            M.T1 = eye(3);
            M.v0 = zeros(1,2);
            M.v1 = zeros(1,2);
            M.dv = zeros(1,2);
            M.alfa = 0;

            M.clearMotionCallbacks();
            try
                set(M.figure, 'Pointer', 'arrow');
            catch
            end
            M.armCallbacks();
        end

        function clearMotionCallbacks(M)
            try
                set(M.figure, 'WindowButtonMotionFcn', '');
                set(M.figure, 'WindowButtonUpFcn', '');
            catch
            end
        end

        function safeDisableModes(M)
            try, zoom(M.figure,'off'); catch, end
            try, pan(M.figure,'off'); catch, end
            try, rotate3d(M.figure,'off'); catch, end
        end

        function h = searchImageInChildren(~, ax)
            h = [];
            try
                kids = get(ax,'Children');
                for i = 1:numel(kids)
                    if isa(kids(i),'matlab.graphics.primitive.Image')
                        h = kids(i);
                        return;
                    end
                end
            catch
            end
            error('no image in children of this axis');
        end

        function tf = isIdentity3x3(~, A)
            tf = false;
            if ~isequal(size(A), [3 3])
                return;
            end
            E = eye(3);
            tf = max(abs(A(:) - E(:))) < 1e-12;
        end

        function R = rotz2D(~, thetaDeg)
            c = cosd(thetaDeg);
            s = sind(thetaDeg);
            R = [c -s 0; s c 0; 0 0 1];
        end
    end
end
