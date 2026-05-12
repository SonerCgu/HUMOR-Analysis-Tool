% HUMOR_SAFE_ARCHIVE_CLEANUP.m
% Conservative cleanup for HUMOR-Analysis-Tool.
% It DOES NOT delete anything. It moves only obvious backup/report/inventory files
% into an archive folder that should not be on the MATLAB path.
%
% Usage in MATLAB Command Window:
%   cd('D:\Github\HUMOR-Analysis-Tool');
%   run('HUMOR_SAFE_ARCHIVE_CLEANUP.m');
%
% After running, test with:
%   restoredefaultpath;
%   cd('D:\Github\HUMOR-Analysis-Tool');
%   addpath(pwd); rehash; clear functions;
%   which -all run_fusi_studio fusi_studio GroupAnalysis SCM_gui mask
%   run_fusi_studio

rootDir = 'D:\Github\HUMOR-Analysis-Tool';
if ~exist(rootDir,'dir')
    rootDir = pwd;
end
cd(rootDir);

stamp = datestr(now,'yyyymmdd_HHMMSS');
archiveDir = fullfile(rootDir, ['_ARCHIVE_REVIEW_NOT_ON_PATH_' stamp]);
if ~exist(archiveDir,'dir'), mkdir(archiveDir); end

items = { ...
    'GA_exportGroupAnalysisPPTBundleFix_20260504.m.backup_20260511_154841', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260504.m.backup_20260511_170030', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511.m.backup_20260511_170029', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511.m.backup_logic_bundlefinder_20260511_170634', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511.m.backup_missing_ga_table_files_20260511_171537', ...
    'GroupAnalysis.m.backup_before_export_fix_20260511_150237', ...
    'GroupAnalysis.m.backup_before_export_fix_20260511_20260511_152412', ...
    'GroupAnalysis.m.backup_before_exportppt_fix_20260511_151710', ...
    'GroupAnalysis.m.backup_before_fast_export_20260511C_20260511_153907', ...
    'GroupAnalysis.m.backup_before_timeseries_export_fix_20260511B_20260511_153006', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_BACKUP_20260511_172713.m', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_BACKUP_20260511_173537.m', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_BACKUP_BEFORE_FINAL_20260511_183736.m', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_backup_TextBoxFix_20260511_202728.m', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_BEFORE_DOUBLECALL_PATCH_20260511_174255.m', ...
    'GA_exportGroupAnalysisPPTBundleFix_20260511_BROKEN_PARSER_20260511_174850.m', ...
    '_backup_GA_exportGroupAnalysisPPTBundleFix_before_PPT_stylefix_20260511_205134.m', ...
    '_backup_before_GA_PPT_visual_fix_20260511_211852', ...
    '_backup_before_mask_scm_bundle_patch_20260511_212749', ...
    '_health_reports', ...
    '_repo_mfile_inventory_20260511_174618', ...
    '_legacy_unused' ...
};

fprintf('\nHUMOR safe archive cleanup\n');
fprintf('Root:    %s\n', rootDir);
fprintf('Archive: %s\n\n', archiveDir);

moved = 0;
missing = 0;
failed = 0;
for i = 1:numel(items)
    src = fullfile(rootDir, items{i});
    dst = fullfile(archiveDir, items{i});
    if exist(src,'file') || exist(src,'dir')
        dstParent = fileparts(dst);
        if ~exist(dstParent,'dir'), mkdir(dstParent); end
        try
            movefile(src, dst);
            moved = moved + 1;
            fprintf('[MOVED]   %s\n', items{i});
        catch ME
            failed = failed + 1;
            fprintf(2,'[FAILED]  %s\n         %s\n', items{i}, ME.message);
        end
    else
        missing = missing + 1;
        fprintf('[MISSING] %s\n', items{i});
    end
end

% Make sure the archive is not active in this MATLAB session.
try
    rmpath(genpath(archiveDir));
catch
end
rehash;
clear functions;

fprintf('\nDone. Moved: %d | Missing: %d | Failed: %d\n', moved, missing, failed);
fprintf('Nothing was deleted. Keep the archive until you have tested fUSI Studio, GroupAnalysis, SCM, Video GUI, Mask Editor, Registration, and FC.\n');
fprintf('\nRecommended clean test commands:\n');
fprintf('restoredefaultpath; cd(''%s''); addpath(pwd); rehash; clear functions;\n', rootDir);
fprintf('which -all run_fusi_studio fusi_studio GroupAnalysis SCM_gui mask\n');
fprintf('run_fusi_studio\n');
