"""Unit tests for core data structures."""

import pytest
from uam.core import TerminalConfig, PortConfig, DemandScenario, NetworkDesign
from uam.core.graph import CandidateGraph, PortAugmentedGraph, BackboneEdge, ConnectorArc


class TestPortConfig:
    def test_admits_direction_within_sector(self):
        p = PortConfig("h1", direction_deg=90, sector_half_width_deg=30)
        assert p.admits_direction(80)
        assert p.admits_direction(100)
        assert p.admits_direction(90)

    def test_rejects_direction_outside_sector(self):
        p = PortConfig("h1", direction_deg=90, sector_half_width_deg=30)
        assert not p.admits_direction(0)
        assert not p.admits_direction(180)
        assert not p.admits_direction(270)

    def test_wrapping_near_zero(self):
        p = PortConfig("h1", direction_deg=10, sector_half_width_deg=20)
        assert p.admits_direction(350)  # -10 deg, within ±20
        assert not p.admits_direction(330)  # -40 deg, outside ±20

    def test_full_circle_sector(self):
        p = PortConfig("h1", direction_deg=0, sector_half_width_deg=180)
        assert p.admits_direction(0)
        assert p.admits_direction(90)
        assert p.admits_direction(180)
        assert p.admits_direction(270)


class TestTerminalConfig:
    def test_num_ports(self):
        t = TerminalConfig("T1", ports=[PortConfig("h1"), PortConfig("h2")])
        assert t.num_ports == 2

    def test_get_port(self):
        t = TerminalConfig("T1", ports=[PortConfig("h1", a=0.5)])
        assert t.get_port("h1").a == 0.5

    def test_get_port_missing(self):
        t = TerminalConfig("T1", ports=[PortConfig("h1")])
        with pytest.raises(KeyError):
            t.get_port("h99")

    def test_distance(self):
        t1 = TerminalConfig("T1", x=0, y=0)
        t2 = TerminalConfig("T2", x=3, y=4)
        assert t1.distance_to(t2) == pytest.approx(5.0)


class TestCandidateGraph:
    def setup_method(self):
        self.t1 = TerminalConfig("T1", x=0, y=0, ports=[PortConfig("h1")])
        self.t2 = TerminalConfig("T2", x=1, y=0, ports=[PortConfig("h1")])
        self.g = CandidateGraph(
            terminals={"T1": self.t1, "T2": self.t2},
            waypoints={"W1": (0.5, 1.0)},
            backbone_edges={
                "E1": BackboneEdge("E1", "T1", "T2", 1.0),
                "E2": BackboneEdge("E2", "T1", "W1", 1.0),
                "E3": BackboneEdge("E3", "T2", "W1", 1.0),
            },
        )

    def test_edge_direction(self):
        # T1(0,0) -> T2(1,0) should be ~0 degrees (east)
        d = self.g.compute_edge_direction(self.g.backbone_edges["E1"], "T1")
        assert d == pytest.approx(0.0, abs=1.0)

    def test_edges_incident(self):
        edges = self.g.edges_incident_to("T1")
        edge_ids = {e.edge_id for e in edges}
        assert edge_ids == {"E1", "E2"}

    def test_neighborhood(self):
        n1 = self.g.neighborhood_edges("T1", hops=1)
        assert "E1" in n1
        assert "E2" in n1

        n2 = self.g.neighborhood_edges("T1", hops=2)
        assert "E3" in n2


class TestNetworkDesign:
    def test_topology_distance_identical(self):
        d1 = NetworkDesign(active_edges={"E1", "E2"})
        d2 = NetworkDesign(active_edges={"E1", "E2"})
        assert d1.topology_distance_backbone(d2) == 0.0

    def test_topology_distance_disjoint(self):
        d1 = NetworkDesign(active_edges={"E1"})
        d2 = NetworkDesign(active_edges={"E2"})
        assert d1.topology_distance_backbone(d2) == 1.0

    def test_topology_distance_partial(self):
        d1 = NetworkDesign(active_edges={"E1", "E2", "E3"})
        d2 = NetworkDesign(active_edges={"E1", "E4"})
        # intersection=1, union=4 -> TD=0.75
        assert d1.topology_distance_backbone(d2) == pytest.approx(0.75)

    def test_total_unmet(self):
        d = NetworkDesign(unmet={("k1", "w1"): 3.0, ("k2", "w1"): 2.0, ("k1", "w2"): 1.0})
        assert d.total_unmet("w1") == 5.0
        assert d.total_unmet("w2") == 1.0


class TestDemandScenario:
    def test_total_demand(self):
        d = DemandScenario(od_demand={("T1", "T2"): 5.0, ("T2", "T1"): 3.0})
        assert d.total_demand == 8.0
        assert d.num_od_pairs == 2
