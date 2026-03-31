function plugin = buildPlugin(level, responses, extWeights)
    % buildPlugin 插件工厂函数
    %
    %   plugin = uam.abstraction.buildPlugin(level, responses)
    %   plugin = uam.abstraction.buildPlugin(level, responses, extWeights)
    %
    %   输入:
    %     level      - uam.core.AbstractionLevel 枚举值
    %     responses  - containers.Map: makeKey(terminalId, styleId) -> TerminalResponse
    %     extWeights - [噪声权重, 人口暴露权重]，默认 [1, 1]
    %
    %   输出:
    %     plugin - TerminalPlugin 子类实例

    arguments
        level      uam.core.AbstractionLevel
        responses  containers.Map
        extWeights (1,2) double = [1.0, 1.0]
    end

    switch level
        case uam.core.AbstractionLevel.A0
            plugin = uam.abstraction.A0Plugin(responses);
        case uam.core.AbstractionLevel.A1
            plugin = uam.abstraction.A1Plugin(responses);
        case uam.core.AbstractionLevel.A2
            plugin = uam.abstraction.A2Plugin(responses, extWeights);
        case uam.core.AbstractionLevel.A2Plus
            plugin = uam.abstraction.A2PlusPlugin(responses, extWeights);
        case uam.core.AbstractionLevel.Full
            plugin = uam.abstraction.FullModelPlugin(responses, extWeights);
        otherwise
            error('uam:abstraction:unknownLevel', '未知抽象层级: %s', char(level));
    end
end
