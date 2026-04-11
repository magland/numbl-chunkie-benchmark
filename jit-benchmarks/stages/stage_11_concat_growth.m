% Stage 11: empty matrix literal + vertical concat growth.
% Chunkie's flagnear_rectangle uses
%     it = [];
%     for jj = 1:length(xi)
%         if (in)
%             it = [it; i];
%         end
%     end
% as the per-leaf "found" list. The growth is bounded but unknown at
% lowering time, so the JIT needs to handle a tensor variable whose
% shape is `[?, 1]` and which gets reassigned to a longer tensor each
% concat.
%
% Lowering required:
%   * Empty matrix literal `[]`: lower as a tensor of shape `[0, 0]`
%     with `kind: tensor, nonneg: true`. Reads/writes via index would
%     fail at runtime, but unification with a non-empty tensor in the
%     loop body should widen to `[?, 1]` (or whatever shape the concat
%     produces).
%   * Vertical concat `[a; b]` where `a` is a (k,1) tensor and `b` is
%     a scalar: produces a (k+1, 1) tensor. The simplest implementation
%     is a per-iteration alloc-and-copy via a new helper.
%   * Type unification at the loop join: `it` starts as `tensor[0x0]`
%     and after the first concat becomes `tensor[?x1]`. The fixed-point
%     iterator in lowerFor handles this if the unification rule
%     understands "0x0 unifies with kx1 to ?x1".

npts = 500000;

t0 = tic;
totallen = 0;
totalsum = 0;
for i = 1:npts
    assert_jit_compiled();
    it = [];
    for j = 1:5
        if mod(i + j, 3) == 0
            it = [it; i * 10 + j];
        end
    end
    if ~isempty(it)
        totallen = totallen + length(it);
        totalsum = totalsum + it(1);
    end
end
t = toc(t0);

fprintf('BENCH: phase=stage11 t=%.6f\n', t);
fprintf('CHECK: name=totallen value=%.16e\n', double(totallen));
fprintf('CHECK: name=totalsum value=%.16e\n', totalsum);
fprintf('DONE\n');
