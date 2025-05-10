// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023‑2025 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal‑disclaimer/license
pragma solidity >=0.8.19;

import { LibParty } from "../../libraries/LibParty.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { CommonErrors } from "../../libraries/CommonErrors.sol";
import { ScheduledReleaseBalanceOps } from "../../libraries/LibScheduledReleaseBalance.sol";

import { AppStorage } from "../../storages/AppStorage.sol";
import { TradeStorage } from "../../storages/TradeStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";

import { MarginType } from "../../types/BaseTypes.sol";
import { IntentStatus } from "../../types/IntentTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Withdraw, WithdrawStatus } from "../../types/WithdrawTypes.sol";
import { LiquidationStatus, LiquidationDetail, LiquidationSide } from "../../types/LiquidationTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason, CrossEntry } from "../../types/BalanceTypes.sol";

import { ClearingHouseFacetErrors } from "./ClearingHouseFacetErrors.sol";

library ClearingHouseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibParty for address;

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
		// upnl & collateralPrice start at 0 – identical to the old logic.
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
		CommonErrors.requireStatus("LiquidationStatus", uint8(detail.status), uint8(expected));
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
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert ClearingHouseFacetErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		_flag(address(0), partyB, collateral, LiquidationSide.PARTY_B);
	}

	function unflagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		_unflag(address(0), partyB, collateral);
	}

	function liquidateIsolatedPartyB(address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = _detail(address(0), partyB, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		uint256 isolatedBalance = AccountStorage.layout().balances[partyB][collateral].isolatedBalance;

		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;
		if (int256(isolatedBalance) + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0) {
			revert ClearingHouseFacetErrors.PartyBIsSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                 📍  Party B – Cross margin  📍
	// =============================================================

	function flagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert ClearingHouseFacetErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(partyA, collateral, MarginType.CROSS);

		_flag(partyA, partyB, collateral, LiquidationSide.PARTY_B);
	}

	function unflagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		_unflag(partyA, partyB, collateral);
	}

	function liquidateCrossPartyB(address partyB, address partyA, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationDetail storage detail = _detail(partyA, partyB, collateral);
		_requireStatus(detail, LiquidationStatus.FLAGGED);

		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		ScheduledReleaseBalance storage balB = accountLayout.balances[partyB][collateral];
		CrossEntry storage crossBalance = balB.crossBalance[partyA];

		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;
		if (crossBalance.balance + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0) {
			revert ClearingHouseFacetErrors.PartyBIsSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			accountLayout.balances[partyA][collateral].subForCounterParty(
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

		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		ScheduledReleaseBalance storage balA = accountLayout.balances[detail.partyA][detail.collateral];
		CrossEntry storage crossBalance = balA.crossBalance[detail.partyB];

		if ((crossBalance.balance - int256(crossBalance.totalMM)) + (upnl * 1e18) / int256(collateralPrice) >= 0) {
			revert ClearingHouseFacetErrors.PartyAIsSolvent(detail.partyA, detail.partyB, detail.collateral);
		}

		if (crossBalance.balance > 0) {
			ScheduledReleaseBalance storage balB = accountLayout.balances[detail.partyB][detail.collateral];
			balA.subForCounterParty(detail.partyB, uint256(crossBalance.balance), MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			balB.scheduledAdd(detail.partyB, uint256(crossBalance.balance), MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossBalance.balance = 0;
		crossBalance.locked = 0;
		crossBalance.totalMM = 0;

		_beginLiquidation(detail, collateralPrice);
	}

	// =============================================================
	//                 🔄  Shared 🔄
	// =============================================================

	/// @dev Behavior identical to the original – left untouched for clarity.
	function closeTrades(uint256 liquidationId, uint256[] memory tradeIds, uint256[] memory prices) internal {
		if (tradeIds.length != prices.length) revert ClearingHouseFacetErrors.MismatchedArrays(tradeIds.length, prices.length);

		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		_requireStatus(detail, LiquidationStatus.IN_PROGRESS);

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = TradeStorage.layout().trades[tradeIds[i]];
			uint256 price = prices[i];

			if (trade.status != TradeStatus.OPENED) {
				uint8[] memory requiredStatuses = new uint8[](1);
				requiredStatuses[0] = uint8(TradeStatus.OPENED);
				revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
			}
			if (trade.partyA != detail.partyA || trade.partyB != detail.partyB) {
				revert ClearingHouseFacetErrors.TradeIsNotInLiquidation(liquidationId, trade.id);
			}

			trade.settledPrice = price;
			trade.close(TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
		}
	}

	function allocateFromReserveToCross(address party, address counterParty, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage balance = AccountStorage.layout().balances[party][collateral];
		if (balance.reserveBalance < amount) revert();
		balance.reserveBalance -= amount;
		balance.crossBalance[counterParty].balance += int256(amount);
	}

	function confiscatePartyA(address /*partyB*/, address /*partyA*/, address /*collateral*/, uint256 /*amount*/) internal {}

	function confiscatePartyBWithdrawal(address /*partyB*/, uint256 /*withdrawId*/) internal {}

	function distributeCollateral(address /*partyB*/, address /*collateral*/, address[] memory /*partyAs*/) internal {}
}
