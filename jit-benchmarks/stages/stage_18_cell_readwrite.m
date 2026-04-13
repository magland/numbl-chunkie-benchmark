% Stage 18: Cell array scalar read/write + horizontal concatenation
%           inside JIT loops.
%
% Tests the pattern from flagself where a cell array element is read,
% horizontally concatenated with a scalar, and written back:
%   binids{idx} = [binids{idx}, value]
%
% This is the key pattern that prevents flagself from JIT'ing.

addpath(fileparts(mfilename('fullpath')));

N = 5000;
ids = mod(0:N-1, 100) + 1;

% --- Test 1: cell append pattern ---
c = cell(100, 1);
for i = 1:100; c{i} = []; end

total = 0;
t0 = tic;
for j = 1:N
    assert_jit_compiled();
    idx = ids(j);
    c{idx} = [c{idx}, j];
    total = total + j;
end
t1 = toc(t0);
fprintf('BENCH: phase=stage_18 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('CHECK: name=c1_len value=%.16e\n', length(c{1}));

fprintf('DONE\n');
