// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/SymbolStorage.sol";
import "../libraries/LibCloseIntent.sol";

library LibTradeOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;

	function tradeOpenAmount(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration;
	}

	function getAvailableAmountToClose(Trade memory self) internal pure returns (uint256) {
		return self.tradeAgreements.quantity - self.closedAmountBeforeExpiration - self.closePendingAmount;
	}

	function getValueOfTradeForPartyA(Trade memory self, uint256 currentPrice, uint256 filledAmount) internal view returns (uint256 pnl) {
		Symbol storage symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];

		if (currentPrice > self.tradeAgreements.strikePrice && symbol.optionType == OptionType.CALL) {
			pnl = ((currentPrice - self.tradeAgreements.strikePrice) * filledAmount) / 1e18;
		} else if (currentPrice < self.tradeAgreements.strikePrice && symbol.optionType == OptionType.PUT) {
			pnl = ((self.tradeAgreements.strikePrice - currentPrice) * filledAmount) / 1e18;
		}
	}

	function save(Trade memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		intentLayout.tradesOf[self.partyA].push(self.id);
		intentLayout.tradesOf[self.partyB].push(self.id);
		intentLayout.activeTradesOf[self.partyA].push(self.id);
		intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].push(self.id);

		intentLayout.partyATradesIndex[self.id] = intentLayout.activeTradesOf[self.partyA].length - 1;
		intentLayout.partyBTradesIndex[self.id] = intentLayout.activeTradesOfPartyB[self.partyB][symbol.collateral].length - 1;

		AccountStorage.layout().balances[self.partyA][symbol.collateral].addPartyB(self.partyB, block.timestamp);
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
		uint256 len = self.activeCloseIntentIds.length;
		for (uint8 i = 0; i < len; i++) {
			CloseIntent storage intent = IntentStorage.layout().closeIntents[self.activeCloseIntentIds[0]];
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = intentStatus;
			intent.remove();
		}
		self.status = tradeStatus;
		self.statusModifyTimestamp = block.timestamp;
		remove(self);
	}
}
