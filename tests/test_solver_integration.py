"""Integration test: minimal graph, full regret pipeline.

Graph: Source S --E1--> T1(h1, east) --E2--> W1
                \\--E3--> T1(h2, west, blocked footprint on E1)

Terminal T1 has 2 ports:
  h1 (east, cheap service a=0.1, b=0.2)
  h2 (west, expensive service a=0.1, b=1.0)

E1 (east, cheap travel cost=1.0) -> only admissible via h1
E3 (west, expensive travel cost=2.0) -> only admissible via h2

M0 sees only aggregate cost -> may prefer E1 (cheaper travel)
M1 sees port service asymmetry -> may adjust
M* sees everything including cross-port coupling

Key property to verify: regret ≥ 0 for all models.
"""

import pytest
from uam.core.terminal import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc
from uam.core.demand import DemandScenario
from uam.truth.access import build_full_admissibility
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface
from uam.solver import (
    ModelLevel, SolverParams, build_and_solve,
    truth_evaluate, run_regret_experiment,
)


@pytest.fixture
def simple_problem():
    """Build a minimal 2-edge, 1-terminal, 2-port problem."""
    t1 = TerminalConfig(
        "T1", x=0, y=0,
        ports=[
            PortConfig("h1", direction_deg=0, sector_half_width_deg=50, a=0.1, b=0.2),
            PortConfig("h2", direction_deg=180, sector_half_width_deg=50, a=0.1, b=1.0),
        ],
        mu_bar=10.0,
        psi_sat=2.0,
        cross_port_coupling={("h1", "h2"): 0.15},
    )

    base = CandidateGraph(
        terminals={"T1": t1},
        waypoints={"S": (-2.0, 0.0), "W1": (2.0, 0.0), "W2": (-2.0, 0.5)},
        backbone_edges={
            "E1": BackboneEdge("E1", "S", "T1", length=2.0, construction_cost=1.0, travel_cost=1.0, capacity=20),
            "E2": BackboneEdge("E2", "T1", "W1", length=2.0, construction_cost=1.0, travel_cost=1.0, capacity=20),
            "E3": BackboneEdge("E3", "W2", "T1", length=2.0, construction_cost=1.5, travel_cost=2.0, capacity=20),
        },
    )

    # Build admissibility
    adm = build_full_admissibility(base)

    # Build connectors for each admissible (terminal, port, edge) triple
    connectors = {}
    conn_idx = 0
    for (tid, pid, eid), is_adm in adm.items():
        if is_adm:
            conn_idx += 1
            cid = f"C{conn_idx}"
            direction = base.compute_edge_direction(base.backbone_edges[eid], tid)
            connectors[cid] = ConnectorArc(cid, eid, tid, pid, direction, travel_cost=0.05)

    graph = PortAugmentedGraph(base=base, connectors=connectors, admissibility=adm)

    # Simple demand: S -> T1
    scenario = DemandScenario(
        scenario_id="w1",
        od_demand={("S", "T1"): 5.0},
        probability=1.0,
        unmet_penalty=100.0,
    )

    return graph, [scenario], t1


class TestMStarSolve:
    def test_mstar_finds_solution(self, simple_problem):
        graph, scenarios, _ = simple_problem
        design = build_and_solve(
            graph, scenarios, ModelLevel.MSTAR,
            params=SolverParams(verbose=False, mip_gap=0.001),
        )
        assert design.objective < float("inf"), "M* should find a feasible solution"
        assert len(design.active_edges) > 0, "Should activate some edges"

    def test_truth_evaluate_matches(self, simple_problem):
        graph, scenarios, _ = simple_problem
        design = build_and_solve(
            graph, scenarios, ModelLevel.MSTAR,
            params=SolverParams(verbose=False, mip_gap=0.001),
        )
        j_truth, breakdown = truth_evaluate(design, graph, scenarios)
        assert j_truth < float("inf")
        assert breakdown.total == pytest.approx(j_truth, rel=0.01)


class TestRegretNonNegative:
    """The critical property: regret must be ≥ 0 for all models."""

    def test_regret_nonneg(self, simple_problem):
        graph, scenarios, t1 = simple_problem
        m0 = {t1.terminal_id: extract_s_only(t1)}
        m1 = {t1.terminal_id: extract_as_interface(t1, graph.base)}
        m2 = {t1.terminal_id: extract_asf_interface(t1, graph.base)}

        result = run_regret_experiment(
            graph, scenarios,
            levels=[ModelLevel.M0, ModelLevel.M1, ModelLevel.M2],
            m0_interfaces=m0,
            m1_interfaces=m1,
            m2_interfaces=m2,
            params=SolverParams(verbose=False, mip_gap=0.001),
        )

        j_star = result.truth_result.truth_objective
        assert j_star < float("inf"), "M* should be feasible"

        for level, r in result.model_results.items():
            assert r.regret >= -1e-4, (
                f"{level.name} has negative regret {r.regret:.6f}! "
                f"J_truth={r.truth_objective:.4f}, J*={j_star:.4f}"
            )
            print(f"{level.name}: Δ={r.regret:.4f} ({r.relative_regret:.1%}), "
                  f"TD_bb={r.td_backbone:.2f}")

    def test_mstar_regret_zero(self, simple_problem):
        """M* evaluated under M* should have exactly zero regret."""
        graph, scenarios, _ = simple_problem
        design = build_and_solve(
            graph, scenarios, ModelLevel.MSTAR,
            params=SolverParams(verbose=False, mip_gap=0.001),
        )
        j_truth, _ = truth_evaluate(design, graph, scenarios)
        # J^truth(x*) should equal the M* solve objective (up to numerical tolerance)
        assert j_truth == pytest.approx(design.objective, rel=0.05)
