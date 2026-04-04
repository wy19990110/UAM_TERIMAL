classdef ProblemInstance
    % ProblemInstance 完整的 port-augmented 网络设计问题实例
    %
    %   打包：terminals + waypoints + backbone edges + connectors
    %        + admissibility matrix + demand + unmet penalty
    properties
        terminals       % containers.Map: tid -> TerminalConfig
        waypoints       % containers.Map: wid -> [x, y]
        edges           % containers.Map: eid -> BackboneEdge
        connectors      % containers.Map: cid -> ConnectorArc
        admissibility   % containers.Map: "tid_pid_eid" -> bool
        odDemand        % containers.Map: "src-dst" -> demand
        unmetPenalty    (1,1) double = 100
        excitation      struct = struct('E_A',0,'E_S',0,'E_F',0)  % 激发指标
    end

    methods
        function obj = ProblemInstance()
            obj.terminals = containers.Map();
            obj.waypoints = containers.Map();
            obj.edges = containers.Map();
            obj.connectors = containers.Map();
            obj.admissibility = containers.Map();
            obj.odDemand = containers.Map();
        end

        function dir = edgeDirection(obj, edgeId, fromNode)
            % 从 fromNode 看 edge 另一端的方向 (度)
            e = obj.edges(edgeId);
            if e.nodeU == fromNode
                toNode = e.nodeV;
            else
                toNode = e.nodeU;
            end
            [x0, y0] = obj.nodePos(fromNode);
            [x1, y1] = obj.nodePos(toNode);
            dir = mod(atan2d(y1-y0, x1-x0), 360);
        end

        function [x, y] = nodePos(obj, nodeId)
            nid = char(nodeId);
            if obj.terminals.isKey(nid)
                t = obj.terminals(nid);
                x = t.x; y = t.y;
            elseif obj.waypoints.isKey(nid)
                p = obj.waypoints(nid);
                x = p(1); y = p(2);
            else
                error('Node %s not found', nid);
            end
        end

        function eids = incidentEdges(obj, nodeId)
            % 返回与 nodeId 关联的所有 edge IDs
            eids = string.empty;
            keys = obj.edges.keys;
            for i = 1:numel(keys)
                e = obj.edges(keys{i});
                if e.nodeU == nodeId || e.nodeV == nodeId
                    eids(end+1) = e.edgeId; %#ok<AGROW>
                end
            end
        end

        function eids = neighborhoodEdges(obj, terminalId, hops)
            % BFS 找 hops 范围内的边
            arguments
                obj; terminalId (1,1) string; hops (1,1) double = 1
            end
            visited = containers.Map();
            visited(char(terminalId)) = 0;
            queue = {char(terminalId)};
            eids = string.empty;
            while ~isempty(queue)
                node = queue{1}; queue(1) = [];
                d = visited(node);
                if d >= hops, continue; end
                keys = obj.edges.keys;
                for i = 1:numel(keys)
                    e = obj.edges(keys{i});
                    neighbor = "";
                    if char(e.nodeU) == string(node)
                        neighbor = e.nodeV;
                    elseif char(e.nodeV) == string(node)
                        neighbor = e.nodeU;
                    end
                    if neighbor ~= ""
                        eids(end+1) = e.edgeId; %#ok<AGROW>
                        nchar = char(neighbor);
                        if ~visited.isKey(nchar)
                            visited(nchar) = d + 1;
                            queue{end+1} = nchar; %#ok<AGROW>
                        end
                    end
                end
            end
            eids = unique(eids);
        end

        function commodities = getCommodities(obj)
            % 返回 OD 对列表: Nx2 string array
            keys = obj.odDemand.keys;
            commodities = strings(numel(keys), 2);
            for i = 1:numel(keys)
                parts = split(string(keys{i}), '-');
                commodities(i,1) = parts(1);
                commodities(i,2) = parts(2);
            end
        end

        function d = getDemand(obj, src, dst)
            key = char(src + "-" + dst);
            if obj.odDemand.isKey(key)
                d = obj.odDemand(key);
            else
                d = 0;
            end
        end
    end
end
