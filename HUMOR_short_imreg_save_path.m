function p = HUMOR_short_imreg_save_path(p)
% HUMOR_short_imreg_save_path
% Shortens imregdemons/demons MAT output paths before save().
% MATLAB 2017b compatible.

try
    try
        if isstring(p)
            p = char(p);
        end
    catch
    end

    if ~ischar(p) || isempty(p)
        return;
    end

    [folder,base,ext] = fileparts(p);
    if isempty(folder)
        folder = pwd;
    end
    if isempty(ext)
        ext = '.mat';
    end

    fullLow = lower([folder filesep base ext]);

    % Only change imregdemons/demons outputs.
    if isempty(strfind(fullLow,'imreg')) && isempty(strfind(fullLow,'demons'))
        return;
    end

    % If path is already safe, keep it.
    if numel(p) < 220 && numel(base) < 80
        return;
    end

    method = 'median';
    nsub = 'x';

    tok = regexpi(base,'imregdemons[_\-]([A-Za-z0-9]+)[_\-]nsub([0-9]+)','tokens','once');
    if ~isempty(tok)
        method = tok{1};
        nsub = tok{2};
    end

    tsTok = regexp(base,'\d{8}_\d{6}','match');
    if ~isempty(tsTok)
        ts = tsTok{end};
    else
        ts = datestr(now,'yyyymmdd_HHMMSS');
    end

    newBase = sprintf('imreg_%s_nsub%s_%s', method, nsub, ts);
    newBase = regexprep(newBase,'[^A-Za-z0-9_\-]','_');

    outFolder = folder;
    cand = fullfile(outFolder,[newBase ext]);

    % If still too long, use short sibling folder P next to Preprocessing.
    if numel(cand) > 240
        [parentFolder,thisFolder] = fileparts(folder);
        if strcmpi(thisFolder,'Preprocessing')
            outFolder = fullfile(parentFolder,'P');
        else
            outFolder = fullfile(folder,'P');
        end
        if exist(outFolder,'dir') ~= 7
            mkdir(outFolder);
        end
        cand = fullfile(outFolder,[newBase ext]);
    end

    % Final emergency shortening.
    if numel(cand) > 240
        newBase = sprintf('irg_%s', ts);
        cand = fullfile(outFolder,[newBase ext]);
    end

    % Avoid overwrite.
    if exist(cand,'file') == 2
        for k = 1:999
            cand2 = fullfile(outFolder,sprintf('%s_dup%03d%s',newBase,k,ext));
            if exist(cand2,'file') ~= 2
                cand = cand2;
                break;
            end
        end
    end

    if ~strcmp(p,cand)
        fprintf('\n[HUMoR] Imregdemons save path shortened:\nOLD: %s\nNEW: %s\n', p, cand);
        p = cand;
    end

catch ME
    try
        fprintf('\n[HUMoR] HUMOR_short_imreg_save_path warning: %s\n', ME.message);
    catch
    end
end
end
