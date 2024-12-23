// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./ILiquidationEvents.sol";
import "../../storages/AppStorage.sol";

interface ILiquidationFacet is ILiquidationEvents {
    function liquidate(
        address partyB,
        LiquidationSig memory liquidationSig
    ) external;

    function setSymbolsPrice(
        address partyA,
        LiquidationSig memory liquidationSig
    ) external;

    function liquidateOpenIntents(
        address partyB,
        uint256[] memory openIntentIds
    ) external;

    function liquidateTrades(
        address partyB,
        uint256[] memory tradeIds
    ) external;

    function settleLiquidation(
        address partyB,
        address[] memory partyAs
    ) external;
}
