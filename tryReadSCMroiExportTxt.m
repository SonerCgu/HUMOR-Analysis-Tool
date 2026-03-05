function [ok, tMin, psc] = tryReadSCMroiExportTxt(fname)
% Tries to read SCM_gui ROI export txt:
% - header lines begin with '#'
% - table columns: time_sec   time_min   PSC
%
% Returns ok=false if not readable / not in expected format.

ok = false;
tMin = [];
psc  = [];

if nargin < 1 || isempty(fname), return; end
fname = strtrim(char(fname));
if exist(fname,'file')~=2, return; end

fid = fopen(fname,'r');
if fid < 0, return; end
cln = onCleanup(@() fclose(fid)); %#ok<NASGU>

inTable = false;

while true
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end

    if startsWith(ln,'#')
        % detect start of numeric table
        if contains(lower(ln),'# columns:') && contains(lower(ln),'psc')
            inTable = true;
        end
        continue;
    end

    if inTable
        vals = sscanf(ln,'%f');
        if numel(vals) >= 3
            tMin(end+1,1) = vals(2); %#ok<AGROW>
            psc(end+1,1)  = vals(3); %#ok<AGROW>
        end
    end
end

if numel(tMin) >= 5 && numel(psc) == numel(tMin)
    ok = true;
end
end