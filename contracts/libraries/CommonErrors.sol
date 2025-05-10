// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library CommonErrors {
	error ZeroAddress(string property);

	error EmptyList();

	error SuspendedAddress(address user);

	error InvalidSymbol(uint256 symbolId);

	error LowDeadline(uint256 deadline, uint256 current);

	error InvalidAmount(string property, uint256 amount, uint8 operator, uint256 required); // 0: gt | 1: lt | 2: eq

	error InsufficientBalance(address user, address token, uint256 requested, uint256 available);

	error InsufficientIntBalance(address user, address token, uint256 requested, int256 available);

	error CooldownNotOver(string cooldown, uint256 currentTime, uint256 requiredTime);

	error UnauthorizedSender(address sender, address requiredSender);

	error InvalidState(string property, uint8 currentStatus, uint8[] requiredStatus);

	error CollateralNotWhitelisted(address collateral);

	function requireStatus(string memory property, uint8 current, uint8 expected) internal pure {
		if (current != expected) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = expected;
			revert InvalidState(property, current, requiredStatuses);
		}
	}
}
