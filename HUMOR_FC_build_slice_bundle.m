function sliceResults = HUMOR_FC_build_slice_bundle(s,subIdx,resWhole)
sliceResults = struct([]);
try
    if ~isfield(s,'Z') || s.Z < 1 || isempty(resWhole), return; end
    n = 0;
    for z = 1:s.Z
        ss = s;
        ss.slice = z;
        ss.sliceRegionOnly = true;
        rz = HUMOR_FC_make_slice_roi_result(ss,subIdx,resWhole,z);
        if isempty(rz) || ~isfield(rz,'M') || isempty(rz.M), continue; end
        if ~isfield(rz,'labels') || numel(rz.labels) < 2, continue; end

        n = n + 1;
        R = double(rz.M);
        Zm = atanh(max(-0.999999,min(0.999999,R)));
        Zm(1:size(Zm,1)+1:end) = 0;

        sliceResults(n).sliceIndex = z; %#ok<AGROW>
        sliceResults(n).sliceLabel = sprintf('Slice%03d',z);
        sliceResults(n).labels = rz.labels;
        sliceResults(n).names = rz.names;
        sliceResults(n).counts = rz.counts;
        sliceResults(n).meanTS = rz.meanTS;
        sliceResults(n).R = R;
        sliceResults(n).Z = Zm;
        sliceResults(n).M = R;
        sliceResults(n).statMatrix = Zm;
        sliceResults(n).statSpace = 'Fisher z';
        sliceResults(n).displayMatrix = R;
        sliceResults(n).displaySpace = 'Pearson r';
        if isfield(rz,'timeIdx'), sliceResults(n).timeIdx = rz.timeIdx; else, sliceResults(n).timeIdx = []; end
    end
catch
    sliceResults = struct([]);
end
end
