function varargout = computeGabrielSignalChange(varargin)
% Compatibility wrapper. Preferred function: computeImregdemonsSignalChange.
if exist('computeImregdemonsSignalChange','file') ~= 2
    error('computeGabrielSignalChange:MissingPreferredFunction', 'Preferred function computeImregdemonsSignalChange was not found on the MATLAB path.');
end
if nargout == 0
    computeImregdemonsSignalChange(varargin{:});
else
    [varargout{1:nargout}] = computeImregdemonsSignalChange(varargin{:});
end
end


