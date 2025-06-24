// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library PartyRelationsErrors {
	// Instant mode
	error InstantModeActive(address sender);
	error InstantModeNotActive(address sender);

	// Party binding
	error DeactivationNotProposed(address user);
	error PartyBNotActive(address partyB);
	error BoundedToAnotherPartyB(address user, address partyB);
	error BoundedPartyBNotFound(address user);
	error UnbindingAlreadyInProgress(address user, uint256 requestTime);
	error UnbindingNotInitiated(address user);
	error UnbindingCooldownNotOver(address user, uint256 currentTime, uint256 requiredTime);
}
