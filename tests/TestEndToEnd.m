classdef TestEndToEnd < matlab.unittest.TestCase
    % TestEndToEnd 端到端流程测试
    %   StyleCatalog → MesoscopicModel → TerminalResponse → Plugin → 查询
    %   验证 E0 场景下 A0 和 A1 的关键行为差异

    methods (Test)
        function testE0FullPipeline(testCase)
            % 构建 E0 场景的完整数据流
            model = uam.terminal.MesoscopicModel();

            % 1. 从 StyleCatalog 获取样式
            styleN = uam.terminal.StyleCatalog.fixedNorth();
            styleS = uam.terminal.StyleCatalog.fixedSouth();

            % 2. 通过 MesoscopicModel 生成 TerminalResponse
            respN = model.computeResponse(styleN, 30, []);
            respS = model.computeResponse(styleS, 30, []);

            % 3. 构建 responses Map
            responses = containers.Map();
            responses(uam.core.makeKey("T1", "fixed_north")) = respN;
            responses(uam.core.makeKey("T1", "fixed_south")) = respS;

            % 4. 构建各层级插件
            a0 = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A0, responses);
            a1 = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A1, responses);
            full = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.Full, responses);

            % 5. 验证 A0 盲区：对 fixed_north 查询 S 走廊
            testCase.verifyTrue(a0.isCorridorFeasible("T1", "fixed_north", "S"), ...
                'A0 应看不见接口限制，恒返回 true');
            testCase.verifyFalse(a1.isCorridorFeasible("T1", "fixed_north", "S"), ...
                'A1 应能识别 S 走廊不兼容 fixed_north');
            testCase.verifyFalse(full.isCorridorFeasible("T1", "fixed_north", "S"), ...
                'Full 应与 A1 一致');

            % 6. 验证容量一致
            testCase.verifyEqual(a0.getCapacity("T1", "fixed_north"), ...
                                 a0.getCapacity("T1", "fixed_south"), ...
                'A0 看到的两种样式容量应相同');
        end

        function testE1FullPipeline(testCase)
            % E1 场景：compact_ring vs wide_ring
            model = uam.terminal.MesoscopicModel();

            styleC = uam.terminal.StyleCatalog.compactRing();
            styleW = uam.terminal.StyleCatalog.wideRing();

            respC = model.computeResponse(styleC, 30, []);
            respW = model.computeResponse(styleW, 30, []);

            responses = containers.Map();
            responses(uam.core.makeKey("T1", "compact_ring")) = respC;
            responses(uam.core.makeKey("T1", "wide_ring")) = respW;

            a1 = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A1, responses);
            a2 = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A2, responses);

            % A1 看不见 footprint 阻塞
            testCase.verifyFalse(a1.isCorridorBlocked("T1", "wide_ring", "C"), ...
                'A1 应看不见空域脚印阻塞');

            % A2 能看见 footprint 阻塞
            testCase.verifyTrue(a2.isCorridorBlocked("T1", "wide_ring", "C"), ...
                'A2 应能识别 wide_ring 阻塞走廊 C');

            % compact_ring 在任何层级都不阻塞 C
            testCase.verifyFalse(a2.isCorridorBlocked("T1", "compact_ring", "C"), ...
                'compact_ring 不应阻塞任何走廊');
        end

        function testBatchCorridorVectors(testCase)
            % 测试批量查询接口
            model = uam.terminal.MesoscopicModel();
            styleN = uam.terminal.StyleCatalog.fixedNorth();
            respN = model.computeResponse(styleN, 30, []);

            responses = containers.Map();
            responses(uam.core.makeKey("T1", "fixed_north")) = respN;

            a1 = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A1, responses);

            corridorIds = ["N"; "S"; "B"];
            [feasVec, blockVec] = a1.getCorridorVectors("T1", "fixed_north", corridorIds);

            testCase.verifyEqual(feasVec, [true; false; true]);  % N可行, S不可行, B可行
            testCase.verifyEqual(blockVec, [false; false; false]); % A1 不看阻塞
        end

        function testPluginFactory(testCase)
            % 测试 buildPlugin 工厂函数
            responses = containers.Map();
            resp = uam.core.TerminalResponse('capacity', 60, ...
                'feasibleCorridors', "N", 'blockedCorridors', "C");
            responses(uam.core.makeKey("T1", "s1")) = resp;

            levels = [uam.core.AbstractionLevel.A0, ...
                      uam.core.AbstractionLevel.A1, ...
                      uam.core.AbstractionLevel.A2, ...
                      uam.core.AbstractionLevel.A2Plus, ...
                      uam.core.AbstractionLevel.Full];
            for i = 1:numel(levels)
                plugin = uam.abstraction.buildPlugin(levels(i), responses);
                testCase.verifyTrue(isa(plugin, 'uam.abstraction.TerminalPlugin'));
                testCase.verifyEqual(plugin.getCapacity("T1", "s1"), 60);
            end
        end

        function testMakeKeyConsistency(testCase)
            % 验证 makeKey 在不同输入类型下一致
            k1 = uam.core.makeKey("T1", "fixed_north");
            k2 = uam.core.makeKey('T1', 'fixed_north');
            testCase.verifyEqual(k1, k2);
            testCase.verifyTrue(ischar(k1));
        end
    end
end
