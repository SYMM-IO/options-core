// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IntentStorage } from "../storages/IntentStorage.sol";
import { ISignatureVerifier } from "../interfaces/ISignatureVerifier.sol";

library LibSignature {
	function verifySignature(bytes32 hashValue, bytes calldata signature, address signer) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		require(ISignatureVerifier(intentLayout.signatureVerifier).verifySignature(signer, hashValue, signature), "LibSignature: Invalid signature");
		require(!intentLayout.isSigUsed[hashValue], "LibSignature: Signature is already used");
		intentLayout.isSigUsed[hashValue] = true;
	}
}
