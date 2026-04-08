function results = computeRegret(inst, levels, ifaces, opts)
    % computeRegret 编排任意抽象层级 → truth evaluate → regret
    %
    %   levels: string array, 如 ["M0","M1","M2"] 或含 "B0","B1","JO"
    %   ifaces: containers.Map level -> (containers.Map tid -> iface struct)
    %   opts: struct with .nPwl, .verbose, .truthLevel (默认 "Mstar")
    arguments
        inst asf.core.ProblemInstance
        levels (:,1) string = ["M0";"M1";"M2"]
        ifaces containers.Map = containers.Map()
        opts struct = struct('nPwl', 7, 'verbose', false)
    end

    % Truth benchmark level（默认 Mstar，EXP-7 可传 "JO"）
    if isfield(opts, 'truthLevel')
        truthLevel = opts.truthLevel;
    else
        truthLevel = "Mstar";
    end

    % 1. 求解 truth benchmark + 各抽象层级，收集所有设计
    if opts.verbose, fprintf('求解 %s (truth benchmark)...\n', truthLevel); end
    tStar0 = tic;
    starDesign = asf.solver.solveMILP(inst, truthLevel, containers.Map(), opts);
    starTime = toc(tStar0);
    [jStarRaw, starBD] = asf.solver.truthEvaluate(starDesign, inst);

    % 收集所有设计及其 truth 值，取全局最优作为 J*
    allDesigns = {starDesign};
    allJTruth = jStarRaw;
    allBD = {starBD};
    allLabels = {char(truthLevel)};
    allTimes = starTime;

    % 2. 各抽象层级
    for li = 1:numel(levels)
        lv = levels(li);
        if opts.verbose, fprintf('求解 %s...\n', lv); end
        lvIfaces = containers.Map();
        if ifaces.isKey(char(lv))
            lvIfaces = ifaces(char(lv));
        end
        tLv0 = tic;
        design = asf.solver.solveMILP(inst, lv, lvIfaces, opts);
        lvTime = toc(tLv0);
        [jTruth, bd] = asf.solver.truthEvaluate(design, inst);
        allDesigns{end+1} = design; %#ok<AGROW>
        allJTruth(end+1) = jTruth; %#ok<AGROW>
        allBD{end+1} = bd; %#ok<AGROW>
        allLabels{end+1} = char(lv); %#ok<AGROW>
        allTimes(end+1) = lvTime; %#ok<AGROW>
    end

    % 取 truth 口径下的全局最优作为 J*（跨所有模型选最好的设计）
    [jStar, bestIdx] = min(allJTruth);
    starDesign = allDesigns{bestIdx};
    starBD = allBD{bestIdx};

    results.star.design = starDesign;
    results.star.jTruth = jStar;
    results.star.breakdown = starBD;
    results.star.source = allLabels{bestIdx};
    results.star.solveTime = allTimes(1);  % truth benchmark solve time

    if opts.verbose
        fprintf('J* = %.4f (来自 %s), edges=%s\n', jStar, allLabels{bestIdx}, strjoin(starDesign.activeEdges, ','));
    end

    % 3. 计算 regret（相对全局最优 J*）
    m0Regret = NaN;
    b0Regret = NaN;
    for li = 1:numel(levels)
        lv = levels(li);
        design = allDesigns{1 + li};  % +1 因为 allDesigns{1} 是 truth benchmark
        jTruth = allJTruth(1 + li);
        bd = allBD{1 + li};

        delta = jTruth - jStar;
        relDelta = delta / max(abs(jStar), 1e-10);

        r.design = design;
        r.jTruth = jTruth;
        r.breakdown = bd;
        r.regret = delta;
        r.relRegret = relDelta;
        r.tdBB = design.topologyDistBB(starDesign);
        r.tdConn = design.topologyDistConn(starDesign);
        r.solveTime = allTimes(1 + li);

        if lv == "M0"
            m0Regret = delta;
        end
        if lv == "B0"
            b0Regret = delta;
        end

        % Recovery rate (相对 M0 或 B0 中较大的)
        refRegret = m0Regret;
        if isnan(refRegret), refRegret = b0Regret; end
        if ~isnan(refRegret) && refRegret > 1e-10
            r.recoveryRate = 1 - delta / refRegret;
        else
            r.recoveryRate = NaN;
        end

        results.(char(lv)) = r;

        if opts.verbose
            fprintf('  %s: J_truth=%.4f, Δ=%.4f (%.1f%%), TD=%.2f (%.1fs)\n', ...
                lv, jTruth, delta, relDelta*100, r.tdBB, r.solveTime);
        end
    end

    % 重算 recovery rates（M0 可能不在第一个位置）
    refRegret = NaN;
    if ~isnan(m0Regret), refRegret = m0Regret;
    elseif ~isnan(b0Regret), refRegret = b0Regret; end
    if ~isnan(refRegret) && refRegret > 1e-10
        for li = 1:numel(levels)
            lv = char(levels(li));
            results.(lv).recoveryRate = 1 - results.(lv).regret / refRegret;
        end
    end

    % === Pairwise uplift 指标 ===
    % Uplift 指标: 分母统一用 jStar (全局最优 truth cost), 避免异常大分母掩盖问题
    if isfield(results, 'M0') && isfield(results, 'M1')
        results.U01 = results.M0.jTruth - results.M1.jTruth;
        results.relU01 = results.U01 / max(abs(jStar), 1e-10);
    end
    if isfield(results, 'M1') && isfield(results, 'M2')
        results.U12 = results.M1.jTruth - results.M2.jTruth;
        results.relU12 = results.U12 / max(abs(jStar), 1e-10);
    end
    if isfield(results, 'M0') && isfield(results, 'M2')
        results.U02 = results.M0.jTruth - results.M2.jTruth;
        results.relU02 = results.U02 / max(abs(jStar), 1e-10);
    end
    % Model recommendation
    results.recommendation = "M0";
    if isfield(results, 'relU01') && isfield(results, 'relU12')
        if results.relU12 >= 0.03
            results.recommendation = "M2";
        elseif results.relU01 >= 0.03
            results.recommendation = "M1";
        end
    end
end
