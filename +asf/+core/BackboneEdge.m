classdef BackboneEdge
    % BackboneEdge 候选主干走廊
    properties
        edgeId      (1,1) string
        nodeU       (1,1) string    % 端点 u
        nodeV       (1,1) string    % 端点 v
        len         (1,1) double = 1
        constructionCost (1,1) double = 1
        travelCost  (1,1) double = 1
        capacity    (1,1) double = 50
    end
    methods
        function obj = BackboneEdge(id, u, v, len, cc, tc, cap)
            arguments
                id (1,1) string; u (1,1) string; v (1,1) string
                len (1,1) double = 1; cc (1,1) double = 1
                tc (1,1) double = 1; cap (1,1) double = 50
            end
            obj.edgeId = id; obj.nodeU = u; obj.nodeV = v;
            obj.len = len; obj.constructionCost = cc;
            obj.travelCost = tc; obj.capacity = cap;
        end
    end
end
