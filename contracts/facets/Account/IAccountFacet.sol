// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType } from "../../types/BaseTypes.sol";
import { UpnlSig } from "../../types/WithdrawTypes.sol";

import { IAccountEvents } from "./IAccountEvents.sol";

interface IAccountFacet is IAccountEvents {
	function deposit(address collateral, uint256 amount) external;

	function securedDepositFor(address collateral, address user, uint256 amount) external;

	function depositFor(address collateral, address user, uint256 amount) external;

	function internalTransfer(address collateral, address user, uint256 amount) external;

	function initiateWithdraw(address collateral, uint256 amount, address to) external;

	function completeWithdraw(uint256 id) external;

	function cancelWithdraw(uint256 id) external;

	function activateInstantActionMode() external;

	function proposeToDeactivateInstantActionMode() external;

	function deactivateInstantActionMode() external;

	function bindToPartyB(address partyB) external;

	function initiateUnbindingFromPartyB() external;

	function completeUnbindingFromPartyB() external;

	function cancelUnbindingFromPartyB() external;

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external;

	function allocate(address collateral, address counterParty, uint256 amount) external;

	function deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig memory upnlSig) external;

	function allocateToReserveBalance(address collateral, uint256 amount) external;

	function deallocateFromReserveBalance(address collateral, uint256 amount) external;
}
