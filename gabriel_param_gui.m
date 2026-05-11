function varargout = gabriel_param_gui(varargin)
% Compatibility wrapper. Preferred function: imregdemons_param_gui.
if exist('imregdemons_param_gui','file') ~= 2
    error('gabriel_param_gui:MissingPreferredFunction', 'Preferred function imregdemons_param_gui was not found on the MATLAB path.');
end
if nargout == 0
    imregdemons_param_gui(varargin{:});
else
    [varargout{1:nargout}] = imregdemons_param_gui(varargin{:});
end
end


