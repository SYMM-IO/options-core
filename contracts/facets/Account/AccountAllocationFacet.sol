// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "../../libraries/core/LibBucket.sol";

import { LibAllocationOperations } from "../../libraries/core/LibAllocationOperations.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { UpnlSig } from "../../types/WithdrawTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { ReentrancyGuard } from "../../utils/ReentrancyGuard.sol";

import { IAccountEvents } from "./IAccountEvents.sol";

/// @notice Bucket-aware allocation operations using ordinary wallet authorization.
contract AccountAllocationFacet is Accessibility, Pausable, IAccountEvents, ReentrancyGuard {
	using LibParty for address;

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
	function allocate(uint256 bucketId, address collateral, address cp, uint256 cpBucketId, uint256 amount) external whenPartyNotPaused(msg.sender) {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibAllocationOperations.allocate(msg.sender, bucketId, collateral, cp, cpBucketId, amount);
		emit BucketAllocation(msg.sender, bucketId, cp, cpBucketId, collateral, amount, true);
	}
	function deallocate(
		uint256 bucketId,
		address collateral,
		address cp,
		uint256 cpBucketId,
		uint256 amount,
		bool isPartyB,
		UpnlSig memory sig
	) external whenPartyNotPaused(msg.sender) {
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibAllocationOperations.deallocate(bucketId, collateral, cp, cpBucketId, amount, isPartyB, sig);
		emit BucketAllocation(msg.sender, bucketId, cp, cpBucketId, collateral, amount, false);
	}
	function allocateToReserveBalance(uint256 bucketId, address collateral, uint256 amount) external whenPartyNotPaused(msg.sender) {
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibAllocationOperations.allocateToReserveBalance(bucketId, collateral, amount);
		emit BucketReserveChanged(msg.sender, bucketId, collateral, amount, true);
	}
	function deallocateFromReserveBalance(uint256 bucketId, address collateral, uint256 amount) external whenPartyNotPaused(msg.sender) {
		LibBucket.requireRegistered(msg.sender, bucketId);
		LibBucket.requireNotSuspended(msg.sender, bucketId);
		LibBucket.requireInstantModeInactive(msg.sender, bucketId);
		LibAllocationOperations.deallocateFromReserveBalance(bucketId, collateral, amount);
		emit BucketReserveChanged(msg.sender, bucketId, collateral, amount, false);
	}
}
