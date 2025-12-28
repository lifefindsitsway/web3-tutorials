> 上一篇我们知道了 call 可以在不知道 ABI 的情况下调用合约。本篇深入讲解 call 的完整用法。

## call 的完整语法

```solidity
(bool success, bytes memory data) = targetAddress.call{
    value: 0.001 ether,  // 附带的 ETH（可选）
    gas: 100000          // 指定 gas 上限（可选）
}(
    calldata              // 要发送的数据
);
```

各部分含义：

| 部分 | 说明 |
|------|------|
| `targetAddress` | 目标合约地址 |
| `value` | 附带的 ETH，目标函数需要是 `payable` |
| `gas` | 转发的 gas 上限，不写则转发大部分剩余 gas |
| `calldata` | 函数选择器 + ABI 编码的参数 |
| `success` | 调用是否成功（目标没有 revert） |
| `data` | 目标函数的返回值（原始 bytes） |

**重要**：`call` 永远不会 revert。即使目标合约出错，也只是返回 `success = false`。你必须自己检查并处理失败情况。

## calldata 是什么？

当你调用 `token.transfer(to, amount)` 时，EVM 收到的不是函数名，而是一串字节：

```
0xa9059cbb                                                        ← 函数选择器（4 字节）
000000000000000000000000recipient_address_here                    ← 参数1: to
0000000000000000000000000000000000000000000000000000000000000064  ← 参数2: amount
```

这串字节就是 **calldata**，由两部分组成：

1. **函数选择器**（4 字节）：`bytes4(keccak256("transfer(address,uint256)"))`
2. **ABI 编码的参数**：按顺序编码的参数值

## 三种构造 calldata 的方式

### 1. abi.encodeWithSignature

用函数签名字符串构造：

```solidity
bytes memory data = abi.encodeWithSignature(
    "transfer(address,uint256)",  // 函数签名
    to,                           // 参数1
    amount                        // 参数2
);
```

**注意**：签名字符串中参数类型用逗号分隔，**不能有空格**，也**不包含返回值类型**。

### 2. abi.encodeWithSelector

用函数选择器构造：

```solidity
bytes memory data = abi.encodeWithSelector(
    IERC20.transfer.selector,  // 4 字节选择器
    to,
    amount
);
```

两者本质相同：

```solidity
abi.encodeWithSignature(sig, args...) 
≡ 
abi.encodeWithSelector(bytes4(keccak256(bytes(sig))), args...)
```

### 3. abi.encodeCall（推荐）

Solidity 0.8.11 引入，**类型安全**：

```solidity
bytes memory data = abi.encodeCall(
    IERC20.transfer,    // 函数指针，通常来自接口/合约名的函数成员
    (to, amount)        // 参数元组
);
```

**关键区别**：编译器会检查参数类型是否匹配函数定义。如果你传错类型，编译时就会报错。

### 三种方式对比

| 方式 | 类型检查 | 重构友好 | 推荐场景 |
|------|---------|---------|---------|
| `encodeWithSignature` | ❌ | ❌ | 快速调试、实验 |
| `encodeWithSelector` | ❌ | ❌ | 只有 selector 时 |
| `encodeCall` | ✅ | ✅ | **生产代码首选** |

为什么 `encodeCall` 更好？

```solidity
// 假设接口改了：transfer(address,uint256) → transfer(address,uint128)

// encodeWithSignature：编译通过，运行时静默失败
abi.encodeWithSignature("transfer(address,uint256)", to, amount);

// encodeCall：编译报错，立即发现问题
abi.encodeCall(IERC20.transfer, (to, amount));
```

## 处理返回值

`call` 返回的 `data` 是原始 bytes，需要用 `abi.decode` 解析：

```solidity
(bool success, bytes memory returnData) = token.call(data);
require(success, "Call failed");

bool result = abi.decode(returnData, (bool));
```

**实际开发中的坑**：有些非标准 ERC20 代币的 `transfer` 不返回值，但执行成功。直接 `abi.decode` 会失败。

兼容写法：

```solidity
function _parseBoolReturn(bool success, bytes memory returnData) internal pure returns (bool) {
    if (!success) return false;
    if (returnData.length == 0) return true;  // 兼容非标准 ERC20
    return abi.decode(returnData, (bool));
}
```

## 处理调用失败

`call` 返回 `success = false` 的情况：

- 目标函数 `revert`
- gas 不足
- 目标地址没有代码
- 其他执行错误

**注意**：调用一个不存在的函数，如果目标合约有 `fallback`，`success` 可能是 `true`！

正确的错误处理：

```solidity
(bool success, bytes memory returnData) = target.call(data);

if (!success) {
    if (returnData.length > 0) {
        // 转发 revert 原因
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    } else {
        revert("Call failed without reason");
    }
}
```

## 用 call 发送 ETH

除了调用函数，`call` 也是发送 ETH 的推荐方式：

```solidity
// 纯转账，不调用任何函数
(bool success, ) = recipient.call{value: 1 ether}("");
require(success, "Transfer failed");
```

为什么不用 `transfer` 或 `send`？因为它们有 2300 gas 限制，可能导致接收方的 `receive` 函数执行失败。

## 动手实验：TransferViaCall

下面这个合约完整演示了四种转账方式，可以部署后实际对比：

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IERC20.sol";

contract TransferViaCall {
    event LowLevelCall(bool success, bytes returnData);

    // 1）接口直接调用
    function transferViaInterface(address token, address recipient, uint256 amount) external returns (bool) {
        return IERC20(token).transfer(recipient, amount);
    }

    // 2）encodeWithSignature
    function transferViaSignature(address token, address recipient, uint256 amount) external returns (bool) {
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);
        (bool success, bytes memory returnData) = token.call(data);
        emit LowLevelCall(success, returnData);
        return _parseBoolReturn(success, returnData);
    }

    // 3）encodeWithSelector
    function transferViaSelector(address token, address recipient, uint256 amount) external returns (bool) {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount);
        (bool success, bytes memory returnData) = token.call(data);
        emit LowLevelCall(success, returnData);
        return _parseBoolReturn(success, returnData);
    }

    // 4）encodeCall（推荐）
    function transferViaEncodeCall(address token, address recipient, uint256 amount) external returns (bool) {
        bytes memory data = abi.encodeCall(IERC20.transfer, (recipient, amount));
        (bool success, bytes memory returnData) = token.call(data);
        emit LowLevelCall(success, returnData);
        return _parseBoolReturn(success, returnData);
    }

    /// @dev 兼容标准和非标准 ERC20
    function _parseBoolReturn(bool success, bytes memory returnData) internal pure returns (bool) {
        if (!success) return false;
        if (returnData.length == 0) return true;  // 非标准 ERC20
        return abi.decode(returnData, (bool));
    }
}
```

### 实验步骤

1. 部署一个 ERC20 代币合约（合约可参考：[IERC20.sol](./../../assets/codes/IERC20.sol)，[ERC20.sol](./../../assets/codes/ERC20.sol)）
2. 给自己 mint 一些代币
3. 向 `TransferViaCall` 合约转一些代币
4. 调用四个 transfer 函数，观察事件日志中的 `returnData`

### 观察结果

- **标准 ERC20**：`returnData` 是 32 字节，解码后为 `true`
- **非标准 ERC20**：`returnData` 可能为空（长度为 0），但 `success = true`

这就是为什么 `_parseBoolReturn` 要先检查长度——直接 decode 空数据会报错。

## 小结

本篇我们学习了：

1. `call` 的完整语法和各参数含义
2. calldata 的结构：选择器 + ABI 编码参数
3. 三种构造 calldata 的方式，推荐 `abi.encodeCall`
4. 如何正确处理返回值和调用失败
5. 通过 `TransferViaCall` 实验验证所学

下一篇，我们学习如何创建合约：`create` 和 `create2` 的区别，以及如何预测合约地址。



**系列导航**

- 第一篇：[四种方式调用已部署合约](./solidity_contract_call_part1_251221.md)
- 第二篇：底层调用与 calldata 详解（本篇）
- 第三篇：[创建合约的两种方式：create 与 create2](./solidity_contract_call_part3_251227.md)
