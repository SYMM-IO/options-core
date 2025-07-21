// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023‑2025 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal‑disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../models/LibParty.sol";
import { LibTradeOps } from "../models/LibTrade.sol";
import { ScheduledReleaseBalanceOps } from "../models/LibScheduledReleaseBalance.sol";
import { LibOpenIntentOps } from "../models/LibOpenIntent.sol";
import { LibCloseIntentOps } from "../models/LibCloseIntent.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";
import { OpenIntentStorage } from "../../storages/OpenIntentStorage.sol";
import { CloseIntentStorage } from "../../storages/CloseIntentStorage.sol";
import { SymbolStorage } from "../../storages/SymbolStorage.sol";

import { MarginType, TradeSide } from "../../types/BaseTypes.sol";
import { OpenIntentStatus, CloseIntentStatus, OpenIntent, CloseIntent } from "../../types/IntentTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Withdraw, WithdrawStatus } from "../../types/WithdrawTypes.sol";
import { LiquidationStatus, LiquidationDetail, LiquidationSide } from "../../types/LiquidationTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason, CrossEntry } from "../../types/BalanceTypes.sol";

import { ValidationErrors } from "../../errors/ValidationErrors.sol";
import { LiquidationErrors } from "../../errors/LiquidationErrors.sol";
import { BalanceErrors } from "../../errors/BalanceErrors.sol";

library LibClearingHouse {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibParty for address;
	using LibOpenIntentOps for OpenIntent;
	using LibCloseIntentOps for CloseIntent;

	// =============================================================
	//                      ✨  Internal helpers  ✨
	// =============================================================

	/**
	 * @dev Creates a new liquidation entry and stores the mapping key.
	 */
	function _flag(address partyA, address partyB, address collateral, LiquidationSide side) private returns (LiquidationDetail storage detail) {
		LiquidationStorage.Layout storage l = LiquidationStorage.layout();
		uint256 liquidationId = ++l.lastLiquidationId;
		l.inProgressLiquidationIds[partyA][partyB][collateral] = liquidationId;
		detail = l.liquidationDetails[liquidationId];
		detail.status = LiquidationStatus.FLAGGED;
		detail.flagTimestamp = block.timestamp;
		detail.flagger = msg.sender;
		detail.collateral = collateral;
		detail.partyA = partyA;
		detail.partyB = partyB;
		detail.side = side;
		// upnl & collateralPrice start at 0
	}

	/**
	 * @dev Common body for un‑flagging.
	 */
	function _unflag(address partyA, address partyB, address collateral) private {
		LiquidationStorage.Layout storage l = LiquidationStorage.layout();
		LiquidationDetail storage detail = _detail(partyA, partyB, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);
		l.inProgressLiquidationIds[partyA][partyB][collateral] = 0;
		detail.status = LiquidationStatus.CANCELLED;
	}

	/**
	 * @dev Fetches the liquidation detail for a (partyA, partyB, collateral) triple.
	 */
	function _detail(address partyA, address partyB, address collateral) private view returns (LiquidationDetail storage) {
		LiquidationStorage.Layout storage layout = LiquidationStorage.layout();
		return layout.liquidationDetails[layout.inProgressLiquidationIds[partyA][partyB][collateral]];
	}

	/**
	 * @dev Reverts when the liquidation is not in the expected status.
	 */
	function _requireStatus(LiquidationDetail storage detail, LiquidationStatus expected) private view {
		ValidationErrors.requireStatus("LiquidationStatus", uint8(detail.status), uint8(expected));
	}

	/**
	 * @dev Marks a FLAGGED liquidation as IN_PROGRESS and stores the execution price.
	 */
	function _beginLiquidation(LiquidationDetail storage detail, uint256 collateralPrice) private {
		detail.status = LiquidationStatus.IN_PROGRESS;
		detail.collateralPrice = collateralPrice;
	}

	// =============================================================
	//                 📍  Party B – Isolated  📍
	// =============================================================

	function flagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert LiquidationErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		_flag(address(0), partyB, collateral, LiquidationSide.PARTY_B);
	}

	function unflagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		_unflag(address(0), partyB, collateral);
	}

	function liquidateIsolatedPartyB(address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = _detail(address(0), partyB, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		uint256 isolatedBalance = partyB.balanceOf(collateral).isolatedBalance;

		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;
		if (int256(isolatedBalance) + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0) {
			revert LiquidationErrors.PartyBSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                 📍  Party B – Cross margin  📍
	// =============================================================

	function flagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert LiquidationErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(partyA, collateral, MarginType.CROSS);

		_flag(partyA, partyB, collateral, LiquidationSide.PARTY_B);
	}

	function unflagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		_unflag(partyA, partyB, collateral);
	}

	function liquidateCrossPartyB(address partyB, address partyA, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = _detail(partyA, partyB, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		ScheduledReleaseBalance storage balB = partyB.balanceOf(collateral);
		CrossEntry storage crossBalance = balB.crossBalance[partyA];

		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;
		if (crossBalance.balance + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0) {
			revert LiquidationErrors.PartyBSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			partyA.balanceOf(collateral).subForCounterParty(
				partyB,
				uint256(crossBalance.balance),
				MarginType.CROSS,
				DecreaseBalanceReason.LIQUIDATION
			);
			balB.scheduledAdd(partyA, uint256(crossBalance.balance), MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossBalance.balance = 0;
		crossBalance.locked = 0;
		crossBalance.totalMM = 0;

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                       📍  Party A                        📍
	// =============================================================

	function flagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		partyA.requireSolvent(partyB, collateral, MarginType.CROSS);
		_flag(partyA, partyB, collateral, LiquidationSide.PARTY_A);
	}

	function unflagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		_unflag(partyA, partyB, collateral);
	}

	function liquidateCrossPartyA(uint256 liquidationId, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		ScheduledReleaseBalance storage balA = detail.partyA.balanceOf(detail.collateral);
		CrossEntry storage crossBalance = balA.crossBalance[detail.partyB];

		if ((crossBalance.balance - int256(crossBalance.totalMM)) + (upnl * 1e18) / int256(collateralPrice) >= 0) {
			revert LiquidationErrors.PartyASolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			ScheduledReleaseBalance storage balB = detail.partyB.balanceOf(detail.collateral);
			balA.subForCounterParty(detail.partyB, uint256(crossBalance.balance), MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			balB.scheduledAdd(detail.partyB, uint256(crossBalance.balance), MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossBalance.balance = 0;
		crossBalance.locked = 0;
		crossBalance.totalMM = 0;

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                       🔄  Shared 🔄
	// =============================================================

	function closeTrades(uint256 liquidationId, uint256[] calldata tradeIds, uint256[] calldata prices) internal {
		if (tradeIds.length != prices.length) revert LiquidationErrors.MismatchedArrayLengths(tradeIds.length, prices.length);

		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = TradeStorage.layout().trades[tradeIds[i]];
			uint256 price = prices[i];

			ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));
			if (trade.partyA != detail.partyA || trade.partyB != detail.partyB) {
				revert LiquidationErrors.TradeNotInLiquidation(liquidationId, trade.id);
			}

			if (trade.tradeAgreements.tradeSide == TradeSide.BUY) {
				ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(
					SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId].collateral
				);

				if (trade.tradeAgreements.marginType == MarginType.ISOLATED) {
					partyBBalance.instantIsolatedAdd(
						trade.calculateProportionalPremium(trade.getOpenAmount()),
						IncreaseBalanceReason.PREMIUM
					);
				} else {
					partyBBalance.scheduledAdd(
						trade.partyA,
						trade.calculateProportionalPremium(trade.getOpenAmount()),
						trade.tradeAgreements.marginType,
						IncreaseBalanceReason.PREMIUM
					);
				}
			} else {
				trade.partyA.balanceOf(SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId].collateral).decreaseMM(
					trade.partyB,
					trade.calculateProportionalMM(trade.getOpenAmount())
				);
			}

			trade.settledPrice = price;
			trade.close(TradeStatus.LIQUIDATED, CloseIntentStatus.CANCELED);
		}
	}

	function allocateFromReserveToCross(address party, address counterParty, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage balance = party.balanceOf(collateral);
		if (balance.reserveBalance < amount) revert BalanceErrors.InsufficientBalance(party, collateral, amount, balance.reserveBalance);
		balance.reserveBalance -= amount;
		balance.scheduledAdd(counterParty, amount, MarginType.CROSS, IncreaseBalanceReason.ALLOCATE_FROM_RESERVE);
	}

	function confiscatePartyA(uint256 liquidationId, uint256 amount) internal {
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];

		ScheduledReleaseBalance storage balance = detail.partyA.balanceOf(detail.collateral);

		int256 counterPartyBalance = balance.counterPartyBalance(detail.partyB, MarginType.CROSS);
		if (counterPartyBalance < int256(amount))
			revert BalanceErrors.InsufficientIntBalance(detail.partyA, detail.collateral, amount, counterPartyBalance);

		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);

		balance.subForCounterParty(detail.partyB, amount, MarginType.CROSS, DecreaseBalanceReason.CONFISCATE);
	}

	function confiscatePartyBWithdrawal(uint256 withdrawId) internal {
		Withdraw storage withdrawal = AccountStorage.layout().withdrawals[withdrawId];
		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED));
		withdrawal.status = WithdrawStatus.CANCELED;
		withdrawal.user.balanceOf(withdrawal.collateral).instantIsolatedAdd(withdrawal.amount, IncreaseBalanceReason.DEPOSIT);
	}

	function distributeCollateral(
		address partyB,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] calldata amounts
	) internal {
		if (partyAs.length != amounts.length) revert LiquidationErrors.MismatchedArrayLengths(partyAs.length, amounts.length);

		ScheduledReleaseBalance storage balanceB = partyB.balanceOf(collateral);

		uint256 totalAmount = 0;
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			uint256 amount = amounts[i];
			totalAmount += amount;

			// Subtract from partyB's balance
			balanceB.subForCounterParty(partyA, amount, marginType, DecreaseBalanceReason.LIQUIDATION);

			// Add to partyA's balance
			partyA.balanceOf(collateral).scheduledAdd(partyB, amount, marginType, IncreaseBalanceReason.LIQUIDATION);
		}

		if (balanceB.counterPartyBalance(partyB, marginType) < int256(totalAmount)) {
			revert BalanceErrors.InsufficientIntBalance(partyB, collateral, totalAmount, balanceB.counterPartyBalance(partyB, marginType));
		}
	}

	function cancelOpenIntents(uint256[] calldata intentIds) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		for (uint256 i = 0; i < intentIds.length; i++) {
			OpenIntent storage intent = openIntentLayout.openIntents[intentIds[i]];

			if (!(intent.status == OpenIntentStatus.PENDING || intent.status == OpenIntentStatus.LOCKED)) {
				uint8[] memory requiredStatuses = new uint8[](2);
				requiredStatuses[0] = uint8(OpenIntentStatus.PENDING);
				requiredStatuses[1] = uint8(OpenIntentStatus.LOCKED);

				revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(intent.status), requiredStatuses);
			}
			address collateral = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral;
			bool partyAIsSolvent = intent.partyA.isSolvent(intent.partyB, collateral, intent.tradeAgreements.marginType);
			bool partyBIsSolvent = intent.partyB.isSolvent(intent.partyA, collateral, intent.tradeAgreements.marginType);

			if (partyAIsSolvent && partyBIsSolvent) {
				revert LiquidationErrors.PartiesNotInLiquidation(intent.partyA, intent.partyB, collateral);
			}

			if (block.timestamp > intent.deadline) {
				intent.expire();
			} else {
				intent.status = OpenIntentStatus.CANCELED;
				intent.unlockFees();
				intent.unlockPremiumIfBuy();
				intent.unlockMMIfSell();
				intent.unregister(false);
			}
			intent.statusModifyTimestamp = block.timestamp;
		}
	}

	function cancelCloseIntents(uint256[] calldata intentIds) internal {
		CloseIntentStorage.Layout storage closeIntentLayout = CloseIntentStorage.layout();
		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();

		for (uint256 i = 0; i < intentIds.length; i++) {
			CloseIntent storage intent = closeIntentLayout.closeIntents[intentIds[i]];
			Trade memory trade = tradeLayout.trades[intent.tradeId];
			ValidationErrors.requireStatus("CloseIntentStatus", uint8(intent.status), uint8(CloseIntentStatus.PENDING));

			address collateral = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId].collateral;
			bool partyAIsSolvent = trade.partyA.isSolvent(trade.partyB, collateral, trade.tradeAgreements.marginType);
			bool partyBIsSolvent = trade.partyB.isSolvent(trade.partyA, collateral, trade.tradeAgreements.marginType);

			if (partyAIsSolvent && partyBIsSolvent) {
				revert LiquidationErrors.PartiesNotInLiquidation(trade.partyA, trade.partyB, collateral);
			}

			if (block.timestamp > intent.deadline) {
				intent.expire();
			} else {
				intent.status = CloseIntentStatus.CANCELED;
				intent.statusModifyTimestamp = block.timestamp;
				intent.unregister();
			}
		}
	}
}
