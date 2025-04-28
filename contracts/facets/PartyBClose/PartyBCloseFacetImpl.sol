// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { SymbolStorage, Symbol } from "../../storages/SymbolStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { CloseIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { PartyBCloseFacetErrors } from "./PartyBCloseFacetErrors.sol";

library PartyBCloseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function acceptCancelCloseIntent(address sender, uint256 intentId) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];

		if (trade.partyB != sender) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		if (intent.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.remove();
	}

	function fillCloseIntent(address sender, uint256 intentId, uint256 quantity, uint256 price) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		if (sender != trade.partyB) revert CommonErrors.UnauthorizedSender(sender, trade.partyB);

		sender.requireSolventPartyB(trade.partyA, symbol.collateral, trade.partyBMarginType);
		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			trade.partyA.requireSolventPartyA(trade.partyB, symbol.collateral);
		}

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
			if (trade.tradeAgreements.marginType == MarginType.ISOLATED && trade.partyBMarginType == MarginType.ISOLATED) {
				accountLayout.balances[trade.partyB][symbol.collateral].instantIsolatedAdd(
					(trade.getPremium() * quantity) / trade.tradeAgreements.quantity,
					IncreaseBalanceReason.PREMIUM
				);
			} else {
				accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
					trade.partyA,
					(trade.getPremium() * quantity) / trade.tradeAgreements.quantity,
					trade.partyBMarginType,
					IncreaseBalanceReason.PREMIUM
				);
			}

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
			if (trade.tradeAgreements.marginType == MarginType.CROSS) {
				accountLayout.balances[trade.partyA][symbol.collateral].decreaseMM(
					trade.partyB,
					(trade.tradeAgreements.mm * quantity) / trade.tradeAgreements.quantity
				);
			}
			accountLayout.balances[trade.partyA][symbol.collateral].subForCounterParty(
				trade.partyB,
				pnl,
				trade.tradeAgreements.marginType,
				DecreaseBalanceReason.PREMIUM
			);
			accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
				trade.partyA,
				pnl,
				trade.partyBMarginType,
				IncreaseBalanceReason.PREMIUM
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
