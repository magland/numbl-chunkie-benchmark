% Stage 14: full chunkie ptloop variant (struct-of-struct flavor).
% This is the AMBITIOUS target — a near-direct copy of the outer for
% loop in chunkie's `flagnear_rectangle` (line 111-173 of
% chunkie/@chunker/flagnear_rectangle.m), keeping the struct-array form
% of the BVH (`T.nodes(inode).chld`, `T.nodes(inode).xi`) instead of
% the flat-tensor surrogate stage 8 used.
%
% Combines every JIT capability staged in 09-13 plus everything from
% stages 1-8:
%   * scalar reads + writes                              (stages 02-04)
%   * 1-colon and 2-colon slice reads                    (stage 05)
%   * range slice writes from another tensor's range     (stage 06)
%   * range slice writes from a whole-tensor variable    (stage 09)
%   * `and()` / `or()` function-call form in conditions  (stage 10)
%   * empty matrix init + vertical concat growth         (stage 11)
%   * scalar struct field read                           (stage 12)
%   * struct array indexing + chained Member             (stage 13)
%
% If THIS stage JITs cleanly, the actual flagnear_rectangle.m should
% JIT cleanly too — meaning the chunkie ex01_helmholtz_starfish
% interior phase will finally run faster than matlab.

% --- Build a tiny BVH using struct-array form (mirrors hypoct output) ---
n_nodes = 5;
T.nodes(1).chld = [2; 3; 4; 5];   T.nodes(1).xi = zeros(0, 1);
T.nodes(2).chld = zeros(0, 1);    T.nodes(2).xi = (1:25).';
T.nodes(3).chld = zeros(0, 1);    T.nodes(3).xi = (26:50).';
T.nodes(4).chld = zeros(0, 1);    T.nodes(4).xi = (51:75).';
T.nodes(5).chld = zeros(0, 1);    T.nodes(5).xi = (76:100).';

nlev = 2;
nnodes = n_nodes;

% Bounding rects per node, axis-aligned: bvhbounds(:,1,inode) = [xl;yl],
% bvhbounds(:,2,inode) = [xu;yu].
bvhbounds = zeros(2, 2, n_nodes);
bvhbounds(:, :, 1) = [-3, 3; -3, 3];   % root
bvhbounds(:, :, 2) = [-3, 0; -3, 0];   % SW
bvhbounds(:, :, 3) = [ 0, 3; -3, 0];   % SE
bvhbounds(:, :, 4) = [-3, 0;  0, 3];   % NW
bvhbounds(:, :, 5) = [ 0, 3;  0, 3];   % NE

% Per-rect data, packed in the same shape as chunkie's `rectinfo`:
% rectinfo(:,1,j) = d1 axis, rectinfo(:,2,j) = d2 axis,
% rectinfo(1:2, 3, j) = [d1min; d1max], rectinfo(1:2, 4, j) = [d2min; d2max].
nrect = 100;
rectinfo = zeros(2, 4, nrect);
for j = 1:nrect
    rectinfo(1, 1, j) = 1;  rectinfo(2, 1, j) = 0;
    rectinfo(1, 2, j) = 0;  rectinfo(2, 2, j) = 1;
    rectinfo(1, 3, j) = -2.95 + 0.05 * j;
    rectinfo(2, 3, j) = -2.55 + 0.05 * j;
    rectinfo(1, 4, j) = -2.95 + 0.04 * j;
    rectinfo(2, 4, j) = -2.45 + 0.04 * j;
end

% Points to query
npts = 20000;
ip = (1:npts);
px = (mod(ip * 37, 100) / 100) * 6 - 3;
py = (mod(ip * 73, 100) / 100) * 6 - 3;
pts = [px; py];

% Output buffers (intentionally start small so the growth path fires)
nnzero = 0;
nn = 1024;
isp = zeros(nn, 1);
jsp = zeros(nn, 1);
istack = zeros(4 * nlev, 1);

t0 = tic;
for i = 1:npts
    assert_jit_compiled();
    ntry = 0;
    is = 1;
    pt = pts(:, i);
    x = pt(1);
    y = pt(2);
    istack(1) = 1;
    while and(is > 0, ntry <= nnodes)
        ntry = ntry + 1;
        inode = istack(is);
        bvhtmp = bvhbounds(:, :, inode);
        xl = bvhtmp(1, 1); xu = bvhtmp(1, 2);
        yl = bvhtmp(2, 1); yu = bvhtmp(2, 2);
        if (x >= xl && x <= xu && y >= yl && y <= yu)
            chld = T.nodes(inode).chld;
            if ~isempty(chld)
                istack(is:is + length(chld) - 1) = chld;
                is = is + length(chld) - 1;
            else
                xi = T.nodes(inode).xi;
                if ~isempty(xi)
                    it = [];
                    js = [];
                    for jj = 1:length(xi)
                        jell = xi(jj);
                        d1 = pt(1) * rectinfo(1, 1, jell) + pt(2) * rectinfo(2, 1, jell);
                        d2 = pt(1) * rectinfo(1, 2, jell) + pt(2) * rectinfo(2, 2, jell);
                        in = (d1 >= rectinfo(1, 3, jell) && ...
                              d1 <= rectinfo(2, 3, jell) && ...
                              d2 >= rectinfo(1, 4, jell) && ...
                              d2 <= rectinfo(2, 4, jell));
                        if (in)
                            it = [it; i];
                            js = [js; jell];
                        end
                    end
                    nnew = length(it);
                    if nnew + nnzero > nn
                        itemp = isp;
                        jtemp = jsp;
                        isp = zeros(2 * nn, 1);
                        jsp = zeros(2 * nn, 1);
                        isp(1:nn) = itemp;
                        jsp(1:nn) = jtemp;
                        nn = 2 * nn;
                    end
                    isp(nnzero + 1:nnzero + nnew) = it;
                    jsp(nnzero + 1:nnzero + nnew) = js;
                    nnzero = nnew + nnzero;
                end
                is = is - 1;
            end
        else
            is = is - 1;
        end
    end
end
t = toc(t0);

checksum = sum(isp(1:nnzero)) + sum(jsp(1:nnzero));

fprintf('BENCH: phase=stage14 t=%.6f\n', t);
fprintf('CHECK: name=nnzero value=%.16e\n', double(nnzero));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
