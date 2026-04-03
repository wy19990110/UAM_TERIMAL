"""EXP-3: F 的必要性 — 证明 AS 还不够，footprint 改变最优网络。

Graph:
  S ---E_near---> T ---E_far---> D
       (cheap)        (expensive)
  S ---E_bypass------------------> D
       (medium, longer)

Terminal T has footprint that penalizes E_near (nearby edge).
- M0/M1: don't see footprint → pick E_near+E_far (cheapest path through T)
- M2: sees footprint → may prefer E_bypass (avoids T's footprint zone)
- M*: truth footprint with load-sensitivity → optimal routing

When footprint severity is low: M1 ≈ M* (footprint doesn't matter)
When footprint severity is high: M1 fails, M2 recovers

Parameter sweep: φ_F (severity) × π_F (penalty magnitude) × ρ (demand)
"""

from __future__ import annotations

import json
from pathlib import Path

from uam.core.terminal import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc
from uam.core.demand import DemandScenario
from uam.truth.access import build_full_admissibility
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


def build_exp3_instance(
    demand: float = 3.0,
    footprint_penalty: float = 1.0,
    footprint_load_sens: float = 0.3,
    blocked: bool = False,
):
    """Build EXP-3 instance.

    S(source) --E_near--> T(terminal) --E_far--> D(destination waypoint)
    S --E_bypass--> D  (avoids terminal entirely)

    T has footprint on E_near:
      - base penalty π on E_near
      - load sensitivity ρ on E_near w.r.t. T's port
      - optionally hard-block E_near

    All models share the same A and S for T.
    The difference is ONLY in footprint visibility.
    """
    t = TerminalConfig(
        "T", x=0.5, y=0.0,
        ports=[PortConfig("h1", direction_deg=180, sector_half_width_deg=80, a=0.1, b=0.3)],
        mu_bar=10.0, psi_sat=2.0,
        footprint_radius_hops=1,
        footprint_base_penalty={"E_near": footprint_penalty},
        footprint_load_sensitivity={("E_near", "h1"): footprint_load_sens},
        blocked_edges={"E_near"} if blocked else set(),
    )

    base = CandidateGraph(
        terminals={"T": t},
        waypoints={
            "S": (0.0, 0.0),
            "D": (1.0, 0.0),
        },
        backbone_edges={
            # E_near: S→T, cheap but in T's footprint zone
            "E_near": BackboneEdge("E_near", "S", "T", 0.5, 0.5, 1.0, 50),
            # E_far: T→D
            "E_far": BackboneEdge("E_far", "T", "D", 0.5, 0.5, 1.0, 50),
            # E_bypass: S→D directly, more expensive but avoids T
            "E_bypass": BackboneEdge("E_bypass", "S", "D", 1.0, 1.0, 2.5, 50),
        },
    )

    adm = build_full_admissibility(base)

    # Create connectors for T's port to incident edges
    connectors = {}
    for eid in ["E_near", "E_far"]:
        edge = base.backbone_edges[eid]
        if edge.u == "T" or edge.v == "T":
            cid = f"C_T_h1_{eid}"
            d = base.compute_edge_direction(edge, "T")
            connectors[cid] = ConnectorArc(cid, eid, "T", "h1", d, 0.01)

    graph = PortAugmentedGraph(base=base, connectors=connectors, admissibility=adm)

    scenario = DemandScenario(
        scenario_id="w1",
        od_demand={("S", "D"): demand},
        probability=1.0, unmet_penalty=100.0,
    )

    return graph, [scenario], t


def run_exp3(verbose: bool = False) -> list[dict]:
    """Run EXP-3 parameter sweep."""
    params = SolverParams(verbose=verbose, mip_gap=0.001)
    results = []

    for rho in [0.6, 0.9, 1.2]:
        for pi_f in [0.2, 0.5, 1.0, 2.0]:
            for phi_f in [0.0, 0.2, 0.5, 1.0]:
                demand = rho * 5.0
                load_sens = phi_f * 0.5  # load sensitivity scales with severity
                blocked = phi_f >= 1.0  # hard block at max severity

                graph, scenarios, t = build_exp3_instance(
                    demand=demand,
                    footprint_penalty=pi_f,
                    footprint_load_sens=load_sens,
                    blocked=blocked,
                )

                m0 = {"T": extract_s_only(t)}
                m1 = {"T": extract_as_interface(t, graph.base)}
                m2 = {"T": extract_asf_interface(t, graph.base)}

                r = run_regret_experiment(
                    graph, scenarios,
                    levels=[ModelLevel.M0, ModelLevel.M1, ModelLevel.M2],
                    m0_interfaces=m0, m1_interfaces=m1, m2_interfaces=m2,
                    params=params,
                )

                results.append({
                    "rho": rho, "pi_F": pi_f, "phi_F": phi_f,
                    "j_star": r.truth_result.truth_objective,
                    "m0_regret": r.model_results[ModelLevel.M0].regret,
                    "m0_rel": r.model_results[ModelLevel.M0].relative_regret,
                    "m1_regret": r.model_results[ModelLevel.M1].regret,
                    "m1_rel": r.model_results[ModelLevel.M1].relative_regret,
                    "m2_regret": r.model_results[ModelLevel.M2].regret,
                    "m2_rel": r.model_results[ModelLevel.M2].relative_regret,
                    "m1_td": r.model_results[ModelLevel.M1].td_backbone,
                    "m2_rr": r.model_results[ModelLevel.M2].recovery_rate,
                    "mstar_edges": sorted(r.truth_result.design.active_edges),
                    "m1_edges": sorted(r.model_results[ModelLevel.M1].design.active_edges),
                })

    return results


if __name__ == "__main__":
    print("=== EXP-3: F necessity (footprint changes network) ===\n")
    results = run_exp3()

    print(f"{'rho':>5} {'pi_F':>5} {'phi_F':>5} | {'J*':>8} {'M0_%':>7} {'M1_%':>7} {'M2_%':>7} {'M1_TD':>6} | M* edges")
    print("-" * 85)
    for r in results:
        print(f"{r['rho']:5.1f} {r['pi_F']:5.1f} {r['phi_F']:5.1f} | "
              f"{r['j_star']:8.2f} {r['m0_rel']:6.1%} {r['m1_rel']:6.1%} {r['m2_rel']:6.1%} "
              f"{r['m1_td']:6.2f} | {r['mstar_edges']}")

    pos_m1 = sum(1 for r in results if r["m1_regret"] > 0.01)
    print(f"\nM1 positive regret: {pos_m1}/{len(results)} instances")
    print(f"Max M1 relative regret: {max(r['m1_rel'] for r in results):.1%}")
    print(f"Max M2 relative regret: {max(r['m2_rel'] for r in results):.4f}")

    out = Path("results/exp3_results.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(results, indent=2, default=str))
    print(f"\nResults saved to {out}")
