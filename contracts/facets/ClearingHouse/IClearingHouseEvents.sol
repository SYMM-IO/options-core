// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface IClearingHouseEvents {
	event FlagIsolatedPartyBLiquidation(address operator, address partyB, address collateral);
	event UnflagIsolatedPartyBLiquidation(address operator, address partyB, address collateral);
	event LiquidateIsolatedPartyB(address operator, address partyB, address collateral, uint256 balance, int256 upnl, uint256 collateralPrice);
	event ConfiscatePartyA(uint256 liquidationId, uint256 amount);
	event ConfiscatePartyBWithdrawal(address partyB, uint256 withdrawId);
	event DistributeCollateral(address operator, address partyB, address collateral, address[] partyAs, uint256[] amounts);
	event FullyLiquidated(address partyB, uint256 liquidationId);
	event FlagCrossPartyBLiquidation(address operator, address partyB, address partyA, address collateral);
	event UnflagCrossPartyBLiquidation(address operator, address partyB, address partyA, address collateral);
	event LiquidateCrossPartyB(address operator, address partyB, address partyA, address collateral, int256 upnl, uint256 collateralPrice);
	event FlagPartyALiquidation(address operator, address partyA, address partyB, address collateral);
	event UnflagPartyALiquidation(address operator, address partyA, address partyB, address collateral);
	event LiquidateCrossPartyA(
		address operator,
		uint256 liquidationId,
		address partyA,
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	);
	event CloseTradesForLiquidation(address operator, uint256[] tradeIds, uint256[] prices);
}
