"""Access truth model: direction-based admissibility.

A^truth_{t,h,e} = 1{|wrap(θ_e - θ_{t,h})| ≤ β_{t,h}}
                · 1{e ∉ Z_t(ω)}
                · 1{regime rule satisfied}
"""

from __future__ import annotations

from uam.core.terminal import TerminalConfig
from uam.core.graph import CandidateGraph, BackboneEdge


def compute_admissibility(
    terminal: TerminalConfig,
    edge: BackboneEdge,
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> dict[str, bool]:
    """Compute admissibility for each port of a terminal w.r.t. a backbone edge.

    Returns:
        Dict mapping port_id -> bool (admissible or not).
    """
    # Edge must be incident to this terminal
    tid = terminal.terminal_id
    if edge.u != tid and edge.v != tid:
        return {p.port_id: False for p in terminal.ports}

    # Direction of the edge as seen from this terminal
    theta_e = graph.compute_edge_direction(edge, tid)

    # Context-dependent blocked edges
    context_blocked = terminal.context_blocked_edges.get(context_state, set())

    result = {}
    for port in terminal.ports:
        # Direction check
        dir_ok = port.admits_direction(theta_e)

        # Not in blocked set
        not_blocked = edge.edge_id not in terminal.blocked_edges
        not_context_blocked = edge.edge_id not in context_blocked

        result[port.port_id] = dir_ok and not_blocked and not_context_blocked

    return result


def build_full_admissibility(
    graph: CandidateGraph,
    context_state: str = "relaxed",
) -> dict[tuple[str, str, str], bool]:
    """Build the full admissibility matrix A^truth for all (terminal, port, edge) triples.

    Returns:
        Dict mapping (terminal_id, port_id, edge_id) -> bool.
    """
    A: dict[tuple[str, str, str], bool] = {}
    for tid, terminal in graph.terminals.items():
        for edge in graph.edges_incident_to(tid):
            port_adm = compute_admissibility(terminal, edge, graph, context_state)
            for port_id, admissible in port_adm.items():
                A[(tid, port_id, edge.edge_id)] = admissible
    return A
