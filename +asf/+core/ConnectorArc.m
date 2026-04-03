classdef ConnectorArc
    % ConnectorArc 连接 backbone edge 到 terminal port 的接驳弧
    properties
        arcId       (1,1) string
        edgeId      (1,1) string    % 对应的 backbone edge
        terminalId  (1,1) string
        portId      (1,1) string
        directionDeg (1,1) double = 0
        travelCost  (1,1) double = 0.05
    end
    methods
        function obj = ConnectorArc(id, eid, tid, pid, dir, tc)
            arguments
                id (1,1) string; eid (1,1) string
                tid (1,1) string; pid (1,1) string
                dir (1,1) double = 0; tc (1,1) double = 0.05
            end
            obj.arcId = id; obj.edgeId = eid;
            obj.terminalId = tid; obj.portId = pid;
            obj.directionDeg = dir; obj.travelCost = tc;
        end
    end
end
