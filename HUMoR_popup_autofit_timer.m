function HUMoR_popup_autofit_timer(action)
% HUMoR_popup_autofit_timer
% Stable version: auto-polishes general setup popups, but NEVER touches
% Atlas Segmentation windows. This prevents segmentation popup vibration.

if nargin < 1 || isempty(action)
    action = 'start';
end
action = lower(strtrim(char(action)));

switch action
    case 'start'
        localStopTimers();
        t = timer('Name','HUMoR_popup_autofit_timer_STABLE_NO_SEG', ...
            'ExecutionMode','fixedSpacing', ...
            'Period',0.75, ...
            'BusyMode','drop', ...
            'TimerFcn',@(~,~)localTick());
        start(t);
        localTick();

    case 'stop'
        localStopTimers();

    case {'once','apply'}
        localTick();

    otherwise
        error('Unknown action: %s', action);
end
end

function localTick()
try
    figs = findall(0,'Type','figure');
catch
    return;
end

keep = [];
for k = 1:numel(figs)
    f = figs(k);
    if ~ishghandle(f), continue; end

    nm = '';
    tg = '';
    try, nm = char(get(f,'Name')); catch, end
    try, tg = char(get(f,'Tag')); catch, end
    s = lower([nm ' ' tg]);

    isSeg = false;
    if ~isempty(strfind(s,'segmentation')), isSeg = true; end
    if ~isempty(strfind(s,'atlas segmentation')), isSeg = true; end
    if ~isempty(strfind(s,'roi segmentation')), isSeg = true; end
    if ~isempty(strfind(s,'region-time')), isSeg = true; end
    if ~isempty(strfind(s,'parcellation')), isSeg = true; end

    if isSeg
        continue;
    end

    keep = [keep f]; %#ok<AGROW>
end

if isempty(keep)
    return;
end

try
    HUMoR_popup_polish_now(keep);
catch
end
end

function localStopTimers()
try
    ts = timerfindall;
    for k = 1:numel(ts)
        nm = '';
        try, nm = char(get(ts(k),'Name')); catch, end
        low = lower(nm);
        if ~isempty(strfind(low,'humor_popup')) || ~isempty(strfind(low,'popup_autofit')) || ~isempty(strfind(low,'autofit_timer')) || ~isempty(strfind(low,'stable_no_seg'))
            try, stop(ts(k)); catch, end
            try, delete(ts(k)); catch, end
        end
    end
catch
end
end
