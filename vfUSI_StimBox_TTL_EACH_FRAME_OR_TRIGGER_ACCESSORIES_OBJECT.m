classdef vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_OBJECT < handle
    % ASCII safe
    % MATLAB 2017b compatible
    %
    % Per-frame callback object for:
    %   SCAN.doppler(...,'processRF',@obj.newImage)
    %
    % Supports:
    %   - StimBox triggers
    %   - PulsePal triggers
    %   - GUI frame updates
    %   - user stop requests
    %   - motor scheduling inside a trial
    %
    % IMPORTANT FIX IN THIS VERSION
    % -------------------------------------------------------------
    % processRF may pass RF/image data, not a frame index.
    % Also, processRF may expect the callback to return data.
    %
    % Therefore:
    %   - newImage(obj, rfIn) returns rfOut = rfIn unchanged
    %   - frame counting is handled internally by frame_counter
    %
    % This avoids callback contract mismatch which can cause:
    %   Output argument "I" (and maybe others) not assigned during
    %   call to "echoScan/doppler".

    properties
        port = []

        % -------------------------------------------------------------
        % Legacy StimBox trigger frames
        % -------------------------------------------------------------
        d3_trig = NaN
        d5_trig = NaN
        d6_trig = NaN

        % Backward-compatibility mode field
        stim_mode = 'none'   % 'none' | 'stimbox' | 'pulsepal' | 'hybrid'

        % -------------------------------------------------------------
        % Trial-global
        % -------------------------------------------------------------
        total_frames = 0
        frame_counter = 0

        % -------------------------------------------------------------
        % StimBox scheduled mode
        % -------------------------------------------------------------
        stimbox_enable = false
        stimbox_output_d3 = false
        stimbox_output_d5 = true
        stimbox_output_d6 = false

        stimbox_start_frame = NaN
        stimbox_duration_frames = 1
        stimbox_repeat_enable = false
        stimbox_repeat_every_frames = NaN

        % Fallback shared schedule
        stimbox_fire_frames = []

        % Explicit per-line schedules
        stimbox_d3_frames = []
        stimbox_d5_frames = []
        stimbox_d6_frames = []

        % Compact log behavior
        stimbox_log_each_frame = false
        stimbox_prev_active = false
        stimbox_prev_lines = ''
        stimbox_active_start_frame = NaN

        % -------------------------------------------------------------
        % PulsePal
        % -------------------------------------------------------------
        pulsepal_enable = false
        pulsepal_start = NaN
        pulsepal_duration = NaN
        pulsepal_channel = 1
        pulsepal_com = ''
        pulsepal_verbose = true

        pulsepal_duration_frames = 1
        pulsepal_repeat_enable = false
        pulsepal_repeat_every_frames = NaN

        pulsepal_fire_frames = []
        pulsepal_trigger_frames = []

        % -------------------------------------------------------------
        % General
        % -------------------------------------------------------------
        verbose = true
        onFrameFcn = []
        onEventFcn = []
        onMotorStepFcn = []
        stopRequestedFcn = []
        frameUpdateEvery = 10

        % -------------------------------------------------------------
        % Motor scheduling
        % -------------------------------------------------------------
        motor_enable = false
        motor_axis = []
        motor_mode = 'single'              % 'single' | 'stepped'
        motor_positions_abs_mm = []
        motor_frames_per_position = NaN
        motor_periodic = false
        motor_settle_pause_s = 0.05

        motor_start_frame = 1
        motor_duration_frames = 1
        motor_repeat_enable = false
        motor_repeat_every_frames = NaN

        motor_plan_frames = []
        motor_plan_indices = []

        % Explicit motor plan
        motor_move_frames = []
        motor_move_target_abs_mm = []
        motor_home_abs_mm = NaN
        motor_use_explicit_plan = false

        motor_current_index = 1
        motor_move_count = 0
        motor_display_total = 0
        motor_last_move_frame = NaN
    end

    methods
        function obj = vfUSI_StimBox_TTL_EACH_FRAME_OR_TRIGGER_ACCESSORIES_OBJECT(port)
            if nargin > 0
                obj.port = port;
            end
        end

        function prepareTrial(obj)
            obj.frame_counter = 0;
            obj.motor_current_index = 1;
            obj.motor_move_count = 0;
            obj.motor_last_move_frame = NaN;

            obj.stimbox_prev_active = false;
            obj.stimbox_prev_lines = '';
            obj.stimbox_active_start_frame = NaN;

            % ---------------------------------------------------------
            % Build fallback StimBox shared schedule only if explicit
            % per-line schedules are not already supplied.
            % ---------------------------------------------------------
            if isempty(obj.stimbox_d3_frames) && isempty(obj.stimbox_d5_frames) && isempty(obj.stimbox_d6_frames)
                obj.stimbox_fire_frames = obj.localBuildBlockFrameList( ...
                    obj.stimbox_start_frame, ...
                    obj.stimbox_duration_frames, ...
                    obj.stimbox_repeat_enable, ...
                    obj.stimbox_repeat_every_frames, ...
                    obj.total_frames);
            else
                obj.stimbox_d3_frames = obj.localCleanFrameVector(obj.stimbox_d3_frames, obj.total_frames);
                obj.stimbox_d5_frames = obj.localCleanFrameVector(obj.stimbox_d5_frames, obj.total_frames);
                obj.stimbox_d6_frames = obj.localCleanFrameVector(obj.stimbox_d6_frames, obj.total_frames);
            end

            % ---------------------------------------------------------
            % PulsePal schedule
            % ---------------------------------------------------------
            if isempty(obj.pulsepal_trigger_frames)
                obj.pulsepal_fire_frames = obj.localBuildPulsePalTriggerFrames( ...
                    obj.pulsepal_start, ...
                    obj.pulsepal_repeat_enable, ...
                    obj.pulsepal_repeat_every_frames, ...
                    obj.total_frames);
            else
                obj.pulsepal_fire_frames = obj.localCleanFrameVector(obj.pulsepal_trigger_frames, obj.total_frames);
            end

            % ---------------------------------------------------------
            % Motor plan
            % ---------------------------------------------------------
            if ~(obj.motor_use_explicit_plan && ~isempty(obj.motor_move_frames) && ~isempty(obj.motor_move_target_abs_mm))
                [obj.motor_plan_frames, obj.motor_plan_indices] = obj.localBuildMotorPlan();
            else
                obj.motor_move_frames = obj.localCleanFrameVector(obj.motor_move_frames, obj.total_frames);

                % Keep vectors same length if needed
                n1 = numel(obj.motor_move_frames);
                n2 = numel(obj.motor_move_target_abs_mm);
                n = min(n1, n2);

                obj.motor_move_frames = obj.motor_move_frames(1:n);
                obj.motor_move_target_abs_mm = obj.motor_move_target_abs_mm(1:n);
            end

            if isempty(obj.motor_display_total) || ~isnumeric(obj.motor_display_total) || obj.motor_display_total < 0
                if obj.motor_use_explicit_plan
                    obj.motor_display_total = numel(obj.motor_move_frames);
                else
                    obj.motor_display_total = numel(obj.motor_plan_frames);
                end
            end
        end

        function rfOut = newImage(obj, rfIn)
            % ---------------------------------------------------------
            % IMPORTANT:
            % processRF may pass RF/image data, not a frame number.
            % Some implementations also expect callback output.
            %
            % So:
            %   1) return data unchanged
            %   2) use internal frame counter for scheduling
            % ---------------------------------------------------------
            rfOut = rfIn;

            try
                obj.frame_counter = obj.frame_counter + 1;
                imag = obj.frame_counter;

                % -----------------------------------------------------
                % User stop check
                % -----------------------------------------------------
                if ~isempty(obj.stopRequestedFcn) && isa(obj.stopRequestedFcn, 'function_handle')
                    try
                        if obj.stopRequestedFcn()
                            error('vfUSI:UserStop', 'User stop requested.');
                        end
                    catch ME
                        if strcmp(ME.identifier, 'vfUSI:UserStop')
                            rethrow(ME);
                        end
                    end
                end

                % -----------------------------------------------------
                % GUI frame update
                % -----------------------------------------------------
                if ~isempty(obj.onFrameFcn) && isa(obj.onFrameFcn, 'function_handle')
                    try
                        if imag == 1 || mod(imag, max(1, round(obj.frameUpdateEvery))) == 0
                            obj.onFrameFcn(imag);
                        end
                    catch
                    end
                end

                % -----------------------------------------------------
                % Motor scheduling
                % -----------------------------------------------------
                obj.localHandleMotorSchedule(imag);

                % -----------------------------------------------------
                % StimBox
                % -----------------------------------------------------
                obj.localHandleStimBox(imag);

                % -----------------------------------------------------
                % PulsePal
                % -----------------------------------------------------
                obj.localHandlePulsePal(imag);

            catch ME
                try
                    obj.localEmitEvent(sprintf('CALLBACK ERROR at frame %d: %s', imag, ME.message));
                catch
                end
                rethrow(ME);
            end
        end

        function close(obj)
            try
                if isempty(obj.port)
                    return;
                end

                if strcmpi(class(obj.port), 'serial')
                    if strcmpi(obj.port.Status, 'open')
                        fclose(obj.port);
                    end
                    delete(obj.port);

                elseif strcmpi(class(obj.port), 'serialport')
                    delete(obj.port);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function localHandleStimBox(obj, imag)
            manualFired = {};
            scheduledFired = {};

            % ---------------------------------------------------------
            % Legacy manual triggers are used only when explicit per-line
            % schedules are absent for that corresponding line.
            % ---------------------------------------------------------
            if isempty(obj.stimbox_d3_frames) && obj.localShouldFire(obj.d3_trig, imag)
                obj.localWriteChar('S');
                manualFired{end+1} = 'D3'; %#ok<AGROW>
            end

            if isempty(obj.stimbox_d5_frames) && obj.localShouldFire(obj.d5_trig, imag)
                obj.localWriteChar('N');
                manualFired{end+1} = 'D5'; %#ok<AGROW>
            end

            if isempty(obj.stimbox_d6_frames) && obj.localShouldFire(obj.d6_trig, imag)
                obj.localWriteChar('T');
                manualFired{end+1} = 'D6'; %#ok<AGROW>
            end

            if ~isempty(manualFired)
                obj.localEmitEvent(sprintf('StimBox trigger at frame %d -> %s', imag, strjoin(manualFired, ',')));
            end

            % ---------------------------------------------------------
            % Scheduled / explicit mode
            % ---------------------------------------------------------
            if obj.stimbox_enable
                % Explicit per-line frame lists
                if obj.localFrameInList(obj.stimbox_d3_frames, imag)
                    obj.localWriteChar('S');
                    scheduledFired{end+1} = 'D3'; %#ok<AGROW>
                end

                if obj.localFrameInList(obj.stimbox_d5_frames, imag)
                    obj.localWriteChar('N');
                    scheduledFired{end+1} = 'D5'; %#ok<AGROW>
                end

                if obj.localFrameInList(obj.stimbox_d6_frames, imag)
                    obj.localWriteChar('T');
                    scheduledFired{end+1} = 'D6'; %#ok<AGROW>
                end

                % Fallback shared schedule if no explicit per-line firing happened
                if isempty(scheduledFired) && obj.localFrameInList(obj.stimbox_fire_frames, imag)
                    if obj.stimbox_output_d3
                        obj.localWriteChar('S');
                        scheduledFired{end+1} = 'D3'; %#ok<AGROW>
                    end
                    if obj.stimbox_output_d5
                        obj.localWriteChar('N');
                        scheduledFired{end+1} = 'D5'; %#ok<AGROW>
                    end
                    if obj.stimbox_output_d6
                        obj.localWriteChar('T');
                        scheduledFired{end+1} = 'D6'; %#ok<AGROW>
                    end
                end
            end
            
            % ---------------------------------------------------------
            % Simple pulse logging
            % ---------------------------------------------------------
            if ~isempty(scheduledFired)
                obj.localEmitEvent(sprintf('StimBox trigger at frame %d -> %s', imag, strjoin(scheduledFired, ',')));
            end
           
        end

        function localUpdateStimBoxCompactLog(obj, imag, scheduledFired)
            activeNow = ~isempty(scheduledFired);

            if activeNow
                linesNow = strjoin(scheduledFired, ',');

                if ~obj.stimbox_prev_active
                    obj.stimbox_prev_active = true;
                    obj.stimbox_prev_lines = linesNow;
                    obj.stimbox_active_start_frame = imag;

                    obj.localEmitEvent(sprintf('StimBox RUNNING from frame %d -> %s', ...
                        imag, linesNow));

                elseif ~strcmp(obj.stimbox_prev_lines, linesNow)
                    prevEnd = imag - 1;
                    obj.localEmitEvent(sprintf('StimBox window ended at frame %d -> %s', ...
                        prevEnd, obj.stimbox_prev_lines));

                    obj.stimbox_prev_active = true;
                    obj.stimbox_prev_lines = linesNow;
                    obj.stimbox_active_start_frame = imag;

                    obj.localEmitEvent(sprintf('StimBox RUNNING from frame %d -> %s', ...
                        imag, linesNow));
                end

                if ~isempty(obj.total_frames) && isnumeric(obj.total_frames) && obj.total_frames > 0 && imag >= obj.total_frames
                    obj.localEmitEvent(sprintf('StimBox window ended at frame %d -> %s', ...
                        imag, obj.stimbox_prev_lines));
                    obj.stimbox_prev_active = false;
                    obj.stimbox_prev_lines = '';
                    obj.stimbox_active_start_frame = NaN;
                end

            else
                if obj.stimbox_prev_active
                    prevEnd = imag - 1;
                    obj.localEmitEvent(sprintf('StimBox window ended at frame %d -> %s', ...
                        prevEnd, obj.stimbox_prev_lines));
                    obj.stimbox_prev_active = false;
                    obj.stimbox_prev_lines = '';
                    obj.stimbox_active_start_frame = NaN;
                end
            end
        end

        function localHandlePulsePal(obj, imag)
            if obj.pulsepal_enable && obj.localFrameInList(obj.pulsepal_fire_frames, imag)
                try
                    TriggerPulsePal(obj.pulsepal_channel);

                    msg = sprintf('PulsePal trigger at frame %d | channel %d', ...
                        imag, obj.pulsepal_channel);

                    if obj.pulsepal_verbose
                        fprintf('%s\n', msg);
                    end

                    obj.localEmitEvent(msg);

                catch ME
                    warnMsg = sprintf('PulsePal trigger failed at frame %d: %s', imag, ME.message);
                    warning('%s', warnMsg);
                    obj.localEmitEvent(warnMsg);
                end
            end
        end

        function localHandleMotorSchedule(obj, imag)
            if ~obj.motor_enable
                return;
            end

            if isempty(obj.motor_axis)
                return;
            end

            % ---------------------------------------------------------
            % Explicit plan
            % ---------------------------------------------------------
            if obj.motor_use_explicit_plan && ~isempty(obj.motor_move_frames) && ~isempty(obj.motor_move_target_abs_mm)
                hit = find(obj.motor_move_frames == imag, 1, 'first');
                if isempty(hit)
                    return;
                end

                targetPos = obj.motor_move_target_abs_mm(hit);
                obj.localMoveMotorToPosition(targetPos, imag, hit, numel(obj.motor_move_frames));
                return;
            end

            % ---------------------------------------------------------
            % Fallback internal plan
            % ---------------------------------------------------------
            if isempty(obj.motor_positions_abs_mm)
                return;
            end

            if isempty(obj.motor_plan_frames) || isempty(obj.motor_plan_indices)
                return;
            end

            hit = find(obj.motor_plan_frames == imag, 1, 'first');
            if isempty(hit)
                return;
            end

            idx = obj.motor_plan_indices(hit);
            obj.motor_current_index = idx;
            obj.localMoveMotorToIndex(idx, imag);
        end

        function localMoveMotorToIndex(obj, idx, imag)
            try
                targetPos = obj.motor_positions_abs_mm(idx);
                obj.localMoveMotorToPosition(targetPos, imag, idx, numel(obj.motor_positions_abs_mm));
            catch ME
                warning('Motor move failed: %s', ME.message);
                obj.localEmitEvent(sprintf('Motor move failed at frame %d: %s', imag, ME.message));
            end
        end

        function localMoveMotorToPosition(obj, targetPos, imag, idxLabel, totalLabel) %#ok<INUSD>
            try
                obj.motor_axis.moveAbsolute(targetPos, zaber.motion.Units.LENGTH_MILLIMETRES);

                if ~isempty(obj.motor_settle_pause_s) && isnumeric(obj.motor_settle_pause_s) && obj.motor_settle_pause_s > 0
                    pause(obj.motor_settle_pause_s);
                end

                obj.motor_last_move_frame = imag;
                obj.motor_move_count = obj.motor_move_count + 1;

                if ~isempty(obj.onMotorStepFcn) && isa(obj.onMotorStepFcn, 'function_handle')
                    try
                        obj.onMotorStepFcn(obj.motor_move_count, obj.motor_display_total, targetPos, imag);
                    catch
                    end
                end

                obj.localEmitEvent(sprintf('Motor moved at frame %d -> abs %.3f mm (%d/%d)', ...
                    imag, targetPos, obj.motor_move_count, obj.motor_display_total));

            catch ME
                warning('Motor move failed: %s', ME.message);
                obj.localEmitEvent(sprintf('Motor move failed at frame %d: %s', imag, ME.message));
            end
        end

        function frames = localBuildBlockFrameList(~, startFrame, durationFrames, repeatEnable, repeatEveryFrames, totalFrames)
            frames = [];

            if isempty(startFrame) || ~isnumeric(startFrame) || isnan(startFrame)
                return;
            end

            startFrame = round(startFrame);
            if startFrame < 1
                return;
            end

            if isempty(durationFrames) || ~isnumeric(durationFrames) || isnan(durationFrames) || durationFrames < 1
                durationFrames = 1;
            end
            durationFrames = max(1, round(durationFrames));

            if ~repeatEnable || isempty(repeatEveryFrames) || ~isnumeric(repeatEveryFrames) || isnan(repeatEveryFrames) || repeatEveryFrames < 1
                blockStarts = startFrame;
            else
                if isempty(totalFrames) || ~isnumeric(totalFrames) || isnan(totalFrames) || totalFrames < 1
                    totalFrames = startFrame + durationFrames - 1;
                end
                blockStarts = startFrame:max(1, round(repeatEveryFrames)):round(totalFrames);
            end

            for k = 1:numel(blockStarts)
                s0 = round(blockStarts(k));
                s1 = s0 + durationFrames - 1;

                if ~isempty(totalFrames) && isnumeric(totalFrames) && isfinite(totalFrames) && totalFrames > 0
                    s1 = min(s1, round(totalFrames));
                end

                frames = [frames s0:s1]; %#ok<AGROW>
            end

            frames = unique(objSafeRound(frames), 'stable');
        end

        function frames = localBuildPulsePalTriggerFrames(~, startFrame, repeatEnable, repeatEveryFrames, totalFrames)
            frames = [];

            if isempty(startFrame) || ~isnumeric(startFrame) || isnan(startFrame)
                return;
            end

            startFrame = round(startFrame);
            if startFrame < 1
                return;
            end

            if ~repeatEnable || isempty(repeatEveryFrames) || ~isnumeric(repeatEveryFrames) || isnan(repeatEveryFrames) || repeatEveryFrames < 1
                frames = startFrame;
            else
                if isempty(totalFrames) || ~isnumeric(totalFrames) || isnan(totalFrames) || totalFrames < 1
                    totalFrames = startFrame;
                end
                frames = startFrame:max(1, round(repeatEveryFrames)):round(totalFrames);
            end

            frames = objSafeRound(frames);
        end

        function [planFrames, planIndices] = localBuildMotorPlan(obj)
            planFrames = [];
            planIndices = [];

            if ~obj.motor_enable
                return;
            end

            if isempty(obj.motor_positions_abs_mm) || any(isnan(obj.motor_positions_abs_mm))
                return;
            end

            nPos = numel(obj.motor_positions_abs_mm);
            if nPos < 1
                return;
            end

            if isempty(obj.total_frames) || ~isnumeric(obj.total_frames) || obj.total_frames < 1
                totalFrames = inf;
            else
                totalFrames = round(obj.total_frames);
            end

            startFrame = round(obj.motor_start_frame);
            if isempty(startFrame) || isnan(startFrame) || startFrame < 1
                startFrame = 1;
            end

            durationFrames = round(obj.motor_duration_frames);
            if isempty(durationFrames) || isnan(durationFrames) || durationFrames < 1
                durationFrames = 1;
            end

            if obj.motor_repeat_enable && ~isempty(obj.motor_repeat_every_frames) && ...
                    isnumeric(obj.motor_repeat_every_frames) && ~isnan(obj.motor_repeat_every_frames) && obj.motor_repeat_every_frames >= 1
                if isfinite(totalFrames)
                    windowStarts = startFrame:round(obj.motor_repeat_every_frames):totalFrames;
                else
                    windowStarts = startFrame;
                end
            else
                windowStarts = startFrame;
            end

            allFrames = [];
            allIdx = [];

            for w = 1:numel(windowStarts)
                ws = round(windowStarts(w));
                if ws < 1 || (isfinite(totalFrames) && ws > totalFrames)
                    continue;
                end

                we = ws + durationFrames - 1;
                if isfinite(totalFrames)
                    we = min(we, totalFrames);
                end

                if strcmpi(obj.motor_mode, 'single')
                    allFrames(end+1) = ws; %#ok<AGROW>
                    allIdx(end+1) = 1; %#ok<AGROW>

                else
                    framesPer = round(obj.motor_frames_per_position);
                    if isempty(framesPer) || isnan(framesPer) || framesPer < 1
                        framesPer = 1;
                    end

                    moveFrames = ws:framesPer:we;
                    if isempty(moveFrames)
                        continue;
                    end

                    if obj.motor_periodic
                        nMoves = numel(moveFrames);
                        moveIdx = mod(0:nMoves-1, nPos) + 1;
                    else
                        nMoves = min(numel(moveFrames), nPos);
                        moveFrames = moveFrames(1:nMoves);
                        moveIdx = 1:nMoves;
                    end

                    allFrames = [allFrames moveFrames]; %#ok<AGROW>
                    allIdx = [allIdx moveIdx]; %#ok<AGROW>
                end
            end

            if isempty(allFrames)
                return;
            end

            [planFrames, ia] = unique(round(allFrames), 'stable');
            planIndices = allIdx(ia);
        end

        function tf = localShouldFire(~, frameSpec, imag)
            if isempty(frameSpec) || ~isnumeric(frameSpec) || isnan(frameSpec)
                tf = false;
                return;
            end

            if isscalar(frameSpec) && frameSpec == -1
                tf = true;
            elseif isscalar(frameSpec)
                tf = (imag == round(frameSpec));
            else
                tf = any(round(frameSpec) == imag);
            end
        end

        function tf = localFrameInList(~, frameList, imag)
            if isempty(frameList)
                tf = false;
                return;
            end
            tf = any(frameList == imag);
        end

        function frames = localCleanFrameVector(~, framesIn, totalFrames)
            if isempty(framesIn) || ~isnumeric(framesIn)
                frames = [];
                return;
            end

            frames = unique(round(framesIn(:)'));
            frames = frames(isfinite(frames));
            frames = frames(frames >= 1);

            if ~isempty(totalFrames) && isnumeric(totalFrames) && isfinite(totalFrames) && totalFrames > 0
                frames = frames(frames <= round(totalFrames));
            end
        end

        function localWriteChar(obj, cmdChar)
            if isempty(obj.port)
                return;
            end

            try
                if strcmpi(class(obj.port), 'serial')
                    fwrite(obj.port, cmdChar, 'char');
                    try
                        flushinput(obj.port);
                    catch
                    end

                elseif strcmpi(class(obj.port), 'serialport')
                    write(obj.port, uint8(cmdChar), 'uint8');
                    try
                        flush(obj.port);
                    catch
                    end

                else
                    error('Unsupported port object class: %s', class(obj.port));
                end
            catch ME
                warning('StimBox write failed: %s', ME.message);
                obj.localEmitEvent(sprintf('StimBox write failed: %s', ME.message));
            end
        end

        function localEmitEvent(obj, msg)
            if obj.verbose
                fprintf('%s\n', msg);
            end

            if ~isempty(obj.onEventFcn) && isa(obj.onEventFcn, 'function_handle')
                try
                    obj.onEventFcn(msg);
                catch
                end
            end
        end
    end
end

function v = objSafeRound(v)
    if isempty(v)
        return;
    end
    v = round(v);
    v = v(isfinite(v));
end