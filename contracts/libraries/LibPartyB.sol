// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AppStorage.sol";
import "./LibIntent.sol";

library LibPartyB {
    function fillOpenIntent(
        uint256 intentId,
        uint256 quantity,
        uint256 price
    ) internal returns (uint256 newIntentId) {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        AppStorage.Layout storage appLayout = AppStorage.layout();

        OpenIntent storage intent = intentLayout.openIntents[intentId];
        require(
            SymbolStorage.layout().symbols[intent.symbolId].isValid,
            "PartyBFacet: Symbol is not valid"
        );
        require(
            intent.status == IntentStatus.LOCKED ||
                intent.status == IntentStatus.CANCEL_PENDING,
            "PartyBFacet: Invalid state"
        );
        require(
            block.timestamp <= intent.deadline,
            "PartyBFacet: Intent is expired"
        );

        require(
            block.timestamp <= intent.expirationTimestamp,
            "PartyBFacet: Requested expiration has been passed"
        );

        address feeCollector = appLayout.affiliateFeeCollector[
            intent.affiliate
        ] == address(0)
            ? appLayout.defaultFeeCollector
            : appLayout.affiliateFeeCollector[intent.affiliate];

        require(
            intent.quantity >= quantity && quantity > 0,
            "PartyBFacet: Invalid quantity"
        );
        accountLayout.balances[feeCollector] +=
            (quantity * intent.price * intent.tradingFee) /
            1e36;

        require(price <= intent.price, "PartyBFacet: Opened price isn't valid");

        uint256 tradeId = ++intentLayout.lastTradeId;
        Trade memory trade = Trade({
            id: tradeId,
            openIntentId: intentId,
            activeCloseIntentIds: new uint256[](0),
            symbolId: intent.symbolId,
            quantity: quantity,
            strikePrice: intent.strikePrice,
            expirationTimestamp: intent.expirationTimestamp,
            partyA: intent.partyA,
            partyB: intent.partyB,
            openedPrice: price,
            closedAmount: 0,
            closePendingAmount: 0,
            avgClosedPrice: 0,
            status: TradeStatus.OPENED,
            createTimestamp: block.timestamp,
            statusModifyTimestamp: block.timestamp
        });

        intent.tradeId = tradeId;
        intent.status = IntentStatus.FILLED;
        intent.statusModifyTimestamp = block.timestamp;

        LibIntent.removeFromPartyAOpenIntents(intentId);
        LibIntent.removeFromPartyBOpenIntents(intentId);

        accountLayout.lockedBalances[intent.partyA] -= LibIntent
            .getPremiumOfOpenIntent(intentId);

        // partially fill
        if (intent.quantity >= quantity) {
            newIntentId = ++intentLayout.lastOpenIntentId;
            IntentStatus newStatus;
            if (intent.status == IntentStatus.CANCEL_PENDING) {
                newStatus = IntentStatus.CANCELED;
            } else {
                newStatus = IntentStatus.PENDING;
            }

            OpenIntent memory q = OpenIntent({
                id: newIntentId,
                tradeId: 0,
                partyBsWhiteList: intent.partyBsWhiteList,
                symbolId: intent.symbolId,
                price: intent.price,
                quantity: intent.quantity - quantity,
                strikePrice: intent.strikePrice,
                expirationTimestamp: intent.expirationTimestamp,
                partyA: intent.partyA,
                partyB: address(0),
                status: newStatus,
                parentId: intent.id,
                createTimestamp: block.timestamp,
                statusModifyTimestamp: block.timestamp,
                deadline: intent.deadline,
                tradingFee: intent.tradingFee,
                affiliate: intent.affiliate
            });

            intentLayout.openIntents[newIntentId] = q;
            intentLayout.openIntentsOf[intent.partyA].push(newIntentId);
            LibIntent.addToPartyAOpenIntents(newIntentId);

            OpenIntent storage newIntent = intentLayout.openIntents[
                newIntentId
            ];

            if (newStatus == IntentStatus.CANCELED) {
                // send trading Fee back to partyA
                uint256 fee = LibIntent.getTradingFee(newIntent.id);
                accountLayout.balances[newIntent.partyA] += fee;
            } else {
                accountLayout.lockedBalances[intent.partyA] += LibIntent
                    .getPremiumOfOpenIntent(newIntent.id);
            }
            intent.quantity = quantity;
        }
        LibIntent.addToActiveTrades(tradeId);
        uint256 premium = LibIntent.getPremiumOfOpenIntent(intentId);
        accountLayout.balances[trade.partyA] -= premium;
        accountLayout.balances[trade.partyB] += premium;
    }

    function fillCloseIntent(
        uint256 intentId,
        uint256 quantity,
        uint256 price
    ) internal {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();

        CloseIntent storage intent = intentLayout.closeIntents[intentId];
        Trade storage trade = intentLayout.trades[intent.tradeId];

        require(
            quantity > 0 && quantity <= intent.quantity - intent.filledAmount,
            "LibIntent: Low filled amount"
        );
        require(
            intent.status == IntentStatus.PENDING ||
                intent.status == IntentStatus.CANCEL_PENDING,
            "LibIntent: Invalid state"
        );
        require(
            trade.status == TradeStatus.OPENED,
            "LibIntent: Invalid trade state"
        );
        require(
            block.timestamp <= intent.deadline,
            "LibIntent: Intent is expired"
        );
        require(
            block.timestamp < trade.expirationTimestamp,
            "LibIntent: Trade is expired"
        );
        require(price >= intent.price, "LibIntent: Closed price isn't valid");

        uint256 pnl = (quantity * price) / 1e18;
        accountLayout.balances[trade.partyA] += pnl;
        accountLayout.balances[trade.partyB] -= pnl;

        trade.avgClosedPrice =
            (trade.avgClosedPrice * trade.closedAmount + quantity * price) /
            (trade.closedAmount + quantity);

        trade.closedAmount += quantity;
        intent.filledAmount += quantity;

        if (intent.filledAmount == intent.quantity) {
            intent.statusModifyTimestamp = block.timestamp;
            intent.status = IntentStatus.FILLED;
            LibIntent.removeFromActiveCloseIntents(intentId);
            if (trade.quantity == trade.closedAmount) {
                trade.status = TradeStatus.CLOSED;
                trade.statusModifyTimestamp = block.timestamp;
            }
        } else if (intent.status == IntentStatus.CANCEL_PENDING) {
            intent.status = IntentStatus.CANCELED;
            intent.statusModifyTimestamp = block.timestamp;
        }
    }
}
