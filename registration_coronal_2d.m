function Reg2Dout = registration_coronal_2d(atlas, src2D, sourceInfo, initialReg, saveDir, funcCandidates, defaultFuncIndex, logFcn)
% registration_coronal_2d.m
%
% Manual simple 2D coronal atlas registration
%
% Target stays fixed: atlas coronal slice
% Source moves:       selected coronal source image
%
% This version:
%   - fixes mouse drag on the fused view
%   - saves only Reg2D + atlas underlay MAT files
%   - does NOT export giant warped functional MAT files
%   - optional source mask contour overlay if sourceInfo.mask2D exists
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

S = struct();
S.atlasMode = 'vascular';
S.slice = round(size(atlas.Vascular,1)/2);

S.opacity = 0.65;
S.winMin = 0.02;
S.winMax = 0.98;
S.invert = false;
S.cmapName = 'gray';

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

bg = [0.06 0.06 0.07];
fg = [0.95 0.95 0.95];
panelBG = [0.10 0.10 0.12];
panelBG2 = [0.13 0.13 0.15];

fig = figure( ...
    'Name','Simple 2D Coronal Atlas Registration', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[80 60 1480 920], ...
    'CloseRequestFcn',@onClose);

axAtlas = axes('Parent',fig,'Units','normalized','Position',[0.03 0.12 0.28 0.76], ...
    'Color','k');
axis(axAtlas,'image');
axis(axAtlas,'off');

axFuse = axes('Parent',fig,'Units','normalized','Position',[0.34 0.12 0.28 0.76], ...
    'Color','k');
axis(axFuse,'image');
axis(axFuse,'off');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.91 0.59 0.04], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',16, ...
    'FontWeight','bold', ...
    'String','Simple 2D Coronal Atlas Registration');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.87 0.28 0.03], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'String','Atlas target');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.34 0.87 0.28 0.03], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'String','Atlas underlay + moving source overlay');

if isfield(sourceInfo,'label') && ~isempty(sourceInfo.label)
    srcLabel = sourceInfo.label;
else
    srcLabel = 'source';
end

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.02 0.59 0.05], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',[0.78 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',10, ...
    'String',['Source: ' srcLabel]);

ctrl = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.65 0.05 0.32 0.88], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'Title','Controls', ...
    'FontSize',12, ...
    'FontWeight','bold');

% Atlas section
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.93 0.90 0.03], ...
    'String','Atlas underlay', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',11, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.885 0.22 0.03], ...
    'String','Mode', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

atlasModes = {'vascular','histology','regions'};
modeIdx = find(strcmp(atlasModes, S.atlasMode), 1, 'first');
if isempty(modeIdx), modeIdx = 1; end

hMode = uicontrol('Style','popupmenu','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.888 0.30 0.035], ...
    'String',atlasModes, ...
    'Value',modeIdx, ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'Callback',@onModeChanged);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.84 0.22 0.03], ...
    'String','Slice', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

hSliceEdit = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.843 0.12 0.035], ...
    'String',num2str(S.slice), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'Callback',@onSliceEdit);

hSliceSlider = uicontrol('Style','slider','Parent',ctrl,'Units','normalized', ...
    'Position',[0.42 0.847 0.48 0.025], ...
    'Min',1,'Max',size(atlas.Vascular,1),'Value',S.slice, ...
    'SliderStep',[1/max(1,size(atlas.Vascular,1)-1) 10/max(1,size(atlas.Vascular,1)-1)], ...
    'Callback',@onSliceSlider);

% Display section
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.77 0.90 0.03], ...
    'String','Overlay display', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',11, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.725 0.22 0.03], ...
    'String','Opacity', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

hOpacity = uicontrol('Style','slider','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.73 0.62 0.025], ...
    'Min',0,'Max',1,'Value',S.opacity, ...
    'Callback',@onOpacity);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.68 0.22 0.03], ...
    'String','Win min', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

hWinMin = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.683 0.18 0.035], ...
    'String',num2str(S.winMin), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'Callback',@onDisplayEdit);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.50 0.68 0.18 0.03], ...
    'String','Win max', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

hWinMax = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
    'Position',[0.72 0.683 0.18 0.035], ...
    'String',num2str(S.winMax), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'Callback',@onDisplayEdit);

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.635 0.22 0.03], ...
    'String','Colormap', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left');

cmaps = {'gray','bone','hot','copper','parula','jet'};
cmapIdx = find(strcmp(cmaps, S.cmapName), 1, 'first');
if isempty(cmapIdx), cmapIdx = 1; end

hCmap = uicontrol('Style','popupmenu','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.638 0.30 0.035], ...
    'String',cmaps, ...
    'Value',cmapIdx, ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'Callback',@onDisplayEdit);

hInvert = uicontrol('Style','checkbox','Parent',ctrl,'Units','normalized', ...
    'Position',[0.65 0.638 0.25 0.035], ...
    'String','Invert', ...
    'Value',double(S.invert), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'Callback',@onDisplayEdit);

% Transform section
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.575 0.90 0.03], ...
    'String','Manual transform', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',11, ...
    'FontWeight','bold');

[hTx, hTy, hRot, hSx, hSy] = createTransformRows();

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.205 0.90 0.05], ...
    'String','Mouse: left-drag translate, right-drag rotate', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.82 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',10, ...
    'FontWeight','bold');

% Buttons
hReset = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.095 0.20 0.055], ...
    'String','Reset', ...
    'BackgroundColor',[0.35 0.35 0.35], ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'Callback',@onReset);

hSave = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.28 0.095 0.20 0.055], ...
    'String','Save Reg', ...
    'BackgroundColor',[0.15 0.70 0.55], ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'Callback',@onSave);

hWarp = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.51 0.095 0.25 0.055], ...
    'String','Save Underlays', ...
    'BackgroundColor',[0.22 0.50 0.90], ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'Callback',@onSaveUnderlays);

hClose = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.79 0.095 0.15 0.055], ...
    'String','Close', ...
    'BackgroundColor',[0.85 0.25 0.25], ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'Callback',@onClose);

hStatus = uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.02 0.90 0.06], ...
    'String','', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.70 0.95 0.70], ...
    'HorizontalAlignment','left', ...
    'FontSize',9);

% Images
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

        y0 = 0.515;
        dy = 0.07;

        hTx  = makeRow('Shift X', S.tx, y0,         @onTxEdit,  @onTxMinus,  @onTxPlus);
        hTy  = makeRow('Shift Y', S.ty, y0-dy,      @onTyEdit,  @onTyMinus,  @onTyPlus);
        hRot = makeRow('Rotate',  S.rotDeg, y0-2*dy,@onRotEdit, @onRotMinus, @onRotPlus);
        hSx  = makeRow('Scale X', S.sx, y0-3*dy,    @onSxEdit,  @onSxMinus,  @onSxPlus);
        hSy  = makeRow('Scale Y', S.sy, y0-4*dy,    @onSyEdit,  @onSyMinus,  @onSyPlus);

        function hRow = makeRow(lbl, val, y, cbEdit, cbMinus, cbPlus)
            uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
                'Position',[0.05 y 0.20 0.03], ...
                'String',lbl, ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'HorizontalAlignment','left');

            hRow.edit = uicontrol('Style','edit','Parent',ctrl,'Units','normalized', ...
                'Position',[0.28 y 0.24 0.04], ...
                'String',num2str(val), ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Callback',cbEdit);

            hRow.minus = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
                'Position',[0.56 y 0.14 0.04], ...
                'String','-', ...
                'BackgroundColor',[0.35 0.35 0.35], ...
                'ForegroundColor','w', ...
                'Callback',cbMinus);

            hRow.plus = uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
                'Position',[0.74 y 0.14 0.04], ...
                'String','+', ...
                'BackgroundColor',[0.35 0.35 0.35], ...
                'ForegroundColor','w', ...
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
            S.cmapName = 'gray';
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

        set(hStatus,'String',sprintf(['Slice %d | Mode %s | tx %.2f | ty %.2f | rot %.2f | ' ...
                                      'sx %.3f | sy %.3f'], ...
                                      S.slice, S.atlasMode, S.tx, S.ty, S.rotDeg, S.sx, S.sy));

        drawnow limitrate;
    end

    function onModeChanged(src, ~)
        strs = get(src,'String');
        v = get(src,'Value');
        if iscell(strs)
            S.atlasMode = strs{v};
        else
            S.atlasMode = deblank(strs(v,:));
        end
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
    end

    function onSave(~, ~)
        Reg2D = buildReg2D();
        outFile = fullfile(saveDir,'CoronalRegistration2D.mat');
        try
            save(outFile,'Reg2D');
            savedFile = outFile;
            Reg2Dout = Reg2D;
            set(hStatus,'String',['Saved: ' outFile]);
            logMessage(['Saved CoronalRegistration2D.mat -> ' outFile]);
        catch ME
            set(hStatus,'String',['Save failed: ' ME.message]);
            logMessage(['Save failed: ' ME.message]);
        end
    end

    function onSaveUnderlays(~, ~)

        try
            onSave([],[]);

            Reg2D = buildReg2D();
            files = saveAtlasUnderlaysLocal(atlas, Reg2D, saveDir);

            savedFile = fullfile(saveDir,'CoronalRegistration2D.mat');
            Reg2Dout = Reg2D;

            set(hStatus,'String','Saved Reg2D + vascular/histology/regions underlays.');
            logMessage(['Saved atlas underlays -> ' saveDir]);

            msgbox({ ...
                'Saved registration and atlas underlays.', ...
                ['Reg2D:      ' fullfile(saveDir,'CoronalRegistration2D.mat')], ...
                ['Vascular:   ' files.vascular], ...
                ['Histology:  ' files.histology], ...
                ['Regions:    ' files.regions], ...
                'Use one of these underlay MAT files in SCM GUI.', ...
                'SCM should warp the functional stack in memory using Reg2D.'}, ...
                '2D Registration Export', 'help');

        catch ME
            set(hStatus,'String',['Save underlays failed: ' ME.message]);
            logMessage(['Save underlays failed: ' ME.message]);
        end
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
        if isempty(Reg2Dout)
            Reg2Dout = buildReg2D();
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
            Reg2D.savedFile = fullfile(saveDir,'CoronalRegistration2D.mat');
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

    atlasUnderlay = getAtlasSliceNumeric(atlas, modeName, sliceIdx);
    atlasUnderlayRGB = getAtlasSliceRGB(atlas, modeName, sliceIdx);
    brainImage = atlasUnderlay; %#ok<NASGU>
    atlasMode = modeName; %#ok<NASGU>

    outFile = fullfile(saveDir, sprintf('atlasUnderlay_%s_slice%03d.mat', lower(modeName), sliceIdx));
    save(outFile, 'atlasUnderlay', 'brainImage', 'atlasUnderlayRGB', 'atlasMode', 'Reg2D');

    outFiles.(modeName) = outFile;
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
        RGB = labelToRGB(L, atlas.infoRegions.rgb);

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