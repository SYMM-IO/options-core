// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library PartyAFacetImpl {
    function sendOpenIntent(
        address[] calldata partyBsWhiteList,
        uint256 symbolId,
        uint256 price,
        uint256 quantity,
        uint256 strikePrice,
        uint256 expirationTimestamp,
        uint256 deadline,
        address affiliate
    ) internal returns (uint256 intentId) {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        AppStorage.Layout storage appLayout = AppStorage.layout();
        SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

        require(
            symbolLayout.symbols[symbolId].isValid,
            "PartyAFacet: Symbol is not valid"
        );
        require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
        require(
            expirationTimestamp >= block.timestamp,
            "PartyAFacet: Low expiration timestamp"
        );

        for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
            require(
                partyBsWhiteList[i] != msg.sender,
                "PartyAFacet: Sender isn't allowed in partyBWhiteList"
            );
        }

        require(
            uint256(accountLayout.balances[msg.sender]) >=
                (quantity *
                    price *
                    (1e18 + symbolLayout.symbols[symbolId].tradingFee)) /
                    1e36,
            "PartyAFacet: insufficient available balance"
        );
        require(
            appLayout.affiliateStatus[affiliate] || affiliate == address(0),
            "PartyAFacet: Invalid affiliate"
        );

        intentId = ++intentLayout.lastOpenIntentId;
        // create intent.
        OpenIntent memory intent = OpenIntent({
            id: intentId,
            tradeId: 0,
            partyBsWhiteList: partyBsWhiteList,
            symbolId: symbolId,
            price: price,
            quantity: quantity,
            strikePrice: strikePrice,
            expirationTimestamp: expirationTimestamp,
            partyA: msg.sender,
            partyB: address(0),
            status: IntentStatus.PENDING,
            parentId: 0,
            createTimestamp: block.timestamp,
            statusModifyTimestamp: block.timestamp,
            deadline: deadline,
            tradingFee: symbolLayout.symbols[symbolId].tradingFee,
            affiliate: affiliate
        });

        intentLayout.openIntents[intentId] = intent;
        intentLayout.openIntentsOf[msg.sender].push(intent.id);
        LibIntent.addToPartyAOpenIntents(intent.id);

        // lock funds the in middle of way
        accountLayout.lockedBalances[msg.sender] += LibIntent
            .getPremiumOfOpenIntent(intentId);

        uint256 fee = LibIntent.getTradingFee(intentId);
        accountLayout.balances[msg.sender] -= fee;
    }

    function cancelOpenIntent(
        uint256 intentId
    ) internal returns (IntentStatus result) {
        AccountStorage.Layout storage accountLayout = AccountStorage.layout();
        OpenIntent storage intent = IntentStorage.layout().openIntents[
            intentId
        ];
        require(
            intent.status == IntentStatus.PENDING ||
                intent.status == IntentStatus.LOCKED,
            "PartyAFacet: Invalid state"
        );

        if (block.timestamp > intent.deadline) {
            LibIntent.expireOpenIntent(intentId);
            result = IntentStatus.EXPIRED;
        } else if (intent.status == IntentStatus.PENDING) {
            intent.status = IntentStatus.CANCELED;
            uint256 fee = LibIntent.getTradingFee(intent.id);
            accountLayout.balances[intent.partyA] += fee;

            accountLayout.lockedBalances[intent.partyA] -= LibIntent
                .getPremiumOfOpenIntent(intentId);
            LibIntent.removeFromPartyAOpenIntents(intentId);
            result = IntentStatus.CANCELED;
        } else {
            // Intent is locked
            intent.status = IntentStatus.CANCEL_PENDING;
            result = IntentStatus.CANCEL_PENDING;
        }
        intent.statusModifyTimestamp = block.timestamp;
    }

    function cancelCloseIntent(
        uint256 intentId
    ) internal returns (IntentStatus) {
        CloseIntent storage intent = IntentStorage.layout().closeIntents[
            intentId
        ];
        require(
            intent.status == IntentStatus.PENDING,
            "PartyAFacet: Invalid state"
        );
        if (block.timestamp > intent.deadline) {
            LibIntent.expireCloseIntent(intentId);
            return IntentStatus.EXPIRED;
        } else {
            intent.statusModifyTimestamp = block.timestamp;
            intent.status = IntentStatus.CANCEL_PENDING;
            return IntentStatus.CANCEL_PENDING;
        }
    }

    function sendCloseIntent(
        uint256 tradeId,
        uint256 price,
        uint256 quantity,
        uint256 deadline
    ) internal returns (uint256 intentId) {
        IntentStorage.Layout storage intentLayout = IntentStorage.layout();
        Trade storage trade = intentLayout.trades[tradeId];

        require(
            trade.status == TradeStatus.OPENED,
            "PartyAFacet: Invalid state"
        );
        require(deadline >= block.timestamp, "PartyAFacet: Low deadline");

        require(
            LibIntent.getAvailableAmountToClose(trade.id) >= quantity,
            "PartyAFacet: Invalid quantity"
        );
        require(
            trade.activeCloseIntentIds.length <
                AppStorage.layout().maxCloseOrdersLength,
            "PartyAFacet: Too many close orders"
        );

        // create intent.
        intentId = ++intentLayout.lastCloseIntentId;
        CloseIntent memory intent = CloseIntent({
            id: intentId,
            tradeId: tradeId,
            price: price,
            quantity: quantity,
            filledAmount: 0,
            status: IntentStatus.PENDING,
            createTimestamp: block.timestamp,
            statusModifyTimestamp: block.timestamp,
            deadline: deadline
        });

        intentLayout.closeIntents[intentId] = intent;
        trade.activeCloseIntentIds.push(intent.id);
        intentLayout.closeIntentIdsOf[trade.id].push(intentId);
        trade.closePendingAmount += quantity;
    }
}
