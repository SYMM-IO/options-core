// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.19;

import { IPartiesEvents } from "../../interfaces/IPartiesEvents.sol";
import { IntentStatus } from "../../storages/IntentStorage.sol";

interface IPartyAOpenEvents is IPartiesEvents {
	event CancelOpenIntent(address partyA, address partyB, IntentStatus status, uint256 intentId);
}
