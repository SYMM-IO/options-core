// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

import "../../storages/AccountStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/SymbolStorage.sol";

contract ViewFacet/* is IViewFacet */{
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
			openIntentIds[i - start] = intentLayout.openIntentIdsOf[partyA][i];
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
	function getOpenIntents(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory) {
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


}
