function T = fc_region_names_from_region_struct(r)
T = struct('labels',[],'names',{{}});
try
    if ~isstruct(r), return; end
    if isfield(r,'labels'), labs = double(r.labels(:)); else, labs = []; end
    names = {};
    if isfield(r,'names') && ~isempty(r.names)
        names = cellstr(r.names(:));
    elseif isfield(r,'acronyms') && ~isempty(r.acronyms)
        names = cellstr(r.acronyms(:));
    end
    if isempty(labs) || isempty(names), return; end
    n = min(numel(labs),numel(names));
    T.labels = labs(1:n);
    T.names = names(1:n);
catch
    T = struct('labels',[],'names',{{}});
end
end
