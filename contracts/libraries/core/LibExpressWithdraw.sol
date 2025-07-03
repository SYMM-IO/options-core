// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibDecimals } from "../utils/LibDecimals.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";
import { LibParty } from "../models/LibParty.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { ExpressWithdrawStorage } from "../../storages/ExpressWithdrawStorage.sol";

import { ExpressWithdraw, ExpressWithdrawStatus } from "../../types/ExpressWithdrawTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { BalanceErrors } from "../../errors/BalanceErrors.sol";

library LibExpressWithdraw {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibParty for address;

	function expressWithdraw(
		address sender,
		address collateral,
		uint256 amount,
		address provider,
		address receiver
	) internal returns (uint256 currentId) {
		ExpressWithdrawStorage.Layout storage expressWithdrawLayout = ExpressWithdrawStorage.layout();

		if (!expressWithdrawLayout.providers[provider]) revert BalanceErrors.ProviderNotWhitelisted(provider);
		if (provider == sender) revert BalanceErrors.SelfProviderNotAllowed(provider);
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("receiver");

		ScheduledReleaseBalance storage balance = sender.balanceOf(collateral);
		balance.syncAll();

		if (balance.isolatedBalance - balance.isolatedLockedBalance < amount)
			revert BalanceErrors.InsufficientBalance(sender, collateral, amount, balance.isolatedBalance);

		currentId = ++expressWithdrawLayout.lastExpressWithdrawId;
		ExpressWithdraw memory withdraw = ExpressWithdraw({
			id: currentId,
			amount: amount,
			collateral: collateral,
			sender: sender,
			receiver: receiver,
			provider: provider,
			timestamp: block.timestamp,
			status: ExpressWithdrawStatus.RECEIVED
		});

		balance.isolatedSub(LibDecimals.normalizeAmount(collateral, amount), DecreaseBalanceReason.EXPRESS_WITHDRAW);

		expressWithdrawLayout.expressWithdraws[currentId] = withdraw;
	}

	function collectReceivedExpressWithdraws(uint256[] memory expressWithdrawIds) internal {
		ExpressWithdrawStorage.Layout storage expressWithdrawLayout = ExpressWithdrawStorage.layout();

		uint256 totalAmount = 0;
		if (expressWithdrawIds.length == 0) revert ValidationErrors.EmptyList();

		address collateral = expressWithdrawLayout.expressWithdraws[expressWithdrawIds[0]].collateral;
		for (uint256 i = expressWithdrawIds.length; i != 0; i--) {
			uint256 expressWithdrawId = expressWithdrawIds[i - 1];
			if (expressWithdrawId > expressWithdrawLayout.lastExpressWithdrawId) revert BalanceErrors.ExpressWithdrawIdNotFound(expressWithdrawId);

			ExpressWithdraw storage withdraw = expressWithdrawLayout.expressWithdraws[expressWithdrawId];

			if (collateral != withdraw.collateral) revert BalanceErrors.MismatchedCollateral(collateral, withdraw.collateral);

			ValidationErrors.requireStatus("ExpressWithdrawStatus", uint8(withdraw.status), uint8(ExpressWithdrawStatus.RECEIVED));

			if (block.timestamp < AppStorage.layout().partyADeallocateCooldown + withdraw.timestamp)
				revert ValidationErrors.CooldownNotOver(
					"withdraw",
					block.timestamp,
					AppStorage.layout().partyADeallocateCooldown + withdraw.timestamp
				);

			if (withdraw.provider != msg.sender) revert ValidationErrors.UnauthorizedSender(msg.sender, withdraw.provider);

			totalAmount += withdraw.amount;
			withdraw.status = ExpressWithdrawStatus.WITHDRAWN;
		}

		IERC20(collateral).safeTransfer(msg.sender, totalAmount);
	}

	function suspendExpressWithdraw(uint256 expressWithdrawId) internal {
		ExpressWithdrawStorage.Layout storage expressWithdrawLayout = ExpressWithdrawStorage.layout();
		ExpressWithdraw storage withdraw = expressWithdrawLayout.expressWithdraws[expressWithdrawId];

		if (expressWithdrawId > expressWithdrawLayout.lastExpressWithdrawId) revert BalanceErrors.ExpressWithdrawIdNotFound(expressWithdrawId);

		ValidationErrors.requireStatus("ExpressWithdrawStatus", uint8(withdraw.status), uint8(ExpressWithdrawStatus.RECEIVED));

		withdraw.status = ExpressWithdrawStatus.SUSPENDED;
	}

	function restoreExpressWithdraw(uint256 expressWithdrawId, uint256 validAmount) internal {
		ExpressWithdrawStorage.Layout storage expressWithdrawLayout = ExpressWithdrawStorage.layout();
		ExpressWithdraw storage withdraw = expressWithdrawLayout.expressWithdraws[expressWithdrawId];

		ValidationErrors.requireStatus("ExpressWithdrawStatus", uint8(withdraw.status), uint8(ExpressWithdrawStatus.SUSPENDED));

		if (expressWithdrawLayout.invalidExpressWithdrawsPool == address(0)) revert ValidationErrors.ZeroAddress("invalidExpressWithdrawsPool");

		if (validAmount > withdraw.amount) revert BalanceErrors.ValidAmountExceedsOriginal(validAmount, withdraw.amount);

		ScheduledReleaseBalance storage balance = expressWithdrawLayout.invalidExpressWithdrawsPool.balanceOf(withdraw.collateral);

		balance.setup(expressWithdrawLayout.invalidExpressWithdrawsPool, withdraw.collateral);
		balance.instantIsolatedAdd(
			LibDecimals.normalizeAmount(withdraw.collateral, withdraw.amount - validAmount),
			IncreaseBalanceReason.EXPRESS_WITHDRAW
		);
		withdraw.status = ExpressWithdrawStatus.RECEIVED;
		withdraw.amount = validAmount;
	}
}
