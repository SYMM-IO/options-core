// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { LibMuon } from "../services/LibMuon.sol";
import { LibParty } from "../models/LibParty.sol";
import { LibTradeOps } from "../models/LibTrade.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";

import { CloseIntentStatus } from "../../types/IntentTypes.sol";
import { Symbol, OptionType } from "../../types/SymbolTypes.sol";
import { TradeSide, MarginType } from "../../types/BaseTypes.sol";
import { Trade, TradeStatus, SettlementPriceSig } from "../../types/TradeTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { TradeErrors } from "../../errors/TradeErrors.sol";
import { ValidationErrors } from "../../errors/ValidationErrors.sol";

import { ITradeNFT } from "../../interfaces/ITradeNFT.sol";
import { IMultiAccount } from "../../interfaces/IMultiAccount.sol";

library LibTradeOperations {
	using LibTradeOps for Trade;
	using LibParty for address;
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;

	/**
	 * @dev Shared logic for both diamond-initiated and NFT-initiated trade transfers.
	 */
	function validateAndTransferTrade(address sender, address receiver, uint256 tradeId) internal {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		Symbol memory symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];

		if (trade.partyA != sender) revert ValidationErrors.UnauthorizedSender(sender, trade.partyA);
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
		if (AppStorage.layout().tradeNftAddress != address(0))
			ITradeNFT(AppStorage.layout().tradeNftAddress).transferNFTInitiatedInSymmio(msg.sender, receiver, tradeId);
	}

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) internal {
		if (msg.sender != AppStorage.layout().tradeNftAddress)
			revert ValidationErrors.UnauthorizedSender(msg.sender, AppStorage.layout().tradeNftAddress);
		validateAndTransferTrade(sender, receiver, tradeId);
	}

	function executeTrades(
		uint256[] memory tradeIds,
		SettlementPriceSig memory sig
	) internal returns (bool[] memory exercised, bool[] memory expired) {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		LibMuon.verifySettlementPriceSig(sig);

		Symbol storage symbol = SymbolStorage.layout().symbols[sig.symbolId];

		exercised = new bool[](tradeIds.length);
		expired = new bool[](tradeIds.length);

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = TradeStorage.layout().trades[tradeIds[i]];

			// If the trade is already exercised or expired by another party, we don't need to do anything
			if (trade.status == TradeStatus.EXERCISED || trade.status == TradeStatus.EXPIRED) {
				exercised[i] = false;
				expired[i] = false;
				continue;
			}

			if (trade.tradeAgreements.marginType == MarginType.CROSS) {
				trade.partyA.requireSolvent(trade.partyB, symbol.collateral, trade.tradeAgreements.marginType);
				trade.partyB.requireSolvent(trade.partyA, symbol.collateral, trade.tradeAgreements.marginType);
			} else {
				trade.partyB.requireSolvent(address(0), symbol.collateral, trade.tradeAgreements.marginType);
			}

			if (sig.symbolId != trade.tradeAgreements.symbolId) revert TradeErrors.MismatchedSymbolId(sig.symbolId, trade.tradeAgreements.symbolId);

			ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

			if (block.timestamp <= trade.tradeAgreements.expirationTimestamp)
				revert TradeErrors.TradeNotYetExpired(tradeIds[i], block.timestamp, trade.tradeAgreements.expirationTimestamp);

			if (symbol.optionType == OptionType.PUT) {
				if (sig.settlementPrice < trade.tradeAgreements.strikePrice) {
					exercised[i] = true;
				} else {
					trade.settledPrice = sig.settlementPrice;
					trade.close(TradeStatus.EXPIRED, CloseIntentStatus.CANCELED);
					expired[i] = true;
				}
			} else {
				if (sig.settlementPrice > trade.tradeAgreements.strikePrice) {
					exercised[i] = true;
				} else {
					trade.settledPrice = sig.settlementPrice;
					trade.close(TradeStatus.EXPIRED, CloseIntentStatus.CANCELED);
					expired[i] = true;
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

			if (exercised[i]) {
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

	function mintNFTForTrade(uint256 tradeId) internal {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		ITradeNFT(AppStorage.layout().tradeNftAddress).mintNFTForTrade(trade.partyA, tradeId);
	}
}
