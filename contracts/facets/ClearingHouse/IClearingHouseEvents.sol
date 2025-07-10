// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

interface IClearingHouseEvents {
	event FlagIsolatedPartyBLiquidation(address indexed operator, address indexed partyB, address indexed collateral);
	event UnflagIsolatedPartyBLiquidation(address indexed operator, address indexed partyB, address indexed collateral);
	event LiquidateIsolatedPartyB(
		address indexed operator,
		address indexed partyB,
		address indexed collateral,
		uint256 balance,
		int256 upnl,
		uint256 collateralPrice
	);
	event ConfiscatePartyA(address indexed operator, uint256 liquidationId, uint256 amount);
	event ConfiscatePartyBWithdrawal(address indexed operator, uint256 withdrawId);
	event DistributeCollateral(address indexed operator, address indexed partyB, address indexed collateral, address[] partyAs, uint256[] amounts);
	event FullyLiquidated(address indexed partyB, uint256 liquidationId);
	event FlagCrossPartyBLiquidation(address operator, address indexed partyB, address indexed partyA, address indexed collateral);
	event UnflagCrossPartyBLiquidation(address operator, address indexed partyB, address indexed partyA, address indexed collateral);
	event LiquidateCrossPartyB(
		address operator,
		address indexed partyB,
		address indexed partyA,
		address indexed collateral,
		int256 upnl,
		uint256 collateralPrice
	);
	event FlagPartyALiquidation(address operator, address indexed partyA, address indexed partyB, address indexed collateral);
	event UnflagPartyALiquidation(address operator, address indexed partyA, address indexed partyB, address indexed collateral);
	event LiquidateCrossPartyA(
		address operator,
		uint256 liquidationId,
		address partyA,
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	);
	event CloseTradesForLiquidation(address operator, uint256 liquidationId, uint256[] tradeIds, uint256[] prices);
	event CancelOpenIntentsForLiquidation(address operator, uint256[] intentIds);
	event CancelCloseIntentsForLiquidation(address operator, uint256[] intentIds);
	event AllocateFromReserveToCross(address operator, address party, address counterParty, address collateral, uint256 amount);
}
