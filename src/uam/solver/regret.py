"""Regret framework: orchestrate M0/M1/M2/M* solve + truth evaluate + compute metrics."""

from __future__ import annotations

from dataclasses import dataclass, field

from uam.core.graph import PortAugmentedGraph
from uam.core.demand import DemandScenario
from uam.core.design import NetworkDesign
from uam.solver.miqp_builder import ModelLevel, SolverParams, build_and_solve
from uam.solver.evaluator import truth_evaluate, TruthBreakdown


@dataclass
class RegretResult:
    """Result for a single model level."""

    level: ModelLevel
    design: NetworkDesign
    model_objective: float  # objective from the model's own MIP
    truth_objective: float  # J^truth
    breakdown: TruthBreakdown
    regret: float = 0.0  # Δ_i = J^truth(x_i) - J^truth(x*)
    relative_regret: float = 0.0  # Δ_i / J^truth(x*)
    recovery_rate: float = 0.0  # 1 - Δ_i / Δ_0
    td_backbone: float = 0.0
    td_connectors: float = 0.0


@dataclass
class ExperimentResult:
    """Full result of a regret experiment."""

    truth_result: RegretResult  # M* result
    model_results: dict[ModelLevel, RegretResult] = field(default_factory=dict)

    # --- Pairwise uplift metrics (新的实验要求: §一) ---

    @property
    def u01(self) -> float:
        """Pairwise uplift M0→M1: J^truth(M0) - J^truth(M1).

        Positive means M1 is better (lower truth cost) than M0.
        """
        m0 = self.model_results.get(ModelLevel.M0)
        m1 = self.model_results.get(ModelLevel.M1)
        if m0 is None or m1 is None:
            return float("nan")
        return m0.truth_objective - m1.truth_objective

    @property
    def u12(self) -> float:
        """Pairwise uplift M1→M2: J^truth(M1) - J^truth(M2).

        Positive means M2 is better (lower truth cost) than M1.
        """
        m1 = self.model_results.get(ModelLevel.M1)
        m2 = self.model_results.get(ModelLevel.M2)
        if m1 is None or m2 is None:
            return float("nan")
        return m1.truth_objective - m2.truth_objective

    @property
    def u02(self) -> float:
        """Pairwise uplift M0→M2: J^truth(M0) - J^truth(M2)."""
        m0 = self.model_results.get(ModelLevel.M0)
        m2 = self.model_results.get(ModelLevel.M2)
        if m0 is None or m2 is None:
            return float("nan")
        return m0.truth_objective - m2.truth_objective

    def recommend_model(self, threshold: float = 0.03) -> ModelLevel:
        """Recommend the cheapest sufficient model level.

        Rule (from 新的实验要求):
        - If U01 < threshold AND U02 < threshold → recommend M0
        - If U01 >= threshold AND U12 < threshold → recommend M1
        - If U12 >= threshold → recommend M2
        """
        j_star = self.truth_result.truth_objective
        denom = max(abs(j_star), 1e-10)

        rel_u01 = self.u01 / denom
        rel_u12 = self.u12 / denom
        rel_u02 = self.u02 / denom

        if rel_u01 < threshold and rel_u02 < threshold:
            return ModelLevel.M0
        if rel_u01 >= threshold and rel_u12 < threshold:
            return ModelLevel.M1
        return ModelLevel.M2

    def summary(self) -> str:
        lines = [f"M* truth objective: {self.truth_result.truth_objective:.4f}"]
        for level, r in sorted(self.model_results.items(), key=lambda x: x[0].value):
            lines.append(
                f"  {level.name}: Δ={r.regret:.4f} ({r.relative_regret:.1%}), "
                f"RR={r.recovery_rate:.1%}, TD_bb={r.td_backbone:.2f}, TD_conn={r.td_connectors:.2f}"
            )
        # Append pairwise uplifts if available
        import math
        if not math.isnan(self.u01):
            lines.append(f"  U01={self.u01:.4f}, U12={self.u12:.4f}, U02={self.u02:.4f}")
            lines.append(f"  Recommended: {self.recommend_model().name}")
        return "\n".join(lines)


def run_regret_experiment(
    graph: PortAugmentedGraph,
    scenarios: list[DemandScenario],
    levels: list[ModelLevel] | None = None,
    *,
    m0_interfaces: dict | None = None,
    m1_interfaces: dict | None = None,
    m2_interfaces: dict | None = None,
    b0_interfaces: dict | None = None,
    b1_interfaces: dict | None = None,
    params: SolverParams | None = None,
    truth_level: ModelLevel = ModelLevel.MSTAR,
) -> ExperimentResult:
    """Run a full regret experiment.

    1. Solve truth_level (default M*) to get truth benchmark design x*
    2. Truth-evaluate x* to get J*(x*)
    3. For each level in levels: solve -> truth-evaluate -> compute regret

    When truth_level is JO, the joint-optimization solve is used as upper bound.

    Returns:
        ExperimentResult with all metrics.
    """
    if levels is None:
        levels = [ModelLevel.M0, ModelLevel.M1, ModelLevel.M2]
    if params is None:
        params = SolverParams()
    # B0/B1 use M0/M1 interfaces respectively
    if b0_interfaces is None:
        b0_interfaces = m0_interfaces
    if b1_interfaces is None:
        b1_interfaces = m1_interfaces

    # Step 1: Solve truth benchmark (M* or JO)
    star_design = build_and_solve(
        graph, scenarios, truth_level, params=params,
    )

    # Step 2: Truth-evaluate M*
    j_star, star_breakdown = truth_evaluate(star_design, graph, scenarios)

    truth_result = RegretResult(
        level=truth_level,
        design=star_design,
        model_objective=star_design.objective,
        truth_objective=j_star,
        breakdown=star_breakdown,
    )

    # Step 3: For each model level
    model_results: dict[ModelLevel, RegretResult] = {}
    m0_regret = None

    for level in levels:
        # Route B0/B1 to their respective interfaces
        level_m0 = b0_interfaces if level == ModelLevel.B0 else m0_interfaces
        level_m1 = b1_interfaces if level == ModelLevel.B1 else m1_interfaces
        design = build_and_solve(
            graph, scenarios, level,
            m0_interfaces=level_m0,
            m1_interfaces=level_m1,
            m2_interfaces=m2_interfaces,
            params=params,
        )

        j_truth, breakdown = truth_evaluate(design, graph, scenarios)

        regret = j_truth - j_star
        rel_regret = regret / max(abs(j_star), 1e-10)

        if level == ModelLevel.M0:
            m0_regret = regret

        rr = 0.0
        if m0_regret is not None and m0_regret > 1e-10:
            rr = 1.0 - regret / m0_regret

        result = RegretResult(
            level=level,
            design=design,
            model_objective=design.objective,
            truth_objective=j_truth,
            breakdown=breakdown,
            regret=regret,
            relative_regret=rel_regret,
            recovery_rate=rr,
            td_backbone=design.topology_distance_backbone(star_design),
            td_connectors=design.topology_distance_connectors(star_design),
        )
        model_results[level] = result

    # Recompute recovery rates now that M0 regret is known
    if m0_regret is not None and m0_regret > 1e-10:
        for level, r in model_results.items():
            r.recovery_rate = 1.0 - r.regret / m0_regret

    return ExperimentResult(
        truth_result=truth_result,
        model_results=model_results,
    )
