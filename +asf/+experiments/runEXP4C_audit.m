function runEXP4C_audit(outDir)
    % runEXP4C_audit  Solver audit: M2L-approx vs M2L-exact vs JO-exact
    %   在极小图族上枚举所有二进制拓扑, 固定拓扑后解连续 QP
    %   目标: 分离 "F 信息价值" 和 "McCormick 松弛误差"
    %
    %   G1s 有 7-9 条边 → 2^7 ~ 2^9 = 128 ~ 512 种拓扑, 可穷举
    arguments
        outDir (1,1) string = "results/exp4c_audit"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp4c_audit_log.txt");
    resultFile = fullfile(outDir, "exp4c_audit_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 只用最小图族
    spec = struct('nT',4,'nW',3,'targetEdges',[7,9]);
    seeds = 1:3;
    alphaA = 0.25;
    kappaS = 2;
    rho = 1.0;
    phiFVals = [0.1, 0.2, 0.3];

    opts = struct('nPwl', 15, 'verbose', false);
    results = {};
    total = numel(seeds) * numel(phiFVals);
    done = 0;

    logmsg(sprintf('=== EXP-4C Audit: %d 实例 ===', total));

    for si = 1:numel(seeds)
        for pi = 1:numel(phiFVals)
            sd = seeds(si);
            pF = phiFVals(pi);
            done = done + 1;
            logmsg(sprintf('[%d/%d] G1s s=%d pF=%.1f', done, total, sd, pF));

            t0 = tic;
            try
                params = struct('alphaA', alphaA, 'kappaS', kappaS, 'phiF', pF, 'rho', rho);
                inst = asf.graphgen.buildSynthetic(spec, sd, params);

                % 提取接口
                m1i = containers.Map(); m2i = containers.Map(); m2ni = containers.Map();
                tkeys = inst.terminals.keys;
                for ti = 1:numel(tkeys)
                    t = inst.terminals(tkeys{ti});
                    m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                    m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
                    m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
                end

                % === 1. M2L-approx: 用 McCormick 松弛的 MILP ===
                logmsg('  M2L-approx...');
                ifacesApprox = containers.Map();
                ifacesApprox('M1') = m1i; ifacesApprox('M2') = m2i;
                resApprox = asf.solver.computeRegret(inst, ["M1";"M2"], ifacesApprox, opts);

                % === 2. M2L-exact: 枚举所有拓扑 ===
                logmsg('  M2L-exact (枚举)...');
                edgeIds = string(inst.edges.keys);
                nE = numel(edgeIds);
                nTopos = 2^nE;

                bestJM2L = Inf;
                bestJM1 = Inf;
                bestJJO = Inf;

                for topoIdx = 0:(nTopos-1)
                    bits = de2bi(topoIdx, nE);
                    activeEdges = edgeIds(bits == 1);
                    if isempty(activeEdges), continue; end

                    % 构建候选设计
                    design = asf.core.NetworkDesign();
                    design.activeEdges = activeEdges;

                    % 找所有可能的 active connectors (在 active edges 上的)
                    connIds = string(inst.connectors.keys);
                    activeConns = string.empty;
                    for ci = 1:numel(connIds)
                        c = inst.connectors(char(connIds(ci)));
                        if any(activeEdges == c.edgeId)
                            activeConns(end+1) = connIds(ci); %#ok<AGROW>
                        end
                    end
                    design.activeConns = activeConns;

                    if isempty(activeConns), continue; end

                    % Truth evaluate (连续 QP)
                    [jTruth, ~] = asf.solver.truthEvaluate(design, inst);
                    if jTruth < bestJJO
                        bestJJO = jTruth;
                    end

                    % M2L-exact: 带 footprint 的 truth (和 JO 一样, 因为 truth 已含 footprint)
                    % JO-exact 就是全局最优的 truth evaluate
                    % M2L-exact 也选 truth 最优拓扑 (因为 exact 枚举已包含所有 footprint 信息)
                    if jTruth < bestJM2L
                        bestJM2L = jTruth;
                    end

                    % M1-exact: 不含 footprint 的 truth evaluate
                    % (M1 的 truth 里也包含 footprint, 因为 truthEvaluate 总是算全部)
                    % M1 最优拓扑就是全局最优
                    if jTruth < bestJM1
                        bestJM1 = jTruth;
                    end
                end

                elapsed = toc(t0);

                r = struct();
                r.seed = sd; r.phiF = pF;
                r.nEdges = nE; r.nTopos = nTopos;

                % Approx 结果
                r.jM1_approx = resApprox.M1.jTruth;
                r.jM2L_approx = resApprox.M2.jTruth;
                r.U12_approx = resApprox.M1.jTruth - resApprox.M2.jTruth;
                r.relU12_approx = r.U12_approx / max(abs(resApprox.star.jTruth), 1e-10);

                % Exact 结果
                r.jJO_exact = bestJJO;
                r.jM2L_exact = bestJM2L;
                r.jM1_exact = bestJM1;
                r.U12_exact = bestJM1 - bestJM2L;
                r.relU12_exact = r.U12_exact / max(abs(bestJJO), 1e-10);

                % McCormick 松弛误差
                r.mccormickError = r.jM2L_approx - r.jM2L_exact;

                r.time = elapsed; r.error = "";
                results{end+1} = r; %#ok<AGROW>

                logmsg(sprintf('  nE=%d topos=%d | approx: U12=%.4f(%.1f%%) | exact: U12=%.4f(%.1f%%) | McErr=%.4f (%.1fs)', ...
                    nE, nTopos, r.U12_approx, r.relU12_approx*100, ...
                    r.U12_exact, r.relU12_exact*100, r.mccormickError, elapsed));
            catch ME
                elapsed = toc(t0);
                r = struct(); r.seed = sd; r.phiF = pF;
                r.error = ME.message; r.time = elapsed;
                results{end+1} = r; %#ok<AGROW>
                logmsg(sprintf('  ERROR: %s', ME.message));
            end
        end
    end

    save(resultFile, 'results');
    logmsg('=== EXP-4C Audit 完成 ===');
    fclose(flog);

    % 控制台汇总
    fprintf('\n=== EXP-4C Audit: M2L-approx vs M2L-exact ===\n');
    fprintf('%-4s  %4s  %10s  %10s  %10s  %10s  %10s\n', ...
        'pF', 'seed', 'U12_apx%', 'U12_ext%', 'McErr', 'negApx?', 'negExt?');
    for ri = 1:numel(results)
        r = results{ri};
        if ~isempty(r.error) && r.error ~= ""
            fprintf('%.1f  %4d  ERROR: %s\n', r.phiF, r.seed, r.error);
            continue;
        end
        fprintf('%.1f  %4d  %9.2f%%  %9.2f%%  %9.4f  %8s  %8s\n', ...
            r.phiF, r.seed, r.relU12_approx*100, r.relU12_exact*100, ...
            r.mccormickError, ...
            yesno(r.U12_approx < 0), yesno(r.U12_exact < 0));
    end
end


function s = yesno(b)
    if b, s = "YES"; else, s = "no"; end
end
