// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartyACloseEvents } from "./IPartyACloseEvents.sol";

interface IPartyACloseFacet is IPartyACloseEvents {
	function expireCloseIntent(uint256[] memory expiredIntentIds) external;

	function cancelCloseIntent(uint256[] memory intentIds) external;

	function sendCloseIntent(uint256 tradeId, uint256 price, uint256 quantity, uint256 deadline) external;

	function transferTrade(address receiver, uint256 tradeId) external;
}
