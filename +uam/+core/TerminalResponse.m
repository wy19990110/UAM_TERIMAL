classdef TerminalResponse
    % TerminalResponse 终端区中观模型输出 R_t = (A, μ, D, V, X, C)
    %
    %   这是全系统的通用数据货币：终端模型产出它，
    %   抽象层级读取它的子集，求解器通过插件查询它。
    %
    %   属性:
    %     feasibleCorridors      - A_t: 兼容走廊 ID 集合 (string 数组)
    %     capacity               - μ_t: 容量 (ops/hour)
    %     delayAlpha             - D_t 参数: D(λ) = alpha * (λ/(μ-λ))^beta
    %     delayBeta              - D_t 参数
    %     blockedCorridors       - V_t: 被空域脚印阻塞的走廊 ID (string 数组)
    %     footprintRadiusNm      - V_t: 空域脚印半径 (海里)
    %     noiseIndex             - X_t: 噪声指数
    %     populationExposure     - X_t: 人口暴露度
    %     acceptedVehicleClasses - C_t: 接受的航空器类别 (string 数组)
    %     closureWindThresholdKt - C_t: 关闭风速阈值 (节)
    %     requiresILS            - C_t: 是否需要 ILS

    properties
        feasibleCorridors      (:,1) string = string.empty
        capacity               (1,1) double = 0
        delayAlpha             (1,1) double = 0.1
        delayBeta              (1,1) double = 1.0
        blockedCorridors       (:,1) string = string.empty
        footprintRadiusNm      (1,1) double = 0
        noiseIndex             (1,1) double = 1.0
        populationExposure     (1,1) double = 0
        acceptedVehicleClasses (:,1) string = "eVTOL"
        closureWindThresholdKt (1,1) double = 30
        requiresILS            (1,1) logical = false
    end

    methods
        function obj = TerminalResponse(varargin)
            if nargin == 0, return; end
            p = inputParser;
            addParameter(p, 'feasibleCorridors', string.empty);
            addParameter(p, 'capacity', 0);
            addParameter(p, 'delayAlpha', 0.1);
            addParameter(p, 'delayBeta', 1.0);
            addParameter(p, 'blockedCorridors', string.empty);
            addParameter(p, 'footprintRadiusNm', 0);
            addParameter(p, 'noiseIndex', 1.0);
            addParameter(p, 'populationExposure', 0);
            addParameter(p, 'acceptedVehicleClasses', "eVTOL");
            addParameter(p, 'closureWindThresholdKt', 30);
            addParameter(p, 'requiresILS', false);
            parse(p, varargin{:});

            fields = fieldnames(p.Results);
            for i = 1:numel(fields)
                obj.(fields{i}) = p.Results.(fields{i});
            end
            obj.feasibleCorridors = string(obj.feasibleCorridors);
            obj.blockedCorridors = string(obj.blockedCorridors);
            obj.acceptedVehicleClasses = string(obj.acceptedVehicleClasses);
        end

        function d = computeDelay(obj, arrivalRate)
            % 计算延误 D(λ) = alpha * (λ / (μ - λ))^beta
            if arrivalRate >= obj.capacity
                d = Inf;
            else
                d = obj.delayAlpha * (arrivalRate / (obj.capacity - arrivalRate))^obj.delayBeta;
            end
        end

        function tf = allowsCorridor(obj, corridorId)
            % 检查走廊是否在兼容集合中
            tf = any(obj.feasibleCorridors == corridorId);
        end

        function tf = blocksCorridor(obj, corridorId)
            % 检查走廊是否被空域脚印阻塞
            tf = any(obj.blockedCorridors == corridorId);
        end
    end
end
