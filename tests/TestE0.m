classdef TestE0 < matlab.unittest.TestCase
    % TestE0 E0 实验烟雾测试

    methods (Test)
        function testE0ProducesRegret(testCase)
            % E0 核心断言：Δ_A0 > 0 且 Δ_A1 ≈ 0
            [results, trueResult] = uam.experiments.RunE0.run();

            testCase.verifyEqual(trueResult.status, "optimal");
            testCase.verifyGreaterThan(results(1).regret, 0, ...
                'A0 should have positive regret');
            testCase.verifyEqual(results(2).regret, 0, 'AbsTol', 1e-6, ...
                'A1 should have near-zero regret');
            testCase.verifyFalse(results(1).topologyMatch, ...
                'A0 topology should differ from optimal');
            testCase.verifyTrue(results(2).topologyMatch, ...
                'A1 topology should match optimal');
        end
    end
end
