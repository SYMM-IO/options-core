// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

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
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if ((!counterParty.isPartyB() && !sender.isPartyB()) || (counterParty.isPartyB() && sender.isPartyB()))
			revert BalanceErrors.InvalidCounterParty(sender, counterParty);

		if (
			!sender.isPartyB() &&
			(sender.balanceOf(collateral).crossBalance[counterParty].balance + int256(amount) > int256(appLayout.balanceLimitPerUser[collateral]))
		)
			revert BalanceErrors.BalanceLimitExceeded(
				sender.balanceOf(collateral).crossBalance[counterParty].balance,
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		sender.requireSolvent(counterParty, collateral, MarginType.ISOLATED);
		sender.requireSolvent(counterParty, collateral, MarginType.CROSS);

		sender.balanceOf(collateral).allocateBalance(counterParty, amount);
	}

	function deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig memory upnlSig) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		uint256 oracleId = isPartyB ? appLayout.partyBConfigs[msg.sender].oracleId : appLayout.partyBConfigs[counterParty].oracleId;
		LibMuon.verifyUpnlSig(upnlSig, collateral, msg.sender, counterParty, oracleId);

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(collateral);

		if (isPartyB) {
			deallocateForPartyBValidation(collateral, counterParty, amount, upnlSig);
		} else {
			deallocateForPartyAValidation(collateral, counterParty, amount, upnlSig);
			if (balance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
				revert BalanceErrors.BalanceLimitExceeded(int256(balance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		}

		msg.sender.requireSolvent(counterParty, collateral, MarginType.ISOLATED);
		msg.sender.requireSolvent(counterParty, collateral, MarginType.CROSS);

		balance.deallocateBalance(counterParty, amount);
	}

	function allocateToReserveBalance(address collateral, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(collateral);

		if (msg.sender.isPartyB()) msg.sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);
		if (balance.isolatedBalance - balance.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(msg.sender, collateral, amount, balance.isolatedBalance - balance.isolatedLockedBalance);
		if (!msg.sender.isPartyB() && (balance.reserveBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(int256(balance.reserveBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		balance.isolatedBalance -= amount;
		balance.reserveBalance += amount;
	}

	function deallocateFromReserveBalance(address collateral, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		ScheduledReleaseBalance storage balance = msg.sender.balanceOf(collateral);

		if (msg.sender.isPartyB()) msg.sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);
		if (balance.reserveBalance < amount) revert BalanceErrors.InsufficientBalance(msg.sender, collateral, amount, balance.reserveBalance);
		if (!msg.sender.isPartyB() && (balance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(int256(balance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);
		balance.isolatedBalance += amount;
		balance.reserveBalance -= amount;
	}

	function deallocateForPartyAValidation(address collateral, address counterParty, uint256 amount, UpnlSig memory upnlSig) internal view {
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[counterParty];

		CrossEntry memory partyACrossEntry = msg.sender.balanceOf(collateral).crossBalance[counterParty];
		int256 partyAAvailableBalance = partyACrossEntry.balance +
			((upnlSig.partyUpnl * 1e18) / int256(upnlSig.collateralPrice)) -
			int256(partyACrossEntry.totalMM) -
			int256(partyACrossEntry.locked);

		// min balance and available balance
		int256 partyAReadyToDeallocate = partyACrossEntry.balance < partyAAvailableBalance ? partyACrossEntry.balance : partyAAvailableBalance;

		if (int256(amount) > partyAReadyToDeallocate)
			revert BalanceErrors.InsufficientIntBalance(msg.sender, collateral, amount, partyAReadyToDeallocate);

		CrossEntry memory partyBCrossEntry = counterParty.balanceOf(collateral).crossBalance[msg.sender];
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
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[msg.sender];

		CrossEntry memory partyACrossEntry = counterParty.balanceOf(collateral).crossBalance[msg.sender];
		int256 partyAAvailableBalance = partyACrossEntry.balance +
			((upnlSig.counterPartyUpnl * 1e18) / int256(upnlSig.collateralPrice)) -
			int256(partyACrossEntry.totalMM);

		CrossEntry memory partyBCrossEntry = msg.sender.balanceOf(collateral).crossBalance[counterParty];
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
			if (partyBCrossEntry.balance - int256(amount) < collateralMustHave) revert BalanceErrors.NotSolvent(msg.sender, counterParty, collateral, MarginType.CROSS);
		}
	}
}
