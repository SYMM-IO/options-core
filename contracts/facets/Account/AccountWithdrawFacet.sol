// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "../../libraries/core/LibBucket.sol";

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { AccountStorage, Withdraw } from "../../storages/AccountStorage.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";

import { IAccountEvents } from "./IAccountEvents.sol";

/// @notice Bucket-aware withdraw operations using ordinary wallet authorization.
contract AccountWithdrawFacet is Accessibility, Pausable, IAccountEvents, ReentrancyGuard {
	using LibParty for address;

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
			withdrawObject.user.balanceOf(withdrawObject.bucketId, withdrawObject.collateral).isolatedBalance
		);
	}
	function initiateWithdraw(
		uint256 bucketId,
		address collateral,
		uint256 amount,
		address to
	) external nonReentrant whenWithdrawingNotPaused whenNotSuspended(to) whenPartyNotPaused(msg.sender) {
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		uint256 id = LibBalanceOperations.initiateWithdraw(msg.sender, bucketId, collateral, amount, to, address(0), "");
		emit BucketWithdrawInitiated(id, msg.sender, bucketId, to, collateral, amount);
	}
	function initiateExpressWithdraw(
		uint256 bucketId,
		address collateral,
		uint256 amount,
		address to,
		address provider,
		bytes memory userData
	) external nonReentrant whenWithdrawingNotPaused whenNotExpressWithdrawPaused whenNotSuspended(to) whenPartyNotPaused(msg.sender) {
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		uint256 id = LibBalanceOperations.initiateWithdraw(msg.sender, bucketId, collateral, amount, to, provider, userData);
		emit BucketWithdrawInitiated(id, msg.sender, bucketId, to, collateral, amount);
		emit BucketExpressWithdrawInitiated(id, msg.sender, bucketId, provider, userData);
	}
}
