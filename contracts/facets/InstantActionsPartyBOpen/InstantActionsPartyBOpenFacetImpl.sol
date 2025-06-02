// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../../libraries/LibHash.sol";
import { LibSignature } from "../../libraries/LibSignature.sol";

import { OpenIntentStatus } from "../../types/IntentTypes.sol";
import { SignedFillIntentById, SignedSimpleActionIntent } from "../../types/SignedIntentTypes.sol";

import { PartyBOpenFacetImpl } from "../PartyBOpen/PartyBOpenFacetImpl.sol";

library InstantActionsPartyBOpenFacetImpl {
	function instantFillOpenIntent(
		SignedFillIntentById calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		bytes32 fillOpenIntentHash = LibHash.hashSignedFillOpenIntentById(signedFillOpenIntent);
		LibSignature.verifySignature(fillOpenIntentHash, partyBSignature, signedFillOpenIntent.partyB);

		(tradeId, newIntentId) = PartyBOpenFacetImpl.fillOpenIntent(
			signedFillOpenIntent.partyB,
			signedFillOpenIntent.intentId,
			signedFillOpenIntent.quantity,
			signedFillOpenIntent.price
		);
	}

	function instantLock(SignedSimpleActionIntent calldata signedLockIntent, bytes calldata partyBSignature) internal {
		bytes32 lockIntentHash = LibHash.hashSignedLockIntent(signedLockIntent);
		LibSignature.verifySignature(lockIntentHash, partyBSignature, signedLockIntent.signer);

		PartyBOpenFacetImpl.lockOpenIntent(signedLockIntent.signer, signedLockIntent.intentId);
	}

	function instantUnlock(SignedSimpleActionIntent calldata signedUnlockIntent, bytes calldata partyBSignature) internal returns (OpenIntentStatus) {
		bytes32 unlockIntentHash = LibHash.hashSignedUnlockIntent(signedUnlockIntent);
		LibSignature.verifySignature(unlockIntentHash, partyBSignature, signedUnlockIntent.signer);

		return PartyBOpenFacetImpl.unlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
	}
}
