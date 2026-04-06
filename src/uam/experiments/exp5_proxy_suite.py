"""EXP-5: Realistic proxy suite — three sensitivity types.

Per 新的实验要求 §一.7:
- A-sensitive proxy: port direction misalignment + extra inadmissible connectors
- S-sensitive proxy: multiple ODs converging on shared terminal resources
- F-sensitive proxy: airport-adjacent with protection zone (existing design)

Each type: 3-5 seeds, low/med/high demand x relaxed/constrained context.
Goal: show that A, S, F channels each independently change network design
in realistic-looking scenarios.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_a_sensitive_proxy,
    generate_s_sensitive_proxy,
    generate_f_sensitive_proxy,
    generate_demand,
)
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface
from uam.solver import ModelLevel, SolverParams, run_regret_experiment


@dataclass
class ProxySuiteConfig:
    seeds: list[int]
    rho_values: list[float]
    mip_gap: float = 0.01
    time_limit: float = 300.0


MINI_CONFIG = ProxySuiteConfig(
    seeds=[1],
    rho_values=[0.8, 1.2],
)

FULL_CONFIG = ProxySuiteConfig(
    seeds=[1, 2, 3, 4, 5],
    rho_values=[0.6, 1.0, 1.4],
)


def run_proxy_instance(
    proxy_type: str,
    seed: int,
    rho: float,
    params: SolverParams,
) -> dict:
    """Run a single proxy instance with M0/M1/M2."""
    if proxy_type == "A-sensitive":
        graph = generate_a_sensitive_proxy(seed=seed, demand_intensity=rho)
    elif proxy_type == "S-sensitive":
        graph = generate_s_sensitive_proxy(seed=seed, demand_intensity=rho)
    elif proxy_type == "F-sensitive":
        graph = generate_f_sensitive_proxy(seed=seed, demand_intensity=rho)
    else:
        raise ValueError(f"Unknown proxy type: {proxy_type}")

    scenarios = generate_demand(graph, intensity=rho, seed=seed)

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
        "proxy_type": proxy_type,
        "seed": seed,
        "rho": rho,
        "j_star": result.truth_result.truth_objective,
        "U01": result.u01,
        "U12": result.u12,
        "recommended": result.recommend_model().name,
    }
    for level in [ModelLevel.M0, ModelLevel.M1, ModelLevel.M2]:
        tag = level.name.lower()
        r = result.model_results[level]
        row[f"{tag}_regret"] = r.regret
        row[f"{tag}_rel"] = r.relative_regret
        row[f"{tag}_rr"] = r.recovery_rate
        row[f"{tag}_td_bb"] = r.td_backbone
        row[f"{tag}_td_conn"] = r.td_connectors
    row["time_s"] = round(elapsed, 1)
    return row


def run_proxy_suite(
    config: ProxySuiteConfig,
    output_dir: Path,
) -> list[dict]:
    """Run the full three-type proxy suite."""
    output_dir.mkdir(parents=True, exist_ok=True)
    params = SolverParams(mip_gap=config.mip_gap, time_limit=config.time_limit)

    proxy_types = ["A-sensitive", "S-sensitive", "F-sensitive"]
    results = []

    total = len(proxy_types) * len(config.seeds) * len(config.rho_values)
    done = 0

    for ptype in proxy_types:
        for seed in config.seeds:
            for rho in config.rho_values:
                done += 1
                print(f"[{done}/{total}] {ptype} seed={seed} rho={rho}")
                try:
                    row = run_proxy_instance(ptype, seed, rho, params)
                    results.append(row)
                    print(f"  J*={row['j_star']:.1f} U01={row['U01']:.3f} "
                          f"U12={row['U12']:.3f} rec={row['recommended']}")
                except Exception as e:
                    print(f"  ERROR: {e}")
                    results.append({"proxy_type": ptype, "seed": seed,
                                    "rho": rho, "error": str(e)})

    (output_dir / "proxy_suite_results.json").write_text(
        json.dumps(results, indent=2, default=str))
    return results


if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "mini"
    cfg = MINI_CONFIG if mode == "mini" else FULL_CONFIG
    run_proxy_suite(cfg, Path("results/exp5_proxy"))
