// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { TradeAgreements, FeeStructure } from "./BaseTypes.sol";

enum OpenIntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED
}

enum CloseIntentStatus {
	PENDING,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED
}

struct OpenIntent {
	uint256 id;
	uint256 tradeId;
	TradeAgreements tradeAgreements;
	uint256 price;
	address[] partyBsWhiteList;
	uint256 parentId;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
	FeeStructure feeStructure;
	address partyA;
	address partyB;
	address affiliate;
	bytes userData;
	OpenIntentStatus status;
}

struct CloseIntent {
	uint256 id;
	uint256 tradeId;
	uint256 price;
	uint256 quantity;
	uint256 filledAmount;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
	FeeStructure feeStructure;
	CloseIntentStatus status;
}
