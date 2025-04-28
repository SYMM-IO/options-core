// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../storages/AppStorage.sol";
import { TradeStorage } from "../storages/TradeStorage.sol";
import { SymbolStorage } from "../storages/SymbolStorage.sol";
import { AccountStorage } from "../storages/AccountStorage.sol";
import { CloseIntentStorage } from "../storages/CloseIntentStorage.sol";

import { Trade, TradeStatus } from "../types/TradeTypes.sol";
import { Symbol, OptionType } from "../types/SymbolTypes.sol";
import { ScheduledReleaseBalance } from "../types/BalanceTypes.sol";
import { CloseIntent, IntentStatus } from "../types/IntentTypes.sol";

import { LibCloseIntentOps } from "./LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps } from "./LibScheduledReleaseBalance.sol";

library LibTradeOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;

	// Custom errors
	error TooManyActiveTradesForPartyA(address partyA, uint256 currentCount, uint256 maxCount);

	function getOpenAmount(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration;
	}

	function getAvailableAmountToClose(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration - self.closePendingAmount;
	}

	function getPnl(Trade memory self, uint256 currentPrice, uint256 filledAmount) internal view returns (uint256 pnl) {
		Symbol storage symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		if (currentPrice > self.tradeAgreements.strikePrice && symbol.optionType == OptionType.CALL) {
			pnl = ((currentPrice - self.tradeAgreements.strikePrice) * filledAmount) / 1e18;
		} else if (currentPrice < self.tradeAgreements.strikePrice && symbol.optionType == OptionType.PUT) {
			pnl = ((self.tradeAgreements.strikePrice - currentPrice) * filledAmount) / 1e18;
		}
	}

	function getPremium(Trade memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.openedPrice) / 1e18;
	}

	function getExerciseFee(Trade memory self, uint256 settlementPrice, uint256 pnl) internal pure returns (uint256) {
		uint256 cap = (self.tradeAgreements.exerciseFee.cap * pnl) / 1e18;
		uint256 fee = (self.tradeAgreements.exerciseFee.rate * settlementPrice * (getOpenAmount(self))) / 1e36;
		return cap < fee ? cap : fee;
	}

	function save(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();

		if (tradeLayout.activeTradesOf[self.partyA].length >= AppStorage.layout().maxTradePerPartyA)
			revert TooManyActiveTradesForPartyA(self.partyA, tradeLayout.activeTradesOf[self.partyA].length, AppStorage.layout().maxTradePerPartyA);

		tradeLayout.trades[self.id] = self;

		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		tradeLayout.tradesOf[self.partyA].push(self.id);
		tradeLayout.tradesOf[self.partyB].push(self.id);
		tradeLayout.activeTradesOf[self.partyA].push(self.id);
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].push(self.id);

		tradeLayout.partyATradesIndex[self.id] = tradeLayout.activeTradesOf[self.partyA].length - 1;
		tradeLayout.partyBTradesIndex[self.id] = tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;

		AccountStorage.layout().balances[self.partyA][symbol.collateral].addCounterParty(self.partyB);
	}

	function remove(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		uint256 indexOfPartyATrade = tradeLayout.partyATradesIndex[self.id];
		uint256 indexOfPartyBTrade = tradeLayout.partyBTradesIndex[self.id];
		uint256 lastIndex = tradeLayout.activeTradesOf[self.partyA].length - 1;
		tradeLayout.activeTradesOf[self.partyA][indexOfPartyATrade] = tradeLayout.activeTradesOf[self.partyA][lastIndex];
		tradeLayout.partyATradesIndex[tradeLayout.activeTradesOf[self.partyA][lastIndex]] = indexOfPartyATrade;
		tradeLayout.activeTradesOf[self.partyA].pop();

		lastIndex = tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][indexOfPartyBTrade] = tradeLayout.activeTradesOfPartyB[self.partyB][
			symbol.collateral
		][lastIndex];
		tradeLayout.partyBTradesIndex[tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][lastIndex]] = indexOfPartyBTrade;
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].pop();

		tradeLayout.partyATradesIndex[self.id] = 0;
		tradeLayout.partyBTradesIndex[self.id] = 0;
	}

	function close(Trade storage self, TradeStatus tradeStatus, IntentStatus intentStatus) internal {
		uint256 len = self.activeCloseIntentIds.length;
		for (uint8 i = 0; i < len; i++) {
			CloseIntent storage intent = CloseIntentStorage.layout().closeIntents[self.activeCloseIntentIds[0]];
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = intentStatus;
			intent.remove();
		}
		self.status = tradeStatus;
		self.statusModifyTimestamp = block.timestamp;
		remove(self);
	}
}
