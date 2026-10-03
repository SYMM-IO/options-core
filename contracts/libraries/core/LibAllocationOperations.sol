// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "./LibBucket.sol";

import { LibParty } from "../models/LibParty.sol";
import { LibMuon } from "../services/LibMuon.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { UpnlSig } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, CrossEntry } from "../../types/BalanceTypes.sol";

import { BalanceErrors } from "../../errors/BalanceErrors.sol";

library LibAllocationOperations {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function allocate(address sender, address collateral, address counterParty, uint256 amount) internal {
		allocate(sender, 0, collateral, counterParty, 0, amount);
	}

	function allocate(
		address sender,
		uint256 bucketId,
		address collateral,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 amount
	) internal {
		LibBucket.requireNotSuspended(sender, bucketId);
		LibBucket.requireRegistered(sender, bucketId);
		LibBucket.requireRegistered(counterParty, counterPartyBucketId);
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if ((!counterParty.isPartyB() && !sender.isPartyB()) || (counterParty.isPartyB() && sender.isPartyB()))
			revert BalanceErrors.InvalidCounterParty(sender, counterParty);

		if (
			!sender.isPartyB() &&
			(sender.balanceOf(bucketId, collateral).crossEntry(counterParty, counterPartyBucketId).balance + int256(amount) >
				int256(appLayout.balanceLimitPerUser[collateral]))
		)
			revert BalanceErrors.BalanceLimitExceeded(
				sender.balanceOf(bucketId, collateral).crossEntry(counterParty, counterPartyBucketId).balance,
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		sender.requireSolvent(bucketId, counterParty, counterPartyBucketId, collateral, MarginType.ISOLATED);
		sender.requireSolvent(bucketId, counterParty, counterPartyBucketId, collateral, MarginType.CROSS);

		sender.balanceOf(bucketId, collateral).allocateBalance(counterParty, counterPartyBucketId, amount);
	}

	function deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig memory upnlSig) internal {
		deallocate(0, collateral, counterParty, 0, amount, isPartyB, upnlSig);
	}

	function deallocate(
		uint256 bucketId,
		address collateral,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 amount,
		bool isPartyB,
		UpnlSig memory upnlSig
	) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireRegistered(counterParty, counterPartyBucketId);
		AppStorage.Layout storage appLayout = AppStorage.layout();

		uint256 oracleId = isPartyB ? appLayout.partyBConfigs[msg.sender].oracleId : appLayout.partyBConfigs[counterParty].oracleId;
		LibMuon.verifyUpnlSig(upnlSig, collateral, msg.sender, bucketId, counterParty, counterPartyBucketId, oracleId);

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(bucketId, collateral);

		if (isPartyB) {
			deallocateForPartyBValidation(bucketId, collateral, counterParty, counterPartyBucketId, amount, upnlSig);
		} else {
			deallocateForPartyAValidation(bucketId, collateral, counterParty, counterPartyBucketId, amount, upnlSig);
			if (balance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
				revert BalanceErrors.BalanceLimitExceeded(int256(balance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		}

		msg.sender.requireSolvent(bucketId, counterParty, counterPartyBucketId, collateral, MarginType.ISOLATED);
		msg.sender.requireSolvent(bucketId, counterParty, counterPartyBucketId, collateral, MarginType.CROSS);

		balance.deallocateBalance(counterParty, counterPartyBucketId, amount);
	}

	function allocateToReserveBalance(address collateral, uint256 amount) internal {
		allocateToReserveBalance(0, collateral, amount);
	}

	function allocateToReserveBalance(uint256 bucketId, address collateral, uint256 amount) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireRegistered(msg.sender, bucketId);
		AppStorage.Layout storage appLayout = AppStorage.layout();

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(bucketId, collateral);

		if (msg.sender.isPartyB()) msg.sender.requireSolvent(bucketId, address(0), 0, collateral, MarginType.ISOLATED);
		if (balance.isolatedBalance - balance.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(msg.sender, collateral, amount, balance.isolatedBalance - balance.isolatedLockedBalance);
		if (!msg.sender.isPartyB() && (balance.reserveBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(int256(balance.reserveBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		balance.isolatedBalance -= amount;
		balance.reserveBalance += amount;
	}

	function deallocateFromReserveBalance(address collateral, uint256 amount) internal {
		deallocateFromReserveBalance(0, collateral, amount);
	}

	function deallocateFromReserveBalance(uint256 bucketId, address collateral, uint256 amount) internal {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireRegistered(msg.sender, bucketId);
		AppStorage.Layout storage appLayout = AppStorage.layout();

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(bucketId, collateral);

		if (msg.sender.isPartyB()) msg.sender.requireSolvent(bucketId, address(0), 0, collateral, MarginType.ISOLATED);
		if (balance.reserveBalance < amount) revert BalanceErrors.InsufficientBalance(msg.sender, collateral, amount, balance.reserveBalance);
		if (!msg.sender.isPartyB() && (balance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(int256(balance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		balance.isolatedBalance += amount;
		balance.reserveBalance -= amount;
	}

	function deallocateForPartyAValidation(address collateral, address counterParty, uint256 amount, UpnlSig memory upnlSig) internal view {
		deallocateForPartyAValidation(0, collateral, counterParty, 0, amount, upnlSig);
	}

	function deallocateForPartyAValidation(
		uint256 bucketId,
		address collateral,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 amount,
		UpnlSig memory upnlSig
	) internal view {
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[counterParty];

		CrossEntry memory partyACrossEntry = msg.sender.balanceOf(bucketId, collateral).crossEntry(counterParty, counterPartyBucketId);
		int256 partyAAvailableBalance =
			partyACrossEntry.balance +
				((upnlSig.partyUpnl * 1e18) / int256(upnlSig.collateralPrice)) -
				int256(partyACrossEntry.totalMM) -
				int256(partyACrossEntry.locked);

		// min balance and available balance
		int256 partyAReadyToDeallocate = partyACrossEntry.balance < partyAAvailableBalance ? partyACrossEntry.balance : partyAAvailableBalance;

		if (int256(amount) > partyAReadyToDeallocate)
			revert BalanceErrors.InsufficientIntBalance(msg.sender, collateral, amount, partyAReadyToDeallocate);

		CrossEntry memory partyBCrossEntry = counterParty.balanceOf(counterPartyBucketId, collateral).crossEntry(msg.sender, bucketId);
		int256 partyBAvailableBalance = partyBCrossEntry.balance + ((upnlSig.counterPartyUpnl * 1e18) / int256(upnlSig.collateralPrice));
		if (partyBAvailableBalance < 0) {
			int256 debt;
			if (upnlSig.counterPartyUpnl >= 0) {
				debt = -partyBAvailableBalance;
			} else {
				//check with loss coverage
				int256 collateralMustHave = (-upnlSig.counterPartyUpnl * int256(partyBConfig.lossCoverage)) / int256(upnlSig.collateralPrice);
				debt = collateralMustHave - partyBCrossEntry.balance;
			}
			if (partyAReadyToDeallocate - int256(amount) < (-debt))
				revert BalanceErrors.InsufficientDebtCoverage(msg.sender, counterParty, partyAReadyToDeallocate, amount, debt);
		}
	}

	function deallocateForPartyBValidation(address collateral, address counterParty, uint256 amount, UpnlSig memory upnlSig) internal view {
		deallocateForPartyBValidation(0, collateral, counterParty, 0, amount, upnlSig);
	}

	function deallocateForPartyBValidation(
		uint256 bucketId,
		address collateral,
		address counterParty,
		uint256 counterPartyBucketId,
		uint256 amount,
		UpnlSig memory upnlSig
	) internal view {
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[msg.sender];

		CrossEntry memory partyACrossEntry = counterParty.balanceOf(counterPartyBucketId, collateral).crossEntry(msg.sender, bucketId);
		int256 partyAAvailableBalance =
			partyACrossEntry.balance + ((upnlSig.counterPartyUpnl * 1e18) / int256(upnlSig.collateralPrice)) - int256(partyACrossEntry.totalMM);

		CrossEntry memory partyBCrossEntry = msg.sender.balanceOf(bucketId, collateral).crossEntry(counterParty, counterPartyBucketId);
		int256 partyBAvailableBalance = partyBCrossEntry.balance + ((upnlSig.partyUpnl * 1e18) / int256(upnlSig.collateralPrice));

		// partyA solvent
		if (partyAAvailableBalance < 0) revert BalanceErrors.NotSolvent(msg.sender, counterParty, collateral, MarginType.CROSS);

		if (upnlSig.partyUpnl >= 0) {
			// partyB solvent if upnl is pos and balance be positive
			int256 partyBReadyToDeallocate = partyBCrossEntry.balance < partyBAvailableBalance ? partyBCrossEntry.balance : partyBAvailableBalance;
			if (int256(amount) > partyBReadyToDeallocate)
				revert BalanceErrors.InsufficientIntBalance(msg.sender, counterParty, amount, partyBReadyToDeallocate);
		} else {
			// partyB solvent with loss coverage
			int256 collateralMustHave = (-upnlSig.partyUpnl * int256(partyBConfig.lossCoverage)) / int256(upnlSig.collateralPrice);
			if (partyBCrossEntry.balance - int256(amount) < collateralMustHave)
				revert BalanceErrors.NotSolvent(msg.sender, counterParty, collateral, MarginType.CROSS);
		}
	}
}
