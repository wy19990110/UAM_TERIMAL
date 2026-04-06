function runEXP4D(outDir)
    % runEXP4D Held-out recommendation map (规则式分层规划器)
    %   按新的实验要求 §一.6:
    %   1) 收集实例数据: E_A/E_S/E_F + j_m0/j_m1/j_m2
    %   2) 70/30 train/test split
    %   3) Train: grid search 阈值规则 (E_A, E_S, E_F) -> M0/M1/M2
    %   4) Test: accuracy, excess regret, vs "always M1"/"always M2"
    %   5) 导出 calibrated_rule.mat 供 EXP-6/7/8 使用
    arguments
        outDir (1,1) string = "results/exp4d"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4d_log.txt");
    cpFile = fullfile(outDir, "exp4d_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4d_results.mat");
    ruleFile = fullfile(outDir, "calibrated_rule.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % ========== 阶段一: 数据收集 ==========
    families = struct('name',{'G1s','G2s','G3a','G4ap'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
                struct('nT',4,'nW',4,'targetEdges',[8,11]), ...
                struct('nT',3,'nW',3,'targetEdges',[6,9],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
    seeds = 1:4;

    rhoVals = [0.5, 1.0, 1.5];
    alphaAVals = [0, 0.3, 0.6];
    kappaSVals = [1, 3];
    phiFVals = [0, 0.2, 0.5];

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
    total = numel(combos);
    logmsg(sprintf('=== EXP-4D Held-out: %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        results = cp.results;
        completed = cp.completed;
        logmsg(sprintf('加载 checkpoint: %d/%d', sum(completed), total));
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
        aA = alphaAVals(c.ai); kS = kappaSVals(c.ki); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.1f kS=%d pF=%.1f', ...
            idx, total, fname, sd, rho, aA, kS, pF));
        t0 = tic;
        try
            params = struct('alphaA', aA, 'kappaS', kS, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);
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
            r.jM0 = res.M0.jTruth; r.jM1 = res.M1.jTruth; r.jM2 = res.M2.jTruth;
            r.m0Rel = res.M0.relRegret; r.m1Rel = res.M1.relRegret; r.m2Rel = res.M2.relRegret;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            % Truth-best-in-family
            [~, bestIdx] = min([r.jM0, r.jM1, r.jM2]);
            labels = ["M0","M1","M2"];
            r.truthBest = labels(bestIdx);
            r.time = elapsed; r.error = "";
            results{idx} = r;
            logmsg(sprintf('  Best=%s E_A=%.3f E_S=%.3f E_F=%.3f (%.1fs)', ...
                r.truthBest, r.E_A, r.E_S, r.E_F, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.kappaS = kS; r.phiF = pF;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    % ========== 阶段二: Train/Test Split + Rule Calibration ==========
    logmsg('=== 阶段二: Rule Calibration ===');

    % 收集有效记录
    validIdx = [];
    for idx = 1:total
        r = results{idx};
        if ~isempty(r) && (isempty(r.error) || r.error == "")
            validIdx(end+1) = idx; %#ok<AGROW>
        end
    end
    nValid = numel(validIdx);
    logmsg(sprintf('有效实例: %d/%d', nValid, total));

    if nValid < 10
        logmsg('有效实例不足, 跳过 calibration');
        save(resultFile, 'results', 'combos');
        fclose(flog);
        return;
    end

    % 70/30 split
    rng(42);
    perm = randperm(nValid);
    nTrain = round(nValid * 0.7);
    trainIdx = validIdx(perm(1:nTrain));
    testIdx = validIdx(perm(nTrain+1:end));

    % Grid search on train
    bestAccuracy = -1;
    bestRule = struct('eaThresh', 0.3, 'esThresh', 0.5, 'efThresh', 0.2);

    eaGrid = 0.1:0.1:0.7;
    esGrid = 0.2:0.1:1.0;
    efGrid = 0.1:0.1:0.5;

    for ea = eaGrid
        for es = esGrid
            for ef = efGrid
                correct = 0;
                for ii = 1:numel(trainIdx)
                    r = results{trainIdx(ii)};
                    rec = applyRule(r.E_A, r.E_S, r.E_F, ea, es, ef);
                    if rec == r.truthBest
                        correct = correct + 1;
                    end
                end
                acc = correct / numel(trainIdx);
                if acc > bestAccuracy
                    bestAccuracy = acc;
                    bestRule = struct('eaThresh', ea, 'esThresh', es, 'efThresh', ef);
                end
            end
        end
    end

    logmsg(sprintf('最佳规则: E_A>=%.1f→M1, E_S>=%.1f→M1, E_F>=%.1f→M2 (train acc=%.1f%%)', ...
        bestRule.eaThresh, bestRule.esThresh, bestRule.efThresh, bestAccuracy*100));

    % ========== 阶段三: Test Set 评估 ==========
    nTest = numel(testIdx);
    correct = 0;
    totalExcess = 0;
    alwaysM1Excess = 0;
    alwaysM2Excess = 0;
    recCounts = struct('M0', 0, 'M1', 0, 'M2', 0);

    for ii = 1:nTest
        r = results{testIdx(ii)};
        rec = applyRule(r.E_A, r.E_S, r.E_F, bestRule.eaThresh, bestRule.esThresh, bestRule.efThresh);
        recCounts.(char(rec)) = recCounts.(char(rec)) + 1;

        if rec == r.truthBest
            correct = correct + 1;
        end

        bestJ = min([r.jM0, r.jM1, r.jM2]);
        jMap = struct('M0', r.jM0, 'M1', r.jM1, 'M2', r.jM2);
        recJ = jMap.(char(rec));
        totalExcess = totalExcess + max(0, recJ - bestJ);
        alwaysM1Excess = alwaysM1Excess + max(0, r.jM1 - bestJ);
        alwaysM2Excess = alwaysM2Excess + max(0, r.jM2 - bestJ);
    end

    evaluation = struct();
    evaluation.accuracy = correct / max(nTest, 1);
    evaluation.meanExcessRegret = totalExcess / max(nTest, 1);
    evaluation.alwaysM1Excess = alwaysM1Excess / max(nTest, 1);
    evaluation.alwaysM2Excess = alwaysM2Excess / max(nTest, 1);
    evaluation.modelDistribution = recCounts;
    evaluation.rule = bestRule;
    evaluation.nTrain = nTrain;
    evaluation.nTest = nTest;

    logmsg(sprintf('Test: accuracy=%.1f%%, excess=%.4f, alwaysM1=%.4f, alwaysM2=%.4f', ...
        evaluation.accuracy*100, evaluation.meanExcessRegret, ...
        evaluation.alwaysM1Excess, evaluation.alwaysM2Excess));
    logmsg(sprintf('分布: M0=%d, M1=%d, M2=%d', recCounts.M0, recCounts.M1, recCounts.M2));

    % 保存
    save(resultFile, 'results', 'combos', 'evaluation');

    % 导出 calibrated rule（供 EXP-6/7/8 使用）
    calibratedRule = bestRule;
    save(ruleFile, 'calibratedRule');
    logmsg(sprintf('Calibrated rule 已保存到 %s', ruleFile));

    logmsg('=== EXP-4D 完成 ===');
    fclose(flog);

    % 控制台输出
    fprintf('\n=== EXP-4D Held-out Recommendation Map ===\n');
    fprintf('Rule: E_A>=%.2f→M1, E_S>=%.2f→M1, E_F>=%.2f→M2\n', ...
        bestRule.eaThresh, bestRule.esThresh, bestRule.efThresh);
    fprintf('Train accuracy: %.1f%% (%d instances)\n', bestAccuracy*100, nTrain);
    fprintf('Test accuracy:  %.1f%% (%d instances)\n', evaluation.accuracy*100, nTest);
    fprintf('Excess regret:  PR=%.4f, alwaysM1=%.4f, alwaysM2=%.4f\n', ...
        evaluation.meanExcessRegret, evaluation.alwaysM1Excess, evaluation.alwaysM2Excess);
    fprintf('Distribution: M0=%d, M1=%d, M2=%d\n', recCounts.M0, recCounts.M1, recCounts.M2);
end


function rec = applyRule(E_A, E_S, E_F, eaThresh, esThresh, efThresh)
    % 阈值规则: E_F >= thresh → M2; E_A >= thresh or E_S >= thresh → M1; else M0
    if E_F >= efThresh
        rec = "M2";
    elseif E_A >= eaThresh || E_S >= esThresh
        rec = "M1";
    else
        rec = "M0";
    end
end
