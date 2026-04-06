classdef InstanceLibrary
    % InstanceLibrary 实验实例工厂
    %
    %   提供 E0、E1 和城市级实验的标准化实例构建。

    methods (Static)
        function inst = buildE0()
            % buildE0 构建 E0 实验实例：P2 反例的极小实现
            %
            %   关键设计：终端样式是外生固定的，不是决策变量。
            %   T1 固定为 fixed_north (只允许 N, B)
            %   T2 固定为 fixed_south (只允许 S, B)
            %   两种样式有相同的 μ 和 D，仅接口 A 不同。
            %
            %   走廊 N(cost=1) 和 S(cost=4) 各只在一端可行，
            %   只有 B(cost=2.5) 对两端都可行。
            %
            %   真值/A1 最优：走廊 B（唯一两端都可行的），J* = 12.5
            %   A0 盲区：看不见接口限制，选走廊 N（最便宜），但 T2 端不可行
            %             → 真值评估时流量无效 → 巨额惩罚

            terminals = ["T1"; "T2"];

            corridors = [
                uam.core.CandidateCorridor("N", "T1", "T2", 1.0, ...
                    'region', "north", 'capacity', 10, 'activationCost', 0)
                uam.core.CandidateCorridor("S", "T1", "T2", 4.0, ...
                    'region', "south", 'capacity', 10, 'activationCost', 0)
                uam.core.CandidateCorridor("B", "T1", "T2", 2.5, ...
                    'region', "backup", 'capacity', 10, 'activationCost', 0)
            ];

            od = containers.Map({'T1-T2'}, {5.0});
            scenarios = uam.core.DemandScenario("w1", od, 1.0);

            % 关键：每个终端只有一种固定样式（外生给定，非决策变量）
            styleN = uam.terminal.StyleCatalog.fixedNorth(["N"; "B"]);
            styleS = uam.terminal.StyleCatalog.fixedSouth(["S"; "B"]);

            styleOptions = containers.Map();
            styleOptions('T1') = styleN;   % T1 固定 fixed_north
            styleOptions('T2') = styleS;   % T2 固定 fixed_south

            inst = uam.core.NetworkInstance(terminals, corridors, scenarios, ...
                styleOptions, 100);
        end

        function inst = buildE1()
            % buildE1 构建 E1 实验实例：2 终端、3 走廊、2 样式
            %
            %   场景：compact_ring vs wide_ring
            %   两种样式有相同的 (A, μ, D)，仅空域脚印 V 不同
            %   wide_ring 阻塞中心走廊 C

            terminals = ["T1"; "T2"];

            corridors = [
                uam.core.CandidateCorridor("C", "T1", "T2", 1.0, ...
                    'region', "center", 'capacity', 10, 'activationCost', 0)
                uam.core.CandidateCorridor("N", "T1", "T2", 2.0, ...
                    'region', "north", 'capacity', 10, 'activationCost', 0)
                uam.core.CandidateCorridor("S", "T1", "T2", 2.0, ...
                    'region', "south", 'capacity', 10, 'activationCost', 0)
            ];

            od = containers.Map({'T1-T2'}, {5.0});
            scenarios = uam.core.DemandScenario("w1", od, 1.0);

            styleC = uam.terminal.StyleCatalog.compactRing(["C"; "N"; "S"]);
            styleW = uam.terminal.StyleCatalog.wideRing(["C"; "N"; "S"], "C");

            % T1 固定 compact_ring（不阻塞），T2 固定 wide_ring（阻塞 C）
            styleOptions = containers.Map();
            styleOptions('T1') = styleC;
            styleOptions('T2') = styleW;

            inst = uam.core.NetworkInstance(terminals, corridors, scenarios, ...
                styleOptions, 100);
        end
        function inst = buildE0b()
            % buildE0b 渐变 regret 实验：接口级延误差异驱动
            %
            %   单源 S → 单终端 T，两条走廊接两个不同接口
            %   走廊 1 接 h1（高效直线进近，延误低），c1=1.02
            %   走廊 2 接 h2（绕行进近，延误高），c2=1.00
            %   总容量和接口集合相同，仅 D_{T,h1} ≠ D_{T,h2}
            %
            %   A0 只看 D_agg(λ_total)，被 c2 更便宜吸引 → 选走廊 2
            %   A1 看见接口级延误差异 → 选走廊 1（总成本更低）

            terminals = ["S"; "T"];

            corridors = [
                uam.core.CandidateCorridor("H1", "S", "T", 1.02, ...
                    'region', "direct", 'capacity', 30, 'activationCost', 0)
                uam.core.CandidateCorridor("H2", "S", "T", 1.00, ...
                    'region', "detour", 'capacity', 30, 'activationCost', 0)
            ];

            % 高需求：接近接口容量，让延误差异显现
            od = containers.Map({'S-T'}, {20.0});
            scenarios = uam.core.DemandScenario("w1", od, 1.0);

            % 终端 T 的样式：两个接口，不同延误特性
            % h1 (H1走廊): 高效进近，环形半径小，延误低
            % h2 (H2走廊): 绕行进近，环形半径大，延误高
            styleT = uam.core.TerminalStyleConfig('dual_interface', ...
                'feasibleCorridors', ["H1"; "H2"], ...
                'padCount', 2, ...
                'waitingSlots', 4, ...
                'serviceTime', 120, ...
                'ringRadiusNm', 0.5, ...
                'approachLengthNm', 1.0, ...
                'footprintBlock', string.empty, ...
                'noiseIndex', 1.0, ...
                'populationExposure', 0, ...
                'interfaceDirections', ["direct"; "detour"], ...
                'marginalExtCoeff', [0; 0], ...
                'baseExternality', 0);

            % 源节点 S 不限制
            styleS = uam.core.TerminalStyleConfig('source', ...
                'feasibleCorridors', ["H1"; "H2"], ...
                'padCount', 4, 'waitingSlots', 8, 'serviceTime', 60, ...
                'ringRadiusNm', 0.1, 'approachLengthNm', 0.2);

            styleOptions = containers.Map();
            styleOptions('S') = styleS;
            styleOptions('T') = styleT;

            inst = uam.core.NetworkInstance(terminals, corridors, scenarios, ...
                styleOptions, 100);
        end
        function inst = buildCityInstance(nT, seed, demandLevel, footprintLevel)
            % buildCityInstance 参数化城市级实例生成器
            %
            %   输入:
            %     nT             - 终端数量 (8-12)
            %     seed           - 随机种子（可复现）
            %     demandLevel    - 需求强度 ("low", "medium", "high")
            %     footprintLevel - 脚印约束水平 ("none", "moderate", "severe")
            %
            %   输出:
            %     inst - NetworkInstance（多终端、多OD、多走廊）

            arguments
                nT (1,1) double = 8
                seed (1,1) double = 42
                demandLevel (1,1) string = "medium"
                footprintLevel (1,1) string = "moderate"
            end

            rng(seed);

            % === 终端位置（随机二维平面） ===
            posX = rand(nT, 1) * 20;  % 0-20 nm
            posY = rand(nT, 1) * 20;

            terminalIds = arrayfun(@(i) sprintf("T%d", i), (1:nT)', 'UniformOutput', false);
            terminalIds = [terminalIds{:}]';

            % === 走廊生成（距离 < 阈值的终端对） ===
            distThreshold = 15;  % nm
            corridors = uam.core.CandidateCorridor.empty;
            corrIdx = 0;
            for i = 1:nT
                for j = i+1:nT
                    d = sqrt((posX(i)-posX(j))^2 + (posY(i)-posY(j))^2);
                    if d > distThreshold, continue; end

                    corrIdx = corrIdx + 1;
                    cid = sprintf("E%d", corrIdx);
                    % 成本正比于距离 + 小随机扰动
                    cost = d * (0.8 + 0.4 * rand());
                    cap = 20 + randi(30);  % 20-50 ops/hour

                    % 方向标签
                    angle = atan2d(posY(j)-posY(i), posX(j)-posX(i));
                    if angle < 0, angle = angle + 360; end
                    if angle < 45 || angle >= 315
                        region = "east";
                    elseif angle < 135
                        region = "north";
                    elseif angle < 225
                        region = "west";
                    else
                        region = "south";
                    end

                    corridors(end+1) = uam.core.CandidateCorridor(cid, ...
                        terminalIds(i), terminalIds(j), cost, ...
                        'region', region, 'capacity', cap, ...
                        'activationCost', d * 0.5); %#ok<AGROW>
                end
            end

            % === 需求场景（多 OD 对） ===
            switch demandLevel
                case "low",    baseDemand = 3;
                case "medium", baseDemand = 8;
                case "high",   baseDemand = 15;
                otherwise,     baseDemand = 8;
            end

            od = containers.Map();
            for i = 1:nT
                for j = 1:nT
                    if i == j, continue; end
                    if rand() < 0.4  % 40% 的 OD 对有需求
                        key = char(terminalIds(i) + "-" + terminalIds(j));
                        demand = baseDemand * (0.5 + rand());
                        od(key) = demand;
                    end
                end
            end
            scenarios = uam.core.DemandScenario("w1", od, 1.0);

            % === 终端样式分配 ===
            styleOptions = containers.Map();
            for t = 1:nT
                tid = char(terminalIds(t));

                % 收集该终端关联的走廊 ID
                connCorridors = string.empty;
                for e = 1:numel(corridors)
                    if corridors(e).origin == terminalIds(t) || ...
                       corridors(e).destination == terminalIds(t)
                        connCorridors(end+1) = corridors(e).id; %#ok<AGROW>
                    end
                end

                if isempty(connCorridors)
                    connCorridors = "dummy";
                end

                % 根据 footprintLevel 决定是否有脚印阻塞
                nConn = numel(connCorridors);
                switch footprintLevel
                    case "none"
                        blocked = string.empty;
                        ringR = 0.3;
                    case "moderate"
                        % 30% 终端有脚印阻塞（阻塞 1 条走廊）
                        if rand() < 0.3 && nConn > 1
                            blocked = connCorridors(randi(nConn));
                            ringR = 1.0;
                        else
                            blocked = string.empty;
                            ringR = 0.3;
                        end
                    case "severe"
                        % 60% 终端有脚印阻塞（阻塞 1-2 条走廊）
                        if rand() < 0.6 && nConn > 1
                            nBlock = min(2, nConn - 1);
                            idx = randperm(nConn, nBlock);
                            blocked = connCorridors(idx);
                            ringR = 1.5;
                        else
                            blocked = string.empty;
                            ringR = 0.3;
                        end
                    otherwise
                        blocked = string.empty;
                        ringR = 0.3;
                end

                % 接口方向：随机分配 direct/detour
                nH = numel(connCorridors);
                dirs = repmat("direct", nH, 1);
                if nH >= 2
                    % 随机选一些接口为 detour（延误高）
                    nDetour = max(1, round(nH * 0.3));
                    detourIdx = randperm(nH, nDetour);
                    dirs(detourIdx) = "detour";
                end

                % 边际外部性系数
                mec = rand(nH, 1) * 0.5;  % 0-0.5
                baseExt = rand() * 2;      % 0-2

                padCount = 2 + randi(2);   % 2-4
                style = uam.core.TerminalStyleConfig(sprintf("style_T%d", t), ...
                    'feasibleCorridors', connCorridors, ...
                    'padCount', padCount, ...
                    'waitingSlots', padCount * 2, ...
                    'serviceTime', 90 + randi(60), ...  % 90-150 秒
                    'ringRadiusNm', ringR, ...
                    'approachLengthNm', 0.5 + rand(), ...
                    'footprintBlock', blocked, ...
                    'noiseIndex', 0.5 + rand(), ...
                    'populationExposure', randi(50), ...
                    'interfaceDirections', dirs, ...
                    'marginalExtCoeff', mec, ...
                    'baseExternality', baseExt);

                styleOptions(tid) = style;
            end

            inst = uam.core.NetworkInstance(terminalIds, corridors, ...
                scenarios, styleOptions, 100);
        end
    end
end
