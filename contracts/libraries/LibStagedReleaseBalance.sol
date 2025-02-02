// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.18;

import "../storages/AccountStorage.sol";

// StagedReleaseEntry implements a two-stage fund release system:
// - Funds start in 'queued' stage
// - Move to 'pending' at first interval
// - Become available at second interval
// - System uses periodic "bus arrivals" to transition funds between stages

// @title StagedReleaseEntry
// @notice Manages a single staged release entry using a bus schedule model
struct StagedReleaseEntry {
	uint256 releaseInterval; // Duration between transitions
	uint256 pending; // Funds ready for next release
	uint256 queued; // Funds waiting for future release
	uint256 lastTransitionTimestamp; // Last transition timestamp
}

// @title StagedReleaseBalance
// @notice Combines immediate and staged release funds per partyB
struct StagedReleaseBalance {
	uint256 available; // Immediately accessible funds
	mapping(address => StagedReleaseEntry) partyBStages; // Stage entries per partyB
}

// @title StagedReleaseBalanceOps
// @notice Operations for managing staged release balances
library StagedReleaseBalanceOps {
	// @notice Adds funds to release queue
	// @dev Initializes entry if needed, syncs state before adding
	function add(
		StagedReleaseBalance storage self,
		address partyB,
		uint256 value,
		uint256 timestamp
	) internal returns (StagedReleaseBalance storage) {
		StagedReleaseEntry storage entry = self.partyBStages[partyB];

		if (entry.releaseInterval == 0) {
			entry.releaseInterval = AccountStorage.layout().defaultReleaseInterval;
			entry.pending = 0;
			entry.queued = 0;
			entry.lastTransitionTimestamp = (timestamp / entry.releaseInterval) * entry.releaseInterval;
		} else {
			sync(self, partyB, timestamp);
		}

		require(entry.releaseInterval > 0, "StagedReleaseBalance: Use instant add for zero release interval");

		entry.queued += value;
		return self;
	}

	// @notice Adds funds directly to available balance
	function instantAdd(StagedReleaseBalance storage self, uint256 value) internal returns (StagedReleaseBalance storage) {
		self.available += value;
		return self;
	}

	// @notice Deducts funds from available balance only
	function sub(StagedReleaseBalance storage self, uint256 value) internal returns (StagedReleaseBalance storage) {
		require(self.available >= value, "StagedReleaseBalance: Insufficient balance");
		self.available -= value;
		return self;
	}

	// @notice Deducts funds from available, pending, then queued balances for a specific partyB
	function subForPartyB(StagedReleaseBalance storage self, address partyB, uint256 value) internal returns (StagedReleaseBalance storage) {
		require(partyB != address(0), "StagedReleaseBalance: Invalid partyB address");
		sync(self, partyB, block.timestamp);
		StagedReleaseEntry storage entry = self.partyBStages[partyB];

		uint256 totalBalance = self.available + entry.pending + entry.queued;
		require(totalBalance >= value, "StagedReleaseBalance: Insufficient balance");

		if (self.available >= value) {
			self.available -= value;
			return self;
		}

		uint256 remaining = value - self.available;
		self.available = 0;

		if (entry.pending >= remaining) {
			entry.pending -= remaining;
			return self;
		}

		remaining -= entry.pending;
		entry.pending = 0;
		entry.queued -= remaining;
		return self;
	}

	// @notice Returns the total balance for a specific partyB including available, pending and queued funds
	function partyBBalance(StagedReleaseBalance storage self, address partyB) internal view returns (uint256) {
		StagedReleaseEntry storage entry = self.partyBStages[partyB];
		return self.available + entry.pending + entry.queued;
	}

	// @notice Updates fund states based on elapsed time intervals
	// @dev Moves funds through stages based on timestamp checkpoints
	function sync(StagedReleaseBalance storage self, address partyB, uint256 timestamp) internal returns (StagedReleaseBalance storage) {
		StagedReleaseEntry storage entry = self.partyBStages[partyB];

		require(entry.releaseInterval > 0, "StagedReleaseBalance: Can't sync zero release interval");
		require(timestamp >= entry.lastTransitionTimestamp, "StagedReleaseBalance: Invalid sync timestamp");

		uint256 thisTransitionTimestamp = entry.lastTransitionTimestamp + entry.releaseInterval;
		uint256 nextTransitionTimestamp = entry.lastTransitionTimestamp + (entry.releaseInterval * 2);

		if (timestamp >= thisTransitionTimestamp) {
			self.available += entry.pending;
			if (timestamp < nextTransitionTimestamp) {
				entry.pending = entry.queued;
				entry.queued = 0;
			} else {
				entry.pending = 0;
			}
		}

		if (timestamp >= nextTransitionTimestamp) {
			self.available += entry.queued;
			entry.queued = 0;
		}

		entry.lastTransitionTimestamp = (timestamp / entry.releaseInterval) * entry.releaseInterval;
		return self;
	}

	// @notice Updates the release interval
	// @dev Only allowed when no funds are in transition
	function setReleaseInterval(
		StagedReleaseBalance storage self,
		address partyB,
		uint256 newReleaseInterval,
		uint256 timestamp
	) internal returns (StagedReleaseBalance storage) {
		sync(self, partyB, timestamp);
		StagedReleaseEntry storage entry = self.partyBStages[partyB];
		require(
			entry.queued == 0 && entry.pending == 0,
			"StagedReleaseBalance: There should be no pending/queued balance when updating release interval"
		);
		require(newReleaseInterval > 0, "StagedReleaseBalance: newReleaseInterval must be greater than 0");

		entry.releaseInterval = newReleaseInterval;
		return self;
	}
}
