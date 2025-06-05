// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IInstantActionsAccountEvents } from "./IInstantActionsAccountEvents.sol";
import { SignedInternalTransfer, SignedWithdraw } from "../../types/SignedAccountTypes.sol";

interface IInstantActionsAccountFacet is IInstantActionsAccountEvents {
	function instantInternalTransfer(
		SignedInternalTransfer calldata signedInternalTransferRequest,
		bytes calldata partyASignature,
		SignedInternalTransfer calldata signedInternalTransferAcceptance,
		bytes calldata partyBSignature
	) external;

	function instantInitiateWithdraw(
		SignedWithdraw calldata signedWithdrawRequest,
		bytes calldata partyASignature,
		SignedWithdraw calldata signedWithdrawAcceptance,
		bytes calldata partyBSignature
	) external returns (uint256 withdrawId);
}
