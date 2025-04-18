// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { MarginType } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibOpenIntentOps } from "../../libraries/LibOpenIntent.sol";
import { OpenIntent, ExerciseFee, IntentStorage, TradeSide, IntentStatus, TradeAgreements } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyAOpenEvents } from "./IPartyAOpenEvents.sol";
import { IPartyAOpenFacet } from "./IPartyAOpenFacet.sol";
import { PartyAOpenFacetImpl } from "./PartyAOpenFacetImpl.sol";

/**
 * @title PartyAOpenFacet
 * @notice Manages open intent creation and lifecycle actions for PartyA users
 * @dev Implements the IPartyAOpenFacet interface with access control and pausability
 */
contract PartyAOpenFacet is Accessibility, Pausable, IPartyAOpenFacet {
	using LibOpenIntentOps for OpenIntent;

	/**
	 * @notice Creates and submits a new open intent to the protocol
	 * @dev The intent status will be set to PENDING upon creation. Only non-suspended users with inactive instant mode can call this function.
	 * @param partyBsWhiteList List of PartyB addresses allowed to act on this intent
	 * @param symbolId Unique identifier for the trading symbol (e.g., BTCUSDT)
	 * @param price The maximum price at which PartyA is willing to open the trade
	 * @param quantity Size of the trade in base units
	 * @param strikePrice The strike price for the options contract
	 * @param expirationTimestamp The timestamp when the options contract expires
	 * @param penalty The amount PartyB would pay to PartyA if the position gets liquidated
	 * @param tradeSide Direction of the trade (LONG or SHORT)
	 * @param marginType Type of margin used for the trade (e.g., ISOLATED, CROSS)
	 * @param exerciseFee The fee structure applied during option exercise
	 * @param deadline Timestamp after which the intent expires if no PartyB takes action
	 * @param feeToken The token used for paying fees related to this trade
	 * @param affiliate The affiliate address for this trade, if any
	 * @param userData Additional user-defined data to be stored with the intent
	 * @return intentId The unique identifier for the newly created open intent
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
	) external whenNotPartyAActionsPaused inactiveInstantMode(msg.sender) returns (uint256 intentId) {
		intentId = PartyAOpenFacetImpl.sendOpenIntent(
			msg.sender,
			partyBsWhiteList,
			TradeAgreements({
				symbolId: symbolId,
				quantity: quantity,
				strikePrice: strikePrice,
				expirationTimestamp: expirationTimestamp,
				penalty: penalty,
				tradeSide: tradeSide,
				marginType: marginType,
				exerciseFee: exerciseFee
			}),
			price,
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
	 * @notice Expires multiple open intents that have reached their deadline
	 * @dev This function transitions intents to EXPIRED state and can be called by anyone when PartyA actions are not paused
	 * @param expiredIntentIds Array of intent IDs to be marked as expired
	 */
	function expireOpenIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		for (uint256 i; i < expiredIntentIds.length; i++) {
			intentLayout.openIntents[expiredIntentIds[i]].expire();
			emit ExpireOpenIntent(expiredIntentIds[i]);
		}
	}

	/**
	 * @notice Initiates cancellation requests for specified open intents
	 * @dev The outcome depends on the current state of each intent:
	 *      - For unlocked intents: Immediate cancellation (CANCELED state)
	 *      - For locked intents: Pending cancellation (CANCEL_PENDING state) awaiting PartyB's decision
	 *      - For opened positions: Cancellation not possible
	 * @param intentIds Array of intent IDs to be canceled
	 */
	function cancelOpenIntent(uint256[] memory intentIds) external whenNotPartyAActionsPaused inactiveInstantMode(msg.sender) {
		for (uint256 i; i < intentIds.length; i++) {
			IntentStatus result = PartyAOpenFacetImpl.cancelOpenIntent(msg.sender, intentIds[i]);

			if (result == IntentStatus.EXPIRED) {
				emit ExpireOpenIntent(intentIds[i]);
			} else if (result == IntentStatus.CANCELED || result == IntentStatus.CANCEL_PENDING) {
				emit CancelOpenIntent(intentIds[i], result);
			}
		}
	}
}
