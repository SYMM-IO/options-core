// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibParty } from "../../libraries/LibParty.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { CloseIntent, Trade, IntentStorage, IntentStatus, TradeStatus, TradeSide } from "../../storages/IntentStorage.sol";
import { SymbolStorage, Symbol } from "../../storages/SymbolStorage.sol";
import { PartyBCloseFacetErrors } from "./PartyBCloseFacetErrors.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";

library PartyBCloseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function acceptCancelCloseIntent(address sender, uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];

		if (trade.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		trade.partyB.requireSolvent(SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId].collateral);
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

		if (sender != trade.partyB) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		trade.partyB.requireSolvent(symbol.collateral);

		if (quantity == 0 || quantity > intent.quantity - intent.filledAmount)
			revert PartyBCloseFacetErrors.InvalidFilledAmount(quantity, intent.quantity - intent.filledAmount);

		if (!(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING)) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(IntentStatus.PENDING);
			requiredStatuses[1] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (trade.status != TradeStatus.OPENED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(TradeStatus.OPENED);
			revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
		}

		if (block.timestamp > intent.deadline) revert PartyBCloseFacetErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (block.timestamp >= trade.tradeAgreements.expirationTimestamp)
			revert PartyBCloseFacetErrors.TradeExpired(intent.tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (
			(trade.tradeAgreements.tradeSide == TradeSide.BUY && price < intent.price) ||
			(trade.tradeAgreements.tradeSide == TradeSide.SELL && price > intent.price)
		) revert PartyBCloseFacetErrors.InvalidClosedPrice(price, intent.price);

		uint256 pnl = (quantity * price) / 1e18;
		if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
			accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
				trade.partyA,
				(trade.getPremium() * quantity) / trade.tradeAgreements.quantity,
				trade.partyBMarginType,
				IncreaseBalanceReason.PREMIUM
			);
			accountLayout.balances[trade.partyB][symbol.collateral].subForCounterParty(
				trade.partyA,
				pnl,
				trade.partyBMarginType,
				DecreaseBalanceReason.REALIZED_PNL
			);
			accountLayout.balances[trade.partyA][symbol.collateral].scheduledAdd(
				trade.partyB,
				pnl,
				trade.tradeAgreements.marginType,
				IncreaseBalanceReason.REALIZED_PNL
			);
		} else {
			accountLayout.balances[trade.partyA][symbol.collateral].subForCounterParty(
				trade.partyB,
				pnl,
				trade.tradeAgreements.marginType,
				DecreaseBalanceReason.REALIZED_PNL
			);
			accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
				trade.partyA,
				pnl,
				trade.partyBMarginType,
				IncreaseBalanceReason.REALIZED_PNL
			);
		}

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
