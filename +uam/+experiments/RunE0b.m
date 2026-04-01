classdef RunE0b
    % RunE0b E0b 实验：渐变 regret（接口级延误差异驱动）
    %
    %   证明：即使接口集合和总容量相同，
    %   聚合延误（A0）也不够，接口级延误（A1）才是必要信息。

    methods (Static)
        function [results, trueResult] = run(savePath)
            arguments
                savePath (1,1) string = ""
            end

            fprintf('========== E0b 实验：渐变 regret（接口级延误）==========\n\n');

            inst = uam.experiments.InstanceLibrary.buildE0b();
            model = uam.terminal.MesoscopicModel();

            fprintf('实例: %d 终端, %d 走廊, %d 场景\n', ...
                inst.numTerminals(), inst.numCorridors(), inst.numScenarios());

            % η=1, ξ=0（E0b 不测外部性，只测延误）
            framework = uam.regret.RegretFramework(inst, model, [1 1], 1.0, 0);
            levels = [uam.core.AbstractionLevel.A0, ...
                      uam.core.AbstractionLevel.A1];
            [results, trueResult] = framework.computeRegret(levels);

            % 汇总
            fprintf('\n========== E0b 结果汇总 ==========\n');
            fprintf('真值最优 J* = %.4f\n', trueResult.objective);
            fprintf('%-5s  %-10s  %-10s  %-10s  %-8s\n', ...
                '层级', '抽象目标', '真值评估', 'Regret', '拓扑一致');
            fprintf('%s\n', repmat('-', 1, 50));
            for i = 1:numel(results)
                r = results(i);
                fprintf('%-5s  %-10.4f  %-10.4f  %-10.4f  %-8s\n', ...
                    r.level.label(), r.objectiveUnderAbstraction, ...
                    r.objectiveUnderTrue, r.regret, string(r.topologyMatch));
            end

            % 判断
            fprintf('\n========== 渐变 regret 判断 ==========\n');
            deltaA0 = results(1).regret;
            deltaA1 = results(2).regret;
            if deltaA0 > 1e-4 && deltaA1 < deltaA0
                fprintf('渐变 regret 成立: Δ_A0=%.4f > 0, Δ_A1=%.4f\n', deltaA0, deltaA1);
                fprintf('→ 聚合延误不够，接口级延误信息有价值（渐变机制）。\n');
            else
                fprintf('WARNING: Δ_A0=%.4f, Δ_A1=%.4f\n', deltaA0, deltaA1);
            end

            if savePath ~= ""
                if ~exist(savePath, 'dir'), mkdir(savePath); end
                save(fullfile(savePath, 'e0b_results.mat'), ...
                    'results', 'trueResult', 'inst');
                fprintf('\n结果已保存到 %s\n', savePath);
            end
        end
    end
end
