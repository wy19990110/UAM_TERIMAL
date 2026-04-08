function iface = extractM2N(terminal, inst)
    % extractM2N 提取 ASF 接口: M1 + nominal footprint (无 load-sensitivity)
    %   M2N = hard blocks + nominal local penalties
    %   与 extractM2 的区别: 不含 loadSensitivity 字段, solver 不会生成 McCormick 松弛
    %   footprint penalty 重新定标为"平均边 travel cost 的倍数"
    arguments
        terminal asf.core.TerminalConfig
        inst asf.core.ProblemInstance
    end
    iface = asf.interface.extractM1(terminal, inst);

    % Rescale nominal penalty: 以平均边 travel cost 为单位
    ekeys = inst.edges.keys;
    meanTC = mean(arrayfun(@(k) inst.edges(char(k)).travelCost, string(ekeys)));

    fnames = fieldnames(terminal.fpBasePenalty);
    rescaled = struct();
    for i = 1:numel(fnames)
        rescaled.(fnames{i}) = terminal.fpBasePenalty.(fnames{i}) / max(meanTC, 1e-10);
    end
    iface.nominalPenalty = rescaled;

    % Hard blocks
    iface.blockedEdges = terminal.blockedEdges;

    % 注意: 不设置 loadSensitivity —— 这是与 extractM2 的关键区别
end
