function runEXP6(outDir)
    % runEXP6 向下比 incumbent abstractions
    %   按新的实验要求 §二.8:
    %   比较 B0/B1/M0/M1(=O1)/M2(=O2)/PR，共用同一 candidate graph + truth re-evaluation
    %   核心指标: truth regret, topology distance, recovery rate, runtime
    %   回答: "我们的抽象比现有抽象到底好多少"
    arguments
        outDir (1,1) string = "results/exp6"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp6_log.txt");
    cpFile = fullfile(outDir, "exp6_checkpoint.mat");
    resultFile = fullfile(outDir, "exp6_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 加载 calibrated rule (from EXP-4D)
    ruleFile = fullfile('results', 'exp4d', 'calibrated_rule.mat');
    if exist(ruleFile, 'file')
        rl = load(ruleFile);
        rule = rl.calibratedRule;
        logmsg(sprintf('加载 rule: E_A>=%.2f→M1, E_S>=%.2f→M1, E_F>=%.2f→M2', ...
            rule.eaThresh, rule.esThresh, rule.efThresh));
    else
        logmsg('未找到 calibrated_rule.mat, 使用默认规则');
        rule = struct('eaThresh', 0.3, 'esThresh', 0.5, 'efThresh', 0.2);
    end

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
    logmsg(sprintf('=== EXP-6 Incumbent Benchmark: %d 实例 ===', total));

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
        aA = alphaAVals(c.ai); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.2f pF=%.1f', ...
            idx, total, fname, sd, rho, aA, pF));
        t0 = tic;
        try
            params = struct('alphaA', aA, 'kappaS', 2, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 提取所有接口
            b0i = containers.Map(); b1i = containers.Map();
            m0i = containers.Map(); m1i = containers.Map(); m2i = containers.Map();
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

            allLevels = ["B0";"B1";"M0";"M1";"M2"];
            res = asf.solver.computeRegret(inst, allLevels, ifaces, opts);
            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.time = elapsed; r.error = "";

            for lv = allLevels'
                tag = char(lv);
                lr = res.(tag);
                r.(tag).regret = lr.regret;
                r.(tag).relRegret = lr.relRegret;
                r.(tag).tdBB = lr.tdBB;
                r.(tag).recoveryRate = lr.recoveryRate;
                r.(tag).jTruth = lr.jTruth;
                r.(tag).solveTime = lr.solveTime;
            end

            % PR: 用 rule 选择模型
            E_A = inst.excitation.E_A;
            E_S = inst.excitation.E_S;
            E_F = inst.excitation.E_F;
            r.E_A = E_A; r.E_S = E_S; r.E_F = E_F;
            prRec = applyRule(E_A, E_S, E_F, rule.eaThresh, rule.esThresh, rule.efThresh);
            r.prRecommendation = char(prRec);
            prData = res.(char(prRec));
            r.PR.jTruth = prData.jTruth;
            r.PR.regret = prData.regret;
            r.PR.relRegret = prData.relRegret;
            r.PR.tdBB = prData.tdBB;
            r.PR.recoveryRate = prData.recoveryRate;
            r.PR.solveTime = prData.solveTime;

            results{idx} = r;
            logmsg(sprintf('  B0=%.1f%% B1=%.1f%% M1=%.1f%% M2=%.1f%% PR(%s)=%.1f%% (%.1fs)', ...
                res.B0.relRegret*100, res.B1.relRegret*100, ...
                res.M1.relRegret*100, res.M2.relRegret*100, ...
                r.prRecommendation, r.PR.relRegret*100, elapsed));
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
    logmsg('=== EXP-6 完成 ===');
    fclose(flog);

    % 控制台汇总
    fprintf('\n=== EXP-6 Incumbent Benchmark 汇总 ===\n');
    nValid = 0; sums = struct('B0',0,'B1',0,'M0',0,'M1',0,'M2',0,'PR',0);
    for idx = 1:total
        r = results{idx};
        if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
        nValid = nValid + 1;
        for lv = ["B0","B1","M0","M1","M2","PR"]
            sums.(char(lv)) = sums.(char(lv)) + abs(r.(char(lv)).relRegret);
        end
    end
    if nValid > 0
        fprintf('平均 |relative regret| (%d 实例):\n', nValid);
        for lv = ["B0","B1","M0","M1","M2","PR"]
            fprintf('  %s: %.2f%%\n', lv, sums.(char(lv))/nValid*100);
        end
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
