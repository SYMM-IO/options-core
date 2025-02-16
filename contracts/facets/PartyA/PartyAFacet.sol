// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./PartyAFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "./IPartyAFacet.sol";

contract PartyAFacet is Accessibility, Pausable, IPartyAFacet {
	/**
	 * @notice Send a open intent to the protocol. The intent status will be pending.
	 * @param partyBsWhiteList List of party B addresses allowed to act on this intent.
	 * @param symbolId Each symbol within the system possesses a unique identifier, for instance, BTCUSDT carries its own distinct ID
	 * @param price This is the user-requested price that the user is willing to open a trade. For example, if the market price for an arbitrary symbol is $1000 and the user wants to
	 * 				open a trade on this symbol they might be ok with prices up to $1050
	 * @param quantity Size of the trade
	 * @param strikePrice The strike price for the options contract
	 * @param expirationTimestamp The expiration time for the options contract
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
		ExerciseFee memory exerciseFee,
		uint256 deadline,
		address feeToken,
		address affiliate
	) external whenNotPartyAActionsPaused notSuspended(msg.sender) returns (uint256 intentId) {
		intentId = PartyAFacetImpl.sendOpenIntent(
			partyBsWhiteList,
			symbolId,
			price,
			quantity,
			strikePrice,
			expirationTimestamp,
			exerciseFee,
			deadline,
			feeToken,
			affiliate
		);
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		emit SendOpenIntent(
			msg.sender,
			intentId,
			partyBsWhiteList,
			symbolId,
			price,
			quantity,
			strikePrice,
			expirationTimestamp,
			exerciseFee,
			intent.tradingFee,
			deadline
		);
	}

	/**
	 * @notice Expires the specified open intents.
	 * @param expiredIntentIds An array of IDs of the open intents to be expired.
	 */
	function expireOpenIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		for (uint256 i; i < expiredIntentIds.length; i++) {
			LibIntent.expireOpenIntent(expiredIntentIds[i]);
			emit ExpireOpenIntent(expiredIntentIds[i]);
		}
	}

	/**
	 * @notice Expires the specified close intents.
	 * @param expiredIntentIds An array of IDs of the close intents to be expired.
	 */
	function expireCloseIntent(uint256[] memory expiredIntentIds) external whenNotPartyAActionsPaused {
		for (uint256 i; i < expiredIntentIds.length; i++) {
			LibIntent.expireCloseIntent(expiredIntentIds[i]);
			emit ExpireCloseIntent(expiredIntentIds[i]);
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
			IntentStatus result = PartyAFacetImpl.cancelOpenIntent(intentIds[i]);
			OpenIntent memory intent = IntentStorage.layout().openIntents[intentIds[i]];

			if (result == IntentStatus.EXPIRED) {
				emit ExpireOpenIntent(intent.id);
			} else if (result == IntentStatus.CANCELED || result == IntentStatus.CANCEL_PENDING) {
				emit CancelOpenIntent(intent.partyA, intent.partyB, result, intent.id);
			}
		}
	}

	/**
	 * @notice Requests to cancel a close intent.
	 * @param intentIds The ID of the close intents to be canceled.
	 */
	function cancelCloseIntent(uint256[] memory intentIds) external whenNotPartyAActionsPaused {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		for (uint256 i; i < intentIds.length; i++) {
			Trade storage trade = intentLayout.trades[intentLayout.closeIntents[intentIds[i]].tradeId];
			IntentStatus result = PartyAFacetImpl.cancelCloseIntent(intentIds[i]);
			if (result == IntentStatus.EXPIRED) {
				emit ExpireCloseIntent(intentIds[i]);
			} else if (result == IntentStatus.CANCEL_PENDING) {
				emit CancelCloseIntent(trade.partyA, trade.partyB, intentIds[i]);
			}
		}
	}

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
	) external whenNotPartyAActionsPaused onlyPartyAOfTrade(tradeId) {
		uint256 closeIntentId = PartyAFacetImpl.sendCloseIntent(tradeId, price, quantity, deadline);
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];
		emit SendCloseIntent(trade.partyA, trade.partyB, tradeId, closeIntentId, price, quantity, deadline, IntentStatus.PENDING);
	}

	/**
	 * @notice Standard trade transfer (initiated by the partyA).
	 *         If an NFT is mapped to this trade, it will also call the NFT contract to transfer it.
	 * @param receiver The receiver address of the trade
	 * @param tradeId The Id of the trade
	 */
	function transferTrade(address receiver, uint256 tradeId) external whenNotPartyAActionsPaused onlyPartyAOfTrade(tradeId) {
		PartyAFacetImpl.transferTrade(receiver, tradeId);
		emit TransferTradeByPartyA(msg.sender, receiver, tradeId);
	}

	/**
	 * @notice Called by the NFT contract whenever an NFT is transferred from->to,
	 *         so the trade ownership is also updated here.
	 * @param sender The sender address of the trade
	 * @param receiver The receiver address of the trade
	 * @param tradeId The Id of the trade
	 */
	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) external whenNotPartyAActionsPaused {
		PartyAFacetImpl.transferTradeFromNFT(sender, receiver, tradeId);
		emit TransferTradeByPartyA(sender, receiver, tradeId);
	}
}
