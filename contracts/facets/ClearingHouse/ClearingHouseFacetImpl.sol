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
import { SymbolStorage } from "../../storages/SymbolStorage.sol";
import { AccountStorage } from "../../storages/AccountStorage.sol";
import { LiquidationStorage } from "../../storages/LiquidationStorage.sol";

import { Symbol } from "../../types/SymbolTypes.sol";
import { MarginType } from "../../types/BaseTypes.sol";
import { IntentStatus } from "../../types/IntentTypes.sol";
import { Trade, TradeStatus } from "../../types/TradeTypes.sol";
import { Withdraw, WithdrawStatus } from "../../types/WithdrawTypes.sol";
import { LiquidationStatus, LiquidationDetail, LiquidationState } from "../../types/LiquidationTypes.sol";
import { ScheduledReleaseBalance, IncreaseBalanceReason, DecreaseBalanceReason } from "../../types/BalanceTypes.sol";

import { ClearingHouseFacetErrors } from "./ClearingHouseFacetErrors.sol";

library ClearingHouseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibParty for address;

	function flagLiquidation(address partyB, address collateral) internal returns (uint256 liquidationId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		if (appLayout.partyBConfigs[partyB].lossCoverage == 0) revert ClearingHouseFacetErrors.ZeroLossCoverage(partyB);

		partyB.requireSolvent(collateral);

		liquidationId = ++liquidationLayout.lastLiquidationId;

		liquidationLayout.liquidationStates[partyB][collateral] = LiquidationState({
			inProgressLiquidationId: liquidationId,
			status: LiquidationStatus.FLAGGED
		});
		liquidationLayout.liquidationDetails[liquidationId] = LiquidationDetail({
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			collateralPrice: 0,
			flagger: msg.sender,
			collectedCollateral: 0,
			requiredCollateral: 0,
			clearingHouseLiquidationId: ""
		});
	}

	function unflagLiquidation(address partyB, address collateral) internal {
		LiquidationState storage state = partyB.getLiquidationState(collateral);

		if (state.status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(state.status), requiredStatuses);
		}

		state.inProgressLiquidationId = 0;
		state.status = LiquidationStatus.SOLVENT;
	}

	function liquidate(bytes memory clearingHouseLiquidationId, address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (partyB.getLiquidationState(collateral).status != LiquidationStatus.FLAGGED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(LiquidationStatus.FLAGGED);
			revert CommonErrors.InvalidState("LiquidationStatus", uint8(partyB.getLiquidationState(collateral).status), requiredStatuses);
		}

		if (upnl >= 0) revert ClearingHouseFacetErrors.InvalidUpnl(upnl);

		int256 requiredCollateral = (-upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) / int256(collateralPrice);
		if (int256(accountLayout.balances[partyB][collateral].isolatedBalance) >= requiredCollateral)
			revert ClearingHouseFacetErrors.PartyBIsSolvent(
				partyB,
				collateral,
				int256(accountLayout.balances[partyB][collateral].isolatedBalance),
				requiredCollateral
			);

		LiquidationDetail storage detail = partyB.getInProgressLiquidationDetail(collateral);
		detail.clearingHouseLiquidationId = clearingHouseLiquidationId;
		detail.upnl = upnl;
		detail.liquidationTimestamp = block.timestamp;
		detail.collateralPrice = collateralPrice;
		detail.collectedCollateral = accountLayout.balances[partyB][collateral].isolatedBalance;
	}

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage balance = AccountStorage.layout().balances[partyA][collateral];

		int256 b = balance.counterPartyBalance(partyB, MarginType.ISOLATED);
		if (b <= int256(amount)) revert CommonErrors.InsufficientBalance(partyA, collateral, amount, uint256(b));

		partyB.requireInProgressLiquidation(collateral);

		balance.subForCounterParty(partyB, amount, MarginType.ISOLATED, DecreaseBalanceReason.CONFISCATE);
		partyB.getInProgressLiquidationDetail(collateral).collectedCollateral += amount;
	}

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		if (withdrawId > accountLayout.lastWithdrawId)
			revert CommonErrors.InvalidAmount(
				"withdrawId",
				withdrawId,
				1, // 1 for less than check
				accountLayout.lastWithdrawId
			);

		Withdraw memory withdraw = accountLayout.withdrawals[withdrawId];

		if (withdraw.status != WithdrawStatus.INITIATED) {
			uint8[] memory requiredStatuses = new uint8[](1);
			requiredStatuses[0] = uint8(WithdrawStatus.INITIATED);
			revert CommonErrors.InvalidState("WithdrawStatus", uint8(withdraw.status), requiredStatuses);
		}

		if (withdraw.user != partyB) revert ClearingHouseFacetErrors.InvalidWithdrawalUser(withdrawId, withdraw.user, partyB);

		partyB.requireInProgressLiquidation(withdraw.collateral);

		withdraw.status = WithdrawStatus.CANCELED;

		partyB.getInProgressLiquidationDetail(withdraw.collateral).collectedCollateral += withdraw.amount;
	}

	function closeTrades(uint256[] memory tradeIds, uint256[] memory prices) internal {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		if (tradeIds.length != prices.length) revert ClearingHouseFacetErrors.MismatchedArrays(tradeIds.length, prices.length);

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = TradeStorage.layout().trades[tradeIds[i]];
			Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
			uint256 price = prices[i];

			if (trade.status != TradeStatus.OPENED) {
				uint8[] memory requiredStatuses = new uint8[](1);
				requiredStatuses[0] = uint8(TradeStatus.OPENED);
				revert CommonErrors.InvalidState("TradeStatus", uint8(trade.status), requiredStatuses);
			}

			trade.partyB.requireInProgressLiquidation(symbol.collateral);
			trade.settledPrice = price;

			uint256 pnl = trade.getPnl(price, trade.tradeAgreements.quantity);

			if (pnl > 0) {
				uint256 amountToTransfer = (pnl * AppStorage.layout().partyBConfigs[trade.partyB].lossCoverage) / 1e18;
				LiquidationDetail storage detail = trade.partyB.getInProgressLiquidationDetail(symbol.collateral);

				amountToTransfer = (amountToTransfer * 1e18) / detail.collateralPrice;
				if (liquidationLayout.liquidationDebtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] == 0) {
					liquidationLayout.involvedPartyAsCountInLiquidation[trade.partyB][symbol.collateral] += 1;
				}
				liquidationLayout.liquidationDebtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] += amountToTransfer;
				detail.requiredCollateral += amountToTransfer;

				trade.close(TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			} else {
				trade.close(TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			}
		}
	}

	function distributeCollateral(
		address partyB,
		address collateral,
		address[] memory partyAs
	) internal returns (bool isLiquidationFinished, uint256 liquidationId, uint256[] memory amounts) {
		LiquidationStorage.Layout storage liquidationLayout = LiquidationStorage.layout();

		LiquidationState storage state = partyB.getLiquidationState(collateral);
		LiquidationDetail storage detail = partyB.getInProgressLiquidationDetail(collateral);

		if (TradeStorage.layout().activeTradesOfPartyB[partyB][collateral].length != 0)
			revert ClearingHouseFacetErrors.PartyBHasOpenTrades(
				partyB,
				collateral,
				TradeStorage.layout().activeTradesOfPartyB[partyB][collateral].length
			);

		partyB.requireInProgressLiquidation(collateral);

		if (detail.collectedCollateral < detail.requiredCollateral)
			revert ClearingHouseFacetErrors.InsufficientCollateralForDebts(partyB, collateral, detail.collectedCollateral, detail.requiredCollateral);

		liquidationId = state.inProgressLiquidationId;

		amounts = new uint256[](partyAs.length);
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			uint256 amountToTransfer = liquidationLayout.liquidationDebtsToPartyAs[partyB][collateral][partyA];
			amounts[i] = amountToTransfer;
			liquidationLayout.involvedPartyAsCountInLiquidation[partyB][collateral] -= 1;
			AccountStorage.layout().balances[partyA][collateral].instantIsolatedAdd(amountToTransfer, IncreaseBalanceReason.LIQUIDATION);
			liquidationLayout.liquidationDebtsToPartyAs[partyB][collateral][partyA] = 0;
		}
		if (liquidationLayout.involvedPartyAsCountInLiquidation[partyB][collateral] == 0) {
			isLiquidationFinished = true;
			state.status = LiquidationStatus.SOLVENT;
			state.inProgressLiquidationId = 0;
		}
	}
}
