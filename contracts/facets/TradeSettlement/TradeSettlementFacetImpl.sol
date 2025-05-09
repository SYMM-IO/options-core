// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibMuon } from "../../libraries/LibMuon.sol";
import { LibParty } from "../../libraries/LibParty.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { IntentStatus } from "../../types/IntentTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Symbol, OptionType } from "../../types/SymbolTypes.sol";
import { SettlementPriceSig } from "../../types/SettlementTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { TradeSettlementFacetErrors } from "./TradeSettlementFacetErrors.sol";

library TradeSettlementFacetImpl {
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

		if (sig.symbolId != trade.tradeAgreements.symbolId)
			revert TradeSettlementFacetErrors.InvalidSymbolId(sig.symbolId, trade.tradeAgreements.symbolId);

		CommonErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		if (block.timestamp <= trade.tradeAgreements.expirationTimestamp)
			revert TradeSettlementFacetErrors.TradeNotExpired(tradeId, block.timestamp, trade.tradeAgreements.expirationTimestamp);

		if (symbol.optionType == OptionType.PUT) {
			if (sig.settlementPrice < trade.tradeAgreements.strikePrice) {
				isExpired = false;
			} else {
				trade.settledPrice = sig.settlementPrice;
				trade.close(TradeStatus.EXPIRED, IntentStatus.CANCELED);
				isExpired = true;
			}
		} else {
			// == OptionType.CALL
			if (sig.settlementPrice > trade.tradeAgreements.strikePrice) {
				isExpired = false;
			} else {
				trade.settledPrice = sig.settlementPrice;
				trade.close(TradeStatus.EXPIRED, IntentStatus.CANCELED);
				isExpired = true;
			}
		}

		if (!isExpired) {
			if (msg.sender != trade.partyB) {
				if (trade.tradeAgreements.expirationTimestamp + appLayout.ownerExclusiveWindow > block.timestamp)
					revert TradeSettlementFacetErrors.OwnerExclusiveWindowActive(
						block.timestamp,
						trade.tradeAgreements.expirationTimestamp + appLayout.ownerExclusiveWindow
					);
			}

			uint256 pnl = trade.getPnl(sig.settlementPrice, trade.getOpenAmount());

			uint256 exerciseFee = trade.getExerciseFee(sig.settlementPrice, pnl);
			uint256 amountToTransfer = pnl - exerciseFee;

			amountToTransfer = (amountToTransfer * 1e18) / sig.collateralPrice;

			trade.settledPrice = sig.settlementPrice;

			if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
				if (trade.tradeAgreements.marginType == MarginType.ISOLATED) {
					accountLayout.balances[trade.partyB][symbol.collateral].instantIsolatedAdd(
						(trade.getPremium() * trade.getOpenAmount()) / trade.tradeAgreements.quantity,
						IncreaseBalanceReason.PREMIUM
					);
				} else {
					accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
						trade.partyA,
						(trade.getPremium() * trade.getOpenAmount()) / trade.tradeAgreements.quantity,
						trade.tradeAgreements.marginType,
						IncreaseBalanceReason.PREMIUM
					);
				}
				accountLayout.balances[trade.partyB][symbol.collateral].subForCounterParty(
					trade.partyA,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					DecreaseBalanceReason.REALIZED_PNL
				);
				accountLayout.balances[trade.partyA][symbol.collateral].scheduledAdd(
					trade.partyA,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					IncreaseBalanceReason.REALIZED_PNL
				);
			} else {
				if (trade.tradeAgreements.marginType == MarginType.CROSS) {
					accountLayout.balances[trade.partyA][symbol.collateral].decreaseMM(
						trade.partyB,
						(trade.tradeAgreements.mm * trade.getOpenAmount()) / trade.tradeAgreements.quantity
					);
				}
				accountLayout.balances[trade.partyA][symbol.collateral].subForCounterParty(
					trade.partyB,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					DecreaseBalanceReason.REALIZED_PNL
				);
				accountLayout.balances[trade.partyB][symbol.collateral].scheduledAdd(
					trade.partyB,
					amountToTransfer,
					trade.tradeAgreements.marginType,
					IncreaseBalanceReason.REALIZED_PNL
				);
			}

			trade.close(TradeStatus.EXERCISED, IntentStatus.CANCELED);
		}
		if (trade.tradeAgreements.marginType == MarginType.CROSS) {
			accountLayout.nonces[trade.partyA][trade.partyB] += 1;
			accountLayout.nonces[trade.partyB][trade.partyA] += 1;
		}
	}
}
