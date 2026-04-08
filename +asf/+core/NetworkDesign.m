classdef NetworkDesign
    % NetworkDesign 网络设计解
    properties
        activeEdges     (:,1) string = string.empty     % 激活的 backbone edge IDs
        activeConns     (:,1) string = string.empty     % 激活的 connector IDs
        portLoads       % containers.Map: "tid_pid" -> load
        unmetDemand     % containers.Map: "src-dst" -> unmet
        objective       (1,1) double = Inf              % 模型内目标值
        truthObjective  (1,1) double = Inf              % truth 评估值
        solveStatus     (1,1) double = 0               % intlinprog exitflag
        mipGap          (1,1) double = NaN             % intlinprog relative gap
    end
    methods
        function obj = NetworkDesign()
            obj.portLoads = containers.Map();
            obj.unmetDemand = containers.Map();
        end
        function td = topologyDistBB(obj, other)
            s1 = obj.activeEdges; s2 = other.activeEdges;
            un = unique([s1; s2]);
            if isempty(un), td = 0; return; end
            inter = intersect(s1, s2);
            td = 1 - numel(inter) / numel(un);
        end
        function td = topologyDistConn(obj, other)
            s1 = obj.activeConns; s2 = other.activeConns;
            un = unique([s1; s2]);
            if isempty(un), td = 0; return; end
            inter = intersect(s1, s2);
            td = 1 - numel(inter) / numel(un);
        end
    end
end
