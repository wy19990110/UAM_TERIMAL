classdef A0Plugin < uam.abstraction.TerminalPlugin
    % A0Plugin 容量抽象 — 仅看 (μ, D)
    %
    %   isCorridorFeasible 恒返回 true（无接口信息）
    %   isCorridorBlocked  恒返回 false（无空域信息）
    %   getExternalityCost 恒返回 0（无外部性信息）
    %   isVehicleQualified 恒返回 true（无资格信息）

    properties (Access = private)
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
    end

    methods
        function obj = A0Plugin(responses)
            % 构造函数
            %   responses: containers.Map, key="terminalId-styleId", value=TerminalResponse
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

        function tf = isCorridorFeasible(~, ~, ~, ~)
            tf = true;  % A0 没有接口信息，所有走廊均视为可行
        end

        function tf = isCorridorBlocked(~, ~, ~, ~)
            tf = false;  % A0 没有空域脚印信息
        end

        function cost = getExternalityCost(~, ~, ~)
            cost = 0;  % A0 没有外部性信息
        end

        function tf = isVehicleQualified(~, ~, ~, ~)
            tf = true;  % A0 没有资格信息
        end
    end

    methods (Access = protected)
        function resp = getResponse(obj, terminalId, styleId)
            key = uam.core.makeKey(terminalId, styleId);
            resp = obj.responses(key);
        end
    end
end
