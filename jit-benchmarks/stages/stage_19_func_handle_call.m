% Stage 19: Function handle invocation inside JIT loops.
%
% Tests the ability to call a variable holding a function_handle from
% within a JIT-compiled loop. This is the key missing capability for
% JIT'ing chunkie's adaptive quadrature (adapgausskerneval), where the
% kernel function `kern(srcinfo, targinfo)` is passed as a function handle.
%
% Adds: function_handle JIT type recognition + FuncHandleCall IR node +
%       callFuncHandle runtime helper. Return type is number (scalar).

addpath(fileparts(mfilename('fullpath')));

N = 200000;

% --- Test: call a scalar function handle in a hot loop ---
f = @(x) x * x + 1;

total = 0;
t0 = tic;
for i = 1:N
    assert_jit_compiled();
    total = total + f(i);
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_19 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);

fprintf('DONE\n');
