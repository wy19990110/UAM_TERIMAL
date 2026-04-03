function iface = extractM1(terminal, inst)
    % extractM1 提取 AS 接口: admissibility + per-port 服务
    arguments
        terminal asf.core.TerminalConfig
        inst asf.core.ProblemInstance
    end
    iface.terminalId = terminal.terminalId;
    % Admissibility
    iface.adm = asf.truth.accessTruth(inst);
    % Per-port service
    iface.portService = struct();
    for i = 1:numel(terminal.ports)
        pid = terminal.ports(i).portId;
        [a, b] = asf.truth.fitPortService(terminal, pid);
        fn = char(pid);
        iface.portService.(fn).a = a;
        iface.portService.(fn).b = b;
    end
end
