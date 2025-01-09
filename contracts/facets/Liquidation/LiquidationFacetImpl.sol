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

		appLayout.liquidationDetails[partyB][collateral] = LiquidationDetail({
			liquidationId: "",
			status: LiquidationStatus.FLAGGED,
			upnl: 0,
			flagTimestamp: block.timestamp,
			involvedPartyACounts: 0,
			liquidationTimestamp: 0,
			liquidators: new address[](2)
		});
	}

	function liquidate(address partyB, address collateral, LiquidationSig memory liquidationSig) internal {
		AppStorage.Layout storage appLayout = AppStorage.layout();
		AccountStorage.Layout storage accountLayout = AccountStorage.layout();

		LibMuon.verifyLiquidationSig(liquidationSig, partyB, collateral);
		require(block.timestamp <= liquidationSig.timestamp + appLayout.liquidationSigValidTime, "LiquidationFacet: Expired signature");
		require(
			liquidationSig.timestamp > appLayout.liquidationDetails[partyB][collateral].flagTimestamp,
			"LiquidationFacet: Signature should be retrived after flagging"
		);
		require(
			appLayout.liquidationDetails[partyB][collateral].status == LiquidationStatus.FLAGGED,
			"LiquidationFacet: PartyB is already liquidated"
		);
		require(liquidationSig.upnl < 0, "LiquidationFacet: Invalid upnl");

		int256 availableBalance = (liquidationSig.upnl * int256(appLayout.partyBConfigs[partyB].lossCoverage)) /
			1e18 +
			int256(accountLayout.balances[partyB][collateral]);

		require(availableBalance < 0, "LiquidationFacet: PartyB is solvent");
		appLayout.liquidationDetails[partyB][collateral].status = LiquidationStatus.IN_PROGRESS;
		appLayout.liquidationDetails[partyB][collateral].liquidationId = liquidationSig.liquidationId;
		appLayout.liquidationDetails[partyB][collateral].upnl = liquidationSig.upnl;
		appLayout.liquidationDetails[partyB][collateral].liquidationTimestamp = liquidationSig.timestamp;
		appLayout.liquidationDetails[partyB][collateral].liquidators.push(msg.sender);
	}

	function setSymbolsPrice(address partyB, LiquidationSig memory liquidationSig) internal {
		// AppStorage.Layout storage appLayout = AppStorage.layout();
		// LibMuon.verifyLiquidationSig(liquidationSig, partyB);
		// require(
		//     appLayout.liquidationStatus[partyB],
		//     "LiquidationFacet: PartyB is solvent"
		// );
		// require(
		//     keccak256(appLayout.liquidationDetails[partyB].liquidationId) ==
		//         keccak256(liquidationSig.liquidationId),
		//     "LiquidationFacet: Invalid liquidationId"
		// );
		// for (
		//     uint256 index = 0;
		//     index < liquidationSig.symbolIds.length;
		//     index++
		// ) {
		//     appLayout.symbolsPrices[partyB][
		//         liquidationSig.symbolIds[index]
		//     ] = Price(
		//         liquidationSig.prices[index],
		//         appLayout.liquidationDetails[partyB].timestamp
		//     );
		// }
	}

	function liquidateOpenIntents(
		address partyB,
		uint256[] memory openIntentIds
	) internal returns (uint256[] memory liquidatedAmounts, bytes memory liquidationId) {
		// IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		// AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		// AppStorage.Layout storage appLayout = AppStorage.layout();
		// require(
		//     AppStorage.layout().liquidationStatus[partyB],
		//     "LiquidationFacet: PartyA is solvent"
		// );
		// liquidatedAmounts = new uint256[](openIntentIds.length);
		// liquidationId = appLayout.liquidationDetails[partyB].liquidationId;
		// for (uint256 index = 0; index < openIntentIds.length; index++) {
		//     OpenIntent storage intent = intentLayout.openIntents[
		//         openIntentIds[index]
		//     ];
		//     require(
		//         intent.status == IntentStatus.LOCKED ||
		//             intent.status == IntentStatus.CANCEL_PENDING,
		//         "LiquidationFacet: Invalid state"
		//     );
		//     require(intent.partyB == partyB, "LiquidationFacet: Invalid party");
		//     intent.statusModifyTimestamp = block.timestamp;
		//     accountLayout.lockedBalances[intent.partyA] -= LibIntent
		//         .getPremiumOfOpenIntent(intent.id);
		//     // send trading Fee back to partyA
		//     uint256 fee = LibIntent.getTradingFee(intent.id);
		//     accountLayout.balances[intent.partyA] += fee;
		//     LibIntent.removeFromPartyAOpenIntents(intent.id);
		//     LibIntent.removeFromPartyBOpenIntents(intent.id);
		//     intent.status = IntentStatus.CANCELED;
		//     liquidatedAmounts[index] = intent.quantity;
		// }
	}

	function liquidateTrades(
		address partyB,
		uint256[] memory tradeIds
	) internal returns (uint256[] memory liquidatedAmounts, bytes memory liquidationId) {
		// AppStorage.Layout storage appLayout = AppStorage.layout();
		// IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		// liquidatedAmounts = new uint256[](tradeIds.length);
		// liquidationId = appLayout.liquidationDetails[partyB].liquidationId;
		// require(
		//     appLayout.liquidationStatus[partyB],
		//     "LiquidationFacet: PartyA is solvent"
		// );
		// for (uint256 index = 0; index < tradeIds.length; index++) {
		//     Trade storage trade = intentLayout.trades[tradeIds[index]];
		//     require(
		//         trade.status == TradeStatus.OPENED,
		//         "LiquidationFacet: Invalid state"
		//     );
		//     require(trade.partyB == partyB, "LiquidationFacet: Invalid party");
		//     require(
		//         appLayout.symbolsPrices[partyB][trade.symbolId].timestamp ==
		//             appLayout.liquidationDetails[partyB].timestamp,
		//         "LiquidationFacet: Price should be set"
		//     );
		//     liquidatedAmounts[index] = LibIntent.tradeOpenAmount(trade);
		//     trade.status = TradeStatus.LIQUIDATED;
		//     trade.statusModifyTimestamp = block.timestamp;
		//     uint256 profit = LibIntent.getValueOfTradeForPartyA(
		//         appLayout.symbolsPrices[partyB][trade.symbolId].price,
		//         LibIntent.tradeOpenAmount(trade),
		//         trade
		//     );
		//     if (!appLayout.settlementStates[partyB][trade.partyA].pending) {
		//         appLayout.settlementStates[partyB][trade.partyA].pending = true;
		//         appLayout.liquidationDetails[partyB].involvedPartyACounts += 1;
		//     }
		//     appLayout.settlementStates[partyB][trade.partyA].amount -= int256(
		//         profit
		//     );
		//     // accountLayout.lockedBalances[trade.partyA].subQuote(trade);
		//     trade.settledPrice = appLayout
		//     .symbolsPrices[partyB][trade.symbolId].price;
		//     LibIntent.closeTrade(
		//         trade.id,
		//         TradeStatus.LIQUIDATED,
		//         IntentStatus.CANCELED
		//     );
		//     trade.closedAmountBeforeExpiration = trade.quantity;
		//     LibIntent.removeFromActiveTrades(trade.id);
		// }
	}
	function settleLiquidation(
		address partyB,
		address[] memory partyAs
	) internal returns (int256[] memory settleAmounts, bytes memory liquidationId) {
		// AccountStorage.Layout storage accountLayout = AccountStorage.layout();
		// IntentStorage.Layout storage intentLayout = IntentStorage.layout();
		// require(
		//     intentLayout.partyAPositionsCount[partyA] == 0 &&
		//         intentLayout.partyAPendingQuotes[partyA].length == 0,
		//     "LiquidationFacet: PartyA has still open positions"
		// );
		// require(
		//     MAStorage.layout().liquidationStatus[partyA],
		//     "LiquidationFacet: PartyA is solvent"
		// );
		// require(
		//     !accountLayout.liquidationDetails[partyA].disputed,
		//     "LiquidationFacet: PartyA liquidation process get disputed"
		// );
		// liquidationId = accountLayout.liquidationDetails[partyA].liquidationId;
		// settleAmounts = new int256[](partyBs.length);
		// for (uint256 i = 0; i < partyBs.length; i++) {
		//     address partyB = partyBs[i];
		//     require(
		//         accountLayout.settlementStates[partyA][partyB].pending,
		//         "LiquidationFacet: PartyB is not in settlement"
		//     );
		//     accountLayout.settlementStates[partyA][partyB].pending = false;
		//     accountLayout.liquidationDetails[partyA].involvedPartyBCounts -= 1;
		//     int256 settleAmount = accountLayout
		//     .settlementStates[partyA][partyB].actualAmount;
		//     accountLayout.partyBAllocatedBalances[partyB][
		//         partyA
		//     ] += accountLayout.settlementStates[partyA][partyB].cva;
		//     emit SharedEvents.BalanceChangePartyB(
		//         partyB,
		//         partyA,
		//         accountLayout.settlementStates[partyA][partyB].cva,
		//         SharedEvents.BalanceChangeType.CVA_IN
		//     );
		//     if (settleAmount < 0) {
		//         accountLayout.partyBAllocatedBalances[partyB][
		//             partyA
		//         ] += uint256(-settleAmount);
		//         emit SharedEvents.BalanceChangePartyB(
		//             partyB,
		//             partyA,
		//             uint256(-settleAmount),
		//             SharedEvents.BalanceChangeType.REALIZED_PNL_IN
		//         );
		//         settleAmounts[i] = settleAmount;
		//     } else {
		//         if (
		//             accountLayout.partyBAllocatedBalances[partyB][partyA] >=
		//             uint256(settleAmount)
		//         ) {
		//             accountLayout.partyBAllocatedBalances[partyB][
		//                 partyA
		//             ] -= uint256(settleAmount);
		//             settleAmounts[i] = settleAmount;
		//             emit SharedEvents.BalanceChangePartyB(
		//                 partyB,
		//                 partyA,
		//                 uint256(settleAmount),
		//                 SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		//             );
		//         } else {
		//             settleAmounts[i] = int256(
		//                 accountLayout.partyBAllocatedBalances[partyB][partyA]
		//             );
		//             accountLayout.partyBAllocatedBalances[partyB][partyA] = 0;
		//             emit SharedEvents.BalanceChangePartyB(
		//                 partyB,
		//                 partyA,
		//                 uint256(settleAmounts[i]),
		//                 SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		//             );
		//         }
		//     }
		//     delete accountLayout.settlementStates[partyA][partyB];
		// }
		// if (
		//     accountLayout.liquidationDetails[partyA].involvedPartyBCounts == 0
		// ) {
		//     emit SharedEvents.BalanceChangePartyA(
		//         partyA,
		//         accountLayout.allocatedBalances[partyA],
		//         SharedEvents.BalanceChangeType.REALIZED_PNL_OUT
		//     );
		//     accountLayout.allocatedBalances[partyA] = accountLayout
		//         .partyAReimbursement[partyA];
		//     accountLayout.partyAReimbursement[partyA] = 0;
		//     accountLayout.lockedBalances[partyA].makeZero();
		//     uint256 lf = accountLayout
		//         .liquidationDetails[partyA]
		//         .liquidationFee;
		//     if (lf > 0) {
		//         accountLayout.allocatedBalances[
		//             accountLayout.liquidators[partyA][0]
		//         ] += lf / 2;
		//         accountLayout.allocatedBalances[
		//             accountLayout.liquidators[partyA][1]
		//         ] += lf / 2;
		//         emit SharedEvents.BalanceChangePartyA(
		//             accountLayout.liquidators[partyA][0],
		//             lf / 2,
		//             SharedEvents.BalanceChangeType.LF_IN
		//         );
		//         emit SharedEvents.BalanceChangePartyA(
		//             accountLayout.liquidators[partyA][1],
		//             lf / 2,
		//             SharedEvents.BalanceChangeType.LF_IN
		//         );
		//     }
		//     delete accountLayout.liquidators[partyA];
		//     delete accountLayout.liquidationDetails[partyA].liquidationType;
		//     MAStorage.layout().liquidationStatus[partyA] = false;
		//     accountLayout.partyANonces[partyA] += 1;
		// }
	}
}
