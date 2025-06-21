// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyBOpenErrors {
	error PartyBInEmergencyMode(address partyB);
	error SystemInEmergencyMode();
	error SelfTradeNotAllowed(address user);
	error IntentNotFound(uint256 intentId);
	error OracleMismatch(address partyB, uint256 partyBOracleId, uint256 symbolOracleId);
	error SymbolTypeMismatch(address partyB, uint256 partyBSymbolType, uint256 symbolType);
	error NotWhitelistedPartyB(address sender, address[] whiteList);
	error InvalidOpenPrice(uint256 providedPrice, uint256 maxPrice);
}
