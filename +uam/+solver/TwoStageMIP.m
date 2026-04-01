classdef TwoStageMIP < handle
    % TwoStageMIP 上层网络设计两阶段随机 MIP（主论文层）
    %
    %   决策变量:
    %     x(e)           ∈ {0,1}  走廊激活
    %     z(t,k)         ∈ {0,1}  终端样式选择
    %     f(e,ω)         ≥ 0      走廊流量
    %     unmet(ω)       ≥ 0      未满足需求
    %     psi(t,ω)       ≥ 0      终端广义成本 Ψ_t
    %
    %   目标函数:
    %     J = F^route(x) + Σ_ω p_ω [Σ c_e f_e^ω + Σ_t psi_t^ω + κ·unmet^ω]
    %
    %   约束:
    %     C1: f ≤ cap·x                  走廊容量
    %     C2: x ≤ Σ feasCoeff·z          走廊可行性
    %     C3: Σ z = 1                     样式唯一
    %     C4: Σ f + unmet ≥ demand       需求满足
    %     C5: λ_{t,h} = Σ f_e            负荷-流量链接
    %     C6a: Σ λ_{t,h} ≤ μ_t          总终端容量
    %     C6b: λ_{t,h} ≤ λ̄_{t,h}        接口有效域
    %     C7: psi ≥ 分段线性化(λ)         Ψ_t SOS2 近似

    properties
        instance    % NetworkInstance
        plugin      % TerminalPlugin
        eta     (1,1) double = 1.0    % 延误权重
        xi      (1,1) double = 0      % 外部性权重
        numPwlPts (1,1) double = 8    % 分段线性化断点数
    end

    properties (Access = private)
        prob
        vars
    end

    methods
        function obj = TwoStageMIP(instance, plugin, eta, xi, numPwlPts)
            arguments
                instance
                plugin
                eta (1,1) double = 1.0
                xi (1,1) double = 0
                numPwlPts (1,1) double = 8
            end
            obj.instance = instance;
            obj.plugin = plugin;
            obj.eta = eta;
            obj.xi = xi;
            obj.numPwlPts = numPwlPts;
        end

        function result = solve(obj)
            obj.buildProblem();

            opts = optimoptions('intlinprog', 'Display', 'off');
            [sol, fval, exitflag] = solve(obj.prob, 'Options', opts);

            if exitflag <= 0
                result.design = uam.core.NetworkDesign();
                result.objective = Inf;
                result.exitflag = exitflag;
                result.status = "infeasible";
                return;
            end

            result.design = obj.extractDesign(sol);
            result.objective = fval;
            result.exitflag = exitflag;
            result.status = "optimal";
        end
    end

    methods (Access = private)
        function buildProblem(obj)
            inst = obj.instance;
            nE = inst.numCorridors();
            nT = inst.numTerminals();
            nW = inst.numScenarios();

            styleIds = obj.getAllStyleIds();
            totalStyles = sum(cellfun(@numel, styleIds));

            % ============ 决策变量 ============
            x = optimvar('x', nE, 1, 'Type', 'integer', ...
                'LowerBound', 0, 'UpperBound', 1);
            f = optimvar('f', nE, nW, 'LowerBound', 0);
            unmet = optimvar('unmet', nW, 1, 'LowerBound', 0);
            z = optimvar('z', totalStyles, 1, 'Type', 'integer', ...
                'LowerBound', 0, 'UpperBound', 1);
            psi = optimvar('psi', nT, nW, 'LowerBound', 0);

            obj.vars = struct('x', x, 'f', f, 'unmet', unmet, 'z', z, 'psi', psi);

            % ============ 目标函数 ============
            actCosts = arrayfun(@(c) c.activationCost, inst.corridors);
            objExpr = sum(actCosts(:) .* x);

            flowCosts = arrayfun(@(c) c.cost, inst.corridors);
            for w = 1:nW
                pw = inst.scenarios(w).probability;
                objExpr = objExpr + pw * sum(flowCosts(:) .* f(:,w));
                objExpr = objExpr + pw * sum(psi(:,w));  % Ψ_t 进目标
                objExpr = objExpr + pw * inst.unmetPenalty * unmet(w);
            end

            prob = optimproblem('ObjectiveSense', 'minimize');
            prob.Objective = objExpr;

            % ============ C1: 走廊容量 ============
            caps = arrayfun(@(c) c.capacity, inst.corridors);
            for w = 1:nW
                prob.Constraints.(['cap_w' num2str(w)]) = ...
                    f(:,w) <= caps(:) .* x;
            end

            % ============ C2: 走廊可行性 ============
            zIdx = 0;
            for t = 1:nT
                tid = inst.terminals(t);
                nK = numel(styleIds{t});
                zRange = zIdx+1 : zIdx+nK;

                for e = 1:nE
                    corr = inst.corridors(e);
                    if corr.origin ~= tid && corr.destination ~= tid
                        continue;
                    end
                    feasCoeff = zeros(nK, 1);
                    for k = 1:nK
                        sid = styleIds{t}(k);
                        isFeas = obj.plugin.isCorridorFeasible(tid, sid, corr.id);
                        isBlock = obj.plugin.isCorridorBlocked(tid, sid, corr.id);
                        feasCoeff(k) = double(isFeas && ~isBlock);
                    end
                    prob.Constraints.(sprintf('feas_T%d_E%d', t, e)) = ...
                        x(e) <= sum(feasCoeff .* z(zRange));
                end
                zIdx = zIdx + nK;
            end

            % ============ C3: 样式唯一 ============
            zIdx = 0;
            for t = 1:nT
                nK = numel(styleIds{t});
                prob.Constraints.(['oneStyle_T' num2str(t)]) = ...
                    sum(z(zIdx+1 : zIdx+nK)) == 1;
                zIdx = zIdx + nK;
            end

            % ============ C4: 需求满足 ============
            for w = 1:nW
                scen = inst.scenarios(w);
                totalDemand = sum(cell2mat(scen.odDemand.values));
                prob.Constraints.(['demand_w' num2str(w)]) = ...
                    sum(f(:,w)) + unmet(w) >= totalDemand;
            end

            % ============ C5/C6/C7: 终端负荷 + 容量 + Ψ_t ============
            % 对每个终端，查询 plugin 获取 Ψ 断点，构建分段线性约束
            obj.buildTerminalConstraints(prob, f, psi, nT, nE, nW, inst, styleIds);

            obj.prob = prob;
        end

        function buildTerminalConstraints(obj, prob, f, psi, nT, nE, nW, inst, styleIds)
            % 为每个终端构建 C5(负荷链接) + C6(容量) + C7(Ψ分段线性化)

            for t = 1:nT
                tid = inst.terminals(t);
                % 取第一个样式（z 外生固定时只有一个）
                sid = styleIds{t}(1);

                % 获取 Ψ 断点
                [bpData, valData, isPerInterface] = ...
                    obj.plugin.getPsiBreakpoints(tid, sid, obj.eta, obj.xi, obj.numPwlPts);

                mu = obj.plugin.getCapacity(tid, sid);

                if ~isPerInterface
                    % === A0: 总负荷一元模式 ===
                    obj.buildA0TerminalConstraints( ...
                        prob, f, psi, t, tid, nE, nW, inst, bpData, valData, mu);
                else
                    % === A1/A2/Full: 按接口分解模式 ===
                    obj.buildPerInterfaceTerminalConstraints( ...
                        prob, f, psi, t, tid, sid, nE, nW, inst, bpData, valData, mu);
                end
            end
        end

        function buildA0TerminalConstraints(obj, prob, f, psi, t, tid, nE, nW, inst, bp, vals, mu)
            % A0: 总负荷 → 一元 Ψ_t 分段线性化
            % bp, vals 是向量（总负荷断点 → Ψ 值）

            for w = 1:nW
                % 总负荷 = Σ 流经该终端的走廊流量
                flowExpr = obj.buildTotalLoadExpr(f, t, tid, nE, w, inst);

                % C6a: 总容量上界
                prob.Constraints.(sprintf('capTotal_T%d_w%d', t, w)) = ...
                    flowExpr <= mu;

                % C7: 分段线性化（上方弦近似 = 逐段线性约束）
                % 对凸函数，用断点间的线性插值
                m = numel(bp);
                for j = 1:m-1
                    if bp(j+1) - bp(j) < 1e-12, continue; end
                    slope = (vals(j+1) - vals(j)) / (bp(j+1) - bp(j));
                    % psi >= slope * (lambda - bp_j) + vals_j  （凸下界切线）
                    % 但我们要上方弦近似。对 min 问题，用切线是低估。
                    % 所以改用：psi 直接通过 SOS2 插值。
                    % 简化实现：对小规模用多段线性约束上界
                end

                % 简化 SOS2 实现：用增量式
                % delta_j = lambda 在第 j 段的增量
                % psi = Σ slope_j * delta_j + vals(1)
                m = numel(bp);
                if m < 2
                    prob.Constraints.(sprintf('psiZero_T%d_w%d', t, w)) = psi(t,w) == 0;
                    continue;
                end

                segWidths = diff(bp);
                segSlopes = diff(vals) ./ max(segWidths, 1e-12);
                nSeg = m - 1;

                delta = optimvar(sprintf('dA0_T%d_w%d', t, w), nSeg, 1, 'LowerBound', 0);
                y = optimvar(sprintf('yA0_T%d_w%d', t, w), nSeg, 1, 'Type', 'integer', ...
                    'LowerBound', 0, 'UpperBound', 1);

                % delta_j <= segWidth_j * y_j
                for j = 1:nSeg
                    prob.Constraints.(sprintf('dBnd_T%d_w%d_j%d', t, w, j)) = ...
                        delta(j) <= segWidths(j) * y(j);
                end

                % 排序：y_j >= y_{j+1}（保证从左到右填充）
                for j = 1:nSeg-1
                    prob.Constraints.(sprintf('yOrd_T%d_w%d_j%d', t, w, j)) = ...
                        y(j) >= y(j+1);
                end

                % 负荷链接：flowExpr = bp(1) + Σ delta_j
                prob.Constraints.(sprintf('loadLink_T%d_w%d', t, w)) = ...
                    flowExpr == bp(1) + sum(delta);

                % Ψ 链接：psi = vals(1) + Σ slope_j * delta_j
                prob.Constraints.(sprintf('psiLink_T%d_w%d', t, w)) = ...
                    psi(t,w) == vals(1) + sum(segSlopes(:) .* delta);
            end
        end

        function buildPerInterfaceTerminalConstraints(obj, prob, f, psi, t, tid, sid, nE, nW, inst, bpCell, valCell, mu)
            % A1/A2/Full: 按接口分解 → 每接口单独分段线性化

            resp = obj.plugin.getResponse(tid, sid);
            nH = numel(resp.interfaceIds);

            for w = 1:nW
                psiExpr = optimexpr(0);  % 累计 Ψ_t

                totalLoadExpr = optimexpr(0);

                for h = 1:nH
                    hId = resp.interfaceIds(h);
                    bp = bpCell{h};
                    vals = valCell{h};

                    % C5: λ_{t,h} = Σ f_e 流经该接口的走廊
                    loadExpr = obj.buildInterfaceLoadExpr(f, t, tid, hId, nE, w, inst);

                    totalLoadExpr = totalLoadExpr + loadExpr;

                    % C6b: 接口有效域
                    capMax = resp.interfaceCapMax(h);
                    prob.Constraints.(sprintf('capIF_T%d_h%d_w%d', t, h, w)) = ...
                        loadExpr <= capMax;

                    % C7: 每接口分段线性化
                    m = numel(bp);
                    if m < 2
                        continue;
                    end

                    segWidths = diff(bp);
                    segSlopes = diff(vals) ./ max(segWidths, 1e-12);
                    nSeg = m - 1;

                    delta = optimvar(sprintf('d_T%d_h%d_w%d', t, h, w), nSeg, 1, 'LowerBound', 0);
                    y = optimvar(sprintf('y_T%d_h%d_w%d', t, h, w), nSeg, 1, 'Type', 'integer', ...
                        'LowerBound', 0, 'UpperBound', 1);

                    for j = 1:nSeg
                        prob.Constraints.(sprintf('dBnd_T%d_h%d_w%d_j%d', t, h, w, j)) = ...
                            delta(j) <= segWidths(j) * y(j);
                    end

                    for j = 1:nSeg-1
                        prob.Constraints.(sprintf('yOrd_T%d_h%d_w%d_j%d', t, h, w, j)) = ...
                            y(j) >= y(j+1);
                    end

                    % 负荷链接
                    prob.Constraints.(sprintf('ldLnk_T%d_h%d_w%d', t, h, w)) = ...
                        loadExpr == bp(1) + sum(delta);

                    % 接口 Ψ 贡献
                    psiH = vals(1) + sum(segSlopes(:) .* delta);
                    psiExpr = psiExpr + psiH;
                end

                % C6a: 总容量
                prob.Constraints.(sprintf('capTotal_T%d_w%d', t, w)) = ...
                    totalLoadExpr <= mu;

                % 加 baseExternality 常数项（ξ > 0 时）
                baseExtCost = 0;
                if obj.xi > 0
                    resp2 = obj.plugin.getResponse(tid, sid);
                    baseExtCost = obj.xi * resp2.baseExternality / resp2.refExternality;
                end

                % Ψ_t = 延误项 + 基础外部性
                prob.Constraints.(sprintf('psiLink_T%d_w%d', t, w)) = ...
                    psi(t,w) == psiExpr + baseExtCost;
            end
        end

        function expr = buildTotalLoadExpr(~, f, t, tid, nE, w, inst)
            % 构建终端 t 在场景 w 的总负荷表达式 = Σ 关联走廊流量
            expr = optimexpr(0);
            for e = 1:nE
                corr = inst.corridors(e);
                if corr.origin == tid || corr.destination == tid
                    expr = expr + f(e, w);
                end
            end
        end

        function expr = buildInterfaceLoadExpr(~, f, t, tid, hId, nE, w, inst)
            % 构建终端 t 的接口 hId 在场景 w 的负荷
            % = Σ 走廊 e 如果 e 的 ID == hId 且 e 关联终端 t
            expr = optimexpr(0);
            for e = 1:nE
                corr = inst.corridors(e);
                if (corr.origin == tid || corr.destination == tid) && corr.id == hId
                    expr = expr + f(e, w);
                end
            end
        end

        function styleIds = getAllStyleIds(obj)
            inst = obj.instance;
            nT = inst.numTerminals();
            styleIds = cell(nT, 1);
            for t = 1:nT
                tid = inst.terminals(t);
                styles = inst.getStyles(tid);
                if iscell(styles)
                    styleIds{t} = arrayfun(@(s) s.styleId, [styles{:}]);
                else
                    styleIds{t} = arrayfun(@(s) s.styleId, styles);
                end
            end
        end

        function design = extractDesign(obj, sol)
            inst = obj.instance;
            nE = inst.numCorridors();
            nW = inst.numScenarios();
            styleIds = obj.getAllStyleIds();

            ca = containers.Map();
            for e = 1:nE
                cid = char(inst.corridors(e).id);
                ca(cid) = sol.x(e) > 0.5;
            end

            ss = containers.Map();
            zIdx = 0;
            for t = 1:numel(inst.terminals)
                tid = char(inst.terminals(t));
                nK = numel(styleIds{t});
                zVals = sol.z(zIdx+1 : zIdx+nK);
                [~, bestK] = max(zVals);
                ss(tid) = char(styleIds{t}(bestK));
                zIdx = zIdx + nK;
            end

            fa = containers.Map();
            um = containers.Map();
            tl = containers.Map();  % terminalLoads
            tp = containers.Map();  % terminalPsiCost
            for w = 1:nW
                wid = char(inst.scenarios(w).id);
                wFlow = containers.Map();
                for e = 1:nE
                    cid = char(inst.corridors(e).id);
                    wFlow(cid) = sol.f(e, w);
                end
                fa(wid) = wFlow;
                um(wid) = sol.unmet(w);
            end

            % 提取终端负荷和 Ψ 成本
            for t = 1:numel(inst.terminals)
                tidStr = char(inst.terminals(t));
                % Ψ 成本取第一个场景（单场景兼容）
                tp(tidStr) = sol.psi(t, 1);

                % 终端负荷从流量反推
                loads = containers.Map();
                sid = ss(tidStr);
                resp = obj.plugin.getResponse(inst.terminals(t), sid);
                for h = 1:numel(resp.interfaceIds)
                    hId = char(resp.interfaceIds(h));
                    loadVal = 0;
                    for e = 1:nE
                        corr = inst.corridors(e);
                        if (corr.origin == inst.terminals(t) || corr.destination == inst.terminals(t)) ...
                                && corr.id == resp.interfaceIds(h)
                            loadVal = loadVal + sol.f(e, 1);
                        end
                    end
                    loads(hId) = loadVal;
                end
                tl(tidStr) = loads;
            end

            design = uam.core.NetworkDesign(ca, ss, fa, um);
            design.terminalLoads = tl;
            design.terminalPsiCost = tp;
        end
    end
end
