classdef A2PlusPlugin < uam.abstraction.TerminalPlugin
    % A2PlusPlugin 全部抽象 — 看 (A, μ, D, V, X, C)
    %
    %   所有方法均查询完整 TerminalResponse，与 FullModelPlugin 行为一致。
    %   区别在于 A2PlusPlugin 使用预计算的 responses，
    %   而 FullModelPlugin 未来可直接调用中观模型实时计算。

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
        extWeights (1,2) double = [1.0, 1.0]
    end

    methods
        function obj = A2PlusPlugin(responses, extWeights)
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

        function tf = isVehicleQualified(obj, terminalId, styleId, vehicleClass)
            resp = obj.getResponse(terminalId, styleId);
            tf = any(resp.acceptedVehicleClasses == vehicleClass);
        end
    end

    methods (Access = protected)
        function resp = getResponse(obj, terminalId, styleId)
            key = uam.core.makeKey(terminalId, styleId);
            resp = obj.responses(key);
        end
    end
end
