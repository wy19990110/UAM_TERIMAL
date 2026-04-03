"""Network design solution data structure."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class NetworkDesign:
    """A network design solution: which edges/connectors are active, flow allocation.

    Attributes:
        active_edges: Set of activated backbone edge IDs.
        active_connectors: Set of activated connector arc IDs.
        flows: Dict mapping (arc_id, commodity, scenario) -> flow value.
            arc_id can be a backbone edge or connector.
        port_loads: Dict mapping (terminal_id, port_id, scenario) -> load lambda.
        unmet: Dict mapping (commodity, scenario) -> unmet demand.
        objective: Objective value from the solving model (model-specific).
        truth_objective: Objective value under truth evaluation.
    """

    active_edges: set[str] = field(default_factory=set)
    active_connectors: set[str] = field(default_factory=set)
    flows: dict[tuple[str, str, str], float] = field(default_factory=dict)
    port_loads: dict[tuple[str, str, str], float] = field(default_factory=dict)
    unmet: dict[tuple[str, str], float] = field(default_factory=dict)
    objective: float = float("inf")
    truth_objective: float = float("inf")

    @property
    def active_backbone_set(self) -> set[str]:
        return self.active_edges

    def topology_distance_backbone(self, other: NetworkDesign) -> float:
        """Jaccard distance on backbone edge sets."""
        union = self.active_edges | other.active_edges
        if not union:
            return 0.0
        intersection = self.active_edges & other.active_edges
        return 1.0 - len(intersection) / len(union)

    def topology_distance_connectors(self, other: NetworkDesign) -> float:
        """Jaccard distance on connector arc sets."""
        union = self.active_connectors | other.active_connectors
        if not union:
            return 0.0
        intersection = self.active_connectors & other.active_connectors
        return 1.0 - len(intersection) / len(union)

    def total_unmet(self, scenario_id: str) -> float:
        return sum(v for (_, s), v in self.unmet.items() if s == scenario_id)
