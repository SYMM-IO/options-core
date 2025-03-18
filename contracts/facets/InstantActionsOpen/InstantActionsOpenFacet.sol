// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { SignedFillIntentById, OpenIntent, IntentStorage, SignedSimpleActionIntent, IntentStatus, SignedOpenIntent, SignedFillIntent } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyAOpenEvents } from "../PartyAOpen/IPartyAOpenEvents.sol";
import { IPartyBOpenEvents } from "../PartyBOpen/IPartyBOpenEvents.sol";
import { IInstantActionsOpenFacet } from "./IInstantActionsOpenFacet.sol";
import { InstantActionsOpenFacetImpl } from "./InstantActionsOpenFacetImpl.sol";

contract InstantActionsOpenFacet is Accessibility, Pausable, IInstantActionsOpenFacet {
	/// @notice Any party can fill the existing open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedFillOpenIntent The pure data of signature that partyB wants to fill the open order
	/// @param partyBSignature The signature of partyB
	function instantFillOpenIntent(
		SignedFillIntentById calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsOpenFacetImpl.instantFillOpenIntent(signedFillOpenIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[signedFillOpenIntent.intentId];
		emit FillOpenIntent(intent.id, intent.tradeId, intent.partyA, intent.partyB, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	/// @notice Any party can lock an open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedLockIntent The pure data of intent that is going to be locked
	/// @param partyBSignature The signature of partyB
	function instantLock(
		SignedSimpleActionIntent calldata signedLockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsOpenFacetImpl.instantLock(signedLockIntent, partyBSignature);
		OpenIntent storage intent = IntentStorage.layout().openIntents[signedLockIntent.intentId];
		emit LockOpenIntent(intent.partyB, signedLockIntent.intentId);
	}

	/// @notice Any party can unlock an open intent on behalf of partyB if it has the suitable signature from the partyB
	/// @param signedUnlockIntent The pure data of intent that is going to be unlocked
	/// @param partyBSignature The signature of partyB
	function instantUnlock(
		SignedSimpleActionIntent calldata signedUnlockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus res = InstantActionsOpenFacetImpl.instantUnlock(signedUnlockIntent, partyBSignature);
		if (res == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedUnlockIntent.intentId);
		} else if (res == IntentStatus.PENDING) {
			emit UnlockOpenIntent(signedUnlockIntent.signer, signedUnlockIntent.intentId);
		}
	}

	/// @notice Any party can fill an open intent on behalf of partyB if it has the suitable signature from the partyB and partyA
	/// @param signedOpenIntent The pure data of intent that partyA wants to broadcast
	/// @param partyASignature The signature of partyA
	/// @param signedFillOpenIntent The pure data of signature that partyB wants to fill the open order
	/// @param partyBSignature The signature of partyB
	function instantCreateAndFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		uint256 intentId = InstantActionsOpenFacetImpl.instantCreateAndFillOpenIntent(
			signedOpenIntent,
			partyASignature,
			signedFillOpenIntent,
			partyBSignature
		);
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		emit SendOpenIntent(
			intent.partyA,
			intent.id,
			intent.partyBsWhiteList,
			abi.encodePacked(
				intent.tradeAgreements.symbolId,
				intent.price,
				intent.tradeAgreements.quantity,
				intent.tradeAgreements.strikePrice,
				intent.tradeAgreements.expirationTimestamp,
				intent.tradeAgreements.penalty,
				intent.tradeAgreements.tradeSide,
				intent.tradeAgreements.marginType,
				intent.tradeAgreements.exerciseFee.rate,
				intent.tradeAgreements.exerciseFee.cap,
				intent.deadline
			)
		);
		emit FillOpenIntent(intent.id, intent.tradeId, intent.partyA, intent.partyB, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
	}

	/// @notice Any party can cancel an open intent on behalf of parties if it has the suitable signature from the partyB and partyA
	/// @param signedCancelOpenIntent The pure data of open intent that partyA wants to cancel
	/// @param partyASignature The signature of partyA
	/// @param signedAcceptCancelOpenIntent The pure data of signature that partyB wants to accept the cancel open intent
	/// @param partyBSignature The signature of partyB
	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus result = InstantActionsOpenFacetImpl.instantCancelOpenIntent(
			signedCancelOpenIntent,
			partyASignature,
			signedAcceptCancelOpenIntent,
			partyBSignature
		);
		OpenIntent memory intent = IntentStorage.layout().openIntents[signedCancelOpenIntent.intentId];
		if (result == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(intent.id);
		} else if (result == IntentStatus.CANCELED) {
			emit CancelOpenIntent(intent.partyA, intent.partyB, result, intent.id);
		}
	}
}
