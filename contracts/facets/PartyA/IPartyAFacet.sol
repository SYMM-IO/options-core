// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./IPartyAEvents.sol";
interface IPartyAFacet is IPartyAEvents {
    function sendOpenIntent(
        address[] calldata partyBsWhiteList,
        uint256 symbolId,
        uint256 price,
        uint256 quantity,
        uint256 strikePrice,
        uint256 expirationTimestamp,
        ExerciseFee memory exerciseFee,
        uint256 deadline,
        address affiliate
    ) external returns (uint256);

    function expireOpenIntent(uint256[] memory expiredIntentIds) external;
    function expireCloseIntent(uint256[] memory expiredIntentIds) external;

    function cancelOpenIntent(uint256[] memory intentIds) external;
    function cancelCloseIntent(uint256[] memory intentIds) external;

    function sendCloseIntent(
        uint256 tradeId,
        uint256 price,
        uint256 quantity,
        uint256 deadline
    ) external;
}
