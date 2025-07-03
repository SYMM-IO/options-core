// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/core/LibAccessibility.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IExpressWithdrawFacet } from "./IExpressWithdrawFacet.sol";
import { LibExpressWithdraw } from "../../libraries/core/LibExpressWithdraw.sol";

/**
 * @title ExpressWithdrawFacet
 * @notice Manages express withdraw transactions through express withdraw operations
 * @dev Implements the IExpressWithdrawFacet interface with access control and pausability mechanisms
 */
contract ExpressWithdrawFacet is Accessibility, Pausable, IExpressWithdrawFacet {
	using LibParty for address;
	/**
	 * @notice Transfers collateral to a designated express withdraw provider to skip deallocate cooldown
	 * @dev Generates a unique express withdraw ID for tracking the express withdraw transfer
	 * @param collateral The address of the collateral token to express withdraw
	 * @param amount The precise amount to be transferred, specified in collateral decimals
	 * @param provider The address of the provider contract
	 * @param receiver The address on the destination chain that will receive the collateral
	 */
	function expressWithdraw(
		address collateral,
		uint256 amount,
		address provider,
		address receiver
	) external whenNotExpressWithdrawPaused whenNotSuspended(msg.sender) whenInstantModeIsNotActive(msg.sender) onlyNotPartyB(msg.sender) {
		uint256 expressWithdrawId = LibExpressWithdraw.expressWithdraw(msg.sender, collateral, amount, provider, receiver);
		emit ExpressWithdraw(msg.sender, receiver, collateral, amount, provider, expressWithdrawId, msg.sender.balanceOf(collateral).isolatedBalance);
	}

	/**
	 * @notice Processes and finalizes multiple received express withdraws
	 * @dev Claims tokens that have been express withdrawn to this express withdraw provider and updates internal accounting
	 * @param expressWithdrawIds An array of express withdraw IDs for which the received express withdraw values will be withdrawn
	 */
	function collectReceivedExpressWithdraws(
		uint256[] memory expressWithdrawIds
	) external whenNotExpressWithdrawCollectionPaused whenNotSuspended(msg.sender) {
		LibExpressWithdraw.collectReceivedExpressWithdraws(expressWithdrawIds);
		emit CollectReceivedExpressWithdraws(expressWithdrawIds);
	}

	/**
	 * @notice Temporarily halts a specific express withdraw due to suspicious activity
	 * @dev Only accounts with SUSPENDER_ROLE can suspend transactions
	 * @param expressWithdrawId The express withdraw ID of the express withdraw to be suspended
	 */
	function suspendExpressWithdraw(uint256 expressWithdrawId) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		LibExpressWithdraw.suspendExpressWithdraw(expressWithdrawId);
		emit SuspendExpressWithdraw(expressWithdrawId);
	}

	/**
	 * @notice Reactivates a previously suspended express withdraw with a potentially adjusted amount
	 * @dev Only accounts with DISPUTE_ROLE can restore transactions, typically after investigation
	 * @param expressWithdrawId The express withdraw ID of the express withdraw to be restored
	 * @param validAmount The verified amount to be processed, which may differ from the original amount
	 */
	function restoreExpressWithdraw(uint256 expressWithdrawId, uint256 validAmount) external onlyRole(LibAccessibility.DISPUTE_ROLE) {
		LibExpressWithdraw.restoreExpressWithdraw(expressWithdrawId, validAmount);
		emit RestoreExpressWithdraw(expressWithdrawId, validAmount);
	}
}
