function HUMoR_segmentation_popup_fix_now(varargin)
% HUMoR_segmentation_popup_fix_now
% Dedicated Atlas Segmentation popup polish.
% MATLAB 2017b compatible.

if nargin >= 1 && ~isempty(varargin{1}) && ishghandle(varargin{1})
    figs = varargin{1};
else
    figs = findall(0,'Type','figure');
end

for fi = 1:numel(figs)
    f = figs(fi);
    if ~ishghandle(f), continue; end
    try
        nm = lower(char(get(f,'Name')));
    catch
        nm = '';
    end

    if isempty(nm)
        continue;
    end

    isSeg = ~isempty(strfind(nm,'segmentation')) || ~isempty(strfind(nm,'region-time'));
    isAtlas = ~isempty(strfind(nm,'atlas')) || ~isempty(strfind(nm,'humor'));

    if isSeg && isAtlas
        localFixSegmentationFigure(f);
    end
end
end

function localFixSegmentationFigure(f)
try
    oldFigUnits = get(f,'Units');
    set(f,'Units','pixels');
catch
    oldFigUnits = 'pixels';
end

% Large but screen-safe size.
try
    scr = get(0,'ScreenSize');
    targetW = min(1780, max(1450, scr(3)-70));
    targetH = min(1030, max(880,  scr(4)-110));
    targetX = max(10, round((scr(3)-targetW)/2));
    targetY = max(35, round((scr(4)-targetH)/2));
    targetPos = [targetX targetY targetW targetH];
catch
    targetPos = [10 35 1650 940];
end

doScale = true;
try
    if isappdata(f,'HUMoR_SEG_PATCH30B_DONE')
        doScale = false;
    end
catch
end

try
    oldPos = get(f,'Position');
    if numel(oldPos) < 4 || oldPos(3) <= 0 || oldPos(4) <= 0
        oldPos = targetPos;
    end
    set(f,'Position',targetPos);
catch
    oldPos = targetPos;
end

if doScale
    sx = targetPos(3) / max(1,oldPos(3));
    sy = targetPos(4) / max(1,oldPos(4));
    sx = min(max(sx,1.00),1.25);
    sy = min(max(sy,1.00),1.22);
    localScaleControls(f,sx,sy);
    try, setappdata(f,'HUMoR_SEG_PATCH30B_DONE',true); catch, end
end

localStyleControls(f);
localHideBottomStatus(f);

try, set(f,'Units',oldFigUnits); catch, end
drawnow;
end

function localScaleControls(f,sx,sy)
try
    hs = findall(f);
catch
    return;
end

for ii = 1:numel(hs)
    h = hs(ii);
    if isequal(h,f), continue; end
    try
        typ = lower(char(get(h,'Type')));
    catch
        typ = '';
    end

    if ~(strcmp(typ,'uicontrol') || strcmp(typ,'uipanel') || strcmp(typ,'axes'))
        continue;
    end

    try
        oldUnits = get(h,'Units');
        set(h,'Units','pixels');
        p = get(h,'Position');
        if isnumeric(p) && numel(p) >= 4
            p(1) = round(p(1)*sx);
            p(2) = round(p(2)*sy);
            p(3) = round(p(3)*sx);
            p(4) = round(p(4)*sy);
            set(h,'Position',p);
        end
        set(h,'Units',oldUnits);
    catch
    end
end
end

function localStyleControls(f)
try
    set(f,'Color',[0.05 0.06 0.08]);
catch
end

try
    panels = findall(f,'Type','uipanel');
catch
    panels = [];
end

for ii = 1:numel(panels)
    try
        set(panels(ii),'FontName','Arial','FontSize',18,'FontWeight','bold');
    catch
    end
end

try
    hs = findall(f,'Type','uicontrol');
catch
    hs = [];
end

for ii = 1:numel(hs)
    h = hs(ii);
    try
        sty = lower(char(get(h,'Style')));
    catch
        sty = '';
    end

    s = localGetString(h);
    low = lower(s);

    try, set(h,'FontName','Arial'); catch, end

    if strcmp(sty,'text')
        if ~isempty(strfind(low,'atlas segmentation'))
            fs = 30; fw = 'bold';
        elseif ~isempty(strfind(low,'segmentation means'))
            fs = 17; fw = 'bold';
        elseif ~isempty(strfind(low,'active data:'))
            fs = 15; fw = 'bold';
        elseif ~isempty(strfind(low,'functional source')) || ~isempty(strfind(low,'atlas / label source')) || ~isempty(strfind(low,'baseline and extraction'))
            fs = 18; fw = 'bold';
        elseif ~isempty(strfind(low,'functional data')) || ~isempty(strfind(low,'label source')) || ~isempty(strfind(low,'baseline start')) || ~isempty(strfind(low,'baseline end')) || ~isempty(strfind(low,'minimum voxels'))
            fs = 16; fw = 'bold';
        else
            fs = 14; fw = 'bold';
        end
        try, set(h,'FontSize',fs,'FontWeight',fw); catch, end

    elseif strcmp(sty,'pushbutton')
        try, set(h,'FontSize',17,'FontWeight','bold'); catch, end

    elseif strcmp(sty,'popupmenu')
        try, set(h,'FontSize',16,'FontWeight','bold'); catch, end

    elseif strcmp(sty,'edit')
        try, set(h,'FontSize',17,'FontWeight','bold'); catch, end

    elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
        try, set(h,'FontSize',16,'FontWeight','bold'); catch, end
    end

    localEnforceControlSize(h,sty,low);
end
end

function localEnforceControlSize(h,sty,low)
try
    oldUnits = get(h,'Units');
    set(h,'Units','pixels');
    p = get(h,'Position');
    if ~isnumeric(p) || numel(p) < 4
        set(h,'Units',oldUnits);
        return;
    end

    if strcmp(sty,'pushbutton')
        p(4) = max(p(4),42);
        p(3) = max(p(3),140);
        if ~isempty(strfind(low,'run segmentation')) || ~isempty(strfind(low,'cancel'))
            p(4) = max(p(4),56);
            p(3) = max(p(3),285);
        end

    elseif strcmp(sty,'popupmenu')
        p(4) = max(p(4),38);
        p(3) = max(p(3),330);

    elseif strcmp(sty,'edit')
        p(4) = max(p(4),36);
        p(3) = max(p(3),130);

    elseif strcmp(sty,'checkbox') || strcmp(sty,'radiobutton')
        p(4) = max(p(4),32);

    elseif strcmp(sty,'text')
        if ~isempty(strfind(low,'atlas segmentation'))
            p(4) = max(p(4),46);
        elseif ~isempty(strfind(low,'segmentation means'))
            p(4) = max(p(4),32);
        else
            p(4) = max(p(4),26);
        end
    end

    set(h,'Position',p);
    set(h,'Units',oldUnits);
catch
end
end

function localHideBottomStatus(f)
try
    hs = findall(f,'Type','uicontrol');
catch
    hs = [];
end

for ii = 1:numel(hs)
    h = hs(ii);
    try
        sty = lower(char(get(h,'Style')));
    catch
        sty = '';
    end

    if ~strcmp(sty,'text')
        continue;
    end

    s = localGetString(h);
    low = lower(s);

    try
        oldUnits = get(h,'Units');
        set(h,'Units','pixels');
        p = get(h,'Position');
        set(h,'Units',oldUnits);
    catch
        p = [0 9999 0 0];
    end

    isBottom = p(2) < 190;
    looksMisleading = false;
    keys = {'active data','manual atlas','baseline','psc off','requested baseline','frames 1-','min voxels'};
    for kk = 1:numel(keys)
        if ~isempty(strfind(low,keys{kk}))
            looksMisleading = true;
            break;
        end
    end

    if isBottom && looksMisleading
        try
            set(h,'String','','Visible','off');
        catch
        end
    end
end
end

function s = localGetString(h)
s = '';
try
    x = get(h,'String');
    if iscell(x)
        tmp = '';
        for jj = 1:numel(x)
            try
                tmp = [tmp ' ' char(x{jj})]; %#ok<AGROW>
            catch
            end
        end
        s = tmp;
    elseif ischar(x)
        s = x;
    else
        try, s = char(x); catch, s = ''; end
    end
catch
    s = '';
end
end
