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

	function acceptCancelOpenIntent(uint256 intentId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		OpenIntent storage intent = IntentStorage.layout().openIntents[intentId];
		Symbol memory symbol = SymbolStorage.layout().symbols[intent.symbolId];
		require(intent.status == IntentStatus.CANCEL_PENDING, "PartyBFacet: Invalid state");
		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		accountLayout.lockedBalances[intent.partyA][symbol.collateral] -= LibIntent.getPremiumOfOpenIntent(intentId);

		// send trading Fee back to partyA
		uint256 fee = LibIntent.getTradingFee(intentId);
		if (intent.partyBsWhiteList.length == 1) {
			accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].scheduledAdd(intent.partyBsWhiteList[0], fee, block.timestamp);
		} else {
			accountLayout.balances[intent.partyA][intent.tradingFee.feeToken].instantAdd(fee);
		}

		LibIntent.removeFromPartyAOpenIntents(intentId);
		LibIntent.removeFromPartyBOpenIntents(intentId);
	}

	function acceptCancelCloseIntent(uint256 intentId) internal {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		CloseIntent storage intent = intentLayout.closeIntents[intentId];

		require(intent.status == IntentStatus.CANCEL_PENDING, "LibIntent: Invalid state");

		intent.statusModifyTimestamp = block.timestamp;
		intent.status = IntentStatus.CANCELED;
		LibIntent.removeFromActiveCloseIntents(intentId);
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
		trade.settledPrice = sig.settlementPrice;

		LibIntent.closeTrade(tradeId, TradeStatus.EXPIRED, IntentStatus.CANCELED);
	}

	function exerciseTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		require(sig.symbolId == trade.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.expirationTimestamp, "PartyBFacet: Trade isn't expired");
		require(
			AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.SOLVENT,
			"PartyBFacet: PartyB is liquidated"
		);

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

		accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(amountToTransfer); //CHECK: instantAdd or add?
		accountLayout.balances[trade.partyB][symbol.collateral].sub(amountToTransfer);

		LibIntent.closeTrade(tradeId, TradeStatus.EXERCISED, IntentStatus.CANCELED);
	}
}
