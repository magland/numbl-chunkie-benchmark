% Stage 20: Transpose, bsxfun folding, and mtimes in JIT loops
%
% Tests three new JIT capabilities together, mirroring the operations in
% chunkie's oneintp() / chnk.stok2d.kern():
%   - Transpose (.' and ')
%   - bsxfun(@minus, ...), bsxfun(@rdivide, ...)  folded to element-wise ops
%   - mtimes (tensor * tensor) matrix multiply
%
% These are the key operations inside the kernel evaluation loop of
% adapgausskerneval.m.

k = 16;       % chunkie node count per panel
k2 = 16;      % quadrature node count

% Precompute data matching oneintp sizes
% Use distinct Legendre-like nodes so bsxfun(@rdivide,...) doesn't hit zeros
rs = ones(2, k) + 0.01 * (1:k);
ds = ones(2, k) + 0.02 * (1:k);
ct = linspace(-1, 1, k).';          % k x 1 (Legendre nodes)
bw = ones(k, 1) ./ (1:k).';        % k x 1 (barycentric weights)
t_nodes = linspace(-0.9, 0.9, k2).';  % k2 x 1 (distinct from ct)

N = 50000;
total = 0;

t0 = tic;
for i = 1:N
    % Transpose: mirrors (tt(:)).'  in oneintp
    tt = t_nodes.';   % k2 x 1 -> 1 x k2

    % bsxfun folding: mirrors bsxfun(@minus, ct(:), (tt(:)).') in oneintp
    diff_mat = bsxfun(@minus, ct, tt);     % k x k2
    interpmat = bsxfun(@rdivide, bw, diff_mat);  % k x k2

    % mtimes: mirrors rs * interpmat in oneintp
    rint = rs * interpmat;   % 2 x k2

    % Element-wise ops: mirrors kernel arithmetic
    rx = rint(1,:);
    ry = rint(2,:);
    r2 = rx .^ 2 + ry .^ 2;
    rn = rx .* ry ./ (r2 + 1);

    total = total + sum(rn);
    assert_jit_compiled();
end
elapsed = toc(t0);

fprintf('BENCH: name=stage_20 t=%.6f\n', elapsed);
fprintf('CHECK: name=total value=%.16e\n', total);
fprintf('DONE\n');
