function runEXP4B_S(outDir)
    % runEXP4B_S  S 通道隔离 redesign 实验 (二轮修改: 完全重做)
    %   新的 4 维扫描轴:
    %     kappa_loc ∈ {1,2,4}       — 本地端口曲率差
    %     r_shared  ∈ {0,0.25,0.5,0.75} — 共享资源占比
    %     eta       ∈ {0.4,0.7,1.0,1.3} — 饱和激活强度 (q_total/mu_bar)
    %     c         ∈ {0,0.3,0.6}       — OD 集中度
    %
    %   固定 A=0 (alphaA=0), F=0 (phiF=0)
    %   图族: G1s/G2s, 5 seeds, nPwl=15
    %   核心指标: median U01 是否随 eta/r_shared 单调上升
    %   服务真值: C_S(λ) = Σ_h(a_h λ_h + b_h λ_h²) + Σ_{S} m λ_h λ_{h'} + ψ[Σλ-μ̄]²₊
    %   m 只作用于共享资源对 (由 r_shared 控制)
    arguments
        outDir (1,1) string = "results/exp4b_s"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4b_s_log.txt");
    cpFile = fullfile(outDir, "exp4b_s_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4b_s_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 图族
    families = struct('name',{'G1s','G2s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13])});
    seeds = 1:5;

    % 新的 4 维扫描轴 (A=0, F=0 固定)
    kappaLocVals = [1, 2, 4];
    rSharedVals = [0, 0.25, 0.5, 0.75];
    etaVals = [0.4, 0.7, 1.0, 1.3];
    concVals = [0, 0.3, 0.6];

    combos = {};
    for fi = 1:numel(families)
        for si = 1:numel(seeds)
            for ki = 1:numel(kappaLocVals)
                for ri = 1:numel(rSharedVals)
                    for ei = 1:numel(etaVals)
                        for ci = 1:numel(concVals)
                            combos{end+1} = struct('fi',fi,'si',si,'ki',ki,'ri',ri,'ei',ei,'ci',ci); %#ok<AGROW>
                        end
                    end
                end
            end
        end
    end
    total = numel(combos);
    logmsg(sprintf('=== EXP-4B-S S通道隔离 (二轮): %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        if numel(cp.completed) == total
            results = cp.results;
            completed = cp.completed;
            logmsg(sprintf('加载 checkpoint: %d/%d 已完成', sum(completed), total));
        else
            logmsg(sprintf('旧 checkpoint 不兼容, 重新开始'));
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
        sd = seeds(c.si);
        kLoc = kappaLocVals(c.ki);
        rSh = rSharedVals(c.ri);
        eta = etaVals(c.ei);
        conc = concVals(c.ci);

        logmsg(sprintf('[%d/%d] %s s=%d kL=%d rSh=%.2f eta=%.1f c=%.1f', ...
            idx, total, fname, sd, kLoc, rSh, eta, conc));
        t0 = tic;
        try
            % A=0, F=0, 新参数
            params = struct('alphaA', 0, 'kappaS', kLoc, 'phiF', 0, ...
                'rho', 1.0, 'r_shared', rSh, 'eta', eta, ...
                'concentration', conc);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            m0i = containers.Map(); m1i = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m0i(tkeys{ti}) = asf.interface.extractM0(t);
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M0') = m0i; ifaces('M1') = m1i;

            res = asf.solver.computeRegret(inst, ["M0";"M1"], ifaces, opts);
            elapsed = toc(t0);

            E_S = inst.excitation.E_S;

            r = struct();
            r.family = fname; r.seed = sd;
            r.kappaLoc = kLoc; r.rShared = rSh; r.eta = eta; r.concentration = conc;
            r.E_S = E_S;
            r.jStar = res.star.jTruth;
            r.m0Regret = res.M0.regret; r.m0Rel = res.M0.relRegret;
            r.m1Regret = res.M1.regret; r.m1Rel = res.M1.relRegret;
            r.m0TD = res.M0.tdBB; r.m1TD = res.M1.tdBB;
            if isfield(res, 'U01'), r.U01 = res.U01; r.relU01 = res.relU01;
            else, r.U01 = NaN; r.relU01 = NaN; end
            r.time = elapsed; r.error = "";
            results{idx} = r;
            logmsg(sprintf('  J*=%.1f U01=%.4f relU01=%.1f%% E_S=%.3f (%.1fs)', ...
                res.star.jTruth, r.U01, r.relU01*100, E_S, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd;
            r.kappaLoc = kLoc; r.rShared = rSh; r.eta = eta; r.concentration = conc;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    save(resultFile, 'results', 'combos');

    % === 汇总: median U01 by eta and r_shared ===
    logmsg('=== 汇总: median U01 ===');
    fprintf('\n=== EXP-4B-S median U01 by eta x r_shared ===\n');
    fprintf('%6s', '');
    for ri = 1:numel(rSharedVals)
        fprintf('  rSh=%.2f', rSharedVals(ri));
    end
    fprintf('\n');
    for ei = 1:numel(etaVals)
        fprintf('eta=%.1f', etaVals(ei));
        for ri = 1:numel(rSharedVals)
            vals = [];
            for idx = 1:total
                r = results{idx};
                if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
                if abs(r.eta - etaVals(ei)) < 1e-6 && abs(r.rShared - rSharedVals(ri)) < 1e-6
                    vals(end+1) = r.U01; %#ok<AGROW>
                end
            end
            if ~isempty(vals)
                fprintf('  %8.4f', median(vals));
            else
                fprintf('  %8s', 'N/A');
            end
        end
        fprintf('\n');
        logmsg(sprintf('eta=%.1f: median U01 = [%s]', etaVals(ei), ...
            strjoin(arrayfun(@(rs) sprintf('rSh=%.2f:%.4f', rs, ...
            safeMedian(results, total, etaVals(ei), rs)), rSharedVals, 'UniformOutput', false), ', ')));
    end

    logmsg('=== EXP-4B-S 完成 ===');
    fclose(flog);
    fprintf('EXP-4B-S 完成: %d 实例\n', total);
end


function m = safeMedian(results, total, eta, rSh)
    vals = [];
    for idx = 1:total
        r = results{idx};
        if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
        if abs(r.eta - eta) < 1e-6 && abs(r.rShared - rSh) < 1e-6
            vals(end+1) = r.U01; %#ok<AGROW>
        end
    end
    if isempty(vals), m = NaN; else, m = median(vals); end
end
