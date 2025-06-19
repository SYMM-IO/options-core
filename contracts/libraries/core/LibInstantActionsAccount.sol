// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../../libraries/utils/LibHash.sol";
import { LibSignature } from "../../libraries/services/LibSignature.sol";
import { LibBalanceOperations } from "../../libraries/core/LibBalanceOperations.sol";
import { LibBridge } from "../../libraries/core/LibBridge.sol";

import { SignedInternalTransfer, SignedWithdraw, SignedBridgeTransfer } from "../../types/SignedAccountTypes.sol";

library LibInstantActionsAccount {
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
			signedInternalTransferRequest.signer != signedInternalTransferAcceptance.signer ||
			signedInternalTransferRequest.receiver != signedInternalTransferAcceptance.receiver ||
			signedInternalTransferRequest.collateral != signedInternalTransferAcceptance.collateral ||
			signedInternalTransferRequest.amount != signedInternalTransferAcceptance.amount ||
			signedInternalTransferRequest.deadline != signedInternalTransferAcceptance.deadline ||
			signedInternalTransferRequest.salt != signedInternalTransferAcceptance.salt
		) revert MismatchedSignatures();

		LibBalanceOperations.internalTransfer(
			signedInternalTransferRequest.collateral,
			signedInternalTransferRequest.signer,
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
		bytes32 withdrawHash = LibHash.hashWithdraw(signedWithdrawRequest);
		LibSignature.verifySignature(withdrawHash, partyASignature, signedWithdrawRequest.signer);

		bytes32 withdrawHashAcceptanceHash = LibHash.hashWithdraw(signedWithdrawAcceptance);
		LibSignature.verifySignature(withdrawHashAcceptanceHash, partyBSignature, signedWithdrawAcceptance.signer);

		if (signedWithdrawRequest.deadline < block.timestamp) revert DeadlineExpired();

		if (
			signedWithdrawRequest.signer != signedWithdrawAcceptance.signer ||
			signedWithdrawRequest.sender != signedWithdrawAcceptance.sender ||
			signedWithdrawRequest.receiver != signedWithdrawAcceptance.receiver ||
			signedWithdrawRequest.collateral != signedWithdrawAcceptance.collateral ||
			signedWithdrawRequest.amount != signedWithdrawAcceptance.amount ||
			signedWithdrawRequest.deadline != signedWithdrawAcceptance.deadline ||
			signedWithdrawRequest.salt != signedWithdrawAcceptance.salt
		) revert MismatchedSignatures();

		return
			LibBalanceOperations.initiateWithdraw(
				signedWithdrawRequest.signer,
				signedWithdrawRequest.collateral,
				signedWithdrawRequest.amount,
				signedWithdrawRequest.receiver
			);
	}

	function instantTransferToBridge(
		SignedBridgeTransfer calldata signedBridgeTransferRequest,
		bytes calldata partyASignature,
		SignedBridgeTransfer calldata signedBridgeTransferAcceptance,
		bytes calldata partyBSignature
	) internal returns (uint256 bridgeTransactionId) {
		bytes32 bridgeTransferHash = LibHash.hashBridgeTransfer(signedBridgeTransferRequest);
		LibSignature.verifySignature(bridgeTransferHash, partyASignature, signedBridgeTransferRequest.signer);

		bytes32 bridgeTransferAcceptanceHash = LibHash.hashBridgeTransfer(signedBridgeTransferAcceptance);
		LibSignature.verifySignature(bridgeTransferAcceptanceHash, partyBSignature, signedBridgeTransferAcceptance.signer);

		if (signedBridgeTransferRequest.deadline < block.timestamp) revert DeadlineExpired();

		if (
			signedBridgeTransferRequest.sender != signedBridgeTransferAcceptance.sender ||
			signedBridgeTransferRequest.signer != signedBridgeTransferAcceptance.signer ||
			signedBridgeTransferRequest.bridge != signedBridgeTransferAcceptance.bridge ||
			signedBridgeTransferRequest.receiver != signedBridgeTransferAcceptance.receiver ||
			signedBridgeTransferRequest.collateral != signedBridgeTransferAcceptance.collateral ||
			signedBridgeTransferRequest.amount != signedBridgeTransferAcceptance.amount ||
			signedBridgeTransferRequest.deadline != signedBridgeTransferAcceptance.deadline ||
			signedBridgeTransferRequest.salt != signedBridgeTransferAcceptance.salt
		) revert MismatchedSignatures();

		return
			LibBridge.transferToBridge(
				signedBridgeTransferRequest.signer,
				signedBridgeTransferRequest.collateral,
				signedBridgeTransferRequest.amount,
				signedBridgeTransferRequest.bridge,
				signedBridgeTransferRequest.receiver
			);
	}
}
