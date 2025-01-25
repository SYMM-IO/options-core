// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;
interface IClearingHouseEvents {
	event FlagLiquidation(address liquidator, address partyB, address collateral);
	event UnflagLiquidation(address operator, address partyB, address collateral);
	event Liquidate(
		address liquidator,
		address partyB,
		address collateral,
		uint256 balance,
		int256 upnl,
		uint256 collateralPrice,
		bytes liquidationId
	);
	event SetSymbolsPrices(address liquidator, address partyB, uint256[] symbolIds, uint256[] prices, bytes liquidationId);
	event LiquidateTrades(address liquidator, address partyB, uint256[] tradeIds, uint256[] liquidatedAmounts, int256[] pnls, bytes liquidationId);
	event FullyLiquidated(address partyB, bytes liquidationId);
}
