// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { MarginType } from "../../types/BaseTypes.sol";

import { IPartyBOpenEvents } from "./IPartyBOpenEvents.sol";

interface IPartyBOpenFacet is IPartyBOpenEvents {
	function lockOpenIntent(uint256 intentId) external;

	function unlockOpenIntent(uint256 intentId) external;

	function acceptCancelOpenIntent(uint256 intentId) external;

	function fillOpenIntent(uint256 intentId, uint256 quantity, uint256 price) external;
}
