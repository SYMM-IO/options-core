// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IInstantActionsEvents.sol";

interface IInstantActionsFacet is IInstantActionsEvents {
	function instantFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyAAignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external;

	function instantFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external;

	function instantCancelOpenIntent(
		SignedCancelIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external;

	function instantCancelCloseIntent(
		SignedCancelIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedCancelIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external;

	// TODO: add revert backs 1. revert back close intent 2. revert back withdraw or send alot of open intent
}
