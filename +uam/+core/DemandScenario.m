classdef DemandScenario
    % DemandScenario 需求场景
    %
    %   属性:
    %     id          - 场景标识 (string)
    %     odDemand    - OD 需求量，containers.Map: "origin-destination" -> demand
    %     probability - 场景概率

    properties
        id          (1,1) string
        odDemand    % containers.Map (string -> double)
        probability (1,1) double = 1.0
    end

    methods
        function obj = DemandScenario(id, odDemand, probability)
            arguments
                id
                odDemand    % containers.Map
                probability (1,1) double = 1.0
            end
            obj.id = string(id);
            obj.odDemand = odDemand;
            obj.probability = probability;
        end

        function d = getDemand(obj, origin, destination)
            % 获取指定 OD 对的需求量
            key = origin + "-" + destination;
            if obj.odDemand.isKey(char(key))
                d = obj.odDemand(char(key));
            else
                d = 0;
            end
        end

        function keys = odPairs(obj)
            % 返回所有 OD 对（string 数组）
            keys = string(obj.odDemand.keys);
        end
    end
end
