"""Unit tests for truth model (access, service, footprint)."""

import pytest
from uam.core import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, BackboneEdge
from uam.truth.access import compute_admissibility, build_full_admissibility
from uam.truth.service import (
    compute_service_cost,
    compute_service_gradient,
    fit_aggregate_service,
    fit_port_service,
)
from uam.truth.footprint import compute_footprint_cost, extract_nominal_footprint


@pytest.fixture
def two_port_terminal():
    return TerminalConfig(
        "T1", x=0, y=0,
        ports=[
            PortConfig("h1", direction_deg=0, sector_half_width_deg=40, a=0.2, b=0.3),
            PortConfig("h2", direction_deg=180, sector_half_width_deg=40, a=0.2, b=0.8),
        ],
        mu_bar=1.0,
        psi_sat=3.0,
        cross_port_coupling={("h1", "h2"): 0.2},
        blocked_edges={"E2"},
        footprint_base_penalty={"E1": 0.5},
        footprint_load_sensitivity={("E1", "h1"): 0.3},
    )


@pytest.fixture
def small_graph(two_port_terminal):
    return CandidateGraph(
        terminals={"T1": two_port_terminal},
        waypoints={"W1": (1.0, 0.0), "W2": (-1.0, 0.0)},
        backbone_edges={
            "E1": BackboneEdge("E1", "T1", "W1", 1.0, 1.0, 1.0, 50),  # east
            "E2": BackboneEdge("E2", "T1", "W2", 1.0, 1.0, 1.0, 50),  # west
        },
    )


class TestAccessTruth:
    def test_direction_admissibility(self, two_port_terminal, small_graph):
        # E1 goes east (0°), h1 faces east (0°±40) -> admissible
        # E1 goes east, h2 faces west (180°±40) -> not admissible
        adm = compute_admissibility(two_port_terminal, small_graph.backbone_edges["E1"], small_graph)
        assert adm["h1"] is True
        assert adm["h2"] is False

    def test_blocked_edge(self, two_port_terminal, small_graph):
        # E2 goes west (180°), h2 faces west -> direction OK, but E2 is blocked
        adm = compute_admissibility(two_port_terminal, small_graph.backbone_edges["E2"], small_graph)
        assert adm["h2"] is False  # blocked
        assert adm["h1"] is False  # direction mismatch

    def test_non_incident_edge(self, two_port_terminal, small_graph):
        # Edge not connected to terminal
        fake_edge = BackboneEdge("E99", "W1", "W2", 1.0)
        adm = compute_admissibility(two_port_terminal, fake_edge, small_graph)
        assert all(v is False for v in adm.values())

    def test_full_admissibility(self, small_graph):
        A = build_full_admissibility(small_graph)
        assert A[("T1", "h1", "E1")] is True
        assert A[("T1", "h2", "E1")] is False
        assert A[("T1", "h2", "E2")] is False  # blocked


class TestServiceTruth:
    def test_basic_cost(self, two_port_terminal):
        loads = {"h1": 0.3, "h2": 0.2}
        cost = compute_service_cost(two_port_terminal, loads)
        # a1*0.3 + b1*0.3² + a2*0.2 + b2*0.2² + m*0.3*0.2 + ψ*[0.5-1.0]²₊
        expected = 0.2 * 0.3 + 0.3 * 0.09 + 0.2 * 0.2 + 0.8 * 0.04 + 0.2 * 0.06 + 0
        assert cost == pytest.approx(expected)

    def test_saturation_penalty(self, two_port_terminal):
        loads = {"h1": 0.6, "h2": 0.6}  # total=1.2, excess=0.2
        cost = compute_service_cost(two_port_terminal, loads)
        no_sat = 0.2 * 0.6 + 0.3 * 0.36 + 0.2 * 0.6 + 0.8 * 0.36 + 0.2 * 0.36
        sat_pen = 3.0 * 0.2 ** 2
        assert cost == pytest.approx(no_sat + sat_pen)

    def test_zero_load(self, two_port_terminal):
        loads = {"h1": 0.0, "h2": 0.0}
        assert compute_service_cost(two_port_terminal, loads) == 0.0

    def test_gradient_at_zero(self, two_port_terminal):
        loads = {"h1": 0.0, "h2": 0.0}
        grad = compute_service_gradient(two_port_terminal, loads)
        assert grad["h1"] == pytest.approx(0.2)  # just a_h1
        assert grad["h2"] == pytest.approx(0.2)  # just a_h2

    def test_fit_per_port_recovers_params(self, two_port_terminal):
        a1, b1 = fit_port_service(two_port_terminal, "h1")
        assert a1 == pytest.approx(0.2, abs=0.01)
        assert b1 == pytest.approx(0.3, abs=0.01)

    def test_aggregate_differs_from_port(self, two_port_terminal):
        a_bar, b_bar = fit_aggregate_service(two_port_terminal)
        # With cross-port coupling, aggregate should differ from simple sum
        a1, b1 = fit_port_service(two_port_terminal, "h1")
        a2, b2 = fit_port_service(two_port_terminal, "h2")
        # a_bar ≠ (a1+a2)/2 because coupling term adds to aggregate
        assert a_bar != pytest.approx((a1 + a2), abs=0.05)


class TestFootprintTruth:
    def test_base_penalty(self, two_port_terminal, small_graph):
        cost = compute_footprint_cost(
            two_port_terminal, small_graph, {"E1"}, {"h1": 0.0, "h2": 0.0}
        )
        assert cost == pytest.approx(0.5)  # E1 has base penalty 0.5

    def test_load_sensitivity(self, two_port_terminal, small_graph):
        cost = compute_footprint_cost(
            two_port_terminal, small_graph, {"E1"}, {"h1": 1.0, "h2": 0.0}
        )
        # base 0.5 + rho*lambda = 0.3*1.0
        assert cost == pytest.approx(0.8)

    def test_blocked_edge_big_m(self, two_port_terminal, small_graph):
        cost = compute_footprint_cost(
            two_port_terminal, small_graph, {"E2"}, {"h1": 0.0, "h2": 0.0}
        )
        assert cost >= 1e4  # BIG_M penalty

    def test_no_active_no_cost(self, two_port_terminal, small_graph):
        cost = compute_footprint_cost(
            two_port_terminal, small_graph, set(), {"h1": 0.0, "h2": 0.0}
        )
        assert cost == 0.0

    def test_extract_nominal(self, two_port_terminal, small_graph):
        pi_tilde, blocked = extract_nominal_footprint(two_port_terminal, small_graph)
        assert pi_tilde == {"E1": 0.5}
        assert "E2" in blocked
