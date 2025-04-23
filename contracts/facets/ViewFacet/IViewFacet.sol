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
import { TransferIntent } from "../../types/TransferIntentTypes.sol";
import { OpenIntent, CloseIntent } from "../../types/IntentTypes.sol";
import { LiquidationDetail, LiquidationState } from "../../types/LiquidationTypes.sol";

interface IViewFacet {
	struct Bitmap {
		uint256 size;
		BitmapElement[] elements;
	}

	struct BitmapElement {
		uint256 offset;
		uint256 bitmap;
	}

	// Account
	function balanceOf(address user, address collateral) external view returns (uint256);

	function partyAStats(address partyA, address collateral) external view returns (bool, uint256, uint256[] memory, uint256[] memory);

	function getReleaseInterval(address user) external view returns (uint256);

	function getMaxConnectedCounterParties() external view returns (uint256);

	function getWithdraw(uint256 id) external view returns (Withdraw memory);

	function isSuspended(address user) external view returns (bool);

	function isSuspendedWithdrawal(uint256 withdrawId) external view returns (bool);

	function getBridges(address bridge) external view returns (bool);

	function getBridgeTransaction(uint256 bridgeId) external view returns (BridgeTransaction memory);

	function getBridgeTransactionIds(address bridge) external view returns (uint256[] memory);

	function getLastBridgeId() external view returns (uint256);

	function getInvalidBridgedAmountsPool() external view returns (address);
	///////////////////////////////////////////

	// Symbols
	function getSymbol(uint256 symbolId) external view returns (Symbol memory);

	function getSymbols(uint256 start, uint256 size) external view returns (Symbol[] memory);

	function getLastSymbolId() external view returns (uint256);

	function symbolsByOpenIntentId(uint256[] memory openIntentIds) external view returns (Symbol[] memory);

	function symbolNameByTradeId(uint256[] memory tradeIds) external view returns (string[] memory);

	function symbolNameById(uint256[] memory symbolIds) external view returns (string[] memory);

	function getOracle(uint256 oracleId) external view returns (Oracle memory);

	function getLastOracleId() external view returns (uint256);

	// Intents
	function getOpenIntent(uint256 openIntentId) external view returns (OpenIntent memory);

	function getOpenIntentsByParent(uint256 openIntentId, uint256 size) external view returns (OpenIntent[] memory);

	function openIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory);

	function openIntentsLength(address user) external view returns (uint256);

	function activeOpenIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getActiveOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory);

	function activeOpenIntentsLength(address user) external view returns (uint256);

	function activeOpenIntentsCount(address user) external view returns (uint256);

	function getLastOpenIntentId() external view returns (uint256);

	function partyATradesIndex(uint256 index) external view returns (uint256);

	function partyBTradesIndex(uint256 index) external view returns (uint256);

	function getLastTradeId() external view returns (uint256);

	function getLastCloseIntentId() external view returns (uint256);

	function isSigUsed(bytes32 intentHash) external view returns (bool);

	function signatureVerifier() external view returns (address);

	function getTransferIntent(uint256 intentId) external view returns (TransferIntent memory);

	function getLastTransferIntentId() external view returns (uint256);

	function getOpenIntentsWithBitmap(Bitmap calldata bitmap, uint256 gasNeededForReturn) external view returns (OpenIntent[] memory openIntents);

	function getTrade(uint256 tradeId) external view returns (Trade memory);

	function tradeIdsOf(address user, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getTradesOf(address user, uint256 start, uint256 size) external view returns (Trade[] memory);

	function tradesOfLength(address user) external view returns (uint256);

	function activePartyATradeIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory);

	function activePartyBTradeIdsOf(address partyB, address collateral, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getActivePartyATradesOf(address partyA, uint256 start, uint256 size) external view returns (Trade[] memory);

	function getActivePartyBTradesOf(address partyB, address collateral, uint256 start, uint256 size) external view returns (Trade[] memory);

	function activePartyATradesLength(address partyA) external view returns (uint256);

	function activePartyBTradesLength(address partyB, address collateral) external view returns (uint256);

	function getCloseIntent(uint256 closeIntentId) external view returns (CloseIntent memory);

	function closeIntentIdsOf(uint256 tradeId, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getCloseIntentsOf(uint256 tradeId, uint256 start, uint256 size) external view returns (CloseIntent[] memory);

	//App
	function whiteListedCollateral(address collateral) external view returns (bool);

	function balanceLimitPerUser() external view returns (uint256);

	function maxCloseOrdersLength() external view returns (uint256);

	function maxTradePerPartyA() external view returns (uint256);

	function priceOracleAddress() external view returns (address);

	function globalPaused() external view returns (bool);

	function depositingPaused() external view returns (bool);

	function withdrawingPaused() external view returns (bool);

	function partyBActionsPaused() external view returns (bool);

	function partyAActionsPaused() external view returns (bool);

	function liquidatingPaused() external view returns (bool);

	function thirdPartyActionsPaused() external view returns (bool);

	function internalTransferPaused() external view returns (bool);

	function bridgePaused() external view returns (bool);

	function bridgeWithdrawPaused() external view returns (bool);

	function emergencyMode() external view returns (bool);

	function partyBEmergencyStatus(address partyB) external view returns (bool);

	function partyADeallocateCooldown() external view returns (uint256);

	function partyBDeallocateCooldown() external view returns (uint256);

	function forceCancelOpenIntentTimeout() external view returns (uint256);

	function forceCancelCloseIntentTimeout() external view returns (uint256);

	function ownerExclusiveWindow() external view returns (uint256);

	function defaultFeeCollector() external view returns (address);

	function affiliateStatus(address affiliate) external view returns (bool);

	function affiliateFeeCollector(address affiliate) external view returns (address);

	function partyBConfigs(address partyB) external view returns (PartyBConfig memory);

	function partyBList() external view returns (address[] memory);

	function tradeNftAddress() external view returns (address);

	function settlementPriceSigValidTime() external view returns (uint256);

	function liquidationSigValidTime() external view returns (uint256);

	function version() external view returns (uint16);

	function liquidationStates(address partyBAddress, address collateral) external view returns (LiquidationState memory);

	function liquidationDetail(uint256 liquidationId) external view returns (LiquidationDetail memory);

	function liquidationDebtsToPartyAs(address partyB, address collateral, address partyA) external view returns (uint256);

	function involvedPartyAsCountInLiquidation(address partyB, address collateral) external view returns (uint256);

	function affiliateFees(address affiliate, uint256 symbolId) external view returns (uint256);

	//Role
	function hasRole(address user, bytes32 role) external view returns (bool);

	function getRoleHash(string memory str) external pure returns (bytes32);
}
