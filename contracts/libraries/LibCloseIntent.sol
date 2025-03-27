// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { CloseIntent, IntentStorage, Trade, IntentStatus } from "../storages/IntentStorage.sol";
import { CommonErrors } from "./CommonErrors.sol";

library LibCloseIntentOps {
	// Custom errors
	error ItemNotFound(uint256 item);
	error IntentNotExpired(uint256 intentId, uint256 currentTime, uint256 deadline);

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
		uint256 index = getIndexOfItem(array_, item);
		if (index == type(uint256).max) revert ItemNotFound(item);
		array_[index] = array_[array_.length - 1];
		array_.pop();
	}

	function save(CloseIntent memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[self.tradeId];
		intentLayout.closeIntents[self.id] = self;
		intentLayout.closeIntentIdsOf[trade.id].push(self.id);
		trade.activeCloseIntentIds.push(self.id);
		trade.closePendingAmount += self.quantity;
	}

	function remove(CloseIntent memory self) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[self.tradeId];
		removeFromArray(trade.activeCloseIntentIds, self.id);
		trade.closePendingAmount -= self.quantity;
	}

	function expire(CloseIntent storage self) internal {
		if (block.timestamp <= self.deadline) revert IntentNotExpired(self.id, block.timestamp, self.deadline);

		if (self.status != IntentStatus.PENDING && self.status != IntentStatus.CANCEL_PENDING) {
			uint8[] memory requiredStatuses = new uint8[](2);
			requiredStatuses[0] = uint8(IntentStatus.PENDING);
			requiredStatuses[1] = uint8(IntentStatus.CANCEL_PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(self.status), requiredStatuses);
		}

		self.statusModifyTimestamp = block.timestamp;
		self.status = IntentStatus.EXPIRED;
		remove(self);
	}
}
