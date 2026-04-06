# 主模型升级实施计划（送审稿 v3，已按两轮审阅意见修订）

**基于 4.md 冻结的 4 个建模决策，将 MVP-反例层推进到主论文层的具体实施方案。**

---

## 冻结决策回顾

| # | 决策 | 冻结内容 |
|---|------|----------|
| Q1 | Ψ_t 形式 | $\Psi_t = \eta\tilde{L}_t + \xi\tilde{X}_t$，$L_t = \sum_h \lambda_{t,h} D_{t,h}(\lambda_{t,h})$，向量化负荷 |
| Q1.4 | 参数 | $\eta=1$，$\xi=0.1$（A2基线），敏感性 $\xi \in \{0, 0.05, 0.1, 0.2\}$ |
| Q2 | 容量 | 硬上界 + 软拥堵混合；$\mu$ 仅由 pad 决定，waiting slots 影响 $D$ 形状 |
| Q3 | z 角色 | 核心实验外生固定，附加实验内生 |
| Q4 | $X_t$ | E0/E1 中 $\xi=0$；主实验 $X_t = \bar{X}_t + \sum_h \chi_{t,h}\lambda_{t,h}$ 进目标 |

---

## 一、改动总览

```
数据层     TerminalStyleConfig → TerminalResponse → NetworkDesign（扩展接口级参数）
模型层     MesoscopicModel（容量公式修正）+ DelayModel（接口级延误拟合 + D_agg 标定）
抽象层     TerminalPlugin 新增 getPsiFunction()，各层级实现 Ψ_t 差异
求解层     TwoStageMIP（λ_{t,h} 变量 + 按层级分解的 Ψ_t 线性化 + 两层容量约束）
评估层     Evaluator（同步加入 Ψ_t 计算）
实验层     E0/E1 适配 + 新增 E0b 渐变 regret 实验
```

**阶段说明**：当前实施计划仅覆盖核心实验（$z$ 外生）的求解器升级，因此暂不包含 $F^{term}(z)$。若进入附加实验（$z$ 内生），将补入 $F^{term}(z) = \sum_{t,k} f^{term}_{tk} z_{tk}$，其中 $f^{term}_{tk}$ 初期用样式复杂度/基础设施代理成本表示。

---

## 二、目标函数升级

### 当前（MVP 层）

$$J = \sum_e a_e x_e + \sum_\omega p_\omega \left[\sum_e c_e f_e^\omega + \kappa \cdot unmet^\omega\right]$$

### 升级后（主论文层）

$$J = F^{route}(x) + \sum_\omega p_\omega \left[\sum_e c_e f_e^\omega + \sum_t \Psi_t(\boldsymbol{\lambda}_t^\omega; \phi_t) + \kappa \cdot unmet^\omega\right]$$

其中：

$$\Psi_t = \eta \cdot \tilde{L}_t + \xi \cdot \tilde{X}_t$$

$$L_t = \sum_{h \in \mathcal{H}_t} \lambda_{t,h} \cdot D_{t,h}(\lambda_{t,h}; \phi_t)$$

$$X_t = \bar{X}_t(\phi_t) + \sum_{h \in \mathcal{H}_t} \chi_{t,h} \cdot \lambda_{t,h}$$

**无量纲化定义**：

$$\tilde{L}_t = \frac{L_t}{L^{ref}}, \quad \tilde{X}_t = \frac{X_t}{X^{ref}}$$

其中 $L^{ref}$ 与 $X^{ref}$ 由基准终端样式在基准负荷水平下的总延误量与总外部性确定。第一篇只做相对权重敏感性分析，不做绝对经济标定。因此 $\eta=1, \xi=0.1$ 是在无量纲化后的尺度下成立。

> **注**：目前实现阶段为单商品版本。主论文推广到多 OD 时，$\lambda_{t,h}^\omega = \sum_{od} \sum_{e \in E_h(t)} f_{od,e}^\omega$ 将显式加入商品索引。

---

## 三、新增约束

### C5: 负荷-流量链接

$$\lambda_{t,h}^\omega = \sum_{e \in E_h(t)} f_e^\omega \quad \forall t, h, \omega$$

其中 $E_h(t)$ 是流经终端 $t$ 的接口 $h$ 的走廊集合。

### C6: 终端容量约束（两层）

**总终端容量上界**：

$$\sum_{h \in \mathcal{H}_t} \lambda_{t,h}^\omega \le \mu_t \quad \forall t, \omega$$

**接口级有效域约束**：

$$\lambda_{t,h}^\omega \le \bar{\lambda}_{t,h} \quad \forall t, h, \omega$$

其中 $\bar{\lambda}_{t,h}$ 来自接口服务能力或延误函数 $D_{t,h}$ 的拟合可信域上界。这保证 $D_{t,h}(\lambda_{t,h})$ 始终在拟合域内求值。

### C7: Ψ_t 分段线性化（按抽象层级分解）

**关键设计**：$\Psi_t$ 的线性化方式必须与抽象层级一致，不能把 A1/A2 的接口级信息重新聚合掉。

#### A0 层级：总负荷一元函数

A0 只看聚合延误，$\Psi_t$ 是总负荷 $\lambda_{total}$ 的一元函数：

$$\lambda_t^\omega = \sum_h \lambda_{t,h}^\omega, \quad \psi_t^\omega \approx \Psi_t^{A0}(\lambda_t^\omega)$$

对 $\Psi_t^{A0}(\lambda_t)$ 做 SOS2 分段线性插值（5-8 个断点）。

#### A1 / A2 / Full 层级：按接口分解

A1/A2 的 $\Psi_t$ 是按接口可分的。对每个接口 $h$ 的延误贡献 $L_{t,h} = \lambda_{t,h} \cdot D_{t,h}(\lambda_{t,h})$ 单独做分段线性化：

$$\lambda_{t,h}^\omega = \sum_{j=0}^{m} \Lambda_{h,j} \cdot w_{t,h,j}^\omega, \quad \ell_{t,h}^\omega = \sum_{j=0}^{m} \mathcal{L}_{h,j} \cdot w_{t,h,j}^\omega$$

$$\sum_{j=0}^{m} w_{t,h,j}^\omega = 1, \quad w_{t,h,j}^\omega \ge 0, \quad \{w_{t,h,j}^\omega\} \in \text{SOS2}$$

然后汇总：

$$\psi_t^\omega = \eta \sum_h \frac{\ell_{t,h}^\omega}{L^{ref}} + \xi \cdot \tilde{X}_t^\omega$$

其中 $X_t = \bar{X}_t + \sum_h \chi_{t,h} \lambda_{t,h}$ 本身已是线性的，**不需要 SOS2**，直接进目标。

#### SOS2 实现方式（已冻结）

- **核心实验（E0/E1/E0b）**：MATLAB `intlinprog`，用**增量式二进制变量模拟 SOS2**
- **城市级实验如需扩展**：切换到 Gurobi（原生 SOS2 支持）

---

## 四、容量公式修正

### 当前

$$\mu = \min\left(\frac{padCount \times 3600}{serviceTime},\; \frac{waitingSlots \times 3600}{serviceTime}\right)$$

### 修正后

$$\mu_t = \frac{padCount \times 3600}{serviceTime}$$

waiting slots 不再参与 $\mu$ 计算，改为影响 $D(\lambda)$ 的形状：
- 有限缓冲导致更陡的延误曲线
- 接近满缓冲时延误急剧上升
- 具体机制：DelayModel 中的合流延误和等待延误项的分母引入 waitingSlots 饱和效应

---

## 五、各抽象层级的 Ψ_t 差异实现

| 层级 | $L_t$ 计算方式 | $X_t$ 进入 | Ψ_t 线性化方式 |
|------|---------------|------------|---------------|
| **A0** | $L_t = \lambda_{total} \cdot D_{agg}(\lambda_{total})$，聚合 | 不进入（$\xi=0$） | 总负荷一元 SOS2 |
| **A1** | $L_t = \sum_h \lambda_{t,h} \cdot D_{t,h}(\lambda_{t,h})$，按接口 | 不进入（$\xi=0$） | 按接口分解 SOS2 |
| **A2** | 同 A1 | $\xi > 0$，$X_t$ 线性项直接进目标 | 按接口分解 SOS2 + 线性 X |
| **Full** | 直接调用真值模型或高保真查找表 | 同 A2 | 按接口分解 SOS2 + 线性 X |

### A0 的聚合延误函数 $D_{agg}$ 定义

A0 的聚合延误函数 $D_{agg}(\lambda_{total})$ **不由接口级延误函数做解析平均**，而是由同一终端区真值模型在"仅以总入流为输入"的条件下标定得到。即：

- 真值模型输入：$\boldsymbol{\lambda}_t = (\lambda_{t,h})_{h \in \mathcal{H}_t}$（向量）
- A0 代理输入：$\lambda_{total} = \sum_h \lambda_{t,h}$（标量）
- 用中观模型在多组"均匀分配到各接口"的条件下计算总延误量，拟合 $D_{agg}$ 参数

这样 A0 是对真值模型的一个**合理的粗粒化一元代理**，而不是来源不明的聚合函数。

### A2 与 Full 的区别

A2 与 Full 在"可见信息项"上相同（都看 $A, \mu, D, V, X$），但在实现层面不同：

- **A2**：使用由中观终端模型标定得到的**代理函数**（$D_{t,h}^{sur}$、$\bar{X}_t^{sur}$、$\chi_{t,h}^{sur}$），是对真值模型的参数化近似
- **Full**：采用预计算的高保真查找表或离线评估结果，不经过代理拟合，不在城市级 MIP 中在线调用中观仿真

因此 Full 仍是 A2 的真值基准，而非同一模型。A2 的 regret 来源是代理拟合误差。

**Full 的使用范围**：Full 仅用于 E0/E1/E0b 及必要的小规模验证实验，作为 regret 的真值基准。城市级实验不直接用 Full 参与优化，只用 A0/A1/A2/A2+ 及其代理函数。

**A2 在 E0/E1 中的角色说明**：在 E0/E1 中，A2 主要承担"局部空域脚印/阻塞信息层"的角色；A2 作为完整的"外部性层级"只在主实验中通过 $\xi > 0$ 激活。

**A0 的 $D_{agg}$ 误差来源说明**：$D_{agg}$ 是在固定调度策略和预设接口分配规则（均匀分配）下得到的一元代理，因此其误差既来自接口信息丢失，也可能来自聚合策略本身。这个界限需在论文讨论中明确。

### 关键差异机制

- A0 用 $D_{agg}(\lambda_{total})$ → **丢失接口级拥堵不均衡信息**
- A1 用 $D_{t,h}(\lambda_{t,h})$ → **能区分不同方向的拥堵差异**
- A2 额外加 $X_t$ → **外部性成本影响路径偏好**
- Full 用真值模型直接评估 → **无代理拟合误差**

---

## 六、接口集合 $\mathcal{H}_t$ 定义（已冻结）

- **玩具实验（E0/E1/E0b）**：每条可行接入走廊就是一个接口，$|\mathcal{H}_t| = |\text{feasibleCorridors}_t|$
- **城市级实验**：按方位扇区聚合（如 4 象限或 8 扇区），将多条走廊映射到同一接口组

---

## 七、实施顺序

| 步骤 | 内容 | 验证门 |
|------|------|--------|
| 1 | 数据结构扩展（TerminalResponse, StyleConfig, NetworkDesign） | 构造测试通过 |
| 2 | 终端模型修正（容量公式 + 接口级延误拟合 + $D_{agg}$ 标定） | TestTerminalModel 通过 |
| 3 | 插件层扩展（getPsiFunction 各层级实现） | TestAbstraction 通过 |
| 4 | MIP 升级（λ 变量 + 按层级分解的 Ψ 线性化 + 两层容量约束） | TestSolver + TestPsi 通过 |
| 5 | 评估器升级（Ψ_t 进入 J 计算） | TestE0 + TestE1 回归通过 |
| 6 | E0b 渐变 regret 实验 | A0 的 regret 来自接口级延误差异（渐变，非硬切） |

---

## 八、新增实验 E0b：渐变 regret

### 目的

验证 Ψ_t 进入目标后，**接口级延误差异也能驱动 regret**（而非仅依赖接口可行性/阻塞的硬切换）。

### 设计

**单个目标终端 T，两个接口 $h_1, h_2$，两条走廊（微小成本差异消除平局）。**

- 终端 T 有两个接口 $h_1, h_2$
- 走廊 1 接 $h_1$（高效直线进近，延误低），外部成本 $c_1 = 1.02$
- 走廊 2 接 $h_2$（绕行进近，延误高），外部成本 $c_2 = 1.00$
- 总容量和接口集合完全相同，仅 $D_{T,h_1}(\lambda) \neq D_{T,h_2}(\lambda)$
- **A0**：只看 $D_{agg}(\lambda_{total})$，两走廊终端成本近乎无差别，但 $c_2$ 更便宜 → **选走廊 2（高延误接口）**
- **A1**：看见 $D_{T,h_1} < D_{T,h_2}$，终端延误差异超过走廊成本差异 → **选走廊 1（低延误接口）**

### 为什么给走廊 2 微小成本优势

如果两走廊完全等成本，A0 可能随机选到好接口（平局问题）。给"错误接口"的走廊一个很小的成本优势（$c_2 < c_1$），确保 A0 **可重复地选错**——它会被便宜的走廊成本吸引，但看不见更高的终端延误。

### 预期结果

- $\Delta_{A0} > 0$（**渐变**，非硬切）：A0 选了走廊成本低但终端延误高的路径
- $\Delta_{A1} \approx 0$：A1 正确权衡接口级延误，选了总成本更低的路径

### 这个实验证明什么

> 即使接口集合相同、终端总容量也相同，单纯聚合延误也不够；**接口级延误才是必要信息**。

---

## 九、仅余的确认点

以下事项已内部冻结，不再上抛：
- $\mathcal{H}_t$ 定义（第六节已冻结）
- SOS2 实现方式（第三节 C7 已冻结）

**唯一需要确认的问题**：

> **第一篇默认采用"固定调度策略 + 均匀接口分配"标定 $D_{agg}$**。更一般的接口分配策略族（如按历史/预测流量比例分配）作为局限性与后续扩展讨论，而不是本轮实现前提。
>
> 如果实际流量分布严重不均匀，$D_{agg}$ 的代理质量可能下降——但这本身也是 A0 信息丢失的一部分，恰好说明接口级信息的必要性。
>
> **需确认**：是否同意此默认方案，还是需要在第一篇中就做多种标定策略的对比。
