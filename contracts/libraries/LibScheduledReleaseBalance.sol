// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.18;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../storages/AppStorage.sol";

// ScheduledReleaseEntry implements a two-stage fund release system:
// - Funds start in 'scheduled' stage
// - Move to 'transitioning' at first interval
// - Become available at second interval
// - System uses periodic "bus arrivals" to transition funds between stages

// @title ScheduledReleaseEntry
// @notice Manages a single scheduled release entry using a bus schedule model
struct ScheduledReleaseEntry {
	uint256 releaseInterval; // Duration between transitions
	uint256 transitioning; // Funds ready for next release
	uint256 scheduled; // Funds waiting for future release
	uint256 lastTransitionTimestamp; // Last transition timestamp
}

// @title ScheduledReleaseBalance
// @notice Combines immediate and scheduled release funds per partyB
struct ScheduledReleaseBalance {
	uint256 available; // Immediately accessible funds
	address collateral; // Address of the collateral asset
	mapping(address => ScheduledReleaseEntry) partyBSchedules; // Scheduled entries per partyB
	mapping(address => uint256) partyBIndexes; // Index of partyB in the addresses array
	address[] partyBAddresses; // List of all partyB addresses
}

// @title ScheduledReleaseBalanceOps
// @notice Operations for managing scheduled release balances
library ScheduledReleaseBalanceOps {
	// @notice Adds funds to release schedule
	// @dev Initializes entry if needed, syncs state before adding
	function scheduledAdd(
		ScheduledReleaseBalance storage self,
		address partyB,
		uint256 value,
		uint256 timestamp
	) internal returns (ScheduledReleaseBalance storage) {
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];

		if (self.partyBAddresses.length == 0 || self.partyBAddresses[self.partyBIndexes[partyB]] != partyB) {
			addPartyB(self, partyB, timestamp);
		} else {
			sync(self, partyB, timestamp);
		}

		if (entry.releaseInterval == 0) {
			return instantAdd(self, self.collateral, value);
		}

		entry.scheduled += value;
		return self;
	}

	// @notice Adds a partyB to the scheduled release entries without adding funds
	// @dev Initializes entry with default release interval if not already present
	function addPartyB(ScheduledReleaseBalance storage self, address partyB, uint256 timestamp) internal returns (ScheduledReleaseBalance storage) {
		// Check if partyB is already added
		if (self.partyBAddresses.length > 0 && self.partyBAddresses[self.partyBIndexes[partyB]] == partyB) return self;

		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];

		require(self.partyBAddresses.length < AccountStorage.layout().maxConnectedPartyBs, "StagedReleaseBalance: Max partyB connections reached");
		entry.releaseInterval = AccountStorage.layout().partyBReleaseIntervals[partyB];
		entry.transitioning = 0;
		entry.scheduled = 0;
		entry.lastTransitionTimestamp = entry.releaseInterval == 0 ? timestamp : (timestamp / entry.releaseInterval) * entry.releaseInterval;

		// Add to tracking arrays
		self.partyBIndexes[partyB] = self.partyBAddresses.length;
		self.partyBAddresses.push(partyB);

		return self;
	}

	// @notice Adds funds directly to available balance
	function instantAdd(ScheduledReleaseBalance storage self, address collateral, uint256 value) internal returns (ScheduledReleaseBalance storage) {
		// Initialize collateral if it's the first usage
		if (self.collateral == address(0)) {
			self.collateral = collateral;
		} else {
			require(self.collateral == collateral, "ScheduledReleaseBalance: Collateral mismatch");
		}
		self.available += value;
		return self;
	}

	// @notice Deducts funds from available balance only
	function sub(ScheduledReleaseBalance storage self, uint256 value) internal returns (ScheduledReleaseBalance storage) {
		require(self.available >= value, "StagedReleaseBalance: Insufficient balance");
		self.available -= value;
		return self;
	}

	// @notice Deducts funds from available, transitioning, then scheduled balances for a specific partyB
	function subForPartyB(ScheduledReleaseBalance storage self, address partyB, uint256 value) internal returns (ScheduledReleaseBalance storage) {
		require(partyB != address(0), "StagedReleaseBalance: Invalid partyB address");
		sync(self, partyB, block.timestamp);
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		if (entry.releaseInterval == 0) {
			return sub(self, value);
		}

		uint256 totalBalance = self.available + entry.transitioning + entry.scheduled;
		require(totalBalance >= value, "StagedReleaseBalance: Insufficient balance");

		uint256 remaining = value;

		// First use queued funds
		if (entry.scheduled >= remaining) {
			entry.scheduled -= remaining;
			return self;
		}

		if (entry.scheduled > 0) {
			remaining -= entry.scheduled;
			entry.scheduled = 0;
		}

		// Then use pending funds
		if (entry.transitioning >= remaining) {
			entry.transitioning -= remaining;
			return self;
		}

		if (entry.transitioning > 0) {
			remaining -= entry.transitioning;
			entry.transitioning = 0;
		}

		// Finally use available funds
		self.available -= remaining;
		return self;
	}

	// @notice Returns the total balance for a specific partyB including available, transitioning and scheduled funds
	function partyBBalance(ScheduledReleaseBalance storage self, address partyB) internal view returns (uint256) {
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		return self.available + entry.transitioning + entry.scheduled;
	}

	// @notice Updates fund states based on elapsed time intervals
	// @dev Moves funds through stages based on timestamp checkpoints
	function sync(ScheduledReleaseBalance storage self, address partyB, uint256 timestamp) internal returns (ScheduledReleaseBalance storage) {
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		if (entry.releaseInterval != AccountStorage.layout().partyBReleaseIntervals[partyB]) {
			// release interval changed
			entry.releaseInterval = AccountStorage.layout().partyBReleaseIntervals[partyB];
			entry.lastTransitionTimestamp = entry.releaseInterval == 0 ? timestamp : (timestamp / entry.releaseInterval) * entry.releaseInterval;
			entry.scheduled += entry.transitioning;
			entry.transitioning = 0;
			return self;
		}
		if (entry.releaseInterval == 0) return self;
		require(timestamp >= entry.lastTransitionTimestamp, "StagedReleaseBalance: Invalid sync timestamp");
		if (AppStorage.layout().liquidationDetails[partyB][self.collateral].status != LiquidationStatus.SOLVENT) {
			return self;
		}
		uint256 thisTransitionTimestamp = entry.lastTransitionTimestamp + entry.releaseInterval;
		uint256 nextTransitionTimestamp = entry.lastTransitionTimestamp + (entry.releaseInterval * 2);

		if (timestamp >= thisTransitionTimestamp) {
			self.available += entry.transitioning;
			if (timestamp < nextTransitionTimestamp) {
				entry.transitioning = entry.scheduled;
				entry.scheduled = 0;
			} else {
				entry.transitioning = 0;
			}
		}

		if (timestamp >= nextTransitionTimestamp) {
			self.available += entry.scheduled;
			entry.scheduled = 0;
		}

		entry.lastTransitionTimestamp = (timestamp / entry.releaseInterval) * entry.releaseInterval;
		return self;
	}

	// @notice Syncs all partyB balances
	function syncAll(ScheduledReleaseBalance storage self, uint256 timestamp) internal returns (ScheduledReleaseBalance storage) {
		for (uint256 i = 0; i < self.partyBAddresses.length; i++) {
			sync(self, self.partyBAddresses[i], timestamp);
		}
		return self;
	}

	// @notice Removes a partyB from tracking when they have no balance
	function removePartyB(ScheduledReleaseBalance storage self, address partyB) internal returns (ScheduledReleaseBalance storage) {
		require(partyB != address(0), "StagedReleaseBalance: Invalid partyB address");
		require(partyBBalance(self, partyB) == 0, "StagedReleaseBalance: Cannot clear slot with non-zero balance");

		uint256 index = self.partyBIndexes[partyB];
		uint256 lastIndex = self.partyBAddresses.length - 1;

		// If this isn't the last element, move the last element to this position
		if (index != lastIndex) {
			address lastPartyB = self.partyBAddresses[lastIndex];
			self.partyBAddresses[index] = lastPartyB;
			self.partyBIndexes[lastPartyB] = index;
		}

		// Remove last element
		self.partyBAddresses.pop();
		delete self.partyBIndexes[partyB];
		delete self.partyBSchedules[partyB];

		return self;
	}
}
