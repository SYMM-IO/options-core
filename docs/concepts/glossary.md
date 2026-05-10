---
title: Glossary
aliases:
    - Terms
    - Vocabulary
tags:
    - symmio
    - options-core
    - concept
---

# Glossary

A definitive A–Z dictionary of every domain term used in Options Core. Each entry gives a one-sentence definition, an optional clarification with a link to the deeper doc, and the primary code reference where applicable. Sections are grouped by concern; entries inside a section are alphabetical.

## Contents

-   [Actors](#actors)
-   [Trading And Lifecycle](#trading-and-lifecycle)
-   [Money And Margin](#money-and-margin)
-   [Pricing And PnL](#pricing-and-pnl)
-   [Helpers And Off-chain](#helpers-and-off-chain)
-   [Risk And Liquidation](#risk-and-liquidation)
-   [System Concepts](#system-concepts)

## Actors

-   **Affiliate** — Address that earns the affiliate fee stream on intents tagged with it; must be active or zero (`contracts/storages/FeeManagementStorage.sol:13`, `contracts/libraries/core/LibPartyAOpen.sol:68`). Routing rules are in [[open-intents]].
-   **Bound Party A** — A Party A that has called `bindToPartyB(partyB)`; while bound, every open-intent whitelist must equal `[boundPartyB]` and deferred Party B sells are rejected (`contracts/libraries/core/LibPartyAOpen.sol:70-75`). See [[instant-actions]].
-   **Clearing house** — Address holding `CLEARING_HOUSE_ROLE` that runs the liquidation and confiscation/distribution pipeline (`contracts/facets/ClearingHouse/ClearingHouseFacet.sol`). Detailed in [[liquidation-and-force-actions]].
-   **Default fee collector** — Address that receives platform fees and any affiliate fee with no configured collector (`contracts/storages/FeeManagementStorage.sol:11`, `contracts/facets/Control/ControlFacet.sol:333`).
-   **Disputer** — Holder of `DISPUTER_ROLE` that may restore a suspended withdrawal at a possibly reduced amount (`contracts/utils/Accessibility.sol`, `contracts/facets/Account/AccountFacet.sol:211`).
-   **Party A** — The trader account that owns open intents, close intents, and trades (`contracts/libraries/models/LibParty.sol:32-34`); may be an EOA or a `SymmioPartyA` instance.
-   **Party B** — A market maker / solver address activated through `ControlFacet.setPartyBConfig`; identified by `partyBConfigs[addr].isActive == true` (`contracts/storages/AppStorage.sol:7-11`, `contracts/libraries/models/LibParty.sol:32`).
-   **Solver** — Synonym for Party B in fee/event terminology; the `solverFee` stream is paid to `intent.partyB` (`contracts/types/BaseTypes.sol:34-40`, `contracts/libraries/core/LibPartyBOpen.sol:326-333`).

## Trading And Lifecycle

-   **CALL** — Option type whose intrinsic value is `max(settlementPrice − strikePrice, 0)` (`contracts/types/SymbolTypes.sol:9`, `contracts/libraries/models/LibTrade.sol:36-44`).
-   **Close intent** — Party A's signed RFQ to close part of a trade at a threshold price (`contracts/types/IntentTypes.sol:44-55`); lifecycle in [[close-and-settlement]].
-   **Deferred Party B sell** — An unbound `SELL + CROSS` open intent with an empty Party B whitelist; Party A's seller MM and estimated open fees are held in `OpenIntentEscrow` until a Party B locks and fills. Detailed in [[open-intents]].
-   **Force action timeout** — Either `forceCancelOpenIntentTimeout` or `forceCancelCloseIntentTimeout`; the cooldown after which anyone may force-cancel a `CANCEL_PENDING` intent (`contracts/storages/AppStorage.sol:34-35`, `contracts/libraries/core/LibForceActions.sol:23-58`).
-   **Force cancel** — Permissionless transition of a stuck `CANCEL_PENDING` intent to `CANCELED` once the matching timeout elapses (`contracts/facets/ForceActions/ForceActionsFacet.sol:25,36`).
-   **Open intent** — Party A's signed offer to open a position; carries trade agreements, fees, and a Party B whitelist (`contracts/types/IntentTypes.sol:26-42`). Detailed in [[open-intents]].
-   **OptionType** — Enum `{ PUT, CALL }` configured per symbol (`contracts/types/SymbolTypes.sol:9`).
-   **PUT** — Option type whose intrinsic value is `max(strikePrice − settlementPrice, 0)` (`contracts/libraries/models/LibTrade.sol:36-44`).
-   **Symbol** — Configuration record `{ symbolId, oracleId, symbolType, platformFee, collateral, optionType, isValid, name }` (`contracts/types/SymbolTypes.sol:20`).
-   **Symbol id** — Monotonic identifier into `SymbolStorage.symbols`; used in every trade and intent (`contracts/storages/SymbolStorage.sol`, `contracts/types/BaseTypes.sol:42`).
-   **Symbol type** — Free-form integer category that Party B opts into via `partyBSupportedSymbolTypes[partyB][symbolType]` (`contracts/storages/AppStorage.sol:50`, `contracts/libraries/core/LibPartyBOpen.sol:92`).
-   **Trade** — On-chain position created when Party B fills an open intent; tracks open/close quantity, premium, MM, and settlement state (`contracts/types/TradeTypes.sol:18-35`).
-   **Trade agreements** — Embedded `TradeAgreements` struct snapshotting symbol, quantity, strike, expiry, mm, side, and margin type for an intent or trade (`contracts/types/BaseTypes.sol:42-51`).
-   **TradeNFT** — ERC-721 representation of an isolated trade; transfers route back through `TradeFacet.transferTradeFromNFT` (`contracts/helpers/TradeNFT.sol`, `contracts/facets/Trade/TradeFacet.sol:45`).

## Money And Margin

-   **Cross balance** — Bilateral signed balance between one Party A and one Party B for a given collateral, stored in `crossBalance[counterParty]` (`contracts/types/BalanceTypes.sol:31-39`). See [[margin-modes]].
-   **Cross margin** — Margin mode in which collateral is pooled per `(partyA, partyB, collateral)` rather than per trade (`contracts/types/BaseTypes.sol:12-16`).
-   **Isolated balance** — `ScheduledReleaseBalance.isolatedBalance`, the user's free isolated funds before locks (`contracts/types/BalanceTypes.sol:46`).
-   **Isolated margin** — Margin mode in which each trade's collateral is reserved via `isolatedLockedBalance` and is not pooled across counterparties.
-   **Locked balance** — Either `isolatedLockedBalance` or `crossBalance[cp].locked`; funds reserved by an active intent or trade (`contracts/libraries/models/LibScheduledReleaseBalance.sol:427-462`).
-   **Maintenance margin (MM)** — Per-trade SELL-side collateral the seller posts; tracked at the trade level via `tradeAgreements.mm` (`contracts/types/BaseTypes.sol:42-51`).
-   **manualSync user** — A user (typically Party B) for whom `accountLayout.manualSync[user]` is true; the protocol skips auto-sync and counterparty tracking, requiring explicit `syncBalances` calls (`contracts/storages/AccountStorage.sol:23`, `contracts/facets/Control/ControlFacet.sol:397`).
-   **Open intent escrow** — `OpenIntentEscrow`, a temporary isolated lock record for deferred Party B sells, storing Party A, collateral, fee token, seller MM, estimated open-fee lock, and existence/consumption guards (`contracts/types/IntentTypes.sol:44-52`).
-   **Reserve balance** — Third pool sitting next to isolated and cross; pre-funded by the user and pull-able by the clearing house (`contracts/types/BalanceTypes.sol:46`, `contracts/libraries/core/LibClearingHouse.sol:249-254`).
-   **Scheduled release** — Two-bus pipeline (`scheduled` → `transitioning` → `isolatedBalance`) gated by `releaseInterval` (`contracts/types/BalanceTypes.sol:24`, `contracts/libraries/models/LibScheduledReleaseBalance.sol:302`). Background in [[account-balances]].
-   **Sync / syncAll** — `_sync(counterParty)` advances one schedule; `syncAll()` walks every tracked counterparty (`contracts/libraries/models/LibScheduledReleaseBalance.sol:302`). The public entry point is `AccountFacet.syncBalances` (`contracts/facets/Account/AccountFacet.sol:252`).
-   **Total MM (totalMM)** — Aggregated maintenance margin a Party A has locked against a single Party B; lives in `crossBalance[cp].totalMM` (`contracts/types/BalanceTypes.sol:31-39`).
-   **Tuple (partyA, partyB, collateral)** — The triple keying every cross-margin slot, liquidation, and active-trade counter (`contracts/storages/LiquidationStorage.sol:13`, `contracts/storages/TradeStorage.sol`).

## Pricing And PnL

-   **Affiliate fee** — `feeStructure.affiliateFee.openFee` / `closeFee` charged to Party A and credited to the affiliate fee collector (`contracts/types/BaseTypes.sol:34-40`, `contracts/libraries/core/LibPartyBOpen.sol:316-324`).
-   **Close fee** — Party-A-paid fee on close-intent fills and at settlement; covers platform, affiliate, and solver streams (`contracts/libraries/core/LibPartyBClose.sol:124-153`, `contracts/libraries/core/LibTradeOperations.sol:191-225`).
-   **Collateral price** — `collateralPrice` field in Muon-signed payloads; converts symbol-quote PnL to collateral units (`contracts/types/TradeTypes.sol:42-50`, `contracts/libraries/core/LibTradeOperations.sol:168-169`).
-   **Collateral whitelist** — `AppStorage.whiteListedCollateral`; a token must be present here to back a deposit or symbol (`contracts/storages/AppStorage.sol:21`, `contracts/facets/Control/ControlFacet.sol:99`).
-   **Exercise fee** — Per-trade fee charged at settlement; the lesser of `cap * pnl / 1e18` and `rate * settlementPrice * openAmount / 1e36` (`contracts/types/BaseTypes.sol:17-20`, `contracts/libraries/models/LibTrade.sol:58-62`).
-   **In-the-money (ITM)** — Trade has positive intrinsic value at `settlementPrice`; settlement marks it `EXERCISED` (`contracts/libraries/core/LibTradeOperations.sol:118-134`).
-   **Limit price** — `OpenIntent.price` for opens and `CloseIntent.price` for closes; acts as a cap for BUY and a floor for SELL (`contracts/libraries/core/LibPartyBOpen.sol:213-216`, `contracts/libraries/core/LibPartyBClose.sol:79-90`).
-   **Open fee** — Party-A-paid fee on `fillOpenIntent`; split into platform / affiliate / solver components (`contracts/libraries/core/LibPartyBOpen.sol:306-334`).
-   **Out-of-the-money (OTM)** — Trade has zero intrinsic value at expiry; settlement marks it `EXPIRED` (`contracts/libraries/core/LibTradeOperations.sol:118-134`).
-   **Premium** — Per-unit price the buyer pays the seller at fill (`Trade.openedPrice`); proportional pieces move on close and at settlement (`contracts/types/TradeTypes.sol:18-35`, `contracts/libraries/models/LibTrade.sol:46-48`).
-   **Realized PnL** — Settled gain/loss moved between balances at `executeTrades` time, tagged with `REALIZED_PNL` (`contracts/types/BalanceTypes.sol:66`, `contracts/libraries/core/LibTradeOperations.sol:177-188`).
-   **Settled price** — `Trade.settledPrice`; the on-chain record of the price used at exercise/expiry (`contracts/types/TradeTypes.sol:18-35`, `contracts/libraries/core/LibTradeOperations.sol:122,131`).
-   **Settlement price** — `SettlementPriceSig.settlementPrice`; the off-chain oracle value carried into `executeTrades` (`contracts/types/TradeTypes.sol:42-50`).
-   **Solver fee** — Per-trade fee paid to Party B on opens and closes; routes through `scheduledAdd(...CROSS,...)` for cross trades and `instantIsolatedAdd` for isolated trades (`contracts/libraries/core/LibPartyBOpen.sol:326-333`, `contracts/libraries/core/LibPartyBClose.sol:144-151`).
-   **Strike price** — `tradeAgreements.strikePrice`; the option's reference price (`contracts/types/BaseTypes.sol:42-51`).
-   **uPnL** — Unrealized PnL signed off-chain via `UpnlSig`; consumed by `deallocate` and the liquidation flow (`contracts/types/WithdrawTypes.sol:22`, `contracts/libraries/services/LibMuon.sol:59`).

## Helpers And Off-chain

-   **EIP-712** — Typed-data signature standard used by `InstantLayer` to authorize signed operations (`contracts/helpers/InstantLayer.sol`).
-   **ERC-1271** — Smart-contract signature interface implemented by `MultiAccount` and `SymmioPartyB` so on-chain accounts can sign for InstantLayer (`contracts/helpers/MultiAccount.sol`, `contracts/helpers/SymmioPartyB.sol`).
-   **ERC-2535** — The Diamond standard governing facet routing and storage isolation (`contracts/Diamond.sol`, `contracts/libraries/LibDiamond.sol`).
-   **Gateway signature** — ECDSA signature from Muon's `validGateway` accompanying the TSS aggregate (`contracts/types/MuonTypes.sol:12-16`, `contracts/libraries/services/LibMuon.sol`).
-   **Instant action mode** — Party A flag enabling `InstantLayer` to drive its account; gates user-callable Party A entry points via `whenInstantModeIsNotActive` (`contracts/storages/CounterPartyRelationsStorage.sol`, `contracts/utils/Accessibility.sol`). See [[instant-actions]].
-   **InstantLayer** — Off-chain-driven contract that verifies EIP-712 signed operations and forwards them through `MultiAccount` (Party A) or `SymmioPartyB` (Party B) (`contracts/helpers/InstantLayer.sol`).
-   **MultiAccount** — Factory and forwarder for `SymmioPartyA` accounts; mediates owner and InstantLayer calls (`contracts/helpers/MultiAccount.sol`).
-   **Muon** — The off-chain TSS oracle network whose signatures back uPnL and settlement payloads (`contracts/libraries/services/LibMuon.sol`, `contracts/helpers/MuonOracle.sol`).
-   **Schnorr** — Signature scheme used by Muon's threshold signers; encoded as `SchnorrSign` (`contracts/types/MuonTypes.sol:18`).
-   **SymmioPartyA** — Per-Party-A account contract managed by `MultiAccount`; can hold and forward trade NFTs (`contracts/helpers/SymmioPartyA.sol`).
-   **SymmioPartyB** — Upgradeable Party B executor with selector restrictions, multicall, and ERC-1271 (`contracts/helpers/SymmioPartyB.sol`).
-   **TSS** — Threshold Signature Scheme used by Muon to produce a single Schnorr signature from a quorum of signers.

## Risk And Liquidation

-   **Confiscation** — Clearing house removing collateral from a liquidated party (or a pending withdrawal) into the liquidation pool (`contracts/libraries/core/LibClearingHouse.sol:256-273`).
-   **Distribution** — Clearing house releasing pooled liquidation collateral back to a list of Party As (`contracts/libraries/core/LibClearingHouse.sol:280-301`).
-   **Flagged** — `LiquidationStatus.FLAGGED`; the clearing house has marked a tuple but has not yet executed (`contracts/types/LiquidationTypes.sol:7`).
-   **In progress** — `LiquidationStatus.IN_PROGRESS`; the executable phase during which `closeTrades`, `confiscate`, and `distributeCollateral` run (`contracts/types/LiquidationTypes.sol:7`).
-   **Liquidation** — End-to-end pipeline gated by `CLEARING_HOUSE_ROLE` that flags, snapshots uPnL, closes trades, confiscates, and distributes collateral (`contracts/libraries/core/LibClearingHouse.sol`). Detailed in [[liquidation-and-force-actions]].
-   **Loss coverage** — Per-Party-B multiplier `partyBConfigs[partyB].lossCoverage` used in deallocation/liquidation math (`contracts/storages/AppStorage.sol:7-11`, `contracts/libraries/core/LibAllocationOperations.sol`).
-   **requireSolvent** — `LibParty.requireSolvent(self, counterParty, collateral, marginType)`: passes iff no active liquidation id exists for the relevant tuple — it does NOT compute uPnL (`contracts/libraries/models/LibParty.sol:17-30`).

## System Concepts

-   **Bilateral nonce** — `AccountStorage.nonces[party][counterParty]`; incremented after balance-affecting cross-margin actions to invalidate older Muon signatures (`contracts/storages/AccountStorage.sol`, `contracts/libraries/core/LibPartyBOpen.sol:364-367`, `contracts/libraries/core/LibPartyBClose.sol:170-171`, `contracts/libraries/core/LibTradeOperations.sol:232-235`).
-   **Diamond** — The EIP-2535 proxy in `contracts/Diamond.sol` that delegates each selector to a registered facet via `LibDiamond`.
-   **Disputer** — See [Actors](#actors).
-   **Express withdraw** — Provider-fronted withdrawal path that pays the user immediately and reimburses the provider on `completeWithdraw` (`contracts/libraries/core/LibBalanceOperations.sol:104`, `contracts/interfaces/IExpressWithdrawProvider.sol`).
-   **External transfer target** — Whitelisted contract that can receive an `externalTransfer`; receives an `onTransfer` callback (`contracts/storages/AccountStorage.sol`, `contracts/interfaces/IExternalTransferTarget.sol`).
-   **Facet** — Contract whose selectors are mounted onto the Diamond via `diamondCut` (`contracts/facets/...`). API in [[facets]].
-   **Pause flags** — Per-domain booleans in `StateControlStorage` that gate the `whenXxxNotPaused` modifiers (`contracts/storages/StateControlStorage.sol`, `contracts/utils/Pausable.sol`).
-   **Party B emergency mode** — Per-Party-B and global flags that halt Party B intent locks and fills (`contracts/storages/StateControlStorage.sol`, `contracts/libraries/core/LibPartyBOpen.sol:51-52`).
-   **Replay protection** — Combination of `AppStorage.isSigUsed[hash]` for Muon payloads and `InstantLayer.usedOperationHashes`/`nonces` for signed operations (`contracts/storages/AppStorage.sol`, `contracts/helpers/InstantLayer.sol`).
-   **Storage slot** — A `bytes32` constant such as `keccak256("diamond.standard.storage.<name>")` from which a storage library's `Layout` is read (`contracts/storages/AppStorage.sol:14`, see [[types-and-storage]]).
-   **Suspended (address/withdrawal)** — `StateControlStorage.suspendedAddresses[user]` blocks user-side actions; `suspendedWithdrawal[id]` blocks `complete`/`cancel` until restored (`contracts/storages/StateControlStorage.sol`, `contracts/utils/Accessibility.sol`).
-   **Virtual deposit** — `virtualDepositFor` credit by `VIRTUAL_DEPOSITOR_ROLE` without ERC-20 movement (`contracts/facets/Account/AccountFacet.sol:51`, `contracts/libraries/core/LibBalanceOperations.sol:40`).
-   **Virtual withdraw** — Withdrawal whose `isVirtual = true` (set by the express provider config); `completeWithdraw` skips the ERC-20 transfer (`contracts/types/WithdrawTypes.sol:9`, `contracts/libraries/core/LibBalanceOperations.sol:184`).
-   **Whitelist** — Generic term for `OpenIntent.partyBsWhiteList`, `whiteListedCollateral`, `externalTransferTargets`, and `expressWithdrawProviderConfigs`; semantics differ per surface. For open intents, empty whitelist means any active Party B for isolated intents and deferred Party B sells, but not for normal cross intents.
