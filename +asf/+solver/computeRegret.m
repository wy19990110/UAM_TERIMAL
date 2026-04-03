function results = computeRegret(inst, levels, ifaces, opts)
    % computeRegret 编排 M0/M1/M2/M* → truth evaluate → regret
    %
    %   levels: string array, 如 ["M0","M1","M2"]
    %   ifaces: containers.Map level -> (containers.Map tid -> iface struct)
    %   opts: struct with .nPwl, .verbose
    arguments
        inst asf.core.ProblemInstance
        levels (:,1) string = ["M0";"M1";"M2"]
        ifaces containers.Map = containers.Map()
        opts struct = struct('nPwl', 7, 'verbose', false)
    end

    % 1. 求解 M* + 各抽象层级，收集所有设计
    if opts.verbose, fprintf('求解 M*...\n'); end
    starDesign = asf.solver.solveMILP(inst, "Mstar", containers.Map(), opts);
    [jStarRaw, starBD] = asf.solver.truthEvaluate(starDesign, inst);

    % 收集所有设计及其 truth 值，取全局最优作为 J*
    allDesigns = {starDesign};
    allJTruth = jStarRaw;
    allBD = {starBD};
    allLabels = {"Mstar"};

    % 2. 各抽象层级
    for li = 1:numel(levels)
        lv = levels(li);
        if opts.verbose, fprintf('求解 %s...\n', lv); end
        lvIfaces = containers.Map();
        if ifaces.isKey(char(lv))
            lvIfaces = ifaces(char(lv));
        end
        design = asf.solver.solveMILP(inst, lv, lvIfaces, opts);
        [jTruth, bd] = asf.solver.truthEvaluate(design, inst);
        allDesigns{end+1} = design; %#ok<AGROW>
        allJTruth(end+1) = jTruth; %#ok<AGROW>
        allBD{end+1} = bd; %#ok<AGROW>
        allLabels{end+1} = char(lv); %#ok<AGROW>
    end

    % 取 truth 口径下的全局最优作为 J*（跨所有模型选最好的设计）
    [jStar, bestIdx] = min(allJTruth);
    starDesign = allDesigns{bestIdx};
    starBD = allBD{bestIdx};

    results.star.design = starDesign;
    results.star.jTruth = jStar;
    results.star.breakdown = starBD;
    results.star.source = allLabels{bestIdx};

    if opts.verbose
        fprintf('J* = %.4f (来自 %s), edges=%s\n', jStar, allLabels{bestIdx}, strjoin(starDesign.activeEdges, ','));
    end

    % 3. 计算 regret（相对全局最优 J*）
    m0Regret = NaN;
    for li = 1:numel(levels)
        lv = levels(li);
        design = allDesigns{1 + li};  % +1 因为 allDesigns{1} 是 Mstar
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

        if lv == "M0"
            m0Regret = delta;
        end

        % Recovery rate
        if ~isnan(m0Regret) && m0Regret > 1e-10
            r.recoveryRate = 1 - delta / m0Regret;
        else
            r.recoveryRate = NaN;
        end

        results.(char(lv)) = r;

        if opts.verbose
            fprintf('  %s: J_truth=%.4f, Δ=%.4f (%.1f%%), TD=%.2f\n', ...
                lv, jTruth, delta, relDelta*100, r.tdBB);
        end
    end

    % 重算 recovery rates
    if ~isnan(m0Regret) && m0Regret > 1e-10
        for li = 1:numel(levels)
            lv = char(levels(li));
            results.(lv).recoveryRate = 1 - results.(lv).regret / m0Regret;
        end
    end
end
