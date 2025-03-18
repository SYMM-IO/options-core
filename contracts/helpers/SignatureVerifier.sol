// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @notice A minimal contract that hashes and verifies signatures
 *         for creating open intents on behalf of Party A.
 */
contract SignatureVerifier {
	function verifySignature(address signer, bytes32 hash, bytes calldata signature) external view returns (bool) {
		return SignatureChecker.isValidSignatureNow(signer, hash, signature);
	}
}
