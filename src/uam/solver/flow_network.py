"""Build a directed flow network from the port-augmented graph.

The flow network has:
  - Backbone nodes (terminals + waypoints)
  - Port nodes: "port_{terminal_id}_{port_id}"
  - Backbone arcs (both directions for each undirected edge)
  - Connector arcs: terminal backbone node -> port node (for destination)
                    port node -> terminal backbone node (for origin)

Demand: source backbone node -> destination port nodes (any port of the destination terminal).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from uam.core.graph import PortAugmentedGraph


@dataclass
class FlowArc:
    arc_id: str
    tail: str  # from node
    head: str  # to node
    cost: float = 0.0
    capacity: float = float("inf")
    is_backbone: bool = False
    backbone_edge_id: str | None = None  # link back to backbone edge
    is_connector: bool = False
    connector_id: str | None = None
    terminal_id: str | None = None
    port_id: str | None = None


def build_flow_network(graph: PortAugmentedGraph) -> tuple[list[str], list[FlowArc]]:
    """Build a directed flow network.

    Returns:
        (nodes, arcs)
    """
    nodes = set()
    arcs: list[FlowArc] = []

    # Backbone nodes
    for tid in graph.terminals:
        nodes.add(tid)
    for wid in graph.base.waypoints:
        nodes.add(wid)

    # Port nodes
    for tid, terminal in graph.terminals.items():
        for port in terminal.ports:
            nodes.add(f"port_{tid}_{port.port_id}")

    # Backbone arcs (both directions for each undirected edge)
    for eid, edge in graph.backbone_edges.items():
        arcs.append(FlowArc(
            arc_id=f"{eid}_fwd", tail=edge.u, head=edge.v,
            cost=edge.travel_cost, capacity=edge.capacity,
            is_backbone=True, backbone_edge_id=eid,
        ))
        arcs.append(FlowArc(
            arc_id=f"{eid}_rev", tail=edge.v, head=edge.u,
            cost=edge.travel_cost, capacity=edge.capacity,
            is_backbone=True, backbone_edge_id=eid,
        ))

    # Connector arcs: terminal backbone node <-> port node
    for cid, conn in graph.connectors.items():
        port_node = f"port_{conn.terminal_id}_{conn.port_id}"
        # Inbound: backbone node -> port (for traffic arriving at terminal)
        arcs.append(FlowArc(
            arc_id=f"{cid}_in", tail=conn.terminal_id, head=port_node,
            cost=conn.travel_cost, capacity=float("inf"),
            is_connector=True, connector_id=cid,
            terminal_id=conn.terminal_id, port_id=conn.port_id,
        ))
        # Outbound: port -> backbone node (for traffic departing from terminal)
        arcs.append(FlowArc(
            arc_id=f"{cid}_out", tail=port_node, head=conn.terminal_id,
            cost=conn.travel_cost, capacity=float("inf"),
            is_connector=True, connector_id=cid,
            terminal_id=conn.terminal_id, port_id=conn.port_id,
        ))

    return sorted(nodes), arcs


def get_sink_nodes(graph: PortAugmentedGraph, terminal_id: str) -> list[str]:
    """Get all port nodes for a terminal (potential sink nodes for demand to this terminal)."""
    terminal = graph.terminals.get(terminal_id)
    if not terminal:
        return [terminal_id]  # fallback: backbone node
    return [f"port_{terminal_id}_{p.port_id}" for p in terminal.ports]


def get_source_nodes(graph: PortAugmentedGraph, terminal_id: str) -> list[str]:
    """Get source nodes for a terminal.

    If source is a terminal with ports, traffic originates from port nodes.
    If source is a waypoint, traffic originates from the waypoint backbone node.
    """
    if terminal_id in graph.terminals:
        terminal = graph.terminals[terminal_id]
        return [f"port_{terminal_id}_{p.port_id}" for p in terminal.ports]
    return [terminal_id]
