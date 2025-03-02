// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ITradeNFT.sol";

library PartyAFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

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
		address affiliate,
		bytes32 userData
	) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Symbol memory symbol = SymbolStorage.layout().symbols[symbolId];

		require(symbol.isValid, "PartyAFacet: Symbol is not valid");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(expirationTimestamp >= block.timestamp, "PartyAFacet: Low expiration timestamp");
		require(exerciseFee.cap <= 1e18, "PartyAFacet: High cap for exercise fee");
		require(!accountLayout.instantActionsMode[msg.sender], "PartyAFacet: Instant action mode is activated");
		require(appLayout.affiliateStatus[affiliate] || affiliate == address(0), "PartyAFacet: Invalid affiliate");

		if (accountLayout.boundPartyB[msg.sender] != address(0)) {
			require(
				partyBsWhiteList.length == 1 && partyBsWhiteList[0] == accountLayout.boundPartyB[msg.sender],
				"PartyAFacet: User is bound to another PartyB"
			);
		}

		for (uint8 i = 0; i < partyBsWhiteList.length; i++) {
			require(partyBsWhiteList[i] != msg.sender, "PartyAFacet: Sender isn't allowed in partyBWhiteList");
		}

		if (partyBsWhiteList.length == 1) {
			require(
				uint256(accountLayout.balances[msg.sender][symbol.collateral].partyBBalance(partyBsWhiteList[0])) >= (quantity * price) / 1e18,
				"PartyAFacet: insufficient available balance"
			);
			require(
				uint256(accountLayout.balances[msg.sender][feeToken].partyBBalance(partyBsWhiteList[0])) >=
					(quantity * price * symbol.tradingFee) / 1e36,
				"PartyAFacet: insufficient available balance for trading fee"
			);
		} else {
			require(
				uint256(accountLayout.balances[msg.sender][symbol.collateral].available) >= (quantity * price) / 1e18,
				"PartyAFacet: insufficient available balance"
			);
			require(
				uint256(accountLayout.balances[msg.sender][feeToken].available) >= (quantity * price * symbol.tradingFee) / 1e36,
				"PartyAFacet: insufficient available balance for trading fee"
			);
		}

		intentId = ++intentLayout.lastOpenIntentId;
		OpenIntent memory intent = OpenIntent({
			id: intentId,
			tradeId: 0,
			partyBsWhiteList: partyBsWhiteList,
			symbolId: symbolId,
			price: price,
			quantity: quantity,
			strikePrice: strikePrice,
			expirationTimestamp: expirationTimestamp,
			exerciseFee: exerciseFee,
			partyA: msg.sender,
			partyB: address(0),
			status: IntentStatus.PENDING,
			parentId: 0,
			createTimestamp: block.timestamp,
			statusModifyTimestamp: block.timestamp,
			deadline: deadline,
			tradingFee: TradingFee(feeToken, IPriceOracle(AppStorage.layout().priceOracleAddress).getPrice(feeToken), symbol.tradingFee),
			affiliate: affiliate,
			userData: userData
		});

		intentLayout.openIntents[intentId] = intent;
		intentLayout.openIntentsOf[msg.sender].push(intent.id);
		LibIntent.addToPartyAOpenIntents(intent.id);

		accountLayout.lockedBalances[msg.sender][symbol.collateral] += LibIntent.getPremiumOfOpenIntent(intentId);

		uint256 tradingFee = LibIntent.getTradingFee(intentId);
		uint256 affiliateFee = LibIntent.getAffiliateFee(intentId);
		accountLayout.balances[msg.sender][feeToken].syncAll(block.timestamp);
		if (partyBsWhiteList.length == 1) {
			accountLayout.balances[msg.sender][feeToken].subForPartyB(partyBsWhiteList[0], tradingFee);
			accountLayout.balances[msg.sender][feeToken].subForPartyB(partyBsWhiteList[0], affiliateFee);
		} else {
			accountLayout.balances[msg.sender][feeToken].sub(tradingFee);
			accountLayout.balances[msg.sender][feeToken].sub(affiliateFee);
		}
	}

	function cancelOpenIntent(uint256 intentId) internal returns (IntentStatus result) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];

		require(intent.status == IntentStatus.PENDING || intent.status == IntentStatus.LOCKED, "PartyAFacet: Invalid state");
		require(intent.partyA == msg.sender, "PartyAFacet: Should be partyA of Intent");
		require(!accountLayout.instantActionsMode[msg.sender], "PartyAFacet: Instant action mode is activated");

		if (block.timestamp > intent.deadline) {
			LibIntent.expireOpenIntent(intentId);
			result = IntentStatus.EXPIRED;
		} else if (intent.status == IntentStatus.PENDING) {
			intent.status = IntentStatus.CANCELED;
			uint256 tradingFee = LibIntent.getTradingFee(intent.id);
			uint256 affiliateFee = LibIntent.getAffiliateFee(intentId);
			if (intent.partyBsWhiteList.length == 1) {
				accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].scheduledAdd(intent.partyBsWhiteList[0], tradingFee, block.timestamp);
				accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].scheduledAdd(intent.partyBsWhiteList[0], affiliateFee, block.timestamp);
			} else {
				accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].instantAdd(intent.tradingFee.feeToken, tradingFee);
				accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].instantAdd(intent.tradingFee.feeToken, affiliateFee);
			}
			accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= LibIntent.getPremiumOfOpenIntent(intentId);
			LibIntent.removeFromPartyAOpenIntents(intentId);
			result = IntentStatus.CANCELED;
		} else {
			// Intent is locked
			intent.status = IntentStatus.CANCEL_PENDING;
			result = IntentStatus.CANCEL_PENDING;
		}
		intent.statusModifyTimestamp = block.timestamp;
	}

	function cancelCloseIntent(uint256 intentId) internal returns (IntentStatus) {
		CloseIntent storage intent = IntentStorage.layout().closeIntents[intentId];
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

	function sendCloseIntent(uint256 tradeId, uint256 price, uint256 quantity, uint256 deadline) internal returns (uint256 intentId) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];

		require(trade.status == TradeStatus.OPENED, "PartyAFacet: Invalid state");
		require(deadline >= block.timestamp, "PartyAFacet: Low deadline");
		require(!AccountStorage.layout().instantActionsMode[trade.partyA], "PartyAFacet: Instant action mode is activated");
		require(LibIntent.getAvailableAmountToClose(trade.id) >= quantity, "PartyAFacet: Invalid quantity");
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

		intentLayout.closeIntents[intentId] = intent;
		trade.activeCloseIntentIds.push(intent.id);
		intentLayout.closeIntentIdsOf[trade.id].push(intentId);
		trade.closePendingAmount += quantity;
	}

	/**
	 * @dev Shared logic for both diamond-initiated and NFT-initiated trade transfers.
	 */
	function validateAndTransferTrade(address sender, address receiver, uint256 tradeId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Trade storage trade = intentLayout.trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.symbolId];

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
