% Stage 15: tensor arithmetic + IBuiltin calls inside JIT loops.
%
% Verifies that tensor+scalar arithmetic (v = v + 1), length() on
% tensors, and abs() on scalars work inside JIT-compiled loops.
% These are prerequisites for the flagself sliding-window pattern.

addpath(fileparts(mfilename('fullpath')));

N = 5000;
sortedx = sort(rand(30000, 1));
sortedy = sort(rand(N, 1));

% Sliding window with 2-element tensor + IBuiltin calls
v = [1; 2];
total = 0;
t0 = tic;
for j = 1:N
    assert_jit_compiled();
    while v(2) < length(sortedx) && sortedx(v(2)) < sortedy(j)
        v = v + 1;
    end
    d1 = abs(sortedx(v(1)) - sortedy(j));
    d2 = abs(sortedx(v(2)) - sortedy(j));
    total = total + d1 + d2;
end
t1 = toc(t0);
fprintf('BENCH: phase=stage_15 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('CHECK: name=v1 value=%.16e\n', v(1));

fprintf('DONE\n');
