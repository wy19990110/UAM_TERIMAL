"""EXP-4B-S: S-channel isolation redesign.

Per 新的实验要求 §一.4:
- Fix A=0 (all connectors admissible), F=0 (no footprint)
- Sweep: rho (demand), m (cross-port coupling), psi (saturation penalty),
         c (OD concentration toward a single terminal)
- Compare M0 vs M1 only
- Core metric: U01 = J^truth(M0) - J^truth(M1)
- Output: U01 heatmap on rho x E_S

The goal is NOT to "prove S exists again" (EXP-2 already did that),
but to find the S-channel's medium-scale boundary: at what congestion
activation level does upgrading from M0 to M1 become worthwhile?
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    G1_SMALL, G2_SMALL, GraphSpec,
)
from uam.interface import extract_s_only, extract_as_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class SIsolationConfig:
    """Parameter sweep for S-channel isolation."""
    families: list[tuple[str, GraphSpec]]
    seeds: list[int]
    rho_values: list[float]
    coupling_m_values: list[float]
    psi_values: list[float]
    od_concentration_values: list[float]
    mip_gap: float = 0.01
    time_limit: float = 300.0

    @property
    def total_instances(self) -> int:
        return (len(self.families) * len(self.seeds)
                * len(self.rho_values) * len(self.coupling_m_values)
                * len(self.psi_values) * len(self.od_concentration_values))


MINI_CONFIG = SIsolationConfig(
    families=[("G1s", G1_SMALL)],
    seeds=[1],
    rho_values=[0.6, 1.0],
    coupling_m_values=[0.0, 0.3],
    psi_values=[1.0, 3.0],
    od_concentration_values=[0.3, 0.7],
)

MEDIUM_CONFIG = SIsolationConfig(
    families=[("G1s", G1_SMALL), ("G2s", G2_SMALL)],
    seeds=[1, 2, 3],
    rho_values=[0.4, 0.6, 0.8, 1.0, 1.2],
    coupling_m_values=[0.0, 0.1, 0.3, 0.5],
    psi_values=[1.0, 2.0, 3.0, 5.0],
    od_concentration_values=[0.3, 0.5, 0.7, 1.0],
)


def compute_service_excitation(
    coupling_m: float, psi: float, rho: float, concentration: float
) -> float:
    """Compute E_S: service excitation score.

    Combines cross-port coupling strength, saturation penalty intensity,
    and load pressure into a single scalar. Higher E_S means the
    terminal's port-level service differences are more likely to matter.
    """
    return coupling_m * 2.0 + (psi / 5.0) + rho * concentration


def run_single_instance(
    family_name: str,
    spec: GraphSpec,
    seed: int,
    rho: float,
    coupling_m: float,
    psi: float,
    concentration: float,
    params: SolverParams,
) -> dict:
    """Run M0 vs M1 for a single S-isolation instance."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=rho,
        access_restrictiveness=0.0,  # A=0: all connectors admissible
        service_asymmetry=2.0,       # keep asymmetry moderate-high
        footprint_severity=0.0,      # F=0: no footprint
        coupling_m=coupling_m,
        psi_sat=psi,
    )
    scenarios = generate_demand(
        graph, intensity=rho, seed=seed,
        concentration=concentration,
    )

    m0_ifaces = {}
    m1_ifaces = {}
    for tid, terminal in graph.terminals.items():
        m0_ifaces[tid] = extract_s_only(terminal)
        m1_ifaces[tid] = extract_as_interface(terminal, graph.base)

    t0 = time.time()
    result = run_regret_experiment(
        graph, scenarios,
        levels=[ModelLevel.M0, ModelLevel.M1],
        m0_interfaces=m0_ifaces,
        m1_interfaces=m1_ifaces,
        params=params,
    )
    elapsed = time.time() - t0

    e_s = compute_service_excitation(coupling_m, psi, rho, concentration)

    row = {
        "family": family_name,
        "seed": seed,
        "rho": rho,
        "coupling_m": coupling_m,
        "psi": psi,
        "concentration": concentration,
        "E_S": round(e_s, 4),
        "j_star": result.truth_result.truth_objective,
        "U01": result.u01,
        "m0_regret": result.model_results[ModelLevel.M0].regret,
        "m0_rel": result.model_results[ModelLevel.M0].relative_regret,
        "m1_regret": result.model_results[ModelLevel.M1].regret,
        "m1_rel": result.model_results[ModelLevel.M1].relative_regret,
        "m0_td_bb": result.model_results[ModelLevel.M0].td_backbone,
        "m1_td_bb": result.model_results[ModelLevel.M1].td_backbone,
        "time_s": round(elapsed, 1),
    }
    return row


def run_sweep(
    config: SIsolationConfig,
    checkpoint_path: Path | None = None,
    log_path: Path | None = None,
) -> list[dict]:
    """Run the S-isolation parameter sweep."""
    params = SolverParams(mip_gap=config.mip_gap, time_limit=config.time_limit)

    completed = set()
    results = []
    if checkpoint_path and checkpoint_path.exists():
        results = json.loads(checkpoint_path.read_text())
        for r in results:
            key = (r["family"], r["seed"], r["rho"], r["coupling_m"], r["psi"], r["concentration"])
            completed.add(key)

    total = config.total_instances
    done = len(completed)

    def log(msg: str):
        line = f"[{time.strftime('%H:%M:%S')}] {msg}"
        print(line)
        if log_path:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")

    log(f"=== EXP-4B-S: S-channel isolation, {total} instances ({done} done) ===")

    for fname, spec in config.families:
        for seed in config.seeds:
            for rho in config.rho_values:
                for m in config.coupling_m_values:
                    for psi in config.psi_values:
                        for c in config.od_concentration_values:
                            key = (fname, seed, rho, m, psi, c)
                            if key in completed:
                                continue
                            done += 1
                            log(f"[{done}/{total}] {fname} s={seed} "
                                f"rho={rho} m={m} psi={psi} c={c}")
                            try:
                                row = run_single_instance(
                                    fname, spec, seed, rho, m, psi, c, params)
                                results.append(row)
                                log(f"  J*={row['j_star']:.1f} "
                                    f"U01={row['U01']:.4f} E_S={row['E_S']:.2f} "
                                    f"({row['time_s']}s)")
                            except Exception as e:
                                log(f"  ERROR: {e}")
                                results.append({
                                    **dict(zip(
                                        ["family", "seed", "rho", "coupling_m", "psi", "concentration"],
                                        key,
                                    )),
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
    out_dir = Path("results/exp4b_s")
    out_dir.mkdir(parents=True, exist_ok=True)
    results = run_sweep(
        cfg,
        checkpoint_path=out_dir / f"exp4b_s_{mode}_checkpoint.json",
        log_path=out_dir / f"exp4b_s_{mode}.log",
    )
    (out_dir / f"exp4b_s_{mode}_results.json").write_text(
        json.dumps(results, indent=2, default=str))
    print(f"Results saved to {out_dir}")
