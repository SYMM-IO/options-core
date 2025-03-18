// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Trade, IntentStorage } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyBCloseEvents } from "./IPartyBCloseEvents.sol";
import { IPartyBCloseFacet } from "./IPartyBCloseFacet.sol";
import { PartyBCloseFacetImpl } from "./PartyBCloseFacetImpl.sol";

contract PartyBCloseFacet is Accessibility, Pausable, IPartyBCloseFacet {
	/**
	 * @notice Accepts the cancellation request for the specified close intent.
	 * @param intentId The ID of the close intent for which the cancellation request is accepted.
	 */
	function acceptCancelCloseIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyBOfCloseIntent(intentId) {
		PartyBCloseFacetImpl.acceptCancelCloseIntent(msg.sender, intentId);
		emit AcceptCancelCloseIntent(intentId);
	}

	/**
	 * @notice Closes a trade for the specified close intent.
	 * @param intentId The ID of the close intent for which the trade is opened.
	 * @param quantity PartyB has the option to close the position with either the full amount requested by the user or a specific fraction of it
	 * @param price The closed price for the trade.
	 */
	function fillCloseIntent(
		uint256 intentId,
		uint256 quantity,
		uint256 price
	) external whenNotPartyBActionsPaused onlyPartyBOfCloseIntent(intentId) {
		PartyBCloseFacetImpl.fillCloseIntent(msg.sender, intentId, quantity, price);
		Trade storage trade = IntentStorage.layout().trades[IntentStorage.layout().closeIntents[intentId].tradeId];

		emit FillCloseIntent(intentId, trade.id, trade.partyA, trade.partyB, quantity, price);
	}
}
