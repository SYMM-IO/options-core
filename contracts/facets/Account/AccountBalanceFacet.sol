// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "../../libraries/core/LibBucket.sol";
import { BucketRef } from "../../types/BucketTypes.sol";

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";

import { IAccountEvents } from "./IAccountEvents.sol";

/// @notice Bucket-aware balance operations using ordinary wallet authorization.
contract AccountBalanceFacet is Accessibility, Pausable, IAccountEvents, ReentrancyGuard {
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
	 * @notice Synchronizes balances between a PartyA and multiple PartyBs
	 * @dev Updates internal accounting to reflect the latest state across parties
	 * @param collateral The address of the collateral token to synchronize
	 * @param partyA The PartyA address whose balance will be synchronized
	 * @param partyBs Array of PartyB addresses with which to synchronize balances
	 */
	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external {
		LibBalanceOperations.syncBalances(collateral, partyA, partyBs);
	}

	function deposit(
		uint256 bucketId,
		address collateral,
		uint256 amount
	) external nonReentrant whenDepositingNotPaused whenPartyNotPaused(msg.sender) {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBalanceOperations.deposit(collateral, msg.sender, bucketId, amount);
		emit BucketDeposit(msg.sender, msg.sender, bucketId, collateral, amount);
	}
	function depositFor(
		uint256 bucketId,
		address collateral,
		address user,
		uint256 amount
	) external nonReentrant whenDepositingNotPaused whenNotSuspended(msg.sender) whenPartyNotPaused(msg.sender) whenPartyNotPaused(user) {
		LibBucket.requireNotSuspended(user, bucketId);
		LibBalanceOperations.deposit(collateral, user, bucketId, amount);
		emit BucketDeposit(msg.sender, user, bucketId, collateral, amount);
	}
	function internalTransfer(
		uint256 bucketId,
		address collateral,
		address user,
		uint256 userBucketId,
		uint256 amount
	) external whenInternalTransferNotPaused whenPartyNotPaused(msg.sender) whenPartyNotPaused(user) onlyNotPartyB(msg.sender) {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireNotSuspended(user, userBucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibBalanceOperations.internalTransfer(collateral, msg.sender, bucketId, user, userBucketId, amount);
		emit BucketInternalTransfer(msg.sender, bucketId, user, userBucketId, collateral, amount);
	}
	function syncBalances(address collateral, address owner, uint256 bucketId, BucketRef[] calldata counterparties) external {
		LibBalanceOperations.syncBalances(collateral, owner, bucketId, counterparties);
	}

	function virtualDepositFor(
		uint256 bucketId,
		address collateral,
		address user,
		uint256 amount
	) external whenDepositingNotPaused onlyRole(LibAccessibility.VIRTUAL_DEPOSITOR_ROLE) {
		LibBalanceOperations.virtualDepositFor(collateral, user, bucketId, amount);
		emit BucketDeposit(msg.sender, user, bucketId, collateral, amount);
		emit BucketVirtualDeposit(msg.sender, user, bucketId, collateral, amount);
	}
	function externalTransfer(
		uint256 bucketId,
		address collateral,
		address user,
		uint256 amount,
		address target
	) external nonReentrant whenNotExternalTransferPaused whenPartyNotPaused(msg.sender) {
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibBalanceOperations.externalTransfer(collateral, msg.sender, bucketId, user, amount, target);
		emit BucketExternalTransfer(msg.sender, bucketId, user, collateral, amount, target);
	}
}
