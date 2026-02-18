function par = preproc_param_gui(par)
% Simple parameter dialog for preprocessing

prompt = {
    'LPF (0–1, 0 = off):'
    'HPF (0–1, 0 = off):'
    'Gaussian size:'
    'Gaussian sigma:'
};

def = {
    num2str(par.LPF)
    num2str(par.HPF)
    num2str(par.gaussSize)
    num2str(par.gaussSig)
};

answ = inputdlg(prompt,'Preprocessing parameters',1,def);

if isempty(answ)
    % User cancelled ? keep previous parameters
    return;
end

par.LPF       = str2double(answ{1});
par.HPF       = str2double(answ{2});
par.gaussSize = round(str2double(answ{3}));
par.gaussSig  = str2double(answ{4});

% Optional (safe default, ignored unless used)
if ~isfield(par,'temporalWin')
    par.temporalWin = 10;
end

end
