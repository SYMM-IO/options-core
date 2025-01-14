// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/AccountStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/SymbolStorage.sol";
import "./IViewFacet.sol";

contract ViewFacet is IViewFacet {
    /**
	 * @notice Returns the balance for a specified user and collateral type.
	 * @param user The address of the user.
     * @param collateral The address of the collateral type.
	 * @return balance The balance of the user and specic collateral type.
	 */
	function balanceOf(address user, address collateral) external view returns (uint256) {
		return AccountStorage.layout().balances[user][collateral];
	}


	/**
	 * @notice Returns the locked balance for a specific user and collateral type.
	 * @param user The address of the user.
	 * @param collateral The address of the collateral type.
	 * @return lockedBalances The locked balance of the user and specic collateral type.
	 */
	function lockedBalancesOf(address user, address collateral) external view returns(uint256){
		return AccountStorage.layout().lockedBalances[user][collateral];
	}

    /**
	 * @notice Returns various values related to Party A.
	 * @param partyA The address of Party A.
	 // TODO 1, return liquidationStatus The liquidation status of Party A.
	 * @return suspendedAddresses returns a true/false representing whether the given address is suspended or not.
	 * @return balance The balance of Party A.
	 * @return lockedBalance The locked balance of Party A and specific collateral.
	 * @return withdrawIds The list of withdrawIds of Party A.
	 * @return openIntentsOf The list of openIntents of Party A.
	 * @return tradesOf The list of trades of Party A.
	 */
	function partyAStats(
		address partyA,
		address collateral
	)
		external
		view
		returns (bool, uint256, uint256, uint256[] memory, uint256[] memory, uint256[] memory)
	{
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		// MAStorage.Layout storage maLayout = MAStorage.layout();  #TODO 1: consider adding this after liquidation dev.
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		return (
			// maLayout.liquidationStatus[partyA], #TODO 1
			accountLayout.suspendedAddresses[partyA],
			accountLayout.balances[partyA][collateral],
			accountLayout.lockedBalances[partyA][collateral],
			accountLayout.withdrawIds[partyA],
			//TODO 2: consider adding AppStorage:partyAReimbursement after it's used 
			intentLayout.openIntentsOf[partyA],
			intentLayout.tradesOf[partyA]
			// intentLayout.closeIntentIdsOf TODO 3: consider adding this if it's necessary
		);
	}

	/**
	 * @notice Returns the Withdraw object. You can read Withdraw object attributes at AccountFact:Withdraw
	 * @param id The id of the Withdraw object.
	 * @return Withdraw The Withdraw object associated with the given `id`.
	 */
	function getWithdraw(uint256 id) external view returns(Withdraw memory){
		return AccountStorage.layout().withdraws[id];
	}

	/**
	 @notice Checks whether the user is suspned or not.
	 @param user The address of the user.
	 @return isSuspended A boolean value(true/false) to show that the `user` is suspended or not.
	 */
	function isSuspended(address user) external view returns(bool){
		return AccountStorage.layout().suspendedAddresses[user];
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
	 * @notice Returns an array of symbols associated with an array of openIntent IDs.
	 * @param openIntentIds An array of openIntent IDs.
	 * @return symbols An array of symbols.
	 */
	function symbolsByOpenIntentId(uint256[] memory openIntentIds) external view returns (Symbol[] memory) {
		Symbol[] memory symbols = new Symbol[](openIntentIds.length);
		for (uint256 i = 0; i < openIntentIds.length; i++) {
			symbols[i] = SymbolStorage.layout().symbols[IntentStorage.layout().openIntents[openIntentIds[i]].symbolId];
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
			symbols[i] = SymbolStorage.layout().symbols[IntentStorage.layout().trades[tradeIds[i]].symbolId].name;
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
	 * @notice Returns the details of a openIntent by its ID.
	 * @param openIntentId The ID of the openIntent.
	 * @return openIntent The details of the openIntent.
	 */
	function getOpenIntent(uint256 openIntentId) external view returns (OpenIntent memory) {
		return IntentStorage.layout().openIntents[openIntentId];
	}

	/**
	 * @notice Returns an array of openIntents associated with a parent openIntent ID.
	 * @param openIntentId The parent openIntent ID.
	 * @param size The size of the array.
	 * @return openIntents An array of openIntents.
	 */
	function getOpenIntentsByParent(uint256 openIntentId, uint256 size) external view returns (OpenIntent[] memory) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		return IntentStorage.layout().openIntentsOf[user].length;
	}

	/**
	 * @notice Returns an array of active openIntent IDs associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeOpenIntentIds An array of openIntent IDs that are active.
	 */
	function activeOpenIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		return IntentStorage.layout().activeOpenIntentsOf[user].length;
	}

	/**
	 * @notice Retrieves a filtered list of openIntents based on a bitmap. The method returns openIntents only if sufficient gas remains.
	 * @param bitmap A structured data type representing a bitmap, used to indicate which openIntents to retrieve based on their positions. The bitmap consists of multiple elements, each with an offset and a 256-bit integer representing selectable openIntents.
	 * @param gasNeededForReturn The minimum gas required to complete the function execution and return the data. This ensures the function doesn't start a retrieval that it can't complete.
	 * @return openIntents An array of `OpenIntent` structures, each corresponding to a openIntent identified by the bitmap.
	 */
	function getOpenIntentssWithBitmap(Bitmap calldata bitmap, uint256 gasNeededForReturn) external view returns (OpenIntent[] memory openIntents) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

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
		return IntentStorage.layout().trades[tradeId];
	}

	/**
	 * @notice Returns an array of trade IDs associated with a user address.
	 * @param user The address of user.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return tradeIds An array of trade IDs.
	 */
	function tradeIdsOf(address user, uint256 start, uint256 size) external view returns (uint256[] memory) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.tradesOf[user].length < start + size) {
			size = intentLayout.tradesOf[user].length - start;
		}
		uint256[] memory tradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			tradeIds[i - start] = intentLayout.tradesOf[user][i];
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
	function getTradesOf(address user, uint256 start, uint256 size) external view returns (Trade[] memory){
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.tradesOf[partyA].length < start + size) {
			size = intentLayout.tradesOf[partyA].length - start;
		}
		Trade[] memory trades = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			trades[i - start] = intentLayout.trades[intentLayout.tradesOf[partyA][i]];
		}
		return trades;
	}

	/**
	 * @notice Returns the length of the trade array associated with a user.
	 * @param user The address of the user.
	 * @return length The length of the trade array.
	 */
	function tradesOfLength(address user) external view returns (uint256) {
		return IntentStorage.layout().tradesOf[user].length;
	}

	/**
	 * @notice Returns an array of active trade IDs associated with a party A address.
	 * @param partyA The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return activeTradeIds An array of trade IDs that are active.
	 */
	function activePartyATradeIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.activeTradesOf[partyA].length < start + size) {
			size = intentLayout.activeTradesOf[partyA].length - start;
		}
		uint256[] memory activeTradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTradeIds[i - start] = intentLayout.activeTradesOf[partyA][i];
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.activeTradesOfPartyB[partyB][collateral].length < start + size) {
			size = intentLayout.activeTradesOf[partyB][collateral].length - start;
		}
		uint256[] memory activeTradeIds = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTradeIds[i - start] = intentLayout.activeTradesOf[partyB][collateral][i];
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.activeTradesOf[partyA].length < start + size) {
			size = intentLayout.activeTradesOf[partyA].length - start;
		}
		Trade[] memory activeTrades = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTrades[i - start] = intentLayout.trades[intentLayout.activeTradesOf[partyA][i]];
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.activeTradesOfPartyB[partyB][collateral].length < start + size) {
			size = intentLayout.activeTradesOfPartyB[partyB].length - start;
		}
		Trade[] memory activeTrades = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			activeTrades[i - start] = intentLayout.trades[intentLayout.activeTradesOfPartyB[partyA][collateral][i]];
		}
		return activeTrades;
	}

	/**
	 * @notice Returns the length of the active trades array associated with a party A.
	 * @param partyA The address of the party A.
	 * @return length The length of the active trades array.
	 */
	function activePartyATradesLength(address partyA) external view returns (uint256) {
		return IntentStorage.layout().activeTradesOf[partyA].length;
	}

	/**
	 * @notice Returns the length of the active trades array associated with a party B and specific collateral.
	 * @param partyB The address of the party B.
	 * @param collateral The address of collateral.
	 * @return length The length of the active trades array.
	 */
	function activePartyBTradesLength(address partyB, address collateral) external view returns (uint256) {
		return IntentStorage.layout().activeTradesOfPartyB[partyB][collateral].length;
	}

	/**
	 * @notice Returns the details of a closeIntent by its ID.
	 * @param closeIntentId The ID of the closeIntent.
	 * @return closeIntent The details of the closeIntent.
	 */
	function getCloseIntent(uint256 closeIntentId) external view returns (CloseIntent memory) {
		return IntentStorage.layout().closeIntents[closeIntentId];
	}

	/**
	 * @notice Returns an array of active closeIntent IDs associated with a party A address.
	 * @param tradeId The address of party A.
	 * @param start The starting index.
	 * @param size The size of the array.
	 * @return closeIntentIds An array of closeIntent IDs that are active.
	 */
	function closeIntentIdsOf(uint256 tradeId, uint256 start, uint256 size) external view returns (uint256[] memory) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		if (intentLayout.closeIntentIdsOf[tradeId].length < start + size) {
			size = intentLayout.closeIntentIdsOf[tradeId].length - start;
		}
		CloseIntent[] memory closeIntents = new uint256[](size);
		for (uint256 i = start; i < start + size; i++) {
			closeIntents[i - start] = intentLayout.closeIntents[intentLayout.closeIntentIdsOf[tradeId][i]];
		}
		return closeIntents;
	}
}
