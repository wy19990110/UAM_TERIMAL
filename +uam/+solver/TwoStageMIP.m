classdef TwoStageMIP < handle
    % TwoStageMIP 上层网络设计两阶段随机 MIP
    %
    %   使用 optimproblem + intlinprog 求解。
    %
    %   决策变量:
    %     x(e)       ∈ {0,1}  走廊 e 是否激活
    %     z(t,k)     ∈ {0,1}  终端 t 是否选样式 k
    %     f(e,ω)     ≥ 0      场景 ω 下走廊 e 的流量
    %     unmet(ω)   ≥ 0      场景 ω 下未满足需求
    %
    %   目标函数:
    %     min Σ activationCost(e)*x(e)
    %       + Σ_ω p_ω * [Σ cost(e)*f(e,ω) + penalty*unmet(ω)]
    %
    %   约束:
    %     1. 流量 ≤ 容量 × 激活:  f(e,ω) ≤ cap(e) * x(e)
    %     2. 走廊可行性: x(e) ≤ Σ_k feasCoeff(t,k,e) * z(t,k)
    %     3. 样式唯一: Σ_k z(t,k) = 1
    %     4. 需求满足: Σ_e f(e,ω) + unmet(ω) ≥ demand(ω)

    properties
        instance    % NetworkInstance
        plugin      % TerminalPlugin
    end

    properties (Access = private)
        prob        % optimproblem
        vars        % struct: x, z, f, unmet
    end

    methods
        function obj = TwoStageMIP(instance, plugin)
            obj.instance = instance;
            obj.plugin = plugin;
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

            % 收集每个终端的样式 ID
            styleIds = obj.getAllStyleIds();
            totalStyles = sum(cellfun(@numel, styleIds));

            % === 决策变量 ===
            x = optimvar('x', nE, 1, 'Type', 'integer', ...
                'LowerBound', 0, 'UpperBound', 1);
            f = optimvar('f', nE, nW, 'LowerBound', 0);
            unmet = optimvar('unmet', nW, 1, 'LowerBound', 0);
            z = optimvar('z', totalStyles, 1, 'Type', 'integer', ...
                'LowerBound', 0, 'UpperBound', 1);

            obj.vars = struct('x', x, 'f', f, 'unmet', unmet, 'z', z);

            % === 目标函数 ===
            actCosts = arrayfun(@(c) c.activationCost, inst.corridors);
            objExpr = sum(actCosts(:) .* x);

            flowCosts = arrayfun(@(c) c.cost, inst.corridors);
            for w = 1:nW
                pw = inst.scenarios(w).probability;
                objExpr = objExpr + pw * sum(flowCosts(:) .* f(:,w));
                objExpr = objExpr + pw * inst.unmetPenalty * unmet(w);
            end

            prob = optimproblem('ObjectiveSense', 'minimize');
            prob.Objective = objExpr;

            % === 约束 C1: 流量 ≤ 容量 × 激活 ===
            caps = arrayfun(@(c) c.capacity, inst.corridors);
            for w = 1:nW
                prob.Constraints.(['cap_w' num2str(w)]) = ...
                    f(:,w) <= caps(:) .* x;
            end

            % === 约束 C2: 走廊可行性（内联，避免值类型传参丢失） ===
            %   对每条走廊 e 和其关联终端 t:
            %     x(e) ≤ Σ_k feasCoeff(t,k,e) * z(t,k)
            %   其中 feasCoeff = isCorridorFeasible AND NOT isCorridorBlocked
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

                    cname = sprintf('feas_T%d_E%d', t, e);
                    prob.Constraints.(cname) = ...
                        x(e) <= sum(feasCoeff .* z(zRange));
                end

                zIdx = zIdx + nK;
            end

            % === 约束 C3: 每个终端恰好选一种样式 ===
            zIdx = 0;
            for t = 1:nT
                nK = numel(styleIds{t});
                prob.Constraints.(['oneStyle_T' num2str(t)]) = ...
                    sum(z(zIdx+1 : zIdx+nK)) == 1;
                zIdx = zIdx + nK;
            end

            % === 约束 C4: 需求满足 ===
            for w = 1:nW
                scen = inst.scenarios(w);
                totalDemand = sum(cell2mat(scen.odDemand.values));
                prob.Constraints.(['demand_w' num2str(w)]) = ...
                    sum(f(:,w)) + unmet(w) >= totalDemand;
            end

            obj.prob = prob;
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

            design = uam.core.NetworkDesign(ca, ss, fa, um);
        end
    end
end
