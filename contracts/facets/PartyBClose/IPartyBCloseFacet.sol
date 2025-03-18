// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { IPartyBCloseEvents } from "./IPartyBCloseEvents.sol";

interface IPartyBCloseFacet is IPartyBCloseEvents {
	function acceptCancelCloseIntent(uint256 intentId) external;

	function fillCloseIntent(uint256 intentId, uint256 quantity, uint256 price) external;
}
