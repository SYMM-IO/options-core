// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library AccountFacetErrors {
	// Collateral errors
	error CollateralNotWhitelisted(address collateral);

	// Instant action mode errors
	error InstantActionModeAlreadyActivated(address user);
	error InstantActionModeNotActivated(address user);
	error InstantActionModeActive(address user);
	error InstantActionModeDeactivationNotProposed(address user);

	// Withdraw errors
	error InvalidWithdrawId(uint256 id, uint256 lastWithdrawId);

	// PartyB binding errors
	error PartyBNotActive(address partyB);
	error AlreadyBoundToPartyB(address user, address partyB);
	error NotBoundToAnyPartyB(address user);
	error UnbindingAlreadyInitiated(address user, uint256 requestTime);
	error UnbindingNotInitiated(address user);
	error UnbindingCooldownNotReached(address user, uint256 currentTime, uint256 requiredTime);

	// deallocate errors
	error InvalidCounterPartyToAllocate(address party, address counterParty);
	error NotEnoughBalance(address party, address counterParty, int256 availableBalance, int256 amount);
	error RemainingAmountMoreThanCounterPartyDebt(address party, address counterParty, int256 partyAReadyToDeallocate, int256 amount, int256 debt);
}
