// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { BucketRef } from "../../types/BucketTypes.sol";

import { UpnlSig } from "../../types/WithdrawTypes.sol";

import { IAccountEvents } from "./IAccountEvents.sol";

interface IAccountFacet is IAccountEvents {
	function deposit(address collateral, uint256 amount) external;

	function virtualDepositFor(address collateral, address user, uint256 amount) external;

	function depositFor(address collateral, address user, uint256 amount) external;

	function internalTransfer(address collateral, address user, uint256 amount) external;

	function initiateWithdraw(address collateral, uint256 amount, address to) external;

	function completeWithdraw(uint256 id) external;

	function cancelWithdraw(uint256 id) external;

	function syncBalances(address collateral, address partyA, address[] calldata partyBs) external;

	function allocate(address collateral, address counterParty, uint256 amount) external;

	function deallocate(address collateral, address counterParty, uint256 amount, bool isPartyB, UpnlSig memory upnlSig) external;

	function allocateToReserveBalance(address collateral, uint256 amount) external;

	function deallocateFromReserveBalance(address collateral, uint256 amount) external;

	function deposit(uint256 bucketId, address collateral, uint256 amount) external;
	function depositFor(uint256 bucketId, address collateral, address user, uint256 amount) external;
	function internalTransfer(uint256 bucketId, address collateral, address user, uint256 userBucketId, uint256 amount) external;
	function initiateWithdraw(uint256 bucketId, address collateral, uint256 amount, address to) external;
	function syncBalances(address collateral, address owner, uint256 bucketId, BucketRef[] calldata counterparties) external;
	function allocate(uint256 bucketId, address collateral, address cp, uint256 cpBucketId, uint256 amount) external;
	function deallocate(
		uint256 bucketId,
		address collateral,
		address cp,
		uint256 cpBucketId,
		uint256 amount,
		bool isPartyB,
		UpnlSig memory sig
	) external;
	function allocateToReserveBalance(uint256 bucketId, address collateral, uint256 amount) external;
	function deallocateFromReserveBalance(uint256 bucketId, address collateral, uint256 amount) external;

	function virtualDepositFor(uint256 bucketId, address collateral, address user, uint256 amount) external;
	function externalTransfer(uint256 bucketId, address collateral, address user, uint256 amount, address target) external;
	function initiateExpressWithdraw(
		uint256 bucketId,
		address collateral,
		uint256 amount,
		address to,
		address provider,
		bytes memory userData
	) external;

	function externalTransfer(address collateral, address user, uint256 amount, address target) external;
	function initiateExpressWithdraw(address collateral, uint256 amount, address to, address provider, bytes memory userData) external;
	function suspendWithdraw(uint256 id) external;
	function restoreWithdraw(uint256 id, uint256 validAmount) external;
}
