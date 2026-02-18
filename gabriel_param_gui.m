function par = gabriel_param_gui(par)
% gabriel_param_gui
% ------------------------------------------------------------
% Parameter dialog for Gabriel preprocessing.
% ONLY spatial-domain parameters are allowed here.
%
% Allowed:
%   - Gaussian spatial smoothing
%
% Disallowed (intentionally):
%   - LPF / HPF
%   - Temporal interpolation
%
% Author: Soner Caner Cagun
% Refactor: Naman Jain
% ------------------------------------------------------------

prompt = {
    'Gaussian size (0 = off):'
    'Gaussian sigma:'
};

def = {
    num2str(par.gaussSize)
    num2str(par.gaussSig)
};

answ = inputdlg(prompt, 'Gabriel preprocessing parameters', 1, def);

if isempty(answ)
    return;
end


par.gaussSize = round(str2double(answ{1}));
par.gaussSig  = str2double(answ{2});

% Safety
if isnan(par.gaussSize) || par.gaussSize < 0
    par.gaussSize = 0;
end

if isnan(par.gaussSig) || par.gaussSig <= 0
    par.gaussSig = 1;
end

end
