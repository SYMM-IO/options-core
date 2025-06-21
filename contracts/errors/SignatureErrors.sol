// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library SignatureErrors {
	error ExpiredSignature(uint256 currentTime, uint256 sigTimestamp, uint256 validTime, uint256 expiryTime);
	error InvalidSignature(address signer, bytes32 hashValue);
	error SignatureAlreadyUsed(bytes32 hashValue);
}
