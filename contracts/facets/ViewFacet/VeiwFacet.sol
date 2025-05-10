// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";

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

import { IViewFacet } from "./IViewFacet.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ViewFacet is IViewFacet {
	using EnumerableSet for EnumerableSet.AddressSet;
	using LibParty for address;

	/**
	 * @notice Returns the balance for a specified user and collateral type.
	 * @param user The address of the user.
	 * @param collateral The address of the collateral type.
	 * @return balance The balance of the user and specific collateral type.
	 */
	function balanceOf(address user, address collateral) external view returns (uint256) {
		return AccountStorage.layout().balances[user][collateral].isolatedBalance;
	}

	/**
	 * @notice Returns max connected partyBs.
	 * @return max connected partyBs.
	 */
	function getMaxConnectedCounterParties() external view returns (uint256) {
		return AccountStorage.layout().maxConnectedCounterParties;
	}

	function getReleaseInterval(address user) external view returns (uint256) {
		return user.getReleaseInterval();
	}

	/**
	 * @notice Returns various values related to Party A.
	 * @param partyA The address of Party A.
	 // TODO 1, return liquidationStatus The liquidation status of Party A.
	 * @return suspendedAddresses returns a true/false representing whether the given address is suspended or not.
	 * @return balance The balance of Party A.
	 * @return openIntentsOf The list of openIntents of Party A.
	 * @return tradesOf The list of trades of Party A.
	 */
	function partyAStats(address partyA, address collateral) external view returns (bool, uint256, uint256[] memory, uint256[] memory) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		// MAStorage.Layout storage maLayout = MAStorage.layout();  #TODO 1: consider adding this after liquidation dev.
		return (
			// maLayout.liquidationStatus[partyA], #TODO 1
			StateControlStorage.layout().suspendedAddresses[partyA],
			accountLayout.balances[partyA][collateral].isolatedBalance,
			//TODO 2: consider adding AppStorage:partyAReimbursement after it's used
			OpenIntentStorage.layout().openIntentsOf[partyA],
			TradeStorage.layout().tradesOf[partyA]
			// intentLayout.closeIntentIdsOf TODO 3: consider adding this if it's necessary
		);
	}

	/**
	 * @notice Returns the Withdraw object. You can read Withdraw object attributes at AccountFact:Withdraw
	 * @param id The id of the Withdraw object.
	 * @return Withdraw The Withdraw object associated with the given `id`.
	 */
	function getWithdraw(uint256 id) external view returns (Withdraw memory) {
		return AccountStorage.layout().withdrawals[id];
	}

	/**
	 @notice Checks whether the user is suspned or not.
	 @param user The address of the user.
	 @return isSuspended A boolean value(true/false) to show that the `user` is suspended or not.
	 */
	function isSuspended(address user) external view returns (bool) {
		return StateControlStorage.layout().suspendedAddresses[user];
	}

	/**
	 @notice Checks whether the withdraw is suspended or not.
	 @param withdrawId The id of withdraw.
	 @return isSuspendedWithdrawal A boolean value(true/false) to show that the `withdraw` is suspended or not.
	 */
	function isSuspendedWithdrawal(uint256 withdrawId) external view returns (bool) {
		return StateControlStorage.layout().suspendedWithdrawal[withdrawId];
	}

	function getBridges(address bridge) external view returns (bool) {
		return BridgeStorage.layout().bridges[bridge];
	}

	function getBridgeTransaction(uint256 bridgeId) external view returns (BridgeTransaction memory) {
		return BridgeStorage.layout().bridgeTransactions[bridgeId];
	}

	function getBridgeTransactionIds(address bridge) external view returns (uint256[] memory) {
		return BridgeStorage.layout().bridgeTransactionIds[bridge];
	}

	function getLastBridgeId() external view returns (uint256) {
		return BridgeStorage.layout().lastBridgeId;
	}

	function getInvalidBridgedAmountsPool() external view returns (address) {
		return BridgeStorage.layout().invalidBridgedAmountsPool;
	}

	/**
	 * @notice Returns the details of a symbol by its ID.
	 * @param symbolId The ID of the symbol.
	 * @return symbol The details of the symbol.
	 */
	function getSymbol(uint256 symbolId) external view returns (Symbol memory) {
		return SymbolStorage.layout().symbols[symbolId];
	}

	/**
	 * @notice Returns an array of symbols starting from a specific index.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return symbols An array of symbols.
	 */
	function getSymbols(uint256 start, uint256 size) external view returns (Symbol[] memory) {
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();
		if (symbolLayout.lastSymbolId < start + size) {
			size = symbolLayout.lastSymbolId - start;
		}
		Symbol[] memory symbols = new Symbol[](size);
		for (uint256 i = start; i < start + size; i++) {
			symbols[i - start] = symbolLayout.symbols[i + 1];
		}
		return symbols;
	}

	/**
	 * @notice Returns last symbol id.
	 * @return last symbol id.
	 */
	function getLastSymbolId() external view returns (uint256) {
		return SymbolStorage.layout().lastSymbolId;
	}

	/**
	 * @notice Returns an array of symbols associated with an array of openIntent IDs.
	 * @param openIntentIds An array of openIntent IDs.
	 * @return symbols An array of symbols.
	 */
	function symbolsByOpenIntentId(uint256[] memory openIntentIds) external view returns (Symbol[] memory) {
		Symbol[] memory symbols = new Symbol[](openIntentIds.length);
		for (uint256 i = 0; i < openIntentIds.length; i++) {
			symbols[i] = SymbolStorage.layout().symbols[OpenIntentStorage.layout().openIntents[openIntentIds[i]].tradeAgreements.symbolId];
		}
		return symbols;
	}

	/**
	 * @notice Returns an array of symbol names associated with an array of trade IDs.
	 * @param tradeIds An array of trade IDs.
	 * @return symbols An array of symbol names.
	 */
	function symbolNameByTradeId(uint256[] memory tradeIds) external view returns (string[] memory) {
		string[] memory symbols = new string[](tradeIds.length);
		for (uint256 i = 0; i < tradeIds.length; i++) {
			symbols[i] = SymbolStorage.layout().symbols[TradeStorage.layout().trades[tradeIds[i]].tradeAgreements.symbolId].name;
		}
		return symbols;
	}

	/**
	 * @notice Returns an array of symbol names associated with an array of symbol IDs.
	 * @param symbolIds An array of symbol IDs.
	 * @return symbolNames An array of symbol names.
	 */
	function symbolNameById(uint256[] memory symbolIds) external view returns (string[] memory) {
		string[] memory symbolNames = new string[](symbolIds.length);
		for (uint256 i = 0; i < symbolIds.length; i++) {
			symbolNames[i] = SymbolStorage.layout().symbols[symbolIds[i]].name;
		}
		return symbolNames;
	}

	/**
	 * @notice Returns the details of a oracle by its ID.
	 * @param oracleId The ID of the oracle.
	 * @return oracle The details of the oracle.
	 */
	function getOracle(uint256 oracleId) external view returns (Oracle memory) {
		return SymbolStorage.layout().oracles[oracleId];
	}

	/**
	 * @notice Returns last oracle id.
	 * @return last oracle id.
	 */
	function getLastOracleId() external view returns (uint256) {
		return SymbolStorage.layout().lastOracleId;
	}

	/**
	 * @notice Returns the details of a openIntent by its ID.
	 * @param openIntentId The ID of the openIntent.
	 * @return openIntent The details of the openIntent.
	 */
	function getOpenIntent(uint256 openIntentId) external view returns (OpenIntent memory) {
		return OpenIntentStorage.layout().openIntents[openIntentId];
	}

	/**
	 * @notice Returns an array of openIntents associated with a parent openIntent ID.
	 * @param openIntentId The parent openIntent ID.
	 * @param size The size of the array.
	 * @return openIntents An array of openIntents.
	 */
	function getOpenIntentsByParent(uint256 openIntentId, uint256 size) external view returns (OpenIntent[] memory) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		OpenIntent[] memory openIntents = new OpenIntent[](size);
		OpenIntent memory openIntent = intentLayout.openIntents[openIntentId];
		openIntents[0] = openIntent;
		for (uint256 i = 1; i < size; i++) {
			if (openIntent.parentId == 0) {
				break;
			}
			openIntent = intentLayout.openIntents[openIntent.parentId];
			openIntents[i] = openIntent;
		}
		return openIntents;
	}

	/**
	 * @notice Returns an array of openIntent IDs associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return openIntentIds An array of openIntent IDs.
	 */
	function openIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		if (intentLayout.openIntentsOf[partyA].length < start + size) {
			size = intentLayout.openIntentsOf[partyA].length - start;
		}
		uint256[] memory openIntentIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			openIntentIds[i - start] = intentLayout.openIntentsOf[partyA][i];
		}
		return openIntentIds;
	}

	/**
	 * @notice Returns an array of openIntent associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return openIntents An array of openIntents.
	 */
	function getOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		if (intentLayout.openIntentsOf[partyA].length < start + size) {
			size = intentLayout.openIntentsOf[partyA].length - start;
		}
		OpenIntent[] memory openIntents = new OpenIntent[](size);
		for (uint256 i = start; i < start + size; i++) {
			openIntents[i - start] = intentLayout.openIntents[intentLayout.openIntentsOf[partyA][i]];
		}
		return openIntents;
	}

	/**
	 * @notice Returns the length of the openIntents array associated with a user.
	 * @param user The address of the user.
	 * @return length The length of the openIntents array.
	 */
	function openIntentsLength(address user) external view returns (uint256) {
		return OpenIntentStorage.layout().openIntentsOf[user].length;
	}

	/**
	 * @notice Returns an array of active openIntent IDs associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeOpenIntentIds An array of openIntent IDs that are active.
	 */
	function activeOpenIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		if (intentLayout.activeOpenIntentsOf[partyA].length < start + size) {
			size = intentLayout.activeOpenIntentsOf[partyA].length - start;
		}
		uint256[] memory activeOpenIntentIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeOpenIntentIds[i - start] = intentLayout.activeOpenIntentsOf[partyA][i];
		}
		return activeOpenIntentIds;
	}

	/**
	 * @notice Returns an array of active openIntent associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeOpenIntents An array of active openIntents.
	 */
	function getActiveOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();
		if (intentLayout.activeOpenIntentsOf[partyA].length < start + size) {
			size = intentLayout.activeOpenIntentsOf[partyA].length - start;
		}
		OpenIntent[] memory activeOpenIntents = new OpenIntent[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeOpenIntents[i - start] = intentLayout.openIntents[intentLayout.activeOpenIntentsOf[partyA][i]];
		}
		return activeOpenIntents;
	}

	/**
	 * @notice Returns the length of the active openIntents array associated with a user.
	 * @param user The address of the user.
	 * @return length The length of the active openIntents array.
	 */
	function activeOpenIntentsLength(address user) external view returns (uint256) {
		return OpenIntentStorage.layout().activeOpenIntentsOf[user].length;
	}

	function activeOpenIntentsCount(address user) external view returns (uint256) {
		return OpenIntentStorage.layout().activeOpenIntentsCount[user];
	}

	function getLastOpenIntentId() external view returns (uint256) {
		return OpenIntentStorage.layout().lastOpenIntentId;
	}

	function partyATradesIndex(uint256 index) external view returns (uint256) {
		return TradeStorage.layout().partyATradesIndex[index];
	}

	function partyBTradesIndex(uint256 index) external view returns (uint256) {
		return TradeStorage.layout().partyBTradesIndex[index];
	}

	function getLastTradeId() external view returns (uint256) {
		return TradeStorage.layout().lastTradeId;
	}

	function getLastCloseIntentId() external view returns (uint256) {
		return CloseIntentStorage.layout().lastCloseIntentId;
	}

	function isSigUsed(bytes32 intentHash) external view returns (bool) {
		return AppStorage.layout().isSigUsed[intentHash];
	}

	function signatureVerifier() external view returns (address) {
		return AppStorage.layout().signatureVerifier;
	}

	/**
	 * @notice Retrieves a filtered list of openIntents based on a bitmap. The method returns openIntents only if sufficient gas remains.
	 * @param bitmap A structured data type representing a bitmap, used to indicate which openIntents to retrieve based on their positions. The bitmap consists of multiple elements, each with an offset and a 256-bit integer representing selectable openIntents.
	 * @param gasNeededForReturn The minimum gas required to complete the function execution and return the data. This ensures the function doesn't start a retrieval that it can't complete.
	 * @return openIntents An array of `OpenIntent` structures, each corresponding to a openIntent identified by the bitmap.
	 */
	function getOpenIntentsWithBitmap(Bitmap calldata bitmap, uint256 gasNeededForReturn) external view returns (OpenIntent[] memory openIntents) {
		OpenIntentStorage.Layout storage intentLayout = OpenIntentStorage.layout();

		openIntents = new OpenIntent[](bitmap.size);
		uint256 openIntentIndex = 0;

		for (uint256 i = 0; i < bitmap.elements.length; ++i) {
			uint256 bits = bitmap.elements[i].bitmap;
			uint256 offset = bitmap.elements[i].offset;
			while (bits > 0 && gasleft() > gasNeededForReturn) {
				if ((bits & 1) > 0) {
					openIntents[openIntentIndex] = intentLayout.openIntents[offset];
					++openIntentIndex;
				}
				++offset;
				bits >>= 1;
			}
		}
	}

	/**
	 * @notice Returns the details of a trade by its ID.
	 * @param tradeId The ID of the trade.
	 * @return trade The details of the trade.
	 */
	function getTrade(uint256 tradeId) external view returns (Trade memory) {
		return TradeStorage.layout().trades[tradeId];
	}

	/**
	 * @notice Returns an array of trade IDs associated with a user address.
	 * @param user The address of user.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return tradeIds An array of trade IDs.
	 */
	function tradeIdsOf(address user, uint256 start, uint256 size) external view returns (uint256[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.tradesOf[user].length < start + size) {
			size = tradeLayout.tradesOf[user].length - start;
		}
		uint256[] memory tradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			tradeIds[i - start] = tradeLayout.tradesOf[user][i];
		}
		return tradeIds;
	}

	/**
	 * @notice Returns an array of trade IDs associated with a user address.
	 * @param user The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return trades An array of trades.
	 */
	function getTradesOf(address user, uint256 start, uint256 size) external view returns (Trade[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.tradesOf[user].length < start + size) {
			size = tradeLayout.tradesOf[user].length - start;
		}
		Trade[] memory trades = new Trade[](size);
		for (uint256 i = start; i < start + size; i++) {
			trades[i - start] = tradeLayout.trades[tradeLayout.tradesOf[user][i]];
		}
		return trades;
	}

	/**
	 * @notice Returns the length of the trade array associated with a user.
	 * @param user The address of the user.
	 * @return length The length of the trade array.
	 */
	function tradesOfLength(address user) external view returns (uint256) {
		return TradeStorage.layout().tradesOf[user].length;
	}

	/**
	 * @notice Returns an array of active trade IDs associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeTradeIds An array of trade IDs that are active.
	 */
	function activePartyATradeIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.activeTradesOf[partyA].length < start + size) {
			size = tradeLayout.activeTradesOf[partyA].length - start;
		}
		uint256[] memory activeTradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTradeIds[i - start] = tradeLayout.activeTradesOf[partyA][i];
		}
		return activeTradeIds;
	}

	/**
	 * @notice Returns an array of active trade IDs associated with a party B address and specific collateral.
	 * @param partyB The address of party B.
	 * @param collateral The address of collateral.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeTradeIds An array of trade IDs that are active.
	 */
	function activePartyBTradeIdsOf(address partyB, address collateral, uint256 start, uint256 size) external view returns (uint256[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.activeTradesOfPartyB[partyB][collateral].length < start + size) {
			size = tradeLayout.activeTradesOfPartyB[partyB][collateral].length - start;
		}
		uint256[] memory activeTradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTradeIds[i - start] = tradeLayout.activeTradesOfPartyB[partyB][collateral][i];
		}
		return activeTradeIds;
	}

	/**
	 * @notice Returns an array of active trades associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeTradeIds An array of trades that are active.
	 */
	function getActivePartyATradesOf(address partyA, uint256 start, uint256 size) external view returns (Trade[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.activeTradesOf[partyA].length < start + size) {
			size = tradeLayout.activeTradesOf[partyA].length - start;
		}
		Trade[] memory activeTrades = new Trade[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTrades[i - start] = tradeLayout.trades[tradeLayout.activeTradesOf[partyA][i]];
		}
		return activeTrades;
	}

	/**
	 * @notice Returns an array of active trades associated with a party B address and specific collateral.
	 * @param partyB The address of party B.
	 * @param collateral The address of collateral.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeTradeIds An array of trades that are active.
	 */
	function getActivePartyBTradesOf(address partyB, address collateral, uint256 start, uint256 size) external view returns (Trade[] memory) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		if (tradeLayout.activeTradesOfPartyB[partyB][collateral].length < start + size) {
			size = tradeLayout.activeTradesOfPartyB[partyB][collateral].length - start;
		}
		Trade[] memory activeTrades = new Trade[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTrades[i - start] = tradeLayout.trades[tradeLayout.activeTradesOfPartyB[partyB][collateral][i]];
		}
		return activeTrades;
	}

	/**
	 * @notice Returns the length of the active trades array associated with a party A.
	 * @param partyA The address of the party A.
	 * @return length The length of the active trades array.
	 */
	function activePartyATradesLength(address partyA) external view returns (uint256) {
		return TradeStorage.layout().activeTradesOf[partyA].length;
	}

	/**
	 * @notice Returns the length of the active trades array associated with a party B and specific collateral.
	 * @param partyB The address of the party B.
	 * @param collateral The address of collateral.
	 * @return length The length of the active trades array.
	 */
	function activePartyBTradesLength(address partyB, address collateral) external view returns (uint256) {
		return TradeStorage.layout().activeTradesOfPartyB[partyB][collateral].length;
	}

	/**
	 * @notice Returns the details of a closeIntent by its ID.
	 * @param closeIntentId The ID of the closeIntent.
	 * @return closeIntent The details of the closeIntent.
	 */
	function getCloseIntent(uint256 closeIntentId) external view returns (CloseIntent memory) {
		return CloseIntentStorage.layout().closeIntents[closeIntentId];
	}

	/**
	 * @notice Returns an array of active closeIntent IDs associated with a party A address.
	 * @param tradeId The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return closeIntentIds An array of closeIntent IDs that are active.
	 */
	function closeIntentIdsOf(uint256 tradeId, uint256 start, uint256 size) external view returns (uint256[] memory) {
		CloseIntentStorage.Layout storage intentLayout = CloseIntentStorage.layout();
		if (intentLayout.closeIntentIdsOf[tradeId].length < start + size) {
			size = intentLayout.closeIntentIdsOf[tradeId].length - start;
		}
		uint256[] memory closeIntentIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			closeIntentIds[i - start] = intentLayout.closeIntentIdsOf[tradeId][i];
		}
		return closeIntentIds;
	}

	/**
	 * @notice Returns an array of active closeIntents associated with a trade id.
	 * @param tradeId The id of the trade.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return closeIntents An array of closeIntents.
	 */
	function getCloseIntentsOf(uint256 tradeId, uint256 start, uint256 size) external view returns (CloseIntent[] memory) {
		CloseIntentStorage.Layout storage intentLayout = CloseIntentStorage.layout();
		if (intentLayout.closeIntentIdsOf[tradeId].length < start + size) {
			size = intentLayout.closeIntentIdsOf[tradeId].length - start;
		}
		CloseIntent[] memory closeIntents = new CloseIntent[](size);
		for (uint256 i = start; i < start + size; i++) {
			closeIntents[i - start] = intentLayout.closeIntents[intentLayout.closeIntentIdsOf[tradeId][i]];
		}
		return closeIntents;
	}

	/**
	 * @notice Checks if a user has a specific role.
	 * @param user The address of the user.
	 * @param role The role to check.
	 * @return True if the user has the role, false otherwise.
	 */
	function hasRole(address user, bytes32 role) external view returns (bool) {
		return AccessControlStorage.layout().hasRole[user][role];
	}

	function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
		return AccessControlStorage.layout().roleMembers[role].at(index);
	}

	function getRoleMemberCount(bytes32 role) public view returns (uint256) {
		return AccessControlStorage.layout().roleMembers[role].length();
	}

	function getRoleMembers(bytes32 role) public view returns (address[] memory) {
		return AccessControlStorage.layout().roleMembers[role].values();
	}

	/**
	 * @notice Returns the hash of a role string.
	 * @param str The role string.
	 * @return The hash of the role string.
	 */
	function getRoleHash(string memory str) external pure returns (bytes32) {
		return keccak256(abi.encodePacked(str));
	}

	function getLastWithdrawId() external view returns (uint256) {
		return AccountStorage.layout().lastWithdrawId;
	}

	function getInstantActionsModeStatus(address user) external view returns (bool) {
		return CounterPartyRelationsStorage.layout().instantActionsMode[user];
	}

	function getInstantActionsModeDeactivateTime(address user) external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().instantActionsModeDeactivateTime[user];
	}

	function getDeactiveInstantActionModeCooldown() external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().deactiveInstantActionModeCooldown;
	}

	function getBoundPartyB(address user) external view returns (address) {
		return CounterPartyRelationsStorage.layout().boundPartyB[user];
	}

	function getUnbindingRequestTime(address user) external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().unbindingRequestTime[user];
	}

	function getUnbindingCooldown() external view returns (uint256) {
		return CounterPartyRelationsStorage.layout().unbindingCooldown;
	}

	function whiteListedCollateral(address collateral) external view returns (bool) {
		return AppStorage.layout().whiteListedCollateral[collateral];
	}

	function balanceLimitPerUser(address collateral) external view returns (uint256) {
		return AppStorage.layout().balanceLimitPerUser[collateral];
	}

	function maxCloseOrdersLength() external view returns (uint256) {
		return AppStorage.layout().maxCloseOrdersLength;
	}

	function maxTradePerPartyA() external view returns (uint256) {
		return AppStorage.layout().maxTradePerPartyA;
	}

	function priceOracleAddress() external view returns (address) {
		return AppStorage.layout().priceOracleAddress;
	}

	function globalPaused() external view returns (bool) {
		return StateControlStorage.layout().globalPaused;
	}

	function depositingPaused() external view returns (bool) {
		return StateControlStorage.layout().depositingPaused;
	}

	function withdrawingPaused() external view returns (bool) {
		return StateControlStorage.layout().withdrawingPaused;
	}

	function partyBActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().partyBActionsPaused;
	}

	function partyAActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().partyAActionsPaused;
	}

	function liquidatingPaused() external view returns (bool) {
		return StateControlStorage.layout().liquidatingPaused;
	}

	function thirdPartyActionsPaused() external view returns (bool) {
		return StateControlStorage.layout().thirdPartyActionsPaused;
	}

	function internalTransferPaused() external view returns (bool) {
		return StateControlStorage.layout().internalTransferPaused;
	}

	function bridgePaused() external view returns (bool) {
		return StateControlStorage.layout().bridgePaused;
	}

	function bridgeWithdrawPaused() external view returns (bool) {
		return StateControlStorage.layout().bridgeWithdrawPaused;
	}

	function emergencyMode() external view returns (bool) {
		return StateControlStorage.layout().emergencyMode;
	}

	function partyBEmergencyStatus(address partyB) external view returns (bool) {
		return StateControlStorage.layout().partyBEmergencyStatus[partyB];
	}

	function partyADeallocateCooldown() external view returns (uint256) {
		return AppStorage.layout().partyADeallocateCooldown;
	}

	function partyBDeallocateCooldown() external view returns (uint256) {
		return AppStorage.layout().partyBDeallocateCooldown;
	}

	function forceCancelOpenIntentTimeout() external view returns (uint256) {
		return AppStorage.layout().forceCancelOpenIntentTimeout;
	}

	function forceCancelCloseIntentTimeout() external view returns (uint256) {
		return AppStorage.layout().forceCancelCloseIntentTimeout;
	}

	function ownerExclusiveWindow() external view returns (uint256) {
		return AppStorage.layout().ownerExclusiveWindow;
	}

	function defaultFeeCollector() external view returns (address) {
		return FeeManagementStorage.layout().defaultFeeCollector;
	}

	function affiliateStatus(address affiliate) external view returns (bool) {
		return FeeManagementStorage.layout().affiliateStatus[affiliate];
	}

	function affiliateFeeCollector(address affiliate) external view returns (address) {
		return FeeManagementStorage.layout().affiliateFeeCollector[affiliate];
	}

	function partyBConfigs(address partyB) external view returns (PartyBConfig memory) {
		return AppStorage.layout().partyBConfigs[partyB];
	}

	function partyBList() external view returns (address[] memory) {
		return AppStorage.layout().partyBList;
	}

	function tradeNftAddress() external view returns (address) {
		return AppStorage.layout().tradeNftAddress;
	}

	function settlementPriceSigValidTime() external view returns (uint256) {
		return AppStorage.layout().settlementPriceSigValidTime;
	}

	function version() external view returns (uint16) {
		return AppStorage.layout().version;
	}

	function getNonce(address party, address counterParty) external view returns (uint256) {
		return AccountStorage.layout().nonces[party][counterParty];
	}

	function liquidationDetail(uint256 liquidationId) external view returns (LiquidationDetail memory) {
		return LiquidationStorage.layout().liquidationDetails[liquidationId];
	}

	function liquidationDebtsToPartyAs(address partyB, address collateral, address partyA) external view returns (uint256) {
		return LiquidationStorage.layout().liquidationDebtsToPartyAs[partyB][collateral][partyA];
	}

	function involvedPartyAsCountInLiquidation(address partyB, address collateral) external view returns (uint256) {
		return LiquidationStorage.layout().involvedPartyAsCountInLiquidation[partyB][collateral];
	}

	function affiliateFees(address affiliate, uint256 symbolId) external view returns (uint256) {
		return FeeManagementStorage.layout().affiliateFees[affiliate][symbolId];
	}

	function getDefaultReleaseInterval() external view returns (uint256) {
		return AccountStorage.layout().defaultReleaseInterval;
	}

	function getConfiguredReleaseInterval(address user) external view returns (bool, uint256) {
		return (AccountStorage.layout().hasConfiguredInterval[user], AccountStorage.layout().releaseIntervals[user]);
	}
}
