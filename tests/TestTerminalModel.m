classdef TestTerminalModel < matlab.unittest.TestCase
    % TestTerminalModel 测试终端区中观模型（stub 版本）

    methods (Test)
        function testCapacityComputation(testCase)
            % padCount=2, serviceTime=120 → μ = 2*3600/120 = 60 ops/hour
            style = uam.terminal.StyleCatalog.fixedNorth();
            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 30, []);
            testCase.verifyEqual(resp.capacity, 60, 'AbsTol', 1e-10);
        end

        function testFeasibleCorridorsPassthrough(testCase)
            style = uam.terminal.StyleCatalog.fixedNorth();
            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 30, []);
            testCase.verifyTrue(resp.allowsCorridor("N"));
            testCase.verifyTrue(resp.allowsCorridor("B"));
            testCase.verifyFalse(resp.allowsCorridor("S"));
        end

        function testFootprintPassthrough(testCase)
            style = uam.terminal.StyleCatalog.wideRing();
            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 30, []);
            testCase.verifyTrue(resp.blocksCorridor("C"));
            testCase.verifyFalse(resp.blocksCorridor("N"));
        end

        function testCompactRingNoBlocking(testCase)
            style = uam.terminal.StyleCatalog.compactRing();
            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 30, []);
            testCase.verifyFalse(resp.blocksCorridor("C"));
            testCase.verifyFalse(resp.blocksCorridor("N"));
        end

        function testSameCapacityDifferentStyles(testCase)
            % fixedNorth 和 fixedSouth 应有相同容量
            model = uam.terminal.MesoscopicModel();
            rN = model.computeResponse(uam.terminal.StyleCatalog.fixedNorth(), 30, []);
            rS = model.computeResponse(uam.terminal.StyleCatalog.fixedSouth(), 30, []);
            testCase.verifyEqual(rN.capacity, rS.capacity);
        end

        function testFootprintRadius(testCase)
            style = uam.terminal.StyleCatalog.wideRing();
            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 30, []);
            % wideRing: ringRadius=1.0 + approachLength=1.5 = 2.5
            testCase.verifyEqual(resp.footprintRadiusNm, 2.5, 'AbsTol', 1e-10);
        end
    end
end
