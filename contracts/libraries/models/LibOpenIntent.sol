// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";

library LibOpenIntentOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function getTradingFee(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price * self.tradingFee.platformFee) / (self.tradingFee.tokenPriceInCollateral * 1e18);
	}

	function getAffiliateFee(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price * self.tradingFee.affiliateFee) / (self.tradingFee.tokenPriceInCollateral * 1e18);
	}

	function getPremium(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price) / 1e18;
	}

	function save(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		openIntentLayout.openIntents[self.id] = self;
		openIntentLayout.openIntentsOf[msg.sender].push(self.id);

		if (self.status == OpenIntentStatus.PENDING) {
			openIntentLayout.activeOpenIntentsOf[self.partyA].push(self.id);
			openIntentLayout.activeOpenIntentsCount[self.partyA] += 1;
			openIntentLayout.partyAOpenIntentsIndex[self.id] = openIntentLayout.activeOpenIntentsOf[self.partyA].length - 1;
		}
	}

	function saveForPartyB(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		openIntentLayout.openIntentsOf[self.partyB].push(self.id);
		openIntentLayout.activeOpenIntentsOf[self.partyB].push(self.id);
		openIntentLayout.partyBOpenIntentsIndex[self.id] = openIntentLayout.activeOpenIntentsOf[self.partyB].length - 1;
	}

	function remove(OpenIntent memory self, bool fromPartyBOnly) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		if (!fromPartyBOnly) {
			uint256 indexOfIntent = openIntentLayout.partyAOpenIntentsIndex[self.id];
			uint256 lastIndex = openIntentLayout.activeOpenIntentsOf[self.partyA].length - 1;
			openIntentLayout.activeOpenIntentsOf[self.partyA][indexOfIntent] = openIntentLayout.activeOpenIntentsOf[self.partyA][lastIndex];
			openIntentLayout.partyAOpenIntentsIndex[openIntentLayout.activeOpenIntentsOf[self.partyA][lastIndex]] = indexOfIntent;
			openIntentLayout.activeOpenIntentsOf[self.partyA].pop();
			openIntentLayout.partyAOpenIntentsIndex[self.id] = 0;
			openIntentLayout.activeOpenIntentsCount[self.partyA] -= 1;
		}

		if (self.partyB != address(0)) {
			uint256 indexOfIntent = openIntentLayout.partyBOpenIntentsIndex[self.id];
			uint256 lastIndex = openIntentLayout.activeOpenIntentsOf[self.partyB].length - 1;
			openIntentLayout.activeOpenIntentsOf[self.partyB][indexOfIntent] = openIntentLayout.activeOpenIntentsOf[self.partyB][lastIndex];
			openIntentLayout.partyBOpenIntentsIndex[openIntentLayout.activeOpenIntentsOf[self.partyB][lastIndex]] = indexOfIntent;
			openIntentLayout.activeOpenIntentsOf[self.partyB].pop();
			openIntentLayout.partyBOpenIntentsIndex[self.id] = 0;
		}
	}

	function expire(OpenIntent storage self) internal {
		if (block.timestamp <= self.deadline) revert IntentErrors.IntentNotExpired(self.id, block.timestamp, self.deadline);

		if (!(self.status == OpenIntentStatus.PENDING || self.status == OpenIntentStatus.CANCEL_PENDING || self.status == OpenIntentStatus.LOCKED)) {
			uint8[] memory requiredStatuses = new uint8[](3);
			requiredStatuses[0] = uint8(OpenIntentStatus.PENDING);
			requiredStatuses[1] = uint8(OpenIntentStatus.CANCEL_PENDING);
			requiredStatuses[2] = uint8(OpenIntentStatus.LOCKED);

			revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(self.status), requiredStatuses);
		}

		self.status = OpenIntentStatus.EXPIRED;
		self.statusModifyTimestamp = block.timestamp;

		handleFeesAndPremium(self, false);
		remove(self, false);
	}

	function handleFeesAndPremium(OpenIntent memory self, bool isUserPaying) internal {
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyAFeeBalance = self.partyA.balanceOf(self.tradingFee.feeToken);

		uint256 tradingFee = getTradingFee(self);
		uint256 affiliateFee = getAffiliateFee(self);
		uint256 premium = getPremium(self);

		if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
			if (isUserPaying) {
				if (self.partyBsWhiteList.length == 1) {
					partyAFeeBalance.subForCounterParty(
						self.partyBsWhiteList[0],
						tradingFee + affiliateFee,
						self.tradeAgreements.marginType,
						DecreaseBalanceReason.FEE
					);
				} else {
					partyAFeeBalance.isolatedSub(tradingFee + affiliateFee, DecreaseBalanceReason.FEE);
				}
				partyABalance.isolatedLock(premium);
			} else {
				if (self.partyBsWhiteList.length == 1) {
					partyAFeeBalance.scheduledAdd(
						self.partyBsWhiteList[0],
						tradingFee + affiliateFee,
						self.tradeAgreements.marginType,
						IncreaseBalanceReason.FEE
					);
				} else {
					partyAFeeBalance.instantIsolatedAdd(tradingFee + affiliateFee, IncreaseBalanceReason.FEE);
				}

				partyABalance.isolatedUnlock(premium);
			}
		} else {
			if (isUserPaying) {
				partyAFeeBalance.subForCounterParty(
					self.partyBsWhiteList[0],
					tradingFee + affiliateFee,
					self.tradeAgreements.marginType,
					DecreaseBalanceReason.FEE
				);
				if (self.tradeAgreements.tradeSide == TradeSide.BUY) partyABalance.crossLock(self.partyBsWhiteList[0], premium);
				else partyABalance.crossLock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
			} else {
				partyAFeeBalance.scheduledAdd(
					self.partyBsWhiteList[0],
					tradingFee + affiliateFee,
					self.tradeAgreements.marginType,
					IncreaseBalanceReason.FEE
				);
				if (self.tradeAgreements.tradeSide == TradeSide.BUY) partyABalance.crossUnlock(self.partyBsWhiteList[0], premium);
				else partyABalance.crossUnlock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
			}
		}
	}
}
