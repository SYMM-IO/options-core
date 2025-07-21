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
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { CloseIntent, CloseIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { TradeErrors } from "../../errors/TradeErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";

library LibPartyBClose {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function acceptCancelCloseIntent(address sender, uint256 intentId) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Only the assigned Party B can accept the cancellation
		if (trade.partyB != sender) revert ValidationErrors.UnauthorizedSender(sender, trade.partyB);

		// Intent must currently be waiting for Party B’s approval
		ValidationErrors.requireStatus("CloseIntentStatus", uint8(intent.status), uint8(CloseIntentStatus.CANCEL_PENDING));

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = CloseIntentStatus.CANCELED;
		intent.unregister();
	}

	function fillCloseIntent(address sender, uint256 intentId, uint256 quantity, uint256 price) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
		CloseIntent storage intent = closeIntentLayout.closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
		MarginType marginType = trade.tradeAgreements.marginType;

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Only the designated Party B may execute the fill
		if (sender != trade.partyB) revert ValidationErrors.UnauthorizedSender(sender, trade.partyB);

		// Verify that both parties are not in liquidation process
		if (marginType == MarginType.CROSS) {
			trade.partyA.requireSolvent(trade.partyB, symbol.collateral, marginType);
		}
		trade.partyB.requireSolvent(trade.partyA, symbol.collateral, marginType);

		// Quantity must be >0 and ≤ remaining unfilled amount
		if (quantity == 0 || quantity > (intent.quantity - intent.filledAmount)) {
			revert IntentErrors.InvalidFillAmount(quantity, intent.quantity - intent.filledAmount);
		}

		// Intent must be PENDING or CANCEL_PENDING
		if (intent.status != CloseIntentStatus.PENDING && intent.status != CloseIntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(CloseIntentStatus.PENDING);
			requiredStatuses[1] = uint8(CloseIntentStatus.CANCEL_PENDING);
			revert ValidationErrors.InvalidState("CloseIntentStatus", uint8(intent.status), requiredStatuses);
		}

		// Underlying trade must still be OPENED
		ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		// Intent deadline & option expiration checks
		if (block.timestamp > intent.deadline) revert IntentErrors.IntentExpired(intentId, block.timestamp, intent.deadline);

		if (block.timestamp >= trade.tradeAgreements.expirationTimestamp)
			revert TradeErrors.TradeExpired(intent.tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		// Price must be favorable to Party A (BUY → price ≥ intent.price, SELL → price ≤ intent.price)
		if (
			(trade.tradeAgreements.tradeSide == TradeSide.BUY && price < intent.price) ||
			(trade.tradeAgreements.tradeSide == TradeSide.SELL && price > intent.price)
		) revert IntentErrors.InvalidClosePrice(price, intent.price);

		/* ---------------------------------------- BALANCES ---------------------------------------- */

		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

		uint256 closePremium = (quantity * price) / 1e18;

		if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
			uint256 openPremium = trade.calculateProportionalPremium(quantity);
			if (marginType == MarginType.ISOLATED) {
				partyBBalance.instantIsolatedAdd(openPremium, IncreaseBalanceReason.PREMIUM);
			} else {
				partyBBalance.scheduledAdd(trade.partyA, openPremium, marginType, IncreaseBalanceReason.PREMIUM);
			}

			partyBBalance.subForCounterParty(trade.partyA, closePremium, marginType, DecreaseBalanceReason.PREMIUM);
			partyABalance.scheduledAdd(trade.partyB, closePremium, marginType, IncreaseBalanceReason.PREMIUM);
		} else {
			partyABalance.decreaseMM(trade.partyB, trade.calculateProportionalMM(quantity));
			partyABalance.subForCounterParty(trade.partyB, closePremium, marginType, DecreaseBalanceReason.PREMIUM);
			partyBBalance.scheduledAdd(trade.partyA, closePremium, marginType, IncreaseBalanceReason.PREMIUM);
		}

		// Collect close-fees from Party A
		uint256[3] memory fees = intent.getFeesFromUser(quantity, price);

		{
			address feeToken = intent.feeStructure.feeToken;

			// Determine affiliate fee collector (use default if none specified)
			address affiliateFeeCollector = feeLayout.affiliateFeeCollector[trade.affiliate] == address(0)
				? feeLayout.defaultFeeCollector
				: feeLayout.affiliateFeeCollector[trade.affiliate];

			// Pay platform fees
			ScheduledReleaseBalance storage defaultFeeCollectorBalance = feeLayout.defaultFeeCollector.balanceOf(feeToken);
			defaultFeeCollectorBalance.setup(feeLayout.defaultFeeCollector, feeToken);
			defaultFeeCollectorBalance.instantIsolatedAdd(fees[0], IncreaseBalanceReason.PLATFORM_FEE);

			// Pay affiliate fees
			ScheduledReleaseBalance storage affiliateFeeCollectorBalance = affiliateFeeCollector.balanceOf(feeToken);
			affiliateFeeCollectorBalance.setup(affiliateFeeCollector, feeToken);
			affiliateFeeCollectorBalance.instantIsolatedAdd(fees[1], IncreaseBalanceReason.AFFILIATE_FEE);

			// Pay solver fees
			ScheduledReleaseBalance storage solverFeeCollectorBalance = trade.partyB.balanceOf(feeToken);
			solverFeeCollectorBalance.setup(trade.partyB, feeToken);
			if (marginType == MarginType.ISOLATED) {
				solverFeeCollectorBalance.instantIsolatedAdd(fees[2], IncreaseBalanceReason.SOLVER_FEE);
			} else {
				solverFeeCollectorBalance.scheduledAdd(trade.partyA, fees[2], MarginType.CROSS, IncreaseBalanceReason.SOLVER_FEE);
			}
		}

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		// Re-compute weighted average close price
		trade.avgClosedPriceBeforeExpiration =
			(trade.avgClosedPriceBeforeExpiration * trade.closedAmountBeforeExpiration + quantity * price) /
			(trade.closedAmountBeforeExpiration + quantity);

		// Bump filled/closed amounts
		trade.closedAmountBeforeExpiration += quantity;
		intent.filledAmount += quantity;

		/* ---------------------------------------- NONCE ---------------------------------------- */

		// For cross-margin, increment bilateral nonce to invalidate off-chain sigs
		if (marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}

		/* ---------------------------------------- COMPLETION ---------------------------------------- */

		if (intent.filledAmount == intent.quantity) {
			// Intent completely filled → finalize
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = CloseIntentStatus.FILLED;
			intent.unregister();

			// If the entire trade is now closed, mark it accordingly
			if (trade.tradeAgreements.quantity == trade.closedAmountBeforeExpiration) {
				trade.status = TradeStatus.CLOSED;
				trade.statusModifyTimestamp = block.timestamp;
				trade.unregister();
			}
		} else if (intent.status == CloseIntentStatus.CANCEL_PENDING) {
			// Partial fill on a cancel-pending intent: mark remaining portion as canceled
			intent.status = CloseIntentStatus.CANCELED;
			intent.statusModifyTimestamp = block.timestamp;
			intent.unregister();
		}
	}
}
