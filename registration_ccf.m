% Urban Lab - NERF empowered by imec, KU Leuven and VIB
% Mace Lab  - Max Planck institute of Neurobiology
% Authors:  G. MONTALDO, E. MACE
% Review & test: C.BRUNNER, M. GRILLET
% September 2020
%
% UPDATED for fUSI Studio integration (MATLAB 2017b compatible)
% - Programmatic dark GUI (does NOT use figviewscan.fig)
% - No bottom colormap/caxis bar
% - No plane sliders: use plane edit boxes + mouse wheel scrolling on axes (HOVER-based)
% - Right side shows: Atlas underlay + Anatomy overlay (opacity + intensity + colormap)
% - Atlas options: Vascular / Histology / Regions
% - Apply + Save Transformation matrix panel with clear labels
% - Help + Close buttons (bottom right)
% - Robust index clamping (fixes "Index exceeds matrix dimensions")
% - Debounced line refresh to reduce lag
%
% FIXES IN THIS VERSION:
% - Scroll is NOT "locked" to last-clicked axes (hover-based axes detection)
% - Plane labels renamed to Coronal/Sagittal/Axial (and top-right too)
% - Scale labels renamed to Coronal(X)/Sagittal(Y)/Axial(Z)
% - moveimage attaches to OVERLAY images explicitly (drag/rotate works)
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
        overlayIntensity = 1.0       % 0.60..1.40
        overlayCmapName = 'hot'

        % integration
        logFcn = []
        saveDir = ''

        % perf
        debounceTimer
        pendingFullRefresh = false

        % smooth scroll throttle
        lastScrollT = -inf
        scrollMinDt = 0.03  % ~30fps
    end

    properties (Access=protected)
        % LEFT images (atlas RGB)
        im1
        im2
        im3

        % RIGHT underlay (atlas RGB)
        im4Under
        im5Under
        im6Under

        % RIGHT overlay (anatomy scalar)
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

        % UI
        uiEditCor
        uiEditSag
        uiEditAxi
        uiSliceInfo

        uiOpacity
        uiIntensity
        uiCmapPopup
        uiOverlayStatus

        uiScaleCorX
        uiScaleSagY
        uiScaleAxiZ
        uiApply
        uiSave
        uiSaveStatus

        uiAtlasGroup
        uiAtlasVasc
        uiAtlasHist
        uiAtlasReg

        uiHelp
        uiClose

        uiLab4
        uiLab5
        uiLab6
    end

    methods
        function R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir)

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

            % equalize + resample anatomy into atlas space
            scananatomy.Data = equalizeImages(double(scananatomy.Data));
            tmp = interpolate3D(atlas, scananatomy);

            R.ms2 = mapscan(double(tmp.Data), hot(256), 'fix');
            R.ms2.caxis = [0.10 0.80];

            R.mapHistology = mapscan(atlas.Histology, gray(256), 'index');
            R.mapVascular  = mapscan(atlas.Vascular,  gray(256), 'auto');
            R.mapRegions   = mapscan(atlas.Regions,   atlas.infoRegions.rgb, 'index');

            R.ms1 = R.mapVascular;
            R.linmap = atlas.Lines;

            R.DataNoScale = R.ms2.D;

            R.scale = [1 1 1];
            R.Trot  = eye(4);
            R.TF    = eye(4);

            R.buildGUI();

            R.debounceTimer = timer( ...
                'ExecutionMode','singleShot', ...
                'StartDelay',0.12, ...
                'TimerFcn',@(~,~)R.refreshFull());

            R.restartMove();

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
        % GUI
        % ==========================================================
        function buildGUI(R)

            scr = get(0,'ScreenSize');
            W = min(1400, scr(3)-160);
            Hh = min(900,  scr(4)-140);
            x0 = max(40, floor((scr(3)-W)/2));
            y0 = max(40, floor((scr(4)-Hh)/2));

            bg = [0.06 0.06 0.06];
            fg = [0.95 0.95 0.95];
            panelBG  = [0.10 0.10 0.10];
            panelBG2 = [0.12 0.12 0.12];

            f = figure( ...
                'Name','Atlas GUI', ...
                'Color',bg, ...
                'MenuBar','none', ...
                'ToolBar','none', ...
                'NumberTitle','off', ...
                'Position',[x0 y0 W Hh]);

            R.H.figure1 = f;

            % HOVER-BASED scrolling (no locking)
            set(f,'WindowScrollWheelFcn',@(src,evt)R.onScroll(evt));

            % layout
            leftX = 0.03;
            midX  = 0.36;
            ctrlX = 0.69;
            axW   = 0.30;
            axH   = 0.24;
            gapY  = 0.04;

            yTop = 0.70;
            yMid = yTop - axH - gapY;
            yBot = yMid - axH - gapY;

            uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.03 0.94 0.64 0.045], ...
                'String','Atlas GUI — Registration to Allen CCF', ...
                'BackgroundColor',bg, ...
                'ForegroundColor',fg, ...
                'FontSize',18, ...
                'FontWeight','bold', ...
                'HorizontalAlignment','left');

            R.uiSliceInfo = uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.69 0.94 0.28 0.045], ...
                'String','Coronal: -/-   Sagittal: -/-   Axial: -/-', ...
                'BackgroundColor',bg, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'FontSize',12, ...
                'FontWeight','bold', ...
                'HorizontalAlignment','right');

            % axes left
            R.H.axes1 = axes('Parent',f,'Units','normalized','Position',[leftX yTop axW axH], 'Color','k');
            R.H.axes2 = axes('Parent',f,'Units','normalized','Position',[leftX yMid axW axH], 'Color','k');
            R.H.axes3 = axes('Parent',f,'Units','normalized','Position',[leftX yBot axW axH], 'Color','k');

            % axes right
            R.H.axes4 = axes('Parent',f,'Units','normalized','Position',[midX yTop axW axH], 'Color','k'); % Coronal
            R.H.axes5 = axes('Parent',f,'Units','normalized','Position',[midX yMid axW axH], 'Color','k'); % Axial
            R.H.axes6 = axes('Parent',f,'Units','normalized','Position',[midX yBot axW axH], 'Color','k'); % Sagittal

            % right labels
            R.uiLab4 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yTop+axH+0.005 axW 0.02], ...
                'String','Coronal', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            R.uiLab5 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yMid+axH+0.005 axW 0.02], ...
                'String','Axial', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            R.uiLab6 = uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yBot+axH+0.005 axW 0.02], ...
                'String','Sagittal', 'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            axAll = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];
            for k = 1:numel(axAll)
                axis(axAll(k),'image');
                axis(axAll(k),'off');
                set(axAll(k),'Box','off','XColor',bg,'YColor',bg,'LineWidth',1);
            end

            % controls
            ctrlPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[ctrlX 0.10 0.28 0.82], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'Title','Controls', ...
                'FontSize',12, ...
                'FontWeight','bold', ...
                'BorderType','line', ...
                'HighlightColor',panelBG, ...
                'ShadowColor',panelBG);

            ovPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.63 0.88 0.34], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Anatomy overlay', ...
                'FontSize',11, ...
                'FontWeight','bold', ...
                'BorderType','line', ...
                'HighlightColor',panelBG2, ...
                'ShadowColor',panelBG2);

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
                'Value',max(1,find(strcmp(cmapList,R.overlayCmapName),1,'first')), ...
                'BackgroundColor',[0.15 0.15 0.15], ...
                'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            R.uiOverlayStatus = uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.08 0.88 0.16], ...
                'String','', ...
                'BackgroundColor',panelBG2,'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left','FontSize',9);

            trPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.33 0.88 0.27], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Transformation matrix', ...
                'FontSize',11, ...
                'FontWeight','bold', ...
                'BorderType','line', ...
                'HighlightColor',panelBG2, ...
                'ShadowColor',panelBG2);

            % NOTE: these are TRUE 3D scales (affect all views), but labeled by plane/axis
            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.70 0.40 0.18], ...
                'String','Scale Coronal (X)', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleCorX = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.46 0.73 0.16 0.18], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12], 'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.48 0.40 0.18], ...
                'String','Scale Sagittal (Y)', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleSagY = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.46 0.51 0.16 0.18], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12], 'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.26 0.40 0.18], ...
                'String','Scale Axial (Z)', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleAxiZ = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.46 0.29 0.16 0.18], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12], 'ForegroundColor',fg);

            R.uiApply = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.66 0.56 0.30 0.24], ...
                'String','1. Apply', ...
                'BackgroundColor',[0.20 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onApply());

            R.uiSave = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.66 0.28 0.30 0.24], ...
                'String','2. Save', ...
                'BackgroundColor',[0.15 0.70 0.55], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onSave());

            R.uiSaveStatus = uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.02 0.90 0.16], ...
                'String','', ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left', ...
                'FontSize',9);

            % Planes panel (renamed)
            plPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.16 0.88 0.14], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Planes (scroll on images)', ...
                'FontSize',11, ...
                'FontWeight','bold', ...
                'BorderType','line', ...
                'HighlightColor',panelBG2, ...
                'ShadowColor',panelBG2);

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.55 0.30 0.35], ...
                'String','Coronal', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditCor = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.28 0.60 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.50 0.55 0.22 0.35], ...
                'String','Sagittal', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditSag = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.70 0.60 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.10 0.30 0.35], ...
                'String','Axial', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditAxi = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.28 0.14 0.18 0.32], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            % help/close
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

            % atlas selection bottom-left
            atlasPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[0.03 0.03 0.63 0.065], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'Title','Atlas underlay (left + right)', ...
                'FontSize',11, ...
                'FontWeight','bold', ...
                'BorderType','line', ...
                'HighlightColor',panelBG, ...
                'ShadowColor',panelBG);

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
            % Create images
            % ----------------------------------------------------------
            % left
            R.im1 = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes1);
            R.im2 = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes2);
            R.im3 = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes3);

            % right (OVERLAY first -> but we still pass explicit handle to moveimage)
            cla(R.H.axes4);
            R.im4 = imagesc(zeros(R.ms2.ny, R.ms2.nz), 'Parent', R.H.axes4);
            set(R.im4,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes4,'on');
            R.im4Under = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes4);
            set(R.im4Under,'HitTest','off');
            hold(R.H.axes4,'off');
            uistack(R.im4,'top');

            cla(R.H.axes5); % AXIAL
            R.im5 = imagesc(zeros(R.ms2.ny, R.ms2.nx), 'Parent', R.H.axes5);
            set(R.im5,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes5,'on');
            R.im5Under = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes5);
            set(R.im5Under,'HitTest','off');
            hold(R.H.axes5,'off');
            uistack(R.im5,'top');

            cla(R.H.axes6); % SAGITTAL
            R.im6 = imagesc(zeros(R.ms2.nx, R.ms2.nz), 'Parent', R.H.axes6);
            set(R.im6,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes6,'on');
            R.im6Under = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes6);
            set(R.im6Under,'HitTest','off');
            hold(R.H.axes6,'off');
            uistack(R.im6,'top');

            R.applyOverlayColormap();

            % crosshairs left
            R.line1x = line(R.H.axes1, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line1y = line(R.H.axes1, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1]);

            R.line2x = line(R.H.axes2, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1]);
            R.line2y = line(R.H.axes2, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1]);

            R.line3x = line(R.H.axes3, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line3y = line(R.H.axes3, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % crosshairs right
            % axes4 coronal (ny x nz): row=y0 col=z0
            R.line4x = line(R.H.axes4, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line4y = line(R.H.axes4, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % axes5 axial (ny x nx): row=y0 col=x0
            R.line5x = line(R.H.axes5, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1]);
            R.line5y = line(R.H.axes5, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1]);

            % axes6 sagittal (nx x nz): row=x0 col=z0
            R.line6x = line(R.H.axes6, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1]);
            R.line6y = line(R.H.axes6, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1]);

            R.hlinesC = gobjects(0);
            R.hlinesT = gobjects(0);
            R.hlinesS = gobjects(0);

            % init plane edits
            set(R.uiEditCor,'String',num2str(R.ms1.x0));
            set(R.uiEditSag,'String',num2str(R.ms1.y0));
            set(R.uiEditAxi,'String',num2str(R.ms1.z0));
        end

        % ==========================================================
        % moveimage on overlay (explicit)
        % ==========================================================
        function restartMove(R)
            try
                R.r1 = moveimage(R.H.axes4, R.im4);
                R.r2 = moveimage(R.H.axes5, R.im5);
                R.r3 = moveimage(R.H.axes6, R.im6);
            catch ME
                R.log(['[Atlas GUI] moveimage init warning: ' ME.message]);
            end
        end

        % ==========================================================
        % Apply 3D transform
        % ==========================================================
        function apply(R)
            tot = build3DrotationMatrix(R);
            R.Trot = R.Trot * tot;

            TS = eye(4);
            TS(1,1)=R.scale(1);
            TS(2,2)=R.scale(2);
            TS(3,3)=R.scale(3);

            R.TF = R.T0 * TS * R.Trot;

            m = affine3d(R.TF);
            ref = imref3d(size(R.ms1.D));

            R.ms2.setData(imwarp(R.DataNoScale, m, 'OutputView', ref));

            if ~isempty(R.r1), R.r1.resetTransform(); end
            if ~isempty(R.r2), R.r2.resetTransform(); end
            if ~isempty(R.r3), R.r3.resetTransform(); end
        end

        % ==========================================================
        % Overlay controls
        % ==========================================================
        function applyOverlayColormap(R)
            try
                cmapList = get(R.uiCmapPopup,'String');
                idx = get(R.uiCmapPopup,'Value');
                if iscell(cmapList)
                    R.overlayCmapName = cmapList{idx};
                else
                    R.overlayCmapName = cmapList(idx,:);
                end
            catch
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
            if ~isempty(R.uiOpacity) && isgraphics(R.uiOpacity)
                R.overlayOpacity = get(R.uiOpacity,'Value');
            end
            if ~isempty(R.uiIntensity) && isgraphics(R.uiIntensity)
                R.overlayIntensity = get(R.uiIntensity,'Value');
            end

            R.applyOverlayColormap();

            if isgraphics(R.im4), set(R.im4,'AlphaData',R.overlayOpacity); end
            if isgraphics(R.im5), set(R.im5,'AlphaData',R.overlayOpacity); end
            if isgraphics(R.im6), set(R.im6,'AlphaData',R.overlayOpacity); end

            set(R.uiOverlayStatus,'String',sprintf('Opacity %.2f | Intensity %.2f | %s', ...
                R.overlayOpacity, R.overlayIntensity, R.overlayCmapName));

            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Planes edits (Coronal/Sagittal/Axial)
        % ==========================================================
        function onPlaneEdited(R)
            cor = round(str2double(get(R.uiEditCor,'String')));
            sag = round(str2double(get(R.uiEditSag,'String')));
            axi = round(str2double(get(R.uiEditAxi,'String')));

            if isnan(cor), cor = R.ms1.x0; end
            if isnan(sag), sag = R.ms1.y0; end
            if isnan(axi), axi = R.ms1.z0; end

            R.ms1.x0 = cor; % coronal index
            R.ms1.y0 = sag; % sagittal index
            R.ms1.z0 = axi; % axial index

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;

            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Atlas mode
        % ==========================================================
        function onAtlasMode(R, tag)
            switch lower(tag)
                case 'vascular',  R.ms1 = R.mapVascular;
                case 'histology', R.ms1 = R.mapHistology;
                case 'regions',   R.ms1 = R.mapRegions;
                otherwise,        R.ms1 = R.mapVascular;
            end
            R.refreshFast(false);
            R.scheduleFullRefresh();
        end

        % ==========================================================
        % Apply / Save
        % ==========================================================
        function onApply(R)
            sx = str2double(get(R.uiScaleCorX,'String')); if isnan(sx) || sx<=0, sx=1; end
            sy = str2double(get(R.uiScaleSagY,'String')); if isnan(sy) || sy<=0, sy=1; end
            sz = str2double(get(R.uiScaleAxiZ,'String')); if isnan(sz) || sz<=0, sz=1; end

            % TRUE 3D scaling (affects all views)
            R.scale = [sx sy sz];

            set(R.H.figure1,'Pointer','watch'); drawnow;
            R.apply();
            R.refreshFast(false);
            R.scheduleFullRefresh();
            set(R.H.figure1,'Pointer','arrow');

            set(R.uiSaveStatus,'String','Applied.');
            R.log('[Atlas GUI] Apply executed.');
        end

        function onSave(R)
            Transf.M = R.TF;
            Transf.size = size(R.ms1.D);

            outFile = fullfile(R.saveDir,'Transformation.mat');
            try
                save(outFile,'Transf');
                set(R.uiSaveStatus,'String','Saved Transformation.mat');
                R.log(sprintf('[Atlas GUI] Saved Transformation.mat -> %s', outFile));
            catch ME
                set(R.uiSaveStatus,'String',['Save failed: ' ME.message]);
                R.log(['[Atlas GUI] Save failed: ' ME.message]);
            end
        end

        % ==========================================================
        % Help / Close
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
                'SCROLL: hover over any slice and use mouse wheel (no clicking required).'
                ' '
                'RIGHT (Registration view):'
                '  - Drag overlay with LEFT mouse (translate)'
                '  - Drag overlay with RIGHT mouse (rotate)'
                ' '
                'Planes are indices: Coronal=X, Sagittal=Y, Axial=Z.'
                'Scaling is a true 3D affine scale (affects all views).'
            };

            uicontrol(hf,'Style','edit','Max',2,'Min',0, ...
                'Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontName','Consolas','FontSize',12, ...
                'HorizontalAlignment','left', ...
                'String',strjoin(txt,newline));
        end

        function onClose(R)
            try, delete(R.H.figure1); catch, end
        end

        % ==========================================================
        % Scroll (hover-based axes detection, not locked)
        % ==========================================================
        function onScroll(R, evt)
            t = now * 24*3600;
            if (t - R.lastScrollT) < R.scrollMinDt
                return;
            end
            R.lastScrollT = t;

            ax = R.getAxesUnderPointer();
            if isempty(ax) || ~isgraphics(ax), return; end

            step = -sign(evt.VerticalScrollCount);
            if step == 0, return; end

            % Map axes to index:
            % axes1/4 = coronal (x0), axes2 = sagittal(y0), axes3 = axial(z0)
            % right: axes4 coronal(x0), axes5 axial(z0), axes6 sagittal(y0)
            if ax == R.H.axes1 || ax == R.H.axes4
                R.ms1.x0 = R.ms1.x0 + step;
            elseif ax == R.H.axes2 || ax == R.H.axes6
                R.ms1.y0 = R.ms1.y0 + step;
            elseif ax == R.H.axes3 || ax == R.H.axes5
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

        function ax = getAxesUnderPointer(R)
            fig = R.H.figure1;
            cp = get(fig,'CurrentPoint'); % pixels (x,y)
            axList = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];

            ax = [];
            for k = 1:numel(axList)
                a = axList(k);
                if ~isgraphics(a), continue; end
                p = getpixelposition(a, true); % [x y w h] in figure pixels
                if cp(1) >= p(1) && cp(1) <= p(1)+p(3) && cp(2) >= p(2) && cp(2) <= p(2)+p(4)
                    ax = a;
                    return;
                end
            end
        end

        function scheduleFullRefresh(R)
            R.pendingFullRefresh = true;
            try
                if ~isempty(R.debounceTimer) && isvalid(R.debounceTimer)
                    stop(R.debounceTimer);
                    start(R.debounceTimer);
                end
            catch
                R.refreshFull();
            end
        end

        function refreshFull(R)
            if ~R.pendingFullRefresh, return; end
            R.pendingFullRefresh = false;
            R.refreshFast(true);
        end

        % ==========================================================
        % Refresh
        % ==========================================================
        function refreshFast(R, doLines)

            R.clampIndices();

            x0 = R.ms1.x0; % coronal index
            y0 = R.ms1.y0; % sagittal index
            z0 = R.ms1.z0; % axial index

            set(R.uiSliceInfo,'String',sprintf('Coronal: %d/%d   Sagittal: %d/%d   Axial: %d/%d', ...
                x0, R.ms1.nx, y0, R.ms1.ny, z0, R.ms1.nz));

            set(R.uiEditCor,'String',num2str(x0));
            set(R.uiEditSag,'String',num2str(y0));
            set(R.uiEditAxi,'String',num2str(z0));

            % atlas cuts
            [aCor, aSag, aAxi] = R.ms1.cuts(); % coronal, sagittal, axial

            % left: coronal, sagittal, axial
            set(R.im1,'CData',aCor);
            set(R.im2,'CData',aSag);
            set(R.im3,'CData',permute(aAxi,[2 1 3]));

            % right underlays:
            set(R.im4Under,'CData',aCor);                 % coronal
            set(R.im5Under,'CData',permute(aAxi,[2 1 3]));% axial
            set(R.im6Under,'CData',aSag);                 % sagittal

            % overlay window
            baseWin = [0.10 0.80];
            cen  = mean(baseWin);
            half = (baseWin(2)-baseWin(1))/2;
            half = half / R.overlayIntensity;
            win = [cen-half, cen+half];
            win(1) = max(0, win(1));
            win(2) = min(1, win(2));
            if win(2) <= win(1), win = baseWin; end

            ms2 = R.ms2;

            % coronal overlay: x fixed -> ny x nz
            oCor = squeeze(ms2.D(x0,:,:));

            % axial overlay: z fixed -> nx x ny -> display ny x nx
            oAxi = squeeze(ms2.D(:,:,z0))';
            % sagittal overlay: y fixed -> nx x nz
            oSag = squeeze(ms2.D(:,y0,:));

            set(R.H.axes4,'CLim',win);
            set(R.H.axes5,'CLim',win);
            set(R.H.axes6,'CLim',win);

            set(R.im4,'CData',oCor);
            set(R.im5,'CData',oAxi);
            set(R.im6,'CData',oSag);

            set(R.im4,'AlphaData',R.overlayOpacity);
            set(R.im5,'AlphaData',R.overlayOpacity);
            set(R.im6,'AlphaData',R.overlayOpacity);

            % crosshairs left
            set(R.line1x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line1y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            set(R.line2x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line2y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            set(R.line3x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line3y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            % crosshairs right
            % axes4 coronal
            set(R.line4x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line4y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            % axes5 axial (ny x nx)
            set(R.line5x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line5y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            % axes6 sagittal (nx x nz)
            set(R.line6x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line6y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            if doLines
                delete(R.hlinesC); delete(R.hlinesT); delete(R.hlinesS);

                idxCor = clampToNumel(R.linmap.Cor, x0);
                idxTra = bestLineIndex(R.linmap.Tra, R.ms1, x0, y0, z0); % auto-map to correct axis
                idxSag = bestLineIndex(R.linmap.Sag, R.ms1, x0, y0, z0);

                R.hlinesC = addLines(R.H.axes4, R.linmap.Cor, idxCor);
                R.hlinesT = addLines(R.H.axes5, R.linmap.Tra, idxTra); % axial panel
                R.hlinesS = addLines(R.H.axes6, R.linmap.Sag, idxSag); % sagittal panel
            end

            drawnow limitrate;
        end

        function clampIndices(R)
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

        function log(R, msg)
            if isempty(msg), return; end
            try
                if ~isempty(R.logFcn) && isa(R.logFcn,'function_handle')
                    R.logFcn(msg);
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
    if mx > 0, DataNorm = DataNorm ./ mx; end
    m = median(DataNorm(:));
    if m <= 0, m = 0.5; end
    comp = -2/log2(m);
    DataNorm = DataNorm.^comp;
    DataNorm = DataNorm - min(DataNorm(:));
    mx = max(DataNorm(:));
    if mx > 0, DataNorm = DataNorm ./ mx; end
end

function tot = build3DrotationMatrix(R)
    tot = eye(4);
    if isempty(R.r1) || isempty(R.r2) || isempty(R.r3), return; end

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

function idx = clampToNumel(LL, idx)
    n = numel(LL);
    if n < 1, idx = 1; return; end
    idx = max(1, min(n, idx));
end

function idx = bestLineIndex(LL, ms1, x0, y0, z0)
    % Pick the index whose dimension matches numel(LL)
    n = numel(LL);
    if n == ms1.nx
        idx = x0;
    elseif n == ms1.ny
        idx = y0;
    elseif n == ms1.nz
        idx = z0;
    else
        idx = max(1, min(n, round(n/2)));
    end
    idx = max(1, min(n, idx));
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
    for ib=1:nb
        x = L{ib};
        h(ib) = plot(ax, x(:,2), x(:,1), 'w:', 'LineWidth', 1);
    end
    hold(ax,'off');
end
