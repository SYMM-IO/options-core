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

	function liquidate(address partyB, address collateral, int256 upnl, uint256 collateralPrice) external;

	function confiscatePartyA(address partyB, address partyA, address collateral, uint256 amount) external;

	function confiscatePartyBWithdrawal(address partyB, uint256 withdrawId) external;

	function unfreezePartyAs(address partyB, address collateral) external;

	function expireTrades(uint256[] memory tradeIds, uint256[] memory prices) external;

	function exerciseTrades(uint256[] memory tradeIds, uint256[] memory prices) external;

	function liquidateTrades(uint256[] memory tradeIds, uint256[] memory closedPrices) external;

	function distributeCollateral(address[] memory partyAs) external;
}
