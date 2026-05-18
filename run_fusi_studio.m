function run_fusi_studio()
% run_fusi_studio - clean launcher for split HUMoR / fUSI Studio.
% MATLAB 2017b + 2023b compatible.
%
% Source files kept in toolbox root:
%   fusi_studio_GUI.m
%   fusi_studio_callback.m
%
% A temporary assembled runtime file is created in tempdir because MATLAB
% nested callbacks must exist in one parsed function scope.

root = fileparts(mfilename('fullpath'));
if isempty(root) || exist(root,'dir') ~= 7
    root = pwd;
end

cd(root);

try
    addpath(root,'-begin');
catch
end

% Remove backup/quarantine/report folders from path if they were added earlier.
try
    d = dir(root);
    for k = 1:numel(d)
        if ~d(k).isdir
            continue;
        end
        nm = d(k).name;
        isBadPath = false;
        if numel(nm) >= 8 && strcmp(nm(1:8),'_backup_')
            isBadPath = true;
        end
        if strcmp(nm,'_legacy_unused') || strcmp(nm,'_health_reports') || strcmp(nm,'_archive_review')
            isBadPath = true;
        end
        if isBadPath
            pp = fullfile(root,nm);
            try, rmpath(genpath(pp)); catch, end
        end
    end
catch
end

% Validate split source files.
if exist(fullfile(root,'fusi_studio_GUI.m'),'file') ~= 2
    error('Missing fusi_studio_GUI.m in %s', root);
end
if exist(fullfile(root,'fusi_studio_callback.m'),'file') ~= 2
    error('Missing fusi_studio_callback.m in %s', root);
end

% Assemble temporary runtime outside the toolbox root.
try
    part1 = fusi_studio_GUI('source');
    part2 = fusi_studio_callback('source');
    runtimeCode = [part1 sprintf('\n') part2];

    runtimeDir = fullfile(tempdir,'HUMOR_fUSI_Studio_runtime');
    if exist(runtimeDir,'dir') ~= 7
        mkdir(runtimeDir);
    end
    addpath(runtimeDir,'-begin');

    % HUMOR_ICON_COPY_PATCH_20260518B
    % Runtime lives in tempdir, so copy Icon.png beside fusi_studio_runtime.m.
    try
        iconSrc = fullfile(root,'Icon.png');
        iconDst = fullfile(runtimeDir,'Icon.png');
        if exist(iconSrc,'file') == 2
            copyfile(iconSrc, iconDst);
        end
    catch ME_iconcopy
        warning('HUMoR:IconCopy', 'Could not copy Icon.png: %s', ME_iconcopy.message);
    end

    % HUMOR_ICON_COPY_PATCH_20260518
    % The assembled fusi_studio_runtime.m lives in tempdir, so mfilename
    % inside the runtime points there. Copy Icon.png into the runtime folder.
    try
        iconSrc = fullfile(root,'Icon.png');
        iconDst = fullfile(runtimeDir,'Icon.png');
        if exist(iconSrc,'file') == 2
            copyfile(iconSrc, iconDst);
        end
    catch ME_iconcopy
        warning('HUMoR:IconCopy', 'Could not copy Icon.png to runtime folder: %s', ME_iconcopy.message);
    end

    runtimeFile = fullfile(runtimeDir,'fusi_studio_runtime.m');
    writeFile = true;
    if exist(runtimeFile,'file') == 2
        try
            oldCode = fileread(runtimeFile);
            writeFile = ~strcmp(oldCode, runtimeCode);
        catch
            writeFile = true;
        end
    end

    if writeFile
        fid = fopen(runtimeFile,'w');
        if fid < 0
            error('Could not write temporary runtime file: %s', runtimeFile);
        end
        cleaner = onCleanup(@() fclose(fid));
        fwrite(fid, runtimeCode, 'char');
        clear cleaner;
    end
catch ME
    error('HUMoR:SplitAssemble','Could not assemble fUSI Studio split files: %s', ME.message);
end

% Start popup auto-fit helper if available.
try
    if exist('HUMoR_popup_autofit_timer','file') == 2
        HUMoR_popup_autofit_timer('stop');
        HUMoR_popup_autofit_timer('start');
    end
catch ME
    warning('HUMoR:PopupAutoFit', 'Could not start popup auto-fit timer: %s', ME.message);
end

fprintf('HUMoR / fUSI Studio root:\n%s\n\n', root);

% Launch assembled Studio runtime.
try, HUMoR_popup_autofit_timer('start'); catch, end
rehash;
clear fusi_studio_runtime;
fusi_studio_runtime;

end
