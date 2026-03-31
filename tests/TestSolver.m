classdef TestSolver < matlab.unittest.TestCase
    % TestSolver MIP 求解器和 Evaluator 测试

    methods (Test)
        function testTrivialMIP(testCase)
            % 极简 MIP: 1 终端(T1), 1 走廊(A), 1 场景, 1 样式
            corridors = uam.core.CandidateCorridor("A", "T1", "T1", 2.0, ...
                'capacity', 10);
            od = containers.Map({'T1-T1'}, {3.0});
            scen = uam.core.DemandScenario("w1", od);
            style = uam.core.TerminalStyleConfig('s1', ...
                'feasibleCorridors', "A", 'padCount', 2, 'serviceTime', 120);
            styles = containers.Map({'T1'}, {style});
            inst = uam.core.NetworkInstance("T1", corridors, scen, styles, 100);

            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 0, []);
            responses = containers.Map();
            responses(uam.core.makeKey("T1", "s1")) = resp;

            plugin = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.Full, responses);
            mip = uam.solver.TwoStageMIP(inst, plugin);
            result = mip.solve();

            testCase.verifyEqual(result.status, "optimal");
            testCase.verifyTrue(result.design.corridorActivation('A'));
            testCase.verifyEqual(result.design.getFlow("w1", "A"), 3.0, 'AbsTol', 0.01);
        end

        function testInfeasibleCorridor(testCase)
            % 走廊不可行时应使用 unmet demand
            corridors = uam.core.CandidateCorridor("X", "T1", "T1", 1.0, ...
                'capacity', 10);
            od = containers.Map({'T1-T1'}, {5.0});
            scen = uam.core.DemandScenario("w1", od);
            style = uam.core.TerminalStyleConfig('s1', ...
                'feasibleCorridors', "Y", 'padCount', 2, 'serviceTime', 120);  % 不允许 X
            styles = containers.Map({'T1'}, {style});
            inst = uam.core.NetworkInstance("T1", corridors, scen, styles, 100);

            model = uam.terminal.MesoscopicModel();
            resp = model.computeResponse(style, 0, []);
            responses = containers.Map();
            responses(uam.core.makeKey("T1", "s1")) = resp;

            plugin = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.A1, responses);
            mip = uam.solver.TwoStageMIP(inst, plugin);
            result = mip.solve();

            testCase.verifyEqual(result.status, "optimal");
            % 走廊 X 不可行，全部需求变 unmet
            testCase.verifyEqual(result.design.getUnmet("w1"), 5.0, 'AbsTol', 0.01);
        end

        function testEvaluator(testCase)
            % 手动构建设计并评估
            corridors = uam.core.CandidateCorridor("A", "T1", "T1", 3.0, ...
                'capacity', 10, 'activationCost', 1.0);
            od = containers.Map({'T1-T1'}, {4.0});
            scen = uam.core.DemandScenario("w1", od);
            style = uam.core.TerminalStyleConfig('s1', ...
                'feasibleCorridors', "A", 'padCount', 2, 'serviceTime', 120);
            styles = containers.Map({'T1'}, {style});
            inst = uam.core.NetworkInstance("T1", corridors, scen, styles, 50);

            resp = uam.terminal.MesoscopicModel().computeResponse(style, 0, []);
            responses = containers.Map();
            responses(uam.core.makeKey("T1", "s1")) = resp;
            plugin = uam.abstraction.buildPlugin(uam.core.AbstractionLevel.Full, responses);

            ca = containers.Map({'A'}, {true});
            ss = containers.Map({'T1'}, {'s1'});
            w1f = containers.Map({'A'}, {4.0});
            fa = containers.Map({'w1'}, {w1f});
            um = containers.Map({'w1'}, {0});
            design = uam.core.NetworkDesign(ca, ss, fa, um);

            [J, bd] = uam.solver.Evaluator.evaluate(design, plugin, inst);
            % routeCost = 1.0, operationalCost = 3.0*4.0 = 12.0
            testCase.verifyEqual(bd.routeCost, 1.0, 'AbsTol', 0.01);
            testCase.verifyEqual(bd.operationalCost, 12.0, 'AbsTol', 0.01);
        end
    end
end
