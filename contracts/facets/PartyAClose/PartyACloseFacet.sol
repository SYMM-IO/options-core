// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { CloseIntent, IntentStorage, Trade, IntentStatus } from "../../storages/IntentStorage.sol";
import { Accessibility } from "../../utils/Accessibility.sol";
import { Pausable } from "../../utils/Pausable.sol";
import { IPartyACloseEvents } from "./IPartyACloseEvents.sol";
import { IPartyACloseFacet } from "./IPartyACloseFacet.sol";
import { PartyACloseFacetImpl } from "./PartyACloseFacetImpl.sol";

contract PartyACloseFacet is Accessibility, Pausable, IPartyACloseFacet {
	using LibCloseIntentOps for CloseIntent;

	/**
	 * @notice User sends a close intent to close their trade.
	 * @param tradeId The ID of the trade to be closed.
	 * @param price The closing price for the position. this is the price the user wants to close the trade at. Say, for a random symbol, the market price is $1000.
	 * 						If a user wants to close a trade on this symbol, they might be cool with prices up to $990
	 * @param quantity The quantity of the trade to be closed.
	 * @param deadline The deadline for executing the position closure. If 'partyB' doesn't get back to the request within a certain time, then the request will just time out
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
	 * @notice Expires the specified close intents.
	 * @param expiredIntentIds An array of IDs of the close intents to be expired.
	 */
	function expireCloseIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		for (uint256 i; i < expiredIntentIds.length; i++) {
			intentLayout.closeIntents[expiredIntentIds[i]].expire();
			emit ExpireCloseIntent(expiredIntentIds[i]);
		}
	}

	/**
	 * @notice Requests to cancel a close intent.
	 * @param intentIds The ID of the close intents to be canceled.
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
	 * @notice Standard trade transfer (initiated by the partyA).
	 *         If an NFT is mapped to this trade, it will also call the NFT contract to transfer it.
	 * @param receiver The receiver address of the trade
	 * @param tradeId The Id of the trade
	 */
	function transferTrade(
		address receiver,
		uint256 tradeId
	) external whenNotPartyAActionsPaused onlyPartyAOfTrade(tradeId) notSuspended(msg.sender) notSuspended(receiver) {
		PartyACloseFacetImpl.transferTrade(receiver, tradeId);
		emit TransferTradeByPartyA(msg.sender, receiver, tradeId);
	}

	/**
	 * @notice Called by the NFT contract whenever an NFT is transferred from->to,
	 *         so the trade ownership is also updated here.
	 * @param sender The sender address of the trade
	 * @param receiver The receiver address of the trade
	 * @param tradeId The Id of the trade
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
