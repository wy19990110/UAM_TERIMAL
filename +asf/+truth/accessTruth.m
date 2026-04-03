function A = accessTruth(inst, contextState)
    % accessTruth 计算完整 admissibility 矩阵
    %   A = containers.Map: "tid_pid_eid" -> bool
    %   A^truth_{t,h,e} = 1{方向在扇区内} · 1{边未被阻塞}
    arguments
        inst asf.core.ProblemInstance
        contextState (1,1) string = "relaxed"
    end
    A = containers.Map();
    tkeys = inst.terminals.keys;
    for ti = 1:numel(tkeys)
        tid = tkeys{ti};
        terminal = inst.terminals(tid);
        eids = inst.incidentEdges(tid);
        for ei = 1:numel(eids)
            eid = eids(ei);
            theta = inst.edgeDirection(eid, tid);
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
