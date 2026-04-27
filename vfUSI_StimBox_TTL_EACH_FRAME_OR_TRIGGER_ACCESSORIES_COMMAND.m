function vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_COMMAND(cfg)
% ASCII safe, MATLAB 2017b compatible
%
% Backend runner used by the GUI entry file.
%
% WHAT THIS VERSION DOES
% -------------------------------------------------------------------------
% 1) Keeps backward compatibility with the older config structure.
% 2) Supports independent enable/disable for:
%       - StimBox
%       - PulsePal
%       - Step motor
% 3) Uses explicit per-trial schedules built here and passed to the object.
% 4) Supports TRUE ABSOLUTE motor start/end positions in mm.
% 5) Uses a safe processRF bridge:
%       - the callback returns RF data unchanged
%       - scheduling side effects are handled inside the object
% 6) Reduces log spam by default.
%
% IMPORTANT
% -------------------------------------------------------------------------
% This command file expects the updated object file:
%   vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_OBJECT.m
%
% That object must contain:
%   - frame_counter
%   - newImage(obj, rfIn) returning rfOut = rfIn

    if nargin < 1 || ~isstruct(cfg)
        error('Input cfg must be a struct.');
    end

    cfg = localApplyDefaults(cfg);
    cfg = localApplyBackwardCompatibility(cfg);
    localValidateConfig(cfg);

    SCAN = echoScan;
    FS   = fService();

    port = [];
    pp = [];
    pulsePalConnected = false;

    motorConnection = [];
    motorAxis = [];
    motorHomeMM = NaN;
    motorPositionsAbsMM = NaN;
    motorPlan = struct('frames', [], 'targets_abs_mm', []);

    stimboxFrames = struct('d3_frames', [], 'd5_frames', [], 'd6_frames', []);
    pulsepalTriggerFrames = [];

  sessionTag = datestr(now, 'yymmdd_HHMMSS');

% -------------------------------------------------------------
% Prepare output folder once per GUI START click.
%
% In split motor mode, all slice files from this run go into:
%   Data\<save_owner>\<xp_name>\Session_001_SplitMotor
%   Data\<save_owner>\<xp_name>\Session_002_SplitMotor
%   ...
% -------------------------------------------------------------
cfg = localPrepareSplitMotorSessionFolder(cfg, sessionTag);

userStopped = false;

    try
        localGuiStatus(cfg, 'Connecting hardware...', 'notready');
if isfield(cfg, 'output_session_folder') && ~isempty(cfg.output_session_folder)
    localGuiLog(cfg, sprintf('Split motor session folder: %s', cfg.output_session_folder));
end
        % Create callback object in all cases so GUI frame updates and STOP work
        pp = vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_OBJECT([]);

        % -----------------------------------------------------------------
        % GUI callbacks and object behaviour
        % -----------------------------------------------------------------
        localSetObjPropIfExists(pp, 'total_frames', cfg.n_frames);

        if isfield(cfg, 'gui') && isstruct(cfg.gui)
            if isfield(cfg.gui, 'frameFcn')
                localSetObjPropIfExists(pp, 'onFrameFcn', cfg.gui.frameFcn);
            end
            if isfield(cfg.gui, 'logFcn')
                localSetObjPropIfExists(pp, 'onEventFcn', cfg.gui.logFcn);
            end
            if isfield(cfg.gui, 'motorStepFcn')
                localSetObjPropIfExists(pp, 'onMotorStepFcn', cfg.gui.motorStepFcn);
            end
            if isfield(cfg.gui, 'stopRequestedFcn')
                localSetObjPropIfExists(pp, 'stopRequestedFcn', cfg.gui.stopRequestedFcn);
            end
            if isfield(cfg.gui, 'frameUpdateEvery') && ~isempty(cfg.gui.frameUpdateEvery)
                localSetObjPropIfExists(pp, 'frameUpdateEvery', cfg.gui.frameUpdateEvery);
            end
        end

        % Less noisy by default
        localSetObjPropIfExists(pp, 'verbose', false);
        localSetObjPropIfExists(pp, 'stimbox_log_each_frame', false);

        % -----------------------------------------------------------------
        % Build schedules first
        % -----------------------------------------------------------------
        stimboxFrames = localBuildStimBoxFrameSets(cfg.stimbox, cfg.n_frames);
        pulsepalTriggerFrames = localBuildPulsePalTriggerFrames(cfg.pulsepal, cfg.n_frames);

        % -----------------------------------------------------------------
        % Motor
        % -----------------------------------------------------------------
        if cfg.motor.enable
            localGuiLog(cfg, sprintf('Opening motor on %s ...', cfg.motor.com));
            [motorConnection, motorAxis, motorHomeMM] = localOpenMotor(cfg.motor.com);
            motorPositionsAbsMM = localBuildMotorPositions(motorHomeMM, cfg.motor);
            motorPlan = localBuildMotorPlan(cfg.motor, motorPositionsAbsMM, cfg.n_frames);
        else
            motorPositionsAbsMM = NaN;
            motorPlan.frames = [];
            motorPlan.targets_abs_mm = [];
        end

        % -----------------------------------------------------------------
        % StimBox
        % -----------------------------------------------------------------
        if cfg.stimbox.enable
            localGuiLog(cfg, sprintf('Opening StimBox on %s ...', cfg.stimbox.com));
            port = localOpenStimBoxPort(cfg.stimbox.com, cfg.stimbox.baud);

            localSetObjPropIfExists(pp, 'port', port);
            localSetObjPropIfExists(pp, 'stim_mode', 'stimbox');

            % Legacy fallback fields
            localSetObjPropIfExists(pp, 'd3_trig', localFramesToLegacySpec(stimboxFrames.d3_frames, cfg.n_frames));
            localSetObjPropIfExists(pp, 'd5_trig', localFramesToLegacySpec(stimboxFrames.d5_frames, cfg.n_frames));
            localSetObjPropIfExists(pp, 'd6_trig', localFramesToLegacySpec(stimboxFrames.d6_frames, cfg.n_frames));

            % New explicit frame lists
            localSetObjPropIfExists(pp, 'stimbox_enable', true);
            localSetObjPropIfExists(pp, 'stimbox_d3_frames', stimboxFrames.d3_frames);
            localSetObjPropIfExists(pp, 'stimbox_d5_frames', stimboxFrames.d5_frames);
            localSetObjPropIfExists(pp, 'stimbox_d6_frames', stimboxFrames.d6_frames);

            % Shared schedule fallback fields
            localSetObjPropIfExists(pp, 'stimbox_output_d3', cfg.stimbox.d3_enable);
            localSetObjPropIfExists(pp, 'stimbox_output_d5', cfg.stimbox.d5_enable);
            localSetObjPropIfExists(pp, 'stimbox_output_d6', cfg.stimbox.d6_enable);
            localSetObjPropIfExists(pp, 'stimbox_start_frame', cfg.stimbox.start_frame);
            localSetObjPropIfExists(pp, 'stimbox_duration_frames', cfg.stimbox.frame_duration);
            localSetObjPropIfExists(pp, 'stimbox_repeat_enable', cfg.stimbox.repeat_enable);
            localSetObjPropIfExists(pp, 'stimbox_repeat_every_frames', cfg.stimbox.repeat_interval_frames);

            % Keep object verbose off unless explicitly requested
            localSetObjPropIfExists(pp, 'verbose', logical(cfg.stimbox.verbose));

            localGuiLog(cfg, sprintf('StimBox armed on %s.', cfg.stimbox.com));
            localGuiLog(cfg, localStimBoxSummaryText(cfg, stimboxFrames));
        else
            localSetObjPropIfExists(pp, 'stimbox_enable', false);
        end

        % -----------------------------------------------------------------
        % PulsePal
        % -----------------------------------------------------------------
        if cfg.pulsepal.enable
            localGuiLog(cfg, sprintf('Opening PulsePal on %s ...', cfg.pulsepal.com));

localOpenPulsePalRobust(cfg.pulsepal.com);
pulsePalConnected = true;

if cfg.pulsepal.custom_train_id > 0
    error(['CustomTrainID > 0 is not supported yet in this GUI, ' ...
           'because no custom pulse times/voltages are uploaded with SendCustomPulseTrain.']);
end

try
    localProgramPulsePal(cfg);
catch MEpp
    localGuiLog(cfg, sprintf('PulsePal programming failed on first try, retrying: %s', MEpp.message));
    localClosePulsePalRobust();
    localKillCOMPortRobust(cfg.pulsepal.com);
    pause(0.30);
    localOpenPulsePalRobust(cfg.pulsepal.com);
    localProgramPulsePal(cfg);
end

            localGuiLog(cfg, sprintf(['PulsePal programmed: ch=%d | V1=%g V | d1=%g s | ' ...
                'IPI=%g s | train=%g s | rest=%g V | biphasic=%d'], ...
                cfg.pulsepal.channel, ...
                cfg.pulsepal.phase1_voltage, ...
                cfg.pulsepal.phase1_duration_s, ...
                cfg.pulsepal.interpulse_interval_s, ...
                cfg.pulsepal.train_duration_s, ...
                cfg.pulsepal.resting_voltage, ...
                logical(cfg.pulsepal.is_biphasic)));

            localSetObjPropIfExists(pp, 'pulsepal_enable', true);
            localSetObjPropIfExists(pp, 'pulsepal_start', localFramesToLegacyPulsePalStart(pulsepalTriggerFrames));
            localSetObjPropIfExists(pp, 'pulsepal_channel', cfg.pulsepal.channel);
            localSetObjPropIfExists(pp, 'pulsepal_duration', cfg.pulsepal.train_duration_s);
            localSetObjPropIfExists(pp, 'pulsepal_com', cfg.pulsepal.com);
            localSetObjPropIfExists(pp, 'pulsepal_verbose', true);
            localSetObjPropIfExists(pp, 'pulsepal_trigger_frames', pulsepalTriggerFrames);

            if cfg.stimbox.enable
                localSetObjPropIfExists(pp, 'stim_mode', 'hybrid');
            else
                localSetObjPropIfExists(pp, 'stim_mode', 'pulsepal');
            end

            localGuiLog(cfg, sprintf('PulsePal armed on %s, channel %d.', ...
                cfg.pulsepal.com, cfg.pulsepal.channel));
            localGuiLog(cfg, localPulsePalSummaryText(cfg, pulsepalTriggerFrames));
        else
            localSetObjPropIfExists(pp, 'pulsepal_enable', false);
        end

        if ~cfg.stimbox.enable && ~cfg.pulsepal.enable
            localGuiLog(cfg, 'No stimulation device selected.');
            localSetObjPropIfExists(pp, 'stim_mode', 'none');
        elseif cfg.stimbox.enable && cfg.pulsepal.enable
            localGuiLog(cfg, 'StimBox and PulsePal both enabled.');
            localSetObjPropIfExists(pp, 'stim_mode', 'hybrid');
        end

% -------------------------------------------------------------
% Motor callback behavior depends on acquisition mode.
%
% Split mode:
%   motor moves before SCAN.doppler
%   no motor callback
%
% Continuous mode:
%   one long MAT
%   motor moves inside processRF callback
% -------------------------------------------------------------
if cfg.motor.enable && strcmpi(localGetMotorAcqMode(cfg), 'continuous')

    continuousMotorPlan = localBuildContinuousMotorCallbackPlan( ...
        cfg.motor, motorPositionsAbsMM, cfg.n_frames);

    localSetObjPropIfExists(pp, 'motor_enable', true);
    localSetObjPropIfExists(pp, 'motor_axis', motorAxis);
    localSetObjPropIfExists(pp, 'motor_settle_pause_s', cfg.motor.settle_pause_s);

    localSetObjPropIfExists(pp, 'motor_use_explicit_plan', true);
    localSetObjPropIfExists(pp, 'motor_move_frames', continuousMotorPlan.frames);
    localSetObjPropIfExists(pp, 'motor_move_target_abs_mm', continuousMotorPlan.targets_abs_mm);
    localSetObjPropIfExists(pp, 'motor_display_total', numel(continuousMotorPlan.frames));

    localGuiLog(cfg, sprintf( ...
        'Continuous motor mode armed: %d in-scan motor moves planned.', ...
        numel(continuousMotorPlan.frames)));

else

    localSetObjPropIfExists(pp, 'motor_enable', false);
    localSetObjPropIfExists(pp, 'motor_axis', []);
    localSetObjPropIfExists(pp, 'motor_use_explicit_plan', false);
    localSetObjPropIfExists(pp, 'motor_move_frames', []);
    localSetObjPropIfExists(pp, 'motor_move_target_abs_mm', []);
    localSetObjPropIfExists(pp, 'motor_display_total', 0);

end

       % -----------------------------------------------------------------
% Main acquisition loop: STABLE SYNCHRONIZED MOTOR MODE
%
% Important:
%   - motor moves BEFORE SCAN.doppler
%   - motor settles BEFORE SCAN.doppler
%   - motor does NOT move during SCAN.doppler
%
% One motor position = one complete saved acquisition.
% -----------------------------------------------------------------

if cfg.motor.enable && ~isempty(motorPositionsAbsMM) && all(~isnan(motorPositionsAbsMM))
    scanMotorPositionsAbsMM = motorPositionsAbsMM(:)';
else
    scanMotorPositionsAbsMM = NaN;
end

motorIsValid = cfg.motor.enable && ...
    ~isempty(scanMotorPositionsAbsMM) && ...
    all(~isnan(scanMotorPositionsAbsMM));

if motorIsValid
    nMotorPositionsThisRun = numel(scanMotorPositionsAbsMM);
else
    nMotorPositionsThisRun = 1;
end

motorAcqMode = 'off';
if cfg.motor.enable && isfield(cfg.motor, 'acquisition_mode')
    motorAcqMode = cfg.motor.acquisition_mode;
end

isSplitMotor = motorIsValid && strcmpi(motorAcqMode, 'split');
isContinuousMotor = motorIsValid && strcmpi(motorAcqMode, 'continuous');

% Split mode:
%   one SCAN.doppler call per slice block.
%   Keep cycling through slices until cfg.n_frames total requested frames
%   are reached.
%
% Example:
%   cfg.n_frames = 125
%   cfg.motor.frames_per_position = 25
%   nMotorPositionsThisRun = 3
%
%   nSplitBlocksPerTrial = ceil(125 / 25) = 5
%   sequence:
%       block 1 -> slice 1, t001
%       block 2 -> slice 2, t001
%       block 3 -> slice 3, t001
%       block 4 -> slice 1, t002
%       block 5 -> slice 2, t002

if isSplitMotor
    framesPerSplitBlock = max(1, round(cfg.motor.frames_per_position));
    nSplitBlocksPerTrial = ceil(cfg.n_frames / framesPerSplitBlock);
    nMotorLoopThisRun = nSplitBlocksPerTrial;

    if mod(nSplitBlocksPerTrial, nMotorPositionsThisRun) ~= 0
        localGuiLog(cfg, sprintf([ ...
            'SPLIT MOTOR WARNING: total frames do not form complete slice cycles. ' ...
            'Frames/trial=%d, frames/slice=%d, slices=%d. ' ...
            'For clean motor reconstruction, prefer Frames/trial = slices x frames/slice x cycles.'], ...
            cfg.n_frames, framesPerSplitBlock, nMotorPositionsThisRun));
    end
else
    framesPerSplitBlock = cfg.n_frames;
    nSplitBlocksPerTrial = 1;
    nMotorLoopThisRun = 1;
end

totalAcqCount = cfg.n_trials * nMotorLoopThisRun;
acqCounter = 0;

% Split motor: do not write TXT/JOURNAL after every small MAT file.
% Store lightweight info and write ONE summary TXT at the very end.
splitSessionRows = {};
splitLastNameFile = '';
splitLastMd = struct();
splitLastTrial = NaN;

for iTrial = 1:cfg.n_trials

    for iMotor = 1:nMotorLoopThisRun

        acqCounter = acqCounter + 1;
   
        % -------------------------------------------------------------
        % Split mode block indexing
        %
        % iMotor is now the split block number, not always the slice number.
        % Convert block number into:
        %   iSliceIndex = physical motor slice
        %   iTimeIndex  = repeated time/cycle index
        % -------------------------------------------------------------
        if isSplitMotor
            iSliceIndex = mod(iMotor - 1, nMotorPositionsThisRun) + 1;
            iTimeIndex  = floor((iMotor - 1) / nMotorPositionsThisRun) + 1;
        else
            iSliceIndex = iMotor;
            iTimeIndex  = iTrial;
        end
        if localStopRequested(cfg)
            error('vfUSI:UserStop', 'User stop requested.');
        end

        localGuiFrame(cfg, 0);
        localGuiTrial(cfg, acqCounter, totalAcqCount);

        requestedMotorAbsMM = NaN;
        actualMotorAbsMM = NaN;

              % -------------------------------------------------------------
        % Motor movement before acquisition
        %
        % Split mode:
        %   move to every slice before each SCAN.doppler call.
        %
        % Continuous mode:
        %   move to the first slice before SCAN.doppler starts.
        %   later moves happen inside processRF callback.
        % -------------------------------------------------------------
 if isSplitMotor

    requestedMotorAbsMM = scanMotorPositionsAbsMM(iSliceIndex);

    localGuiStatus(cfg, sprintf( ...
        'Split mode: moving motor slice %d/%d, t%03d before acquisition...', ...
        iSliceIndex, nMotorPositionsThisRun, iTimeIndex), 'notready');

    [actualMotorAbsMM, ~] = localMoveMotorBeforeStableScan( ...
        cfg, motorAxis, requestedMotorAbsMM, iSliceIndex, nMotorPositionsThisRun);

    localGuiMotor(cfg, iSliceIndex, nMotorPositionsThisRun, actualMotorAbsMM, 0);

        elseif isContinuousMotor

            requestedMotorAbsMM = scanMotorPositionsAbsMM(1);

            localGuiStatus(cfg, sprintf( ...
                'Continuous mode: moving motor to first slice before acquisition...'), ...
                'notready');

            [actualMotorAbsMM, ~] = localMoveMotorBeforeStableScan( ...
                cfg, motorAxis, requestedMotorAbsMM, 1, nMotorPositionsThisRun);

            localGuiMotor(cfg, 1, nMotorPositionsThisRun, actualMotorAbsMM, 0);
        end
        runMsg = sprintf('Running acquisition %d/%d | Trial %d/%d', ...
            acqCounter, totalAcqCount, iTrial, cfg.n_trials);

        if cfg.motor.enable
            runMsg = sprintf('%s | Stable motor %d/%d | abs %.3f mm', ...
                runMsg, iMotor, nMotorPositionsThisRun, requestedMotorAbsMM);
        end

        localGuiStatus(cfg, runMsg, 'notready');
        localGuiLog(cfg, runMsg);

        fprintf('----- Acquisition %02d / %02d -----\n', acqCounter, totalAcqCount);
        fprintf('----- Trial %02d / %02d -----\n', iTrial, cfg.n_trials);

        if cfg.motor.enable
            fprintf('----- Stable motor position %02d / %02d: requested %.3f mm, actual %.3f mm -----\n', ...
                iMotor, nMotorPositionsThisRun, requestedMotorAbsMM, actualMotorAbsMM);
        end

                tTrial = tic;

        % -------------------------------------------------------------
        % Decide how many frames THIS SCAN.doppler call acquires.
        %
        % Split mode:
        %   each slice file gets cfg.motor.frames_per_position frames.
        %
        % Continuous mode / no motor:
        %   one full acquisition gets cfg.n_frames frames.
        % -------------------------------------------------------------
  nFramesThisAcq = cfg.n_frames;

if isSplitMotor
    framesAlreadyRequested = (iMotor - 1) * framesPerSplitBlock;
    framesRemaining = cfg.n_frames - framesAlreadyRequested;

    nFramesThisAcq = min(framesPerSplitBlock, framesRemaining);
end

        if isempty(nFramesThisAcq) || ~isnumeric(nFramesThisAcq) || ...
                isnan(nFramesThisAcq) || nFramesThisAcq < 1
            error('Invalid number of frames for this acquisition.');
        end

        nFramesThisAcq = round(nFramesThisAcq);

        % The callback object must know the frame count of THIS acquisition.
        localSetObjPropIfExists(pp, 'total_frames', nFramesThisAcq);

        % -------------------------------------------------------------
        % Configure motor behavior for this acquisition.
        %
        % Split mode:
        %   motor movement is disabled inside callback.
        %
        % Continuous mode:
        %   motor movement is enabled inside callback.
        % -------------------------------------------------------------
    if isContinuousMotor
    continuousMotorPlan = localBuildContinuousMotorCallbackPlan( ...
        cfg.motor, scanMotorPositionsAbsMM, nFramesThisAcq);

    localSetObjPropIfExists(pp, 'motor_enable', true);
    localSetObjPropIfExists(pp, 'motor_axis', motorAxis);
    localSetObjPropIfExists(pp, 'motor_settle_pause_s', cfg.motor.settle_pause_s);

    % Use explicit plan so the motor does NOT move again at frame 1.
    % The command file already moved to slice 1 before SCAN.doppler.
    localSetObjPropIfExists(pp, 'motor_use_explicit_plan', true);
    localSetObjPropIfExists(pp, 'motor_move_frames', continuousMotorPlan.frames);
    localSetObjPropIfExists(pp, 'motor_move_target_abs_mm', continuousMotorPlan.targets_abs_mm);
    localSetObjPropIfExists(pp, 'motor_display_total', numel(continuousMotorPlan.frames));

        else
            localSetObjPropIfExists(pp, 'motor_enable', false);
            localSetObjPropIfExists(pp, 'motor_axis', []);
            localSetObjPropIfExists(pp, 'motor_use_explicit_plan', false);
            localSetObjPropIfExists(pp, 'motor_move_frames', []);
            localSetObjPropIfExists(pp, 'motor_move_target_abs_mm', []);
            localSetObjPropIfExists(pp, 'motor_display_total', 0);
        end

        try
            pp.prepareTrial();
        catch
        end

   try
    acqTic = tic;
    acqStartDatenum = now;

    % -------------------------------------------------------------
    % IMPORTANT:
    % If no frame-synchronized stimulation is needed, do NOT pass
    % processRF. This keeps acquisition identical to the stable
    % collaborator/plain scanner version.
    %
    % Motor is already handled before SCAN.doppler, so motor does not
    % need processRF either.
    % -------------------------------------------------------------
useProcessRF = false;

% Need processRF for real frame-synchronized StimBox triggering.
if isfield(cfg, 'stimbox') && isstruct(cfg.stimbox) && logical(cfg.stimbox.enable)
    useProcessRF = true;
end

% Need processRF for real frame-synchronized PulsePal triggering.
if isfield(cfg, 'pulsepal') && isstruct(cfg.pulsepal) && logical(cfg.pulsepal.enable)
    useProcessRF = true;
end

% Also use processRF when the GUI wants live frame/time updates,
% even if no stimulation device is enabled.
if isfield(cfg, 'gui') && isstruct(cfg.gui) && ...
        isfield(cfg.gui, 'forceProcessRFForLiveFrames') && ...
        logical(cfg.gui.forceProcessRFForLiveFrames) && ...
        isfield(cfg.gui, 'frameFcn')
    useProcessRF = true;
end
% Continuous motor mode needs processRF because motor movements are frame-based.
if isContinuousMotor
    useProcessRF = true;
end

if useProcessRF
    if logical(cfg.stimbox.enable) || logical(cfg.pulsepal.enable)
        localGuiLog(cfg, 'Using processRF callback for stimulation + live GUI frame/time updates.');
    else
        localGuiLog(cfg, 'Using processRF callback for live GUI frame/time updates only.');
    end
[I, md] = SCAN.doppler(cfg.nblocksImage, nFramesThisAcq, ...
    'processRF', @(rf)localProcessRFBridge(pp, rf));
else
    localGuiLog(cfg, 'Using plain SCAN.doppler without processRF callback.');

  [I, md] = SCAN.doppler(cfg.nblocksImage, nFramesThisAcq);
end

 acqElapsedSec = toc(acqTic);
acqEndDatenum = now;

requestedDtSec = localCalcTRSec(cfg.nblocksImage);
actualFrames = localGetAcquiredFrameCount(I, nFramesThisAcq);
actualMeanDtSec = acqElapsedSec / max(1, actualFrames);

    try
        md.requested_dt_s = requestedDtSec;
        md.actual_acq_elapsed_s = acqElapsedSec;
        md.actual_frames_saved = actualFrames;
        md.actual_mean_dt_s = actualMeanDtSec;
        md.actual_dt_deviation_s = actualMeanDtSec - requestedDtSec;
        md.actual_dt_deviation_percent = 100 * (actualMeanDtSec - requestedDtSec) / requestedDtSec;
    catch
    end

if requestedDtSec > 0
    devPct = 100 * (actualMeanDtSec - requestedDtSec) / requestedDtSec;

    localGuiTiming(cfg, requestedDtSec, actualMeanDtSec, devPct, acqElapsedSec, actualFrames);

    if abs(devPct) > 15 || abs(actualMeanDtSec - requestedDtSec) > 0.050
        localGuiLog(cfg, sprintf( ...
            'TR WARNING after acquisition: requested %.3f s, actual mean %.3f s (%+.1f%%).', ...
            requestedDtSec, actualMeanDtSec, devPct));
    else
        localGuiLog(cfg, sprintf( ...
            'Timing QC: requested %.3f s, actual mean %.3f s (%+.1f%%).', ...
            requestedDtSec, actualMeanDtSec, devPct));
    end
end

catch ME
    localGuiLog(cfg, sprintf('DOPPLER FAILURE: %s', ME.message));
    fprintf(2, '\n===== DOPPLER FAILURE =====\n');
    fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));
    rethrow(ME);
end

          % -------------------------------------------------------------
        % Add acquisition + motor metadata
        % -------------------------------------------------------------
        try
            md.acquisition_mode = 'normal';

            if cfg.motor.enable
                md.acquisition_mode = cfg.motor.acquisition_mode;
            end

            md.requested_frames_this_file = nFramesThisAcq;
            md.acq_start_datenum = acqStartDatenum;
            md.acq_end_datenum = acqEndDatenum;
            md.acq_start_time_string = datestr(acqStartDatenum, 'yyyy-mm-dd HH:MM:SS.FFF');
            md.acq_end_time_string = datestr(acqEndDatenum, 'yyyy-mm-dd HH:MM:SS.FFF');

            md.motor_enabled = logical(cfg.motor.enable);
            md.motor_acquisition_mode = motorAcqMode;

            md.motor_split_mode = logical(isSplitMotor);
            md.motor_continuous_mode = logical(isContinuousMotor);

            md.motor_moves_during_acquisition = logical(isContinuousMotor);
            md.motor_moves_between_acquisitions = logical(isSplitMotor);

            md.motor_stable_acquisition = logical(isSplitMotor);
            md.motor_frames_per_slice_requested = cfg.motor.frames_per_position;md.motor_time_index = iTimeIndex;
md.motor_slice_index = iSliceIndex;
md.motor_slice_count = nMotorPositionsThisRun;

md.timeIndex = iTimeIndex;
md.sliceIndex = iSliceIndex;

md.motor_index = iSliceIndex;
md.motor_n_positions = nMotorPositionsThisRun;
            md.motor_requested_abs_mm = requestedMotorAbsMM;
            md.motor_actual_abs_mm = actualMotorAbsMM;
            md.motor_home_abs_mm = motorHomeMM;

            if ~isnan(requestedMotorAbsMM) && ~isnan(motorHomeMM)
                md.motor_requested_rel_mm = requestedMotorAbsMM - motorHomeMM;
            else
                md.motor_requested_rel_mm = NaN;
            end

            if ~isnan(actualMotorAbsMM) && ~isnan(motorHomeMM)
                md.motor_actual_rel_mm = actualMotorAbsMM - motorHomeMM;
            else
                md.motor_actual_rel_mm = NaN;
            end

            md.motor_settle_pause_s = cfg.motor.settle_pause_s;

            if isSplitMotor
                md.motor_rebuild_hint = 'Split mode: sort files by motor_time_index, then motor_slice_index.';
            elseif isContinuousMotor
                md.motor_rebuild_hint = 'Continuous mode: one file contains all motor positions; use frames_per_position and motor plan.';
            else
                md.motor_rebuild_hint = 'No motor reconstruction needed.';
            end
        catch
        end
        
        [nameFile, nameShort] = localMakeSaveName(FS, cfg, sessionTag, motorPositionsAbsMM, motorHomeMM, iTrial);

              if cfg.motor.enable
            if isSplitMotor
            [nameFile, nameShort] = localAppendSplitSliceToSaveName( ...
    nameFile, iTimeIndex, iSliceIndex, nMotorPositionsThisRun, ...
    requestedMotorAbsMM, motorHomeMM);

            elseif isContinuousMotor
                [nameFile, nameShort] = localAppendContinuousMotorToSaveName( ...
                    nameFile, nMotorPositionsThisRun, cfg.motor.frames_per_position, ...
                    scanMotorPositionsAbsMM(1), scanMotorPositionsAbsMM(end), motorHomeMM);

            else
          [nameFile, nameShort] = localAppendMotorPositionToSaveName( ...
    nameFile, cfg, requestedMotorAbsMM, motorHomeMM, iMotor, iTimeIndex);
            end
        end

        [nameFile, nameShort] = localMakeFileNameUnique(nameFile);

infoI = whos('I');
localGuiLog(cfg, sprintf('Saving I: class=%s | size=%s | %.2f MB', ...
    infoI.class, mat2str(size(I)), infoI.bytes/1024/1024));


% In split motor mode, writing a txt file after every tiny slice file
% adds avoidable delay between slices. The MAT already contains md.
% Write txt only for the first split file and the last split file.
if isSplitMotor
    localFastSaveMat(nameFile, I, md, cfg);
else
    localReliableSaveMat(nameFile, I, md, cfg);
end

% IMPORTANT:
% In split motor mode, do NOT write TXT during acquisition.
% This prevents slow delay between slice files / trials.
if ~isSplitMotor
    localWriteScanInfoText(nameFile, cfg, iTrial, md);
end

% Keep lightweight split info in memory for one final summary TXT.
if isSplitMotor
    splitLastNameFile = nameFile;
    splitLastMd = md;
    splitLastTrial = iTrial;

    splitSessionRows{end+1} = sprintf( ...
        'File=%s | Trial=%d | T=%03d | Slice=%03d/%03d | Frames=%d | ReqAbs=%.3f | ActAbs=%.3f', ...
        nameShort, iTrial, iTimeIndex, iSliceIndex, nMotorPositionsThisRun, ...
        nFramesThisAcq, requestedMotorAbsMM, actualMotorAbsMM); %#ok<AGROW>
end
        journalTxt = localMakeJournalText(nameShort, cfg, motorPositionsAbsMM, motorHomeMM, iTrial);
        if isfield(cfg, 'output_session_name') && ~isempty(cfg.output_session_name)
    journalTxt = sprintf('%s | OutputSession=%s', journalTxt, cfg.output_session_name);
end
        if cfg.motor.enable
            if isSplitMotor
            journalTxt = sprintf('%s | MotorMode=SPLIT | T=%03d | Slice=%d/%d | FramesThisFile=%d | ReqAbs=%.3f mm | ActAbs=%.3f mm | MotorNotMovingDuringAcq=1', ...
    journalTxt, iTimeIndex, iSliceIndex, nMotorPositionsThisRun, nFramesThisAcq, requestedMotorAbsMM, actualMotorAbsMM);

            elseif isContinuousMotor
                journalTxt = sprintf('%s | MotorMode=CONTINUOUS | Slices=%d | FramesPerSlice=%d | FramesThisFile=%d | MotorMovesDuringAcq=1', ...
                    journalTxt, nMotorPositionsThisRun, round(cfg.motor.frames_per_position), nFramesThisAcq);

            else
                journalTxt = sprintf('%s | MotorMode=UNKNOWN | FramesThisFile=%d', ...
                    journalTxt, nFramesThisAcq);
            end
        end

% In split motor mode, do not write journal during acquisition.
% Journal/file-system writing can delay the next slice/trial.
writeJournalNow = ~isSplitMotor;

if writeJournalNow
    try
        FS.writeJournal(journalTxt);
    catch MEj
        localGuiLog(cfg, sprintf('Journal write warning: %s', MEj.message));
    end
end

        localGuiLog(cfg, sprintf('Saved file: %s', nameFile));
        localGuiLog(cfg, sprintf('Saved folder: %s', fileparts(nameFile)));

        fprintf('Elapsed time: %.1f seconds\n', toc(tTrial));

 doPauseNow = false;

if isSplitMotor
    % In split mode, do NOT pause between slice files.
    % Only pause after the full split trial is finished.
    doPauseNow = (iMotor == nMotorLoopThisRun) && (iTrial < cfg.n_trials);
else
    doPauseNow = acqCounter < totalAcqCount;
end

if doPauseNow
    localGuiStatus(cfg, 'Waiting before next trial...', 'notready');
    localSafePause(cfg.time_pause);
end
    end
end

        % After split motor acquisition is completely finished,
        % write ONE summary TXT and ONE journal entry.
        if isSplitMotor && ~isempty(splitLastNameFile)
            try
                localWriteSplitSessionSummaryText( ...
                    cfg, splitSessionRows, splitLastNameFile, splitLastTrial, splitLastMd);
            catch MEsum
                localGuiLog(cfg, sprintf('Split summary TXT warning: %s', MEsum.message));
            end

            try
                FS.writeJournal(sprintf( ...
                    '* Split motor session finished | Folder=%s | Files=%d | Frames/trial=%d | Frames/slice=%d', ...
                    fileparts(splitLastNameFile), numel(splitSessionRows), ...
                    cfg.n_frames, round(cfg.motor.frames_per_position)));
            catch MEj
                localGuiLog(cfg, sprintf('Final split journal warning: %s', MEj.message));
            end
        end

        localGuiStatus(cfg, 'Experiment finished successfully.', 'ready');
        localGuiLog(cfg, 'Experiment finished successfully.');

    catch ME
        if strcmp(ME.identifier, 'vfUSI:UserStop')
            userStopped = true;
            localGuiStatus(cfg, 'Experiment stopped by user.', 'notready');
            localGuiLog(cfg, 'Experiment stopped by user.');
        else
            localGuiStatus(cfg, sprintf('Error: %s', ME.message), 'error');
            localGuiLog(cfg, sprintf('ERROR: %s', ME.message));
            fprintf(2, 'ERROR in vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_COMMAND:\n');
            fprintf(2, '  %s\n', ME.message);
            localCleanup();
            rethrow(ME);
        end
    end

    localCleanup();

    if userStopped
        return;
    end

    % =====================================================================
    % Cleanup
    % =====================================================================
     function localCleanup()
        if cfg.motor.enable
            try
                if ~isempty(motorAxis) && ~isnan(motorHomeMM) && cfg.motor.return_to_zero
                    localGuiStatus(cfg, 'Returning motor to home position...', 'notready');
                    motorAxis.moveAbsolute(motorHomeMM, zaber.motion.Units.LENGTH_MILLIMETRES);
                    localSafePause(0.10);
                end
            catch
            end

            try
                if ~isempty(motorConnection)
                    motorConnection.close();
                end
            catch
            end
        end

        try
            if ~isempty(port)
                if strcmpi(class(port), 'serial')
                    if strcmpi(port.Status, 'open')
                        fclose(port);
                    end
                    delete(port);

                    try
                        delete(instrfind('Port', cfg.stimbox.com));
                    catch
                    end

                elseif strcmpi(class(port), 'serialport')
                    delete(port);
                end
            end
        catch
        end

        if pulsePalConnected
            localClosePulsePalRobust();
        end
     end


% =========================================================================
% Safe processRF bridge
% =========================================================================
function rfOut = localProcessRFBridge(pp, rfIn)
    % Safe bridge for echoScan processRF.
    %
    % Some OpenfUS / echoScan versions expect the processRF callback to
    % return RF data, but the collaborator-style pp.newImage callback often
    % has NO output argument.
    %
    % Therefore:
    %   - call pp.newImage(rfIn) only for side effects:
    %       GUI frame update, StimBox, PulsePal, stop check
    %   - always return rfIn unchanged to echoScan
    %   - motor movement is NOT handled here

    rfOut = rfIn;

    try
        pp.newImage(rfIn);   % no output expected from object callback
    catch ME
        rethrow(ME);
    end
end

function [I, md, actualFrames, acqElapsedSec, requestedDtSec, actualMeanDtSec] = ...
    localRunDopplerAcquisition(SCAN, pp, cfg, nFramesThis)

    nFramesThis = max(1, round(nFramesThis));

    localSetObjPropIfExists(pp, 'total_frames', nFramesThis);

    try
        pp.prepareTrial();
    catch
    end

    acqTic = tic;
    useProcessRF = localShouldUseProcessRF(cfg);

    try
        if useProcessRF
            localGuiLog(cfg, 'Using processRF callback.');

            [I, md] = SCAN.doppler(cfg.nblocksImage, nFramesThis, ...
                'processRF', @(rf)localProcessRFBridge(pp, rf));
        else
            localGuiLog(cfg, 'Using plain SCAN.doppler without processRF callback.');

            [I, md] = SCAN.doppler(cfg.nblocksImage, nFramesThis);
        end

    catch ME
        localGuiLog(cfg, sprintf('DOPPLER FAILURE: %s', ME.message));
        fprintf(2, '\n===== DOPPLER FAILURE =====\n');
        fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));
        rethrow(ME);
    end

    acqElapsedSec = toc(acqTic);

    requestedDtSec = localCalcTRSec(cfg.nblocksImage);
    actualFrames = localGetAcquiredFrameCount(I, nFramesThis);
    actualMeanDtSec = acqElapsedSec / max(1, actualFrames);

    try
        md.requested_dt_s = requestedDtSec;
        md.actual_acq_elapsed_s = acqElapsedSec;
        md.actual_frames_saved = actualFrames;
        md.actual_mean_dt_s = actualMeanDtSec;
        md.actual_dt_deviation_s = actualMeanDtSec - requestedDtSec;
        md.actual_dt_deviation_percent = 100 * ...
            (actualMeanDtSec - requestedDtSec) / requestedDtSec;
    catch
    end

    if requestedDtSec > 0
        devPct = 100 * (actualMeanDtSec - requestedDtSec) / requestedDtSec;

        localGuiTiming(cfg, requestedDtSec, actualMeanDtSec, ...
            devPct, acqElapsedSec, actualFrames);

        if abs(devPct) > 15 || abs(actualMeanDtSec - requestedDtSec) > 0.050
            localGuiLog(cfg, sprintf( ...
                'TR WARNING after acquisition: requested %.3f s, actual mean %.3f s (%+.1f%%).', ...
                requestedDtSec, actualMeanDtSec, devPct));
        else
            localGuiLog(cfg, sprintf( ...
                'Timing QC: requested %.3f s, actual mean %.3f s (%+.1f%%).', ...
                requestedDtSec, actualMeanDtSec, devPct));
        end
    end
end


% =========================================================================
% Defaults
% =========================================================================
function cfg = localApplyDefaults(cfg)

    if ~isfield(cfg, 'xp_name') || isempty(cfg.xp_name)
        cfg.xp_name = 'Data_w_Triggers';
    end

    if ~isfield(cfg, 'n_frames') || isempty(cfg.n_frames)
        cfg.n_frames = 9000;
    end

    if ~isfield(cfg, 'nblocksImage') || isempty(cfg.nblocksImage)
        cfg.nblocksImage = 16;
    end

    if ~isfield(cfg, 'n_trials') || isempty(cfg.n_trials)
        cfg.n_trials = 1;
    end

    if ~isfield(cfg, 'time_pause') || isempty(cfg.time_pause)
        cfg.time_pause = 1;
    end

    if ~isfield(cfg, 'stim_start') || isempty(cfg.stim_start)
        cfg.stim_start = NaN;
    end

    if ~isfield(cfg, 'stim_duration') || isempty(cfg.stim_duration)
        cfg.stim_duration = NaN;
    end

    % ---------------- StimBox ----------------
    if ~isfield(cfg, 'stimbox') || ~isstruct(cfg.stimbox)
        cfg.stimbox = struct();
    end

    if ~isfield(cfg.stimbox, 'enable') || isempty(cfg.stimbox.enable)
        cfg.stimbox.enable = false;
    end

    if ~isfield(cfg.stimbox, 'com') || isempty(cfg.stimbox.com)
        cfg.stimbox.com = 'COM9';
    end

    if ~isfield(cfg.stimbox, 'baud') || isempty(cfg.stimbox.baud)
        cfg.stimbox.baud = 9600;
    end

    if ~isfield(cfg.stimbox, 'verbose') || isempty(cfg.stimbox.verbose)
        cfg.stimbox.verbose = true;
    end

    if ~isfield(cfg.stimbox, 'start_frame') || isempty(cfg.stimbox.start_frame)
        cfg.stimbox.start_frame = 20;
    end

    if ~isfield(cfg.stimbox, 'frame_duration') || isempty(cfg.stimbox.frame_duration)
        cfg.stimbox.frame_duration = 10;
    end

    if ~isfield(cfg.stimbox, 'repeat_enable') || isempty(cfg.stimbox.repeat_enable)
        cfg.stimbox.repeat_enable = true;
    end

    if ~isfield(cfg.stimbox, 'repeat_interval_frames') || isempty(cfg.stimbox.repeat_interval_frames)
        cfg.stimbox.repeat_interval_frames = 50;
    end

    if ~isfield(cfg.stimbox, 'd3_enable') || isempty(cfg.stimbox.d3_enable)
        cfg.stimbox.d3_enable = false;
    end

    if ~isfield(cfg.stimbox, 'd5_enable') || isempty(cfg.stimbox.d5_enable)
        cfg.stimbox.d5_enable = true;
    end

    if ~isfield(cfg.stimbox, 'd6_enable') || isempty(cfg.stimbox.d6_enable)
        cfg.stimbox.d6_enable = false;
    end

    if ~isfield(cfg.stimbox, 'd3_trig') || isempty(cfg.stimbox.d3_trig)
        cfg.stimbox.d3_trig = NaN;
    end

    if ~isfield(cfg.stimbox, 'd5_trig') || isempty(cfg.stimbox.d5_trig)
        cfg.stimbox.d5_trig = NaN;
    end

    if ~isfield(cfg.stimbox, 'd6_trig') || isempty(cfg.stimbox.d6_trig)
        cfg.stimbox.d6_trig = NaN;
    end

    % ---------------- PulsePal ----------------
    if ~isfield(cfg, 'pulsepal') || ~isstruct(cfg.pulsepal)
        cfg.pulsepal = struct();
    end

    if ~isfield(cfg.pulsepal, 'enable') || isempty(cfg.pulsepal.enable)
        cfg.pulsepal.enable = false;
    end

    if ~isfield(cfg.pulsepal, 'com') || isempty(cfg.pulsepal.com)
        cfg.pulsepal.com = 'COM14';
    end

    if ~isfield(cfg.pulsepal, 'channel') || isempty(cfg.pulsepal.channel)
        cfg.pulsepal.channel = 1;
    end

    if ~isfield(cfg.pulsepal, 'start_frame') || isempty(cfg.pulsepal.start_frame)
        cfg.pulsepal.start_frame = 100;
    end

    if ~isfield(cfg.pulsepal, 'frame_duration') || isempty(cfg.pulsepal.frame_duration)
        cfg.pulsepal.frame_duration = 1;
    end

    if ~isfield(cfg.pulsepal, 'repeat_enable') || isempty(cfg.pulsepal.repeat_enable)
        cfg.pulsepal.repeat_enable = false;
    end

    if ~isfield(cfg.pulsepal, 'repeat_interval_frames') || isempty(cfg.pulsepal.repeat_interval_frames)
        cfg.pulsepal.repeat_interval_frames = 10;
    end

    if ~isfield(cfg.pulsepal, 'is_biphasic') || isempty(cfg.pulsepal.is_biphasic)
        cfg.pulsepal.is_biphasic = false;
    end
    if ~isfield(cfg.pulsepal, 'phase1_voltage') || isempty(cfg.pulsepal.phase1_voltage)
        cfg.pulsepal.phase1_voltage = 5;
    end
    if ~isfield(cfg.pulsepal, 'phase1_duration_s') || isempty(cfg.pulsepal.phase1_duration_s)
        cfg.pulsepal.phase1_duration_s = 0.005;
    end
    if ~isfield(cfg.pulsepal, 'interphase_interval_s') || isempty(cfg.pulsepal.interphase_interval_s)
        cfg.pulsepal.interphase_interval_s = 0.0001;
    end
    if ~isfield(cfg.pulsepal, 'phase2_voltage') || isempty(cfg.pulsepal.phase2_voltage)
        cfg.pulsepal.phase2_voltage = -5;
    end
    if ~isfield(cfg.pulsepal, 'phase2_duration_s') || isempty(cfg.pulsepal.phase2_duration_s)
        cfg.pulsepal.phase2_duration_s = 0.005;
    end
    if ~isfield(cfg.pulsepal, 'resting_voltage') || isempty(cfg.pulsepal.resting_voltage)
        cfg.pulsepal.resting_voltage = 0;
    end
    if ~isfield(cfg.pulsepal, 'interpulse_interval_s') || isempty(cfg.pulsepal.interpulse_interval_s)
        cfg.pulsepal.interpulse_interval_s = 0.050;
    end
    if ~isfield(cfg.pulsepal, 'burst_duration_s') || isempty(cfg.pulsepal.burst_duration_s)
        cfg.pulsepal.burst_duration_s = 0;
    end
    if ~isfield(cfg.pulsepal, 'interburst_interval_s') || isempty(cfg.pulsepal.interburst_interval_s)
        cfg.pulsepal.interburst_interval_s = 0.100;
    end
    if ~isfield(cfg.pulsepal, 'train_delay_s') || isempty(cfg.pulsepal.train_delay_s)
        cfg.pulsepal.train_delay_s = 0;
    end
    if ~isfield(cfg.pulsepal, 'train_duration_s') || isempty(cfg.pulsepal.train_duration_s)
        cfg.pulsepal.train_duration_s = 0.500;
    end
    if ~isfield(cfg.pulsepal, 'custom_train_id') || isempty(cfg.pulsepal.custom_train_id)
        cfg.pulsepal.custom_train_id = 0;
    end
    if ~isfield(cfg.pulsepal, 'custom_train_target') || isempty(cfg.pulsepal.custom_train_target)
        cfg.pulsepal.custom_train_target = 0;
    end
    if ~isfield(cfg.pulsepal, 'custom_train_loop') || isempty(cfg.pulsepal.custom_train_loop)
        cfg.pulsepal.custom_train_loop = false;
    end
    if ~isfield(cfg.pulsepal, 'link_trigger_ch1') || isempty(cfg.pulsepal.link_trigger_ch1)
        cfg.pulsepal.link_trigger_ch1 = false;
    end
    if ~isfield(cfg.pulsepal, 'link_trigger_ch2') || isempty(cfg.pulsepal.link_trigger_ch2)
        cfg.pulsepal.link_trigger_ch2 = false;
    end
    if ~isfield(cfg.pulsepal, 'trigger_mode1') || isempty(cfg.pulsepal.trigger_mode1)
        cfg.pulsepal.trigger_mode1 = 0;
    end
    if ~isfield(cfg.pulsepal, 'trigger_mode2') || isempty(cfg.pulsepal.trigger_mode2)
        cfg.pulsepal.trigger_mode2 = 0;
    end

    % ---------------- Motor ----------------
    if ~isfield(cfg, 'motor') || ~isstruct(cfg.motor)
        cfg.motor = struct();
    end

    if ~isfield(cfg.motor, 'enable') || isempty(cfg.motor.enable)
        cfg.motor.enable = true;
    end
if ~isfield(cfg.motor, 'acquisition_mode') || isempty(cfg.motor.acquisition_mode)
    cfg.motor.acquisition_mode = 'split';
end

if ~strcmpi(cfg.motor.acquisition_mode, 'continuous') && ~strcmpi(cfg.motor.acquisition_mode, 'split')
    error('cfg.motor.acquisition_mode must be continuous or split.');
end
    if ~isfield(cfg.motor, 'mode') || isempty(cfg.motor.mode)
        cfg.motor.mode = 'stepped';
    end

    if ~isfield(cfg.motor, 'com') || isempty(cfg.motor.com)
        cfg.motor.com = 'COM8';
    end

    if ~isfield(cfg.motor, 'frame_start') || isempty(cfg.motor.frame_start)
        cfg.motor.frame_start = 1;
    end

    if ~isfield(cfg.motor, 'frame_duration') || isempty(cfg.motor.frame_duration)
        cfg.motor.frame_duration = cfg.n_frames;
    end

    if ~isfield(cfg.motor, 'repeat_enable') || isempty(cfg.motor.repeat_enable)
        cfg.motor.repeat_enable = false;
    end

    if ~isfield(cfg.motor, 'repeat_interval_frames') || isempty(cfg.motor.repeat_interval_frames)
        cfg.motor.repeat_interval_frames = 100;
    end

    if ~isfield(cfg.motor, 'start_mm')
        cfg.motor.start_mm = [];
    end
    if ~isfield(cfg.motor, 'end_mm')
        cfg.motor.end_mm = [];
    end

    if ~isfield(cfg.motor, 'start_offset_mm') || isempty(cfg.motor.start_offset_mm)
        cfg.motor.start_offset_mm = -2;
    end

    if ~isfield(cfg.motor, 'end_offset_mm') || isempty(cfg.motor.end_offset_mm)
        cfg.motor.end_offset_mm = 2;
    end

    if ~isfield(cfg.motor, 'step_mm') || isempty(cfg.motor.step_mm)
        cfg.motor.step_mm = 0.5;
    end
if ~isfield(cfg.motor, 'frames_per_position') || isempty(cfg.motor.frames_per_position)
    cfg.motor.frames_per_position = 50;
end

    if ~isfield(cfg.motor, 'periodic') || isempty(cfg.motor.periodic)
        cfg.motor.periodic = false;
    end

    if ~isfield(cfg.motor, 'return_to_zero') || isempty(cfg.motor.return_to_zero)
        cfg.motor.return_to_zero = true;
    end

    if ~isfield(cfg.motor, 'settle_pause_s') || isempty(cfg.motor.settle_pause_s)
        cfg.motor.settle_pause_s = 1.0;
    end
end

% =========================================================================
% Backward compatibility bridge
% =========================================================================
function cfg = localApplyBackwardCompatibility(cfg)

    if isfield(cfg, 'stim') && isstruct(cfg.stim) && isfield(cfg.stim, 'device') && ~isempty(cfg.stim.device)
        switch lower(strtrim(cfg.stim.device))
            case 'stimbox'
                if ~isfield(cfg.stimbox, 'enable') || isempty(cfg.stimbox.enable)
                    cfg.stimbox.enable = true;
                end
            case 'pulsepal'
                if ~isfield(cfg.pulsepal, 'enable') || isempty(cfg.pulsepal.enable)
                    cfg.pulsepal.enable = true;
                end
        end
    end

    if isnan(localGetNumericField(cfg.stimbox, {'start_frame','frame_start'}, NaN))
        if isfield(cfg, 'stim_start') && ~isempty(cfg.stim_start) && isnumeric(cfg.stim_start) && ~isnan(cfg.stim_start)
            cfg.stimbox.start_frame = cfg.stim_start;
        end
    end

    if isempty(localGetNumericField(cfg.stimbox, {'frame_duration','duration_frames'}, NaN)) || ...
            isnan(localGetNumericField(cfg.stimbox, {'frame_duration','duration_frames'}, NaN))
        if isfield(cfg, 'stim_duration') && ~isempty(cfg.stim_duration) && isnumeric(cfg.stim_duration) && ~isnan(cfg.stim_duration)
            cfg.stimbox.frame_duration = cfg.stim_duration;
        end
    end

    if isnan(localGetNumericField(cfg.pulsepal, {'start_frame','frame_start'}, NaN))
        if isfield(cfg, 'stim_start') && ~isempty(cfg.stim_start) && isnumeric(cfg.stim_start) && ~isnan(cfg.stim_start)
            cfg.pulsepal.start_frame = cfg.stim_start;
        end
    end

    if isfield(cfg.stimbox, 'd3_trig') && isnumeric(cfg.stimbox.d3_trig) && ~isnan(cfg.stimbox.d3_trig)
        cfg.stimbox.d3_enable = true;
    end
    if isfield(cfg.stimbox, 'd5_trig') && isnumeric(cfg.stimbox.d5_trig) && ~isnan(cfg.stimbox.d5_trig)
        cfg.stimbox.d5_enable = true;
    end
    if isfield(cfg.stimbox, 'd6_trig') && isnumeric(cfg.stimbox.d6_trig) && ~isnan(cfg.stimbox.d6_trig)
        cfg.stimbox.d6_enable = true;
    end

    if isempty(cfg.motor.start_mm)
        cfg.motor.start_mm = localGetNumericField(cfg.motor, {'start_pos_mm','absolute_start_mm'}, []);
    end
    if isempty(cfg.motor.end_mm)
        cfg.motor.end_mm = localGetNumericField(cfg.motor, {'end_pos_mm','absolute_end_mm'}, []);
    end
end

% =========================================================================
% Validation
% =========================================================================
function localValidateConfig(cfg)

    if ~ischar(cfg.xp_name) || isempty(cfg.xp_name)
        error('cfg.xp_name must be a non-empty char array.');
    end

    if ~isscalar(cfg.n_frames) || ~isnumeric(cfg.n_frames) || cfg.n_frames < 1
        error('cfg.n_frames must be a positive scalar.');
    end

    if ~isscalar(cfg.nblocksImage) || ~isnumeric(cfg.nblocksImage) || cfg.nblocksImage < 1
        error('cfg.nblocksImage must be a positive scalar.');
    end

    if ~isscalar(cfg.n_trials) || ~isnumeric(cfg.n_trials) || cfg.n_trials < 1
        error('cfg.n_trials must be a positive scalar.');
    end

    if ~isscalar(cfg.time_pause) || ~isnumeric(cfg.time_pause) || cfg.time_pause < 0
        error('cfg.time_pause must be a non-negative scalar.');
    end

    if cfg.stimbox.enable
        if ~ischar(cfg.stimbox.com) || isempty(cfg.stimbox.com)
            error('cfg.stimbox.com must be a non-empty char array.');
        end
        if ~isscalar(cfg.stimbox.baud) || ~isnumeric(cfg.stimbox.baud) || cfg.stimbox.baud <= 0
            error('cfg.stimbox.baud must be a positive scalar.');
        end
    end

    if cfg.pulsepal.enable
        if ~ischar(cfg.pulsepal.com) || isempty(cfg.pulsepal.com)
            error('cfg.pulsepal.com must be a non-empty char array.');
        end

        if ~isscalar(cfg.pulsepal.channel) || cfg.pulsepal.channel < 1 || cfg.pulsepal.channel > 4
            error('cfg.pulsepal.channel must be 1..4.');
        end

        if cfg.pulsepal.phase1_voltage < -10 || cfg.pulsepal.phase1_voltage > 10
            error('PulsePal phase1 voltage must be between -10 and 10 V.');
        end
        if cfg.pulsepal.phase2_voltage < -10 || cfg.pulsepal.phase2_voltage > 10
            error('PulsePal phase2 voltage must be between -10 and 10 V.');
        end
        if cfg.pulsepal.resting_voltage < -10 || cfg.pulsepal.resting_voltage > 10
            error('PulsePal resting voltage must be between -10 and 10 V.');
        end

        if cfg.pulsepal.phase1_duration_s < 0.0001
            error('PulsePal phase1 duration must be >= 0.0001 s.');
        end
        if cfg.pulsepal.interphase_interval_s < 0.0001
            error('PulsePal interphase interval must be >= 0.0001 s.');
        end
        if cfg.pulsepal.phase2_duration_s < 0.0001
            error('PulsePal phase2 duration must be >= 0.0001 s.');
        end
        if cfg.pulsepal.interpulse_interval_s < 0.0001
            error('PulsePal inter-pulse interval must be >= 0.0001 s.');
        end
        if cfg.pulsepal.burst_duration_s < 0
            error('PulsePal burst duration must be >= 0.');
        end
        if cfg.pulsepal.interburst_interval_s < 0
            error('PulsePal inter-burst interval must be >= 0.');
        end
        if cfg.pulsepal.train_delay_s < 0
            error('PulsePal train delay must be >= 0.');
        end
        if cfg.pulsepal.train_duration_s < 0.0001
            error('PulsePal train duration must be >= 0.0001 s.');
        end
    end

    if cfg.motor.enable
        if ~ischar(cfg.motor.com) || isempty(cfg.motor.com)
            error('cfg.motor.com must be a non-empty char array.');
        end

        if ~ischar(cfg.motor.mode) || isempty(cfg.motor.mode)
            error('cfg.motor.mode must be ''single'' or ''stepped''.');
        end

        if ~strcmpi(cfg.motor.mode, 'single') && ~strcmpi(cfg.motor.mode, 'stepped')
            error('cfg.motor.mode must be ''single'' or ''stepped''.');
        end

        if ~isscalar(cfg.motor.settle_pause_s) || ~isnumeric(cfg.motor.settle_pause_s) || cfg.motor.settle_pause_s < 0
            error('cfg.motor.settle_pause_s must be >= 0.');
        end

        if strcmpi(cfg.motor.mode, 'stepped')
            if ~isscalar(cfg.motor.step_mm) || ~isnumeric(cfg.motor.step_mm) || cfg.motor.step_mm <= 0
                error('cfg.motor.step_mm must be > 0 for stepped motor mode.');
            end

            if ~isscalar(cfg.motor.frames_per_position) || ~isnumeric(cfg.motor.frames_per_position) || cfg.motor.frames_per_position < 1
                error('cfg.motor.frames_per_position must be >= 1 for stepped motor mode.');
            end
        end
    end
end

% =========================================================================
% Explicit frame set builders
% =========================================================================
function framesOut = localBuildStimBoxFrameSets(stimboxCfg, nFrames)
    framesOut = struct();
    framesOut.d3_frames = [];
    framesOut.d5_frames = [];
    framesOut.d6_frames = [];

    if ~stimboxCfg.enable
        return;
    end

    sharedStart  = localGetNumericField(stimboxCfg, {'start_frame','frame_start'}, NaN);
    sharedRepeat = localGetLogicalField(stimboxCfg, {'repeat_enable','repeat'}, false);
    sharedEvery  = localGetNumericField(stimboxCfg, {'repeat_interval_frames','repeat_every_frames','repeat_after_frames'}, NaN);

    % IMPORTANT:
    % Use START FRAMES only, not full duration windows.
    % This matches the older working behavior much better.
    triggerFrames = localBuildStimBoxTriggerFrames(sharedStart, sharedRepeat, sharedEvery, nFrames);

    framesOut.d3_frames = localResolveStimLineFrames(stimboxCfg, 'd3', triggerFrames, nFrames);
    framesOut.d5_frames = localResolveStimLineFrames(stimboxCfg, 'd5', triggerFrames, nFrames);
    framesOut.d6_frames = localResolveStimLineFrames(stimboxCfg, 'd6', triggerFrames, nFrames);
end

function frames = localBuildStimBoxTriggerFrames(startFrame, repeatOn, repeatEvery, nFrames)
    frames = [];

    if isempty(startFrame) || ~isnumeric(startFrame) || isnan(startFrame)
        return;
    end

    startFrame = round(startFrame);
    if startFrame < 1 || startFrame > nFrames
        return;
    end

    if ~repeatOn || isempty(repeatEvery) || ~isnumeric(repeatEvery) || isnan(repeatEvery) || repeatEvery < 1
        frames = startFrame;
    else
        repeatEvery = max(1, round(repeatEvery));
        frames = startFrame:repeatEvery:nFrames;
    end

    frames = localCleanFrameVector(frames, nFrames);
end

function frames = localResolveStimLineFrames(stimboxCfg, lineName, triggerFrames, nFrames)

    frames = [];

    explicitField = [lineName '_frames'];
    enableField   = [lineName '_enable'];
    legacyField   = [lineName '_trig'];

    if isfield(stimboxCfg, explicitField)
        frames = localCleanFrameVector(stimboxCfg.(explicitField), nFrames);
        return;
    end

    lineEnabled = localGetLogicalField(stimboxCfg, {enableField}, false);

    if lineEnabled
        frames = triggerFrames;
        return;
    end

    if isfield(stimboxCfg, legacyField)
        legacyVal = stimboxCfg.(legacyField);
        if isnumeric(legacyVal) && ~isempty(legacyVal) && ~isnan(legacyVal)
            if isscalar(legacyVal) && legacyVal == -1
                frames = 1:nFrames;
            else
                frames = localCleanFrameVector(legacyVal, nFrames);
            end
        end
    end
end

function frames = localBuildPulsePalTriggerFrames(pulsepalCfg, nFrames)
    frames = [];

    if ~pulsepalCfg.enable
        return;
    end

    if isfield(pulsepalCfg, 'trigger_frames')
        frames = localCleanFrameVector(pulsepalCfg.trigger_frames, nFrames);
        return;
    end

    startFrame  = localGetNumericField(pulsepalCfg, {'start_frame','frame_start'}, NaN);
    repeatOn    = localGetLogicalField(pulsepalCfg, {'repeat_enable','repeat'}, false);
    repeatEvery = localGetNumericField(pulsepalCfg, {'repeat_interval_frames','repeat_every_frames','repeat_after_frames'}, NaN);

    if isempty(startFrame) || isnan(startFrame)
        return;
    end

    startFrame = round(startFrame);
    if startFrame < 1 || startFrame > nFrames
        return;
    end

    if ~repeatOn || isempty(repeatEvery) || isnan(repeatEvery) || repeatEvery < 1
        frames = startFrame;
    else
        repeatEvery = max(1, round(repeatEvery));
        frames = startFrame:repeatEvery:nFrames;
    end

    frames = localCleanFrameVector(frames, nFrames);
end

% =========================================================================
% Motor
% =========================================================================
function [connection, axis, homeMM] = localOpenMotor(comName)
    import zaber.motion.ascii.Connection;
    import zaber.motion.Units;

    connection = Connection.openSerialPort(comName);
    deviceList = connection.detectDevices();

    if isempty(deviceList)
        error('No Zaber devices detected on %s.', comName);
    end

    device = deviceList(1);
    axis = device.getAxis(1);
    homeMM = axis.getPosition(Units.LENGTH_MILLIMETRES);
end

function positionsAbsMM = localBuildMotorPositions(homeMM, motorCfg)
    if ~motorCfg.enable
        positionsAbsMM = NaN;
        return;
    end

    useAbsolute = ~isempty(motorCfg.start_mm) && isnumeric(motorCfg.start_mm) && ~isnan(motorCfg.start_mm);

    if useAbsolute
        startAbs = motorCfg.start_mm;

        if strcmpi(motorCfg.mode, 'single')
            positionsAbsMM = startAbs;
            return;
        end

        if ~isempty(motorCfg.end_mm) && isnumeric(motorCfg.end_mm) && ~isnan(motorCfg.end_mm)
            endAbs = motorCfg.end_mm;
        else
            endAbs = startAbs;
        end
    else
        startAbs = homeMM + motorCfg.start_offset_mm;

        if strcmpi(motorCfg.mode, 'single')
            positionsAbsMM = startAbs;
            return;
        end

        endAbs = homeMM + motorCfg.end_offset_mm;
    end

    stepMM = abs(motorCfg.step_mm);

    if abs(endAbs - startAbs) < eps
        positionsAbsMM = startAbs;
        return;
    end

    if endAbs < startAbs
        stepMM = -stepMM;
    end

    positionsAbsMM = startAbs:stepMM:endAbs;

    if isempty(positionsAbsMM)
        positionsAbsMM = [startAbs endAbs];
    else
        if abs(positionsAbsMM(end) - endAbs) > 1e-12
            positionsAbsMM = [positionsAbsMM endAbs];
        end
    end
end

function plan = localBuildMotorPlan(motorCfg, positionsAbsMM, nFrames)
    plan = struct();
    plan.frames = [];
    plan.targets_abs_mm = [];

    if ~motorCfg.enable
        return;
    end

    if isempty(positionsAbsMM) || all(isnan(positionsAbsMM))
        return;
    end

    cycleStart = localGetNumericField(motorCfg, {'frame_start','start_frame'}, 1);
    cycleDur   = localGetNumericField(motorCfg, {'frame_duration','duration_frames'}, nFrames);
    repeatOn   = localGetLogicalField(motorCfg, {'repeat_enable','repeat'}, false);
    repeatEvery = localGetNumericField(motorCfg, {'repeat_interval_frames','repeat_every_frames','repeat_after_frames'}, NaN);

    cycleStart = max(1, round(cycleStart));
    cycleDur   = max(1, round(cycleDur));

    if ~repeatOn || isempty(repeatEvery) || isnan(repeatEvery) || repeatEvery < 1
        cycleStarts = cycleStart;
    else
        repeatEvery = max(1, round(repeatEvery));
        cycleStarts = cycleStart:repeatEvery:nFrames;
    end

    nPos = numel(positionsAbsMM);

    for iC = 1:numel(cycleStarts)
        c0 = cycleStarts(iC);
        c1 = min(nFrames, c0 + cycleDur - 1);

        if strcmpi(motorCfg.mode, 'single')
            if c0 >= 1 && c0 <= nFrames
                plan.frames(end+1) = c0; %#ok<AGROW>
                plan.targets_abs_mm(end+1) = positionsAbsMM(1); %#ok<AGROW>
            end
            continue;
        end

        framesPer = max(1, round(motorCfg.frames_per_position));
        slotFrames = c0:framesPer:c1;

        if isempty(slotFrames)
            slotFrames = c0;
        end

        if motorCfg.periodic
            for k = 1:numel(slotFrames)
                idx = mod(k-1, nPos) + 1;
                plan.frames(end+1) = slotFrames(k); %#ok<AGROW>
                plan.targets_abs_mm(end+1) = positionsAbsMM(idx); %#ok<AGROW>
            end
        else
            nUse = min(numel(slotFrames), nPos);
            for k = 1:nUse
                plan.frames(end+1) = slotFrames(k); %#ok<AGROW>
                plan.targets_abs_mm(end+1) = positionsAbsMM(k); %#ok<AGROW>
            end
        end
    end

    [plan.frames, sortIdx] = sort(plan.frames);
    if ~isempty(sortIdx)
        plan.targets_abs_mm = plan.targets_abs_mm(sortIdx);
    end
end

function [actualPosMM, ok] = localMoveMotorBeforeStableScan(cfg, motorAxis, targetAbsMM, iMotor, nMotor)
    actualPosMM = NaN;
    ok = false;

    if isempty(motorAxis)
        error('Motor is enabled, but motorAxis is empty.');
    end

    if isempty(targetAbsMM) || ~isnumeric(targetAbsMM) || isnan(targetAbsMM)
        error('Invalid motor target position.');
    end

    localGuiLog(cfg, sprintf( ...
        'Motor move BEFORE acquisition: %d/%d -> abs %.3f mm', ...
        iMotor, nMotor, targetAbsMM));

    motorAxis.moveAbsolute(targetAbsMM, zaber.motion.Units.LENGTH_MILLIMETRES);

    if isfield(cfg, 'motor') && isfield(cfg.motor, 'settle_pause_s') && ...
            isnumeric(cfg.motor.settle_pause_s) && cfg.motor.settle_pause_s > 0

        localGuiLog(cfg, sprintf('Motor settling pause: %.3f s', cfg.motor.settle_pause_s));
        pause(cfg.motor.settle_pause_s);
    end

    try
        actualPosMM = motorAxis.getPosition(zaber.motion.Units.LENGTH_MILLIMETRES);
    catch
        actualPosMM = targetAbsMM;
    end

    localGuiLog(cfg, sprintf( ...
        'Motor stable BEFORE acquisition: requested %.3f mm | actual %.3f mm', ...
        targetAbsMM, actualPosMM));

    ok = true;
end

% =========================================================================
% StimBox serial open
% =========================================================================
function port = localOpenStimBoxPort(comName, baudRate)
    port = [];

    hasSerialPort = (exist('serialport', 'file') == 2) || (exist('serialport', 'class') == 8);

    if hasSerialPort
        port = serialport(comName, baudRate);
        try
            flush(port);
        catch
        end
    else
        try
            oldObj = instrfind('Port', comName);
            if ~isempty(oldObj)
                fclose(oldObj);
                delete(oldObj);
            end
        catch
        end

        port = serial(comName);
        port.BaudRate = baudRate;
        fopen(port);
    end
end

% =========================================================================
% Save names and journal text
% =========================================================================
function [nameFile, nameShort] = localMakeSaveName(FS, cfg, sessionTag, motorPositionsAbsMM, motorHomeMM, iTrial) %#ok<INUSD>
    % Save path:
    %   Data\<save_owner>\<xp_name>\<xp_name>_scanN[_StimBox][_ElectricalStim][_Motor].mat
    %
    % IMPORTANT:
    % scan number is global within the experiment folder, independent of suffix.

if ~isfield(cfg, 'save_owner') || isempty(cfg.save_owner)
    cfg.save_owner = 'Soner';
end

% Default experiment folder
baseFolder = fullfile(pwd, 'Data', cfg.save_owner, cfg.xp_name);

if isfield(cfg, 'output_base_folder') && ~isempty(cfg.output_base_folder)
    baseFolder = cfg.output_base_folder;
end

if ~exist(baseFolder, 'dir')
    mkdir(baseFolder);
end

% In split motor mode, save inside the prepared session subfolder.
saveFolder = baseFolder;

useSplitMotorFolder = false;
try
    useSplitMotorFolder = ...
        isfield(cfg, 'motor') && isstruct(cfg.motor) && ...
        isfield(cfg.motor, 'enable') && logical(cfg.motor.enable) && ...
        isfield(cfg.motor, 'acquisition_mode') && ...
        strcmpi(cfg.motor.acquisition_mode, 'split') && ...
        isfield(cfg, 'output_session_folder') && ...
        ~isempty(cfg.output_session_folder);
catch
    useSplitMotorFolder = false;
end

if useSplitMotorFolder
    saveFolder = cfg.output_session_folder;
end

if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

deviceSuffix = localBuildDeviceSuffix(cfg);

% Scan index is counted inside the folder where files are saved.
scanIdx = localGetNextScanIndex(saveFolder, cfg.xp_name);

    if isempty(deviceSuffix)
        nameShort = sprintf('%s_scan%d.mat', cfg.xp_name, scanIdx);
    else
        nameShort = sprintf('%s_scan%d%s.mat', cfg.xp_name, scanIdx, deviceSuffix);
    end

nameFile = fullfile(saveFolder, nameShort);
end
function [nameFileOut, nameShortOut] = localMakeFileNameUnique(nameFileIn)
    [folderPath, baseName, ext] = fileparts(nameFileIn);

    nameFileOut = nameFileIn;
    nameShortOut = [baseName ext];

    if ~exist(nameFileOut, 'file')
        return;
    end

    for k = 1:999
        candidateShort = sprintf('%s_dup%03d%s', baseName, k, ext);
        candidateFull = fullfile(folderPath, candidateShort);

        if ~exist(candidateFull, 'file')
            nameFileOut = candidateFull;
            nameShortOut = candidateShort;
            return;
        end
    end

    error('Could not create unique filename for %s.', nameFileIn);
end


function localReliableSaveMat(nameFile, I, md, cfg)
    [saveFolder, saveBase, saveExt] = fileparts(nameFile);

    if ~exist(saveFolder, 'dir')
        mkdir(saveFolder);
    end

    lastErr = '';

    for attempt = 1:3

        tmpFile = fullfile(saveFolder, sprintf('%s__tmp_%s_%06d%s', ...
            saveBase, datestr(now, 'HHMMSS'), round(rand * 1e6), saveExt));

        try
            if exist(tmpFile, 'file')
                delete(tmpFile);
            end

            save(tmpFile, 'I', 'md', '-v7.3');

            if ~exist(tmpFile, 'file')
                error('Temporary MAT file was not created.');
            end

            d = dir(tmpFile);
            if isempty(d) || d.bytes <= 0
                error('Temporary MAT file is empty.');
            end

            varsInTmp = whos('-file', tmpFile);
            varNames = {varsInTmp.name};

            if ~ismember('I', varNames)
                error('Temporary MAT file created, but variable I is missing.');
            end

            if ~ismember('md', varNames)
                error('Temporary MAT file created, but variable md is missing.');
            end

            [ok, msg] = movefile(tmpFile, nameFile, 'f');
            if ~ok
                error('Could not move temporary MAT file into final location: %s', msg);
            end

            if ~exist(nameFile, 'file')
                error('Final MAT file missing after movefile.');
            end

            varsFinal = whos('-file', nameFile);
            finalNames = {varsFinal.name};

            if ~ismember('I', finalNames) || ~ismember('md', finalNames)
                error('Final MAT file verification failed: I or md missing.');
            end

            localGuiLog(cfg, sprintf('Reliable save verified: %s', nameFile));
            return;

        catch ME
            lastErr = ME.message;

            try
                if exist(tmpFile, 'file')
                    delete(tmpFile);
                end
            catch
            end

            localGuiLog(cfg, sprintf('Save attempt %d failed: %s', attempt, lastErr));
            pause(0.5);
        end
    end

    error('Reliable save failed after 3 attempts: %s', lastErr);
end

function localFastSaveMat(nameFile, I, md, cfg)
    % Fast save for split-motor tiny files.
    % Uses -v7 first because it is much faster than -v7.3 for small files.
    % Falls back to -v7.3 if needed.

    [saveFolder, ~, ~] = fileparts(nameFile);

    if ~exist(saveFolder, 'dir')
        mkdir(saveFolder);
    end

    try
        save(nameFile, 'I', 'md', '-v7');
    catch ME1
        try
            localGuiLog(cfg, sprintf('Fast -v7 save failed, trying -v7.3: %s', ME1.message));
            save(nameFile, 'I', 'md', '-v7.3');
        catch ME2
            localGuiLog(cfg, sprintf('Fast save failed, using reliable save: %s', ME2.message));
            localReliableSaveMat(nameFile, I, md, cfg);
        end
    end
end

function [nameFileOut, nameShortOut] = localAppendMotorPositionToSaveName(nameFileIn, cfg, absPosMM, homeMM, iMotor, iTimeIndex)

    if nargin < 6 || isempty(iTimeIndex) || isnan(iTimeIndex)
        iTimeIndex = 1;
    end

    [folderPath, baseName, ext] = fileparts(nameFileIn);

    motorMode = localGetMotorAcqMode(cfg);

    switch lower(motorMode)

        case 'split'
            % IMPORTANT for motor.m:
            % It can parse:
            %   slice001_t001
            %   slice002_t001
            %   slice001_t002
            %
            % Keep this simple and analysis-friendly.
            tag = sprintf('M_split_slice%03d_t%03d', ...
                round(iMotor), round(iTimeIndex));

        case 'continuous'
            % One long MAT file containing all motor positions.
            tag = 'M_continuousmotor';

        otherwise
            tag = 'M_motor';
    end

    nameShortOut = [baseName '_' tag ext];
    nameFileOut = fullfile(folderPath, nameShortOut);
end
function [nameFileOut, nameShortOut] = localAppendSplitSliceToSaveName(nameFileIn, iTrial, iSlice, nSlices, absPosMM, homeMM) %#ok<INUSD>
    [folderPath, baseName, ext] = fileparts(nameFileIn);

    nameShortOut = sprintf('%s_T%03d_Slice%03dof%03d%s', ...
        baseName, round(iTrial), round(iSlice), round(nSlices), ext);

    nameFileOut = fullfile(folderPath, nameShortOut);
end

function md = localAddMotorMetadata(md, cfg, motorHomeMM, requestedMotorAbsMM, actualMotorAbsMM, ...
    iMotor, nMotor, iTimeIndex, nTimeTotal, globalFrameStart, globalFrameEnd, ...
    continuousMotorPlan)

    if nargin < 12
        continuousMotorPlan = struct('frames', [], 'targets_abs_mm', []);
    end

    if ~isstruct(md)
        tmp = md;
        md = struct();
        md.original_md = tmp;
    end

    motorMode = localGetMotorAcqMode(cfg);

    try
        md.motor_enabled = logical(cfg.motor.enable);
        md.motor_acquisition_mode = motorMode;
        md.motor_moves_during_acquisition = strcmpi(motorMode, 'continuous');
        md.motor_stable_acquisition = strcmpi(motorMode, 'split');

        md.sliceIndex = iMotor;
        md.timeIndex = iTimeIndex;
        md.globalFrameStart = globalFrameStart;
        md.globalFrameEnd = globalFrameEnd;

        md.motor_index = iMotor;
        md.motor_n_positions = nMotor;
        md.motor_time_index = iTimeIndex;
        md.motor_n_time_indices = nTimeTotal;

        md.motor_requested_abs_mm = requestedMotorAbsMM;
        md.motor_actual_abs_mm = actualMotorAbsMM;
        md.motor_home_abs_mm = motorHomeMM;
        md.motor_requested_rel_mm = requestedMotorAbsMM - motorHomeMM;
        md.motor_actual_rel_mm = actualMotorAbsMM - motorHomeMM;
        md.motor_settle_pause_s = cfg.motor.settle_pause_s;

        md.motor_frames_per_slice = cfg.motor.frames_per_position;
        md.motor_total_target_frames = cfg.n_frames;

        motorMeta = struct();
        motorMeta.acquisitionMode = motorMode;
        motorMeta.sliceIndex = iMotor;
        motorMeta.timeIndex = iTimeIndex;
        motorMeta.globalFrameStart = globalFrameStart;
        motorMeta.globalFrameEnd = globalFrameEnd;
        motorMeta.nMotorPositions = nMotor;
        motorMeta.nTimeIndices = nTimeTotal;
        motorMeta.framesPerSlice = cfg.motor.frames_per_position;
        motorMeta.totalTargetFrames = cfg.n_frames;
        motorMeta.requestedAbsMM = requestedMotorAbsMM;
        motorMeta.actualAbsMM = actualMotorAbsMM;
        motorMeta.homeAbsMM = motorHomeMM;
        motorMeta.movesDuringAcquisition = strcmpi(motorMode, 'continuous');
        motorMeta.stableDuringAcquisition = strcmpi(motorMode, 'split');

        if strcmpi(motorMode, 'continuous')
            motorMeta.continuousMoveFrames = continuousMotorPlan.frames;
            motorMeta.continuousMoveTargetsAbsMM = continuousMotorPlan.targets_abs_mm;
            motorMeta.reconstructionHint = ...
                'Continuous mode: use one long I movie with motorFramesPerSlice from metadata.';
        else
            motorMeta.reconstructionHint = ...
                'Split mode: group files by sliceIndex and timeIndex or by slice###_t### filename.';
        end

        md.motorMeta = motorMeta;
    catch
    end
end

function [nameFileOut, nameShortOut] = localAppendContinuousMotorToSaveName(nameFileIn, nSlices, framesPerSlice, startAbsMM, endAbsMM, homeMM) %#ok<INUSD>
    [folderPath, baseName, ext] = fileparts(nameFileIn);

    nameShortOut = sprintf('%s_ContinuousMotor_Slices%03d%s', ...
        baseName, round(nSlices), ext);

    nameFileOut = fullfile(folderPath, nameShortOut);
end

function suffix = localBuildDeviceSuffix(cfg)
    parts = {};

    if isfield(cfg, 'stimbox') && isstruct(cfg.stimbox) && isfield(cfg.stimbox, 'enable') && logical(cfg.stimbox.enable)
        parts{end+1} = 'SB'; %#ok<AGROW>
    end

    if isfield(cfg, 'pulsepal') && isstruct(cfg.pulsepal) && isfield(cfg.pulsepal, 'enable') && logical(cfg.pulsepal.enable)
        parts{end+1} = 'ES'; %#ok<AGROW>
    end

% Do not add generic _M here.
% Motor mode is added later as:
%   M_continuousmotor
%   M_split_slice001_t001

    if isempty(parts)
        suffix = '';
    else
        suffix = ['_' strjoin(parts, '_')];
    end
end

function scanIdx = localGetNextScanIndex(folderPath, expName)
    % IMPORTANT:
    % Use one common scan counter across ALL scan files in this experiment folder,
    % regardless of device suffix such as _Motor, _StimBox, _SB_M, etc.

    d = dir(fullfile(folderPath, [expName '_scan*.mat']));
    scanNums = [];

    expr = ['^' regexptranslate('escape', expName) '_scan(\d+)(?:_.*)?\.mat$'];

    for i = 1:numel(d)
        thisName = d(i).name;
        tok = regexp(thisName, expr, 'tokens', 'once');

        if ~isempty(tok)
            n = str2double(tok{1});
            if ~isnan(n)
                scanNums(end+1) = n; %#ok<AGROW>
            end
        end
    end

    if isempty(scanNums)
        scanIdx = 1;
    else
        scanIdx = max(scanNums) + 1;
    end
end

function txt = localMakeJournalText(nameShort, cfg, motorPositionsAbsMM, motorHomeMM, iTrial)
    motorTag = localMotorTag(cfg, motorPositionsAbsMM, motorHomeMM);
    deviceSuffix = localBuildDeviceSuffix(cfg);

    txt = sprintf('* %s (Trial=%d, Frames=%d, Devices=%s, MotorMode=%s, MotorTag=%s, StimBox=%d, PulsePal=%d, Motor=%d)', ...
        nameShort, ...
        iTrial, ...
        cfg.n_frames, ...
        deviceSuffix, ...
        cfg.motor.mode, ...
        motorTag, ...
        logical(cfg.stimbox.enable), ...
        logical(cfg.pulsepal.enable), ...
        logical(cfg.motor.enable));
end


function localWriteScanInfoText(nameFile, cfg, iTrial, md)
    [folderPath, baseName, ~] = fileparts(nameFile);
    txtFile = fullfile(folderPath, [baseName '.txt']);

    fid = fopen(txtFile, 'w');
    if fid < 0
        warning('Could not create scan info txt file: %s', txtFile);
        return;
    end

    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    trSec = localCalcTRSec(cfg.nblocksImage);

    fprintf(fid, 'Scan information\n');
    fprintf(fid, '================\n\n');

    fprintf(fid, 'Saved on: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'MAT file: %s\n', nameFile);
    fprintf(fid, 'Trial number: %d\n\n', iTrial);

    fprintf(fid, '[Acquisition]\n');
    fprintf(fid, 'Save owner: %s\n', localSafeText(localGetFieldIfExists(cfg, 'save_owner', 'NA')));
    fprintf(fid, 'Experiment name: %s\n', localSafeText(localGetFieldIfExists(cfg, 'xp_name', 'NA')));
    if isfield(cfg, 'output_session_name') && ~isempty(cfg.output_session_name)
    fprintf(fid, 'Output session folder: %s\n', localSafeText(cfg.output_session_name));
end

if isfield(cfg, 'output_session_folder') && ~isempty(cfg.output_session_folder)
    fprintf(fid, 'Output session path: %s\n', localSafeText(cfg.output_session_folder));
end
    fprintf(fid, 'Frames per trial: %s\n', localNumToStr(cfg.n_frames));
    fprintf(fid, 'Number of trials: %s\n', localNumToStr(cfg.n_trials));
    fprintf(fid, 'nblocksImage: %s\n', localNumToStr(cfg.nblocksImage));
    fprintf(fid, 'TR (s): %s\n', localNumToStr(trSec));
    fprintf(fid, 'Frame rate (Hz): %s\n', localNumToStr(1 / trSec));
    fprintf(fid, 'Pause between trials (s): %s\n', localNumToStr(cfg.time_pause));
if nargin >= 4 && isstruct(md)
    fprintf(fid, '\n[Timing QC]\n');

    if isfield(md, 'requested_dt_s')
        fprintf(fid, 'Requested dt/TR (s): %s\n', localNumToStr(md.requested_dt_s));
    end
    if isfield(md, 'actual_mean_dt_s')
        fprintf(fid, 'Actual mean dt/TR (s): %s\n', localNumToStr(md.actual_mean_dt_s));
    end
    if isfield(md, 'actual_acq_elapsed_s')
        fprintf(fid, 'Actual acquisition elapsed time (s): %s\n', localNumToStr(md.actual_acq_elapsed_s));
    end
    if isfield(md, 'actual_frames_saved')
        fprintf(fid, 'Actual frames saved: %s\n', localNumToStr(md.actual_frames_saved));
    end
    if isfield(md, 'actual_dt_deviation_percent')
        fprintf(fid, 'Actual dt deviation (percent): %s\n', localNumToStr(md.actual_dt_deviation_percent));
    end
end
    fprintf(fid, '\n[StimBox]\n');
    fprintf(fid, 'Enabled: %s\n', localOnOff(cfg.stimbox.enable));
    fprintf(fid, 'COM: %s\n', localSafeText(cfg.stimbox.com));
    fprintf(fid, 'Baud: %s\n', localNumToStr(cfg.stimbox.baud));
    fprintf(fid, 'Frame start: %s\n', localNumToStr(cfg.stimbox.start_frame));
    fprintf(fid, 'Frames active: %s\n', localNumToStr(cfg.stimbox.frame_duration));
    fprintf(fid, 'Repeat enabled: %s\n', localOnOff(cfg.stimbox.repeat_enable));
    fprintf(fid, 'Repeat every frames: %s\n', localNumToStr(cfg.stimbox.repeat_interval_frames));
    fprintf(fid, 'D3 enabled: %s\n', localOnOff(cfg.stimbox.d3_enable));
    fprintf(fid, 'D5 enabled: %s\n', localOnOff(cfg.stimbox.d5_enable));
    fprintf(fid, 'D6 enabled: %s\n', localOnOff(cfg.stimbox.d6_enable));
    fprintf(fid, 'Verbose log: %s\n', localOnOff(cfg.stimbox.verbose));

    fprintf(fid, '\n[Electrical Stimulation / PulsePal]\n');
    fprintf(fid, 'Enabled: %s\n', localOnOff(cfg.pulsepal.enable));
    fprintf(fid, 'COM: %s\n', localSafeText(cfg.pulsepal.com));
    fprintf(fid, 'Channel: %s\n', localNumToStr(cfg.pulsepal.channel));
    fprintf(fid, 'Frame start: %s\n', localNumToStr(cfg.pulsepal.start_frame));
    fprintf(fid, 'Frames active: %s\n', localNumToStr(cfg.pulsepal.frame_duration));
    fprintf(fid, 'Repeat enabled: %s\n', localOnOff(cfg.pulsepal.repeat_enable));
    fprintf(fid, 'Repeat every frames: %s\n', localNumToStr(cfg.pulsepal.repeat_interval_frames));
    fprintf(fid, 'Biphasic: %s\n', localOnOff(cfg.pulsepal.is_biphasic));
    fprintf(fid, 'Phase1 voltage (V): %s\n', localNumToStr(cfg.pulsepal.phase1_voltage));
    fprintf(fid, 'Phase1 duration (s): %s\n', localNumToStr(cfg.pulsepal.phase1_duration_s));
    fprintf(fid, 'Interphase interval (s): %s\n', localNumToStr(cfg.pulsepal.interphase_interval_s));
    fprintf(fid, 'Phase2 voltage (V): %s\n', localNumToStr(cfg.pulsepal.phase2_voltage));
    fprintf(fid, 'Phase2 duration (s): %s\n', localNumToStr(cfg.pulsepal.phase2_duration_s));
    fprintf(fid, 'Resting voltage (V): %s\n', localNumToStr(cfg.pulsepal.resting_voltage));
    fprintf(fid, 'Interpulse interval (s): %s\n', localNumToStr(cfg.pulsepal.interpulse_interval_s));
    fprintf(fid, 'Burst duration (s): %s\n', localNumToStr(cfg.pulsepal.burst_duration_s));
    fprintf(fid, 'Interburst interval (s): %s\n', localNumToStr(cfg.pulsepal.interburst_interval_s));
    fprintf(fid, 'Train delay (s): %s\n', localNumToStr(cfg.pulsepal.train_delay_s));
    fprintf(fid, 'Train duration (s): %s\n', localNumToStr(cfg.pulsepal.train_duration_s));

       fprintf(fid, '\n[Step Motor]\n');
    fprintf(fid, 'Enabled: %s\n', localOnOff(cfg.motor.enable));
    fprintf(fid, 'COM: %s\n', localSafeText(cfg.motor.com));

    if isfield(cfg.motor, 'acquisition_mode')
        fprintf(fid, 'Acquisition mode: %s\n', localSafeText(cfg.motor.acquisition_mode));
    else
        fprintf(fid, 'Acquisition mode: NA\n');
    end

    fprintf(fid, 'Mode: %s\n', localSafeText(cfg.motor.mode));
    fprintf(fid, 'Active from frame: %s\n', localNumToStr(cfg.motor.frame_start));
    fprintf(fid, 'Active for frames: %s\n', localNumToStr(cfg.motor.frame_duration));
    fprintf(fid, 'Repeat enabled: %s\n', localOnOff(cfg.motor.repeat_enable));
    fprintf(fid, 'Repeat every frames: %s\n', localNumToStr(cfg.motor.repeat_interval_frames));
    fprintf(fid, 'Start position (mm): %s\n', localNumToStr(cfg.motor.start_mm));
    fprintf(fid, 'End position (mm): %s\n', localNumToStr(cfg.motor.end_mm));
    fprintf(fid, 'Step size (mm): %s\n', localNumToStr(cfg.motor.step_mm));
    fprintf(fid, 'Frames per position: %s\n', localNumToStr(cfg.motor.frames_per_position));
    fprintf(fid, 'Periodic: %s\n', localOnOff(cfg.motor.periodic));
    fprintf(fid, 'Return home: %s\n', localOnOff(cfg.motor.return_to_zero));
    fprintf(fid, 'Settle pause (s): %s\n', localNumToStr(cfg.motor.settle_pause_s));
if nargin >= 4 && isstruct(md)
    fprintf(fid, '\n[Motor Reconstruction Metadata]\n');

    if isfield(md, 'motor_time_index')
        fprintf(fid, 'Motor time index: %s\n', localNumToStr(md.motor_time_index));
    end
    if isfield(md, 'motor_slice_index')
        fprintf(fid, 'Motor slice index: %s\n', localNumToStr(md.motor_slice_index));
    end
    if isfield(md, 'motor_slice_count')
        fprintf(fid, 'Motor slice count: %s\n', localNumToStr(md.motor_slice_count));
    end
    if isfield(md, 'requested_frames_this_file')
        fprintf(fid, 'Requested frames this file: %s\n', localNumToStr(md.requested_frames_this_file));
    end
    if isfield(md, 'motor_rebuild_hint')
        fprintf(fid, 'Rebuild hint: %s\n', localSafeText(md.motor_rebuild_hint));
    end
end
   fprintf(fid, '\n[User Journal Note]\n');
userNote = localGetFieldIfExists(cfg, 'journal_note', '');

if isempty(userNote)
    fprintf(fid, 'NA\n');
else
    userNote = localNormalizeJournalNote(userNote);

    if isempty(strtrim(userNote))
        fprintf(fid, 'NA\n');
    else
        fprintf(fid, '%s\n', userNote);
    end
end

    localGuiLog(cfg, sprintf('Saved scan info txt: %s', txtFile));
end

function localWriteSplitSessionSummaryText(cfg, splitSessionRows, lastNameFile, lastTrial, lastMd)

    if isfield(cfg, 'output_session_folder') && ~isempty(cfg.output_session_folder)
        folderPath = cfg.output_session_folder;
    else
        folderPath = fileparts(lastNameFile);
    end

    if isfield(cfg, 'output_session_name') && ~isempty(cfg.output_session_name)
        summaryName = [cfg.output_session_name '_summary.txt'];
    else
        summaryName = 'SplitMotor_session_summary.txt';
    end

    txtFile = fullfile(folderPath, summaryName);

    fid = fopen(txtFile, 'w');
    if fid < 0
        warning('Could not create split session summary TXT: %s', txtFile);
        return;
    end

    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    trSec = localCalcTRSec(cfg.nblocksImage);

    fprintf(fid, 'Split motor session summary\n');
    fprintf(fid, '===========================\n\n');

    fprintf(fid, 'Saved on: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Output folder: %s\n', folderPath);
    fprintf(fid, 'Experiment name: %s\n', localSafeText(cfg.xp_name));

    if isfield(cfg, 'output_session_name') && ~isempty(cfg.output_session_name)
        fprintf(fid, 'Output session: %s\n', localSafeText(cfg.output_session_name));
    end

    fprintf(fid, '\n[Acquisition]\n');
    fprintf(fid, 'Frames per trial total: %s\n', localNumToStr(cfg.n_frames));
    fprintf(fid, 'Number of trials: %s\n', localNumToStr(cfg.n_trials));
    fprintf(fid, 'nblocksImage: %s\n', localNumToStr(cfg.nblocksImage));
    fprintf(fid, 'Requested TR (s): %s\n', localNumToStr(trSec));
    fprintf(fid, 'Requested frame rate (Hz): %s\n', localNumToStr(1 / trSec));

    fprintf(fid, '\n[Step Motor]\n');
    fprintf(fid, 'Enabled: %s\n', localOnOff(cfg.motor.enable));
    fprintf(fid, 'COM: %s\n', localSafeText(cfg.motor.com));
    fprintf(fid, 'Acquisition mode: %s\n', localSafeText(cfg.motor.acquisition_mode));
    fprintf(fid, 'Mode: %s\n', localSafeText(cfg.motor.mode));
    fprintf(fid, 'Start position (mm): %s\n', localNumToStr(cfg.motor.start_mm));
    fprintf(fid, 'End position (mm): %s\n', localNumToStr(cfg.motor.end_mm));
    fprintf(fid, 'Step size (mm): %s\n', localNumToStr(cfg.motor.step_mm));
    fprintf(fid, 'Frames per position/slice file: %s\n', localNumToStr(cfg.motor.frames_per_position));
    fprintf(fid, 'Periodic: %s\n', localOnOff(cfg.motor.periodic));
    fprintf(fid, 'Settle pause (s): %s\n', localNumToStr(cfg.motor.settle_pause_s));

    if nargin >= 5 && isstruct(lastMd)
        fprintf(fid, '\n[Last file timing QC]\n');

        if isfield(lastMd, 'requested_dt_s')
            fprintf(fid, 'Requested dt/TR (s): %s\n', localNumToStr(lastMd.requested_dt_s));
        end
        if isfield(lastMd, 'actual_mean_dt_s')
            fprintf(fid, 'Actual mean dt/TR (s): %s\n', localNumToStr(lastMd.actual_mean_dt_s));
        end
        if isfield(lastMd, 'actual_acq_elapsed_s')
            fprintf(fid, 'Actual acquisition elapsed time (s): %s\n', localNumToStr(lastMd.actual_acq_elapsed_s));
        end
        if isfield(lastMd, 'actual_frames_saved')
            fprintf(fid, 'Actual frames saved: %s\n', localNumToStr(lastMd.actual_frames_saved));
        end
        if isfield(lastMd, 'actual_dt_deviation_percent')
            fprintf(fid, 'Actual dt deviation percent: %s\n', localNumToStr(lastMd.actual_dt_deviation_percent));
        end
    end

    fprintf(fid, '\n[Split files]\n');
    fprintf(fid, 'Number of MAT files: %d\n', numel(splitSessionRows));
    fprintf(fid, 'Last trial: %s\n\n', localNumToStr(lastTrial));

    for k = 1:numel(splitSessionRows)
        fprintf(fid, '%s\n', splitSessionRows{k});
    end

    fprintf(fid, '\n[User Journal Note]\n');
    userNote = localGetFieldIfExists(cfg, 'journal_note', '');

    if isempty(userNote)
        fprintf(fid, 'NA\n');
    else
        userNote = localNormalizeJournalNote(userNote);
        if isempty(strtrim(userNote))
            fprintf(fid, 'NA\n');
        else
            fprintf(fid, '%s\n', userNote);
        end
    end

    localGuiLog(cfg, sprintf('Saved final split session summary TXT: %s', txtFile));
end


function s = localMotorTag(cfg, motorPositionsAbsMM, motorHomeMM)
    if ~cfg.motor.enable
        s = 'MOTOROFF';
        return;
    end

    if strcmpi(cfg.motor.mode, 'single')
        if isempty(motorPositionsAbsMM) || isnan(motorPositionsAbsMM(1))
            s = 'PNA';
        else
            relPosMM = motorPositionsAbsMM(1) - motorHomeMM;
            s = sprintf('P%0.3f', relPosMM);
            s = strrep(s, '-', 'm');
            s = strrep(s, '.', 'p');
        end
    else
        s = 'STEPPED';
    end
end

% =========================================================================
% Summary printing
% =========================================================================
function localPrintSummary(cfg, motorHomeMM, motorPositionsAbsMM, stimboxFrames, pulsepalTriggerFrames, motorPlan)
    trSec = localCalcTRSec(cfg.nblocksImage);
    fps = 1 / trSec;

    disp(' ');
    disp('############################################################');
    disp('Get ready! The fUS acquisition will start shortly.');
    fprintf('- Experiment name: %s\n', cfg.xp_name);
    fprintf('- Frames per trial: %d\n', cfg.n_frames);
    fprintf('- Number of trials: %d\n', cfg.n_trials);
    fprintf('- nblocksImage: %d\n', cfg.nblocksImage);
    fprintf('- TR (2D probe assumption): %.3f s\n', trSec);
    fprintf('- Frame rate: %.3f fps\n', fps);

    fprintf('- StimBox enabled: %d\n', logical(cfg.stimbox.enable));
    if cfg.stimbox.enable
        fprintf('- StimBox COM: %s\n', cfg.stimbox.com);
        fprintf('- StimBox D3 frames: %d\n', numel(stimboxFrames.d3_frames));
        fprintf('- StimBox D5 frames: %d\n', numel(stimboxFrames.d5_frames));
        fprintf('- StimBox D6 frames: %d\n', numel(stimboxFrames.d6_frames));
    end

    fprintf('- PulsePal enabled: %d\n', logical(cfg.pulsepal.enable));
    if cfg.pulsepal.enable
        fprintf('- PulsePal COM: %s\n', cfg.pulsepal.com);
        fprintf('- PulsePal channel: %d\n', cfg.pulsepal.channel);
        fprintf('- PulsePal trigger count: %d\n', numel(pulsepalTriggerFrames));
        fprintf('- Phase1Voltage: %g V\n', cfg.pulsepal.phase1_voltage);
        fprintf('- Phase1Duration: %g s\n', cfg.pulsepal.phase1_duration_s);
        fprintf('- InterPulseInterval: %g s\n', cfg.pulsepal.interpulse_interval_s);
        fprintf('- PulseTrainDuration: %g s\n', cfg.pulsepal.train_duration_s);
        fprintf('- RestingVoltage: %g V\n', cfg.pulsepal.resting_voltage);
        fprintf('- Biphasic: %d\n', logical(cfg.pulsepal.is_biphasic));
    end

    fprintf('- Motor enabled: %d\n', logical(cfg.motor.enable));
    if cfg.motor.enable
        fprintf('- Motor COM: %s\n', cfg.motor.com);
        fprintf('- Motor mode: %s\n', cfg.motor.mode);
        fprintf('- Motor home position: %.3f mm\n', motorHomeMM);

        if ~isempty(cfg.motor.start_mm) && isnumeric(cfg.motor.start_mm) && ~isnan(cfg.motor.start_mm)
            fprintf('- Motor absolute start: %.3f mm\n', cfg.motor.start_mm);
            if ~isempty(cfg.motor.end_mm) && isnumeric(cfg.motor.end_mm) && ~isnan(cfg.motor.end_mm)
                fprintf('- Motor absolute end: %.3f mm\n', cfg.motor.end_mm);
            end
        else
            fprintf('- Motor start offset: %.3f mm\n', cfg.motor.start_offset_mm);
            fprintf('- Motor end offset: %.3f mm\n', cfg.motor.end_offset_mm);
        end

        if strcmpi(cfg.motor.mode, 'stepped')
            fprintf('- Step size: %.3f mm\n', cfg.motor.step_mm);
            fprintf('- Frames per position: %d\n', round(cfg.motor.frames_per_position));
            fprintf('- Periodic within cycle: %d\n', logical(cfg.motor.periodic));
        end

        if ~isempty(motorPositionsAbsMM) && all(~isnan(motorPositionsAbsMM))
            fprintf('- Configured motor positions: %d\n', numel(motorPositionsAbsMM));
        end

        fprintf('- Used motor moves per trial: %d\n', numel(motorPlan.frames));
    end

    fprintf('- Pause between trials: %.3f s\n', cfg.time_pause);
    disp('############################################################');
    disp(' ');
end

function trSec = localCalcTRSec(nblocksImage)
    trSec = nblocksImage * 0.02;
end

function localSafePause(t)
    if ~isempty(t) && isnumeric(t) && isfinite(t) && t > 0
        pause(t);
    end
end

function n = localGetAcquiredFrameCount(I, fallbackN)
    n = fallbackN;

    try
        sz = size(I);
        if numel(sz) >= 3
            n = sz(end);
        end

        if isempty(n) || ~isnumeric(n) || isnan(n) || n < 1
            n = fallbackN;
        end
    catch
        n = fallbackN;
    end
end

% =========================================================================
% GUI bridge
% =========================================================================
function tf = localStopRequested(cfg)
    tf = false;
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'stopRequestedFcn')
        try
            tf = logical(cfg.gui.stopRequestedFcn());
        catch
            tf = false;
        end
    end
end

function localGuiStatus(cfg, msg, state)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'statusFcn')
        try
            cfg.gui.statusFcn(msg, state);
        catch
        end
    end
end

function localGuiLog(cfg, msg)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'logFcn')
        try
            cfg.gui.logFcn(msg);
        catch
        end
    end
end

function localGuiFrame(cfg, frameIdx)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'frameFcn')
        try
            cfg.gui.frameFcn(frameIdx);
        catch
        end
    end
end

function localGuiTrial(cfg, iTrial, nTrials)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'trialFcn')
        try
            cfg.gui.trialFcn(iTrial, nTrials);
        catch
        end
    end
end

function localGuiMotor(cfg, moveCount, total, absPosMM, frameIdx)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'motorStepFcn')
        try
            cfg.gui.motorStepFcn(moveCount, total, absPosMM, frameIdx);
        catch
        end
    end
end




function localOpenPulsePalRobust(comName)
    % Force-close any stale MATLAB PulsePal session first
    localClosePulsePalRobust();
    localKillCOMPortRobust(comName);
    pause(0.30);

    lastErr = '';

    for k = 1:3
        try
            PulsePal(comName);
            pause(0.50);

            % If PulsePal opened without throwing an error,
            % accept that as connected for this toolbox version.
            try
                PulsePalDisplay('MATLAB commanded');
            catch
            end
            return;

        catch ME
            lastErr = ME.message;
        end

        localClosePulsePalRobust();
        localKillCOMPortRobust(comName);
        pause(0.40);
    end

    error('Could not initialize PulsePal on %s. Last error: %s', comName, lastErr);
end

function localKillCOMPortRobust(comName)
    try
        oldObj = instrfind('Port', comName);
        if ~isempty(oldObj)
            for i = 1:numel(oldObj)
                try
                    if strcmpi(get(oldObj(i), 'Status'), 'open')
                        fclose(oldObj(i));
                    end
                catch
                end
                try
                    delete(oldObj(i));
                catch
                end
            end
        end
    catch
    end

    try
        if exist('serialportfind', 'file') == 2 || exist('serialportfind', 'builtin') == 5
            sp = serialportfind("Port", comName);
            if ~isempty(sp)
                for i = 1:numel(sp)
                    try
                        delete(sp(i));
                    catch
                    end
                end
            end
        end
    catch
    end
end


function localBootstrapPulsePalDefaults()
    S = [];

    % First try if the example MAT is already on the MATLAB path
    try
        exFile = which('PulsePalProgram_Example.mat');
    catch
        exFile = '';
    end

    % If not on path, try PulsePal toolbox Programs folder
    if isempty(exFile)
        try
            ppFile = which('PulsePal');
            ppRoot = fileparts(ppFile);
            exFile = fullfile(ppRoot, 'Programs', 'PulsePalProgram_Example.mat');
            if ~exist(exFile, 'file')
                exFile = '';
            end
        catch
            exFile = '';
        end
    end

    if isempty(exFile)
        error(['Could not find PulsePalProgram_Example.mat. ' ...
               'Add the PulsePal Programs folder to the MATLAB path, or place the MAT file on path.']);
    end

    S = load(exFile);

    if ~isfield(S, 'ParameterMatrix')
        error('PulsePalProgram_Example.mat does not contain ParameterMatrix.');
    end

    ProgramPulsePal(S.ParameterMatrix);
    pause(0.10);
end


function tf = localIsPulsePalReady()
    global PulsePalSystem
    tf = false;

    try
        if isempty(PulsePalSystem)
            return;
        end
    catch
        return;
    end

    % Accept either classic struct-like API or object-like API
    try
        if isstruct(PulsePalSystem)
            tf = isfield(PulsePalSystem, 'Params');
            return;
        end
    catch
    end

    try
        tf = isprop(PulsePalSystem, 'Params');
        if tf
            return;
        end
    catch
    end

    % Last fallback: if ProgramPulsePalParam exists, we can still try it
    try
        tf = (exist('ProgramPulsePalParam', 'file') == 2);
    catch
        tf = false;
    end
end

function localClosePulsePalRobust()
    global PulsePalSystem

    try
        AbortPulsePal;
    catch
    end

    try
        EndPulsePal;
    catch
    end

    pause(0.20);

    try
        clear global PulsePalSystem
    catch
    end

    try
        PulsePalSystem = [];
    catch
    end
end

function localProgramPulsePal(cfg)
    ch = round(cfg.pulsepal.channel);

    if ch < 1 || ch > 4
        error('PulsePal channel must be 1..4.');
    end

    try
        AbortPulsePal;
    catch
    end

    % Selected output channel parameters
    localProgramPulsePalParamChecked(ch, 'IsBiphasic',         double(logical(cfg.pulsepal.is_biphasic)));
    localProgramPulsePalParamChecked(ch, 'Phase1Voltage',      cfg.pulsepal.phase1_voltage);
    localProgramPulsePalParamChecked(ch, 'Phase2Voltage',      cfg.pulsepal.phase2_voltage);
    localProgramPulsePalParamChecked(ch, 'RestingVoltage',     cfg.pulsepal.resting_voltage);

    localProgramPulsePalParamChecked(ch, 'Phase1Duration',     cfg.pulsepal.phase1_duration_s);
    localProgramPulsePalParamChecked(ch, 'InterPhaseInterval', cfg.pulsepal.interphase_interval_s);
    localProgramPulsePalParamChecked(ch, 'Phase2Duration',     cfg.pulsepal.phase2_duration_s);
    localProgramPulsePalParamChecked(ch, 'InterPulseInterval', cfg.pulsepal.interpulse_interval_s);

    localProgramPulsePalParamChecked(ch, 'BurstDuration',      cfg.pulsepal.burst_duration_s);
    localProgramPulsePalParamChecked(ch, 'InterBurstInterval', cfg.pulsepal.interburst_interval_s);
    localProgramPulsePalParamChecked(ch, 'PulseTrainDelay',    cfg.pulsepal.train_delay_s);
    localProgramPulsePalParamChecked(ch, 'PulseTrainDuration', cfg.pulsepal.train_duration_s);

    % Keep external/custom features OFF in current workflow
    try, localProgramPulsePalParamChecked(ch, 'CustomTrainID', 0);       catch, end
    try, localProgramPulsePalParamChecked(ch, 'CustomTrainTarget', 0);   catch, end
    try, localProgramPulsePalParamChecked(ch, 'CustomTrainLoop', 0);     catch, end
    try, localProgramPulsePalParamChecked(ch, 'LinkedToTriggerCH1', 0);  catch, end
    try, localProgramPulsePalParamChecked(ch, 'LinkedToTriggerCH2', 0);  catch, end

    % Trigger channel modes off
    try, localProgramPulsePalParamChecked(1, 'TriggerMode', 0); catch, end
    try, localProgramPulsePalParamChecked(2, 'TriggerMode', 0); catch, end

    try
        SyncPulsePalParams;
    catch
    end

    try
        SetContinuousPlay(ch, 0);
    catch
        try
            SetContinuousLoop(ch, 0);
        catch
        end
    end

    try
        PulsePalDisplay('MATLAB commanded');
    catch
    end
end

function localGuiTiming(cfg, requestedDtSec, actualMeanDtSec, devPct, acqElapsedSec, actualFrames)
    if isfield(cfg, 'gui') && isstruct(cfg.gui) && isfield(cfg.gui, 'timingFcn')
        try
            cfg.gui.timingFcn(requestedDtSec, actualMeanDtSec, devPct, acqElapsedSec, actualFrames);
        catch
        end
    end
end

function motorMode = localGetMotorAcqMode(cfg)

    motorMode = 'off';

    try
        if ~isfield(cfg, 'motor') || ~isstruct(cfg.motor) || ...
                ~isfield(cfg.motor, 'enable') || ~logical(cfg.motor.enable)
            return;
        end

        if isfield(cfg.motor, 'acquisition_mode') && ~isempty(cfg.motor.acquisition_mode)
            if strcmpi(cfg.motor.acquisition_mode, 'continuous')
                motorMode = 'continuous';
            elseif strcmpi(cfg.motor.acquisition_mode, 'split')
                motorMode = 'split';
            else
                motorMode = 'split';
            end
        else
            motorMode = 'split';
        end
    catch
        motorMode = 'split';
    end
end

function localProgramPulsePalParamChecked(channel, paramName, value)
    try
        confirmBit = ProgramPulsePalParam(channel, paramName, value);
    catch ME
        error('ProgramPulsePalParam failed for %s on channel %d: %s', ...
            paramName, channel, ME.message);
    end

    if isnumeric(confirmBit) && isscalar(confirmBit) && confirmBit == 0
        error('PulsePal rejected parameter %s on channel %d.', paramName, channel);
    end
end
function tf = localShouldUseProcessRF(cfg)

    tf = false;

    % Needed for frame-synchronized StimBox.
    try
        if isfield(cfg, 'stimbox') && isstruct(cfg.stimbox) && logical(cfg.stimbox.enable)
            tf = true;
            return;
        end
    catch
    end

    % Needed for frame-synchronized PulsePal.
    try
        if isfield(cfg, 'pulsepal') && isstruct(cfg.pulsepal) && logical(cfg.pulsepal.enable)
            tf = true;
            return;
        end
    catch
    end

    % Needed for continuous motor mode because motor moves inside the scan.
    try
        if isfield(cfg, 'motor') && isstruct(cfg.motor) && ...
                logical(cfg.motor.enable) && ...
                isfield(cfg.motor, 'acquisition_mode') && ...
                strcmpi(cfg.motor.acquisition_mode, 'continuous')
            tf = true;
            return;
        end
    catch
    end

    % Optional GUI-only live frame updates.
    % Keep this false if you care about TR.
    try
        if isfield(cfg, 'gui') && isstruct(cfg.gui) && ...
                isfield(cfg.gui, 'forceProcessRFForLiveFrames') && ...
                logical(cfg.gui.forceProcessRFForLiveFrames)
            tf = true;
            return;
        end
    catch
    end
end
function plan = localBuildContinuousMotorCallbackPlan(motorCfg, positionsAbsMM, nFrames)

    plan = struct();
    plan.frames = [];
    plan.targets_abs_mm = [];

    if isempty(positionsAbsMM) || any(isnan(positionsAbsMM))
        return;
    end

    nPos = numel(positionsAbsMM);
    if nPos < 2
        return;
    end

    framesPerSlice = max(1, round(motorCfg.frames_per_position));

    startFrame = 1;
    if isfield(motorCfg, 'frame_start') && ~isempty(motorCfg.frame_start) && ...
            isnumeric(motorCfg.frame_start) && isfinite(motorCfg.frame_start)
        startFrame = max(1, round(motorCfg.frame_start));
    end

    nFrames = max(1, round(nFrames));

    % We pre-move to slice 1 before SCAN.doppler.
    % Therefore first motor move during acquisition is to slice 2.
    maxMoveSlots = floor((nFrames - startFrame) / framesPerSlice);

    if maxMoveSlots < 1
        return;
    end

    if isfield(motorCfg, 'periodic') && logical(motorCfg.periodic)
        nMoves = maxMoveSlots;
    else
        nMoves = min(maxMoveSlots, nPos - 1);
    end

    for k = 1:nMoves
        moveFrame = startFrame + k * framesPerSlice;

        if moveFrame > nFrames
            continue;
        end

        if isfield(motorCfg, 'periodic') && logical(motorCfg.periodic)
            targetIdx = mod(k, nPos) + 1;
        else
            targetIdx = k + 1;
        end

        plan.frames(end+1) = moveFrame; %#ok<AGROW>
        plan.targets_abs_mm(end+1) = positionsAbsMM(targetIdx); %#ok<AGROW>
    end
end

function localPPSet(channelOrTrig, paramName, paramValue)
    confirmBit = ProgramPulsePalParam(channelOrTrig, paramName, paramValue);

    if isempty(confirmBit) || ~isequal(confirmBit, 1)
        error('PulsePal failed while programming parameter "%s".', paramName);
    end
end
% =========================================================================
% Small utilities
% =========================================================================
function cfg = localPrepareSplitMotorSessionFolder(cfg, sessionTag)

    if ~isfield(cfg, 'save_owner') || isempty(cfg.save_owner)
        cfg.save_owner = 'Soner';
    end

    baseFolder = fullfile(pwd, 'Data', cfg.save_owner, cfg.xp_name);

    if ~exist(baseFolder, 'dir')
        mkdir(baseFolder);
    end

    cfg.output_base_folder = baseFolder;
    cfg.output_session_folder = '';
    cfg.output_session_name = '';
    cfg.output_session_tag = sessionTag;

    useSplitMotor = false;

    try
        useSplitMotor = ...
            isfield(cfg, 'motor') && isstruct(cfg.motor) && ...
            isfield(cfg.motor, 'enable') && logical(cfg.motor.enable) && ...
            isfield(cfg.motor, 'acquisition_mode') && ...
            strcmpi(cfg.motor.acquisition_mode, 'split');
    catch
        useSplitMotor = false;
    end

    if ~useSplitMotor
        return;
    end

    sessionIdx = localGetNextSplitMotorSessionIndex(baseFolder);

    sessionName = sprintf('Session_%03d_SplitMotor', sessionIdx);
    sessionFolder = fullfile(baseFolder, sessionName);

    if ~exist(sessionFolder, 'dir')
        mkdir(sessionFolder);
    end

    cfg.output_session_name = sessionName;
    cfg.output_session_folder = sessionFolder;
end

function sessionIdx = localGetNextSplitMotorSessionIndex(baseFolder)

    sessionIdx = 1;

    if ~exist(baseFolder, 'dir')
        return;
    end

    d = dir(fullfile(baseFolder, 'Session_*_SplitMotor*'));

    nums = [];

    for i = 1:numel(d)
        if ~d(i).isdir
            continue;
        end

        tok = regexp(d(i).name, '^Session_(\d+)_SplitMotor', 'tokens', 'once');

        if ~isempty(tok)
            n = str2double(tok{1});
            if ~isnan(n)
                nums(end+1) = n; %#ok<AGROW>
            end
        end
    end

    if ~isempty(nums)
        sessionIdx = max(nums) + 1;
    end
end

function localSetObjPropIfExists(obj, propName, propValue)
    try
        if isprop(obj, propName)
            obj.(propName) = propValue;
        end
    catch
    end
end

function frames = localBuildBlockFrameList(startFrame, durationFrames, repeatOn, repeatEvery, nFrames)
    frames = [];

    if isempty(startFrame) || ~isnumeric(startFrame) || isnan(startFrame)
        return;
    end

    startFrame = round(startFrame);
    if startFrame < 1 || startFrame > nFrames
        return;
    end

    if isempty(durationFrames) || ~isnumeric(durationFrames) || isnan(durationFrames) || durationFrames < 1
        durationFrames = 1;
    end
    durationFrames = max(1, round(durationFrames));

    if ~repeatOn || isempty(repeatEvery) || ~isnumeric(repeatEvery) || isnan(repeatEvery) || repeatEvery < 1
        blockStarts = startFrame;
    else
        repeatEvery = max(1, round(repeatEvery));
        blockStarts = startFrame:repeatEvery:nFrames;
    end

    for k = 1:numel(blockStarts)
        s0 = round(blockStarts(k));
        s1 = min(nFrames, s0 + durationFrames - 1);
        frames = [frames s0:s1]; %#ok<AGROW>
    end

    frames = unique(localCleanFrameVector(frames, nFrames), 'stable');
end

function frames = localCleanFrameVector(framesIn, nFrames)
    if isempty(framesIn) || ~isnumeric(framesIn)
        frames = [];
        return;
    end

    frames = unique(round(framesIn(:)'));
    frames = frames(isfinite(frames));
    frames = frames(frames >= 1 & frames <= nFrames);
end

function v = localGetNumericField(S, names, defaultVal)
    v = defaultVal;
    if ~isstruct(S)
        return;
    end

    for i = 1:numel(names)
        if isfield(S, names{i}) && ~isempty(S.(names{i}))
            v = S.(names{i});
            return;
        end
    end
end

function tf = localGetLogicalField(S, names, defaultVal)
    tf = defaultVal;
    if ~isstruct(S)
        return;
    end

    for i = 1:numel(names)
        if isfield(S, names{i}) && ~isempty(S.(names{i}))
            try
                tf = logical(S.(names{i}));
            catch
                tf = defaultVal;
            end
            return;
        end
    end
end

function legacySpec = localFramesToLegacySpec(frames, nFrames)
    legacySpec = NaN;

    if isempty(frames)
        return;
    end

    frames = unique(frames(:)');

    if isequal(frames, 1:nFrames)
        legacySpec = -1;
    elseif numel(frames) == 1
        legacySpec = frames(1);
    else
        legacySpec = NaN;
    end
end

function legacyStart = localFramesToLegacyPulsePalStart(frames)
    legacyStart = NaN;
    if isempty(frames)
        return;
    end
    legacyStart = frames(1);
end

function txt = localStimBoxSummaryText(cfg, stimboxFrames)
    nTotal = numel(unique([stimboxFrames.d3_frames stimboxFrames.d5_frames stimboxFrames.d6_frames]));
    activeLines = {};
    if cfg.stimbox.d3_enable, activeLines{end+1} = 'D3'; end %#ok<AGROW>
    if cfg.stimbox.d5_enable, activeLines{end+1} = 'D5'; end %#ok<AGROW>
    if cfg.stimbox.d6_enable, activeLines{end+1} = 'D6'; end %#ok<AGROW>
    if isempty(activeLines)
        activeTxt = 'none';
    else
        activeTxt = strjoin(activeLines, ',');
    end
    txt = sprintf('StimBox summary: start=%s, duration=%s, repeat=%d, repeatEvery=%s, unique trigger frames=%d, lines=%s', ...
        localNumToStr(cfg.stimbox.start_frame), ...
        localNumToStr(cfg.stimbox.frame_duration), ...
        logical(cfg.stimbox.repeat_enable), ...
        localNumToStr(cfg.stimbox.repeat_interval_frames), ...
        nTotal, activeTxt);
end

function txt = localNormalizeJournalNote(noteIn)
    if isempty(noteIn)
        txt = '';
        return;
    end

    if isstring(noteIn)
        noteIn = char(noteIn);
    end

    if ischar(noteIn)
        % If noteIn is a multi-row char array, convert each row into a line
        if size(noteIn, 1) > 1
            rows = cellstr(noteIn);
            rows = rows(:)';
            txt = strjoin(rows, newline);
        else
            txt = noteIn;
        end
    else
        txt = '';
    end
end

function s = localOnOff(tf)
    if isempty(tf) || ~logical(tf)
        s = 'OFF';
    else
        s = 'ON';
    end
end

function s = localSafeText(v)
    if isempty(v)
        s = 'NA';
        return;
    end

    if ischar(v)
        s = v;
    elseif isstring(v)
        s = char(v);
    else
        s = 'NA';
    end
end

function v = localGetFieldIfExists(S, fieldName, defaultVal)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        v = S.(fieldName);
    else
        v = defaultVal;
    end
end


function txt = localPulsePalSummaryText(cfg, pulsepalFrames)
    txt = sprintf('PulsePal summary: start=%s, repeat=%d, repeatEvery=%s, trigger count=%d, channel=%d', ...
        localNumToStr(cfg.pulsepal.start_frame), ...
        logical(cfg.pulsepal.repeat_enable), ...
        localNumToStr(cfg.pulsepal.repeat_interval_frames), ...
        numel(pulsepalFrames), ...
        cfg.pulsepal.channel);
end

function txt = localMotorSummaryText(cfg, motorHomeMM, motorPositionsAbsMM, motorPlan)
    if isempty(motorPositionsAbsMM) || all(isnan(motorPositionsAbsMM))
        txt = 'Motor summary: no valid positions.';
        return;
    end

    txt = sprintf('Motor summary: home=%.3f mm, start=%.3f mm, end=%.3f mm, positions=%d, used moves=%d', ...
        motorHomeMM, motorPositionsAbsMM(1), motorPositionsAbsMM(end), ...
        numel(motorPositionsAbsMM), numel(motorPlan.frames));
end

function s = localNumToStr(v)
    if isempty(v) || ~isnumeric(v) || isnan(v)
        s = 'NA';
    else
        s = sprintf('%g', v);
    end
end

end