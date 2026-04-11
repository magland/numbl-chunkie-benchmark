% Stage 4: like stage 3, but instead of just counting we write the (point,
% rect) hits into preallocated output arrays via scalar indexed assignment.
% This is the first stage that EXERCISES the tensor scalar-write capability.
%
% Adds: tensor scalar write `out_pt(nout) = i` (AssignLValue with Index).
% No slice writes — the result arrays are preallocated large enough that no
% growth path is needed.

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

% Preallocated output arrays — large enough that no growth is needed.
nout_max = 200000;
out_pt   = zeros(nout_max, 1);
out_rect = zeros(nout_max, 1);

t0 = tic;
nhit = 0;
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
            out_pt(nhit)   = i;       % SCALAR INDEXED ASSIGNMENT
            out_rect(nhit) = j;       % SCALAR INDEXED ASSIGNMENT
        end
    end
end
t = toc(t0);

% Checksum over the populated portion (avoid slicing — sum all and rely on
% the preallocated zeros for the unwritten tail).
checksum = sum(out_pt) + sum(out_rect);

fprintf('BENCH: phase=stage04 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
