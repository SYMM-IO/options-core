// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AccountStorage } from "../../storages/AccountStorage.sol";

import { SignedInternalTransfer, SignedWithdraw } from "../../types/SignedAccountTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IInstantActionsAccountFacet } from "./IInstantActionsAccountFacet.sol";
import { InstantActionsAccountFacetImpl } from "./InstantActionsAccountFacetImpl.sol";

/**
 * @title InstantActionsAccountFacet
 * @notice Enables meta-transaction functionality for Account intent operations
 * @dev Allows third parties to execute actions on behalf of PartyA and PartyB using cryptographic signatures
 * This facilitates gas-efficient operations and improves UX by allowing actions to be performed
 * without requiring direct blockchain interaction from either party
 */
contract InstantActionsAccountFacet is Accessibility, Pausable, IInstantActionsAccountFacet {
	/**
	 * @notice Executes an internal transfer between accounts using signatures from both PartyA and PartyB
	 * @dev Requires signatures from both parties to execute the internal transfer in a single transaction
	 * This atomic operation allows funds to be transferred between accounts without requiring
	 * direct interaction from either party, enabling third-party execution
	 * @param signedInternalTransferRequest The transfer request data from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing the transfer
	 * @param signedInternalTransferAcceptance The transfer acceptance data from PartyB
	 * @param partyBSignature Cryptographic signature from PartyB authorizing acceptance of the transfer
	 */
	function instantInternalTransfer(
		SignedInternalTransfer calldata signedInternalTransferRequest,
		bytes calldata partyASignature,
		SignedInternalTransfer calldata signedInternalTransferAcceptance,
		bytes calldata partyBSignature
	) external whenNotThirdPartyActionsPaused {
		InstantActionsAccountFacetImpl.instantInternalTransfer(
			signedInternalTransferRequest,
			partyASignature,
			signedInternalTransferAcceptance,
			partyBSignature
		);
		emit InternalTransfer(
			signedInternalTransferRequest.sender,
			signedInternalTransferRequest.receiver,
			signedInternalTransferRequest.collateral,
			signedInternalTransferRequest.amount,
			AccountStorage.layout().balances[signedInternalTransferRequest.sender][signedInternalTransferRequest.collateral].isolatedBalance,
			AccountStorage.layout().balances[signedInternalTransferRequest.receiver][signedInternalTransferRequest.collateral].isolatedBalance
		);
	}

	/**
	 * @notice Initiates a withdrawal operation using signatures from both PartyA and PartyB
	 * @dev Combines the withdrawal request from PartyA and acceptance from PartyB in a single transaction
	 * All actions are authorized through signatures, allowing execution by any third party
	 * @param signedWithdrawRequest The withdrawal request data from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing the withdrawal request
	 * @param signedWithdrawAcceptance The withdrawal acceptance data from PartyB
	 * @param partyBSignature Cryptographic signature from PartyB authorizing acceptance of the withdrawal
	 */
	function instantInitiateWithdraw(
		SignedWithdraw calldata signedWithdrawRequest,
		bytes calldata partyASignature,
		SignedWithdraw calldata signedWithdrawAcceptance,
		bytes calldata partyBSignature
	) external whenNotThirdPartyActionsPaused returns (uint256 withdrawId) {
		withdrawId = InstantActionsAccountFacetImpl.instantInitiateWithdraw(
			signedWithdrawRequest,
			partyASignature,
			signedWithdrawAcceptance,
			partyBSignature
		);
		emit InitiateWithdraw(
			withdrawId,
			signedWithdrawRequest.sender,
			signedWithdrawRequest.receiver,
			signedWithdrawRequest.collateral,
			signedWithdrawRequest.amount,
			AccountStorage.layout().balances[signedWithdrawRequest.sender][signedWithdrawRequest.collateral].isolatedBalance
		);
	}
}
