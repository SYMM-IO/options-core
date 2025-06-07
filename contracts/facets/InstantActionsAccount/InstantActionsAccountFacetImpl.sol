// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../../libraries/utils/LibHash.sol";
import { LibSignature } from "../../libraries/services/LibSignature.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";

import { SignedInternalTransfer, SignedWithdraw } from "../../types/SignedAccountTypes.sol";

library InstantActionsAccountFacetImpl {
	error MismatchedSignatures();
	error DeadlineExpired();

	function instantInternalTransfer(
		SignedInternalTransfer calldata signedInternalTransferRequest,
		bytes calldata partyASignature,
		SignedInternalTransfer calldata signedInternalTransferAcceptance,
		bytes calldata partyBSignature
	) internal {
		bytes32 internalTransferHash = LibHash.hashInternalTransfer(signedInternalTransferRequest);
		LibSignature.verifySignature(internalTransferHash, partyASignature, signedInternalTransferRequest.signer);

		bytes32 internalTransferAcceptanceHash = LibHash.hashInternalTransfer(signedInternalTransferAcceptance);
		LibSignature.verifySignature(internalTransferAcceptanceHash, partyBSignature, signedInternalTransferAcceptance.signer);

		if (signedInternalTransferRequest.deadline < block.timestamp) revert DeadlineExpired();

		if (
			signedInternalTransferRequest.sender != signedInternalTransferAcceptance.sender ||
			signedInternalTransferRequest.receiver != signedInternalTransferAcceptance.receiver ||
			signedInternalTransferRequest.collateral != signedInternalTransferAcceptance.collateral ||
			signedInternalTransferRequest.amount != signedInternalTransferAcceptance.amount ||
			signedInternalTransferRequest.salt != signedInternalTransferAcceptance.salt
		) revert MismatchedSignatures();

		LibBalanceOperations.internalTransfer(
			signedInternalTransferRequest.collateral,
			signedInternalTransferRequest.sender,
			signedInternalTransferRequest.receiver,
			signedInternalTransferRequest.amount
		);
	}

	function instantInitiateWithdraw(
		SignedWithdraw calldata signedWithdrawRequest,
		bytes calldata partyASignature,
		SignedWithdraw calldata signedWithdrawAcceptance,
		bytes calldata partyBSignature
	) internal returns (uint256 withdrawId) {
		bytes32 internalTransferHash = LibHash.hashWithdraw(signedWithdrawRequest);
		LibSignature.verifySignature(internalTransferHash, partyASignature, signedWithdrawRequest.signer);

		bytes32 internalTransferAcceptanceHash = LibHash.hashWithdraw(signedWithdrawAcceptance);
		LibSignature.verifySignature(internalTransferAcceptanceHash, partyBSignature, signedWithdrawAcceptance.signer);

		if (signedWithdrawRequest.deadline < block.timestamp) revert DeadlineExpired();

		if (
			signedWithdrawRequest.sender != signedWithdrawAcceptance.sender ||
			signedWithdrawRequest.receiver != signedWithdrawAcceptance.receiver ||
			signedWithdrawRequest.collateral != signedWithdrawAcceptance.collateral ||
			signedWithdrawRequest.amount != signedWithdrawAcceptance.amount ||
			signedWithdrawRequest.salt != signedWithdrawAcceptance.salt
		) revert MismatchedSignatures();

		return
			LibBalanceOperations.initiateWithdraw(
				signedWithdrawRequest.sender,
				signedWithdrawRequest.collateral,
				signedWithdrawRequest.amount,
				signedWithdrawRequest.receiver
			);
	}
}
