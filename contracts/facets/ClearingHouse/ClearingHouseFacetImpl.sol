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

	function flagLiquidation(address partyB, address collateral) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.SOLVENT,
			"LiquidationFacet: PartyB is in the liquidation process"
		);
		require(appLayout.partyBConfigs[partyB].lossCoverage > 0, "LiquidationFacet: Loss coverage of partyB is zero");
		appLayout.liquidationDetails[partyB][collateral] = LiquidationDetail({
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			liquidationTimestamp: 0,
			collateralPrice: 0,
			flagger: msg.sender,
			collectedCollateral: 0
		});
	}

	function unflagLiquidation(address partyB, address collateral) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED, "LiquidationFacet: PartyB should be flagged");
		delete appLayout.liquidationDetails[partyB][collateral];
	}

	function liquidate(address partyB, address collateral, int256 upnl, uint256 collateralPrice) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED,
			"LiquidationFacet: PartyB is already liquidated"
		);
		require(upnl < 0, "LiquidationFacet: Invalid upnl");
		int256 requiredCollateral = (-upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) / int256(collateralPrice);
		require(requiredCollateral > int256(accountLayout.balances[partyB][collateral].available), "LiquidationFacet: PartyB is solvent");
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
		// TODO: shouldn't be synced
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
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		require(tradeIds.length == prices.length, "LiquidationFacet: Invalid length");
		for (uint256 i = 0; i < tradeIds.length; i++) {
			Trade storage trade = IntentStorage.layout().trades[tradeIds[i]];
			Symbol storage symbol = SymbolStorage.layout().symbols[trade.symbolId];
			uint256 price = prices[i];
			require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid trade state");
			require(block.timestamp > trade.expirationTimestamp, "LiquidationFacet: Trade isn't expired");
			require(
				AppStorage.layout().liquidationDetails[trade.partyB][symbol.collateral].status == LiquidationStatus.IN_PROGRESS,
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
				uint256 amountToTransfer = pnl - exerciseFee;
				if (!symbol.isStableCoin) {
					amountToTransfer = (amountToTransfer * 1e18) / price;
				}

				accountLayout.balances[trade.partyA][symbol.collateral].instantAdd(amountToTransfer); //CHECK: instantAdd or add?
				accountLayout.balances[trade.partyB][symbol.collateral].sub(amountToTransfer);

				LibIntent.closeTrade(trade.id, TradeStatus.EXERCISED, IntentStatus.CANCELED);
			} else {
				LibIntent.closeTrade(trade.id, TradeStatus.EXPIRED, IntentStatus.CANCELED);
			}
		}
	}

	// function setSymbolsPrice(address partyB, LiquidationSig memory liquidationSig) internal {
	// 	AppStorage.Layout storage appLayout = AppStorage.layout();
	// 	LibMuon.verifyLiquidationSig(liquidationSig, partyB);
	// 	require(
	// 		appLayout.liquidationDetails[partyB][liquidationSig.collateral].status == LiquidationStatus.IN_PROGRESS,
	// 		"LiquidationFacet: PartyB is solvent"
	// 	);
	// 	require(
	// 		keccak256(appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationId) == keccak256(liquidationSig.liquidationId),
	// 		"LiquidationFacet: Invalid liquidationId"
	// 	);
	// 	for (uint256 index = 0; index < liquidationSig.symbolIds.length; index++) {
	// 		appLayout.symbolsPrices[partyB][liquidationSig.symbolIds[index]] = Price(
	// 			liquidationSig.prices[index],
	// 			appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationTimestamp
	// 		);
	// 	}
	// }

	// function liquidateTrades(
	// 	address partyB,
	// 	address collateral,
	// 	uint256[] memory tradeIds
	// ) internal returns (uint256[] memory liquidatedAmounts, int256[] memory pnls, bytes memory liquidationId, bool isFullyLiquidated) {
	// 	AppStorage.Layout storage appLayout = AppStorage.layout();
	// 	IntentStorage.Layout storage intentLayout = IntentStorage.layout();
	// 	liquidatedAmounts = new uint256[](tradeIds.length);
	// 	pnls = new int256[](tradeIds.length);
	// 	liquidationId = appLayout.liquidationDetails[partyB][collateral].liquidationId;
	// 	require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.IN_PROGRESS, "LiquidationFacet: PartyB is solvent");

	// 	for (uint256 index = 0; index < tradeIds.length; index++) {
	// 		Trade storage trade = intentLayout.trades[tradeIds[index]];
	// 		require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid state");
	// 		require(trade.partyB == partyB, "LiquidationFacet: Invalid party");
	// 		require(
	// 			appLayout.symbolsPrices[partyB][trade.symbolId].timestamp == appLayout.liquidationDetails[partyB][collateral].liquidationTimestamp,
	// 			"LiquidationFacet: Price should be set"
	// 		);
	// 		liquidatedAmounts[index] = LibIntent.tradeOpenAmount(trade);
	// 		trade.status = TradeStatus.LIQUIDATED;
	// 		trade.statusModifyTimestamp = block.timestamp;
	// 		uint256 profit = LibIntent.getValueOfTradeForPartyA(
	// 			appLayout.symbolsPrices[partyB][trade.symbolId].price,
	// 			LibIntent.tradeOpenAmount(trade),
	// 			trade
	// 		);
	// 		pnls[index] = int256(profit);
	// 		if (profit > 0) {
	// 			uint256 balanceToTransfer = (profit * appLayout.liquidationDetails[partyB][collateral].lossFactor) /
	// 				appLayout.liquidationDetails[partyB][collateral].collateralPrice;
	// 			AccountStorage.layout().balances[partyB][collateral].sub(balanceToTransfer);
	// 			AccountStorage.layout().balances[trade.partyA][collateral].instantAdd(balanceToTransfer);
	// 		}
	// 		trade.settledPrice = appLayout.symbolsPrices[partyB][trade.symbolId].price;
	// 		LibIntent.closeTrade(trade.id, TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
	// 		trade.closedAmountBeforeExpiration = trade.quantity;
	// 		LibIntent.removeFromActiveTrades(trade.id);
	// 	}
	// 	// check if full liuidated
	// 	if (intentLayout.activeTradesOfPartyB[partyB][collateral].length == 0) {
	// 		isFullyLiquidated = true;
	// 		delete appLayout.liquidationDetails[partyB][collateral];
	// 	}
	// }
}
