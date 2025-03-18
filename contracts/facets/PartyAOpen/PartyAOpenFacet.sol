// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { OpenIntent, ExerciseFee, IntentStorage, TradeSide, MarginType, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyAOpenEvents } from "./IPartyAOpenEvents.sol";
import { IPartyAOpenFacet } from "./IPartyAOpenFacet.sol";
import { PartyAOpenFacetImpl } from "./PartyAOpenFacetImpl.sol";

contract PartyAOpenFacet is Accessibility, Pausable, IPartyAOpenFacet {
	using LibOpenIntentOps for OpenIntent;

	/**
	 * @notice Send a open intent to the protocol. The intent status will be pending.
	 * @param partyBsWhiteList List of party B addresses allowed to act on this intent.
	 * @param symbolId Each symbol within the system possesses a unique identifier, for instance, BTCUSDT carries its own distinct ID
	 * @param price This is the user-requested price that the user is willing to open a trade. For example, if the market price for an arbitrary symbol is $1000 and the user wants to
	 * 				open a trade on this symbol they might be ok with prices up to $1050
	 * @param quantity Size of the trade
	 * @param strikePrice The strike price for the options contract
	 * @param expirationTimestamp The expiration time for the options contract
	 * @param penalty The penalty that partyB would pay to partyA if it gets liquidated
	 * @param exerciseFee The exercise fee for the options contract during the exercise
	 * @param deadline The user should set a deadline for their request. If no PartyB takes action on the intent within this timeframe, the request will expire
	 * @param affiliate The affiliate of this intent
	 */
	function sendOpenIntent(
		address[] calldata partyBsWhiteList,
		uint256 symbolId,
		uint256 price,
		uint256 quantity,
		uint256 strikePrice,
		uint256 expirationTimestamp,
		uint256 penalty,
		TradeSide tradeSide,
		MarginType marginType,
		ExerciseFee memory exerciseFee,
		uint256 deadline,
		address feeToken,
		address affiliate,
		bytes memory userData
	) external whenNotPartyAActionsPaused notSuspended(msg.sender) returns (uint256 intentId) {
		intentId = PartyAOpenFacetImpl.sendOpenIntent(
			msg.sender,
			partyBsWhiteList,
			symbolId,
			price,
			quantity,
			strikePrice,
			expirationTimestamp,
			penalty,
			tradeSide,
			marginType,
			exerciseFee,
			deadline,
			feeToken,
			affiliate,
			userData
		);
		IntentStorage.layout().openIntents[intentId];
		emit SendOpenIntent(
			msg.sender,
			intentId,
			partyBsWhiteList,
			abi.encodePacked(
				symbolId,
				price,
				quantity,
				strikePrice,
				expirationTimestamp,
				penalty,
				tradeSide,
				marginType,
				exerciseFee.rate,
				exerciseFee.cap,
				deadline
			)
		);
	}

	/**
	 * @notice Expires the specified open intents.
	 * @param expiredIntentIds An array of IDs of the open intents to be expired.
	 */
	function expireOpenIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		for (uint256 i; i < expiredIntentIds.length; i++) {
			intentLayout.openIntents[expiredIntentIds[i]].expire();
			emit ExpireOpenIntent(expiredIntentIds[i]);
		}
	}

	/**
     * @notice Requests to cancel the specified open intent. Two scenarios can occur:
    		If the intent has not yet been locked, it will be immediately canceled.
    		For a locked intent, the outcome depends on PartyB's decision to either accept the cancellation request or to proceed with opening the trade, disregarding the request.
    		If PartyB agrees to cancel, the intent will no longer be accessible for others to interact with.
    		Conversely, if the position has been opened, the user is unable to issue this request.
     * @param intentIds The ID of the open intents to be canceled.
     */
	function cancelOpenIntent(uint256[] memory intentIds) external whenNotPartyAActionsPaused {
		for (uint256 i; i < intentIds.length; i++) {
			IntentStatus result = PartyAOpenFacetImpl.cancelOpenIntent(msg.sender, intentIds[i]);
			OpenIntent memory intent = IntentStorage.layout().openIntents[intentIds[i]];

			if (result == IntentStatus.EXPIRED) {
				emit ExpireOpenIntent(intent.id);
			} else if (result == IntentStatus.CANCELED || result == IntentStatus.CANCEL_PENDING) {
				emit CancelOpenIntent(intent.partyA, intent.partyB, result, intent.id);
			}
		}
	}
}
