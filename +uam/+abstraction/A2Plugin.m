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

        function [bp, vals, isPerInterface] = getPsiBreakpoints(obj, terminalId, styleId, eta, xiVal, numPts)
            % A2: 按接口分解 D_{t,h} + X_t 线性项
            arguments
                obj; terminalId; styleId; eta; xiVal; numPts = 8
            end
            resp = obj.getResponse(terminalId, styleId);
            nH = numel(resp.interfaceIds);
            bp = cell(nH, 1);
            vals = cell(nH, 1);
            for h = 1:nH
                [bp{h}, Lvals] = resp.computePsiBreakpoints(h, numPts);
                % Ψ_h = η·L̃_{t,h} + ξ·χ_{t,h}·λ_{t,h}/X^ref
                chiH = 0;
                if h <= numel(resp.marginalExtCoeff)
                    chiH = resp.marginalExtCoeff(h);
                end
                vals{h} = eta * Lvals / resp.refTotalDelay ...
                         + xiVal * chiH * bp{h} / resp.refExternality;
            end
            % baseExternality 是常数项，在 MIP 中另加
            isPerInterface = true;
        end
    end

    methods (Access = protected)
        function resp = getResponse(obj, terminalId, styleId)
            key = uam.core.makeKey(terminalId, styleId);
            resp = obj.responses(key);
        end
    end
end
