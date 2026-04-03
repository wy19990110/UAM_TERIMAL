# 负 Regret 根因诊断报告

## 1. 最可能的根因：PwL 近似口径与 Evaluator 精确口径的系统性不一致

**核心问题：MIP 用 PwL 等式约束嵌入 Ψ_t，Evaluator 用精确非线性公式重算 Ψ_t，两者不等价。当 PwL 高估时，Full MIP 的"最优解"在 Evaluator 口径下不再是最优。**

### 详细机制

MIP 中 `psi(t,w) == PwL(λ)` 是**等式约束**（TwoStageMIP.m 第约 150 行 `psiLnk` 约束）。这意味着 MIP 看到的 Ψ_t 成本**恒等于** PwL 近似值——不是上界也不是下界，而是精确等于 PwL 插值。

Evaluator 计算的是精确的 `L_t = Σ_h λ_h · D_{t,h}(λ_h)`，其中 `D_{t,h}(λ) = α·(λ/(μ-λ))^β`。

**PwL 的偏差方向：**

`computePsiBreakpoints` 在 `TerminalResponse.m` 中用 `linspace(0, capMax*0.95, numPts)` 生成均匀断点，然后对 **凸函数** `L(λ) = λ·D(λ)` 取精确值做线性插值。

对于凸函数，**弦插值（线性连接两个精确点）总是在两个断点之间给出上界**——这是 Jensen 不等式的直接推论。换言之：

> **PwL(λ) ≥ L_exact(λ) 对所有 λ 成立**（上界近似）

这意味着 MIP 中 Ψ_t 的成本被系统性高估。

## 2. PwL 上界如何导致负 Regret

### 2.1 Full MIP（按接口分解、多元 PwL）vs A0 MIP（标量聚合、一元 PwL）

**Full/A1/A2 MIP** 使用按接口分解的 PwL：每个接口 h 单独一条 PwL，即 `psi_t = Σ_h PwL_h(λ_h)`。

**A0 MIP** 使用聚合总负荷的一元 PwL：`psi_t = PwL_agg(λ_total)`，其中 `λ_total = Σ_h λ_h`。

关键洞察：**分解后的多元 PwL 高估幅度通常大于聚合一元 PwL 的高估幅度。**

原因：
- 接口分解后，每个接口的 capMax 较小（`capacity * 0.9`），曲线更陡
- 聚合 D_agg 的参数（`aggDelayAlpha`, `aggDelayBeta`）与接口级参数可能不同
- 多个独立凸函数的 PwL 近似误差是累加的

因此：
- Full MIP 看到的 Ψ_t 成本（分解PwL）可能显著高于 A0 MIP 看到的 Ψ_t 成本（聚合PwL）
- Full MIP 在优化时会**过度回避高终端负荷**（因为 PwL 夸大了终端成本）
- Full MIP 的最优解 y* 可能选择了更多走廊来分散负荷，或者选择了更高走廊成本但更低（PwL 口径下的）终端成本的方案
- 但在 Evaluator 精确口径下，终端成本没那么高，y* 的"过度分散"反而增加了走廊成本，使总成本 J(y*; Full) 不是最小的

与此同时：
- A0 MIP 看到较低的 Ψ_t 高估，做出的决策 ŷ_A0 在走廊选择上更"激进"（更少走廊、更集中流量）
- 在 Evaluator 精确口径下，这种集中负荷的方案终端成本没有 PwL 预期的那么高
- 因此 J(ŷ_A0; Full_exact) < J(y*; Full_exact)，产生负 regret

### 2.2 为什么 footprint=none 时负 regret 最严重？

当 footprint=none 时：
- Full 和 A0 的**可行域差异仅来自接口可行性**（isCorridorFeasible），没有脚印阻塞（isCorridorBlocked 均为 false）
- A0 的可行域 ⊇ Full 的可行域（A0 恒返回 feasible=true）
- Full MIP 受到接口 PwL 高估的最大影响（没有脚印约束来掩盖这个效应）
- 高估效应完全暴露，负 regret 最大（-31% 到 -51%）

当 footprint=moderate 时：
- 30% 终端有脚印阻塞，Full MIP 的可行域额外受限
- 脚印约束是"硬"约束（对/错），不受 PwL 近似影响
- 因此负 regret 部分被脚印约束的真实效应抵消

### 2.3 为什么 A1 在 footprint=none 时 regret=0？

A1 使用**与 Full 相同的按接口分解 PwL**，且 A1 的 `isCorridorFeasible` 也查接口矩阵（与 Full 相同）。在 footprint=none 下，Full 和 A1 的唯一差异是：
- `isCorridorBlocked`：Full 查脚印，A1 恒 false。但 footprint=none 时 Full 也没有阻塞走廊
- `getExternalityCost`：Full 返回 noiseIndex + populationExposure，A1 返回 0
- PwL：Full 的 `getPsiBreakpoints` 在 `vals` 中加了 `xiVal * chiH * bp / refExternality`，但当 `xi=0` 时（RegretFramework 默认 xi=0），这一项为零

**当 xi=0 时，A1 和 Full 的 MIP 完全等价**（相同的 PwL、相同的可行域约束），所以产生相同的最优解，regret=0。

但注意：Evaluator 中有一个**遗留外部性成本**（TwoStageMIP.m 不包含，但 Evaluator.m 包含）：

```matlab
% 旧的外部性成本保留为独立项（向后兼容，xi=0 时为主要外部性来源）
externalityCost = 0;
if xi == 0
    for t = 1:instance.numTerminals()
        ...
        externalityCost = externalityCost + plugin.getExternalityCost(tid, sid);
    end
end
```

**这是第二个重大不一致！** 当 xi=0 时：
- MIP 目标中**完全没有外部性成本**
- Evaluator 中**加了 `getExternalityCost`**（对 Full plugin 返回 `noiseIndex + populationExposure`，对 A0/A1 返回 0）

这意味着：
- J(y*; Full_evaluator) = MIP目标 + Full外部性成本
- J(ŷ_A0; Full_evaluator) = MIP目标' + Full外部性成本'

但由于外部性成本只取决于样式选择（不取决于流量分配），且城市级实例每终端只有一种样式，所以对 Full evaluator 来说**所有方案的外部性成本相同**。因此这个不一致**不是负 regret 的直接原因**，但它确实导致 Evaluator 的 J 值与 MIP 的 J 值不可比。

## 3. 可行域差异分析

### A0 vs Full 的 MIP 可行域

| 维度 | A0 | Full |
|------|-----|------|
| C2 走廊可行性 | `isCorridorFeasible` 恒 true → 约束 `x(e) ≤ 1` (松弛) | 查接口矩阵，部分走廊被禁 |
| C2 脚印阻塞 | `isCorridorBlocked` 恒 false | 查脚印，部分走廊被禁 |
| C6b 接口有效域 | 无此约束（一元模式） | `loadExpr ≤ capMax` 每接口独立约束 |
| C7 PwL | 一元聚合 PwL | 多元分解 PwL |

**A0 的可行域严格大于 Full**（在 footprint=none 下，差异来自 C6b 和 PwL 分解）。

但负 regret 的根因不是可行域差异——而是 PwL 近似导致的**目标函数失真**。Full MIP 在更紧的可行域上优化了一个**高估的目标函数**，得到的"最优解"在真实目标下不是最优。

## 4. 诊断方向和修复建议

### 4.1 确认诊断（优先级最高）

**验证 PwL 高估假说：** 对一个典型负 regret 实例：
1. 取 y*（Full MIP 最优解），计算 MIP 目标中的 `Σ psi(t,w)` 值
2. 用 Evaluator 精确计算同一方案的 `Σ terminalCost`
3. 计算差值 `MIP_psi - Eval_terminalCost`
4. 对 ŷ_A0 做同样计算
5. 预期结果：Full MIP 的 PwL 高估幅度 > A0 MIP 的高估幅度

### 4.2 修复方案 A：Evaluator 也用 PwL（口径统一）

最简单的修复：让 Evaluator 使用与 MIP 相同的 PwL 近似来评估 Ψ_t，而不是精确公式。这保证 regret 定义在同一口径下，必然非负。

**缺点：** 论文讲的是"在真值模型下评估"，如果 Evaluator 也用 PwL 近似，失去了"真值"含义。

### 4.3 修复方案 B：MIP 用不等式约束代替等式（推荐）

将 MIP 中的 PwL 约束从等式改为**不等式**：

```
psi(t,w) ≥ PwL(λ)     （下界约束）
```

由于 PwL 是凸函数的弦插值（上界），改为 `psi ≥ PwL` 会使 MIP 能自由选择 `psi ≥ 真实值`，但在最小化目标下会取到 PwL 值。这与当前等式约束行为相同，**不能解决问题**。

真正的修复是：**用凸下界近似**而非弦插值。对凸函数，可以用**切线下界**（取断点处的切线），保证 PwL_lower(λ) ≤ L_exact(λ)，然后配合不等式约束 `psi ≥ PwL_lower(λ)`。

但这在 MIP 中建模更复杂。

### 4.4 修复方案 C：增加 PwL 精度（最小改动，推荐）

将 `numPwlPts` 从 8 增加到 20-30，并使用**非均匀断点**（在高曲率区域加密）。凸函数的 PwL 弦插值误差随断点密度增加而趋于零。如果 PwL 足够精确，高估幅度足够小，负 regret 会消失或可忽略。

**推荐实现：**
- 在接近 capMax 的高负荷区域加密断点（这里曲率最大）
- 使用 Chebyshev 节点或对数间隔代替 linspace 均匀间隔
- 目标：确保 PwL 近似误差 < 1% 的总成本

### 4.5 修复方案 D：统一评估口径（最严谨）

Regret 定义修正为：

> Δ_ℓ = J_MIP(ŷ_ℓ; Full_plugin) - J_MIP(y*; Full_plugin)

即：**用 Full plugin 的 MIP**（不是 Evaluator）来评估所有方案。既然 MIP 用同一套 PwL 近似，且 y* 是 Full MIP 的最优解，则 J_MIP(ŷ_ℓ) ≥ J_MIP(y*) 必然成立。

但这要求对 ŷ_ℓ 重新求解 Full MIP 的运营子问题（固定 x，求最优 f 和 psi），实现稍复杂。

### 4.6 推荐修复策略

**短期（快速修复）：** 方案 C，将 PwL 断点从 8 增加到 20+，使用非均匀间隔（对数或平方根间距），验证负 regret 是否消失。

**中期（严谨修复）：** 方案 D，在 Evaluator 中也用 PwL 近似（或等价地，用 Full MIP 重新评估），保证 regret 定义的数学正确性。

**论文叙事建议：** 在论文中明确说明 Evaluator 用精确公式，MIP 用 PwL 近似，两者的差异是 O(1/N²)（N=断点数），并报告实际近似误差。

## 5. 总结

| 问题 | 根因 |
|------|------|
| 负 regret | Full MIP 的多元分解 PwL **高估** Ψ_t 比 A0 的一元聚合 PwL 更严重 |
| PwL 偏差方向 | 凸函数弦插值 → **上界**（Jensen 不等式） |
| Full MIP y* 次优 | Full MIP 优化了高估的目标 → y* 过度回避终端负荷 → Evaluator 精确口径下次优 |
| A0 footprint=none 最严重 | 可行域差异最小，PwL 高估差异完全暴露 |
| A1 footprint=none regret=0 | xi=0 时 A1 和 Full 的 MIP 完全等价 |
| 修复 | 增加 PwL 精度 + 统一评估口径 |
