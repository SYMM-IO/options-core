// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { TradeAgreements } from "./BaseTypes.sol";

enum IntentStatus {
	PENDING,
	LOCKED,
	CANCEL_PENDING,
	CANCELED,
	FILLED,
	EXPIRED
}

struct TradingFee {
	address feeToken;
	uint256 tokenPrice;
	uint256 platformFee;
	uint256 affiliateFee;
}

struct OpenIntent {
	uint256 id;
	uint256 tradeId;
	TradeAgreements tradeAgreements;
	uint256 price;
	address partyA;
	address partyB;
	address[] partyBsWhiteList;
	IntentStatus status;
	uint256 parentId;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
	TradingFee tradingFee;
	address affiliate;
	bytes userData;
}

struct CloseIntent {
	uint256 id;
	uint256 tradeId;
	uint256 price;
	uint256 quantity;
	uint256 filledAmount;
	IntentStatus status;
	uint256 createTimestamp;
	uint256 statusModifyTimestamp;
	uint256 deadline;
}
