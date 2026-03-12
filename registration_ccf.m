classdef registration_ccf < handle

    properties
        H
        atlas
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
        hlinesS
        hlinesC
        hlinesT

        overlayOpacity = 0.65
        overlayIntensity = 1.0
        overlayCmapName = 'hot'

        logFcn = []
        saveDir = ''

        funcFiles = {}
        funcLabels = {}

        lastScrollT = -inf
        scrollMinDt = 0.03
    end

    properties (Access=protected)
        im1
        im2
        im3

        im4Under
        im5Under
        im6Under

        im4
        im5
        im6

        line1x
        line1y
        line2x
        line2y
        line3x
        line3y
        line4x
        line4y
        line5x
        line5y
        line6x
        line6y

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

        uiFuncPopup
        uiFuncPreview
        uiFuncRegister
        uiFuncStatus
    end

    methods
        function R = registration_ccf(atlas, scananatomy, varargin)
            % Supports:
            % R = registration_ccf(atlas, scananatomy)
            % R = registration_ccf(atlas, scananatomy, initialTransf)
            % R = registration_ccf(atlas, scananatomy, initialTransf, logFcn)
            % R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir)
            % R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir, funcCandidates)

            initialTransf = [];
            logFcn = [];
            saveDir = '';
            funcCandidates = struct('files',{{}},'labels',{{}});

            if numel(varargin) >= 1
                initialTransf = varargin{1};
            end
            if numel(varargin) >= 2
                logFcn = varargin{2};
            end
            if numel(varargin) >= 3
                saveDir = varargin{3};
            end
            if numel(varargin) >= 4
                funcCandidates = varargin{4};
            end

            if ~isempty(initialTransf) && isstruct(initialTransf) && isfield(initialTransf,'M')
                R.T0 = initialTransf.M;
            else
                R.T0 = eye(4);
            end

            if ~isempty(logFcn) && isa(logFcn,'function_handle')
                R.logFcn = logFcn;
            else
                R.logFcn = [];
            end

            if ~isempty(saveDir) && ischar(saveDir) && exist(saveDir,'dir')
                R.saveDir = saveDir;
            else
                R.saveDir = pwd;
            end

            if ~isempty(funcCandidates) && isstruct(funcCandidates)
                if isfield(funcCandidates,'files') && iscell(funcCandidates.files)
                    R.funcFiles = funcCandidates.files;
                end
                if isfield(funcCandidates,'labels') && iscell(funcCandidates.labels)
                    R.funcLabels = funcCandidates.labels;
                end
            end
            if isempty(R.funcLabels)
                R.funcLabels = R.funcFiles;
            end

            R.atlas = atlas;
            R.log(sprintf('[Atlas GUI] Save directory: %s', R.saveDir));

            scananatomy.Data = equalizeImages(double(scananatomy.Data));
            tmp = interpolate3D(atlas, scananatomy);

            R.ms2 = mapscan(double(tmp.Data), hot(256), 'fix');
            R.ms2.caxis = [0.10 0.80];

            R.mapHistology = mapscan(atlas.Histology, gray(256), 'index');
            R.mapVascular  = mapscan(atlas.Vascular, gray(256), 'auto');
            R.mapRegions   = mapscan(atlas.Regions, atlas.infoRegions.rgb, 'index');

            R.ms1 = R.mapVascular;
            R.linmap = atlas.Lines;

            R.scale = [1 1 1];
            R.Trot  = eye(4);
            R.TF    = eye(4);

            R.buildGUI();

            R.DataNoScale = R.ms2.D;

            R.restartMove();
            R.apply();
            R.refresh();
        end

        function buildGUI(R)

            scr = get(0,'ScreenSize');
            W = min(1420, scr(3)-120);
            Hh = min(920, scr(4)-100);
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
            set(f,'WindowScrollWheelFcn',@(src,evt)R.onScroll(evt));

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
                'String','Atlas GUI - Registration to Allen CCF', ...
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

            R.H.axes1 = axes('Parent',f,'Units','normalized','Position',[leftX yTop axW axH], 'Color','k');
            R.H.axes2 = axes('Parent',f,'Units','normalized','Position',[leftX yMid axW axH], 'Color','k');
            R.H.axes3 = axes('Parent',f,'Units','normalized','Position',[leftX yBot axW axH], 'Color','k');

            R.H.axes4 = axes('Parent',f,'Units','normalized','Position',[midX yTop axW axH], 'Color','k');
            R.H.axes5 = axes('Parent',f,'Units','normalized','Position',[midX yMid axW axH], 'Color','k');
            R.H.axes6 = axes('Parent',f,'Units','normalized','Position',[midX yBot axW axH], 'Color','k');

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

            axAll = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];
            for k = 1:numel(axAll)
                axis(axAll(k),'image');
                axis(axAll(k),'off');
                set(axAll(k),'Box','off','XColor',bg,'YColor',bg,'LineWidth',1);
            end

            ctrlPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[ctrlX 0.08 0.28 0.84], ...
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
                'Position',[0.06 0.67 0.88 0.30], ...
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
                'Position',[0.06 0.42 0.88 0.21], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Transformation matrix', ...
                'FontSize',11, ...
                'FontWeight','bold');

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

            funcPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.21 0.88 0.17], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Functional preview and register', ...
                'FontSize',11, ...
                'FontWeight','bold');

            popupStrings = {'No functional candidates found'};
            popupEnable = 'off';
            btnEnable = 'off';
            if ~isempty(R.funcLabels)
                popupStrings = R.funcLabels;
                popupEnable = 'on';
                btnEnable = 'on';
            end

            uicontrol(funcPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.72 0.24 0.16], ...
                'String','Selected file', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiFuncPopup = uicontrol(funcPanel,'Style','popupmenu','Units','normalized', ...
                'Position',[0.06 0.50 0.88 0.20], ...
                'String',popupStrings, ...
                'Value',1, ...
                'Enable',popupEnable, ...
                'BackgroundColor',[0.15 0.15 0.15], ...
                'ForegroundColor',fg);

            R.uiFuncPreview = uicontrol(funcPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.06 0.20 0.40 0.20], ...
                'String','Preview selected', ...
                'Enable',btnEnable, ...
                'BackgroundColor',[0.32 0.48 0.86], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onPreviewFunctional());

            R.uiFuncRegister = uicontrol(funcPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.54 0.20 0.40 0.20], ...
                'String','Register selected', ...
                'Enable',btnEnable, ...
                'BackgroundColor',[0.64 0.42 0.20], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onRegisterFunctional());

            R.uiFuncStatus = uicontrol(funcPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.02 0.88 0.12], ...
                'String','', ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left', ...
                'FontSize',9);

            plPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.06 0.09 0.88 0.09], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Planes (scroll on images)', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.42 0.22 0.35], ...
                'String','Coronal', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditCor = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.22 0.45 0.13 0.34], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.40 0.42 0.22 0.35], ...
                'String','Sagittal', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditSag = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.59 0.45 0.13 0.34], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(plPanel,'Style','text','Units','normalized', ...
                'Position',[0.74 0.42 0.16 0.35], ...
                'String','Axial', 'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');

            R.uiEditAxi = uicontrol(plPanel,'Style','edit','Units','normalized', ...
                'Position',[0.84 0.45 0.10 0.34], ...
                'String','1', 'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            R.uiHelp = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.06 0.01 0.42 0.06], ...
                'String','HELP', ...
                'BackgroundColor',[0.25 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onHelp());

            R.uiClose = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.52 0.01 0.42 0.06], ...
                'String','CLOSE', ...
                'BackgroundColor',[0.85 0.25 0.25], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onClose());

            atlasPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[0.03 0.03 0.63 0.05], ...
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
                'Units','normalized','Position',[0.05 0.10 0.25 0.80], ...
                'String','Vascular', 'Tag','vascular', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','Value',1);

            R.uiAtlasHist = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized','Position',[0.35 0.10 0.25 0.80], ...
                'String','Histology', 'Tag','histology', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold');

            R.uiAtlasReg = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized','Position',[0.65 0.10 0.25 0.80], ...
                'String','Regions', 'Tag','regions', ...
                'BackgroundColor',panelBG,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold');

            R.im1 = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes1);
            R.im2 = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes2);
            R.im3 = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes3);

            cla(R.H.axes4);
            R.im4Under = image(zeros(R.ms1.ny, R.ms1.nz, 3), 'Parent', R.H.axes4);
            set(R.im4Under,'HitTest','off');
            hold(R.H.axes4,'on');
            R.im4 = imagesc(zeros(R.ms2.ny, R.ms2.nz), 'Parent', R.H.axes4);
            set(R.im4,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes4,'off');
            uistack(R.im4,'top');

            cla(R.H.axes5);
            R.im5Under = image(zeros(R.ms1.nx, R.ms1.nz, 3), 'Parent', R.H.axes5);
            set(R.im5Under,'HitTest','off');
            hold(R.H.axes5,'on');
            R.im5 = imagesc(zeros(R.ms2.nx, R.ms2.nz), 'Parent', R.H.axes5);
            set(R.im5,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes5,'off');
            uistack(R.im5,'top');

            cla(R.H.axes6);
            R.im6Under = image(zeros(R.ms1.ny, R.ms1.nx, 3), 'Parent', R.H.axes6);
            set(R.im6Under,'HitTest','off');
            hold(R.H.axes6,'on');
            R.im6 = imagesc(zeros(R.ms2.ny, R.ms2.nx), 'Parent', R.H.axes6);
            set(R.im6,'AlphaData',R.overlayOpacity,'HitTest','on');
            hold(R.H.axes6,'off');
            uistack(R.im6,'top');

            R.applyOverlayColormap();

            R.line1x = line(R.H.axes1, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1], 'HitTest','off');
            R.line1y = line(R.H.axes1, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1], 'HitTest','off');

            R.line2x = line(R.H.axes2, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1], 'HitTest','off');
            R.line2y = line(R.H.axes2, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1], 'HitTest','off');

            R.line3x = line(R.H.axes3, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1], 'HitTest','off');
            R.line3y = line(R.H.axes3, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1], 'HitTest','off');

            R.line4x = line(R.H.axes4, [1 R.ms1.nz], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1], 'HitTest','off');
            R.line4y = line(R.H.axes4, [R.ms1.z0 R.ms1.z0], [1 R.ms1.ny], 'Color',[1 1 1], 'HitTest','off');

            R.line5x = line(R.H.axes5, [1 R.ms1.nz], [R.ms1.x0 R.ms1.x0], 'Color',[1 1 1], 'HitTest','off');
            R.line5y = line(R.H.axes5, [R.ms1.z0 R.ms1.z0], [1 R.ms1.nx], 'Color',[1 1 1], 'HitTest','off');

            R.line6x = line(R.H.axes6, [1 R.ms1.nx], [R.ms1.y0 R.ms1.y0], 'Color',[1 1 1], 'HitTest','off');
            R.line6y = line(R.H.axes6, [R.ms1.x0 R.ms1.x0], [1 R.ms1.ny], 'Color',[1 1 1], 'HitTest','off');

            R.hlinesS = gobjects(0);
            R.hlinesC = gobjects(0);
            R.hlinesT = gobjects(0);

            set(R.uiEditCor,'String',num2str(R.ms1.x0));
            set(R.uiEditSag,'String',num2str(R.ms1.y0));
            set(R.uiEditAxi,'String',num2str(R.ms1.z0));
        end

        function restartMove(R)
            R.r1 = moveimage(R.H.axes4, R.im4);
            R.r2 = moveimage(R.H.axes5, R.im5);
            R.r3 = moveimage(R.H.axes6, R.im6);
        end

        function tf = anyDragging(R)
            tf = safeIsDragging(R.r1) || safeIsDragging(R.r2) || safeIsDragging(R.r3);
        end

        function TransfNow = getCurrentTransform(R)
            TS = eye(4);
            TS(1,1) = R.scale(1);
            TS(2,2) = R.scale(2);
            TS(3,3) = R.scale(3);

            tot = build3DrotationMatrix(R);

            TransfNow = struct();
            TransfNow.M = R.T0 * TS * R.Trot * tot;
            TransfNow.size = size(R.ms1.D);
        end

        function apply(R)
            tot = build3DrotationMatrix(R);
            R.Trot = R.Trot * tot;

            TS = eye(4);
            TS(1,1) = R.scale(1);
            TS(2,2) = R.scale(2);
            TS(3,3) = R.scale(3);

            R.TF = R.T0 * TS * R.Trot;

            m = affine3d(R.TF);
            ref = imref3d(size(R.ms1.D));

            R.ms2.setData(imwarp(R.DataNoScale, m, 'OutputView', ref));

            safeResetMove(R.r1);
            safeResetMove(R.r2);
            safeResetMove(R.r3);
        end

        function refresh(R)

            R.clampIndices();

            x0 = R.ms1.x0;
            y0 = R.ms1.y0;
            z0 = R.ms1.z0;

            set(R.uiSliceInfo,'String',sprintf('Coronal: %d/%d   Sagittal: %d/%d   Axial: %d/%d', ...
                x0, R.ms1.nx, y0, R.ms1.ny, z0, R.ms1.nz));

            set(R.uiEditCor,'String',num2str(x0));
            set(R.uiEditSag,'String',num2str(y0));
            set(R.uiEditAxi,'String',num2str(z0));

            [aCor, aSag, aAxi] = R.ms1.cuts();

            set(R.im1,'CData',aCor);
            set(R.im2,'CData',aSag);
            set(R.im3,'CData',permute(aAxi,[2 1 3]));

            set(R.im4Under,'CData',aCor);
            set(R.im5Under,'CData',aSag);
            set(R.im6Under,'CData',permute(aAxi,[2 1 3]));

            baseWin = [0.10 0.80];
            cen = mean(baseWin);
            half = (baseWin(2) - baseWin(1)) / 2;
            half = half / R.overlayIntensity;
            win = [cen-half, cen+half];
            win(1) = max(0, win(1));
            win(2) = min(1, win(2));
            if win(2) <= win(1)
                win = baseWin;
            end

            ms2 = R.ms2;

            oCor = squeeze(ms2.D(x0,:,:));
            oSag = squeeze(ms2.D(:,y0,:));
            oAxi = squeeze(ms2.D(:,:,z0))';

            set(R.H.axes4,'CLim',win);
            set(R.H.axes5,'CLim',win);
            set(R.H.axes6,'CLim',win);

            if isempty(R.r1) || ~isvalidHandleObj(R.r1)
                set(R.im4,'CData',oCor);
            else
                R.r1.setImageData(oCor);
            end

            if isempty(R.r2) || ~isvalidHandleObj(R.r2)
                set(R.im5,'CData',oSag);
            else
                R.r2.setImageData(oSag);
            end

            if isempty(R.r3) || ~isvalidHandleObj(R.r3)
                set(R.im6,'CData',oAxi);
            else
                R.r3.setImageData(oAxi);
            end

            set(R.im4,'AlphaData',R.overlayOpacity);
            set(R.im5,'AlphaData',R.overlayOpacity);
            set(R.im6,'AlphaData',R.overlayOpacity);

            set(R.line1x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line1y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            set(R.line2x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line2y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            set(R.line3x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line3y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            set(R.line4x,'XData',[1 R.ms1.nz],'YData',[y0 y0]);
            set(R.line4y,'XData',[z0 z0],'YData',[1 R.ms1.ny]);

            set(R.line5x,'XData',[1 R.ms1.nz],'YData',[x0 x0]);
            set(R.line5y,'XData',[z0 z0],'YData',[1 R.ms1.nx]);

            set(R.line6x,'XData',[1 R.ms1.nx],'YData',[y0 y0]);
            set(R.line6y,'XData',[x0 x0],'YData',[1 R.ms1.ny]);

            safeDeleteGraphics(R.hlinesC);
            R.hlinesC = addLines(R.H.axes4, R.linmap.Cor, clampToNumel(R.linmap.Cor, x0));

            safeDeleteGraphics(R.hlinesT);
            R.hlinesT = addLines(R.H.axes5, R.linmap.Tra, clampToNumel(R.linmap.Tra, y0));

            safeDeleteGraphics(R.hlinesS);
            R.hlinesS = addLines(R.H.axes6, R.linmap.Sag, clampToNumel(R.linmap.Sag, z0));

            drawnow;
        end

        function onOverlayChanged(R)
            if ~isempty(R.uiOpacity) && isgraphics(R.uiOpacity)
                R.overlayOpacity = get(R.uiOpacity,'Value');
            end
            if ~isempty(R.uiIntensity) && isgraphics(R.uiIntensity)
                R.overlayIntensity = get(R.uiIntensity,'Value');
            end

            R.applyOverlayColormap();
            R.refresh();

            set(R.uiOverlayStatus,'String',sprintf('Opacity %.2f | Intensity %.2f | %s', ...
                R.overlayOpacity, R.overlayIntensity, R.overlayCmapName));
        end

        function applyOverlayColormap(R)
            try
                cmapList = get(R.uiCmapPopup,'String');
                idx = get(R.uiCmapPopup,'Value');
                if iscell(cmapList)
                    R.overlayCmapName = cmapList{idx};
                else
                    R.overlayCmapName = deblank(cmapList(idx,:));
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

        function onPlaneEdited(R)
            cor = round(str2double(get(R.uiEditCor,'String')));
            sag = round(str2double(get(R.uiEditSag,'String')));
            axi = round(str2double(get(R.uiEditAxi,'String')));

            if isnan(cor), cor = R.ms1.x0; end
            if isnan(sag), sag = R.ms1.y0; end
            if isnan(axi), axi = R.ms1.z0; end

            R.ms1.x0 = cor;
            R.ms1.y0 = sag;
            R.ms1.z0 = axi;

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;

            R.refresh();
        end

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

            R.ms1.x0 = R.ms2.x0;
            R.ms1.y0 = R.ms2.y0;
            R.ms1.z0 = R.ms2.z0;

            R.refresh();
        end

        function onApply(R)
            sx = str2double(get(R.uiScaleCorX,'String'));
            sy = str2double(get(R.uiScaleSagY,'String'));
            sz = str2double(get(R.uiScaleAxiZ,'String'));

            if isnan(sx) || sx <= 0, sx = 1; end
            if isnan(sy) || sy <= 0, sy = 1; end
            if isnan(sz) || sz <= 0, sz = 1; end

            R.scale = [sx sy sz];

            set(R.H.figure1,'Pointer','watch');
            drawnow;
            R.apply();
            R.refresh();
            set(R.H.figure1,'Pointer','arrow');

            set(R.uiSaveStatus,'String','Applied.');
            R.log('[Atlas GUI] Apply executed.');
        end

        function onSave(R)
            Transf = R.getCurrentTransform();
            outFile = fullfile(R.saveDir,'Transformation.mat');
            try
                save(outFile,'Transf');
                set(R.uiSaveStatus,'String',['Saved: ' outFile]);
                R.log(sprintf('[Atlas GUI] Saved Transformation.mat -> %s', outFile));
            catch ME
                set(R.uiSaveStatus,'String',['Save failed: ' ME.message]);
                R.log(['[Atlas GUI] Save failed: ' ME.message]);
            end
        end

        function onPreviewFunctional(R)
            if isempty(R.funcFiles)
                set(R.uiFuncStatus,'String','No functional candidates.');
                return;
            end

            idx = get(R.uiFuncPopup,'Value');
            idx = max(1, min(numel(R.funcFiles), idx));
            f = R.funcFiles{idx};

            try
                [scan, desc0] = loadFunctionalCandidateFile(f);
                [scanPrev, desc1] = makePreviewScan(scan);

                TransfNow = R.getCurrentTransform();
                regVol = register_data(R.atlas, scanPrev, TransfNow);

                R.showPreviewFigure(regVol, f, [desc0 ' | ' desc1]);
                set(R.uiFuncStatus,'String','Preview opened.');
            catch ME
                set(R.uiFuncStatus,'String',['Preview failed: ' ME.message]);
            end
        end

        function onRegisterFunctional(R)
            if isempty(R.funcFiles)
                set(R.uiFuncStatus,'String','No functional candidates.');
                return;
            end

            idx = get(R.uiFuncPopup,'Value');
            idx = max(1, min(numel(R.funcFiles), idx));
            f = R.funcFiles{idx};

            try
                set(R.H.figure1,'Pointer','watch');
                drawnow;

                [scan, desc0] = loadFunctionalCandidateFile(f);
                TransfNow = R.getCurrentTransform();

                [registered, desc1] = registerFullOrStaticScan(R.atlas, scan, TransfNow);

                [~,nm,~] = fileparts(stripNiiGzExt(f));
                ts = datestr(now,'yyyymmdd_HHMMSS');
                outFile = fullfile(R.saveDir, sprintf('%s_registered_to_atlas_%s.mat', safeFileStem(nm), ts));

                meta = struct();
                meta.source_file = f;
                meta.source_description = desc0;
                meta.registration_description = desc1;
                meta.transformation_file = fullfile(R.saveDir,'Transformation.mat');
                meta.timestamp = ts;

                save(outFile,'registered','meta','TransfNow','-v7.3');

                set(R.uiFuncStatus,'String',['Registered saved: ' outFile]);
                R.log(sprintf('[Atlas GUI] Registered scan saved -> %s', outFile));

                set(R.H.figure1,'Pointer','arrow');
            catch ME
                set(R.H.figure1,'Pointer','arrow');
                set(R.uiFuncStatus,'String',['Register failed: ' ME.message]);
                R.log(['[Atlas GUI] Register failed: ' ME.message]);
            end
        end

        function showPreviewFigure(R, regVol, srcFile, descText)

            x0 = R.ms1.x0;
            y0 = R.ms1.y0;
            z0 = R.ms1.z0;

            [aCor, aSag, aAxi] = R.ms1.cuts();

            oCor = squeeze(regVol(x0,:,:));
            oSag = squeeze(regVol(:,y0,:));
            oAxi = squeeze(regVol(:,:,z0))';

            win = estimateDisplayRange(regVol);
            cmap = getOverlayCmap(R.overlayCmapName);

            hf = figure( ...
                'Name','Preview registered functional', ...
                'Color',[0 0 0], ...
                'MenuBar','none', ...
                'ToolBar','none', ...
                'NumberTitle','off', ...
                'Position',[100 100 1350 500]);

            ax1 = axes('Parent',hf,'Units','normalized','Position',[0.03 0.12 0.29 0.76], 'Color','k');
            ax2 = axes('Parent',hf,'Units','normalized','Position',[0.355 0.12 0.29 0.76], 'Color','k');
            ax3 = axes('Parent',hf,'Units','normalized','Position',[0.68 0.12 0.29 0.76], 'Color','k');

            drawOverlayPreview(ax1, aCor, oCor, win, cmap, R.overlayOpacity, sprintf('Coronal x = %d', x0));
            drawOverlayPreview(ax2, aSag, oSag, win, cmap, R.overlayOpacity, sprintf('Sagittal y = %d', y0));
            drawOverlayPreview(ax3, permute(aAxi,[2 1 3]), oAxi, win, cmap, R.overlayOpacity, sprintf('Axial z = %d', z0));

            uicontrol('Style','text','Parent',hf,'Units','normalized', ...
                'Position',[0.02 0.93 0.96 0.05], ...
                'BackgroundColor',[0 0 0], ...
                'ForegroundColor',[1 1 1], ...
                'HorizontalAlignment','left', ...
                'FontSize',11, ...
                'String',sprintf('Source: %s | %s', srcFile, descText));
        end

        function onHelp(R)
            bg = [0.06 0.06 0.06];
            fg = [0.95 0.95 0.95];

            hf = figure('Name','Atlas GUI - Help', ...
                'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
                'Position',[200 120 900 650]);

            txt = {
                'Atlas GUI - Manual registration help'
                ' '
                'Recommended workflow:'
                '1) Adjust anatomy overlay on the right.'
                '2) Scroll slices to verify alignment.'
                '3) Press Apply to commit the current manual adjustment.'
                '4) Press Save to write Transformation.mat.'
                '5) Use the functional dropdown to preview or register a selected scan.'
                ' '
                'Functional buttons:'
                '  - Preview selected   : preview a registered mean/static volume'
                '  - Register selected  : save the selected scan registered to atlas space'
                ' '
                'Atlas underlay stays fixed.'
                'Anatomy overlay is the movable image.'
                };

            uicontrol(hf,'Style','edit','Max',2,'Min',0, ...
                'Units','normalized','Position',[0.03 0.03 0.94 0.94], ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontName','Consolas','FontSize',12, ...
                'HorizontalAlignment','left', ...
                'String',strjoin(txt, sprintf('\n')));
        end

        function onClose(R)
            try
                delete(R.H.figure1);
            catch
            end
        end

        function onScroll(R, evt)
            if R.anyDragging()
                return;
            end

            t = now * 24 * 3600;
            if (t - R.lastScrollT) < R.scrollMinDt
                return;
            end
            R.lastScrollT = t;

            ax = R.getAxesUnderPointer();
            if isempty(ax) || ~isgraphics(ax)
                return;
            end

            step = -sign(evt.VerticalScrollCount);
            if step == 0
                return;
            end

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

            R.refresh();
        end

        function ax = getAxesUnderPointer(R)
            fig = R.H.figure1;
            cp = get(fig,'CurrentPoint');
            axList = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];

            ax = [];
            for k = 1:numel(axList)
                a = axList(k);
                if ~isgraphics(a)
                    continue;
                end
                p = getpixelposition(a, true);
                if cp(1) >= p(1) && cp(1) <= p(1)+p(3) && cp(2) >= p(2) && cp(2) <= p(2)+p(4)
                    ax = a;
                    return;
                end
            end
        end

        function clampIndices(R)
            nx = min(R.ms1.nx, size(R.ms2.D,1));
            ny = min(R.ms1.ny, size(R.ms2.D,2));
            nz = min(R.ms1.nz, size(R.ms2.D,3));

            R.ms1.nx = nx;
            R.ms1.ny = ny;
            R.ms1.nz = nz;

            R.ms2.nx = nx;
            R.ms2.ny = ny;
            R.ms2.nz = nz;

            R.ms1.x0 = max(1, min(nx, R.ms1.x0));
            R.ms1.y0 = max(1, min(ny, R.ms1.y0));
            R.ms1.z0 = max(1, min(nz, R.ms1.z0));

            R.ms2.x0 = R.ms1.x0;
            R.ms2.y0 = R.ms1.y0;
            R.ms2.z0 = R.ms1.z0;
        end

        function log(R, msg)
            if isempty(msg)
                return;
            end
            try
                if ~isempty(R.logFcn) && isa(R.logFcn,'function_handle')
                    R.logFcn(msg);
                end
            catch
            end
        end
    end
end

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

    comp = -2 / log2(m);
    DataNorm = DataNorm .^ comp;
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
    tmpx(3,1:2) = fliplr(tmpx(3,1:2));
    tmp = [tmpx(1,:); zeros(1,3); tmpx(2:end,:)];
    tmp = [tmp(:,1), zeros(4,1), tmp(:,2:end)];
    tmp(2,2) = 1;
    tot = tot * tmp;

    tmpx = R.r2.T0;
    tmpx(1:2,1:2) = tmpx(1:2,1:2)';
    tmpx(3,1:2) = fliplr(tmpx(3,1:2));
    tmp = [zeros(1,3); tmpx(1:end,:)];
    tmp = [zeros(4,1), tmp(:,1:end)];
    tmp(1,1) = 1;
    tot = tot * tmp;

    tmpx = R.r3.T0;
    tmpx(1:2,1:2) = tmpx(1:2,1:2)';
    tmpx(3,1:2) = fliplr(tmpx(3,1:2));
    tmp = [tmpx(1:2,:); zeros(1,3); tmpx(3:end,:)];
    tmp = [tmp(:,1:2), zeros(4,1), tmp(:,3:end)];
    tmp(3,3) = 1;
    tot = tot * tmp;
end

function idx = clampToNumel(LL, idx)
    n = numel(LL);
    if n < 1
        idx = 1;
        return;
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
    for ib = 1:nb
        x = L{ib};
        h(ib) = plot(ax, x(:,2), x(:,1), 'w:', 'LineWidth', 1, 'HitTest','off');
    end
    hold(ax,'off');
end

function safeDeleteGraphics(h)
    try
        if isempty(h)
            return;
        end
        for k = 1:numel(h)
            if isgraphics(h(k))
                delete(h(k));
            end
        end
    catch
    end
end

function tf = safeIsDragging(r)
    tf = false;
    try
        if ~isempty(r) && ismethod(r,'isDragging')
            tf = r.isDragging();
        end
    catch
        tf = false;
    end
end

function tf = isvalidHandleObj(obj)
    tf = false;
    try
        tf = ~isempty(obj) && isvalid(obj);
    catch
        tf = false;
    end
end

function safeResetMove(r)
    try
        if ~isempty(r) && ismethod(r,'resetTransform')
            r.resetTransform();
        end
    catch
    end
end

function [scan, descText] = loadFunctionalCandidateFile(f)

if endsWithLowerLocal(f,'.mat')
    S = load(f);
    [scan, descText] = detectBestFunctionalFromMat(S);
elseif endsWithLowerLocal(f,'.nii') || endsWithLowerLocal(f,'.nii.gz')
    [D, vox] = loadNiftiMaybeGzLocal(f);
    scan = struct();
    scan.Data = double(D);
    if isempty(vox)
        vox = [1 1 1];
    end
    scan.VoxelSize = vox;
    descText = sprintf('NIfTI [%s]', joinDimsLocal(size(scan.Data)));
else
    error('Unsupported functional candidate: %s', f);
end

if ~isfield(scan,'Data') || isempty(scan.Data)
    error('Loaded functional candidate has empty Data.');
end
if ~isfield(scan,'VoxelSize') || isempty(scan.VoxelSize)
    scan.VoxelSize = [1 1 1];
end

end

function [scanBest, descText] = detectBestFunctionalFromMat(S)

fields = fieldnames(S);

voxHint = [];
try
    if isfield(S,'VoxelSize')
        voxHint = S.VoxelSize;
    end
    if isempty(voxHint) && isfield(S,'meta') && isstruct(S.meta) && isfield(S.meta,'VoxelSize')
        voxHint = S.meta.VoxelSize;
    end
catch
end
if isempty(voxHint)
    voxHint = [1 1 1];
end

bestScore = -inf;
scanBest = [];
descText = '';

for i = 1:numel(fields)
    v = S.(fields{i});

    if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
        D = double(v.Data);
        if ndims(D) >= 2 && ndims(D) <= 4
            tmp = struct();
            tmp.Data = D;
            if isfield(v,'VoxelSize') && ~isempty(v.VoxelSize)
                tmp.VoxelSize = v.VoxelSize;
            else
                tmp.VoxelSize = voxHint;
            end
            sc = 1000 * ndims(D) + log(double(numel(D)) + 1);
            if sc > bestScore
                bestScore = sc;
                scanBest = tmp;
                descText = sprintf('MAT struct %s [%s]', fields{i}, joinDimsLocal(size(D)));
            end
        end
    elseif (isnumeric(v) || islogical(v)) && ~isempty(v)
        D = double(v);
        if ndims(D) >= 2 && ndims(D) <= 4
            tmp = struct();
            tmp.Data = D;
            tmp.VoxelSize = voxHint;
            sc = 1000 * ndims(D) + log(double(numel(D)) + 1);
            if sc > bestScore
                bestScore = sc;
                scanBest = tmp;
                descText = sprintf('MAT numeric %s [%s]', fields{i}, joinDimsLocal(size(D)));
            end
        end
    end
end

if isempty(scanBest)
    error('No suitable functional candidate found inside MAT file.');
end

end

function [scanPrev, descText] = makePreviewScan(scanIn)

scanPrev = scanIn;
D = double(scanIn.Data);

if ndims(D) == 4
    scanPrev.Data = mean(D,4);
    descText = sprintf('Preview = mean over time of 4D [%s]', joinDimsLocal(size(D)));
elseif ndims(D) == 3
    if size(D,3) == 1
        scanPrev.Data = D;
        descText = sprintf('Preview = single-plane 3D [%s]', joinDimsLocal(size(D)));
    elseif size(D,3) > 16
        scanPrev.Data = reshape(mean(D,3), [size(D,1) size(D,2) 1]);
        descText = sprintf('Preview = mean over dim3 of 3D [%s]', joinDimsLocal(size(D)));
    else
        scanPrev.Data = D;
        descText = sprintf('Preview = static 3D volume [%s]', joinDimsLocal(size(D)));
    end
elseif ndims(D) == 2
    scanPrev.Data = reshape(D, [size(D,1) size(D,2) 1]);
    descText = sprintf('Preview = single 2D image [%s]', joinDimsLocal(size(D)));
else
    error('Unsupported preview dimensionality.');
end

if ~isfield(scanPrev,'VoxelSize') || isempty(scanPrev.VoxelSize)
    scanPrev.VoxelSize = [1 1 1];
end

end

function [registered, descText] = registerFullOrStaticScan(atlas, scanIn, TransfNow)

registered = struct();
registered.VoxelSize = atlas.VoxelSize;

D = double(scanIn.Data);

if ndims(D) == 4
    T = size(D,4);
    tmpFirst = struct();
    tmpFirst.Data = squeeze(D(:,:,:,1));
    tmpFirst.VoxelSize = scanIn.VoxelSize;
    reg1 = register_data(atlas, tmpFirst, TransfNow);

    regAll = zeros([size(reg1) T], 'single');
    regAll(:,:,:,1) = single(reg1);

    for t = 2:T
        tmp = struct();
        tmp.Data = squeeze(D(:,:,:,t));
        tmp.VoxelSize = scanIn.VoxelSize;
        regAll(:,:,:,t) = single(register_data(atlas, tmp, TransfNow));
    end

    registered.Data = regAll;
    descText = sprintf('Full 4D scan registered [%s]', joinDimsLocal(size(D)));

elseif ndims(D) == 3
    if size(D,3) > 16
        T = size(D,3);
        tmpFirst = struct();
        tmpFirst.Data = reshape(D(:,:,1), [size(D,1) size(D,2) 1]);
        tmpFirst.VoxelSize = scanIn.VoxelSize;
        reg1 = register_data(atlas, tmpFirst, TransfNow);

        regAll = zeros([size(reg1) T], 'single');
        regAll(:,:,:,1) = single(reg1);

        for t = 2:T
            tmp = struct();
            tmp.Data = reshape(D(:,:,t), [size(D,1) size(D,2) 1]);
            tmp.VoxelSize = scanIn.VoxelSize;
            regAll(:,:,:,t) = single(register_data(atlas, tmp, TransfNow));
        end

        registered.Data = regAll;
        descText = sprintf('3D data treated as YXT and registered framewise [%s]', joinDimsLocal(size(D)));
    else
        tmp = struct();
        tmp.Data = D;
        tmp.VoxelSize = scanIn.VoxelSize;
        registered.Data = single(register_data(atlas, tmp, TransfNow));
        descText = sprintf('Static 3D volume registered [%s]', joinDimsLocal(size(D)));
    end

elseif ndims(D) == 2
    tmp = struct();
    tmp.Data = reshape(D, [size(D,1) size(D,2) 1]);
    tmp.VoxelSize = scanIn.VoxelSize;
    registered.Data = single(register_data(atlas, tmp, TransfNow));
    descText = sprintf('2D image registered as single plane [%s]', joinDimsLocal(size(D)));
else
    error('Unsupported scan dimensionality for registration.');
end

end

function drawOverlayPreview(ax, underRGB, overData, win, cmap, alphaVal, ttl)
axes(ax); %#ok<LAXES>
cla(ax);
image(underRGB, 'Parent', ax);
axis(ax,'image');
axis(ax,'off');
hold(ax,'on');
h = imagesc(overData, 'Parent', ax);
set(h,'AlphaData',alphaVal);
set(ax,'CLim',win);
colormap(ax, cmap);
title(ax, ttl, 'Color','w', 'FontWeight','bold');
hold(ax,'off');
end

function cmap = getOverlayCmap(nameIn)
try
    cmap = feval(nameIn, 256);
catch
    cmap = hot(256);
end
end

function win = estimateDisplayRange(V)
v = double(V(:));
v = v(isfinite(v));
if isempty(v)
    win = [0 1];
    return;
end

lo = prctile(v, 2);
hi = prctile(v, 98);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(v);
    hi = max(v);
end
if hi <= lo
    hi = lo + 1;
end
win = [lo hi];
end

function tf = endsWithLowerLocal(str, suffix)
str = lower(str);
suffix = lower(suffix);
if numel(str) < numel(suffix)
    tf = false;
    return;
end
tf = strcmp(str(end-numel(suffix)+1:end), suffix);
end

function [D, vox] = loadNiftiMaybeGzLocal(f)

vox = [];
isGz = (numel(f) >= 7 && strcmpi(f(end-6:end),'.nii.gz'));

if isGz
    tmpDir = tempname;
    mkdir(tmpDir);
    gunzip(f, tmpDir);
    d = dir(fullfile(tmpDir,'*.nii'));
    if isempty(d)
        error('Failed to gunzip: %s', f);
    end
    niiFile = fullfile(tmpDir, d(1).name);

    info = niftiinfo(niiFile);
    D = niftiread(info);

    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions) >= 3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end

    try
        rmdir(tmpDir,'s');
    catch
    end
else
    info = niftiinfo(f);
    D = niftiread(info);
    try
        if isfield(info,'PixelDimensions') && numel(info.PixelDimensions) >= 3
            vox = double(info.PixelDimensions(1:3));
        end
    catch
    end
end
end

function s = joinDimsLocal(sz)
if isempty(sz)
    s = '';
    return;
end
s = num2str(sz(1));
for k = 2:numel(sz)
    s = [s 'x' num2str(sz(k))]; %#ok<AGROW>
end
end

function stem = safeFileStem(s)
if isempty(s)
    stem = 'scan';
    return;
end
stem = regexprep(s,'[^A-Za-z0-9_]+','_');
stem = regexprep(stem,'_+','_');
stem = regexprep(stem,'^_','');
stem = regexprep(stem,'_$','');
if isempty(stem)
    stem = 'scan';
end
if numel(stem) > 60
    stem = stem(1:60);
end
end

function out = stripNiiGzExt(f)
out = f;
if numel(out) >= 7 && strcmpi(out(end-6:end), '.nii.gz')
    out = out(1:end-7);
    return;
end
[p,n,~] = fileparts(out);
out = fullfile(p,n);
end