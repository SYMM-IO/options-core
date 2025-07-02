// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IMultiAccount {
	function owners(address user) external view returns (address);
	function _call(address account, bytes[] memory _callDatas) external;
	function verifySignatureOfAccount(address account, bytes32 hash, bytes calldata signature) external view returns (bytes4);
	function transferTradeNFT(address account, address to, uint256 tokenId) external;
}
