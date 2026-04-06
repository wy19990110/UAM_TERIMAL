function runEXP7(outDir)
    % runEXP7 向上比 integrated upper bound (JO)
    %   按新的实验要求 §二.9:
    %   JO 是 integrated upper-bound benchmark (= Mstar, joint optimization)
    %   Small: 3-4 terminals, 2-3 waypoints, 尽量 exact
    %   Medium: 5-6 terminals, 3-4 waypoints, time-limited + gap
    %
    %   比较: B0 / B1 / M1(=O1) / M2(=O2) / PR / JO
    %   核心输出:
    %     - gap to JO per model
    %     - PR gap closure vs B0/B1
    %     - JO vs PR runtime ratio
    arguments
        outDir (1,1) string = "results/exp7"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp7_log.txt");
    cpFile = fullfile(outDir, "exp7_checkpoint.mat");
    resultFile = fullfile(outDir, "exp7_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 加载 calibrated rule
    ruleFile = fullfile('results', 'exp4d', 'calibrated_rule.mat');
    if exist(ruleFile, 'file')
        rl = load(ruleFile);
        rule = rl.calibratedRule;
        logmsg(sprintf('加载 rule: E_A>=%.2f, E_S>=%.2f, E_F>=%.2f', ...
            rule.eaThresh, rule.esThresh, rule.efThresh));
    else
        logmsg('未找到 calibrated_rule.mat, 使用默认规则');
        rule = struct('eaThresh', 0.3, 'esThresh', 0.5, 'efThresh', 0.2);
    end

    % Small + medium specs
    families = struct('name',{'JO_S','JO_M'}, ...
        'spec',{struct('nT',3,'nW',2,'targetEdges',[4,6]), ...
                struct('nT',5,'nW',3,'targetEdges',[9,13])});
    seeds = 1:5;
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
    logmsg(sprintf('=== EXP-7 JO Upper Bound: %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        results = cp.results;
        completed = cp.completed;
        logmsg(sprintf('加载 checkpoint: %d/%d', sum(completed), total));
    else
        results = cell(total, 1);
        completed = false(total, 1);
    end

    opts = struct('nPwl', 15, 'verbose', false, 'truthLevel', 'JO');

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

            % 提取所有接口
            b0i = containers.Map(); b1i = containers.Map();
            m1i = containers.Map(); m2i = containers.Map();
            m0i = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                b0i(tkeys{ti}) = asf.interface.extractB0(t);
                b1i(tkeys{ti}) = asf.interface.extractB1(t, inst);
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
            end
            ifaces = containers.Map();
            ifaces('B0') = b0i; ifaces('B1') = b1i;
            ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2i;

            allLevels = ["B0";"B1";"M1";"M2"];
            res = asf.solver.computeRegret(inst, allLevels, ifaces, opts);
            elapsed = toc(t0);

            % JO 的 truth objective 就是 J*
            jJO = res.star.jTruth;
            joTime = res.star.solveTime;

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.jJO = jJO;
            r.joSolveTime = joTime;
            r.time = elapsed; r.error = "";

            for lv = allLevels'
                tag = char(lv);
                lr = res.(tag);
                r.(tag).jTruth = lr.jTruth;
                r.(tag).gapToJO = lr.jTruth - jJO;
                r.(tag).gapToJOPct = (lr.jTruth - jJO) / max(abs(jJO), 1e-10);
                r.(tag).tdBB = lr.tdBB;
                r.(tag).solveTime = lr.solveTime;
            end

            % PR
            E_A = inst.excitation.E_A;
            E_S = inst.excitation.E_S;
            E_F = inst.excitation.E_F;
            r.E_A = E_A; r.E_S = E_S; r.E_F = E_F;
            prRec = applyRule(E_A, E_S, E_F, rule.eaThresh, rule.esThresh, rule.efThresh);
            r.prRecommendation = char(prRec);
            % PR 模型从已求解的 levels 中取（M1 或 M2, M0 不在 allLevels）
            if prRec == "M0"
                % M0 未求解，用 B0 近似（B0 = M0 的 incumbent 版本）
                prData = res.B0;
            else
                prData = res.(char(prRec));
            end
            r.PR.jTruth = prData.jTruth;
            r.PR.gapToJO = prData.jTruth - jJO;
            r.PR.gapToJOPct = (prData.jTruth - jJO) / max(abs(jJO), 1e-10);
            r.PR.solveTime = prData.solveTime;

            % Gap closure
            b0Gap = r.B0.gapToJO;
            b1Gap = r.B1.gapToJO;
            prGap = r.PR.gapToJO;
            if b0Gap > 1e-10
                r.prGapClosureVsB0 = 1 - prGap / b0Gap;
            else
                r.prGapClosureVsB0 = 0;
            end
            if b1Gap > 1e-10
                r.prGapClosureVsB1 = 1 - prGap / b1Gap;
            else
                r.prGapClosureVsB1 = 0;
            end

            % Runtime ratio
            if r.PR.solveTime > 1e-6
                r.joVsPrRuntimeRatio = joTime / r.PR.solveTime;
            else
                r.joVsPrRuntimeRatio = Inf;
            end

            results{idx} = r;
            logmsg(sprintf('  JO=%.1f B0gap=%.1f%% M2gap=%.1f%% PRgap=%.1f%% closure=%.1f%% (%.1fs)', ...
                jJO, r.B0.gapToJOPct*100, r.M2.gapToJOPct*100, r.PR.gapToJOPct*100, ...
                r.prGapClosureVsB0*100, elapsed));
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
    logmsg('=== EXP-7 完成 ===');
    fclose(flog);

    % 控制台汇总
    fprintf('\n=== EXP-7 JO Upper Bound 汇总 ===\n');
    nValid = 0; sumGap = struct('B0',0,'B1',0,'M1',0,'M2',0,'PR',0);
    sumClosure = 0;
    for idx = 1:total
        r = results{idx};
        if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
        nValid = nValid + 1;
        for lv = ["B0","B1","M1","M2","PR"]
            sumGap.(char(lv)) = sumGap.(char(lv)) + r.(char(lv)).gapToJOPct;
        end
        sumClosure = sumClosure + r.prGapClosureVsB0;
    end
    if nValid > 0
        fprintf('平均 gap to JO (%d 实例):\n', nValid);
        for lv = ["B0","B1","M1","M2","PR"]
            fprintf('  %s: %.2f%%\n', lv, sumGap.(char(lv))/nValid*100);
        end
        fprintf('PR gap closure vs B0: %.1f%%\n', sumClosure/nValid*100);
    end
end


function rec = applyRule(E_A, E_S, E_F, eaThresh, esThresh, efThresh)
    if E_F >= efThresh
        rec = "M2";
    elseif E_A >= eaThresh || E_S >= esThresh
        rec = "M1";
    else
        rec = "M0";
    end
end
