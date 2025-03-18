// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibPartyB.sol";
import "../../libraries/LibMuon.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";
import "../../interfaces/ISignatureVerifier.sol";

library PartyBFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;
	using LibTradeOps for Trade;

	function acceptCancelOpenIntent(uint256 intentId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		require(
			AppStorage.layout().liquidationDetails[intent.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"AccountFacet: PartyB is in the liquidation process"
		);
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;

		ScheduledReleaseBalance storage partyABalance = accountLayout.balances[msg.sender][symbol.collateral];
		ScheduledReleaseBalance storage partyAFeeBalance = accountLayout.balances[msg.sender][intent.tradingFee.feeToken];

		partyABalance.instantAdd(symbol.collateral, intent.getPremium());

		// send trading Fee back to partyA
		uint256 tradingFee = intent.getTradingFee();
		uint256 affiliateFee = intent.getAffiliateFee();
		if (intent.partyBsWhiteList.length == 1) {
			partyAFeeBalance.scheduledAdd(intent.partyBsWhiteList[0], tradingFee + affiliateFee, block.timestamp);
		} else {
			partyAFeeBalance.instantAdd(intent.tradingFee.feeToken, tradingFee + affiliateFee);
		}

		intent.remove(false);
	}

	function acceptCancelCloseIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];
		Trade storage trade = IntentStorage.layout().trades[intent.tradeId];

		require(intent.status == IntentStatus.CANCEL_PENDING, "LibIntent: Invalid state");
		require(
			AppStorage.layout().liquidationDetails[trade.partyB][SymbolStorage.layout().symbols[trade.symbolId].collateral].status ==
				LiquidationStatus.SOLVENT,
			"AccountFacet: PartyB is in the liquidation process"
		);

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		intent.remove();
	}

	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) internal returns (uint256 tradeId) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];

		require(accountLayout.suspendedAddresses[intent.partyA] == false, "PartyBFacet: PartyA is suspended");
		require(!accountLayout.suspendedAddresses[msg.sender], "PartyBFacet: Sender is Suspended");
		require(!appLayout.partyBEmergencyStatus[intent.partyB], "PartyBFacet: PartyB is in emergency mode");
		require(!appLayout.emergencyMode, "PartyBFacet: System is in emergency mode");

		tradeId = LibPartyB.fillOpenIntent(intentId, quantity, price);
	}

	function fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price) internal {
		LibPartyB.fillCloseIntent(intentId, quantity, price);
	}

	function expireTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		require(sig.symbolId == trade.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.expirationTimestamp, "PartyBFacet: Trade isn't expired");
		if (symbol.optionType == OptionType.PUT) {
			require(sig.settlementPrice >= trade.strikePrice, "PartyBFacet: Invalid price");
		} else {
			require(sig.settlementPrice <= trade.strikePrice, "PartyBFacet: Invalid price");
		}
		if (msg.sender != trade.partyB) {
			require(
				trade.expirationTimestamp + AppStorage.layout().ownerExclusiveWindow <= block.timestamp,
				"PartyBFacet: Third parties should wait for owner exclusive window"
			);
		}
		trade.settledPrice = sig.settlementPrice;
		trade.close(TradeStatus.EXPIRED, IntentStatus.CANCELED);
	}

	function exerciseTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		require(sig.symbolId == trade.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.expirationTimestamp, "PartyBFacet: Trade isn't expired");
		require(
			appLayout.liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);
		if (msg.sender != trade.partyB) {
			require(
				trade.expirationTimestamp + appLayout.ownerExclusiveWindow <= block.timestamp,
				"PartyBFacet: Third parties should wait for owner exclusive window"
			);
		}

		uint256 pnl;
		if (symbol.optionType == OptionType.PUT) {
			require(sig.settlementPrice < trade.strikePrice, "PartyBFacet: Invalid price");
			pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (trade.strikePrice - sig.settlementPrice)) / 1e18;
		} else {
			require(sig.settlementPrice > trade.strikePrice, "PartyBFacet: Invalid price");
			pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (sig.settlementPrice - trade.strikePrice)) / 1e18;
		}
		uint256 exerciseFee;
		{
			uint256 cap = (trade.exerciseFee.cap * pnl) / 1e18;
			uint256 fee = (trade.exerciseFee.rate * sig.settlementPrice * (trade.quantity - trade.closedAmountBeforeExpiration)) / 1e36;
			exerciseFee = cap < fee ? cap : fee;
		}
		uint256 amountToTransfer = pnl - exerciseFee;
		if (!symbol.isStableCoin) {
			amountToTransfer = (amountToTransfer * 1e18) / sig.settlementPrice;
		}

		trade.settledPrice = sig.settlementPrice;

		accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(symbol.collateral, amountToTransfer); //TODO: instantAdd or add?
		accountLayout.balances[trade.partyB][symbol.collateral].sub(amountToTransfer);

		trade.close(TradeStatus.EXERCISED, IntentStatus.CANCELED);
	}
}
