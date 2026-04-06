function iface = extractB1(terminal, inst)
    % extractB1 提取 B1 incumbent 接口: admissibility + aggregate service
    %   有 admissibility（知道哪些 connector 可用），但服务用聚合曲线
    %   （不做 per-port 分解）。代表"terminal-aware 但不完全接口分解"的文献做法。
    arguments
        terminal asf.core.TerminalConfig
        inst asf.core.ProblemInstance
    end
    iface.terminalId = terminal.terminalId;
    iface.adm = asf.truth.accessTruth(inst);
    [aBar, bBar] = asf.truth.fitAggregate(terminal);
    iface.aBar = aBar;
    iface.bBar = bBar;
    iface.level = "B1";
    % portService 用均分的聚合值（让 solveMILP 的 M1 分支能读取）
    iface.portService = struct();
    nP = terminal.numPorts();
    for i = 1:nP
        pid = char(terminal.ports(i).portId);
        iface.portService.(pid).a = aBar / nP;
        iface.portService.(pid).b = bBar / nP;
    end
end
