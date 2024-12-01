// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

interface IAccountEvents {
    event Deposit(
        address sender,
        address user,
        uint256 amount,
        uint256 newBalance
    );
    event InitWithdraw(
        address user,
        address to,
        uint256 amount,
        uint256 newBalance
    );
    event ClaimWithdraw(uint256 id);
    event CancelWithdraw(uint256 id, uint256 newBalance);
}
