// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/AccountStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/SymbolStorage.sol";

interface IViewFacet{

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

	function lockedBalancesOf(address user, address collateral) external view returns(uint256);

    function partyAStats(
		address partyA,
		address collateral
	)
		external
		view
		returns (bool, uint256, uint256, uint256[] memory, uint256[] memory, uint256[] memory);

	function getWithdraw(uint256 id) external view returns(Withdraw memory);

	function isSuspended(address user) external view returns(bool);
	

	///////////////////////////////////////////

	// Symbols
	function getSymbol(uint256 symbolId) external view returns (Symbol memory);

	function getSymbols(uint256 start, uint256 size) external view returns (Symbol[] memory);

	function symbolsByOpenIntentId(uint256[] memory openIntentIds) external view returns (Symbol[] memory);

	function symbolNameByTradeId(uint256[] memory tradeIds) external view returns (string[] memory);

	function symbolNameById(uint256[] memory symbolIds) external view returns (string[] memory);

	function getOracle(uint256 oracleId) external view returns (Oracle memory);
	
	// Intents
	function getOpenIntent(uint256 openIntentId) external view returns (OpenIntent memory);

	function getOpenIntentsByParent(uint256 openIntentId, uint256 size) external view returns (OpenIntent[] memory);

	function openIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory);

	function openIntentsLength(address user) external view returns (uint256);

	function activeOpenIntentIdsOf(address partyA, uint256 start, uint256 size) external view returns (uint256[] memory);

	function getActiveOpenIntentsOf(address partyA, uint256 start, uint256 size) external view returns (OpenIntent[] memory);

	function activeOpenIntentsLength(address user) external view returns (uint256);

	function getOpenIntentssWithBitmap(Bitmap calldata bitmap, uint256 gasNeededForReturn) external view returns (OpenIntent[] memory openIntents);

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
}