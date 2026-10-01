# Implementation Proposal: Native Deferred PartyB Sell Escrow

## Summary

Implement the escrow idea as a narrow SYMMIO open-intent feature inside `src/symmio/contracts`, not as a market or symbol creation change.

The new supported case is:

```text
tradeSide == SELL
marginType == CROSS
partyBsWhiteList.length == 0
```

This allows PartyA to broadcast a funded sell intent before PartyB is known. SYMMIO locks PartyA's seller maintenance margin and open-fee estimate in intent-scoped escrow. When a valid PartyB locks and fills the intent, the escrow is converted into ordinary `(PartyA, PartyB, collateral)` cross-margin accounting and the resulting trade behaves like a normal cross trade.

Recommended v1 scope:

**lafa comment**
1. Allow only `SELL + CROSS + empty whitelist`.
2. Keep `SELL + ISOLATED` rejected.
3. Keep `BUY + CROSS + empty whitelist` rejected.
4. Keep `SELL + CROSS + multiple PartyBs` rejected.
*lets discuss if we want these other modes 2/, 3/, 4/ as well the others as well*
[See addendum: mode scope discussion](./impl_proposal_add.md#discussion-other-modes)

5. Require PartyA to be unbound to a PartyB.
6. Lock escrow from isolated balances until fill.
7. Move escrow into selected PartyB cross state at fill, not at lock.


**lafa comment**
8. Disable partial fills for deferred sells in v1.
// I guess its very hard to implement partial fills, and might also not be desired UX from PartyA sender perspective, as we most likely have to isolate both sells.
so its an AOC (all or cancel only)

**lafa comment**
9. Release escrow on every non-fill terminal path.
*potentially gotta add a cancel function? I guess we already have something?*
[See addendum: PartyA cancellation](./impl_proposal_add.md#partya-cancellation)


## Current Blockers

`LibPartyAOpen.sendOpenIntent` currently rejects all cross-margin open intents that do not specify exactly one PartyB:

```solidity
if (tradeAgreements.marginType == MarginType.CROSS) {
    if (partyBsWhiteList.length != 1) revert IntentErrors.MultiplePartyBNotAllowed();
    sender.requireSolvent(partyBsWhiteList[0], symbol.collateral, tradeAgreements.marginType);
    partyBsWhiteList[0].requireSolvent(sender, symbol.collateral, tradeAgreements.marginType);
}
```

`LibOpenIntentOps` also assumes a concrete PartyB when locking cross-margin fees and seller MM:

```solidity
function _lock(OpenIntent memory self, address collateral, uint256 amount) internal {
    ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(collateral);
    if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
        partyABalance.isolatedLock(amount);
    } else {
        partyABalance.crossLock(self.partyBsWhiteList[0], amount);
    }
}

function lockMMIfSell(OpenIntent memory self) internal {
    if (self.tradeAgreements.tradeSide == TradeSide.SELL)
        self.partyA.balanceOf(getSymbol(self).collateral).crossLock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
}
```

So `SELL + CROSS + []` needs a separate escrow branch instead of indexing `partyBsWhiteList[0]`.

## Storage Design

Add an intent-scoped escrow record. Do not add fields to `OpenIntent`, because it is persisted storage and contains dynamic fields.

Add to `contracts/types/IntentTypes.sol`:

```solidity
struct OpenIntentEscrow {
    address partyA;
    address collateral;
    address feeToken;
    uint256 mm;
    uint256 feeLockAmount;
    bool exists;
    bool consumed;
}
```

Append to `OpenIntentStorage.Layout`:

```solidity
mapping(uint256 => OpenIntentEscrow) openIntentEscrows;
```

Appending to the layout preserves the existing diamond storage shape. The source of truth should be keyed by `intentId`, not by PartyA, because cancel, expiry, force-cancel, fill, and partial-fill lifecycle operations are all intent-scoped.

## Helper Predicates

Add helpers in `LibOpenIntent.sol`:

```solidity
function isDeferredPartyBSell(
    address[] memory partyBsWhiteList,
    TradeAgreements memory agreements
) internal pure returns (bool) {
    return
        agreements.tradeSide == TradeSide.SELL &&
        agreements.marginType == MarginType.CROSS &&
        partyBsWhiteList.length == 0;
}

function isDeferredPartyBSellIntent(OpenIntent memory intent) internal pure returns (bool) {
    return
        intent.tradeAgreements.tradeSide == TradeSide.SELL &&
        intent.tradeAgreements.marginType == MarginType.CROSS &&
        intent.partyBsWhiteList.length == 0;
}
```

These helpers keep the special case explicit and prevent accidentally creating generalized multi-PartyB cross margin.

## Send Open Intent Flow

Modify `LibPartyAOpen.sendOpenIntent`.

Existing behavior stays unchanged for:

1. `BUY + ISOLATED`.
2. `BUY + CROSS + one PartyB`.
3. `SELL + CROSS + one PartyB`.
4. Existing rejected cases except the new deferred sell case.

New behavior:

```solidity
bool deferredSell = LibOpenIntentOps.isDeferredPartyBSell(partyBsWhiteList, tradeAgreements);

if (tradeAgreements.marginType == MarginType.CROSS) {
    if (deferredSell) {
        _validateDeferredSellPartyA(sender);
    } else {
        if (partyBsWhiteList.length != 1) revert IntentErrors.MultiplePartyBNotAllowed();
        sender.requireSolvent(partyBsWhiteList[0], symbol.collateral, tradeAgreements.marginType);
        partyBsWhiteList[0].requireSolvent(sender, symbol.collateral, tradeAgreements.marginType);
    }
}
```

For v1, `_validateDeferredSellPartyA` should at least reject bound PartyA accounts:

```solidity
function _validateDeferredSellPartyA(address partyA) internal view {
    address boundPartyB = CounterPartyRelationsStorage.layout().boundPartyB[partyA];
    if (boundPartyB != address(0)) {
        revert IntentErrors.DeferredSellNotAllowedForBoundPartyA(partyA, boundPartyB);
    }
}
```

After registering the intent:

```solidity
if (deferredSell) {
    intent.lockDeferredSellEscrow();
} else {
    intent.lockFees();
    intent.lockPremiumIfBuy();
    intent.lockMMIfSell();
}
```

## Escrow Locking

Use isolated-balance locking for v1. This avoids pretending there is bilateral cross exposure before PartyB is known.

Lock:

1. `tradeAgreements.mm` from PartyA's isolated balance for the symbol collateral.
2. Estimated open fees from PartyA's isolated balance for `feeToken`.

Implementation shape:

```solidity
function lockDeferredSellEscrow(OpenIntent memory intent) internal {
    OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
    Symbol memory symbol = getSymbol(intent);

    uint256 mm = intent.tradeAgreements.mm;
    uint256 feeLockAmount = calculateOpenFeeLock(intent);

    intent.partyA.balanceOf(symbol.collateral).isolatedLock(mm);
    intent.partyA.balanceOf(intent.feeStructure.feeToken).isolatedLock(feeLockAmount);

    layout.openIntentEscrows[intent.id] = OpenIntentEscrow({
        partyA: intent.partyA,
        collateral: symbol.collateral,
        feeToken: intent.feeStructure.feeToken,
        mm: mm,
        feeLockAmount: feeLockAmount,
        exists: true,
        consumed: false
    });

    emit LockOpenIntentEscrow(intent.id, intent.partyA, symbol.collateral, mm, intent.feeStructure.feeToken, feeLockAmount);
}
```

`calculateOpenFeeLock` should sum the same fee types that `lockFees` currently locks at the submitted intent price:

```solidity
function calculateOpenFeeLock(OpenIntent memory intent) internal pure returns (uint256) {
    FeeStructure memory s = intent.feeStructure;

    return
        intent.calculateFee(s.platformFee.openFee, intent.price) +
        intent.calculateFee(s.affiliateFee.openFee, intent.price) +
        intent.calculateFee(s.solverFee.openFee, intent.price);
}
```

If `feeToken == collateral`, both locks hit the same `ScheduledReleaseBalance` slot. That is acceptable as long as available isolated balance covers `mm + feeLockAmount`.

## Lock Open Intent Flow

`LibPartyBOpen.lockOpenIntent` already allows empty whitelists:

```solidity
if (intent.partyBsWhiteList.length == 0) {
    isValidPartyB = true;
}
```

Add a deferred-sell escrow check before assigning PartyB:

```solidity
if (intent.isDeferredPartyBSellIntent()) {
    OpenIntentEscrow storage escrow = OpenIntentStorage.layout().openIntentEscrows[intentId];
    if (!escrow.exists) revert IntentErrors.MissingOpenIntentEscrow(intentId);
    if (escrow.consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(intentId);
}
```

Do not move escrow into cross state at lock time. Keep it intent-scoped until fill. This keeps PartyB unlock, PartyA cancel-pending, and expiry behavior simpler.

## Fill Open Intent Flow

Modify `LibPartyBOpen.fillOpenIntent`.

For normal intents, keep current behavior:

```solidity
intent.unlockFees();
intent.unlockPremiumIfBuy();
intent.unlockMMIfSell();
```

For deferred sells, skip normal unlock helpers and consume escrow:

```solidity
bool deferredSell = intent.isDeferredPartyBSellIntent();

if (deferredSell) {
    if (quantity != intent.tradeAgreements.quantity) {
        revert IntentErrors.PartialFillNotAllowedForDeferredSell(intent.id);
    }
    intent.consumeDeferredSellEscrow(tradeId, intent.partyB);
} else {
    intent.unlockFees();
    intent.unlockPremiumIfBuy();
    intent.unlockMMIfSell();
}
```

Consume logic:

```solidity
function consumeDeferredSellEscrow(
    OpenIntent storage intent,
    uint256 tradeId,
    address partyB
) internal {
    OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
    OpenIntentEscrow storage escrow = layout.openIntentEscrows[intent.id];

    if (!escrow.exists) revert IntentErrors.MissingOpenIntentEscrow(intent.id);
    if (escrow.consumed) revert IntentErrors.OpenIntentEscrowAlreadyConsumed(intent.id);

    escrow.partyA.balanceOf(escrow.collateral).isolatedUnlock(escrow.mm);
    escrow.partyA.balanceOf(escrow.feeToken).isolatedUnlock(escrow.feeLockAmount);

    escrow.partyA.balanceOf(escrow.collateral).allocateBalance(partyB, escrow.mm);

    emit ConsumeOpenIntentEscrow(intent.id, tradeId, partyB, escrow.mm, 0);

    delete layout.openIntentEscrows[intent.id];
}
```

Do not call `increaseMM` inside `consumeDeferredSellEscrow`. The existing sell fill path already does:

```solidity
partyABalance.increaseMM(trade.partyB, trade.tradeAgreements.mm);
```

Keeping that call where it is minimizes downstream changes to close, exercise, and liquidation behavior.

## Fee Handling On Fill

The lock amount is based on the submitted intent price. The actual fill price may be better for PartyA, which can make actual fees higher than the locked estimate.

Recommended v1:

1. Lock fees at submitted intent price.
2. On fill, unlock the fee escrow.
3. Charge actual fees using existing fee logic.
4. If actual fees exceed the locked estimate, require the extra amount to be available from PartyA.

Because existing fee subtraction for cross margin expects a concrete counterparty, the deferred-sell fill path must ensure fee collection uses the selected `intent.partyB`, not `partyBsWhiteList[0]`.

One clean implementation is to update `_handleFees` to use:

```solidity
address partyB = self.partyBsWhiteList.length == 1 ? self.partyBsWhiteList[0] : self.partyB;
```

and require `partyB != address(0)` for cross-margin subtract/add operations. For lock/unlock operations, deferred sells should use the escrow helpers instead of `_lock` and `_unlock`.

## Partial Fills

Disable partial fills for deferred sells in v1:

```solidity
error PartialFillNotAllowedForDeferredSell(uint256 intentId);
```

Reason: partial fills require proportional escrow splitting, child intent escrow creation, fee lock split accounting, and repeated-conservation tests. That can be added later after the full-fill path is proven.

If partial fills are added later, the invariant should be:

```text
original escrow = consumed escrow + released escrow + child escrow
```

## Cancel, Expire, Force-Cancel, Clearing House

Every path that currently unlocks normal open-intent funds must branch for deferred sells.

Current pattern:

```solidity
intent.unlockFees();
intent.unlockPremiumIfBuy();
intent.unlockMMIfSell();
```

New helper:

```solidity
function unlockForCancelOrExpire(OpenIntent storage intent) internal {
    if (intent.isDeferredPartyBSellIntent()) {
        releaseDeferredSellEscrow(intent.id);
    } else {
        intent.unlockFees();
        intent.unlockPremiumIfBuy();
        intent.unlockMMIfSell();
    }
}
```

Use it in:

1. `LibPartyAOpen.cancelOpenIntent`
2. `LibOpenIntentOps.expire`
3. `LibPartyBOpen.acceptCancelOpenIntent`
4. `LibForceActions.forceCancelOpenIntent`
5. `LibClearingHouse.cancelOpenIntents`

Release logic:

```solidity
function releaseDeferredSellEscrow(uint256 intentId) internal {
    OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
    OpenIntentEscrow storage escrow = layout.openIntentEscrows[intentId];

    if (!escrow.exists) return;
    if (escrow.consumed) return;

    escrow.partyA.balanceOf(escrow.collateral).isolatedUnlock(escrow.mm);
    escrow.partyA.balanceOf(escrow.feeToken).isolatedUnlock(escrow.feeLockAmount);

    emit ReleaseOpenIntentEscrow(intentId, escrow.partyA, escrow.collateral, escrow.mm, escrow.feeToken, escrow.feeLockAmount);

    delete layout.openIntentEscrows[intentId];
}
```

## Events And Errors

Add errors to `IntentErrors.sol`:

```solidity
error DeferredSellNotAllowedForBoundPartyA(address partyA, address boundPartyB);
error MissingOpenIntentEscrow(uint256 intentId);
error OpenIntentEscrowAlreadyConsumed(uint256 intentId);
error PartialFillNotAllowedForDeferredSell(uint256 intentId);
```

Add events to `IPartyAOpenEvents.sol` or another shared open-intent event interface:

```solidity
event LockOpenIntentEscrow(
    uint256 indexed intentId,
    address indexed partyA,
    address indexed collateral,
    uint256 mm,
    address feeToken,
    uint256 feeLockAmount
);

event ReleaseOpenIntentEscrow(
    uint256 indexed intentId,
    address indexed partyA,
    address indexed collateral,
    uint256 mm,
    address feeToken,
    uint256 feeLockAmount
);

event ConsumeOpenIntentEscrow(
    uint256 indexed intentId,
    uint256 indexed tradeId,
    address indexed partyB,
    uint256 mmConsumed,
    uint256 mmRemaining
);
```

## Views

Add a view struct if needed:

```solidity
struct OpenIntentEscrowView {
    bool exists;
    bool consumed;
    address partyA;
    address collateral;
    address feeToken;
    uint256 mm;
    uint256 feeLockAmount;
}
```

Add to `ViewFacet` and `IViewFacet`:

```solidity
function getOpenIntentEscrow(uint256 intentId) external view returns (OpenIntentEscrow memory);

function isDeferredPartyBSellIntent(uint256 intentId) external view returns (bool);
```

The frontend and PartyBs need to see that the broadcast sell intent is funded before attempting to lock/fill it.

## File Touchpoints

Likely Solidity changes:

1. `contracts/types/IntentTypes.sol`
   - Add `OpenIntentEscrow`.
2. `contracts/storages/OpenIntentStorage.sol`
   - Append `mapping(uint256 => OpenIntentEscrow) openIntentEscrows`.
3. `contracts/errors/IntentErrors.sol`
   - Add deferred-sell escrow errors.
4. `contracts/facets/PartyAOpen/IPartyAOpenEvents.sol`
   - Add escrow events.
5. `contracts/libraries/models/LibOpenIntent.sol`
   - Add predicates, fee-lock calculation, escrow lock/release/consume helpers, and cancel/expire unlock helper.
6. `contracts/libraries/core/LibPartyAOpen.sol`
   - Allow deferred sell at send time and lock escrow.
7. `contracts/libraries/core/LibPartyBOpen.sol`
   - Validate escrow on lock, consume escrow on fill, reject partial deferred fills, avoid normal unlock helpers for deferred sell.
8. `contracts/libraries/core/LibForceActions.sol`
   - Release escrow on force-cancel.
9. `contracts/libraries/core/LibClearingHouse.sol`
   - Release or route escrow on clearing-house cancellation.
10. `contracts/facets/View/ViewFacet.sol`
    - Expose escrow state.
11. `contracts/facets/View/IViewFacet.sol`
    - Add view function declarations.

## Tests

Add tests around these cases:

### Creation

1. `SELL + CROSS + empty whitelist` succeeds when PartyA has enough isolated collateral.
2. It reverts if PartyA lacks available isolated balance for MM plus fees.
3. It reverts if PartyA is bound to a PartyB.
4. `BUY + CROSS + empty whitelist` still reverts.
5. `SELL + CROSS + multiple PartyBs` still reverts.
6. Existing `SELL + CROSS + one PartyB` still works.

### Lock

1. Any valid PartyB can lock the deferred sell intent.
2. Suspended PartyB cannot lock.
3. PartyB with wrong oracle cannot lock.
4. PartyB without symbol support cannot lock.
5. Lock reverts if escrow is missing or consumed.

### Fill

1. Full fill consumes escrow and opens trade with original PartyA.
2. Trade has selected PartyB.
3. PartyA MM is allocated into selected PartyB cross state.
4. Existing sell fill code increases PartyA total MM against selected PartyB.
5. Fees are charged correctly.
6. Better-than-quoted sell price handles additional fee requirement.
7. Partial fill reverts in v1.

### Cancel And Expiry

1. PartyA cancel while pending releases escrow.
2. Expiry releases escrow.
3. PartyB unlock returns intent to pending and keeps escrow.
4. PartyA cancel while locked moves to `CANCEL_PENDING` and keeps escrow.
5. PartyB accept cancel releases escrow.
6. Force cancel releases escrow.
7. Clearing-house cancellation does not leave escrow locked.

### Regression

1. Existing isolated buy flow still works.
2. Existing cross buy with one PartyB still works.
3. Existing cross sell with one PartyB still works.
4. Existing close, exercise, and liquidation paths for filled sell trades remain unchanged.

## Security Invariants

1. Deferred-sell escrow is never withdrawable while the intent is pending or locked.
2. Escrow can be released only once.
3. Escrow can be consumed only once.
4. A filled deferred sell trade always has the original PartyA as `trade.partyA`.
5. A filled deferred sell trade always has the locking PartyB as `trade.partyB`.
6. No bilateral cross accounting exists before fill.
7. After fill, the trade uses ordinary cross-margin accounting.

## Open Decisions

The recommended v1 answers are included above, but these decisions should be confirmed before implementation:

1. Should escrow be backed by isolated balance or reserve balance?
2. Should partial fills be disabled in v1?
3. Should deferred sell automatically bind PartyA to the selected PartyB?
4. What exact clean-subaccount rule should core enforce beyond "not bound"?
5. Should liquidation cancel escrow, release escrow, or confiscate escrow?
6. Should fee locks include a buffer for better-than-quoted sell fills?
7. Should the feature be globally gated or symbol-gated?

## Recommended V1

Implement the full-fill-only isolated-balance escrow design first.

This gives the product outcome with the smallest core surface area:

```text
PartyA broadcasts a funded sell intent to all eligible PartyBs.
One PartyB locks and fills it.
SYMMIO converts the escrow into normal bilateral cross margin.
The opened trade has the original PartyA and the selected PartyB.
```

Partial fills, automatic PartyB binding, and liquidation-specific escrow confiscation can be added after this path is tested and reviewed.
