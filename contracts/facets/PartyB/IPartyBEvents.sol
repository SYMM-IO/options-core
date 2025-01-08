// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../../storages/IntentStorage.sol";
import "../../interfaces/IPartiesEvents.sol";

interface IPartyBEvents is IPartiesEvents {
    event AcceptCancelOpenIntent(uint256 intentId);
    event AcceptCancelCloseIntent(uint256 intentId);
    event LockOpenIntent(address partyB, uint256 intentId);
    event UnlockOpenIntent(address partyB, uint256 intentId);
    event FillOpenIntent(
        uint256 intentId,
        uint256 tradeId,
        address partyA,
        address partyB,
        uint256 quantity,
        uint256 price
    );
    event FillCloseIntent(
        uint256 intentId,
        uint256 tradeId,
        address partyA,
        address partyB,
        uint256 quantity,
        uint256 price
    );
}
