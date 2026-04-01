classdef TerminalResponse
    % TerminalResponse 终端区中观模型输出 R_t = (A, μ, D, V, X, C)
    %
    %   这是全系统的通用数据货币：终端模型产出它，
    %   抽象层级读取它的子集，求解器通过插件查询它。

    properties
        % === 原有属性 ===
        feasibleCorridors      (:,1) string = string.empty   % A_t
        capacity               (1,1) double = 0              % μ_t (ops/hour)
        delayAlpha             (1,1) double = 0.1            % D_t 聚合参数（向后兼容）
        delayBeta              (1,1) double = 1.0
        blockedCorridors       (:,1) string = string.empty   % V_t
        footprintRadiusNm      (1,1) double = 0
        noiseIndex             (1,1) double = 1.0            % X_t
        populationExposure     (1,1) double = 0
        acceptedVehicleClasses (:,1) string = "eVTOL"        % C_t
        closureWindThresholdKt (1,1) double = 30
        requiresILS            (1,1) logical = false

        % === 接口级延误参数 D_{t,h} ===
        interfaceIds           (:,1) string = string.empty   % H_t 接口标识
        interfaceDelayAlpha    (:,1) double = []              % 每接口 alpha_h
        interfaceDelayBeta     (:,1) double = []              % 每接口 beta_h
        interfaceCapMax        (:,1) double = []              % λ̄_{t,h} 接口有效域上界

        % === 接口级外部性 ===
        marginalExtCoeff       (:,1) double = []              % χ_{t,h}
        baseExternality        (1,1) double = 0               % X̄_t 固有外部性

        % === 聚合延误（A0 用）===
        aggDelayAlpha          (1,1) double = 0.1             % D_agg alpha
        aggDelayBeta           (1,1) double = 1.0             % D_agg beta

        % === 无量纲化参考值 ===
        refTotalDelay          (1,1) double = 1.0             % L^ref
        refExternality         (1,1) double = 1.0             % X^ref
    end

    methods
        function obj = TerminalResponse(varargin)
            if nargin == 0, return; end
            p = inputParser;
            % 原有参数
            addParameter(p, 'feasibleCorridors', string.empty);
            addParameter(p, 'capacity', 0);
            addParameter(p, 'delayAlpha', 0.1);
            addParameter(p, 'delayBeta', 1.0);
            addParameter(p, 'blockedCorridors', string.empty);
            addParameter(p, 'footprintRadiusNm', 0);
            addParameter(p, 'noiseIndex', 1.0);
            addParameter(p, 'populationExposure', 0);
            addParameter(p, 'acceptedVehicleClasses', "eVTOL");
            addParameter(p, 'closureWindThresholdKt', 30);
            addParameter(p, 'requiresILS', false);
            % 新增参数
            addParameter(p, 'interfaceIds', string.empty);
            addParameter(p, 'interfaceDelayAlpha', []);
            addParameter(p, 'interfaceDelayBeta', []);
            addParameter(p, 'interfaceCapMax', []);
            addParameter(p, 'marginalExtCoeff', []);
            addParameter(p, 'baseExternality', 0);
            addParameter(p, 'aggDelayAlpha', 0.1);
            addParameter(p, 'aggDelayBeta', 1.0);
            addParameter(p, 'refTotalDelay', 1.0);
            addParameter(p, 'refExternality', 1.0);
            parse(p, varargin{:});

            fields = fieldnames(p.Results);
            for i = 1:numel(fields)
                obj.(fields{i}) = p.Results.(fields{i});
            end
            obj.feasibleCorridors = string(obj.feasibleCorridors);
            obj.blockedCorridors = string(obj.blockedCorridors);
            obj.acceptedVehicleClasses = string(obj.acceptedVehicleClasses);
            if ~isempty(obj.interfaceIds)
                obj.interfaceIds = string(obj.interfaceIds);
            end

            % 如果未提供接口级参数，从聚合参数自动填充
            if isempty(obj.interfaceIds) && ~isempty(obj.feasibleCorridors)
                obj.interfaceIds = obj.feasibleCorridors;
            end
            nH = numel(obj.interfaceIds);
            if isempty(obj.interfaceDelayAlpha) && nH > 0
                obj.interfaceDelayAlpha = repmat(obj.delayAlpha, nH, 1);
                obj.interfaceDelayBeta = repmat(obj.delayBeta, nH, 1);
            end
            if isempty(obj.interfaceCapMax) && nH > 0
                obj.interfaceCapMax = repmat(obj.capacity * 0.9, nH, 1);
            end
            if isempty(obj.marginalExtCoeff) && nH > 0
                obj.marginalExtCoeff = zeros(nH, 1);
            end
        end

        %% 延误计算
        function d = computeDelay(obj, arrivalRate)
            % 聚合延误 D(λ) = alpha * (λ/(μ-λ))^beta（向后兼容）
            if arrivalRate >= obj.capacity || arrivalRate < 0
                d = Inf;
            elseif arrivalRate == 0
                d = 0;
            else
                d = obj.delayAlpha * (arrivalRate / (obj.capacity - arrivalRate))^obj.delayBeta;
            end
        end

        function d = computeDelayAtInterface(obj, hIdx, arrivalRate)
            % 接口 h 的延误 D_{t,h}(λ_{t,h})
            if hIdx < 1 || hIdx > numel(obj.interfaceDelayAlpha)
                d = Inf; return;
            end
            capMax = obj.interfaceCapMax(hIdx);
            if arrivalRate >= capMax || arrivalRate < 0
                d = Inf;
            elseif arrivalRate == 0
                d = 0;
            else
                alpha = obj.interfaceDelayAlpha(hIdx);
                beta = obj.interfaceDelayBeta(hIdx);
                d = alpha * (arrivalRate / (capMax - arrivalRate))^beta;
            end
        end

        function d = computeAggDelay(obj, totalArrivalRate)
            % A0 用的聚合延误 D_agg(λ_total)
            if totalArrivalRate >= obj.capacity || totalArrivalRate < 0
                d = Inf;
            elseif totalArrivalRate == 0
                d = 0;
            else
                d = obj.aggDelayAlpha * (totalArrivalRate / (obj.capacity - totalArrivalRate))^obj.aggDelayBeta;
            end
        end

        %% Ψ_t 计算
        function Lt = computeLtPerInterface(obj, lambdaVec)
            % L_t = Σ_h λ_{t,h} · D_{t,h}(λ_{t,h})
            nH = numel(lambdaVec);
            Lt = 0;
            for h = 1:nH
                d = obj.computeDelayAtInterface(h, lambdaVec(h));
                if isinf(d), Lt = Inf; return; end
                Lt = Lt + lambdaVec(h) * d;
            end
        end

        function Lt = computeLtAggregate(obj, totalArrivalRate)
            % A0 版 L_t = λ_total · D_agg(λ_total)
            d = obj.computeAggDelay(totalArrivalRate);
            Lt = totalArrivalRate * d;
        end

        function [bp, vals] = computePsiBreakpoints(obj, hIdx, numPts)
            % 返回接口 h 的 L_{t,h}(λ) = λ·D_{t,h}(λ) 的分段线性断点
            %   bp   - 负荷断点 (numPts×1)
            %   vals - L_{t,h} 值 (numPts×1)
            arguments
                obj
                hIdx (1,1) double
                numPts (1,1) double = 8
            end
            if hIdx == 0
                % 聚合模式（A0）
                capMax = obj.capacity;
            else
                capMax = obj.interfaceCapMax(hIdx);
            end
            bp = linspace(0, capMax * 0.95, numPts)';
            vals = zeros(numPts, 1);
            for j = 1:numPts
                if hIdx == 0
                    vals(j) = obj.computeLtAggregate(bp(j));
                else
                    d = obj.computeDelayAtInterface(hIdx, bp(j));
                    vals(j) = bp(j) * d;
                end
            end
        end

        %% 兼容性查询
        function tf = allowsCorridor(obj, corridorId)
            tf = any(obj.feasibleCorridors == corridorId);
        end

        function tf = blocksCorridor(obj, corridorId)
            tf = any(obj.blockedCorridors == corridorId);
        end

        function idx = interfaceIndex(obj, corridorId)
            % 返回走廊对应的接口索引
            idx = find(obj.interfaceIds == corridorId, 1);
            if isempty(idx), idx = 0; end
        end
    end
end
