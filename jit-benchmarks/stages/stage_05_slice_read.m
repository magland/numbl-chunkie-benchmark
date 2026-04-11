% Stage 5: like stage 4, but extracts the per-point coordinates and the
% per-rect bounds via column-slice reads instead of element-by-element
% indexing. Mirrors the chunkie ptloop pattern `pt = pts(:,i); x = pt(1)`.
%
% Adds: column slice read `pts(:, i)` returning a small column vector,
% then scalar element reads from that local slice.

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

nout_max = 200000;
out_pt   = zeros(nout_max, 1);
out_rect = zeros(nout_max, 1);

t0 = tic;
nhit = 0;
for i = 1:npts
    pt = pts(:, i);                 % SLICE READ → 2×1
    pxi = pt(1);
    pyi = pt(2);
    for j = 1:nrect
        rj = rects(:, j);           % SLICE READ → 4×1
        if pxi >= rj(1) && pxi <= rj(2) && pyi >= rj(3) && pyi <= rj(4)
            nhit = nhit + 1;
            out_pt(nhit)   = i;
            out_rect(nhit) = j;
        end
    end
end
t = toc(t0);

checksum = sum(out_pt) + sum(out_rect);

fprintf('BENCH: phase=stage05 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
