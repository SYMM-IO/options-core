// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";
import { LibMuon } from "../../libraries/LibMuon.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage, PartyBConfig } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { Withdraw, WithdrawStatus, UpnlSig } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason, CrossEntry } from "../../types/BalanceTypes.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AccountFacetErrors } from "./AccountFacetErrors.sol";

library AccountFacetImpl {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	// Constants
	uint256 private constant PRECISION_FACTOR = 1e18;

	function deposit(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) {
			revert CommonErrors.CollateralNotWhitelisted(collateral);
		}
		if (amount == 0) revert CommonErrors.InvalidAmount("amount", amount, 0, 0);
		if (user == address(0)) revert CommonErrors.ZeroAddress("user");

		uint256 amountWith18Decimals = _normalizeAmount(collateral, amount);
		if (
			!appLayout.partyBConfigs[user].isActive &&
			(accountLayout.balances[user][collateral].isolatedBalance + amountWith18Decimals > appLayout.balanceLimitPerUser[collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[user][collateral].isolatedBalance),
				amountWith18Decimals,
				appLayout.balanceLimitPerUser[collateral]
			);

		IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amountWith18Decimals, IncreaseBalanceReason.DEPOSIT);
	}

	function securedDepositFor(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) {
			revert CommonErrors.CollateralNotWhitelisted(collateral);
		}
		if (
			!appLayout.partyBConfigs[user].isActive &&
			(accountLayout.balances[user][collateral].isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[user][collateral].isolatedBalance),
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amount, IncreaseBalanceReason.DEPOSIT);
	}

	function internalTransfer(address collateral, address user, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		accountLayout.balances[msg.sender][collateral].syncAll();

		uint256 available = accountLayout.balances[msg.sender][collateral].isolatedBalance -
			accountLayout.balances[msg.sender][collateral].isolatedLockedBalance;
		if (available < amount) {
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, available);
		}

		if (
			!appLayout.partyBConfigs[user].isActive &&
			(accountLayout.balances[user][collateral].isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[user][collateral].isolatedBalance),
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		if (CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender]) revert AccountFacetErrors.InstantActionModeActive(msg.sender);

		accountLayout.balances[msg.sender][collateral].isolatedSub(amount, DecreaseBalanceReason.INTERNAL_TRANSFER);
		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amount, IncreaseBalanceReason.INTERNAL_TRANSFER);
	}

	function initiateWithdraw(address collateral, uint256 amount, address to) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (to == address(0)) revert CommonErrors.ZeroAddress("to");
		if (amount == 0) revert CommonErrors.InvalidAmount("amount", amount, 0, 0);

		if (!accountLayout.manualSync[msg.sender]) {
			accountLayout.balances[msg.sender][collateral].syncAll();
		}

		uint256 available = accountLayout.balances[msg.sender][collateral].isolatedBalance -
			accountLayout.balances[msg.sender][collateral].isolatedLockedBalance;
		if (available < amount) {
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, available);
		}

		if (CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender]) revert AccountFacetErrors.InstantActionModeActive(msg.sender);

		msg.sender.requireSolventParty(address(0), collateral, MarginType.ISOLATED);

		accountLayout.balances[msg.sender][collateral].isolatedSub(amount, DecreaseBalanceReason.WITHDRAW);

		currentId = ++accountLayout.lastWithdrawId;
		Withdraw memory withdrawObject = Withdraw({
			id: currentId,
			amount: amount,
			user: msg.sender,
			collateral: collateral,
			to: to,
			timestamp: block.timestamp,
			status: WithdrawStatus.INITIATED
		});

		accountLayout.withdrawals[currentId] = withdrawObject;
	}

	function completeWithdraw(uint256 id) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (id > accountLayout.lastWithdrawId) {
			revert AccountFacetErrors.InvalidWithdrawId(id, accountLayout.lastWithdrawId);
		}

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		if (withdrawal.status != WithdrawStatus.INITIATED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(WithdrawStatus.INITIATED);
			revert CommonErrors.InvalidState("WithdrawStatus", uint8(withdrawal.status), requiredStatuses);
		}

		if (!appLayout.whiteListedCollateral[withdrawal.collateral]) revert CommonErrors.CollateralNotWhitelisted(withdrawal.collateral);

		uint256 cooldownPeriod;
		if (appLayout.partyBConfigs[withdrawal.user].isActive) {
			cooldownPeriod = appLayout.partyBDeallocateCooldown;
		} else {
			cooldownPeriod = appLayout.partyADeallocateCooldown;
		}

		if (block.timestamp < cooldownPeriod + withdrawal.timestamp) {
			revert CommonErrors.CooldownNotOver("withdraw", block.timestamp, cooldownPeriod + withdrawal.timestamp);
		}

		withdrawal.status = WithdrawStatus.COMPLETED;

		uint256 amountInCollateralDecimals = _denormalizeAmount(withdrawal.collateral, withdrawal.amount);
		IERC20(withdrawal.collateral).safeTransfer(withdrawal.to, amountInCollateralDecimals);
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (id > accountLayout.lastWithdrawId) {
			revert AccountFacetErrors.InvalidWithdrawId(id, accountLayout.lastWithdrawId);
		}

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		if (withdrawal.status != WithdrawStatus.INITIATED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(WithdrawStatus.INITIATED);
			revert CommonErrors.InvalidState("WithdrawStatus", uint8(withdrawal.status), requiredStatuses);
		}
		if (
			!appLayout.partyBConfigs[withdrawal.user].isActive &&
			(accountLayout.balances[withdrawal.user][withdrawal.collateral].isolatedBalance + withdrawal.amount >
				appLayout.balanceLimitPerUser[withdrawal.collateral])
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				int256(accountLayout.balances[withdrawal.user][withdrawal.collateral].isolatedBalance),
				withdrawal.amount,
				appLayout.balanceLimitPerUser[withdrawal.collateral]
			);

		withdrawal.status = WithdrawStatus.CANCELED;
		accountLayout.balances[withdrawal.user][withdrawal.collateral].instantIsolatedAdd(withdrawal.amount, IncreaseBalanceReason.DEPOSIT);
	}

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		for (uint256 i = 0; i < partyBs.length; i++) {
			accountLayout.balances[partyA][collateral].sync(partyBs[i]);
		}
	}

	function allocate(address collateral, address counterParty, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (
			(!appLayout.partyBConfigs[counterParty].isActive && !appLayout.partyBConfigs[msg.sender].isActive) ||
			(appLayout.partyBConfigs[counterParty].isActive && appLayout.partyBConfigs[msg.sender].isActive)
		) revert AccountFacetErrors.InvalidCounterPartyToAllocate(msg.sender, counterParty);
		if (CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender]) revert AccountFacetErrors.InstantActionModeActive(msg.sender);
		if (
			!appLayout.partyBConfigs[msg.sender].isActive &&
			(accountLayout.balances[msg.sender][collateral].crossBalance[counterParty].balance + int256(amount) >
				int256(appLayout.balanceLimitPerUser[collateral]))
		)
			revert AccountFacetErrors.BalanceLimitPerUserReached(
				accountLayout.balances[msg.sender][collateral].crossBalance[counterParty].balance,
				amount,
				appLayout.balanceLimitPerUser[collateral]
			);

		accountLayout.balances[msg.sender][collateral].allocateBalance(counterParty, amount);
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
		accountLayout.balances[msg.sender][collateral].deallocateBalance(counterParty, amount);
	}

	function activateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();

		if (layout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeAlreadyActivated(msg.sender);
		}

		layout.instantActionsMode[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();

		if (!layout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeNotActivated(msg.sender);
		}

		layout.instantActionsModeDeactivateTime[msg.sender] = block.timestamp + layout.deactiveInstantActionModeCooldown;
	}

	function deactivateInstantActionMode() internal {
		CounterPartyRelationsStorage.Layout storage layout = CounterPartyRelationsStorage.layout();

		if (!layout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeNotActivated(msg.sender);
		}

		if (layout.instantActionsModeDeactivateTime[msg.sender] == 0) {
			revert AccountFacetErrors.InstantActionModeDeactivationNotProposed(msg.sender);
		}

		if (layout.instantActionsModeDeactivateTime[msg.sender] > block.timestamp) {
			revert CommonErrors.CooldownNotOver("deactiveInstantActionMode", block.timestamp, layout.instantActionsModeDeactivateTime[msg.sender]);
		}

		layout.instantActionsMode[msg.sender] = false;
		layout.instantActionsModeDeactivateTime[msg.sender] = 0;
	}

	function bindToPartyB(address partyB) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();

		if (!appLayout.partyBConfigs[partyB].isActive) {
			revert AccountFacetErrors.PartyBNotActive(partyB);
		}

		if (counterPartyRelationsLayout.boundPartyB[msg.sender] != address(0)) {
			revert AccountFacetErrors.AlreadyBoundToPartyB(msg.sender, counterPartyRelationsLayout.boundPartyB[msg.sender]);
		}

		counterPartyRelationsLayout.boundPartyB[msg.sender] = partyB;
	}

	function initiateUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();
		address currentPartyB = counterPartyRelationsLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert AccountFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] != 0) {
			revert AccountFacetErrors.UnbindingAlreadyInitiated(msg.sender, counterPartyRelationsLayout.unbindingRequestTime[msg.sender]);
		}

		counterPartyRelationsLayout.unbindingRequestTime[msg.sender] = block.timestamp;
	}

	function completeUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();
		address currentPartyB = counterPartyRelationsLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert AccountFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] == 0) {
			revert AccountFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		uint256 requiredTime = counterPartyRelationsLayout.unbindingRequestTime[msg.sender] + counterPartyRelationsLayout.unbindingCooldown;
		if (block.timestamp < requiredTime) {
			revert CommonErrors.CooldownNotOver("unbinding", block.timestamp, requiredTime);
		}

		delete counterPartyRelationsLayout.boundPartyB[msg.sender];
		delete counterPartyRelationsLayout.unbindingRequestTime[msg.sender];
	}

	function cancelUnbindingFromPartyB() internal {
		CounterPartyRelationsStorage.Layout storage counterPartyRelationsLayout = CounterPartyRelationsStorage.layout();

		if (counterPartyRelationsLayout.unbindingRequestTime[msg.sender] == 0) {
			revert AccountFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		delete counterPartyRelationsLayout.unbindingRequestTime[msg.sender];
	}

	function allocateToReserveBalance(address collateral, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		msg.sender.requireSolventParty(address(0), collateral, MarginType.ISOLATED);
		if (
			accountLayout.balances[msg.sender][collateral].isolatedBalance - accountLayout.balances[msg.sender][collateral].isolatedLockedBalance <
			amount
		)
			// revert InsufficientBalance(self.collateral, amount, int256(self.isolatedBalance));
			revert();
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

		msg.sender.requireSolventParty(address(0), collateral, MarginType.ISOLATED);
		if (accountLayout.balances[msg.sender][collateral].reserveBalance < amount)
			// revert InsufficientBalance(self.collateral, amount, int256(self.isolatedBalance));
			revert();
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

	// Helper functions
	function _normalizeAmount(address token, uint256 amount) private view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * PRECISION_FACTOR) / (10 ** decimals);
	}

	function _denormalizeAmount(address token, uint256 amount) private view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * (10 ** decimals)) / PRECISION_FACTOR;
	}

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
				int256 collatearlMustHave = (-upnlSig.counterPartyUpnl * int256(partyBConfig.lossCoverage)) / int256(upnlSig.collateralPrice);
				debt = collatearlMustHave - partyBCrossEntry.balance;
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
		if (partyAAvailableBalance < 0) revert();

		if (upnlSig.partyUpnl >= 0) {
			// partyB solvent if upnl is pos and balance be positive
			int256 partyBReadyToDeallocate = partyBCrossEntry.balance < partyBAvailableBalance ? partyBCrossEntry.balance : partyBAvailableBalance;
			if (amount > partyBReadyToDeallocate)
				revert AccountFacetErrors.NotEnoughBalance(msg.sender, counterParty, partyBReadyToDeallocate, amount);
		} else {
			// partyB solvent with loss coverage
			int256 collatearlMustHave = (-upnlSig.partyUpnl * int256(partyBConfig.lossCoverage)) / int256(upnlSig.collateralPrice);
			if (partyBCrossEntry.balance - amount < collatearlMustHave) revert();
		}
	}
}
