function HUMoR_popup_autofit_apply(hFig)
% Direct wrapper for HUMoR popup auto-fit.
if nargin < 1 || isempty(hFig) || ~ishghandle(hFig)
    try, hFig = gcf; catch, return; end
end
try
    HUMoR_popup_autofit_timer('apply',hFig);
catch
end
end
