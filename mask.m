function out = mask(varargin)
% mask.m — fUSI Studio Mask Editor (MATLAB 2017b)
%
% MAIN GOAL OF THIS VERSION:
%   ? Underlay now matches Gabriel’s look by default:
%      underlay = mean(I, T) then dB: 20*log10(mean / max(mean(:)))
%      scaled with fixed dB range (default [-48  -7]) like Gabriel examples.
%
% FIXES / CHANGES:
%   1) NEW Underlay option: "Gabriel Mean (dB)" (DEFAULT)
%      - Uses fixed dB window (editable): dB low / dB high
%      - No percentile scaling in this mode (this was the mismatch!)
%   2) Removed the double toneMapSoft call; tone-mapping is now optional
%      (OFF by default to match Gabriel more closely).
%   3) Sharpness slider is truly 0..6 (halo-safe mapping).
%   4) Layout fixed: brightness/contrast/gamma/sharpness rows are correct
%      (your pasted code had duplicates/missing rows).
%   5) Saved brainImage remains NATIVE orientation (no flipud), as you wanted.
%   6) Returns Studio fields:
%        out.anatomical_reference_raw
%        out.anatomical_reference
%        out.mask
%        out.files.brainImage_mat
%
% Painting:
%   Left-drag  = ADD mask
%   Right-drag = ERASE mask
%   Shift+Left = ERASE (trackpad fallback)
%
% Key:
%   F = fill hole under/near cursor

% =========================================================
% 0) Parse inputs robustly
% =========================================================
studio = struct();
I = [];
initMask = [];
datasetLabel = 'dataset';

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
        elseif isfield(a,'I') && isnumeric(a.I)
            I = a.I;
        end
    elseif isnumeric(a)
        if isempty(I) && (ndims(a)==3 || ndims(a)==4)
            I = a;
        else
            if isempty(initMask)
                initMask = a;
            end
        end
    elseif ischar(a) || isstring(a)
        s = char(a);
        if ~isempty(s), datasetLabel = s; end
    elseif islogical(a)
        initMask = a;
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
    nY = sz(1); nX = sz(2); nZ = 1; nT = sz(3);
elseif ndI == 4
    nY = sz(1); nX = sz(2); nZ = sz(3); nT = sz(4);
else
    errordlg('mask.m: I must be 3D (Y X T) or 4D (Y X Z T).','Mask Editor');
    out = struct('cancelled',true);
    return;
end

% =========================================================
% 2) Theme
% =========================================================
C.bg0 = [0.06 0.06 0.07];
C.bg1 = [0.10 0.10 0.12];
C.bg2 = [0.14 0.14 0.16];
C.fg  = [0.92 0.92 0.92];
C.sub = [0.75 0.88 1.00];
C.ac  = [0.30 0.65 0.95];
C.ok  = [0.22 0.75 0.45];
C.bad = [0.88 0.24 0.24];
C.warn= [0.95 0.60 0.15];
C.dim = [0.30 0.30 0.34];
C.blue= [0.22 0.50 0.90];

% =========================================================
% 3) State
% =========================================================
S = struct();
S.z = max(1, round(nZ/2));

% Display orientation fix (UI only)
S.flipUD_display = true;   % applied ONLY for UI drawing/view

S.editorOn = true;
S.previewMasked = false;

% Underlay
% 1 mean linear, 2 median linear, 3 max linear, 4 external, 5 Gabriel mean dB (DEFAULT), 6 MIP(Z) of Mean(T)
S.underlayMode = 5;
S.externalFile = '';
UbaseLabel = 'Gabriel Mean (dB)';

% Gabriel dB window (editable)
S.dbLow  = -48;   % like Gabriel examples
S.dbHigh = -7;

% Display (match Gabriel look more closely by default)
S.brightness = 0.00;
S.contrast   = 1.00;
S.gamma      = 1.00;
S.sharpness  = 0.00;     % 0..100

S.globalScaling = false; % used only for linear modes
S.pctLow  = 1;
S.pctHigh = 99;

% Optional tone map (OFF by default to match Gabriel)
S.softToneMap = false;

% Colormap (display only)
S.cmapMode = 1; % 1 Gray, 2 B/W inverted, 3 Hot, 4 Copper, 5 Bone

% Vessel enhancement (optional)
S.vesselOn = false;
S.vesselPct = 99;          % fixed
S.vesselConn = 50;         % 0..250
S.vesselSigma = 6.0;       % 0..40
S.vesselStrength = 6.0;    % 0..15

% Smoothing
S.smoothSize = 8;          % 0..100

% Brush
S.brushR = 18;             % 1..200
S.brushShape = 1;          % 1 round, 2 square, 3 linear pen, 4 diamond

% Painting
S.isPainting = false;
S.paintMode = '';
S.lastRaw = [NaN NaN];

% Brush cache
brushCache = struct('r',NaN,'shape',NaN,'K',[],'R',0);

% Mask volume (stored in NATIVE coordinates)
maskVol = false(nY,nX,nZ);

% Apply init mask if valid
if ~isempty(initMask)
    try
        M = logical(initMask);
        if nZ == 1
            if isequal(size(M),[nY nX])
                maskVol(:,:,1) = M;
            elseif ndims(M)==3 && isequal(size(M),[nY nX 1])
                maskVol(:,:,1) = M(:,:,1);
            end
        else
            if isequal(size(M),[nY nX nZ])
                maskVol = M;
            end
        end
    catch
    end
end

% Build underlay base (stored NATIVE)
Ubase = computeUnderlayVolume(S.underlayMode);
if isempty(Ubase)
    if ndI==3
        Ubase = double(I(:,:,1));
        Ubase = reshape(Ubase,[nY nX 1]);
    else
        Utmp = double(I(:,:,S.z,1));
        Ubase = repmat(reshape(Utmp,[nY nX 1]),[1 1 nZ]);
    end
    UbaseLabel = 'Fallback';
end

% =========================================================
% 4) Output defaults
% =========================================================
out = struct();
out.cancelled = true;
out.mask = [];
out.brainImage = [];
out.anatomical_reference_raw = [];
out.anatomical_reference     = [];
out.files = struct();
out.files.brainImage_mat = '';

% =========================================================
% 5) Figure / axes
% =========================================================
fig = figure( ...
    'Name','Mask Editor', ...
    'Color',C.bg0, ...
    'MenuBar','none','ToolBar','none','NumberTitle','off', ...
    'Position',[200 60 1750 990], ...
    'Resize','on');

try, set(fig,'Renderer','opengl'); catch, end

set(fig,'CloseRequestFcn',@onCloseCancel);
set(fig,'SizeChangedFcn',@onResize);

titleText = uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.955 0.62 0.035], ...
    'BackgroundColor',C.bg0,'ForegroundColor',C.fg, ...
    'FontSize',16,'FontWeight','bold', ...
    'HorizontalAlignment','center', ...
    'String','Mask Editor');

ax = axes('Parent',fig,'Units','normalized','Position',[0.03 0.08 0.62 0.86], ...
    'Color',[0 0 0]);
hold(ax,'on');
axis(ax,'image'); axis(ax,'off');
set(ax,'XLim',[0.5 nX+0.5],'YLim',[0.5 nY+0.5], ...
       'XLimMode','manual','YLimMode','manual');
axis(ax,'manual');
set(ax,'YDir','normal');

imgH = image(ax, zeros(nY,nX,3,'single'));
set(imgH,'HitTest','on');
try, set(imgH,'Interpolation','nearest'); catch, end

txtSlice = text(ax, 0.99, 0.02, '', 'Units','normalized', ...
    'Color',[0.80 0.90 1.00],'FontSize',12,'FontWeight','bold', ...
    'HorizontalAlignment','right','VerticalAlignment','bottom', ...
    'Interpreter','none');

brushPreview = [];
statusBox = uicontrol('Style','text','Parent',fig,'Units','normalized', ...
    'Position',[0.03 0.01 0.62 0.06], ...
    'BackgroundColor',C.bg0,'ForegroundColor',[0.75 0.90 1.00], ...
    'FontName','Courier New','FontSize',12, ...
    'HorizontalAlignment','left', ...
    'String','');

% =========================================================
% 6) Right panel
% =========================================================
panel = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.68 0.08 0.29 0.90], ...
    'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
    'Title','Mask Controls','FontSize',13,'FontWeight','bold');

% --- LAYOUT FIX (ONLY): give ctrlPanel more height so Clear/Fill are not cut off
bottomPanel = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.03 0.02 0.94 0.22], ...
    'BackgroundColor',C.bg1,'BorderType','none');

ctrlPanel = uipanel('Parent',panel,'Units','normalized', ...
    'Position',[0.03 0.25 0.94 0.73], ...
    'BackgroundColor',C.bg1,'BorderType','none');

% =========================================================
% 7) Controls
% =========================================================
h = struct(); b = struct();
FS_T = 12; FS_L = 11; FS_B = 11; FS_S = 11;

    function t = makeTitle(parent, str)
        t = uicontrol('Style','text','Parent',parent,'String',str, ...
            'BackgroundColor',C.bg1,'ForegroundColor',C.sub, ...
            'FontSize',FS_T,'FontWeight','bold','HorizontalAlignment','left');
    end
    function l = makeLabel(parent, str)
        l = uicontrol('Style','text','Parent',parent,'String',str, ...
            'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
            'FontSize',FS_L,'HorizontalAlignment','left');
    end
    function [lbl, sl, txt] = makeSliderRow(parent, label, vmin, vmax, v0, cb, fmt)
        if nargin < 8 || isempty(fmt), fmt = '%.2f'; end
        lbl = makeLabel(parent,label);
        sl = uicontrol('Style','slider','Parent',parent, ...
            'Min',vmin,'Max',vmax,'Value',v0, ...
            'Callback',cb);
        txt = uicontrol('Style','text','Parent',parent,'String',sprintf(fmt,v0), ...
            'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
            'FontSize',FS_S,'HorizontalAlignment','right');
    end

h.togEditor = uicontrol('Style','togglebutton','Parent',ctrlPanel, ...
    'String','Editor ON','Value',1, ...
    'BackgroundColor',C.ok,'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold', ...
    'Callback',@onToggleEditor);

h.togPreview = uicontrol('Style','togglebutton','Parent',ctrlPanel, ...
    'String','Preview: FULL','Value',0, ...
    'BackgroundColor',C.ac,'ForegroundColor','w', ...
    'FontSize',12,'FontWeight','bold', ...
    'Callback',@onTogglePreview);

% Underlay
h.underTitle = makeTitle(ctrlPanel,'Underlay');
h.popUnderlay = uicontrol('Style','popupmenu','Parent',ctrlPanel, ...
    'String',{'Mean (T) [linear]', ...
          'Median (T) [linear]', ...
          'Max (T) [linear]', ...
          'External file...', ...
          'Gabriel Mean (dB) [DEFAULT]', ...
          'MIP (Z) of Mean(T) [linear]'}, ...
    'Value',S.underlayMode, ...
    'BackgroundColor',C.bg2,'ForegroundColor','w', ...
    'FontSize',FS_L, ...
    'Callback',@onUnderlayMode);

h.btnLoadUnderlay = uicontrol('Style','pushbutton','Parent',ctrlPanel, ...
    'String','Load external underlay', ...
    'BackgroundColor',C.dim,'ForegroundColor','w', ...
    'FontSize',FS_B,'FontWeight','bold', ...
    'Callback',@onLoadExternal);

h.chkGlobal = uicontrol('Style','checkbox','Parent',ctrlPanel, ...
    'String','Global scaling (linear modes only)', ...
    'Value',double(S.globalScaling), ...
    'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
    'FontSize',FS_L, ...
    'Callback',@onGlobalScaling);

h.txtUnderlayLabel = uicontrol('Style','text','Parent',ctrlPanel, ...
    'String',['Underlay: ' UbaseLabel], ...
    'BackgroundColor',C.bg1,'ForegroundColor',[0.70 0.85 1], ...
    'FontName','Courier New','FontSize',11, ...
    'HorizontalAlignment','left');

% Gabriel dB range (enabled only in dB mode)
h.dbTitle = makeTitle(ctrlPanel,'Gabriel dB window');
h.lblDbLow  = makeLabel(ctrlPanel,'dB low');
h.edDbLow   = uicontrol('Style','edit','Parent',ctrlPanel,'String',num2str(S.dbLow), ...
    'BackgroundColor',C.bg2,'ForegroundColor','w','FontSize',FS_L,'Callback',@onDbEdit);
h.lblDbHigh = makeLabel(ctrlPanel,'dB high');
h.edDbHigh  = uicontrol('Style','edit','Parent',ctrlPanel,'String',num2str(S.dbHigh), ...
    'BackgroundColor',C.bg2,'ForegroundColor','w','FontSize',FS_L,'Callback',@onDbEdit);

% Display
h.dispTitle = makeTitle(ctrlPanel,'Display');
[h.lblBright,h.slBright,h.txtBright] = makeSliderRow(ctrlPanel,'Brightness',-0.6,0.6,S.brightness,@onDisplayChange,'%.2f');
[h.lblCont,  h.slCont,  h.txtCont]   = makeSliderRow(ctrlPanel,'Contrast',0.5,3.0,S.contrast,@onDisplayChange,'%.2f');
[h.lblGamma, h.slGamma, h.txtGamma]  = makeSliderRow(ctrlPanel,'Gamma',0.2,3.0,S.gamma,@onDisplayChange,'%.2f');
[h.lblSharp, h.slSharp, h.txtSharp]  = makeSliderRow(ctrlPanel,'Sharpness',0,100,S.sharpness,@onDisplayChange,'%.2f');

h.chkTone = uicontrol('Style','checkbox','Parent',ctrlPanel, ...
    'String','Soft tone map (optional)', ...
    'Value',double(S.softToneMap), ...
    'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
    'FontSize',FS_L, ...
    'Callback',@onToneToggle);

% Vessels
h.vTitle = makeTitle(ctrlPanel,'Enhance vessels');
h.chkVessel = uicontrol('Style','checkbox','Parent',ctrlPanel, ...
    'String','Enable vessel enhancement', ...
    'Value',double(S.vesselOn), ...
    'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
    'FontSize',FS_L, ...
    'Callback',@onVesselToggle);

[h.lblVConn,h.slVConn,h.txtVConn] = makeSliderRow(ctrlPanel,'Connect size',0,250,S.vesselConn,@onVesselChange,'%.0f');
[h.lblVSig, h.slVSig, h.txtVSig]  = makeSliderRow(ctrlPanel,'Sigma',0,40,S.vesselSigma,@onVesselChange,'%.1f');
[h.lblVStr, h.slVStr, h.txtVStr]  = makeSliderRow(ctrlPanel,'Strength',0,15,S.vesselStrength,@onVesselChange,'%.1f');

% Slice
if nZ > 1
    h.sliceTitle = makeTitle(ctrlPanel,'Slice');
    h.slSlice = uicontrol('Style','slider','Parent',ctrlPanel, ...
        'Min',1,'Max',nZ,'Value',S.z, ...
        'SliderStep',[1/max(1,nZ-1) 5/max(1,nZ-1)], ...
        'Callback',@onSliceChange);
    h.txtSliceVal = uicontrol('Style','text','Parent',ctrlPanel, ...
        'String',sprintf('z = %d / %d (scroll wheel)',S.z,nZ), ...
        'BackgroundColor',C.bg1,'ForegroundColor',C.fg, ...
        'FontSize',FS_L,'HorizontalAlignment','left');
else
    h.sliceTitle = [];
    h.slSlice = [];
    h.txtSliceVal = [];
end

% Smoothing
h.smoothTitle = makeTitle(ctrlPanel,'Smoothing');
[h.lblSmooth,h.slSmooth,h.txtSmooth] = makeSliderRow(ctrlPanel,'Size',0,100,S.smoothSize,@onSmoothSize,'%.0f');
h.btnSmooth = uicontrol('Style','pushbutton','Parent',ctrlPanel, ...
    'String','Smooth current slice', ...
    'BackgroundColor',C.dim,'ForegroundColor','w', ...
    'FontSize',FS_B,'FontWeight','bold', ...
    'Callback',@onSmooth);

% Mask tools
h.toolsTitle = makeTitle(ctrlPanel,'Mask tools');
h.btnClearSlice = uicontrol('Style','pushbutton','Parent',ctrlPanel, ...
    'String','Clear Slice', ...
    'BackgroundColor',C.warn,'ForegroundColor','w', ...
    'FontSize',FS_B,'FontWeight','bold', ...
    'Callback',@onClearSlice);

h.btnClearMask = uicontrol('Style','pushbutton','Parent',ctrlPanel, ...
    'String','Clear Mask', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontSize',FS_B,'FontWeight','bold', ...
    'Callback',@onClearMask);

h.btnFillHolesAll = uicontrol('Style','pushbutton','Parent',ctrlPanel, ...
    'String','Fill holes (slice)   [Key: F]', ...
    'BackgroundColor',C.dim,'ForegroundColor','w', ...
    'FontSize',FS_B,'FontWeight','bold', ...
    'Callback',@onFillHolesAll);

% Bottom panel: Brush + Save/Help/Close + Colormap
b.brushTitle = uicontrol('Style','text','Parent',bottomPanel,'String','Brush', ...
    'BackgroundColor',C.bg1,'ForegroundColor',C.sub, ...
    'FontSize',FS_T,'FontWeight','bold','HorizontalAlignment','left');

[b.lblBrush,b.slBrush,b.txtBrush] = makeSliderRow(bottomPanel,'Radius',1,200,S.brushR,@onBrushChange,'%.0f');

b.lblKind = makeLabel(bottomPanel,'Kind');
b.popShape = uicontrol('Style','popupmenu','Parent',bottomPanel, ...
    'String',{'Round','Quadratic','Linear (freehand pen)','Diamond'}, ...
    'Value',shapeToPopupValue(S.brushShape), ...
    'BackgroundColor',C.bg2,'ForegroundColor','w', ...
    'FontSize',FS_L, ...
    'Callback',@onShapeChange);

b.lblCmap = makeLabel(bottomPanel,'Colors');
b.popCmap = uicontrol('Style','popupmenu','Parent',bottomPanel, ...
    'String',{'Gray','B/W (inverted)','Hot','Copper','Bone'}, ...
    'Value',S.cmapMode, ...
    'BackgroundColor',C.bg2,'ForegroundColor','w', ...
    'FontSize',FS_L, ...
    'Callback',@onCmapChange);

b.btnSave = uicontrol('Style','pushbutton','Parent',bottomPanel, ...
    'String','SAVE', ...
    'BackgroundColor',C.ok,'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Callback',@onSaveOnly);

b.btnHelp = uicontrol('Style','pushbutton','Parent',bottomPanel, ...
    'String','HELP', ...
    'BackgroundColor',C.blue,'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Callback',@onHelp);

b.btnClose = uicontrol('Style','pushbutton','Parent',bottomPanel, ...
    'String','CLOSE', ...
    'BackgroundColor',C.bad,'ForegroundColor','w', ...
    'FontSize',13,'FontWeight','bold', ...
    'Callback',@onCloseReturn);

% =========================================================
% 8) Window callbacks
% =========================================================
set(fig,'WindowButtonDownFcn',@onMouseDown);
set(fig,'WindowButtonUpFcn',@onMouseUp);
set(fig,'WindowButtonMotionFcn',@onMouseMove);
set(fig,'WindowScrollWheelFcn',@onScrollWheel);
set(fig,'KeyPressFcn',@onKey);

updateTitle();
relayoutAll();
applyVesselControlsEnabled(S.vesselOn);
updateDbControlsEnabled();
updateStatus('Ready. Left=ADD, Right=ERASE. Press F to fill hole under cursor.');
renderNow();

uiwait(fig);

% =========================================================
% ======================= NESTED FUNCS ======================
% =========================================================
    function onResize(~,~)
        relayoutAll();
        renderNow();
    end

    function relayoutAll()
        pC = getpixelposition(ctrlPanel);
        W = pC(3); Hh = pC(4);
        pad = 6; gap = 4;

        Htog = 32;
        Htitle = 18;
        Hpop = 26;
        Hbtn = 28;
        Hchk = 22;
        Htxt = 18;
        HsLbl = 18;
        HsSld = 16;
        Hed  = 24;

        x = pad;
        w = W - 2*pad;
        y = Hh - pad;

        w2 = floor((w - gap)/2);
        setpixelposition(h.togEditor,[x y-Htog w2 Htog]);
        setpixelposition(h.togPreview,[x+w2+gap y-Htog w2 Htog]);
        y = y - Htog - gap;

        % Underlay
        setpixelposition(h.underTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        setpixelposition(h.popUnderlay,[x y-Hpop w Hpop]); y = y - Hpop - gap;
        setpixelposition(h.btnLoadUnderlay,[x y-Hbtn w Hbtn]); y = y - Hbtn - gap;
        setpixelposition(h.chkGlobal,[x y-Hchk w Hchk]); y = y - Hchk - 2;
        setpixelposition(h.txtUnderlayLabel,[x y-Htxt w Htxt]); y = y - Htxt - (gap+1);

        % Gabriel dB window block
        setpixelposition(h.dbTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        setpixelposition(h.lblDbLow,[x y-HsLbl 70 HsLbl]);
        setpixelposition(h.edDbLow,[x+72 y-Hed 90 Hed]);
        setpixelposition(h.lblDbHigh,[x+170 y-HsLbl 70 HsLbl]);
        setpixelposition(h.edDbHigh,[x+242 y-Hed 90 Hed]);
        y = y - Hed - (gap+2);

        % Display
        setpixelposition(h.dispTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        y = layoutSliderRow(h.lblBright,h.slBright,h.txtBright,y,'%.2f');
        y = layoutSliderRow(h.lblCont,  h.slCont,  h.txtCont,  y,'%.2f');
        y = layoutSliderRow(h.lblGamma, h.slGamma, h.txtGamma, y,'%.2f');
        y = layoutSliderRow(h.lblSharp, h.slSharp, h.txtSharp, y,'%.2f');
        setpixelposition(h.chkTone,[x y-Hchk w Hchk]); y = y - Hchk - (gap+1);

        % Vessels
        setpixelposition(h.vTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        setpixelposition(h.chkVessel,[x y-Hchk w Hchk]); y = y - Hchk - 2;
        y = layoutSliderRow(h.lblVConn,h.slVConn,h.txtVConn,y,'%.0f');
        y = layoutSliderRow(h.lblVSig, h.slVSig, h.txtVSig, y,'%.1f');
        y = layoutSliderRow(h.lblVStr, h.slVStr, h.txtVStr, y,'%.1f');
        y = y - (gap+1);

        % Slice
        if nZ > 1
            setpixelposition(h.sliceTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
            setpixelposition(h.slSlice,[x y-HsSld w HsSld]); y = y - HsSld - 2;
            setpixelposition(h.txtSliceVal,[x y-Htxt w Htxt]); y = y - Htxt - (gap+1);
        end

        % Smoothing
        setpixelposition(h.smoothTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        y = layoutSliderRow(h.lblSmooth,h.slSmooth,h.txtSmooth,y,'%.0f');
        setpixelposition(h.btnSmooth,[x y-Hbtn w Hbtn]); y = y - Hbtn - (gap+1);

        % Tools
        setpixelposition(h.toolsTitle,[x y-Htitle w Htitle]); y = y - Htitle - 2;
        w2b = floor((w - gap)/2);
        setpixelposition(h.btnClearSlice,[x y-Hbtn w2b Hbtn]);
        setpixelposition(h.btnClearMask,[x+w2b+gap y-Hbtn w2b Hbtn]);
        y = y - Hbtn - gap;
        setpixelposition(h.btnFillHolesAll,[x y-Hbtn w Hbtn]);

        % External enable
        if get(h.popUnderlay,'Value') == 4
            set(h.btnLoadUnderlay,'Enable','on','BackgroundColor',C.dim);
        else
            set(h.btnLoadUnderlay,'Enable','off','BackgroundColor',[0.22 0.22 0.25]);
        end

        % Bottom panel
        pB = getpixelposition(bottomPanel);
        WB = pB(3); HB = pB(4);
        xb = pad; wb = WB - 2*pad;

        % --- tiny layout tweak (ONLY): move brush block slightly DOWN
        yb = HB - pad - 8;

        setpixelposition(b.brushTitle,[xb yb-Htitle wb Htitle]); yb = yb - Htitle - 2;

        setpixelposition(b.lblBrush,[xb yb-HsLbl 70 HsLbl]);
        setpixelposition(b.txtBrush,[xb+wb-60 yb-HsLbl 60 HsLbl]);
        setpixelposition(b.slBrush,[xb+72 yb-HsSld wb-72-62 HsSld]);
        yb = yb - HsLbl - gap;

        setpixelposition(b.lblKind,[xb yb-HsLbl 70 HsLbl]);
        setpixelposition(b.popShape,[xb+72 yb-Hpop wb-72 Hpop]);
        yb = yb - Hpop - gap;

        setpixelposition(b.lblCmap,[xb yb-HsLbl 70 HsLbl]);
        setpixelposition(b.popCmap,[xb+72 yb-Hpop wb-72 Hpop]);
        yb = yb - Hpop - gap;

        btnH2 = 36; btnGap = 6;
        btnW = floor((wb - 2*btnGap)/3);
        setpixelposition(b.btnSave,[xb 6 btnW btnH2]);
        setpixelposition(b.btnHelp,[xb+btnW+btnGap 6 btnW btnH2]);
        setpixelposition(b.btnClose,[xb+2*(btnW+btnGap) 6 btnW btnH2]);

        function yout = layoutSliderRow(lbl, sl, txt, ycur, fmt)
            setpixelposition(lbl,[x ycur-(HsLbl) 95 HsLbl]);
            setpixelposition(txt,[x+w-60 ycur-(HsLbl) 60 HsLbl]);
            setpixelposition(sl,[x+98 ycur-(HsSld) w-98-62 HsSld]);
            yout = ycur - HsLbl - gap;
            try
                v = get(sl,'Value');
                set(txt,'String',sprintf(fmt,v));
            catch
            end
        end
    end

% -------------------- UI actions --------------------
    function onToggleEditor(src,~)
        S.editorOn = logical(get(src,'Value'));
        if S.editorOn
            set(src,'String','Editor ON','BackgroundColor',C.ok);
            updateStatus('Editor ON.');
        else
            set(src,'String','Editor OFF','BackgroundColor',C.bad);
            stopPainting();
            updateStatus('Editor OFF.');
        end
        renderNow();
    end

    function onTogglePreview(src,~)
        S.previewMasked = logical(get(src,'Value'));
        if S.previewMasked
            set(src,'String','Preview: MASKED');
            updateStatus('Preview MASKED.');
        else
            set(src,'String','Preview: FULL');
            updateStatus('Preview FULL.');
        end
        renderNow();
    end

    function onUnderlayMode(src,~)
        S.underlayMode = get(src,'Value');
        if S.underlayMode == 4
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
            set(h.popUnderlay,'Value',5);
            S.underlayMode = 5;
            Ubase = computeUnderlayVolume(5);
            updateTitle();
            updateDbControlsEnabled();
            renderNow();
            return;
        end

        S.externalFile = fullfile(p,f);
        try
            tmp = loadUnderlayAny(S.externalFile);
            tmp = fitUnderlayToDims(tmp, nY, nX, nZ);
            Ubase = double(tmp);
            S.underlayMode = 4;
            set(h.popUnderlay,'Value',4);

            [~,nm,ex] = fileparts(f);
            UbaseLabel = ['External: ' nm ex];
            updateTitle();
            updateDbControlsEnabled();
            updateStatus('External underlay loaded.');
            renderNow();
        catch ME
            errordlg(ME.message,'External underlay failed');
            set(h.popUnderlay,'Value',5);
            S.underlayMode = 5;
            Ubase = computeUnderlayVolume(5);
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

    function onDisplayChange(~,~)
        S.brightness = get(h.slBright,'Value');
        S.contrast   = get(h.slCont,'Value');
        S.gamma      = get(h.slGamma,'Value');
        S.sharpness  = get(h.slSharp,'Value');

        set(h.txtBright,'String',sprintf('%.2f',S.brightness));
        set(h.txtCont,  'String',sprintf('%.2f',S.contrast));
        set(h.txtGamma, 'String',sprintf('%.2f',S.gamma));
        set(h.txtSharp, 'String',sprintf('%.2f',S.sharpness));
        renderNow();
    end

    function onToneToggle(src,~)
        S.softToneMap = logical(get(src,'Value'));
        renderNow();
    end

    function onVesselToggle(src,~)
        S.vesselOn = logical(get(src,'Value'));
        applyVesselControlsEnabled(S.vesselOn);
        renderNow();
    end

    function onVesselChange(~,~)
        S.vesselConn = get(h.slVConn,'Value');
        S.vesselSigma = get(h.slVSig,'Value');
        S.vesselStrength = get(h.slVStr,'Value');

        set(h.txtVConn,'String',sprintf('%.0f',S.vesselConn));
        set(h.txtVSig,'String',sprintf('%.1f',S.vesselSigma));
        set(h.txtVStr,'String',sprintf('%.1f',S.vesselStrength));
        renderNow();
    end

    function applyVesselControlsEnabled(tf)
        if tf, en='on'; col=C.bg2; else, en='off'; col=[0.22 0.22 0.25]; end
        set(h.slVConn,'Enable',en,'BackgroundColor',col);
        set(h.slVSig, 'Enable',en,'BackgroundColor',col);
        set(h.slVStr, 'Enable',en,'BackgroundColor',col);
    end

    function updateDbControlsEnabled()
        isDb = (S.underlayMode == 5);
        if isDb
            set(h.dbTitle,'Enable','on');
            set(h.lblDbLow,'Enable','on');  set(h.edDbLow,'Enable','on');
            set(h.lblDbHigh,'Enable','on'); set(h.edDbHigh,'Enable','on');
            set(h.chkGlobal,'Enable','off');
        else
            set(h.dbTitle,'Enable','off');
            set(h.lblDbLow,'Enable','off');  set(h.edDbLow,'Enable','off');
            set(h.lblDbHigh,'Enable','off'); set(h.edDbHigh,'Enable','off');
            set(h.chkGlobal,'Enable','on');
        end
    end

    function onSliceChange(src,~)
        S.z = max(1, min(nZ, round(get(src,'Value'))));
        if ~isempty(h.txtSliceVal) && isgraphics(h.txtSliceVal)
            set(h.txtSliceVal,'String',sprintf('z = %d / %d (scroll wheel)',S.z,nZ));
        end
        renderNow();
    end

    function onCmapChange(src,~)
        S.cmapMode = get(src,'Value');
        renderNow();
    end

    function onScrollWheel(~,evt)
        if nZ <= 1, return; end
        if ~isCursorOverAxes(), return; end
        dz = -sign(evt.VerticalScrollCount);
        if dz == 0, return; end
        S.z = max(1, min(nZ, S.z + dz));
        if ~isempty(h.slSlice) && isgraphics(h.slSlice), set(h.slSlice,'Value',S.z); end
        if ~isempty(h.txtSliceVal) && isgraphics(h.txtSliceVal)
            set(h.txtSliceVal,'String',sprintf('z = %d / %d (scroll wheel)',S.z,nZ));
        end
        renderNow();
    end

    function onSmoothSize(~,~)
        S.smoothSize = max(0, round(get(h.slSmooth,'Value')));
        set(h.txtSmooth,'String',sprintf('%d',S.smoothSize));
    end

    function onSmooth(~,~)
        z = S.z;
        maskVol(:,:,z) = smoothMaskSafe(maskVol(:,:,z), S.smoothSize);
        updateStatus('Smoothed current slice.');
        renderNow();
    end

    function onClearSlice(~,~)
        maskVol(:,:,S.z) = false;
        updateStatus(sprintf('Cleared slice %d.',S.z));
        renderNow();
    end

    function onClearMask(~,~)
        maskVol(:) = false;
        updateStatus('Cleared mask.');
        renderNow();
    end

    function onFillHolesAll(~,~)
        z = S.z;
        maskVol(:,:,z) = fillHolesAllSafe(maskVol(:,:,z));
        updateStatus('Filled holes (current slice).');
        renderNow();
    end

    function onBrushChange(~,~)
        S.brushR = max(1, round(get(b.slBrush,'Value')));
        set(b.txtBrush,'String',sprintf('%d',S.brushR));
        invalidateBrushCache();
        renderNow();
    end

    function onShapeChange(src,~)
        S.brushShape = popupValueToShape(get(src,'Value'));
        invalidateBrushCache();
        stopPainting();
        renderNow();
    end

    function onHelp(~,~)
        msg = {
            'Mask Editor — Help'
            ' '
            'UNDERLAY MATCH (Gabriel)'
            '  • Default = Gabriel Mean (dB)'
            '  • dB = 20*log10(mean(I)/max(mean(I)))'
            '  • Scaled with dB window (default [-48 -7])'
            ' '
            'PAINT'
            '  • Left drag  = ADD mask'
            '  • Right drag = ERASE mask'
            '  • Shift+Left = ERASE (trackpad fallback)'
            ' '
            'FILL HOLES'
            '  • Button: fill holes in current slice'
            '  • Key F: fill hole under/near cursor'
            ' '
            'SAVE'
            '  • Saves ONE file with ONE variable: brainImage'
            '  • brainImage = masked underlay (outside = 0), native orientation'
        };
        msgbox(msg,'Mask Editor','help');
    end

    function onKey(~,evt)
        if ~isfield(evt,'Key'), return; end
        k = lower(evt.Key);
        switch k
            case 'f'
                if isCursorOverAxes()
                    xyDisp = getCursorXYdisp();
                    if all(isfinite(xyDisp))
                        [xRaw,yRaw] = disp2raw(xyDisp(1), xyDisp(2));
                        z = S.z;
                        [M2, didFill] = fillHoleAtOrNearPoint(maskVol(:,:,z), xRaw, yRaw, 18);
                        if didFill
                            maskVol(:,:,z) = M2;
                            updateStatus('Filled hole (F).');
                            renderNow();
                        else
                            updateStatus('F: no closed hole under/near cursor.');
                        end
                    end
                end
        end
    end

  function onSaveOnly(~,~)
    if ~any(maskVol(:))
        errordlg('Mask is empty. Draw the brain first, then SAVE.','Mask Editor');
        return;
    end

    % Build brain-only image (masked underlay; outside = 0), native orientation
    brainImage = buildBrainImageForSave_native(); 

    % Also save the binary brain mask (native orientation)
    brainMask = logical(maskVol); 
    if nZ == 1
        brainMask = brainMask(:,:,1);
    end

    visDir = fullfile(studio.exportPath,'Visualization');
    if ~exist(visDir,'dir'), mkdir(visDir); end
    ts = datestr(now,'yyyymmdd_HHMMSS');

    outFile = fullfile(visDir, sprintf('BrainOnly_%s_%s.mat', safeFileStem(datasetLabel), ts));

    try
        % Save both variables in ONE file
        save(outFile,'brainImage','brainMask','-v7.3');
    catch ME
        errordlg(ME.message,'Save failed');
        return;
    end

    out.files.brainImage_mat = outFile;
    out.brainImage = brainImage;

    % Keep the output mask updated too
    out.mask = logical(maskVol);

    updateStatus(['Saved: ' outFile]);
    try
        hmsg = msgbox('Saved brainImage and brainMask (native orientation).','Mask Editor','help');
        try
            pause(0.35);
            if ishandle(hmsg), close(hmsg); end
        catch
        end
    catch
    end
end

    function onCloseReturn(~,~)
        out.cancelled = false;
        out.mask = logical(maskVol);

        out.anatomical_reference_raw = double(Ubase);
        out.anatomical_reference     = double(Ubase);

        try
            if any(maskVol(:))
                out.brainImage = buildBrainImageForSave_native();
            end
        catch
        end

        try, uiresume(fig); catch, end
        try, delete(fig); catch, end
    end

    function onCloseCancel(~,~)
        out.cancelled = true;
        try, uiresume(fig); catch, end
        try, delete(fig); catch, end
    end

% -------------------- Mouse painting --------------------
    function onMouseDown(~,~)
        if ~S.editorOn, return; end
        if ~isCursorOverAxes(), return; end

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
        if any(isnan(xyDisp)), return; end
        [xRaw,yRaw] = disp2raw(xyDisp(1), xyDisp(2));
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

        if ~S.editorOn || ~S.isPainting, return; end
        if ~isCursorOverAxes(), return; end

        xyDisp = getCursorXYdisp();
        if any(isnan(xyDisp)), return; end
        [xRaw,yRaw] = disp2raw(xyDisp(1), xyDisp(2));

        x0 = S.lastRaw(1); y0 = S.lastRaw(2);
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
        Msl_raw = maskVol(:,:,z);

        if S.flipUD_display
            Usl = flipud(Usl_raw);
            Msl = flipud(Msl_raw);
        else
            Usl = Usl_raw;
            Msl = Msl_raw;
        end

        % Scaling: KEY FIX for Gabriel match
        if S.underlayMode == 5
            U01 = scaleFixed(Usl, S.dbLow, S.dbHigh);   % fixed dB window
        else
            U01 = scale01(Usl, S.globalScaling);        % percentile (linear modes)
        end

        U01 = applyDisplayAdjust(U01, S.brightness, S.contrast, S.gamma, S.sharpness);

        if S.vesselOn && S.vesselStrength > 0
            U01 = applyVesselEnhance_Safer(U01, S.vesselSigma, S.vesselConn, S.vesselStrength);
        end

        if S.softToneMap
            U01 = toneMapSoft(U01);
        end

        RGB = mapToRGB(U01, S.cmapMode);

        if S.previewMasked
            keep3 = repmat(Msl,[1 1 3]);
            outRGB = zeros(size(RGB),'single');
            outRGB(keep3) = RGB(keep3);
            RGB = outRGB;
        else
            if any(Msl(:))
                tint  = cat(3, 0.6*ones(nY,nX), 0.6*ones(nY,nX), 0.6*ones(nY,nX));
                alpha = 0.08;
                M3 = repmat(Msl,[1 1 3]);
                RGB = RGB .* (1 - alpha*M3) + single(tint) .* (alpha*M3);

                E = edgeMask(Msl);
                if any(E(:))
                    e = single(E);
                    RGB(:,:,1) = max(RGB(:,:,1), e);
                    RGB(:,:,2) = max(RGB(:,:,2), e);
                    RGB(:,:,3) = max(RGB(:,:,3), e);
                end
            end
        end

        imgH.CData = RGB;

        if nZ > 1
            txtSlice.String = sprintf('Slice %d / %d', z, nZ);
        else
            txtSlice.String = '';
        end

        drawnow;
    end

    function brainImage = buildBrainImageForSave_native()
        brainImage = zeros(nY,nX,nZ,'single');

        for zz = 1:nZ
            Usl = Ubase(:,:,zz);   % native
            Msl = maskVol(:,:,zz); % native

            if S.underlayMode == 5
                U01 = scaleFixed(Usl, S.dbLow, S.dbHigh);
            else
                U01 = scale01(Usl, S.globalScaling);
            end

            U01 = applyDisplayAdjust(U01, S.brightness, S.contrast, S.gamma, S.sharpness);

            if S.vesselOn && S.vesselStrength > 0
                U01 = applyVesselEnhance_Safer(U01, S.vesselSigma, S.vesselConn, S.vesselStrength);
            end

            if S.softToneMap
                U01 = toneMapSoft(U01);
            end

            U01(~Msl) = 0;
            brainImage(:,:,zz) = single(U01);
        end

        if nZ == 1
            brainImage = brainImage(:,:,1);
        end
    end

    function updateTitle()
        set(titleText,'String',sprintf('Mask Editor — %s — %s', shortenLabel(datasetLabel, 55), shortenLabel(UbaseLabel, 70)));
        set(h.txtUnderlayLabel,'String',['Underlay: ' UbaseLabel]);
    end

    function updateStatus(msg)
        mode = 'OFF'; if S.editorOn, mode = 'ON'; end
        view = 'FULL'; if S.previewMasked, view = 'MASKED'; end
        set(statusBox,'String',sprintf( ...
            'Editor=%s | View=%s | Brush=%d (%s) | z=%d/%d | %s', ...
            mode, view, S.brushR, brushShapeName(S.brushShape), S.z, nZ, msg));
        drawnow;
    end

% -------------------- Brush preview --------------------
    function renderBrushPreview()
        xy = getCursorXYdisp();
        if any(isnan(xy)), deleteBrushPreview(); return; end
        x = xy(1); y = xy(2);

        [px,py,lw] = brushOutlinePoly(x,y,S.brushR,S.brushShape);

        if isempty(brushPreview) || ~isgraphics(brushPreview)
            brushPreview = plot(ax, px, py, '-', 'LineWidth', lw);
            set(brushPreview,'HitTest','off','Clipping','on');
        else
            set(brushPreview,'XData',px,'YData',py,'LineWidth',lw);
        end

        if S.isPainting && strcmp(S.paintMode,'erase')
            set(brushPreview,'Color',[1.0 0.35 0.35]);
        else
            set(brushPreview,'Color',[0.25 1.0 0.35]);
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

% -------------------- Painting ops --------------------
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
        if xc<1 || xc>nX || yc<1 || yc>nY, return; end

        if S.brushShape == 3
            penRad = max(1, round(S.brushR/10));
            setPixelsDisk(xc,yc,z,penRad);
            return;
        end

        K = getBrushKernel();
        r = brushCache.R;

        xMin = max(1, xc-r); xMax = min(nX, xc+r);
        yMin = max(1, yc-r); yMax = min(nY, yc+r);

        kx1 = 1 + (xMin - (xc-r));
        kx2 = (2*r+1) - ((xc+r) - xMax);
        ky1 = 1 + (yMin - (yc-r));
        ky2 = (2*r+1) - ((yc+r) - yMax);

        patch = K(ky1:ky2, kx1:kx2);

        if strcmp(S.paintMode,'add')
            maskVol(yMin:yMax, xMin:xMax, z) = maskVol(yMin:yMax, xMin:xMax, z) | patch;
        else
            maskVol(yMin:yMax, xMin:xMax, z) = maskVol(yMin:yMax, xMin:xMax, z) & ~patch;
        end
    end

    function setPixelsDisk(xc, yc, z, rad)
        rad = max(1, round(rad));
        [X,Y] = meshgrid(-rad:rad, -rad:rad);
        disk = (X.^2 + Y.^2) <= rad^2;

        xMin = max(1, xc-rad); xMax = min(nX, xc+rad);
        yMin = max(1, yc-rad); yMax = min(nY, yc+rad);

        kx1 = 1 + (xMin - (xc-rad));
        kx2 = (2*rad+1) - ((xc+rad) - xMax);
        ky1 = 1 + (yMin - (yc-rad));
        ky2 = (2*rad+1) - ((yc+rad) - yMax);

        patch = disk(ky1:ky2, kx1:kx2);

        if strcmp(S.paintMode,'add')
            maskVol(yMin:yMax, xMin:xMax, z) = maskVol(yMin:yMax, xMin:xMax, z) | patch;
        else
            maskVol(yMin:yMax, xMin:xMax, z) = maskVol(yMin:yMax, xMin:xMax, z) & ~patch;
        end
    end

    function invalidateBrushCache()
        brushCache.r = NaN; brushCache.shape = NaN; brushCache.K = []; brushCache.R = 0;
    end

    function K = getBrushKernel()
        r = max(1, round(S.brushR));
        sh = S.brushShape;
        if sh == 3, sh = 1; end
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
            tf = false; return;
        end
        cp = get(ax,'CurrentPoint');
        x = cp(1,1); y = cp(1,2);
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
                    U = underlayMeanLinear(I);
                    UbaseLabel = 'Mean(T) [linear]';
                case 2
                    U = underlayMedianLinear(I);
                    UbaseLabel = 'Median(T) [linear]';
                case 3
                    U = underlayMaxLinear(I);
                    UbaseLabel = 'Max(T) [linear]';
                case 4
                    if ~isempty(S.externalFile)
                        tmp = loadUnderlayAny(S.externalFile);
                        U = fitUnderlayToDims(tmp,nY,nX,nZ);
                        UbaseLabel = 'External';
                    else
                        U = underlayGabrielMeanDB(I);
                        UbaseLabel = 'Gabriel Mean (dB)';
                    end
                case 5
                    U = underlayGabrielMeanDB(I);
                    UbaseLabel = 'Gabriel Mean (dB)';
                case 6
                U = underlayMIP_Z_ofMeanT(I);
                UbaseLabel = 'MIP (Z) of Mean(T) [linear]';
            end
            U = double(U);
            U(~isfinite(U)) = 0;
            if ndims(U)==2, U = reshape(U,[nY nX 1]); end
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
    % MIP like FSLeyes (axial direction here):
    % For 4D: a0(y,x,z) = mean_t I(y,x,z,t)
    %         mip(y,x)  = max_z a0(y,x,z)
    % We replicate mip across z so the slice slider still works.

    if ndims(Iin) == 3
        % 2D probe: no Z dimension -> MIP degenerates to Mean(T)
        U = mean(double(Iin), 3);
        U = reshape(U, [nY nX 1]);
        return;
    end

    % 4D input: [Y X Z T]
    T = size(Iin, 4);

    % Memory-safe mean over T (avoids double(Iin) full copy)
    a0 = zeros(nY, nX, nZ, 'double');
    for tt = 1:T
        a0 = a0 + double(Iin(:,:,:,tt));
    end
    a0 = a0 / max(1, T);

    % Maximum intensity projection along Z
    mip2 = max(a0, [], 3);  % [Y X]

    % Replicate across Z so Ubase(:,:,z) exists for all z
    U = repmat(reshape(mip2, [nY nX 1]), [1 1 nZ]);
end
    function Udb = underlayGabrielMeanDB(Iin)
        % Gabriel style:
        % a0 = mean(I, T); a0 = 20*log10(a0 ./ max(a0(:)));
        if ndims(Iin)==3
            a0 = mean(double(Iin),3);
            mx = max(a0(:));
            if ~isfinite(mx) || mx <= 0, mx = max(eps, max(a0(:))); end
            Udb = 20*log10( max(a0,0) / (mx + eps) + eps );
            Udb = reshape(Udb,[nY nX 1]);
        else
            a0 = mean(double(Iin),4); % (Y X Z)
            mx = max(a0(:));
            if ~isfinite(mx) || mx <= 0, mx = max(eps, max(a0(:))); end
            Udb = 20*log10( max(a0,0) / (mx + eps) + eps );
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
            tmpDir = tempname; mkdir(tmpDir);
            gunzip(fullFile, tmpDir);
            d = dir(fullfile(tmpDir,'*.nii'));
            if isempty(d), error('gunzip failed'); end
            niiFile = fullfile(tmpDir, d(1).name);
            U = double(niftiread(niiFile));
            try, rmdir(tmpDir,'s'); catch, end
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
        U = double(U); U(~isfinite(U)) = 0;

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
                U = v.I; return;
            end
        end
        for kk = 1:numel(fn)
            v = Sx.(fn{kk});
            if isnumeric(v)
                U = v; return;
            end
        end
        error('No numeric variable found in MAT.');
    end

% -------------------- Display utils --------------------
    function U01 = scale01(U, globalFlag)
        U = double(U); U(~isfinite(U)) = 0;
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
            p1 = min(U(:)); p99 = max(U(:));
            if p99 <= p1
                U01 = zeros(size(U)); return;
            end
        end
        U = min(max(U,p1),p99);
        U01 = (U - p1) / max(eps,(p99 - p1));
        U01 = min(max(U01,0),1);
    end

    function U01 = scaleFixed(U, lo, hi)
        U = double(U); U(~isfinite(U)) = lo;
        if ~isfinite(lo), lo = -48; end
        if ~isfinite(hi), hi = -7; end
        if hi <= lo + 1, hi = lo + 1; end
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

      % Sharpness 0..100 (stronger but still stable)
sharp = max(0, min(100, double(sharp)));
if sharp > 0
    sharpMax  = 100;
    amountMax = 2.2;                         % max sharpening strength
   amount = amountMax * (1 - exp(-sharp/25));   % 25 -> reaches ~98% at ~100

    % Slightly larger blur at higher sharpness reduces halos
    sigma = 1.25 + 0.35*(sharp/sharpMax);
    B = gaussBlur2D(U01, sigma);

    hi = (U01 - B);

    % Clamp high-frequency boost (prevents harsh ringing/noise blow-up)
    hi = max(min(hi, 0.25), -0.25);

    U01 = U01 + amount * hi;
    U01 = min(max(U01,0),1);
end
    end

    function Uo = toneMapSoft(Ui)
        Ui = double(Ui);
        Ui = min(max(Ui,0),1);
        g = 4.0;
        Uo = asinh(g*Ui) / asinh(g);
        Uo = min(max(Uo,0),1);
    end

    function RGB = mapToRGB(U01, cmapMode)
        U01 = double(U01);
        U01 = min(max(U01,0),1);

        idx = 1 + floor(U01*255);
        idx(idx<1) = 1; idx(idx>256) = 256;

        switch round(cmapMode)
            case 1, cmap = gray(256);
            case 2, cmap = flipud(gray(256));
            case 3, cmap = hot(256);
            case 4, cmap = copper(256);
            case 5, cmap = bone(256);
            otherwise, cmap = gray(256);
        end

        RGB = reshape(cmap(idx(:),:), [size(U01,1) size(U01,2) 3]);
        RGB = single(RGB);
    end

% -------------------- Vessel enhancement --------------------
    function U01 = applyVesselEnhance_Safer(U01, sigmaSlider, connSize, strength)
        A = double(U01);
        A = min(max(A,0),1);

        t = max(0, min(40, double(sigmaSlider))) / 40;
        sigmaEff = 0.6 + (t^1.25) * 5.4;

        B = gaussBlur2D(A, sigmaEff);
        V = A - B;
        V = max(V, 0);
        V(~isfinite(V)) = 0;

        vv = V(:); vv = vv(isfinite(vv));
        if isempty(vv) || max(vv) <= 0
            U01 = A; return;
        end
        s = prctile(vv, 99);
        if ~isfinite(s) || s <= 0, s = max(vv); end
        Vn = V / max(eps, s);
        Vn = min(max(Vn,0),1);
        Vn = Vn .^ 1.25;

        connSize = max(0, min(250, double(connSize)));
        if connSize > 0
            radClose = max(1, round(connSize/30));
            minArea  = max(0, round(connSize*0.8));
            Vb = Vn > 0.30;
            Vb = closeBinarySafe(Vb, radClose);
            Vb = bwareaopenSafe(Vb, minArea);
            Vn = Vn .* double(Vb);
        end

        w = max(0, min(15, double(strength))) / 10;
        U01 = A + (0.55*w) * Vn;
        U01 = min(max(U01,0),1);
    end

    function B = gaussBlur2D(A, sigma)
        sigma = max(0, double(sigma));
        if sigma <= 0, B = A; return; end
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

    function Vb = closeBinarySafe(Vb, rad)
        Vb = logical(Vb);
        rad = max(1, round(rad));
        try
            se = strel('disk', rad);
            Vb = imclose(Vb, se);
        catch
            K = ones(2*rad+1);
            dil = conv2(double(Vb), K, 'same') > 0;
            ero = conv2(double(dil), K, 'same') >= numel(K);
            Vb = logical(ero);
        end
    end

    function BW = bwareaopenSafe(BW, minArea)
        BW = logical(BW);
        minArea = max(0, round(minArea));
        if minArea <= 0, return; end
        try
            BW = bwareaopen(BW, minArea);
        catch
            try
                CC = bwconncomp(BW, 8);
                keep = false(size(BW));
                for ii = 1:CC.NumObjects
                    if numel(CC.PixelIdxList{ii}) >= minArea
                        keep(CC.PixelIdxList{ii}) = true;
                    end
                end
                BW = keep;
            catch
            end
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
            case 1, name = 'round';
            case 2, name = 'quadratic';
            case 3, name = 'linear';
            case 4, name = 'diamond';
            otherwise, name = 'round';
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
        v = shape; if v < 1 || v > 4, v = 1; end
    end

    function shape = popupValueToShape(v)
        v = round(v); v = max(1, min(4, v)); shape = v;
    end

% -------------------- Holes + smoothing --------------------
    function M = fillHolesAllSafe(M)
        M = logical(M);
        try
            M = imfill(M,'holes');
        catch
            holes = findHolesNoIPT(M);
            M = M | holes;
        end
    end

    function [M2, didFill] = fillHoleAtOrNearPoint(M, x, y, searchRad)
        M = logical(M);
        M2 = M;
        didFill = false;
        if x<1 || x>size(M,2) || y<1 || y>size(M,1), return; end

        try
            filled = imfill(M,'holes');
            holes = filled & ~M;
        catch
            holes = findHolesNoIPT(M);
        end
        if ~any(holes(:)), return; end

        if ~holes(y,x)
            yMin = max(1,y-searchRad); yMax = min(size(M,1),y+searchRad);
            xMin = max(1,x-searchRad); xMax = min(size(M,2),x+searchRad);

            [YY,XX] = ndgrid(yMin:yMax, xMin:xMax);
            idx = sub2ind(size(M), YY(:), XX(:));
            cand = holes(idx);
            if ~any(cand), return; end
            YY = YY(:); XX = XX(:);
            YY = YY(cand); XX = XX(cand);
            d2 = (YY - y).^2 + (XX - x).^2;
            [~,ii] = min(d2);
            yPick = YY(ii); xPick = XX(ii);
        else
            yPick = y; xPick = x;
        end

        comp = getConnectedComponentAt(holes, xPick, yPick);
        if any(comp(:))
            M2 = M | comp;
            didFill = true;
        end
    end

    function holes = findHolesNoIPT(M)
        M = logical(M);
        bg = ~M;
        [Hh,Wh] = size(bg);
        visited = false(Hh,Wh);

        qy = zeros(Hh*Wh,1);
        qx = zeros(Hh*Wh,1);
        qh = 1; qt = 0;

        for xx = 1:Wh
            if bg(1,xx) && ~visited(1,xx), qt=qt+1; qy(qt)=1; qx(qt)=xx; visited(1,xx)=true; end
            if bg(Hh,xx) && ~visited(Hh,xx), qt=qt+1; qy(qt)=Hh; qx(qt)=xx; visited(Hh,xx)=true; end
        end
        for yy = 1:Hh
            if bg(yy,1) && ~visited(yy,1), qt=qt+1; qy(qt)=yy; qx(qt)=1; visited(yy,1)=true; end
            if bg(yy,Wh) && ~visited(yy,Wh), qt=qt+1; qy(qt)=yy; qx(qt)=Wh; visited(yy,Wh)=true; end
        end

        nbr = [-1 -1; -1 0; -1 1; 0 -1; 0 1; 1 -1; 1 0; 1 1];

        while qh <= qt
            yy = qy(qh); xx = qx(qh); qh = qh + 1;
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

    function comp = getConnectedComponentAt(BW, x, y)
        BW = logical(BW);
        [Hh,Wh] = size(BW);
        comp = false(Hh,Wh);
        if x<1 || x>Wh || y<1 || y>Hh, return; end
        if ~BW(y,x), return; end

        qy = zeros(Hh*Wh,1);
        qx = zeros(Hh*Wh,1);
        qh = 1; qt = 1;
        qy(1)=y; qx(1)=x;
        comp(y,x)=true;

        nbr = [-1 -1; -1 0; -1 1; 0 -1; 0 1; 1 -1; 1 0; 1 1];

        while qh <= qt
            yy = qy(qh); xx = qx(qh); qh=qh+1;
            for kk = 1:8
                ny = yy + nbr(kk,1);
                nx = xx + nbr(kk,2);
                if ny>=1 && ny<=Hh && nx>=1 && nx<=Wh
                    if BW(ny,nx) && ~comp(ny,nx)
                        comp(ny,nx)=true;
                        qt=qt+1;
                        qy(qt)=ny; qx(qt)=nx;
                    end
                end
            end
        end
    end

    function M = smoothMaskSafe(M, rad)
        M = logical(M);
        rad = max(0, round(rad));
        if rad == 0, return; end
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

% -------------------- Edge overlay --------------------
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
        if isempty(s), s = ''; return; end
        if numel(s) > maxLen
            s = [s(1:maxLen) '...'];
        end
    end

    function stem = safeFileStem(s)
        if isempty(s), stem='dataset'; return; end
        stem = regexprep(s,'[^A-Za-z0-9_]+','_');
        stem = regexprep(stem,'_+','_');
        stem = regexprep(stem,'^_','');
        stem = regexprep(stem,'_$','');
        if isempty(stem), stem='dataset'; end
        if numel(stem) > 40, stem = stem(1:40); end
    end
end