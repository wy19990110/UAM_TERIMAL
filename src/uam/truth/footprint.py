"""Footprint truth model: neighborhood penalty and blocked edges.

X^truth_t(x, λ_t; ω) = Σ_{e ∈ E_loc(t)} (π̄_{t,e}(ω) + Σ_h ρ_{t,e,h} λ_{t,h}) x_e
                       + M Σ_{e ∈ B_t(ω)} x_e
"""

from __future__ import annotations

from uam.core.terminal import TerminalConfig
from uam.core.graph import CandidateGraph

BIG_M = 1e4


def compute_footprint_cost(
    terminal: TerminalConfig,
    graph: CandidateGraph,
    active_edges: set[str],
    port_loads: dict[str, float],
    context_state: str = "relaxed",
) -> float:
    """Compute the truth footprint cost X^truth for a terminal.

    Args:
        terminal: Terminal configuration.
        graph: Candidate graph (for neighborhood computation).
        active_edges: Set of activated backbone edge IDs.
        port_loads: Dict mapping port_id -> load.
        context_state: Current context state.

    Returns:
        Total footprint cost X^truth_t.
    """
    cost = 0.0
    neighborhood = graph.neighborhood_edges(
        terminal.terminal_id, terminal.footprint_radius_hops
    )

    # Soft penalties on neighborhood edges
    for eid in neighborhood:
        if eid not in active_edges:
            continue

        # Base penalty
        base_pi = terminal.footprint_base_penalty.get(eid, 0.0)

        # Load-dependent penalty
        load_pi = 0.0
        for port in terminal.ports:
            rho = terminal.footprint_load_sensitivity.get(
                (eid, port.port_id), 0.0
            )
            load_pi += rho * port_loads.get(port.port_id, 0.0)

        cost += base_pi + load_pi

    # Hard-blocked edges (big-M penalty)
    blocked = set(terminal.blocked_edges)
    context_blocked = terminal.context_blocked_edges.get(context_state, set())
    all_blocked = blocked | context_blocked

    for eid in all_blocked:
        if eid in active_edges:
            cost += BIG_M

    return cost


def extract_nominal_footprint(
    terminal: TerminalConfig,
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> tuple[dict[str, float], set[str]]:
    """Extract nominal footprint for M2 (ASF interface).

    Evaluates footprint penalties at nominal (zero) load to get π̃_{t,e},
    and collects blocked edges B̃_t.

    Returns:
        (pi_tilde, blocked_tilde):
            pi_tilde: Dict mapping edge_id -> nominal penalty.
            blocked_tilde: Set of hard-blocked edge IDs.
    """
    neighborhood = graph.neighborhood_edges(
        terminal.terminal_id, terminal.footprint_radius_hops
    )

    pi_tilde = {}
    for eid in neighborhood:
        base_pi = terminal.footprint_base_penalty.get(eid, 0.0)
        if base_pi > 0:
            pi_tilde[eid] = base_pi

    blocked = set(terminal.blocked_edges)
    context_blocked = terminal.context_blocked_edges.get(context_state, set())
    blocked_tilde = blocked | context_blocked

    return pi_tilde, blocked_tilde
