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

library LiquidationFacetImpl {
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
			lossFactor: 0,
			collateralPrice: 0,
			flagger: msg.sender
		});
	}

	function unflagLiquidation(address partyB, address collateral, bool checkFlagger) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED, "LiquidationFacet: PartyB should be flagged");
		if (checkFlagger) {
			require(msg.sender == appLayout.liquidationDetails[partyB][collateral].flagger, "LiquidationFacet: Sender should be the flagger");
		}
		appLayout.liquidationDetails[partyB][collateral].status = LiquidationStatus.SOLVENT;
		appLayout.liquidationDetails[partyB][collateral].flagger = address(0);
	}

	function liquidate(address partyB, LiquidationSig memory liquidationSig) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuon.verifyLiquidationSig(liquidationSig, partyB);
		require(block.timestamp <= liquidationSig.timestamp + appLayout.liquidationSigValidTime, "LiquidationFacet: Expired signature");
		require(
			liquidationSig.timestamp > appLayout.liquidationDetails[partyB][liquidationSig.collateral].flagTimestamp,
			"LiquidationFacet: Signature should be retrived after flagging"
		);
		require(
			appLayout.liquidationDetails[partyB][liquidationSig.collateral].status == LiquidationStatus.FLAGGED,
			"LiquidationFacet: PartyB is already liquidated"
		);
		require(liquidationSig.upnl < 0, "LiquidationFacet: Invalid upnl");
		int256 requiredCollateral = (-liquidationSig.upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) /
			int256(liquidationSig.collateralPrice);
		require(requiredCollateral > int256(accountLayout.balances[partyB][liquidationSig.collateral]), "LiquidationFacet: PartyB is solvent");
		int256 loss = requiredCollateral - int256(accountLayout.balances[partyB][liquidationSig.collateral]);
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].status = LiquidationStatus.IN_PROGRESS;
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationId = liquidationSig.liquidationId;
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].upnl = liquidationSig.upnl;
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].lossFactor = uint256((loss * 1e18) / requiredCollateral);
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationTimestamp = liquidationSig.timestamp;
		appLayout.liquidationDetails[partyB][liquidationSig.collateral].collateralPrice = liquidationSig.collateralPrice;
	}

	function setSymbolsPrice(address partyB, LiquidationSig memory liquidationSig) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		LibMuon.verifyLiquidationSig(liquidationSig, partyB);
		require(
			appLayout.liquidationDetails[partyB][liquidationSig.collateral].status == LiquidationStatus.IN_PROGRESS,
			"LiquidationFacet: PartyB is solvent"
		);
		require(
			keccak256(appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationId) == keccak256(liquidationSig.liquidationId),
			"LiquidationFacet: Invalid liquidationId"
		);
		for (uint256 index = 0; index < liquidationSig.symbolIds.length; index++) {
			appLayout.symbolsPrices[partyB][liquidationSig.symbolIds[index]] = Price(
				liquidationSig.prices[index],
				appLayout.liquidationDetails[partyB][liquidationSig.collateral].liquidationTimestamp
			);
		}
	}

	function liquidateTrades(
		address partyB,
		address collateral,
		uint256[] memory tradeIds
	) internal returns (uint256[] memory liquidatedAmounts, int256[] memory pnls, bytes memory liquidationId, bool isFullyLiquidated) {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		liquidatedAmounts = new uint256[](tradeIds.length);
		pnls = new int256[](tradeIds.length);
		liquidationId = appLayout.liquidationDetails[partyB][collateral].liquidationId;
		require(appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.IN_PROGRESS, "LiquidationFacet: PartyB is solvent");

		for (uint256 index = 0; index < tradeIds.length; index++) {
			Trade storage trade = intentLayout.trades[tradeIds[index]];
			require(trade.status == TradeStatus.OPENED, "LiquidationFacet: Invalid state");
			require(trade.partyB == partyB, "LiquidationFacet: Invalid party");
			require(
				appLayout.symbolsPrices[partyB][trade.symbolId].timestamp == appLayout.liquidationDetails[partyB][collateral].liquidationTimestamp,
				"LiquidationFacet: Price should be set"
			);
			liquidatedAmounts[index] = LibIntent.tradeOpenAmount(trade);
			trade.status = TradeStatus.LIQUIDATED;
			trade.statusModifyTimestamp = block.timestamp;
			uint256 profit = LibIntent.getValueOfTradeForPartyA(
				appLayout.symbolsPrices[partyB][trade.symbolId].price,
				LibIntent.tradeOpenAmount(trade),
				trade
			);
			pnls[index] = int256(profit);
			if (profit > 0) {
				uint256 balanceToTransfer = (profit * appLayout.liquidationDetails[partyB][collateral].lossFactor) /
					appLayout.liquidationDetails[partyB][collateral].collateralPrice;
				AccountStorage.layout().balances[partyB][collateral] -= balanceToTransfer;
				AccountStorage.layout().balances[trade.partyA][collateral] += balanceToTransfer;
			}
			trade.settledPrice = appLayout.symbolsPrices[partyB][trade.symbolId].price;
			LibIntent.closeTrade(trade.id, TradeStatus.LIQUIDATED, IntentStatus.CANCELED);
			trade.closedAmountBeforeExpiration = trade.quantity;
			LibIntent.removeFromActiveTrades(trade.id);
		}
		// check if full liuidated
		if (intentLayout.activeTradesOfPartyB[partyB][collateral].length == 0) {
			isFullyLiquidated = true;
			delete appLayout.liquidationDetails[partyB][collateral];
		}
	}
}
