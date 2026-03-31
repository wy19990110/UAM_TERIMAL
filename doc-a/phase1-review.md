# Phase 1 代码审查报告

## 总体评价

Phase 1 的代码质量**整体较好**。数据结构设计清晰，抽象层级插件的信息可见性逻辑正确，测试覆盖了核心路径。但存在若干设计缺陷会阻碍 Phase 2，需要在继续之前修复。

---

## 审查点 1: 数据结构对 R_t = (A, μ, D, V, X, C) 的覆盖

### 覆盖情况

| 1.md 定义 | TerminalResponse 属性 | 状态 |
|---|---|---|
| A (兼容矩阵/可连接方位) | `feasibleCorridors` | 已覆盖 |
| μ (容量) | `capacity` | 已覆盖 |
| D (延误函数) | `delayAlpha`, `delayBeta` + `computeDelay()` | 已覆盖 |
| V (局部空域脚印) | `blockedCorridors`, `footprintRadiusNm` | 已覆盖 |
| X (外部性) | `noiseIndex`, `populationExposure` | 已覆盖 |
| C (资格/关闭规则) | `acceptedVehicleClasses`, `closureWindThresholdKt`, `requiresILS` | 已覆盖 |

### 问题列表

**[1.1] TerminalResponse 延误模型过于简化 — 严重度: minor**
- 文件: `+uam/+core/TerminalResponse.m`
- 延误函数 `D(λ) = α * (λ/(μ-λ))^β` 是 M/M/1 变体。对 Phase 1 stub 够用，但要确保 Phase 2 MIP 求解器中不会把这个公式硬编码——它应通过插件接口获取延误值，而不是自行计算。
- **建议**: 无需修改，但在 Phase 2 MIP 实现时确保只通过 `getDelay()` 获取延误。

**[1.2] TerminalResponse 的外部性建模缺少聚合方法 — 严重度: major**
- 文件: `+uam/+core/TerminalResponse.m`
- `noiseIndex` 和 `populationExposure` 是两个独立标量，但 `FullModelPlugin.getExternalityCost()` 中直接硬编码了 `noiseIndex + populationExposure` 作为聚合方式。
- 这个线性加和缺乏权重参数，且将聚合逻辑放在了插件内部而非 TerminalResponse 本身。
- **建议**: 在 `TerminalResponse` 中添加 `computeExternalityCost(weights)` 方法，或在 MIP 问题定义中明确外部性权重参数。

**[1.3] TerminalResponse 缺少 `closureWindThresholdKt` 的查询方法 — 严重度: minor**
- 文件: `+uam/+core/TerminalResponse.m`
- 有 `allowsCorridor()` 和 `blocksCorridor()` 便利方法，但没有 `isClosed(windSpeed)` 之类的方法。
- `TerminalPlugin` 接口也没有关闭状态查询。
- **建议**: 如果 E0/E1 不涉及天气场景可暂缓，但 A2+ 层级需要此功能。

---

## 审查点 2: TerminalPlugin 接口设计对 MIP 求解器的支撑

**[2.1] 缺少批量查询接口 — 严重度: critical (Phase 2 阻塞)**
- 文件: `+uam/+abstraction/TerminalPlugin.m`
- 当前接口全是逐个查询：`isCorridorFeasible(terminalId, styleId, corridorId)` 每次查一条走廊。
- MIP 求解器需要对所有终端×所有样式×所有走廊构建约束矩阵。逐个调用效率极低，且代码会非常冗长。
- **建议**: 添加批量接口方法：
  ```matlab
  % 返回完整的 TerminalResponse（或其子集）给求解器批量构建约束
  resp = getResponse(obj, terminalId, styleId)
  
  % 或添加批量版本
  feasibility = getFeasibilityVector(obj, terminalId, styleId, corridorIds)
  ```

**[2.2] 缺少目标函数贡献的统一计算接口 — 严重度: major**
- 文件: `+uam/+abstraction/TerminalPlugin.m`
- MIP 目标函数 `J(y; φ)` 需要综合延误成本、激活成本、外部性成本、未满足需求惩罚。当前插件只提供零散的查询方法，没有统一的 `computeObjectiveContribution(terminalId, styleId, flows, corridors)` 之类的方法。
- **建议**: 不必在插件中实现完整目标函数（那是求解器的事），但考虑添加 `getTerminalCost(terminalId, styleId, arrivalRate)` 汇总延误+外部性的方法。

**[2.3] 插件不知道 NetworkInstance 的存在 — 严重度: major**
- 当前插件构造需要传入预计算好的 `responses` Map。这意味着调用方必须先用 MesoscopicModel 为每个 (terminalId, styleId) 对计算 response，再传给插件。
- 这个流程是合理的，但**缺少一个工厂方法**来自动从 NetworkInstance 构建插件。
- **建议**: 添加静态工厂方法，例如：
  ```matlab
  plugin = A0Plugin.fromInstance(networkInstance, mesoscopicModel)
  ```

---

## 审查点 3: A0/A1/Full 信息可见性逻辑

**[3.1] A0 可见性逻辑 — 正确**
- `isCorridorFeasible` 恒返回 `true` ✓
- `isCorridorBlocked` 恒返回 `false` ✓
- `getExternalityCost` 恒返回 `0` ✓
- `isVehicleQualified` 恒返回 `true` ✓
- 测试已覆盖 ✓

**[3.2] A1 可见性逻辑 — 正确**
- `isCorridorFeasible` 查询 `resp.allowsCorridor()` ✓
- `isCorridorBlocked` 恒返回 `false` ✓
- `getExternalityCost` 恒返回 `0` ✓
- `isVehicleQualified` 恒返回 `true` ✓
- 测试已覆盖 ✓

**[3.3] FullModelPlugin 可见性 — 正确**
- 所有方法都查询完整 TerminalResponse ✓
- 测试已覆盖 ✓

**[3.4] 缺少 A2Plugin 和 A2PlusPlugin — 严重度: major**
- 文件: `+uam/+abstraction/`
- 1.md 定义了四个抽象层级 A0/A1/A2/A2+，但只实现了 A0、A1 和 Full。
- `AbstractionLevel` 枚举包含 A2 和 A2Plus，但没有对应插件。
- E1 实验需要 A1 vs A2 的对比，所以 A2Plugin 是 Phase 2 必需的。
- **建议**: 至少补充 A2Plugin（看 A, μ, D, V, X 但不看 C）。A2PlusPlugin 可在 WP7 之前补充。预期实现：
  - `isCorridorFeasible`: 查矩阵
  - `isCorridorBlocked`: 查脚印
  - `getExternalityCost`: 返回实际值
  - `isVehicleQualified`: 恒返回 `true`（A2 不看 C）

---

## 审查点 4: MATLAB OOP 用法

**[4.1] value class vs handle class 混用可能引起困惑 — 严重度: minor**
- `TerminalPlugin` 继承 `handle`，但所有核心数据类（TerminalResponse, NetworkDesign 等）是 value class。
- 这个选择本身是合理的（插件是有状态的服务对象用 handle，数据是不可变值用 value），但需要在文档中明确。
- **建议**: 在项目 README 或设计文档中说明这个约定。

**[4.2] containers.Map 的 key 类型不一致 — 严重度: major**
- 多处使用 `containers.Map`，但 key 有时传 `string`、有时传 `char`。MATLAB 的 `containers.Map` 默认 key 类型是 `char`。
- 例如 `NetworkInstance.getStyles()` 使用 `char(terminalId)`，`DemandScenario.getDemand()` 也使用 `char(key)`。
- 这在当前代码中工作正常（因为到处都做了 `char()` 转换），但很脆弱——如果某处忘记转换就会找不到 key。
- **建议**: 统一在所有 Map 操作中使用 `char` key，或考虑用 dictionary（R2022b+）替代。在代码中添加一个辅助函数 `makeKey()` 来统一 key 生成。

**[4.3] 属性类型验证不完整 — 严重度: minor**
- `NetworkInstance.corridors` 和 `scenarios` 的类型声明只写了 `(:,1)` 但没有指定类名（因为 MATLAB 异构数组的限制）。
- `RegretResult.level` 和 `RegretResult.design` 也没有类型约束。
- **建议**: 对于不能在属性声明中约束的类型，在构造函数中添加 `validateattributes` 检查。

**[4.4] inputParser 和 arguments block 混用 — 严重度: minor**
- `CandidateCorridor` 和 `TerminalStyleConfig` 使用 `inputParser`。
- `DemandScenario` 和 `NetworkInstance` 使用 `arguments` block。
- 两者功能类似但风格不统一。`arguments` block 是更现代的写法（R2019b+），性能更好。
- **建议**: 统一使用 `arguments` block。但这不是紧急事项。

---

## 审查点 5: 测试覆盖

**[5.1] 缺少 MesoscopicModel 测试 — 严重度: major**
- `MesoscopicModel.computeResponse()` 是从 TerminalStyleConfig 到 TerminalResponse 的关键转换。
- 没有任何测试验证：给定样式配置，输出的 response 是否正确（容量计算、脚印传递等）。
- **建议**: 添加 `TestMesoscopicModel.m`，验证 `padCount=2, serviceTime=120` → `capacity=60`，以及 `footprintBlock` 正确传递到 `blockedCorridors`。

**[5.2] 缺少 StyleCatalog 测试 — 严重度: minor**
- 预定义样式的属性值没有被测试验证。
- **建议**: 添加 `TestStyleCatalog.m`，验证 fixedNorth/fixedSouth 容量相同但接口不同。

**[5.3] 缺少端到端流程测试 — 严重度: critical (Phase 2 阻塞)**
- 没有测试验证完整的数据流：
  `StyleCatalog → MesoscopicModel → TerminalResponse → Plugin → 查询`
- 这个端到端路径是 Phase 2 MIP 求解器的基础。
- **建议**: 添加 `TestEndToEnd.m`，构建一个 E0 风格的极小实例，走通全流程。

**[5.4] 缺少边界/错误处理测试 — 严重度: minor**
- 没有测试：查询不存在的 terminalId-styleId 组合时的行为（当前会抛 Map key 错误）。
- 没有测试：`arrivalRate` 为负数时的延误计算。
- **建议**: 添加负面测试用例，或在 TerminalPlugin 中添加输入验证。

---

## 审查点 6: Phase 2 阻塞性设计缺陷

### 阻塞问题汇总

| # | 问题 | 严重度 | 影响 |
|---|---|---|---|
| B1 | 缺少 A2Plugin | critical | E1 实验无法对比 A1 vs A2 |
| B2 | 缺少批量查询接口 | critical | MIP 约束矩阵构建效率极低 |
| B3 | 缺少插件工厂方法 | major | MIP 求解器调用方代码冗长 |
| B4 | 缺少端到端流程测试 | critical | 无法验证 Phase 1 → Phase 2 衔接 |
| B5 | NetworkDesign 缺少样式选择的场景维度 | major | 见下方详述 |

**[B5] NetworkDesign.styleSelection 缺少场景维度 — 严重度: major**
- 文件: `+uam/+core/NetworkDesign.m`
- `styleSelection` 是 `Map: terminalId -> styleId`，这意味着每个终端只能选一个样式。
- 但 1.md 的 MIP 问题中，样式选择 `z_tk` 是一个二元变量（终端 t 选样式 k），且可能需要在多场景下分别求解或统一选择。
- 当前结构假设了 first-stage 决策（样式固定不随场景变化），这个假设在 1.md 中是合理的（终端基建是长期决策），但需要明确。
- `flowAllocation` 也缺少场景维度——多场景下每个场景的流量不同。
- **建议**: 将 `flowAllocation` 改为 `Map: scenarioId -> Map: corridorId -> flow`，或者让 NetworkDesign 只表示单场景方案，另建一个 `MultiScenarioDesign` 来包含场景维度。

**[B6] NetworkDesign 缺少目标函数计算方法 — 严重度: major**
- 文件: `+uam/+core/NetworkDesign.m`
- NetworkDesign 只存储决策变量，但没有方法来计算 `J(y; φ)` 目标函数值。
- Phase 2 的 Regret 计算需要 `J(ŷ; φ_real)` 和 `J(y*; φ_real)`，所以必须有统一的目标函数计算。
- **建议**: 在 Phase 2 中实现 `ObjectiveEvaluator` 类，接受 `(NetworkDesign, NetworkInstance, TerminalPlugin)` 输入，返回目标函数值。

---

## 修改优先级建议

### Phase 2 开始前必须修复（阻塞项）

1. 实现 `A2Plugin`（和可选的 `A2PlusPlugin`）
2. 在 `TerminalPlugin` 中添加 `getResponse()` 批量接口方法
3. 添加插件工厂方法 `fromInstance()`
4. 添加端到端流程测试 `TestEndToEnd.m`

### Phase 2 期间应修复

5. 重构 `NetworkDesign` 的场景维度（flowAllocation 按场景分）
6. 统一 containers.Map 的 key 处理
7. 补充 MesoscopicModel 测试
8. 将 FullModelPlugin.getExternalityCost 中的硬编码聚合改为参数化

### 可延后

9. 统一 inputParser vs arguments block
10. 属性类型验证
11. 负面/边界测试
12. 关闭状态查询方法

---

## 代码亮点

- TerminalPlugin 作为抽象基类的设计思路完全正确，是 Strategy 模式的标准应用
- AbstractionLevel 枚举配合 label() 方法，方便打印和记录
- A0 vs A1 的信息可见性测试（`testA0vsA1FeasibilityGap`）很好地验证了核心区别
- TerminalResponse 的延误计算带了单调性测试
- 包命名空间 `+uam/+core/`, `+uam/+abstraction/`, `+uam/+terminal/` 的组织清晰合理
