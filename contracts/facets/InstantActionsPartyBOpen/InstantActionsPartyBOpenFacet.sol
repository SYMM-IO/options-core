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

import { IInstantActionsPartyBOpenFacet } from "./IInstantActionsPartyBOpenFacet.sol";
import { InstantActionsPartyBOpenFacetImpl } from "./InstantActionsPartyBOpenFacetImpl.sol";

/**
 * @title InstantActionsOpenFacet
 * @notice Enables meta-transaction functionality for open intent operations
 * @dev Allows third parties to execute actions on behalf of PartyA and PartyB using cryptographic signatures
 *      This facilitates gas-efficient operations and improves UX by allowing actions to be performed
 *      without requiring direct blockchain interaction from either party
 */
contract InstantActionsPartyBOpenFacet is Accessibility, Pausable, IInstantActionsPartyBOpenFacet {
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
		InstantActionsPartyBOpenFacetImpl.instantLock(signedLockIntent, partyBSignature);
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
		IntentStatus finalStatus = InstantActionsPartyBOpenFacetImpl.instantUnlock(signedUnlockIntent, partyBSignature);
		if (finalStatus == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(signedUnlockIntent.intentId);
		} else if (finalStatus == IntentStatus.PENDING) {
			emit UnlockOpenIntent(signedUnlockIntent.intentId);
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
		(uint256 tradeId, uint256 newIntentId) = InstantActionsPartyBOpenFacetImpl.instantFillOpenIntent(signedFillOpenIntent, partyBSignature);
		emit FillOpenIntent(signedFillOpenIntent.intentId, tradeId, signedFillOpenIntent.quantity, signedFillOpenIntent.price);
		if (newIntentId != 0) {
			OpenIntent storage newIntent = OpenIntentStorage.layout().openIntents[newIntentId];
			emit SendOpenIntent(
				newIntent.partyA,
				newIntent.id,
				newIntent.partyBsWhiteList,
				abi.encodePacked(
					newIntent.tradeAgreements.symbolId,
					newIntent.price,
					newIntent.tradeAgreements.quantity,
					newIntent.tradeAgreements.strikePrice,
					newIntent.tradeAgreements.expirationTimestamp,
					newIntent.tradeAgreements.mm,
					newIntent.tradeAgreements.tradeSide,
					newIntent.tradeAgreements.marginType,
					newIntent.tradeAgreements.exerciseFee.rate,
					newIntent.tradeAgreements.exerciseFee.cap,
					newIntent.deadline
				)
			);
			if (newIntent.status == IntentStatus.CANCELED) {
				emit CancelOpenIntent(newIntentId, IntentStatus.CANCEL_PENDING);
				emit AcceptCancelOpenIntent(newIntent.id);
			}
		}
	}
}
