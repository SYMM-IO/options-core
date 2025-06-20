// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { ICounterPartyRelationsEvents } from "./ICounterPartyRelationsEvents.sol";

interface ICounterPartyRelationsFacet is ICounterPartyRelationsEvents {
	function activateInstantActionMode() external;

	function proposeToDeactivateInstantActionMode() external;

	function deactivateInstantActionMode() external;

	function bindToPartyB(address partyB) external;

	function initiateUnbindingFromPartyB() external;

	function completeUnbindingFromPartyB() external;

	function cancelUnbindingFromPartyB() external;
}
