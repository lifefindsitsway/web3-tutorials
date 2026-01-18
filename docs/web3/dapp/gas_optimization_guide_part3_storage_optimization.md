# Gas 优化指南（三）：存储优化

> 本篇是 Gas 优化系列的第三篇，聚焦于存储层面的 Gas 优化。

存储读写是 EVM 中最昂贵的操作，本篇将介绍变量打包、结构体打包、constant/immutable、缓存存储变量、瞬时存储等核心技巧，并通过一个教学版用户管理合约（UserManagerV1 → UserManagerV2）演示完整的存储优化过程。

## 一、为什么存储优化最重要

存储优化的核心目标不是"少写一点"，而是系统性地减少三类成本：

1. **减少 0 → 非 0 的首次写入次数**
2. **减少每笔交易触达的 cold slot 数量（即新 slot 数量）**
3. **减少对同一 slot 的重复写入次数，尤其是 read-modify-write**

优化存储是 Gas 优化的核心。

回顾存储成本：

| 操作                  | Gas 成本     |
| --------------------- | ------------ |
| SLOAD（冷）           | 2,100        |
| SLOAD（热）           | 100          |
| SSTORE（0 → 非零）    | 22,100       |
| SSTORE（非零 → 非零） | 5,000        |
| SSTORE（非零 → 0）    | 5,000，退款  |
| MLOAD/MSTORE          | 3            |
| ADD/SUB               | 3            |

结论：在多数写状态合约中，storage 成本往往决定交易成本上限。

本章的技巧按目标可分为三类：

**A. 减少槽位数量与 cold 触达**：变量打包、结构体打包、类型精简

**B. 减少读写次数**：storage 指针与惰性读取、缓存 SLOAD、合并写入

**C. 避免昂贵状态转移**：避免 0 → 非 0、合理使用 transient 替代交易内锁

## 二、变量打包

EVM 每个 storage slot 为 32 字节，小于 32 字节的变量可以按声明顺序打包。

注意：打包减少槽位数量，但对同一 slot 的单字段写入可能触发 read-modify-write。只有当读写模式匹配时，打包才稳定省 Gas。

推荐规则：

- 读多写少，且经常一起读取的字段适合打包
- 高频独立更新的字段谨慎打包，否则会放大 slot 重写次数

```solidity
// ❌ 未优化：3 个槽位
contract Unpacked {
    uint64 a;    // slot 0（独占）
    uint256 b;   // slot 1
    uint64 c;    // slot 2（独占）
}

// ✅ 优化后：2 个槽位
contract Packed {
    uint64 a;    // slot 0
    uint64 c;    // slot 0（与 a 打包）
    uint256 b;   // slot 1
}
```

常见打包组合：

| 组合                    | 总大小             | 槽位数 |
| ----------------------- | ------------------ | ------ |
| address + uint96        | 160 + 96 = 256     | 1      |
| address + uint64 + bool | 160 + 64 + 8 = 232 | 1      |
| uint128 + uint128       | 128 + 128 = 256    | 1      |
| uint64 × 4              | 64 × 4 = 256       | 1      |

## 三、结构体打包

结构体成员同样可以打包，但需要注意声明顺序。

```solidity
// ❌ 未优化：3 个槽位
struct User {
    uint64 timestamp;  // slot n
    uint256 balance;   // slot n+1（无法打包）
    address owner;     // slot n+2
}

// ✅ 优化后：2 个槽位
struct User {
    uint64 timestamp;  // slot n
    address owner;     // slot n（与 timestamp 打包，共 224 位）
    uint256 balance;   // slot n+1
}
```

节省：读写结构体时减少 1 次 SLOAD/SSTORE。

## 四、constant 和 immutable

不变的值应该声明为 constant 或 immutable，因为它们不占用 storage slot，读取来自 code 而不是 SLOAD。

| 类型      | 特点               | 存储位置 |
| --------- | ------------------ | -------- |
| 普通变量  | 可修改             | 存储槽   |
| constant  | 编译时确定，不可改 | 字节码   |
| immutable | 部署时确定，不可改 | 字节码   |

**constant**：必须在编译时确定，直接内联到字节码，不分配 storage slot。对 constant 的"读取"不是 SLOAD，而是 PUSH32 等便宜指令，运行时省掉每次读取的 SLOAD（尤其是 cold 的 2100 量级）。适用场景：手续费分母、固定倍率、类型 hash 等协议级永不变参数。

**immutable**：部署时确定，构造函数执行完后固定，存进合约代码而不是 storage。读取成本是"从 code 取常量"，比 SLOAD 便宜。适用场景：owner（不需要可升级的合约）、外部依赖合约地址（weth、router、oracle 等）、部署时决定的费率参数。

```solidity
// ❌ 浪费存储
contract Bad {
    uint256 MAX_SUPPLY = 10000;  // 占用 slot 0
    
    function getMax() external view returns (uint256) {
        return MAX_SUPPLY;  // SLOAD: 2100 gas
    }
}

// ✅ 零存储成本
contract Good {
    uint256 constant MAX_SUPPLY = 10000;  // 嵌入字节码
    
    function getMax() external pure returns (uint256) {
        return MAX_SUPPLY;  // 无 SLOAD，约 3 gas
    }
}
```

## 五、缓存存储变量

Solidity 不会自动缓存存储读取，多次读取同一变量，每次都会执行 SLOAD。

同一笔交易内，对同一 slot 的重复读取，第一次是 cold，后续是 warm。缓存能避免后续 warm SLOAD 的 100 Gas，同时也减少重复读取的字节码路径。

```solidity
// ❌ 多次读取
function increment() public {
    require(count < 10);    // SLOAD #1
    count = count + 1;      // SLOAD #2 + SSTORE
}

// ✅ 缓存后单次读取
function increment() public {
    uint256 _count = count; // SLOAD #1（缓存到内存）
    require(_count < 10);   // 读内存
    count = _count + 1;     // SSTORE
}
```

## 六、瞬时存储（Transient Storage）

2024 年 Cancun 升级引入的新特性，使用 TSTORE/TLOAD 操作码。

| 特性     | 普通存储       | 瞬时存储       |
| -------- | -------------- | -------------- |
| 持久性   | 永久           | 交易结束后清除 |
| 写入成本 | 5,000 - 22,100 | 100            |
| 读取成本 | 100 - 2,100    | 100            |

瞬时存储只在 Cancun 后链上可用，且仅在同一笔交易内有效，不能跨交易保存状态，因此只能替换"交易内锁与临时标记"，不能替换业务状态。

适用场景：重入锁、闪电贷状态、跨合约调用的临时标记。

```solidity
// ❌ 传统方式
contract Traditional {
    uint256 private _status = 1;
    
    modifier nonReentrant() {
        require(_status != 2);
        _status = 2;  // SSTORE: ~5,000 gas
        _;
        _status = 1;  // SSTORE: ~5,000 gas
    }
}

// ✅ 瞬时存储（Solidity 0.8.24+）
contract Transient {
    bool private transient _locked;
    
    modifier nonReentrant() {
        require(!_locked);
        _locked = true;   // TSTORE: 100 gas
        _;
        _locked = false;  // TSTORE: 100 gas
    }
}
```

## 七、避免 0 到非 0 写入

从 0 写入非零值是最贵的操作（22,100 Gas）。

避免从 0 写入非零的实战技巧：用 1 和 2 代替 0 和 1 作为状态标记。OpenZeppelin 的 ReentrancyGuard 就是这样做的：

```solidity
uint256 private constant NOT_ENTERED = 1;
uint256 private constant ENTERED = 2;
uint256 private _status = NOT_ENTERED;  // 初始化为 1

modifier nonReentrant() {
    require(_status != ENTERED);
    _status = ENTERED;  // 1 → 2: 5,000 gas（而非 0 → 1 的 22,100）
    _;
    _status = NOT_ENTERED;  // 2 → 1: 5,000 gas
}
```

## 八、映射 vs 数组

数组读通常包含长度读取与越界检查等额外逻辑，这需要额外的 Gas；映射读没有边界检查，但映射无法遍历。是否省 Gas 依赖上下文，数值建议以实际编译产物与 trace 为准。

```solidity
// 数组读取
contract UseArray {
    uint256[] public data;
    
    function get(uint256 i) external view returns (uint256) {
        return data[i];  // 包含边界检查
    }
}

// 映射读取
contract UseMapping {
    mapping(uint256 => uint256) public data;
    
    function get(uint256 i) external view returns (uint256) {
        return data[i];  // 无边界检查
    }
}
```

## 九、存储指针 vs 内存复制

在介绍完整的优化案例之前，先理解一个关键概念：存储指针（storage）与内存复制（memory）的区别。

| 声明方式                            | 行为                           | Gas 消耗               |
| ----------------------------------- | ------------------------------ | ---------------------- |
| `User memory user = users[userId]`  | 将整个结构体复制到内存         | 每个字段都 SLOAD       |
| `User storage user = users[userId]` | 创建一个指针，指向存储位置     | 仅声明时不读取任何数据 |

```solidity
// memory：复制整个结构体到内存
User memory user = users[userId];
// → SLOAD slot n（读取 wallet + lastActive + isActive）
// → SLOAD slot n+1（读取 balance）
// → 即使只需要 balance，也会读取所有字段

// storage：只保存一个指针
User storage user = users[userId];
// → 不执行任何 SLOAD（惰性加载）
// → 访问 user.balance 时才 SLOAD slot n+1
// → 访问 user.isActive 时才 SLOAD slot n
```

存储指针是惰性的：只有在访问具体字段时才执行 SLOAD。如果结构体有 5 个槽位但你只需要 1 个字段，使用 storage 可以节省 80% 的读取成本。

storage 引用变量（T storage ref）指向某个 storage 对象时，赋值得到的是引用/别名，修改 ref 会修改原 storage。以 `User storage user = users[userId]` 为例：修改 user 的内容，等同于修改 users[userId]。

下面通过一个极简合约演示这一概念：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract UserManagerSimple {
    struct User {
        address wallet;     // 160 bits
        uint48 lastActive;  // 48 bits（够用数百万年）
        bool isActive;      // 8 bits
        // address + uint48 + bool 总计 216 bits，打包在同一个 slot
        uint256 balance;    // slot n+1
    }
    
    uint256 public userCount;
    uint256 constant maxUsers = 1000;   // constant 不占槽位
    mapping(uint256 => User) public users;
    
    function updateBalance(uint256 userId, uint256 amount) external {
        User storage user = users[userId];          // 存储指针
        require(user.isActive);                     // 只读需要的字段
        uint256 newBalance = user.balance + amount; // 缓存
        user.balance = newBalance;
        user.lastActive = uint48(block.timestamp);
    }
}
```

优化要点：

| 技巧       | 应用                                          |
| ---------- | --------------------------------------------- |
| 结构体打包 | wallet + lastActive + isActive 打包到一个槽位 |
| 类型精简   | lastActive 从 uint256 改为 uint48             |
| constant   | maxUsers 改为 constant                        |
| 存储指针   | 使用 storage 而非 memory                      |
| 缓存       | 计算结果缓存后再写入                          |

## 十、教学版用户管理合约：UserManagerV1

UserManagerSimple 只是一个极简示例，用于演示存储指针的概念。接下来我们引入一个更完整的教学合约 UserManagerV1，它将作为后续所有优化工作的基础。

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title UserManagerV1
/// @notice 教学版用户管理合约，用于 Gas 优化练习
/// @dev 本合约不考虑可升级性、不支持删除用户或迁移钱包，仅用于教学场景
contract UserManagerV1 {
    // 下一个可分配的用户 ID
    uint256 public nextUserId = 1;
    // 最大允许创建的用户数量（等价于最大 userId）
    uint256 public constant MAX_USERS = 1000;
    address public owner;

    /// @notice 用户结构体
    /// @dev isBanned=true 表示用户被封禁，封禁用户无法修改余额
    struct User {
        uint256 id;            // 用户 ID（与 mapping 的 key 保持一致）
        uint256 balance;       // 用户余额（教学中用于演示 SSTORE 行为）
        uint256 lastUpdated;   // 最近一次状态或余额变更的区块时间戳
        address wallet;        // 用户绑定的钱包地址（不可更换）
        bool isBanned;         // 是否被封禁
    }

    mapping(uint256 => User) public users;
    // wallet => userId 的反向索引，0 表示该 wallet 尚未注册
    mapping(address => uint256) public userIdByWallet;

    event UserCreated(uint256 indexed userId, address indexed wallet, uint256 balance, uint256 lastUpdated);
    event BalanceUpdated(uint256 indexed userId, uint256 balance, uint256 lastUpdated);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    /// @dev status == true 表示 isBanned == true（用户被封禁）
    event UserStatusChanged(uint256 indexed userId, bool status, uint256 lastUpdated);

    error Unauthorized(address owner, address caller);
    error MaxUsersReached(uint256 maxUsers, uint256 nextUserId);
    error InvalidWallet(address wallet);
    error WalletExisted(address wallet);
    error NotExist(uint256 userId);
    error BannedUser(uint256 userId);
    error ZeroAddress();

    /// @notice 构造函数，部署者成为初始 owner
    constructor() {
        owner = msg.sender;
    }

    /// @notice 仅允许 owner 调用的修饰器
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(owner, msg.sender);
        _;
    }

    /// @notice 创建一个新用户账户
    /// @param wallet 用户绑定的钱包地址（必须唯一，且不可为 0 地址）
    function createUserAccount(address wallet) public onlyOwner {
        if (nextUserId > MAX_USERS) { revert MaxUsersReached(MAX_USERS, nextUserId); }
        if (wallet == address(0)) revert InvalidWallet(wallet);
        if (userIdByWallet[wallet] != 0) revert WalletExisted(wallet);

        uint256 newUserId = nextUserId;
        users[newUserId].id = newUserId;
        users[newUserId].balance = 0;
        users[newUserId].lastUpdated = block.timestamp;
        users[newUserId].wallet = wallet;
        users[newUserId].isBanned = false;
        // 建立 wallet → userId 的反向索引
        userIdByWallet[wallet] = newUserId;

        emit UserCreated(newUserId, wallet, users[newUserId].balance, users[newUserId].lastUpdated);
        unchecked { nextUserId = newUserId + 1; }
    }

    /// @notice 设置（覆盖）用户余额
    function setBalance(uint256 userId, uint256 amount) public onlyOwner {
        if (users[userId].wallet == address(0)) revert NotExist(userId);
        if (users[userId].isBanned) revert BannedUser(userId);

        users[userId].balance = amount;
        users[userId].lastUpdated = block.timestamp;

        emit BalanceUpdated(userId, users[userId].balance, users[userId].lastUpdated);
    }

    /// @notice 修改用户封禁状态
    /// @param status true 表示封禁，false 表示解封
    function changeStatus(uint256 userId, bool status) public onlyOwner {
        if (users[userId].wallet == address(0)) revert NotExist(userId);

        users[userId].isBanned = status;
        users[userId].lastUpdated = block.timestamp;

        emit UserStatusChanged(userId, users[userId].isBanned, users[userId].lastUpdated);
    }

    /// @notice 检查 wallet → userId → wallet 的映射不变式是否成立
    /// @dev 教学用函数，用于理解双向索引的一致性
    function checkIfWalletMappedCorrectly(address wallet) public view returns (bool) {
        uint256 id = userIdByWallet[wallet];
        return (id != 0 && users[id].wallet == wallet);
    }

    /// @notice 转移管理员权限
    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
```

UserManagerV1 存在以下可优化点：

- 结构体字段未打包，占用过多槽位
- 未使用 storage 指针，存在多次重复 SLOAD
- 逐字段赋值可能导致对同一 packed slot 多次 read-modify-write
- 事件参数从 storage 读取，增加额外 SLOAD

## 十一、UserManagerV2：存储优化版

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title UserManagerV2
/// @notice Gas 优化版（存储优化）
contract UserManagerV2 {
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
        uint64 ts = uint64(block.timestamp);

        if (newUserId > MAX_USERS) { revert MaxUsersReached(MAX_USERS, newUserId); }
        if (wallet == address(0)) revert InvalidWallet(wallet);
        if (userIdByWallet[wallet] != 0) revert WalletExisted(wallet);

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

        u.balance = amount;
        u.lastUpdated = uint64(block.timestamp);

        emit BalanceUpdated(userId, u.balance, u.lastUpdated);
    }

    function changeStatus(uint16 userId, bool status) public onlyOwner {
        User storage u = users[userId];

        if (u.wallet == address(0)) revert NotExist(userId);

        u.isBanned = status;
        u.lastUpdated = uint64(block.timestamp);

        emit UserStatusChanged(userId, u.isBanned, u.lastUpdated);
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

**V1 → V2 核心优化点**

| 优化项         | V1                        | V2                                    |
| -------------- | ------------------------- | ------------------------------------- |
| 结构体字段排列 | 未打包，每字段独占槽位    | id + wallet + lastUpdated + isBanned 打包 |
| 类型精简       | uint256 userId/timestamp  | uint16 userId, uint64 timestamp       |
| 存储指针       | 直接访问 users[userId]    | User storage u = users[userId]        |
| 结构体赋值     | 逐字段赋值                | 一次性 struct 赋值                    |
| 事件参数       | 从 storage 读取           | 使用局部变量                          |

在 EVM 层面，给同一 slot 不同字段赋值，编译器通常会做 read-modify-write：第一次把 slot 从 0 写成非零（昂贵 0→非零），之后每次再改同一 slot 都是非零→非零（仍要付 SSTORE 成本）。这正是"结构体打包"经常被忽略的副作用：打包省槽位，但如果写入方式不当，会导致对同一个槽位反复 SSTORE。

建议用一次性 struct 赋值，让编译器更容易生成每个 slot 一次 SSTORE。

## 小结

本篇介绍了存储优化的核心技巧：

- 变量打包和结构体打包可以减少槽位数量；
- constant 和 immutable 可以完全避免 SLOAD；
- 缓存存储变量可以减少重复读取；
- 瞬时存储可以大幅降低交易内锁的成本；
- 避免 0→非 0 写入可以节省 17,100 Gas；

通过 UserManagerV1 → UserManagerV2 的演示，我们看到了如何系统性地应用这些技巧。

下一篇我们将在 UserManagerV2 的基础上继续进行计算层面的优化，包括循环优化、短路求值、自定义错误等技巧，完成 UserManagerV3 的开发。



**系列导航：**

* 第一篇：[Gas 优化指南（一）：Gas 机制原理](./gas_optimization_guide_part1_gas_mechanism.md)
* 第二篇：[Gas 优化指南（二）：EIP-1559 交易解析](./gas_optimization_guide_part2_eip1559_transaction_analysis.md)
* 第三篇：Gas 优化指南（三）：存储优化（本篇）

* 第四篇：[Gas 优化指南（四）：计算优化](./gas_optimization_guide_part4_computation_optimization.md)
* 第五篇：[Gas 优化指南（五）：Gas 评估与测量](./gas_optimization_guide_part5_gas_measurement.md)
