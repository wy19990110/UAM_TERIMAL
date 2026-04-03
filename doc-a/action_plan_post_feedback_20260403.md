# 实验反馈行动计划（2026-04-03）

## 反馈核心诊断

现有 EXP-4 的问题不是"结果不好看"，而是**识别和数值都不够干净**：
1. PwL 近似造成 ~10% baseline regret，不是科学信号
2. 图生成器 port 对齐 incident edge → admissibility 对 M0 无约束 → A 信息无区分力
3. κS 效应被 PwL 线性化稀释
4. 单商品流压低了所有 regret 差异
5. M1≈M0 不是"AS 不重要"的科学结论，而是实验设计的 artifact

## 需要做的改动

### 改动 1：指标体系改为 pairwise uplift

从 Δ_i = J^truth(x_i) - J* 改为：
```
U01 = J^truth(M0) - J^truth(M1)    (M0→M1 升级价值)
U12 = J^truth(M1) - J^truth(M2)    (M1→M2 升级价值)
```
推荐规则：U01<3% 且 U02<3% → M0; U01≥3% 且 U12<3% → M1; U12≥3% → M2

### 改动 2：回到 Python/Gurobi MIQP 精确求解

Gurobi restricted license 限制 ~200 变量的 MIQP。解决方案：
- **方案 A**：申请 Gurobi 学术 license（WFU license，无限制）
- **方案 B**：用更小的图（3-5 terminals）+ 精确 MIQP
- **方案 C**：用 scipy.optimize.minimize（SLSQP）做 fixed-topology NLP 代替 quadprog

对于 EXP-4A calibration subset（40-60 实例），用小图精确解。
对于 EXP-4D 混合 regime（384-576 实例），可接受近似但需高精度 PwL（nPwl≥15）。

### 改动 3：图生成器重构

- Port 不再对齐 incident edge → 加入 ±20°~40° 随机偏移
- 每 port 增加 1-2 条 non-incident backbone edge 的 connector（M0 的"错误选项"）
- 计算实际激发指标 E_A = 1 - Jaccard(C_M0, C_M1)

### 改动 4：多商品流

EXP-4D 和 EXP-5 必须用 multi-commodity flow。

### 改动 5：M2 footprint 接口升级

从 F=(π̃, B̃) 升级到 F=(π̃, B̃, ρ̃)，加入 edge-level load-sensitivity。

## EXP-4 重构为四段

| 子实验 | 目的 | 规模 | 求解器 | 过关标准 |
|--------|------|------|--------|----------|
| **4A** | 数值校准 | 40-60 实例 | exact MIQP | φF=0 时 baseline regret 中位<1%, P95<3% |
| **4B** | A/S 隔离 | ~200 实例 | exact MIQP | 高 E_A/E_S 区域 U01 稳定正 |
| **4C** | F 隔离 | ~150 实例 | MIQP | U12 在 φF>0 区域显著 |
| **4D** | 混合 regime | 384-576 实例 | MIQP/高精度PwL | model recommendation map 可读 |

## 补做的实验

| 实验 | 优先级 | 说明 |
|------|--------|------|
| **EXP-0** (factor screening) | P0 | 前置条件，不通过不做后续 |
| **EXP-5** (现实代理) | P0 | 必进主文 |
| EXP-6 (对抗证伪) | P2 | 附录 |

## 执行顺序

1. **解决 Gurobi license 问题**（申请学术版或确认小图方案）
2. EXP-0 factor screening
3. EXP-4A 数值校准
4. 图生成器重构 + 多商品流
5. EXP-4B A/S 隔离
6. EXP-4C F 隔离
7. EXP-4D 混合 regime
8. EXP-5 现实代理
9. EXP-1/2/3 在 Python/Gurobi 统一口径重跑 clean version

## 对现有代码资产的处置

| 资产 | 处置 |
|------|------|
| Python src/uam/ (core, truth, interface) | **保留**，是新实验的基础 |
| Python solver/miqp_builder.py | **改造**：加多商品流、改 uplift 指标 |
| Python solver/evaluator.py | **保留**：truth QP 评估器 |
| Python graph_gen/synthetic.py | **重构**：port 偏移 + non-incident connector |
| Python experiments/exp1-3 | **统一口径重跑** |
| MATLAB +asf/ | **降级为 debug 工具**，不作为主证据 |
| 实验报告 EXP-1~4 | **保留为草稿**，最终版需重写 |
