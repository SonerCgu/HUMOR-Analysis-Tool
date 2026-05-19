function keep = HUMOR_FC_slice_keep_indices(s,meta,n,axisName)
keep = [];
try
    subj = s.subjects(s.currentSubject);
    if isempty(subj.roiAtlas), return; end
    A = subj.roiAtlas;
    if ndims(A) < 3
        atlasS = round(double(A));
    else
        z = max(1,min(size(A,3),round(s.slice)));
        atlasS = round(double(A(:,:,z)));
    end
    present = unique(atlasS(isfinite(atlasS) & atlasS ~= 0));
    if isempty(present), return; end
    presentAbs = unique(abs(present));
    for ii = 1:n
        labs = [];
        if isfield(meta,'isRectangular') && meta.isRectangular
            if strcmpi(axisName,'x')
                if isfield(meta,'orderX') && isfield(meta,'rawLabels')
                    idx = meta.orderX(ii); if idx >= 1 && idx <= numel(meta.rawLabels), labs = meta.rawLabels(idx); end
                elseif isfield(meta,'displayLabelsX')
                    labs = meta.displayLabelsX(ii);
                end
            else
                if isfield(meta,'orderY') && isfield(meta,'rawLabels')
                    idx = meta.orderY(ii); if idx >= 1 && idx <= numel(meta.rawLabels), labs = meta.rawLabels(idx); end
                elseif isfield(meta,'displayLabelsY')
                    labs = meta.displayLabelsY(ii);
                end
            end
        else
            if isfield(meta,'groups') && ii <= numel(meta.groups) && isfield(meta,'rawLabels')
                idx = meta.groups{ii}; idx = idx(:);
                idx = idx(idx >= 1 & idx <= numel(meta.rawLabels));
                labs = meta.rawLabels(idx);
            elseif isfield(meta,'displayLabels') && ii <= numel(meta.displayLabels)
                labs = meta.displayLabels(ii);
            end
        end
        labs = round(double(labs(:)));
        labs = labs(isfinite(labs) & labs ~= 0);
        if isempty(labs), continue; end
        if any(ismember(labs,present)) || any(ismember(abs(labs),presentAbs))
            keep(end+1) = ii; %#ok<AGROW>
        end
    end
catch
    keep = [];
end
end
