classdef RegretFramework < handle
    % RegretFramework Regret 计算编排器
    %
    %   对给定的 NetworkInstance 和终端模型：
    %   1. 预计算所有终端响应
    %   2. 在 Full 模型下求解真值最优 y*
    %   3. 在各抽象层级下求解 ŷ_ℓ
    %   4. 在真值模型下评估 ŷ_ℓ 的目标值
    %   5. 计算 Δ_ℓ = J(ŷ_ℓ; M) - J(y*; M)

    properties
        instance        % NetworkInstance
        model           % MesoscopicModel
        extWeights      (1,2) double = [1.0, 1.0]
        eta             (1,1) double = 1.0    % 延误权重
        xi              (1,1) double = 0      % 外部性权重
    end

    methods
        function obj = RegretFramework(instance, model, extWeights, eta, xi)
            arguments
                instance
                model
                extWeights (1,2) double = [1.0, 1.0]
                eta (1,1) double = 1.0
                xi (1,1) double = 0
            end
            obj.instance = instance;
            obj.model = model;
            obj.extWeights = extWeights;
            obj.eta = eta;
            obj.xi = xi;
        end

        function [results, trueResult] = computeRegret(obj, levels)
            % computeRegret 计算各抽象层级的 regret
            %
            %   输入:
            %     levels - AbstractionLevel 数组（不含 Full）
            %
            %   输出:
            %     results    - RegretResult 数组
            %     trueResult - 真值求解结果 struct

            % 1. 预计算所有终端响应
            responses = obj.precomputeResponses();

            % 2. 真值求解
            fullPlugin = uam.abstraction.buildPlugin( ...
                uam.core.AbstractionLevel.Full, responses, obj.extWeights);
            trueMIP = uam.solver.TwoStageMIP(obj.instance, fullPlugin, obj.eta, obj.xi);
            trueSol = trueMIP.solve();

            [jStar, trueBreakdown] = uam.solver.Evaluator.evaluate( ...
                trueSol.design, fullPlugin, obj.instance);

            trueResult.design = trueSol.design;
            trueResult.objective = jStar;
            trueResult.breakdown = trueBreakdown;
            trueResult.status = trueSol.status;

            fprintf('真值最优: J* = %.4f (状态: %s)\n', jStar, trueSol.status);
            fprintf('  激活走廊: %s\n', strjoin(trueSol.design.activeCorridors(), ', '));

            % 3. 各抽象层级求解 + 评估
            results = uam.core.RegretResult.empty;
            for i = 1:numel(levels)
                lv = levels(i);
                fprintf('\n--- %s 层级 ---\n', lv.label());

                plugin = uam.abstraction.buildPlugin(lv, responses, obj.extWeights);
                absMIP = uam.solver.TwoStageMIP(obj.instance, plugin, obj.eta, obj.xi);
                absSol = absMIP.solve();

                % 在抽象模型下的目标值
                [jAbstract, ~] = uam.solver.Evaluator.evaluate( ...
                    absSol.design, plugin, obj.instance);

                % 在真值模型下评估抽象设计
                [jTrue, ~] = uam.solver.Evaluator.evaluate( ...
                    absSol.design, fullPlugin, obj.instance);

                delta = jTrue - jStar;
                topoMatch = trueSol.design.topologyEquals(absSol.design);

                fprintf('  抽象目标: %.4f\n', jAbstract);
                fprintf('  真值评估: %.4f\n', jTrue);
                fprintf('  Regret Δ: %.4f\n', delta);
                fprintf('  拓扑一致: %s\n', string(topoMatch));
                fprintf('  激活走廊: %s\n', strjoin(absSol.design.activeCorridors(), ', '));

                results(end+1) = uam.core.RegretResult( ...
                    'level', lv, ...
                    'design', absSol.design, ...
                    'objectiveUnderAbstraction', jAbstract, ...
                    'objectiveUnderTrue', jTrue, ...
                    'optimalTrueObjective', jStar, ...
                    'regret', delta, ...
                    'topologyMatch', topoMatch); %#ok<AGROW>
            end
        end
    end

    methods (Access = private)
        function responses = precomputeResponses(obj)
            % 为所有 (终端, 样式) 对预计算 TerminalResponse
            responses = containers.Map();
            inst = obj.instance;
            for t = 1:inst.numTerminals()
                tid = inst.terminals(t);
                styles = inst.getStyles(tid);
                if iscell(styles)
                    styles = [styles{:}];
                end
                for k = 1:numel(styles)
                    style = styles(k);
                    resp = obj.model.computeResponse(style, 0, []);
                    key = uam.core.makeKey(tid, style.styleId);
                    responses(key) = resp;
                end
            end
        end
    end
end
