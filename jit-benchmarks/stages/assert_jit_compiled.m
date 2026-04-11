function assert_jit_compiled()
%ASSERT_JIT_COMPILED  Marker that asserts the surrounding loop body is
% JIT-compiled. No-op when run under MATLAB.
%
% In numbl, the JIT lowering elides this call when the surrounding
% for/while body lowers cleanly. If lowering bails, the call survives
% to the interpreter, which throws (unless `--opt 0` is in effect).
%
% This .m file is the MATLAB-side shim: MATLAB has no concept of
% lowering vs interpretation, so the function is a silent no-op there.
% This lets the same stage script run under both engines without
% modification.
end
