// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
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

		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral is not whitelisted");
		IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

		uint256 amountWith18Decimals = _normalizeAmount(collateral, amount);
		accountLayout.balances[user][collateral].instantAdd(collateral, amountWith18Decimals);
	}

	function securedDepositFor(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral is not whitelisted");
		accountLayout.balances[user][collateral].instantAdd(collateral, amount);
	}

	function internalTransfer(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral is not whitelisted");
		require(accountLayout.balances[msg.sender][collateral].available >= amount, "AccountFacet: Insufficient balance");

		accountLayout.balances[msg.sender][collateral].sub(amount);
		accountLayout.balances[user][collateral].instantAdd(collateral, amount);
	}

	function initiateWithdraw(address collateral, uint256 amount, address to) internal returns (uint256 currentId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral is not whitelisted");
		require(to != address(0), "AccountFacet: Zero address");

		accountLayout.balances[msg.sender][collateral].syncAll();

		require(accountLayout.balances[msg.sender][collateral].available >= amount, "AccountFacet: Insufficient balance");
		require(!accountLayout.instantActionsMode[msg.sender], "AccountFacet: Instant action mode is activated");
		msg.sender.requireSolvent(collateral);

		accountLayout.balances[msg.sender][collateral].sub(amount);

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

		require(id <= accountLayout.lastWithdrawId, "AccountFacet: Invalid Id");

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		withdrawal.user.requireSolvent(withdrawal.collateral);
		require(withdrawal.status == WithdrawStatus.INITIATED, "AccountFacet: Invalid state");

		uint256 cooldownPeriod;
		if (appLayout.partyBConfigs[withdrawal.user].isActive) {
			cooldownPeriod = appLayout.partyBDeallocateCooldown;
		} else {
			cooldownPeriod = appLayout.partyADeallocateCooldown;
		}

		require(block.timestamp >= cooldownPeriod + withdrawal.timestamp, "AccountFacet: Cooldown is not over yet");

		withdrawal.status = WithdrawStatus.COMPLETED;

		uint256 amountInCollateralDecimals = _denormalizeAmount(withdrawal.collateral, withdrawal.amount);
		IERC20(withdrawal.collateral).safeTransfer(withdrawal.to, amountInCollateralDecimals);
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(id <= accountLayout.lastWithdrawId, "AccountFacet: Invalid Id");

		Withdraw storage withdrawal = accountLayout.withdrawals[id];
		require(withdrawal.status == WithdrawStatus.INITIATED, "AccountFacet: Invalid state");

		withdrawal.status = WithdrawStatus.CANCELED;
		accountLayout.balances[withdrawal.user][withdrawal.collateral].instantAdd(withdrawal.collateral, withdrawal.amount);
	}

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		for (uint256 i = 0; i < partyBs.length; i++) {
			accountLayout.balances[partyA][collateral].sync(partyBs[i]);
		}
	}

	function activateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(!accountLayout.instantActionsMode[msg.sender], "AccountFacet: Instant actions mode is already activated");
		accountLayout.instantActionsMode[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(accountLayout.instantActionsMode[msg.sender], "AccountFacet: Instant actions mode isn't activated");
		accountLayout.instantActionsModeDeactivateTime[msg.sender] = block.timestamp + accountLayout.deactiveInstantActionModeCooldown;
	}

	function deactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(accountLayout.instantActionsMode[msg.sender], "AccountFacet: Instant actions mode isn't activated");
		require(accountLayout.instantActionsModeDeactivateTime[msg.sender] != 0, "AccountFacet: Deactivation is not proposed");
		require(accountLayout.instantActionsModeDeactivateTime[msg.sender] <= block.timestamp, "AccountFacet: Cooldown is not over yet");

		accountLayout.instantActionsMode[msg.sender] = false;
		accountLayout.instantActionsModeDeactivateTime[msg.sender] = 0;
	}

	function bindToPartyB(address partyB) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(appLayout.partyBConfigs[partyB].isActive, "ControlFacet: PartyB is not active");
		require(accountLayout.boundPartyB[msg.sender] == address(0), "ControlFacet: Already bound");

		accountLayout.boundPartyB[msg.sender] = partyB;
	}

	function initiateUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address currentPartyB = accountLayout.boundPartyB[msg.sender];

		require(currentPartyB != address(0), "ControlFacet: Not bound to any PartyB");
		require(accountLayout.unbindingRequestTime[msg.sender] == 0, "ControlFacet: Unbinding already initiated");

		accountLayout.unbindingRequestTime[msg.sender] = block.timestamp;
	}

	function completeUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address currentPartyB = accountLayout.boundPartyB[msg.sender];

		require(currentPartyB != address(0), "ControlFacet: Not bound to any PartyB");
		require(accountLayout.unbindingRequestTime[msg.sender] != 0, "ControlFacet: Unbinding not initiated");
		require(
			block.timestamp >= accountLayout.unbindingRequestTime[msg.sender] + accountLayout.unbindingCooldown,
			"ControlFacet: Unbinding cooldown not reached"
		);

		delete accountLayout.boundPartyB[msg.sender];
		delete accountLayout.unbindingRequestTime[msg.sender];
	}

	function cancelUnbindingFromPartyB() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(accountLayout.unbindingRequestTime[msg.sender] != 0, "ControlFacet: No pending unbinding");

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
