// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyAOpenEvents.sol";

interface IPartyAOpenFacet is IPartyAOpenEvents {
    function sendOpenIntent(
        address[] calldata partyBsWhiteList,
        uint256 symbolId,
        uint256 price,
        uint256 quantity,
        uint256 strikePrice,
        uint256 expirationTimestamp,
        uint256 penalty,
        ExerciseFee memory exerciseFee,
        uint256 deadline,
        address feeToken,
        address affiliate,
        bytes memory userData
    ) external returns (uint256);

    function expireOpenIntent(uint256[] memory expiredIntentIds) external;

    function cancelOpenIntent(uint256[] memory intentIds) external;
}
