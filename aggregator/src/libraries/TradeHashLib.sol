// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { IV3PositionManager } from "../interfaces/IAgentExecutorDEX.sol";

// ============================================================================
//  TradeHashLib.sol
//  FlipSwap DEX · Deterministic Trade Parameter Hashing
// ============================================================================
//
//  PURPOSE
//  -------
//  Provides pure, deterministic keccak256 hash functions for binding a
//  one-time settlement approval to the EXACT set of trade parameters.
//
//  SECURITY PROPERTIES
//  -------------------
//  - Uses abi.encode (not abi.encodePacked) to avoid dynamic-type collisions
//  - Domain separators ("V2_ADD", "V2_REMOVE", "V3_ADD", "V3_REMOVE") ensure
//    cross-operation hash uniqueness even if numeric fields coincide
//  - Any tamper of any single field produces a completely different hash,
//    making the approval invalid and causing TradeNotApproved to revert
//
// ============================================================================

library TradeHashLib {

    // ── Swap ──────────────────────────────────────────────────────────────────

    /// @notice Hash for a swap execution approval.
    /// Encodes: user · tokenIn · tokenOut · amountIn · minAmountOut · slippageBps · deadline
    function swapHash(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 slippageBps,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(user, tokenIn, tokenOut, amountIn, minAmountOut, slippageBps, deadline)
        );
    }

    // ── V2 Liquidity ──────────────────────────────────────────────────────────

    /// @notice Hash for a V2 add-liquidity approval.
    function v2AddHash(
        address user,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "V2_ADD",
                user, tokenA, tokenB,
                amountADesired, amountBDesired,
                amountAMin, amountBMin,
                deadline
            )
        );
    }

    /// @notice Hash for a V2 remove-liquidity approval.
    function v2RemoveHash(
        address user,
        address tokenA,
        address tokenB,
        address lpToken,
        uint256 lpAmount,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "V2_REMOVE",
                user, tokenA, tokenB,
                lpToken, lpAmount,
                amountAMin, amountBMin,
                deadline
            )
        );
    }

    // ── V3 Liquidity ──────────────────────────────────────────────────────────

    /// @notice Hash for a V3 mint (add liquidity) approval.
    function v3AddHash(
        address user,
        IV3PositionManager.MintParams calldata p
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "V3_ADD",
                user,
                p.token0, p.token1, p.fee,
                p.tickLower, p.tickUpper,
                p.amount0Desired, p.amount1Desired,
                p.amount0Min, p.amount1Min,
                p.deadline
            )
        );
    }

    /// @notice Hash for a V3 decrease-liquidity (remove liquidity) approval.
    function v3RemoveHash(
        address user,
        IV3PositionManager.DecreaseLiquidityParams calldata p,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "V3_REMOVE",
                user, tokenId,
                p.liquidity,
                p.amount0Min, p.amount1Min,
                p.deadline
            )
        );
    }
}
