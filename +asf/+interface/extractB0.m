function iface = extractB0(terminal)
    % extractB0 提取 B0 incumbent 接口: node + aggregate surrogate
    %   与 M0 (S-only) 完全相同的提取逻辑，只是显式标记为文献基线。
    %   代表"文献里把 terminal 当普通节点"的做法。
    arguments
        terminal asf.core.TerminalConfig
    end
    [aBar, bBar] = asf.truth.fitAggregate(terminal);
    iface.terminalId = terminal.terminalId;
    iface.aBar = aBar;
    iface.bBar = bBar;
    iface.level = "B0";
end
