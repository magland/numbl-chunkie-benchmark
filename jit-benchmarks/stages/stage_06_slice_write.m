% Stage 6: adds a slice-write growth path on top of stage 5. Starts with a
% smaller preallocation (`nout_max = 1024`) and grows the output arrays via
% slice copy (`new(1:nout) = old(1:nout)`) when full. Mirrors the chunkie
% ptloop's `isp(nnzero+1:nnzero+nnew) = it` and the explicit doubling.
%
% Adds: range-slice write `out(1:nout) = src(1:nout)` (AssignLValue with
% Index whose index is a Range expression).

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

% Intentionally start small so we hit the growth path repeatedly.
nout_max = 1024;
out_pt   = zeros(nout_max, 1);
out_rect = zeros(nout_max, 1);

t0 = tic;
nhit = 0;
for i = 1:npts
    pt = pts(:, i);
    pxi = pt(1);
    pyi = pt(2);
    for j = 1:nrect
        rj = rects(:, j);
        if pxi >= rj(1) && pxi <= rj(2) && pyi >= rj(3) && pyi <= rj(4)
            if nhit >= nout_max
                tmp_pt   = out_pt;
                tmp_rect = out_rect;
                nout_max_new = nout_max * 2;
                out_pt   = zeros(nout_max_new, 1);
                out_rect = zeros(nout_max_new, 1);
                out_pt(1:nout_max)   = tmp_pt(1:nout_max);     % SLICE WRITE
                out_rect(1:nout_max) = tmp_rect(1:nout_max);   % SLICE WRITE
                nout_max = nout_max_new;
            end
            nhit = nhit + 1;
            out_pt(nhit)   = i;
            out_rect(nhit) = j;
        end
    end
end
t = toc(t0);

checksum = sum(out_pt(1:nhit)) + sum(out_rect(1:nhit));

fprintf('BENCH: phase=stage06 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
