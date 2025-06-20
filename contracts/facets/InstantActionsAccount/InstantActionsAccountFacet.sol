// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibInstantActionsAccount } from "../../libraries/core/LibInstantActionsAccount.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";

import { SignedInternalTransfer, SignedWithdraw, SignedBridgeTransfer, SignedAllocate } from "../../types/SignedAccountTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IInstantActionsAccountFacet } from "./IInstantActionsAccountFacet.sol";

/**
 * @title InstantActionsAccountFacet
 * @notice Enables meta-transaction functionality for Account intent operations
 * @dev Allows third parties to execute actions on behalf of PartyA and PartyB using cryptographic signatures
 * This facilitates gas-efficient operations and improves UX by allowing actions to be performed
 * without requiring direct blockchain interaction from either party
 */
contract InstantActionsAccountFacet is Accessibility, Pausable, IInstantActionsAccountFacet {
	using LibParty for address;

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
	)
		external
		whenNotThirdPartyActionsPaused
		whenNotInternalTransferPaused
		notSuspended(signedInternalTransferRequest.signer)
		notSuspended(signedInternalTransferRequest.receiver)
		userNotPartyB(signedInternalTransferRequest.signer)
	{
		LibInstantActionsAccount.instantInternalTransfer(
			signedInternalTransferRequest,
			partyASignature,
			signedInternalTransferAcceptance,
			partyBSignature
		);
		emit InternalTransfer(
			signedInternalTransferRequest.signer,
			signedInternalTransferRequest.receiver,
			signedInternalTransferRequest.collateral,
			signedInternalTransferRequest.amount,
			signedInternalTransferRequest.signer.balanceOf(signedInternalTransferRequest.collateral).isolatedBalance,
			signedInternalTransferRequest.receiver.balanceOf(signedInternalTransferRequest.collateral).isolatedBalance
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
	)
		external
		whenNotThirdPartyActionsPaused
		whenNotWithdrawingPaused
		notSuspended(signedWithdrawRequest.signer)
		notSuspended(signedWithdrawRequest.receiver)
		returns (uint256 withdrawId)
	{
		withdrawId = LibInstantActionsAccount.instantInitiateWithdraw(
			signedWithdrawRequest,
			partyASignature,
			signedWithdrawAcceptance,
			partyBSignature
		);
		emit InitiateWithdraw(
			withdrawId,
			signedWithdrawRequest.signer,
			signedWithdrawRequest.receiver,
			signedWithdrawRequest.collateral,
			signedWithdrawRequest.amount,
			signedWithdrawRequest.signer.balanceOf(signedWithdrawRequest.collateral).isolatedBalance
		);
	}

	/**
	 * @notice Transfer funds to bridge using signatures from both PartyA and PartyB
	 * @dev Combines the bridge request from PartyA and acceptance from PartyB in a single transaction
	 * All actions are authorized through signatures, allowing execution by any third party
	 * @param signedBridgeTransferRequest The bridge transfer request data from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing the bridge transfer request
	 * @param signedBridgeTransferAcceptance The bridge transfer acceptance data from PartyB
	 * @param partyBSignature Cryptographic signature from PartyB authorizing acceptance of the bridge transfer
	 */
	function instantTransferToBridge(
		SignedBridgeTransfer calldata signedBridgeTransferRequest,
		bytes calldata partyASignature,
		SignedBridgeTransfer calldata signedBridgeTransferAcceptance,
		bytes calldata partyBSignature
	)
		external
		whenNotThirdPartyActionsPaused
		whenNotBridgePaused
		notSuspended(signedBridgeTransferRequest.signer)
		userNotPartyB(signedBridgeTransferRequest.signer)
		returns (uint256 bridgeTransactionId)
	{
		bridgeTransactionId = LibInstantActionsAccount.instantTransferToBridge(
			signedBridgeTransferRequest,
			partyASignature,
			signedBridgeTransferAcceptance,
			partyBSignature
		);
		emit TransferToBridge(
			signedBridgeTransferRequest.signer,
			signedBridgeTransferRequest.receiver,
			signedBridgeTransferRequest.collateral,
			signedBridgeTransferRequest.amount,
			signedBridgeTransferRequest.bridge,
			bridgeTransactionId,
			signedBridgeTransferRequest.signer.balanceOf(signedBridgeTransferRequest.collateral).isolatedBalance
		);
	}

	/**
	 * @notice Allocates tokens from a user's isolated balance to their cross balance with a counterparty
	 * @dev Combines the allocation request from PartyA and acceptance from PartyB in a single transaction
	 * All actions are authorized through signatures, allowing execution by any third party
	 * @param signedAllocateRequest The allocation request data from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing the allocation request
	 * @param signedAllocateAcceptance The allocation acceptance data from PartyB
	 * @param partyBSignature Cryptographic signature from PartyB authorizing acceptance of the allocation
	 */
	function instantAllocate(
		SignedAllocate calldata signedAllocateRequest,
		bytes calldata partyASignature,
		SignedAllocate calldata signedAllocateAcceptance,
		bytes calldata partyBSignature
	) external whenNotThirdPartyActionsPaused notSuspended(signedAllocateRequest.signer) {
		LibInstantActionsAccount.instantAllocate(signedAllocateRequest, partyASignature, signedAllocateAcceptance, partyBSignature);
		ScheduledReleaseBalance storage balance = signedAllocateRequest.signer.balanceOf(signedAllocateRequest.collateral);
		emit Allocate(
			signedAllocateRequest.signer,
			signedAllocateRequest.collateral,
			signedAllocateRequest.counterParty,
			signedAllocateRequest.amount,
			balance.isolatedBalance,
			balance.crossBalance[signedAllocateRequest.counterParty].balance
		);
	}
}
