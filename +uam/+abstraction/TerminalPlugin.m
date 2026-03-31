classdef (Abstract) TerminalPlugin < handle
    % TerminalPlugin 终端区抽象接口基类（核心接缝）
    %
    %   所有抽象层级和完整模型都实现此接口。
    %   上层 MIP 求解器只通过此接口查询终端区信息，
    %   不同层级的实现决定了信息可见性。
    %
    %   子类:
    %     A0Plugin      - 仅 (μ, D)
    %     A1Plugin      - (A, μ, D)
    %     A2Plugin      - (A, μ, D, V, X)
    %     A2PlusPlugin  - (A, μ, D, V, X, C)
    %     FullModelPlugin - 完整中观模型

    methods (Abstract)
        % 获取终端容量 μ_t
        mu = getCapacity(obj, terminalId, styleId)

        % 获取延误 D_t(λ)
        d = getDelay(obj, terminalId, styleId, arrivalRate)

        % 走廊是否可连接（A_t 兼容性）
        tf = isCorridorFeasible(obj, terminalId, styleId, corridorId)

        % 走廊是否被空域脚印阻塞（V_t）
        tf = isCorridorBlocked(obj, terminalId, styleId, corridorId)

        % 外部性成本（X_t）
        cost = getExternalityCost(obj, terminalId, styleId)

        % 航空器类别是否被接受（C_t）
        tf = isVehicleQualified(obj, terminalId, styleId, vehicleClass)
    end

    methods
        function [feasVec, blockVec] = getCorridorVectors(obj, terminalId, styleId, corridorIds)
            % getCorridorVectors 批量查询走廊可行性和阻塞状态
            %
            %   输入:
            %     terminalId  - 终端 ID
            %     styleId     - 样式 ID
            %     corridorIds - 走廊 ID 数组 (string)
            %
            %   输出:
            %     feasVec  - logical 向量，是否可连接
            %     blockVec - logical 向量，是否被阻塞
            n = numel(corridorIds);
            feasVec = true(n, 1);
            blockVec = false(n, 1);
            for i = 1:n
                feasVec(i) = obj.isCorridorFeasible(terminalId, styleId, corridorIds(i));
                blockVec(i) = obj.isCorridorBlocked(terminalId, styleId, corridorIds(i));
            end
        end
    end
end
