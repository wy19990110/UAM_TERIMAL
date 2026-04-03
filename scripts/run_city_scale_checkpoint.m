% run_city_scale_checkpoint.m
% 带断点续传的城市级参数扫描实验
% 用法: 直接运行或由 .bat 脚本启动

cd('C:\Projects\UAM_NET');
run('startup.m');

savePath = fullfile(pwd, 'results', 'city_scale');
if ~exist(savePath, 'dir'), mkdir(savePath); end

logFile = fullfile(savePath, 'city_scale_log.txt');
checkpointFile = fullfile(savePath, 'city_scale_checkpoint.mat');

flog = fopen(logFile, 'a');
logmsg = @(msg) fprintf(flog, '[%s] %s\n', datestr(now, 'HH:MM:SS'), msg);

logmsg('========== 城市级参数扫描实验（断点续传） ==========');

% 参数网格
nTerminals = 8;
demandLevels = ["low", "medium", "high"];
footprintLevels = ["none", "moderate", "severe"];
seeds = 1:5;

nD = numel(demandLevels);
nF = numel(footprintLevels);
nS = numel(seeds);
totalRuns = nD * nF * nS;

% 加载或初始化 checkpoint
if exist(checkpointFile, 'file')
    cp = load(checkpointFile);
    seedRegretAll = cp.seedRegretAll;  % nD x nF x nS x 3
    seedJstarAll = cp.seedJstarAll;    % nD x nF x nS
    completed = cp.completed;          % nD x nF x nS logical
    logmsg(sprintf('已加载 checkpoint，已完成 %d/%d 轮', sum(completed(:)), totalRuns));
else
    seedRegretAll = NaN(nD, nF, nS, 3);
    seedJstarAll = NaN(nD, nF, nS);
    completed = false(nD, nF, nS);
    logmsg('从头开始运行');
end

levels = [uam.core.AbstractionLevel.A0, ...
          uam.core.AbstractionLevel.A1, ...
          uam.core.AbstractionLevel.A2];

runIdx = 0;
for d = 1:nD
    for fp = 1:nF
        for s = 1:nS
            runIdx = runIdx + 1;

            if completed(d, fp, s)
                msg = sprintf('[%d/%d] demand=%s, footprint=%s, seed=%d ... SKIP (已完成)', ...
                    runIdx, totalRuns, demandLevels(d), footprintLevels(fp), seeds(s));
                logmsg(msg);
                continue;
            end

            msg = sprintf('[%d/%d] demand=%s, footprint=%s, seed=%d ... 开始', ...
                runIdx, totalRuns, demandLevels(d), footprintLevels(fp), seeds(s));
            logmsg(msg);

            try
                inst = uam.experiments.InstanceLibrary.buildCityInstance( ...
                    nTerminals, seeds(s), demandLevels(d), footprintLevels(fp));
                model = uam.terminal.MesoscopicModel();
                framework = uam.regret.RegretFramework( ...
                    inst, model, [1 1], 1.0, 0.1);
                [results, trueResult] = framework.computeRegret(levels);

                seedJstarAll(d, fp, s) = trueResult.objective;
                for lv = 1:3
                    seedRegretAll(d, fp, s, lv) = results(lv).regret;
                end
                completed(d, fp, s) = true;

                msg = sprintf('  完成: J*=%.1f, Δ=[%.1f, %.1f, %.1f]', ...
                    trueResult.objective, results(1).regret, results(2).regret, results(3).regret);
                logmsg(msg);
            catch ME
                msg = sprintf('  ERROR: %s', ME.message);
                logmsg(msg);
                seedRegretAll(d, fp, s, :) = NaN;
                seedJstarAll(d, fp, s) = NaN;
                completed(d, fp, s) = true;  % 标记为已处理（错误也不重跑）
            end

            % 每轮保存 checkpoint
            save(checkpointFile, 'seedRegretAll', 'seedJstarAll', 'completed', ...
                'demandLevels', 'footprintLevels', 'seeds', 'nTerminals');
        end
    end
end

% 汇总结果
logmsg('========== 汇总结果 ==========');

regretA0 = zeros(nD, nF);
regretA1 = zeros(nD, nF);
regretA2 = zeros(nD, nF);
jStar = zeros(nD, nF);

for d = 1:nD
    for fp = 1:nF
        regretA0(d, fp) = nanmean(squeeze(seedRegretAll(d, fp, :, 1)));
        regretA1(d, fp) = nanmean(squeeze(seedRegretAll(d, fp, :, 2)));
        regretA2(d, fp) = nanmean(squeeze(seedRegretAll(d, fp, :, 3)));
        jStar(d, fp) = nanmean(squeeze(seedJstarAll(d, fp, :)));
    end
end

regimeData.regretA0 = regretA0;
regimeData.regretA1 = regretA1;
regimeData.regretA2 = regretA2;
regimeData.jStar = jStar;
regimeData.demandLevels = demandLevels;
regimeData.footprintLevels = footprintLevels;
regimeData.relRegretA0 = regretA0 ./ max(jStar, 1e-6) * 100;
regimeData.relRegretA1 = regretA1 ./ max(jStar, 1e-6) * 100;
regimeData.relRegretA2 = regretA2 ./ max(jStar, 1e-6) * 100;

delta_threshold = 0.01;
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
regimeData.seedRegretAll = seedRegretAll;
regimeData.seedJstarAll = seedJstarAll;

paramGrid.demandLevels = demandLevels;
paramGrid.footprintLevels = footprintLevels;

% 保存最终结果
save(fullfile(savePath, 'city_scale_results.mat'), 'regimeData', 'paramGrid');

% 打印 regime map 到日志
logmsg('');
logmsg('========== Regime Map ==========');
logmsg('最小充分层级（相对 regret < 1%）:');
header = sprintf('%-10s', '');
for fp = 1:nF, header = [header, sprintf('%-12s', footprintLevels(fp))]; end
logmsg(header);
for d = 1:nD
    row = sprintf('%-10s', demandLevels(d));
    for fp = 1:nF, row = [row, sprintf('%-12s', minSufficient(d, fp))]; end
    logmsg(row);
end

logmsg('');
logmsg('相对 Regret A0 (%):');
for d = 1:nD
    row = sprintf('%-10s', demandLevels(d));
    for fp = 1:nF, row = [row, sprintf('%-12.1f', regimeData.relRegretA0(d, fp))]; end
    logmsg(row);
end

logmsg('');
logmsg('相对 Regret A1 (%):');
for d = 1:nD
    row = sprintf('%-10s', demandLevels(d));
    for fp = 1:nF, row = [row, sprintf('%-12.1f', regimeData.relRegretA1(d, fp))]; end
    logmsg(row);
end

logmsg('');
logmsg('========== 实验完成 ==========');
logmsg(sprintf('结果已保存到 %s', savePath));

fclose(flog);
exit;
