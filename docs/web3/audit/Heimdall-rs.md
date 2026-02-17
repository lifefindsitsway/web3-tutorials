# Claude Code + Heimdall-rs 深度逆向 EVM 智能合约

> 在 DeFi 的"黑暗森林"中，你经常会遇到这样的场景：一个管理着数百万美元资金的合约，在 Etherscan 上却只能看到一堆不可读的十六进制字节码——没有源码，没有 ABI，没有文档。它是安全的金库，还是精心伪装的 Rug Pull？字节码是你唯一的线索。Heimdall-rs 正是为这类场景而生的武器，本文将完整介绍这款工具的安装、使用，并通过一个实战案例展示如何配合 Claude Code 对未开源合约进行黑盒审计。

Heimdall-rs 是一款使用 Rust 编写的高性能 EVM 智能合约分析工具包，专注于**字节码分析**与**逆向工程**。它可以将不可读的字节码还原为可理解的伪代码、操作码序列和可视化控制流图，目前支持六大核心操作：

- 字节码反汇编（Disassemble）
- 控制流图生成（CFG）
- 智能合约反编译（Decompile）
- 合约存储导出（Dump）
- 交易 Calldata 解码（Decode）
- 交易 Trace 解码（Inspect）

截至撰写本文时，最新版本为 v0.9.2。建议通过 `bifrost` 定期检查并安装最新版本以获得最佳的反编译效果。

Github 仓库：https://github.com/Jon-Becker/heimdall-rs/

## 安装指南

Heimdall-rs 通过其专用的安装管理器 **bifrost** 来安装和更新。下面分别介绍官方标准流程和针对国内网络环境（WSL2 + 代理）的实战流程。

**前置条件：安装 Rust 与 Cargo**

如果你的系统尚未安装 Rust 工具链，请先执行以下命令：

```bash
curl https://sh.rustup.rs -sSf | sh
```

安装完成后，运行 `source ~/.cargo/env` 或新开一个终端以激活环境变量。

### 方式一：官方标准安装

在网络畅通的环境下，按照官方文档两步即可完成安装：

```bash
# 第一步：安装 bifrost（Heimdall 的安装/更新管理器）
curl -L http://get.heimdall.rs | bash

# 第二步：新开终端，运行 bifrost 安装 Heimdall 核心程序
bifrost
```

安装完成后，新开终端即可使用 `heimdall` 命令。

### 方式二：WSL2 Ubuntu 24.04 + v2rayN 代理安装（推荐国内用户）

在 WSL2 环境下，`get.heimdall.rs` 会重定向到 GitHub / Google Storage，直接执行会遇到**网络屏蔽**和**缺少依赖**的问题。以下是经过验证的完整安装流程。

**第一步：安装系统底层依赖**

```bash
sudo apt update
sudo apt install build-essential pkg-config libssl-dev -y
```

**第二步：配置代理并安装 bifrost**

WSL2 在网络层被视为局域网设备，因此需要通过 Windows 主机的代理来访问外网。请确保 v2rayN 已开启 **"允许来自局域网的连接（Allow LAN）"** 选项。

```bash
# 动态获取 WSL2 的网关地址（即 Windows 主机 IP）
export hostip=$(ip route | grep default | awk '{print $3}')
export proxy_port=10809  # v2rayN 默认 HTTP 代理端口，根据实际情况修改
export http_proxy="http://${hostip}:${proxy_port}"
export https_proxy="http://${hostip}:${proxy_port}"

# 执行 bifrost 安装脚本
curl -L http://get.heimdall.rs | bash
```

**第三步：激活环境变量并安装 Heimdall**

bifrost 安装完成后会自动将自身添加到 `~/.bashrc`。你需要刷新环境，然后运行 bifrost 来真正安装 Heimdall 核心程序：

```bash
# 刷新当前终端的环境变量
source ~/.bashrc

# 运行 bifrost 安装 heimdall 核心程序
# 注意：这一步 bifrost 会下载 heimdall 二进制文件，同样需要保持代理开启
bifrost
```

**第四步：验证安装**

安装完成后，新开一个终端或再次 `source ~/.bashrc`，验证版本：

```bash
heimdall --version
# 预期输出：heimdall 0.9.x 或更新版本
```

### bifrost 进阶用法

bifrost 不仅用于首次安装，还是 Heimdall 的版本管理器：

```bash
# 查看所有可用版本
bifrost -l

# 安装指定版本
bifrost -v 0.9.2

# 安装开发分支（用于测试新功能）
bifrost -v feat/decompile
```

## 主要功能模块

Heimdall-rs 采用模块化设计，每个功能对应一个子命令。所有模块共享以下通用选项：

```plain
-v          提高输出详细程度（可叠加使用，如 -vvv 表示最详细）
-q          静默模式，隐藏所有输出
-r <URL>    指定 RPC 节点地址（支持所有 EVM 兼容链）
-o <PATH>   指定输出文件或目录
```

### 1. 反编译 — `heimdall decompile`

这是 Heimdall 最核心也最强大的功能。它能将 EVM 字节码转换成高度可读的伪代码（类似 Solidity 的风格），即使在没有 ABI 的情况下也能高度还原合约逻辑。

**核心能力：** 自动识别函数选择器和签名、解析控制流（If/Else、循环）、推断变量类型和存储布局、生成对应的 ABI 文件。

```bash
# 通过链上合约地址反编译（需要 RPC）
heimdall decompile <CONTRACT_ADDRESS> -r <RPC_URL> -vvv

# 通过本地字节码反编译
heimdall decompile <BYTECODE_HEX>
```

**典型场景：** 分析黑客攻击后的恶意合约、审查未开源的第三方协议、探索闭源交易机器人的策略逻辑。

### 2. 反汇编 — `heimdall disassemble`

将字节码转换成底层 EVM 操作码（Opcodes）序列，如 `PUSH1`、`SSTORE`、`DELEGATECALL` 等。相比于简单的反汇编工具，Heimdall 提供了更好的格式化输出，方便分析底层执行流程。

```bash
heimdall disassemble <CONTRACT_ADDRESS> -r <RPC_URL>
```

**典型场景：** 理解合约的底层执行逻辑、辅助手动安全审计、学习 EVM 操作码。

### 3. 控制流图 — `heimdall cfg`

生成合约逻辑的可视化控制流图（Control Flow Graph），输出为 Graphviz 的 `.dot` 文件，也可以通过 `--format` 参数转换为 SVG 或 PNG 等格式。

```bash
# 生成 .dot 文件
heimdall cfg <CONTRACT_ADDRESS> -r <RPC_URL> -vvv

# 直接生成 SVG 文件（方便在浏览器中查看）
heimdall cfg <CONTRACT_ADDRESS> -r <RPC_URL> -vvv --format svg
```

**典型场景：** 通过图形化方式一眼识别异常的逻辑分支或隐藏后门、辅助安全审计人员理解合约跳转逻辑（JUMP/JUMPI）。

### 4. 交易解码 — `heimdall decode`

解码交易的 Calldata（输入数据）。当你有一串未知的交易数据时，它能帮你解析出调用的函数及其参数，无需提供 ABI。该模块使用 samczsun 的函数签名库来匹配和解码函数选择器。

```bash
# 通过交易哈希解码
heimdall decode <TX_HASH> -r <RPC_URL>

# 解码原始 calldata
heimdall decode <RAW_CALLDATA_HEX> -r <RPC_URL>

# 解码合约构造函数参数
heimdall decode <CONTRACT_CREATION_CODE> --constructor -r <RPC_URL>
```

**典型场景：** 分析可疑交易的具体行为、理解复杂协议（如 Seaport）的交互参数、调试合约调用。

### 5. 存储导出 — `heimdall dump`

导出指定合约在特定区块范围内的所有存储槽（Storage Slots）及其值，输出为 CSV 文件。

```bash
heimdall dump <CONTRACT_ADDRESS> -vvv \
  --threads 20 \
  --from-block 15000000 \
  --to-block 15000100
```

**典型场景：** 追踪合约状态变量的变化、分析代币余额变动、检查所有者权限变更记录。

### 6. 交易检查 — `heimdall inspect`

对以太坊交易进行详细检查，包括 Calldata 与 Trace 解码、日志可视化等。这是一个综合性的交易分析工具。

```bash
heimdall inspect <TRANSACTION_HASH> -r <RPC_URL>
```

**典型场景：** 对安全事件中的攻击交易进行全面分析、追踪资金流向和内部调用链。

## 实战演示：逆向分析一个 ETH 金库合约

为了完整展示 Heimdall-rs 的六大功能模块在真实场景中的表现，我编写了一个教学用途的 SimpleVault 合约并将其部署到 Sepolia 测试网。这个合约**不做源码验证**，模拟你在链上遇到的"黑盒"场景——你只能看到字节码，需要完全依赖 Heimdall-rs 来理解它在做什么。

### 演示合约设计

合约的核心功能是一个 ETH 金库，支持存款、提款、批量转账和暂停控制。选择这些功能的原因是它们能覆盖 Heimdall 的所有分析维度：

- 多种状态变量类型（address、mapping、uint256、bool）用于演示存储导出；
- 多种函数可见性和修饰符用于演示反编译推断；
- 分支逻辑与循环结构用于演示控制流图；
- ETH 转账和事件触发用于演示交易 Trace 解码；
- 动态数组参数用于演示 Calldata 解码。

合约完整源码见下方折叠区域，你也可以直接跳到后续的分析结果部分。演示合约使用 Solidity 0.8.28 编译，Heimdall 对高版本 Solidity 引入的自定义 `Error` 类型和 `Panic` 错误码均有良好的反编译支持。

<details>
<summary>📄 SimpleVault 完整源码（点击展开）</summary>

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SimpleVault - Heimdall-rs 功能演示合约
 * @author Lifefindsitsway
 * 
 * 设计思路：
 *   - 多种状态变量类型（address, mapping, uint256, bool）→ 演示 Dump 存储导出
 *   - 多种函数可见性和修饰符（external, public, view, payable）→ 演示 Decompile 修饰符推断
 *   - 分支逻辑与权限检查（require, if/else）→ 演示 CFG 控制流图 & Disassemble 操作码
 *   - ETH 转账 + 事件触发 → 演示 Inspect 交易 Trace 解码
 *   - 多样化的函数参数类型（uint256, address, 动态数组）→ 演示 Decode Calldata 解码
 */
contract SimpleVault {
    // ============================================================
    //                       状态变量
    // 这些变量会被写入链上的 Storage Slots，用于演示 heimdall dump
    // ============================================================

    address public owner;           // 合约所有者地址（slot 0）
    bool public isActive;           // 金库是否处于激活状态（slot 1）
    uint256 public totalDeposits;   // 累计存款总额（slot 2）
    mapping(address => uint256) public balances;    // 每个地址的存款余额（slot 3 起，mapping 使用 keccak256 计算实际存储位置）

    // ============================================================
    //                         事件
    // Heimdall decompile 会自动识别和还原事件声明
    // Heimdall inspect 会可视化交易中触发的事件日志
    // ============================================================

    event Deposited(address indexed user, uint256 amount);      // 存款事件：记录谁存了多少 ETH
    event Withdrawn(address indexed user, uint256 amount);      // 提款事件：记录谁取了多少 ETH
    event BatchTransferred(address indexed from, uint256 count);// 批量转账事件：记录发起者和总转账笔数
    event VaultToggled(bool newState);                          // 金库状态切换事件

    // ============================================================
    //                        修饰符
    // require 检查会在字节码中生成 JUMPI 分支，丰富 CFG 图结构
    // ============================================================

    /// @notice 仅允许合约所有者调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    /// @notice 仅在金库激活时允许操作
    modifier whenActive() {
        require(isActive, "Vault is paused");
        _;
    }

    // ============================================================
    //                       构造函数
    // 构造函数中初始化状态变量，确保部署后 Storage 中就有非零数据
    // 这样即使不做任何交互，heimdall dump 也能导出有意义的内容
    // ============================================================

    constructor() {
        owner = msg.sender;     // slot 0: 部署者地址
        isActive = true;        // slot 1: 默认激活
        totalDeposits = 0;      // slot 2: 初始为 0（显式赋值便于教学理解）
    }

    /**
     * @notice 存款函数 - 将 ETH 存入金库
     * @dev payable 修饰符允许接收 ETH；Heimdall decompile 会推断出 payable 属性
     *
     * 演示重点：
     *   - Decode: 虽然无参数，但 msg.value 会体现在交易的 value 字段中
     *   - Dump:   调用后 balances mapping 和 totalDeposits 会被更新
     *   - Inspect: 会触发 Deposited 事件，Trace 中可见日志
     */
    function deposit() external payable whenActive {
        // 这个分支在 CFG 中会生成一个 JUMPI 节点
        require(msg.value > 0, "Must send ETH");
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice 提款函数 - 从金库中取出指定金额的 ETH
     * @param amount 要提取的 ETH 数量（单位：wei）
     *
     * 演示重点（这是演示效果最丰富的函数，建议用它的交易哈希来测试 Decode 和 Inspect）：
     *   - Decode:   参数类型为 uint256，解码后可以看到具体的提款金额
     *   - Inspect:  包含 ETH 转账（CALL 操作）+ 事件日志，Trace 内容最丰富
     *   - CFG:      多个 require 检查形成多层分支结构
     */
    function withdraw(uint256 amount) external whenActive {
        require(amount > 0, "Amount must be > 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        totalDeposits -= amount;

        // 这一步会在 Trace 中产生一个 CALL 操作，是 Inspect 的核心看点
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice 批量转账函数 - 向多个地址分发金库中的 ETH
     * @param recipients 接收者地址数组
     * @param amounts    对应的转账金额数组
     *
     * 演示重点：
     *   - Decode:   动态数组参数（address[], uint256[]）的 ABI 编码较为复杂，
     *               能充分展示 Heimdall 解码动态类型的能力
     *   - CFG:      for 循环在字节码层面表现为 JUMP 回跳，会在 CFG 中形成环路结构
     *   - Inspect:  多次 CALL + 多次事件触发，Trace 会很丰富
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner whenActive {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty arrays");

        // 字节码中的循环结构：JUMPDEST → 条件检查 → JUMPI → 循环体 → JUMP 回跳
        for (uint256 i = 0; i < recipients.length; i++) {
            require(amounts[i] > 0, "Zero amount");
            require(recipients[i] != address(0), "Zero address");

            // 从合约余额中直接转账（不是从 sender 的 balances 中扣）
            (bool success, ) = payable(recipients[i]).call{value: amounts[i]}("");
            require(success, "Transfer failed");
        }

        emit BatchTransferred(msg.sender, recipients.length);
    }

    // ============================================================
    //                       查询函数
    // view 函数不修改状态，Heimdall decompile 会推断出 view 属性
    // ============================================================

    /**
     * @notice 查询指定地址的存款余额
     * @param user 要查询的地址
     * @return 该地址在金库中的余额（wei）
     * 
     * 演示重点：
     *   - Decompile: Heimdall 会推断此函数为 view（因为没有 SSTORE 操作码）
     *   - Decode:    参数类型为 address，解码后可以看到被查询的地址
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice 查询合约自身持有的 ETH 总量
     * @return 合约地址的 ETH 余额（wei）
     * 
     * 演示重点：
     *   - Decompile: 使用了 address(this).balance，反编译后可以看到 SELFBALANCE 操作码的还原
     */
    function getVaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ============================================================
    //                       管理函数
    // ============================================================

    /**
     * @notice 切换金库的激活/暂停状态
     *
     * 演示重点：
     *   - CFG:       简单的状态翻转逻辑，在 CFG 中是一个清晰的线性路径
     *   - Dump:      调用后 isActive (slot 1) 的值会从 true 变为 false 或反之
     *   - Decompile: onlyOwner 修饰符的 require 检查会被还原
     */
    function toggleActive() external onlyOwner {
        isActive = !isActive;
        emit VaultToggled(isActive);
    }

    /**
     * @notice 允许合约接收 ETH（不通过 deposit 函数直接转账时触发）
     * @dev receive 函数在字节码中会生成独立的分发路径，
     *      CFG 中可以看到 calldata size == 0 时的跳转分支
     */
    receive() external payable {
        balances[msg.sender] += msg.value;  // 直接转入的 ETH 也计入发送者的余额
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}

```

</details>

**部署信息：**

- 网络：Sepolia Testnet（Chain ID: 11155111）
- 合约地址：`0x411885324AFd60404252213106C006E6Fff84C79`
- 免费公共 RPC：`https://ethereum-sepolia-rpc.publicnode.com`

> 💡 本次分析使用 Claude Code 通过 MCP（Model Context Protocol）集成 Heimdall-rs，AI Agent 并非简单地搜索或转述信息，而是通过 `foundry_mcp_server` **实时调用** Heimdall 的各个子命令，读取生成的反编译文件和控制流图，再对输出结果进行逻辑推演和交叉验证。整个模块分析流程由一条 Prompt 指令驱动。完整的 Prompt 模板和生成的所有分析文件见 附录。

### 分析结果一：反编译（Decompile）— 还原函数接口

Heimdall 在完全没有 ABI 的情况下，从纯字节码中成功还原出了合约的全部 10 个函数签名。下表是反编译输出的函数接口汇总：

| 函数 | 选择器 | 功能说明 |
|---|---|---|
| `owner()` | — | 查询合约所有者 |
| `isActive()` | — | 查询金库是否处于激活状态 |
| `totalDeposits()` | — | 查询总存款量 |
| `deposit()` | `0xd0e30db0` | 存入 ETH |
| `withdraw(uint256)` | `0x2e1a7d4d` | 提取指定数量的 ETH |
| `getBalance(address)` | `0xf8b2cb4f` | 查询某地址的存款余额 |
| `balances(address)` | `0x27e235e3` | 查询余额映射 |
| `getVaultBalance()` | `0xed12e8ef` | 查询合约持有的 ETH 总量 |
| `toggleActive()` | `0x29c68dc1` | 切换金库激活/暂停状态（仅 owner） |
| `batchTransfer(address[],uint256[])` | `0x88d695b2` | 批量转账（仅 owner） |

反编译同时还原出了两个事件：`BatchTransferred(address, uint256)` 在批量转账完成时触发，另一个匿名事件 `Event_381234db()` 在 `toggleActive` 切换状态时触发。值得注意的是，后者在原始源码中是 `VaultToggled(bool newState)`，Heimdall 无法从字节码中完整还原事件名称（因为事件名在编译后只保留 keccak256 哈希值），但它正确识别了事件的触发位置和参数结构。

反编译还准确还原了合约的核心业务逻辑。以 `deposit()` 为例，还原出的伪代码包含了完整的检查链：先验证金库处于激活状态（`require(isActive == true)`），再检查 `msg.value > 0`，然后执行 `balances[msg.sender] += msg.value` 和 `totalDeposits += msg.value`，溢出保护也被正确识别。这与原始 Solidity 源码几乎完全一致。

### 分析结果二：反汇编（Disassemble）— 操作码安全扫描

反汇编输出了完整的 EVM 操作码序列。在安全审计场景中，我们最关心的是是否存在高风险操作码。以下是关键操作码的统计结果：

| 操作码 | 出现次数 | 安全意义 |
|---|---|---|
| `CALL` | 2 次 | `withdraw` 和 `batchTransfer` 各一处 ETH 转账，属于正常业务逻辑 |
| `SSTORE` | 7 次 | 状态写入（余额更新、totalDeposits、isActive 等） |
| `LOG2` / `LOG1` | 5 / 1 次 | 事件记录，无安全风险 |
| `DELEGATECALL` | **0 次** | ✅ 不存在代理模式的逻辑篡改风险 |
| `SELFDESTRUCT` | **0 次** | ✅ 合约不可被销毁 |
| `CALLCODE` | **0 次** | ✅ 不存在已废弃的危险调用方式 |
| `CREATE` | 1 次 | 出现在合约末尾，属于构造函数的部署码部分，非运行时风险 |

这份操作码扫描的价值在于：在没有源码的情况下，你可以在几秒钟内确认一个合约是否包含 `DELEGATECALL`（代理合约风险）、`SELFDESTRUCT`（合约可被销毁）或 `CALLCODE`（已废弃的危险调用）等高风险指令，快速建立对合约安全性的初步判断。

### 分析结果三：控制流图（CFG）— 可视化逻辑结构

Heimdall 生成的控制流图（`.dot` 格式）清晰展示了合约的执行路径：

- **入口节点**：首先检查 `CALLVALUE != 0`，如果携带 ETH 但调用的不是 payable 函数则直接 REVERT
- **路由节点**：检查 `CALLDATASIZE >= 4` 后读取函数选择器，通过一系列比较跳转到对应的函数实现
- **函数内部**：每个函数都有多重 `require` 检查形成级联的条件分支，而 `batchTransfer` 中的 `for` 循环在 CFG 中表现为明显的回跳环路结构

CFG 对安全审计的价值在于图形化呈现——你可以一眼看出是否存在异常的跳转路径或隐藏的后门分支，而不需要逐行阅读操作码。

### 分析结果四：存储导出（Dump）— 读取链上状态

通过 `dump` 配合 `cast`（Foundry 工具）读取存储槽，还原出了合约的完整存储布局和当前状态：

| 存储槽 | 变量 | 当前值 | 含义 |
|---|---|---|---|
| Slot 0 | `owner` + `isActive` | `0x1d477b...7AA0` / `true` | owner 和 isActive **打包在同一个 slot** 中 |
| Slot 1 | `totalDeposits` | 0.03597 ETH | 历史累计存入总额 |
| Slot 2 | `balances` | mapping | 每个用户的存款余额映射 |

这里有一个值得关注的细节：`owner`（address 类型，占 20 字节）和 `isActive`（bool 类型，占 1 字节）被 Solidity 编译器**打包到同一个 32 字节的存储槽**中，这是 Solidity 的紧凑存储优化（Storage Packing）。通过 `cast storage` 读取 Slot 0 的原始数据，你会看到一串 32 字节的 Hex 值：

```
0x0000000000000000000000011d477b7733fe1347ee91e8d15f8c7f203e147aa0
```

Heimdall 正确地将这串数据拆解为两个独立变量：低 160 位（20 字节）是 `owner` 地址 `0x1d477b...7AA0`，紧邻其上的 1 字节 `01` 则是 `isActive = true`。在源码中，这两个变量分别声明为 `address public owner` 和 `bool public isActive`，Solidity 编译器发现它们的总大小（20 + 1 = 21 字节）不超过 32 字节，于是自动将它们打包进同一个 slot 以节省 gas。能从纯字节码中正确还原这种打包行为，体现了 Heimdall 反编译引擎对 EVM 存储模型的深度理解。

另一个有趣的发现是数据不一致：`totalDeposits` 显示累计存款为 0.03597 ETH，但通过 `getVaultBalance()` 查询合约实际余额只有 0.006 ETH，差额约 0.03 ETH。这说明已有资金被提走或转出——在真实审计场景中，这种差异往往是进一步调查的起点。

### 分析结果五：交易解码（Decode）— 解析 batchTransfer 调用

使用 `decode` 解析交易 `0x63bd2f2e...` 的 Calldata，Heimdall 成功还原了完整的函数调用信息：

- **函数**：`batchTransfer(address[], uint256[])`
- **参数 addresses**：[`0x1d477b...`（owner 本人）, `0x84B62e...`]
- **参数 amounts**：[0.02 ETH, 0.01 ETH]

将解码结果与反编译代码进行对比验证：该交易由 owner 发起（通过 `require(msg.sender == owner)` 检查）、金库处于激活状态（通过 `require(isActive)` 检查）、两个数组长度一致（通过长度匹配检查）、地址均非零且金额均大于 0（通过循环内检查）。所有条件均满足，交易成功执行并触发了 `BatchTransferred(owner, 2)` 事件。

这个例子很好地展示了 `decode` 的价值：面对一串不可读的十六进制 Calldata，Heimdall 无需 ABI 就能解析出完整的函数名和参数——对于动态数组这类复杂的 ABI 编码格式尤其有用。

### 分析结果六：交易检查（Inspect）— 追踪 withdraw 内部调用

使用 `inspect` 追踪交易 `0xa66c471b...`，还原了一笔 `withdraw(0.004 ETH)` 的完整执行过程：

- 发送者 `0x1d477b...`（owner）调用 `withdraw(4000000000000000)`
- 合约先执行 `SSTORE` 更新 `balances` 映射（减少 0.004 ETH）
- 然后执行 `CALL` 向调用者发送 0.004 ETH
- 最后触发 Withdrawal 事件，LOG2 日志中记录了提款者地址和金额

`inspect` 的核心价值在于**可视化内部调用流**。在这笔交易中，我们可以清楚地看到合约采用了 **Checks-Effects-Interactions（CEI）模式**——先更新状态（SSTORE），再执行外部调用（CALL）。这一顺序对防范重入攻击至关重要，而通过 `inspect` 可以在不读源码的情况下直接从交易 Trace 中确认这一点。

### 安全发现总结

综合六个模块的分析结果，可以对这个未开源合约形成完整的安全评估：

**合理的安全设计：** 合约不含 `DELEGATECALL`/`SELFDESTRUCT`/`CALLCODE` 等高风险操作码；`withdraw` 函数遵循 CEI 模式，降低了重入风险；`toggleActive` 和 `batchTransfer` 均有 owner 权限校验；`deposit` 中对余额累加进行了溢出保护。

> **⚠️ 高危发现：`batchTransfer` 存在资金挪用风险**
>
> 从反编译代码中可以看出，`batchTransfer` 直接从合约余额中转出 ETH，**没有对应减少任何用户的 `balances` mapping**。这意味着 owner 可以绕过用户余额限制，将金库中**所有用户**的存款全部转走，而链上的 `balances` 记录不会反映这笔支出。
>
> 更进一步，owner 还可以通过 `toggleActive()` 暂停金库，阻止所有用户提款，然后再通过 `batchTransfer` 将剩余资金全部转出——这构成了一个完整的 Rug Pull 路径。整个过程中，没有多签、时间锁或治理机制能够阻止这一操作。**这是此合约最大的安全隐患。**

这个发现完全来自对字节码的逆向分析，体现了 Heimdall-rs 在实战安全审计中的核心价值：即使面对完全未开源的合约，你也能通过反编译和交易验证发现潜在的设计缺陷。

## 使用场景

**安全审计：** 在没有源码的情况下，通过反编译和 CFG 检查第三方协议的安全性。这在评估新 DeFi 协议的风险时尤为有用。

**攻击分析：** 当链上发生安全事故时，可以快速反编译攻击合约、解码攻击交易的 Calldata，理解黑客的完整攻击路径。

**逆向工程：** 探索闭源项目（如 MEV 机器人的策略合约）的实现逻辑。

**漏洞赏金：** 在 Bug Bounty 项目中，对那些未公开源码的合约进行深度分析，寻找潜在漏洞。

## 技术优势

**Rust 驱动的极速性能：** 在处理复杂的递归分析和大规模字节码时，速度远超 Python 或 JavaScript 编写的同类工具（如 Panoramix）。

**符号执行与启发式算法：** 结合符号执行和先进的启发式算法来推断函数名称和逻辑，即使在没有 ABI 的情况下也能高度还原合约意图。

**灵活的输入方式：** 支持直接从以太坊节点（通过 RPC URL）拉取合约代码，也支持本地字节码文件或原始十六进制输入。此外支持 MESC 标准进行 RPC 端点统一配置。

**学术认可：** Heimdall-rs 已被多篇学术论文和硕士论文引用，在智能合约分析领域具有广泛的学术影响力。

## 附录

### A. AI Agent 分析 Prompt 模板

以下是本次实战演示中使用的完整 Prompt，通过 MCP 协议集成 Foundry MCP Server 的 Heimdall-rs 工具集，让 AI Agent 自动化执行全部六个分析模块并生成结构化报告。你可以根据自己的目标合约和 RPC 地址进行修改后直接使用：

> 我需要对 Sepolia 上的未验证合约 `0x411885324afd60404252213106c006e6fff84c79` 进行深度逆向分析。请使用 `foundry_mcp_server` 提供的 **Heimdall-rs** 工具集，按以下步骤执行并汇总报告：
>
> **1. 静态结构分析：** 执行 `decompile` 还原逻辑，并生成 `cfg` 控制流图（请描述图中的主要逻辑分支）。
>
> **2. 底层指令查看：** 执行 `disassemble` 观察关键的操作码分布，特别关注是否存在 `delegatecall` 或 `selfdestruct` 等敏感指令。
>
> **3. 存储布局导出：** 执行 `dump` 导出当前的存储槽，重点分析 Slot 0 (`owner`) 和 Slot 1 (`isActive`) 的当前值及其含义。
>
> **4. 交易行为解码：**
>
> - 使用 `decode` 解析这笔交易的输入参数：`0x63bd2f2e19ad89eeeac17fba2a49b28a63aaf0e8b09e369a645699212d256073`，请说明这笔交易调用了哪个函数，传入了什么参数。
> - 使用 `inspect` 追踪这笔提款交易的内部调用流：`0xa66c471b820f80f8ec60424d88a6b7145a0aef4fd8e0db31ea996ed652efbbe1`，请详细解释其中的内部调用流。
>
> 请将 `decode` 得到的参数与 `decompile` 还原出的逻辑进行对比，确认该笔交易是否触发了代码中的预期分支，并解释 `inspect` 追踪到的内部调用与代码逻辑是否一致。
>
> 请在分析完成后，用中文提交一份结构清晰的报告，涵盖：核心业务逻辑、是否存在潜在风险，以及你对各模块分析结果的解读。
>
> RPC URL 请使用：`https://eth-sepolia.g.alchemy.com/v2/<YOUR_API_KEY>`
>
> **注意：** 如果生成了反编译的源文件或控制流图文件，请务必读取文件内容并结合代码进行深度解读，不要只报告"文件已生成"。

### B. 生成的分析文件

| 文件 | 说明 |
|---|---|
| `decompiled.sol` | 反编译还原的 Solidity 伪代码 |
| `abi.json` | 自动还原的 ABI 接口定义 |
| `cfg.dot` | 控制流图（Graphviz DOT 格式） |
| `disassembled.asm` | 完整的反汇编操作码序列 |
| `reverse-engineering-report.md` | AI Agent 生成的完整逆向分析报告 |

所有文件的完整内容可在此查看：[Github 仓库目录](https://github.com/lifefindsitsway/web3-tutorials/tree/main/docs/assets/codes/0x411885324afd60404252213106c006e6fff84c79/)

### C. 参考资料

- [Heimdall-rs GitHub 仓库](https://github.com/Jon-Becker/heimdall-rs/) — 源码、文档与 Issue 跟踪
- [Foundry Book](https://book.getfoundry.sh/) — Foundry 工具链官方文档（含 `cast storage` 等命令的详细用法）
- [Foundry MCP Server](https://github.com/PraneshASP/foundry-mcp-server) — 本文使用的 MCP 集成方案，将 Foundry + Heimdall 工具暴露给 AI Agent
- [samczsun 函数签名数据库](https://openchain.xyz/signatures) — Heimdall decode 模块使用的函数签名匹配源
