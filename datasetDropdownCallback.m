function datasetDropdownCallback(src,~)
fig = ancestor(src,'figure');
if isempty(fig) || ~ishghandle(fig), return; end
studio = guidata(fig);
keys = get(src,'UserData');
if isempty(keys) || ~iscell(keys), return; end
idx = get(src,'Value');
idx = max(1,min(numel(keys),idx));
studio.activeDataset = keys{idx};
guidata(fig,studio);
if isfield(studio,'activeDatasetText') && ishghandle(studio.activeDatasetText)
    fullName = localGetName(studio,studio.activeDataset);
    set(studio.activeDatasetText,'String',['ACTIVE DATASET: ' localShort(fullName,85)],'TooltipString',['ACTIVE DATASET: ' fullName]);
end
end

function name = localGetName(studio,key)
name = key;
try
    d = studio.datasets.(key);
    if isstruct(d) && isfield(d,'displayNameFull') && ~isempty(d.displayNameFull)
        name = d.displayNameFull;
    end
catch
end
end

function s = localShort(s,n)
if nargin < 2, n = 85; end
if numel(s) > n
    s = [s(1:ceil((n-3)/2)) '...' s(end-floor((n-3)/2)+1:end)];
end
end
