// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { Trade } from "../../types/TradeTypes.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyBCloseEvents } from "./IPartyBCloseEvents.sol";
import { IPartyBCloseFacet } from "./IPartyBCloseFacet.sol";
import { PartyBCloseFacetImpl } from "./PartyBCloseFacetImpl.sol";

/**
 * @title PartyBCloseFacet
 * @notice Manages PartyB's actions for closing and handling cancellations of close intents
 * @dev Implements the IPartyBCloseFacet interface with access controls and pausability
 */
contract PartyBCloseFacet is Accessibility, Pausable, IPartyBCloseFacet {
	/**
	 * @notice Allows PartyB to accept a cancellation request for a close intent
	 * @dev When accepted, the close intent will be marked as canceled
	 * @param intentId The unique identifier of the close intent for which the cancellation request is being accepted
	 */
	function acceptCancelCloseIntent(uint256 intentId) external whenNotPartyBActionsPaused {
		PartyBCloseFacetImpl.acceptCancelCloseIntent(msg.sender, intentId);
		emit AcceptCancelCloseIntent(intentId);
	}

	/**
	 * @notice Executes a trade closure based on a previously submitted close intent
	 * @dev PartyB can choose to close the full requested amount or a partial amount at the specified price
	 * @param intentId The unique identifier of the close intent to be filled
	 * @param quantity The amount to be closed, which can be equal to or less than the original requested amount
	 * @param price The execution price at which the trade is being closed, must be favorable to PartyA compared to their requested price
	 */
	function fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price) external whenNotPartyBActionsPaused {
		PartyBCloseFacetImpl.fillCloseIntent(msg.sender, intentId, quantity, price);
		emit FillCloseIntent(intentId, quantity, price);
	}
}
