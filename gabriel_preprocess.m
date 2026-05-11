function varargout = gabriel_preprocess(varargin)
% Compatibility wrapper. Preferred function: imregdemons_preprocess.
if exist('imregdemons_preprocess','file') ~= 2
    error('gabriel_preprocess:MissingPreferredFunction', 'Preferred function imregdemons_preprocess was not found on the MATLAB path.');
end
if nargout == 0
    imregdemons_preprocess(varargin{:});
else
    [varargout{1:nargout}] = imregdemons_preprocess(varargin{:});
end
end


