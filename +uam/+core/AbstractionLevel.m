classdef AbstractionLevel
    % AbstractionLevel 终端区抽象层级枚举
    %   A0       - 容量抽象 (μ, D)
    %   A1       - 容量 + 接口 (A, μ, D)
    %   A2       - 容量 + 接口 + 空域/外部性 (A, μ, D, V, X)
    %   A2Plus   - 全部 + 资格/关闭规则 (A, μ, D, V, X, C)
    %   Full     - 完整中观模型

    enumeration
        A0
        A1
        A2
        A2Plus
        Full
    end

    methods
        function str = label(obj)
            switch obj
                case uam.core.AbstractionLevel.A0
                    str = 'A0';
                case uam.core.AbstractionLevel.A1
                    str = 'A1';
                case uam.core.AbstractionLevel.A2
                    str = 'A2';
                case uam.core.AbstractionLevel.A2Plus
                    str = 'A2+';
                case uam.core.AbstractionLevel.Full
                    str = 'Full';
            end
        end
    end
end
