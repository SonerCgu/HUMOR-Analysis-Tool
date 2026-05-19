function region = HUMOR_apply_region_names_to_region(region, nameFile)
% Replace generic Region N names using an external name table.
try
    T = HUMOR_read_region_names_file(nameFile);
    if isempty(T) || ~isstruct(T) || ~isfield(T,'labels') || isempty(T.labels)
        return;
    end
    labsT = abs(round(double(T.labels(:))));
    for ii = 1:numel(region.labels)
        lab = abs(round(double(region.labels(ii))));
        jj = find(labsT == lab,1,'first');
        if isempty(jj), continue; end
        if isfield(T,'acronyms') && jj <= numel(T.acronyms)
            a = strtrim(char(T.acronyms{jj}));
            if ~isempty(a), region.acronyms{ii} = a; end
        end
        if isfield(T,'names') && jj <= numel(T.names)
            n = strtrim(char(T.names{jj}));
            if ~isempty(n), region.names{ii} = n; end
        end
    end
catch
end
end
