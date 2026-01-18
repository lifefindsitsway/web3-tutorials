# Gas 优化指南（五）：Gas 评估与测量

> 本篇是 Gas 优化系列的最后一篇，聚焦于 Gas 评估与测量工具。

在进行 Gas 优化之前，首先需要准确地测量和评估代码的 Gas 消耗。

本篇将介绍 Foundry 提供的三种 Gas 测量工具：Gas Report、Gas Snapshots 和 gasleft()，帮助你建立完整的 Gas 测量流程。最后，我们将回顾整个系列的核心内容。

## 一、为什么需要 Gas 测量

Gas 测量的作用：

- **建立基线**：了解当前代码的 Gas 消耗情况
- **识别瓶颈**：找出最消耗 Gas 的操作
- **验证优化效果**：对比优化前后的差异
- **防止性能退化**：在 CI/CD 中监控 Gas 消耗变化

## 二、使用 Foundry 的 Gas Report

Gas Report 可以自动统计测试中每个函数的 Gas 消耗。

运行指令：

```bash
forge test --gas-report
```

Gas Report 会输出每个合约函数的 min/avg/max Gas 消耗，适合整体性能评估。

## 三、使用 Gas Snapshots

Gas Snapshots 是 Foundry 的另一个强大功能，用于追踪 Gas 变化，适合 CI/CD 集成。

注意：Gas Report 统计的是合约函数调用的统计，是合约函数本体 gas 统计，而 snapshot 记录的是测试函数整体 gas，是整条测试用例的 gas，包括 setUp，console.log，断言等。

**3.1 创建基线快照**

```bash
forge snapshot
```

默认会在项目根目录生成一个 `.gas-snapshot` 文件，记录每个测试的 Gas 消耗。

**3.2 修改代码后对比**

假设你修改了代码，再次运行：

```bash
forge snapshot --diff
```

Foundry 会自动对比并显示差异。

**3.3 CI 检查**

在 PR 中自动检查 Gas 是否退化：

```bash
forge snapshot --check
```

如果任何测试的 Gas 增加，命令返回非零退出码。

**3.4 最佳实践**

- ✅ 将 `.gas-snapshot` 提交到 Git
- ✅ PR 审查时关注 Gas 变化
- ✅ 设置 CI 自动检查

## 四、使用 gasleft() 精确测量

`gasleft()` 是 Solidity 内置函数，返回当前剩余的 Gas 数量，可以用来精确测量特定代码段的 Gas 消耗。

**4.1 运行精确对比测试**

```bash
forge test --match-test xxx -vv
```

**4.2 注意事项**

- **测量开销**：`gasleft()` 本身消耗约 2 Gas，在精确测量时需要考虑
- **编译器优化**：某些情况下编译器可能会优化掉未使用的代码
- **外部调用影响**：跨合约调用时，Gas 的计算可能更复杂
- **上下文依赖**：测量结果可能受到调用上下文的影响（如存储槽的冷/热状态，导致同一测试中先后调用的 Gas 不同）

## 五、三种方法对比

| 方法          | 优点                           | 缺点             | 适用场景     |
| ------------- | ------------------------------ | ---------------- | ------------ |
| Gas Report    | 自动化、全面、显示 min/avg/max | 粒度较粗         | 整体性能评估 |
| Gas Snapshots | 追踪变化、CI 集成、版本对比    | 需要维护快照文件 | 防止性能退化 |
| gasleft()     | 精确、灵活、可自定义输出       | 需要写测试代码   | 细粒度对比   |

**推荐做法**

1. 建立基线：在优化前先测量当前性能
2. 使用多种工具：结合 Gas Report、Snapshot 和 gasleft()
3. 版本控制：提交 `.gas-snapshot` 文件
4. 关注关键路径：重点优化高频调用的函数
5. 验证优化效果：优化后必须再次测量

**推荐组合**

- 日常开发：Gas Report（快速查看）
- 版本控制：Snapshots（追踪变化）
- 精细优化：gasleft()（精确对比）

## 六、工具速查表

| 工具          | 命令                      | 场景       |
| ------------- | ------------------------- | ---------- |
| Gas Report    | `forge test --gas-report` | 整体评估   |
| 创建 Snapshot | `forge snapshot`          | 建立基线   |
| 对比 Snapshot | `forge snapshot --diff`   | 验证优化   |
| 检查 Snapshot | `forge snapshot --check`  | CI 集成    |
| 精确测量      | `gasleft()` + `-vv`       | 细粒度对比 |

## 七、系列总结

至此，我们完成了整个 Gas 优化系列的学习。

学完本系列，你将掌握：

1. **理论基础**：深入理解 Gas 机制、EIP-1559 定价模型、操作码成本分级
2. **存储优化**：变量打包、结构体打包、constant/immutable、存储指针、瞬时存储
3. **计算优化**：循环优化、短路求值、自定义错误、位运算
4. **测量工具**：使用 Foundry 的 Gas Report、Snapshots、gasleft() 验证优化效果
5. **实战经验**：通过 UserManager 合约的完整优化流程（V1→V2→V3），掌握系统性的优化方法

Gas 优化是一门平衡的艺术。优化通常会使代码变得更难读和更复杂，一个好的工程师必须在可读性、可维护性和 Gas 效率之间做出权衡。记住：先测量，再优化，最后验证。



**系列导航：**

* 第一篇：[Gas 优化指南（一）：Gas 机制原理](./gas_optimization_guide_part1_gas_mechanism.md)
* 第二篇：[Gas 优化指南（二）：EIP-1559 交易解析](./gas_optimization_guide_part2_eip1559_transaction_analysis.md)
* 第三篇：[Gas 优化指南（三）：存储优化](./gas_optimization_guide_part3_storage_optimization.md)

* 第四篇：[Gas 优化指南（四）：计算优化](./gas_optimization_guide_part4_computation_optimization.md)
* 第五篇：Gas 优化指南（五）：Gas 评估与测量（本篇）
