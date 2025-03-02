// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AppStorage.sol";
import "./LibIntent.sol";

library LibPartyB {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

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
		accountLayout.balances[feeCollector][intent.tradingFee.feeToken].instantAdd(
			intent.tradingFee.feeToken,
			(quantity * price * intent.tradingFee.platformFee) / (intent.tradingFee.tokenPrice * 1e18)
		);
		accountLayout.balances[feeCollector][intent.tradingFee.feeToken].instantAdd(
			intent.tradingFee.feeToken,
			(quantity * price * intent.tradingFee.platformFee) / (intent.tradingFee.tokenPrice * 1e18)
		);

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
				affiliate: intent.affiliate,
				userData: intent.userData
			});

			intentLayout.openIntents[newIntentId] = q;
			intentLayout.openIntentsOf[intent.partyA].push(newIntentId);
			LibIntent.addToPartyAOpenIntents(newIntentId);

			OpenIntent storage newIntent = intentLayout.openIntents[newIntentId];

			if (newStatus == IntentStatus.CANCELED) {
				// send trading Fee back to partyA
				uint256 tradingFee = LibIntent.getTradingFee(newIntent.id);
				uint256 affiliateFee = LibIntent.getAffiliateFee(newIntent.id);
				if (intent.partyBsWhiteList.length == 1) {
					accountLayout.balances[intent.partyA][symbol.collateral].scheduledAdd(newIntent.partyBsWhiteList[0], tradingFee, block.timestamp);
					accountLayout.balances[intent.partyA][symbol.collateral].scheduledAdd(newIntent.partyBsWhiteList[0], affiliateFee, block.timestamp);
				} else {
					accountLayout.balances[intent.partyA][symbol.collateral].instantAdd(symbol.collateral, tradingFee);
					accountLayout.balances[intent.partyA][symbol.collateral].instantAdd(symbol.collateral, affiliateFee);
				}
			} else {
				accountLayout.lockedBalances[intent.partyA][symbol.collateral] += LibIntent.getPremiumOfOpenIntent(newIntent.id);
			}
			intent.quantity = quantity;
		}
		LibIntent.addToActiveTrades(tradeId);
		uint256 premium = LibIntent.getPremiumOfOpenIntent(intentId);
		accountLayout.balances[trade.partyA][symbol.collateral].syncAll(block.timestamp);
		accountLayout.balances[trade.partyA][symbol.collateral].subForPartyB(trade.partyB, premium);
		accountLayout.balances[trade.partyB][symbol.collateral].instantAdd(symbol.collateral, premium);
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

	function lockOpenIntent(uint256 intentId, address partyB) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];
		Symbol storage symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(intent.status == IntentStatus.PENDING, "LibPartyB: Invalid state");
		require(block.timestamp <= intent.deadline, "LibPartyB: Intent is expired");
		require(symbol.isValid, "LibPartyB: Symbol is not valid");
		require(block.timestamp <= intent.expirationTimestamp, "LibPartyB: Requested expiration has been passed");
		require(intentId <= intentLayout.lastOpenIntentId, "LibPartyB: Invalid intentId");
		require(AppStorage.layout().partyBConfigs[partyB].oracleId == symbol.oracleId, "LibPartyB: Oracle not matched");

		bool isValidPartyB;
		if (intent.partyBsWhiteList.length == 0) {
			require(partyB != intent.partyA, "LibPartyB: PartyA can't be partyB too");
			isValidPartyB = true;
		} else {
			for (uint8 index = 0; index < intent.partyBsWhiteList.length; index++) {
				if (partyB == intent.partyBsWhiteList[index]) {
					isValidPartyB = true;
					break;
				}
			}
		}
		require(isValidPartyB, "LibPartyB: Sender isn't whitelisted");
		require(
			AppStorage.layout().liquidationDetails[partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"LibPartyB: PartyB is in the liquidation process"
		);
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.LOCKED;
		intent.partyB = partyB;
		LibIntent.addToPartyBOpenIntents(intentId);
		intentLayout.openIntentsOf[intent.partyB].push(intent.id);
	}

	function unlockOpenIntent(uint256 intentId) internal returns (IntentStatus) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		OpenIntent storage intent = intentLayout.openIntents[intentId];

		require(intent.status == IntentStatus.LOCKED, "LibPartyB: Invalid state");
		require(
			AppStorage.layout().liquidationDetails[intent.partyB][SymbolStorage.layout().symbols[intent.symbolId].collateral].status ==
				LiquidationStatus.SOLVENT,
			"LibPartyB: PartyB is in the liquidation process"
		);

		if (block.timestamp > intent.deadline) {
			LibIntent.expireOpenIntent(intentId);
			return IntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.PENDING;
			LibIntent.removeFromPartyBOpenIntents(intentId);
			intent.partyB = address(0);
			return IntentStatus.PENDING;
		}
	}
}
