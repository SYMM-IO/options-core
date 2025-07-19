// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibDecimals } from "../utils/LibDecimals.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { BalanceErrors } from "../../errors/BalanceErrors.sol";
import { ValidationErrors } from "../../errors/ValidationErrors.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { Withdraw, WithdrawStatus, ExpressWithdrawProviderConfig } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { IExternalTransferTarget } from "../../interfaces/IExternalTransferTarget.sol";
import { IExpressWithdrawProvider } from "../../interfaces/IExpressWithdrawProvider.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library LibBalanceOperations {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function deposit(address collateral, address user, uint256 amount) internal {
		_deposit(collateral, user, amount, true);
	}

	function virtualDepositFor(address collateral, address user, uint256 amount) internal {
		_deposit(collateral, user, amount, false);
	}

	function _deposit(address collateral, address user, uint256 amount, bool doTransfer) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) revert ValidationErrors.CollateralNotWhitelisted(collateral);
		if (amount == 0) revert ValidationErrors.ZeroAmount();
		if (user == address(0)) revert ValidationErrors.ZeroAddress("user");
		user.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		ScheduledReleaseBalance storage balance = user.balanceOf(collateral);

		uint256 amountWith18Decimals = LibDecimals.normalizeAmount(collateral, amount);
		if (!user.isPartyB() && (balance.isolatedBalance + amountWith18Decimals > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(
				int256(balance.isolatedBalance),
				amountWith18Decimals,
				appLayout.balanceLimitPerUser[collateral]
			);

		if (doTransfer) IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

		balance.setup(user, collateral);
		balance.instantIsolatedAdd(amountWith18Decimals, IncreaseBalanceReason.DEPOSIT);
	}

	function internalTransfer(address collateral, address sender, address receiver, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (amount == 0) revert ValidationErrors.ZeroAmount();
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("user");

		ScheduledReleaseBalance storage sourceBalance = sender.balanceOf(collateral);
		ScheduledReleaseBalance storage targetBalance = receiver.balanceOf(collateral);

		sourceBalance.syncAll();

		uint256 available = sourceBalance.isolatedBalance - sourceBalance.isolatedLockedBalance;
		if (available < amount) revert BalanceErrors.InsufficientBalance(sender, collateral, amount, available);

		if (!receiver.isPartyB() && (targetBalance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert BalanceErrors.BalanceLimitExceeded(int256(targetBalance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);

		sourceBalance.isolatedSub(amount, DecreaseBalanceReason.INTERNAL_TRANSFER);
		targetBalance.setup(receiver, collateral);
		targetBalance.instantIsolatedAdd(amount, IncreaseBalanceReason.INTERNAL_TRANSFER);
	}

	function externalTransfer(address collateral, address sender, address receiver, uint256 amount, address target) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (amount == 0) revert ValidationErrors.ZeroAmount();
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("user");
		if (target == address(0)) revert ValidationErrors.ZeroAddress("target");
		if (!accountLayout.externalTransferTargets[target][collateral])
			revert ValidationErrors.ExternalTransferTargetNotWhitelisted(target, collateral);

		ScheduledReleaseBalance storage sourceBalance = sender.balanceOf(collateral);
		sourceBalance.isolatedSub(amount, DecreaseBalanceReason.EXTERNAL_TRANSFER);

		uint256 amountInCollateralDecimals = LibDecimals.denormalizeAmount(collateral, amount);
		IERC20(collateral).safeTransfer(target, amountInCollateralDecimals);

		IExternalTransferTarget(target).onTransfer(collateral, sender, receiver, amount);
	}

	function initiateWithdraw(
		address sender,
		address collateral,
		uint256 amount,
		address to,
		address provider,
		bytes memory userData
	) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (to == address(0)) revert ValidationErrors.ZeroAddress("to");
		if (amount == 0) revert ValidationErrors.ZeroAmount();

		ScheduledReleaseBalance storage balance = sender.balanceOf(collateral);

		if (!accountLayout.manualSync[sender]) balance.syncAll();

		uint256 available = balance.isolatedBalance - balance.isolatedLockedBalance;
		if (available < amount) revert BalanceErrors.InsufficientBalance(sender, collateral, amount, available);
		sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		bool isVirtual = false;
		if (provider != address(0)) {
			ExpressWithdrawProviderConfig storage providerConfig = accountLayout.expressWithdrawProviderConfigs[provider][collateral];
			if (!providerConfig.isActive) revert BalanceErrors.ExpressWithdrawProviderNotActive(provider);
			if (providerConfig.receiver == address(0)) revert ValidationErrors.ZeroAddress("receiver");

			isVirtual = providerConfig.isVirtual;

			(bool isValid, string memory reason) = IExpressWithdrawProvider(provider).validateWithdraw(sender, collateral, amount, to, userData);
			if (!isValid) revert BalanceErrors.ExpressWithdrawRejectedByProvider(provider, reason);
		}

		balance.isolatedSub(amount, DecreaseBalanceReason.WITHDRAW);

		currentId = ++accountLayout.lastWithdrawId;
		Withdraw memory withdrawObject = Withdraw({
			id: currentId,
			amount: amount,
			user: sender,
			collateral: collateral,
			to: to,
			provider: provider,
			userData: userData,
			timestamp: block.timestamp,
			status: WithdrawStatus.INITIATED,
			isVirtual: isVirtual
		});

		accountLayout.withdrawals[currentId] = withdrawObject;
	}

	function suspendWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));
		withdrawal.status = WithdrawStatus.SUSPENDED;
	}

	function restoreWithdraw(uint256 id, uint256 validAmount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.SUSPENDED));
		if (accountLayout.invalidWithdrawalsAmountsPool == address(0)) revert ValidationErrors.ZeroAddress("invalidWithdrawalsAmountsPool");
		if (validAmount > withdrawal.amount) revert BalanceErrors.ValidAmountExceedsOriginal(validAmount, withdrawal.amount);

		ScheduledReleaseBalance storage balance = accountLayout.invalidWithdrawalsAmountsPool.balanceOf(withdrawal.collateral);

		balance.setup(accountLayout.invalidWithdrawalsAmountsPool, withdrawal.collateral);
		balance.instantIsolatedAdd(
			LibDecimals.normalizeAmount(withdrawal.collateral, withdrawal.amount - validAmount),
			IncreaseBalanceReason.INVALID_WITHDRAWAL
		);

		withdrawal.status = WithdrawStatus.INITIATED;
		withdrawal.amount = validAmount;
	}

	function completeWithdraw(uint256 id) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (id > accountLayout.lastWithdrawId) revert BalanceErrors.InvalidWithdrawalId(id);

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));

		uint256 cooldownPeriod;
		if (withdrawal.user.isPartyB()) {
			cooldownPeriod = appLayout.partyBDeallocateCooldown;
		} else {
			cooldownPeriod = appLayout.partyADeallocateCooldown;
		}

		if (block.timestamp < cooldownPeriod + withdrawal.timestamp) {
			revert ValidationErrors.CooldownNotOver("withdraw", block.timestamp, cooldownPeriod + withdrawal.timestamp);
		}

		withdrawal.status = WithdrawStatus.COMPLETED;

		if (!withdrawal.isVirtual) {
			uint256 amountInCollateralDecimals = LibDecimals.denormalizeAmount(withdrawal.collateral, withdrawal.amount);
			address receiver = withdrawal.to;
			if (withdrawal.provider != address(0))
				receiver = accountLayout.expressWithdrawProviderConfigs[withdrawal.provider][withdrawal.collateral].receiver;
			IERC20(withdrawal.collateral).safeTransfer(receiver, amountInCollateralDecimals);
		}
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (id > accountLayout.lastWithdrawId) revert BalanceErrors.InvalidWithdrawalId(id);

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		if (withdrawal.provider != address(0)) revert BalanceErrors.ExpressWithdrawCancellationNotAllowed(withdrawal.provider);

		ScheduledReleaseBalance storage balance = withdrawal.user.balanceOf(withdrawal.collateral);

		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));

		if (!withdrawal.user.isPartyB() && (balance.isolatedBalance + withdrawal.amount > appLayout.balanceLimitPerUser[withdrawal.collateral]))
			revert BalanceErrors.BalanceLimitExceeded(
				int256(balance.isolatedBalance),
				withdrawal.amount,
				appLayout.balanceLimitPerUser[withdrawal.collateral]
			);
		withdrawal.user.requireSolvent(address(0), withdrawal.collateral, MarginType.ISOLATED);

		withdrawal.status = WithdrawStatus.CANCELED;
		balance.instantIsolatedAdd(withdrawal.amount, IncreaseBalanceReason.DEPOSIT);
	}

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) internal {
		for (uint256 i = 0; i < partyBs.length; i++) partyA.balanceOf(collateral).sync(partyBs[i]);
	}
}
