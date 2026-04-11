% Benchmark: Helmholtz starfish exterior scattering via CFIE.
% Based on the first example in the chunkie documentation, minus plotting.
% Emits machine-parseable BENCH: and CHECK: lines so the runner can compare
% phase timings and result summaries between MATLAB and numbl.

t_chunkie_load = tic;
mip load --install chunkie;
fprintf('BENCH: phase=chunkie_load t=%.6f\n', toc(t_chunkie_load));

t_execution = tic;

% ---- planewave definitions ----
kvec = 20*[1;-1.5];
zk = norm(kvec);
planewave = @(kvec,r) exp(1i*sum(bsxfun(@times,kvec(:),r(:,:)))).';

narms = 5;
amp = 0.5;

% ---- Phase: discretize ----
t0 = tic;
chnkr = chunkerfunc(@(t) starfish(t,narms,amp), struct('maxchunklen',4/zk));
t_discretize = toc(t0);
fprintf('BENCH: phase=discretize t=%.6f\n', t_discretize);

% ---- Phase: build system matrix ----
t0 = tic;
fkern = kernel('helm','c',zk,[1,-zk*1i]);
sysmat = chunkermat(chnkr,fkern);
sysmat = 0.5*eye(chnkr.k*chnkr.nch) + sysmat;
t_build = toc(t0);
fprintf('BENCH: phase=build_matrix t=%.6f\n', t_build);

% ---- Phase: solve ----
t0 = tic;
rhs = -planewave(kvec(:),chnkr.r(:,:));
sol = gmres(sysmat,rhs,[],1e-13,100);
t_solve = toc(t0);
fprintf('BENCH: phase=solve t=%.6f\n', t_solve);

% ---- evaluation targets ----
x1 = linspace(-3,3,200);
[xxtarg,yytarg] = meshgrid(x1,x1);
targets = [xxtarg(:).';yytarg(:).'];

% ---- Phase: interior test ----
t0 = tic;
in = chunkerinterior(chnkr,targets);
out = ~in;
t_interior = toc(t0);
fprintf('BENCH: phase=interior t=%.6f\n', t_interior);

% ---- Phase: evaluate scattered field at targets ----
t0 = tic;
uscat = chunkerkerneval(chnkr,fkern,sol,targets(:,out));
t_eval = toc(t0);
fprintf('BENCH: phase=eval t=%.6f\n', t_eval);

uin = planewave(kvec,targets(:,out));
utot = uscat(:) + uin;

% ---- Result check values for cross-implementation comparison ----
fprintf('CHECK: name=zk value=%.16e\n', zk);
fprintf('CHECK: name=chnkr_k value=%.16e\n', double(chnkr.k));
fprintf('CHECK: name=chnkr_nch value=%.16e\n', double(chnkr.nch));
fprintf('CHECK: name=chnkr_r_norm value=%.16e\n', norm(chnkr.r(:)));
fprintf('CHECK: name=sysmat_fro value=%.16e\n', norm(sysmat,'fro'));
fprintf('CHECK: name=rhs_norm value=%.16e\n', norm(rhs));
fprintf('CHECK: name=sol_norm value=%.16e\n', norm(sol));
fprintf('CHECK: name=num_exterior value=%.16e\n', double(sum(out(:))));
fprintf('CHECK: name=uscat_norm value=%.16e\n', norm(uscat(:)));
fprintf('CHECK: name=utot_norm value=%.16e\n', norm(utot(:)));

fprintf('BENCH: phase=execution t=%.6f\n', toc(t_execution));
fprintf('DONE\n');
