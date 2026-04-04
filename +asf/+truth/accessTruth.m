function A = accessTruth(inst, contextState)
    % accessTruth 计算完整 admissibility 矩阵
    %   A = containers.Map: "tid_pid_eid" -> bool
    %   A^truth_{t,h,e} = 1{方向在扇区内} · 1{边未被阻塞}
    %
    %   遍历所有 edge（不仅是 incident edge），以支持 non-incident connector
    arguments
        inst asf.core.ProblemInstance
        contextState (1,1) string = "relaxed"
    end
    A = containers.Map();
    tkeys = inst.terminals.keys;
    ekeys = inst.edges.keys;
    for ti = 1:numel(tkeys)
        tid = tkeys{ti};
        terminal = inst.terminals(tid);
        % 遍历所有 backbone edge（不只是 incident edge）
        for ei = 1:numel(ekeys)
            eid = string(ekeys{ei});
            e = inst.edges(ekeys{ei});
            % 计算从 terminal 看该 edge 的方向
            [tx, ty] = inst.nodePos(tid);
            % 用 edge 两端的中点作为方向参考（non-incident edge 没有直接端点关系）
            [ux, uy] = inst.nodePos(e.nodeU);
            [vx, vy] = inst.nodePos(e.nodeV);
            mx = (ux + vx) / 2; my = (uy + vy) / 2;
            theta = mod(atan2d(my - ty, mx - tx), 360);
            for pi = 1:numel(terminal.ports)
                port = terminal.ports(pi);
                pid = port.portId;
                dirOk = port.admitsDirection(theta);
                notBlocked = ~any(terminal.blockedEdges == eid);
                key = char(tid + "_" + pid + "_" + eid);
                A(key) = dirOk && notBlocked;
            end
        end
    end
end
