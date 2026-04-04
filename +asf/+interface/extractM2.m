function iface = extractM2(terminal, inst)
    % extractM2 提取 ASF 接口: M1 + nominal footprint
    arguments
        terminal asf.core.TerminalConfig
        inst asf.core.ProblemInstance
    end
    iface = asf.interface.extractM1(terminal, inst);
    % Nominal footprint
    iface.nominalPenalty = terminal.fpBasePenalty;  % struct: edgeId -> π
    iface.blockedEdges = terminal.blockedEdges;     % string array
    iface.loadSensitivity = terminal.fpLoadSens;    % struct: edgeId_portId -> ρ̃
end
