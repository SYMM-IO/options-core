// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

interface ISignatureVerifier {
	function verifySignature(address signer, bytes32 hash, bytes calldata signature) external view returns (bool);
}
