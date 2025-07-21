// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { TradeStorage } from "../../storages/TradeStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { Trade } from "../../types/TradeTypes.sol";
import { CloseIntent, CloseIntentStatus } from "../../types/IntentTypes.sol";
import { FeeStructure } from "../../types/BaseTypes.sol";
import { ScheduledReleaseBalance, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";

library LibCloseIntentOps {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function calculateFee(CloseIntent memory self, uint256 rate, uint256 quantity, uint256 price) internal pure returns (uint256) {
		return (quantity * price * rate) / (self.feeStructure.tokenPriceInCollateral * 1e18);
	}

	/**
	 * @notice Gets the index of an item in an array.
	 * @param array_ The array in which to search for the item.
	 * @param item The item to find the index of.
	 * @return The index of the item in the array, or type(uint256).max if the item is not found.
	 */
	function getIndexOfItem(uint256[] storage array_, uint256 item) internal view returns (uint256) {
		for (uint256 index = 0; index < array_.length; index++) {
			if (array_[index] == item) return index;
		}
		return type(uint256).max;
	}

	/**
	 * @notice Removes an item from an array.
	 * @param array_ The array from which to remove the item.
	 * @param item The item to remove from the array.
	 */
	function removeFromArray(uint256[] storage array_, uint256 item) internal {
		uint256 index = getIndexOfItem(array_, item); // Should always be found
		array_[index] = array_[array_.length - 1];
		array_.pop();
	}

	function register(CloseIntent memory self) internal {
		Trade storage trade = TradeStorage.layout().trades[self.tradeId];
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		closeIntentLayout.closeIntents[self.id] = self;
		closeIntentLayout.closeIntentIdsOf[trade.id].push(self.id);
		trade.activeCloseIntentIds.push(self.id);
		trade.closePendingAmount += self.quantity;
	}

	function unregister(CloseIntent memory self) internal {
		Trade storage trade = TradeStorage.layout().trades[self.tradeId];
		removeFromArray(trade.activeCloseIntentIds, self.id);
		trade.closePendingAmount -= self.quantity;
	}

	function expire(CloseIntent storage self) internal {
		if (block.timestamp <= self.deadline) revert IntentErrors.IntentNotExpired(self.id, block.timestamp, self.deadline);

		if (self.status != CloseIntentStatus.PENDING && self.status != CloseIntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(CloseIntentStatus.PENDING);
			requiredStatuses[1] = uint8(CloseIntentStatus.CANCEL_PENDING);
			revert ValidationErrors.InvalidState("CloseIntentStatus", uint8(self.status), requiredStatuses);
		}

		self.statusModifyTimestamp = block.timestamp;
		self.status = CloseIntentStatus.EXPIRED;
		unregister(self);
	}

	function getFeesFromUser(CloseIntent memory self, uint256 quantity, uint256 price) internal returns (uint256[3] memory) {
		Trade storage trade = TradeStorage.layout().trades[self.tradeId];
		FeeStructure memory s = self.feeStructure;
		ScheduledReleaseBalance storage bal = trade.partyA.balanceOf(s.feeToken);

		uint256[3] memory fees = [
			calculateFee(self, s.platformFee.closeFee, quantity, price),
			calculateFee(self, s.affiliateFee.closeFee, quantity, price),
			calculateFee(self, s.solverFee.closeFee, quantity, price)
		];

		DecreaseBalanceReason[3] memory decReasons = [
			DecreaseBalanceReason.PLATFORM_FEE,
			DecreaseBalanceReason.AFFILIATE_FEE,
			DecreaseBalanceReason.SOLVER_FEE
		];

		for (uint8 i; i < 3; ++i) bal.subForCounterParty(trade.partyB, fees[i], trade.tradeAgreements.marginType, decReasons[i]);
		return fees;
	}
}
