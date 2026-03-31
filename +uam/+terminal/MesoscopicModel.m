classdef MesoscopicModel
    % MesoscopicModel 终端区中观模型（Phase 1 stub 版本）
    %
    %   Phase 1: 从 TerminalStyleConfig 直接生成硬编码 TerminalResponse
    %   Phase 3: 将替换为排队论参数化计算器

    methods
        function resp = computeResponse(~, styleConfig, ~, ~)
            % computeResponse 从终端样式配置生成终端响应
            %
            %   输入:
            %     styleConfig   - TerminalStyleConfig
            %     arrivalRate   - 到达率 (当前 stub 忽略)
            %     directionDist - 方向分布 (当前 stub 忽略)
            %
            %   输出:
            %     resp - TerminalResponse

            % 容量：基于起降坪数量和服务时间计算
            % μ = padCount * 3600 / serviceTime (ops/hour)
            mu = styleConfig.padCount * 3600 / styleConfig.serviceTime;

            resp = uam.core.TerminalResponse( ...
                'feasibleCorridors', styleConfig.feasibleCorridors, ...
                'capacity', mu, ...
                'delayAlpha', 0.1, ...
                'delayBeta', 1.0, ...
                'blockedCorridors', styleConfig.footprintBlock, ...
                'footprintRadiusNm', styleConfig.ringRadiusNm + styleConfig.approachLengthNm, ...
                'noiseIndex', styleConfig.noiseIndex, ...
                'populationExposure', styleConfig.populationExposure, ...
                'acceptedVehicleClasses', styleConfig.acceptedVehicleClasses, ...
                'closureWindThresholdKt', styleConfig.closureWindThresholdKt, ...
                'requiresILS', styleConfig.requiresILS);
        end
    end
end
