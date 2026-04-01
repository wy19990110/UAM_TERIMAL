classdef Evaluator
    % Evaluator 在指定插件（真值模型）下评估网络设计的目标函数值
    %
    %   J(y; φ) = F^route(x)
    %           + Σ_ω p_ω [Σ c_e f_e^ω + Σ_t Ψ_t(λ_t; φ_t) + κ·unmet^ω]

    methods (Static)
        function [J, breakdown] = evaluate(design, plugin, instance, eta, xi)
            % evaluate 计算设计方案在给定插件下的目标函数值
            arguments
                design
                plugin
                instance
                eta (1,1) double = 1.0
                xi (1,1) double = 0
            end

            nE = instance.numCorridors();
            nW = instance.numScenarios();

            % 走廊激活成本
            routeCost = 0;
            for e = 1:nE
                corr = instance.corridors(e);
                cid = char(corr.id);
                if design.corridorActivation.isKey(cid) && design.corridorActivation(cid)
                    routeCost = routeCost + corr.activationCost;
                end
            end

            % 场景加权运营成本 + 终端广义成本
            operationalCost = 0;
            unmetCost = 0;
            terminalCost = 0;

            for w = 1:nW
                scen = instance.scenarios(w);
                pw = scen.probability;

                % 走廊流量成本
                for e = 1:nE
                    corr = instance.corridors(e);
                    flow = design.getFlow(scen.id, corr.id);

                    isUsable = true;
                    endpoints = [corr.origin, corr.destination];
                    for ep = endpoints
                        if design.styleSelection.isKey(char(ep))
                            sid = design.styleSelection(char(ep));
                            isFeas = plugin.isCorridorFeasible(ep, sid, corr.id);
                            isBlock = plugin.isCorridorBlocked(ep, sid, corr.id);
                            if ~isFeas || isBlock
                                isUsable = false;
                            end
                        end
                    end

                    if isUsable
                        operationalCost = operationalCost + pw * corr.cost * flow;
                    else
                        unmetCost = unmetCost + pw * instance.unmetPenalty * flow;
                    end
                end

                % 未满足需求惩罚
                u = design.getUnmet(scen.id);
                unmetCost = unmetCost + pw * instance.unmetPenalty * u;

                % 终端广义成本 Ψ_t
                for t = 1:instance.numTerminals()
                    tid = instance.terminals(t);
                    if ~design.styleSelection.isKey(char(tid)), continue; end
                    sid = design.styleSelection(char(tid));
                    resp = plugin.getResponse(tid, sid);

                    % 计算接口级负荷
                    nH = numel(resp.interfaceIds);
                    lambdaVec = zeros(nH, 1);
                    for h = 1:nH
                        hId = resp.interfaceIds(h);
                        for e = 1:nE
                            corr = instance.corridors(e);
                            if (corr.origin == tid || corr.destination == tid) && corr.id == hId
                                lambdaVec(h) = lambdaVec(h) + design.getFlow(scen.id, corr.id);
                            end
                        end
                    end

                    % L_t = Σ_h λ_h · D_{t,h}(λ_h)
                    Lt = resp.computeLtPerInterface(lambdaVec);
                    if isinf(Lt), Lt = instance.unmetPenalty * sum(lambdaVec); end

                    % X_t = X̄_t + Σ_h χ_h · λ_h
                    Xt = resp.baseExternality;
                    for h = 1:nH
                        if h <= numel(resp.marginalExtCoeff)
                            Xt = Xt + resp.marginalExtCoeff(h) * lambdaVec(h);
                        end
                    end

                    psiT = eta * Lt / resp.refTotalDelay + xi * Xt / resp.refExternality;
                    terminalCost = terminalCost + pw * psiT;
                end
            end

            % 旧的外部性成本保留为独立项（向后兼容，xi=0 时为主要外部性来源）
            externalityCost = 0;
            if xi == 0
                for t = 1:instance.numTerminals()
                    tid = instance.terminals(t);
                    if design.styleSelection.isKey(char(tid))
                        sid = design.styleSelection(char(tid));
                        externalityCost = externalityCost + plugin.getExternalityCost(tid, sid);
                    end
                end
            end

            J = routeCost + operationalCost + unmetCost + terminalCost + externalityCost;

            breakdown.routeCost = routeCost;
            breakdown.operationalCost = operationalCost;
            breakdown.terminalCost = terminalCost;
            breakdown.externalityCost = externalityCost;
            breakdown.unmetCost = unmetCost;
            breakdown.total = J;
        end
    end
end
