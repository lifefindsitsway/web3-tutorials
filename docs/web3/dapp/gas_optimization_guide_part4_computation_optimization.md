# Gas 优化指南（四）：计算优化

> 本篇是 Gas 优化系列的第四篇，聚焦于计算层面的 Gas 优化。

本篇将介绍循环优化、短路求值、自定义错误、位运算等技巧，并在 UserManagerV2 的基础上完成 UserManagerV3 的计算优化。

## 一、计算优化的价值

计算操作通常远便宜于 storage，但在循环与高频函数中，计算成本会线性累计。计算优化的价值主要体现在两类场景：

1. **循环次数大，批量处理多元素**
2. **storage 热点已经压低，计算成为新的瓶颈**

## 二、循环优化

循环优化的目标是减少每次迭代的额外开销，尤其是避免重复触发昂贵路径。

**缓存长度与常用值**：把 arr.length 等重复读取的值缓存到局部变量，减少迭代中的额外指令路径。

**用 unchecked 包裹递增操作**：Solidity 0.8+ 默认检查算术溢出，这需要额外指令。在确保不会溢出的场景，可以用 unchecked 跳过检查。

**递增前置**：前置递增 `++i` 比后置递增 `i++` 略省 Gas。补充：对 0.8 系列而言，差异经常被编译器优化掉，尤其在优化器开启时。

```solidity
function sumOptimized(uint256[] calldata arr) external pure returns (uint256 total) {
    uint256 len = arr.length;
    for (uint256 i; i < len; ) {
        total += arr[i];
        unchecked { ++i; }
    }
}
```

## 三、短路求值

逻辑运算符 `&&` 和 `||` 会短路求值：

- `A && B`：如果 A 为 false，不计算 B
- `A || B`：如果 A 为 true，不计算 B

优化原则：把更便宜的、更可能短路的条件放前面。

短路优化的价值不是节省一次比较操作，而是避免触发更昂贵的路径，例如 SLOAD、外部调用或哈希计算。

```solidity
// ❌ 昂贵操作在前
function check(uint256 id) external view returns (bool) {
    // balanceOf 需要 SLOAD，即使 id == 0 也会执行
    return balanceOf[id] > 0 && id != 0;
}

// ✅ 便宜操作在前
function check(uint256 id) external view returns (bool) {
    // id != 0 只需栈操作，如果为 false 就短路
    return id != 0 && balanceOf[id] > 0;
}
```

## 四、自定义错误

自定义错误减少部署字节码与 revert data，通常比 require 字符串更省 Gas，并且更利于前端结构化解析。

| 方式                 | 存储内容            | 大小     |
| -------------------- | ------------------- | -------- |
| require("message")   | 错误选择器 + 字符串 | 64+ 字节 |
| revert CustomError() | 错误选择器          | 4 字节   |

```solidity
// ❌ 字符串错误
function withdraw(uint256 amount) external {
    require(amount <= balance, "Insufficient balance");
    // ...
}

// ✅ 自定义错误
error InsufficientBalance(uint256 available, uint256 required);

function withdraw(uint256 amount) external {
    if (amount > balance) {
        revert InsufficientBalance(balance, amount);
    }
    // ...
}
```

## 五、位运算优化

现代编译器会自动优化常量乘除，手动优化的收益有限，位运算不是"通用省 Gas 秘籍"。

位运算优化在 EVM 上的价值主要来自两个地方：bit packing 与 bitmap 类数据结构，以及避免分支或实现 mask 提取。如果只是把 x 乘 8 写成左移，多数情况下收益很有限。

**乘除 2 的幂次**

```solidity
x * 2   →   x << 1
x / 2   →   x >> 1
x * 8   →   x << 3
x / 256 →   x >> 8
```

**取模 2 的幂次**

```solidity
x % 2   →   x & 1
x % 256 →   x & 0xff
```

**判断奇偶**

```solidity
// 传统方式
bool isEven = (x % 2 == 0);

// 位运算
bool isEven = (x & 1 == 0);
```

**位运算符一览**

| 运算 | 运算符 | 含义                       |
| ---- | ------ | -------------------------- |
| 与   | `&`    | 两位都为 1 才为 1          |
| 或   | `\|`   | 任意一位为 1 即为 1        |
| 异或 | `^`    | 两位不同才为 1             |
| 非   | `~`    | 按位取反                   |
| 左移 | `<<`   | 所有位向左移动             |
| 右移 | `>>`   | 所有位向右移动（算术右移） |

注意：`&&` / `||` 是逻辑运算，不是位运算。

## 六、已过时的技巧

以下技巧在早期版本有效，现在已不再推荐：

| 技巧            | 状态           | 原因                      |
| --------------- | -------------- | ------------------------- |
| Gas Token       | ❌ 失效        | EIP-3529 削减了退款上限   |
| 短字符串打包    | ⚠️ 编译器已优化 | Solidity 0.8+ 自动处理    |
| `> 0` 改 `!= 0` | ⚠️ 收益极小    | 编译器通常会优化          |
| `i++` 改 `++i`  | ⚠️ 收益极小    | 在 unchecked 块外差异不大 |

## 七、UserManagerV3：计算优化版

在 UserManagerV2 的基础上，我们继续进行计算层面的优化：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title UserManagerV3
/// @notice Gas 优化版（存储优化、计算优化）
contract UserManagerV3 {
    uint16 public nextUserId = 1;
    uint16 constant MAX_USERS = 1000;
    address public owner;

    struct User {
        uint16 id;             // 用户 ID（与 mapping 的 key 保持一致）
        address wallet;        // 用户绑定的钱包地址（不可更换）
        uint64 lastUpdated;    // 最近一次状态或余额变更的区块时间戳
        bool isBanned;         // 是否被封禁
        uint256 balance;       // 用户余额
    }

    mapping(uint16 => User) public users;
    mapping(address => uint16) public userIdByWallet;

    event UserCreated(uint16 indexed userId, address indexed wallet, uint256 balance, uint64 lastUpdated);
    event BalanceUpdated(uint16 indexed userId, uint256 balance, uint64 lastUpdated);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event UserStatusChanged(uint16 indexed userId, bool status, uint64 lastUpdated);

    error Unauthorized(address owner, address caller);
    error MaxUsersReached(uint16 maxUsers, uint16 nextUserId);
    error InvalidWallet(address wallet);
    error WalletExisted(address wallet);
    error NotExist(uint16 userId);
    error BannedUser(uint16 userId);
    error ZeroAddress();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(owner, msg.sender);
        _;
    }

    function createUserAccount(address wallet) public onlyOwner {
        uint16 newUserId = nextUserId;

        if (newUserId > MAX_USERS) { revert MaxUsersReached(MAX_USERS, newUserId); }
        if (wallet == address(0)) revert InvalidWallet(wallet);
        if (userIdByWallet[wallet] != 0) revert WalletExisted(wallet);

        uint64 ts = uint64(block.timestamp);
        users[newUserId] = User({
            id: newUserId,
            wallet: wallet,
            lastUpdated: ts,
            isBanned: false,
            balance: 0
        });

        userIdByWallet[wallet] = newUserId;

        emit UserCreated(newUserId, wallet, 0, ts);
        unchecked { nextUserId = newUserId + 1; }
    }

    function setBalance(uint16 userId, uint256 amount) public onlyOwner {
        User storage u = users[userId];

        if (u.wallet == address(0)) revert NotExist(userId);
        if (u.isBanned) revert BannedUser(userId);

        uint64 ts = uint64(block.timestamp);
        u.balance = amount;
        u.lastUpdated = ts;

        emit BalanceUpdated(userId, amount, ts);
    }

    function changeStatus(uint16 userId, bool status) public onlyOwner {
        User storage u = users[userId];

        if (u.wallet == address(0)) revert NotExist(userId);

        uint64 ts = uint64(block.timestamp);
        u.isBanned = status;
        u.lastUpdated = ts;

        emit UserStatusChanged(userId, status, ts);
    }

    function checkIfWalletMappedCorrectly(address wallet) public view returns (bool) {
        uint16 id = userIdByWallet[wallet];
        return (id != 0 && users[id].wallet == wallet);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
```

**V2 → V3 核心优化点**

对比 V2 的 changeStatus 函数：

```solidity
// V2 版本
function changeStatus(uint16 userId, bool status) public onlyOwner {
    User storage u = users[userId];
    if (u.wallet == address(0)) revert NotExist(userId);

    u.isBanned = status;
    u.lastUpdated = uint64(block.timestamp);

    emit UserStatusChanged(userId, u.isBanned, u.lastUpdated);
}

// V3 版本
function changeStatus(uint16 userId, bool status) public onlyOwner {
    User storage u = users[userId];
    if (u.wallet == address(0)) revert NotExist(userId);

    uint64 ts = uint64(block.timestamp);
    u.isBanned = status;
    u.lastUpdated = ts;

    emit UserStatusChanged(userId, status, ts);
}
```

V3 版本将事件参数从 storage 读取改为使用局部变量，减少了额外的 SLOAD。

## 八、事件参数使用局部变量的安全性

你可能会担心：如果事件参数使用局部变量而非 storage 读取，会不会出现"storage 没写成功，但事件里却像写成功了一样"的不一致情况？

答案是：在正常 Solidity 执行中，这种不一致不会发生。核心规则如下：

**规则 1**：只要交易没有回滚，emit 之前的 storage 写入也必然发生过。日志与 storage 是同一条执行路径的副产品。EVM 按顺序执行，如果写入时发生错误（out-of-gas、revert），整个调用会回滚，包括 storage 更改和事件日志。

**规则 2**：事件参数用局部变量的常见收益是减少额外 SLOAD，并且更贴近事件语义——事件记录的是动作的输入，而不是最终状态快照。

需要注意的边界情况包括：同一笔交易后面又把值改回去、使用 delegatecall 导致 storage 写在另一个合约、用内联汇编伪造日志等。但这些都不是正常 Solidity emit 的问题，而是特定场景下的"认知陷阱"。

## 九、总结与展望

本篇介绍的计算优化技巧包括：

| 技巧       | 应用场景                           |
| ---------- | ---------------------------------- |
| 循环优化   | 缓存长度、unchecked 递增、前置递增 |
| 短路求值   | 便宜条件前置，避免触发昂贵路径     |
| 自定义错误 | 减少部署字节码与 revert data       |
| 位运算     | bit packing、bitmap、mask 提取     |
| 事件参数   | 使用局部变量减少 SLOAD             |

通过 UserManagerV1 → V2（存储优化）→ V3（计算优化）的演进，我们完成了一个教学合约的完整优化流程。

**进一步优化方向**

合约 Gas 优化还可以从以下方面考虑，但本系列暂不涉及：

- **架构层面**：合约拆分、代理模式、批量操作合并
- **内联汇编**：直接操作 EVM 指令，绕过 Solidity 抽象层
- **编译器优化**：调整 optimizer runs 参数、使用 via-ir 编译管道

这些高级优化技巧需要更深入的 EVM 知识，适合在掌握基础优化后进一步学习。

## 小结

本篇介绍了计算层面的 Gas 优化技巧：

- 循环优化通过缓存长度和 unchecked 递增减少开销；
- 短路求值通过条件排序避免触发昂贵路径；
- 自定义错误比 require 字符串更省 Gas；
- 位运算在特定场景下有优化价值。

通过 UserManagerV2 → UserManagerV3 的演示，我们看到了如何在存储优化的基础上进一步进行计算优化。

下一篇我们将介绍 Gas 评估与测量工具，学习如何使用 Foundry 的 Gas Report、Snapshots 和 gasleft() 来验证优化效果，并对整个系列进行总结。



**系列导航：**

* 第一篇：[Gas 优化指南（一）：Gas 机制原理](./gas_optimization_guide_part1_gas_mechanism.md)
* 第二篇：[Gas 优化指南（二）：EIP-1559 交易解析](./gas_optimization_guide_part2_eip1559_transaction_analysis.md)
* 第三篇：[Gas 优化指南（三）：存储优化](./gas_optimization_guide_part3_storage_optimization.md)

* 第四篇：Gas 优化指南（四）：计算优化（本篇）
* 第五篇：[Gas 优化指南（五）：Gas 评估与测量](./gas_optimization_guide_part5_gas_measurement.md)
