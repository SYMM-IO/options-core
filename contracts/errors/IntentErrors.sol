// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library IntentErrors {
	// Intent timing
	error IntentExpired(uint256 intentId, uint256 currentTime, uint256 deadline);
	error IntentNotExpired(uint256 intentId, uint256 currentTime, uint256 deadline);
	error ExpirationTimestampPassed(uint256 provided, uint256 current);

	// Open intent - PartyA specific
	error PartyBSender();
	error IsolatedModeSellNotAllowed();
	error InvalidWhitelistEntry(address partyA);
	error InvalidExerciseFee(uint256 cap, uint256 maxCap);
	error InvalidAffiliate(address affiliate);
	error MultiplePartyBNotAllowed();
	error InvalidOpenQuantity();

	// Open intent - PartyB specific
	error IntentNotFound(uint256 intentId);
	error OracleMismatch(address partyB, uint256 partyBOracleId, uint256 symbolOracleId);
	error SymbolTypeNotSupported(address partyB, uint256 symbolType);
	error NotWhitelistedPartyB(address sender, address[] whiteList);
	error InvalidOpenPrice(uint256 providedPrice, uint256 thresholdPrice);

	// Close intent errors
	error InvalidQuantity(uint256 requested, uint256 available);
	error TooManyCloseOrders(uint256 current, uint256 maximum);
	error InvalidClosePrice(uint256 providedPrice, uint256 thresholdPrice);

	// Fill intent errors
	error InvalidFillAmount(uint256 quantity, uint256 availableAmount);
}
