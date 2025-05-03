// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType } from "./BaseTypes.sol";

// ────────────────────────────────────────────────────────────────────────────────
// ↑↑  CORE DATA STRUCTURES  ↑↑
// ────────────────────────────────────────────────────────────────────────────────

/**
 * @title ScheduledReleaseEntry
 * @notice Internal bookkeeping slot that implements the "two‑bus" unlock model.
 *         Funds wait in `scheduled` (second bus), move to `transitioning`
 *         (first bus) at the first arrival, and finally reach the user’s free
 *         balance after the second arrival.
 *
 * @param releaseInterval          Interval in seconds between bus arrivals.
 * @param transitioning            Funds that will unlock after one interval.
 * @param scheduled                Funds that will unlock after two intervals.
 * @param lastTransitionTimestamp  Timestamp aligned to the start of the last
 *                                 processed interval.
 */
struct ScheduledReleaseEntry {
	uint256 releaseInterval;
	uint256 transitioning;
	uint256 scheduled;
	uint256 lastTransitionTimestamp;
}

struct CrossEntry {
	int256 balance;
	uint256 locked;
	uint256 totalMM;
}

/**
 * @title ScheduledReleaseBalance
 * @notice Complete margin state for a user/collateral pair.
 *         ‑ `isolatedBalance`   → instantly available ISOLATED margin
 *         ‑ `crossBalance`      → instantly available CROSS margin per counter‑party
 *         ‑ `counterPartySchedules` → delayed balances managed by the two‑bus model
 *         The struct also maintains packed index maps so that cross‑balances can
 *         be enumerated and removed in O(1).
 */
struct ScheduledReleaseBalance {
	// ─── general settings ──────────────────────────────────────────────────────
	address collateral;
	address user; // owner of this slot
	// ─── free balances ────────────────────────────────────────────────────────
	uint256 isolatedBalance; // free isolated funds
	uint256 isolatedLockedBalance; // free isolated funds
	uint256 reserveBalance;
	mapping(address => CrossEntry) crossBalance; // cross funds
	// ─── delayed balances ─────────────────────────────────────────────────────
	mapping(address => ScheduledReleaseEntry) counterPartySchedules;
	// ─── enumeration helpers (packed array + 1‑based index map) ───────────────
	address[] counterPartyAddresses;
	mapping(address => uint256) counterPartyIndexes; // 0 ⇒ not present
}

// ────────────────────────────────────────────────────────────────────────────────
// ↑↑  ENUMS FOR EVENT REASONS  ↑↑
// ────────────────────────────────────────────────────────────────────────────────

enum IncreaseBalanceReason {
	DEPOSIT,
	INTERNAL_TRANSFER,
	BRIDGE,
	FEE,
	PREMIUM,
	REALIZED_PNL,
	LIQUIDATION
}

enum DecreaseBalanceReason {
	WITHDRAW,
	INTERNAL_TRANSFER,
	BRIDGE,
	FEE,
	PREMIUM,
	REALIZED_PNL,
	CONFISCATE
}
