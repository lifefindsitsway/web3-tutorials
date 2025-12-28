> 当你的合约需要和链上其他合约交互时，该怎么做？本篇介绍最常用的四种方式。

## 前置知识：receive 和 fallback

在讲调用之前，先认识两个特殊函数。它们是合约的"后门入口"，在接收 ETH 和处理合约中不存在的函数调用时非常重要。

### receive：专门接收 ETH

当合约收到**纯 ETH 转账**（没有附带任何数据）时，`receive` 会被触发。

```solidity
receive() external payable {
    // 处理收到的 ETH
}
```

语法特点：没有 `function` 关键字，没有参数，没有返回值，必须是 `external payable`。

### fallback：兜底函数

当调用合约时，如果找不到匹配的函数，就会触发 `fallback`。

```solidity
// 基础形式
fallback() external payable {}

// 带参数形式（可以访问 calldata 并返回数据）
fallback(bytes calldata input) external payable returns (bytes memory) {
    return abi.encode(input.length);
}
```

### 触发逻辑

```
                     调用合约
                        │
                        ▼
                 msg.data 是否为空？
                   /         \
                 是            否
                /               \
              ▼                  ▼
        receive 存在？      函数签名匹配？
          /     \            /       \
        是       否        是         否
        /         \        /           \
    receive    fallback  执行函数    fallback
```

简单记忆：**纯转账走 receive，其他兜底走 fallback**。

## 调用已部署合约需要什么？

两样东西：**合约地址** + **调用接口**。

接口告诉编译器：这个地址上的合约有哪些函数可以调用。

```solidity
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    // ...其他函数
}
```

有了接口，就可以开始调用了。

### 方式一：通过接口调用（推荐）

这是最常用、最推荐的方式，类型安全，代码清晰。

```solidity
import "./IERC20.sol";

contract MyContract {
    function getBalance(address token, address account) public view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }
}
```

核心语法：`IERC20(token)` 把地址"包装"成接口类型，然后就能像调用本地函数一样调用它。

### 方式二：通过合约类型调用

如果你有目标合约的完整代码，可以直接用合约类型。

```solidity
import "./ERC20.sol";

contract MyContract {
    function getBalance(address token, address account) public view returns (uint256) {
        return ERC20(token).balanceOf(account);
    }
}
```

本质上和接口调用一样——都是告诉编译器"这个地址有哪些函数"。

**区别**：接口只声明函数签名，合约类型包含完整实现。如果只需要调用，用接口更轻量。

### 方式三：存储合约引用

当你需要多次调用同一个合约时，可以把引用存为状态变量。

```solidity
import "./IERC20.sol";

contract MyContract {
    IERC20 public token;  // 存储合约引用

    constructor(address _token) {
        token = IERC20(_token);
    }

    function getBalance(address account) public view returns (uint256) {
        return token.balanceOf(account);
    }

    function doTransfer(address to, uint256 amount) public {
        token.transfer(to, amount);
    }
}
```

好处：代码更简洁，不用每次都传地址。

### 方式四：使用 call 调用

当你**不知道目标合约的接口**时，可以用底层的 `call`。

```solidity
contract MyContract {
    function getBalance(address token, address account) public returns (uint256) {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        require(success, "Call failed");
        return abi.decode(data, (uint256));
    }
}
```

`call` 是 `address` 类型的底层方法，特点是：

- 需要自己构造 calldata
- 需要自己检查 success
- 需要自己解析返回值

**什么时候用 call？**

- 目标合约的 ABI 未知
- 需要更灵活的控制（如指定 gas、附带 ETH）

一般情况下，**优先用接口调用**，更安全更清晰。

### 四种方式对比

| 方式 | 需要接口/合约代码 | 类型安全 | 使用场景 |
|------|------------------|---------|---------|
| 接口调用 | 需要接口 | ✅ | 日常开发首选 |
| 合约类型调用 | 需要完整代码 | ✅ | 有源码时可用 |
| 存储引用 | 需要接口 | ✅ | 频繁调用同一合约 |
| call 调用 | 不需要 | ❌ | ABI 未知或需要底层控制 |

## 小结

本篇我们学习了：

1. `receive` 和 `fallback` 的触发逻辑
2. 四种调用已部署合约的方式
3. 日常开发推荐使用接口调用

下一篇，我们深入 `call` 的底层细节：如何构造 calldata、三种 ABI 编码方式的区别，以及如何正确处理返回值。



**系列导航**

- 第一篇：四种方式调用已部署合约（本篇）
- 第二篇：[底层调用与 calldata 详解](./solidity_contract_call_part2_251223.md)
- 第三篇：[创建合约的两种方式：create 与 create2](./solidity_contract_call_part3_251227.md)

