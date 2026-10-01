---
title: Events Catalog
aliases:
    - Event Catalog
    - Subgraph
tags:
    - symmio
    - options-core
    - reference
---

# Events Catalog

Catalog of every event emitted by the SYMM Options Core Diamond and its helper contracts. Each entry lists the on-chain signature with `indexed` markers, the function or state transition that emits it, the meaning and units of each field, the source declaration, and one or more emission sites. Subgraph notes call out keys and reconstruction tips. Verified against the source on the `develop` branch; all line numbers are real.

Indexed parameters are marked `(idx)` in tables; non-indexed are `(data)`. Most monetary amounts in the Diamond are 18-decimal normalized values; ERC20 amounts in `AccountFacet.deposit` use the collateral's native decimals (the emitted `amount` is the post-normalization 18-decimal value).

## Contents

-   [AccountFacet](#accountfacet)
-   [PartyAOpenFacet (shared `IPartiesEvents`)](#partyaopenfacet-shared-ipartiesevents)
-   [PartyBOpenFacet](#partybopenfacet)
-   [PartyACloseFacet](#partyaclosefacet)
-   [PartyBCloseFacet](#partybclosefacet)
-   [TradeFacet](#tradefacet)
-   [ForceActionsFacet](#forceactionsfacet)
-   [ClearingHouseFacet](#clearinghousefacet)
-   [CounterPartyRelationsFacet](#counterpartyrelationsfacet)
-   [ControlFacet](#controlfacet)
-   [LibScheduledReleaseBalance (library events)](#libscheduledreleasebalance-library-events)
-   [LibDiamond / DiamondCutFacet](#libdiamond--diamondcutfacet)
-   [InstantLayer (helper)](#instantlayer-helper)
-   [MultiAccount (helper)](#multiaccount-helper)
-   [SymmioPartyA (helper)](#symmiopartya-helper)
-   [SymmioPartyB (helper)](#symmiopartyb-helper)
-   [TradeNFT (helper)](#tradenft-helper)
-   [MuonOracle (helper)](#muonoracle-helper)
-   [Defined But Not Emitted](#defined-but-not-emitted)
-   [Cross-Cutting Patterns](#cross-cutting-patterns)

---

## AccountFacet

Source for events: `contracts/facets/Account/IAccountEvents.sol`. All emissions in `contracts/facets/Account/AccountFacet.sol`.

| Event                          | Signature                                                                                                                                      | Trigger                                                                                                                              | Decl line | Emit line(s) |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | --------- | ------------ |
| `Deposit`                      | `(address sender idx, address user idx, address collateral idx, uint256 amount, uint256 newBalance)`                                           | `deposit`, `depositFor`, `virtualDepositFor` credit `user.isolatedBalance`. `amount` is 18-decimal post-normalization.               | 8         | 41, 57, 82   |
| `VirtualDeposit`               | `(address sender idx, address user idx, address collateral idx, uint256 amount, uint256 newBalance)`                                           | `virtualDepositFor` (no ERC20 transfer; book-only credit).                                                                           | 9         | 58           |
| `InternalTransfer`             | `(address sender idx, address receiver idx, address collateral idx, uint256 amount, uint256 newBalanceOfSender, uint256 newBalanceOfReceiver)` | `internalTransfer` moves isolated balance between in-protocol users.                                                                 | 10        | 107          |
| `ExternalTransfer`             | `(address sender idx, address user idx, address collateral idx, uint256 amount, address target)`                                               | `externalTransfer` sends ERC20 to a whitelisted external `target` and calls `target.onTransfer`. `amount` is the 18-decimal request. | 18        | 139          |
| `InitiateWithdraw`             | `(uint256 id, address user idx, address to idx, address collateral idx, uint256 amount, uint256 newBalance)`                                   | `initiateWithdraw` and the non-express path of `initiateExpressWithdraw`. `id` is the new withdraw request ID.                       | 19        | 162, 191     |
| `InitiateExpressWithdraw`      | `(uint256 id, address user idx, address to idx, address collateral idx, address provider, bytes userData, uint256 amount, uint256 newBalance)` | `initiateExpressWithdraw` (third-party provider path). Emitted alongside `InitiateWithdraw`.                                         | 20        | 192          |
| `CompleteWithdraw`             | `(uint256 id)`                                                                                                                                 | `completeWithdraw` after cooldown elapses; releases ERC20 to `to`.                                                                   | 30        | 225          |
| `CancelWithdraw`               | `(uint256 id, address user idx, address collateral idx, uint256 amount, uint256 newBalance)`                                                   | `cancelWithdraw` returns funds to user's isolated balance.                                                                           | 31        | 236          |
| `SuspendWithdraw`              | `(uint256 id, address suspender)`                                                                                                              | `suspendWithdraw` (admin-suspended pending withdrawal). `suspender = msg.sender`.                                                    | 32        | 202          |
| `RestoreWithdraw`              | `(uint256 id, uint256 validAmount)`                                                                                                            | `restoreWithdraw` reactivates a suspended withdrawal at `validAmount` (may be reduced).                                              | 33        | 213          |
| `Allocate`                     | `(address user idx, address collateral idx, address counterParty idx, uint256 amount, uint256 newBalance, int256 newAllocatedBalance)`         | `allocate` moves isolated balance into a cross-margin slot vs `counterParty`. `newAllocatedBalance` is the signed cross balance.     | 34        | 268          |
| `Deallocate`                   | `(address user idx, address collateral idx, address counterParty idx, uint256 amount, uint256 newBalance, int256 newAllocatedBalance)`         | `deallocate` returns cross balance to isolated, gated by uPnL signature and cooldown.                                                | 42        | 294          |
| `AllocateToReserveBalance`     | `(address user idx, address collateral idx, uint256 amount, uint256 newBalance)`                                                               | `allocateToReserveBalance` parks isolated funds in clearing-house-controlled reserve.                                                | 51        | 314          |
| `DeallocateFromReserveBalance` | `(address user idx, address collateral idx, uint256 amount, uint256 newBalance)`                                                               | `deallocateFromReserveBalance` returns reserve back to isolated.                                                                     | 52        | 327          |

Subgraph notes: `id` from `InitiateWithdraw` / `InitiateExpressWithdraw` is the unique key for the withdrawal lifecycle (`Suspend`, `Restore`, `Complete`, `Cancel`, `ConfiscateWithdrawal`). `(user, collateral, counterParty)` is the natural key for cross-balance reconstruction.

---

## PartyAOpenFacet (shared `IPartiesEvents`)

`PartyAOpenFacet` re-exports the shared `IPartiesEvents` interface (`contracts/facets/PartyAOpen/IPartyAOpenEvents.sol:9`). Definitions live in `contracts/interfaces/IPartiesEvents.sol`. Emissions: `contracts/facets/PartyAOpen/PartyAOpenFacet.sol`.

### `SendOpenIntent`

`SendOpenIntent(address indexed partyA, uint256 intentId, address[] partyBsWhiteList, bytes requestedParams)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:10`
-   Emit: `contracts/facets/PartyAOpen/PartyAOpenFacet.sol:85` (initial intent), `contracts/facets/PartyBOpen/PartyBOpenFacet.sol:74` (residual intent created when a partial fill leaves leftover quantity).
-   Triggered by `PartyAOpenFacet.sendOpenIntent` and inside `PartyBOpenFacet.fillOpenIntent` when `newIntentId != 0`.
-   `requestedParams` packs: `(symbolId, price, quantity, strikePrice, expirationTimestamp, mm, tradeSide, marginType, exerciseFee.rate, exerciseFee.cap, solverFee.openFee, solverFee.closeFee, deadline)` for the original; the residual variant omits `solverFee` fields. All amounts are 18-decimal.
-   Subgraph: `intentId` is the primary key for `OpenIntent`. Two emission sites means indexers must accept both.

### `CancelOpenIntent`

`CancelOpenIntent(uint256 intentId, OpenIntentStatus finalStatus)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:11`
-   Emit: `contracts/facets/PartyAOpen/PartyAOpenFacet.sol:136`, `contracts/facets/PartyBOpen/PartyBOpenFacet.sol:93`.
-   `cancelOpenIntent` resolves to either `CANCELED` (immediate) or `CANCEL_PENDING` (locked, awaiting Party B). Also fired when the residual intent of a fill is auto-canceled.
-   `finalStatus` enum is `OpenIntentStatus` from `contracts/types/IntentTypes.sol`.

### `ExpireOpenIntent`

`ExpireOpenIntent(uint256 intentId)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:12`
-   Emit: `contracts/facets/PartyAOpen/PartyAOpenFacet.sol:117`, `:134`, and `contracts/facets/PartyBOpen/PartyBOpenFacet.sol:43` (lock attempt past deadline).
-   Marks the intent as `EXPIRED`; can be fired by anyone for already-expired intents via `expireOpenIntent`, indirectly through `cancelOpenIntent`, or by a Party B trying to lock.

### `ExpireCloseIntent`

`ExpireCloseIntent(uint256 intentId)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:13`
-   Emit: `contracts/facets/PartyAClose/PartyACloseFacet.sol:58`, `:73`. Same dual path as the open variant.

### `LockOpenIntentEscrow`

`LockOpenIntentEscrow(uint256 indexed intentId, address indexed partyA, address indexed collateral, uint256 mm, address feeToken, uint256 feeLockAmount)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:14-21`; library declaration mirrors it in `contracts/libraries/models/LibOpenIntent.sol:24-31`.
-   Emit: `contracts/libraries/models/LibOpenIntent.sol:162`.
-   Triggered when Party A creates a deferred Party B sell (`SELL + CROSS + empty whitelist`).
-   `mm` is the seller maintenance margin locked from Party A isolated `collateral`; `feeLockAmount` is the estimated total open fee locked from Party A isolated `feeToken` at the intent limit price.

### `ReleaseOpenIntentEscrow`

`ReleaseOpenIntentEscrow(uint256 indexed intentId, address indexed partyA, address indexed collateral, uint256 mm, address feeToken, uint256 feeLockAmount)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:22-29`; library declaration mirrors it in `contracts/libraries/models/LibOpenIntent.sol:32-39`.
-   Emit: `contracts/libraries/models/LibOpenIntent.sol:175`.
-   Triggered when a deferred Party B sell reaches a non-fill terminal path: pending cancel, Party B accept-cancel, force-cancel, expiry, or clearing-house cancel/expire.
-   Subgraph: pair this with `LockOpenIntentEscrow` to know that the isolated reservation was returned and `openIntentEscrows[intentId]` was deleted.

### `ConsumeOpenIntentEscrow`

`ConsumeOpenIntentEscrow(uint256 indexed intentId, uint256 indexed tradeId, address indexed partyB, uint256 mmConsumed, uint256 feeConsumed)`

-   Decl: `contracts/interfaces/IPartiesEvents.sol:30`; library declaration mirrors it in `contracts/libraries/models/LibOpenIntent.sol:40`.
-   Emit: `contracts/libraries/models/LibOpenIntent.sol:207`.
-   Triggered during fill of a deferred Party B sell, after the selected Party B is known and before the normal cross fee/premium accounting completes. On partial fills, the event reports only the consumed slice.
-   `mmConsumed` is allocated into Party A's cross collateral bucket against `partyB`; `feeConsumed` is the actual fill-price open fee allocated into Party A's cross `feeToken` bucket against `partyB`.
-   A residual partial-fill escrow move does not emit a second lock event because the balances stay locked; indexers should follow the residual `SendOpenIntent` child and read `getOpenIntentEscrow(childIntentId)`.

---

## PartyBOpenFacet

Source: `contracts/facets/PartyBOpen/IPartyBOpenEvents.sol`. Inherits `IPartiesEvents`. Emissions in `contracts/facets/PartyBOpen/PartyBOpenFacet.sol`.

### `LockOpenIntent`

`LockOpenIntent(uint256 intentId, address indexed partyB)`

-   Decl: `IPartyBOpenEvents.sol:11`
-   Emit: `PartyBOpenFacet.sol:31`
-   Party B reserves an `OpenIntent` for exclusive fill (state → `LOCKED`).

### `UnlockOpenIntent`

`UnlockOpenIntent(uint256 intentId, address indexed partyB)`

-   Decl: `IPartyBOpenEvents.sol:12`
-   Emit: `PartyBOpenFacet.sol:45`
-   Party B releases its lock (state → `PENDING`). Same call path may emit `ExpireOpenIntent` instead if past deadline.

### `AcceptCancelOpenIntent`

`AcceptCancelOpenIntent(uint256 intentId)`

-   Decl: `IPartyBOpenEvents.sol:10`
-   Emit: `PartyBOpenFacet.sol:57`
-   Party B accepts a Party A `CANCEL_PENDING` request (state → `CANCELED`).

### `FillOpenIntent`

`FillOpenIntent(uint256 intentId, uint256 tradeId, uint256 quantity, uint256 price)`

-   Decl: `IPartyBOpenEvents.sol:13`
-   Emit: `PartyBOpenFacet.sol:71`
-   `quantity` and `price` are 18-decimal. `tradeId` is the newly created trade. If `quantity` < requested, a residual `SendOpenIntent` follows.
-   Subgraph: `tradeId` is the primary key for `Trade`; pair with the originating `intentId`.

---

## PartyACloseFacet

Source: `contracts/facets/PartyAClose/IPartyACloseEvents.sol` (extends `IPartiesEvents`). Emissions in `contracts/facets/PartyAClose/PartyACloseFacet.sol`.

### `SendCloseIntent`

`SendCloseIntent(uint256 tradeId, uint256 intentId, uint256 price, uint256 quantity, uint256 deadline)`

-   Decl: `IPartyACloseEvents.sol:10`
-   Emit: `PartyACloseFacet.sol:45`
-   Party A asks to close `quantity` of `tradeId` at `price` before `deadline` (unix seconds). Field order is `(tradeId, intentId, price, quantity, deadline)` — note `price` precedes `quantity` in the event, opposite to the function signature order.

### `CancelCloseIntent`

`CancelCloseIntent(uint256 intentId)`

-   Decl: `IPartyACloseEvents.sol:11`
-   Emit: `PartyACloseFacet.sol:75`
-   Resolves to `CANCEL_PENDING` (the only state that fires this event; expired close intents fire `ExpireCloseIntent` instead).

---

## PartyBCloseFacet

Source: `contracts/facets/PartyBClose/IPartyBCloseEvents.sol`. Emissions in `contracts/facets/PartyBClose/PartyBCloseFacet.sol`.

### `AcceptCancelCloseIntent`

`AcceptCancelCloseIntent(uint256 intentId)`

-   Decl: `IPartyBCloseEvents.sol:10`
-   Emit: `PartyBCloseFacet.sol:28`
-   Party B accepts Party A's pending close cancellation.

### `FillCloseIntent`

`FillCloseIntent(uint256 intentId, uint256 quantity, uint256 price)`

-   Decl: `IPartyBCloseEvents.sol:11`
-   Emit: `PartyBCloseFacet.sol:40`
-   No new `tradeId` is emitted — closes operate on the intent's bound trade. `quantity` and `price` are 18-decimal.

---

## TradeFacet

Source: `contracts/facets/Trade/ITradeEvents.sol`. Emissions in `contracts/facets/Trade/TradeFacet.sol`.

### `TransferTradeByPartyA`

`TransferTradeByPartyA(address indexed sender, address indexed receiver, uint256 tradeId)`

-   Decl: `ITradeEvents.sol:8`
-   Emit: `TradeFacet.sol:34` (Party A direct transfer), `:51` (mirrored from `TradeNFT` via `transferTradeFromNFT`).
-   Tracks ownership change of a `Trade`. The same event handles both bare transfers and NFT-mediated transfers; pair with `TradeNFT.TradeNFTTransferred` to disambiguate.

### `ExecuteTrades`

`ExecuteTrades(address operator, uint256[] tradeIds, bool[] exercised, bool[] expired, uint256 settlementPrice, uint256 collateralPrice)`

-   Decl: `ITradeEvents.sol:9`
-   Emit: `TradeFacet.sol:63`
-   Emitted by `executeTrades(tradeIds, settlementPriceSig)` after expiration. `exercised[i]` and `expired[i]` describe per-trade outcome (mutually exclusive). `settlementPrice` and `collateralPrice` come from the Muon-signed `SettlementPriceSig` and are 18-decimal.

---

## ForceActionsFacet

Source: `contracts/facets/ForceActions/ForceActionsFacetEvents.sol`. Emissions in `contracts/facets/ForceActions/ForceActionsFacet.sol`.

| Event                    | Signature            | Trigger                                                                               | Decl line | Emit line |
| ------------------------ | -------------------- | ------------------------------------------------------------------------------------- | --------- | --------- |
| `ForceCancelOpenIntent`  | `(uint256 intentId)` | `forceCancelOpenIntent` after the configured force-cancel timeout has elapsed.        | 8         | 27        |
| `ForceCancelCloseIntent` | `(uint256 intentId)` | `forceCancelCloseIntent` after the configured force-cancel close timeout has elapsed. | 9         | 38        |

Use these to distinguish force-driven cancellations from voluntary `CancelOpenIntent` / `CancelCloseIntent`.

---

## ClearingHouseFacet

Source: `contracts/facets/ClearingHouse/IClearingHouseEvents.sol`. Emissions in `contracts/facets/ClearingHouse/ClearingHouseFacet.sol`. All operators are `CLEARING_HOUSE_ROLE` holders.

| Event                              | Signature                                                                                                                             | Trigger                                                                                                         | Decl line | Emit line |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | --------- | --------- |
| `FlagIsolatedPartyBLiquidation`    | `(address operator idx, address partyB idx, address collateral idx)`                                                                  | `flagIsolatedPartyBLiquidation` opens a liquidation window on Party B's isolated book.                          | 10        | 31        |
| `UnflagIsolatedPartyBLiquidation`  | `(address operator idx, address partyB idx, address collateral idx)`                                                                  | `unflagIsolatedPartyBLiquidation` clears the flag.                                                              | 11        | 44        |
| `LiquidateIsolatedPartyB`          | `(address operator idx, address partyB idx, address collateral idx, uint256 balance, int256 upnl, uint256 collateralPrice)`           | `liquidateIsolatedPartyB`. `balance` is the snapshot isolated balance; `upnl`/`collateralPrice` from signature. | 12        | 61        |
| `Confiscate`                       | `(address operator idx, address party idx, address counterParty idx, uint256 liquidationId, uint256 amount, MarginType marginType)`   | `confiscate` seizes `amount` (18-dec) from `(party, counterParty)` per `liquidationId`.                         | 20        | 72        |
| `ConfiscateWithdrawal`             | `(address operator idx, uint256 withdrawId)`                                                                                          | `confiscateWithdrawal` voids a pending withdrawal during liquidation.                                           | 28        | 77        |
| `DistributeCollateral`             | `(address operator idx, address partyB idx, address collateral idx, uint256 liquidationId, address[] partyAs, uint256[] amounts)`     | `distributeCollateral` parcels confiscated funds back to multiple Party A counterparties.                       | 29        | 89        |
| `FlagCrossPartyBLiquidation`       | `(address operator, address partyB idx, address partyA idx, address collateral idx)`                                                  | `flagCrossPartyBLiquidation` (cross-margin variant; `operator` is non-indexed).                                 | 38        | 98        |
| `UnflagCrossPartyBLiquidation`     | `(address operator, address partyB idx, address partyA idx, address collateral idx)`                                                  | `unflagCrossPartyBLiquidation`.                                                                                 | 39        | 107       |
| `LiquidateCrossPartyB`             | `(address operator, address partyB idx, address partyA idx, address collateral idx, int256 upnl, uint256 collateralPrice)`            | `liquidateCrossPartyB`.                                                                                         | 40        | 118       |
| `FlagPartyALiquidation`            | `(address operator, address partyA idx, address partyB idx, address collateral idx)`                                                  | `flagPartyALiquidation`.                                                                                        | 48        | 127       |
| `UnflagPartyALiquidation`          | `(address operator, address partyA idx, address partyB idx, address collateral idx)`                                                  | `unflagPartyALiquidation`.                                                                                      | 49        | 136       |
| `LiquidateCrossPartyA`             | `(address operator, uint256 liquidationId, address partyA, address partyB, address collateral, int256 upnl, uint256 collateralPrice)` | `liquidateCrossPartyA`. None of the address fields are indexed — filter client-side.                            | 50        | 148       |
| `CloseTradesForLiquidation`        | `(address operator, uint256 liquidationId, uint256[] tradeIds, uint256[] prices)`                                                     | `closeTradesForLiquidation` settles a batch of open trades at administered prices.                              | 59        | 157       |
| `CancelOpenIntentsForLiquidation`  | `(address operator, uint256[] intentIds)`                                                                                             | `cancelOpenIntentsForLiquidation`.                                                                              | 60        | 172       |
| `CancelCloseIntentsForLiquidation` | `(address operator, uint256[] intentIds)`                                                                                             | `cancelCloseIntentsForLiquidation`.                                                                             | 61        | 177       |
| `AllocateFromReserveToCross`       | `(address operator, address party, address counterParty, address collateral, uint256 amount)`                                         | `allocateFromReserveToCross` taps a party's reserve to cover its cross balance during a liquidation.            | 62        | 167       |

`FullyLiquidated(address indexed partyB, uint256 liquidationId)` is declared (`IClearingHouseEvents.sol:37`) but never emitted in the current codebase — see [Defined But Not Emitted](#defined-but-not-emitted).

Subgraph note: `liquidationId` is the primary key joining `Confiscate`, `DistributeCollateral`, `LiquidateCrossPartyA`, and `CloseTradesForLiquidation`. The flag/unflag pairs let indexers compute liquidation windows.

---

## CounterPartyRelationsFacet

Source: `contracts/facets/CounterPartyRelations/ICounterPartyRelationsEvents.sol`. Emissions in `contracts/facets/CounterPartyRelations/CounterPartyRelationsFacet.sol`.

| Event                                  | Signature                                                          | Trigger                                                                                            | Decl line | Emit line |
| -------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | --------- | --------- |
| `ActivateInstantActionMode`            | `(address user idx, uint256 timestamp)`                            | `activateInstantActionMode` puts the caller (Party A) into instant mode against its bound Party B. | 8         | 31        |
| `ProposeToDeactivateInstantActionMode` | `(address user idx, uint256 timestamp)`                            | `proposeToDeactivateInstantActionMode` starts the deactivation cooldown.                           | 9         | 45        |
| `DeactivateInstantActionMode`          | `(address user idx, uint256 timestamp)`                            | `deactivateInstantActionMode` after cooldown.                                                      | 10        | 54        |
| `BindToPartyB`                         | `(address partyA idx, address partyB idx)`                         | `bindToPartyB` enforces an exclusive Party B for the caller.                                       | 11        | 64        |
| `InitiateUnbindingFromPartyB`          | `(address partyA idx, address partyB idx, uint256 initiationTime)` | `initiateUnbindingFromPartyB` starts the unbinding cooldown timer.                                 | 12        | 73        |
| `CompleteUnbindingFromPartyB`          | `(address partyA idx, address partyB idx)`                         | `completeUnbindingFromPartyB` after `unbindingCooldown` passes; clears the relationship.           | 13        | 83        |
| `CancelUnbindingFromPartyB`            | `(address partyA idx, address partyB idx)`                         | `cancelUnbindingFromPartyB` aborts the pending unbind and keeps the binding active.                | 14        | 92        |

`timestamp`/`initiationTime` are unix seconds (`block.timestamp`).

---

## ControlFacet

Source: `contracts/facets/Control/IControlEvents.sol`. All emissions in `contracts/facets/Control/ControlFacet.sol`. Most events are admin-driven configuration changes for off-chain audit trails; they are not used for state reconstruction.

### Roles And Access

| Event         | Signature                              | Trigger                         | Decl | Emit   |
| ------------- | -------------------------------------- | ------------------------------- | ---- | ------ |
| `RoleGranted` | `(bytes32 role idx, address user idx)` | `init`, `grantRoles` per-entry. | 54   | 56, 71 |
| `RoleRevoked` | `(bytes32 role idx, address user idx)` | `revokeRoles` per-entry.        | 55   | 87     |

`RoleUpdated(address indexed account, bytes32 indexed role, bool granted)` is declared (`IControlEvents.sol:47`) but never emitted; the facet uses `RoleGranted` / `RoleRevoked` instead.

### Collateral, Limits, Cooldowns

| Event                                      | Signature                                | Trigger                                                   | Decl | Emit     |
| ------------------------------------------ | ---------------------------------------- | --------------------------------------------------------- | ---- | -------- |
| `CollateralWhitelisted`                    | `(address collateral idx)`               | `whitelistCollateral`                                     | 14   | 102      |
| `CollateralRemovedFromWhitelist`           | `(address collateral idx)`               | `removeCollateralFromWhitelist`                           | 15   | 111      |
| `MaxCloseOrdersLengthUpdated`              | `(uint256 max)`                          | `setMaxCloseOrdersLength`                                 | 16   | 125      |
| `MaxTradePerPartyAUpdated`                 | `(uint256 max)`                          | `setMaxTradePerPartyA`                                    | 17   | 135      |
| `BalanceLimitPerUserUpdated`               | `(address collateral, uint256 limit)`    | `setBalanceLimitPerUser`                                  | 18   | 146      |
| `PartyADeallocateCooldownUpdated`          | `(uint256 cooldown)`                     | `setTimingParams`, `setPartyADeallocateCooldown`          | 19   | 187, 206 |
| `PartyBDeallocateCooldownUpdated`          | `(uint256 cooldown)`                     | `setTimingParams`, `setPartyBDeallocateCooldown`          | 20   | 188, 215 |
| `ForceCancelOpenIntentTimeoutUpdated`      | `(uint256 timeout)`                      | `setTimingParams`, `setForceCancelOpenIntentTimeout`      | 21   | 189, 224 |
| `ForceCancelCloseIntentTimeoutUpdated`     | `(uint256 timeout)`                      | `setTimingParams`, `setForceCancelCloseIntentTimeout`     | 22   | 190, 233 |
| `SettlementPriceSigValidTimeUpdated`       | `(uint256 time)`                         | `setTimingParams`, `setSettlementPriceSigValidTime`       | 50   | 191, 242 |
| `UpnlSigValidTimeUpdated`                  | `(uint256 time)`                         | `setTimingParams`, `setUpnlSigValidTime`                  | 51   | 192, 251 |
| `PartyBExclusiveWindowUpdated`             | `(uint256 window)`                       | `setTimingParams`, `setPartyBExclusiveWindow`             | 84   | 193, 260 |
| `UnbindingCooldownUpdated`                 | `(uint256 cooldown)`                     | `setTimingParams`, `setUnbindingCooldown`                 | 59   | 194, 269 |
| `DeactiveInstantActionModeCooldownUpdated` | `(uint256 cooldown)`                     | `setTimingParams`, `setDeactiveInstantActionModeCooldown` | 62   | 195, 278 |
| `MaxConnectedCounterPartiesUpdated`        | `(uint256 max)`                          | `setMaxConnectedCounterParties`                           | 58   | 322      |
| `PartyBReleaseIntervalUpdated`             | `(address partyB idx, uint256 interval)` | `setPartyBReleaseInterval`                                | 56   | 303      |
| `DefaultReleaseIntervalUpdated`            | `(uint256 interval)`                     | `setDefaultReleaseInterval`                               | 57   | 312      |

### Fees And Affiliates

| Event                           | Signature                                                | Trigger                                         | Decl | Emit |
| ------------------------------- | -------------------------------------------------------- | ----------------------------------------------- | ---- | ---- |
| `DefaultFeeCollectorUpdated`    | `(address collector idx)`                                | `setDefaultFeeCollector`                        | 23   | 336  |
| `AffiliateStatusUpdated`        | `(address affiliate idx, bool status)`                   | `setAffiliateStatus`                            | 44   | 346  |
| `AffiliateFeesCollectorUpdated` | `(address affiliate idx, address feeCollector idx)`      | `setAffiliateFeesCollector`                     | 45   | 357  |
| `AffiliateFeesUpdated`          | `(address affiliate idx, uint256 symbolId idx, Fee fee)` | `setAffiliateFees` per `(symbolId, fee)` entry. | 46   | 379  |

### Party B Configuration

| Event                               | Signature                                                   | Trigger                                                | Decl | Emit |
| ----------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------ | ---- | ---- |
| `PartyBConfigUpdated`               | `(address partyB idx, PartyBConfig config)`                 | `setPartyBConfig` (full struct from `AppStorage.sol`). | 48   | 398  |
| `PartyBSupportedSymbolTypesUpdated` | `(address partyB idx, uint256 symbolType idx, bool status)` | `setPartyBSupportedSymbolTypes` per-entry.             | 49   | 417  |

### Pause Toggles (no payload)

`GlobalPaused`, `DepositPaused`, `WithdrawPaused`, `ExpressWithdrawPaused`, `InternalTransferPaused`, `ExternalTransferPaused`, `PartyBActionsPaused`, `PartyAActionsPaused`, `LiquidatingPaused`, `ThirdPartyActionsPaused`, `InstantLayerPaused` and their `*Unpaused` counterparts. Decl lines 24–39 and 85–90; emit lines 432–602.

### Emergency Mode

| Event                             | Signature              | Trigger                                     | Decl | Emit |
| --------------------------------- | ---------------------- | ------------------------------------------- | ---- | ---- |
| `PartyBsEmergencyModeActivated`   | `()`                   | `activatePartyBsEmergencyMode` (global).    | 40   | 614  |
| `PartyBsEmergencyModeDeactivated` | `()`                   | `deactivatePartyBsEmergencyMode`.           | 41   | 622  |
| `PartyBEmergencyModeActivated`    | `(address partyB idx)` | `activatePartyBEmergencyMode` (per-partyB). | 42   | 632  |
| `PartyBEmergencyModeDeactivated`  | `(address partyB idx)` | `deactivatePartyBEmergencyMode`.            | 43   | 642  |

### Suspensions

| Event                 | Signature                               | Trigger                                                    | Decl | Emit     |
| --------------------- | --------------------------------------- | ---------------------------------------------------------- | ---- | -------- |
| `AddressSuspended`    | `(address user idx, bool status)`       | `suspendAddress`, `suspendAddresses` (per-entry).          | 60   | 657, 683 |
| `WithdrawalSuspended` | `(uint256 withdrawId idx, bool status)` | `suspendWithdrawal` toggles a specific withdrawal request. | 61   | 668      |

### Symbols And Oracles

| Event                       | Signature                                                                                                                               | Trigger                           | Decl | Emit |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- | ---- | ---- |
| `OracleAdded`               | `(uint256 oracleId idx, string name, address contractAddress)`                                                                          | `addOracle`                       | 64   | 713  |
| `OracleUpdated`             | `(uint256 oracleId idx, address oldAddress, address newAddress)`                                                                        | `updateOracle`                    | 91   | 729  |
| `PriceOracleAddressUpdated` | `(address oracle idx)`                                                                                                                  | `setPriceOracle`                  | 78   | 739  |
| `SymbolAdded`               | `(uint256 symbolId idx, string name, OptionType optionType, uint256 oracleId, address collateral, Fee platformFee, uint256 symbolType)` | `addSymbol`                       | 65   | 780  |
| `SymbolStateUpdated`        | `(uint256 symbolId idx, bool status)`                                                                                                   | `setSymbolStates` per-entry       | 74   | 826  |
| `SymbolNameUpdated`         | `(uint256 symbolId idx, string name)`                                                                                                   | `setSymbolNames` per-entry        | 75   | 843  |
| `SymbolTypeUpdated`         | `(uint256 symbolId idx, uint256 symbolType)`                                                                                            | `setSymbolTypes` per-entry        | 76   | 859  |
| `SymbolPlatformFeeUpdated`  | `(uint256 _symbolId idx, Fee _oldFee, Fee _newFee)`                                                                                     | `setSymbolPlatformFees` per-entry | 77   | 807  |

### Verifier, Withdraw Provider, External Transfer

| Event                                           | Signature                                                      | Trigger                                     | Decl | Emit |
| ----------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------- | ---- | ---- |
| `SignatureVerifierUpdated`                      | `(address verifier idx)`                                       | `setSignatureVerifier`                      | 80   | 874  |
| `ExpressWithdrawProviderConfigUpdated`          | `(address provider idx, ExpressWithdrawProviderConfig config)` | `setExpressWithdrawProviderConfig`          | 81   | 894  |
| `InvalidWithdrawalsAmountsPoolUpdated`          | `(address pool idx)`                                           | `setInvalidWithdrawalsAmountsPool`          | 82   | 904  |
| `ExternalTransferTargetValidationStatusUpdated` | `(address target idx, address collateral idx, bool status)`    | `setExternalTransferTargetValidationStatus` | 92   | 926  |
| `TradeNftAddressUpdated`                        | `(address tradeNftAddress idx)`                                | `setTradeNftAddress`                        | 63   | 287  |

`SetManualSync`, `UserWindowUpdated`, `LiquidationDetailUpdated`, `SymbolPriceUpdated` are declared (decl lines 79, 83, 52, 53) but never emitted.

---

## LibScheduledReleaseBalance (library events)

Source: `contracts/libraries/models/LibScheduledReleaseBalance.sol`. These are the low-level balance bookkeeping events emitted by `ScheduledReleaseBalanceOps`. Reasons are enums from `contracts/types/BalanceTypes.sol` (`IncreaseBalanceReason` lines 66–78, `DecreaseBalanceReason` lines 80–92).

### `IncreaseBalance`

`IncreaseBalance(address indexed user, address indexed counterParty, address indexed collateral, uint256 amount, IncreaseBalanceReason reason, bool isInstant, MarginType marginType)`

-   Decl: `LibScheduledReleaseBalance.sol:30-38`
-   Emit: lines 103, 124, 131
-   Fired whenever any balance (cross or isolated) credits a user. `isInstant=true` means the credit is immediately spendable; `false` means it joins the scheduled-release queue. `counterParty == address(0)` for isolated credits.
-   `IncreaseBalanceReason`: `DEPOSIT, INTERNAL_TRANSFER, EXPRESS_WITHDRAW, AFFILIATE_FEE, SOLVER_FEE, PLATFORM_FEE, PREMIUM, REALIZED_PNL, LIQUIDATION, INVALID_WITHDRAWAL, ALLOCATE_FROM_RESERVE`.

### `DecreaseBalance`

`DecreaseBalance(address indexed user, address indexed counterParty, address indexed collateral, uint256 amount, DecreaseBalanceReason reason, MarginType marginType)`

-   Decl: `LibScheduledReleaseBalance.sol:40-47`
-   Emit: lines 143, 168, 190, 201, 212
-   Fired on every debit. `DecreaseBalanceReason`: `WITHDRAW, INTERNAL_TRANSFER, EXPRESS_WITHDRAW, AFFILIATE_FEE, SOLVER_FEE, PLATFORM_FEE, PREMIUM, REALIZED_PNL, CONFISCATE, LIQUIDATION, EXTERNAL_TRANSFER`.
-   Subgraph: paired with `IncreaseBalance`, these are the only reliable source of fine-grained ledger replay because facet-level `Deposit` / `Allocate` events do not break out fee splits.

### `SyncBalance`

`SyncBalance(address indexed user, address indexed counterParty, address indexed collateral)`

-   Decl: line 49
-   Emit: lines 328, 365
-   Marker that scheduled-release balances were drained into spendable. Fires whenever `_syncBalance` actually advances the cursor.

### `LockBalance` / `UnlockBalance`

`LockBalance(address indexed user, address indexed collateral, uint256 amount, MarginType marginType)`
`UnlockBalance(address indexed user, address indexed collateral, uint256 amount, MarginType marginType)`

-   Decl: lines 51, 53
-   Emit: 431, 443 (lock isolated/cross), 437, 450 (unlock isolated/cross)
-   Tracks reservation of balance for pending intents, fees, premium, or margin. Note `counterParty` is not on the signature — the binding is implied by call context (locks are not cross-counterparty-keyed).

---

## LibDiamond / DiamondCutFacet

Source: `contracts/libraries/core/LibDiamond.sol`. Standard EIP-2535 Diamond events.

| Event                      | Signature                                                              | Trigger                                                              | Decl | Emit   |
| -------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------- | ---- | ------ |
| `OwnershipTransferred`     | `(address previousOwner idx, address newOwner idx)`                    | `setContractOwner` and `acceptOwnership`.                            | 38   | 45, 60 |
| `OwnershipTransferStarted` | `(address currentOwner idx, address pendingOwner idx)`                 | `transferOwnership` (two-step).                                      | 39   | 51     |
| `DiamondCut`               | `(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata)` | `diamondCut` after every facet add/replace/remove and init delegate. | 71   | 87     |

`IDiamondCut.sol:31` re-declares `DiamondCut` as part of the standard interface; the actual emit lives in the library.

---

## InstantLayer (helper)

Helper contract at `contracts/helpers/InstantLayer.sol`. Routes signed Party A and Party B operations to the Diamond. Events are inline on the contract.

| Event                      | Signature                                        | Trigger                                                                                | Decl line | Emit line |
| -------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------- | --------- | --------- |
| `TemplateAdded`            | `(uint256 templateId idx, string name)`          | `addTemplate` registers a new operation template.                                      | 148       | 286       |
| `TemplateUpdated`          | `(uint256 templateId idx, bool active)`          | `setTemplateActive` toggles a template.                                                | 151       | 297       |
| `OperationsExecuted`       | `(uint256 templateId idx, address executor idx)` | `executeTemplate` after a successful template run.                                     | 154       | 344       |
| `BatchExecuted`            | `(address executor idx, uint256 operationCount)` | `executeBatch` after a successful template-less batch.                                 | 157       | 374       |
| `NonceIncremented`         | `(address user idx, uint256 newNonce)`           | `_verifyOperation` whenever an operation uses ordered-nonce protection (`nonce != 0`). | 160       | 413       |
| `PartyBRegistered`         | `(address partyB idx)`                           | `registerPartyB` and `registerPartyBBatch`.                                            | 163       | 214, 235  |
| `PartyBUnregistered`       | `(address partyB idx)`                           | `unregisterPartyB`.                                                                    | 166       | 224       |
| `MultiAccountRegistered`   | `(address multiAccount idx)`                     | `registerMultiAccount`, `registerMultiAccountBatch`.                                   | 169       | 245, 264  |
| `MultiAccountUnregistered` | `(address multiAccount idx)`                     | `unregisterMultiAccount`.                                                              | 172       | 254       |

`NonceIncremented` reflects the InstantLayer's own per-user replay nonce — distinct from the Diamond's bilateral nonces. Operations using salt-only mode (`nonce == 0`) do not emit.

---

## MultiAccount (helper)

`contracts/helpers/MultiAccount.sol`. Manages `SymmioPartyA` sub-accounts.

| Event                      | Signature                                                                                   | Trigger                                                               | Decl line | Emit line |
| -------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | --------- | --------- |
| `SetAccountImplementation` | `(bytes oldImplementation, bytes newImplementation)`                                        | `setAccountImplementation` updates the deployed bytecode template.    | 96        | 320       |
| `SetSymmioAddress`         | `(address oldSymmioAddress, address newSymmioAddress)`                                      | `setSymmioAddress` redirects to a new Diamond.                        | 103       | 331       |
| `SetTradeNFTAddress`       | `(address oldTradeNFTAddress, address newTradeNFTAddress)`                                  | `setTradeNFTAddress` redirects to a new TradeNFT.                     | 110       | 342       |
| `AddAccount`               | `(address user idx, address account idx, string name)`                                      | `addAccount` deploys and registers a new `SymmioPartyA` for `user`.   | 118       | 204       |
| `EditAccountName`          | `(address user idx, address accountAddress idx, string name)`                               | `editAccountName`.                                                    | 126       | 217       |
| `DeployContract`           | `(address deployer idx, address contractAddress idx)`                                       | `_deployContract` CREATE2 deployment (called from `addAccount` etc.). | 133       | 307       |
| `Call`                     | `(address sender idx, address account idx, bytes callData, bool success, bytes resultData)` | Every account-level `_call` (`call`, `_callBatch`, etc.).             | 143       | 274       |
| `AdminPartyACall`          | `(address partyA idx, bytes data, bool success, bytes returnData)`                          | `adminPartyACall` admin override route.                               | 152       | 357       |

---

## SymmioPartyA (helper)

`contracts/helpers/SymmioPartyA.sol` — per-user sub-account.

| Event              | Signature                                                              | Trigger                                                                   | Decl | Emit |
| ------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- | ---- | ---- |
| `SetSymmioAddress` | `(address oldSymmioContractAddress, address newSymmioContractAddress)` | `setSymmioAddress` (admin only).                                          | 43   | 82   |
| `NFTTransferred`   | `(address to, uint256 tokenId)`                                        | `transferTradeNFT` after `IERC721.safeTransferFrom` succeeds (try/catch). | 50   | 136  |

---

## SymmioPartyB (helper)

`contracts/helpers/SymmioPartyB.sol` — Party B operator router.

| Event                   | Signature                                              | Trigger                                                 | Decl | Emit |
| ----------------------- | ------------------------------------------------------ | ------------------------------------------------------- | ---- | ---- |
| `SetSymmioAddress`      | `(address oldSymmioAddress, address newSymmioAddress)` | `setSymmioAddress`.                                     | 85   | 147  |
| `SetRestrictedSelector` | `(bytes4 selector, bool state)`                        | `setRestrictedSelector` toggles MANAGER-only selectors. | 92   | 160  |
| `SetMulticastWhitelist` | `(address addr, bool state)`                           | `setMulticastWhitelist`.                                | 99   | 183  |

---

## TradeNFT (helper)

`contracts/helpers/TradeNFT.sol` (ERC-721 representation of trades).

| Event                 | Signature                                                             | Trigger                                                                                                     | Decl | Emit |
| --------------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---- | ---- |
| `TradeNFTMinted`      | `(address indexed owner, uint256 indexed tokenId)`                    | `mintNFTForTrade` (only Symmio Diamond). `tokenId == tradeId`.                                              | 64   | 104  |
| `TradeNFTTransferred` | `(uint256 indexed tokenId, address indexed from, address indexed to)` | `_beforeTokenTransfer` for user-initiated transfers (skipped when transfer was initiated from the Diamond). | 72   | 158  |

Note: standard ERC-721 `Transfer` and `Approval` events are also emitted by the OpenZeppelin parent.

---

## MuonOracle (helper)

`contracts/helpers/MuonOracle.sol` implements `IMuonOracle`.

| Event           | Signature                | Trigger                    | Decl                                     | Emit |
| --------------- | ------------------------ | -------------------------- | ---------------------------------------- | ---- |
| `ConfigUpdated` | `(MuonConfig newConfig)` | `setConfig` (SETTER role). | `contracts/interfaces/IMuonOracle.sol:7` | 49   |

`CheckGatewaySignatureUpdated(bool newValue)` is declared at `IMuonOracle.sol:8` but no setter currently emits it.

---

## Defined But Not Emitted

The following events exist in interfaces but no contract currently emits them. Indexers can ignore them until a future version wires them up.

| Event                          | Declared at                                                  |
| ------------------------------ | ------------------------------------------------------------ |
| `FullyLiquidated`              | `contracts/facets/ClearingHouse/IClearingHouseEvents.sol:37` |
| `RoleUpdated`                  | `contracts/facets/Control/IControlEvents.sol:47`             |
| `LiquidationDetailUpdated`     | `contracts/facets/Control/IControlEvents.sol:52`             |
| `SymbolPriceUpdated`           | `contracts/facets/Control/IControlEvents.sol:53`             |
| `SetManualSync`                | `contracts/facets/Control/IControlEvents.sol:79`             |
| `UserWindowUpdated`            | `contracts/facets/Control/IControlEvents.sol:83`             |
| `CheckGatewaySignatureUpdated` | `contracts/interfaces/IMuonOracle.sol:8`                     |

---

## Cross-Cutting Patterns

### Nonces

-   The Diamond uses bilateral `nonces[partyA][partyB][collateral]` for cross-margin actions, but does not emit a dedicated nonce event — clients read the post-state from facet calls or the `ViewFacet`.
-   `InstantLayer.NonceIncremented` is the only on-chain nonce event and only fires when the operation uses ordered-nonce mode (`nonce != 0`); salt-only mode is silent.
-   `BindToPartyB` / `Initiate|Complete|CancelUnbindingFromPartyB` define when a bilateral relation exists, which is the base for nonce-keyed off-chain signing.

### Intent IDs vs Trade IDs

-   `intentId` is the primary key for `OpenIntent` and `CloseIntent` lifecycles. Carriers: `SendOpenIntent`, `LockOpenIntent`, `UnlockOpenIntent`, `AcceptCancelOpenIntent`, `CancelOpenIntent`, `ExpireOpenIntent`, `ForceCancelOpenIntent`, `SendCloseIntent`, `FillCloseIntent`, `CancelCloseIntent`, `ExpireCloseIntent`, `ForceCancelCloseIntent`, `AcceptCancelCloseIntent`, `CancelOpenIntentsForLiquidation`, `CancelCloseIntentsForLiquidation`.
-   `tradeId` is the primary key for `Trade`. Carriers: `FillOpenIntent` (creates), `SendCloseIntent` (references), `TransferTradeByPartyA`, `TradeNFTMinted`, `TradeNFTTransferred`, `ExecuteTrades`, `CloseTradesForLiquidation`. `tokenId` on TradeNFT events equals `tradeId`.
-   `liquidationId` joins all clearing-house events (`Confiscate`, `LiquidateCrossPartyA`, `DistributeCollateral`, `CloseTradesForLiquidation`, `AllocateFromReserveToCross` derived from context, `CancelOpenIntentsForLiquidation`, `CancelCloseIntentsForLiquidation`).
-   `withdrawId` (`uint256 id` in `InitiateWithdraw`/`InitiateExpressWithdraw`) is the key for the withdrawal lifecycle.

### Off-chain replay and state reconstruction

-   `SendOpenIntent` is the canonical "create" event for intents (covers both fresh creation in `PartyAOpenFacet` and residual creation inside `PartyBOpenFacet.fillOpenIntent`). Indexers must subscribe to both source files.
-   `LibScheduledReleaseBalance.IncreaseBalance` / `DecreaseBalance` / `SyncBalance` together are the authoritative ledger for ScheduledReleaseBalance; facet-level `Deposit`, `Allocate`, etc. are coarser and can be cross-checked against them.
-   `TransferTradeByPartyA` is fired in two places: direct `transferTrade` and the NFT callback `transferTradeFromNFT`. Pair with `TradeNFTTransferred` to disambiguate the source.
-   `ExecuteTrades` carries arrays — split per index for per-trade indexing; align `tradeIds[i]` with `exercised[i]` and `expired[i]`.
-   Pause/unpause events from `ControlFacet` are the only on-chain signal of operational state; they're flag-style with no payload, so indexers must maintain a running stack from each pair.
-   `DiamondCut` fully describes facet topology changes; replaying it from genesis reproduces the current selector → facet routing.
