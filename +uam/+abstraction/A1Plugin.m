classdef A1Plugin < uam.abstraction.TerminalPlugin
    % A1Plugin 容量 + 接口抽象 — 看 (A, μ, D)
    %
    %   isCorridorFeasible 查询兼容矩阵 A_t
    %   isCorridorBlocked  恒返回 false（无空域信息）
    %   getExternalityCost 恒返回 0（无外部性信息）
    %   isVehicleQualified 恒返回 true（无资格信息）

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
    end

    methods
        function obj = A1Plugin(responses)
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

        function tf = isCorridorBlocked(~, ~, ~, ~)
            tf = false;  % A1 没有空域脚印信息
        end

        function cost = getExternalityCost(~, ~, ~)
            cost = 0;  % A1 没有外部性信息
        end

        function tf = isVehicleQualified(~, ~, ~, ~)
            tf = true;  % A1 没有资格信息
        end

        function [bp, vals, isPerInterface] = getPsiBreakpoints(obj, terminalId, styleId, eta, ~, numPts)
            % A1: 按接口分解 D_{t,h}，ξ=0（无外部性）
            arguments
                obj; terminalId; styleId; eta; ~; numPts = 8
            end
            resp = obj.getResponse(terminalId, styleId);
            nH = numel(resp.interfaceIds);
            bp = cell(nH, 1);
            vals = cell(nH, 1);
            for h = 1:nH
                [bp{h}, Lvals] = resp.computePsiBreakpoints(h, numPts);
                vals{h} = eta * Lvals / resp.refTotalDelay;
            end
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
