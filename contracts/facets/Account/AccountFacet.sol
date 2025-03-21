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

/**
 * @title AccountFacet
 * @notice Manages account operations including deposits, withdrawals, and PartyA/PartyB relationships
 * @dev Implements the IAccountFacet interface with access control and pausability
 */
contract AccountFacet is Accessibility, Pausable, IAccountFacet {
	/**
	 * @notice Allows a user to deposit collateral into their own account
	 * @dev Increases the sender's available balance for the specified collateral
	 * @param collateral The address of the collateral token to deposit
	 * @param amount The amount of collateral to be deposited, specified in collateral decimals
	 */
	function deposit(address collateral, uint256 amount) external whenNotDepositingPaused notSuspended(msg.sender) {
		AccountFacetImpl.deposit(collateral, msg.sender, amount);
		emit Deposit(msg.sender, msg.sender, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/**
	 * @notice Transfers collateral from sender's available balance to another user's available balance
	 * @dev Both sender and recipient must not be suspended for the operation to succeed
	 * @param collateral The address of the collateral token to transfer
	 * @param user The address of the recipient user
	 * @param amount The amount to transfer, specified in collateral decimals
	 */
	function internalTransfer(
		address collateral,
		address user,
		uint256 amount
	) external whenNotInternalTransferPaused notSuspended(msg.sender) notSuspended(user) {
		AccountFacetImpl.internalTransfer(collateral, user, amount);
		emit InternalTransfer(msg.sender, user, collateral, amount, AccountStorage.layout().balances[collateral][user].available);
	}

	/**
	 * @notice Allows privileged roles to deposit collateral on behalf of another user
	 * @dev Restricted to accounts with SECURED_DEPOSITOR_ROLE
	 * @param collateral The address of the collateral token to deposit
	 * @param user The recipient address who will receive the deposited collateral
	 * @param amount The amount of collateral to be deposited, specified in collateral decimals
	 */
	function securedDepositFor(
		address collateral,
		address user,
		uint256 amount
	) external whenNotDepositingPaused onlyRole(LibAccessibility.SECURED_DEPOSITOR_ROLE) {
		AccountFacetImpl.securedDepositFor(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, AccountStorage.layout().balances[user][collateral].available);
	}

	/**
	 * @notice Allows a user to deposit collateral on behalf of another user
	 * @dev Both sender and recipient must not be suspended for the operation to succeed
	 * @param collateral The address of the collateral token to deposit
	 * @param user The recipient address who will receive the deposited collateral
	 * @param amount The amount of collateral to be deposited, specified in collateral decimals
	 */
	function depositFor(
		address collateral,
		address user,
		uint256 amount
	) external whenNotDepositingPaused notSuspended(msg.sender) notSuspended(user) {
		AccountFacetImpl.deposit(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, AccountStorage.layout().balances[user][collateral].available);
	}

	/**
	 * @notice Initiates a withdrawal request for collateral
	 * @dev Starts the withdrawal process, moving funds to a pending state
	 * @param collateral The address of the collateral token to withdraw
	 * @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals
	 * @param to The address that will receive the collateral upon completion
	 * @return id The unique identifier for the withdrawal request
	 */
	function initiateWithdraw(
		address collateral,
		uint256 amount,
		address to
	) external whenNotWithdrawingPaused notSuspended(msg.sender) notSuspended(to) {
		uint256 id = AccountFacetImpl.initiateWithdraw(collateral, amount, to);
		emit InitiateWithdraw(id, msg.sender, to, collateral, amount, AccountStorage.layout().balances[msg.sender][collateral].available);
	}

	/**
	 * @notice Completes a previously initiated withdrawal request
	 * @dev Transfers the collateral to the destination address specified in the withdrawal request
	 * @param id The unique identifier of the withdrawal request to complete
	 */
	function completeWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		AccountFacetImpl.completeWithdraw(id);
		emit CompleteWithdraw(id);
	}

	/**
	 * @notice Cancels a pending withdrawal request
	 * @dev Returns the funds back to the user's available balance
	 * @param id The unique identifier of the withdrawal request to cancel
	 */
	function cancelWithdraw(uint256 id) external whenNotWithdrawingPaused notSuspendedWithdrawal(id) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[id];
		AccountFacetImpl.cancelWithdraw(id);
		emit CancelWithdraw(id, withdrawObject.user, AccountStorage.layout().balances[withdrawObject.user][withdrawObject.collateral].available);
	}

	/**
	 * @notice Synchronizes balances between a PartyA and multiple PartyBs
	 * @dev Updates internal accounting to reflect the latest state across parties
	 * @param collateral The address of the collateral token to synchronize
	 * @param partyA The PartyA address whose balance will be synchronized
	 * @param partyBs Array of PartyB addresses with which to synchronize balances
	 */
	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external {
		AccountFacetImpl.syncBalances(collateral, partyA, partyBs);
		emit SyncBalances(collateral, partyA, partyBs);
	}

	/**
	 * @notice Enables the instant action mode for a PartyA
	 * @dev Only callable by PartyA accounts, not PartyB
	 */
	function activateInstantActionMode() external notPartyB {
		AccountFacetImpl.activateInstantActionMode();
		emit ActivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Initiates the process to deactivate instant action mode
	 * @dev Only callable by PartyA accounts, starts a time-delayed process
	 */
	function proposeToDeactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.proposeToDeactivateInstantActionMode();
		emit ProposeToDeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Completes the deactivation of instant action mode after proposal
	 * @dev Only callable by PartyA accounts after the waiting period has passed
	 */
	function deactivateInstantActionMode() external notPartyB {
		AccountFacetImpl.deactivateInstantActionMode();
		emit DeactivateInstantActionMode(msg.sender, block.timestamp);
	}

	/**
	 * @notice Creates a binding relationship between a PartyA and a PartyB
	 * @dev Only callable by PartyA accounts when PartyA actions are not paused
	 * @param partyB The address of the PartyB to establish a relationship with
	 */
	function bindToPartyB(address partyB) external notPartyB whenNotPartyAActionsPaused {
		AccountFacetImpl.bindToPartyB(partyB);
		emit BindToPartyB(msg.sender, partyB);
	}

	/**
	 * @notice Begins the process of terminating a relationship with a PartyB
	 * @dev Starts a cooldown period before the unbinding can be completed
	 */
	function initiateUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AccountFacetImpl.initiateUnbindingFromPartyB();
		emit InitiateUnbindingFromPartyB(msg.sender, accountLayout.boundPartyB[msg.sender], block.timestamp);
	}

	/**
	 * @notice Finalizes the unbinding process from a PartyB after the cooldown period
	 * @dev Only callable after the required waiting period from initiation has passed
	 */
	function completeUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		address previousPartyB = accountLayout.boundPartyB[msg.sender];
		AccountFacetImpl.completeUnbindingFromPartyB();
		emit CompleteUnbindingFromPartyB(msg.sender, previousPartyB);
	}

	/**
	 * @notice Revokes a pending request to unbind from a PartyB
	 * @dev Can only be called during the cooldown period after initiation
	 */
	function cancelUnbindingFromPartyB() external notPartyB whenNotPartyAActionsPaused {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AccountFacetImpl.cancelUnbindingFromPartyB();
		emit CancelUnbindingFromPartyB(msg.sender, accountLayout.boundPartyB[msg.sender]);
	}
}
