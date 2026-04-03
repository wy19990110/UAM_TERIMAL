"""Synthetic candidate graph generators: G1 (sparse), G2 (dense), G3 (airport-adjacent).

Generation procedure:
1. Place terminals and waypoints on a unit square
2. Build MST for backbone connectivity
3. Add shortest non-crossing edges up to target density
4. For each terminal port, create connectors to incident backbone edges
5. Compute admissibility from truth access model
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

import networkx as nx
import numpy as np

from uam.core.terminal import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc
from uam.truth.access import build_full_admissibility


@dataclass
class GraphSpec:
    """Specification for a graph family."""
    n_terminals: int
    n_waypoints: int
    target_edges: tuple[int, int]  # (min, max) backbone edges
    has_airport_zone: bool = False
    airport_zone_center: tuple[float, float] = (0.5, 0.5)
    airport_zone_radius: float = 0.15


# Predefined graph families
G1_SPEC = GraphSpec(n_terminals=8, n_waypoints=6, target_edges=(18, 22))
G2_SPEC = GraphSpec(n_terminals=10, n_waypoints=8, target_edges=(26, 32))
G3_SPEC = GraphSpec(
    n_terminals=6, n_waypoints=6, target_edges=(18, 25),
    has_airport_zone=True, airport_zone_center=(0.8, 0.5), airport_zone_radius=0.15,
)


def generate_terminal_config(
    tid: str,
    x: float, y: float,
    n_ports: int,
    seed: int,
    spec: GraphSpec,
    *,
    access_restrictiveness: float = 0.25,
    service_asymmetry: float = 1.0,
    footprint_severity: float = 0.0,
) -> TerminalConfig:
    """Generate a parameterized terminal configuration.

    Args:
        access_restrictiveness: α_A ∈ [0, 0.5]. Higher = narrower sectors.
        service_asymmetry: κ_S ∈ [1, 3]. Ratio of max/min port service cost.
        footprint_severity: φ_F ∈ [0, 0.5]. Fraction of neighborhood edges with penalty.
    """
    rng = random.Random(seed)

    # Port directions: spread evenly around the circle
    base_angle = rng.uniform(0, 360)
    ports = []
    for i in range(n_ports):
        direction = (base_angle + i * 360 / n_ports) % 360
        # Sector width decreases with access_restrictiveness
        sector_hw = max(15, 50 - 70 * access_restrictiveness)

        # Service asymmetry: first port is cheap, others get progressively expensive
        ratio = 1.0 + (service_asymmetry - 1.0) * i / max(n_ports - 1, 1)
        a = 0.1 + rng.uniform(0, 0.1)
        b = (0.2 + rng.uniform(0, 0.2)) * ratio

        ports.append(PortConfig(
            port_id=f"h{i+1}",
            direction_deg=direction,
            sector_half_width_deg=sector_hw,
            a=a,
            b=b,
        ))

    # Cross-port coupling (only between adjacent ports)
    coupling = {}
    for i in range(n_ports):
        for j in range(i + 1, n_ports):
            coupling[(f"h{i+1}", f"h{j+1}")] = rng.uniform(0.05, 0.2)

    # Context type
    context = "open-city"
    if spec.has_airport_zone:
        dist_to_airport = math.hypot(x - spec.airport_zone_center[0], y - spec.airport_zone_center[1])
        if dist_to_airport < spec.airport_zone_radius * 2:
            context = "airport-adjacent"

    # Organization
    org = rng.choice(["direct", "single-ring", "multi-ring"])
    proc = rng.choice(["procedure-like", "path-like"])

    return TerminalConfig(
        terminal_id=tid,
        x=x, y=y,
        ports=ports,
        pads=rng.randint(1, 3),
        gates=rng.choice([0, 2, 4]),
        organization=org,
        procedure_type=proc,
        context_type=context,
        mu_bar=3.0 + rng.uniform(0, 3),
        psi_sat=rng.uniform(1, 5),
        cross_port_coupling=coupling,
        footprint_radius_hops=1,
    )


def generate_synthetic_graph(
    spec: GraphSpec,
    seed: int = 42,
    *,
    demand_intensity: float = 1.0,
    access_restrictiveness: float = 0.25,
    service_asymmetry: float = 1.0,
    footprint_severity: float = 0.0,
) -> PortAugmentedGraph:
    """Generate a complete port-augmented graph from a family specification.

    Returns:
        PortAugmentedGraph with terminals, waypoints, backbone, connectors, admissibility.
    """
    rng = random.Random(seed)
    np_rng = np.random.RandomState(seed)

    # --- Place nodes ---
    all_positions = {}
    terminals = {}

    for i in range(spec.n_terminals):
        tid = f"T{i+1}"
        x, y = np_rng.uniform(0.05, 0.95, 2)
        n_ports = rng.choice([1, 2, 3])
        t = generate_terminal_config(
            tid, x, y, n_ports, seed + i * 100, spec,
            access_restrictiveness=access_restrictiveness,
            service_asymmetry=service_asymmetry,
            footprint_severity=footprint_severity,
        )
        terminals[tid] = t
        all_positions[tid] = (x, y)

    waypoints = {}
    for i in range(spec.n_waypoints):
        wid = f"W{i+1}"
        x, y = np_rng.uniform(0.05, 0.95, 2)
        waypoints[wid] = (x, y)
        all_positions[wid] = (x, y)

    # --- Build backbone edges ---
    node_ids = list(all_positions.keys())
    n_nodes = len(node_ids)

    # Compute all pairwise distances
    dist_matrix = {}
    for i, u in enumerate(node_ids):
        for j, v in enumerate(node_ids):
            if i < j:
                d = math.hypot(
                    all_positions[u][0] - all_positions[v][0],
                    all_positions[u][1] - all_positions[v][1],
                )
                dist_matrix[(u, v)] = d

    # MST for connectivity
    g = nx.Graph()
    for (u, v), d in dist_matrix.items():
        g.add_edge(u, v, weight=d)
    mst = nx.minimum_spanning_tree(g)

    backbone = {}
    edge_idx = 0
    for u, v, data in mst.edges(data=True):
        edge_idx += 1
        eid = f"E{edge_idx}"
        d = data["weight"]
        backbone[eid] = BackboneEdge(
            edge_id=eid, u=u, v=v,
            length=d,
            construction_cost=d * (0.8 + rng.random() * 0.4),
            travel_cost=d * (0.5 + rng.random() * 0.5),
            capacity=20 + rng.randint(0, 30),
        )

    # Add more edges up to target density
    remaining = sorted(
        [(d, u, v) for (u, v), d in dist_matrix.items() if not mst.has_edge(u, v)],
    )
    target = rng.randint(*spec.target_edges)
    for d, u, v in remaining:
        if len(backbone) >= target:
            break
        edge_idx += 1
        eid = f"E{edge_idx}"
        backbone[eid] = BackboneEdge(
            edge_id=eid, u=u, v=v,
            length=d,
            construction_cost=d * (0.8 + rng.random() * 0.4),
            travel_cost=d * (0.5 + rng.random() * 0.5),
            capacity=20 + rng.randint(0, 30),
        )

    base_graph = CandidateGraph(
        terminals=terminals,
        waypoints=waypoints,
        backbone_edges=backbone,
    )

    # --- Footprint: assign penalties based on severity ---
    for tid, terminal in terminals.items():
        neighborhood = base_graph.neighborhood_edges(tid, 1)
        n_penalized = int(len(neighborhood) * footprint_severity)
        if n_penalized > 0:
            penalized = rng.sample(neighborhood, min(n_penalized, len(neighborhood)))
            for eid in penalized:
                terminal.footprint_base_penalty[eid] = rng.uniform(0.5, 2.0)
            # Block some edges (half of penalized, rounded down)
            n_blocked = max(0, n_penalized // 2)
            for eid in penalized[:n_blocked]:
                terminal.blocked_edges.add(eid)

    # --- Build connectors and admissibility ---
    admissibility = build_full_admissibility(base_graph)

    connectors = {}
    conn_idx = 0
    for (tid, pid, eid), is_adm in admissibility.items():
        if is_adm:
            conn_idx += 1
            cid = f"C{conn_idx}"
            direction = base_graph.compute_edge_direction(base_graph.backbone_edges[eid], tid)
            connectors[cid] = ConnectorArc(
                cid, eid, tid, pid, direction,
                travel_cost=0.05 + rng.random() * 0.05,
            )

    return PortAugmentedGraph(
        base=base_graph,
        connectors=connectors,
        admissibility=admissibility,
    )


def generate_demand(
    graph: PortAugmentedGraph,
    intensity: float = 1.0,
    seed: int = 42,
    coverage: float = 0.4,
) -> list:
    """Generate demand scenarios for a graph.

    Args:
        intensity: ρ multiplier on base demand.
        seed: Random seed.
        coverage: Fraction of OD pairs with demand.

    Returns:
        List with one DemandScenario.
    """
    from uam.core.demand import DemandScenario

    rng = random.Random(seed)
    tids = list(graph.terminals.keys())
    od = {}
    for src in tids:
        for dst in tids:
            if src == dst:
                continue
            if rng.random() < coverage:
                base = 1.0 + rng.random() * 2.0
                od[(src, dst)] = base * intensity

    return [DemandScenario(
        scenario_id="w1",
        od_demand=od,
        probability=1.0,
        unmet_penalty=100.0,
    )]
