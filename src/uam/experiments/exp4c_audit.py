"""EXP-4C Solver Audit: separate F-channel value from solver approximation artifacts.

Per 新的实验要求 §一.5:
- For phi_F in {0.1, 0.2, 0.3, 0.4, 0.5}, sample instances
- Run each with: current solver, higher precision, near-exact refinement
- Goal: separate "F information itself has value" from "negative U12 is McCormick artifact"
- Output: convergence table + residual U12 after tightening

Since the Python solver uses Gurobi MIQP (exact quadratic, no PwL), this audit
focuses on comparing different MIP gap targets and NonConvex settings to verify
that U12 results are robust to solver precision.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    G1_SMALL, G3_SMALL, GraphSpec,
)
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class AuditConfig:
    families: list[tuple[str, GraphSpec]]
    seeds: list[int]
    phi_F_values: list[float]
    rho_values: list[float]
    mip_gaps: list[float]  # different precision levels
    time_limits: list[float]

    @property
    def total_instances(self) -> int:
        return (len(self.families) * len(self.seeds)
                * len(self.phi_F_values) * len(self.rho_values)
                * len(self.mip_gaps))


AUDIT_CONFIG = AuditConfig(
    families=[("G1s", G1_SMALL), ("G3s", G3_SMALL)],
    seeds=[1, 2, 3],
    phi_F_values=[0.1, 0.2, 0.3, 0.4, 0.5],
    rho_values=[0.8, 1.0],
    mip_gaps=[0.01, 0.005, 0.001],
    time_limits=[300.0, 600.0, 1200.0],
)

MINI_AUDIT = AuditConfig(
    families=[("G1s", G1_SMALL)],
    seeds=[1],
    phi_F_values=[0.2, 0.5],
    rho_values=[1.0],
    mip_gaps=[0.01, 0.001],
    time_limits=[120.0, 300.0],
)


def run_audit_instance(
    family_name: str,
    spec: GraphSpec,
    seed: int,
    rho: float,
    phi_F: float,
    mip_gap: float,
    time_limit: float,
) -> dict:
    """Run M1 vs M2 at a specific solver precision level."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=rho,
        access_restrictiveness=0.25,
        service_asymmetry=1.5,
        footprint_severity=phi_F,
    )
    scenarios = generate_demand(graph, intensity=rho, seed=seed)

    m0_ifaces = {}
    m1_ifaces = {}
    m2_ifaces = {}
    for tid, terminal in graph.terminals.items():
        m0_ifaces[tid] = extract_s_only(terminal)
        m1_ifaces[tid] = extract_as_interface(terminal, graph.base)
        m2_ifaces[tid] = extract_asf_interface(terminal, graph.base)

    params = SolverParams(mip_gap=mip_gap, time_limit=time_limit)

    t0 = time.time()
    result = run_regret_experiment(
        graph, scenarios,
        levels=[ModelLevel.M0, ModelLevel.M1, ModelLevel.M2],
        m0_interfaces=m0_ifaces,
        m1_interfaces=m1_ifaces,
        m2_interfaces=m2_ifaces,
        params=params,
    )
    elapsed = time.time() - t0

    return {
        "family": family_name,
        "seed": seed,
        "rho": rho,
        "phi_F": phi_F,
        "mip_gap": mip_gap,
        "time_limit": time_limit,
        "j_star": result.truth_result.truth_objective,
        "U01": result.u01,
        "U12": result.u12,
        "m1_regret": result.model_results[ModelLevel.M1].regret,
        "m1_rel": result.model_results[ModelLevel.M1].relative_regret,
        "m2_regret": result.model_results[ModelLevel.M2].regret,
        "m2_rel": result.model_results[ModelLevel.M2].relative_regret,
        "m1_td_bb": result.model_results[ModelLevel.M1].td_backbone,
        "m2_td_bb": result.model_results[ModelLevel.M2].td_backbone,
        "negative_u12": result.u12 < 0,
        "time_s": round(elapsed, 1),
    }


def run_audit(
    config: AuditConfig,
    checkpoint_path: Path | None = None,
    log_path: Path | None = None,
) -> list[dict]:
    """Run the solver audit sweep."""
    completed = set()
    results = []
    if checkpoint_path and checkpoint_path.exists():
        results = json.loads(checkpoint_path.read_text())
        for r in results:
            key = (r["family"], r["seed"], r["rho"], r["phi_F"], r["mip_gap"])
            completed.add(key)

    total = config.total_instances
    done = len(completed)

    def log(msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line)
        if log_path:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    log(f"=== EXP-4C Audit: {total} instances ({done} done) ===")

    for fname, spec in config.families:
        for seed in config.seeds:
            for phi_F in config.phi_F_values:
                for rho in config.rho_values:
                    for gap, tlim in zip(config.mip_gaps, config.time_limits):
                        key = (fname, seed, rho, phi_F, gap)
                        if key in completed:
                            continue
                        done += 1
                        log(f"[{done}/{total}] {fname} s={seed} "
                            f"pF={phi_F} rho={rho} gap={gap}")
                        try:
                            row = run_audit_instance(
                                fname, spec, seed, rho, phi_F, gap, tlim)
                            results.append(row)
                            log(f"  U12={row['U12']:.4f} neg={row['negative_u12']} "
                                f"({row['time_s']}s)")
                        except Exception as e:
                            log(f"  ERROR: {e}")
                            results.append({
                                **dict(zip(
                                    ["family", "seed", "rho", "phi_F", "mip_gap"], key)),
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
    cfg = MINI_AUDIT if mode == "mini" else AUDIT_CONFIG
    out_dir = Path("results/exp4c_audit")
    out_dir.mkdir(parents=True, exist_ok=True)
    results = run_audit(
        cfg,
        checkpoint_path=out_dir / f"audit_{mode}_checkpoint.json",
        log_path=out_dir / f"audit_{mode}.log",
    )
    (out_dir / f"audit_{mode}_results.json").write_text(
        json.dumps(results, indent=2, default=str))
