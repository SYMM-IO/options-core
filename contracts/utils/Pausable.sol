// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "../storages/AppStorage.sol";

abstract contract Pausable {
    modifier whenNotGlobalPaused() {
        require(!AppStorage.layout().globalPaused, "Pausable: Global paused");
        _;
    }

    modifier whenNotDepositingPaused() {
        require(!AppStorage.layout().globalPaused, "Pausable: Global paused");
        require(
            !AppStorage.layout().depositingPaused,
            "Pausable: Depositing paused"
        );
        _;
    }

    modifier whenNotWithdrawingPaused() {
        require(
            !AppStorage.layout().globalPaused,
            "Pausable: Depositing paused"
        );
        require(
            !AppStorage.layout().withdrawingPaused,
            "Pausable: Withdrawing paused"
        );
        _;
    }

    modifier whenNotPartyAActionsPaused() {
        require(!AppStorage.layout().globalPaused, "Pausable: Global paused");
        require(
            !AppStorage.layout().partyAActionsPaused,
            "Pausable: PartyA actions paused"
        );
        _;
    }

    modifier whenNotPartyBActionsPaused() {
        require(!AppStorage.layout().globalPaused, "Pausable: Global paused");
        require(
            !AppStorage.layout().partyBActionsPaused,
            "Pausable: PartyB actions paused"
        );
        _;
    }

    modifier whenNotLiquidationPaused() {
        require(!AppStorage.layout().globalPaused, "Pausable: Global paused");
        require(
            !AppStorage.layout().liquidatingPaused,
            "Pausable: Liquidating paused"
        );
        _;
    }
}
