// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { CloseIntent, IntentStatus } from "../../types/IntentTypes.sol";
import { Trade } from "../../types/TradeTypes.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyACloseEvents } from "./IPartyACloseEvents.sol";
import { IPartyACloseFacet } from "./IPartyACloseFacet.sol";
import { PartyACloseFacetImpl } from "./PartyACloseFacetImpl.sol";

/**
 * @title PartyACloseFacet
 * @notice Manages the lifecycle of close intents and trade transfers for PartyA users
 * @dev Implements the IPartyACloseFacet interface with access control and pausability
 */
contract PartyACloseFacet is Accessibility, Pausable, IPartyACloseFacet {
	using LibCloseIntentOps for CloseIntent;

	/**
	 * @notice Creates a new close intent to request the closure of an existing trade
	 * @dev Only the PartyA who owns the trade can create a close intent, and instant mode must be inactive
	 * @param tradeId The unique identifier of the trade to be closed
	 * @param price The target price at which PartyA is willing to close the position
	 *              (e.g., for a market price of $1000, PartyA might accept prices down to $990)
	 * @param quantity The amount of the trade to be closed, allowing for partial closures
	 * @param deadline Timestamp after which the close intent expires if not filled by PartyB
	 */
	function sendCloseIntent(
		uint256 tradeId,
		uint256 price,
		uint256 quantity,
		uint256 deadline
	) external whenNotPartyAActionsPaused onlyPartyAOfTrade(tradeId) inactiveInstantMode(msg.sender) {
		uint256 intentId = PartyACloseFacetImpl.sendCloseIntent(msg.sender, tradeId, price, quantity, deadline);
		emit SendCloseIntent(tradeId, intentId, price, quantity, deadline);
	}

	/**
	 * @notice Marks specified close intents as expired when they have passed their deadlines
	 * @dev This function can be called by anyone, and transitions intents to EXPIRED state
	 * @param expiredIntentIds Array of close intent IDs to be marked as expired
	 */
	function expireCloseIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		CloseIntentStorage.Layout storage intentLayout = CloseIntentStorage.layout();

		for (uint256 i; i < expiredIntentIds.length; i++) {
			intentLayout.closeIntents[expiredIntentIds[i]].expire();
			emit ExpireCloseIntent(expiredIntentIds[i]);
		}
	}

	/**
	 * @notice Requests cancellation of specified close intents
	 * @dev The outcome depends on the current state of each intent:
	 *      - Can result in either EXPIRED state if the deadline has passed
	 *      - Or CANCEL_PENDING state if awaiting PartyB's acceptance
	 * @param intentIds Array of close intent IDs to be canceled
	 */
	function cancelCloseIntent(uint256[] memory intentIds) external whenNotPartyAActionsPaused inactiveInstantMode(msg.sender) {
		for (uint256 i; i < intentIds.length; i++) {
			IntentStatus result = PartyACloseFacetImpl.cancelCloseIntent(msg.sender, intentIds[i]);
			if (result == IntentStatus.EXPIRED) {
				emit ExpireCloseIntent(intentIds[i]);
			} else if (result == IntentStatus.CANCEL_PENDING) {
				emit CancelCloseIntent(intentIds[i]);
			}
		}
	}

	/**
	 * @notice Transfers ownership of a trade to another address
	 * @dev Only the current PartyA owner of the trade can initiate this transfer
	 *      If the trade has an associated NFT, the NFT will also be transferred
	 * @param receiver The address that will become the new owner of the trade
	 * @param tradeId The unique identifier of the trade to be transferred
	 */
	function transferTrade(
		address receiver,
		uint256 tradeId
	) external whenNotPartyAActionsPaused onlyPartyAOfTrade(tradeId) notSuspended(msg.sender) notSuspended(receiver) {
		PartyACloseFacetImpl.transferTrade(receiver, tradeId);
		emit TransferTradeByPartyA(msg.sender, receiver, tradeId);
	}

	/**
	 * @notice Updates trade ownership when an associated NFT is transferred
	 * @dev This function is designed to be called only by the NFT contract itself
	 *      It synchronizes the trade ownership with the NFT ownership after transfers
	 * @param sender The previous owner of the trade/NFT
	 * @param receiver The new owner who will receive ownership of the trade
	 * @param tradeId The unique identifier of the trade whose ownership is being updated
	 */
	function transferTradeFromNFT(
		address sender,
		address receiver,
		uint256 tradeId
	) external whenNotPartyAActionsPaused notSuspended(sender) notSuspended(receiver) {
		PartyACloseFacetImpl.transferTradeFromNFT(sender, receiver, tradeId);
		emit TransferTradeByPartyA(sender, receiver, tradeId);
	}
}
