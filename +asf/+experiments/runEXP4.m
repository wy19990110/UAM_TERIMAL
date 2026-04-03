function runEXP4(mode, outDir)
    % runEXP4 全网 regime map 扫描（带断点续传）
    %   mode: 'mini' | 'medium' | 'full'
    %   outDir: 输出目录
    arguments
        mode (1,1) string = "mini"
        outDir (1,1) string = "results/exp4"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, sprintf("exp4_%s_log.txt", mode));
    cpFile = fullfile(outDir, sprintf("exp4_%s_checkpoint.mat", mode));
    resultFile = fullfile(outDir, sprintf("exp4_%s_results.mat", mode));

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % === 图族定义 ===
    switch mode
        case "mini"
            families = struct('name',{'G1s'}, 'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9])});
            seeds = 1;
            rhoVals = [0.5, 1.0];
            alphaAVals = [0, 0.25];
            kappaSVals = [1, 2];
            phiFVals = [0, 0.3];
        case "medium"
            families = struct('name',{'G1s','G2s','G3s'}, ...
                'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                        struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
                        struct('nT',3,'nW',3,'targetEdges',[6,9],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
            seeds = 1:3;
            rhoVals = [0.5, 0.8, 1.0, 1.2];
            alphaAVals = [0, 0.25, 0.5];
            kappaSVals = [1, 2, 3];
            phiFVals = [0, 0.2, 0.5];
        case "full"
            families = struct('name',{'G1','G2','G3'}, ...
                'spec',{struct('nT',8,'nW',6,'targetEdges',[18,22]), ...
                        struct('nT',10,'nW',8,'targetEdges',[26,32]), ...
                        struct('nT',6,'nW',6,'targetEdges',[18,25],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
            seeds = 1:5;
            rhoVals = [0.5, 0.8, 1.0, 1.2];
            alphaAVals = [0, 0.25, 0.5];
            kappaSVals = [1, 2, 3];
            phiFVals = [0, 0.2, 0.5];
    end

    % === 参数组合 ===
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

    % === 加载 checkpoint ===
    if exist(cpFile, 'file')
        cp = load(cpFile);
        results = cp.results;
        completed = cp.completed;
        logmsg(sprintf('加载 checkpoint: %d/%d 已完成', sum(completed), total));
    else
        results = struct('family',{},'seed',{},'rho',{},'alphaA',{},'kappaS',{},'phiF',{}, ...
            'jStar',{},'m0Regret',{},'m0Rel',{},'m1Regret',{},'m1Rel',{},...
            'm2Regret',{},'m2Rel',{},'m0TD',{},'m1TD',{},'m2TD',{}, ...
            'm0Suff3',{},'m1Suff3',{},'m2Suff3',{}, ...
            'time',{},'error',{});
        results(total).family = "";  % preallocate
        completed = false(total, 1);
        logmsg(sprintf('=== EXP-4 %s: %d 实例 ===', mode, total));
    end

    opts = struct('nPwl', 7, 'verbose', false);

    for idx = 1:total
        if completed(idx), continue; end

        c = combos{idx};
        fname = families(c.fi).name;
        spec = families(c.fi).spec;
        sd = seeds(c.si);
        rho = rhoVals(c.ri);
        aA = alphaAVals(c.ai);
        kS = kappaSVals(c.ki);
        pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f aA=%.2f kS=%d pF=%.1f', ...
            idx, total, fname, sd, rho, aA, kS, pF));

        t0 = tic;
        try
            % 构建实例
            params = struct('alphaA', aA, 'kappaS', kS, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 提取接口
            m0i = containers.Map();
            m1i = containers.Map();
            m2i = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2i;

            % Regret
            res = asf.solver.computeRegret(inst, ["M0";"M1";"M2"], ifaces, opts);
            elapsed = toc(t0);

            results(idx).family = fname;
            results(idx).seed = sd;
            results(idx).rho = rho;
            results(idx).alphaA = aA;
            results(idx).kappaS = kS;
            results(idx).phiF = pF;
            results(idx).jStar = res.star.jTruth;
            results(idx).m0Regret = res.M0.regret;
            results(idx).m0Rel = res.M0.relRegret;
            results(idx).m1Regret = res.M1.regret;
            results(idx).m1Rel = res.M1.relRegret;
            results(idx).m2Regret = res.M2.regret;
            results(idx).m2Rel = res.M2.relRegret;
            results(idx).m0TD = res.M0.tdBB;
            results(idx).m1TD = res.M1.tdBB;
            results(idx).m2TD = res.M2.tdBB;
            results(idx).m0Suff3 = abs(res.M0.relRegret) <= 0.03;
            results(idx).m1Suff3 = abs(res.M1.relRegret) <= 0.03;
            results(idx).m2Suff3 = abs(res.M2.relRegret) <= 0.03;
            results(idx).time = elapsed;
            results(idx).error = "";

            logmsg(sprintf('  J*=%.1f M0=%.1f%% M1=%.1f%% M2=%.1f%% (%.1fs)', ...
                res.star.jTruth, res.M0.relRegret*100, res.M1.relRegret*100, res.M2.relRegret*100, elapsed));

        catch ME
            elapsed = toc(t0);
            results(idx).family = fname;
            results(idx).seed = sd;
            results(idx).rho = rho;
            results(idx).alphaA = aA;
            results(idx).kappaS = kS;
            results(idx).phiF = pF;
            results(idx).error = ME.message;
            results(idx).time = elapsed;
            logmsg(sprintf('  ERROR: %s (%.1fs)', ME.message, elapsed));
        end

        completed(idx) = true;
        save(cpFile, 'results', 'completed');
    end

    % === 保存最终结果 ===
    save(resultFile, 'results');
    logmsg('=== 完成 ===');
    fclose(flog);
end
