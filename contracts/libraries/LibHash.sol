// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SignedOpenIntent, SignedCloseIntent, SignedFillIntent, SignedFillIntentById, SignedSimpleActionIntent } from "../storages/IntentStorage.sol";

library LibHash {
	function hashSignedOpenIntent(SignedOpenIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioOpenIntent_v1");

		bytes memory encodedData = abi.encode(
			SIGN_PREFIX,
			req.partyA,
			req.partyB,
			req.price,
			abi.encode(req.symbolId, req.quantity, req.strikePrice, req.expirationTimestamp, req.mm, req.exerciseFee.rate, req.exerciseFee.cap),
			req.marginType,
			req.deadline,
			req.feeToken,
			req.affiliate,
			req.salt
		);

		return keccak256(encodedData);
	}

	function hashSignedCloseIntent(SignedCloseIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyA, req.tradeId, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillOpenIntent(SignedFillIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt, req.marginType));
	}

	function hashSignedFillOpenIntentById(SignedFillIntentById calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillOpenIntentById_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt, req.marginType));
	}

	function hashSignedFillCloseIntent(SignedFillIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentHash, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedFillCloseIntentById(SignedFillIntentById calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioFillCloseIntentById_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.partyB, req.intentId, req.price, req.quantity, req.deadline, req.salt));
	}

	function hashSignedCancelOpenIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedAcceptCancelOpenIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelOpenIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedCancelCloseIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioCancelCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedAcceptCancelCloseIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioAcceptCancelCloseIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedLockIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioLockIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}

	function hashSignedUnlockIntent(SignedSimpleActionIntent calldata req) internal pure returns (bytes32) {
		bytes32 SIGN_PREFIX = keccak256("SymmioUnlockIntent_v1");

		return keccak256(abi.encode(SIGN_PREFIX, req.signer, req.intentId, req.deadline, req.salt));
	}
}
