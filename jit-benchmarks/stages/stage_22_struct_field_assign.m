% Stage 22: struct field assign (Member lvalue) inside JIT loops.
%
% `chnk.adapgausskerneval.m`'s `oneintp` local function builds the
% srcinfo/targinfo structs each call:
%
%   srcinfo = [];
%   srcinfo.r  = rint;
%   srcinfo.d  = dint;
%   srcinfo.d2 = d2int;
%   srcinfo.n  = nint;
%   srcinfo.data = dataint;
%   mat_tt = kern(srcinfo, targinfo);
%
% Current jitLower has no `case "Member"` branch in `lowerAssignLValue`,
% so any `s.f = v` inside a candidate function body bails the whole
% function. That's why `oneintp` itself doesn't lower, which is why the
% adap inner loop can't inline its UserCall, even once stage 17 makes
% the surrounding `vals(:, j) = v2` acceptable.
%
% Stage 22 tests the basic capability in isolation. The body does
% scalar arithmetic through struct fields, mirroring a user function
% that builds a transient struct to pass through an interface.
%
% Required jitLower change: new IR node `AssignMember { baseName,
% fieldName, value }`. In `lowerAssignLValue`, recognize lvalue shape
% `Member(Ident(base), name)`. Two cases:
%   1. base's env type is already `struct`/`class_instance`: emit
%      assignment to the existing fields map via `$h.structSetField_h`.
%   2. base's env type is `empty` (from `s = []`) or `unknown`: treat
%      as promoting empty to a fresh struct. Requires tracking "empty
%      numeric" as a pseudo-type that transitions to struct on first
%      Member-assign.
% Codegen emits `$h.structSetField_h(base, "field", value, rt)` which
% unshare-copies base if `_rc > 1` and `.set(field, value)` on the
% fields Map. The corresponding stage 12 read path already handles
% `base.fields.get("field")`, so downstream `s.f` reads flow through
% the existing hoisted alias AFTER an Assign to `base` triggers
% hoist-refresh.

addpath(fileparts(mfilename('fullpath')));

N = 100000;

total = 0;
t0 = tic;
for i = 1:N
    assert_jit_compiled();
    % Build a fresh struct each iter (mirrors srcinfo = []; srcinfo.r = ...).
    s = struct();             % start with an empty struct literal
    s.a = i;
    s.b = i * 2 + 1;
    s.c = i - 3;
    total = total + s.a + s.b - s.c;
end
t1 = toc(t0);

fprintf('BENCH: phase=stage_22 t=%.6f\n', t1);
fprintf('CHECK: name=total value=%.16e\n', total);

fprintf('DONE\n');
