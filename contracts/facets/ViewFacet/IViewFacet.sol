// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { PartyBConfig } from "../../storages/AppStorage.sol";
import { Symbol, Oracle } from "../../storages/SymbolStorage.sol";

import { Trade } from "../../types/TradeTypes.sol";
import { Withdraw } from "../../types/WithdrawTypes.sol";
import { BridgeTransaction } from "../../types/BridgeTypes.sol";
import { OpenIntent, CloseIntent } from "../../types/IntentTypes.sol";
import { LiquidationDetail } from "../../types/LiquidationTypes.sol";
import { ScheduledReleaseEntry, CrossEntry } from "../../types/BalanceTypes.sol";

/**
 * @title IViewFacet
 * @notice Interface for read-only access to all protocol state
 * @dev Organized by storage contract for clarity and completeness
 */
interface IViewFacet {
	// ════════════════════════════════════════════════════════════════════════════
	//                           ACCOUNT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getIsolatedBalance(address user, address collateral) external view returns (uint256);
	function getIsolatedLockedBalance(address user, address collateral) external view returns (uint256);
	function getReserveBalance(address user, address collateral) external view returns (uint256);
	function getCrossBalance(address user, address collateral, address counterParty) external view returns (CrossEntry memory);
	function getScheduledReleaseEntry(address user, address collateral, address counterParty) external view returns (ScheduledReleaseEntry memory);
	function getCounterPartyAddresses(address user, address collateral) external view returns (address[] memory);
	function getWithdrawal(uint256 withdrawId) external view returns (Withdraw memory);
	function getLastWithdrawalId() external view returns (uint256);
	function getReleaseInterval(address user) external view returns (uint256);
	function getDefaultReleaseInterval() external view returns (uint256);
	function getUserReleaseInterval(address user) external view returns (bool hasConfigured, uint256 interval);
	function getMaxConnectedCounterParties() external view returns (uint256);
	function isManualSync(address user) external view returns (bool);
	function getNonce(address party, address counterParty) external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                           APP STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getVersion() external view returns (uint16);
	function getBalanceLimitPerUser(address collateral) external view returns (uint256);
	function getMaxCloseOrdersLength() external view returns (uint256);
	function getMaxTradePerPartyA() external view returns (uint256);
	function getPriceOracleAddress() external view returns (address);
	function isWhitelistedCollateral(address collateral) external view returns (bool);
	function getTradeNftAddress() external view returns (address);
	function isSignatureUsed(bytes32 sigHash) external view returns (bool);
	function getSignatureVerifier() external view returns (address);
	function getPartyADeallocateCooldown() external view returns (uint256);
	function getPartyBDeallocateCooldown() external view returns (uint256);
	function getForceCancelOpenIntentTimeout() external view returns (uint256);
	function getForceCancelCloseIntentTimeout() external view returns (uint256);
	function getPartyBExclusiveWindow() external view returns (uint256);
	function getSettlementPriceSigValidTime() external view returns (uint256);
	function getPartyBConfig(address partyB) external view returns (PartyBConfig memory);
	function isCallFromInstantLayer() external view returns (bool);

	// ════════════════════════════════════════════════════════════════════════════
	//                           BRIDGE STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function isBridgeWhitelisted(address bridge) external view returns (bool);
	function getBridgeTransaction(uint256 transactionId) external view returns (BridgeTransaction memory);
	function getLastBridgeTransactionId() external view returns (uint256);
	function getInvalidBridgedAmountsPool() external view returns (address);

	// ════════════════════════════════════════════════════════════════════════════
	//                        CLOSE INTENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getCloseIntent(uint256 intentId) external view returns (CloseIntent memory);
	function getCloseIntentIds(uint256 tradeId) external view returns (uint256[] memory);
	function getCloseIntents(uint256 tradeId, uint256 start, uint256 size) external view returns (CloseIntent[] memory);
	function getLastCloseIntentId() external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                    COUNTER PARTY RELATIONS STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getBoundPartyB(address partyA) external view returns (address);
	function getUnbindingRequestTime(address partyA) external view returns (uint256);
	function getUnbindingCooldown() external view returns (uint256);
	function isInstantActionsModeActive(address user) external view returns (bool);
	function getInstantActionsModeDeactivateTime(address user) external view returns (uint256);
	function getDeactiveInstantActionModeCooldown() external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                      FEE MANAGEMENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getDefaultFeeCollector() external view returns (address);
	function isAffiliateActive(address affiliate) external view returns (bool);
	function getAffiliateFeeCollector(address affiliate) external view returns (address);
	function getAffiliateFee(address affiliate, uint256 symbolId) external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                       LIQUIDATION STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getInProgressLiquidationId(address partyA, address partyB, address collateral) external view returns (uint256);
	function getLiquidationDetail(uint256 liquidationId) external view returns (LiquidationDetail memory);
	function getLastLiquidationId() external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                        OPEN INTENT STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getOpenIntent(uint256 intentId) external view returns (OpenIntent memory);
	function getActiveOpenIntentIds(address user) external view returns (uint256[] memory);
	function getActiveOpenIntentsCount(address user) external view returns (uint256);
	function getActiveOpenIntents(address user, uint256 start, uint256 size) external view returns (OpenIntent[] memory);
	function getPartyAOpenIntentIndex(uint256 intentId) external view returns (uint256);
	function getPartyBOpenIntentIndex(uint256 intentId) external view returns (uint256);
	function getLastOpenIntentId() external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                       STATE CONTROL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function isGlobalPaused() external view returns (bool);
	function isDepositingPaused() external view returns (bool);
	function isWithdrawingPaused() external view returns (bool);
	function isPartyBActionsPaused() external view returns (bool);
	function isPartyAActionsPaused() external view returns (bool);
	function isLiquidatingPaused() external view returns (bool);
	function isThirdPartyActionsPaused() external view returns (bool);
	function isInternalTransferPaused() external view returns (bool);
	function isBridgePaused() external view returns (bool);
	function isBridgeWithdrawPaused() external view returns (bool);
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
		);
	function isEmergencyMode() external view returns (bool);
	function isPartyBInEmergencyMode(address partyB) external view returns (bool);
	function isAddressSuspended(address user) external view returns (bool);
	function isWithdrawalSuspended(uint256 withdrawId) external view returns (bool);

	// ════════════════════════════════════════════════════════════════════════════
	//                       ACCESS CONTROL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function hasRole(address user, bytes32 role) external view returns (bool);
	function getRoleMembers(bytes32 role) external view returns (address[] memory);
	function getRoleMemberCount(bytes32 role) external view returns (uint256);
	function getRoleMember(bytes32 role, uint256 index) external view returns (address);

	// ════════════════════════════════════════════════════════════════════════════
	//                          SYMBOL STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getOracle(uint256 oracleId) external view returns (Oracle memory);
	function getLastOracleId() external view returns (uint256);
	function getSymbol(uint256 symbolId) external view returns (Symbol memory);
	function getSymbols(uint256 start, uint256 size) external view returns (Symbol[] memory);
	function getLastSymbolId() external view returns (uint256);

	// ════════════════════════════════════════════════════════════════════════════
	//                          TRADE STORAGE VIEWS
	// ════════════════════════════════════════════════════════════════════════════

	function getTrade(uint256 tradeId) external view returns (Trade memory);
	function getActiveTradeIdsOfPartyA(address user) external view returns (uint256[] memory);
	function getActiveTradesOfPartyA(address user, uint256 start, uint256 size) external view returns (Trade[] memory);
	function getActiveTradeIdsForPartyB(address partyB, address collateral) external view returns (uint256[] memory);
	function getPartyATradeIndex(uint256 tradeId) external view returns (uint256);
	function getPartyBTradeIndex(uint256 tradeId) external view returns (uint256);
	function getLastTradeId() external view returns (uint256);
}
