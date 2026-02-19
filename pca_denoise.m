function [newData, stats] = pca_denoise(dataStruct, saveRoot, tag)

% ==========================================================
% SAFE + FAST PCA FOR fUSI STUDIO
% - Masked variance PCA
% - Mean restored
% - Preserves datatype
% - Saves newData struct
% - Studio-compatible
% ==========================================================

if nargin < 3 || isempty(tag)
    tag = datestr(now,'yyyymmdd_HHMMSS');
end

if nargin < 2 || isempty(saveRoot)
    saveRoot = pwd;
end

I = dataStruct.I;
origClass = class(I);

sz = size(I);

if ndims(I)==3
    Y=sz(1); X=sz(2); T=sz(3); Z=1;
    I4D = reshape(I,Y,X,1,T);
else
    Y=sz(1); X=sz(2); Z=sz(3); T=sz(4);
    I4D = I;
end

%% ---------------------------------------------------------
% Reshape
%% ---------------------------------------------------------
flat = reshape(double(I4D),[],T)';

% Remove mean (store it)
meanVol = mean(flat,1);
flat = flat - meanVol;

%% ---------------------------------------------------------
% Variance mask (keep top 10%)
%% ---------------------------------------------------------
voxelStd = std(flat,0,1);
[~,idx] = sort(voxelStd,'descend');

keepN = max(2000, round(0.1*numel(voxelStd)));
flatReduced = flat(:, idx(1:keepN));

%% ---------------------------------------------------------
% Economy SVD (fast)
%% ---------------------------------------------------------
nComp = min(25,T);
[U,S,V] = svd(flatReduced,'econ');

score = U(:,1:nComp)*S(1:nComp,1:nComp);
coeff = V(:,1:nComp);

singVals = diag(S).^2;
explained = 100*singVals(1:nComp)/sum(singVals);

%% ---------------------------------------------------------
% Interactive Selection
%% ---------------------------------------------------------
dropMask = false(1,nComp);

fig = figure('Name','PCA Components','Color','w');
set(fig,'KeyPressFcn',@keyHandler);

for i=1:nComp
    subplot(5,5,i)
    comp = score(:,i);
    comp = comp/std(comp);
    plot(comp,'k','LineWidth',0.8)
    title(sprintf('PC%d (%.1f%%)',i,explained(i)))
    set(gca,'ButtonDownFcn',{@clickHandler,i});
    set(gca,'XTick',[],'YTick',[]);
end

annotation(fig,'textbox',[0 0.96 1 0.04],...
    'String','Click PCs to drop (red). Press ENTER.',...
    'HorizontalAlignment','center',...
    'EdgeColor','none','FontWeight','bold');

uiwait(fig);

%% ---------------------------------------------------------
% Apply dropped components
%% ---------------------------------------------------------
score(:,dropMask)=0;

% Reconstruct reduced space
reconReduced = score*coeff';

% Insert back into full voxel space
flat(:,idx(1:keepN)) = reconReduced;

% Add mean back
flat = flat + meanVol;

recon = reshape(flat',Y,X,Z,T);

% Cast back to original datatype
recon = cast(recon,origClass);

%% ---------------------------------------------------------
% Build newData struct (IMPORTANT)
%% ---------------------------------------------------------
newData = dataStruct;
newData.I = recon;
newData.preprocessing = 'PCA (variance masked)';
newData.pcaDropped = find(dropMask);
newData.pcaExplained = explained;

%% ---------------------------------------------------------
% Save newData (lazy load compatible)
%% ---------------------------------------------------------
pcaFile = fullfile(saveRoot,'Preprocessing',...
          ['pca_cleaned_' tag '.mat']);

save(pcaFile,'newData','-v7.3');

%% ---------------------------------------------------------
% Save QC PNG
%% ---------------------------------------------------------
qcDir = fullfile(saveRoot,'Preprocessing','QC_PCA');
if ~exist(qcDir,'dir'), mkdir(qcDir); end

qcFile = fullfile(qcDir,['PCA_grid_' tag '.png']);
saveas(fig,qcFile);
close(fig);

%% ---------------------------------------------------------
% Stats
%% ---------------------------------------------------------
stats.percentExplainedRemoved = sum(explained(dropMask));
stats.qcFile = qcFile;
stats.pcaFile = pcaFile;

%% ==========================================================
% Nested functions
%% ==========================================================

    function clickHandler(~,~,id)
        dropMask(id)=~dropMask(id);
        if dropMask(id)
            title(sprintf('PC%d ?',id),'Color','r')
        else
            title(sprintf('PC%d (%.1f%%)',id,explained(id)),'Color','k')
        end
    end

    function keyHandler(~,event)
        if strcmp(event.Key,'return')
            uiresume(fig);
        end
    end

end
