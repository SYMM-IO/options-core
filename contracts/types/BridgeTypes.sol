// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

struct BridgeTransaction {
	uint256 id;
	uint256 amount;
	address collateral;
	address sender;
	address receiver;
	address bridge;
	uint256 timestamp;
	BridgeTransactionStatus status;
}

enum BridgeTransactionStatus {
	RECEIVED,
	SUSPENDED,
	WITHDRAWN
}
