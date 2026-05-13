function p = HUMOR_redirect_imreg_save_file(varargin)
% HUMOR_REDIRECT_VARARGIN_PATCH_V2
if nargin == 0
    p = '';
elseif nargin == 1
    p = varargin{1};
else
    p = fullfile(varargin{:});
end
% Redirect imregdemons/demons MAT output to short local path.
% MATLAB 2017b compatible.
try
    try
        if isstring(p), p = char(p); end
    catch
    end

    if ~ischar(p) || isempty(p)
        return;
    end

    src = p;
    low = lower(src);

    if isempty(strfind(low,'imreg')) && isempty(strfind(low,'demons'))
        return;
    end

    [folder,base,ext] = fileparts(src);
    if isempty(ext), ext = '.mat'; end

    method = 'median';
    nsub = 'x';
    tok = regexpi(base,'imregdemons[_\-]([A-Za-z0-9]+)[_\-]nsub([0-9]+)','tokens','once');
    if isempty(tok)
        tok = regexpi(base,'imreg[_\-]([A-Za-z0-9]+)[_\-]nsub([0-9]+)','tokens','once');
    end
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

    datasetKey = 'dataset';
    try
        [parentFolder,thisFolder] = fileparts(folder);
        if strcmpi(thisFolder,'Preprocessing') || strcmpi(thisFolder,'P')
            [~,datasetKey] = fileparts(parentFolder);
        else
            datasetKey = thisFolder;
        end
    catch
    end

    datasetKey = regexprep(datasetKey,'[^A-Za-z0-9_\-]','_');
    datasetKey = regexprep(datasetKey,'_+','_');
    datasetKey = regexprep(datasetKey,'^_+|_+$','');
    if isempty(datasetKey), datasetKey = 'dataset'; end

    outRoot = 'C:\Data\HUMOR_Imregdemons_Output';
    if exist(outRoot,'dir') ~= 7, mkdir(outRoot); end

    outFolder = fullfile(outRoot,datasetKey);
    if exist(outFolder,'dir') ~= 7, mkdir(outFolder); end

    newBase = sprintf('imreg_%s_nsub%s_%s',method,nsub,ts);
    newBase = regexprep(newBase,'[^A-Za-z0-9_\-]','_');
    cand = fullfile(outFolder,[newBase ext]);

    if exist(cand,'file') == 2
        for k = 1:999
            cand2 = fullfile(outFolder,sprintf('%s_dup%03d%s',newBase,k,ext));
            if exist(cand2,'file') ~= 2
                cand = cand2;
                break;
            end
        end
    end

    if ~strcmp(src,cand)
        fprintf('\n[HUMoR] REDIRECTING imregdemons MAT output:\nOLD: %s\nNEW: %s\n',src,cand);
        p = cand;
    end

catch ME
    try
        fprintf('\n[HUMoR] redirect helper warning: %s\n',ME.message);
    catch
    end
end
end
