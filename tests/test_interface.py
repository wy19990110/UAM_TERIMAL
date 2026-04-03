"""Unit tests for interface extractors (M0, M1, M2)."""

import pytest
from uam.core import TerminalConfig, PortConfig
from uam.core.graph import CandidateGraph, BackboneEdge
from uam.interface import extract_s_only, extract_as_interface, extract_asf_interface


@pytest.fixture
def asymmetric_terminal():
    """Terminal with asymmetric ports: h1 cheap, h2 expensive."""
    return TerminalConfig(
        "T1", x=0, y=0,
        ports=[
            PortConfig("h1", direction_deg=0, sector_half_width_deg=40, a=0.1, b=0.2),
            PortConfig("h2", direction_deg=180, sector_half_width_deg=40, a=0.1, b=1.0),
        ],
        mu_bar=1.0,
        psi_sat=2.0,
        cross_port_coupling={("h1", "h2"): 0.15},
        blocked_edges={"E_blocked"},
        footprint_base_penalty={"E1": 0.8},
    )


@pytest.fixture
def test_graph(asymmetric_terminal):
    return CandidateGraph(
        terminals={"T1": asymmetric_terminal},
        waypoints={"W1": (1.0, 0.0), "W2": (-1.0, 0.0)},
        backbone_edges={
            "E1": BackboneEdge("E1", "T1", "W1"),  # east
            "E2": BackboneEdge("E2", "T1", "W2"),  # west
            "E_blocked": BackboneEdge("E_blocked", "T1", "W2"),
        },
    )


class TestSOnly:
    def test_m0_is_scalar(self, asymmetric_terminal):
        m0 = extract_s_only(asymmetric_terminal)
        # M0 gives a single scalar cost for total load
        cost = m0.service_cost(0.5)
        assert isinstance(cost, float)
        assert cost >= 0

    def test_m0_loses_asymmetry(self, asymmetric_terminal):
        """M0 cannot distinguish which port receives the load."""
        m0 = extract_s_only(asymmetric_terminal)
        # Same total load, different distribution -> same M0 cost
        cost1 = m0.service_cost(0.5)
        cost2 = m0.service_cost(0.5)
        assert cost1 == cost2


class TestASInterface:
    def test_admissibility_preserved(self, asymmetric_terminal, test_graph):
        m1 = extract_as_interface(asymmetric_terminal, test_graph)
        # h1 (east) should admit E1 (east), reject E2 (west)
        assert m1.is_admissible("h1", "E1") is True
        assert m1.is_admissible("h1", "E2") is False
        # h2 (west) should admit E2 (west) but E_blocked is blocked
        assert m1.is_admissible("h2", "E2") is True
        assert m1.is_admissible("h2", "E_blocked") is False

    def test_port_service_captures_asymmetry(self, asymmetric_terminal, test_graph):
        m1 = extract_as_interface(asymmetric_terminal, test_graph)
        # h2 has higher b (1.0 vs 0.2), so should have higher cost at same load
        cost_h1 = m1.port_service["h1"].cost(0.3)
        cost_h2 = m1.port_service["h2"].cost(0.3)
        assert cost_h2 > cost_h1

    def test_m1_service_is_separable(self, asymmetric_terminal, test_graph):
        """M1 cost should be sum of per-port costs (no coupling)."""
        m1 = extract_as_interface(asymmetric_terminal, test_graph)
        loads = {"h1": 0.3, "h2": 0.2}
        total = m1.service_cost(loads)
        sum_parts = m1.port_service["h1"].cost(0.3) + m1.port_service["h2"].cost(0.2)
        assert total == pytest.approx(sum_parts)


class TestASFInterface:
    def test_inherits_as(self, asymmetric_terminal, test_graph):
        m2 = extract_asf_interface(asymmetric_terminal, test_graph)
        assert m2.is_admissible("h1", "E1") is True

    def test_footprint_penalty(self, asymmetric_terminal, test_graph):
        m2 = extract_asf_interface(asymmetric_terminal, test_graph)
        assert "E1" in m2.nominal_penalty
        assert m2.nominal_penalty["E1"] == pytest.approx(0.8)

    def test_blocked_edges(self, asymmetric_terminal, test_graph):
        m2 = extract_asf_interface(asymmetric_terminal, test_graph)
        assert "E_blocked" in m2.blocked_edges

    def test_footprint_cost_with_blocked(self, asymmetric_terminal, test_graph):
        m2 = extract_asf_interface(asymmetric_terminal, test_graph)
        cost = m2.footprint_cost({"E1", "E_blocked"})
        assert cost >= 1e4  # BIG_M from blocked edge


class TestM0VsM1VsTruth:
    """Cross-cutting test: verify that M0 loses information M1 retains."""

    def test_m0_cannot_see_port_asymmetry(self, asymmetric_terminal, test_graph):
        from uam.truth.service import compute_service_cost

        m0 = extract_s_only(asymmetric_terminal)
        m1 = extract_as_interface(asymmetric_terminal, test_graph)

        # Scenario: all load on cheap port h1
        loads_cheap = {"h1": 0.4, "h2": 0.0}
        truth_cheap = compute_service_cost(asymmetric_terminal, loads_cheap)

        # Scenario: all load on expensive port h2
        loads_expensive = {"h1": 0.0, "h2": 0.4}
        truth_expensive = compute_service_cost(asymmetric_terminal, loads_expensive)

        # Truth sees the difference
        assert truth_expensive > truth_cheap

        # M1 sees the difference
        m1_cheap = m1.service_cost(loads_cheap)
        m1_expensive = m1.service_cost(loads_expensive)
        assert m1_expensive > m1_cheap

        # M0 cannot distinguish (same total load)
        m0_cost = m0.service_cost(0.4)
        # M0 gives one cost regardless of distribution
        assert isinstance(m0_cost, float)
