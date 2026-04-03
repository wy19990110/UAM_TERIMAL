# 实验问题清单与待解决事项（2026-04-03）

本文档汇总 EXP-1~4 全部实验中发现的问题、异常、设计缺陷和待决事项。
每个问题标注严重等级、影响范围和建议处理方向。

---

## ISSUE-1：M1(AS) 未明显优于 M0(S-only)

**严重等级：🔴 高（影响论文主张）**

### 现象
EXP-4 中 M1 sufficiency (59%) ≈ M0 sufficiency (60%)，αA 和 κS 变化对 M0→M1 的分离几乎无效应。在 mini 验证中甚至出现 M1 regret > M0 regret 的情况（instance #8: M1=36.4% vs M0=23.2%）。

### 预期
M1 信息 ⊃ M0 信息，因此 M1 的 truth-evaluated regret 应 ≤ M0。在 αA 增大（access restrictiveness 增强）时，M1 应明显优于 M0。

### 可能原因

**原因 A：PwL 近似质量差异掩盖了信息优势**
- M0 用 aggregate PwL（一元函数，7 段）
- M1 用 per-port PwL（多个一元函数，各 7 段）
- 在某些实例上，M0 的 aggregate PwL "碰巧"给出了更好的拓扑选择
- 证据：φF=0 时所有模型都有 ~10% 不 sufficient → PwL 误差是普遍问题

**原因 B：图生成策略导致 admissibility 约束对 M0 无效**
- `buildSynthetic` 中 port 方向对齐 incident edge 方向 → 大多数 connector 对 M0 也 admissible
- M0 虽然没有 admissibility 约束，但可选的 connector 和 M1 几乎相同
- 需要检查：每个实例中 M0 实际可用的 connector 数 vs M1 实际可用的 connector 数

**原因 C：κS 的实际效应被稀释**
- κS 通过 port b 系数比值控制
- 但 PwL 只用了切线下界（线性化了二次项），可能在 MILP 中看不到 port 间的 b 差异
- EXP-2（手工图，Gurobi MIQP 直接二次目标）中 κS 效应显著 → 问题出在 PwL 线性化

### 建议处理

1. **短期验证**：在几个 M1>M0 的实例上，打印 M0 和 M1 的 MILP 选边和 connector 选择，比对差异来源
2. **增加 PwL 精度**：nPwl 从 7 增到 15-20，重跑 mini 看 M1 是否分离
3. **图生成改进**：生成时刻意加入一些"方向偏离"的 port（不对齐 incident edge），让 admissibility 约束真正起作用
4. **终极方案**：考虑用 MATLAB 的 `fmincon` 做 MINLP（固定整数后 NLP），避免 PwL 误差

### 对论文的影响
如果 M1 确实无法在全网实验中显著优于 M0，论文结论需要从"三段式 regime (S→AS→ASF)"调整为"二段式 (S→ASF)"。这仍然有价值——说明 A 和 S 的信息需要与 F 一起才有实际意义，单独加 A/S 不够。但需要重新审视 EXP-1/2 的小规模反例在全网中被稀释的原因。

---

## ISSUE-2：~10% Baseline Regret（PwL vs QP 口径差）

**严重等级：🟡 中（影响数值精度，不影响定性结论）**

### 现象
φF=0 时所有模型（M0/M1/M2）的 sufficiency 都只有 ~90% 而非 100%。此时三个模型理应等价（无 footprint 差异），但仍有 ~10% 的实例 regret > 3%。

### 原因
MILP 目标函数用 PwL 切线下界近似 b·λ²，而 truth evaluator 用 quadprog 精确 QP。两者的最优解不同，导致 MILP 选的拓扑在 QP 口径下不是最优。

虽然 `computeRegret` 已修复为"取跨所有模型的 truth-best J*"（消除了负 regret），但 PwL 近似仍然让所有模型的 MILP 阶段都有误差。

### 证据
- φF=0, M0=M1=M2=90% suff（三者完全相同 → 误差来自共享的 PwL 近似，不是模型差异）
- EXP-2（Gurobi MIQP，无 PwL）中 M1 regret 精确为 0 → PwL 是唯一误差源

### 建议处理

1. **增加 PwL 段数**：7→15→30，量化 suff 改善
2. **用凸包近似代替切线下界**：切线下界是 lower bound，凸包（弦插值）是 upper bound。两者的最优解偏差方向不同。可以考虑用两者的平均或用更精细的 SOS2
3. **报告中标注**："所有 sufficiency 数值包含 PwL 近似导致的 ~X% baseline regret"

### 对论文的影响
定性结论不变（φF 是主导因子），但数值上 M2 的 91% suff 可能在精确求解下更接近 95-100%。需要在论文中说明 PwL 近似的存在和量级。

---

## ISSUE-3：M1 Regret > M0 Regret 的具体实例

**严重等级：🟡 中（理论违反，但原因已知）**

### 现象
Mini 验证 instance #8（ρ=0.5, αA=0.25, κS=2, φF=0.3）中 M1 regret=36.4% > M0 regret=23.2%。

### 原因
M1 和 M0 的 MILP 使用不同的 PwL 近似（M0 aggregate vs M1 per-port），两者近似误差方向不同。在某些实例上 M1 的 per-port PwL 恰好引导 MILP 选了一个 truth 口径下更差的拓扑。

### 说明
这不是理论违反——理论上 M1 信息 ⊃ M0 只保证**在精确求解下** M1 regret ≤ M0。当两个模型都用不精确的求解方法（PwL MILP）时，"信息更多"不等于"近似更准"。

### 建议处理
1. 在 EXP-4 报告中说明：M1>M0 是 PwL 近似 artifact，非理论违反
2. 如果精确求解（MIQP 或 enumeration）后 M1>M0 仍然出现，则需要重新审查接口提取逻辑

---

## ISSUE-4：J* 定义的修正及其含义

**严重等级：🟢 低（已修复，需在论文中说明）**

### 现象
原始实现中 J* = truthEval(design_Mstar)。但 M* MILP(PwL) 选的拓扑在 truth(QP) 下不一定最优 → 出现负 regret。

### 修复
J* = min over all models {truthEval(design_i)}。即取所有模型设计中 truth 口径下最好的一个作为 benchmark。

### 含义
这个修复在实际操作中是合理的——benchmark 应该是"能找到的最好设计"，不限于特定模型。但需要在论文中明确说明 J* 的定义：

> J* = min_{y ∈ {y_M0, y_M1, y_M2, y_M*}} J^truth(y)

而非：

> J* = J^truth(y_M*)

这两个定义在精确求解下等价（因为 M* 的可行域最大），但在近似求解下不等价。

---

## ISSUE-5：合成图中 admissible connector 比例可能过高

**严重等级：🟡 中（影响 EXP-4 中 A 信息的区分力）**

### 现象
`buildSynthetic` 将 port 方向对齐 incident edge 方向，导致大部分 connector 都是 admissible 的。M0 虽然不检查 admissibility，但实际可选的 connector 和 M1 相同 → A 信息无区分力。

### 量化缺失
尚未统计每个实例中：
- M0 可用 connector 数（=全部 connector）
- M1 可用 connector 数（=admissible connector）
- 二者的 Jaccard 距离

### 建议处理
1. **统计**：对 EXP-4 的 972 个实例，计算上述比值
2. **改进图生成**：生成后随机旋转部分 port 方向（±20°~±40°偏移），降低 admissible 比例
3. **增加 non-incident connector**：为每个 port 生成 1-2 个不 incident 的 backbone edge 的 connector，让 M0 有"错误选项"

---

## ISSUE-6：Truth evaluator 简化了饱和惩罚

**严重等级：🟢 低（当前实验中 μ̄ 较大，饱和很少触发）**

### 现象
`truthEvaluate` 中 ψ[Λ-μ̄]²₊ 饱和惩罚被简化处理——quadprog 是无约束 QP，没有显式建模 [·]₊ 的非光滑性。

### 影响
当 Σλ_h < μ̄ 时无影响（大部分 case）。当 Σλ_h > μ̄ 时，quadprog 的二次项可能无法精确模拟分段二次的饱和惩罚。

### 建议处理
1. 检查 EXP-4 中有多少实例的 port load 超过 μ̄
2. 如果比例显著，改用 `fmincon` 替代 `quadprog` 以精确处理 [·]₊

---

## ISSUE-7：单商品流简化

**严重等级：🟡 中（影响 regime map 的真实性）**

### 现象
`solveMILP` 使用单商品流（aggregate demand）而非多商品流（per-OD commodity）。这意味着不同 OD 对的流量可以在网络中任意混合，不需要各自满足流守恒。

### 影响
单商品流允许"搭便车"：OD1 的流量可以经由 OD2 的最优路径走。这使得所有模型的目标值偏低，可能减小 regret 差异。

### 建议处理
1. 实现多商品流版本（变量数 × nK 倍，但 intlinprog 无变量限制）
2. 对比单商品 vs 多商品的 regime map 差异
3. 优先级较低——单商品已经能展示 regime 分离

---

## ISSUE-8：EXP-2/3 数据口径（Python Gurobi MIQP vs MATLAB intlinprog+PwL）

**严重等级：🟢 低（存在性实验不要求精确一致）**

### 现象
EXP-2 和 EXP-3 的数据来自 Python Gurobi（直接 MIQP，无 PwL），而 EXP-4 来自 MATLAB intlinprog（PwL 近似）。两者的数值结果不可直接比较。

### 影响
EXP-2/3 的 regret 值比 MATLAB 版更精确（无 PwL 误差）。论文中如果引用 EXP-2 的"M0 max regret=23.6%"和 EXP-4 的 sufficiency 比例，读者可能误以为用的是同一求解器。

### 建议处理
1. 在论文中明确标注每个实验使用的求解器
2. 可选：用 MATLAB 重跑 EXP-2/3（参数扫描代码已有框架），统一口径
3. 或在论文中说明：EXP-1/2/3 是存在性证明（精确求解），EXP-4 是大规模统计（近似求解）

---

## 优先级排序

| 优先级 | Issue | 处理方向 | 阻塞论文？ |
|--------|-------|----------|-----------|
| **P0** | ISSUE-1 (M1≈M0) | 调查根因 + 调整论文叙事 | **是**（影响主张） |
| **P1** | ISSUE-5 (admissible比例) | 统计 + 改进图生成 | 可能改善 ISSUE-1 |
| **P1** | ISSUE-2 (PwL baseline) | 增加 nPwl 重跑 | 改善数值精度 |
| **P2** | ISSUE-7 (单商品流) | 实现多商品流 | 不阻塞，但改善真实性 |
| **P2** | ISSUE-3 (M1>M0) | 已解释，论文中说明 | 不阻塞 |
| **P3** | ISSUE-4 (J*定义) | 已修复，论文中说明 | 不阻塞 |
| **P3** | ISSUE-6 (饱和惩罚) | 检查触发频率 | 不阻塞 |
| **P3** | ISSUE-8 (口径不一致) | 论文标注或重跑 | 不阻塞 |

---

## 建议下一步行动

1. **先做 ISSUE-5 的统计**（10 分钟）：确认 admissible connector 比例是否导致 ISSUE-1
2. **如果确认**：改进图生成，加入非对齐 port，重跑 mini 验证 M1 分离
3. **如果 M1 分离出来**：重跑 EXP-4 medium
4. **如果仍然 M1≈M0**：调整论文叙事为两段式 regime，M1 中间层作为 discussion
5. **并行**：增加 nPwl 到 15，量化 baseline regret 改善
