"""M1: AS interface — admissibility + per-port separable service, no footprint.

Terminal exposes:
    A_{t,h,e}: admissibility matrix (from truth)
    L̃^(1)(λ) = Σ_h (ã_{t,h} λ_{t,h} + b̃_{t,h} λ_{t,h}²)
"""

from __future__ import annotations

from dataclasses import dataclass, field

from uam.core.terminal import TerminalConfig
from uam.core.graph import CandidateGraph
from uam.truth.access import build_full_admissibility
from uam.truth.service import fit_port_service


@dataclass
class PortServiceParams:
    """Per-port separable service parameters."""

    port_id: str
    a_tilde: float
    b_tilde: float

    def cost(self, load: float) -> float:
        return self.a_tilde * load + self.b_tilde * load ** 2

    def gradient(self, load: float) -> float:
        return self.a_tilde + 2 * self.b_tilde * load


@dataclass
class ASInterface:
    """AS (M1) interface for a terminal.

    Exposes admissibility and per-port service curves.
    No cross-port coupling. No footprint.
    """

    terminal_id: str
    admissibility: dict[tuple[str, str, str], bool]  # (tid, port_id, edge_id) -> bool
    port_service: dict[str, PortServiceParams] = field(default_factory=dict)

    def is_admissible(self, port_id: str, edge_id: str) -> bool:
        return self.admissibility.get((self.terminal_id, port_id, edge_id), False)

    def service_cost(self, port_loads: dict[str, float]) -> float:
        total = 0.0
        for pid, lam in port_loads.items():
            if pid in self.port_service:
                total += self.port_service[pid].cost(lam)
        return total

    def service_gradient(self, port_loads: dict[str, float]) -> dict[str, float]:
        return {
            pid: self.port_service[pid].gradient(lam)
            for pid, lam in port_loads.items()
            if pid in self.port_service
        }


def extract_as_interface(
    terminal: TerminalConfig,
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> ASInterface:
    """Extract M1 (AS) interface from truth model."""
    # Admissibility from truth
    full_adm = build_full_admissibility(graph, context_state)
    # Filter to this terminal
    adm = {k: v for k, v in full_adm.items() if k[0] == terminal.terminal_id}

    # Per-port service fitting
    port_svc = {}
    for port in terminal.ports:
        a_t, b_t = fit_port_service(terminal, port.port_id)
        port_svc[port.port_id] = PortServiceParams(port.port_id, a_t, b_t)

    return ASInterface(
        terminal_id=terminal.terminal_id,
        admissibility=adm,
        port_service=port_svc,
    )
