// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/AppStorage.sol";
import "../../libraries/LibScheduledReleaseBalance.sol";

library AccountFacetImpl {
	using SafeERC20 for IERC20;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	function deposit(address collateral, address user, uint256 amount) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(appLayout.whiteListedCollateral[collateral], "AccountFacet: Collateral is not whitelisted");
		IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
		uint256 amountWith18Decimals = (amount * 1e18) / (10 ** IERC20Metadata(collateral).decimals());
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
		accountLayout.balances[msg.sender][collateral].syncAll(block.timestamp);
		require(accountLayout.balances[msg.sender][collateral].available >= amount, "AccountFacet: Insufficient balance");
		require(!accountLayout.instantActionsMode[msg.sender], "AccountFacet: Instant action mode is activated");
		require(
			appLayout.liquidationDetails[msg.sender][collateral].status == LiquidationStatus.SOLVENT,
			"AccountFacet: PartyB is in the liquidation process"
		);
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

		Withdraw storage w = accountLayout.withdrawals[id];
		require(
			appLayout.liquidationDetails[w.user][w.collateral].status == LiquidationStatus.SOLVENT,
			"AccountFacet: PartyB is in the liquidation process"
		);
		require(w.status == WithdrawStatus.INITIATED, "AccountFacet: Invalid state");
		if (appLayout.partyBConfigs[w.user].isActive) {
			require(block.timestamp >= appLayout.partyBDeallocateCooldown + w.timestamp, "AccountFacet: Cooldown is not over yet");
		} else {
			require(block.timestamp >= appLayout.partyADeallocateCooldown + w.timestamp, "AccountFacet: Cooldown is not over yet");
		}

		w.status = WithdrawStatus.COMPLETED;
		uint256 amountInCollateralDecimals = (w.amount * (10 ** IERC20Metadata(w.collateral).decimals())) / 1e18;
		IERC20(w.collateral).safeTransfer(w.to, amountInCollateralDecimals);
	}

	function cancelWithdraw(uint256 id) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(id <= accountLayout.lastWithdrawId, "AccountFacet: Invalid Id");

		Withdraw storage w = accountLayout.withdrawals[id];
		require(w.status == WithdrawStatus.INITIATED, "AccountFacet: Invalid state");

		w.status = WithdrawStatus.CANCELED;
		accountLayout.balances[w.user][w.collateral].instantAdd(w.collateral, w.amount);
	}

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		for (uint256 i = 0; i < partyBs.length; i++) accountLayout.balances[partyA][collateral].sync(partyBs[i], block.timestamp);
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
}
