function HUMoR_popup_polish_now(h)
% HUMoR_popup_polish_now
% NO-VIBRATE PATCH: do not call HUMoR_segmentation_popup_fix_now() here.
% That second helper resizes the segmentation popup to a different size,
% and the autofit timer can make the popup grow/shrink repeatedly.
% HUMoR_SEGMENTATION_PATCH30B_CALL
% NO-VIBRATE PATCH: removed direct segmentation popup resizing call.
% HUMoR_popup_polish_now
% Enlarges and polishes selected HUMoR/fUSI popup windows.
% Size is applied once per popup. Fonts/controls can be refreshed safely.

if nargin < 1 || isempty(h)
    try
        figs = findall(0,'Type','figure');
    catch
        return;
    end
else
    figs = h(:)';
end

for ii = 1:numel(figs)
    f = figs(ii);
    if ~ishghandle(f)
        continue;
    end

    nm = '';
    tg = '';
    try, nm = char(get(f,'Name')); catch, end
    try, tg = char(get(f,'Tag'));  catch, end

    kind = localClassifyPopup(nm,tg);
    if isempty(kind)
        continue;
    end

    try
        localPolishFigure(f,kind);
    catch
    end
end
end

function kind = localClassifyPopup(nm,tg)
s = lower([char(nm) ' ' char(tg)]);
kind = '';

% Do not resize the main Studio window.
if localHasAny(s,{'humor / fusi studio','humor fusi studio','fusi studio main','main studio'})
    if ~localHasAny(s,{'scrub','scrubbing','frame rejection','temporal smoothing','subsampling','filtering','butterworth','segmentation','functional connectivity'})
        return;
    end
end

if localHasAny(s,{'scrubbing','scrub','frame rejection','dvars','rejected volumes','rejection setup'})
    kind = 'scrub';
elseif localHasAny(s,{'temporal smoothing','subsampling','smoothing/subsampling','subsample','smooth/subsample'})
    kind = 'smooth';
elseif localHasAny(s,{'filtering','butterworth','bandpass','band-pass','high-pass','low-pass','temporal filter'})
    kind = 'filter';
elseif localHasAny(s,{'segmentation','atlas segmentation','roi segmentation','parcellation','roi atlas','atlas labels','region labels'})
    % NO-VIBRATE PATCH: Segmentation.m handles its own fixed layout.
    % Do not let global popup polish resize this window.
    kind = '';
    return;
elseif localHasAny(s,{'functional connectivity','connectivity','fc setup','seed correlation','roi heatmap','pair roi','graph matrix'})
    kind = 'fc';
end
end

function tf = localHasAny(s,keys)
tf = false;
for kk = 1:numel(keys)
    if ~isempty(strfind(s,keys{kk}))
        tf = true;
        return;
    end
end
end

function localPolishFigure(f,kind)
[targetPos,minFont,maxFont,titleFont,buttonFont,editH] = localStyle(kind);

try
    oldUnits = get(f,'Units');
    set(f,'Units','pixels');
    oldPos = get(f,'Position');
catch
    oldUnits = 'pixels';
    oldPos = [100 100 targetPos(3) targetPos(4)];
end

targetPos = localFitOnScreen(targetPos);

sizeKey = ['HUMoR_popup_size_done_patch28_' kind];
doScale = true;
try
    if isappdata(f,sizeKey) && isequal(getappdata(f,sizeKey),true)
        doScale = false;
    end
catch
end

if doScale
    hs = [];
    try, hs = findall(f); catch, end

    try
        set(f,'Position',targetPos);
    catch
    end

    sx = 1; sy = 1;
    try
        if oldPos(3) > 10, sx = targetPos(3) / oldPos(3); end
        if oldPos(4) > 10, sy = targetPos(4) / oldPos(4); end
    catch
    end

    if isfinite(sx) && isfinite(sy) && sx > 0 && sy > 0
        for jj = 1:numel(hs)
            h = hs(jj);
            if ~ishghandle(h) || isequal(h,f)
                continue;
            end
            typ = '';
            try, typ = get(h,'Type'); catch, end
            if ~(strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel') || strcmpi(typ,'axes') || strcmpi(typ,'uitable'))
                continue;
            end
            try
                hu = get(h,'Units');
                set(h,'Units','pixels');
                p = get(h,'Position');
                if isnumeric(p) && numel(p) >= 4
                    p(1) = round(p(1) * sx);
                    p(2) = round(p(2) * sy);
                    p(3) = max(1,round(p(3) * sx));
                    p(4) = max(1,round(p(4) * sy));
                    set(h,'Position',p);
                end
                set(h,'Units',hu);
            catch
            end
        end
    end

    try, setappdata(f,sizeKey,true); catch, end
end

try
    set(f,'Color',[0.07 0.08 0.10]);
catch
end

localApplyFontsAndControls(f,kind,minFont,maxFont,titleFont,buttonFont,editH);

if strcmpi(kind,'segmentation')
    try, localPolishSegmentationSpecific(f); catch, end
end

try, set(f,'Units',oldUnits); catch, end
end

function targetPos = localFitOnScreen(targetPos)
try
    scr = get(0,'ScreenSize');
catch
    scr = [1 1 1920 1080];
end

maxW = max(900, scr(3) - 80);
maxH = max(650, scr(4) - 110);
targetPos(3) = min(targetPos(3), maxW);
targetPos(4) = min(targetPos(4), maxH);
targetPos(1) = max(20, round((scr(3) - targetPos(3)) / 2));
targetPos(2) = max(30, round((scr(4) - targetPos(4)) / 2));
end

function [pos,minFont,maxFont,titleFont,buttonFont,editH] = localStyle(kind)
switch lower(kind)
    case 'scrub'
        pos = [40 45 1550 900];
        minFont = 17; maxFont = 24; titleFont = 26; buttonFont = 18; editH = 42;
    case 'smooth'
        pos = [35 40 1600 940];
        minFont = 17; maxFont = 24; titleFont = 26; buttonFont = 18; editH = 42;
    case 'filter'
        pos = [35 40 1600 940];
        minFont = 17; maxFont = 24; titleFont = 26; buttonFont = 18; editH = 42;
    case 'segmentation'
        % Segmentation has many long labels; use a larger window but controlled fonts.
        pos = [20 30 1680 980];
        minFont = 13; maxFont = 18; titleFont = 21; buttonFont = 15; editH = 34;
    case 'fc'
        pos = [35 35 1650 960];
        minFont = 15; maxFont = 22; titleFont = 24; buttonFont = 17; editH = 38;
    otherwise
        pos = [80 80 1300 820];
        minFont = 14; maxFont = 20; titleFont = 22; buttonFont = 16; editH = 36;
end
end

function localApplyFontsAndControls(f,kind,minFont,maxFont,titleFont,buttonFont,editH)
try
    hs = findall(f);
catch
    return;
end

for jj = 1:numel(hs)
    h = hs(jj);
    if ~ishghandle(h) || isequal(h,f)
        continue;
    end

    typ = ''; sty = ''; str = '';
    try, typ = get(h,'Type'); catch, end
    try, sty = lower(char(get(h,'Style'))); catch, end
    try
        tmp = get(h,'String');
        if ischar(tmp), str = tmp; end
    catch
    end

    isControl = strcmpi(typ,'uicontrol') || strcmpi(typ,'uipanel') || strcmpi(typ,'axes') || strcmpi(typ,'uitable');
    if ~isControl
        continue;
    end

    try, set(h,'FontName','Arial'); catch, end

    fsTarget = minFont;
    lowStr = lower(str);

    if strcmpi(typ,'uipanel')
        fsTarget = max(minFont, minFont + 1);
    elseif strcmp(sty,'pushbutton')
        fsTarget = buttonFont;
    elseif strcmp(sty,'edit') || strcmp(sty,'popupmenu') || strcmp(sty,'listbox')
        fsTarget = minFont;
    elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
        fsTarget = minFont;
    elseif strcmp(sty,'text')
        fsTarget = minFont;
    end

    if localHasAny(lowStr,{'scrubbing','frame rejection','temporal smoothing','subsampling','filtering','butterworth','segmentation','functional connectivity'})
        fsTarget = titleFont;
        try, set(h,'FontWeight','bold'); catch, end
    end

    fsTarget = min(maxFont, max(minFont, fsTarget));
    try
        fsOld = get(h,'FontSize');
        if isempty(fsOld) || ~isnumeric(fsOld) || ~isfinite(fsOld) || fsOld < fsTarget
            set(h,'FontSize',fsTarget);
        end
    catch
    end

    try
        hu = get(h,'Units');
        set(h,'Units','pixels');
        p = get(h,'Position');
        if isnumeric(p) && numel(p) >= 4
            if strcmp(sty,'pushbutton')
                p(3) = max(p(3), 150);
                p(4) = max(p(4), editH + 6);
            elseif strcmp(sty,'edit') || strcmp(sty,'popupmenu')
                p(4) = max(p(4), editH);
            elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
                p(4) = max(p(4), editH - 4);
                p(3) = max(p(3), 220);
            elseif strcmp(sty,'text')
                p(4) = max(p(4), editH - 6);
            end
            set(h,'Position',p);
        end
        set(h,'Units',hu);
    catch
    end

    try
        if strcmp(sty,'pushbutton')
            set(h,'FontWeight','bold');
        end
    catch
    end
end
end


function localPolishSegmentationSpecific(f)
% Extra layout cleanup for the Atlas Segmentation popup.
% NO-VIBRATE PATCH: apply figure size only once per popup.
try
    alreadySized = false;
    try, alreadySized = isappdata(f,'HUMoR_SEGMENTATION_SIZE_FIXED_NO_VIBRATE'); catch, end
    if ~alreadySized
        set(f,'Units','pixels');
        scr = get(0,'ScreenSize');
        targetW = min(1680, max(1300, scr(3)-70));
        targetH = min(980,  max(820,  scr(4)-90));
        pos = [max(20,round((scr(3)-targetW)/2)) max(30,round((scr(4)-targetH)/2)) targetW targetH];
        set(f,'Position',pos);
        setappdata(f,'HUMoR_SEGMENTATION_SIZE_FIXED_NO_VIBRATE',true);
    end
catch
end

try
    hs = findall(f,'Type','uicontrol');
catch
    return;
end

for ii = 1:numel(hs)
    h = hs(ii);
    try, sty = lower(char(get(h,'Style'))); catch, sty = ''; end
    try
        s = get(h,'String');
        if iscell(s), s = strjoin(s,' '); end
        if ~ischar(s), s = ''; end
    catch
        s = '';
    end
    low = lower(s);

    try, set(h,'FontName','Arial'); catch, end

    % Main title: readable but not huge.
    if strcmp(sty,'text') && ~isempty(strfind(low,'atlas segmentation'))
        try, set(h,'FontSize',21,'FontWeight','bold'); catch, end
    elseif strcmp(sty,'text') && ~isempty(strfind(low,'segmentation means'))
        try, set(h,'FontSize',16,'FontWeight','bold'); catch, end
    elseif strcmp(sty,'text')
        try
            fs = get(h,'FontSize');
            if isnumeric(fs) && fs > 15
                set(h,'FontSize',15);
            elseif isnumeric(fs) && fs < 12
                set(h,'FontSize',12);
            end
        catch
        end
    elseif strcmp(sty,'pushbutton')
        try, set(h,'FontSize',15,'FontWeight','bold'); catch, end
    elseif strcmp(sty,'popupmenu') || strcmp(sty,'edit')
        try, set(h,'FontSize',13); catch, end
    elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
        try, set(h,'FontSize',13); catch, end
    end

    % Keep controls tall enough but do not let text fields become oversized.
    try
        oldU = get(h,'Units');
        set(h,'Units','pixels');
        p = get(h,'Position');
        if isnumeric(p) && numel(p) >= 4
            if strcmp(sty,'pushbutton')
                p(4) = max(34,min(p(4),48));
                p(3) = max(p(3),120);
            elseif strcmp(sty,'popupmenu') || strcmp(sty,'edit')
                p(4) = max(30,min(p(4),40));
            elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
                p(4) = max(24,min(p(4),36));
            elseif strcmp(sty,'text')
                p(4) = max(22,min(p(4),42));
                if ~isempty(strfind(low,'segmentation means'))
                    p(4) = max(p(4),34);
                end
            end
            set(h,'Position',p);
        end
        set(h,'Units',oldU);
    catch
    end
end
end

