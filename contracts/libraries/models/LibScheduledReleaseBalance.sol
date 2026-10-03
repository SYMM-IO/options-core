// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023‑2025 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license

pragma solidity >=0.8.19;

import { IBucketFacet } from "../../facets/Bucket/IBucketFacet.sol";
import { BucketRef, BucketBalanceOp } from "../../types/BucketTypes.sol";

import { LibParty } from "./LibParty.sol";

import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import {
	ScheduledReleaseBalance,
	ScheduledReleaseEntry,
	IncreaseBalanceReason,
	DecreaseBalanceReason,
	CrossEntry
} from "../../types/BalanceTypes.sol";

import { BalanceErrors } from "../../errors/BalanceErrors.sol";
import { ValidationErrors } from "../../errors/ValidationErrors.sol";

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

	event SyncBalance(address indexed user, address indexed counterParty, address indexed collateral);

	event LockBalance(address indexed user, address indexed collateral, uint256 amount, MarginType marginType);

	event UnlockBalance(address indexed user, address indexed collateral, uint256 amount, MarginType marginType);

	// ─── modifiers ────────────────────────────────────────────────────────────

	/// @dev Reverts unless the balance slot has been initialized via `setup`.
	modifier checkSetup(ScheduledReleaseBalance storage self) {
		if (self.collateral == address(0) || self.user == address(0)) revert BalanceErrors.BalanceSetupRequired();
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
		setup(self, _user, 0, _collateral);
	}

	function setup(ScheduledReleaseBalance storage self, address _user, uint256 bucketId, address _collateral) internal {
		if (self.collateral != address(0) && self.user != address(0)) return;
		if (_user == address(0)) revert ValidationErrors.ZeroAddress("user");
		if (_collateral == address(0)) revert ValidationErrors.ZeroAddress("collateral");
		self.collateral = _collateral;
		self.user = _user;
		self.bucketId = bucketId;
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
		scheduledAdd(self, counterParty, 0, value, marginType, reason);
	}

	function scheduledAdd(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 value,
		MarginType marginType,
		IncreaseBalanceReason reason
	) internal checkSetup(self) {
		if (value == 0) return;
		if (counterParty == address(0)) revert ValidationErrors.ZeroAddress("counterParty");

		if (marginType == MarginType.CROSS) {
			crossEntry(self, counterParty, counterPartyBucketId).balance += int256(value);
			emit IncreaseBalance(self.user, counterParty, self.collateral, value, reason, true, MarginType.CROSS);
			_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.INCREASE, MarginType.CROSS);
			return;
		}

		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		// ensure counter‑party is tracked so that future syncAll calls reach it
		if (!accountLayout.manualSync[self.user]) addCounterParty(self, counterParty, counterPartyBucketId);

		// keep schedule up‑to‑date first
		_sync(self, counterParty, counterPartyBucketId);

		// zero interval ⇒ treat as instant add
		if (counterParty.getReleaseInterval() == 0) {
			// global Interval or per user set on account
			instantIsolatedAdd(self, value, reason);
			return;
		}

		// finally queue the funds
		scheduleEntry(self, counterParty, counterPartyBucketId).scheduled += value;
		emit IncreaseBalance(self.user, counterParty, self.collateral, value, reason, false, marginType);
		_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.INCREASE, marginType);
	}

	/// @notice Instantly credit funds to `isolatedBalance`.
	function instantIsolatedAdd(ScheduledReleaseBalance storage self, uint256 value, IncreaseBalanceReason reason) internal {
		if (value == 0) return;
		self.isolatedBalance += value;
		emit IncreaseBalance(self.user, address(0), self.collateral, value, reason, true, MarginType.ISOLATED);
		_emitBucketChange(self, address(0), 0, value, BucketBalanceOp.INCREASE, MarginType.ISOLATED);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  DECREASE OPERATIONS  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/// @notice Debit funds from `isolatedBalance` only.
	function isolatedSub(ScheduledReleaseBalance storage self, uint256 value, DecreaseBalanceReason reason) internal {
		if (value == 0) return;
		if (self.isolatedBalance < value) revert BalanceErrors.InsufficientBalance(self.user, self.collateral, value, self.isolatedBalance);
		self.isolatedBalance -= value;
		emit DecreaseBalance(self.user, address(0), self.collateral, value, reason, MarginType.ISOLATED);
		_emitBucketChange(self, address(0), 0, value, BucketBalanceOp.DECREASE, MarginType.ISOLATED);
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
		subForCounterParty(self, counterParty, 0, value, marginType, reason);
	}

	function subForCounterParty(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 value,
		MarginType marginType,
		DecreaseBalanceReason reason
	) internal {
		if (value == 0) return;
		if (marginType == MarginType.CROSS && counterParty == address(0)) revert ValidationErrors.ZeroAddress("counterParty");

		if (counterParty == address(0)) {
			isolatedSub(self, value, reason);
			return;
		}

		if (marginType == MarginType.CROSS) {
			crossEntry(self, counterParty, counterPartyBucketId).balance -= int256(value);
			emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, MarginType.CROSS);
			_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.DECREASE, MarginType.CROSS);
			return;
		}
		// realize matured buckets first
		sync(self, counterParty, counterPartyBucketId);

		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);

		// zero interval ⇒ fallback to simple sub
		if (entry.releaseInterval == 0) {
			return isolatedSub(self, value, reason);
		}

		uint256 baseBalance = self.isolatedBalance;
		uint256 totalBalance = baseBalance + entry.transitioning + entry.scheduled;
		if (totalBalance < value) revert BalanceErrors.InsufficientBalance(self.user, self.collateral, value, totalBalance);

		uint256 remaining = value;

		// drain from scheduled bucket first
		if (entry.scheduled >= remaining) {
			entry.scheduled -= remaining;
			emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, marginType);
			_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.DECREASE, marginType);
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
			_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.DECREASE, marginType);
			return;
		}
		if (entry.transitioning > 0) {
			remaining -= entry.transitioning;
			entry.transitioning = 0;
		}

		// finally free balance
		self.isolatedBalance -= remaining;

		emit DecreaseBalance(self.user, counterParty, self.collateral, value, reason, marginType);
		_emitBucketChange(self, counterParty, counterPartyBucketId, value, BucketBalanceOp.DECREASE, marginType);
	}

	/**
	 * @notice Return in transition for a counter‑party.
	 */
	function inTransitionBalance(ScheduledReleaseBalance storage self, address counterParty) internal view returns (uint256) {
		return inTransitionBalance(self, counterParty, 0);
	}

	function inTransitionBalance(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId
	) internal view returns (uint256) {
		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);
		return entry.transitioning + entry.scheduled;
	}

	/**
	 * @notice Return total balance of user for a counterparty
	 */
	function counterPartyBalance(ScheduledReleaseBalance storage self, address counterParty, MarginType marginType) internal view returns (int256) {
		return counterPartyBalance(self, counterParty, 0, marginType);
	}

	function counterPartyBalance(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId,
		MarginType marginType
	) internal view returns (int256) {
		if (counterParty == address(0)) {
			if (marginType == MarginType.ISOLATED) {
				return int256(self.isolatedBalance);
			} else {
				return crossEntry(self, counterParty, counterPartyBucketId).balance;
			}
		}
		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);
		if (marginType == MarginType.ISOLATED) {
			return int256(self.isolatedBalance + entry.transitioning + entry.scheduled);
		} else {
			return crossEntry(self, counterParty, counterPartyBucketId).balance;
		}
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  ALLOCATION  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Move funds from isolated → cross balance for `counterParty`.
	 */
	function allocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		allocateBalance(self, counterParty, 0, amount);
	}

	function allocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		if (amount == 0) return;
		if (counterParty == address(0)) revert ValidationErrors.ZeroAddress("counterParty");

		if (self.isolatedBalance - self.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(self.user, self.collateral, amount, self.isolatedBalance);

		self.isolatedBalance -= amount;
		crossEntry(self, counterParty, counterPartyBucketId).balance += int256(amount);
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.ALLOCATE, MarginType.CROSS);
	}

	/**
	 * @notice Move funds from cross → isolated balance for `counterParty`.
	 * @dev Should be called via a source that has already verified solvency of user (via a muon signature probably)
	 */
	function deallocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		deallocateBalance(self, counterParty, 0, amount);
	}

	function deallocateBalance(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		if (amount == 0) return;
		if (counterParty == address(0)) revert ValidationErrors.ZeroAddress("counterParty");

		crossEntry(self, counterParty, counterPartyBucketId).balance -= int256(amount);
		self.isolatedBalance += amount;
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.DEALLOCATE, MarginType.CROSS);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  SYNC ROUTINES  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Public entry point that realizes matured buckets for `counterParty`.
	 * @dev     Thin wrapper around `_sync` with `tryRemoveCounterPartyOnEmpty = true`.
	 */
	function sync(ScheduledReleaseBalance storage self, address counterParty) internal {
		sync(self, counterParty, 0);
	}

	function sync(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId) internal {
		return _sync(self, counterParty, counterPartyBucketId);
	}

	/**
	 * @notice Sync the entire counter‑party list of `marginType`.
	 */
	function syncAll(ScheduledReleaseBalance storage self) internal {
		address[] storage list = self.counterPartyAddresses;
		uint256 len = list.length;
		// doing it in reverse order to allow removing of parties in sync method
		while (len != 0) {
			unchecked {
				--len;
			}
			_sync(self, list[len], 0);
		}
		len = self.bucketedCounterParties.length;
		while (len != 0) {
			--len;
			BucketRef memory cp = self.bucketedCounterParties[len];
			_sync(self, cp.owner, cp.bucketId);
		}
	}

	/**
	 * @notice Core sync routine. Moves funds through the two‑bus pipeline.
	 */
	function _sync(ScheduledReleaseBalance storage self, address counterParty) internal {
		_sync(self, counterParty, 0);
	}

	function _sync(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId) internal {
		// insolvent counter‑party ⇒ keep everything locked
		if (!counterParty.isSolvent(counterPartyBucketId, self.user, self.bucketId, self.collateral, MarginType.ISOLATED)) {
			// OK as no effect when counter party is A in ISOLATED Margin type
			return;
		}

		uint256 updatedReleaseInterval = counterParty.getReleaseInterval(); // default account interval or user specific interval if available

		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);

		// (1) Release interval changed externally → reinitialize everything.
		if (entry.releaseInterval != updatedReleaseInterval) {
			entry.releaseInterval = updatedReleaseInterval;
			entry.lastTransitionTimestamp =
				entry.releaseInterval == 0 ? block.timestamp : (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

			if (entry.releaseInterval == 0) {
				self.isolatedBalance += (entry.transitioning + entry.scheduled);
				entry.transitioning = 0;
				entry.scheduled = 0;
			} else {
				entry.scheduled += entry.transitioning; //merge buckets
				entry.transitioning = 0;
			}
			emit SyncBalance(self.user, counterParty, self.collateral);
			_emitBucketChange(self, counterParty, counterPartyBucketId, 0, BucketBalanceOp.SYNC, MarginType.ISOLATED);
			return;
		}

		// (2) No schedule → nothing to do.
		if (entry.releaseInterval == 0) return;

		// Sanity check
		if (block.timestamp < entry.lastTransitionTimestamp)
			revert BalanceErrors.InvalidSyncTimestamp(block.timestamp, entry.lastTransitionTimestamp);

		uint256 intervals = (block.timestamp - entry.lastTransitionTimestamp) / entry.releaseInterval;
		if (intervals == 0) return;

		// ---------------------------------------------------------------------
		// (3) Move buckets forward if we have passed transitions
		// ---------------------------------------------------------------------
		uint256 thisTransitionTimestamp = entry.lastTransitionTimestamp + entry.releaseInterval;
		// uint256 nextTransitionTimestamp = thisTransitionTimestamp + entry.releaseInterval; // +1 interval

		if (block.timestamp >= thisTransitionTimestamp + entry.releaseInterval) {
			// second bus arrived → everything free
			self.isolatedBalance += (entry.scheduled + entry.transitioning);
			entry.scheduled = 0;
			entry.transitioning = 0;
		} else if (block.timestamp >= thisTransitionTimestamp) {
			// first bus passed → scheduled → transitioning
			self.isolatedBalance += entry.transitioning;
			entry.transitioning = entry.scheduled;
			entry.scheduled = 0;
		}

		// align timestamp to current interval start
		entry.lastTransitionTimestamp = (block.timestamp / entry.releaseInterval) * entry.releaseInterval;

		tryRemoveCounterParty(self, counterParty, counterPartyBucketId);

		emit SyncBalance(self.user, counterParty, self.collateral);
		_emitBucketChange(self, counterParty, counterPartyBucketId, 0, BucketBalanceOp.SYNC, MarginType.ISOLATED);
	}

	// ────────────────────────────────────────────────────────────────────────────
	// ↑↑  COUNTER‑PARTY TRACKING  ↑↑
	// ────────────────────────────────────────────────────────────────────────────

	/**
	 * @notice Ensure `counterParty` is present in the tracking list for `marginType`.
	 */
	function addCounterParty(ScheduledReleaseBalance storage self, address counterParty) internal {
		addCounterParty(self, counterParty, 0);
	}

	function addCounterParty(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		uint256 index =
			counterPartyBucketId == 0 ? self.counterPartyIndexes[counterParty] : self.bucketedCounterPartyIndexes[counterParty][counterPartyBucketId];
		if (index != 0 || accountLayout.manualSync[self.user]) return;
		uint256 count = self.counterPartyAddresses.length + self.bucketedCounterParties.length;
		if (count >= accountLayout.maxConnectedCounterParties) {
			syncAll(self);
			count = self.counterPartyAddresses.length + self.bucketedCounterParties.length;
			if (count >= accountLayout.maxConnectedCounterParties)
				revert BalanceErrors.MaxCounterPartyConnectionsReached(count, accountLayout.maxConnectedCounterParties);
		}
		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);
		entry.releaseInterval = counterParty.getReleaseInterval();
		entry.lastTransitionTimestamp =
			entry.releaseInterval == 0 ? block.timestamp : (block.timestamp / entry.releaseInterval) * entry.releaseInterval;
		if (counterPartyBucketId == 0) {
			self.counterPartyAddresses.push(counterParty);
			self.counterPartyIndexes[counterParty] = self.counterPartyAddresses.length;
		} else {
			self.bucketedCounterParties.push(BucketRef(counterParty, counterPartyBucketId));
			self.bucketedCounterPartyIndexes[counterParty][counterPartyBucketId] = self.bucketedCounterParties.length;
		}
	}

	/**
	 * @notice Remove `counterParty` from tracking once balances are zero.
	 */
	function tryRemoveCounterParty(ScheduledReleaseBalance storage self, address counterParty) internal {
		tryRemoveCounterParty(self, counterParty, 0);
	}

	function tryRemoveCounterParty(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId) internal {
		if (counterParty == address(0)) revert ValidationErrors.ZeroAddress("counterParty");
		ScheduledReleaseEntry storage entry = scheduleEntry(self, counterParty, counterPartyBucketId);
		uint256 tradeCount =
			self.bucketId == 0 && counterPartyBucketId == 0
				? TradeStorage.layout().activeTradesOfPartyAWithPartyBCount[self.user][self.collateral][counterParty]
				: TradeStorage.layout().activeTradesOfBucketPairCount[self.user][self.bucketId][self.collateral][counterParty][counterPartyBucketId];
		if (entry.transitioning != 0 || entry.scheduled != 0 || tradeCount != 0) return;
		uint256 idxPlusOne =
			counterPartyBucketId == 0 ? self.counterPartyIndexes[counterParty] : self.bucketedCounterPartyIndexes[counterParty][counterPartyBucketId];
		if (idxPlusOne == 0) return;
		uint256 index = idxPlusOne - 1;
		if (counterPartyBucketId == 0) {
			uint256 last = self.counterPartyAddresses.length - 1;
			if (index != last) {
				address moved = self.counterPartyAddresses[last];
				self.counterPartyAddresses[index] = moved;
				self.counterPartyIndexes[moved] = index + 1;
			}
			self.counterPartyAddresses.pop();
			delete self.counterPartyIndexes[counterParty];
			delete self.counterPartySchedules[counterParty];
		} else {
			uint256 last = self.bucketedCounterParties.length - 1;
			if (index != last) {
				BucketRef memory moved = self.bucketedCounterParties[last];
				self.bucketedCounterParties[index] = moved;
				self.bucketedCounterPartyIndexes[moved.owner][moved.bucketId] = index + 1;
			}
			self.bucketedCounterParties.pop();
			delete self.bucketedCounterPartyIndexes[counterParty][counterPartyBucketId];
			delete self.bucketedSchedules[counterParty][counterPartyBucketId];
		}
	}

	function isolatedLock(ScheduledReleaseBalance storage self, uint256 amount) internal {
		if (self.isolatedBalance - self.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(self.user, self.collateral, amount, self.isolatedBalance - self.isolatedLockedBalance);
		self.isolatedLockedBalance += amount;
		emit LockBalance(self.user, self.collateral, amount, MarginType.ISOLATED);
		_emitBucketChange(self, address(0), 0, amount, BucketBalanceOp.LOCK, MarginType.ISOLATED);
	}

	function isolatedUnlock(ScheduledReleaseBalance storage self, uint256 amount) internal {
		if (self.isolatedLockedBalance < amount) revert BalanceErrors.InsufficientLockedBalance(self.collateral, amount, self.isolatedLockedBalance);
		self.isolatedLockedBalance -= amount;
		emit UnlockBalance(self.user, self.collateral, amount, MarginType.ISOLATED);
		_emitBucketChange(self, address(0), 0, amount, BucketBalanceOp.UNLOCK, MarginType.ISOLATED);
	}

	function crossLock(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		crossLock(self, counterParty, 0, amount);
	}

	function crossLock(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		CrossEntry storage entry = crossEntry(self, counterParty, counterPartyBucketId);
		entry.locked += amount;
		emit LockBalance(self.user, self.collateral, amount, MarginType.CROSS);
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.LOCK, MarginType.CROSS);
	}

	function crossUnlock(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		crossUnlock(self, counterParty, 0, amount);
	}

	function crossUnlock(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		CrossEntry storage entry = crossEntry(self, counterParty, counterPartyBucketId);
		if (entry.locked < amount) revert BalanceErrors.InsufficientLockedBalance(self.collateral, amount, entry.locked);
		entry.locked -= amount;
		emit UnlockBalance(self.user, self.collateral, amount, MarginType.CROSS);
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.UNLOCK, MarginType.CROSS);
	}

	function increaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		increaseMM(self, counterParty, 0, amount);
	}

	function increaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		CrossEntry storage entry = crossEntry(self, counterParty, counterPartyBucketId);
		entry.totalMM += amount;
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.MM_INCREASE, MarginType.CROSS);
	}

	function decreaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 amount) internal {
		decreaseMM(self, counterParty, 0, amount);
	}

	function decreaseMM(ScheduledReleaseBalance storage self, address counterParty, uint256 counterPartyBucketId, uint256 amount) internal {
		CrossEntry storage entry = crossEntry(self, counterParty, counterPartyBucketId);
		if (entry.totalMM < amount) revert BalanceErrors.InsufficientMMBalance(self.collateral, amount, entry.totalMM);
		entry.totalMM -= amount;
		_emitBucketChange(self, counterParty, counterPartyBucketId, amount, BucketBalanceOp.MM_DECREASE, MarginType.CROSS);
	}

	function crossEntry(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId
	) internal view returns (CrossEntry storage) {
		if (counterPartyBucketId == 0) return self.crossBalance[counterParty];
		return self.bucketedCrossBalance[counterParty][counterPartyBucketId];
	}
	function scheduleEntry(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId
	) internal view returns (ScheduledReleaseEntry storage) {
		if (counterPartyBucketId == 0) return self.counterPartySchedules[counterParty];
		return self.bucketedSchedules[counterParty][counterPartyBucketId];
	}

	function _emitBucketChange(
		ScheduledReleaseBalance storage self,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 amount,
		BucketBalanceOp operation,
		MarginType marginType
	) private {
		if (self.bucketId != 0 || counterPartyBucketId != 0)
			emit IBucketFacet.BucketBalanceChanged(
				self.user,
				self.bucketId,
				counterParty,
				counterPartyBucketId,
				self.collateral,
				amount,
				operation,
				marginType
			);
	}
}
