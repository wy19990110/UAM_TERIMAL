classdef FullModelPlugin < uam.abstraction.TerminalPlugin
    % FullModelPlugin 完整中观模型插件 — 看全部 (A, μ, D, V, X, C)
    %
    %   作为真值基准使用。所有方法都查询完整的 TerminalResponse。

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
    end

    methods
        function obj = FullModelPlugin(responses)
            obj.responses = responses;
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
            cost = resp.noiseIndex + resp.populationExposure;
        end

        function tf = isVehicleQualified(obj, terminalId, styleId, vehicleClass)
            resp = obj.getResponse(terminalId, styleId);
            tf = any(resp.acceptedVehicleClasses == vehicleClass);
        end
    end

    methods (Access = private)
        function resp = getResponse(obj, terminalId, styleId)
            key = char(terminalId + "-" + styleId);
            resp = obj.responses(key);
        end
    end
end
