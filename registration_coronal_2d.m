function Reg2Dout = registration_coronal_2d(atlas, src2D, sourceInfo, initialReg, saveDir, funcCandidates, defaultFuncIndex, logFcn)
% registration_coronal_2d.m
%
% Manual simple 2D coronal atlas registration
%
% Target stays fixed: atlas coronal slice
% Source moves:       selected coronal source image
%
% UPDATED GUI VERSION:
%   - image titles above images
%   - larger bottom atlas slice/mode panel
%   - thicker slice slider
%   - larger right-side controls and larger action buttons
%   - action buttons arranged in 2 rows
%   - atlas mode uses checkboxes
%   - mouse wheel changes atlas slice
%   - closing without explicit save returns empty
%
% Saved files:
%   saveDir/CoronalRegistration2D.mat
%   saveDir/atlasUnderlay_vascular_sliceXXX.mat
%   saveDir/atlasUnderlay_histology_sliceXXX.mat
%   saveDir/atlasUnderlay_regions_sliceXXX.mat
%
% ASCII only
% MATLAB 2017b compatible

if nargin < 3 || isempty(sourceInfo)
    sourceInfo = struct();
end
if nargin < 4
    initialReg = [];
end
if nargin < 5 || isempty(saveDir)
    saveDir = pwd;
end
if nargin < 6
    funcCandidates = []; %#ok<NASGU>
end
if nargin < 7
    defaultFuncIndex = []; %#ok<NASGU>
end
if nargin < 8
    logFcn = [];
end

if ~exist(saveDir,'dir')
    mkdir(saveDir);
end

src2D = double(src2D);
src2D(~isfinite(src2D)) = 0;
src2D = rescale01(src2D);

sourceMask2D = [];
if isstruct(sourceInfo) && isfield(sourceInfo,'mask2D') && ~isempty(sourceInfo.mask2D)
    try
        tmpMask = logical(sourceInfo.mask2D);
        if isequal(size(tmpMask), size(src2D))
            sourceMask2D = tmpMask;
        end
    catch
    end
end

targetH = size(atlas.Vascular,2);
targetW = size(atlas.Vascular,3);

srcH = size(src2D,1);
srcW = size(src2D,2);

Reg2Dout = [];
savedFile = '';
didExplicitSave = false;

S = struct();
S.atlasMode = 'vascular';
S.slice = round(size(atlas.Vascular,1)/2);

S.opacity = 0.65;
S.winMin = 0.02;
S.winMax = 0.98;
S.invert = false;
S.cmapName = 'hot';

S.tx = ((targetW + 1) / 2) - ((srcW + 1) / 2);
S.ty = ((targetH + 1) / 2) - ((srcH + 1) / 2);
S.rotDeg = 0;
S.sx = 1.0;
S.sy = 1.0;

S.dragging = false;
S.dragMode = '';
S.dragStartPoint = [0 0];
S.dragStartTx = 0;
S.dragStartTy = 0;
S.dragStartRot = 0;

if ~isempty(initialReg) && isstruct(initialReg)
    if isfield(initialReg,'atlasMode'),       S.atlasMode = initialReg.atlasMode; end
    if isfield(initialReg,'atlasSliceIndex'), S.slice = initialReg.atlasSliceIndex; end
    if isfield(initialReg,'opacity'),         S.opacity = initialReg.opacity; end
    if isfield(initialReg,'winMin'),          S.winMin = initialReg.winMin; end
    if isfield(initialReg,'winMax'),          S.winMax = initialReg.winMax; end
    if isfield(initialReg,'invert'),          S.invert = initialReg.invert; end
    if isfield(initialReg,'cmapName'),        S.cmapName = initialReg.cmapName; end
    if isfield(initialReg,'tx'),              S.tx = initialReg.tx; end
    if isfield(initialReg,'ty'),              S.ty = initialReg.ty; end
    if isfield(initialReg,'rotDeg'),          S.rotDeg = initialReg.rotDeg; end
    if isfield(initialReg,'sx'),              S.sx = initialReg.sx; end
    if isfield(initialReg,'sy'),              S.sy = initialReg.sy; end
end

bg       = [0.06 0.06 0.07];
fg       = [0.95 0.95 0.95];
panelBG  = [0.10 0.10 0.12];
panelBG2 = [0.13 0.13 0.15];
blueBtn  = [0.20 0.45 0.92];
greenBtn = [0.18 0.68 0.36];
grayBtn  = [0.34 0.34 0.36];
redBtn   = [0.82 0.24 0.24];

FS.title   = 18;
FS.section = 13;
FS.label   = 11.5;
FS.edit    = 11.5;
FS.button  = 11.0;
FS.status  = 10.0;
FS.small   = 10.5;
FS.mode    = 11.0;

fig = figure( ...
    'Name','2D Coronal Atlas Registration', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[120 120 1680 980], ...
    'Resize','off', ...
    'CloseRequestFcn',@onClose, ...
    'WindowScrollWheelFcn',@onScrollWheel);

% ---------------------------------------------------------------------
% Main axes
% ---------------------------------------------------------------------
axAtlas = axes('Parent',fig,'Units','normalized','Position',[0.025 0.285 0.255 0.50], ...
    'Color','k');
axis(axAtlas,'image');
axis(axAtlas,'off');

axFuse = axes('Parent',fig,'Units','normalized','Position',[0.300 0.285 0.255 0.50], ...
    'Color','k');
axis(axFuse,'image');
axis(axFuse,'off');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.18 0.945 0.53 0.04], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.title, ...
    'FontWeight','bold', ...
    'String','2D Coronal Atlas Registration');

% Image titles ABOVE images
uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.025 0.805 0.255 0.035], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',FS.section, ...
    'FontWeight','bold', ...
    'String','Atlas Reference');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.300 0.805 0.255 0.035], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',FS.section, ...
    'FontWeight','bold', ...
    'String','Move Overlay');

if isfield(sourceInfo,'label') && ~isempty(sourceInfo.label)
    srcLabel = sourceInfo.label;
else
    srcLabel = 'source';
end

% ---------------------------------------------------------------------
% Bottom panel below image display
% ---------------------------------------------------------------------
bottomPanel = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.025 0.055 0.53 0.165], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'Title','Atlas slice and mode', ...
    'FontSize',12, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.64 0.94 0.16], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.78 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.small, ...
    'String',['Source: ' srcLabel]);

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.32 0.12 0.20], ...
    'String','Mode', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label, ...
    'FontWeight','bold');

hModeVascular = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.16 0.30 0.17 0.22], ...
    'String','Vascular', ...
    'Value',double(strcmpi(S.atlasMode,'vascular')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

hModeHistology = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.34 0.30 0.18 0.22], ...
    'String','Histology', ...
    'Value',double(strcmpi(S.atlasMode,'histology')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

hModeRegions = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.54 0.30 0.16 0.22], ...
    'String','Regions', ...
    'Value',double(strcmpi(S.atlasMode,'regions')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.05 0.12 0.20], ...
    'String','Slice', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label, ...
    'FontWeight','bold');

hSliceEdit = uicontrol('Style','edit','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.16 0.05 0.10 0.22], ...
    'String',num2str(S.slice), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onSliceEdit);

% Thicker slider
hSliceSlider = uicontrol('Style','slider','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.29 0.08 0.50 0.15], ...
    'Min',1,'Max',size(atlas.Vascular,1),'Value',S.slice, ...
    'SliderStep',[1/max(1,size(atlas.Vascular,1)-1) 10/max(1,size(atlas.Vascular,1)-1)], ...
    'Callback',@onSliceSlider);

% ---------------------------------------------------------------------
% Right controls panel
% ---------------------------------------------------------------------
ctrl = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.575 0.035 0.395 0.93], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'Title','Controls', ...
    'FontSize',13, ...
    'FontWeight','bold');

xLbl  = 0.05;
xEdit = 0.30;
wLbl  = 0.22;
wEditSmall = 0.18;
hText = 0.034;
hEdit = 0.042;
hBtn  = 0.045;
hSl   = 0.024;

% ---------------------------------------------------------------------
% Overlay section
% ---------------------------------------------------------------------
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.925 0.90 0.035], ...
    'String','Overlay display', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.section, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[xLbl 0.875 wLbl hText], ...
    'String','Opacity', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label);

hOpacity = uicontrol('Style','slider','Parent',ctrl,'Units','normalized', ...
    'Position',[xEdit 0.882 0.60 hSl], ...
    'Min',0,'Max',1,'Value',S.opacity, ...
    'Callback',@onOpacity);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[xLbl 0.825 0.16 hText], ...
    'String','Win min', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label);

hWinMin = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
    'Position',[xEdit 0.827 wEditSmall hEdit], ...
    'String',num2str(S.winMin), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onDisplayEdit);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.55 0.825 0.16 hText], ...
    'String','Win max', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label);

hWinMax = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
    'Position',[0.73 0.827 wEditSmall hEdit], ...
    'String',num2str(S.winMax), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onDisplayEdit);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[xLbl 0.775 wLbl hText], ...
    'String','Colormap', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label);

cmaps = {'gray','bone','hot','copper','parula','jet'};
cmapIdx = find(strcmp(cmaps, S.cmapName), 1, 'first');
if isempty(cmapIdx), cmapIdx = 1; end

hCmap = uicontrol('Style','popupmenu','Parent',ctrl,'Units','normalized', ...
    'Position',[xEdit 0.777 0.32 hEdit], ...
    'String',cmaps, ...
    'Value',cmapIdx, ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onDisplayEdit);

hInvert = uicontrol('Style','checkbox','Parent',ctrl,'Units','normalized', ...
    'Position',[0.67 0.775 0.20 hEdit], ...
    'String','Invert', ...
    'Value',double(S.invert), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.label, ...
    'Callback',@onDisplayEdit);

% ---------------------------------------------------------------------
% Transform section
% ---------------------------------------------------------------------
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.690 0.90 0.035], ...
    'String','Manual transform', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.section, ...
    'FontWeight','bold');

[hTx, hTy, hRot, hSx, hSy] = createTransformRows();

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.245 0.90 0.040], ...
    'String','Mouse: left-drag translate, right-drag rotate, wheel scroll slices', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.82 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.small, ...
    'FontWeight','bold');

% ---------------------------------------------------------------------
% Status text
% ---------------------------------------------------------------------
hStatus = uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.020 0.90 0.045], ...
    'String','', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.70 0.95 0.70], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.status);

% ---------------------------------------------------------------------
% Larger action buttons in 2 rows
% ---------------------------------------------------------------------
btnW3 = 0.24;
btnH2 = 0.060;
btnGap3 = 0.05;
row1Y = 0.145;
row2Y = 0.075;

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.08 row1Y btnW3 btnH2], ...
    'String','Help', ...
    'BackgroundColor',blueBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onHelp);

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.08 + btnW3 + btnGap3 row1Y btnW3 btnH2], ...
    'String','Reset', ...
    'BackgroundColor',grayBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onReset);

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.08 + 2*(btnW3 + btnGap3) row1Y btnW3 btnH2], ...
    'String','Close', ...
    'BackgroundColor',redBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onClose);

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.08 row2Y 0.38 btnH2], ...
    'String','Save Transformation', ...
    'BackgroundColor',greenBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onSave);

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.54 row2Y 0.38 btnH2], ...
    'String','Save Underlays', ...
    'BackgroundColor',greenBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onSaveUnderlays);

% ---------------------------------------------------------------------
% Images
% ---------------------------------------------------------------------
axes(axAtlas);
hAtlas = image(zeros(targetH,targetW,3));
axis(axAtlas,'image');
axis(axAtlas,'off');

axes(axFuse);
hFuseUnder = image(zeros(targetH,targetW,3));
hold(axFuse,'on');

hOverlay = imagesc(zeros(targetH,targetW));
set(hOverlay, ...
    'AlphaData',zeros(targetH,targetW), ...
    'HitTest','on', ...
    'ButtonDownFcn',@onStartDrag);

hMaskContour = image(zeros(targetH,targetW,3));
set(hMaskContour, ...
    'AlphaData',zeros(targetH,targetW), ...
    'HitTest','on', ...
    'ButtonDownFcn',@onStartDrag);

hold(axFuse,'off');
axis(axFuse,'image');
axis(axFuse,'off');
set(axFuse,'CLim',[0 1]);

set(hFuseUnder,  'HitTest','on', 'ButtonDownFcn',@onStartDrag);
set(hOverlay,    'HitTest','on', 'ButtonDownFcn',@onStartDrag);
set(hMaskContour,'HitTest','on', 'ButtonDownFcn',@onStartDrag);
set(axFuse,      'HitTest','on', 'ButtonDownFcn',@onStartDrag);

renderAll();
uiwait(fig);

    function [hTx, hTy, hRot, hSx, hSy] = createTransformRows()

        y0 = 0.625;
        dy = 0.072;

        hTx  = makeRow('Shift X', S.tx,     y0,         @onTxEdit,  @onTxMinus,  @onTxPlus);
        hTy  = makeRow('Shift Y', S.ty,     y0-dy,      @onTyEdit,  @onTyMinus,  @onTyPlus);
        hRot = makeRow('Rotate',  S.rotDeg, y0-2*dy,    @onRotEdit, @onRotMinus, @onRotPlus);
        hSx  = makeRow('Scale X', S.sx,     y0-3*dy,    @onSxEdit,  @onSxMinus,  @onSxPlus);
        hSy  = makeRow('Scale Y', S.sy,     y0-4*dy,    @onSyEdit,  @onSyMinus,  @onSyPlus);

        function hRow = makeRow(lbl, val, y, cbEdit, cbMinus, cbPlus)

            uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
                'Position',[xLbl y+0.004 wLbl hText], ...
                'String',lbl, ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'HorizontalAlignment','left', ...
                'FontSize',FS.label);

            hRow.edit = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
                'Position',[xEdit y 0.24 hEdit], ...
                'String',num2str(val), ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'FontSize',FS.edit, ...
                'Callback',cbEdit);

            hRow.minus = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
                'Position',[0.60 y 0.14 hBtn], ...
                'String','-', ...
                'BackgroundColor',grayBtn, ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'FontSize',FS.button, ...
                'Callback',cbMinus);

            hRow.plus = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
                'Position',[0.78 y 0.14 hBtn], ...
                'String','+', ...
                'BackgroundColor',grayBtn, ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'FontSize',FS.button, ...
                'Callback',cbPlus);
        end
    end

    function renderAll()

        S.slice = max(1, min(size(atlas.Vascular,1), round(S.slice)));

        atlasRGB = getAtlasSliceRGB(atlas, S.atlasMode, S.slice);
        set(hAtlas,'CData',atlasRGB);
        set(hFuseUnder,'CData',atlasRGB);

        srcDisp = applyDisplay(src2D, S.winMin, S.winMax, S.invert);
        tform = affine2d(buildAffine2D(S, [srcH srcW]));
        ref2d = imref2d([targetH targetW]);

        warped = imwarp(srcDisp, tform, 'OutputView', ref2d);

        maskSrc = ones(srcH, srcW);
        alphaMask = imwarp(maskSrc, tform, 'OutputView', ref2d);
        alphaMask = min(max(alphaMask,0),1);

        set(hOverlay,'CData',warped);
        set(hOverlay,'AlphaData',S.opacity * alphaMask);

        if ~isempty(sourceMask2D)
            edge0 = simplePerimeter(sourceMask2D);
            edgeWarp = imwarp(double(edge0), tform, 'OutputView', ref2d);
            edgeWarp = edgeWarp > 0.1;

            rgb = zeros(targetH, targetW, 3);
            rgb(:,:,2) = double(edgeWarp);

            set(hMaskContour,'CData',rgb);
            set(hMaskContour,'AlphaData',0.85 * double(edgeWarp));
        else
            set(hMaskContour,'CData',zeros(targetH,targetW,3));
            set(hMaskContour,'AlphaData',zeros(targetH,targetW));
        end

        try
            cmap = feval(S.cmapName, 256);
        catch
            cmap = gray(256);
            S.cmapName = 'hot';
        end
        colormap(axFuse, cmap);
        set(axFuse,'CLim',[0 1]);

        set(hSliceEdit,'String',num2str(S.slice));
        set(hSliceSlider,'Value',S.slice);

        set(hTx.edit,'String',num2str(S.tx));
        set(hTy.edit,'String',num2str(S.ty));
        set(hRot.edit,'String',num2str(S.rotDeg));
        set(hSx.edit,'String',num2str(S.sx));
        set(hSy.edit,'String',num2str(S.sy));

        updateModeCheckboxes();

        set(hStatus,'String',sprintf(['Slice %d | Mode %s | tx %.2f | ty %.2f | rot %.2f | ' ...
                                      'sx %.3f | sy %.3f'], ...
                                      S.slice, S.atlasMode, S.tx, S.ty, S.rotDeg, S.sx, S.sy));

        drawnow limitrate;
    end

    function updateModeCheckboxes()
        set(hModeVascular, 'Value', double(strcmpi(S.atlasMode,'vascular')));
        set(hModeHistology,'Value', double(strcmpi(S.atlasMode,'histology')));
        set(hModeRegions,  'Value', double(strcmpi(S.atlasMode,'regions')));
    end

    function onModeCheckbox(src, ~)
        if src == hModeVascular
            S.atlasMode = 'vascular';
        elseif src == hModeHistology
            S.atlasMode = 'histology';
        else
            S.atlasMode = 'regions';
        end
        updateModeCheckboxes();
        renderAll();
    end

    function onSliceSlider(src, ~)
        S.slice = round(get(src,'Value'));
        renderAll();
    end

    function onSliceEdit(src, ~)
        v = round(str2double(get(src,'String')));
        if ~isfinite(v)
            v = S.slice;
        end
        S.slice = v;
        renderAll();
    end

    function onScrollWheel(~, event)
        try
            d = event.VerticalScrollCount;
        catch
            d = 0;
        end

        if ~isfinite(d)
            d = 0;
        end

        if d == 0
            return;
        end

        S.slice = S.slice - sign(d);
        renderAll();
    end

    function onOpacity(src, ~)
        S.opacity = get(src,'Value');
        renderAll();
    end

    function onDisplayEdit(~, ~)
        wmin = str2double(get(hWinMin,'String'));
        wmax = str2double(get(hWinMax,'String'));
        if ~isfinite(wmin), wmin = S.winMin; end
        if ~isfinite(wmax), wmax = S.winMax; end

        wmin = max(0, min(1, wmin));
        wmax = max(0, min(1, wmax));
        if wmax <= wmin
            wmax = min(1, wmin + 0.01);
        end

        S.winMin = wmin;
        S.winMax = wmax;
        S.invert = logical(get(hInvert,'Value'));

        strs = get(hCmap,'String');
        v = get(hCmap,'Value');
        if iscell(strs)
            S.cmapName = strs{v};
        else
            S.cmapName = deblank(strs(v,:));
        end

        renderAll();
    end

    function onTxEdit(~, ~)
        S.tx = parseOrKeep(hTx.edit, S.tx);
        renderAll();
    end

    function onTyEdit(~, ~)
        S.ty = parseOrKeep(hTy.edit, S.ty);
        renderAll();
    end

    function onRotEdit(~, ~)
        S.rotDeg = parseOrKeep(hRot.edit, S.rotDeg);
        renderAll();
    end

    function onSxEdit(~, ~)
        S.sx = max(0.05, parseOrKeep(hSx.edit, S.sx));
        renderAll();
    end

    function onSyEdit(~, ~)
        S.sy = max(0.05, parseOrKeep(hSy.edit, S.sy));
        renderAll();
    end

    function onTxMinus(~, ~), S.tx = S.tx - 2; renderAll(); end
    function onTxPlus(~, ~),  S.tx = S.tx + 2; renderAll(); end

    function onTyMinus(~, ~), S.ty = S.ty - 2; renderAll(); end
    function onTyPlus(~, ~),  S.ty = S.ty + 2; renderAll(); end

    function onRotMinus(~, ~), S.rotDeg = S.rotDeg - 1; renderAll(); end
    function onRotPlus(~, ~),  S.rotDeg = S.rotDeg + 1; renderAll(); end

    function onSxMinus(~, ~), S.sx = max(0.05, S.sx - 0.01); renderAll(); end
    function onSxPlus(~, ~),  S.sx = S.sx + 0.01; renderAll(); end

    function onSyMinus(~, ~), S.sy = max(0.05, S.sy - 0.01); renderAll(); end
    function onSyPlus(~, ~),  S.sy = S.sy + 0.01; renderAll(); end

    function onReset(~, ~)
        S.tx = ((targetW + 1) / 2) - ((srcW + 1) / 2);
        S.ty = ((targetH + 1) / 2) - ((srcH + 1) / 2);
        S.rotDeg = 0;
        S.sx = 1;
        S.sy = 1;
        renderAll();
        set(hStatus,'String','Transform reset.');
    end

   function onSave(~, ~)

    Reg2D = buildReg2D();

    sliceDir = getSliceSaveDir(saveDir, S.slice);
    outFile = fullfile(sliceDir, ...
        sprintf('CoronalRegistration2D_slice%03d_%s.mat', S.slice, lower(S.atlasMode)));

    try
        save(outFile,'Reg2D');

        savedFile = outFile;
        Reg2D.savedFile = outFile;
        Reg2Dout = Reg2D;
        didExplicitSave = true;

        set(hStatus,'String',['Saved transformation: ' outFile]);
        logMessage(['Saved slice-specific registration -> ' outFile]);

    catch ME
        set(hStatus,'String',['Save failed: ' ME.message]);
        logMessage(['Save failed: ' ME.message]);
    end
end

 function onSaveUnderlays(~, ~)

    try
        Reg2D = buildReg2D();

        sliceDir = getSliceSaveDir(saveDir, S.slice);
        sliceFile = fullfile(sliceDir, ...
            sprintf('CoronalRegistration2D_slice%03d_%s.mat', S.slice, lower(S.atlasMode)));

        save(sliceFile,'Reg2D');

        savedFile = sliceFile;
        Reg2D.savedFile = sliceFile;
        Reg2Dout = Reg2D;
        didExplicitSave = true;

        files = saveAtlasUnderlaysLocal(atlas, Reg2D, sliceDir);

        set(hStatus,'String','Saved transformation and atlas underlays.');
        logMessage(['Saved slice registration -> ' sliceFile]);
        logMessage(['Saved atlas underlays    -> ' sliceDir]);
        logMessage(['Vascular underlay        -> ' files.vascular]);
        logMessage(['Histology underlay       -> ' files.histology]);
        logMessage(['Regions underlay         -> ' files.regions]);

    catch ME
        set(hStatus,'String',['Save underlays failed: ' ME.message]);
        logMessage(['Save underlays failed: ' ME.message]);
    end
end

    function onHelp(~, ~)

        helpFig = figure( ...
            'Name','2D Registration Help', ...
            'Color',[0.08 0.08 0.09], ...
            'MenuBar','none', ...
            'ToolBar','none', ...
            'NumberTitle','off', ...
            'Resize','off', ...
            'WindowStyle','modal', ...
            'Position',[220 120 760 620]);

        helpText = { ...
            '2D CORONAL REGISTRATION - QUICK GUIDE'; ...
            ' '; ...
            '1) Atlas target is fixed on the left and in the fused view.'; ...
            '2) Your selected source image moves on top of the atlas.'; ...
            '3) Use the mode checkboxes to switch between:'; ...
            '      - Vascular'; ...
            '      - Histology'; ...
            '      - Regions'; ...
            ' '; ...
            '4) Change atlas slice using:'; ...
            '      - mouse wheel'; ...
            '      - slice slider'; ...
            '      - slice edit box'; ...
            ' '; ...
            '5) Mouse interaction in fused view:'; ...
            '      - left drag  = translate'; ...
            '      - right drag = rotate'; ...
            ' '; ...
            '6) Fine adjustment is available on the right side:'; ...
            '      - Shift X / Shift Y'; ...
            '      - Rotate'; ...
            '      - Scale X / Scale Y'; ...
            ' '; ...
            '7) Overlay display controls:'; ...
            '      - Opacity'; ...
            '      - Window min / max'; ...
            '      - Colormap'; ...
            '      - Invert'; ...
            ' '; ...
            '8) Buttons:'; ...
            '      - Reset: restore default transform'; ...
            '      - Save Transformation: saves CoronalRegistration2D.mat'; ...
            '      - Save Underlays: saves registration and atlas underlay MAT files'; ...
            '      - Close: closes without saving unless you explicitly saved'; ...
            ' '; ...
            'IMPORTANT:'; ...
            'Closing the GUI alone does NOT save anything.'; ...
            'Only the save buttons write files.'; ...
            ' '; ...
            'Tip:'; ...
            'First align by translation, then rotation, then scale.' ...
            };

        uicontrol('Style','edit','Parent',helpFig,'Units','normalized', ...
            'Position',[0.04 0.12 0.92 0.82], ...
            'Max',2, ...
            'Min',0, ...
            'Enable','inactive', ...
            'HorizontalAlignment','left', ...
            'BackgroundColor',[0.12 0.12 0.14], ...
            'ForegroundColor',[0.95 0.95 0.95], ...
            'FontName','Courier', ...
            'FontSize',11, ...
            'String',helpText);

        uicontrol('Style','pushbutton','Parent',helpFig,'Units','normalized', ...
            'Position',[0.40 0.035 0.20 0.06], ...
            'String','Close Help', ...
            'BackgroundColor',blueBtn, ...
            'ForegroundColor','w', ...
            'FontWeight','bold', ...
            'FontSize',11, ...
            'Callback',@(a,b) delete(helpFig)); %#ok<INUSD>
    end

    function onStartDrag(~, ~)

        cp = get(axFuse, 'CurrentPoint');
        x = cp(1,1);
        y = cp(1,2);

        if ~(isfinite(x) && isfinite(y))
            return;
        end

        if x < 0.5 || x > (targetW + 0.5) || y < 0.5 || y > (targetH + 0.5)
            return;
        end

        S.dragging = true;
        S.dragStartPoint = [x y];
        S.dragStartTx = S.tx;
        S.dragStartTy = S.ty;
        S.dragStartRot = S.rotDeg;

        st = get(fig,'SelectionType');
        if strcmp(st,'alt')
            S.dragMode = 'rotate';
        else
            S.dragMode = 'translate';
        end

        set(fig,'Pointer','hand');
        set(fig,'WindowButtonMotionFcn',@onDragMotion);
        set(fig,'WindowButtonUpFcn',@onStopDrag);
    end

    function onDragMotion(~, ~)
        if ~S.dragging
            return;
        end

        cp = get(axFuse, 'CurrentPoint');
        p = cp(1,1:2);
        d = p - S.dragStartPoint;

        if strcmp(S.dragMode,'translate')
            S.tx = S.dragStartTx + d(1);
            S.ty = S.dragStartTy + d(2);
        else
            S.rotDeg = S.dragStartRot + d(1);
        end

        renderAll();
    end

    function onStopDrag(~, ~)
        S.dragging = false;
        S.dragMode = '';
        set(fig,'Pointer','arrow');
        set(fig,'WindowButtonMotionFcn','');
        set(fig,'WindowButtonUpFcn','');
    end

    function onClose(~, ~)
        if ~didExplicitSave
            Reg2Dout = [];
            logMessage('2D registration closed without explicit save.');
        end

        try
            uiresume(fig);
        catch
        end
        try
            delete(fig);
        catch
        end
    end

    function Reg2D = buildReg2D()
        Reg2D = struct();
        Reg2D.type = 'simple_coronal_2d';
        Reg2D.A = buildAffine2D(S, [srcH srcW]);
        Reg2D.atlasSliceIndex = round(S.slice);
        Reg2D.atlasMode = S.atlasMode;
        Reg2D.outputSize = [targetH targetW];
        Reg2D.sourceSize = [srcH srcW];
        Reg2D.tx = S.tx;
        Reg2D.ty = S.ty;
        Reg2D.rotDeg = S.rotDeg;
        Reg2D.sx = S.sx;
        Reg2D.sy = S.sy;
        Reg2D.opacity = S.opacity;
        Reg2D.winMin = S.winMin;
        Reg2D.winMax = S.winMax;
        Reg2D.invert = S.invert;
        Reg2D.cmapName = S.cmapName;
        Reg2D.timestamp = datestr(now,'yyyymmdd_HHMMSS');
if isfield(sourceInfo,'sourceSliceIndex') && ~isempty(sourceInfo.sourceSliceIndex) && isfinite(sourceInfo.sourceSliceIndex)
    Reg2D.sourceSliceIndex = round(sourceInfo.sourceSliceIndex);
else
    Reg2D.sourceSliceIndex = 1;
end

if isfield(sourceInfo,'sourceWas3D') && ~isempty(sourceInfo.sourceWas3D)
    Reg2D.sourceWas3D = logical(sourceInfo.sourceWas3D);
else
    Reg2D.sourceWas3D = false;
end
        if isfield(sourceInfo,'path')
            Reg2D.sourcePath = sourceInfo.path;
        else
            Reg2D.sourcePath = '';
        end
        if isfield(sourceInfo,'label')
            Reg2D.sourceLabel = sourceInfo.label;
        else
            Reg2D.sourceLabel = '';
        end

        if ~isempty(savedFile)
    Reg2D.savedFile = savedFile;
else
    Reg2D.savedFile = fullfile(getSliceSaveDir(saveDir, S.slice), ...
    sprintf('CoronalRegistration2D_slice%03d_%s.mat', S.slice, lower(S.atlasMode)));
end
    end

    function logMessage(msg)
        try
            if ~isempty(logFcn) && isa(logFcn,'function_handle')
                logFcn(msg);
            else
                fprintf('[COREG 2D] %s\n', msg);
            end
        catch
        end
    end
end


%% =======================================================================
% Underlay saver
%% =======================================================================
function outFiles = saveAtlasUnderlaysLocal(atlas, Reg2D, saveDir)

if nargin < 3 || isempty(saveDir)
    saveDir = pwd;
end
if ~exist(saveDir,'dir')
    mkdir(saveDir);
end

sliceIdx = Reg2D.atlasSliceIndex;
modes = {'vascular','histology','regions'};

outFiles = struct();

for i = 1:numel(modes)
    modeName = modes{i};

    atlasUnderlay    = getAtlasSliceNumeric(atlas, modeName, sliceIdx);
    atlasUnderlayRGB = getAtlasSliceRGB(atlas, modeName, sliceIdx);
    atlasMode        = modeName; %#ok<NASGU>

    outFile = fullfile(saveDir, sprintf('AtlasUnderlay_%s_slice%03d.mat', lower(modeName), sliceIdx));

    if strcmpi(modeName,'regions')

        brainImage = atlasUnderlayRGB; %#ok<NASGU>
        atlasRegionLabels2D = round(double(atlasUnderlay)); %#ok<NASGU>
        atlasRegionLabelsLR2D = makeSignedHemisphereLabels2D(atlasRegionLabels2D); %#ok<NASGU>

        if isfield(atlas,'infoRegions')
            atlasInfoRegions = atlas.infoRegions; %#ok<NASGU>
        else
            atlasInfoRegions = []; %#ok<NASGU>
        end

        regionList = buildSliceRegionList(atlasRegionLabels2D, atlasInfoRegions); %#ok<NASGU>

        save(outFile, ...
            'atlasUnderlay', ...
            'atlasUnderlayRGB', ...
            'brainImage', ...
            'atlasMode', ...
            'Reg2D', ...
            'atlasRegionLabels2D', ...
            'atlasRegionLabelsLR2D', ...
            'atlasInfoRegions', ...
            'regionList');

        try
            txtFile = fullfile(saveDir, sprintf('AtlasRegions_slice%03d.txt', sliceIdx));
            writeRegionListTextFile(txtFile, regionList);
        catch
        end

    else
        brainImage = atlasUnderlay; %#ok<NASGU>

        save(outFile, ...
            'atlasUnderlay', ...
            'atlasUnderlayRGB', ...
            'brainImage', ...
            'atlasMode', ...
            'Reg2D');
    end

    outFiles.(modeName) = outFile;
end
end


%% =======================================================================
% Helpers for Regions SCM Color
%% =======================================================================
function labelsLR = makeSignedHemisphereLabels2D(labels2D)

labelsLR = round(double(labels2D));
labelsLR(~isfinite(labelsLR)) = 0;

nCols = size(labelsLR,2);
midCol = round(nCols/2);

labelsLR(:,1:midCol) = -abs(labelsLR(:,1:midCol));
if midCol < nCols
    labelsLR(:,midCol+1:end) = abs(labelsLR(:,midCol+1:end));
end
end


function regionList = buildSliceRegionList(labels2D, atlasInfoRegions)

labels2D = round(double(labels2D));
ids = unique(abs(labels2D(:)));
ids(ids == 0) = [];

regionList = struct();
regionList.ids         = ids(:);
regionList.acr         = cell(numel(ids),1);
regionList.name        = cell(numel(ids),1);
regionList.pixelCount  = zeros(numel(ids),1);
regionList.leftPixels  = zeros(numel(ids),1);
regionList.rightPixels = zeros(numel(ids),1);

nCols = size(labels2D,2);
midCol = round(nCols/2);

for i = 1:numel(ids)
    rid = ids(i);

    mAll = (abs(labels2D) == rid);
    mL   = false(size(labels2D));
    mR   = false(size(labels2D));

    mL(:,1:midCol) = mAll(:,1:midCol);
    if midCol < nCols
        mR(:,midCol+1:end) = mAll(:,midCol+1:end);
    end

    regionList.pixelCount(i)  = nnz(mAll);
    regionList.leftPixels(i)  = nnz(mL);
    regionList.rightPixels(i) = nnz(mR);

    acr = '';
    nam = '';

    if ~isempty(atlasInfoRegions)
        if isfield(atlasInfoRegions,'acr') && rid >= 1 && rid <= numel(atlasInfoRegions.acr)
            acr = atlasInfoRegions.acr{rid};
        end
        if isfield(atlasInfoRegions,'name') && rid >= 1 && rid <= numel(atlasInfoRegions.name)
            nam = atlasInfoRegions.name{rid};
        end
    end

    regionList.acr{i}  = acr;
    regionList.name{i} = nam;
end
end


function writeRegionListTextFile(txtFile, regionList)

fid = fopen(txtFile,'w');
if fid == -1
    return;
end

fprintf(fid,'Regions present in exported 2D atlas slice\n\n');
fprintf(fid,'ID\tACR\tNAME\tPIXELS\tLEFT\tRIGHT\n');

for i = 1:numel(regionList.ids)
    fprintf(fid,'%d\t%s\t%s\t%d\t%d\t%d\n', ...
        regionList.ids(i), ...
        safeCellStr(regionList.acr, i), ...
        safeCellStr(regionList.name, i), ...
        regionList.pixelCount(i), ...
        regionList.leftPixels(i), ...
        regionList.rightPixels(i));
end

fclose(fid);
end


function s = safeCellStr(C, idx)

s = '';
if isempty(C)
    return;
end
if idx >= 1 && idx <= numel(C)
    s = C{idx};
    if isempty(s)
        s = '';
    end
end
end


%% =======================================================================
% Atlas slice extraction
%% =======================================================================
function atlasSlice = getAtlasSliceNumeric(atlas, modeName, sliceIdx)

sliceIdx = max(1, min(size(atlas.Vascular,1), round(sliceIdx)));

switch lower(modeName)
    case 'vascular'
        atlasSlice = squeeze(atlas.Vascular(sliceIdx,:,:));
        atlasSlice = rescale01(double(atlasSlice));

    case 'histology'
        atlasSlice = squeeze(atlas.Histology(sliceIdx,:,:));
        atlasSlice = rescale01(double(atlasSlice));

    case 'regions'
        atlasSlice = double(squeeze(atlas.Regions(sliceIdx,:,:)));

    otherwise
        atlasSlice = squeeze(atlas.Vascular(sliceIdx,:,:));
        atlasSlice = rescale01(double(atlasSlice));
end
end


function RGB = getAtlasSliceRGB(atlas, modeName, sliceIdx)

sliceIdx = max(1, min(size(atlas.Vascular,1), round(sliceIdx)));

switch lower(modeName)
    case 'vascular'
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);

    case 'histology'
        A = squeeze(atlas.Histology(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);

    case 'regions'
        L = squeeze(atlas.Regions(sliceIdx,:,:));
        if isfield(atlas,'infoRegions') && isfield(atlas.infoRegions,'rgb') && ~isempty(atlas.infoRegions.rgb)
            RGB = labelToRGB(L, atlas.infoRegions.rgb);
        else
            nLab = max(1, max(abs(round(double(L(:))))));
            RGB = labelToRGB(L, lines(nLab));
        end

    otherwise
        A = squeeze(atlas.Vascular(sliceIdx,:,:));
        A = rescale01(double(A));
        RGB = grayToRGB(A);
end
end


%% =======================================================================
% Image helpers
%% =======================================================================
function v = parseOrKeep(hEdit, vold)
v = str2double(get(hEdit,'String'));
if ~isfinite(v)
    v = vold;
end
end


function A = buildAffine2D(S, srcSize)

srcH = srcSize(1);
srcW = srcSize(2);

cx = (srcW + 1) / 2;
cy = (srcH + 1) / 2;

T0 = [1 0 0; 0 1 0; -cx -cy 1];
TS = [S.sx 0 0; 0 S.sy 0; 0 0 1];

ang = S.rotDeg * pi / 180;
TR = [cos(ang) sin(ang) 0; -sin(ang) cos(ang) 0; 0 0 1];

TC = [1 0 0; 0 1 0; cx cy 1];
TT = [1 0 0; 0 1 0; S.tx S.ty 1];

A = T0 * TS * TR * TC * TT;
end


function out = applyDisplay(I, winMin, winMax, invertFlag)
out = double(I);
out = min(max(out,winMin),winMax);
out = (out - winMin) ./ max(eps, (winMax - winMin));
out = min(max(out,0),1);
if invertFlag
    out = 1 - out;
end
end


function RGB = grayToRGB(A)
A = rescale01(double(A));
RGB = zeros(size(A,1), size(A,2), 3);
RGB(:,:,1) = A;
RGB(:,:,2) = A;
RGB(:,:,3) = A;
end


function RGB = labelToRGB(L, cmap)
L = round(double(L));
idx = abs(L);
idx(idx < 1) = 1;
idx(idx > size(cmap,1)) = 1;

rgbFlat = cmap(idx(:), :);
RGB = reshape(rgbFlat, [size(L,1) size(L,2) 3]);

zeroMask = (L == 0);
for c = 1:3
    tmp = RGB(:,:,c);
    tmp(zeroMask) = 0;
    RGB(:,:,c) = tmp;
end
end

function sliceDir = getSliceSaveDir(baseDir, sliceIdx)

    sliceDir = fullfile(baseDir, sprintf('Slice%03d', round(sliceIdx)));

    if ~exist(sliceDir,'dir')
        mkdir(sliceDir);
    end
end

function A = rescale01(A)
A = double(A);
A(~isfinite(A)) = 0;
mn = min(A(:));
mx = max(A(:));
if mx > mn
    A = (A - mn) ./ (mx - mn);
else
    A = zeros(size(A));
end
end


function E = simplePerimeter(BW)
BW = logical(BW);
try
    E = bwperim(BW,8);
catch
    K = ones(3);
    N = conv2(double(BW), K, 'same');
    E = BW & (N < 9);
end
end