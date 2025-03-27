// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library TradeSettlementFacetErrors {
	// Signature errors
	error InvalidSymbolId(uint256 providedSymbolId, uint256 tradeSymbolId);

	// Trade expiration errors
	error TradeNotExpired(uint256 tradeId, uint256 currentTime, uint256 expirationTimestamp);

	// Price errors
	error InvalidSettlementPrice(uint256 settlementPrice, uint256 strikePrice, bool isPut);

	// Access window errors
	error OwnerExclusiveWindowActive(uint256 currentTime, uint256 requiredTime);

	// Exercise errors
	error CannotExerciseWithPrice(uint256 tradeId, uint256 settlementPrice, uint256 pnl);
}
