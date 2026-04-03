function inst = buildSynthetic(spec, seed, params)
    % buildSynthetic 合成 port-augmented 候选图
    %
    %   先放节点、建 MST + 额外边，再按 incident edge 方向创建 ports，
    %   最后建 admissibility 和 connectors。
    %
    %   spec: struct with .nT, .nW, .targetEdges([min,max]),
    %         .hasAirport, .airportCenter, .airportRadius
    %   params: struct with .alphaA, .kappaS, .phiF, .rho
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
    % 距离矩阵
    distPairs = [];  % [dist, i, j]
    for i = 1:nN
        pi = allPos(char(nodeIds(i)));
        for j = i+1:nN
            pj = allPos(char(nodeIds(j)));
            d = sqrt((pi(1)-pj(1))^2 + (pi(2)-pj(2))^2);
            distPairs = [distPairs; d, i, j]; %#ok<AGROW>
        end
    end
    distPairs = sortrows(distPairs, 1);

    % Kruskal MST
    parent = 1:nN;
    findP = @(x) deal(x); % placeholder
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

    % === 3. 创建 terminals（ports 对齐 incident edges）===
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
            for pi = 1:nPorts
                assigned = sortIdx(pi:nPorts:nInc);
                angles = incDirs(assigned);
                ms = mean(sind(angles)); mc = mean(cosd(angles));
                portDirs(pi) = mod(atan2d(ms, mc), 360);
            end
        end

        ports = asf.core.PortConfig.empty;
        coupling = struct();
        for pi = 1:nPorts
            ratio = 1 + (kappaS-1)*(pi-1)/max(nPorts-1,1);
            a = 0.1 + rand*0.1;
            b = (0.2 + rand*0.2) * ratio;
            ports(pi) = asf.core.PortConfig(sprintf("h%d",pi), portDirs(pi), sectorHW, a, b);
        end
        for pi = 1:nPorts
            for pj = pi+1:nPorts
                fn = sprintf('h%d_h%d', pi, pj);
                coupling.(fn) = 0.05 + rand*0.15;
            end
        end

        % Context
        ctx = "open-city";
        if isfield(spec, 'hasAirport') && spec.hasAirport
            dap = sqrt((tpos(1)-spec.airportCenter(1))^2 + (tpos(2)-spec.airportCenter(2))^2);
            if dap < spec.airportRadius*2, ctx = "airport-adjacent"; end
        end

        % Footprint
        fpBP = struct(); fpLS = struct(); blocked = string.empty;
        if phiF > 0 && nInc > 0
            nPen = max(1, round(nInc * phiF));
            penIdx = randperm(nInc, min(nPen, nInc));
            for pi2 = penIdx
                fn = char(incEids(pi2));
                fn = strrep(fn, '-', '_');
                fpBP.(fn) = 0.5 + rand*1.5;
            end
            nBlock = floor(nPen/2);
            for bi = 1:nBlock
                blocked(end+1) = incEids(penIdx(bi)); %#ok<AGROW>
            end
        end

        inst.terminals(tid) = asf.core.TerminalConfig(tids(ti), tpos(1), tpos(2), ports, ...
            'muBar', 3+rand*3, 'psiSat', 1+rand*4, 'coupling', coupling, ...
            'fpRadius', 1, 'fpBasePenalty', fpBP, 'fpLoadSens', struct(), ...
            'blockedEdges', blocked);
    end

    % === 4. Admissibility + Connectors ===
    inst.admissibility = asf.truth.accessTruth(inst);
    cidx = 0;
    akeys = inst.admissibility.keys;
    for i = 1:numel(akeys)
        if inst.admissibility(akeys{i})
            cidx = cidx+1;
            parts = split(string(akeys{i}), '_');
            tid2 = parts(1); pid2 = parts(2); eid2 = strjoin(parts(3:end),'_');
            d = inst.edgeDirection(eid2, tid2);
            cid = sprintf("C%d", cidx);
            inst.connectors(cid) = asf.core.ConnectorArc(cid, eid2, tid2, pid2, d, 0.05+rand*0.05);
        end
    end

    % === 5. 需求 ===
    for i = 1:nT
        for j = 1:nT
            if i == j, continue; end
            if rand < 0.4
                key = char(tids(i) + "-" + tids(j));
                inst.odDemand(key) = (1+rand*2) * params.rho;
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
