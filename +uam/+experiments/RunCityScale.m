classdef RunCityScale
    % RunCityScale 城市级参数扫描实验
    %
    %   扫描 需求强度 × 脚印约束水平 × 随机种子，
    %   计算 A0/A1/A2 的 regret，生成 regime map 数据。

    methods (Static)
        function [regimeData, paramGrid] = run(savePath)
            arguments
                savePath (1,1) string = ""
            end

            fprintf('========== 城市级参数扫描实验 ==========\n\n');

            % 参数网格
            nTerminals = 8;
            demandLevels = ["low", "medium", "high"];
            footprintLevels = ["none", "moderate", "severe"];
            seeds = 1:5;  % 5 个随机种子取平均

            nD = numel(demandLevels);
            nF = numel(footprintLevels);
            nS = numel(seeds);

            % 结果存储
            regretA0 = zeros(nD, nF);
            regretA1 = zeros(nD, nF);
            regretA2 = zeros(nD, nF);
            jStar = zeros(nD, nF);

            levels = [uam.core.AbstractionLevel.A0, ...
                      uam.core.AbstractionLevel.A1, ...
                      uam.core.AbstractionLevel.A2];

            totalRuns = nD * nF * nS;
            runIdx = 0;

            for d = 1:nD
                for fp = 1:nF
                    seedRegrets = zeros(nS, 3);  % [A0, A1, A2] per seed
                    seedJstar = zeros(nS, 1);

                    for s = 1:nS
                        runIdx = runIdx + 1;
                        fprintf('[%d/%d] demand=%s, footprint=%s, seed=%d ... ', ...
                            runIdx, totalRuns, demandLevels(d), footprintLevels(fp), seeds(s));

                        try
                            inst = uam.experiments.InstanceLibrary.buildCityInstance( ...
                                nTerminals, seeds(s), demandLevels(d), footprintLevels(fp));
                            model = uam.terminal.MesoscopicModel();

                            % xi=0.1 对 A2 层级
                            framework = uam.regret.RegretFramework( ...
                                inst, model, [1 1], 1.0, 0.1);

                            [results, trueResult] = framework.computeRegret(levels);

                            seedJstar(s) = trueResult.objective;
                            for lv = 1:3
                                seedRegrets(s, lv) = results(lv).regret;
                            end
                            fprintf('J*=%.1f, Δ=[%.1f, %.1f, %.1f]\n', ...
                                trueResult.objective, results(1).regret, ...
                                results(2).regret, results(3).regret);
                        catch ME
                            fprintf('ERROR: %s\n', ME.message);
                            seedRegrets(s, :) = NaN;
                            seedJstar(s) = NaN;
                        end
                    end

                    % 种子平均
                    regretA0(d, fp) = nanmean(seedRegrets(:, 1));
                    regretA1(d, fp) = nanmean(seedRegrets(:, 2));
                    regretA2(d, fp) = nanmean(seedRegrets(:, 3));
                    jStar(d, fp) = nanmean(seedJstar);
                end
            end

            % 构建 regime map 数据
            regimeData.regretA0 = regretA0;
            regimeData.regretA1 = regretA1;
            regimeData.regretA2 = regretA2;
            regimeData.jStar = jStar;
            regimeData.demandLevels = demandLevels;
            regimeData.footprintLevels = footprintLevels;

            % 相对 regret（占 J* 百分比）
            regimeData.relRegretA0 = regretA0 ./ max(jStar, 1e-6) * 100;
            regimeData.relRegretA1 = regretA1 ./ max(jStar, 1e-6) * 100;
            regimeData.relRegretA2 = regretA2 ./ max(jStar, 1e-6) * 100;

            % 最小充分层级判断
            delta_threshold = 0.01;  % 1% 阈值
            minSufficient = strings(nD, nF);
            for d = 1:nD
                for fp = 1:nF
                    relA0 = regimeData.relRegretA0(d, fp);
                    relA1 = regimeData.relRegretA1(d, fp);
                    relA2 = regimeData.relRegretA2(d, fp);
                    if relA0 <= delta_threshold
                        minSufficient(d, fp) = "A0";
                    elseif relA1 <= delta_threshold
                        minSufficient(d, fp) = "A1";
                    elseif relA2 <= delta_threshold
                        minSufficient(d, fp) = "A2";
                    else
                        minSufficient(d, fp) = "A2+";
                    end
                end
            end
            regimeData.minSufficient = minSufficient;

            paramGrid.demandLevels = demandLevels;
            paramGrid.footprintLevels = footprintLevels;

            % 打印 regime map
            fprintf('\n========== Regime Map ==========\n');
            fprintf('最小充分层级（相对 regret < 1%%）:\n');
            fprintf('%-10s', '');
            for fp = 1:nF
                fprintf('%-12s', footprintLevels(fp));
            end
            fprintf('\n');
            for d = 1:nD
                fprintf('%-10s', demandLevels(d));
                for fp = 1:nF
                    fprintf('%-12s', minSufficient(d, fp));
                end
                fprintf('\n');
            end

            fprintf('\n相对 Regret A0 (%%):\n');
            fprintf('%-10s', '');
            for fp = 1:nF, fprintf('%-12s', footprintLevels(fp)); end
            fprintf('\n');
            for d = 1:nD
                fprintf('%-10s', demandLevels(d));
                for fp = 1:nF
                    fprintf('%-12.1f', regimeData.relRegretA0(d, fp));
                end
                fprintf('\n');
            end

            fprintf('\n相对 Regret A1 (%%):\n');
            fprintf('%-10s', '');
            for fp = 1:nF, fprintf('%-12s', footprintLevels(fp)); end
            fprintf('\n');
            for d = 1:nD
                fprintf('%-10s', demandLevels(d));
                for fp = 1:nF
                    fprintf('%-12.1f', regimeData.relRegretA1(d, fp));
                end
                fprintf('\n');
            end

            % 保存
            if savePath ~= ""
                if ~exist(savePath, 'dir'), mkdir(savePath); end
                save(fullfile(savePath, 'city_scale_results.mat'), ...
                    'regimeData', 'paramGrid');
                fprintf('\n结果已保存到 %s\n', savePath);
            end
        end
    end
end
