"""EXP-8: Quality-time frontier / scaling analysis.

Per 新的实验要求 §二.10:
Quantify that "JO is expensive" by measuring runtime vs quality across scales.

Sweep: increasing nT, nW, OD density.
Report: runtime, timeout rate, best gap for B0/B1/O1/O2/JO.
Main plot: quality-time frontier (x=runtime, y=gap-to-JO).

Expected pattern:
- B0/B1: cheap but quality is poor
- JO: quality is best but cost explodes with scale
- O2/PR: quality close to JO, cost much lower than JO
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

from uam.graph_gen.synthetic import (
    generate_synthetic_graph, generate_demand,
    GraphSpec,
)
from uam.interface import (
    extract_s_only, extract_as_interface, extract_asf_interface,
    extract_b0, extract_b1,
)
from uam.solver import ModelLevel, SolverParams, build_and_solve
from uam.solver.evaluator import truth_evaluate


# Scaling graph specs: increasing size
SCALE_SPECS = [
    ("S3", GraphSpec(n_terminals=3, n_waypoints=2, target_edges=(5, 7))),
    ("S5", GraphSpec(n_terminals=5, n_waypoints=3, target_edges=(10, 14))),
    ("S8", GraphSpec(n_terminals=8, n_waypoints=5, target_edges=(18, 22))),
    ("S12", GraphSpec(n_terminals=12, n_waypoints=8, target_edges=(28, 35))),
    ("S16", GraphSpec(n_terminals=16, n_waypoints=10, target_edges=(38, 48))),
]


@dataclass
class ScalingConfig:
    specs: list[tuple[str, GraphSpec]]
    seeds: list[int]
    rho: float = 1.0
    alpha_A: float = 0.25
    phi_F: float = 0.3
    mip_gap: float = 0.01
    time_limit: float = 600.0


MINI_CONFIG = ScalingConfig(
    specs=SCALE_SPECS[:3],
    seeds=[1],
)

FULL_CONFIG = ScalingConfig(
    specs=SCALE_SPECS,
    seeds=[1, 2, 3],
    time_limit=1200.0,
)


def run_scaling_instance(
    spec_name: str,
    spec: GraphSpec,
    seed: int,
    config: ScalingConfig,
) -> dict:
    """Run all model levels on a single scaling instance, recording runtimes."""
    graph = generate_synthetic_graph(
        spec, seed=seed,
        demand_intensity=config.rho,
        access_restrictiveness=config.alpha_A,
        service_asymmetry=1.5,
        footprint_severity=config.phi_F,
    )
    scenarios = generate_demand(graph, intensity=config.rho, seed=seed)

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

    params = SolverParams(mip_gap=config.mip_gap, time_limit=config.time_limit)

    row = {
        "spec": spec_name,
        "n_terminals": spec.n_terminals,
        "n_waypoints": spec.n_waypoints,
        "seed": seed,
    }

    # Solve each level independently and measure runtime
    model_configs = [
        (ModelLevel.B0, m0_ifaces, None, None),
        (ModelLevel.B1, None, m1_ifaces, None),
        (ModelLevel.M1, None, m1_ifaces, None),
        (ModelLevel.M2, None, m1_ifaces, m2_ifaces),
        (ModelLevel.JO, None, None, None),
    ]

    # First solve JO to get the benchmark
    t0 = time.time()
    jo_design = build_and_solve(graph, scenarios, ModelLevel.JO, params=params)
    jo_time = time.time() - t0
    j_jo, _ = truth_evaluate(jo_design, graph, scenarios)
    row["jo_truth_obj"] = j_jo
    row["jo_time"] = round(jo_time, 2)
    row["jo_timed_out"] = jo_design.objective == float("inf")

    for level, m0_if, m1_if, m2_if in model_configs:
        if level == ModelLevel.JO:
            continue
        tag = level.name.lower()
        t0 = time.time()
        try:
            design = build_and_solve(
                graph, scenarios, level,
                m0_interfaces=m0_if or m0_ifaces,
                m1_interfaces=m1_if or m1_ifaces,
                m2_interfaces=m2_if or m2_ifaces,
                params=params,
            )
            solve_time = time.time() - t0
            j_truth, _ = truth_evaluate(design, graph, scenarios)
            row[f"{tag}_truth_obj"] = j_truth
            row[f"{tag}_gap_to_jo"] = j_truth - j_jo
            row[f"{tag}_gap_pct"] = (j_truth - j_jo) / max(abs(j_jo), 1e-10)
            row[f"{tag}_time"] = round(solve_time, 2)
            row[f"{tag}_timed_out"] = design.objective == float("inf")
        except Exception as e:
            row[f"{tag}_error"] = str(e)
            row[f"{tag}_time"] = round(time.time() - t0, 2)

    return row


def run_scaling(
    config: ScalingConfig,
    output_dir: Path,
) -> list[dict]:
    """Run the full scaling analysis."""
    output_dir.mkdir(parents=True, exist_ok=True)
    results = []
    total = len(config.specs) * len(config.seeds)
    done = 0

    for spec_name, spec in config.specs:
        for seed in config.seeds:
            done += 1
            print(f"[{done}/{total}] {spec_name} (nT={spec.n_terminals}) seed={seed}")
            try:
                row = run_scaling_instance(spec_name, spec, seed, config)
                results.append(row)
                jo_t = row.get("jo_time", "?")
                m2_gap = row.get("m2_gap_pct", 0)
                print(f"  JO_time={jo_t}s M2_gap={m2_gap:.1%}")
            except Exception as e:
                print(f"  ERROR: {e}")
                results.append({"spec": spec_name, "seed": seed, "error": str(e)})

    (output_dir / "scaling_results.json").write_text(
        json.dumps(results, indent=2, default=str))
    return results


if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "mini"
    cfg = MINI_CONFIG if mode == "mini" else FULL_CONFIG
    run_scaling(cfg, Path("results/exp8_scaling"))
