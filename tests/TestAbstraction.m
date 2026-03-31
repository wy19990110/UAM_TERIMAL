classdef TestAbstraction < matlab.unittest.TestCase
    % TestAbstraction 测试抽象层级插件逻辑

    properties (TestParameter)
    end

    properties
        responses  % containers.Map: "terminalId-styleId" -> TerminalResponse
    end

    methods (TestMethodSetup)
        function setupResponses(testCase)
            % 构建两个终端响应：
            %   T1-fixed_north: 可连接 N,B; 不阻塞任何走廊
            %   T1-fixed_south: 可连接 S,B; 不阻塞任何走廊
            respNorth = uam.core.TerminalResponse( ...
                'feasibleCorridors', ["N"; "B"], ...
                'capacity', 60, ...
                'delayAlpha', 0.1, 'delayBeta', 1.0, ...
                'blockedCorridors', string.empty, ...
                'noiseIndex', 1.0, 'populationExposure', 10);
            respSouth = uam.core.TerminalResponse( ...
                'feasibleCorridors', ["S"; "B"], ...
                'capacity', 60, ...
                'delayAlpha', 0.1, 'delayBeta', 1.0, ...
                'blockedCorridors', "C", ...
                'noiseIndex', 2.0, 'populationExposure', 50);

            testCase.responses = containers.Map();
            testCase.responses(uam.core.makeKey("T1", "fixed_north")) = respNorth;
            testCase.responses(uam.core.makeKey("T1", "fixed_south")) = respSouth;
        end
    end

    methods (Test)
        %% A0Plugin 测试
        function testA0Capacity(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            testCase.verifyEqual(plugin.getCapacity("T1", "fixed_north"), 60);
            testCase.verifyEqual(plugin.getCapacity("T1", "fixed_south"), 60);
        end

        function testA0Delay(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            d = plugin.getDelay("T1", "fixed_north", 30);
            testCase.verifyEqual(d, 0.1, 'AbsTol', 1e-10);
        end

        function testA0AlwaysFeasible(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            % A0 对所有走廊都返回 true，即使它们不在兼容集合里
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "N"));
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "S"));  % 实际不可行，但 A0 看不见
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "X"));  % 不存在的走廊也 true
        end

        function testA0NeverBlocked(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            testCase.verifyFalse(plugin.isCorridorBlocked("T1", "fixed_south", "C"));  % 实际被阻塞，但 A0 看不见
        end

        function testA0ZeroExternality(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            testCase.verifyEqual(plugin.getExternalityCost("T1", "fixed_south"), 0);
        end

        function testA0AlwaysQualified(testCase)
            plugin = uam.abstraction.A0Plugin(testCase.responses);
            testCase.verifyTrue(plugin.isVehicleQualified("T1", "fixed_north", "helicopter"));
        end

        %% A1Plugin 测试
        function testA1Capacity(testCase)
            plugin = uam.abstraction.A1Plugin(testCase.responses);
            testCase.verifyEqual(plugin.getCapacity("T1", "fixed_north"), 60);
        end

        function testA1FeasibilityCheck(testCase)
            plugin = uam.abstraction.A1Plugin(testCase.responses);
            % fixed_north 允许 N 和 B
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "N"));
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "B"));
            testCase.verifyFalse(plugin.isCorridorFeasible("T1", "fixed_north", "S"));  % A1 能看到不可行

            % fixed_south 允许 S 和 B
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_south", "S"));
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_south", "B"));
            testCase.verifyFalse(plugin.isCorridorFeasible("T1", "fixed_south", "N"));  % A1 能看到不可行
        end

        function testA1NeverBlocked(testCase)
            plugin = uam.abstraction.A1Plugin(testCase.responses);
            testCase.verifyFalse(plugin.isCorridorBlocked("T1", "fixed_south", "C"));  % A1 仍看不见阻塞
        end

        function testA1ZeroExternality(testCase)
            plugin = uam.abstraction.A1Plugin(testCase.responses);
            testCase.verifyEqual(plugin.getExternalityCost("T1", "fixed_south"), 0);
        end

        %% FullModelPlugin 测试
        function testFullFeasibility(testCase)
            plugin = uam.abstraction.FullModelPlugin(testCase.responses);
            testCase.verifyTrue(plugin.isCorridorFeasible("T1", "fixed_north", "N"));
            testCase.verifyFalse(plugin.isCorridorFeasible("T1", "fixed_north", "S"));
        end

        function testFullBlocking(testCase)
            plugin = uam.abstraction.FullModelPlugin(testCase.responses);
            testCase.verifyTrue(plugin.isCorridorBlocked("T1", "fixed_south", "C"));
            testCase.verifyFalse(plugin.isCorridorBlocked("T1", "fixed_north", "C"));
        end

        function testFullExternality(testCase)
            plugin = uam.abstraction.FullModelPlugin(testCase.responses);
            % fixed_south: noiseIndex=2.0 + populationExposure=50 = 52
            testCase.verifyEqual(plugin.getExternalityCost("T1", "fixed_south"), 52);
            % fixed_north: 1.0 + 10 = 11
            testCase.verifyEqual(plugin.getExternalityCost("T1", "fixed_north"), 11);
        end

        function testFullVehicleQualification(testCase)
            plugin = uam.abstraction.FullModelPlugin(testCase.responses);
            testCase.verifyTrue(plugin.isVehicleQualified("T1", "fixed_north", "eVTOL"));
            testCase.verifyFalse(plugin.isVehicleQualified("T1", "fixed_north", "helicopter"));
        end

        %% A0 vs A1 关键区别：可行性盲区
        function testA0vsA1FeasibilityGap(testCase)
            a0 = uam.abstraction.A0Plugin(testCase.responses);
            a1 = uam.abstraction.A1Plugin(testCase.responses);

            % 对 fixed_north 样式查询走廊 S：
            % A0 看不见接口限制，返回 true（错误）
            % A1 查到兼容矩阵，返回 false（正确）
            testCase.verifyTrue(a0.isCorridorFeasible("T1", "fixed_north", "S"));
            testCase.verifyFalse(a1.isCorridorFeasible("T1", "fixed_north", "S"));
        end
    end
end
