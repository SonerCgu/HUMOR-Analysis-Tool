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
    userStopped = false;

    try
        localGuiStatus(cfg, 'Connecting hardware...', 'notready');

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

            PulsePal(cfg.pulsepal.com);
            pulsePalConnected = true;

            if cfg.pulsepal.custom_train_id > 0
                error(['CustomTrainID > 0 is not supported yet in this GUI, ' ...
                       'because no custom pulse times/voltages are uploaded with SendCustomPulseTrain.']);
            end

            localProgramPulsePal(cfg);

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

        % -----------------------------------------------------------------
        % Motor scheduling into callback object
        % -----------------------------------------------------------------
        localSetObjPropIfExists(pp, 'motor_enable', cfg.motor.enable);
        localSetObjPropIfExists(pp, 'motor_axis', motorAxis);

        % Legacy/internal schedule fallback
        localSetObjPropIfExists(pp, 'motor_mode', cfg.motor.mode);
        localSetObjPropIfExists(pp, 'motor_positions_abs_mm', motorPositionsAbsMM);
        localSetObjPropIfExists(pp, 'motor_frames_per_position', cfg.motor.frames_per_position);
        localSetObjPropIfExists(pp, 'motor_periodic', cfg.motor.periodic);
        localSetObjPropIfExists(pp, 'motor_settle_pause_s', cfg.motor.settle_pause_s);
        localSetObjPropIfExists(pp, 'motor_start_frame', cfg.motor.frame_start);
        localSetObjPropIfExists(pp, 'motor_duration_frames', cfg.motor.frame_duration);
        localSetObjPropIfExists(pp, 'motor_repeat_enable', cfg.motor.repeat_enable);
        localSetObjPropIfExists(pp, 'motor_repeat_every_frames', cfg.motor.repeat_interval_frames);

        % New explicit plan
        localSetObjPropIfExists(pp, 'motor_move_frames', motorPlan.frames);
        localSetObjPropIfExists(pp, 'motor_move_target_abs_mm', motorPlan.targets_abs_mm);
        localSetObjPropIfExists(pp, 'motor_home_abs_mm', motorHomeMM);
        localSetObjPropIfExists(pp, 'motor_use_explicit_plan', true);
        localSetObjPropIfExists(pp, 'motor_display_total', numel(motorPlan.frames));

        localPrintSummary(cfg, motorHomeMM, motorPositionsAbsMM, stimboxFrames, pulsepalTriggerFrames, motorPlan);

        localGuiStatus(cfg, 'Hardware ready. Starting experiment...', 'notready');
        localGuiFrame(cfg, 0);
        localGuiTrial(cfg, 0, cfg.n_trials);

        if cfg.motor.enable
            localGuiMotor(cfg, 0, numel(motorPlan.frames), motorHomeMM, 0);
            localGuiLog(cfg, localMotorSummaryText(cfg, motorHomeMM, motorPositionsAbsMM, motorPlan));
        else
            localGuiMotor(cfg, 0, 0, NaN, 0);
        end

        % -----------------------------------------------------------------
        % Main trial loop
        % -----------------------------------------------------------------
        for iTrial = 1:cfg.n_trials
            if localStopRequested(cfg)
                error('vfUSI:UserStop', 'User stop requested.');
            end

            localGuiFrame(cfg, 0);
            localGuiTrial(cfg, iTrial, cfg.n_trials);

            if cfg.motor.enable
                localGuiMotor(cfg, 0, numel(motorPlan.frames), motorHomeMM, 0);
            end

            runMsg = sprintf('Running trial %d/%d', iTrial, cfg.n_trials);
            localGuiStatus(cfg, runMsg, 'notready');
            localGuiLog(cfg, runMsg);

            fprintf('----- Trial %02d / %02d -----\n', iTrial, cfg.n_trials);
            tTrial = tic;

            try
                pp.prepareTrial();
            catch
            end

            try
                [I, md] = SCAN.doppler(cfg.nblocksImage, cfg.n_frames, ...
                    'processRF', @(rf)localProcessRFBridge(pp, rf));
            catch ME
                localGuiLog(cfg, sprintf('DOPPLER FAILURE: %s', ME.message));
                fprintf(2, '\n===== DOPPLER FAILURE =====\n');
                fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'on'));
                rethrow(ME);
            end

            [nameFile, nameShort] = localMakeSaveName(FS, cfg, sessionTag, motorPositionsAbsMM, motorHomeMM, iTrial);
            save(nameFile, 'I', 'md', '-v6');

            FS.writeJournal(localMakeJournalText(nameShort, cfg, motorPositionsAbsMM, motorHomeMM, iTrial));

            localGuiLog(cfg, sprintf('Saved file: %s', nameFile));
            localGuiLog(cfg, sprintf('Saved folder: %s', fileparts(nameFile)));

            fprintf('Elapsed time: %.1f seconds\n', toc(tTrial));

            if iTrial < cfg.n_trials
                localGuiStatus(cfg, 'Waiting between trials...', 'notready');
                localSafePause(cfg.time_pause);
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
            try
                AbortPulsePal;
            catch
            end
            try
                EndPulsePal;
            catch
            end
        end
    end
end

% =========================================================================
% Safe processRF bridge
% =========================================================================
function rfOut = localProcessRFBridge(pp, rfIn)
    % Pass RF data through unchanged while still allowing the object
    % to perform GUI updates, trigger scheduling, motor moves, and stop checks.
    rfOut = pp.newImage(rfIn);
end

% =========================================================================
% Defaults
% =========================================================================
function cfg = localApplyDefaults(cfg)

    if ~isfield(cfg, 'xp_name') || isempty(cfg.xp_name)
        cfg.xp_name = 'Data_w_Triggers';
    end

    if ~isfield(cfg, 'n_frames') || isempty(cfg.n_frames)
        cfg.n_frames = 500;
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
        cfg.stimbox.start_frame = 100;
    end

    if ~isfield(cfg.stimbox, 'frame_duration') || isempty(cfg.stimbox.frame_duration)
        cfg.stimbox.frame_duration = 50;
    end

    if ~isfield(cfg.stimbox, 'repeat_enable') || isempty(cfg.stimbox.repeat_enable)
        cfg.stimbox.repeat_enable = false;
    end

    if ~isfield(cfg.stimbox, 'repeat_interval_frames') || isempty(cfg.stimbox.repeat_interval_frames)
        cfg.stimbox.repeat_interval_frames = 10;
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
        cfg.pulsepal.com = 'COM13';
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
        cfg.motor.frames_per_position = 100;
    end

    if ~isfield(cfg.motor, 'periodic') || isempty(cfg.motor.periodic)
        cfg.motor.periodic = false;
    end

    if ~isfield(cfg.motor, 'return_to_zero') || isempty(cfg.motor.return_to_zero)
        cfg.motor.return_to_zero = true;
    end

    if ~isfield(cfg.motor, 'settle_pause_s') || isempty(cfg.motor.settle_pause_s)
        cfg.motor.settle_pause_s = 0.05;
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
function [nameFile, nameShort] = localMakeSaveName(FS, cfg, sessionTag, motorPositionsAbsMM, motorHomeMM, iTrial)
    motorTag = localMotorTag(cfg, motorPositionsAbsMM, motorHomeMM);

    fileSpec = sprintf('%s\\Session_%s\\fUS_%s_%s_T%03d.mat', ...
        cfg.xp_name, sessionTag, sessionTag, motorTag, iTrial);

    [nameFile, nameShort] = FS.newName(fileSpec);
end

function txt = localMakeJournalText(nameShort, cfg, motorPositionsAbsMM, motorHomeMM, iTrial)
    motorTag = localMotorTag(cfg, motorPositionsAbsMM, motorHomeMM);

    txt = sprintf('* %s (Trial=%d, Frames=%d, MotorMode=%s, MotorTag=%s, StimBox=%d, PulsePal=%d)', ...
        nameShort, ...
        iTrial, ...
        cfg.n_frames, ...
        cfg.motor.mode, ...
        motorTag, ...
        logical(cfg.stimbox.enable), ...
        logical(cfg.pulsepal.enable));
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

% =========================================================================
% PulsePal programming
% =========================================================================
function localProgramPulsePal(cfg)
    global PulsePalSystem

    ch = round(cfg.pulsepal.channel);

    if ch < 1 || ch > 4
        error('PulsePal channel must be 1..4.');
    end

    try
        AbortPulsePal;
    catch
    end

    % Safe baseline for all channels
    PulsePalSystem.Params.IsBiphasic(:)         = 0;
    PulsePalSystem.Params.Phase1Voltage(:)      = 0;
    PulsePalSystem.Params.Phase2Voltage(:)      = 0;
    PulsePalSystem.Params.RestingVoltage(:)     = 0;

    PulsePalSystem.Params.Phase1Duration(:)     = 0.0001;
    PulsePalSystem.Params.InterPhaseInterval(:) = 0.0001;
    PulsePalSystem.Params.Phase2Duration(:)     = 0.0001;
    PulsePalSystem.Params.InterPulseInterval(:) = 0.001;

    PulsePalSystem.Params.BurstDuration(:)      = 0;
    PulsePalSystem.Params.InterBurstInterval(:) = 0;
    PulsePalSystem.Params.PulseTrainDuration(:) = 0.001;
    PulsePalSystem.Params.PulseTrainDelay(:)    = 0;

    PulsePalSystem.Params.LinkTriggerChannel1(:) = 0;
    PulsePalSystem.Params.LinkTriggerChannel2(:) = 0;
    PulsePalSystem.Params.CustomTrainID(:)       = 0;
    PulsePalSystem.Params.CustomTrainTarget(:)   = 0;
    PulsePalSystem.Params.CustomTrainLoop(:)     = 0;
    PulsePalSystem.Params.TriggerMode(:)         = 0;

    % Selected output channel parameters
    PulsePalSystem.Params.IsBiphasic(ch)         = double(logical(cfg.pulsepal.is_biphasic));
    PulsePalSystem.Params.Phase1Voltage(ch)      = cfg.pulsepal.phase1_voltage;
    PulsePalSystem.Params.Phase2Voltage(ch)      = cfg.pulsepal.phase2_voltage;
    PulsePalSystem.Params.RestingVoltage(ch)     = cfg.pulsepal.resting_voltage;

    PulsePalSystem.Params.Phase1Duration(ch)     = cfg.pulsepal.phase1_duration_s;
    PulsePalSystem.Params.InterPhaseInterval(ch) = cfg.pulsepal.interphase_interval_s;
    PulsePalSystem.Params.Phase2Duration(ch)     = cfg.pulsepal.phase2_duration_s;
    PulsePalSystem.Params.InterPulseInterval(ch) = cfg.pulsepal.interpulse_interval_s;

    PulsePalSystem.Params.BurstDuration(ch)      = cfg.pulsepal.burst_duration_s;
    PulsePalSystem.Params.InterBurstInterval(ch) = cfg.pulsepal.interburst_interval_s;
    PulsePalSystem.Params.PulseTrainDelay(ch)    = cfg.pulsepal.train_delay_s;
    PulsePalSystem.Params.PulseTrainDuration(ch) = cfg.pulsepal.train_duration_s;

    % Keep these OFF in your current software-triggered workflow
    PulsePalSystem.Params.CustomTrainID(ch)       = 0;
    PulsePalSystem.Params.CustomTrainTarget(ch)   = 0;
    PulsePalSystem.Params.CustomTrainLoop(ch)     = 0;
    PulsePalSystem.Params.LinkTriggerChannel1(ch) = 0;
    PulsePalSystem.Params.LinkTriggerChannel2(ch) = 0;

    % Trigger modes off
    PulsePalSystem.Params.TriggerMode(1) = 0;
    PulsePalSystem.Params.TriggerMode(2) = 0;

    SyncPulsePalParams;
    SetContinuousPlay(ch, 0);
end

% =========================================================================
% Small utilities
% =========================================================================
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