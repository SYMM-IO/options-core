// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { CloseIntent, Trade, IntentStorage, TradeStatus, IntentStatus } from "../storages/IntentStorage.sol";
import { Symbol, SymbolStorage, OptionType } from "../storages/SymbolStorage.sol";
import { AppStorage } from "../storages/AppStorage.sol";
import { LibCloseIntentOps } from "./LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "./LibScheduledReleaseBalance.sol";
import { CommonErrors } from "./CommonErrors.sol";

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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		if (intentLayout.activeTradesOf[self.partyA].length >= AppStorage.layout().maxTradePerPartyA)
			revert TooManyActiveTradesForPartyA(self.partyA, intentLayout.activeTradesOf[self.partyA].length, AppStorage.layout().maxTradePerPartyA);

		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		intentLayout.tradesOf[self.partyA].push(self.id);
		intentLayout.tradesOf[self.partyB].push(self.id);
		intentLayout.activeTradesOf[self.partyA].push(self.id);
		intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].push(self.id);

		intentLayout.partyATradesIndex[self.id] = intentLayout.activeTradesOf[self.partyA].length - 1;
		intentLayout.partyBTradesIndex[self.id] = intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;

		AccountStorage.layout().balances[self.partyA][symbol.collateral].addCounterParty(self.partyB, self.tradeAgreements.marginType);
	}

	function remove(Trade memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		uint256 indexOfPartyATrade = intentLayout.partyATradesIndex[self.id];
		uint256 indexOfPartyBTrade = intentLayout.partyBTradesIndex[self.id];
		uint256 lastIndex = intentLayout.activeTradesOf[self.partyA].length - 1;
		intentLayout.activeTradesOf[self.partyA][indexOfPartyATrade] = intentLayout.activeTradesOf[self.partyA][lastIndex];
		intentLayout.partyATradesIndex[intentLayout.activeTradesOf[self.partyA][lastIndex]] = indexOfPartyATrade;
		intentLayout.activeTradesOf[self.partyA].pop();

		lastIndex = intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;
		intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][indexOfPartyBTrade] = intentLayout.activeTradesOfPartyB[self.partyB][
			symbol.collateral
		][lastIndex];
		intentLayout.partyBTradesIndex[intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][lastIndex]] = indexOfPartyBTrade;
		intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].pop();

		intentLayout.partyATradesIndex[self.id] = 0;
		intentLayout.partyBTradesIndex[self.id] = 0;
	}

	function close(Trade storage self, TradeStatus tradeStatus, IntentStatus intentStatus) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		uint256 len = self.activeCloseIntentIds.length;
		for (uint8 i = 0; i < len; i++) {
			CloseIntent storage intent = intentLayout.closeIntents[self.activeCloseIntentIds[0]];
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = intentStatus;
			intent.remove();
		}
		self.status = tradeStatus;
		self.statusModifyTimestamp = block.timestamp;
		remove(self);
	}
}
