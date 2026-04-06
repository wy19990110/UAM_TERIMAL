function runEXP4C(outDir)
    % runEXP4C F 通道隔离 + Solver Audit 实验
    %   按新的实验要求 §一.5:
    %   - A/S 固定(moderate)，扫 φF × ρ
    %   - 在 φF∈{0.1,0.2,0.3,0.4,0.5} 上加 solver audit:
    %     对每个实例跑 3 个精度等级 (nPwl=7,15,31)
    %   - 目标: 分离 "F 信息本身有价值" vs "负 U12 是 PwL 伪影"
    %   - 输出: U12 heatmap + convergence table
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
    seeds = 1:3;

    % A/S 固定为 moderate 值
    alphaA = 0.25;
    kappaS = 2;
    rhoVals = [0.5, 0.8, 1.0, 1.2, 1.5];
    phiFVals = [0, 0.1, 0.2, 0.3, 0.5, 0.7];

    % Audit 精度等级
    auditNPwl = [7, 15, 31];
    % Audit 只在这些 φF 值上做
    auditPhiF = [0.1, 0.2, 0.3, 0.4, 0.5];

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
    logmsg(sprintf('=== EXP-4C F隔离+Audit: %d 实例 ===', total));

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
        sd = seeds(c.si); rho = rhoVals(c.ri); pF = phiFVals(c.pi);

        logmsg(sprintf('[%d/%d] %s s=%d rho=%.1f pF=%.1f', idx, total, fname, sd, rho, pF));
        t0 = tic;
        try
            params = struct('alphaA', alphaA, 'kappaS', kappaS, 'phiF', pF, 'rho', rho);
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
            r.alphaA = alphaA; r.kappaS = kappaS; r.phiF = pF;
            r.jStar = res.star.jTruth;
            r.m0Rel = res.M0.relRegret; r.m1Rel = res.M1.relRegret; r.m2Rel = res.M2.relRegret;
            r.U01 = res.relU01; r.U12 = res.relU12; r.U02 = res.relU02;
            r.recommendation = res.recommendation;
            r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
            r.time = elapsed; r.error = "";

            % === Solver Audit: 多精度 nPwl ===
            needsAudit = any(abs(auditPhiF - pF) < 1e-6);
            if needsAudit
                r.audit = struct();
                for ai = 1:numel(auditNPwl)
                    nPwl = auditNPwl(ai);
                    auditOpts = struct('nPwl', nPwl, 'verbose', false);
                    tAudit = tic;
                    auditRes = asf.solver.computeRegret(inst, ["M1";"M2"], ifaces, auditOpts);
                    auditTime = toc(tAudit);

                    tag = sprintf('nPwl%d', nPwl);
                    r.audit.(tag).m1Rel = auditRes.M1.relRegret;
                    r.audit.(tag).m2Rel = auditRes.M2.relRegret;
                    if isfield(auditRes, 'U12')
                        r.audit.(tag).U12 = auditRes.U12;
                        r.audit.(tag).relU12 = auditRes.relU12;
                        r.audit.(tag).negU12 = auditRes.U12 < 0;
                    end
                    r.audit.(tag).time = auditTime;
                end
                logmsg(sprintf('  Audit: nPwl=[7→U12=%.4f, 15→%.4f, 31→%.4f]', ...
                    r.audit.nPwl7.relU12, r.audit.nPwl15.relU12, r.audit.nPwl31.relU12));
            end

            results{idx} = r;
            logmsg(sprintf('  U12=%.1f%% E_F=%.3f (%.1fs)', res.relU12*100, inst.excitation.E_F, elapsed));
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

    % === Audit 汇总 ===
    logmsg('=== Solver Audit 汇总 ===');
    for ai = 1:numel(auditPhiF)
        pF = auditPhiF(ai);
        u12Vals = struct('nPwl7',[],'nPwl15',[],'nPwl31',[]);
        for idx = 1:total
            r = results{idx};
            if isempty(r) || ~isempty(r.error), continue; end
            if abs(r.phiF - pF) > 1e-6, continue; end
            if ~isfield(r, 'audit'), continue; end
            for ni = 1:numel(auditNPwl)
                tag = sprintf('nPwl%d', auditNPwl(ni));
                if isfield(r.audit, tag)
                    u12Vals.(tag)(end+1) = r.audit.(tag).relU12;
                end
            end
        end
        logmsg(sprintf('  phiF=%.1f: nPwl7=%.2f%% nPwl15=%.2f%% nPwl31=%.2f%%', ...
            pF, safeMean(u12Vals.nPwl7)*100, safeMean(u12Vals.nPwl15)*100, safeMean(u12Vals.nPwl31)*100));
    end

    save(resultFile, 'results', 'combos');
    logmsg('=== EXP-4C 完成 ===');
    fclose(flog);
    fprintf('EXP-4C 完成: %d 实例\n', total);
end

function m = safeMean(v)
    if isempty(v), m = NaN; else, m = mean(v); end
end
