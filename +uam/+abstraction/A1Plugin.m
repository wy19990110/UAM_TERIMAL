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
    end

    methods (Access = private)
        function resp = getResponse(obj, terminalId, styleId)
            key = char(terminalId + "-" + styleId);
            resp = obj.responses(key);
        end
    end
end
