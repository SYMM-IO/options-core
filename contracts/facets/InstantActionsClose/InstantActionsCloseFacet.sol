// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { SignedFillIntentById, CloseIntent, IntentStorage, Trade, SignedCloseIntent, SignedFillIntent, SignedSimpleActionIntent, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyACloseEvents } from "../PartyAClose/IPartyACloseEvents.sol";
import { IPartyBCloseEvents } from "../PartyBClose/IPartyBCloseEvents.sol";
import { IInstantActionsCloseFacet } from "./IInstantActionsCloseFacet.sol";
import { InstantActionsCloseFacetImpl } from "./InstantActionsCloseFacetImpl.sol";

contract InstantActionsCloseFacet is Accessibility, Pausable, IInstantActionsCloseFacet {
	/// @notice Any party can close a trade on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedFillCloseIntent The pure data of signature that partyB wants to fill the close order
	/// @param partyBSignature The signature of partyB
	function instantFillCloseIntent(
		SignedFillIntentById calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsCloseFacetImpl.instantFillCloseIntent(signedFillCloseIntent, partyBSignature);
		CloseIntent storage intent = IntentStorage.layout().closeIntents[signedFillCloseIntent.intentId];
		Trade storage trade = IntentStorage.layout().trades[intent.tradeId];
		emit FillCloseIntent(intent.id, trade.id, trade.partyA, trade.partyB, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
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
		Trade storage trade = IntentStorage.layout().trades[signedCloseIntent.tradeId];
		emit SendCloseIntent(
			trade.partyA,
			trade.partyB,
			trade.id,
			intentId,
			signedFillCloseIntent.price,
			signedFillCloseIntent.quantity,
			signedCloseIntent.deadline,
			IntentStatus.PENDING
		);
		emit FillCloseIntent(intentId, trade.id, trade.partyA, trade.partyB, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

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
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		IntentStatus result = InstantActionsCloseFacetImpl.instantCancelCloseIntent(
			signedCancelCloseIntent,
			partyASignature,
			signedAcceptCancelCloseIntent,
			partyBSignature
		);
		Trade memory trade = intentLayout.trades[intentLayout.closeIntents[signedCancelCloseIntent.intentId].tradeId];
		if (result == IntentStatus.EXPIRED) {
			emit ExpireCloseIntent(signedCancelCloseIntent.intentId);
		} else if (result == IntentStatus.CANCEL_PENDING) {
			emit CancelCloseIntent(trade.partyA, trade.partyB, signedCancelCloseIntent.intentId);
		}
	}
}
