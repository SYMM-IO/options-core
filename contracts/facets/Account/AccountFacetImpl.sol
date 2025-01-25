// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/AppStorage.sol";

library AccountFacetImpl {
	using SafeERC20 for IERC20;

	function deposit(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral isn't white listed");
		IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(collateral).decimals());
		AccountStorage.layout().balances[user][collateral] += amountWith18Decimals;
	}

	function withdraw(address collateral, uint256 amount, address to) internal returns (uint256 currentId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(AppStorage.layout().whiteListedCollateral[collateral], "AccountFacet: Collateral isn't white listed");
		require(to != address(0), "AccountFacet: Zero address");
		require(
			accountLayout.balances[msg.sender][collateral] - accountLayout.lockedBalances[msg.sender][collateral] >= amount,
			"AccountFacet: Insufficient balance"
		);
		require(!accountLayout.isInstantActionModeActivated[msg.sender], "AccountFacet: Instant action mode is activated");

		accountLayout.balances[msg.sender][collateral] -= amount;

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
		accountLayout.withdraws[currentId] = withdrawObject;
		accountLayout.withdrawIds[msg.sender].push(currentId);
	}

	function claimWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Withdraw storage withdrawObject = accountLayout.withdraws[id];
		require(id <= accountLayout.lastWithdrawId, "AccountFacet: Invalid Id");
		require(withdrawObject.status == WithdrawStatus.INITIATED, "AccountFacet: Already withdrawn");
		if (AppStorage.layout().partyBConfigs[withdrawObject.user].isActive) {
			require(
				block.timestamp >= AppStorage.layout().partyBDeallocateCooldown + withdrawObject.timestamp,
				"AccountFacet: Cooldown hasn't reached"
			);
		} else {
			require(
				block.timestamp >= AppStorage.layout().partyADeallocateCooldown + withdrawObject.timestamp,
				"AccountFacet: Cooldown hasn't reached"
			);
		}

		require(withdrawObject.user != address(0), "AccountFacet: Zero address");

		withdrawObject.status = WithdrawStatus.COMPLETED;
		uint256 amountInCollateralDecimals = (withdrawObject.amount * (10 ** IERC20Metadata(withdrawObject.collateral).decimals())) / 1e18;
		IERC20(withdrawObject.collateral).safeTransfer(withdrawObject.to, amountInCollateralDecimals);
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Withdraw storage withdrawObject = accountLayout.withdraws[id];
		require(id <= accountLayout.lastWithdrawId, "AccountFacet: Invalid Id");
		require(withdrawObject.status == WithdrawStatus.INITIATED, "AccountFacet: Already withdrawn");
		require(withdrawObject.user != address(0), "AccountFacet: Zero address");

		withdrawObject.status = WithdrawStatus.CANCELED;
		accountLayout.balances[withdrawObject.user][withdrawObject.collateral] += withdrawObject.amount;
	}

	function activateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(!accountLayout.isInstantActionModeActivated[msg.sender], "AccountFacet: Instant action mode is already activated");
		accountLayout.isInstantActionModeActivated[msg.sender] = true;
	}

	function proposeToDeactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(accountLayout.isInstantActionModeActivated[msg.sender], "AccountFacet: Instant action mode isn't activated");
		accountLayout.deactiveInstantActionModeProposalTimestamp[msg.sender] = block.timestamp;
	}

	function deactivateInstantActionMode() internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(accountLayout.isInstantActionModeActivated[msg.sender], "AccountFacet: Instant action mode isn't activated");
		require(accountLayout.deactiveInstantActionModeProposalTimestamp[msg.sender] != 0, "AccountFacet: Proposal hasn't been set");
		require(
			accountLayout.deactiveInstantActionModeProposalTimestamp[msg.sender] + accountLayout.deactiveInstantActionModeCooldown <= block.timestamp,
			"AccountFacet: Cooldown not reached"
		);
		accountLayout.isInstantActionModeActivated[msg.sender] = false;
		accountLayout.deactiveInstantActionModeProposalTimestamp[msg.sender] = 0;
	}
}
