function iface = extractM0(terminal)
    % extractM0 提取 S-only 接口: 聚合标量服务 L̃(Λ) = ā Λ + b̄ Λ²
    arguments
        terminal asf.core.TerminalConfig
    end
    [aBar, bBar] = asf.truth.fitAggregate(terminal);
    iface.terminalId = terminal.terminalId;
    iface.aBar = aBar;
    iface.bBar = bBar;
end
