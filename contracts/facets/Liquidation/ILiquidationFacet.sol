// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./ILiquidationEvents.sol";
import "../../storages/AppStorage.sol";

interface ILiquidationFacet is ILiquidationEvents {
	function flagLiquidation(address partyB, address collateral) external;

	function unflagLiquidation(address partyB, address collateral) external;

	function forceUnflagLiquidation(address partyB, address collateral) external;

	function liquidate(address partyB, LiquidationSig memory liquidationSig) external;

	function setSymbolsPrice(address partyB, LiquidationSig memory liquidationSig) external;

	function liquidateTrades(address partyB, address collateral, uint256[] memory tradeIds) external;
}
