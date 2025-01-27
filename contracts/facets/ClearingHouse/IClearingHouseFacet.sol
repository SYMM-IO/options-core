// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IClearingHouseEvents.sol";
import "../../storages/AppStorage.sol";

interface IClearingHouseFacet is IClearingHouseEvents {
	function flagLiquidation(address partyB, address collateral) external;

	function unflagLiquidation(address partyB, address collateral) external;

	// function forceUnflagLiquidation(address partyB, address collateral) external;

	function liquidate(address partyB, LiquidationSig memory liquidationSig) external;

	function setSymbolsPrice(address partyB, LiquidationSig memory liquidationSig) external;

	function liquidateTrades(address partyB, address collateral, uint256[] memory tradeIds) external;

	// TODO: revert back withdrawal

	// TODO: suspend the new closed amount and revert it back

	// TODO: distribute the collateral between counter parties
}
