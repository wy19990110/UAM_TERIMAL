function cost = serviceTruth(terminal, portLoads)
    % serviceTruth 计算 truth 服务成本
    %   L^truth = Σ_h (a_h λ_h + b_h λ_h²)
    %           + Σ_{h<h'} m_{hh'} λ_h λ_{h'}
    %           + ψ [Λ - μ̄]²₊
    %
    %   portLoads: containers.Map "portId" -> load
    arguments
        terminal asf.core.TerminalConfig
        portLoads containers.Map
    end
    cost = 0;
    % 逐端口二次项
    for i = 1:numel(terminal.ports)
        p = terminal.ports(i);
        pid = char(p.portId);
        if portLoads.isKey(pid)
            lam = portLoads(pid);
        else
            lam = 0;
        end
        cost = cost + p.a * lam + p.b * lam^2;
    end
    % 跨端口耦合
    fnames = fieldnames(terminal.coupling);
    for i = 1:numel(fnames)
        fn = fnames{i};
        mval = terminal.coupling.(fn);
        parts = split(fn, '_');
        lam_i = 0; lam_j = 0;
        if portLoads.isKey(parts{1}), lam_i = portLoads(parts{1}); end
        if portLoads.isKey(parts{2}), lam_j = portLoads(parts{2}); end
        cost = cost + mval * lam_i * lam_j;
    end
    % 饱和惩罚
    totalLoad = 0;
    for i = 1:numel(terminal.ports)
        pid = char(terminal.ports(i).portId);
        if portLoads.isKey(pid), totalLoad = totalLoad + portLoads(pid); end
    end
    excess = max(0, totalLoad - terminal.muBar);
    cost = cost + terminal.psiSat * excess^2;
end
