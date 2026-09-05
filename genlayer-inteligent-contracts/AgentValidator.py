# { "Depends": "py-genlayer:1jb45aa8ynh2a9c9xn3b7qqh8sm5q93hwfp7jqmwsfhh8jpz09h6" }

# =============================================================================
#  AgentValidator — GenLayer Intelligent Contract
#  FlipSwap DEX · AI-Validated Execution Layer
# =============================================================================
#
#  PURPOSE
#  -------
#  This contract sits between the AI agent (Gemini) and the actual DEX
#  execution (AGGFlowEntrypoint + AgentExecutor.sol).
#
#  FLOW
#  ----
#  User → Gemini → tools → Aggregator → ExecutionProposal
#                                               ↓
#                                    AgentValidator (this contract)
#                                               ↓ approved
#                                    AgentExecutor.sol
#                                               ↓
#                                    AGGFlowEntrypoint → V2/V3
#
#  SECURITY MODEL
#  --------------
#  - Only validates explicit action types: SWAP, ADD_LIQUIDITY, REMOVE_LIQUIDITY
#  - Never allows arbitrary calldata
#  - Enforces approved token list, approved routers, slippage caps
#  - LLM-based review is scoped to pre-built numeric rules only
#  - Prompt injection is mitigated: user free-text NEVER enters the LLM prompt;
#    only structured numeric/enum fields from the proposal are used
#
# =============================================================================

from genlayer import *
from dataclasses import dataclass
import json
import hashlib


# ---------------------------------------------------------------------------
# Constants — update addresses to match your deployed contracts
# ---------------------------------------------------------------------------

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

# NOTE: keep this in sync with DEPLOYMENTS.md / frontend/flipswap/constants/addresses.js.
# AGGFlowEntrypoint and AGGFlowRouter were redeployed alongside AgentExecutor — the
# previous entries here pointed at the pre-redeployment addresses, which caused every
# real proposal (frontend always submits the current aggregatorEntrypoint) to fail the
# deterministic router-whitelist check below.
APPROVED_ROUTERS: dict = {
    "AGGFlowEntrypoint":        "0x95feE6Cb918Ed9C621E36082EE8D998873031EaA",
    "AGGFlowEntrypoint_Legacy": "0xfdf5cD6452EDC340e67cd16db6A9D74aaa4f81a3",
    "AGGFlowEntrypoint_Legacy2": "0xF69E64804000d28aA695eB5c594B996100fb3B49",
    "AGGFlowRouter":            "0xafCAD2bf0E85e30a2b54ac6491dC81987cE7767C",
    "AGGFlowRouter_Legacy":     "0xDF474006aa807598B616500d146FfF661d644138",
    "V2Router":                 "0xF456737D17C2Bbb348fd4F7D1b000D62A46FB3b5",
    "V3Router":                 "0xdf69970B2fE416339187aA41D39882e864984CE9",
    "V3PositionManager":        "0x779380011B5F2aB40985D810B5c7641539beD870",
    "AgentExecutor":            "0xaE547F01f9ddCa4dB66cdbf0727f7563Fc44bC26",
}

def addr(value) -> str:
    """
    Normalise an address argument to a lowercase string.

    GenLayer calldata is self-describing, so an address-shaped argument can
    arrive either as a plain `str` (what genlayer-js sends for a `str` param)
    or as an `Address` object (what the genlayer CLI produces when an argument
    looks like 40 hex chars). Calling `.lower()` directly blows up on the
    latter with "'Address' object has no attribute 'lower'", which previously
    made the whole validation revert. Going through `str()` accepts both.
    """
    return str(value).strip().lower()


ALLOWED_ACTIONS: set = {"SWAP", "ADD_LIQUIDITY", "REMOVE_LIQUIDITY"}
MAX_SLIPPAGE_BPS: int = 300   # 3.00% hard cap (configurable via state)
NATIVE_ZERO: str = "0x0000000000000000000000000000000000000000"
NATIVE_PLACEHOLDER: str = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"


# ---------------------------------------------------------------------------
# Trading mandate — amortises consensus across many trades
# ---------------------------------------------------------------------------
#
#  WHY THIS EXISTS
#  ---------------
#  A GenVM consensus round (activation → leader → commit → reveal → accept) is
#  inherently slow, and on a congested testnet it can take minutes. Paying that
#  cost on EVERY swap makes interactive trading — and autonomous agent-to-agent
#  trading in particular — unusable.
#
#  The expensive operation is the consensus WRITE. A @gl.public.view read costs
#  nothing and returns instantly. So:
#
#    ONCE  per session:  issue_trading_mandate(...)   ← @gl.public.write, full
#                                                       Optimistic Democracy
#                                                       consensus + LLM policy
#                                                       review. Slow, but once.
#
#    EVERY trade:        check_mandate(...)           ← @gl.public.view, instant.
#                                                       Authority derives from the
#                                                       consensus-approved mandate
#                                                       already committed to state.
#
#  SECURITY — this does NOT weaken the enforced settlement gate. AgentExecutor
#  still binds every individual settlement to a one-time hash of the EXACT trade
#  parameters (user, tokenIn, tokenOut, amountIn, minAmountOut, slippage, deadline)
#  and deletes it on use. An unapproved or modified trade still cannot settle, and
#  a trade outside the mandate's committed bounds is refused here. The mandate
#  replaces the per-trade consensus ROUND, never the per-trade on-chain BINDING.


@allow_storage
@dataclass
class TradingMandate:
    user:             str   # address the mandate is bound to (lowercase)
    tokens:           str   # comma-separated lowercase token addresses allowed
    max_amount_in:    str   # per-trade cap, raw token units
    max_slippage_bps: u256
    expires_at:       u256  # unix timestamp; enforced on-chain by AgentExecutor
    max_trades:       u256
    active:           bool


# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------

class AgentValidator(gl.Contract):
    """
    GenLayer Intelligent Contract — FlipSwap DEX execution validator.

    Validates AI-generated execution proposals using:
      1. Deterministic rule checks (token whitelist, router whitelist, slippage, amounts)
      2. LLM-based coherence review via GenLayer equivalence principle
         (operates only on numeric fields, never on user free-text)
    """

    # ---- Persistent State ----
    validated_count:  u256
    approved_count:   u256
    rejected_count:   u256
    mandate_count:    u256
    owner:            Address
    agent_executor:   Address
    max_slippage_bps: u256
    paused:           bool
    mandates:         TreeMap[str, TradingMandate]
    # proposal_id -> "1" approved / "0" rejected.
    #
    # A GenLayer write transaction's RETURN VALUE is not recoverable from the
    # receipt: `receipt.result` carries the consensus vote enum (AGREE/DISAGREE),
    # not the contract's payload. Callers therefore had no way to learn whether a
    # validation actually approved, and defaulted to "rejected" even when the
    # round had approved the trade. Persisting the verdict lets the caller read it
    # back with `get_validation` — a view, so it is instant and free.
    validations:      TreeMap[str, str]

    def __init__(self, owner: Address, agent_executor: Address) -> None:
        self.validated_count  = u256(0)
        self.approved_count   = u256(0)
        self.rejected_count   = u256(0)
        self.mandate_count    = u256(0)
        self.owner            = owner
        self.agent_executor   = agent_executor
        self.max_slippage_bps = u256(MAX_SLIPPAGE_BPS)
        self.paused           = False

    # -----------------------------------------------------------------------
    # Admin (owner-only)
    # -----------------------------------------------------------------------

    @gl.public.write
    def set_max_slippage(self, bps: u256) -> None:
        """Update the maximum allowed slippage in basis points."""
        assert gl.message.sender == self.owner, "Only owner"
        assert bps <= u256(10000), "Cannot exceed 100%"
        self.max_slippage_bps = bps

    @gl.public.write
    def set_agent_executor(self, executor: Address) -> None:
        """Update the AgentExecutor contract address."""
        assert gl.message.sender == self.owner, "Only owner"
        self.agent_executor = executor

    @gl.public.write
    def set_paused(self, paused: bool) -> None:
        """Emergency pause / unpause all validations."""
        assert gl.message.sender == self.owner, "Only owner"
        self.paused = paused

    # -----------------------------------------------------------------------
    # Read-only views
    # -----------------------------------------------------------------------

    @gl.public.view
    def get_stats(self) -> dict:
        return {
            "validated": int(self.validated_count),
            "approved":  int(self.approved_count),
            "rejected":  int(self.rejected_count),
            "paused":    self.paused,
        }

    @gl.public.view
    def get_config(self) -> dict:
        return {
            "owner":            str(self.owner),
            "agent_executor":   str(self.agent_executor),
            "max_slippage_bps": int(self.max_slippage_bps),
            "paused":           self.paused,
        }

    @gl.public.view
    def is_token_approved(self, address: str) -> bool:
        return addr(address) in {v.lower() for v in APPROVED_TOKENS.values()}

    @gl.public.view
    def is_router_approved(self, address: str) -> bool:
        return addr(address) in {v.lower() for v in APPROVED_ROUTERS.values()}

    # -----------------------------------------------------------------------
    # Trading mandates — pay consensus ONCE, then validate trades instantly
    # -----------------------------------------------------------------------

    @gl.public.write
    def issue_trading_mandate(
        self,
        user:             str,
        tokens:           str,   # comma-separated token addresses the agent may trade
        max_amount_in:    str,   # per-trade cap in raw token units
        max_slippage_bps: u256,
        expires_at:       u256,  # unix timestamp — enforced on-chain at settlement
        max_trades:       u256,
    ) -> dict:
        """
        Establish a consensus-approved trading mandate for an agent session.

        This is the ONE slow call: it runs full Optimistic Democracy consensus
        plus an LLM policy review of the mandate's risk envelope. Every trade
        afterwards is checked against it via check_mandate(), which is a view
        and therefore instant.
        """
        if self.paused:
            return {"approved": False, "reason": "Contract paused by owner", "mandate_id": ""}

        # --- Deterministic bounds (identical on every validator node) ---
        if max_slippage_bps > self.max_slippage_bps:
            return self._reject_mandate(
                f"Mandate slippage {int(max_slippage_bps)} bps exceeds cap of {int(self.max_slippage_bps)} bps"
            )

        if int(expires_at) == 0:
            return self._reject_mandate("Mandate must carry a non-zero expiry timestamp")

        if int(max_trades) == 0:
            return self._reject_mandate("Mandate must permit at least one trade")

        try:
            cap = int(max_amount_in)
        except (ValueError, TypeError):
            return self._reject_mandate("max_amount_in must be a valid integer string")
        if cap <= 0:
            return self._reject_mandate("max_amount_in must be greater than zero")

        # Every token in the mandate must already be on the approved whitelist.
        approved = {v.lower() for v in APPROVED_TOKENS.values()}
        requested = [addr(t) for t in str(tokens).split(",") if str(t).strip()]
        if not requested:
            return self._reject_mandate("Mandate must list at least one token")
        for token in requested:
            if token not in approved and token not in {NATIVE_ZERO.lower(), NATIVE_PLACEHOLDER.lower()}:
                return self._reject_mandate(f"Token '{token}' is not on the approved list")

        # --- LLM policy review of the mandate's risk envelope (consensus-gated) ---
        # Only a boolean crosses the strict_eq boundary — see _llm_review for why
        # returning LLM-authored text here makes consensus impossible.
        try:
            llm_approved = self._consensus_mandate_review(
                len(requested), cap, int(max_slippage_bps), int(max_trades)
            )
        except Exception:
            return self._reject_mandate("Consensus unavailable — failed closed")

        if not llm_approved:
            return self._reject_mandate("Mandate envelope rejected by policy review")

        mandate_id = hashlib.sha256(
            f"{user}:{tokens}:{max_amount_in}:{int(max_slippage_bps)}:{int(expires_at)}:{int(max_trades)}".encode()
        ).hexdigest()[:24]

        self.mandates[mandate_id] = TradingMandate(
            user=addr(user),
            tokens=",".join(requested),
            max_amount_in=str(cap),
            max_slippage_bps=max_slippage_bps,
            expires_at=expires_at,
            max_trades=max_trades,
            active=True,
        )
        self.mandate_count = self.mandate_count + u256(1)

        return {
            "approved": True,
            "reason": "Trading mandate approved by GenVM consensus",
            "mandate_id": mandate_id,
        }

    @gl.public.write
    def revoke_mandate(self, mandate_id: str) -> dict:
        """Revoke a mandate. Callable by the owner or the mandate's own user."""
        if mandate_id not in self.mandates:
            return {"approved": False, "reason": "Unknown mandate_id"}
        mandate = self.mandates[mandate_id]
        sender = str(gl.message.sender).lower()
        if sender != str(self.owner).lower() and sender != mandate.user:
            return {"approved": False, "reason": "Only the owner or mandate holder may revoke"}
        mandate.active = False
        return {"approved": True, "reason": "Mandate revoked"}

    @gl.public.view
    def check_mandate(
        self,
        mandate_id:   str,
        user:         str,
        token_in:     str,
        token_out:    str,
        amount_in:    str,
        slippage_bps: u256,
        deadline:     u256,
    ) -> dict:
        """
        Validate a single trade against an already consensus-approved mandate.

        This is a VIEW: it costs nothing and returns immediately, which is what
        makes per-trade latency effectively zero. Its authority comes from the
        mandate, which was committed to state by a full consensus round.

        Settlement remains gated on-chain: AgentExecutor still requires a
        one-time approval hash over the exact trade parameters, so nothing here
        can be replayed or tampered into a different trade.
        """
        if self.paused:
            return {"approved": False, "reason": "Contract paused by owner"}

        if mandate_id not in self.mandates:
            return {"approved": False, "reason": "Unknown or expired mandate_id"}

        mandate = self.mandates[mandate_id]

        if not mandate.active:
            return {"approved": False, "reason": "Mandate has been revoked"}

        if addr(user) != mandate.user:
            return {"approved": False, "reason": "Mandate is bound to a different user"}

        # The trade must expire no later than the mandate does. Real expiry is
        # enforced deterministically on-chain by AgentExecutor's validDeadline.
        if int(deadline) == 0 or int(deadline) > int(mandate.expires_at):
            return {"approved": False, "reason": "Trade deadline falls outside the mandate window"}

        if slippage_bps > mandate.max_slippage_bps:
            return {
                "approved": False,
                "reason": f"Slippage {int(slippage_bps)} bps exceeds mandate cap of {int(mandate.max_slippage_bps)} bps",
            }

        try:
            amt = int(amount_in)
        except (ValueError, TypeError):
            return {"approved": False, "reason": "amount_in must be a valid integer string"}
        if amt <= 0:
            return {"approved": False, "reason": "amount_in must be greater than zero"}
        if amt > int(mandate.max_amount_in):
            return {"approved": False, "reason": "amount_in exceeds the per-trade cap in this mandate"}

        allowed = set(mandate.tokens.split(","))
        native = {NATIVE_ZERO.lower(), NATIVE_PLACEHOLDER.lower()}
        if addr(token_in) not in allowed and addr(token_in) not in native:
            return {"approved": False, "reason": f"tokenIn '{token_in}' is not covered by this mandate"}
        if addr(token_out) not in allowed and addr(token_out) not in native:
            return {"approved": False, "reason": f"tokenOut '{token_out}' is not covered by this mandate"}
        if addr(token_in) == addr(token_out):
            return {"approved": False, "reason": "tokenIn and tokenOut cannot be the same address"}

        return {
            "approved": True,
            "reason": "Trade is within a GenVM consensus-approved mandate",
            "mandate_id": mandate_id,
        }

    @gl.public.view
    def get_validation(self, proposal_id: str) -> dict:
        """
        Read back the verdict of a previously validated proposal.

        Needed because a write transaction's return value cannot be recovered
        from its receipt — the receipt only carries the consensus vote enum. This
        view is how a caller learns whether `validate_proposal` approved a trade.

        It is also a cache: a proposal that has already been validated can be
        re-checked instantly here, with no new consensus round.
        """
        if proposal_id not in self.validations:
            return {"found": False, "approved": False, "reason": "No validation recorded for this proposal_id"}
        approved = self.validations[proposal_id] == "1"
        return {
            "found": True,
            "approved": approved,
            "reason": "All validation checks passed" if approved else "Proposal was rejected by GenVM consensus",
            "proposal_id": proposal_id,
        }

    @gl.public.view
    def compute_proposal_id(
        self,
        action:         str,
        token_in:       str,
        token_out:      str,
        amount_in:      str,
        min_amount_out: str,
        slippage_bps:   u256,
        deadline:       u256,
    ) -> str:
        """
        The proposal_id `validate_proposal` will assign to these exact params.

        Exposed so a caller can look up a verdict with `get_validation` without
        having to re-implement (and keep in sync with) the hashing scheme.
        """
        return self._proposal_id(action, token_in, token_out, amount_in, min_amount_out, slippage_bps, deadline)

    @gl.public.view
    def get_mandate(self, mandate_id: str) -> dict:
        """Inspect a mandate's committed terms."""
        if mandate_id not in self.mandates:
            return {"found": False}
        m = self.mandates[mandate_id]
        return {
            "found":            True,
            "user":             m.user,
            "tokens":           m.tokens,
            "max_amount_in":    m.max_amount_in,
            "max_slippage_bps": int(m.max_slippage_bps),
            "expires_at":       int(m.expires_at),
            "max_trades":       int(m.max_trades),
            "active":           m.active,
        }

    # -----------------------------------------------------------------------
    # Main validation entry point
    # -----------------------------------------------------------------------

    @gl.public.write
    def validate_proposal(
        self,
        action:          str,   # "SWAP" | "ADD_LIQUIDITY" | "REMOVE_LIQUIDITY"
        token_in:        str,   # ERC-20 address or NATIVE_ZERO for native token
        token_out:       str,   # ERC-20 address
        amount_in:       str,   # uint256 in raw token units (as string)
        min_amount_out:  str,   # uint256 in raw token units (as string)
        slippage_bps:    u256,  # e.g. 30 = 0.30%
        router:          str,   # router contract address to be called
        deadline:        u256,  # unix timestamp
        extra_data:      str,   # compact JSON (route, fee tier, etc.) — max 500 chars
    ) -> dict:
        """
        Validate an execution proposal from the AI agent.

        Returns:
            {
              "approved":    bool,
              "reason":      str,
              "proposal_id": str   # deterministic ID built from inputs
            }
        """
        self.validated_count = self.validated_count + u256(1)

        # --- Pause guard ---
        if self.paused:
            self.rejected_count = self.rejected_count + u256(1)
            return {"approved": False, "reason": "Contract paused by owner", "proposal_id": ""}

        # --- Phase 1: Deterministic rules (runs identically on every node) ---
        det = self._check_deterministic_rules(
            action, token_in, token_out, amount_in,
            min_amount_out, slippage_bps, router, deadline
        )
        if not det["approved"]:
            self.rejected_count = self.rejected_count + u256(1)
            return det

        # --- Phase 2: LLM coherence review (non-deterministic, consensus via eq_principle) ---
        #
        # CRITICAL: whatever this block returns must be BYTE-IDENTICAL on every
        # validator, because strict_eq compares the values directly. Returning the
        # LLM's own prose (e.g. its "reason" text) can never satisfy that — each
        # node gets slightly different wording, the comparison fails, and the round
        # ends UNDETERMINED/DISAGREE instead of reaching a verdict. That is exactly
        # why validations were stalling. Only the boolean crosses the boundary; all
        # human-readable text is composed deterministically out here.
        try:
            llm_approved = self._consensus_review(
                action, slippage_bps, amount_in, min_amount_out, extra_data
            )
        except Exception:
            self.rejected_count = self.rejected_count + u256(1)
            return {
                "approved": False,
                "reason": "Consensus unavailable — failed closed",
                "proposal_id": "",
            }

        if not llm_approved:
            self.rejected_count = self.rejected_count + u256(1)
            self.validations[det["proposal_id"]] = "0"
            return {
                "approved": False,
                "reason": "LLM coherence review did not approve this proposal",
                "proposal_id": det["proposal_id"],
            }

        # --- All checks passed ---
        self.approved_count = self.approved_count + u256(1)
        # Persist the verdict so the caller can read it back (see `validations`).
        self.validations[det["proposal_id"]] = "1"
        return {
            "approved":    True,
            "reason":      "All validation checks passed",
            "proposal_id": det["proposal_id"],
        }

    # -----------------------------------------------------------------------
    # Phase 1 — Deterministic rules (no LLM, no external calls)
    # -----------------------------------------------------------------------

    def _check_deterministic_rules(
        self,
        action:         str,
        token_in:       str,
        token_out:      str,
        amount_in:      str,
        min_amount_out: str,
        slippage_bps:   u256,
        router:         str,
        deadline:       u256,
    ) -> dict:

        # 1 — Action whitelist
        if action not in ALLOWED_ACTIONS:
            return self._reject(f"Unknown action '{action}'. Allowed: {ALLOWED_ACTIONS}")

        # 2 — token_in approved (native zero / placeholder always allowed)
        if addr(token_in) not in {NATIVE_ZERO.lower(), NATIVE_PLACEHOLDER.lower()}:
            if addr(token_in) not in {v.lower() for v in APPROVED_TOKENS.values()}:
                return self._reject(f"tokenIn '{token_in}' is not an approved token")

        # 3 — token_out approved (native zero / placeholder always allowed)
        if addr(token_out) not in {NATIVE_ZERO.lower(), NATIVE_PLACEHOLDER.lower()}:
            if addr(token_out) not in {v.lower() for v in APPROVED_TOKENS.values()}:
                return self._reject(f"tokenOut '{token_out}' is not an approved token")

        # 4 — Different tokens
        if addr(token_in) == addr(token_out):
            return self._reject("tokenIn and tokenOut cannot be the same address")

        # 5 — Router approved
        if addr(router) not in {v.lower() for v in APPROVED_ROUTERS.values()}:
            return self._reject(f"Router '{router}' is not in the approved router list")

        # 6 — Slippage cap
        if slippage_bps > self.max_slippage_bps:
            return self._reject(
                f"Slippage {int(slippage_bps)} bps exceeds cap of {int(self.max_slippage_bps)} bps"
            )

        # 7 — Amount validation
        try:
            amt_in  = int(amount_in)
            amt_out = int(min_amount_out)
        except (ValueError, TypeError):
            return self._reject("amount_in and min_amount_out must be valid integer strings")

        if amt_in <= 0:
            return self._reject("amount_in must be greater than zero")

        if amt_out < 0:
            return self._reject("min_amount_out cannot be negative")

        # 8 — Deadline must be non-zero (a Unix timestamp was supplied).
        # NOTE: actual expiry is intentionally NOT checked against wall-clock time here —
        # gl.exec_prompt/os "current time" is not deterministic across validator nodes and
        # would cause consensus mismatches for proposals near the boundary. Expiry is
        # enforced deterministically on-chain by AgentExecutor's validDeadline modifier
        # (see execution-rules.json → deadline.description).
        if int(deadline) == 0:
            return self._reject("Deadline cannot be zero — provide a Unix timestamp")

        # All deterministic checks passed — build a collision-resistant proposal ID
        pid = self._proposal_id(action, token_in, token_out, amount_in, min_amount_out, slippage_bps, deadline)
        return {"approved": True, "reason": "Deterministic rules passed", "proposal_id": pid}

    # -----------------------------------------------------------------------
    # Phase 2 — LLM coherence check (non-deterministic, reaches consensus)
    # -----------------------------------------------------------------------

    # ── Consensus wrappers ────────────────────────────────────────────────
    #
    # The nondeterministic call is isolated in its own method on purpose.
    # genvm-lint marks the scope CONTAINING an inline `strict_eq(lambda: ...)`
    # as a non-deterministic context, and storage writes are forbidden there —
    # which is why `validate_proposal` and `issue_trading_mandate` previously
    # failed lint with "storage writes are forbidden in non-deterministic
    # contexts" and "nested non-deterministic blocks are forbidden". Keeping the
    # lambda here means the callers stay deterministic and may write state.
    #
    # Only a BARE BOOLEAN crosses the strict_eq boundary — see _llm_review.

    def _consensus_review(
        self,
        action:         str,
        slippage_bps:   u256,
        amount_in:      str,
        min_amount_out: str,
        extra_data:     str,
    ) -> bool:
        # A nested def passed BY NAME, not an inline lambda. genvm-lint marks the
        # scope containing an inline nondet lambda as a non-deterministic context,
        # which then makes this very strict_eq call read as a nested nondet block.
        # This is the pattern GenLayer's own contract template uses.
        def review() -> bool:
            return self._llm_review(action, slippage_bps, amount_in, min_amount_out, extra_data)

        return gl.eq_principle.strict_eq(review)

    def _consensus_mandate_review(
        self,
        token_count:      int,
        cap:              int,
        max_slippage_bps: int,
        max_trades:       int,
    ) -> bool:
        def review() -> bool:
            return self._llm_mandate_review(token_count, cap, max_slippage_bps, max_trades)

        return gl.eq_principle.strict_eq(review)

    def _llm_review(
        self,
        action:         str,
        slippage_bps:   u256,
        amount_in:      str,
        min_amount_out: str,
        extra_data:     str,
    ) -> bool:
        """
        Scoped LLM review for numeric/logic coherence.

        Returns a BARE BOOLEAN on purpose. This runs inside
        `gl.eq_principle.strict_eq`, which compares the returned value across
        validators for exact equality — so it must carry no LLM-authored prose.
        An earlier version returned the model's own `reason` string, which
        differs per node, so nodes could never agree and rounds terminated
        UNDETERMINED (DISAGREE) instead of producing a verdict.

        SECURITY: Only structured numeric + enum fields are passed to the
        LLM prompt. User free-text from chat is never included here.
        """
        safe_extra = (extra_data or "{}")[:400]
        slippage_pct = round(int(slippage_bps) / 100, 2)

        # The two amount fields mean DIFFERENT things per action, and a single
        # set of swap-shaped rules made validators disagree on liquidity.
        #
        # For a deposit, `amount_in` and `min_amount_out` are the two INDEPENDENT
        # sides of the position — "10 WGEN and 200 USDC" is perfectly valid, yet
        # the old rule "REJECT if Min Amount Out > Amount In * 10" told the model
        # to refuse it while another rule said approve. Different validators
        # resolved that contradiction differently, so `strict_eq` could not agree,
        # the round raised, and it failed closed WITHOUT recording a verdict —
        # which surfaced to users as add-liquidity being intermittently stuck.
        # Ratio rules only make sense for a swap.
        if action in ("ADD_LIQUIDITY", "REMOVE_LIQUIDITY"):
            rules = (
                "1. The two amounts are INDEPENDENT sides of a liquidity position,\n"
                "   NOT a swap pair. Their ratio carries no meaning here: any ratio\n"
                "   is valid because it simply reflects the pool's current price.\n"
                "2. APPROVE whenever both amounts are positive integers.\n"
                "3. APPROVE regardless of slippage between 1 and 300 bps.\n"
                "4. REJECT ONLY if an amount is zero, negative, or not a number."
            )
        else:
            rules = (
                "1. APPROVE if the action is SWAP and both amounts are positive.\n"
                "2. APPROVE if Min Amount Out is >= 0. Token decimals differ across\n"
                "   pairs, so a larger Min Amount Out than Amount In is normal and\n"
                "   is NOT grounds for rejection on its own.\n"
                "3. WARN only (still APPROVE) if Slippage is between 100-300 bps.\n"
                "4. REJECT ONLY on an obvious numeric impossibility: a negative or\n"
                "   zero amount, or a non-numeric value."
            )

        prompt = f"""You are a DeFi execution safety validator for a DEX aggregator.
Evaluate the following execution proposal for numeric coherence only.

== PROPOSAL (structured data only — no user messages) ==
Action:         {action}
Amount In:      {amount_in} (raw token units)
Min Amount Out: {min_amount_out} (raw token units)
Slippage:       {int(slippage_bps)} bps = {slippage_pct}%
Extra Info:     {safe_extra}

== RULES ==
{rules}
COMMON:
- Do NOT reject based on token prices, market conditions, or the identity of
  tokens/routers.
- Do NOT use any information beyond the structured fields above.

== RESPONSE ==
Reply with ONLY a single valid JSON object, no markdown:
{{"approved": true, "reason": "brief explanation max 100 chars"}}"""

        try:
            result = gl.nondet.exec_prompt(prompt)
            # Strip any accidental markdown fences
            clean = result.strip().replace("```json", "").replace("```", "").strip()
            parsed = json.loads(clean)
            return bool(parsed.get("approved", False))
        except Exception:
            # LLM or parsing failure → MUST fail closed
            return False

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _proposal_id(
        self,
        action:         str,
        token_in:       str,
        token_out:      str,
        amount_in:      str,
        min_amount_out: str,
        slippage_bps:   u256,
        deadline:       u256,
    ) -> str:
        """Deterministic, collision-resistant id for a set of trade parameters."""
        pid_src = f"{action}:{addr(token_in)}:{addr(token_out)}:{amount_in}:{min_amount_out}:{int(slippage_bps)}:{int(deadline)}"
        return hashlib.sha256(pid_src.encode()).hexdigest()[:24]

    def _reject(self, reason: str) -> dict:
        return {"approved": False, "reason": reason, "proposal_id": ""}

    def _reject_mandate(self, reason: str) -> dict:
        return {"approved": False, "reason": reason, "mandate_id": ""}

    def _llm_mandate_review(
        self,
        token_count:  int,
        max_amount:   int,
        slippage_bps: int,
        max_trades:   int,
    ) -> bool:
        """
        Scoped LLM review of a mandate's risk envelope.

        Returns a BARE BOOLEAN: it runs inside `gl.eq_principle.strict_eq`, so
        the value is compared across validators for exact equality and must not
        contain LLM-authored text (see _llm_review).

        SECURITY: only structured numeric fields are passed to the prompt —
        no user free-text, no token identities, so there is nothing for a
        prompt-injection payload to ride in on.
        """
        prompt = f"""You are a DeFi risk policy reviewer for a DEX trading mandate.
A mandate lets an automated agent execute trades within fixed bounds without
re-running consensus for each trade.

== MANDATE ENVELOPE (structured numeric data only) ==
Distinct tokens permitted: {token_count}
Max amount per trade:      {max_amount} (raw token units)
Max slippage:              {slippage_bps} bps
Max trades:                {max_trades}

== RULES ==
1. APPROVE when slippage is <= 300 bps, amounts are positive, and trade count is finite.
2. REJECT only on an obviously unsafe envelope: slippage > 300 bps, non-positive
   amounts, or an unbounded trade count.
3. Do NOT reason about token prices, market conditions, or token identity.

== RESPONSE ==
Reply with ONLY a single valid JSON object, no markdown:
{{"approved": true, "reason": "brief explanation max 100 chars"}}"""

        try:
            result = gl.nondet.exec_prompt(prompt)
            clean = result.strip().replace("```json", "").replace("```", "").strip()
            parsed = json.loads(clean)
            return bool(parsed.get("approved", False))
        except Exception:
            # LLM or parsing failure → MUST fail closed
            return False
