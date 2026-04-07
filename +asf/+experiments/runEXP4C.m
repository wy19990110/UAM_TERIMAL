function runEXP4C(outDir)
    % runEXP4C  F 通道隔离: 主文版 (M1 vs M2N)
    %   二轮修改: 主文模型改为 M2N (hard blocks + nominal local penalties, 无双线性项)
    %   - 固定 alphaA=0.25, kappaS=2
    %   - 扫描 phiF x rho
    %   - footprint penalty 已在 extractM2N 中重新定标为平均边 travel cost 的倍数
    %   - 比较 M1 vs M2N
    arguments
        outDir (1,1) string = "results/exp4c"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4c_log.txt");
    cpFile = fullfile(outDir, "exp4c_checkpoint.mat");
    resultFile = fullfile(outDir, "exp4c_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    families = struct('name',{'G1s','G2s','G3s'}, ...
        'spec',{struct('nT',4,'nW',3,'targetEdges',[7,9]), ...
                struct('nT',5,'nW',4,'targetEdges',[10,13]), ...
                struct('nT',3,'nW',3,'targetEdges',[6,9],'hasAirport',true,'airportCenter',[0.8,0.5],'airportRadius',0.15)});
    seeds = 1:5;

    % 固定参数
    alphaA = 0.25;
    kappaS = 2;

    % 扫描轴 (二轮修改)
    phiFVals = [0, 0.1, 0.2, 0.3, 0.4, 0.5];
    rhoVals = [0.5, 0.8, 1.0, 1.2];

    combos = {};
    for fi = 1:numel(families)
        for si = 1:numel(seeds)
            for ri = 1:numel(rhoVals)
                for pi = 1:numel(phiFVals)
                    combos{end+1} = struct('fi',fi,'si',si,'ri',ri,'pi',pi); %#ok<AGROW>
                end
            end
        end
    end
    total = numel(combos);
    logmsg(sprintf('=== EXP-4C-main M1 vs M2N: %d 实例 ===', total));

    if exist(cpFile, 'file')
        cp = load(cpFile);
        if numel(cp.completed) == total
            results = cp.results;
            completed = cp.completed;
            logmsg(sprintf('加载 checkpoint: %d/%d', sum(completed), total));
        else
            logmsg(sprintf('旧 checkpoint 大小(%d)与当前网格(%d)不兼容, 重新开始', ...
                numel(cp.completed), total));
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
        sd = seeds(c.si); rho = rhoVals(c.ri); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f pF=%.1f', idx, total, fname, sd, rho, pF));
        t0 = tic;
        try
            params = struct('alphaA', alphaA, 'kappaS', kappaS, 'phiF', pF, 'rho', rho);
            inst = asf.graphgen.buildSynthetic(spec, sd, params);

            % 提取 M1 和 M2N 接口 (不再提取 M2/M2L)
            m1i = containers.Map(); m2ni = containers.Map();
            tkeys = inst.terminals.keys;
            for ti = 1:numel(tkeys)
                t = inst.terminals(tkeys{ti});
                m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
            end
            ifaces = containers.Map();
            ifaces('M1') = m1i; ifaces('M2') = m2ni;  % solver 用 "M2" 分支处理 M2N

            res = asf.solver.computeRegret(inst, ["M1";"M2"], ifaces, opts);
            elapsed = toc(t0);

            r = struct();
            r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = alphaA; r.kappaS = kappaS; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.m1Rel = res.M1.relRegret; r.m2nRel = res.M2.relRegret;
            r.m1JTruth = res.M1.jTruth; r.m2nJTruth = res.M2.jTruth;
            if isfield(res, 'U12')
                r.U12 = res.U12; r.relU12 = res.relU12;
            else
                r.U12 = NaN; r.relU12 = NaN;
            end
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            r.time = elapsed; r.error = "";

            results{idx} = r;
            logmsg(sprintf('  U12=%.4f relU12=%.1f%% E_F=%.3f (%.1fs)', ...
                r.U12, r.relU12*100, r.E_F, elapsed));
        catch ME
            elapsed = toc(t0);
            r = struct(); r.family = fname; r.seed = sd; r.rho = rho;
            r.alphaA = alphaA; r.kappaS = kappaS; r.phiF = pF;
            r.error = ME.message; r.time = elapsed;
            results{idx} = r;
            logmsg(sprintf('  ERROR: %s', ME.message));
        end
        completed(idx) = true;
        save(cpFile, 'results', 'completed', 'combos');
    end

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-4C-main 完成 ===');
    fclose(flog);

    % 控制台汇总
    fprintf('\n=== EXP-4C-main M1 vs M2N 汇总 ===\n');
    for pi = 1:numel(phiFVals)
        pF = phiFVals(pi);
        u12Vals = [];
        for idx = 1:total
            r = results{idx};
            if isempty(r) || (~isempty(r.error) && r.error ~= ""), continue; end
            if abs(r.phiF - pF) > 1e-6, continue; end
            u12Vals(end+1) = r.relU12; %#ok<AGROW>
        end
        if ~isempty(u12Vals)
            fprintf('  phiF=%.1f: median_relU12=%.2f%% mean=%.2f%% n=%d\n', ...
                pF, median(u12Vals)*100, mean(u12Vals)*100, numel(u12Vals));
        end
    end
end
