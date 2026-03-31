classdef CandidateCorridor
    % CandidateCorridor 候选外部走廊/航路
    %
    %   属性:
    %     id             - 走廊唯一标识 (string)
    %     origin         - 起点终端区 ID (string)
    %     destination    - 终点终端区 ID (string)
    %     cost           - 单位流量运营成本
    %     activationCost - 走廊启用固定成本
    %     region         - 空间区域标签（用于脚印阻塞判断）
    %     capacity       - 走廊容量上界

    properties
        id          (1,1) string
        origin      (1,1) string
        destination (1,1) string
        cost        (1,1) double
        activationCost (1,1) double = 0
        region      (1,1) string = ""
        capacity    (1,1) double = Inf
    end

    methods
        function obj = CandidateCorridor(id, origin, destination, cost, varargin)
            p = inputParser;
            addRequired(p, 'id');
            addRequired(p, 'origin');
            addRequired(p, 'destination');
            addRequired(p, 'cost');
            addParameter(p, 'activationCost', 0);
            addParameter(p, 'region', "");
            addParameter(p, 'capacity', Inf);
            parse(p, id, origin, destination, cost, varargin{:});

            obj.id = string(p.Results.id);
            obj.origin = string(p.Results.origin);
            obj.destination = string(p.Results.destination);
            obj.cost = p.Results.cost;
            obj.activationCost = p.Results.activationCost;
            obj.region = string(p.Results.region);
            obj.capacity = p.Results.capacity;
        end
    end
end
