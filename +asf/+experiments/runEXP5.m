function runEXP5(outDir)
    % runEXP5  现实代理套件 (3 类 proxy) (二轮修改)
    %   修改:
    %     - F-sensitive 用 M2N 代替 M2
    %     - A/S proxy: quantitative (主文定量结果)
    %     - F proxy: qualitative only (不用绝对 regret 写正文 headline)
    %     - 等 4C-main/M2N 跑完再决定是否升回定量主图
    arguments
        outDir (1,1) string = "results/exp5"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp5_log.txt");
    resultFile = fullfile(outDir, "exp5_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);
    logmsg('=== EXP-5 三类现实代理 (二轮) ===');

    seeds = 1:5;
    rhoVals = [0.6, 1.0, 1.4];
    proxyTypes = ["A-sensitive", "S-sensitive", "F-sensitive"];

    % 图规格
    specDefault = struct('nT', 4, 'nW', 3, 'targetEdges', [7, 9]);
    specAirport = struct('nT', 4, 'nW', 3, 'targetEdges', [7, 9], ...
        'hasAirport', true, 'airportCenter', [0.7, 0.5], 'airportRadius', 0.2);

    opts = struct('nPwl', 15, 'verbose', false);
    results = {};
    total = numel(proxyTypes) * numel(seeds) * numel(rhoVals);
    done = 0;

    for pti = 1:numel(proxyTypes)
        ptype = proxyTypes(pti);
        for si = 1:numel(seeds)
            for ri = 1:numel(rhoVals)
                sd = seeds(si);
                rho = rhoVals(ri);
                done = done + 1;
                logmsg(sprintf('[%d/%d] %s seed=%d rho=%.1f', done, total, ptype, sd, rho));

                t0 = tic;
                try
                    % 按 proxy 类型构建实例
                    switch char(ptype)
                        case 'A-sensitive'
                            params = struct('alphaA', 0.5, 'kappaS', 1, 'phiF', 0, 'rho', rho, ...
                                'portMisalignDeg', 40);
                            inst = asf.graphgen.buildSynthetic(specDefault, sd, params);
                        case 'S-sensitive'
                            params = struct('alphaA', 0, 'kappaS', 2.5, 'phiF', 0, 'rho', rho, ...
                                'couplingM', 0.4, 'psiSat', 3.0, 'concentration', 0.6);
                            inst = asf.graphgen.buildSynthetic(specDefault, sd, params);
                        case 'F-sensitive'
                            params = struct('alphaA', 0.25, 'kappaS', 1.5, 'phiF', 0.5, 'rho', rho);
                            inst = asf.graphgen.buildSynthetic(specAirport, sd, params);
                    end

                    % 提取接口: F-sensitive 用 M2N (二轮修改)
                    m0i = containers.Map(); m1i = containers.Map(); m2i = containers.Map();
                    tkeys = inst.terminals.keys;
                    for ti = 1:numel(tkeys)
                        t = inst.terminals(tkeys{ti});
                        m0i(tkeys{ti}) = asf.interface.extractM0(t);
                        m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                        if ptype == "F-sensitive"
                            m2i(tkeys{ti}) = asf.interface.extractM2N(t, inst);
                        else
                            m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
                        end
                    end
                    ifaces = containers.Map();
                    ifaces('M0') = m0i; ifaces('M1') = m1i; ifaces('M2') = m2i;

                    res = asf.solver.computeRegret(inst, ["M0";"M1";"M2"], ifaces, opts);
                    elapsed = toc(t0);

                    r = struct();
                    r.proxyType = char(ptype);
                    r.seed = sd; r.rho = rho;
                    r.jStar = res.star.jTruth;
                    r.starSource = res.star.source;

                    % 二轮修改: quantitative flag
                    r.quantitative = (ptype ~= "F-sensitive");

                    for lv = ["M0","M1","M2"]
                        lvr = res.(char(lv));
                        r.(char(lv)).jTruth = lvr.jTruth;
                        r.(char(lv)).relRegret = lvr.relRegret;
                        r.(char(lv)).breakdown = lvr.breakdown;
                        r.(char(lv)).tdBB = lvr.tdBB;
                        r.(char(lv)).recoveryRate = lvr.recoveryRate;
                        r.(char(lv)).activeEdges = lvr.design.activeEdges;
                    end

                    if isfield(res, 'U01'), r.U01 = res.relU01; else, r.U01 = NaN; end
                    if isfield(res, 'U12'), r.U12 = res.relU12; else, r.U12 = NaN; end
                    r.recommendation = res.recommendation;
                    r.E_A = inst.excitation.E_A; r.E_S = inst.excitation.E_S; r.E_F = inst.excitation.E_F;
                    r.time = elapsed; r.error = "";
                    results{end+1} = r; %#ok<AGROW>

                    logmsg(sprintf('  J*=%.1f M0=%.1f%% M1=%.1f%% M2=%.1f%% quant=%d (%.1fs)', ...
                        res.star.jTruth, res.M0.relRegret*100, res.M1.relRegret*100, ...
                        res.M2.relRegret*100, r.quantitative, elapsed));
                catch ME
                    elapsed = toc(t0);
                    r = struct(); r.proxyType = char(ptype); r.seed = sd; r.rho = rho;
                    r.error = ME.message; r.time = elapsed;
                    results{end+1} = r; %#ok<AGROW>
                    logmsg(sprintf('  ERROR: %s', ME.message));
                end
            end
        end
    end

    save(resultFile, 'results');
    logmsg('=== EXP-5 完成 ===');
    fclose(flog);

    % 控制台汇总 (二轮: 分开 quantitative 和 qualitative)
    fprintf('\n=== EXP-5 三类现实代理 (二轮) ===\n');

    fprintf('\n--- Quantitative (A/S proxy, 主文) ---\n');
    fprintf('%-14s  %4s  %4s  %6s  %6s  %6s  %6s  %s\n', ...
        'Type', 'seed', 'rho', 'M0%', 'M1%', 'M2%', 'U01%', 'Rec');
    for ri = 1:numel(results)
        r = results{ri};
        if ~isempty(r.error) && r.error ~= "", continue; end
        if ~r.quantitative, continue; end
        fprintf('%-14s  %4d  %4.1f  %5.1f%%  %5.1f%%  %5.1f%%  %5.1f%%  %s\n', ...
            r.proxyType, r.seed, r.rho, ...
            r.M0.relRegret*100, r.M1.relRegret*100, r.M2.relRegret*100, ...
            r.U01*100, r.recommendation);
    end

    fprintf('\n--- Qualitative (F proxy, 仅 overlay/case) ---\n');
    fprintf('%-14s  %4s  %4s  %6s  %6s  %6s  %s\n', ...
        'Type', 'seed', 'rho', 'M0%', 'M1%', 'M2N%', 'note');
    for ri = 1:numel(results)
        r = results{ri};
        if ~isempty(r.error) && r.error ~= "", continue; end
        if r.quantitative, continue; end
        fprintf('%-14s  %4d  %4.1f  %5.1f%%  %5.1f%%  %5.1f%%  qualitative-only\n', ...
            r.proxyType, r.seed, r.rho, ...
            r.M0.relRegret*100, r.M1.relRegret*100, r.M2.relRegret*100);
    end
end
