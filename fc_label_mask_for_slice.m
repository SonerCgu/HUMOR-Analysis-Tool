function mask = fc_label_mask_for_slice(atlasS,lab)
atlasS = round(double(atlasS));
lab = round(double(lab));
mask = atlasS == lab;
if ~any(mask(:))
    mask = abs(atlasS) == abs(lab);
end
end
