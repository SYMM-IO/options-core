// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ScheduledReleaseBalanceOps, ScheduledReleaseBalance } from "../../libraries/LibScheduledReleaseBalance.sol";
import { LibTradeOps } from "../../libraries/LibTrade.sol";
import { AccountStorage, Withdraw, WithdrawStatus } from "../../storages/AccountStorage.sol";
import { AppStorage, LiquidationStatus, LiquidationDetail } from "../../storages/AppStorage.sol";
import { Trade, IntentStorage, TradeStatus, IntentStatus } from "../../storages/IntentStorage.sol";
import { Symbol, SymbolStorage, OptionType } from "../../storages/SymbolStorage.sol";

library ClearingHouseFacetImpl {
	using ScheduledReleaseBalanceOps for ScheduledReleaseBalance;
	using LibTradeOps for Trade;

	function flagLiquidation(address partyB, address collateral) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.SOLVENT,
			"LiquidationFacet: PartyB is in the liquidation process"
		);
		require(appLayout.partyBConfigs[partyB].lossCoverage > 0, "LiquidationFacet: Loss coverage of partyB is zero");
		appLayout.liquidationDetails[partyB][collateral] = LiquidationDetail({
			liquidationId: "",
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			collateralPrice: 0,
			flagger: msg.sender,
			collectedCollateral: 0,
			requiredCollateral: 0
		});
	}

	function unflagLiquidation(address partyB, address collateral) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED, "LiquidationFacet: PartyB should be flagged");
		delete appLayout.liquidationDetails[partyB][collateral];
	}

	function liquidate(bytes memory liquidationId, address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED,
			"LiquidationFacet: PartyB is already liquidated"
		);
		require(upnl < 0, "LiquidationFacet: Invalid upnl");
		int256 requiredCollateral = (-upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) / int256(collateralPrice);
		require(int256(accountLayout.balances[partyB][collateral].available) < requiredCollateral, "LiquidationFacet: PartyB is solvent");
		LiquidationDetail storage detail = appLayout.liquidationDetails[partyB][collateral];
		detail.liquidationId = liquidationId;
		detail.status = LiquidationStatus.IN_PROGRESS;
		detail.upnl = upnl;
		detail.liquidationTimestamp = block.timestamp;
		detail.collateralPrice = collateralPrice;
		detail.collectedCollateral = accountLayout.balances[partyB][collateral].available;
	}

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.IN_PROGRESS,
			"LiquidationFacet: PartyB is not in liquidation process"
		);
		ScheduledReleaseBalance storage balance = accountLayout.balances[partyA][collateral];
		require(balance.partyBBalance(partyB) > amount, "LiquidationFacet: Insufficient funds");
		balance.subForPartyB(partyB, amount);
		appLayout.liquidationDetails[partyB][collateral].collectedCollateral += amount;
	}

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();

		require(withdrawId <= accountLayout.lastWithdrawId, "LiquidationFacet: Invalid Id");

		Withdraw storage withdraw = accountLayout.withdrawals[withdrawId];
		LiquidationDetail storage detail = appLayout.liquidationDetails[partyB][withdraw.collateral];

		require(detail.status == LiquidationStatus.IN_PROGRESS, "LiquidationFacet: PartyB is not in liquidation process");
		require(withdraw.status == WithdrawStatus.INITIATED, "LiquidationFacet: Invalid withdrawal state");
		require(withdraw.user == partyB, "LiquidationFacet: Invalid user for withdraw Id");

		withdraw.status = WithdrawStatus.CANCELED;
		detail.collectedCollateral += withdraw.amount;
	}

	function closeTrades(uint256[] memory tradeIds, uint256[] memory prices) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();

		require(tradeIds.length == prices.length, "LiquidationFacet: Mismatched arrays");

		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = IntentStorage.layout().trades[tradeIds[i]];
			Symbol storage symbol = SymbolStorage.layout().symbols[trade.tradeAgreements.symbolId];
			uint256 price = prices[i];

			require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid trade state");
			require(
				appLayout.liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.IN_PROGRESS,
				"LiquidationFacet: PartyB is not in liquidation process"
			);
			trade.settledPrice = price;

			uint256 pnl = trade.getPnl(price, trade.tradeAgreements.quantity);

			if (pnl > 0) {
				// uint256 exerciseFee = trade.getExerciseFee(sig.settlementPrice, pnl);
				pnl = (pnl * appLayout.partyBConfigs[trade.partyB].lossCoverage) / 1e18;
				// uint256 amountToTransfer = pnl - exerciseFee;
				uint256 amountToTransfer = pnl;

				amountToTransfer = (amountToTransfer * 1e18) / appLayout.liquidationDetails[trade.partyB][symbol.collateral].collateralPrice;
				if (appLayout.debtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] == 0) {
					appLayout.connectedPartyAs[trade.partyB][symbol.collateral] += 1;
				}
				appLayout.debtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] += amountToTransfer;
				appLayout.liquidationDetails[trade.partyB][symbol.collateral].requiredCollateral += amountToTransfer;

				trade.close(TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			} else {
				trade.close(TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			}
		}
	}

	// TODO: fix deadlock when the required collateral isn't equal with collected collateral

	function distributeCollateral(
		address partyB,
		address collateral,
		address[] memory partyAs
	) internal returns (bool isLiquidationFinished, bytes memory liquidationId, uint256[] memory amounts) {
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LiquidationDetail storage detail = appLayout.liquidationDetails[partyB][collateral];

		require(intentLayout.activeTradesOfPartyB[partyB][collateral].length == 0, "LiquidationFacet: PartyB has still open trades");
		require(detail.status == LiquidationStatus.IN_PROGRESS, "LiquidationFacet: PartyB is not in liquidation process");
		require(detail.collectedCollateral >= detail.requiredCollateral, "LiquidationFacet: not enough collateral to pay debts");

		liquidationId = detail.liquidationId;

		amounts = new uint256[](partyAs.length);
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			uint256 amountToTransfer = appLayout.debtsToPartyAs[partyB][collateral][partyA];
			// if (amountToTransfer == 0) break; //FIXME: why break?
			amounts[i] = amountToTransfer;
			appLayout.connectedPartyAs[partyB][collateral] -= 1;
			accountLayout.balances[partyA][collateral].instantAdd(collateral, amountToTransfer);
			appLayout.debtsToPartyAs[partyB][collateral][partyA] = 0;
		}
		if (appLayout.connectedPartyAs[partyB][collateral] == 0) {
			isLiquidationFinished = true;
			delete appLayout.liquidationDetails[partyB][collateral];
		}
	}
}
