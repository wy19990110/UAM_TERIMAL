classdef FootprintCalc
    % FootprintCalc 终端区空域脚印计算
    %
    %   基于环形半径和进近航路长度计算空域占用。

    methods (Static)
        function [blockedCorridors, radius] = compute(styleConfig, allCorridors)
            % compute 计算空域脚印
            %
            %   输入:
            %     styleConfig  - TerminalStyleConfig
            %     allCorridors - CandidateCorridor 数组（可选，用于几何判断）
            %
            %   输出:
            %     blockedCorridors - 被阻塞的走廊 ID (string 数组)
            %     radius           - 空域脚印半径 (海里)

            arguments
                styleConfig
                allCorridors = []
            end

            radius = styleConfig.ringRadiusNm + styleConfig.approachLengthNm;
            blockedCorridors = styleConfig.footprintBlock;
        end
    end
end
