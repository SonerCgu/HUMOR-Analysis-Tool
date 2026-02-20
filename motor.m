function [I3D, motorInfo] = motor(I, TR, qcFolder)
% =========================================================
% MOTOR RECONSTRUCTION (RAW ONLY, TIME BASED)
% 2D ? 3D reconstruction
% =========================================================

if ndims(I) ~= 3
    error('Motor expects 2D data (Y x X x T).');
end

I = single(I);
[Y,X,T] = size(I);
timeVec = (0:T-1) * TR;

%% --------------------------------------------------------
% USER PARAMETERS
%% --------------------------------------------------------
prompt = { ...
    'Number of slices:', ...
    'Seconds per slice:', ...
    'Discard seconds at transitions:', ...
    'Baseline BEFORE motor start (sec):'};

def = {'7','10','3','30'};
answ = inputdlg(prompt,'Motor parameters',1,def);

if isempty(answ)
    error('Motor cancelled.');
end

nSlices  = str2double(answ{1});
secSlice = str2double(answ{2});
secTrim  = str2double(answ{3});
secBase  = str2double(answ{4});

if any(isnan([nSlices secSlice secTrim secBase]))
    error('Invalid motor parameters.');
end

%% --------------------------------------------------------
% Time based cycle calculation
%% --------------------------------------------------------
cycleDur = nSlices * secSlice;
tMotorStart = secBase;
tMotorEnd   = timeVec(end);

nCycles = floor((tMotorEnd - tMotorStart) / cycleDur);

validDur = secSlice - 2*secTrim;
if validDur <= 0
    error('Trim too large.');
end

volPerSlice = floor(validDur / TR);
Tnew = nCycles * volPerSlice;

if Tnew < 5
    error('Not enough usable data.');
end

%% --------------------------------------------------------
% Preallocate (memory safe)
%% --------------------------------------------------------
I3D = zeros(Y,X,nSlices,Tnew,'single');

%% --------------------------------------------------------
% Reconstruction
%% --------------------------------------------------------
for s = 1:nSlices

    cnt = 0;

    for c = 1:nCycles

        tStart = tMotorStart ...
               + (c-1)*cycleDur ...
               + (s-1)*secSlice ...
               + secTrim;

        tEnd = tStart + validDur;

        idx = find(timeVec >= tStart & timeVec < tEnd);

        if numel(idx) < volPerSlice
            continue
        end

        idx = idx(1:volPerSlice);

        I3D(:,:,s,cnt+1:cnt+volPerSlice) = I(:,:,idx);
        cnt = cnt + volPerSlice;
    end
end

%% --------------------------------------------------------
% QC (RAW BEFORE vs AFTER)
%% --------------------------------------------------------
if ~exist(qcFolder,'dir')
    mkdir(qcFolder);
end

fig = figure('Visible','off','Position',[200 200 1400 900]);

% Global RAW mean
globalRawMean = squeeze(mean(mean(I,1),2));
subplot(nSlices+1,1,1)
plot(globalRawMean,'k','LineWidth',1.2)
title('Global RAW Mean (Entire Dataset)')
ylabel('Intensity')
grid on

for s = 1:nSlices

    subplot(nSlices+1,1,s+1)

    afterMean = squeeze(mean(mean(I3D(:,:,s,:),1),2));

    plot(afterMean,'r','LineWidth',1.2)
    title(['Slice ' num2str(s)])
    ylabel('Intensity')
    legend('After Reconstruction')
    grid on
end

annotation('textbox',[0 0.96 1 0.03],...
    'String','Motor QC - Raw Signal Reconstruction',...
    'EdgeColor','none',...
    'HorizontalAlignment','center',...
    'FontWeight','bold',...
    'FontSize',14);

saveas(fig, fullfile(qcFolder,'motor_QC_full.png'));

close(fig)
clear fig globalRawMean afterMean
drawnow

%% --------------------------------------------------------
% OUTPUT STRUCT
%% --------------------------------------------------------
motorInfo = struct();
motorInfo.nSlices = nSlices;
motorInfo.volumesPerSlice = Tnew;
motorInfo.minutesPerSlice = (Tnew*TR)/60;
motorInfo.TR = TR;
motorInfo.cycles = nCycles;
motorInfo.trimSeconds = secTrim;
motorInfo.sliceSeconds = secSlice;
motorInfo.baselineSeconds = secBase;

clear I
pack

end
