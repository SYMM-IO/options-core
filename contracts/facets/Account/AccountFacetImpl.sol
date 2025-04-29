// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { CounterPartyRelationsStorage } from "../../storages/CounterPartyRelationsStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { Withdraw, WithdrawStatus } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

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
			revert AccountFacetErrors.CollateralNotWhitelisted(collateral);
		}
		IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

		uint256 amountWith18Decimals = _normalizeAmount(collateral, amount);
		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amountWith18Decimals, IncreaseBalanceReason.DEPOSIT);
	}

	function securedDepositFor(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) {
			revert AccountFacetErrors.CollateralNotWhitelisted(collateral);
		}
		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amount, IncreaseBalanceReason.DEPOSIT);
	}

	function internalTransfer(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) {
			revert AccountFacetErrors.CollateralNotWhitelisted(collateral);
		}

		uint256 available = accountLayout.balances[msg.sender][collateral].isolatedBalance;
		if (available < amount) {
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, available);
		}

		accountLayout.balances[msg.sender][collateral].isolatedSub(amount, DecreaseBalanceReason.INTERNAL_TRANSFER);
		accountLayout.balances[user][collateral].setup(user, collateral);
		accountLayout.balances[user][collateral].instantIsolatedAdd(amount, IncreaseBalanceReason.INTERNAL_TRANSFER);
	}

	function initiateWithdraw(address collateral, uint256 amount, address to) internal returns (uint256 currentId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) {
			revert AccountFacetErrors.CollateralNotWhitelisted(collateral);
		}

		if (to == address(0)) {
			revert CommonErrors.ZeroAddress("to");
		}

		accountLayout.balances[msg.sender][collateral].syncAll();

		uint256 available = accountLayout.balances[msg.sender][collateral].isolatedBalance -
			accountLayout.balances[msg.sender][collateral].isolatedLockedBalance;
		if (available < amount) {
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, available);
		}

		if (CounterPartyRelationsStorage.layout().instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeActive(msg.sender);
		}

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

		withdrawal.user.requireSolventParty(address(0), withdrawal.collateral, MarginType.ISOLATED);

		if (withdrawal.status != WithdrawStatus.INITIATED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(WithdrawStatus.INITIATED);
			revert CommonErrors.InvalidState("WithdrawStatus", uint8(withdrawal.status), requiredStatuses);
		}

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

		if (id > accountLayout.lastWithdrawId) {
			revert AccountFacetErrors.InvalidWithdrawId(id, accountLayout.lastWithdrawId);
		}

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		if (withdrawal.status != WithdrawStatus.INITIATED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(WithdrawStatus.INITIATED);
			revert CommonErrors.InvalidState("WithdrawStatus", uint8(withdrawal.status), requiredStatuses);
		}

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
		// TODO: check solvency
		AccountStorage.layout().balances[msg.sender][collateral].allocateBalance(counterParty, amount);
	}

	// TODO: add muon sig and check if both parites will be solvent after the deallocation
	function deallocate(address collateral, address counterParty, uint256 amount) internal {
		// TODO: check solvency
		AccountStorage.layout().balances[msg.sender][collateral].deallocateBalance(counterParty, amount);
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

	// Helper functions
	function _normalizeAmount(address token, uint256 amount) private view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * PRECISION_FACTOR) / (10 ** decimals);
	}

	function _denormalizeAmount(address token, uint256 amount) private view returns (uint256) {
		uint8 decimals = IERC20Metadata(token).decimals();
		return (amount * (10 ** decimals)) / PRECISION_FACTOR;
	}
}
