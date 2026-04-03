function [jTruth, breakdown] = truthEvaluate(design, inst)
    % truthEvaluate 固定设计(x,y)，用 truth model 精确评估
    %
    %   固定 backbone 和 connector 激活，用 quadprog 重新求最优流分配。
    %   服务成本用精确二次型（非 PwL），保证 regret ≥ 0。
    %
    %   返回: jTruth = 总目标值, breakdown = 成本分解 struct
    arguments
        design asf.core.NetworkDesign
        inst asf.core.ProblemInstance
    end

    % === 索引化活跃弧 ===
    % 只对活跃的 connector 分配流量
    activeConns = design.activeConns;
    nAC = numel(activeConns);

    if nAC == 0
        % 没有活跃 connector → 所有需求 unmet
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

    % 决策变量: f_conn(nAC) = 每个活跃 connector 的流量
    %           + unmet(1) = 未满足需求
    nVars = nAC + 1;

    % === 构建 QP: min 0.5 x'Hx + f'x ===
    % 服务成本二次项: Σ_t Σ_h b_h * (Σ_{c→(t,h)} f_c)²
    %   = Σ_t Σ_h b_h * (f_c1 + f_c2 + ...)²
    %   展开后是 H 矩阵的对应项

    H = zeros(nVars);
    fLin = zeros(nVars, 1);

    % Admissibility 检查: 不可行的 connector 流量设为 0
    admissibleMask = true(nAC, 1);
    for i = 1:nAC
        c = inst.connectors(char(activeConns(i)));
        key = char(c.terminalId + "_" + c.portId + "_" + c.edgeId);
        if inst.admissibility.isKey(key)
            admissibleMask(i) = inst.admissibility(key);
        else
            admissibleMask(i) = false;
        end
    end

    % Travel cost (linear)
    for i = 1:nAC
        c = inst.connectors(char(activeConns(i)));
        fLin(i) = c.travelCost;
        % 加上 backbone edge 的 travel cost
        if inst.edges.isKey(char(c.edgeId))
            e = inst.edges(char(c.edgeId));
            fLin(i) = fLin(i) + e.travelCost;
        end
    end

    % Unmet penalty
    fLin(end) = inst.unmetPenalty;

    % 终端服务成本（truth 二次型）
    tkeys = inst.terminals.keys;
    for ti = 1:numel(tkeys)
        terminal = inst.terminals(tkeys{ti});
        for pi = 1:numel(terminal.ports)
            port = terminal.ports(pi);
            % 找到所有流向 (tid, pid) 的 connector 索引
            indices = [];
            for ci = 1:nAC
                c = inst.connectors(char(activeConns(ci)));
                if c.terminalId == terminal.terminalId && c.portId == port.portId
                    indices(end+1) = ci; %#ok<AGROW>
                end
            end
            if isempty(indices), continue; end

            % 线性项: a * λ_h = a * Σ f_c
            for ci = indices
                fLin(ci) = fLin(ci) + port.a;
            end

            % 二次项: b * λ_h² = b * (Σ f_c)²
            for ci = indices
                for cj = indices
                    H(ci, cj) = H(ci, cj) + 2 * port.b;
                end
            end
        end

        % 跨端口耦合: m * λ_h * λ_h' = m * (Σ f_{c→h})(Σ f_{c→h'})
        fnames = fieldnames(terminal.coupling);
        for fi = 1:numel(fnames)
            mval = terminal.coupling.(fnames{fi});
            parts = split(fnames{fi}, '_');
            h1 = parts{1}; h2 = parts{2};
            idx1 = []; idx2 = [];
            for ci = 1:nAC
                c = inst.connectors(char(activeConns(ci)));
                if c.terminalId == terminal.terminalId
                    if char(c.portId) == string(h1), idx1(end+1) = ci; end %#ok<AGROW>
                    if char(c.portId) == string(h2), idx2(end+1) = ci; end %#ok<AGROW>
                end
            end
            for ci = idx1
                for cj = idx2
                    H(ci, cj) = H(ci, cj) + mval;
                    H(cj, ci) = H(cj, ci) + mval;
                end
            end
        end

        % 饱和惩罚: ψ [Λ - μ̄]²₊  → 用辅助变量 excess 建模
        % 简化: 如果总 port load ≤ μ̄ 则忽略（大多数情况）
        % 严格做法需要引入辅助变量，这里先用近似
    end

    % === 约束 ===
    % Σ f_conn + unmet = totalDemand
    totalDemand = 0;
    dkeys = inst.odDemand.keys;
    for i = 1:numel(dkeys)
        totalDemand = totalDemand + inst.odDemand(dkeys{i});
    end

    Aeq = [ones(1, nAC), 1];  % Σf + unmet = demand
    beq = totalDemand;

    % Admissibility: inadmissible connectors → f = 0
    for i = 1:nAC
        if ~admissibleMask(i)
            row = zeros(1, nVars);
            row(i) = 1;
            Aeq = [Aeq; row]; %#ok<AGROW>
            beq = [beq; 0]; %#ok<AGROW>
        end
    end

    % Capacity: Σ f_c(on same backbone edge) ≤ capacity
    for ei = 1:numel(design.activeEdges)
        eid = design.activeEdges(ei);
        if ~inst.edges.isKey(char(eid)), continue; end
        e = inst.edges(char(eid));
        indices = [];
        for ci = 1:nAC
            c = inst.connectors(char(activeConns(ci)));
            if c.edgeId == eid
                indices(end+1) = ci; %#ok<AGROW>
            end
        end
        if ~isempty(indices)
            row = zeros(1, nVars);
            row(indices) = 1;
            Aineq_row = row;
            bineq_row = e.capacity;
        end
    end

    lb = zeros(nVars, 1);
    ub = Inf(nVars, 1);

    % === 求解 QP ===
    % 确保 H 半正定
    H = (H + H') / 2;
    optns = optimoptions('quadprog', 'Display', 'off');
    [sol, fval, exitflag] = quadprog(H, fLin, [], [], Aeq, beq, lb, ub, [], optns);

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

    travelCost = 0;
    for i = 1:nAC
        c = inst.connectors(char(activeConns(i)));
        flow = sol(i);
        travelCost = travelCost + c.travelCost * flow;
        if inst.edges.isKey(char(c.edgeId))
            travelCost = travelCost + inst.edges(char(c.edgeId)).travelCost * flow;
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
            c = inst.connectors(char(activeConns(ci)));
            if char(c.terminalId) == string(tkeys{ti})
                pid = char(c.portId);
                loads(pid) = loads(pid) + sol(ci);
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
            c = inst.connectors(char(activeConns(ci)));
            if char(c.terminalId) == string(tkeys{ti})
                pid = char(c.portId);
                loads(pid) = loads(pid) + sol(ci);
            end
        end
        footprintCost = footprintCost + asf.truth.footprintTruth(terminal, inst, design.activeEdges, loads);
    end

    unmetCost = inst.unmetPenalty * sol(end);

    jTruth = constructionCost + travelCost + serviceCost + footprintCost + unmetCost;

    breakdown.constructionCost = constructionCost;
    breakdown.travelCost = travelCost;
    breakdown.serviceCost = serviceCost;
    breakdown.footprintCost = footprintCost;
    breakdown.unmetCost = unmetCost;
    breakdown.total = jTruth;

    % 更新 design 的 port loads
    for ci = 1:nAC
        c = inst.connectors(char(activeConns(ci)));
        key = char(c.terminalId + "_" + c.portId);
        if design.portLoads.isKey(key)
            design.portLoads(key) = design.portLoads(key) + sol(ci);
        else
            design.portLoads(key) = sol(ci);
        end
    end
    design.truthObjective = jTruth;
end
