# Baseline 候选论文全文阅读笔记

> 目标论文："面向低空可复用航路网络设计的终端区决策保持抽象"
> 阅读日期：2026-04-01

---

## 1. Stuive & Gzara (2024, TRC) — Airspace network design for urban UAV traffic management with congestion

**DOI**: 10.1016/j.trc.2024.104882

### 核心思想
UTM 提供商从城市道路网络中选择一个子集，将其投影到空中作为 3D 走廊网络。用 CSO（约束系统最优）交通分配评估候选网络质量，BPR 函数建模拥塞。

### 数学模型 (UTM-TT)

| 要素 | 内容 |
|------|------|
| 图 | $G = (N, A)$，$N$ = 道路交叉口，$A$ = 路段 |
| 决策变量 | $z_{ij} \in \{0,1\}$（弧激活）；$x_{ij}^k \in \{0,1\}$（OD对k走弧(i,j)）；$f_{ij}$（弧上总流量） |
| 目标函数 | $\min \sum_{(i,j) \in A'} t_{ij}(f_{ij}) \cdot f_{ij}$（最小化总出行时间，含BPR拥塞） |
| 约束 (1b) | **多商品流守恒**：$\sum_j x_{ij}^k - \sum_j x_{ji}^k = b_i^k$ |
| 约束 (1c) | 流量聚合：$f_{ij} = \sum_k d^k x_{ij}^k$ |
| 约束 (1d) | 设计强制：$x_{ij}^k \leq z_{ij}$ |
| 约束 (1e) | 路径长度限制（电池续航） |
| 约束 (1f) | 预算约束：$\sum c_{ij} z_{ij} \leq B$ |
| 拥塞函数 | BPR：$t(f) = t_{FF}(1 + \alpha(f/\kappa)^\beta)$，仿真标定3D空域容量参数κ |

**本质：Fixed-Charge Network Design + CSO Traffic Assignment**

### 求解方法
- 非线性 → PWL 近似 (UTM-TT-PWL)
- 分段线性化 BPR 函数，转为 MILP

### 终端建模
**纯点（A(-1)级别）**——节点是道路交叉口，无容量、无延迟、无空域占用。终端在模型中完全透明。

### 案例研究
芝加哥市中心。分析了预算、拥塞、最小路径偏差、需求模式对网络设计的影响。

### 与任务的匹配度

| 任务要求 | 匹配度 | 说明 |
|---------|--------|------|
| 走廊激活决策 | ✅ 完美 | $z_{ij}$ 弧激活 |
| 流量分配 | ✅ 完美 | 多商品流 $x_{ij}^k$ |
| 数学模型 | ✅ 完美 | 完整 MIP + PWL |
| 候选走廊集 | ✅ 完美 | 道路子集选择 |
| 拥塞/容量 | ✅ 完美 | BPR 拥塞函数 |
| 终端容量 | ❌ 无 | 纯点节点 |
| 应用域 | ✅ | 城市无人机 UTM |

### 结论
**最佳 A0 baseline**。决策结构完全匹配 MCND，终端零建模正好做升级实验。

### 注意事项
- 不是 vertiport 概念——节点是道路交叉口
- 单向拥塞——counter-flow 不影响行驶时间
- PWL 近似是实际求解版本

---

## 2. Wei, Gao, Clarke & Topcu (2024, TRB) — Risk-aware UAM network design with overflow redundancy

**DOI**: 10.1016/j.trb.2024.102967

### 核心思想
给已有 UAM 网络加"备用容量"——在候选位置建少量 backup vertiport + backup flight corridor，在节点/链路容量随机退化时提供分流能力，最大化期望吞吐量。

### 网络模型

**原始网络** $\mathcal{N}$：
- 图 $\mathcal{G} = (\mathcal{V}, \mathcal{E})$
- 节点 = vertiport（容量 $c_v$），链路 = flight corridor（容量 $c_e$）
- **容量可随机退化**：$c_{ev} \in \{c_{ev,0}, c_{ev,1}, ..., c_{ev,k_{ev}}\}$，离散概率分布

**吞吐量** $S^*$（Definition 3, Eq. 7）：
$$S^* = \max_{X,D_1,D_2} \mathbf{1}^T D_1^T \mathbf{1}$$
s.t. 流守恒、节点容量、链路容量

**扩展网络**（加入 backup 后）：
- $\mathcal{V}' = \mathcal{V} \cup \mathcal{V}^b$，$\mathcal{E}' = \mathcal{E} \cup \mathcal{E}^b$
- 扰动时流量可重路由到备用节点/链路

### 优化模型 (Section 4.1)
- 决策：$Z \in \{0,1\}^{|\mathcal{V}^b| \times \bar{n}_Z}$（备用点位置 + 容量等级选择）
- 目标：$\max \mathbb{E}[S^*(\mathcal{N}^{ext}(ev,k))]$（最大化期望吞吐量）
- 预算：$\mathbf{1}^T(Z \odot F)\mathbf{1} \leq \bar{J}$
- **双层双线性 → MILP**（Theorem 1: LP 对偶 + bilinear → McCormick linearization）

### 终端建模
**有容量**（$c_v$ 节点容量 + 随机退化 + 备用容量决策），但**无延迟函数**（硬上界，不是 BPR 式拥塞）

### 案例研究
Milwaukee（7 vertiport, 12 corridor）、Atlanta（11, 58）、Dallas-Fort Worth（15, 64）

### 与任务的匹配度

| 任务要求 | 匹配度 | 说明 |
|---------|--------|------|
| 走廊激活决策 | ⚠️ 部分 | 备用走廊隐含决策（由备用节点决定），非显式弧激活 |
| 节点容量 | ✅ 显式 | $c_v$ + 随机退化 + 备用容量选择 |
| 流守恒 | ✅ | 多商品流 |
| 数学模型 | ✅ 严格 | MILP，有定理证明 |
| 拥塞 | ❌ | 硬容量上界，无延迟函数 |

### 结论
**适合当"节点容量如何影响网络设计"的参考**。不太适合直接当 A0 baseline（问题是"加backup"不是"从零设计"）。文献综述 Section 2 很有价值（network redundancy + capacity + NDP 三方向交叉）。

---

## 3. Kim et al. (2025/2026, DSA) — Centralized and distributed optimization of AAM strategic traffic management

**DOI**: 10.1139/dsa-2025-0020

### 核心思想
一体化解决 AAM 的空域扇区化 + 走廊路径规划 + 交通流优化。集中式（单一 MIP）和分布式（PSU 间合作博弈）两种框架。

### 三层方法

**Layer 1：空域扇区化**
- Louvain 社区检测 + Voronoi 图
- 权重函数 $w_i = \alpha_1 \mathcal{G}_i + \alpha_2 \mathcal{N}_i + \alpha_3 \mathcal{H}_i + \alpha_4 \mathcal{Q}_i$（距离、连通度、人口相似度、容量相似度）
- 输出：各 PSU 管辖区域

**Layer 2：走廊路径规划**
- 两种方法：distance-based Dijkstra vs weighted Dijkstra
- 走廊容量：$k_i = \frac{d_i}{d_s} \times h_i$（长度/间隔 × 垂直层数）
- 多车道双向走廊结构（Fig. 5）

**Layer 3：交通流优化 (MIP, Eq. 4-13)**

| 要素 | 内容 |
|------|------|
| 决策变量 | $w_{f,t}^{dep}$, $w_{f,t}^{arr}$, $w_{f,t}^k$（航班f在时刻t的起飞/到达/走廊到达状态） |
| 目标函数 | 最小化加权总延误（起飞延误 + 空中延误），含服务优先级 $s_f$ 和公平性 $\epsilon$ |
| 约束 (5a/5b) | **时变 vertiport 起飞/降落容量**：$\sum(w^{dep}) \leq \mathcal{T}_{v,t}$，$\sum(w^{arr}) \leq \mathcal{L}_{v,t}$ |
| 约束 (6) | **走廊吞吐量容量**：$\sum(w^k) \leq \mathcal{M}_k$ |
| 约束 (7a/7b) | 走廊最小/最大通过时间（飞行器速度范围） |
| 约束 (11-13) | 空间冲突区域的时序解脱（big-M） |

**分布式博弈论**：PSU 间合作博弈（Shapley 值），各 PSU 内独立 MIP

### 终端建模
**有容量（时变）**：$\mathcal{T}_{v,t}$（起飞容量）、$\mathcal{L}_{v,t}$（降落容量），按时间步变化。

### 走廊建模
- 多车道双向走廊（Fig. 5）
- 7 种空间冲突类型（Fig. 6）：起降冲突、交叉冲突、中空交叉、共享 vertiport 等
- 容量由几何参数决定

### 案例研究
人工城市地图，150/300 架飞行器，Monte Carlo 仿真，三种飞行器配置（multicopter/vectored thrust/lift-and-cruise），三种服务优先级（regular/express/medical）

### 与任务的匹配度

| 任务要求 | 匹配度 | 说明 |
|---------|--------|------|
| 走廊选择 | ❌ | 走廊由 Dijkstra 生成后固定，不做选择优化 |
| 节点容量 | ✅ 时变 | $\mathcal{T}_{v,t}$, $\mathcal{L}_{v,t}$ |
| 走廊容量 | ✅ | $\mathcal{M}_k$ 几何计算 |
| 冲突解脱 | ✅ | 7种空间冲突 + 时序解脱 |
| 多飞行器类型 | ✅ | 3种配置 |

### 结论
**不适合当 baseline**（不是 NDP），但在以下方面有重要参考价值：
- **Fig. 3 的 ConOps 对比表**：总结了 13 个组织的走廊概念
- **Fig. 5 多车道走廊 + Fig. 6 七种冲突**：论证终端区空域占用的重要性
- **时变起降容量**：可以讨论与 A0 聚合延迟 $D$ 的关系

---

## 4. He, Li et al. (2024, TRC) — A distributed route network planning method with congestion pricing for drone delivery services in cities

**DOI**: 10.1016/j.trc.2024.104536

### 核心思想
为城市无人机配送设计**空间分离的航路网络**。创新点：用拥塞定价（congestion pricing）作为软约束替代硬冲突消解，分布式协调多 OD 对路径。灵感来自美团深圳无人机配送实践。

### 问题结构
- 城市空间离散化为 3D 网格（grid cells）
- 每个 OD 对 $(o_n, d_n)$ 有一条路线 $r_n$（waypoint 序列）
- 路线连接 vertiport 的 **departing fix** 和 **approaching fix**
- **路线间必须空间分离**——路径占据的 3D 体积（含 buffer zone）不重叠

### 数学模型

**原始问题 (Problem 1, Eq. 1a-1e)**：
$$\min_{r_{[N]}} \sum_{n \in [N]} C_o(r_n) + \alpha_a C_a(r_{[N]}) + \alpha_i C_i(r_{[N]})$$

| 成本项 | 说明 |
|--------|------|
| $C_o(r_n)$ | 个体运营成本 = $\sum[a_g D_g + a_c D_c + a_d D_d + a_y |Y|]$（地面距离+爬升+下降+转弯） |
| $C_a(r_{[N]})$ | **空域占用成本** = $card(\bigcup_n \mathcal{M}(r_n))$（所有路径占用的总网格数） |
| $C_i(r_{[N]})$ | **影响成本** = $\sum_{a \in \bigcup \mathcal{M}(r_n)} I(a)$（噪声/隐私/风险） |

约束：
- (1b-1c)：飞行能力约束（转弯角 $\lambda_y$、俯仰角 $\lambda_d$ 限制）
- (1d)：障碍物回避 $\mathcal{M}(r_n) \cap B = \emptyset$
- **(1e)：路径间空间无冲突** $\mathcal{M}(r_i) \cap \mathcal{M}(r_j) = \emptyset, \forall i \neq j$

**拥塞定价改造 (Problem 7a, Eq. 7a-7d)**：

将硬冲突约束 (1e) 松弛为拥塞定价：
$$\min \sum_n C_o(r_n) + \alpha_a C_a + \alpha_i C_i + \alpha_t \sum_n C_t(r_n)$$

其中 $C_t(r_n) = C_j(r_{[N]}) - C_j(r_{-n})$（路线 $n$ 对系统拥塞的**边际贡献**）。
拥塞水平按网格计算：$C_j(g) = 4 C_p(g)(C_p(g)-1)/2 + C_p(g) \cdot C_b(g)$

### 求解方法 (DRP-CGSTN)
分布式迭代：
1. **初始路径生成**：各 OD 对用 Extended Theta* 独立生成最优单路径
2. **拥塞评估**：按网格统计路径重叠
3. **拥塞缓解方案**：各路线提出绕行方案，目标函数 (Eq. 8) 加入拥塞定价项
4. **增益评估与排序**：选增益最大的方案执行
5. **迭代**直到无冲突

### 终端建模
有 **approaching fix** 和 **departing fix** 概念（Fig. 3b），但终端本身**无容量建模**。Vertiport 只是路线的起止点。

### 空域占用建模
✅ 显式。$\mathcal{M}(r_n)$ 计算每条路径占据的 3D 网格集合（含 buffer zone）。空域占用成本 $C_a$ 最小化总占用。

### 案例研究
- Toy examples（2D）
- 标准 2D 场景（50×50, 100×100 网格）
- 真实场景：香港旺角（Mong Kok）

### 与任务的匹配度

| 任务要求 | 匹配度 | 说明 |
|---------|--------|------|
| 走廊/路径选择 | ✅ | 每个 OD 对选择路线（分布式优化） |
| 终端接口 | ✅ 概念 | approaching/departing fix（Fig. 3b） |
| 空域占用 | ✅ 显式 | $\mathcal{M}(r_n)$ 3D网格体积 + $C_a$ 成本 |
| 拥塞 | ✅ 创新 | 拥塞定价作为软约束 |
| 数学模型 | ✅ | 有形式化问题定义（Problem 1, 7a） |
| 多商品流 | ❌ | 分布式路径搜索，非经典网络流 |
| 网络设计 | ⚠️ | 多路径联合规划，但非经典 NDP 弧激活 |

### 结论
**不适合直接当 A0 baseline**（数学结构与 MCND 差异大），但在以下方面极具参考价值：
- **Fig. 3b 的路线结构图**：approaching/departing fix + buffer zone = 您论文中"终端区接口"的概念原型
- **空域占用成本 $C_a$**：直接对应 A2 抽象层级的空域脚印
- **影响成本 $C_i$**：对应 A2 的外部性
- **拥塞定价机制**：替代 BPR 的拥塞建模思路

---

## 5. He, Sun et al. (2026, IEEE TITS) — A Hierarchical Optimization Method for eVTOL Network Design

**DOI**: 10.1109/TITS.2025.3648294

### 核心思想
eVTOL vertiport 选址的大规模求解方法。决策是选哪些 vertiport 开通（不是走廊设计）。

### 数学模型 (ILP, Eq. 1-9)
- 决策变量：$x_p \in \{0,1\}$（vertiport 开/关）；$y_{ipqj} \in \{0,1\}$（eVTOL 路径激活）
- 目标函数：$\max \sum F_{ipqj}$（最大化可行 eVTOL 需求，binary logit 模式选择）
- 约束：飞行距离上下限、出行时间竞争力（省40%+）、vertiport 总数 ≤ h

### 终端建模
**纯点**——只有开/关（$x_p$），无容量、无延迟、无空域。

### 方法贡献
HOME 启发式：分组子集选择 + 精英合并，解大规模 ILP。南加州案例。

### 结论
**不适合当 baseline**（纯选址，非走廊设计）。但 **Table I 的文献分类**（6类 vertiport 网络设计方法的优缺点对比）可直接用于 related work。

---

## 横向对比总结

| 维度 | Stuive & Gzara | Wei et al. | Kim et al. | He (TRC) | He (TITS) |
|------|---------------|------------|------------|----------|-----------|
| **核心问题** | 选子集建网络 | 加备用节点 | 交通调度 | 多路径联合规划 | 选址 |
| **走廊激活** | ✅ $z_{ij}$ | ⚠️ 隐含 | ❌ 给定 | ⚠️ 路径选择 | ❌ |
| **节点容量** | ❌ 无 | ✅ 随机退化 | ✅ 时变 | ❌ 无 | ❌ 无 |
| **走廊容量** | ✅ BPR | ✅ 硬上界 | ✅ 几何 | ✅ 拥塞定价 | ❌ |
| **多商品流** | ✅ | ✅ | ❌ | ❌ | ❌ |
| **进离场接口** | ❌ | ❌ | ❌ | ✅ fix | ❌ |
| **空域占用** | ❌ | ❌ | ✅ 冲突区 | ✅ 网格体积 | ❌ |
| **适合当baseline** | **✅ 最佳** | 参考 | 参考 | 参考 | 不适合 |

## 综合推荐

1. **A0 Baseline → Stuive & Gzara (2024, TRC)**：MCND 结构最匹配，终端零建模正好做升级
2. **终端区接口概念 → He et al. (2024, TRC)**：approaching/departing fix + 空域占用
3. **节点容量影响 → Wei et al. (2024, TRB)**：vertiport 容量退化改变网络设计
4. **运行层约束 → Kim et al. (2025, DSA)**：时变起降容量 + 走廊冲突分类
5. **文献分类表 → He et al. (2026, TITS)**：Table I vertiport 网络设计方法综述
