// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface IAccountEvents {
	event Deposit(address sender, address user, address collateral, uint256 amount, uint256 newBalance);
	event InternalTransfer(
		address sender,
		address receiver,
		address collateral,
		uint256 amount,
		uint256 newBalanceOfSender,
		uint256 newBalanceOfReceiver
	);
	event InitiateWithdraw(uint256 id, address user, address to, address collateral, uint256 amount, uint256 newBalance);
	event CompleteWithdraw(uint256 id);
	event CancelWithdraw(uint256 id, address user, address collateral, uint256 amount, uint256 newBalance);
	event ActivateInstantActionMode(address user, uint256 timestamp);
	event ProposeToDeactivateInstantActionMode(address user, uint256 timestamp);
	event DeactivateInstantActionMode(address user, uint256 timestamp);
	event BindToPartyB(address indexed partyA, address indexed partyB);
	event InitiateUnbindingFromPartyB(address indexed partyA, address indexed partyB, uint256 initiationTime);
	event CompleteUnbindingFromPartyB(address indexed partyA, address indexed partyB);
	event CancelUnbindingFromPartyB(address indexed partyA, address indexed partyB);
	event SyncBalances(address collateral, address partyA, address[] partyBs, uint256 newBalance);
	event Allocate(
		address indexed user,
		address indexed collateral,
		address indexed counterParty,
		uint256 amount,
		uint256 newBalance,
		int256 newAllocatedBalance
	);
	event Deallocate(
		address indexed user,
		address indexed collateral,
		address indexed counterParty,
		uint256 amount,
		uint256 newBalance,
		int256 newAllocatedBalance
	);

	event AllocateToReserveBalance(address user, address collateral, uint256 amount, uint256 newBalance);
	event DeallocateFromReserveBalance(address user, address collateral, uint256 amount, uint256 newBalance);
}
