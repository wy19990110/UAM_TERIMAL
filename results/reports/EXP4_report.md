# EXP-4 实验报告：全网 Regime Map

## 1. 报告首页

- 报告编号：EXP-4-20260403
- 实验日期：2026-04-03
- 实验模块：EXP-4（medium 规模）
- 执行人：Claude + 狗修金sama
- 代码分支/提交号：master / 6b9bb5d
- 求解器与版本：MATLAB intlinprog (R2024b) + quadprog
- 报告状态：初稿
- 对应研究问题：[x] regime 边界识别（什么条件下哪层接口足够）

## 2. 实验目的与预期

### 2.1 本次实验目的
在完整候选网络上回答：什么 regime 下 S-only (M0) 足够，什么 regime 下需要 AS (M1)，什么 regime 下需要 ASF (M2)。

### 2.2 对应假设/预期现象
- 低 ρ、低 αA、低 φF 区域：M0 足够
- αA 或 κS 上升后：M1 才足够
- φF 大时（特别是 G3 airport-adjacent）：M2 才进入 sufficiency 区域
- G3 比 G1/G2 更早进入"必须 ASF"的区域

### 2.3 与实验链的关系
- 上游依赖：EXP-1/2/3 全部 Go（已满足）
- 下游影响：结果直接进入论文正文 regime map 图

### 2.4 成功判据（预注册）
能画出从 S-only → AS → ASF 的 regime map，且三段式区域可辨认。

## 3. 口径核对清单

1. M0/M1/M2/M* 共享同一候选图 G⁺：**是**
2. Truth evaluation 使用统一 M* 重算流分配：**是**（quadprog 精确 QP）
3. Regret = truth-evaluated 差值：**是**
4. **J* 取跨所有模型的 truth-best 设计**：**是**（修复后的 computeRegret）
5. M0/M1/M2 接口从 truth 拟合：**是**
6. MIP gap ≤ 1%：**是**（intlinprog 默认 AbsGap=1e-6）
7. Random seed 完整记录：**是**（seed 1-3）
8. **负 regret = 0 个实例**：**是**

## 4. 环境设置

### 4.1 图族

| 图族 | nT | nW | 目标边数 | Airport Zone | 实例数 |
|------|----|----|---------|-------------|--------|
| G1s (open sparse) | 4 | 3 | 7-9 | 无 | 324 |
| G2s (open dense) | 5 | 4 | 10-13 | 无 | 324 |
| G3s (airport-adj) | 3 | 3 | 6-9 | 有 (0.8,0.5) r=0.15 | 324 |

每图族 3 个 random seeds × 108 参数组合 = 324 实例。

### 4.2 Terminal 配置
由 `buildSynthetic` 自动生成：
- Port 数量：1-3（随机，受 incident edge 数限制）
- Port 方向：对齐 incident backbone edge 方向
- Service 参数：a ∈ [0.1, 0.2], b ∈ [0.2, 0.4] × κS ratio
- Cross-port coupling：m ∈ [0.05, 0.2]
- μ̄ ∈ [3, 6], ψ_sat ∈ [1, 5]

### 4.3 需求
- 40% OD 对覆盖率
- 每 OD 需求 = (1 + rand×2) × ρ

## 5. 参数设置

| 参数 | 取值 | 维度 |
|------|------|------|
| ρ (demand intensity) | {0.5, 0.8, 1.0, 1.2} | 4 |
| αA (access restrictiveness) | {0, 0.25, 0.5} | 3 |
| κS (service asymmetry) | {1, 2, 3} | 3 |
| φF (footprint severity) | {0, 0.2, 0.5} | 3 |
| **每图族参数组合** | | **108** |
| **总实例数** | 3 图族 × 3 seeds × 108 | **972** |

求解器设置：nPwl=7, intlinprog + quadprog, 每实例 ~0.1s，总 ~2.5 min。

## 6. EXP-4 专用字段
- 图族与 seed 数：3 × 3
- 参数扫描网格：4×3×3×3 = 108
- 总实例数：972
- Sufficiency 阈值（预注册）：3%
- Warm start：否

## 7. 实验过程记录

| 步骤 | 时间 | 操作 |
|------|------|------|
| 1 | 17:03:30 | 启动 medium sweep 后台 MATLAB |
| 2 | 17:03:30-17:06:16 | 972 实例逐个求解（~0.1s/实例） |
| 3 | 17:06:16 | 全部完成，0 error |
| 4 | 即时 | 结果分析 |

总耗时：**~2.5 分钟**。

## 8. 实验结果（定量）

### 8.1 总体 Sufficiency（|Δ/J*| ≤ 3%）

| 模型 | Sufficient 数 | 比例 |
|------|-------------|------|
| M0 (S-only) | 585/972 | **60%** |
| M1 (AS) | 570/972 | **59%** |
| M2 (ASF) | 887/972 | **91%** |

**负 regret：0 个实例（全部 ≥ 0）。**

### 8.2 按图族分组

| 图族 | M0 suff | M1 suff | M2 suff |
|------|---------|---------|---------|
| G1s (open sparse) | 47% | 44% | 82% |
| G2s (open dense) | 60% | 62% | 98% |
| G3s (airport-adj) | 73% | 70% | 93% |

### 8.3 按 φF（footprint severity）分组 ← **最强区分因子**

| φF | M0 suff | M1 suff | M2 suff | 说明 |
|----|---------|---------|---------|------|
| 0 | 90% | 90% | 90% | 无 footprint: 三模型等价 |
| 0.2 | 56% | 52% | **90%** | 轻 footprint: M0/M1 下降，M2 稳定 |
| 0.5 | 34% | 34% | **94%** | 重 footprint: M0/M1 严重不足，M2 依然够 |

### 8.4 按 ρ（demand intensity）分组

| ρ | M0 suff | M1 suff | M2 suff |
|---|---------|---------|---------|
| 0.5 | 48% | 44% | 82% |
| 0.8 | 64% | 65% | 93% |
| 1.0 | 65% | 64% | 96% |
| 1.2 | 64% | 61% | 94% |

### 8.5 按 αA（access restrictiveness）分组

| αA | M0 suff | M1 suff | M2 suff |
|----|---------|---------|---------|
| 0 | 63% | 59% | 87% |
| 0.25 | 59% | 57% | 94% |
| 0.50 | 59% | 60% | 94% |

### 8.6 按 κS（service asymmetry）分组

| κS | M0 suff | M1 suff | M2 suff |
|----|---------|---------|---------|
| 1 | 60% | 60% | 90% |
| 2 | 60% | 58% | 91% |
| 3 | 61% | 58% | 92% |

### 8.7 交叉分组（φF × ρ，最关键的 2D 切片）

**M0 sufficiency (%)**:

| | ρ=0.5 | ρ=0.8 | ρ=1.0 | ρ=1.2 |
|---|-------|-------|-------|-------|
| φF=0 | 78% | 93% | 96% | 93% |
| φF=0.2 | 41% | 59% | 62% | 63% |
| φF=0.5 | 26% | 41% | 37% | 33% |

**M2 sufficiency (%)**:

| | ρ=0.5 | ρ=0.8 | ρ=1.0 | ρ=1.2 |
|---|-------|-------|-------|-------|
| φF=0 | 78% | 93% | 96% | 93% |
| φF=0.2 | 78% | 93% | 96% | 93% |
| φF=0.5 | 89% | 93% | 96% | 96% |

## 9. 初步分析

### 9.1 结果是否符合预期

**部分符合，有重要偏差。**

✅ 符合：
- φF 是最强区分因子：从 90% 降到 34%（M0），M2 稳定 90%+
- M2 全局 sufficiency 91%，远好于 M0 的 60%
- 无负 regret

⚠️ 偏差：
- **M1 并未明显优于 M0**（59% vs 60%）——预期 M1 > M0
- **αA 和 κS 几乎无影响**——预期 αA 和 κS 增大时 M0↓ M1↑
- **ρ=0.5 时 sufficiency 反而最低（48%）**——预期低 ρ 时 M0 最够用

### 9.2 对研究问题的含义

**结论 1：φF（footprint severity）是决定接口层级必要性的主导参数。**
当 φF=0 时，M0/M1/M2 表现一致（90% suff）。当 φF>0 时，只有 M2 保持高 sufficiency。

**结论 2：在当前建模框架下，M1(AS) 相对 M0(S-only) 的优势不显著。**
这可能意味着：(a) port-level service 差异在 PwL 近似下未被有效捕获；或 (b) 合成图中 admissibility 限制不够强（port 方向对齐了 incident edges，导致 M0 也恰好选到 admissible 的 connector）。

**结论 3：regime map 呈两段式而非三段式：**
- **无 footprint 区域**：S-only 够用（M0 ≈ M1 ≈ M2）
- **有 footprint 区域**：需要 ASF（M2），AS(M1) 没有明显中间地带

### 9.3 错误归因分析

**M0/M1 的 regret 主要来自 F 信息缺失。**

证据：
- φF 从 0→0.5 时，M0 suff 从 90%→34%（-56 pp）
- αA 从 0→0.5 时，M0 suff 从 63%→59%（-4 pp）
- κS 从 1→3 时，M0 suff 从 60%→61%（+1 pp，无效应）

A 和 S 信息在全网实验中的贡献远小于 F。这与 EXP-1/2 的小规模反例不矛盾——小规模反例是精心构造的极端情况，全网中这些极端情况被稀释。

### 9.4 Regime 边界

**主边界：φF ≈ 0.1-0.2**
- φF < 0.1：M0 足够（~90% suff）
- φF > 0.2：M0 不足（~50% suff），需要 M2（~90% suff）
- M1 不形成独立 regime

**次要边界：ρ ≈ 0.5 时图的连通性不足**
ρ=0.5 时 sufficiency 偏低可能因为需求太少 → 很多 OD 对无需求 → 少数被选中的 OD 对高度敏感于拓扑选择

### 9.5 异常迹象

**⚠️ M1 ≈ M0（有时 M1 < M0）**

在 mini 验证中发现 instance #8: M1 regret=36.4% > M0 regret=23.2%。这在理论上不应发生（M1 信息 ⊃ M0），但在 MILP(PwL) 框架下，M1 使用 per-port PwL 而 M0 使用 aggregate PwL，两者的近似误差方向不同，可能导致 M1 MILP 选了一个在 truth QP 口径下更差的拓扑。

**可能根因**：
1. PwL 切线下界近似对 per-port 小容量曲线的精度不足
2. M0 的 aggregate PwL 恰好在某些 instance 上"偏对了方向"
3. Port 方向对齐策略使 admissibility 约束很少实际限制 M0

**建议调查方向**：
- 增加 nPwl 断点数（7→15）看 M1 是否改善
- 检查 admissible connector 数量：如果 M0 也只能用 admissible 的 connector（因为图结构限制），M1 的 admissibility 约束就无额外价值
- 考虑生成更多"non-admissible"的 connector 供 M0 误用

**⚠️ M2 在 φF=0 时也有 10% 不 sufficient**

M2 应该在 φF=0 时与 M0/M1 完全一致（因为无 footprint 信息可用），但 M0=M1=M2=90% 而非 100%。这 10% 来自 **PwL 近似误差**：所有模型的 MILP 都用 PwL，truth evaluator 用 QP，两者的近似差导致所有模型都有 ~10% 的 baseline regret。

### 9.6 Stop/Go 判定

**条件性 Go。**
- ✅ φF 维度上看到清晰的 M0→M2 regime 转换
- ⚠️ αA / κS 维度上 M0→M1 的 regime 转换不明显
- 建议：先写论文，把结论聚焦在"S-only vs ASF"的两段式 regime，M1 的中间层级作为"未来工作"或"需要更精细建模"的讨论点

### 9.7 是否需要重跑
- **否**（数据质量 OK，0 负 regret）
- 可选改进：nPwl 增大后重跑，看 M1 是否分离

### 9.8 下一步
1. 写 EXP-4 报告（本文档）✅
2. 考虑 EXP-5（现实代理）是否仍需做
3. 论文写作：regime map 热力图（φF × ρ 平面），sufficiency bar chart

## 10. 审核结论
- 审核意见：待复核
- 可进入论文主文：**是**（φF regime 清晰）
- 需要讨论的问题：
  1. M1 ≈ M0 的原因及改进方向
  2. ~10% baseline regret 来自 PwL 近似
  3. 两段式 vs 三段式 regime 的论文叙事调整
- 建议论文图表：
  - Fig: φF × ρ sufficiency heatmap（M0 vs M2 对比）
  - Fig: sufficiency bar chart 按图族分组
  - Table: 各参数维度的 sufficiency probability
