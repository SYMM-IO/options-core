// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { SignedFillIntentById, CloseIntent, IntentStorage, Trade, SignedCloseIntent, SignedFillIntent, SignedSimpleActionIntent, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyACloseEvents } from "../PartyAClose/IPartyACloseEvents.sol";
import { IPartyBCloseEvents } from "../PartyBClose/IPartyBCloseEvents.sol";
import { IInstantActionsCloseFacet } from "./IInstantActionsCloseFacet.sol";
import { InstantActionsCloseFacetImpl } from "./InstantActionsCloseFacetImpl.sol";

contract InstantActionsCloseFacet is Accessibility, Pausable, IInstantActionsCloseFacet {
	/// @notice Any party can cancel a close intent on behalf of parties if it has the suitable signature from the partyB and partyA
	/// @param signedCancelCloseIntent The pure data of close intent that partyA wants to cancel
	/// @param partyASignature The signature of partyA
	/// @param signedAcceptCancelCloseIntent The pure data of signature that partyB wants to accept the cancel close intent
	/// @param partyBSignature The signature of partyB
	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus result = InstantActionsCloseFacetImpl.instantCancelCloseIntent(
			signedCancelCloseIntent,
			partyASignature,
			signedAcceptCancelCloseIntent,
			partyBSignature
		);
		if (result == IntentStatus.EXPIRED) {
			emit ExpireCloseIntent(signedCancelCloseIntent.intentId);
		} else {
			emit CancelCloseIntent(signedCancelCloseIntent.intentId);
		}
	}

	/// @notice Any party can close a trade on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedFillCloseIntent The pure data of signature that partyB wants to fill the close order
	/// @param partyBSignature The signature of partyB
	function instantFillCloseIntent(
		SignedFillIntentById calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsCloseFacetImpl.instantFillCloseIntent(signedFillCloseIntent, partyBSignature);
		emit FillCloseIntent(signedFillCloseIntent.intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	/// @notice Any party can close a trade on behalf of partyB if it has the suitable signature from the partyB and partyA
	/// @param signedCloseIntent The pure data of close intent that partyA wants to broadcast
	/// @param partyASignature The signature of partyA
	/// @param signedFillCloseIntent The pure data of signature that partyB wants to fill the close order
	/// @param partyBSignature The signature of partyB
	function instantCreateAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		uint256 intentId = InstantActionsCloseFacetImpl.instantCreateAndFillCloseIntent(
			signedCloseIntent,
			partyASignature,
			signedFillCloseIntent,
			partyBSignature
		);
		emit SendCloseIntent(
			signedCloseIntent.tradeId,
			intentId,
			signedFillCloseIntent.price,
			signedFillCloseIntent.quantity,
			signedCloseIntent.deadline
		);
		emit FillCloseIntent(intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}
}
