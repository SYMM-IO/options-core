// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library CounterPartyRelationsFacetErrors {
	// Instant action mode errors
	error InstantActionModeActive(address user);
	error InstantActionModeDeactivationNotProposed(address user);

	// PartyB binding errors
	error PartyBNotActive(address partyB);
	error AlreadyBoundToPartyB(address user, address partyB);
	error NotBoundToAnyPartyB(address user);
	error UnbindingAlreadyInitiated(address user, uint256 requestTime);
	error UnbindingNotInitiated(address user);
	error UnbindingCooldownNotReached(address user, uint256 currentTime, uint256 requiredTime);
}
