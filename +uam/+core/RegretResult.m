classdef RegretResult
    % RegretResult Regret 计算结果
    %
    %   属性:
    %     level                    - 抽象层级 (AbstractionLevel)
    %     design                   - 该层级下的最优设计 ŷ_ℓ (NetworkDesign)
    %     objectiveUnderAbstraction - J(ŷ_ℓ; φ^(ℓ)) 在抽象模型下的目标值
    %     objectiveUnderTrue       - J(ŷ_ℓ; M) 在真值模型下的目标值
    %     optimalTrueObjective     - J(y*; M) 真值最优目标值
    %     regret                   - Δ_ℓ = J(ŷ_ℓ; M) - J(y*; M)
    %     topologyMatch            - 走廊激活拓扑是否与真值最优一致

    properties
        level
        design
        objectiveUnderAbstraction (1,1) double = 0
        objectiveUnderTrue        (1,1) double = 0
        optimalTrueObjective      (1,1) double = 0
        regret                    (1,1) double = 0
        topologyMatch             (1,1) logical = false
    end

    methods
        function obj = RegretResult(varargin)
            if nargin == 0, return; end
            p = inputParser;
            addParameter(p, 'level', uam.core.AbstractionLevel.A0);
            addParameter(p, 'design', uam.core.NetworkDesign());
            addParameter(p, 'objectiveUnderAbstraction', 0);
            addParameter(p, 'objectiveUnderTrue', 0);
            addParameter(p, 'optimalTrueObjective', 0);
            addParameter(p, 'regret', 0);
            addParameter(p, 'topologyMatch', false);
            parse(p, varargin{:});

            fields = fieldnames(p.Results);
            for i = 1:numel(fields)
                obj.(fields{i}) = p.Results.(fields{i});
            end
        end
    end
end
