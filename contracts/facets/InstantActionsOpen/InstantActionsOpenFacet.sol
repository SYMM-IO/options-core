// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";

import { OpenIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { SignedFillIntentById, SignedSimpleActionIntent, SignedOpenIntent, SignedFillIntent } from "../../types/SignedIntentTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

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
		emit FillOpenIntent(intent.id, tradeId, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
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
