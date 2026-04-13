% Stage 16: vector indexing arr(tensor_idx) inside JIT loops.
%
% Tests the pattern from flagself where a sorted array is indexed
% with a 2-element tensor to read two adjacent values:
%   vals = sorted_arr(idcheck)   % idcheck is [n; n+1]
%
% Also tests abs(tensor) and tensor-scalar arithmetic on the result.

addpath(fileparts(mfilename('fullpath')));

N = 5000;
sortedx = sort(rand(30000, 1));
sortedy = sort(rand(N, 1));

% Sliding window with vector indexing + abs on tensor result
v = [1; 2];
n_sx = length(sortedx);
total = 0;
t0 = tic;
for j = 1:N
    assert_jit_compiled();
    while v(2) < n_sx && sortedx(v(2)) < sortedy(j)
        v = v + 1;
    end
    diffs = abs(sortedx(v) - sortedy(j));
    total = total + diffs(1) + diffs(2);
end
t1 = toc(t0);
fprintf('BENCH: phase=stage_16 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('CHECK: name=v1 value=%.16e\n', v(1));

fprintf('DONE\n');
