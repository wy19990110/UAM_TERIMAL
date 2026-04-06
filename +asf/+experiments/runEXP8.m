function runEXP8(outDir)
    % runEXP8 Quality-time frontier / scaling 分析
    %   按新的实验要求 §二.10:
    %   量化 "JO 很贵"：随 nT/nW/OD 密度增大，报告各模型 runtime + gap
    %   主图: quality-time frontier (x=runtime, y=gap-to-JO)
    %
    %   预期:
    %     - B0/B1: 便宜但质量差
    %     - JO: 质量高但代价大
    %     - PR: 质量接近 JO, 成本远低于 JO
    arguments
        outDir (1,1) string = "results/exp8"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp8_log.txt");
    resultFile = fullfile(outDir, "exp8_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);

    % 加载 calibrated rule
    ruleFile = fullfile('results', 'exp4d', 'calibrated_rule.mat');
    if exist(ruleFile, 'file')
        rl = load(ruleFile);
        rule = rl.calibratedRule;
    else
        rule = struct('eaThresh', 0.3, 'esThresh', 0.5, 'efThresh', 0.2);
    end

    % 递增规模
    scaleSpecs = struct('name', {}, 'spec', {});
    scaleSpecs(1) = struct('name', 'S3',  'spec', struct('nT',3, 'nW',2, 'targetEdges',[4,6]));
    scaleSpecs(2) = struct('name', 'S5',  'spec', struct('nT',5, 'nW',3, 'targetEdges',[9,13]));
    scaleSpecs(3) = struct('name', 'S8',  'spec', struct('nT',8, 'nW',5, 'targetEdges',[17,21]));
    scaleSpecs(4) = struct('name', 'S12', 'spec', struct('nT',12,'nW',8, 'targetEdges',[27,34]));
    scaleSpecs(5) = struct('name', 'S16', 'spec', struct('nT',16,'nW',10,'targetEdges',[37,47]));

    seeds = 1:3;
    % 固定中等参数
    alphaA = 0.25;
    phiF = 0.3;
    rho = 1.0;

    opts = struct('nPwl', 15, 'verbose', false);
    modelLevels = ["B0","B1","M1","M2","JO"];

    results = {};
    total = numel(scaleSpecs) * numel(seeds);
    done = 0;

    logmsg(sprintf('=== EXP-8 Scaling: %d 实例 ===', total));

    for si2 = 1:numel(scaleSpecs)
        sname = scaleSpecs(si2).name;
        spec = scaleSpecs(si2).spec;
        for si = 1:numel(seeds)
            sd = seeds(si);
            done = done + 1;
            logmsg(sprintf('[%d/%d] %s (nT=%d) seed=%d', done, total, sname, spec.nT, sd));

            try
                params = struct('alphaA', alphaA, 'kappaS', 2, 'phiF', phiF, 'rho', rho);
                inst = asf.graphgen.buildSynthetic(spec, sd, params);

                % 提取接口
                b0i = containers.Map(); b1i = containers.Map();
                m0i = containers.Map(); m1i = containers.Map(); m2i = containers.Map();
                tkeys = inst.terminals.keys;
                for ti = 1:numel(tkeys)
                    t = inst.terminals(tkeys{ti});
                    b0i(tkeys{ti}) = asf.interface.extractB0(t);
                    b1i(tkeys{ti}) = asf.interface.extractB1(t, inst);
                    m0i(tkeys{ti}) = asf.interface.extractM0(t);
                    m1i(tkeys{ti}) = asf.interface.extractM1(t, inst);
                    m2i(tkeys{ti}) = asf.interface.extractM2(t, inst);
                end

                r = struct();
                r.specName = sname; r.nTerminals = spec.nT; r.nWaypoints = spec.nW;
                r.seed = sd; r.error = "";

                % 先求解 JO 得到 benchmark
                logmsg('  求解 JO...');
                tJO = tic;
                joDesign = asf.solver.solveMILP(inst, "JO", containers.Map(), opts);
                joTime = toc(tJO);
                [jJO, ~] = asf.solver.truthEvaluate(joDesign, inst);
                r.joTruthObj = jJO;
                r.joTime = joTime;
                r.joTimedOut = joDesign.objective == Inf;

                % 各模型独立求解
                ifacesMap = containers.Map();
                ifacesMap('B0') = b0i; ifacesMap('B1') = b1i;
                ifacesMap('M0') = m0i; ifacesMap('M1') = m1i; ifacesMap('M2') = m2i;

                for lvi = 1:numel(modelLevels)
                    lv = modelLevels(lvi);
                    if lv == "JO", continue; end
                    tag = char(lv);
                    lvIfaces = containers.Map();
                    if ifacesMap.isKey(tag)
                        lvIfaces = ifacesMap(tag);
                    end
                    tLv = tic;
                    try
                        design = asf.solver.solveMILP(inst, lv, lvIfaces, opts);
                        lvTime = toc(tLv);
                        [jTruth, ~] = asf.solver.truthEvaluate(design, inst);
                        r.(tag).truthObj = jTruth;
                        r.(tag).gapToJO = jTruth - jJO;
                        r.(tag).gapPct = (jTruth - jJO) / max(abs(jJO), 1e-10);
                        r.(tag).time = lvTime;
                        r.(tag).timedOut = design.objective == Inf;
                    catch ME2
                        r.(tag).error = ME2.message;
                        r.(tag).time = toc(tLv);
                    end
                end

                % PR: rule-based
                E_A = inst.excitation.E_A;
                E_S = inst.excitation.E_S;
                E_F = inst.excitation.E_F;
                prRec = applyRule(E_A, E_S, E_F, rule.eaThresh, rule.esThresh, rule.efThresh);
                r.prRecommendation = char(prRec);
                if isfield(r, char(prRec)) && isfield(r.(char(prRec)), 'truthObj')
                    prData = r.(char(prRec));
                    r.PR.truthObj = prData.truthObj;
                    r.PR.gapToJO = prData.gapToJO;
                    r.PR.gapPct = prData.gapPct;
                    r.PR.time = prData.time;
                    r.PR.timedOut = prData.timedOut;
                elseif prRec == "M0" && isfield(r, 'B0')
                    r.PR = r.B0;  % M0 没单独跑时用 B0 近似
                end

                results{end+1} = r; %#ok<AGROW>
                logmsg(sprintf('  JO=%.1f(%.1fs) B0gap=%.1f%% M2gap=%.1f%% PRgap=%.1f%%', ...
                    jJO, joTime, ...
                    safeField(r,'B0','gapPct',NaN)*100, ...
                    safeField(r,'M2','gapPct',NaN)*100, ...
                    safeField(r,'PR','gapPct',NaN)*100));
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

    % 控制台汇总
    fprintf('\n=== EXP-8 Scaling / Quality-Time Frontier ===\n');
    fprintf('%-5s  %4s  %8s  %8s  %8s  %8s  %8s  %8s\n', ...
        'Spec', 'seed', 'JO_t', 'B0_gap%', 'B1_gap%', 'M2_gap%', 'PR_gap%', 'PR_t');
    for ri = 1:numel(results)
        r = results{ri};
        if ~isempty(r.error) && r.error ~= ""
            fprintf('%-5s  %4d  ERROR\n', r.specName, r.seed);
            continue;
        end
        fprintf('%-5s  %4d  %7.1fs  %7.1f%%  %7.1f%%  %7.1f%%  %7.1f%%  %7.1fs\n', ...
            r.specName, r.seed, r.joTime, ...
            safeField(r,'B0','gapPct',NaN)*100, ...
            safeField(r,'B1','gapPct',NaN)*100, ...
            safeField(r,'M2','gapPct',NaN)*100, ...
            safeField(r,'PR','gapPct',NaN)*100, ...
            safeField(r,'PR','time',NaN));
    end
end


function rec = applyRule(E_A, E_S, E_F, eaThresh, esThresh, efThresh)
    if E_F >= efThresh
        rec = "M2";
    elseif E_A >= eaThresh || E_S >= esThresh
        rec = "M1";
    else
        rec = "M0";
    end
end

function v = safeField(r, lvTag, fieldName, default)
    if isfield(r, lvTag) && isfield(r.(lvTag), fieldName)
        v = r.(lvTag).(fieldName);
    else
        v = default;
    end
end
