function design = solveMILP(inst, level, ifaces, opts)
    % solveMILP 构建并求解 MILP
    %
    %   服务成本二次项用 PwL 近似：对每个 port 的 b*λ² 用分段线性上逼近。
    %   引入辅助变量 ψ_{t,h} 表示 port 级服务成本的 PwL 值。
    arguments
        inst asf.core.ProblemInstance
        level (1,1) string = "Mstar"
        ifaces = containers.Map()
        opts struct = struct('nPwl', 7, 'verbose', false)
    end

    edgeIds = string(inst.edges.keys);
    connIds = string(inst.connectors.keys);
    nE = numel(edgeIds);
    nC = numel(connIds);
    comms = inst.getCommodities();
    nK = size(comms, 1);

    % 收集 backbone 节点
    nodeMap = containers.Map();
    nIdx = 0;
    for i = 1:nE
        e = inst.edges(char(edgeIds(i)));
        if ~nodeMap.isKey(char(e.nodeU)), nIdx=nIdx+1; nodeMap(char(e.nodeU))=nIdx; end
        if ~nodeMap.isKey(char(e.nodeV)), nIdx=nIdx+1; nodeMap(char(e.nodeV))=nIdx; end
    end

    % Port 列表
    tkeys = inst.terminals.keys;
    portList = {};  % {tid, pid, a, b}
    for ti = 1:numel(tkeys)
        t = inst.terminals(tkeys{ti});
        for pi = 1:numel(t.ports)
            p = t.ports(pi);
            portList{end+1} = struct('tid', tkeys{ti}, 'pid', char(p.portId), ...
                'a', p.a, 'b', p.b); %#ok<AGROW>
        end
    end
    nP = numel(portList);

    % Connector → port 映射: connPortIdx(i) = 该 connector 对应的 portList 索引
    connPortIdx = zeros(nC, 1);
    for ci = 1:nC
        c = inst.connectors(char(connIds(ci)));
        for pi = 1:nP
            if strcmp(portList{pi}.tid, char(c.terminalId)) && strcmp(portList{pi}.pid, char(c.portId))
                connPortIdx(ci) = pi; break;
            end
        end
    end

    % === 获取每个 port 的服务成本参数（按 level） ===
    portA = zeros(nP, 1);  % 线性系数
    portB = zeros(nP, 1);  % 二次系数
    for pi = 1:nP
        tid = portList{pi}.tid;
        pid = portList{pi}.pid;
        if level == "M0" && ifaces.isKey(tid)
            m0 = ifaces(tid);
            % M0: 聚合 → 所有 port 共享 aggregate 系数（按 port 数均分）
            t = inst.terminals(tid);
            nPorts = numel(t.ports);
            portA(pi) = m0.aBar / nPorts;
            portB(pi) = m0.bBar / nPorts;
        elseif (level == "M1" || level == "M2") && ifaces.isKey(tid)
            m1 = ifaces(tid);
            if isfield(m1.portService, pid)
                portA(pi) = m1.portService.(pid).a;
                portB(pi) = m1.portService.(pid).b;
            end
        else
            % Mstar: truth coefficients
            portA(pi) = portList{pi}.a;
            portB(pi) = portList{pi}.b;
        end
    end

    % === 变量布局 ===
    % x(nE) | y(nC) | f_fwd(nE) | f_rev(nE) | f_conn(nC) | lam(nP) | psi(nP) | unmet(1)
    oX = 0;
    oY = nE;
    oFwd = nE + nC;
    oRev = oFwd + nE;
    oFc = oRev + nE;
    oLam = oFc + nC;
    oPsi = oLam + nP;
    oUn = oPsi + nP;
    nVars = oUn + 1;

    nBin = nE + nC;

    % === 边数据 ===
    edgeCosts = zeros(nE, 1);
    edgeCaps = zeros(nE, 1);
    edgeCC = zeros(nE, 1);
    for i = 1:nE
        e = inst.edges(char(edgeIds(i)));
        edgeCosts(i) = e.travelCost;
        edgeCaps(i) = e.capacity;
        edgeCC(i) = e.constructionCost;
    end
    connCosts = zeros(nC, 1);
    for i = 1:nC
        c = inst.connectors(char(connIds(i)));
        connCosts(i) = c.travelCost;
    end

    % === 目标函数 ===
    fObj = zeros(nVars, 1);
    fObj(oX+1:oX+nE) = edgeCC;
    fObj(oFwd+1:oFwd+nE) = edgeCosts;
    fObj(oRev+1:oRev+nE) = edgeCosts;
    fObj(oFc+1:oFc+nC) = connCosts;
    % 线性服务成本 a*λ 通过 port load 变量
    fObj(oLam+1:oLam+nP) = portA;
    % PwL 近似的二次成本通过 ψ 变量
    fObj(oPsi+1:oPsi+nP) = 1;  % ψ 直接进目标
    fObj(oUn+1) = inst.unmetPenalty;

    % M2 footprint penalty on x
    if level == "M2"
        for ti = 1:numel(tkeys)
            if ~ifaces.isKey(tkeys{ti}), continue; end
            m2 = ifaces(tkeys{ti});
            if isfield(m2, 'nominalPenalty')
                fnames = fieldnames(m2.nominalPenalty);
                for fi = 1:numel(fnames)
                    eIdx = find(edgeIds == string(fnames{fi}));
                    if ~isempty(eIdx)
                        fObj(oX + eIdx) = fObj(oX + eIdx) + m2.nominalPenalty.(fnames{fi});
                    end
                end
            end
            if isfield(m2, 'blockedEdges')
                for bi = 1:numel(m2.blockedEdges)
                    eIdx = find(edgeIds == m2.blockedEdges(bi));
                    if ~isempty(eIdx)
                        fObj(oX + eIdx) = fObj(oX + eIdx) + 1e4;
                    end
                end
            end
        end
    elseif level == "Mstar"
        for ti = 1:numel(tkeys)
            t = inst.terminals(tkeys{ti});
            fnames = fieldnames(t.fpBasePenalty);
            for fi = 1:numel(fnames)
                eIdx = find(edgeIds == string(fnames{fi}));
                if ~isempty(eIdx)
                    fObj(oX + eIdx) = fObj(oX + eIdx) + t.fpBasePenalty.(fnames{fi});
                end
            end
            for bi = 1:numel(t.blockedEdges)
                eIdx = find(edgeIds == t.blockedEdges(bi));
                if ~isempty(eIdx)
                    fObj(oX + eIdx) = fObj(oX + eIdx) + 1e4;
                end
            end
        end
    end

    % === 不等式约束 ===
    Aineq = []; bineq = [];

    % C1: f_fwd + f_rev <= cap * x
    for i = 1:nE
        row = zeros(1, nVars);
        row(oFwd + i) = 1; row(oRev + i) = 1; row(oX + i) = -edgeCaps(i);
        Aineq(end+1,:) = row; bineq(end+1,1) = 0; %#ok<AGROW>
    end

    % C2: f_conn <= bigM * y
    for i = 1:nC
        row = zeros(1, nVars);
        row(oFc + i) = 1; row(oY + i) = -1000;
        Aineq(end+1,:) = row; bineq(end+1,1) = 0; %#ok<AGROW>
    end

    % C3: y <= x
    for i = 1:nC
        c = inst.connectors(char(connIds(i)));
        eIdx = find(edgeIds == c.edgeId);
        if ~isempty(eIdx)
            row = zeros(1, nVars);
            row(oY + i) = 1; row(oX + eIdx) = -1;
            Aineq(end+1,:) = row; bineq(end+1,1) = 0; %#ok<AGROW>
        end
    end

    % C7: PwL 近似 b*λ² → ψ >= 斜率_j * λ - 截距_j
    % 对凸函数 b*λ², 切线下界: ψ >= 2b*λ_j * λ - b*λ_j²
    nPwl = opts.nPwl;
    for pi = 1:nP
        b = portB(pi);
        if abs(b) < 1e-10, continue; end
        % 断点: 均匀分布在 [0, capMax]
        tid = portList{pi}.tid;
        t = inst.terminals(tid);
        capMax = t.muBar;
        bps = linspace(0, capMax, nPwl);
        for j = 1:nPwl
            % 切线: ψ >= 2b*bp_j * λ - b*bp_j²
            % → -ψ + 2b*bp_j * λ <= b*bp_j²
            % → ψ - 2b*bp_j * λ >= -b*bp_j²
            % Aineq: -(ψ - slope*λ) <= intercept → -ψ + slope*λ <= intercept
            row = zeros(1, nVars);
            row(oPsi + pi) = -1;
            row(oLam + pi) = 2 * b * bps(j);
            Aineq(end+1,:) = row; %#ok<AGROW>
            bineq(end+1,1) = b * bps(j)^2; %#ok<AGROW>
        end
    end

    % === 等式约束 ===
    Aeq = []; beq = [];

    % C4: Admissibility (M0 skips)
    if level ~= "M0"
        for i = 1:nC
            c = inst.connectors(char(connIds(i)));
            key = char(c.terminalId + "_" + c.portId + "_" + c.edgeId);
            admissible = false;
            if inst.admissibility.isKey(key)
                admissible = inst.admissibility(key);
            end
            if ~admissible
                row = zeros(1, nVars);
                row(oY + i) = 1;
                Aeq(end+1,:) = row; beq(end+1,1) = 0; %#ok<AGROW>
            end
        end
    end

    % C5: Flow conservation at backbone nodes
    allNodes = nodeMap.keys;
    for ni = 1:numel(allNodes)
        node = allNodes{ni};
        row = zeros(1, nVars);
        for i = 1:nE
            e = inst.edges(char(edgeIds(i)));
            if char(e.nodeV) == string(node), row(oFwd+i) = 1; end   % fwd inflow
            if char(e.nodeU) == string(node), row(oFwd+i) = row(oFwd+i) - 1; end  % fwd outflow
            if char(e.nodeU) == string(node), row(oRev+i) = 1; end   % rev inflow
            if char(e.nodeV) == string(node), row(oRev+i) = row(oRev+i) - 1; end  % rev outflow
        end
        % Connector outflow from terminal backbone node
        for i = 1:nC
            c = inst.connectors(char(connIds(i)));
            if char(c.terminalId) == string(node)
                row(oFc + i) = -1;
            end
        end
        % Supply
        supply = 0;
        for ki = 1:nK
            if char(comms(ki,1)) == string(node)
                supply = supply - inst.getDemand(comms(ki,1), comms(ki,2));
            end
        end
        Aeq(end+1,:) = row; beq(end+1,1) = supply; %#ok<AGROW>
    end

    % C6: Port load = Σ connector flows to that port
    for pi = 1:nP
        row = zeros(1, nVars);
        row(oLam + pi) = -1;
        for ci = 1:nC
            if connPortIdx(ci) == pi
                row(oFc + ci) = 1;
            end
        end
        Aeq(end+1,:) = row; beq(end+1,1) = 0; %#ok<AGROW>
    end

    % Demand balance: Σ port_loads + unmet = totalDemand
    totalDemand = 0;
    for ki = 1:nK
        totalDemand = totalDemand + inst.getDemand(comms(ki,1), comms(ki,2));
    end
    row = zeros(1, nVars);
    row(oLam+1:oLam+nP) = 1;
    row(oUn+1) = 1;
    Aeq(end+1,:) = row; beq(end+1,1) = totalDemand;

    % === 变量边界 ===
    lb = zeros(nVars, 1);
    ub = Inf(nVars, 1);
    ub(oX+1:oX+nE) = 1;
    ub(oY+1:oY+nC) = 1;
    intcon = 1:nBin;

    % === 求解 ===
    optns = optimoptions('intlinprog', 'Display', 'off');
    if opts.verbose
        optns = optimoptions('intlinprog', 'Display', 'final');
    end

    [sol, fval, exitflag] = intlinprog(fObj, intcon, Aineq, bineq, Aeq, beq, lb, ub, optns);

    design = asf.core.NetworkDesign();
    if exitflag <= 0, return; end

    design.objective = fval;
    design.activeEdges = edgeIds(sol(oX+1:oX+nE) > 0.5);
    design.activeConns = connIds(sol(oY+1:oY+nC) > 0.5);
    for pi = 1:nP
        key = strcat(portList{pi}.tid, '_', portList{pi}.pid);
        design.portLoads(key) = sol(oLam + pi);
    end
    design.unmetDemand('total') = sol(oUn+1);
end
