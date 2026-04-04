# EXP-4A 实验报告：Calibration Gate（校准门控）

## 1. 报告首页

- 报告编号：EXP-4A-20260404
- 实验日期：2026-04-04
- 实验模块：EXP-4（子实验 4A：校准门控）
- 执行人：Claude + 狗修金sama
- 审核人：待定
- 代码分支/提交号：main / d1972d7
- 求解器与版本：MATLAB intlinprog + quadprog (R2024b)
- Python 环境版本：N/A（纯 MATLAB 实验）
- 报告状态：初稿
- 对应研究问题：
  - [x] A 的必要性（admissibility 信息是否不可省）
  - [x] S 的必要性（port-level service 是否不可省）
  - [x] F 的必要性（footprint 信息是否不可省）
  - [x] regime 边界识别（什么条件下哪层接口足够）

---

## 2. 实验目的与预期

### 2.1 本次实验目的
在正式 EXP-4 regime map 扫描之前，执行校准门控（calibration gate），验证：在 φ_F=0（无 footprint 约束）条件下，M1 和 M2 的 baseline regret 是否足够小（接近零），以确认 PwL 近似精度不会污染后续实验的信号。

### 2.2 对应假设/预期现象
- φ_F=0 子集中，M1 和 M2 应与 M* 几乎一致（因为 F 通道无信号），regret 接近零
- M0 在 φ_F=0 下仍可能有显著 regret（因为 A 通道信号独立于 F）
- 如果 M1/M2 baseline regret 过大，说明 PwL 近似引入了系统性偏差，需增加 nPwl 或修正

### 2.3 与实验链的关系
- 上游依赖：EXP-0 (Go)，EXP-1/2/3 (Go)，port offset + non-incident connector 修复
- 下游影响：Go → 进入 EXP-4 full regime map 扫描

### 2.4 成功判据（预注册）
- φ_F=0 子集中 M1 baseline regret：median < 1%, P95 < 3%
- φ_F=0 子集中 M2 baseline regret：median < 1%, P95 < 3%

---

## 3. 口径核对清单

1. M0/M1/M2/M* 共享同一候选图 G⁺：**是**（每个 instance 的四个模型共享相同的 G⁺）
2. Truth evaluation 使用统一 M* 重算流分配：**是**（quadprog 精确 QP）
3. Regret = truth-evaluated 差值：**是**（Δᵢ = J^truth(xᵢ,yᵢ) - J^truth(x*,y*)）
4. M1 port service 从 truth 拟合：**是**
5. M2 nominal footprint 从 truth 提取：**是**
6. M0 aggregate service 从 truth 拟合：**是**
7. Terminal truth model 参数在实验前固定：**是**
8. MIP gap 满足预设标准：**是**（intlinprog 默认精度）
9. Random seed 完整记录：**是**（2 seeds per graph family）
10. Feasibility violation 检查已执行：**是**（truth 下不可用 connector 被 M0 使用时导致大 regret）

---

## 4. 环境设置

### 4.1 候选图

| 图族 | 代号 | Terminal 数 | Waypoint 数 | 说明 |
|------|------|-----------|-----------|------|
| G1s | 4T3W | 4 | 3 | Open-city sparse |
| G2s | 5T4W | 5 | 4 | Open-city dense |
| G3s | 3T3W | 3 | 3 | Airport-adjacent |

- Seeds per family: 2
- 每个 graph-seed 组合上运行多组参数 → 共 60 instances

### 4.2 Terminal 配置
- 各图族的 terminal 具有不同数量的 port（2–4），sector 宽度、service 参数随机生成
- Port offset 机制已启用：port 物理位置从 terminal 中心偏移，确保几何 admissibility 有实际区分度

### 4.3 需求场景
- OD 生成规则：随机 OD 对
- Demand intensity ρ ∈ {0.5, 0.8, 1.0, 1.2}

---

## 5. 参数设置

### 参数扫描网格

| 参数 | 取值 | 含义 |
|------|------|------|
| ρ (demand intensity) | {0.5, 0.8, 1.0, 1.2} | 需求强度 |
| α_A (access restrictiveness) | {0, 0.25, 0.5} | A 通道强度 |
| κ_S (service asymmetry) | {1, 2} | S 通道强度 |
| φ_F (footprint fraction) | {0, 0, 0, 0.3} | F 通道强度（75% 为 φ_F=0） |

- φ_F 采样中 75% 为零值（φ_F=0），这是门控设计的关键：确保有足够的 baseline 样本
- 总参数组合：参数从上述范围中采样，3 图族 × 2 seeds × 参数组合 = 60 instances

### 求解器参数
- 网络求解器：MATLAB intlinprog
- 连续子问题：MATLAB quadprog
- nPwl = 31（高精度分段线性近似）
- MIP gap：默认

---

## 6. EXP-4 专用字段

- 图族与 seed 数：3 图族 × 2 seeds = 6 个 graph 实例
- 参数扫描：ρ × α_A × κ_S × φ_F 从 {0.5,0.8,1.0,1.2} × {0,0.25,0.5} × {1,2} × {0,0,0,0.3} 中采样
- 总实例数：60
- Sufficiency 阈值（预注册）：门控阈值 median < 1%, P95 < 3%
- 是否使用 warm start：否
- 本子实验为 calibration gate，不做 regime 判定，仅验证 baseline 精度

---

## 7. 实验过程记录

| 步骤 | 时间/耗时 | 实际操作 | 关键文件/日志 | 异常与处理 |
|------|----------|---------|-------------|-----------|
| 1. 生成候选图 | ~2s | 生成 G1s/G2s/G3s 各 2 seeds | — | 无 |
| 2. 生成参数组合 | ~1s | 60 组参数采样 | — | 无 |
| 3. 求解 M*/M0/M1/M2 | ~10s | intlinprog + quadprog, nPwl=31 | — | 无 |
| 4. Truth evaluation | ~5s | 每个方案在 M* truth 模型下重算 | — | 无 |
| 5. 计算 regret | ~2s | Δᵢ = J^truth(xᵢ) - J^truth(x*) | — | 无 |
| 6. 门控统计 | ~1s | 按 φ_F=0 / φ_F>0 分组统计 | — | 无 |
| **总耗时** | **~20s** | | | |

---

## 8. 实验结果（定量）

### 8.1 φ_F=0 子集门控结果（41 instances）

| 模型 | Median Regret(%) | P95 Regret(%) | Max Regret(%) | 门控判定 |
|------|-----------------|---------------|---------------|---------|
| **M1** | 0.00% | 0.00% | 0.09% | **PASS** ✓ |
| **M2** | 0.00% | 0.00% | 0.09% | **PASS** ✓ |
| M0 | 0.01% | 3464% | 5586% | — (非门控对象) |

### 8.2 M0 极端 regret 分析

- M0 在 φ_F=0 下出现高达 5586% 的 regret
- 根因：M0 无法区分 admissible 与 inadmissible connectors，选择了在 truth evaluation 中被阻断的 connector
- 当 α_A > 0 时，M0 选中的部分 connector 在 truth 下不可用 → 流量被迫走高成本路径或需求不被满足 → 极端 regret
- **这不是 PwL 误差，而是 A 通道的真实信号**

### 8.3 A 通道价值确认（U01 指标）

| 指标 | φ_F=0 子集 |
|------|-----------|
| U01 均值 | 32.61% |
| U01 > 0 的实例数 | 20 / 41 (48.8%) |

- U01 = (M0 regret - M1 regret) / M0 regret，度量 A 通道信息带来的 regret 降低
- 20/41 实例中 M1 显著优于 M0，A 通道价值已确认

### 8.4 关键发现：Port Offset + Non-Incident Connector 修复的效果

此前（修复前），M1 ≈ M0 问题长期存在——M1 虽然有 admissibility 信息，但无法利用。修复包含两个关键改动：

1. **Port offset**：port 物理位置从 terminal 中心偏移至实际方位，使 connector 的几何方向与 port sector 产生真实匹配/不匹配
2. **Non-incident connector 变化**：确保不同 port 选择确实对应不同的可用 connector 集合

修复后效果：
- M0 出现大量极端 regret（因为它无法区分 admissible/inadmissible）
- M1/M2 regret 接近零（正确利用了 admissibility 信息）
- M1 ≈ M0 问题彻底解决

---

## 9. 初步分析

### 9.1 结果是否符合预期
- ✓ φ_F=0 下 M1/M2 baseline regret 接近零（median=0.00%, max=0.09%）→ PwL 精度充分
- ✓ M0 出现极端 regret → A 通道信号真实存在
- ✓ U01 > 0 的实例占比约一半 → A 通道在实际参数空间中有实质影响

### 9.2 对研究问题的含义
- nPwl=31 的 PwL 近似精度足以支撑后续 EXP-4 regime map 实验
- M1/M2 的 baseline regret 不会污染 regime 判定
- M0 的大 regret 确认了论文核心主张：省略 admissibility 信息（A 通道）会导致严重的网络设计错误

### 9.3 错误归因分析
- M0 的 regret 主要来自 **A 通道信息缺失**：选中了 inadmissible connector，truth evaluation 时被阻断
- 在 φ_F=0 条件下排除了 F 通道的贡献，因此 M0 regret 可完全归因于 A（+S）通道
- M1/M2 regret ≈ 0，说明 S/F 通道的 PwL 近似没有引入可检测的偏差

### 9.4 是否发现 regime 边界或阈值效应
- α_A = 0 时 M0 与 M1 差异较小（所有 connector 均可用），α_A > 0 时差异急剧增大
- 这提示 α_A 是 A 通道 regime 切换的关键参数，后续 EXP-4 应重点覆盖

### 9.5 是否存在异常迹象
- M0 P95=3464%、max=5586%：非异常，已确认为 A 通道信号（inadmissible connector 被选中）
- 无负 regret ✓
- 无 M2 regret > M1 regret 的单调性违反 ✓
- 无求解器未收敛 ✓

### 9.6 Stop / Go 判定
- **条件性 Go** ✓
- Gate criterion：φ_F=0 子集中 M1/M2 baseline regret median < 1%, P95 < 3%
  - M1：median=0.00%, P95=0.00% → **PASS**
  - M2：median=0.00%, P95=0.00% → **PASS**
- M0 大 regret 是 A 通道信号而非 PwL 误差，不影响门控判定
- 可进入 EXP-4 full regime map 扫描

### 9.7 是否需要重跑
- 否

### 9.8 下一步动作
- 进入 EXP-4 full regime map：扩大实例数至数百~千级，覆盖完整参数网格
- 利用门控结果确认 nPwl=31 精度足够，后续实验可沿用
- 关注 α_A 的 regime 切换效应，确保参数网格覆盖 α_A=0 和 α_A>0 两侧

---

## 10. 审核结论

- 审核意见：待审核
- 是否可进入论文主文：是（作为实验方法论的校准证据，进入论文附录或方法学章节）
- 口径核对清单是否全部通过：是
- 审核备注：校准门控通过，M1/M2 baseline regret 远低于门控阈值。Port offset + non-incident connector 修复彻底解决了 M1≈M0 问题，A 通道信号现在清晰可测。可进入 EXP-4 正式实验。
- 签字/日期：待签
