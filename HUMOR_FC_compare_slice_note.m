function note = HUMOR_FC_compare_slice_note(s,lab)
note = '';
try
    subj = s.subjects(s.currentSubject);
    A = subj.roiAtlas;
    z = max(1,min(s.Z,round(s.slice)));
    if isempty(A), note = sprintf('Slice Z %d/%d: no atlas loaded',z,s.Z); return; end
    if ndims(A) < 3
        AS = round(double(A));
    else
        AS = round(double(A(:,:,max(1,min(size(A,3),z)))));
    end
    nExact = nnz(AS == round(double(lab)));
    nAbs = nnz(abs(AS) == abs(round(double(lab))));
    if nExact > 0
        note = sprintf('Slice Z %d/%d: selected ROI present (%d pixels)',z,s.Z,nExact);
    elseif nAbs > 0
        note = sprintf('Slice Z %d/%d: selected ROI present by abs label (%d pixels)',z,s.Z,nAbs);
    else
        note = sprintf('Slice Z %d/%d: selected ROI not present in this slice',z,s.Z);
    end
catch
    note = '';
end
end
