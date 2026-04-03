"""Candidate graph and port-augmented graph data structures."""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import networkx as nx

from .terminal import TerminalConfig


@dataclass
class BackboneEdge:
    """A candidate backbone corridor between two nodes.

    Nodes can be terminals or waypoints.
    """

    edge_id: str
    u: str  # origin node id
    v: str  # destination node id
    length: float = 1.0
    construction_cost: float = 1.0
    travel_cost: float = 1.0
    capacity: float = 50.0

    @property
    def direction_deg_from(self) -> float | None:
        """Direction is computed externally from node positions."""
        return None  # Set after graph construction


@dataclass
class ConnectorArc:
    """A connector arc linking a backbone edge to a terminal port.

    Represents the approach/departure path from the backbone network
    into a specific port of a terminal.
    """

    arc_id: str
    edge_id: str  # which backbone edge this connects to
    terminal_id: str
    port_id: str
    direction_deg: float = 0.0  # incoming direction at the terminal
    travel_cost: float = 0.1


@dataclass
class CandidateGraph:
    """The base candidate graph before port augmentation.

    Contains terminals, waypoints, and backbone edges.
    """

    terminals: dict[str, TerminalConfig] = field(default_factory=dict)
    waypoints: dict[str, tuple[float, float]] = field(default_factory=dict)
    backbone_edges: dict[str, BackboneEdge] = field(default_factory=dict)

    def all_node_positions(self) -> dict[str, tuple[float, float]]:
        pos = {}
        for tid, t in self.terminals.items():
            pos[tid] = (t.x, t.y)
        pos.update(self.waypoints)
        return pos

    def compute_edge_direction(self, edge: BackboneEdge, from_node: str) -> float:
        """Compute the direction (degrees) of an edge as seen from from_node."""
        pos = self.all_node_positions()
        if from_node not in pos:
            return 0.0
        x0, y0 = pos[from_node]
        to_node = edge.v if edge.u == from_node else edge.u
        if to_node not in pos:
            return 0.0
        x1, y1 = pos[to_node]
        return math.degrees(math.atan2(y1 - y0, x1 - x0)) % 360

    def edges_incident_to(self, node_id: str) -> list[BackboneEdge]:
        return [
            e
            for e in self.backbone_edges.values()
            if e.u == node_id or e.v == node_id
        ]

    def neighborhood_edges(self, terminal_id: str, hops: int = 1) -> list[str]:
        """Return edge IDs within `hops` hops of a terminal in the backbone."""
        g = nx.Graph()
        for e in self.backbone_edges.values():
            g.add_edge(e.u, e.v, edge_id=e.edge_id)
        if terminal_id not in g:
            return []
        nearby_nodes = set(
            nx.single_source_shortest_path_length(g, terminal_id, cutoff=hops).keys()
        )
        result = []
        for e in self.backbone_edges.values():
            if e.u in nearby_nodes and e.v in nearby_nodes:
                result.append(e.edge_id)
        return result


@dataclass
class PortAugmentedGraph:
    """The port-augmented candidate graph G+ = (V ∪ P, E ∪ E^conn).

    Extends the CandidateGraph with connector arcs linking backbone edges
    to terminal ports, based on the admissibility truth model.
    """

    base: CandidateGraph = field(default_factory=CandidateGraph)
    connectors: dict[str, ConnectorArc] = field(default_factory=dict)

    # Admissibility matrix: (terminal_id, port_id, edge_id) -> bool
    admissibility: dict[tuple[str, str, str], bool] = field(default_factory=dict)

    @property
    def terminals(self) -> dict[str, TerminalConfig]:
        return self.base.terminals

    @property
    def backbone_edges(self) -> dict[str, BackboneEdge]:
        return self.base.backbone_edges

    def connectors_for_port(self, terminal_id: str, port_id: str) -> list[ConnectorArc]:
        return [
            c
            for c in self.connectors.values()
            if c.terminal_id == terminal_id and c.port_id == port_id
        ]

    def connectors_for_edge(self, edge_id: str, terminal_id: str) -> list[ConnectorArc]:
        return [
            c
            for c in self.connectors.values()
            if c.edge_id == edge_id and c.terminal_id == terminal_id
        ]
