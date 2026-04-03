"""EXP-2: S 的必要性 — port-level service asymmetry 改变最优网络。

1 terminal, 2 ports, 2 backbone edges (both admissible to their respective port).
Left port cheap service, right port expensive.
Left backbone edge more expensive travel, right backbone edge cheaper travel.

M0 (aggregate): can't distinguish ports → picks cheaper travel (right) → loads expensive port.
M1 (per-port): sees asymmetry → may split or pick left → lower total cost.
M*: full truth with coupling → optimal split.

Parameter sweep: ρ × Δc × κ_S
"""

from __future__ import annotations

import json
from pathlib import Path

from uam.core.terminal import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc
from uam.core.demand import DemandScenario
from uam.truth.access import build_full_admissibility
from uam.interface import extract_s_only, extract_as_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


def build_exp2_instance(
    demand: float = 3.0,
    cost_gap: float = 0.5,
    service_asymmetry: float = 2.0,
):
    """Build EXP-2 instance.

    Args:
        demand: Total demand S→T.
        cost_gap: Δc = travel cost difference between left and right edges.
        service_asymmetry: κ_S = ratio of right port's b to left port's b.
    """
    base_travel = 1.5
    t = TerminalConfig(
        "T", x=0, y=0,
        ports=[
            # h1 faces east (0°), cheap service
            PortConfig("h1", direction_deg=0, sector_half_width_deg=80, a=0.1, b=0.3),
            # h2 faces west (180°), expensive service
            PortConfig("h2", direction_deg=180, sector_half_width_deg=80, a=0.1, b=0.3 * service_asymmetry),
        ],
        mu_bar=10.0, psi_sat=2.0,
        cross_port_coupling={("h1", "h2"): 0.1},
    )

    base = CandidateGraph(
        terminals={"T": t},
        waypoints={"S_east": (1.0, 0.0), "S_west": (-1.0, 0.0)},
        backbone_edges={
            # E_east → h1 (cheap port). Travel cost = base + Δc/2 (more expensive travel)
            "E_east": BackboneEdge("E_east", "S_east", "T", 1.0, 0.5,
                                   base_travel + cost_gap / 2, 50),
            # E_west → h2 (expensive port). Travel cost = base - Δc/2 (cheaper travel)
            "E_west": BackboneEdge("E_west", "S_west", "T", 1.0, 0.5,
                                   base_travel - cost_gap / 2, 50),
            # Link so both sources can reach T via either path
            "E_link": BackboneEdge("E_link", "S_east", "S_west", 2.0, 0.3, 0.5, 50),
        },
    )

    adm = build_full_admissibility(base)
    connectors = {}
    for tid, terminal in base.terminals.items():
        for port in terminal.ports:
            for eid in ["E_east", "E_west"]:
                cid = f"C_{tid}_{port.port_id}_{eid}"
                d = base.compute_edge_direction(base.backbone_edges[eid], tid)
                connectors[cid] = ConnectorArc(cid, eid, tid, port.port_id, d, 0.01)

    graph = PortAugmentedGraph(base=base, connectors=connectors, admissibility=adm)
    scenario = DemandScenario(
        scenario_id="w1",
        od_demand={("S_east", "T"): demand},
        probability=1.0, unmet_penalty=100.0,
    )
    return graph, [scenario], t


def run_exp2(verbose: bool = False) -> list[dict]:
    """Run EXP-2 parameter sweep."""
    params = SolverParams(verbose=verbose, mip_gap=0.001)
    results = []

    for rho in [0.4, 0.6, 0.8, 1.0, 1.2]:
        for dc in [0.0, 0.1, 0.2, 0.3]:
            for kappa in [1.0, 1.5, 2.0, 3.0]:
                demand = rho * 5.0  # scale to meaningful level
                graph, scenarios, t = build_exp2_instance(demand, dc, kappa)
                m0 = {"T": extract_s_only(t)}
                m1 = {"T": extract_as_interface(t, graph.base)}

                r = run_regret_experiment(
                    graph, scenarios, [ModelLevel.M0, ModelLevel.M1],
                    m0_interfaces=m0, m1_interfaces=m1, params=params,
                )

                results.append({
                    "rho": rho, "delta_c": dc, "kappa_S": kappa,
                    "j_star": r.truth_result.truth_objective,
                    "m0_regret": r.model_results[ModelLevel.M0].regret,
                    "m0_rel": r.model_results[ModelLevel.M0].relative_regret,
                    "m1_regret": r.model_results[ModelLevel.M1].regret,
                    "m1_rel": r.model_results[ModelLevel.M1].relative_regret,
                    "m0_td": r.model_results[ModelLevel.M0].td_backbone,
                    "m1_rr": r.model_results[ModelLevel.M1].recovery_rate,
                })

    return results


if __name__ == "__main__":
    print("=== EXP-2: S necessity (port-level service asymmetry) ===\n")
    results = run_exp2()

    # Print summary table
    print(f"{'rho':>5} {'Δc':>5} {'κ_S':>5} | {'J*':>8} {'M0_Δ':>8} {'M0_%':>7} {'M1_Δ':>8} {'M1_RR':>7}")
    print("-" * 70)
    for r in results:
        print(f"{r['rho']:5.1f} {r['delta_c']:5.2f} {r['kappa_S']:5.1f} | "
              f"{r['j_star']:8.2f} {r['m0_regret']:8.4f} {r['m0_rel']:6.1%} "
              f"{r['m1_regret']:8.4f} {r['m1_rr']:6.1%}")

    # Count how many have positive M0 regret
    pos_m0 = sum(1 for r in results if r["m0_regret"] > 0.01)
    print(f"\nM0 positive regret: {pos_m0}/{len(results)} instances")
    print(f"Max M0 relative regret: {max(r['m0_rel'] for r in results):.1%}")
    print(f"M1 max regret: {max(r['m1_regret'] for r in results):.4f}")

    # Save results
    out = Path("results/exp2_results.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(results, indent=2))
    print(f"\nResults saved to {out}")
