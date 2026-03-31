classdef RunE1
    % RunE1 E1 实验运行器：抽象层级必要性验证（A1 vs A2）
    %
    %   目标：证明 A1 也可能失败（Δ_A1 > 0），A2 显著降低 regret
    %   机制：wide_ring 的空域脚印阻塞走廊 C，但 A1 看不见

    methods (Static)
        function [results, trueResult] = run(savePath)
            arguments
                savePath (1,1) string = ""
            end

            fprintf('========== E1 实验：抽象层级必要性验证 ==========\n\n');

            inst = uam.experiments.InstanceLibrary.buildE1();
            model = uam.terminal.MesoscopicModel();

            fprintf('实例: %d 终端, %d 走廊, %d 场景\n', ...
                inst.numTerminals(), inst.numCorridors(), inst.numScenarios());

            framework = uam.regret.RegretFramework(inst, model);
            levels = [uam.core.AbstractionLevel.A0, ...
                      uam.core.AbstractionLevel.A1, ...
                      uam.core.AbstractionLevel.A2];
            [results, trueResult] = framework.computeRegret(levels);

            % 汇总
            fprintf('\n========== E1 结果汇总 ==========\n');
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
            fprintf('\n========== 层级必要性判断 ==========\n');
            deltaA1 = results(2).regret;
            deltaA2 = results(3).regret;
            if deltaA1 > 0 && deltaA2 < deltaA1
                fprintf('A2 必要: Δ_A1=%.4f > 0, Δ_A2=%.4f < Δ_A1\n', deltaA1, deltaA2);
                fprintf('→ 接口抽象不够，空域脚印信息有价值。\n');
            elseif deltaA1 <= 1e-6
                fprintf('A1 已充分: Δ_A1=%.4f ≈ 0\n', deltaA1);
                fprintf('→ 此场景下接口信息已足够，不需要 A2。\n');
            else
                fprintf('WARNING: Δ_A1=%.4f, Δ_A2=%.4f\n', deltaA1, deltaA2);
            end

            if savePath ~= ""
                if ~exist(savePath, 'dir'), mkdir(savePath); end
                save(fullfile(savePath, 'e1_results.mat'), ...
                    'results', 'trueResult', 'inst');
                fprintf('\n结果已保存到 %s\n', savePath);
            end
        end
    end
end
