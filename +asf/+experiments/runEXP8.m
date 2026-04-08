function runEXP8(outDir)
    % runEXP8  Quality-time frontier / scaling 分析 (二轮修改)
    %   修改:
    %     - 用 M2N 代替 M2, 去掉 PR
    %     - 新 gap 指标: Delta_J / J_scale
    %     - JO quality gate: status + MIPGap
    %     - S12/S16 seeds 扩到 10, 新增 S20
    %     - 报告 median + IQR
    arguments
        outDir (1,1) string = "results/exp8"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp8_log.txt");
    resultFile = fullfile(outDir, "exp8_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 递增规模 (二轮: 新增 S20)
    scaleSpecs = struct('name', {}, 'spec', {}, 'seeds', {});
    scaleSpecs(1) = struct('name', 'S3',  'spec', struct('nT',3, 'nW',2, 'targetEdges',[4,6]), 'seeds', 1:3);
    scaleSpecs(2) = struct('name', 'S5',  'spec', struct('nT',5, 'nW',3, 'targetEdges',[9,13]), 'seeds', 1:3);
    scaleSpecs(3) = struct('name', 'S8',  'spec', struct('nT',8, 'nW',5, 'targetEdges',[17,21]), 'seeds', 1:3);
    scaleSpecs(4) = struct('name', 'S12', 'spec', struct('nT',12,'nW',8, 'targetEdges',[27,34]), 'seeds', 1:10);
    scaleSpecs(5) = struct('name', 'S16', 'spec', struct('nT',16,'nW',10,'targetEdges',[37,47]), 'seeds', 1:10);
    scaleSpecs(6) = struct('name', 'S20', 'spec', struct('nT',20,'nW',12,'targetEdges',[47,60]), 'seeds', 1:10);

    % 固定中等参数
    alphaA = 0.25;
    phiF = 0.3;
    rho = 1.0;

    opts = struct('nPwl', 15, 'verbose', false);
    modelLevels = ["B0","B1","M1","M2N"];

    results = {};
    total = 0;
    for si2 = 1:numel(scaleSpecs)
        total = total + numel(scaleSpecs(si2).seeds);
    end
    done = 0;

    logmsg(sprintf('=== EXP-8 Scaling (二轮): %d 实例 ===', total));

    for si2 = 1:numel(scaleSpecs)
        sname = scaleSpecs(si2).name;
        spec = scaleSpecs(si2).spec;
        seedList = scaleSpecs(si2).seeds;
        for si = 1:numel(seedList)
            sd = seedList(si);
            done = done + 1;
            logmsg(sprintf('[%d/%d] %s (nT=%d) seed=%d', done, total, sname, spec.nT, sd));

            try
                params = struct('alphaA', alphaA, 'kappaS', 2, 'phiF', phiF, 'rho', rho);
                inst = asf.graphgen.buildSynthetic(spec, sd, params);

                % J_scale (二轮修改)
                totalDemand = 0;
                dkeys = inst.odDemand.keys;
                for di = 1:numel(dkeys)
                    totalDemand = totalDemand + inst.odDemand(dkeys{di});
                end
                ekeys = inst.edges.keys;
                meanTC = mean(arrayfun(@(k) inst.edges(char(k)).travelCost, string(ekeys)));
                J_scale = totalDemand * meanTC;

                % 提取接口 (M2N)
                b0i = containers.Map(); b1i = containers.Map();
                m1i = containers.Map(); m2ni = containers.Map();
                tkeys = inst.terminals.keys;
                for ti = 1:numel(tkeys)
                    t = inst.terminals(tkeys{ti});
                    b0i(tkeys{ti}) = asf.interface.extractB0(t);
                    b1i(tkeys{ti}) = asf.interface.extractB1(t, inst);
                    m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                    m2ni(tkeys{ti}) = asf.interface.extractM2N(t, inst);
                end

                r = struct();
                r.specName = sname; r.nTerminals = spec.nT; r.nWaypoints = spec.nW;
                r.seed = sd; r.error = ""; r.J_scale = J_scale;

                % 先求解 JO
                logmsg('  求解 JO...');
                tJO = tic;
                joDesign = asf.solver.solveMILP(inst, "JO", containers.Map(), opts);
                joTime = toc(tJO);
                r.joTime = joTime;
                r.joStatus = joDesign.solveStatus;
                r.joMipGap = joDesign.mipGap;

                joTimedOut = joDesign.objective == Inf;
                r.joTimedOut = joTimedOut;

                % JO quality gate
                joOptimal = (joDesign.solveStatus == 1);
                joGapOK = (~isnan(joDesign.mipGap) && joDesign.mipGap <= 1e-3);
                r.joQualified = joOptimal || joGapOK;

                if joTimedOut
                    r.joTruthObj = Inf;
                    logmsg('  JO 求解失败/超时');
                    r.error = "JO_timeout";
                    results{end+1} = r; %#ok<AGROW>
                    continue;
                end
                [jJO, ~] = asf.solver.truthEvaluate(joDesign, inst);
                r.joTruthObj = jJO;

                % 各模型独立求解
                ifacesMap = containers.Map();
                ifacesMap('B0') = b0i; ifacesMap('B1') = b1i;
                ifacesMap('M1') = m1i; ifacesMap('M2') = m2ni;  % M2N 走 M2 solver 分支

                for lvi = 1:numel(modelLevels)
                    lv = modelLevels(lvi);
                    % M2N 在 solver 中用 "M2" level
                    if lv == "M2N"
                        solverLv = "M2";
                        ifKey = "M2";
                    else
                        solverLv = lv;
                        ifKey = char(lv);
                    end
                    tag = char(lv);
                    tLv = tic;
                    try
                        lvIfaces = containers.Map();
                        if ifacesMap.isKey(ifKey)
                            lvIfaces = ifacesMap(ifKey);
                        end
                        design = asf.solver.solveMILP(inst, solverLv, lvIfaces, opts);
                        lvTime = toc(tLv);
                        lvTimedOut = design.objective == Inf;
                        r.(tag).time = lvTime;
                        r.(tag).timedOut = lvTimedOut;
                        if lvTimedOut
                            r.(tag).truthObj = Inf;
                            r.(tag).deltaJ = Inf;
                            r.(tag).deltaJ_scaled = Inf;
                        else
                            [jTruth, ~] = asf.solver.truthEvaluate(design, inst);
                            r.(tag).truthObj = jTruth;
                            r.(tag).deltaJ = jTruth - jJO;
                            r.(tag).deltaJ_scaled = (jTruth - jJO) / max(J_scale, 1e-10);
                        end
                    catch ME2
                        r.(tag).error = ME2.message;
                        r.(tag).time = toc(tLv);
                        r.(tag).truthObj = Inf;
                        r.(tag).deltaJ = Inf;
                        r.(tag).deltaJ_scaled = Inf;
                        r.(tag).timedOut = true;
                    end
                end

                results{end+1} = r; %#ok<AGROW>
                logmsg(sprintf('  JO=%.1f(gap=%.1e,qual=%d) B0Δ=%.2f%% M2NΔ=%.2f%% (%.1fs)', ...
                    jJO, joDesign.mipGap, r.joQualified, ...
                    safeField(r,'B0','deltaJ_scaled',NaN)*100, ...
                    safeField(r,'M2N','deltaJ_scaled',NaN)*100, ...
                    joTime));
            catch ME
                r = struct(); r.specName = sname; r.nTerminals = spec.nT; r.seed = sd;
                r.error = ME.message;
                results{end+1} = r; %#ok<AGROW>
                logmsg(sprintf('  ERROR: %s', ME.message));
            end
        end
    end

    save(resultFile, 'results');
    logmsg('=== EXP-8 完成 ===');
    fclose(flog);

    % 控制台汇总: per-scale median + IQR
    fprintf('\n=== EXP-8 Scaling / Quality-Time Frontier (二轮) ===\n');
    for si2 = 1:numel(scaleSpecs)
        sname = scaleSpecs(si2).name;
        % 收集该 scale 的 qualified results
        scaleResults = {};
        for ri = 1:numel(results)
            r = results{ri};
            if ~isfield(r, 'specName'), continue; end
            if string(r.specName) ~= string(sname), continue; end
            if ~isempty(r.error) && r.error ~= "", continue; end
            if ~r.joQualified, continue; end
            scaleResults{end+1} = r; %#ok<AGROW>
        end
        n = numel(scaleResults);
        if n == 0
            fprintf('%-5s: no qualified results\n', sname);
            continue;
        end
        fprintf('\n%-5s (n=%d qualified):\n', sname, n);
        fprintf('  JO runtime: median=%.1fs IQR=[%.1f, %.1f]\n', ...
            median(cellfun(@(r) r.joTime, scaleResults)), ...
            quantile(cellfun(@(r) r.joTime, scaleResults), 0.25), ...
            quantile(cellfun(@(r) r.joTime, scaleResults), 0.75));
        for lv = modelLevels
            tag = char(lv);
            vals = [];
            times = [];
            for qi = 1:n
                if isfield(scaleResults{qi}, tag) && isfield(scaleResults{qi}.(tag), 'deltaJ_scaled')
                    vals(end+1) = scaleResults{qi}.(tag).deltaJ_scaled; %#ok<AGROW>
                    times(end+1) = scaleResults{qi}.(tag).time; %#ok<AGROW>
                end
            end
            if ~isempty(vals)
                fprintf('  %-4s: med_Δ/Js=%.2f%% IQR=[%.2f%%,%.2f%%] med_t=%.1fs\n', ...
                    tag, median(vals)*100, quantile(vals,0.25)*100, quantile(vals,0.75)*100, ...
                    median(times));
            end
        end
    end

    % QA flag: S16 seed=2
    fprintf('\n--- QA Check: S16 seed=2 ---\n');
    for ri = 1:numel(results)
        r = results{ri};
        if isfield(r, 'specName') && string(r.specName) == "S16" && r.seed == 2
            if ~isempty(r.error) && r.error ~= ""
                fprintf('  ERROR: %s\n', r.error);
            else
                fprintf('  JO=%.4f status=%d mipGap=%.1e qualified=%d\n', ...
                    r.joTruthObj, r.joStatus, r.joMipGap, r.joQualified);
                for lv = modelLevels
                    tag = char(lv);
                    if isfield(r, tag) && isfield(r.(tag), 'deltaJ_scaled')
                        fprintf('  %s: Δ/Js=%.4f%%\n', tag, r.(tag).deltaJ_scaled*100);
                    end
                end
            end
            break;
        end
    end
end


function v = safeField(r, lvTag, fieldName, default)
    if isfield(r, lvTag) && isfield(r.(lvTag), fieldName)
        v = r.(lvTag).(fieldName);
    else
        v = default;
    end
end
