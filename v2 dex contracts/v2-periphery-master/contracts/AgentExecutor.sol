// SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

/**
 * @dev Standard SafeMath library
 */
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface ISwappingDexV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

/**
 * @title AgentExecutor
 * @notice Restricted execution contract for AI Agent intents on GenLayer DEX.
 * @dev Enforces strict whitelists, limits, and explicit capabilities.
 * NO arbitrary calls allowed.
 */
contract AgentExecutor {
    using SafeMath for uint;

    address public owner;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Whitelists
    mapping(address => bool) public approvedRouters;
    mapping(address => bool) public approvedTokens;
    mapping(bytes32 => bool) public approvedTrades;

    // Safety limits
    uint public maxAllowedSlippageBps = 1000; // 10% maximum slippage cap

    // Events
    event AgentSwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint amountIn,
        uint amountOut,
        address router
    );

    event AgentLiquidityAdded(
        address indexed user,
        address indexed tokenA,
        address indexed tokenB,
        uint amountA,
        uint amountB,
        uint liquidity
    );

    event RouterApprovalUpdated(address indexed router, bool approved);
    event TokenApprovalUpdated(address indexed token, bool approved);
    event TradeApproved(bytes32 indexed tradeHash);
    event TradeApprovalRevoked(bytes32 indexed tradeHash);
    event TradeApprovalConsumed(bytes32 indexed tradeHash, address indexed user);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "AgentExecutor: caller is not the owner");
        _;
    }

    constructor(
        address[] memory _initialRouters,
        address[] memory _initialTokens
    ) public {
        owner = msg.sender;
        for (uint i = 0; i < _initialRouters.length; i++) {
            approvedRouters[_initialRouters[i]] = true;
            emit RouterApprovalUpdated(_initialRouters[i], true);
        }
        for (uint i = 0; i < _initialTokens.length; i++) {
            approvedTokens[_initialTokens[i]] = true;
            emit TokenApprovalUpdated(_initialTokens[i], true);
        }
    }

    function setRouterApproval(address router, bool approved) external onlyOwner {
        require(router != address(0), "Invalid router");
        approvedRouters[router] = approved;
        emit RouterApprovalUpdated(router, approved);
    }

    function setTokenApproval(address token, bool approved) external onlyOwner {
        require(token != address(0), "Invalid token");
        approvedTokens[token] = approved;
        emit TokenApprovalUpdated(token, approved);
    }

    function setMaxSlippageBps(uint _maxBps) external onlyOwner {
        require(_maxBps <= 2000, "Max slippage cap cannot exceed 20%");
        maxAllowedSlippageBps = _maxBps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getTradeHash(
        address router,
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint minAmountOut,
        address[] memory path,
        uint deadline
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(router, tokenIn, tokenOut, amountIn, minAmountOut, path, deadline));
    }

    function approveTrade(bytes32 tradeHash) external onlyOwner {
        require(tradeHash != bytes32(0), "Invalid trade hash");
        approvedTrades[tradeHash] = true;
        emit TradeApproved(tradeHash);
    }

    function revokeTradeApproval(bytes32 tradeHash) external onlyOwner {
        approvedTrades[tradeHash] = false;
        emit TradeApprovalRevoked(tradeHash);
    }

    /**
     * @notice Execute a token swap validated through the AI Agent intent
     */
    function executeSwap(
        address router,
        address tokenIn,
        address tokenOut,
        uint amountIn,
        uint minAmountOut,
        address[] calldata path,
        uint deadline
    ) external payable returns (uint amountOut) {
        bytes32 tradeHash = getTradeHash(router, tokenIn, tokenOut, amountIn, minAmountOut, path, deadline);
        require(approvedTrades[tradeHash], "AgentExecutor: trade not approved");
        delete approvedTrades[tradeHash];
        emit TradeApprovalConsumed(tradeHash, msg.sender);

        require(approvedRouters[router], "AgentExecutor: router not approved");
        require(approvedTokens[tokenIn] || tokenIn == NATIVE_TOKEN, "AgentExecutor: tokenIn not approved");
        require(approvedTokens[tokenOut] || tokenOut == NATIVE_TOKEN, "AgentExecutor: tokenOut not approved");
        require(deadline >= block.timestamp, "AgentExecutor: deadline passed");
        require(amountIn > 0, "AgentExecutor: amountIn must be > 0");

        if (tokenIn == NATIVE_TOKEN) {
            require(msg.value >= amountIn, "AgentExecutor: insufficient ETH sent");
            uint[] memory amounts = ISwappingDexV2Router02(router).swapExactETHForTokens{value: amountIn}(
                minAmountOut,
                path,
                msg.sender,
                deadline
            );
            amountOut = amounts[amounts.length - 1];
        } else if (tokenOut == NATIVE_TOKEN) {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "AgentExecutor: transferFrom failed");
            IERC20(tokenIn).approve(router, amountIn);
            uint[] memory amounts = ISwappingDexV2Router02(router).swapExactTokensForETH(
                amountIn,
                minAmountOut,
                path,
                msg.sender,
                deadline
            );
            amountOut = amounts[amounts.length - 1];
        } else {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "AgentExecutor: transferFrom failed");
            IERC20(tokenIn).approve(router, amountIn);
            uint[] memory amounts = ISwappingDexV2Router02(router).swapExactTokensForTokens(
                amountIn,
                minAmountOut,
                path,
                msg.sender,
                deadline
            );
            amountOut = amounts[amounts.length - 1];
        }

        require(amountOut >= minAmountOut, "AgentExecutor: slippage limit breached");

        emit AgentSwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut, router);
        return amountOut;
    }

    /**
     * @notice Execute adding V2 liquidity validated through the AI Agent intent
     */
    function executeAddLiquidity(
        address router,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) external payable returns (uint amountA, uint amountB, uint liquidity) {
        require(approvedRouters[router], "AgentExecutor: router not approved");
        require(approvedTokens[tokenA] || tokenA == NATIVE_TOKEN, "AgentExecutor: tokenA not approved");
        require(approvedTokens[tokenB] || tokenB == NATIVE_TOKEN, "AgentExecutor: tokenB not approved");
        require(deadline >= block.timestamp, "AgentExecutor: deadline passed");

        if (tokenA == NATIVE_TOKEN) {
            require(IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired), "TransferFrom tokenB failed");
            IERC20(tokenB).approve(router, amountBDesired);
            (amountB, amountA, liquidity) = ISwappingDexV2Router02(router).addLiquidityETH{value: amountADesired}(
                tokenB,
                amountBDesired,
                amountBMin,
                amountAMin,
                msg.sender,
                deadline
            );
        } else if (tokenB == NATIVE_TOKEN) {
            require(IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired), "TransferFrom tokenA failed");
            IERC20(tokenA).approve(router, amountADesired);
            (amountA, amountB, liquidity) = ISwappingDexV2Router02(router).addLiquidityETH{value: amountBDesired}(
                tokenA,
                amountADesired,
                amountAMin,
                amountBMin,
                msg.sender,
                deadline
            );
        } else {
            require(IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired), "TransferFrom tokenA failed");
            require(IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired), "TransferFrom tokenB failed");
            IERC20(tokenA).approve(router, amountADesired);
            IERC20(tokenB).approve(router, amountBDesired);
            (amountA, amountB, liquidity) = ISwappingDexV2Router02(router).addLiquidity(
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                amountAMin,
                amountBMin,
                msg.sender,
                deadline
            );
        }

        emit AgentLiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
    }

    receive() external payable {}
}
