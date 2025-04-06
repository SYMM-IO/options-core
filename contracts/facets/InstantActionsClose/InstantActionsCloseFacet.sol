// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { SignedFillIntentById, CloseIntent, IntentStorage, Trade, SignedCloseIntent, SignedFillIntent, SignedSimpleActionIntent, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyACloseEvents } from "../PartyAClose/IPartyACloseEvents.sol";
import { IPartyBCloseEvents } from "../PartyBClose/IPartyBCloseEvents.sol";
import { IInstantActionsCloseFacet } from "./IInstantActionsCloseFacet.sol";
import { InstantActionsCloseFacetImpl } from "./InstantActionsCloseFacetImpl.sol";

/**
 * @title InstantActionsCloseFacet
 * @notice Enables meta-transaction functionality for close intent operations
 * @dev Allows third parties to execute trade closing actions using cryptographic signatures from PartyA and PartyB
 *      This contract complements InstantActionsOpenFacet by providing similar functionality for closing trades
 *      Improves UX by allowing atomic execution of multi-step processes and removing the need for direct
 *      blockchain interaction from the trading parties
 */
contract InstantActionsCloseFacet is Accessibility, Pausable, IInstantActionsCloseFacet {
	/**
	 * @notice Cancels a close intent using signatures from both PartyA and PartyB
	 * @dev Combines the cancel request from PartyA and acceptance from PartyB (if needed otherwise the second signature can be empty)
	 *	    into a single atomic transaction
	 *      May result in either EXPIRED or CANCELED status depending on the intent's deadline
	 * @param signedCancelCloseIntent The intent data for PartyA's cancellation request
	 * @param partyASignature Cryptographic signature from PartyA authorizing the cancellation
	 * @param signedAcceptCancelCloseIntent The intent data for PartyB's acceptance of the cancellation
	 * @param partyBSignature Cryptographic signature from PartyB authorizing the acceptance
	 */
	function instantCancelCloseIntent(
		SignedSimpleActionIntent calldata signedCancelCloseIntent,
		bytes calldata partyASignature,
		SignedSimpleActionIntent calldata signedAcceptCancelCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		IntentStatus result = InstantActionsCloseFacetImpl.instantCancelCloseIntent(
			signedCancelCloseIntent,
			partyASignature,
			signedAcceptCancelCloseIntent,
			partyBSignature
		);
		if (result == IntentStatus.EXPIRED) {
			emit ExpireCloseIntent(signedCancelCloseIntent.intentId);
		} else {
			emit CancelCloseIntent(signedCancelCloseIntent.intentId);
			emit AcceptCancelCloseIntent(signedCancelCloseIntent.intentId);
		}
	}

	/**
	 * @notice Executes the closing of a trade on behalf of PartyB
	 * @dev Allows any third party to fill a close intent using PartyB's signed authorization
	 *      Verifies the signature before executing the close at the specified price and quantity
	 *      This function is the meta-transaction equivalent of PartyB calling fillCloseIntent directly
	 * @param signedFillCloseIntent Data structure containing the intent ID, quantity, and price for closing
	 * @param partyBSignature Cryptographic signature from PartyB authorizing this closing action
	 */
	function instantFillCloseIntent(
		SignedFillIntentById calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		InstantActionsCloseFacetImpl.instantFillCloseIntent(signedFillCloseIntent, partyBSignature);
		emit FillCloseIntent(signedFillCloseIntent.intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}

	/**
	 * @notice Creates and immediately fills a close intent in a single atomic transaction
	 * @dev Combines PartyA's request to close a trade and PartyB's filling it into one operation
	 *      Verifies signatures from both parties before creating and executing the close
	 *      This atomic operation eliminates the typical multi-step process and reduces gas costs
	 * @param signedCloseIntent The complete close intent data structure from PartyA
	 * @param partyASignature Cryptographic signature from PartyA authorizing intent creation
	 * @param signedFillCloseIntent The fill parameters from PartyB (price and quantity)
	 * @param partyBSignature Cryptographic signature from PartyB authorizing the fill
	 */
	function instantCreateAndFillCloseIntent(
		SignedCloseIntent calldata signedCloseIntent,
		bytes calldata partyASignature,
		SignedFillIntent calldata signedFillCloseIntent,
		bytes calldata partyBSignature
	) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
		uint256 intentId = InstantActionsCloseFacetImpl.instantCreateAndFillCloseIntent(
			signedCloseIntent,
			partyASignature,
			signedFillCloseIntent,
			partyBSignature
		);
		emit SendCloseIntent(
			signedCloseIntent.tradeId,
			intentId,
			signedFillCloseIntent.price,
			signedFillCloseIntent.quantity,
			signedCloseIntent.deadline
		);
		emit FillCloseIntent(intentId, signedFillCloseIntent.quantity, signedFillCloseIntent.price);
	}
}
