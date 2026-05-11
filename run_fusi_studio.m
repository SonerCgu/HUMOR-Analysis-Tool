function run_fusi_studio()
% run_fusi_studio - clean launcher for HUMoR / fUSI Studio.
% MATLAB 2017b + 2023b compatible.

root = fileparts(mfilename('fullpath'));
if isempty(root) || exist(root,'dir') ~= 7
    root = pwd;
end

cd(root);

% Keep the main root first on the path.
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
        if strcmp(nm,'_legacy_unused') || strcmp(nm,'_health_reports')
            isBadPath = true;
        end
        if isBadPath
            pp = fullfile(root,nm);
            try, rmpath(genpath(pp)); catch, end
        end
    end
catch
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

% Launch Studio.
try, HUMoR_popup_autofit_timer('start'); catch, end
fusi_studio;

end
