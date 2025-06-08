// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../../libraries/utils/LibHash.sol";
import { LibSignature } from "../../libraries/services/LibSignature.sol";

import { CloseIntentStatus } from "../../types/IntentTypes.sol";
import { SignedFillIntentById, SignedSimpleActionIntent, SignedFillIntent, SignedCloseIntent } from "../../types/SignedIntentTypes.sol";

import { LibPartyBClose } from "../../libraries/core/LibPartyBClose.sol";
import { LibPartyAClose } from "../../libraries/core/LibPartyAClose.sol";

library InstantActionsCloseFacetImpl {
	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) internal returns (CloseIntentStatus status) {
		bytes32 cancelIntentHash = LibHash.hashSignedCancelCloseIntent(signedCancelCloseIntent);
		LibSignature.verifySignature(cancelIntentHash, partyASignature, signedCancelCloseIntent.signer);

		status = LibPartyAClose.cancelCloseIntent(signedCancelCloseIntent.signer, signedCancelCloseIntent.intentId);

		if (status == CloseIntentStatus.CANCEL_PENDING) {
			bytes32 acceptCancelIntentHash = LibHash.hashSignedAcceptCancelCloseIntent(signedAcceptCancelCloseIntent);
			LibSignature.verifySignature(acceptCancelIntentHash, partyBSignature, signedAcceptCancelCloseIntent.signer);

			LibPartyBClose.acceptCancelCloseIntent(signedAcceptCancelCloseIntent.signer, signedAcceptCancelCloseIntent.intentId);
			status = CloseIntentStatus.CANCELED;
		}
	}

	function instantFillCloseIntent(SignedFillIntentById calldata signedFillCloseIntent, bytes calldata partyBSignature) internal {
		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntentById(signedFillCloseIntent);
		LibSignature.verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

		LibPartyBClose.fillCloseIntent(
			signedFillCloseIntent.partyB,
			signedFillCloseIntent.intentId,
			signedFillCloseIntent.quantity,
			signedFillCloseIntent.price
		);
	}

	function instantCloseAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 intentId) {
		bytes32 closeIntentHash = LibHash.hashSignedCloseIntent(signedCloseIntent);
		LibSignature.verifySignature(closeIntentHash, partyASignature, signedCloseIntent.partyA);

		bytes32 fillCloseIntentHash = LibHash.hashSignedFillCloseIntent(signedFillCloseIntent);
		LibSignature.verifySignature(fillCloseIntentHash, partyBSignature, signedFillCloseIntent.partyB);

		intentId = LibPartyAClose.sendCloseIntent(
			signedCloseIntent.partyA,
			signedCloseIntent.tradeId,
			signedCloseIntent.quantity,
			signedCloseIntent.price,
			signedCloseIntent.deadline
		);

		LibPartyBClose.fillCloseIntent(signedFillCloseIntent.partyB, intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}
}
