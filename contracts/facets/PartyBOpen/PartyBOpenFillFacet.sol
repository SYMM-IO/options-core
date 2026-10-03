// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";

import { OpenIntent, OpenIntentStatus } from "../../types/IntentTypes.sol";

import { Pausable } from "../../utils/Pausable.sol";
import { Accessibility } from "../../utils/Accessibility.sol";

import { IPartyBOpenEvents } from "./IPartyBOpenEvents.sol";
import { LibPartyBOpen } from "../../libraries/core/LibPartyBOpen.sol";

/**
 * @title PartyBOpenFacet
 * @notice Manages PartyB's interactions with open intents submitted by PartyA users
 * @dev Implements the IPartyBOpenEvents interface with access control and pausability mechanisms
 */
contract PartyBOpenFillFacet is Accessibility, Pausable, IPartyBOpenEvents {
	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) external whenPartyNotPaused(msg.sender) {
		(uint256 tradeId, uint256 newIntentId) = LibPartyBOpen.fillOpenIntent(msg.sender, intentId, quantity, price);
		emit FillOpenIntent(intentId, tradeId, quantity, price);
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
			if (newIntent.status == OpenIntentStatus.CANCELED) {
				emit CancelOpenIntent(newIntent.id, OpenIntentStatus.CANCELED);
			}
		}
	}
}
