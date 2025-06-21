// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibTradeOps } from "../models/LibTrade.sol";
import { LibCloseIntentOps } from "../models/LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { SymbolStorage, Symbol } from "../../storages/SymbolStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { CloseIntent, CloseIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { CommonErrors } from "../../errors/CommonErrors.sol";
import { PartyBCloseErrors } from "../../errors/PartyBCloseErrors.sol";

library LibPartyBClose {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function acceptCancelCloseIntent(address sender, uint256 intentId) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];

		if (trade.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		CommonErrors.requireStatus("CloseIntentStatus", uint8(intent.status), uint8(CloseIntentStatus.CANCEL_PENDING));

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = CloseIntentStatus.CANCELED;
		intent.remove();
	}

	function fillCloseIntent(address sender, uint256 intentId, uint256 quantity, uint256 price) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		if (sender != trade.partyB) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			trade.partyA.requireSolvent(trade.partyB, symbol.collateral, trade.tradeAgreements.marginType);
		}
		trade.partyB.requireSolvent(trade.partyA, symbol.collateral, trade.tradeAgreements.marginType);

		if (quantity == 0 || quantity > intent.quantity - intent.filledAmount)
			revert PartyBCloseErrors.InvalidFillAmount(quantity, intent.quantity - intent.filledAmount);

		if (!(intent.status == CloseIntentStatus.PENDING || intent.status == CloseIntentStatus.CANCEL_PENDING)) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(CloseIntentStatus.PENDING);
			requiredStatuses[1] = uint8(CloseIntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("CloseIntentStatus", uint8(intent.status), requiredStatuses);
		}

		CommonErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		if (block.timestamp > intent.deadline) revert CommonErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (block.timestamp >= trade.tradeAgreements.expirationTimestamp)
			revert PartyBCloseErrors.TradeExpired(intent.tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (
			(trade.tradeAgreements.tradeSide == TradeSide.BUY && price < intent.price) ||
			(trade.tradeAgreements.tradeSide == TradeSide.SELL && price > intent.price)
		) revert PartyBCloseErrors.InvalidClosePrice(price, intent.price);

		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

		uint256 pnl = (quantity * price) / 1e18;
		if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (trade.tradeAgreements.marginType == MarginType.ISOLATED) {
				partyBBalance.instantIsolatedAdd((trade.getPremium() * quantity) / trade.tradeAgreements.quantity, IncreaseBalanceReason.PREMIUM);
			} else {
				partyBBalance.scheduledAdd(
					trade.partyA,
					(trade.getPremium() * quantity) / trade.tradeAgreements.quantity,
					MarginType.ISOLATED,
					IncreaseBalanceReason.PREMIUM
				);
			}

			partyBBalance.subForCounterParty(trade.partyA, pnl, trade.tradeAgreements.marginType, DecreaseBalanceReason.REALIZED_PNL);
			partyABalance.scheduledAdd(trade.partyB, pnl, trade.tradeAgreements.marginType, IncreaseBalanceReason.REALIZED_PNL);
		} else {
			if (trade.tradeAgreements.marginType == MarginType.CROSS)
				partyABalance.decreaseMM(trade.partyB, (trade.tradeAgreements.mm * quantity) / trade.tradeAgreements.quantity);
			partyABalance.subForCounterParty(trade.partyB, pnl, trade.tradeAgreements.marginType, DecreaseBalanceReason.PREMIUM);
			partyBBalance.scheduledAdd(trade.partyA, pnl, trade.tradeAgreements.marginType, IncreaseBalanceReason.PREMIUM);
		}

		trade.avgClosedPriceBeforeExpiration =
			(trade.avgClosedPriceBeforeExpiration * trade.closedAmountBeforeExpiration + quantity * price) /
			(trade.closedAmountBeforeExpiration + quantity);
		trade.closedAmountBeforeExpiration += quantity;
		intent.filledAmount += quantity;

		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}

		if (intent.filledAmount == intent.quantity) {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = CloseIntentStatus.FILLED;
			intent.remove();
			if (trade.tradeAgreements.quantity == trade.closedAmountBeforeExpiration) {
				trade.status = TradeStatus.CLOSED;
				trade.statusModifyTimestamp = block.timestamp;
				trade.remove();
			}
		} else if (intent.status == CloseIntentStatus.CANCEL_PENDING) {
			intent.status = CloseIntentStatus.CANCELED;
			intent.statusModifyTimestamp = block.timestamp;
			intent.remove();
		}
	}
}
