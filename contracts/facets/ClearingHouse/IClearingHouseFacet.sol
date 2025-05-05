// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IClearingHouseEvents } from "./IClearingHouseEvents.sol";

interface IClearingHouseFacet is IClearingHouseEvents {
	// Actions needed for partyB in isolated mode
	function flagIsolatedPartyBLiquidation(address partyB, address collateral) external;

	function unflagIsolatedPartyBLiquidation(address partyB, address collateral) external;

	function liquidateIsolatedPartyB(bytes32 liquidationId, address partyB, address collateral, int256 upnl, uint256 collateralPrice) external;

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) external;

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) external;

	// function unfreezePartyAs(address partyB, address collateral) external;

	function distributeCollateral(address partyB, address collateral, address[] memory partyAs, uint256[] memory amounts) external;

	// Actions needed for partyB in cross
	function flagCrossPartyBLiquidation(address partyB, address partyA, address collateral) external;

	function unflagCrossPartyBLiquidation(address partyB, address partyA, address collateral) external;

	function liquidateCrossPartyB(
		bytes32 liquidationId,
		address partyB,
		address partyA,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external;

	// Actions needed for partyA in cross
	function flagPartyALiquidation(address partyA, address partyB, address collateral) external;

	function unflagPartyALiquidation(address partyA, address partyB, address collateral) external;

	function liquidateCrossPartyA(
		bytes32 liquidationId,
		address partyA,
		address partyB,
		address collateral,
		int256 upnl,
		uint256 collateralPrice
	) external;

	// Common actions
	function closeTrades(uint256[] memory tradeIds, uint256[] memory prices) external;

	function allocateFromReserveToCross(address party, address counterParty, address collateral, uint256 amount) external;
}
