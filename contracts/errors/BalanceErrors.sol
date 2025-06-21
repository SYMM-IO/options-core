// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library BalanceErrors {
	error MaxCounterPartyConnectionsReached(uint256 current, uint256 maximum);
	error InvalidSyncTimestamp(uint256 currentTime, uint256 lastTransitionTimestamp);
	error NonZeroBalanceCounterParty(address counterParty, uint256 balance);
	error InsufficientBalance(address token, uint256 requested, int256 balance);
	error InsufficientLockedBalance(address token, uint256 requested, uint256 balance);
	error InsufficientMMBalance(address token, uint256 requested, uint256 balance);
	error BalanceSetupRequired();
}
