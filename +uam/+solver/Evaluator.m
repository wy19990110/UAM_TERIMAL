classdef Evaluator
    % Evaluator 在指定插件（真值模型）下评估网络设计的目标函数值
    %
    %   J(y; φ) = Σ activationCost(e)*x(e)
    %           + Σ_ω p_ω * [Σ cost(e)*f(e,ω) + penalty*unmet(ω)]
    %           + Σ_ω p_ω * Σ_t externalityCost(t, selectedStyle)

    methods (Static)
        function [J, breakdown] = evaluate(design, plugin, instance)
            % evaluate 计算设计方案在给定插件下的目标函数值
            %
            %   输入:
            %     design   - NetworkDesign
            %     plugin   - TerminalPlugin（通常是 FullModelPlugin）
            %     instance - NetworkInstance
            %
            %   输出:
            %     J         - 总目标函数值
            %     breakdown - struct: routeCost, operationalCost,
            %                         externalityCost, unmetCost, total

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

            % 场景加权运营成本
            operationalCost = 0;
            unmetCost = 0;
            for w = 1:nW
                scen = instance.scenarios(w);
                pw = scen.probability;

                % 流量成本
                for e = 1:nE
                    corr = instance.corridors(e);
                    flow = design.getFlow(scen.id, corr.id);

                    % 检查走廊在选定样式下是否真正可用
                    % 如果不可用但有流量，加巨额惩罚
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
                        % 走廊在真值模型下不可用，流量视为无效，需求转为未满足
                        unmetCost = unmetCost + pw * instance.unmetPenalty * flow;
                    end
                end

                % 未满足需求惩罚
                u = design.getUnmet(scen.id);
                unmetCost = unmetCost + pw * instance.unmetPenalty * u;
            end

            % 外部性成本
            externalityCost = 0;
            for t = 1:instance.numTerminals()
                tid = instance.terminals(t);
                if design.styleSelection.isKey(char(tid))
                    sid = design.styleSelection(char(tid));
                    externalityCost = externalityCost + plugin.getExternalityCost(tid, sid);
                end
            end

            J = routeCost + operationalCost + unmetCost + externalityCost;

            breakdown.routeCost = routeCost;
            breakdown.operationalCost = operationalCost;
            breakdown.externalityCost = externalityCost;
            breakdown.unmetCost = unmetCost;
            breakdown.total = J;
        end
    end
end
