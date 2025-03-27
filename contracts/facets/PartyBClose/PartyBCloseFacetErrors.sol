// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyBCloseFacetErrors {
	// Quantity errors
	error InvalidFilledAmount(uint256 quantity, uint256 availableAmount);

	// Timestamp errors
	error IntentExpired(uint256 intentId, uint256 currentTime, uint256 deadline);
	error TradeExpired(uint256 tradeId, uint256 currentTime, uint256 expirationTimestamp);

	// Price errors
	error InvalidClosedPrice(uint256 providedPrice, uint256 requiredMinPrice);
}
