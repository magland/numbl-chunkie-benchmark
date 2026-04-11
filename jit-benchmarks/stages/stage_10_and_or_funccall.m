% Stage 10: function-call form `and(a, b)` / `or(a, b)` in conditions.
% Chunkie's flagnear_rectangle uses `while(and(is > 0, ntry <= nnodes))`
% — the function-call form rather than the `&&` operator. The lowering
% currently routes this through `lowerIBuiltinCall` which produces an
% `$h.ib_and(...)` call inside the hot loop, defeating the V8 inlining
% that the operator form gets.
%
% Lowering required:
%   * In `lowerExpr` case "FuncCall", recognize `and(a, b)` / `or(a, b)`
%     with two scalar args and emit a synthetic `Binary` JitExpr with
%     `BinaryOperation.AndAnd` / `OrOr`. Same fast path as `&&` / `||`.
%   * Optionally also handle `not(a)` → `Unary(Not, a)`.

n = 2000000;

t0 = tic;
total_a = 0;
total_b = 0;
for i = 1:n
    assert_jit_compiled();
    a = mod(i, 7);
    b = mod(i, 11);
    if and(a > 2, b < 8)
        total_a = total_a + 1;
    end
    if or(a == 0, b == 0)
        total_b = total_b + 1;
    end
end
t = toc(t0);

fprintf('BENCH: phase=stage10 t=%.6f\n', t);
fprintf('CHECK: name=total_a value=%.16e\n', double(total_a));
fprintf('CHECK: name=total_b value=%.16e\n', double(total_b));
fprintf('DONE\n');
