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

    % 1. 求解 M* (truth benchmark)
    if opts.verbose, fprintf('求解 M*...\n'); end
    starDesign = asf.solver.solveMILP(inst, "Mstar", containers.Map(), opts);
    [jStar, starBD] = asf.solver.truthEvaluate(starDesign, inst);

    results.star.design = starDesign;
    results.star.jTruth = jStar;
    results.star.breakdown = starBD;

    if opts.verbose
        fprintf('M*: J*=%.4f, edges=%s\n', jStar, strjoin(starDesign.activeEdges, ','));
    end

    % 2. 各抽象层级
    m0Regret = NaN;
    for li = 1:numel(levels)
        lv = levels(li);
        if opts.verbose, fprintf('求解 %s...\n', lv); end

        % 选择对应的接口
        lvIfaces = containers.Map();
        if ifaces.isKey(char(lv))
            lvIfaces = ifaces(char(lv));
        end

        design = asf.solver.solveMILP(inst, lv, lvIfaces, opts);
        [jTruth, bd] = asf.solver.truthEvaluate(design, inst);

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
