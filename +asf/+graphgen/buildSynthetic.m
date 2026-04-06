function inst = buildSynthetic(spec, seed, params)
    % buildSynthetic 合成 port-augmented 候选图
    %
    %   先放节点、建 MST + 额外边，再按 incident edge 方向创建 ports，
    %   最后建 admissibility 和 connectors（含 non-incident connector）。
    %
    %   spec: struct with .nT, .nW, .targetEdges([min,max]),
    %         .hasAirport, .airportCenter, .airportRadius
    %   params: struct with .alphaA, .kappaS, .phiF, .rho
    %     可选: .couplingM (固定跨端口耦合值, NaN=随机)
    %           .psiSat   (固定饱和惩罚系数, NaN=随机)
    %           .concentration (OD 集中度, 0=均匀, 1=全部集中到单个 terminal)
    %           .portMisalignDeg (port 方向额外偏移角度, 0=不偏移)
    arguments
        spec struct
        seed (1,1) double = 42
        params struct = struct('alphaA',0.25,'kappaS',1,'phiF',0,'rho',1)
    end

    rng(seed);
    inst = asf.core.ProblemInstance();

    % === 1. 放置节点 ===
    nT = spec.nT; nW = spec.nW;
    allPos = containers.Map();

    tids = strings(nT, 1);
    for i = 1:nT
        tids(i) = sprintf("T%d", i);
        allPos(char(tids(i))) = [rand*0.9+0.05, rand*0.9+0.05];
    end
    for i = 1:nW
        wid = sprintf("W%d", i);
        inst.waypoints(wid) = [rand*0.9+0.05, rand*0.9+0.05];
        allPos(wid) = inst.waypoints(wid);
    end

    % === 2. 建 backbone edges (MST + extra) ===
    nodeIds = string(allPos.keys);
    nN = numel(nodeIds);
    distPairs = [];
    for i = 1:nN
        pi_ = allPos(char(nodeIds(i)));
        for j = i+1:nN
            pj = allPos(char(nodeIds(j)));
            d = sqrt((pi_(1)-pj(1))^2 + (pi_(2)-pj(2))^2);
            distPairs = [distPairs; d, i, j]; %#ok<AGROW>
        end
    end
    distPairs = sortrows(distPairs, 1);

    % Kruskal MST
    parent = 1:nN;
    mstEdges = [];
    for k = 1:size(distPairs,1)
        i = distPairs(k,2); j = distPairs(k,3);
        ri = findRoot(parent, i); rj = findRoot(parent, j);
        if ri ~= rj
            parent(ri) = rj;
            mstEdges = [mstEdges; k]; %#ok<AGROW>
        end
        if numel(mstEdges) >= nN-1, break; end
    end

    eidx = 0;
    usedPairs = false(size(distPairs,1),1);
    for k = mstEdges'
        usedPairs(k) = true;
        eidx = eidx+1;
        d = distPairs(k,1);
        u = nodeIds(distPairs(k,2)); v = nodeIds(distPairs(k,3));
        eid = sprintf("E%d", eidx);
        inst.edges(eid) = asf.core.BackboneEdge(eid, u, v, d, ...
            d*(0.8+rand*0.4), d*(0.5+rand*0.5), 20+randi(30));
    end

    % Extra edges
    target = randi(spec.targetEdges);
    for k = 1:size(distPairs,1)
        if eidx >= target, break; end
        if usedPairs(k), continue; end
        eidx = eidx+1;
        d = distPairs(k,1);
        u = nodeIds(distPairs(k,2)); v = nodeIds(distPairs(k,3));
        eid = sprintf("E%d", eidx);
        inst.edges(eid) = asf.core.BackboneEdge(eid, u, v, d, ...
            d*(0.8+rand*0.4), d*(0.5+rand*0.5), 20+randi(30));
    end

    % === 3. 创建 terminals（ports 对齐 incident edges + 随机偏移）===
    alphaA = params.alphaA;
    kappaS = params.kappaS;
    phiF = params.phiF;

    for ti = 1:nT
        tid = char(tids(ti));
        tpos = allPos(tid);

        % 找 incident edge 方向
        incDirs = [];
        incEids = string.empty;
        ekeys = inst.edges.keys;
        for ei = 1:numel(ekeys)
            e = inst.edges(ekeys{ei});
            other = "";
            if char(e.nodeU) == tid, other = e.nodeV; end
            if char(e.nodeV) == tid, other = e.nodeU; end
            if other == "", continue; end
            op = allPos(char(other));
            angle = mod(atan2d(op(2)-tpos(2), op(1)-tpos(1)), 360);
            incDirs(end+1) = angle; %#ok<AGROW>
            incEids(end+1) = string(ekeys{ei}); %#ok<AGROW>
        end

        nInc = numel(incDirs);
        nPorts = min(max(1, randi(3)), max(1, nInc));
        sectorHW = max(15, 50 - 70*alphaA);

        % Port 方向：聚类 incident edges
        if nInc == 0
            portDirs = rand*360;
        elseif nPorts == 1
            portDirs = incDirs(ceil(nInc/2));
            sectorHW = max(sectorHW, 180/max(nInc,1)+30);
        else
            [~, sortIdx] = sort(incDirs);
            portDirs = zeros(1, nPorts);
            for pi2 = 1:nPorts
                assigned = sortIdx(pi2:nPorts:nInc);
                angles = incDirs(assigned);
                ms = mean(sind(angles)); mc = mean(cosd(angles));
                portDirs(pi2) = mod(atan2d(ms, mc), 360);
            end
        end

        % === Port 方向随机偏移（核心改动）===
        % alphaA 越大偏移越大 → 更多 connector 变得 inadmissible → A 有区分力
        offsetRange = 20 + 40 * alphaA;  % [20°, 60°]
        % 额外 portMisalignDeg 偏移（EXP-5 A-sensitive proxy 用）
        if isfield(params, 'portMisalignDeg') && params.portMisalignDeg > 0
            offsetRange = offsetRange + params.portMisalignDeg;
        end
        for pi2 = 1:numel(portDirs)
            portDirs(pi2) = mod(portDirs(pi2) + (2*rand-1)*offsetRange, 360);
        end

        ports = asf.core.PortConfig.empty;
        coupling = struct();
        for pi2 = 1:nPorts
            ratio = 1 + (kappaS-1)*(pi2-1)/max(nPorts-1,1);
            a = 0.1 + rand*0.1;
            b = (0.2 + rand*0.2) * ratio;
            ports(pi2) = asf.core.PortConfig(sprintf("h%d",pi2), portDirs(pi2), sectorHW, a, b);
        end
        for pi2 = 1:nPorts
            for pj = pi2+1:nPorts
                fn = sprintf('h%d_h%d', pi2, pj);
                if isfield(params, 'couplingM') && ~isnan(params.couplingM)
                    coupling.(fn) = params.couplingM;
                else
                    coupling.(fn) = 0.05 + rand*0.15;
                end
            end
        end

        % Context
        ctx = "open-city";
        if isfield(spec, 'hasAirport') && spec.hasAirport
            dap = sqrt((tpos(1)-spec.airportCenter(1))^2 + (tpos(2)-spec.airportCenter(2))^2);
            if dap < spec.airportRadius*2, ctx = "airport-adjacent"; end
        end

        % Footprint（含 load-sensitivity）
        fpBP = struct(); fpLS = struct(); blocked = string.empty;
        if phiF > 0 && nInc > 0
            nPen = max(1, round(nInc * phiF));
            penIdx = randperm(nInc, min(nPen, nInc));
            for pi3 = penIdx
                fn = char(incEids(pi3));
                fn = strrep(fn, '-', '_');
                fpBP.(fn) = 0.5 + rand*1.5;
                % 为每个 port 生成 load-sensitivity 系数
                for pi4 = 1:nPorts
                    lsFn = sprintf('%s_h%d', fn, pi4);
                    fpLS.(lsFn) = 0.05 + rand*0.25;
                end
            end
            nBlock = floor(nPen/2);
            for bi = 1:nBlock
                blocked(end+1) = incEids(penIdx(bi)); %#ok<AGROW>
            end
        end

        if isfield(params, 'psiSat') && ~isnan(params.psiSat)
            effPsiSat = params.psiSat;
        else
            effPsiSat = 1+rand*4;
        end
        inst.terminals(tid) = asf.core.TerminalConfig(tids(ti), tpos(1), tpos(2), ports, ...
            'muBar', 3+rand*3, 'psiSat', effPsiSat, 'coupling', coupling, ...
            'fpRadius', 1, 'fpBasePenalty', fpBP, 'fpLoadSens', fpLS, ...
            'blockedEdges', blocked);
    end

    % === 4. Admissibility + Connectors（incident edges）===
    inst.admissibility = asf.truth.accessTruth(inst);
    cidx = 0;

    % 4a: Incident edge connectors（原有逻辑）
    tkeys2 = inst.terminals.keys;
    for ti = 1:numel(tkeys2)
        tid2 = string(tkeys2{ti});
        terminal = inst.terminals(tkeys2{ti});
        incEids2 = inst.incidentEdges(tid2);
        for ei = 1:numel(incEids2)
            eid2 = incEids2(ei);
            for pi2 = 1:numel(terminal.ports)
                port = terminal.ports(pi2);
                pid2 = port.portId;
                key = char(tid2 + "_" + pid2 + "_" + eid2);
                % 无论 admissible 与否都创建 connector（M0 不检查 admissibility）
                cidx = cidx + 1;
                d = inst.edgeDirection(eid2, tid2);
                cid = sprintf("C%d", cidx);
                inst.connectors(cid) = asf.core.ConnectorArc(cid, eid2, tid2, pid2, d, 0.05+rand*0.05);
            end
        end
    end

    % 4b: Non-incident connectors（新增：给 M0 提供"错误选项"）
    for ti = 1:numel(tkeys2)
        tid2 = string(tkeys2{ti});
        terminal = inst.terminals(tkeys2{ti});
        incEids2 = inst.incidentEdges(tid2);
        % 找 2-hop 邻域内的非 incident 边
        neighborEids = inst.neighborhoodEdges(tid2, 2);
        nonIncEids = setdiff(neighborEids, incEids2);
        % 取 1-2 条
        nNonInc = min(numel(nonIncEids), min(2, numel(terminal.ports)));
        if nNonInc > 0
            selIdx = randperm(numel(nonIncEids), nNonInc);
            for ni = 1:nNonInc
                eid2 = nonIncEids(selIdx(ni));
                e = inst.edges(char(eid2));
                [ux, uy] = inst.nodePos(e.nodeU);
                [vx, vy] = inst.nodePos(e.nodeV);
                mx = (ux+vx)/2; my = (uy+vy)/2;
                [tx, ty] = inst.nodePos(tid2);
                theta = mod(atan2d(my-ty, mx-tx), 360);
                % 为随机一个 port 创建 connector
                pi2 = randi(numel(terminal.ports));
                port = terminal.ports(pi2);
                pid2 = port.portId;
                cidx = cidx + 1;
                cid = sprintf("C%d", cidx);
                inst.connectors(cid) = asf.core.ConnectorArc(cid, eid2, tid2, pid2, theta, 0.08+rand*0.07);
            end
        end
    end

    % 重新计算 admissibility（包含新增的 non-incident connectors）
    inst.admissibility = asf.truth.accessTruth(inst);

    % === 5. 激发指标 E_A / E_S / E_F ===
    % E_A: 只统计有 connector 的 (tid,pid,eid) 组合
    ckeys2 = inst.connectors.keys;
    nConnTotal = numel(ckeys2);
    nConnAdm = 0;
    for ci = 1:nConnTotal
        c = inst.connectors(ckeys2{ci});
        key = char(c.terminalId + "_" + c.portId + "_" + c.edgeId);
        if inst.admissibility.isKey(key) && inst.admissibility(key)
            nConnAdm = nConnAdm + 1;
        end
    end
    E_A = 1 - nConnAdm / max(nConnTotal, 1);

    % E_S: port 间 marginal cost 离散度 + coupling 强度
    allMarginals = [];
    allCouplings = [];
    for ti = 1:numel(tkeys2)
        terminal = inst.terminals(tkeys2{ti});
        for pi2 = 1:numel(terminal.ports)
            allMarginals(end+1) = terminal.ports(pi2).a + 2*terminal.ports(pi2).b; %#ok<AGROW>
        end
        fnames = fieldnames(terminal.coupling);
        for fi = 1:numel(fnames)
            allCouplings(end+1) = terminal.coupling.(fnames{fi}); %#ok<AGROW>
        end
    end
    cvMarginal = std(allMarginals) / max(mean(allMarginals), 1e-10);
    meanCoupling = 0;
    if ~isempty(allCouplings), meanCoupling = mean(allCouplings); end
    E_S = cvMarginal + meanCoupling;

    % E_F: footprint penalty 占总建设成本比例
    totalFP = 0; totalCC = 0;
    ekeys2 = inst.edges.keys;
    for i = 1:numel(ekeys2)
        totalCC = totalCC + inst.edges(ekeys2{i}).constructionCost;
    end
    for ti = 1:numel(tkeys2)
        terminal = inst.terminals(tkeys2{ti});
        fnames = fieldnames(terminal.fpBasePenalty);
        for fi = 1:numel(fnames)
            totalFP = totalFP + terminal.fpBasePenalty.(fnames{fi});
        end
    end
    E_F = totalFP / max(totalCC, 1e-10);

    inst.excitation = struct('E_A', E_A, 'E_S', E_S, 'E_F', E_F);

    % === 6. 需求（含 concentration 支持）===
    concentration = 0;
    if isfield(params, 'concentration'), concentration = params.concentration; end
    % 集中目标 terminal
    concentrateOn = "";
    if concentration > 0
        concentrateOn = tids(randi(nT));
    end
    for i = 1:nT
        for j = 1:nT
            if i == j, continue; end
            if rand < 0.4
                baseDemand = (1+rand*2) * params.rho;
                if concentration > 0 && concentrateOn ~= ""
                    if tids(j) == concentrateOn || tids(i) == concentrateOn
                        baseDemand = baseDemand * (1 + concentration * 2);
                    else
                        baseDemand = baseDemand * max(0.3, 1 - concentration * 0.5);
                    end
                end
                key = char(tids(i) + "-" + tids(j));
                inst.odDemand(key) = baseDemand;
            end
        end
    end
end

function r = findRoot(parent, x)
    while parent(x) ~= x
        parent(x) = parent(parent(x));
        x = parent(x);
    end
    r = x;
end
