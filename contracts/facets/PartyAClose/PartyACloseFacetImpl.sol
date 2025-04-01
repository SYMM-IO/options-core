// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ITradeNFT } from "../../interfaces/ITradeNFT.sol";
import { LibCloseIntentOps } from "../../libraries/LibCloseIntent.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { CloseIntent, Trade, IntentStorage, IntentStatus, TradeStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage } from "../../storages/SymbolStorage.sol";
import { PartyACloseFacetErrors } from "./PartyACloseFacetErrors.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";

library PartyACloseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;
	using LibPartyB for address;

	function sendCloseIntent(address sender, uint256 tradeId, uint256 price, uint256 quantity, uint256 deadline) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];

		if (sender != trade.partyA) revert CommonErrors.UnauthorizedSender(sender, trade.partyA);

		if (trade.status != TradeStatus.OPENED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(TradeStatus.OPENED);
			revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
		}

		if (deadline < block.timestamp) revert CommonErrors.LowDeadline(deadline, block.timestamp);

		if (trade.getAvailableAmountToClose() < quantity) revert PartyACloseFacetErrors.InvalidQuantity(quantity, trade.getAvailableAmountToClose());

		if (trade.activeCloseIntentIds.length >= AppStorage.layout().maxCloseOrdersLength)
			revert PartyACloseFacetErrors.TooManyCloseOrders(trade.activeCloseIntentIds.length, AppStorage.layout().maxCloseOrdersLength);

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

		if (trade.partyA != sender) revert CommonErrors.UnauthorizedSender(sender, trade.partyA);

		if (intent.status != IntentStatus.PENDING) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(IntentStatus.PENDING);
			revert CommonErrors.InvalidState("IntentStatus", uint8(intent.status), requiredStatuses);
		}

		if (block.timestamp > intent.deadline) {
			intent.expire();
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
		Trade storage trade = intentLayout.trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		if (trade.partyA != sender) revert PartyACloseFacetErrors.OnlyPartyACanTransfer(sender, trade.partyA);

		if (trade.partyB == receiver) revert PartyACloseFacetErrors.ReceiverIsPartyB(receiver, trade.partyB);

		if (receiver == address(0)) revert CommonErrors.ZeroAddress("receiver");

		if (trade.status != TradeStatus.OPENED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(TradeStatus.OPENED);
			revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
		}

		trade.partyB.requireSolvent(symbol.collateral);

		trade.remove();
		trade.partyA = receiver;
		trade.save();
	}

	function transferTrade(address receiver, uint256 tradeId) internal {
		validateAndTransferTrade(msg.sender, receiver, tradeId);
		ITradeNFT(AppStorage.layout().tradeNftAddress).transferNFTInitiatedInSymmio(msg.sender, receiver, tradeId);
	}

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) internal {
		if (msg.sender != AppStorage.layout().tradeNftAddress)
			revert CommonErrors.UnauthorizedSender(msg.sender, AppStorage.layout().tradeNftAddress);

		validateAndTransferTrade(sender, receiver, tradeId);
	}
}
