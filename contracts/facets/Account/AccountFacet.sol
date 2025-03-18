// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/LibAccessibility.sol";
import { AccountStorage, Withdraw } from "../../storages/AccountStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { AccountFacetImpl } from "./AccountFacetImpl.sol";
import { IAccountEvents } from "./IAccountEvents.sol";
import { IAccountFacet } from "./IAccountFacet.sol";

contract AccountFacet is Accessibility, Pausable, IAccountFacet {
	/// @notice Allows either PartyA or PartyB to deposit collateral.
	/// @param collateral The address of the collateral token to deposit.
	/// @param amount The amount of collateral to be deposited, specified in collateral decimals.
	function deposit(address collateral, uint256 amount) external whenNotDepositingPaused notSuspended(msg.sender) {
		AccountFacetImpl.deposit(collateral, msg.sender, amount);
		emit Deposit(msg.sender, msg.sender, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/// @notice Transfers the sender's deposited balance to the user allocated balance.
	/// @param collateral The address of the collateral token to internal transfer.
	/// @param user The address of the recipient user.
	/// @param amount The amount to transfer.
	function internalTransfer(
		address collateral,
		address user,
		uint256 amount
	) external whenNotInternalTransferPaused notSuspended(msg.sender) notSuspended(user) {
		AccountFacetImpl.internalTransfer(collateral, user, amount);
		emit InternalTransfer(msg.sender, user, AccountStorage.layout().balances[collateral][user].available, collateral, amount);
	}

	/// @notice Allows specific roles to deposit collateral on behalf of another user out of this contract.
	/// @param collateral The address of the collateral token.
	/// @param user The recipient address for the deposit.
	/// @param amount The amount of collateral to be deposited, specified in collateral decimals.
	function securedDepositFor(
		address collateral,
		address user,
		uint256 amount
	) external whenNotDepositingPaused onlyRole(LibAccessibility.SECURED_DEPOSITOR_ROLE) {
		AccountFacetImpl.securedDepositFor(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, AccountStorage.layout().balances[user][collateral].available);
	}

	/// @notice Allows either PartyA or PartyB to deposit collateral on behalf of another user.
	/// @param collateral The address of the collateral token.
	/// @param user The recipient address for the deposit.
	/// @param amount The amount of collateral to be deposited, specified in collateral decimals.
	function depositFor(
		address collateral,
		address user,
		uint256 amount
	) external whenNotDepositingPaused notSuspended(msg.sender) notSuspended(user) {
		AccountFacetImpl.deposit(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, AccountStorage.layout().balances[user][collateral].available);
	}

	/// @notice Allows parties to initiate a withdrawal of collateral.
	/// @param collateral The address of the collateral token to withdraw.
	/// @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals.
	/// @param to The address that will receive the collateral.
	function initiateWithdraw(
		address collateral,
		uint256 amount,
		address to
	) external whenNotWithdrawingPaused notSuspended(msg.sender) notSuspended(to) {
		uint256 id = AccountFacetImpl.initiateWithdraw(collateral, amount, to);
		emit InitiateWithdraw(id, msg.sender, to, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/// @notice Allows parties to complete a withdrawal.
	/// @param id The identifier of the withdrawal request.
	function completeWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		AccountFacetImpl.completeWithdraw(id);
		emit CompleteWithdraw(id);
	}

	/// @notice Allows parties to cancel a withdrawal.
	/// @param id The identifier of the withdrawal request.
	function cancelWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[id];
		AccountFacetImpl.cancelWithdraw(id);
		emit CancelWithdraw(id, withdrawObject.user, AccountStorage.layout().balances[withdrawObject.user][withdrawObject.collateral].available);
	}

	/// @notice Synchronizes balances between the specified PartyA and PartyB addresses.
	/// @param collateral The address of the collateral token.
	/// @param partyA The PartyA address whose balance will be synchronized.
	/// @param partyBs Array of PartyB addresses with which to synchronize balances.
	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external {
		AccountFacetImpl.syncBalances(collateral, partyA, partyBs);
		emit SyncBalances(collateral, partyA, partyBs);
	}

	/// @notice Allows PartyAs to activate the instant action mode.
	function activateInstantActionMode() external notPartyB {
		AccountFacetImpl.activateInstantActionMode();
		emit ActivateInstantActionMode(msg.sender, block.timestamp);
	}

	/// @notice Allows PartyAs to propose deactivation of the instant action mode.
	function proposeToDeactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.proposeToDeactivateInstantActionMode();
		emit ProposeToDeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/// @notice Allows PartyAs to deactivate the instant action mode after a proposal.
	function deactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.deactivateInstantActionMode();
		emit DeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/// @notice Allows PartyA to bind to a PartyB.
	/// @param partyB The address of the PartyB to bind to.
	function bindToPartyB(address partyB) external notPartyB whenNotPartyAActionsPaused {
		AccountFacetImpl.bindToPartyB(partyB);
		emit BindToPartyB(msg.sender, partyB);
	}

	/// @notice Initiates the process of unbinding from PartyB.
	/// Must wait for a cooldown period before finalizing.
	function initiateUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AccountFacetImpl.initiateUnbindingFromPartyB();
		emit InitiateUnbindingFromPartyB(msg.sender, accountLayout.boundPartyB[msg.sender], block.timestamp);
	}

	/// @notice Completes the unbinding from PartyB after the cooldown period.
	function completeUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address previousPartyB = accountLayout.boundPartyB[msg.sender];
		AccountFacetImpl.completeUnbindingFromPartyB();
		emit CompleteUnbindingFromPartyB(msg.sender, previousPartyB);
	}

	/// @notice Cancels a pending unbinding request from PartyB.
	function cancelUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AccountFacetImpl.cancelUnbindingFromPartyB();
		emit CancelUnbindingFromPartyB(msg.sender, accountLayout.boundPartyB[msg.sender]);
	}
}
