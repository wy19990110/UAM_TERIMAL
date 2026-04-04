function runEXP5(outDir)
    % runEXP5 现实代理实验
    %   固定 airport-adjacent 图: 1 airport zone + 2 procedure terminals + 3 vertiports
    %   6 情景 × 4 模型, 输出: 设计对比、成本分解、regret、边归因
    arguments
        outDir (1,1) string = "results/exp5"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp5_log.txt");
    resultFile = fullfile(outDir, "exp5_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);
    logmsg('=== EXP-5 现实代理 ===');

    % 6 情景: {low, medium, high} demand × {relaxed, constrained} context
    scenarios = struct('name', {}, 'rho', {}, 'alphaA', {}, 'kappaS', {}, 'phiF', {});
    scenarios(1) = struct('name','low_relaxed',     'rho',0.5, 'alphaA',0.1, 'kappaS',1.5, 'phiF',0.1);
    scenarios(2) = struct('name','low_constrained', 'rho',0.5, 'alphaA',0.5, 'kappaS',3,   'phiF',0.5);
    scenarios(3) = struct('name','med_relaxed',     'rho',1.0, 'alphaA',0.1, 'kappaS',1.5, 'phiF',0.1);
    scenarios(4) = struct('name','med_constrained', 'rho',1.0, 'alphaA',0.5, 'kappaS',3,   'phiF',0.5);
    scenarios(5) = struct('name','high_relaxed',    'rho',1.5, 'alphaA',0.1, 'kappaS',1.5, 'phiF',0.1);
    scenarios(6) = struct('name','high_constrained','rho',1.5, 'alphaA',0.5, 'kappaS',3,   'phiF',0.5);

    % 固定图规格：airport-adjacent
    spec = struct('nT', 6, 'nW', 4, 'targetEdges', [12, 16], ...
        'hasAirport', true, 'airportCenter', [0.7, 0.5], 'airportRadius', 0.2);
    seed = 2026;  % 固定 seed

    opts = struct('nPwl', 15, 'verbose', false);
    results = cell(numel(scenarios), 1);

    for si = 1:numel(scenarios)
        sc = scenarios(si);
        logmsg(sprintf('[%d/6] Scenario: %s (rho=%.1f aA=%.1f kS=%.1f pF=%.1f)', ...
            si, sc.name, sc.rho, sc.alphaA, sc.kappaS, sc.phiF));

        t0 = tic;
        try
            params = struct('alphaA', sc.alphaA, 'kappaS', sc.kappaS, 'phiF', sc.phiF, 'rho', sc.rho);
            inst = asf.graphgen.buildSynthetic(spec, seed, params);

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
            r.scenario = sc.name;
            r.rho = sc.rho; r.alphaA = sc.alphaA; r.kappaS = sc.kappaS; r.phiF = sc.phiF;
            r.jStar = res.star.jTruth;
            r.starSource = res.star.source;
            r.starEdges = res.star.design.activeEdges;
            r.starBreakdown = res.star.breakdown;

            for lv = ["M0","M1","M2"]
                lvr = res.(char(lv));
                r.(char(lv)).jTruth = lvr.jTruth;
                r.(char(lv)).relRegret = lvr.relRegret;
                r.(char(lv)).breakdown = lvr.breakdown;
                r.(char(lv)).activeEdges = lvr.design.activeEdges;
                r.(char(lv)).activeConns = lvr.design.activeConns;
                r.(char(lv)).tdBB = lvr.tdBB;
            end

            r.U01 = res.relU01; r.U12 = res.relU12; r.U02 = res.relU02;
            r.recommendation = res.recommendation;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            r.nEdges = inst.edges.Count; r.nConns = inst.connectors.Count;
            r.nCommodities = size(inst.getCommodities(), 1);
            r.time = elapsed; r.error = "";
            results{si} = r;

            logmsg(sprintf('  J*=%.1f M0=%.1f%% M1=%.1f%% M2=%.1f%% Rec=%s (%.1fs)', ...
                res.star.jTruth, res.M0.relRegret*100, res.M1.relRegret*100, ...
                res.M2.relRegret*100, res.recommendation, elapsed));

        catch ME
            elapsed = toc(t0);
            r = struct(); r.scenario = sc.name; r.error = ME.message; r.time = elapsed;
            results{si} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
    end

    save(resultFile, 'results', 'scenarios');
    logmsg('=== EXP-5 完成 ===');
    fclose(flog);

    % 控制台汇总
    fprintf('\n=== EXP-5 现实代理 汇总 ===\n');
    fprintf('%-20s  %6s  %6s  %6s  %6s  %6s  %s\n', ...
        'Scenario', 'J*', 'M0%', 'M1%', 'M2%', 'U01%', 'Rec');
    for si = 1:numel(results)
        r = results{si};
        if ~isempty(r.error) && ~isempty(r.error), continue; end
        fprintf('%-20s  %6.1f  %5.1f%%  %5.1f%%  %5.1f%%  %5.1f%%  %s\n', ...
            r.scenario, r.jStar, r.M0.relRegret*100, r.M1.relRegret*100, ...
            r.M2.relRegret*100, r.U01*100, r.recommendation);
    end
end
