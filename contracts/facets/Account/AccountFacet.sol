// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";
import { LibAllocationOperations } from "../../libraries/core/LibAllocationOperations.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { AccountStorage, Withdraw } from "../../storages/AccountStorage.sol";

import { UpnlSig } from "../../types/WithdrawTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";

import { IAccountFacet } from "./IAccountFacet.sol";

/**
 * @title AccountFacet
 * @notice Manages account operations including deposits, withdrawals
 * @dev Implements the IAccountFacet interface with access control and pausability
 */
contract AccountFacet is Accessibility, Pausable, IAccountFacet, ReentrancyGuard {
	using LibParty for address;

	/**
	 * @notice Allows a user to deposit collateral into their own account
	 * @dev Increases the sender's available balance for the specified collateral
	 * @param collateral The address of the collateral token to deposit
	 * @param amount The amount of collateral to be deposited, specified in collateral decimals
	 */
	function deposit(
		address collateral,
		uint256 amount
	) external nonReentrant whenDepositingNotPaused whenNotSuspended(msg.sender) whenPartyNotPaused(msg.sender) {
		LibBalanceOperations.deposit(collateral, msg.sender, amount);
		emit Deposit(msg.sender, msg.sender, collateral, amount, msg.sender.balanceOf(collateral).isolatedBalance);
	}

	/**
	 * @notice Allows privileged roles to deposit collateral on behalf of another user
	 * @dev Restricted to accounts with VIRTUAL_DEPOSITOR_ROLE
	 * @param collateral The address of the collateral token to deposit
	 * @param user The recipient address who will receive the deposited collateral
	 * @param amount The amount of collateral to be deposited, specified in collateral decimals
	 */
	function virtualDepositFor(
		address collateral,
		address user,
		uint256 amount
	) external whenDepositingNotPaused whenNotSuspended(user) onlyRole(LibAccessibility.VIRTUAL_DEPOSITOR_ROLE) {
		LibBalanceOperations.virtualDepositFor(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, user.balanceOf(collateral).isolatedBalance);
		emit VirtualDeposit(msg.sender, user, collateral, amount, user.balanceOf(collateral).isolatedBalance);
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
	)
		external
		nonReentrant
		whenDepositingNotPaused
		whenNotSuspended(msg.sender)
		whenNotSuspended(user)
		whenPartyNotPaused(msg.sender)
		whenPartyNotPaused(user)
	{
		LibBalanceOperations.deposit(collateral, user, amount);
		emit Deposit(msg.sender, user, collateral, amount, user.balanceOf(collateral).isolatedBalance);
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
	)
		external
		whenInternalTransferNotPaused
		whenNotSuspended(msg.sender)
		whenNotSuspended(user)
		whenInstantModeIsNotActive(msg.sender)
		whenPartyNotPaused(msg.sender)
		whenPartyNotPaused(user)
		onlyNotPartyB(msg.sender)
	{
		LibBalanceOperations.internalTransfer(collateral, msg.sender, user, amount);
		emit InternalTransfer(
			msg.sender,
			user,
			collateral,
			amount,
			user.balanceOf(collateral).isolatedBalance,
			msg.sender.balanceOf(collateral).isolatedBalance
		);
	}

	/**
	 * @notice Transfers collateral from sender's available balance to whitelisted target without any cooldown
	 * @dev sender must not be suspended for the operation to succeed
	 * @param collateral The address of the collateral token to transfer
	 * @param user The address of the recipient user in the target contract
	 * @param amount The amount to transfer, specified in collateral decimals
	 * @param target The address of the target contract that will receive the collateral
	 */
	function externalTransfer(
		address collateral,
		address user,
		uint256 amount,
		address target
	)
		external
		nonReentrant
		whenNotExternalTransferPaused
		whenNotSuspended(msg.sender)
		whenInstantModeIsNotActive(msg.sender)
		whenPartyNotPaused(msg.sender)
	{
		LibBalanceOperations.externalTransfer(collateral, msg.sender, user, amount, target);
		emit ExternalTransfer(msg.sender, user, collateral, amount, target);
	}

	/**
	 * @notice Initiates a withdrawal request for collateral
	 * @dev Starts the withdrawal process, moving funds to a pending state
	 * @param collateral The address of the collateral token to withdraw
	 * @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals
	 * @param to The address that will receive the collateral upon completion
	 */
	function initiateWithdraw(
		address collateral,
		uint256 amount,
		address to
	)
		external
		whenWithdrawingNotPaused
		whenNotSuspended(msg.sender)
		whenInstantModeIsNotActive(msg.sender)
		whenNotSuspended(to)
		whenPartyNotPaused(msg.sender)
	{
		uint256 id = LibBalanceOperations.initiateWithdraw(msg.sender, collateral, amount, to, address(0), "");
		emit InitiateWithdraw(id, msg.sender, to, collateral, amount, msg.sender.balanceOf(collateral).isolatedBalance);
	}

	/**
	 * @notice Initiates a withdrawal request for collateral
	 * @dev Starts the withdrawal process, moving funds to a pending state
	 * @param collateral The address of the collateral token to withdraw
	 * @param amount The precise amount of collateral to be withdrawn, specified in 18 decimals
	 * @param to The address that will receive the collateral upon completion
	 * @param provider The address of the express withdraw provider
	 * @param userData The user data
	 */
	function initiateExpressWithdraw(
		address collateral,
		uint256 amount,
		address to,
		address provider,
		bytes memory userData
	)
		external
		nonReentrant
		whenWithdrawingNotPaused
		whenNotExpressWithdrawPaused
		whenNotSuspended(msg.sender)
		whenInstantModeIsNotActive(msg.sender)
		whenNotSuspended(to)
		whenPartyNotPaused(msg.sender)
	{
		uint256 id = LibBalanceOperations.initiateWithdraw(msg.sender, collateral, amount, to, provider, userData);
		emit InitiateWithdraw(id, msg.sender, to, collateral, amount, msg.sender.balanceOf(collateral).isolatedBalance);
		emit InitiateExpressWithdraw(id, msg.sender, to, collateral, provider, userData, amount, msg.sender.balanceOf(collateral).isolatedBalance);
	}

	/**
	 * @notice Suspends a withdrawal request
	 * @dev Suspends the withdrawal request, preventing it from being completed
	 * @param id The unique identifier of the withdrawal request to suspend
	 */
	function suspendWithdraw(uint256 id) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		LibBalanceOperations.suspendWithdraw(id);
		emit SuspendWithdraw(id, msg.sender);
	}

	/**
	 * @notice Restores a suspended withdrawal request
	 * @dev Restores the withdrawal request, allowing it to be completed
	 * @param id The unique identifier of the withdrawal request to restore
	 * @param validAmount The verified amount to be processed, which may differ from the original amount
	 */
	function restoreWithdraw(uint256 id, uint256 validAmount) external onlyRole(LibAccessibility.DISPUTER_ROLE) {
		LibBalanceOperations.restoreWithdraw(id, validAmount);
		emit RestoreWithdraw(id, validAmount);
	}

	/**
	 * @notice Completes a previously initiated withdrawal request
	 * @dev Transfers the collateral to the destination address specified in the withdrawal request
	 * @param id The unique identifier of the withdrawal request to complete
	 */
	function completeWithdraw(
		uint256 id
	) external nonReentrant whenWithdrawingNotPaused whenWithdrawalNotSuspended(id) whenPartyNotPaused(msg.sender) {
		LibBalanceOperations.completeWithdraw(id);
		emit CompleteWithdraw(id);
	}

	/**
	 * @notice Cancels a pending withdrawal request
	 * @dev Returns the funds back to the user's available balance
	 * @param id The unique identifier of the withdrawal request to cancel
	 */
	function cancelWithdraw(uint256 id) external whenWithdrawingNotPaused whenWithdrawalNotSuspended(id) whenPartyNotPaused(msg.sender) {
		Withdraw storage withdrawObject = AccountStorage.layout().withdrawals[id];
		LibBalanceOperations.cancelWithdraw(id);
		emit CancelWithdraw(
			id,
			withdrawObject.user,
			withdrawObject.collateral,
			withdrawObject.amount,
			withdrawObject.user.balanceOf(withdrawObject.collateral).isolatedBalance
		);
	}

	/**
	 * @notice Synchronizes balances between a PartyA and multiple PartyBs
	 * @dev Updates internal accounting to reflect the latest state across parties
	 * @param collateral The address of the collateral token to synchronize
	 * @param partyA The PartyA address whose balance will be synchronized
	 * @param partyBs Array of PartyB addresses with which to synchronize balances
	 */
	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external {
		LibBalanceOperations.syncBalances(collateral, partyA, partyBs);
	}

	/**
	 * @notice Allocates tokens from a user's isolated balance to their cross balance with a counterparty
	 * @param collateral The address of the collateral token to allocate
	 * @param counterParty The address of the counterparty
	 * @param amount The amount of collateral to be allocated
	 */
	function allocate(
		address collateral,
		address counterParty,
		uint256 amount
	) external whenNotSuspended(msg.sender) whenInstantModeIsNotActive(msg.sender) whenPartyNotPaused(msg.sender) {
		LibAllocationOperations.allocate(msg.sender, collateral, counterParty, amount);
		emit Allocate(
			msg.sender,
			collateral,
			counterParty,
			amount,
			msg.sender.balanceOf(collateral).isolatedBalance,
			msg.sender.balanceOf(collateral).crossBalance[counterParty].balance
		);
	}

	/**
	 * @notice Deallocates tokens, returning them to a user's isolated balance
	 * @param collateral The address of the collateral token to deallocate
	 * @param counterParty The address of the counterparty
	 * @param amount The amount of collateral to be deallocated
	 * @param isPartyB The bool that shows if the sender is partyB
	 * @param upnlSig The Muon signature that represents the upnl of parties
	 */
	function deallocate(
		address collateral,
		address counterParty,
		uint256 amount,
		bool isPartyB,
		UpnlSig memory upnlSig
	) external whenNotSuspended(msg.sender) whenInstantModeIsNotActive(msg.sender) whenPartyNotPaused(msg.sender) {
		LibAllocationOperations.deallocate(collateral, counterParty, amount, isPartyB, upnlSig);
		emit Deallocate(
			msg.sender,
			collateral,
			counterParty,
			amount,
			msg.sender.balanceOf(collateral).isolatedBalance,
			msg.sender.balanceOf(collateral).crossBalance[counterParty].balance
		);
	}

	/**
	 * @notice Allocates tokens to a user's reserve balance
	 * @param collateral The address of the collateral token to deallocate
	 * @param amount The amount of collateral to be allocated
	 */
	function allocateToReserveBalance(
		address collateral,
		uint256 amount
	) external whenInstantModeIsNotActive(msg.sender) whenPartyNotPaused(msg.sender) {
		LibAllocationOperations.allocateToReserveBalance(collateral, amount);
		emit AllocateToReserveBalance(msg.sender, collateral, amount, msg.sender.balanceOf(collateral).isolatedBalance);
	}

	/**
	 * @notice Deallocates tokens from a user's reserve balance
	 * @param collateral The address of the collateral token to deallocate
	 * @param amount The amount of collateral to be deallocated
	 */
	function deallocateFromReserveBalance(
		address collateral,
		uint256 amount
	) external whenInstantModeIsNotActive(msg.sender) whenPartyNotPaused(msg.sender) {
		LibAllocationOperations.deallocateFromReserveBalance(collateral, amount);
		emit DeallocateFromReserveBalance(msg.sender, collateral, amount, msg.sender.balanceOf(collateral).isolatedBalance);
	}
}
