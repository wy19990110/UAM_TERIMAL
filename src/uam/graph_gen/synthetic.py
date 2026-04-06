"""Synthetic candidate graph generators with port-aligned terminal creation.

Key design: terminals are created AFTER backbone edges, so port directions
can be aligned to actual incident edge directions. This ensures every terminal
has at least one admissible connector.
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
    n_terminals: int
    n_waypoints: int
    target_edges: tuple[int, int]
    has_airport_zone: bool = False
    airport_zone_center: tuple[float, float] = (0.5, 0.5)
    airport_zone_radius: float = 0.15


G1_SPEC = GraphSpec(n_terminals=8, n_waypoints=6, target_edges=(18, 22))
G2_SPEC = GraphSpec(n_terminals=10, n_waypoints=8, target_edges=(26, 32))
G3_SPEC = GraphSpec(
    n_terminals=6, n_waypoints=6, target_edges=(18, 25),
    has_airport_zone=True, airport_zone_center=(0.8, 0.5), airport_zone_radius=0.15,
)
G1_SMALL = GraphSpec(n_terminals=4, n_waypoints=3, target_edges=(8, 10))
G2_SMALL = GraphSpec(n_terminals=5, n_waypoints=4, target_edges=(10, 14))
G3_SMALL = GraphSpec(
    n_terminals=3, n_waypoints=3, target_edges=(7, 10),
    has_airport_zone=True, airport_zone_center=(0.8, 0.5), airport_zone_radius=0.15,
)
# G4ap: airport-adjacent (EXP-4D mixed regime)
G4_SPEC = GraphSpec(
    n_terminals=6, n_waypoints=4, target_edges=(15, 20),
    has_airport_zone=True, airport_zone_center=(0.7, 0.5), airport_zone_radius=0.18,
)
G4_SMALL = GraphSpec(
    n_terminals=3, n_waypoints=3, target_edges=(7, 10),
    has_airport_zone=True, airport_zone_center=(0.7, 0.5), airport_zone_radius=0.18,
)
# Small/medium specs for EXP-7 (integrated upper bound, need exact solve)
JO_SMALL = GraphSpec(n_terminals=3, n_waypoints=2, target_edges=(5, 7))
JO_MEDIUM = GraphSpec(n_terminals=5, n_waypoints=3, target_edges=(10, 14))


def generate_synthetic_graph(
    spec: GraphSpec,
    seed: int = 42,
    *,
    demand_intensity: float = 1.0,
    access_restrictiveness: float = 0.25,
    service_asymmetry: float = 1.0,
    footprint_severity: float = 0.0,
    coupling_m: float | None = None,
    psi_sat: float | None = None,
    port_misalign_deg: float = 0.0,
    extra_connectors_per_port: int = 0,
) -> PortAugmentedGraph:
    rng = random.Random(seed)
    np_rng = np.random.RandomState(seed)

    # --- 1. Place nodes ---
    positions: dict[str, tuple[float, float]] = {}
    terminal_ids = []
    for i in range(spec.n_terminals):
        tid = f"T{i+1}"
        positions[tid] = tuple(np_rng.uniform(0.05, 0.95, 2))
        terminal_ids.append(tid)

    waypoints: dict[str, tuple[float, float]] = {}
    for i in range(spec.n_waypoints):
        wid = f"W{i+1}"
        pos = tuple(np_rng.uniform(0.05, 0.95, 2))
        positions[wid] = pos
        waypoints[wid] = pos

    # --- 2. Build backbone edges (MST + extra) ---
    node_ids = list(positions.keys())
    dist_pairs = []
    for i, u in enumerate(node_ids):
        for j, v in enumerate(node_ids):
            if i < j:
                d = math.hypot(positions[u][0] - positions[v][0],
                               positions[u][1] - positions[v][1])
                dist_pairs.append((d, u, v))

    g = nx.Graph()
    for d, u, v in dist_pairs:
        g.add_edge(u, v, weight=d)
    mst = nx.minimum_spanning_tree(g)

    backbone: dict[str, BackboneEdge] = {}
    eidx = 0
    for u, v, data in mst.edges(data=True):
        eidx += 1
        d = data["weight"]
        backbone[f"E{eidx}"] = BackboneEdge(
            f"E{eidx}", u, v, d,
            construction_cost=d * (0.8 + rng.random() * 0.4),
            travel_cost=d * (0.5 + rng.random() * 0.5),
            capacity=20 + rng.randint(0, 30),
        )

    remaining = sorted([(d, u, v) for d, u, v in dist_pairs if not mst.has_edge(u, v)])
    target = rng.randint(*spec.target_edges)
    for d, u, v in remaining:
        if len(backbone) >= target:
            break
        eidx += 1
        backbone[f"E{eidx}"] = BackboneEdge(
            f"E{eidx}", u, v, d,
            construction_cost=d * (0.8 + rng.random() * 0.4),
            travel_cost=d * (0.5 + rng.random() * 0.5),
            capacity=20 + rng.randint(0, 30),
        )

    # --- 3. Create terminals with port directions aligned to incident edges ---
    terminals: dict[str, TerminalConfig] = {}
    for tid in terminal_ids:
        tx, ty = positions[tid]

        # Find incident edge directions
        incident_dirs = []
        for eid, edge in backbone.items():
            if edge.u == tid or edge.v == tid:
                other = edge.v if edge.u == tid else edge.u
                ox, oy = positions[other]
                angle = math.degrees(math.atan2(oy - ty, ox - tx)) % 360
                incident_dirs.append((angle, eid))

        # Create ports: cluster incident edges into port groups
        n_incident = len(incident_dirs)
        if n_incident == 0:
            n_ports = 1
        else:
            n_ports = min(rng.choice([1, 2, 3]), n_incident)

        # Sort by direction, then assign to ports round-robin
        incident_dirs.sort()

        # Port directions: if we have n_ports, place them at the centroid of their assigned edges
        sector_hw = max(15, 50 - 70 * access_restrictiveness)

        if n_incident == 0:
            port_dirs = [rng.uniform(0, 360)]
        elif n_ports == 1:
            # Single port covers all directions — use wide sector
            port_dirs = [incident_dirs[len(incident_dirs) // 2][0]]
            sector_hw = max(sector_hw, 180 / max(n_incident, 1) + 30)
        else:
            # Spread ports evenly, but center each on its assigned edges
            edges_per_port = [[] for _ in range(n_ports)]
            for idx, (angle, eid) in enumerate(incident_dirs):
                edges_per_port[idx % n_ports].append(angle)
            port_dirs = []
            for angles in edges_per_port:
                if angles:
                    # Circular mean
                    mean_sin = sum(math.sin(math.radians(a)) for a in angles) / len(angles)
                    mean_cos = sum(math.cos(math.radians(a)) for a in angles) / len(angles)
                    port_dirs.append(math.degrees(math.atan2(mean_sin, mean_cos)) % 360)
                else:
                    port_dirs.append(rng.uniform(0, 360))

        ports = []
        for i, pdir in enumerate(port_dirs):
            ratio = 1.0 + (service_asymmetry - 1.0) * i / max(len(port_dirs) - 1, 1)
            a = 0.1 + rng.uniform(0, 0.1)
            b = (0.2 + rng.uniform(0, 0.2)) * ratio
            ports.append(PortConfig(f"h{i+1}", pdir, sector_hw, a, b))

        # Port misalignment for A-sensitive proxies (EXP-5)
        if port_misalign_deg > 0:
            for p in ports:
                p.direction_deg = (p.direction_deg + rng.uniform(-port_misalign_deg, port_misalign_deg)) % 360

        coupling = {}
        for i in range(len(ports)):
            for j in range(i + 1, len(ports)):
                m_val = coupling_m if coupling_m is not None else rng.uniform(0.05, 0.2)
                coupling[(f"h{i+1}", f"h{j+1}")] = m_val

        context = "open-city"
        if spec.has_airport_zone:
            dist_ap = math.hypot(tx - spec.airport_zone_center[0], ty - spec.airport_zone_center[1])
            if dist_ap < spec.airport_zone_radius * 2:
                context = "airport-adjacent"

        effective_psi = psi_sat if psi_sat is not None else rng.uniform(1, 5)
        terminals[tid] = TerminalConfig(
            terminal_id=tid, x=tx, y=ty,
            ports=ports, pads=rng.randint(1, 3), gates=rng.choice([0, 2, 4]),
            organization=rng.choice(["direct", "single-ring", "multi-ring"]),
            procedure_type=rng.choice(["procedure-like", "path-like"]),
            context_type=context,
            mu_bar=3.0 + rng.uniform(0, 3), psi_sat=effective_psi,
            cross_port_coupling=coupling, footprint_radius_hops=1,
        )

    base = CandidateGraph(terminals=terminals, waypoints=waypoints, backbone_edges=backbone)

    # --- 4. Footprint ---
    for tid, terminal in terminals.items():
        neighborhood = base.neighborhood_edges(tid, 1)
        n_penalized = int(len(neighborhood) * footprint_severity)
        if n_penalized > 0:
            penalized = rng.sample(neighborhood, min(n_penalized, len(neighborhood)))
            for eid in penalized:
                terminal.footprint_base_penalty[eid] = rng.uniform(0.5, 2.0)
            for eid in penalized[: max(0, n_penalized // 2)]:
                terminal.blocked_edges.add(eid)

    # --- 5. Admissibility + connectors ---
    admissibility = build_full_admissibility(base)
    connectors: dict[str, ConnectorArc] = {}
    cidx = 0
    for (tid, pid, eid), ok in admissibility.items():
        if ok:
            cidx += 1
            cid = f"C{cidx}"
            d = base.compute_edge_direction(base.backbone_edges[eid], tid)
            connectors[cid] = ConnectorArc(cid, eid, tid, pid, d, 0.05 + rng.random() * 0.05)

    # Extra non-incident connectors for A-sensitive proxies (EXP-5)
    if extra_connectors_per_port > 0:
        all_eids = list(backbone.keys())
        for tid, terminal in terminals.items():
            for port in terminal.ports:
                existing = {c.edge_id for c in connectors.values()
                            if c.terminal_id == tid and c.port_id == port.port_id}
                non_incident = [e for e in all_eids if e not in existing]
                rng.shuffle(non_incident)
                for eid in non_incident[:extra_connectors_per_port]:
                    cidx += 1
                    cid = f"C{cidx}"
                    d = base.compute_edge_direction(backbone[eid], tid)
                    connectors[cid] = ConnectorArc(cid, eid, tid, port.port_id, d,
                                                   0.05 + rng.random() * 0.05)
                    # These are NOT admissible under truth — M0 doesn't know that
                    admissibility[(tid, port.port_id, eid)] = False

    return PortAugmentedGraph(base=base, connectors=connectors, admissibility=admissibility)


def generate_demand(
    graph: PortAugmentedGraph,
    intensity: float = 1.0,
    seed: int = 42,
    coverage: float = 0.4,
    concentration: float = 0.0,
    concentrate_on: str | None = None,
) -> list:
    """Generate demand scenarios.

    Args:
        concentration: 0.0 = uniform, 1.0 = all ODs target a single terminal.
            Used by EXP-4B-S to test S-channel activation under load concentration.
        concentrate_on: if set, this terminal gets the concentrated ODs.
    """
    from uam.core.demand import DemandScenario
    rng = random.Random(seed)
    tids = list(graph.terminals.keys())
    od = {}

    # Pick concentration target
    if concentrate_on is None and concentration > 0:
        concentrate_on = rng.choice(tids)

    for src in tids:
        for dst in tids:
            if src == dst:
                continue
            if rng.random() < coverage:
                base_demand = (1.0 + rng.random() * 2.0) * intensity
                # Boost demand toward concentration target
                if concentration > 0 and concentrate_on:
                    if dst == concentrate_on or src == concentrate_on:
                        base_demand *= 1.0 + concentration * 2.0
                    else:
                        base_demand *= max(0.3, 1.0 - concentration * 0.5)
                od[(src, dst)] = base_demand
    return [DemandScenario(scenario_id="w1", od_demand=od, probability=1.0, unmet_penalty=100.0)]


# --- Proxy graph generators for EXP-5 ---

def generate_a_sensitive_proxy(
    seed: int = 42,
    *,
    demand_intensity: float = 1.0,
    access_restrictiveness: float = 0.4,
) -> PortAugmentedGraph:
    """A-sensitive proxy: port directions offset from incident edges.

    Key: M0 sees extra (inadmissible) connectors and has no way to reject them.
    """
    return generate_synthetic_graph(
        G1_SMALL, seed=seed,
        demand_intensity=demand_intensity,
        access_restrictiveness=access_restrictiveness,
        service_asymmetry=1.0,
        footprint_severity=0.0,
        port_misalign_deg=45.0,
        extra_connectors_per_port=2,
    )


def generate_s_sensitive_proxy(
    seed: int = 42,
    *,
    demand_intensity: float = 1.0,
    coupling_m: float = 0.4,
    psi_sat: float = 3.0,
) -> PortAugmentedGraph:
    """S-sensitive proxy: high cross-port coupling, ODs converge on shared terminals.

    Key: M0's aggregate service misses port-level congestion asymmetry.
    """
    return generate_synthetic_graph(
        G1_SMALL, seed=seed,
        demand_intensity=demand_intensity,
        access_restrictiveness=0.0,  # all admissible — isolate S channel
        service_asymmetry=2.5,
        footprint_severity=0.0,
        coupling_m=coupling_m,
        psi_sat=psi_sat,
    )


def generate_f_sensitive_proxy(
    seed: int = 42,
    *,
    demand_intensity: float = 1.0,
    footprint_severity: float = 0.5,
) -> PortAugmentedGraph:
    """F-sensitive proxy: airport-adjacent with protection zone.

    Key: M1 (AS) misses footprint penalties near the airport zone.
    """
    return generate_synthetic_graph(
        G3_SMALL, seed=seed,
        demand_intensity=demand_intensity,
        access_restrictiveness=0.25,
        service_asymmetry=1.5,
        footprint_severity=footprint_severity,
    )
