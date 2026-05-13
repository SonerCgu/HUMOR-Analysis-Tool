% UTF-8 safe, MATLAB 2017b compatible
%
% GUI ENTRY SCRIPT
% Keep this filename unchanged because the encrypted launcher may call it.

localLaunchMainGUI();

function localLaunchMainGUI()

    fig = figure( ...
        'Name', 'OpenfUS Trigger Controller', ...
        'NumberTitle', 'off', ...
        'MenuBar', 'none', ...
        'ToolBar', 'none', ...
        'Color', [0.07 0.08 0.10], ...
        'Position', [35 15 1560 960], ...
        'Resize', 'on', ...
        'CloseRequestFcn', @(src, evt)localOnClose(src));

    C = localBuildColors();

    H = struct();
    H.fig = fig;
    H.C = C;

    % ------------------------------------------------------------------
    % Header
    % ------------------------------------------------------------------
H.hBanner = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.012 0.895 0.976 0.088], ...
    'BorderType', 'line', ...
    'HighlightColor', C.banner, ...
    'ShadowColor', C.banner, ...
    'BackgroundColor', C.banner);

  H.hTitle = uicontrol(H.hBanner, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.016 0.38 0.26 0.50], ...
    'String', 'Trigger Controller', ...
    'FontSize', 24, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.banner);

H.hSubTitle = uicontrol(H.hBanner, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.016 0.08 0.34 0.22], ...
    'String', 'Trigger-based acquisition control for StimBox, PulsePal and stepping motor', ...
    'FontSize', 10, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left', ...
    'ForegroundColor', C.textSoft, ...
    'BackgroundColor', C.banner);

H.hStatus = uicontrol(H.hBanner, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.29 0.26 0.30 0.56], ...
    'String', 'Status: Idle', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.idle);

H.hReady = uicontrol(H.hBanner, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.61 0.26 0.055 0.56], ...
    'String', 'READY', ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.ready);

% Live measured dt/TR display.
% This is based on wall-clock timing between frame callback updates.
H.pLiveDtBox = localMakeMiniInfoPanel(H.hBanner, [0.680 0.16 0.082 0.72], 'Live dt', C, C.edgePulse);
H.hLiveDt = localMakeMiniInfoText(H.pLiveDtBox, 'set --', C);
set(H.hLiveDt, 'FontSize', 16);     % bigger Live dt value

H.pFrameBox = localMakeMiniInfoPanel(H.hBanner, [0.768 0.16 0.060 0.72], 'Frame / s', C, C.edgeAcq);
H.hFrame = localMakeMiniInfoText(H.pFrameBox, '0', C);
set(H.hFrame, 'FontSize', 16);      % bigger frame/time value

set(H.pLiveDtBox, 'FontSize', 11);  % bigger title
set(H.pFrameBox, 'FontSize', 11);   % bigger title


H.pTrialBox = localMakeMiniInfoPanel(H.hBanner, [0.834 0.16 0.064 0.72], 'Trial', C, C.edgeStim);
H.hTrial = localMakeMiniInfoText(H.pTrialBox, '0/0', C);

H.pMotorBox = localMakeMiniInfoPanel(H.hBanner, [0.904 0.16 0.074 0.72], 'Motor', C, C.edgeMotor);
H.hMotor = localMakeMiniInfoText(H.pMotorBox, 'off', C);
% ------------------------------------------------------------------
% Main panels
% ------------------------------------------------------------------

% ===== Acquisition =====
pAcqWrap = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.012 0.490 0.234 0.372], ...
    'Title', '', ...
    'BackgroundColor', C.edgeAcq, ...
    'BorderType', 'line', ...
    'HighlightColor', C.edgeAcq, ...
    'ShadowColor', C.edgeAcq);

uicontrol(pAcqWrap, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.92 0.96 0.07], ...
    'String', 'Acquisition', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.edgeAcq);

pAcq = uipanel(pAcqWrap, ...
    'Units', 'normalized', ...
    'Position', [0.006 0.006 0.988 0.905], ...
    'BorderType', 'none', ...
    'BackgroundColor', C.panel);

% ===== StimBox =====
pStimBoxWrap = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.249 0.490 0.234 0.372], ...
    'Title', '', ...
    'BackgroundColor', C.edgeStim, ...
    'BorderType', 'line', ...
    'HighlightColor', C.edgeStim, ...
    'ShadowColor', C.edgeStim);

uicontrol(pStimBoxWrap, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.92 0.96 0.07], ...
    'String', 'StimBox Triggering', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.edgeStim);

pStimBox = uipanel(pStimBoxWrap, ...
    'Units', 'normalized', ...
    'Position', [0.006 0.006 0.988 0.905], ...
    'BorderType', 'none', ...
    'BackgroundColor', C.panel);

% ===== PulsePal =====
pPulsePalWrap = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.486 0.490 0.237 0.372], ...
    'Title', '', ...
    'BackgroundColor', C.edgePulse, ...
    'BorderType', 'line', ...
    'HighlightColor', C.edgePulse, ...
    'ShadowColor', C.edgePulse);

uicontrol(pPulsePalWrap, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.92 0.96 0.07], ...
    'String', 'Electrical Stimulation / PulsePal', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.edgePulse);

pPulsePal = uipanel(pPulsePalWrap, ...
    'Units', 'normalized', ...
    'Position', [0.006 0.006 0.988 0.905], ...
    'BorderType', 'none', ...
    'BackgroundColor', C.panel);

% ===== Motor =====
pMotorWrap = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.726 0.490 0.262 0.372], ...
    'Title', '', ...
    'BackgroundColor', C.edgeMotor, ...
    'BorderType', 'line', ...
    'HighlightColor', C.edgeMotor, ...
    'ShadowColor', C.edgeMotor);

uicontrol(pMotorWrap, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.92 0.96 0.07], ...
    'String', 'Step Motor', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.edgeMotor);

pMotor = uipanel(pMotorWrap, ...
    'Units', 'normalized', ...
    'Position', [0.006 0.006 0.988 0.905], ...
    'BorderType', 'none', ...
    'BackgroundColor', C.panel);

% ===== Live Log =====
pLogWrap = uipanel(fig, ...
    'Units', 'normalized', ...
    'Position', [0.012 0.075 0.976 0.350], ...
    'Title', '', ...
    'BackgroundColor', C.edgeHeader, ...
    'BorderType', 'line', ...
    'HighlightColor', C.edgeHeader, ...
    'ShadowColor', C.edgeHeader);

uicontrol(pLogWrap, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.02 0.92 0.96 0.07], ...
    'String', 'Live Log', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.edgeHeader);

pLog = uipanel(pLogWrap, ...
    'Units', 'normalized', ...
    'Position', [0.004 0.004 0.992 0.905], ...
    'BorderType', 'none', ...
    'BackgroundColor', C.panel);
    % ------------------------------------------------------------------
% Acquisition / StimBox / PulsePal / Motor panels
% unified row grid
% ------------------------------------------------------------------
panelFs = 11;
smallFs = 10;

% Shared two-column grid for all upper panels.
% This makes Acquisition / StimBox / PulsePal / Motor rows line up better.
xLlbl = 0.05;
xLedt = 0.28;
wLedt = 0.17;

xRlbl = 0.50;
xRedt = 0.74;
wRedt = 0.16;

y1 = 0.78;
y2 = 0.66;
y3 = 0.54;
y4 = 0.42;
y5 = 0.30;
y6 = 0.18;
y7 = 0.06;

% ------------------------------------------------------------------
% Acquisition panel
% ------------------------------------------------------------------

% ------------------------------------------------------------------
% Save location selector (above folder warning)
% ------------------------------------------------------------------
uicontrol(pAcq, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.922 0.22 0.050], ...
    'String', 'Save under', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', 13, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);


% For adding other folder destination names change here
H.pSaveOwner = uicontrol(pAcq, 'Style', 'popupmenu', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.920 0.55 0.050], ...
    'String', {'Soner','Yan','Guest'}, ...
    'Value', 1, ...
    'FontSize', 13, ...
    'BackgroundColor', C.editbg, ...
    'ForegroundColor', [0 0 0]);

uicontrol(pAcq, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.86 0.78 0.05], ...
    'String', 'Care: Change Folder Name!', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 0.2 0.2], ...
    'BackgroundColor', C.panel);

H.eXpName = localMakeLabeledEdit(pAcq, ...
    'Exp. Name', [xLlbl y1 0.18 0.055], [xLedt y1-0.008 0.65 0.075], ...
    'RGRO_yymmdd_1024_MM_B6J_ID', C, panelFs, C.panel);

H.eNFrames = localMakeLabeledEdit(pAcq, ...
    'Frames / trial', [xLlbl y2 0.18 0.055], [xLedt y2-0.008 wLedt 0.075], ...
    '9000', C, panelFs, C.panel);

H.eNTrials = localMakeLabeledEdit(pAcq, ...
    'Trials', [xRlbl y2 0.16 0.055], [xRedt y2-0.008 wRedt 0.075], ...
    '1', C, panelFs, C.panel);

H.eNBlocks = localMakeLabeledEdit(pAcq, ...
    'nblocksImage', [xLlbl y3 0.18 0.055], [xLedt y3-0.008 wLedt 0.075], ...
    '16', C, panelFs, C.panel);

uicontrol(pAcq, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [xRlbl y3 0.12 0.055], ...
    'String', 'TR', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.hTR = uicontrol(pAcq, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [xRedt y3-0.008 wRedt 0.075], ...
    'String', '0.320 s', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.box);

H.ePause = localMakeLabeledEdit(pAcq, ...
    'Pause (s)', [xLlbl y4 0.18 0.055], [xLedt y4-0.008 wLedt 0.075], ...
    '1', C, panelFs, C.panel);

H.hCalcTitle = uicontrol(pAcq, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y5 0.28 0.055], ...
    'String', 'Frame / Time', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titleAcq, ...
    'BackgroundColor', C.panel);

H.eCalcSec = localMakeLabeledEdit(pAcq, ...
    'Seconds', [xLlbl y6 0.15 0.055], [xLedt y6-0.008 wLedt 0.075], ...
    '10', C, panelFs, C.panel);

H.eCalcFrames = localMakeLabeledEdit(pAcq, ...
    'Frames', [xRlbl y6 0.15 0.055], [xRedt y6-0.008 wRedt 0.075], ...
    '31', C, panelFs, C.panel);

H.bSecToFrames = uicontrol(pAcq, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.05 y7 0.40 0.08], ...
    'String', 'sec -> frames', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.btn, ...
    'Callback', @(src,evt)localCalcSecToFrames(fig));

H.bFramesToSec = uicontrol(pAcq, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.50 y7 0.40 0.08], ...
    'String', 'frames -> sec', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.btn, ...
    'Callback', @(src,evt)localCalcFramesToSec(fig));

% ------------------------------------------------------------------
% StimBox panel
% ------------------------------------------------------------------
H.cStimEnable = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.89 0.34 0.06], ...
    'String', 'Enable StimBox', ...
    'Value', 0, ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titleStim, ...
    'BackgroundColor', C.panel, ...
    'Callback', @(src,evt)localRefreshStimBoxPanel(fig));

H.eStimCom = localMakeLabeledEdit(pStimBox, ...
    'COM', [xLlbl y1 0.15 0.055], [xLedt y1-0.008 wLedt 0.075], ...
    'COM9', C, panelFs, C.panel);

H.eStimBaud = localMakeLabeledEdit(pStimBox, ...
    'Baud', [xRlbl y1 0.17 0.055], [xRedt y1-0.008 wRedt 0.075], ...
    '9600', C, panelFs, C.panel);

H.eStimStart = localMakeLabeledEdit(pStimBox, ...
    'Frame start', [xLlbl y2 0.18 0.055], [xLedt y2-0.008 wLedt 0.075], ...
    '20', C, panelFs, C.panel);

H.eStimDur = localMakeLabeledEdit(pStimBox, ...
    'Frames active', [xRlbl y2 0.20 0.055], [xRedt y2-0.008 wRedt 0.075], ...
    '10', C, panelFs, C.panel);

H.cD3 = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y3 0.18 0.06], ...
    'String', 'D3 ON', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.cD5 = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xRlbl y3 0.18 0.06], ...
    'String', 'D5 ON', ...
    'Value', 1, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.cD6 = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y4 0.18 0.06], ...
    'String', 'D6 ON', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.cStimVerbose = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xRlbl y4 0.28 0.06], ...
    'String', 'Verbose log', ...
    'Value', 1, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.cStimRepeat = uicontrol(pStimBox, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y6 0.18 0.06], ...
    'String', 'Repeat', ...
    'Value', 1, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titleStim, ...
    'BackgroundColor', C.repeatBg, ...
    'Callback', @(src,evt)localRefreshStimBoxPanel(fig));

H.eStimRepeatEvery = localMakeLabeledEdit(pStimBox, ...
    'Every', [xRlbl y6 0.12 0.055], [xRedt y6-0.008 wRedt 0.075], ...
    '50', C, panelFs, C.repeatBg);

H.hStimSummary = uicontrol(pStimBox, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.05 0.86 0.08], ...
    'String', 'StimBox disabled', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.textSoft, ...
    'BackgroundColor', C.panel);

% ------------------------------------------------------------------
% PulsePal panel
% ------------------------------------------------------------------
CPP = C;
CPP.panel = C.panel;

H.cPPEnable = uicontrol(pPulsePal, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.89 0.40 0.06], ...
    'String', 'Enable electrical stim', ...
    'Value', 0, ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titlePulse, ...
    'BackgroundColor', C.panel, ...
    'Callback', @(src,evt)localRefreshPulsePalPanel(fig));

H.ppStdBtn = uicontrol(pPulsePal, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.58 0.892 0.14 0.055], ...
    'String', 'Standard', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.blueBtn, ...
    'Callback', @(src,evt)localSwitchPulsePalTab(fig, 'std'));

H.ppAdvBtn = uicontrol(pPulsePal, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.75 0.892 0.14 0.055], ...
    'String', 'Advanced', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.btnDark, ...
    'Callback', @(src,evt)localSwitchPulsePalTab(fig, 'adv'));

H.ppStdPanel = uipanel(pPulsePal, ...
    'Units', 'normalized', ...
    'Position', [0.03 0.04 0.94 0.83], ...
    'BorderType', 'none', ...
    'BackgroundColor', CPP.panel);

H.ppAdvPanel = uipanel(pPulsePal, ...
    'Units', 'normalized', ...
    'Position', [0.03 0.04 0.94 0.83], ...
    'BorderType', 'none', ...
    'BackgroundColor', CPP.panel, ...
    'Visible', 'off');

% Standard tab
H.ePPCom = localMakeLabeledEdit(H.ppStdPanel, ...
    'COM', [xLlbl y1 0.15 0.055], [xLedt y1-0.008 wLedt 0.075], ...
    'COM14', CPP, panelFs, CPP.panel);

H.ePPChan = localMakeLabeledEdit(H.ppStdPanel, ...
    'Channel', [xRlbl y1 0.18 0.055], [xRedt y1-0.008 wRedt 0.075], ...
    '1', CPP, panelFs, CPP.panel);

H.ePPStart = localMakeLabeledEdit(H.ppStdPanel, ...
    'Frame start', [xLlbl y2 0.18 0.055], [xLedt y2-0.008 wLedt 0.075], ...
    '100', CPP, panelFs, CPP.panel);

H.ePPDurFrames = localMakeLabeledEdit(H.ppStdPanel, ...
    'Frames active', [xRlbl y2 0.20 0.055], [xRedt y2-0.008 wRedt 0.075], ...
    '1', CPP, panelFs, CPP.panel);

H.ePPVolt1 = localMakeLabeledEdit(H.ppStdPanel, ...
    'Phase1 V', [xLlbl y3 0.15 0.055], [xLedt y3-0.008 wLedt 0.075], ...
    '5', CPP, panelFs, CPP.panel);

H.ePPDur1 = localMakeLabeledEdit(H.ppStdPanel, ...
    'P1 dur / width (s)', [xRlbl y3 0.22 0.055], [xRedt y3-0.008 wRedt 0.075], ...
    '0.005', CPP, panelFs, CPP.panel);

H.ePPIPI = localMakeLabeledEdit(H.ppStdPanel, ...
    'IPI / interval (s)', [xLlbl y4 0.18 0.055], [xLedt y4-0.008 wLedt 0.075], ...
    '0.050', CPP, panelFs, CPP.panel);

H.ePPTrainDur = localMakeLabeledEdit(H.ppStdPanel, ...
    'Train dur (s)', [xRlbl y4 0.18 0.055], [xRedt y4-0.008 wRedt 0.075], ...
    '0.500', CPP, panelFs, CPP.panel);

H.ePPRest = localMakeLabeledEdit(H.ppStdPanel, ...
    'Rest V', [xLlbl y5 0.15 0.055], [xLedt y5-0.008 wLedt 0.075], ...
    '0', CPP, panelFs, CPP.panel);

H.cPPBiphasic = uicontrol(H.ppStdPanel, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xRlbl y5 0.22 0.06], ...
    'String', 'Biphasic', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', CPP.panel, ...
    'Callback', @(src,evt)localRefreshPulsePalPanel(fig));

H.cPPRepeat = uicontrol(H.ppStdPanel, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y6 0.18 0.06], ...
    'String', 'Repeat', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titlePulse, ...
    'BackgroundColor', C.repeatBg, ...
    'Callback', @(src,evt)localRefreshPulsePalPanel(fig));

H.ePPRepeatEvery = localMakeLabeledEdit(H.ppStdPanel, ...
    'Every', [xRlbl y6 0.12 0.055], [xRedt y6-0.008 wRedt 0.075], ...
    '100', CPP, panelFs, C.repeatBg);

H.hPPFreqInfo = uicontrol(H.ppStdPanel, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.10 0.82 0.04], ...
    'String', 'IPI = 0.0500 s  (~20.00 Hz)', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', smallFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.textSoft, ...
    'BackgroundColor', CPP.panel);

H.tPPNote = uicontrol(H.ppStdPanel, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.03 0.82 0.04], ...
    'String', 'P1 dur = pulse width. Train dur = total stimulation time after one trigger.', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', smallFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.textSoft, ...
    'BackgroundColor', CPP.panel);

% Advanced tab
H.ePPInterPhase = localMakeLabeledEdit(H.ppAdvPanel, ...
    'InterPhase (s)', [xLlbl y1 0.18 0.055], [xLedt y1-0.008 wLedt 0.075], ...
    '0.0001', CPP, panelFs, CPP.panel);

H.ePPVolt2 = localMakeLabeledEdit(H.ppAdvPanel, ...
    'Phase2 V', [xRlbl y1 0.18 0.055], [xRedt y1-0.008 wRedt 0.075], ...
    '-5', CPP, panelFs, CPP.panel);

H.ePPDur2 = localMakeLabeledEdit(H.ppAdvPanel, ...
    'P2 dur / width (s)', [xLlbl y2 0.22 0.055], [xLedt y2-0.008 wLedt 0.075], ...
    '0.005', CPP, panelFs, CPP.panel);

H.ePPBurstDur = localMakeLabeledEdit(H.ppAdvPanel, ...
    'Burst dur (s)', [xRlbl y2 0.18 0.055], [xRedt y2-0.008 wRedt 0.075], ...
    '0', CPP, panelFs, CPP.panel);

H.ePPInterBurst = localMakeLabeledEdit(H.ppAdvPanel, ...
    'InterBurst (s)', [xLlbl y3 0.20 0.055], [xLedt y3-0.008 wLedt 0.075], ...
    '0.100', CPP, panelFs, CPP.panel);

H.ePPTrainDelay = localMakeLabeledEdit(H.ppAdvPanel, ...
    'Train delay (s)', [xRlbl y3 0.20 0.055], [xRedt y3-0.008 wRedt 0.075], ...
    '0', CPP, panelFs, CPP.panel);

H.pPPCustomID = localMakeLabeledPopup(H.ppAdvPanel, ...
    'CustomTrainID', [xLlbl y4 0.22 0.055], [xLedt y4-0.008 0.26 0.075], ...
    {'Parametric','Custom 1','Custom 2'}, 1, CPP, CPP.panel);

H.pPPCustomTarget = localMakeLabeledPopup(H.ppAdvPanel, ...
    'Custom target', [xRlbl y4 0.18 0.055], [xRedt y4-0.008 wRedt 0.075], ...
    {'Pulses','Bursts'}, 1, CPP, CPP.panel);

H.cPPCustomLoop = uicontrol(H.ppAdvPanel, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y5 0.22 0.055], ...
    'String', 'Custom loop', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', CPP.panel);

H.cPPLink1 = uicontrol(H.ppAdvPanel, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.33 y5 0.24 0.055], ...
    'String', 'Link Trig CH1', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', CPP.panel);

H.cPPLink2 = uicontrol(H.ppAdvPanel, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.62 y5 0.24 0.055], ...
    'String', 'Link Trig CH2', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', CPP.panel);

H.pPPTrigMode1 = localMakeLabeledPopup(H.ppAdvPanel, ...
    'Trig mode CH1', [xLlbl y6 0.18 0.055], [xLedt y6-0.008 0.23 0.075], ...
    {'Normal','Toggle','Pulse gated'}, 1, CPP, CPP.panel);

H.pPPTrigMode2 = localMakeLabeledPopup(H.ppAdvPanel, ...
    'Trig mode CH2', [xRlbl y6 0.18 0.055], [xRedt y6-0.008 wRedt 0.075], ...
    {'Normal','Toggle','Pulse gated'}, 1, CPP, CPP.panel);

% ------------------------------------------------------------------
% Motor panel
% ------------------------------------------------------------------
H.cMotorEnable = uicontrol(pMotor, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.89 0.22 0.06], ...
    'String', 'Enable motor', ...
    'Value', 0, ...
    'FontSize', 11, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titleMotor, ...
    'BackgroundColor', C.panel, ...
    'Callback', @(src,evt)localRefreshMotorPanel(fig));

uicontrol(pMotor, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.30 0.89 0.16 0.055], ...
    'String', 'Acq mode', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.pMotorAcqMode = uicontrol(pMotor, 'Style', 'popupmenu', ...
    'Units', 'normalized', ...
   'Position', [0.46 0.882 0.30 0.075], ...
    'String', {'Continuous one MAT','Split per slice MAT'}, ...
    'Value', 2, ...
   'FontSize', panelFs, ...
    'BackgroundColor', C.editbg, ...
    'ForegroundColor', [0 0 0], ...
    'Callback', @(src,evt)localOnMotorAcqModeChanged(fig));

uicontrol(pMotor, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.78 0.89 0.07 0.055], ...
    'String', 'Pos', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.pMotorMode = uicontrol(pMotor, 'Style', 'popupmenu', ...
    'Units', 'normalized', ...
    'Position', [0.85 0.882 0.12 0.075], ...
    'String', {'Single','Stepped'}, ...
    'Value', 2, ...
    'FontSize', panelFs, ...
    'BackgroundColor', C.editbg, ...
    'Callback', @(src,evt)localRefreshMotorPanel(fig));

H.eMotorCom = localMakeLabeledEdit(pMotor, ...
    'COM', [xLlbl y1 0.15 0.055], [xLedt y1-0.008 wLedt 0.075], ...
    'COM8', C, panelFs, C.panel);

H.hCurrentPosLabel = uicontrol(pMotor, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [xRlbl y1 0.20 0.055], ...
    'String', 'Current pos', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.hCurrentPos = uicontrol(pMotor, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [xRedt y1-0.008 wRedt 0.075], ...
    'String', 'NA mm', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.box);

H.eMotorFrameStart = localMakeLabeledEdit(pMotor, ...
    'Active from frame', [xLlbl y2 0.20 0.055], [xLedt y2-0.008 wLedt 0.075], ...
    '0', C, panelFs, C.panel);

H.eMotorFrameDur = localMakeLabeledEdit(pMotor, ...
    'Active for frames', [xRlbl y2 0.20 0.055], [xRedt y2-0.008 wRedt 0.075], ...
    '9000', C, panelFs, C.panel);

H.eMStart = localMakeLabeledEdit(pMotor, ...
    'Start pos (mm)', [xLlbl y3 0.18 0.055], [xLedt y3-0.008 wLedt 0.075], ...
    '10', C, panelFs, C.panel);

H.eMEnd = localMakeLabeledEdit(pMotor, ...
    'End pos (mm)', [xRlbl y3 0.18 0.055], [xRedt y3-0.008 wRedt 0.075], ...
    '30', C, panelFs, C.panel);

H.eMStep = localMakeLabeledEdit(pMotor, ...
    'Step (mm)', [xLlbl y4 0.18 0.055], [xLedt y4-0.008 wLedt 0.075], ...
    '0.5', C, panelFs, C.panel);

H.eMFrames = localMakeLabeledEdit(pMotor, ...
    'Frames/slice', [xRlbl y4 0.18 0.055], [xRedt y4-0.008 wRedt 0.075], ...
    '50', C, panelFs, C.panel);

H.cMotorRepeat = uicontrol(pMotor, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl y6 0.16 0.06], ...
    'String', 'Repeat', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.titleMotor, ...
    'BackgroundColor', C.repeatBg, ...
    'Callback', @(src,evt)localRefreshMotorPanel(fig));

H.eMotorRepeatEvery = localMakeLabeledEdit(pMotor, ...
    'Every', [xRlbl y6 0.12 0.055], [xRedt y6-0.008 wRedt 0.075], ...
    '100', C, panelFs, C.repeatBg);

H.cPeriodic = uicontrol(pMotor, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [xLlbl 0.12 0.18 0.06], ...
    'String', 'Periodic', ...
    'Value', 0, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.cReturnZero = uicontrol(pMotor, 'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.12 0.24 0.06], ...
    'String', 'Return home', ...
    'Value', 1, ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.text, ...
    'BackgroundColor', C.panel);

H.bReadMotor = uicontrol(pMotor, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.72 0.08 0.20 0.08], ...
    'String', 'READ POS', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.blueBtn, ...
    'Callback', @(src,evt)localTryReadMotorPos(fig, false));

H.hMotorSummary = uicontrol(pMotor, 'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.05 0.03 0.88 0.05], ...
    'String', 'Estimated positions: 1 | Used per trial: 1', ...
    'HorizontalAlignment', 'left', ...
    'FontSize', panelFs, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', C.textSoft, ...
    'BackgroundColor', C.panel);

    % ------------------------------------------------------------------
    % Log
    % ------------------------------------------------------------------
H.logList = uicontrol(pLog, 'Style', 'listbox', ...
    'Units', 'normalized', ...
    'Position', [0.012 0.06 0.976 0.88], ...
    'Max', 2, ...
    'Min', 0, ...
    'FontName', 'Courier New', ...
    'FontSize', 14, ...
    'ForegroundColor', [0.96 0.96 0.96], ...
    'BackgroundColor', [0.06 0.07 0.09], ...
    'String', {'GUI ready.'});
    % ------------------------------------------------------------------
    % Buttons and footer
    % ------------------------------------------------------------------
    H.bStart = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.012 0.020 0.12 0.05], ...
        'String', 'START', ...
        'FontSize', 13, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', C.greenBtn, ...
        'Callback', @(src, evt)localOnStart(fig));

H.bStop = uicontrol(fig, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.142 0.020 0.12 0.05], ...
    'String', 'STOP', ...
    'FontSize', 13, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', C.redBtn, ...
    'Enable', 'on', ...
    'Callback', @(src, evt)localOnStop(fig));

    H.bDefaults = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.272 0.020 0.12 0.05], ...
        'String', 'DEFAULTS', ...
        'FontSize', 13, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', C.btn, ...
        'Callback', @(src, evt)localLoadDefaults(fig));

    H.hFooter = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.405 0.020 0.32 0.05], ...
        'String', 'by Soner Caner Cagun - MPI for Biological Cybernetics - 2026', ...
        'FontSize', 10, ...
        'HorizontalAlignment', 'center', ...
        'ForegroundColor', [0.78 0.80 0.84], ...
        'BackgroundColor', C.bg);

    H.bHelp = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.755 0.020 0.11 0.05], ...
        'String', 'HELP', ...
        'FontSize', 13, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', C.blueBtn, ...
        'Callback', @(src, evt)localShowHelpWindow());

    H.bClose = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.875 0.020 0.11 0.05], ...
        'String', 'CLOSE', ...
        'FontSize', 13, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', C.redBtn, ...
        'Callback', @(src, evt)localOnClose(fig));

    
    %Journal Button
H.bJournalNote = uicontrol(fig, 'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.355 0.445 0.290 0.036], ...
    'String', 'JOURNAL NOTE (SET BEFORE SCAN)', ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'ForegroundColor', [1 1 1], ...
    'BackgroundColor', [0.85 0.45 0.10], ...
    'Callback', @(src, evt)localEditJournalNote(fig));
    % ------------------------------------------------------------------
    % Input handles
    % ------------------------------------------------------------------
    H.inputHandles = [ ...
         H.bJournalNote ...
        H.pSaveOwner H.eXpName H.eNFrames H.eNTrials H.eNBlocks H.ePause ...
        H.eCalcSec H.eCalcFrames H.bSecToFrames H.bFramesToSec ...
        H.cStimEnable H.eStimCom H.eStimBaud H.eStimStart H.eStimDur H.cStimRepeat H.eStimRepeatEvery H.cD3 H.cD5 H.cD6 H.cStimVerbose ...
        H.cPPEnable H.ppStdBtn H.ppAdvBtn H.ePPCom H.ePPChan H.ePPStart H.ePPDurFrames H.cPPRepeat H.ePPRepeatEvery ...
        H.ePPVolt1 H.ePPDur1 H.ePPIPI H.ePPTrainDur H.ePPRest H.cPPBiphasic ...
        H.ePPInterPhase H.ePPVolt2 H.ePPDur2 H.ePPBurstDur H.ePPInterBurst H.ePPTrainDelay ...
        H.pPPCustomID H.pPPCustomTarget H.cPPCustomLoop H.cPPLink1 H.cPPLink2 H.pPPTrigMode1 H.pPPTrigMode2 ...
        H.cMotorEnable H.pMotorAcqMode H.pMotorMode H.eMotorCom H.eMotorFrameStart H.eMotorFrameDur H.cMotorRepeat H.eMotorRepeatEvery ...
        H.eMStart H.eMEnd H.eMStep H.eMFrames H.cPeriodic H.cReturnZero H.bReadMotor ...
        ];

    % ------------------------------------------------------------------
    % Callbacks
    % ------------------------------------------------------------------
    set(H.eNBlocks, 'Callback', @(src,evt)localUpdateTRDisplay(fig));
    set(H.eNFrames, 'Callback', @(src,evt)localRefreshAllSummaries(fig));

    set(H.eStimStart, 'Callback', @(src,evt)localRefreshStimBoxPanel(fig));
    set(H.eStimDur, 'Callback', @(src,evt)localRefreshStimBoxPanel(fig));
    set(H.eStimRepeatEvery, 'Callback', @(src,evt)localRefreshStimBoxPanel(fig));

    set(H.ePPStart, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
    set(H.ePPDurFrames, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
    set(H.ePPRepeatEvery, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
set(H.cPPBiphasic, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
set(H.ePPIPI, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
set(H.ePPTrainDur, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
set(H.ePPDur1, 'Callback', @(src,evt)localRefreshPulsePalPanel(fig));
    set(H.eMotorCom, 'Callback', @(src,evt)localOnMotorFieldChanged(fig));
    set(H.eMotorFrameStart, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMotorFrameDur, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMotorRepeatEvery, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMStart, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMEnd, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMStep, 'Callback', @(src,evt)localRefreshMotorPanel(fig));
    set(H.eMFrames, 'Callback', @(src,evt)localRefreshMotorPanel(fig));

    guidata(fig, H);
setappdata(fig, 'stopRequested', false);
setappdata(fig, 'isRunning', false);
setappdata(fig, 'motorCurrentPosAbsMM', NaN);
setappdata(fig, 'PulsePalTab', 'std');
setappdata(fig, 'journalNote', '');

% Live measured dt/TR tracking.
setappdata(fig, 'liveTRStats', localInitLiveTRStats());
    localSetStatus(fig, 'Idle', 'idle');
    localSetReady(fig, true);
    localSetFrame(fig, 0);
    localSetTrial(fig, 0, 0);
    localSetMotor(fig, 0, 0, NaN, 0);
    localSetCurrentPos(fig, NaN);
        localUpdateJournalNoteButton(fig);
    localAppendLog(fig, 'GUI opened.');
localResetLiveTR(fig);

    localLoadDefaults(fig);
    localRestorePulsePalTab(fig);
    localTryReadMotorPos(fig, true);
end

% =========================================================================
% UI builders
% =========================================================================
function C = localBuildColors()
    C.bg         = [0.07 0.08 0.10];
    C.banner     = [0.09 0.11 0.14];
    C.panel      = [0.12 0.14 0.18];
    C.text       = [0.96 0.97 0.98];
    C.textSoft   = [0.78 0.81 0.86];
    C.editbg     = [0.99 0.99 1.00];

    C.ready      = [0.15 0.58 0.22];
    C.notready   = [0.65 0.18 0.18];
    C.running    = [0.14 0.39 0.80];
   C.error      = [0.74 0.18 0.18];
C.warn       = [0.85 0.45 0.10];
C.good       = [0.15 0.58 0.22];
C.idle       = [0.25 0.28 0.33];

    C.btn        = [0.28 0.33 0.40];
    C.btnDark    = [0.20 0.23 0.28];
    C.greenBtn   = [0.16 0.62 0.24];
    C.redBtn     = [0.72 0.16 0.16];
    C.blueBtn    = [0.15 0.40 0.82];

    % IMPORTANT: keep this, your code still uses C.box
    C.box        = [0.18 0.21 0.26];

    % Top mini-box inner background
    C.miniBg     = [0.05 0.06 0.08];

    % Highlight background for Repeat/Every rows
    C.repeatBg   = [0.16 0.19 0.24];

    C.titleAcq   = [0.92 0.95 1.00];
    C.titleStim  = [0.50 0.95 0.66];
    C.titlePulse = [0.54 0.80 1.00];
    C.titleMotor = [0.95 0.35 0.35];

    C.edgeHeader = [0.30 0.36 0.44];
    C.edgeAcq    = [0.52 0.58 0.68];
    C.edgeStim   = [0.35 0.72 0.48];
    C.edgePulse  = [0.33 0.58 0.90];
    C.edgeMotor  = [0.82 0.22 0.22];
end

function p = localMakeMiniInfoPanel(parent, pos, titleStr, C, edgeColor)
    p = uipanel(parent, ...
        'Units', 'normalized', ...
        'Position', pos, ...
        'Title', titleStr, ...
        'FontSize', 10, ...
        'FontWeight', 'bold', ...
        'BorderType', 'line', ...
        'ForegroundColor', C.text, ...
        'BackgroundColor', edgeColor, ...
        'HighlightColor', edgeColor, ...
        'ShadowColor', edgeColor);

    inner = uipanel(p, ...
        'Units', 'normalized', ...
        'Position', [0.04 0.10 0.92 0.76], ...
        'BorderType', 'none', ...
        'BackgroundColor', C.miniBg);

    setappdata(p, 'innerPanel', inner);
end

function h = localMakeMiniInfoText(parent, s, C)
    inner = getappdata(parent, 'innerPanel');
    if isempty(inner) || ~ishandle(inner)
        inner = parent;
    end

    h = uicontrol(inner, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.02 0.96 0.96], ...
        'String', s, ...
        'FontSize', 14, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', C.miniBg);
end
function hEdit = localMakeLabeledEdit(parent, labelStr, labelPos, editPos, defaultVal, C, fs, bgColor)
    if nargin < 7
        fs = 11;
    end
    if nargin < 8
        bgColor = C.panel;
    end

    uicontrol(parent, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', labelPos, ...
        'String', labelStr, ...
        'HorizontalAlignment', 'left', ...
        'FontSize', fs, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', C.text, ...
        'BackgroundColor', bgColor);

    hEdit = uicontrol(parent, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', editPos, ...
        'String', defaultVal, ...
        'FontSize', fs, ...
        'BackgroundColor', C.editbg, ...
        'ForegroundColor', [0 0 0]);
end

function hPop = localMakeLabeledPopup(parent, labelStr, labelPos, popPos, items, defaultVal, C, bgColor)
    if nargin < 8
        bgColor = C.panel;
    end

    uicontrol(parent, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', labelPos, ...
        'String', labelStr, ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10, ...
        'FontWeight', 'bold', ...
        'ForegroundColor', C.text, ...
        'BackgroundColor', bgColor);

    hPop = uicontrol(parent, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', popPos, ...
        'String', items, ...
        'Value', defaultVal, ...
        'FontSize', 10, ...
        'BackgroundColor', C.editbg, ...
        'ForegroundColor', [0 0 0]);
end

% =========================================================================
% Panel refresh
% =========================================================================
function localRefreshAllSummaries(fig)
    if ~ishandle(fig)
        return;
    end
    localUpdateTRDisplay(fig);
    localRefreshStimBoxPanel(fig);
    localRefreshPulsePalPanel(fig);
    localRefreshMotorPanel(fig);
end

function localSwitchPulsePalTab(fig, tabName)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    switch lower(tabName)
        case 'std'
            set(H.ppStdPanel, 'Visible', 'on');
            set(H.ppAdvPanel, 'Visible', 'off');
            set(H.ppStdBtn, 'BackgroundColor', H.C.blueBtn);
            set(H.ppAdvBtn, 'BackgroundColor', H.C.btnDark);
            setappdata(fig, 'PulsePalTab', 'std');

        case 'adv'
            set(H.ppStdPanel, 'Visible', 'off');
            set(H.ppAdvPanel, 'Visible', 'on');
            set(H.ppStdBtn, 'BackgroundColor', H.C.btnDark);
            set(H.ppAdvBtn, 'BackgroundColor', H.C.blueBtn);
            setappdata(fig, 'PulsePalTab', 'adv');
    end

    drawnow limitrate;
end

function localRestorePulsePalTab(fig)
    if ~ishandle(fig)
        return;
    end

    if isappdata(fig, 'PulsePalTab')
        tabName = getappdata(fig, 'PulsePalTab');
    else
        tabName = 'std';
    end

    localSwitchPulsePalTab(fig, tabName);
end

function localRefreshStimBoxPanel(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    stimOn = logical(get(H.cStimEnable, 'Value'));
    repOn = logical(get(H.cStimRepeat, 'Value'));

    handles = [H.eStimCom H.eStimBaud H.eStimStart H.eStimDur H.cStimRepeat H.eStimRepeatEvery H.cD3 H.cD5 H.cD6 H.cStimVerbose];
    localSetHandleGroup(handles, stimOn);
    localSetHandleGroup(H.eStimRepeatEvery, stimOn && repOn);

    if ~stimOn
        set(H.hStimSummary, 'String', 'StimBox disabled');
        return;
    end

    s0 = localParseNumericNoError(get(H.eStimStart, 'String'));
    dur = localParseNumericNoError(get(H.eStimDur, 'String'));
    repEvery = localParseNumericNoError(get(H.eStimRepeatEvery, 'String'));

    activeLines = {};
    if logical(get(H.cD3, 'Value')), activeLines{end+1} = 'D3'; end %#ok<AGROW>
    if logical(get(H.cD5, 'Value')), activeLines{end+1} = 'D5'; end %#ok<AGROW>
    if logical(get(H.cD6, 'Value')), activeLines{end+1} = 'D6'; end %#ok<AGROW>

    if isempty(activeLines)
        activeText = 'none';
    else
        activeText = strjoin(activeLines, ', ');
    end

    if repOn
        repText = sprintf('repeat every %s', localNum2Str(repEvery));
    else
        repText = 'no repeat';
    end

    set(H.hStimSummary, 'String', sprintf('Start %s | Active %s frames | %s | Lines: %s', ...
        localNum2Str(s0), localNum2Str(dur), repText, activeText));
end

function localRefreshPulsePalPanel(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    ppOn = logical(get(H.cPPEnable, 'Value'));
    repOn = logical(get(H.cPPRepeat, 'Value'));
    biphasicOn = logical(get(H.cPPBiphasic, 'Value'));

    pulsepalHandles = [ ...
        H.ppStdBtn H.ppAdvBtn ...
        H.ePPCom H.ePPChan H.ePPStart H.ePPDurFrames H.cPPRepeat H.ePPRepeatEvery ...
        H.ePPVolt1 H.ePPDur1 H.ePPIPI H.ePPTrainDur H.ePPRest H.cPPBiphasic ...
        H.ePPInterPhase H.ePPVolt2 H.ePPDur2 H.ePPBurstDur H.ePPInterBurst H.ePPTrainDelay ...
        H.pPPCustomID H.pPPCustomTarget H.cPPCustomLoop H.cPPLink1 H.cPPLink2 H.pPPTrigMode1 H.pPPTrigMode2 ...
        ];

    localSetHandleGroup(pulsepalHandles, ppOn);
    localSetHandleGroup(H.ePPRepeatEvery, ppOn && repOn);

    % Only true biphasic-only controls
    localSetHandleGroup([H.ePPInterPhase H.ePPVolt2 H.ePPDur2], ppOn && biphasicOn);

    % Still disabled in your present software-triggered workflow
    localSetHandleGroup([ ...
        H.pPPCustomID H.pPPCustomTarget H.cPPCustomLoop ...
        H.cPPLink1 H.cPPLink2 H.pPPTrigMode1 H.pPPTrigMode2 ...
        ], false);

    try
        ipi = str2double(get(H.ePPIPI, 'String'));
        if ~isnan(ipi) && isfinite(ipi) && ipi > 0
            hz = 1 / ipi;
            set(H.hPPFreqInfo, 'String', sprintf('IPI = %.4f s  (~%.2f Hz)', ipi, hz));
        else
            set(H.hPPFreqInfo, 'String', 'IPI = NA');
        end
    catch
        try
            set(H.hPPFreqInfo, 'String', 'IPI = NA');
        catch
        end
    end

    localRestorePulsePalTab(fig);
end
function localOnMotorAcqModeChanged(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    acqModeIdx = get(H.pMotorAcqMode, 'Value');
    isContinuous = (acqModeIdx == 1);

    if isContinuous
        % Continuous one-MAT mode should cycle through the slice list.
        set(H.cPeriodic, 'Value', 1);

        % Start at 0 = pre-position before scan.
        set(H.eMotorFrameStart, 'String', '0');

        % Use full trial length as motor active duration.
        try
            set(H.eMotorFrameDur, 'String', get(H.eNFrames, 'String'));
        catch
        end
    end

    localRefreshMotorPanel(fig);
end
function localRefreshMotorPanel(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    motorOn = logical(get(H.cMotorEnable, 'Value'));
    steppedMode = (get(H.pMotorMode, 'Value') == 2);

    acqModeIdx = get(H.pMotorAcqMode, 'Value');
    splitMode = (acqModeIdx == 2);

    motorHandlesAlways = [ ...
        H.pMotorAcqMode H.pMotorMode H.eMotorCom ...
        H.eMStart H.cReturnZero H.bReadMotor];

    motorHandlesStepped = [H.eMEnd H.eMStep H.eMFrames];

    localSetHandleGroup([motorHandlesAlways motorHandlesStepped], motorOn);

    if motorOn
        localSetHandleGroup(motorHandlesStepped, steppedMode);
    end

    % Old continuous-only controls.
    % In split mode they are not used because each slice is its own scan.
    localSetHandleGroup([H.eMotorFrameStart H.eMotorFrameDur H.cMotorRepeat H.eMotorRepeatEvery H.cPeriodic], ...
        motorOn && ~splitMode);

    nPos = localEstimateMotorPositions(fig);
    framesPerSlice = str2double(get(H.eMFrames, 'String'));

    if isnan(framesPerSlice) || framesPerSlice < 1
        framesPerSlice = NaN;
    end

    if ~motorOn
        set(H.hMotorSummary, 'String', 'Motor OFF');
        localSetMotor(fig, 0, 0, NaN, 0);
        localSetCurrentPos(fig, NaN);

    elseif ~steppedMode
        if splitMode
            set(H.hMotorSummary, 'String', sprintf( ...
                'Split mode: 1 slice file/trial | %s frames/file | no acquisition during movement', ...
                localNum2Str(framesPerSlice)));
        else
            set(H.hMotorSummary, 'String', sprintf( ...
                'Continuous mode: single position | one MAT | %s frames/slice', ...
                localNum2Str(framesPerSlice)));
        end
        localSetMotor(fig, 0, 1, NaN, 0);

    else
        if splitMode
            set(H.hMotorSummary, 'String', sprintf( ...
                'Split mode: %d slice files/trial | %s frames/file | motor moves between files', ...
                nPos, localNum2Str(framesPerSlice)));
        else
            expectedFrames = nPos * framesPerSlice;
            set(H.hMotorSummary, 'String', sprintf( ...
                'Continuous mode: one MAT | %d slices x %s frames = ~%s frames', ...
                nPos, localNum2Str(framesPerSlice), localNum2Str(expectedFrames)));
        end

        localSetMotor(fig, 0, nPos, NaN, 0);
    end
end

function localSetHandleGroup(handles, tfEnable)
    if tfEnable
        modeStr = 'on';
    else
        modeStr = 'off';
    end

    for k = 1:numel(handles)
        try
            set(handles(k), 'Enable', modeStr);
        catch
        end
    end
end

% =========================================================================
% TR / calculator
% =========================================================================
function localUpdateTRDisplay(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    nblocks = str2double(get(H.eNBlocks, 'String'));
    if isnan(nblocks) || nblocks <= 0
        tr = NaN;
        set(H.hTR, 'String', 'NA');
    else
        tr = nblocks * 0.02;
        set(H.hTR, 'String', sprintf('%.3f s', tr));
    end

    calcFrames = str2double(get(H.eCalcFrames, 'String'));
    if ~isnan(calcFrames) && ~isnan(tr)
        set(H.eCalcSec, 'String', sprintf('%.3f', calcFrames * tr));
    end

    % When not running, update the live-dt target display too.
    try
        if ~getappdata(fig, 'isRunning')
            localResetLiveTR(fig);
        end
    catch
    end
end

function localCalcSecToFrames(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    tr = localGetTR(fig);

    secVal = str2double(get(H.eCalcSec, 'String'));
    if isnan(secVal) || isnan(tr) || tr <= 0
        localAppendLog(fig, 'Calculator error: invalid seconds or TR.');
        return;
    end

    frames = secVal / tr;
    set(H.eCalcFrames, 'String', sprintf('%.2f', frames));
end

function localCalcFramesToSec(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    tr = localGetTR(fig);

    frameVal = str2double(get(H.eCalcFrames, 'String'));
    if isnan(frameVal) || isnan(tr) || tr <= 0
        localAppendLog(fig, 'Calculator error: invalid frames or TR.');
        return;
    end

    secVal = frameVal * tr;
    set(H.eCalcSec, 'String', sprintf('%.3f', secVal));
end

function tr = localGetTR(fig)
    H = guidata(fig);
    nblocks = str2double(get(H.eNBlocks, 'String'));
    if isnan(nblocks) || nblocks <= 0
        tr = NaN;
    else
        tr = nblocks * 0.02;
    end
end

% =========================================================================
% Motor estimation
% =========================================================================
function nPos = localEstimateMotorPositions(fig)
    H = guidata(fig);

    motorOn = logical(get(H.cMotorEnable, 'Value'));
    if ~motorOn
        nPos = 0;
        return;
    end

    modeVal = get(H.pMotorMode, 'Value');
    if modeVal == 1
        nPos = 1;
        return;
    end

    s0 = str2double(get(H.eMStart, 'String'));
    s1 = str2double(get(H.eMEnd, 'String'));
    st = str2double(get(H.eMStep, 'String'));

    if any(isnan([s0 s1 st])) || st <= 0
        nPos = 1;
        return;
    end

    vals = localBuildAbsolutePositionList(s0, s1, st);
    nPos = numel(vals);
end

function nUsed = localEstimateMotorVisitsPerTrial(fig)
    H = guidata(fig);

    motorOn = logical(get(H.cMotorEnable, 'Value'));
    if ~motorOn
        nUsed = 0;
        return;
    end

    modeVal = get(H.pMotorMode, 'Value');

    if modeVal == 1
        nUsed = 1;
    else
        nUsed = localEstimateMotorPositions(fig);
    end
end

function vals = localBuildAbsolutePositionList(startPos, endPos, stepVal)
    stepVal = abs(stepVal);

    if abs(endPos - startPos) < eps
        vals = startPos;
        return;
    end

    if endPos < startPos
        stepVal = -stepVal;
    end

    vals = startPos:stepVal:endPos;

    if isempty(vals)
        vals = [startPos endPos];
    else
        if abs(vals(end) - endPos) > 1e-12
            vals = [vals endPos];
        end
    end
end

function starts = localBuildCycleStarts(frameStart, repeatOn, repeatEvery, nFramesTotal)
    if isnan(frameStart) || frameStart < 1
        frameStart = 1;
    end

    frameStart = round(frameStart);

    if ~repeatOn || isnan(repeatEvery) || repeatEvery < 1
        starts = frameStart;
    else
        starts = frameStart:max(1, round(repeatEvery)):nFramesTotal;
    end
end

function localOnMotorFieldChanged(fig)
    if ~ishandle(fig)
        return;
    end
    localRefreshMotorPanel(fig);
    localTryReadMotorPos(fig, true);
end

% =========================================================================
% Motor position read
% =========================================================================
function localTryReadMotorPos(fig, quiet)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    if ~logical(get(H.cMotorEnable, 'Value'))
        localSetCurrentPos(fig, NaN);
        return;
    end

    comName = strtrim(get(H.eMotorCom, 'String'));
    if isempty(comName)
        localSetCurrentPos(fig, NaN);
        return;
    end

    connection = [];
    try
        import zaber.motion.ascii.Connection;
        import zaber.motion.Units;

        connection = Connection.openSerialPort(comName);
        deviceList = connection.detectDevices();

        if isempty(deviceList)
            localSetCurrentPos(fig, NaN);
            if ~quiet
                localAppendLog(fig, sprintf('No motor detected on %s.', comName));
            end
            try
                connection.close();
            catch
            end
            return;
        end

        deviceIdx = 1;
        axisIdx = 1;

        if numel(deviceList) < deviceIdx
            error('Requested device index %d not found on %s.', deviceIdx, comName);
        end

        device = deviceList(deviceIdx);

        try
            nAxes = device.getAxisCount();
        catch
            nAxes = 1;
        end

        if axisIdx > nAxes
            error('Requested axis index %d not found. Device has %d axes.', axisIdx, nAxes);
        end

        axis = device.getAxis(axisIdx);
        posMM = axis.getPosition(Units.LENGTH_MILLIMETRES);

    setappdata(fig, 'motorCurrentPosAbsMM', posMM);
localSetCurrentPos(fig, posMM);

try
    set(H.eMStart, 'String', sprintf('%.3f', posMM));
catch
end

try
    localRefreshMotorPanel(fig);
catch
end

if ~quiet
    localAppendLog(fig, sprintf('Current motor position read from %s: %.3f mm', comName, posMM));
end
        try
            connection.close();
        catch
        end

    catch ME
        localSetCurrentPos(fig, NaN);
        if ~quiet
            localAppendLog(fig, sprintf('Could not read motor position: %s', ME.message));
        end
        try
            if ~isempty(connection)
                connection.close();
            end
        catch
        end
    end
end

% =========================================================================
% Start / stop / close
% =========================================================================
function localOnStart(fig)
    if ~ishandle(fig)
        return;
    end

    if getappdata(fig, 'isRunning')
        return;
    end

    try
        cfg = localCollectCfg(fig);
    catch ME
        localSetStatus(fig, ['Invalid settings: ' ME.message], 'error');
        localSetReady(fig, false);
        localAppendLog(fig, ['Invalid settings: ' ME.message]);
        return;
    end

    setappdata(fig, 'stopRequested', false);
    setappdata(fig, 'isRunning', true);

  localSetBusy(fig, true);
localSetFrame(fig, 0);
localResetLiveTR(fig);
localSetTrial(fig, 0, cfg.n_trials);
localSetMotor(fig, 0, localEstimateMotorVisitsPerTrial(fig), NaN, 0);
localSetStatus(fig, 'Starting experiment...', 'running');
    localSetReady(fig, false);
    localAppendLog(fig, 'Starting experiment...');

    cfg.gui = struct();
    cfg.gui.statusFcn = @(msg, state)localSafeGuiStatus(fig, msg, state);
    cfg.gui.logFcn = @(msg)localSafeGuiLog(fig, msg);
 cfg.gui.frameFcn = @(frameIdx)localSafeGuiFrame(fig, frameIdx);
cfg.gui.trialFcn = @(iTrial, nTrials)localSafeGuiTrial(fig, iTrial, nTrials);
cfg.gui.motorStepFcn = @(idx, total, absPosMM, frameIdx)localSafeGuiMotor(fig, idx, total, absPosMM, frameIdx);
cfg.gui.timingFcn = @(targetDt, meanDt, devPct, elapsedSec, nFrames)localSafeGuiTiming(fig, targetDt, meanDt, devPct, elapsedSec, nFrames);
cfg.gui.stopRequestedFcn = @()localSafeStopRequested(fig);
% Do not update GUI every frame. GUI drawing can slow acquisition.
cfg.gui.frameUpdateEvery = 10;

% IMPORTANT:
% Do not force processRF only for live GUI display.
% processRF is used only when needed for StimBox, PulsePal,
% or continuous motor movement.
%
% In split motor mode this keeps acquisition close to plain SCAN.doppler.
cfg.gui.forceProcessRFForLiveFrames = true;
cfg.gui.frameUpdateEvery = 1;
  try
    vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_COMMAND(cfg);

    if ishandle(fig)
        setappdata(fig, 'stopRequested', false);

        % Clear journal note after a completed run so next scan starts fresh
        setappdata(fig, 'journalNote', '');
        localUpdateJournalNoteButton(fig);

        localSetStatus(fig, 'Ready for next run', 'idle');
        localSetReady(fig, true);
        localAppendLog(fig, 'Journal note cleared after completed scan run.');
    end

catch ME
        if ishandle(fig)
            localSetStatus(fig, ['Error: ' ME.message], 'error');
            localSetReady(fig, false);
            localAppendLog(fig, ['ERROR: ' ME.message]);
        end
    end

    if ishandle(fig)
        setappdata(fig, 'isRunning', false);
        localSetBusy(fig, false);
        localTryReadMotorPos(fig, true);
    end
end

function localOnStop(fig)
    if ~ishandle(fig)
        return;
    end

    if ~getappdata(fig, 'isRunning')
        return;
    end

    setappdata(fig, 'stopRequested', true);
    localSetStatus(fig, 'Stop requested...', 'notready');
    localSetReady(fig, false);
    localAppendLog(fig, 'Stop requested by user.');
end

function localOnClose(fig)
    if ~ishandle(fig)
        return;
    end

    if getappdata(fig, 'isRunning')
        setappdata(fig, 'stopRequested', true);
        localSetStatus(fig, 'Stop requested before close...', 'notready');
        localSetReady(fig, false);
        localAppendLog(fig, 'Close requested while running. Stop requested first.');
        return;
    end

    delete(fig);
end

% =========================================================================
% Defaults
% =========================================================================
% =========================================================================
function localLoadDefaults(fig)
    H = guidata(fig);

    
set(H.pSaveOwner, 'Value', 1);   % 1 = Soner, 2 = Yan, 3 = Guest
    set(H.eXpName, 'String', 'RGRO_yymmdd_1024_MM_B6J_ID');
    set(H.eNFrames, 'String', '9000');
    set(H.eNTrials, 'String', '1');
    set(H.eNBlocks, 'String', '16');
    set(H.ePause, 'String', '1');

    % StimBox
    set(H.cStimEnable, 'Value', 0);
    set(H.eStimCom, 'String', 'COM9');
    set(H.eStimBaud, 'String', '9600');
    set(H.eStimStart, 'String', '20');
set(H.eStimDur, 'String', '10');
set(H.cStimRepeat, 'Value', 1);
set(H.eStimRepeatEvery, 'String', '50');
    set(H.cD3, 'Value', 0);
    set(H.cD5, 'Value', 1);
    set(H.cD6, 'Value', 0);
    set(H.cStimVerbose, 'Value', 1);

    % PulsePal
    % These defaults are a paper-like starter example:
    % pulse width = 0.5 ms, frequency = 4 Hz, low starting voltage
    set(H.cPPEnable, 'Value', 0);
    set(H.ePPCom, 'String', 'COM14');
    set(H.ePPChan, 'String', '1');
    set(H.ePPStart, 'String', '100');
    set(H.ePPDurFrames, 'String', '1');
    set(H.cPPRepeat, 'Value', 0);
    set(H.ePPRepeatEvery, 'String', '100');

    % Monophasic starter defaults
    set(H.ePPVolt1, 'String', '5.0');       % start low; actual current depends on load impedance
    set(H.ePPDur1, 'String', '0.0005');     % 0.5 ms pulse width
    set(H.ePPIPI, 'String', '0.25');        % 4 Hz = 0.25 s interpulse interval
    set(H.ePPTrainDur, 'String', '1.0');    % total train duration after one trigger
    set(H.ePPRest, 'String', '0');
    set(H.cPPBiphasic, 'Value', 0);

    % Biphasic-only / advanced defaults
    set(H.ePPInterPhase, 'String', '0.0001');
    set(H.ePPVolt2, 'String', '-5.0');
    set(H.ePPDur2, 'String', '0.0005');
    set(H.ePPBurstDur, 'String', '0');
    set(H.ePPInterBurst, 'String', '0.100');
    set(H.ePPTrainDelay, 'String', '0');

    % Currently unused in your software-triggered workflow
    set(H.pPPCustomID, 'Value', 1);
    set(H.pPPCustomTarget, 'Value', 1);
    set(H.cPPCustomLoop, 'Value', 0);
    set(H.cPPLink1, 'Value', 0);
    set(H.cPPLink2, 'Value', 0);
    set(H.pPPTrigMode1, 'Value', 1);
    set(H.pPPTrigMode2, 'Value', 1);

    % Motor
  set(H.cMotorEnable, 'Value', 0);
set(H.pMotorAcqMode, 'Value', 2);   % 1 = continuous, 2 = split per slice
set(H.pMotorMode, 'Value', 2);      % stepped positions
set(H.eMotorCom, 'String', 'COM8');

set(H.eMotorFrameStart, 'String', '0');
set(H.eMotorFrameDur, 'String', '9000');
set(H.cMotorRepeat, 'Value', 0);
set(H.eMotorRepeatEvery, 'String', '100');

set(H.eMStart, 'String', '0');
set(H.eMEnd, 'String', '30');
set(H.eMStep, 'String', '0.5');

set(H.eMFrames, 'String', '50');    % frames per slice
set(H.cPeriodic, 'Value', 0);
set(H.cReturnZero, 'Value', 1);
    % Calculator
    set(H.eCalcSec, 'String', '10');
    set(H.eCalcFrames, 'String', '31');

    localUpdateTRDisplay(fig);
    localRestorePulsePalTab(fig);
    localRefreshStimBoxPanel(fig);
    localRefreshPulsePalPanel(fig);
    localRefreshMotorPanel(fig);
    localTryReadMotorPos(fig, true);

    localAppendLog(fig, 'Defaults loaded.');
    localSetReady(fig, true);
    localSetStatus(fig, 'Idle', 'idle');
end

% =========================================================================
% Config collection
% =========================================================================
function cfg = localCollectCfg(fig)
    H = guidata(fig);

    cfg = struct();
    
    if isappdata(fig, 'journalNote')
    cfg.journal_note = getappdata(fig, 'journalNote');
else
    cfg.journal_note = '';
end
% Acquisition
saveOwners = get(H.pSaveOwner, 'String');
saveOwnerIdx = get(H.pSaveOwner, 'Value');
cfg.save_owner = strtrim(saveOwners{saveOwnerIdx});

    cfg.xp_name      = strtrim(get(H.eXpName, 'String'));
    cfg.n_frames     = localParseNumeric(get(H.eNFrames, 'String'), 'Frames / trial');
    cfg.n_trials     = localParseNumeric(get(H.eNTrials, 'String'), 'Trials');
    cfg.nblocksImage = localParseNumeric(get(H.eNBlocks, 'String'), 'nblocksImage');
    cfg.time_pause   = localParseNumeric(get(H.ePause, 'String'), 'Pause');

    % StimBox
    cfg.stimbox = struct();
    cfg.stimbox.enable = logical(get(H.cStimEnable, 'Value'));
    cfg.stimbox.com = strtrim(get(H.eStimCom, 'String'));
    cfg.stimbox.baud = localParseNumeric(get(H.eStimBaud, 'String'), 'StimBox baud');
    cfg.stimbox.start_frame = localParseNumeric(get(H.eStimStart, 'String'), 'StimBox frame start');
    cfg.stimbox.frame_duration = localParseNumeric(get(H.eStimDur, 'String'), 'StimBox active frames');
    cfg.stimbox.repeat_enable = logical(get(H.cStimRepeat, 'Value'));
    cfg.stimbox.repeat_interval_frames = localParseNumeric(get(H.eStimRepeatEvery, 'String'), 'StimBox repeat after frames');
    cfg.stimbox.d3_enable = logical(get(H.cD3, 'Value'));
    cfg.stimbox.d5_enable = logical(get(H.cD5, 'Value'));
    cfg.stimbox.d6_enable = logical(get(H.cD6, 'Value'));
    cfg.stimbox.verbose = logical(get(H.cStimVerbose, 'Value'));

    % legacy fields retained
    cfg.stimbox.d3_trig = NaN;
    cfg.stimbox.d5_trig = NaN;
    cfg.stimbox.d6_trig = NaN;

    % PulsePal
    cfg.pulsepal = struct();
    cfg.pulsepal.enable = logical(get(H.cPPEnable, 'Value'));
    cfg.pulsepal.com = strtrim(get(H.ePPCom, 'String'));
    cfg.pulsepal.channel = localParseNumeric(get(H.ePPChan, 'String'), 'PulsePal channel');
    cfg.pulsepal.start_frame = localParseNumeric(get(H.ePPStart, 'String'), 'PulsePal frame start');
    cfg.pulsepal.frame_duration = localParseNumeric(get(H.ePPDurFrames, 'String'), 'PulsePal active frames');
    cfg.pulsepal.repeat_enable = logical(get(H.cPPRepeat, 'Value'));
    cfg.pulsepal.repeat_interval_frames = localParseNumeric(get(H.ePPRepeatEvery, 'String'), 'PulsePal repeat after frames');

    cfg.pulsepal.is_biphasic           = logical(get(H.cPPBiphasic, 'Value'));
    cfg.pulsepal.phase1_voltage        = localParseNumeric(get(H.ePPVolt1, 'String'), 'PulsePal phase1 voltage');
    cfg.pulsepal.phase1_duration_s     = localParseNumeric(get(H.ePPDur1, 'String'), 'PulsePal phase1 duration');
    cfg.pulsepal.interphase_interval_s = localParseNumeric(get(H.ePPInterPhase, 'String'), 'PulsePal interphase interval');
    cfg.pulsepal.phase2_voltage        = localParseNumeric(get(H.ePPVolt2, 'String'), 'PulsePal phase2 voltage');
    cfg.pulsepal.phase2_duration_s     = localParseNumeric(get(H.ePPDur2, 'String'), 'PulsePal phase2 duration');
    cfg.pulsepal.resting_voltage       = localParseNumeric(get(H.ePPRest, 'String'), 'PulsePal resting voltage');
    cfg.pulsepal.interpulse_interval_s = localParseNumeric(get(H.ePPIPI, 'String'), 'PulsePal inter-pulse interval');
    cfg.pulsepal.burst_duration_s      = localParseNumeric(get(H.ePPBurstDur, 'String'), 'PulsePal burst duration');
    cfg.pulsepal.interburst_interval_s = localParseNumeric(get(H.ePPInterBurst, 'String'), 'PulsePal inter-burst interval');
    cfg.pulsepal.train_delay_s         = localParseNumeric(get(H.ePPTrainDelay, 'String'), 'PulsePal train delay');
    cfg.pulsepal.train_duration_s      = localParseNumeric(get(H.ePPTrainDur, 'String'), 'PulsePal train duration');
     % -------------------------------------------------------------
    % Current controller mode:
    % PulsePal is SOFTWARE-triggered from the scan callback by
    % TriggerPulsePal(channel) at selected frame(s).
    %
    % Therefore we keep external trigger links OFF and custom train OFF
    % until a real external-trigger mode and custom-train upload UI exist.
    % -------------------------------------------------------------
    cfg.pulsepal.custom_train_id       = 0;
    cfg.pulsepal.custom_train_target   = 0;
    cfg.pulsepal.custom_train_loop     = false;
    cfg.pulsepal.link_trigger_ch1      = false;
    cfg.pulsepal.link_trigger_ch2      = false;
    cfg.pulsepal.trigger_mode1         = 0;
    cfg.pulsepal.trigger_mode2         = 0;

    % Motor
    cfg.motor = struct();
    cfg.motor.enable = logical(get(H.cMotorEnable, 'Value'));
motorAcqItems = get(H.pMotorAcqMode, 'String');
motorAcqIdx = get(H.pMotorAcqMode, 'Value');
motorAcqText = lower(strtrim(motorAcqItems{motorAcqIdx}));

if ~isempty(strfind(motorAcqText, 'continuous'))
    cfg.motor.acquisition_mode = 'continuous';
else
    cfg.motor.acquisition_mode = 'split';
end
    if get(H.pMotorMode, 'Value') == 1
        cfg.motor.mode = 'single';
    else
        cfg.motor.mode = 'stepped';
    end

    cfg.motor.com = strtrim(get(H.eMotorCom, 'String'));
    cfg.motor.frame_start = localParseNumeric(get(H.eMotorFrameStart, 'String'), 'Motor active from frame');
    cfg.motor.frame_duration = localParseNumeric(get(H.eMotorFrameDur, 'String'), 'Motor active for frames');
    cfg.motor.repeat_enable = logical(get(H.cMotorRepeat, 'Value'));
    cfg.motor.repeat_interval_frames = localParseNumeric(get(H.eMotorRepeatEvery, 'String'), 'Motor repeat after frames');

    % IMPORTANT: absolute positions
    cfg.motor.start_mm = localParseNumeric(get(H.eMStart, 'String'), 'Motor start position');
    cfg.motor.end_mm = localParseNumeric(get(H.eMEnd, 'String'), 'Motor end position');

    % compatibility fallback
    cfg.motor.start_offset_mm = cfg.motor.start_mm;
    cfg.motor.end_offset_mm = cfg.motor.end_mm;

    cfg.motor.step_mm = localParseNumeric(get(H.eMStep, 'String'), 'Motor step size');
 cfg.motor.frames_per_position = localParseNumeric(get(H.eMFrames, 'String'), 'Frames per slice');
    cfg.motor.periodic = logical(get(H.cPeriodic, 'Value'));
    cfg.motor.return_to_zero = logical(get(H.cReturnZero, 'Value'));
    cfg.motor.settle_pause_s = 1.0;

    % Optional compatibility metadata
    if cfg.stimbox.enable
        cfg.stim_start = cfg.stimbox.start_frame;
        cfg.stim_duration = cfg.stimbox.frame_duration;
    elseif cfg.pulsepal.enable
        cfg.stim_start = cfg.pulsepal.start_frame;
        cfg.stim_duration = cfg.pulsepal.frame_duration;
    else
        cfg.stim_start = NaN;
        cfg.stim_duration = NaN;
    end

    % Legacy stim struct
    cfg.stim = struct();
    if cfg.stimbox.enable && ~cfg.pulsepal.enable
        cfg.stim.device = 'stimbox';
    elseif cfg.pulsepal.enable && ~cfg.stimbox.enable
        cfg.stim.device = 'pulsepal';
    elseif cfg.stimbox.enable && cfg.pulsepal.enable
        cfg.stim.device = 'hybrid';
    else
        cfg.stim.device = 'none';
    end
end

function v = localParseNumeric(s, labelStr)
    v = str2double(strtrim(s));
    if isnan(v)
        error('%s must be numeric.', labelStr);
    end
end

function v = localParseNumericNoError(s)
    v = str2double(strtrim(s));
    if isnan(v)
        v = NaN;
    end
end

% =========================================================================
% Busy state
% =========================================================================
function localSetBusy(fig, tf)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

 if tf
    localSetHandleGroup(H.inputHandles, false);
    set(H.bStart, 'Enable', 'off');
    set(H.bStop, 'Enable', 'on');
    set(H.bDefaults, 'Enable', 'off');
    set(H.bHelp, 'Enable', 'off');
else
    localSetHandleGroup(H.inputHandles, true);
    set(H.bStart, 'Enable', 'on');
    set(H.bStop, 'Enable', 'on');
    set(H.bDefaults, 'Enable', 'on');
    set(H.bHelp, 'Enable', 'on');

        localRefreshStimBoxPanel(fig);
        localRefreshPulsePalPanel(fig);
        localRefreshMotorPanel(fig);
    end

    drawnow limitrate;
end

% =========================================================================
% Status widgets
% =========================================================================
function localSetStatus(fig, msg, state)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    C = H.C;

    switch lower(state)
        case 'ready'
            bg = C.ready;
        case 'notready'
            bg = C.notready;
        case 'running'
            bg = C.running;
        case 'error'
            bg = C.error;
        otherwise
            bg = C.idle;
    end

    set(H.hStatus, 'String', ['Status: ' msg], 'BackgroundColor', bg);
    drawnow limitrate;
end

function localSetReady(fig, tfReady)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    C = H.C;

    if tfReady
        set(H.hReady, 'String', 'READY', 'BackgroundColor', C.ready);
    else
        set(H.hReady, 'String', 'NOT READY', 'BackgroundColor', C.notready);
    end
    drawnow limitrate;
end

function localSetFrame(fig, frameIdx, elapsedSec)
    if ~ishandle(fig)
        return;
    end

    if nargin < 3 || isempty(elapsedSec) || isnan(elapsedSec)
        elapsedSec = NaN;

        try
            if isappdata(fig, 'liveTRStats')
                S = getappdata(fig, 'liveTRStats');
                if isstruct(S) && isfield(S, 'elapsedSec')
                    elapsedSec = S.elapsedSec;
                end
            end
        catch
        end
    end

    H = guidata(fig);

    fpsVal = NaN;
    try
        if isappdata(fig, 'liveTRStats')
            S = getappdata(fig, 'liveTRStats');
            if isstruct(S) && isfield(S, 'meanDtSec') && ...
                    isfinite(S.meanDtSec) && S.meanDtSec > 0
                fpsVal = 1 / S.meanDtSec;
            end
        end
    catch
        fpsVal = NaN;
    end

    if isnan(elapsedSec)
        elapsedTxt = '--.-s';
    else
        elapsedTxt = sprintf('%.1fs', elapsedSec);
    end

    if isnan(fpsVal)
        fpsTxt = '--/s';
    else
        fpsTxt = sprintf('%.1f/s', fpsVal);
    end

    txt = sprintf('%d\n%s\n%s', round(frameIdx), elapsedTxt, fpsTxt);

    set(H.hFrame, 'String', txt);

    drawnow limitrate;
end

function localSetTrial(fig, iTrial, nTrials)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    set(H.hTrial, 'String', sprintf('%d/%d', iTrial, nTrials));
    drawnow limitrate;
end

function localSetMotor(fig, idx, totalUsed, absPosMM, frameIdx)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    if totalUsed <= 0
        txt = 'off';
    elseif idx <= 0
        txt = sprintf('0/%d', totalUsed);
    else
        txt = sprintf('%d/%d', idx, totalUsed);
    end

    set(H.hMotor, 'String', txt);

    if nargin >= 4 && ~isempty(absPosMM) && ~isnan(absPosMM)
        localSetCurrentPos(fig, absPosMM);
    end

    drawnow limitrate;
end

function localSetCurrentPos(fig, absPosMM)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    if nargin < 2 || isempty(absPosMM) || isnan(absPosMM)
        set(H.hCurrentPos, 'String', 'NA mm');
    else
        set(H.hCurrentPos, 'String', sprintf('%.3f mm', absPosMM));
    end

    drawnow limitrate;
end

% =========================================================================
% Log
% =========================================================================
function localAppendLog(fig, msg)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    old = get(H.logList, 'String');
    if ischar(old)
        old = cellstr(old);
    end
    if isempty(old)
        old = {};
    end

    stamp = datestr(now, 'HH:MM:SS');
    old{end+1} = sprintf('[%s] %s', stamp, msg);

    if numel(old) > 600
        old = old(end-599:end);
    end

    set(H.logList, 'String', old, 'Value', numel(old));
    drawnow limitrate;
end

% =========================================================================
% Safe GUI bridge
% =========================================================================
function localSafeGuiStatus(fig, msg, state)
    if ~ishandle(fig)
        return;
    end

    localSetStatus(fig, msg, state);

    if strcmpi(state, 'ready') || strcmpi(state, 'idle')
        localSetReady(fig, true);
    else
        localSetReady(fig, false);
    end
end

function localSafeGuiLog(fig, msg)
    if ~ishandle(fig)
        return;
    end
    localAppendLog(fig, msg);
end

function localSafeGuiFrame(fig, frameIdx)
    if ~ishandle(fig)
        return;
    end

    frameIdx = round(frameIdx);

    % Backend sends frame 0 before every new acquisition.
    % Use that to reset live timing.
    if frameIdx <= 0
        localResetLiveTR(fig);
        localSetFrame(fig, 0, 0);
        return;
    end

    % This updates both:
    %   1) real frame index
    %   2) real elapsed wall-clock seconds
    %   3) live measured dt/TR box
    localUpdateLiveTRFromFrame(fig, frameIdx);
end

function localSafeGuiTrial(fig, iTrial, nTrials)
    if ~ishandle(fig)
        return;
    end
    localSetTrial(fig, iTrial, nTrials);
end

function localSafeGuiMotor(fig, idx, totalFromBackend, absPosMM, frameIdx)
    if ~ishandle(fig)
        return;
    end

    if nargin < 3 || isempty(totalFromBackend) || totalFromBackend <= 0
        totalUsed = localEstimateMotorPositions(fig);
    else
        totalUsed = totalFromBackend;
    end

    localSetMotor(fig, idx, totalUsed, absPosMM, frameIdx);
end

function localSafeGuiTiming(fig, targetDt, meanDt, devPct, elapsedSec, nFrames)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);

    warnNow = false;
    if ~isempty(targetDt) && ~isnan(targetDt) && targetDt > 0 && ...
            ~isempty(meanDt) && ~isnan(meanDt)

        if abs(devPct) > 15 || abs(meanDt - targetDt) > 0.050
            warnNow = true;
        end
    end

    if isfield(H, 'hLiveDt') && ishandle(H.hLiveDt)
        if isempty(meanDt) || isnan(meanDt)
            txt = 'dt --';
            bg = H.C.miniBg;
        else
            txt = sprintf('%.3fs %+0.0f%%', meanDt, devPct);

            if warnNow
                bg = H.C.error;
            else
                bg = H.C.good;
            end
        end

        set(H.hLiveDt, ...
            'String', txt, ...
            'BackgroundColor', bg, ...
            'ForegroundColor', [1 1 1]);
    end

    drawnow limitrate;
end


function tf = localSafeStopRequested(fig)
    tf = false;
    if ~ishandle(fig)
        return;
    end

    try
        tf = logical(getappdata(fig, 'stopRequested'));
    catch
        tf = false;
    end
end

% =========================================================================
% Live measured dt / TR monitor
% =========================================================================
function S = localInitLiveTRStats()
    S.targetDtSec = NaN;

    S.firstWallSec = NaN;
    S.lastFrame = NaN;
    S.lastWallSec = NaN;

    S.elapsedSec = 0;
    S.meanDtSec = NaN;
    S.nIntervals = 0;

    % Warning rule:
    % Warn if measured dt differs from expected TR by >15 percent
    % OR by more than 50 ms.
    S.warnFrac = 0.15;
    S.warnAbsSec = 0.050;

    % Avoid log spam
    S.lastWarnFrame = -Inf;
    S.warnEveryFrames = 200;
end

function localResetLiveTR(fig)
    if ~ishandle(fig)
        return;
    end

    S = localInitLiveTRStats();
    S.targetDtSec = localGetTR(fig);
    setappdata(fig, 'liveTRStats', S);

    localSetFrame(fig, 0, 0);

    H = guidata(fig);
    if isfield(H, 'hLiveDt') && ishandle(H.hLiveDt)
        if isnan(S.targetDtSec)
            set(H.hLiveDt, 'String', 'set --', ...
                'BackgroundColor', H.C.miniBg, ...
                'ForegroundColor', [1 1 1]);
        else
            set(H.hLiveDt, 'String', sprintf('set %.3fs', S.targetDtSec), ...
                'BackgroundColor', H.C.miniBg, ...
                'ForegroundColor', [1 1 1]);
        end
    end
end

function localUpdateLiveTRFromFrame(fig, frameIdx)
    if ~ishandle(fig)
        return;
    end

    frameIdx = round(frameIdx);
    if frameIdx < 1
        return;
    end

    H = guidata(fig);

    if ~isappdata(fig, 'liveTRStats')
        setappdata(fig, 'liveTRStats', localInitLiveTRStats());
    end

    S = getappdata(fig, 'liveTRStats');

    if isempty(S) || ~isstruct(S)
        S = localInitLiveTRStats();
    end

    if isempty(S.targetDtSec) || isnan(S.targetDtSec)
        S.targetDtSec = localGetTR(fig);
    end

    nowSec = now * 86400;

    % First received real frame callback.
    if isnan(S.firstWallSec)
        S.firstWallSec = nowSec;
        S.lastFrame = frameIdx;
        S.lastWallSec = nowSec;
        S.elapsedSec = 0;

        setappdata(fig, 'liveTRStats', S);

        localSetFrame(fig, frameIdx, 0);
        return;
    end

    frameDelta = frameIdx - S.lastFrame;
    timeDeltaSec = nowSec - S.lastWallSec;

    S.elapsedSec = max(0, nowSec - S.firstWallSec);

    if frameDelta <= 0 || timeDeltaSec <= 0
        setappdata(fig, 'liveTRStats', S);
        localSetFrame(fig, frameIdx, S.elapsedSec);
        return;
    end

    blockDtSec = timeDeltaSec / frameDelta;

    if isnan(S.meanDtSec)
        S.meanDtSec = blockDtSec;
        S.nIntervals = frameDelta;
    else
        S.meanDtSec = ((S.meanDtSec * S.nIntervals) + (blockDtSec * frameDelta)) / ...
            max(1, S.nIntervals + frameDelta);
        S.nIntervals = S.nIntervals + frameDelta;
    end

    S.lastFrame = frameIdx;
    S.lastWallSec = nowSec;

    target = S.targetDtSec;
    warnNow = false;
    devPct = NaN;

    if ~isnan(target) && target > 0 && ~isnan(S.meanDtSec)
        devFrac = abs(S.meanDtSec - target) / target;
        devPct = 100 * (S.meanDtSec - target) / target;

        if devFrac > S.warnFrac || abs(S.meanDtSec - target) > S.warnAbsSec
            warnNow = true;
        end
    end

    % Update Frame / seconds box.
    localSetFrame(fig, frameIdx, S.elapsedSec);

    % Update live dt/TR box.
    if isfield(H, 'hLiveDt') && ishandle(H.hLiveDt)
        if isnan(S.meanDtSec)
            txt = 'dt --';
            bg = H.C.miniBg;
        else
            if isnan(devPct)
                txt = sprintf('%.3fs', S.meanDtSec);
            else
                txt = sprintf('%.3fs %+0.f%%', S.meanDtSec, devPct);
            end

            if warnNow
                bg = H.C.error;
            else
                bg = H.C.good;
            end
        end

        set(H.hLiveDt, 'String', txt, ...
            'BackgroundColor', bg, ...
            'ForegroundColor', [1 1 1]);
    end

    if warnNow && frameIdx - S.lastWarnFrame >= S.warnEveryFrames
        localAppendLog(fig, sprintf( ...
            'TR WARNING: expected %.3f s, measured mean %.3f s (%+.1f%%) at frame %d.', ...
            target, S.meanDtSec, devPct, frameIdx));

        S.lastWarnFrame = frameIdx;
    end

    setappdata(fig, 'liveTRStats', S);
end
% =========================================================================
% Help
% =========================================================================
function localShowHelpWindow()
    hf = figure( ...
        'Name', 'Trigger Controller Help', ...
        'NumberTitle', 'off', ...
        'MenuBar', 'none', ...
        'ToolBar', 'none', ...
        'Color', [0.09 0.09 0.10], ...
        'Position', [180 120 940 690], ...
        'Resize', 'on');

    txt = sprintf([ ...
        'OpenfUS Trigger Controller - Help\n\n' ...
        '1) Acquisition\n' ...
        '   - Frames / trial: total number of acquired frames in one trial.\n' ...
        '   - nblocksImage: determines TR for a 2D probe as TR = nblocksImage x 0.02 s.\n' ...
        '   - Trials: number of repeated acquisitions.\n' ...
        '   - Pause (s): pause between trials.\n\n' ...
        '2) StimBox\n' ...
        '   - Enable StimBox independently from all other devices.\n' ...
        '   - Frame start = first frame where the active trigger block begins.\n' ...
        '   - Frames active = how many consecutive frames the trigger block lasts.\n' ...
        '   - Repeat after frames = start a new trigger block again after that many frames.\n' ...
        '   - D3 / D5 / D6 can be enabled individually.\n\n' ...
        '3) Electrical stimulation / PulsePal\n' ...
        '   - Enable PulsePal independently from StimBox and Motor.\n' ...
        '   - Frame start = first trigger frame.\n' ...
        '   - Frames active = metadata window for scheduling block logic.\n' ...
        '   - Repeat after = trigger again after this many frames.\n' ...
        '   - Standard tab contains common stimulation parameters.\n' ...
        '   - Advanced tab contains phase 2, burst, train, custom train and trigger settings.\n\n' ...
        '4) Step Motor\n' ...
        '   - Start pos and End pos are ABSOLUTE positions in mm.\n' ...
        '   - Active from frame = first frame where the motor becomes active.\n' ...
        '   - Active for frames = size of the active motor window.\n' ...
        '   - Move every N frames = how often the motor advances to the next position.\n' ...
        '   - Example: Active from frame 10, active for 150 frames, move every 100 frames\n' ...
        '     means the motor moves at frame 10 and again at frame 110.\n' ...
        '   - Periodic repeats the position list inside one active window.\n' ...
        '   - Return home moves back to the initial read motor position when finished.\n\n' ...
        '5) Notes\n' ...
        '   - The live log is intentionally less noisy now.\n' ...
        '   - StimBox does not print every single active frame trigger by default.\n' ...
        '   - Key events, motor moves, saved files and errors are still shown.\n' ...
        ]);

    uicontrol(hf, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.03 0.04 0.94 0.92], ...
        'Max', 2, ...
        'Min', 0, ...
        'Enable', 'inactive', ...
        'HorizontalAlignment', 'left', ...
        'FontName', 'Helvetica', ...
        'FontSize', 11, ...
        'ForegroundColor', [1 1 1], ...
        'BackgroundColor', [0.12 0.12 0.13], ...
        'String', txt);
end

% =========================================================================
% Small helpers
% =========================================================================
function sessionFolder = getNextSplitMotorSessionFolder(expFolder)
% Creates next available split-motor session folder:
% Session_001_SplitMotor, Session_002_SplitMotor, ...

if nargin < 1 || isempty(expFolder) || ~exist(expFolder, 'dir')
    error('Experiment folder does not exist.');
end

d = dir(fullfile(expFolder, 'Session_*_SplitMotor'));
existingNames = {d([d.isdir]).name};

maxIdx = 0;
for i = 1:numel(existingNames)
    tok = regexp(existingNames{i}, '^Session_(\d+)_SplitMotor$', 'tokens', 'once');
    if ~isempty(tok)
        v = str2double(tok{1});
        if isfinite(v)
            maxIdx = max(maxIdx, v);
        end
    end
end

nextIdx = maxIdx + 1;
sessionFolder = fullfile(expFolder, sprintf('Session_%03d_SplitMotor', nextIdx));

if ~exist(sessionFolder, 'dir')
    mkdir(sessionFolder);
end
end

function localEditJournalNote(fig)
    if ~ishandle(fig)
        return;
    end

    prevNote = '';
    if isappdata(fig, 'journalNote')
        prevNote = getappdata(fig, 'journalNote');
    end

    defaultTemplate = sprintf([ ...
        'Experimental Scheme: Baseline 5 min, Injection 10 min, Post-injection 30 min\n' ...
        'Left: (µM, µL, µL/min)\n' ...
        'Right: (µM, µL, µL/min)\n' ...
        'Notes: ']);

    if isempty(strtrim(prevNote))
        startNote = defaultTemplate;
    else
        startNote = prevNote;
    end

    answer = inputdlg( ...
        {'Journal note for per-scan txt file (set before scan):'}, ...
        'Journal Note', ...
        [10 90], ...
        {startNote});

    if isempty(answer)
        return;
    end

    noteTxt = answer{1};

    if ischar(noteTxt) && size(noteTxt, 1) > 1
        noteTxt = strjoin(cellstr(noteTxt), sprintf('\n'));
    end

    noteTxt = strtrim(noteTxt);

    setappdata(fig, 'journalNote', noteTxt);
    localUpdateJournalNoteButton(fig);

    if isempty(noteTxt)
        localAppendLog(fig, 'Journal note cleared.');
    else
        localAppendLog(fig, 'Journal note updated.');
    end
end

function localUpdateJournalNoteButton(fig)
    if ~ishandle(fig)
        return;
    end

    H = guidata(fig);
    if isempty(H) || ~isfield(H, 'bJournalNote') || ~ishandle(H.bJournalNote)
        return;
    end

    noteTxt = '';
    if isappdata(fig, 'journalNote')
        noteTxt = getappdata(fig, 'journalNote');
    end

    if isempty(strtrim(noteTxt))
        set(H.bJournalNote, ...
            'String', 'JOURNAL NOTE (SET BEFORE SCAN)', ...
            'BackgroundColor', [0.85 0.45 0.10], ...
            'ForegroundColor', [1 1 1]);
    else
        set(H.bJournalNote, ...
            'String', 'JOURNAL NOTE SET (BEFORE SCAN)', ...
            'BackgroundColor', [0.15 0.40 0.82], ...
            'ForegroundColor', [1 1 1]);
    end
end


function s = localNum2Str(v)
    if isempty(v) || ~isnumeric(v) || isnan(v)
        s = 'NA';
    else
        if abs(v - round(v)) < 1e-12
            s = sprintf('%d', round(v));
        else
            s = sprintf('%.3f', v);
        end
    end
end