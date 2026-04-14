function v = stage24_helper_bsxfun(A, s)
% Helper for stage 24 — bsxfun(@fn, ...) with a function-handle first
% arg isn't lowered by the JIT, so the callee's body bails. Stage 24's
% soft-bail path detects this, probes the return type, and emits a
% UserDispatchCall so the outer loop still JITs.
v = bsxfun(@times, A, s);
end
