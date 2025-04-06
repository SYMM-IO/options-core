// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.19;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../storages/AppStorage.sol";
import { LibPartyB } from "../libraries/LibPartyB.sol";
import { CommonErrors } from "./CommonErrors.sol";

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
	address user; // Address of the user
	mapping(address => ScheduledReleaseEntry) partyBSchedules; // Scheduled entries per partyB
	mapping(address => uint256) partyBIndexes; // Index of partyB in the addresses array
	address[] partyBAddresses; // List of all partyB addresses
}

enum IncreaseBalanceType {
	DEPOSIT,
	INTERNAL_TRANSFER,
	BRIDGE,
	FEE,
	PREMIUM,
	REALIZED_PNL,
	LIQUIDATION
}

enum DecreaseBalanceType {
	WITHDRAW,
	INTERNAL_TRANSFER,
	BRIDGE,
	FEE,
	PREMIUM,
	REALIZED_PNL,
	CONFISCATE
}

// @title ScheduledReleaseBalanceOps
// @notice Operations for managing scheduled release balances
library ScheduledReleaseBalanceOps {
	using LibPartyB for address;

	event IncreaseBalance(address user, address collateral, uint256 amount, IncreaseBalanceType _type, bool isInstant);
	event DecreaseBalance(address user, address partyB, address collateral, uint256 amount, DecreaseBalanceType _type);
	event SyncBalance(address user, address partyB, address collateral);

	// Custom errors
	error MaxPartyBConnectionsReached(uint256 current, uint256 maximum);
	error InvalidSyncTimestamp(uint256 currentTime, uint256 lastTransitionTimestamp);
	error NonZeroBalancePartyB(address partyB, uint256 balance);
	error InsufficientBalance(address token, uint256 requested, uint256 available);
	error BalanceSetupRequired();

	modifier checkSetup(ScheduledReleaseBalance storage self) {
		if (self.collateral == address(0) || self.user == address(0)) revert BalanceSetupRequired();
		_;
	}

	function setup(
		ScheduledReleaseBalance storage self,
		address _user,
		address collateral
	) internal checkSetup(self) returns (ScheduledReleaseBalance storage) {
		self.collateral = collateral;
		self.user = _user;
		return self;
	}

	// @notice Adds funds to release schedule
	// @dev Initializes entry if needed, syncs state before adding
	function scheduledAdd(
		ScheduledReleaseBalance storage self,
		address partyB,
		uint256 value,
		IncreaseBalanceType _type
	) internal checkSetup(self) returns (ScheduledReleaseBalance storage) {
		_sync(self, partyB, false);

		if (AccountStorage.layout().partyBReleaseIntervals[partyB] == 0) {
			return instantAdd(self, value, _type);
		}

		addPartyB(self, partyB);
		self.partyBSchedules[partyB].scheduled += value;
		emit IncreaseBalance(self.user, self.collateral, value, _type, false);
		return self;
	}

	// @notice Adds funds directly to available balance
	function instantAdd(
		ScheduledReleaseBalance storage self,
		uint256 value,
		IncreaseBalanceType _type
	) internal returns (ScheduledReleaseBalance storage) {
		self.available += value;
		emit IncreaseBalance(self.user, self.collateral, value, _type, true);
		return self;
	}

	// @notice Deducts funds from available balance only
	function sub(ScheduledReleaseBalance storage self, uint256 value, DecreaseBalanceType _type) internal returns (ScheduledReleaseBalance storage) {
		if (self.available < value) revert InsufficientBalance(self.collateral, value, self.available);

		self.available -= value;
		emit DecreaseBalance(self.user, address(0), self.collateral, value, _type);
		return self;
	}

	// @notice Deducts funds from available, transitioning, then scheduled balances for a specific partyB
	function subForPartyB(
		ScheduledReleaseBalance storage self,
		address partyB,
		uint256 value,
		DecreaseBalanceType _type
	) internal returns (ScheduledReleaseBalance storage) {
		if (partyB == address(0)) revert CommonErrors.ZeroAddress("partyB");

		sync(self, partyB);
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		if (entry.releaseInterval == 0) {
			return sub(self, value, _type);
		}

		uint256 totalBalance = self.available + entry.transitioning + entry.scheduled;
		if (totalBalance < value) revert InsufficientBalance(self.collateral, value, totalBalance);

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
		emit DecreaseBalance(self.user, partyB, self.collateral, value, _type);
		return self;
	}

	// @notice Returns the total balance for a specific partyB including available, transitioning and scheduled funds
	function partyBBalance(ScheduledReleaseBalance storage self, address partyB) internal view returns (uint256) {
		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		return self.available + entry.transitioning + entry.scheduled;
	}

	// @notice Updates fund states based on elapsed time intervals
	// @dev Moves funds through stages based on timestamp checkpoints
	function sync(ScheduledReleaseBalance storage self, address partyB) internal returns (ScheduledReleaseBalance storage) {
		return _sync(self, partyB, true);
	}

	// @notice Updates fund states based on elapsed time intervals
	// @dev Moves funds through stages based on timestamp checkpoints
	function _sync(
		ScheduledReleaseBalance storage self,
		address partyB,
		bool removePartyBOnEmpty
	) internal returns (ScheduledReleaseBalance storage) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!partyB.isSolvent(self.collateral)) {
			return self;
		}

		if (self.partyBAddresses.length == 0 || self.partyBAddresses[self.partyBIndexes[partyB]] != partyB) {
			return self;
		}

		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];
		if (entry.releaseInterval != accountLayout.partyBReleaseIntervals[partyB]) {
			// release interval changed
			entry.releaseInterval = accountLayout.partyBReleaseIntervals[partyB];
			entry.lastTransitionTimestamp = entry.releaseInterval == 0
				? block.timestamp
				: (block.timestamp / entry.releaseInterval) * entry.releaseInterval;
			entry.scheduled += entry.transitioning;
			entry.transitioning = 0;
			emit SyncBalance(self.user, partyB, self.collateral);
			return self;
		}
		if (entry.releaseInterval == 0) return self;

		if (block.timestamp < entry.lastTransitionTimestamp) revert InvalidSyncTimestamp(block.timestamp, entry.lastTransitionTimestamp);

		uint256 thisTransitionTimestamp = entry.lastTransitionTimestamp + entry.releaseInterval;
		uint256 nextTransitionTimestamp = entry.lastTransitionTimestamp + (entry.releaseInterval * 2);

		if (block.timestamp >= thisTransitionTimestamp) {
			self.available += entry.transitioning;
			if (block.timestamp < nextTransitionTimestamp) {
				entry.transitioning = entry.scheduled;
				entry.scheduled = 0;
			} else {
				entry.transitioning = 0;
			}
		}

		if (block.timestamp >= nextTransitionTimestamp) {
			self.available += entry.scheduled;
			entry.scheduled = 0;
		}

		entry.lastTransitionTimestamp = (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

		if (removePartyBOnEmpty && entry.transitioning == 0 && entry.scheduled == 0) {
			removePartyB(self, partyB);
		}
		emit SyncBalance(self.user, partyB, self.collateral);
		return self;
	}

	// @notice Syncs all partyB balances
	function syncAll(ScheduledReleaseBalance storage self) internal returns (ScheduledReleaseBalance storage) {
		for (uint256 i = 0; i < self.partyBAddresses.length; i++) {
			sync(self, self.partyBAddresses[i]);
		}
		return self;
	}

	// @notice Adds a partyB to the scheduled release entries without adding funds
	// @dev Initializes entry with default release interval if not already present
	function addPartyB(ScheduledReleaseBalance storage self, address partyB) internal returns (ScheduledReleaseBalance storage) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// Check if partyB is already added
		if (self.partyBAddresses.length > 0 && self.partyBAddresses[self.partyBIndexes[partyB]] == partyB) return self;

		ScheduledReleaseEntry storage entry = self.partyBSchedules[partyB];

		if (self.partyBAddresses.length >= accountLayout.maxConnectedPartyBs)
			revert MaxPartyBConnectionsReached(self.partyBAddresses.length, accountLayout.maxConnectedPartyBs);

		entry.releaseInterval = accountLayout.partyBReleaseIntervals[partyB];
		entry.transitioning = 0;
		entry.scheduled = 0;
		entry.lastTransitionTimestamp = entry.releaseInterval == 0
			? block.timestamp
			: (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

		// Add to tracking arrays
		self.partyBIndexes[partyB] = self.partyBAddresses.length;
		self.partyBAddresses.push(partyB);

		return self;
	}

	// @notice Removes a partyB from tracking when they have no balance
	function removePartyB(ScheduledReleaseBalance storage self, address partyB) internal returns (ScheduledReleaseBalance storage) {
		if (partyB == address(0)) revert CommonErrors.ZeroAddress("partyB");

		uint256 balance = partyBBalance(self, partyB);
		if (balance != 0) revert NonZeroBalancePartyB(partyB, balance);

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
