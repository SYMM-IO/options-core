// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IExpressWithdrawEvents } from "./IExpressWithdrawEvents.sol";

interface IExpressWithdrawFacet is IExpressWithdrawEvents {
	function expressWithdraw(address collateral, uint256 amount, address provider, address receiver) external;

	function suspendExpressWithdraw(uint256 expressWithdrawId) external;

	function restoreExpressWithdraw(uint256 expressWithdrawId, uint256 validAmount) external;

	function collectReceivedExpressWithdraws(uint256[] memory expressWithdrawIds) external;
}
