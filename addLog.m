function addLog(msg)
% addLog.m - fallback logger for HUMoR / fUSI Studio
% MATLAB 2017b compatible.

if nargin < 1
    msg = '';
end

try
    if iscell(msg)
        tmp = '';
        for ii = 1:numel(msg)
            tmp = [tmp char(msg{ii}) ' ']; %#ok<AGROW>
        end
        msg = tmp;
    elseif isnumeric(msg)
        msg = num2str(msg);
    else
        msg = char(msg);
    end
catch
    msg = '<log message could not be converted>';
end

entry = sprintf('[%s] %s', datestr(now,'HH:MM:SS'), msg);

% Always echo to Command Window too.
try
    fprintf('%s\n', entry);
catch
end

try
    figs = findall(0,'Type','figure','Name','HUMoR Analysis Tool');
    if isempty(figs)
        figs = findall(0,'Type','figure');
    end
    if isempty(figs)
        return;
    end

    fig = figs(1);
    studio = guidata(fig);
    if isempty(studio) || ~isstruct(studio)
        return;
    end

    if isfield(studio,'logBoxJava') && ~isempty(studio.logBoxJava)
        try
            oldText = char(studio.logBoxJava.getText());
            if isempty(oldText)
                newText = entry;
            else
                newText = [oldText sprintf('\n') entry];
            end
            studio.logBoxJava.setText(newText);
            studio.logBoxJava.setCaretPosition(studio.logBoxJava.getDocument().getLength());
            drawnow;
            return;
        catch
        end
    end

    if isfield(studio,'logBox') && ~isempty(studio.logBox) && ishandle(studio.logBox)
        try
            current = get(studio.logBox,'String');
            if isempty(current)
                current = {};
            elseif ischar(current)
                current = cellstr(current);
            elseif ~iscell(current)
                current = {current};
            end
            if numel(current) == 1 && isempty(strtrim(current{1}))
                current = {};
            end
            set(studio.logBox,'String',[current; {entry}]);
            drawnow;
        catch
        end
    end
catch
end

end
