% Stage 8 — AMBITIOUS TARGET. Full BVH-style query that mirrors the chunkie
% flagnear_rectangle ptloop pattern: stack-driven tree traversal, leaf rect
% loop with the box-containment test, hit accumulation into preallocated
% output arrays with a slice-copy growth path.
%
% Tree (5 nodes):
%   node 1 = root   (children = 2..5)
%   nodes 2..5     = leaves (each owns a contiguous slice of rects)
%
% Encoded as flat arrays so the kernel can run without struct field reads.
%
% Combines every JIT capability the staged scripts add:
%   * scalar tensor reads via idx1 / idx2  (stages 02, 03)
%   * scalar tensor WRITES                  (stage 04)
%   * column SLICE READS                    (stage 05)
%   * range SLICE WRITES                    (stage 06)
%   * while loop with stack push/pop        (stage 07)

npts  = 4000;
nrect = 1000;

ip = (1:npts);
ir = (1:nrect);
px = (mod(ip * 37, 100) / 100) * 6 - 3;
py = (mod(ip * 73, 100) / 100) * 6 - 3;
cx = (mod(ir * 53, 100) / 100) * 6 - 3;
cy = (mod(ir * 91, 100) / 100) * 6 - 3;
hw = (mod(ir * 29, 100) / 100) * 0.3 + 0.05;
xl = cx - hw;
xu = cx + hw;
yl = cy - hw;
yu = cy + hw;
pts   = [px; py];
rects = [xl; xu; yl; yu];

% Build the tree (vectorized so the setup itself doesn't depend on indexed
% writes, which several stages don't yet JIT). 4 leaves of nrect/4 each.
qsize = nrect / 4;
q_xl = min(reshape(xl, qsize, 4), [], 1);
q_xu = max(reshape(xu, qsize, 4), [], 1);
q_yl = min(reshape(yl, qsize, 4), [], 1);
q_yu = max(reshape(yu, qsize, 4), [], 1);
r_xl = min(xl);  r_xu = max(xu);  r_yl = min(yl);  r_yu = max(yu);

node_xl = [r_xl, q_xl];        % 1×5
node_xu = [r_xu, q_xu];
node_yl = [r_yl, q_yl];
node_yu = [r_yu, q_yu];
node_first_child = [2, 0, 0, 0, 0];
node_num_child   = [4, 0, 0, 0, 0];
node_first_rect  = [0, 1, 1+qsize, 1+2*qsize, 1+3*qsize];
node_num_rect    = [0, qsize, qsize, qsize, qsize];

stack = zeros(2048, 1);

% Intentionally start small so the slice-write growth path is exercised.
nout_max = 4096;
out_pt   = zeros(nout_max, 1);
out_rect = zeros(nout_max, 1);

t0 = tic;
nhit = 0;
for i = 1:npts
    pt = pts(:, i);
    pxi = pt(1);
    pyi = pt(2);

    sp = 1;
    stack(1) = 1;
    while sp > 0
        inode = stack(sp);
        sp = sp - 1;
        nxl = node_xl(inode);
        nxu = node_xu(inode);
        nyl = node_yl(inode);
        nyu = node_yu(inode);
        if pxi >= nxl && pxi <= nxu && pyi >= nyl && pyi <= nyu
            nc = node_num_child(inode);
            if nc > 0
                fc = node_first_child(inode);
                for cc = 0:(nc - 1)
                    sp = sp + 1;
                    stack(sp) = fc + cc;
                end
            else
                fr = node_first_rect(inode);
                nr = node_num_rect(inode);
                for jj = 0:(nr - 1)
                    j = fr + jj;
                    rj = rects(:, j);
                    if pxi >= rj(1) && pxi <= rj(2) && pyi >= rj(3) && pyi <= rj(4)
                        if nhit >= nout_max
                            tmp_pt   = out_pt;
                            tmp_rect = out_rect;
                            nout_max_new = nout_max * 2;
                            out_pt   = zeros(nout_max_new, 1);
                            out_rect = zeros(nout_max_new, 1);
                            out_pt(1:nout_max)   = tmp_pt(1:nout_max);
                            out_rect(1:nout_max) = tmp_rect(1:nout_max);
                            nout_max = nout_max_new;
                        end
                        nhit = nhit + 1;
                        out_pt(nhit)   = i;
                        out_rect(nhit) = j;
                    end
                end
            end
        end
    end
end
t = toc(t0);

checksum = sum(out_pt(1:nhit)) + sum(out_rect(1:nhit));

fprintf('BENCH: phase=stage08 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
