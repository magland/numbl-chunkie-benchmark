% Stage 23: integration target — simplified `adapgausskerneval` inner
% subdivision loop, combining stages 17 (column slice write) and 19
% (function handle call). Stages 21 and 22 are exercised by the
% companion helper `stage_23_adap_inner_step.m`; when stage 22 lands
% AND stage 21 lands, this loop should JIT the helper as a UserCall
% and inline through.
%
% Mirrors `chnk.adapgausskerneval.m:109-160`:
%   - Scalar stack of interval endpoints (stage 4).
%   - Column-slice writes `vals(:, jj+1) = v2` (stage 17 — NEW).
%   - Function-handle call returning a 2-element column (stage 19).
%
% Success criterion: when stage 17 JITs cleanly, this stage JITs as a
% single loop function and runs within a small factor of matlab. The
% helper UserCall path depends on stages 21 + 22 for full inlining of
% the struct construction.

addpath(fileparts(mfilename('fullpath')));

ntarg    = 8000;
maxdepth = 64;
nnmax    = 400;
eps_tol  = 1e-10;
% Deterministic targets so matlab/numbl checksums match.
ii       = 1:ntarg;
rt       = [mod(ii * 37, ntarg) / ntarg; mod(ii * 73, ntarg) / ntarg];

% Direct function handle so we don't cross into the struct-building
% helper (stage 22) until those stages land. Once they do, rewriting
% the handle to call `stage_23_adap_inner_step(srcinfo, targinfo)`
% tests the full shape.
% Non-smooth enough that the hybrid rule actually subdivides.
kern = @(a, b, x, y) [ (b - a) * sin(5 * x * (a + b) / 2); ...
                       (b - a) * cos(5 * y * (a + b) / 2) ];

stack = zeros(2, maxdepth);
vals  = zeros(2, maxdepth);
fints = zeros(2 * ntarg, 1);

t0 = tic;
for ii = 1:ntarg
    x = rt(1, ii);
    y = rt(2, ii);

    stack(1, 1) = -1;
    stack(2, 1) = 1;
    vals(:, 1) = kern(-1, 1, x, y);    % <-- COLUMN SLICE WRITE (stage 17)

    jj = 1;
    f1 = 0;
    f2 = 0;

    for i = 1:nnmax
        assert_jit_compiled();
        a = stack(1, jj);
        b = stack(2, jj);
        c = (a + b) / 2;

        v2 = kern(a, c, x, y);         % <-- FUNC HANDLE CALL (stage 19, tensor return)
        v3 = kern(c, b, x, y);

        diff1 = v2(1) + v3(1) - vals(1, jj);
        diff2 = v2(2) + v3(2) - vals(2, jj);
        dd = max(abs(diff1), abs(diff2));

        if dd <= eps_tol
            f1 = f1 + v2(1) + v3(1);
            f2 = f2 + v2(2) + v3(2);
            jj = jj - 1;
            if jj == 0
                break;
            end
        else
            stack(1, jj+1) = stack(1, jj);
            stack(2, jj+1) = (stack(1, jj) + stack(2, jj)) / 2;
            vals(:, jj+1) = v2;        % <-- COLUMN SLICE WRITE (stage 17)
            stack(1, jj)  = (stack(1, jj) + stack(2, jj)) / 2;
            vals(:, jj)   = v3;        % <-- COLUMN SLICE WRITE (stage 17)
            jj = jj + 1;
            if jj > maxdepth
                break;
            end
        end
    end

    fints(2*ii - 1) = f1;
    fints(2*ii)     = f2;
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_23 t=%.6f\n', t1);
fprintf('CHECK: name=fints_norm value=%.16e\n', norm(fints));
fprintf('CHECK: name=fints_sum value=%.16e\n', sum(fints));

fprintf('DONE\n');
