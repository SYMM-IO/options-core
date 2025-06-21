// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

library AccessibilityErrors {
	error NotPartyB(address sender);
	error UserIsPartyB(address user);
	error MissingRole(address sender, bytes32 role);
	error NotPartyAOfTrade(address sender, uint256 tradeId, address partyA);
	error NotPartyBOfTrade(address sender, uint256 tradeId, address partyB);
	error UserSuspended(address user);
	error ReceiverSuspended(address receiver);
	error SuspendedWithdrawal(uint256 withdrawId);
	error InstantModeActive(address sender);
	error InstantActionModeNotActive(address sender);
}
