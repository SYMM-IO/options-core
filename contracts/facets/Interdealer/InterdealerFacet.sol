// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./InterdealerFacetImpl.sol";
import "../../utils/Accessibility.sol";
import "../../utils/Pausable.sol";
import "../../libraries/LibPartyB.sol";
import "./IInterdealerFacet.sol";

contract InterdealerFacet is Accessibility, Pausable, IInterdealerFacet {
	function interdealerIntent(uint256 tradeId, address[] memory partyBWhitelist) external {
		InterdealerFacetImpl.interdealerIntent(tradeId, partyBWhitelist);
		emit InterdealerIntent(tradeId, msg.sender, partyBWhitelist);
	}

	function cancelInterdealerIntent(uint256 intentId) external {}

	function lockInterdealerIntent(uint256 intentId, uint256 tradeQuantity) external {}

	function unlockInterdealerIntent(uint256 intentId) external {}

	function acceptCancelInterdealerIntent(uint256 intentId) external {}

	function fillInterdealerIntent(uint256 intentId, uint256 price) external {}

	// /**
	//  * @notice Once a user issues a open intent, any PartyB can secure it, based on their estimated profit and loss from opening the trade.
	//  * @param intentId The ID of the open intent to be locked.
	//  */
	// function lockOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyB {
	// 	LibPartyB.lockOpenIntent(intentId, msg.sender);
	// 	OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
	// 	emit LockOpenIntent(intent.partyB, intentId);
	// }
	// /**
	//  * @notice Unlocks the specified open intent.
	//  * @param intentId The ID of the open intent to be unlocked.
	//  */
	// function unlockOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyBOfOpenIntent(intentId) {
	// 	IntentStatus res = LibPartyB.unlockOpenIntent(intentId);
	// 	if (res == IntentStatus.EXPIRED) {
	// 		emit ExpireOpenIntent(intentId);
	// 	} else if (res == IntentStatus.PENDING) {
	// 		emit UnlockOpenIntent(msg.sender, intentId);
	// 	}
	// }
	// /**
	//  * @notice Accepts the cancellation request for the specified open intent.
	//  * @param intentId The ID of the open intent for which the cancellation request is accepted.
	//  */
	// function acceptCancelOpenIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyBOfOpenIntent(intentId) {
	// 	PartyBFacetImpl.acceptCancelOpenIntent(intentId);
	// 	emit AcceptCancelOpenIntent(intentId);
	// }
	// /**
	//  * @notice Accepts the cancellation request for the specified close intent.
	//  * @param intentId The ID of the close intent for which the cancellation request is accepted.
	//  */
	// function acceptCancelCloseIntent(uint256 intentId) external whenNotPartyBActionsPaused onlyPartyBOfCloseIntent(intentId) {
	// 	PartyBFacetImpl.acceptCancelCloseIntent(intentId);
	// 	emit AcceptCancelCloseIntent(intentId);
	// }
	// /**
	//  * @notice Opens a trade for the specified open intent.
	//  * @param intentId The ID of the open intent for which the trade is opened.
	//  * @param quantity PartyB has the option to open the position with either the full amount requested by the user or a specific fraction of it
	//  * @param price The opened price for the trade.
	//  */
	// function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) external whenNotPartyBActionsPaused onlyPartyBOfOpenIntent(intentId) {
	// 	uint256 newId = PartyBFacetImpl.fillOpenIntent(intentId, quantity, price);
	// 	OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
	// 	emit FillOpenIntent(intentId, intent.tradeId, intent.partyA, intent.partyB, quantity, price);
	// 	if (newId != 0) {
	// 		OpenIntent storage newIntent = IntentStorage.layout().openIntents[newId];
	// 		if (newIntent.status == IntentStatus.PENDING) {
	// 			emit SendOpenIntent(
	// 				newIntent.partyA,
	// 				newIntent.id,
	// 				newIntent.partyBsWhiteList,
	// 				newIntent.symbolId,
	// 				newIntent.price,
	// 				newIntent.quantity,
	// 				newIntent.strikePrice,
	// 				newIntent.expirationTimestamp,
	// 				newIntent.exerciseFee,
	// 				newIntent.tradingFee,
	// 				newIntent.deadline
	// 			);
	// 		} else if (newIntent.status == IntentStatus.CANCELED) {
	// 			emit AcceptCancelOpenIntent(newIntent.id);
	// 		}
	// 	}
	// }
	// /**
	//  * @notice Closes a trade for the specified close intent.
	//  * @param intentId The ID of the close intent for which the trade is opened.
	//  * @param quantity PartyB has the option to close the position with either the full amount requested by the user or a specific fraction of it
	//  * @param price The closed price for the trade.
	//  */
	// function fillCloseIntent(
	// 	uint256 intentId,
	// 	uint256 quantity,
	// 	uint256 price
	// ) external whenNotPartyBActionsPaused onlyPartyBOfCloseIntent(intentId) {
	// 	PartyBFacetImpl.fillCloseIntent(intentId, quantity, price);
	// 	Trade storage trade = IntentStorage.layout().trades[IntentStorage.layout().closeIntents[intentId].tradeId];
	// 	emit FillCloseIntent(intentId, trade.id, trade.partyA, trade.partyB, quantity, price);
	// }
	// /**
	//  * @notice Expires a trade.
	//  * @param tradeId The ID of the trade.
	//  * @param settlementPriceSig The muon sig about price of the symbol at the time of expiration
	//  */
	// function expireTrade(
	// 	uint256 tradeId,
	// 	SettlementPriceSig memory settlementPriceSig
	// ) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
	// 	PartyBFacetImpl.expireTrade(tradeId, settlementPriceSig);
	// 	emit ExpireTrade(msg.sender, tradeId, settlementPriceSig.settlementPrice);
	// }
	// /**
	//  * @notice Exercises a trade.
	//  * @param tradeId The ID of the trade.
	//  * @param settlementPriceSig The muon sig about price of the symbol at the time of expiration
	//  */
	// function exerciseTrade(
	// 	uint256 tradeId,
	// 	SettlementPriceSig memory settlementPriceSig
	// ) external whenNotPartyBActionsPaused whenNotThirdPartyActionsPaused {
	// 	PartyBFacetImpl.exerciseTrade(tradeId, settlementPriceSig);
	// 	emit ExerciseTrade(msg.sender, tradeId, settlementPriceSig.settlementPrice);
	// }
}
