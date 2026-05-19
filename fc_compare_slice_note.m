function note = fc_compare_slice_note(s,lab)
note = '';
try
    subj = s.subjects(s.currentSubject);
    A = subj.roiAtlas;
    if isempty(A), note = sprintf('Slice Z %d/%d: no atlas loaded',s.slice,s.Z); return; end
    if ndims(A) < 3
        atlasS = round(double(A)); zNow = 1; zMax = 1;
    else
        zNow = max(1,min(size(A,3),round(s.slice))); zMax = size(A,3);
        atlasS = round(double(A(:,:,zNow)));
    end
    exactPix = nnz(atlasS == round(double(lab)));
    absPix = nnz(abs(atlasS) == abs(round(double(lab))));
    if exactPix > 0
        note = sprintf('Slice Z %d/%d: selected region present (%d pixels, exact label)',zNow,zMax,exactPix);
    elseif absPix > 0
        note = sprintf('Slice Z %d/%d: selected region present by absolute label (%d pixels)',zNow,zMax,absPix);
    else
        note = sprintf('Slice Z %d/%d: selected region not present; map shows other slice regions correlated with it',zNow,zMax);
    end
catch
    note = '';
end
end
