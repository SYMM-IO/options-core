// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";

import { TradeSide, MarginType, FeeStructure, FeeOp } from "../../types/BaseTypes.sol";
import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";

library LibOpenIntentOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function calculateFeeAmount(OpenIntent memory self, uint256 rate) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price * rate) / (self.feeStructure.tokenPriceInCollateral * 1e18);
	}

	function calculatePremiumAmount(OpenIntent memory self) internal pure returns (uint256) {
		return (self.tradeAgreements.quantity * self.price) / 1e18;
	}

	function save(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		openIntentLayout.openIntents[self.id] = self;

		if (self.status == OpenIntentStatus.PENDING) {
			openIntentLayout.activeOpenIntentsOf[self.partyA].push(self.id);
			openIntentLayout.activeOpenIntentsCount[self.partyA] += 1;
			openIntentLayout.partyAOpenIntentsIndex[self.id] = openIntentLayout.activeOpenIntentsOf[self.partyA].length - 1;
		}
	}

	function saveForPartyB(OpenIntent memory self) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

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

		returnFeesToUser(self);
		unlockPremium(self);
		unlockMaintenanceMargin(self);
		remove(self, false);
	}

	function _handleFees(OpenIntent memory self, FeeOp op) internal {
		FeeStructure memory s = self.feeStructure;
		bool isolated = self.tradeAgreements.marginType == MarginType.ISOLATED;
		bool singlePartyB = self.partyBsWhiteList.length == 1;
		address partyB = self.partyBsWhiteList[0];

		ScheduledReleaseBalance storage bal = self.partyA.balanceOf(s.feeToken);

		uint256[3] memory fees = [
			calculateFeeAmount(self, s.platformFee.openFee),
			calculateFeeAmount(self, s.affiliateFee.openFee),
			calculateFeeAmount(self, s.solverFee.openFee)
		];

		DecreaseBalanceReason[3] memory decReasons = [
			DecreaseBalanceReason.PLATFORM_FEE,
			DecreaseBalanceReason.AFFILIATE_FEE,
			DecreaseBalanceReason.SOLVER_FEE
		];
		IncreaseBalanceReason[3] memory incReasons = [
			IncreaseBalanceReason.PLATFORM_FEE,
			IncreaseBalanceReason.AFFILIATE_FEE,
			IncreaseBalanceReason.SOLVER_FEE
		];

		for (uint8 i; i < 3; ++i) {
			if (op == FeeOp.Subtract) {
				if (isolated && !singlePartyB) {
					bal.isolatedSub(fees[i], decReasons[i]);
				} else {
					bal.subForCounterParty(partyB, fees[i], self.tradeAgreements.marginType, decReasons[i]);
				}
			} else {
				if (isolated && !singlePartyB) {
					bal.instantIsolatedAdd(fees[i], incReasons[i]);
				} else {
					bal.scheduledAdd(partyB, fees[i], self.tradeAgreements.marginType, incReasons[i]);
				}
			}
		}
	}

	function getFeesFromUser(OpenIntent memory self) internal {
		_handleFees(self, FeeOp.Subtract);
	}

	function returnFeesToUser(OpenIntent memory self) internal {
		_handleFees(self, FeeOp.Add);
	}

	function lockPremium(OpenIntent memory self) internal {
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(symbol.collateral);

		if (self.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
				partyABalance.isolatedLock(self.tradeAgreements.mm);
			} else {
				partyABalance.crossLock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
			}
		}
	}

	function unlockPremium(OpenIntent memory self) internal {
		Symbol memory symbol = SymbolStorage.layout().symbols[self.tradeAgreements.symbolId];
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(symbol.collateral);

		if (self.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (self.tradeAgreements.marginType == MarginType.ISOLATED) {
				partyABalance.isolatedUnlock(self.tradeAgreements.mm);
			} else {
				partyABalance.crossUnlock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
			}
		}
	}

	function lockMaintenanceMargin(OpenIntent memory self) internal {
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(
			SymbolStorage.layout().symbols[self.tradeAgreements.symbolId].collateral
		);
		if (self.tradeAgreements.tradeSide == TradeSide.SELL) {
			partyABalance.crossLock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
		}
	}

	function unlockMaintenanceMargin(OpenIntent memory self) internal {
		ScheduledReleaseBalance storage partyABalance = self.partyA.balanceOf(
			SymbolStorage.layout().symbols[self.tradeAgreements.symbolId].collateral
		);
		if (self.tradeAgreements.tradeSide == TradeSide.SELL) {
			partyABalance.crossUnlock(self.partyBsWhiteList[0], self.tradeAgreements.mm);
		}
	}
}
