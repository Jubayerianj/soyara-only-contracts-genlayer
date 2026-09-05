// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// ============================================================================
//  IAgentExecutorDEX.sol
//  FlipSwap DEX · External Interface Definitions
// ============================================================================
//  All external protocol interfaces used by AgentExecutor.
//  Kept in a separate file so they can be independently imported by tests,
//  integration scripts, and other contracts without pulling in the full
//  AgentExecutor implementation.
// ============================================================================

/// @notice Minimal AGGFlowEntrypoint interface (Soyara aggregator)
interface IAGGFlowEntrypoint {
    struct SwapIntent {
        address tokenUserBuys;
        uint256 minAmountUserBuys;
        address tokenUserSells;
        uint256 amountUserSells;
    }

    struct FeeCollection {
        address feeCollectorAddress;
        uint256 feeBps;
        address referrerAddress;
        uint256 referrerFeeBps;
        bool    isInTokenFee;
    }

    function executeSwapWithReceiver(
        SwapIntent    calldata swapIntent,
        FeeCollection calldata feeCollection,
        bytes         calldata program,
        address               receiver
    ) external payable returns (uint256 amountOut);
}

/// @notice Minimal SoyaraDex V2 Router interface
interface IUniswapV2Router {
    function addLiquidity(
        address tokenA, address tokenB,
        uint256 amountADesired, uint256 amountBDesired,
        uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA, address tokenB,
        uint256 liquidity,
        uint256 amountAMin, uint256 amountBMin,
        address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

/// @notice Minimal SoyaraDex V3 NonfungiblePositionManager interface
interface IV3PositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        returns (uint256 amount0, uint256 amount1);
}
