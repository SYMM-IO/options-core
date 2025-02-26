// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/AppStorage.sol";
import "../storages/SymbolStorage.sol";
import "../interfaces/IPriceOracle.sol";

library LibIntent {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function tradeOpenAmount(Trade storage trade) internal view returns (uint256) {
		return trade.quantity - trade.closedAmountBeforeExpiration;
	}

	function getAvailableAmountToClose(uint256 tradeId) internal view returns (uint256) {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		return trade.quantity - trade.closedAmountBeforeExpiration - trade.closePendingAmount;
	}

	function getPremiumOfOpenIntent(uint256 intentId) internal view returns (uint256) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		return (intent.quantity * intent.price) / 1e18;
	}

	function getValueOfTradeForPartyA(uint256 currentPrice, uint256 filledAmount, Trade storage trade) internal view returns (uint256 pnl) {
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];

		if (currentPrice > trade.strikePrice && symbol.optionType == OptionType.CALL) {
			pnl = ((currentPrice - trade.strikePrice) * filledAmount) / 1e18;
		} else if (currentPrice < trade.strikePrice && symbol.optionType == OptionType.PUT) {
			pnl = ((trade.strikePrice - currentPrice) * filledAmount) / 1e18;
		}
	}

	/**
	 * @notice Adds a intent to the open intents of partyA.
	 * @param intentId The ID of the intent to add to the open intents.
	 */
	function addToPartyAOpenIntents(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.symbolId];

		intentLayout.activeOpenIntentsOf[intent.partyA].push(intent.id);
		intentLayout.activeOpenIntentsCount[intent.partyA] += 1;
		intentLayout.partyAOpenIntentsIndex[intent.id] = intentLayout.activeOpenIntentsOf[intent.partyA].length - 1;
		if (intentLayout.activeOpenIntentsCount[intent.partyA] == 1) {
			AccountStorage.layout().balances[intent.partyA][symbol.collateral].addPartyB(intent.partyB, block.timestamp);
		}
	}

	/**
	 * @notice Adds a intent to the open intents of partyB.
	 * @param intentId The ID of the intent to add to the open intents.
	 */
	function addToPartyBOpenIntents(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		intentLayout.activeOpenIntentsOf[intent.partyB].push(intent.id);
		intentLayout.partyBOpenIntentsIndex[intent.id] = intentLayout.activeOpenIntentsOf[intent.partyB].length - 1;
	}

	/**
	 * @notice Removes a intent from the open intents of partyA.
	 * @param intentId The ID of the intent to remove from the open positions.
	 */
	function removeFromPartyAOpenIntents(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.symbolId];

		uint256 indexOfIntent = intentLayout.partyAOpenIntentsIndex[intent.id];
		uint256 lastIndex = intentLayout.activeOpenIntentsOf[intent.partyA].length - 1;
		intentLayout.activeOpenIntentsOf[intent.partyA][indexOfIntent] = intentLayout.activeOpenIntentsOf[intent.partyA][lastIndex];
		intentLayout.partyAOpenIntentsIndex[intentLayout.activeOpenIntentsOf[intent.partyA][lastIndex]] = indexOfIntent;
		intentLayout.activeOpenIntentsOf[intent.partyA].pop();

		intentLayout.partyAOpenIntentsIndex[intent.id] = 0;

		intentLayout.activeOpenIntentsCount[intent.partyA] -= 1;
		if (intentLayout.activeOpenIntentsCount[intent.partyA] == 0) {
			AccountStorage.layout().balances[intent.partyA][symbol.collateral].removePartyB(intent.partyB);
		}
	}

	/**
	 * @notice Removes a intent from the open intents of partyB.
	 * @param intentId The ID of the intent to remove from the open positions.
	 */
	function removeFromPartyBOpenIntents(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];
		uint256 indexOfIntent = intentLayout.partyBOpenIntentsIndex[intent.id];
		uint256 lastIndex = intentLayout.activeOpenIntentsOf[intent.partyB].length - 1;
		intentLayout.activeOpenIntentsOf[intent.partyB][indexOfIntent] = intentLayout.activeOpenIntentsOf[intent.partyB][lastIndex];
		intentLayout.partyBOpenIntentsIndex[intentLayout.activeOpenIntentsOf[intent.partyB][lastIndex]] = indexOfIntent;
		intentLayout.activeOpenIntentsOf[intent.partyB].pop();

		intentLayout.partyBOpenIntentsIndex[intent.id] = 0;
	}

	/**
	 * @notice Adds a intent to the open positions.
	 * @param tradeId The ID of the intent to add to the open positions.
	 */
	function addToActiveTrades(uint256 tradeId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];
		intentLayout.tradesOf[trade.partyA].push(trade.id);
		intentLayout.tradesOf[trade.partyB].push(trade.id);
		intentLayout.activeTradesOf[trade.partyA].push(trade.id);
		intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral].push(trade.id);

		intentLayout.partyATradesIndex[trade.id] = intentLayout.activeTradesOf[trade.partyA].length - 1;
		intentLayout.partyBTradesIndex[trade.id] = intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral].length - 1;
	}

	/**
	 * @notice Removes a trade from the active trades.
	 * @param tradeId The ID of the trade to remove from the active trades.
	 */
	function removeFromActiveTrades(uint256 tradeId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];

		uint256 indexOfPartyATrade = intentLayout.partyATradesIndex[trade.id];
		uint256 indexOfPartyBTrade = intentLayout.partyBTradesIndex[trade.id];
		uint256 lastIndex = intentLayout.activeTradesOf[trade.partyA].length - 1;
		intentLayout.activeTradesOf[trade.partyA][indexOfPartyATrade] = intentLayout.activeTradesOf[trade.partyA][lastIndex];
		intentLayout.partyATradesIndex[intentLayout.activeTradesOf[trade.partyA][lastIndex]] = indexOfPartyATrade;
		intentLayout.activeTradesOf[trade.partyA].pop();

		lastIndex = intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral].length - 1;
		intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral][indexOfPartyBTrade] = intentLayout.activeTradesOfPartyB[trade.partyB][
			symbol.collateral
		][lastIndex];
		intentLayout.partyBTradesIndex[intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral][lastIndex]] = indexOfPartyBTrade;
		intentLayout.activeTradesOfPartyB[trade.partyB][symbol.collateral].pop();

		intentLayout.partyATradesIndex[trade.id] = 0;
		intentLayout.partyBTradesIndex[trade.id] = 0;
	}

	/**
	 * @notice Gets the trading fee for a intent.
	 * @param intentId The ID of the intent for which to get the trading fee.
	 * @return fee The trading fee for the intent.
	 */
	function getTradingFee(uint256 intentId) internal view returns (uint256 fee) {
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		fee = (intent.quantity * intent.price * intent.tradingFee.fee) / (intent.tradingFee.tokenPrice * 1e18);
	}

	/**
	 * @notice Gets the index of an item in an array.
	 * @param array_ The array in which to search for the item.
	 * @param item The item to find the index of.
	 * @return The index of the item in the array, or type(uint256).max if the item is not found.
	 */
	function getIndexOfItem(uint256[] storage array_, uint256 item) internal view returns (uint256) {
		for (uint256 index = 0; index < array_.length; index++) {
			if (array_[index] == item) return index;
		}
		return type(uint256).max;
	}

	/**
	 * @notice Removes an item from an array.
	 * @param array_ The array from which to remove the item.
	 * @param item The item to remove from the array.
	 */
	function removeFromArray(uint256[] storage array_, uint256 item) internal {
		uint256 index = getIndexOfItem(array_, item);
		require(index != type(uint256).max, "LibIntent: Item not Found");
		array_[index] = array_[array_.length - 1];
		array_.pop();
	}

	function removeFromActiveCloseIntents(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];

		removeFromArray(trade.activeCloseIntentIds, intentId);

		trade.closePendingAmount -= intent.quantity;
	}

	/**
	 * @notice Expires a open intent.
	 * @param intentId The ID of the open intent to expire.
	 */
	function expireOpenIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];
		require(block.timestamp > intent.deadline, "LibIntent: Intent isn't expired");
		require(
			intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING || intent.status == IntentStatus.LOCKED,
			"LibIntent: Invalid state"
		);
		intent.statusModifyTimestamp = block.timestamp;
		accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= getPremiumOfOpenIntent(intentId);

		// send trading Fee back to partyA
		uint256 fee = getTradingFee(intent.id);
		if (intent.partyBsWhiteList.length == 1) {
			accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].scheduledAdd(intent.partyBsWhiteList[0], fee, block.timestamp);
		} else {
			accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].instantAdd(intent.tradingFee.feeToken, fee);
		}

		removeFromPartyAOpenIntents(intent.id);
		if (intent.status == IntentStatus.LOCKED || intent.status == IntentStatus.CANCEL_PENDING) {
			removeFromPartyBOpenIntents(intent.id);
		}
		intent.status = IntentStatus.EXPIRED;
	}

	function expireCloseIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];

		require(block.timestamp > intent.deadline, "LibIntent: Intent isn't expired");
		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING, "LibIntent: Invalid state");

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.EXPIRED;
		removeFromActiveCloseIntents(intentId);
	}

	function closeTrade(uint256 tradeId, TradeStatus tradeStatus, IntentStatus intentStatus) internal {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		uint256 len = trade.activeCloseIntentIds.length;
		for (uint8 i = 0; i < len; i++) {
			CloseIntent storage intent = IntentStorage.layout().closeIntents[trade.activeCloseIntentIds[0]];
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = intentStatus;
			removeFromActiveCloseIntents(intent.id);
		}
		trade.status = tradeStatus;
		trade.statusModifyTimestamp = block.timestamp;
		removeFromActiveTrades(tradeId);
	}

	function hashSignedOpenIntent(SignedOpenIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioOpenIntent_v1");

		return
			keccak256(
				abi.encode(
					SIGN_PREFIX,
					req.partyA,
					req.partyB,
					req.symbolId,
					req.price,
					req.quantity,
					req.strikePrice,
					req.expirationTimestamp,
					req.exerciseFee.rate,
					req.exerciseFee.cap,
					req.deadline,
					req.feeToken,
					req.affiliate,
					req.salt
				)
			);
	}

	function hashSignedCloseIntent(SignedCloseIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyA, req.tradeId, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillOpenIntent(SignedFillIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillOpenIntentById(SignedFillIntentById calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntentById_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillCloseIntent(SignedFillIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillCloseIntentById(SignedFillIntentById calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntentById_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedCancelOpenIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedAcceptCancelOpenIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedCancelCloseIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedAcceptCancelCloseIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedLockIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioLockIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedUnlockIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioUnlockIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}
}
