% Stage 9: range-slice write where the RHS is a whole-tensor variable
% (a plain Ident, not a `src(c:d)` range slice). Mirrors the chunkie
% grow-and-copy line `isp(1:nn) = itemp` where `itemp` is the OLD
% buffer reassigned to a fresh local just before `isp` is reallocated.
%
% Stage 6 already handles `dst(a:b) = src(c:d)`. Stage 9 adds the
% degenerate-RHS form `dst(a:b) = src` with a runtime length-match
% check between the LHS range and the source's `numel`.
%
% Lowering required:
%   * Extend `tryLowerRangeAssign` (or add a sibling) to accept an
%     RHS that's an `Ident` of a real tensor (or a `FuncCall` that
%     resolves to one), and emit a helper call that copies the entire
%     source into the dst range.

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

nout_max = 1024;
out_pt   = zeros(nout_max, 1);
out_rect = zeros(nout_max, 1);

t0 = tic;
nhit = 0;
for i = 1:npts
    assert_jit_compiled();
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
                out_pt(1:nout_max)   = tmp_pt;     % WHOLE-TENSOR SRC
                out_rect(1:nout_max) = tmp_rect;   % WHOLE-TENSOR SRC
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

fprintf('BENCH: phase=stage09 t=%.6f\n', t);
fprintf('CHECK: name=nhit value=%.16e\n', double(nhit));
fprintf('CHECK: name=checksum value=%.16e\n', checksum);
fprintf('DONE\n');
