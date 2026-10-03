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
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration; // how about pending close intents
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

	function activeTradesOfPartyA(address owner, uint256 bucketId) internal view returns (uint256[] storage) {
		TradeStorage.Layout storage layout = TradeStorage.layout();
		if (bucketId == 0) return layout.activeTradesOfPartyA[owner];
		return layout.activeTradesOfPartyABucket[owner][bucketId];
	}

	function activeTradesOfPartyB(address owner, uint256 bucketId, address collateral) internal view returns (uint256[] storage) {
		TradeStorage.Layout storage layout = TradeStorage.layout();
		if (bucketId == 0) return layout.activeTradesOfPartyB[owner][collateral];
		return layout.activeTradesOfPartyBBucket[owner][bucketId][collateral];
	}

	function register(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		uint256[] storage partyATrades = activeTradesOfPartyA(self.partyA, self.partyABucketId);
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		uint256[] storage partyBTrades = activeTradesOfPartyB(self.partyB, self.partyBBucketId, symbol.collateral);

		if (partyATrades.length >= AppStorage.layout().maxTradePerPartyA)
			revert TradeErrors.TooManyActiveTradesForPartyA(self.partyA, partyATrades.length, AppStorage.layout().maxTradePerPartyA);
		tradeLayout.trades[self.id] = self;
		partyATrades.push(self.id);
		partyBTrades.push(self.id);
		tradeLayout.partyATradesIndex[self.id] = partyATrades.length - 1;
		tradeLayout.partyBTradesIndex[self.id] = partyBTrades.length - 1;
		if (self.partyABucketId == 0 && self.partyBBucketId == 0)
			tradeLayout.activeTradesOfPartyAWithPartyBCount[self.partyA][symbol.collateral][self.partyB]++;
		else tradeLayout.activeTradesOfBucketPairCount[self.partyA][self.partyABucketId][symbol.collateral][self.partyB][self.partyBBucketId]++;
		self.partyA.balanceOf(self.partyABucketId, symbol.collateral).addCounterParty(self.partyB, self.partyBBucketId);
	}

	function unregister(Trade memory self) internal {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		uint256[] storage partyATrades = activeTradesOfPartyA(self.partyA, self.partyABucketId);
		uint256[] storage partyBTrades = activeTradesOfPartyB(self.partyB, self.partyBBucketId, symbol.collateral);
		uint256 index = tradeLayout.partyATradesIndex[self.id];
		uint256 lastTradeId = partyATrades[partyATrades.length - 1];
		partyATrades[index] = lastTradeId;
		tradeLayout.partyATradesIndex[lastTradeId] = index;
		partyATrades.pop();
		index = tradeLayout.partyBTradesIndex[self.id];
		lastTradeId = partyBTrades[partyBTrades.length - 1];
		partyBTrades[index] = lastTradeId;
		tradeLayout.partyBTradesIndex[lastTradeId] = index;
		partyBTrades.pop();
		delete tradeLayout.partyATradesIndex[self.id];
		delete tradeLayout.partyBTradesIndex[self.id];
		if (self.partyABucketId == 0 && self.partyBBucketId == 0)
			tradeLayout.activeTradesOfPartyAWithPartyBCount[self.partyA][symbol.collateral][self.partyB]--;
		else tradeLayout.activeTradesOfBucketPairCount[self.partyA][self.partyABucketId][symbol.collateral][self.partyB][self.partyBBucketId]--;
		self.partyA.balanceOf(self.partyABucketId, symbol.collateral).tryRemoveCounterParty(self.partyB, self.partyBBucketId);
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
