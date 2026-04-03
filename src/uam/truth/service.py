"""Service truth model: quadratic port-level costs with cross-port coupling.

L^truth_t(λ_t) = Σ_h (a_{t,h} λ_{t,h} + b_{t,h} λ_{t,h}²)
               + Σ_{h<h'} m_{t,hh'} λ_{t,h} λ_{t,h'}
               + ψ_t [Λ_t - μ̄_t]²₊
"""

from __future__ import annotations

import numpy as np

from uam.core.terminal import TerminalConfig


def compute_service_cost(
    terminal: TerminalConfig,
    port_loads: dict[str, float],
) -> float:
    """Compute the truth service cost L^truth for a terminal given port loads.

    Args:
        terminal: Terminal configuration.
        port_loads: Dict mapping port_id -> load (λ_{t,h}).

    Returns:
        Total service cost L^truth_t.
    """
    cost = 0.0

    # Per-port quadratic terms: a*λ + b*λ²
    for port in terminal.ports:
        lam = port_loads.get(port.port_id, 0.0)
        cost += port.a * lam + port.b * lam ** 2

    # Cross-port coupling: m * λ_h * λ_h'
    for (h_i, h_j), m_val in terminal.cross_port_coupling.items():
        lam_i = port_loads.get(h_i, 0.0)
        lam_j = port_loads.get(h_j, 0.0)
        cost += m_val * lam_i * lam_j

    # Saturation penalty: ψ * [Λ - μ̄]²₊
    total_load = sum(port_loads.get(p.port_id, 0.0) for p in terminal.ports)
    excess = max(0.0, total_load - terminal.mu_bar)
    cost += terminal.psi_sat * excess ** 2

    return cost


def compute_service_gradient(
    terminal: TerminalConfig,
    port_loads: dict[str, float],
) -> dict[str, float]:
    """Compute ∂L/∂λ_h for each port.

    Useful for optimality checks and flow allocation.
    """
    total_load = sum(port_loads.get(p.port_id, 0.0) for p in terminal.ports)
    excess = max(0.0, total_load - terminal.mu_bar)

    grad = {}
    for port in terminal.ports:
        h = port.port_id
        lam = port_loads.get(h, 0.0)
        # d/dλ_h of (a*λ + b*λ²) = a + 2b*λ
        g = port.a + 2 * port.b * lam
        # Cross-port coupling terms
        for (h_i, h_j), m_val in terminal.cross_port_coupling.items():
            if h_i == h:
                g += m_val * port_loads.get(h_j, 0.0)
            elif h_j == h:
                g += m_val * port_loads.get(h_i, 0.0)
        # Saturation: 2ψ[Λ-μ̄]₊
        if excess > 0:
            g += 2 * terminal.psi_sat * excess
        grad[h] = g
    return grad


def fit_aggregate_service(
    terminal: TerminalConfig,
    num_samples: int = 20,
) -> tuple[float, float]:
    """Fit aggregate service curve L̃^(0)(Λ) = ā Λ + b̄ Λ² from truth model.

    Assumes uniform load distribution across ports.

    Returns:
        (a_bar, b_bar) coefficients.
    """
    n_ports = terminal.num_ports
    if n_ports == 0:
        return (0.0, 0.0)

    # Sample total loads from 0 to 1.5 * mu_bar
    lambdas = np.linspace(0, 1.5 * terminal.mu_bar, num_samples)
    costs = np.zeros(num_samples)
    for i, lam_total in enumerate(lambdas):
        # Uniform split
        per_port = lam_total / n_ports
        loads = {p.port_id: per_port for p in terminal.ports}
        costs[i] = compute_service_cost(terminal, loads)

    # Fit: L = a_bar * Λ + b_bar * Λ²
    # Using least squares: [Λ, Λ²] @ [a, b]^T = costs
    A_mat = np.column_stack([lambdas, lambdas ** 2])
    coeffs, _, _, _ = np.linalg.lstsq(A_mat, costs, rcond=None)
    return (float(coeffs[0]), float(coeffs[1]))


def fit_port_service(
    terminal: TerminalConfig,
    port_id: str,
    num_samples: int = 20,
) -> tuple[float, float]:
    """Fit per-port service curve ã_{t,h} λ + b̃_{t,h} λ² from truth model.

    Loads only the target port, all others at zero.
    This captures the separable component for M1 (AS interface).

    Returns:
        (a_tilde, b_tilde) coefficients.
    """
    port = terminal.get_port(port_id)
    cap = terminal.mu_bar / max(terminal.num_ports, 1)

    lambdas = np.linspace(0, 1.5 * cap, num_samples)
    costs = np.zeros(num_samples)
    for i, lam in enumerate(lambdas):
        loads = {p.port_id: 0.0 for p in terminal.ports}
        loads[port_id] = lam
        costs[i] = compute_service_cost(terminal, loads)

    A_mat = np.column_stack([lambdas, lambdas ** 2])
    coeffs, _, _, _ = np.linalg.lstsq(A_mat, costs, rcond=None)
    return (float(coeffs[0]), float(coeffs[1]))
