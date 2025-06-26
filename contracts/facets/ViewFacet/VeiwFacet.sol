// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/models/LibParty.sol";

import { TradeStorage } from "../../storages/TradeStorage.sol";
import { BridgeStorage } from "../../storages/BridgeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";
import { StateControlStorage } from "../../storages/StateControlStorage.sol";
import { AccessControlStorage } from "../../storages/AccessControlStorage.sol";
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";
import { SymbolStorage, Symbol, Oracle } from "../../storages/SymbolStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { Trade } from "../../types/TradeTypes.sol";
import { Withdraw } from "../../types/WithdrawTypes.sol";
import { BridgeTransaction } from "../../types/BridgeTypes.sol";
import { OpenIntent, CloseIntent } from "../../types/IntentTypes.sol";
import { LiquidationDetail } from "../../types/LiquidationTypes.sol";
import { ScheduledReleaseEntry, CrossEntry } from "../../types/BalanceTypes.sol";

import { IViewFacet } from "./IViewFacet.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ViewFacet
 * @notice Provides read-only access to all protocol state
 * @dev Organized by storage contract for clarity and completeness
 */
contract ViewFacet is IViewFacet {
	using EnumerableSet for EnumerableSet.AddressSet;
	using LibParty for address;

	// ════════════════════════════════════════════════════════════════════════════
	//                           ACCOUNT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets the isolated balance for a user and collateral
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @return The isolated balance amount
	 */
	function getIsolatedBalance(address user, address collateral) external view returns (uint256) {
		return user.balanceOf(collateral).isolatedBalance;
	}

	/**
	 * @notice Gets the isolated locked balance for a user and collateral
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @return The isolated locked balance amount
	 */
	function getIsolatedLockedBalance(address user, address collateral) external view returns (uint256) {
		return user.balanceOf(collateral).isolatedLockedBalance;
	}

	/**
	 * @notice Gets the reserve balance for a user and collateral
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @return The reserve balance amount
	 */
	function getReserveBalance(address user, address collateral) external view returns (uint256) {
		return user.balanceOf(collateral).reserveBalance;
	}

	/**
	 * @notice Gets the cross balance entry for a user, collateral and counterparty
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @param counterParty The counterparty address
	 * @return The cross balance entry
	 */
	function getCrossBalance(address user, address collateral, address counterParty) external view returns (CrossEntry memory) {
		return user.balanceOf(collateral).crossBalance[counterParty];
	}

	/**
	 * @notice Gets the scheduled release entry for a user, collateral and counterparty
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @param counterParty The counterparty address
	 * @return The scheduled release entry
	 */
	function getScheduledReleaseEntry(address user, address collateral, address counterParty) external view returns (ScheduledReleaseEntry memory) {
		return user.balanceOf(collateral).counterPartySchedules[counterParty];
	}

	/**
	 * @notice Gets the list of counterparty addresses for a user's balance
	 * @param user The user address
	 * @param collateral The collateral token address
	 * @return Array of counterparty addresses
	 */
	function getCounterPartyAddresses(address user, address collateral) external view returns (address[] memory) {
		return user.balanceOf(collateral).counterPartyAddresses;
	}

	/**
	 * @notice Gets withdrawal details by ID
	 * @param withdrawId The withdrawal ID
	 * @return The withdrawal details
	 */
	function getWithdrawal(uint256 withdrawId) external view returns (Withdraw memory) {
		return AccountStorage.layout().withdrawals[withdrawId];
	}

	/**
	 * @notice Gets the last withdrawal ID
	 * @return The last withdrawal ID used
	 */
	function getLastWithdrawalId() external view returns (uint256) {
		return AccountStorage.layout().lastWithdrawId;
	}

	/**
	 * @notice Gets the release interval for a user
	 * @param user The user address
	 * @return The release interval in seconds
	 */
	function getReleaseInterval(address user) external view returns (uint256) {
		return user.getReleaseInterval();
	}

	/**
	 * @notice Gets the default release interval
	 * @return The default release interval in seconds
	 */
	function getDefaultReleaseInterval() external view returns (uint256) {
		return AccountStorage.layout().defaultReleaseInterval;
	}

	/**
	 * @notice Checks if a user has a configured release interval
	 * @param user The user address
	 * @return hasConfigured Whether the user has a configured interval
	 * @return interval The configured interval (if any)
	 */
	function getUserReleaseInterval(address user) external view returns (bool hasConfigured, uint256 interval) {
		AccountStorage.Layout storage layout = AccountStorage.layout();
		return (layout.hasConfiguredInterval[user], layout.releaseIntervals[user]);
	}

	/**
	 * @notice Gets the maximum allowed connected counterparties
	 * @return The maximum number of connected counterparties
	 */
	function getMaxConnectedCounterParties() external view returns (uint256) {
		return AccountStorage.layout().maxConnectedCounterParties;
	}

	/**
	 * @notice Checks if manual sync is enabled for a user
	 * @param user The user address
	 * @return Whether manual sync is enabled
	 */
	function isManualSync(address user) external view returns (bool) {
		return AccountStorage.layout().manualSync[user];
	}

	/**
	 * @notice Gets the nonce between two parties
	 * @param party The first party
	 * @param counterParty The counterparty
	 * @return The current nonce
	 */
	function getNonce(address party, address counterParty) external view returns (uint256) {
		return AccountStorage.layout().nonces[party][counterParty];
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                           APP STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets the current protocol version
	 * @return The protocol version number
	 */
	function getVersion() external view returns (uint16) {
		return AppStorage.layout().version;
	}

	/**
	 * @notice Gets the balance limit per user for a collateral
	 * @param collateral The collateral token address
	 * @return The balance limit
	 */
	function getBalanceLimitPerUser(address collateral) external view returns (uint256) {
		return AppStorage.layout().balanceLimitPerUser[collateral];
	}

	/**
	 * @notice Gets the maximum close orders length
	 * @return The maximum number of close orders
	 */
	function getMaxCloseOrdersLength() external view returns (uint256) {
		return AppStorage.layout().maxCloseOrdersLength;
	}

	/**
	 * @notice Gets the maximum trades per PartyA
	 * @return The maximum number of trades
	 */
	function getMaxTradePerPartyA() external view returns (uint256) {
		return AppStorage.layout().maxTradePerPartyA;
	}

	/**
	 * @notice Gets the price oracle address
	 * @return The price oracle contract address
	 */
	function getPriceOracleAddress() external view returns (address) {
		return AppStorage.layout().priceOracleAddress;
	}

	/**
	 * @notice Checks if a collateral is whitelisted
	 * @param collateral The collateral token address
	 * @return Whether the collateral is whitelisted
	 */
	function isWhitelistedCollateral(address collateral) external view returns (bool) {
		return AppStorage.layout().whiteListedCollateral[collateral];
	}

	/**
	 * @notice Gets the trade NFT contract address
	 * @return The NFT contract address
	 */
	function getTradeNftAddress() external view returns (address) {
		return AppStorage.layout().tradeNftAddress;
	}

	/**
	 * @notice Checks if a signature has been used
	 * @param sigHash The signature hash
	 * @return Whether the signature has been used
	 */
	function isSignatureUsed(bytes32 sigHash) external view returns (bool) {
		return AppStorage.layout().isSigUsed[sigHash];
	}

	/**
	 * @notice Gets the signature verifier address
	 * @return The signature verifier contract address
	 */
	function getSignatureVerifier() external view returns (address) {
		return AppStorage.layout().signatureVerifier;
	}

	/**
	 * @notice Gets the PartyA deallocate cooldown
	 * @return The cooldown period in seconds
	 */
	function getPartyADeallocateCooldown() external view returns (uint256) {
		return AppStorage.layout().partyADeallocateCooldown;
	}

	/**
	 * @notice Gets the PartyB deallocate cooldown
	 * @return The cooldown period in seconds
	 */
	function getPartyBDeallocateCooldown() external view returns (uint256) {
		return AppStorage.layout().partyBDeallocateCooldown;
	}

	/**
	 * @notice Gets the force cancel open intent timeout
	 * @return The timeout period in seconds
	 */
	function getForceCancelOpenIntentTimeout() external view returns (uint256) {
		return AppStorage.layout().forceCancelOpenIntentTimeout;
	}

	/**
	 * @notice Gets the force cancel close intent timeout
	 * @return The timeout period in seconds
	 */
	function getForceCancelCloseIntentTimeout() external view returns (uint256) {
		return AppStorage.layout().forceCancelCloseIntentTimeout;
	}

	/**
	 * @notice Gets the PartyB exclusive window period
	 * @return The exclusive window period in seconds
	 */
	function getPartyBExclusiveWindow() external view returns (uint256) {
		return AppStorage.layout().partyBExclusiveWindow;
	}

	/**
	 * @notice Gets the settlement price signature valid time
	 * @return The valid time period in seconds
	 */
	function getSettlementPriceSigValidTime() external view returns (uint256) {
		return AppStorage.layout().settlementPriceSigValidTime;
	}

	/**
	 * @notice Gets PartyB configuration
	 * @param partyB The PartyB address
	 * @return The PartyB configuration
	 */
	function getPartyBConfig(address partyB) external view returns (PartyBConfig memory) {
		return AppStorage.layout().partyBConfigs[partyB];
	}

	/**
	 * @notice Checks if being called from instant layer
	 * @return Whether the call is from instant layer
	 */
	function isCallFromInstantLayer() external view returns (bool) {
		return AppStorage.layout().callFromInstantLayer;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                           BRIDGE STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Checks if a bridge is whitelisted
	 * @param bridge The bridge address
	 * @return Whether the bridge is whitelisted
	 */
	function isBridgeWhitelisted(address bridge) external view returns (bool) {
		return BridgeStorage.layout().bridges[bridge];
	}

	/**
	 * @notice Gets bridge transaction details
	 * @param transactionId The transaction ID
	 * @return The bridge transaction details
	 */
	function getBridgeTransaction(uint256 transactionId) external view returns (BridgeTransaction memory) {
		return BridgeStorage.layout().bridgeTransactions[transactionId];
	}

	/**
	 * @notice Gets the last bridge transaction ID
	 * @return The last transaction ID
	 */
	function getLastBridgeTransactionId() external view returns (uint256) {
		return BridgeStorage.layout().lastBridgeTransactionId;
	}

	/**
	 * @notice Gets the invalid bridged amounts pool address
	 * @return The pool address
	 */
	function getInvalidBridgedAmountsPool() external view returns (address) {
		return BridgeStorage.layout().invalidBridgedAmountsPool;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                        CLOSE INTENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets close intent details
	 * @param intentId The intent ID
	 * @return The close intent details
	 */
	function getCloseIntent(uint256 intentId) external view returns (CloseIntent memory) {
		return CloseIntentStorage.layout().closeIntents[intentId];
	}

	/**
	 * @notice Gets close intent IDs for a trade
	 * @param tradeId The trade ID
	 * @return Array of close intent IDs
	 */
	function getCloseIntentIds(uint256 tradeId) external view returns (uint256[] memory) {
		return CloseIntentStorage.layout().closeIntentIdsOf[tradeId];
	}

	/**
	 * @notice Gets paginated close intents for a trade
	 * @param tradeId The trade ID
	 * @param start The starting index
	 * @param size The number of items to return
	 * @return Array of close intents
	 */
	function getCloseIntents(uint256 tradeId, uint256 start, uint256 size) external view returns (CloseIntent[] memory) {
		CloseIntentStorage.Layout storage layout = CloseIntentStorage.layout();
		uint256[] memory intentIds = layout.closeIntentIdsOf[tradeId];

		if (start >= intentIds.length) {
			return new CloseIntent[](0);
		}

		uint256 end = start + size;
		if (end > intentIds.length) {
			end = intentIds.length;
		}

		CloseIntent[] memory intents = new CloseIntent[](end - start);
		for (uint256 i = start; i < end; i++) {
			intents[i - start] = layout.closeIntents[intentIds[i]];
		}

		return intents;
	}

	/**
	 * @notice Gets the last close intent ID
	 * @return The last intent ID
	 */
	function getLastCloseIntentId() external view returns (uint256) {
		return CloseIntentStorage.layout().lastCloseIntentId;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                    COUNTER PARTY RELATIONS STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets the bound PartyB for a PartyA
	 * @param partyA The PartyA address
	 * @return The bound PartyB address (or zero address if none)
	 */
	function getBoundPartyB(address partyA) external view returns (address) {
		return CounterPartyRelationsStorage.layout().boundPartyB[partyA];
	}

	/**
	 * @notice Gets the unbinding request time for a PartyA
	 * @param partyA The PartyA address
	 * @return The timestamp when unbinding was requested (0 if no request)
	 */
	function getUnbindingRequestTime(address partyA) external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().unbindingRequestTime[partyA];
	}

	/**
	 * @notice Gets the unbinding cooldown period
	 * @return The cooldown period in seconds
	 */
	function getUnbindingCooldown() external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().unbindingCooldown;
	}

	/**
	 * @notice Checks if instant actions mode is active for a user
	 * @param user The user address
	 * @return Whether instant actions mode is active
	 */
	function isInstantActionsModeActive(address user) external view returns (bool) {
		return CounterPartyRelationsStorage.layout().instantActionsMode[user];
	}

	/**
	 * @notice Gets the deactivation time for instant actions mode
	 * @param user The user address
	 * @return The timestamp when deactivation can occur
	 */
	function getInstantActionsModeDeactivateTime(address user) external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().instantActionsModeDeactivateTime[user];
	}

	/**
	 * @notice Gets the deactivation cooldown for instant actions mode
	 * @return The cooldown period in seconds
	 */
	function getDeactiveInstantActionModeCooldown() external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().deactiveInstantActionModeCooldown;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                      FEE MANAGEMENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets the default fee collector address
	 * @return The default fee collector address
	 */
	function getDefaultFeeCollector() external view returns (address) {
		return FeeManagementStorage.layout().defaultFeeCollector;
	}

	/**
	 * @notice Checks affiliate status
	 * @param affiliate The affiliate address
	 * @return Whether the affiliate is active
	 */
	function isAffiliateActive(address affiliate) external view returns (bool) {
		return FeeManagementStorage.layout().affiliateStatus[affiliate];
	}

	/**
	 * @notice Gets the fee collector for an affiliate
	 * @param affiliate The affiliate address
	 * @return The fee collector address
	 */
	function getAffiliateFeeCollector(address affiliate) external view returns (address) {
		return FeeManagementStorage.layout().affiliateFeeCollector[affiliate];
	}

	/**
	 * @notice Gets affiliate fee for a symbol
	 * @param affiliate The affiliate address
	 * @param symbolId The symbol ID
	 * @return The affiliate fee amount
	 */
	function getAffiliateFee(address affiliate, uint256 symbolId) external view returns (uint256) {
		return FeeManagementStorage.layout().affiliateFees[affiliate][symbolId];
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                       LIQUIDATION STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets the liquidation ID for parties and collateral
	 * @param partyA The PartyA address
	 * @param partyB The PartyB address
	 * @param collateral The collateral address
	 * @return The liquidation ID (0 if none)
	 */
	function getInProgressLiquidationId(address partyA, address partyB, address collateral) external view returns (uint256) {
		return LiquidationStorage.layout().inProgressLiquidationIds[partyA][partyB][collateral];
	}

	/**
	 * @notice Gets liquidation details by ID
	 * @param liquidationId The liquidation ID
	 * @return The liquidation details
	 */
	function getLiquidationDetail(uint256 liquidationId) external view returns (LiquidationDetail memory) {
		return LiquidationStorage.layout().liquidationDetails[liquidationId];
	}

	/**
	 * @notice Gets the last liquidation ID
	 * @return The last liquidation ID
	 */
	function getLastLiquidationId() external view returns (uint256) {
		return LiquidationStorage.layout().lastLiquidationId;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                        OPEN INTENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets open intent details
	 * @param intentId The intent ID
	 * @return The open intent details
	 */
	function getOpenIntent(uint256 intentId) external view returns (OpenIntent memory) {
		return OpenIntentStorage.layout().openIntents[intentId];
	}

	/**
	 * @notice Gets active open intent IDs for a user
	 * @param user The user address
	 * @return Array of active open intent IDs
	 */
	function getActiveOpenIntentIds(address user) external view returns (uint256[] memory) {
		return OpenIntentStorage.layout().activeOpenIntentsOf[user];
	}

	/**
	 * @notice Gets the count of active open intents for a user
	 * @param user The user address
	 * @return The count of active open intents
	 */
	function getActiveOpenIntentsCount(address user) external view returns (uint256) {
		return OpenIntentStorage.layout().activeOpenIntentsCount[user];
	}

	/**
	 * @notice Gets paginated active open intents for a user
	 * @param user The user address
	 * @param start The starting index
	 * @param size The number of items to return
	 * @return Array of open intents
	 */
	function getActiveOpenIntents(address user, uint256 start, uint256 size) external view returns (OpenIntent[] memory) {
		OpenIntentStorage.Layout storage layout = OpenIntentStorage.layout();
		uint256[] memory intentIds = layout.activeOpenIntentsOf[user];

		if (start >= intentIds.length) {
			return new OpenIntent[](0);
		}

		uint256 end = start + size;
		if (end > intentIds.length) {
			end = intentIds.length;
		}

		OpenIntent[] memory intents = new OpenIntent[](end - start);
		for (uint256 i = start; i < end; i++) {
			intents[i - start] = layout.openIntents[intentIds[i]];
		}

		return intents;
	}

	/**
	 * @notice Gets the PartyA index for an open intent
	 * @param intentId The intent ID
	 * @return The index in the PartyA's active intents array
	 */
	function getPartyAOpenIntentIndex(uint256 intentId) external view returns (uint256) {
		return OpenIntentStorage.layout().partyAOpenIntentsIndex[intentId];
	}

	/**
	 * @notice Gets the PartyB index for an open intent
	 * @param intentId The intent ID
	 * @return The index in the PartyB's active intents array
	 */
	function getPartyBOpenIntentIndex(uint256 intentId) external view returns (uint256) {
		return OpenIntentStorage.layout().partyBOpenIntentsIndex[intentId];
	}

	/**
	 * @notice Gets the last open intent ID
	 * @return The last intent ID
	 */
	function getLastOpenIntentId() external view returns (uint256) {
		return OpenIntentStorage.layout().lastOpenIntentId;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                       STATE CONTROL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Checks if global operations are paused
	 * @return Whether global pause is active
	 */
	function isGlobalPaused() external view returns (bool) {
		return StateControlStorage.layout().globalPaused;
	}

	/**
	 * @notice Checks if depositing is paused
	 * @return Whether depositing is paused
	 */
	function isDepositingPaused() external view returns (bool) {
		return StateControlStorage.layout().depositingPaused;
	}

	/**
	 * @notice Checks if withdrawing is paused
	 * @return Whether withdrawing is paused
	 */
	function isWithdrawingPaused() external view returns (bool) {
		return StateControlStorage.layout().withdrawingPaused;
	}

	/**
	 * @notice Checks if PartyB actions are paused
	 * @return Whether PartyB actions are paused
	 */
	function isPartyBActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().partyBActionsPaused;
	}

	/**
	 * @notice Checks if PartyA actions are paused
	 * @return Whether PartyA actions are paused
	 */
	function isPartyAActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().partyAActionsPaused;
	}

	/**
	 * @notice Checks if liquidating is paused
	 * @return Whether liquidating is paused
	 */
	function isLiquidatingPaused() external view returns (bool) {
		return StateControlStorage.layout().liquidatingPaused;
	}

	/**
	 * @notice Checks if third party actions are paused
	 * @return Whether third party actions are paused
	 */
	function isThirdPartyActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().thirdPartyActionsPaused;
	}

	/**
	 * @notice Checks if internal transfers are paused
	 * @return Whether internal transfers are paused
	 */
	function isInternalTransferPaused() external view returns (bool) {
		return StateControlStorage.layout().internalTransferPaused;
	}

	/**
	 * @notice Checks if bridge operations are paused
	 * @return Whether bridge operations are paused
	 */
	function isBridgePaused() external view returns (bool) {
		return StateControlStorage.layout().bridgePaused;
	}

	/**
	 * @notice Checks if bridge withdrawals are paused
	 * @return Whether bridge withdrawals are paused
	 */
	function isBridgeWithdrawPaused() external view returns (bool) {
		return StateControlStorage.layout().bridgeWithdrawPaused;
	}

	/**
	 * @notice Returns all system pause states
	 * @return globalPaused Whether global operations are paused
	 * @return depositingPaused Whether depositing is paused
	 * @return withdrawingPaused Whether withdrawing is paused
	 * @return partyBActionsPaused Whether PartyB actions are paused
	 * @return partyAActionsPaused Whether PartyA actions are paused
	 * @return liquidatingPaused Whether liquidating is paused
	 * @return thirdPartyActionsPaused Whether third party actions are paused
	 * @return internalTransferPaused Whether internal transfers are paused
	 * @return bridgePaused Whether bridge operations are paused
	 * @return bridgeWithdrawPaused Whether bridge withdrawals are paused
	 * @return emergencyMode Whether emergency mode is active
	 */
	function getAllPauseStates()
		external
		view
		returns (
			bool globalPaused,
			bool depositingPaused,
			bool withdrawingPaused,
			bool partyBActionsPaused,
			bool partyAActionsPaused,
			bool liquidatingPaused,
			bool thirdPartyActionsPaused,
			bool internalTransferPaused,
			bool bridgePaused,
			bool bridgeWithdrawPaused,
			bool emergencyMode
		)
	{
		StateControlStorage.Layout storage stateLayout = StateControlStorage.layout();
		return (
			stateLayout.globalPaused,
			stateLayout.depositingPaused,
			stateLayout.withdrawingPaused,
			stateLayout.partyBActionsPaused,
			stateLayout.partyAActionsPaused,
			stateLayout.liquidatingPaused,
			stateLayout.thirdPartyActionsPaused,
			stateLayout.internalTransferPaused,
			stateLayout.bridgePaused,
			stateLayout.bridgeWithdrawPaused,
			stateLayout.emergencyMode
		);
	}

	/**
	 * @notice Checks if emergency mode is active
	 * @return Whether emergency mode is active
	 */
	function isEmergencyMode() external view returns (bool) {
		return StateControlStorage.layout().emergencyMode;
	}

	/**
	 * @notice Checks PartyB emergency status
	 * @param partyB The PartyB address
	 * @return Whether PartyB is in emergency mode
	 */
	function isPartyBInEmergencyMode(address partyB) external view returns (bool) {
		return StateControlStorage.layout().partyBEmergencyMode[partyB];
	}

	/**
	 * @notice Checks if an address is suspended
	 * @param user The user address
	 * @return Whether the address is suspended
	 */
	function isAddressSuspended(address user) external view returns (bool) {
		return StateControlStorage.layout().suspendedAddresses[user];
	}

	/**
	 * @notice Checks if a withdrawal is suspended
	 * @param withdrawId The withdrawal ID
	 * @return Whether the withdrawal is suspended
	 */
	function isWithdrawalSuspended(uint256 withdrawId) external view returns (bool) {
		return StateControlStorage.layout().suspendedWithdrawal[withdrawId];
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                       ACCESS CONTROL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Checks if a user has a specific role
	 * @param user The user address
	 * @param role The role identifier
	 * @return Whether the user has the role
	 */
	function hasRole(address user, bytes32 role) external view returns (bool) {
		return AccessControlStorage.layout().hasRole[user][role];
	}

	/**
	 * @notice Gets role members
	 * @param role The role identifier
	 * @return Array of addresses that have the role
	 */
	function getRoleMembers(bytes32 role) external view returns (address[] memory) {
		return AccessControlStorage.layout().roleMembers[role].values();
	}

	/**
	 * @notice Gets the count of role members
	 * @param role The role identifier
	 * @return The number of members with this role
	 */
	function getRoleMemberCount(bytes32 role) external view returns (uint256) {
		return AccessControlStorage.layout().roleMembers[role].length();
	}

	/**
	 * @notice Gets a role member by index
	 * @param role The role identifier
	 * @param index The member index
	 * @return The member address at the given index
	 */
	function getRoleMember(bytes32 role, uint256 index) external view returns (address) {
		return AccessControlStorage.layout().roleMembers[role].at(index);
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                          SYMBOL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets oracle details
	 * @param oracleId The oracle ID
	 * @return The oracle details
	 */
	function getOracle(uint256 oracleId) external view returns (Oracle memory) {
		return SymbolStorage.layout().oracles[oracleId];
	}

	/**
	 * @notice Gets the last oracle ID
	 * @return The last oracle ID
	 */
	function getLastOracleId() external view returns (uint256) {
		return SymbolStorage.layout().lastOracleId;
	}

	/**
	 * @notice Gets symbol details
	 * @param symbolId The symbol ID
	 * @return The symbol details
	 */
	function getSymbol(uint256 symbolId) external view returns (Symbol memory) {
		return SymbolStorage.layout().symbols[symbolId];
	}

	/**
	 * @notice Gets paginated symbols
	 * @param start The starting index
	 * @param size The number of items to return
	 * @return Array of symbols
	 */
	function getSymbols(uint256 start, uint256 size) external view returns (Symbol[] memory) {
		SymbolStorage.Layout storage layout = SymbolStorage.layout();

		if (start > layout.lastSymbolId) {
			return new Symbol[](0);
		}

		uint256 end = start + size;
		if (end > layout.lastSymbolId + 1) {
			end = layout.lastSymbolId + 1;
		}

		Symbol[] memory symbols = new Symbol[](end - start);
		for (uint256 i = start; i < end; i++) {
			symbols[i - start] = layout.symbols[i];
		}

		return symbols;
	}

	/**
	 * @notice Gets the last symbol ID
	 * @return The last symbol ID
	 */
	function getLastSymbolId() external view returns (uint256) {
		return SymbolStorage.layout().lastSymbolId;
	}

	// ════════════════════════════════════════════════════════════════════════════
	//                          TRADE STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	/**
	 * @notice Gets trade details
	 * @param tradeId The trade ID
	 * @return The trade details
	 */
	function getTrade(uint256 tradeId) external view returns (Trade memory) {
		return TradeStorage.layout().trades[tradeId];
	}

	/**
	 * @notice Gets all active trade IDs for a user
	 * @param user The user address
	 * @return Array of trade IDs
	 */
	function getActiveTradeIdsOfPartyA(address user) external view returns (uint256[] memory) {
		return TradeStorage.layout().activeTradesOfPartyA[user];
	}

	/**
	 * @notice Gets paginated active trades for a user
	 * @param user The user address
	 * @param start The starting index
	 * @param size The number of items to return
	 * @return Array of trades
	 */
	function getActiveTradesOfPartyA(address user, uint256 start, uint256 size) external view returns (Trade[] memory) {
		TradeStorage.Layout storage layout = TradeStorage.layout();
		uint256[] memory tradeIds = layout.activeTradesOfPartyA[user];

		if (start >= tradeIds.length) {
			return new Trade[](0);
		}

		uint256 end = start + size;
		if (end > tradeIds.length) {
			end = tradeIds.length;
		}

		Trade[] memory trades = new Trade[](end - start);
		for (uint256 i = start; i < end; i++) {
			trades[i - start] = layout.trades[tradeIds[i]];
		}

		return trades;
	}

	/**
	 * @notice Gets active trade IDs for PartyB and collateral
	 * @param partyB The PartyB address
	 * @param collateral The collateral address
	 * @return Array of active trade IDs
	 */
	function getActiveTradeIdsForPartyB(address partyB, address collateral) external view returns (uint256[] memory) {
		return TradeStorage.layout().activeTradesOfPartyB[partyB][collateral];
	}

	/**
	 * @notice Gets the PartyA trade index
	 * @param tradeId The trade ID
	 * @return The index in PartyA's active trades array
	 */
	function getPartyATradeIndex(uint256 tradeId) external view returns (uint256) {
		return TradeStorage.layout().partyATradesIndex[tradeId];
	}

	/**
	 * @notice Gets the PartyB trade index
	 * @param tradeId The trade ID
	 * @return The index in PartyB's active trades array
	 */
	function getPartyBTradeIndex(uint256 tradeId) external view returns (uint256) {
		return TradeStorage.layout().partyBTradesIndex[tradeId];
	}

	/**
	 * @notice Gets the last trade ID
	 * @return The last trade ID
	 */
	function getLastTradeId() external view returns (uint256) {
		return TradeStorage.layout().lastTradeId;
	}
}
