// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
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

	function flagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert ClearingHouseFacetErrors.ZeroLossCoverage(partyB);
		partyB.requireSolvent(address(0), collateral, MarginType.ISOLATED);

		address partyA = address(0);
		uint256 liquidationId = ++liquidationLayout.lastLiquidationId;
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = liquidationId;
		liquidationLayout.liquidationDetails[liquidationId] = LiquidationDetail({
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			flagger: msg.sender,
			collateral: collateral,
			collateralPrice: 0,
			partyA: partyA,
			partyB: partyB,
			side: LiquidationSide.PARTY_B
		});
	}

	function unflagIsolatedPartyBLiquidation(address partyB, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();
		address partyA = address(0);

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[
			liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral]
		];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = 0;
		detail.status = LiquidationStatus.CANCELLED;
	}

	function liquidateIsolatedPartyB(address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[
			liquidationLayout.inProgressLiquidationIds[address(0)][partyB][collateral]
		];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}

		ScheduledReleaseBalance storage balancePartyB = accountLayout.balances[detail.partyB][detail.collateral];

		uint256 balance = balancePartyB.isolatedBalance;
		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int256(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;

		if (int256(balance) + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0)
			revert ClearingHouseFacetErrors.PartyBIsSolvent(detail.partyA, detail.partyB, detail.collateral);

		detail.status = LiquidationStatus.IN_PROGRESS;
		detail.collateralPrice = collateralPrice;
	}

	function flagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();
		if (AppStorage.layout().partyBConfigs[partyB].lossCoverage == 0) revert ClearingHouseFacetErrors.ZeroLossCoverage(partyB);

		partyB.requireSolvent(partyA, collateral, MarginType.CROSS);

		uint256 liquidationId = ++liquidationLayout.lastLiquidationId;
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = liquidationId;
		liquidationLayout.liquidationDetails[liquidationId] = LiquidationDetail({
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			flagger: msg.sender,
			collateral: collateral,
			collateralPrice: 0,
			partyA: partyA,
			partyB: partyB,
			side: LiquidationSide.PARTY_B
		});
	}

	function unflagCrossPartyBLiquidation(address partyB, address partyA, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[
			liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral]
		];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = 0;
		detail.status = LiquidationStatus.CANCELLED;
	}

	function liquidateCrossPartyB(address partyB, address partyA, address collateral, int256 upnl, uint256 collateralPrice) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[
			liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral]
		];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}

		ScheduledReleaseBalance storage balancePartyB = accountLayout.balances[detail.partyB][detail.collateral];

		CrossEntry storage crossEntry = balancePartyB.crossBalance[detail.partyA];
		int256 crossBalance = crossEntry.balance;
		int256 effectiveUpnl = upnl > 0 ? upnl : (upnl * int(AppStorage.layout().partyBConfigs[partyB].lossCoverage)) / 1e18;

		if (crossBalance + (effectiveUpnl * 1e18) / int256(collateralPrice) >= 0)
			revert ClearingHouseFacetErrors.PartyBIsSolvent(detail.partyA, detail.partyB, detail.collateral);

		ScheduledReleaseBalance storage balancePartyA = accountLayout.balances[detail.partyA][detail.collateral];
		if (crossBalance > 0) {
			balancePartyA.subForCounterParty(detail.partyB, uint256(crossBalance), MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			balancePartyB.scheduledAdd(detail.partyA, uint256(crossBalance), MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossEntry.balance = 0;
		crossEntry.locked = 0;
		crossEntry.totalMM = 0;

		detail.status = LiquidationStatus.IN_PROGRESS;
		detail.collateralPrice = collateralPrice;
	}

	function flagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		partyA.requireSolvent(partyB, collateral, MarginType.CROSS);

		uint256 liquidationId = ++liquidationLayout.lastLiquidationId;
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = liquidationId;
		liquidationLayout.liquidationDetails[liquidationId] = LiquidationDetail({
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			flagger: msg.sender,
			collateral: collateral,
			collateralPrice: 0,
			partyA: partyA,
			partyB: partyB,
			side: LiquidationSide.PARTY_A
		});
	}

	function unflagPartyALiquidation(address partyA, address partyB, address collateral) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[
			liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral]
		];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}
		detail.status = LiquidationStatus.CANCELLED;
		liquidationLayout.inProgressLiquidationIds[partyA][partyB][collateral] = 0;
	}

	function liquidateCrossPartyA(uint256 liquidationId, int256 upnl, uint256 collateralPrice) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LiquidationDetail storage detail = liquidationLayout.liquidationDetails[liquidationId];
		if (detail.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}

		ScheduledReleaseBalance storage balancePartyA = accountLayout.balances[detail.partyA][detail.collateral];
		CrossEntry storage crossEntry = balancePartyA.crossBalance[detail.partyB];
		int256 crossBalance = crossEntry.balance;

		if ((crossBalance - int256(crossEntry.totalMM)) + (upnl * 1e18) / int256(collateralPrice) >= 0)
			revert ClearingHouseFacetErrors.PartyAIsSolvent(detail.partyA, detail.partyB, detail.collateral);

		ScheduledReleaseBalance storage balancePartyB = accountLayout.balances[detail.partyB][detail.collateral];
		if (crossBalance > 0) {
			balancePartyA.subForCounterParty(detail.partyB, uint256(crossBalance), MarginType.CROSS, DecreaseBalanceReason.LIQUIDATION);
			balancePartyB.scheduledAdd(detail.partyB, uint256(crossBalance), MarginType.CROSS, IncreaseBalanceReason.LIQUIDATION);
		}
		crossEntry.balance = 0;
		crossEntry.locked = 0;
		crossEntry.totalMM = 0;

		detail.status = LiquidationStatus.IN_PROGRESS;
		detail.collateralPrice = collateralPrice;
	}

	function closeTrades(uint256 liquidationId, uint256[] memory tradeIds, uint256[] memory prices) internal {
		if (tradeIds.length != prices.length) revert ClearingHouseFacetErrors.MismatchedArrays(tradeIds.length, prices.length);

		LiquidationDetail storage detail = LiquidationStorage.layout().liquidationDetails[liquidationId];
		if (detail.status != LiquidationStatus.IN_PROGRESS) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.IN_PROGRESS);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(detail.status), requiredStatuses);
		}

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = TradeStorage.layout().trades[tradeIds[i]];
			uint256 price = prices[i];

			if (trade.status != TradeStatus.OPENED) {
				uint8[] memory requiredStatuses = new uint8[](1);
				requiredStatuses[0] = uint8(TradeStatus.OPENED);
				revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
			}
			if (trade.partyA != detail.partyA || trade.partyB != detail.partyB)
				revert ClearingHouseFacetErrors.TradeIsNotInLiquidation(liquidationId, trade.id);

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

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) internal {
		//FIXME: Isolated or cross
		// if (partyB.isSolvent(partyA, collateral, MarginType.ISOLATED)) require(false);
		// ScheduledReleaseBalance storage balance = AccountStorage.layout().balances[partyA][collateral];
		// int256 scheduledBalance = balance.counterPartyBalance(partyB);
		// if (scheduledBalance < 0 || scheduledBalance < int256(amount))
		// 	revert ClearingHouseFacetErrors.InsufficientBalance(partyA, collateral, amount, scheduledBalance);
		// balance.subForCounterParty(partyB, amount, MarginType.ISOLATED, DecreaseBalanceReason.CONFISCATE);
		// partyB.getInProgressLiquidationDetail(collateral).collectedCollateral += amount;
	}

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) internal {}

	function distributeCollateral(address partyB, address collateral, address[] memory partyAs) internal {}

	// function unfreezePartyAs(address partyB, address collateral) external whenNotLiquidationPaused onlyRole(LibAccessibility.CLEARING_HOUSE_ROLE) {}
}
