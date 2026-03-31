classdef NetworkInstance
    % NetworkInstance 完整网络设计问题实例
    %
    %   属性:
    %     terminals        - 终端区 ID 列表 (string 数组)
    %     corridors        - 候选走廊数组 (CandidateCorridor 数组)
    %     scenarios        - 需求场景数组 (DemandScenario 数组)
    %     styleOptions     - 各终端可用样式, containers.Map: terminalId -> TerminalStyleConfig 数组
    %     unmetPenalty     - 未满足需求惩罚系数

    properties
        terminals    (:,1) string
        corridors    (:,1) % CandidateCorridor 数组
        scenarios    (:,1) % DemandScenario 数组
        styleOptions       % containers.Map: string -> TerminalStyleConfig 数组
        unmetPenalty (1,1) double = 100
    end

    methods
        function obj = NetworkInstance(terminals, corridors, scenarios, styleOptions, unmetPenalty)
            arguments
                terminals    (:,1) string
                corridors    (:,1)
                scenarios    (:,1)
                styleOptions
                unmetPenalty (1,1) double = 100
            end
            obj.terminals = terminals;
            obj.corridors = corridors;
            obj.scenarios = scenarios;
            obj.styleOptions = styleOptions;
            obj.unmetPenalty = unmetPenalty;
        end

        function n = numCorridors(obj)
            n = numel(obj.corridors);
        end

        function n = numTerminals(obj)
            n = numel(obj.terminals);
        end

        function n = numScenarios(obj)
            n = numel(obj.scenarios);
        end

        function styles = getStyles(obj, terminalId)
            % 获取指定终端的可用样式列表
            styles = obj.styleOptions(char(terminalId));
        end

        function ids = corridorIds(obj)
            ids = arrayfun(@(c) c.id, obj.corridors);
        end
    end
end
