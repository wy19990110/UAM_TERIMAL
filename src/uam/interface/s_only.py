"""M0: S-only interface — aggregate service curve, no admissibility, no footprint.

Terminal is a plain node with:
    L̃^(0)(Λ) = ā Λ + b̄ Λ²
"""

from __future__ import annotations

from dataclasses import dataclass

from uam.core.terminal import TerminalConfig
from uam.truth.service import fit_aggregate_service


@dataclass
class SOnlyInterface:
    """S-only (M0) interface for a terminal.

    All connectors are admissible.  No footprint penalties.
    Service cost is a scalar function of total load only.
    """

    terminal_id: str
    a_bar: float  # aggregate linear coefficient
    b_bar: float  # aggregate quadratic coefficient

    def service_cost(self, total_load: float) -> float:
        return self.a_bar * total_load + self.b_bar * total_load ** 2

    def service_gradient(self, total_load: float) -> float:
        return self.a_bar + 2 * self.b_bar * total_load


def extract_s_only(terminal: TerminalConfig) -> SOnlyInterface:
    """Extract M0 interface from truth model."""
    a_bar, b_bar = fit_aggregate_service(terminal)
    return SOnlyInterface(
        terminal_id=terminal.terminal_id,
        a_bar=a_bar,
        b_bar=b_bar,
    )
