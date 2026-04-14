% Stage 24: soft-bail UserCall → interpreter dispatch.
%
% Tests that a JIT-friendly outer loop still JITs when the callee's
% body has constructs the JIT lowerer can't handle. Instead of bailing
% the entire loop, `lowerUserFuncCall` probes the callee's return type
% and emits a `UserDispatchCall` IR node that codegens to
% `$h.callUserFunc($rt, name, expectedType, ...args)` — the helper
% dispatches through `rt.dispatch` at runtime.
%
% Pattern: scalar loop body doing slice reads + scalar arith +
% per-iter user-function call whose body uses `bsxfun(@fn, ...)` —
% a construct the JIT doesn't currently lower. Before stage 24 this
% loop BAILS; after, it JITs and runs with one interpreter dispatch
% per iter for the callee while the outer scaffolding stays native.

addpath(fileparts(mfilename('fullpath')));

N = 100000;
A = ones(4, 1);
total = 0;
t0 = tic;
for i = 1:N
    assert_jit_compiled();
    v = stage24_helper_bsxfun(A, i); % soft-bail (callee body bails, probe OK)
    total = total + v(1) + v(4);
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_24 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('DONE\n');
