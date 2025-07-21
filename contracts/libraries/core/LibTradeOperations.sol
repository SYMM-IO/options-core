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
import { FeeManagementStorage } from "../../storages/FeeManagementStorage.sol";

import { CloseIntentStatus } from "../../types/IntentTypes.sol";
import { Symbol, OptionType } from "../../types/SymbolTypes.sol";
import { TradeSide, MarginType, FeeStructure } from "../../types/BaseTypes.sol";
import { Trade, TradeStatus, SettlementPriceSig } from "../../types/TradeTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { TradeErrors } from "../../errors/TradeErrors.sol";
import { ValidationErrors } from "../../errors/ValidationErrors.sol";

import { ITradeNFT } from "../../interfaces/ITradeNFT.sol";

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

		/* ---------------------------------------- CHECKS ---------------------------------------- */

		// Only the partyA can transfer the trade
		if (trade.partyA != sender) revert ValidationErrors.UnauthorizedSender(sender, trade.partyA);

		// Receiver cannot be zero address
		if (receiver == address(0)) revert ValidationErrors.ZeroAddress("receiver");

		// Receiver cannot be Party B
		if (receiver.isPartyB()) revert TradeErrors.ReceiverIsPartyB(receiver, trade.partyB);

		// Trade must be OPENED
		ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));

		// Cross-margin trades cannot be transferred
		if (trade.tradeAgreements.marginType == MarginType.CROSS) revert TradeErrors.CrossTradeTransferNotAllowed(tradeId);

		// Party B must be solvent
		trade.partyB.requireSolvent(address(0), symbol.collateral, MarginType.ISOLATED);

		/* ---------------------------------------- UPDATE ---------------------------------------- */

		trade.unregister();
		trade.partyA = receiver;
		trade.register();
	}

	function transferTrade(address receiver, uint256 tradeId) internal {
		validateAndTransferTrade(msg.sender, receiver, tradeId);
		if (AppStorage.layout().tradeNftAddress != address(0))
			ITradeNFT(AppStorage.layout().tradeNftAddress).transferTradeNFT(msg.sender, receiver, tradeId);
	}

	function transferTradeFromNFT(address sender, address receiver, uint256 tradeId) internal {
		if (msg.sender != AppStorage.layout().tradeNftAddress)
			revert ValidationErrors.UnauthorizedSender(msg.sender, AppStorage.layout().tradeNftAddress);
		validateAndTransferTrade(sender, receiver, tradeId);
	}

	function executeTrades(
		uint256[] calldata tradeIds,
		SettlementPriceSig calldata sig
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

			/* ---------------------------------------- BALANCES ---------------------------------------- */

			ScheduledReleaseBalance storage partyABalance = trade.partyA.balanceOf(symbol.collateral);
			ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(symbol.collateral);

			if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
				if (trade.tradeAgreements.marginType == MarginType.ISOLATED) {
					partyBBalance.instantIsolatedAdd(trade.calculateProportionalPremium(trade.getOpenAmount()), IncreaseBalanceReason.PREMIUM);
				} else {
					partyBBalance.scheduledAdd(
						trade.partyA,
						trade.calculateProportionalPremium(trade.getOpenAmount()),
						trade.tradeAgreements.marginType,
						IncreaseBalanceReason.PREMIUM
					);
				}
			} else {
				partyABalance.decreaseMM(trade.partyB, trade.calculateProportionalMM(trade.getOpenAmount()));
			}

			if (exercised[i]) {
				if (msg.sender != trade.partyB) {
					if (trade.tradeAgreements.expirationTimestamp + appLayout.partyBExclusiveWindow > block.timestamp)
						revert TradeErrors.PartyBExclusiveWindowNotOver(
							block.timestamp,
							trade.tradeAgreements.expirationTimestamp + appLayout.partyBExclusiveWindow
						);
				}

				uint256 pnl = trade.calculatePnl(sig.settlementPrice, trade.getOpenAmount());
				uint256 exerciseFee = trade.calculateExerciseFee(sig.settlementPrice, pnl);

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
					partyABalance.subForCounterParty(
						trade.partyB,
						amountToTransfer,
						trade.tradeAgreements.marginType,
						DecreaseBalanceReason.REALIZED_PNL
					);
					partyBBalance.scheduledAdd(trade.partyB, amountToTransfer, trade.tradeAgreements.marginType, IncreaseBalanceReason.REALIZED_PNL);
				}

				{
					FeeManagementStorage.Layout storage feeLayout = FeeManagementStorage.layout();
					FeeStructure memory s = trade.feeStructure;

					/* ---------------------------------------- GET FEES ---------------------------------------- */
					uint256 pnlInCollateral = (pnl * 1e18) / sig.collateralPrice;
					uint256[2] memory fees = [(pnlInCollateral * s.platformFee.closeFee) / 1e18, (pnlInCollateral * s.affiliateFee.closeFee) / 1e18];

					DecreaseBalanceReason[2] memory decReasons = [DecreaseBalanceReason.PLATFORM_FEE, DecreaseBalanceReason.AFFILIATE_FEE];

					for (uint8 j; j < 2; ++j)
						partyABalance.subForCounterParty(trade.partyB, fees[j], trade.tradeAgreements.marginType, decReasons[j]);

					/* ---------------------------------------- PAY FEES ---------------------------------------- */

					// Determine affiliate fee collector (use default if none specified)
					address affiliateFeeCollector = feeLayout.affiliateFeeCollector[trade.affiliate] == address(0)
						? feeLayout.defaultFeeCollector
						: feeLayout.affiliateFeeCollector[trade.affiliate];

					// Pay affiliate fees
					ScheduledReleaseBalance storage affiliateFeeCollectorBalance = affiliateFeeCollector.balanceOf(symbol.collateral);
					affiliateFeeCollectorBalance.setup(affiliateFeeCollector, symbol.collateral);
					affiliateFeeCollectorBalance.instantIsolatedAdd(fees[1], IncreaseBalanceReason.AFFILIATE_FEE);

					// Pay platform fees
					ScheduledReleaseBalance storage defaultFeeCollectorBalance = feeLayout.defaultFeeCollector.balanceOf(symbol.collateral);
					defaultFeeCollectorBalance.setup(feeLayout.defaultFeeCollector, symbol.collateral);
					defaultFeeCollectorBalance.instantIsolatedAdd(fees[0], IncreaseBalanceReason.PLATFORM_FEE);
				}

				trade.close(TradeStatus.EXERCISED, CloseIntentStatus.CANCELED);
			}

			/* ---------------------------------------- NONCE ---------------------------------------- */

			if (trade.tradeAgreements.marginType == MarginType.CROSS) {
				accountLayout.nonces[trade.partyA][trade.partyB] += 1;
				accountLayout.nonces[trade.partyB][trade.partyA] += 1;
			}
		}
	}

	function mintNFTForTrade(uint256 tradeId) internal {
		Trade storage trade = TradeStorage.layout().trades[tradeId];
		if (trade.tradeAgreements.marginType == MarginType.CROSS) revert TradeErrors.NFTMintingNotAllowedForCrossMarginTrade(tradeId);
		ITradeNFT(AppStorage.layout().tradeNftAddress).mintNFTForTrade(trade.partyA, tradeId);
	}
}
