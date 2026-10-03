---
title: Facet API Reference
aliases:
    - Facet API
    - Diamond Functions
    - Public API
tags:
    - symmio
    - options-core
    - reference
---

# Facet API Reference

This document is the per-facet, per-function reference for every selector exposed by the Diamond. Each section lists signatures, the caller restriction, the modifiers applied at the facet, the precondition asserted by the called core library, the resulting state effect, the events emitted, and the most relevant revert paths. Source citations point at the implementation in `contracts/facets/<Name>/<File>.sol`. For end-to-end semantics see [[architecture]] and the flows under [docs/flows](../flows). Pause flag, role, and modifier definitions live in [[roles-and-pauses]].

## Contents

- [AccountFacet](#accountfacet)
- [ClearingHouseFacet](#clearinghousefacet)
- [ControlFacet](#controlfacet)
- [CounterPartyRelationsFacet](#counterpartyrelationsfacet)
- [DiamondCutFacet](#diamondcutfacet)
- [DiamondLoupeFacet](#diamondloupefacet)
- [ForceActionsFacet](#forceactionsfacet)
- [PartyAOpenFacet](#partyaopenfacet)
- [PartyACloseFacet](#partyaclosefacet)
- [PartyBOpenFacet](#partybopenfacet)
- [PartyBCloseFacet](#partybclosefacet)
- [TradeFacet](#tradefacet)
- [ViewFacet](#viewfacet)

Notation: pause modifier names follow `Pausable`/`Accessibility`. `whenPartyNotPaused(addr)` asserts the global pause and the per-side (Party A or Party B) pause that applies to `addr`. `whenInstantModeIsNotActive` asserts that Party A has not enabled instant action mode for delegated execution. `onlyNotPartyB`/`onlyPartyB` is enforced through `AppStorage.partyBConfigs[addr].isActive`. Caller restrictions citing "msg.sender = Party A" mean an account that is not configured as a Party B.

---

## AccountFacet

Source: `contracts/facets/Account/AccountFacet.sol`. Owner of deposit, withdrawal, internal/external transfer, allocation, and reserve flows. Amounts entering through `deposit*` are denominated in collateral decimals; all other amounts are 18-decimal normalized.

### Deposits

#### `deposit(address collateral, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:36`
- Caller: any non-suspended address (Party A or Party B).
- Modifiers: `nonReentrant`, `whenDepositingNotPaused`, `whenNotSuspended(msg.sender)`, `whenPartyNotPaused(msg.sender)`.
- Precondition: `collateral` is whitelisted; the per-user balance limit (if set) is not exceeded.
- Effect: pulls `amount` of `collateral`, normalizes to 18 decimals, increases `msg.sender`'s isolated balance.
- Events: `Deposit(sender, user, collateral, amount, newBalance)`.
- Reverts: `CollateralNotWhitelisted`, `BalanceLimitReached`, ERC-20 transfer failure.

#### `depositFor(address collateral, address user, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:68`
- Caller: any non-suspended address. Sender funds; `user` is credited.
- Modifiers: `nonReentrant`, `whenDepositingNotPaused`, `whenNotSuspended(msg.sender)`, `whenNotSuspended(user)`, `whenPartyNotPaused(msg.sender)`, `whenPartyNotPaused(user)`.
- Effect: same as `deposit` but credits `user`.
- Events: `Deposit(sender, user, collateral, amount, newBalance)`.

#### `virtualDepositFor(address collateral, address user, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:51`
- Caller: holders of `VIRTUAL_DEPOSITOR_ROLE`. Increases `user`'s isolated balance without pulling tokens.
- Modifiers: `whenDepositingNotPaused`, `whenNotSuspended(user)`, `onlyRole(VIRTUAL_DEPOSITOR_ROLE)`.
- Events: `Deposit`, `VirtualDeposit`.

### Transfers

#### `internalTransfer(address collateral, address user, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:92`
- Caller: Party A only (`onlyNotPartyB(msg.sender)`).
- Modifiers: `whenInternalTransferNotPaused`, both-side `whenNotSuspended`, `whenInstantModeIsNotActive(msg.sender)`, both-side `whenPartyNotPaused`, `onlyNotPartyB(msg.sender)`.
- Effect: moves isolated balance from sender to `user`.
- Events: `InternalTransfer(sender, user, collateral, amount, newRecipientBalance, newSenderBalance)`.

#### `externalTransfer(address collateral, address user, uint256 amount, address target)`

- Source: `contracts/facets/Account/AccountFacet.sol:125`
- Caller: any non-suspended account, no instant mode.
- Modifiers: `nonReentrant`, `whenNotExternalTransferPaused`, `whenNotSuspended(msg.sender)`, `whenInstantModeIsNotActive(msg.sender)`, `whenPartyNotPaused(msg.sender)`.
- Precondition: `target` is configured as a valid `IExternalTransferTarget` for `collateral`.
- Effect: debits sender's isolated balance; calls `target.deposit(...)` after token transfer.
- Events: `ExternalTransfer(sender, user, collateral, amount, target)`.

### Withdrawals

#### `initiateWithdraw(address collateral, uint256 amount, address to)`

- Source: `contracts/facets/Account/AccountFacet.sol:149`
- Caller: Party A or Party B (the underlying user).
- Modifiers: `whenWithdrawingNotPaused`, `whenNotSuspended(msg.sender)`, `whenInstantModeIsNotActive(msg.sender)`, `whenNotSuspended(to)`, `whenPartyNotPaused(msg.sender)`.
- Effect: locks `amount` (18-decimal) from sender's isolated balance into a pending `Withdraw` record. The release time is set to `block.timestamp + releaseInterval(msg.sender)`.
- Events: `InitiateWithdraw(id, user, to, collateral, amount, newBalance)`.

#### `initiateExpressWithdraw(address collateral, uint256 amount, address to, address provider, bytes userData)`

- Source: `contracts/facets/Account/AccountFacet.sol:174`
- Caller: same as `initiateWithdraw` but `provider` must be a configured `IExpressWithdrawProvider` for `collateral`.
- Modifiers: `nonReentrant`, `whenWithdrawingNotPaused`, `whenNotExpressWithdrawPaused`, suspension and party-pause checks as above.
- Events: `InitiateWithdraw`, `InitiateExpressWithdraw(id, user, to, collateral, provider, userData, amount, newBalance)`.

#### `completeWithdraw(uint256 id)`

- Source: `contracts/facets/Account/AccountFacet.sol:221`
- Caller: anyone; the credited destination is fixed in the `Withdraw` record.
- Modifiers: `nonReentrant`, `whenWithdrawingNotPaused`, `whenWithdrawalNotSuspended(id)`, `whenPartyNotPaused(msg.sender)`.
- Precondition: withdrawal exists, has not been completed/canceled, and its scheduled release time has passed.
- Effect: transfers tokens out; for express withdrawals, settles via the provider.
- Events: `CompleteWithdraw(id)`.

#### `cancelWithdraw(uint256 id)`

- Source: `contracts/facets/Account/AccountFacet.sol:233`
- Caller: the original withdrawer.
- Modifiers: `whenWithdrawingNotPaused`, `whenWithdrawalNotSuspended(id)`, `whenPartyNotPaused(msg.sender)`.
- Effect: returns funds to user's isolated balance.
- Events: `CancelWithdraw(id, user, collateral, amount, newBalance)`.

#### `suspendWithdraw(uint256 id)`

- Source: `contracts/facets/Account/AccountFacet.sol:200`
- Caller: `SUSPENDER_ROLE`.
- Effect: marks withdrawal `id` as suspended, blocking complete/cancel.
- Events: `SuspendWithdraw(id, suspender)`.

#### `restoreWithdraw(uint256 id, uint256 validAmount)`

- Source: `contracts/facets/Account/AccountFacet.sol:211`
- Caller: `DISPUTER_ROLE`. Re-enables the withdrawal at a possibly reduced `validAmount`; the difference is routed to the invalid withdrawals pool.
- Events: `RestoreWithdraw(id, validAmount)`.

### Sync, Allocation, Reserve

#### `syncBalances(address collateral, address partyA, address[] partyBs)`

- Source: `contracts/facets/Account/AccountFacet.sol:252`
- Caller: anyone. No pause modifiers.
- Effect: forces release of any matured scheduled-release entries between `partyA` and each `partyB` for `collateral` (cross-margin).

#### `allocate(address collateral, address counterParty, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:262`
- Caller: any non-suspended account, no instant mode.
- Modifiers: `whenNotSuspended(msg.sender)`, `whenInstantModeIsNotActive(msg.sender)`, `whenPartyNotPaused(msg.sender)`.
- Effect: moves `amount` from sender's isolated balance into the cross balance with `counterParty`.
- Events: `Allocate(user, collateral, counterParty, amount, newIsolatedBalance, newCrossBalance)`.

#### `deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig upnlSig)`

- Source: `contracts/facets/Account/AccountFacet.sol:286`
- Caller: cross-margin participant. `upnlSig` is a Muon-verified upnl snapshot used to enforce solvency.
- Modifiers: same trio as `allocate`.
- Precondition: post-deallocation cross balance must remain solvent at `upnlSig.upnl`; deallocate cooldown must have elapsed (`partyADeallocateCooldown` or `partyBDeallocateCooldown`).
- Effect: moves `amount` back to isolated balance; bumps bilateral nonce.
- Events: `Deallocate(user, collateral, counterParty, amount, newIsolatedBalance, newCrossBalance)`.

#### `allocateToReserveBalance(address collateral, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:309`
- Caller: Party A or Party B. Moves isolated balance into reserve balance for clearing-house use.
- Events: `AllocateToReserveBalance(user, collateral, amount, newIsolatedBalance)`.

#### `deallocateFromReserveBalance(address collateral, uint256 amount)`

- Source: `contracts/facets/Account/AccountFacet.sol:322`
- Caller: same as above. Moves reserve balance back to isolated.
- Events: `DeallocateFromReserveBalance(user, collateral, amount, newIsolatedBalance)`.

---

## ClearingHouseFacet

Source: `contracts/facets/ClearingHouse/ClearingHouseFacet.sol`. Liquidation pipeline. Every function is `whenNotLiquidationPaused` and `onlyRole(CLEARING_HOUSE_ROLE)`.

### Isolated Party B Liquidation

| Function                                                             | Source | Effect                                                                                                    | Event                             |
| -------------------------------------------------------------------- | ------ | --------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `flagIsolatedPartyBLiquidation(partyB, collateral)`                  | `:26`  | Marks `partyB` flagged for isolated liquidation on `collateral`; blocks downstream actions for that pair. | `FlagIsolatedPartyBLiquidation`   |
| `unflagIsolatedPartyBLiquidation(partyB, collateral)`                | `:39`  | Clears flag if Party B has recovered.                                                                     | `UnflagIsolatedPartyBLiquidation` |
| `liquidateIsolatedPartyB(partyB, collateral, upnl, collateralPrice)` | `:54`  | Allocates a new `liquidationId`, captures snapshot from upnl/price, freezes balances.                     | `LiquidateIsolatedPartyB`         |

### Cross Party B Liquidation

| Function                                                                  | Source | Effect                                                      | Event                          |
| ------------------------------------------------------------------------- | ------ | ----------------------------------------------------------- | ------------------------------ |
| `flagCrossPartyBLiquidation(partyB, partyA, collateral)`                  | `:92`  | Flags Party B in the cross context with a specific Party A. | `FlagCrossPartyBLiquidation`   |
| `unflagCrossPartyBLiquidation(partyB, partyA, collateral)`                | `:101` | Clears the cross flag.                                      | `UnflagCrossPartyBLiquidation` |
| `liquidateCrossPartyB(partyB, partyA, collateral, upnl, collateralPrice)` | `:110` | Snapshots and starts cross liquidation for Party B.         | `LiquidateCrossPartyB`         |

### Cross Party A Liquidation

| Function                                                                                 | Source | Effect                                                             | Event                     |
| ---------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------ | ------------------------- |
| `flagPartyALiquidation(partyA, partyB, collateral)`                                      | `:121` | Flags Party A.                                                     | `FlagPartyALiquidation`   |
| `unflagPartyALiquidation(partyA, partyB, collateral)`                                    | `:130` | Clears Party A flag.                                               | `UnflagPartyALiquidation` |
| `liquidateCrossPartyA(liquidationId, partyA, partyB, collateral, upnl, collateralPrice)` | `:139` | Executes cross Party A liquidation under existing `liquidationId`. | `LiquidateCrossPartyA`    |

### Liquidation Cleanup and Distribution

| Function                                                                                    | Source | Effect                                                                                      | Event                              |
| ------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------- | ---------------------------------- |
| `closeTrades(liquidationId, tradeIds[], prices[])`                                          | `:151` | Closes trades belonging to the liquidated party at supplied prices.                         | `CloseTradesForLiquidation`        |
| `cancelOpenIntents(intentIds[])`                                                            | `:170` | Cancels open intents for the liquidated party.                                              | `CancelOpenIntentsForLiquidation`  |
| `cancelCloseIntents(intentIds[])`                                                           | `:175` | Cancels close intents for the liquidated party.                                             | `CancelCloseIntentsForLiquidation` |
| `confiscate(liquidationId, amount, party, counterParty, marginType)`                        | `:64`  | Confiscates `amount` from `party` into the liquidation pool for the given margin type.      | `Confiscate`                       |
| `confiscateWithdrawal(withdrawId)`                                                          | `:75`  | Pulls a pending withdrawal into the liquidation pool.                                       | `ConfiscateWithdrawal`             |
| `distributeCollateral(liquidationId, partyB, collateral, marginType, partyAs[], amounts[])` | `:80`  | Distributes pooled collateral back to multiple Party As.                                    | `DistributeCollateral`             |
| `allocateFromReserveToCross(party, counterParty, collateral, amount)`                       | `:160` | During liquidation, taps `party`'s reserve to top up its cross balance with `counterParty`. | `AllocateFromReserveToCross`       |

Reverts across this facet are concentrated in `LibClearingHouse` and the validation library: `LiquidationNotInProgress`, `AlreadyFlagged`, `InvalidLiquidationState`, `Insolvent`, `InvalidPartyMatch`, etc.

---

## ControlFacet

Source: `contracts/facets/Control/ControlFacet.sol`. Configuration surface for roles, parameters, fees, symbols, oracles, pauses, suspensions, and emergency switches. All setters revert on zero address where applicable (`ValidationErrors.ZeroAddress`).

### Access Control

| Function                                   | Source | Caller                      | Effect                                                                       |
| ------------------------------------------ | ------ | --------------------------- | ---------------------------------------------------------------------------- |
| `setAdmin(address _admin)`                 | `:53`  | `onlyOwner` (Diamond owner) | Grants `DEFAULT_ADMIN_ROLE`; emits `RoleGranted`.                            |
| `grantRole(address _user, bytes32 _role)`  | `:65`  | `DEFAULT_ADMIN_ROLE`        | Adds role and role-member set entry; emits `RoleGranted` only on transition. |
| `revokeRole(address _user, bytes32 _role)` | `:81`  | `DEFAULT_ADMIN_ROLE`        | Removes role; emits `RoleRevoked` only on transition.                        |

### Collateral

| Function                                             | Source | Caller        | Effect                                                             |
| ---------------------------------------------------- | ------ | ------------- | ------------------------------------------------------------------ |
| `whiteListCollateral(address _collateral)`           | `:99`  | `SETTER_ROLE` | Whitelists collateral for deposits. Emits `CollateralWhitelisted`. |
| `removeCollateralFromWhitelist(address _collateral)` | `:109` | `SETTER_ROLE` | De-whitelists. Emits `CollateralRemovedFromWhitelist`.             |

### System Parameters and Limits

| Function                                        | Source | Caller        | Effect / Event                                                                                  |
| ----------------------------------------------- | ------ | ------------- | ----------------------------------------------------------------------------------------------- |
| `setMaxCloseOrdersLength(uint256)`              | `:122` | `SETTER_ROLE` | `MaxCloseOrdersLengthUpdated`. Reverts `ZeroAmount`.                                            |
| `setMaxTradePerPartyA(uint256)`                 | `:132` | `SETTER_ROLE` | `MaxTradePerPartyAUpdated`. Reverts `ZeroAmount`.                                               |
| `setBalanceLimitPerUser(address, uint256)`      | `:143` | `SETTER_ROLE` | `BalanceLimitPerUserUpdated`.                                                                   |
| `setTimingParameters(...nine uints)`            | `:162` | `SETTER_ROLE` | Sets every cooldown/timeout in one transaction; emits the nine corresponding `*Updated` events. |
| `setPartyADeallocateCooldown(uint256)`          | `:204` | `SETTER_ROLE` | `PartyADeallocateCooldownUpdated`.                                                              |
| `setPartyBDeallocateCooldown(uint256)`          | `:213` | `SETTER_ROLE` | `PartyBDeallocateCooldownUpdated`.                                                              |
| `setForceCancelOpenIntentTimeout(uint256)`      | `:222` | `SETTER_ROLE` | `ForceCancelOpenIntentTimeoutUpdated`.                                                          |
| `setForceCancelCloseIntentTimeout(uint256)`     | `:231` | `SETTER_ROLE` | `ForceCancelCloseIntentTimeoutUpdated`.                                                         |
| `setSettlementPriceSigValidTime(uint256)`       | `:240` | `SETTER_ROLE` | `SettlementPriceSigValidTimeUpdated`.                                                           |
| `setUpnlSigValidTime(uint256)`                  | `:249` | `SETTER_ROLE` | `UpnlSigValidTimeUpdated`.                                                                      |
| `setPartyBExclusiveWindow(uint256)`             | `:258` | `SETTER_ROLE` | `PartyBExclusiveWindowUpdated`.                                                                 |
| `setUnbindingCooldown(uint256)`                 | `:267` | `SETTER_ROLE` | `UnbindingCooldownUpdated`.                                                                     |
| `setDeactiveInstantActionModeCooldown(uint256)` | `:276` | `SETTER_ROLE` | `DeactiveInstantActionModeCooldownUpdated`.                                                     |
| `setTradeNftAddress(address)`                   | `:285` | `SETTER_ROLE` | `TradeNftAddressUpdated`.                                                                       |
| `setPartyBReleaseInterval(address, uint256)`    | `:299` | `SETTER_ROLE` | Marks the interval as configured. Emits `PartyBReleaseIntervalUpdated`.                         |
| `setDefaultReleaseInterval(uint256)`            | `:310` | `SETTER_ROLE` | `DefaultReleaseIntervalUpdated`.                                                                |
| `setMaxConnectedCounterParties(uint256)`        | `:319` | `SETTER_ROLE` | `MaxConnectedCounterPartiesUpdated`. Reverts `ZeroAmount`.                                      |

### Fees

| Function                                                                | Source | Caller                                                                              | Effect                                                                                                            |
| ----------------------------------------------------------------------- | ------ | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `setDefaultFeeCollector(address)`                                       | `:333` | `SETTER_ROLE`                                                                       | `DefaultFeeCollectorUpdated`.                                                                                     |
| `setAffiliateStatus(address, bool)`                                     | `:344` | `AFFILIATE_MANAGER_ROLE`                                                            | `AffiliateStatusUpdated`.                                                                                         |
| `setAffiliateFeesCollector(address, address)`                           | `:354` | `AFFILIATE_MANAGER_ROLE`                                                            | `AffiliateFeesCollectorUpdated`.                                                                                  |
| `setAffiliateFees(address _affiliate, uint256[] symbolIds, Fee[] fees)` | `:366` | `SETTER_ROLE`; if `_affiliate != msg.sender` then also `AFFILIATE_FEE_MANAGER_ROLE` | Per-symbol fee table; emits `AffiliateFeesUpdated` per symbol. Reverts `MismatchedLengths`, `UnauthorizedSender`. |

### Party B Configuration

| Function                                                    | Source | Caller                 | Effect                                                                                                       |
| ----------------------------------------------------------- | ------ | ---------------------- | ------------------------------------------------------------------------------------------------------------ |
| `setPartyBConfig(address, PartyBConfig)`                    | `:392` | `PARTY_B_MANAGER_ROLE` | Activates/configures Party B; if active, verifies oracleId. Forces manual sync. Emits `PartyBConfigUpdated`. |
| `setPartyBSupportedSymbolTypes(address, uint256[], bool[])` | `:407` | `PARTY_B_MANAGER_ROLE` | Per-type support toggles. Emits `PartyBSupportedSymbolTypesUpdated`.                                         |

### Pauses (all `PAUSER_ROLE` for pause, `UNPAUSER_ROLE` for unpause)

| Pause / Unpause     | Source pause / unpause | Event pair                                              |
| ------------------- | ---------------------- | ------------------------------------------------------- |
| Global              | `:430` / `:520`        | `GlobalPaused` / `GlobalUnpaused`                       |
| Deposit             | `:438` / `:528`        | `DepositPaused` / `DepositUnpaused`                     |
| Withdraw            | `:446` / `:536`        | `WithdrawPaused` / `WithdrawUnpaused`                   |
| Express withdraw    | `:454` / `:560`        | `ExpressWithdrawPaused` / `ExpressWithdrawUnpaused`     |
| Internal transfer   | `:462` / `:544`        | `InternalTransferPaused` / `InternalTransferUnpaused`   |
| External transfer   | `:470` / `:552`        | `ExternalTransferPaused` / `ExternalTransferUnpaused`   |
| Party B actions     | `:478` / `:568`        | `PartyBActionsPaused` / `PartyBActionsUnpaused`         |
| Party A actions     | `:486` / `:576`        | `PartyAActionsPaused` / `PartyAActionsUnpaused`         |
| Liquidating         | `:494` / `:584`        | `LiquidatingPaused` / `LiquidatingUnpaused`             |
| Third-party actions | `:502` / `:592`        | `ThirdPartyActionsPaused` / `ThirdPartyActionsUnpaused` |
| Instant layer       | `:510` / `:600`        | `InstantLayerPaused` / `InstantLayerUnpaused`           |

### Emergency Modes

| Function                               | Source | Caller          | Effect                                                               |
| -------------------------------------- | ------ | --------------- | -------------------------------------------------------------------- |
| `activePartyBsEmergencyMode()`         | `:612` | `PAUSER_ROLE`   | Sets global Party B emergency flag. `PartyBsEmergencyModeActivated`. |
| `deactivePartyBsEmergencyMode()`       | `:620` | `UNPAUSER_ROLE` | Clears global emergency. `PartyBsEmergencyModeDeactivated`.          |
| `activePartyBEmergencyMode(address)`   | `:629` | `PAUSER_ROLE`   | Per-Party-B emergency. `PartyBEmergencyModeActivated`.               |
| `deactivePartyBEmergencyMode(address)` | `:639` | `UNPAUSER_ROLE` | `PartyBEmergencyModeDeactivated`.                                    |

### Suspension

| Function                              | Source | Caller           | Effect                                                                  |
| ------------------------------------- | ------ | ---------------- | ----------------------------------------------------------------------- |
| `suspendAddress(address, bool)`       | `:654` | `SUSPENDER_ROLE` | Per-address suspension. `AddressSuspended`.                             |
| `suspendAddresses(address[], bool[])` | `:676` | `SUSPENDER_ROLE` | Batch variant. Reverts `MismatchedLengths`.                             |
| `suspendWithdrawal(uint256, bool)`    | `:665` | `SUSPENDER_ROLE` | Per-withdrawal suspension. `WithdrawalSuspended`. Reverts `ZeroAmount`. |

### Oracles and Symbols

| Function                                                                     | Source | Caller                | Effect                                                                                     |
| ---------------------------------------------------------------------------- | ------ | --------------------- | ------------------------------------------------------------------------------------------ |
| `addOracle(string, address)`                                                 | `:706` | `ORACLE_MANAGER_ROLE` | Allocates new oracle id, persists `Oracle`. `OracleAdded`. Reverts `EmptyField`.           |
| `updateOracle(uint256, address)`                                             | `:721` | `ORACLE_MANAGER_ROLE` | Overwrites contract address of existing oracle. `OracleUpdated`. Reverts `OracleNotFound`. |
| `setPriceOracleAddress(address)`                                             | `:736` | `ORACLE_MANAGER_ROLE` | Sets `IPriceOracle`. `PriceOracleAddressUpdated`.                                          |
| `addSymbol(name, optionType, oracleId, collateral, platformFee, symbolType)` | `:755` | `SYMBOL_MANAGER_ROLE` | Allocates symbol id; verifies oracle. `SymbolAdded`.                                       |
| `addSymbols(Symbol[])`                                                       | `:787` | `SYMBOL_MANAGER_ROLE` | Batch add.                                                                                 |
| `setSymbolsPlatformFees(uint256[], Fee[])`                                   | `:799` | `SYMBOL_MANAGER_ROLE` | Updates per-symbol platform fee. `SymbolPlatformFeeUpdated`. Reverts `InvalidSymbol`.      |
| `setSymbolsValidationState(uint256[], bool[])`                               | `:816` | `SYMBOL_MANAGER_ROLE` | Marks symbols valid/invalid. `SymbolStateUpdated`.                                         |
| `setSymbolsNames(uint256[], string[])`                                       | `:835` | `SYMBOL_MANAGER_ROLE` | Renames symbols. `SymbolNameUpdated`. Reverts `EmptyField`.                                |
| `setSymbolsTypes(uint256[], uint256[])`                                      | `:852` | `SYMBOL_MANAGER_ROLE` | Updates symbol type. `SymbolTypeUpdated`.                                                  |

### Signature, Withdraw, Targets, Instant Layer

| Function                                                                                                | Source | Caller                                  | Effect                                                                                                       |
| ------------------------------------------------------------------------------------------------------- | ------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `setSignatureVerifier(address)`                                                                         | `:871` | `SETTER_ROLE`                           | `SignatureVerifierUpdated`.                                                                                  |
| `setExpressWithdrawProviderConfig(address provider, address collateral, ExpressWithdrawProviderConfig)` | `:887` | `SETTER_ROLE`                           | `ExpressWithdrawProviderConfigUpdated`.                                                                      |
| `setInvalidWithdrawalsAmountsPool(address)`                                                             | `:901` | `SETTER_ROLE`                           | `InvalidWithdrawalsAmountsPoolUpdated`.                                                                      |
| `setExternalTransferTargetValidationStatus(address target, address collateral, bool)`                   | `:917` | `EXTERNAL_TRANSFER_TARGET_MANAGER_ROLE` | `ExternalTransferTargetValidationStatusUpdated`.                                                             |
| `setCallFromInstantLayer(bool)`                                                                         | `:937` | `INSTANT_LAYER_ROLE`                    | Toggles diamond-side instant-layer flag. Reverts `SystemErrors.InstantLayerPaused` if enabling while paused. |

---

## CounterPartyRelationsFacet

Source: `contracts/facets/CounterPartyRelations/CounterPartyRelationsFacet.sol`. Manages Party A → Party B binding and instant action mode (delegated execution from `InstantLayer`). All functions are `onlyNotPartyB(msg.sender)` and `whenPartyNotPaused(msg.sender)`.

### `activateInstantActionMode()`

- Source: `:29`
- Caller: Party A.
- Modifiers: `onlyNotPartyB`, `whenInstantModeIsNotActive(msg.sender)`, `whenPartyNotPaused`.
- Effect: enables instant mode for `msg.sender` immediately.
- Events: `ActivateInstantActionMode(user, timestamp)`.

### `proposeToDeactivateInstantActionMode()`

- Source: `:38`
- Caller: Party A with instant mode active.
- Modifiers: `whenInstantModeIsActive(msg.sender)`.
- Effect: schedules deactivation at `block.timestamp + deactiveInstantActionModeCooldown`.
- Events: `ProposeToDeactivateInstantActionMode(user, timestamp)`.

### `deactivateInstantActionMode()`

- Source: `:52`
- Caller: Party A. Requires the cooldown set by `proposeToDeactivateInstantActionMode` to have elapsed.
- Effect: clears the instant-mode flag.
- Events: `DeactivateInstantActionMode(user, timestamp)`.

### `bindToPartyB(address partyB)`

- Source: `:62`
- Caller: Party A. `partyB` must be active in `partyBConfigs`.
- Effect: writes `boundPartyB[msg.sender] = partyB`.
- Events: `BindToPartyB(partyA, partyB)`.
- Reverts: `AlreadyBound`, `PartyBNotActive`.

### `initiateUnbindingFromPartyB()`

- Source: `:71`
- Caller: Party A with an existing binding.
- Effect: stamps `unbindingRequestTime[msg.sender]`.
- Events: `InitiateUnbindingFromPartyB(partyA, currentBoundPartyB, timestamp)`.

### `completeUnbindingFromPartyB()`

- Source: `:80`
- Caller: Party A. Requires `unbindingCooldown` elapsed since initiate.
- Effect: clears `boundPartyB` and `unbindingRequestTime`.
- Events: `CompleteUnbindingFromPartyB(partyA, previousPartyB)`.

### `cancelUnbindingFromPartyB()`

- Source: `:90`
- Caller: Party A during cooldown window.
- Effect: clears `unbindingRequestTime`.
- Events: `CancelUnbindingFromPartyB(partyA, currentBoundPartyB)`.

---

## DiamondCutFacet

Source: `contracts/facets/DiamondCut/DiamondCutFacet.sol`.

### `diamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata)`

- Source: `:20`
- Caller: Diamond contract owner (`LibDiamond.enforceIsContractOwner`).
- Effect: bumps `AppStorage.version`; adds, replaces, or removes selectors per `_diamondCut`; if `_init != address(0)`, delegatecalls `_calldata` on `_init` for initialization.
- Events: `DiamondCut(_diamondCut, _init, _calldata)`.
- Reverts: `LibDiamond.NotContractOwner`, `IncorrectFacetCutAction`, `NoSelectorsInFacetForCut`, `CannotAddFunctionToDiamondThatAlreadyExists`, `CannotReplaceFunctionThatDoesNotExists`, `CannotRemoveFunctionThatDoesNotExist`, init delegatecall reverts.

---

## DiamondLoupeFacet

Source: `contracts/facets/DiamondLoupe/DiamondLoupeFacet.sol`. All functions are `view`, no access control or pause guards. Implements EIP-2535 loupe and ERC-165.

| Function                                 | Source | Returns                                                                                                     |
| ---------------------------------------- | ------ | ----------------------------------------------------------------------------------------------------------- |
| `facets()`                               | `:18`  | Array of `Facet { address facetAddress; bytes4[] functionSelectors; }` for every facet currently installed. |
| `facetFunctionSelectors(address _facet)` | `:72`  | Selectors registered to a single facet address; empty if none.                                              |
| `facetAddresses()`                       | `:94`  | Deduplicated list of facet addresses.                                                                       |
| `facetAddress(bytes4 _functionSelector)` | `:131` | Facet address handling the selector, or `address(0)` if not registered.                                     |
| `supportsInterface(bytes4 _interfaceId)` | `:137` | ERC-165 support flag from `LibDiamond.diamondStorage().supportedInterfaces`.                                |

---

## ForceActionsFacet

Source: `contracts/facets/ForceActions/ForceActionsFacet.sol`. Lets anyone push an intent past an unresponsive Party B once timeouts elapse. Both functions are `whenPartyNotPaused(msg.sender)`.

### `forceCancelOpenIntent(uint256 intentId)`

- Source: `:25`
- Caller: anyone. Intent must be in `CANCEL_PENDING` and `block.timestamp > intent.statusModifyTimestamp + forceCancelOpenIntentTimeout`.
- Effect: transitions intent to `CANCELED`; releases Party A's normal open-intent locks or deferred Party B sell escrow.
- Events: `ForceCancelOpenIntent(intentId)`.
- Reverts: `ForceCancelCooldown`, `InvalidIntentStatus`.

### `forceCancelCloseIntent(uint256 intentId)`

- Source: `:36`
- Caller: anyone. Close intent must be `CANCEL_PENDING` and timeout elapsed (`forceCancelCloseIntentTimeout`).
- Effect: transitions close intent to `CANCELED`; trade returns to fillable state.
- Events: `ForceCancelCloseIntent(intentId)`.

---

## PartyAOpenFacet

Source: `contracts/facets/PartyAOpen/PartyAOpenFacet.sol`. Open intent lifecycle on the Party A side. All functions are `whenPartyNotPaused(msg.sender)`.

### `sendOpenIntent(...)`

- Source: `:48`
- Signature: `sendOpenIntent(address[] partyBsWhiteList, uint256 symbolId, uint256 price, uint256 quantity, uint256 strikePrice, uint256 expirationTimestamp, uint256 mm, TradeSide tradeSide, MarginType marginType, ExerciseFee exerciseFee, Fee solverFee, uint256 deadline, address feeToken, address affiliate, bytes userData) returns (uint256 intentId)`.
- Caller: Party A. `whenInstantModeIsNotActive(msg.sender)` (instant-mode users go through `InstantLayer`).
- Precondition: symbol valid; deadline in the future; affiliate active if non-zero; normal cross intents name exactly one Party B; deferred `SELL + CROSS + []` is allowed only for unbound Party A.
- Effect: creates a `PENDING` `OpenIntent`, indexes by Party A, then either locks normal premium/fees/MM or stores `OpenIntentEscrow` for deferred Party B sells.
- Events: `SendOpenIntent(partyA, intentId, partyBsWhiteList, packedAgreements)`.
- Reverts: `InvalidSymbol`, `DeadlineInPast`, `InsufficientBalance`, `InvalidAffiliate`, `DeferredSellNotAllowedForBoundPartyA`, `MultiplePartyBNotAllowed`, etc.

### `expireOpenIntent(uint256[] expiredIntentIds)`

- Source: `:112`
- Caller: anyone.
- Precondition: each intent's deadline has passed and status is one of the expirable statuses.
- Effect: marks each intent `EXPIRED`; refunds normal locks or deferred Party B sell escrow to Party A.
- Events: `ExpireOpenIntent(intentId)` per id.

### `cancelOpenIntent(uint256[] intentIds)`

- Source: `:129`
- Caller: Party A (the intent owner).
- Modifiers: `whenInstantModeIsNotActive(msg.sender)`.
- Effect: depending on current status: `PENDING` → `CANCELED` (instant), `LOCKED` → `CANCEL_PENDING` (awaits Party B accept), past-deadline → `EXPIRED`. Normal locks or deferred escrow are released on terminal non-fill transitions.
- Events: `CancelOpenIntent(intentId, status)` for `CANCELED`/`CANCEL_PENDING`; `ExpireOpenIntent` for the deadline path.

---

## PartyACloseFacet

Source: `contracts/facets/PartyAClose/PartyACloseFacet.sol`.

### `sendCloseIntent(uint256 tradeId, uint256 quantity, uint256 price, uint256 deadline) returns (uint256 intentId)`

- Source: `:38`
- Caller: Party A owner of the trade (`onlyPartyAOfTrade(tradeId)`).
- Modifiers: `whenPartyNotPaused`, `whenInstantModeIsNotActive`.
- Precondition: trade is open with available close quantity; `deadline` in the future; close-orders count under `maxCloseOrdersLength`.
- Effect: creates a `PENDING` `CloseIntent` indexed by trade.
- Events: `SendCloseIntent(tradeId, intentId, price, quantity, deadline)`.
- Reverts: `InvalidTradeOwner`, `TradeNotOpen`, `InsufficientCloseAmount`, `MaxCloseOrdersExceeded`.

### `expireCloseIntent(uint256[] expiredIntentIds)`

- Source: `:53`
- Caller: anyone. Each intent must be expirable.
- Effect: moves intent to `EXPIRED`.
- Events: `ExpireCloseIntent(intentId)` per id.

### `cancelCloseIntent(uint256[] intentIds)`

- Source: `:69`
- Caller: Party A. `whenInstantModeIsNotActive`.
- Effect: `PENDING` → `EXPIRED` (deadline) or `CANCEL_PENDING` (awaits Party B accept).
- Events: `ExpireCloseIntent` or `CancelCloseIntent` per id depending on outcome.

---

## PartyBOpenFacet

Source: `contracts/facets/PartyBOpen/PartyBOpenFacet.sol`. All functions are `whenPartyNotPaused(msg.sender)`.

### `lockOpenIntent(uint256 intentId)`

- Source: `:29`
- Caller: an active Party B (`onlyPartyB(msg.sender)`) which is whitelisted for `intentId` (or the whitelist is empty).
- Precondition: intent is `PENDING`; deadline not passed; Party B supports the symbol type and the symbol's collateral matches Party B config; Party B is solvent for required isolated/cross balance. Deferred Party B sells must have a live, unconsumed escrow.
- Effect: transitions intent to `LOCKED`, records `partyB` and `lockTimestamp`.
- Events: `LockOpenIntent(intentId, partyB)`.

### `unlockOpenIntent(uint256 intentId)`

- Source: `:40`
- Caller: the Party B that locked the intent.
- Effect: returns intent to `PENDING` if still within deadline, else `EXPIRED`.
- Events: `UnlockOpenIntent(intentId, partyB)` or `ExpireOpenIntent(intentId)`.

### `acceptCancelOpenIntent(uint256 intentId)`

- Source: `:55`
- Caller: Party B that locked the intent.
- Precondition: intent is `CANCEL_PENDING`.
- Effect: marks intent `CANCELED`; refunds Party A's normal locks or deferred escrow.
- Events: `AcceptCancelOpenIntent(intentId)`.

### `fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price)`

- Source: `:69`
- Caller: Party B that locked the intent.
- Precondition: intent is `LOCKED`; `price <= intent.price` for buy-side and `price >= intent.price` for sell-side; `quantity <= remaining`; Party B has sufficient balance.
- Effect: creates a new `Trade`, resolves normal locks or consumes deferred escrow, debits Party B premium and Party A fees, indexes by both parties; if partial fill, spawns a residual intent. Deferred Party B sell residuals carry the remaining escrow to the child, or release it immediately if the child is created as `CANCELED`.
- Events: `FillOpenIntent(intentId, tradeId, quantity, price)`. On residual, `SendOpenIntent` (and possibly `CancelOpenIntent`) for the new id.

---

## PartyBCloseFacet

Source: `contracts/facets/PartyBClose/PartyBCloseFacet.sol`.

### `acceptCancelCloseIntent(uint256 intentId)`

- Source: `:26`
- Caller: Party B counterparty of the trade. `whenPartyNotPaused`.
- Precondition: close intent is `CANCEL_PENDING`.
- Effect: marks intent `CANCELED`.
- Events: `AcceptCancelCloseIntent(intentId)`.

### `fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price)`

- Source: `:38`
- Caller: Party B counterparty.
- Precondition: intent is `PENDING` or `CANCEL_PENDING`; `quantity <= intent.quantity`; `price` favorable to Party A relative to `intent.price`.
- Effect: closes `quantity` of the trade at `price`; settles PnL between parties; updates trade open amount and may close trade if fully filled.
- Events: `FillCloseIntent(intentId, quantity, price)`.

---

## TradeFacet

Source: `contracts/facets/Trade/TradeFacet.sol`.

### `transferTrade(address receiver, uint256 tradeId)`

- Source: `:29`
- Caller: current Party A owner of the trade (`onlyPartyAOfTrade(tradeId)`).
- Modifiers: `nonReentrant`, `whenPartyNotPaused(msg.sender)`, `whenNotSuspended(msg.sender)`, `whenNotSuspended(receiver)`.
- Precondition: no pending close intents that block transfer; `receiver` has compatible counterparty configuration.
- Effect: rewrites trade ownership; if the trade has an associated NFT, transfers the NFT to match.
- Events: `TransferTradeByPartyA(sender, receiver, tradeId)`.

### `transferTradeFromNFT(address sender, address receiver, uint256 tradeId)`

- Source: `:45`
- Caller: only the configured `tradeNftAddress` (enforced inside `LibTradeOperations`).
- Modifiers: `whenPartyNotPaused(sender)`, `whenNotSuspended(sender)`, `whenNotSuspended(receiver)`.
- Effect: synchronizes trade ownership after an ERC-721 transfer.
- Events: `TransferTradeByPartyA(sender, receiver, tradeId)`.
- Reverts: `OnlyTradeNFT` (or equivalent), state-consistency reverts.

### `executeTrades(uint256[] tradeIds, SettlementPriceSig settlementPriceSig)`

- Source: `:61`
- Caller: anyone (third-party-callable). `whenNotThirdPartyActionsPaused`.
- Precondition: each trade's symbol matches `settlementPriceSig.symbolId`; signature is valid and within `settlementPriceSigValidTime`; trades are at or past `expirationTimestamp`.
- Effect: per trade, decides exercise vs expire; transfers PnL and exercise fee accordingly; closes trade.
- Events: `ExecuteTrades(operator, tradeIds, exercised, expired, settlementPrice, collateralPrice)`.

### `mintNFTForTrade(uint256 tradeId)`

- Source: `:71`
- Caller: Party A owner of the trade (`onlyPartyAOfTrade(tradeId)`).
- Modifiers: `nonReentrant`. No pause guard.
- Precondition: trade has no NFT yet; `tradeNftAddress` is set.
- Effect: calls the configured `TradeNFT` to mint a token bound to the trade.

---

## ViewFacet

Source: `contracts/facets/View/ViewFacet.sol`. All functions are `external view`, callable by anyone, with no pause or role guards. Citation column is the line number in `ViewFacet.sol`.

### Account / Balance

| Function                                                                           | Line | Returns                                                    |
| ---------------------------------------------------------------------------------- | ---- | ---------------------------------------------------------- |
| `getIsolatedBalance(address user, address collateral)`                             | 57   | Available isolated balance, 18-decimal.                    |
| `getIsolatedLockedBalance(address user, address collateral)`                       | 67   | Isolated locked-for-intent balance.                        |
| `getReserveBalance(address user, address collateral)`                              | 77   | Reserve sub-balance.                                       |
| `getCrossBalance(address user, address collateral, address counterParty)`          | 88   | `CrossEntry` (balance + scheduled release entries).        |
| `getScheduledReleaseEntry(address user, address collateral, address counterParty)` | 99   | Pending release amounts and timestamps.                    |
| `getCounterPartyAddresses(address user, address collateral)`                       | 109  | Counterparties that have a cross balance with `user`.      |
| `getWithdrawal(uint256 withdrawId)`                                                | 118  | `Withdraw` record.                                         |
| `getLastWithdrawalId()`                                                            | 126  | Latest allocated withdrawal id.                            |
| `getExpressWithdrawProviderConfig(address provider, address collateral)`           | 136  | Provider config tuple.                                     |
| `getInvalidWithdrawalsPool()`                                                      | 144  | Pool address that captures invalid withdrawal residuals.   |
| `getReleaseInterval(address user)`                                                 | 153  | Effective release interval.                                |
| `getDefaultReleaseInterval()`                                                      | 161  | Protocol default release interval.                         |
| `getUserReleaseInterval(address user)`                                             | 171  | `(hasConfigured, interval)` raw record.                    |
| `getMaxConnectedCounterParties()`                                                  | 180  | Cap on cross counterparties per user.                      |
| `isManualSync(address user)`                                                       | 189  | Whether the user requires manual sync.                     |
| `getNonce(address party, address counterParty)`                                    | 199  | Bilateral nonce used for off-chain signature invalidation. |

### App / Protocol Parameters

| Function                                                             | Line | Returns                                                     |
| -------------------------------------------------------------------- | ---- | ----------------------------------------------------------- |
| `getVersion()`                                                       | 211  | `uint16` Diamond version, bumped per cut.                   |
| `getBalanceLimitPerUser(address collateral)`                         | 220  | Per-user deposit cap.                                       |
| `getMaxCloseOrdersLength()`                                          | 228  | Limit on concurrent close intents per trade.                |
| `getMaxTradePerPartyA()`                                             | 236  | Cap on active trades per Party A.                           |
| `getPriceOracleAddress()`                                            | 244  | Address of `IPriceOracle` used for fee-token pricing.       |
| `isWhitelistedCollateral(address collateral)`                        | 253  | Whether the collateral is enabled.                          |
| `getTradeNftAddress()`                                               | 261  | Configured `TradeNFT`.                                      |
| `isSignatureUsed(bytes32 sigHash)`                                   | 270  | Replay protection bit.                                      |
| `getSignatureVerifier()`                                             | 278  | Shared `SignatureVerifier` address.                         |
| `getPartyADeallocateCooldown()`                                      | 286  | Seconds.                                                    |
| `getPartyBDeallocateCooldown()`                                      | 294  | Seconds.                                                    |
| `getForceCancelOpenIntentTimeout()`                                  | 302  | Seconds.                                                    |
| `getForceCancelCloseIntentTimeout()`                                 | 310  | Seconds.                                                    |
| `getPartyBExclusiveWindow()`                                         | 318  | Seconds.                                                    |
| `getSettlementPriceSigValidTime()`                                   | 326  | Seconds.                                                    |
| `getUpnlSigValidTime()`                                              | 334  | Seconds.                                                    |
| `getPartyBConfig(address partyB)`                                    | 343  | Full `PartyBConfig` struct.                                 |
| `isSymbolTypesSupportedByPartyB(address partyB, uint256 symbolType)` | 353  | Per-Party-B symbol-type support.                            |
| `isCallFromInstantLayer()`                                           | 361  | Diamond-side instant-layer toggle (`callFromInstantLayer`). |

### Close Intents

| Function                                                        | Line | Returns                           |
| --------------------------------------------------------------- | ---- | --------------------------------- |
| `getCloseIntent(uint256 intentId)`                              | 374  | Full `CloseIntent`.               |
| `getCloseIntentIds(uint256 tradeId)`                            | 383  | All close intent ids for a trade. |
| `getCloseIntents(uint256 tradeId, uint256 start, uint256 size)` | 394  | Paginated close intents.          |
| `getLastCloseIntentId()`                                        | 419  | Last allocated close intent id.   |

### Counter Party Relations

| Function                                            | Line | Returns                                                                 |
| --------------------------------------------------- | ---- | ----------------------------------------------------------------------- |
| `getBoundPartyB(address partyA)`                    | 432  | Currently bound Party B, or `address(0)`.                               |
| `getUnbindingRequestTime(address partyA)`           | 441  | Timestamp of pending unbinding request.                                 |
| `getUnbindingCooldown()`                            | 449  | Cooldown applied to `completeUnbindingFromPartyB`.                      |
| `isInstantActionsModeActive(address user)`          | 458  | Whether instant mode is currently active.                               |
| `getInstantActionsModeDeactivateTime(address user)` | 467  | Earliest timestamp at which `deactivateInstantActionMode` can complete. |
| `getDeactiveInstantActionModeCooldown()`            | 475  | Configured cooldown.                                                    |

### Fees

| Function                                               | Line | Returns                            |
| ------------------------------------------------------ | ---- | ---------------------------------- |
| `getDefaultFeeCollector()`                             | 487  | Default fee collector address.     |
| `isAffiliateActive(address affiliate)`                 | 496  | Affiliate activation flag.         |
| `getAffiliateFeeCollector(address affiliate)`          | 505  | Per-affiliate fee collector.       |
| `getAffiliateFee(address affiliate, uint256 symbolId)` | 515  | `Fee` (open + close basis points). |

### Liquidation

| Function                                                                         | Line | Returns                                      |
| -------------------------------------------------------------------------------- | ---- | -------------------------------------------- |
| `getInProgressLiquidationId(address partyA, address partyB, address collateral)` | 530  | Active liquidation id for the tuple, or `0`. |
| `getLiquidationDetail(uint256 liquidationId)`                                    | 539  | Snapshot details of a liquidation.           |
| `getLastLiquidationId()`                                                         | 547  | Last allocated liquidation id.               |

### Open Intents

| Function                                                          | Line | Returns                                                                      |
| ----------------------------------------------------------------- | ---- | ---------------------------------------------------------------------------- |
| `getOpenIntent(uint256 intentId)`                                 | 560  | Full `OpenIntent`.                                                           |
| `getOpenIntentEscrow(uint256 intentId)`                           | 564  | `OpenIntentEscrow` for deferred Party B sells; zeroed after release/consume. |
| `isDeferredPartyBSellIntent(uint256 intentId)`                    | 568  | Whether the stored intent is `SELL + CROSS + empty whitelist`.               |
| `getActiveOpenIntentIds(address user)`                            | 578  | Ids the user appears in.                                                     |
| `getActiveOpenIntentsCount(address user)`                         | 587  | Length of the active set.                                                    |
| `getActiveOpenIntents(address user, uint256 start, uint256 size)` | 598  | Paginated active intents.                                                    |
| `getPartyAOpenIntentIndex(uint256 intentId)`                      | 624  | Index inside Party A's active set.                                           |
| `getPartyBOpenIntentIndex(uint256 intentId)`                      | 633  | Index inside Party B's active set.                                           |
| `getLastOpenIntentId()`                                           | 641  | Last allocated id.                                                           |

### Pause / Suspension State

| Function                                    | Line | Returns                                                          |
| ------------------------------------------- | ---- | ---------------------------------------------------------------- |
| `isGlobalPaused()`                          | 644  | `bool`.                                                          |
| `isDepositingPaused()`                      | 652  | `bool`.                                                          |
| `isWithdrawingPaused()`                     | 660  | `bool`.                                                          |
| `isPartyBActionsPaused()`                   | 668  | `bool`.                                                          |
| `isPartyAActionsPaused()`                   | 676  | `bool`.                                                          |
| `isLiquidatingPaused()`                     | 684  | `bool`.                                                          |
| `isThirdPartyActionsPaused()`               | 692  | `bool`.                                                          |
| `isInternalTransferPaused()`                | 700  | `bool`.                                                          |
| `isExternalTransferPaused()`                | 708  | `bool`.                                                          |
| `isExpressWithdrawPaused()`                 | 716  | `bool`.                                                          |
| `isInstantLayerPaused()`                    | 724  | `bool`.                                                          |
| `getAllPauseStates()`                       | 743  | Twelve-bool tuple covering every pause flag plus emergency mode. |
| `isPartyBsEmergencyMode()`                  | 782  | Global Party B emergency.                                        |
| `isPartyBInEmergencyMode(address partyB)`   | 791  | Per-Party-B emergency.                                           |
| `isAddressSuspended(address user)`          | 800  | Address-level suspension.                                        |
| `isWithdrawalSuspended(uint256 withdrawId)` | 809  | Per-withdrawal suspension.                                       |

### Access Control

| Function                                     | Line | Returns            |
| -------------------------------------------- | ---- | ------------------ |
| `hasRole(address user, bytes32 role)`        | 823  | `bool`.            |
| `getRoleMembers(bytes32 role)`               | 832  | Members of a role. |
| `getRoleMemberCount(bytes32 role)`           | 841  | Member count.      |
| `getRoleMember(bytes32 role, uint256 index)` | 851  | Indexed access.    |

### Symbols and Oracles

| Function                                  | Line | Returns                   |
| ----------------------------------------- | ---- | ------------------------- |
| `getOracle(uint256 oracleId)`             | 864  | `Oracle` record.          |
| `getLastOracleId()`                       | 872  | Last allocated oracle id. |
| `getSymbol(uint256 symbolId)`             | 881  | `Symbol` record.          |
| `getSymbols(uint256 start, uint256 size)` | 891  | Paginated symbols.        |
| `getLastSymbolId()`                       | 915  | Last allocated symbol id. |

### Trades

| Function                                                             | Line | Returns                                              |
| -------------------------------------------------------------------- | ---- | ---------------------------------------------------- |
| `getTrade(uint256 tradeId)`                                          | 928  | Full `Trade`.                                        |
| `getActiveTradeIdsOfPartyA(address user)`                            | 937  | Active trade ids for a Party A.                      |
| `getActiveTradesOfPartyA(address user, uint256 start, uint256 size)` | 948  | Paginated active trades.                             |
| `getActiveTradeIdsForPartyB(address partyB, address collateral)`     | 975  | Active trade ids on the Party B side per collateral. |
| `getPartyATradeIndex(uint256 tradeId)`                               | 984  | Index inside Party A's active set.                   |
| `getPartyBTradeIndex(uint256 tradeId)`                               | 993  | Index inside Party B's active set.                   |
| `getLastTradeId()`                                                   | 1001 | Last allocated trade id.                             |

### Pricing Helpers

| Function                                                                        | Line | Returns                                                            |
| ------------------------------------------------------------------------------- | ---- | ------------------------------------------------------------------ |
| `getOpenIntentPlatformFee(uint256 intentId)`                                    | 1014 | Platform fee due for the intent.                                   |
| `getOpenIntentAffiliateFee(uint256 intentId)`                                   | 1024 | Affiliate fee due for the intent.                                  |
| `getOpenIntentPremium(uint256 intentId)`                                        | 1034 | Premium that would be locked at `intent.price`.                    |
| `getOpenIntentPremiumProportional(uint256 intentId, uint256 price)`             | 1045 | Premium re-priced at `price`.                                      |
| `getCloseIntentPlatformFee(uint256 intentId, uint256 quantity, uint256 price)`  | 1061 | Platform fee on a partial close.                                   |
| `getCloseIntentAffiliateFee(uint256 intentId, uint256 quantity, uint256 price)` | 1073 | Affiliate fee on a partial close.                                  |
| `getTradeOpenAmount(uint256 tradeId)`                                           | 1087 | Currently open quantity.                                           |
| `getTradeAvailableAmountToClose(uint256 tradeId)`                               | 1096 | Quantity not already covered by pending close intents.             |
| `getTradePnl(uint256 tradeId, uint256 currentPrice, uint256 filledAmount)`      | 1107 | Notional PnL at `currentPrice` for `filledAmount`.                 |
| `getTradePremium(uint256 tradeId)`                                              | 1116 | Total premium locked on the trade.                                 |
| `getTradeExerciseFee(uint256 tradeId, uint256 settlementPrice, uint256 pnl)`    | 1127 | Exercise fee charged on the supplied `pnl`/`settlementPrice` pair. |
