// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibMuon } from "../../libraries/LibMuon.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { SettlementPriceSig, AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { Trade, IntentStorage, TradeStatus, IntentStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage, OptionType } from "../../storages/SymbolStorage.sol";

library TradeSettlementFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibPartyB for address;

	function expireTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		trade.partyB.requireSolvent(symbol.collateral);
		require(sig.symbolId == trade.tradeAgreements.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.tradeAgreements.expirationTimestamp, "PartyBFacet: Trade isn't expired");

		if (symbol.optionType == OptionType.PUT) {
			require(sig.settlementPrice >= trade.tradeAgreements.strikePrice, "PartyBFacet: Invalid price");
		} else {
			require(sig.settlementPrice <= trade.tradeAgreements.strikePrice, "PartyBFacet: Invalid price");
		}
		if (msg.sender != trade.partyB) {
			require(
				trade.tradeAgreements.expirationTimestamp + AppStorage.layout().ownerExclusiveWindow <= block.timestamp,
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
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		trade.partyB.requireSolvent(symbol.collateral);
		require(sig.symbolId == trade.tradeAgreements.symbolId, "PartyBFacet: Invalid symbolId");
		require(trade.status == TradeStatus.OPENED, "PartyBFacet: Invalid trade state");
		require(block.timestamp > trade.tradeAgreements.expirationTimestamp, "PartyBFacet: Trade isn't expired");

		if (msg.sender != trade.partyB) {
			require(
				trade.tradeAgreements.expirationTimestamp + appLayout.ownerExclusiveWindow <= block.timestamp,
				"PartyBFacet: Third parties should wait for owner exclusive window"
			);
		}

		uint256 pnl = trade.getPnl(sig.settlementPrice, trade.getOpenAmount());
		require(pnl > 0, "PartyBFacet: Can't exercise with this price");

		uint256 exerciseFee = trade.getExerciseFee(sig.settlementPrice, pnl);
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
