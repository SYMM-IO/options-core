// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../libraries/LibIntent.sol";
import "../../libraries/LibMuon.sol";
import "../../storages/AppStorage.sol";
import "../../storages/IntentStorage.sol";
import "../../storages/AccountStorage.sol";
import "../../storages/SymbolStorage.sol";

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
		appLayout.liquidationDetails[partyB][collateral].liquidationId = liquidationId;
		appLayout.liquidationDetails[partyB][collateral].status = LiquidationStatus.IN_PROGRESS;
		appLayout.liquidationDetails[partyB][collateral].upnl = upnl;
		appLayout.liquidationDetails[partyB][collateral].liquidationTimestamp = block.timestamp;
		appLayout.liquidationDetails[partyB][collateral].collateralPrice = collateralPrice;
		appLayout.liquidationDetails[partyB][collateral].collectedCollateral = accountLayout.balances[partyB][collateral].available;
	}

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(
			AppStorage.layout().liquidationDetails[partyB][collateral].status == LiquidationStatus.IN_PROGRESS,
			"LiquidationFacet: PartyB is already liquidated"
		);
		require(
			accountLayout.balances[partyA][collateral].partyBSchedules[partyB].scheduled +
				accountLayout.balances[partyA][collateral].partyBSchedules[partyB].transitioning <
				amount,
			"LiquidationFacet: The amount is so high"
		);
		accountLayout.balances[partyA][collateral].subForPartyB(partyB, amount);
		AppStorage.layout().liquidationDetails[partyB][collateral].collectedCollateral += amount;
	}

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) internal {
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(withdrawId <= accountLayout.lastWithdrawId, "LiquidationFacet: Invalid Id");
		Withdraw storage w = accountLayout.withdrawals[withdrawId];

		require(
			AppStorage.layout().liquidationDetails[partyB][w.collateral].status == LiquidationStatus.IN_PROGRESS,
			"LiquidationFacet: PartyB is already liquidated"
		);

		require(w.status == WithdrawStatus.INITIATED, "LiquidationFacet: Invalid state");
		require(w.user == partyB, "LiquidationFacet: Invalid user for withdraw Id");

		w.status = WithdrawStatus.CANCELED;
		AppStorage.layout().liquidationDetails[partyB][w.collateral].collectedCollateral += w.amount;
	}

	function closeTrades(uint256[] memory tradeIds, uint256[] memory prices) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(tradeIds.length == prices.length, "LiquidationFacet: Invalid length");
		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = IntentStorage.layout().trades[tradeIds[i]];
			Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
			uint256 price = prices[i];
			require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid trade state");
			require(
				appLayout.liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.IN_PROGRESS,
				"LiquidationFacet: PartyB is liquidated"
			);
			trade.settledPrice = price;

			uint256 pnl;
			if (symbol.optionType == OptionType.PUT) {
				if (price < trade.strikePrice) {
					pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (trade.strikePrice - price)) / 1e18;
				}
			} else {
				if (price > trade.strikePrice) {
					pnl = ((trade.quantity - trade.closedAmountBeforeExpiration) * (price - trade.strikePrice)) / 1e18;
				}
			}
			if (pnl > 0) {
				uint256 exerciseFee;
				{
					uint256 cap = (trade.exerciseFee.cap * pnl) / 1e18;
					uint256 fee = (trade.exerciseFee.rate * price * (trade.quantity - trade.closedAmountBeforeExpiration)) / 1e36;
					exerciseFee = cap < fee ? cap : fee;
				}
				// TODO: handle loss factor
				uint256 amountToTransfer = pnl - exerciseFee;
				amountToTransfer = (amountToTransfer * 1e18) / appLayout.liquidationDetails[trade.partyB][symbol.collateral].collateralPrice;
				if (appLayout.debtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] == 0) {
					appLayout.connectedPartyAs[trade.partyB][symbol.collateral] += 1;
				}
				appLayout.debtsToPartyAs[trade.partyB][symbol.collateral][trade.partyA] += amountToTransfer;
				appLayout.liquidationDetails[trade.partyB][symbol.collateral].requiredCollateral += amountToTransfer;

				trade.close( TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			} else {
				trade.close( TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
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

		require(intentLayout.activeTradesOfPartyB[partyB][collateral].length == 0, "LiquidationFacet: PartyB has still open trades");
		require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.IN_PROGRESS, "LiquidationFacet: PartyB is liquidated");
		require(
			appLayout.liquidationDetails[partyB][collateral].collectedCollateral >=
				appLayout.liquidationDetails[partyB][collateral].requiredCollateral,
			"LiquidationFacet: not enough collateral to pay debts"
		);
		liquidationId = appLayout.liquidationDetails[partyB][collateral].liquidationId;
		amounts = new uint256[](partyAs.length);
		for (uint256 i = 0; i < partyAs.length; i++) {
			address partyA = partyAs[i];
			uint256 amountToTransfer = appLayout.debtsToPartyAs[partyB][collateral][partyA];
			if (amountToTransfer == 0) {
				break;
			}
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
