# Addendum: Mode Scope and PartyA Cancellation

This addendum expands the discussion comments in `implementation_proposal.md` around:

1. Whether to support modes beyond `SELL + CROSS + empty whitelist`.
2. How PartyA cancels a deferred PartyB sell intent.

## Recommendation

Keep v1 narrow:

1. Support `SELL + CROSS + empty whitelist`.
2. Keep `SELL + ISOLATED` rejected.
3. Keep `BUY + CROSS + empty whitelist` rejected.
4. Keep `SELL + CROSS + multiple PartyBs` rejected.
5. Reuse the existing `cancelOpenIntent(uint256[] intentIds)` function for PartyA cancellation.

The main reason is accounting risk. The escrow feature changes the meaning of "locked but not yet assigned to PartyB". That should be proven in the smallest product-relevant case before expanding to other intent shapes.

## Discussion: Other Modes

### 1. `SELL + ISOLATED`

Current behavior rejects isolated sell intents:

```text
tradeSide == SELL
marginType == ISOLATED
```

Recommendation: keep rejected in v1.

Reasoning:

1. The product goal is PartyA discovering a PartyB and then becoming a normal cross-margin relationship with that selected PartyB.
2. Isolated sell does not need the same PartyB discovery mechanism unless the protocol wants isolated seller positions without pre-selecting a PartyB.
3. Supporting it would require reviewing whether seller MM should remain isolated for the lifetime of the trade or be converted after fill.
4. It increases surface area without solving the current first-sell cross discovery problem.

Future option:

```text
SELL + ISOLATED + empty whitelist
```

could be allowed later as "broadcast isolated sell". That would probably be easier than cross because the escrow could remain isolated, but it is a separate product mode and should not be bundled into the first escrow implementation.

### 2. `BUY + CROSS + empty whitelist`

Current behavior rejects cross intents without exactly one PartyB. The proposal only carves out a narrow exception for sell-side discovery.

Recommendation: keep rejected in v1.

Reasoning:

1. BUY intents lock premium, not seller MM.
2. Cross BUY with unknown PartyB still has a counterparty-specific accounting problem for premium locks, fees, solvency, and later premium transfer.
3. The product need described in the escrow idea is specifically "PartyA wants to sell first and discover a market maker".
4. Supporting broad BUY discovery may be useful later, but it needs its own design around premium escrow and selected-PartyB accounting.

Future option:

```text
BUY + CROSS + empty whitelist
```

could use intent-scoped premium escrow. On fill, the premium escrow would be assigned to the selected PartyB and then processed like an ordinary cross BUY. That should be a second feature after sell escrow is proven.

### 3. `SELL + CROSS + multiple PartyBs`

Current behavior rejects multiple PartyBs for cross margin.

Recommendation: keep rejected in v1.

Reasoning:

1. Empty whitelist already means "any eligible PartyB can lock".
2. One PartyB whitelist already means "specific bilateral cross intent".
3. Multiple PartyBs would introduce a third mode: "broadcast to a selected set".
4. The locking and fill behavior would be similar to empty whitelist, but the validation and UX differ.
5. It is easy to add later once the escrow path works.

Future option:

```text
SELL + CROSS + N whitelisted PartyBs
```

could be supported as "restricted broadcast sell". It would use the same escrow mechanics as empty whitelist, but `lockOpenIntent` would require `sender` to be in the whitelist. This should be considered after v1, not during v1.

## Suggested Mode Matrix

For v1:

```text
BUY  + ISOLATED + empty/multiple whitelist: existing behavior
BUY  + CROSS    + one PartyB: existing behavior
BUY  + CROSS    + empty whitelist: reject
BUY  + CROSS    + multiple PartyBs: reject

SELL + ISOLATED + any whitelist: reject
SELL + CROSS    + one PartyB: existing behavior
SELL + CROSS    + empty whitelist: new deferred PartyB sell escrow
SELL + CROSS    + multiple PartyBs: reject
```

For v2 candidates:

```text
SELL + CROSS + multiple PartyBs
BUY  + CROSS + empty whitelist
SELL + ISOLATED + empty whitelist
```

Recommended expansion order:

1. `SELL + CROSS + multiple PartyBs`, because it can reuse most deferred-sell escrow mechanics.
2. `BUY + CROSS + empty whitelist`, because it needs premium escrow rather than MM escrow.
3. `SELL + ISOLATED + empty whitelist`, only if the product wants isolated broadcast sells.

## PartyA Cancellation

No new external cancel function is required for v1.

The core already has:

```solidity
function cancelOpenIntent(uint256[] calldata intentIds) external
```

on `PartyAOpenFacet`, which calls:

```solidity
LibPartyAOpen.cancelOpenIntent(msg.sender, intentIds[i])
```

Current behavior:

1. If the intent is `PENDING`, PartyA cancellation is immediate.
2. If the intent is `LOCKED`, PartyA cancellation moves it to `CANCEL_PENDING`.
3. If the intent has expired, cancellation routes through expiry.
4. If the intent is already filled/canceled/expired, cancellation reverts.

That lifecycle works for deferred PartyB sell intents too. The required change is not a new API. The required change is replacing normal open-intent unlock calls with escrow release calls when the intent is deferred.

## Deferred Sell Cancellation Behavior

### Pending Intent

State:

```text
PENDING
partyB == address(0)
escrow exists
```

PartyA calls:

```solidity
cancelOpenIntent([intentId])
```

Expected result:

```text
status = CANCELED
escrow released
intent unregistered from PartyA active intents
```

Implementation change:

```solidity
if (intent.status == OpenIntentStatus.PENDING) {
    intent.status = OpenIntentStatus.CANCELED;
    intent.unlockForCancelOrExpire();
    intent.unregister(false);
}
```

where:

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

### Locked Intent

State:

```text
LOCKED
partyB == selected PartyB
escrow still exists
```

PartyA calls:

```solidity
cancelOpenIntent([intentId])
```

Expected result:

```text
status = CANCEL_PENDING
escrow remains locked
PartyB keeps right to fill or accept cancel according to existing lifecycle
```

Do not release escrow immediately while locked. Releasing at `CANCEL_PENDING` would let PartyA remove funding after PartyB already reserved the intent.

### PartyB Accepts Cancel

PartyB calls existing:

```solidity
acceptCancelOpenIntent(intentId)
```

Expected result:

```text
status = CANCELED
escrow released
intent unregistered
```

Implementation change:

```solidity
intent.unlockForCancelOrExpire();
```

instead of directly calling:

```solidity
intent.unlockFees();
intent.unlockPremiumIfBuy();
intent.unlockMMIfSell();
```

### Force Cancel

If PartyA cancellation is stuck in `CANCEL_PENDING`, the existing force-cancel path should continue to apply after the configured timeout:

```text
forceCancelOpenIntentTimeout
```

Expected result:

```text
status = CANCELED
escrow released
intent unregistered
```

Again, no new API is needed. The force-cancel implementation should call the same deferred-aware unlock helper.

### Expiry

If the deferred sell intent expires while `PENDING`, `LOCKED`, or `CANCEL_PENDING`, expiry should release escrow and unregister the intent.

Expected result:

```text
status = EXPIRED
escrow released
intent unregistered
```

This means `LibOpenIntentOps.expire` must also use `unlockForCancelOrExpire()`.

## Should We Add a Dedicated Cancel Function?

Recommendation: no dedicated cancel function for v1.

Avoid:

```solidity
cancelDeferredSellIntent(uint256 intentId)
cancelBroadcastSellIntent(uint256 intentId)
```

Reasons:

1. `cancelOpenIntent` already handles open-intent cancellation.
2. Adding another external cancel selector creates duplicate lifecycle paths.
3. Duplicate paths increase the chance that one path releases escrow and the other forgets.
4. Indexers and frontend code already understand the existing cancel event.

Frontend or SDK can add a convenience wrapper:

```ts
cancelBroadcastSellIntent(intentId) {
  return partyAOpenFacet.cancelOpenIntent([intentId]);
}
```

but the core contract should keep one cancellation path.

## Required Cancel-Path Code Changes

Update these files to use the deferred-aware unlock helper:

1. `contracts/libraries/core/LibPartyAOpen.sol`
    - `cancelOpenIntent`
2. `contracts/libraries/models/LibOpenIntent.sol`
    - `expire`
3. `contracts/libraries/core/LibPartyBOpen.sol`
    - `acceptCancelOpenIntent`
4. `contracts/libraries/core/LibForceActions.sol`
    - `forceCancelOpenIntent`
5. `contracts/libraries/core/LibClearingHouse.sol`
    - `cancelOpenIntents`

The important invariant:

```text
Every non-fill terminal path for a deferred sell intent releases escrow exactly once.
```

## Final Proposal

For the first implementation:

1. Do not expand into the rejected modes on lines 20-22 of `implementation_proposal.md`.
2. Add notes that those modes are v2 candidates.
3. Reuse existing `cancelOpenIntent`.
4. Do not add a new external cancel function.
5. Make cancellation, expiry, force-cancel, clearing-house cancel, and PartyB accept-cancel all call the same deferred-aware escrow release helper.
