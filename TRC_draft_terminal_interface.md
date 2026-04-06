# When terminals are not nodes: A hierarchical interface for reusable low-altitude route network design

**Anonymous authors**

## Abstract

Reusable low-altitude route network design often treats terminals as homogeneous nodes, even though access rules, port-level service, and terminal-neighborhood constraints are heterogeneous. This paper studies when that simplification misguides strategic network design and asks what terminal information must be exposed to the upper-level planner. We propose a hierarchical terminal interface with three network-facing channels: access admissibility (A), port-level service capability (S), and local footprint/conflict (F). The interface is evaluated through a shared-candidate-graph protocol in which each model designs a network under its own abstraction and the resulting design is then re-evaluated under a richer terminal truth model. Minimal counterexamples show that omitting A can produce infeasible or 331.6% regret designs, omitting S yields regret that rises from 0 to 14.7% as demand increases, and omitting F can cause catastrophic failures under hard terminal-neighborhood blocks. On 864 synthetic network instances, the AS planner raises sufficiency from 38.3% to 72.3% relative to the S-only planner, while ASF becomes necessary in high-footprint regimes. An airport-adjacent proxy case further shows that ignoring footprint can raise regret from 52.1% to about 972% in the strongest constrained scenario. The results support a tested hierarchical terminal interface and corresponding model-upgrade rules for strategic reusable route network design.

**Keywords:** low-altitude transportation; urban air mobility; network design; terminal abstraction; interface sufficiency; design misguidance

## 1. Introduction

Urban air mobility (UAM) and low-altitude transportation are moving from isolated demonstrations toward network design questions: where reusable corridors should be built, how terminals should be connected to them, and how demand should be distributed across the resulting network. Existing UAM network studies have begun to address structured network construction and vertiport siting, often by adapting hub-location logic and graph design methods to new aircraft and range constraints (Willey and Salmon, 2021). At the same time, airspace design studies emphasize that the usable low-altitude network is shaped by geometry, capacity, legacy airspace constructs, and local operational rules rather than by unconstrained Euclidean distance alone (Bauranov and Rakas, 2021; Vascik et al., 2020).

A key modeling tension follows. Strategic network design prefers terminals to be as coarse as possible, ideally as node-level demand sinks or sources with a single aggregate service representation. Yet the terminal-side literature points in the opposite direction. Stochastic and queueing models in air traffic management show that local congestion, scarce resources, and delay propagation can be represented meaningfully at mesoscopic scales rather than only through full microsimulation (Shone et al., 2021; Itoh and Mitici, 2019). Terminal-area control studies for multi-vertiport operations explicitly rely on local geometric rules, holding structures, and junction control policies (Shao et al., 2021). Geofencing studies likewise treat protected or prohibited local airspace volumes as first-class operational constraints (Kim and Atkins, 2022). The consequence is that terminals are not merely points with scalar capacities. They are interfaces between the external network and local operational structure.

This paper addresses that interface problem. The goal is not to push every terminal-side detail into a permanently integrated network-terminal optimizer. The goal is to identify a network-facing terminal abstraction that is sufficiently informative for strategic network design. We ask: what is the smallest practically useful set of terminal-side information that must be exposed to the upper-level planner so that the designed network is not systematically misled? The answer proposed here is a hierarchical interface with three channels: access admissibility (A), port-level service capability (S), and local footprint/conflict (F).

The paper makes four contributions. First, it formulates a terminal-coupled reusable-route network design problem in which terminal heterogeneity can change the ranking of network designs. Second, it introduces a hierarchical A/S/F interface family and an adopted terminal truth class that is richer than the design abstractions but still compatible with network-level optimization. Third, it evaluates S-only, AS, and ASF planners through a design-then-evaluate-under-truth protocol that targets design misguidance rather than fit error. Fourth, it provides an evidence chain that moves from screening to mechanism-level counterexamples, isolated regime experiments, a mixed recommendation map, and a realistic airport-adjacent proxy case.

The paper is intentionally bounded. It does not claim that A/S/F is the globally minimal sufficient interface for all terminal models. It does not solve terminal layout design, scheduling, or detailed terminal operations. Instead, it offers a tested hierarchical interface family for strategic network design under an adopted truth class, together with upgrade rules for when a planner should move from S-only to AS and then to ASF.

## 2. Problem statement and hierarchical terminal interface

### 2.1. Terminal-coupled reusable-route network design

Consider a candidate graph composed of terminal nodes, waypoint nodes, corridor candidates, and connector candidates. The strategic planner chooses a subset of backbone corridors and connector edges and assigns demand over the resulting network. The classical abstraction collapses each terminal into a node with a scalar demand and, at most, an aggregate service or capacity surrogate. In a terminal-coupled design problem, that collapse can be decision-relevant: two network designs that appear equivalent under a node-level abstraction may perform differently once terminal-side admissibility, service interaction, or local neighborhood restrictions are restored.

The upper-level design object in this paper therefore remains strategic and network-oriented. The planner chooses (i) reusable backbone edges, (ii) terminal-to-network connectors, and (iii) demand routing over the selected structure. What changes is not the level of the decision problem but the information passed upward from the terminal.

### 2.2. Adopted terminal truth class

The richer benchmark used for evaluation is an adopted mesoscopic terminal truth class. It is not presented as the only correct operational model of a terminal. Its role is to define a benchmark that is structurally richer than the planning abstractions, sensitive to the kinds of errors the paper studies, and still tractable enough to support systematic re-evaluation of designed networks.

The truth class is organized around three network-facing channels.

**A: access admissibility.** A captures which connectors may legally or geometrically reach which terminal ports. It is induced by port orientation, sector width, interface regime, and context-specific directional or connector prohibitions. At the network level, A determines whether a connector-port pair is feasible.

**S: port-level service capability.** S represents how terminal-side resource competition enters strategic design. The underlying intuition is queueing-based: ports draw on scarce resources such as pads, merge points, waiting segments, release windows, or terminal-wide control capacity. Shared resources generate cross-port drag, and terminal-wide constraints induce saturation. Instead of carrying the full resource model into the network design layer, the adopted truth class compresses this into port-level convex service costs plus cross-port coupling terms over the design-relevant operating range.

**F: local footprint/conflict.** F represents the effect of the terminal neighborhood on nearby network edges. It includes hard local blocks and nominal local penalties that stand in for protected airspace, procedure exclusion, local control envelopes, and similar geometric or regulatory constructs. In the present manuscript, F is intentionally kept conservative in the main text: the emphasis is on hard blocks and nominal penalties rather than on a fully load-sensitive neighborhood-conflict theory.

### 2.3. Interface hierarchy

Three planning models are compared.

- **M0 (S-only):** the terminal is collapsed to a coarse node with only aggregate service information.
- **M1 (AS):** the terminal is expanded into ports and admissible connectors, and port-level service information is preserved.
- **M2 (ASF):** M1 is augmented with local footprint information in the form of blocked or penalized nearby edges.
- **M\***: the richer terminal truth benchmark used for evaluation.

The hierarchy is motivated by engineering parsimony. M0 is cheapest but least informative. M1 adds the geometry of terminal entry plus port-specific terminal-side cost. M2 further exposes the external effect of the terminal neighborhood on nearby network design.

## 3. Models and evaluation protocol

### 3.1. Design models

All planners operate on the same candidate graph. The design decision therefore differs only because each model sees a different terminal abstraction.

M0 evaluates connectors and route choices through aggregate terminal-side service terms. It cannot distinguish among ports and cannot prevent itself from selecting connectors that are infeasible under the richer admissibility structure.

M1 introduces port-aware admissibility and port-level service. It therefore distinguishes between connector feasibility and between cheap and expensive terminal entry points, but it ignores terminal-neighborhood effects on nearby external edges.

M2 inherits the M1 structure and adds nominal footprint information. Nearby candidate edges that are blocked or penalized by the terminal neighborhood are visible to the strategic planner.

### 3.2. Truth-based design evaluation

The paper does not compare planners by the objective values they compute under their own abstractions. Instead, it evaluates the network design produced by each planner under a common truth model.

The protocol is as follows.

1. Construct a shared candidate graph.
2. Solve the strategic design problem under each abstraction.
3. Freeze the selected network topology for each design.
4. Re-optimize the demand assignment under the common truth benchmark M\*.
5. Compare truth-evaluated objective values, regret, recovery, and topology differences.

This protocol is central because it targets the problem of interest: whether an abstraction misguides network design. A planner that solves its own simplified model perfectly may still be poor if the resulting topology performs badly once the omitted terminal-side information is restored.

### 3.3. Performance metrics

The primary metric is relative regret, defined as the truth-evaluated objective gap between a model’s design and the truth-best design, normalized by the truth-best objective. A design is called **sufficient** when its relative regret is below a preset threshold, set to 3% in the current experiments. Recovery rate measures how often a richer abstraction removes the positive regret of a coarser abstraction. Topology distance measures whether the selected network structure itself changes, rather than only its re-evaluated cost.

### 3.4. Scope of the claim

The evidence in this paper supports a **tested interface sufficiency** claim: within the adopted truth class, the chosen candidate-graph families, and the tested decision instances, the A/S/F hierarchy captures decision-relevant terminal heterogeneity and supports model-upgrade rules. The paper does **not** establish a universal minimum-sufficiency theorem. It also does not claim that a richer integrated network-terminal model would never uncover additional design-relevant information.

## 4. Experimental design

### 4.1. Screening experiment (EXP-0)

The first experiment is a screening test, not a discovery module. Six hundred base terminals are generated, and five coarse perturbation families are applied one at a time: port geometry, routing, operational configuration, context, and demand. For each perturbation, the experiment records terminal-side response magnitudes in A, S, and F. The purpose is to verify that none of the three channels is degenerate and to identify sensible parameter regions for the subsequent mechanism experiments.

**[Figure 1 about here]**  
*Figure 1. Screening design and channel-response heatmap for EXP-0.*

### 4.2. Minimal counterexamples (EXP-1 to EXP-3)

Three hand-built counterexample families isolate the independent necessity of A, S, and F.

- **EXP-1 (A necessity):** A minimal graph is constructed so that an apparently cheap connector is inadmissible or points to the wrong port under the truth model. The test includes both a hard-cut case and a soft case.
- **EXP-2 (S necessity):** Admissibility is held fixed while port-level service asymmetry is varied. The experiment scans demand intensity, travel-cost differences, and service asymmetry.
- **EXP-3 (F necessity):** A and S are held fixed while a terminal-neighborhood footprint blocks or penalizes a nearby edge, forcing a bypass when F becomes strong enough.

**[Figure 2 about here]**  
*Figure 2. Minimal counterexamples for A, S, and F.*

### 4.3. Multi-instance regime experiments (EXP-4A to EXP-4D)

The second layer of evidence moves beyond hand-built examples to synthetic families of network instances.

- **EXP-4A (calibration gate):** verifies that the piecewise-linear service approximation does not generate spurious signal when the footprint channel is inactive.
- **EXP-4B (A/S isolation):** fixes F at zero and scans demand intensity, access restrictiveness, and service asymmetry to identify where upgrading from M0 to M1 matters.
- **EXP-4C (F isolation):** holds A and S at moderate levels and scans footprint severity to identify where upgrading from M1 to M2 matters.
- **EXP-4D (mixed regime map):** combines multiple graph families and parameter combinations to produce a recommendation map over the M0/M1/M2 hierarchy.

The current synthetic experiments use open-city sparse graphs, open-city dense graphs, mixed graphs, and airport-adjacent graphs.

**[Figure 3 about here]**  
*Figure 3. Candidate-graph families and parameter grid used in EXP-4A to EXP-4D.*

### 4.4. Realistic proxy case study (EXP-5)

A fixed airport-adjacent network with six terminals and four waypoints is used as a more realistic proxy. Six scenarios combine three demand levels with relaxed versus constrained local context. The purpose is not to claim a broad external validation from one case, but to check whether the regime patterns found in the synthetic experiments survive in a larger and more interpretable network.

**[Figure 4 about here]**  
*Figure 4. Realistic airport-adjacent proxy network and scenario overlays.*

### 4.5. Planned benchmark layer against incumbent abstractions and an integrated upper bound

The next validation layer will compare the proposed hierarchy against two additional baselines on the same candidate graphs.

- **T0:** an incumbent pure-network abstraction in which each terminal is treated as a node with only aggregate service or capacity information.
- **T1:** an incumbent terminal-aware abstraction that exposes some terminal structure but not the proposed A/S/F interface.
- **RH:** a rule-based hierarchy-aware planner that chooses between M1 and M2 using the empirical upgrade rules.
- **JO:** a richer integrated benchmark or upper bound used only as a research tool for quality comparison, not as the paper’s main contribution.

The planned outputs are regret, topology distance, gap closure relative to T0/T1, and runtime. These comparisons are not yet inserted in the present draft and are therefore left as explicit placeholders.

**[Table 1 about here]**  
*Table 1. Planned external benchmark design: T0, T1, M1, M2, RH, and JO on shared candidate graphs.*

## 5. Results

### 5.1. Screening evidence supports the adopted interface hypothesis

The screening experiment confirms that all three channels respond non-trivially to terminal perturbations. No channel is dormant across the tested families. Routing perturbations induce the strongest S response, while context perturbations induce the strongest F response. Because EXP-0 is a screening experiment rather than a discovery procedure, its role is limited: it justifies the subsequent mechanism experiments and supports the adopted interface hypothesis, but it does not itself prove a unique factor-to-channel decomposition.

### 5.2. Minimal counterexamples show that A, S, and F can each independently mislead design

The A counterexample is numerically sharp. In the hard-cut setting, M0 chooses a connector that is infeasible under the truth model and therefore becomes infeasible after truth re-evaluation. In the soft setting, M0 incurs 331.6% relative regret, while M1 recovers the truth-best design with zero regret. This is strong evidence that access admissibility cannot be safely ignored when connector feasibility depends on terminal geometry and rules.

The S counterexample shows a different mechanism. Here admissibility is held fixed, so the mistake cannot be attributed to geometric access alone. At low demand, M0 and M1 coincide, but once demand intensity reaches moderate values the aggregate service abstraction breaks down. The mean regret of M0 rises from 0% at low load to 14.7% at the highest tested load, with maximum regret reaching 23.6%. M1 recovers the truth-best design in every positive-regret instance. Thus S is not merely a refinement of A; it is independently decision-relevant.

The F counterexample isolates terminal-neighborhood effects. With A and S fixed, a sufficiently strong footprint changes which external edge should be selected near the terminal. Under hard blocks, M1 fails catastrophically because it continues to use a now-blocked nearby edge, whereas M2 observes the footprint and recovers the correct bypass. This confirms that AS is not always sufficient: some terminal-coupled network designs require footprint-aware planning.

**[Table 2 about here]**  
*Table 2. Minimal-counterexample results for A, S, and F.*

### 5.3. Regime evidence identifies where to upgrade the abstraction

#### 5.3.1. Calibration gate

The calibration gate passes cleanly. In the subset with zero footprint severity, the median and 95th-percentile regret of M1 and M2 are both 0%, and the maximum is only 0.09%. This indicates that the later regime maps are not being drawn primarily by approximation error.

#### 5.3.2. Access boundary

With the footprint channel switched off, the value of upgrading from M0 to M1 becomes visible only once access restrictiveness is sufficiently strong. Across 898 valid instances, 44% show an M0-to-M1 upgrade value above 3%. The median gain remains near zero in mild-access regimes but jumps to 14.8% when effective access tightness reaches approximately 0.7. In other words, A behaves like a threshold channel: below a certain restrictiveness, the coarse model survives; above it, ignoring admissibility becomes costly.

#### 5.3.3. Footprint boundary

The footprint isolation experiment gives the clearest medium-scale boundary. At footprint severity 0.5, the median regret of M0, M1, and M2 is 2083.3%, 9.6%, and 0.6%, respectively, and the median M1-to-M2 upgrade value is +8.8%. This is decisive evidence that F becomes necessary in sufficiently strong terminal-neighborhood regimes. At lower footprint values (0.1–0.3), the current M2 formulation sometimes underperforms M1 due to conservative McCormick linearization of bilinear footprint terms. That pattern should be interpreted as a limitation of the current approximation, not as evidence that F is uninformative.

#### 5.3.4. Mixed recommendation map

The mixed regime experiment covers 864 synthetic network instances. Under a 3% sufficiency threshold, the overall sufficiency rates are 38.3% for M0, 72.3% for M1, and 67.9% for M2. The recommendation distribution is 46.3% M0, 38.4% M1, and 15.3% M2. When footprint severity is zero, M1 is recommended in 57% of instances; when footprint severity reaches 0.5, M2 is recommended in 45% of instances. These results show that the hierarchy is meaningful: M1 is not redundant relative to M0, and M2 is not universally dominant. Instead, different regimes justify different abstractions.

**[Figure 5 about here]**  
*Figure 5. Calibration gate and isolated-regime evidence for A and F.*

**[Figure 6 about here]**  
*Figure 6. Mixed recommendation map over the M0/M1/M2 hierarchy.*

### 5.4. Realistic proxy evidence is strongest for footprint-dominated airport-adjacent cases

The realistic airport-adjacent proxy supports the practical importance of F. In the most constrained high-demand scenario, relative regret is approximately 972.5% for M0, 972.6% for M1, and 52.1% for M2. In the relaxed high-demand scenario, M0 regret drops to 1.3%, indicating that coarse planning can be acceptable when strong local constraints are absent. The strongest realistic evidence therefore concerns footprint-dominated constrained cases: when nearby airport-related restrictions are active, ignoring the terminal neighborhood can drastically degrade the network design.

The same proxy also reveals a limitation. Across its six scenarios, M0 and M1 are almost identical. This means that the current realistic case is informative primarily about F and much less about A or S. The case study should therefore be read as a footprint-heavy realistic proxy rather than as a universal external validation of all three channels.

**[Figure 7 about here]**  
*Figure 7. Relaxed and constrained designs in the airport-adjacent proxy case.*

### 5.5. Placeholder for incumbent-abstraction and integrated-upper-bound benchmarks

**[Results to be inserted after completion of the benchmark layer described in Section 4.5.]**

The final manuscript will report, for T0, T1, M1, M2, RH, and JO, the truth-evaluated objective, relative regret, topology distance, gap closure over incumbent abstractions, and runtime. The intended comparison is not between a single proposed model and a single oracle, but between (i) incumbent abstractions, (ii) the proposed hierarchy-aware interface family, and (iii) a richer integrated upper bound used only as a research tool.

**[Figure 8 about here]**  
*Figure 8. Planned quality-time frontier for incumbent abstractions, hierarchy-aware planning, and the integrated upper bound.*

## 6. Discussion

The main deliverable of the paper is not a monolithic terminal model. It is a hierarchical, network-facing terminal interface family together with a truth-based evaluation protocol and empirically grounded upgrade rules. That is the contribution most likely to remain useful if the work is cited later. A future planner does not need to adopt the exact same truth class or the exact same optimization details to benefit from the central message: heterogeneous terminals can mislead strategic network design through access, service, and neighborhood channels, and the planner should expose only the channels that are needed in the regime at hand.

The current evidence is strongest on three points. First, terminals cannot always be treated as homogeneous nodes. Second, A, S, and F can each independently change the network design, as shown by the minimal counterexamples. Third, the medium-scale evidence already identifies a clear access boundary and a clear footprint boundary, while the mixed recommendation map shows that the hierarchy does not collapse into a single universally best model.

At the same time, the evidence is intentionally bounded. The paper does not prove that A/S/F is the globally minimal sufficient interface for all terminal representations. The service channel has a strong existence result but not yet a fully isolated medium-scale boundary of the same quality as A and F. The footprint channel is implemented conservatively in the main text and shows a known approximation artifact in moderate regimes when bilinear terms are linearized. The realistic proxy is more convincing for F than for A or S.

These limitations are manageable as long as the paper states its claim precisely. The safe claim is that A/S/F is a tested hierarchical interface family under the adopted truth class and tested decision instances. That claim is supported. The unsafe claim would be that A/S/F is the universal and globally minimal interface for all heterogeneous terminals. The present paper should not make that stronger claim.

The planned benchmark layer against incumbent abstractions and an integrated upper bound is the natural next step for strengthening the paper externally. If the same truth-based protocol shows that the hierarchy-aware planner both dominates incumbent abstractions and captures much of the value of the integrated upper bound at lower computational cost, then the interface argument will become substantially harder to dismiss from either the “why not stay coarse?” or the “why not fully integrate?” direction.

## 7. Conclusions

This paper studies a class of terminal-coupled reusable-route network design problems in which heterogeneous terminals cannot always be collapsed to homogeneous nodes without changing the quality of the resulting design. The central question is not how to keep enlarging the optimizer, but what terminal-side information must be exposed to the strategic network planner.

To answer that question, the paper proposes a hierarchical terminal interface with access admissibility, port-level service capability, and local footprint/conflict. The interface is evaluated using a design-then-evaluate-under-truth protocol that directly measures design misguidance. Minimal counterexamples show the independent necessity of A, S, and F. Synthetic regime experiments identify clear upgrade regions for A and F and yield a mixed recommendation map in which AS substantially outperforms the S-only abstraction while ASF becomes necessary in high-footprint regimes. A realistic airport-adjacent case further shows that ignoring terminal-neighborhood constraints can dramatically alter network design outcomes.

The paper therefore supports a practical conclusion: terminal complexity does not need to be lifted wholesale into strategic network optimization, but it also cannot be collapsed indiscriminately. A tested hierarchical interface, paired with regime-aware upgrade rules, offers a tractable middle ground for reusable low-altitude route network design.

## References

Bauranov, A., & Rakas, J. (2021). Designing airspace for urban air mobility: A review of concepts and approaches. Progress in Aerospace Sciences, 125, 100726. https://doi.org/10.1016/j.paerosci.2021.100726

Elhedhli, S., & Hu, F. X. (2005). Hub-and-spoke network design with congestion. Computers & Operations Research, 32(6), 1615-1632. https://doi.org/10.1016/j.cor.2003.11.016

Itoh, E., & Mitici, M. (2019). Queue-based modeling of the aircraft arrival process at a single airport. Aerospace, 6(10), 103. https://doi.org/10.3390/aerospace6100103

Kim, J., & Atkins, E. (2022). Airspace geofencing and flight planning for low-altitude, urban, small unmanned aircraft systems. Applied Sciences, 12(2), 576. https://doi.org/10.3390/app12020576

Shao, Q., Shao, M., & Lu, Y. (2021). Terminal area control rules and eVTOL adaptive scheduling model for multi-vertiport system in urban air mobility. Transportation Research Part C: Emerging Technologies, 132, 103385. https://doi.org/10.1016/j.trc.2021.103385

Shone, R., Glazebrook, K., & Zografos, K. G. (2021). Applications of stochastic modeling in air traffic management: Methods, challenges and opportunities for solving air traffic problems under uncertainty. European Journal of Operational Research, 292(1), 1-26. https://doi.org/10.1016/j.ejor.2020.10.039

Vascik, P. D., Cho, J., Bulusu, V., & Polishchuk, V. (2020). A geometric approach towards airspace assessment for emerging operations. Journal of Air Transportation, 28(3), 124-133. https://doi.org/10.2514/1.D0183

Willey, L. C., & Salmon, J. L. (2021). A method for urban air mobility network design using hub location and subgraph isomorphism. Transportation Research Part C: Emerging Technologies, 125, 102997. https://doi.org/10.1016/j.trc.2021.102997