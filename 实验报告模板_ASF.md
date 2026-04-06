# 终端区决策保持抽象（ASF）实验报告模板

> 用途：统一收取 EXP-0 ~ EXP-6 各模块的实验报告。
> 原则：每次实验必须单独提交 1 份报告；不得用"同上""同批次"替代关键设置。

---

## 1. 报告首页

- 报告编号：
- 实验日期：
- 实验模块：EXP-0 / EXP-1 / EXP-2 / EXP-3 / EXP-4 / EXP-5 / EXP-6
- 执行人：
- 审核人：
- 代码分支 / 提交号：
- 求解器与版本（如 Gurobi 11.0）：
- Python 环境版本：
- 报告状态：初稿 / 已复核 / 需重跑
- 对应研究问题：
  - [ ] A 的必要性（admissibility 信息是否不可省）
  - [ ] S 的必要性（port-level service 是否不可省）
  - [ ] F 的必要性（footprint 信息是否不可省）
  - [ ] regime 边界识别（什么条件下哪层接口足够）
  - [ ] 现实场景验证
  - [ ] ASF 充分性检验

---

## 2. 实验目的与预期

### 2.1 本次实验目的
[填写。2–4 句话，写清楚要回答什么问题。]

### 2.2 对应假设 / 预期现象
[填写。明确写出"如果实验成功，预期看到什么"。]

### 2.3 与实验链的关系
- 上游依赖：本实验是否依赖某个前置实验的 Go 判定？
- 下游影响：本实验的 Go/Stop 判定影响哪些后续实验？

### 2.4 成功判据（预注册）
[填写。必须在跑实验前写好，不得事后补填。]

---

## 3. 口径核对清单（必填）

请对每项填写：是 / 否 + 本次实现说明。

1. M0 / M1 / M2 / M* 四个模型共享同一候选图 G⁺ = (V∪P, E∪E^conn)。
2. truth evaluation 使用统一 M* 模型，固定设计后**重新求最优流分配**，再计算 J^truth。
3. regret 定义为 Δᵢ = J^truth(xᵢ,yᵢ) - J^truth(x*,y*)，而非模型内部目标值之差。
4. M1 的 port-level service 参数 (ã,b̃) 从 truth model 在 nominal load 下拟合得到，而非手工指定。
5. M2 的 nominal footprint (π̃,B̃) 从 truth model 在 nominal context 下提取，而非手工指定。
6. M0 的 aggregate service 参数 (ā,b̄) 从 truth model 在"均匀分流"假设下拟合得到。
7. 所有 terminal truth model 参数（a,b,m,ψ,π,ρ,B 等）在实验前固定，未在求解过程中被修改。
8. MIP gap 满足预设标准：小图（EXP-1/2/3）≤ 0.1%，中图（EXP-4）≤ 1%。
9. random seed 完整记录，结果可复现。
10. feasibility violation 检查已执行：truth 下不可用 connector 或 blocked edge 未被使用。

---

## 4. 环境设置

### 4.1 候选图

- 图族类型：G1(open-city sparse) / G2(open-city dense) / G3(airport-adjacent) / 手工构造
- terminal 数量：
- waypoint 数量：
- backbone 候选边数 |E|：
- connector 数 |E^conn|：
- port 总数 |P| = Σ|H_t|：
- random seed：
- 附图/附件文件名：

### 4.2 Terminal 配置

对每个 terminal 填写（或附表）：

| Terminal | H_t | β_{t,h} | Procedure | Pads | Gates | Organization | Context | 备注 |
|----------|-----|---------|-----------|------|-------|-------------|---------|------|
| T1 | | | | | | | | |
| T2 | | | | | | | | |
| ... | | | | | | | | |

### 4.3 需求场景

- OD 数量：
- 总需求 Q_tot：
- demand intensity ρ：
- OD 生成规则（如随机/固定矩阵）：
- context states（如 relaxed / constrained）：

---

## 5. 参数设置（总表）

请填写所有本次使用参数。未启用的参数也要写"不启用"。

### Access 参数
- port 数 H_t：
- sector width β：
- access restrictiveness α_A：
- context-dependent禁用规则 Z_t(ω)：

### Service 参数
- port-level 线性项 a_{t,h}：
- port-level 二次项 b_{t,h}：
- cross-port coupling m_{t,hh'}：
- saturation threshold μ̄_t：
- saturation penalty ψ_t：
- asymmetry ratio κ_S：

### Footprint 参数
- neighborhood radius（hop 数）：
- base penalty π̄_{t,e}：
- load sensitivity ρ_{t,e,h}：
- blocked-edge fraction φ_F：
- hard-block penalty M：

### Demand 参数
- overall intensity ρ：
- OD 覆盖率：

### 求解器参数
- time limit：
- MIP gap target：
- threads：
- warm start（是/否，来源）：

---

## 6. 按实验类型补充填写

### EXP-0：Factor Screening
- base terminal 数量：
- perturbation families：P/G / R/O / X
- 每 terminal perturbation 次数：
- 采样方式（LHS / random / grid）：
- 统计方法（ANOVA / one-factor-at-a-time / 其他）：
- 输出变量：d_A / d_S / d_F 的定义与计算方式：

### EXP-1：A 的必要性（E0）
- 手工图结构描述：
- terminal design 对 (u^A, u^B) 的差异说明：
- aggregate service 是否精确相同（是/否）：
- 穷举的 topology 数量：

### EXP-2：S 的必要性（E0b）
- 手工图结构描述：
- port service asymmetry 设置（左/右 port 的 a,b 值）：
- 扫描维度与取值：
  - ρ：
  - Δc：
  - κ_S：
- 穷举/求解方式：

### EXP-3：F 的必要性（E1）
- 图结构描述：
- 两个 design 共享 A/S 的验证（是/否）：
- footprint 差异设置：
- 扫描维度与取值：
  - φ_F：
  - π_F：
  - ρ：

### EXP-4：Regime Map（E2）
- 图族与 seed 数：
- 参数扫描网格：
  - ρ × α_A × κ_S × φ_F = __ × __ × __ × __ = __ 个组合
- 总实例数（图族×seeds×组合）：
- sufficiency 阈值（预注册）：3% / 5%
- 是否使用 warm start：

### EXP-5：现实代理案例（E3）
- 代理场景描述：
- airport protection zone 设置：
- terminal 类型分布（procedure-like / path-based）：
- OD 矩阵来源：
- context states：
- 情景总数：

### EXP-4B-S：S 通道隔离（新增）
- 扫描维度与取值：
  - ρ：
  - coupling_m：
  - ψ：
  - OD concentration：
- E_S 计算公式说明：
- 是否固定 A=0, F=0：

### EXP-4C Solver Audit（增补）
- 审计的 φF 取值：
- MIP gap 精度级别：
- 是否观察到负 U12 在精度提高后消失：
- near-exact refinement 方式：

### EXP-4D Held-out Recommendation（重构）
- 数据来源（哪些实验的结果）：
- train/test 分割比例：
- 阈值规则参数（E_A, E_S, E_F）：
- recommendation accuracy：
- 基线对比（always M1 / always M2）：

### EXP-6：Incumbent Benchmark（新增）
- 基线定义：
  - B0（具体说明）：
  - B1（具体说明）：
- 候选图共享确认（是/否）：
- truth re-evaluation 协议一致确认（是/否）：

### EXP-7：Integrated Upper Bound（新增）
- JO 实例规模（small / medium / large）：
- MIP gap 与 time limit：
- JO 是否收敛：
- gap closure 主指标：

### EXP-8：Scaling / Quality-Time Frontier（新增）
- 规模梯度（nT 列表）：
- 是否所有模型都在同一 time limit 下：
- JO 在哪个规模开始 timeout：

---

## 7. 实验过程记录

按实际顺序写，不得只写"运行成功"。

| 步骤 | 时间/耗时 | 实际操作 | 关键文件 / 日志 | 异常与处理 |
|------|----------|---------|----------------|-----------|
| 1. 生成/读取候选图 | | | | |
| 2. 生成 terminal configs | | | | |
| 3. 提取 M0/M1/M2 接口 | | | | |
| 4. 构建并求解 M* MIP | | | | |
| 5. 构建并求解 M0/M1/M2 MIP | | | | |
| 6. Truth evaluation（所有方案） | | | | |
| 7. 计算 regret 与指标 | | | | |
| 8. QA 与复核 | | | | |
| 9. 若重跑，说明原因 | | | | |

---

## 8. 实验结果（定量）

### 8.1 核心指标摘要

| 模型 | J^truth | Δᵢ | Δᵢ/J*(%) | RRᵢ | TD^backbone | TD^conn | Feasibility OK | Time(s) | Gap(%) |
|------|---------|-----|----------|------|-------------|---------|---------------|---------|--------|
| M* | | 0 (定义) | 0 | — | 0 | 0 | | | |
| M2 | | | | | | | | | |
| M1 | | | | | | | | | |
| M0 | | | | | | | | | |

### 8.2 成本分解

| 模型 | Construction | Travel | Terminal Service | Footprint | Unmet Penalty | Total |
|------|-------------|--------|-----------------|-----------|---------------|-------|
| M* | | | | | | |
| M2 | | | | | | |
| M1 | | | | | | |
| M0 | | | | | | |

### 8.3 需求满足

| 模型 | Served Demand | Unmet Demand | Unmet Rate(%) |
|------|--------------|-------------|---------------|
| M* | | | |
| M2 | | | |
| M1 | | | |
| M0 | | | |

### 8.4 Sufficiency 判定

| 模型 | |Δᵢ/J*| ≤ 3%? | |Δᵢ/J*| ≤ 5%? | Feasibility Violation = 0? | 判定 |
|------|--------------|--------------|---------------------------|------|
| M2 | | | | |
| M1 | | | | |
| M0 | | | | |

### 8.5 结构结果与图件

- 网络拓扑叠图（M0/M1/M2/M* 对比）：
- 成本分解柱状图：
- Regret 热图（若为参数扫描）：
- Sufficiency 热图（若为参数扫描）：
- Recovery rate 箱线图（若为参数扫描）：
- 原始数据文件路径：

---

## 9. 初步分析

### 9.1 结果是否符合预期
[填写。对照 2.2 的预期现象逐条核对。]

### 9.2 对研究问题的含义
[填写。这个实验结果对论文主张意味着什么？]

### 9.3 错误归因分析
[填写。M0/M1 的 regret 主要来自 A、S 还是 F 的信息缺失？通过什么证据判断？]

### 9.4 是否发现 regime 边界或阈值效应
[填写。是否存在某个参数值使 sufficiency 判定翻转？]

### 9.5 是否存在异常迹象
[填写。特别注意：
- 负 regret（必须为 0，否则有 bug）
- M2 regret > M1 regret（违反单调性）
- Feasibility violation > 0
- 求解器未收敛]

### 9.6 Stop / Go 判定
- 本实验是否满足 Go 条件？是 / 否
- Go 条件具体内容：
- 若 Stop，原因分析与建议下一步：

### 9.7 是否需要重跑
- 否 / 是
- 若是，请说明原因：

### 9.8 下一步动作
[填写。]

---

## 10. 审核结论

- 审核意见：通过 / 退回重做 / 作为扩展结果保留但不纳入主对比
- 退回原因（如有）：
- 是否可进入论文主文：是 / 否 / 附录
- 口径核对清单是否全部通过：是 / 否
- 审核备注：
- 签字 / 日期：
