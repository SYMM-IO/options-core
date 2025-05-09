// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SignedFillIntentById, SignedCloseIntent, SignedFillIntent, SignedSimpleActionIntent } from "../../types/SignedIntentTypes.sol";

import { IInstantActionsCloseEvents } from "./IInstantActionsCloseEvents.sol";

interface IInstantActionsCloseFacet is IInstantActionsCloseEvents {
	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external;

	function instantFillCloseIntent(SignedFillIntentById calldata signedFillCloseIntent, bytes calldata partyBSignature) external;

	function instantCreateAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external;
}
