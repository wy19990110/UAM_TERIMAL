function runEXP4B_S(outDir)
    % runEXP4B_S  S 通道隔离 redesign 实验
    %   按新的实验要求 §一.4:
    %   - 固定 A=0 (alphaA=0), F=0 (phiF=0)
    %   - 扫 4 变量: rho(需求), couplingM(跨端口耦合), psiSat(饱和惩罚), concentration(OD 集中度)
    %   - 只比 M0 vs M1
    %   - 核心指标: U01 = J^truth(M0) - J^truth(M1)
    %   - 输出: U01 heatmap on (rho x E_S)
    %
    %   目标不是"再证明 S 存在"(EXP-2 已做)，而是找 S 通道的中尺度边界:
    %   什么拥挤激活水平下从 M0 升级到 M1 值得。
    arguments
        outDir (1,1) string = "results/exp4b_s"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4b_s_log.txt");
    cpFile = fullfile(outDir, "exp4b_s_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4b_s_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 图族
    families = struct('name',{'G1s','G2s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13])});
    seeds = 1:3;

    % 扫描参数: A=0, F=0 固定
    rhoVals = [0.4, 0.6, 0.8, 1.0, 1.2];
    couplingMVals = [0.0, 0.1, 0.3, 0.5];
    psiSatVals = [1.0, 2.0, 3.0, 5.0];
    concentrationVals = [0.0, 0.3, 0.5, 0.7];

    combos = {};
    for fi = 1:numel(families)
        for si = 1:numel(seeds)
            for ri = 1:numel(rhoVals)
                for mi = 1:numel(couplingMVals)
                    for pi = 1:numel(psiSatVals)
                        for ci = 1:numel(concentrationVals)
                            combos{end+1} = struct('fi',fi,'si',si,'ri',ri,'mi',mi,'pi',pi,'ci',ci); %#ok<AGROW>
                        end
                    end
                end
            end
        end
    end
    total = numel(combos);
    logmsg(sprintf('=== EXP-4B-S S通道隔离: %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        results = cp.results;
        completed = cp.completed;
        logmsg(sprintf('加载 checkpoint: %d/%d 已完成', sum(completed), total));
    else
        results = cell(total, 1);
        completed = false(total, 1);
    end

    opts = struct('nPwl', 15, 'verbose', false);

    for idx = 1:total
        if completed(idx), continue; end
        c = combos{idx};
        fname = families(c.fi).name;
        spec = families(c.fi).spec;
        sd = seeds(c.si);
        rho = rhoVals(c.ri);
        mVal = couplingMVals(c.mi);
        psi = psiSatVals(c.pi);
        conc = concentrationVals(c.ci);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f m=%.1f psi=%.1f c=%.1f', ...
            idx, total, fname, sd, rho, mVal, psi, conc));
        t0 = tic;
        try
            % A=0, F=0, 用新参数
            params = struct('alphaA', 0, 'kappaS', 2, 'phiF', 0, 'rho', rho, ...
                'couplingM', mVal, 'psiSat', psi, 'concentration', conc);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            m0i = containers.Map(); m1i = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M0') = m0i; ifaces('M1') = m1i;

            res = asf.solver.computeRegret(inst, ["M0";"M1"], ifaces, opts);
            elapsed = toc(t0);

            % E_S 计算（与 buildSynthetic 一致）
            E_S = inst.excitation.E_S;

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.couplingM = mVal; r.psiSat = psi; r.concentration = conc;
            r.E_S = E_S;
            r.jStar = res.star.jTruth;
            r.m0Regret = res.M0.regret; r.m0Rel = res.M0.relRegret;
            r.m1Regret = res.M1.regret; r.m1Rel = res.M1.relRegret;
            r.m0TD = res.M0.tdBB; r.m1TD = res.M1.tdBB;
            if isfield(res, 'U01'), r.U01 = res.U01; r.relU01 = res.relU01;
            else, r.U01 = NaN; r.relU01 = NaN; end
            r.time = elapsed; r.error = "";
            results{idx} = r;
            logmsg(sprintf('  J*=%.1f U01=%.4f relU01=%.1f%% E_S=%.3f (%.1fs)', ...
                res.star.jTruth, r.U01, r.relU01*100, E_S, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
            r.couplingM = mVal; r.psiSat = psi; r.concentration = conc;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-4B-S 完成 ===');
    fclose(flog);
    fprintf('EXP-4B-S 完成: %d 实例\n', total);
end
