// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { SignedFillIntentById, SignedSimpleActionIntent, SignedOpenIntent, SignedFillIntent } from "../../types/SignedIntentTypes.sol";
import { OpenIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { IPartyAOpenEvents } from "../PartyAOpen/IPartyAOpenEvents.sol";
import { IPartyBOpenEvents } from "../PartyBOpen/IPartyBOpenEvents.sol";
import { IInstantActionsOpenFacet } from "./IInstantActionsOpenFacet.sol";
import { InstantActionsOpenFacetImpl } from "./InstantActionsOpenFacetImpl.sol";

/**
 * @title InstantActionsOpenFacet
 * @notice Enables meta-transaction functionality for open intent operations
 * @dev Allows third parties to execute actions on behalf of PartyA and PartyB using cryptographic signatures
 *      This facilitates gas-efficient operations and improves UX by allowing actions to be performed
 *      without requiring direct blockchain interaction from either party
 */
contract InstantActionsOpenFacet is Accessibility, Pausable, IInstantActionsOpenFacet {
	/**
	 * @notice Locks an open intent on behalf of PartyB using their cryptographic signature
	 * @dev Verifies the signature against the provided intent data before executing the lock
	 *      Equivalent to PartyB calling lockOpenIntent directly but can be executed by anyone
	 * @param signedLockIntent The intent data structure containing the intent ID
	 * @param partyBSignature Cryptographic signature from PartyB authorizing this action
	 */
	function instantLock(
		SignedSimpleActionIntent calldata signedLockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsOpenFacetImpl.instantLock(signedLockIntent, partyBSignature);
		emit LockOpenIntent(signedLockIntent.intentId, signedLockIntent.signer);
	}

	/**
	 * @notice Unlocks a previously locked open intent on behalf of PartyB using their signature
	 * @dev Verifies the signature before executing the unlock action
	 *      The intent may transition to EXPIRED or PENDING state depending on its deadline
	 * @param signedUnlockIntent The intent data structure containing the intent ID
	 * @param partyBSignature Cryptographic signature from PartyB authorizing this action
	 */
	function instantUnlock(
		SignedSimpleActionIntent calldata signedUnlockIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus finalStatus = InstantActionsOpenFacetImpl.instantUnlock(signedUnlockIntent, partyBSignature);
		if (finalStatus == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedUnlockIntent.intentId);
		} else if (finalStatus == IntentStatus.PENDING) {
			emit UnlockOpenIntent(signedUnlockIntent.intentId);
		}
	}

	/**
	 * @notice Cancels an open intent using signatures from both PartyA and PartyB
	 * @dev Requires signatures from both parties to execute the cancellation in a single transaction
	 *      This atomic operation replaces the two-step process of PartyA requesting cancellation
	 *      and PartyB accepting it (partyB signature is not needed if quote is not locked)
	 * @param signedCancelOpenIntent The intent data for PartyA's cancellation request
	 * @param partyASignature Cryptographic signature from PartyA authorizing cancellation
	 * @param signedAcceptCancelOpenIntent The intent data for PartyB's acceptance of cancellation
	 * @param partyBSignature Cryptographic signature from PartyB authorizing acceptance
	 */
	function instantCancelOpenIntent(
		SignedSimpleActionIntent calldata signedCancelOpenIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus finalStatus = InstantActionsOpenFacetImpl.instantCancelOpenIntent(
			signedCancelOpenIntent,
			partyASignature,
			signedAcceptCancelOpenIntent,
			partyBSignature
		);
		if (finalStatus == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedCancelOpenIntent.intentId);
		} else if (finalStatus == IntentStatus.CANCELED) {
			emit CancelOpenIntent(signedCancelOpenIntent.intentId, IntentStatus.CANCELED);
		}
	}

	/**
	 * @notice Fills an existing open intent on behalf of PartyB using their signature
	 * @dev Executes the trade creation based on the intent and PartyB's signed parameters
	 *      May create a new intent for any unfilled quantity (partial fill)
	 * @param signedFillOpenIntent The fill data including intent ID, quantity, and price
	 * @param partyBSignature Cryptographic signature from PartyB authorizing the fill
	 */
	function instantFillOpenIntent(
		SignedFillIntentById calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		(uint256 tradeId, uint256 newIntentId) = InstantActionsOpenFacetImpl.instantFillOpenIntent(signedFillOpenIntent, partyBSignature);
		emit FillOpenIntent(
			signedFillOpenIntent.intentId,
			tradeId,
			signedFillOpenIntent.quantity,
			signedFillOpenIntent.price,
			signedFillOpenIntent.marginType
		);
		if (newIntentId != 0) {
			OpenIntent storage newIntent = OpenIntentStorage.layout().openIntents[newIntentId];
			_emitSendOpenIntent(newIntent);
			if (newIntent.status == IntentStatus.CANCELED) {
				emit CancelOpenIntent(newIntentId, IntentStatus.CANCEL_PENDING);
				emit AcceptCancelOpenIntent(newIntent.id);
			}
		}
	}

	/**
	 * @notice Creates and fills an open intent in a single transaction
	 * @dev Combines the creation of an intent by PartyA and its immediate lock and filling by PartyB
	 *      All actions are authorized through signatures, allowing execution by any third party
	 * @param signedOpenIntent The complete open intent data structure from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing intent creation
	 * @param signedFillOpenIntent The fill parameters from PartyB (quantity and price)
	 * @param partyBSignature Cryptographic signature from PartyB authorizing the fill
	 */
	function instantCreateAndFillOpenIntent(
		SignedOpenIntent calldata signedOpenIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillOpenIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		(uint256 intentId, uint256 tradeId, uint256 newIntentId) = InstantActionsOpenFacetImpl.instantCreateAndFillOpenIntent(
			signedOpenIntent,
			partyASignature,
			signedFillOpenIntent,
			partyBSignature
		);
		OpenIntent storage intent = OpenIntentStorage.layout().openIntents[intentId];
		_emitSendOpenIntent(intent);
		emit FillOpenIntent(intent.id, tradeId, signedFillOpenIntent.quantity, signedFillOpenIntent.price, signedFillOpenIntent.marginType);
		if (newIntentId != 0) {
			_emitSendOpenIntent(OpenIntentStorage.layout().openIntents[newIntentId]);
		}
	}

	/**
	 * @notice Helper function to emit the SendOpenIntent event with all required parameters
	 * @dev Extracts all necessary data from the OpenIntent struct and packs it for the event
	 * @param intent Reference to the OpenIntent storage struct containing the intent data
	 */
	function _emitSendOpenIntent(OpenIntent storage intent) private {
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
				intent.tradeAgreements.mm,
				intent.tradeAgreements.tradeSide,
				intent.tradeAgreements.marginType,
				intent.tradeAgreements.exerciseFee.rate,
				intent.tradeAgreements.exerciseFee.cap,
				intent.deadline
			)
		);
	}
}
