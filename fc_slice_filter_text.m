function txt = fc_slice_filter_text(s)
try
    if isfield(s,'sliceRegionOnly') && s.sliceRegionOnly
        txt = sprintf('Z %d/%d only',s.slice,s.Z);
    else
        txt = sprintf('all regions; Z %d/%d display',s.slice,s.Z);
    end
catch
    txt = 'all regions';
end
end
