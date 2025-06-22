// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/models/LibParty.sol";
import { LibTradeOps } from "../../libraries/models/LibTrade.sol";
import { LibCloseIntentOps } from "../../libraries/models/LibCloseIntent.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";

import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { ScheduledReleaseBalance } from "../../types/BalanceTypes.sol";
import { CloseIntent, CloseIntentStatus } from "../../types/IntentTypes.sol";
import { MarginType } from "../../types/BaseTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { TradeErrors } from "../../errors/TradeErrors.sol";
import { IntentErrors } from "../../errors/IntentErrors.sol";
import { ITradeNFT } from "../../interfaces/ITradeNFT.sol";

library LibPartyAClose {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibParty for address;

	function sendCloseIntent(address sender, uint256 tradeId, uint256 quantity, uint256 price, uint256 deadline) internal returns (uint256 intentId) {
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		Trade storage trade = tradeLayout.trades[tradeId];

		if (sender != trade.partyA) revert ValidationErrors.UnauthorizedSender(sender, trade.partyA);

		ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		if (deadline < block.timestamp) revert ValidationErrors.LowDeadline(deadline, block.timestamp);

		if (trade.getAvailableAmountToClose() < quantity) revert IntentErrors.InvalidQuantity(quantity, trade.getAvailableAmountToClose());

		if (trade.activeCloseIntentIds.length >= AppStorage.layout().maxCloseOrdersLength)
			revert IntentErrors.TooManyCloseOrders(trade.activeCloseIntentIds.length, AppStorage.layout().maxCloseOrdersLength);

		intentId = ++CloseIntentStorage.layout().lastCloseIntentId;
		CloseIntent memory intent = CloseIntent({
			id: intentId,
			tradeId: tradeId,
			price: price,
			quantity: quantity,
			filledAmount: 0,
			status: CloseIntentStatus.PENDING,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: deadline
		});

		intent.save();
	}

	function cancelCloseIntent(address sender, uint256 intentId) internal returns (CloseIntentStatus) {
		CloseIntent storage intent = CloseIntentStorage.layout().closeIntents[intentId];
		Trade storage trade = TradeStorage.layout().trades[intent.tradeId];

		if (trade.partyA != sender) revert ValidationErrors.UnauthorizedSender(sender, trade.partyA);

		ValidationErrors.requireStatus("CloseIntentStatus", uint8(intent.status), uint8(CloseIntentStatus.PENDING));

		if (block.timestamp > intent.deadline) {
			intent.expire();
			return CloseIntentStatus.EXPIRED;
		} else {
			intent.statusModifyTimestamp = block.timestamp;
			intent.status = CloseIntentStatus.CANCEL_PENDING;
			return CloseIntentStatus.CANCEL_PENDING;
		}
	}

	/**
	 * @dev Shared logic for both diamond-initiated and NFT-initiated trade transfers.
	 */
	function validateAndTransferTrade(address sender, address receiver, uint256 tradeId) internal {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		if (trade.partyA != sender) revert ValidationErrors.UnauthorizedSender(sender, trade.partyA);
		if (trade.partyB == receiver) revert TradeErrors.ReceiverIsPartyB(receiver, trade.partyB);
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("receiver");
		if (receiver.isPartyB()) revert TradeErrors.ReceiverIsPartyB(receiver, trade.partyB);
		ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));
		if (trade.tradeAgreements.marginType == MarginType.CROSS) revert TradeErrors.CrossTradeTransferNotAllowed(tradeId);
		trade.partyB.requireSolvent(address(0), symbol.collateral, MarginType.ISOLATED);

		trade.remove();
		trade.partyA = receiver;
		trade.save();
	}

	function transferTrade(address receiver, uint256 tradeId) internal {
		validateAndTransferTrade(msg.sender, receiver, tradeId);
		if (AppStorage.layout().tradeNftAddress != address(0)) {
			ITradeNFT(AppStorage.layout().tradeNftAddress).transferNFTInitiatedInSymmio(msg.sender, receiver, tradeId);
		}
	}

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) internal {
		if (msg.sender != AppStorage.layout().tradeNftAddress)
			revert ValidationErrors.UnauthorizedSender(msg.sender, AppStorage.layout().tradeNftAddress);

		validateAndTransferTrade(sender, receiver, tradeId);
	}
}
