% Stage 13: struct array indexing + chained Member access.
% Mirrors chunkie's `T.nodes(inode).chld` and `T.nodes(inode).xi`
% pattern from flagnear_rectangle's BVH walk. The struct is built
% outside the loop; the loop body reads scalars and small tensors via
% `T.nodes(idx).field`.
%
% Lowering required (builds on stage 12):
%   * Struct array type tracking. A struct array is a homogeneous
%     collection of structs with the same set of fields and the same
%     per-field type. Represent it as
%     `{ kind: "struct_array", elemFields: { ... }, length?: number }`.
%   * `lowerExpr` case "Index" where the base is a struct array Var or
%     a Member access producing a struct array: emit a JS index load
%     of the underlying storage. Most natural runtime representation
%     is one Float64Array per scalar field plus one variable-length
%     array per tensor field, indexed by element.
%   * Chained `Member(Index(Member(T, nodes), [i]), chld)`:
%       T.nodes        → struct_array (the value of T's `nodes` field)
%       T.nodes(i)     → "row i" of the struct array — a virtual
%                        struct value bound to the array + index
%       T.nodes(i).f   → indexed read on the field-specific storage
%     Implement as a "struct array alias": never materialize the
%     intermediate row, substitute through to a direct field-storage
%     read at the leaf.

n_iters = 200000;
n_nodes = 5;

% Build a tree-like struct: each node has a scalar `val` and a
% vector `chld` of child indices.
T.nodes(1).val = 1;   T.nodes(1).chld = [2; 3; 4; 5];
T.nodes(2).val = 10;  T.nodes(2).chld = [0; 0; 0; 0];
T.nodes(3).val = 20;  T.nodes(3).chld = [0; 0; 0; 0];
T.nodes(4).val = 30;  T.nodes(4).chld = [0; 0; 0; 0];
T.nodes(5).val = 40;  T.nodes(5).chld = [0; 0; 0; 0];

t0 = tic;
total_val = 0;
total_chld = 0;
for i = 1:n_iters
    assert_jit_compiled();
    inode = mod(i - 1, n_nodes) + 1;
    total_val = total_val + T.nodes(inode).val;
    chld = T.nodes(inode).chld;
    total_chld = total_chld + chld(1) + chld(2);
end
t = toc(t0);

fprintf('BENCH: phase=stage13 t=%.6f\n', t);
fprintf('CHECK: name=total_val value=%.16e\n', total_val);
fprintf('CHECK: name=total_chld value=%.16e\n', total_chld);
fprintf('DONE\n');
