// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023‑2025 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal‑disclaimer/license
pragma solidity >=0.8.19;

import { LibBucket } from "./LibBucket.sol";
import { IClearingHouseEvents } from "../../facets/ClearingHouse/IClearingHouseEvents.sol";

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

import { MarginType, TradeSide, TradeAgreements } from "../../types/BaseTypes.sol";
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
	//                  ✨  Internal helpers  ✨
	// =============================================================

	/**
	 * @dev Creates a new liquidation entry and stores the mapping key.
	 */
	function _liquidationId(address partyA, uint256 bucketA, address partyB, uint256 bucketB, address collateral) private view returns (uint256) {
		LiquidationStorage.Layout storage layout = LiquidationStorage.layout();
		if (bucketA == 0 && bucketB == 0) return layout.inProgressLiquidationIds[partyA][partyB][collateral];
		return layout.bucketInProgressLiquidationIds[partyA][bucketA][partyB][bucketB][collateral];
	}

	function _setLiquidationId(address partyA, uint256 bucketA, address partyB, uint256 bucketB, address collateral, uint256 id) private {
		LiquidationStorage.Layout storage layout = LiquidationStorage.layout();
		if (bucketA == 0 && bucketB == 0) layout.inProgressLiquidationIds[partyA][partyB][collateral] = id;
		else layout.bucketInProgressLiquidationIds[partyA][bucketA][partyB][bucketB][collateral] = id;
	}

	function _flag(
		address partyA,
		uint256 bucketA,
		address partyB,
		uint256 bucketB,
		address collateral,
		LiquidationSide side,
		bool nativeBucket
	) private returns (LiquidationDetail storage detail) {
		LiquidationStorage.Layout storage layout = LiquidationStorage.layout();
		uint256 id = ++layout.lastLiquidationId;
		_setLiquidationId(partyA, bucketA, partyB, bucketB, collateral, id);
		detail = layout.liquidationDetails[id];
		detail.status = LiquidationStatus.FLAGGED;
		detail.flagTimestamp = block.timestamp;
		detail.flagger = msg.sender;
		detail.collateral = collateral;
		detail.partyA = partyA;
		detail.partyABucketId = bucketA;
		detail.partyB = partyB;
		detail.partyBBucketId = bucketB;
		detail.isBucketLiquidation = nativeBucket;
		detail.side = side;
		_emitBucketStatus(id, detail);
	}

	function _unflag(address partyA, uint256 bucketA, address partyB, uint256 bucketB, address collateral) private {
		LiquidationDetail storage detail = _detail(partyA, bucketA, partyB, bucketB, collateral);
		if (detail.status != LiquidationStatus.FLAGGED && detail.status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory expected = new uint8[](2);
			expected[0] = uint8(LiquidationStatus.FLAGGED);
			expected[1] = uint8(LiquidationStatus.IN_PROGRESS);
			revert ValidationErrors.InvalidState("LiquidationStatus", uint8(detail.status), expected);
		}
		uint256 id = _liquidationId(partyA, bucketA, partyB, bucketB, collateral);
		_setLiquidationId(partyA, bucketA, partyB, bucketB, collateral, 0);
		detail.status = LiquidationStatus.CANCELLED;
		_emitBucketStatus(id, detail);
	}

	function _detail(
		address partyA,
		uint256 bucketA,
		address partyB,
		uint256 bucketB,
		address collateral
	) private view returns (LiquidationDetail storage) {
		return LiquidationStorage.layout().liquidationDetails[_liquidationId(partyA, bucketA, partyB, bucketB, collateral)];
	}

	function _matchesPair(
		LiquidationDetail storage detail,
		address party,
		uint256 bucket,
		address counterParty,
		uint256 counterBucket
	) private view returns (bool) {
		return
			(party == detail.partyA && bucket == detail.partyABucketId && counterParty == detail.partyB && counterBucket == detail.partyBBucketId) ||
			(party == detail.partyB && bucket == detail.partyBBucketId && counterParty == detail.partyA && counterBucket == detail.partyABucketId);
	}

	function _emitBucketStatus(uint256 id, LiquidationDetail storage detail) private {
		if (detail.isBucketLiquidation)
			emit IClearingHouseEvents.BucketLiquidationStatusChanged(
				id,
				detail.partyA,
				detail.partyB,
				detail.partyABucketId,
				detail.partyBBucketId,
				detail.collateral,
				uint8(detail.status)
			);
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
		_emitBucketStatus(_liquidationId(detail.partyA, detail.partyABucketId, detail.partyB, detail.partyBBucketId, detail.collateral), detail);
	}

	// =============================================================
	//                 📍  Party B – Isolated  📍
	// =============================================================

	function flagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert LiquidationErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		_flag(address(0), 0, partyB, 0, collateral, LiquidationSide.PARTY_B, false);
	}

	function unflagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		_unflag(address(0), 0, partyB, 0, collateral);
	}

	function liquidateIsolatedPartyB(address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = _detail(address(0), 0, partyB, 0, collateral);
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
		_flagCrossPartyB(partyB, 0, partyA, 0, collateral, false);
	}

	function flagCrossPartyBLiquidation(address partyB, uint256 partyBBucketId, address partyA, uint256 partyABucketId, address collateral) internal {
		_flagCrossPartyB(partyB, partyBBucketId, partyA, partyABucketId, collateral, true);
	}

	function _flagCrossPartyB(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral,
		bool nativeBucket
	) private {
		if (nativeBucket) {
			LibBucket.requireRegistered(partyA, partyABucketId);
			LibBucket.requireRegistered(partyB, partyBBucketId);
		}
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert LiquidationErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(partyBBucketId, partyA, partyABucketId, collateral, MarginType.CROSS);

		_flag(partyA, partyABucketId, partyB, partyBBucketId, collateral, LiquidationSide.PARTY_B, nativeBucket);
	}

	function unflagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		unflagCrossPartyBLiquidation(partyB, 0, partyA, 0, collateral);
	}

	function unflagCrossPartyBLiquidation(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral
	) internal {
		_unflag(partyA, partyABucketId, partyB, partyBBucketId, collateral);
	}

	function liquidateCrossPartyB(address partyB, address partyA, address collateral, int256 upnl, uint256 collateralPrice) internal {
		liquidateCrossPartyB(partyB, 0, partyA, 0, collateral, upnl, collateralPrice);
	}

	function liquidateCrossPartyB(
		address partyB,
		uint256 partyBBucketId,
		address partyA,
		uint256 partyABucketId,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) internal {
		LiquidationDetail storage detail = _detail(partyA, partyABucketId, partyB, partyBBucketId, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		ScheduledReleaseBalance storage balB = partyB.balanceOf(partyBBucketId, collateral);
		CrossEntry storage crossBalance = balB.crossEntry(partyA, partyABucketId);

		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;
		if (crossBalance.balance + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0) {
			revert LiquidationErrors.PartyBSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			uint256 balance = uint256(crossBalance.balance);
			balB.subForCounterParty(partyA, partyABucketId, balance, MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			partyA.balanceOf(partyABucketId, collateral).scheduledAdd(
				partyB,
				partyBBucketId,
				balance,
				MarginType.CROSS,
				IncreaseBalanceReason.LIQUIDATION
			);
		}
		crossBalance.balance = 0;
		crossBalance.locked = 0; // no effect as Party B is not Locking anything
		crossBalance.totalMM = 0; // no effect as MM is for Party A

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                       📍  Party A                        📍
	// =============================================================

	function flagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		_flagPartyA(partyA, 0, partyB, 0, collateral, false);
	}

	function flagPartyALiquidation(address partyA, uint256 partyABucketId, address partyB, uint256 partyBBucketId, address collateral) internal {
		_flagPartyA(partyA, partyABucketId, partyB, partyBBucketId, collateral, true);
	}

	function _flagPartyA(
		address partyA,
		uint256 partyABucketId,
		address partyB,
		uint256 partyBBucketId,
		address collateral,
		bool nativeBucket
	) private {
		if (nativeBucket) {
			LibBucket.requireRegistered(partyA, partyABucketId);
			LibBucket.requireRegistered(partyB, partyBBucketId);
		}
		partyA.requireSolvent(partyABucketId, partyB, partyBBucketId, collateral, MarginType.CROSS);
		_flag(partyA, partyABucketId, partyB, partyBBucketId, collateral, LiquidationSide.PARTY_A, nativeBucket);
	}

	function unflagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		unflagPartyALiquidation(partyA, 0, partyB, 0, collateral);
	}

	function unflagPartyALiquidation(address partyA, uint256 partyABucketId, address partyB, uint256 partyBBucketId, address collateral) internal {
		_unflag(partyA, partyABucketId, partyB, partyBBucketId, collateral);
	}

	function validateLiquidationMetadata(uint256 liquidationId, address partyA, address partyB, address collateral) internal view {
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		if (detail.isBucketLiquidation && (detail.partyA != partyA || detail.partyB != partyB || detail.collateral != collateral))
			revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
	}

	function liquidateCrossPartyA(uint256 liquidationId, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		ScheduledReleaseBalance storage balA = detail.partyA.balanceOf(detail.partyABucketId, detail.collateral);
		CrossEntry storage crossBalance = balA.crossEntry(detail.partyB, detail.partyBBucketId);

		if ((crossBalance.balance - int256(crossBalance.totalMM)) + (upnl * 1e18) / int256(collateralPrice) >= 0) {
			revert LiquidationErrors.PartyASolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			ScheduledReleaseBalance storage balB = detail.partyB.balanceOf(detail.partyBBucketId, detail.collateral);
			uint256 balance = uint256(crossBalance.balance);
			balA.subForCounterParty(detail.partyB, detail.partyBBucketId, balance, MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			balB.scheduledAdd(detail.partyA, detail.partyABucketId, balance, MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossBalance.balance = 0;

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                       🔄  Shared 🔄
	// =============================================================

	function closeTrades(uint256 liquidationId, uint256[] calldata tradeIds, uint256[] calldata prices) internal {
		if (tradeIds.length != prices.length) revert LiquidationErrors.MismatchedArrayLengths(tradeIds.length, prices.length);

		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);

		TradeStorage.Layout storage tradeLayout = TradeStorage.layout();
		SymbolStorage.Layout storage symbolLayout = SymbolStorage.layout();

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = tradeLayout.trades[tradeIds[i]];
			TradeAgreements storage tradeAgreement = trade.tradeAgreements;

			uint256 price = prices[i];

			ValidationErrors.requireStatus("TradeStatus", uint8(trade.status), uint8(TradeStatus.OPENED));
			bool exactPair = detail.isBucketLiquidation || trade.relationshipId != 0;
			if (exactPair) {
				if (
					trade.partyA != detail.partyA ||
					trade.partyABucketId != detail.partyABucketId ||
					trade.partyB != detail.partyB ||
					trade.partyBBucketId != detail.partyBBucketId ||
					tradeAgreement.marginType != MarginType.CROSS ||
					symbolLayout.symbols[tradeAgreement.symbolId].collateral != detail.collateral
				) revert LiquidationErrors.TradeNotInLiquidation(liquidationId, trade.id);
			} else if (
				(detail.partyA != address(0) && (trade.partyA != detail.partyA || trade.partyABucketId != detail.partyABucketId)) ||
				(detail.partyB != address(0) && (trade.partyB != detail.partyB || trade.partyBBucketId != detail.partyBBucketId))
			) {
				revert LiquidationErrors.TradeNotInLiquidation(liquidationId, trade.id);
			}

			if (tradeAgreement.tradeSide == TradeSide.BUY) {
				ScheduledReleaseBalance storage partyBBalance = trade.partyB.balanceOf(
					trade.partyBBucketId,
					symbolLayout.symbols[tradeAgreement.symbolId].collateral
				);

				if (tradeAgreement.marginType == MarginType.ISOLATED) {
					partyBBalance.instantIsolatedAdd(trade.calculateProportionalPremium(trade.getOpenAmount()), IncreaseBalanceReason.PREMIUM);
				} else {
					partyBBalance.scheduledAdd(
						trade.partyA,
						trade.partyABucketId,
						trade.calculateProportionalPremium(trade.getOpenAmount()),
						tradeAgreement.marginType,
						IncreaseBalanceReason.PREMIUM
					);
				}
			} else {
				trade.partyA.balanceOf(trade.partyABucketId, symbolLayout.symbols[tradeAgreement.symbolId].collateral).decreaseMM(
					trade.partyB,
					trade.partyBBucketId,
					trade.calculateProportionalMM(trade.getOpenAmount())
				);
			}

			trade.settledPrice = price;
			trade.close(TradeStatus.LIQUIDATED, CloseIntentStatus.CANCELED);
		}
	}

	function allocateFromReserveToCross(address party, address counterParty, address collateral, uint256 amount) internal {
		allocateFromReserveToCross(party, 0, counterParty, 0, collateral, amount);
	}

	function allocateFromReserveToCross(
		address party,
		uint256 partyBucketId,
		address counterParty,
		uint256 counterPartyBucketId,
		address collateral,
		uint256 amount
	) internal {
		LibBucket.requireRegistered(party, partyBucketId);
		LibBucket.requireRegistered(counterParty, counterPartyBucketId);
		ScheduledReleaseBalance storage balance = party.balanceOf(partyBucketId, collateral);
		if (balance.reserveBalance < amount) revert BalanceErrors.InsufficientBalance(party, collateral, amount, balance.reserveBalance);
		balance.reserveBalance -= amount;
		balance.scheduledAdd(counterParty, counterPartyBucketId, amount, MarginType.CROSS, IncreaseBalanceReason.ALLOCATE_FROM_RESERVE);
	}

	function confiscate(
		uint256 liquidationId,
		address party,
		address[] calldata counterParties,
		uint256[] calldata amounts,
		MarginType marginType
	) internal {
		uint256[] memory buckets = new uint256[](counterParties.length);
		confiscate(liquidationId, party, 0, counterParties, buckets, amounts, marginType);
	}

	function confiscate(
		uint256 liquidationId,
		address party,
		uint256 partyBucketId,
		address[] calldata counterParties,
		uint256[] memory counterPartyBucketIds,
		uint256[] calldata amounts,
		MarginType marginType
	) internal {
		if (counterParties.length != amounts.length) revert LiquidationErrors.MismatchedArrayLengths(counterParties.length, amounts.length);
		if (counterParties.length != counterPartyBucketIds.length)
			revert LiquidationErrors.MismatchedArrayLengths(counterParties.length, counterPartyBucketIds.length);
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		if (party != detail.partyA && party != detail.partyB)
			revert LiquidationErrors.PartyNotInLiquidation(party, detail.partyA, detail.partyB, detail.collateral);
		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);
		if (detail.isBucketLiquidation) {
			if (
				marginType != MarginType.CROSS ||
				!((party == detail.partyA && partyBucketId == detail.partyABucketId) ||
					(party == detail.partyB && partyBucketId == detail.partyBBucketId))
			) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
		} else if (partyBucketId != 0) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
		ScheduledReleaseBalance storage balance = party.balanceOf(partyBucketId, detail.collateral);
		uint256 sum;
		for (uint256 i = 0; i < counterParties.length; i++) {
			address counterParty = counterParties[i];
			uint256 counterBucketId = counterPartyBucketIds[i];
			if (detail.isBucketLiquidation) {
				if (!_matchesPair(detail, party, partyBucketId, counterParty, counterBucketId))
					revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
			} else if (counterBucketId != 0) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
			uint256 amount = amounts[i];
			int256 counterPartyBalance = balance.counterPartyBalance(counterParty, counterBucketId, marginType);
			if (counterPartyBalance < int256(amount))
				revert BalanceErrors.InsufficientIntBalance(party, detail.collateral, amount, counterPartyBalance);
			balance.subForCounterParty(counterParty, counterBucketId, amount, marginType, DecreaseBalanceReason.CONFISCATE);
			sum += amount;
		}
		detail.confiscatedAmount += sum;
	}

	function confiscateWithdrawal(uint256 withdrawId) internal {
		AccountStorage.Layout storage acc = AccountStorage.layout();
		if (withdrawId == 0 || withdrawId > acc.lastWithdrawId) {
			revert ValidationErrors.InvalidID(withdrawId, acc.lastWithdrawId);
		}
		Withdraw storage withdrawal = AccountStorage.layout().withdrawals[withdrawId];
		ValidationErrors.requireStatus("WithdrawStatus", uint8(withdrawal.status), uint8(WithdrawStatus.INITIATED)); //  0 is the initiated state by default
		withdrawal.status = WithdrawStatus.CANCELED;
		withdrawal.user.balanceOf(withdrawal.bucketId, withdrawal.collateral).instantIsolatedAdd(withdrawal.amount, IncreaseBalanceReason.DEPOSIT);
	}

	function distributeCollateral(
		uint256 liquidationId,
		address partyB,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] calldata amounts
	) internal {
		uint256[] memory buckets = new uint256[](partyAs.length);
		distributeCollateral(liquidationId, partyB, 0, collateral, marginType, partyAs, buckets, amounts);
	}

	function distributeCollateral(
		uint256 liquidationId,
		address partyB,
		uint256 partyBBucketId,
		address collateral,
		MarginType marginType,
		address[] calldata partyAs,
		uint256[] memory partyABucketIds,
		uint256[] calldata amounts
	) internal {
		if (partyAs.length != amounts.length) revert LiquidationErrors.MismatchedArrayLengths(partyAs.length, amounts.length);
		if (partyAs.length != partyABucketIds.length) revert LiquidationErrors.MismatchedArrayLengths(partyAs.length, partyABucketIds.length);
		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);
		if (detail.isBucketLiquidation) {
			if (
				collateral != detail.collateral ||
				marginType != MarginType.CROSS ||
				!((partyB == detail.partyA && partyBBucketId == detail.partyABucketId) ||
					(partyB == detail.partyB && partyBBucketId == detail.partyBBucketId))
			) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
		} else if (partyBBucketId != 0) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
		uint256 sum;
		for (uint256 i = 0; i < partyAs.length; i++) {
			uint256 bucketA = partyABucketIds[i];
			if (detail.isBucketLiquidation) {
				if (!_matchesPair(detail, partyAs[i], bucketA, partyB, partyBBucketId))
					revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
			} else if (bucketA != 0) revert LiquidationErrors.LiquidationScopeMismatch(liquidationId);
			partyAs[i].balanceOf(bucketA, collateral).scheduledAdd(partyB, partyBBucketId, amounts[i], marginType, IncreaseBalanceReason.LIQUIDATION);
			sum += amounts[i];
		}
		detail.distributedAmount += sum;
		if (detail.distributedAmount > detail.confiscatedAmount) revert LiquidationErrors.DistributedAmountExceedsConfiscatedAmount(liquidationId);
	}

	function cancelOpenIntents(uint256[] calldata intentIds) internal {
		OpenIntentStorage.Layout storage openIntentLayout = OpenIntentStorage.layout();

		for (uint256 i = 0; i < intentIds.length; i++) {
			OpenIntent storage intent = openIntentLayout.openIntents[intentIds[i]];

			address collateral = SymbolStorage.layout().symbols[intent.tradeAgreements.symbolId].collateral;
			address counterParty = intent.partyB;
			if (counterParty == address(0) && intent.relationshipId != 0) counterParty = intent.partyBsWhiteList[0];
			bool partyAIsSolvent = intent.partyA.isSolvent(
				intent.partyABucketId,
				counterParty,
				intent.partyBBucketId,
				collateral,
				intent.tradeAgreements.marginType
			);
			bool partyBIsSolvent = counterParty.isSolvent(
				intent.partyBBucketId,
				intent.partyA,
				intent.partyABucketId,
				collateral,
				intent.tradeAgreements.marginType
			);
			if (!(intent.status == OpenIntentStatus.PENDING || intent.status == OpenIntentStatus.LOCKED)) {
				uint8[] memory requiredStatuses = new uint8[](2);
				requiredStatuses[0] = uint8(OpenIntentStatus.PENDING);
				requiredStatuses[1] = uint8(OpenIntentStatus.LOCKED);

				revert ValidationErrors.InvalidState("OpenIntentStatus", uint8(intent.status), requiredStatuses);
			}

			if (partyAIsSolvent && partyBIsSolvent) {
				revert LiquidationErrors.PartiesNotInLiquidation(intent.partyA, intent.partyB, collateral);
			}

			if (block.timestamp > intent.deadline) {
				intent.expire();
			} else {
				if (intent.tradeAgreements.marginType == MarginType.ISOLATED && intent.partyBsWhiteList.length != 1) {
					// Isolated mode means Party B Liquidated: return the intent to the other whitelisted Party Bs
					intent.status = OpenIntentStatus.PENDING;
					intent.unregister(true);
					intent.partyB = address(0); // Clear Party B assignment (must be after unregister), as in LibPartyBOpen.unlockOpenIntent
				} else {
					// in Cross Mode every Intents must be closed
					intent.status = OpenIntentStatus.CANCELED;
					intent.unlockForCancelOrExpire();
					intent.unregister(false);
				}
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
			bool partyAIsSolvent = trade.partyA.isSolvent(
				trade.partyABucketId,
				trade.partyB,
				trade.partyBBucketId,
				collateral,
				trade.tradeAgreements.marginType
			);
			bool partyBIsSolvent = trade.partyB.isSolvent(
				trade.partyBBucketId,
				trade.partyA,
				trade.partyABucketId,
				collateral,
				trade.tradeAgreements.marginType
			);

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
