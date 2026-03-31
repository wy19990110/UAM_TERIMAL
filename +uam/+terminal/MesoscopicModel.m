classdef MesoscopicModel
    % MesoscopicModel 终端区中观模型（排队论参数化版本）
    %
    %   基于排队论计算 (A, μ, D, V, X, C)：
    %     - 容量 μ: min(起降坪吞吐, 等待位约束)
    %     - 延误 D: M/D/c 排队 + 环形等待 + 合流延误，拟合为参数化函数
    %     - 空域脚印 V: 几何计算
    %     - 外部性 X: 噪声和人口暴露
    %     - 接口 A 和规则 C: 从样式配置直接传递

    methods
        function resp = computeResponse(~, styleConfig, ~, ~)
            % computeResponse 从终端样式配置生成完整终端响应
            %
            %   输入:
            %     styleConfig   - TerminalStyleConfig
            %     arrivalRate   - 到达率（用于延误参数拟合采样范围，0 使用默认）
            %     directionDist - 方向分布（预留，当前未使用）
            %
            %   输出:
            %     resp - TerminalResponse

            % μ: 容量计算
            mu = uam.terminal.MesoscopicModel.computeCapacity(styleConfig);

            % D: 延误参数拟合
            [alpha, beta] = uam.terminal.DelayModel.fitDelayParams(styleConfig, mu);

            % V: 空域脚印
            [blocked, radius] = uam.terminal.FootprintCalc.compute(styleConfig);

            % 构建响应
            resp = uam.core.TerminalResponse( ...
                'feasibleCorridors', styleConfig.feasibleCorridors, ...
                'capacity', mu, ...
                'delayAlpha', alpha, ...
                'delayBeta', beta, ...
                'blockedCorridors', blocked, ...
                'footprintRadiusNm', radius, ...
                'noiseIndex', styleConfig.noiseIndex, ...
                'populationExposure', styleConfig.populationExposure, ...
                'acceptedVehicleClasses', styleConfig.acceptedVehicleClasses, ...
                'closureWindThresholdKt', styleConfig.closureWindThresholdKt, ...
                'requiresILS', styleConfig.requiresILS);
        end
    end

    methods (Static)
        function mu = computeCapacity(styleConfig)
            % computeCapacity 计算终端区容量 (ops/hour)
            %
            %   μ = min(起降坪吞吐, 等待位约束吞吐)
            %   起降坪吞吐 = padCount * 3600 / serviceTime
            %   等待位约束 = waitingSlots * 3600 / serviceTime（缓冲限制）

            padThroughput = styleConfig.padCount * 3600 / styleConfig.serviceTime;
            waitThroughput = styleConfig.waitingSlots * 3600 / styleConfig.serviceTime;
            mu = min(padThroughput, waitThroughput);
        end
    end
end
