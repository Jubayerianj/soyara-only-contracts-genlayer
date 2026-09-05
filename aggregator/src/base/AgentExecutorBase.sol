// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// ============================================================================
//  AgentExecutorBase.sol
//  FlipSwap DEX · Shared State, Events, Errors, Admin & Approval Management
// ============================================================================
//
//  PURPOSE
//  -------
//  Houses everything that is NOT execution logic:
//    · All state variables
//    · All events & custom errors
//    · All access-control modifiers
//    · Owner admin functions (set agent, tokens, routers, slippage, pause)
//    · One-time trade approval management (approveTrade / revokeTradeApproval)
//
//  INHERITANCE
//  -----------
//  AgentExecutor inherits AgentExecutorBase and adds the five execute*
//  functions.  Tests and integrations can import this base to get all
//  type definitions without pulling in execution logic.
//
// ============================================================================

import { IERC20 }          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable }         from "@openzeppelin/contracts/access/Ownable.sol";
import { TradeHashLib }    from "../libraries/TradeHashLib.sol";
import { IV3PositionManager } from "../interfaces/IAgentExecutorDEX.sol";

abstract contract AgentExecutorBase is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice Primary agent. Kept for backward compatibility: existing
    ///         deployments and tooling reference this single address.
    address public authorisedAgent;

    /// @notice Additional authorised agents.
    ///
    /// A single `authorisedAgent` meant only one operator could ever settle, so
    /// third-party agents had to route through the primary operator's server.
    /// Registering an address here lets an independent agent bind and consume
    /// its own one-time approvals directly, WITHOUT weakening the gate: every
    /// trade is still bound to a consensus-approved parameter hash that is
    /// checked and deleted on use, so an agent can only execute trades GenLayer
    /// has already approved.
    mapping(address => bool) public agents;

    /// @notice AGGFlowEntrypoint for aggregated swaps
    address public aggFlowEntrypoint;

    /// @notice SoyaraDex V2 Router
    address public v2Router;

    /// @notice SoyaraDex V3 NonfungiblePositionManager
    address public v3PositionManager;

    /// @notice Maximum allowed slippage for swaps (in basis points)
    uint256 public maxSlippageBps;

    /// @notice ERC-20 token whitelist
    mapping(address => bool) public approvedTokens;

    /// @notice Router / entrypoint whitelist
    mapping(address => bool) public approvedRouters;

    /// @notice One-time trade approval registry — each entry consumed on use
    mapping(bytes32 => bool) public approvedTrades;

    /// @notice Emergency pause flag
    bool public paused;

    // ── Events ────────────────────────────────────────────────────────────────

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event LiquidityAdded(
        address indexed user,
        address tokenA,
        address tokenB,
        string  version,
        uint256 amountA,
        uint256 amountB
    );

    event LiquidityRemoved(
        address indexed user,
        address tokenA,
        address tokenB,
        string  version
    );

    event TokenApproved(address indexed token, bool approved);
    event RouterApproved(address indexed router, bool approved);
    event AgentUpdated(address indexed oldAgent, address indexed newAgent);
    event Paused(bool isPaused);

    /// @notice Emitted when the agent registers a trade approval.
    /// @dev tokenIn/tokenOut/amountIn/minAmountOut are populated only when
    ///      approveTradeWithParams is used. Prefer it over raw approveTrade()
    ///      for complete auditability.
    event TradeApproved(
        bytes32 indexed tradeHash,
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    );
    event TradeApprovalRevoked(bytes32 indexed tradeHash);
    event TradeApprovalConsumed(bytes32 indexed tradeHash, address indexed user);

    // ── Errors ────────────────────────────────────────────────────────────────

    error Unauthorized();
    error ContractPaused();
    error TokenNotApproved(address token);
    error RouterNotApproved(address router);
    error SlippageExceeded(uint256 bps, uint256 maxBps);
    error DeadlineExpired();
    error ZeroAmount();
    event AgentAuthorisationUpdated(address indexed agent, bool allowed);

    error ZeroAddress();
    error SameToken();
    error TradeNotApproved(bytes32 tradeHash);
    error InvalidTradeHash();

    // ── Modifiers ─────────────────────────────────────────────────────────────

    modifier onlyAgent() {
        if (msg.sender != authorisedAgent && !agents[msg.sender]) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier validDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert DeadlineExpired();
        _;
    }

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(
        address _owner,
        address _authorisedAgent,
        address _aggFlowEntrypoint,
        address _v2Router,
        address _v3PositionManager,
        uint256 _maxSlippageBps,
        address[] memory _initialApprovedTokens
    ) Ownable(_owner) {
        if (_authorisedAgent   == address(0)) revert ZeroAddress();
        if (_aggFlowEntrypoint == address(0)) revert ZeroAddress();
        if (_v2Router          == address(0)) revert ZeroAddress();
        if (_v3PositionManager == address(0)) revert ZeroAddress();

        authorisedAgent   = _authorisedAgent;
        aggFlowEntrypoint = _aggFlowEntrypoint;
        v2Router          = _v2Router;
        v3PositionManager = _v3PositionManager;
        maxSlippageBps    = _maxSlippageBps;
        paused            = false;

        approvedRouters[_aggFlowEntrypoint] = true;
        approvedRouters[_v2Router]          = true;
        approvedRouters[_v3PositionManager] = true;

        for (uint256 i = 0; i < _initialApprovedTokens.length; i++) {
            approvedTokens[_initialApprovedTokens[i]] = true;
        }
    }

    // ── Owner Admin ───────────────────────────────────────────────────────────

    function setAuthorisedAgent(address _agent) external onlyOwner {
        if (_agent == address(0)) revert ZeroAddress();
        emit AgentUpdated(authorisedAgent, _agent);
        authorisedAgent = _agent;
    }

    /// @notice Register or revoke an additional agent.
    /// @dev Owner-only. Revoking cannot strand funds: agents never custody
    ///      anything — tokens move from the user straight through the router in
    ///      a single call.
    function setAgentAuthorisation(address _agent, bool _allowed) external onlyOwner {
        if (_agent == address(0)) revert ZeroAddress();
        agents[_agent] = _allowed;
        emit AgentAuthorisationUpdated(_agent, _allowed);
    }

    /// @notice True when `_who` may bind and consume trade approvals.
    function isAgent(address _who) external view returns (bool) {
        return _who == authorisedAgent || agents[_who];
    }

    function setMaxSlippage(uint256 _bps) external onlyOwner {
        require(_bps <= 10_000, "Cannot exceed 100%");
        maxSlippageBps = _bps;
    }

    function setApprovedToken(address _token, bool _approved) external onlyOwner {
        approvedTokens[_token] = _approved;
        emit TokenApproved(_token, _approved);
    }

    function setApprovedRouter(address _router, bool _approved) external onlyOwner {
        approvedRouters[_router] = _approved;
        emit RouterApproved(_router, _approved);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    // ── Hash Helpers (public — agent/frontend compute off-chain too) ──────────

    /// @notice Compute the approval hash for a swap.
    function getTradeHash(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 slippageBps,
        uint256 deadline
    ) public pure returns (bytes32) {
        return TradeHashLib.swapHash(user, tokenIn, tokenOut, amountIn, minAmountOut, slippageBps, deadline);
    }

    /// @notice Compute the approval hash for a V2 add-liquidity operation.
    function getLiquidityV2AddHash(
        address user,
        address tokenA, address tokenB,
        uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin,
        uint256 deadline
    ) public pure returns (bytes32) {
        return TradeHashLib.v2AddHash(
            user, tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin,
            deadline
        );
    }

    /// @notice Compute the approval hash for a V2 remove-liquidity operation.
    function getLiquidityV2RemoveHash(
        address user,
        address tokenA, address tokenB,
        address lpToken, uint256 lpAmount,
        uint256 amountAMin, uint256 amountBMin,
        uint256 deadline
    ) public pure returns (bytes32) {
        return TradeHashLib.v2RemoveHash(
            user, tokenA, tokenB,
            lpToken, lpAmount,
            amountAMin, amountBMin,
            deadline
        );
    }

    /// @notice Compute the approval hash for a V3 mint operation.
    function getLiquidityV3AddHash(
        address user,
        IV3PositionManager.MintParams calldata params
    ) public pure returns (bytes32) {
        return TradeHashLib.v3AddHash(user, params);
    }

    /// @notice Compute the approval hash for a V3 decrease-liquidity operation.
    function getLiquidityV3RemoveHash(
        address user,
        IV3PositionManager.DecreaseLiquidityParams calldata params,
        uint256 tokenId
    ) public pure returns (bytes32) {
        return TradeHashLib.v3RemoveHash(user, params, tokenId);
    }

    // ── Approval Management ───────────────────────────────────────────────────

    /**
     * @notice Approve a pre-computed trade hash for one-time settlement.
     * @dev Prefer approveTradeWithParams — this raw-hash overload emits
     *      zeroed event fields which limits off-chain auditability.
     */
    function approveTrade(bytes32 tradeHash) external onlyAgent whenNotPaused {
        if (tradeHash == bytes32(0)) revert InvalidTradeHash();
        approvedTrades[tradeHash] = true;
        emit TradeApproved(tradeHash, address(0), address(0), address(0), 0, 0);
    }

    /**
     * @notice Approve a swap by its exact parameters (PREFERRED — fully auditable).
     * @dev Computes hash on-chain so the event carries complete parameter data.
     */
    function approveTradeWithParams(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 slippageBps,
        uint256 deadline
    ) external onlyAgent whenNotPaused {
        bytes32 tradeHash = TradeHashLib.swapHash(
            user, tokenIn, tokenOut, amountIn, minAmountOut, slippageBps, deadline
        );
        approvedTrades[tradeHash] = true;
        emit TradeApproved(tradeHash, user, tokenIn, tokenOut, amountIn, minAmountOut);
    }

    /**
     * @notice Revoke a pending trade approval (e.g. user cancelled intent).
     */
    function revokeTradeApproval(bytes32 tradeHash) external onlyAgent {
        delete approvedTrades[tradeHash];
        emit TradeApprovalRevoked(tradeHash);
    }

    /**
     * @notice Check whether a trade hash is currently approved.
     */
    function isTradeApproved(bytes32 tradeHash) external view returns (bool) {
        return approvedTrades[tradeHash];
    }

    // ── Safety ────────────────────────────────────────────────────────────────

    /// @notice Owner can rescue stuck ERC-20 tokens.
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Owner can rescue stuck ETH.
    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
    }

    receive() external payable {}
}
