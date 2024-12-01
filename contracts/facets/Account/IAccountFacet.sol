// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IAccountEvents.sol";

interface IAccountFacet is IAccountEvents {
    function deposit(uint256 amount) external;

    function depositFor(address user, uint256 amount) external;

    function withdraw(uint256 amount, address to) external;

    function claimWithdraw(uint256 id) external;

    function cancelWithdraw(uint256 id) external;
}
