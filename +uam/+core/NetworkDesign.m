classdef NetworkDesign
    % NetworkDesign 网络设计方案 y = (x, z, f)
    %
    %   属性:
    %     corridorActivation   - x_e: containers.Map corridorId -> logical
    %     styleSelection       - z_tk: containers.Map terminalId -> styleId
    %     flowAllocation       - f: containers.Map corridorId -> flow (double)
    %     unmetDemand          - 未满足需求量

    properties
        corridorActivation   % containers.Map (string -> logical)
        styleSelection       % containers.Map (string -> string)
        flowAllocation       % containers.Map (string -> double)
        unmetDemand  (1,1) double = 0
    end

    methods
        function obj = NetworkDesign(corridorActivation, styleSelection, flowAllocation, unmetDemand)
            arguments
                corridorActivation = containers.Map()
                styleSelection     = containers.Map()
                flowAllocation     = containers.Map()
                unmetDemand        (1,1) double = 0
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
    end
end
