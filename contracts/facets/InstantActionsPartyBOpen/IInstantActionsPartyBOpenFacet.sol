// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { SignedFillIntentById, SignedOpenIntent, SignedFillIntent, SignedSimpleActionIntent } from "../../types/SignedIntentTypes.sol";

import { IInstantActionsPartyBOpenEvents } from "./IInstantActionsPartyBOpenEvents.sol";

interface IInstantActionsPartyBOpenFacet is IInstantActionsPartyBOpenEvents {
	function instantLock(SignedSimpleActionIntent calldata signedLockIntent, bytes calldata partyBSignature) external;

	function instantUnlock(SignedSimpleActionIntent calldata signedUnlockIntent, bytes calldata partyBSignature) external;

	function instantFillOpenIntent(SignedFillIntentById calldata signedFillOpenIntent, bytes calldata partyBSignature) external;
}
