function runEXP0(outDir)
    % runEXP0 Factor Screening（前置实验）
    %   生成 600 base terminals，对每个做 5 类单参数扰动，
    %   评估 d_A(admissibility变化), d_S(service cost变化), d_F(footprint变化)
    %   不需要网络求解——只做 terminal 级 truth model 评估
    arguments
        outDir (1,1) string = "results/exp0"
    end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    logFile = fullfile(outDir, "exp0_log.txt");
    resultFile = fullfile(outDir, "exp0_results.mat");

    flog = fopen(logFile, 'a');
    logmsg = @(m) fprintf(flog, '[%s] %s\n', datestr(now,'HH:MM:SS'), m);
    logmsg('=== EXP-0 Factor Screening ===');

    nBase = 600;
    rng(42);

    % 扰动类型
    pertTypes = {'portGeom', 'routing', 'opConfig', 'context', 'demand'};
    nPert = numel(pertTypes);

    % 结果存储
    results = struct();
    results.d_A = zeros(nBase, nPert);
    results.d_S = zeros(nBase, nPert);
    results.d_F = zeros(nBase, nPert);
    results.pertTypes = pertTypes;

    for bi = 1:nBase
        if mod(bi, 100) == 0
            logmsg(sprintf('处理 %d/%d...', bi, nBase));
        end

        % 生成一个小实例（2 terminals + 1 waypoint）作为 base
        spec = struct('nT', 2, 'nW', 1, 'targetEdges', [2, 3]);
        baseParams = struct('alphaA', 0.1+rand*0.4, 'kappaS', 1+rand*3, ...
            'phiF', rand*0.5, 'rho', 0.5+rand*1.5);
        baseInst = asf.graphgen.buildSynthetic(spec, bi, baseParams);

        % Base 评估
        [baseAdm, baseSvc, baseFP] = evalTerminalMetrics(baseInst);

        % 5 类扰动
        for pi = 1:nPert
            pertInst = applyPerturbation(spec, bi, baseParams, pertTypes{pi});
            [pertAdm, pertSvc, pertFP] = evalTerminalMetrics(pertInst);

            % d_A: Hamming distance on admissibility
            results.d_A(bi, pi) = admHamming(baseAdm, pertAdm);
            % d_S: relative service cost change
            results.d_S(bi, pi) = abs(pertSvc - baseSvc) / max(abs(baseSvc), 1e-10);
            % d_F: relative footprint change
            results.d_F(bi, pi) = abs(pertFP - baseFP) / max(abs(baseFP), 1e-10);
        end
    end

    % 汇总 effect size
    logmsg('=== Effect Size 汇总 ===');
    for pi = 1:nPert
        logmsg(sprintf('%s: d_A=%.3f d_S=%.3f d_F=%.3f', ...
            pertTypes{pi}, mean(results.d_A(:,pi)), ...
            mean(results.d_S(:,pi)), mean(results.d_F(:,pi))));
    end

    save(resultFile, 'results');
    logmsg('=== EXP-0 完成 ===');
    fclose(flog);

    % 控制台输出
    fprintf('\n=== EXP-0 Factor Screening ===\n');
    fprintf('%-12s  %8s  %8s  %8s\n', 'Perturbation', 'mean_dA', 'mean_dS', 'mean_dF');
    for pi = 1:nPert
        fprintf('%-12s  %8.3f  %8.3f  %8.3f\n', pertTypes{pi}, ...
            mean(results.d_A(:,pi)), mean(results.d_S(:,pi)), mean(results.d_F(:,pi)));
    end
end

function inst = applyPerturbation(spec, seed, baseParams, pertType)
    % 对 base 参数施加单类型扰动
    params = baseParams;
    pertSeed = seed + 10000;  % 不同于 base 的 seed

    switch pertType
        case 'portGeom'
            % Port 几何扰动：增大 αA（改变 port 方向偏移）
            params.alphaA = min(1, params.alphaA + 0.3);
        case 'routing'
            % 路由扰动：改变 κS（port 间 service 非对称性）
            params.kappaS = params.kappaS * 2;
        case 'opConfig'
            % 运营配置扰动：改变 ρ（需求强度）
            params.rho = params.rho * 1.5;
        case 'context'
            % 环境扰动：改变 φF（footprint severity）
            params.phiF = min(1, params.phiF + 0.3);
        case 'demand'
            % 需求模式扰动：用不同 seed 生成不同 OD
            pertSeed = seed + 20000;
    end

    inst = asf.graphgen.buildSynthetic(spec, pertSeed, params);
end

function [admMap, svcCost, fpCost] = evalTerminalMetrics(inst)
    % 评估 terminal 级指标
    admMap = inst.admissibility;

    % Service cost: 给每个 port 单位负荷下的总成本
    svcCost = 0;
    tkeys = inst.terminals.keys;
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        loads = containers.Map();
        for pi = 1:numel(terminal.ports)
            loads(char(terminal.ports(pi).portId)) = 1.0;  % 单位负荷
        end
        svcCost = svcCost + asf.truth.serviceTruth(terminal, loads);
    end

    % Footprint cost: 假设所有 edge 都 active
    fpCost = 0;
    activeEdges = string(inst.edges.keys);
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        loads = containers.Map();
        for pi = 1:numel(terminal.ports)
            loads(char(terminal.ports(pi).portId)) = 1.0;
        end
        fpCost = fpCost + asf.truth.footprintTruth(terminal, inst, activeEdges, loads);
    end
end

function d = admHamming(map1, map2)
    % Hamming distance between two admissibility maps
    keys1 = map1.keys; keys2 = map2.keys;
    allKeys = unique([keys1, keys2]);
    differ = 0;
    for i = 1:numel(allKeys)
        k = allKeys{i};
        v1 = false; v2 = false;
        if map1.isKey(k), v1 = map1(k); end
        if map2.isKey(k), v2 = map2(k); end
        if v1 ~= v2, differ = differ + 1; end
    end
    d = differ / max(numel(allKeys), 1);
end
