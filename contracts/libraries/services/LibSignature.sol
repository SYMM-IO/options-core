// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { AppStorage } from "../../storages/AppStorage.sol";

import { ISignatureVerifier } from "../../interfaces/ISignatureVerifier.sol";
import { SignatureErrors } from "../../errors/SignatureErrors.sol";

library LibSignature {
	function verifySignature(bytes32 hashValue, bytes calldata signature, address signer) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (!ISignatureVerifier(appLayout.signatureVerifier).verifySignature(signer, hashValue, signature))
			revert SignatureErrors.InvalidSignature(signer, hashValue);

		if (appLayout.isSigUsed[hashValue]) revert SignatureErrors.SignatureAlreadyUsed(hashValue);

		appLayout.isSigUsed[hashValue] = true;
	}
}
