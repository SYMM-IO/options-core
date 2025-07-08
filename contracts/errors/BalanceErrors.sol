// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType } from "../types/BaseTypes.sol";

library BalanceErrors {
    // Balance checks
    error InsufficientBalance(address user, address token, uint256 requested, uint256 available);
    error InsufficientIntBalance(address user, address token, uint256 requested, int256 available);
    error InsufficientLockedBalance(address token, uint256 requested, uint256 balance);
    error InsufficientMMBalance(address token, uint256 requested, uint256 balance);
    
    // Balance limits
    error BalanceLimitExceeded(int256 balance, uint256 amount, uint256 limit);
    
    // Scheduled release specific
    error MaxCounterPartyConnectionsReached(uint256 current, uint256 maximum);
    error InvalidSyncTimestamp(uint256 currentTime, uint256 lastTransitionTimestamp);
    error NonZeroBalanceCounterParty(address counterParty, uint256 balance);
    error BalanceSetupRequired();
    
    // Allocation/Deallocation
    error InvalidCounterParty(address party, address counterParty);
    error InsufficientDebtCoverage(address party, address counterParty, int256 partyAReadyToDeallocate, uint256 amount, int256 debt);
    
    // Solvency
    error NotSolvent(address user, address counterParty, address collateral, MarginType marginType);
    
    // Withdrawal specific
    error InvalidWithdrawalId(uint256 id);
    error ExpressWithdrawCancellationNotAllowed(address provider);
    error ExpressWithdrawProviderNotActive(address provider);
    error ExpressWithdrawProviderReceiverNotSet(address provider);
    error ExpressWithdrawRejectedByProvider(address provider, string reason);
	error ValidAmountExceedsOriginal(uint256 givenValidAmount, uint256 expressWithdrawAmount);
}