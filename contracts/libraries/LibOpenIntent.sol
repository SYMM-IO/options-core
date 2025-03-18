// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/IntentStorage.sol";
import "../storages/AccountStorage.sol";
import "../storages/SymbolStorage.sol";
import "../storages/AppStorage.sol";

library LibOpenIntentOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function getTradingFee(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price * self.tradingFee.platformFee) / (self.tradingFee.tokenPrice * 1e18);
	}

	function getAffiliateFee(OpenIntent memory self) internal view returns (uint256) {
		uint256 affiliateFee = AppStorage.layout().affiliateFees[self.affiliate][self.tradeAgreements.symbolId];
		return (self.tradeAgreements.quantity * self.price * affiliateFee) / (self.tradingFee.tokenPrice * 1e18);
	}

	function getPremium(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price) / 1e18;
	}

	function save(OpenIntent memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		intentLayout.openIntents[self.id] = self;
		intentLayout.openIntentsOf[msg.sender].push(self.id);

		if (self.status == IntentStatus.PENDING) {
			intentLayout.activeOpenIntentsOf[self.partyA].push(self.id);
			intentLayout.activeOpenIntentsCount[self.partyA] += 1;
			intentLayout.partyAOpenIntentsIndex[self.id] = intentLayout.activeOpenIntentsOf[self.partyA].length - 1;
		}
	}

	function remove(OpenIntent memory self, bool fromPartyBOnly) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		if (!fromPartyBOnly) {
			uint256 indexOfIntent = intentLayout.partyAOpenIntentsIndex[self.id];
			uint256 lastIndex = intentLayout.activeOpenIntentsOf[self.partyA].length - 1;
			intentLayout.activeOpenIntentsOf[self.partyA][indexOfIntent] = intentLayout.activeOpenIntentsOf[self.partyA][lastIndex];
			intentLayout.partyAOpenIntentsIndex[intentLayout.activeOpenIntentsOf[self.partyA][lastIndex]] = indexOfIntent;
			intentLayout.activeOpenIntentsOf[self.partyA].pop();
			intentLayout.partyAOpenIntentsIndex[self.id] = 0;
			intentLayout.activeOpenIntentsCount[self.partyA] -= 1;
		}

		if (self.partyB != address(0)) {
			uint256 indexOfIntent = intentLayout.partyBOpenIntentsIndex[self.id];
			uint256 lastIndex = intentLayout.activeOpenIntentsOf[self.partyB].length - 1;
			intentLayout.activeOpenIntentsOf[self.partyB][indexOfIntent] = intentLayout.activeOpenIntentsOf[self.partyB][lastIndex];
			intentLayout.partyBOpenIntentsIndex[intentLayout.activeOpenIntentsOf[self.partyB][lastIndex]] = indexOfIntent;
			intentLayout.activeOpenIntentsOf[self.partyB].pop();
			intentLayout.partyBOpenIntentsIndex[self.id] = 0;
		}
	}

	function saveForPartyB(OpenIntent memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		intentLayout.openIntentsOf[self.partyB].push(self.id);
		intentLayout.activeOpenIntentsOf[self.partyB].push(self.id);
		intentLayout.partyBOpenIntentsIndex[self.id] = intentLayout.activeOpenIntentsOf[self.partyB].length - 1;
	}
}
