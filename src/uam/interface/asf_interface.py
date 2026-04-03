"""M2: ASF interface — admissibility + per-port service + nominal footprint.

Extends M1 (AS) with:
    X̃^(2)(x) = Σ_{e ∈ E_loc(t)} π̃_{t,e} x_e + M Σ_{e ∈ B̃_t} x_e
"""

from __future__ import annotations

from dataclasses import dataclass, field

from uam.core.terminal import TerminalConfig
from uam.core.graph import CandidateGraph
from uam.interface.as_interface import ASInterface, extract_as_interface
from uam.truth.footprint import extract_nominal_footprint, BIG_M


@dataclass
class ASFInterface:
    """ASF (M2) interface for a terminal.

    Extends AS with nominal footprint penalties.
    """

    as_iface: ASInterface
    nominal_penalty: dict[str, float] = field(default_factory=dict)  # edge_id -> π̃
    blocked_edges: set[str] = field(default_factory=set)

    @property
    def terminal_id(self) -> str:
        return self.as_iface.terminal_id

    def is_admissible(self, port_id: str, edge_id: str) -> bool:
        return self.as_iface.is_admissible(port_id, edge_id)

    def service_cost(self, port_loads: dict[str, float]) -> float:
        return self.as_iface.service_cost(port_loads)

    def footprint_cost(self, active_edges: set[str]) -> float:
        cost = 0.0
        for eid, pi in self.nominal_penalty.items():
            if eid in active_edges:
                cost += pi
        for eid in self.blocked_edges:
            if eid in active_edges:
                cost += BIG_M
        return cost


def extract_asf_interface(
    terminal: TerminalConfig,
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> ASFInterface:
    """Extract M2 (ASF) interface from truth model."""
    as_iface = extract_as_interface(terminal, graph, context_state)
    pi_tilde, blocked_tilde = extract_nominal_footprint(
        terminal, graph, context_state
    )
    return ASFInterface(
        as_iface=as_iface,
        nominal_penalty=pi_tilde,
        blocked_edges=blocked_tilde,
    )
