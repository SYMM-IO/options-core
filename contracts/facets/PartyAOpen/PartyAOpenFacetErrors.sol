// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyAOpenFacetErrors {
	// Sender validation errors
	error SenderIsPartyB(address sender);
	error ShortTradeInIsolatedMode();

	// Timestamp errors
	error LowExpirationTimestamp(uint256 provided, uint256 current);

	// Fee errors
	error HighExerciseFeeCap(uint256 cap, uint256 maxCap);

	// Affiliate errors
	error InvalidAffiliate(address affiliate);

	// PartyB binding errors
	error UserBoundToAnotherPartyB(address user, address boundPartyB, address[] requestedPartyBs);
}
