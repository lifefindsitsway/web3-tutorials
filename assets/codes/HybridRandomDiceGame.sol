// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title HybridRandomDiceGame - 混合随机骰子游戏（生产级单文件版本）
 * @author Lifefindsitsway
 * @notice 基于 Commit-Reveal + Chainlink VRF v2.5 的公平骰子游戏
 * @dev 本合约兼顾"教学可读性"与"生产级健壮性"，适合作为 Web3 游戏开发的参考实现
 *
 * @custom:version 1.0.0
 * @custom:date 2026-01-24
 * @custom:network Sepolia
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                              一、合约定位
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 这是一个"教学可读性 + 生产级健壮性"兼顾的骰子游戏（Dice Game）实现：
 * - 面向真实线上环境：随机性不可预测、回调不中断、资金不被锁死、可运维可观测
 * - 面向教学演示：清晰展示 Commit-Reveal 的时序与 VRF 异步结算模型
 *
 * 【游戏规则（简化版）】
 * - 玩家每局固定下注 BET_AMOUNT
 * - 玩家猜 1~6 的点数
 * - 若掷骰结果 roll == guess，则赢取固定奖金 PRIZE_AMOUNT（合约需提前注资）
 * - 若未中奖，则下注进入奖池（扣除协议手续费）
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                         二、随机性设计（Hybrid Randomness）
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 本合约采用"混合随机性"策略，将两种随机来源组合，从而同时满足：
 * - 防止玩家事后改答案（Commit-Reveal）
 * - 防止矿工/验证者或任何人提前预测结果（Chainlink VRF）
 *
 * 1) Commit-Reveal（承诺-揭示）
 *    - Commit：玩家先提交承诺 commitHash，不暴露 guess 与 secret
 *    - Reveal：玩家在时间窗口内公开 guess 与 secret，合约校验其与 commitHash 一致
 *
 * 2) Chainlink VRF v2.5（强不可预测随机源）
 *    - Reveal 后向 VRF Coordinator 发起请求（异步）
 *    - Coordinator 回调 fulfillRandomWords() 交付随机数 randomWords[0]
 *
 * 3) Hybrid Mix（混合熵）
 *    最终随机数由下式生成：
 *      mixed = keccak256(VRF_random, secret, player, requestId, address(this), chainid)
 *    这样即使 VRF 输出可复用，也能通过 secret / player / requestId / 合约地址 / 链 ID 增强唯一性。
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                       三、生产级关键策略（强烈建议保留）
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 1) 回调 fulfillRandomWords() 尽量不 revert
 *    - 若回调 revert，则 VRF 本次交付失败，玩家可能永久卡死在等待状态
 *    - 本合约采用"忽略异常 + 发事件记录"策略：emit CallbackIgnored(...) 并 return
 *
 * 2) Pull Payment（拉取支付）
 *    - 回调中不直接向玩家转账，避免因为转账失败导致回调 revert
 *    - 玩家奖金写入 pendingWithdrawals，玩家主动 withdraw() 领取
 *
 * 3) 单玩家单局（避免状态膨胀与复杂并发）
 *    - 同一玩家在 Committed / RandomRequested 阶段禁止开启新局
 *    - 合约不保存历史数组，仅保存 lastResults（上一局结果），全量历史通过事件日志追踪
 *
 * 4) 手续费模型（协议收入）
 *    - 下注收取 feeBps（bps：基点，100 = 1%）
 *    - 手续费累计到 protocolFeesAccrued，由 feeRecipient 提取
 *
 * 5) VRF 容灾（超时可重试）
 *    - 若 VRF 长时间未回调（VRF_TIMEOUT），允许 retryVrfRequest()
 *    - 旧 requestId 的回调若后续到达，将被忽略并记录 CallbackIgnored
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                           四、资金与奖池安全
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 为避免"奖池不足导致中奖无法支付"的情况：
 * - revealAndRequestRandom() 发起 VRF 请求前，会检查 _availablePrizeBalance() >= PRIZE_AMOUNT
 * - _availablePrizeBalance() 会扣除两类"已承诺负债"：
 *   (1) totalPendingWithdrawals：玩家已中奖/退款的待提现余额
 *   (2) protocolFeesAccrued：协议累计手续费（可被提取）
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                          五、可观测性（Observability）
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 关键状态变更均通过事件广播：
 * - Committed / RandomnessRequested / Settled / Cancelled / Withdrawn
 * - CallbackIgnored（回调异常原因定位）
 * - FeeCharged / ProtocolFeesWithdrawn（收入与资金流追踪）
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 *                        六、集成与部署注意事项
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 1) VRF 配置参数需按目标网络设置（Coordinator、Subscription、keyHash）
 * 2) 合约需提前 receive() 注资奖池，确保可支付 PRIZE_AMOUNT
 * 3) 管理员函数使用 onlyOwner 修饰符（来自 VRFConsumerBaseV2Plus 继承的 ConfirmedOwner）
 */

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title HybridRandomDiceGame
 * @notice 混合随机骰子游戏核心合约
 * @dev 继承关系：
 *      - VRFConsumerBaseV2Plus：Chainlink VRF v2.5 消费者基类（含 ConfirmedOwner）
 *      - Pausable：紧急暂停功能
 *      - ReentrancyGuard：重入攻击防护
 */
contract HybridRandomDiceGame is VRFConsumerBaseV2Plus, Pausable, ReentrancyGuard {
    
    // ═══════════════════════════════════════════════════════════════════════════
    //                        游戏参数常量（产品配置）
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public constant BET_AMOUNT = 0.001 ether;       // 单局下注金额
    uint256 public constant PRIZE_AMOUNT = 0.005 ether;     // 胜利奖金（奖池需提前注资）

    uint256 public constant COMMIT_DURATION = 60;           // commit 后等待多久才能 reveal
    uint256 public constant REVEAL_DURATION = 120;          // reveal 窗口时长
    uint256 public constant VRF_TIMEOUT = 10 minutes;       // VRF 超时阈值：超时后允许玩家调用 retryVrfRequest 重试

    // ═══════════════════════════════════════════════════════════════════════════
    //                          VRF 配置（Chainlink）
    // ═══════════════════════════════════════════════════════════════════════════

    uint256 public immutable subscriptionId;                // Chainlink VRF Subscription ID（订阅号）
    bytes32 public immutable keyHash;                       // VRF Gas Lane（keyHash / gasLane）

    uint32 public callbackGasLimit = 200000;                // VRF 回调可用 gas 上限（过小会导致回调失败）
    uint16 public requestConfirmations = 3;                 // VRF 请求区块确认数（越大越安全但越慢）
    uint32 public numWords = 1;                             // VRF 随机数数量（骰子游戏只需 1 个随机数）

    /// @notice VRF 配置更新事件
    /// @param callbackGasLimit 新的回调 gas 上限
    /// @param requestConfirmations 新的确认数
    /// @param numWords 新的随机数数量
    event VrfConfigUpdated(uint32 callbackGasLimit, uint16 requestConfirmations, uint32 numWords);

    // ═══════════════════════════════════════════════════════════════════════════
    //                        手续费配置（协议收入模型）
    // ═══════════════════════════════════════════════════════════════════════════

    uint16 public constant MAX_FEE_BPS = 500;   // 手续费率上限（基点），最高 5%，500 bps = 5%
    address public feeRecipient;                // 手续费接收地址，可通过 setFeeConfig 更新
    uint16 public feeBps;                       // 手续费费率（bps），100 = 1%
    uint256 public protocolFeesAccrued;         // 已累计但尚未提取的手续费（以 ETH 记账）
    uint256 public totalPendingWithdrawals;     // 全体玩家待提现总额（ETH），用于计算奖池可用余额

    /// @notice 手续费配置更新事件
    /// @param feeRecipient 新的手续费接收地址
    /// @param feeBps 新的手续费率
    event FeeConfigUpdated(address indexed feeRecipient, uint16 feeBps);

    /// @notice 手续费扣除事件
    /// @param player 被扣费的玩家
    /// @param feeRecipient 手续费接收地址
    /// @param fee 扣除的手续费金额（ETH）
    event FeeCharged(address indexed player, address indexed feeRecipient, uint256 fee);

    // ═══════════════════════════════════════════════════════════════════════════
    //                        状态机设计（单玩家单局）
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 游戏状态枚举
     * @dev 每个玩家独立维护一份状态，状态转换流程：
     *      None → Committed（commit 成功）
     *      Committed → RandomRequested（reveal 成功）
     *      RandomRequested → None（VRF 回调结算）
     *      Committed → None（超时取消）
     */
    enum GameState {
        None,                   // 空闲状态：可开始新局
        Committed,              // 已提交承诺：等待 reveal
        RandomRequested         // 已 reveal 且已请求 VRF：等待回调结算
    }

    /**
     * @notice 玩家当前局的核心状态结构
     * @dev 每个玩家地址对应一个 Game 结构，存储在 games mapping 中
     *
     * 【字段说明】
     * @param commitHash 承诺哈希，由 keccak256(player, guess, secret, address(this), chainid, nonce) 计算
     * @param commitTime commit 时间戳（秒），用于可观测性与调试
     * @param revealStart reveal 窗口起始时间 = commitTime + COMMIT_DURATION
     * @param revealDeadline reveal 截止时间 = revealStart + REVEAL_DURATION
     * @param guess 玩家猜测的点数（1~6），reveal 后写入
     * @param secret 玩家的秘密随机数，reveal 后写入，用于 Hybrid Mix
     * @param requestId VRF 请求 ID，用于匹配回调
     * @param vrfRequestTime VRF 请求发起时间，用于超时判断
     * @param nonce 防重放 nonce，每完成一局递增（无论输赢/取消）
     * @param feePaid 当局已扣除的手续费，cancel 时用于计算退款
     * @param state 当前游戏状态
     */
    struct Game {
        bytes32 commitHash;
        uint64 commitTime;
        uint64 revealStart;
        uint64 revealDeadline;
        uint8 guess;
        bytes32 secret;
        uint256 requestId;
        uint64 vrfRequestTime;
        uint32 nonce;
        uint256 feePaid;
        GameState state;
    }

    /**
     * @notice 玩家上一局结果结构
     * @dev 链上仅保留上一局结果，全量历史通过 Settled 事件追溯
     *
     * 【字段说明】
     * @param settledTime 结算时间戳（秒）
     * @param requestId 对应的 VRF 请求 ID
     * @param roll 掷骰结果（1~6）
     * @param guess 玩家猜测的点数（1~6）
     * @param won 是否中奖
     * @param payout 实际派奖金额（中奖为 PRIZE_AMOUNT，否则为 0）
     */
    struct LastResult {
        uint64 settledTime;
        uint256 requestId;
        uint8 roll;
        uint8 guess;
        bool won;
        uint256 payout;
    }

    /// @notice 玩家地址 → 当前局状态
    /// @dev private 以防止外部直接读取；通过 getGame() 查询
    mapping(address => Game) private games;

    /// @notice 玩家地址 → 上一局结果
    /// @dev private 以防止外部直接读取；通过 getLastResult() 查询
    mapping(address => LastResult) private lastResults;

    /// @notice VRF requestId → 玩家地址
    /// @dev 用于 VRF 回调时定位玩家；重试时旧映射会被删除
    mapping(uint256 => address) public requestToPlayer;

    /// @notice 玩家地址 → 可提取金额（ETH）
    /// @dev Pull Payment 模式：中奖/退款不直接转账，而是累计到此 mapping
    mapping(address => uint256) public pendingWithdrawals;

    // ═══════════════════════════════════════════════════════════════════════════
    //                            自定义错误
    // ═══════════════════════════════════════════════════════════════════════════

    error FeeRecipientZeroAddress();     // feeRecipient 不能为零地址
    error InvalidGuess();                // guess 必须在 1~6 范围内
    error ZeroCommitHash();              // commitHash 不能为 bytes32(0)
    error IncorrectBetAmount();          // 下注金额必须严格等于 BET_AMOUNT
    error GameAlreadyActive();           // 玩家已有进行中的游戏（Committed/RandomRequested）
    error NoActiveGame();                // 当前没有可操作的游戏（状态不符合预期）
    error CommitPhaseNotOver();          // commit 冷却期未结束，不能 reveal
    error RevealPhaseOver();             // reveal 截止时间已过
    error InvalidReveal();               // reveal 信息不匹配 commitHash（guess/secret/nonce不对）
    error PrizePoolInsufficient();       // 奖池不足以覆盖 PRIZE_AMOUNT
    error RevealNotExpired();            // reveal 尚未过期，不能取消
    error NothingToWithdraw();           // 没有可提现余额
    error WithdrawFailed();              // 转账失败
    error FeeTooHigh();                  // feeBps 超过上限 MAX_FEE_BPS
    error NotFeeRecipient();             // 非 feeRecipient 无权提取手续费
    error VrfTimeoutNotReached();        // VRF 未超时，不能 retry
    error NotWaitingVrf();               // 当前不是等待 VRF 回调状态
    error InvalidVrfConfig();            // VRF 配置参数非法

    // ═══════════════════════════════════════════════════════════════════════════
    //                            事件定义
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice 奖池注资事件
    /// @param funder 注资者地址
    /// @param amount 注资金额（ETH）
    event PrizePoolFunded(address indexed funder, uint256 amount);

    /// @notice 玩家提交承诺事件
    /// @param player 玩家地址
    /// @param commitHash 承诺哈希
    /// @param commitTime commit 时间戳
    /// @param revealStart reveal 窗口起始时间
    /// @param revealDeadline reveal 截止时间
    /// @param nonce 本局使用的 nonce
    event Committed(
        address indexed player,
        bytes32 indexed commitHash,
        uint256 commitTime,
        uint256 revealStart,
        uint256 revealDeadline,
        uint32 nonce
    );

    /// @notice VRF 请求发起事件
    /// @param player 玩家地址
    /// @param requestId VRF 请求 ID
    event RandomnessRequested(address indexed player, uint256 indexed requestId);

    /// @notice VRF 请求重试事件
    /// @param player 玩家地址
    /// @param oldRequestId 旧的 VRF 请求 ID
    /// @param newRequestId 新的 VRF 请求 ID
    event VrfRequestRetried(
        address indexed player,
        uint256 indexed oldRequestId,
        uint256 indexed newRequestId
    );

    /// @notice 游戏结算事件
    /// @param player 玩家地址
    /// @param requestId VRF 请求 ID
    /// @param roll 掷骰结果（1~6）
    /// @param guess 玩家猜测（1~6）
    /// @param won 是否中奖
    /// @param payout 派奖金额
    event Settled(
        address indexed player,
        uint256 indexed requestId,
        uint256 roll,
        uint256 guess,
        bool won,
        uint256 payout
    );

    /// @notice 玩家取消游戏事件
    /// @param player 玩家地址
    /// @param refund 退款金额
    event Cancelled(address indexed player, uint256 refund);

    /// @notice 玩家提现事件
    /// @param player 玩家地址
    /// @param amount 提现金额
    event Withdrawn(address indexed player, uint256 amount);

    /// @notice 协议手续费提取事件
    /// @param feeRecipient 手续费接收地址
    /// @param amount 提取金额
    event ProtocolFeesWithdrawn(address indexed feeRecipient, uint256 amount);

    /**
     * @notice VRF 回调忽略原因枚举
     * @dev 用于 CallbackIgnored 事件，帮助定位回调异常原因
     *
     * UnknownRequestId: requestId 未映射到玩家（可能已 delete 或从未存在）
     * InvalidGameState: 玩家状态不是 RandomRequested
     * RequestIdMismatch: 玩家 requestId 已更新（retry 后旧回调到达）
     * EmptyRandomWords: randomWords 数组为空（防御式编程）
     */
    enum CallbackIgnoreReason {
        UnknownRequestId,
        InvalidGameState,
        RequestIdMismatch,
        EmptyRandomWords
    }

    /// @notice VRF 回调被忽略事件
    /// @dev 生产环境中用于监控和排查 VRF 回调异常
    /// @param requestId VRF 请求 ID
    /// @param player 玩家地址（可能为 address(0)）
    /// @param reason 忽略原因
    event CallbackIgnored(
        uint256 indexed requestId,
        address indexed player,
        CallbackIgnoreReason reason
    );

    // ═══════════════════════════════════════════════════════════════════════════
    //                              构造函数
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 部署合约并初始化 VRF 与手续费配置
     * @dev 构造函数参数需根据目标网络配置：
     *      - Sepolia: coordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
     *      - Sepolia: gasLane = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
     *      - 其他网络的参数参见 Chainlink 文档
     *
     * @param coordinator Chainlink VRF Coordinator 地址
     * @param subId VRF Subscription ID（需在 Chainlink 控制台创建）
     * @param gasLane VRF keyHash（Gas Lane）
     * @param _feeRecipient 协议手续费接收地址
     * @param _feeBps 初始手续费率（基点），不得超过 MAX_FEE_BPS
     */
    constructor(
        address coordinator,
        uint256 subId,
        bytes32 gasLane,
        address _feeRecipient,
        uint16 _feeBps
    ) VRFConsumerBaseV2Plus(coordinator) {
        // 参数校验
        if (_feeRecipient == address(0)) revert FeeRecipientZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        // 初始化 VRF 配置（immutable）
        subscriptionId = subId;
        keyHash = gasLane;

        // 初始化手续费配置
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;

        emit FeeConfigUpdated(_feeRecipient, _feeBps);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              奖池注资
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 接收 ETH 作为奖池注资
     * @dev 任何人可向合约转账以补充奖池；建议运营方部署后立即注资
     */
    receive() external payable {
        emit PrizePoolFunded(msg.sender, msg.value);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                       Commit-Reveal：Commit 阶段
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 提交承诺（Commit 阶段）
     * @dev 玩家在此阶段提交 commitHash 并支付 BET_AMOUNT
     *
     * 【承诺哈希计算公式】
     * commitHash = keccak256(abi.encode(player, guess, secret, address(this), block.chainid, nonce))
     *
     * 【前端集成流程】
     * 1. 调用 getNextNonce(player) 获取下一个 nonce
     * 2. 前端生成 32 字节随机 secret
     * 3. 玩家选择 guess（1~6）
     * 4. 计算 commitHash（可调用 computeCommitHash 辅助函数）
     * 5. 调用 commit(commitHash) 并附带 BET_AMOUNT
     *
     * 【状态转换】
     * None → Committed
     *
     * 【修饰符】
     * - nonReentrant：防止重入攻击
     * - whenNotPaused：合约暂停时禁止操作
     *
     * @param commitHash 承诺哈希（不能为 bytes32(0)）
     *
     * @custom:reverts ZeroCommitHash 如果 commitHash 为零
     * @custom:reverts IncorrectBetAmount 如果 msg.value != BET_AMOUNT
     * @custom:reverts GameAlreadyActive 如果玩家已有进行中的游戏
     */
    function commit(bytes32 commitHash) external payable nonReentrant whenNotPaused {
        // 参数校验
        if (commitHash == bytes32(0)) revert ZeroCommitHash();
        if (msg.value != BET_AMOUNT) revert IncorrectBetAmount();

        // 状态校验：单玩家单局
        Game storage g = games[msg.sender];
        if (g.state == GameState.Committed || g.state == GameState.RandomRequested) {
            revert GameAlreadyActive();
        }

        // 计算时间窗口
        uint64 nowTs = uint64(block.timestamp);
        uint32 newNonce = g.nonce + 1;  // nonce 自增，前端可通过 getNextNonce() 预读
        uint64 revealStart = nowTs + uint64(COMMIT_DURATION);
        uint64 revealDeadline = revealStart + uint64(REVEAL_DURATION);

        // 手续费记账（非直接转账，避免失败）
        uint256 fee = (BET_AMOUNT * feeBps) / 10000;
        if (fee > 0) {
            protocolFeesAccrued += fee;
            emit FeeCharged(msg.sender, feeRecipient, fee);
        }

        // EFFECTS：初始化新局状态
        games[msg.sender] = Game({
            commitHash: commitHash,
            commitTime: nowTs,
            revealStart: revealStart,
            revealDeadline: revealDeadline,
            guess: 0,                   // reveal 时填充
            secret: bytes32(0),         // reveal 时填充
            requestId: 0,               // VRF 请求时填充
            vrfRequestTime: 0,          // VRF 请求时填充
            nonce: newNonce,
            feePaid: fee,
            state: GameState.Committed
        });

        emit Committed(msg.sender, commitHash, nowTs, revealStart, revealDeadline, newNonce);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                   Commit-Reveal：Reveal + VRF 请求
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 揭示承诺并发起 VRF 请求（Reveal 阶段）
     * @dev 玩家在 reveal 时间窗口内公开 guess 和 secret，合约验证后发起 VRF 请求
     *
     * 【核心流程】
     * 1. 校验 reveal 时间窗口：nowTs ∈ [revealStart, revealDeadline)
     * 2. 校验 commitHash 匹配：防止玩家事后修改 guess/secret
     * 3. 校验奖池余额：确保中奖时可支付 PRIZE_AMOUNT
     * 4. 发起 VRF 请求：进入异步等待回调状态
     *
     * 【状态转换】
     * Committed → RandomRequested
     *
     * @param guess 玩家猜测的点数（1~6）
     * @param secret 玩家的秘密随机数（32 字节）
     * @return requestId VRF 请求 ID
     *
     * @custom:reverts InvalidGuess 如果 guess 不在 1~6 范围
     * @custom:reverts NoActiveGame 如果当前状态不是 Committed
     * @custom:reverts CommitPhaseNotOver 如果当前时间 < revealStart
     * @custom:reverts RevealPhaseOver 如果当前时间 >= revealDeadline
     * @custom:reverts InvalidReveal 如果计算的 commitHash 不匹配
     * @custom:reverts PrizePoolInsufficient 如果奖池余额 < PRIZE_AMOUNT
     */
    function revealAndRequestRandom(
        uint8 guess,
        bytes32 secret
    ) external nonReentrant whenNotPaused returns (uint256 requestId) {
        // 参数校验
        if (guess < 1 || guess > 6) revert InvalidGuess();

        Game storage g = games[msg.sender];
        if (g.state != GameState.Committed) revert NoActiveGame();

        // 时间窗口校验
        uint256 nowTs = block.timestamp;
        if (nowTs < g.revealStart) revert CommitPhaseNotOver();
        if (nowTs >= g.revealDeadline) revert RevealPhaseOver();

        // 承诺校验：确保 guess/secret/nonce 与 commit 时一致
        bytes32 computed = _computeCommitHash(msg.sender, guess, secret, g.nonce);
        if (computed != g.commitHash) revert InvalidReveal();

        // 奖池校验：确保中奖可支付（扣除已承诺负债）
        if (_availablePrizeBalance() < PRIZE_AMOUNT) revert PrizePoolInsufficient();

        // EFFECTS：保存 reveal 数据，进入等待 VRF 状态
        g.guess = guess;
        g.secret = secret;
        g.state = GameState.RandomRequested;

        // INTERACTIONS：发起 VRF 请求
        requestId = _requestVrf();
        g.requestId = requestId;
        g.vrfRequestTime = uint64(nowTs);
        requestToPlayer[requestId] = msg.sender;

        emit RandomnessRequested(msg.sender, requestId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        VRF 容灾：超时重试
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice VRF 超时后重试请求（容灾机制）
     * @dev 若 VRF Coordinator 长时间未回调（网络拥堵、LINK 余额不足等），
     *      玩家可在超时后调用此函数重新发起 VRF 请求
     *
     * 【旧回调处理】
     * - 旧 requestId 的映射会被删除
     * - 若旧回调后续到达，将触发 CallbackIgnored 事件并被忽略
     *
     * 【状态转换】
     * RandomRequested → RandomRequested（requestId 更新）
     *
     * @return newRequestId 新的 VRF 请求 ID
     *
     * @custom:reverts NotWaitingVrf 如果当前状态不是 RandomRequested
     * @custom:reverts VrfTimeoutNotReached 如果 VRF 尚未超时
     */
    function retryVrfRequest() external nonReentrant whenNotPaused returns (uint256 newRequestId) {
        Game storage g = games[msg.sender];
        if (g.state != GameState.RandomRequested) revert NotWaitingVrf();

        // 检查超时
        uint256 deadline = uint256(g.vrfRequestTime) + VRF_TIMEOUT;
        if (block.timestamp < deadline) revert VrfTimeoutNotReached();

        uint256 oldRequestId = g.requestId;

        // 删除旧映射：旧回调到达时将被忽略（触发 CallbackIgnored）
        delete requestToPlayer[oldRequestId];

        // 发起新的 VRF 请求
        newRequestId = _requestVrf();
        g.requestId = newRequestId;
        g.vrfRequestTime = uint64(block.timestamp);
        requestToPlayer[newRequestId] = msg.sender;

        emit VrfRequestRetried(msg.sender, oldRequestId, newRequestId);
        emit RandomnessRequested(msg.sender, newRequestId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                     VRF 回调：结算逻辑（不 revert）
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Chainlink VRF 回调入口（由 Coordinator 调用）
     * @dev 【生产级关键设计】本函数尽量不 revert！
     *
     * 【为什么不能 revert】
     * - VRF Coordinator 调用此函数交付随机数
     * - 若 revert，则本次随机数交付失败，玩家永久卡死在 RandomRequested 状态
     * - 虽然可通过 retryVrfRequest 恢复，但用户体验极差
     *
     * 【异常处理策略】
     * - 遇到任何异常情况，发出 CallbackIgnored 事件并 return
     * - 不使用 require/revert，确保函数正常返回
     *
     * 【Hybrid Mix 随机数混合】
     * mixed = keccak256(VRF_random, secret, player, requestId, address(this), chainid)
     * 这样即使 VRF 输出被复用，也能通过其他熵源增强唯一性
     *
     * 【状态转换】
     * RandomRequested → None
     *
     * @param requestId VRF 请求 ID
     * @param randomWords 随机数数组（本合约只使用 randomWords[0]）
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        // 查找玩家：requestId → player
        address player = requestToPlayer[requestId];
        if (player == address(0)) {
            // 未知 requestId：可能是已删除的旧请求或无效请求
            emit CallbackIgnored(requestId, address(0), CallbackIgnoreReason.UnknownRequestId);
            return;
        }

        Game storage g = games[player];

        // 状态校验：必须是 RandomRequested
        if (g.state != GameState.RandomRequested) {
            emit CallbackIgnored(requestId, player, CallbackIgnoreReason.InvalidGameState);
            return;
        }

        // requestId 匹配校验：防止旧回调干扰
        if (g.requestId != requestId) {
            // 说明玩家已 retry，当前是旧回调迟到
            emit CallbackIgnored(requestId, player, CallbackIgnoreReason.RequestIdMismatch);
            return;
        }

        // 随机数校验：防御式编程
        if (randomWords.length == 0) {
            emit CallbackIgnored(requestId, player, CallbackIgnoreReason.EmptyRandomWords);
            return;
        }

        // Hybrid Mix：混合多源熵生成最终随机数
        uint256 mixed = uint256(
            keccak256(
                abi.encode(
                    randomWords[0],     // VRF 随机数
                    g.secret,           // 玩家秘密
                    player,             // 玩家地址
                    requestId,          // 请求 ID
                    address(this),      // 合约地址
                    block.chainid       // 链 ID
                )
            )
        );

        // 计算掷骰结果：1~6
        uint8 roll = uint8((mixed % 6) + 1);
        bool won = (roll == g.guess);

        // 派奖处理：Pull Payment 模式
        uint256 payout = 0;
        if (won) {
            payout = PRIZE_AMOUNT;

            // 不直接转账，累计到待提现余额
            pendingWithdrawals[player] += payout;
            totalPendingWithdrawals += payout;
        }

        // 记录上一局结果（链上仅保留一局）
        lastResults[player] = LastResult({
            settledTime: uint64(block.timestamp),
            requestId: requestId,
            roll: roll,
            guess: g.guess,
            won: won,
            payout: payout
        });

        // 清理状态：释放玩家可开启新局
        delete requestToPlayer[requestId];

        // 重置 Game 结构（保留 nonce 递增计数；lastResults 不动）
        g.commitHash = bytes32(0);
        g.commitTime = 0;
        g.revealStart = 0;
        g.revealDeadline = 0;
        g.guess = 0;
        g.secret = bytes32(0);
        g.requestId = 0;
        g.vrfRequestTime = 0;
        g.feePaid = 0;
        g.state = GameState.None;

        emit Settled(player, requestId, roll, lastResults[player].guess, won, payout);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        取消：防止资金锁死
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 超时未 reveal 时取消游戏并获得部分退款
     * @dev 若玩家在 revealDeadline 后仍未 reveal，可调用此函数取消游戏
     *
     * 【退款计算】
     * - 手续费 feePaid 不退（视为不可逆的协议收入）
     * - 净下注 netBet = BET_AMOUNT - feePaid
     * - 退款 refund = netBet / 2（另一半进入奖池作为惩罚）
     *
     * 【状态转换】
     * Committed → None
     *
     * @custom:reverts NoActiveGame 如果当前状态不是 Committed
     * @custom:reverts RevealNotExpired 如果 revealDeadline 尚未到达
     */
    function cancelExpiredCommitment() external nonReentrant {
        Game storage g = games[msg.sender];
        if (g.state != GameState.Committed) revert NoActiveGame();
        if (block.timestamp < g.revealDeadline) revert RevealNotExpired();

        // 计算退款：(BET_AMOUNT - feePaid) / 2
        uint256 netBet = BET_AMOUNT - g.feePaid;
        uint256 refund = netBet / 2;

        // Pull Payment：累计到待提现余额
        pendingWithdrawals[msg.sender] += refund;
        totalPendingWithdrawals += refund;

        // 清理本局状态
        g.commitHash = bytes32(0);
        g.commitTime = 0;
        g.revealStart = 0;
        g.revealDeadline = 0;
        g.guess = 0;
        g.secret = bytes32(0);
        g.requestId = 0;
        g.vrfRequestTime = 0;
        g.feePaid = 0;
        g.state = GameState.None;

        emit Cancelled(msg.sender, refund);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        提现（Pull Payment）
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 玩家提取待提现余额（中奖/退款）
     * @dev Pull Payment 模式：玩家主动调用领取，避免合约主动推送转账失败
     *
     * 【CEI 模式】
     * 1. Checks：检查余额 > 0
     * 2. Effects：清零余额
     * 3. Interactions：转账
     *
     * @custom:reverts NothingToWithdraw 如果待提现余额为 0
     * @custom:reverts WithdrawFailed 如果 ETH 转账失败
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // EFFECTS：先清零，防止重入
        pendingWithdrawals[msg.sender] = 0;
        totalPendingWithdrawals -= amount;

        // INTERACTIONS：转账
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert WithdrawFailed();

        emit Withdrawn(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                      手续费提取（协议收入）
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice feeRecipient 提取累计的协议手续费
     * @dev 使用 Pull 模式，避免在 commit 中直接转账可能导致的失败
     *
     * @param amount 提取金额（不能为 0，不能超过 protocolFeesAccrued）
     *
     * @custom:reverts NotFeeRecipient 如果调用者不是 feeRecipient
     * @custom:reverts NothingToWithdraw 如果 amount 为 0 或超过累计金额
     * @custom:reverts WithdrawFailed 如果 ETH 转账失败
     */
    function withdrawProtocolFees(uint256 amount) external nonReentrant {
        if (msg.sender != feeRecipient) revert NotFeeRecipient();
        if (amount == 0 || amount > protocolFeesAccrued) revert NothingToWithdraw();

        // EFFECTS
        protocolFeesAccrued -= amount;

        // INTERACTIONS
        (bool ok, ) = feeRecipient.call{value: amount}("");
        if (!ok) revert WithdrawFailed();

        emit ProtocolFeesWithdrawn(feeRecipient, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                           管理员功能
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 更新手续费配置
     * @dev 仅合约 Owner 可调用（onlyOwner 来自 VRFConsumerBaseV2Plus 继承的 ConfirmedOwner）
     *
     * @param _feeRecipient 新的手续费接收地址（不能为零地址）
     * @param _feeBps 新的手续费率（基点），不能超过 MAX_FEE_BPS
     *
     * @custom:reverts FeeRecipientZeroAddress 如果 _feeRecipient 为零地址
     * @custom:reverts FeeTooHigh 如果 _feeBps > MAX_FEE_BPS
     */
    function setFeeConfig(address _feeRecipient, uint16 _feeBps) external onlyOwner {
        if (_feeRecipient == address(0)) revert FeeRecipientZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        feeRecipient = _feeRecipient;
        feeBps = _feeBps;

        emit FeeConfigUpdated(_feeRecipient, _feeBps);
    }

    /**
     * @notice 调整 VRF 回调参数
     * @dev 用于生产环境的运维调优，例如：
     *      - 网络拥堵时增加 callbackGasLimit
     *      - 安全要求提高时增加 requestConfirmations
     *
     * 【参数建议】
     * - callbackGasLimit：>= 100000，建议 200000
     * - requestConfirmations：主网 3-10，测试网 1-3
     * - numWords：骰子游戏固定为 1
     *
     * @param _callbackGasLimit 新的回调 gas 上限（>= 100000）
     * @param _requestConfirmations 新的确认数（1-200）
     * @param _numWords 随机数数量（必须为 1）
     *
     * @custom:reverts InvalidVrfConfig 如果参数不合法
     */
    function setVrfConfig(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords
    ) external onlyOwner {
        // 参数校验
        if (_callbackGasLimit < 100000) revert InvalidVrfConfig();
        if (_requestConfirmations < 1 || _requestConfirmations > 200) revert InvalidVrfConfig();
        if (_numWords != 1) revert InvalidVrfConfig();      // 骰子游戏只需 1 个随机数

        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        numWords = _numWords;

        emit VrfConfigUpdated(_callbackGasLimit, _requestConfirmations, _numWords);
    }

    /**
     * @notice 暂停合约
     * @dev 紧急情况下暂停所有用户操作（commit/reveal/retry）
     *      已在进行中的游戏不受影响，但新游戏无法开始
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice 恢复合约
     * @dev 解除暂停状态，恢复正常运营
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                           只读查询函数
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 查询玩家当前局的完整状态
     * @dev 前端可通过此函数获取玩家游戏状态，用于 UI 展示
     *
     * @param player 玩家地址
     * @return Game 结构体（包含所有字段）
     */
    function getGame(address player) external view returns (Game memory) {
        return games[player];
    }

    /**
     * @notice 查询玩家上一局的结果
     * @dev 前端可通过此函数展示玩家的上一次游戏结果
     *
     * @param player 玩家地址
     * @return LastResult 结构体
     */
    function getLastResult(address player) external view returns (LastResult memory) {
        return lastResults[player];
    }

    /**
     * @notice 获取玩家下一次 commit 应使用的 nonce
     * @dev 前端计算 commitHash 时需要使用此 nonce
     *
     * 【使用示例】
     * ```javascript
     * const nonce = await contract.getNextNonce(playerAddress);
     * const commitHash = ethers.solidityPackedKeccak256(
     *   ['address', 'uint8', 'bytes32', 'address', 'uint256', 'uint32'],
     *   [player, guess, secret, contractAddress, chainId, nonce]
     * );
     * ```
     *
     * @param player 玩家地址
     * @return 下一个 nonce 值（当前 nonce + 1）
     */
    function getNextNonce(address player) external view returns (uint32) {
        return games[player].nonce + 1;
    }

    /**
     * @notice 查询当前奖池可用于支付奖金的余额
     * @dev 计算公式：合约余额 - 玩家待提现 - 协议手续费保留
     *
     * @return 可用奖池余额（ETH）
     */
    function availablePrizeBalance() external view returns (uint256) {
        return _availablePrizeBalance();
    }

    /**
     * @notice 查询合约资金分布详情
     * @dev 用于运营监控和财务审计
     *
     * @return balance 合约总余额
     * @return reserved 已保留金额（pending + feesAccrued）
     * @return available 可用奖池余额
     * @return pending 玩家待提现总额
     * @return feesAccrued 协议累计手续费
     */
    function getReservedBalance() external view
        returns (
            uint256 balance,
            uint256 reserved,
            uint256 available,
            uint256 pending,
            uint256 feesAccrued
        )
    {
        balance = address(this).balance;
        pending = totalPendingWithdrawals;
        feesAccrued = protocolFeesAccrued;
        reserved = pending + feesAccrued;

        if (balance <= reserved) {
            available = 0;
        } else {
            available = balance - reserved;
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                       CommitHash 工具函数
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 计算承诺哈希（供前端/测试使用）
     * @dev 【哈希计算公式】
     *      commitHash = keccak256(abi.encode(player, guess, secret, address(this), block.chainid, nonce))
     *
     * 【安全设计】
     * 哈希中包含 address(this) 和 chainid，防止：
     * - 跨合约重放（不同合约地址）
     * - 跨链重放（不同链 ID）
     *
     * @param player 玩家地址
     * @param guess 猜测点数（1~6）
     * @param secret 玩家秘密（32 字节随机数）
     * @param nonce 当前 nonce（通过 getNextNonce 获取）
     * @return 计算得到的 commitHash
     */
    function computeCommitHash(
        address player,
        uint8 guess,
        bytes32 secret,
        uint32 nonce
    ) external view returns (bytes32) {
        return _computeCommitHash(player, guess, secret, nonce);
    }

    /**
     * @notice 内部承诺哈希计算函数
     * @dev 被 commit 验证和 computeCommitHash 公共函数共用
     */
    function _computeCommitHash(
        address player,
        uint8 guess,
        bytes32 secret,
        uint32 nonce
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    player,
                    guess,
                    secret,
                    address(this),      // 合约地址：防跨合约重放
                    block.chainid,      // 链 ID：防跨链重放
                    nonce               // 序号：防同合约重放
                )
            );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          内部工具函数
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice 发起 VRF 随机数请求
     * @dev 内部函数，被 revealAndRequestRandom 和 retryVrfRequest 调用
     *
     * 【VRF 请求参数】
     * - keyHash：Gas Lane，决定请求的 gas 价格档位
     * - subId：Subscription ID，需在 Chainlink 控制台创建并充值 LINK
     * - requestConfirmations：区块确认数
     * - callbackGasLimit：回调可用 gas
     * - numWords：随机数数量
     * - nativePayment：false 表示使用 LINK 支付（非原生 ETH）
     *
     * @return requestId VRF 请求 ID
     */
    function _requestVrf() internal returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})  // 使用 LINK 支付
                )
            })
        );
    }

    /**
     * @notice 计算奖池可用余额
     * @dev 内部函数，用于 revealAndRequestRandom 的奖池校验
     *
     * 【计算公式】
     * available = balance - reserved
     * reserved = totalPendingWithdrawals + protocolFeesAccrued
     *
     * 【设计目的】
     * 确保发起 VRF 请求前，奖池有足够资金支付可能的中奖
     *
     * @return 可用奖池余额（若负债超过余额则返回 0）
     */
    function _availablePrizeBalance() internal view returns (uint256) {
        uint256 reserved = totalPendingWithdrawals + protocolFeesAccrued;
        uint256 bal = address(this).balance;
        if (bal <= reserved) return 0;
        return bal - reserved;
    }
}
