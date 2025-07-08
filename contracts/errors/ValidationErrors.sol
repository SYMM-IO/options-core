// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library ValidationErrors {
	// Basic validation
	error ZeroAddress(string property);
	error ZeroAmount();
	error EmptyList();
	error EmptyField(string property);
	error LowDeadline(uint256 deadline, uint256 current);
	error CooldownNotOver(string cooldown, uint256 currentTime, uint256 requiredTime);
	error InvalidState(string property, uint8 currentStatus, uint8[] requiredStatus);
	error UnauthorizedSender(address sender, address requiredSender);
	error MismatchedLengths();
	
	// Access control
	error NotPartyB(address user);
	error PartyBUser(address user);
	error MissingRole(address sender, bytes32 role);

	// Symbol/Oracle validation
	error InvalidSymbol(uint256 symbolId);
	error CollateralNotWhitelisted(address collateral);
	error OracleNotFound(uint256 oracleId);

	// Signature validation
	error ExpiredSignature(uint256 currentTime, uint256 sigTimestamp, uint256 validTime, uint256 expiryTime);
	error InvalidSignature(address signer, bytes32 hashValue);
	error SignatureAlreadyUsed(bytes32 hashValue);

	// Data validation
	error InsufficientBytes(uint256 providedLength, uint256 minimumLength);

	// External transfer validation
	error ExternalTransferTargetNotWhitelisted(address target, address collateral);

	// Helper function for requireStatus pattern used throughout the codebase
	function requireStatus(string memory property, uint8 current, uint8 expected) internal pure {
		if (current != expected) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = expected;
			revert InvalidState(property, current, requiredStatuses);
		}
	}
}
