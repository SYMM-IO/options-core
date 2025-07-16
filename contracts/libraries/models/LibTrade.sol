// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibCloseIntentOps } from "../models/LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";
import { LibParty } from "../models/LibParty.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Symbol, OptionType } from "../../types/SymbolTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { CloseIntent, CloseIntentStatus } from "../../types/IntentTypes.sol";

import { TradeErrors } from "../../errors/TradeErrors.sol";

library LibTradeOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibParty for address;

	function getOpenAmount(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration;
	}

	function getAvailableAmountToClose(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration - self.closePendingAmount;
	}

	function calculatePnl(Trade memory self, uint256 currentPrice, uint256 filledAmount) internal view returns (uint256 pnl) {
		Symbol storage symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		if (currentPrice > self.tradeAgreements.strikePrice && symbol.optionType == OptionType.CALL) {
			pnl = ((currentPrice - self.tradeAgreements.strikePrice) * filledAmount) / 1e18;
		} else if (currentPrice < self.tradeAgreements.strikePrice && symbol.optionType == OptionType.PUT) {
			pnl = ((self.tradeAgreements.strikePrice - currentPrice) * filledAmount) / 1e18;
		}
	}

	function calculatePremium(Trade memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.openedPrice) / 1e18;
	}

	function calculateProportionalPremium(Trade memory self, uint256 amount) internal pure returns (uint256) {
		return (calculatePremium(self) * amount) / self.tradeAgreements.quantity;
	}

	function calculateProportionalMM(Trade memory self, uint256 amount) internal pure returns (uint256) {
		return (self.tradeAgreements.mm * amount) / self.tradeAgreements.quantity;
	}

	function calculateExerciseFee(Trade memory self, uint256 settlementPrice, uint256 pnl) internal pure returns (uint256) {
		uint256 cap = (self.tradeAgreements.exerciseFee.cap * pnl) / 1e18;
		uint256 fee = (self.tradeAgreements.exerciseFee.rate * settlementPrice * (getOpenAmount(self))) / 1e36;
		return cap < fee ? cap : fee;
	}

	function register(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();

		if (tradeLayout.activeTradesOfPartyA[self.partyA].length >= AppStorage.layout().maxTradePerPartyA)
			revert TradeErrors.TooManyActiveTradesForPartyA(
				self.partyA,
				tradeLayout.activeTradesOfPartyA[self.partyA].length,
				AppStorage.layout().maxTradePerPartyA
			);

		tradeLayout.trades[self.id] = self;

		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		tradeLayout.activeTradesOfPartyA[self.partyA].push(self.id);
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].push(self.id);

		tradeLayout.partyATradesIndex[self.id] = tradeLayout.activeTradesOfPartyA[self.partyA].length - 1;
		tradeLayout.partyBTradesIndex[self.id] = tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;

		tradeLayout.activeTradesOfPartyAWithPartyBCount[self.partyA][symbol.collateral][self.partyB]++;
		self.partyA.balanceOf(symbol.collateral).addCounterParty(self.partyB);
	}

	function unregister(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		uint256 indexOfPartyATrade = tradeLayout.partyATradesIndex[self.id];
		uint256 indexOfPartyBTrade = tradeLayout.partyBTradesIndex[self.id];
		uint256 lastIndex = tradeLayout.activeTradesOfPartyA[self.partyA].length - 1;
		tradeLayout.activeTradesOfPartyA[self.partyA][indexOfPartyATrade] = tradeLayout.activeTradesOfPartyA[self.partyA][lastIndex];
		tradeLayout.partyATradesIndex[tradeLayout.activeTradesOfPartyA[self.partyA][lastIndex]] = indexOfPartyATrade;
		tradeLayout.activeTradesOfPartyA[self.partyA].pop();

		lastIndex = tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][indexOfPartyBTrade] = tradeLayout.activeTradesOfPartyB[self.partyB][
			symbol.collateral
		][lastIndex];
		tradeLayout.partyBTradesIndex[tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral][lastIndex]] = indexOfPartyBTrade;
		tradeLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].pop();

		tradeLayout.partyATradesIndex[self.id] = 0;
		tradeLayout.partyBTradesIndex[self.id] = 0;

		tradeLayout.activeTradesOfPartyAWithPartyBCount[self.partyA][symbol.collateral][self.partyB]--;
		self.partyA.balanceOf(symbol.collateral).tryRemoveCounterParty(self.partyB);
	}

	function close(Trade storage self, TradeStatus tradeStatus, CloseIntentStatus intentStatus) internal {
		uint256 len = self.activeCloseIntentIds.length;
		for (uint8 i = 0; i < len; i++) {
			CloseIntent storage intent = CloseIntentStorage.layout().closeIntents[self.activeCloseIntentIds[0]];
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = intentStatus;
			intent.unregister();
		}
		self.status = tradeStatus;
		self.statusModifyTimestamp = block.timestamp;
		unregister(self);
	}
}
