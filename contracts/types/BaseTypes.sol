// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

enum TradeSide {
	BUY,
	SELL
}

enum MarginType {
	ISOLATED, // per‑position margin
	CROSS // shared margin against a specific counter‑party
}

struct ExerciseFee {
	uint256 rate;
	uint256 cap;
}

struct TradingFee {
	address feeToken;
	uint256 tokenPrice;
	uint256 platformFee;
	uint256 affiliateFee;
}

struct TradeAgreements {
	uint256 symbolId;
	uint256 quantity;
	uint256 strikePrice;
	uint256 expirationTimestamp;
	uint256 mm;
	TradeSide tradeSide;
	MarginType marginType;
	ExerciseFee exerciseFee;
}
