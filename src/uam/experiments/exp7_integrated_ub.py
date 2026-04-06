"""EXP-7: Integrated upper bound (JO) benchmark.

Per 新的实验要求 §二.9:
JO is the integrated upper-bound benchmark — a joint optimization that solves
the full truth model directly. It's expensive but gives the theoretical best.

Instances:
- Small: 3-4 terminals, 2-3 waypoints (aim for exact solve)
- Medium: 5-6 terminals, 3-4 waypoints (time-limited + gap)
- Large: only for scaling analysis (no exact requirement)

Compare: B0, B1, O1(M1), O2(M2), JO
Key outputs:
- Gap to JO for each model
- PR's gap closure relative to B0/B1
- JO vs PR runtime ratio
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    JO_SMALL, JO_MEDIUM, G1_SMALL, GraphSpec,
)
from uam.interface import (
    extract_s_only, extract_as_interface, extract_asf_interface,
    extract_b0, extract_b1,
)
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class JOConfig:
    families: list[tuple[str, GraphSpec]]
    seeds: list[int]
    rho_values: list[float]
    alpha_A_values: list[float]
    phi_F_values: list[float]
    mip_gap: float = 0.005  # tighter gap for JO benchmark
    time_limit: float = 600.0

    @property
    def total_instances(self) -> int:
        return (len(self.families) * len(self.seeds)
                * len(self.rho_values) * len(self.alpha_A_values)
                * len(self.phi_F_values))


MINI_CONFIG = JOConfig(
    families=[("JO_S", JO_SMALL)],
    seeds=[1],
    rho_values=[0.8, 1.2],
    alpha_A_values=[0.25],
    phi_F_values=[0.0, 0.3],
)

SMALL_CONFIG = JOConfig(
    families=[("JO_S", JO_SMALL)],
    seeds=[1, 2, 3, 4, 5],
    rho_values=[0.5, 0.8, 1.0, 1.2],
    alpha_A_values=[0.0, 0.25, 0.5],
    phi_F_values=[0.0, 0.2, 0.5],
    mip_gap=0.001,
    time_limit=1200.0,
)

MEDIUM_CONFIG = JOConfig(
    families=[("JO_S", JO_SMALL), ("JO_M", JO_MEDIUM)],
    seeds=[1, 2, 3],
    rho_values=[0.5, 0.8, 1.0, 1.2],
    alpha_A_values=[0.0, 0.25, 0.5],
    phi_F_values=[0.0, 0.2, 0.5],
    mip_gap=0.005,
    time_limit=900.0,
)


def run_jo_instance(
    family_name: str,
    spec: GraphSpec,
    seed: int,
    rho: float,
    alpha_A: float,
    phi_F: float,
    params: SolverParams,
) -> dict:
    """Run B0/B1/M1/M2 + JO on the same instance."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=rho,
        access_restrictiveness=alpha_A,
        service_asymmetry=1.5,
        footprint_severity=phi_F,
    )
    scenarios = generate_demand(graph, intensity=rho, seed=seed)

    m0_ifaces = {}
    m1_ifaces = {}
    m2_ifaces = {}
    b0_ifaces = {}
    b1_ifaces = {}
    for tid, terminal in graph.terminals.items():
        m0_ifaces[tid] = extract_s_only(terminal)
        m1_ifaces[tid] = extract_as_interface(terminal, graph.base)
        m2_ifaces[tid] = extract_asf_interface(terminal, graph.base)
        b0_ifaces[tid] = extract_b0(terminal)
        b1_ifaces[tid] = extract_b1(terminal, graph.base)

    all_levels = [ModelLevel.B0, ModelLevel.B1, ModelLevel.M1, ModelLevel.M2]

    # Run with JO as the truth benchmark (upper bound)
    t0 = time.time()
    result = run_regret_experiment(
        graph, scenarios,
        levels=all_levels,
        m0_interfaces=m0_ifaces,
        m1_interfaces=m1_ifaces,
        m2_interfaces=m2_ifaces,
        b0_interfaces=b0_ifaces,
        b1_interfaces=b1_ifaces,
        params=params,
        truth_level=ModelLevel.JO,
    )
    elapsed = time.time() - t0

    j_jo = result.truth_result.truth_objective

    row = {
        "family": family_name,
        "seed": seed,
        "rho": rho,
        "alpha_A": alpha_A,
        "phi_F": phi_F,
        "j_jo": j_jo,
        "jo_solve_time": round(elapsed, 1),
    }

    for level in all_levels:
        tag = level.name.lower()
        r = result.model_results[level]
        row[f"{tag}_truth_obj"] = r.truth_objective
        row[f"{tag}_gap_to_jo"] = r.truth_objective - j_jo
        row[f"{tag}_gap_to_jo_pct"] = (r.truth_objective - j_jo) / max(abs(j_jo), 1e-10)
        row[f"{tag}_td_bb"] = r.td_backbone

    # Gap closure: how much of B0's gap does O2 close?
    b0_gap = row.get("b0_gap_to_jo", 0)
    m2_gap = row.get("m2_gap_to_jo", 0)
    row["m2_gap_closure_vs_b0"] = 1.0 - m2_gap / max(b0_gap, 1e-10) if b0_gap > 1e-10 else 0.0

    b1_gap = row.get("b1_gap_to_jo", 0)
    row["m2_gap_closure_vs_b1"] = 1.0 - m2_gap / max(b1_gap, 1e-10) if b1_gap > 1e-10 else 0.0

    return row


def run_sweep(
    config: JOConfig,
    checkpoint_path: Path | None = None,
    log_path: Path | None = None,
) -> list[dict]:
    """Run the JO benchmark sweep."""
    params = SolverParams(mip_gap=config.mip_gap, time_limit=config.time_limit)
    completed = set()
    results = []
    if checkpoint_path and checkpoint_path.exists():
        results = json.loads(checkpoint_path.read_text())
        for r in results:
            key = (r["family"], r["seed"], r["rho"], r["alpha_A"], r["phi_F"])
            completed.add(key)

    total = config.total_instances
    done = len(completed)

    def log(msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line)
        if log_path:
            with open(log_path, "a", encoding="utf-8") as fp:
                fp.write(line + "\n")

    log(f"=== EXP-7 JO Upper Bound: {total} instances ({done} done) ===")

    for fname, spec in config.families:
        for seed in config.seeds:
            for rho in config.rho_values:
                for alpha_A in config.alpha_A_values:
                    for phi_F in config.phi_F_values:
                        key = (fname, seed, rho, alpha_A, phi_F)
                        if key in completed:
                            continue
                        done += 1
                        log(f"[{done}/{total}] {fname} s={seed} "
                            f"rho={rho} aA={alpha_A} pF={phi_F}")
                        try:
                            row = run_jo_instance(
                                fname, spec, seed, rho, alpha_A, phi_F, params)
                            results.append(row)
                            log(f"  JO={row['j_jo']:.1f} "
                                f"B0gap={row['b0_gap_to_jo_pct']:.1%} "
                                f"M2gap={row['m2_gap_to_jo_pct']:.1%} "
                                f"closure={row['m2_gap_closure_vs_b0']:.1%}")
                        except Exception as e:
                            log(f"  ERROR: {e}")
                            results.append({
                                **dict(zip(
                                    ["family", "seed", "rho", "alpha_A", "phi_F"], key)),
                                "error": str(e),
                            })
                        if checkpoint_path:
                            checkpoint_path.write_text(
                                json.dumps(results, indent=2, default=str))

    log(f"=== Done: {len(results)} results ===")
    return results


if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "mini"
    cfgs = {"mini": MINI_CONFIG, "small": SMALL_CONFIG, "medium": MEDIUM_CONFIG}
    cfg = cfgs.get(mode, MINI_CONFIG)
    out_dir = Path("results/exp7_jo")
    out_dir.mkdir(parents=True, exist_ok=True)
    results = run_sweep(
        cfg,
        checkpoint_path=out_dir / f"exp7_{mode}_checkpoint.json",
        log_path=out_dir / f"exp7_{mode}.log",
    )
    (out_dir / f"exp7_{mode}_results.json").write_text(
        json.dumps(results, indent=2, default=str))
