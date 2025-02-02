// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IAccountFacet.sol";
import "./AccountFacetImpl.sol";
import "../../storages/AppStorage.sol";

contract AccountFacet is Accessibility, Pausable, IAccountFacet {
	/// @notice Allows either PartyA or PartyB to deposit collateral.
	/// @param amount The amount of collateral to be deposited, specified in collateral decimals.
	function deposit(address collateral, uint256 amount) external whenNotDepositingPaused notSuspended(msg.sender) {
		AccountFacetImpl.deposit(collateral, msg.sender, amount);
		emit Deposit(msg.sender, msg.sender, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/// @notice Allows either Party A or Party B to deposit collateral on behalf of another user.
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

	/// @notice Allows parties to initiate a withdraw with specified amount of collateral.
	/// @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals.
	/// @param to The address that the collateral transfers
	function initiateWithdraw(
		address collateral,
		uint256 amount,
		address to
	) external whenNotWithdrawingPaused notSuspended(msg.sender) notSuspended(to) {
		uint256 id = AccountFacetImpl.initiateWithdraw(collateral, amount, to);
		emit InitiateWithdraw(id, msg.sender, to, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/// @notice Allows parties to complete a withdraw.
	/// @param id The Id of withdraw object
	function completeWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		AccountFacetImpl.completeWithdraw(id);
		emit CompleteWithdraw(id);
	}

	/// @notice Allows parties to cancel a withdraw.
	/// @param id The Id of withdraw object
	function cancelWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[id];
		AccountFacetImpl.cancelWithdraw(id);
		emit CancelWithdraw(id, withdrawObject.user, AccountStorage.layout().balances[withdrawObject.user][withdrawObject.collateral].available);
	}

	/// @notice Syncs balances between specified PartyA and PartyBs
	/// @param partyA The PartyA address to sync balances for
	/// @param partyBs Array of PartyB addresses to sync balances with
	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external {
		AccountFacetImpl.syncBalances(collateral, partyA, partyBs);
		emit SyncBalances(collateral, partyA, partyBs);
	}

	/// @notice Allows partyAs to activate the instant action mode
	function activateInstantActionMode() external notPartyB {
		AccountFacetImpl.activateInstantActionMode();
		emit ActivateInstantActionMode(msg.sender, block.timestamp);
	}

	/// @notice Allows partyAs to propose to deactivate the instant action mode
	function proposeToDeactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.proposeToDeactivateInstantActionMode();
		emit ProposeToDeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/// @notice Allows PartyAs to deactivate the instant action mode after the proposal
	function deactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.deactivateInstantActionMode();
		emit DeactivateInstantActionMode(msg.sender, block.timestamp);
	}
}
