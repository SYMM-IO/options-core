// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";

interface IPartyBCloseEvents is IPartiesEvents {
	event AcceptCancelCloseIntent(uint256 intentId);
	event FillCloseIntent(uint256 intentId, uint256 tradeId, uint256 quantity, uint256 price);
}
