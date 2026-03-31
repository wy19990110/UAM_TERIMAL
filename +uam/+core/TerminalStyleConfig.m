classdef TerminalStyleConfig
    % TerminalStyleConfig 终端区管理样式配置
    %
    %   属性:
    %     styleId             - 样式唯一标识
    %     feasibleCorridors   - 该样式允许连接的走廊 ID 集合 (string 数组)
    %     padCount            - 起降坪数量
    %     waitingSlots        - 等待位容量
    %     serviceTime         - 单次起降服务时间 (秒)
    %     schedulingPolicy    - 调度策略 ("FCFS" | "PRIORITY")
    %     ringRadiusNm        - 环形等待半径 (海里)
    %     approachLengthNm    - 进近航路长度 (海里)
    %     footprintBlock      - 该样式阻塞的走廊 ID 集合 (string 数组)
    %     noiseIndex          - 噪声指数
    %     populationExposure  - 人口暴露度
    %     acceptedVehicleClasses - 接受的航空器类别 (string 数组)
    %     closureWindThresholdKt - 关闭风速阈值 (节)
    %     requiresILS         - 是否需要 ILS

    properties
        styleId             (1,1) string
        feasibleCorridors   (:,1) string = string.empty
        padCount            (1,1) double = 2
        waitingSlots        (1,1) double = 4
        serviceTime         (1,1) double = 120    % 秒
        schedulingPolicy    (1,1) string = "FCFS"
        ringRadiusNm        (1,1) double = 0.5
        approachLengthNm    (1,1) double = 1.0
        footprintBlock      (:,1) string = string.empty
        noiseIndex          (1,1) double = 1.0
        populationExposure  (1,1) double = 0
        acceptedVehicleClasses (:,1) string = "eVTOL"
        closureWindThresholdKt (1,1) double = 30
        requiresILS         (1,1) logical = false
    end

    methods
        function obj = TerminalStyleConfig(styleId, varargin)
            p = inputParser;
            addRequired(p, 'styleId');
            addParameter(p, 'feasibleCorridors', string.empty);
            addParameter(p, 'padCount', 2);
            addParameter(p, 'waitingSlots', 4);
            addParameter(p, 'serviceTime', 120);
            addParameter(p, 'schedulingPolicy', "FCFS");
            addParameter(p, 'ringRadiusNm', 0.5);
            addParameter(p, 'approachLengthNm', 1.0);
            addParameter(p, 'footprintBlock', string.empty);
            addParameter(p, 'noiseIndex', 1.0);
            addParameter(p, 'populationExposure', 0);
            addParameter(p, 'acceptedVehicleClasses', "eVTOL");
            addParameter(p, 'closureWindThresholdKt', 30);
            addParameter(p, 'requiresILS', false);
            parse(p, styleId, varargin{:});

            fields = fieldnames(p.Results);
            for i = 1:numel(fields)
                obj.(fields{i}) = p.Results.(fields{i});
            end
            obj.styleId = string(obj.styleId);
            obj.feasibleCorridors = string(obj.feasibleCorridors);
            obj.footprintBlock = string(obj.footprintBlock);
            obj.acceptedVehicleClasses = string(obj.acceptedVehicleClasses);
        end
    end
end
