# EXP-4D 实验报告：Held-out Recommendation Map

## 1. 报告首页

- 报告编号：EXP-4D-20260407
- 实验日期：2026-04-07
- 实验模块：EXP-4D（Held-out recommendation map）
- 执行人：Claude + 狗修金sama
- 审核人：待定
- 代码分支/提交号：main
- 求解器与版本：MATLAB intlinprog + quadprog (R2024b)
- 报告状态：初稿
- 对应研究问题：
  - [x] 从 (E_A, E_S, E_F) 激励指标能否学到 rule-based planner？
  - [x] Rule 在 held-out 数据上的泛化能力如何？

---

## 2. 实验目的与预期

### 2.1 本次实验目的
从全参数扫描数据中学习 (E_A, E_S, E_F) → M0/M1/M2 的 recommendation rule，并在 held-out 测试集上评估泛化性能。

### 2.2 对应假设/预期现象
- 存在阈值组合使 rule 准确率 > 70%
- Excess regret（rule 选错模型的代价）在测试集上较低

### 2.3 成功判据
- Rule 准确率 > 60%
- Mean excess regret < 5%

---

## 3. 实验设计

- 扫描：αA∈{0,0.15,0.3,0.6} × κS∈{1,2,3} × φF∈{0,0.1,0.2,0.3,0.5,0.7} × ρ∈{0.5,0.8,1.0,1.2,1.5}
- 图族：G1s, G2s, G3a（含 airport）
- 种子：4 per combo
- 总实例：**864**
- Grid search 在 (E_A, E_S, E_F) 阈值空间上寻优

---

## 4. 结果

### 4.1 Truth-best 分布
| 模型 | 实例数 | 比例 |
|------|--------|------|
| M0 | 316 | 36.6% |
| M1 | 395 | 45.7% |
| M2 | 153 | 17.7% |

### 4.2 Calibrated Rule
```
if E_F ≥ 0.10 → M2
elif E_A ≥ 0.20 or E_S ≥ 0.90 → M1
else → M0
```

### 4.3 性能
| 指标 | 值 |
|------|-----|
| Rule 准确率 | **40.3%** |
| Median excess regret | 0.00% |
| Mean excess regret | 246% |
| Max excess regret | 32687% |

---

## 5. 分析

### 5.1 成功判据检验
- ❌ 准确率 40.3% < 60% 阈值
- ❌ Mean excess regret 246% >> 5%

### 5.2 失败原因诊断

1. **E_F 阈值 0.10 过低**：几乎所有有 footprint 的实例都被推向 M2（216/324 在 EXP-6 中为 M2 推荐），但 truth-best 只有 17.7% 是 M2。Rule 过度使用 M2。

2. **E_S 阈值 0.90 过高**：几乎没有实例 E_S 能达到 0.90，S 通道的 rule 形同虚设。

3. **Median excess regret = 0%**：虽然 rule 经常选错模型名称，但多数情况下"错选的模型"恰好也给出最优或接近最优的 truth 值（特别是 M1 和 M2 在很多场景下 truth 评估结果相同）。

4. **Mean 被极端离群值拉高**：max excess regret 达 32687%，来自高 φF 场景下的量纲爆炸。

### 5.3 改进方向
- E_F 阈值提升到 0.3-0.4（与 EXP-4C 发现的 φF=0.4 转折点一致）
- E_S 阈值降低到 0.3-0.5
- 评估 "always M1" baseline 的准确率作为对比
- 考虑决策树或多阈值分段方案替代单阈值 rule

---

## 6. 结论

- 当前 rule 准确率仅 40%，不足以支撑 "rule-based hierarchical planner" 的论文叙述
- 但 median excess regret=0% 表明实际损失不大——M1/M2 在大部分场景下等效
- 需要重新校准阈值或改用更灵活的分类策略

---

## 7. 数据位置
- 结果文件：`results/exp4d/exp4d_results.mat`
- Rule 文件：`results/exp4d/calibrated_rule.mat`
- 日志：`results/exp4d/exp4d_log.txt`
- 脚本：`+asf/+experiments/runEXP4D.m`
