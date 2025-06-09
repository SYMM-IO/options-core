// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibHash } from "../utils/LibHash.sol";
import { LibSignature } from "../services/LibSignature.sol";

import { OpenIntentStatus } from "../../types/IntentTypes.sol";
import { SignedFillIntentById, SignedSimpleActionIntent } from "../../types/SignedIntentTypes.sol";

import { LibPartyBOpen } from "../core/LibPartyBOpen.sol";

library LibInstantActionsPartyBOpen {
	function instantFillOpenIntent(
		SignedFillIntentById calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) internal returns (uint256 tradeId, uint256 newIntentId) {
		bytes32 fillOpenIntentHash = LibHash.hashSignedFillOpenIntentById(signedFillOpenIntent);
		LibSignature.verifySignature(fillOpenIntentHash, partyBSignature, signedFillOpenIntent.partyB);

		(tradeId, newIntentId) = LibPartyBOpen.fillOpenIntent(
			signedFillOpenIntent.partyB,
			signedFillOpenIntent.intentId,
			signedFillOpenIntent.quantity,
			signedFillOpenIntent.price
		);
	}

	function instantLock(SignedSimpleActionIntent calldata signedLockIntent, bytes calldata partyBSignature) internal {
		bytes32 lockIntentHash = LibHash.hashSignedLockIntent(signedLockIntent);
		LibSignature.verifySignature(lockIntentHash, partyBSignature, signedLockIntent.signer);

		LibPartyBOpen.lockOpenIntent(signedLockIntent.signer, signedLockIntent.intentId);
	}

	function instantUnlock(SignedSimpleActionIntent calldata signedUnlockIntent, bytes calldata partyBSignature) internal returns (OpenIntentStatus) {
		bytes32 unlockIntentHash = LibHash.hashSignedUnlockIntent(signedUnlockIntent);
		LibSignature.verifySignature(unlockIntentHash, partyBSignature, signedUnlockIntent.signer);

		return LibPartyBOpen.unlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
	}
}
