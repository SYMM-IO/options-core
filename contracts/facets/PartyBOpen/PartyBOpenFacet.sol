// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { OpenIntent, IntentStorage, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyBOpenEvents } from "./IPartyBOpenEvents.sol";
import { IPartyBOpenFacet } from "./IPartyBOpenFacet.sol";
import { PartyBOpenFacetImpl } from "./PartyBOpenFacetImpl.sol";

contract PartyBOpenFacet is Accessibility, Pausable, IPartyBOpenFacet {
	/**
	 * @notice Once a user issues a open intent, any PartyB can secure it, based on their estimated profit and loss from opening the trade.
	 * @param intentId The ID of the open intent to be locked.
	 */
	function lockOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyB {
		PartyBOpenFacetImpl.lockOpenIntent(msg.sender, intentId);
		emit LockOpenIntent(intentId, msg.sender);
	}

	/**
	 * @notice Unlocks the specified open intent.
	 * @param intentId The ID of the open intent to be unlocked.
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
	 * @notice Accepts the cancellation request for the specified open intent.
	 * @param intentId The ID of the open intent for which the cancellation request is accepted.
	 */
	function acceptCancelOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused {
		PartyBOpenFacetImpl.acceptCancelOpenIntent(msg.sender, intentId);
		emit AcceptCancelOpenIntent(intentId);
	}

	/**
	 * @notice Opens a trade for the specified open intent.
	 * @param intentId The ID of the open intent for which the trade is opened.
	 * @param quantity PartyB has the option to open the position with either the full amount requested by the user or a specific fraction of it
	 * @param price The opened price for the trade.
	 */
	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) external whenNotPartyBActionsPaused {
		(uint256 tradeId, uint256 newIntentId) = PartyBOpenFacetImpl.fillOpenIntent(msg.sender, intentId, quantity, price);
		emit FillOpenIntent(intentId, tradeId, quantity, price);
		if (newIntentId != 0) {
			OpenIntent storage newIntent = IntentStorage.layout().openIntents[newIntentId];
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
						newIntent.tradeAgreements.penalty,
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
