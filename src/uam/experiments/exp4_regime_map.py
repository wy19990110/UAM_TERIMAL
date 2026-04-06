"""EXP-4: Full-network regime map — identify sufficiency regions for S-only / AS / ASF.

Sweeps: graph_family × seed × ρ × α_A × κ_S × φ_F
Full: 3 families × 5 seeds × 4×3×3×3 = 1620 instances, each with M0/M1/M2/M*

Can run in mini mode (1 family × 1 seed × 2×2×2×2 = 16 instances) for validation.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    G1_SPEC, G2_SPEC, G3_SPEC,
    G1_SMALL, G2_SMALL, G3_SMALL,
    GraphSpec,
)
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class SweepConfig:
    """Parameter sweep configuration."""
    families: list[tuple[str, GraphSpec]]
    seeds: list[int]
    rho_values: list[float]
    alpha_A_values: list[float]
    kappa_S_values: list[float]
    phi_F_values: list[float]
    mip_gap: float = 0.01
    time_limit: float = 300.0

    @property
    def total_instances(self) -> int:
        return (len(self.families) * len(self.seeds)
                * len(self.rho_values) * len(self.alpha_A_values)
                * len(self.kappa_S_values) * len(self.phi_F_values))


MINI_CONFIG = SweepConfig(
    families=[("G1s", G1_SMALL)],
    seeds=[1],
    rho_values=[0.5, 1.0],
    alpha_A_values=[0.0, 0.25],
    kappa_S_values=[1, 2],
    phi_F_values=[0.0, 0.3],
)

MEDIUM_CONFIG = SweepConfig(
    families=[("G1s", G1_SMALL), ("G2s", G2_SMALL), ("G3s", G3_SMALL)],
    seeds=[1, 2, 3],
    rho_values=[0.5, 0.8, 1.0, 1.2],
    alpha_A_values=[0.0, 0.25, 0.5],
    kappa_S_values=[1, 2, 3],
    phi_F_values=[0.0, 0.2, 0.5],
)

FULL_CONFIG = SweepConfig(
    families=[("G1", G1_SPEC), ("G2", G2_SPEC), ("G3", G3_SPEC)],
    seeds=[1, 2, 3, 4, 5],
    rho_values=[0.5, 0.8, 1.0, 1.2],
    alpha_A_values=[0.0, 0.25, 0.5],
    kappa_S_values=[1, 2, 3],
    phi_F_values=[0.0, 0.2, 0.5],
)


def run_single_instance(
    family_name: str,
    spec: GraphSpec,
    seed: int,
    rho: float,
    alpha_A: float,
    kappa_S: float,
    phi_F: float,
    params: SolverParams,
) -> dict:
    """Run M0/M1/M2/M* for a single parameter combination."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=rho,
        access_restrictiveness=alpha_A,
        service_asymmetry=kappa_S,
        footprint_severity=phi_F,
    )
    scenarios = generate_demand(graph, intensity=rho, seed=seed)

    # Extract interfaces
    m0_ifaces = {}
    m1_ifaces = {}
    m2_ifaces = {}
    for tid, terminal in graph.terminals.items():
        m0_ifaces[tid] = extract_s_only(terminal)
        m1_ifaces[tid] = extract_as_interface(terminal, graph.base)
        m2_ifaces[tid] = extract_asf_interface(terminal, graph.base)

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

    row = {
        "family": family_name,
        "seed": seed,
        "rho": rho,
        "alpha_A": alpha_A,
        "kappa_S": kappa_S,
        "phi_F": phi_F,
        "j_star": result.truth_result.truth_objective,
        "time_s": round(elapsed, 1),
    }

    for level in [ModelLevel.M0, ModelLevel.M1, ModelLevel.M2]:
        tag = level.name.lower()
        r = result.model_results[level]
        row[f"{tag}_regret"] = r.regret
        row[f"{tag}_rel"] = r.relative_regret
        row[f"{tag}_rr"] = r.recovery_rate
        row[f"{tag}_td_bb"] = r.td_backbone
        row[f"{tag}_td_conn"] = r.td_connectors
        row[f"{tag}_suff3"] = abs(r.relative_regret) <= 0.03
        row[f"{tag}_suff5"] = abs(r.relative_regret) <= 0.05

    return row


def run_sweep(
    config: SweepConfig,
    checkpoint_path: Path | None = None,
    log_path: Path | None = None,
) -> list[dict]:
    """Run the full parameter sweep with checkpoint/resume."""
    params = SolverParams(mip_gap=config.mip_gap, time_limit=config.time_limit)

    # Load checkpoint if exists
    completed = set()
    results = []
    if checkpoint_path and checkpoint_path.exists():
        results = json.loads(checkpoint_path.read_text())
        for r in results:
            key = (r["family"], r["seed"], r["rho"], r["alpha_A"], r["kappa_S"], r["phi_F"])
            completed.add(key)

    total = config.total_instances
    done = len(completed)

    def log(msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line)
        if log_path:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    log(f"=== EXP-4 Regime Map: {total} instances ({done} already done) ===")

    for fname, spec in config.families:
        for seed in config.seeds:
            for rho in config.rho_values:
                for alpha_A in config.alpha_A_values:
                    for kappa_S in config.kappa_S_values:
                        for phi_F in config.phi_F_values:
                            key = (fname, seed, rho, alpha_A, kappa_S, phi_F)
                            if key in completed:
                                continue

                            done += 1
                            log(f"[{done}/{total}] {fname} s={seed} "
                                f"rho={rho} aA={alpha_A} kS={kappa_S} pF={phi_F}")

                            try:
                                row = run_single_instance(
                                    fname, spec, seed, rho, alpha_A, kappa_S, phi_F, params,
                                )
                                results.append(row)
                                log(f"  J*={row['j_star']:.1f} "
                                    f"M0={row['m0_rel']:.1%} M1={row['m1_rel']:.1%} "
                                    f"M2={row['m2_rel']:.1%} ({row['time_s']}s)")
                            except Exception as e:
                                log(f"  ERROR: {e}")
                                results.append({**dict(zip(
                                    ["family","seed","rho","alpha_A","kappa_S","phi_F"], key
                                )), "error": str(e)})

                            # Checkpoint after each instance
                            if checkpoint_path:
                                checkpoint_path.write_text(
                                    json.dumps(results, indent=2, default=str)
                                )

    log(f"=== Done: {len(results)} results ===")
    return results


if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "mini"

    out_dir = Path("results/exp4")
    out_dir.mkdir(parents=True, exist_ok=True)

    if mode == "full":
        config = FULL_CONFIG
    elif mode == "medium":
        config = MEDIUM_CONFIG
    else:
        config = MINI_CONFIG

    results = run_sweep(
        config,
        checkpoint_path=out_dir / f"exp4_{mode}_checkpoint.json",
        log_path=out_dir / f"exp4_{mode}_log.txt",
    )

    # Final save
    (out_dir / f"exp4_{mode}_results.json").write_text(
        json.dumps(results, indent=2, default=str)
    )
    print(f"\nResults saved to {out_dir}/exp4_{mode}_results.json")

    # Quick summary
    if results and "error" not in results[0]:
        m0_pos = sum(1 for r in results if r.get("m0_regret", 0) > 0.01)
        m1_pos = sum(1 for r in results if r.get("m1_regret", 0) > 0.01)
        m2_pos = sum(1 for r in results if r.get("m2_regret", 0) > 0.01)
        m0_suff3 = sum(1 for r in results if r.get("m0_suff3", False))
        m1_suff3 = sum(1 for r in results if r.get("m1_suff3", False))
        m2_suff3 = sum(1 for r in results if r.get("m2_suff3", False))
        n = len(results)
        print(f"\nSummary ({n} instances):")
        print(f"  M0 sufficient (3%): {m0_suff3}/{n} ({m0_suff3/n:.0%})")
        print(f"  M1 sufficient (3%): {m1_suff3}/{n} ({m1_suff3/n:.0%})")
        print(f"  M2 sufficient (3%): {m2_suff3}/{n} ({m2_suff3/n:.0%})")
