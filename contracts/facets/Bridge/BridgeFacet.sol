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

contract BridgeFacet is Accessibility, Pausable, IBridgeFacet {
	/// @notice Transfers a specified amount to the designated bridge address.
	/// @param collateral The address of the collateral token to bridge.
	/// @param amount The precise amount to be transferred, specified in decimal units.
	/// @param bridgeAddress The address of the bridge to which the collateral will be transferred.
	/// @param receiver The address of the receiver to which bridge will send the collateral.
	function transferToBridge(
		address collateral,
		uint256 amount,
		address bridgeAddress,
		address receiver
	) external whenNotBridgePaused notSuspended(msg.sender) {
		uint256 transactionId = BridgeFacetImpl.transferToBridge(collateral, amount, bridgeAddress, receiver);
		emit TransferToBridge(msg.sender, receiver, collateral, amount, bridgeAddress, transactionId);
	}

	/// @notice Withdraws the received bridge values associated with multiple transaction IDs.
	/// @param transactionIds An array of transaction IDs for which the received bridge values will be withdrawn.
	function withdrawReceivedBridgeValues(uint256[] memory transactionIds) external whenNotBridgeWithdrawPaused notSuspended(msg.sender) {
		BridgeFacetImpl.withdrawReceivedBridgeValues(transactionIds);
		emit WithdrawReceivedBridgeValues(transactionIds);
	}

	/// @notice Suspends a specific bridge transaction.
	/// @param transactionId The transaction ID of the bridge transaction to be suspended.
	function suspendBridgeTransaction(uint256 transactionId) external onlyRole(LibAccessibility.SUSPENDER_ROLE) {
		BridgeFacetImpl.suspendBridgeTransaction(transactionId);
		emit SuspendBridgeTransaction(transactionId);
	}

	/// @notice Restores a previously suspended bridge transaction and updates the valid transaction amount.
	/// @param transactionId The transaction ID of the bridge transaction to be restored.
	/// @param validAmount The validated amount to be associated with the restored transaction.
	function restoreBridgeTransaction(uint256 transactionId, uint256 validAmount) external onlyRole(LibAccessibility.DISPUTE_ROLE) {
		BridgeFacetImpl.restoreBridgeTransaction(transactionId, validAmount);
		emit RestoreBridgeTransaction(transactionId, validAmount);
	}
}
