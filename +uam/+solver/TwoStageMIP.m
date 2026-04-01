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
            % 内联构建（optimproblem 是值类型，不能通过子方法修改）
            for t = 1:nT
                tid = inst.terminals(t);
                sid = styleIds{t}(1);

                [bpData, valData, isPerInterface] = ...
                    obj.plugin.getPsiBreakpoints(tid, sid, obj.eta, obj.xi, obj.numPwlPts);
                mu_t = obj.plugin.getCapacity(tid, sid);

                % 预收集该终端关联的走廊索引
                corrIdxAll = [];
                for e = 1:nE
                    corr = inst.corridors(e);
                    if corr.origin == tid || corr.destination == tid
                        corrIdxAll(end+1) = e; %#ok<AGROW>
                    end
                end

                if ~isPerInterface
                    % === A0: 总负荷一元模式 ===
                    for w = 1:nW
                        % 总负荷表达式（用索引直接构建，不用 optimexpr(0) 累加）
                        if isempty(corrIdxAll)
                            prob.Constraints.(sprintf('psiZero_T%d_w%d', t, w)) = psi(t,w) == 0;
                            continue;
                        end
                        loadExpr = sum(f(corrIdxAll, w));

                        prob.Constraints.(sprintf('capTotal_T%d_w%d', t, w)) = loadExpr <= mu_t;

                        bp = bpData; vals = valData;
                        m = numel(bp);
                        if m < 2
                            prob.Constraints.(sprintf('psiZero_T%d_w%d', t, w)) = psi(t,w) == 0;
                            continue;
                        end

                        segW = diff(bp); segS = diff(vals) ./ max(segW, 1e-12);
                        nSeg = m - 1;
                        delta = optimvar(sprintf('dA0_T%d_w%d', t, w), nSeg, 1, 'LowerBound', 0);
                        ybin = optimvar(sprintf('yA0_T%d_w%d', t, w), nSeg, 1, ...
                            'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);

                        for j = 1:nSeg
                            prob.Constraints.(sprintf('dBnd_T%d_w%d_j%d', t, w, j)) = delta(j) <= segW(j) * ybin(j);
                        end
                        for j = 1:nSeg-1
                            prob.Constraints.(sprintf('yOrd_T%d_w%d_j%d', t, w, j)) = ybin(j) >= ybin(j+1);
                        end
                        prob.Constraints.(sprintf('ldLnk_T%d_w%d', t, w)) = loadExpr == bp(1) + sum(delta);
                        prob.Constraints.(sprintf('psiLnk_T%d_w%d', t, w)) = psi(t,w) == vals(1) + sum(segS(:) .* delta);
                    end
                else
                    % === A1/A2/Full: 按接口分解 ===
                    resp = obj.plugin.getResponse(tid, sid);
                    nH = numel(resp.interfaceIds);

                    % 预收集每接口关联的走廊索引
                    corrIdxPerH = cell(nH, 1);
                    for h = 1:nH
                        hId = resp.interfaceIds(h);
                        corrIdxPerH{h} = [];
                        for e = 1:nE
                            corr = inst.corridors(e);
                            if (corr.origin == tid || corr.destination == tid) && corr.id == hId
                                corrIdxPerH{h}(end+1) = e;
                            end
                        end
                    end

                    for w = 1:nW
                        % 收集所有接口的 psi 贡献（用数组索引而非 optimexpr 累加）
                        psiParts = {};  % cell array of optimization expressions

                        for h = 1:nH
                            bp = bpData{h}; vals = valData{h};

                            % C5: 接口负荷 = 走廊流量
                            hIdx = corrIdxPerH{h};
                            if isempty(hIdx)
                                loadExpr = 0;
                            else
                                loadExpr = sum(f(hIdx, w));
                            end

                            % C6b: 接口有效域（仅当有匹配走廊时）
                            capMax = resp.interfaceCapMax(h);
                            if ~isempty(hIdx)
                                prob.Constraints.(sprintf('capIF_T%d_h%d_w%d', t, h, w)) = loadExpr <= capMax;
                            end

                            % C7: 分段线性化
                            m = numel(bp);
                            if m < 2, continue; end

                            segW = diff(bp); segS = diff(vals) ./ max(segW, 1e-12);
                            nSeg = m - 1;
                            delta = optimvar(sprintf('d_T%d_h%d_w%d', t, h, w), nSeg, 1, 'LowerBound', 0);
                            ybin = optimvar(sprintf('y_T%d_h%d_w%d', t, h, w), nSeg, 1, ...
                                'Type', 'integer', 'LowerBound', 0, 'UpperBound', 1);

                            for j = 1:nSeg
                                prob.Constraints.(sprintf('dBnd_T%d_h%d_w%d_j%d', t, h, w, j)) = delta(j) <= segW(j) * ybin(j);
                            end
                            for j = 1:nSeg-1
                                prob.Constraints.(sprintf('yOrd_T%d_h%d_w%d_j%d', t, h, w, j)) = ybin(j) >= ybin(j+1);
                            end
                            if ~isempty(hIdx)
                                prob.Constraints.(sprintf('ldLnk_T%d_h%d_w%d', t, h, w)) = loadExpr == bp(1) + sum(delta);
                            else
                                % 无匹配走廊：强制 delta=0
                                prob.Constraints.(sprintf('ldLnk_T%d_h%d_w%d', t, h, w)) = sum(delta) == 0;
                            end
                            psiParts{end+1} = vals(1) + sum(segS(:) .* delta); %#ok<AGROW>
                        end

                        % C6a: 总容量（用预收集的索引）
                        if ~isempty(corrIdxAll)
                            prob.Constraints.(sprintf('capTotal_T%d_w%d', t, w)) = sum(f(corrIdxAll, w)) <= mu_t;
                        end

                        % 基础外部性常数项
                        baseExtCost = 0;
                        if obj.xi > 0
                            baseExtCost = obj.xi * resp.baseExternality / resp.refExternality;
                        end
                        % 汇总 psi: 用 sum 而非 optimexpr 累加
                        if isempty(psiParts)
                            prob.Constraints.(sprintf('psiLnk_T%d_w%d', t, w)) = psi(t,w) == baseExtCost;
                        else
                            totalPsi = psiParts{1};
                            for pp = 2:numel(psiParts)
                                totalPsi = totalPsi + psiParts{pp};
                            end
                            prob.Constraints.(sprintf('psiLnk_T%d_w%d', t, w)) = psi(t,w) == totalPsi + baseExtCost;
                        end
                    end
                end
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
