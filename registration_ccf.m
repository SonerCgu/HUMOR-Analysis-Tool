classdef registration_ccf < handle
% =========================================================
% Atlas registration GUI
%
% ASCII only
% MATLAB 2017b compatible
%
% Main goals:
%   - Use your nice mask-editor brainImage / MIP / anatomy as overlay
%   - Better contrast controls for overlay
%   - Keep atlas fixed, move overlay
%   - Save Transformation.mat
%   - Preview/register functional files to atlas space
%
% Constructor supports:
%   R = registration_ccf(atlas, scananatomy)
%   R = registration_ccf(atlas, scananatomy, initialTransf)
%   R = registration_ccf(atlas, scananatomy, initialTransf, logFcn)
%   R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir)
%   R = registration_ccf(atlas, scananatomy, initialTransf, logFcn, saveDir, funcCandidates)
% =========================================================

    properties
        H
        atlas

        ms1
        ms2
        DataNoScale

        scale
        Trot
        TF
        T0

        r1
        r2
        r3

        mapRegions
        mapHistology
        mapVascular
        linmap

        hlinesS
        hlinesC
        hlinesT

        logFcn = []
        saveDir = ''

        funcFiles = {}
        funcLabels = {}

        overlayOpacity = 0.65
        overlayCmapName = 'gray'
        overlayInvert = false
        overlayWinMin = 0.05
        overlayWinMax = 0.95
        showAtlasLines = true

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
        uiWinMin
        uiWinMax
        uiInvert
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
        uiShowLines

        uiHelp
        uiClose

        uiFuncPopup
        uiFuncPreview
        uiFuncRegister
        uiFuncStatus
    end

    methods
        function R = registration_ccf(atlas, scananatomy, varargin)

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

            % Normalize anatomy overlay and bring it into atlas voxel/orientation space
            scananatomy.Data = equalizeImages(double(scananatomy.Data));
            tmp = interpolate3D(atlas, scananatomy);

            R.ms2 = mapscan(double(tmp.Data), gray(256), 'fix');
            R.ms2.caxis = [0 1];

            R.mapHistology = mapscan(atlas.Histology, gray(256), 'index');
            R.mapVascular  = mapscan(atlas.Vascular,  gray(256), 'auto');
            R.mapRegions   = mapscan(atlas.Regions,   atlas.infoRegions.rgb, 'index');

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
            W = min(1460, scr(3)-80);
            Hh = min(940, scr(4)-80);
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
            midX  = 0.35;
            ctrlX = 0.68;
            axW   = 0.28;
            axH   = 0.24;
            gapY  = 0.04;

            yTop = 0.70;
            yMid = yTop - axH - gapY;
            yBot = yMid - axH - gapY;

            uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.03 0.94 0.63 0.045], ...
                'String','Atlas GUI - Register anatomy first, then preview functional in atlas space', ...
                'BackgroundColor',bg, ...
                'ForegroundColor',fg, ...
                'FontSize',16, ...
                'FontWeight','bold', ...
                'HorizontalAlignment','left');

            R.uiSliceInfo = uicontrol(f,'Style','text', ...
                'Units','normalized', ...
                'Position',[0.68 0.94 0.29 0.045], ...
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

            axAll = [R.H.axes1 R.H.axes2 R.H.axes3 R.H.axes4 R.H.axes5 R.H.axes6];
            for k = 1:numel(axAll)
                axis(axAll(k),'image');
                axis(axAll(k),'off');
                set(axAll(k),'Box','off');
            end

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[leftX yTop+axH+0.005 axW 0.02], ...
                'String','Atlas - Coronal', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[leftX yMid+axH+0.005 axW 0.02], ...
                'String','Atlas - Sagittal', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[leftX yBot+axH+0.005 axW 0.02], ...
                'String','Atlas - Axial', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yTop+axH+0.005 axW 0.02], ...
                'String','Overlay on Atlas - Coronal', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yMid+axH+0.005 axW 0.02], ...
                'String','Overlay on Atlas - Sagittal', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            uicontrol(f,'Style','text','Units','normalized', ...
                'Position',[midX yBot+axH+0.005 axW 0.02], ...
                'String','Overlay on Atlas - Axial', ...
                'BackgroundColor',bg,'ForegroundColor',fg, ...
                'FontSize',11,'FontWeight','bold','HorizontalAlignment','center');

            ctrlPanel = uipanel(f, ...
                'Units','normalized', ...
                'Position',[ctrlX 0.06 0.29 0.87], ...
                'BackgroundColor',panelBG, ...
                'ForegroundColor',fg, ...
                'Title','Controls', ...
                'FontSize',12, ...
                'FontWeight','bold');

            % Overlay display panel
            ovPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.05 0.69 0.90 0.28], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Overlay display', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.79 0.26 0.12], ...
                'String','Opacity', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiOpacity = uicontrol(ovPanel,'Style','slider','Units','normalized', ...
                'Position',[0.36 0.82 0.58 0.10], ...
                'Min',0,'Max',1,'Value',R.overlayOpacity, ...
                'BackgroundColor',panelBG2, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.57 0.26 0.12], ...
                'String','Window min', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiWinMin = uicontrol(ovPanel,'Style','edit','Units','normalized', ...
                'Position',[0.36 0.58 0.20 0.12], ...
                'String',num2str(R.overlayWinMin), ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.60 0.57 0.20 0.12], ...
                'String','Window max', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiWinMax = uicontrol(ovPanel,'Style','edit','Units','normalized', ...
                'Position',[0.80 0.58 0.14 0.12], ...
                'String',num2str(R.overlayWinMax), ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.34 0.26 0.12], ...
                'String','Colormap', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            cmapList = {'gray','bone','hot','copper','parula','jet'};
            R.uiCmapPopup = uicontrol(ovPanel,'Style','popupmenu','Units','normalized', ...
                'Position',[0.36 0.35 0.32 0.14], ...
                'String',cmapList, ...
                'Value',1, ...
                'BackgroundColor',[0.15 0.15 0.15], ...
                'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            R.uiInvert = uicontrol(ovPanel,'Style','checkbox','Units','normalized', ...
                'Position',[0.72 0.34 0.22 0.14], ...
                'String','Invert', ...
                'Value',0, ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onOverlayChanged());

            R.uiOverlayStatus = uicontrol(ovPanel,'Style','text','Units','normalized', ...
                'Position',[0.06 0.08 0.88 0.14], ...
                'String','', ...
                'BackgroundColor',panelBG2,'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left','FontSize',9);

            % Transform panel
            trPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.05 0.47 0.90 0.18], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Transform', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.05 0.66 0.36 0.16], ...
                'String','Scale X', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleCorX = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.30 0.66 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.05 0.40 0.36 0.16], ...
                'String','Scale Y', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleSagY = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.30 0.40 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.05 0.14 0.36 0.16], ...
                'String','Scale Z', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiScaleAxiZ = uicontrol(trPanel,'Style','edit','Units','normalized', ...
                'Position',[0.30 0.14 0.16 0.18], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12], ...
                'ForegroundColor',fg);

            R.uiApply = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.56 0.54 0.37 0.26], ...
                'String','1. Apply', ...
                'BackgroundColor',[0.20 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onApply());

            R.uiSave = uicontrol(trPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.56 0.18 0.37 0.26], ...
                'String','2. Save', ...
                'BackgroundColor',[0.15 0.70 0.55], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onSave());

            R.uiSaveStatus = uicontrol(trPanel,'Style','text','Units','normalized', ...
                'Position',[0.05 0.01 0.88 0.10], ...
                'String','', ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left', ...
                'FontSize',9);

            % Functional panel
            funcPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.05 0.28 0.90 0.15], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Functional preview/register', ...
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

            R.uiFuncPopup = uicontrol(funcPanel,'Style','popupmenu','Units','normalized', ...
                'Position',[0.05 0.56 0.90 0.22], ...
                'String',popupStrings, ...
                'Value',1, ...
                'Enable',popupEnable, ...
                'BackgroundColor',[0.15 0.15 0.15], ...
                'ForegroundColor',fg);

            R.uiFuncPreview = uicontrol(funcPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.05 0.24 0.42 0.20], ...
                'String','Preview selected', ...
                'Enable',btnEnable, ...
                'BackgroundColor',[0.32 0.48 0.86], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onPreviewFunctional());

            R.uiFuncRegister = uicontrol(funcPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.53 0.24 0.42 0.20], ...
                'String','Register selected', ...
                'Enable',btnEnable, ...
                'BackgroundColor',[0.64 0.42 0.20], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onRegisterFunctional());

            R.uiFuncStatus = uicontrol(funcPanel,'Style','text','Units','normalized', ...
                'Position',[0.05 0.03 0.90 0.12], ...
                'String','', ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',[0.7 0.95 0.7], ...
                'HorizontalAlignment','left', ...
                'FontSize',9);

            % Plane and atlas panel
            miscPanel = uipanel(ctrlPanel, ...
                'Units','normalized', ...
                'Position',[0.05 0.10 0.90 0.14], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'Title','Planes and atlas', ...
                'FontSize',11, ...
                'FontWeight','bold');

            uicontrol(miscPanel,'Style','text','Units','normalized', ...
                'Position',[0.03 0.58 0.16 0.18], ...
                'String','Cor', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiEditCor = uicontrol(miscPanel,'Style','edit','Units','normalized', ...
                'Position',[0.14 0.58 0.12 0.20], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(miscPanel,'Style','text','Units','normalized', ...
                'Position',[0.30 0.58 0.16 0.18], ...
                'String','Sag', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiEditSag = uicontrol(miscPanel,'Style','edit','Units','normalized', ...
                'Position',[0.40 0.58 0.12 0.20], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            uicontrol(miscPanel,'Style','text','Units','normalized', ...
                'Position',[0.56 0.58 0.16 0.18], ...
                'String','Axi', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'HorizontalAlignment','left','FontSize',10,'FontWeight','bold');

            R.uiEditAxi = uicontrol(miscPanel,'Style','edit','Units','normalized', ...
                'Position',[0.66 0.58 0.12 0.20], ...
                'String','1', ...
                'BackgroundColor',[0.12 0.12 0.12],'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onPlaneEdited());

            R.uiShowLines = uicontrol(miscPanel,'Style','checkbox','Units','normalized', ...
                'Position',[0.03 0.28 0.30 0.18], ...
                'String','Atlas lines', ...
                'Value',1, ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg, ...
                'Callback',@(src,evt)R.onShowLines());

            atlasModeStrings = {'vascular','histology','regions'};
            R.uiAtlasGroup = uibuttongroup(miscPanel, ...
                'Units','normalized', ...
                'Position',[0.38 0.10 0.57 0.35], ...
                'BackgroundColor',panelBG2, ...
                'ForegroundColor',fg, ...
                'SelectionChangedFcn',@(src,evt)R.onAtlasMode(evt.NewValue.Tag));

            R.uiAtlasVasc = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized', ...
                'Position',[0.02 0.10 0.30 0.80], ...
                'String',atlasModeStrings{1}, ...
                'Tag','vascular', ...
                'Value',1, ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg);

            R.uiAtlasHist = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized', ...
                'Position',[0.34 0.10 0.30 0.80], ...
                'String',atlasModeStrings{2}, ...
                'Tag','histology', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg);

            R.uiAtlasReg = uicontrol(R.uiAtlasGroup,'Style','radiobutton', ...
                'Units','normalized', ...
                'Position',[0.66 0.10 0.30 0.80], ...
                'String',atlasModeStrings{3}, ...
                'Tag','regions', ...
                'BackgroundColor',panelBG2,'ForegroundColor',fg);

            R.uiHelp = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.05 0.02 0.42 0.05], ...
                'String','HELP', ...
                'BackgroundColor',[0.25 0.45 0.95], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onHelp());

            R.uiClose = uicontrol(ctrlPanel,'Style','pushbutton','Units','normalized', ...
                'Position',[0.53 0.02 0.42 0.05], ...
                'String','CLOSE', ...
                'BackgroundColor',[0.85 0.25 0.25], ...
                'ForegroundColor','w', ...
                'FontWeight','bold', ...
                'Callback',@(src,evt)R.onClose());

            % Create images
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

            % Crosshairs
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

            oCor = squeeze(R.ms2.D(x0,:,:));
            oSag = squeeze(R.ms2.D(:,y0,:));
            oAxi = squeeze(R.ms2.D(:,:,z0))';

            if R.overlayInvert
                oCor = 1 - oCor;
                oSag = 1 - oSag;
                oAxi = 1 - oAxi;
            end

            wmin = R.overlayWinMin;
            wmax = R.overlayWinMax;
            if wmax <= wmin
                wmax = wmin + 0.01;
            end

            set(R.H.axes4,'CLim',[wmin wmax]);
            set(R.H.axes5,'CLim',[wmin wmax]);
            set(R.H.axes6,'CLim',[wmin wmax]);

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
            safeDeleteGraphics(R.hlinesT);
            safeDeleteGraphics(R.hlinesS);

            if R.showAtlasLines
                R.hlinesC = addLines(R.H.axes4, R.linmap.Cor, clampToNumel(R.linmap.Cor, x0));
                R.hlinesT = addLines(R.H.axes5, R.linmap.Tra, clampToNumel(R.linmap.Tra, y0));
                R.hlinesS = addLines(R.H.axes6, R.linmap.Sag, clampToNumel(R.linmap.Sag, z0));
            end

            drawnow;
        end

        function onOverlayChanged(R)

            if ~isempty(R.uiOpacity) && isgraphics(R.uiOpacity)
                R.overlayOpacity = get(R.uiOpacity,'Value');
            end

            wmin = str2double(get(R.uiWinMin,'String'));
            wmax = str2double(get(R.uiWinMax,'String'));
            if ~isfinite(wmin)
                wmin = R.overlayWinMin;
            end
            if ~isfinite(wmax)
                wmax = R.overlayWinMax;
            end

            wmin = max(0, min(1, wmin));
            wmax = max(0, min(1, wmax));
            if wmax <= wmin
                wmax = min(1, wmin + 0.01);
            end

            R.overlayWinMin = wmin;
            R.overlayWinMax = wmax;
            set(R.uiWinMin,'String',num2str(R.overlayWinMin));
            set(R.uiWinMax,'String',num2str(R.overlayWinMax));

            R.overlayInvert = logical(get(R.uiInvert,'Value'));

            cmapList = get(R.uiCmapPopup,'String');
            idx = get(R.uiCmapPopup,'Value');
            if iscell(cmapList)
                R.overlayCmapName = cmapList{idx};
            else
                R.overlayCmapName = deblank(cmapList(idx,:));
            end

            R.applyOverlayColormap();
            R.refresh();

            set(R.uiOverlayStatus,'String',sprintf( ...
                'Opacity %.2f | Win [%.2f %.2f] | %s | Invert %d', ...
                R.overlayOpacity, R.overlayWinMin, R.overlayWinMax, R.overlayCmapName, double(R.overlayInvert)));
        end

        function applyOverlayColormap(R)
            try
                cmap = feval(R.overlayCmapName, 256);
            catch
                cmap = gray(256);
                R.overlayCmapName = 'gray';
            end

            colormap(R.H.axes4, cmap);
            colormap(R.H.axes5, cmap);
            colormap(R.H.axes6, cmap);
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

        function onShowLines(R)
            R.showAtlasLines = logical(get(R.uiShowLines,'Value'));
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
                R.log(['[Atlas GUI] Preview failed: ' ME.message]);
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

            if R.overlayInvert
                oCor = 1 - rescaleSafe(oCor);
                oSag = 1 - rescaleSafe(oSag);
                oAxi = 1 - rescaleSafe(oAxi);
            end

            win = estimateDisplayRange01(regVol);
            cmap = getOverlayCmap(R.overlayCmapName);

            hf = figure( ...
                'Name','Preview registered functional', ...
                'Color',[0 0 0], ...
                'MenuBar','none', ...
                'ToolBar','none', ...
                'NumberTitle','off', ...
                'Position',[100 100 1380 520]);

            ax1 = axes('Parent',hf,'Units','normalized','Position',[0.03 0.12 0.29 0.76], 'Color','k');
            ax2 = axes('Parent',hf,'Units','normalized','Position',[0.355 0.12 0.29 0.76], 'Color','k');
            ax3 = axes('Parent',hf,'Units','normalized','Position',[0.68 0.12 0.29 0.76], 'Color','k');

            drawOverlayPreview(ax1, aCor, rescaleSafe(oCor), [R.overlayWinMin R.overlayWinMax], cmap, R.overlayOpacity, sprintf('Coronal x = %d', x0));
            drawOverlayPreview(ax2, aSag, rescaleSafe(oSag), [R.overlayWinMin R.overlayWinMax], cmap, R.overlayOpacity, sprintf('Sagittal y = %d', y0));
            drawOverlayPreview(ax3, permute(aAxi,[2 1 3]), rescaleSafe(oAxi), [R.overlayWinMin R.overlayWinMax], cmap, R.overlayOpacity, sprintf('Axial z = %d', z0));

            uicontrol('Style','text','Parent',hf,'Units','normalized', ...
                'Position',[0.02 0.93 0.96 0.05], ...
                'BackgroundColor',[0 0 0], ...
                'ForegroundColor',[1 1 1], ...
                'HorizontalAlignment','left', ...
                'FontSize',11, ...
                'String',sprintf('Source: %s | %s | display range estimate [%.3f %.3f]', srcFile, descText, win(1), win(2)));
        end

        function onHelp(R)
            bg = [0.06 0.06 0.06];
            fg = [0.95 0.95 0.95];

            hf = figure('Name','Atlas GUI - Help', ...
                'Color',bg,'MenuBar','none','ToolBar','none','NumberTitle','off', ...
                'Position',[200 120 900 650]);

            txt = {
                'Atlas GUI - Help'
                ' '
                'Recommended workflow:'
                '1) Select your nice BrainOnly / brainImage / MIP-like anatomy in coreg.'
                '2) In this GUI, mainly align coronal first.'
                '3) Then verify and refine with sagittal and axial.'
                '4) Use Apply, then Save.'
                '5) Use Preview selected or Register selected for functional outputs.'
                ' '
                'Mouse interaction on right panels:'
                '  - Left drag  = translate overlay'
                '  - Right drag = rotate overlay'
                ' '
                'Important:'
                'A reliable 3D transform should not be based on coronal only.'
                'Use coronal as primary view, but confirm sagittal and axial too.'
                ' '
                'The overlay display controls are only for contrast/visibility.'
                'They do not change the data used for the saved transformation.'
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
tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
tmp = [tmpx(1,:); zeros(1,3); tmpx(2:end,:)];
tmp = [tmp(:,1), zeros(4,1), tmp(:,2:end)];
tmp(2,2) = 1;
tot = tot * tmp;

tmpx = R.r2.T0;
tmpx(1:2,1:2) = tmpx(1:2,1:2)';
tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
tmp = [zeros(1,3); tmpx(1:end,:)];
tmp = [zeros(4,1), tmp(:,1:end)];
tmp(1,1) = 1;
tot = tot * tmp;

tmpx = R.r3.T0;
tmpx(1:2,1:2) = tmpx(1:2,1:2)';
tmpx(3,1:2)   = fliplr(tmpx(3,1:2));
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

scanBest = [];
descText = '';

preferredNumeric = { ...
    'brainImage', ...
    'I', ...
    'PSC', ...
    'Data', ...
    'anatomical_reference', ...
    'anatomical_reference_raw' ...
    };

for i = 1:numel(preferredNumeric)
    nm = preferredNumeric{i};
    if isfield(S, nm)
        v = S.(nm);
        if (isnumeric(v) || islogical(v)) && ~isempty(v)
            if ndims(v) >= 2 && ndims(v) <= 4
                scanBest = struct();
                scanBest.Data = double(v);
                scanBest.VoxelSize = voxHint;
                descText = sprintf('MAT numeric %s [%s]', nm, joinDimsLocal(size(v)));
                return;
            end
        end
    end
end

preferredStruct = { ...
    'registered', ...
    'scan', ...
    'scanfus', ...
    'anatomic', ...
    'proc', ...
    'out' ...
    };

for i = 1:numel(preferredStruct)
    nm = preferredStruct{i};
    if isfield(S, nm)
        v = S.(nm);
        if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
            scanBest = struct();
            scanBest.Data = double(v.Data);
            if isfield(v,'VoxelSize') && ~isempty(v.VoxelSize)
                scanBest.VoxelSize = v.VoxelSize;
            else
                scanBest.VoxelSize = voxHint;
            end
            descText = sprintf('MAT struct %s.Data [%s]', nm, joinDimsLocal(size(v.Data)));
            return;
        end
    end
end

for i = 1:numel(fields)
    v = S.(fields{i});
    if isstruct(v) && isfield(v,'Data') && isnumeric(v.Data) && ~isempty(v.Data)
        if ndims(v.Data) >= 2 && ndims(v.Data) <= 4
            scanBest = struct();
            scanBest.Data = double(v.Data);
            if isfield(v,'VoxelSize') && ~isempty(v.VoxelSize)
                scanBest.VoxelSize = v.VoxelSize;
            else
                scanBest.VoxelSize = voxHint;
            end
            descText = sprintf('MAT struct %s.Data [%s]', fields{i}, joinDimsLocal(size(v.Data)));
            return;
        end
    end
end

bestScore = -inf;

for i = 1:numel(fields)
    v = S.(fields{i});

    if (isnumeric(v) || islogical(v)) && ~isempty(v)
        if ndims(v) >= 2 && ndims(v) <= 4
            sc = 1000 * ndims(v) + log(double(numel(v)) + 1);
            if sc > bestScore
                bestScore = sc;
                scanBest = struct();
                scanBest.Data = double(v);
                scanBest.VoxelSize = voxHint;
                descText = sprintf('MAT numeric %s [%s]', fields{i}, joinDimsLocal(size(v)));
            end
        end
    end
end

if isempty(scanBest)
    error('No suitable functional candidate found. No numeric 2D/3D/4D variable or struct.Data field was found.');
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


function drawOverlayPreview(ax, underRGB, overData01, win, cmap, alphaVal, ttl)

axes(ax); %#ok<LAXES>
cla(ax);
image(underRGB, 'Parent', ax);
axis(ax,'image');
axis(ax,'off');
hold(ax,'on');
h = imagesc(overData01, 'Parent', ax);
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
    cmap = gray(256);
end
end


function win = estimateDisplayRange01(V)
v = double(V(:));
v = v(isfinite(v));
if isempty(v)
    win = [0 1];
    return;
end

v = rescaleSafe(v);
lo = prctile(v, 2);
hi = prctile(v, 98);

if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(v);
    hi = max(v);
end
if hi <= lo
    hi = lo + 0.01;
end

win = [lo hi];
end


function x = rescaleSafe(x)
x = double(x);
mn = min(x(:));
mx = max(x(:));
if ~isfinite(mn), mn = 0; end
if ~isfinite(mx), mx = 1; end
if mx <= mn
    x = zeros(size(x));
else
    x = (x - mn) ./ (mx - mn);
end
x = min(max(x,0),1);
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