function runEXP7(outDir)
    % runEXP7  向上比 integrated upper bound (JO) (二轮修改)
    %   修改:
    %     - 去掉 PR (等 4D 修好)
    %     - 用 M2N 代替 M2
    %     - gap 指标改为: Delta_J / J_scale (J_scale = totalDemand * meanTC)
    %     - JO quality gate: 只有 optimal 或 MIPGap<=1e-3 才当 upper bound
    %     - 报告 median + IQR, 不用 mean
    arguments
        outDir (1,1) string = "results/exp7"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp7_log.txt");
    cpFile = fullfile(outDir, "exp7_checkpoint.mat");
    resultFile = fullfile(outDir, "exp7_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

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
    logmsg(sprintf('=== EXP-7 JO Upper Bound (二轮): %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        % 版本检查: v2 = tdBB 相对 JO 设计 + 新 gap 指标
        cpVersionOK = isfield(cp, 'cpVersion') && cp.cpVersion >= 2;
        if cpVersionOK && numel(cp.completed) == total
            results = cp.results;
            completed = cp.completed;
            logmsg(sprintf('加载 checkpoint v2: %d/%d', sum(completed), total));
        else
            if ~cpVersionOK
                logmsg('旧 checkpoint (v1) 不兼容新 tdBB 基线, 重新开始');
            else
                logmsg(sprintf('checkpoint 大小(%d)与网格(%d)不兼容, 重新开始', ...
                    numel(cp.completed), total));
            end
            results = cell(total, 1);
            completed = false(total, 1);
        end
    else
        results = cell(total, 1);
        completed = false(total, 1);
    end
    cpVersion = 2;  %#ok<NASGU> saved with checkpoint

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

            % 计算 J_scale (二轮修改: 尺度化分母)
            totalDemand = 0;
            dkeys = inst.odDemand.keys;
            for di = 1:numel(dkeys)
                totalDemand = totalDemand + inst.odDemand(dkeys{di});
            end
            ekeys = inst.edges.keys;
            meanTC = mean(arrayfun(@(k) inst.edges(char(k)).travelCost, string(ekeys)));
            J_scale = totalDemand * meanTC;

            % 提取接口 (M2N 代替 M2)
            b0i = containers.Map(); b1i = containers.Map();
            m1i = containers.Map(); m2ni = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                b0i(tkeys{ti}) = asf.interface.extractB0(t);
                b1i(tkeys{ti}) = asf.interface.extractB1(t, inst);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
            end
            ifaces = containers.Map();
            ifaces('B0') = b0i; ifaces('B1') = b1i;
            ifaces('M1') = m1i; ifaces('M2') = m2ni;

            allLevels = ["B0";"B1";"M1";"M2"];
            res = asf.solver.computeRegret(inst, allLevels, ifaces, opts);

            % === JO 求解 + quality gate ===
            tJO0 = tic;
            joDesign = asf.solver.solveMILP(inst, "JO", containers.Map(), opts);
            joTime = toc(tJO0);

            if joDesign.objective == Inf
                elapsed = toc(t0);
                r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
                r.alphaA = aA; r.phiF = pF;
                r.error = "JO_solve_failed"; r.time = elapsed;
                r.joSolveTime = joTime;
                results{idx} = r;
                logmsg(sprintf('  JO 求解失败 (%.1fs)', elapsed));
                completed(idx) = true;
                save(cpFile, 'results', 'completed', 'combos', 'cpVersion');
                continue;
            end
            [jJO, ~] = asf.solver.truthEvaluate(joDesign, inst);

            % JO quality gate (二轮修改)
            joOptimal = (joDesign.solveStatus == 1);
            joGapOK = (~isnan(joDesign.mipGap) && joDesign.mipGap <= 1e-3);
            joQualified = joOptimal || joGapOK;

            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.jJO = jJO;
            r.joSolveTime = joTime;
            r.joStatus = joDesign.solveStatus;
            r.joMipGap = joDesign.mipGap;
            r.joQualified = joQualified;
            r.J_scale = J_scale;
            r.time = elapsed; r.error = "";
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;

            for lv = allLevels'
                tag = char(lv);
                lr = res.(tag);
                r.(tag).jTruth = lr.jTruth;
                % 新 gap 指标 (二轮修改)
                r.(tag).deltaJ = lr.jTruth - jJO;  % 绝对 excess cost
                r.(tag).deltaJ_scaled = (lr.jTruth - jJO) / max(J_scale, 1e-10);  % 尺度化 excess
                % topology distance 相对 JO 设计 (不是 res.star.design)
                r.(tag).tdBB = lr.design.topologyDistBB(joDesign);
                r.(tag).solveTime = lr.solveTime;
            end

            results{idx} = r;
            logmsg(sprintf('  JO=%.1f(gap=%.1e,qual=%d) B0Δ=%.2f%% M2NΔ=%.2f%% (%.1fs)', ...
                jJO, joDesign.mipGap, joQualified, ...
                r.B0.deltaJ_scaled*100, r.M2.deltaJ_scaled*100, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = aA; r.phiF = pF;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos', 'cpVersion');
    end

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-7 完成 ===');
    fclose(flog);

    % 控制台汇总: median + IQR
    fprintf('\n=== EXP-7 JO Upper Bound (二轮) ===\n');
    modelTags = ["B0","B1","M1","M2"];
    modelLabels = ["B0","B1","M1","M2N"];

    % 只用 qualified JO 实例
    qualResults = {};
    unqualCount = 0;
    for idx = 1:total
        r = results{idx};
        if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
        if r.joQualified
            qualResults{end+1} = r; %#ok<AGROW>
        else
            unqualCount = unqualCount + 1;
        end
    end
    nQual = numel(qualResults);
    fprintf('Qualified JO instances: %d (uncertain: %d)\n\n', nQual, unqualCount);

    fprintf('%-5s  %10s  %10s  %10s\n', 'Model', 'med Δ/Js%', 'P25', 'P75');
    for mi = 1:numel(modelTags)
        tag = char(modelTags(mi));
        vals = [];
        for qi = 1:nQual
            if isfield(qualResults{qi}, tag) && isfield(qualResults{qi}.(tag), 'deltaJ_scaled')
                vals(end+1) = qualResults{qi}.(tag).deltaJ_scaled; %#ok<AGROW>
            end
        end
        if ~isempty(vals)
            fprintf('%-5s  %9.2f%%  %9.2f%%  %9.2f%%\n', ...
                modelLabels(mi), median(vals)*100, quantile(vals,0.25)*100, quantile(vals,0.75)*100);
        end
    end
end
