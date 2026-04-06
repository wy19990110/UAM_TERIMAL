"""EXP-6: Incumbent abstractions benchmark.

Per 新的实验要求 §二.8:
Compare our interface family against literature-plausible baselines:
- B0: node + aggregate terminal surrogate (what literature does today)
- B1: A-only or A+coarse-service (terminal-aware but not ASF)
- O1: our M1 (AS interface)
- O2: our M2 (ASF interface)
- PR: rule-based planner from EXP-4D

All methods share the same candidate graph, data, and truth re-evaluation.

This answers: "Our abstraction beats not just our own M0, but also
plausible literature approaches."
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    G1_SMALL, G2_SMALL, G3_SMALL, GraphSpec,
)
from uam.interface import (
    extract_s_only, extract_as_interface, extract_asf_interface,
    extract_b0, extract_b1,
)
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class IncumbentConfig:
    families: list[tuple[str, GraphSpec]]
    seeds: list[int]
    rho_values: list[float]
    alpha_A_values: list[float]
    phi_F_values: list[float]
    mip_gap: float = 0.01
    time_limit: float = 300.0

    @property
    def total_instances(self) -> int:
        return (len(self.families) * len(self.seeds)
                * len(self.rho_values) * len(self.alpha_A_values)
                * len(self.phi_F_values))


MINI_CONFIG = IncumbentConfig(
    families=[("G1s", G1_SMALL)],
    seeds=[1],
    rho_values=[0.8, 1.2],
    alpha_A_values=[0.0, 0.3],
    phi_F_values=[0.0, 0.4],
)

MEDIUM_CONFIG = IncumbentConfig(
    families=[("G1s", G1_SMALL), ("G2s", G2_SMALL), ("G3s", G3_SMALL)],
    seeds=[1, 2, 3],
    rho_values=[0.5, 0.8, 1.0, 1.2],
    alpha_A_values=[0.0, 0.25, 0.5],
    phi_F_values=[0.0, 0.2, 0.5],
)


def run_incumbent_instance(
    family_name: str,
    spec: GraphSpec,
    seed: int,
    rho: float,
    alpha_A: float,
    phi_F: float,
    params: SolverParams,
) -> dict:
    """Run B0/B1/M0/M1/M2 on the same instance."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=rho,
        access_restrictiveness=alpha_A,
        service_asymmetry=1.5,
        footprint_severity=phi_F,
    )
    scenarios = generate_demand(graph, intensity=rho, seed=seed)

    # Extract all interfaces
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

    # Run all 5 models: B0, B1, M0 (=O0), M1 (=O1), M2 (=O2)
    all_levels = [ModelLevel.B0, ModelLevel.B1, ModelLevel.M0, ModelLevel.M1, ModelLevel.M2]

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
    )
    elapsed = time.time() - t0

    row = {
        "family": family_name,
        "seed": seed,
        "rho": rho,
        "alpha_A": alpha_A,
        "phi_F": phi_F,
        "j_star": result.truth_result.truth_objective,
        "time_s": round(elapsed, 1),
    }

    for level in all_levels:
        tag = level.name.lower()
        r = result.model_results[level]
        row[f"{tag}_regret"] = r.regret
        row[f"{tag}_rel"] = r.relative_regret
        row[f"{tag}_td_bb"] = r.td_backbone
        row[f"{tag}_suff3"] = abs(r.relative_regret) <= 0.03
        row[f"{tag}_suff5"] = abs(r.relative_regret) <= 0.05

    return row


def run_sweep(
    config: IncumbentConfig,
    checkpoint_path: Path | None = None,
    log_path: Path | None = None,
) -> list[dict]:
    """Run the incumbent benchmark sweep."""
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

    log(f"=== EXP-6 Incumbent Benchmark: {total} instances ({done} done) ===")

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
                            row = run_incumbent_instance(
                                fname, spec, seed, rho, alpha_A, phi_F, params)
                            results.append(row)
                            log(f"  B0={row['b0_rel']:.1%} B1={row['b1_rel']:.1%} "
                                f"M1={row['m1_rel']:.1%} M2={row['m2_rel']:.1%}")
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
    cfg = MINI_CONFIG if mode == "mini" else MEDIUM_CONFIG
    out_dir = Path("results/exp6_incumbent")
    out_dir.mkdir(parents=True, exist_ok=True)
    results = run_sweep(
        cfg,
        checkpoint_path=out_dir / f"exp6_{mode}_checkpoint.json",
        log_path=out_dir / f"exp6_{mode}.log",
    )
    (out_dir / f"exp6_{mode}_results.json").write_text(
        json.dumps(results, indent=2, default=str))
