// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType, TradeSide, ExerciseFee } from "./BaseTypes.sol";

struct SignedOpenIntent {
	address partyA;
	address partyB;
	uint256 symbolId;
	uint256 price;
	uint256 quantity;
	uint256 strikePrice;
	uint256 expirationTimestamp;
	uint256 mm;
	TradeSide tradeSide;
	MarginType marginType;
	ExerciseFee exerciseFee;
	uint256 deadline;
	address affiliate;
	address feeToken;
	bytes userData;
	uint256 salt;
}

struct SignedCloseIntent {
	address partyA;
	uint256 tradeId;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
}

struct SignedFillIntent {
	address partyB;
	bytes32 intentHash;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
	MarginType marginType;
}

struct SignedFillIntentById {
	address partyB;
	uint256 intentId;
	uint256 price;
	uint256 quantity;
	uint256 deadline;
	uint256 salt;
	MarginType marginType;
}

struct SignedSimpleActionIntent {
	address signer;
	uint256 intentId;
	uint256 deadline;
	uint256 salt;
}
