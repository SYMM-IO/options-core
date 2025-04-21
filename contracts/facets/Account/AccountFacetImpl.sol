// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason, MarginType } from "../../libraries/LibScheduledReleaseBalance.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { AccountFacetErrors } from "./AccountFacetErrors.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage, Withdraw, WithdrawStatus } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library AccountFacetImpl {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibPartyB for address;

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

		accountLayout.balances[msg.sender][collateral].syncAll(MarginType.ISOLATED);

		uint256 available = accountLayout.balances[msg.sender][collateral].isolatedBalance;
		if (available < amount) {
			revert CommonErrors.InsufficientBalance(msg.sender, collateral, amount, available);
		}

		if (accountLayout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeActive(msg.sender);
		}

		msg.sender.requireSolvent(collateral);

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

		withdrawal.user.requireSolvent(withdrawal.collateral);

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

	function syncBalances(address collateral, address partyA, address[] calldata partyBs, MarginType marginType) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		for (uint256 i = 0; i < partyBs.length; i++) {
			accountLayout.balances[partyA][collateral].sync(partyBs[i], marginType);
		}
	}

	function allocate(address collateral, address counterParty, uint256 amount) internal {
		AccountStorage.layout().balances[msg.sender][collateral].allocateBalance(counterParty, amount);
	}

	function deallocate(address collateral, address counterParty, uint256 amount) internal {
		AccountStorage.layout().balances[msg.sender][collateral].deallocateBalance(counterParty, amount);
	}

	function activateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (accountLayout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeAlreadyActivated(msg.sender);
		}

		accountLayout.instantActionsMode[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!accountLayout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeNotActivated(msg.sender);
		}

		accountLayout.instantActionsModeDeactivateTime[msg.sender] = block.timestamp + accountLayout.deactiveInstantActionModeCooldown;
	}

	function deactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!accountLayout.instantActionsMode[msg.sender]) {
			revert AccountFacetErrors.InstantActionModeNotActivated(msg.sender);
		}

		if (accountLayout.instantActionsModeDeactivateTime[msg.sender] == 0) {
			revert AccountFacetErrors.InstantActionModeDeactivationNotProposed(msg.sender);
		}

		if (accountLayout.instantActionsModeDeactivateTime[msg.sender] > block.timestamp) {
			revert CommonErrors.CooldownNotOver(
				"deactiveInstantActionMode",
				block.timestamp,
				accountLayout.instantActionsModeDeactivateTime[msg.sender]
			);
		}

		accountLayout.instantActionsMode[msg.sender] = false;
		accountLayout.instantActionsModeDeactivateTime[msg.sender] = 0;
	}

	function bindToPartyB(address partyB) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (!appLayout.partyBConfigs[partyB].isActive) {
			revert AccountFacetErrors.PartyBNotActive(partyB);
		}

		if (accountLayout.boundPartyB[msg.sender] != address(0)) {
			revert AccountFacetErrors.AlreadyBoundToPartyB(msg.sender, accountLayout.boundPartyB[msg.sender]);
		}

		accountLayout.boundPartyB[msg.sender] = partyB;
	}

	function initiateUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address currentPartyB = accountLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert AccountFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (accountLayout.unbindingRequestTime[msg.sender] != 0) {
			revert AccountFacetErrors.UnbindingAlreadyInitiated(msg.sender, accountLayout.unbindingRequestTime[msg.sender]);
		}

		accountLayout.unbindingRequestTime[msg.sender] = block.timestamp;
	}

	function completeUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address currentPartyB = accountLayout.boundPartyB[msg.sender];

		if (currentPartyB == address(0)) {
			revert AccountFacetErrors.NotBoundToAnyPartyB(msg.sender);
		}

		if (accountLayout.unbindingRequestTime[msg.sender] == 0) {
			revert AccountFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		uint256 requiredTime = accountLayout.unbindingRequestTime[msg.sender] + accountLayout.unbindingCooldown;
		if (block.timestamp < requiredTime) {
			revert CommonErrors.CooldownNotOver("unbinding", block.timestamp, requiredTime);
		}

		delete accountLayout.boundPartyB[msg.sender];
		delete accountLayout.unbindingRequestTime[msg.sender];
	}

	function cancelUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (accountLayout.unbindingRequestTime[msg.sender] == 0) {
			revert AccountFacetErrors.UnbindingNotInitiated(msg.sender);
		}

		delete accountLayout.unbindingRequestTime[msg.sender];
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
