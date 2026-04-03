"""Terminal and port configuration data structures."""

from __future__ import annotations

import math
from dataclasses import dataclass, field


@dataclass
class PortConfig:
    """A single port (approach/departure interface) of a terminal.

    Attributes:
        port_id: Unique identifier within the terminal (e.g. "h1", "h2").
        direction_deg: Center direction of the admissible sector (degrees, 0=East, CCW).
        sector_half_width_deg: Half-width of the admissible sector (degrees).
        a: Linear delay coefficient for this port's service curve.
        b: Quadratic delay coefficient for this port's service curve.
    """

    port_id: str
    direction_deg: float = 0.0
    sector_half_width_deg: float = 45.0
    a: float = 0.2
    b: float = 0.5

    def admits_direction(self, theta_deg: float) -> bool:
        """Check if an incoming edge direction falls within this port's sector."""
        diff = (theta_deg - self.direction_deg + 180) % 360 - 180
        return abs(diff) <= self.sector_half_width_deg


@dataclass
class TerminalConfig:
    """Full configuration of a terminal (vertiport).

    This combines physical layout (P/G), operational rules (R/O),
    and contextual factors (X) into a single object from which
    the truth model computes A, S, F.

    Attributes:
        terminal_id: Unique identifier (e.g. "T1").
        x, y: Position in the plane (normalized units).
        ports: List of port configurations.
        pads: Number of landing/takeoff pads.
        gates: Number of passenger boarding gates.
        organization: Operational organization type.
        procedure_type: "procedure-like" or "path-like".
        context_type: "open-city", "cluster", or "airport-adjacent".
        mu_bar: Overall saturation threshold (normalized).
        psi_sat: Penalty coefficient for exceeding saturation.
        cross_port_coupling: Dict mapping (h_i, h_j) -> coupling coefficient m.
        footprint_radius_hops: Neighborhood radius for footprint effects.
        footprint_base_penalty: Dict mapping edge_id -> base penalty pi_bar.
        footprint_load_sensitivity: Dict mapping (edge_id, port_id) -> sensitivity rho.
        blocked_edges: Set of edge IDs that are hard-blocked by this terminal.
        context_blocked_edges: Dict mapping context_state -> set of additionally blocked edges.
    """

    terminal_id: str
    x: float = 0.0
    y: float = 0.0
    ports: list[PortConfig] = field(default_factory=list)
    pads: int = 2
    gates: int = 2
    organization: str = "direct"  # "direct", "single-ring", "multi-ring"
    procedure_type: str = "path-like"  # "procedure-like", "path-like"
    context_type: str = "open-city"  # "open-city", "cluster", "airport-adjacent"
    mu_bar: float = 1.0
    psi_sat: float = 2.0
    cross_port_coupling: dict[tuple[str, str], float] = field(default_factory=dict)
    footprint_radius_hops: int = 1
    footprint_base_penalty: dict[str, float] = field(default_factory=dict)
    footprint_load_sensitivity: dict[tuple[str, str], float] = field(default_factory=dict)
    blocked_edges: set[str] = field(default_factory=set)
    context_blocked_edges: dict[str, set[str]] = field(default_factory=dict)

    @property
    def num_ports(self) -> int:
        return len(self.ports)

    @property
    def port_ids(self) -> list[str]:
        return [p.port_id for p in self.ports]

    def get_port(self, port_id: str) -> PortConfig:
        for p in self.ports:
            if p.port_id == port_id:
                return p
        raise KeyError(f"Port {port_id} not found in terminal {self.terminal_id}")

    def distance_to(self, other: TerminalConfig) -> float:
        return math.hypot(self.x - other.x, self.y - other.y)
