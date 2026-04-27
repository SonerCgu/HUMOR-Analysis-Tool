function fig = fUSI_Live_Studio(I, TR, metadata, datasetName)
% fUSI_Live_Studio
% Clean GUI refresh of the live viewer.
% Same overall functionality, improved styling/layout only.
% ASCII-safe.

if nargin < 4
    datasetName = 'Active Dataset';
end

I_raw_loaded  = I;
TR_raw_loaded = TR;

dims = ndims(I);
sz   = size(I);

% -------------------------------------------------------------------------
% Global intensity reference
% -------------------------------------------------------------------------
if ndims(I) == 4
    refLo_raw = prctile(I(:),1);
    refHi_raw = prctile(I(:),99);
else
    refLo_raw = min(I(:));
    refHi_raw = max(I(:));
end

if refHi_raw <= refLo_raw
    refLo_raw = min(I(:));
    refHi_raw = max(I(:));
end

refLo = refLo_raw;
refHi = refHi_raw;

if dims == 3
    systemType = 'Daxasonics (3D Time-Series)';
    Ny = sz(1);
    Nx = sz(2);
    T  = sz(3);
    Nz = 1;
else
    systemType = 'Matrix Probe (4D Volumetric)';
    Ny = sz(1);
    Nx = sz(2);
    Nz = sz(3);
    T  = sz(4);
end

fprintf('\n=========== fUSI Live (Studio Mode) ===========\n');
fprintf('Dataset: %s\n', datasetName);
fprintf('System:  %s\n', systemType);
fprintf('Dims:    %s\n', mat2str(sz));
fprintf('TR:      %.3f s\n', TR);
fprintf('Duration: %.2f min\n', (T*TR)/60);
fprintf('===============================================\n\n');

% -------------------------------------------------------------------------
% Internal state
% -------------------------------------------------------------------------
gabriel_active = false;
gabriel_use       = false;
gabriel_nsub      = 50;
gabriel_regSmooth = 1.3; %#ok<NASGU>

I_proc  = I;
TR_proc = TR;

if gabriel_use
    fprintf('[Gabriel] ENABLED (on load): nsub=%d, regSmooth=%.2f\n', ...
        gabriel_nsub, gabriel_regSmooth);

    opts = struct();
    opts.nsub   = gabriel_nsub;
    opts.saveQC = false;
    opts.showQC = false;

    if dims == 3
        out     = gabriel_preprocess(I, TR, opts);
        I_proc  = out.I;
        TR_proc = out.blockDur;
        T       = out.nVols;
    else
        nr = floor(T / gabriel_nsub);
        I_proc = zeros(Ny, Nx, Nz, nr, 'like', I);

        for z = 1:Nz
            outz = gabriel_preprocess(squeeze(I(:,:,z,:)), TR, opts);
            I_proc(:,:,z,:) = outz.I;
        end

        TR_proc = TR * gabriel_nsub;
        T       = nr;
    end

    I  = I_proc;
    TR = TR_proc;
    fprintf('[Gabriel] Effective TR: %.3f s | New T: %d\n', TR, T);
end

% -------------------------------------------------------------------------
% Initial PSC
% -------------------------------------------------------------------------
Nbaseline = min(T,1000);

if dims == 3
    base = mean(I(:,:,1:Nbaseline),3);
    PSC  = (I - base) ./ base * 100;
else
    base = mean(I(:,:,:,1:Nbaseline),4);
    PSC  = bsxfun(@rdivide, bsxfun(@minus,I,base),base) * 100;
end

% -------------------------------------------------------------------------
% GUI state
% -------------------------------------------------------------------------
currentFrame     = 1;
currentSpeed     = 1.0; %#ok<NASGU>
loopEnabled      = true; %#ok<NASGU>
liveROI_enabled  = false;

% -------------------------------------------------------------------------
% Theme
% -------------------------------------------------------------------------
C = struct();
C.fig      = [0.03 0.03 0.03];
C.sidebar  = [0.11 0.11 0.12];
C.panel    = [0.14 0.14 0.15];
C.ctrl     = [0.22 0.22 0.23];
C.ctrlDark = [0.18 0.18 0.19];
C.text     = [0.96 0.96 0.96];
C.textSoft = [0.75 0.82 0.90];
C.textDim  = [0.68 0.68 0.68];
C.green    = [0.18 0.62 0.24];
C.greenDark= [0.10 0.45 0.14];
C.red      = [0.72 0.14 0.14];
C.orange   = [0.82 0.48 0.10];
C.blue     = [0.24 0.42 0.76];
C.cyan     = [0.36 0.78 1.00];
C.gold     = [1.00 0.78 0.35];
C.border   = [0.25 0.25 0.27];
C.live     = [0.00 1.00 0.28];

% -------------------------------------------------------------------------
% Main figure
% -------------------------------------------------------------------------
fig = figure('Name',['fUSI Viewer v8 - ' systemType], ...
    'Position',[100 80 2200 1200], ...
    'Color',C.fig, ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'NumberTitle','off', ...
    'WindowButtonDownFcn',@mouseClick, ...
    'WindowScrollWheelFcn',@mouseWheelScroll, ...
    'KeyPressFcn',@keyPressHandler, ...
    'DefaultUicontrolFontName','Helvetica', ...
    'DefaultUicontrolFontSize',11, ...
    'DefaultAxesFontName','Helvetica', ...
    'DefaultAxesFontSize',11);

drawnow;

% -------------------------------------------------------------------------
% Sidebar
% -------------------------------------------------------------------------
sidebar = uipanel(fig,'Units','normalized', ...
    'Position',[0 0 0.20 1], ...
    'BackgroundColor',C.sidebar, ...
    'BorderType','line', ...
    'HighlightColor',C.border, ...
    'ShadowColor',C.border);

uicontrol(sidebar,'Style','text','String','Live Viewer Controls', ...
    'Units','normalized','Position',[0.05 0.962 0.90 0.034], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',15,'FontWeight','bold');

uicontrol(sidebar,'Style','text','String','Interactive time-series viewer', ...
    'Units','normalized','Position',[0.05 0.938 0.90 0.020], ...
    'ForegroundColor',C.textSoft,'BackgroundColor',C.sidebar, ...
    'FontSize',9);

BOTTOM_RESERVED = 0.12;
Y       = 0.900;
dRow    = 0.022;
dBlock  = 0.036;
sliderH = 0.020;

% Display mode
uicontrol(sidebar,'Style','text','String','Display Mode', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

displayDropdown = uicontrol(sidebar,'Style','popupmenu', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'String',{'Raw Intensity','Normalized','% Signal Change'}, ...
    'Value',1,'FontSize',11, ...
    'BackgroundColor',C.ctrl,'ForegroundColor',C.text, ...
    'Callback',@togglePSCpanel);
Y = Y - dBlock;

% ROI size
uicontrol(sidebar,'Style','text','String','ROI Size (px)', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

roiSlider = uicontrol(sidebar,'Style','slider', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'Min',2,'Max',150,'Value',10, ...
    'SliderStep',[1/150 10/150], ...
    'BackgroundColor',C.ctrl);
Y = Y - dBlock;

% Live ROI
uicontrol(sidebar,'Style','text','String','Live ROI Preview', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

liveROIbtn = uicontrol(sidebar,'Style','togglebutton', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'String','OFF','Value',0, ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',[0.45 0.08 0.08], ...
    'ForegroundColor',C.text, ...
    'Callback',@toggleLiveROI);
Y = Y - dBlock;

% Brightness
uicontrol(sidebar,'Style','text','String','Brightness', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

brightness = uicontrol(sidebar,'Style','slider', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'Min',-1,'Max',1,'Value',0, ...
    'BackgroundColor',C.ctrl);
Y = Y - dBlock;

% Contrast
uicontrol(sidebar,'Style','text','String','Contrast', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

contrast = uicontrol(sidebar,'Style','slider', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'Min',0.1,'Max',5,'Value',1, ...
    'BackgroundColor',C.ctrl);
Y = Y - dBlock;

% Gamma
uicontrol(sidebar,'Style','text','String','Gamma', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

gammaSlider = uicontrol(sidebar,'Style','slider', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'Min',0.1,'Max',5,'Value',1, ...
    'BackgroundColor',C.ctrl);
Y = Y - dBlock;

% Colormap
uicontrol(sidebar,'Style','text','String','Colormap', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

mapDropdown = uicontrol(sidebar,'Style','popupmenu', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'String',{'gray','hot'}, ...
    'FontSize',11, ...
    'BackgroundColor',C.ctrl,'ForegroundColor',C.text);
Y = Y - dBlock;

% Hist EQ
histEQ = uicontrol(sidebar,'Style','checkbox', ...
    'String','Histogram Equalization', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11);
Y = Y - dBlock;

% Gabriel
uicontrol(sidebar,'Style','text','String','Gabriel preprocessing', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.gold,'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

gabrielToggle = uicontrol(sidebar,'Style','checkbox', ...
    'String','Mean Block Average', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'Value',gabriel_use, ...
    'ForegroundColor',C.text, ...
    'BackgroundColor',C.sidebar, ...
    'FontSize',11, ...
    'Callback',@(src,~) setGabrielUse(src));
Y = Y - dRow;

uicontrol(sidebar,'Style','text','String','nsub (frames/block)', ...
    'Units','normalized','Position',[0.05 Y 0.55 0.028], ...
    'ForegroundColor',C.text, ...
    'BackgroundColor',C.sidebar, ...
    'FontSize',11);

gabrielNsub = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.62 Y 0.33 0.030], ...
    'String','50', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
Y = Y - dBlock;

uicontrol(sidebar,'Style','text','String','Z slice range (Gabriel)', ...
    'Units','normalized','Position',[0.05 Y 0.55 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11);

gabrielZstart = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.62 Y 0.15 0.030], ...
    'String','1', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);

gabrielZend = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.80 Y 0.15 0.030], ...
    'String',num2str(Nz), ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
Y = Y - dBlock;

gabrielReloadBtn = uicontrol(sidebar,'Style','pushbutton', ...
    'String','Apply Gabriel preprocessing', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.035], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',C.green,'ForegroundColor',C.text, ...
    'Callback',@reloadWithGabriel);
Y = Y - dBlock;

% Despike
despikeToggle = uicontrol(sidebar,'Style','checkbox', ...
    'String','Despike', ...
    'Units','normalized','Position',[0.05 Y 0.35 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'Value',1,'FontSize',11);

uicontrol(sidebar,'Style','text','String','Z-threshold', ...
    'Units','normalized','Position',[0.42 Y 0.25 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11);

despikeZ = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.72 Y 0.23 0.030], ...
    'String','5', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
Y = Y - dBlock;

% Filtering
dYf = 0.028;
Y = Y - 0.015;

uicontrol(sidebar,'Style','text','String','Filtering', ...
    'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
    'ForegroundColor',C.cyan, ...
    'BackgroundColor',C.sidebar, ...
    'FontSize',12,'FontWeight','bold');
Y = Y - dRow;

filterDropdown = uicontrol(sidebar,'Style','popupmenu', ...
    'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
    'String',{'None','High-pass','Low-pass','Band-pass'}, ...
    'FontSize',11, ...
    'BackgroundColor',C.ctrl,'ForegroundColor',C.text, ...
    'Callback',@toggleBandpass);
Y = Y - dBlock;

uicontrol(sidebar,'Style','text','String','Order', ...
    'Units','normalized','Position',[0.05 Y 0.22 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11);

filterOrder = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.31 Y 0.25 0.030], ...
    'String','4', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
Y = Y - dBlock;

lowCutLabel = uicontrol(sidebar,'Style','text','String','Low cutoff (Hz)', ...
    'Units','normalized','Position',[0.05 Y 0.40 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11); %#ok<NASGU>

lowCut = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.55 Y 0.40 0.030], ...
    'String','0.05', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
Y = Y - dYf;

highCutLabel = uicontrol(sidebar,'Style','text','String','High cutoff (Hz)', ...
    'Units','normalized','Position',[0.05 Y 0.40 0.028], ...
    'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
    'FontSize',11);

highCut = uicontrol(sidebar,'Style','edit', ...
    'Units','normalized','Position',[0.55 Y 0.40 0.030], ...
    'String','0.20', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);
set(highCut,'Visible','off');
set(highCutLabel,'Visible','off');
Y = Y - dBlock;

% Slice slider
if dims == 4
    uicontrol(sidebar,'Style','text','String','Slice (Z)', ...
        'Units','normalized','Position',[0.05 Y 0.90 0.028], ...
        'ForegroundColor',C.text,'BackgroundColor',C.sidebar, ...
        'FontSize',12,'FontWeight','bold');
    Y = Y - dRow;

    if Nz > 1
        smallStep = 1/(Nz-1);
        largeStep = min(5/(Nz-1),1);
    else
        smallStep = 1;
        largeStep = 1;
    end

    sliceSlider = uicontrol(sidebar,'Style','slider', ...
        'Units','normalized','Position',[0.05 Y 0.90 sliderH], ...
        'Min',1,'Max',Nz,'Value',round(Nz/2), ...
        'SliderStep',[smallStep largeStep], ...
        'BackgroundColor',C.ctrl);
    Y = Y - dBlock;
else
    sliceSlider = [];
end

% PSC panel
PSCpanel = uipanel(sidebar,'Units','normalized', ...
    'Position',[0.02 0.075 0.96 0.060], ...
    'BackgroundColor',C.panel, ...
    'BorderType','line', ...
    'HighlightColor',C.border, ...
    'ShadowColor',C.border, ...
    'Visible','off');

uicontrol(PSCpanel,'Style','text','String','% Signal Change Baseline (s)', ...
    'Units','normalized','Position',[0.05 0.62 0.90 0.28], ...
    'ForegroundColor',[0.45 1.00 0.45], ...
    'BackgroundColor',C.panel, ...
    'FontSize',11,'FontWeight','bold');

uicontrol(PSCpanel,'Style','text','String','Start', ...
    'Units','normalized','Position',[0.05 0.38 0.25 0.22], ...
    'ForegroundColor',C.text,'BackgroundColor',C.panel, ...
    'FontSize',10);

baseStart = uicontrol(PSCpanel,'Style','edit', ...
    'Units','normalized','Position',[0.35 0.38 0.25 0.25], ...
    'String','0', ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);

uicontrol(PSCpanel,'Style','text','String','End', ...
    'Units','normalized','Position',[0.62 0.38 0.20 0.22], ...
    'ForegroundColor',C.text,'BackgroundColor',C.panel, ...
    'FontSize',10);

baseEnd = uicontrol(PSCpanel,'Style','edit', ...
    'Units','normalized','Position',[0.82 0.38 0.15 0.25], ...
    'String',num2str(Nbaseline*TR), ...
    'BackgroundColor',C.ctrlDark,'ForegroundColor',C.text);

recalcBtn = uicontrol(PSCpanel,'Style','pushbutton', ...
    'String','Recalculate PSC', ...
    'Units','normalized','Position',[0.22 0.06 0.56 0.24], ...
    'FontSize',10,'FontWeight','bold', ...
    'BackgroundColor',C.greenDark,'ForegroundColor',C.text, ...
    'Callback',@recalcPSCfunc); %#ok<NASGU>

set(PSCpanel,'Visible','off');

Y = max(Y, BOTTOM_RESERVED + 0.02);

% Bottom buttons
uicontrol(sidebar,'Style','pushbutton','String','Help / Info', ...
    'Units','normalized','Position',[0.05 0.01 0.27 0.042], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',C.blue,'ForegroundColor',C.text, ...
    'Callback',@showHelpWindow);

uicontrol(sidebar,'Style','pushbutton','String','Export MP4', ...
    'Units','normalized','Position',[0.365 0.01 0.27 0.042], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',C.greenDark,'ForegroundColor',C.text, ...
    'Callback',@exportVideoCB);

uicontrol(sidebar,'Style','pushbutton','String','Close Viewer', ...
    'Units','normalized','Position',[0.68 0.01 0.27 0.042], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',C.red,'ForegroundColor',C.text, ...
    'Callback',@(src,event) cleanup());
% -------------------------------------------------------------------------
% Header info block
% -------------------------------------------------------------------------
infoPanel = uipanel(fig,'Units','normalized', ...
    'Position',[0.23 0.925 0.50 0.050], ...
    'BackgroundColor',C.fig, ...
    'BorderType','none');

datasetLabel = uicontrol(infoPanel,'Style','text', ...
    'Units','normalized','Position',[0.00 0.48 1.00 0.50], ...
    'ForegroundColor',C.text, ...
    'BackgroundColor',C.fig, ...
    'HorizontalAlignment','left', ...
    'FontSize',15, ...
    'FontWeight','bold', ...
    'String',['Dataset: ' datasetName]);

statusLabel = uicontrol(infoPanel,'Style','text', ...
    'Units','normalized','Position',[0.00 0.02 1.00 0.46], ...
    'ForegroundColor',C.textSoft, ...
    'BackgroundColor',C.fig, ...
    'HorizontalAlignment','left', ...
    'FontSize',11, ...
    'String','Display: Raw Intensity | Slice: 1 | Frame: 1/1 | Time: 0.00 s');

% -------------------------------------------------------------------------
% Main image axis
% -------------------------------------------------------------------------
ax1 = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.23 0.54 0.53 0.35], ...
    'Color','k','XColor',C.textDim,'YColor',C.textDim, ...
    'Box','on','LineWidth',1);
hold(ax1,'on');
axis(ax1,'image');
axis(ax1,'off');
view(ax1,[0 90]);

if dims == 4
    currentZ = round(Nz/2);
    frame0 = I(:,:,currentZ,1);
else
    currentZ = 1;
    frame0 = I(:,:,1);
end

frameH = imagesc(ax1, rot90(normalizeVol(frame0),2));
colormap(ax1,'gray');
set(ax1,'CLim',[0 1]);

L_text = text(ax1, 0.01, 0.93, 'Left', ...
    'Units','normalized', ...
    'Color',[1 0.15 0.15],'FontSize',18,'FontWeight','bold', ...
    'HorizontalAlignment','left','VerticalAlignment','top'); %#ok<NASGU>

R_text = text(ax1, 0.99, 0.93, 'Right', ...
    'Units','normalized', ...
    'Color',[1 0.15 0.15],'FontSize',18,'FontWeight','bold', ...
    'HorizontalAlignment','right','VerticalAlignment','top'); %#ok<NASGU>

% -------------------------------------------------------------------------
% Timecourse axis
% -------------------------------------------------------------------------
ax2 = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.23 0.10 0.72 0.34], ...
    'Color','k','XColor',C.text,'YColor',C.text, ...
    'Box','on','LineWidth',1, ...
    'GridColor',[0.25 0.25 0.25], ...
    'GridAlpha',0.45);
hold(ax2,'on');
grid(ax2,'on');
xlabel(ax2,'Time (s)','Color',C.text);
ylabel(ax2,'Intensity [AU]','Color',C.text);

hLive = plot(ax2,(0:T-1)*TR, zeros(1,T), 'LineWidth',2,'Color',C.live);

% -------------------------------------------------------------------------
% ROI storage and live rectangle
% -------------------------------------------------------------------------
roiColors  = [1 0 0; 0 1 0; 0.3 0.3 1; 1 1 0; 1 0.5 0; 0 1 1; 1 0 1];
ROI        = struct('x1',{},'x2',{},'y1',{},'y2',{},'z',{},'color',{});
roiHandles = [];
roiPlots   = [];
mousePos   = [NaN NaN];

roiLive = rectangle(ax1,'Position',[1 1 1 1], ...
    'EdgeColor',[1 0 0],'LineWidth',2,'Visible','off');

set(fig,'WindowButtonMotionFcn',@(~,~) updateMousePos);

% -------------------------------------------------------------------------
% Playback panel
% -------------------------------------------------------------------------
playbackPanel = uipanel(fig,'Units','normalized', ...
    'Position',[0.78 0.82 0.20 0.15], ...
    'BackgroundColor',C.panel, ...
    'BorderType','line', ...
    'HighlightColor',C.border, ...
    'ShadowColor',C.border);


playBtn = uicontrol(playbackPanel,'Style','pushbutton','String','Play', ...
    'Units','normalized','Position',[0.04 0.55 0.22 0.35], ...
    'FontSize',11,'FontWeight','bold', ...
    'BackgroundColor',C.green,'ForegroundColor',C.text, ...
    'Callback',@togglePlay_A);

uicontrol(playbackPanel,'Style','text','String','Speed (x)', ...
    'Units','normalized','Position',[0.30 0.78 0.65 0.18], ...
    'ForegroundColor',C.text,'BackgroundColor',C.panel, ...
    'FontSize',10,'FontWeight','bold', ...
    'HorizontalAlignment','left');

speedSlider = uicontrol(playbackPanel,'Style','slider', ...
    'Units','normalized','Position',[0.30 0.60 0.65 0.18], ...
    'Min',0,'Max',4,'Value',1.0, ...
    'SliderStep',[0.02 0.10], ...
    'BackgroundColor',C.ctrl);

speedText = uicontrol(playbackPanel,'Style','text', ...
    'Units','normalized','Position',[0.30 0.44 0.65 0.15], ...
    'ForegroundColor',[0.72 1.00 0.72], ...
    'BackgroundColor',C.panel, ...
    'FontSize',9,'FontWeight','bold', ...
    'HorizontalAlignment','left', ...
    'String','Speed: 1.00x');

set(speedSlider,'Callback',@(s,~) set(speedText,'String',sprintf('Speed: %.2fx',get(s,'Value'))));

loopBox = uicontrol(playbackPanel,'Style','checkbox','String','Loop', ...
    'Units','normalized','Position',[0.75 0.43 0.20 0.18], ...
    'ForegroundColor',C.text,'BackgroundColor',C.panel, ...
    'Value',1);

uicontrol(playbackPanel,'Style','text','String','Frame', ...
    'Units','normalized','Position',[0.04 0.23 0.20 0.15], ...
    'ForegroundColor',C.textSoft, ...
    'BackgroundColor',C.panel, ...
    'FontSize',10,'FontWeight','bold', ...
    'HorizontalAlignment','left');

frameTimeLabel = uicontrol(playbackPanel,'Style','text', ...
    'Units','normalized','Position',[0.75 0.23 0.20 0.15], ...
    'ForegroundColor',[0.75 0.90 1.00], ...
    'BackgroundColor',C.panel, ...
    'FontSize',11,'FontWeight','bold', ...
    'HorizontalAlignment','right', ...
    'String','0.00 s');

if T > 1
    smallStep = 1/(T-1);
    largeStep = min(10/(T-1),1);
else
    smallStep = 1;
    largeStep = 1;
end

frameScrubber = uicontrol(playbackPanel,'Style','slider', ...
    'Units','normalized','Position',[0.04 0.05 0.91 0.18], ...
    'Min',1,'Max',T,'Value',1, ...
    'SliderStep',[smallStep largeStep], ...
    'BackgroundColor',C.ctrl, ...
    'Callback',@jumpFrame_A);

% Hidden internal frame slider
if T > 1
    smallStep = 1/(T-1);
    largeStep = min(10/(T-1),1);
else
    smallStep = 1;
    largeStep = 1;
end

frameSlider = uicontrol(fig,'Style','slider', ...
    'Units','normalized','Position',[0.23 0.01 0.72 0.02], ...
    'Min',1,'Max',T,'Value',1, ...
    'Visible','off', ...
    'SliderStep',[smallStep largeStep]);

% Footer
footer = uicontrol(fig,'Style','text', ...
    'Units','normalized','Position',[0.23 0.045 0.75 0.025], ...
    'ForegroundColor',[0.80 0.80 0.80], ...
    'BackgroundColor',C.fig, ...
    'HorizontalAlignment','right', ...
    'FontSize',10, ...
    'String', sprintf('Soner Caner Cagun | MPI-B Cybernetics | fUSI Live Viewer v8 | %s', ...
    datestr(now,'yyyy mmm dd - HH:MM:SS'))); %#ok<NASGU>

% -------------------------------------------------------------------------
% Timers
% -------------------------------------------------------------------------
refreshTimer = timer('ExecutionMode','fixedRate','Period',0.10, ...
    'TimerFcn',@updateFrame,'BusyMode','drop');
start(refreshTimer);

playTimer = timer('ExecutionMode','fixedRate','Period',0.10, ...
    'TimerFcn',@stepPlayback_A,'BusyMode','drop');

set(fig,'CloseRequestFcn',@cleanup);

% =========================================================================
% Nested functions
% =========================================================================
    function updateMousePos
        if ~isvalid(ax1)
            return;
        end
        Cpt = get(ax1,'CurrentPoint');
        mousePos = round([Cpt(1,1) Cpt(1,2)]);
    end

    function jumpFrame_A(s,~)
        newF = round(get(s,'Value'));
        currentFrame = newF;
        set(frameSlider,'Value',newF);
        set(frameTimeLabel,'String',sprintf('%.2f s',(newF-1)*TR));
        updateFrame();
    end

    function togglePlay_A(varargin)
        if strcmp(get(playTimer,'Running'),'off')
            set(playBtn,'String','Pause','BackgroundColor',C.orange);
            start(playTimer);
        else
            set(playBtn,'String','Play','BackgroundColor',C.green);
            stop(playTimer);
        end
    end

    function stepPlayback_A(varargin)
        if ~ishghandle(fig)
            return;
        end

        currentSpeed = get(speedSlider,'Value');
        if currentSpeed < 1e-3
            return;
        end

        currentFrame = currentFrame + currentSpeed;

        if currentFrame > T
            if get(loopBox,'Value')
                currentFrame = 1;
            else
                stop(playTimer);
                set(playBtn,'String','Play','BackgroundColor',C.green);
                return;
            end
        end

        set(frameSlider,'Value',currentFrame);
        set(frameScrubber,'Value',currentFrame);
        set(frameTimeLabel,'String',sprintf('%.2f s',(currentFrame-1)*TR));
        updateFrame();
    end

    function [sigOut, spikeMask] = doDespikeMAD(sigIn)
        sigIn = double(sigIn(:)');
        sigOut = sigIn;
        spikeMask = false(size(sigIn));

        if ~get(despikeToggle,'Value')
            return;
        end

        zthr = str2double(get(despikeZ,'String'));
        if isnan(zthr) || zthr < 2
            zthr = 5;
        end

        med = median(sigIn,'omitnan');
        madv = median(abs(sigIn - med),'omitnan');

        if madv < eps
            return;
        end

        robustZ = 0.6745 * (sigIn - med) / madv;
        spikeMask = abs(robustZ) > zthr;

        if ~any(spikeMask)
            return;
        end

        x = 1:numel(sigIn);
        good = ~spikeMask & ~isnan(sigIn);

        if nnz(good) < 2
            return;
        end

        sigOut(spikeMask) = interp1(x(good), sigIn(good), x(spikeMask), 'linear', 'extrap');
    end

    function sigOut = doFiltering(sigIn)
        mode   = get(filterDropdown,'Value');
        FcLow  = str2double(get(lowCut,'String'));
        FcHigh = str2double(get(highCut,'String'));
        order  = str2double(get(filterOrder,'String'));

        if isnan(FcLow),  FcLow  = 0.05; end
        if isnan(FcHigh), FcHigh = 0.20; end
        if isnan(order),  order  = 4;    end

        Fs = 1/TR;

        switch mode
            case 1
                sigOut = sigIn;

            case 2
                Wn = FcLow/(Fs/2);
                [b,a] = butter(order, max(Wn,0.001), 'high');
                sigOut = filtfilt(b,a,double(sigIn));

            case 3
                Wn = FcHigh/(Fs/2);
                [b,a] = butter(order, min(Wn,0.999), 'low');
                sigOut = filtfilt(b,a,double(sigIn));

            case 4
                Wlow  = max(FcLow/(Fs/2), 0.001);
                Whigh = min(FcHigh/(Fs/2), 0.999);

                if Whigh <= Wlow
                    Whigh = Wlow + 0.05;
                end

                [b,a] = butter(order, [Wlow Whigh], 'bandpass');
                sigOut = filtfilt(b,a,double(sigIn));
        end
    end

    function updateFrame(varargin)
        if ~ishghandle(fig)
            return;
        end

        currentFrame = round(get(frameSlider,'Value'));

        if dims == 4
            currentZ = round(get(sliceSlider,'Value'));
            Fraw = I(:,:,currentZ,currentFrame);
            Fpsc = PSC(:,:,currentZ,currentFrame);
        else
            currentZ = 1;
            Fraw = I(:,:,currentFrame);
            Fpsc = PSC(:,:,currentFrame);
        end

        mode = get(displayDropdown,'Value');
        switch mode
            case 1
                if dims == 4
                    F = (double(Fraw) - refLo) / (refHi - refLo);
                    F = max(0, min(1, F));
                else
                    F = normalizeVol(Fraw);
                end

            case 2
                if dims == 4
                    F = (double(Fraw) - refLo) / (refHi - refLo);
                    F = max(0, min(1, F));
                else
                    F = normalizeVol(Fraw);
                end

            case 3
                F = normalizeVol(Fpsc);
        end

        F = F * get(contrast,'Value') + get(brightness,'Value');
        F = max(0, min(1, F));
        F = F.^get(gammaSlider,'Value');

        if get(histEQ,'Value')
            F = histeq(F);
        end

        set(frameH,'CData',fliplr(rot90(F,2)));

        maps = {'gray','hot'};
        colormap(ax1, maps{get(mapDropdown,'Value')});

        displayNames = {'Raw Intensity','Normalized','% Signal Change'};
        t_s = (currentFrame - 1) * TR;
        set(statusLabel,'String',sprintf('Display: %s  |  Slice: %d/%d  |  Frame: %d/%d  |  Time: %.2f s', ...
            displayNames{mode}, currentZ, max(1,Nz), currentFrame, T, t_s));

        if ~liveROI_enabled
            set(roiLive,'Visible','off');
            set(hLive,'YData',zeros(1,T));
            drawnow limitrate;
            return;
        end

        x = mousePos(1);
        y = mousePos(2);

        if isnan(x) || x<1 || x>Nx || isnan(y) || y<1 || y>Ny
            set(roiLive,'Visible','off');
            return;
        end

        rs  = round(get(roiSlider,'Value'));
        hlf = floor(rs/2);

        x1 = max(1, x-hlf);
        x2 = min(Nx, x+hlf);
        y1 = max(1, y-hlf);
        y2 = min(Ny, y+hlf);

        nextColor = roiColors(mod(numel(ROI),size(roiColors,1))+1,:);

        set(roiLive,'Position',[x1 y1 x2-x1+1 y2-y1+1], ...
            'Visible','on','EdgeColor',nextColor);

        y1d = Ny - y2 + 1;
        y2d = Ny - y1 + 1;

        if dims == 3
            tc_raw = squeeze(mean(mean(I(y1d:y2d, x1:x2, :),1),2));
            tc_psc = squeeze(mean(mean(PSC(y1d:y2d, x1:x2, :),1),2));
        else
            tc_raw = squeeze(mean(mean(I(y1d:y2d, x1:x2, currentZ, :),1),2));
            tc_psc = squeeze(mean(mean(PSC(y1d:y2d, x1:x2, currentZ, :),1),2));
        end

        tc_raw = tc_raw(:)';
        mn = min(tc_raw);
        rg = max(tc_raw)-mn;
        if rg == 0
            rg = 1;
        end
        tc_norm = (tc_raw - mn)/rg;

        displayMode = get(displayDropdown,'Value');
        switch displayMode
            case 1
                tc = tc_raw;
            case 2
                tc = tc_norm;
            case 3
                tc = tc_psc;
        end

        [tc, ~] = doDespikeMAD(tc);
        tc = doFiltering(tc);

        set(hLive,'YData',tc,'Color',nextColor);
        drawnow limitrate;
    end

    function mouseClick(~,~)
        if ~liveROI_enabled
            return;
        end

        type = get(fig,'SelectionType');
        x = mousePos(1);
        y = mousePos(2);

        if isnan(x) || x<1 || x>Nx || isnan(y) || y<1 || y>Ny
            return;
        end

        rs  = round(get(roiSlider,'Value'));
        hlf = floor(rs/2);

        x1 = max(1,x-hlf);
        x2 = min(Nx,x+hlf);
        y1 = max(1,y-hlf);
        y2 = min(Ny,y+hlf);

        if strcmp(type,'normal')
            col = roiColors(mod(numel(ROI),size(roiColors,1))+1,:);

            ROI(end+1) = struct('x1',x1,'x2',x2,'y1',y1,'y2',y2,'z',currentZ,'color',col);

            r = rectangle(ax1,'Position',[x1 y1 x2-x1+1 y2-y1+1], ...
                'EdgeColor',col,'LineWidth',2);
            roiHandles(end+1) = r;

            y1d = Ny - y2 + 1;
            y2d = Ny - y1 + 1;

            if dims == 3
                tc_raw = squeeze(mean(mean(I(y1d:y2d, x1:x2, :),1),2));
                tc_psc = squeeze(mean(mean(PSC(y1d:y2d, x1:x2, :),1),2));
            else
                tc_raw = squeeze(mean(mean(I(y1d:y2d, x1:x2, currentZ, :),1),2));
                tc_psc = squeeze(mean(mean(PSC(y1d:y2d, x1:x2, currentZ, :),1),2));
            end

            tc_raw = tc_raw(:)';

            mn = min(tc_raw);
            rg = max(tc_raw)-mn;
            if rg == 0
                rg = 1;
            end
            tc_norm = (tc_raw - mn)/rg;

            displayMode = get(displayDropdown,'Value');
            switch displayMode
                case 1
                    tc_final = tc_raw;
                case 2
                    tc_final = tc_norm;
                case 3
                    tc_final = tc_psc;
            end

            [tc_final, ~] = doDespikeMAD(tc_final);
            tc_final = doFiltering(tc_final);

            h = plot(ax2,(0:T-1)*TR, tc_final,'Color',col,'LineWidth',2);
            roiPlots(end+1) = h;

        elseif strcmp(type,'alt')
            if isempty(ROI)
                return;
            end

            centers = zeros(numel(ROI),2);
            for k = 1:numel(ROI)
                centers(k,:) = [(ROI(k).x1+ROI(k).x2)/2 , (ROI(k).y1+ROI(k).y2)/2];
            end

            d2 = sum((centers - [x y]).^2,2);
            [~, idxMin] = min(d2);

            delete(roiHandles(idxMin));
            delete(roiPlots(idxMin));

            roiHandles(idxMin) = [];
            roiPlots(idxMin)   = [];
            ROI(idxMin)        = [];
        end
    end

    function keyPressHandler(~,event)
        switch event.Key
            case 'rightarrow'
                if dims == 4
                    set(sliceSlider,'Value',min(Nz, get(sliceSlider,'Value') + 1));
                    updateFrame();
                end

            case 'leftarrow'
                if dims == 4
                    set(sliceSlider,'Value',max(1, get(sliceSlider,'Value') - 1));
                    updateFrame();
                end

            case 'uparrow'
                set(roiSlider,'Value',min(150, get(roiSlider,'Value') + 1));

            case 'downarrow'
                set(roiSlider,'Value',max(2, get(roiSlider,'Value') - 1));

            case 'space'
                togglePlay_A();
        end
    end

    function mouseWheelScroll(~,event)
        if dims ~= 4
            return;
        end
        v = get(sliceSlider,'Value') - event.VerticalScrollCount;
        set(sliceSlider,'Value',max(1,min(Nz,v)));
        updateFrame();
    end

    function toggleLiveROI(src,~)
        liveROI_enabled = logical(get(src,'Value'));

        if liveROI_enabled
            set(src,'String','ON','BackgroundColor',C.green);
        else
            set(src,'String','OFF','BackgroundColor',[0.45 0.08 0.08]);
            set(roiLive,'Visible','off');
            set(hLive,'YData',zeros(1,T));
        end
    end

    function setGabrielUse(src)
        gabriel_use = logical(get(src,'Value'));
    end

    function reloadWithGabriel(varargin)
        try
            stop(playTimer);
            set(playBtn,'String','Play','BackgroundColor',C.green);
        catch
        end

        z1 = max(1, round(str2double(get(gabrielZstart,'String'))));
        z2 = min(Nz, round(str2double(get(gabrielZend,'String'))));

        if isnan(z1) || isnan(z2) || z2 < z1
            errordlg('Invalid Gabriel slice range');
            return;
        end

        if gabriel_active
            fprintf('[Viewer] Reverting to RAW data\n');

            I  = I_raw_loaded;
            TR = TR_raw_loaded;
            T  = size(I, ndims(I));

            refLo = refLo_raw;
            refHi = refHi_raw;

            gabriel_active = false;
            set(gabrielToggle,'Value',0);

        else
            fprintf('[Viewer] Applying Gabriel preprocessing\n');

            nsub = str2double(get(gabrielNsub,'String'));
            if isnan(nsub) || nsub < 2
                nsub = 50;
            end
            nsub = round(nsub);

            opts = struct();
            opts.nsub = nsub;

            if dims == 3
                out = gabriel_preprocess(I_raw_loaded, TR_raw_loaded, opts);
                I  = out.I;
                TR = out.blockDur;
                T  = out.nVols;
            else
                nr = floor(size(I_raw_loaded,4) / nsub);

                Inew = I_raw_loaded(:,:,:,1:nsub*nr);
                Inew = reshape(Inew, Ny, Nx, Nz, nsub, nr);
                Inew = squeeze(mean(Inew,4));

                zRef = round((z1 + z2)/2);
                Iref = mean(Inew(:,:,zRef,1:min(10,nr)),4);

                fprintf('[Gabriel] FAST mode | zRef=%d | range=%d:%d\n', zRef, z1, z2);

                defFields = cell(1,nr);
                for t = 1:nr
                    [D,~] = imregdemons(Inew(:,:,zRef,t), Iref, 'DisplayWaitbar', false);
                    defFields{t} = D;
                end

                for z = z1:z2
                    for t = 1:nr
                        Inew(:,:,z,t) = imwarp(Inew(:,:,z,t), defFields{t}, ...
                            'InterpolationMethod','linear', 'FillValues',0);
                    end
                end

                I  = Inew;
                TR = TR_raw_loaded * nsub;
                T  = nr;
            end

            if ndims(I) == 4
                refLo = prctile(I(:),1);
                refHi = prctile(I(:),99);
            else
                refLo = min(I(:));
                refHi = max(I(:));
            end

            gabriel_active = true;
            set(gabrielToggle,'Value',1);
        end

        if ~isempty(roiHandles), delete(roiHandles); end
        if ~isempty(roiPlots),   delete(roiPlots);   end

        ROI = struct('x1',{},'x2',{},'y1',{},'y2',{},'z',{},'color',{});
        roiHandles = [];
        roiPlots   = [];

        Nbaseline = min(T,1000);
        if dims == 3
            base = mean(I(:,:,1:Nbaseline),3);
            PSC  = (I - base)./base * 100;
        else
            base = mean(I(:,:,:,1:Nbaseline),4);
            PSC  = bsxfun(@rdivide, bsxfun(@minus,I,base),base) * 100;
        end

        currentFrame = 1;

        set(frameSlider,'Max',T,'Value',1);
        set(frameScrubber,'Max',T,'Value',1);

        if T > 1
            smallStep = 1/(T-1);
            largeStep = min(10/(T-1),1);
        else
            smallStep = 1;
            largeStep = 1;
        end

        set(frameSlider,'SliderStep',[smallStep largeStep]);
        set(frameScrubber,'SliderStep',[smallStep largeStep]);

        set(hLive,'XData',(0:T-1)*TR,'YData',zeros(1,T));
        set(frameTimeLabel,'String','0.00 s');

        if gabriel_active
            set(gabrielReloadBtn,'String','Revert to RAW data','BackgroundColor',C.red);
            fprintf('[Viewer] Gabriel ON | TR=%.3f s | T=%d\n', TR, T);
        else
            set(gabrielReloadBtn,'String','Apply Gabriel preprocessing','BackgroundColor',C.green);
            fprintf('[Viewer] Gabriel OFF | RAW restored | TR=%.3f s | T=%d\n', TR, T);
        end

        updateFrame();
    end

    function togglePSCpanel(varargin)
        mode = get(displayDropdown,'Value');

        switch mode
            case 3
                set(PSCpanel,'Visible','on');
                ylabel(ax2,'% Signal Change [%]','Color',C.text);
            otherwise
                set(PSCpanel,'Visible','off');
                ylabel(ax2,'Intensity [AU]','Color',C.text);
        end

        updateFrame();
    end

    function toggleBandpass(varargin)
        if get(filterDropdown,'Value') == 4
            set(highCut,'Visible','on');
            set(highCutLabel,'Visible','on');
        else
            set(highCut,'Visible','off');
            set(highCutLabel,'Visible','off');
        end
    end

    function recalcPSCfunc(varargin)
        t1 = str2double(get(baseStart,'String'));
        t2 = str2double(get(baseEnd,'String'));

        if isnan(t1) || isnan(t2) || t1 >= t2
            errordlg('Invalid baseline range.');
            return;
        end

        f1 = max(1, round(t1/TR));
        f2 = min(T, round(t2/TR));

        fprintf('Recomputing PSC: frames %d to %d\n', f1, f2);

        if dims == 3
            base_new = mean(I(:,:,f1:f2),3);
            PSC      = (I - base_new)./base_new * 100;
        else
            base_new = mean(I(:,:,:,f1:f2),4);
            PSC      = bsxfun(@rdivide, bsxfun(@minus,I,base_new),base_new) * 100;
        end

        updateFrame();
    end

  function videosDir = getAnalysedVideosDir()

    baseDir = '';
    cand = {};

    % =========================================================
    % Collect candidate paths from metadata
    % =========================================================
    try
        if isstruct(metadata)

            if isfield(metadata,'exportPath') && ~isempty(metadata.exportPath)
                cand{end+1} = char(metadata.exportPath);
            end

            if isfield(metadata,'savePath') && ~isempty(metadata.savePath)
                cand{end+1} = char(metadata.savePath);
            end

            if isfield(metadata,'outPath') && ~isempty(metadata.outPath)
                cand{end+1} = char(metadata.outPath);
            end

            if isfield(metadata,'analysedPath') && ~isempty(metadata.analysedPath)
                cand{end+1} = char(metadata.analysedPath);
            end

            if isfield(metadata,'loadedPath') && ~isempty(metadata.loadedPath)
                cand{end+1} = char(metadata.loadedPath);
            end

            if isfield(metadata,'loadedFile') && ~isempty(metadata.loadedFile)
                lf = char(metadata.loadedFile);
                if exist(lf,'file') == 2
                    cand{end+1} = fileparts(lf);
                else
                    [lfPath,~,~] = fileparts(lf);
                    if ~isempty(lfPath)
                        cand{end+1} = lfPath;
                    end
                end
            end
        end
    catch
    end

    % =========================================================
    % Clean candidates
    % =========================================================
    cleanCand = {};
    for ii = 1:numel(cand)
        try
            p = strtrim(strrep(cand{ii}, '"', ''));
            if ~isempty(p)
                cleanCand{end+1} = p; %#ok<AGROW>
            end
        catch
        end
    end
    cand = unique(cleanCand, 'stable');

    % =========================================================
    % First preference: existing AnalysedData path
    % =========================================================
    for ii = 1:numel(cand)

        p = cand{ii};

        if exist(p,'dir') == 7 && ~isempty(strfind(lower(p), lower('analyseddata'))) %#ok<STREMP>
            baseDir = p;
            break;
        end
    end

    % =========================================================
    % Second preference: convert RawData path to AnalysedData path
    % =========================================================
    if isempty(baseDir)

        for ii = 1:numel(cand)

            p = cand{ii};

            if isempty(p)
                continue;
            end

            pLow = lower(p);
            rawIdx = strfind(pLow, lower('rawdata'));

            if isempty(rawIdx)
                continue;
            end

            k = rawIdx(1);

            leftPart  = p(1:k-1);
            rightPart = p(k+length('RawData'):end);

            while ~isempty(rightPart) && any(rightPart(1) == ['\' '/'])
                rightPart = rightPart(2:end);
            end

            testDir = fullfile(leftPart, 'AnalysedData', rightPart);

            if exist(testDir,'dir') ~= 7
                try
                    mkdir(testDir);
                catch
                end
            end

            if exist(testDir,'dir') == 7
                baseDir = testDir;
                break;
            end
        end
    end

    % =========================================================
    % Final fallback: ask user
    % =========================================================
    if isempty(baseDir) || exist(baseDir,'dir') ~= 7

        startPath = pwd;

        if exist('Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData','dir') == 7
            startPath = 'Z:\fUS\Project_PACAP_AVATAR_SC\AnalysedData';
        end

        selectedDir = uigetdir(startPath, ...
            'Select analysed folder for Live Viewer MP4 export');

        if isequal(selectedDir,0)
            error('MP4 export cancelled: no output folder selected.');
        end

        baseDir = selectedDir;
    end

    % =========================================================
    % IMPORTANT:
    % Avoid Unicode/special-character folder names for VideoWriter.
    % If baseDir contains non-ASCII characters, create an ASCII-safe
    % video folder one level above or inside a safe sibling folder.
    % =========================================================
    baseDir = char(baseDir);

    if hasNonAscii(baseDir)
        parentDir = fileparts(baseDir);

        safeName = makeSafeAsciiFileName(datasetName);
        if isempty(safeName)
            safeName = ['LiveViewer_' datestr(now,'yyyymmdd_HHMMSS')];
        end

        safeBaseDir = fullfile(parentDir, [safeName '_VideoExport']);

        if exist(safeBaseDir,'dir') ~= 7
            [ok,msg] = mkdir(safeBaseDir);
            if ~ok
                error('Could not create ASCII-safe video export folder:\n%s\n\nReason: %s', ...
                    safeBaseDir, msg);
            end
        end

        baseDir = safeBaseDir;
    end

    videosDir = fullfile(baseDir, 'Videos');

    if exist(videosDir,'dir') ~= 7
        [ok,msg] = mkdir(videosDir);
        if ~ok
            error('Could not create Videos folder:\n%s\n\nReason: %s', videosDir, msg);
        end
    end

    % =========================================================
    % Test write permission/path validity before VideoWriter
    % =========================================================
    testFile = fullfile(videosDir, ['write_test_' datestr(now,'yyyymmdd_HHMMSS') '.tmp']);

    fid = fopen(testFile,'w');

    if fid == -1
        error(['Cannot write to Videos folder:\n%s\n\n' ...
               'This usually means the network path is unavailable, the folder has permission issues, ' ...
               'or VideoWriter cannot handle the path.'], videosDir);
    end

    fprintf(fid,'test');
    fclose(fid);

    try
        delete(testFile);
    catch
    end
end


function tf = hasNonAscii(s)

    tf = false;

    try
        s = char(s);
        tf = any(double(s) > 127);
    catch
        tf = true;
    end
end


function s = makeSafeAsciiFileName(s)

    if nargin < 1 || isempty(s)
        s = 'LiveViewer';
    end

    s = char(s);

    s = strrep(s, 'µ', 'u');
    s = strrep(s, 'μ', 'u');
    s = strrep(s, 'ä', 'ae');
    s = strrep(s, 'ö', 'oe');
    s = strrep(s, 'ü', 'ue');
    s = strrep(s, 'Ä', 'Ae');
    s = strrep(s, 'Ö', 'Oe');
    s = strrep(s, 'Ü', 'Ue');
    s = strrep(s, 'ß', 'ss');

    s = regexprep(s, '\.nii\.gz$', '', 'ignorecase');
    s = regexprep(s, '\.nii$', '', 'ignorecase');
    s = regexprep(s, '\.mat$', '', 'ignorecase');

    s = regexprep(s, '[^A-Za-z0-9_\-]+', '_');
    s = regexprep(s, '_+', '_');
    s = regexprep(s, '^_+', '');
    s = regexprep(s, '_+$', '');

    if isempty(s)
        s = 'LiveViewer';
    end
end




 function exportVideoCB(~,~)
    txtExp = [];
    vid = [];
    wasPlaying = false;
    oldFrame = currentFrame;
    oldZ = currentZ;
    oldLiveROI = liveROI_enabled;
    roiWasVisible = {};
    hiddenTxt = [];
    hiddenTxtVisible = {};

        try
            % -------------------------------------------------------------
            % Stop playback during export
            % -------------------------------------------------------------
            try
                wasPlaying = strcmp(get(playTimer,'Running'),'on');
            catch
                wasPlaying = false;
            end

            if wasPlaying
                stop(playTimer);
            end
            set(playBtn,'String','Play','BackgroundColor',C.green);

            % -------------------------------------------------------------
            % Hide live/permanent ROI overlays for clean underlay export
            % -------------------------------------------------------------
            try
                set(roiLive,'Visible','off');
            catch
            end

            if ~isempty(roiHandles)
                roiWasVisible = cell(size(roiHandles));
                for kk = 1:numel(roiHandles)
                    if isgraphics(roiHandles(kk))
                        try
                            roiWasVisible{kk} = get(roiHandles(kk),'Visible');
                            set(roiHandles(kk),'Visible','off');
                        catch
                        end
                    end
                end
            end

            if oldLiveROI
                liveROI_enabled = false;
                set(liveROIbtn,'Value',0, ...
                    'String','OFF', ...
                    'BackgroundColor',[0.45 0.08 0.08]);
            end

            % -------------------------------------------------------------
            % Default export FPS from current speed slider
            % playTimer runs at 0.1 s, so displayed frame rate is ~10*speed
            % -------------------------------------------------------------
            defaultFPS = max(1, round(10 * max(0.1, get(speedSlider,'Value'))));

            if dims == 4
                defAllSlices = '0';
            else
                defAllSlices = '0';
            end

            a = inputdlg({ ...
                'Export FPS:', ...
                'Repeat each frame (slow down movie):', ...
                'Export all slices? (1=yes, 0=current slice):'}, ...
                'Export MP4', 1, ...
                {num2str(defaultFPS), '1', defAllSlices});

            if isempty(a)
                restoreAfterExport();
                return;
            end

            exportFPS = round(str2double(a{1}));
            if ~isfinite(exportFPS) || exportFPS < 1
                exportFPS = defaultFPS;
            end

            repeatEach = round(str2double(a{2}));
            if ~isfinite(repeatEach) || repeatEach < 1
                repeatEach = 1;
            end

            exportAllSlices = logical(round(str2double(a{3})));
            if ~isfinite(exportAllSlices)
                exportAllSlices = false;
            end

                             % -------------------------------------------------------------
            % Output folder
            % -------------------------------------------------------------
            videosDir = getAnalysedVideosDir();

            if ~exist(videosDir,'dir')
                [ok,msg] = mkdir(videosDir);
                if ~ok
                    error('Could not create Videos folder:\n%s\n\nReason: %s', videosDir, msg);
                end
            end

            disp('--- LIVE VIEWER SAVE VIDEO DEBUG ---');
            disp(['videosDir    = ' videosDir]);
            % -------------------------------------------------------------
            % Naming
            % -------------------------------------------------------------
            modeNames = get(displayDropdown,'String');
            modeName = modeNames{get(displayDropdown,'Value')};
            modeTag = lower(regexprep(modeName,'[^a-zA-Z0-9]+','_'));

dataTag = lower(makeSafeAsciiFileName(datasetName));

if isempty(dataTag)
    dataTag = 'liveviewer';
end
            timeTag = datestr(now,'yyyymmdd_HHMMSS');

            if dims == 4 && exportAllSlices
                sliceList = 1:Nz;
            else
                sliceList = currentZ;
            end

            % -------------------------------------------------------------
            % Time label on the image axis
            % -------------------------------------------------------------
            txtExp = text(ax1, 0.02, 0.98, '', ...
                'Units','normalized', ...
                'Color','w', ...
                'FontName','Courier New', ...
                'FontSize',18, ...
                'FontWeight','bold', ...
                'VerticalAlignment','top', ...
                'HorizontalAlignment','left', ...
                'BackgroundColor','k', ...
                'Margin',6, ...
                'Interpreter','none');
% Hide any other text objects on the image axis during export
axTxt = findall(ax1, 'Type', 'text');
for kk = 1:numel(axTxt)
    hTxt = axTxt(kk);

    if isequal(hTxt, txtExp) || isequal(hTxt, L_text) || isequal(hTxt, R_text)
        continue;
    end

    hiddenTxt(end+1) = hTxt; %#ok<AGROW>
    try
        hiddenTxtVisible{end+1} = get(hTxt, 'Visible'); %#ok<AGROW>
        set(hTxt, 'Visible', 'off');
    catch
        hiddenTxtVisible{end+1} = 'on'; %#ok<AGROW>
    end
end
            % -------------------------------------------------------------
            % Export loop
            % -------------------------------------------------------------
            for zz = sliceList
                if dims == 4
                    currentZ = zz;
                    set(sliceSlider,'Value',zz);
                else
                    currentZ = 1;
                    zz = 1;
                end

            outFile = fullfile(videosDir, ...
    sprintf('%s_%s_z%02d_%s.mp4', dataTag, modeTag, zz, timeTag));

% Make absolutely sure the parent folder exists
outParent = fileparts(outFile);
if exist(outParent,'dir') ~= 7
    [ok,msg] = mkdir(outParent);
    if ~ok
        error('Could not create output folder:\n%s\n\nReason: %s', outParent, msg);
    end
end

% Debug print
disp('--- MP4 EXPORT TARGET ---');
disp(['outParent = ' outParent]);
disp(['outFile   = ' outFile]);

% Pre-test file creation
fid = fopen(outFile, 'w');
if fid == -1
    error(['Cannot create MP4 file at:\n%s\n\n' ...
           'The folder may not exist, may be read-only, or the path contains unsupported characters.'], ...
           outFile);
end
fclose(fid);
delete(outFile);

vid = VideoWriter(outFile,'MPEG-4');
vid.FrameRate = exportFPS;
vid.Quality = 95;
open(vid);

                for ff = 1:T
                    currentFrame = ff;

                    set(frameSlider,'Value',ff);
                    set(frameScrubber,'Value',ff);
                    set(frameTimeLabel,'String',sprintf('%.2f s',(ff-1)*TR));

                    % Reuse normal viewer rendering
                    updateFrame();

                    tSec = (ff - 1) * TR;
                    if dims == 4
                        set(txtExp,'String',sprintf('Slice %d/%d | t = %.2f s | Frame %d/%d', ...
                            zz, Nz, tSec, ff, T));
                    else
                        set(txtExp,'String',sprintf('t = %.2f s | Frame %d/%d', ...
                            tSec, ff, T));
                    end

                    drawnow;
                    fr = getframe(ax1);

                    for rr = 1:repeatEach
                        writeVideo(vid, fr);
                    end
                end

                close(vid);
                vid = [];
            end

            if ~isempty(txtExp) && isgraphics(txtExp)
                delete(txtExp);
                txtExp = [];
            end

            restoreAfterExport();
                     fprintf('[Live Viewer] MP4 export finished: %s\n', videosDir);

try
    msgbox(sprintf('MP4 export finished.\n\nSaved in:\n%s', videosDir), ...
        'Export complete', 'help');
catch
end

        catch ME
            try
                if ~isempty(txtExp) && isgraphics(txtExp)
                    delete(txtExp);
                end
            catch
            end

            try
                if ~isempty(vid)
                    close(vid);
                end
            catch
            end

            restoreAfterExport();
            errordlg(sprintf('MP4 export failed:\n\n%s', ME.message), ...
                'Export MP4 failed');
        end


       

        function restoreAfterExport()
            currentFrame = oldFrame;

            if dims == 4
                currentZ = oldZ;
                set(sliceSlider,'Value',oldZ);
            else
                currentZ = 1;
            end

            set(frameSlider,'Value',oldFrame);
            set(frameScrubber,'Value',oldFrame);
            set(frameTimeLabel,'String',sprintf('%.2f s',(oldFrame-1)*TR));

            if oldLiveROI
                liveROI_enabled = true;
                set(liveROIbtn,'Value',1, ...
                    'String','ON', ...
                    'BackgroundColor',C.green);
            else
                liveROI_enabled = false;
                set(liveROIbtn,'Value',0, ...
                    'String','OFF', ...
                    'BackgroundColor',[0.45 0.08 0.08]);
            end

                       if ~isempty(roiHandles)
                for kk = 1:numel(roiHandles)
                    if isgraphics(roiHandles(kk))
                        try
                            if numel(roiWasVisible) >= kk && ~isempty(roiWasVisible{kk})
                                set(roiHandles(kk),'Visible',roiWasVisible{kk});
                            else
                                set(roiHandles(kk),'Visible','on');
                            end
                        catch
                        end
                    end
                end
            end

            if ~isempty(hiddenTxt)
                for kk = 1:numel(hiddenTxt)
                    if isgraphics(hiddenTxt(kk))
                        try
                            if numel(hiddenTxtVisible) >= kk && ~isempty(hiddenTxtVisible{kk})
                                set(hiddenTxt(kk), 'Visible', hiddenTxtVisible{kk});
                            else
                                set(hiddenTxt(kk), 'Visible', 'on');
                            end
                        catch
                        end
                    end
                end
            end

            updateFrame();

            updateFrame();

            if wasPlaying
                set(playBtn,'String','Pause','BackgroundColor',C.orange);
                start(playTimer);
            else
                set(playBtn,'String','Play','BackgroundColor',C.green);
            end
        end
    end

    function showHelpWindow(varargin)
        helpFig = figure('Name','Help and User Manual', ...
            'Color','k', ...
            'MenuBar','none', ...
            'ToolBar','none', ...
            'NumberTitle','off', ...
            'Position',[350 200 900 700]);

        uicontrol(helpFig,'Style','edit', ...
            'Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
            'Max',200,'Min',1, ...
            'BackgroundColor',[0.12 0.12 0.12], ...
            'ForegroundColor','w','FontSize',11, ...
            'HorizontalAlignment','left', ...
            'String',{ ...
            '==================== fUSI Live Viewer v8 - USER MANUAL ===================='; ...
            ''; ...
            'PURPOSE:'; ...
            '  Interactive exploration of 3D and 4D fUSI datasets with ROI tools,'; ...
            '  PSC visualization, filtering, and playback.'; ...
            ''; ...
            '1) DISPLAY MODES'; ...
            '  - Raw Intensity: absolute intensity view'; ...
            '  - Normalized: normalized frame view'; ...
            '  - % Signal Change: PSC = (I - baseline) / baseline * 100'; ...
            ''; ...
            '2) ROI TOOLS'; ...
            '  - Enable Live ROI Preview to hover and inspect timecourses'; ...
            '  - Left click adds a permanent ROI'; ...
            '  - Right click removes the nearest ROI'; ...
            '  - ROI size can be adjusted with the slider or up/down arrows'; ...
            ''; ...
            '3) PLAYBACK'; ...
            '  - Play/Pause animates frames'; ...
            '  - Speed slider sets playback speed'; ...
            '  - Frame slider scrubs through time'; ...
            '  - Loop repeats playback'; ...
            ''; ...
            '4) KEYBOARD SHORTCUTS'; ...
            '  - Space: play/pause'; ...
            '  - Left/right arrow: previous/next slice for 4D data'; ...
            '  - Up/down arrow: increase/decrease ROI size'; ...
            ''; ...
            '5) FILTERING'; ...
            '  - Butterworth filters are applied to timecourses only'; ...
            '  - Modes: None, High-pass, Low-pass, Band-pass'; ...
            '  - filtfilt is used for zero-phase filtering'; ...
            ''; ...
            '6) DESPIKING'; ...
            '  - Robust median and MAD based despiking is applied to ROI timecourses'; ...
            '  - Spikes above the selected Z-threshold are replaced by interpolation'; ...
            ''; ...
            '7) GABRIEL PREPROCESSING'; ...
            '  - Optional mean block averaging'; ...
            '  - For matrix data, demons registration is applied to the selected slice range'; ...
            ''; ...
            '8) PSC BASELINE'; ...
            '  - In PSC mode, define baseline start and end time in seconds'; ...
            '  - Click Recalculate PSC to rebuild the PSC volume'; ...
            ''; ...
            '9) ORIENTATION'; ...
            '  - Frames are displayed in a fixed neurological orientation'; ...
            '  - Left and Right markers are shown on the image'; ...
            ''; ...
            '10) PERFORMANCE'; ...
            '  - Turning Live ROI Preview off gives the highest refresh speed'; ...
            ''; ...
            'Developed by Soner Caner Cagun'; ...
            'MPI for Biological Cybernetics'; ...
            ''; ...
            '=========================== END OF MANUAL ==========================='; ...
            '' });
    end

    function cleanup(varargin)
        try
            if isvalid(refreshTimer)
                stop(refreshTimer);
                delete(refreshTimer);
            end
        catch
        end

        try
            if isvalid(playTimer)
                stop(playTimer);
                delete(playTimer);
            end
        catch
        end

        if ishghandle(fig)
            delete(fig);
        end
    end
end

% =========================================================================
% Helper: normalizeVol
% =========================================================================
function O = normalizeVol(V)
V = double(V);
V = V - min(V(:));
vmax = max(V(:));
if vmax > 0
    V = V ./ vmax;
end
O = V;
end

% =========================================================================
% Gabriel preprocessing
% =========================================================================
function out = gabriel_preprocess(Iin, TRin, opts)
% Clean Gabriel-style preprocessing (MATLAB 2017b compatible)

fprintf('\n[Viewer] GABRIEL PREPROCESSING APPLIED\n');
fprintf('    Input size: %s\n', mat2str(size(Iin)));
fprintf('    Input TR: %.3f s\n', TRin);

if nargin < 3
    error('gabriel_preprocess requires inputs: Iin, TRin, opts');
end

if ~isfield(opts,'nsub')
    error('opts.nsub is required');
end

nsub = opts.nsub;
if ~isscalar(nsub) || nsub < 2
    error('opts.nsub must be integer >= 2');
end

if ~isfield(opts,'regSmooth') || isempty(opts.regSmooth)
    opts.regSmooth = 1.3;
end

[ny,nx,nt] = size(Iin);
nr = floor(nt / nsub);

if nr < 1
    error('Not enough frames (%d) for nsub=%d', nt, nsub);
end

fprintf('[Gabriel] block averaging (nsub=%d -> %d vols)\n', nsub, nr);

Ir = zeros(ny, nx, nr, 'like', Iin);
for i = 1:nr
    idx = (i-1)*nsub + (1:nsub);
    Ir(:,:,i) = mean(Iin(:,:,idx), 3);
end

fprintf('[Gabriel] demons registration\n');

nRef = min(10, nr);
Iref = mean(Ir(:,:,1:nRef), 3);

Ic = Ir;
for i = 1:nr
    [~, tmp] = imregdemons(Ir(:,:,i), Iref, 'DisplayWaitbar', false);
    Ic(:,:,i) = tmp;
end

out = struct();
out.I         = Ic;
out.TR        = TRin;
out.blockDur  = TRin * nsub;
out.nVols     = nr;
out.totalTime = nt * TRin;
out.method    = sprintf('Gabriel block avg (nsub=%d) + demons', nsub);

fprintf('[Gabriel] blockDur = %.3f s | totalTime = %.1f s\n', ...
    out.blockDur, out.totalTime);
end