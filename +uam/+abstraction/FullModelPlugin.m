classdef FullModelPlugin < uam.abstraction.TerminalPlugin
    % FullModelPlugin 完整中观模型插件 — 看全部 (A, μ, D, V, X, C)
    %
    %   作为真值基准使用。所有方法都查询完整的 TerminalResponse。

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
        extWeights (1,2) double = [1.0, 1.0]  % [噪声权重, 人口暴露权重]
    end

    methods
        function obj = FullModelPlugin(responses, extWeights)
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

        function [bp, vals, isPerInterface] = getPsiBreakpoints(obj, terminalId, styleId, eta, xiVal, numPts)
            % Full: 同 A2（按接口分解 + X_t），使用高保真预计算值
            arguments
                obj; terminalId; styleId; eta; xiVal; numPts = 8
            end
            resp = obj.getResponse(terminalId, styleId);
            nH = numel(resp.interfaceIds);
            bp = cell(nH, 1);
            vals = cell(nH, 1);
            for h = 1:nH
                [bp{h}, Lvals] = resp.computePsiBreakpoints(h, numPts);
                chiH = 0;
                if h <= numel(resp.marginalExtCoeff)
                    chiH = resp.marginalExtCoeff(h);
                end
                vals{h} = eta * Lvals / resp.refTotalDelay ...
                         + xiVal * chiH * bp{h} / resp.refExternality;
            end
            isPerInterface = true;
        end
    end

    methods
        function resp = getResponse(obj, terminalId, styleId)
            key = uam.core.makeKey(terminalId, styleId);
            resp = obj.responses(key);
        end
    end
end
