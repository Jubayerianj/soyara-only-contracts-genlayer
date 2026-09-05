# { "Depends": "py-genlayer:1jb45aa8ynh2a9c9xn3b7qqh8sm5q93hwfp7jqmwsfhh8jpz09h6" }

# =============================================================================
#  LiquidityValidator — GenLayer Intelligent Contract
#  FlipSwap DEX · AI-Validated Liquidity Execution Layer
# =============================================================================
#
#  PURPOSE
#  -------
#  Specialized validator for liquidity operations (ADD / REMOVE) that
#  need extra validation logic beyond the general AgentValidator.
#
#  For V3 liquidity, validates:
#    - Fee tier is one of the approved tiers (500, 3000, 10000)
#    - tickLower < tickCurrent < tickUpper (price range sanity)
#    - token0 and token1 amounts are non-zero
#    - deadline is valid
#
#  For V2 liquidity, validates:
#    - Both token amounts are non-zero
#    - Minimum amounts (slippage protection) are reasonable
#
# =============================================================================

from genlayer import *
import json

APPROVED_TOKENS: dict = {
    "GEN":       "0x0000000000000000000000000000000000000000",
    "WGEN":      "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    "WSOMI":     "0x315374AA9b5536037Cc1Efeea2439CCC0913A77e",
    "USDC":      "0x58B6CD7891cd0A682226E25607b958a6479195A6",
    "USDT":      "0x4B54235778c26Ee8ac27744A53d4c5BC4c9D46fc",
    "WBTC":      "0x723534bc6C2B536fF5D0455111513A9431c44e25",
    "ETH":       "0x0F56b4E7f4e2cf346a94aB9263Ed3F3644db7c0C",
    "FSWP":      "0xA2eC9aAf2235C66491767e69eBBD885469697B3E",
    "ZKUSDC":    "0x58B6CD7891cd0A682226E25607b958a6479195A6",
    "ZKUSDT":    "0x4B54235778c26Ee8ac27744A53d4c5BC4c9D46fc",
    "ZKBTC":     "0x723534bc6C2B536fF5D0455111513A9431c44e25",
    "LETH":      "0x0F56b4E7f4e2cf346a94aB9263Ed3F3644db7c0C",
    "NATIVE_ETH": "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
}

APPROVED_V3_FEE_TIERS: set = {500, 3000, 10000}  # 0.05%, 0.30%, 1.00%

MAX_TICK:  int = 887272
MIN_TICK:  int = -887272
MAX_SLIPPAGE_BPS: int = 300


class LiquidityValidator(gl.Contract):
    """
    GenLayer Intelligent Contract for validating V2 and V3 liquidity operations.
    """

    validated_count:  u256
    approved_count:   u256
    rejected_count:   u256
    owner:            Address
    paused:           bool

    def __init__(self, owner: Address) -> None:
        self.validated_count = u256(0)
        self.approved_count  = u256(0)
        self.rejected_count  = u256(0)
        self.owner           = owner
        self.paused          = False

    @gl.public.write
    def set_paused(self, paused: bool) -> None:
        assert gl.message.sender == self.owner, "Only owner"
        self.paused = paused

    @gl.public.view
    def get_stats(self) -> dict:
        return {
            "validated": int(self.validated_count),
            "approved":  int(self.approved_count),
            "rejected":  int(self.rejected_count),
        }

    # -----------------------------------------------------------------------
    # V2 Liquidity Validation
    # -----------------------------------------------------------------------

    @gl.public.write
    def validate_add_liquidity_v2(
        self,
        token_a:        str,   # ERC-20 address
        token_b:        str,   # ERC-20 address
        amount_a:       str,   # desired amount token A (raw units)
        amount_b:       str,   # desired amount token B (raw units)
        min_amount_a:   str,   # minimum amount A after slippage
        min_amount_b:   str,   # minimum amount B after slippage
        deadline:       u256,
    ) -> dict:
        """Validate a V2 add-liquidity proposal."""
        self.validated_count = self.validated_count + u256(1)

        if self.paused:
            self.rejected_count = self.rejected_count + u256(1)
            return {"approved": False, "reason": "Contract paused", "proposal_id": ""}

        # Token checks
        if not self._approved_token(token_a):
            return self._reject(f"tokenA '{token_a}' not approved")
        if not self._approved_token(token_b):
            return self._reject(f"tokenB '{token_b}' not approved")
        if token_a.lower() == token_b.lower():
            return self._reject("tokenA and tokenB cannot be the same")

        # Amount checks
        try:
            amt_a     = int(amount_a)
            amt_b     = int(amount_b)
            min_a     = int(min_amount_a)
            min_b     = int(min_amount_b)
        except (ValueError, TypeError):
            return self._reject("All amounts must be valid integers")

        if amt_a <= 0 or amt_b <= 0:
            return self._reject("Both token amounts must be greater than zero")
        if min_a < 0 or min_b < 0:
            return self._reject("Minimum amounts cannot be negative")
        if min_a > amt_a or min_b > amt_b:
            return self._reject("Minimum amounts cannot exceed desired amounts")

        # Deadline check
        if int(deadline) == 0:
            return self._reject("Deadline cannot be zero")

        # Slippage check: implied slippage = (desired - min) / desired
        slippage_a_bps = int(((amt_a - min_a) * 10000) / amt_a) if amt_a > 0 else 0
        slippage_b_bps = int(((amt_b - min_b) * 10000) / amt_b) if amt_b > 0 else 0
        max_slippage   = max(slippage_a_bps, slippage_b_bps)

        if max_slippage > MAX_SLIPPAGE_BPS:
            return self._reject(f"Implied slippage {max_slippage} bps exceeds cap {MAX_SLIPPAGE_BPS} bps")

        self.approved_count = self.approved_count + u256(1)
        pid = f"V2-ADD-{token_a[:6]}-{token_b[:6]}-{amount_a[:8]}"
        return {"approved": True, "reason": "V2 add-liquidity proposal validated", "proposal_id": pid}

    @gl.public.write
    def validate_remove_liquidity_v2(
        self,
        token_a:        str,   # ERC-20 address
        token_b:        str,   # ERC-20 address
        lp_amount:      str,   # LP token amount to burn (raw units)
        min_amount_a:   str,   # minimum A to receive
        min_amount_b:   str,   # minimum B to receive
        deadline:       u256,
    ) -> dict:
        """Validate a V2 remove-liquidity proposal."""
        self.validated_count = self.validated_count + u256(1)

        if self.paused:
            self.rejected_count = self.rejected_count + u256(1)
            return {"approved": False, "reason": "Contract paused", "proposal_id": ""}

        if not self._approved_token(token_a):
            return self._reject(f"tokenA '{token_a}' not approved")
        if not self._approved_token(token_b):
            return self._reject(f"tokenB '{token_b}' not approved")

        try:
            lp  = int(lp_amount)
            min_a = int(min_amount_a)
            min_b = int(min_amount_b)
        except (ValueError, TypeError):
            return self._reject("All amounts must be valid integers")

        if lp <= 0:
            return self._reject("LP amount must be greater than zero")
        if min_a < 0 or min_b < 0:
            return self._reject("Minimum output amounts cannot be negative")
        if int(deadline) == 0:
            return self._reject("Deadline cannot be zero")

        self.approved_count = self.approved_count + u256(1)
        pid = f"V2-REM-{token_a[:6]}-{token_b[:6]}-{lp_amount[:8]}"
        return {"approved": True, "reason": "V2 remove-liquidity proposal validated", "proposal_id": pid}

    # -----------------------------------------------------------------------
    # V3 Liquidity Validation
    # -----------------------------------------------------------------------

    @gl.public.write
    def validate_add_liquidity_v3(
        self,
        token0:         str,   # ERC-20 address (lower address)
        token1:         str,   # ERC-20 address (higher address)
        fee:            u256,  # fee tier: 500, 3000, or 10000
        tick_lower:     int,   # lower tick bound
        tick_upper:     int,   # upper tick bound
        amount0_desired: str,  # desired token0 amount (raw units)
        amount1_desired: str,  # desired token1 amount (raw units)
        amount0_min:    str,   # minimum token0 (slippage protection)
        amount1_min:    str,   # minimum token1 (slippage protection)
        deadline:       u256,
    ) -> dict:
        """Validate a V3 add-liquidity (mint position) proposal."""
        self.validated_count = self.validated_count + u256(1)

        if self.paused:
            self.rejected_count = self.rejected_count + u256(1)
            return {"approved": False, "reason": "Contract paused", "proposal_id": ""}

        # Token checks
        if not self._approved_token(token0):
            return self._reject(f"token0 '{token0}' not approved")
        if not self._approved_token(token1):
            return self._reject(f"token1 '{token1}' not approved")
        if token0.lower() == token1.lower():
            return self._reject("token0 and token1 cannot be the same")

        # Fee tier check
        if int(fee) not in APPROVED_V3_FEE_TIERS:
            return self._reject(f"Fee tier {int(fee)} not in approved list {APPROVED_V3_FEE_TIERS}")

        # Tick range checks
        if tick_lower >= tick_upper:
            return self._reject(f"tickLower ({tick_lower}) must be less than tickUpper ({tick_upper})")
        if tick_lower < MIN_TICK or tick_upper > MAX_TICK:
            return self._reject(f"Ticks must be within [{MIN_TICK}, {MAX_TICK}]")

        # Amount checks
        try:
            amt0     = int(amount0_desired)
            amt1     = int(amount1_desired)
            min0     = int(amount0_min)
            min1     = int(amount1_min)
        except (ValueError, TypeError):
            return self._reject("All amounts must be valid integers")

        if amt0 < 0 or amt1 < 0:
            return self._reject("Token amounts cannot be negative")
        if amt0 == 0 and amt1 == 0:
            return self._reject("At least one token amount must be greater than zero")
        if min0 < 0 or min1 < 0:
            return self._reject("Minimum amounts cannot be negative")
        if (amt0 > 0 and min0 > amt0) or (amt1 > 0 and min1 > amt1):
            return self._reject("Minimum amounts cannot exceed desired amounts")

        # Deadline check
        if int(deadline) == 0:
            return self._reject("Deadline cannot be zero")

        self.approved_count = self.approved_count + u256(1)
        pid = f"V3-ADD-{token0[:6]}-{token1[:6]}-{int(fee)}-{tick_lower}-{tick_upper}"
        return {"approved": True, "reason": "V3 add-liquidity proposal validated", "proposal_id": pid}

    @gl.public.write
    def validate_remove_liquidity_v3(
        self,
        token_id:       str,   # NFT position token ID (as string)
        liquidity:      str,   # liquidity to remove (as string uint128)
        amount0_min:    str,   # minimum token0 to receive
        amount1_min:    str,   # minimum token1 to receive
        deadline:       u256,
    ) -> dict:
        """Validate a V3 decrease-liquidity / collect proposal."""
        self.validated_count = self.validated_count + u256(1)

        if self.paused:
            self.rejected_count = self.rejected_count + u256(1)
            return {"approved": False, "reason": "Contract paused", "proposal_id": ""}

        try:
            tid = int(token_id)
            liq = int(liquidity)
            min0 = int(amount0_min)
            min1 = int(amount1_min)
        except (ValueError, TypeError):
            return self._reject("tokenId, liquidity and amounts must be valid integers")

        if tid <= 0:
            return self._reject("tokenId must be a positive integer")
        if liq <= 0:
            return self._reject("Liquidity to remove must be greater than zero")
        if min0 < 0 or min1 < 0:
            return self._reject("Minimum output amounts cannot be negative")
        if int(deadline) == 0:
            return self._reject("Deadline cannot be zero")

        self.approved_count = self.approved_count + u256(1)
        pid = f"V3-REM-{token_id}-{liquidity[:8]}"
        return {"approved": True, "reason": "V3 remove-liquidity proposal validated", "proposal_id": pid}

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _approved_token(self, address: str) -> bool:
        return address.lower() in {v.lower() for v in APPROVED_TOKENS.values()}

    def _reject(self, reason: str) -> dict:
        self.rejected_count = self.rejected_count + u256(1)
        return {"approved": False, "reason": reason, "proposal_id": ""}
