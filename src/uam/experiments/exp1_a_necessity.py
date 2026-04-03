"""EXP-1: A 的必要性 — 证明 S-only 会选错连接边。

Scenario A (hard-cut): Terminal has narrow sectors. M0 doesn't see admissibility,
picks a cheap edge whose connector is truth-infeasible → flow is forced to unmet.

Scenario B (soft): Admissibility constrains flow distribution across ports with
different service costs. M0 picks based on aggregate → suboptimal.
"""

from __future__ import annotations

from uam.core.terminal import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc
from uam.core.demand import DemandScenario
from uam.truth.access import build_full_admissibility
from uam.interface import extract_s_only, extract_as_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


def build_hard_cut_instance(demand: float = 5.0):
    """Hard-cut: T has 1 port facing east. 2 edges: E_east (cheap, admissible) and E_north (cheaper, NOT admissible).

    M0 picks E_north (cheapest travel). Truth: E_north has no admissible connector → unmet → big penalty.
    M1 sees admissibility → picks E_east.
    """
    t = TerminalConfig(
        "T", x=0, y=0,
        ports=[PortConfig("h1", direction_deg=0, sector_half_width_deg=40, a=0.1, b=0.3)],
        mu_bar=20.0, psi_sat=2.0,
    )

    # Key insight: M0 has no admissibility constraint on connectors.
    # We create TWO connectors for E_north (even though truth says not admissible),
    # so M0's MIP can use them. But truth evaluator blocks the flow.
    # Actually - in our framework, M0 skips admissibility constraints,
    # so ALL connectors must exist in the graph for M0 to potentially use them.
    # Let's create connectors for all (terminal, port, edge) pairs,
    # and only enforce admissibility at M1/M* level.

    base = CandidateGraph(
        terminals={"T": t},
        waypoints={"S": (0.0, 1.0), "S2": (1.0, 0.0)},
        backbone_edges={
            # E_north: S(0,1)->T(0,0). From T dir=90° (north). h1(0°±40°) NOT admit. Cheap travel=1.0
            "E_north": BackboneEdge("E_north", "S", "T", 1.0, 2.0, 1.0, 50),
            # E_east: S2(1,0)->T(0,0). From T dir=0° (east). h1(0°±40°) admits. Expensive travel=3.0
            "E_east": BackboneEdge("E_east", "S2", "T", 1.0, 2.0, 3.0, 50),
            # Link S->S2 so demand can route S->S2->T via E_east (expensive but admissible)
            "E_link": BackboneEdge("E_link", "S", "S2", 1.4, 1.0, 1.5, 50),
        },
    )

    adm = build_full_admissibility(base)

    # Create connectors for ALL (terminal, port, edge) — M0 needs them
    connectors = {}
    for tid, terminal in base.terminals.items():
        for port in terminal.ports:
            for eid in ["E_north", "E_east"]:
                cid = f"C_{tid}_{port.port_id}_{eid}"
                d = base.compute_edge_direction(base.backbone_edges[eid], tid)
                connectors[cid] = ConnectorArc(cid, eid, tid, port.port_id, d, 0.01)

    graph = PortAugmentedGraph(base=base, connectors=connectors, admissibility=adm)

    scenario = DemandScenario(
        scenario_id="w1",
        od_demand={("S", "T"): demand},
        probability=1.0, unmet_penalty=100.0,
    )

    return graph, [scenario], t


def build_soft_instance(service_asymmetry: float = 2.0, demand: float = 3.0):
    """Soft: 2 ports with different service costs. Both edges admissible to their respective port.
    M0 can't distinguish → picks cheapest travel → loads expensive port.
    """
    t = TerminalConfig(
        "T", x=0, y=0,
        ports=[
            PortConfig("h1", direction_deg=0, sector_half_width_deg=50, a=0.1, b=0.2),
            PortConfig("h2", direction_deg=180, sector_half_width_deg=50, a=0.1, b=0.2 * service_asymmetry),
        ],
        mu_bar=10.0, psi_sat=2.0,
    )

    base = CandidateGraph(
        terminals={"T": t},
        waypoints={"S_east": (1.0, 0.0), "S_west": (-1.0, 0.0)},
        backbone_edges={
            "E_east": BackboneEdge("E_east", "S_east", "T", 1.0, 0.5, 1.0, 50),
            "E_west": BackboneEdge("E_west", "S_west", "T", 1.0, 0.5, 2.0, 50),
        },
    )

    adm = build_full_admissibility(base)
    connectors = {}
    conn_idx = 0
    for (tid, pid, eid), ok in adm.items():
        if ok:
            conn_idx += 1
            cid = f"C{conn_idx}"
            d = base.compute_edge_direction(base.backbone_edges[eid], tid)
            connectors[cid] = ConnectorArc(cid, eid, tid, pid, d, 0.01)

    graph = PortAugmentedGraph(base=base, connectors=connectors, admissibility=adm)
    scenario = DemandScenario(
        scenario_id="w1",
        od_demand={("S_east", "T"): demand},
        probability=1.0, unmet_penalty=100.0,
    )
    return graph, [scenario], t


def run_exp1(verbose: bool = False) -> dict:
    """Run both hard-cut and soft scenarios."""
    results = {}
    params = SolverParams(verbose=verbose, mip_gap=0.001)

    # Hard-cut
    graph, scenarios, t = build_hard_cut_instance()
    m0 = {"T": extract_s_only(t)}
    m1 = {"T": extract_as_interface(t, graph.base)}
    r = run_regret_experiment(
        graph, scenarios, [ModelLevel.M0, ModelLevel.M1],
        m0_interfaces=m0, m1_interfaces=m1, params=params,
    )
    results["hard_cut"] = {
        "j_star": r.truth_result.truth_objective,
        "m0_regret": r.model_results[ModelLevel.M0].regret,
        "m0_rel": r.model_results[ModelLevel.M0].relative_regret,
        "m1_regret": r.model_results[ModelLevel.M1].regret,
        "m0_edges": r.model_results[ModelLevel.M0].design.active_edges,
        "mstar_edges": r.truth_result.design.active_edges,
        "summary": r.summary(),
    }

    # Soft (parameter sweep)
    for kappa in [1.0, 1.5, 2.0, 3.0]:
        graph, scenarios, t = build_soft_instance(service_asymmetry=kappa)
        m0 = {"T": extract_s_only(t)}
        m1 = {"T": extract_as_interface(t, graph.base)}
        r = run_regret_experiment(
            graph, scenarios, [ModelLevel.M0, ModelLevel.M1],
            m0_interfaces=m0, m1_interfaces=m1, params=params,
        )
        results[f"soft_kS={kappa}"] = {
            "j_star": r.truth_result.truth_objective,
            "m0_regret": r.model_results[ModelLevel.M0].regret,
            "m0_rel": r.model_results[ModelLevel.M0].relative_regret,
            "m1_regret": r.model_results[ModelLevel.M1].regret,
            "m0_edges": r.model_results[ModelLevel.M0].design.active_edges,
            "mstar_edges": r.truth_result.design.active_edges,
        }

    return results


if __name__ == "__main__":
    print("=== EXP-1: A necessity ===\n")
    results = run_exp1()
    for name, r in results.items():
        print(f"[{name}]")
        if "summary" in r:
            print(r["summary"])
        print(f"  M0 Δ={r['m0_regret']:.4f} ({r['m0_rel']:.1%}), M1 Δ={r['m1_regret']:.4f}")
        print(f"  M0 edges={r['m0_edges']}, M* edges={r['mstar_edges']}")
        print()
