% Stage 7: while loop driving an integer stack stored in a tensor. Mirrors
% the chunkie ptloop's BVH traversal pattern (push children, pop on miss),
% but tested against a single flat list of rectangles encoded as a 1-level
% degenerate tree (one root node containing all leaves) so we don't need
% real tree data.
%
% Adds: while loop with scalar tensor read of a stack (`inode = stack(sp)`)
% combined with scalar tensor writes (`stack(sp) = ...`) — exactly the
% scalar push/pop access pattern that dominates the chunkie ptloop.

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

stack = zeros(1024, 1);

t0 = tic;
nhit = 0;
checksum = 0.0;
for i = 1:npts
    pxi = pts(1, i);
    pyi = pts(2, i);
    % Seed the stack with all rect indices in reverse order so popping from
    % the top gives 1, 2, 3, ... (we test all rectangles, just like the
    % degenerate single-leaf BVH described in the header).
    sp = 0;
    for j = nrect:-1:1
        sp = sp + 1;
        stack(sp) = j;
    end
    while sp > 0
        jj = stack(sp);
        sp = sp - 1;
        rxl = rects(1, jj);
        rxu = rects(2, jj);
        ryl = rects(3, jj);
        ryu = rects(4, jj);
        if pxi >= rxl && pxi <= rxu && pyi >= ryl && pyi <= ryu
            nhit = nhit + 1;
            checksum = checksum + i + jj;
        end
    end
end
t = toc(t0);

fprintf('BENCH: phase=stage07 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
