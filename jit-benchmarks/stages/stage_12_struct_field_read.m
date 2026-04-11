% Stage 12: scalar struct field read inside a loop.
% A struct is built outside the loop and used inside via `s.f`. Mirrors
% any chunkie code reading scalar parameters from a struct (e.g.
% `chnkr.k`, `chnkr.nch`, `opts.rho`).
%
% Lowering required:
%   * Track struct types in the type env, including their field types.
%     For a literal struct created via `s.f = v` or `s = struct('f', v)`,
%     remember `{ kind: "struct", fields: { f: numberType } }`.
%   * `lowerExpr` case "Member": `s.f` where `s` has a struct type with
%     known field `f` → emit a JS property load. Need a new IR node
%     `tag: "MemberRead"` (or extend `Index` with a string-key form).
%   * Codegen the property load: `s_f = s.f` (one .data-style hoist
%     opportunity) or per-call `s.f` reads.
%
% Note: this stage only covers SCALAR struct fields. Tensor-typed fields
% are stage 13's job (chained access on a struct array).

n_iters = 2000000;

opts.k = 16;
opts.nch = 200;
opts.tol = 1e-6;
opts.rho = 1.8;

t0 = tic;
total = 0;
for i = 1:n_iters
    assert_jit_compiled();
    val = opts.k * i + opts.nch;
    if val > opts.tol
        total = total + val * opts.rho;
    end
end
t = toc(t0);

fprintf('BENCH: phase=stage12 t=%.6f\n', t);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('DONE\n');
