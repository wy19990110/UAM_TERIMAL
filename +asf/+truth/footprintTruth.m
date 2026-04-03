function cost = footprintTruth(terminal, inst, activeEdges, portLoads)
    % footprintTruth 计算 truth footprint 成本
    %   X^truth = Σ_{e∈邻域} (π̄_e + Σ_h ρ_{e,h} λ_h) · 1{e active}
    %           + M · Σ_{e∈blocked} 1{e active}
    arguments
        terminal asf.core.TerminalConfig
        inst asf.core.ProblemInstance
        activeEdges (:,1) string
        portLoads containers.Map
    end
    BIG_M = 1e4;
    cost = 0;
    neighborhood = inst.neighborhoodEdges(terminal.terminalId, terminal.fpRadius);
    for i = 1:numel(neighborhood)
        eid = neighborhood(i);
        if ~any(activeEdges == eid), continue; end
        % 基础惩罚
        fn = char(eid);
        fn = strrep(fn, '-', '_');  % struct 字段名安全化
        if isfield(terminal.fpBasePenalty, fn)
            cost = cost + terminal.fpBasePenalty.(fn);
        end
        % 负荷敏感度
        for pi = 1:numel(terminal.ports)
            pid = terminal.ports(pi).portId;
            sfn = char(eid + "_" + pid);
            sfn = strrep(sfn, '-', '_');
            if isfield(terminal.fpLoadSens, sfn)
                lam = 0;
                if portLoads.isKey(char(pid)), lam = portLoads(char(pid)); end
                cost = cost + terminal.fpLoadSens.(sfn) * lam;
            end
        end
    end
    % 硬阻塞
    for i = 1:numel(terminal.blockedEdges)
        if any(activeEdges == terminal.blockedEdges(i))
            cost = cost + BIG_M;
        end
    end
end
