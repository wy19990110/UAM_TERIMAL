# EXP-7 实验报告：Integrated Upper Bound (JO)

## 1. 报告首页

- 报告编号：EXP-7-20260407
- 实验日期：2026-04-07
- 实验模块：EXP-7（Integrated upper bound / Joint Optimization）
- 执行人：Claude + 狗修金sama
- 审核人：待定
- 代码分支/提交号：main
- 求解器与版本：MATLAB intlinprog + quadprog (R2024b)
- 报告状态：初稿
- 对应研究问题：
  - [x] 向上比：分层接口 vs 联合优化（JO）的 gap 有多大？
  - [x] PR 能恢复多少 JO 的价值？

---

## 2. 实验目的与预期

### 2.1 本次实验目的
量化分层接口方法 vs 联合优化（JO）的 gap，回答审稿人问题："你们的分层方法丢了多少设计价值？"

### 2.2 JO 定义
JO = M* truth model 直接求解（solveMILP("JO")），代表一体化优化的理论上界。

### 2.3 成功判据
- PR gap to JO < B0 gap to JO（PR 比 incumbent 更接近 JO）
- PR gap closure > 20%

---

## 3. 实验设计

- 图族：JO_S (3T/2W, small), JO_M (5T/3W, medium)
- 扫描：5 seeds × 4 ρ × 3 αA × 3 φF
- 总实例：2 × 5 × 4 × 3 × 3 = **360**
- JO 独立求解 + truth evaluate，不经过 computeRegret 的 star 选择
- JO 求解失败（objective==Inf）时跳过该实例

---

## 4. 结果

### 4.1 按 Family

| Family | n | B0 gap% | B1 gap% | M1 gap% | M2 gap% | PR gap% | Closure% |
|--------|---|---------|---------|---------|---------|---------|----------|
| JO_S (3T/2W) | 180 | 838 | 1.6 | 0.7 | 63.3 | 63.3 | 36.4 |
| JO_M (5T/3W) | 180 | 18986 | 12721 | 11615 | 6808 | 6808 | 36.6 |
| **全部** | **360** | **9912** | **6361** | **5808** | **3436** | **3436** | **36.5** |

### 4.2 按 αA

| αA | B0 gap% | M2 gap% | PR gap% | Closure% |
|----|---------|---------|---------|----------|
| 0.00 | 12327 | 3805 | 3805 | 20.4% |
| 0.25 | 11479 | 3746 | 3746 | 46.5% |
| 0.50 | 5931 | 2756 | 2756 | 42.6% |

### 4.3 Runtime
| 指标 | JO | PR |
|------|----|----|
| Median solve time | 0.05s | 0.06s |
| Runtime ratio | ≈ 1.0x | — |

---

## 5. 分析

### 5.1 成功判据检验
- ✅ PR gap < B0 gap（3436% vs 9912%）
- ✅ Gap closure = 36.5% > 20%

### 5.2 关键发现

1. **小规模 JO_S**：B1/M1 gap 接近 0（1.6%/0.7%），说明 3T/2W 规模上分层接口几乎不损失设计价值。M2 gap=63% 说明 F 通道在小图上反而引入偏差。

2. **中规模 JO_M**：所有方法 gap 都很大（千到万%）。B0=18986%, M2=6808%, PR=6808%。PR 恢复了 36.6% 的 gap。

3. **gap 百分比过大的问题**：
   - 公式 `(jTruth - jJO) / |jJO|` 在 jJO 接近 0 时产生极端值
   - 需要在论文中改用 `max(jJO, ε)` 归一化或绝对 gap
   - 或使用 log scale 展示

4. **Runtime ratio ≈ 1.0**：当前规模太小（max 5T/3W），solver overhead 占主导，JO 和 PR 运行时间无差异。运行时间的差异需要依赖 EXP-8 的大规模数据。

5. **αA 的影响**：高 αA 时 B0 gap 下降（因为 port 错位大→B0 的 "选错 connector" 代价被限制），closure 在 αA=0.25 处最高（46.5%）。

---

## 6. 结论

- PR 恢复了 B0→JO 之间 **36.5%** 的 gap
- 小规模 JO_S 上分层接口几乎无损
- 中规模 JO_M 上所有方法都有显著 gap，但 PR/M2 仍比 B0 好约 3 倍
- 论文展示需要注意 gap 百分比的量纲问题

---

## 7. 数据位置
- 结果文件：`results/exp7/exp7_results.mat`
- 日志：`results/exp7/exp7_log.txt`
- 脚本：`+asf/+experiments/runEXP7.m`
