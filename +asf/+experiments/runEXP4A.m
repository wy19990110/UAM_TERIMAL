function runEXP4A(outDir)
    % runEXP4A 数值校准门控实验
    %   40-60 实例，高精度 PwL(nPwl=31)
    %   过关标准：φF=0 子集 baseline regret 中位 < 1%, P95 < 3%
    arguments
        outDir (1,1) string = "results/exp4a"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4a_log.txt");
    cpFile = fullfile(outDir, "exp4a_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4a_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % === 图族定义（3 图族 × 2 seeds）===
    families = struct('name',{'G1s','G2s','G3s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
                struct('nT',3,'nW',3,'targetEdges',[6,9],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
    seeds = 1:2;

    % 参数：φF=0 为主(校准baseline)，加少量 φF>0 对照
    rhoVals = [0.5, 0.8, 1.0, 1.2];
    alphaAVals = [0, 0.25, 0.5];
    kappaSVals = [1, 2];
    phiFVals = [0, 0, 0, 0.3];  % 75% φF=0, 25% φF=0.3

    % 参数组合
    combos = {};
    for fi = 1:numel(families)
        for si = 1:numel(seeds)
            for ri = 1:numel(rhoVals)
                for ai = 1:numel(alphaAVals)
                    for ki = 1:numel(kappaSVals)
                        for pi = 1:numel(phiFVals)
                            combos{end+1} = struct('fi',fi,'si',si,'ri',ri,'ai',ai,'ki',ki,'pi',pi); %#ok<AGROW>
                        end
                    end
                end
            end
        end
    end
    % 为了控制在 40-60 实例，如果 combos 太多就随机采样
    total = numel(combos);
    if total > 60
        rng(999);
        idx = randperm(total, 60);
        combos = combos(idx);
        total = 60;
    end

    logmsg(sprintf('=== EXP-4A 校准: %d 实例, nPwl=31 ===', total));

    % 加载 checkpoint
    if exist(cpFile, 'file')
        cp = load(cpFile);
        results = cp.results;
        completed = cp.completed;
        logmsg(sprintf('加载 checkpoint: %d/%d 已完成', sum(completed), total));
    else
        results = cell(total, 1);
        completed = false(total, 1);
    end

    opts = struct('nPwl', 31, 'verbose', false);

    for idx = 1:total
        if completed(idx), continue; end

        c = combos{idx};
        fname = families(c.fi).name;
        spec = families(c.fi).spec;
        sd = seeds(c.si);
        rho = rhoVals(c.ri);
        aA = alphaAVals(c.ai);
        kS = kappaSVals(c.ki);
        pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.2f kS=%d pF=%.1f', ...
            idx, total, fname, sd, rho, aA, kS, pF));

        t0 = tic;
        try
            params = struct('alphaA', aA, 'kappaS', kS, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 提取接口
            m0i = containers.Map(); m1i = containers.Map(); m2i = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2i;

            res = asf.solver.computeRegret(inst, ["M0";"M1";"M2"], ifaces, opts);
            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.kappaS = kS; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.m0Rel = res.M0.relRegret; r.m1Rel = res.M1.relRegret; r.m2Rel = res.M2.relRegret;
            r.U01 = res.relU01; r.U12 = res.relU12; r.U02 = res.relU02;
            r.recommendation = res.recommendation;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            r.time = elapsed; r.error = "";
            results{idx} = r;

            logmsg(sprintf('  J*=%.1f M0=%.1f%% M1=%.1f%% M2=%.1f%% U01=%.1f%% U12=%.1f%% (%.1fs)', ...
                res.star.jTruth, res.M0.relRegret*100, res.M1.relRegret*100, ...
                res.M2.relRegret*100, res.relU01*100, res.relU12*100, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.kappaS = kS; r.phiF = pF;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s (%.1fs)', ME.message, elapsed));
        end

        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    % === 门控分析 ===
    logmsg('=== 门控分析 ===');
    phiF0_regrets = [];
    phiFPos_regrets = [];
    for idx = 1:total
        r = results{idx};
        if isempty(r) || ~isempty(r.error), continue; end
        baselineRegret = max([abs(r.m0Rel), abs(r.m1Rel), abs(r.m2Rel)]);
        if r.phiF == 0
            phiF0_regrets(end+1) = baselineRegret; %#ok<AGROW>
        else
            phiFPos_regrets(end+1) = baselineRegret; %#ok<AGROW>
        end
    end

    if ~isempty(phiF0_regrets)
        medRegret = median(phiF0_regrets);
        p95Regret = prctile(phiF0_regrets, 95);
        gatePass = medRegret < 0.01 && p95Regret < 0.03;
        logmsg(sprintf('φF=0 baseline: median=%.2f%%, P95=%.2f%% → %s', ...
            medRegret*100, p95Regret*100, string(ternary(gatePass, "PASS", "FAIL"))));
    end

    % 保存结果
    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-4A 完成 ===');
    fclose(flog);

    % 控制台输出
    if ~isempty(phiF0_regrets)
        fprintf('\n=== EXP-4A 校准门控 ===\n');
        fprintf('φF=0 实例数: %d\n', numel(phiF0_regrets));
        fprintf('Baseline regret median: %.2f%%\n', median(phiF0_regrets)*100);
        fprintf('Baseline regret P95: %.2f%%\n', prctile(phiF0_regrets, 95)*100);
        fprintf('门控: %s\n', string(ternary(medRegret<0.01 && p95Regret<0.03, "PASS", "FAIL")));
    end
end

function v = ternary(cond, a, b)
    if cond, v = a; else, v = b; end
end
