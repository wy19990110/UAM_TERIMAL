classdef NetworkDesign
    % NetworkDesign 网络设计方案 y = (x, z, f)
    %
    %   属性:
    %     corridorActivation - x_e: containers.Map corridorId -> logical
    %     styleSelection     - z_tk: containers.Map terminalId -> styleId
    %     flowAllocation     - containers.Map scenarioId -> containers.Map(corridorId -> flow)
    %     unmetDemand        - containers.Map scenarioId -> unmet (double)，或标量(单场景)

    properties
        corridorActivation   % containers.Map (char -> logical)
        styleSelection       % containers.Map (char -> char)
        flowAllocation       % containers.Map (char -> containers.Map(char -> double))
        unmetDemand          % containers.Map (char -> double) 或标量

        % === 主模型层新增 ===
        terminalLoads          % containers.Map: terminalId -> containers.Map(interfaceId -> load)
        terminalPsiCost        % containers.Map: terminalId -> double (Ψ_t 值)
    end

    methods
        function obj = NetworkDesign(corridorActivation, styleSelection, flowAllocation, unmetDemand)
            arguments
                corridorActivation = containers.Map()
                styleSelection     = containers.Map()
                flowAllocation     = containers.Map()
                unmetDemand        = 0
            end
            obj.corridorActivation = corridorActivation;
            obj.styleSelection = styleSelection;
            obj.flowAllocation = flowAllocation;
            obj.unmetDemand = unmetDemand;
        end

        function ids = activeCorridors(obj)
            % 返回被激活的走廊 ID 列表
            allKeys = string(obj.corridorActivation.keys);
            active = false(size(allKeys));
            for i = 1:numel(allKeys)
                active(i) = obj.corridorActivation(char(allKeys(i)));
            end
            ids = allKeys(active);
        end

        function tf = topologyEquals(obj, other)
            % 比较两个设计的走廊激活拓扑是否相同
            ids1 = sort(obj.activeCorridors());
            ids2 = sort(other.activeCorridors());
            tf = isequal(ids1, ids2);
        end

        function f = getFlow(obj, scenarioId, corridorId)
            % 获取指定场景和走廊的流量
            if isa(obj.flowAllocation, 'containers.Map')
                scenKey = char(scenarioId);
                if obj.flowAllocation.isKey(scenKey)
                    scenFlow = obj.flowAllocation(scenKey);
                    corrKey = char(corridorId);
                    if scenFlow.isKey(corrKey)
                        f = scenFlow(corrKey);
                    else
                        f = 0;
                    end
                else
                    f = 0;
                end
            else
                f = 0;
            end
        end

        function u = getUnmet(obj, scenarioId)
            % 获取指定场景的未满足需求
            if isa(obj.unmetDemand, 'containers.Map')
                key = char(scenarioId);
                if obj.unmetDemand.isKey(key)
                    u = obj.unmetDemand(key);
                else
                    u = 0;
                end
            else
                u = obj.unmetDemand;  % 标量（单场景兼容）
            end
        end
    end
end
