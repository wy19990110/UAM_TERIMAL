"""MIQP model builder for port-augmented corridor network design.

Uses the flow network abstraction for clean flow conservation.
Terminal service costs are embedded as quadratic terms (no PwL needed).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

import gurobipy as gp
from gurobipy import GRB

from uam.core.graph import PortAugmentedGraph
from uam.core.demand import DemandScenario
from uam.core.design import NetworkDesign
from uam.solver.flow_network import build_flow_network, get_sink_nodes, get_source_nodes, FlowArc


class ModelLevel(Enum):
    M0 = auto()
    M1 = auto()
    M2 = auto()
    MSTAR = auto()


@dataclass
class SolverParams:
    time_limit: float = 3600.0
    mip_gap: float = 0.01
    threads: int = 0
    verbose: bool = False


def build_and_solve(
    graph: PortAugmentedGraph,
    scenarios: list[DemandScenario],
    level: ModelLevel,
    *,
    m0_interfaces: dict | None = None,
    m1_interfaces: dict | None = None,
    m2_interfaces: dict | None = None,
    params: SolverParams | None = None,
) -> NetworkDesign:
    if params is None:
        params = SolverParams()

    model = gp.Model("uam_network_design")
    model.setParam("OutputFlag", 1 if params.verbose else 0)
    model.setParam("TimeLimit", params.time_limit)
    model.setParam("MIPGap", params.mip_gap)
    if params.threads > 0:
        model.setParam("Threads", params.threads)
    # Allow non-convex MIQP for bilinear terms (M* footprint load-sensitivity)
    model.setParam("NonConvex", 2)

    edges = graph.backbone_edges
    connectors = graph.connectors
    terminals = graph.terminals
    nodes, flow_arcs = build_flow_network(graph)

    # --- Activation variables ---
    x = {eid: model.addVar(vtype=GRB.BINARY, name=f"x_{eid}") for eid in edges}
    y = {cid: model.addVar(vtype=GRB.BINARY, name=f"y_{cid}") for cid in connectors}

    # --- Flow variables (per commodity, per scenario, per arc) ---
    f = {}  # (arc_id, commodity_key, scenario_id) -> var
    u = {}  # (commodity_key, scenario_id) -> var
    port_load = {}  # (terminal_id, port_id, scenario_id) -> var

    for scen in scenarios:
        sid = scen.scenario_id
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            for arc in flow_arcs:
                f[(arc.arc_id, k, sid)] = model.addVar(lb=0, name=f"f_{arc.arc_id}_{k}_{sid}")
            u[(k, sid)] = model.addVar(lb=0, name=f"u_{k}_{sid}")

        for tid, terminal in terminals.items():
            for port in terminal.ports:
                port_load[(tid, port.port_id, sid)] = model.addVar(
                    lb=0, name=f"lam_{tid}_{port.port_id}_{sid}"
                )

    model.update()

    # --- Constraints ---

    # 1. Flow conservation
    for scen in scenarios:
        sid = scen.scenario_id
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            src, dst = k_od
            demand = scen.od_demand[k_od]

            # Source nodes (may be multiple if terminal with ports)
            src_nodes = get_source_nodes(graph, src)
            # Sink nodes (port nodes of destination terminal)
            sink_nodes = get_sink_nodes(graph, dst)

            # Supersink: total absorbed = demand - unmet
            # We add a super-sink variable to collect flow from all sink nodes
            sink_absorbed = {sn: model.addVar(lb=0, name=f"sink_{sn}_{k}_{sid}") for sn in sink_nodes}
            model.addConstr(
                gp.quicksum(sink_absorbed.values()) + u[(k, sid)] == demand,
                name=f"demand_{k}_{sid}",
            )

            for node in nodes:
                inflow = gp.LinExpr()
                outflow = gp.LinExpr()

                for arc in flow_arcs:
                    if arc.head == node:
                        inflow += f[(arc.arc_id, k, sid)]
                    if arc.tail == node:
                        outflow += f[(arc.arc_id, k, sid)]

                # Source injection
                supply = 0.0
                if node in src_nodes:
                    # Distribute demand equally among source nodes
                    supply = demand / len(src_nodes)

                # Sink absorption
                absorbed = sink_absorbed.get(node, None)

                if absorbed is not None:
                    model.addConstr(
                        inflow - outflow + supply - absorbed == 0,
                        name=f"fc_{node}_{k}_{sid}",
                    )
                else:
                    model.addConstr(
                        inflow - outflow + supply == 0,
                        name=f"fc_{node}_{k}_{sid}",
                    )

    # 2. Backbone capacity + activation linking
    for scen in scenarios:
        sid = scen.scenario_id
        for eid, edge in edges.items():
            total = gp.LinExpr()
            for arc in flow_arcs:
                if arc.backbone_edge_id == eid:
                    for k_od in scen.commodities:
                        k = f"{k_od[0]}-{k_od[1]}"
                        total += f[(arc.arc_id, k, sid)]
            model.addConstr(total <= edge.capacity * x[eid], name=f"cap_{eid}_{sid}")

    # 3. Connector activation linking
    for cid, conn in connectors.items():
        if conn.edge_id in x:
            model.addConstr(y[cid] <= x[conn.edge_id], name=f"cy_{cid}")

    for scen in scenarios:
        sid = scen.scenario_id
        for cid in connectors:
            total = gp.LinExpr()
            for arc in flow_arcs:
                if arc.connector_id == cid:
                    for k_od in scen.commodities:
                        k = f"{k_od[0]}-{k_od[1]}"
                        total += f[(arc.arc_id, k, sid)]
            model.addConstr(total <= 1000 * y[cid], name=f"ca_{cid}_{sid}")

    # 4. Admissibility (not for M0)
    if level != ModelLevel.M0:
        for cid, conn in connectors.items():
            key = (conn.terminal_id, conn.port_id, conn.edge_id)
            if not graph.admissibility.get(key, False):
                model.addConstr(y[cid] == 0, name=f"adm_{cid}")

    # 5. Port load definition
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
                model.addConstr(
                    port_load[(tid, port.port_id, sid)] == load_expr,
                    name=f"pload_{tid}_{port.port_id}_{sid}",
                )

    # --- Objective ---
    obj = gp.QuadExpr()

    # Construction cost
    for eid, edge in edges.items():
        obj += edge.construction_cost * x[eid]

    for scen in scenarios:
        sid = scen.scenario_id
        pw = scen.probability

        # Travel cost
        for arc in flow_arcs:
            for k_od in scen.commodities:
                k = f"{k_od[0]}-{k_od[1]}"
                obj += pw * arc.cost * f[(arc.arc_id, k, sid)]

        # Unmet penalty
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            obj += pw * scen.unmet_penalty * u[(k, sid)]

        # Terminal cost (model-level dependent)
        for tid, terminal in terminals.items():
            _add_terminal_cost(
                model, obj, terminal, port_load, x, sid, pw, level,
                m0_interfaces, m1_interfaces, m2_interfaces, graph,
            )

    model.setObjective(obj, GRB.MINIMIZE)
    model.optimize()

    # --- Extract solution ---
    if model.SolCount == 0:
        result = NetworkDesign(objective=float("inf"))
        model.dispose()
        return result

    design = NetworkDesign(
        active_edges={eid for eid in edges if x[eid].X > 0.5},
        active_connectors={cid for cid in connectors if y[cid].X > 0.5},
        objective=model.ObjVal,
    )

    for scen in scenarios:
        sid = scen.scenario_id
        for k_od in scen.commodities:
            k = f"{k_od[0]}-{k_od[1]}"
            for arc in flow_arcs:
                val = f[(arc.arc_id, k, sid)].X
                if val > 1e-6:
                    design.flows[(arc.arc_id, k, sid)] = val
            design.unmet[(k, sid)] = u[(k, sid)].X
        for tid, terminal in terminals.items():
            for port in terminal.ports:
                design.port_loads[(tid, port.port_id, sid)] = port_load[
                    (tid, port.port_id, sid)
                ].X

    model.dispose()
    return design


def _add_terminal_cost(model, obj, terminal, port_load, x, sid, pw, level,
                       m0_interfaces, m1_interfaces, m2_interfaces, graph):
    tid = terminal.terminal_id

    if level == ModelLevel.M0 and m0_interfaces:
        iface = m0_interfaces[tid]
        total_load = gp.quicksum(
            port_load[(tid, p.port_id, sid)] for p in terminal.ports
        )
        obj.add(pw * iface.a_bar * total_load)
        obj.add(pw * iface.b_bar * total_load * total_load)

    elif level == ModelLevel.M1 and m1_interfaces:
        iface = m1_interfaces[tid]
        for port in terminal.ports:
            lam = port_load[(tid, port.port_id, sid)]
            ps = iface.port_service.get(port.port_id)
            if ps:
                obj.add(pw * ps.a_tilde * lam)
                obj.add(pw * ps.b_tilde * lam * lam)

    elif level == ModelLevel.M2 and m2_interfaces:
        iface = m2_interfaces[tid]
        for port in terminal.ports:
            lam = port_load[(tid, port.port_id, sid)]
            ps = iface.as_iface.port_service.get(port.port_id)
            if ps:
                obj.add(pw * ps.a_tilde * lam)
                obj.add(pw * ps.b_tilde * lam * lam)
        for eid, pi in iface.nominal_penalty.items():
            if eid in x:
                obj.add(pw * pi * x[eid])
        for eid in iface.blocked_edges:
            if eid in x:
                obj.add(pw * 1e4 * x[eid])

    else:  # MSTAR
        for port in terminal.ports:
            lam = port_load[(tid, port.port_id, sid)]
            obj.add(pw * port.a * lam)
            obj.add(pw * port.b * lam * lam)

        for (h_i, h_j), m_val in terminal.cross_port_coupling.items():
            lam_i = port_load[(tid, h_i, sid)]
            lam_j = port_load[(tid, h_j, sid)]
            obj.add(pw * m_val * lam_i * lam_j)

        total_load = gp.quicksum(
            port_load[(tid, p.port_id, sid)] for p in terminal.ports
        )
        excess = model.addVar(lb=0, name=f"ex_{tid}_{sid}")
        model.addConstr(excess >= total_load - terminal.mu_bar, name=f"exd_{tid}_{sid}")
        obj.add(pw * terminal.psi_sat * excess * excess)

        # Footprint
        neighborhood = graph.base.neighborhood_edges(tid, terminal.footprint_radius_hops)
        for eid in neighborhood:
            if eid not in x:
                continue
            base_pi = terminal.footprint_base_penalty.get(eid, 0.0)
            if base_pi > 0:
                obj.add(pw * base_pi * x[eid])
            for port in terminal.ports:
                rho = terminal.footprint_load_sensitivity.get((eid, port.port_id), 0.0)
                if rho > 0:
                    obj.add(pw * rho * port_load[(tid, port.port_id, sid)] * x[eid])

        for eid in terminal.blocked_edges:
            if eid in x:
                obj.add(pw * 1e4 * x[eid])
