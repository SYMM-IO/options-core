// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibCloseIntent.sol";
import "../../libraries/LibTrade.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

library PartyBCloseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;

	function acceptCancelCloseIntent(address sender, uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = IntentStorage.layout().trades[intent.tradeId];

		require(trade.partyB == sender, "PartyBFacet: Invalid sender");
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(
			AppStorage.layout().liquidationDetails[trade.partyB][SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId].collateral].status ==
				LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is in the liquidation process"
		);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.remove();
	}

	function fillCloseIntent(address sender, uint256 intentId, uint256 quantity, uint256 price) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		require(sender == trade.partyB, "PartyBFacet: Invalid sender");
		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		require(quantity > 0 && quantity <= intent.quantity - intent.filledAmount, "PartyBFacet: Invalid filled amount");
		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp <= intent.deadline, "PartyBFacet: Intent is expired");
		require(block.timestamp < trade.tradeAgreements.expirationTimestamp, "PartyBFacet: Trade is expired");
		require(price >= intent.price, "PartyBFacet: Closed price isn't valid");

		uint256 pnl = (quantity * price) / 1e18;
		accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(symbol.collateral, pnl);
		accountLayout.balances[trade.partyB][symbol.collateral].sub(pnl);

		trade.avgClosedPriceBeforeExpiration =
			(trade.avgClosedPriceBeforeExpiration * trade.closedAmountBeforeExpiration + quantity * price) /
			(trade.closedAmountBeforeExpiration + quantity);

		trade.closedAmountBeforeExpiration += quantity;
		intent.filledAmount += quantity;

		if (intent.filledAmount == intent.quantity) {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.FILLED;
			intent.remove();
			if (trade.tradeAgreements.quantity == trade.closedAmountBeforeExpiration) {
				trade.status = TradeStatus.CLOSED;
				trade.statusModifyTimestamp = block.timestamp;
				trade.remove();
			}
		} else if (intent.status == IntentStatus.CANCEL_PENDING) {
			intent.status = IntentStatus.CANCELED;
			intent.statusModifyTimestamp = block.timestamp;
			intent.remove();
		}
	}
}
