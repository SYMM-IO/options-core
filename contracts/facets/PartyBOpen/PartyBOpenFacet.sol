// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { OpenIntent, IntentStatus } from "../../types/IntentTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IPartyBOpenFacet } from "./IPartyBOpenFacet.sol";
import { PartyBOpenFacetImpl } from "./PartyBOpenFacetImpl.sol";

/**
 * @title PartyBOpenFacet
 * @notice Manages PartyB's interactions with open intents submitted by PartyA users
 * @dev Implements the IPartyBOpenFacet interface with access control and pausability mechanisms
 */
contract PartyBOpenFacet is Accessibility, Pausable, IPartyBOpenFacet {
	/**
	 * @notice Allows PartyB to reserve an open intent for fulfillment
	 * @dev Temporarily locks the intent to prevent other PartyBs from acting on it
	 * @param intentId The unique identifier of the open intent to be locked
	 */
	function lockOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyB {
		PartyBOpenFacetImpl.lockOpenIntent(msg.sender, intentId);
		emit LockOpenIntent(intentId, msg.sender);
	}

	/**
	 * @notice Releases a previously locked open intent, making it available again
	 * @dev The intent may be marked as expired if its deadline has passed or returned to pending state
	 *      Only the PartyB who locked the intent can unlock it
	 * @param intentId The unique identifier of the open intent to be unlocked
	 */
	function unlockOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused {
		IntentStatus finalStatus = PartyBOpenFacetImpl.unlockOpenIntent(msg.sender, intentId);
		if (finalStatus == IntentStatus.EXPIRED) {
			emit ExpireOpenIntent(intentId);
		} else if (finalStatus == IntentStatus.PENDING) {
			emit UnlockOpenIntent(intentId);
		}
	}

	/**
	 * @notice Approves a cancellation request initiated by PartyA for an open intent
	 * @dev This can only be called by the PartyB who locked the intent
	 *      Once accepted, the intent will be marked as canceled
	 * @param intentId The unique identifier of the open intent for which the cancellation is being accepted
	 */
	function acceptCancelOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused {
		PartyBOpenFacetImpl.acceptCancelOpenIntent(msg.sender, intentId);
		emit AcceptCancelOpenIntent(intentId);
	}

	/**
	 * @notice Opens a trade based on a previously submitted open intent
	 * @dev Creates a new trade record and potentially a new intent for any unfilled quantity
	 *      The price must be favorable to PartyA compared to their requested price
	 *      Only the PartyB who locked the intent can fill it
	 * @param intentId The unique identifier of the open intent to be filled
	 * @param quantity The amount to be filled, which can be equal to or less than the original requested quantity
	 * @param price The price at which the trade is being opened
	 */
	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price, MarginType marginType) external whenNotPartyBActionsPaused {
		(uint256 tradeId, uint256 newIntentId) = PartyBOpenFacetImpl.fillOpenIntent(msg.sender, marginType, intentId, quantity, price);
		emit FillOpenIntent(intentId, tradeId, quantity, price, marginType);
		if (newIntentId != 0) {
			OpenIntent storage newIntent = OpenIntentStorage.layout().openIntents[newIntentId];
			if (newIntent.status == IntentStatus.PENDING) {
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
			} else if (newIntent.status == IntentStatus.CANCELED) {
				emit AcceptCancelOpenIntent(newIntent.id);
			}
		}
	}
}
