// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library AccountErrors {
	error BalanceLimitExceeded(int256 balance, uint256 amount, uint256 limit);
	error InvalidWithdrawalId(uint256 id);
	error InvalidCounterParty(address party, address counterParty);
	error InsufficientDebtCoverage(address party, address counterParty, int256 partyAReadyToDeallocate, uint256 amount, int256 debt);
	error InsolventParty(address party);
}
