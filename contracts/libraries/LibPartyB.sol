// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AppStorage.sol";
import "./LibIntent.sol";

library LibPartyB {
	using StagedReleaseBalanceOps for StagedReleaseBalance;

	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) internal returns (uint256 newIntentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(symbol.isValid, "LibPartyB: Symbol is not valid");
		require(intent.status == IntentStatus.LOCKED || intent.status == IntentStatus.CANCEL_PENDING, "LibPartyB: Invalid state");
		require(
			appLayout.liquidationDetails[intent.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"LibPartyB: PartyB is liquidated"
		);
		require(block.timestamp <= intent.deadline, "LibPartyB: Intent is expired");
		require(block.timestamp <= intent.expirationTimestamp, "LibPartyB: Requested expiration has been passed");
		require(intentLayout.activeTradesOf[intent.partyA].length < appLayout.maxTradePerPartyA, "LibPartyB: Too many active trades for partyA");
		require(intent.quantity >= quantity && quantity > 0, "LibPartyB: Invalid quantity");
		require(price <= intent.price, "LibPartyB: Opened price isn't valid");

		address feeCollector = appLayout.affiliateFeeCollector[intent.affiliate] == address(0)
			? appLayout.defaultFeeCollector
			: appLayout.affiliateFeeCollector[intent.affiliate];
		accountLayout.balances[feeCollector][symbol.collateral].instantAdd((quantity * intent.price * intent.tradingFee) / 1e36);

		uint256 tradeId = ++intentLayout.lastTradeId;
		Trade memory trade = Trade({
			id: tradeId,
			openIntentId: intentId,
			activeCloseIntentIds: new uint256[](0),
			symbolId: intent.symbolId,
			quantity: quantity,
			strikePrice: intent.strikePrice,
			expirationTimestamp: intent.expirationTimestamp,
			settledPrice: 0,
			exerciseFee: intent.exerciseFee,
			partyA: intent.partyA,
			partyB: intent.partyB,
			openedPrice: price,
			closedAmountBeforeExpiration: 0,
			closePendingAmount: 0,
			avgClosedPriceBeforeExpiration: 0,
			status: TradeStatus.OPENED,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp
		});

		intent.tradeId = tradeId;
		intent.status = IntentStatus.FILLED;
		intent.statusModifyTimestamp = block.timestamp;

		LibIntent.removeFromPartyAOpenIntents(intentId);
		LibIntent.removeFromPartyBOpenIntents(intentId);

		accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= LibIntent.getPremiumOfOpenIntent(intentId);

		// partially fill
		if (intent.quantity > quantity) {
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
				exerciseFee: intent.exerciseFee,
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

			OpenIntent storage newIntent = intentLayout.openIntents[newIntentId];

			if (newStatus == IntentStatus.CANCELED) {
				// send trading Fee back to partyA
				uint256 fee = LibIntent.getTradingFee(newIntent.id);
				if (intent.partyBsWhiteList.length == 1) {
					accountLayout.balances[intent.partyA][symbol.collateral].add(newIntent.partyBsWhiteList[0], fee, block.timestamp);
				} else {
					accountLayout.balances[intent.partyA][symbol.collateral].instantAdd(fee);
				}
			} else {
				accountLayout.lockedBalances[intent.partyA][symbol.collateral] += LibIntent.getPremiumOfOpenIntent(newIntent.id);
			}
			intent.quantity = quantity;
		}
		LibIntent.addToActiveTrades(tradeId);
		uint256 premium = LibIntent.getPremiumOfOpenIntent(intentId);
		accountLayout.balances[trade.partyA][symbol.collateral].subForPartyB(trade.partyB, premium);
		accountLayout.balances[trade.partyB][symbol.collateral].instantAdd(premium);
	}

	function fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];

		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"LibPartyB: PartyB is liquidated"
		);
		require(quantity > 0 && quantity <= intent.quantity - intent.filledAmount, "LibPartyB: Invalid filled amount");
		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.CANCEL_PENDING, "LibPartyB: Invalid state");
		require(trade.status == TradeStatus.OPENED, "LibPartyB: Invalid trade state");
		require(block.timestamp <= intent.deadline, "LibPartyB: Intent is expired");
		require(block.timestamp < trade.expirationTimestamp, "LibPartyB: Trade is expired");
		require(price >= intent.price, "LibPartyB: Closed price isn't valid");

		uint256 pnl = (quantity * price) / 1e18;
		accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(pnl);
		accountLayout.balances[trade.partyB][symbol.collateral].sub(pnl);

		trade.avgClosedPriceBeforeExpiration =
			(trade.avgClosedPriceBeforeExpiration * trade.closedAmountBeforeExpiration + quantity * price) /
			(trade.closedAmountBeforeExpiration + quantity);

		trade.closedAmountBeforeExpiration += quantity;
		intent.filledAmount += quantity;

		if (intent.filledAmount == intent.quantity) {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.FILLED;
			LibIntent.removeFromActiveCloseIntents(intentId);
			if (trade.quantity == trade.closedAmountBeforeExpiration) {
				trade.status = TradeStatus.CLOSED;
				trade.statusModifyTimestamp = block.timestamp;
				LibIntent.removeFromActiveTrades(trade.id);
			}
		} else if (intent.status == IntentStatus.CANCEL_PENDING) {
			intent.status = IntentStatus.CANCELED;
			intent.statusModifyTimestamp = block.timestamp;
			LibIntent.removeFromActiveCloseIntents(intentId);
		}
	}
}
