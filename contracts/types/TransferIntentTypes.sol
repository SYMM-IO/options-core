// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

enum TransferIntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FINALIZED
}

struct TransferIntent {
	uint256 id;
	uint256 tradeId;
	uint256 deadline;
	address sender;
	address[] whitelist;
	address receiver;
	uint256 proposedPrice;
	TransferIntentStatus status;
}
