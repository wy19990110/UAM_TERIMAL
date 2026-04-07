function runEXP6(outDir)
    % runEXP6  向下比 incumbent abstractions (二轮修改: 分层报告)
    %   模型: B0 / B1 / M1 / M2N / JO (去掉 PR, 等 4D 修好再回来)
    %   指标: median truth excess cost, P90, sufficiency rate (<3%, <5%)
    %   展示方式按 regime 分层:
    %     phiF=0, 0<phiF<0.4, phiF>=0.4, E_A>=0.7 子样本
    arguments
        outDir (1,1) string = "results/exp6"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp6_log.txt");
    cpFile = fullfile(outDir, "exp6_checkpoint.mat");
    resultFile = fullfile(outDir, "exp6_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    families = struct('name',{'G1s','G2s','G3s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
                struct('nT',3,'nW',3,'targetEdges',[6,9],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
    seeds = 1:3;
    rhoVals = [0.5, 0.8, 1.0, 1.2];
    alphaAVals = [0, 0.25, 0.5];
    phiFVals = [0, 0.2, 0.5];

    combos = {};
    for fi = 1:numel(families)
        for si = 1:numel(seeds)
            for ri = 1:numel(rhoVals)
                for ai = 1:numel(alphaAVals)
                    for pi = 1:numel(phiFVals)
                        combos{end+1} = struct('fi',fi,'si',si,'ri',ri,'ai',ai,'pi',pi); %#ok<AGROW>
                    end
                end
            end
        end
    end
    total = numel(combos);
    logmsg(sprintf('=== EXP-6 Incumbent Benchmark (二轮): %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        if numel(cp.completed) == total
            results = cp.results;
            completed = cp.completed;
            logmsg(sprintf('加载 checkpoint: %d/%d', sum(completed), total));
        else
            results = cell(total, 1);
            completed = false(total, 1);
        end
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
        sd = seeds(c.si); rho = rhoVals(c.ri);
        aA = alphaAVals(c.ai); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.2f pF=%.1f', ...
            idx, total, fname, sd, rho, aA, pF));
        t0 = tic;
        try
            params = struct('alphaA', aA, 'kappaS', 2, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 提取所有接口 (二轮: M2N 代替 M2)
            b0i = containers.Map(); b1i = containers.Map();
            m0i = containers.Map(); m1i = containers.Map(); m2ni = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                b0i(tkeys{ti}) = asf.interface.extractB0(t);
                b1i(tkeys{ti}) = asf.interface.extractB1(t, inst);
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
            end
            ifaces = containers.Map();
            ifaces('B0') = b0i; ifaces('B1') = b1i;
            ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2ni;

            allLevels = ["B0";"B1";"M0";"M1";"M2"];
            res = asf.solver.computeRegret(inst, allLevels, ifaces, opts);
            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.time = elapsed; r.error = "";
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;

            for lv = allLevels'
                tag = char(lv);
                % M2 在结果中实际是 M2N
                lr = res.(tag);
                r.(tag).regret = lr.regret;
                r.(tag).relRegret = lr.relRegret;
                r.(tag).tdBB = lr.tdBB;
                r.(tag).recoveryRate = lr.recoveryRate;
                r.(tag).jTruth = lr.jTruth;
                r.(tag).solveTime = lr.solveTime;
                % truth excess cost (绝对值)
                r.(tag).excessCost = lr.regret;
            end

            results{idx} = r;
            logmsg(sprintf('  B0=%.1f%% B1=%.1f%% M1=%.1f%% M2N=%.1f%% (%.1fs)', ...
                res.B0.relRegret*100, res.B1.relRegret*100, ...
                res.M1.relRegret*100, res.M2.relRegret*100, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-6 数据收集完成 ===');

    % === 分层汇总 ===
    modelTags = ["B0","B1","M0","M1","M2"];
    modelLabels = ["B0","B1","M0","M1","M2N"];

    % 收集有效结果
    validResults = {};
    for idx = 1:total
        r = results{idx};
        if ~isempty(r) && (isempty(r.error) || r.error == "")
            validResults{end+1} = r; %#ok<AGROW>
        end
    end

    % 定义 regime 切片
    regimes = struct('name', {}, 'filter', {});
    regimes(1) = struct('name', 'phiF=0', 'filter', @(r) abs(r.phiF) < 1e-6);
    regimes(2) = struct('name', '0<phiF<0.4', 'filter', @(r) r.phiF > 1e-6 && r.phiF < 0.4);
    regimes(3) = struct('name', 'phiF>=0.4', 'filter', @(r) r.phiF >= 0.4);
    regimes(4) = struct('name', 'E_A>=0.7', 'filter', @(r) r.E_A >= 0.7);

    fprintf('\n=== EXP-6 Regime-Stratified Results ===\n');
    for ri = 1:numel(regimes)
        regime = regimes(ri);
        subset = {};
        for vi = 1:numel(validResults)
            if regime.filter(validResults{vi})
                subset{end+1} = validResults{vi}; %#ok<AGROW>
            end
        end
        n = numel(subset);
        fprintf('\n--- %s (n=%d) ---\n', regime.name, n);
        fprintf('%-5s  %10s  %10s  %8s  %8s\n', 'Model', 'med_excess', 'P90_excess', 'suff<3%', 'suff<5%');

        for mi = 1:numel(modelTags)
            tag = char(modelTags(mi));
            excessVals = [];
            for si2 = 1:n
                if isfield(subset{si2}, tag) && isfield(subset{si2}.(tag), 'relRegret')
                    excessVals(end+1) = subset{si2}.(tag).relRegret; %#ok<AGROW>
                end
            end
            if isempty(excessVals)
                fprintf('%-5s  %10s  %10s  %8s  %8s\n', modelLabels(mi), 'N/A','N/A','N/A','N/A');
                continue;
            end
            medExcess = median(excessVals);
            p90Excess = quantile(excessVals, 0.90);
            suff3 = mean(abs(excessVals) < 0.03);
            suff5 = mean(abs(excessVals) < 0.05);
            fprintf('%-5s  %9.2f%%  %9.2f%%  %7.0f%%  %7.0f%%\n', ...
                modelLabels(mi), medExcess*100, p90Excess*100, suff3*100, suff5*100);
        end

        logmsg(sprintf('Regime %s: n=%d', regime.name, n));
    end

    logmsg('=== EXP-6 完成 ===');
    fclose(flog);
end
