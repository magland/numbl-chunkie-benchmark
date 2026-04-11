% Stage 1: scalar-arithmetic-only loop. No tensor reads, no tensor writes.
% This stage exists to confirm the baseline — the simplest possible loop
% the JIT should specialize. If this is slow in numbl, the JIT is broken.

n = 50000000;

t0 = tic;
s = 0.0;
acc = 0.0;
for i = 1:n
    a = i * 0.5;
    b = a + 1.0;
    if a > b
        s = s + a;
    else
        s = s + b;
    end
    acc = acc + a - b;
end
t = toc(t0);

fprintf('BENCH: phase=stage01 t=%.6f\n', t);
fprintf('CHECK: name=s value=%.16e\n', s);
fprintf('CHECK: name=acc value=%.16e\n', acc);
fprintf('DONE\n');
