function HUMoR_force_fullscreen_fig(hFig)
% HUMoR_force_fullscreen_fig
% Opens normal MATLAB figure GUIs in a large/maximized window.
% MATLAB 2017b + 2023b compatible.

if nargin < 1 || isempty(hFig) || ~ishghandle(hFig)
    try
        hFig = gcf;
    catch
        return;
    end
end

try
    set(hFig,'Resize','on');
catch
end

try
    set(hFig,'Units','pixels');
catch
end

drawnow;

% Newer MATLAB versions: use true maximized state.
try
    if isprop(hFig,'WindowState')
        set(hFig,'WindowState','maximized');
        drawnow;
        return;
    end
catch
end

% MATLAB 2017b fallback: fill most of the screen.
try
    scr = get(0,'ScreenSize');
    margin = 25;
    W = max(1000, scr(3) - 2*margin);
    H = max(700,  scr(4) - 2*margin);
    set(hFig,'Position',[margin margin W H]);
    drawnow;
catch
end
end
