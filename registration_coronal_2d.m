function Reg2Dout = registration_coronal_2d(atlas, src2D, sourceInfo, initialReg, saveDir, funcCandidates, defaultFuncIndex, logFcn)
% registration_coronal_2d.m
%
% Manual simple 2D coronal atlas registration.
%
% Updated for 2D step-motor / multi-slice data:
%   - One larger GUI.
%   - Source slice selector is inside the main GUI.
%   - Switch source slice with Prev/Next, slider, edit box.
%   - Each source slice keeps its own temporary transform state.
%   - Save creates per-source-slice/per-atlas-slice Reg2D files.
%
% Target stays fixed: atlas coronal slice
% Source moves:       selected source/step-motor slice
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

Reg2Dout = [];
savedFile = '';
savedReg2DFiles = {};
didExplicitSave = false;

%% ---------------------------------------------------------------------
% Source stack support
%% ---------------------------------------------------------------------
sourceStack3D = [];
maskStack3D = [];
sourceNSlices = 1;
currentSourceSlice = 1;
sourceIsMultiSlice = false;

if isstruct(sourceInfo)
    if isfield(sourceInfo,'sourceWas3D') && ~isempty(sourceInfo.sourceWas3D)
        sourceIsMultiSlice = logical(sourceInfo.sourceWas3D);
    end
    if isfield(sourceInfo,'sourceStack3D') && ~isempty(sourceInfo.sourceStack3D)
        sourceStack3D = double(sourceInfo.sourceStack3D);
        sourceStack3D(~isfinite(sourceStack3D)) = 0;
        if ndims(sourceStack3D) == 3
            sourceNSlices = size(sourceStack3D,3);
            sourceIsMultiSlice = sourceNSlices > 1;
        end
    end
    if isfield(sourceInfo,'maskStack3D') && ~isempty(sourceInfo.maskStack3D)
        maskStack3D = sourceInfo.maskStack3D;
    end
    if isfield(sourceInfo,'sourceSliceIndex') && ~isempty(sourceInfo.sourceSliceIndex)
        currentSourceSlice = round(double(sourceInfo.sourceSliceIndex));
    end
end

if isempty(sourceStack3D)
    src2D = double(src2D);
    src2D(~isfinite(src2D)) = 0;
    sourceStack3D = reshape(src2D, size(src2D,1), size(src2D,2), 1);
    sourceNSlices = 1;
    sourceIsMultiSlice = false;
end

currentSourceSlice = max(1, min(sourceNSlices, currentSourceSlice));

src2D = getCurrentSourceImage();
sourceMask2D = getCurrentSourceMask();

targetH = size(atlas.Vascular,2);
targetW = size(atlas.Vascular,3);

srcH = size(src2D,1);
srcW = size(src2D,2);

sourceStates = cell(sourceNSlices,1);

%% ---------------------------------------------------------------------
% State defaults
%% ---------------------------------------------------------------------
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

saveCurrentSourceState();

%% ---------------------------------------------------------------------
% GUI colors and fonts
%% ---------------------------------------------------------------------
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
FS.button  = 10.8;
FS.status  = 10.0;
FS.small   = 10.5;
FS.mode    = 11.0;

scr = get(0,'ScreenSize');
figW = min(1720, scr(3)-80);
figH = min(1000, scr(4)-80);
figX = max(40, floor((scr(3)-figW)/2));
figY = max(40, floor((scr(4)-figH)/2));

fig = figure( ...
    'Name','2D Coronal Atlas Registration', ...
    'Color',bg, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[figX figY figW figH], ...
    'Resize','off', ...
    'CloseRequestFcn',@onClose, ...
    'WindowScrollWheelFcn',@onScrollWheel);

%% ---------------------------------------------------------------------
% Main axes
%% ---------------------------------------------------------------------
axAtlas = axes('Parent',fig,'Units','normalized','Position',[0.025 0.300 0.255 0.50], 'Color','k');
axis(axAtlas,'image');
axis(axAtlas,'off');

axFuse = axes('Parent',fig,'Units','normalized','Position',[0.300 0.300 0.255 0.50], 'Color','k');
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

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.025 0.820 0.255 0.035], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',FS.section, ...
    'FontWeight','bold', ...
    'String','Atlas Reference');

uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.300 0.820 0.255 0.035], ...
    'BackgroundColor',bg, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','center', ...
    'FontSize',FS.section, ...
    'FontWeight','bold', ...
    'String','Move Source Overlay');

if isfield(sourceInfo,'label') && ~isempty(sourceInfo.label)
    srcLabel = sourceInfo.label;
else
    srcLabel = 'source';
end

%% ---------------------------------------------------------------------
% Bottom panel below image display
%% ---------------------------------------------------------------------
bottomPanel = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.025 0.040 0.53 0.210], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'Title','Source slice, atlas slice and mode', ...
    'FontSize',12, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.66 0.94 0.13], ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.78 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.small, ...
    'String',['Source: ' srcLabel]);

% Source slice controls inside the main GUI
uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.82 0.13 0.12], ...
    'String','Source', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label, ...
    'FontWeight','bold');

hSourceSliceEdit = uicontrol('Style','edit','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.16 0.82 0.10 0.13], ...
    'String',num2str(currentSourceSlice), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onSourceSliceEdit);

sourceSliderMax = max(2, sourceNSlices);
hSourceSliceSlider = uicontrol('Style','slider','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.29 0.85 0.35 0.08], ...
    'Min',1, ...
    'Max',sourceSliderMax, ...
    'Value',currentSourceSlice, ...
    'SliderStep',[1/max(1,sourceNSlices-1) 5/max(1,sourceNSlices-1)], ...
    'Enable',onOff(sourceNSlices > 1), ...
    'Callback',@onSourceSliceSlider);

hSourcePrev = uicontrol('Style','pushbutton','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.66 0.82 0.08 0.13], ...
    'String','Prev', ...
    'BackgroundColor',grayBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.small, ...
    'Enable',onOff(sourceNSlices > 1), ...
    'Callback',@onSourcePrev);

hSourceNext = uicontrol('Style','pushbutton','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.75 0.82 0.08 0.13], ...
    'String','Next', ...
    'BackgroundColor',grayBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.small, ...
    'Enable',onOff(sourceNSlices > 1), ...
    'Callback',@onSourceNext);

hSourceSliceText = uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.84 0.82 0.13 0.13], ...
    'String',sprintf('%d / %d', currentSourceSlice, sourceNSlices), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[1.00 0.86 0.45], ...
    'HorizontalAlignment','right', ...
    'FontSize',FS.small, ...
    'FontWeight','bold');

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.38 0.12 0.14], ...
    'String','Mode', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label, ...
    'FontWeight','bold');

hModeVascular = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.16 0.36 0.17 0.16], ...
    'String','Vascular', ...
    'Value',double(strcmpi(S.atlasMode,'vascular')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

hModeHistology = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.34 0.36 0.18 0.16], ...
    'String','Histology', ...
    'Value',double(strcmpi(S.atlasMode,'histology')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

hModeRegions = uicontrol('Style','checkbox','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.54 0.36 0.16 0.16], ...
    'String','Regions', ...
    'Value',double(strcmpi(S.atlasMode,'regions')), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.mode, ...
    'Callback',@onModeCheckbox);

uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.03 0.11 0.12 0.14], ...
    'String','Atlas', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',fg, ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.label, ...
    'FontWeight','bold');

hSliceEdit = uicontrol('Style','edit','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.16 0.10 0.10 0.15], ...
    'String',num2str(S.slice), ...
    'BackgroundColor',panelBG2, ...
    'ForegroundColor',fg, ...
    'FontSize',FS.edit, ...
    'Callback',@onSliceEdit);

hSliceSlider = uicontrol('Style','slider','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.29 0.13 0.50 0.10], ...
    'Min',1,'Max',size(atlas.Vascular,1),'Value',S.slice, ...
    'SliderStep',[1/max(1,size(atlas.Vascular,1)-1) 10/max(1,size(atlas.Vascular,1)-1)], ...
    'Callback',@onSliceSlider);

hSourceInfo = uicontrol('Style','text','Parent',bottomPanel,'Units','normalized', ...
    'Position',[0.80 0.10 0.17 0.15], ...
    'String',getSourceSliceStatusText(), ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[1.00 0.86 0.45], ...
    'HorizontalAlignment','right', ...
    'FontSize',FS.small, ...
    'FontWeight','bold');

%% ---------------------------------------------------------------------
% Right controls panel
%% ---------------------------------------------------------------------
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

% Overlay section
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

% Transform section
uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.690 0.90 0.035], ...
    'String','Manual transform / trafo', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.section, ...
    'FontWeight','bold');

[hTx, hTy, hRot, hSx, hSy] = createTransformRows();

uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.245 0.90 0.040], ...
    'String','Mouse: left-drag translate, right-drag rotate, wheel scroll atlas slices', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.82 0.90 1.00], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.small, ...
    'FontWeight','bold');

hStatus = uicontrol('Style','text','Parent',ctrl,'Units','normalized', ...
    'Position',[0.05 0.020 0.90 0.045], ...
    'String','', ...
    'BackgroundColor',panelBG, ...
    'ForegroundColor',[0.70 0.95 0.70], ...
    'HorizontalAlignment','left', ...
    'FontSize',FS.status);

% Action buttons
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
    'String','Save Current Slice', ...
    'TooltipString','Saves transform + vascular + histology + regions + regions TXT for the current source slice.', ...
    'BackgroundColor',greenBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onSaveTrafo);

uicontrol('Style','pushbutton','Parent',ctrl,'Units','normalized', ...
    'Position',[0.54 row2Y 0.38 btnH2], ...
    'String','Save ALL Visited', ...
    'TooltipString','Saves the full package for every visited/aligned source slice.', ...
    'BackgroundColor',greenBtn, ...
    'ForegroundColor','w', ...
    'FontWeight','bold', ...
    'FontSize',FS.button, ...
    'Callback',@onSaveAllTrafos);

%% ---------------------------------------------------------------------
% Images
%% ---------------------------------------------------------------------
axes(axAtlas); %#ok<LAXES>
hAtlas = image(zeros(targetH,targetW,3));
axis(axAtlas,'image');
axis(axAtlas,'off');

axes(axFuse); %#ok<LAXES>
hFuseUnder = image(zeros(targetH,targetW,3));
hold(axFuse,'on');

hOverlay = imagesc(zeros(targetH,targetW));
set(hOverlay, 'AlphaData',zeros(targetH,targetW), 'HitTest','on', 'ButtonDownFcn',@onStartDrag);

hMaskContour = image(zeros(targetH,targetW,3));
set(hMaskContour, 'AlphaData',zeros(targetH,targetW), 'HitTest','on', 'ButtonDownFcn',@onStartDrag);

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

%% ======================================================================
% Nested functions
%% ======================================================================
    function img = getCurrentSourceImage()
        idx = max(1, min(sourceNSlices, round(currentSourceSlice)));
        img = squeeze(sourceStack3D(:,:,idx));
        img = double(img);
        img(~isfinite(img)) = 0;
        img = rescale01(img);
    end

    function mask2D = getCurrentSourceMask()
        mask2D = [];
        if isempty(maskStack3D)
            if isstruct(sourceInfo) && isfield(sourceInfo,'mask2D') && ~isempty(sourceInfo.mask2D)
                try
                    tmpMask = logical(sourceInfo.mask2D);
                    if isequal(size(tmpMask), size(src2D))
                        mask2D = tmpMask;
                    end
                catch
                end
            end
            return;
        end
        try
            if ndims(maskStack3D) == 2
                tmp = logical(maskStack3D);
            elseif ndims(maskStack3D) == 3
                idx = max(1, min(size(maskStack3D,3), round(currentSourceSlice)));
                tmp = logical(squeeze(maskStack3D(:,:,idx)));
            else
                tmp = [];
            end
            if ~isempty(tmp) && isequal(size(tmp), size(src2D))
                mask2D = tmp;
            end
        catch
            mask2D = [];
        end
    end

    function saveCurrentSourceState()
        if currentSourceSlice < 1 || currentSourceSlice > numel(sourceStates)
            return;
        end
        st = struct();
        st.atlasMode = S.atlasMode;
        st.slice = S.slice;
        st.opacity = S.opacity;
        st.winMin = S.winMin;
        st.winMax = S.winMax;
        st.invert = S.invert;
        st.cmapName = S.cmapName;
        st.tx = S.tx;
        st.ty = S.ty;
        st.rotDeg = S.rotDeg;
        st.sx = S.sx;
        st.sy = S.sy;
        sourceStates{currentSourceSlice} = st;
    end

    function restoreSourceStateOrDefault(newIdx)
        if newIdx >= 1 && newIdx <= numel(sourceStates) && ~isempty(sourceStates{newIdx})
            st = sourceStates{newIdx};
            S.atlasMode = st.atlasMode;
            S.slice = st.slice;
            S.opacity = st.opacity;
            S.winMin = st.winMin;
            S.winMax = st.winMax;
            S.invert = st.invert;
            S.cmapName = st.cmapName;
            S.tx = st.tx;
            S.ty = st.ty;
            S.rotDeg = st.rotDeg;
            S.sx = st.sx;
            S.sy = st.sy;
        else
            % New source slice: keep atlas slice/mode/display, but recenter transform.
            S.tx = ((targetW + 1) / 2) - ((srcW + 1) / 2);
            S.ty = ((targetH + 1) / 2) - ((srcH + 1) / 2);
            S.rotDeg = 0;
            S.sx = 1.0;
            S.sy = 1.0;
        end
    end

    function switchSourceSlice(newIdx)
        if sourceNSlices <= 1
            return;
        end
        newIdx = max(1, min(sourceNSlices, round(newIdx)));
        if newIdx == currentSourceSlice
            return;
        end

        saveCurrentSourceState();
        currentSourceSlice = newIdx;

        if isstruct(sourceInfo)
            sourceInfo.sourceSliceIndex = currentSourceSlice;
            sourceInfo.sourceWas3D = sourceNSlices > 1;
            sourceInfo.sourceNSlices = sourceNSlices;
            if isfield(sourceInfo,'baseLabel') && ~isempty(sourceInfo.baseLabel)
                sourceInfo.label = sprintf('%s | source slice %03d', sourceInfo.baseLabel, currentSourceSlice);
            end
        end

        src2D = getCurrentSourceImage();
        srcH = size(src2D,1);
        srcW = size(src2D,2);
        sourceMask2D = getCurrentSourceMask();

        restoreSourceStateOrDefault(currentSourceSlice);
        set(hStatus,'String',sprintf('Switched to source slice %d / %d', currentSourceSlice, sourceNSlices));
        renderAll();
    end

    function onSourceSliceSlider(src, ~)
        switchSourceSlice(round(get(src,'Value')));
    end

    function onSourceSliceEdit(src, ~)
        v = round(str2double(get(src,'String')));
        if ~isfinite(v)
            v = currentSourceSlice;
        end
        switchSourceSlice(v);
    end

    function onSourcePrev(~, ~)
        switchSourceSlice(currentSourceSlice - 1);
    end

    function onSourceNext(~, ~)
        switchSourceSlice(currentSourceSlice + 1);
    end

    function [hTx, hTy, hRot, hSx, hSy] = createTransformRows()
        y0 = 0.625;
        dy = 0.072;
        hTx  = makeRow('Shift X', S.tx,     y0,      @onTxEdit,  @onTxMinus,  @onTxPlus);
        hTy  = makeRow('Shift Y', S.ty,     y0-dy,   @onTyEdit,  @onTyMinus,  @onTyPlus);
        hRot = makeRow('Rotate',  S.rotDeg, y0-2*dy, @onRotEdit, @onRotMinus, @onRotPlus);
        hSx  = makeRow('Scale X', S.sx,     y0-3*dy, @onSxEdit,  @onSxMinus,  @onSxPlus);
        hSy  = makeRow('Scale Y', S.sy,     y0-4*dy, @onSyEdit,  @onSyMinus,  @onSyPlus);

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
        currentSourceSlice = max(1, min(sourceNSlices, round(currentSourceSlice)));

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
            cmap = hot(256);
            S.cmapName = 'hot';
        end
        colormap(axFuse, cmap);
        set(axFuse,'CLim',[0 1]);

        set(hSliceEdit,'String',num2str(S.slice));
        set(hSliceSlider,'Value',S.slice);
        set(hSourceInfo,'String',getSourceSliceStatusText());

        set(hSourceSliceEdit,'String',num2str(currentSourceSlice));
        set(hSourceSliceSlider,'Value',currentSourceSlice);
        set(hSourceSliceText,'String',sprintf('%d / %d', currentSourceSlice, sourceNSlices));

        set(hTx.edit,'String',num2str(S.tx));
        set(hTy.edit,'String',num2str(S.ty));
        set(hRot.edit,'String',num2str(S.rotDeg));
        set(hSx.edit,'String',num2str(S.sx));
        set(hSy.edit,'String',num2str(S.sy));

        updateModeCheckboxes();

        set(hStatus,'String',sprintf(['Source slice %d/%d | Atlas slice %d | %s | tx %.2f | ty %.2f | rot %.2f | ' ...
                                      'sx %.3f | sy %.3f'], ...
                                      currentSourceSlice, sourceNSlices, S.slice, S.atlasMode, ...
                                      S.tx, S.ty, S.rotDeg, S.sx, S.sy));
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
        if ~isfinite(d) || d == 0
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

    function onTxEdit(~, ~), S.tx = parseOrKeep(hTx.edit, S.tx); renderAll(); end
    function onTyEdit(~, ~), S.ty = parseOrKeep(hTy.edit, S.ty); renderAll(); end
    function onRotEdit(~, ~), S.rotDeg = parseOrKeep(hRot.edit, S.rotDeg); renderAll(); end
    function onSxEdit(~, ~), S.sx = max(0.05, parseOrKeep(hSx.edit, S.sx)); renderAll(); end
    function onSyEdit(~, ~), S.sy = max(0.05, parseOrKeep(hSy.edit, S.sy)); renderAll(); end

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

   function onSaveTrafo(~, ~)
    saveCurrentFullPackage();
end

function onSaveAllTrafos(~, ~)
    saveAllVisitedFullPackages();
end

    



    function saveCurrentFullPackage()
    try
        saveCurrentSourceState();

        Reg2D = buildReg2D();

        [sliceFile, extraFiles] = saveReg2DFullPackage(Reg2D);

        savedFile = sliceFile;
        Reg2Dout = Reg2D;
        didExplicitSave = true;

        savedReg2DFiles{end+1} = sliceFile;

        set(hStatus,'String',sprintf('Saved FULL package | source %d | atlas %03d | %s', ...
            Reg2D.sourceSliceIndex, Reg2D.atlasSliceIndex, Reg2D.atlasMode));

        logMessage(['Saved FULL Reg2D package -> ' sliceFile]);
        logTrafoDetails();

        msgbox(sprintf(['Saved current source slice.\n\n' ...
            'Transform MAT:\n%s\n\n' ...
            'Extra atlas files:\n%s'], ...
            sliceFile, strjoin(extraFiles(:), newline)), ...
            'Save Current Slice complete');

    catch ME
        set(hStatus,'String',['Save Current Slice failed: ' ME.message]);
        logMessage(['Save Current Slice failed: ' ME.message]);
        errordlg(ME.message, 'Save Current Slice failed');
    end
end


function saveAllVisitedFullPackages()
    try
        saveCurrentSourceState();

        visited = false(sourceNSlices,1);

        for ii = 1:sourceNSlices
            visited(ii) = ~isempty(sourceStates{ii});
        end

        visitedIdx = find(visited);

        if isempty(visitedIdx)
            error('No source-slice states were found. Align at least one slice first.');
        end

        if sourceNSlices > 1 && numel(visitedIdx) < sourceNSlices
            missingIdx = setdiff(1:sourceNSlices, visitedIdx);

            msg = sprintf([ ...
                'Only %d / %d source slices have been visited/aligned.\n\n' ...
                'Visited slices: %s\n' ...
                'Missing slices: %s\n\n' ...
                'Save only visited slices?'], ...
                numel(visitedIdx), sourceNSlices, ...
                compactIndexListLocal(visitedIdx), ...
                compactIndexListLocal(missingIdx));

            ch = questdlg(msg, ...
                'Save ALL Visited', ...
                'Save visited only', 'Cancel', 'Cancel');

            if isempty(ch) || strcmpi(ch,'Cancel')
                return;
            end
        end

        Reg2DList = cell(numel(visitedIdx),1);
        filesOut  = cell(numel(visitedIdx),1);

        for kk = 1:numel(visitedIdx)

            sourceIdx = visitedIdx(kk);
            st = sourceStates{sourceIdx};

            Reg2D = buildReg2DFromState(st, sourceIdx);

            [sliceFile, ~] = saveReg2DFullPackage(Reg2D);

            Reg2DList{kk} = Reg2D;
            filesOut{kk} = sliceFile;

            logMessage(sprintf('Saved FULL package -> source %03d | atlas %03d | %s', ...
                sourceIdx, Reg2D.atlasSliceIndex, sliceFile));
        end

        stamp = datestr(now,'yyyymmdd_HHMMSS');
        bundleFile = fullfile(saveDir, sprintf('StepMotor_Reg2D_Session_%s.mat', stamp));

        StepMotorReg2D = struct();
        StepMotorReg2D.kind = 'STEP_MOTOR_REG2D_SESSION_INDEX_ONLY';
        StepMotorReg2D.created = datestr(now,'yyyy-mm-dd HH:MM:SS');
        StepMotorReg2D.note = 'Index only. SCM should use the CoronalRegistration2D_sourceXXX_atlasYYY_*.mat files, not this file.';
        StepMotorReg2D.sourceNSlices = sourceNSlices;
        StepMotorReg2D.savedSourceIdx = visitedIdx(:).';
        StepMotorReg2D.files = filesOut;
        StepMotorReg2D.Reg2DList = Reg2DList;

        if isstruct(sourceInfo) && isfield(sourceInfo,'path')
            StepMotorReg2D.sourcePath = sourceInfo.path;
        else
            StepMotorReg2D.sourcePath = '';
        end

        save(bundleFile, 'StepMotorReg2D', '-v7');

        savedReg2DFiles = filesOut;
        savedFile = bundleFile;
        Reg2Dout = StepMotorReg2D;
        didExplicitSave = true;

        set(hStatus,'String',sprintf('Saved ALL visited source slices: %d full package(s)', numel(visitedIdx)));

        logMessage(['Saved StepMotor index only -> ' bundleFile]);

        msgbox(sprintf(['Saved %d full step-motor slice package(s).\n\n' ...
            'Session index file:\n%s\n\n' ...
            'SCM should use the CoronalRegistration2D_sourceXXX_atlasYYY files.'], ...
            numel(visitedIdx), bundleFile), ...
            'Save ALL Visited complete');

    catch ME
        set(hStatus,'String',['Save ALL Visited failed: ' ME.message]);
        logMessage(['Save ALL Visited failed: ' ME.message]);
        errordlg(ME.message, 'Save ALL Visited failed');
    end
end


function [sliceFile, extraFiles] = saveReg2DFullPackage(Reg2D)

    sliceFile = Reg2D.savedFile;
    sliceDir = fileparts(sliceFile);

    if ~exist(sliceDir,'dir')
        mkdir(sliceDir);
    end

    % Save main transform MAT.
    saveReg2DWithFixedAtlas(sliceFile, Reg2D);

    % Save separate atlas underlay MAT files + region TXT.
    files = saveAtlasUnderlaysLocal(atlas, Reg2D, sliceDir);

    extraFiles = {};

    if isstruct(files)
        if isfield(files,'vascular'),   extraFiles{end+1} = files.vascular;   end %#ok<AGROW>
        if isfield(files,'histology'),  extraFiles{end+1} = files.histology;  end %#ok<AGROW>
        if isfield(files,'regions'),    extraFiles{end+1} = files.regions;    end %#ok<AGROW>
        if isfield(files,'regionsTxt'), extraFiles{end+1} = files.regionsTxt; end %#ok<AGROW>
    end

    verifyFilesExist([{sliceFile} extraFiles]);
end

    function verifyFilesExist(fileCell)
        if isempty(fileCell), return; end
        for ii = 1:numel(fileCell)
            f = fileCell{ii};
            if isempty(f), continue; end
            if exist(f,'file') ~= 2
                error(['Save verification failed. Missing file: ' f]);
            end
        end
    end

    function logTrafoDetails()
        logMessage(sprintf('TRAFO details             -> source slice %d | atlas slice %03d | mode %s | tx %.2f | ty %.2f | rot %.2f | sx %.3f | sy %.3f', ...
            getSourceSliceIndexForStatus(), round(S.slice), S.atlasMode, ...
            S.tx, S.ty, S.rotDeg, S.sx, S.sy));
    end

    function sliceDir = getCurrentSliceDir()
        sliceDir = getSliceSaveDir(saveDir, S.slice, getSourceSliceIndexForStatus(), isSourceMultiSlice());
    end

    function sliceFile = getCurrentRegFile()
        sliceDir = getCurrentSliceDir();
        sliceFile = fullfile(sliceDir, ...
            sprintf('CoronalRegistration2D_source%03d_atlas%03d_%s.mat', ...
            getSourceSliceIndexForStatus(), round(S.slice), lower(S.atlasMode)));
    end

    function sourceIdx = getSourceSliceIndexForStatus()
        sourceIdx = max(1, min(sourceNSlices, round(currentSourceSlice)));
    end

    function tf = isSourceMultiSlice()
        tf = sourceNSlices > 1 || sourceIsMultiSlice;
    end

    function txt = getSourceSliceStatusText()
        if sourceNSlices > 1
            txt = sprintf('Source slice %d / %d', currentSourceSlice, sourceNSlices);
        else
            txt = 'Single source';
        end
    end

    function onHelp(~, ~)
        helpFig = figure('Name','2D Registration Help','Color',[0.08 0.08 0.09], ...
            'MenuBar','none','ToolBar','none','NumberTitle','off','Resize','off','WindowStyle','modal', ...
            'Position',[220 120 900 720]);
        helpText = { ...
            '2D CORONAL REGISTRATION - QUICK GUIDE'; ...
            ' '; ...
            'Main idea:'; ...
            '  - Atlas target is fixed.'; ...
            '  - Your source/step-motor slice moves on top of the atlas.'; ...
            ' '; ...
            'Step-motor source slice controls:'; ...
            '  - Use Source slider/edit/Prev/Next inside this same GUI.'; ...
            '  - The current source slice is shown as Source slice X / N.'; ...
            '  - Each source slice can be saved as its own Reg2D file.'; ...
            ' '; ...
            'Atlas controls:'; ...
            '  - Use mouse wheel, atlas slider, or atlas edit box.'; ...
            '  - Vascular / Histology / Regions changes atlas display mode.'; ...
            ' '; ...
            'Mouse interaction in fused view:'; ...
            '  - Left drag  = translate source overlay'; ...
            '  - Right drag = rotate source overlay'; ...
            ' '; ...
            'Save buttons:'; ...
            '  - Save Trafo: saves only current Reg2D transform.'; ...
            '  - Save Underlays + Regions: also saves atlas underlays and region list.'; ...
            ' '; ...
            'Important:'; ...
            '  - Closing without saving does not write a new Reg2D file.'; ...
            '  - For step-motor data, save each source slice separately.'; ...
            ' '; ...
            'Recommended workflow:'; ...
            '  1) Pick source slice.'; ...
            '  2) Pick matching atlas coronal slice.'; ...
            '  3) Translate, rotate, scale.'; ...
            '  4) Save Trafo or Save Underlays + Regions.'; ...
            '  5) Move to next source slice.' ...
            };
        uicontrol('Style','edit','Parent',helpFig,'Units','normalized', ...
            'Position',[0.04 0.12 0.92 0.82], ...
            'Max',2,'Min',0,'Enable','inactive','HorizontalAlignment','left', ...
            'BackgroundColor',[0.12 0.12 0.14], ...
            'ForegroundColor',[0.95 0.95 0.95], ...
            'FontName','Courier','FontSize',11, ...
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
        if ~(isfinite(x) && isfinite(y)), return; end
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
        if ~S.dragging, return; end
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
        try, uiresume(fig); catch, end
        try, delete(fig); catch, end
    end

    function Reg2D = buildReg2D()
    Reg2D = buildReg2DFromState(S, getSourceSliceIndexForStatus());
end


function Reg2D = buildReg2DFromState(st, sourceIdx)

    sourceIdx = max(1, min(sourceNSlices, round(sourceIdx)));

    srcHlocal = size(sourceStack3D,1);
    srcWlocal = size(sourceStack3D,2);

    Reg2D = struct();

    Reg2D.type = 'simple_coronal_2d';

    % This A is already MATLAB affine2d-compatible.
    % SCM should use it directly.
    Reg2D.A = buildAffine2D(st, [srcHlocal srcWlocal]);

    Reg2D.atlasSliceIndex = round(st.slice);
    Reg2D.atlasMode = st.atlasMode;

    Reg2D.outputSize = [targetH targetW];
    Reg2D.sourceSize = [srcHlocal srcWlocal];

    Reg2D.tx = st.tx;
    Reg2D.ty = st.ty;
    Reg2D.rotDeg = st.rotDeg;
    Reg2D.sx = st.sx;
    Reg2D.sy = st.sy;

    Reg2D.opacity = st.opacity;
    Reg2D.winMin = st.winMin;
    Reg2D.winMax = st.winMax;
    Reg2D.invert = st.invert;
    Reg2D.cmapName = st.cmapName;

    Reg2D.timestamp = datestr(now,'yyyymmdd_HHMMSS');

    Reg2D.sourceSliceIndex = sourceIdx;
    Reg2D.sourceWas3D = isSourceMultiSlice();
    Reg2D.sourceNSlices = sourceNSlices;

    if isfield(sourceInfo,'path')
        Reg2D.sourcePath = sourceInfo.path;
    else
        Reg2D.sourcePath = '';
    end

    if isfield(sourceInfo,'baseLabel') && ~isempty(sourceInfo.baseLabel)
        Reg2D.sourceBaseLabel = sourceInfo.baseLabel;
        Reg2D.sourceLabel = sprintf('%s | source slice %03d', sourceInfo.baseLabel, sourceIdx);
    elseif isfield(sourceInfo,'label')
        Reg2D.sourceBaseLabel = sourceInfo.label;
        Reg2D.sourceLabel = sourceInfo.label;
    else
        Reg2D.sourceBaseLabel = '';
        Reg2D.sourceLabel = '';
    end

    sliceDir = getSliceSaveDir(saveDir, st.slice, sourceIdx, isSourceMultiSlice());

    if ~exist(sliceDir,'dir')
        mkdir(sliceDir);
    end

    Reg2D.savedFile = fullfile(sliceDir, ...
        sprintf('CoronalRegistration2D_source%03d_atlas%03d_%s.mat', ...
        sourceIdx, round(st.slice), lower(st.atlasMode)));

    % ---------------------------------------------------------
    % Fixed atlas target images saved inside the same Reg2D file.
    % This prevents SCM from losing the histology background.
    % ---------------------------------------------------------
    Reg2D.fixedImage = getAtlasSliceNumeric(atlas, st.atlasMode, st.slice);
    Reg2D.fixedUnderlay = Reg2D.fixedImage;
    Reg2D.atlasUnderlay = Reg2D.fixedImage;
    Reg2D.atlasUnderlayRGB = getAtlasSliceRGB(atlas, st.atlasMode, st.slice);

    Reg2D.histologyImage = getAtlasSliceNumeric(atlas, 'histology', st.slice);
    Reg2D.histologyUnderlay = Reg2D.histologyImage;

    Reg2D.vascularImage = getAtlasSliceNumeric(atlas, 'vascular', st.slice);
    Reg2D.vascularUnderlay = Reg2D.vascularImage;

    Reg2D.regionsImage = getAtlasSliceNumeric(atlas, 'regions', st.slice);
    Reg2D.regionsUnderlay = Reg2D.regionsImage;
end

    function saveReg2DWithFixedAtlas(sliceFile, Reg2D)

    outDir = fileparts(sliceFile);

    if ~exist(outDir,'dir')
        mkdir(outDir);
    end

    fixedImage       = Reg2D.fixedImage;          %#ok<NASGU>
    fixedUnderlay    = Reg2D.fixedUnderlay;       %#ok<NASGU>
    atlasUnderlay    = Reg2D.atlasUnderlay;       %#ok<NASGU>
    atlasUnderlayRGB = Reg2D.atlasUnderlayRGB;    %#ok<NASGU>

    histologyImage    = Reg2D.histologyImage;     %#ok<NASGU>
    histologyUnderlay = Reg2D.histologyUnderlay;  %#ok<NASGU>

    vascularImage    = Reg2D.vascularImage;       %#ok<NASGU>
    vascularUnderlay = Reg2D.vascularUnderlay;    %#ok<NASGU>

    regionsImage    = Reg2D.regionsImage;         %#ok<NASGU>
    regionsUnderlay = Reg2D.regionsUnderlay;      %#ok<NASGU>

    sourceImage = []; %#ok<NASGU>
    sourceMask  = []; %#ok<NASGU>

    try
        sourceImage = squeeze(sourceStack3D(:,:,Reg2D.sourceSliceIndex));
    catch
        sourceImage = [];
    end

    try
        sourceMask = sourceMask2D;
    catch
        sourceMask = [];
    end

    save(sliceFile, ...
        'Reg2D', ...
        'fixedImage', ...
        'fixedUnderlay', ...
        'atlasUnderlay', ...
        'atlasUnderlayRGB', ...
        'histologyImage', ...
        'histologyUnderlay', ...
        'vascularImage', ...
        'vascularUnderlay', ...
        'regionsImage', ...
        'regionsUnderlay', ...
        'sourceImage', ...
        'sourceMask', ...
        '-v7');
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
        save(outFile, 'atlasUnderlay', 'atlasUnderlayRGB', 'brainImage', 'atlasMode', 'Reg2D', ...
            'atlasRegionLabels2D', 'atlasRegionLabelsLR2D', 'atlasInfoRegions', 'regionList');
        txtFile = fullfile(saveDir, sprintf('AtlasRegions_slice%03d.txt', sliceIdx));
        writeRegionListTextFile(txtFile, regionList);
        outFiles.regionsTxt = txtFile;
    else
        brainImage = atlasUnderlay; %#ok<NASGU>
        save(outFile, 'atlasUnderlay', 'atlasUnderlayRGB', 'brainImage', 'atlasMode', 'Reg2D');
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
    error('Could not write region list TXT file: %s', txtFile);
end
fprintf(fid,'Regions present in exported 2D atlas slice\n\n');
fprintf(fid,'ID\tACR\tNAME\tPIXELS\tLEFT\tRIGHT\n');
for i = 1:numel(regionList.ids)
    fprintf(fid,'%d\t%s\t%s\t%d\t%d\t%d\n', ...
        regionList.ids(i), safeCellStr(regionList.acr, i), safeCellStr(regionList.name, i), ...
        regionList.pixelCount(i), regionList.leftPixels(i), regionList.rightPixels(i));
end
fclose(fid);
end


function s = safeCellStr(C, idx)
s = '';
if isempty(C), return; end
if idx >= 1 && idx <= numel(C)
    s = C{idx};
    if isempty(s), s = ''; end
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

function s = compactIndexListLocal(v)

    if isempty(v)
        s = '<none>';
        return;
    end

    v = unique(sort(round(v(:).')));

    parts = {};
    i = 1;

    while i <= numel(v)
        j = i;

        while j < numel(v) && v(j+1) == v(j) + 1
            j = j + 1;
        end

        if i == j
            parts{end+1} = sprintf('%d', v(i)); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%d-%d', v(i), v(j)); %#ok<AGROW>
        end

        i = j + 1;
    end

    s = strjoin(parts, ', ');
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


function sliceDir = getSliceSaveDir(baseDir, atlasSliceIdx, sourceSliceIdx, useSourceFolder)
if nargin < 3 || isempty(sourceSliceIdx)
    sourceSliceIdx = 1;
end
if nargin < 4 || isempty(useSourceFolder)
    useSourceFolder = false;
end
if useSourceFolder
    sliceDir = fullfile(baseDir, sprintf('SourceSlice%03d_AtlasSlice%03d', round(sourceSliceIdx), round(atlasSliceIdx)));
else
    sliceDir = fullfile(baseDir, sprintf('Slice%03d', round(atlasSliceIdx)));
end
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


function s = onOff(tf)
% onOff
% Small local helper. This fixes the error:
% "Undefined function 'onOff' for input arguments of type 'logical'".
if tf
    s = 'on';
else
    s = 'off';
end
end
