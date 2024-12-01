// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/AppStorage.sol";
import "../storages/SymbolStorage.sol";

library LibIntent {
    function getAvailableAmountToClose(
        uint256 tradeId
    ) internal view returns (uint256) {
        Trade storage trade = IntentStorage.layout().trades[tradeId];
        return trade.quantity - trade.closedAmount - trade.closePendingAmount;
    }

    function getPremiumOfOpenIntent(
        uint256 intentId
    ) internal view returns (uint256) {
        OpenIntent storage intent = IntentStorage.layout().openIntents[
            intentId
        ];
        return (intent.quantity * intent.price) / 1e18;
    }

    /**
     * @notice Adds a intent to the open intents of partyA.
     * @param intentId The ID of the intent to add to the open intents.
     */
    function addToPartyAOpenIntents(uint256 intentId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        OpenIntent storage intent = intentLayout.openIntents[intentId];

        intentLayout.activeOpenIntentsOf[intent.partyA].push(intent.id);
        intentLayout.partyAOpenIntentsIndex[intent.id] =
            intentLayout.activeOpenIntentsOf[intent.partyA].length -
            1;
    }

    /**
     * @notice Adds a intent to the open intents of partyB.
     * @param intentId The ID of the intent to add to the open intents.
     */
    function addToPartyBOpenIntents(uint256 intentId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        OpenIntent storage intent = intentLayout.openIntents[intentId];

        intentLayout.activeOpenIntentsOf[intent.partyB].push(intent.id);
        intentLayout.partyBOpenIntentsIndex[intent.id] =
            intentLayout.activeOpenIntentsOf[intent.partyB].length -
            1;
    }

    /**
     * @notice Removes a intent from the open intents of partyA.
     * @param intentId The ID of the intent to remove from the open positions.
     */
    function removeFromPartyAOpenIntents(uint256 intentId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        OpenIntent storage intent = intentLayout.openIntents[intentId];
        uint256 indexOfIntent = intentLayout.partyAOpenIntentsIndex[intent.id];
        uint256 lastIndex = intentLayout
            .activeOpenIntentsOf[intent.partyA]
            .length - 1;
        intentLayout.activeOpenIntentsOf[intent.partyA][
            indexOfIntent
        ] = intentLayout.activeOpenIntentsOf[intent.partyA][lastIndex];
        intentLayout.partyAOpenIntentsIndex[
            intentLayout.activeOpenIntentsOf[intent.partyA][lastIndex]
        ] = indexOfIntent;
        intentLayout.activeOpenIntentsOf[intent.partyA].pop();

        intentLayout.partyAOpenIntentsIndex[intent.id] = 0;
    }

    /**
     * @notice Removes a intent from the open intents of partyB.
     * @param intentId The ID of the intent to remove from the open positions.
     */
    function removeFromPartyBOpenIntents(uint256 intentId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        OpenIntent storage intent = intentLayout.openIntents[intentId];
        uint256 indexOfIntent = intentLayout.partyBOpenIntentsIndex[intent.id];
        uint256 lastIndex = intentLayout
            .activeOpenIntentsOf[intent.partyB]
            .length - 1;
        intentLayout.activeOpenIntentsOf[intent.partyB][
            indexOfIntent
        ] = intentLayout.activeOpenIntentsOf[intent.partyB][lastIndex];
        intentLayout.partyBOpenIntentsIndex[
            intentLayout.activeOpenIntentsOf[intent.partyB][lastIndex]
        ] = indexOfIntent;
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

        intentLayout.tradesOf[trade.partyA].push(trade.id);
        intentLayout.tradesOf[trade.partyB].push(trade.id);
        intentLayout.activeTradesOf[trade.partyA].push(trade.id);
        intentLayout.activeTradesOf[trade.partyB].push(trade.id);

        intentLayout.partyATradesIndex[trade.id] =
            intentLayout.activeTradesOf[trade.partyA].length -
            1;
        intentLayout.partyBTradesIndex[trade.id] =
            intentLayout.activeTradesOf[trade.partyB].length -
            1;
    }

    /**
     * @notice Removes a trade from the active trades.
     * @param tradeId The ID of the trade to remove from the active trades.
     */
    function removeFromActiveTrades(uint256 tradeId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        Trade storage trade = intentLayout.trades[tradeId];
        uint256 indexOfPartyATrade = intentLayout.partyATradesIndex[trade.id];
        uint256 indexOfPartyBTrade = intentLayout.partyBTradesIndex[trade.id];
        uint256 lastIndex = intentLayout.activeTradesOf[trade.partyA].length -
            1;
        intentLayout.activeTradesOf[trade.partyA][
            indexOfPartyATrade
        ] = intentLayout.activeTradesOf[trade.partyA][lastIndex];
        intentLayout.partyATradesIndex[
            intentLayout.activeTradesOf[trade.partyA][lastIndex]
        ] = indexOfPartyATrade;
        intentLayout.activeTradesOf[trade.partyA].pop();

        lastIndex = intentLayout.activeTradesOf[trade.partyB].length - 1;
        intentLayout.activeTradesOf[trade.partyB][
            indexOfPartyBTrade
        ] = intentLayout.activeTradesOf[trade.partyB][lastIndex];
        intentLayout.partyBTradesIndex[
            intentLayout.activeTradesOf[trade.partyB][lastIndex]
        ] = indexOfPartyBTrade;
        intentLayout.activeTradesOf[trade.partyB].pop();

        intentLayout.partyATradesIndex[trade.id] = 0;
        intentLayout.partyBTradesIndex[trade.id] = 0;
    }

    // /**
    //  * @notice Calculates the value of a intent for Party A based on the current price and filled amount.
    //  * @param currentPrice The current price of the intent.
    //  * @param filledAmount The filled amount of the intent.
    //  * @param intent The intent for which to calculate the value.
    //  * @return hasMadeProfit A boolean indicating whether Party A has made a profit.
    //  * @return pnl The profit or loss value for Party A.
    //  */
    // function getValueOfIntentForPartyA(
    //     uint256 currentPrice,
    //     uint256 filledAmount,
    //     Intent storage intent
    // ) internal view returns (bool hasMadeProfit, uint256 pnl) {
    //     if (currentPrice > intent.openedPrice) {
    //         if (intent.positionType == PositionType.LONG) {
    //             hasMadeProfit = true;
    //         } else {
    //             hasMadeProfit = false;
    //         }
    //         pnl = ((currentPrice - intent.openedPrice) * filledAmount) / 1e18;
    //     } else {
    //         if (intent.positionType == PositionType.LONG) {
    //             hasMadeProfit = false;
    //         } else {
    //             hasMadeProfit = true;
    //         }
    //         pnl = ((intent.openedPrice - currentPrice) * filledAmount) / 1e18;
    //     }
    // }

    /**
     * @notice Gets the trading fee for a intent.
     * @param intentId The ID of the intent for which to get the trading fee.
     * @return fee The trading fee for the intent.
     */
    function getTradingFee(
        uint256 intentId
    ) internal view returns (uint256 fee) {
        OpenIntent storage intent = IntentStorage.layout().openIntents[
            intentId
        ];
        fee = (intent.quantity * intent.price * intent.tradingFee) / 1e36;
    }

    // /**
    //  * @notice Closes a intent.
    //  * @param intent The intent to close.
    //  * @param filledAmount The filled amount of the intent.
    //  * @param closedPrice The price at which the intent is closed.
    //  */
    // function closeIntent(Intent storage intent, uint256 filledAmount, uint256 closedPrice) internal {
    // 	IntentStorage.Layout storage intentLayout = IntentStorage.layout();
    // 	AccountStorage.Layout storage accountLayout = AccountStorage.layout();
    // 	SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

    // 	require(
    // 		intent.lockedValues.cva == 0 || (intent.lockedValues.cva * filledAmount) / LibIntent.intentOpenAmount(intent) > 0,
    // 		"LibIntent: Low filled amount"
    // 	);
    // 	require(
    // 		intent.lockedValues.partyAmm == 0 || (intent.lockedValues.partyAmm * filledAmount) / LibIntent.intentOpenAmount(intent) > 0,
    // 		"LibIntent: Low filled amount"
    // 	);
    // 	require(
    // 		intent.lockedValues.partyBmm == 0 || (intent.lockedValues.partyBmm * filledAmount) / LibIntent.intentOpenAmount(intent) > 0,
    // 		"LibIntent: Low filled amount"
    // 	);
    // 	require((intent.lockedValues.lf * filledAmount) / LibIntent.intentOpenAmount(intent) > 0, "LibIntent: Low filled amount");
    // 	LockedValues memory lockedValues = LockedValues(
    // 		intent.lockedValues.cva - ((intent.lockedValues.cva * filledAmount) / (LibIntent.intentOpenAmount(intent))),
    // 		intent.lockedValues.lf - ((intent.lockedValues.lf * filledAmount) / (LibIntent.intentOpenAmount(intent))),
    // 		intent.lockedValues.partyAmm - ((intent.lockedValues.partyAmm * filledAmount) / (LibIntent.intentOpenAmount(intent))),
    // 		intent.lockedValues.partyBmm - ((intent.lockedValues.partyBmm * filledAmount) / (LibIntent.intentOpenAmount(intent)))
    // 	);
    // 	accountLayout.lockedBalances[intent.partyA].subIntent(intent).add(lockedValues);
    // 	accountLayout.partyBLockedBalances[intent.partyB][intent.partyA].subIntent(intent).add(lockedValues);
    // 	intent.lockedValues = lockedValues;

    // 	if (LibIntent.intentOpenAmount(intent) == intent.quantityToClose) {
    // 		require(
    // 			intent.lockedValues.totalForPartyA() == 0 ||
    // 				intent.lockedValues.totalForPartyA() >= symbolLayout.symbols[intent.symbolId].minAcceptableIntentValue,
    // 			"LibIntent: Remaining intent value is low"
    // 		);
    // 	}

    // 	chargeAccumulatedFundingFee(intent.id);

    // 	(bool hasMadeProfit, uint256 pnl) = LibIntent.getValueOfIntentForPartyA(closedPrice, filledAmount, intent);

    // 	if (hasMadeProfit) {
    // 		require(
    // 			accountLayout.partyBAllocatedBalances[intent.partyB][intent.partyA] >= pnl,
    // 			"LibIntent: PartyA should first exit its positions that are incurring losses"
    // 		);
    // 		accountLayout.allocatedBalances[intent.partyA] += pnl;
    // 		emit SharedEvents.BalanceChangePartyA(intent.partyA, pnl, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
    // 		accountLayout.partyBAllocatedBalances[intent.partyB][intent.partyA] -= pnl;
    // 		emit SharedEvents.BalanceChangePartyB(intent.partyB, intent.partyA, pnl, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
    // 	} else {
    // 		require(
    // 			accountLayout.allocatedBalances[intent.partyA] >= pnl,
    // 			"LibIntent: PartyA should first exit its positions that are currently in profit."
    // 		);
    // 		accountLayout.allocatedBalances[intent.partyA] -= pnl;
    // 		emit SharedEvents.BalanceChangePartyA(intent.partyA, pnl, SharedEvents.BalanceChangeType.REALIZED_PNL_OUT);
    // 		accountLayout.partyBAllocatedBalances[intent.partyB][intent.partyA] += pnl;
    // 		emit SharedEvents.BalanceChangePartyB(intent.partyB, intent.partyA, pnl, SharedEvents.BalanceChangeType.REALIZED_PNL_IN);
    // 	}

    // 	intent.avgClosedPrice = (intent.avgClosedPrice * intent.closedAmount + filledAmount * closedPrice) / (intent.closedAmount + filledAmount);

    // 	intent.closedAmount += filledAmount;
    // 	intent.quantityToClose -= filledAmount;

    // 	if (intent.closedAmount == intent.quantity) {
    // 		intent.statusModifyTimestamp = block.timestamp;
    // 		intent.status = IntentStatus.CLOSED;
    // 		intent.requestedClosePrice = 0;
    // 		removeFromOpenPositions(intent.id);
    // 	} else if (intent.status == IntentStatus.CANCEL_CLOSE_PENDING || intent.quantityToClose == 0) {
    // 		intent.status = IntentStatus.OPENED;
    // 		intent.statusModifyTimestamp = block.timestamp;
    // 		intent.requestedClosePrice = 0;
    // 		intent.quantityToClose = 0; // for CANCEL_CLOSE_PENDING status
    // 	}
    // 	if (
    // 		intentLayout.partyBPendingIntents[intent.partyB][intent.partyA].length == 0 &&
    // 		intentLayout.partyBPositionsCount[intent.partyB][intent.partyA] == 0
    // 	) {
    // 		accountLayout.connectedPartyBCount[intent.partyA] -= 1;
    // 	}
    // }

    /**
     * @notice Gets the index of an item in an array.
     * @param array_ The array in which to search for the item.
     * @param item The item to find the index of.
     * @return The index of the item in the array, or type(uint256).max if the item is not found.
     */
    function getIndexOfItem(
        uint256[] storage array_,
        uint256 item
    ) internal view returns (uint256) {
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

        removeFromArray(trade.closeIntentIds, intentId);

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
        require(
            block.timestamp > intent.deadline,
            "LibIntent: Intent isn't expired"
        );
        require(
            intent.status == IntentStatus.PENDING ||
                intent.status == IntentStatus.CANCEL_PENDING ||
                intent.status == IntentStatus.LOCKED,
            "LibIntent: Invalid state"
        );
        intent.statusModifyTimestamp = block.timestamp;
        accountLayout.lockedBalances[intent.partyA] -= getPremiumOfOpenIntent(
            intentId
        );

        // send trading Fee back to partyA
        uint256 fee = getTradingFee(intent.id);
        accountLayout.balances[intent.partyA] += fee;

        removeFromPartyAOpenIntents(intent.id);
        if (
            intent.status == IntentStatus.LOCKED ||
            intent.status == IntentStatus.CANCEL_PENDING
        ) {
            removeFromPartyBOpenIntents(intent.id);
        }
        intent.status = IntentStatus.EXPIRED;
    }

    function expireCloseIntent(uint256 intentId) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        CloseIntent storage intent = intentLayout.closeIntents[intentId];

        require(
            block.timestamp > intent.deadline,
            "LibIntent: Intent isn't expired"
        );
        require(
            intent.status == IntentStatus.PENDING ||
                intent.status == IntentStatus.CANCEL_PENDING,
            "LibIntent: Invalid state"
        );

        intent.statusModifyTimestamp = block.timestamp;
        intent.status = IntentStatus.EXPIRED;
        removeFromActiveCloseIntents(intentId);
    }
}
