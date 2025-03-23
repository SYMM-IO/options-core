// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { AppStorage } from "../storages/AppStorage.sol";
import { OpenIntent, IntentStorage, IntentStatus } from "../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../storages/SymbolStorage.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "./LibScheduledReleaseBalance.sol";

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

	function saveForPartyB(OpenIntent memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		intentLayout.openIntentsOf[self.partyB].push(self.id);
		intentLayout.activeOpenIntentsOf[self.partyB].push(self.id);
		intentLayout.partyBOpenIntentsIndex[self.id] = intentLayout.activeOpenIntentsOf[self.partyB].length - 1;
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

	function expire(OpenIntent storage self) internal {
		require(block.timestamp > self.deadline, "LibIntent: intent isn't expired");
		require(
			self.status == IntentStatus.PENDING || self.status == IntentStatus.CANCEL_PENDING || self.status == IntentStatus.LOCKED,
			"LibIntent: Invalid state"
		);

		self.status = IntentStatus.EXPIRED;
		self.statusModifyTimestamp = block.timestamp;

		returnFeesAndPremium(self);
		remove(self, false);
	}

	function getFeesAndPremium(OpenIntent memory self) internal {
		handleFeesAndPremium(self, true);
	}

	function returnFeesAndPremium(OpenIntent memory self) internal {
		handleFeesAndPremium(self, false);
	}

	function handleFeesAndPremium(OpenIntent memory self, bool isGetting) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[self.partyA][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[self.partyA][self.tradingFee.feeToken];

		uint256 tradingFee = getTradingFee(self);
		uint256 affiliateFee = getAffiliateFee(self);
		uint256 premium = getPremium(self);

		if (self.partyBsWhiteList.length == 1) {
			if (isGetting) {
				partyAFeeBalance.subForPartyB(self.partyBsWhiteList[0], tradingFee + affiliateFee);
				partyABalance.subForPartyB(self.partyBsWhiteList[0], premium);
			} else {
				partyAFeeBalance.scheduledAdd(self.partyBsWhiteList[0], tradingFee + affiliateFee);
				partyABalance.scheduledAdd(self.partyBsWhiteList[0], premium);
			}
		} else {
			if (isGetting) {
				partyAFeeBalance.sub(tradingFee + affiliateFee);
				partyABalance.sub(premium);
			} else {
				partyAFeeBalance.instantAdd(self.tradingFee.feeToken, tradingFee + affiliateFee);
				partyABalance.instantAdd(symbol.collateral, premium);
			}
		}
	}
}
