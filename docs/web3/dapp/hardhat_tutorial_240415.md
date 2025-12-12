> 说明：原版发布于 2024-04-15，基于 Node 20.x，Ubuntu 20.04 系统开发，最新版更新于2025-12-12，基于 Node 22.x，Ubuntu 24.04 系统开发。

Hardhat 是一个以 Node.js/JavaScript 生态为核心的以太坊智能合约开发环境，帮助开发者把「写合约 → 编译 → 测试 → 本地调试 → 部署到测试网/主网」这一系列重复工作自动化与工程化；它内置 Hardhat Network（本地以太坊网络），用于部署、跑测试、调试合约逻辑。  

在 Hardhat 的设计里：

- 在命令行每跑一次 `npx hardhat xxx`，本质上是在执行一个 task；
- 大部分能力由 plugins 提供（例如 ethers 集成、chai-matchers、Ignition 部署等），官方推荐初学者使用 `@nomicfoundation/hardhat-toolbox` 一揽子插件。

## 一、配置环境

在 Windows 系统使用 VS Code 配置 Ubuntu 24.04 上的开发环境。

安装 22.x 版 Node.js：

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 查看安装的版本
node -v
npm -v
```

## 二、创建 Hardhat 项目

使用 Node.js 的包管理器 `npm` 来安装 hardhat：

初始化项目目录与 npm 工程：

```bash
mkdir hardhat-tutorial
cd hardhat-tutorial
npm init
```

安装 Hardhat v2（官方教程使用 `hardhat@hh2` 这个标签来锁定 v2）：

```bash
npm install --save-dev hardhat@hh2 # 该过程可能比较花时间
```

初始化 Hardhat 配置文件：

```bash
npx hardhat init	# 选择：Create an empty hardhat.config.js
```

安装官方推荐插件集合 hardhat-toolbox：

```bash
npm install --save-dev @nomicfoundation/hardhat-toolbox@hh2
```

在 hardhat.config.js 文件中添加 `require("@nomicfoundation/hardhat-toolbox");`，这一步完成后，hardhat.config.js 如下：

```javascript
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
};
```

补充：如果使用 npm install --save-dev hardhat 安装 hardhat 太慢，可以使用 yarn add --dev hardhat 来安装。

安装 yarn 指令如下：`yarn` 官方提供了一个 APT 仓库，可以通过它来安装 `yarn`，配置仓库并导入 Yarn 的 GPG 公钥：

```bash
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update
sudo apt-get install yarn
yarn --version
```

## 三、创建 & 编译智能合约

在项目根目录中新建一个 `contracts` 目录，接下来就可以在 `contracts` 目录中编写我们的合约代码，以下 MiniToken.sol 参考自 Hardhat 官方教程：

```solidity
// SPDX-License-Identifier:MIT
pragma solidity ^0.8.28;
import "hardhat/console.sol";

contract MiniToken {
    string public name = "Mini Hardhat Token";
    string public symbol = "MHT";
    uint256 public totalSupply = 1000000;

    address public owner;
    mapping(address => uint256) private balances;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor() {
        owner = msg.sender;
        balances[msg.sender] = totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external {
        require(balances[msg.sender] >= amount, "Not enough tokens");
        balances[msg.sender] -= amount;
        balances[to] += amount;
      
        emit Transfer(msg.sender, to, amount);
    }
}
```

注：可以在 VS Code 中安装 hardhat 的扩展程序 Solidity by Nomic Foundation。

合约代码编写完后，使用 `npx hardhat compile` 指令编译。

## 四、编写测试并运行（基于 Hardhat Network）

Hardhat 默认网络就是 Hardhat Network，跑测试无需额外启动节点或配置。官方教程用 ethers.js + Mocha + Chai 来写测试。

在根目录中新建一个目录 `test`，添加如下 MiniToken.js 文件：

```javascript
const { expect } = require("chai");

describe("MiniToken", function () {
  it("部署后：部署者应拿到全部 totalSupply", async function () {
    const [owner] = await ethers.getSigners();
    const token = await ethers.deployContract("MiniToken");

    const ownerBalance = await token.balanceOf(owner.address);
    expect(await token.totalSupply()).to.equal(ownerBalance);
  });

  it("转账：应能在不同账户间转移余额", async function () {
    const [owner, addr1, addr2] = await ethers.getSigners();
    const token = await ethers.deployContract("MiniToken");

    await token.transfer(addr1.address, 50);
    expect(await token.balanceOf(addr1.address)).to.equal(50);

    await token.connect(addr1).transfer(addr2.address, 50);
    expect(await token.balanceOf(addr2.address)).to.equal(50);
  });

  it("失败用例：余额不足应 revert", async function () {
    const [, addr1, addr2] = await ethers.getSigners();
    const token = await ethers.deployContract("MiniToken");

    await expect(token.connect(addr1).transfer(addr2.address, 1))
      .to.be.revertedWith("Not enough tokens");
  });
});
```

执行`npx hardhat test`指令，测试结果如下：

```bash
test@DESKTOP-958GQ8P:~/desktop/hardhat-tutorial$ npx hardhat test


  MiniToken
    ✔ 部署后：部署者应拿到全部 totalSupply (486ms)
    ✔ 转账：应能在不同账户间转移余额
    ✔ 失败用例：余额不足应 revert


  3 passing (537ms)
  
```

官方教程还推荐用 `loadFixture` 做测试夹具与快照回滚，提高测试速度并减少重复部署代码。

## 五、使用 Hardhat Network 调试

### 5.1 在 Solidity 里直接 console.log

Hardhat Network 支持在 Solidity 代码中调用 `console.log()` 输出日志信息、合约变量，用法是在合约代码中导入 `import "hardhat/console.sol";` 并在函数里打印。

示例：编辑 `contracts/MiniToken.sol`，在 `transfer()` 中加入日志：

```solidity
import "hardhat/console.sol";

function transfer(address to, uint256 amount) external {
    require(balances[msg.sender] >= amount, "Not enough tokens");

    console.log(
        "Transferring from %s to %s %s tokens",
        msg.sender,
        to,
        amount
    );

    balances[msg.sender] -= amount;
    balances[to] += amount;
    emit Transfer(msg.sender, to, amount);
}
```

再跑一次测试指令`npx hardhat test`，会在测试输出中看到转账日志：

```bash
test@DESKTOP-958GQ8P:~/desktop/hardhat-tutorial$ npx hardhat test
Compiled 2 Solidity files successfully (evm target: paris).


  MiniToken
    ✔ 部署后：部署者应拿到全部 totalSupply (471ms)
Transferring from 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 to 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 50 tokens
Transferring from 0x70997970c51812dc3a010c7d01b50e0d17dc79c8 to 0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc 50 tokens
    ✔ 转账：应能在不同账户间转移余额
    ✔ 失败用例：余额不足应 revert


  3 passing (520ms)
```

注意点（来自 Hardhat Network 参考文档）：

- `console.log` 可在 call/transaction 中使用，`view` 可用，但 `pure` 不行；
- 需要`import "hardhat/console.sol"`；
- `console.log` 最多支持 4 个参数，且有明确的类型范围与若干单参 API。

### 5.2 额外调试抓手

**失败堆栈**：Hardhat Network 默认会在交易失败时抛出“JavaScript + Solidity”的组合堆栈信息（便于定位 revert 触发点）。

**in-process vs JSON-RPC node**：测试时用的是 in-process Hardhat Network；如果用 `node` 任务启动 JSON-RPC server（便于前端/钱包连接），日志与行为会略有不同（例如 loggingEnabled 默认值对 in-process 与 node 有差异）。

## 六、部署到 Sepolia 测试网

### 6.1 用 Ignition Module 描述部署

Ignition 的部署入口是 Module，放在 `ignition/modules` 目录下。

创建 `ignition/modules/MiniToken.js` 文件如下：

```javascript
const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

const TokenModule = buildModule("TokenModule", (m) => {
  const token = m.contract("Token");

  return { token };
});

module.exports = TokenModule;
```

### 6.2 配置 Sepolia RPC 与私钥

部署到远程测试网络需要在 `hardhat.config.js` 中配置 RPC 信息，然后在部署指令中使用 `--network`参数告知 Hardhat 连接到哪个网络。

注册一个 [Alchemy](https://www.alchemy.com/) 账户， 然后创建一个 Ethereum Sepolia 的 App，获取该 App 的 API key。

从虚拟钱包发出的每一笔交易都需要使用`private key`来签名，该步骤通过把钱包地址的 private key、alchemy API key 存储在一个 environment file 中，来为程序提供必要的访问权限。

通过`npm install dotenv`指令安装 dotenv 模块，以便读取`.env`文件：

```plain
ALCHEMY_API_KEY = "xxx"
SEPOLIA_PRIVATE_KEY = "xxx"
```

注：测试用的钱包地址中不要放置任何真实资产。

在`hardhat.config.js`文件中添加配置，以便部署到 Sepolia 测试网：

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { ALCHEMY_API_KEY, SEPOLIA_PRIVATE_KEY } = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
  },
};
```

### 6.3 部署合约

到目前为止，已经可以完成最后的部署了，在终端中执行如下指令：

```shell
$ npx hardhat ignition deploy ./ignition/modules/MiniToken.js --network sepolia
[dotenv@17.2.3] injecting env (2) from .env -- tip: 🔐 prevent committing .env to code: https://dotenvx.com/precommit
✔ Confirm deploy to network sepolia (11155111)? … yes
[ MiniTokenModule ] Nothing new to deploy based on previous execution stored in ./ignition/deployments/chain-11155111

Deployed Addresses

MiniTokenModule#MiniToken - 0x07831829b9F8182eE65B446adc7cD6Dc0Ba61b6D
```

Hardhat 也支持通过脚本来部署合约。在项目根目录下新建`scripts/` 目录，将 JS 编写的部署脚本 `deploy.js` 放在该`scripts/` 目录中，最后执行 `npx hardhat run scripts/deploy.js --network sepolia`就可以了。

```javascript
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Deployer:", deployer.address);
  console.log("Deployer balance:", hre.ethers.formatEther(balance), "ETH");

  // 推荐写法：hardhat-ethers 提供 ethers.deployContract
  const token = await hre.ethers.deployContract("MiniToken");
  await token.waitForDeployment();

  // ethers v6 合约地址常用 token.target（或 await token.getAddress()）
  console.log("MiniToken deployed to:", token.target);

  const tx = token.deploymentTransaction();
  console.log("Deployment tx hash:", tx.hash);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
```

执行结果大致如下：

```bash
test@DESKTOP-958GQ8P:~/desktop/hardhat-tutorial$ npx hardhat run scripts/deploy.js --network sepolia
[dotenv@17.2.3] injecting env (2) from .env -- tip: ⚙️  load multiple .env files with { path: ['.env.local', '.env'] }
[dotenv@17.2.3] injecting env (0) from .env -- tip: 🛠️  run anywhere with `dotenvx run -- yourcommand`
Deployer: 0x84B62e4c0766414a867A5aCc7BCa14901B3c713C
Deployer balance: 0.508237594610744345 ETH
MiniToken deployed to: 0xEc2E9d1ddEb8d6b1F695c23512afaa70d716458e
Deployment tx hash: 0x421c29757589388e092d52d48bf65d89060bb725cfc96a9b02497557b64bd8fa
```

参考资料：[Hardhat's tutorial for beginners](https://v2.hardhat.org/tutorial)
