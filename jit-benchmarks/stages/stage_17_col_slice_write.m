% Stage 17: multi-dim column slice write `dst(:, j) = src` where `src` is a
% tensor.
%
% This is the single capability gap responsible for almost all of ex02's
% ~12s eval-phase slowness. `chnk.adapgausskerneval.m` drives a recursive
% subdivision via a scalar stack (`stack(1,jj)`, `stack(2,jj)` — stage 4
% handles those) plus a column-slice write of the per-subinterval
% integral value:
%
%   vals(:, jj+1) = v2;      % line 145 in adapgausskerneval.m
%   vals(:, jj)   = v3;      % line 148
%
% Stage 6 only handles linear range writes `dst(a:b) = src(c:d)` — the
% multi-dim form is listed as out-of-scope in PERF_NOTES.md. This stage
% exercises exactly that pattern.
%
% Required jitLower change: recognize an AssignLValue whose lvalue is
% `Index(Ident(dst), [Colon, scalar_j])` on a real tensor, with RHS a
% real tensor whose shape is statically `[dst_rows, 1]`. New IR node
% `AssignIndexCol` + helper `setCol2r_h(dstData, dstRows, dstCols, j,
% srcData)`. Bounds-checks j in [1, dstCols] and copies
% `srcData[0..dstRows-1]` into `dstData[(j-1)*dstRows .. j*dstRows-1]`.

addpath(fileparts(mfilename('fullpath')));

N = 2000000;
nslots = 128;

vals = zeros(2, nslots);
src  = zeros(2, 1);

total = 0;
t0 = tic;
for i = 1:N
    assert_jit_compiled();
    j = mod(i - 1, nslots) + 1;
    src(1) = i;
    src(2) = i * 2 + 1;
    vals(:, j) = src;          % <-- COLUMN SLICE WRITE (multi-dim)
    total = total + vals(1, j) - vals(2, j);
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_17 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('CHECK: name=last_v1 value=%.16e\n', vals(1, nslots));
fprintf('CHECK: name=last_v2 value=%.16e\n', vals(2, nslots));

fprintf('DONE\n');
