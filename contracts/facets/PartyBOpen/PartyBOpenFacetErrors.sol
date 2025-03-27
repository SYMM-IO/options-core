// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyBOpenFacetErrors {
	// Party errors
	error PartyBInEmergencyMode(address partyB);
	error SystemInEmergencyMode();
	error UserOnBothSides(address user);

	// Intent validation errors
	error InvalidIntentId(uint256 intentId, uint256 lastIntentId);
	error IntentExpired(uint256 intentId, uint256 currentTime, uint256 deadline);
	error ExpirationTimestampPassed(uint256 intentId, uint256 currentTime, uint256 expirationTimestamp);

	// Oracle errors
	error OracleNotMatched(address partyB, uint256 partyBOracleId, uint256 symbolOracleId);
	error MismatchedSymbolType(address partyB, uint256 partyBSymbolType, uint256 symbolType);

	// Whitelist errors
	error NotWhitelistedPartyB(address sender, address[] whiteList);

	// Price errors
	error InvalidOpenPrice(uint256 providedPrice, uint256 maxPrice);
}
