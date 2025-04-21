// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { MarginType } from "../../libraries/LibScheduledReleaseBalance.sol";

interface IPartyBOpenEvents is IPartiesEvents {
	event AcceptCancelOpenIntent(uint256 intentId);
	event LockOpenIntent(uint256 intentId, address partyB);
	event UnlockOpenIntent(uint256 intentId);
	event FillOpenIntent(uint256 intentId, uint256 tradeId, uint256 quantity, uint256 price, MarginType marginType);
}
