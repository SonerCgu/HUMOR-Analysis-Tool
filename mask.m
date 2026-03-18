function out = mask(varargin)
% mask.m - fUSI Studio Mask Editor
% MATLAB 2017b / 2023b compatible
% ASCII-only source for maximum copy-paste safety
%
% PURPOSE
%   - Draw a brain / underlay mask
%   - Draw an overlay / signal mask
%   - Save both into ONE MAT bundle
%
% IMPORTANT SAVE LOGIC
%   SAVE BRAIN:
%       mask / loadedMask = brainMask
%   SAVE OVERLAY:
%       mask / loadedMask = overlayMask
%   SAVE BOTH:
%       brainMask / underlayMask = brain region
%       overlayMask / signalMask = display restriction region
%       mask / loadedMask = overlayMask
%
% SAVED VARIABLES
%   brainImage
%   brainMask
%   underlayMask
%   overlayMask
%   signalMask
%   mask
%   activeMask
%   loadedMask
%   maskIsInclude
%   loadedMaskIsInclude
%   overlayMaskIsInclude
%   maskBundle
%   maskEditorInfo
%
% PAINTING
%   Left drag  = ADD
%   Right drag = ERASE
%   Shift+Left = ERASE
%
% KEY
%   F = fill current slice of active target
%   ESC = close editor

% =========================================================
% 0) Parse inputs
% =========================================================
studio = struct();
I = [];
datasetLabel = 'dataset';

initBrainMask = [];
initOverlayMask = [];

for k = 1:nargin
    a = varargin{k};

    if isstruct(a)
        if isfield(a,'exportPath') || isfield(a,'activeDataset') || isfield(a,'loadedPath') || isfield(a,'loadedFile')
            studio = a;

            if isfield(studio,'activeDataset') && ~isempty(studio.activeDataset)
                datasetLabel = studio.activeDataset;
            elseif isfield(studio,'loadedFile') && ~isempty(studio.loadedFile)
                datasetLabel = studio.loadedFile;
            end

            if isempty(initBrainMask)
                if isfield(studio,'brainMask') && ~isempty(studio.brainMask)
                    initBrainMask = studio.brainMask;
                elseif isfield(studio,'underlayMask') && ~isempty(studio.underlayMask)
                    initBrainMask = studio.underlayMask;
                elseif isfield(studio,'mask') && ~isempty(studio.mask)
                    initBrainMask = studio.mask;
                end
            end

            if isempty(initOverlayMask)
                if isfield(studio,'overlayMask') && ~isempty(studio.overlayMask)
                    initOverlayMask = studio.overlayMask;
                elseif isfield(studio,'signalMask') && ~isempty(studio.signalMask)
                    initOverlayMask = studio.signalMask;
                end
            end

        elseif isfield(a,'I') && isnumeric(a.I)
            I = a.I;

            if isempty(initBrainMask)
                if isfield(a,'brainMask') && ~isempty(a.brainMask)
                    initBrainMask = a.brainMask;
                elseif isfield(a,'underlayMask') && ~isempty(a.underlayMask)
                    initBrainMask = a.underlayMask;
                elseif isfield(a,'mask') && ~isempty(a.mask)
                    initBrainMask = a.mask;
                end
            end

            if isempty(initOverlayMask)
                if isfield(a,'overlayMask') && ~isempty(a.overlayMask)
                    initOverlayMask = a.overlayMask;
                elseif isfield(a,'signalMask') && ~isempty(a.signalMask)
                    initOverlayMask = a.signalMask;
                end
            end
        end

    elseif isnumeric(a)
        if isempty(I) && (ndims(a)==3 || ndims(a)==4)
            I = a;
        else
            if isempty(initBrainMask)
                initBrainMask = a;
            elseif isempty(initOverlayMask)
                initOverlayMask = a;
            end
        end

    elseif islogical(a)
        if isempty(initBrainMask)
            initBrainMask = a;
        elseif isempty(initOverlayMask)
            initOverlayMask = a;
        end

    elseif ischar(a) || isstring(a)
        s = char(a);
        if ~isempty(s)
            datasetLabel = s;
        end
    end
end

if isempty(I) || ~isnumeric(I)
    errordlg('mask.m: No valid image volume provided. Call mask(I) or mask(studio,data).','Mask Editor');
    out = struct('cancelled',true);
    return;
end

if ~isfield(studio,'exportPath') || isempty(studio.exportPath) || ~exist(studio.exportPath,'dir')
    studio.exportPath = pwd;
end

% =========================================================
% 1) Dimensions
% =========================================================
ndI = ndims(I);
sz = size(I);

if ndI == 3
    nY = sz(1); nX = sz(2); nZ = 1;
elseif ndI == 4
    nY = sz(1); nX = sz(2); nZ = sz(3);
else
    errordlg('mask.m: I must be 3D (Y X T) or 4D (Y X Z T).','Mask Editor');
    out = struct('cancelled',true);
    return;
end

% =========================================================
% 2) Theme
% =========================================================
C = struct();
C.fig      = [0.07 0.08 0.10];
C.panel    = [0.11 0.12 0.15];
C.panel2   = [0.15 0.16 0.20];
C.axbg     = [0.00 0.00 0.00];

C.text     = [0.95 0.96 0.98];
C.textDim  = [0.78 0.81 0.86];
C.subtle   = [0.58 0.63 0.70];

C.blue     = [0.28 0.53 0.88];
C.green    = [0.27 0.75 0.48];
C.orange   = [0.91 0.62 0.20];
C.red      = [0.86 0.28 0.28];
C.grayBtn  = [0.38 0.40 0.45];
C.yellow   = [0.95 0.82 0.18];

C.brain    = [0.27 0.75 0.48];
C.overlay  = [0.91 0.62 0.20];
C.erase    = [0.92 0.30 0.30];

UI = struct();
UI.fontName = 'Arial';
UI.fsTitle  = 15;
UI.fsPanel  = 13;
UI.fsText   = 12;
UI.fsBtn    = 12;
UI.fsSmall  = 11;
UI.fsStatus = 10;
% =========================================================
% 3) State
% =========================================================
S = struct();
S.z = max(1, round(nZ/2));
S.flipUD_display = true;

S.editorOn = true;
S.previewMasked = false;

% 1 = brain / underlay
% 2 = overlay / signal
S.editTarget = 1;

% Underlay modes:
% 1 MIP(Z) of Mean(T) [default]
% 2 Mean(T) [linear]
% 3 Median(T) [linear]
% 4 Max(T) [linear]
% 5 External file
% 6 imregdemons Mean (dB)
S.underlayMode = 1;
S.externalFile = '';
UbaseLabel = 'MIP (Z) of Mean(T)';

S.dbLow  = -48;
S.dbHigh = -7;

S.brightness = 0.00;
S.contrast   = 1.00;
S.gamma      = 1.00;
S.sharpness  = 0.00;
S.globalScaling = false;
S.pctLow  = 1;
S.pctHigh = 99;
S.cmapMode = 1;

S.showOverlay = true;
S.overlayAlpha = 0.30;

S.smoothSize = 8;
S.brushR = 50;
S.brushShape = 2; % 1 round, 2 square, 3 pen, 4 diamond

S.isPainting = false;
S.paintMode = '';
S.lastRaw = [NaN NaN];

brushCache = struct('r',NaN,'shape',NaN,'K',[],'R',0);

brainMaskVol   = false(nY,nX,nZ);
overlayMaskVol = false(nY,nX,nZ);

if ~isempty(initBrainMask)
    brainMaskVol = fitMaskToDims(initBrainMask, nY, nX, nZ);
end
if ~isempty(initOverlayMask)
    overlayMaskVol = fitMaskToDims(initOverlayMask, nY, nX, nZ);
end

% Preload commonly used underlays
Ucache = struct();
Ucache.mip        = [];
Ucache.mean       = [];
Ucache.median     = [];
Ucache.max        = [];
Ucache.imregd     = [];
Ucache.external   = [];

try
    Ucache.mip = underlayMIP_Z_ofMeanT(I);
catch
    Ucache.mip = [];
end

try
    Ucache.mean = underlayMeanLinear(I);
catch
    Ucache.mean = [];
end

try
    Ucache.max = underlayMaxLinear(I);
catch
    Ucache.max = [];
end

try
    Ucache.imregd = underlayImregdemonsMeanDB(I);
catch
    Ucache.imregd = [];
end

Ubase = computeUnderlayVolume(S.underlayMode);
if isempty(Ubase)
    if ndI == 3
        Ubase = double(I(:,:,1));
        Ubase = reshape(Ubase,[nY nX 1]);
    else
        Utmp = double(I(:,:,S.z,1));
        Ubase = repmat(reshape(Utmp,[nY nX 1]),[1 1 nZ]);
    end
    UbaseLabel = 'Fallback';
end

% =========================================================
% 4) Outputs
% =========================================================
out = struct();
out.cancelled = true;
out.mask = [];
out.brainMask = [];
out.underlayMask = [];
out.overlayMask = [];
out.signalMask = [];
out.brainImage = [];
out.anatomical_reference_raw = [];
out.anatomical_reference = [];
out.files = struct();
out.files.maskBundle_mat = '';
out.files.brainImage_mat = '';

% =========================================================
% 5) Figure
% =========================================================
fig = figure( ...
    'Name','Mask Editor', ...
    'Color',C.fig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'Position',[80 40 1820 1020], ...
    'Resize','on', ...
    'InvertHardcopy','off', ...
    'DefaultUicontrolFontName',UI.fontName, ...
    'DefaultUicontrolFontSize',UI.fsText, ...
    'DefaultUipanelFontName',UI.fontName, ...
    'DefaultUipanelFontSize',UI.fsPanel);

try
    set(fig,'Renderer','opengl');
catch
end

set(fig,'CloseRequestFcn',@onCloseReturn);

titleText = uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.952 0.63 0.035], ...
    'BackgroundColor',C.fig,'ForegroundColor',C.text, ...
    'FontSize',UI.fsTitle,'FontWeight','bold', ...
    'HorizontalAlignment','center', ...
    'String','Mask Editor');

ax = axes('Parent',fig,'Units','normalized','Position',[0.03 0.085 0.63 0.86], ...
    'Color',C.axbg);
hold(ax,'on');
axis(ax,'image');
axis(ax,'off');
set(ax,'XLim',[0.5 nX+0.5],'YLim',[0.5 nY+0.5], ...
       'XLimMode','manual','YLimMode','manual');
axis(ax,'manual');
set(ax,'YDir','normal');

imgH = image(ax, zeros(nY,nX,3,'single'));
set(imgH,'HitTest','on');
try
    set(imgH,'Interpolation','nearest');
catch
end

txtSlice = text(ax, 0.99, 0.02, '', 'Units','normalized', ...
    'Color',[0.86 0.93 1.00], ...
    'FontSize',11, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'VerticalAlignment','bottom', ...
    'Interpreter','none');

brushPreview = [];

statusBox = uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.01 0.63 0.055], ...
    'BackgroundColor',C.fig,'ForegroundColor',C.textDim, ...
    'FontName',UI.fontName,'FontSize',UI.fsStatus, ...
    'HorizontalAlignment','left', ...
    'String','');

% =========================================================
% 6) Right-side layout
% =========================================================
panel = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.67 0.035 0.31 0.945], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Mask Controls', ...
    'FontSize',13, ...
    'FontWeight','bold');

pMode = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.80 0.96 0.17], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Mode', ...
    'FontSize',13, ...
    'FontWeight','bold');

pUnder = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.60 0.96 0.17], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Underlay', ...
    'FontSize',13, ...
    'FontWeight','bold');

pDisplay = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.40 0.96 0.18], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Display', ...
    'FontSize',13, ...
    'FontWeight','bold');

pTools = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.16 0.96 0.22], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Tools', ...
    'FontSize',13, ...
    'FontWeight','bold');

pSave = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.08 0.96 0.07], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.text, ...
    'Title','Save', ...
    'FontSize',13, ...
    'FontWeight','bold');

pBottom = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.02 0.01 0.96 0.06], ...
    'BackgroundColor',C.panel, ...
    'ForegroundColor',C.panel, ...
    'BorderType','none');
% =========================================================
% 7) Helper makers
% =========================================================
    function hObj = makeText(parent, pos, str, col, fs, fw, ha)
        if nargin < 7 || isempty(ha), ha = 'left'; end
        if nargin < 6 || isempty(fw), fw = 'normal'; end
        if nargin < 5 || isempty(fs), fs = UI.fsText; end
        if nargin < 4 || isempty(col), col = C.text; end

        bgCol = C.panel;
        try
            bgCol = get(parent,'BackgroundColor');
        catch
        end

        hObj = uicontrol('Style','text','Parent',parent,'Units','normalized', ...
            'Position',pos, ...
            'String',str, ...
            'BackgroundColor',bgCol, ...
            'ForegroundColor',col, ...
            'FontName',UI.fontName, ...
            'FontSize',fs, ...
            'FontWeight',fw, ...
            'HorizontalAlignment',ha);
    end

    function hObj = makeButton(parent, pos, str, bg, fg, cb)
        if nargin < 5 || isempty(fg), fg = [1 1 1]; end
        hObj = uicontrol('Style','pushbutton','Parent',parent,'Units','normalized', ...
            'Position',pos, ...
            'String',str, ...
            'BackgroundColor',bg, ...
            'ForegroundColor',fg, ...
            'FontName',UI.fontName, ...
            'FontSize',UI.fsBtn, ...
            'FontWeight','bold', ...
            'Callback',cb);
    end

    function hObj = makeSlider(parent, pos, mn, mx, val, cb)
        hObj = uicontrol('Style','slider','Parent',parent,'Units','normalized', ...
            'Position',pos, ...
            'Min',mn,'Max',mx,'Value',val, ...
            'Callback',cb);
    end

% =========================================================
% 8) Controls
% =========================================================
h = struct();

% -------------------- Mode --------------------
h.togEditor = uicontrol('Style','togglebutton','Parent',pMode,'Units','normalized', ...
    'Position',[0.02 0.69 0.46 0.19], ...
    'String','Editor ON','Value',1, ...
    'BackgroundColor',C.green,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@onToggleEditor);

h.togPreview = uicontrol('Style','togglebutton','Parent',pMode,'Units','normalized', ...
    'Position',[0.52 0.69 0.46 0.19], ...
    'String','Preview: FULL','Value',0, ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',12,'FontWeight','bold', ...
    'Callback',@onTogglePreview);

h.btnTargetBrain = makeButton(pMode,[0.02 0.44 0.46 0.19],'BRAIN / UNDERLAY',C.brain,'w',@onTargetBrain);
h.btnTargetOverlay = makeButton(pMode,[0.52 0.44 0.46 0.19],'OVERLAY / SIGNAL',C.grayBtn,C.text,@onTargetOverlay);

h.txtTargetInfo = makeText(pMode,[0.03 0.24 0.94 0.11],'Active: Brain / Underlay mask',C.brain,11,'bold','left');

h.chkShowOverlay = uicontrol('Style','checkbox','Parent',pMode,'Units','normalized', ...
    'Position',[0.03 0.14 0.42 0.08], ...
    'String','Show overlay', ...
    'Value',double(S.showOverlay), ...
    'BackgroundColor',C.panel,'ForegroundColor',C.text, ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onShowOverlayToggle);

h.lblOverlayAlpha = makeText(pMode,[0.03 0.03 0.08 0.07],'Alpha',C.text,11,'normal','left');
h.slOverlayAlpha = makeSlider(pMode,[0.12 0.045 0.66 0.10],0,1,S.overlayAlpha,@onOverlayAlphaChange);
h.txtOverlayAlpha = makeText(pMode,[0.84 0.03 0.12 0.07],sprintf('%.2f',S.overlayAlpha),C.text,11,'normal','right');


% -------------------- Underlay --------------------
h.popUnderlay = uicontrol('Style','popupmenu','Parent',pUnder,'Units','normalized', ...
    'Position',[0.03 0.79 0.94 0.12], ...
    'String',{'MIP (Z) of Mean(T) [default]', ...
              'Mean (T) [linear]', ...
              'Median (T) [linear]', ...
              'Max (T) [linear]', ...
              'External file...', ...
              'imregdemons Mean (dB)'}, ...
    'Value',S.underlayMode, ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onUnderlayMode);

h.btnLoadUnderlay = makeButton(pUnder,[0.03 0.61 0.94 0.12],'Load external underlay',C.grayBtn,'w',@onLoadExternal);

h.chkGlobal = uicontrol('Style','checkbox','Parent',pUnder,'Units','normalized', ...
    'Position',[0.03 0.47 0.94 0.09], ...
    'String','Global scaling (linear modes only)', ...
    'Value',double(S.globalScaling), ...
    'BackgroundColor',C.panel,'ForegroundColor',C.subtle, ...
    'FontName',UI.fontName,'FontSize',10, ...
    'Callback',@onGlobalScaling);

h.txtUnderlayLabel = makeText(pUnder,[0.03 0.36 0.94 0.09],['Underlay: ' UbaseLabel],[0.72 0.86 1.00],11,'normal','left');

h.lblDbLow = makeText(pUnder,[0.03 0.15 0.13 0.08],'dB low',C.text,11,'normal','left');
h.edDbLow = uicontrol('Style','edit','Parent',pUnder,'Units','normalized', ...
    'Position',[0.18 0.16 0.18 0.13], ...
    'String',num2str(S.dbLow), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onDbEdit);

h.lblDbHigh = makeText(pUnder,[0.44 0.15 0.13 0.08],'dB high',C.text,11,'normal','left');
h.edDbHigh = uicontrol('Style','edit','Parent',pUnder,'Units','normalized', ...
    'Position',[0.59 0.16 0.18 0.13], ...
    'String',num2str(S.dbHigh), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onDbEdit);

if nZ > 1
    h.slSlice = makeSlider(pUnder,[0.03 0.02 0.72 0.12],1,nZ,S.z,@onSliceChange);
    set(h.slSlice,'SliderStep',[1/max(1,nZ-1) 5/max(1,nZ-1)]);
    h.txtSliceVal = makeText(pUnder,[0.76 0.02 0.20 0.09],sprintf('z=%d/%d',S.z,nZ),C.text,11,'normal','right');
else
    h.slSlice = [];
    h.txtSliceVal = [];
end

% -------------------- Display --------------------
h.lblBright = makeText(pDisplay,[0.03 0.80 0.18 0.10],'Bright',C.text,11,'normal','left');
h.slBright = makeSlider(pDisplay,[0.22 0.83 0.58 0.11],-0.6,0.6,S.brightness,@onDisplayChange);
h.txtBright = makeText(pDisplay,[0.82 0.80 0.15 0.10],sprintf('%.2f',S.brightness),C.text,11,'normal','right');

h.lblCont = makeText(pDisplay,[0.03 0.59 0.18 0.10],'Contrast',C.text,11,'normal','left');
h.slCont = makeSlider(pDisplay,[0.22 0.62 0.58 0.11],0.5,3.0,S.contrast,@onDisplayChange);
h.txtCont = makeText(pDisplay,[0.82 0.59 0.15 0.10],sprintf('%.2f',S.contrast),C.text,11,'normal','right');

h.lblGamma = makeText(pDisplay,[0.03 0.38 0.18 0.10],'Gamma',C.text,11,'normal','left');
h.slGamma = makeSlider(pDisplay,[0.22 0.41 0.58 0.11],0.2,3.0,S.gamma,@onDisplayChange);
h.txtGamma = makeText(pDisplay,[0.82 0.38 0.15 0.10],sprintf('%.2f',S.gamma),C.text,11,'normal','right');

h.lblSharp = makeText(pDisplay,[0.03 0.18 0.18 0.10],'Sharp',C.text,11,'normal','left');
h.slSharp = makeSlider(pDisplay,[0.22 0.21 0.58 0.11],0,300,S.sharpness,@onDisplayChange);
h.txtSharp = makeText(pDisplay,[0.82 0.18 0.15 0.10],sprintf('%.2f',S.sharpness),C.text,11,'normal','right');

h.popCmap = uicontrol('Style','popupmenu','Parent',pDisplay,'Units','normalized', ...
    'Position',[0.03 0.02 0.94 0.11], ...
    'String',{'Gray','B/W (inverted)','Hot','Copper','Bone'}, ...
    'Value',S.cmapMode, ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onCmapChange);

% -------------------- Tools --------------------
h.lblBrush = makeText(pTools,[0.03 0.82 0.26 0.10],'Brush Size & Type',C.text,11,'normal','left');
h.slBrush = makeSlider(pTools,[0.30 0.85 0.50 0.11],1,200,S.brushR,@onBrushChange);
h.txtBrush = makeText(pTools,[0.82 0.82 0.15 0.10],sprintf('%.0f',S.brushR),C.text,11,'normal','right');

h.popShape = uicontrol('Style','popupmenu','Parent',pTools,'Units','normalized', ...
    'Position',[0.03 0.66 0.94 0.10], ...
    'String',{'Round','Square','Pen','Diamond'}, ...
    'Value',shapeToPopupValue(S.brushShape), ...
    'BackgroundColor',C.panel2,'ForegroundColor','w', ...
    'FontName',UI.fontName,'FontSize',11, ...
    'Callback',@onShapeChange);

h.lblSmooth = makeText(pTools,[0.03 0.46 0.15 0.10],'Smooth',C.text,11,'normal','left');
h.slSmooth = makeSlider(pTools,[0.20 0.49 0.60 0.11],0,100,S.smoothSize,@onSmoothSize);
h.txtSmooth = makeText(pTools,[0.82 0.46 0.15 0.10],sprintf('%.0f',S.smoothSize),C.text,11,'normal','right');

h.btnFillSlice = makeButton(pTools,[0.03 0.22 0.22 0.14],'Fill Slice',C.yellow,'k',@onFillSlice);
h.btnFillAll = makeButton(pTools,[0.27 0.22 0.22 0.14],'Fill All',[0.92 0.74 0.12],'k',@onFillAll);
h.btnSmooth = makeButton(pTools,[0.51 0.22 0.22 0.14],'Smooth',C.grayBtn,'w',@onSmooth);
h.btnClearSlice = makeButton(pTools,[0.75 0.22 0.22 0.14],'Clr Slice',C.orange,'w',@onClearSlice);

h.btnClearMask = makeButton(pTools,[0.03 0.05 0.94 0.11],'Clear Active Mask',C.red,'w',@onClearMask);

% -------------------- Save --------------------
h.btnSaveBrain = makeButton(pSave,[0.00 0.14 0.31 0.62],'SAVE UNDERLAY',C.green,'w',@onSaveBrain);
h.btnSaveOverlay = makeButton(pSave,[0.345 0.14 0.31 0.62],'SAVE OVERLAY',C.orange,'w',@onSaveOverlay);
h.btnSaveBoth = makeButton(pSave,[0.69 0.14 0.31 0.62],'SAVE BOTH',C.blue,'w',@onSaveBoth);

% -------------------- Bottom --------------------
h.btnHelp = makeButton(pBottom,[0.00 0.08 0.48 0.84],'HELP',C.blue,'w',@onHelp);
h.btnClose = makeButton(pBottom,[0.52 0.08 0.48 0.84],'CLOSE',C.red,'w',@onCloseReturn);

% =========================================================
% 9) Figure callbacks
% =========================================================
set(fig,'WindowButtonDownFcn',@onMouseDown);
set(fig,'WindowButtonUpFcn',@onMouseUp);
set(fig,'WindowButtonMotionFcn',@onMouseMove);
set(fig,'WindowScrollWheelFcn',@onScrollWheel);
set(fig,'KeyPressFcn',@onKey);

updateTitle();
updateTargetUI();
updateDbControlsEnabled();
updateStatus('Ready. Left drag = add. Right drag = erase. Press F to fill current slice.');
renderNow();

uiwait(fig);

% =========================================================
% ======================= NESTED FUNCS =====================
% =========================================================

% -------------------- General UI --------------------
    function onToggleEditor(src,~)
        S.editorOn = logical(get(src,'Value'));
        if S.editorOn
            set(src,'String','Editor ON','BackgroundColor',C.green);
            updateStatus('Editor enabled.');
        else
            set(src,'String','Editor OFF','BackgroundColor',C.red);
            stopPainting();
            updateStatus('Editor disabled.');
        end
        renderNow();
    end

    function onTogglePreview(src,~)
        S.previewMasked = logical(get(src,'Value'));
        if S.previewMasked
            set(src,'String','Preview: MASKED');
            updateStatus('Preview masked by brain mask.');
        else
            set(src,'String','Preview: FULL');
            updateStatus('Preview full underlay.');
        end
        renderNow();
    end

    function onTargetBrain(~,~)
        S.editTarget = 1;
        updateTargetUI();
        renderNow();
    end

    function onTargetOverlay(~,~)
        S.editTarget = 2;
        updateTargetUI();
        renderNow();
    end

    function updateTargetUI()
        if S.editTarget == 1
            set(h.btnTargetBrain,'BackgroundColor',C.brain,'ForegroundColor','w');
            set(h.btnTargetOverlay,'BackgroundColor',C.grayBtn,'ForegroundColor',C.text);
            set(h.txtTargetInfo,'String','Active: Brain / Underlay mask','ForegroundColor',C.brain);
        else
            set(h.btnTargetBrain,'BackgroundColor',C.grayBtn,'ForegroundColor',C.text);
            set(h.btnTargetOverlay,'BackgroundColor',C.overlay,'ForegroundColor','w');
            set(h.txtTargetInfo,'String','Active: Overlay / Signal mask','ForegroundColor',C.overlay);
        end
    end

    function onShowOverlayToggle(src,~)
        S.showOverlay = logical(get(src,'Value'));
        renderNow();
    end

    function onOverlayAlphaChange(~,~)
        S.overlayAlpha = get(h.slOverlayAlpha,'Value');
        set(h.txtOverlayAlpha,'String',sprintf('%.2f',S.overlayAlpha));
        renderNow();
    end

% -------------------- Underlay controls --------------------
    function onUnderlayMode(src,~)
        S.underlayMode = get(src,'Value');
        if S.underlayMode == 5
            onLoadExternal();
            return;
        end
        Ubase = computeUnderlayVolume(S.underlayMode);
        updateTitle();
        updateDbControlsEnabled();
        renderNow();
    end

    function onLoadExternal(~,~)
        startPath = studio.exportPath;
        if isfield(studio,'loadedPath') && ~isempty(studio.loadedPath) && exist(studio.loadedPath,'dir')
            startPath = studio.loadedPath;
        end

        [f,p] = uigetfile({'*.mat;*.nii;*.nii.gz;*.tif;*.tiff;*.png;*.jpg;*.jpeg', ...
                           'Underlay (*.mat,*.nii,*.nii.gz, images)'}, ...
                           'Select external underlay', startPath);

        if isequal(f,0)
            if isgraphics(h.popUnderlay)
                set(h.popUnderlay,'Value',S.underlayMode);
            end
            return;
        end

        S.externalFile = fullfile(p,f);

        try
            tmp = loadUnderlayAny(S.externalFile);
            tmp = fitUnderlayToDims(tmp, nY, nX, nZ);
            Ucache.external = double(tmp);
            Ubase = Ucache.external;
            S.underlayMode = 5;
            set(h.popUnderlay,'Value',5);

            [~,nm,ex] = fileparts(f);
            UbaseLabel = ['External: ' nm ex];

            updateTitle();
            updateDbControlsEnabled();
            updateStatus('External underlay loaded.');
            renderNow();
        catch ME
            errordlg(ME.message,'External underlay failed');
            set(h.popUnderlay,'Value',1);
            S.underlayMode = 1;
            Ubase = computeUnderlayVolume(1);
            updateTitle();
            updateDbControlsEnabled();
            renderNow();
        end
    end

    function onGlobalScaling(src,~)
        S.globalScaling = logical(get(src,'Value'));
        renderNow();
    end

    function onDbEdit(~,~)
        lo = str2double(get(h.edDbLow,'String'));
        hi = str2double(get(h.edDbHigh,'String'));

        if ~isfinite(lo), lo = S.dbLow; end
        if ~isfinite(hi), hi = S.dbHigh; end
        if hi <= lo + 1
            hi = lo + 1;
        end

        S.dbLow = lo;
        S.dbHigh = hi;

        set(h.edDbLow,'String',num2str(S.dbLow));
        set(h.edDbHigh,'String',num2str(S.dbHigh));

        renderNow();
    end

    function updateDbControlsEnabled()
        isDb = (S.underlayMode == 6);
        if isDb
            set(h.lblDbLow,'Enable','on');
            set(h.edDbLow,'Enable','on');
            set(h.lblDbHigh,'Enable','on');
            set(h.edDbHigh,'Enable','on');
            set(h.chkGlobal,'Enable','off');
        else
            set(h.lblDbLow,'Enable','off');
            set(h.edDbLow,'Enable','off');
            set(h.lblDbHigh,'Enable','off');
            set(h.edDbHigh,'Enable','off');
            set(h.chkGlobal,'Enable','on');
        end
    end

    function onSliceChange(src,~)
        S.z = max(1, min(nZ, round(get(src,'Value'))));
        if ~isempty(h.txtSliceVal) && isgraphics(h.txtSliceVal)
            set(h.txtSliceVal,'String',sprintf('z=%d/%d',S.z,nZ));
        end
        renderNow();
    end

    function onScrollWheel(~,evt)
        if nZ <= 1
            return;
        end
        if ~isCursorOverAxes()
            return;
        end

        dz = -sign(evt.VerticalScrollCount);
        if dz == 0
            return;
        end

        S.z = max(1, min(nZ, S.z + dz));

        if ~isempty(h.slSlice) && isgraphics(h.slSlice)
            set(h.slSlice,'Value',S.z);
        end
        if ~isempty(h.txtSliceVal) && isgraphics(h.txtSliceVal)
            set(h.txtSliceVal,'String',sprintf('z=%d/%d',S.z,nZ));
        end

        renderNow();
    end

% -------------------- Display controls --------------------
    function onDisplayChange(~,~)
        S.brightness = get(h.slBright,'Value');
        S.contrast   = get(h.slCont,'Value');
        S.gamma      = get(h.slGamma,'Value');
        S.sharpness  = get(h.slSharp,'Value');

        set(h.txtBright,'String',sprintf('%.2f',S.brightness));
        set(h.txtCont,'String',sprintf('%.2f',S.contrast));
        set(h.txtGamma,'String',sprintf('%.2f',S.gamma));
        set(h.txtSharp,'String',sprintf('%.2f',S.sharpness));

        renderNow();
    end

    function onCmapChange(src,~)
        S.cmapMode = get(src,'Value');
        renderNow();
    end

% -------------------- Tool controls --------------------
    function onBrushChange(~,~)
        S.brushR = max(1, round(get(h.slBrush,'Value')));
        set(h.txtBrush,'String',sprintf('%d',S.brushR));
        invalidateBrushCache();
        renderNow();
    end

    function onShapeChange(src,~)
        S.brushShape = popupValueToShape(get(src,'Value'));
        invalidateBrushCache();
        stopPainting();
        renderNow();
    end

    function onSmoothSize(~,~)
        S.smoothSize = max(0, round(get(h.slSmooth,'Value')));
        set(h.txtSmooth,'String',sprintf('%d',S.smoothSize));
    end

    function onSmooth(~,~)
        z = S.z;
        if S.editTarget == 1
            brainMaskVol(:,:,z) = smoothMaskSafe(brainMaskVol(:,:,z), S.smoothSize);
            updateStatus('Smoothed brain mask in current slice.');
        else
            overlayMaskVol(:,:,z) = smoothMaskSafe(overlayMaskVol(:,:,z), S.smoothSize);
            updateStatus('Smoothed overlay mask in current slice.');
        end
        renderNow();
    end

    function onFillSlice(~,~)
        z = S.z;
        if S.editTarget == 1
            brainMaskVol(:,:,z) = fillHolesAllSafe(brainMaskVol(:,:,z));
            updateStatus('Filled holes in brain mask for current slice.');
        else
            overlayMaskVol(:,:,z) = fillHolesAllSafe(overlayMaskVol(:,:,z));
            updateStatus('Filled holes in overlay mask for current slice.');
        end
        renderNow();
    end

    function onFillAll(~,~)
        if S.editTarget == 1
            for zz = 1:nZ
                brainMaskVol(:,:,zz) = fillHolesAllSafe(brainMaskVol(:,:,zz));
            end
            updateStatus('Filled holes in brain mask for all slices.');
        else
            for zz = 1:nZ
                overlayMaskVol(:,:,zz) = fillHolesAllSafe(overlayMaskVol(:,:,zz));
            end
            updateStatus('Filled holes in overlay mask for all slices.');
        end
        renderNow();
    end

    function onClearSlice(~,~)
        if S.editTarget == 1
            brainMaskVol(:,:,S.z) = false;
            updateStatus(sprintf('Cleared brain mask in slice %d.',S.z));
        else
            overlayMaskVol(:,:,S.z) = false;
            updateStatus(sprintf('Cleared overlay mask in slice %d.',S.z));
        end
        renderNow();
    end

    function onClearMask(~,~)
        if S.editTarget == 1
            brainMaskVol(:) = false;
            updateStatus('Cleared brain mask.');
        else
            overlayMaskVol(:) = false;
            updateStatus('Cleared overlay mask.');
        end
        renderNow();
    end

% -------------------- Save --------------------
    function onSaveBrain(~,~)
        saveMaskBundle('brain');
    end

    function onSaveOverlay(~,~)
        saveMaskBundle('overlay');
    end

    function onSaveBoth(~,~)
        saveMaskBundle('both');
    end

    function saveMaskBundle(mode)
        brainHas = any(brainMaskVol(:));
        overlayHas = any(overlayMaskVol(:));

        switch lower(mode)
            case 'brain'
                if ~brainHas
                    errordlg('Brain mask is empty. Draw it first, then SAVE BRAIN.','Mask Editor');
                    return;
                end
            case 'overlay'
                if ~overlayHas
                    errordlg('Overlay mask is empty. Draw it first, then SAVE OVERLAY.','Mask Editor');
                    return;
                end
            case 'both'
                if ~brainHas
                    errordlg('Brain mask is empty. Draw it first, then SAVE BOTH.','Mask Editor');
                    return;
                end
                if ~overlayHas
                    errordlg('Overlay mask is empty. Draw it first, then SAVE BOTH.','Mask Editor');
                    return;
                end
        end

        visDir = fullfile(studio.exportPath,'Visualization');
        if ~exist(visDir,'dir')
            mkdir(visDir);
        end

        ts = datestr(now,'yyyymmdd_HHMMSS');

        if nZ == 1
            brainMask = logical(brainMaskVol(:,:,1));
            underlayMask = brainMask;
            overlayMask = logical(overlayMaskVol(:,:,1));
            signalMask = overlayMask;
        else
            brainMask = logical(brainMaskVol);
            underlayMask = brainMask;
            overlayMask = logical(overlayMaskVol);
            signalMask = overlayMask;
        end

        if brainHas
            brainImage = buildBrainImageForSave_native();
        else
            brainImage = [];
        end

                              switch lower(mode)
            case 'brain'
                mask = brainMask;
                activeMask = brainMask;
                loadedMask = brainMask;
                maskIsInclude = true;
                loadedMaskIsInclude = true;
                overlayMaskIsInclude = true;
                filePrefix = 'MaskEditor_UnderlayMaskOnly';
                saveModeLabel = 'Underlay mask only';

            case 'overlay'
                mask = overlayMask;
                activeMask = overlayMask;
                loadedMask = overlayMask;
                maskIsInclude = true;
                loadedMaskIsInclude = true;
                overlayMaskIsInclude = true;
                filePrefix = 'MaskEditor_OverlayMaskOnly';
                saveModeLabel = 'Overlay mask only';

            otherwise
                mask = overlayMask;
                activeMask = overlayMask;
                loadedMask = overlayMask;
                maskIsInclude = true;
                loadedMaskIsInclude = true;
                overlayMaskIsInclude = true;
                filePrefix = 'MaskEditor_UnderlayAndOverlayMasks';
                saveModeLabel = 'Underlay and overlay masks';
        end

                maskEditorInfo = struct();
        maskEditorInfo.datasetLabel = datasetLabel;
        maskEditorInfo.timestamp = ts;
        maskEditorInfo.saveMode = mode;
        maskEditorInfo.saveModeLabel = saveModeLabel;
        maskEditorInfo.outputFilePrefix = filePrefix;
        maskEditorInfo.underlayMode = S.underlayMode;
        maskEditorInfo.underlayLabel = UbaseLabel;
        maskEditorInfo.dbLow = S.dbLow;
        maskEditorInfo.dbHigh = S.dbHigh;
        maskEditorInfo.brightness = S.brightness;
        maskEditorInfo.contrast = S.contrast;
        maskEditorInfo.gamma = S.gamma;
        maskEditorInfo.sharpness = S.sharpness;
        maskEditorInfo.globalScaling = S.globalScaling;
        maskEditorInfo.cmapMode = S.cmapMode;
        maskEditorInfo.showOverlay = S.showOverlay;
        maskEditorInfo.overlayAlpha = S.overlayAlpha;
        maskEditorInfo.flipUD_display = S.flipUD_display;
        maskEditorInfo.maskIsInclude = maskIsInclude;
        maskEditorInfo.loadedMaskIsInclude = loadedMaskIsInclude;
        maskEditorInfo.overlayMaskIsInclude = overlayMaskIsInclude;

        maskBundle = struct();
        maskBundle.brainImage = brainImage;
        maskBundle.brainMask = brainMask;
        maskBundle.underlayMask = underlayMask;
        maskBundle.overlayMask = overlayMask;
        maskBundle.signalMask = signalMask;
        maskBundle.mask = mask;
        maskBundle.activeMask = activeMask;
        maskBundle.loadedMask = loadedMask;
        maskBundle.maskIsInclude = maskIsInclude;
        maskBundle.loadedMaskIsInclude = loadedMaskIsInclude;
        maskBundle.overlayMaskIsInclude = overlayMaskIsInclude;
        maskBundle.maskEditorInfo = maskEditorInfo;

        outFile = fullfile(visDir, sprintf('%s_%s_%s.mat', filePrefix, safeFileStem(datasetLabel), ts));

        try
            save(outFile, ...
                'brainImage', ...
                'brainMask', ...
                'underlayMask', ...
                'overlayMask', ...
                'signalMask', ...
                'mask', ...
                'activeMask', ...
                'loadedMask', ...
                'maskIsInclude', ...
                'loadedMaskIsInclude', ...
                'overlayMaskIsInclude', ...
                'maskBundle', ...
                'maskEditorInfo', ...
                '-v7.3');
        catch ME
            errordlg(ME.message,'Save failed');
            return;
        end

        out.files.maskBundle_mat = outFile;
        if brainHas
            out.files.brainImage_mat = outFile;
        end

        out.mask = logical(brainMaskVol);
        out.brainMask = logical(brainMaskVol);
        out.underlayMask = logical(brainMaskVol);
        out.overlayMask = logical(overlayMaskVol);
        out.signalMask = logical(overlayMaskVol);
        if brainHas
            out.brainImage = brainImage;
        end

        updateStatus(['Saved: ' outFile]);
    end

% -------------------- Help / close --------------------
    function onKey(~,evt)
        if ~isfield(evt,'Key')
            return;
        end
        switch lower(evt.Key)
            case 'f'
                onFillSlice();
            case 'escape'
                onCloseReturn();
        end
    end

    function onHelp(~,~)
        helpFig = figure( ...
            'Name','Mask Editor Help', ...
            'Color',C.fig, ...
            'MenuBar','none', ...
            'ToolBar','none', ...
            'NumberTitle','off', ...
            'Resize','off', ...
            'Position',[220 160 760 520], ...
            'InvertHardcopy','off');

        uicontrol('Style','text','Parent',helpFig,'Units','normalized', ...
            'Position',[0.04 0.91 0.92 0.06], ...
            'String','Mask Editor - Quick Guide', ...
            'BackgroundColor',C.fig, ...
            'ForegroundColor',C.text, ...
            'FontName',UI.fontName, ...
            'FontSize',14, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','center');

        helpLines = { ...
            'The mask editor lets you define two separate masks on top of an anatomical-style underlay.', ...
            'The brain / underlay mask defines the structural region to keep as valid brain area.', ...
            'The overlay / signal mask defines where overlay-like signal display is allowed to appear.', ...
            ' ', ...
            'How to paint:', ...
            'Left drag adds pixels. Right drag erases pixels. Shift + left also erases.', ...
            'Use the mouse wheel over the image to move through slices. Press F to fill holes in the current slice.', ...
            ' ', ...
            'Main controls:', ...
            'Editor ON/OFF enables drawing.', ...
            'Preview FULL or MASKED switches whether display is shown everywhere or only inside the brain mask.', ...
            'BRAIN / UNDERLAY selects the structural mask target.', ...
            'OVERLAY / SIGNAL selects the signal display restriction mask target.', ...
            'Show overlay and Alpha control how strongly the overlay mask is visualized.', ...
            ' ', ...
            'Underlay options:', ...
            'MIP is the default starting underlay for easier overall overview.', ...
            'imregdemons Mean (dB) remains available as the dB-based structural view.', ...
            'Brightness, Contrast, Gamma and Sharp only change visualization, not the actual saved mask geometry.', ...
            ' ', ...
            'Tools:', ...
            'Brush changes size, Shape changes geometry, Smooth regularizes the active mask.', ...
            'Fill Slice / Fill All fill holes, Clear Slice clears one slice, Clear Active Mask clears the selected mask entirely.', ...
            ' ', ...
            'Saving:', ...
            'SAVE UNDERLAY stores the underlay / brain mask as compatibility mask.', ...
            'SAVE OVERLAY stores the overlay mask as compatibility mask.', ...
            'SAVE BOTH stores both masks, but mask / loadedMask still point to the overlay mask for playback compatibility.', ...
            ' ', ...
            'Closing:', ...
            'CLOSE returns the current masks and attempts to set fUSI Studio back to Ready.'};

        uicontrol('Style','edit','Parent',helpFig,'Units','normalized', ...
            'Position',[0.04 0.12 0.92 0.76], ...
            'Max',50,'Min',0, ...
            'Enable','inactive', ...
            'HorizontalAlignment','left', ...
            'String',helpLines, ...
            'BackgroundColor',C.panel, ...
            'ForegroundColor',C.text, ...
            'FontName',UI.fontName, ...
            'FontSize',11);

        uicontrol('Style','pushbutton','Parent',helpFig,'Units','normalized', ...
            'Position',[0.36 0.03 0.28 0.06], ...
            'String','Close Help', ...
            'BackgroundColor',C.blue, ...
            'ForegroundColor','w', ...
            'FontName',UI.fontName, ...
            'FontSize',11, ...
            'FontWeight','bold', ...
            'Callback',@(src,evt) delete(helpFig));
    end

    function onCloseReturn(~,~)
        out.cancelled = false;
        out.mask = logical(brainMaskVol);
        out.brainMask = logical(brainMaskVol);
        out.underlayMask = logical(brainMaskVol);
        out.overlayMask = logical(overlayMaskVol);
        out.signalMask = logical(overlayMaskVol);
        out.anatomical_reference_raw = double(Ubase);
        out.anatomical_reference = double(Ubase);

        try
            if any(brainMaskVol(:))
                out.brainImage = buildBrainImageForSave_native();
            end
        catch
        end

        notifyStudioReady();

        try
            uiresume(fig);
        catch
        end
        try
            delete(fig);
        catch
        end
    end

    function notifyStudioReady()
        try
            if isfield(studio,'statusFcn') && isa(studio.statusFcn,'function_handle')
                try
                    feval(studio.statusFcn,'Ready');
                catch
                    try
                        feval(studio.statusFcn,'Ready','Mask editor closed');
                    catch
                    end
                end
            end
        catch
        end

        try
            if isfield(studio,'logFcn') && isa(studio.logFcn,'function_handle')
                feval(studio.logFcn,'Mask editor closed. Studio ready.');
            end
        catch
        end

        try
            if isfield(studio,'figure') && ~isempty(studio.figure) && ishghandle(studio.figure)
                setappdata(studio.figure,'maskEditorOpen',false);
                setappdata(studio.figure,'maskEditorState','ready');
                figure(studio.figure);
            end
        catch
        end

        try
            if isfield(studio,'onMaskEditorClosed') && isa(studio.onMaskEditorClosed,'function_handle')
                feval(studio.onMaskEditorClosed, out);
            end
        catch
        end
    end

% -------------------- Mouse painting --------------------
    function onMouseDown(~,~)
        if ~S.editorOn
            return;
        end
        if ~isCursorOverAxes()
            return;
        end

        sel = get(fig,'SelectionType');
        if strcmp(sel,'normal')
            S.paintMode = 'add';
        elseif strcmp(sel,'alt') || strcmp(sel,'extend')
            S.paintMode = 'erase';
        else
            return;
        end

        mods = get(fig,'CurrentModifier');
        if iscell(mods) && any(strcmpi(mods,'shift'))
            S.paintMode = 'erase';
        end

        S.isPainting = true;

        xyDisp = getCursorXYdisp();
        if any(isnan(xyDisp))
            return;
        end

        [xRaw,yRaw] = disp2raw(xyDisp(1),xyDisp(2));
        S.lastRaw = [xRaw yRaw];

        stampAtRaw(xRaw,yRaw,S.z);
        renderNow();
    end

    function onMouseUp(~,~)
        stopPainting();
        renderNow();
    end

    function onMouseMove(~,~)
        if S.editorOn && isCursorOverAxes()
            renderBrushPreview();
        else
            deleteBrushPreview();
        end

        if ~S.editorOn || ~S.isPainting
            return;
        end
        if ~isCursorOverAxes()
            return;
        end

        xyDisp = getCursorXYdisp();
        if any(isnan(xyDisp))
            return;
        end

        [xRaw,yRaw] = disp2raw(xyDisp(1),xyDisp(2));

        x0 = S.lastRaw(1);
        y0 = S.lastRaw(2);

        if any(isnan([x0 y0]))
            stampAtRaw(xRaw,yRaw,S.z);
        else
            paintSegmentRaw(x0,y0,xRaw,yRaw,S.z);
        end

        S.lastRaw = [xRaw yRaw];
        renderNow();
    end

    function stopPainting()
        S.isPainting = false;
        S.paintMode = '';
        S.lastRaw = [NaN NaN];
        deleteBrushPreview();
    end

% -------------------- Render --------------------
    function renderNow()
        z = max(1, min(nZ, S.z));

        Usl_raw = Ubase(:,:,z);
        Bsl_raw = brainMaskVol(:,:,z);
        Osl_raw = overlayMaskVol(:,:,z);

        if S.flipUD_display
            Usl = flipud(Usl_raw);
            Bsl = flipud(Bsl_raw);
            Osl = flipud(Osl_raw);
        else
            Usl = Usl_raw;
            Bsl = Bsl_raw;
            Osl = Osl_raw;
        end

        if S.underlayMode == 6
            U01 = scaleFixed(Usl, S.dbLow, S.dbHigh);
        else
            U01 = scale01(Usl, S.globalScaling);
        end

        U01 = applyDisplayAdjust(U01, S.brightness, S.contrast, S.gamma, S.sharpness);
        RGB = mapToRGB(U01, S.cmapMode);

        if S.previewMasked
            keep3 = repmat(Bsl,[1 1 3]);
            tmpRGB = zeros(size(RGB),'single');
            tmpRGB(keep3) = RGB(keep3);
            RGB = tmpRGB;
        end

        % Brain mask in green
        if any(Bsl(:))
            alphaB = 0.16;
            B3 = repmat(Bsl,[1 1 3]);
            tintB = cat(3, ...
                C.brain(1)*ones(nY,nX), ...
                C.brain(2)*ones(nY,nX), ...
                C.brain(3)*ones(nY,nX));
            RGB = RGB .* (1 - alphaB*B3) + single(tintB) .* (alphaB*B3);

            Eb = edgeMask(Bsl);
            if any(Eb(:))
                e = single(Eb);
                RGB(:,:,1) = max(RGB(:,:,1), 0.18*e);
                RGB(:,:,2) = max(RGB(:,:,2), 1.00*e);
                RGB(:,:,3) = max(RGB(:,:,3), 0.28*e);
            end
        end

        % Overlay mask in orange
        if S.showOverlay && any(Osl(:))
            alphaO = max(0,min(1,double(S.overlayAlpha)));
            O3 = repmat(Osl,[1 1 3]);

            tintO = cat(3, ...
                C.overlay(1)*ones(nY,nX), ...
                C.overlay(2)*ones(nY,nX), ...
                C.overlay(3)*ones(nY,nX));

            RGB = RGB .* (1 - alphaO*O3) + single(tintO) .* (alphaO*O3);

            Eo = edgeMask(Osl);
            if any(Eo(:))
                e = single(Eo);
                RGB(:,:,1) = max(RGB(:,:,1), 1.00*e);
                RGB(:,:,2) = max(RGB(:,:,2), 0.74*e);
                RGB(:,:,3) = max(RGB(:,:,3), 0.20*e);
            end
        end

        imgH.CData = RGB;

        if nZ > 1
            txtSlice.String = sprintf('Slice %d / %d', z, nZ);
        else
            txtSlice.String = '';
        end

        try
            drawnow limitrate;
        catch
            drawnow;
        end
    end

    function brainImage = buildBrainImageForSave_native()
        brainImage = zeros(nY,nX,nZ,'single');

        for zz = 1:nZ
            Usl = Ubase(:,:,zz);
            Msl = brainMaskVol(:,:,zz);

            if S.underlayMode == 6
                U01 = scaleFixed(Usl, S.dbLow, S.dbHigh);
            else
                U01 = scale01(Usl, S.globalScaling);
            end

            U01 = applyDisplayAdjust(U01, S.brightness, S.contrast, S.gamma, S.sharpness);
            U01(~Msl) = 0;
            brainImage(:,:,zz) = single(U01);
        end

        if nZ == 1
            brainImage = brainImage(:,:,1);
        end
    end

    function updateTitle()
        set(titleText,'String',sprintf('Mask Editor - %s - %s', shortenLabel(datasetLabel,55), shortenLabel(UbaseLabel,70)));
        set(h.txtUnderlayLabel,'String',['Underlay: ' UbaseLabel]);
    end

    function updateStatus(msg)
        mode = 'OFF';
        if S.editorOn
            mode = 'ON';
        end

        viewText = 'FULL';
        if S.previewMasked
            viewText = 'MASKED';
        end

        if S.editTarget == 1
            tgt = 'Brain';
        else
            tgt = 'Overlay';
        end

        set(statusBox,'String',sprintf( ...
            'Editor=%s | View=%s | Target=%s | Brush=%d (%s) | z=%d/%d | %s', ...
            mode, viewText, tgt, S.brushR, brushShapeName(S.brushShape), S.z, nZ, msg));
        drawnow;
    end

% -------------------- Brush preview --------------------
    function renderBrushPreview()
        xy = getCursorXYdisp();
        if any(isnan(xy))
            deleteBrushPreview();
            return;
        end

        x = xy(1);
        y = xy(2);

        [px,py,lw] = brushOutlinePoly(x,y,S.brushR,S.brushShape);

        if isempty(brushPreview) || ~isgraphics(brushPreview)
            brushPreview = plot(ax, px, py, '-', 'LineWidth', lw);
            set(brushPreview,'HitTest','off','Clipping','on');
        else
            set(brushPreview,'XData',px,'YData',py,'LineWidth',lw);
        end

        if S.isPainting && strcmp(S.paintMode,'erase')
            set(brushPreview,'Color',C.erase);
        else
            if S.editTarget == 1
                set(brushPreview,'Color',C.brain);
            else
                set(brushPreview,'Color',C.overlay);
            end
        end
    end

    function deleteBrushPreview()
        if ~isempty(brushPreview) && isgraphics(brushPreview)
            delete(brushPreview);
        end
        brushPreview = [];
    end

% -------------------- Coord mapping --------------------
    function [xRaw,yRaw] = disp2raw(xDisp,yDisp)
        xRaw = round(xDisp);
        if S.flipUD_display
            yRaw = round(nY - yDisp + 1);
        else
            yRaw = round(yDisp);
        end
        xRaw = max(1,min(nX,xRaw));
        yRaw = max(1,min(nY,yRaw));
    end

% -------------------- Painting --------------------
    function paintSegmentRaw(x0,y0,x1,y1,z)
        dx = x1 - x0;
        dy = y1 - y0;
        nSteps = max(1, ceil(sqrt(double(dx*dx + dy*dy))));
        xs = linspace(x0, x1, nSteps);
        ys = linspace(y0, y1, nSteps);

        for ii = 1:nSteps
            stampAtRaw(round(xs(ii)), round(ys(ii)), z);
        end
    end

    function stampAtRaw(xc, yc, z)
        if xc<1 || xc>nX || yc<1 || yc>nY
            return;
        end

        if S.brushShape == 3
            penRad = max(1, round(S.brushR/10));
            setPixelsDisk(xc,yc,z,penRad);
            return;
        end

        K = getBrushKernel();
        r = brushCache.R;

        xMin = max(1, xc-r);
        xMax = min(nX, xc+r);
        yMin = max(1, yc-r);
        yMax = min(nY, yc+r);

        kx1 = 1 + (xMin - (xc-r));
        kx2 = (2*r+1) - ((xc+r) - xMax);
        ky1 = 1 + (yMin - (yc-r));
        ky2 = (2*r+1) - ((yc+r) - yMax);

        patch = K(ky1:ky2, kx1:kx2);

        if S.editTarget == 1
            if strcmp(S.paintMode,'add')
                brainMaskVol(yMin:yMax, xMin:xMax, z) = brainMaskVol(yMin:yMax, xMin:xMax, z) | patch;
            else
                brainMaskVol(yMin:yMax, xMin:xMax, z) = brainMaskVol(yMin:yMax, xMin:xMax, z) & ~patch;
            end
        else
            if strcmp(S.paintMode,'add')
                overlayMaskVol(yMin:yMax, xMin:xMax, z) = overlayMaskVol(yMin:yMax, xMin:xMax, z) | patch;
            else
                overlayMaskVol(yMin:yMax, xMin:xMax, z) = overlayMaskVol(yMin:yMax, xMin:xMax, z) & ~patch;
            end
        end
    end

    function setPixelsDisk(xc, yc, z, rad)
        rad = max(1, round(rad));
        [X,Y] = meshgrid(-rad:rad, -rad:rad);
        disk = (X.^2 + Y.^2) <= rad^2;

        xMin = max(1, xc-rad);
        xMax = min(nX, xc+rad);
        yMin = max(1, yc-rad);
        yMax = min(nY, yc+rad);

        kx1 = 1 + (xMin - (xc-rad));
        kx2 = (2*rad+1) - ((xc+rad) - xMax);
        ky1 = 1 + (yMin - (yc-rad));
        ky2 = (2*rad+1) - ((yc+rad) - yMax);

        patch = disk(ky1:ky2, kx1:kx2);

        if S.editTarget == 1
            if strcmp(S.paintMode,'add')
                brainMaskVol(yMin:yMax, xMin:xMax, z) = brainMaskVol(yMin:yMax, xMin:xMax, z) | patch;
            else
                brainMaskVol(yMin:yMax, xMin:xMax, z) = brainMaskVol(yMin:yMax, xMin:xMax, z) & ~patch;
            end
        else
            if strcmp(S.paintMode,'add')
                overlayMaskVol(yMin:yMax, xMin:xMax, z) = overlayMaskVol(yMin:yMax, xMin:xMax, z) | patch;
            else
                overlayMaskVol(yMin:yMax, xMin:xMax, z) = overlayMaskVol(yMin:yMax, xMin:xMax, z) & ~patch;
            end
        end
    end

    function invalidateBrushCache()
        brushCache.r = NaN;
        brushCache.shape = NaN;
        brushCache.K = [];
        brushCache.R = 0;
    end

    function K = getBrushKernel()
        r = max(1, round(S.brushR));
        sh = S.brushShape;
        if sh == 3
            sh = 1;
        end

        if ~isequal(brushCache.r,r) || ~isequal(brushCache.shape,sh) || isempty(brushCache.K)
            K = makeBrushKernel(r, sh);
            brushCache.r = r;
            brushCache.shape = sh;
            brushCache.K = K;
            brushCache.R = r;
        else
            K = brushCache.K;
        end
    end

% -------------------- Cursor helpers --------------------
    function tf = isCursorOverAxes()
        hhit = hittest(fig);
        axHit = ancestor(hhit,'axes');
        if isempty(axHit) || axHit ~= ax
            tf = false;
            return;
        end
        cp = get(ax,'CurrentPoint');
        x = cp(1,1);
        y = cp(1,2);
        tf = (x>=1 && x<=nX && y>=1 && y<=nY);
    end

    function xy = getCursorXYdisp()
        cp = get(ax,'CurrentPoint');
        x = round(cp(1,1));
        y = round(cp(1,2));
        if x<1 || x>nX || y<1 || y>nY
            xy = [NaN NaN];
        else
            xy = [x y];
        end
    end

% -------------------- Underlay building --------------------
    function U = computeUnderlayVolume(mode)
        U = [];
        try
            switch mode
                case 1
                    if isempty(Ucache.mip)
                        Ucache.mip = underlayMIP_Z_ofMeanT(I);
                    end
                    U = Ucache.mip;
                    UbaseLabel = 'MIP (Z) of Mean(T)';

                case 2
                    if isempty(Ucache.mean)
                        Ucache.mean = underlayMeanLinear(I);
                    end
                    U = Ucache.mean;
                    UbaseLabel = 'Mean(T) [linear]';

                case 3
                    if isempty(Ucache.median)
                        Ucache.median = underlayMedianLinear(I);
                    end
                    U = Ucache.median;
                    UbaseLabel = 'Median(T) [linear]';

                case 4
                    if isempty(Ucache.max)
                        Ucache.max = underlayMaxLinear(I);
                    end
                    U = Ucache.max;
                    UbaseLabel = 'Max(T) [linear]';

                case 5
                    if ~isempty(Ucache.external)
                        U = Ucache.external;
                        if isempty(S.externalFile)
                            UbaseLabel = 'External';
                        else
                            [~,nm,ex] = fileparts(S.externalFile);
                            UbaseLabel = ['External: ' nm ex];
                        end
                    else
                        if isempty(Ucache.mip)
                            Ucache.mip = underlayMIP_Z_ofMeanT(I);
                        end
                        U = Ucache.mip;
                        UbaseLabel = 'MIP (Z) of Mean(T)';
                    end

                case 6
                    if isempty(Ucache.imregd)
                        Ucache.imregd = underlayImregdemonsMeanDB(I);
                    end
                    U = Ucache.imregd;
                    UbaseLabel = 'imregdemons Mean (dB)';
            end

            U = double(U);
            U(~isfinite(U)) = 0;

            if ndims(U)==2
                U = reshape(U,[nY nX 1]);
            end

            if size(U,1)~=nY || size(U,2)~=nX || size(U,3)~=nZ
                U = fitUnderlayToDims(U,nY,nX,nZ);
            end
        catch
            U = [];
        end
    end

    function U = underlayMeanLinear(Iin)
        if ndims(Iin)==3
            U = mean(double(Iin),3);
            U = reshape(U,[nY nX 1]);
        else
            U = mean(double(Iin),4);
        end
    end

    function U = underlayMaxLinear(Iin)
        if ndims(Iin)==3
            U = max(double(Iin),[],3);
            U = reshape(U,[nY nX 1]);
        else
            U = max(double(Iin),[],4);
        end
    end

    function U = underlayMedianLinear(Iin)
        Iin = double(Iin);
        if ndims(Iin)==3
            T = size(Iin,3);
            idx = pickSubsampleIdx(T, 600);
            U = median(Iin(:,:,idx),3);
            U = reshape(U,[nY nX 1]);
        else
            T = size(Iin,4);
            idx = pickSubsampleIdx(T, 600);
            U = median(Iin(:,:,:,idx),4);
        end
    end

    function U = underlayMIP_Z_ofMeanT(Iin)
        if ndims(Iin) == 3
            U = mean(double(Iin),3);
            U = reshape(U,[nY nX 1]);
            return;
        end

        T = size(Iin,4);
        a0 = zeros(nY,nX,nZ,'double');
        for tt = 1:T
            a0 = a0 + double(Iin(:,:,:,tt));
        end
        a0 = a0 / max(1,T);

        mip2 = max(a0,[],3);
        U = repmat(reshape(mip2,[nY nX 1]),[1 1 nZ]);
    end

    function Udb = underlayImregdemonsMeanDB(Iin)
        if ndims(Iin)==3
            a0 = mean(double(Iin),3);
            mx = max(a0(:));
            if ~isfinite(mx) || mx <= 0
                mx = max(eps, max(a0(:)));
            end
            Udb = 20*log10(max(a0,0) / (mx + eps) + eps);
            Udb = reshape(Udb,[nY nX 1]);
        else
            a0 = mean(double(Iin),4);
            mx = max(a0(:));
            if ~isfinite(mx) || mx <= 0
                mx = max(eps, max(a0(:)));
            end
            Udb = 20*log10(max(a0,0) / (mx + eps) + eps);
        end
        Udb(~isfinite(Udb)) = S.dbLow;
    end

    function idx = pickSubsampleIdx(T, maxFrames)
        if T <= maxFrames
            idx = 1:T;
        else
            step = ceil(T/maxFrames);
            idx = 1:step:T;
        end
    end

    function U = loadUnderlayAny(fullFile)
        if ~exist(fullFile,'file')
            error('Underlay not found: %s', fullFile);
        end

        if numel(fullFile) >= 7 && strcmpi(fullFile(end-6:end), '.nii.gz')
            tmpDir = tempname;
            mkdir(tmpDir);
            gunzip(fullFile, tmpDir);
            d = dir(fullfile(tmpDir,'*.nii'));
            if isempty(d)
                error('gunzip failed');
            end
            niiFile = fullfile(tmpDir, d(1).name);
            U = double(niftiread(niiFile));
            try
                rmdir(tmpDir,'s');
            catch
            end
            U = squeezeTo2Dor3D(U);
            return;
        end

        [~,~,ext] = fileparts(fullFile);

        if strcmpi(ext,'.nii')
            U = double(niftiread(fullFile));
            U = squeezeTo2Dor3D(U);
            return;
        end

        if strcmpi(ext,'.mat')
            Sx = load(fullFile);
            U = pickNumericFromMat(Sx);
            U = double(U);
            U = squeezeTo2Dor3D(U);
            return;
        end

        A = imread(fullFile);
        A = double(A);
        if ndims(A)==3 && size(A,3)==3
            A = 0.2989*A(:,:,1) + 0.5870*A(:,:,2) + 0.1140*A(:,:,3);
        end
        U = squeezeTo2Dor3D(A);
    end

    function U = squeezeTo2Dor3D(U)
        while ndims(U) > 3
            U = mean(U, ndims(U));
        end
        if ndims(U)==2
            U = reshape(U,[size(U,1) size(U,2) 1]);
        end
    end

    function U = fitUnderlayToDims(U, ny, nx, nz)
        U = double(U);
        U(~isfinite(U)) = 0;

        if ndims(U)==2
            U2 = resize2D(U, ny, nx);
            if nz > 1
                U = repmat(U2,[1 1 nz]);
            else
                U = reshape(U2,[ny nx 1]);
            end
            return;
        end

        if ndims(U)==3
            zIn = size(U,3);
            if zIn ~= nz
                zIdx = round(linspace(1,zIn,nz));
                zIdx = max(1,min(zIn,zIdx));
                U = U(:,:,zIdx);
            end
            outVol = zeros(ny,nx,nz);
            for zz = 1:nz
                outVol(:,:,zz) = resize2D(U(:,:,zz), ny, nx);
            end
            U = outVol;
            return;
        end

        U = squeezeTo2Dor3D(U);
        U = fitUnderlayToDims(U, ny, nx, nz);
    end

    function M = fitMaskToDims(Min, ny, nx, nz)
        M = false(ny,nx,nz);

        try
            A = logical(Min);
        catch
            return;
        end

        if ismatrix(A)
            if size(A,1)==ny && size(A,2)==nx
                if nz > 1
                    M = repmat(A,[1 1 nz]);
                else
                    M(:,:,1) = A;
                end
            else
                A2 = resize2D(double(A), ny, nx) > 0.5;
                if nz > 1
                    M = repmat(A2,[1 1 nz]);
                else
                    M(:,:,1) = A2;
                end
            end
            return;
        end

        if ndims(A)==3
            zIn = size(A,3);

            if size(A,1) ~= ny || size(A,2) ~= nx
                tmp = false(ny,nx,zIn);
                for zz = 1:zIn
                    tmp(:,:,zz) = resize2D(double(A(:,:,zz)), ny, nx) > 0.5;
                end
                A = tmp;
            end

            if zIn ~= nz
                zIdx = round(linspace(1,zIn,nz));
                zIdx = max(1,min(zIn,zIdx));
                A = A(:,:,zIdx);
            end

            M = logical(A);
        end
    end

    function A = resize2D(A, ny, nx)
        if size(A,1)==ny && size(A,2)==nx
            return;
        end
        try
            A = imresize(A,[ny nx],'bilinear');
        catch
            [yy,xx] = ndgrid(linspace(1,size(A,1),ny), linspace(1,size(A,2),nx));
            A = interp2(A, xx, yy, 'linear', 0);
        end
    end

    function U = pickNumericFromMat(Sx)
        fn = fieldnames(Sx);

        for kk = 1:numel(fn)
            v = Sx.(fn{kk});
            if isstruct(v) && isfield(v,'I') && isnumeric(v.I)
                U = v.I;
                return;
            end
        end

        for kk = 1:numel(fn)
            v = Sx.(fn{kk});
            if isnumeric(v)
                U = v;
                return;
            end
        end

        error('No numeric variable found in MAT.');
    end

% -------------------- Display utils --------------------
    function U01 = scale01(U, globalFlag)
        U = double(U);
        U(~isfinite(U)) = 0;

        if ~globalFlag
            v = U(:);
            p1  = prctile(v, S.pctLow);
            p99 = prctile(v, S.pctHigh);
        else
            vAll = double(Ubase(:));
            vAll(~isfinite(vAll)) = 0;
            p1  = prctile(vAll, S.pctLow);
            p99 = prctile(vAll, S.pctHigh);
        end

        if ~isfinite(p1) || ~isfinite(p99) || p99 <= p1
            p1 = min(U(:));
            p99 = max(U(:));
            if p99 <= p1
                U01 = zeros(size(U));
                return;
            end
        end

        U = min(max(U,p1),p99);
        U01 = (U - p1) / max(eps,(p99 - p1));
        U01 = min(max(U01,0),1);
    end

    function U01 = scaleFixed(U, lo, hi)
        U = double(U);
        U(~isfinite(U)) = lo;
        if ~isfinite(lo), lo = -48; end
        if ~isfinite(hi), hi = -7; end
        if hi <= lo + 1
            hi = lo + 1;
        end
        U = min(max(U, lo), hi);
        U01 = (U - lo) / max(eps, (hi - lo));
        U01 = min(max(U01,0),1);
    end

    function U01 = applyDisplayAdjust(U01, bright, cont, gam, sharp)
        U01 = double(U01);

        U01 = U01 * cont + bright;
        U01 = min(max(U01,0),1);

        U01 = U01 .^ (1/max(eps,gam));
        U01 = min(max(U01,0),1);

        sharp = max(0, min(300, double(sharp)));
        if sharp > 0
            amountMax = 4.5;
            amount = amountMax * (1 - exp(-sharp/60));
            sigma = 1.10 + 0.90*(sharp/300);

            B = gaussBlur2D(U01, sigma);
            hi = U01 - B;
            hi = 0.35 * tanh(hi / 0.35);

            U01 = U01 + amount * hi;
            U01 = min(max(U01,0),1);
        end
    end

    function RGB = mapToRGB(U01, cmapMode)
        U01 = double(U01);
        U01 = min(max(U01,0),1);

        idx = 1 + floor(U01*255);
        idx(idx<1) = 1;
        idx(idx>256) = 256;

        switch round(cmapMode)
            case 1
                cmap = gray(256);
            case 2
                cmap = flipud(gray(256));
            case 3
                cmap = hot(256);
            case 4
                cmap = copper(256);
            case 5
                cmap = bone(256);
            otherwise
                cmap = gray(256);
        end

        RGB = reshape(cmap(idx(:),:), [size(U01,1) size(U01,2) 3]);
        RGB = single(RGB);
    end

    function B = gaussBlur2D(A, sigma)
        sigma = max(0, double(sigma));
        if sigma <= 0
            B = A;
            return;
        end
        try
            B = imgaussfilt(A, sigma);
        catch
            rad = max(1, ceil(3*sigma));
            x = -rad:rad;
            g = exp(-(x.^2)/(2*sigma^2));
            g = g / sum(g);
            B = conv2(conv2(A, g, 'same'), g', 'same');
        end
    end

% -------------------- Brush shapes --------------------
    function [px,py,lw] = brushOutlinePoly(x,y,r,shape)
        r = max(1, round(r));

        if shape == 3
            penRad = max(1, round(r/10));
            th = linspace(0,2*pi,40);
            px = x + penRad*cos(th);
            py = y + penRad*sin(th);
            lw = 1.4;
            return;
        end

        lw = 1.4;
        switch shape
            case 1
                th = linspace(0,2*pi,80);
                px = x + r*cos(th);
                py = y + r*sin(th);
            case 2
                px = [x-r x+r x+r x-r x-r];
                py = [y-r y-r y+r y+r y-r];
            case 4
                px = [x    x+r  x    x-r  x];
                py = [y-r y   y+r y   y-r];
            otherwise
                th = linspace(0,2*pi,80);
                px = x + r*cos(th);
                py = y + r*sin(th);
        end
    end

    function name = brushShapeName(v)
        switch v
            case 1
                name = 'round';
            case 2
                name = 'square';
            case 3
                name = 'pen';
            case 4
                name = 'diamond';
            otherwise
                name = 'round';
        end
    end

    function K = makeBrushKernel(r, shape)
        d = 2*r + 1;
        [X,Y] = meshgrid(-r:r, -r:r);

        switch shape
            case 1
                K = (X.^2 + Y.^2) <= r^2;
            case 2
                K = true(d,d);
            case 4
                K = (abs(X) + abs(Y)) <= r;
            otherwise
                K = (X.^2 + Y.^2) <= r^2;
        end

        K = logical(K);
    end

    function v = shapeToPopupValue(shape)
        v = shape;
        if v < 1 || v > 4
            v = 1;
        end
    end

    function shape = popupValueToShape(v)
        v = round(v);
        v = max(1, min(4, v));
        shape = v;
    end

% -------------------- Mask processing --------------------
    function M = fillHolesAllSafe(M)
        M = logical(M);
        try
            M = imfill(M,'holes');
        catch
            holes = findHolesNoIPT(M);
            M = M | holes;
        end
    end

    function holes = findHolesNoIPT(M)
        M = logical(M);
        bg = ~M;
        [Hh,Wh] = size(bg);
        visited = false(Hh,Wh);

        qy = zeros(Hh*Wh,1);
        qx = zeros(Hh*Wh,1);
        qh = 1;
        qt = 0;

        for xx = 1:Wh
            if bg(1,xx) && ~visited(1,xx)
                qt=qt+1; qy(qt)=1; qx(qt)=xx; visited(1,xx)=true;
            end
            if bg(Hh,xx) && ~visited(Hh,xx)
                qt=qt+1; qy(qt)=Hh; qx(qt)=xx; visited(Hh,xx)=true;
            end
        end
        for yy = 1:Hh
            if bg(yy,1) && ~visited(yy,1)
                qt=qt+1; qy(qt)=yy; qx(qt)=1; visited(yy,1)=true;
            end
            if bg(yy,Wh) && ~visited(yy,Wh)
                qt=qt+1; qy(qt)=yy; qx(qt)=Wh; visited(yy,Wh)=true;
            end
        end

        nbr = [-1 -1; -1 0; -1 1; 0 -1; 0 1; 1 -1; 1 0; 1 1];

        while qh <= qt
            yy = qy(qh);
            xx = qx(qh);
            qh = qh + 1;

            for kk = 1:8
                ny = yy + nbr(kk,1);
                nx = xx + nbr(kk,2);
                if ny>=1 && ny<=Hh && nx>=1 && nx<=Wh
                    if bg(ny,nx) && ~visited(ny,nx)
                        visited(ny,nx) = true;
                        qt = qt + 1;
                        qy(qt) = ny;
                        qx(qt) = nx;
                    end
                end
            end
        end

        holes = bg & ~visited;
    end

    function M = smoothMaskSafe(M, rad)
        M = logical(M);
        rad = max(0, round(rad));
        if rad == 0
            return;
        end
        try
            se = strel('disk', max(1,rad));
            M = imopen(M,se);
            M = imclose(M,se);
            M = imfill(M,'holes');
        catch
            K = ones(2*rad+1);
            K = K / sum(K(:));
            Sx = conv2(double(M), K, 'same');
            M = Sx > 0.5;
        end
    end

    function E = edgeMask(M)
        M = logical(M);
        try
            E = bwperim(M,8);
        catch
            E = M & ~erodeBinarySafe(M,1);
        end
    end

    function M = erodeBinarySafe(M, rad)
        M = logical(M);
        rad = max(1, round(rad));
        try
            se = strel('square',2*rad+1);
            M = imerode(M,se);
        catch
            K = ones(2*rad+1);
            Sx = conv2(double(M), K, 'same');
            M = Sx >= numel(K);
        end
    end

% -------------------- String helpers --------------------
    function s = shortenLabel(s, maxLen)
        if isempty(s)
            s = '';
            return;
        end
        if numel(s) > maxLen
            s = [s(1:maxLen) '...'];
        end
    end

    function stem = safeFileStem(s)
        if isempty(s)
            stem = 'dataset';
            return;
        end
        stem = regexprep(s,'[^A-Za-z0-9_]+','_');
        stem = regexprep(stem,'_+','_');
        stem = regexprep(stem,'^_','');
        stem = regexprep(stem,'_$','');
        if isempty(stem)
            stem = 'dataset';
        end
        if numel(stem) > 40
            stem = stem(1:40);
        end
    end
end