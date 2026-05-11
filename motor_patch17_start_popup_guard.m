function motor_patch17_start_popup_guard()
% motor_patch17_start_popup_guard
% Live popup scaler/validator for HUMoR Motor Reconstruction dialog.
% MATLAB 2017b + 2023b compatible.

persistent t
try
    if ~isempty(t) && isvalid(t)
        try stop(t); catch, end
        try delete(t); catch, end
    end
catch
end

try
    t = timer('Name','HUMOR_motor_patch17_popup_guard', ...
        'ExecutionMode','fixedSpacing', ...
        'Period',0.30, ...
        'TasksToExecute',600, ...
        'TimerFcn',@(~,~)motor_patch17_scan_dialogs());
    start(t);
catch ME
    fprintf('[Patch17] Timer unavailable, applying once: %s\n', ME.message);
    try motor_patch17_scan_dialogs(); catch, end
end
end

function motor_patch17_scan_dialogs()
try
    figs = findall(0,'Type','figure');
catch
    return;
end

for i = 1:numel(figs)
    fig = figs(i);
    if ~ishghandle(fig), continue; end
    try
        nm = lower(get(fig,'Name'));
    catch
        nm = '';
    end
    if motor_patch17_has(nm,'motor') && motor_patch17_has(nm,'reconstruct')
        try
            motor_patch17_patch_one_dialog(fig);
            motor_patch17_update_preview(fig);
        catch ME
            fprintf('[Patch17] Motor popup update skipped: %s\n', ME.message);
        end
    end
end
end

function motor_patch17_patch_one_dialog(fig)
if ~ishghandle(fig), return; end

if ~isappdata(fig,'motor_patch17_scaled')
    try
        oldPos = get(fig,'Position');
        newW = max(oldPos(3), 1180);
        newH = max(oldPos(4), 820);
        sx = newW / max(1,oldPos(3));
        sy = newH / max(1,oldPos(4));
        scr = get(0,'ScreenSize');
        oldPos(1) = max(20, round((scr(3)-newW)/2));
        oldPos(2) = max(20, round((scr(4)-newH)/2));
        oldPos(3) = newW;
        oldPos(4) = newH;
        set(fig,'Position',oldPos);
        motor_patch17_scale_children(fig,sx,sy,1.16);
    catch
    end
    setappdata(fig,'motor_patch17_scaled',true);
end

if isempty(findall(fig,'Tag','motor_patch17_preview'))
    try
        pos = get(fig,'Position');
        uicontrol(fig,'Style','text', ...
            'Tag','motor_patch17_preview', ...
            'String','Motor reconstruction preview will appear here.', ...
            'Units','pixels', ...
            'Position',[45 104 max(400,pos(3)-90) 34], ...
            'BackgroundColor',[0.10 0.11 0.14], ...
            'ForegroundColor',[0.92 0.55 0.16], ...
            'FontName','Arial', ...
            'FontSize',13, ...
            'FontWeight','bold', ...
            'HorizontalAlignment','left');
    catch
    end
end
end

function motor_patch17_scale_children(fig,sx,sy,fontScale)
try
    hs = findall(fig);
catch
    return;
end

for ii = 1:numel(hs)
    h = hs(ii);
    if isequal(h,fig), continue; end
    try
        typ = get(h,'Type');
    catch
        typ = '';
    end
    if ~(strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel'))
        continue;
    end

    try
        oldUnits = get(h,'Units');
        set(h,'Units','pixels');
        p = get(h,'Position');
        if isnumeric(p) && numel(p) >= 4
            p(1) = round(p(1) * sx);
            p(2) = round(p(2) * sy);
            p(3) = round(p(3) * sx);
            p(4) = max(round(p(4) * sy), p(4) + 2);
            set(h,'Position',p);
        end
        set(h,'Units',oldUnits);
    catch
    end

    try
        fs = get(h,'FontSize');
        if isnumeric(fs) && isfinite(fs) && fs > 0
            set(h,'FontSize',max(10,round(fs*fontScale)));
        end
    catch
    end
end
end

function motor_patch17_update_preview(fig)
if ~ishghandle(fig), return; end

preview = findall(fig,'Tag','motor_patch17_preview');
if isempty(preview), return; end
preview = preview(1);

P = motor_patch17_extract_params(fig);

hasFPP = isfinite(P.framesPerPlane) && P.framesPerPlane > 0;
hasNP  = isfinite(P.nPlanes) && P.nPlanes > 0;
hasBadDiscard = isfinite(P.discardFrames) && P.discardFrames < 0;

if hasFPP && hasNP && ~hasBadDiscard
    fpp = round(P.framesPerPlane);
    np  = round(P.nPlanes);
    totalBlock = fpp * np;
    msg = sprintf('This will reconstruct %d planes with %d frames per plane. One full cycle = %d frames. Discard/skip = %s.', np, fpp, totalBlock, P.discardText);
    set(preview,'String',msg,'ForegroundColor',[0.35 0.95 0.55]);
    motor_patch17_set_run_buttons(fig,true);
    P.valid = true;
else
    if hasBadDiscard
        msg = 'Invalid motor settings: discarded/skipped frames cannot be negative.';
        disable = true;
    elseif ~hasFPP && ~hasNP
        msg = 'Enter valid Frames per plane and Number of planes to preview reconstruction.';
        disable = false;
    elseif ~hasFPP
        msg = 'Invalid motor settings: Frames per plane must be positive.';
        disable = true;
    else
        msg = 'Invalid motor settings: Number of planes must be positive.';
        disable = true;
    end
    set(preview,'String',msg,'ForegroundColor',[1.00 0.38 0.30]);
    motor_patch17_set_run_buttons(fig,~disable);
    P.valid = false;
end

try
    setappdata(fig,'motor_patch17_params',P);
catch
end

try
    motor_patch17_save_snapshot(P);
catch
end
end

function P = motor_patch17_extract_params(fig)
P = struct();
P.framesPerPlane = NaN;
P.nPlanes = NaN;
P.discardFrames = 0;
P.discardText = '0';
P.sourceMode = '';
P.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');

try
    labels = findall(fig,'Style','text');
catch
    labels = [];
end
try
    edits = findall(fig,'Style','edit');
catch
    edits = [];
end

[P.framesPerPlane,~] = motor_patch17_value_by_label(labels,edits,{'frames per plane','frame per plane','frames/plane','frames per slice','frames per z'});
[P.nPlanes,~] = motor_patch17_value_by_label(labels,edits,{'number of planes','num planes','n planes','nplanes','planes','slices'});
[P.discardFrames,P.discardText] = motor_patch17_value_by_label(labels,edits,{'discard','skip','drop','remove first','ignored frames'});

if ~isfinite(P.discardFrames)
    P.discardFrames = 0;
    P.discardText = '0';
end

try
    popups = findall(fig,'Style','popupmenu');
    if ~isempty(popups)
        s = get(popups(1),'String');
        v = get(popups(1),'Value');
        if iscell(s) && v >= 1 && v <= numel(s)
            P.sourceMode = s{v};
        elseif ischar(s)
            P.sourceMode = s;
        end
    end
catch
end
end

function [val,str] = motor_patch17_value_by_label(labels,edits,keys)
val = NaN;
str = '';
if isempty(labels) || isempty(edits), return; end

bestScore = Inf;
bestEdit = [];

for i = 1:numel(labels)
    try
        labelStr = lower(motor_patch17_char(get(labels(i),'String')));
    catch
        labelStr = '';
    end
    if ~motor_patch17_has_any(labelStr,keys)
        continue;
    end

    try
        lp = get(labels(i),'Position');
    catch
        continue;
    end
    ly = lp(2) + lp(4)/2;
    lx = lp(1);

    for j = 1:numel(edits)
        try
            ep = get(edits(j),'Position');
            ey = ep(2) + ep(4)/2;
            ex = ep(1);
        catch
            continue;
        end
        score = abs(ey-ly) + 0.01*abs(ex-lx);
        if ex < lx
            score = score + 100;
        end
        if score < bestScore
            bestScore = score;
            bestEdit = edits(j);
        end
    end
end

if isempty(bestEdit), return; end
try
    str = strtrim(motor_patch17_char(get(bestEdit,'String')));
catch
    str = '';
end

nums = sscanf(str,'%f');
if ~isempty(nums)
    val = nums(1);
end
end

function motor_patch17_set_run_buttons(fig,enableRun)
try
    btns = findall(fig,'Style','pushbutton');
catch
    return;
end

for i = 1:numel(btns)
    try
        s = lower(motor_patch17_char(get(btns(i),'String')));
    catch
        s = '';
    end
    isRun = motor_patch17_has_any(s,{'proceed','run','reconstruct','start','ok','apply'});
    isSafe = motor_patch17_has_any(s,{'cancel','close','browse','help','select'});
    if isRun && ~isSafe
        try
            if enableRun
                set(btns(i),'Enable','on');
            else
                set(btns(i),'Enable','off');
            end
        catch
        end
    end
end
end

function motor_patch17_save_snapshot(P)
try
    root = pwd;
    reportDir = fullfile(root,'_health_reports');
    if exist(reportDir,'dir') ~= 7
        mkdir(reportDir);
    end
    matFile = fullfile(reportDir,'motor_patch17_last_params.mat');
    txtFile = fullfile(reportDir,'motor_patch17_last_params.txt');
    save(matFile,'P');
    fid = fopen(txtFile,'w');
    if fid > 0
        fprintf(fid,'HUMoR Motor Patch 17 parameter snapshot\n');
        fprintf(fid,'Timestamp: %s\n',P.timestamp);
        fprintf(fid,'Frames per plane: %g\n',P.framesPerPlane);
        fprintf(fid,'Number of planes: %g\n',P.nPlanes);
        fprintf(fid,'Discard/skip frames: %s\n',P.discardText);
        fprintf(fid,'Source mode: %s\n',P.sourceMode);
        fprintf(fid,'Valid: %d\n',logical(P.valid));
        fclose(fid);
    end
catch
end
end

function tf = motor_patch17_has(s,key)
tf = ~isempty(strfind(lower(char(s)),lower(char(key))));
end

function tf = motor_patch17_has_any(s,keys)
tf = false;
for i = 1:numel(keys)
    if motor_patch17_has(s,keys{i})
        tf = true;
        return;
    end
end
end

function s = motor_patch17_char(x)
try
    if iscell(x)
        s = strjoin(x,' ');
    elseif isempty(x)
        s = '';
    else
        s = char(x);
    end
catch
    s = '';
end
end
