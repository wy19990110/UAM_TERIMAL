"""Incumbent baseline abstractions for EXP-6/7/8 external benchmarking.

B0: node + aggregate terminal surrogate (literature incumbent).
    Identical formulation to M0/S-only but explicitly named as the baseline
    that represents "what the literature does today".

B1: A-only or A+coarse-service (terminal-aware incumbent).
    Exposes admissibility constraints like M1 (AS), but uses a coarser
    service model — single aggregate service per terminal rather than
    per-port curves. This represents a "terminal-aware but not fully
    interface-decomposed" abstraction.

These baselines exist so that EXP-6/7 can answer: "Our ASF family beats
not just our own M0, but also plausible literature approaches."
"""

from __future__ import annotations

from dataclasses import dataclass, field

from uam.core.terminal import TerminalConfig
from uam.core.graph import CandidateGraph
from uam.interface.s_only import SOnlyInterface, extract_s_only
from uam.truth.access import build_full_admissibility
from uam.truth.service import fit_aggregate_service


@dataclass
class B0Interface:
    """B0: node + aggregate surrogate (identical to S-only, explicit incumbent label).

    This is the standard literature abstraction: terminal is a node with
    aggregate capacity/delay, no admissibility, no footprint.
    """

    terminal_id: str
    a_bar: float
    b_bar: float

    def service_cost(self, total_load: float) -> float:
        return self.a_bar * total_load + self.b_bar * total_load ** 2


@dataclass
class B1Interface:
    """B1: A + coarse service (terminal-aware incumbent).

    Exposes admissibility like M1, but uses aggregate (not per-port) service.
    This represents a hypothetical literature approach that knows about
    terminal access constraints but does not decompose service by port.
    """

    terminal_id: str
    admissibility: dict[tuple[str, str, str], bool]
    a_bar: float  # aggregate linear coefficient
    b_bar: float  # aggregate quadratic coefficient

    def is_admissible(self, port_id: str, edge_id: str) -> bool:
        return self.admissibility.get((self.terminal_id, port_id, edge_id), False)

    def service_cost(self, total_load: float) -> float:
        return self.a_bar * total_load + self.b_bar * total_load ** 2


def extract_b0(terminal: TerminalConfig) -> B0Interface:
    """Extract B0 incumbent interface from truth model.

    Identical extraction to M0/S-only.
    """
    a_bar, b_bar = fit_aggregate_service(terminal)
    return B0Interface(
        terminal_id=terminal.terminal_id,
        a_bar=a_bar,
        b_bar=b_bar,
    )


def extract_b1(
    terminal: TerminalConfig,
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> B1Interface:
    """Extract B1 incumbent interface: admissibility + aggregate service.

    Takes admissibility from truth (same as M1), but service is aggregate
    (same as M0). This is the "knows about access, doesn't decompose service"
    middle ground.
    """
    full_adm = build_full_admissibility(graph, context_state)
    adm = {k: v for k, v in full_adm.items() if k[0] == terminal.terminal_id}
    a_bar, b_bar = fit_aggregate_service(terminal)
    return B1Interface(
        terminal_id=terminal.terminal_id,
        admissibility=adm,
        a_bar=a_bar,
        b_bar=b_bar,
    )
