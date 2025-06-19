// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

struct SignedInternalTransfer {
	address signer;
	address sender;
	address receiver;
	uint256 amount;
	address collateral;
	uint256 deadline;
	uint256 salt;
}

struct SignedWithdraw {
	address signer;
	address sender;
	address receiver;
	uint256 amount;
	address collateral;
	uint256 deadline;
	uint256 salt;
}

struct SignedBridgeTransfer {
	address signer;
	address sender;
	address bridge;
	address receiver;
	uint256 amount;
	address collateral;
	uint256 deadline;
	uint256 salt;
}

struct SignedAllocate {
	address signer;
	address sender;
	address counterParty;
	uint256 amount;
	address collateral;
	uint256 deadline;
	uint256 salt;
}