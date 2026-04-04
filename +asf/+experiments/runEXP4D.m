function runEXP4D(outDir)
    % runEXP4D 混合 regime 实验
    %   4 图族 × 4 seeds × ~30 组合 ≈ 480 实例
    %   输出: model recommendation map on (E_A, E_S, E_F) 空间
    arguments
        outDir (1,1) string = "results/exp4d"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4d_log.txt");
    cpFile = fullfile(outDir, "exp4d_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4d_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 4 图族
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
    logmsg(sprintf('=== EXP-4D 混合regime: %d 实例 ===', total));

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
            r.m0Rel = res.M0.relRegret; r.m1Rel = res.M1.relRegret; r.m2Rel = res.M2.relRegret;
            r.U01 = res.relU01; r.U12 = res.relU12; r.U02 = res.relU02;
            r.recommendation = res.recommendation;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            r.m0TD = res.M0.tdBB; r.m1TD = res.M1.tdBB; r.m2TD = res.M2.tdBB;
            r.time = elapsed; r.error = "";
            results{idx} = r;
            logmsg(sprintf('  Rec=%s U01=%.1f%% U12=%.1f%% (%.1fs)', ...
                res.recommendation, res.relU01*100, res.relU12*100, elapsed));
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

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-4D 完成 ===');
    fclose(flog);
    fprintf('EXP-4D 完成: %d 实例\n', total);
end
