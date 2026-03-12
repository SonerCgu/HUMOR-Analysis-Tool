function Transf = coreg(studio, mode)
% coreg.m
% Entry point that lets the user choose between:
%   - complex 3D atlas registration
%   - simple 2D coronal registration
%
% ASCII only
% MATLAB 2017b compatible

Transf = [];

if nargin < 2 || isempty(mode)
    choice = questdlg( ...
        ['Choose atlas registration mode:' char(10) char(10) ...
         'Complex 3D = full atlas GUI (existing workflow)' char(10) ...
         'Simple 2D  = easy coronal manual alignment for atlas underlay visualization'], ...
        'Atlas Registration Mode', ...
        'Simple 2D','Complex 3D','Cancel', ...
        'Simple 2D');

    if isempty(choice) || strcmpi(choice,'Cancel')
        return;
    end

    if strcmpi(choice,'Simple 2D')
        mode = '2d';
    else
        mode = '3d';
    end
end

mode = lower(strtrim(mode));

switch mode
    case {'2d','simple','simple2d','coronal','coronal2d'}
        Transf = coreg_coronal_2d(studio);

    case {'3d','complex','complex3d'}
        if exist('coreg_3d','file') ~= 2
            error(['coreg_3d.m not found.' char(10) ...
                   'Please save your current complex 3D coreg code as coreg_3d.m ' ...
                   'and change its first line to: function Transf = coreg_3d(studio)']);
        end
        Transf = coreg_3d(studio);

    otherwise
        error('Unknown mode. Use ''2d'' or ''3d''.');
end
end