# EXP-1 实验报告：A 的必要性

## 1. 报告首页

- 报告编号：EXP-1-20260403
- 实验日期：2026-04-03
- 实验模块：EXP-1
- 执行人：Claude + 狗修金sama
- 代码分支/提交号：master / 77b7a1a (MATLAB), d35ae64 (Python)
- 求解器与版本：MATLAB intlinprog (R2024b) + Python Gurobi 13.0.1
- 报告状态：初稿
- 对应研究问题：[x] A 的必要性（admissibility 信息是否不可省）

## 2. 实验目的与预期

### 2.1 本次实验目的
证明 S-only 模型（M0）由于看不见 connector-port admissibility，会在某些 terminal 配置下选错网络拓扑。

### 2.2 对应假设/预期现象
- M0 偏向选外部成本最低的 backbone edge，即使该 edge 的 connector 在 truth 下不可行或指向高成本 port
- M1 看见 admissibility + port-level service → 纠正错误 → regret ≈ 0

### 2.3 与实验链的关系
- 上游依赖：无（第一个存在性实验）
- 下游影响：Go → 可进入 EXP-2

### 2.4 成功判据（预注册）
M0 出现稳定正 regret 或 truth-infeasibility；M1 regret ≈ 0。

## 3. 口径核对清单

1. M0/M1/M* 共享同一候选图 G⁺：**是**
2. Truth evaluation 使用统一 M* 重算流分配：**是**（quadprog 精确 QP）
3. Regret = truth-evaluated 差值：**是**
4. M1 port service 从 truth 拟合：**是**（fitPortService 精确恢复 a, b）
5. MIP gap ≤ 0.1%：**是**（intlinprog AbsoluteGapTolerance=1e-6）
6. Random seed 记录：**是**（手工图，确定性）

## 4. 环境设置

### 4.1 候选图
- 图族类型：手工构造（最小反例）
- Terminal 数量：1 (T)
- Waypoint 数量：2 (Sw, Se) 或 3 (含 link)
- Backbone 候选边数：2-3

### Scenario A: Hard-cut（Python Gurobi）
```
S(source) --E_north(cheap, 不可行)--> T(1 port, east-facing)
S2(source) --E_east(expensive, 可行)--> T
S --E_link-- S2 (绕行路径)
```
h1 面向 east（0°±40°），E_north 方向 90° → **不可行**。

### Scenario B: Soft（MATLAB + Python）
```
Sw(west) --Ew(cheap travel=1.0)--> T --h2(west, b=2.0, 贵)
Se(east) --Ee(expensive travel=1.5)--> T --h1(east, b=0.2, 便宜)
Sw --Elk-- Se (绕行)
```
两个 port 都 admissible 到各自方向的 edge，但 service cost 差 10 倍。

### 4.2 Terminal 配置

| Terminal | Ports | μ̄ | ψ_sat | 说明 |
|----------|-------|-----|-------|------|
| T (hard-cut) | h1: 0°±40°, a=0.1, b=0.3 | 20 | 2 | 只 admit east |
| T (soft) | h1: 0°±50°, a=0.1, b=0.2; h2: 180°±50°, a=0.1, b=2.0 | 10 | 2 | h2 比 h1 贵 10× |

### 4.3 需求
- Hard-cut: S2→T, demand=5.0
- Soft: Sw→T, demand=5.0

## 5. 参数设置
- Hard-cut: 无参数扫描，单一 instance
- Soft (Python): κ_S ∈ {1.0, 1.5, 2.0, 3.0}, demand=3.0

## 6. EXP-1 专用字段
- 手工图结构：见 §4.1
- Aggregate service 是否精确相同：Soft 场景中两 port 的 a 相同(0.1)，b 不同 → aggregate 是均值
- 穷举 topology 数量：Hard-cut 全自动 MILP；Soft 4 个 κ_S 参数点

## 7. 实验过程记录

| 步骤 | 操作 | 异常 |
|------|------|------|
| 1 | 手工构建 ProblemInstance | 无 |
| 2 | accessTruth 计算 admissibility | Hard-cut: h1 不 admit E_north ✓ |
| 3 | 建 connectors（含不可行的，M0 需要） | 无 |
| 4 | computeRegret 跑 M*/M0/M1 | 无 |
| 5 | 验证 regret ≥ 0 | 通过 |

## 8. 实验结果（定量）

### 8.1 Hard-cut（Python Gurobi）

| 模型 | J^truth | Δ | Δ/J*(%) | TD^bb | 选边 |
|------|---------|---|---------|-------|------|
| M* | 17.05 | 0 | 0 | 0 | E_east, E_north |
| M1 | 17.05 | 0.00 | 0.0% | 0.00 | E_east, E_north |
| M0 | ∞ | ∞ | ∞ | 0.50 | E_north 仅 |

M0 只选了 E_north（便宜），但 truth 下 E_north connector 不可行 → 所有需求 unmet → 巨额惩罚。

### 8.2 Soft（MATLAB intlinprog，demand=5.0, κ_S 隐含在 b=2.0）

| 模型 | J^truth | Δ | Δ/J*(%) | TD^bb | 选边 |
|------|---------|---|---------|-------|------|
| M* | 12.94 | 0 | 0 | 0 | Ee, Ew |
| M1 | 12.94 | 0.00 | 0.0% | 0.00 | Ee, Ew |
| M0 | 55.85 | 42.91 | 331.6% | 0.50 | Ew 仅 |

M0 只选 Ew（travel 便宜=1.0），全部 5.0 流量走 h2（b=2.0）→ service cost = 0.1×5+2.0×25=50.5。
M* 开两条边，流量走 h1（b=0.2）→ service cost = 0.1×5+0.2×25=5.5，省了 45。

### 8.3 Soft 参数扫描（Python Gurobi，demand=3.0）

| κ_S | M0 Δ/J* | M1 Δ/J* | M0 选边 | M* 选边 |
|-----|---------|---------|---------|---------|
| 1.0 | 7.6% | 0.0% | E_east | E_east, E_west |
| 1.5 | 4.1% | 0.0% | E_east | E_east, E_west |
| 2.0 | 1.8% | 0.0% | E_east | E_east, E_west |
| 3.0 | 0.0% | 0.0% | E_east | E_east |

### 8.4 Sufficiency 判定

| 模型 | |Δ/J*| ≤ 3%? | |Δ/J*| ≤ 5%? | 判定 |
|------|-------------|-------------|------|
| M1 | ✅ 全部 | ✅ 全部 | 充分 |
| M0 | ❌ hard-cut ∞, soft 331% | ❌ | 不充分 |

## 9. 初步分析

### 9.1 结果是否符合预期
**完全符合。**
- Hard-cut: M0 选了 inadmissible 边 → 预期的 infeasibility
- Soft: M0 走便宜 travel 但贵 port → 预期的 positive regret
- M1 在所有 case 中 regret=0 → 预期的纠正

### 9.2 对研究问题的含义
**A 信息（admissibility）不可省略。** 当 terminal port 有方向限制时，忽略 A 会导致两种错误：
1. **硬切错误**：选了根本接不上的 connector → 需求不可达
2. **软错误**：选了 admissible 但 service 昂贵的 port → 成本飙升

### 9.3 错误归因分析
M0 的 regret **100% 来自 A 信息缺失**：
- Hard-cut: 方向不匹配导致 connector infeasible（A 信息）
- Soft: 无法区分 port → 无法优化 port-level flow allocation（A+S 联合信息）

### 9.4 是否发现 regime 边界或阈值效应
Soft 扫描显示 κ_S=3.0 时 M0 regret 消失——因为当一个 port 极贵时，M* 也只选单边，与 M0 一致。**A 信息的价值在中等不对称时最大。**

### 9.5 异常迹象
无。所有 regret ≥ 0。

### 9.6 Stop/Go 判定
**Go。** M0 在 hard-cut 下出现 infeasibility，在 soft 下出现稳定正 regret（最高 331.6%），满足 Go 条件。

### 9.7 下一步
进入 EXP-2（S 的必要性）。

## 10. 审核结论
- 审核意见：待复核
- 可进入论文主文：**是**（hard-cut 作为 Proposition 数值验证，soft 作为参数化反例）
