// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IAccountEvents {
	event Deposit(address sender, address user, address collateral, uint256 amount, uint256 newBalance);
	event InitiateWithdraw(uint256 id, address user, address to, address collateral, uint256 amount, uint256 newBalance);
	event CompleteWithdraw(uint256 id);
	event CancelWithdraw(uint256 id, address user, uint256 newBalance);
	event ActivateInstantActionMode(address user, uint256 timestamp);
	event ProposeToDeactivateInstantActionMode(address user, uint256 timestamp);
	event DeactivateInstantActionMode(address user, uint256 timestamp);
}
