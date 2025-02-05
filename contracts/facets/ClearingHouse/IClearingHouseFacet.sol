// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IClearingHouseEvents.sol";
import "../../storages/AppStorage.sol";

interface IClearingHouseFacet is IClearingHouseEvents {
	function suspendPartyA(address partyA, address collateral) external;

	function blockPartyABalance(address partyA, address collateral) external;

	function cancelPartyBWithdrawal(uint256 withdrawId) external;

	function flagLiquidation(address partyB, address collateral) external;

	function unflagLiquidation(address partyB, address collateral) external;

	function liquidate(address partyB, address collateral) external;

	function expireTrades(uint256[] memory tradeIds) external;

	function exerciseTrades(uint256[] memory tradeIds, uint256[] memory prices) external;

	function liquidateTrades(uint256[] memory tradeIds, uint256[] memory closedPrices) external;

	function settleBalances(address partyA, address collateral) external;
}
