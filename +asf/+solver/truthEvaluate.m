function [jTruth, breakdown] = truthEvaluate(design, inst)
    % truthEvaluate 固定设计(x,y)，用 truth model 精确评估（多商品流 QP）
    %
    %   固定 backbone 和 connector 激活，用 quadprog 重新求最优流分配。
    %   服务成本用精确二次型（非 PwL），保证 regret >= 0。
    %   多商品流：每 OD 对独立流分配，port load 为各 OD 贡献之和。
    arguments
        design asf.core.NetworkDesign
        inst asf.core.ProblemInstance
    end

    % === 索引化活跃弧 ===
    activeConns = design.activeConns;
    nAC = numel(activeConns);
    comms = inst.getCommodities();
    nK = size(comms, 1);

    if nAC == 0 || nK == 0
        totalDemand = 0;
        dkeys = inst.odDemand.keys;
        for i = 1:numel(dkeys)
            totalDemand = totalDemand + inst.odDemand(dkeys{i});
        end
        jTruth = sum(arrayfun(@(eid) inst.edges(char(eid)).constructionCost, design.activeEdges)) ...
               + inst.unmetPenalty * totalDemand;
        breakdown.constructionCost = jTruth - inst.unmetPenalty * totalDemand;
        breakdown.travelCost = 0;
        breakdown.serviceCost = 0;
        breakdown.footprintCost = 0;
        breakdown.unmetCost = inst.unmetPenalty * totalDemand;
        breakdown.total = jTruth;
        return;
    end

    % 决策变量: f_conn(nAC, nK) + unmet(nK)
    %   f(ci, ki) = flow on active connector ci for commodity ki
    %   变量布局: [f_conn(nAC*nK) | unmet(nK)]
    nVars = nAC * nK + nK;

    % === Connector → terminal/port/edge 预索引 ===
    connTid = strings(nAC, 1);
    connPid = strings(nAC, 1);
    connEid = strings(nAC, 1);
    for ci = 1:nAC
        c = inst.connectors(char(activeConns(ci)));
        connTid(ci) = c.terminalId;
        connPid(ci) = c.portId;
        connEid(ci) = c.edgeId;
    end

    % Admissibility mask
    admissibleMask = true(nAC, 1);
    for ci = 1:nAC
        key = char(connTid(ci) + "_" + connPid(ci) + "_" + connEid(ci));
        if inst.admissibility.isKey(key)
            admissibleMask(ci) = inst.admissibility(key);
        else
            admissibleMask(ci) = false;
        end
    end

    % === 构建 QP: min 0.5 x'Hx + f'x ===
    H = zeros(nVars);
    fLin = zeros(nVars, 1);

    % Travel cost (linear, per commodity)
    for ci = 1:nAC
        c = inst.connectors(char(activeConns(ci)));
        tcost = c.travelCost;
        if inst.edges.isKey(char(c.edgeId))
            tcost = tcost + inst.edges(char(c.edgeId)).travelCost;
        end
        for ki = 1:nK
            fIdx = (ki-1)*nAC + ci;
            fLin(fIdx) = tcost;
        end
    end

    % Unmet penalty (per commodity)
    for ki = 1:nK
        fLin(nAC*nK + ki) = inst.unmetPenalty;
    end

    % 终端服务成本（truth 二次型）
    % port load λ_{t,h} = Σ_k Σ_{ci→(t,h)} f(ci,k)
    % 服务成本 = Σ_{t,h} (a_h * λ + b_h * λ²) + coupling + saturation
    % λ² = (Σ_{k,ci} f(ci,k))² → 展开为 H 矩阵交叉项
    tkeys = inst.terminals.keys;
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        for pi = 1:numel(terminal.ports)
            port = terminal.ports(pi);
            % 找到所有流向 (tid, pid) 的 connector 索引
            cidxList = find(connTid == terminal.terminalId & connPid == port.portId);
            if isempty(cidxList), continue; end

            % 所有 (ci, ki) 变量索引
            varIdxAll = [];
            for ki = 1:nK
                for ci = cidxList'
                    varIdxAll(end+1) = (ki-1)*nAC + ci; %#ok<AGROW>
                end
            end

            % 线性项: a * λ_h = a * Σ_{k,ci} f(ci,k)
            for vi = varIdxAll
                fLin(vi) = fLin(vi) + port.a;
            end

            % 二次项: b * λ_h² = b * (Σ f)²
            for vi = varIdxAll
                for vj = varIdxAll
                    H(vi, vj) = H(vi, vj) + 2 * port.b;
                end
            end
        end

        % 跨端口耦合: m * λ_h * λ_{h'}
        fnames = fieldnames(terminal.coupling);
        for fi = 1:numel(fnames)
            mval = terminal.coupling.(fnames{fi});
            parts = split(fnames{fi}, '_');
            h1 = parts{1}; h2 = parts{2};
            cidx1 = find(connTid == terminal.terminalId & connPid == string(h1));
            cidx2 = find(connTid == terminal.terminalId & connPid == string(h2));
            varIdx1 = [];
            for ki = 1:nK
                for ci = cidx1', varIdx1(end+1) = (ki-1)*nAC + ci; end %#ok<AGROW>
            end
            varIdx2 = [];
            for ki = 1:nK
                for ci = cidx2', varIdx2(end+1) = (ki-1)*nAC + ci; end %#ok<AGROW>
            end
            for vi = varIdx1
                for vj = varIdx2
                    H(vi, vj) = H(vi, vj) + mval;
                    H(vj, vi) = H(vj, vi) + mval;
                end
            end
        end
    end

    % === 约束 ===
    Aeq_rows = []; Aeq_cols = []; Aeq_vals = [];
    beq = [];
    eqIdx = 0;

    % Per-commodity demand balance at destination:
    % Σ_{ci reaching dst_k's terminal} f(ci,k) + unmet(k) = demand_k
    for ki = 1:nK
        dst_k = comms(ki, 2);
        demand_k = inst.getDemand(comms(ki,1), comms(ki,2));
        eqIdx = eqIdx + 1;
        for ci = 1:nAC
            if connTid(ci) == dst_k
                fIdx = (ki-1)*nAC + ci;
                Aeq_rows(end+1) = eqIdx; Aeq_cols(end+1) = fIdx; Aeq_vals(end+1) = 1; %#ok<AGROW>
            end
        end
        Aeq_rows(end+1) = eqIdx; Aeq_cols(end+1) = nAC*nK + ki; Aeq_vals(end+1) = 1; %#ok<AGROW>
        beq(end+1,1) = demand_k; %#ok<AGROW>
    end

    % Admissibility: inadmissible connectors → f = 0 for all commodities
    for ci = 1:nAC
        if ~admissibleMask(ci)
            for ki = 1:nK
                eqIdx = eqIdx + 1;
                fIdx = (ki-1)*nAC + ci;
                Aeq_rows(end+1) = eqIdx; Aeq_cols(end+1) = fIdx; Aeq_vals(end+1) = 1; %#ok<AGROW>
                beq(end+1,1) = 0; %#ok<AGROW>
            end
        end
    end

    % Capacity: Σ_k Σ_{ci on edge e} f(ci,k) <= capacity(e)
    Aineq_rows = []; Aineq_cols = []; Aineq_vals = [];
    bineq = [];
    ineqIdx = 0;
    for ei = 1:numel(design.activeEdges)
        eid = design.activeEdges(ei);
        if ~inst.edges.isKey(char(eid)), continue; end
        e = inst.edges(char(eid));
        ineqIdx = ineqIdx + 1;
        for ci = 1:nAC
            if connEid(ci) == eid
                for ki = 1:nK
                    fIdx = (ki-1)*nAC + ci;
                    Aineq_rows(end+1) = ineqIdx; Aineq_cols(end+1) = fIdx; Aineq_vals(end+1) = 1; %#ok<AGROW>
                end
            end
        end
        bineq(end+1,1) = e.capacity; %#ok<AGROW>
    end

    Aeq = sparse(Aeq_rows, Aeq_cols, Aeq_vals, eqIdx, nVars);
    if ineqIdx > 0
        Aineq = sparse(Aineq_rows, Aineq_cols, Aineq_vals, ineqIdx, nVars);
    else
        Aineq = []; bineq = [];
    end

    lb = zeros(nVars, 1);
    ub = Inf(nVars, 1);

    % === 求解 QP ===
    H = (H + H') / 2;
    optns = optimoptions('quadprog', 'Display', 'off');
    [sol, ~, exitflag] = quadprog(H, fLin, Aineq, bineq, Aeq, beq, lb, ub, [], optns);

    if exitflag <= 0
        jTruth = Inf;
        breakdown = struct('total', Inf);
        return;
    end

    % === 成本分解 ===
    constructionCost = 0;
    for i = 1:numel(design.activeEdges)
        eid = design.activeEdges(i);
        if inst.edges.isKey(char(eid))
            constructionCost = constructionCost + inst.edges(char(eid)).constructionCost;
        end
    end

    % 计算每个 connector 的总流量（跨所有 commodity）
    connFlow = zeros(nAC, 1);
    for ci = 1:nAC
        for ki = 1:nK
            connFlow(ci) = connFlow(ci) + sol((ki-1)*nAC + ci);
        end
    end

    travelCost = 0;
    for ci = 1:nAC
        c = inst.connectors(char(activeConns(ci)));
        travelCost = travelCost + c.travelCost * connFlow(ci);
        if inst.edges.isKey(char(c.edgeId))
            travelCost = travelCost + inst.edges(char(c.edgeId)).travelCost * connFlow(ci);
        end
    end

    % 服务成本（truth 精确）
    serviceCost = 0;
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        loads = containers.Map();
        for pi = 1:numel(terminal.ports)
            loads(char(terminal.ports(pi).portId)) = 0;
        end
        for ci = 1:nAC
            if connTid(ci) == string(tkeys{ti})
                pid = char(connPid(ci));
                if loads.isKey(pid)
                    loads(pid) = loads(pid) + connFlow(ci);
                end
            end
        end
        serviceCost = serviceCost + asf.truth.serviceTruth(terminal, loads);
    end

    % Footprint 成本
    footprintCost = 0;
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        loads = containers.Map();
        for pi = 1:numel(terminal.ports)
            loads(char(terminal.ports(pi).portId)) = 0;
        end
        for ci = 1:nAC
            if connTid(ci) == string(tkeys{ti})
                pid = char(connPid(ci));
                if loads.isKey(pid)
                    loads(pid) = loads(pid) + connFlow(ci);
                end
            end
        end
        footprintCost = footprintCost + asf.truth.footprintTruth(terminal, inst, design.activeEdges, loads);
    end

    unmetCost = 0;
    for ki = 1:nK
        unmetCost = unmetCost + inst.unmetPenalty * sol(nAC*nK + ki);
    end

    jTruth = constructionCost + travelCost + serviceCost + footprintCost + unmetCost;

    breakdown.constructionCost = constructionCost;
    breakdown.travelCost = travelCost;
    breakdown.serviceCost = serviceCost;
    breakdown.footprintCost = footprintCost;
    breakdown.unmetCost = unmetCost;
    breakdown.total = jTruth;

    % 更新 design 的 port loads
    pkeys = design.portLoads.keys;
    for i = 1:numel(pkeys)
        design.portLoads(pkeys{i}) = 0;
    end
    for ci = 1:nAC
        key = char(connTid(ci) + "_" + connPid(ci));
        if design.portLoads.isKey(key)
            design.portLoads(key) = design.portLoads(key) + connFlow(ci);
        else
            design.portLoads(key) = connFlow(ci);
        end
    end
    design.truthObjective = jTruth;
end
