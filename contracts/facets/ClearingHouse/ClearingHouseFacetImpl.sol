// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { LibPartyB } from "../../libraries/LibPartyB.sol";
import { AccountStorage, Withdraw, WithdrawStatus } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus, LiquidationDetail, LiquidationState } from "../../storages/AppStorage.sol";
import { Trade, IntentStorage, TradeStatus, IntentStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage, OptionType } from "../../storages/SymbolStorage.sol";

library ClearingHouseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;
	using LibPartyB for address;

	function flagLiquidation(address partyB, address collateral) internal returns (uint256 liquidationId) {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		require(appLayout.partyBConfigs[partyB].lossCoverage > 0, "LiquidationFacet: Loss coverage of partyB is zero");
		partyB.requireSolvent(collateral);

		liquidationId = ++appLayout.lastLiquidationId;

		appLayout.liquidationStates[partyB][collateral] = LiquidationState({
			inProgressLiquidationId: liquidationId,
			status: LiquidationStatus.FLAGGED
		});
		appLayout.liquidationDetails[liquidationId] = LiquidationDetail({
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

		require(state.status == LiquidationStatus.FLAGGED, "LiquidationFacet: Invalid liquidation status");

		state.inProgressLiquidationId = 0;
		state.status = LiquidationStatus.SOLVENT;
	}

	function liquidate(bytes memory clearingHouseLiquidationId, address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(partyB.getLiquidationState(collateral).status == LiquidationStatus.FLAGGED, "LiquidationFacet: Invalid liquidation status");

		require(upnl < 0, "LiquidationFacet: Invalid upnl");

		int256 requiredCollateral = (-upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) / int256(collateralPrice);
		require(int256(accountLayout.balances[partyB][collateral].available) < requiredCollateral, "LiquidationFacet: PartyB is solvent");

		LiquidationDetail storage detail = partyB.getInProgressLiquidationDetail(collateral);
		detail.clearingHouseLiquidationId = clearingHouseLiquidationId;
		detail.upnl = upnl;
		detail.liquidationTimestamp = block.timestamp;
		detail.collateralPrice = collateralPrice;
		detail.collectedCollateral = accountLayout.balances[partyB][collateral].available;
	}

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) internal {
		ScheduledReleaseBalance storage balance = AccountStorage.layout().balances[partyA][collateral];

		require(balance.partyBBalance(partyB) > amount, "LiquidationFacet: Insufficient funds");
		partyB.requireInProgressLiquidation(collateral);

		balance.subForPartyB(partyB, amount);
		partyB.getInProgressLiquidationDetail(collateral).collectedCollateral += amount;
	}

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(withdrawId <= accountLayout.lastWithdrawId, "LiquidationFacet: Invalid Id");

		Withdraw memory withdraw = accountLayout.withdrawals[withdrawId];

		require(withdraw.status == WithdrawStatus.INITIATED, "LiquidationFacet: Invalid withdrawal state");
		require(withdraw.user == partyB, "LiquidationFacet: Invalid user for withdraw Id");
		partyB.requireInProgressLiquidation(withdraw.collateral);

		withdraw.status = WithdrawStatus.CANCELED;

		partyB.getInProgressLiquidationDetail(withdraw.collateral).collectedCollateral += withdraw.amount;
	}

	function closeTrades(uint256[] memory tradeIds, uint256[] memory prices) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		require(tradeIds.length == prices.length, "LiquidationFacet: Mismatched arrays");

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = IntentStorage.layout().trades[tradeIds[i]];
			Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
			uint256 price = prices[i];

			require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid trade state");
			trade.partyB.requireInProgressLiquidation(symbol.collateral);
			trade.settledPrice = price;

			uint256 pnl = trade.getPnl(price, trade.tradeAgreements.quantity);

			if (pnl > 0) {
				uint256 amountToTransfer = (pnl * appLayout.partyBConfigs[trade.partyB].lossCoverage) / 1e18;
				LiquidationDetail storage detail = trade.partyB.getInProgressLiquidationDetail(symbol.collateral);

				amountToTransfer = (amountToTransfer * 1e18) / detail.collateralPrice;
				if (appLayout.liquidationDebtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] == 0) {
					appLayout.involvedPartyAsCountInLiquidation[trade.partyB][symbol.collateral] += 1;
				}
				appLayout.liquidationDebtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] += amountToTransfer;
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
		AppStorage.Layout storage appLayout = AppStorage.layout();

		LiquidationState storage state = partyB.getLiquidationState(collateral);
		LiquidationDetail storage detail = partyB.getInProgressLiquidationDetail(collateral);

		require(IntentStorage.layout().activeTradesOfPartyB[partyB][collateral].length == 0, "LiquidationFacet: PartyB has still open trades");
		partyB.requireInProgressLiquidation(collateral);
		require(detail.collectedCollateral >= detail.requiredCollateral, "LiquidationFacet: not enough collateral to pay debts");

		liquidationId = state.inProgressLiquidationId;

		amounts = new uint256[](partyAs.length);
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			uint256 amountToTransfer = appLayout.liquidationDebtsToPartyAs[partyB][collateral][partyA];
			amounts[i] = amountToTransfer;
			appLayout.involvedPartyAsCountInLiquidation[partyB][collateral] -= 1;
			AccountStorage.layout().balances[partyA][collateral].instantAdd(collateral, amountToTransfer);
			appLayout.liquidationDebtsToPartyAs[partyB][collateral][partyA] = 0;
		}
		if (appLayout.involvedPartyAsCountInLiquidation[partyB][collateral] == 0) {
			isLiquidationFinished = true;
			state.status = LiquidationStatus.SOLVENT;
			state.inProgressLiquidationId = 0;
		}
	}
}
