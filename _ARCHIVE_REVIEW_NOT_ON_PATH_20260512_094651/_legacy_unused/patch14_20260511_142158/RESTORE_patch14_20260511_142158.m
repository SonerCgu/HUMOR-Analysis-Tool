% Restore files moved by Patch 14
root = 'D:\Github\HUMOR-Analysis-Tool';
quarantineDir = 'D:\Github\HUMOR-Analysis-Tool\_legacy_unused\patch14_20260511_142158';

filesToRestore = { ...
    'autoThreshold.m'; ...
};

for k = 1:numel(filesToRestore)
    src = fullfile(quarantineDir, filesToRestore{k});
    dst = fullfile(root, filesToRestore{k});
    if exist(src,'file')
        movefile(src,dst);
        fprintf('Restored: %s\n', filesToRestore{k});
    else
        fprintf('Missing in quarantine: %s\n', filesToRestore{k});
    end
end
rehash; clear functions;
