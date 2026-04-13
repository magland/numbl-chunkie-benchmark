% Benchmark: Stokes flow in a peanut-shaped domain with circular holes.
% Based on tmp/try1.m (chunkie Stokes demo), minus plotting.
% Emits machine-parseable BENCH: and CHECK: lines.

t_chunkie_load = tic;
mip load --install chunkie;
fprintf('BENCH: phase=chunkie_load t=%.6f\n', toc(t_chunkie_load));

t_execution = tic;

% ---- Phase: discretize ----
t0 = tic;

% peanut-shaped outer boundary
modes = [2.5,0,0,1];
ctr = [0;0];
chnkrouter = chunkerfunc(@(t) chnk.curves.bymode(t,modes,ctr));

% inner boundaries: circles (reversed for correct orientation)
chnkrcirc = chunkerfunc(@(t) chnk.curves.bymode(t,0.25,[0;0]));
chnkrcirc = reverse(chnkrcirc);

% reduced set: 4 inner circles instead of 10
centers = [[-1, 0, 1, 0]; [0.5, -0.5, 0.5, -0.5]];
centers = centers + 0.1*randn(size(centers));

chnkrlist = [chnkrouter];
for j = 1:size(centers,2)
    chnkr1 = chnkrcirc;
    chnkr1 = chnkr1.move([0;0],centers(:,j));
    chnkrlist = [chnkrlist chnkr1];
end
chnkr = merge(chnkrlist);

t_discretize = toc(t0);
fprintf('BENCH: phase=discretize t=%.6f\n', t_discretize);

% ---- Phase: build system matrix ----
t0 = tic;

% boundary condition: Gaussian velocity on outer boundary
wid = 0.3;
f = @(r) [exp(-r(2,:).^2/(2*wid^2)); zeros(size(r(2,:)))];
rhsout = f(chnkrouter.r(:,:)); rhsout = rhsout(:);
rhs = [rhsout; zeros(2*size(centers,2)*chnkrcirc.npt,1)];

% combined layer Stokes kernel
c = -1;
mu = 1;
kerncvel = kernel('stok','dvel',mu) + c*kernel('stok','svel',mu);

% matrix discretization
cmat = chunkermat(chnkr,kerncvel);

% identity term + nullspace correction
W = normonesmat(chnkr);
sysmat = cmat - 0.5*eye(2*chnkr.npt) + W;

t_build = toc(t0);
fprintf('BENCH: phase=build_matrix t=%.6f\n', t_build);

% ---- Phase: solve ----
t0 = tic;
sigma = gmres(sysmat,rhs,[],1e-10,100);
t_solve = toc(t0);
fprintf('BENCH: phase=solve t=%.6f\n', t_solve);

% ---- Phase: interior test ----
t0 = tic;
x1 = linspace(-3.75,3.75,80);
y1 = linspace(-2,2,40);
[xx,yy] = meshgrid(x1,y1);
targs = [xx(:).'; yy(:).'];
in = chunkerinterior(chnkr,{x1,y1});
t_interior = toc(t0);
fprintf('BENCH: phase=interior t=%.6f\n', t_interior);

% ---- Phase: evaluate velocity at targets ----
t0 = tic;
uu = nan([2,size(xx)]);
uu(:,in) = reshape(chunkerkerneval(chnkr,kerncvel,sigma,targs(:,in)),2,nnz(in));
t_eval_vel = toc(t0);
fprintf('BENCH: phase=eval_vel t=%.6f\n', t_eval_vel);

% ---- Phase: evaluate pressure at targets ----
t0 = tic;
kerncpres = kernel('stok','dpres',mu) + c*kernel('stok','spres',mu);
opts = []; opts.eps = 1e-3;
pres = nan(size(xx));
pres(in) = chunkerkerneval(chnkr,kerncpres,sigma,targs(:,in),opts);
t_eval_pres = toc(t0);
fprintf('BENCH: phase=eval_pres t=%.6f\n', t_eval_pres);

% ---- Result checks ----
fprintf('CHECK: name=chnkr_npt value=%.16e\n', double(chnkr.npt));
fprintf('CHECK: name=rhs_norm value=%.16e\n', norm(rhs));
fprintf('CHECK: name=sysmat_fro value=%.16e\n', norm(sysmat,'fro'));
fprintf('CHECK: name=sigma_norm value=%.16e\n', norm(sigma));
fprintf('CHECK: name=num_interior value=%.16e\n', double(nnz(in)));
fprintf('CHECK: name=uu_norm value=%.16e\n', norm(uu(~isnan(uu))));
fprintf('CHECK: name=pres_norm value=%.16e\n', norm(pres(~isnan(pres))));

fprintf('BENCH: phase=execution t=%.6f\n', toc(t_execution));
fprintf('DONE\n');
