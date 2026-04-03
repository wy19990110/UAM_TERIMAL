"""Demand scenario data structures."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class DemandScenario:
    """A demand scenario with OD pairs and context state.

    Attributes:
        scenario_id: Unique identifier.
        od_demand: Dict mapping (origin, destination) -> demand quantity.
        probability: Probability of this scenario (for stochastic models).
        context_state: Context label (e.g. "relaxed", "constrained").
        unmet_penalty: Cost per unit of unmet demand.
    """

    scenario_id: str = "w1"
    od_demand: dict[tuple[str, str], float] = field(default_factory=dict)
    probability: float = 1.0
    context_state: str = "relaxed"
    unmet_penalty: float = 100.0

    @property
    def total_demand(self) -> float:
        return sum(self.od_demand.values())

    @property
    def num_od_pairs(self) -> int:
        return len(self.od_demand)

    @property
    def commodities(self) -> list[tuple[str, str]]:
        return list(self.od_demand.keys())
