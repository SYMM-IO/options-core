// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibDecimals } from "../utils/LibDecimals.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { CommonErrors } from "../../errors/CommonErrors.sol";
import { AccountErrors } from "../../errors/AccountErrors.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { Withdraw, WithdrawStatus } from "../../types/WithdrawTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


library LibBalanceOperations {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function deposit(address collateral, address user, uint256 amount) internal {
		_deposit(collateral, user, amount, true);
	}

	function securedDepositFor(address collateral, address user, uint256 amount) internal {
		_deposit(collateral, user, amount, false);
	}

	function _deposit(address collateral, address user, uint256 amount, bool doTransfer) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (!appLayout.whiteListedCollateral[collateral]) revert CommonErrors.CollateralNotWhitelisted(collateral);
		if (amount == 0) revert CommonErrors.InvalidAmount("amount", amount, 0, 0);
		if (user == address(0)) revert CommonErrors.ZeroAddress("user");
		user.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		ScheduledReleaseBalance storage balance = user.balanceOf(collateral);

		uint256 amountWith18Decimals = LibDecimals.normalizeAmount(collateral, amount);
		if (!user.isPartyB() && (balance.isolatedBalance + amountWith18Decimals > appLayout.balanceLimitPerUser[collateral]))
			revert AccountErrors.BalanceLimitExceeded(
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

		if (amount == 0) revert CommonErrors.InvalidAmount("amount", amount, 0, 0);
		if (receiver == address(0)) revert CommonErrors.ZeroAddress("user");

		ScheduledReleaseBalance storage sourceBalance = sender.balanceOf(collateral);
		ScheduledReleaseBalance storage targetBalance = receiver.balanceOf(collateral);

		sourceBalance.syncAll();

		uint256 available = sourceBalance.isolatedBalance - sourceBalance.isolatedLockedBalance;
		if (available < amount) revert CommonErrors.InsufficientBalance(sender, collateral, amount, available);

		if (!receiver.isPartyB() && (targetBalance.isolatedBalance + amount > appLayout.balanceLimitPerUser[collateral]))
			revert AccountErrors.BalanceLimitExceeded(int256(targetBalance.isolatedBalance), amount, appLayout.balanceLimitPerUser[collateral]);

		sourceBalance.isolatedSub(amount, DecreaseBalanceReason.INTERNAL_TRANSFER);
		targetBalance.setup(receiver, collateral);
		targetBalance.instantIsolatedAdd(amount, IncreaseBalanceReason.INTERNAL_TRANSFER);
	}

	function initiateWithdraw(address sender, address collateral, uint256 amount, address to) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (to == address(0)) revert CommonErrors.ZeroAddress("to");
		if (amount == 0) revert CommonErrors.InvalidAmount("amount", amount, 0, 0);

		ScheduledReleaseBalance storage balance = sender.balanceOf(collateral);

		if (!accountLayout.manualSync[sender]) balance.syncAll();

		uint256 available = balance.isolatedBalance - balance.isolatedLockedBalance;
		if (available < amount) revert CommonErrors.InsufficientBalance(sender, collateral, amount, available);
		sender.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		balance.isolatedSub(amount, DecreaseBalanceReason.WITHDRAW);

		currentId = ++accountLayout.lastWithdrawId;
		Withdraw memory withdrawObject = Withdraw({
			id: currentId,
			amount: amount,
			user: sender,
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

		if (id > accountLayout.lastWithdrawId) revert AccountErrors.InvalidWithdrawalId(id);

		Withdraw storage withdrawal = accountLayout.withdrawals[id];

		CommonErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));

		uint256 cooldownPeriod;
		if (withdrawal.user.isPartyB()) {
			cooldownPeriod = appLayout.partyBDeallocateCooldown;
		} else {
			cooldownPeriod = appLayout.partyADeallocateCooldown;
		}

		if (block.timestamp < cooldownPeriod + withdrawal.timestamp) {
			revert CommonErrors.CooldownNotOver("withdraw", block.timestamp, cooldownPeriod + withdrawal.timestamp);
		}

		withdrawal.status = WithdrawStatus.COMPLETED;

		uint256 amountInCollateralDecimals = LibDecimals.denormalizeAmount(withdrawal.collateral, withdrawal.amount);
		IERC20(withdrawal.collateral).safeTransfer(withdrawal.to, amountInCollateralDecimals);
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (id > accountLayout.lastWithdrawId) revert AccountErrors.InvalidWithdrawalId(id);

		Withdraw storage withdrawal = accountLayout.withdrawals[id];
		ScheduledReleaseBalance storage balance = withdrawal.user.balanceOf(withdrawal.collateral);

		CommonErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));

		if (!withdrawal.user.isPartyB() && (balance.isolatedBalance + withdrawal.amount > appLayout.balanceLimitPerUser[withdrawal.collateral]))
			revert AccountErrors.BalanceLimitExceeded(
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
