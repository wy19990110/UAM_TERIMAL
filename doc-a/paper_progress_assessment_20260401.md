# 论文工作进展评估报告（2026-04-01）

## 一、整体进度总览

| 模块 | 状态 | 说明 |
|------|------|------|
| **问题定义 & 理论框架** (1.md→8.md) | ✅ 完成 | 经 8 轮迭代审查，已冻结所有设计决策 |
| **核心数据结构** (Phase 1) | ✅ 完成 | TerminalResponse, NetworkInstance, Plugins 等 |
| **MIP 求解器** (Phase 2) | ✅ 完成 | TwoStageMIP + Ψ_t 已集成到目标函数 |
| **终端模型** (Phase 3) | ✅ 完成 | 排队论延迟 + 脚印 + 外部性 |
| **主模型升级** (Steps 1-7) | ✅ 完成 | Ψ_t 进目标函数、Evaluator 修正、SOS2 线性化 |
| **E0 实验**（接口可行性存在性证明） | ✅ 完成 | A0 不足以保留接口约束信息 |
| **E1 实验**（空域脚印存在性证明） | ✅ 完成 | A1 不足以保留空域外部性信息 |
| **E0b 实验**（渐变 regret 证明） | ✅ 完成 | 接口延迟差异导致连续 regret |
| **城市级参数扫描** (WP6.3) | ✅ 刚完成 | 3×3×5=45 轮，regime map 已生成 |
| **多商品流守恒约束** (WP6.2) | ❌ 未开始 | 当前仅单商品流 |
| **可视化** (WP6.4) | ❌ 未开始 | regret 柱状图、regime map 热力图、网络拓扑图 |
| **A2+ 层级实验** (WP7) | ❌ 未开始 | 资质/关闭规则，代码仅骨架 |
| **论文 LaTeX 撰写** | ❌ 未开始 | 无 .tex 文件 |

---

## 二、实验结果汇总与解读

### 2.1 小规模存在性证明（E0, E1, E0b）

| 实验 | 核心发现 | 论文角色 |
|------|----------|----------|
| **E0** | A0 忽略接口可行性矩阵 → 选择了不可行的终端样式 → 二值 regret | Proposition 的数值验证 |
| **E1** | A1 忽略空域脚印约束 → 选择了脚印冲突的走廊 → 二值 regret | 证明 A1 → A2 升级必要性 |
| **E0b** | 同一终端两接口延迟不同 → A0 的标量化丢失信息 → 连续 regret | 证明 regret 非仅二值开关 |

**评价**: 三个实验覆盖了 A0→A1→A2 逐级必要性证明，逻辑链完整。

### 2.2 城市级参数扫描结果

**Regime Map（最小充分层级，相对 regret < 1%）:**

```
              none        moderate    severe
low           A0          A0          A2
medium        A0          A2          A2
high          A0          A0          A2
```

**相对 Regret A0 (%):**
```
              none        moderate    severe
low           -31.5       -37.5       620.5
medium        -38.9       67.7        453.4
high          -50.6       -3.4        26.2
```

**相对 Regret A1 (%):**
```
              none        moderate    severe
low           0.0         96.1        671.7
medium        0.0         72.2        417.1
high          0.0         23.0        19.9
```

### 2.3 城市级结果中的问题与疑点

#### 🔴 问题 1: A0 大面积负 regret

A0 在 none/moderate 脚印下全部出现**负 regret**（-3.4% 到 -50.6%），意味着 A0 选出的网络设计在真值评估下比真值最优解**更好**。

**这在理论上不可能**（J* 已是真值模型下全局最优）。可能原因：
- Evaluator 评估 A0 方案时使用了不同的评估路径/参数
- MIP 求解器在真值模型下没有找到真正的全局最优（求解器间隙/时间限制）
- A0 方案的真值评估计算有 bug（可能 Ψ_t 没被正确加入）

**这是一个必须修复的关键问题。负 regret 会动摇整篇论文的可信度。**

#### 🟡 问题 2: A1 在 footprint=none 时 regret 恒为 0

A1 在无脚印约束时完美匹配真值最优，这从理论上说得通（A1 比 A0 多了接口信息，无脚印时 A1 ≈ Full）。但需要在论文中解释：为什么 A1 在 none 下就够了，但 moderate 下突然跳到 96%。

#### 🟡 问题 3: A1 在 severe 下 regret 非常不稳定

- low-severe: A1 regret 671.7%
- medium-severe: A1 regret 417.1%
- high-severe: A1 regret 19.9%

high demand + severe footprint 下 A1 regret 仅 19.9%，反而比 low demand 小得多。需要检查是否因 high demand 下几乎所有走廊都被激活，掩盖了脚印约束差异。

#### 🟡 问题 4: Regime map 中 high-moderate 判为 A0

high demand + moderate footprint 下 A0 relative regret = -3.4%，判定 A0 充分。但负 regret 本身就有问题（见问题 1），修复负 regret bug 后这个判定可能翻转。

---

## 三、代码完备性评估

### 3.1 已实现且经测试

| 组件 | 文件 | 测试状态 |
|------|------|----------|
| 抽象层级枚举 | AbstractionLevel.m | ✅ |
| 终端响应结构 | TerminalResponse.m | ✅ |
| A0/A1/A2/Full 插件 | +abstraction/*.m | ✅ |
| 排队延迟模型 | DelayModel.m | ✅ |
| 脚印计算 | FootprintCalc.m | ✅ |
| TwoStageMIP | TwoStageMIP.m | ✅（E0-E1通过） |
| Evaluator | Evaluator.m | ⚠️（可能有负regret bug） |
| RegretFramework | RegretFramework.m | ✅ |
| 城市级实例生成 | InstanceLibrary.m | ✅ |

### 3.2 已设计但未实现

| 组件 | 计划位置 | 影响 |
|------|----------|------|
| 多商品流约束 | TwoStageMIP 扩展 | 当前单 OD 对无法验证流守恒 |
| A2+ 资质/关闭规则 | A2PlusPlugin.m | 仅骨架，WP7 依赖 |
| z（终端样式）内生化 | TwoStageMIP 扩展 | 4.md 计划为补充实验 |
| 灵敏度分析（ξ 扫描） | 新实验 | 4.md 计划 ξ ∈ {0, 0.05, 0.1, 0.2} |

### 3.3 已设计但无代码

| 组件 | 说明 |
|------|------|
| LaTeX 论文 | 完全未开始 |
| 所有可视化 | 无图表生成代码 |

---

## 四、论文可写性评估

### 能支撑的论文结构

基于现有实验结果，可以撰写以下论文结构：

1. **Introduction** — UAM 网络设计中终端建模抽象的问题 ✅ 有理论框架
2. **Problem Formulation** — 抽象层级定义 + regret 度量 ✅ 已冻结
3. **Terminal Model** — 排队论 + 脚印 + 外部性 ✅ 已实现
4. **MIP Formulation** — 两阶段网络设计 + Ψ_t ✅ 已实现
5. **Existence Proofs (E0, E1, E0b)** — 小规模反例 ✅ 有数据
6. **City-Scale Experiments** — Regime map ⚠️ 有数据但负 regret 问题
7. **Conclusion** — 最小充分层级指南 ⚠️ 依赖修复后的 regime map

### 缺失的关键论文元素

| 元素 | 重要性 | 当前状态 |
|------|--------|----------|
| **负 regret bug 修复** | 🔴 致命 | 未开始 |
| **可视化图表** | 🔴 必需 | 未开始（至少需要 regime map 热力图、regret 柱状图） |
| **多商品流实验** | 🟡 重要 | 未实现（单 OD 对的 scalability 受限） |
| **ξ 灵敏度分析** | 🟡 重要 | 未开始（4.md 已规划） |
| **文献综述** | 🟡 重要 | 1.md 有理论框架但无 .bib |
| **LaTeX 撰写** | 🔴 必需 | 未开始 |

---

## 五、风险评估

### 高风险

1. **负 regret 问题（Bug or Design?）**
   - 如果是 Evaluator bug → 修复后数据需全部重跑
   - 如果是 MIP 求解精度问题 → 需收紧 gap tolerance
   - 如果是 A0 "恰好选对"（理论可能） → 需要重新定义 regret 或增加约束
   - **影响**: 这决定了整个 regime map 的可信度

2. **A1 regret 在 footprint=none 下恒为零**
   - 论文需要解释为什么 A1 在此条件下等价于 Full
   - 如果原因是"无脚印时所有层级等价"，那 A1 的存在价值仅在有脚印时
   - 需要验证 A1 和 Full 在 none 条件下是否确实给出相同决策

### 中风险

3. **单商品流 vs 多商品流**
   - 当前所有实验都是单 OD 对的简化版本
   - Reviewer 可能质疑 scalability
   - 如果时间不够，可以在 limitations 中说明

4. **A2+ 缺失**
   - 1.md 定义了 A2+（资质/关闭规则），但无实验
   - 可以在论文中将 A2+ 定位为 "future work"

---

## 六、建议优先级排序

### 立即行动（阻塞论文撰写）

1. **🔴 诊断并修复负 regret 问题**
   - 检查 Evaluator.m 的 Ψ_t 计算路径
   - 对比 A0 方案 vs 真值最优方案的逐项成本分解
   - 验证 MIP solver gap tolerance

2. **🔴 可视化（WP6.4）**
   - Regime map 热力图（3×3 grid, 颜色 = 最小充分层级）
   - Regret 柱状图（按 demand × footprint 分组）
   - 至少 1 个网络拓扑示意图

### 短期（论文核心内容）

3. **🟡 ξ 灵敏度扫描**
   - ξ ∈ {0, 0.05, 0.1, 0.2}，观察 regime map 变化
   - 验证外部性权重对层级选择的影响

4. **🟡 开始 LaTeX 撰写**
   - 先写 Problem Formulation + Model 章节（这部分已完全冻结）
   - E0/E1/E0b 实验章节可以先写

### 中期（增强论文说服力）

5. **🟢 多商品流扩展** — 如果时间允许
6. **🟢 z 内生化补充实验** — 如果时间允许

---

## 七、工作量估算（含校正系数）

| 任务 | 原始估算 | 校正后 | 说明 |
|------|----------|--------|------|
| 负 regret 诊断修复 | 2-4h debug | 2-4h | 纯调试，不折减 |
| 重跑实验（如需） | ~15min 机时 | 15min | 机时不折减 |
| 可视化代码 | 4h 编码 | **24min** | ÷10 |
| ξ 灵敏度扫描 | 1h 编码 + 1h 机时 | **6min + 1h** | 编码÷10 |
| LaTeX 论文正文 | 40h 写作 | **8h** | ÷5 |
| 文献综述 | 8h 写作 | **1.6h** | ÷5 |

**估算总工作量: ~12-14h**（含修 bug 和机时等待）
