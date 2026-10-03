// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @notice OpenZeppelin 4.x signature semantics: accept a valid ECDSA signature from `signer`, otherwise fall back to ERC-1271.
/// @dev OpenZeppelin 5.x routes on `signer.code.length`, which rejects raw-key signatures from signers that have code
///      (e.g. EIP-7702-delegated EOAs). Kept to avoid changing who can authorize during the OZ 5 migration.
library LibSignatureChecker {
	function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
		(address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
		return (err == ECDSA.RecoverError.NoError && recovered == signer) || SignatureChecker.isValidERC1271SignatureNow(signer, hash, signature);
	}
}
