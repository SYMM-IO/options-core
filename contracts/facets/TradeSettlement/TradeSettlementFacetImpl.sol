// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibMuon } from "../../libraries/LibMuon.sol";
import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance, IncreaseBalanceType, DecreaseBalanceType } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { SettlementPriceSig, AppStorage, LiquidationStatus } from "../../storages/AppStorage.sol";
import { Trade, IntentStorage, TradeStatus, IntentStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage, OptionType } from "../../storages/SymbolStorage.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { TradeSettlementFacetErrors } from "./TradeSettlementFacetErrors.sol";

library TradeSettlementFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibPartyB for address;

	function expireTrade(uint256 tradeId, SettlementPriceSig memory sig) internal {
		Trade storage trade = IntentStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
		LibMuon.verifySettlementPriceSig(sig);
		trade.partyB.requireSolvent(symbol.collateral);

		if (sig.symbolId != trade.tradeAgreements.symbolId)
			revert TradeSettlementFacetErrors.InvalidSymbolId(sig.symbolId, trade.tradeAgreements.symbolId);

		if (trade.status != TradeStatus.OPENED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(TradeStatus.OPENED);
			revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
		}

		if (block.timestamp <= trade.tradeAgreements.expirationTimestamp)
			revert TradeSettlementFacetErrors.TradeNotExpired(tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (symbol.optionType == OptionType.PUT) {
			if (sig.settlementPrice < trade.tradeAgreements.strikePrice)
				revert TradeSettlementFacetErrors.InvalidSettlementPrice(sig.settlementPrice, trade.tradeAgreements.strikePrice, true);
		} else {
			if (sig.settlementPrice > trade.tradeAgreements.strikePrice)
				revert TradeSettlementFacetErrors.InvalidSettlementPrice(sig.settlementPrice, trade.tradeAgreements.strikePrice, false);
		}

		if (msg.sender != trade.partyB) {
			if (trade.tradeAgreements.expirationTimestamp + AppStorage.layout().ownerExclusiveWindow > block.timestamp)
				revert TradeSettlementFacetErrors.OwnerExclusiveWindowActive(
					block.timestamp,
					trade.tradeAgreements.expirationTimestamp + AppStorage.layout().ownerExclusiveWindow
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

		if (sig.symbolId != trade.tradeAgreements.symbolId)
			revert TradeSettlementFacetErrors.InvalidSymbolId(sig.symbolId, trade.tradeAgreements.symbolId);

		if (trade.status != TradeStatus.OPENED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(TradeStatus.OPENED);
			revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
		}

		if (block.timestamp <= trade.tradeAgreements.expirationTimestamp)
			revert TradeSettlementFacetErrors.TradeNotExpired(tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (msg.sender != trade.partyB) {
			if (trade.tradeAgreements.expirationTimestamp + appLayout.ownerExclusiveWindow > block.timestamp)
				revert TradeSettlementFacetErrors.OwnerExclusiveWindowActive(
					block.timestamp,
					trade.tradeAgreements.expirationTimestamp + appLayout.ownerExclusiveWindow
				);
		}

		uint256 pnl = trade.getPnl(sig.settlementPrice, trade.getOpenAmount());
		if (pnl <= 0) revert TradeSettlementFacetErrors.CannotExerciseWithPrice(tradeId, sig.settlementPrice, pnl);

		uint256 exerciseFee = trade.getExerciseFee(sig.settlementPrice, pnl);
		uint256 amountToTransfer = pnl - exerciseFee;
		if (!symbol.isStableCoin) {
			amountToTransfer = (amountToTransfer * 1e18) / sig.settlementPrice;
		}

		trade.settledPrice = sig.settlementPrice;
		accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(amountToTransfer, IncreaseBalanceType.REALIZED_PNL); //TODO: instantAdd or add?
		accountLayout.balances[trade.partyB][symbol.collateral].sub(amountToTransfer, DecreaseBalanceType.REALIZED_PNL);
		trade.close(TradeStatus.EXERCISED, IntentStatus.CANCELED);
	}
}
