function HUMoR_style_rejected_qc_axis(ax)
% Make rejected-volume QC axes readable in GUI and saved PNG.
if nargin < 1 || isempty(ax) || ~ishghandle(ax)
    ax = gca;
end
try
    fig = ancestor(ax,'figure');
    set(fig,'Color','w','InvertHardcopy','off');
    set(fig,'PaperPositionMode','auto');
    set(fig,'Units','pixels');
    pos = get(fig,'Position');
    if numel(pos) == 4
        pos(3) = max(pos(3),1400);
        pos(4) = max(pos(4),760);
        set(fig,'Position',pos);
    end
catch
end
try
    set(ax,'Units','normalized');
    set(ax,'Position',[0.11 0.18 0.84 0.70]);
    set(ax,'LooseInset',[0.06 0.06 0.04 0.06]);
    set(ax,'Color','w');
    set(ax,'XColor','k','YColor','k','ZColor','k');
    set(ax,'GridColor',[0.72 0.72 0.72]);
    set(ax,'FontSize',13,'FontWeight','bold','LineWidth',1.4,'Box','on');
    ylim(ax,[-0.15 1.15]);
    set(ax,'YTick',[0 1],'YTickLabel',{'Accepted','Rejected'});
    xlabel(ax,'Time (s)','Color','k','FontSize',15,'FontWeight','bold');
    ylabel(ax,'Frame status','Color','k','FontSize',15,'FontWeight','bold');
    title(ax,'Rejected volumes over time','Color','k','FontSize',17,'FontWeight','bold');
    grid(ax,'on');
catch
end
try
    hs = findall(ax);
    for i = 1:numel(hs)
        h = hs(i);
        if isprop(h,'LineWidth')
            try
                lw = get(h,'LineWidth');
                if isempty(lw) || lw < 2.0
                    set(h,'LineWidth',2.0);
                end
            catch
            end
        end
        if isprop(h,'MarkerSize')
            try
                ms = get(h,'MarkerSize');
                if isempty(ms) || ms < 5
                    set(h,'MarkerSize',5);
                end
            catch
            end
        end
    end
catch
end
drawnow;
end
