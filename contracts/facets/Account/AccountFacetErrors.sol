// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library AccountFacetErrors {
	error BalanceLimitPerUserReached(int256 balance, uint256 amount, uint256 limit);

	// Withdraw errors
	error InvalidWithdrawId(uint256 id, uint256 lastWithdrawId);

	// deallocate errors
	error InvalidCounterPartyToAllocate(address party, address counterParty);
	error NotEnoughBalance(address party, address counterParty, int256 availableBalance, int256 amount);
	error RemainingAmountMoreThanCounterPartyDebt(address party, address counterParty, int256 partyAReadyToDeallocate, int256 amount, int256 debt);
	error PartyShouldBeLiquidated(address party);
}
