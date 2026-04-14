% Stage 21: range slice read on RHS `x = t(a:b)`.
%
% This is the Newton-iteration bail in `chnk.chunk_nearparam.m:95` that
% takes ex02 interior from 0.28s (matlab) to 0.93s (numbl). The loop body
% calls `lege.exev(...)` producing a long column vector and then splits
% it into three chunks via range-slice reads:
%
%   all0 = lege.exev(t0, cfs);       % tensor[6*dim x 1]
%   r0   = all0(1:dim);              % line 114
%   d0   = all0(dim+1:2*dim);        % line 115
%   d20  = all0(2*dim+1:end);        % line 116
%
% Current jitLower `lowerIndexExpr` only accepts all-scalar or single
% tensor-index reads. Range indices inside a read fall through to
% `return null`, bailing the whole loop.
%
% Required jitLower change: either (a) materialize — emit
% `$h.subarrayCopy1r(srcData, srcLen, a, b)` returning a fresh tensor
% (per-iter allocation, but small slices are cheap in V8 young-gen), or
% (b) extend stage 5's slice-alias substitution to accept Range indices,
% rewriting downstream `r0(k)` to `src((a-1) + k)`. (a) is simpler and
% covers the chunk_nearparam shape; (b) is faster but needs the alias
% infrastructure to track a base offset.

addpath(fileparts(mfilename('fullpath')));

N    = 500000;
dim  = 3;
M    = 3 * dim;                % length of the source column
src0 = (1:M)';                 % base values

total = 0;
t0 = tic;
for i = 1:N
    assert_jit_compiled();
    % Produce a new source tensor per iter (mimics lege.exev output)
    src = src0 + i;
    r0  = src(1:dim);              % <-- RANGE SLICE READ from start
    d0  = src(dim+1:2*dim);        % <-- RANGE SLICE READ with non-1 base
    d20 = src(2*dim+1:M);          % <-- RANGE SLICE READ to end
    total = total + r0(1) + r0(dim) + d0(1) + d20(dim);
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_21 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);

fprintf('DONE\n');
