// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibAccessibility } from "../../libraries/LibAccessibility.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { BridgeFacetImpl } from "./BridgeFacetImpl.sol";
import { IBridgeEvents } from "./IBridgeEvents.sol";
import { IBridgeFacet } from "./IBridgeFacet.sol";

/**
 * @title BridgeFacet
 * @notice Manages bridge transactions through bridge operations
 * @dev Implements the IBridgeFacet interface with access control and pausability mechanisms
 */
contract BridgeFacet is Accessibility, Pausable, IBridgeFacet {
	/**
	 * @notice Transfers collateral to a designated bridge to skip deallocate cooldown
	 * @dev Generates a unique transaction ID for tracking the bridge transfer
	 * @param collateral The address of the collateral token to bridge
	 * @param amount The precise amount to be transferred, specified in collateral decimals
	 * @param bridgeAddress The address of the bridge contract
	 * @param receiver The address on the destination chain that will receive the collateral
	 */
	function transferToBridge(
		address collateral,
		uint256 amount,
		address bridgeAddress,
		address receiver
	) external whenNotBridgePaused notSuspended(msg.sender) {
		uint256 transactionId = BridgeFacetImpl.transferToBridge(collateral, amount, bridgeAddress, receiver);
		emit TransferToBridge(msg.sender, receiver, collateral, amount, bridgeAddress, transactionId);
	}

	/**
	 * @notice Processes and finalizes multiple received bridge transactions
	 * @dev Claims tokens that have been bridged to this bridge and updates internal accounting
	 * @param transactionIds An array of transaction IDs for which the received bridge values will be withdrawn
	 */
	function withdrawReceivedBridgeValues(uint256[] memory transactionIds) external whenNotBridgeWithdrawPaused notSuspended(msg.sender) {
		BridgeFacetImpl.withdrawReceivedBridgeValues(transactionIds);
		emit WithdrawReceivedBridgeValues(transactionIds);
	}

	/**
	 * @notice Temporarily halts a specific bridge transaction due to suspicious activity
	 * @dev Only accounts with SUSPENDER_ROLE can suspend transactions
	 * @param transactionId The transaction ID of the bridge transaction to be suspended
	 */
	function suspendBridgeTransaction(uint256 transactionId) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		BridgeFacetImpl.suspendBridgeTransaction(transactionId);
		emit SuspendBridgeTransaction(transactionId);
	}

	/**
	 * @notice Reactivates a previously suspended bridge transaction with a potentially adjusted amount
	 * @dev Only accounts with DISPUTE_ROLE can restore transactions, typically after investigation
	 * @param transactionId The transaction ID of the bridge transaction to be restored
	 * @param validAmount The verified amount to be processed, which may differ from the original amount
	 */
	function restoreBridgeTransaction(uint256 transactionId, uint256 validAmount) external onlyRole(LibAccessibility.DISPUTE_ROLE) {
		BridgeFacetImpl.restoreBridgeTransaction(transactionId, validAmount);
		emit RestoreBridgeTransaction(transactionId, validAmount);
	}
}
