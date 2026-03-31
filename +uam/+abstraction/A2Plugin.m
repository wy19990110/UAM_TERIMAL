classdef A2Plugin < uam.abstraction.TerminalPlugin
    % A2Plugin 容量 + 接口 + 空域/外部性抽象 — 看 (A, μ, D, V, X)
    %
    %   isCorridorFeasible 查询兼容矩阵 A_t
    %   isCorridorBlocked  查询空域脚印 V_t
    %   getExternalityCost 返回实际外部性 X_t
    %   isVehicleQualified 恒返回 true（不看 C_t 资格规则）

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
        extWeights (1,2) double = [1.0, 1.0]  % [噪声权重, 人口暴露权重]
    end

    methods
        function obj = A2Plugin(responses, extWeights)
            arguments
                responses
                extWeights (1,2) double = [1.0, 1.0]
            end
            obj.responses = responses;
            obj.extWeights = extWeights;
        end

        function mu = getCapacity(obj, terminalId, styleId)
            resp = obj.getResponse(terminalId, styleId);
            mu = resp.capacity;
        end

        function d = getDelay(obj, terminalId, styleId, arrivalRate)
            resp = obj.getResponse(terminalId, styleId);
            d = resp.computeDelay(arrivalRate);
        end

        function tf = isCorridorFeasible(obj, terminalId, styleId, corridorId)
            resp = obj.getResponse(terminalId, styleId);
            tf = resp.allowsCorridor(corridorId);
        end

        function tf = isCorridorBlocked(obj, terminalId, styleId, corridorId)
            resp = obj.getResponse(terminalId, styleId);
            tf = resp.blocksCorridor(corridorId);
        end

        function cost = getExternalityCost(obj, terminalId, styleId)
            resp = obj.getResponse(terminalId, styleId);
            cost = obj.extWeights(1) * resp.noiseIndex ...
                 + obj.extWeights(2) * resp.populationExposure;
        end

        function tf = isVehicleQualified(~, ~, ~, ~)
            tf = true;  % A2 不看资格规则
        end
    end

    methods (Access = protected)
        function resp = getResponse(obj, terminalId, styleId)
            key = uam.core.makeKey(terminalId, styleId);
            resp = obj.responses(key);
        end
    end
end
