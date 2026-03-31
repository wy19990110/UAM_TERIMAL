classdef TestCore < matlab.unittest.TestCase
    % TestCore 测试 +uam/+core/ 全部数据类

    methods (Test)
        %% AbstractionLevel
        function testAbstractionLevelEnum(testCase)
            testCase.verifyEqual(uam.core.AbstractionLevel.A0.label(), 'A0');
            testCase.verifyEqual(uam.core.AbstractionLevel.A1.label(), 'A1');
            testCase.verifyEqual(uam.core.AbstractionLevel.A2.label(), 'A2');
            testCase.verifyEqual(uam.core.AbstractionLevel.A2Plus.label(), 'A2+');
            testCase.verifyEqual(uam.core.AbstractionLevel.Full.label(), 'Full');
        end

        %% CandidateCorridor
        function testCorridorConstruction(testCase)
            c = uam.core.CandidateCorridor("N", "T1", "T2", 1.0, ...
                'region', "north", 'capacity', 10);
            testCase.verifyEqual(c.id, "N");
            testCase.verifyEqual(c.origin, "T1");
            testCase.verifyEqual(c.destination, "T2");
            testCase.verifyEqual(c.cost, 1.0);
            testCase.verifyEqual(c.region, "north");
            testCase.verifyEqual(c.capacity, 10);
            testCase.verifyEqual(c.activationCost, 0);
        end

        function testCorridorDefaults(testCase)
            c = uam.core.CandidateCorridor("X", "A", "B", 5.0);
            testCase.verifyEqual(c.capacity, Inf);
            testCase.verifyEqual(c.activationCost, 0);
            testCase.verifyEqual(c.region, "");
        end

        %% DemandScenario
        function testDemandScenario(testCase)
            od = containers.Map({'T1-T2', 'T2-T1'}, {5.0, 3.0});
            ds = uam.core.DemandScenario("w1", od, 0.6);
            testCase.verifyEqual(ds.id, "w1");
            testCase.verifyEqual(ds.probability, 0.6);
            testCase.verifyEqual(ds.getDemand("T1", "T2"), 5.0);
            testCase.verifyEqual(ds.getDemand("T2", "T1"), 3.0);
            testCase.verifyEqual(ds.getDemand("T1", "T3"), 0);  % 不存在的 OD
        end

        %% TerminalStyleConfig
        function testStyleConfig(testCase)
            style = uam.core.TerminalStyleConfig('test_style', ...
                'feasibleCorridors', ["A"; "B"], ...
                'padCount', 3, ...
                'footprintBlock', "C");
            testCase.verifyEqual(style.styleId, "test_style");
            testCase.verifyEqual(style.feasibleCorridors, ["A"; "B"]);
            testCase.verifyEqual(style.padCount, 3);
            testCase.verifyEqual(style.footprintBlock, "C");
        end

        %% TerminalResponse
        function testTerminalResponse(testCase)
            resp = uam.core.TerminalResponse( ...
                'feasibleCorridors', ["N"; "B"], ...
                'capacity', 60, ...
                'delayAlpha', 0.1, ...
                'delayBeta', 1.0, ...
                'blockedCorridors', "S");

            testCase.verifyEqual(resp.capacity, 60);
            testCase.verifyTrue(resp.allowsCorridor("N"));
            testCase.verifyTrue(resp.allowsCorridor("B"));
            testCase.verifyFalse(resp.allowsCorridor("S"));
            testCase.verifyTrue(resp.blocksCorridor("S"));
            testCase.verifyFalse(resp.blocksCorridor("N"));
        end

        function testDelayComputation(testCase)
            resp = uam.core.TerminalResponse( ...
                'capacity', 60, ...
                'delayAlpha', 0.1, ...
                'delayBeta', 1.0);

            % D(30) = 0.1 * (30/(60-30))^1 = 0.1 * 1 = 0.1
            testCase.verifyEqual(resp.computeDelay(30), 0.1, 'AbsTol', 1e-10);

            % D(0) = 0
            testCase.verifyEqual(resp.computeDelay(0), 0, 'AbsTol', 1e-10);

            % D(60) = Inf (at capacity)
            testCase.verifyEqual(resp.computeDelay(60), Inf);

            % D(59) 应该很大
            testCase.verifyGreaterThan(resp.computeDelay(59), 1);
        end

        function testDelayMonotonicity(testCase)
            resp = uam.core.TerminalResponse('capacity', 60, ...
                'delayAlpha', 0.1, 'delayBeta', 1.5);
            rates = 10:10:50;
            delays = arrayfun(@(r) resp.computeDelay(r), rates);
            % 延误应严格单调递增
            testCase.verifyTrue(all(diff(delays) > 0));
        end

        %% NetworkInstance
        function testNetworkInstance(testCase)
            corridors = [
                uam.core.CandidateCorridor("N", "T1", "T2", 1.0)
                uam.core.CandidateCorridor("S", "T1", "T2", 4.0)
            ];
            od = containers.Map({'T1-T2'}, {5.0});
            scenarios = uam.core.DemandScenario("w1", od);

            styles = containers.Map();
            styles('T1') = uam.core.TerminalStyleConfig('s1', 'feasibleCorridors', ["N"; "S"]);
            styles('T2') = uam.core.TerminalStyleConfig('s1', 'feasibleCorridors', ["N"; "S"]);

            inst = uam.core.NetworkInstance(["T1"; "T2"], corridors, scenarios, styles, 100);
            testCase.verifyEqual(inst.numCorridors(), 2);
            testCase.verifyEqual(inst.numTerminals(), 2);
            testCase.verifyEqual(inst.numScenarios(), 1);
            testCase.verifyEqual(inst.corridorIds(), ["N"; "S"]);
        end

        %% NetworkDesign
        function testNetworkDesign(testCase)
            ca = containers.Map({'N', 'S', 'B'}, {true, false, true});
            ss = containers.Map({'T1'}, {'fixed_north'});
            % flowAllocation 现在按场景分层
            w1Flow = containers.Map({'N', 'B'}, {3.0, 2.0});
            fa = containers.Map({'w1'}, {w1Flow});
            unmet = containers.Map({'w1'}, {0});
            design = uam.core.NetworkDesign(ca, ss, fa, unmet);

            active = design.activeCorridors();
            testCase.verifyEqual(numel(active), 2);
            testCase.verifyTrue(any(active == "N"));
            testCase.verifyTrue(any(active == "B"));
            testCase.verifyFalse(any(active == "S"));

            % 测试 getFlow
            testCase.verifyEqual(design.getFlow("w1", "N"), 3.0);
            testCase.verifyEqual(design.getFlow("w1", "B"), 2.0);
            testCase.verifyEqual(design.getFlow("w1", "S"), 0);
            testCase.verifyEqual(design.getFlow("w2", "N"), 0);  % 不存在的场景

            % 测试 getUnmet
            testCase.verifyEqual(design.getUnmet("w1"), 0);
        end

        function testTopologyEquals(testCase)
            ca1 = containers.Map({'N', 'S'}, {true, false});
            ca2 = containers.Map({'N', 'S'}, {true, false});
            ca3 = containers.Map({'N', 'S'}, {false, true});
            ss = containers.Map(); fa = containers.Map();

            d1 = uam.core.NetworkDesign(ca1, ss, fa);
            d2 = uam.core.NetworkDesign(ca2, ss, fa);
            d3 = uam.core.NetworkDesign(ca3, ss, fa);

            testCase.verifyTrue(d1.topologyEquals(d2));
            testCase.verifyFalse(d1.topologyEquals(d3));
        end

        %% RegretResult
        function testRegretResult(testCase)
            rr = uam.core.RegretResult( ...
                'level', uam.core.AbstractionLevel.A0, ...
                'regret', 3.5, ...
                'topologyMatch', false);
            testCase.verifyEqual(rr.level, uam.core.AbstractionLevel.A0);
            testCase.verifyEqual(rr.regret, 3.5);
            testCase.verifyFalse(rr.topologyMatch);
        end
    end
end
