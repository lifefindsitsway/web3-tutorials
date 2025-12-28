> 前两篇讲了如何调用合约，本篇讲如何在合约中创建新合约。

## 两种创建方式

EVM 提供两个操作码来创建合约：

| 操作码 | 地址计算方式 | 特点 |
|--------|-------------|------|
| `CREATE` | 部署者地址 + nonce | 地址不可预测 |
| `CREATE2` | 部署者地址 + salt + initcode | 地址可预测 |

## CREATE：基础创建

语法很简单，就是 `new` 一个合约：

```solidity
Contract x = new Contract{value: _value}(params);
```

- `Contract`：要创建的合约名
- `x`：返回的合约实例（本质是地址）
- `value`：附带的 ETH（构造函数需要是 `payable`）
- `params`：构造函数参数

### 示例：简易 Pair 工厂

```solidity
// Pair.sol
contract Pair {
    address public factory;
    address public token0;
    address public token1;

    constructor() {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }
}
```

```solidity
// PairFactory.sol
import "./Pair.sol";

contract PairFactory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address) {
        Pair pair = new Pair();           // 创建新合约
        pair.initialize(tokenA, tokenB);  // 初始化
        
        getPair[tokenA][tokenB] = address(pair);
        getPair[tokenB][tokenA] = address(pair);
        
        return address(pair);
    }
}
```

**问题**：每次调用 `createPair`，得到的地址都不同，无法提前预测。

## CREATE2：确定性创建

CREATE2 的地址由四个因素决定：

```
地址 = keccak256(0xff ++ deployer ++ salt ++ keccak256(initcode))[12:]
```

| 因素 | 说明 |
|------|------|
| `0xff` | 固定前缀 |
| `deployer` | 部署者地址（通常是工厂合约） |
| `salt` | 32 字节的盐值，由开发者指定 |
| `initcode` | 创建代码 + 构造函数参数 |

只要这四个因素相同，地址就相同——**可以在部署前预测地址**。

语法

```solidity
Contract x = new Contract{salt: salt}(params);
```

只需加一个 `salt` 参数。

### 示例：可预测地址的 Pair 工厂

```solidity
contract PairFactory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address tokenA, address tokenB) external returns (address) {
        // 排序，确保同一对 token 的 salt 一致
        (address token0, address token1) = tokenA < tokenB 
            ? (tokenA, tokenB) 
            : (tokenB, tokenA);
        
        // 用 token 地址生成 salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        
        // 使用 CREATE2 部署
        Pair pair = new Pair{salt: salt}();
        pair.initialize(tokenA, tokenB);
        
        getPair[tokenA][tokenB] = address(pair);
        getPair[tokenB][tokenA] = address(pair);
        
        return address(pair);
    }
}
```

### 预测地址

无需调用 `createPair`，就能计算出 Pair 的地址：

```solidity
function predictPair(address tokenA, address tokenB) external view returns (address) {
    (address token0, address token1) = tokenA < tokenB 
        ? (tokenA, tokenB) 
        : (tokenB, tokenA);
    
    bytes32 salt = keccak256(abi.encodePacked(token0, token1));
    
    // initcode = 创建代码 + 构造函数参数
    bytes32 initCodeHash = keccak256(
        abi.encodePacked(type(Pair).creationCode)  // Pair 无构造参数
    );
    
    // CREATE2 地址公式
    return address(uint160(uint256(keccak256(abi.encodePacked(
        bytes1(0xff),
        address(this),  // deployer
        salt,
        initCodeHash
    )))));
}
```

**为什么地址转换要写成 `address(uint160(uint256(...)))`？**

CREATE2 计算出的是 32 字节哈希（`bytes32`），但以太坊地址只有 20 字节（160 bit）。合约地址取的是哈希的**低 20 字节**。

Solidity 不允许直接把 `bytes32` 强转成 `address`——这样做会有歧义：取高 20 字节还是低 20 字节？所以必须显式告诉编译器：

```solidity
bytes32 h = keccak256(...);

uint256(h)              // 第一步：把 bytes32 当作 256 位整数
uint160(uint256(h))     // 第二步：截断为 160 位（自动保留低 160 bit）
address(uint160(...))   // 第三步：把 160 位整数解释为 address
```

这是 Solidity 中"截断取低位"的标准写法，在处理哈希结果时经常用到。

### 理解 initcode

两个容易混淆的概念：

| 概念 | 说明 | 获取方式 |
|------|------|---------|
| initcode | 部署时执行的代码，包含构造函数 | `type(C).creationCode` |
| runtime code | 部署后存储在链上的代码 | `type(C).runtimeCode` |

initcode 执行完毕后，返回 runtime code，后者才是用户实际调用的代码。

**CREATE2 地址计算用的是 initcode 的哈希**。

如果合约有构造函数参数：

```solidity
bytes memory initcode = abi.encodePacked(
    type(Pair).creationCode,
    abi.encode(constructorArg1, constructorArg2)
);
bytes32 initCodeHash = keccak256(initcode);
```

### CREATE2 的应用场景

1. 反事实部署

先计算地址 → 用户向该地址转账 → 之后再部署合约。

账户抽象钱包常用这种模式：用户先拿到钱包地址收款，真正需要时才部署钱包合约。

2. 跨链确定性部署

在多条链上用相同参数部署，得到相同地址。跨链协议需要这个特性。

3. 合约重建

销毁合约后，用相同参数可以在同一地址重新部署（需要 `selfdestruct`）。

### 注意事项

**1. 同地址只能部署一次**

同样的 `deployer + salt + initcode` 组合，第二次部署会失败。

**2. value 不影响地址**

`new Pair{salt: salt, value: 1 ether}()` 中的 `value` 不参与地址计算。

**3. deployer 是工厂合约**

在 `PairFactory.createPair()` 中调用 `new Pair{salt: ...}()`，deployer 是 `PairFactory` 的地址，而不是调用 `createPair` 的用户。

**4. 任何因素变化都会改变地址**

工厂地址、salt、合约代码、构造参数——任何一个变化，地址都会不同。

## 底层调用方式

如果需要部署任意字节码，可以用 assembly：

```solidity
// CREATE
function rawCreate(bytes memory bytecode) external returns (address addr) {
    assembly {
        addr := create(0, add(bytecode, 0x20), mload(bytecode))
        if iszero(addr) { revert(0, 0) }
    }
}

// CREATE2
function rawCreate2(bytes memory bytecode, bytes32 salt) external returns (address addr) {
    assembly {
        addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        if iszero(addr) { revert(0, 0) }
    }
}
```

参数含义：`create(value, offset, size)` / `create2(value, offset, size, salt)`

## selfdestruct 的变化

2024 年坎昆升级（EIP-6780）限制了 `selfdestruct`：

- **同一笔交易内**：仍可删除代码和存储
- **之后的交易**：只转移 ETH，代码和存储保留

这意味着"销毁后重建"的模式基本不再可行。

## 小结

本篇我们学习了：

1. `CREATE` 和 `CREATE2` 的区别
2. CREATE2 地址的计算公式
3. 如何预测合约地址（以及为什么地址转换要写成 `address(uint160(uint256(...)))`）

至此，合约间调用系列完结。你已经掌握了：

- 如何调用其他合约（四种方式）
- 底层 call 的用法和 calldata 构造
- 如何在合约中创建新合约



**系列导航**

- 第一篇：[四种方式调用已部署合约](./solidity_contract_call_part1_251221.md)
- 第二篇：[底层调用与 calldata 详解](./solidity_contract_call_part2_251223.md)
- 第三篇：创建合约的两种方式：create 与 create2（本篇）
