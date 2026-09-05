// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// ============================================================================
//  AgentExecutor.sol
//  FlipSwap DEX · AI Agent Bridge Contract (Execution Layer)
// ============================================================================
//
//  ARCHITECTURE
//  ------------
//  This file contains ONLY the five execute* functions.
//  All state, events, errors, admin, and approval management live in:
//
//    src/base/AgentExecutorBase.sol   ← inherit
//    src/libraries/TradeHashLib.sol   ← pure hash functions
//    src/interfaces/IAgentExecutorDEX.sol ← external protocol interfaces
//
//  FLOW
//  ----
//  GenLayer AgentValidator (off-chain IC, consensus-gated)
//       │  approves proposal → agent calls approveTradeWithParams(...)
//       ▼
//  AgentExecutor.executeSwap / executeAddLiquidity / executeRemoveLiquidity
//       │  1. Validate params (fail BEFORE consuming approval)
//       │  2. Verify & delete one-time approval hash
//       │  3. Pull tokens, delegate to router
//       ▼
//  AGGFlowEntrypoint (aggregated swaps)
//  V2 Router / V3 PositionManager (liquidity)
//
//  SECURITY
//  --------
//  - Only onlyAgent can call execute* functions
//  - Every execute function checks approvedTrades[hash] — fails if missing
//  - Approval is consumed (deleted) immediately after check — single-use only
//  - Parameter validation runs BEFORE consuming the approval so bad params
//    do NOT permanently burn the one-time approval slot
//  - Reentrancy protected via ReentrancyGuard in AgentExecutorBase
//
// ============================================================================

import { IERC20 }            from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 }         from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AgentExecutorBase } from "./base/AgentExecutorBase.sol";
import { TradeHashLib }      from "./libraries/TradeHashLib.sol";
import {
    IAGGFlowEntrypoint,
    IUniswapV2Router,
    IV3PositionManager
} from "./interfaces/IAgentExecutorDEX.sol";

contract AgentExecutor is AgentExecutorBase {
    using SafeERC20 for IERC20;

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(
        address _owner,
        address _authorisedAgent,
        address _aggFlowEntrypoint,
        address _v2Router,
        address _v3PositionManager,
        uint256 _maxSlippageBps,
        address[] memory _initialApprovedTokens
    )
        AgentExecutorBase(
            _owner,
            _authorisedAgent,
            _aggFlowEntrypoint,
            _v2Router,
            _v3PositionManager,
            _maxSlippageBps,
            _initialApprovedTokens
        )
    {}

    // ── Execution: Swap ───────────────────────────────────────────────────────

    /**
     * @notice Execute an AI-validated swap through the AGGFlowEntrypoint.
     *
     * @dev Security flow:
     *   1. Validate parameters (ZeroAddress, SameToken, amounts, slippage, whitelist)
     *   2. Verify and consume one-time approval hash — reverts if not approved
     *   3. Pull tokenIn from user → approve entrypoint → execute swap → transfer out to user
     *
     * @param user         Recipient of the output tokens
     * @param tokenIn      ERC-20 to sell (address(0) for native ETH)
     * @param tokenOut     ERC-20 to buy
     * @param amountIn     Exact amount to sell
     * @param minAmountOut Minimum acceptable output (slippage bound)
     * @param slippageBps  Declared slippage in basis points (must be <= maxSlippageBps)
     * @param deadline     Unix timestamp — reverts after this time
     * @param aggProgram   Aggregator routing calldata
     * @param feeBps       Fee in basis points charged by feeCollector
     * @param feeCollector Address that receives the fee
     */
    function executeSwap(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 slippageBps,
        uint256 deadline,
        bytes   calldata aggProgram,
        uint256 feeBps,
        address feeCollector
    )
        external
        payable
        onlyAgent
        nonReentrant
        whenNotPaused
        validDeadline(deadline)
        returns (uint256 amountOut)
    {
        // ── 1. Parameter Validations (BEFORE consuming approval) ──────────────
        if (user     == address(0)) revert ZeroAddress();
        if (tokenIn  == tokenOut)   revert SameToken();
        if (amountIn == 0)          revert ZeroAmount();
        if (slippageBps > maxSlippageBps) revert SlippageExceeded(slippageBps, maxSlippageBps);

        // address(0) denotes the NATIVE asset, which is not an ERC-20 and so is
        // never present in the ERC-20 whitelist. Both sides must exempt it, or
        // the swap is unexecutable: previously only tokenIn was exempted, so
        // every swap OUT to native reverted with TokenNotApproved(0x0) before
        // any other check could run.
        if (tokenIn  != address(0) && !approvedTokens[tokenIn])  revert TokenNotApproved(tokenIn);
        if (tokenOut != address(0) && !approvedTokens[tokenOut]) revert TokenNotApproved(tokenOut);

        // ── 2. One-Time Approval Check ────────────────────────────────────────
        bytes32 tradeHash = TradeHashLib.swapHash(
            user, tokenIn, tokenOut, amountIn, minAmountOut, slippageBps, deadline
        );
        if (!approvedTrades[tradeHash]) revert TradeNotApproved(tradeHash);
        delete approvedTrades[tradeHash];
        emit TradeApprovalConsumed(tradeHash, user);

        // ── 3. Execute ────────────────────────────────────────────────────────
        if (tokenIn != address(0)) {
            IERC20(tokenIn).safeTransferFrom(user, address(this), amountIn);
            IERC20(tokenIn).forceApprove(aggFlowEntrypoint, amountIn);
        }

        IAGGFlowEntrypoint.SwapIntent memory swapIntent = IAGGFlowEntrypoint.SwapIntent({
            tokenUserBuys:     tokenOut,
            minAmountUserBuys: minAmountOut,
            tokenUserSells:    tokenIn,
            amountUserSells:   amountIn
        });

        IAGGFlowEntrypoint.FeeCollection memory feeData = IAGGFlowEntrypoint.FeeCollection({
            feeCollectorAddress: feeCollector != address(0) ? feeCollector : address(this),
            feeBps:              feeBps,
            referrerAddress:     address(0),
            referrerFeeBps:      0,
            isInTokenFee:        true
        });

        amountOut = IAGGFlowEntrypoint(aggFlowEntrypoint).executeSwapWithReceiver{
            value: tokenIn == address(0) ? amountIn : 0
        }(swapIntent, feeData, aggProgram, user);

        if (tokenIn != address(0)) IERC20(tokenIn).forceApprove(aggFlowEntrypoint, 0);

        emit SwapExecuted(user, tokenIn, tokenOut, amountIn, amountOut);
    }

    // ── Execution: V2 Add Liquidity ───────────────────────────────────────────

    /**
     * @notice Execute an AI-validated V2 add-liquidity operation.
     *
     * @dev Params validated before approval consumed. Unused tokens refunded.
     */
    function executeAddLiquidityV2(
        address user,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    )
        external
        onlyAgent
        nonReentrant
        whenNotPaused
        validDeadline(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        // ── 1. Param Validations ──────────────────────────────────────────────
        if (user   == address(0))   revert ZeroAddress();
        if (tokenA == tokenB)       revert SameToken();
        if (!approvedTokens[tokenA]) revert TokenNotApproved(tokenA);
        if (!approvedTokens[tokenB]) revert TokenNotApproved(tokenB);
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        // ── 2. One-Time Approval Check ────────────────────────────────────────
        bytes32 opHash = TradeHashLib.v2AddHash(
            user, tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin,
            deadline
        );
        if (!approvedTrades[opHash]) revert TradeNotApproved(opHash);
        delete approvedTrades[opHash];
        emit TradeApprovalConsumed(opHash, user);

        // ── 3. Execute ────────────────────────────────────────────────────────
        IERC20(tokenA).safeTransferFrom(user, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(user, address(this), amountBDesired);
        IERC20(tokenA).forceApprove(v2Router, amountADesired);
        IERC20(tokenB).forceApprove(v2Router, amountBDesired);

        (amountA, amountB, liquidity) = IUniswapV2Router(v2Router).addLiquidity(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin,
            user, deadline
        );

        // Refund unused tokens
        uint256 remainA = amountADesired - amountA;
        uint256 remainB = amountBDesired - amountB;
        if (remainA > 0) IERC20(tokenA).safeTransfer(user, remainA);
        if (remainB > 0) IERC20(tokenB).safeTransfer(user, remainB);

        IERC20(tokenA).forceApprove(v2Router, 0);
        IERC20(tokenB).forceApprove(v2Router, 0);

        emit LiquidityAdded(user, tokenA, tokenB, "V2", amountA, amountB);
    }

    // ── Execution: V2 Remove Liquidity ────────────────────────────────────────

    /**
     * @notice Execute an AI-validated V2 remove-liquidity operation.
     */
    function executeRemoveLiquidityV2(
        address user,
        address tokenA,
        address tokenB,
        address lpToken,
        uint256 lpAmount,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    )
        external
        onlyAgent
        nonReentrant
        whenNotPaused
        validDeadline(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        // ── 1. Param Validations ──────────────────────────────────────────────
        if (user   == address(0))   revert ZeroAddress();
        if (tokenA == tokenB)       revert SameToken();
        if (!approvedTokens[tokenA]) revert TokenNotApproved(tokenA);
        if (!approvedTokens[tokenB]) revert TokenNotApproved(tokenB);
        if (lpAmount == 0)           revert ZeroAmount();

        // ── 2. One-Time Approval Check ────────────────────────────────────────
        bytes32 opHash = TradeHashLib.v2RemoveHash(
            user, tokenA, tokenB,
            lpToken, lpAmount,
            amountAMin, amountBMin,
            deadline
        );
        if (!approvedTrades[opHash]) revert TradeNotApproved(opHash);
        delete approvedTrades[opHash];
        emit TradeApprovalConsumed(opHash, user);

        // ── 3. Execute ────────────────────────────────────────────────────────
        IERC20(lpToken).safeTransferFrom(user, address(this), lpAmount);
        IERC20(lpToken).forceApprove(v2Router, lpAmount);

        (amountA, amountB) = IUniswapV2Router(v2Router).removeLiquidity(
            tokenA, tokenB,
            lpAmount,
            amountAMin, amountBMin,
            user, deadline
        );

        IERC20(lpToken).forceApprove(v2Router, 0);
        emit LiquidityRemoved(user, tokenA, tokenB, "V2");
    }

    // ── Execution: V3 Add Liquidity (Mint Position) ───────────────────────────

    /**
     * @notice Execute an AI-validated V3 mint-position operation.
     *
     * @dev mintParams.recipient is always overridden to `user` — the NFT goes
     *      directly to the user regardless of what the agent passed in params.
     */
    function executeAddLiquidityV3(
        address user,
        IV3PositionManager.MintParams calldata params
    )
        external
        onlyAgent
        nonReentrant
        whenNotPaused
        validDeadline(params.deadline)
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        // ── 1. Param Validations ──────────────────────────────────────────────
        if (user == address(0)) revert ZeroAddress();
        if (!approvedTokens[params.token0]) revert TokenNotApproved(params.token0);
        if (!approvedTokens[params.token1]) revert TokenNotApproved(params.token1);
        if (params.amount0Desired == 0 && params.amount1Desired == 0) revert ZeroAmount();

        // ── 2. One-Time Approval Check ────────────────────────────────────────
        bytes32 opHash = TradeHashLib.v3AddHash(user, params);
        if (!approvedTrades[opHash]) revert TradeNotApproved(opHash);
        delete approvedTrades[opHash];
        emit TradeApprovalConsumed(opHash, user);

        // ── 3. Execute ────────────────────────────────────────────────────────
        if (params.amount0Desired > 0) {
            IERC20(params.token0).safeTransferFrom(user, address(this), params.amount0Desired);
            IERC20(params.token0).forceApprove(v3PositionManager, params.amount0Desired);
        }
        if (params.amount1Desired > 0) {
            IERC20(params.token1).safeTransferFrom(user, address(this), params.amount1Desired);
            IERC20(params.token1).forceApprove(v3PositionManager, params.amount1Desired);
        }

        IV3PositionManager.MintParams memory mintParams = params;
        mintParams.recipient = user; // NFT always goes directly to user

        (tokenId, liquidity, amount0, amount1) = IV3PositionManager(v3PositionManager).mint(mintParams);

        // Refund unused tokens
        uint256 remain0 = params.amount0Desired - amount0;
        uint256 remain1 = params.amount1Desired - amount1;
        if (remain0 > 0) IERC20(params.token0).safeTransfer(user, remain0);
        if (remain1 > 0) IERC20(params.token1).safeTransfer(user, remain1);

        if (params.amount0Desired > 0) IERC20(params.token0).forceApprove(v3PositionManager, 0);
        if (params.amount1Desired > 0) IERC20(params.token1).forceApprove(v3PositionManager, 0);

        emit LiquidityAdded(user, params.token0, params.token1, "V3", amount0, amount1);
    }

    // ── Execution: V3 Remove Liquidity ────────────────────────────────────────

    /**
     * @notice Execute an AI-validated V3 decrease-liquidity + collect operation.
     *
     * @param token0  token0 of the position — required for whitelist enforcement
     * @param token1  token1 of the position — required for whitelist enforcement
     */
    function executeRemoveLiquidityV3(
        address user,
        IV3PositionManager.DecreaseLiquidityParams calldata decreaseParams,
        uint256 tokenId,
        address token0,
        address token1
    )
        external
        onlyAgent
        nonReentrant
        whenNotPaused
        validDeadline(decreaseParams.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        // ── 1. Param Validations ──────────────────────────────────────────────
        if (user == address(0)) revert ZeroAddress();
        if (!approvedTokens[token0]) revert TokenNotApproved(token0);
        if (!approvedTokens[token1]) revert TokenNotApproved(token1);
        if (decreaseParams.liquidity == 0) revert ZeroAmount();

        // ── 2. One-Time Approval Check ────────────────────────────────────────
        bytes32 opHash = TradeHashLib.v3RemoveHash(user, decreaseParams, tokenId);
        if (!approvedTrades[opHash]) revert TradeNotApproved(opHash);
        delete approvedTrades[opHash];
        emit TradeApprovalConsumed(opHash, user);

        // ── 3. Execute ────────────────────────────────────────────────────────
        (amount0, amount1) = IV3PositionManager(v3PositionManager).decreaseLiquidity(decreaseParams);

        IV3PositionManager(v3PositionManager).collect(
            IV3PositionManager.CollectParams({
                tokenId:    tokenId,
                recipient:  user,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit LiquidityRemoved(user, token0, token1, "V3");
    }
}
