"""Truth evaluator: fix design (x,y), re-optimize flows under M*, compute J^truth."""

from __future__ import annotations

from dataclasses import dataclass

import gurobipy as gp
from gurobipy import GRB

from uam.core.graph import PortAugmentedGraph
from uam.core.demand import DemandScenario
from uam.core.design import NetworkDesign
from uam.solver.flow_network import build_flow_network, get_sink_nodes, get_source_nodes


@dataclass
class TruthBreakdown:
    construction_cost: float = 0.0
    travel_cost: float = 0.0
    terminal_service_cost: float = 0.0
    footprint_cost: float = 0.0
    unmet_cost: float = 0.0
    total: float = 0.0


def truth_evaluate(
    design: NetworkDesign,
    graph: PortAugmentedGraph,
    scenarios: list[DemandScenario],
    verbose: bool = False,
) -> tuple[float, TruthBreakdown]:
    model = gp.Model("truth_eval")
    model.setParam("OutputFlag", 1 if verbose else 0)
    model.setParam("NonConvex", 2)

    terminals = graph.terminals
    edges = graph.backbone_edges
    connectors = graph.connectors
    active_e = design.active_edges
    active_c = design.active_connectors
    nodes, flow_arcs = build_flow_network(graph)

    # Flow variables
    f = {}
    u = {}
    port_load = {}

    for scen in scenarios:
        sid = scen.scenario_id
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            for arc in flow_arcs:
                # Restrict flow: backbone arcs only on active edges, connector arcs only on active connectors
                ub = float("inf")
                if arc.is_backbone and arc.backbone_edge_id not in active_e:
                    ub = 0.0
                if arc.is_connector and arc.connector_id not in active_c:
                    ub = 0.0
                # Admissibility check under truth
                if arc.is_connector:
                    key = (arc.terminal_id, arc.port_id, None)
                    # Find the backbone edge for this connector
                    conn = connectors.get(arc.connector_id)
                    if conn:
                        akey = (conn.terminal_id, conn.port_id, conn.edge_id)
                        if not graph.admissibility.get(akey, False):
                            ub = 0.0
                f[(arc.arc_id, k, sid)] = model.addVar(lb=0, ub=ub, name=f"f_{arc.arc_id}_{k}_{sid}")
            u[(k, sid)] = model.addVar(lb=0, name=f"u_{k}_{sid}")

        for tid, terminal in terminals.items():
            for port in terminal.ports:
                port_load[(tid, port.port_id, sid)] = model.addVar(
                    lb=0, name=f"lam_{tid}_{port.port_id}_{sid}"
                )

    model.update()

    # Flow conservation (same logic as miqp_builder)
    for scen in scenarios:
        sid = scen.scenario_id
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            src, dst = k_od
            demand = scen.od_demand[k_od]
            src_nodes = get_source_nodes(graph, src)
            sink_nodes = get_sink_nodes(graph, dst)

            sink_absorbed = {sn: model.addVar(lb=0, name=f"sk_{sn}_{k}_{sid}") for sn in sink_nodes}
            model.addConstr(
                gp.quicksum(sink_absorbed.values()) + u[(k, sid)] == demand,
                name=f"dem_{k}_{sid}",
            )

            for node in nodes:
                inflow = gp.LinExpr()
                outflow = gp.LinExpr()
                for arc in flow_arcs:
                    if arc.head == node:
                        inflow += f[(arc.arc_id, k, sid)]
                    if arc.tail == node:
                        outflow += f[(arc.arc_id, k, sid)]

                supply = demand / len(src_nodes) if node in src_nodes else 0.0
                absorbed = sink_absorbed.get(node)

                if absorbed is not None:
                    model.addConstr(inflow - outflow + supply - absorbed == 0, name=f"fc_{node}_{k}_{sid}")
                else:
                    model.addConstr(inflow - outflow + supply == 0, name=f"fc_{node}_{k}_{sid}")

    # Capacity (on active edges only)
    for scen in scenarios:
        sid = scen.scenario_id
        for eid, edge in edges.items():
            total = gp.LinExpr()
            for arc in flow_arcs:
                if arc.backbone_edge_id == eid:
                    for k_od in scen.commodities:
                        k = f"{k_od[0]}-{k_od[1]}"
                        total += f[(arc.arc_id, k, sid)]
            cap = edge.capacity if eid in active_e else 0
            model.addConstr(total <= cap, name=f"cap_{eid}_{sid}")

    # Port loads
    for scen in scenarios:
        sid = scen.scenario_id
        for tid, terminal in terminals.items():
            for port in terminal.ports:
                port_node = f"port_{tid}_{port.port_id}"
                load_expr = gp.LinExpr()
                for arc in flow_arcs:
                    if arc.head == port_node and arc.is_connector:
                        for k_od in scen.commodities:
                            k = f"{k_od[0]}-{k_od[1]}"
                            load_expr += f[(arc.arc_id, k, sid)]
                model.addConstr(port_load[(tid, port.port_id, sid)] == load_expr,
                                name=f"pl_{tid}_{port.port_id}_{sid}")

    # --- Objective: truth model ---
    obj = gp.QuadExpr()
    construction_val = sum(edge.construction_cost for eid, edge in edges.items() if eid in active_e)

    travel_expr = gp.LinExpr()
    service_expr = gp.QuadExpr()
    footprint_val = 0.0
    unmet_expr = gp.LinExpr()

    for scen in scenarios:
        sid = scen.scenario_id
        pw = scen.probability

        for arc in flow_arcs:
            for k_od in scen.commodities:
                k = f"{k_od[0]}-{k_od[1]}"
                travel_expr += pw * arc.cost * f[(arc.arc_id, k, sid)]

        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            unmet_expr += pw * scen.unmet_penalty * u[(k, sid)]

        for tid, terminal in terminals.items():
            for port in terminal.ports:
                lam = port_load[(tid, port.port_id, sid)]
                service_expr += pw * port.a * lam
                service_expr += pw * port.b * lam * lam

            for (h_i, h_j), m_val in terminal.cross_port_coupling.items():
                service_expr += pw * m_val * port_load[(tid, h_i, sid)] * port_load[(tid, h_j, sid)]

            total_load = gp.quicksum(port_load[(tid, p.port_id, sid)] for p in terminal.ports)
            excess = model.addVar(lb=0, name=f"ex_{tid}_{sid}")
            model.addConstr(excess >= total_load - terminal.mu_bar, name=f"exd_{tid}_{sid}")
            service_expr += pw * terminal.psi_sat * excess * excess

            # Footprint (fixed x, so just constants + linear in λ)
            neighborhood = graph.base.neighborhood_edges(tid, terminal.footprint_radius_hops)
            for eid in neighborhood:
                if eid not in active_e:
                    continue
                base_pi = terminal.footprint_base_penalty.get(eid, 0.0)
                footprint_val += pw * base_pi
                for port in terminal.ports:
                    rho = terminal.footprint_load_sensitivity.get((eid, port.port_id), 0.0)
                    if rho > 0:
                        service_expr += pw * rho * port_load[(tid, port.port_id, sid)]

            for eid in terminal.blocked_edges:
                if eid in active_e:
                    footprint_val += pw * 1e4

    obj = construction_val + travel_expr + service_expr + footprint_val + unmet_expr
    model.setObjective(obj, GRB.MINIMIZE)
    model.optimize()

    if model.Status not in (GRB.OPTIMAL, GRB.SUBOPTIMAL) or model.SolCount == 0:
        return float("inf"), TruthBreakdown(total=float("inf"))

    obj_val = model.ObjVal
    breakdown = TruthBreakdown(
        construction_cost=construction_val,
        travel_cost=travel_expr.getValue(),
        terminal_service_cost=service_expr.getValue(),
        footprint_cost=footprint_val,
        unmet_cost=unmet_expr.getValue(),
        total=obj_val,
    )

    for scen in scenarios:
        sid = scen.scenario_id
        for tid, terminal in terminals.items():
            for port in terminal.ports:
                design.port_loads[(tid, port.port_id, sid)] = port_load[(tid, port.port_id, sid)].X

    design.truth_objective = obj_val
    model.dispose()
    return obj_val, breakdown
