// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023‑2025 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.19;

import { AccountStorage } from "../storages/AccountStorage.sol";
import { ScheduledReleaseBalance, ScheduledReleaseEntry, IncreaseBalanceReason, DecreaseBalanceReason } from "../types/BalanceTypes.sol";
import { MarginType } from "../types/BaseTypes.sol";
import { LibParty } from "../libraries/LibParty.sol";
import { CommonErrors } from "./CommonErrors.sol";

/// @title ScheduledReleaseBalanceOps
/// @notice Collection of helper functions to operate on {@link ScheduledReleaseBalance}.
///         All functions operate directly on storage using an explicit struct
///         reference (`self`) and therefore have **no** external visibility.
///         The library emits granular events so that indexers can recreate the
///         full margin state without loading contract storage.
library ScheduledReleaseBalanceOps {
	using LibParty for address;

	// ─── events ───────────────────────────────────────────────────────────────

	event IncreaseBalance(
		address indexed user,
		address indexed counterParty,
		address indexed collateral,
		uint256 amount,
		IncreaseBalanceReason reason,
		bool isInstant,
		MarginType marginType
	);

	event DecreaseBalance(
		address indexed user,
		address indexed counterParty,
		address indexed collateral,
		uint256 amount,
		DecreaseBalanceReason reason,
		MarginType marginType
	);

	event SyncBalance(address indexed user, address indexed counterParty, address indexed collateral, MarginType marginType);
	event AllocateBalance(address indexed user, address indexed counterParty, address indexed collateral, uint256 amount);
	event DeallocateBalance(address indexed user, address indexed counterParty, address indexed collateral, uint256 amount);

	// ─── custom errors ────────────────────────────────────────────────────────

	error MaxCounterPartyConnectionsReached(uint256 current, uint256 maximum);
	error InvalidSyncTimestamp(uint256 currentTime, uint256 lastTransitionTimestamp);
	error NonZeroBalanceCounterParty(address counterParty, int256 balance);
	error InsufficientBalance(address token, uint256 requested, int256 balance);
	error InsufficientLockedBalance(address token, uint256 requested, uint256 balance);
	error InsufficientMMBalance(address token, uint256 requested, uint256 balance);
	error BalanceSetupRequired();

	// ─── modifiers ────────────────────────────────────────────────────────────

	/// @dev Reverts unless the balance slot has been initialized via `setup`.
	modifier checkSetup(ScheduledReleaseBalance storage self) {
		if (self.collateral == address(0) || self.user == address(0)) revert BalanceSetupRequired();
		_;
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  INITIALIZATION  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Initialize the balance slot.
	 * @param self           Storage pointer
	 * @param _user          Owner address
	 * @param _collateral    ERC20 address of the collateral token
	 */
	function setup(ScheduledReleaseBalance storage self, address _user, address _collateral) internal {
		if (self.collateral != address(0) || self.user != address(0)) return;
		self.collateral = _collateral;
		self.user = _user;
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  INCREASE OPERATIONS  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Queue funds for release according to counter‑party schedule.
	 * @dev Falls back to an instant add when the counter‑party’s release interval
	 *      is set to zero. Will auto‑add the counter‑party to the tracking list
	 *      when `manualSync` is disabled.
	 */
	function scheduledAdd(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 value,
		MarginType marginType,
		IncreaseBalanceReason reason
	) internal checkSetup(self) {
		if (value == 0) return;
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// keep schedule up‑to‑date first
		_sync(self, counterParty, marginType, false);

		// zero interval ⇒ treat as instant add
		if (counterParty.getReleaseInterval() == 0) {
			return marginType == MarginType.CROSS ? instantCrossAdd(self, value, counterParty, reason) : instantIsolatedAdd(self, value, reason);
		}

		// ensure counter‑party is tracked so that future syncAll calls reach it
		if (!accountLayout.manualSync[self.user]) addCounterParty(self, counterParty, marginType);

		// finally queue the funds
		self.counterPartySchedules[counterParty][marginType].scheduled += value;
		emit IncreaseBalance(self.user, counterParty, self.collateral, value, reason, false, marginType);
	}

	/// @notice Instantly credit funds to `isolatedBalance`.
	function instantIsolatedAdd(ScheduledReleaseBalance storage self, uint256 value, IncreaseBalanceReason reason) internal {
		if (value == 0) return;
		self.isolatedBalance += value;
		emit IncreaseBalance(self.user, address(0), self.collateral, value, reason, true, MarginType.ISOLATED);
	}

	/// @notice Instantly credit funds to `crossBalance[counterParty]`.
	function instantCrossAdd(ScheduledReleaseBalance storage self, uint256 value, address counterParty, IncreaseBalanceReason reason) internal {
		if (value == 0) return;
		self.crossBalance[counterParty] += int256(value);
		emit IncreaseBalance(self.user, counterParty, self.collateral, value, reason, true, MarginType.CROSS);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  DECREASE OPERATIONS  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/// @notice Debit funds from `isolatedBalance` only.
	function isolatedSub(ScheduledReleaseBalance storage self, uint256 value, DecreaseBalanceReason reason) internal {
		if (value == 0) return;
		if (self.isolatedBalance < value) revert InsufficientBalance(self.collateral, value, int256(self.isolatedBalance));
		self.isolatedBalance -= value;
		emit DecreaseBalance(self.user, address(0), self.collateral, value, reason, MarginType.ISOLATED);
	}

	/// @notice Debit funds from a specific `crossBalance`.
	function crossSub(ScheduledReleaseBalance storage self, uint256 value, address counterParty, DecreaseBalanceReason reason) internal {
		if (value == 0) return;
		self.crossBalance[counterParty] -= int256(value);
		emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, MarginType.CROSS);
	}

	/**
	 * @notice Unified debit that drains (1) scheduled` buckets for a counter‑party, (2) `transitioning`,
	 *         then (3) free balance`.
	 * @dev     `sync` is invoked to realize any matured buckets before counting.
	 */
	function subForCounterParty(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 value,
		MarginType marginType,
		DecreaseBalanceReason reason
	) internal {
		if (value == 0) return;
		if (counterParty == address(0)) revert CommonErrors.ZeroAddress("counterParty");

		// realize matured buckets first
		sync(self, counterParty, marginType);

		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][marginType];

		// zero interval ⇒ fallback to simple sub
		if (entry.releaseInterval == 0) {
			return marginType == MarginType.ISOLATED ? isolatedSub(self, value, reason) : crossSub(self, value, counterParty, reason);
		}

		int256 baseBalance = marginType == MarginType.ISOLATED ? int256(self.isolatedBalance) : self.crossBalance[counterParty];
		int256 totalBalance = baseBalance + int256(entry.transitioning) + int256(entry.scheduled); // won't overflow in real world
		if (marginType == MarginType.ISOLATED && totalBalance < int256(value)) revert InsufficientBalance(self.collateral, value, totalBalance);

		uint256 remaining = value;

		// drain from scheduled bucket first
		if (entry.scheduled >= remaining) {
			entry.scheduled -= remaining;
			emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, marginType);
			return;
		}
		if (entry.scheduled > 0) {
			remaining -= entry.scheduled;
			entry.scheduled = 0;
		}

		// then transitioning bucket
		if (entry.transitioning >= remaining) {
			entry.transitioning -= remaining;
			emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, marginType);
			return;
		}
		if (entry.transitioning > 0) {
			remaining -= entry.transitioning;
			entry.transitioning = 0;
		}

		// finally free balance
		if (marginType == MarginType.ISOLATED) {
			self.isolatedBalance -= remaining;
		} else {
			self.crossBalance[counterParty] -= int256(remaining);
		}

		emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, marginType);
	}

	/**
	 * @notice Return total balance (free + locked) for a counter‑party.
	 */
	function counterPartyBalance(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType) internal view returns (int256) {
		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][marginType];
		int256 baseBalance = marginType == MarginType.ISOLATED ? int256(self.isolatedBalance) : self.crossBalance[counterParty];
		return baseBalance + int256(entry.transitioning) + int256(entry.scheduled);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  ALLOCATION  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Move funds from isolated → cross balance for `counterParty`.
	 */
	function allocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		if (amount == 0) return;
		if (counterParty == address(0)) revert CommonErrors.ZeroAddress("counterParty");
		if (self.isolatedBalance < amount) revert InsufficientBalance(self.collateral, amount, int256(self.isolatedBalance));

		// ensure present in tracking list
		if (!AccountStorage.layout().manualSync[self.user] && self.counterPartyIndexes[counterParty][MarginType.CROSS] == 0) {
			addCounterParty(self, counterParty, MarginType.CROSS);
		}

		self.isolatedBalance -= amount;
		self.crossBalance[counterParty] += int256(amount);
		emit AllocateBalance(self.user, counterParty, self.collateral, amount);
	}

	/**
	 * @notice Move funds from cross → isolated balance for `counterParty`.
	 * @dev Should be called via a source that has already verified solvency of user (via a muon signature probably)
	 */
	function deallocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		if (amount == 0) return;
		if (counterParty == address(0)) revert CommonErrors.ZeroAddress("counterParty");

		self.crossBalance[counterParty] -= int256(amount);
		self.isolatedBalance += amount;
		emit DeallocateBalance(self.user, counterParty, self.collateral, amount);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  SYNC ROUTINES  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Public entry point that realizes matured buckets for `counterParty`.
	 * @dev     Thin wrapper around `_sync` with `removeCounterPartyOnEmpty = true`.
	 */
	function sync(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType) internal {
		return _sync(self, counterParty, marginType, true);
	}

	/**
	 * @notice Sync the entire counter‑party list of `marginType`.
	 */
	function syncAll(ScheduledReleaseBalance storage self, MarginType marginType) internal {
		address[] storage list = self.counterPartyAddresses[marginType];
		uint256 len = list.length;
		// doing it in reverse order to allow removing of parties in sync method
		while (len != 0) {
			unchecked {
				--len;
			}
			_sync(self, list[len], marginType, true);
		}
	}

	/**
	 * @notice Core sync routine. Moves funds through the two‑bus pipeline.
	 * @param removeCounterPartyOnEmpty If true, remove `counterParty` when no balance remains in buses.
	 */
	function _sync(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType, bool removeCounterPartyOnEmpty) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// insolvent counter‑party ⇒ keep everything locked
		if (!counterParty.isSolvent(self.collateral)) {
			return;
		}

		uint256 extReleaseInterval = counterParty.getReleaseInterval();

		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][marginType];

		// (1) Release interval changed externally → reinitialize everything.
		if (entry.releaseInterval != extReleaseInterval) {
			entry.releaseInterval = extReleaseInterval;
			entry.lastTransitionTimestamp = entry.releaseInterval == 0
				? block.timestamp
				: (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

			if (entry.releaseInterval == 0) {
				if (marginType == MarginType.CROSS) {
					self.crossBalance[counterParty] += int(entry.transitioning + entry.scheduled);
				} else {
					self.isolatedBalance += (entry.transitioning + entry.scheduled);
				}
			} else {
				entry.scheduled += entry.transitioning; // merge buckets
				entry.transitioning = 0;
			}
			emit SyncBalance(self.user, counterParty, self.collateral, marginType);
			return;
		}

		// (2) No schedule → nothing to do.
		if (entry.releaseInterval == 0) return;

		// Sanity check
		if (block.timestamp < entry.lastTransitionTimestamp) revert InvalidSyncTimestamp(block.timestamp, entry.lastTransitionTimestamp);

		uint256 intervals = (block.timestamp - entry.lastTransitionTimestamp) / entry.releaseInterval;
		if (intervals == 0) return;

		// ---------------------------------------------------------------------
		// (3) Move buckets forward if we have passed transitions
		// ---------------------------------------------------------------------
		uint256 thisTransitionTimestamp = entry.lastTransitionTimestamp + entry.releaseInterval;
		uint256 nextTransitionTimestamp = thisTransitionTimestamp + entry.releaseInterval; // +1 interval

		if (block.timestamp >= thisTransitionTimestamp) {
			// first bus arrived → transitioning → free
			if (marginType == MarginType.ISOLATED) {
				self.isolatedBalance += entry.transitioning;
			} else {
				self.crossBalance[counterParty] += int256(entry.transitioning);
			}

			if (block.timestamp < nextTransitionTimestamp) {
				// only first bus passed → scheduled → transitioning
				entry.transitioning = entry.scheduled;
				entry.scheduled = 0;
			} else {
				// both buses passed
				entry.transitioning = 0;
			}
		}

		if (block.timestamp >= nextTransitionTimestamp) {
			// second bus arrived → everything free
			if (marginType == MarginType.ISOLATED) {
				self.isolatedBalance += entry.scheduled;
			} else {
				self.crossBalance[counterParty] += int256(entry.scheduled);
			}
			entry.scheduled = 0;
		}

		// align timestamp to current interval start
		entry.lastTransitionTimestamp = (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

		// optionally prune if nothing left
		if (!AccountStorage.layout().manualSync[self.user] && removeCounterPartyOnEmpty && entry.transitioning == 0 && entry.scheduled == 0) {
			removeCounterParty(self, counterParty, marginType);
		}

		emit SyncBalance(self.user, counterParty, self.collateral, marginType);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  COUNTER‑PARTY TRACKING  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Ensure `counterParty` is present in the tracking list for `marginType`.
	 */
	function addCounterParty(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (self.counterPartyIndexes[counterParty][marginType] != 0) return; // already present
		if (self.counterPartyAddresses[marginType].length >= accountLayout.maxConnectedCounterParties) {
			revert MaxCounterPartyConnectionsReached(self.counterPartyAddresses[marginType].length, accountLayout.maxConnectedCounterParties);
		}

		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][marginType];
		entry.releaseInterval = counterParty.getReleaseInterval();
		entry.lastTransitionTimestamp = entry.releaseInterval == 0
			? block.timestamp
			: (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

		// book‑keeping (packed array)
		uint256 newIndex = self.counterPartyAddresses[marginType].length;
		self.counterPartyAddresses[marginType].push(counterParty);
		self.counterPartyIndexes[counterParty][marginType] = newIndex + 1; // store +1 so that 0 means “not present”
	}

	/**
	 * @notice Remove `counterParty` from tracking once balances are zero.
	 */
	function removeCounterParty(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType) internal {
		if (counterParty == address(0)) revert CommonErrors.ZeroAddress("counterParty");

		int256 balance = counterPartyBalance(self, counterParty, marginType);
		if (balance != 0) revert NonZeroBalanceCounterParty(counterParty, balance);
		if (marginType == MarginType.CROSS && self.crossBalance[counterParty] != 0) {
			revert NonZeroBalanceCounterParty(counterParty, self.crossBalance[counterParty]);
		}

		uint256 idxPlusOne = self.counterPartyIndexes[counterParty][marginType];
		if (idxPlusOne == 0) return; // already removed

		uint256 index = idxPlusOne - 1;
		uint256 lastIndex = self.counterPartyAddresses[marginType].length - 1;
		if (index != lastIndex) {
			address moved = self.counterPartyAddresses[marginType][lastIndex];
			self.counterPartyAddresses[marginType][index] = moved;
			self.counterPartyIndexes[moved][marginType] = index + 1;
		}

		self.counterPartyAddresses[marginType].pop();
		delete self.counterPartyIndexes[counterParty][marginType];
		delete self.counterPartySchedules[counterParty][marginType];
	}

	function isolatedLock(ScheduledReleaseBalance storage self, uint256 amount) internal {
		if (self.isolatedBalance < amount) revert InsufficientBalance(self.collateral, amount, int256(self.isolatedBalance));
		self.isolatedLockedBalance += amount;
	}

	function isolatedUnlock(ScheduledReleaseBalance storage self, uint256 amount) internal {
		if (self.isolatedLockedBalance < amount) revert InsufficientLockedBalance(self.collateral, amount, self.isolatedLockedBalance);
		self.isolatedLockedBalance -= amount;
	}

	function crossLock(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][MarginType.CROSS];
		entry.locked += amount;
	}

	function crossUnlock(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][MarginType.CROSS];
		if (entry.locked < amount) revert InsufficientLockedBalance(self.collateral, amount, entry.locked);
		entry.locked -= amount;
	}

	function increaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][MarginType.CROSS];
		entry.totalMM += amount;
	}

	function decreaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		ScheduledReleaseEntry storage entry = self.counterPartySchedules[counterParty][MarginType.CROSS];
		if (entry.totalMM < amount) revert InsufficientMMBalance(self.collateral, amount, entry.totalMM);
		entry.totalMM -= amount;
	}
}
