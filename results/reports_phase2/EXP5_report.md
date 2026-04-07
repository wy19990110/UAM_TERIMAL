# EXP-5 实验报告：三类 Realistic Proxy

## 1. 报告首页

- 报告编号：EXP-5-20260407
- 实验日期：2026-04-07
- 实验模块：EXP-5（Three-type realistic proxy suite）
- 执行人：Claude + 狗修金sama
- 审核人：待定
- 代码分支/提交号：main
- 求解器与版本：MATLAB intlinprog + quadprog (R2024b)
- 报告状态：初稿
- 对应研究问题：
  - [x] A/S/F 三条通道在 realistic proxy 中是否各自能改变网络设计？

---

## 2. 实验目的与预期

### 2.1 本次实验目的
构建三类针对性 proxy（A-sensitive, S-sensitive, F-sensitive），验证每类 proxy 确实激活对应通道，审稿人可看到每条通道在"像真的图"里都有实际效果。

### 2.2 对应假设/预期现象
- A-sensitive：M0 regret 大，M1 恢复（U01 大）
- S-sensitive：M0 regret 大，M1 恢复（U01 大）
- F-sensitive：M0 > M1 > M2（U01 和 U12 都大）

### 2.3 成功判据
- 每类 proxy 中对应通道的 uplift > 10%
- 三类 proxy 的 "主激活通道" 各不相同

---

## 3. 实验设计

| Proxy Type | 关键参数 | 目标激活通道 |
|------------|----------|-------------|
| A-sensitive | αA=0.5, portMisalignDeg=40, F=0 | A |
| S-sensitive | A=0, F=0, couplingM=0.4, psiSat=3, concentration=0.6 | S |
| F-sensitive | αA=0.25, φF=0.5, hasAirport=true | F |

- 每类：5 seeds × 3 ρ levels = 15 实例
- 总实例：**45**
- nPwl = 15

---

## 4. 结果

### 4.1 按 Proxy Type 汇总

| Proxy Type | n | M0 regret | M1 regret | M2 regret | U01 | U12 |
|------------|---|-----------|-----------|-----------|-----|-----|
| A-sensitive | 15 | 1560% ± 1484% | 0.0% ± 0.0% | 0.0% ± 0.0% | 57.4% | 0.0% |
| S-sensitive | 15 | 255% ± 586% | 0.0% ± 0.0% | 0.0% ± 0.0% | 24.1% | 0.0% |
| F-sensitive | 15 | 48031% ± 60020% | 29632% ± 30295% | 10112% ± 20007% | 17.3% | 41.3% |

---

## 5. 分析

### 5.1 成功判据检验
- ✅ A-sensitive：U01=57.4% >> 10%
- ✅ S-sensitive：U01=24.1% > 10%
- ✅ F-sensitive：U01=17.3%, U12=41.3% > 10%
- ✅ 三类 proxy 主激活通道各不相同

### 5.2 关键发现

1. **A-sensitive proxy 完美验证 A 通道**：M0 regret=1560%，加入 admissibility 信息（M1）后 regret 瞬间归零。port 方向偏移 + 非 incident connector 的设计有效。

2. **S-sensitive proxy 验证 S 通道**：M0→M1 提升显著（U01=24%），M1 已完全恢复 truth。高 coupling + OD 集中度有效激活了 S 通道。

3. **F-sensitive proxy 展示三级递降**：
   - M0 → M1：从 48031% 降到 29632%（A 的贡献，U01=17.3%）
   - M1 → M2：从 29632% 降到 10112%（F 的贡献，U12=41.3%）
   - 但 **M2 regret 仍高达 10112%**，说明即使使用 footprint 信息，当前 M2 solver 在 airport-adjacent 场景下仍有严重偏差。

4. **方差极大**：F-sensitive proxy 的标准差与均值同量级（60020% vs 48031%），说明结果在不同 seed/ρ 组合下变化剧烈。

### 5.3 问题
- F-sensitive proxy 中 M2 regret=10112% 远超预期。需要检查 airport 场景下 truth model 的 footprint penalty 量纲。
- 与 EXP-4C 的高 φF 异常一致。

---

## 6. 结论

- A/S/F 三类 proxy **各自成功激活了对应通道**，验证了三通道抽象框架的设计合理性
- A-sensitive 和 S-sensitive 效果清晰（M1 完全恢复 truth）
- F-sensitive 展示了三级递降，但绝对 regret 仍然过高
- 论文可用本实验的 A-sensitive 和 S-sensitive 结果直接支撑 Proposition 1 和 2

---

## 7. 数据位置
- 结果文件：`results/exp5/exp5_results.mat`
- 日志：`results/exp5/exp5_log.txt`
- 脚本：`+asf/+experiments/runEXP5.m`
