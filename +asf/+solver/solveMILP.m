function design = solveMILP(inst, level, ifaces, opts)
    % solveMILP 构建并求解多商品流 MILP
    %
    %   多商品流：每 OD 对独立流守恒
    %   服务成本二次项用 PwL 切线下界近似
    %   M2 footprint load-sensitivity 用 McCormick relaxation
    arguments
        inst asf.core.ProblemInstance
        level (1,1) string = "Mstar"
        ifaces = containers.Map()
        opts struct = struct('nPwl', 15, 'verbose', false)
    end

    % === Level 映射: B0→M0, B1→M1, JO→Mstar ===
    effectiveLevel = level;
    if level == "B0", effectiveLevel = "M0"; end
    if level == "B1", effectiveLevel = "M1"; end
    if level == "JO", effectiveLevel = "Mstar"; end

    edgeIds = string(inst.edges.keys);
    connIds = string(inst.connectors.keys);
    nE = numel(edgeIds);
    nC = numel(connIds);
    comms = inst.getCommodities();
    nK = size(comms, 1);
    if nK == 0
        design = asf.core.NetworkDesign();
        return;
    end

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
    portList = {};
    for ti = 1:numel(tkeys)
        t = inst.terminals(tkeys{ti});
        for pi = 1:numel(t.ports)
            p = t.ports(pi);
            portList{end+1} = struct('tid', tkeys{ti}, 'pid', char(p.portId), ...
                'a', p.a, 'b', p.b); %#ok<AGROW>
        end
    end
    nP = numel(portList);

    % Connector → port 映射
    connPortIdx = zeros(nC, 1);
    for ci = 1:nC
        c = inst.connectors(char(connIds(ci)));
        for pi = 1:nP
            if strcmp(portList{pi}.tid, char(c.terminalId)) && strcmp(portList{pi}.pid, char(c.portId))
                connPortIdx(ci) = pi; break;
            end
        end
    end

    % Connector → edge 映射
    connEdgeIdx = zeros(nC, 1);
    for ci = 1:nC
        c = inst.connectors(char(connIds(ci)));
        for ei = 1:nE
            if edgeIds(ei) == c.edgeId
                connEdgeIdx(ci) = ei; break;
            end
        end
    end

    % === 获取每个 port 的服务成本参数（按 level） ===
    portA = zeros(nP, 1);
    portB = zeros(nP, 1);
    for pi = 1:nP
        tid = portList{pi}.tid;
        pid = portList{pi}.pid;
        if effectiveLevel == "M0" && ifaces.isKey(tid)
            m0 = ifaces(tid);
            t = inst.terminals(tid);
            nPorts = numel(t.ports);
            portA(pi) = m0.aBar / nPorts;
            portB(pi) = m0.bBar / nPorts;
        elseif (effectiveLevel == "M1" || effectiveLevel == "M2") && ifaces.isKey(tid)
            m1 = ifaces(tid);
            if isfield(m1.portService, pid)
                portA(pi) = m1.portService.(pid).a;
                portB(pi) = m1.portService.(pid).b;
            end
        else
            portA(pi) = portList{pi}.a;
            portB(pi) = portList{pi}.b;
        end
    end

    % === 变量布局（多商品流）===
    % x(nE) | y(nC) | f_fwd(nE*nK) | f_rev(nE*nK) | f_conn(nC*nK) | lam(nP) | psi(nP) | unmet(nK)
    oX = 0;
    oY = nE;
    oFwd = nE + nC;
    oRev = oFwd + nE*nK;
    oFc = oRev + nE*nK;
    oLam = oFc + nC*nK;
    oPsi = oLam + nP;
    oUn = oPsi + nP;
    nVars = oUn + nK;

    % McCormick 辅助变量 w（仅 M2 + loadSensitivity）
    mcList = [];  % struct array: edgeIdx, portIdx, rho, lamMax
    oMc = nVars;
    if effectiveLevel == "M2"
        for ti = 1:numel(tkeys)
            if ~ifaces.isKey(tkeys{ti}), continue; end
            m2 = ifaces(tkeys{ti});
            if ~isfield(m2, 'loadSensitivity'), continue; end
            lsFnames = fieldnames(m2.loadSensitivity);
            for fi = 1:numel(lsFnames)
                sfn = lsFnames{fi};
                rhoVal = m2.loadSensitivity.(sfn);
                % 解析 edgeId_portId
                parts = split(string(sfn), '_');
                if numel(parts) < 2, continue; end
                eidStr = strjoin(parts(1:end-1), '_');
                pidStr = parts(end);
                eIdx = find(edgeIds == eidStr);
                if isempty(eIdx), continue; end
                pIdx = 0;
                for pi2 = 1:nP
                    if strcmp(portList{pi2}.tid, tkeys{ti}) && strcmp(portList{pi2}.pid, char(pidStr))
                        pIdx = pi2; break;
                    end
                end
                if pIdx == 0, continue; end
                t2 = inst.terminals(tkeys{ti});
                mcList = [mcList; struct('eIdx', eIdx, 'pIdx', pIdx, 'rho', rhoVal, 'lamMax', t2.muBar)]; %#ok<AGROW>
            end
        end
    end
    nMc = numel(mcList);
    nVars = nVars + nMc;

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
    % Travel cost per commodity
    for ki = 1:nK
        fObj(oFwd + (ki-1)*nE + (1:nE)) = edgeCosts;
        fObj(oRev + (ki-1)*nE + (1:nE)) = edgeCosts;
        fObj(oFc + (ki-1)*nC + (1:nC)) = connCosts;
    end
    % 线性服务成本 a*λ
    fObj(oLam+1:oLam+nP) = portA;
    % PwL 近似的二次成本通过 ψ 变量
    fObj(oPsi+1:oPsi+nP) = 1;
    % Unmet penalty per commodity
    fObj(oUn+1:oUn+nK) = inst.unmetPenalty;
    % McCormick: Σ ρ̃ * w
    for mi = 1:nMc
        fObj(oMc + mi) = mcList(mi).rho;
    end

    % M2 footprint nominal penalty on x
    if effectiveLevel == "M2"
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
    elseif effectiveLevel == "Mstar"
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
            % Mstar: load-sensitivity 也作为 McCormick（精确版直接加 ρ*λ*x）
            % 这里简化：Mstar 用 nominal penalty + loadSens 直接加到 edge cost
            lsFnames = fieldnames(t.fpLoadSens);
            for fi = 1:numel(lsFnames)
                % 在 truth evaluator 中精确处理，MILP 中仅用 nominal
            end
        end
    end

    % === 不等式约束 ===
    % 预分配稀疏构建
    Arows = []; Acols = []; Avals = [];
    bineq = [];
    rowIdx = 0;

    % C1: Σ_k f_fwd(e,k) + Σ_k f_rev(e,k) <= cap(e) * x(e)
    for i = 1:nE
        rowIdx = rowIdx + 1;
        for ki = 1:nK
            Arows(end+1) = rowIdx; Acols(end+1) = oFwd + (ki-1)*nE + i; Avals(end+1) = 1; %#ok<AGROW>
            Arows(end+1) = rowIdx; Acols(end+1) = oRev + (ki-1)*nE + i; Avals(end+1) = 1; %#ok<AGROW>
        end
        Arows(end+1) = rowIdx; Acols(end+1) = oX + i; Avals(end+1) = -edgeCaps(i); %#ok<AGROW>
        bineq(end+1,1) = 0; %#ok<AGROW>
    end

    % C2: f_conn(c,k) <= bigM * y(c)  for all c, k
    bigM = 1000;
    for ci = 1:nC
        for ki = 1:nK
            rowIdx = rowIdx + 1;
            Arows(end+1) = rowIdx; Acols(end+1) = oFc + (ki-1)*nC + ci; Avals(end+1) = 1; %#ok<AGROW>
            Arows(end+1) = rowIdx; Acols(end+1) = oY + ci; Avals(end+1) = -bigM; %#ok<AGROW>
            bineq(end+1,1) = 0; %#ok<AGROW>
        end
    end

    % C3: y(c) <= x(e) for connector c on edge e
    for ci = 1:nC
        eIdx = connEdgeIdx(ci);
        if eIdx > 0
            rowIdx = rowIdx + 1;
            Arows(end+1) = rowIdx; Acols(end+1) = oY + ci; Avals(end+1) = 1; %#ok<AGROW>
            Arows(end+1) = rowIdx; Acols(end+1) = oX + eIdx; Avals(end+1) = -1; %#ok<AGROW>
            bineq(end+1,1) = 0; %#ok<AGROW>
        end
    end

    % C7: PwL 切线下界 ψ >= 2b*bp_j * λ - b*bp_j²
    nPwl = opts.nPwl;
    for pi = 1:nP
        b = portB(pi);
        if abs(b) < 1e-10, continue; end
        tid = portList{pi}.tid;
        t = inst.terminals(tid);
        capMax = t.muBar;
        bps = linspace(0, capMax, nPwl);
        for j = 1:nPwl
            rowIdx = rowIdx + 1;
            Arows(end+1) = rowIdx; Acols(end+1) = oPsi + pi; Avals(end+1) = -1; %#ok<AGROW>
            Arows(end+1) = rowIdx; Acols(end+1) = oLam + pi; Avals(end+1) = 2*b*bps(j); %#ok<AGROW>
            bineq(end+1,1) = b * bps(j)^2; %#ok<AGROW>
        end
    end

    % McCormick constraints for w_{e,h} = λ_h * x_e
    for mi = 1:nMc
        eIdx = mcList(mi).eIdx;
        pIdx = mcList(mi).pIdx;
        lamMax = mcList(mi).lamMax;
        wIdx = oMc + mi;
        % w <= lamMax * x
        rowIdx = rowIdx + 1;
        Arows(end+1) = rowIdx; Acols(end+1) = wIdx; Avals(end+1) = 1; %#ok<AGROW>
        Arows(end+1) = rowIdx; Acols(end+1) = oX + eIdx; Avals(end+1) = -lamMax; %#ok<AGROW>
        bineq(end+1,1) = 0; %#ok<AGROW>
        % w <= λ
        rowIdx = rowIdx + 1;
        Arows(end+1) = rowIdx; Acols(end+1) = wIdx; Avals(end+1) = 1; %#ok<AGROW>
        Arows(end+1) = rowIdx; Acols(end+1) = oLam + pIdx; Avals(end+1) = -1; %#ok<AGROW>
        bineq(end+1,1) = 0; %#ok<AGROW>
        % -w <= -λ + lamMax*(1-x)  →  -w + λ - lamMax*x <= lamMax - 0  →  w >= λ - lamMax*(1-x)
        rowIdx = rowIdx + 1;
        Arows(end+1) = rowIdx; Acols(end+1) = wIdx; Avals(end+1) = -1; %#ok<AGROW>
        Arows(end+1) = rowIdx; Acols(end+1) = oLam + pIdx; Avals(end+1) = 1; %#ok<AGROW>
        Arows(end+1) = rowIdx; Acols(end+1) = oX + eIdx; Avals(end+1) = -lamMax; %#ok<AGROW>
        bineq(end+1,1) = 0; %#ok<AGROW>
        % w >= 0 is handled by lb
    end

    Aineq = sparse(Arows, Acols, Avals, rowIdx, nVars);

    % === 等式约束 ===
    EqRows = []; EqCols = []; EqVals = [];
    beq = [];
    eqIdx = 0;

    % C4: Admissibility (M0 and B0 skip)
    if effectiveLevel ~= "M0"
        for ci = 1:nC
            c = inst.connectors(char(connIds(ci)));
            key = char(c.terminalId + "_" + c.portId + "_" + c.edgeId);
            admissible = false;
            if inst.admissibility.isKey(key)
                admissible = inst.admissibility(key);
            end
            if ~admissible
                eqIdx = eqIdx + 1;
                EqRows(end+1) = eqIdx; EqCols(end+1) = oY + ci; EqVals(end+1) = 1; %#ok<AGROW>
                beq(end+1,1) = 0; %#ok<AGROW>
            end
        end
    end

    % C5: Per-commodity flow conservation at each backbone node
    allNodes = nodeMap.keys;
    for ki = 1:nK
        src_k = char(comms(ki,1));
        demand_k = inst.getDemand(comms(ki,1), comms(ki,2));

        for ni = 1:numel(allNodes)
            node = allNodes{ni};
            eqIdx = eqIdx + 1;

            % Backbone edge flows
            for ei = 1:nE
                e = inst.edges(char(edgeIds(ei)));
                fwdVar = oFwd + (ki-1)*nE + ei;
                revVar = oRev + (ki-1)*nE + ei;
                % fwd: nodeU → nodeV
                if strcmp(char(e.nodeV), node)  % fwd inflow
                    EqRows(end+1) = eqIdx; EqCols(end+1) = fwdVar; EqVals(end+1) = 1; %#ok<AGROW>
                end
                if strcmp(char(e.nodeU), node)  % fwd outflow
                    EqRows(end+1) = eqIdx; EqCols(end+1) = fwdVar; EqVals(end+1) = -1; %#ok<AGROW>
                end
                % rev: nodeV → nodeU
                if strcmp(char(e.nodeU), node)  % rev inflow
                    EqRows(end+1) = eqIdx; EqCols(end+1) = revVar; EqVals(end+1) = 1; %#ok<AGROW>
                end
                if strcmp(char(e.nodeV), node)  % rev outflow
                    EqRows(end+1) = eqIdx; EqCols(end+1) = revVar; EqVals(end+1) = -1; %#ok<AGROW>
                end
            end

            % Connector outflow from terminal backbone node
            for ci = 1:nC
                c = inst.connectors(char(connIds(ci)));
                if strcmp(char(c.terminalId), node)
                    fcVar = oFc + (ki-1)*nC + ci;
                    EqRows(end+1) = eqIdx; EqCols(end+1) = fcVar; EqVals(end+1) = -1; %#ok<AGROW>
                end
            end

            % Supply: only source node injects flow
            supply = 0;
            if string(node) == string(src_k)
                supply = -demand_k;
            end
            beq(end+1,1) = supply; %#ok<AGROW>
        end
    end

    % C6: Port load = Σ_k Σ_{c→p} f_conn(c,k)
    for pi = 1:nP
        eqIdx = eqIdx + 1;
        EqRows(end+1) = eqIdx; EqCols(end+1) = oLam + pi; EqVals(end+1) = -1; %#ok<AGROW>
        for ki = 1:nK
            for ci = 1:nC
                if connPortIdx(ci) == pi
                    fcVar = oFc + (ki-1)*nC + ci;
                    EqRows(end+1) = eqIdx; EqCols(end+1) = fcVar; EqVals(end+1) = 1; %#ok<AGROW>
                end
            end
        end
        beq(end+1,1) = 0; %#ok<AGROW>
    end

    % C8: Per-commodity demand balance at destination
    % Σ_{c reaching dst_k's ports} f_conn(c,k) + unmet(k) = demand_k
    for ki = 1:nK
        dst_k = char(comms(ki,2));
        demand_k = inst.getDemand(comms(ki,1), comms(ki,2));
        eqIdx = eqIdx + 1;
        for ci = 1:nC
            c = inst.connectors(char(connIds(ci)));
            if strcmp(char(c.terminalId), dst_k)
                fcVar = oFc + (ki-1)*nC + ci;
                EqRows(end+1) = eqIdx; EqCols(end+1) = fcVar; EqVals(end+1) = 1; %#ok<AGROW>
            end
        end
        EqRows(end+1) = eqIdx; EqCols(end+1) = oUn + ki; EqVals(end+1) = 1; %#ok<AGROW>
        beq(end+1,1) = demand_k; %#ok<AGROW>
    end

    Aeq = sparse(EqRows, EqCols, EqVals, eqIdx, nVars);

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
    totalUnmet = sum(sol(oUn+1:oUn+nK));
    design.unmetDemand('total') = totalUnmet;
end
