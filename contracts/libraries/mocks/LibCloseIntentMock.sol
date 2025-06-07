// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../models/LibCloseIntent.sol";
import "../../storages/TradeStorage.sol";
import "../../storages/CloseIntentStorage.sol";

contract CloseIntentOpsMock {
	using LibCloseIntentOps for CloseIntent;

	// --- SETUP HELPERS ---

	function setTrade(uint256 tradeId, Trade memory trade) external {
		TradeStorage.layout().trades[tradeId] = trade;
	}

	function setCloseIntent(uint256 intentId, CloseIntent memory intent) external {
		CloseIntentStorage.layout().closeIntents[intentId] = intent;
	}

	// --- LIBRARY FUNCTION WRAPPERS ---

	function testSave(CloseIntent memory intent) external {
		intent.save(); // stores intent, mutates storage arrays
	}

	function testExpire(uint256 intentId) external {
		CloseIntent storage intent = CloseIntentStorage.layout().closeIntents[intentId];
		intent.expire();
	}

	function getCloseIntent(uint256 intentId) external view returns (CloseIntent memory) {
		return CloseIntentStorage.layout().closeIntents[intentId];
	}

	function getTrade(uint256 tradeId) external view returns (Trade memory) {
		return TradeStorage.layout().trades[tradeId];
	}

	function removeCloseIntentFromTrade(uint256 tradeId, uint256 intentId) external {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		LibCloseIntentOps.removeFromArray(trade.activeCloseIntentIds, intentId);
	}

	function getActiveCloseIntentIds(uint256 tradeId) external view returns (uint256[] memory) {
		return TradeStorage.layout().trades[tradeId].activeCloseIntentIds;
	}
}
