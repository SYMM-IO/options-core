// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibTrade.sol";
import "../../libraries/LibCloseIntent.sol";
import "../../libraries/LibUserData.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ITradeNFT.sol";

library PartyACloseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;

	function sendCloseIntent(address sender, uint256 tradeId, uint256 price, uint256 quantity, uint256 deadline) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];

		require(sender == trade.partyA, "PartyAFacet: Invalid sender");
		require(trade.status == TradeStatus.OPENED, "PartyAFacet: Invalid state");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(!AccountStorage.layout().instantActionsMode[trade.partyA], "PartyAFacet: Instant action mode is activated");
		require(trade.getAvailableAmountToClose() >= quantity, "PartyAFacet: Invalid quantity");
		require(trade.activeCloseIntentIds.length < AppStorage.layout().maxCloseOrdersLength, "PartyAFacet: Too many close orders");

		// create intent.
		intentId = ++intentLayout.lastCloseIntentId;
		CloseIntent memory intent = CloseIntent({
			id: intentId,
			tradeId: tradeId,
			price: price,
			quantity: quantity,
			filledAmount: 0,
			status: IntentStatus.PENDING,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: deadline
		});

		intent.save();
	}

	function cancelCloseIntent(address sender, uint256 intentId) internal returns (IntentStatus) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();

		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = intentLayout.trades[intent.tradeId];

		require(trade.partyA == sender, "PartyAFacet: Invalid sender");
		require(intent.status == IntentStatus.PENDING, "PartyAFacet: Invalid state");
		require(IntentStorage.layout().trades[intent.tradeId].partyA == msg.sender, "PartyAFacet: Should be partyA of Intent");
		require(!AccountStorage.layout().instantActionsMode[msg.sender], "PartyAFacet: Instant action mode is activated");

		if (block.timestamp > intent.deadline) {
			LibIntent.expireCloseIntent(intentId);
			return IntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = IntentStatus.CANCEL_PENDING;
			return IntentStatus.CANCEL_PENDING;
		}
	}

	/**
	 * @dev Shared logic for both diamond-initiated and NFT-initiated trade transfers.
	 */
	function validateAndTransferTrade(address sender, address receiver, uint256 tradeId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		require(trade.partyA == sender, "PartyAFacet: from != partyA");
		require(trade.partyB != receiver, "PartyAFacet: to == partyB");
		require(receiver != address(0), "PartyAFacet: zero address");
		require(trade.status == TradeStatus.OPENED, "PartyAFacet: Invalid trade state");
		require(
			appLayout.liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyAFacet: PartyB is liquidated"
		);
		require(intentLayout.activeTradesOf[receiver].length < appLayout.maxTradePerPartyA, "PartyAFacet: too many trades for to");
		require(!accountLayout.suspendedAddresses[sender], "PartyAFacet: from suspended");
		require(!accountLayout.suspendedAddresses[receiver], "PartyAFacet: to suspended");

		// remove from active trades
		uint256 indexOfPartyATrade = intentLayout.partyATradesIndex[trade.id];
		uint256 lastIndex = intentLayout.activeTradesOf[trade.partyA].length - 1;
		intentLayout.activeTradesOf[trade.partyA][indexOfPartyATrade] = intentLayout.activeTradesOf[trade.partyA][lastIndex];
		intentLayout.partyATradesIndex[intentLayout.activeTradesOf[trade.partyA][lastIndex]] = indexOfPartyATrade;
		intentLayout.activeTradesOf[trade.partyA].pop();

		trade.partyA = receiver;

		// add to active trades
		intentLayout.tradesOf[trade.partyA].push(trade.id);
		intentLayout.activeTradesOf[trade.partyA].push(trade.id);
		intentLayout.partyATradesIndex[trade.id] = intentLayout.activeTradesOf[trade.partyA].length - 1;
	}

	function transferTrade(address receiver, uint256 tradeId) internal {
		validateAndTransferTrade(msg.sender, receiver, tradeId);
		ITradeNFT(AppStorage.layout().tradeNftAddress).transferNFTInitiatedInSymmio(msg.sender, receiver, tradeId);
	}

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) internal {
		require(msg.sender == AppStorage.layout().tradeNftAddress, "PartyAFacet: Sender should be the NFT contract");
		validateAndTransferTrade(sender, receiver, tradeId);
	}
}
