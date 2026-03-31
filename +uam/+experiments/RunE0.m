classdef RunE0
    % RunE0 E0 实验运行器：问题存在性验证（A0 vs A1）
    %
    %   目标：证明 A0 可能失败（Δ_A0 > 0），A1 显著降低 regret（Δ_A1 ≈ 0）

    methods (Static)
        function [results, trueResult] = run(savePath)
            % run 运行 E0 实验
            %
            %   输入:
            %     savePath - 可选，结果保存路径（文件夹）
            %
            %   输出:
            %     results    - RegretResult 数组
            %     trueResult - 真值求解结果

            arguments
                savePath (1,1) string = ""
            end

            fprintf('========== E0 实验：问题存在性验证 ==========\n\n');

            % 构建实例
            inst = uam.experiments.InstanceLibrary.buildE0();
            model = uam.terminal.MesoscopicModel();

            fprintf('实例: %d 终端, %d 走廊, %d 场景\n', ...
                inst.numTerminals(), inst.numCorridors(), inst.numScenarios());

            % 运行 regret 框架
            framework = uam.regret.RegretFramework(inst, model);
            levels = [uam.core.AbstractionLevel.A0, ...
                      uam.core.AbstractionLevel.A1];
            [results, trueResult] = framework.computeRegret(levels);

            % 汇总
            fprintf('\n========== E0 结果汇总 ==========\n');
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

            % GO/NO-GO 判断
            fprintf('\n========== GO/NO-GO 判断 ==========\n');
            deltaA0 = results(1).regret;
            deltaA1 = results(2).regret;
            if deltaA0 > 0 && deltaA1 < deltaA0
                fprintf('GO: Δ_A0=%.4f > 0, Δ_A1=%.4f < Δ_A0\n', deltaA0, deltaA1);
                fprintf('→ 容量抽象不够，接口信息有价值。项目继续。\n');
            else
                fprintf('WARNING: Δ_A0=%.4f, Δ_A1=%.4f\n', deltaA0, deltaA1);
                fprintf('→ 需要检查实验设置是否合理。\n');
            end

            % 保存结果
            if savePath ~= ""
                if ~exist(savePath, 'dir')
                    mkdir(savePath);
                end
                save(fullfile(savePath, 'e0_results.mat'), ...
                    'results', 'trueResult', 'inst');
                fprintf('\n结果已保存到 %s\n', savePath);
            end
        end
    end
end
