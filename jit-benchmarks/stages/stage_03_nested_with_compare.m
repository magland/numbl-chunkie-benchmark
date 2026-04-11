% Stage 3: nested for loops with compound conditional. No tensor writes.
% Counts how many (point, rect) pairs have the point inside the rect, by
% brute-force. Mirrors the inner test of the chunkie ptloop.
%
% Adds: nested for loop, compound `&&` conditional, scalar accumulation.

npts  = 10000;
nrect = 2000;

% Setup (vectorized): deterministic data, no tensor writes.
ip = (1:npts);
ir = (1:nrect);
px = (mod(ip * 37, 100) / 100) * 6 - 3;     % 1×npts
py = (mod(ip * 73, 100) / 100) * 6 - 3;     % 1×npts
cx = (mod(ir * 53, 100) / 100) * 6 - 3;     % 1×nrect
cy = (mod(ir * 91, 100) / 100) * 6 - 3;     % 1×nrect
hw = (mod(ir * 29, 100) / 100) * 0.3 + 0.05;
xl = cx - hw;
xu = cx + hw;
yl = cy - hw;
yu = cy + hw;

% Pack into matrix form so the kernel below can read elements via 2D index.
pts   = [px; py];                            % 2×npts
rects = [xl; xu; yl; yu];                    % 4×nrect

t0 = tic;
nhit = 0;
checksum = 0.0;
for i = 1:npts
    pxi = pts(1, i);
    pyi = pts(2, i);
    for j = 1:nrect
        rxl = rects(1, j);
        rxu = rects(2, j);
        ryl = rects(3, j);
        ryu = rects(4, j);
        if pxi >= rxl && pxi <= rxu && pyi >= ryl && pyi <= ryu
            nhit = nhit + 1;
            checksum = checksum + i + j;
        end
    end
end
t = toc(t0);

fprintf('BENCH: phase=stage03 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
