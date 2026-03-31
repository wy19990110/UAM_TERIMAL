classdef TestE1 < matlab.unittest.TestCase
    % TestE1 E1 实验烟雾测试

    methods (Test)
        function testE1ProducesRegret(testCase)
            % E1 核心断言：Δ_A1 > 0 且 Δ_A2 < Δ_A1
            [results, trueResult] = uam.experiments.RunE1.run();

            testCase.verifyEqual(trueResult.status, "optimal");

            deltaA0 = results(1).regret;
            deltaA1 = results(2).regret;
            deltaA2 = results(3).regret;

            testCase.verifyGreaterThan(deltaA1, 0, ...
                'A1 should have positive regret (cannot see footprint)');
            testCase.verifyLessThan(deltaA2, deltaA1, ...
                'A2 regret should be less than A1');
            testCase.verifyEqual(deltaA2, 0, 'AbsTol', 1e-6, ...
                'A2 should have near-zero regret');
            testCase.verifyTrue(results(3).topologyMatch, ...
                'A2 topology should match optimal');
        end
    end
end
