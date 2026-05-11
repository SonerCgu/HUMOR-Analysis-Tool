function HUMoR_popup_autofit_timer(action)
% HUMoR_popup_autofit_timer
% Starts/stops popup polish monitor. Size is applied only once per popup.

if nargin < 1 || isempty(action)
    action = 'start';
end
action = lower(strtrim(char(action)));

switch action
    case 'start'
        localStopTimers();
        t = timer('Name','HUMoR_popup_autofit_timer_patch28', ...
            'ExecutionMode','fixedSpacing', ...
            'Period',0.10, ...
            'BusyMode','drop', ...
            'TimerFcn',@(~,~)localTick());
        start(t);
        try, HUMoR_popup_polish_now(); catch, end
    case 'stop'
        localStopTimers();
    case 'once'
        try, HUMoR_popup_polish_now(); catch, end
    otherwise
        error('Unknown action: %s', action);
end
end

function localTick()
try
    HUMoR_popup_polish_now();
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
        if ~isempty(strfind(low,'humor_popup')) || ~isempty(strfind(low,'popup_autofit')) || ~isempty(strfind(low,'autofit_timer'))
            try, stop(ts(k)); catch, end
            try, delete(ts(k)); catch, end
        end
    end
catch
end
end
