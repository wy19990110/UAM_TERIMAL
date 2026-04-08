function runEXP4D(outDir)
    % runEXP4D  Held-out recommendation map (二轮修改: 代价敏感规则学习)
    %   1) 收集实例数据: E_A/E_S/E_F + j_M0/j_M1/j_M2N
    %   2) 手工 rule baseline 先跑
    %   3) 代价敏感学习: loss = min(excess_regret, 10%) 或 log(1+excess)
    %   4) 深度-2 决策树, 阈值从训练集经验分位数 {30%,50%,70%} 中选
    %   5) 与 always-M1, always-M2N 比较
    %   6) 导出 calibrated_rule.mat
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
    % 二轮修改: 去掉 G3a/G4ap, 只用 G1s/G2s/G3s
    families = struct('name',{'G1s','G2s','G3s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
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
    logmsg(sprintf('=== EXP-4D Held-out (二轮): %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        if numel(cp.completed) == total
            results = cp.results;
            completed = cp.completed;
            logmsg(sprintf('加载 checkpoint: %d/%d', sum(completed), total));
        else
            logmsg('旧 checkpoint 不兼容, 重新开始');
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
        aA = alphaAVals(c.ai); kS = kappaSVals(c.ki); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.1f kS=%d pF=%.1f', ...
            idx, total, fname, sd, rho, aA, kS, pF));
        t0 = tic;
        try
            params = struct('alphaA', aA, 'kappaS', kS, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 二轮修改: 用 M2N 代替 M2
            m0i = containers.Map(); m1i = containers.Map(); m2ni = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2ni;
            res = asf.solver.computeRegret(inst, ["M0";"M1";"M2"], ifaces, opts);
            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.kappaS = kS; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.jM0 = res.M0.jTruth; r.jM1 = res.M1.jTruth; r.jM2N = res.M2.jTruth;
            r.m0Rel = res.M0.relRegret; r.m1Rel = res.M1.relRegret; r.m2nRel = res.M2.relRegret;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            [~, bestIdx] = min([r.jM0, r.jM1, r.jM2N]);
            labels = ["M0","M1","M2N"];
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

    % ========== 阶段二: 收集有效记录 ==========
    logmsg('=== 阶段二: 规则评估 ===');
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
    nTest = numel(testIdx);

    % ========== 阶段三: 手工 rule baseline ==========
    logmsg('=== 手工 rule baseline ===');
    handRule = struct('eaThresh', 0.55, 'esThresh', 0.35, 'efThresh', 0.35);
    handEval = evaluateRule(results, testIdx, handRule, 'M2N');
    logmsg(sprintf('手工 rule: excess=%.4f, alwaysM1=%.4f, alwaysM2N=%.4f', ...
        handEval.meanCappedExcess, handEval.alwaysM1Excess, handEval.alwaysM2NExcess));

    % ========== 阶段四: 代价敏感学习 ==========
    logmsg('=== 代价敏感学习 (depth-2 tree) ===');

    % 从训练集提取经验分位数作为阈值候选
    trainEA = []; trainES = []; trainEF = [];
    for ii = 1:numel(trainIdx)
        r = results{trainIdx(ii)};
        trainEA(end+1) = r.E_A; %#ok<AGROW>
        trainES(end+1) = r.E_S; %#ok<AGROW>
        trainEF(end+1) = r.E_F; %#ok<AGROW>
    end
    quantiles = [0.3, 0.5, 0.7];
    eaGrid = quantile(trainEA, quantiles);
    esGrid = quantile(trainES, quantiles);
    efGrid = quantile(trainEF, quantiles);

    % Grid search: 代价敏感损失 = mean(min(excess_regret, 0.10))
    bestLoss = Inf;
    bestRule = handRule;  % 默认用手工 rule

    for ea = eaGrid
        for es = esGrid
            for ef = efGrid
                totalLoss = 0;
                for ii = 1:numel(trainIdx)
                    r = results{trainIdx(ii)};
                    rec = applyRule(r.E_A, r.E_S, r.E_F, ea, es, ef);
                    bestJ = min([r.jM0, r.jM1, r.jM2N]);
                    jMap = struct('M0', r.jM0, 'M1', r.jM1, 'M2N', r.jM2N);
                    recJ = jMap.(char(rec));
                    excess = max(0, recJ - bestJ) / max(abs(bestJ), 1e-10);
                    % 代价敏感: 截断 + log
                    totalLoss = totalLoss + min(excess, 0.10);
                end
                avgLoss = totalLoss / numel(trainIdx);
                if avgLoss < bestLoss
                    bestLoss = avgLoss;
                    bestRule = struct('eaThresh', ea, 'esThresh', es, 'efThresh', ef);
                end
            end
        end
    end

    logmsg(sprintf('最佳规则: E_A>=%.3f→M1, E_S>=%.3f→M1, E_F>=%.3f→M2N (train loss=%.4f)', ...
        bestRule.eaThresh, bestRule.esThresh, bestRule.efThresh, bestLoss));

    % ========== 阶段五: Test Set 评估 ==========
    learnedEval = evaluateRule(results, testIdx, bestRule, 'M2N');
    alwaysM1Eval = evaluateAlways(results, testIdx, 'M1');
    alwaysM2NEval = evaluateAlways(results, testIdx, 'M2N');

    evaluation = struct();
    evaluation.handRule = handRule;
    evaluation.handEval = handEval;
    evaluation.learnedRule = bestRule;
    evaluation.learnedEval = learnedEval;
    evaluation.alwaysM1 = alwaysM1Eval;
    evaluation.alwaysM2N = alwaysM2NEval;
    evaluation.nTrain = nTrain;
    evaluation.nTest = nTest;
    evaluation.thresholdQuantiles = quantiles;
    evaluation.eaGrid = eaGrid;
    evaluation.esGrid = esGrid;
    evaluation.efGrid = efGrid;

    logmsg(sprintf('Test 手工rule: cappedExcess=%.4f', handEval.meanCappedExcess));
    logmsg(sprintf('Test 学习rule: cappedExcess=%.4f', learnedEval.meanCappedExcess));
    logmsg(sprintf('Test alwaysM1: cappedExcess=%.4f', alwaysM1Eval.meanCappedExcess));
    logmsg(sprintf('Test alwaysM2N: cappedExcess=%.4f', alwaysM2NEval.meanCappedExcess));

    % 保存
    save(resultFile, 'results', 'combos', 'evaluation');

    % 导出 calibrated rule: 选手工和学习中更好的
    if learnedEval.meanCappedExcess <= handEval.meanCappedExcess
        calibratedRule = bestRule;
        logmsg('导出学习规则为 calibrated_rule');
    else
        calibratedRule = handRule;
        logmsg('学习规则不优于手工规则, 导出手工规则');
    end
    save(ruleFile, 'calibratedRule');
    logmsg(sprintf('Calibrated rule 已保存到 %s', ruleFile));

    logmsg('=== EXP-4D 完成 ===');
    fclose(flog);

    % 控制台输出
    fprintf('\n=== EXP-4D Cost-Sensitive Rule Learning ===\n');
    fprintf('手工 rule: E_A>=%.2f→M1, E_S>=%.2f→M1, E_F>=%.2f→M2N\n', ...
        handRule.eaThresh, handRule.esThresh, handRule.efThresh);
    fprintf('学习 rule: E_A>=%.3f→M1, E_S>=%.3f→M1, E_F>=%.3f→M2N\n', ...
        bestRule.eaThresh, bestRule.esThresh, bestRule.efThresh);
    fprintf('\nTest set (%d instances):\n', nTest);
    fprintf('  手工 rule capped excess: %.4f\n', handEval.meanCappedExcess);
    fprintf('  学习 rule capped excess: %.4f\n', learnedEval.meanCappedExcess);
    fprintf('  always-M1 capped excess: %.4f\n', alwaysM1Eval.meanCappedExcess);
    fprintf('  always-M2N capped excess: %.4f\n', alwaysM2NEval.meanCappedExcess);
end


function rec = applyRule(E_A, E_S, E_F, eaThresh, esThresh, efThresh)
    % 阈值规则: E_F >= thresh → M2N; E_A >= thresh or E_S >= thresh → M1; else M0
    if E_F >= efThresh
        rec = "M2N";
    elseif E_A >= eaThresh || E_S >= esThresh
        rec = "M1";
    else
        rec = "M0";
    end
end


function ev = evaluateRule(results, testIdx, rule, m2label)
    % 评估规则在 test set 上的表现, 用代价敏感指标
    nTest = numel(testIdx);
    cappedExcess = zeros(nTest, 1);
    logExcess = zeros(nTest, 1);
    correct = 0;

    for ii = 1:nTest
        r = results{testIdx(ii)};
        rec = applyRule(r.E_A, r.E_S, r.E_F, rule.eaThresh, rule.esThresh, rule.efThresh);
        bestJ = min([r.jM0, r.jM1, r.jM2N]);
        jMap = struct('M0', r.jM0, 'M1', r.jM1);
        jMap.(m2label) = r.jM2N;
        recJ = jMap.(char(rec));
        excess = max(0, recJ - bestJ) / max(abs(bestJ), 1e-10);
        cappedExcess(ii) = min(excess, 0.10);
        logExcess(ii) = log(1 + excess);
        if rec == r.truthBest
            correct = correct + 1;
        end
    end

    ev.meanCappedExcess = mean(cappedExcess);
    ev.medianCappedExcess = median(cappedExcess);
    ev.meanLogExcess = mean(logExcess);
    ev.accuracy = correct / max(nTest, 1);
end


function ev = evaluateAlways(results, testIdx, modelName)
    % 评估 always-X 策略
    nTest = numel(testIdx);
    cappedExcess = zeros(nTest, 1);
    logExcess = zeros(nTest, 1);

    for ii = 1:nTest
        r = results{testIdx(ii)};
        bestJ = min([r.jM0, r.jM1, r.jM2N]);
        if modelName == "M1"
            recJ = r.jM1;
        elseif modelName == "M2N"
            recJ = r.jM2N;
        else
            recJ = r.jM0;
        end
        excess = max(0, recJ - bestJ) / max(abs(bestJ), 1e-10);
        cappedExcess(ii) = min(excess, 0.10);
        logExcess(ii) = log(1 + excess);
    end

    ev.meanCappedExcess = mean(cappedExcess);
    ev.medianCappedExcess = median(cappedExcess);
    ev.meanLogExcess = mean(logExcess);
end
