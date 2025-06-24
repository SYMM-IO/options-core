// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibMuon } from "../../libraries/services/LibMuon.sol";
import { LibParty } from "../../libraries/models/LibParty.sol";
import { LibTradeOps } from "../../libraries/models/LibTrade.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { CloseIntentStatus } from "../../types/IntentTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Symbol, OptionType } from "../../types/SymbolTypes.sol";
import { SettlementPriceSig } from "../../types/SettlementTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { TradeErrors } from "../../errors/TradeErrors.sol";

library LibTradeSettlement {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibParty for address;

	function executeTrade(uint256 tradeId, SettlementPriceSig memory sig) internal returns (bool isExpired) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
		LibMuon.verifySettlementPriceSig(sig);

		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			trade.partyA.requireSolvent(trade.partyB, symbol.collateral, trade.tradeAgreements.marginType);
			trade.partyB.requireSolvent(trade.partyA, symbol.collateral, trade.tradeAgreements.marginType);
		} else {
			trade.partyB.requireSolvent(address(0), symbol.collateral, trade.tradeAgreements.marginType);
		}

		if (sig.symbolId != trade.tradeAgreements.symbolId) revert TradeErrors.MismatchedSymbolId(sig.symbolId, trade.tradeAgreements.symbolId);

		ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		if (block.timestamp <= trade.tradeAgreements.expirationTimestamp)
			revert TradeErrors.TradeNotYetExpired(tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (symbol.optionType == OptionType.PUT) {
			if (sig.settlementPrice < trade.tradeAgreements.strikePrice) {
				isExpired = false;
			} else {
				trade.settledPrice = sig.settlementPrice;
				trade.close(TradeStatus.EXPIRED, CloseIntentStatus.CANCELED);
				isExpired = true;
			}
		} else {
			if (sig.settlementPrice > trade.tradeAgreements.strikePrice) {
				isExpired = false;
			} else {
				trade.settledPrice = sig.settlementPrice;
				trade.close(TradeStatus.EXPIRED, CloseIntentStatus.CANCELED);
				isExpired = true;
			}
		}

		ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
		ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

		if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
			if (trade.tradeAgreements.marginType == MarginType.ISOLATED) {
				partyBBalance.instantIsolatedAdd(
					(trade.getPremium() * trade.getOpenAmount()) / trade.tradeAgreements.quantity,
					IncreaseBalanceReason.PREMIUM
				);
			} else {
				partyBBalance.scheduledAdd(
					trade.partyA,
					(trade.getPremium() * trade.getOpenAmount()) / trade.tradeAgreements.quantity,
					trade.tradeAgreements.marginType,
					IncreaseBalanceReason.PREMIUM
				);
			}
		}

		if (!isExpired) {
			if (msg.sender != trade.partyB) {
				if (trade.tradeAgreements.expirationTimestamp + appLayout.partyBExclusiveWindow > block.timestamp)
					revert TradeErrors.PartyBExclusiveWindowNotOver(
						block.timestamp,
						trade.tradeAgreements.expirationTimestamp + appLayout.partyBExclusiveWindow
					);
			}

			uint256 pnl = trade.getPnl(sig.settlementPrice, trade.getOpenAmount());

			uint256 exerciseFee = trade.getExerciseFee(sig.settlementPrice, pnl);
			uint256 amountToTransfer = pnl - exerciseFee;

			amountToTransfer = (amountToTransfer * 1e18) / sig.collateralPrice;

			trade.settledPrice = sig.settlementPrice;

			if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
				partyBBalance.subForCounterParty(
					trade.partyA,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					DecreaseBalanceReason.REALIZED_PNL
				);
				partyABalance.scheduledAdd(trade.partyB, amountToTransfer, trade.tradeAgreements.marginType, IncreaseBalanceReason.REALIZED_PNL);
			} else {
				if (trade.tradeAgreements.marginType == MarginType.CROSS)
					partyABalance.decreaseMM(trade.partyB, (trade.tradeAgreements.mm * trade.getOpenAmount()) / trade.tradeAgreements.quantity);
				partyABalance.subForCounterParty(
					trade.partyB,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					DecreaseBalanceReason.REALIZED_PNL
				);
				partyBBalance.scheduledAdd(trade.partyB, amountToTransfer, trade.tradeAgreements.marginType, IncreaseBalanceReason.REALIZED_PNL);
			}

			trade.close(TradeStatus.EXERCISED, CloseIntentStatus.CANCELED);
		}
		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}
	}
}
