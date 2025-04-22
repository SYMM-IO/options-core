// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ISignatureVerifier } from "../interfaces/ISignatureVerifier.sol";
import { CommonErrors } from "./CommonErrors.sol";
import { AppStorage } from "../storages/AppStorage.sol";

library LibSignature {
	// Custom errors
	error InvalidSignature(address signer, bytes32 hashValue);
	error SignatureAlreadyUsed(bytes32 hashValue);

	function verifySignature(bytes32 hashValue, bytes calldata signature, address signer) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		if (!ISignatureVerifier(appLayout.signatureVerifier).verifySignature(signer, hashValue, signature))
			revert InvalidSignature(signer, hashValue);

		if (appLayout.isSigUsed[hashValue]) revert SignatureAlreadyUsed(hashValue);

		appLayout.isSigUsed[hashValue] = true;
	}
}
