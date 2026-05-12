function HUMoR_save_qc_png_white(fig, outFile)
% Save QC figure as true RGB PNG with white background.
% Avoids MATLAB saveas/print transparency and dark-margin issues.

if nargin < 1 || isempty(fig) || ~ishghandle(fig), return; end
if nargin < 2 || isempty(outFile), return; end

try
    outDir = fileparts(outFile);
    if ~isempty(outDir) && exist(outDir,'dir') ~= 7
        mkdir(outDir);
    end
catch
end

isRejected = false;
try
    nm = lower(char(get(fig,'Name')));
    if ~isempty(strfind(nm,'rejected')), isRejected = true; end
catch
end
try
    if ~isempty(strfind(lower(outFile),'rejected')), isRejected = true; end
catch
end

% Make the actual visible figure white before screenshot export.
try
    figure(fig);
    set(fig,'Visible','on');
    set(fig,'Units','pixels');
    scr = get(0,'ScreenSize');
    W = min(1500, max(1200, scr(3)-180));
    if isRejected
        H = min(800, max(680, scr(4)-200));
    else
        H = min(760, max(650, scr(4)-200));
    end
    set(fig,'Position',[60 60 W H]);
    set(fig,'Color',[1 1 1]);
    set(fig,'InvertHardcopy','off');
    set(fig,'PaperPositionMode','auto');
catch
end

% Make all containers white.
try
    objs = findall(fig);
    for i = 1:numel(objs)
        h = objs(i);
        try
            if isprop(h,'BackgroundColor')
                set(h,'BackgroundColor',[1 1 1]);
            end
        catch
        end
    end
catch
end

% Style axes and labels.
try
    axs = findall(fig,'Type','axes');
    for a = 1:numel(axs)
        ax = axs(a);
        try
            set(ax,'Units','normalized');
            set(ax,'Color',[1 1 1]);
            set(ax,'XColor',[0 0 0],'YColor',[0 0 0],'ZColor',[0 0 0]);
            set(ax,'GridColor',[0.75 0.75 0.75]);
            set(ax,'FontSize',13,'FontWeight','bold','LineWidth',1.3,'Box','on');
            set(get(ax,'XLabel'),'Color',[0 0 0],'FontWeight','bold','FontSize',15);
            set(get(ax,'YLabel'),'Color',[0 0 0],'FontWeight','bold','FontSize',15);
            set(get(ax,'Title'),'Color',[0 0 0],'FontWeight','bold','FontSize',17);
            if isRejected
                set(ax,'Position',[0.12 0.19 0.84 0.68]);
                ylim(ax,[-0.15 1.15]);
                set(ax,'YTick',[0 1],'YTickLabel',{'Accepted','Rejected'});
                xlabel(ax,'Time (s)','Color',[0 0 0],'FontWeight','bold','FontSize',15);
                ylabel(ax,'Frame status','Color',[0 0 0],'FontWeight','bold','FontSize',15);
                title(ax,'Rejected volumes over time','Color',[0 0 0],'FontWeight','bold','FontSize',17);
            end
        catch
        end
    end
catch
end

% Text/annotation objects black on white.
try
    objs = findall(fig);
    for i = 1:numel(objs)
        h = objs(i);
        try
            if isprop(h,'Color')
                typ = '';
                try, typ = lower(char(get(h,'Type'))); catch, end
                if strcmp(typ,'text')
                    set(h,'Color',[0 0 0]);
                    set(h,'FontWeight','bold');
                end
            end
            if isprop(h,'LineWidth')
                lw = get(h,'LineWidth');
                if isempty(lw) || lw < 1.8, set(h,'LineWidth',1.8); end
            end
            if isprop(h,'MarkerSize')
                ms = get(h,'MarkerSize');
                if isempty(ms) || ms < 5, set(h,'MarkerSize',5); end
            end
        catch
        end
    end
catch
end

drawnow;
pause(0.10);

% Save actual RGB pixels. This removes transparency completely.
try
    fr = getframe(fig);
    imwrite(fr.cdata,outFile,'png');
catch
    try
        print(fig,outFile,'-dpng','-r150');
    catch
    end
end
end
