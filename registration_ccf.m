% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% UPDATED for fUSI Studio integration (MATLAB 2017b compatible)
% - Programmatic dark GUI (does NOT use figviewscan.fig)
% - No bottom colormap/caxis bar
% - No plane sliders: use plane edit boxes + mouse wheel scrolling on axes
% - Right side shows: Atlas underlay + Anatomy overlay (opacity + intensity + colormap)
% - Atlas options restored: Vascular / Histology / Regions
% - Apply + Save Transformation matrix panel with clear labels
% - Help + Close buttons (bottom right)
% - Robust index clamping (fixes "Index exceeds matrix dimensions")
% - Debounced heavy line refresh to reduce lag
%
% Usage:
%   R = registration_ccf(atlas, scananatomy)
%   R = registration_ccf(atlas, scananatomy, InitialTransf)
%   R = registration_ccf(atlas, scananatomy, InitialTransf, logFcn, saveDir)
%
% logFcn  : function handle like @(msg)disp(msg) or @(msg)addLog(msg)
% saveDir : directory where Transformation.mat is written

classdef registration_ccf < handle

    properties
        H
        ms1
        ms2
        DataNoScale
        scale
        r1
        r2
        r3
        Trot
        TF
        T0
        mapRegions
        mapHistology
        mapVascular
        linmap
        hlinesC
        hlinesT
        hlinesS

        % overlay controls
        overlayOpacity = 0.65        % 0..1
        overlayIntensity = 1.0       % 0.4..1.6 window factor
        overlayCmapName = 'hot'      % overlay colormap name

        % external integration
        logFcn = []
        saveDir = ''

        % performance
        debounceTimer
        pendingFullRefresh = false
    end

   properties (Access=protected)
    % LEFT: atlas RGB images
    im1
    im2
    im3

    % RIGHT: atlas underlay RGB
    im4Under
    im5Under
    im6Under

    % RIGHT: anatomy overlay (2D scalar)
    im4
    im5
    im6

    % crosshair lines (left)
    line1x
    line1y
    line2x
    line2y
    line3x
    line3y

    % crosshair lines (right)
    line4x
    line4y
    line5x
    line5y
    line6x
    line6y

    % UI controls
    uiEditX
    uiEditY
    uiEditZ
    uiSliceInfo

    uiOpacity
    uiIntensity
    uiCmapPopup
    uiOverlayStatus

    uiScaleX
    uiScaleY
    uiScaleZ
    uiApply
    uiSave
    uiSaveStatus

    uiAtlasGroup
    uiAtlasVasc
    uiAtlasHist
    uiAtlasReg

    uiHelp
    uiClose

    % axis labels (right)
    uiLab4
    uiLab5
    uiLab6
end


    methods
        function R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir)

            % ----------------------------
            % optional args
            % ----------------------------
            if nargin >= 3 && ~isempty(initialTransf)
                R.T0 = initialTransf.M;
            else
                R.T0 = eye(4);
            end
            if nargin >= 4 && ~isempty(logFcn)
                R.logFcn = logFcn;
            else
                R.logFcn = [];
            end
            if nargin >= 5 && ~isempty(saveDir) && exist(saveDir,'dir')
                R.saveDir = saveDir;
            else
                R.saveDir = pwd;
            end

            R.log(sprintf('[Atlas GUI] Save directory: %s', R.saveDir));

            % ----------------------------
            % equalize + resample scan to atlas space (paper behavior)
            % ----------------------------
            scananatomy.Data = equalizeImages(double(scananatomy.Data));

            tmp = interpolate3D(atlas, scananatomy);

            % ms2 is the anatomy scan in atlas space
            R.ms2 = mapscan(double(tmp.Data), hot(256), 'fix');
            % default viewing window (will be adjusted by intensity slider)
            R.ms2.caxis = [0.10 0.80];

            % atlas maps
            R.mapHistology = mapscan(atlas.Histology, gray(256), 'index');
            R.mapVascular  = mapscan(atlas.Vascular,  gray(256), 'auto');
            R.mapRegions   = mapscan(atlas.Regions,   atlas.infoRegions.rgb, 'index');

            R.ms1 = R.mapVascular;
            R.linmap = atlas.Lines;

            % base volume for warping
            R.DataNoScale = R.ms2.D;

            % init transform state
            R.scale = [1 1 1];
            R.Trot  = eye(4);
            R.TF    = eye(4);

            % ----------------------------
            % build dark GUI
            % ----------------------------
            R.buildGUI();

            % timer for debounced full refresh (lines are expensive)
            R.debounceTimer = timer( ...
                'ExecutionMode','singleShot', ...
                'StartDelay',0.12, ...
                'TimerFcn',@(~,~)R.refreshFull());

            % init move handles (drag/rotate on right overlay)
            R.restartMove();

            % apply initial transform and refresh
            R.apply();
            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        function delete(R)
            try
                if ~isempty(R.debounceTimer) && isvalid(R.debounceTimer)
                    stop(R.debounceTimer);
                    delete(R.debounceTimer);
                end
            catch
            end
        end

        % ==========================================================
        % GUI creation
        % ==========================================================
        function buildGUI(R)

            scr = get(0,'ScreenSize');
            W = min(1600, scr(3)-160);
            Hh = min(950,  scr(4)-140);
            x0 = max(40, floor((scr(3)-W)/2));
            y0 = max(40, floor((scr(4)-Hh)/2));

            bg = [0.06 0.06 0.06];
            fg = [0.95 0.95 0.95];
            panelBG = [0.10 0.10 0.10];
            panelBG2 = [0.12 0.12 0.12];

            f = figure( ...
                'Name','Atlas GUI', ...
                'Color',bg, ...
                'MenuBar','none', ...
                'ToolBar','none', ...
                'NumberTitle','off', ...
                'Position',[x0 y0 W Hh]);

            R.H.figure1 = f;

            % scrolling
            set(f,'WindowScrollWheelFcn',@(src,evt)R.onScroll(evt));

            % ----------------------------------------------------------
            % layout
            % ----------------------------------------------------------
            leftX  = 0.03;
            midX   = 0.36;
            ctrlX  = 0.69;
            axW    = 0.30;
            axH    = 0.24;
            gapY   = 0.04;

            yTop = 0.70;
            yMid = yTop - axH - gapY;
            yBot = yMid - axH - gapY;

            % title
            uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.03 0.94 0.64 0.045], ...
                'String','Atlas GUI — Registration to Allen CCF', ...
                'BackgroundColor',bg, ...
                'ForegroundColor',fg, ...
                'FontSize',18, ...
                'FontWeight','bold', ...
                'HorizontalAlignment','left');

            % slice info (top right)
            R.uiSliceInfo = uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.69 0.94 0.28 0.045], ...
                'String','X: -/-   Y: -/-   Z: -/-', ...
                'BackgroundColor',bg, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'FontSize',12, ...
                'FontWeight','bold', ...
                'HorizontalAlignment','right');

            % ----------------------------------------------------------
            % Axes (LEFT: atlas)
            % ----------------------------------------------------------
            R.H.axes1 = axes('Parent',f,'Units','normalized','Position',[leftX yTop axW axH], 'Color','k');
            R.H.axes2 = axes('Parent',f,'Units','normalized','Position',[leftX yMid axW axH], 'Color','k');
            R.H.axes3 = axes('Parent',f,'Units','normalized','Position',[leftX yBot axW axH], 'Color','k');

            % ----------------------------------------------------------
            % Axes (RIGHT: atlas underlay + anatomy overlay)
            % ----------------------------------------------------------
            R.H.axes4 = axes('Parent',f,'Units','normalized','Position',[midX yTop axW axH], 'Color','k');
            R.H.axes5 = axes('Parent',f,'Units','normalized','Position',[midX yMid axW axH], 'Color','k');
            R.H.axes6 = axes('Parent',f,'Units','normalized','Position',[midX yBot axW axH], 'Color','k');

            % labels for right axes (requested)
            R.uiLab4 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yTop+axH+0.005 axW 0.02], ...
                'String','Coronal', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            R.uiLab5 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yMid+axH+0.005 axW 0.02], ...
                'String','Sagittal', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            R.uiLab6 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yBot+axH+0.005 axW 0.02], ...
                'String','Axial', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            % axes cosmetics
            axAll = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];
            for k = 1:numel(axAll)
                axis(axAll(k),'image');
                axis(axAll(k),'off');
            end

            % ----------------------------------------------------------
            % Controls panel (right side)
            % ----------------------------------------------------------
            ctrlPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[ctrlX 0.10 0.28 0.82], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'Title','Controls', ...
                'FontSize',12, ...
                'FontWeight','bold');

            % Overlay panel
            ovPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.63 0.88 0.34], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Anatomy overlay', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.78 0.35 0.14], ...
                'String','Opacity', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiOpacity = uicontrol(ovPanel,'Style','slider','Units','normalized', ...
                'Position',[0.42 0.82 0.52 0.10], ...
                'Min',0,'Max',1,'Value',R.overlayOpacity, ...
                'BackgroundColor',panelBG2, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.56 0.35 0.14], ...
                'String','Intensity', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            % intensity range deliberately moderate (you asked to reduce dynamic range)
            R.uiIntensity = uicontrol(ovPanel,'Style','slider','Units','normalized', ...
                'Position',[0.42 0.60 0.52 0.10], ...
                'Min',0.60,'Max',1.40,'Value',R.overlayIntensity, ...
                'BackgroundColor',panelBG2, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.34 0.35 0.14], ...
                'String','Overlay colormap', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            cmapList = {'hot','gray','parula','jet','winter','autumn','spring','summer','bone','copper'};
            R.uiCmapPopup = uicontrol(ovPanel,'Style','popupmenu','Units','normalized', ...
                'Position',[0.42 0.36 0.52 0.14], ...
                'String',cmapList, ...
                'Value',find(strcmp(cmapList,R.overlayCmapName),1,'first'), ...
                'BackgroundColor',[0.15 0.15 0.15], ...
                'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            R.uiOverlayStatus = uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.08 0.88 0.16], ...
                'String','', ...
                'BackgroundColor',panelBG2,'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left','FontSize',9);

            % Transform panel
            trPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.33 0.88 0.27], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Transformation matrix', ...
                'FontSize',11, ...
                'FontWeight','bold');

            % scale edits
            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.70 0.22 0.18], ...
                'String','Scale X', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleX = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.28 0.73 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.48 0.70 0.22 0.18], ...
                'String','Scale Y', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleY = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.70 0.73 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.48 0.22 0.18], ...
                'String','Scale Z', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleZ = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.28 0.51 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            % apply/save
            R.uiApply = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.06 0.16 0.40 0.25], ...
                'String','1. Apply', ...
                'BackgroundColor',[0.20 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onApply());

            R.uiSave = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.52 0.16 0.42 0.25], ...
                'String','2. Save Transformation matrix', ...
                'BackgroundColor',[0.15 0.70 0.55], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onSave());

            R.uiSaveStatus = uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.02 0.88 0.12], ...
                'String','', ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left', ...
                'FontSize',9);

            % Plane panel (no sliders, just edits + scroll)
            plPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.16 0.88 0.14], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Planes (scroll on images)', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.55 0.12 0.35], ...
                'String','X', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');
            R.uiEditX = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.12 0.60 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.36 0.55 0.12 0.35], ...
                'String','Y', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');
            R.uiEditY = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.42 0.60 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.66 0.55 0.12 0.35], ...
                'String','Z', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');
            R.uiEditZ = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.72 0.60 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            % Help + Close buttons bottom right (requested)
            R.uiHelp = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.06 0.04 0.42 0.08], ...
                'String','HELP', ...
                'BackgroundColor',[0.25 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onHelp());

            R.uiClose = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.52 0.04 0.42 0.08], ...
                'String','CLOSE', ...
                'BackgroundColor',[0.85 0.25 0.25], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onClose());

            % ----------------------------------------------------------
            % Atlas mode panel (BOTTOM LEFT) — requested restored
            % ----------------------------------------------------------
            atlasPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[0.03 0.03 0.63 0.065], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'Title','Atlas underlay (left + right)', ...
                'FontSize',11, ...
                'FontWeight','bold');

            R.uiAtlasGroup = uibuttongroup(atlasPanel, ...
                'Units','normalized', ...
                'Position',[0.01 0.05 0.98 0.90], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'SelectionChangedFcn',@(src,evt)R.onAtlasMode(evt.NewValue.Tag));

            R.uiAtlasVasc = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized','Position',[0.05 0.15 0.25 0.70], ...
                'String','Vascular', 'Tag','vascular', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','Value',1);

            R.uiAtlasHist = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized','Position',[0.35 0.15 0.25 0.70], ...
                'String','Histology', 'Tag','histology', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold');

            R.uiAtlasReg = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized','Position',[0.65 0.15 0.25 0.70], ...
                'String','Regions', 'Tag','regions', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold');

            % ----------------------------------------------------------
            % Create image objects
            % ----------------------------------------------------------
            % Left atlas images are truecolor RGB
            R.im1 = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes1);
            R.im2 = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes2);
            R.im3 = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes3); % axial displayed permuted

            % Right: underlay atlas (RGB) + overlay anatomy (scalar)
            axes(R.H.axes4); cla(R.H.axes4);
            R.im4Under = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes4);
            hold(R.H.axes4,'on');
            R.im4 = imagesc(zeros(R.ms2.ny, R.ms2.nz), 'Parent', R.H.axes4);
            set(R.im4,'AlphaData',R.overlayOpacity);
            hold(R.H.axes4,'off');

            axes(R.H.axes5); cla(R.H.axes5);
            R.im5Under = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes5);
            hold(R.H.axes5,'on');
            R.im5 = imagesc(zeros(R.ms2.nx, R.ms2.nz), 'Parent', R.H.axes5);
            set(R.im5,'AlphaData',R.overlayOpacity);
            hold(R.H.axes5,'off');

            axes(R.H.axes6); cla(R.H.axes6);
            R.im6Under = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes6); % axial permuted
            hold(R.H.axes6,'on');
            R.im6 = imagesc(zeros(R.ms2.ny, R.ms2.nx), 'Parent', R.H.axes6);      % axial permuted
            set(R.im6,'AlphaData',R.overlayOpacity);
            hold(R.H.axes6,'off');

            % per-axes colormap for overlay (only affects right overlay images)
            R.applyOverlayColormap();

            % Crosshairs (create once, update only)
            % axes1 coronal: y-z plane (ny x nz): row=y0, col=z0
            R.line1x = line(R.H.axes1, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line1y = line(R.H.axes1, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % axes2 sagittal: x-z plane (nx x nz): row=x0, col=z0
            R.line2x = line(R.H.axes2, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1]);
            R.line2y = line(R.H.axes2, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1]);

            % axes3 axial: y-x plane (ny x nx) displayed: row=y0, col=x0
            R.line3x = line(R.H.axes3, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line3y = line(R.H.axes3, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % axes4 coronal (same as axes1)
            R.line4x = line(R.H.axes4, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line4y = line(R.H.axes4, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % axes5 sagittal (same as axes2)
            R.line5x = line(R.H.axes5, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1]);
            R.line5y = line(R.H.axes5, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1]);

            % axes6 axial (same as axes3)
            R.line6x = line(R.H.axes6, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line6y = line(R.H.axes6, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % init line containers
            R.hlinesC = gobjects(0);
            R.hlinesT = gobjects(0);
            R.hlinesS = gobjects(0);

            % init plane edits
            set(R.uiEditX,'String',num2str(R.ms1.x0));
            set(R.uiEditY,'String',num2str(R.ms1.y0));
            set(R.uiEditZ,'String',num2str(R.ms1.z0));
        end

        % ==========================================================
        % Move handles on right overlay
        % ==========================================================
        function restartMove(R)
            % create moveimage on the overlay images (axes4/5/6)
            try
                R.r1 = moveimage(R.H.axes4);
                R.r2 = moveimage(R.H.axes5);
                R.r3 = moveimage(R.H.axes6);
            catch ME
                R.log(['[Atlas GUI] moveimage init warning: ' ME.message]);
            end
        end

        % ==========================================================
        % Apply transform to 3D volume (paper behavior)
        % ==========================================================
        function apply(R)
            tot = build3DrotationMatrix(R);
            R.Trot = R.Trot * tot;

            % scale
            TS = eye(4);
            TS(1,1)=R.scale(1);
            TS(2,2)=R.scale(2);
            TS(3,3)=R.scale(3);

            R.TF = R.T0 * TS * R.Trot;

            m = affine3d(R.TF);
            ref = imref3d(size(R.ms1.D)); % atlas size

            % warp
            R.ms2.setData(imwarp(R.DataNoScale, m, 'OutputView', ref));

            % reset move transforms after applying
            if ~isempty(R.r1), R.r1.T0 = eye(3); end
            if ~isempty(R.r2), R.r2.T0 = eye(3); end
            if ~isempty(R.r3), R.r3.T0 = eye(3); end
        end

        % ==========================================================
        % Overlay controls
        % ==========================================================
        function applyOverlayColormap(R)
            % apply only on right axes (overlay images are scalar)
            try
                cmapList = get(R.uiCmapPopup,'String');
                idx = get(R.uiCmapPopup,'Value');
                if iscell(cmapList)
                    R.overlayCmapName = cmapList{idx};
                else
                    R.overlayCmapName = cmapList(idx,:);
                end
            catch
                % if popup not ready yet
            end

            try
                map = feval(R.overlayCmapName, 256);
            catch
                map = hot(256);
                R.overlayCmapName = 'hot';
            end

            colormap(R.H.axes4, map);
            colormap(R.H.axes5, map);
            colormap(R.H.axes6, map);
        end

        function onOverlayChanged(R)
            % read sliders
            if ~isempty(R.uiOpacity) && isgraphics(R.uiOpacity)
                R.overlayOpacity = get(R.uiOpacity,'Value');
            end
            if ~isempty(R.uiIntensity) && isgraphics(R.uiIntensity)
                R.overlayIntensity = get(R.uiIntensity,'Value');
            end
            R.applyOverlayColormap();

            % update overlay alpha without heavy work
            if isgraphics(R.im4), set(R.im4,'AlphaData',R.overlayOpacity); end
            if isgraphics(R.im5), set(R.im5,'AlphaData',R.overlayOpacity); end
            if isgraphics(R.im6), set(R.im6,'AlphaData',R.overlayOpacity); end

            set(R.uiOverlayStatus,'String',sprintf('Opacity %.2f | Intensity %.2f | %s', ...
                R.overlayOpacity, R.overlayIntensity, R.overlayCmapName));

            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Planes (edit boxes)
        % ==========================================================
        function onPlaneEdited(R)
            x = str2double(get(R.uiEditX,'String'));
            y = str2double(get(R.uiEditY,'String'));
            z = str2double(get(R.uiEditZ,'String'));

            if isnan(x), x = R.ms1.x0; end
            if isnan(y), y = R.ms1.y0; end
            if isnan(z), z = R.ms1.z0; end

            R.ms1.x0 = round(x);
            R.ms1.y0 = round(y);
            R.ms1.z0 = round(z);

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;

            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Atlas mode change
        % ==========================================================
        function onAtlasMode(R, tag)
            switch lower(tag)
                case 'vascular'
                    R.ms1 = R.mapVascular;
                case 'histology'
                    R.ms1 = R.mapHistology;
                case 'regions'
                    R.ms1 = R.mapRegions;
                otherwise
                    R.ms1 = R.mapVascular;
            end
            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Apply button
        % ==========================================================
        function onApply(R)
            % scale from edits
            sx = str2double(get(R.uiScaleX,'String')); if isnan(sx) || sx<=0, sx=1; end
            sy = str2double(get(R.uiScaleY,'String')); if isnan(sy) || sy<=0, sy=1; end
            sz = str2double(get(R.uiScaleZ,'String')); if isnan(sz) || sz<=0, sz=1; end
            R.scale = [sx sy sz];

            set(R.H.figure1,'Pointer','watch'); drawnow;
            R.apply();
            R.refreshFast(false);
            R.scheduleFullRefresh();
            set(R.H.figure1,'Pointer','arrow');

            set(R.uiSaveStatus,'String','Applied.');
            R.log('[Atlas GUI] Apply executed.');
        end

        % ==========================================================
        % Save button
        % ==========================================================
        function onSave(R)
            Transf.M = R.TF;
            Transf.size = size(R.ms1.D);

            outFile = fullfile(R.saveDir,'Transformation.mat');
            try
                save(outFile,'Transf');
                msg = sprintf('[Atlas GUI] Saved Transformation.mat -> %s', outFile);
                set(R.uiSaveStatus,'String','Saved Transformation.mat');
                R.log(msg);
            catch ME
                set(R.uiSaveStatus,'String',['Save failed: ' ME.message]);
                R.log(['[Atlas GUI] Save failed: ' ME.message]);
            end
        end

        % ==========================================================
        % Help + Close
        % ==========================================================
        function onHelp(R)
            bg = [0.06 0.06 0.06];
            fg = [0.95 0.95 0.95];

            hf = figure('Name','Atlas GUI — Help', ...
                'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
                'Position',[200 120 900 650]);

            txt = {
                'Atlas GUI — Manual registration help'
                ' '
                'LEFT (Atlas):'
                '  - Coronal / Sagittal / Axial slices of the selected atlas underlay.'
                '  - Use mouse wheel on any slice to move through that axis.'
                ' '
                'RIGHT (Registration view):'
                '  - Atlas underlay + Anatomy overlay.'
                '  - Drag overlay with LEFT mouse (translate).'
                '  - Drag overlay with RIGHT mouse (rotate).'
                '  - Use Opacity/Intensity/Colormap controls to improve visibility.'
                ' '
                'Planes:'
                '  - The X/Y/Z edit boxes are the current slice indices.'
                '  - Mouse wheel scrolling updates these indices.'
                ' '
                'Apply:'
                '  - Applies your current drag/rotate + scale to the full 3D volume.'
                ' '
                'Save Transformation matrix:'
                '  - Writes Transformation.mat into the configured save directory.'
                ' '
                'Tip (performance):'
                '  - Scrolling updates images immediately; atlas boundary lines refresh with a small delay.'
            };

            uicontrol(hf,'Style','edit','Max',2,'Min',0, ...
                'Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontName','Consolas','FontSize',12, ...
                'HorizontalAlignment','left', ...
                'String',strjoin(txt,newline));
        end

        function onClose(R)
            try
                delete(R.H.figure1);
            catch
            end
        end

        % ==========================================================
        % Scroll handling
        % ==========================================================
        function onScroll(R, evt)
            % identify which axes is under pointer
            fig = R.H.figure1;
            try
                h = hittest(fig);
            catch
                h = [];
            end

            ax = [];
            if ~isempty(h)
                ax = ancestor(h,'axes');
            end
            if isempty(ax) || ~isgraphics(ax)
                return;
            end

            d = -evt.VerticalScrollCount;  % natural scrolling: wheel down -> +1 typically
            step = sign(d);
            if step == 0, return; end

            if ax == R.H.axes1 || ax == R.H.axes4
                R.ms1.x0 = R.ms1.x0 + step;
            elseif ax == R.H.axes2 || ax == R.H.axes5
                R.ms1.y0 = R.ms1.y0 + step;
            elseif ax == R.H.axes3 || ax == R.H.axes6
                R.ms1.z0 = R.ms1.z0 + step;
            else
                return;
            end

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;

            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        function scheduleFullRefresh(R)
            % debounce expensive line refresh
            R.pendingFullRefresh = true;
            try
                if ~isempty(R.debounceTimer) && isvalid(R.debounceTimer)
                    stop(R.debounceTimer);
                    start(R.debounceTimer);
                end
            catch
                % if timer fails, just do full refresh directly
                R.refreshFull();
            end
        end

        % ==========================================================
        % Refresh (fast vs full)
        % ==========================================================
        function refreshFull(R)
            if ~R.pendingFullRefresh
                return;
            end
            R.pendingFullRefresh = false;
            R.refreshFast(true);
        end

        function refreshFast(R, doLines)

            % --- robust bounds to avoid index errors ---
            R.clampIndices();

            x0 = R.ms1.x0;
            y0 = R.ms1.y0;
            z0 = R.ms1.z0;

            % Update slice label (X/Y/Z)
            set(R.uiSliceInfo,'String',sprintf('X: %d/%d   Y: %d/%d   Z: %d/%d', ...
                x0, R.ms1.nx, y0, R.ms1.ny, z0, R.ms1.nz));

            % update plane edits
            set(R.uiEditX,'String',num2str(x0));
            set(R.uiEditY,'String',num2str(y0));
            set(R.uiEditZ,'String',num2str(z0));

            % ---------------------------------------------------------
            % LEFT atlas RGB from mapscan
            % ---------------------------------------------------------
            [a1,a2,a3] = R.ms1.cuts();  % a1 coronal, a2 sagittal, a3 axial
            set(R.im1,'CData',a1);
            set(R.im2,'CData',a2);
            set(R.im3,'CData',permute(a3,[2 1 3])); % axial orientation like original

            % ---------------------------------------------------------
            % RIGHT underlay atlas (same selection)
            % ---------------------------------------------------------
            set(R.im4Under,'CData',a1);
            set(R.im5Under,'CData',a2);
            set(R.im6Under,'CData',permute(a3,[2 1 3]));

            % ---------------------------------------------------------
            % RIGHT overlay anatomy slices (scalar), with intensity window
            % ---------------------------------------------------------
            ms2 = R.ms2;
            % intensity affects the window (reduced dynamic range requested)
            baseWin = [0.10 0.80];
            cen = mean(baseWin);
            half = (baseWin(2)-baseWin(1))/2;
            half = half / R.overlayIntensity; % higher intensity -> tighter window -> stronger contrast
            win = [cen-half, cen+half];
            win(1) = max(0, win(1));
            win(2) = min(1, win(2));
            if win(2) <= win(1), win = baseWin; end

            % coronal: x fixed -> ny x nz
            sx = squeeze(ms2.D(x0,:,:));
            % sagittal: y fixed -> nx x nz
            sy = squeeze(ms2.D(:,y0,:));
            % axial: z fixed -> nx x ny; display permuted -> ny x nx
            sz = squeeze(ms2.D(:,:,z0));
            sz = sz'; % permute [2 1]

            set(R.H.axes4,'CLim',win);
            set(R.H.axes5,'CLim',win);
            set(R.H.axes6,'CLim',win);

            set(R.im4,'CData',sx);
            set(R.im5,'CData',sy);
            set(R.im6,'CData',sz);

            % keep overlay alpha
            set(R.im4,'AlphaData',R.overlayOpacity);
            set(R.im5,'AlphaData',R.overlayOpacity);
            set(R.im6,'AlphaData',R.overlayOpacity);

            % update crosshairs (pixel coordinates)
            % axes1 / axes4 coronal ny x nz: row=y0, col=z0
            set(R.line1x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line1y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            set(R.line4x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line4y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            % axes2 / axes5 sagittal nx x nz: row=x0, col=z0
            set(R.line2x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line2y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            set(R.line5x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line5y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            % axes3 / axes6 axial displayed ny x nx: row=y0, col=x0
            set(R.line3x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line3y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            set(R.line6x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line6y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            % ---------------------------------------------------------
            % expensive atlas boundary lines (debounced)
            % ---------------------------------------------------------
            if doLines
                % clear + redraw only on right side (comparison view)
                delete(R.hlinesC); delete(R.hlinesT); delete(R.hlinesS);
                R.hlinesC = addLines(R.H.axes4, R.linmap.Cor, x0);
                R.hlinesT = addLines(R.H.axes5, R.linmap.Tra, y0);
                R.hlinesS = addLines(R.H.axes6, R.linmap.Sag, z0);
            end

            % ---------------------------------------------------------
            % keep moveimage base consistent after slice changes
            % ---------------------------------------------------------
            try
                if ~isempty(R.r1), R.r1.setBaseFromImage(); end
                if ~isempty(R.r2), R.r2.setBaseFromImage(); end
                if ~isempty(R.r3), R.r3.setBaseFromImage(); end
            catch
            end

            drawnow limitrate;
        end

        function clampIndices(R)
            % clamp indices to BOTH ms1 and ms2 bounds (robust)
            nx = min(R.ms1.nx, size(R.ms2.D,1));
            ny = min(R.ms1.ny, size(R.ms2.D,2));
            nz = min(R.ms1.nz, size(R.ms2.D,3));

            R.ms1.nx = nx; R.ms1.ny = ny; R.ms1.nz = nz;
            R.ms2.nx = nx; R.ms2.ny = ny; R.ms2.nz = nz;

            R.ms1.x0 = max(1, min(nx, R.ms1.x0));
            R.ms1.y0 = max(1, min(ny, R.ms1.y0));
            R.ms1.z0 = max(1, min(nz, R.ms1.z0));

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;
        end

        % ==========================================================
        % logging helper
        % ==========================================================
        function log(R, msg)
            if isempty(msg), return; end
            try
                if ~isempty(R.logFcn) && isa(R.logFcn,'function_handle')
                    R.logFcn(msg);
                else
                    % fallback
                    % fprintf('%s\n',msg);
                end
            catch
            end
        end
    end
end

% ==========================================================
% Helpers (local functions)
% ==========================================================
function DataNorm = equalizeImages(Data)
    DataNorm = Data - min(Data(:));
    mx = max(DataNorm(:));
    if mx > 0
        DataNorm = DataNorm ./ mx;
    end
    m = median(DataNorm(:));
    if m <= 0
        m = 0.5;
    end
    comp = -2/log2(m);
    DataNorm = DataNorm.^comp;
    DataNorm = DataNorm - min(DataNorm(:));
    mx = max(DataNorm(:));
    if mx > 0
        DataNorm = DataNorm ./ mx;
    end
end

function tot = build3DrotationMatrix(R)
    tot = eye(4);

    if isempty(R.r1) || isempty(R.r2) || isempty(R.r3)
        return;
    end

    tmpx = R.r1.T0;
    tmpx(1:2,1:2) = tmpx(1:2,1:2)';
    tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
    tmp = [tmpx(1,:); zeros(1,3); tmpx(2:end,:)];
    tmp = [tmp(:,1), zeros(4,1), tmp(:,2:end)];
    tmp(2,2)=1;
    tot = tot * tmp;

    tmpx = R.r2.T0;
    tmpx(1:2,1:2) = tmpx(1:2,1:2)';
    tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
    tmp = [zeros(1,3); tmpx(1:end,:)];
    tmp = [zeros(4,1), tmp(:,1:end)];
    tmp(1,1)=1;
    tot = tot * tmp;

    tmpx = R.r3.T0;
    tmpx(1:2,1:2) = tmpx(1:2,1:2)';
    tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
    tmp = [tmpx(1:2,:); zeros(1,3); tmpx(3:end,:)];
    tmp = [tmp(:,1:2), zeros(4,1), tmp(:,3:end)];
    tmp(3,3)=1;
    tot = tot * tmp;
end

function h = addLines(ax, LL, ip)
    if isempty(LL) || ip < 1 || ip > numel(LL)
        h = gobjects(0);
        return;
    end
    L = LL{ip};
    hold(ax,'on');
    nb = length(L);
    h = gobjects(nb,1);
    for ib = 1:nb
        x = L{ib};
        h(ib) = plot(ax, x(:,2), x(:,1), 'w:', 'LineWidth', 1);
    end
    hold(ax,'off');
end
