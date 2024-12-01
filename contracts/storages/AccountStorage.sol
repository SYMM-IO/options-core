// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

struct Withdraw {
    uint256 id;
    uint256 amount;
    address user;
    address to;
    uint256 timestamp;
    WithdrawStatus status;
}

enum WithdrawStatus {
    INITIATED,
    CANCELED,
    COMPLETED
}

library AccountStorage {
    bytes32 internal constant ACCOUNT_STORAGE_SLOT =
        keccak256("diamond.standard.storage.account");

    struct Layout {
        mapping(address => uint256) balances;
        mapping(address => uint256) lockedBalances;
        mapping(address => bool) suspendedAddresses;
        /////////////////////////////////////////////////////////
        mapping(uint256 => Withdraw) withdraws;
        mapping(address => uint256[]) withdrawIds;
        uint256 lastWithdrawId;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = ACCOUNT_STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
