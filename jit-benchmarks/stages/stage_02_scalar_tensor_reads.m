% Stage 2: loop body reads scalars from preallocated tensors via 1D, 2D
% and 3D indexing. No tensor writes, no slicing.
%
% Exercises: idx1 (linear), idx2 (matrix), idxN (3D).

n = 20000000;

% Setup (not timed): deterministic data via vectorized ops only (no tensor
% writes — those would defeat the JIT benchmark on stages that don't yet
% support indexed assignment in the JIT).
v = (1:n)' * 0.001;          % n×1
arg = (1:n) * 0.01;          % 1×n
m = [sin(arg); cos(arg)];    % 2×n
t3 = reshape([m(1,:); m(2,:); m(2,:); m(1,:)], 2, 2, n);

t0 = tic;
s = 0.0;
for i = 1:n
    s = s + v(i);                              % idx1
    s = s + m(1, i) * m(2, i);                 % idx2
    s = s + t3(1, 1, i) - t3(2, 2, i);         % idxN (3D)
end
t = toc(t0);

fprintf('BENCH: phase=stage02 t=%.6f\n', t);
fprintf('CHECK: name=s value=%.16e\n', s);
fprintf('DONE\n');
