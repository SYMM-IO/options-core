// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface ISignatureVerifier {
	function verifySignature(address signer, bytes32 hash, bytes calldata signature) external view returns (bool);
	function isValidSignatureEIP1271(bytes32 hash, bytes calldata signature, address signer) external view returns (bytes4);
}
