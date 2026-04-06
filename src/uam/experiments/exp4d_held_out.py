"""EXP-4D: Held-out recommendation map.

Per 新的实验要求 §一.6:
- Collect results from 4B-A, 4B-S, 4C and mixed sweep
- Compute excitation scores E_A, E_S, E_F per instance
- Train/test split (70/30)
- On train: learn threshold rules (E_A, E_S, E_F) -> recommended model
- On test: evaluate recommendation accuracy + excess regret
- Compare against "always M1" / "always M2" baselines

This module is NOT a blind sweep; it's a rule-based hierarchical planner.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from uam.solver import ModelLevel


@dataclass
class InstanceRecord:
    """Processed instance with excitation scores and truth results."""
    instance_id: str
    family: str
    seed: int
    # Excitation scores
    e_a: float  # admissibility tightness
    e_s: float  # service congestion activation
    e_f: float  # footprint severity
    # Truth-evaluated objectives for each model
    j_m0: float
    j_m1: float
    j_m2: float
    j_star: float
    # Derived
    u01: float = 0.0
    u12: float = 0.0
    truth_best_model: str = "M0"

    def __post_init__(self):
        self.u01 = self.j_m0 - self.j_m1
        self.u12 = self.j_m1 - self.j_m2
        # Determine ground truth best
        best_j = min(self.j_m0, self.j_m1, self.j_m2)
        if best_j == self.j_m2:
            self.truth_best_model = "M2"
        elif best_j == self.j_m1:
            self.truth_best_model = "M1"
        else:
            self.truth_best_model = "M0"


@dataclass
class RecommendationRule:
    """Simple threshold-based rule: E_A, E_S, E_F -> recommended model."""
    e_a_threshold: float = 0.3
    e_s_threshold: float = 0.5
    e_f_threshold: float = 0.2

    def recommend(self, e_a: float, e_s: float, e_f: float) -> str:
        if e_f >= self.e_f_threshold:
            return "M2"
        if e_a >= self.e_a_threshold or e_s >= self.e_s_threshold:
            return "M1"
        return "M0"


def load_results_from_json(path: Path) -> list[dict]:
    """Load raw experiment results JSON."""
    return json.loads(path.read_text())


def compute_excitation_scores(row: dict) -> tuple[float, float, float]:
    """Compute E_A, E_S, E_F from a raw result row.

    E_A: effective access tightness (from alpha_A or connector Jaccard distance)
    E_S: service congestion activation (from coupling, psi, rho)
    E_F: footprint severity (from phi_F)
    """
    e_a = row.get("alpha_A", 0.0) * 2.0  # scale to ~[0,1]
    coupling = row.get("coupling_m", 0.1)
    psi = row.get("psi", 2.0)
    rho = row.get("rho", 1.0)
    e_s = coupling * 2.0 + (psi / 5.0) + max(0, rho - 0.5) * 0.5
    e_f = row.get("phi_F", 0.0) * 2.0  # scale to ~[0,1]
    return (e_a, e_s, e_f)


def build_records(raw_results: list[dict]) -> list[InstanceRecord]:
    """Convert raw JSON results to InstanceRecord objects."""
    records = []
    for i, row in enumerate(raw_results):
        if "error" in row:
            continue
        e_a, e_s, e_f = compute_excitation_scores(row)
        records.append(InstanceRecord(
            instance_id=f"inst_{i}",
            family=row.get("family", "unknown"),
            seed=row.get("seed", 0),
            e_a=e_a,
            e_s=e_s,
            e_f=e_f,
            j_m0=row.get("j_star", 0) + row.get("m0_regret", 0),
            j_m1=row.get("j_star", 0) + row.get("m1_regret", 0),
            j_m2=row.get("j_star", 0) + row.get("m2_regret", 0),
            j_star=row.get("j_star", 0),
        ))
    return records


def train_test_split(
    records: list[InstanceRecord], test_fraction: float = 0.3, seed: int = 42,
) -> tuple[list[InstanceRecord], list[InstanceRecord]]:
    """Split records into train and test sets."""
    rng = np.random.RandomState(seed)
    indices = rng.permutation(len(records))
    split = int(len(records) * (1 - test_fraction))
    train = [records[i] for i in indices[:split]]
    test = [records[i] for i in indices[split:]]
    return train, test


def calibrate_rule(train: list[InstanceRecord]) -> RecommendationRule:
    """Learn optimal thresholds on training data via grid search."""
    best_rule = RecommendationRule()
    best_score = -1.0

    for ea_t in np.arange(0.1, 0.8, 0.1):
        for es_t in np.arange(0.2, 1.0, 0.1):
            for ef_t in np.arange(0.1, 0.6, 0.1):
                rule = RecommendationRule(ea_t, es_t, ef_t)
                correct = sum(
                    1 for r in train
                    if rule.recommend(r.e_a, r.e_s, r.e_f) == r.truth_best_model
                )
                score = correct / max(len(train), 1)
                if score > best_score:
                    best_score = score
                    best_rule = rule

    return best_rule


def evaluate_rule(
    rule: RecommendationRule,
    test: list[InstanceRecord],
) -> dict:
    """Evaluate a recommendation rule on test data."""
    correct = 0
    total_excess_regret = 0.0
    model_counts = {"M0": 0, "M1": 0, "M2": 0}

    # Baselines: always M1, always M2
    always_m1_excess = 0.0
    always_m2_excess = 0.0

    for r in test:
        recommended = rule.recommend(r.e_a, r.e_s, r.e_f)
        model_counts[recommended] += 1

        if recommended == r.truth_best_model:
            correct += 1

        # Compute excess regret vs truth-best-in-family
        best_j = min(r.j_m0, r.j_m1, r.j_m2)
        rec_j = {"M0": r.j_m0, "M1": r.j_m1, "M2": r.j_m2}[recommended]
        total_excess_regret += max(0, rec_j - best_j)

        always_m1_excess += max(0, r.j_m1 - best_j)
        always_m2_excess += max(0, r.j_m2 - best_j)

    n = max(len(test), 1)
    return {
        "accuracy": correct / n,
        "mean_excess_regret": total_excess_regret / n,
        "model_distribution": model_counts,
        "always_m1_excess": always_m1_excess / n,
        "always_m2_excess": always_m2_excess / n,
        "rule_thresholds": {
            "e_a": rule.e_a_threshold,
            "e_s": rule.e_s_threshold,
            "e_f": rule.e_f_threshold,
        },
    }


def run_held_out_analysis(
    result_paths: list[Path],
    output_dir: Path,
) -> dict:
    """Run the full held-out recommendation analysis.

    Args:
        result_paths: paths to JSON result files from 4B-A, 4B-S, 4C, 4D sweep.
        output_dir: where to save analysis results.
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    # Collect all results
    all_raw = []
    for p in result_paths:
        if p.exists():
            all_raw.extend(load_results_from_json(p))

    records = build_records(all_raw)
    if len(records) < 10:
        return {"error": f"Too few valid records ({len(records)}), need >= 10"}

    train, test = train_test_split(records)

    # Calibrate
    rule = calibrate_rule(train)

    # Evaluate
    evaluation = evaluate_rule(rule, test)
    evaluation["n_train"] = len(train)
    evaluation["n_test"] = len(test)

    # Save
    (output_dir / "held_out_evaluation.json").write_text(
        json.dumps(evaluation, indent=2, default=str))

    return evaluation


if __name__ == "__main__":
    import sys
    result_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("results")
    paths = [
        result_dir / "exp4b" / "exp4b_medium_results.json",
        result_dir / "exp4b_s" / "exp4b_s_medium_results.json",
        result_dir / "exp4c_audit" / "audit_medium_results.json",
        result_dir / "exp4" / "exp4_medium_results.json",
    ]
    out = run_held_out_analysis(paths, Path("results/exp4d_held_out"))
    print(json.dumps(out, indent=2))
