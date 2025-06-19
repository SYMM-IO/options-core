// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibMuon } from "../services/LibMuon.sol";
import { CommonErrors } from "../utils/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { UpnlSig } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, CrossEntry } from "../../types/BalanceTypes.sol";

import { AccountFacetErrors } from "../../facets/Account/AccountFacetErrors.sol";

library LibAllocationOperations {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function allocate(address sender, address collateral, address counterParty, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (
			(!appLayout.partyBConfigs[counterParty].isActive && !appLayout.partyBConfigs[sender].isActive) ||
			(appLayout.partyBConfigs[counterParty].isActive && appLayout.partyBConfigs[sender].isActive)
		) revert AccountFacetErrors.InvalidCounterPartyToAllocate(sender, counterParty);
		if (
			!appLayout.partyBConfigs[sender].isActive &&
			(accountLayout.balances[sender][collateral].crossBalance[counterParty].balance + int256(amount) >
				int256(appLayout.balanceLimitPerUser[collateral]))
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				accountLayout.balances[sender][collateral].crossBalance[counterParty].balance,
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		sender.requireSolvent(counterParty, collateral, MarginType.ISOLATED);
		sender.requireSolvent(counterParty, collateral, MarginType.CROSS);

		accountLayout.balances[sender][collateral].allocateBalance(counterParty, amount);
	}

	function deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig memory upnlSig) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		uint256 oracleId = isPartyB ? appLayout.partyBConfigs[msg.sender].oracleId : appLayout.partyBConfigs[counterParty].oracleId;
		LibMuon.verifyUpnlSig(upnlSig, collateral, msg.sender, counterParty, oracleId);
		if (isPartyB) {
			deallocateForPartyBValidation(collateral, counterParty, int256(amount), upnlSig);
		} else {
			deallocateForPartyAValidation(collateral, counterParty, int256(amount), upnlSig);
			if (accountLayout.balances[msg.sender][collateral].isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
				revert AccountFacetErrors.BalanceLimitPerUserReached(
					int256(accountLayout.balances[msg.sender][collateral].isolatedBalance),
					amount,
					appLayout.balanceLimitPerUser[collateral]
				);
		}

		msg.sender.requireSolvent(counterParty, collateral, MarginType.ISOLATED);
		msg.sender.requireSolvent(counterParty, collateral, MarginType.CROSS);

		accountLayout.balances[msg.sender][collateral].deallocateBalance(counterParty, amount);
	}

	function allocateToReserveBalance(address collateral, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (AppStorage.layout().partyBConfigs[msg.sender].isActive) msg.sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);
		if (
			accountLayout.balances[msg.sender][collateral].isolatedBalance - accountLayout.balances[msg.sender][collateral].isolatedLockedBalance <
			amount
		)
			revert CommonErrors.InsufficientBalance(
				msg.sender,
				collateral,
				amount,
				accountLayout.balances[msg.sender][collateral].isolatedBalance - accountLayout.balances[msg.sender][collateral].isolatedLockedBalance
			);
		if (
			!appLayout.partyBConfigs[msg.sender].isActive &&
			(accountLayout.balances[msg.sender][collateral].reserveBalance + amount > appLayout.balanceLimitPerUser[collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[msg.sender][collateral].reserveBalance),
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);
		accountLayout.balances[msg.sender][collateral].isolatedBalance -= amount;
		accountLayout.balances[msg.sender][collateral].reserveBalance += amount;
	}

	function deallocateFromReserveBalance(address collateral, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (AppStorage.layout().partyBConfigs[msg.sender].isActive) msg.sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);
		if (accountLayout.balances[msg.sender][collateral].reserveBalance < amount)
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, accountLayout.balances[msg.sender][collateral].reserveBalance);
		if (
			!appLayout.partyBConfigs[msg.sender].isActive &&
			(accountLayout.balances[msg.sender][collateral].isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[msg.sender][collateral].isolatedBalance),
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);
		accountLayout.balances[msg.sender][collateral].isolatedBalance += amount;
		accountLayout.balances[msg.sender][collateral].reserveBalance -= amount;
	}

	// Validation functions
	function deallocateForPartyAValidation(address collateral, address counterParty, int256 amount, UpnlSig memory upnlSig) internal view {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[counterParty];

		CrossEntry memory partyACrossEntry = accountLayout.balances[msg.sender][collateral].crossBalance[counterParty];
		int256 partyAAvailableBalance = partyACrossEntry.balance +
			((upnlSig.partyUpnl * 1e18) / int256(upnlSig.collateralPrice)) -
			int256(partyACrossEntry.totalMM) -
			int256(partyACrossEntry.locked);
		// min balance and available balance
		int256 partyAReadyToDeallocate = partyACrossEntry.balance < partyAAvailableBalance ? partyACrossEntry.balance : partyAAvailableBalance;

		if (amount > partyAReadyToDeallocate) revert AccountFacetErrors.NotEnoughBalance(msg.sender, counterParty, partyAReadyToDeallocate, amount);

		CrossEntry memory partyBCrossEntry = accountLayout.balances[counterParty][collateral].crossBalance[msg.sender];
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
			if (partyAReadyToDeallocate - amount < (-debt))
				revert AccountFacetErrors.RemainingAmountMoreThanCounterPartyDebt(msg.sender, counterParty, partyAReadyToDeallocate, amount, debt);
		}
	}

	function deallocateForPartyBValidation(address collateral, address counterParty, int256 amount, UpnlSig memory upnlSig) internal view {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		PartyBConfig storage partyBConfig = AppStorage.layout().partyBConfigs[msg.sender];

		CrossEntry memory partyACrossEntry = accountLayout.balances[counterParty][collateral].crossBalance[msg.sender];
		int256 partyAAvailableBalance = partyACrossEntry.balance +
			((upnlSig.counterPartyUpnl * 1e18) / int256(upnlSig.collateralPrice)) -
			int256(partyACrossEntry.totalMM);

		CrossEntry memory partyBCrossEntry = accountLayout.balances[msg.sender][collateral].crossBalance[counterParty];
		int256 partyBAvailableBalance = partyBCrossEntry.balance + ((upnlSig.partyUpnl * 1e18) / int256(upnlSig.collateralPrice));

		// partyA solvent
		if (partyAAvailableBalance < 0) revert AccountFacetErrors.PartyShouldBeLiquidated(counterParty);

		if (upnlSig.partyUpnl >= 0) {
			// partyB solvent if upnl is pos and balance be positive
			int256 partyBReadyToDeallocate = partyBCrossEntry.balance < partyBAvailableBalance ? partyBCrossEntry.balance : partyBAvailableBalance;
			if (amount > partyBReadyToDeallocate)
				revert AccountFacetErrors.NotEnoughBalance(msg.sender, counterParty, partyBReadyToDeallocate, amount);
		} else {
			// partyB solvent with loss coverage
			int256 collateralMustHave = (-upnlSig.partyUpnl * int256(partyBConfig.lossCoverage)) / int256(upnlSig.collateralPrice);
			if (partyBCrossEntry.balance - amount < collateralMustHave) revert AccountFacetErrors.PartyShouldBeLiquidated(msg.sender);
		}
	}
}
